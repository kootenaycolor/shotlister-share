import SwiftUI

// **A camera and its lens, one system** — his design, 2026-10-01.
//
// *"Let's get rid of the preset focal lengths and preset camera bodies, and
// I'll just make my own custom ones. When I'm on a zoom lens, I should be able
// to have a slider where I select the focal length, and that should also
// correlate to a shot."* Then: *"Let's try to unify things and simplify as
// much as possible."*
//
// So the film defines two lists and everything else picks from them:
// - **Cameras** (Project Settings): A-Cam, B-Cam — each with the sensor he
//   typed, a name and millimetres (`Doc::set_unit_sensor`). This Mac keeps
//   every sensor he has made as a preset for the next film.
// - **Lenses**: the Lens list. A name says the rest — `24-70mm` is a zoom,
//   `Hawk 2x 50mm` a 2× squeeze (`lens.rs`).
// A camera on the plan *is* its shot: its Camera, Lens and a zoom's focal
// length are the shot's, written to the shot list (`render::camera_optics`).

/// A sensor he typed: a name and millimetres.
struct DiagramFilmSensor: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var w: Double
    var h: Double

    /// `36.70 × 25.54 mm`
    var size: String {
        h > 0 ? String(format: "%.2f × %.2f mm", w, h) : String(format: "%.2f mm", w)
    }
}

/// Every sensor he has made on this Mac, for any film.
enum SensorPresets {
    private static let key = "diagramSensorPresets"

    static func all() -> [DiagramFilmSensor] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([DiagramFilmSensor].self, from: data) else {
            // The one he asked for by name before there were presets.
            return [DiagramFilmSensor(id: "u-alexaminilfopengate", name: "Alexa Mini LF Open Gate", w: 36.70, h: 25.54)]
        }
        return list
    }

    static func id(for name: String) -> String {
        "u-" + name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func keep(_ s: DiagramFilmSensor) {
        var list = all()
        if let i = list.firstIndex(where: { $0.id == s.id }) { list[i] = s } else { list.append(s) }
        save(list)
    }

    static func forget(_ id: String) {
        save(all().filter { $0.id != id })
    }

    private static func save(_ list: [DiagramFilmSensor]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension DiagramModel {
    /// The shot this camera is, when it is one the film still has.
    func shotRow(_ e: DiagramEl) -> ViewModel.Row? {
        guard !e.shot.isEmpty else { return nil }
        return state?.view?.allRows.first { $0.shot == e.shot }
    }

    /// One of the film's cameras: onto the shot, else onto the plan's camera.
    func setCamera(_ e: DiagramEl, unit: String) {
        if let row = shotRow(e), let engine {
            state?.replace(engine.set(shot: row.shot, field: "unit", value: unit))
            reload()
        } else {
            update([e.id], ["unit": unit])
        }
    }

    /// A lens off the film's list: onto the shot, else onto the plan's camera.
    func setLens(_ e: DiagramEl, name: String) {
        if let row = shotRow(e), let engine {
            state?.replace(engine.set(shot: row.shot, field: "lens", value: name))
            if e.lens > 0 { update([e.id], ["lens": 0.0]) } else { reload() }
        } else {
            update([e.id], ["lens_name": name, "lens": 0.0])
        }
    }

    /// Where a zoom is set, or a focal length typed on a camera with no lens.
    func setFocal(_ e: DiagramEl, mm: Double) {
        if let row = shotRow(e), let engine, e.zoom != nil {
            state?.replace(engine.set(shot: row.shot, field: "focal", value: String(Int(mm.rounded()))))
            reload()
        } else {
            update([e.id], ["lens": mm.rounded()])
        }
    }
}

/// **A zoom's focal length**: a slider across its range, and the number,
/// which can be typed. Kept when the slider is let go — one step of undo.
struct FocalSlider: View {
    let range: ClosedRange<Double>
    let value: Double
    let set: (Double) -> Void
    @State private var draft: Double?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 10) {
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0.rounded() }),
                   in: range) { editing in
                if !editing, let d = draft { set(d); draft = nil }
            }
            .controlSize(.small)
            Committing(text: "\(Int((draft ?? value).rounded()))mm") { typed in
                if let n = Double(typed.filter { $0.isNumber || $0 == "." }) {
                    set(min(max(n, range.lowerBound), range.upperBound))
                }
            }
            .frame(width: 64)
        }
        .foregroundStyle(Brand.ink(dark))
    }
}

/// Name, width and height, and Save.
struct NewSensorForm: View {
    let save: (String, Double, Double) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var w = ""
    @State private var h = ""

