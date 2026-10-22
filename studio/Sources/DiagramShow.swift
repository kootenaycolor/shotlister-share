import SwiftUI
import AppKit

/// **Show by Kind** — a switch per kind of thing on the plan, in the View
/// menu's submenu (`DiagramViewMenu`); Scenario's Visibility:
/// "each user has their own visibility setup". What is switched off here is
/// not drawn and cannot be clicked, on this Mac only; the film, the portal
/// and paper are untouched.
enum DiagramShow {
    /// Every switch, in the order the panel lists them.
    static let kinds: [(key: String, title: String)] = [
        ("cameras", "Cameras"), ("cast", "Cast"), ("lights", "Lights"), ("grip", "Grip"),
        ("set", "Set Pieces"), ("walls", "Walls"), ("words", "Words"), ("pictures", "Pictures"),
    ]
    // Names and Cones are not here (Back to Paper, Batch 2): View › Labels
    // and View › Cones are the one switch each, saved with the plan and
    // printed.

    /// Which switch a piece answers to, if any: Grip lives with the lights
    /// in the library, but a lamp is a light only if it throws a beam.
    static func kind(_ e: DiagramEl, beams: [String: Double]) -> String? {
        switch e.kind {
        case "camera": return "cameras"
        case "cast": return "cast"
        case "light": return (beams[e.sym] ?? 1) > 0 ? "lights" : "grip"
        case "set": return "set"
        case "wall", "door", "window", "opening": return "walls"
        case "text", "note": return "words"
        case "image": return "pictures"
        default: return nil
        }
    }

    /// Which switch a part of a drawing answers to, whoever it belongs to.
    static func part(_ p: String) -> String? {
        switch p {
        case "label", "tag", "tie": return "names"
        case "cone": return "cones"
        default: return nil
        }
    }

    /// Each library drawing's beam, looked up once.
    fileprivate static var beamCache: [String: Double] = [:]
    fileprivate static func beams(_ model: DiagramModel) -> [String: Double] {
        if beamCache.isEmpty, let lib = model.library {
            beamCache = Dictionary(lib.symbols.map { ($0.id, $0.beam) }, uniquingKeysWith: { a, _ in a })
        }
        return beamCache
    }
}

extension DiagramModel {
    /// The pieces this Mac is not showing, by id.
    var unseenIds: Set<String> {
        guard !unseenKinds.isEmpty else { return [] }
        let beams = DiagramShow.beams(self)
        return Set(shown.els.filter { DiagramShow.kind($0, beams: beams).map(unseenKinds.contains) ?? false }.map(\.id))
    }

    /// The engine's shapes, less what the Show panel has switched off.
    func seen(_ shapes: [DiagramShape]) -> [DiagramShape] {
        // Storyboard Frames off: no camera's picture on the plan (Ref 1504).
        let shapes = showFrames ? shapes : shapes.filter { $0.p != "shotframe" }
        guard !unseenKinds.isEmpty else { return shapes }
        let gone = unseenIds
        return shapes.filter { s in
            if let e = s.e, !e.isEmpty, gone.contains(e) { return false }
            if let k = DiagramShow.part(s.p), unseenKinds.contains(k) { return false }
            return true
        }
    }

    func setShown(_ key: String, _ on: Bool) {
        if on { unseenKinds.remove(key) } else { unseenKinds.insert(key) }
    }
}
