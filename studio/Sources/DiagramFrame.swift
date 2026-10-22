import SwiftUI

// Frames and gels on the plan — Lane B of the Scenario plan (2026-09-28).
//
// A frame is a light-kind piece drawn `frame`: any size, any skin, standing
// or lying, that cuts, dims, softens or bounces the beams it meets. Gels ride
// on a light or a frame. **The engine does all of it** (`frame.rs`,
// `gels.rs`, `render.rs`'s `light`): this file only names the choices and
// hands the picks back as edits.

/// The built-in gels, as the engine's `gels::GELS` lists them — ids are what
/// the plan stores, names what the menu and the plan's label say. Keep the
/// two lists in step.
enum DiagramGels {
    struct Gel: Identifiable, Hashable { let id: String; let name: String }

    static let groups: [(String, [Gel])] = [
        ("Color Temperature", [
            Gel(id: "cto-quarter", name: "¼ CTO"), Gel(id: "cto-half", name: "½ CTO"),
            Gel(id: "cto-3q", name: "¾ CTO"), Gel(id: "cto-full", name: "Full CTO"),
            Gel(id: "ctb-quarter", name: "¼ CTB"), Gel(id: "ctb-half", name: "½ CTB"),
            Gel(id: "ctb-full", name: "Full CTB"),
        ]),
        ("Neutral Density", [
            Gel(id: "nd3", name: "ND .3"), Gel(id: "nd6", name: "ND .6"), Gel(id: "nd9", name: "ND .9"),
        ]),
        ("Green", [
            Gel(id: "plus-green-quarter", name: "¼ Plus Green"), Gel(id: "plus-green-half", name: "½ Plus Green"),
            Gel(id: "minus-green-quarter", name: "¼ Minus Green"), Gel(id: "minus-green-half", name: "½ Minus Green"),
        ]),
        ("Diffusion", [
            Gel(id: "opal", name: "Opal"), Gel(id: "216", name: "216"),
            Gel(id: "250", name: "250"), Gel(id: "hampshire", name: "Hampshire"),
        ]),
    ]

    static func name(_ id: String) -> String {
        groups.flatMap(\.1).first { $0.id == id }?.name ?? id
    }
}

/// A frame's own choices, as the engine's `frame.rs` lists them — read
/// from the library (`DiagramLibrary.frames`), so there is one list.
enum DiagramFrames {
    static let sym = "frame"

    static func isFrame(_ e: DiagramEl) -> Bool { e.kind == "light" && e.sym == sym }


    static func choices(_ model: DiagramModel) -> DiagramFrameChoices? { model.library?.frames }

    static func materials(_ model: DiagramModel) -> [(String, String)] {
        (choices(model)?.materials ?? []).map { ($0.id, $0.name) }
    }
    static func defaultMaterial(_ model: DiagramModel) -> String { choices(model)?.default ?? "diff-medium" }

    static func material(_ e: DiagramEl, _ model: DiagramModel) -> DiagramFrameChoices.Material? {
        let id = e.material.isEmpty ? defaultMaterial(model) : e.material
        return choices(model)?.materials.first { $0.id == id }
    }

    /// Eight by eight feet: Scenario's new frame, lying flat (the engine
    /// lays a new one down).
    static let side = 8 * 0.3048

    /// How far a frame stands as its knob is dragged: the raised edge, which
    /// the knob rides, follows the hand toward the middle (standing up) or
    /// away (lying down), in 5°
    /// steps from flat (0) to upright (90).
    static func tilt(_ e: DiagramEl, at now: (x: Double, y: Double, rot: Double), from start: CGPoint, to p: CGPoint) -> Double {
        let r = now.rot * .pi / 180
        let half = (e.tall > 0 ? e.tall : e.h) / 2
        guard half > 0 else { return e.tilt }
        let moved = Double(p.x - start.x) * cos(r) + Double(p.y - start.y) * sin(r)
        let edge = half * cos(e.tilt * .pi / 180) - moved
        let k = min(max(edge / half, 0), 1)
        let deg = acos(k) * 180 / .pi
        return min(max((deg / 5).rounded() * 5, 0), 90)
    }
}

extension DiagramModel {
    /// A new frame at `p` — the Frame tool's click, and F at the pointer.
    /// It lies flat (his ruling, 2026-09-30); the engine sees to that.
    func addFrame(at p: CGPoint, rot: Double = 0) {
        edit(["op": "add", "els": [["kind": "light", "sym": DiagramFrames.sym, "x": p.x, "y": p.y, "rot": rot,
                                    "h": DiagramFrames.side, "beam": 0, "reach": 0, "beam_on": false]]], select: true)
        tool = .select
    }

    /// **Gels on these pieces, replacing what they had** — the inspector's
    /// Gels field, and the action bar's (Lane A) when it lands. An empty
    /// list takes them all off.
    func setGels(_ ids: [String], _ gels: [String]) {
        update(ids, ["gels": gels])
    }
}
