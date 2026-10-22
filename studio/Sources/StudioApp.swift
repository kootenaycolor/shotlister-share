import SwiftUI
import AppKit
import ScreenCaptureKit
import QuartzCore
import AVFoundation

/// Registers the process as a real app before the first window exists, rather
/// than from the first view's `onAppear`, which is late enough that the window
/// can be built by a process AppKit does not yet consider an app.
final class Launch: NSObject, NSApplicationDelegate {
    /// True when this launch exists only to check something.
    ///
    /// A checking run must be something Nathaniel cannot notice. He works on the
    /// same Mac these run on, and a check that costs him his place in what he
    /// was doing will rightly get turned off — after which nothing is verified
    /// at all. So a checking launch never becomes a real app: no Dock icon, no
    /// activation, no key window, nothing taken from whatever is in front.
    /// A loud run drives the app the way a person does: frontmost, key
    /// window, real first responder — the path the invisible harness can
    /// never reach. It exists because the quiet lane structurally tests a
    /// fallback, and every bug Nathaniel found lived on the real path.
    ///
    /// **A loud run may only happen on an explicit grant** — his word that
    /// the machine is his to take for the moment (2026-08-17, overnight:
    /// "take full control"). It says LOUD RUN in its output, and it returns
    /// the front to whoever had it when it finishes.
    static var loud: Bool { CommandLine.arguments.contains("--loud") }
    /// A long performance run, which must never fight anybody for the front.
    static var churning: Bool { CommandLine.arguments.contains("--churn") }
    /// **Let clips and gifs move during a checking run.** Off by default: a
    /// photograph of a playing clip is a photograph of whichever frame the
    /// decoder happened to reach, and a check that cannot repeat itself is
    /// worse than no check. On, when the thing being checked *is* the motion.
    static var playing: Bool { CommandLine.arguments.contains("--playing") }

    /// **The frames window, opened with the pen already down.** The arrows
    /// editor is reached by clicking a button in a pop-out, and `--tap` cannot
    /// run alongside `--snapshot` (Ref 369) — so without this the editor could
    /// never be photographed, and a control sitting below the fold or a handle
    /// drawn in the wrong place would ship looking fine.
    static var drawingArrows: Bool { CommandLine.arguments.contains("--drawarrows") }
    /// `--printframe`: the viewer opens on the cursor shot's picture in Print
    /// Frame mode (`PrintFrameEditor`); `--pflayout`, `--pfadd`, `--pfstill`,
    /// `--pfmark` and `--pfnumbers` drive the editor from there.
    static var printFrame: Bool { CommandLine.arguments.contains("--printframe") }

    /// **Another Shotlister, from this one.** `createsNewApplicationInstance`
    /// is the whole of it: without it the Mac simply raises the copy already
    /// running, which is what ⌘N looked like it was doing.
    ///
    /// The new one opens on the project browser rather than on whatever this
    /// one has open — a second window standing on the same project as the first
    /// is a puzzle, not a workspace. `--fresh` is deliberately **not** a
    /// checking flag: it starts a real app, visible, the way he pressed the key
    /// expecting.
    /// **Pull a mode out into its own window** — his ask of 2026-08-23, and
    /// the one idea worth keeping from the "make them all windows" sketch.
    ///
    /// Given a project and a mode, the new instance opens straight onto that
    /// project standing in that mode, so Locations can sit beside the table on
    /// the big monitor. Given neither, it is plain ⌘N and lands on the project
    /// browser, because a second window standing on the same project as the
    /// first is a puzzle rather than a workspace.
    ///
    /// **`--onproject` and `--onmode`, not `--project` and `--place`**, even
    /// though the pairs do the same thing. Those two are *checking* flags: a
    /// run carrying either launches invisibly and exits, which is Ref 93's
    /// lesson and the reason the list exists. These two are the opposite kind
    /// of flag — they exist to start a real window on his screen — so they are
    /// deliberately not on it.
    static func another(on project: URL? = nil, at place: SideTab? = nil) {
        let me = Bundle.main.bundleURL
        let how = NSWorkspace.OpenConfiguration()
        how.createsNewApplicationInstance = true
        if let project, let place {
            how.arguments = ["--onproject", project.path, "--onmode", place.rawValue]
        } else {
            how.arguments = ["--fresh"]
        }
        NSWorkspace.shared.openApplication(at: me, configuration: how) { _, problem in
            guard let problem else { return }
            DispatchQueue.main.async {
                ShellState.shared.say("Could not open another window: \(problem.localizedDescription)")
            }
        }
    }

    static var checking: Bool {
        let args = CommandLine.arguments
        // `--set` is here because it once was not: a run with only `--set`
        // launched as a real app — activated, frontmost, key — and sat open
        // until something killed it. Every flag that exists for checking makes
        // the run a checking run.
        // EVERY flag that exists for checking makes the run a checking run.
        // Twice now a new flag was added without this line and a run launched
        // as a real app — activated, frontmost — and sat open until killed.
        // The modifiers are here too — --cell, --right, --expect and their
        // kin never appear without an action flag in a well-formed run, but a
        // malformed run carrying only a modifier must still be a checking run
        // rather than a real app that sits open on his screen until killed.
        return ["--snapshot", "--spectake", "--drag", "--type", "--hold", "--tap", "--media", "--mediadelete", "--mediashow",
                "--paste", "--set", "--addshot", "--hide", "--show",
                "--addcolumn", "--card", "--ratio", "--ratiomenu", "--notes", "--pin", "--unpin", "--view",
                "--layout",
                "--window",
                "--cell", "--right", "--walk", "--expect",
                "--after", "--tdrag", "--loud",
                "--columns", "--editcolumns", "--archive",
                "--device", "--pull", "--settle", "--sync", "--shrinkclips", "--pictures-waiting", "--copyword", "--autolist", "--relayfilms", "--logaudit", "--stay", "--settings",
                "--filmarchive", "--filmbin", "--browsebox", "--offload", "--download", "--incloud", "--colwidth", "--filmunarchive", "--exportcopy", "--openedcopy", "--addscene", "--addscenedo", "--addsceneagain", "--columnpage", "--scenepage", "--scenefield", "--syncsetup", "--syncsave",
                "--scroll", "--kitmode", "--wheel", "--churn", "--redraws", "--squeeze", "--modes", "--facet", "--find", "--panel", "--list", "--lock",
                "--kind", "--sortby", "--setscript", "--scriptlayout", "--pastesection", "--tie", "--tielines", "--sweep", "--renumber", "--pastescript", "--deletesection", "--sceneafter",
                "--shot", "--shots", "--cells", "--mark", "--range", "--live", "--pick", "--pickday", "--copyto", "--wide",
                // Ref 93, closed 2026-08-21. These eleven put the app into a
                // particular posture and then, on their own, launched it as a
                // *real app* — frontmost, on his screen, sitting there until
                // something killed it. `--place locations --snapshot …` was
                // fine because `--snapshot` is on this list; `--place
                // locations` alone was not.
                "--place", "--tab", "--docstyle", "--docstylesays", "--richsays", "--pagedefault", "--pagedefaultsays", "--boardframes", "--typepanel", "--scene", "--search", "--sidebar",
                "--screen", "--appearance", "--browser", "--editing", "--accent",
                "--project", "--locations", "--addlocation", "--location",
                "--setlocation", "--linkscene", "--homecoming", "--address",
                "--diagramsample", "--diagramtool", "--diagrampick", "--diagrambeat", "--diagramsays",
                "--floorplan", "--scanmode", "--photo", "--openphoto", "--pinviewer", "--dropphoto",
                "--script", "--scriptdo", "--revisions", "--frame", "--frameswindow", "--deleteframes", "--playing",
                "--trimclip", "--trim", "--clipssay",
                "--scriptmerge", "--menu", "--setup", "--setuppick", "--link", "--rename",
                "--wholescript", "--wholescriptwindow", "--another", "--photos", "--removepicked",
                "--filtering", "--master", "--link", "--reference", "--deletecolumn",
                "--addarea", "--movelocation", "--settletimes", "--pickscenes", "--setmode", "--recards", "--reviewdraft", "--pickdraft",
                "--shoot", "--shootmenu", "--moveshoot", "--shootplan", "--filmlink",
                "--pickframe", "--frameguides", "--framemenu",
                "--pickedlocation", "--pickedtime", "--scenetimes",
                "--pinhere", "--deletescene", "--photoshape", "--exportset",
                "--alsoscene", "--sceneorder", "--pickpicture", "--pickpreview", "--layoutall",
                "--addboard", "--board", "--renameboard", "--deleteboard",
                // Mods, 2026-10-17. See `EditReference.swift`.
                "--modson", "--addeditref", "--editreffile", "--editrefsays", "--playeditref", "--editrefat",
                "--editrefsheet", "--editrefbloom", "--editrefplay", "--reducemotion", "--editrefdropping", "--editrefheld",
                "--pinonboard", "--boardssay", "--linkboard", "--unlinkboard",
                "--putpicture", "--pickpictures",
                "--caption", "--tagboard", "--linkhere", "--movepictureto",
                "--crop", "--cropsays",
                "--arrows", "--arrowssays", "--drawarrows", "--arrowline", "--arrowdrag", "--arrowedit", "--arrowslide", "--arrowremember", "--frameswidth",
                "--printframe", "--frameprint", "--pflayout", "--pfadd", "--pfstill", "--pfmark", "--pfnumbers", "--pfremove", "--pfdone",
                "--boardratio", "--dayname", "--daydate", "--dayremove",
                "--daymove", "--dayssay", "--daysheet", "--putday",
                "--calendar", "--month", "--clickdate", "--putdate",
                "--sortdays", "--calendarsays", "--daydots",
                "--synopsis", "--offday", "--synopsissay",
                "--referencessay", "--shutsection",
                "--openstrip", "--mouse", "--shootingorder", "--nudgeshot",
                "--colourterm", "--coloursay", "--setmark", "--marksays",
                "--excellink", "--excelauto", "--excelnow", "--excelmanual", "--excelframes",
                "--settingsend", "--prefs", "--prefsdo",
                "--excelsays", "--exportdays", "--daysections", "--framesize", "--pages", "--exportpdf", "--colwidths",
                "--exportbox", "--tablelayout", "--paper", "--textsize", "--exportcolumns", "--exportpaper", "--exportsetup", "--exportvisit", "--exportnext", "--exportkey", "--exportsave", "--exportdrag", "--stripcheck", "--flat", "--exportdiagram",
                "--drivesync", "--drivesays", "--drivefolder",
                // The Projects Console's doors, 2026-09-15. See `openProject`
                // for `--newfilm`; `--setdirector` and `--filmsays` sit with
                // `--setmark` and `--marksays`.
                "--newfilm", "--setdirector", "--filmsays", "--recordfacts", "--factssays", "--projectcard", "--cardpng",
                // One ID, 2026-10-14. See `cardDoors` and `NewCard.swift`.
                "--cardon", "--cardfetch", "--cardform", "--newcard",
                // Archive done once, 2026-10-05. See `FilmDoor`.
                "--archivefilm", "--unarchivefilm", "--deletefilm", "--holdfilm", "--linkpage", "--specadd",
                // Versions, 2026-09-29. See `Versions.swift`.
                "--versions", "--saveversion", "--lookat", "--bringback", "--goback",
                "--versionssay", "--dailyversion", "--copyversion",
                // The document page by keys alone, 2026-09-30. See `PageKeys.swift`.
                "--pagekeys",
                // Clips that wait for play, 2026-09-30. See `ClipPlay`.
                "--clipswait", "--nopreviewstills", "--clipthumbs"]
            .contains { args.contains($0) }
    }

    /// A shoot day, by the number its band wears — `2` for `Day 2`.
    ///
    /// Days have no name of their own until somebody gives them one and their
    /// ids are the engine's business, so position is the only handle a checking
    /// run can hold. `day_label` derives from position too, so the two agree.
    static func day(_ said: String, _ state: ShellState) -> BoardModel.Lane? {
        state.loadBoard()
        let days = state.stripBoard?.days ?? []
        if let index = Int(said), index >= 1, index <= days.count {
            return days[index - 1]
        }
        return days.first { $0.label.caseInsensitiveCompare(said) == .orderedSame }
    }

