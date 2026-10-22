import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// **`NotesView` lived here until 2026-08-29 and was deleted.** It was the
/// first Notes tab and nothing had instantiated it since the side panel grew
/// its own — `PanelNotes` in `SidePanel.swift` is the live editor, writing the
/// same `notes` and `notes_rich` pair through the same `RichText`. It was also
/// the second place in the app drawing a bare `doc` glyph where `Frames.gap`
/// belongs, which is the Ref 224 trap, so it was worth removing rather than
/// fixing twice.


/// Pinning a file to a scene. The same one ingest door as a shot's frames —
/// the engine has always taken an owner rather than a shot; only what the
/// owner *is* differs.
enum Attachments {
    // **Everything below takes an owner id, not a scene.**
    //
    // A location holds photographs exactly the way a scene holds references —
    // `Kind::Media` through `Kind::MediaRef`, the same bytes stored under the
    // same hash. When the Locations screen arrived it needed all of this and
    // none of it was reachable, because every entry point wanted a
    // `ViewModel.Scene` in order to read one string off it. Copying the file
    // would have been a second answer to a question already answered, and the
    // two copies would have parted company the first time either was fixed.
    //
    // The scene-shaped calls stay as one-line wrappers so nothing that already
    // worked had to be re-checked.

    static func take(_ providers: [NSItemProvider], onto scene: ViewModel.Scene,
                     state: ShellState) -> Bool {
        take(providers, ownedBy: scene.id, state: state)
    }

