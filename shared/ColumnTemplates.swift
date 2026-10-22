import Foundation

/// **Ready-made columns — Cadrage's "Create from template…".**
///
/// A template is nothing clever: a name and a shape, handed to the same
/// `addcolumn` the text field uses. It exists because naming a column and
/// choosing its shape is two decisions for something everybody's list has
/// anyway, and getting the shape wrong is the expensive half — a Cast
/// typed as Text can never become a list of names you pick from.
///
/// **This list is mine, not Cadrage's.** Their own is not in any of the
/// reference screenshots, so rather than guess at it these are the columns
/// a shot list carries beyond the fourteen built in. Easy to edit: it is
/// one array.
///
/// Both apps offer it — `shared/`, since 2026-10-09, when the iPhone was
/// found offering a name and a shape and none of these.
///
/// Title Case, because a new column stands in a list beside *Shot Size*
/// and *Shoot Day* and a sentence-case one beside those reads as a slip.
enum ColumnTemplates {
    struct Ready {
        let label: String
        let kind: String
        /// **What the column already knows** — Ref 346.
        ///
        /// A *Frame Rate* column used to arrive empty, so the first thing you
        /// did with a ready-made column was type 24 into it. These are the
        /// terms the list starts with; a vocabulary still learns anything else
        /// typed into it, so none of this is a fence.
        ///
        /// Only for `single` and `multi` — a text column has no list, and a
        /// checkmark has two states neither of which is a word. Names are the
        /// one thing left blank on purpose: nobody's cast is guessable.
        var values: [String] = []
    }

    static let groups: [(String, [Ready])] = [
        ("Camera", [
            Ready(label: "Frame Rate", kind: "single",
                  values: ["24", "25", "30", "48", "60", "120"]),
            Ready(label: "Filter", kind: "multi",
                  values: ["ND 0.3", "ND 0.6", "ND 0.9", "ND 1.2", "Pola",
                           "Black Pro-Mist 1/4", "Black Pro-Mist 1/2"]),
            Ready(label: "Stop", kind: "text"),
            Ready(label: "Height", kind: "single",
                  values: ["Ground", "Low", "Waist", "Eye", "High", "Overhead"]),
        ]),
        ("The scene", [
            Ready(label: "Cast", kind: "multi"),
            Ready(label: "Props", kind: "multi"),
            Ready(label: "Wardrobe", kind: "text"),
            Ready(label: "Special Equipment", kind: "multi"),
            Ready(label: "Sound", kind: "text"),
            Ready(label: "VFX", kind: "multi",
                  values: ["Green Screen", "Clean Plate", "Wire Removal",
                           "Set Extension", "Tracking Markers"]),
        ]),
        ("The day", [
            Ready(label: "Setup", kind: "text"),
            Ready(label: "Estimated Time", kind: "text"),
            Ready(label: "Pages", kind: "text"),
            Ready(label: "Covered", kind: "check"),
        ]),
    ]
}