    /// What a checking run's ⌘V pastes, instead of reading — or ever
    /// writing — the person's real clipboard.
    static var pasteOverride: String?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // **The references board's arrows, installed before anything is
        // drawn** — Ref 268. It used to be installed when the board appeared,
        // which meant a key pressed before the panel had been drawn landed
        // nowhere; here it cannot be too late for anything. It answers only
        // while the panel is out and standing on References, and reads
        // nothing from a view. See `BoardFocus` for the two homes that were
        // wrong first.
        BoardFocus.install()
        // **Every wall of pictures answers the arrows** — his instruction,
        // 2026-08-24, that a new gallery should inherit these behaviours
        // rather than have them asked for again. One monitor for all of them,
        // installed here for the same reason `BoardFocus` is: a monitor
        // installed when a view appears can be too late for the first key, and
        // two of them race.
        WallKeys.shared.install()
        // The first thing a checking run does is note whose front it might be
        // about to take, because by the watch's first sample the launch
        // lottery may already have run and the answer is gone.
        if Self.checking {
            // **By process, never by name.** His own Shotlister carries the
            // same bundle identifier as a checking copy; asked by name, his
            // app in front looked like the check having taken it — and the
            // "repair" hauled whatever came before to the front over him.
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { victim = front }
        }
        // **One remembered frame, settled before the window is built.**
        //
        // This runs before SwiftUI has made the window, which is the only
        // moment the choice can be made without moving it afterwards — and
        // moving it afterwards was the whole fault. See `settleTheFrame`.
        if !Self.checking { Self.settleTheFrame() }
        // Stays `.regular` even for a check. `.accessory` was the obvious
        // choice and it is wrong: SwiftUI never creates the window for an
        // accessory app, so the process opened nothing and exited instantly
        // with no output at all. What actually took his focus was never the
        // policy — it was calling `activate` and `makeKeyAndOrderFront`, and
        // those are gone.
        NSApp.setActivationPolicy(.regular)
        // Follow the Mac, and say so — this app never picks its own theme.
        // `--appearance` below is a checking tool, not a preference.
        NSApp.appearance = nil
        // The project opens before the first frame, so the window never draws
        // an empty shell and then fills in — which reads as a stall.
        openProject()
        ShellState.shared.restorePanel()
        readFlags()
    }

    /// **The window was being put down twice, on two different monitors.**
    ///
    /// His report, 2026-09-02: *"on startup now the text is all blurry and low
    /// quality"* — and, the same day, the startup freeze. One cause, and this
    /// is it. Traced rather than guessed:
    ///
    /// ```
    /// window before: (29, 60, 1864, 1050)   screen=HP Z24x    scale=1.0
    /// window after : (2148, 174, 1864, 1050) screen=PA32UCDM  scale=2.0
    /// ```
    ///
    /// Two saved frames were fighting. SwiftUI autosaves the main window under
    /// its own identifier, `main`; we then called `setFrameAutosaveName` and
    /// renamed it to `StudioMain` — and **that call does not just rename, it
    /// restores** whatever was saved under the new name. So every launch built
    /// and laid the window out in one place and then hauled it to another,
    /// sometimes to a monitor with a different backing scale.
    ///
    /// That is both faults at once. Text drawn for a 1× screen and then shown
    /// on a 2× one is **blurry**, exactly as he described. And a full resize
    /// and rescale arriving *during* the first layout is the storm the freeze
    /// captures show — the window's own sizing pass restarted underneath
    /// itself, rebuilding the switcher as it went.
    ///
    /// The cure is to have one saved frame, not two. SwiftUI's own is the one
    /// that is set before the window is built, so that is the one to keep;
    /// `StudioMain` is carried across once so he does not lose the size and
    /// place he left it in, and then retired.
    ///
    /// **The rename still happens for a checking run**, which is what it was
    /// added for: a check must never write its window's geometry over his. A
    /// check moves its own window on purpose anyway.
    private static func settleTheFrame() {
        let defaults = UserDefaults.standard
        let mine = "NSWindow Frame StudioMain"
        let swiftUIs = "NSWindow Frame main"
        guard let kept = defaults.string(forKey: mine) else { return }
        // **Both names, one value.** Deleting `StudioMain` and leaning on
        // SwiftUI's was the first attempt and it lost his window: nothing
        // restored the frame at all and the app opened at the default size in
        // the corner. The window has to keep an autosave name to remember
        // anything — so it keeps ours, and this simply makes the frame SwiftUI
        // puts it at *first* the same as the one we restore a moment later.
        // The second placement then moves it nowhere, which is the whole point.
        guard defaults.string(forKey: swiftUIs) != kept else { return }
        defaults.set(kept, forKey: swiftUIs)
    }

    /// `--project <path>` opens a named one; otherwise the last one, or a new
    /// one if this is a first run.
    private func openProject() {
        let args = CommandLine.arguments
        if args.contains("--cardon") || args.contains("--cardfetch") || args.contains("--cardform") {
            cardDoors(args)
        } else if let at = args.firstIndex(of: "--newfilm"), at + 1 < args.count {
            newFilm(titled: args[at + 1])
        } else if args.contains("--archivefilm") || args.contains("--unarchivefilm") || args.contains("--deletefilm") {
            // **The archive door opens nothing.** It finds its film by the
            // page it is linked to and must not be holding that film, or any
            // other, while it moves one — `FilmDoor`.
        } else if let at = args.firstIndex(of: "--project"), at + 1 < args.count {
            _ = ShellState.shared.open(URL(fileURLWithPath: args[at + 1]))
        } else if let at = args.firstIndex(of: "--onproject"), at + 1 < args.count {
            // The same thing `--project` does, for a real second window rather
            // than a checking run. See `Launch.another(on:at:)`.
            _ = ShellState.shared.open(URL(fileURLWithPath: args[at + 1]))
        } else {
            ShellState.shared.openLastOrMakeOne()
            // Settings ▸ General ▸ On Launch: Show Projects puts the
            // browser up over the project it reopened.
            if !Self.checking, LaunchChoice.current == .projects { ShellState.shared.browsing = true }
        }
        let state = ShellState.shared
        let where_ = state.projectPath?.path ?? "nowhere"
        FileHandle.standardError.write(Data((
            "project: \(where_)  titled: \"\(state.view?.project.title ?? "")\"  "
            + "scenes: \(state.view?.scenes.count ?? 0)\n").utf8))
        if let problem = state.problem {
            FileHandle.standardError.write(Data("project problem: \(problem)\n".utf8))
        }
        if !state.stillArriving.isEmpty {
            FileHandle.standardError.write(Data((
                "still arriving: "
                + state.stillArriving.joined(separator: ", ") + "\n").utf8))
        }
    }

    /// **One ID's doors, for a checking run** (`NewCard.swift`), each saying
    /// one line and ending the run:
    ///
    /// - `--cardon` — whether New Project makes the card (`card: on|off`);
    /// - `--cardform "Name" Type` — the form New Project would send, with a
    ///   freshly minted ID (`cardform: {…}`); nothing is sent;
    /// - `--cardfetch <id> "Title"` — the project's Studio side fetched from
    ///   the relay under its ID, into `SHOTLISTER_FILMS` (`cardfetch: <path>
    ///   project <id>` or `cardfetch: refused — why`).
    ///
    /// The server is `-PortalURL`/`-PortalToken` and the relay `--syncsave`, as
    /// in every other checking run; nothing of his is asked.
    private func cardDoors(_ args: [String]) {
        // The relay a checking run is given, before anything asks it: this
        // door ends the run before `readFlags` would take `--syncsave`.
        if let at = args.firstIndex(of: "--syncsave"), at + 2 < args.count {
            _ = Relay.remember(address: args[at + 1])
            _ = Relay.remember(token: args[at + 2])
        }
        var said = ""
        var done = false
        Task { @MainActor in
            if args.contains("--cardon") {
                said = "card: \(await CardDoor.on() ? "on" : "off")"
            } else if let at = args.firstIndex(of: "--cardform"), at + 2 < args.count {
                let form = CardDoor.form(name: args[at + 1], type: args[at + 2], id: CardDoor.mint())
                let data = (try? JSONSerialization.data(withJSONObject: form, options: [.sortedKeys])) ?? Data()
                said = "cardform: \(String(decoding: data, as: UTF8.self))"
            } else if let at = args.firstIndex(of: "--cardfetch"), at + 2 < args.count {
                let home: URL
                if let into = ProcessInfo.processInfo.environment["SHOTLISTER_FILMS"], !into.isEmpty {
                    home = URL(fileURLWithPath: into, isDirectory: true)
                } else {
                    said = "cardfetch: refused — a checking run fetches only into SHOTLISTER_FILMS"
                    done = true
                    return
                }
                do {
                    let url = try await CardDoor.fetch(relay: args[at + 1], title: args[at + 2], into: home)
                    said = "cardfetch: \(url.path)  project \(Relay.projectId(at: url) ?? "")"
                } catch {
                    said = "cardfetch: refused — \(error.localizedDescription)"
                }
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(60)
        while !done && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        FileHandle.standardError.write(Data("\(said.isEmpty ? "card: nothing asked" : said)\n".utf8))
        exit(0)
    }

    /// `--newfilm "Title"` — the Projects Console's door for making a film,
    /// 2026-09-15. The film goes where every film goes,
    /// `Documents/Shotlister/<Title>.shotlist`, and is then open, so `--link
    /// "Console Name"` in the same run ties it to a console project and finds
    /// its Drive folder exactly as it does on any other film.
    ///
    /// **Refused when a film of that name is already there** — a film is
    /// somebody's work, and `freeName`'s "Title 2" would be the wrong answer
    /// for a program that asked for *this* title. The run says so on stderr
    /// and ends with status 1, so the console can read the refusal rather than
    /// find a second film.
    ///
    /// `SHOTLISTER_FILMS` names another folder to make it in. A checking run
    /// uses that so it never writes into his real films; the console never
    /// sets it.
    private func newFilm(titled title: String) {
        let state = ShellState.shared
        let name = Projects.safeName(title)
        let refused = { (why: String) in
            FileHandle.standardError.write(Data("newfilm: refused — \(why)\n".utf8))
            exit(1)
        }
        if name.isEmpty { refused("a film needs a title") }
        let home: URL
        if let said = ProcessInfo.processInfo.environment["SHOTLISTER_FILMS"], !said.isEmpty {
            home = URL(fileURLWithPath: said, isDirectory: true)
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        } else {
            home = Projects.home()
        }
        // By its folder name, case blind — `call her back` and `Call Her Back`
        // would be two films to the disk and one film to him.
        let taken = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .first { $0.lowercased() == "\(name).\(Projects.packageExtension)".lowercased() }
        if let taken {
            refused("a film called \"\(title)\" already exists at "
                    + home.appendingPathComponent(taken).path)
        }
        let path = home.appendingPathComponent(name).appendingPathExtension(Projects.packageExtension)
        guard state.open(path), let engine = state.engine, let id = state.view?.project.id else {
            refused("could not make a film at \(path.path)")
            return
        }
        // Through `replace`, which is what writes it to disk.
        state.replace(engine.set(shot: id, field: "title", value: title))
        FileHandle.standardError.write(Data((
            "newfilm: \"\(state.view?.project.title ?? "")\"  at \"\(path.path)\"\n").utf8))
    }

    /// **A real run that gives his screen straight back.** Set
    /// `SHOTLISTER_BACK=1` and the app launches exactly as it normally does —
    /// real window, restored frame, the whole chrome, and it *does* come to the
    /// front — but hands the front back to whoever had it a moment later.
    ///
    /// An environment variable rather than a flag, on purpose: every flag makes
    /// a run a *checking* run, and a checking run exits before the window has
    /// settled, so no flag can reach a bug that only happens in a real launch.
    /// The startup spin of 2026-09-02 was exactly that bug.
    ///
    /// **Coming to the front is not optional here**, which cost 42 clean runs
    /// to learn: with the activation skipped the spin never happened once. Its
    /// trigger is the appearance change activation brings, so a soak that never
    /// activates is a soak that proves nothing.
    static var background: Bool {
        ProcessInfo.processInfo.environment["SHOTLISTER_BACK"] == "1"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.background {
            // Whoever had the front, recorded before we can have taken it.
            let mine = Bundle.main.bundleIdentifier
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier != mine { victim = front }
            NSApp.activate(ignoringOtherApps: true)
            // Long enough for the activation to land and the first layout to
            // start, short enough that he sees a flicker rather than a theft.
            //
            // `SHOTLISTER_KEEPFRONT=1` holds the front instead — needed only
            // for measuring hover, which macOS does not deliver to an app that
            // is not active. Use it when he is away from the Mac.
            if ProcessInfo.processInfo.environment["SHOTLISTER_KEEPFRONT"] != "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    NSApp.deactivate()
                    NSApp.keyWindow?.resignKey()
                    self?.victim?.activate()
                }
            }
            // Say what the chrome cost to settle, then get out of the way. A
            // launch that settled says a handful; a launch that is thrashing
            // says thousands and climbing, and says it even when the runaway
            // has not tipped all the way over into the freeze.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                FileHandle.standardError.write(Data(
                    "switcher bodies: \(LayoutCost.switcherBodies)\n".utf8))
                exit(0)
            }
        } else if !Self.checking {
            NSApp.activate(ignoringOtherApps: true)
        }
        // **Be ready for the freeze this could not be made to happen again.**
        // See `Watchdog`. Not during a check: a battery drives the app hard and
        // then kills it, so a watchdog there would file the battery as a bug.
        if !Self.checking { Watchdog.begin() }
        // **The console's archive door can ask this window to let go of a
        // film** before it moves it. `FilmDoor`.
        if !Self.checking { FilmDoor.listen(state: ShellState.shared) }
        // **`SHOTLISTER_WEDGE=<seconds>` stops the main thread on purpose.**
        // A hang detector that has never caught a hang is a guess, and this is
        // the only way to make a real one to order: the thread is genuinely
        // blocked, exactly as it is during the freeze, so the capture path is
        // proved rather than assumed. Reachable only from the environment, and
        // never during a checking run.
        if let said = ProcessInfo.processInfo.environment["SHOTLISTER_WEDGE"],
           let seconds = TimeInterval(said), seconds > 0, !Self.checking {
            // `SHOTLISTER_WEDGE_AFTER` delays it, so a wedge can be made to
            // land *after* the app is properly up — which is the other half of
            // the watchdog's behaviour and has to be proved separately: a
            // freeze during his working session is reported and left alone,
            // never quit out from under him.
            let after = TimeInterval(
                ProcessInfo.processInfo.environment["SHOTLISTER_WEDGE_AFTER"] ?? "") ?? 1
            DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                Thread.sleep(forTimeInterval: seconds)
            }
        }
        DispatchQueue.main.async { self.rememberTheWindow() }
        watchHisFocus()
        Updates.begin()
        driveThenSnapshot()
    }

    // ------------------------------------------------- the invisibility guard

    /// Whether this run ever took the front. Sampled rather than assumed,
    /// because the first version of this harness reported clean results the
    /// whole time it was stealing his focus: it measured the app and never its
    /// own effect on the machine around it.
    private var stoleTheFront = false
    private var howStolen = ""
    private var focusWatch: Timer?
    private var loudKeeper: Timer?
    /// Whoever was in front when this process began — recorded before this
    /// process could possibly have taken anything, so a repair has somewhere
    /// to hand the front back to.
    private var victim: NSRunningApplication?

    private func watchHisFocus() {
        guard Self.checking, !Self.loud else { return }
        // This process, not this bundle — see the note where `victim` is
        // first set. His own Shotlister in front is not a theft.
        let me = ProcessInfo.processInfo.processIdentifier
        if victim == nil {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != me { victim = front }
        }
        // **Repaired the moment it happens, not on the next sample.**
        // The timer below is the *report*; these two are the fix. A poll can
        // only give the front back a tick late, and on a machine with one
        // screen that tick is wide enough for a keystroke. Notifications land
        // in the same runloop turn as the theft.
        for name in [NSApplication.didBecomeActiveNotification,
                     NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, Self.checking, !Self.loud else { return }
                NSApp.deactivate()
                NSApp.keyWindow?.resignKey()
                // **Never haul another app to the front during a long run.**
                //
                // 2026-08-29, and this one reached him: a four-minute `--churn`
                // was running in the background while he was working in his own
                // copy of Shotlister. Every time the churn's window became key
                // this fired, and `activate()` is a *cross-process* call — so
                // it repeatedly slammed whatever had been frontmost when the
                // run began (Finder) over the top of the app he was typing in.
                // His report: *"the program seems unable to stay in focus,
                // finder is immediately selected after i click something."*
                //
                // Stepping aside is ours to do; deciding who gets the front
                // instead is not. For the short runs a battery makes, letting
                // go is enough — the system hands the front back on its own.
                if !Self.churning { self.victim?.activate() }
            }
        }
        focusWatch = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let listed = NSWorkspace.shared.frontmostApplication?.processIdentifier == me
            let active = NSApp.isActive
            let keyed = NSApp.keyWindow != nil
            guard listed || active || keyed else { return }
            // Repair first, report after — and hand the front to whoever had
            // it, not merely away from us. `deactivate` alone leaves macOS
            // free to pick the front app itself, and on a machine with no
            // strong claimant it picks the newest process: us again, every
            // sample. The verdict still reports the trip, with all three
            // signals, because "frontmost but never active, never key" is a
            // menu-bar flicker while "active and key" is his keystrokes
            // landing in our buffer — and telling them apart is the
            // difference between a cosmetic bug and a broken law.
            NSApp.deactivate()
            NSApp.keyWindow?.resignKey()
            self.victim?.activate()
            if !self.stoleTheFront {
                self.stoleTheFront = true
                self.howStolen = "listed \(listed), active \(active), key \(keyed), "
                    + "front returned to \(self.victim?.localizedName ?? "no one")"
            }
        }
    }

    /// Every exit runs through here, so no run can end without saying whether
    /// it cost him anything.
    private func finish() {
        // Put the pen down first. A page line that still has the keyboard has
        // its words only in the text view; giving up first responder is what
        // makes it write them. A checking run exits with `exit(0)` — no
        // termination notice reaches anybody — so without this a run could
        // type into the page, quit, and report that nothing was written.
        for window in NSApp.windows where window.firstResponder is NSTextView {
            window.makeFirstResponder(nil)
        }
        reportFocus()
        // `exit` rather than `NSApp.terminate` for a checking run. Terminate is
        // polite — it asks the app to wind down — and an attached sheet declines,
        // so the process hangs on with a window open on his Dell until something
        // kills it. A check must always end, and end quickly.
        if Self.checking { exit(0) }
        NSApp.terminate(nil)
    }

    private func reportFocus() {
        guard Self.checking else { return }
        focusWatch?.invalidate()
        if Self.loud {
            loudKeeper?.invalidate()
            victim?.activate()
            let back = victim?.localizedName ?? "no one was in front"
            FileHandle.standardError.write(Data((
                "LOUD RUN — drove the real path frontmost on the overnight grant; "
                + "front returned to \(back)\n").utf8))
            return
        }
        let verdict = stoleTheFront
            ? "FOCUS STOLEN (\(howStolen)) — this run took the front; it is a bug, not a result\n"
            : "focus watch: clean, never frontmost, never key\n"
        FileHandle.standardError.write(Data(verdict.utf8))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// **`shotlister://film?…` from the Projects Console**, cold or warm.
    /// `FilmLink`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { FilmLink.handle(url, state: ShellState.shared) }
    }

    /// Belt to the autosave's braces: whatever is pending goes to disk on the
    /// way out, so quitting mid-thought costs nothing.
    func applicationWillTerminate(_ notification: Notification) {
        ShellState.shared.engine?.save()
    }

    // ------------------------------------------------------------ the window

    /// The window's size and position are its own business, so AppKit keeps
    /// them. The one thing we insist on is that a *first* run is wide enough
    /// to hold the sidebar and a full table, because a squashed first launch
    /// reads as a broken app.
    private func rememberTheWindow() {
        // **The main window by name, not by luck.** "The first visible window"
        // was the app's own until a checking run opened a viewer before this
        // ran — and then the viewer was given the main window's autosave name,
        // its size and its place on screen. SwiftUI stamps the main window's
        // identifier; the fallback keeps a plain launch working if it ever
        // stops doing so.
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.identifier?.rawValue == "main"
        }) ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        // **A checking run keeps its own window size, and never touches his.**
        // The fourth breach of the same law, and the first one AppKit committed
        // rather than us: an autosave name makes the *window* write its frame
        // into defaults, which the `Remembering` guard cannot intercept. Two
        // costs, both real. His frame was being overwritten by checks. And
        // every coordinate check inherited whatever size HIS window happened
        // to be — so resizing the app by hand silently moved every click in
        // the battery, and clicks past the new right edge landed on nothing
        // at all. Pinned here, like the sidebar width and the density are.
        // **Only a checking run renames the window.** A real run keeps the
        // autosave name SwiftUI gave it, because renaming *restores* the frame
        // saved under the new name — which moved the window, sometimes to a
        // monitor of a different sharpness, after it had already been laid
        // out. See `settleTheFrame`. Ref: his "blurry text" and the startup
        // freeze, both 2026-09-02, both this.
        let trace = ProcessInfo.processInfo.environment["SHOTLISTER_TRACEWINDOW"] == "1"
        func say(_ when: String) {
            guard trace else { return }
            FileHandle.standardError.write(Data((
                "window \(when): \(window.frame) "
                + "screen=\(window.screen?.localizedName ?? "?") "
                + "scale=\(window.backingScaleFactor)\n").utf8))
        }
        say("before")
        window.setFrameAutosaveName(Self.checking ? "StudioChecking" : "StudioMain")
        say("after ")
        if Self.checking, let screen = window.screen ?? NSScreen.main {
            // SHOTLISTER_WIDTH: a narrower window, for a check of what folds.
            let asked = ProcessInfo.processInfo.environment["SHOTLISTER_WIDTH"].flatMap(Double.init).map { CGFloat($0) }
            let wide = min(asked ?? 1560, screen.visibleFrame.width - 80)
            let tall = min(960, screen.visibleFrame.height - 60)
            window.setContentSize(CGSize(width: wide, height: tall))
        }
        // A checking run shows its window without asking for anything:
        // `orderFrontRegardless` puts it on screen so the layers are live and
        // hit-testing works, and never makes it key or brings the app forward.
        // The cost is that the traffic lights photograph grey — a fair trade
        // for a check he cannot feel, and noted wherever those shots are used.
        if Self.checking && !Self.loud {
            // At the *back*, not the front. `orderFrontRegardless` kept the
            // window unkeyed but still invited macOS to treat a freshly
            // launched regular app as the place the person is looking — and
            // sometimes, on launch timing, the system activated it. Two of
            // Nathaniel's own keystrokes once landed inside a check that way.
            // The layers are just as live at the back of the stack.
            // Let go of the front *before* the window appears, not only
            // after. Found 2026-08-19, when his second display went away and
            // every checking run began coming up frontmost: with the window
            // landing on the screen he is actually looking at, the launch
            // lottery hands the front over during the ordering itself, and
            // a repair that waits for the watch's first sample is a repair
            // that arrives after the fact.
            if NSApp.isActive { NSApp.deactivate() }
            NSApp.keyWindow?.resignKey()
            window.order(.below, relativeTo: 0)
            // And once the window exists, the process stops being a regular
            // app at all. It had to start as one — SwiftUI will not create a
            // window for an accessory app — but it does not have to stay one:
            // as an accessory it is out of the launch-activation lottery that
            // was intermittently handing it the front. **The timing is load-
            // bearing and was found by soak-testing, not reasoning**: switch
            // here, after the window is ordered, and ten launches in a row
            // come up clean; switch earlier, in `didFinishLaunching`, and
            // LaunchServices reports the app frontmost on every single run.
            // If a trip still slips through, the watch hands the front back
            // within one sample. Do not move this without re-running the
            // ten-launch soak.
            NSApp.setActivationPolicy(.accessory)
            if NSApp.isActive { NSApp.deactivate() }
            NSApp.keyWindow?.resignKey()
            // And hand it back to whoever had it, immediately. The watch does
            // this too, but no sooner than its next tick; on one screen that
            // is long enough for a keystroke.
            victim?.activate()
        } else {
            window.makeKeyAndOrderFront(nil)
            if Self.loud { NSApp.activate(ignoringOtherApps: true) }
        }
        // The toolbar says which *project* is open. The app's own name is on
        // the menu bar already, and saying it twice costs the project its place.
        window.titleVisibility = .hidden

        // `--screen <n>` puts the window on another display. It exists so a
        // checking run does not open a window over whatever Nathaniel is doing
        // on his main screen. Screens are listed on stderr during a snapshot so
        // the right number can be picked rather than guessed.
        let args = CommandLine.arguments
        // `--wide 2400` sets the window's width, so the columns filling a wide
        // window — and letting go of it again when it narrows — is something a
        // check can see. Without it that behaviour is invisible to everything
        // except his eyes on a big monitor.
        if let at = args.firstIndex(of: "--wide"), at + 1 < args.count,
           let want = Double(args[at + 1]) {
            var frame = window.frame
            frame.size.width = CGFloat(want)
            window.setFrame(frame, display: true)
        }
        // `--screen <index|name>` — **a name, not only a number.** Which index
        // a display gets depends on which one is the main monitor, and that
        // changes: his instruction, 2026-09-02, is that the app's checking
        // windows stay off whichever screen he is working on, and he has just
        // made the PA32UCDM his main. A battery asking for screen 1 would
        // follow him there. Asking for `HP` does not.
        if let at = args.firstIndex(of: "--screen"), at + 1 < args.count,
           let screen = screenAsked(args[at + 1]) {
            let area = screen.visibleFrame
            var frame = window.frame
            frame.size.width = min(frame.width, area.width - 40)
            frame.size.height = min(frame.height, area.height - 40)
            frame.origin = CGPoint(
                x: area.midX - frame.width / 2,
                y: area.midY - frame.height / 2
            )
            window.setFrame(frame, display: true)
        }

        let done = "openedWideEnoughOnce"
        guard !UserDefaults.standard.bool(forKey: done),
              let screen = window.screen ?? NSScreen.main else { return }
        if !Self.checking { UserDefaults.standard.set(true, forKey: done) }
        let wide = min(1560, screen.visibleFrame.width - 80)
        let tall = min(960, screen.visibleFrame.height - 60)
        guard window.frame.width < wide - 1 else { return }
        window.setContentSize(CGSize(width: wide, height: max(window.frame.height, tall)))
        window.center()
    }

    /// Which display a checking run asked for: an index, or any part of a
    /// display's name. Nothing when neither matches, so the window simply
    /// stays where it opened rather than landing somewhere arbitrary.
    private func screenAsked(_ asked: String) -> NSScreen? {
        if let index = Int(asked) {
            return index < NSScreen.screens.count ? NSScreen.screens[index] : nil
        }
        let wanted = asked.lowercased()
        return NSScreen.screens.first {
            $0.localizedName.lowercased().contains(wanted)
        }
    }

    // ------------------------------------------------------------- checking

    /// Flags that put the shell into a known state so a picture of it means
    /// something. None of them are features; they exist so work can be
    /// verified without a hand on the mouse.
    private func readFlags() {
        let args = CommandLine.arguments
        let state = ShellState.shared

        if let at = args.firstIndex(of: "--place"), at + 1 < args.count,
           let tab = SideTab(rawValue: args[at + 1]) {
            state.sideTab = tab
        }
        // **Modes (stage 5 step 4 B)**: `--setmode schedule:off` (or `:on`,
        // `:both` for Shot List with Schedule) asks the server as + and Turn
        // Off do; `--recards` reads the cards again, as the five-minute beat
        // does, so a mode turned off elsewhere can be seen to move the bar.
        if let at = args.firstIndex(of: "--setmode"), at + 1 < args.count {
            let said = args[at + 1].split(separator: ":").map(String.init)
            if let tab = SideTab(rawValue: said.first ?? "") {
                let how = said.count > 1 ? said[1] : "on"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    state.setMode(tab, on: how == "on", both: how == "both")
                }
            }
        }
        // **A draft in Drive (step 4 C)**: `--reviewdraft` presses the
        // banner's Review… once the cards and the script check are in;
        // `--scriptdo take` then imports it as a person would.
        if args.contains("--reviewdraft") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { state.reviewDriveDraft() }
        }
        // `--pickdraft N`: picks the Nth draft (from 0) in "Pick the current draft".
        if let at = args.firstIndex(of: "--pickdraft"), at + 1 < args.count, let n = Int(args[at + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let path = state.projectPath,
                      let found = ProjectCards.shared.draftChoices(film: Relay.projectId(at: path), page: state.view?.project.consolePage ?? ""),
                      n < found.choices.count else {
                    FileHandle.standardError.write(Data("pick draft: no choices\n".utf8)); return
                }
                state.pickDriveDraft(found.choices[n])
            }
        }
        // **Shoots (step 4 D)**: `--shoot N|all|<id>` stands on a shoot (in
        // `applyShootPick`); `--moveshoot <scene number> <shoot N>` is Move to
        // Shoot…; `--shootplan` prints the converter's dry run and
        // `--shootplan apply` writes it (on a copy only); `--filmlink <url>`
        // is a shotlister:// link arriving, as the console sends one.
        if let at = args.firstIndex(of: "--moveshoot"), at + 2 < args.count, let n = Int(args[at + 2]) {
            let number = args[at + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard n >= 1, n <= state.shoots.count,
                      let scene = state.view?.scenes.first(where: { $0.number == number }) else {
                    FileHandle.standardError.write(Data("moveshoot: no such scene or shoot\n".utf8)); return
                }
                state.moveScenes([scene.id], toShoot: state.shoots[n - 1])
                state.applyShootPick()
            }
        }
        if let at = args.firstIndex(of: "--shootplan") {
            let apply = at + 1 < args.count && args[at + 1] == "apply"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let engine = state.engine else { return }
                let said = engine.shootPlan(apply: apply)
                FileHandle.standardError.write(Data("shootplan\(apply ? " apply" : ""): \(said)\n".utf8))
                if apply { state.replace(engine.view()); state.applyShootPick() }
            }
        }
        if let at = args.firstIndex(of: "--filmlink"), at + 1 < args.count, let url = URL(string: args[at + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { FilmLink.handle(url, state: state) }
        }
        if args.contains("--recards") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ProjectCards.shared.refresh(state) }
        }
        // `--onmode` is `--place` for a real second window. See
        // `Launch.another(on:at:)` for why it cannot simply be `--place`.
        if let at = args.firstIndex(of: "--onmode"), at + 1 < args.count,
           let tab = SideTab(rawValue: args[at + 1]) {
            state.sideTab = tab
        }
        // **A posture flag that quietly does nothing is worse than no flag.**
        // The table's own name is `shots`, and `--tab table` set nothing at
        // all — so half an afternoon of measurements on 2026-09-04 compared
        // the document view with itself and reported that the table cost the
        // same. It says so now.
        if let at = args.firstIndex(of: "--tab"), at + 1 < args.count {
            if let tab = SceneTab(rawValue: args[at + 1]) {
                state.tab = tab
            } else {
                FileHandle.standardError.write(Data((
                    "no such view: \(args[at + 1]) — it is "
                    + SceneTab.allCases.map(\.rawValue).joined(separator: ", ")
                    + "\n").utf8))
            }
        }
        // `--docstyle body:14:sans:upper` — set one kind of words on the
        // document page, so a check can watch it reach the page and the
        // export both. A fifth part is the ink: `--docstyle notes:9:serif:as:b3261e`.
        // `--docstyle reset` puts the whole page back.
        if let at = args.firstIndex(of: "--docstyle"), at + 1 < args.count,
           let engine = state.engine {
            let said = args[at + 1]
            if said == "reset" {
                state.replace(engine.resetDocStyle())
            } else {
                let bits = said.split(separator: ":")
                if bits.count >= 4, let size = Double(bits[1]) {
                    state.replace(engine.setDocStyle(
                        String(bits[0]), size: size,
                        face: String(bits[2]), case: String(bits[3]),
                        colour: bits.count > 4 ? String(bits[4]) : ""))
                }
            }
        }
        // `--pagedefault save` keeps this film's page as the one every other
        // film starts from; `--pagedefault clear` forgets it; `--pagedefault
        // use` puts this film onto it. `--pagedefaultsays` reads it back.
        //
        // In memory only under a checking run, which is the point: the real
        // one is his, and a battery that wrote it would set his films' pages
        // from a fixture.
        if let at = args.firstIndex(of: "--pagedefault"), at + 1 < args.count {
            switch args[at + 1] {
            case "save": state.savePageDefault()
            case "clear": state.clearPageDefault()
            case "use": state.usePageDefault()
            default:
                // Setting it here is after the film has already opened, so the
                // handing-over that `open` does has to be asked for again.
                state.pageDefault = args[at + 1]
                state.handOverTheDefault()
            }
        }
        if args.contains("--pagedefaultsays") {
            FileHandle.standardError.write(Data((
                "page default: " + state.pageDefault + "\n").utf8))
        }
        // What the page is set in, said out loud so a check can assert it.
        if args.contains("--typepanel") { state.showTypePanel = true }
        if args.contains("--docstylesays") {
            let all = (state.view?.project.docStyle ?? [])
                .map { "\($0.class)=\(Int($0.size * 10))/\($0.face)/\($0.case)/\($0.colour)" }
                .joined(separator: " ")
            FileHandle.standardError.write(Data(("doc style: " + all + "\n").utf8))
        }
        // `--pictures-waiting <n>` puts a number on the Sync button without a
        // relay.
        //
        // **The one thing about the badge that cannot be checked any other
        // way.** Its real value comes off the relay, so proving it draws would
        // otherwise mean taking a picture out of his live bucket and putting it
        // back — the exact kind of test that is one mistake away from losing
        // something. This sets the published number and nothing else; the
        // counting itself is `Relay.picturesWaiting`, which is the same array
        // `syncMedia` sends from.
        if let at = args.firstIndex(of: "--pictures-waiting"), at + 1 < args.count,
           let many = Int(args[at + 1]) {
            state.picturesWaiting = many
        }
        if let at = args.firstIndex(of: "--scene"), at + 1 < args.count {
            // By the number a person would say out loud — "34" — rather than
            // the engine's internal id, which nobody can type from a screenshot.
            let wanted = args[at + 1]
            state.sceneId = state.view?.scenes.first { $0.number == wanted }?.id ?? wanted
        }
        // **What each storyboard card actually draws.** His ask, 2026-09-04:
        // a card should show every frame the shot has, not the first with a
        // number beside it. The drawing is pixels and no battery can see
        // those, so the card and this ask the same function.
        if args.contains("--boardframes") {
            let said = (state.view?.allRows ?? [])
                .filter { $0.sceneId == state.sceneId }
                .map { row -> String in
                    let drawn = StoryboardView.shown(row).count
                    let more = row.stills.count - drawn
                    return "\(row.number)=\(drawn)" + (more > 0 ? "+\(more)" : "")
                }
                .joined(separator: " ")
            FileHandle.standardError.write(Data((
                "board frames: " + said + "\n").utf8))
        }
        if let at = args.firstIndex(of: "--cell"), at + 1 < args.count {
            state.cursorColumn = args[at + 1]
            state.cursorShot = state.view?.allRows
                .first { $0.sceneId == state.scene?.id }?.id
        }
        // `--shot <number>` puts the cursor on a shot **by its number**,
        // wherever in the script it lives — deliberately without touching
        // which scene the chrome names. That gap is exactly where his ⌘⏎ bug
        // lived: cursor in 34, chrome saying 33, and the new shot landing in
        // 33. A check cannot see that bug unless it can make the gap.
        if let at = args.firstIndex(of: "--shot"), at + 1 < args.count {
            let wanted = args[at + 1].uppercased()
            state.cursorShot = state.view?.allRows
                .first { $0.number.uppercased() == wanted }?.id
        }
        // **What size the words of a shot actually come out at.**
        //
        // The one fact that broke on 2026-09-03 — his *"the body didn't seem
        // to change size with my adjustments"* — and the one nothing else can
        // see: the words are stored as RTF carrying their own point size, so
        // the class landing on the page and the class landing on the *words*
        // are two different things. This says the second out loud.
        if args.contains("--richsays"),
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
            let type = PageType(state.view?.project)
            let drawn = Rich.decode(
                row.descriptionRich, plain: row.description,
                font: Faces.font(type.face(.body), size: type.size(.body)),
                colour: .black)
            var sizes: Set<String> = []
            drawn.enumerateAttribute(
                .font, in: NSRange(location: 0, length: drawn.length)
            ) { value, _, _ in
                guard let font = value as? NSFont else { return }
                sizes.insert(String(format: "%.1f", font.pointSize))
            }
            FileHandle.standardError.write(Data((
                "rich sizes: " + sizes.sorted().joined(separator: " ") + "\n").utf8))
        }
        // `--pick 34A,34C,34D` selects whole shots by number, the way pressing
        // their number columns with ⇧ and ⌘ would. A checking run gets one
        // click, and building a *set* takes several — so without this the
        // multi-shot carry could only ever be checked by reading the code,
        // which is not checking.
        if let at = args.firstIndex(of: "--pick"), at + 1 < args.count {
            let wanted = Set(args[at + 1].split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
            state.wholeShots = Set((state.view?.allRows ?? [])
                .filter { wanted.contains($0.number.uppercased()) }
                .map(\.id))
            state.cursorShot = state.wholeShots.first
        }
        // `--mark 34A,34C` ticks shots (the ⇧-clicked rows a cell's column
        // runs down), and `--range 34A/size..35A/angle` drags a rectangle of
        // cells between two corners, by shot number and column. Without them
        // a copy, cut or paste check could only ever reach the one cell the
        // cursor stands in.
        if let at = args.firstIndex(of: "--mark"), at + 1 < args.count {
            let wanted = Set(args[at + 1].split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
            state.marked = Set((state.view?.allRows ?? [])
                .filter { wanted.contains($0.number.uppercased()) }
                .map(\.id))
        }
        if let at = args.firstIndex(of: "--range"), at + 1 < args.count {
            let ends = args[at + 1].components(separatedBy: "..")
            func corner(_ text: String) -> (row: String, column: String)? {
                let halves = text.split(separator: "/").map(String.init)
                guard halves.count == 2,
                      let row = (state.view?.allRows ?? []).first(where: {
                          $0.number.uppercased() == halves[0].uppercased() })
                else { return nil }
                return (row.id, Columns.resolve(halves[1], state: state))
            }
            if ends.count == 2, let from = corner(ends[0]), let to = corner(ends[1]) {
                state.cursorShot = from.row
                state.cursorColumn = from.column
                state.cellRange = .init(anchorRow: from.row, anchorColumn: from.column,
                                        endRow: to.row, endColumn: to.column)
            }
        }
        // `--frame <file>` puts a picture, a gif or a clip on the shot the
        // cursor is in, by the same door a drop uses. Without it nothing could
        // check what a *moving* frame does in the table, which is the whole of
        // Ref 80.
        if let at = args.firstIndex(of: "--frame"), at + 1 < args.count,
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
            Ingest.attach(url: URL(fileURLWithPath: args[at + 1]), to: row, state: state)
        }
        // `--frameswindow` opens a shot's frames window on the cursor shot,
        // by the call a double-click makes. Until 2026-08-29 the only way in
        // was `--tap`, which cannot run alongside `--snapshot` or a report —
        // so the window could never be photographed, and it drifted into a
        // different-looking program from the other two pop-outs without
        // anything noticing.
        if args.contains("--frameswindow"), let id = state.cursorShot {
            FrameWindows.shared.open(for: id, state: state)
        }
        // `--frameprint` opens the frames window on the cursor shot and flips
        // its Pictures | Print Frame switch: the door he actually uses, in
        // the one window (`--window frames --snapshot` photographs it).
        if args.contains("--frameprint"), let id = state.cursorShot {
            FrameWindows.shared.open(for: id, state: state).printing = true
        }
        // `--printframe` opens the pop-out viewer on the cursor shot's key
        // picture, in Print Frame mode — the switch's own door.
        if args.contains("--printframe"),
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }),
           let still = row.stills.first(where: \.key) ?? row.stills.first {
            Viewer.shared.show(Viewer.subject(
                hash: still.hash, ext: still.ext, filename: still.filename,
                kind: still.kind ?? "", ref: still.ref,
                trimStart: still.trimStart, trimEnd: still.trimEnd,
                framing: still.framing, state: state), state: state)
        }
        // `--deleteframes` takes every picture off the cursor shot, by the
        // call the table's ⌫ alert makes once it is answered. The alert itself
        // cannot be clicked or photographed by any check (Ref 366), so this is
        // the half that can be asserted: the engine's, which is the half that
        // loses data if it is wrong.
        if args.contains("--deleteframes"),
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
            state.removePhotos(row.stills.map(\.ref))
        }
        // `--copyto 35` copies whatever `--pick` selected into that scene, by
        // the same call the menu and the bar make. Neither of those can be
        // clicked by a checking run, and a feature reachable only by hand is a
        // feature nothing checks.
        if let at = args.firstIndex(of: "--copyto"), at + 1 < args.count,
           let engine = state.engine {
            let wanted = args[at + 1]
            if let scene = state.view?.scenes.first(where: { $0.number == wanted }) {
                let held = (state.view?.allRows ?? [])
                    .filter { state.wholeShots.contains($0.id) }
                state.replace(engine.copyShots(held.map(\.placement), toScene: scene.id))
            }
        }
        // ---------------------------------------------------------- locations
        //
        // The Locations screen has no cell to type into and no row to click:
        // it is a name, a map sheet and a wall of pictures. Without these four
        // flags nothing about it could be checked except by photographing it,
        // and a photograph cannot say which record a value landed on.

        // `--addlocation "County Jail"` — through the same engine call the
        // sheet makes.
        for (at, flag) in args.enumerated()
        where flag == "--addlocation" && at + 1 < args.count {
            state.replace(state.engine?.addLocation(name: args[at + 1]))
            state.locationId = (state.view?.locations ?? []).last?.id
        }
        // ---- mood boards --------------------------------------------------
        // `--addboard "Night Exteriors"` makes one; `--board "Anya"` opens it
        // by name, the way clicking it in the sidebar does; `--dropphotoon`
        // hangs a file on it through the very same door a real drag uses.
        // **Searched before anything reports.** This sat six hundred lines
        // below and was applied after `--boardssay` had already written what
        // the sidebar was showing, so a run could set a search and read back a
        // list that had never seen it. It looked exactly like a search box that
        // does nothing — which is what this tab genuinely had until today, so
        // the first check written for it passed for the wrong reason.
        if let at = args.firstIndex(of: "--search"), at + 1 < args.count {
            state.search = args[at + 1]
        }
        for (at, flag) in args.enumerated()
        where flag == "--addboard" && at + 1 < args.count {
            state.replace(state.engine?.addBoard(name: args[at + 1]))
            state.boardId = (state.view?.boards ?? []).last?.id
        }
        if let at = args.firstIndex(of: "--board"), at + 1 < args.count {
            let wanted = args[at + 1].lowercased()
            state.boardId = (state.view?.boards ?? [])
                .first { $0.name.lowercased() == wanted }?.id
        }
        for (at, flag) in args.enumerated()
        where flag == "--renameboard" && at + 1 < args.count {
            if let open = state.board {
                state.replace(state.engine?.renameBoard(open.id, name: args[at + 1]))
            }
        }
        if args.contains("--deleteboard"), let open = state.board {
            state.replace(state.engine?.deleteBoard(open.id))
        }
        // `--boardratio original|square|project` — the same menu `ratioMenu`
        // in `Boards.swift` writes, through the generic `set` the shell's own
        // ⌘⏎ and picker never needed a bespoke command for.
        for (at, flag) in args.enumerated()
        where flag == "--boardratio" && at + 1 < args.count {
            if let open = state.board {
                state.replace(state.engine?.set(shot: open.id, field: "board_ratio", value: args[at + 1]))
            }
        }
        // `--crop <x> <y> <scale>` — frames the **first** picture on the open
        // board, through the same `engine.crop` the sheet's Save calls.
        //
        // **The sheet itself cannot be photographed** — no sheet in this app
        // can, and that has been true since `--editcolumns` — so without this
        // the framing would be checkable only by hand, which is how a thing
        // ships doing nothing.
        for (at, flag) in args.enumerated()
        where flag == "--crop" && at + 3 < args.count {
            guard let x = Double(args[at + 1]), let y = Double(args[at + 2]),
                  let scale = Double(args[at + 3]) else { continue }
            // A board's first picture when a board is open; otherwise the
            // cursor shot's own frame. **The second half is why the crop
            // reaching a printed page could be checked at all** — the fault
            // was on a shot's key frame, and no door could put a crop there.
            let ref = state.board?.media.first?.ref
                ?? state.view?.allRows.first { $0.id == state.cursorShot }?.stills.first?.ref
            if let ref {
                state.replace(state.engine?.crop(ref, x: x, y: y, scale: scale))
            }
        }

        // `--cropsays` — every picture on the open board and how it is framed,
        // read back off the view rather than off anything this run remembers.
        if args.contains("--cropsays"), let open = state.board {
            for picture in open.media {
                let framing = picture.framing
                FileHandle.standardError.write(Data(String(
                    format: "crop: %@ x=%.3f y=%.3f scale=%.3f\n",
                    picture.filename, framing.x, framing.y, framing.scale).utf8))
            }
        }

        // `--arrows <move>` — the storyboard arrows on the cursor shot's first
        // frame, put there by `ArrowBoard.save`, which is the *same* road the
        // hand and the Add menu take. `<move>` is one of the names in the menu
        // — Arrow, Pan Left, Tilt Up, Push In, Truck Left, Orbit, Walk and the rest
        // — or `clear`.
        //
        // **This is the only way any of it can be checked.** Drawing an arrow
        // is a drag, and a synthetic mouse cannot drive one; without this the
        // whole feature would be verifiable only by hand.
        for (at, flag) in args.enumerated()
        where flag == "--arrows" && at + 1 < args.count {
            guard let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }),
                  let first = row.stills.first else { continue }
            let want = args[at + 1]
            if want.lowercased() == "clear" {
                ArrowBoard.save([], ref: first.ref, state: state)
            } else if let move = ViewModel.Arrow.Mark.allCases
                .first(where: { $0.rawValue.lowercased() == want.lowercased() }) {
                // **Inside the film's frame**, exactly as the menu places it —
                // the picture is usually not the film's shape, and a preset
                // laid on the whole photograph puts arrows off the shot.
                let frame = ViewModel.Frame(hash: first.hash,
                                            filename: first.filename, kind: first.kind)
                let visible = Thumbs.shared.image(frame, from: state.engine)
                    .map { Plate.visible(picture: $0.size,
                                         ratio: CGFloat(state.view?.project.ratio ?? 2.39),
                                         framing: first.framing) }
                    ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                ArrowBoard.save(first.marks + move.arrows(in: visible),
                                ref: first.ref, state: state)
            }
        }

        // `--arrowline <line>` — arrows in the stored line's own words (what
        // `ViewModel.Arrow.encode` writes) added to the cursor shot's first
        // frame through `ArrowBoard.save`. The marks menu has no short or
        // hand-widened arrow; this is how a check draws one.
        for (at, flag) in args.enumerated()
        where flag == "--arrowline" && at + 1 < args.count {
            guard let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }),
                  let first = row.stills.first else { continue }
            ArrowBoard.save(first.marks + ViewModel.Arrow.parse(args[at + 1]), ref: first.ref, state: state)
        }

        // `--arrowdrag "<line>;<handle>;<dx>;<dy>"` — the drag arithmetic of
        // the two width handles, on a 1000 x 1000 picture: the stored line's
        // first arrow, the pointer put at handle 0 (shaft) or 1 (head) plus
        // (dx, dy), and what the widths become. A synthetic mouse cannot drag.
        for (at, flag) in args.enumerated()
        where flag == "--arrowdrag" && at + 1 < args.count {
            let bits = args[at + 1].components(separatedBy: ";")
            guard bits.count == 4, let k = Int(bits[1]), let dx = Double(bits[2]), let dy = Double(bits[3]) else { continue }
            let plate = CGRect(x: 0, y: 0, width: 1000, height: 1000)
            let marks = ViewModel.Arrow.parse(bits[0])
            guard let arrow = marks.first else { continue }
            let at0 = Storyboarding.widthHandles(arrow, on: plate)
            guard at0.indices.contains(k) else {
                FileHandle.standardError.write(Data("arrowdrag: handles=\(at0.count) none=\(k)\n".utf8))
                continue
            }
            let to = CGPoint(x: at0[k].x + dx, y: at0[k].y + dy)
            let made = Storyboarding.draggedWidths(arrow, handle: k, to: to, on: plate) ?? []
            var drawn = arrow; drawn.widths = made
            let now = Storyboarding.widths(drawn, in: plate)
            FileHandle.standardError.write(Data(String(format: "arrowdrag: handles=%d wide=%d before=%@ widths=%@ drawn=%.1f,%.1f line=%@\n",
                at0.count, (made.count == 2 && made[0] > made[1]) ? 1 : 0,
                Storyboarding.widths(arrow, in: plate).map { String(format: "%.1f", $0) }.joined(separator: ","),
                made.map { String(format: "%.4f", $0) }.joined(separator: ","),
                now[0], now[1], ViewModel.Arrow.encode([drawn])).utf8))
        }

        if args.contains("--arrowslide") || args.contains("--arrowremember"),
           let suite = UserDefaults(suiteName: "arrow-thickness-check") {
            // A checking run never reads or writes the remembered thickness
            // of the real app.
            ArrowThickness.store = suite
            if let r = args.firstIndex(of: "--arrowremember"), r + 1 < args.count, args[r + 1] == "reset" {
                suite.removeObject(forKey: ArrowThickness.key)
            }
        }
        // `--arrowedit "<line>;<edit>,<edit>…"` — the arrow's bar, pressed. Each
        // edit is what a button or a drag on the bar does to the first arrow
        // (straighten, resetwidths, flat, toward, away, standing, floor, dashed,
        // solid, heads2, red, corner, smooth, widths, movehead, movewhole,
        // pin); the result goes through `ArrowBoard.save` — the road the hand
        // takes — and `--arrowssays` then reads it back off the view. The claim
        // is that no edit changes the thickness (2026-10-15).
        for (at, flag) in args.enumerated()
        where flag == "--arrowedit" && at + 1 < args.count {
            let bits = args[at + 1].components(separatedBy: ";")
            guard bits.count == 2, let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }),
                  let first = row.stills.first else { continue }
            var marks = ViewModel.Arrow.parse(bits[0])
            guard !marks.isEmpty else { continue }
            var a = marks[0]
            let before = a.thickness
            for edit in bits[1].components(separatedBy: ",") where !edit.isEmpty {
                switch edit {
                case "straighten": a = a.straightened
                case "resetwidths": a = a.widthsReset
                case "flat": a = a.withDepth(.flat)
                case "toward": a = a.withDepth(.toward)
                case "away": a = a.withDepth(.away)
                case "standing": a.stance = .standing
                case "floor": a.stance = .floor
                case "dashed": a.dashed = true
                case "solid": a.dashed = false
                case "heads2": a.heads = 2
                case "red": a.look = .red
                case "corner": a.shape = .corner
                case "smooth": a.shape = .smooth
                case "widths": a.widths = [0.02, 0.05]
                case "movehead": a = a.movingEnd(head: true, to: CGPoint(x: 0.7, y: 0.2))
                case "movewhole": a = a.moved(by: CGSize(width: 0.05, height: 0.05), inside: CGRect(x: 0, y: 0, width: 1, height: 1))
                case "pin": a.pins = [.init(x: 0.6, y: 0.5)]
                default: break
                }
                a = a.held
            }
            marks[0] = a
            ArrowBoard.save(marks, ref: first.ref, state: state)
            FileHandle.standardError.write(Data(String(format: "arrowedit: before=%.2f after=%.2f\n", before, a.thickness).utf8))
        }

        // `--arrowslide "<line>;<value>;<redrawn 0|1>"` — the Thickness slider
        // moved to a value and let go, saved through the same draft the bar
        // uses. `redrawn 0` is a click in the track: the release comes before
        // the bar has been redrawn, so the arrow it was last handed is still
        // the old one. Remembers the thickness the way the bar does.
        for (at, flag) in args.enumerated()
        where flag == "--arrowslide" && at + 1 < args.count {
            let bits = args[at + 1].components(separatedBy: ";")
            guard bits.count == 3, let value = Double(bits[1]),
                  let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }),
                  let first = row.stills.first else { continue }
            var marks = ViewModel.Arrow.parse(bits[0])
            guard !marks.isEmpty else { continue }
            let draft = ArrowSliderDraft()
            let handed = marks[0]
            var moved = handed; moved.thickness = value
            draft.moved(to: moved)
            let done = draft.released(showing: bits[2] == "1" ? moved : handed)
            ArrowThickness.remember(done.thickness)
            marks[0] = done.held
            ArrowBoard.save(marks, ref: first.ref, state: state)
            FileHandle.standardError.write(Data(String(format: "arrowslide: saved=%.2f\n", done.thickness).utf8))
        }

        // `--arrowremember` — what a new arrow starts with, and the plain
        // Arrow mark that takes it.
        if args.contains("--arrowremember") {
            let mark = ViewModel.Arrow.Mark.arrow.arrows(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            FileHandle.standardError.write(Data(String(format: "arrowremember: next=%.2f mark=%.2f\n",
                ArrowThickness.remembered(), mark.first?.thickness ?? -1).utf8))
        }

        // `--arrowssays` — every frame on the cursor shot and how many arrows
        // it carries, read back off the view rather than off anything this run
        // remembers. The count is the claim; a screenshot is what proves they
        // are drawn in the right place.
        if args.contains("--arrowssays"),
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
            for still in row.stills {
                let marks = still.marks
                var said = "arrows: \(still.filename) count=\(marks.count)"
                if let first = marks.first {
                    said += String(format: "  first=%.3f,%.3f-%.3f,%.3f heads=%d",
                                   first.x1, first.y1, first.x2, first.y2, first.heads)
                }
                said += "  thick=" + marks.map { String(format: "%.2f", $0.thickness) }.joined(separator: ",")
                FileHandle.standardError.write(Data((said + "\n").utf8))
            }
        }

        // `--pinonboard <file>` — a picture onto the open board, through
        // `Attachments.add`, which is what a drop and the picker both call.
        for (at, flag) in args.enumerated()
        where flag == "--pinonboard" && at + 1 < args.count {
            if let open = state.board {
                Attachments.add(url: URL(fileURLWithPath: args[at + 1]),
                                ownedBy: open.id, state: state)
            }
        }
        // `--putpicture wall.png ref-3.jpg` carries the first picture and drops
        // it on the second, which is what a hand does on the wall. The pixels
        // are the hands script's — a synthetic mouse cannot start a dragging
        // session — but the arithmetic underneath is `ShellState`'s, and this
        // presses exactly that, so the half that can be checked is.
        for (at, flag) in args.enumerated()
        where flag == "--putpicture" && at + 2 < args.count {
            guard let open = state.board else { continue }
            let all = open.media
            let named = { (want: String) in
                all.first { $0.filename.lowercased() == want.lowercased() }?.ref
            }
            if let moving = named(args[at + 1]), let onto = named(args[at + 2]) {
                state.moveWallPicture(moving, before: onto, among: all.map(\.ref))
            }
        }
        // `--caption wall.png "moody"` — what is said under a picture. The
        // sheet that writes this cannot be photographed (Ref 366), so this is
        // the only way the words can be checked at all.
        //
        // **Restored 2026-08-24.** This flag and the two below it went missing
        // between commits — present in the checking-flags list so the app
        // still knew to treat a run carrying one as a checking run, but with
        // no code left that acted on it, so a check asserting a caption,
        // a tag, or a scene link silently asserted nothing. The engine side
        // never moved; only the console door had gone missing.
        for (at, flag) in args.enumerated()
        where flag == "--caption" && at + 2 < args.count {
            guard let open = state.board,
                  let picture = open.media.first(where: {
                      $0.filename.lowercased() == args[at + 1].lowercased()
                  }) else { continue }
            state.replace(state.engine?.caption(picture.ref, args[at + 2]))
        }
        // `--tagboard "Night"` puts a tag on the open board, through the same
        // generic `set` the scene's tags go through — so the term is taught to
        // the film's one vocabulary, not to a list of the board's own.
        for (at, flag) in args.enumerated()
        where flag == "--tagboard" && at + 1 < args.count {
            guard let open = state.board else { continue }
            let held = open.tagList
            let want = args[at + 1]
            state.replace(state.engine?.set(shot: open.id, field: "tags",
                                            value: (held + [want]).joined(separator: ", ")))
        }
        // `--linkhere 34` hangs the open board on that scene — the link made
        // from the board's side rather than the scene's.
        for (at, flag) in args.enumerated()
        where flag == "--linkhere" && at + 1 < args.count {
            guard let open = state.board,
                  let scene = (state.view?.scenes ?? []).first(where: { $0.number == args[at + 1] })
            else { continue }
            state.replace(state.engine?.addSceneBoard(scene.id, open.id))
        }
        // `--movepictureto wall.png "Other Board"` — the arithmetic half of a
        // picture dragged from one board's wall onto another in the sidebar.
        // The drag itself is a session no synthetic mouse can start; this
        // presses the same road `PictureWall`'s `onDrag`/`onDrop` and its
        // "Move to" menu both call, `Engine.movePicture`.
        for (at, flag) in args.enumerated()
        where flag == "--movepictureto" && at + 2 < args.count {
            guard let open = state.board,
                  let picture = open.media.first(where: {
                      $0.filename.lowercased() == args[at + 1].lowercased()
                  }),
                  let target = (state.view?.boards ?? []).first(where: {
                      $0.name.lowercased() == args[at + 2].lowercased()
                  }) else { continue }
            state.replace(state.engine?.movePicture(picture.ref, to: target.id))
        }
        // `--pickpictures wall.png,ref-3.jpg` picks pictures on the open board
        // by name, so what a click does to the selection can be read back.
        for (at, flag) in args.enumerated()
        where flag == "--pickpictures" && at + 1 < args.count {
            guard let open = state.board else { continue }
            let wanted = args[at + 1].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            let refs = open.media
                .filter { wanted.contains($0.filename.lowercased()) }
                .map(\.ref)
            state.pickedPhotos = Set(refs)
            state.pickedPhoto = refs.first
        }
        // `--linkboard "Night Exteriors"` links the scene the cursor is on
        // (`--scene 34`) to a board by name — the same menu the scene editor
        // sheet and the References panel both open. `--unlinkboard` takes it
        // off. Ref SL-348.
        for (at, flag) in args.enumerated()
        where flag == "--linkboard" && at + 1 < args.count {
            let wanted = args[at + 1].lowercased()
            if let scene = state.scene,
               let board = (state.view?.boards ?? []).first(where: { $0.name.lowercased() == wanted }) {
                state.replace(state.engine?.addSceneBoard(scene.id, board.id))
            }
        }
        for (at, flag) in args.enumerated()
        where flag == "--unlinkboard" && at + 1 < args.count {
            let wanted = args[at + 1].lowercased()
            if let scene = state.scene,
               let board = (state.view?.boards ?? []).first(where: { $0.name.lowercased() == wanted }) {
                state.replace(state.engine?.removeSceneBoard(scene.id, board.id))
            }
        }
        // What the boards hold, so a check can read it without a picture.
        if args.contains("--boardssay") {
            for board in state.view?.boards ?? [] {
                // Each picture, and how wide it hangs where that is not the
                // wall's default — `mountain.jpg:4`.
                let files = board.media.map { picture -> String in
                    var said = picture.filename
                    // What is said under it, when anything is — the sheet that
                    // writes a caption cannot be photographed (Ref 366).
                    if !picture.caption.isEmpty { said += "~\(picture.caption)" }
                    return said
                }.joined(separator: ",")
                FileHandle.standardError.write(Data((
                    "moodboard: \(board.name) pictures=\(board.media.count) "
                    + "ratio=\(board.ratioMode) "
                    + "tags=[\(board.tags)] scenes=\(board.scenes.count) "
                    + "[\(files)]\n").utf8))
            }
            FileHandle.standardError.write(Data((
                "moodboards: \((state.view?.boards ?? []).count)"
                + "  open: \(state.board?.name ?? "none")\n").utf8))
            // Which boards the sidebar is actually showing — the search box
            // over that list narrows it, and the count above counts the film.
            FileHandle.standardError.write(Data((
                "boards shown: "
                + (state.boardsShown.map(\.name).joined(separator: ",").isEmpty
                    ? "none" : state.boardsShown.map(\.name).joined(separator: ","))
                + "\n").utf8))
            // What is picked on the open board, by name — the selection is the
            // half of a click a screenshot cannot tell you about.
            let names = (state.board?.media ?? [])
                .filter { state.isPicked($0.ref) }
                .map(\.filename)
            FileHandle.standardError.write(Data((
                "board picked: \(names.isEmpty ? "none" : names.joined(separator: ","))\n").utf8))
            // Which boards each scene links to — the same "id=names" shape
            // `--locations` already prints for `scene locations:`.
            let pairs = (state.view?.scenes ?? []).map { scene -> String in
                let names = (state.view?.boards ?? [])
                    .filter { scene.boards.contains($0.id) }
                    .map(\.name)
                return "\(scene.number)=\(names.isEmpty ? "none" : names.joined(separator: "+"))"
            }.joined(separator: " | ")
            FileHandle.standardError.write(Data(("scene boards: " + pairs + "\n").utf8))
        }

        // `--location "County Jail"` opens one by name, the way clicking it in
        // the sidebar does.
        if let at = args.firstIndex(of: "--location"), at + 1 < args.count {
            let wanted = args[at + 1].lowercased()
            state.locationId = (state.view?.locations ?? [])
                .first { $0.name.lowercased() == wanted }?.id
        }
        // `--setlocation <field> <value>` writes one field on the open record.
        // Address and pin go together — a pin without an address is a dot in a
        // field and an address without a pin cannot be driven to.
        for (at, flag) in args.enumerated()
        where flag == "--setlocation" && at + 2 < args.count {
            if let open = state.location {
                state.replace(state.engine?.setLocation(open.id, args[at + 1], args[at + 2]))
            }
        }
        // `--addarea "Hillcrest House" Kitchen` puts a room inside a location
        // and opens it — Ref 269.
        for (at, flag) in args.enumerated()
        where flag == "--addarea" && at + 2 < args.count {
            let wanted = args[at + 1].lowercased()
            if let house = (state.view?.locations ?? []).first(where: {
                $0.name.lowercased() == wanted
            }) {
                let before = Set((state.view?.locations ?? []).map(\.id))
                state.replace(state.engine?.addArea(house.id, name: args[at + 2]))
                state.locationId = (state.view?.locations ?? [])
                    .first { !before.contains($0.id) }?.id
            }
        }
        // `--movelocation "Kitchen" "Hillcrest House"` files one inside
        // another; an empty second name lets it out again.
        for (at, flag) in args.enumerated()
        where flag == "--movelocation" && at + 2 < args.count {
            let all = state.view?.locations ?? []
            let moving = args[at + 1].lowercased()
            let into = args[at + 2].lowercased()
            if let place = all.first(where: { $0.name.lowercased() == moving }) {
                let house = all.first { $0.name.lowercased() == into }
                state.replace(state.engine?.moveLocation(place.id, into: house?.id ?? ""))
            }
        }
        // `--pinhere <path>` puts a file on the open **location**, through the
        // same door a drag does — which is how the renaming his Ref 273 asked
        // for can be checked rather than eyeballed.
        for (at, flag) in args.enumerated()
        where flag == "--pinhere" && at + 1 < args.count {
            if let open = state.location {
                Attachments.add(url: URL(fileURLWithPath: args[at + 1]),
                                ownedBy: open.id, state: state)
            }
        }
        // `--linkscene 34` shoots that scene at the open location. The other
        // direction — a scene naming its location — goes through the same
        // engine call, so one flag checks both.
        for (at, flag) in args.enumerated()
        where flag == "--linkscene" && at + 1 < args.count {
            if let open = state.location,
               let scene = (state.view?.scenes ?? []).first(where: { $0.number == args[at + 1] }) {
                state.replace(state.engine?.sceneLocation(scene.id, open.id))
            }
        }
        // `--alsoscene <number>` is the other door: the open location is *added*
        // to that scene rather than replacing what is there, which is how a
        // scene that moves between two places is built in a check.
        for (at, flag) in args.enumerated()
        where flag == "--alsoscene" && at + 1 < args.count {
            if let open = state.location,
               let scene = (state.view?.scenes ?? []).first(where: { $0.number == args[at + 1] }) {
                state.replace(state.engine?.addSceneLocation(scene.id, open.id))
            }
        }

        // **`--diagramsample` lays the sample bedroom on the scene** — the
        // plan's own `--floorplan`: a room, three cameras, a light through the
        // window, Anya getting up — so the Diagram mode can be photographed
        // without drawing a plan by hand first.
        if args.contains("--diagramsample"), let id = state.sceneId, let engine = state.engine {
            _ = engine.call("diagramsample", id)
            state.replace(engine.view())
        }

        // **`--floorplan [path]` draws a room.** With a path it reads a real
        // scan; with none it draws the hand-built sample — an L-shaped room,
        // scanned crooked at 23°, with a door, a window and four kinds of
        // furniture. That is the only way to see a floor plan on a machine with
        // no LiDAR in it, and every bug the phone thread found in this drawing
        // was found through its own version of this flag (their Ref 140).
        if let at = args.firstIndex(of: "--floorplan") {
            let given = at + 1 < args.count && !args[at + 1].hasPrefix("--") ? args[at + 1] : ""
            // `--scanmode room` opens on the 3D half instead. It exists so a
            // check can photograph it; without it the mode is whichever he was
            // last on, which is a setting of his and so not a thing a check may
            // depend on — the lesson the whole battery learned this morning.
            let opening: ScanContent.Mode? = args.firstIndex(of: "--scanmode")
                .flatMap { at in at + 1 < args.count ? args[at + 1] : nil }
                .flatMap { $0 == "room" ? .room : .plan }
            if given.isEmpty {
                let nowhere = URL(fileURLWithPath: "/dev/null")
                ScanWindow.shared.show(usdz: nowhere, json: nowhere,
                                       title: "A room nobody stood in",
                                       state: state, sample: true, opening: opening)
            } else {
                let json = URL(fileURLWithPath: given)
                let usdz = json.deletingPathExtension().appendingPathExtension("usdz")
                ScanWindow.shared.show(usdz: usdz, json: json,
                                       title: json.deletingPathExtension().lastPathComponent,
                                       state: state, opening: opening)
            }
        }

        // `--address` opens the map sheet on the location that is open. Only
        // `--live` can photograph it: a sheet is a child window and the layer
        // camera takes the parent.
        if args.contains("--address") { state.findingAddress = state.location?.id }

        // `--homecoming` brings in whatever the phone left in the project
        // folder, through the same call the banner's button makes.
        if args.contains("--homecoming") {
            Scout.bring(Scout.unclaimed(state: state), state: state)
        }

        // `--photo 3` picks the third photograph on the open location, **the
        // whole of what clicking it once does** — including carrying an open
        // viewer with it. A flag that stands in for a click has to do
        // everything the click does, or the half it leaves out is the half
        // nothing checks.
        // `--openphoto 2` double-clicks one: the viewer comes up on it. Applied
        // **before** `--photo` below, so `--openphoto 1 --photo 3` is the
        // sequence a hand makes — open one, then click another — which is the
        // only way to drive "clicking a second photograph carries the open
        // viewer with it". The typist runs later than any of this, so the two
        // halves could not be interleaved with `--type`.
        //
        // **Walked in argument order, and `--pinviewer` walks with it.** His
        // ask of 2026-08-28 is a *sequence* — open one, pin it, open another,
        // and get a second window rather than the first one being overwritten.
        // A flag that only ever fired once could not describe that, and the
        // pin is a button, so nothing else can reach it. `viewer:` now carries
        // `windows:` and `pinned:`, because two overlapping windows photograph
        // as one and the count is the whole claim.
        for (at, flag) in args.enumerated() {
            switch flag {
            case "--openphoto":
                guard at + 1 < args.count, let wanted = Int(args[at + 1]),
                      let open = state.location,
                      wanted >= 1, wanted <= open.photos.count else { continue }
                state.pickedPhoto = open.photos[wanted - 1].ref
                Viewer.shared.show(
                    LocationPage.subject(open.photos[wanted - 1], at: open, state: state),
                    state: state)
            case "--pinviewer":
                Viewer.shared.pinFront()
            default:
                continue
            }
        }

        // `--trimclip` opens Apple's trim bar on whatever clip is showing,
        // through the same call the scissors makes. The bar is reachable
        // only by clicking and cannot be photographed as a state, so
        // without this nothing could check that it opens at all — which is
        // exactly how it shipped not opening (2026-08-28). It prints
        // `trim: bar opened after Nms`, or says why not.
        // `--trim <start> <end>` cuts the cursor shot's first clip to that
        // range, in seconds, by the engine call the trim bar makes. `clear`
        // puts the whole clip back.
        //
        // **`--trimclip` cannot stand in for this.** That one drives AVKit's
        // own trim bar, which needs a frames window with a clip playing in it
        // and gives whatever range the handles happen to sit at — fine for
        // proving the bar is wired up, useless for asking "does a *particular*
        // range reach the printed page". Without a door that names the numbers
        // there was no way to check the four printed moments respect the trim
        // at all, which is how they came to ignore it.
        if let at = args.firstIndex(of: "--trim"), at + 1 < args.count,
           let engine = state.engine,
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }),
           let clip = row.stills.first {
            if args[at + 1] == "clear" {
                _ = engine.call("trim", clip.ref, "clear")
            } else if at + 2 < args.count {
                _ = engine.call("trim", clip.ref, args[at + 1], args[at + 2])
            }
            state.replace(engine.view())
            let now = state.view?.allRows.first { $0.id == row.id }?.stills.first
            FileHandle.standardError.write(Data(String(
                format: "trim: kept %.2f–%.2f\n",
                now?.trimStart ?? 0, now?.trimEnd ?? 0).utf8))
        }

        // `--clipssay` — what the engine thinks needs a four-moment strip, and
        // what each one is filed under. The name folds in the trim, so this is
        // how a check sees that a trimmed use asks for its own strip rather
        // than sharing the whole clip's.
        if args.contains("--clipssay"), let engine = state.engine {
            let said = engine.clipUses().map {
                String(format: "%@ %.2f–%.2f", $0.key, $0.start, $0.end)
            }
            FileHandle.standardError.write(Data(
                ("clips: " + said.joined(separator: " · ") + "\n").utf8))
        }

        if args.contains("--trimclip") {
            // **Waits for a clip rather than assuming one.** A run that opens
            // the frames window does it through `--tap`, which is itself two
            // seconds behind launch; firing on a fixed delay reported "no
            // clip showing" for a window that was about to appear.
            func whenAClipIsShowing(_ tries: Int) {
                if let clip = ClipView.live {
                    clip.trim(from: nil, to: nil,
                              whenStuck: { why in
                                  FileHandle.standardError.write(Data("trim: \(why)\n".utf8))
                              },
                              done: { start, end in
                                  FileHandle.standardError.write(Data(
                                      String(format: "trim: kept %.2f–%.2f\n", start, end).utf8))
                              })
                    return
                }
                guard tries < 60 else {
                    FileHandle.standardError.write(Data("trim: no clip showing\n".utf8))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    whenAClipIsShowing(tries + 1)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { whenAClipIsShowing(0) }
        }

        // The **last** `--photo`, so a check can click one and then click
        // another — which is the only way to drive "clicking a second
        // photograph carries the open viewer with it".
        if let at = args.lastIndex(of: "--photo"), at + 1 < args.count,
           let wanted = Int(args[at + 1]) {
            let photos = state.location?.photos ?? []
            if wanted >= 1 && wanted <= photos.count, let open = state.location {
                state.pickedPhotos = []
                state.pickedPhoto = photos[wanted - 1].ref
                Viewer.shared.follow(
                    LocationPage.subject(photos[wanted - 1], at: open, state: state),
                    state: state)
            }
        }

        // `--dropphoto 1` takes a photograph off the open location, the way the
        // right-click menu does. It exists so a check can be the *other*
        // program: one run drops a photograph while another sits watching, and
        // the watcher either notices or it does not.
        for (at, flag) in args.enumerated()
        where flag == "--dropphoto" && at + 1 < args.count {
            guard let wanted = Int(args[at + 1]), let open = state.location,
                  wanted >= 1, wanted <= open.photos.count else { continue }
            state.replace(state.engine?.detach(frame: open.photos[wanted - 1].ref))
        }

        // `--setup` opens the new-project screen on whatever project is open,
        // so the screen a film starts on can be photographed and read.
        // A window opened by ⌘N picks its own project rather than standing on
        // this one's.
        if args.contains("--fresh") { state.browsing = true }
        // `--another` presses ⌘N. The instance it starts is a *real* app on his
        // screen, so this is only ever run deliberately, never by the battery.
        if args.contains("--another") { Launch.another() }
        // `--photos 1,3` picks several at once, the way ⌘-clicking does, and
        // `--removepicked` runs the menu's own removal on them.
        if let at = args.firstIndex(of: "--photos"), at + 1 < args.count,
           let open = state.location {
            let wanted = args[at + 1].split(separator: ",").compactMap { Int($0) }
            state.pickedPhotos = Set(wanted.compactMap { n -> String? in
                guard n >= 1, n <= open.photos.count else { return nil }
                return open.photos[n - 1].ref
            })
            state.pickedPhoto = state.pickedPhotos.first
        }
        if args.contains("--removepicked") {
            state.removePhotos(Array(state.pickedPhotos))
        }
        // `--master 33A 1` and `--link 34A 33A` — the two the shot menu makes.
        for (at, flag) in args.enumerated()
        where flag == "--master" && at + 2 < args.count {
            if let row = state.view?.allRows.first(where: {
                $0.number.caseInsensitiveCompare(args[at + 1]) == .orderedSame
            }) {
                state.replace(state.engine?.makeMaster(row.shot, on: args[at + 2] != "0"))
            }
        }
        for (at, flag) in args.enumerated()
        where flag == "--link" && at + 2 < args.count {
            let rows = state.view?.allRows ?? []
            if let row = rows.first(where: {
                $0.number.caseInsensitiveCompare(args[at + 1]) == .orderedSame
            }) {
                let target = rows.first {
                    $0.number.caseInsensitiveCompare(args[at + 2]) == .orderedSame
                }
                state.replace(state.engine?.link(row.shot, to: target?.shot))
            }
        }
        // `--reference 2` picks the scene's second pinned reference, the way a
        // click on the board does — the board has no cell and no row, so
        // without this nothing about it could be checked but a photograph.
        if let at = args.firstIndex(of: "--reference"), at + 1 < args.count,
           let wanted = Int(args[at + 1]),
           let scene = state.view?.scenes.first(where: { $0.id == state.scene?.id }),
           wanted >= 1, wanted <= scene.attachments.count {
            state.pickedPhotos = []
            state.pickedPhoto = scene.attachments[wanted - 1].ref
        }
        // `--referencessay` reads the References panel's shape without a
        // photograph: the pictures dropped straight on the scene, then one
        // line per linked mood board and what hangs under its heading.
        // `--shutsection "Night Exteriors"` shuts a heading in the References
        // panel, or opens it again — `scene` for the scene's own pictures. A
        // tap cannot reach this panel (it lands on the container), so without
        // this the heading a hand can shut would be a thing no run can press.
        for (at, flag) in args.enumerated()
        where flag == "--shutsection" && at + 1 < args.count {
            let wanted = args[at + 1].lowercased()
            let id = wanted == "scene" ? "scene"
                : (state.view?.boards ?? []).first { $0.name.lowercased() == wanted }?.id
            if let id {
                if BoardFocus.shared.shut.contains(id) {
                    BoardFocus.shared.shut.remove(id)
                } else {
                    BoardFocus.shared.shut.insert(id)
                }
            }
        }
        // `--drivefolder <path>` says where this film lives in Drive, the way
        // Project Settings' folder picker does. Without it nothing about the
        // switches below can be checked at all: the switch is deliberately
        // dead until the film itself is linked, and `--link` needs one of his
        // real Projects Console projects to exist, which a scratch copy in a
        // temporary folder is not.
        if let at = args.firstIndex(of: "--drivefolder"), at + 1 < args.count {
            Linking.setFolder(args[at + 1], state: state)
        }
        // **Sync with Drive** — Ref 229/343. `--drivesync "The Mansion" 0`
        // flips a location's switch by name and `--drivesync "Tone" 1` a
        // board's; `--drivesays` prints every switch in the film. A place and a
        // board cannot share a name here, and if they ever did the location
        // wins — which is worth nothing except that a check is never ambiguous.
        for (at, flag) in args.enumerated() where flag == "--drivesync" && at + 2 < args.count {
            let wanted = args[at + 1]
            let value = args[at + 2] == "1" ? "1" : "0"
            if let place = state.view?.locations.first(where: {
                $0.name.caseInsensitiveCompare(wanted) == .orderedSame
            }) {
                state.replace(state.engine?.setLocation(place.id, "syncWithDrive", value))
            } else if let board = state.view?.boards.first(where: {
                $0.name.caseInsensitiveCompare(wanted) == .orderedSame
            }) {
                state.replace(state.engine?.set(shot: board.id, field: "sync_with_drive",
                                                value: value))
            }
        }
        if args.contains("--drivesays") {
            let folder = (state.view?.project.driveFolder ?? "")
                .trimmingCharacters(in: .whitespaces)
            FileHandle.standardError.write(Data((
                "drive: film linked=\(folder.isEmpty ? "no" : "yes")\n").utf8))
            for place in state.view?.locations ?? [] {
                FileHandle.standardError.write(Data((
                    "drive: location \(place.name.isEmpty ? "Untitled" : place.name) "
                    + "on=\(place.syncsWithDrive ? "yes" : "no") "
                    + "folder=\"\(place.driveFolder)\"\n").utf8))
            }
            for board in state.view?.boards ?? [] {
                FileHandle.standardError.write(Data((
                    "drive: board \(board.name.isEmpty ? "Untitled" : board.name) "
                    + "on=\(board.syncsWithDrive ? "yes" : "no") "
                    + "folder=\"\(board.driveFolder)\"\n").utf8))
            }
        }
        if args.contains("--referencessay"), let standing = state.scene {
            let live = state.view?.scenes.first { $0.id == standing.id } ?? standing
            let names = { (all: [ViewModel.Attachment]) in
                all.map(\.filename).joined(separator: ",")
            }
            let open = { (id: String) in BoardFocus.shared.shut.contains(id) ? "no" : "yes" }
            FileHandle.standardError.write(Data((
                "references: This scene pictures=\(live.attachments.count) "
                + "open=\(open("scene")) [\(names(live.attachments))]\n").utf8))
            for id in live.boards {
                guard let hung = state.view?.boards.first(where: { $0.id == id }) else { continue }
                FileHandle.standardError.write(Data((
                    "references: \(hung.name.isEmpty ? "Untitled" : hung.name) "
                    + "pictures=\(hung.media.count) open=\(open(hung.id)) "
                    + "[\(names(hung.media))]\n").utf8))
            }
            FileHandle.standardError.write(Data((
                "references: sections=\(1 + live.boards.count)\n").utf8))
        }
        // `--deletecolumn "Rigging"` takes a column away by its label, the way
        // the column's own page does behind its confirmation.
        if let at = args.firstIndex(of: "--deletecolumn"), at + 1 < args.count {
            let wanted = args[at + 1]
            if let field = (state.view?.columns ?? [])
                .map(\.name)
                .first(where: { Columns.label($0).caseInsensitiveCompare(wanted) == .orderedSame }) {
                state.replace(state.engine?.deleteColumn(field: field))
            }
        }
        // `--pickscenes 33,34` picks several in the sidebar — Ref 240. By
        // number, because a check written against ids would have to be
        // rewritten every time the fixture is rebuilt.
        for (at, flag) in args.enumerated()
        where flag == "--pickscenes" && at + 1 < args.count {
            let wanted = Set(args[at + 1].split(separator: ",").map(String.init))
            let picked = (state.view?.scenes ?? [])
                .filter { wanted.contains($0.number) }
                .map(\.id)
            state.sceneSelection = Set(picked)
        }
        // `--pickedlocation "Kitchen"` points every picked scene at it,
        // through the same method the menu calls.
        for (at, flag) in args.enumerated()
        where flag == "--pickedlocation" && at + 1 < args.count {
            let wanted = args[at + 1].lowercased()
            let place = (state.view?.locations ?? []).first { $0.name.lowercased() == wanted }
            state.setLocation(on: Array(state.pickedScenes), to: place?.id ?? "")
        }
        // `--pickedtime SUNSET` sets the time of day on every picked scene,
        // through the same method the right-click menu calls. `--pickedtime ""`
        // clears it, which is the menu's "None".
        for (at, flag) in args.enumerated()
        where flag == "--pickedtime" && at + 1 < args.count {
            state.setTimeOfDay(on: Array(state.pickedScenes), to: args[at + 1])
        }
        // `--scenetimes` says what every scene's time of day is now.
        //
        // **The one thing a photograph cannot check.** The dot the sidebar
        // draws is a colour, and a screenshot of four coloured dots proves
        // nothing about which scene holds which word — so the words are said
        // out loud instead.
        if args.contains("--scenetimes") {
            let said = (state.view?.scenes ?? []).map { scene in
                "\(scene.number)=\(scene.timeOfDay.isEmpty ? "—" : scene.timeOfDay)"
            }.joined(separator: " | ")
            FileHandle.standardError.write(Data(("scene times: " + said + "\n").utf8))
        }
        // `--photoshape original|square|project` — how the wall of
        // photographs is shaped. All three need photographing, and a checking
        // run must never write his real preference to get there.
        for (at, flag) in args.enumerated()
        where flag == "--photoshape" && at + 1 < args.count {
            state.locationRatioMode = args[at + 1]
        }
        // `--deletescene` throws the open scene away, if it is archived.
        if args.contains("--deletescene"), let engine = state.engine, let scene = state.scene {
            state.replace(engine.deleteScene(scene.id))
        }
        if args.contains("--settletimes") { state.replace(state.engine?.settleTimes()) }
        if args.contains("--setup") { state.settingUp = true }
        if args.contains("--newcard") { state.makingCard = true }
        if args.contains("--syncsetup") {
            state.settingUpSync = true
            FileHandle.standardOutput.write(Data("sync setup: shown\n".utf8))
        }
        // `--syncsave <address> <word>` does exactly what the sheet's Save
        // does, then says whether the sync button would now be drawn — the
        // whole journey a Mac that has never synced has to make.
        if let at = args.firstIndex(of: "--syncsave"), at + 2 < args.count {
            // **Refuses a half-filled pair, because the sheet's Save cannot
            // send one.** There the guard is a disabled button; here it has to
            // be said out loud, or this door would exercise a journey he can
            // never take — an empty password is *forget it*, which is the
            // Forget button's job and not Save's.
            let wanted = args[at + 2].trimmingCharacters(in: .whitespacesAndNewlines)
            let why: String?
            if Relay.tidy(args[at + 1]).isEmpty {
                why = "No address yet."
            } else if wanted.isEmpty {
                why = "No password yet."
            } else {
                why = Relay.remember(address: args[at + 1]) ?? Relay.remember(token: wanted)
            }
            FileHandle.standardOutput.write(Data((
                "sync save: \(why ?? "saved")\n" +
                "sync ready: \(Relay.ready)\n").utf8))
        }
        // `--wholescript` opens the reading window on the scene the run is
        // standing on, so the one thing the side panel cannot show — the script
        // at a size somebody would actually read — can be photographed.
        if args.contains("--wholescript") {
            ScriptWindow.read(state: state, scene: state.scene?.number)
        }
        // `--wholescriptwindow` opens our own reader even when the draft kept
        // its file (the usual case opens Preview), so its marks can be
        // photographed with `--window script`.
        if args.contains("--wholescriptwindow") {
            ScriptWindow.shared.show(state: state, scene: state.scene?.number)
        }
        // `--schedule` opens the strip board, and `--addday` puts a day on it,
        // so the one screen with no cell to type into can still be driven and
        // photographed. Photograph it with `--window schedule`.
        if args.contains("--schedule") {
            ScheduleWindow.shared.show(state: state)
        }
        if args.contains("--addday") { state.addDay() }
        // `--dayname 1 "Second unit"`, `--daydate 1 2026-09-12`,
        // `--dayremove 2`, `--daymove 3 0` — the four things the day band's
        // menu does, by the number the band wears rather than by an id nobody
        // outside the engine can know. Ref 341: a right-click menu cannot be
        // opened by a synthetic click, so without these the whole feature is
        // unreachable by anything that checks.
        for (at, flag) in args.enumerated() where flag == "--dayname" && at + 2 < args.count {
            if let day = Self.day(args[at + 1], state) { state.nameDay(day.id, args[at + 2]) }
        }
        for (at, flag) in args.enumerated() where flag == "--daydate" && at + 2 < args.count {
            if let day = Self.day(args[at + 1], state) { state.dateDay(day.id, args[at + 2]) }
        }
        for (at, flag) in args.enumerated() where flag == "--dayremove" && at + 1 < args.count {
            if let day = Self.day(args[at + 1], state) { state.removeDay(day.id) }
        }
        for (at, flag) in args.enumerated() where flag == "--daymove" && at + 2 < args.count {
            if let day = Self.day(args[at + 1], state),
               let index = Int(args[at + 2]) { state.moveDay(day.id, to: index) }
        }
        // `--colourterm size M/OTS 2F7A44` — Ref 55. The recolour menu is a
        // menu inside a sheet, which no synthetic click can reach, so this is
        // the door that makes the feature checkable at all.
        for (at, flag) in args.enumerated()
        where flag == "--colourterm" && at + 3 < args.count {
            state.colourTerm(field: args[at + 1], value: args[at + 2],
                             hex: args[at + 3])
        }
        // `--setmark Star #448361` — the film's own icon and colour, set the
        // way the grid in Project Settings sets them. That grid is inside a
        // sheet, and no synthetic click reaches one, so this is the door that
        // makes the hand-set half checkable — and photographable, since the
        // window behind wears the result.
        //
        // `--setmark none` clears it, which on a linked film is *Take from
        // Notion*: the mirror is free again the moment nothing is hand-set.
        for (at, flag) in args.enumerated()
        where flag == "--setmark" && at + 1 < args.count {
            let named = args[at + 1]
            if named == "none" {
                state.clearTheMark()
            } else if let shape = Marks.shapes.first(where: { $0.name == named }) {
                let colour = at + 2 < args.count && args[at + 2].hasPrefix("#")
                    ? args[at + 2] : Marks.firstHue
                state.setTheMark(path: shape.path, colour: colour)
            }
        }
        // `--setdirector "Name"` writes the film's director the way the New
        // Project sheet does; `--setdirector none` clears it. The Projects
        // Console's door, 2026-09-15, so a linked film can be made to say what
        // its Notion row's Director relation says. Said back on stderr.
        for (at, flag) in args.enumerated()
        where flag == "--setdirector" && at + 1 < args.count {
            if let engine = state.engine, let id = state.view?.project.id {
                let named = args[at + 1] == "none" ? "" : args[at + 1]
                state.replace(engine.set(shot: id, field: "director",
                                         value: named.trimmingCharacters(in: .whitespaces)))
                FileHandle.standardError.write(Data((
                    "director: \"\(state.view?.project.director ?? "")\"\n").utf8))
            }
        }
        // `--recordfacts '{"title":"Let's Bake","director":"…"}'` — **the
        // project record's facts, into the film.** The Projects Console's
        // door (one-record plan, 2026-10-05), the same way `--link` and
        // `--setdirector` are: the console never writes a film, it asks the
        // program that owns it. One JSON object of words to values — `title`
        // (the name the film is shown by), `director`, `producer`, `client`,
        // `agency` — and only those given are written. Anything else in it
        // and the engine refuses the lot. `--recordfacts none` lets go.
        // Touches the project record and nothing else: never a scene, a
        // shot, a day. Said back on stderr.
        if let at = args.firstIndex(of: "--recordfacts"), at + 1 < args.count,
           let engine = state.engine {
            let said = args[at + 1]
            if said == "none" {
                state.replace(engine.letGoOfRecordFacts())
                FileHandle.standardError.write(Data("facts: let go\n".utf8))
            } else if let bytes = said.data(using: .utf8),
                      let given = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] {
                // **A credit may come as a list of names** (2026-10-05, more
                // than one person per credit): joined by the Unit Separator,
                // and the engine makes the credit's one line ("A & B").
                // A plain string is taken as it always was.
                let pairs: [(String, String)] = given.keys.sorted().map { key in
                    if let names = given[key] as? [String] {
                        return (key, names.joined(separator: "\u{1f}"))
                    }
                    return (key, given[key] as? String ?? "")
                }
                let before = state.view?.project
                if let after = engine.takeRecordFacts(pairs) {
                    let changed = [("title", before?.shownTitle, after.project.shownTitle),
                                   ("director", before?.director, after.project.director),
                                   ("producer", before?.producer, after.project.producer),
                                   ("client", before?.client, after.project.client),
                                   ("agency", before?.agency, after.project.agency)]
                        .filter { $0.1 != $0.2 }.map(\.0)
                    state.replace(after)
                    state.engine?.save()
                    FileHandle.standardError.write(Data((
                        "facts: taken \(changed.isEmpty ? "nothing new" : changed.joined(separator: ","))\n").utf8))
                } else {
                    FileHandle.standardError.write(Data("facts: refused\n".utf8))
                }
            } else {
                FileHandle.standardError.write(Data("facts: refused — not a list of facts\n".utf8))
            }
        }
        // `--factssays` — the facts the film shows and where they come from,
        // one line, for the console to read back after `--recordfacts`.
        if args.contains("--factssays") {
            let project = state.view?.project
            var line = "facts: title \"\(project?.shownTitle ?? "")\""
            line += "  director \"\(project?.director ?? "")\""
            line += "  producer \"\(project?.producer ?? "")\""
            line += "  client \"\(project?.client ?? "")\""
            line += "  agency \"\(project?.agency ?? "")\""
            line += "  source \(project?.factsFromRecord == true ? "record" : "film")\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        // `--cardpng <path>` — the Project card, drawn offscreen to a PNG
        // (light, or dark with `--appearance dark`), then the run ends.
        if let at = args.firstIndex(of: "--cardpng"), at + 1 < args.count {
            let dark = args.firstIndex(of: "--appearance").map { $0 + 1 < args.count && args[$0 + 1] == "dark" } ?? false
            let made = MainActor.assumeIsolated { NameCard.photograph(state: state, to: args[at + 1], dark: dark) }
            FileHandle.standardError.write(Data("card: picture \(made ? "written" : "failed")\n".utf8))
            if Self.checking { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.finish() } }
        }
        // **The console's door ends its own run.** A checking run otherwise
        // ends off its window, and with the screen locked a run with flags
        // gets no window (Ref 1195) — so `--setdirector` and `--filmsays` sit
        // until the console's two-minute limit kills them, and the console
        // reads a write that landed as one that did not. Asked nothing else,
        // one of these has already written (every change saves as it lands,
        // in `replace`) and said so; it goes. **Only when every flag on the
        // line is one of the console's doors** — a check that adds anything
        // else is waiting on a window for a reason and keeps the old ending.
        let doors: Set<String> = ["--project", "--recordfacts", "--factssays",
                                  "--setdirector", "--filmsays",
                                  "--appearance", "--device"]
        let flags = args.dropFirst().filter { $0.hasPrefix("--") }
        if Self.checking, !flags.isEmpty, flags.allSatisfy(doors.contains),
           flags.contains(where: { $0 != "--project" && $0 != "--appearance" && $0 != "--device" }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.finish() }
        }
        // `--filmsays` — the film's own card, one line, for the console's
        // readout: title, director, producer, which console project it is,
        // and where its Drive folder and its package are.
        if args.contains("--filmsays") {
            let project = state.view?.project
            // Built up a line at a time: as one expression the type-checker
            // gave up on it under Xcode 27 (2026-09-20).
            var film = "film: title \"\(project?.title ?? "")\""
            film += "  director \"\(project?.director ?? "")\""
            film += "  producer \"\(project?.producer ?? "")\""
            film += "  console \"\(project?.consoleName ?? "")\""
            film += "  folder \"\(project?.driveFolder ?? "")\""
            film += "  path \"\(state.projectPath?.path ?? "")\"\n"
            FileHandle.standardError.write(Data(film.utf8))
        }
        // What the film says it wears, and who said so — the three stored
        // strings, read back out of the engine's own answer.
        if args.contains("--marksays") {
            let project = state.view?.project
            FileHandle.standardError.write(Data((
                "mark: colour \(project?.markColour ?? "none")"
                + "  source \(project?.markSource.isEmpty == false ? project!.markSource : "none")"
                + "  outline \(project?.markPath.isEmpty == false ? "yes" : "no")"
                + "  accent \(Brand.wearing.isEmpty ? "default" : Brand.wearing)\n").utf8))
        }
        if args.contains("--coloursay") {
            for (key, hex) in Brand.termInks.sorted(by: { $0.key < $1.key }) {
                FileHandle.standardError.write(Data((
                    "colour: \(key.replacingOccurrences(of: "\u{1}", with: " / "))"
                    + " = \(hex)\n").utf8))
            }
            FileHandle.standardError.write(Data((
                "colours: \(Brand.termInks.count)\n").utf8))
        }
        // `--putday 3 1` drops Day 3's band above Day 1's — the drop handler's
        // own path, because a drag is a session and no synthetic mouse can
        // perform one. Same bargain as `--puton` and `--putshot`.
        for (at, flag) in args.enumerated() where flag == "--putday" && at + 2 < args.count {
            if let day = Self.day(args[at + 1], state),
               let onto = Self.day(args[at + 2], state) {
                state.moveDay(day.id, above: onto.id)
            }
        }
        // `--daysheet name 1` / `--daysheet date 1` opens the sheet the band's
        // menu opens, so the two sheets can be photographed.
        if let at = args.firstIndex(of: "--daysheet"), at + 2 < args.count,
           let day = Self.day(args[at + 2], state) {
            if args[at + 1] == "date" { state.datingDay = day.id }
            else { state.namingDay = day.id }
        }
        // The calendar panel, from the outside — his ask, 2026-08-28.
        // `--calendar` opens the panel beside the board, `--month 2026-09`
        // pins the month a deterministic check needs, and `--clickdate
        // 2026-09-20` presses a date cell through the same funnel the cell
        // itself calls, printing the funnel's own answer — `added Day 3
        // 2026-09-20`, or `highlighted Day 3` for a date already held.
        if args.contains("--calendar") { state.calendarShown = true }
        // The Synopsis button, from the outside.
        if args.contains("--synopsis") { state.stripSynopsis = true }
        if args.contains("--shootingorder") { state.stripRun = true }
        // `--nudgeshot 1A down` — a shot's Move Up / Move Down on Shooting
        // Order, through the menu's own path, which no synthetic click opens.
        for (at, flag) in args.enumerated() where flag == "--nudgeshot" && at + 2 < args.count {
            state.loadBoard()
            let wanted = args[at + 1]
            for day in state.stripBoard?.days ?? [] {
                if let shot = day.run.first(where: { $0.number == wanted }) {
                    state.nudgeShotInDay(shot.placement, day: day.id, up: args[at + 2] == "up")
                    break
                }
            }
        }
        // `--openstrip 33` opens a strip the way its chevron does, which is
        // the only way its synopsis is on screen to be photographed.
        for (at, flag) in args.enumerated() where flag == "--openstrip" && at + 1 < args.count {
            state.loadBoard()
            let wanted = args[at + 1]
            let strips = (state.stripBoard?.days ?? []).flatMap(\.strips)
            if let strip = strips.first(where: { $0.number == wanted }) {
                state.openStrips.insert(strip.scene)
            }
        }
        // `--offday 35` takes a scene off whatever day it is on, through the
        // strip menu's own path. A context menu cannot be opened by a
        // synthetic click, so without this the one way to remove a scene from
        // the schedule is unverifiable — the bargain `--daysheet` strikes.
        for (at, flag) in args.enumerated() where flag == "--offday" && at + 1 < args.count {
            state.loadBoard()
            let wanted = args[at + 1]
            let strips = (state.stripBoard?.days ?? []).flatMap(\.strips)
            if let strip = strips.first(where: { $0.number == wanted }) {
                state.assign(scene: strip.scene, day: nil)
                FileHandle.standardError.write(Data(
                    "off day: scene \(wanted)\n".utf8))
            } else {
                FileHandle.standardError.write(Data(
                    "off day: no scene \(wanted) on any day\n".utf8))
            }
        }
        // What the strips would show as a synopsis, so the one thing that is
        // read rather than stored can be checked at all.
        if args.contains("--synopsissay") {
            state.loadBoard()
            FileHandle.standardError.write(Data((
                "synopsis showing: \(state.stripSynopsis ? "yes" : "no")\n").utf8))
            for day in state.stripBoard?.days ?? [] {
                for strip in day.strips {
                    let said = state.view?.scenes.first { $0.id == strip.scene }?.description ?? ""
                    FileHandle.standardError.write(Data((
                        "synopsis: \(strip.number) = "
                        + "\(said.isEmpty ? "none" : said)\n").utf8))
                }
            }
        }
        if let at = args.firstIndex(of: "--month"), at + 1 < args.count {
            state.calendarMonth = args[at + 1]
        }
        for (at, flag) in args.enumerated() where flag == "--clickdate" && at + 1 < args.count {
            state.loadBoard()
            let said = state.calendarTap(args[at + 1])
            FileHandle.standardError.write(Data("calendar: \(said)\n".utf8))
        }
        // `--putdate 1 2026-08-30` drops Day 1's band on a calendar date —
        // the drop handler's own path, the bargain `--putday` strikes.
        for (at, flag) in args.enumerated() where flag == "--putdate" && at + 2 < args.count {
            if let day = Self.day(args[at + 1], state) {
                state.dropDay(day.id, onDate: args[at + 2])
            }
        }
        if args.contains("--sortdays") {
            state.loadBoard()
            state.sortDaysByDate()
        }
        // What the calendar marks, and whether the dates disagree with the
        // numbers — the condition the *Put days in date order* button lives on.
        if args.contains("--calendarsays") {
            state.loadBoard()
            for day in state.stripBoard?.days ?? [] where !day.date.isEmpty {
                FileHandle.standardError.write(Data(
                    "marked: \(day.date) = \(day.label) · \(day.count)\n".utf8))
            }
            FileHandle.standardError.write(Data((state.daysOutOfDateOrder
                ? "order: out of date order\n"
                : "order: dated days in order\n").utf8))
        }
        // The dots each band wears, read from the band's own helper so what
        // the check says is what the band shows.
        if args.contains("--daydots") {
            state.loadBoard()
            for day in state.stripBoard?.days ?? [] {
                let keys = Schedule.dotKeys(day.strips)
                FileHandle.standardError.write(Data((
                    "dots: \(day.label) = "
                    + "\(keys.isEmpty ? "none" : keys.joined(separator: ","))\n").utf8))
            }
        }
        // **The live workbook link, from the outside** — SL-375.
        //
        // The link is made by ticking a box in a save panel and kept current
        // by a timer inside `ShellState.replace`; neither is anything a
        // checking run can reach, so without these two doors the whole
        // feature would be unverifiable. Same bargain `--putday` strikes with
        // the drop handler: call the real path, not a copy of it.
        if let at = args.firstIndex(of: "--excellink"), at + 1 < args.count {
            Exporting.link(args[at + 1], state: state)
            FileHandle.standardError.write(Data(
                "excel link: \(state.view?.project.excelPath ?? "")\n".utf8))
        }
        // The auto-update switch, apart from the link itself — his ask,
        // 2026-08-27. Only reachable in the app from a toggle inside Project
        // Settings, which is a sheet and so cannot be photographed at all
        // (Ref 366); this is the only way the switch's actual effect on
        // `refreshLinkedWorkbook` can be proven.
        if let at = args.firstIndex(of: "--excelauto"), at + 1 < args.count {
            Exporting.setAutoUpdate(args[at + 1] == "on", state: state)
            FileHandle.standardError.write(Data(
                "excel auto: \(Exporting.autoUpdateEnabled(for: state.view?.project))\n".utf8))
        }
        // **Which program the workbook is laid out for** — the same door, and
        // for the same reason: the dropdown lives in Settings, whose pane
        // scrolls and cannot be scrolled by a check. Without this there is no
        // way to prove that choosing *Excel* actually puts the pictures back in
        // the file.
        if let at = args.firstIndex(of: "--excelframes"), at + 1 < args.count {
            Exporting.setFrameStyle(args[at + 1] == "file" ? .forExcel : .forGoogleSheets, state: state)
            FileHandle.standardError.write(Data(
                "excel frames: \(Exporting.frameStyle(for: state.view?.project).rawValue)\n".utf8))
        }
        // Rewrite now rather than in three seconds — the debounce is the
        // app's manners, not the behaviour under test, and a check should not
        // have to sleep to see whether the file follows the project.
        if args.contains("--excelnow") {
            let wrote = Exporting.refreshLinkedWorkbook(state: state)
            FileHandle.standardError.write(Data("excel wrote: \(wrote)\n".utf8))
        }
        // Project Settings' own "Export now" — same door problem, different
        // button: it must write even when the automatic switch is off, which
        // is the one case `--excelnow` above will never exercise.
        if args.contains("--excelmanual") {
            Exporting.exportLinkedWorkbookNow(state: state)
            let path = state.view?.project.excelPath ?? ""
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
            FileHandle.standardError.write(Data("excel manual bytes: \(size ?? 0)\n".utf8))
        }
        // A folder per shoot day, without the folder picker no synthetic
        // click can open. Matches the PDF export dialog's own defaults
        // (Table only, landscape, its own text size) rather than the
        // dialog's per-day scope, which also lets him choose these. A third,
        // optional argument narrows to specific days — comma-separated
        // *positions* (`2` for the second day on the board, same addressing
        // `--daysheet`/`--puton` already use, since a day has no name of its
        // own until he gives it one and its real id is the engine's
        // business), or `unscheduled` — the only way the dialog's own Days
        // picker can be proven through at all (Ref 366).
        if let at = args.firstIndex(of: "--exportdays"), at + 1 < args.count {
            let days = state.view?.days ?? []
            let only: Set<String>? = (at + 2 < args.count && !args[at + 2].hasPrefix("--"))
                ? Set(args[at + 2].split(separator: ",").compactMap { said -> String? in
                    if said == "unscheduled" { return Exporting.unscheduledDayId }
                    guard let index = Int(said), index >= 1, index <= days.count else { return nil }
                    return days[index - 1].id
                })
                : nil
            // `--framesize small|medium|large` beside it, so the one dial
            // the export dialog carries can be driven from a checking run —
            // the dialog itself cannot be clicked by one.
            let size = args.firstIndex(of: "--framesize")
                .flatMap { $0 + 1 < args.count ? Printing.FrameSize(rawValue: args[$0 + 1]) : nil }
                ?? .medium
            // Each view on its own paper, at its own size — the same shape
            // the box builds now. `--framesize` still speaks for all three,
            // because it always has and no check should have to name them.
            let looks = ["table", "storyboard", "document"]
                .reduce(into: [String: Printing.Look]()) {
                    $0[$1] = Printing.Look.standard(for: $1, frames: size)
                }
            // `--daysections diagram` (or `table,diagram`): which pages each
            // day's file holds, so a day's diagrams can be checked.
            let sections = args.firstIndex(of: "--daysections")
                .flatMap { $0 + 1 < args.count ? args[$0 + 1].split(separator: ",").map(String.init) : nil }
                ?? ["table"]
            Exporting.exportEachDay(
                state: state,
                sections: sections,
                looks: looks,
                // The checks read the workbook a day package writes; the
                // box itself starts with it off.
                alsoWorkbook: true,
                onlyDays: only,
                into: URL(fileURLWithPath: args[at + 1], isDirectory: true)
            )
        }
        if args.contains("--excelsays") {
            let path = state.view?.project.excelPath ?? ""
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
            FileHandle.standardError.write(Data((
                "excel path: \(path.isEmpty ? "none" : path)"
                + "  auto: \(Exporting.autoUpdateEnabled(for: state.view?.project))"
                + "  exists: \(FileManager.default.fileExists(atPath: path))"
                + "  bytes: \(size ?? 0)\n").utf8))
        }
        // What the days are, in order, with everything a band draws.
        if args.contains("--dayssay") {
            state.loadBoard()
            for day in state.stripBoard?.days ?? [] {
                FileHandle.standardError.write(Data((
                    "day: \(day.label)  name=\"\(day.title)\"  date=\"\(day.date)\""
                    + "  shots=\(day.count)\n").utf8))
            }
            FileHandle.standardError.write(Data((
                "days: \((state.stripBoard?.days ?? []).count)"
                + "  waiting: \((state.stripBoard?.unscheduled ?? []).count)\n").utf8))
        }
        // `--template Cast` adds a ready-made column through the same call the
        // "From template" menu makes. A menu inside a sheet cannot be driven
        // by a synthetic click, so this is how the list itself is checkable —
        // and it reports whether the project already had one, which is the
        // guard that stops a second *Cast* appearing beside the first.
        if let at = args.firstIndex(of: "--template"), at + 1 < args.count {
            let wanted = args[at + 1]
            guard let ready = ColumnTemplates.named(wanted) else {
                FileHandle.standardError.write(Data((
                    "template: no ready-made column called \(wanted)\n").utf8))
                return
            }
            let already = ColumnTemplates.has(ready.label, in: state.view?.columns ?? [])
            FileHandle.standardError.write(Data((
                "template: \(ready.label) kind=\(ready.kind) already=\(already)\n").utf8))
            if !already { ColumnTemplates.add(ready, state: state) }
        }
        // Every ready-made column the sheet offers, so the list can be read
        // without opening a menu.
        if args.contains("--templates") {
            for (group, ready) in ColumnTemplates.groups {
                let said = ready
                    .map { "\($0.label):\($0.kind)"
                         + (ColumnTemplates.has($0.label, in: state.view?.columns ?? [])
                            ? "(already)" : "") }
                    .joined(separator: ", ")
                FileHandle.standardError.write(Data((
                    "templates: \(group) — \(said)\n").utf8))
            }
        }
        // `--puton 35 2` drops scene 35 onto Day 2; `--puton 35 none` puts it
        // back in the waiting column. **This is the drop handler's own call**,
        // not a second path beside it — a synthetic mouse cannot drive an
        // `onDrag`/`onDrop` pair (that is a dragging *session*, not a click),
        // so this is how the board's one gesture is checkable at all. What it
        // does not prove is the pixels; that is a hand's job, and it is on the
        // hands script.
        if let at = args.firstIndex(of: "--puton"), at + 2 < args.count {
            let wanted = args[at + 1]
            let onto = args[at + 2]
            state.loadBoard()
            let scene = state.view?.scenes.first { $0.number == wanted }?.id
            let day = onto == "none"
                ? nil
                : state.stripBoard?.days.first { $0.label == "Day \(onto)" }?.id
            if let scene {
                state.assign(scene: scene, day: day)
            } else {
                FileHandle.standardError.write(Data("puton: no scene \(wanted)\n".utf8))
            }
        }
        // `--putshot 34C 2` pulls one shot out of its scene onto another day —
        // the other half of the drop handler, and the case the board exists
        // for: a scene that will not finish in an afternoon becomes two strips.
        if let at = args.firstIndex(of: "--putshot"), at + 2 < args.count {
            let wanted = args[at + 1]
            let onto = args[at + 2]
            state.loadBoard()
            let placement = (state.stripBoard?.days.flatMap(\.strips) ?? [])
                + (state.stripBoard?.unscheduled ?? [])
            let shot = placement.flatMap(\.shots).first { $0.number == wanted }?.placement
            let day = onto == "none"
                ? nil
                : state.stripBoard?.days.first { $0.label == "Day \(onto)" }?.id
            if let shot {
                state.assign(placement: shot, day: day)
            } else {
                FileHandle.standardError.write(Data("putshot: no shot \(wanted)\n".utf8))
            }
        }
        // What the board says, one line a day, so a check can read it without
        // a picture — and so a relaunch can be asked whether the move stuck.
        if args.contains("--boardsays") {
            state.loadBoard()
            let board = state.stripBoard
            for day in board?.days ?? [] {
                let scenes = day.strips
                    .map { $0.elsewhere.isEmpty ? $0.number
                                                : "\($0.number)(also \($0.elsewhere.joined(separator: "/")))" }
                    .joined(separator: ",")
                FileHandle.standardError.write(Data((
                    "board: \(day.label) shots=\(day.count) "
                    + "scenes=[\(scenes)]\n").utf8))
            }
            let waiting = (board?.unscheduled ?? []).map(\.number).joined(separator: ",")
            FileHandle.standardError.write(Data("board: waiting=[\(waiting)]\n".utf8))
        }
        // `--rename <title>` names the film and lets the package follow, which
        // is the one thing in the setup screen that moves a folder on disk.
        // Nothing else in the harness can reach it: the sheet's own path runs
        // off a text field and a button.
        if let at = args.firstIndex(of: "--rename"), at + 1 < args.count,
           let engine = state.engine, let id = state.view?.project.id {
            state.replace(engine.set(shot: id, field: "title", value: args[at + 1]))
            state.renameFileToTitle()
            let stem = state.projectPath?.deletingPathExtension().lastPathComponent ?? ""
            FileHandle.standardError.write(Data((
                "renamed: title \"\(state.view?.project.title ?? "")\""
                + "  file \"\(stem)\"\n").utf8))
        }
        // `--link "Call Her Back"` ties this project to one of his Projects
        // Console projects by name and then goes looking for the matching
        // folder on this Mac — the whole chain, including the part that reads
        // Google Drive's own id off a folder, which nothing else can check.
        if let at = args.firstIndex(of: "--link"), at + 1 < args.count {
            let wanted = args[at + 1]
            let one = Console.projects().first { $0.name == wanted }
            Linking.link(one, state: state)
            if one != nil, let found = Linking.findFolder(state: state) {
                Linking.setFolder(found.path, state: state)
            }
            FileHandle.standardError.write(Data((
                "linked: \"\(state.view?.project.consoleName ?? "")\""
                + "  folder \"\(state.view?.project.driveFolder ?? "")\"\n").utf8))
        }
        // `--linkpage <page id> "Name"` — the same link, to a page the
        // console has never heard of. Only a check needs it: the archive door
        // finds a film by its page, and a check must use a page that is no
        // real project's, so nothing of his can ever answer to it.
        if let at = args.firstIndex(of: "--linkpage"), at + 2 < args.count {
            let one = Console.Project(pageId: args[at + 1], name: args[at + 2], status: "", kind: "",
                                      dates: "", driveUrl: "", notionUrl: "", iconSvg: "", iconColour: "")
            Linking.link(one, state: state)
            FileHandle.standardError.write(Data((
                "linked: \"\(state.view?.project.consoleName ?? "")\"  page \"\(state.view?.project.consolePage ?? "")\"\n").utf8))
        }
        if args.contains("--editing") { state.editing = true }
        // `--set <column> <value>` writes one field on the cursor's row through
        // the engine. It exists because a checking run that types words into a
        // real project has to be able to put them back; an empty value clears.
        if let at = args.firstIndex(of: "--set"), at + 1 < args.count {
            let column = args[at + 1]
            let value = at + 2 < args.count ? args[at + 2] : ""
            if let engine = state.engine,
               let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
                state.replace(engine.set(shot: row.shot, field: column, value: value))
                FileHandle.standardError.write(Data((
                    "set \(column) to \"\(value)\" on \(row.number)\n").utf8))
            }
        }
        // `--facet <field> <value>` narrows the list the way the filter bar's
        // menus do — the menus themselves are AppKit's and do not open under
        // a synthetic click, so this is how the narrowing is checked.
        if let at = args.firstIndex(of: "--facet"), at + 2 < args.count,
           let engine = state.engine {
            let field = args[at + 1]
            // A location is narrowed by id, and nothing at a command line knows
            // an id — so a name is accepted here and turned into one.
            var value = args[at + 2]
            if field == "location_id", !value.isEmpty {
                value = (state.view?.locations ?? [])
                    .first { $0.name.caseInsensitiveCompare(value) == .orderedSame }?
                    .id ?? value
            }
            if value.isEmpty { state.facets.removeValue(forKey: field) }
            else { state.facets[field] = value }
            state.replace(engine.facet(field, value))
        }
        // `--find <words>` is the filter bar's search box.
        if let at = args.firstIndex(of: "--find"), at + 1 < args.count,
           let engine = state.engine {
            state.replace(engine.filter(text: args[at + 1], hideStruck: false))
        }
        // `--scroll <points>` rolls the wheel over the middle of the window,
        // positive being downward. The table is the whole script now and the
        // chrome follows the scene being *read*, which cannot be checked
        // without something that actually reads its way down.
        if let at = args.firstIndex(of: "--scroll"), at + 1 < args.count,
           let points = Double(args[at + 1]) {
            // **It waits for the window now.** This fired at a fixed six
            // tenths of a second and looked the window up by an identifier
            // nothing sets, so it returned silently and *scrolled nothing* —
            // for weeks. Two runs a moment apart, one with the flag and one
            // without, produced snapshots identical byte for byte. That is
            // the "a check can be wrong in the other direction" trap in
            // STATUS, and the reason the door now says how far it moved.
            whenReady { window in
                let before = ShellState.shared.tableOffset
                Self.wheel(points, over: 20, in: window) {
                    let after = ShellState.shared.tableOffset
                    FileHandle.standardError.write(Data((
                        String(format: "scroll: %.0f → %.0f (asked for %.0f)\n",
                               before, after, points)).utf8))
                }
            }
        }
        // **`--churn <seconds>` is the freeze, driven.**
        //
        // His report, 2026-08-29: *"the app just froze when switching between
        // scenes and scrolling quickly through the shot list."* Nothing here
        // could reproduce that: `--scroll` is one flick of four tenths of a
        // second, and a freeze is what happens when the wheel keeps turning
        // while the scene keeps changing. So this does both, hard, for as long
        // as it is asked to — and, because a stutter cannot be photographed,
        // it measures the thing he actually felt: **the longest the window
        // went without answering.**
        //
        // A timer set for every sixtieth of a second can only be late if the
        // main thread was busy, so the worst lateness *is* the freeze, in
        // milliseconds. Nothing else in this app can see that number.
        if let at = args.firstIndex(of: "--churn"), at + 1 < args.count,
           let seconds = Double(args[at + 1]) {
            whenReady { window in
                let state = ShellState.shared
                let scenes = (state.view?.scenes ?? []).filter { !$0.archived }.map(\.id)
                let began = DispatchTime.now().uptimeNanoseconds
                let startedAt = state.tableOffset
                let builtBefore = ShotTable.builds
                var last = began
                var worst = 0.0
                var ticks = 0
                var wheels = 0
                var visited = 0
                var down = true
                var narrow = true
                let squeeze = args.contains("--squeeze")
                let modes = args.contains("--modes")
                // **Where the lateness sits matters more than its peak.** A
                // hundred milliseconds once is a hitch; a hundred milliseconds
                // every time the scene changes is what he called a freeze. So
                // the ticks are counted in bands, and the ones that land on a
                // scene change are counted apart from the ones that do not.
                var over33 = 0
                var over50 = 0
                var worstOnSwitch = 0.0
                var worstScrolling = 0.0
                var justSwitched = false
                let beat = Timer(timeInterval: 1.0 / 60.0, repeats: true) { clock in
                    let now = DispatchTime.now().uptimeNanoseconds
                    let late = Double(now &- last) / 1_000_000 - 1000.0 / 60.0
                    worst = max(worst, late)
                    if late > 33 { over33 += 1 }
                    if late > 50 { over50 += 1 }
                    if justSwitched {
                        worstOnSwitch = max(worstOnSwitch, late)
                    } else {
                        worstScrolling = max(worstScrolling, late)
                    }
                    justSwitched = false
                    last = now
                    ticks += 1
                    // The wheel keeps turning, and every third of a second the
                    // scene changes underneath it — which is the pair of things
                    // he was doing.
                    Self.wheel(down ? 900 : -900, over: 1, in: window) {}
                    wheels += 1
                    // **Up and down, fast** — his correction, 2026-08-29:
                    // *"the freezing happens when you are scrolling really
                    // fast up and down the shot list."* A scroll that only
                    // ever goes one way runs out of list and then costs
                    // nothing; whipping the direction keeps the lazy stack
                    // building and discarding rows for as long as this runs,
                    // which is the thing he is describing.
                    if ticks % 4 == 0 { down.toggle() }
                    // **`--modes` is his actual motion**, 2026-08-30: *"i was
                    // switching modes and going between scenes quikly."* A
                    // mode change swaps the whole window's contents, and it is
                    // four times as expensive as anything else measured here.
                    if modes, ticks % 5 == 0 {
                        let all = SideTab.allCases
                        state.sideTab = all[(visited &+ wheels) % all.count]
                    }
                    // **And with `--squeeze`, the width keeps moving too.** A
                    // row's height is negotiated against the width it is
                    // given: change the width and every wrapping cell has to
                    // be measured again and the row re-asked how tall it wants
                    // to be. That is the negotiation the three recorded hangs
                    // died inside, so a hunt for one has to keep it running.
                    if squeeze, ticks % 7 == 0 {
                        var f = window.frame
                        f.size.width = narrow ? 1560 : 1040
                        narrow.toggle()
                        window.setFrame(f, display: true)
                    }
                    if ticks % 20 == 0, !scenes.isEmpty {
                        state.sceneId = scenes[visited % scenes.count]
                        visited += 1
                        justSwitched = true
                    }
                    if Double(now &- began) / 1_000_000_000 >= seconds {
                        clock.invalidate()
                        FileHandle.standardError.write(Data((
                            "churn: \(wheels) wheel turns, \(visited) scene changes, "
                            + String(format: "%.1fs\n", Double(now &- began) / 1_000_000_000)
                            + String(format: "stall: worst %.0fms over %d ticks  ",
                                     worst, ticks)
                            + String(format: "late>33ms: %d  late>50ms: %d  ", over33, over50)
                            + String(format: "worst on a scene change %.0fms, "
                                     + "worst while only scrolling %.0fms  ",
                                     worstOnSwitch, worstScrolling)
                            + String(format: "offset %.0f → %.0f  ",
                                     startedAt, state.tableOffset)
                            + "table rebuilt \(ShotTable.builds - builtBefore) times\n"
                            + "republished: " + ShellState.publishes.sorted { $0.value > $1.value }
                                .map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "\n"
                            + String(format: "heartbeat: %d pulls, worst %.0fms, %.0fms in all\n",
                                     state.pulls, state.pullWorstMs, state.pullSpentMs)).utf8))
                        self.reportColumns()
                        self.snapshotIfAsked(after: 0.2)
                    }
                }
                RunLoop.main.add(beat, forMode: .common)
            }
        }
        // `--pull` takes in whatever another device left in the project's
        // changes folder and reports it. The app does this by itself when the
        // folder changes; the flag is how a check can ask for it at a known
        // moment instead of racing a watcher.
        if args.contains("--pull") {
            let pull = state.pullNow()
            FileHandle.standardError.write(Data((
                "pull: merged \(pull?.merged ?? 0), clashes \(pull?.clashes.count ?? 0)\n"
                ).utf8))
        }
        // `--settle` presses the banner's button. Both numbers are reported
        // because the whole complaint is about the second one: what is still
        // standing *after* answering, which is what the next launch will say.
        if args.contains("--settle") {
            let before = state.clashes.count
            state.settleClashes()
            FileHandle.standardError.write(Data((
                "settle: was \(before), standing \(state.clashes.count)\n").utf8))
        }
        // `--addshot` puts a fresh shot on the current scene, so the state a
        // person reaches by clicking "Add shot" can be photographed.
        // `--card <points>` drives the storyboard's card width, so the grid
        // can be photographed at the in-between sizes — where a card stretches
        // past its minimum is exactly where the ratio and the overlap broke.
        // `--notes <words>` writes the scene's notes — the Notes tab's own
        // field, on the scene record rather than a shot.
        if let at = args.firstIndex(of: "--notes"), at + 1 < args.count,
           let engine = state.engine, let scene = state.scene {
            state.replace(engine.setMany(shots: [scene.id], field: "notes",
                                         value: args[at + 1]))
        }
        // `--unpin` takes the first file off, `--pin <path>` puts one on.
        // Unpin runs first, so a run carrying both reads the way it looks on
        // the line — clear, then add. (Pinning first made the pair a no-op,
        // and a check that quietly does nothing passes for the wrong reason.)
        if args.contains("--unpin"), let engine = state.engine,
           let first = state.scene?.attachments.first {
            state.replace(engine.detach(frame: first.ref))
        }
        if let at = args.firstIndex(of: "--pin"), at + 1 < args.count,
           let scene = state.scene {
            Attachments.add(url: URL(fileURLWithPath: args[at + 1]), to: scene, state: state)
        }
        // `--view` opens the scene's first attachment in the viewer, so the
        // window a person reads files in can be photographed like any other.
        if args.contains("--view"), let file = state.scene?.attachments.first {
            Attachments.read(file, among: state.scene?.attachments ?? [], state: state)
        }
        // `--layout "<position> <width>"` moves the cursor shot's frame the
        // way the page's controls do, so the document tab's one write of its
        // own can be checked through the app.
        if let at = args.firstIndex(of: "--layout"), at + 1 < args.count,
           let engine = state.engine,
           let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
            let parts = args[at + 1].split(separator: " ")
            if parts.count == 2, let width = Double(parts[1]) {
                state.replace(engine.layout(shot: row.shot,
                                            position: String(parts[0]), width: width))
            }
        }
        // `--ratio <n>` sets the project's frame, the way the storyboard's
        // ratio menu does — it is a project field, so `--set` (which writes a
        // shot) cannot reach it.
        if let at = args.firstIndex(of: "--ratio"), at + 1 < args.count,
           let engine = state.engine, let project = state.view?.project.id {
            state.replace(engine.set(shot: project, field: "aspect_ratio",
                                     value: args[at + 1]))
        }
        // **The project's frames** (piece E): `--pickframe <name>` picks the
        // frame Studio draws at, as the frame menu does; `--frameguides on|off`
        // shows the others as guide lines; `--framemenu <png>` draws the
        // menu's rows to a file and says them on stderr.
        if let at = args.firstIndex(of: "--pickframe"), at + 1 < args.count, let engine = state.engine {
            let before = state.view?.project.frame ?? ""
            state.replace(engine.pickFrame(args[at + 1]))
            FileHandle.standardError.write(Data("pickframe: \(before) -> \(state.view?.project.frame ?? "") ratio \(state.view?.project.ratio ?? 0)\n".utf8))
        }
        if let at = args.firstIndex(of: "--frameguides"), at + 1 < args.count, let engine = state.engine {
            state.replace(engine.setFrameGuides(args[at + 1] == "on"))
        }
        if let at = args.firstIndex(of: "--framemenu"), at + 1 < args.count {
            let project = state.view?.project
            MainActor.assumeIsolated { FrameMenuDrive.photograph(args[at + 1], project: project) }
        }
        if let at = args.firstIndex(of: "--ratiomenu"), at + 1 < args.count {
            let current = state.view?.project.ratio ?? 2.39
            MainActor.assumeIsolated { RatioDrive.photograph(args[at + 1], current: current) }
        }
        if let at = args.firstIndex(of: "--card"), at + 1 < args.count,
           let points = Double(args[at + 1]) {
            state.cardWidth = CGFloat(points)
        }
        if args.contains("--addshot"), let engine = state.engine, let scene = state.scene {
            state.replace(engine.addShot(scene: scene.id))
        }
        // **Mods** (2026-10-17): `--modson edit_reference` lays the mod on
        // without a server; `--addeditref 34A,34B` makes one over those shots
        // (with `--editreffile <clip>`); `--editrefsays` reads the brackets;
        // `--playeditref` opens the first one's player window.
        if let at = args.firstIndex(of: "--modson"), at + 1 < args.count {
            state.modsOn = args[at + 1].split(separator: ",").map(String.init)
        }
        if let at = args.firstIndex(of: "--addeditref"), at + 1 < args.count {
            let rows = state.view?.allRows ?? []
            let shots = args[at + 1].split(separator: ",").compactMap { n in rows.first { $0.number == String(n) }?.shot }
            let file = args.firstIndex(of: "--editreffile").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            state.addEditRef(name: "Car cut", shots: shots, files: file.map { [URL(fileURLWithPath: $0)] } ?? [], link: "")
        }
        if args.contains("--editrefsays") {
            let rows = state.view?.allRows ?? []
            let said = rows.compactMap { row -> String? in
                guard let pieces = state.editPieces[row.id] else { return nil }
                return row.number + ":" + pieces.map { ($0.first ? "first " : "") + ($0.last ? "last " : "") + $0.ref.name }.joined(separator: "+")
            }
            let refs = (state.view?.editRefs ?? []).map { "\($0.name) \($0.range) \($0.shots.count) shots \(String(format: "%.1f", $0.length))s media \($0.media.count)" }
            let through = state.editThrough.keys.sorted().map { key -> String in
                let scene = key.split(separator: ":").last.map(String.init) ?? ""
                let number = state.view?.scenes.first { $0.id == scene }?.number ?? scene
                return (key.hasPrefix("foot:") ? "under " : "over ") + number
            }
            FileHandle.standardError.write(Data("edit refs: \(refs.joined(separator: " | "))\nedit pieces: \(said.isEmpty ? "none" : said.joined(separator: ", "))\nedit through: \(through.isEmpty ? "none" : through.joined(separator: ", "))\n".utf8))
        }
        if args.contains("--playeditref"), let first = state.view?.editRefs?.first {
            // Once the window is up and its rows measured (`rowFrames`), so
            // the bloom starts at its bracket's button.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let row = state.view?.allRows.first(where: { $0.shot == first.shots.first?.shot }),
                   let rect = state.rowFrames[row.id] {
                    state.editRefFrom = CGRect(x: rect.minX + Columns.edge - 21 + 8 - 8.5, y: rect.minY + 17 - 8.5, width: 17, height: 17)
                }
                state.editRefPlaying = first.id
            }
        }
        if let at = args.firstIndex(of: "--editrefsheet"), at + 1 < args.count {
            let numbers = args[at + 1].split(separator: ",").map(String.init)
            MainActor.assumeIsolated { EditRefSheetWindow.show(numbers: numbers, state: state) }
        }
        // `--addcolumn "kind Label"` makes a column of the project's own, so
        // the battery can type into one without driving the sheet's UI.
        if let at = args.firstIndex(of: "--addcolumn"), at + 1 < args.count,
           let engine = state.engine {
            // Several at once, `;` between: "single Sound;check Done".
            for spec in args[at + 1].split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let kind = String(spec.split(separator: " ").first ?? "text")
                let label = spec.dropFirst(kind.count).trimmingCharacters(in: .whitespaces)
                let before = Set((state.view?.columns ?? []).map(\.name))
                state.replace(engine.addColumn(label: label, kind: kind))
                state.columnLanded = (state.view?.columns ?? [])
                    .first { !before.contains($0.name) }?.name
                FileHandle.standardError.write(Data("added \(kind) column \"\(label)\"\n".utf8))
            }
        }
        if let at = args.firstIndex(of: "--sidebar"), at + 1 < args.count {
            state.sidebarShown = args[at + 1] != "off"
        }
        // A checking run pins the sidebar to its standard width, in memory
        // only. The width persists across launches — including the launches
        // of the divider checks themselves — so without the pin every header
        // coordinate in the battery drifts with whatever some earlier check
        // left behind. One night was spent chasing "regressions" that were a
        // 42-point sidebar shift.
        if Self.checking {
            state.sidebarWidth = 258
            // **And pinned open**, unless the run says otherwise. The width
            // was pinned and the *visibility* was not, so the day he collapsed
            // his sidebar every checking run started measuring a window 258
            // points narrower than every coordinate in the battery assumes —
            // silently, and for a reason no check could report.
            //
            // Third time this exact shape has bitten: a checking run inheriting
            // one of his preferences and testing a screen other than the one
            // it thinks it is testing. The panel and the tab are already
            // pinned for it; this was the one left.
            if !CommandLine.arguments.contains("--sidebar") {
                state.sidebarShown = true
            }
            // A known starting tab **unless the run names one** — a check
            // that inherits his tab tests a different screen than it thinks
            // it does, which is how forty of them failed at once. The
            // `unless` is not decoration: forcing it unconditionally made
            // every `--tab storyboard` check photograph the table instead.
            if !CommandLine.arguments.contains("--tab") { state.tab = .shots }
            // Density 1 too: every tap coordinate in the battery is measured
            // at the standard zoom, and his zoom is his.
            Brand.density = 1
        }
        if args.contains("--browser") { state.browsing = true }
        // `--archive <sceneNumber> <0|1>` sets a scene aside or brings it
        // back, by the number a person would say out loud.
        if let at = args.firstIndex(of: "--archive"), at + 2 < args.count,
           let engine = state.engine,
           let scene = state.view?.scenes.first(where: { $0.number == args[at + 1] }) {
            state.replace(engine.archiveScene(scene.id, on: args[at + 2] != "0"))
        }
        // **`--addcolumn` before `--editcolumns` opens the sheet already
        // scrolled to the new column** — which is the behaviour Ref 281 turned
        // on, so a check has to be able to see it.
        if args.contains("--editcolumns") { state.editingColumns = true }
        // `--layoutall <position> <width>` puts every frame in the document on
        // one setting — what the Layout menu's whole-document items do, so a
        // check can photograph the result. Ref 53.
        // `--pages` — **where the Document view cut its sheets.** The one
        // thing about that screen no stored value can tell you: a page break
        // depends on how tall each block came out, so it is only knowable
        // after the page has drawn itself. The view publishes the answer and
        // this prints it. His ask, 2026-09-01, was that the editor show him
        // the pages the export will have; this is how that is checked without
        // reading a photograph.
        // `--layoutall <above|below|left|right|mix|alternate> [width]` — the
        // Layout menu, from outside. **`mix` and `alternate` call the same
        // `Layouts` the menu items call**, so this is a check on the app
        // rather than a second implementation that could agree with nothing.
        if let at = args.firstIndex(of: "--layoutall"), at + 1 < args.count,
           let engine = state.engine {
            let asked = args[at + 1]
            let width = (at + 2 < args.count) ? Double(args[at + 2]) : nil
            var last: ViewModel?
            for (index, row) in (state.view?.allRows ?? []).enumerated() {
                let (position, wide): (String, Double)
                switch asked {
                case "mix":       (position, wide) = Layouts.mixed(index)
                case "alternate": (position, wide) = Layouts.alternating(
                                        index, width: width ?? row.frameWidth)
                default:
                    position = asked
                    wide = Layouts.clamp(width ?? row.frameWidth, on: asked)
                }
                last = engine.layout(shot: row.shot, position: position, width: wide)
            }
            state.replace(last)
            FileHandle.standardError.write(Data((
                "laid out: " + (state.view?.allRows ?? [])
                    .map { "\($0.number)=\($0.framePosition)/"
                         + String(format: "%.2f", $0.frameWidth) }
                    .joined(separator: " ") + "\n").utf8))
        }
        // `--sceneorder <script|day|location>` reads the film in that order —
        // Ref 102. A way of looking, so it is state rather than a write, and a
        // check has to be able to set it to photograph the result.
        if let at = args.firstIndex(of: "--sceneorder"), at + 1 < args.count,
           let want = ShellState.SceneOrder(rawValue: args[at + 1]) {
            state.sceneOrder = want
            FileHandle.standardError.write(Data((
                "scene order: " + state.scenes.map(\.number).joined(separator: ",")
                + "\n").utf8))
        }
        // `--pickpicture <scene number|shot|location name>` opens the
        // already-in-this-project picker on that owner — Ref 228.
        // `--pickpreview 2` double-clicks the second picture in the open
        // picker. A sheet cannot be clicked into by any check and cannot be
        // photographed at all (Ref 366), so without this the one gallery that
        // gained a preview would have shipped on reasoning alone.
        if let at = args.firstIndex(of: "--pickpreview"), at + 1 < args.count,
           let wanted = Int(args[at + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                state.previewPictureAt = wanted
            }
        }
        if let at = args.firstIndex(of: "--pickpicture"), at + 1 < args.count {
            let wanted = args[at + 1]
            let owner = state.view?.locations.first { $0.name == wanted }?.id
                ?? state.view?.allRows.first { $0.number == wanted }?.shot
                ?? state.view?.scenes.first { $0.number == wanted }?.id
            state.pickingPictureFor = owner
            FileHandle.standardError.write(Data((
                "picking for: \(owner ?? "-")\n").utf8))
        }
        // `--prefs general|aspect|columns|sync` opens Settings (⌘,) on that
        // tab; `--window prefs --snapshot out.png` photographs it.
        if let at = args.firstIndex(of: "--prefs") {
            if at + 1 < args.count { StudioSettings.checkTab = args[at + 1] }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { SettingsDoor.open() }
        }
        if let at = args.firstIndex(of: "--prefsdo"), at + 1 < args.count {
            let name = args[at + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { SettingsDoor.press(name, state) }
        }
        // `--settings [page]` opens Project Settings, on the Script page when
        // asked, so the commercial's script editor can be photographed.
        if let at = args.firstIndex(of: "--settings") {
            // A page by name: details, folder, aspect, columns, lists,
            // script, specsheet (Ref 1627, on a hub a check points it at
            // with `-PortalURL` and `-PortalToken`), sequences.
            if at + 1 < args.count, let named = SettingsPage.named(args[at + 1]) { state.settingsPage = named }
            state.editingProject = true
        }
        // `--specadd 34B` — the shot's own menu's Add to Spec Sheet (Ref
        // 1627), pressed once the kit has come down: its lens, else its
        // camera's body. Says what was asked and what the shot is off after.
        if let at = args.firstIndex(of: "--specadd"), at + 1 < args.count {
            let wanted = args[at + 1]
            let spin = { (until: () -> Bool) in
                let deadline = Date().addingTimeInterval(20)
                while !until() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            }
            spin { SpecSheets.shared.read && !SpecSheets.shared.busy }
            let row = state.view?.allRows.first { $0.number == wanted }
            if let off = row?.offKit {
                if let lens = off.lens { SpecSheets.shared.add(lens: lens, for: off, state: state) }
                else if let body = off.body { SpecSheets.shared.add(body: body, label: off.camera ?? "", for: off, state: state) }
                spin { !SpecSheets.shared.busy }
            }
            let after = state.view?.allRows.first { $0.number == wanted }?.offKit
            FileHandle.standardError.write(Data((
                "specadd: \(row?.offKit == nil ? "nothing to add" : SpecSheets.shared.said)"
                + " · off after: \(after.map { [$0.lens, $0.body].compactMap { $0 }.joined(separator: ", ") } ?? "none")\n").utf8))
        }

        // `--spectake` — Ask's Take (2026-10-13), pressed once the sheets have
        // come down. Says what was offered, the Lens list and cameras after,
        // (no ratio offer: a camera has no Frame Guides any more).
        // `--kitmode off|ask|follow` sets the film's Spec Sheet switch first.
        if let at = args.firstIndex(of: "--kitmode"), at + 1 < args.count, let engine = state.engine {
            state.replace(engine.setKitMode(args[at + 1]))
        }
        if args.contains("--spectake") {
            let deadline = Date().addingTimeInterval(20)
            while !(SpecSheets.shared.read && !SpecSheets.shared.busy) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            let offered = SpecSheets.shared.offer ?? "nothing"
            SpecSheets.shared.takeOffered(state)
            let kit = state.view?.project.kit ?? []
            FileHandle.standardError.write(Data((
                "spectake: switch \(state.view?.project.kitMode ?? "?") · offered \(offered)"
                + " · kit lenses \(kit.flatMap(\.lenses).joined(separator: ", "))"
                + " · cameras \(kit.flatMap(\.cameras).map { "\($0.label) \($0.body)" }.joined(separator: ", "))"
                + " · offer after \(SpecSheets.shared.offer ?? "none")\n").utf8))
        }

        // ---- the console's archive door — `FilmDoor` ------------------------
        //
        // `--archivefilm <page>` / `--unarchivefilm <page>`: one film, found by
        // the Notion page it is linked to, into the bin or out of it, exactly
        // as the Projects screen does it. Below `--syncsave`, so a check can
        // point it at a relay of its own first. One line back, then the run
        // ends.
        for flag in ["--archivefilm", "--unarchivefilm"] {
            guard let at = args.firstIndex(of: flag), at + 1 < args.count else { continue }
            let page = args[at + 1]
            Task { @MainActor in
                let said = flag == "--archivefilm"
                    ? await FilmDoor.archive(page: page)
                    : await FilmDoor.unarchive(page: page)
                FileHandle.standardError.write(Data((said + "\n").utf8))
                self.finish()
            }
            return
        }
        // `--deletefilm <relay id>`: one EMPTY project, deleted as the Projects
        // screen's Delete does it. Refuses anything that holds anything.
        if let at = args.firstIndex(of: "--deletefilm"), at + 1 < args.count {
            let id = args[at + 1]
            Task { @MainActor in
                FileHandle.standardError.write(Data((await FilmDoor.deleteEmpty(relay: id) + "\n").utf8))
                self.finish()
            }
            return
        }
        // `--holdfilm <seconds>` — a window, for a check: hold the film
        // `--project` opened, listen for the door's "let go" the way a real
        // window does, and end after that long.
        if let at = args.firstIndex(of: "--holdfilm"), at + 1 < args.count,
           let seconds = Double(args[at + 1]) {
            FilmDoor.listen(state: state)
            FileHandle.standardError.write(Data((
                "holding: \"\(state.projectPath?.lastPathComponent ?? "-")\"\n").utf8))
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { self.finish() }
            return
        }

        // ---- putting a film away, taking it out, taking a copy of it -------
        //
        // **The three verbs on the Projects screen, without the screen.** That
        // screen is a sheet, and Ref 366 settled that a sheet cannot be
        // photographed here — while one is up a checking run has no windows at
        // all. So the buttons themselves cannot be clicked by a check.
        //
        // What can be checked is everything underneath them, which is where all
        // the risk is: archiving talks to his real relay and then *moves a
        // folder*, and getting the order wrong loses a photograph for good.
        // `ProjectBrowser` holds no logic of its own — it calls exactly these
        // three sequences — so a check that runs them is checking the buttons
        // in every way that matters.
        if args.contains("--filmarchive") {
            let film = state.projectPath ?? URL(fileURLWithPath: ".")
            Task { @MainActor in
                do {
                    let brought = try await Relay.pullEverything(at: film)
                    try await Relay.removeFilm(at: film, fate: .archived)
                    // The same handover the button makes. See
                    // `ShellState.letGoOf` — the button and this flag call one
                    // function on purpose, so checking the flag means something.
                    let letGo = state.letGoOf(film)
                    let put = try Archive.put(film)
                    FileHandle.standardError.write(Data((
                        "archived: \(put.path) fetched \(brought.logs) logs "
                        + "\(brought.media) pictures let go: \(letGo) "
                        + "now open: \(state.projectPath?.lastPathComponent ?? "-")\n").utf8))
                } catch {
                    FileHandle.standardError.write(Data((
                        "archived: failed \(error.localizedDescription)\n").utf8))
                }
                self.finish()
            }
            return
        }
        // `--filmunarchive <name>` — the film of that name, out of the bin.
        if let at = args.firstIndex(of: "--filmunarchive"), at + 1 < args.count {
            let wanted = args[at + 1]
            let found = Archive.all().first {
                $0.deletingPathExtension().lastPathComponent == wanted
            }
            if let found, let back = try? Archive.back(found) {
                FileHandle.standardError.write(Data(("unarchived: \(back.path)\n").utf8))
            } else {
                FileHandle.standardError.write(Data(("unarchived: not in the bin\n").utf8))
            }
            finish()
            return
        }
        // `--exportcopy <path>` — the whole film as one file, pictures and all.
        if let at = args.firstIndex(of: "--exportcopy"), at + 1 < args.count {
            let to = URL(fileURLWithPath: args[at + 1])
            let film = state.projectPath ?? URL(fileURLWithPath: ".")
            Task { @MainActor in
                _ = try? await Relay.pullEverything(at: film)
                do {
                    try Copies.write(film, to: to)
                    let bytes = (try? to.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    FileHandle.standardError.write(Data((
                        "exported: \(to.path) \(bytes) bytes\n").utf8))
                } catch {
                    FileHandle.standardError.write(Data((
                        "exported: failed \(error.localizedDescription)\n").utf8))
                }
                self.finish()
            }
            return
        }
        // `--openedcopy <path>` — one of those files, back into a folder.
        if let at = args.firstIndex(of: "--openedcopy"), at + 1 < args.count {
            let from = URL(fileURLWithPath: args[at + 1])
            let into = state.projectPath?.deletingLastPathComponent()
                ?? Projects.home()
            do {
                let film = try Copies.open(from, into: into)
                FileHandle.standardError.write(Data(("opened copy: \(film.path)\n").utf8))
            } catch {
                FileHandle.standardError.write(Data((
                    "opened copy: failed \(error.localizedDescription)\n").utf8))
            }
            finish()
            return
        }
        // `--offload <film>` does what the Projects screen's *Offload…* does
        // once its question is answered — the same `Offloading.run`, open
        // check, relay check and all — and **waits** for it, so a check can
        // read what happened and a `--browsebox` after it draws the result.
        // The pictures go to the run's own temporary folder, never his Trash.
        // Above `--browsebox` so the screen is drawn after, not before.
        if let at = args.firstIndex(of: "--offload"), at + 1 < args.count {
            let film = URL(fileURLWithPath: args[at + 1])
            var said = "offload: still waiting"
            var done = false
            Task { @MainActor in
                do {
                    let gone = try await Offloading.run(film, state: state) { _, _ in }
                    said = "offload: \(gone.files) files, \(gone.bytes) bytes"
                } catch {
                    said = "offload: refused — \(error.localizedDescription)"
                }
                done = true
            }
            let deadline = Date().addingTimeInterval(120)
            while !done && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            FileHandle.standardError.write(Data((said + "\n").utf8))
        }
        // `--download <film>` is *Download* on an offloaded film's menu, and
        // the first half of clicking one: the pictures back from the relay.
        if let at = args.firstIndex(of: "--download"), at + 1 < args.count {
            let film = URL(fileURLWithPath: args[at + 1])
            var said = "download: still waiting"
            var done = false
            Task { @MainActor in
                do {
                    let got = try await Relay.bringBack(at: film) { _, _ in }
                    said = "download: \(got.brought) brought, \(got.letGo) let go"
                } catch {
                    said = "download: failed — \(error.localizedDescription)"
                }
                done = true
            }
            let deadline = Date().addingTimeInterval(120)
            while !done && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            FileHandle.standardError.write(Data((said + "\n").utf8))
        }
        // `--incloud <film>` says whether the Projects screen would draw it as
        // *In the Cloud*, and how many of its pictures are away.
        if let at = args.firstIndex(of: "--incloud"), at + 1 < args.count {
            let film = URL(fileURLWithPath: args[at + 1])
            let away = Offload.inCloud(film)
            FileHandle.standardError.write(Data((
                "incloud: \(away) missing: \(Offload.missing(at: film).count)\n").utf8))
        }
        // `--browsebox` draws the Projects screen in a window so it can be
        // photographed. See `BrowserWindow` — checking only; it is a sheet in
        // the app and stays one.
        if args.contains("--browsebox") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                BrowserWindow.shared.show(state: state)
            }
        }
        // `--colwidth image 400` — set a column's width for this run, so the
        // thing his complaint is actually about can be reproduced. An empty
        // picture well used to be `width / ratio` tall, so **widening the image
        // column stood every unboarded row up** and there was no way to see
        // that from a check: at the default width the 64-point row floor hides
        // it completely.
        if let at = args.firstIndex(of: "--colwidth"), at + 2 < args.count,
           let points = Double(args[at + 2]) {
            Columns.setWidth(args[at + 1], to: CGFloat(points))
        }
        // `--filmbin` prints what is in the bin, so a check can read it back.
        if args.contains("--filmbin") {
            let said = Archive.all()
                .map { $0.deletingPathExtension().lastPathComponent }
                .joined(separator: " · ")
            FileHandle.standardError.write(Data((
                "archived films: \(said.isEmpty ? "none" : said)\n").utf8))
        }
        // **Versions** — `Versions.swift`. In the order a person would do them:
        // `--saveversion NAME` keeps the film; `--lookat N` puts the Nth newest
        // on screen; `--bringback` presses the banner's Bring Back on whatever
        // `--scene` / the ticks say; `--goback N` goes back without asking;
        // `--versions` opens the window, for `--window versions --snapshot`;
        // `--versionssay` prints the list and what is on screen.
        if let at = args.firstIndex(of: "--saveversion"), at + 1 < args.count {
            state.saveVersion(named: args[at + 1])
        }
        if let at = args.firstIndex(of: "--lookat"), at + 1 < args.count,
           let n = Int(args[at + 1]), n >= 1 {
            let list = state.engine?.versions().list ?? []
            if n <= list.count { state.look(at: list[n - 1]) }
        }
        if args.contains("--bringback") {
            FileHandle.standardError.write(Data(
                "bring back offers: \(state.bringing?.label ?? "nothing")\n".utf8))
            state.bringBackPicked()
        }
        if let at = args.firstIndex(of: "--goback"), at + 1 < args.count,
           let n = Int(args[at + 1]), n >= 1 {
            let list = state.engine?.versions().list ?? []
            if n <= list.count { state.goBack(to: list[n - 1]) }
        }
        if let at = args.firstIndex(of: "--copyversion"), at + 1 < args.count,
           let n = Int(args[at + 1]), n >= 1 {
            let list = state.engine?.versions().list ?? []
            if n <= list.count {
                let film = state.projectPath?.deletingPathExtension().lastPathComponent ?? "Film"
                state.copy(list[n - 1], named: "\(film) (\(list[n - 1].title))")
            }
        }
        if args.contains("--versions") {
            VersionsWindow.shared.show(state: state)
        }
        // `--mediadelete unused | <media id>…` deletes as the Media window's
        // buttons do, without the question; `--media` opens the window.
        if let at = args.firstIndex(of: "--mediadelete"), at + 1 < args.count, let engine = state.engine {
            let what = args[at + 1]
            let done = what == "unused" ? engine.deleteUnusedMedia() : engine.deleteMedia([what])
            state.replace(engine.view())
            state.readHollowFrames()
            FileHandle.standardError.write(Data((
                "media deleted: \(done?.deleted ?? -1), \(done?.freedBytes ?? -1) bytes\n").utf8))
        }
        if args.contains("--media") {
            MediaShelfWindow.shared.show(state: state)
        }
        if args.contains("--versionssay") {
            let (looking, list) = state.engine?.versions() ?? ("", [])
            var said = "versions: \(list.count)\n"
            for v in list {
                said += "version: \(v.title) | \(v.made) | \(v.sinceSaid)\n"
            }
            said += "looking: \(looking.isEmpty ? "now" : (list.first { $0.id == looking }?.title ?? looking))\n"
            said += "scenes on screen: \(state.view?.scenes.count ?? 0)\n"
            said += "read only: \(state.view?.project.readOnly ?? false)\n"
            FileHandle.standardError.write(Data(said.utf8))
        }
        // `--stripcheck` — a clip strip's header reads back (Filmstrip.selfCheck).
        if args.contains("--stripcheck") { Filmstrip.selfCheck() }
        // `--exportbox` opens the export window on the whole film — the share
        // button's own door.
        //
        // **It exists so the box can be photographed.** As a sheet it never
        // could be (Ref 366): while one is up a checking run has no windows at
        // all, so no check has ever seen this screen. Paired with
        // `--window export --snapshot out.png` it finally can.
        if let at = args.firstIndex(of: "--exportbox") {
            if at + 1 < args.count, !args[at + 1].hasPrefix("--") {
                state.exportOpensOn = args[at + 1]
            }
            if let p = args.firstIndex(of: "--exportpaper"), p + 1 < args.count {
                state.exportPaperSaid = args[p + 1]
            }
            if let u = args.firstIndex(of: "--exportsetup"), u + 1 < args.count {
                state.exportSetupSaid = args[u + 1]
            }
            if let v = args.firstIndex(of: "--exportvisit"), v + 1 < args.count {
                state.exportVisitSaid = args[v + 1]
            }
            if let n = args.firstIndex(of: "--exportnext"), n + 1 < args.count {
                state.exportNextSaid = args[n + 1]
            }
            if let k = args.firstIndex(of: "--exportkey"), k + 1 < args.count {
                state.exportKeySaid = args[k + 1]
            }
            if let k = args.firstIndex(of: "--exportsave"), k + 1 < args.count {
                state.exportSaveSaid = args[k + 1]
            }
            if let k = args.firstIndex(of: "--exportset"), k + 1 < args.count {
                state.exportSetSaid = args[k + 1]
            }
            if let k = args.firstIndex(of: "--exportdrag"), k + 1 < args.count {
                state.exportDragSaid = args[k + 1]
            }
            Exporting.exportProjectPDF(state: state)
        }
        // `--exportdiagram` — the Diagram's Export…, on whatever plan the
        // Diagram is showing (`--place diagram --scene N`), so a check can
        // photograph it with `--window export`.
        if args.contains("--exportdiagram"), let owner = state.diagramOwner {
            Exporting.exportDiagram(owner, state: state)
        }
        // `--addscene [heading]` opens the New scene sheet with the line
        // already typed, so a check can photograph what a heading reads as
        // before anything is written.
        if let at = args.firstIndex(of: "--addscene") {
            if at + 1 < args.count, !args[at + 1].hasPrefix("--") {
                state.newSceneHeading = args[at + 1]
            }
            // `--addscenedo` presses Add for itself, so a check watches the
            // box actually write rather than only photographing it.
            // `--addsceneagain` presses *Add another* instead.
            state.newSceneAgain = args.contains("--addsceneagain")
            state.newSceneNow = args.contains("--addscenedo") || state.newSceneAgain
            state.addingScene = true
        }
        // `--panel [script|references|notes]` opens the side panel on a
        // section, so a check can photograph it and read what it holds.
        if let at = args.firstIndex(of: "--panel") {
            state.panelShown = true
            if at + 1 < args.count, let want = PanelSection(rawValue: args[at + 1]) {
                state.panel = want
            }
        }
        // `--script <file.pdf>` opens the import sheet on that PDF;
        // `--scriptdo <scenes|characters|confirm|take>` says what to do once it
        // has read it. The sheet says what it found on stderr as it goes, so a
        // check reads the reading rather than photographing a number.
        if let at = args.firstIndex(of: "--script"), at + 1 < args.count {
            let doing = args.firstIndex(of: "--scriptdo").flatMap {
                $0 + 1 < args.count ? args[$0 + 1] : nil
            } ?? ""
            let folding = args.firstIndex(of: "--scriptmerge").flatMap {
                $0 + 1 < args.count ? args[$0 + 1] : nil
            } ?? ""
            state.importingScript = ScriptFile(
                url: URL(fileURLWithPath: args[at + 1]), opening: doing, merging: folding)
        }
        // `--list <field>` opens the project's settings on that list's page —
        // the one place every column's terms, and the lock on them, live.
        if let at = args.firstIndex(of: "--list"), at + 1 < args.count {
            state.settingsList = args[at + 1]
            state.editingProject = true
        }
        // `--sortby <column>` — the Sort menu's pick, `shootingorder` among
        // them. Then each day's (or scene's) rows are said in order.
        if let at = args.firstIndex(of: "--sortby"), at + 1 < args.count {
            state.replace(state.engine?.sortBy(args[at + 1], descending: false))
            // What the table draws: in shooting order, archived scenes' shots set aside.
            for group in state.shootingOrder ? state.orderGroups : (state.view?.groups ?? []) {
                FileHandle.standardError.write(Data((
                    "order \(group.label): " + group.rows.map(\.number).joined(separator: " ") + "\n").utf8))
            }
        }
        // `--lock <field> <0|1>` closes or opens a list without clicking the
        // switch, so what a lock actually *stops* can be checked.
        // Every occurrence, in order — a check that locks a list and then
        // unlocks it is one run, and reading only the first `--lock` made the
        // second half of that check silently do nothing.
        for (at, flag) in args.enumerated() where flag == "--lock" && at + 2 < args.count {
            state.engine?.lockList(field: args[at + 1], on: args[at + 2] != "0")
        }
        if args.contains("--lock") { state.replace(state.engine?.view()) }
        // `--kind film|commercial` says what sort of film this is, before
        // anything else looks — so a check can open the scratch film as a
        // commercial. `--avpaste <file>` puts that file's text on the
        // clipboard and pastes it as an AV script; `--renumber` runs the
        // commercial's renumber without the question. All three say what
        // they did on stderr.
        if let at = args.firstIndex(of: "--kind"), at + 1 < args.count,
           let engine = state.engine {
            state.replace(engine.setKind(args[at + 1]))
            FileHandle.standardError.write(Data((
                "kind: \(state.view?.project.kind ?? "")\n").utf8))
        }
        // `--setscript <file> [--pastesection <title>]` — the section's
        // script set from the file's text (made by title when new). Several
        // in one run are several scripts. `--tie <shot> <from> <to>` after
        // one ties that shot to the range. Then every script and each
        // shot's quotation are said.
        if let engine = state.engine {
            let sets = args.indices.filter { args[$0] == "--setscript" }
            for at in sets where at + 1 < args.count {
                guard let text = try? String(contentsOfFile: args[at + 1], encoding: .utf8)
                else { continue }
                let next = sets.first { $0 > at } ?? args.count
                var section: String? = nil
                var newSection: String? = nil
                if let s = args[(at + 2)..<next].firstIndex(of: "--pastesection"), s + 1 < args.count {
                    let title = args[s + 1]
                    if let had = state.view?.sequences.first(where: { $0.title == title }) {
                        section = had.id
                    } else {
                        newSection = title
                    }
                }
                let edit = engine.setScript(text, section: section, newSection: newSection)
                state.replace(engine.view())
                FileHandle.standardError.write(Data((
                    "script set: kept \(edit?.kept ?? 0) lost \(edit?.lost ?? 0)\n").utf8))
            }
            if let at = args.firstIndex(of: "--tie"), at + 3 < args.count,
               let row = state.view?.allRows.first(where: { $0.number == args[at + 1] }),
               let from = Int(args[at + 2]), let to = Int(args[at + 3]) {
                let section = state.view?.scripts.first { !$0.section.isEmpty }?.section
                state.replace(engine.tie(shot: row.shot, section: section, from: from, to: to))
            }
            // `--tielines <shot> <from> <to>` ties that shot to a stretch of a
            // film's screenplay (the latest draft's text, offsets as
            // `scriptpages` gives them) and says what the shot now holds; the
            // Whole Script window and the panel draw it. Ref 1568.
            if let at = args.firstIndex(of: "--tielines"), at + 3 < args.count,
               let row = state.view?.allRows.first(where: { $0.number == args[at + 1] }),
               let from = Int(args[at + 2]), let to = Int(args[at + 3]),
               let latest = engine.revisions().first(where: \.latest) {
                state.replace(engine.playTie(shot: row.shot, revision: latest.id, pieces: [(from, to)]))
                FileHandle.standardError.write(Data((
                    "lines \(from)-\(to) for \(row.number): \(row.number) holds "
                    + "\(state.view?.allRows.first { $0.id == row.id }?.playLines ?? [])\n").utf8))
            }
            // `--scriptlayout av|plain` lays the first section's script (or
            // the film's) out as Video beside Audio, or back to plain text.
            if let at = args.firstIndex(of: "--scriptlayout"), at + 1 < args.count {
                let section = state.view?.scripts.first { !$0.section.isEmpty }?.section
                let edit = engine.scriptLayout(section: section, av: args[at + 1] == "av")
                state.replace(engine.view())
                FileHandle.standardError.write(Data((
                    "script layout \(args[at + 1]): kept \(edit?.kept ?? 0) lost \(edit?.lost ?? 0)\n").utf8))
            }
            if !sets.isEmpty || args.contains("--tie") || args.contains("--scriptlayout") {
                for script in state.view?.scripts ?? [] {
                    let title = state.view?.sequences.first { $0.id == script.section }?.title ?? "(film)"
                    FileHandle.standardError.write(Data(("  script \(title): \"\(script.text)\"\n").utf8))
                }
                for row in state.view?.allRows ?? [] where !row.script.isEmpty {
                    FileHandle.standardError.write(Data((
                        "  \(row.number) quotes \(row.scriptFrom ?? 0)-\(row.scriptTo ?? 0): \"\(row.script)\"\n").utf8))
                }
            }
        }
        // `--pastescript <file>` opens the Paste Script sheet holding that
        // file's text, so the reading can be photographed.
        if let at = args.firstIndex(of: "--pastescript"), at + 1 < args.count,
           let text = try? String(contentsOfFile: args[at + 1], encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            state.pastingScript = true
        }
        // `--deletesection <title>` — the sidebar's and Settings' Delete,
        // by the same asker (the alert is skipped while checking).
        if let at = args.firstIndex(of: "--deletesection"), at + 1 < args.count,
           let section = state.view?.sequences.first(where: { $0.title == args[at + 1] }) {
            state.askToDeleteSection(section)
            FileHandle.standardError.write(Data((
                "sections: " + (state.view?.sequences.map(\.title).joined(separator: " | ") ?? "")
                + "\n").utf8))
        }
        // `--sceneafter <number> <number|start>` — the list's drag, by the
        // same call, then the order and each scene's section said back.
        if let at = args.firstIndex(of: "--sceneafter"), at + 2 < args.count,
           let from = state.scenes.firstIndex(where: { $0.number == args[at + 1] }) {
            let to = args[at + 2] == "start" ? 0
                : (state.scenes.firstIndex(where: { $0.number == args[at + 2] }).map { $0 + 1 } ?? from)
            state.moveScenes(IndexSet(integer: from), to: to)
            FileHandle.standardError.write(Data((
                "order: " + state.scenes.map { s in
                    let section = state.view?.sequences.first { $0.id == s.sequence }?.title ?? "-"
                    return "\(s.number)(\(section))"
                }.joined(separator: " ") + "\n").utf8))
        }
        if args.contains("--renumber"), let engine = state.engine {
            let changed = engine.renumberInOrder()
            state.replace(engine.view())
            FileHandle.standardError.write(Data((
                "renumbered: \(changed) changed, now "
                + (state.view?.scenes.map(\.number).joined(separator: " ") ?? "") + "\n").utf8))
        }
        // `--scenepage` opens the scene's own details, on the scene the run
        // is looking at.
        if args.contains("--scenepage") { state.editingScene = state.scene?.id }
        // `--scenefield <field> <value>` writes one fact about the scene, the
        // way `--set` writes one about a shot. The scene's own page and the
        // header both edit these, and a check needs to be able to put a long
        // synopsis there without typing it by hand.
        if let at = args.firstIndex(of: "--scenefield"), at + 2 < args.count,
           let engine = state.engine, let scene = state.scene {
            state.replace(engine.set(shot: scene.id, field: args[at + 1],
                                     value: args[at + 2]))
            FileHandle.standardError.write(Data((
                "scene \(scene.number): \(args[at + 1]) = \"\(args[at + 2])\"\n").utf8))
        }
        // `--columnpage <field>` opens the columns sheet with one column's own
        // page on top of it — a sheet over a sheet, which no photographed
        // click can reach.
        if let at = args.firstIndex(of: "--columnpage"), at + 1 < args.count {
            state.editingColumns = true
            state.editingColumn = args[at + 1]
        }
        // `--hide <column>` / `--show <column>` drive the sheet's engine calls
        // directly, so visibility round-trips are assertable without clicking
        // inside a sheet whose coordinates depend on where the system centres
        // it.
        if let at = args.firstIndex(of: "--hide"), at + 1 < args.count,
           let engine = state.engine {
            state.replace(engine.column(args[at + 1], visible: false))
        }
        if let at = args.firstIndex(of: "--show"), at + 1 < args.count,
           let engine = state.engine {
            state.replace(engine.column(args[at + 1], visible: true))
        }
        // `--autolist` runs the automatic sync. **Above `--sync`, like
        // everything that changes something**, and it waits the same way for
        // the same reason.
        //
        // It exists because the automatic path is otherwise unreachable from a
        // check: it is deliberately switched off during checking runs, and
        // every door that opens a film makes the run a checking run. This calls
        // the transfer directly.
        //
        // **It used to prove that no picture moved.** Since 2026-09-08 the
        // opposite is the law — the automatic sync carries the pictures too —
        // so the name is now narrower than the thing. Left alone rather than
        // renamed: it is on the argument allow-list above and in his notes, and
        // a flag that quietly changed spelling is worse than one named oddly.
        if args.contains("--autolist") {
            state.syncListQuietly()
            let deadline = Date().addingTimeInterval(120)
            while state.syncing && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            FileHandle.standardError.write(Data((
                "autolist: \(state.syncSaid.isEmpty ? "nothing new" : state.syncSaid)\n").utf8))
        }
        // `--relayfilms` asks the relay what it is holding, and **waits** — so a
        // run that then photographs the Projects screen draws the films this
        // Mac does not have yet. Without it the snapshot is taken before the
        // network answers and the screen looks like the feature is missing,
        // which is exactly how it read the first time.
        if args.contains("--relayfilms") {
            var done = false
            var said = "nothing"
            Task { @MainActor in
                if let films = try? await Relay.films() {
                    said = films.map(\.title).sorted().joined(separator: ", ")
                } else {
                    said = "could not ask"
                }
                done = true
            }
            let deadline = Date().addingTimeInterval(60)
            while !done && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            FileHandle.standardError.write(Data(("relayfilms: \(said)\n").utf8))
        }

        // `--logaudit` puts this Mac's change logs beside the relay's and says
        // where they stop agreeing. **Read-only.**
        //
        // It exists because "one file would not move" is filed by `syncLogs`
        // for an upload the relay rejected *and* for a download that failed —
        // two opposite faults wearing one sentence. Deciding between them by
        // reasoning is exactly the guess that ends with somebody overwriting a
        // log, so this asks instead.
        if args.contains("--logaudit") {
            var done = false
            var said = "audit: no film is open"
            if let path = state.projectPath {
                Task { @MainActor in
                    said = await Relay.auditLogs(at: path)
                    done = true
                }
                let deadline = Date().addingTimeInterval(180)
                while !done && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
            }
            FileHandle.standardError.write(Data((said + "\n").utf8))
        }
        // `--copyword` presses "Copy password for iPhone" on the sync button's
        // own menu. **Above `--sync`, like everything that changes something.**
        //
        // It says only whether there is a word and how long it is. The word
        // itself never goes to a terminal — it is the one thing in this program
        // that must not end up in a scrollback or a screenshot, which is also
        // why the menu item copies rather than showing it.
        if args.contains("--copyword") {
            state.copyRelayToken()
            let carried = NSPasteboard.general.string(forType: .string) ?? ""
            let said = state.syncProblem
                ?? (carried.isEmpty ? "nothing was copied" : "copied \(carried.count) characters")
            FileHandle.standardError.write(Data(("copyword: \(said)\n").utf8))
        }
        // **Last of the doors that read, on purpose.** It writes what the
        // app is showing *now*, so a run that lays the frames out and then
        // exports gets the layout it asked for. Placed above `--layoutall` it
        // quietly exported the previous one, and the PDF looked like the
        // feature had not worked.
        // `--exportpdf <path> [document|table|storyboard,…]` — the real PDF
        // the share menu makes, written to a file a check can open. There was
        // no way to see the finished export from outside the dialog, and the
        // dialog cannot be clicked by a checking run — so the one claim this
        // whole screen rests on, that the page and the print are the same
        // page, could not be checked at all. Defaults to the document alone,
        // at 100%, which is what the dialog now opens on.
        if let at = args.firstIndex(of: "--exportpdf"), at + 1 < args.count,
           let engine = state.engine {
            let sections = (at + 2 < args.count && !args[at + 2].hasPrefix("--"))
                ? args[at + 2].split(separator: ",").map(String.init)
                : ["document"]
            let out = URL(fileURLWithPath: args[at + 1])
            // `--colwidths description:1.8,notes:0.6` — the export dialog's
            // own width sliders, from outside. The dialog is a sheet and no
            // sheet in this app can be photographed, so this is the only way
            // the widths can be checked reaching the page at all.
            var widths: [String: Double] = [:]
            if let w = args.firstIndex(of: "--colwidths"), w + 1 < args.count {
                for pair in args[w + 1].split(separator: ",") {
                    let halves = pair.split(separator: ":")
                    if halves.count == 2, let factor = Double(halves[1]) {
                        widths[String(halves[0])] = factor
                    }
                }
            }
            // `--paper table:portrait,document:landscape` — per view, because
            // the paper is per view now. Anything unnamed keeps the sheet its
            // own `Kind` asks for, which is what the box opens on. This
            // replaces a guess (`sections == ["document"] ? .portrait :
            // .landscape`) that could only ever be right about one view.
            var papers: [String: Printing.Orientation] = [:]
            if let p = args.firstIndex(of: "--paper"), p + 1 < args.count {
                for pair in args[p + 1].split(separator: ",") {
                    let halves = pair.split(separator: ":")
                    if halves.count == 2,
                       let paper = Printing.Orientation(rawValue: String(halves[1])) {
                        papers[String(halves[0])] = paper
                    }
                }
            }
            // The rest of the box's dials, so a check can assert them landing
            // on the page. Without these it could assert almost nothing.
            let textSize = args.firstIndex(of: "--textsize")
                .flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 1.0
            let pictureSize = args.firstIndex(of: "--framesize")
                .flatMap { $0 + 1 < args.count ? Printing.FrameSize(rawValue: args[$0 + 1]) : nil }
                ?? .medium
            let onlyColumns: [String]? = args.firstIndex(of: "--exportcolumns")
                .flatMap { $0 + 1 < args.count && !args[$0 + 1].hasPrefix("--")
                    ? args[$0 + 1].split(separator: ",").map(String.init) : nil }

            // `--tablelayout auto` — the table on Auto, the way the export
            // box prints it by default: decided by the engine and printed with
            // exactly its paper, text size and shares.
            // `auto:size=1.2,paper=portrait` — with his Size and paper.
            let auto: Engine.TableLayout? = args.firstIndex(of: "--tablelayout")
                .flatMap { at -> Engine.TableLayout? in
                    guard at + 1 < args.count, args[at + 1].hasPrefix("auto") else { return nil }
                    let asked = args[at + 1].split(separator: ":", maxSplits: 1).dropFirst().first
                        .map { $0.split(separator: ",").map(String.init) } ?? []
                    return engine.tableLayout(scope: Engine.ExportScope(columns: onlyColumns, extra: asked))
                }
            if let auto {
                FileHandle.standardError.write(Data(String(
                    format: "auto table: %@ %.0f%% picture %.2fin pages %d cut %d\n",
                    auto.orientation, auto.scale * 100, auto.picture, auto.pages, auto.cut).utf8))
            }
            let pages = sections.map { section -> Printing.Job in
                if section == "table", let auto {
                    return Printing.Job(
                        section: section,
                        scope: Engine.ExportScope(columns: onlyColumns, scale: auto.scale,
                                                  frames: auto.frames, shares: auto.shares,
                                                  fitted: auto.cut == 0,
                                                  order: state.orderCaption),
                        orientation: auto.look.orientation)
                }
                return Printing.Job(
                    section: section,
                    scope: Engine.ExportScope(
                        columns: onlyColumns,
                        scale: textSize,
                        frames: pictureSize.rawValue,
                        // Widths reach the table and nothing else — the
                        // engine drops them everywhere else anyway, and
                        // sending them is a claim it does not honour.
                        widths: section == "table" ? widths : [:],
                        order: state.orderCaption,
                        // `SHOTLISTER_DIAGRAMPRINT=dark=1,cones=0` — the
                        // diagram page's own switches, from outside.
                        extra: section == "diagram"
                            ? (ProcessInfo.processInfo.environment["SHOTLISTER_DIAGRAMPRINT"] ?? "")
                                .split(separator: ",").map(String.init)
                            : []),
                    orientation: papers[section]
                        ?? (Printing.Kind(rawValue: section) ?? .table).defaultOrientation
                )
            }
            // `--flat` — the pages baked into pictures, the box's own
            // Flat choice from outside; `text:` says whether any words
            // survived, which is the whole claim a flat file makes.
            let flat = args.contains("--flat")
            Printing.combinedDocument(pages, engine: engine) { result in
                switch result {
                case .success(let drawn):
                    let pdf = flat ? Printing.flattened(drawn) : drawn
                    let wrote = pdf.write(to: out)
                    FileHandle.standardError.write(Data((
                        "exported: \(wrote ? "yes" : "no") pages: \(pdf.pageCount)"
                        + " to \(out.path)\n").utf8))
                    FileHandle.standardError.write(Data(
                        "text: \(Printing.wordCount(inFileAt: out)) chars\n".utf8))
                    // **The shape of every page it actually wrote.** The one
                    // assertion that says the Document page came out portrait
                    // inside a landscape export — which it could not, before
                    // the paper became a per-view fact.
                    let shapes = (0..<pdf.pageCount).compactMap { i -> String? in
                        guard let box = pdf.page(at: i)?.bounds(for: .mediaBox) else { return nil }
                        return box.width > box.height ? "landscape" : "portrait"
                    }
                    FileHandle.standardError.write(Data((
                        "page shapes: " + shapes.joined(separator: " ") + "\n").utf8))
                case .failure(let problem):
                    FileHandle.standardError.write(Data((
                        "exported: no — \(problem.localizedDescription)\n").utf8))
                }
            }
        }
        // `--sync` presses the toolbar's Sync button — and **waits for it**.
        //
        // **Last of all the doors, deliberately.** It sat above `--notes` at
        // first, so a run that edited and then synced did it the other way
        // round: it pushed, then made the change, and reported "up to date"
        // about work it had not sent. A check that passes for the wrong reason
        // is worse than one that fails. Sync is the last thing a person does
        // too, so this is also the honest order.
        //
        // The transfer is a `Task`, so a check that simply calls it and reports
        // would print an answer from before anything had happened and pass for
        // the wrong reason. This spins the run loop until the work is done,
        // which is also the only way the `URLSession` callbacks get to run at
        // all in a headless launch.
        // `--shrinkclips` — every clip this film stores at the old bitrate,
        // re-encoded at the new one in place, its poster carried across as a
        // JPEG, the superseded files taken off this Mac and the relay. Run
        // once per film after 2026-09-15; harmless again afterwards, because a
        // clip already quiet is left alone. Put `--sync` after it in the same
        // run to send the result.
        if args.contains("--shrinkclips"), let engine = state.engine, let path = state.projectPath {
            let proxies = path.appending(path: "media/proxies")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: proxies.path)) ?? []
            var owed: [String] = []
            var before = 0, after = 0, done = 0, left = 0
            for movie in engine.movies() {
                let stem = String(movie.hash.prefix(32))
                guard let name = files.first(where: {
                    ($0 as NSString).deletingPathExtension == stem
                        && ["mp4", "mov", "m4v"].contains(($0 as NSString).pathExtension.lowercased())
                }) else {
                    FileHandle.standardError.write(Data("shrink: \(stem) has no movie on this Mac\n".utf8))
                    continue
                }
                let url = proxies.appending(path: name)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                // The poster it has, whichever way it was written — carried
                // across as a JPEG whatever happens to the clip.
                let held = ["jpg", "png"].lazy
                    .compactMap { NSImage(contentsOf: proxies.appending(path: "\(stem).\($0)")) }
                    .first
                let rate = AVURLAsset(url: url).tracks(withMediaType: .video).first
                    .map { Int($0.estimatedDataRate) } ?? 0
                guard rate > ClipEncoder.loudEnough, let arrived = try? Data(contentsOf: url) else {
                    // Quiet already. Only its poster may want re-filing.
                    if !files.contains("\(stem).jpg"), let held, let made = Ingest.poster(held) {
                        engine.poster(hash: movie.hash, data: made)
                        owed.append("\(stem).png")
                    }
                    left += 1
                    FileHandle.standardError.write(Data(
                        "shrink: \(movie.filename) left alone at \(rate / 1000) kbps\n".utf8))
                    continue
                }
                let small = Ingest.shrunk(url, arrived: arrived)
                guard small.data.count < arrived.count else {
                    left += 1
                    FileHandle.standardError.write(Data(
                        "shrink: \(movie.filename) came back no smaller; left alone\n".utf8))
                    continue
                }
                let shape = held.map { $0.size } ?? .zero
                guard let put = engine.reclip(media: movie.media, width: Int(shape.width),
                                              height: Int(shape.height), ext: small.ext,
                                              data: small.data) else {
                    FileHandle.standardError.write(Data(
                        "shrink: \(movie.filename) — the engine would not take it\n".utf8))
                    continue
                }
                if let held, let made = Ingest.poster(held) {
                    engine.poster(hash: put.hash, data: made)
                }
                Thumbs.shared.forget(movie.hash)
                owed.append(contentsOf: put.gone)
                before += size
                after += small.data.count
                done += 1
                FileHandle.standardError.write(Data((
                    "shrink: \(movie.filename)  \(size / 1_000_000) MB → \(small.data.count / 1_000_000) MB"
                    + "  (\(rate / 1000) kbps)\n").utf8))
            }
            state.replace(engine.view())
            // The strips a printed page would ask for, cut from the new files
            // now rather than on the next print.
            Filmstrip.ensure(engine: engine)
            // The superseded files, off the relay. No week's wait: the record
            // is renamed and every device takes logs before pictures.
            let waiting = DispatchSemaphore(value: 0)
            var forgotten = 0
            let names = owed
            Task {
                forgotten = await Relay.forget(names, path: path)
                waiting.signal()
            }
            while waiting.wait(timeout: .now()) == .timedOut {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            FileHandle.standardError.write(Data((
                "shrink: \(done) re-encoded, \(left) left alone; "
                + "\(before / 1_000_000) MB → \(after / 1_000_000) MB; "
                + "\(forgotten) of \(names.count) old files taken off the relay\n").utf8))
        }
        if args.contains("--sync") {
            state.syncNow()
            // Fifteen minutes, not two: a film's worth of clips going up after
            // `--shrinkclips` is a hundred megabytes, and a run that quits at
            // two minutes leaves half of them on the wire and says "nothing
            // to do". A check that has nothing to send still returns at once.
            let deadline = Date().addingTimeInterval(900)
            while state.syncing && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            let said = state.syncProblem.map { "problem: \($0)" }
                ?? (state.syncSaid.isEmpty ? "nothing to do" : state.syncSaid)
            FileHandle.standardError.write(Data(("sync: \(said)\n").utf8))
        }
        // Only ever for taking a picture of the other theme. The app itself
        // follows the Mac and has no appearance setting.
        if let at = args.firstIndex(of: "--appearance"), at + 1 < args.count {
            NSApp.appearance = NSAppearance(
                named: args[at + 1] == "dark" ? .darkAqua : .aqua
            )
        }
    }

    /// `--snapshot <path>` photographs the window and quits.
    ///
    /// The app has to be checked by looking, and driving the screen from
    /// outside is both fragile and something Nathaniel has asked us not to do.
    /// So it takes its own picture: the window draws itself into a bitmap,
    /// which is the same pixels a screenshot would get without any of the
    /// machinery.
    /// `--drag <points>` works the sidebar divider with real mouse events before
    /// the picture is taken.
    ///
    /// The point is to exercise the gesture rather than the arithmetic behind
    /// it. Calling the clamp directly would prove nothing: the bug it is fixing
    /// lived in how SwiftUI delivers a stream of drag updates, not in the sum.
    /// So these are `NSEvent`s posted into the app's own queue — the same route
    /// the old app takes for keys. Nothing touches the pointer on screen, which
    /// matters while Nathaniel is working on the other monitor.
    /// `--type <word>` types a whole word onto the selected cell with real key
    /// events and reports what the engine ended up holding.
    ///
    /// This is the check that would have caught the bug where exactly the first
    /// character landed: a photograph shows a cell that looks like it is being
    /// typed into, and only the committed value tells you the rest of the word
    /// went nowhere. The assertion is the *value*, never the appearance.
    /// Runs the closure when the app is genuinely ready to be driven.
    ///
    /// Quiet runs are ready after a fixed settle. A loud run is ready when it
    /// **actually holds the keyboard** — active app, key window — and not a
    /// moment sooner: back-to-back loud launches race each other's
    /// deactivation, and a run that starts driving before it has the keys
    /// silently exercises the fallback path while claiming to test the real
    /// one, which is the exact lie this lane exists to end. Polls up to six
    /// seconds, re-asserting activation each tick; gives up loudly, never
    /// silently.
    private func whenReady(_ then: @escaping (NSWindow) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // **Wait for the window rather than give up on it.**
            //
            // This was one look and `else { return }` — so a run whose window
            // was a moment late did nothing at all: no keys typed, no clicks,
            // and **not a word about why.** The check that followed then
            // failed on the app for a reason that had nothing to do with the
            // app. Measured 2026-08-23 while writing the references board's
            // arrows: one run in three on a busy machine, and it looked
            // exactly like an intermittent bug in the feature.
            //
            // The paragraph above already promised this — *"gives up loudly,
            // never silently"* — and it was only true of the half below.
            var looks = 0
            func window(_ found: @escaping (NSWindow) -> Void) {
                if let ready = NSApp.windows.first(where: { $0.isVisible }) {
                    found(ready)
                    return
                }
                looks += 1
                if looks > 80 {
                    FileHandle.standardError.write(Data((
                        "NO WINDOW AFTER SIX SECONDS — this run drove nothing, so "
                        + "anything below is the app at rest and not a reading of "
                        + "what was asked for\n").utf8))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { window(found) }
            }
            window { window in
            guard Self.loud else { then(window); return }
            var tries = 0
            // A sheet — project settings, the columns editor, the project
            // browser — becomes the key window when it opens, and the main
            // window behind it is then correctly not key. Demanding the MAIN
            // window meant a run that opened a sheet reported that it never
            // got the keyboard, when in truth it had it and was holding it
            // in front of exactly the thing being checked.
            func ours() -> Bool { NSApp.keyWindow != nil }
            func poll() {
                if NSApp.isActive && (window.isKeyWindow || ours()) {
                    // And it keeps them. The previous loud run's last act is
                    // returning the front to whoever had it — which can land
                    // *after* this run has taken the keys, yanking them away
                    // mid-drive. The result was chords and caret clicks that
                    // failed on some runs and passed on others: the exact
                    // flakiness this lane exists to end. So a loud run
                    // defends its keyboard for its whole length; the final
                    // victim-restore still runs at finish.
                    let keeper = Timer(timeInterval: 0.05, repeats: true) { _ in
                        guard !NSApp.isActive || NSApp.keyWindow == nil else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        // Only the main window is re-ordered, and only when
                        // none of ours is key: pulling it forward while a
                        // sheet is up would take the keyboard off the sheet
                        // being checked.
                        window.makeKeyAndOrderFront(nil)
                    }
                    RunLoop.main.add(keeper, forMode: .common)
                    self.loudKeeper = keeper
                    then(window)
                    return
                }
                tries += 1
                if tries > 60 {
                    FileHandle.standardError.write(Data((
                        "LOUD RUN NEVER GOT THE KEYBOARD — active \(NSApp.isActive), "
                        + "key \(window.isKeyWindow); results below are the fallback "
                        + "path, not the real one\n").utf8))
                    then(window)
                    return
                }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
            }
            poll()
            }
        }
    }

    private func typeThenSnapshot(_ word: String) {
        whenReady { window in
            let state = ShellState.shared
            var delay = 0.0

            func post(_ characters: String, _ code: UInt16) {
                delay += 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let event = NSEvent.keyEvent(
                        with: .keyDown,
                        location: .zero,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        characters: characters,
                        charactersIgnoringModifiers: characters,
                        isARepeat: false,
                        keyCode: code
                    ) else { return }
                    NSApp.postEvent(event, atStart: false)
                }
            }

            let args = CommandLine.arguments
            // `--walk <n>` presses Down n times before Return, which is how the
            // recording's third behaviour is checked: type, arrow down the
            // filtered list, press Return, and the *highlighted* option is what
            // lands — not the letters that filtered it.
            var walk = 0
            if let at = args.firstIndex(of: "--walk"), at + 1 < args.count {
                walk = Int(args[at + 1]) ?? 0
            }
            // `--expect <value>` asserts something other than what was typed.
            // A picker that turns "Pro" into Profile is working; a check that
            // can only assert "what I typed came back" cannot tell that from a
            // picker that wrote "Pro".
            var expected = word
            if let at = args.firstIndex(of: "--expect"), at + 1 < args.count {
                expected = args[at + 1]
            }
            // `--hold` stops before Return so the open cell can be photographed.
            // A committed value says what the engine holds and nothing about
            // what the cell looked like while it was being typed into, and half
            // the defects in this table were only ever visible in that moment.
            let hold = args.contains("--hold")
            // `--right <n>` walks the cursor n columns right with real arrow
            // presses before typing. It is how the sideways scroll is checked:
            // putting the cursor on a column with `--cell` sets it before the
            // table is on screen, so nothing has *changed* and a scroll that
            // only happens on a change looks broken when it is not — and a
            // scroll that only happens at launch looks fine when it is.
            var right = 0
            if let at = args.firstIndex(of: "--right"), at + 1 < args.count {
                right = Int(args[at + 1]) ?? 0
            }
            for _ in 0..<right { post("", 124) }

            // A click after the letters, with no Return in between, is the
            // check for the rule a sheet lives by: **leaving a cell writes what
            // is in it.** Losing an edit because the person clicked the next
            // cell instead of pressing Return is the kind of thing that only
            // shows up when somebody is actually working.
            let thenTap = self.flag("--tap")
            let thenPaste = self.flag("--paste")
            // Tokens in the typed word for the keys that are not letters, so
            // a check can press what a hand presses, in the order a hand
            // presses it: "⏎" Shift-Return, "↩" Return, "⌫" Delete, "⇥" Tab,
            // "←→↑↓"
            // arrows, and "⌘" makes a chord of the next character (⌘a, ⌘c,
            // ⌘v, ⌘z…), which the menu bar routes to the first responder the
            // way a real chord is.
            let typist = Typist(window: window, start: delay)
            typist.play(word)
            // `--tdrag` runs after the word, so a check can open a cell and
            // then drag across its text.
            if let drag = self.flag("--tdrag") {
                typist.delay += 0.3
                self.textDrag(drag, in: window, after: typist.delay)
                typist.delay += 0.6
            }
            // `--after <tokens>` without a tap plays once the word and any
            // drag are done — how a check types into a selection it just made.
            if self.flag("--tap") == nil, let more = self.flag("--after") {
                typist.play(more)
            }
            delay = typist.delay
            for _ in 0..<walk { post("", 125) }
            // `--paste <text>` puts the text on the clipboard and presses ⌘V —
            // pasting a value onto a selected cell, the way a sheet takes one.
            if let thenPaste {
                delay += 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Never the general pasteboard: that is HIS clipboard, on
                    // the machine he is working at, and a checking run that
                    // replaces what he copied has stolen from him as surely
                    // as one that takes his focus. The value rides a private
                    // override the ⌘V handler prefers while checking.
                    Launch.pasteOverride = thenPaste
                    guard let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [.command],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        characters: "v", charactersIgnoringModifiers: "v",
                        isARepeat: false, keyCode: 9
                    ) else { return }
                    NSApp.postEvent(event, atStart: false)
                }
            }
            if !hold && thenTap == nil && thenPaste == nil
                && self.flag("--after") == nil { post("\r", 36) }

            // Read after the arrows have landed and before Return moves on:
            // Return commits *and steps*, so a column read afterwards is the
            // one it stepped to — a fault in the check, not in the app.
            var before = state.cursorColumn
            var target = state.cursorShot
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(right) + 0.02) {
                before = state.cursorColumn
                target = state.cursorShot
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.8) {
                if let thenTap {
                    _ = self.click(thenTap, in: window)
                    // `--after <tokens>` types once the click has landed —
                    // the only way to check what a click *did* to the caret:
                    // click into a word, type a letter, and the letter's
                    // landing place is the caret's answer.
                    var settle = 0.35
                    if let more = self.flag("--after") {
                        let typist = Typist(window: window, start: 0.4)
                        typist.play(more)
                        settle = typist.delay + 0.5
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + settle + 0.25) {
                        let landed = state.view?.allRows
                            .first { $0.id == target }
                            .map { Columns.value($0, before) } ?? "<no row>"
                        let verdict = landed == expected ? "MATCHES" : "WRONG"
                        // Two lines, built apart — one expression was too
                        // much for the type-checker under Xcode 27.
                        var typed = "typed \"\(word)\" into \(before), then clicked away  →  "
                        typed += "engine holds \"\(landed)\"  \(verdict)\n"
                        typed += "  cursor now \(state.cursorColumn), editing \(state.editing), "
                        typed += "buffer \"\(state.editSeed)\"\n"
                        FileHandle.standardError.write(Data(typed.utf8))
                        self.reportColumns()
                self.snapshotIfAsked(after: 0.1)
                    }
                    return
                }
                if hold {
                    FileHandle.standardError.write(Data((
                        "held open: editing \(state.editing), buffer \"\(state.editSeed)\", "
                        + "highlight \(state.pickAt)\n").utf8))
                    self.reportColumns()
                // A `--wheel` run is waiting to land on the open list.
                self.snapshotIfAsked(after: args.contains("--wheel") ? 4.5 : 0.1)
                    return
                }
                let landed = state.view?.allRows
                    .first { $0.id == target }
                    .map { Columns.value($0, before) } ?? "<no row>"
                let verdict = landed == expected ? "MATCHES" : "WRONG"
                FileHandle.standardError.write(Data((
                    "keys seen by the table: \(state.keysSeen), "
                    + "editing: \(state.editing), live: \(state.editorLive), "
                    + "buffer: \"\(state.editSeed)\", "
                    + "cursor: \(state.cursorShot ?? "none")/\(before)\n").utf8))
                let restingRow = state.view?.allRows.first { $0.id == state.cursorShot }?.number ?? "?"
                FileHandle.standardError.write(Data((
                    "cursor rests on \(restingRow) \(state.cursorColumn), "
                    + "editing \(state.editing)\n").utf8))
                let wanted = expected == word ? "" : " (expected \"\(expected)\")"
                let report = "typed \"\(word)\"\(walk > 0 ? " ↓\(walk)" : "") into \(before)"
                    + "  →  engine holds \"\(landed)\"\(wanted)  \(verdict)\n"
                FileHandle.standardError.write(Data(report.utf8))
                if landed != expected {
                    let why = "TYPING DROPPED CHARACTERS — a cell that looks open "
                        + "is not the same as a cell that is taking keys\n"
                    FileHandle.standardError.write(Data(why.utf8))
                }
                self.reportColumns()
                self.snapshotIfAsked(after: 0.1)
            }
        }
    }

    /// `--tap <x>,<y>` clicks once, in window points from the top left.
    ///
    /// The keyboard path through the table is checked to death and the pointer
    /// path is not, which is backwards: choosing an option by clicking it is
    /// how most of them will be chosen. Nothing here touches the real pointer —
    /// the event is posted into this app's own queue, so his cursor stays where
    /// it is.
    /// Clicks once at a point given in window points from the top left.
    ///
    /// A third number is the click count, so `--tap 600,400,2` is a
    /// double-click — which is its own behaviour in a table and had its own
    /// bug: opening a cell empty and then writing that emptiness over the
    /// value.
    private func click(_ spec: String, in window: NSWindow) -> Bool {
        let fields = spec.split(separator: ",").map(String.init)
        let parts = fields.compactMap { Double($0) }
        guard parts.count >= 2 else { return false }
        let clicks = parts.count > 2 ? Int(parts[2]) : 1
        // A fourth field carries modifiers by letter — "s" shift, "c"
        // command — so a check can range-select and toggle the way a hand
        // does: --tap "700,370,1,s" is a shift-click.
        var flags: NSEvent.ModifierFlags = []
        if fields.count > 3 {
            if fields[3].contains("s") { flags.insert(.shift) }
            if fields[3].contains("c") { flags.insert(.command) }
        }
        // Posted in AppKit's coordinates, which count up from the bottom,
        // while every measurement taken off a screenshot counts down from the
        // top. Converting here means the number in the check is the number
        // read off the picture.
        var point = CGPoint(x: parts[0], y: window.frame.height - parts[1])
        // **A sheet is its own window.** The Projects panel, the columns
        // editor and every other sheet sit in a window of their own on top
        // of the main one, and an event posted to the main window's number
        // lands underneath them — on a table the sheet has already made
        // deaf. The photograph a check reads its numbers off shows the sheet
        // in the main window's frame, so the number is right; only the
        // address was wrong. 2026-09-15, found while trying to click a film
        // in the Projects panel.
        var target = window
        if let sheet = window.attachedSheet {
            point = sheet.convertPoint(fromScreen: window.convertPoint(toScreen: point))
            target = sheet
        }
        if let hit = target.contentView?.superview?.hitTest(point) {
            let frame = hit.convert(hit.bounds, to: nil)
            FileHandle.standardError.write(Data(
                "click at \(point) hits \(type(of: hit)) whose window frame is \(frame)\n".utf8))
        }
        for press in 1...max(1, clicks) {
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: kind, location: point, modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: target.windowNumber, context: nil,
                    eventNumber: 0, clickCount: press,
                    pressure: kind == .leftMouseUp ? 0 : 1
                ) else { return false }
                NSApp.postEvent(event, atStart: false)
            }
        }
        return true
    }

    /// Plays a token string as key events posted to a window: letters as
    /// themselves, "↩" Return, "⏎" Shift-Return, "⌫" Delete, "⇥" Tab,
    /// "←→↑↓" arrows,
    /// "⌘x" a command chord. One player, so the main typing pass and the
    /// after-a-click pass cannot drift apart in how they press keys.
    final class Typist {
        let window: NSWindow
        var delay: TimeInterval

        init(window: NSWindow, start: TimeInterval) {
            self.window = window
            self.delay = start
        }

        private func send(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) {
            delay += flags.isEmpty ? 0.05 : 0.09
            let when = delay
            let window = window
            DispatchQueue.main.asyncAfter(deadline: .now() + when) {
                // The window that has the keyboard **now**, not the one this
                // typist was made for. A sheet — project settings, the
                // columns editor, the project browser — becomes the key
                // window when it opens, and keys addressed to the window
                // behind it are delivered to nothing. Read at send time,
                // because the sheet may not have existed when the run began.
                let target = NSApp.keyWindow ?? window
                guard let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: target.windowNumber, context: nil,
                    characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code
                ) else { return }
                NSApp.postEvent(event, atStart: false)
            }
        }

        func key(_ characters: String, _ code: UInt16) { send(characters, code, []) }

        func play(_ word: String) {
            let letters = Array(word)
            var at = 0
            while at < letters.count {
                switch letters[at] {
                case "⏎": send("\r", 36, [.shift])
                case "↩": send("\r", 36, [])
                case "⌫": send("\u{7f}", 51, [])
                case "⎋": send("\u{1b}", 53, [])
                case "⇥": send("\t", 48, [])
                case "⇤": send("\t", 48, [.shift])
                // ⇧ before an arrow, or ⌘⇧ before one: stretching a block.
                case "⇧":
                    if at + 1 < letters.count {
                        at += 1
                        let code: UInt16? = ["←": 123, "→": 124, "↓": 125, "↑": 126][letters[at]]
                        if let code { send("", code, [.shift]) }
                    }
                case "←": send("", 123, [])
                case "→": send("", 124, [])
                case "↑": send("", 126, [])
                case "↓": send("", 125, [])
                case "⌘", "⌃":
                    // A capital letter after the modifier carries shift, the
                    // way a hand makes ⇧⌘Z. "⌘⌫" is command-delete and "⌃↩"
                    // control-return, with their real key codes.
                    let base: NSEvent.ModifierFlags =
                        letters[at] == "⌘" ? .command : .control
                    if at + 1 < letters.count {
                        at += 1
                        switch letters[at] {
                        case "⌫": send("\u{7f}", 51, base)
                        case "↩": send("\r", 36, base)
                        // Arrows under a modifier: ⌘↑/⌘↓ move a shot on the
                        // document page, and a chord is the only way to say
                        // so in a check.
                        case "⇧":
                            if at + 1 < letters.count {
                                at += 1
                                let code: UInt16? = ["←": 123, "→": 124, "↓": 125, "↑": 126][letters[at]]
                                if let code { send("", code, [base, .shift]) }
                            }
                        case "←": send("", 123, base)
                        case "→": send("", 124, base)
                        case "↑": send("", 126, base)
                        case "↓": send("", 125, base)
                        default:
                            let ch = String(letters[at])
                            let flags: NSEvent.ModifierFlags =
                                ch != ch.lowercased() ? [base, .shift] : base
                            send(ch.lowercased(), 0, flags)
                        }
                    }
                default: send(String(letters[at]), 0, [])
                }
                at += 1
            }
        }
    }

    /// `--tdrag x1,y1,x2,y2` presses at the first point, drags to the second
    /// and releases — selecting text inside an open editor the way a hand
    /// does. Window points from the top left, like `--tap`.
    private func textDrag(_ spec: String, in window: NSWindow, after: TimeInterval) {
        let p = spec.split(separator: ",").compactMap { Double($0) }
        guard p.count == 4 else { return }
        let from = CGPoint(x: p[0], y: window.frame.height - p[1])
        let to = CGPoint(x: p[2], y: window.frame.height - p[3])
        // Spaced in time, on a timer that runs in the run loop's *common*
        // modes — the one arrangement both customers accept. A SwiftUI drag
        // gesture needs the moves spread over time or it never fires; an
        // AppKit text view's mouseDown runs a tracking loop during which
        // plain main-queue timers are starved. Common-mode timers fire in
        // both worlds, so one drag routine serves selecting text and pulling
        // a column edge.
        var events: [(TimeInterval, NSEvent.EventType, CGPoint)] = [(0, .leftMouseDown, from)]
        for step in 1...8 {
            let f = CGFloat(step) / 8
            events.append((0.016 * Double(step), .leftMouseDragged,
                CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)))
        }
        events.append((0.016 * 9 + 0.1, .leftMouseUp, to))
        for (wait, kind, point) in events {
            let timer = Timer(timeInterval: after + wait, repeats: false) { _ in
                guard let event = NSEvent.mouseEvent(
                    with: kind, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1,
                    pressure: kind == .leftMouseUp ? 0 : 1
                ) else { return }
                NSApp.postEvent(event, atStart: false)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// One turn of the wheel over the middle of a window, in `steps` nudges.
    ///
    /// A scroll view follows steps, not one shove: sent as a single event a
    /// scroll lands as a flick and settles somewhere else entirely.
    private static func wheel(_ points: Double, over steps: Int,
                              in window: NSWindow,
                              then done: @escaping () -> Void) {
        let middle = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        for step in 0..<max(steps, 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02 * Double(step)) {
                guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                          units: .pixel, wheelCount: 1,
                                          wheel1: Int32(-points / Double(max(steps, 1))),
                                          wheel2: 0, wheel3: 0) else { return }
                event.location = CGPoint(x: window.frame.minX + middle.x,
                                         y: window.frame.minY + middle.y)
                if let ns = NSEvent(cgEvent: event) {
                    NSApp.postEvent(ns, atStart: false)
                }
                if step == max(steps, 1) - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: done)
                }
            }
        }
    }

    private func tapThenSnapshot(_ spec: String) {
        whenReady { window in
            let state = ShellState.shared
            guard self.click(spec, in: window) else { self.reportColumns()
                self.snapshotIfAsked(after: 0.1); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let held = state.view?.allRows
                    .first { $0.id == state.cursorShot }
                    .map { Columns.value($0, state.cursorColumn) } ?? "<no row>"
                FileHandle.standardError.write(Data((
                    "tapped \(spec)  →  \(state.cursorColumn) holds \"\(held)\", "
                    + "open: \(state.editing), buffer \"\(state.editSeed)\", "
                    + "marked: \(state.marked.count)\n").utf8))
                if let want = self.flag("--expect") {
                    let got = state.editSeed.isEmpty ? held : state.editSeed
                    let verdict = got == want ? "MATCHES" : "WRONG"
                    FileHandle.standardError.write(Data((
                        "expected \"\(want)\"  →  got \"\(got)\"  \(verdict)\n").utf8))
                }
                // Edit Reference: did the tap open a player, and which shot
                // did it leave the cursor on?
                if state.modsOn.contains("edit_reference") {
                    let row = state.view?.allRows.first { $0.id == state.cursorShot }?.number ?? "none"
                    FileHandle.standardError.write(Data("editref tap: player \(state.editRefPlaying == nil ? "closed" : "open"), cursor on \(row)\n".utf8))
                }
                self.reportColumns()
                self.snapshotIfAsked(after: 0.1)
            }
        }
    }

    /// `--columns` prints the visible order and each column's width at read
    /// time, so a resize or reorder check asserts numbers rather than a
    /// screenshot.
    /// `--locations` prints every location record and what hangs on it, so a
    /// check about the Locations screen asserts what the *engine* holds rather
    /// than what a screenshot appears to show.
    ///
    /// Written the way `shots:` is: one line, every record, pipe-separated —
    /// because the failure this has to be able to see is "it went onto the
    /// wrong one", and a report scoped to the selected record cannot see that.
    /// Which scenes are picked, by number — Ref 240.
    ///
    /// **Printed late, with the other reports.** The first version of this sat
    /// with the `project:` line at launch and always printed nothing, because
    /// the posture flags have not run yet at that point. A report that runs
    /// before the thing it reports on is a check that can only ever pass by
    /// accident.
    ///
    /// Standing on a scene and having several picked are different facts, so
    /// both are said.
    private func reportPickedScenes() {
        guard CommandLine.arguments.contains("--pickscenes") else { return }
        let state = ShellState.shared
        let scenes = state.view?.scenes ?? []
        let picked = state.pickedScenes
            .compactMap { id in scenes.first { $0.id == id }?.number }
            .sorted()
            .joined(separator: ",")
        FileHandle.standardError.write(Data((
            "standing on: \(scenes.first { $0.id == state.sceneId }?.number ?? "none")"
            + "  picked scenes: \(picked)\n").utf8))
    }

    private func reportLocations() {
        guard CommandLine.arguments.contains("--locations") else { return }
        let state = ShellState.shared
        let all = (state.view?.locations ?? []).map { place -> String in
            let pin = place.pin.map { String(format: "%.4f/%.4f", $0.latitude, $0.longitude) }
                ?? "no pin"
            // **The full name and the address as shown**, not the record's own
            // halves — Ref 269 turns on a room borrowing the house's address,
            // and a report that printed only the record's own field would
            // show every room as having no address and read as a bug. A
            // borrowed one is marked so the two cannot be confused. This is
            // the third instrument this week to nearly lie by printing the
            // narrower of two truths; print both.
            let shown = place.effectiveAddress.replacingOccurrences(of: "\n", with: " · ")
            return [place.fullName.isEmpty ? place.name : place.fullName,
                    place.addressIsInherited ? "(from house) " + shown : shown,
                    pin,
                    "\(place.scenes.count) scenes",
                    "\(place.scenesInside) inside",
                    "\(place.areas.count) areas",
                    "\(place.photos.count) photos",
                    place.effectiveNotes.prefix(20)]
                .map(String.init(describing:))
                .joined(separator: "; ")
        }.joined(separator: " | ")
        FileHandle.standardError.write(Data(("locations: " + all + "\n").utf8))
        FileHandle.standardError.write(Data((
            "open location: \(state.location?.name ?? "none")"
            + "  tab: \(state.sideTab.rawValue)\n").utf8))
        FileHandle.standardError.write(Data((
            "photo shape: \(state.locationRatioMode)\n").utf8))
        // **The two facts, side by side.** A scene's `location` is the word the
        // script wrote on its slugline; its location *record* is the address
        // the crew drives to. They are the pair a wrong field name would
        // silently conflate, and nothing on screen would look wrong when it
        // did — so they are printed together, every scene, one line.
        // **All of the records, not the first one.** A scene can be shot at
        // several places since 2026-08-22, and a report that printed only the
        // first would show a scene that moves between two as if it moved
        // between none.
        let pairs = (state.view?.scenes ?? []).map { scene -> String in
            let names = (state.view?.locations ?? [])
                .filter { scene.locations.contains($0.id) }
                .map(\.fullName)
            let record = names.isEmpty ? "none" : names.joined(separator: "+")
            return "\(scene.number)=\(scene.location.isEmpty ? "—" : scene.location)/\(record)"
        }.joined(separator: " | ")
        FileHandle.standardError.write(Data(("scene locations: " + pairs + "\n").utf8))
        // Which photograph is picked, and whether the pop-out is up. His
        // 2026-08-21 ask has two halves that look identical in a photograph —
        // "a blue box and nothing else" versus "a blue box and a window" — so
        // the difference is said in words.
        let photos = state.location?.photos ?? []
        let at = photos.firstIndex { $0.ref == state.pickedPhoto }
        let picked = at.map { "\($0 + 1)" } ?? "none"
        // Built up a piece at a time — one expression was too much for the
        // type-checker under Xcode 27 (2026-09-20).
        var line = "photos: \(photos.count)  marked: \(state.pickedPhotos.count)  picked: \(picked)"
        line += "  across: \(state.photosAcross)"
        line += "  viewer: \(Viewer.shared.isOpen)"
        line += "  cached: \(Thumbs.shared.held)"
        line += "  waiting: \(Thumbs.shared.waiting)\n"
        FileHandle.standardError.write(Data(line.utf8))
        // **By name.** Twice in one evening a count went wrong and the count
        // alone could not say why — a re-encode changing an extension looks
        // exactly like a photograph nobody has seen.
        FileHandle.standardError.write(Data((
            "photo names: " + photos.map(\.filename).joined(separator: ", ") + "\n").utf8))
    }

    /// What the project keeps of its script — the drafts it has taken in, and
    /// the shape the latest one lays out to.
    private func reportScript() {
        guard CommandLine.arguments.contains("--revisions") else { return }
        let state = ShellState.shared
        let kept = state.engine?.revisions() ?? []
        FileHandle.standardError.write(Data((
            "revisions: \(kept.count)"
            + (kept.isEmpty ? "" : "  [" + kept.map {
                "\($0.name)/\($0.filename)\($0.latest ? "*" : "")"
            }.joined(separator: " ") + "]")
            + "\n").utf8))
        let pages = state.engine?.scriptPages()
        FileHandle.standardError.write(Data((
            "script pages: \(pages?.pages ?? 0)  scenes \(pages?.scenes.count ?? 0)"
            + (pages.map { "  [" + $0.scenes.map { "\($0.label)=\($0.length)" }
                .joined(separator: " ") + "]" } ?? "")
            + "\n").utf8))
    }

    /// **Every key the menu bar answers to.** A shortcut is a promise made in
    /// a menu and kept by the responder chain, and nothing else in the harness
    /// can see the menu bar at all — so a shortcut that silently stopped
    /// working would look exactly like one that works.
    private func reportMenu() {
        guard CommandLine.arguments.contains("--menu") else { return }
        var found: [String] = []
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    let mods = item.keyEquivalentModifierMask
                    let said = (mods.contains(.command) ? "⌘" : "")
                        + (mods.contains(.shift) ? "⇧" : "")
                        + (mods.contains(.option) ? "⌥" : "")
                        + item.keyEquivalent
                    found.append("\(said)=\(item.title)")
                }
                if let under = item.submenu { walk(under) }
            }
        }
        if let bar = NSApp.mainMenu { walk(bar) }
        FileHandle.standardError.write(Data((
            "menu keys: " + found.joined(separator: " ") + "\n").utf8))
        // **Titles as well as keys.** The line above only sees an item that
        // carries a shortcut, so an item with none — *Set Up Sync…*, which is
        // the only way into sync on a Mac that has never had it — was
        // invisible to every check. An entry point nothing can see is the exact
        // bug the sheet exists to fix.
        var titles: [String] = []
        func names(_ menu: NSMenu) {
            for item in menu.items where !item.title.isEmpty {
                titles.append(item.title)
                if let under = item.submenu { names(under) }
            }
        }
        if let bar = NSApp.mainMenu { names(bar) }
        FileHandle.standardError.write(Data((
            "menu items: " + titles.joined(separator: " · ") + "\n").utf8))

        // **And then press one.** A menu item that exists and does nothing
        // looks identical to one that works, so a view key is actually sent
        // through the menu bar and the view it lands on is read back.
        //
        // **⌥⌘2, not ⌘2** — fixed 2026-09-02. This sent a plain ⌘2 and then
        // read back `state.tab`, which is the *view*. That was right until
        // 2026-08-23, when the modes took ⌘1–⌘4 and the views moved to
        // ⌥⌘1–⌥⌘3. From that day the press moved the mode and the report read
        // the view, so the one check that exists to prove a menu key does
        // something had been quietly proving nothing for ten days. It only
        // runs under `quick.sh --all`, which is why it sat there.
        let state = ShellState.shared
        func send(_ mods: NSEvent.ModifierFlags, _ characters: String) {
            guard let press = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: mods,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: "2",
                isARepeat: false, keyCode: 19) else { return }
            _ = NSApp.mainMenu?.performKeyEquivalent(with: press)
        }
        // **Both halves, because they are two different claims.** ⌘2 has to
        // move the mode and ⌥⌘2 has to move the view, and a check that only
        // presses one of them cannot tell a working pair from a swapped one —
        // which is exactly what went unnoticed from 2026-08-23 to 2026-09-02.
        //
        // The option press carries "™" as its characters, which is what the
        // keyboard actually produces for ⌥2; `charactersIgnoringModifiers`
        // stays "2", which is the half AppKit matches the menu on.
        let mode = state.sideTab
        send(.command, "2")
        let view = state.tab
        send([.command, .option], "™")
        FileHandle.standardError.write(Data((
            "menu press: ⌘2 mode \(mode.rawValue)→\(state.sideTab.rawValue)"
            + "  ⌘⌥2 view \(view.rawValue)→\(state.tab.rawValue)\n").utf8))
    }

    /// **What the filter is actually doing.** Every other report reads the
    /// outline, which is deliberately never narrowed, so a filter that did
    /// nothing and a filter that did everything looked identical from outside.
    private func reportFilter() {
        guard CommandLine.arguments.contains("--filtering") else { return }
        let state = ShellState.shared
        let f = state.view?.filter
        let facets = state.facets.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        FileHandle.standardError.write(Data((
            "filter: shown \(f?.shown ?? -1)"
            + "  hiddenScenes \(f?.hiddenScenes ?? -1)"
            + "  narrowed \(f?.narrowed ?? false)"
            + "  facets [\(facets)]\n").utf8))
        // And what the menus would offer — an empty submenu is a filter that
        // cannot be used at all, which looks exactly like one that does nothing.
        let offered = Sidebar.sceneFacets.map { facet -> String in
            "\(facet.field):\(ShellState.shared.sceneValueCount(facet.field))"
        }.joined(separator: " ")
        FileHandle.standardError.write(Data((
            "filter options: " + offered + "\n").utf8))
        // **And what the chips say**, which is the only part of this a person
        // reads. Every line above prints the value narrowed *by* — for a
        // location that is an id, and printing it is correct — so the chip
        // could print the id too and no check could tell. Ref 301.
        let chips = FilterBar.chips(state)
            .map { "\($0.field)→\($0.label)" }.joined(separator: " ")
        FileHandle.standardError.write(Data((
            "filter chips: " + chips + "\n").utf8))
    }

    /// **What colour the app is wearing, and whether the film has a mark.**
    ///
    /// The accent is the one thing in the window that cannot be photographed
    /// into a check — it is a colour, and every check reads words. So it says
    /// itself: `accent: #D44C47  mark: yes` for a film whose Notion row has an
    /// icon, `accent: default  mark: none` for one that has not.
    private func reportMark() {
        guard CommandLine.arguments.contains("--accent") else { return }
        let worn = Brand.wearing
        FileHandle.standardError.write(Data((
            "accent: \(worn.isEmpty ? "default" : worn)"
            + "  mark: \(ShellState.shared.mark == nil ? "none" : "yes")\n").utf8))
    }

    /// `--cells size,tags` prints what every shot of the film holds in those
    /// columns (`cells size: 33A=CU|34A=…`), the clipboard the run was
    /// copying through, and how deep the undo history stands — the three
    /// things a copy, cut, paste, undo or redo check has to read.
    private func reportCells() {
        guard let spec = flag("--cells") else { return }
        let state = ShellState.shared
        for asked in spec.split(separator: ",").map(String.init) {
            let name = Columns.resolve(asked, state: state)
            let line = (state.view?.allRows ?? [])
                .map { "\($0.number)=\(Columns.value($0, name))" }
                .joined(separator: "|")
            FileHandle.standardError.write(Data(("cells \(asked): " + line + "\n").utf8))
        }
        let held = (Launch.pasteOverride ?? "<none>")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        FileHandle.standardError.write(Data(("clip: " + held + "\n").utf8))
        if let history = state.engine?.history() {
            FileHandle.standardError.write(Data((
                "history: depth \(history.depth) undo \"\(history.undoLabel)\""
                + " redo \"\(history.redoLabel)\"\n").utf8))
        }
    }

    private func reportColumns() {
        // **What the pictures cost the drawing thread.** Every one of these
        // milliseconds is a millisecond the window was not answering: the
        // read happens inside a view body, on the main thread.
        FileHandle.standardError.write(Data((
            "picture reads: \(Thumbs.shared.reads)"
            + String(format: "  spent: %.0fms  worst: %.0fms\n",
                     Thumbs.shared.spentMs, Thumbs.shared.worstMs)).utf8))
        reportLocations()
        reportPickedScenes()
        reportScript()
        reportMenu()
        reportFilter()
        reportMark()
        reportCells()
        guard CommandLine.arguments.contains("--columns") else { return }
        let state = ShellState.shared
        var line = (state.view?.columns ?? [])
            .filter(\.visible)
            .map { "\($0.name)=\(Int(Columns.width($0.name)))" }
            .joined(separator: " ")
        if let sorted = state.view?.filter.sortColumn, !sorted.isEmpty {
            line += "  sort=\(sorted)\(state.view?.filter.sortDescending == true ? " desc" : " asc")"
        }
        // Each row carries the head of its description: letters reflow in
        // prep, so after a reorder the numbers alone read exactly as they did
        // before it — the words are what moved.
        // Which rows carry a picture. Kept on its own line rather than folded
        // into `rows=`, which several checks match on exactly.
        let framed = (state.view?.allRows ?? [])
            .filter { $0.sceneId == state.scene?.id }
            .map { $0.number + ($0.frame == nil ? ":none" : ":\($0.frames)") }
            .joined(separator: ",")
        FileHandle.standardError.write(Data(("frames: " + framed + "\n").utf8))
        line += "  rows=" + (state.view?.allRows.filter { $0.sceneId == state.scene?.id }
            .map { $0.number + ($0.struck ? "✕" : "") + ($0.colour != nil ? "•" : "")
                   + ($0.isMaster ? "M" : "") + ($0.linkedTo.map { "→\($0)" } ?? "")
                   + ":" + $0.description.prefix(5) }
            .joined(separator: ",") ?? "")
        // How many shots the list is showing, and whether anything is
        // narrowing it. The rows line above is the *cursor's scene* only, so
        // under a filter it can be empty while the list is full — which read
        // as "the filter broke" when the filter was working perfectly.
        if let filter = state.view?.filter {
            FileHandle.standardError.write(Data((
                "showing: \(filter.shown) shots  narrowed: \(filter.narrowed)"
                + "  hidden scenes: \(filter.hiddenScenes)\n").utf8))
        }
        // **Which scene this run is actually on** — Ref 101.
        //
        // Every check that asserts a position assumes it is looking at the
        // scene it asked for, and nothing ever said whether it was. A filter
        // that empties the scene you are on takes it out of the list, and the
        // app then falls back to the first scene in the film — reasonable in
        // the hand, and invisible to a check, which goes on asserting rows
        // against a scene it is no longer looking at. That is how a battery
        // starts passing and failing for reasons that have nothing to do with
        // what it is testing.
        //
        // Said out loud rather than left to be assumed, and said **loudly**
        // when it does not match, the way a stolen focus is: a check reads the
        // marker and refuses to report a result at all.
        let on = state.scene?.number ?? "-"
        var sitting = "on scene: \(on)"
        if let at = CommandLine.arguments.firstIndex(of: "--scene"),
           at + 1 < CommandLine.arguments.count {
            let asked = CommandLine.arguments[at + 1]
            if asked != on {
                sitting = "WRONG SCENE — asked for \(asked), sitting on \(on); "
                    + "anything below is about \(on)"
            }
        }
        FileHandle.standardError.write(Data((sitting + "\n").utf8))
        FileHandle.standardError.write(Data(("columns: " + line + "\n").utf8))
        // What the columns were handed and what they did with it. Without this
        // "the table fills a wide window" is a claim no check can test.
        FileHandle.standardError.write(Data(
            ("spread: \(Int(Columns.spread))  measured: \(Int(Columns.lastMeasured))"
             + "  table: \(Int(Columns.lastFrame.minX))..\(Int(Columns.lastFrame.maxX))"
             + "  panel: \(Int(state.panelWidth))\n").utf8))
        // **Every scene and what is in it.** The `rows=` above is the cursor's
        // scene only, so a shot that landed in the wrong scene was invisible
        // to every check in the battery — which is how his ⌘⏎ bug shipped.
        let everywhere = (state.view?.scenes ?? []).map { scene in
            scene.number + ":" + (state.view?.allRows
                .filter { $0.sceneId == scene.id }
                .map(\.number)
                .joined(separator: ",") ?? "")
        }.joined(separator: " | ")
        FileHandle.standardError.write(Data(("shots: " + everywhere + "\n").utf8))
        // Whether a cell is open, and who actually holds the keyboard. The
        // second half is the one that mattered on 2026-08-20: a search field
        // holding the window's field editor was swallowing Return.
        let responder = NSApp.keyWindow?.firstResponder
        FileHandle.standardError.write(Data((
            "cursor: \(state.cursorColumn) open: \(state.editing) "
            + "seed \"\(state.editSeed)\" pickAt \(state.pickAt) "
            + "responder: \(responder.map { String(describing: type(of: $0)) } ?? "none")"
            + "\n").utf8))
        let marked = (state.view?.allRows ?? [])
            .filter { state.marked.contains($0.id) }
            .map(\.number).joined(separator: ",")
        FileHandle.standardError.write(Data(("marked: " + marked + "\n").utf8))
        // Whole shots — the ringed rows — reported by number, so a check can
        // say what the carry was actually holding.
        let whole = (state.view?.allRows ?? [])
            .filter { state.wholeShots.contains($0.id) }
            .map(\.number).joined(separator: ",")
        FileHandle.standardError.write(Data(("whole: " + whole + "\n").utf8))
        // The dragged rectangle, by shot number and column. Nothing in the
        // battery could see this before, which is how "click and drag to
        // select cells" could stop working while every range check passed —
        // they all reached the range through `--tdrag` *after* a `--type`, and
        // never on its own.
        let numberOf: (String) -> String = { id in
            (state.view?.allRows ?? []).first { $0.id == id }?.number ?? "?"
        }
        var range = ""
        if let box = state.cellRange {
            let a: String = numberOf(box.anchorRow)
            let b: String = numberOf(box.endRow)
            range = a + "/" + box.anchorColumn + ".." + b + "/" + box.endColumn
        }
        FileHandle.standardError.write(Data(("range: " + range + "\n").utf8))
        // What ⌘C or ⌘X outlined, same spelling, and whether a cut is waiting.
        var ants = ""
        if let box = state.copiedCells {
            ants = numberOf(box.anchorRow) + "/" + box.anchorColumn + ".."
                + numberOf(box.endRow) + "/" + box.endColumn
                + (state.copiedCut ? " cut" : "")
        }
        FileHandle.standardError.write(Data(("ants: " + ants + "\n").utf8))
        FileHandle.standardError.write(Data(("cursor: " + numberOf(state.cursorShot ?? "")
            + "/" + state.cursorColumn + "\n").utf8))
        // Titles, on their own line: the document page can put the keyboard
        // in a shot's title, and the rows line above reads descriptions
        // only. Its own line so no existing check's pattern moves.
        let titles = (state.view?.allRows.filter { $0.sceneId == state.scene?.id }
            .map { $0.number + ":" + $0.title }
            .joined(separator: ",")) ?? ""
        FileHandle.standardError.write(Data(("titles: " + titles + "\n").utf8))
        let frames = state.headerFrames
            .sorted { $0.value.minX < $1.value.minX }
            .map { "\($0.key)@\(Int($0.value.minX))..\(Int($0.value.maxX)),y\(Int($0.value.minY))..\(Int($0.value.maxY))" }
            .joined(separator: " ")
        FileHandle.standardError.write(Data(("header frames: " + frames + "\n").utf8))
        // Rows too — their heights follow their content, so a battery that
        // guesses a row's y is guessing wrong by the tenth check. Numbers
        // reflow in prep; the id pins the report to reality.
        let rowLine = state.rowFrames
            .sorted { $0.value.minY < $1.value.minY }
            .map { id, rect in
                let number = state.view?.allRows.first { $0.id == id }?.number ?? "?"
                return "\(number)@y\(Int(rect.minY))..\(Int(rect.maxY))"
            }
            .joined(separator: " ")
        // The project's own columns, visible or not — a new one arrives hidden,
        // so the visible list above cannot say whether one exists.
        let ours = Columns.custom
            .sorted { $0.key < $1.key }
            .map { "\($0.value.label)/\($0.value.kind)" }
            .joined(separator: " ")
        FileHandle.standardError.write(Data(("custom columns: " + ours + "\n").utf8))
        // **And what each one's list holds.** Ref 346 — a ready-made column can
        // arrive already knowing its terms, and the report said only that the
        // column existed, which is the half that was never in doubt.
        for (field, column) in Columns.custom.sorted(by: { $0.key < $1.key })
        where column.kind == "single" || column.kind == "multi" {
            let known = state.engine?.vocabulary(field) ?? []
            FileHandle.standardError.write(Data((
                "list: \(column.label) (\(field)) "
                + "[\(known.joined(separator: ", "))]\n").utf8))
        }
        FileHandle.standardError.write(Data(("row frames: " + rowLine + "\n").utf8))
        // **The two heights the mouse maths depends on.** Every click that
        // works by position is turned from `locationInWindow` into the same
        // space the frames are recorded in by subtracting the window's height.
        // If the window and its content view are not the same height, every one
        // of those clicks is off by the difference — and a click that lands
        // between rows does nothing at all, silently. Ref 113.
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            let content = window.contentView?.frame.height ?? -1
            FileHandle.standardError.write(Data((
                "mouse space: window \(Int(window.frame.height))"
                + "  content \(Int(content))"
                + "  gap \(Int(window.frame.height - content))\n").utf8))
        }
        if let row = state.view?.allRows.first(where: { $0.id == state.cursorShot }) {
            FileHandle.standardError.write(Data((
                "layout: \(row.number) \(row.framePosition)@"
                + String(format: "%.2f", row.frameWidth) + "\n").utf8))
        }
        if let scene = state.view?.scenes.first(where: { $0.id == state.scene?.id }) {
            // Which reference on the board is picked, and how many are marked —
            // the board's half of the same grammar the photograph wall has.
            let refs = scene.attachments
            let at = refs.firstIndex { $0.ref == state.pickedPhoto }
            FileHandle.standardError.write(Data((
                "references: \(refs.count)"
                + "  picked: \(at.map { String($0 + 1) } ?? "none")"
                + "  marked: \(state.pickedPhotos.count)\n").utf8))
            // Built up a piece at a time — one expression was too much for
            // the type-checker under Xcode 27 (2026-09-20).
            let rich = scene.notesRich?.isEmpty == false
            var notes = "scene notes: \"\(scene.notes)\"  rich: \(rich)"
            notes += "  attachments: \(scene.attachments.count)"
            if !scene.attachments.isEmpty {
                let names = scene.attachments.map { "\($0.filename)/\($0.kind)" }
                notes += " [" + names.joined(separator: " ") + "]"
            }
            notes += "\n"
            FileHandle.standardError.write(Data(notes.utf8))
        }
        if !state.cardFrames.isEmpty {
            let cards = state.cardFrames
                .sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
                .map { id, rect in
                    let number = state.view?.allRows.first { $0.id == id }?.number ?? "?"
                    return String(format: "%@ @%.0f,%.0f %.0fx%.0f=%.3f", number,
                                  rect.minX, rect.minY,
                                  rect.width, rect.height, rect.width / max(rect.height, 1))
                }
                .joined(separator: " · ")
            FileHandle.standardError.write(Data(("card frames: " + cards + "\n").utf8))
        }
    }

    private func flag(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: name), at + 1 < args.count else { return nil }
        return args[at + 1]
    }

    /// Lay the whole window out `times` over, and say what each one cost.
    private func timeRedraws(_ times: Int) {
        let state = ShellState.shared
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
            FileHandle.standardError.write(Data("redraws: no window\n".utf8))
            return
        }
        var total = 0.0
        var worst = 0.0
        var asking = 0.0
        for _ in 0..<max(1, times) {
            // **Two halves, timed apart.** Asking the engine for a fresh view
            // model is a whole document serialised to JSON and parsed back;
            // drawing is every body in the tree. They are wildly different
            // costs and a single number hides which one is hurting.
            let opened = CFAbsoluteTimeGetCurrent()
            let fresh = state.engine?.view()
            asking += (CFAbsoluteTimeGetCurrent() - opened) * 1000
            // **What SwiftUI actually does, not what it can be forced to
            // do.** Marking the content view `needsLayout` and laying the
            // whole tree out measures a worst case nothing ever asks for;
            // flushing the transaction measures the update SwiftUI decided to
            // make, which is the one his keystroke pays for.
            Built.reset()
            let began = CFAbsoluteTimeGetCurrent()
            state.replace(fresh)
            CATransaction.flush()
            let ms = (CFAbsoluteTimeGetCurrent() - began) * 1000
            total += ms
            worst = max(worst, ms)
        }
        let each = Double(max(1, times))
        FileHandle.standardError.write(Data(String(
            format: "redraws: %d  drawing: %.1fms each (worst %.1f)  asking: %.1fms each"
                  + "  built: %d rows %d paragraphs\n",
            times, total / each, worst, asking / each,
            Built.rows, Built.paragraphs).utf8))
    }

    private func driveThenSnapshot() {
        let args = CommandLine.arguments
        // `--churn` runs for as long as it was asked to and reports and
        // photographs itself at the end. Without this the ordinary finishing
        // path below photographed at 1.4 seconds and ended the app, so the
        // churn's own report never printed — the run looked like it had done
        // nothing, which is exactly what a silent bail-out looks like.
        if args.contains("--churn") { return }
        // **What one redraw of this screen costs.** His report, 2026-09-04:
        // *"it's feeling sluggish."*
        //
        // Nothing here could see that, and it is structural: every check draws
        // the screen **once** and photographs it, so a cost paid on every pass
        // — a list rebuilt, a colour parsed from a string, a font asked for
        // again — is paid once in a check and several hundred times a second
        // in his hands. This bumps the model the way a keystroke does and
        // makes the window lay itself out there and then, so the number is a
        // pass and not a launch.
        if let at = args.firstIndex(of: "--redraws"), at + 1 < args.count,
           let times = Int(args[at + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.timeRedraws(times)
                self.reportColumns()
                self.snapshotIfAsked(after: 0.1)
            }
            return
        }
        // `--mouse "down 500 190; move 500 360; up 500 360"` — a press, a
        // pull and a release, in window points from the top left, posted
        // into the app's own queue. **The Schedule's drags were never checked
        // by anything but his hand** because a drag session cannot be driven
        // by a synthetic mouse; the board carries things itself now
        // (`ScheduleHands.swift`), so this can drive it exactly as his mouse
        // does. It ends by printing every day's strips, the picked scenes, the
        // boards in order and what the hand did — then photographs if asked.
        // `--pagekeys "⇥; type Wide; ⌘↩"` — the document page driven by keys
        // alone, reporting after every step. See `PageKeys.swift`.
        if let at = args.firstIndex(of: "--pagekeys"), at + 1 < args.count {
            let script = args[at + 1]
            whenReady { window in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    PageKeys.drive(script, in: window) {
                        self.snapshotIfAsked(after: 0.1)
                    }
                }
            }
            return
        }
        if let at = args.firstIndex(of: "--mouse"), at + 1 < args.count {
            let script = args[at + 1]
            whenReady { window in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    BoardHands.drive(script, in: window) {
                        BoardHands.report()
                        self.snapshotIfAsked(after: 0.1)
                    }
                }
            }
            return
        }
        // `--stay <seconds>` holds the run open, doing nothing, the way a Mac
        // sits with the project open while somebody works on the other one.
        // It is the only way to check that this app **notices** the other
        // device rather than merely reading its work at open time.
        // `SHOTLISTER_STAY` is the same from the environment: with the screen
        // locked, a run that carries extra flags gets no window at all.
        if let seconds = (args.firstIndex(of: "--stay").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil })
            ?? ProcessInfo.processInfo.environment["SHOTLISTER_STAY"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                self.reportColumns()
                self.snapshotIfAsked(after: 0.1)
            }
            return
        }
        // `--wheel x,y,dy,count,at` — `count` trackpad scroll events of `dy`
        // points each at a window point (top-left, like `--tap`), sent `at`
        // seconds in, so they can land on a list another flag has opened.
        // Reports the table's and the list's positions before and after: the
        // check for a dropdown that must keep its scroll to itself.
        if let at = args.firstIndex(of: "--wheel"), at + 1 < args.count {
            let parts = args[at + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 5 {
                whenReady { window in
                    DispatchQueue.main.asyncAfter(deadline: .now() + parts[4]) {
                        func offsets() -> String {
                            var out: [String] = []
                            func walk(_ v: NSView) {
                                if let s = v as? NSScrollView {
                                    out.append("\(Int(s.frame.height))h@\(Int(s.contentView.bounds.origin.y))")
                                }
                                v.subviews.forEach(walk)
                            }
                            if let root = window.contentView { walk(root) }
                            return out.joined(separator: " ")
                        }
                        FileHandle.standardError.write(Data("wheel before: \(offsets())\n".utf8))
                        let p = CGPoint(x: parts[0], y: window.frame.height - parts[1])
                        // A made-up scroll carries no window, so AppKit cannot
                        // route it. This does the window's part by hand: the
                        // open list's guard is asked first — the same question
                        // every real scroll is asked — and what passes goes to
                        // the view under the point.
                        func burst(_ dy: Double, _ label: String) {
                            var dropped = 0
                            for _ in 0..<Int(parts[3]) {
                                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                                       wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0),
                                      let ev = NSEvent(cgEvent: cg) else { continue }
                                if let gate = ListScroll.Anchor.open, gate.swallows(ev, at: p) {
                                    dropped += 1; continue
                                }
                                window.contentView?.hitTest(p)?.scrollWheel(with: ev)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                FileHandle.standardError.write(Data(
                                    "wheel \(label): \(offsets())  (\(dropped) held by the list)\n".utf8))
                            }
                        }
                        // Down to the foot, down again past it, then back up.
                        burst(parts[2], "down")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { burst(parts[2], "past the foot") }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { burst(-parts[2], "back up") }
                    }
                }
            }
        }
        if let at = args.firstIndex(of: "--type"), at + 1 < args.count {
            typeThenSnapshot(args[at + 1])
            return
        }
        if args.contains("--paste") {
            typeThenSnapshot("")
            return
        }
        // A tap followed by keys goes through the typing flow, which owns
        // the click-then-type choreography; the bare-tap flow reads state
        // and nothing else.
        if args.contains("--tap") && args.contains("--after") {
            typeThenSnapshot("")
            return
        }
        if let at = args.firstIndex(of: "--tap"), at + 1 < args.count {
            tapThenSnapshot(args[at + 1])
            return
        }
        // `--sweep x1,y1,x2,y2` — a press at the first point, dragged to the
        // second, released: the text-selection gesture, in window points
        // from the top left like `--tap`. Selecting a stretch of the script
        // panel is what ties it to a shot (2026-09-19), and nothing else
        // could drive that.
        //
        // Several gestures, `;` between them, run one after another — a
        // shot's lines far apart are several drags (2026-10-05). A gesture
        // whose two points are one point is a click.
        if let at = args.firstIndex(of: "--sweep"), at + 1 < args.count {
            let gestures = args[at + 1].split(separator: ";").map { $0.split(separator: ",").compactMap { Double($0) } }
            whenReady { window in
              func run(_ index: Int) {
                guard index < gestures.count else { self.snapshotIfAsked(after: 0.1); return }
                let parts = gestures[index]
                guard parts.count == 4 else { self.snapshotIfAsked(after: 0.1); return }
                let h = window.frame.height
                let from = CGPoint(x: parts[0], y: h - parts[1])
                let to = CGPoint(x: parts[2], y: h - parts[3])
                if let hit = window.contentView?.superview?.hitTest(from) {
                    FileHandle.standardError.write(Data("sweep from \(from) hits \(type(of: hit))\n".utf8))
                }
                func post(_ kind: NSEvent.EventType, _ p: CGPoint) {
                    guard let event = NSEvent.mouseEvent(
                        with: kind, location: p, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseUp ? 0 : 1
                    ) else { return }
                    NSApp.postEvent(event, atStart: false)
                }
                post(.leftMouseDown, from)
                if from != to {
                    for step in 1...8 {
                        let t = CGFloat(step) / 8
                        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                    }
                }
                post(.leftMouseUp, to)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let state = ShellState.shared
                    FileHandle.standardError.write(Data("after gesture \(index + 1):\n".utf8))
                    for row in state.view?.allRows ?? [] where !row.script.isEmpty {
                        let spans = (row.scriptSpans ?? []).map { $0.map(String.init).joined(separator: "-") }.joined(separator: ",")
                        FileHandle.standardError.write(Data((
                            "  \(row.number) quotes \(spans): \"\(row.script)\"\n").utf8))
                    }
                    run(index + 1)
                }
              }
              // The panel takes a beat to arrive after the window does.
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { run(0) }
            }
            return
        }
        // One or more waypoints, comma separated, all inside a single press:
        // `--drag -400,0` pulls the divider well past its stop and brings it
        // back to where it started. The width at the end must equal the width
        // at the start — that is the whole clamping-without-jumping claim, in
        // one number.
        guard let at = args.firstIndex(of: "--drag"), at + 1 < args.count else {
            // With nothing else to drive, a checking run photographs if asked
            // and exits either way — a check must always end.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { self.reportColumns() }
            // **`--stay` has already booked the picture for later.** Taking
            // one here as well photographs the app before it has finished and
            // then quits out from under the one that was actually asked for —
            // which is why a slow export could never be photographed at all.
            if !args.contains("--stay") && ProcessInfo.processInfo.environment["SHOTLISTER_STAY"] == nil { snapshotIfAsked(after: 1.4) }
            return
        }
        let waypoints = args[at + 1].split(separator: ",").compactMap { Double($0) }
        guard !waypoints.isEmpty else {
            snapshotIfAsked(after: 1.4)
            return
        }
        // Two seconds rather than one: the press has to land after SwiftUI has
        // installed the gesture, and an early one is simply swallowed. The
        // first launch after a rebuild is the slow one — cold caches — so a
        // swallowed press retries once rather than reporting a false pass.
        attemptDrag(waypoints: waypoints, wait: 1.6, retriesLeft: 3)
    }

    private func attemptDrag(waypoints: [Double], wait: TimeInterval, retriesLeft: Int) {
        // No activation, no key grab. The previous version asserted both here
        // to make a flaky press land, and that is precisely what yanked
        // Nathaniel out of his work — a check is not allowed to cost him
        // anything. Events are posted straight into this app's own queue, which
        // needs no help from the window server; what the press actually needed
        // was time for SwiftUI to install the gesture, and time is free.
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let state = ShellState.shared
            state.dragUpdates = 0
            let before = state.sidebarWidth
            FileHandle.standardError.write(Data("width before: \(Int(before))\n".utf8))

            let y = window.frame.height / 2
            let steps = 14
            func post(_ kind: NSEvent.EventType, _ x: CGFloat) {
                guard let event = NSEvent.mouseEvent(
                    with: kind,
                    location: CGPoint(x: x, y: y),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: kind == .leftMouseUp ? 0 : 1
                ) else { return }
                NSApp.postEvent(event, atStart: false)
            }

            // The whole path as offsets from where the press landed, walked at
            // roughly a hand's pace: `--step <points>` sets how far the pointer
            // moves between events, five by default. Coarse steps were the
            // harness's blind spot — a run can start and finish exactly right
            // while oscillating the whole way between, and only small steps put
            // enough samples in the trace to see it.
            let flags = CommandLine.arguments
            var step: Double = 5
            if let at = flags.firstIndex(of: "--step"), at + 1 < flags.count,
               let wanted = Double(flags[at + 1]) {
                step = wanted
            }
            var path: [CGFloat] = []
            var from: CGFloat = 0
            for leg in waypoints {
                let distance = abs(CGFloat(leg) - from)
                let count = max(1, Int((distance / CGFloat(max(0.5, step))).rounded(.up)))
                for i in 1...count {
                    path.append(from + (CGFloat(leg) - from) * CGFloat(i) / CGFloat(count))
                }
                from = CGFloat(leg)
            }
            _ = steps

            state.widthTrace = []
            post(.leftMouseDown, before)
            for (i, offset) in path.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(i + 1)) {
                    post(.leftMouseDragged, before + offset)
                }
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.008 * Double(path.count + 1)
            ) {
                post(.leftMouseUp, before + (path.last ?? 0))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let after = state.sidebarWidth
                    let floor = ShellState.sidebarRange.lowerBound
                    // Built up a piece at a time — one expression was too
                    // much for the type-checker under Xcode 27 (2026-09-20).
                    let steps = waypoints.map { Int($0) }
                    var path = "path \(steps)  →  width after: \(Int(after))"
                    path += "  (from \(Int(before)), floor \(Int(floor)),"
                    path += " gesture updates: \(state.dragUpdates),"
                    path += " anchor cleared: \(state.dragAnchor == nil))\n"
                    FileHandle.standardError.write(Data(path.utf8))
                    // The flutter check. The waypoints change direction
                    // `waypoints.count - 1` times, so the width may too — any
                    // reversal beyond that is the sidebar moving one way while
                    // the pointer moved the other, which is what a hand sees as
                    // shake. Plateaus at a stop are not reversals.
                    let trace = state.widthTrace
                    let moves = zip(trace, trace.dropFirst())
                        .map { $1 - $0 }
                        .filter { abs($0) > 0.01 }
                    let reversals = zip(moves, moves.dropFirst())
                        .filter { ($0 < 0) != ($1 < 0) }
                        .count
                    let allowed = max(0, waypoints.count - 1)
                    let worst = zip(moves, moves.dropFirst())
                        .filter { ($0 < 0) != ($1 < 0) }
                        .map { abs($1) }
                        .max() ?? 0
                    // Whole points, every sample. A fractional width is the
                    // shimmer: the sidebar, the divider and the content each
                    // round to device pixels on their own, so a width of 300.37
                    // can put the line a pixel either side of where the hand
                    // has it while the numbers march along perfectly monotonic.
                    let fractional = trace.filter { $0 != $0.rounded() }.count
                    var verdict = "samples \(trace.count), direction reversals "
                        + "\(reversals) (allowed \(allowed)), "
                        + "fractional widths \(fractional)"
                    if reversals > allowed {
                        verdict += "  ← FLUTTER, worst \(String(format: "%.1f", worst))pt"
                    }
                    if fractional > 0 {
                        verdict += "  ← SUB-PIXEL WIDTHS, will shimmer"
                    }
                    FileHandle.standardError.write(Data((verdict + "\n").utf8))

                    // Said loudly, because "the width did not change" and "the
                    // drag never happened" look identical in the number above,
                    // and one of them is a passing test that proved nothing.
                    if state.dragUpdates == 0 {
                        if retriesLeft > 0 {
                            let note = "press was swallowed — retrying "
                                + "(\(retriesLeft) left)\n"
                            FileHandle.standardError.write(Data(note.utf8))
                            self.attemptDrag(waypoints: waypoints,
                                             wait: 0.8,
                                             retriesLeft: retriesLeft - 1)
                            return
                        }
                        let warning = "DRAG NEVER REACHED THE GESTURE — this run "
                            + "proves nothing, launch timing swallowed the press\n"
                        FileHandle.standardError.write(Data(warning.utf8))
                    }
                    self.reportColumns()
                self.snapshotIfAsked(after: 0.1)
                }
            }
            }
        }
    }

    /// `--pages` — **where the Document view cut its sheets.** The one thing
    /// about that screen no stored value can tell you: a page break depends on
    /// how tall each block came out, so it is only knowable after the page has
    /// drawn itself. The view publishes the answer and this prints it.
    ///
    /// His ask, 2026-09-01, was that the editor show him the pages the export
    /// will have; this is how that is checked without reading a photograph.
    ///
    /// **Reported at picture time, not with the other doors.** Asked as the
    /// run starts it always answered `pages: 0`, which reads exactly like the
    /// feature not existing. The moment the snapshot is taken is the one
    /// moment the page is certainly drawn.
    private func reportPages() {
        guard CommandLine.arguments.contains("--pages") else { return }
        let state = ShellState.shared
        let sheets = state.documentSheets
        var out = "pages: \(sheets.count)\n"
        for (at, sheet) in sheets.enumerated() {
            var named: [String] = []
            for slab in sheet {
                switch slab {
                case .head:
                    named.append("head")
                case .section(let id):
                    let scene = state.view?.scenes.first { $0.id == id }
                    let title = scene.flatMap { state.sectionOf($0) }?.title ?? id
                    named.append("section " + title)
                case .scene(let id):
                    let scene = state.view?.scenes.first { $0.id == id }
                    named.append("scene " + (scene?.number ?? id))
                case .shot(let id):
                    let row = state.view?.allRows.first { $0.id == id }
                    named.append(row?.number ?? id)
                }
            }
            out += "page \(at + 1): " + named.joined(separator: ", ") + "\n"
        }
        FileHandle.standardError.write(Data(out.utf8))
    }

    private func snapshotIfAsked(after delay: TimeInterval) {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--snapshot"), at + 1 < args.count else {
            // Every checking run ends. The first version only terminated after a
            // --drag, so a --type run with no snapshot sat there with a window
            // open until something killed it — the exact failure this harness is
            // not allowed to have.
            if Self.checking {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 1.2)) {
                    self.reportPages()
                    self.finish()
                }
            }
            return
        }
        let path = args[at + 1]
        let live = args.contains("--live")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.reportPages()
            // The *frame* view rather than the content view, so the picture
            // includes the toolbar and the traffic lights. The content view
            // stops below the chrome, and a screenshot missing the toolbar
            // cannot answer questions about the toolbar.
            // The main window, not the sheet: a sheet is a *child* window, and
            // photographing it alone would crop away the app it belongs to.
            // Taking the parent gets both, which is what the picture is for.
            // **No sheet in this app can be photographed** — see Ref 366.
            // While one is up a checking run has *no windows at all*, so there
            // is nothing here to widen the net to; `--editcolumns` has always
            // answered "snapshot: no window" the same way. Don't spend an hour
            // on this filter the way I did: the collection really is empty.
            if ProcessInfo.processInfo.environment["SHOTLISTER_ALLWINDOWS"] == "1" {
                FileHandle.standardError.write(Data(("all windows: " + NSApp.windows.map {
                    "\($0.className)[\($0.identifier?.rawValue ?? "-")] visible=\($0.isVisible) frame=\($0.frame) level=\($0.level.rawValue)"
                }.joined(separator: " · ") + "\n").utf8))
            }
            let visible = NSApp.windows.filter { $0.isVisible }
            FileHandle.standardError.write(Data(("windows: " + visible
                .map { "\($0.title.isEmpty ? "<untitled>" : $0.title)"
                     + "[\($0.identifier?.rawValue ?? "-")]" }
                .joined(separator: " · ") + "\n").utf8))
            // `--window viewer|frames` photographs one of the app's own extra
            // windows instead of the main one. They are real windows rather
            // than sheets, so the main-window rule below would never reach
            // them — and a viewer that cannot be photographed cannot be
            // checked, which is how a thumbnail-sized dead end shipped.
            let wanted = args.firstIndex(of: "--window").flatMap { at -> NSWindow? in
                guard at + 1 < args.count else { return nil }
                let name = args[at + 1]
                return visible.first { $0.identifier?.rawValue == name }
            }
            guard let window = wanted
                    ?? visible.first(where: { $0.identifier?.rawValue == "main" })
                    ?? visible.first(where: { $0.sheetParent == nil }) ?? visible.first,
                  let frame = window.contentView?.superview ?? window.contentView
            else {
                FileHandle.standardError.write(Data("snapshot: no window\n".utf8))
                self.finish()
                return
            }
            if live {
                self.liveSnapshotIfAsked(path, window)
                return
            }

            FileHandle.standardError.write(Data((
                "photographing: \(window.title) [\(window.identifier?.rawValue ?? "-")] "
                + "\(Int(window.frame.width))×\(Int(window.frame.height))\n").utf8))
            // Said out loud, because a snapshot in the wrong theme is the
            // easiest way to spend an hour fixing a colour that was right.
            FileHandle.standardError.write(Data(
                "appearance: \(frame.effectiveAppearance.name.rawValue)\n".utf8))
            for (i, screen) in NSScreen.screens.enumerated() {
                let size = screen.frame
                FileHandle.standardError.write(Data((
                    "screen \(i): \(screen.localizedName) "
                    + "\(Int(size.width))×\(Int(size.height))"
                    + (screen == window.screen ? "  ← window is here" : "")
                    + "\n").utf8))
            }

            let png = Launch.picture(of: frame, in: window)
            if let png {
                try? png.write(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("snapshot: \(path)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("snapshot: failed\n".utf8))
            }
            self.finish()
        }
    }

    /// The live path, kept apart from the layer path above so the two can be
    /// compared side by side rather than one quietly replacing the other.
    private func liveSnapshotIfAsked(_ path: String, _ window: NSWindow) {
        if #available(macOS 14.0, *) {
            Launch.livePicture(of: window, to: path) { _ in
                DispatchQueue.main.async { self.finish() }
            }
        } else {
            FileHandle.standardError.write(
                Data("live snapshot needs macOS 14\n".utf8))
            finish()
        }
    }

    /// **A picture of the window as the screen actually shows it.**
    ///
    /// His question, 2026-08-20: *"what do we need to do so that you can see
    /// the liquid glass via screenshot?"* This is the answer, and it is the
    /// only one: `layer.render` below draws what Core Animation composited
    /// **in this process**, and a material — Liquid Glass included — is drawn
    /// by the window server, downstream of anything this process can reach. No
    /// amount of care with layers will ever see it.
    ///
    /// So: ScreenCaptureKit, which asks the window server for the composited
    /// result. `desktopIndependentWindow` is the part that makes it usable
    /// here — it captures **this window's own content whether or not anything
    /// is in front of it**, so the checking window can stay ordered at the
    /// back, never key, never frontmost, and still be photographed truthfully.
    /// The invisibility law survives.
    ///
    /// What it costs is one system permission: **Screen Recording**. That is
    /// the trade, and it is his to make, not mine — hence a flag rather than a
    /// replacement.
    @available(macOS 14.0, *)
    static func livePicture(of window: NSWindow, to path: String,
                            then done: @escaping (Bool) -> Void) {
        let say = { (line: String) in
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        // Asked, never demanded: `preflight` reports without prompting, so a
        // run that cannot do this says so and falls back rather than throwing
        // a system dialog at whatever he is in the middle of.
        guard CGPreflightScreenCaptureAccess() else {
            say("live snapshot: no Screen Recording permission — "
                + "System Settings → Privacy & Security → Screen Recording")
            done(false)
            return
        }
        let number = CGWindowID(window.windowNumber)
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false)
                guard let target = content.windows.first(where: { $0.windowID == number })
                else {
                    say("live snapshot: the window server does not list this window")
                    done(false)
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: target)
                let config = SCStreamConfiguration()
                // Retina, explicitly. `pointPixelScale` came back 1 and the
                // first live shots were half the resolution of the layer ones,
                // which makes a like-for-like comparison of hairlines useless.
                let scale = await MainActor.run { window.backingScaleFactor }
                config.width = Int(filter.contentRect.width * scale)
                config.height = Int(filter.contentRect.height * scale)
                config.showsCursor = false
                config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config)
                let rep = NSBitmapImageRep(cgImage: image)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    say("live snapshot: could not encode")
                    done(false)
                    return
                }
                try png.write(to: URL(fileURLWithPath: path))
                say("live snapshot: \(path)  \(image.width)×\(image.height)")
                done(true)
            } catch {
                say("live snapshot failed: \(error.localizedDescription)")
                done(false)
            }
        }
    }

    /// A picture of a view, by rendering its layer tree.
    ///
    /// `cacheDisplay` was the obvious way and it is the wrong one here: it asks
    /// each view to draw itself, and the system's sidebar is a backdrop rather
    /// than something that draws, so the whole left column came out blank white
    /// while everything else was right. Rendering the layers gets what Core
    /// Animation actually composited.
    static func picture(of view: NSView, in window: NSWindow) -> Data? {
        guard let layer = view.layer else { return nil }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        // The appearance has to be current while the layers render or every
        // dynamic colour resolves to the light one.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.render(in: ctx)
        }

        // Everything else the app has on screen, drawn in at its offset from
        // the main window: sheets, popovers, panels. Each is a separate window
        // with its own layer tree, so a picture of the main one alone shows the
        // *effect* of them — a dimmed window, a highlighted cell — and not the
        // thing itself, which reads as a bug rather than as a blind spot.
        //
        // This has now caught the camera out three times, each with a different
        // window kind. Hence: every window, not a list of the kinds thought of
        // so far.
        // The Whole Script window (`--wholescriptwindow`) sits over the main
        // one, which would be drawn across its left half: leave the main
        // window out of that photograph.
        let alone = CommandLine.arguments.contains("--wholescriptwindow")
            || CommandLine.arguments.contains("--media")
            || CommandLine.arguments.contains("--printframe")
            || CommandLine.arguments.contains("--frameprint")
            || CommandLine.arguments.contains("--prefs")
            // The export window, photographed on its own (2026-10-15): the
            // main window drawn over it hid the box in every picture.
            || CommandLine.arguments.contains("--exportbox")
        for other in NSApp.windows where other.isVisible && other !== window
            && !(alone && other.identifier?.rawValue == "main") {
            guard let otherView = other.contentView?.superview ?? other.contentView,
                  let otherLayer = otherView.layer else { continue }
            ctx.saveGState()
            ctx.translateBy(x: other.frame.minX - window.frame.minX,
                            y: other.frame.minY - window.frame.minY)
            otherView.effectiveAppearance.performAsCurrentDrawingAppearance {
                otherLayer.render(in: ctx)
            }
            ctx.restoreGState()
        }
        guard let image = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }
}