    static func take(_ providers: [NSItemProvider], ownedBy owner: String,
                     state: ShellState) -> Bool {
        var took = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { add(url: url, ownedBy: owner, state: state) }
                }
                took = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                // **The name the sender knows it by.** A drag out of Photos,
                // Safari or Mail hands over pixels and no file, so this branch
                // used to name every one of them `pasted.jpg` — and a mood
                // board's whole rule is that a picture keeps its own name
                // (Ref 273). `suggestedName` is what those senders offer in
                // place of a URL; read it before the pixels, because the
                // provider is gone by the time the picture lands.
                let offered = provider.suggestedName ?? ""
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async {
                        add(image: image, ownedBy: owner, state: state, named: offered)
                    }
                }
                took = true
            }
        }
        return took
    }

    static func addViaPanel(to scene: ViewModel.Scene, state: ShellState) {
        addViaPanel(ownedBy: scene.id, message: "Pin files to scene \(scene.number)",
                    state: state)
    }

    static func addViaPanel(ownedBy owner: String, message: String,
                            state: ShellState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.message = message
        if panel.runModal() == .OK {
            for url in panel.urls { add(url: url, ownedBy: owner, state: state) }
        }
    }

    /// A scene's attachment travels the way a frame does: sized if it is a
    /// picture, whole if it moves. A file the Mac cannot draw is still pinned
    /// — a permit PDF is exactly the kind of thing that belongs here — and
    /// wears a document icon instead of a thumbnail.
    static func add(url: URL, to scene: ViewModel.Scene, state: ShellState) {
        add(url: url, ownedBy: scene.id, state: state)
    }

    static func add(url: URL, ownedBy owner: String, state: ShellState) {
        guard let engine = state.engine else { return }
        let ext = url.pathExtension.lowercased()
        // **Only a raster picture is re-encoded.** `NSImage` opens a PDF
        // perfectly well, which quietly turned a call sheet into a PNG of its
        // first page — no text, no page two, the real file gone. Anything not
        // on this list is kept exactly as it arrived.
        let raster = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "bmp"]
        if raster.contains(ext), let image = NSImage(contentsOf: url) {
            // **Never make a file bigger than it arrived.** Re-encoding is
            // supposed to save space and usually does — but a photograph that
            // was already saved efficiently can come back *larger* after being
            // decoded and written again, and one did: 802 KB in, 1.5 MB out.
            // The battery caught it. When that happens the original is kept
            // exactly as it is, bytes and name and all, because the whole point
            // of this is the size of the folder that syncs.
            let original = (try? Data(contentsOf: url)) ?? Data()
            // **The same picture twice is one file** — Ref 211, which fixed
            // this for clips and left photographs out. Asking by the stored
            // copy's own hash could never match, because the stored copy is a
            // *re-encode* and one encoder run is not byte-for-byte the next.
            // So ask by the hash of the file as it arrived: `source` below
            // records that link, and the engine answers on either. Without
            // this the same reference dropped on a board and on a shot is
            // stored twice, which on a mood board is the ordinary case.
            //
            // **And this use gets its own name**, which is what makes sharing
            // one file safe: a location renames its photographs and a mood
            // board does not (Ref 273), so the name goes on the use rather
            // than on the file. Without that, taking this shortcut would hang
            // `mountain-road.jpg` in a room that should say
            // `hillcrest-house-kitchen-01.jpg`, or the reverse.
            let came = original.isEmpty ? "" : Ingest.sha256Hex(original)
            if !came.isEmpty, let held = Ingest.alreadyStored(came, engine: engine) {
                engine.call("use", owner, held,
                            naming(url.lastPathComponent, ext: ext,
                                   ownedBy: owner, state: state))
                state.replace(engine.view())
                return
            }
            let made = Ingest.compress(image, longest: 2560)
            if let made, made.data.count < original.count || original.isEmpty {
                store(made, ownedBy: owner, named: url.lastPathComponent,
                      state: state, source: came)
            } else if let engine = state.engine, !original.isEmpty {
                state.replace(engine.paste(shot: owner, width: Int(image.size.width),
                                           height: Int(image.size.height), ext: ext,
                                           data: original,
                                           named: naming(url.lastPathComponent, ext: ext,
                                                         ownedBy: owner, state: state)))
            } else {
                add(image: image, ownedBy: owner, state: state, named: url.lastPathComponent)
            }
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            state.say("That file could not be read.")
            return
        }
        let kind = Ingest.isMovie(ext) ? "video" : (ext == "gif" ? "gif" : "other")
        // A PDF is stored whole: the viewer reads its pages, and "Save a Copy"
        // hands back the same file that was dropped, byte for byte.
        // A clip or a paper on a location is named the same way a photograph
        // is — one rule for what lands there, not one for pictures and another
        // for everything else.
        state.replace(engine.paste(shot: owner, width: 0, height: 0, ext: ext,
                                   data: data, kind: kind,
                                   named: naming(url.lastPathComponent, ext: ext,
                                                 ownedBy: owner, state: state)))
    }

    static func add(image: NSImage, to scene: ViewModel.Scene, state: ShellState,
                    named: String = "") {
        add(image: image, ownedBy: scene.id, state: state, named: named)
    }

    /// **Sized and compressed on the way in.** This used to hand the engine a
    /// full-resolution PNG: a 2.6 MB photograph off his phone landed as 20.8 MB,
    /// and every one of those megabytes syncs to his other Mac and into Google
    /// Drive. 2560 on the long side is more than anybody looks at, and the
    /// format follows the picture rather than a habit — see `Ingest.compress`.
    static func add(image: NSImage, ownedBy owner: String, state: ShellState,
                    named: String = "") {
        guard let made = Ingest.compress(image, longest: 2560) else {
            state.say("That picture could not be read.")
            return
        }
        store(made, ownedBy: owner, named: named, state: state)
    }

    /// The name keeps its stem and takes the extension of what was actually
    /// written — a picture called `.png` holding JPEG bytes is the exact
    /// confusion the viewer already has to sniff its way out of, and it is also
    /// what made every already-imported photograph look new to the Drive
    /// banner until that comparison moved to stems. `Ingest.naming` is the one
    /// place that decides, so a photograph is called the same thing whichever
    /// door it came through.
    private static func store(_ made: Ingest.Encoded, ownedBy owner: String,
                              named: String, state: ShellState,
                              source: String = "") {
        guard let engine = state.engine else { return }
        state.replace(engine.paste(shot: owner, width: made.width,
                                   height: made.height, ext: made.ext,
                                   data: made.data,
                                   named: naming(named, ext: made.ext,
                                                 ownedBy: owner, state: state),
                                   source: source))
    }

    /// What to call a picture as it lands — Ref 273.
    ///
    /// His ruling, 2026-08-22: *"Photos in mood boards should keep their own
    /// names. Photos in locations should be renamed based on the location and
    /// area (if there is an area) that they are located in —
    /// `mansion-kitchen-01.jpg`."*
    ///
    /// So this is the one place a file is renamed against its will, and only
    /// there. A photograph on a shot, on a scene or on a board keeps whatever
    /// it arrived as, which is the rule everywhere else in the app.
    ///
    /// **The name itself is `shared/FileNames.swift`'s to make** and this asks it
    /// — Ref 297. The Mac used to hold a second copy, identical because the
    /// shared one was written from it; a rule in two places is a rule that
    /// drifts the moment either is edited, and the phone already reads the
    /// shared one. What stays here is the part only the Mac can answer:
    /// *whose* file this is.
    static func naming(_ given: String, ext: String,
                       ownedBy owner: String, state: ShellState) -> String {
        guard let place = state.view?.locations.first(where: { $0.id == owner }) else {
            return Ingest.naming(given, ext: ext)
        }
        return FileNames.onLocation(place.fullName.isEmpty ? place.name : place.fullName,
                                    ext: ext,
                                    taken: place.media.map(\.filename),
                                    from: place.photos.count)
            ?? Ingest.naming(given, ext: ext)
    }

    /// Opens the file **inside Shotlister**, big enough to read — his gap:
    /// a thumbnail says a file is there, never what it says.
    static func read(_ file: ViewModel.Attachment,
                     among all: [ViewModel.Attachment] = [],
                     state: ShellState) {
        Viewer.shared.show(Viewer.subject(file, among: all, state: state), state: state)
    }

    /// Hands the file to whatever the Mac opens it with.
    static func open(_ file: ViewModel.Attachment, state: ShellState) {
        guard let bytes = state.engine?.proxy(hash: file.hash, ext: file.ext) else {
            state.say("Couldn't read that file")
            return
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlister-open", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(file.filename.isEmpty
                                             ? "\(file.hash).\(file.ext)" : file.filename)
        do {
            try bytes.write(to: out)
            NSWorkspace.shared.open(out)
        } catch {
            state.say("Could not hand that file to an app.")
        }
    }
}
