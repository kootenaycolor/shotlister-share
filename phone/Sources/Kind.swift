import Foundation

/// What kind of thing a file is.
///
/// Taken from the name, which is the same rule the engine falls back on
/// when nothing told it. The engine knows better — it stores a kind — but
/// does not put it on a shot's stills; asked for in
/// `handoff/from-phone.md`.
///
/// It lives in a file of its own, and not inside `Engine`, because three
/// things need it and only one of them can talk to the engine: a `Still`, a
/// `Frame` — a clip drawn in the shot list has to play, and the shot list only
/// ever holds a frame — and a file just picked, which the picture checks
/// exercise without the engine anywhere near them.
enum MediaKind {
    case still, moving, clip, other

    /// **The engine's word first, the filename only as a fallback.** The engine
    /// stores what the bytes actually are and now says so on every picture it
    /// hands over; a name is what somebody typed. A clip called `.dat` was
    /// drawn as a photograph until this.
    init(said: String, ext: String) {
        switch said.lowercased() {
        case "movie", "clip", "video": self = .clip
        case "gif", "moving": self = .moving
        case "image", "picture", "still": self = .still
        default: self = MediaKind(ext)
        }
    }

    init(_ ext: String) {
        switch ext.lowercased() {
        case "gif": self = .moving
        case "mov", "mp4", "m4v", "avi": self = .clip
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp": self = .still
        default: self = .other
        }
    }
}
