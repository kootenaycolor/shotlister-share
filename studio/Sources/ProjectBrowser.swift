import SwiftUI
import AppKit

/// Choosing a project.
///
/// Drawn as a sheet on the one window rather than as a second window, which is
/// a small departure from the checklist's wording and a deliberate one: this app
/// is single-window, and opening a project *replaces what this window is looking
/// at*. A sheet says that; a separate window would imply the two could sit side
/// by side, which they cannot. It also photographs, which a second window makes
/// needlessly ambiguous for the checking harness.
struct ProjectBrowser: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    /// **One list, whatever it is made of.** See `Film`.
    @State private var films: [Film] = []
    /// Each film's Notion icon, by name in lower case. See `look`.
    @State private var marks: [String: Console.Mark] = [:]
    @State private var hovering: Film.ID?
    /// Which one is coming down, if any. One at a time; this is his own short
    /// list of films, not a download manager.
    @State private var fetching: Film.ID?
    @State private var restoring: String?
    @State private var trouble: String?
    /// **The bin.** Films he has finished with, kept whole and out of the way.
    /// See `Archive`.
    @State private var archived: [Film] = []
    /// Shut, because the whole point of archiving is a shorter list. **Open in
    /// a checking run**, so the one screen that cannot be photographed as a
    /// sheet at least gets photographed showing its new half.
    @State private var binOpen = Launch.checking
    /// A film being archived or deleted. Both talk to the relay first, and both
    /// have to stop him clicking anything else while they do — a second one
    /// starting mid-flight is how a folder gets moved out from under a delete.
    @State private var busy: Film.ID?
    /// What the last thing that finished actually did. One line, gone on the
    /// next thing he does. `trouble` is its unhappy twin.
    @State private var note: String?
    /// **How far a long one has got** — checking a film's pictures against the
    /// relay before an offload, or bringing them back before it opens. Drawn
    /// under the film's name as a count, because three hundred pictures is a
    /// wait worth measuring and a spinner alone says nothing about how long.
    @State private var stage: Stage?

    struct Stage {
        var what: String
        var done: Int
        var total: Int
    }

    private var dark: Bool { scheme == .dark }

    /// **A film, wherever it happens to live.**
    ///
    /// His ruling, 2026-08-31, looking at a footer with three "open" verbs on
    /// it: *"why can't the projects be centralized all on relay, that should be
    /// the default? and we don't need to know it's from relay? Like a normal
    /// app right?"*
    ///
    /// He is right, and the old screen had it backwards: it asked *where is the
    /// film coming from* — a question about transport, which is the app's
    /// problem — before it would show him anything. Now there is one list of
    /// his films and clicking one opens it. A film this Mac does not have yet
    /// is fetched first and then opened, on the same click.
    ///
    /// The one thing still worth drawing is whether it is here yet, because a
    /// two-second wait with no explanation is worse than a small cloud. That is
    /// how Music and Photos do it, and it is not a decision he has to make.
    struct Film: Identifiable, Hashable {
        var id: String { onDisk?.path ?? "relay:\(project ?? name)" }
        var name: String
        /// Nil until this Mac has it.
        var onDisk: URL?
        /// Its identity on the relay, when it has one.
        var project: String?
        var edited: Date?
        /// **On this Mac, with its pictures in the cloud only** — offloaded.
        /// The list is here and opens; the pictures come down first. See
        /// `shared/Offload.swift`.
        var inCloud = false
        var here: Bool { onDisk != nil }
    }

    var body: some View {
        // The one anatomy at the standard width; this sheet already had the
        // rule's footer — New Project and Open Other… far left, Done right.
        Sheet(title: "Projects", subtitle: trouble ?? note ?? "",
              width: .standard, height: 440, scrolls: false) {
            if films.isEmpty {
                EmptyState(title: "No projects yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(films, content: row)
                        binSection
                    }
                    .padding(.vertical, 6)
                }
            }
        } leading: {
            Button("New Project") { makeOne() }
            Button("Open Other…") { openElsewhere() }
            // **"Open from relay…" used to sit here and is gone.** Fetching a
            // film this Mac does not have is what clicking its row does now.
        } trailing: {
            Button("Done") { state.browsing = false }
                .buttonStyle(.primary)
                .keyboardShortcut(.cancelAction)
        }
        .onAppear { note = nil; trouble = nil; look() }
        .sheet(item: Binding(
            get: { restoring.map { Restoring(film: $0) } },
            set: { if $0 == nil { restoring = nil } }
        )) { which in
            RestoreSheet(film: which.film) { restored in
                restoring = nil
                state.open(restored)
                state.browsing = false
            }
        }
    }

    private func row(_ film: Film) -> some View {
        let open = film.onDisk != nil && film.onDisk == state.projectPath
        let coming = fetching == film.id
        // Archiving and deleting both go to the relay first, so both have a
        // wait worth drawing — the same small spinner a film coming down uses.
        let working = busy == film.id ? busy : nil
        let counted = stage.map { "\($0.what) \($0.done) of \($0.total)" }
        return Button {
            choose(film)
        } label: {
            HStack(spacing: 10) {
                // **Each film wears its own mark here too**, the way the shelf
                // on the website does. A film with no Notion icon keeps the
                // stack of frames it always had.
                // **The film's own mark carries a fact**, so it stays; a film
                // with none gets an empty ring rather than a stock glyph.
                Group {
                    if let mark = marks[film.id] {
                        FilmIcon(mark: mark, size: 16)
                    } else {
                        Circle().strokeBorder(Brand.rule2(dark), lineWidth: 1)
                            .frame(width: 14, height: 14)
                    }
                }
                .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(film.name)
                        .sans(13, weight: .medium)
                        .foregroundStyle(Brand.ink(dark))
                    Text((coming || working != nil) ? (counted ?? said(film)) : said(film))
                        .sans(10).foregroundStyle(Brand.ink3(dark))
                }
                Spacer(minLength: 0)
                if coming || working != nil {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                } else if open {
                    Text("Open").fieldLabel(dark)
                        .foregroundStyle(Brand.accent(dark))
                } else if !film.here || film.inCloud {
                    // **Not a button and not a choice.** It says the film is not
                    // on this Mac yet, so that the pause after clicking has a
                    // reason. Music and Photos draw exactly this.
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.ink3(dark))
                        // An offloaded film is here; only its pictures are not.
                        .help("Download")
                }
                // **Only where the pointer is.** A row of bins down the list is
                // a row of invitations to lose an afternoon.
                //
                // **Including the film he has open**, which it used not to be.
                // His report, 2026-09-04: *"currently, in the project that I
                // have open, I can't select the contextual menu to archive,
                // delete, or export a copy. I have to select another project
                // first, then go back and touch it."* Exactly so, and the
                // reason was a real one wearing far too big a coat: archiving
                // and deleting move a folder the engine is reading, so the old
                // rule hid the *whole menu* rather than solve it. Taking a copy
                // of the film you are working on is the most ordinary thing
                // here and it was the thing most in the way. See `letGoOf`.
                if hovering == film.id, !coming, working == nil {
                    Menu {
                        if let url = film.onDisk {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            // **The one thing in the app that carries the
                            // photographs.** See `Copies`.
                            Button("Export a copy…") { copy(url) }
                        }
                        // **Going back in time, next to the film itself.** It
                        // lived in a separate program in his Developer folder,
                        // which meant leaving the app to reach yesterday's
                        // version of his own work.
                        if !Backups.snapshots(of: film.name).isEmpty {
                            Button("Restore an earlier version…") { restoring = film.name }
                        }
                        if let url = film.onDisk {
                            Divider()
                            // **Where the pictures live**, his ask of
                            // 2026-09-29: on this Mac, or in the cloud only.
                            // Never for the film he has open — its window is
                            // drawing them, and its next sync would fetch
                            // them straight back.
                            if film.inCloud {
                                Button("Download") { bringBack(film, thenOpen: false) }
                            } else {
                                Button("Offload…") { offload(url, called: film.name) }
                                    .disabled(open)
                            }
                            // **Three verbs now, and they are three different
                            // things.** His ruling, 2026-09-04: archiving takes
                            // a finished film off the list and keeps it whole;
                            // a copy can be taken at any time and has nothing
                            // to do with archiving; deleting is deleting, and
                            // is the only one that asks first.
                            // **A project's film: the project's own Archive and
                            // Delete** (stage 5 step 4), in Projects Console,
                            // behind its previews and confirmations. A film
                            // that is no project's keeps Studio's own.
                            if let card = ProjectCards.shared.card(film: film.project) {
                                Button("Archive…") { askConsole(card, "archive", called: film.name) }
                                Button("Delete…") { askConsole(card, "delete", called: film.name) }
                            } else {
                                Button("Archive") { archive(url, called: film.name) }
                                Button("Delete…") { remove(url, called: film.name, inCloud: film.inCloud) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11))
                            .foregroundStyle(Brand.ink3(dark))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .frame(width: 26)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(hovering == film.id ? Brand.rowHover(dark) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(fetching != nil || busy != nil)
        .onHover { hovering = $0 ? film.id : (hovering == film.id ? nil : hovering) }
    }

    /// **One click, whatever it takes.** A film that is here opens. A film that
    /// is only on the relay is fetched and then opens — same click, and the
    /// difference is the app's business rather than his.
    private func choose(_ film: Film) {
        // **In the cloud: the pictures first, then the film** — the same one
        // click as a film that is not here at all.
        if film.inCloud, !InUse.same(film.onDisk, state.projectPath) {
            bringBack(film, thenOpen: true)
            return
        }
        if let url = film.onDisk {
            state.open(url)
            state.browsing = false
            return
        }
        guard let project = film.project else { return }
        // **The disk, not the list, decides.** The list is drawn when this
        // screen opens and not again while it is up, so a film whose folder
        // was mid-move at that moment — iCloud rearranging, another app
        // copying it out — is filed as server-only and stays that way. The
        // click then tried to fetch a fresh copy over the folder that had
        // since come back, and refused: *"Call Her Back.shotlist is already
        // here. Open it and sync instead."* His report, 2026-09-15: *"It
        // should just always open when I click it."* So look again before
        // fetching, and open what is there.
        if let already = Projects.all().first(where: { url in
            Relay.projectId(at: url) == project
                || url.deletingPathExtension().lastPathComponent
                    .caseInsensitiveCompare(film.name) == .orderedSame
        }) {
            state.open(already)
            state.browsing = false
            return
        }
        fetching = film.id
        trouble = nil
        Task { @MainActor in
            defer { fetching = nil }
            do {
                let arrived = try await Relay.clone(
                    Relay.Film(project: project, title: film.name, logs: 0, bytes: 0),
                    into: Projects.home())
                state.open(arrived)
                state.browsing = false
            } catch Relay.Trouble.alreadyHere(let name) {
                // The fetch found a folder the list did not. It is his film;
                // open it rather than tell him it exists.
                let there = Projects.home().appending(path: name)
                state.open(there)
                state.browsing = false
            } catch {
                trouble = error.localizedDescription
            }
        }
    }

    /// Everything he has, from both places, as one list.
    ///
    /// The films on disk are drawn immediately — they are a directory read —
    /// and the relay's are folded in when its answer arrives, so the screen is
    /// never waiting on the network to show him what is already here.
    private func look() {
        // **The icons, once.** Read here rather than per row, and from the
        // films themselves: since 2026-09-11 a film carries its own icon and
        // colour, written on the outside of the package so a row can be drawn
        // without opening the document.
        //
        // **His Projects Console is the fallback, not the source.** It is one
        // file on this Mac that a different app writes, and a Mac without it
        // used to mean every film here drew blank — which was the whole fault.
        // It still answers for a film that has not been opened by this build
        // yet, and for nothing else.
        let fromConsole = Dictionary(
            Console.projects().compactMap { one -> (String, Console.Mark)? in
                guard let mark = one.mark else { return nil }
                return (one.name.lowercased(), mark)
            },
            uniquingKeysWith: { first, _ in first })
        // **The bin, from disk, every time.** It is a directory read of a folder
        // with a handful of things in it, and it has to be re-read here rather
        // than kept: archiving and deleting both change it, and a list held in
        // one place and changed in another is the drift this app is built to
        // avoid.
        archived = Archive.all().map { url in
            Film(name: url.deletingPathExtension().lastPathComponent,
                 onDisk: url,
                 project: Relay.projectId(at: url),
                 edited: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                     .contentModificationDate)
        }
        films = Projects.all().filter { !ProjectCards.shared.closed(at: $0) }.map { url in
            Film(name: url.deletingPathExtension().lastPathComponent,
                 onDisk: url,
                 project: Relay.projectId(at: url),
                 edited: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                     .contentModificationDate,
                 inCloud: Offload.inCloud(url))
        }
        marks = Dictionary(
            (films + archived).compactMap { film -> (String, Console.Mark)? in
                let own = film.onDisk.flatMap { Marks.inPackage(at: $0) }
                guard let mark = own ?? fromConsole[film.name.lowercased()] else { return nil }
                return (film.id, mark)
            },
            uniquingKeysWith: { first, _ in first })
        guard Relay.ready else { return }
        // What the relay said last time, drawn at once. The network answer
        // replaces it a moment later; without this the list flickers into
        // completeness every time the screen is opened.
        if let already = Relay.knownFilms { fold(already) }
        Task { @MainActor in
            guard let there = try? await Relay.films() else { return }
            // **Do here what was done elsewhere**, then read the disk again:
            // a film archived on the phone is in the bin by the time the
            // list draws.
            let followed = await state.follow(listing: there)
            if let last = followed.last {
                note = last
                look(again: true)
            }
            fold(there)
        }
    }

    /// The disk half of `look`, after `follow` has moved things.
    private func look(again: Bool) {
        archived = Archive.all().map { url in
            Film(name: url.deletingPathExtension().lastPathComponent,
                 onDisk: url,
                 project: Relay.projectId(at: url),
                 edited: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                     .contentModificationDate)
        }
        films = Projects.all().filter { !ProjectCards.shared.closed(at: $0) }.map { url in
            Film(name: url.deletingPathExtension().lastPathComponent,
                 onDisk: url,
                 project: Relay.projectId(at: url),
                 edited: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                     .contentModificationDate,
                 inCloud: Offload.inCloud(url))
        }
    }

    /// Folds the relay's films into the list, adding only the ones this Mac has
    /// never had.
    private func fold(_ there: [Relay.Film]) {
        var merged = films
        for remote in there {
            // A note, not a film: nothing to fetch.
            if remote.gone != nil { continue }
            // Matched on identity, not name: a film can be renamed on one
            // device and the relay still knows it is the same film.
            let known = merged.contains {
                $0.project == remote.project
                    || $0.name.caseInsensitiveCompare(remote.title) == .orderedSame
            }
            // **A film in the bin is not missing.** Archiving takes it off the
            // relay, so this should not fire — but a second Mac that has not
            // heard yet can put it back up, and offering to fetch a film he has
            // just archived, into the list he archived it out of, would be the
            // old *deleted it and it came back* fault wearing a new coat.
            let inTheBin = archived.contains {
                $0.project == remote.project
                    || $0.name.caseInsensitiveCompare(remote.title) == .orderedSame
            }
            if inTheBin { continue }
            // A closed project's shot list stays off the list (2026-10-16).
            if ProjectCards.shared.closed(film: remote.project) { continue }
            if !known {
                let one = Film(name: remote.title, onDisk: nil,
                               project: remote.project, edited: nil)
                // **A film he has never had here still wears its own icon**,
                // because the relay keeps its manifest and the mark is written
                // there beside the title.
                if let mark = remote.mark { marks[one.id] = mark }
                merged.append(one)
            }
        }
        films = merged.sorted {
            ($0.edited ?? .distantPast) > ($1.edited ?? .distantPast)
        }
    }

    /// What the row says under the name.
    private func said(_ film: Film) -> String {
        // **One name for "not on this Mac"**, whether the film was never here
        // or its pictures were offloaded: his word for both is the cloud.
        guard film.here, !film.inCloud else { return "In the Cloud" }
        guard let when = film.edited else { return "—" }
        let shape = RelativeDateTimeFormatter()
        shape.unitsStyle = .full
        return "Edited " + shape.localizedString(for: when, relativeTo: Date())
    }

    // ---- the bin -----------------------------------------------------------

    /// **Films he has finished with**, under the live ones and shut by default.
    ///
    /// A row of its own rather than a second screen: the whole point of
    /// archiving is that the list gets shorter, and a bin behind a button in
    /// the footer is a bin nobody opens. One line at the foot costs nothing and
    /// says the films are still there.
    @ViewBuilder private var binSection: some View {
        if !archived.isEmpty {
            Divider().overlay(Brand.rule(dark)).padding(.top, 4)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { binOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: binOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.ink3(dark))
                        .frame(width: 18)
                    Text("Archived").sans(13, weight: .medium)
                        .foregroundStyle(Brand.ink2(dark))
                    Spacer(minLength: 0)
                    // A count is a count.
                    Text(archived.count == 1 ? "1 film" : "\(archived.count) films")
                        .sans(10).foregroundStyle(Brand.ink3(dark))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            if binOpen {
                ForEach(archived, content: archivedRow)
            }
        }
    }

    /// **One archived film. Clicking it takes it out of the bin and opens it.**
    ///
    /// Not "opens it where it is". A film opened out of the bin would sync
    /// itself straight back onto the relay on the first edit and quietly undo
    /// the archiving, with nothing on screen to say so. One click that means
    /// one thing is worth more than a peek.
    private func archivedRow(_ film: Film) -> some View {
        let working = busy == film.id
        return Button {
            if let url = film.onDisk { unarchive(url, called: film.name) }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let mark = marks[film.id] {
                        FilmIcon(mark: mark, size: 16).opacity(0.6)
                    } else {
                        Circle().strokeBorder(Brand.rule2(dark), lineWidth: 1)
                            .frame(width: 14, height: 14)
                    }
                }
                .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(film.name).sans(13, weight: .medium)
                        .foregroundStyle(Brand.ink2(dark))
                    Text(said(film)).sans(10).foregroundStyle(Brand.ink3(dark))
                }
                Spacer(minLength: 0)
                if working {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                } else if hovering == film.id {
                    Text("Unarchive").fieldLabel(dark)
                    Menu {
                        if let url = film.onDisk {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            Button("Export a copy…") { copy(url) }
                            Divider()
                            if let card = ProjectCards.shared.card(film: film.project) {
                                Button("Delete…") { askConsole(card, "delete", called: film.name) }
                            } else {
                                Button("Delete…") { remove(url, called: film.name) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11))
                            .foregroundStyle(Brand.ink3(dark))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .frame(width: 26)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(hovering == film.id ? Brand.rowHover(dark) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(fetching != nil || busy != nil)
        .onHover { hovering = $0 ? film.id : (hovering == film.id ? nil : hovering) }
    }

    // ---- the three verbs ---------------------------------------------------

    /// **Archiving: this Mac keeps everything, the relay keeps nothing.**
    ///
    /// His decision, 2026-09-04, asked how far an archive should reach: it goes
    /// quiet everywhere — off the relay, so off his iPhone and out of anybody's
    /// crew link — and un-archiving puts it back.
    ///
    /// **The order is the safety.** Fetch anything the relay has that this Mac
    /// does not, *then* take the film off the relay, *then* move the folder.
    /// Two of his own films are already known to differ in that direction — a
    /// picture that reached the relay from the phone and never reached here —
    /// so doing it the other way round would destroy the only copy. Any step
    /// failing leaves the film exactly where it was, still on the list.
    private func archive(_ url: URL, called name: String) {
        let id = url.path
        busy = id
        trouble = nil
        note = nil
        Task { @MainActor in
            defer { busy = nil }
            do {
                let brought = try await Relay.pullEverything(at: url)
                try await Relay.removeFilm(at: url, fate: .archived)
                // **After the relay, before the folder moves.** A relay that
                // cannot be reached changes nothing at all, which is the whole
                // reason the order is this way round; letting go of the film
                // any earlier would swap what he is looking at and then fail.
                guard state.letGoOf(url) else {
                    trouble = "Couldn't archive “\(name)”"
                    return
                }
                _ = try Archive.put(url)
                note = "Archived \(name)"
                look()
            } catch {
                trouble = error.localizedDescription
            }
        }
    }

    /// **The project's Archive or Delete, in Projects Console** (stage 5
    /// step 4). The console shows what will happen and asks; nothing happens
    /// here.
    private func askConsole(_ card: ProjectCards.Card, _ action: String, called name: String) {
        trouble = nil
        note = action == "archive" ? "Archive \(name) in Projects Console" : "Delete \(name) in Projects Console"
        Console.openProject(page: card.consolePage, action: action)
    }

    /// **Out of the bin, and open.**
    ///
    /// Nothing has to push it back to the relay: the relay has nothing under
    /// its name any more, so the film's own next sync finds every log and every
    /// picture missing there and sends the lot up.
    ///
    /// **Since 2026-09-16 the relay is told first** — it keeps a note that the
    /// film was archived, and a sync reads that note before sending anything;
    /// left standing, it would bin the film again the moment it opened.
    private func unarchive(_ url: URL, called name: String) {
        busy = url.path
        trouble = nil
        note = nil
        Task { @MainActor in
            defer { busy = nil }
            do {
                let back = try Archive.back(url)
                await Relay.putBack(at: back)
                state.open(back)
                state.browsing = false
            } catch {
                trouble = "Couldn't restore “\(name)”"
            }
        }
    }

    /// **A copy of the whole film, as one file.** See `Copies`.
    ///
    /// It asks the relay for anything this Mac is missing first, because *"with
    /// everything you'd ever need to restore it"* was the whole of his ask and
    /// a copy short of two photographs is not that. If the relay cannot be
    /// reached the copy is still written — what is here is worth having — and
    /// the header says the pictures may not all be in it.
    private func copy(_ url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Copies.suggestedName(for: url)
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        // **A film in the bin needs nothing fetching.** Archiving already
        // brought everything down before it took the film off the relay, and
        // asking for a film that is deliberately not there comes back 404 —
        // which would report *the relay could not be reached* over a copy that
        // is in fact complete.
        let inTheBin = url.deletingLastPathComponent().lastPathComponent == Archive.folderName

        busy = url.path
        trouble = nil
        note = nil
        Task { @MainActor in
            var everything = true
            if !inTheBin {
                do { _ = try await Relay.pullEverything(at: url) } catch { everything = false }
            }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Copies.write(url, to: destination)
                }.value
                busy = nil
                // The header is 520 points wide. A warning that clips is not a
                // warning, so this one is short and the missing half is the
                // one thing it has to say.
                note = everything
                    ? "Exported \(name)"
                    : "Exported \(name). Some pictures missing."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                busy = nil
                trouble = error.localizedDescription
            }
        }
    }

    /// **Deleting, behind a warning.** His words: *"if you actually want to
    /// delete something you can delete with a warning."*
    ///
    /// The Trash is what keeps this half-reversible on the Mac, and the Finder
    /// already knows how to give a folder back. **The relay is the half that is
    /// not reversible**, which is exactly why the warning says so: taking a
    /// film off the relay takes it off his iPhone and out of anybody's crew
    /// link, and none of that comes back out of the Trash.
    ///
    /// **The film he has open can be deleted too.** `letGoOf` moves the app to
    /// another film first, so the engine is never reading a folder that is on
    /// its way to the Trash.
    private func remove(_ url: URL, called name: String, inCloud: Bool = false) {
        let ask = NSAlert()
        ask.messageText = "Delete “\(name)”?"
        // A sentence, on purpose: this is what a delete will cost, which is one
        // of the four things a sentence is still allowed to say. The second half
        // is the part he cannot see from here and cannot undo.
        //
        // **An offloaded film's photographs are not in the copy here** — the
        // Trash cannot give back what only the relay holds, so it says so.
        ask.informativeText = inCloud
            ? "Deleted from the relay, the iPhone and crew links."
            : "Moves to Trash. Deleted from the relay."
        ask.alertStyle = .warning
        ask.addButton(withTitle: "Delete")
        ask.addButton(withTitle: "Cancel")
        // **Cancel is what Return does**, not Delete. The default button on an
        // alert is the one a stray keypress finds.
        ask.buttons.first?.keyEquivalent = ""
        ask.buttons.last?.keyEquivalent = "\r"
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        busy = url.path
        trouble = nil
        note = nil
        Task { @MainActor in
            defer { busy = nil }
            // **The relay first, and its failure is fatal to the whole thing.**
            // A film trashed here but still on the relay is the exact fault he
            // reported: it comes back on the next click, and he has no way to
            // tell that is what happened.
            do {
                try await Relay.removeFilm(at: url, fate: .deleted)
            } catch {
                trouble = error.localizedDescription
                return
            }
            guard state.letGoOf(url) else {
                trouble = "\(name) is off your relay, but the app could not let go of it."
                return
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                note = "Deleted \(name)"
                look()
            } catch {
                trouble = "\(name) is off your relay, but its folder could not be moved to the Trash."
                look()
            }
        }
    }

    // ---- where the pictures live ------------------------------------------

    /// **Offloading: the relay keeps the pictures, this Mac keeps the list.**
    /// His ask, 2026-09-29. What goes and why is in `shared/Offload.swift`.
    ///
    /// **Asked first, checked second, moved last.** The question says what it
    /// costs; the check asks the relay about every log and every picture and
    /// refuses with one line if it is short of anything; only then do the
    /// pictures go to the Trash. Any refusal leaves the film exactly as it was.
    ///
    /// **Never the film he has open, in this window or another.** The menu
    /// greys it out here; `InUse` answers for the other windows, and is asked
    /// again after the check, because the check takes long enough for him to
    /// open the film somewhere else meanwhile.
    private func offload(_ url: URL, called name: String) {
        guard !InUse.same(url, state.projectPath) else { return }
        let weight = Offloading.said(Offload.bytes(at: url))
        let ask = NSAlert()
        ask.messageText = "Offload “\(name)”?"
        // What it costs, which is what a sentence is still allowed to say:
        // how much leaves this Mac, where it goes, and how it comes back.
        ask.informativeText = "\(weight) of pictures and clips move to Trash. Pictures stay on the relay."
        ask.addButton(withTitle: "Offload")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        busy = url.path
        trouble = nil
        note = nil
        Task { @MainActor in
            defer { busy = nil; stage = nil }
            do {
                let gone = try await Offloading.run(url, state: state) { done, total in
                    stage = Stage(what: "Checking", done: done, total: total)
                }
                note = "Offloaded \(name)"
                look()
            } catch {
                trouble = error.localizedDescription
            }
        }
    }

    /// **The pictures, back from the relay** — and then the film, when it was
    /// a click on the row that asked.
    ///
    /// **With no connection, he decides.** The list is on this Mac and opens
    /// without the pictures; the app's own sync fetches them the moment the
    /// relay answers. So a failure asks rather than refuses — a shot list on
    /// set with no signal is still a shot list. A film taken off the relay
    /// elsewhere is the exception: that is `follow`'s to handle, not an open.
    private func bringBack(_ film: Film, thenOpen: Bool) {
        guard let url = film.onDisk else { return }
        fetching = film.id
        trouble = nil
        note = nil
        Task { @MainActor in
            defer { fetching = nil; stage = nil }
            do {
                try await Relay.bringBack(at: url) { done, total in
                    stage = Stage(what: "Downloading", done: done, total: total)
                }
                if thenOpen {
                    state.open(url)
                    state.browsing = false
                } else {
                    note = "Downloaded \(film.name)"
                    look()
                }
            } catch {
                if case RelayCarrier.Trouble.gone = error {
                    trouble = error.localizedDescription
                    return
                }
                guard thenOpen else {
                    trouble = error.localizedDescription
                    return
                }
                let ask = NSAlert()
                ask.messageText = "Open “\(film.name)” without its pictures?"
                // Why it could not happen, in the carrier's own words — the
                // one thing a label cannot say.
                ask.informativeText = error.localizedDescription
                ask.addButton(withTitle: "Open")
                ask.addButton(withTitle: "Cancel")
                guard ask.runModal() == .alertFirstButtonReturn else {
                    trouble = error.localizedDescription
                    return
                }
                state.open(url)
                state.browsing = false
            }
        }
    }

    private func makeOne() {
        state.browsing = false
        state.newProject()
    }

    /// For a project that lives somewhere else — an old-app one in Documents,
    /// or a copy somebody sent. Nothing is moved; it is opened where it is.
    ///
    /// **Unless it is one of ours in a zip**, in which case it is unpacked
    /// beside the films first and opened from there. That is the other half of
    /// *Export a Copy…*: a copy that can be written and never opened again is a
    /// copy he has to trust rather than one he can check.
    private func openElsewhere() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Projects.home()
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let picked = panel.url else { return }

        if picked.pathExtension.lowercased() == "zip" {
            do {
                let film = try Copies.open(picked, into: Projects.home())
                state.open(film)
                state.browsing = false
                look()
            } catch {
                trouble = error.localizedDescription
            }
            return
        }

        state.open(picked)
        state.browsing = false
    }
}

/// Which film's history is being looked through. A type of its own only so the
/// sheet can be driven by `item:` rather than a bool beside a string, which is
/// two things that can disagree.
private struct Restoring: Identifiable {
    var film: String
    var id: String { film }
}

/// **Going back to how a film was on a particular day.**
///
/// His ask, 2026-08-31: *"Restore from backup should be an option."* It was a
/// separate program in his Developer folder.
///
/// **Nothing here can overwrite the film he is working in.** The restored copy
/// arrives beside it with the date in its name and opens as a film of its own,
/// so the two can be looked at one after the other. The point of a backup is to
/// be sure.
private struct RestoreSheet: View {
    var film: String
    var onRestored: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var snapshots: [Backups.Snapshot] = []
    @State private var working = false
    @State private var trouble: String?

    var body: some View {
        Sheet(title: "Earlier Versions of \(film)", width: .narrow, height: 340, scrolls: false) {
            if snapshots.isEmpty {
                EmptyState(title: "No backups yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshots) { snapshot in
                            Button { restore(snapshot) } label: {
                                HStack {
                                    Text(snapshot.said).sans(Brand.Size.body)
                                        .foregroundStyle(Brand.ink(dark))
                                    Spacer()
                                    Text(ByteCountFormatter.string(
                                        fromByteCount: Int64(snapshot.bytes), countStyle: .file))
                                        .sans(Brand.Size.tiny).foregroundStyle(Brand.ink3(dark))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(working)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        } leading: {
            // The one sentence this screen earns: what picking one will do,
            // because "restore" everywhere else in the world means "over
            // the top of what you have".
            Text("Opens as a copy")
                .sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
        } trailing: {
            if working { ProgressView().controlSize(.small).scaleEffect(0.7) }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(working)
        }
        .onAppear { snapshots = Backups.snapshots(of: film) }
        .alert("Couldn't restore that", isPresented: .constant(trouble != nil)) {
            Button("OK") { trouble = nil }
        } message: {
            Text(trouble ?? "")
        }
    }

    private func restore(_ snapshot: Backups.Snapshot) {
        working = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let back = try Backups.restore(snapshot, beside: Projects.home())
                DispatchQueue.main.async { working = false; onRestored(back) }
            } catch {
                DispatchQueue.main.async { working = false; trouble = error.localizedDescription }
            }
        }
    }
}

/// **The Projects screen, in a window, for checking only.**
///
/// It stays a sheet in the app. That is deliberate and settled — opening a
/// project *replaces what this window is looking at*, and a sheet says so where
/// a second window would imply the two could sit side by side.
///
/// But no sheet in this app can be photographed (Ref 366): while one is up a
/// checking run has no windows at all. So this screen was in the same position
/// the export box was in before 2026-09-02 — every change to it verified by
/// reading a log, never by looking. The export box answered that by becoming a
/// window for real. This one cannot, so it gets a window **only under
/// `--browsebox`**, hosting the same view at the same size.
///
/// **What that does and does not prove.** The rows, the menus, the bin and
/// every word on them are the same view drawn the same way, so it answers every
/// question about the screen's contents. It says nothing about the sheet
/// presentation itself, which is one modifier and has never been the part that
/// breaks.
final class BrowserWindow: NSObject {
    static let shared = BrowserWindow()
    private var window: NSWindow?

    func show(state: ShellState) {
        guard Launch.checking else { return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.identifier = NSUserInterfaceItemIdentifier("projects")
        w.contentView = NSHostingView(rootView: ProjectBrowser(state: state))
        if let main = NSApp.windows.first(where: { $0.isVisible && $0 != w }) {
            main.addChildWindow(w, ordered: .above)
            w.center()
        }
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
