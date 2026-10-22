import SwiftUI

/// **One look everywhere** (after stage 5, item 7; mockup
/// claude.ai/artifact/2yW2m9znRgMT1sZtRzJif7, section A).
///
/// The one set of type, spacing, corners and colours that Studio on the Mac,
/// Studio on the iPhone, the portal and both Projects Console apps draw with.
/// `design/kit/kit.json` is the source; this is the Swift mirror, compiled into
/// both Studio apps. `tools/kitcheck.py` fails if the two disagree.
///
/// Pure values: each app builds its own `Color` from a `Pair` (the Mac through
/// `Brand.pick`, the iPhone through `Color(light:dark:)`).
enum Kit {
    /// Text: five sizes, and the tag size for chips.
    enum Size {
        static let title: CGFloat = 28
        static let heading: CGFloat = 20
        static let row: CGFloat = 15
        static let body: CGFloat = 13
        static let label: CGFloat = 11
        static let tag: CGFloat = 10
    }

    /// Spacing: six steps.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let tag: CGFloat = 5
        static let control: CGFloat = 9
        static let card: CGFloat = 11
        static let panel: CGFloat = 18
        static let pill: CGFloat = 999
    }

    /// A shot tag's air: 2 above and below, 6 at the ends.
    static let tagPadV: CGFloat = 2
    static let tagPadH: CGFloat = 6
    /// The least a tappable row is tall.
    static let rowMin: CGFloat = 44

    /// A colour in the light and in the dark, as hex without the `#`.
    struct Pair {
        let light: String
        let dark: String
        init(_ light: String, _ dark: String) { self.light = light; self.dark = dark }
        func hex(_ dark: Bool) -> String { dark ? self.dark : light }
    }

    enum Ink {
        static let ground = Pair("E4E4E7", "16161A")
        static let surface = Pair("FFFFFF", "0E0E11")
        static let panel = Pair("F2F2F4", "1E1E22")
        static let raise = Pair("FFFFFF", "2E2E35")
        static let rule = Pair("E8E8EB", "232329")
        static let chip = Pair("D9D9DE", "3A3A40")
        static let ink = Pair("17171A", "EDEDF0")
        static let ink2 = Pair("5A5A61", "A0A0A8")
        static let ink3 = Pair("6E6E75", "8E8E96")
        static let ink4 = Pair("AEAEB5", "55555C")
        static let blue = Pair("0A6CE8", "0A84FF")
        static let red = Pair("C0392B", "FF6B5E")
        static let amber = Pair("9A6B10", "FBBF24")
        static let green = Pair("2F7A44", "4ADE80")
        static let phonePage = Pair("F2F2F6", "16161A")
        static let phoneGroup = Pair("FFFFFF", "1E1E22")
    }

    /// A commercial's section wears its color as a wash: this much opacity in
    /// the light and in the dark (kit.json `sectionWash`).
    static let sectionWashLight = 0.10
    static let sectionWashDark = 0.16
    static func sectionWash(dark: Bool) -> Double { dark ? sectionWashDark : sectionWashLight }

    /// A shoot day this close (in days) wears amber; further off, no colour.
    static let soonDays = 14
    static func soon(daysAway days: Int) -> Pair? {
        (0...soonDays).contains(days) ? Ink.amber : nil
    }
}
