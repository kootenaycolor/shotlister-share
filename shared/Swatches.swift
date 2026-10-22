import Foundation

/// **The colours a person picks, one list for both apps** (2026-10-09). The
/// iPhone had none of these: it cycled cameras through named system colours
/// the Mac never used, and could not highlight a shot or colour a term.
///
/// - `highlight`: six, with names — a shot's highlight and a camera's colour,
///   the Mac's `Columns.palette`.
/// - `inks`: eight, muted, no names — what a list value can wear, the Mac's
///   `Brand.chipInks`. They have no names because the app never says one.
///
/// Hex without the `#`, as the engine stores a shot's colour.
enum Swatches {
    static let highlight = ["E5484D", "D97706", "16A34A", "0A6CE8", "7B4BC4", "DB2777"]
    static let highlightNames = ["Red", "Orange", "Green", "Blue", "Purple", "Pink"]

    static let inks = [
        "2C7A7B", "2B6CB0", "4C51BF", "7B4BC4",
        "A33574", "9A6B10", "2F7A44", "B4531B",
    ]
    /// What each of `inks` is called in a menu, in the same order. A menu row
    /// that is only a dot draws blank on the Mac, so every dot gets a word.
    static let inkNames = ["Teal", "Blue", "Indigo", "Purple", "Magenta", "Amber", "Green", "Rust"]
}
