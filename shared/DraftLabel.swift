import Foundation

/// **What a draft of the script is called, everywhere** (stage 5 step 4,
/// piece C). His ask: Studio, the iPhone, the console and the portal show the
/// same current draft with the same name and date. The rule is the portal's
/// Script page's (`hub/src/scriptlabel.js`); the console has it in
/// `scriptlabel.py`. All three answer `hub/scriptlabel-cases.json` the same
/// (`--labelcases` on the Mac, `node hub/scriptdrive.mjs`, the console's
/// `test_scriptlabel.py`).
///
/// - The name is his own name for the draft; the Mac's stand-in
///   *Revision (9/27/26, 9:46 PM)* gives way to the file's name without `.pdf`.
/// - The date is the day it came in, on his clock: *Oct 12, 2026*.
/// - The label is the two: *Halcyon Pink · Oct 12, 2026*.
enum DraftLabel {
    static func name(_ name: String, cameFrom: String) -> String {
        let own = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty, !isStandIn(own) { return own }
        let file = cameFrom.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var stem = file
        if stem.lowercased().hasSuffix(".pdf") { stem = String(stem.dropLast(4)) }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stem.isEmpty { return stem }
        return own.isEmpty ? "Script" : own
    }

    /// `Revision (…)`, the Mac's stand-in name.
    private static func isStandIn(_ s: String) -> Bool {
        s.hasPrefix("Revision (") && s.hasSuffix(")")
    }

    private static let vancouver = TimeZone(identifier: "America/Vancouver") ?? .current

    /// `Oct 12, 2026`, on his clock; "" when the stamp is not a date.
    static func date(_ stamp: String) -> String {
        guard let when = parse(stamp) else { return "" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = vancouver
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: when)
    }

    static func parse(_ stamp: String) -> Date? {
        let s = stamp.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        let fine = ISO8601DateFormatter()
        fine.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fine.date(from: s)
    }

    /// `Halcyon Pink · Oct 12, 2026`.
    static func label(name: String, cameFrom: String, dated: String) -> String {
        [Self.name(name, cameFrom: cameFrom), date(dated)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
