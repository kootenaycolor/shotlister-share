import Foundation

/// **The project Types, and what each one implies.** Written once, for the Mac
/// and the phone. Music Video behaves exactly like Commercial: the same film
/// kind, the same starting modes, the same icon family. The server owns the
/// real modes (`hub/src/studiomodes.js`); this is what the apps assume while
/// the server hasn't said, and what they use to make a new project's film.
enum ProjectTypes {
    /// The Types a New Project offers, in order.
    static let all = ["Narrative", "Commercial", "Music Video", "Personal"]

    /// The Type as a lowercase word, so "Music Video", "music video" and
    /// " Music Video " are one thing.
    private static func word(_ type: String) -> String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Whether the Type is made as a commercial in Studio: Studio's own
    /// `kind` is `commercial` for Commercial and Music Video, `film` for the rest.
    static func isCommercial(_ type: String) -> Bool {
        ["commercial", "music video"].contains(word(type))
    }

    /// Studio's film kind for a Type: `commercial` or `film`.
    static func kind(_ type: String) -> String { isCommercial(type) ? "commercial" : "film" }

    /// The modes a new project of this Type starts with, by the server's names.
    static func startingModes(_ type: String) -> [String] {
        switch word(type) {
        case "narrative": return ["shot_list", "locations", "references", "schedule", "diagram"]
        case "commercial", "music video": return ["shot_list", "references", "schedule"]
        case "personal": return ["shot_list", "references"]
        default: return []
        }
    }

    /// The phone's icon for a Type; Music Video wears Commercial's.
    static func symbol(_ type: String) -> String {
        switch word(type) {
        case "commercial", "music video": return "megaphone.fill"
        case "personal": return "heart.fill"
        case "narrative": return "film.fill"
        default: return "film.stack"
        }
    }
}