@main
struct StudioApp: App {
    @NSApplicationDelegateAdaptor(Launch.self) private var launch
    @ObservedObject private var state = ShellState.shared

    var body: some Scene {
        Window("Shotlister Studio", id: "main") {
            Shell(state: state)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1560, height: 960)
        .commands {
            CommandGroup(replacing: .newItem) {
                // **⌘N opens another Shotlister**, his ask of 2026-08-22, and a
                // second *process* rather than a second window on purpose.
                //
                // A `WindowGroup` would give two windows sharing one
                // `ShellState`, which is a mirror and not a second workspace:
                // both would stand on the same project, the same scene and the
                // same cursor. A second instance has its own everything, and
                // two of them on one project is the case the engine was built
                // for — his two Macs do it all day, and the battery already
                // runs two at once to check it.
                //
                // **It opens on this project now, not on the picker.** It used
                // to pass `--fresh`, which threw the Projects sheet over the new
                // window with *New project* sitting in it — his reading of that
                // was "⌘N has reverted to creating a new project", and it is the
                // only thing that screen looks like. The old reasoning was that
                // "a second window on the same project is a puzzle, not a
                // workspace", and that stopped being true the day ⌥⌘N was added
                // to do exactly that deliberately. One of the two had to go.
                //
                // With no project open there is nothing to stand on, so it still
                // falls back to the picker — that is `Launch.another`'s own
                // guard, not a second rule here.
                Button("New Window") {
                    Launch.another(on: state.projectPath, at: state.sideTab)
                }
                .keyboardShortcut("n")
                Button("New Project") { state.newProject() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Project…") { state.browsing = true }
                    .keyboardShortcut("o")
                Button("Open in Projects Console") {
                    Console.openProject(page: state.view?.project.consolePage ?? "")
                }
                .disabled((state.view?.project.consolePage ?? "").isEmpty)
                Divider()
                // Title Case, because this is the macOS menu bar and the system
                // puts its own Title Case items in beside ours.
                Button("Import Script…") { ScriptImport.pick(state: state) }
                    .disabled(state.engine == nil)
                Button("Paste Script…") { state.pastingScript = true }
                    .keyboardShortcut("v", modifiers: [.command, .shift, .option])
                    .disabled(state.engine == nil || state.view?.project.isCommercial != true)
                Divider()
                // **⌘S keeps a version**, the Mac's own meaning for it in an
                // app that saves on its own — Pages and Keynote say the same.
                // Versions, `Versions.swift`.
                Button("Save Version…") { state.askToSaveVersion() }
                    .keyboardShortcut("s")
                    .disabled(state.engine == nil || state.looking != nil)
                Button("Versions…") { VersionsWindow.shared.show(state: state) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(state.engine == nil)
                Button("Media…") { MediaShelfWindow.shared.show(state: state) }
                    .disabled(state.engine == nil)
            }
            // ⌘, — the Mac's settings key, and the gear's tooltip has been
            // promising it. A menu shortcut is safe here in a way ⌘Z is not:
            // the menu is matched before the responder chain, and nobody
            // types a comma with ⌘ held.
            // ⌘, — the Mac's settings key, and the gear's tooltip has been
            // promising it. A menu shortcut is safe here in a way ⌘Z is not:
            // the menu is matched before the responder chain, and nobody
            // types a comma with ⌘ held.
            // The updater's own item, and nothing at all in an everyday
            // build — see Updates.swift for why it is absent rather than
            // disabled.
            CommandGroup(after: .appInfo) {
                Updates.menuItem
                // **The only way in on a Mac that has never synced.** The sync
                // button is drawn only where sync already works, so it cannot
                // be the thing you press to make it work. Title Case, because
                // this is the menu bar.
                Button("Set Up Sync…") { state.settingUpSync = true }
            }
            // **Settings… ⌘, is the Settings scene's own item** (below), the
            // Mac's standard window with tabs (2026-10-15). Project Settings
            // keeps its sheet and moves to ⇧⌘,.
            CommandGroup(after: .appSettings) {
                Button("Project Settings…") { SettingsDoor.project(state) }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
                    .disabled(state.engine == nil)
            }
            CommandGroup(after: .toolbar) {
                // **⌘1 · ⌘2 · ⌘3 · ⌘4 — the four modes.**
                //
                // These keys were the *views* of a scene until 2026-08-23 (his
                // ask of 2026-08-22), and they moved up with the switcher they
                // belong to. The plain digits go to the bigger question, the
                // same way the plainest strip in the window does; the views
                // took ⌥ ⌘ with them. ⌘4 keeps landing on the schedule, which
                // is the key the old app used for that screen, so the one
                // shortcut he already had in his hands still goes where it
                // always did.
                //
                // Buttons rather than a `Picker`, because a picker in a menu
                // takes no shortcut of its own: four modes have to be four
                // items to be four keys. Safe against the editor, unlike ⌘Z —
                // nobody types a digit with ⌘ held, and the menu is matched
                // before the responder chain.
                ForEach(Array(SideTab.allCases.enumerated()), id: \.element) { at, mode in
                    Button(mode.title) { state.sideTab = mode }
                        .keyboardShortcut(KeyEquivalent(Character("\(at + 1)")),
                                          modifiers: .command)
                        // A mode that is off is not stood in (step 4 B).
                        .disabled(state.engine == nil || !state.modesShown.contains(mode))
                }
                Divider()
                // **⌥⌘1 · ⌥⌘2 · ⌥⌘3 — the views inside the shot list.**
                // Each one takes you to the mode as well as the view: pressing
                // ⌥⌘2 from Locations means "show me the storyboard", and
                // landing on the storyboard of a mode you are not in would be
                // a shortcut that half-works.
                ForEach(Array(SceneTab.allCases.enumerated()), id: \.element) { at, tab in
                    Button(tab.title) {
                        state.sideTab = .scenes
                        state.tab = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(at + 1)")),
                                      modifiers: [.command, .option])
                    .disabled(state.engine == nil || !state.modesShown.contains(.scenes))
                }
                // Play Clips and Clip Thumbnails moved to Settings ▸ General
                // (2026-10-15).
                Divider()
            }
        }
        Settings {
            StudioSettings(state: state)
        }
    }
}
