import SwiftUI

/// **The film's name, at the top of every tab** — his pick, 2026-10-09
/// (`design/42-one-home`, option A). It replaces the tab's own name, which
/// the bar already says, so it costs no room; and a tap on it is the film's
/// one menu. The `⋯` menu that held these was on four tabs of the five.
///
/// Sync shows here too, since this is where Sync Now lives: the arrows turn
/// while it runs, and a red dot says the last one failed.
struct FilmTitleButton: View {
    @EnvironmentObject private var session: Session
    @State private var showing = false
    @State private var turn = false

    private var title: String { session.view?.project.shownTitle ?? session.entry.name }

    /// The name's own width, the icon and the arrow, never more than leaves
    /// the bar room for its two buttons.
    private var width: CGFloat {
        let font = UIFont.systemFont(ofSize: Kit.Size.title, weight: .bold)
        let name = (title as NSString).size(withAttributes: [.font: font]).width
        let icon: CGFloat = session.view?.project.mark == nil ? 0 : 29
        return min(ceil(name) + icon + 22, UIScreen.main.bounds.width - 190)
    }

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 7) {
                if let mark = session.view?.project.mark {
                    FilmIcon(mark: mark, size: 17)
                        .frame(width: 22, height: 22)
                }
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if session.syncing {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Style.ink3)
                        .rotationEffect(.degrees(turn ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: turn)
                        .onAppear { turn = true }
                        .onDisappear { turn = false }
                } else if session.syncProblem != nil {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Style.ink3)
                }
            }
            .contentShape(Rectangle())
            // **A width of its own, measured.** A toolbar item is offered
            // almost nothing, and a name that may shrink took nothing: the
            // icon and the arrow with no name between them. Given the room
            // the bar has, it took too much and iOS folded + into •••. So
            // the name is measured, and a long one shrinks to the limit.
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("film.menu")
        .filmSheet(isPresented: $showing)
    }
}

/// The film's menu, from wherever its door is: the name at a tab's root, or
/// the film's card in the Library. Both sit at a tab's root, where dismiss
/// closes the film itself, since nothing is pushed.
private struct FilmSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var projects: Projects
    @EnvironmentObject private var portal: PortalLine
    @Environment(\.dismiss) private var closeFilm

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            FilmSheet { next in
                isPresented = false
                projects.switchTo = next
                // After the sheet has gone: one presentation at a time.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { closeFilm() }
            }
            .environmentObject(session)
            .environmentObject(projects)
            .environmentObject(portal)
            .presentationDetents([.medium, .large])
            .presentationBackground(Style.page)
        }
    }
}

extension View {
    func filmSheet(isPresented: Binding<Bool>) -> some View {
        modifier(FilmSheetPresenter(isPresented: isPresented))
    }
}

