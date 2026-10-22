import SwiftUI

/// **What time of day a scene is, as a colour — written once for both apps.**
///
/// The same bargain `Words.swift` strikes, for the same reason: the Mac and the
/// phone each drawing their own idea of a sunset is a thing that drifts the
/// moment either is edited. This file is compiled into both — the Mac through
/// `studio/build.sh`, the phone through `../shared` in `phone/project.yml` —
/// and `Brand.timeKeyInk` in `studio/Sources/Theme.swift` is a thin wrapper
/// over it rather than a second opinion.
///
/// **Two copies still exist and cannot be helped**, because they are not
/// Swift: `--tod-*` in `hub/public/hub.css` for the portal, and
/// `time_of_day_colour` in `engine/src/export/html.rs` for the printed page.
/// Change a colour here and change it in those two.
///
/// ---
///
/// **Four times of day**, his ruling of 2026-09-02 — the four in
/// `TIMES_OF_DAY` in `engine/src/script.rs` — and their colours are a
/// temperature scale in the order he listed them:
///
/// > 1. Sunrise — 2nd coolest
/// > 2. Day — brightest yellowish
/// > 3. Sunset — warmest
/// > 4. Night — coolest
///
/// **The four are two pairs, and that is what makes it read as one ramp**
/// rather than four unrelated dots. Night and sunrise are one blue at two
/// weights; day and sunset are one fire at two weights. The dark ends of the
/// bar are the ends of the day and the light middle is the middle of it, so
/// the eye follows the whole thing cold to hot.
///
/// `CONTINUOUS` and `LATER` deliberately get **no colour at all** — they mean
/// "the same as the scene before", and inventing one would be inventing a fact
/// the script did not give. A missing dot says *look up*, which is true.
enum TimeOfDay {
    /// The written words, most specific first — **the order is load-bearing.**
    /// `NIGHTFALL` has to be looked for before `NIGHT` and `DAYBREAK` before
    /// `DAY`, or a sky going dark reads as full night and a sunrise reads as
    /// noon.
    ///
    /// **Far more words than there are answers, on purpose.** MORNING, DUSK,
    /// EVENING and MAGIC HOUR all stopped being times of day on 2026-09-02,
    /// and every one of them still turns up on screen: a slug line belongs to
    /// the script and keeps whatever the writer typed. Don't tidy this list
    /// down to four.
    private static let words: [(String, String)] = [
        ("MAGIC", "sunset"), ("GOLDEN", "sunset"),
        ("SUNSET", "sunset"), ("SUNDOWN", "sunset"), ("EVENING", "sunset"),
        ("NIGHTFALL", "sunset"), ("TWILIGHT", "sunset"), ("DUSK", "sunset"),
        ("SUNRISE", "sunrise"), ("DAYBREAK", "sunrise"), ("SUNUP", "sunrise"),
        ("DAWN", "sunrise"),
        ("MIDNIGHT", "night"), ("NIGHT", "night"),
        ("MORNING", "day"), ("AFTERNOON", "day"),
        ("NOON", "day"), ("MIDDAY", "day"), ("DAY", "day"),
    ]

    /// **The four the app offers**, in the order the day runs them — the
    /// Swift side of `TIMES_OF_DAY` in `engine/src/script.rs`. Every picker
    /// and every menu that sets a time of day reads this, so none of them can
    /// offer a fifth.
    static let all = ["SUNRISE", "DAY", "SUNSET", "NIGHT"]

    /// Which of the four a written time of day means, or nothing at all.
    static func key(_ said: String) -> String? {
        let word = said.uppercased()
        if word.isEmpty { return nil }
        for (needle, key) in words where word.contains(needle) { return key }
        return nil
    }

    /// The colour for one of the four. Coolest to warmest.
    ///
    /// Both grounds are written out rather than one being computed from the
    /// other, so that what the Mac draws, what the phone draws and what the
    /// portal draws are the same six digits and not three near-misses.
    static func ink(key: String, dark: Bool) -> Color {
        switch key {
        case "night": return hex(dark ? "7D9BEE" : "2B4E9E")     // coolest
        case "sunrise": return hex(dark ? "A8C6F0" : "6E9BD1")   // the same blue, paled
        case "sunset": return hex(dark ? "F59254" : "DC7324")    // warmest
        default: return hex(dark ? "F5D07A" : "E8B14A")          // DAY — brightest
        }
    }

    /// The colour a written time of day draws in, or nothing when the slug
    /// names no time we know.
    static func ink(_ said: String, dark: Bool) -> Color? {
        key(said).map { ink(key: $0, dark: dark) }
    }

    private static func hex(_ s: String) -> Color {
        let v = UInt64(s, radix: 16) ?? 0
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

/// The dot itself — nothing at all when the slug names no time of day.
///
/// It reads the appearance from the environment rather than being handed one,
/// because the phone has no `dark` to pass around the way the Mac's views do.
struct TimeDot: View {
    let said: String
    var side: CGFloat = 7
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let ink = TimeOfDay.ink(said, dark: scheme == .dark) {
            Circle().fill(ink).frame(width: side, height: side)
        }
    }
}
