import SwiftUI
import AppKit

// **Light levels**, retired with the lamps' beams (a plot draws neither).
// What is left is the checks' report, so a battery can see they draw
// nothing. The panel, a lamp's height and the sun's brightness went
// 2026-10-05; the settings stay stored in old plans.

enum DiagramLevels {
    /// levels — for the checks: whether they are on, and every piece's
    /// level and ring as drawn.
    static func report(_ model: DiagramModel) -> String {
        let s = model.settings
        let shapes = model.seen(model.plan.shapes).filter { $0.p == "level" }
        let panel = model.showingDetails && model.selection.isEmpty && s.levels
        var out = String(format: "levels: %@ units %@ iso %.0f shutter %.0f stop %.1f ambient %.0f sun %.0f shapes %d panel %@\n",
                         s.levels ? "on" : "off", s.light_units, s.iso, s.shutter, s.stop, s.ambient, s.sun_lux, shapes.count,
                         panel ? "shown" : "hidden")
        var seen: [String] = []
        for sh in shapes { if let e = sh.e, !seen.contains(e) { seen.append(e) } }
        for id in seen {
            let mine = shapes.filter { $0.e == id }
            let words = mine.first { $0.k == "text" }?.tx ?? "-"
            let rings = mine.filter { $0.k != "text" }
            let kind = model.el(id)?.kind ?? "?"
            let dashed = rings.contains { ($0.da ?? "") == "dash" }
            out += "levels: \(kind) \(id) words \"\(words)\" rings \(rings.count) colour \(rings.first?.s ?? "-")\(dashed ? " omni" : "")\n"
        }
        return out
    }
}
