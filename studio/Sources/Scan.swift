import Foundation
import simd

/// A scanned room, as the engine hands it over.
///
/// **There is no geometry in this file, on purpose.** His instruction of
/// 2026-08-21: *"iOS has been handling the floor plan creation. I just need you
/// to display it, or you guys should just share the same engine."*
///
/// So the reading, the straightening, the fitting and the classifying all live
/// in `engine/src/room.rs`, which the Mac, the phone and Claude's own server all
/// build. This is the thin end of it: one command out, one plan back, and a
/// couple of conveniences the *drawing* needs and the engine deliberately does
/// not send — corners at a drawn thickness, and feet and inches.
///
/// It was a full Swift port for about an hour this afternoon. That port is gone;
/// what is left of it is the drawing in `FloorPlan.swift`, which is the only
/// part that genuinely differs between a Mac and a phone.
struct Plan: Decodable {
    var items: [Item]
    /// How far the room was turned to bring it square to the page, kept so a
    /// measurement can still be traced back to the wall it came from.
    var straightenedBy: Float
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float
    /// The commonest wall height — the honest answer when a scanner reports six
    /// walls that agree to the centimetre.
    var ceiling: Float
    var ceilingLow: Float
    var ceilingHigh: Float
    /// Whether the walls disagree enough to be worth saying so. A stepped or
    /// sloped ceiling is a real fact about a location.
    var ceilingVaries: Bool

    struct Item: Decodable, Identifiable {
        enum Kind: String, Decodable {
            case wall, door, window, opening, object
        }
        var part: Kind
        var x: Float
        var y: Float
        /// How long it is, and how thick, from above — **as scanned**. RoomPlan
        /// reports walls with a thickness of exactly zero: they are planes, not
        /// slabs, and the drawing does the inflating so that an invented
        /// thickness can never reach a measurement.
        var length: Float
        var depth: Float
        var height: Float
        /// Turned this far anticlockwise from east, in radians.
        var angle: Float
        var furnishing: Furnishing

        var id: String { "\(part.rawValue)/\(x)/\(y)/\(length)/\(angle)" }
        var kind: Kind { part }
        var centre: SIMD2<Float> { SIMD2(x, y) }
        var size: SIMD2<Float> { SIMD2(length, depth) }

        /// The four corners, in world metres, at whatever thickness is asked
        /// for. Nil keeps the scan's own answer.
        func corners(thickness: Float? = nil) -> [SIMD2<Float>] {
            let across = max(depth, thickness ?? 0)
            let c = cos(angle), s = sin(angle)
            let half = SIMD2(length, across) / 2
            return [
                SIMD2(-half.x, -half.y), SIMD2(half.x, -half.y),
                SIMD2(half.x, half.y), SIMD2(-half.x, half.y),
            ].map { corner in
                SIMD2(centre.x + corner.x * c - corner.y * s,
                      centre.y + corner.x * s + corner.y * c)
            }
        }

        var corners: [SIMD2<Float>] { corners(thickness: nil) }

        /// Where the wall runs, as the two ends of its centre line — what a
        /// dimension is actually measuring.
        var ends: (SIMD2<Float>, SIMD2<Float>) {
            let half = length / 2
            let along = SIMD2(cos(angle), sin(angle))
            return (centre - along * half, centre + along * half)
        }

        /// Which way is "out of the wall".
        var normal: SIMD2<Float> { SIMD2(-sin(angle), cos(angle)) }
    }

    enum Furnishing: String, Decodable {
        case bed, seat, sofa, table, storage, screen, appliance, plumbing, stairs, other
    }

    var walls: [Item] { items.filter { $0.part == .wall } }
    var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        (SIMD2(minX, minY), SIMD2(maxX, maxY))
    }
    var extent: SIMD2<Float> { bounds.max - bounds.min }
    var ceilingRange: (Float, Float) { (ceilingLow, ceilingHigh) }
    var isEmpty: Bool { items.isEmpty }

    /// Ask the engine to read a scan. Nil means there was no room in it — which
    /// is worth failing on rather than drawing half of one.
    static func read(_ url: URL, from engine: Engine?) -> Plan? {
        engine?.floorplan(at: url.path)
    }

    /// The hand-built room, for checking the drawing where there is no room to
    /// stand in. Also the engine's — see `room::sample`.
    static func sample(from engine: Engine?) -> Plan? {
        engine?.floorplan(at: "")
    }
}

// MARK: - saying a length

enum Measured {
    /// Feet and inches, the way a location scout says a room — "13 ft 3 in".
    static func imperial(_ metres: Float) -> String {
        let totalInches = (metres * 39.3700787).rounded()
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        if feet == 0 { return "\(inches) in" }
        return inches == 0 ? "\(feet) ft" : "\(feet) ft \(inches) in"
    }
}
