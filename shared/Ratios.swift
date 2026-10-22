import Foundation

/// **The film's frame, one list for the whole app.** New Project, Project
/// Settings and the storyboard's footer each kept their own until 2026-10-01,
/// and the three disagreed — Settings snapped a 2.35 film to 2.39 because 2.35
/// was not on its list. Every ratio menu draws from here now — the iPhone's
/// too, since 2026-10-09, when it was found offering eight of the Mac's
/// sixteen and snapping a 9:16 film to 1:1.
///
/// A ratio is width over height, so 9:16 is 0.5625. The engine stores the
/// number; the name is ours, worked out on the way to the screen.
enum Ratios {
    struct Preset: Identifiable {
        let value: Double
        let name: String
        let note: String?
        var id: String { name }

        /// What a menu row says: `2.39:1 · Scope`.
        var title: String { note.map { "\(name) · \($0)" } ?? name }
    }

    struct Group: Identifiable {
        let title: String
        let presets: [Preset]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Cinema", presets: [
            Preset(value: 2.76, name: "2.76:1", note: "Ultra Panavision 70"),
            Preset(value: 2.39, name: "2.39:1", note: "Scope"),
            Preset(value: 2.35, name: "2.35:1", note: nil),
            Preset(value: 2.20, name: "2.20:1", note: "70mm"),
            Preset(value: 2.00, name: "2.00:1", note: "Univisium"),
            Preset(value: 1.90, name: "1.90:1", note: "IMAX Digital"),
            Preset(value: 1.85, name: "1.85:1", note: "Flat"),
            Preset(value: 1.66, name: "1.66:1", note: "European"),
            Preset(value: 1.43, name: "1.43:1", note: "IMAX"),
            Preset(value: 1.375, name: "1.37:1", note: "Academy"),
        ]),
        Group(title: "Video & Social", presets: [
            Preset(value: 16.0 / 9.0, name: "16:9", note: "HD"),
            Preset(value: 3.0 / 2.0, name: "3:2", note: nil),
            Preset(value: 4.0 / 3.0, name: "4:3", note: nil),
            Preset(value: 1.0, name: "1:1", note: "Square"),
            Preset(value: 4.0 / 5.0, name: "4:5", note: "Portrait"),
            Preset(value: 9.0 / 16.0, name: "9:16", note: "Vertical"),
        ]),
    ]

    static var presets: [Preset] { groups.flatMap(\.presets) }

    /// Close enough to be the same frame. Films made before 2026-10-01 hold
    /// 1.78 and 1.33 for 16:9 and 4:3, and 1.37 against Academy's 1.375 — all
    /// inside this; the nearest two presets (2.35 and 2.39) are well outside.
    static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.006 }

    static func preset(for ratio: Double) -> Preset? {
        presets.first { same($0.value, ratio) }
    }

    /// The short name: `2.39:1`, `16:9`, `9:16`, or a custom `2.55:1`.
    static func name(_ ratio: Double) -> String {
        if let p = preset(for: ratio) { return p.name }
        // A tall frame reads as whole numbers — 2:3, 5:7 — when it is one.
        if ratio < 1 {
            for tall in 2...32 {
                let wide = (ratio * Double(tall)).rounded()
                if wide >= 1, abs(wide / Double(tall) - ratio) < 0.001 {
                    return "\(Int(wide)):\(tall)"
                }
            }
        }
        return String(format: "%.2f:1", ratio)
    }

    /// The name with its note, for a field that has room: `2.39:1 · Scope`.
    static func title(_ ratio: Double) -> String {
        preset(for: ratio)?.title ?? name(ratio)
    }

    /// What he typed, as width over height — `2.76`, `2.76:1`, `9:16`,
    /// `4096x1716`, `16/9`. The engine's `ratio::parse` reads the same way, so
    /// a ratio typed here is one Claude's connector would take too.
    static func parse(_ said: String) -> Double? {
        let parts = said.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .split(omittingEmptySubsequences: false, whereSeparator: { ":x×/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func number(_ s: String) -> Double? {
            Double(s).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        }
        let r: Double
        switch parts.count {
        case 1: guard let n = number(parts[0]) else { return nil }; r = n
        case 2: guard let w = number(parts[0]), let h = number(parts[1]) else { return nil }; r = w / h
        default: return nil
        }
        return r > 0.2 && r < 10 ? r : nil
    }

    // MARK: his own

    /// The ratios he has typed in, kept across films — a preference of the
    /// Mac's, not a fact about any film, which holds only its number. Stored
    /// as `2.55,0.7` so `@AppStorage` can watch it and a menu redraws the
    /// moment the list changes.
    static let key = "customRatios"

    static func custom(_ stored: String) -> [Double] {
        stored.split(separator: ",").compactMap { Double($0) }
    }

    static func remember(_ ratio: Double) {
        let held = custom(UserDefaults.standard.string(forKey: key) ?? "")
        guard preset(for: ratio) == nil, !held.contains(where: { same($0, ratio) }) else { return }
        UserDefaults.standard.set((held + [ratio]).sorted(by: >)
            .map { String(format: "%.4f", $0) }.joined(separator: ","), forKey: key)
    }
}
