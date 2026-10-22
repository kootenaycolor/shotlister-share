/// `Mark.swift`'s `FilmIcon` names this type. In the app it lives beside the
/// decoder in `Engine.swift`, which the widget does not carry; the widget only
/// needs the name to exist, so it gets this copy of the same two fields.
struct FilmMark: Codable, Hashable {
    var path: String
    var colour: String
}
