import SwiftUI

/// The modes the whole program can be standing in.
///
/// Named `SideTab` rather than `Section` because SwiftUI owns that word, and a
/// type that shadows a view builder's own vocabulary is a trap for whoever
/// writes the next list. **It was `Place` until 2026-08-21**, which stopped
/// being a workable name the moment a location record existed: `state.place`
/// meant "which sidebar list", `f::PLACE` meant "which location", and the
/// bridge's `place` command meant "put this shot on that day".
enum SideTab: String, CaseIterable, Identifiable {
    // **Declaration order is the order of the switcher in the top bar**, so
    // this list reads left to right the way the window does. `schedule` joined
    // the other three on 2026-08-23: it had been a mode all along and the only
    // one reachable nowhere but ⌘4, which meant the switcher named three of the
    // program's four parts and quietly denied the fourth.
    //
    // **The raw values are frozen.** `scenes` is stored in the preferences
    // under "place" and is what `--place scenes` names to a checking run;
    // renaming the case would silently reset everybody's last mode and break
    // every check that says where to stand. What he renamed is the *word on
    // screen*, which is `title`.
    // `diagram` joined on 2026-09-26, the fifth — his ruling of 2026-08-23
    // that a diagram is a mode, not a view of a scene.
    case scenes, locations, boards, schedule, diagram

    var id: String { rawValue }

    /// The word in the top bar — what this part of the program is called.
    var title: String {
        switch self {
        // **"Shot List", not "Scenes"** — his call, 2026-08-23. The mode is
        // the whole business of listing shots; the scenes are only how that
        // list is divided up. It also ends a collision that had been quietly
        // confusing: the mode and one of its own views were both called
        // Shot List, and the view is called Table now.
        case .scenes: return "Shot List"
        // **"Locations", not "Places"** — his call, 2026-08-21, and it is what
        // Cadrage calls the same screen. "Places" was mine and nobody on a set
        // says it.
        case .locations: return "Locations"
        // **"References" here, "Reference Images" everywhere else** — his
        // instruction, 2026-09-08, in two parts. Mood boards became reference
        // images across the product; then: *"The tab in Shotlist Studio can
        // still just be called References."* This is a row of pills and the
        // row lives or dies on its longest word, so the one place the full
        // name will not fit is the one place it gets the short one.
        //
        // **It does collide with the side panel's References section**, which
        // is a scene's pinned things plus every board it links to. He was told
        // and chose this anyway, which is fair: they are the same idea at two
        // scopes — the whole film's references, and this scene's. Do not
        // "fix" it back without asking him.
        //
        // **The sidebar heading below says "Reference Boards"** on purpose:
        // that heading names *what the list holds*, and the list holds boards
        // — one named wall of pictures each.
        case .boards: return "References"
        case .schedule: return "Schedule"
        case .diagram: return "Diagram"
        }
    }

    /// The heading over the sidebar's list — **what the list holds**, which is
    /// not always what the mode is called. Shot List mode is a list of scenes;
    /// so is Schedule mode, since 2026-08-29: it used to draw a "Not
    /// scheduled" column of its own and now uses the one scene list, his
    /// instruction, so it wears the same word. The heading said *Shoot days*
    /// over a list of scenes for exactly one build.
    var heading: String {
        switch self {
        case .scenes, .schedule, .diagram: return "Scenes"
        case .locations: return "Locations"
        // What the list holds: one named wall of pictures each.
        case .boards: return "Reference Boards"
        }
    }

    var icon: String {
        switch self {
        // Not `film.stack` any more: that drew a reel, which said "scenes" —
        // the word this mode no longer wears.
        case .scenes: return "list.bullet.rectangle"
        case .locations: return "mappin.and.ellipse"
        case .boards: return "square.grid.2x2"
        case .schedule: return "calendar"
        case .diagram: return "square.on.square.dashed"
        }
    }

    /// What the sidebar's search box offers to look through here.
    var searching: String {
        switch self {
        case .scenes: return "Search scenes, shots, gear"
        case .locations: return "Search locations"
        case .boards: return "Search reference boards"
        case .schedule, .diagram: return "Search scenes"
        }
    }
}

/// The tabs across the top of a scene.
///
/// Diagram and Script are deliberately absent: they arrive in phases 4 and 2,
/// and a tab that opens onto nothing is worse than a tab that is not there yet.
/// Document is ours rather than Cadrage's.
enum SceneTab: String, CaseIterable, Identifiable {
    // **Notes is gone, by his call.** A tab took the shot list away in order
    // to show a reference, which is the opposite of what a reference is for.
    // The scene's words and the things pinned to it live in the side panel
    // now, beside the list rather than instead of it.
    case shots, storyboard, document

    var id: String { rawValue }

    var title: String {
        switch self {
        // **"Table", not "Shot List"** — his call, 2026-08-23. The mode
        // above is called Shot List now, and one name cannot mean both the
        // whole business and one way of looking at it. This view is the grid
        // of rows and columns, so: Table.
        case .shots: return "Table"
        case .storyboard: return "Storyboard"
        case .document: return "Document"
        }
    }

    var icon: String {
        switch self {
        case .shots: return "tablecells"
        case .storyboard: return "square.grid.3x2"
        case .document: return "doc.text"
        }
    }
}


/// What the side panel is showing. Three sections, one panel — the script,
/// the scene's references, and its words. Script is empty until phase 2; it
/// is here because the panel is *where it will live*, and a panel built for
/// one thing has to be rebuilt for three.
enum PanelSection: String, CaseIterable, Identifiable {
    case script, references, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .script: return "Script"
        case .references: return "References"
        case .notes: return "Notes"
        }
    }

    var icon: String {
        switch self {
        case .script: return "doc.text"
        case .references: return "photo.on.rectangle.angled"
        case .notes: return "note.text"
        }
    }
}
