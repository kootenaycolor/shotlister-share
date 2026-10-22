import Foundation
import simd

/// A scanned room, as the engine works it out.
///
/// **The arithmetic is not here any more.** It lived in this file for an
/// afternoon, was ported into Swift a second time for the Mac, and is now in
/// `engine/src/room.rs` — one copy, ten tests, both apps asking. His ruling:
/// *"iOS has been handling the floor plan creation. I just need you to display
/// it, or you guys should just share the same engine."*
///
/// What is left here is what a *drawing* needs and a measurement must never see:
/// the corners of a shape at whatever thickness the plan chooses to draw walls
/// at. The engine deliberately does not send those — letting an invented 12cm
/// cross that boundary is how it ends up inside somebody's measurement.
struct Plan: Decodable {
    var items: [Item]
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float
    /// How far the room was turned to bring it square to the page.
    var straightenedBy: Float
    /// The commonest wall height — the honest answer when a scanner reports six
    /// walls agreeing to the centimetre.
    var ceiling: Float
    var ceilingLow: Float
    var ceilingHigh: Float
    /// Whether the walls disagree enough to be worth saying so. A stepped or
    /// sloped ceiling is a real fact about a location.
    var ceilingVaries: Bool

    struct Item: Decodable, Identifiable {
        var part: String
        var x: Float
        var y: Float
        var length: Float
        var depth: Float
        var height: Float
        var angle: Float
        var furnishing: String

        var id: String { "\(part)-\(x)-\(y)-\(length)-\(angle)" }

        var isWall: Bool { part == "wall" }
        var isObject: Bool { part == "object" }
        var isHole: Bool { part == "door" || part == "window" || part == "opening" }

        var centre: SIMD2<Float> { SIMD2(x, y) }

        /// The four corners, at whatever thickness the drawing asks for. Zero
        /// keeps the scan's own answer, which is what any measurement must use.
        func corners(thickness: Float? = nil) -> [SIMD2<Float>] {
            let across = max(depth, thickness ?? 0)
            let c = cos(angle), s = sin(angle)
            let half = SIMD2(length, across) / 2
            return [
                SIMD2(-half.x, -half.y), SIMD2(half.x, -half.y),
                SIMD2(half.x, half.y), SIMD2(-half.x, half.y),
            ].map { corner in
                SIMD2(x + corner.x * c - corner.y * s,
                      y + corner.x * s + corner.y * c)
            }
        }

        /// Where the wall runs, as the two ends of its centre line — what a
        /// dimension is actually measuring.
        var ends: (SIMD2<Float>, SIMD2<Float>) {
            let along = SIMD2(cos(angle), sin(angle))
            return (centre - along * (length / 2), centre + along * (length / 2))
        }

        /// Which way is "out of the wall".
        var normal: SIMD2<Float> { SIMD2(-sin(angle), cos(angle)) }
    }

    var walls: [Item] { items.filter(\.isWall) }
    var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        (SIMD2(minX, minY), SIMD2(maxX, maxY))
    }
    var extent: SIMD2<Float> { bounds.max - bounds.min }
    var ceilingRange: (Float, Float) { (ceilingLow, ceilingHigh) }
    var isEmpty: Bool { items.isEmpty }
}

// ---------------------------------------------------------- saying a length

enum Measured {
    /// Feet and inches, the way a location scout says a room — "13 ft 3 in".
    /// Kept here rather than in the engine: it is presentation, and four lines.
    static func imperial(_ metres: Float) -> String {
        let totalInches = (metres * 39.3700787).rounded()
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        if feet == 0 { return "\(inches) in" }
        return inches == 0 ? "\(feet) ft" : "\(feet) ft \(inches) in"
    }
}
