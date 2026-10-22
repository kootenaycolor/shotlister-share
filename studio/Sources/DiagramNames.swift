import SwiftUI
import AppKit

// **Names you can move, and a camera's frame laid on the plan** — Scenario's
// text labels and frame image (the plan of 2026-09-28, items 3 and 15). The
// engine keeps both as fields on the piece: `label_dx`, `label_dy` (metres on
// the page as shown, north up), `label_hidden`; and on a camera `frame_on`,
// `frame_dx`, `frame_dy`, `frame_w`. A label is one size and one weight on
// the plot (Back to Paper): `label_size` and `label_bold` stay stored and
// Claude's connector keeps them, but the app no longer offers them. Every
// change is an edit the engine makes, previewed while it is dragged. Typing
// a name is `DiagramTyping.swift`.

/// A name or a frame, held by the mouse.
enum DiagramNameDrag {
    /// A name, dragged on its own: where the press was, the offset it had.
    case name(id: String, start: CGPoint, dx: Double, dy: Double, now: (Double, Double))
    /// A camera's frame, dragged about.
    case frame(id: String, start: CGPoint, dx: Double, dy: Double, now: (Double, Double))
    /// A camera's frame, sized by any corner (his note, 2026-10-05:
    /// "storyboard frames should be scalable"); the corner across from it
    /// stays. `anchor` that corner and `cam` the camera, on screen; `sx`,
    /// `sy` which way the held corner lies from the anchor.
    case sizing(id: String, anchor: CGPoint, cam: CGPoint, sx: CGFloat, sy: CGFloat, aspect: Double, now: [String: Any])
    /// Pressed on a name that may not move (locked): picked, nothing more.
    case held
}

extension DiagramCanvasView {
    /// The name under a point, by the piece it names.
    func hitLabel(_ v: CGPoint) -> String? {
        let back = model?.layerLockedIds ?? []
        return labelRects.last { $0.0.insetBy(dx: -3, dy: -3).contains(v) && !back.contains($0.1) }?.1
    }

    /// **The name a click takes**, if a name takes it at all. A name lying
    /// over another piece — a lamp's, on the stand it rides; a shape's, under
    /// a shared label — takes the press only once its own piece is picked;
    /// until then the press is the piece's under it. A single click and a
    /// double-click both ask here, so they never land on different pieces.
    func clickedLabel(_ v: CGPoint) -> String? {
        guard let m = model, let id = hitLabel(v) else { return nil }
        if !m.selection.contains(id), let engine = m.engine, let scene = m.scene {
            let p = m.toWorld(v, size: bounds.size)
            if let under = engine.diagramHit(scene: scene, x: p.x, y: p.y, tolerance: 2 / m.scale, beat: m.beat,
                                             skip: m.unseenIds.union([id])), under != id,
               let piece = m.el(under), piece.kind != "image", !piece.locked {
                return nil
            }
        }
        return id
    }

