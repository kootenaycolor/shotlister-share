import Foundation

/// **A version: the film as it stood at a moment** (`engine/src/versions.rs`).
/// Both apps list them the same way — `shared/` since 2026-10-09, when the
/// iPhone got Versions.
struct VersionItem: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var taken: Int64
    var day: String
    var made: String
    var since: [String]

    var date: Date { Date(timeIntervalSince1970: TimeInterval(taken) / 1000) }
    var automatic: Bool { made != "hand" }

    /// His name for it, or — for the one saved at the start of a day — the day.
    var title: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        let shape = DateFormatter()
        shape.dateFormat = "EEEE d MMMM"
        return shape.string(from: date)
    }

    /// When, in the words a person uses.
    var when: String {
        let shape = DateFormatter()
        let calendar = Calendar.current
        shape.dateFormat = calendar.isDateInToday(date)
            ? "'Today at' HH:mm"
            : (calendar.isDateInYesterday(date) ? "'Yesterday at' HH:mm" : "d MMM 'at' HH:mm")
        return shape.string(from: date)
    }

    /// The line under the name: when, and — for one nobody named — why.
    var subtitle: String {
        switch made {
        case "daily": return "\(when) · Start of Day"
        case "draft", "back": return "\(when) · Automatic"
        default: return when
        }
    }

    /// What is different now. A count is a count.
    var sinceSaid: String {
        since.isEmpty ? "Same as now" : since.joined(separator: " · ")
    }
}
