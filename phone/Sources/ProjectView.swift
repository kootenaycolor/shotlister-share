import SwiftUI

/// A project, open on the phone.
///
/// Four tabs: **Shot list**, **Locations**, **Mood boards**, **Schedule** —
/// the Mac's own four modes, in the Mac's own order.
///
/// They began the other way round, on the reasoning that a phone on a scout is a
/// capture device before it is a reader. His ruling on 2026-08-21 put the shot
/// list first — and once the list is editable rather than only readable, it is
/// the thing the app is *for* rather than one of the things it holds.
struct ProjectView: View {
    let entry: Projects.Known

    @EnvironmentObject private var projects: Projects
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loading = Loading()

    var body: some View {
        Group {
            if let session = loading.session, let frames = loading.frames {
                VStack(spacing: 0) {
                    // **An empty project and an unreadable one look identical**
                    // unless one of them says so. On 2026-08-21 a single field
                    // missing from one photograph emptied every screen in the
                    // app, and it read as lost work.
                    if let why = session.unreadable {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.wouldNotOpen ? "Can't open this project"
                                                          : "Can't read this project")
                                    .font(.footnote.weight(.semibold))
                                Text(why)
                                    .font(.kitLabel)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12))
                    }

                ClashBanner().environmentObject(session)
                // Four pins and the Library (Ref 1541 Stage B).
                FilmTabs()
                .environmentObject(session)
                .environmentObject(frames)
                }
                // **The film's own colour, worn by the whole of it.** The Mac
                // has done this since 2026-09-05 and the website before that;
                // since 2026-09-11 the colour rides with the film itself, so
                // the phone needs nothing of its own to know it — no Projects
                // Console, no login, nothing set up on this device.
                .tint(session.view?.project.mark.map { Color(markHex: $0.colour) }
                      ?? .accentColor)
                // **Archived or deleted on another device while open here.**
                // His ruling 2026-09-16: it becomes archived once synced,
                // not asked about. The film closes and the Projects screen
                // follows the fate once the engine has let go of the folder.
                .onChange(of: session.relayFate) { _, fate in
                    guard let fate else { return }
                    projects.followAfterClose = (entry, fate)
                    dismiss()
                }
                .onChange(of: phase) { _, now in
                    // Going into a pocket is how a phone is put away; it is not
                    // quit, and it may never be woken again.
                    if now != .active {
                        session.flush()
                    } else {
                        // Coming back is the other moment: the watcher is not
                        // running while the app is asleep, so whatever landed
                        // in the meantime is taken in now.
                        session.pullNow()
                        // And the same question asked of the relay, which the
                        // folder cannot answer. Everything moves — the list and
                        // the photographs both, since 2026-09-08.
                        session.syncListQuietly()
                        session.watchTheRelay(waking: true)
                    }
                }
            } else if let failure = loading.failure {
                // **With a way out.** This screen had none, and the Projects
                // list reopened the same film at every launch — so a folder
                // iOS would not hand back was a wall he could not get past
                // (2026-09-16, his report).
                ContentUnavailableView {
                    Label("Couldn't open this project", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Back to Projects") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            loading.open(entry: entry, using: projects)
        }
    }

    @MainActor
    final class Loading: ObservableObject {
        @Published var session: Session?
        @Published var frames: Frames?
        @Published var failure: String?

        func open(entry: Projects.Known, using projects: Projects) {
            guard session == nil, failure == nil else { return }
            guard let folder = projects.resolve(entry) else {
                failure = "iOS wouldn't let the app back into that folder. Open it again from the Projects screen."
                // A remembered folder iOS will not give back is not coming
                // back on its own; off the list, so the list stops offering
                // it and the app stops reopening it at launch.
                projects.forget(entry)
                return
            }
            projects.touch(entry)
            let opened = Session(entry: entry, folder: folder)
            session = opened
            projects.noteConsolePage(opened.view?.project.consolePage, for: entry)
            // Opening a film is when being behind matters most — it is the
            // shot list he is about to read.
            opened.syncListQuietly()
            frames = Frames(engine: opened.engine, folder: folder.url)
        }
    }
}