    /// Where a camera's laid-on frame stands on screen.
    func frameRect(_ e: DiagramEl) -> CGRect? {
        guard let m = model, m.showFrames, e.kind == "camera", e.frame_on == true else { return nil }
        let now = e.at(beat: m.beat)
        let c = m.toView(CGPoint(x: now.x, y: now.y), size: bounds.size)
        let w = (e.frame_w ?? 1.5) * Double(m.scale)
        let img = m.shown.shapes.first { $0.e == e.id && $0.p == "shotframe" && $0.k == "img" }
        let aspect = img.flatMap { s -> Double? in
            guard let iw = s.iw, let ih = s.ih, iw > 0 else { return nil }
            return ih / iw
        } ?? 9.0 / 16.0
        let h = w * aspect
        let mid = CGPoint(x: c.x + CGFloat((e.frame_dx ?? 0)) * m.scale, y: c.y + CGFloat((e.frame_dy ?? 1.4)) * m.scale)
        return CGRect(x: mid.x - CGFloat(w) / 2, y: mid.y - CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h))
    }

    /// A laid-on frame's four corners, on screen: top left, top right,
    /// bottom right, bottom left.
    func frameCorners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    /// The frame under a point, and which of its corners, if one.
    func hitFrame(_ v: CGPoint) -> (DiagramEl, corner: Int?)? {
        guard let m = model, m.showFrames else { return nil }
        let back = m.layerLockedIds
        for e in m.shown.els.reversed() where e.kind == "camera" && e.frame_on == true && !m.unseenIds.contains(e.id) && !back.contains(e.id) {
            guard let r = frameRect(e) else { continue }
            if let i = frameCorners(r).firstIndex(where: { hypot(v.x - $0.x, v.y - $0.y) <= 9 }) { return (e, i) }
            if r.insetBy(dx: -2, dy: -2).contains(v) { return (e, nil) }
        }
        return nil
    }

    /// A press in the select tool: on a frame, or on a name. True when it
    /// was one of them and the press is taken.
    func nameDown(_ v: CGPoint, _ event: NSEvent) -> Bool {
        guard let m = model, !event.modifierFlags.contains(.shift) else { return false }
        if let (e, corner) = hitFrame(v) {
            m.selection = [e.id]
            guard !e.locked else { nameDrag = .held; return true }
            let (dx, dy) = (e.frame_dx ?? 0, e.frame_dy ?? 1.4)
            if let corner, let r = frameRect(e) {
                let c = frameCorners(r)
                let held = c[corner], anchor = c[(corner + 2) % 4]
                let cam = CGPoint(x: r.midX - CGFloat(dx) * m.scale, y: r.midY - CGFloat(dy) * m.scale)
                nameDrag = .sizing(id: e.id, anchor: anchor, cam: cam, sx: held.x >= anchor.x ? 1 : -1, sy: held.y >= anchor.y ? 1 : -1,
                                   aspect: r.width > 0 ? Double(r.height / r.width) : 9.0 / 16.0, now: [:])
            } else {
                nameDrag = .frame(id: e.id, start: v, dx: dx, dy: dy, now: (dx, dy))
            }
            return true
        }
        guard let id = clickedLabel(v), let e = m.el(id) else { return false }
        if !m.selection.contains(id) { m.selection = [id] }
        guard !e.locked else { nameDrag = .held; return true }
        // From where it is drawn: a name the plan stepped aside to keep it
        // clear starts its drag from there, not from under its piece.
        let drawn = m.shown.shapes.first { $0.e == id && $0.p == "label" }
        let (dx, dy) = ((e.label_dx ?? 0) + (drawn?.nx ?? 0), (e.label_dy ?? 0) + (drawn?.ny ?? 0))
        nameDrag = .name(id: id, start: v, dx: dx, dy: dy, now: (dx, dy))
        return true
    }

    func nameDragged(_ v: CGPoint, _ event: NSEvent) -> Bool {
        guard let m = model, let held = nameDrag else { return false }
        let k = Double(max(m.scale, 0.001))
        switch held {
        case .name(let id, let start, let dx, let dy, _):
            let now = (dx + Double(v.x - start.x) / k, dy + Double(v.y - start.y) / k)
            nameDrag = .name(id: id, start: start, dx: dx, dy: dy, now: now)
            m.previewing(DiagramOps.update([id], ["label_dx": now.0, "label_dy": now.1]))
        case .frame(let id, let start, let dx, let dy, _):
            let now = (dx + Double(v.x - start.x) / k, dy + Double(v.y - start.y) / k)
            nameDrag = .frame(id: id, start: start, dx: dx, dy: dy, now: now)
            m.previewing(DiagramOps.update([id], ["frame_dx": now.0, "frame_dy": now.1]))
        case .sizing(let id, let anchor, let cam, let sx, let sy, let aspect, _):
            // As wide as the pointer is from the corner that stays, across or
            // down, its own shape kept; never under a foot.
            let a = CGFloat(aspect)
            let across = max(sx * (v.x - anchor.x), sy * (v.y - anchor.y) / max(a, 0.01), CGFloat(0.3 * k))
            let mid = CGPoint(x: anchor.x + sx * across / 2, y: anchor.y + sy * across * a / 2)
            let set: [String: Any] = ["frame_w": Double(across) / k,
                                      "frame_dx": Double(mid.x - cam.x) / k, "frame_dy": Double(mid.y - cam.y) / k]
            nameDrag = .sizing(id: id, anchor: anchor, cam: cam, sx: sx, sy: sy, aspect: aspect, now: set)
            m.previewing(DiagramOps.update([id], set))
        case .held:
            break
        }
        return true
    }

    func nameUp() -> Bool {
        guard let m = model, let held = nameDrag else { return false }
        nameDrag = nil
        switch held {
        case .name(let id, _, let dx, let dy, let now) where now != (dx, dy):
            m.update([id], ["label_dx": now.0, "label_dy": now.1])
        case .frame(let id, _, let dx, let dy, let now) where now != (dx, dy):
            m.update([id], ["frame_dx": now.0, "frame_dy": now.1])
        case .sizing(let id, _, _, _, _, _, let set) where !set.isEmpty:
            m.update([id], set)
        default:
            m.preview = nil
        }
        return true
    }
}

