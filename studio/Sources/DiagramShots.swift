import SwiftUI
import AppKit

// **The shot list, inside the Diagram** — Scenario's Shot List sidebar (the
// plan of 2026-09-28, item 14). A tab of the app's left sidebar beside
// Scenes and Layers (`DiagramSidebar`), so the left side stays one column: this scene's shots in order, each with its
// number, its title and its frame. A shot already standing on the plan says
// so, and a click picks its camera. A shot not yet placed is dragged onto the
// plan to put its camera there. *Remove Camera* takes the camera away and
// keeps the shot — deleting a shot is never the plan's to do.

struct DiagramShots: View {
    @ObservedObject var model: DiagramModel
    @State private var hovered: String?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    private var rows: [ViewModel.Row] { model.state?.rows(of: model.state?.diagramScene) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(footer).sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
                Spacer()
                if !model.readOnly {
                    Button("Add Shot") { model.addShotHere() }
                        .buttonStyle(.rowAction)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            Rectangle().fill(Brand.rule(dark)).frame(height: 1)
            if rows.isEmpty {
                Text("No shots yet").sans(Brand.Size.body).foregroundStyle(Brand.ink2(dark)).padding(12)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.shot) { r in
                            DiagramShotRow(model: model, r: r, cams: model.cameras(for: r.shot),
                                           picked: { let c = model.cameras(for: r.shot); return !c.isEmpty && c.allSatisfy { model.selection.contains($0.id) } }(),
                                           hovered: $hovered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        // A tab of the left sidebar (`DiagramSidebar`), filling it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: String {
        let placed = rows.filter { !model.cameras(for: $0.shot).isEmpty }.count
        return "\(placed) of \(rows.count) on the plan"
    }

}

/// One shot in the list. Its cameras and pick come in from outside, so a
/// camera placed or taken away redraws the row.
struct DiagramShotRow: View {
    @ObservedObject var model: DiagramModel
    let r: ViewModel.Row
    let cams: [DiagramEl]
    let picked: Bool
    @Binding var hovered: String?
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        let placed = !cams.isEmpty
        let base = HStack(spacing: 8) {
            Group {
                if r.frame != nil {
                    Thumbnail(row: r, engine: model.engine, ratio: 16 / 9, dark: dark, width: 64 + 18)
                } else {
                    Rectangle().fill(Brand.rule(dark))
                }
            }
            .frame(width: 64, height: 36)
            // A picture is never rounded (his rule, 2026-10-07).
            .clipShape(Rectangle())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let c = cams.first {
                        Circle().fill(c.color.hasPrefix("#") ? Brand.hex(String(c.color.dropFirst())) : Brand.ink(dark))
                            .frame(width: 7, height: 7)
                    }
                    Text(r.number).sans(Brand.Size.body, weight: .bold).foregroundStyle(Brand.ink(dark))
                }
                Text(name(r)).sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if placed {
                Text("Placed").sans(Brand.Size.small).foregroundStyle(Brand.ink2(dark))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(picked ? Brand.glassOn(dark) : (hovered == r.shot ? Brand.glassHover(dark) : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = r.shot } else if hovered == r.shot { hovered = nil }
        }
        .onTapGesture { if placed { model.selection = cams.map(\.id) } }
        .contextMenu {
            if placed {
                Button("Remove Camera") { model.removeCamera(for: r.shot) }
            } else {
                Button("Place on Plan") { model.placeShot(r.shot, at: nil) }
            }
            Button("Show in Shot List") { model.showInShotList(r.shot) }
        }

        if placed || model.readOnly {
            base
        } else {
            base.diagramDragOut("shot:" + r.shot) {
                Text(r.number).sans(Brand.Size.body, weight: .bold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.glassOn(dark)))
            }
        }
    }

    private func name(_ r: ViewModel.Row) -> String {
        if !r.title.isEmpty { return r.title }
        if !r.description.isEmpty { return r.description }
        return "Untitled"
    }
}


extension DiagramModel {
    /// The cameras on this plan that stand for a shot.
    func cameras(for shot: String) -> [DiagramEl] {
        guard !shot.isEmpty else { return [] }
        return plan.els.filter { $0.kind == "camera" && $0.shot == shot }
    }

    /// A shot's camera put down: where it was dropped, or — from the menu —
    /// in the middle of the view. The shot is already a shot: no new one.
    func placeShot(_ shot: String, at p: CGPoint?) {
        guard !shot.isEmpty, cameras(for: shot).isEmpty else { return }
        let at = p ?? centre
        let op: [String: Any] = ["op": "add", "els": [[
            "kind": "camera", "x": at.x, "y": at.y, "rot": 0,
            "color": nextCameraColour(), "shot": shot,
        ]]]
        edit(op, select: true)
        tool = .select
    }

    /// The camera goes; the shot stays.
    func removeCamera(for shot: String) {
        remove(cameras(for: shot).map(\.id))
    }

    /// A new shot at the end of this scene, not yet on the plan.
    func addShotHere() {
        guard let state, let engine, let scene = state.diagramScene else { return }
        state.replace(engine.addShot(scene: scene))
    }
}

/// The checks' verbs for names, frames and the Shots tab (`studio/diagram.sh`).
enum DiagramShotsDrive {
    @MainActor
    static func perform(_ verb: String, _ args: [String], _ model: DiagramModel,
                        pull: (CGPoint, Double, Double) -> Void) -> Bool {
        let view = model.canvas as? DiagramCanvasView
        let rows = model.state?.rows(of: model.state?.diagramScene) ?? []
        func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        if DiagramSensorsDrive.perform(verb, args, model) { return true }
        switch verb {
        case "sidetab":
            // sidetab <shots|layers|legend> — the left sidebar, open on that tab
            model.sideTab = args.first ?? "layers"
        case "shots":
            // shots — the Shots tab as it reads: number, and whether placed
            let parts = rows.map { r in r.number + (model.cameras(for: r.shot).isEmpty ? " -" : " placed") }
            say("shots: " + parts.joined(separator: " | "))
        case "placeshot":
            // placeshot <n> <x> <y> — the scene's nth shot dragged onto the plan and let go there
            guard args.count >= 3, let n = Int(args[0]), rows.indices.contains(n),
                  let x = Double(args[1]), let y = Double(args[2]) else { return true }
            view?.drop("shot:" + rows[n].shot, at: CGPoint(x: x, y: y))
        case "pickshot":
            // pickshot <n> — a click on the nth shot's row
            guard let n = args.first.flatMap(Int.init), rows.indices.contains(n) else { return true }
            let cams = model.cameras(for: rows[n].shot)
            if !cams.isEmpty { model.selection = cams.map(\.id) }
        case "removecam":
            // removecam <n> — the nth shot's row, right-click Remove Camera
            guard let n = args.first.flatMap(Int.init), rows.indices.contains(n) else { return true }
            model.removeCamera(for: rows[n].shot)
        case "addshot":
            model.addShotHere()
        case "name":
            // name <hide|show|size N|bold on|off|reset> — the action bar's Name menu, on what is picked
            let set: [String: Any]
            switch args.first ?? "" {
            case "hide": set = ["label_hidden": true]
            case "show": set = ["label_hidden": false]
            case "size": set = ["label_size": Double(args.count > 1 ? args[1] : "0") ?? 0]
            case "bold": set = ["label_bold": args.last != "off"]
            case "reset": set = ["label_dx": 0, "label_dy": 0]
            default: return true
            }
            model.update(model.selection, set)
        case "namedrag":
            // namedrag <kind> <dx> <dy> — the name of the last piece of that kind, dragged by itself
            guard args.count >= 3, let view, let dx = Double(args[1]), let dy = Double(args[2]),
                  let e = model.plan.els.last(where: { $0.kind == args[0] }),
                  let r = view.labelRects.last(where: { $0.1 == e.id })?.0 else {
                say("drive: no name to drag \(args)"); return true
            }
            pull(CGPoint(x: r.midX, y: r.midY), dx, dy)
        case "frame":
            // frame <on|off> — the action bar's Frame, on the picked camera
            model.update(model.selection, ["frame_on": args.first != "off"])
        case "framedrag", "framesize":
            // framedrag <dx> <dy> — the picked camera's frame, dragged; framesize <dx> — by its corner
            guard let view, let e = model.shownPicked.first, let r = view.frameRect(e),
                  let dx = args.first.flatMap(Double.init) else { say("drive: no frame \(args)"); return true }
            let dy = args.count > 1 ? Double(args[1]) ?? 0 : 0
            let from = verb == "framesize" ? CGPoint(x: r.maxX - 1, y: r.maxY - 1) : CGPoint(x: r.midX, y: r.midY)
            pull(from, dx, dy)
        case "typename":
            // typename — the picked lamp's Name, opened for typing (the bar's Name)
            if let id = model.selection.first { model.startTyping(id, .name) }
        case "renaming", "typing":
            // typing — what is being typed on the plan, where, and what the words hold
            let field = model.canvas?.window?.firstResponder as? NSTextView
            let t = model.typing
            var line = "typing: \(t.map { "\($0.el) \($0.what.rawValue)" } ?? "none") field \"\(field?.string ?? "-")\" picked \(field.map { $0.selectedRange().length } ?? -1)"
            if let v = (model.canvas as? DiagramCanvasView)?.typist {
                line += String(format: " at %.0f,%.0f %.0fx%.0f pt %.1f", v.frame.minX, v.frame.minY, v.frame.width, v.frame.height, v.font?.pointSize ?? 0)
            }
            line += " bar \"\(model.typed ?? "-")\""
            if let t, let e = model.el(t.el) { line += " hidden \((e.label_hidden ?? false) ? "yes" : "no")" }
            say(line)
        case "typeon":
            // typeon <name|note|text|label> — the bar's Name, Note or Text on the first piece picked: typing on the plan
            guard let id = model.selection.first, let what = args.first.flatMap(DiagramTyping.What.init(rawValue:)) else { return true }
            model.startTyping(id, what)
        case "type":
            // type <words> — typed into whatever has the keyboard, a key at a time
            guard let window = model.canvas?.window else { return true }
            for c in args.joined(separator: " ") {
                if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                            context: nil, characters: String(c), charactersIgnoringModifiers: String(c),
                                            isARepeat: false, keyCode: 0) {
                    NSApp.sendEvent(e)
                }
            }
        case "label":
            // label <words> — names what is picked, as Details' Name field does
            model.update(model.selection, ["label": args.joined(separator: " ")])
        case "opacity":
            // opacity <0…1> — what is picked, as Details' Opacity slider sets it
            if let v = args.first.flatMap(Double.init) { model.update(model.selection, ["opacity": v]) }
        case "names":
            // names — every piece's name fields and laid-on frame, and where its name is drawn
            // Drawn now, so "where it is drawn" is this plan and not the
            // last picture: the foot bar appearing must not race the report.
            view?.needsDisplay = true
            view?.displayIfNeeded()
            for e in model.plan.els {
                var line = String(format: "names: %@ %@ dx %.2f dy %.2f size %.0f bold %@ hidden %@", e.kind, e.id,
                                  e.label_dx ?? 0, e.label_dy ?? 0, e.label_size ?? 0,
                                  (e.label_bold ?? true) ? "yes" : "no", (e.label_hidden ?? false) ? "yes" : "no")
                if let r = view?.labelRects.last(where: { $0.1 == e.id })?.0 {
                    line += String(format: " drawn %.0f,%.0f box %.0f,%.0f,%.0f,%.0f", r.midX, r.midY, r.minX, r.minY, r.maxX, r.maxY)
                    // Where its piece stands on screen, whether a line ties
                    // the name back to it, and the words drawn.
                    if let p = view?.pointOf(e.id) { line += String(format: " piece %.0f,%.0f", p.x, p.y) }
                    let shapes = model.shown.shapes
                    line += " tie " + (shapes.contains { $0.e == e.id && $0.p == "tie" } ? "yes" : "no")
                    let s = shapes.first { $0.e == e.id && $0.p == "label" }
                    line += String(format: " ink %@ patch %@ shift %.2f,%.2f", s?.f ?? "-", s?.pa == true ? "yes" : "no", s?.nx ?? 0, s?.ny ?? 0)
                    line += " text \"\((s?.tx ?? "").replacingOccurrences(of: "\n", with: "/"))\""
                } else {
                    line += " drawn none"
                }
                if e.kind == "light", let n = e.lamp_name, !n.isEmpty { line += " lamp_name \(n)" }
                if e.kind == "camera" {
                    let pic = model.plan.shapes.contains { $0.e == e.id && $0.p == "shotframe" && $0.k == "img" }
                    line += String(format: " frame %@ offset %.2f,%.2f w %.2f picture %@", (e.frame_on ?? false) ? "on" : "off",
                                   e.frame_dx ?? 0, e.frame_dy ?? 0, e.frame_w ?? 0, pic ? "yes" : "no")
                    if let r = view?.frameRect(e) { line += String(format: " at %.0f,%.0f", r.midX, r.midY) }
                }
                say(line)
            }
        default:
            return false
        }
        return true
    }
}
