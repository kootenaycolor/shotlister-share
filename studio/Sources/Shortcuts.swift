import AppKit
import SwiftUI

/// **The shot's keyboard, in one place.**
///
/// His ask of 2026-08-20: *"shortcuts for things like adding shots should be
/// global across views — what are they right now?"* They were not, and the
/// honest answer was three different answers. The table could delete,
/// duplicate, strike, select-all, add-below and undo. The page could delete,
/// duplicate, move and select-all — but not undo, not strike, not paste a
/// picture. The storyboard could undo and paste and nothing else.
///
/// Everything in here acts on **shots**, so it belongs to none of the three
/// surfaces and to all of them. What stays local is what is genuinely local:
/// the table's cell keys, the storyboard's arrows through the grid, the page's
/// Tab through its fields.
///
/// ## The scene is the cursor's, never the chrome's
///
/// The first cut of this file asked each surface for "the rows it is showing",
/// and the table answered with **the current scene's** rows — which is what
/// the sidebar last said, not where the hand is. His report: *"I was on scene
/// 34d, I hit ⌘⏎, and it kept adding shots to a scene above it. ⌘↑/⌘↓ do
/// nothing. ⌘A only selects the shots in scene 34."* All three were the same
/// mistake. The table has shown the whole script since the 19th, so "the
/// current scene" is a fact about the chrome and nothing here may read it.
///
/// So: **every answer is derived from the row the cursor is in.** Which scene
/// a new shot joins, which scene ⌘A selects, which scene a shot moves inside —
/// all of it comes off `cursorShot`. The only thing a surface still says about
/// itself is the scene to use when there is no cursor at all, and how it gets
/// bigger and smaller.
enum Shortcuts {
    struct Surface {
        /// The scene a new shot joins when nothing is under the cursor.
        var scene: String?
        /// −1 smaller · 0 the middle again · +1 bigger. Every surface has a
        /// size of its own — the table's rows, the storyboard's cards, the
        /// page's type — so ⌘+ and ⌘− mean the same thing on all three even
        /// though they move different numbers.
        var resize: ((Int) -> Void)?
    }

    /// Every row on screen, in reading order: the whole script, minus the
    /// scenes set aside. Read from the engine's own view, so a filter or a
    /// sort narrows this exactly as it narrows the screen.
    static func everyRow(_ state: ShellState) -> [ViewModel.Row] {
        let live = Set((state.view?.scenes ?? []).filter { !$0.archived }.map(\.id))
        return (state.view?.allRows ?? []).filter { live.contains($0.sceneId ?? "") }
    }

    /// The row the cursor is in — the anchor for everything below.
    static func cursorRow(_ state: ShellState) -> ViewModel.Row? {
        everyRow(state).first { $0.id == state.cursorShot }
    }

    /// What an operation acts on: the selection when there is one, the shot
    /// the cursor is in otherwise. One rule, so all three surfaces mean the
    /// same thing by "this shot".
    static func acting(_ state: ShellState) -> [ViewModel.Row] {
        let rows = everyRow(state)
        // Shots picked whole by their numbers are the selection too — the
        // table's own `actingOn` has always said so; without it ⌘⌫, ⌘D and
        // ⌘K took one of five ringed shots.
        if !state.wholeShots.isEmpty {
            return rows.filter { state.wholeShots.contains($0.id) }
        }
        // **A block of cells counts as its rows**: shift-click or drag down five
        // cells and ⌘⌫, ⌘D and ⌘K reach those five shots, which is what
        // shift-clicking five rows did before a block of cells took that over.
        if let range = state.cellRange,
           let from = rows.firstIndex(where: { $0.id == range.anchorRow }),
           let to = rows.firstIndex(where: { $0.id == range.endRow }) {
            return Array(rows[min(from, to)...max(from, to)])
        }
        if state.marked.isEmpty {
            return rows.filter { $0.id == state.cursorShot }
        }
        return rows.filter { state.marked.contains($0.id) }
    }