/// **The film's one menu**: what it is, whether it is synced, what can be
/// done to it, and the other films. `leave(nil)` goes back to Projects;
/// `leave(film)` opens that one.
struct FilmSheet: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var projects: Projects
    @EnvironmentObject private var portal: PortalLine
    let leave: (Projects.Known?) -> Void

    /// Settings, opened on this project's page.
    @State private var settings = false
    @State private var exporting = false
    @State private var versioning = false
    /// This sheet itself — closed when an old version goes on screen, so the
    /// banner over the shot list is the first thing seen.
    @Environment(\.dismiss) private var closeSheet
    @State private var consoleMissing = false

    private var project: Engine.Project? { session.view?.project }

    /// The record's line under the name — type, status, dates — when the
    /// portal has sent it; else what the film itself knows.
    private var said: String {
        let facts = portal.front?.film.facts ?? []
        if !facts.isEmpty { return facts.joined(separator: " · ") }
        return project?.isCommercial == true ? "Commercial" : "Film"
    }

    private var credits: [(String, String)] {
        guard let project else { return [] }
        var all = [("Director", project.director), ("Producer", project.producer)]
        if project.isCommercial { all += [("Client", project.client), ("Agency", project.agency)] }
        return all.filter { !$0.1.isEmpty }
    }

    /// The films last opened here, this one left out.
    private var others: [Projects.Known] {
        Array(projects.all.filter {
            $0.id != session.entry.id && $0.name.caseInsensitiveCompare(session.entry.name) != .orderedSame
        }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                head
                syncRow
                group {
                    row("Export", "square.and.arrow.up", chevron: true) { exporting = true }
                    Divider().padding(.leading, 46)
                    row("Versions", "clock.arrow.circlepath", chevron: true) { versioning = true }
                        .accessibilityIdentifier("film.versions")
                    Divider().padding(.leading, 46)
                    row("Open in Projects Console", "arrow.up.forward.app") { ConsoleLink.open(session) { consoleMissing = true } }
                    Divider().padding(.leading, 46)
                    // **One Settings screen** (2026-10-15): Film Settings and
                    // App Settings were two rows and two sheets. This opens
                    // Settings already on this project's page.
                    row("Project Settings", "gearshape", chevron: true) { settings = true }
                        .accessibilityIdentifier("film.settings")
                }
                Text("SWITCH PROJECT")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.9)
                    .foregroundStyle(Style.ink3)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                group {
                    ForEach(others) { film in
                        filmRow(film)
                        Divider().padding(.leading, 46)
                    }
                    row("All Projects", "square.grid.2x2", chevron: true) { leave(nil) }
                        .accessibilityIdentifier("film.allprojects")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .alert("Projects Console Not Installed", isPresented: $consoleMissing) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $settings) {
            PhoneSettings(session: session, start: .project)
                .environmentObject(projects)
                .presentationBackground(Style.page)
        }
        .sheet(isPresented: $exporting) {
            ExportSheet().environmentObject(session)
        }
        .sheet(isPresented: $versioning) {
            VersionsView(leave: {
                versioning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { closeSheet() }
            }, open: { made in
                versioning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { leave(made) }
            })
            .environmentObject(session)
            .environmentObject(projects)
        }
    }

    // ---- the parts ----------------------------------------------------------

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Group {
                    if let mark = project?.mark {
                        FilmIcon(mark: mark, size: 26)
                    } else {
                        Image(systemName: "film").font(.system(size: 20))
                    }
                }
                .frame(width: 48, height: 48)
                .background(Style.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(project?.shownTitle ?? session.entry.name)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(2)
                    Text(said)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink3)
                        .lineLimit(2)
                }
            }
            if !credits.isEmpty {
                // One run of text, so a long name wraps instead of being cut.
                credits.enumerated().reduce(Text("")) { line, credit in
                    line
                        + Text(credit.offset == 0 ? "" : "    ")
                        + Text(credit.element.0 + " ").foregroundStyle(Style.ink3)
                        + Text(credit.element.1).foregroundStyle(Color(.label))
                }
                .font(.system(size: 13))
                .lineLimit(3)
            }
            if let logline = portal.front?.film.logline, !logline.isEmpty {
                Text(logline)
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink2)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var syncRow: some View {
        group {
            HStack(spacing: 10) {
                Circle()
                    .fill(session.syncProblem != nil ? Color.red
                          : session.canSync ? Color.green : Style.ink3)
                    .frame(width: 8, height: 8)
                    .frame(width: 24)
                Text(session.syncing ? "Syncing"
                     : session.syncProblem ?? (session.canSync ? SyncHistory.said : "Sync is off"))
                    .font(.system(size: 15))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if session.canSync {
                    Button("Sync Now") { session.syncNow() }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(session.syncing)
                        .accessibilityIdentifier("film.syncnow")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private func group<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(spacing: 0) { rows() }.card(Style.Radius.list)
    }

    private func row(_ title: String, _ symbol: String, chevron: Bool = false,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(title).font(.system(size: 15))
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Style.ink3)
                }
            }
            .foregroundStyle(Color(.label))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filmRow(_ film: Projects.Known) -> some View {
        Button { leave(film) } label: {
            HStack(spacing: 12) {
                Group {
                    if let mark = film.mark {
                        FilmIcon(mark: mark, size: 15)
                    } else {
                        Image(systemName: "film.stack").font(.system(size: 13)).foregroundStyle(Style.ink3)
                    }
                }
                .frame(width: 24)
                Text(film.name).font(.system(size: 15)).lineLimit(1)
                Spacer()
                Text(projects.away.contains(film.id) ? "In the Cloud"
                     : film.lastOpened > .distantPast
                        ? film.lastOpened.formatted(.relative(presentation: .named)) : "")
                    .font(.system(size: 13))
                    .foregroundStyle(Style.ink3)
            }
            .foregroundStyle(Color(.label))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("film.switch")
    }

}