    private func mm(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." })
    }
    private var ok: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, let w = mm(w), (1...100).contains(w) else { return false }
        return h.isEmpty || (mm(h).map { (0...100).contains($0) } ?? false)
    }
    private func commit() {
        guard ok, let width = mm(w) else { return }
        save(name.trimmingCharacters(in: .whitespaces), width, mm(h) ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Sensor").sans(Brand.Size.body, weight: .semibold)
            Field("Name") { FieldText(placeholder: "Alexa 35 Open Gate", text: $name, onSubmit: commit) }
            HStack(spacing: 10) {
                Field("Width") { FieldText(placeholder: "mm", text: $w, onSubmit: commit) }
                Field("Height") { FieldText(placeholder: "mm", text: $h, onSubmit: commit) }
            }
            HStack {
                Spacer()
                Button("Cancel") { cancel() }.buttonStyle(.capsule).keyboardShortcut(.escape, modifiers: [])
                Button("Save") { commit() }.buttonStyle(.primary).disabled(!ok)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

/// The checks' way in (`SHOTLISTER_DIAGRAMDRIVE`).
enum DiagramSensorsDrive {
    @MainActor
    static func perform(_ verb: String, _ args: [String], _ model: DiagramModel) -> Bool {
        if DiagramPageDrive.perform(verb, args, model) { return true }
        let e = model.selection.count == 1 ? model.el(model.selection[0]) : nil
        switch verb {
        case "sensorform":
            // sensorform <path.png> — the New Sensor form, drawn to a file
            guard let path = args.first else { return true }
            let r = ImageRenderer(content: NewSensorForm(save: { _, _, _ in }, cancel: {})
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        case "dblcam":
            // dblcam — double-click the first camera where it stands, as a person would
            guard let view = model.canvas as? DiagramCanvasView, let window = view.window,
                  let cam = model.plan.els.first(where: { $0.kind == "camera" }), let p = view.pointOf(cam.id) else { return true }
            let at = view.convert(p, to: nil)
            for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1), (.leftMouseDown, 2), (.leftMouseUp, 2)] {
                if let ev = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: n,
                                               pressure: type == .leftMouseUp ? 0 : 1) {
                    window.sendEvent(ev)
                }
            }
        case "addcam":
            // addcam <label> — a camera on the film, as Settings adds one
            guard let engine = model.engine, !args.isEmpty else { return true }
            model.state?.replace(engine.addUnit(label: args.joined(separator: " "), colour: "#D9483B"))
        case "camsensor":
            // camsensor <camera label> <w> <h> <name…> — a film camera's sensor, as Settings sets it
            guard args.count >= 4, let w = Double(args[1]), let h = Double(args[2]), let engine = model.engine,
                  let unit = model.state?.view?.units.first(where: { $0.label == args[0] }) else { return true }
            model.state?.replace(engine.setUnitSensor(id: unit.id, name: args.dropFirst(3).joined(separator: " "), w: w, h: h))
            model.reload()
        case "camera":
            // camera <camera label> — the picked camera's Camera, as its menu sets it
            guard let e, let unit = model.state?.view?.units.first(where: { $0.label == args.joined(separator: " ") }) else { return true }
            model.setCamera(e, unit: unit.id)
        case "lensname":
            // lensname <lens…> — the picked camera's Lens, off the film's list
            guard let e else { return true }
            model.setLens(e, name: args.joined(separator: " "))
        case "focal":
            // focal <mm> — where the picked camera's zoom is set
            guard let e, let mm = args.first.flatMap(Double.init) else { return true }
            model.setFocal(e, mm: mm)
        case "rulers":
            // rulers — every ruler's markers: where each stands and what it is locked to
            var out = ""
            for r in model.plan.els where r.isRuler {
                let marks = r.corners.enumerated().map { i, c in
                    String(format: "%.2f,%.2f", c.x, c.y) + (r.lock(i).flatMap { model.el($0) }.map { "@" + model.lockName($0) } ?? "")
                }
                out += "ruler: \(r.id) \(marks.joined(separator: " "))\n"
            }
            FileHandle.standardError.write(Data(out.utf8))
        case "markeradd":
            // markeradd <stretch> <kind> — a marker on that stretch of the picked ruler, locked to the first piece of that kind
            guard let e, e.isRuler, args.count >= 2, let i = Int(args[0]),
                  let p = model.plan.els.first(where: { $0.kind == args[1] }) else { return true }
            model.edit(model.wallOp("wall_insert", e, ["stretch": i, "on": p.id]))
        case "markerlock":
            // markerlock <corner> <kind> — lock the picked ruler's marker to the first piece of that kind
            guard let e, e.isRuler, args.count >= 2, let i = Int(args[0]),
                  let p = model.plan.els.first(where: { $0.kind == args[1] }) else { return true }
            model.pickedCorner = i
            model.lockMarker(e, to: p.id)
        case "optics":
            // optics — every camera's camera, lens, zoom, focal, sensor and view
            var out = ""
            for c in model.plan.els where c.kind == "camera" {
                out += "optics: \(c.cam_unit_label ?? "-") | \(c.lens_text ?? "-") | zoom \(c.zoom.map { "\(Int($0[0]))-\(Int($0[1]))" } ?? "-") | focal \(Int((c.focal ?? 0).rounded())) | \(c.gate_name ?? "-") | \(String(format: "%.1f", c.aov ?? 0))°\n"
            }
            FileHandle.standardError.write(Data(out.utf8))
        default:
            return false
        }
        return true
    }
}