    /// Returns `nil` when it has dealt with the event, and the event itself
    /// when the surface should carry on and handle it.
    ///
    /// `typing` is the caller's own answer to "is somebody in the middle of a
    /// word" — a real text view, an open cell, an open picker. While that is
    /// true nothing here fires: ⌘⌫ is a word, ⌘Z is un-typing, and ⌘A selects
    /// the sentence rather than the scene.
    static func handle(_ event: NSEvent, state: ShellState,
                       typing: Bool, surface: Surface) -> NSEvent? {
        guard !typing else { return event }
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        // ⌃↩ and ⌘↩ — a new shot below the one you are in. The old app's "Add
        // Shot at Cursor", and the sheet gesture of "give me a row here".
        if event.keyCode == 36, command || event.modifierFlags.contains(.control) {
            return addShot(state, surface: surface)
        }
        guard command else { return event }

        // ⌘Z / ⇧⌘Z — the *document's* undo: the engine's history, with its own
        // labels and its own idea of what one step is. Deliberately not a menu
        // item, because a menu shortcut is matched before the responder chain
        // and would take ⌘Z away from an open editor.
        if event.charactersIgnoringModifiers?.lowercased() == "z" {
            shift ? state.redo() : state.undo()
            return nil
        }

        switch event.keyCode {
        case 51:                                                    // ⌘⌫
            return delete(state)
        // ⇧⌘↑ and ⇧⌘↓ are the table's own: stretching a block of cells to
        // the top or bottom, as a sheet does. Only the plain chord moves a shot.
        case 126 where !shift:                                      // ⌘↑
            return move(state, by: -1)
        case 125 where !shift:                                      // ⌘↓
            return move(state, by: 1)
        default: break
        }

        // ⌘+ · ⌘− · ⌘0 — the surface's own size. `characters` rather than a
        // key code, because = and + are the same key with and without shift.
        if let resize = surface.resize,
           let key = event.charactersIgnoringModifiers,
           ["=", "+", "-", "0"].contains(key) {
            resize(key == "0" ? 0 : (key == "-" ? -1 : 1))
            return nil
        }

        let acting = acting(state)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a" where shift:
            state.marked.removeAll()
            return nil
        case "a":
            // **The scene the cursor is in** — his words: "⌘A doesn't select
            // all the shots in a scene, it only selects the ones in scene 34".
            // Scene 34 was whatever the chrome happened to name. With nothing
            // under the cursor there is no scene to mean, so it takes the
            // surface's — the one you are looking at.
            let scene = cursorRow(state)?.sceneId ?? surface.scene
            state.wholeShots.removeAll()
            state.marked = Set(everyRow(state)
                .filter { $0.sceneId == scene }
                .map(\.id))
            return nil
        case "d":
            guard let engine = state.engine, !acting.isEmpty else { return nil }
            for row in acting { state.replace(engine.duplicate(placement: row.placement)) }
            state.marked.removeAll()
            return nil
        case "k":
            // If any of them is still standing the action is to strike; all
            // struck already means restore. One key.
            guard let engine = state.engine, !acting.isEmpty else { return nil }
            let striking = acting.contains { !$0.struck }
            state.replace(engine.strike(shots: acting.map(\.shot), on: striking))
            return nil
        case "v":
            // **Media on the clipboard is a frame for the shot**, on every
            // surface — screenshot a still, ⌘V, and it lands. Anything else on
            // the clipboard is not ours to interpret here, so the event goes
            // back to the surface, which knows what a paste means in a cell.
            // (`fromPasteboard` refuses outright under a checking run: his
            // clipboard is his.)
            if !acting.isEmpty, Ingest.fromPasteboard(onto: acting, state: state) {
                return nil
            }
            return event
        default:
            return event
        }
    }

    // ---------------------------------------------------------- the moves

    private static func addShot(_ state: ShellState, surface: Surface) -> NSEvent? {
        guard let engine = state.engine else { return nil }
        let here = cursorRow(state)
        // Into the scene of the shot you are standing in, or the surface's own
        // scene when you are standing nowhere. **Never the chrome's scene** —
        // that is how a shot ended up in the scene above the one he was in.
        guard let scene = here?.sceneId ?? surface.scene else { return nil }
        state.replace(engine.addShot(scene: scene, after: here?.placement))
        return nil
    }

    private static func delete(_ state: ShellState) -> NSEvent? {
        let rows = everyRow(state)
        let acting = acting(state)
        guard !acting.isEmpty, let engine = state.engine else { return nil }
        let at = rows.firstIndex { $0.id == acting.first?.id } ?? 0
        // One transaction, so taking forty back is one ⌘Z.
        state.replace(engine.deletePlacements(acting.map(\.placement)))
        state.marked.removeAll()
        state.wholeShots.removeAll()
        let left = everyRow(state)
        state.cursorShot = left.isEmpty ? nil : left[min(at, left.count - 1)].id
        return nil
    }

    /// Up or down **inside its own scene**. A shot belongs to the scene the
    /// script put it in; carrying it across a scene boundary would be
    /// renumbering by accident, and scene numbers are the script's, never ours.
    private static func move(_ state: ShellState, by step: Int) -> NSEvent? {
        guard let engine = state.engine, let row = acting(state).first else { return nil }
        // Under a sort the order on screen is not the scene's own, so moving a
        // shot "down" would move it somewhere nobody asked for. The row drag
        // refuses for the same reason; this says so out loud, because a key
        // that silently does nothing reads as a broken key.
        if let sort = state.view?.filter.sortColumn, !sort.isEmpty {
            state.say("Turn off sorting to move shots")
            return nil
        }
        let within = everyRow(state).filter { $0.sceneId == row.sceneId }
        guard let at = within.firstIndex(where: { $0.id == row.id }) else { return nil }
        let to = at + step
        guard within.indices.contains(to) else { return nil }
        state.replace(engine.reorder(placement: row.placement, to: to))
        state.cursorShot = row.id
        return nil
    }
}