/// What has a name on the plan.
enum DiagramNames {

    /// **Frame on Plan, from anywhere it is offered.** A camera whose shot has
    /// no picture yet used to lay an empty "No Frame" box, which read as a
    /// picture that failed to load (his note, 2026-09-28: "it loads blank").
    /// Switching it on now asks for the picture first — it becomes the shot's
    /// frame, the same as dropping it in the shot list — and a cancel leaves
    /// the plan as it was.
    static func setFrame(_ on: Bool, _ e: DiagramEl, model: DiagramModel) {
        guard on, let state = model.state, !e.shot.isEmpty,
              let row = state.view?.allRows.first(where: { $0.shot == e.shot }), row.frame == nil else {
            model.update([e.id], ["frame_on": on])
            return
        }
        Ingest.addViaPanel(to: row, state: state)
        let got = state.view?.allRows.first(where: { $0.shot == e.shot })?.frame != nil
        if got { model.update([e.id], ["frame_on": true]) }
    }

    /// Kinds that draw a name — a light always, a camera or a person by its
    /// shot or character, the rest when he has typed one.
    static func hasName(_ e: DiagramEl) -> Bool {
        switch e.kind {
        case "light", "camera", "cast": return true
        case "set", "shape", "track", "road", "arrow", "cable", "measure": return !e.label.isEmpty || e.kind == "measure"
        default: return false
        }
    }

    /// Whether this piece's name is typed on the plan (Return, a
    /// double-click, Name on the bar): a piece named by what he types — not
    /// a camera named by its shot, nor a person by their character, which
    /// are named where those live.
    /// **What can wear a Note** (2026-10-05): every piece that draws a name,
    /// whether or not it has one yet. A lamp's and a frame's Note is their
    /// own (`DiagramTyping`); Words are words.
    static func notable(_ e: DiagramEl) -> Bool {
        ["light", "set", "track", "road", "arrow", "shape", "cable", "wall", "camera", "cast"].contains(e.kind)
            || (e.kind == "stroke" && e.isPath)
    }

    static func renamable(_ e: DiagramEl) -> Bool {
        switch e.kind {
        case "light", "set", "track", "road", "arrow", "shape", "cable", "wall": return true
        case "stroke": return e.isPath
        // **Every piece takes a typed label** (2026-10-17): a camera's beats
        // its shot's number, a person's their character.
        case "camera", "cast": return true
        default: return false
        }
    }

    /// Return on one picked piece: the cursor in its words, on the plan —
    /// a lamp's Note, Words' text, anything else's name — or a camera's
    /// Details. Only while the plan has the keyboard.
    static func renameKey(_ e: NSEvent, _ model: DiagramModel) -> Bool {
        guard [36, 76].contains(e.keyCode),
              e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              !model.presenting, !model.readOnly, model.typing == nil,
              model.pending.isEmpty, let canvas = model.canvas, canvas.window?.firstResponder === canvas,
              model.picked.count == 1, let one = model.picked.first else { return false }
        if one.kind == "camera", !one.shot.isEmpty { model.openDetails(); return true }
        model.startTyping(one.id)
        return model.typing != nil
    }
}
