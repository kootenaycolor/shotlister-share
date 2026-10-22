import SwiftUI
import AppKit

// The Diagram mode's model: what the engine says the plan is, and the few
// facts the window keeps for itself — where it is looking, what is picked,
// which tool is in the hand, which beat is showing.
//
// **The engine is the truth.** Everything here about the plan is a reading of
// the engine's last answer (`engine/src/diagram/wire.rs`), replaced whole when
// the next one arrives. An edit goes engine-ward as an op and the plan comes
// back; a drag asks the engine what the plan *would* look like and paints
// that, writing nothing until the hand lets go.

// MARK: - what the engine sends

/// **One step a thing takes** (his ruling, 2026-10-01): every Move or Turn
/// is the next step, lettered as it comes, played on the beat it is put on
/// — nought is none (`engine/src/diagram/mod.rs`, `Step`).
struct DiagramStep: Decodable, Equatable {
    var x: Double
    var y: Double
    var rot: Double
    var beat: Int
    var pose: String = ""
    var turn: Bool = false
}

/// A step as the plan shows it, in letter order — the thing itself (`home`)
/// among them. The engine works these out (`seq`), letters and all.
struct DiagramSpot: Decodable, Equatable {
    var letter: String
    var x: Double
    var y: Double
    var rot: Double
    var beat: Int
    var pose: String
    var turn: Bool
    var home: Bool
}

/// One element, every field present (the engine sends them all).
/// A picture the film already holds — a scene's attachment, a shot's frame, a
/// location's or a board's photograph — offered to the plan.
struct DiagramProjectPicture: Identifiable, Hashable {
    var hash: String
    var filename: String
    var width: Int
    var height: Int
    var id: String { hash }
    var ext: String {
        let parts = filename.split(separator: ".")
        return parts.count > 1 ? String(parts.last!) : "png"
    }
}

struct DiagramEl: Decodable, Identifiable, Equatable {
    var id: String
    var kind: String
    var x: Double, y: Double, x2: Double, y2: Double, rot: Double
    var w: Double, h: Double, curve: Double, thick: Double
    var weight: Double, opacity: Double
    var lens: Double, reach: Double, kelvin: Double, beam: Double, swing: Double, size: Double
    var lanes: Double
    var label: String, color: String, dash: String, group: String, note: String, sym: String
    var shot: String, sensor: String, height: String, rig: String, cast: String, pose: String
    /// For a camera with no shot: which film camera (a unit id), and a lens
    /// off the film's Lens list.
    var unit: String?
    var lens_name: String?
    var role: String, hinge: String, text: String, align: String, head: String, marking: String
    var media: String
    /// The piece this one keeps facing, by id — empty when turned by hand.
    var aim: String
    /// The piece this one rides — a lamp on its stand — by id (`rigging.rs`).
    var rig_on: String?
    /// An arrow's ends, pinned to pieces by id (`settle_arrows`); empty is free.
    var start_on: String?, end_on: String?
    /// A light's dimmer, 0–100.
    var dim: Double?
    /// Gels on a light or in a frame; a frame's skin, pipe, egg crate, lean
    /// and height (`DiagramFrame.swift`).
    var gels: [String]
    var material: String, pipe: String
    var grid: Double, tilt: Double, tall: Double
    /// Its name, moved and styled; a camera's frame laid on the plan
    /// (`DiagramNames.swift`).
    var label_dx: Double?, label_dy: Double?, label_size: Double?
    var label_bold: Bool?, label_hidden: Bool?
    var frame_on: Bool?, frame_dx: Double?, frame_dy: Double?, frame_w: Double?
    /// A group's name, carried by each member ("Group 2" until renamed).
    var group_name: String?
    var fill: Bool, locked: Bool, hidden: Bool, cone: Bool
    var beam_on: Bool, flip: Bool, bold: Bool, walks: Bool
    /// A door that slides along its wall (`swing` then says how far open).
    var slide: Bool?
    /// Two leaves or panels meeting in the middle, and a door that slides
    /// into the wall (`El::door_style`, 2026-10-17).
    var pair: Bool?
    var pocket: Bool?
    var points: [[Double]]
    /// A wall that runs back to its first corner, and its rounded corners
    /// (`walls.rs`).
    var closed: Bool?
    var round: [Int]?
    /// Smooth points: per corner `[in_dx, in_dy, out_dx, out_dy]`, offsets
    /// from the corner (`walls.rs`). A drawn path always has them.
    var handles: [[Double]]?
    /// What a closed path or room is filled with — `#rrggbb`, `auto`, or empty —
    /// and how firm (0 is its own).
    var fill_color: String?
    var fill_alpha: Double?
    /// Its other steps, the first `lead` of them before the thing itself;
    /// `beat` is the thing's own beat.
    var steps: [DiagramStep]
    var lead: Int
    var beat: Int
    /// Every step in letter order, the thing among them — sent only when it
    /// has other steps.
    var seq: [DiagramSpot]?
    // Worked out for a camera (`render::camera_optics`): its film camera,
    // lens and zoom, the gate it reads and the squeeze it sees through.
    var cam_unit: String?, cam_unit_label: String?
    var sensor_set: Bool?
    var lens_text: String?
    var zoom: [Double]?
    var focal: Double?
    var aov: Double?
    var name: String?
    var gate: String?, gate_name: String?
    var gate_w: Double?, gate_h: Double?
    var squeeze_used: Double?
    /// A lighting plot's facts: how many units, the location's own light,
    /// and what is done to it (`off`, `swap`, `dim`, or empty).
    var count: Double?, existing: Bool?, action: String?
    /// A lamp's mark as he picked it, and as the plot draws it now
    /// (`chevron|added|open`).
    var mark: String?, mark_ink: String?, mark_fill: String?, look: String?
    /// The shared label this lamp is named on; drawn underneath everything.
    var tie_to: String?, under: Bool?, practical: Bool?
    /// A string of lamps: `line` or `ring`; nil is one lamp at one spot.
    var spread: String?
    /// What a shared label shows when he has typed nothing on it.
    var shown: String?
    /// How big it is drawn, metres across and down in its own turn, where
    /// that is more than its footprint (`render::drawn_size`, Ref 1511): a
    /// lamp's mark, a camera, Words. A pick is outlined round it.
    var drawn: [Double]?
    /// **A lamp outlined by its mark alone** (`lampscale::hugs`, 2026-10-17):
    /// its pick, handles and a corner drag go round the mark, and a drag
    /// sizes the mark — `mark_k`, times its page size.
    var hug: Bool?, mark_k: Double?
    /// **Name and Note**: a lamp's Name — its label as typed (his call,
    /// 2026-10-15), none until then — and the two lines its label writes:
    /// "4× 4' Titan Tube", "Uplight on BG · ½ CTO".
    var lamp_name: String?
    /// Its legend line: its look and its Name (`plot::entry_key`).
    var legend_key: String?
    /// A frame's Name as typed (2026-10-05); its Note is its `label`.
    var title: String?
    /// Any other piece's Note, under its name (2026-10-05).
    var caption: String?
    /// A picture's own marks and its perspective helper (2026-10-15,
    /// `photomarks`): fractions of the picture.
    var marks: String?
    var perspective: String?
    var label_lines: [String]?
    /// **Set or Plot** (Ref 1498): the layer the engine puts it in, by its
    /// kind (`diagram::layer`) — never stored.
    var layer: String?

    var isLine: Bool { ["wall", "track", "road", "measure", "arrow"].contains(kind) }
    var isPolyline: Bool { ["cable", "stroke"].contains(kind) }
    /// Takes moves, steps and beats. **Not on the lighting plot** (his call,
    /// 2026-10-03: camera and actor moves are cut). A film's moves stay in
    /// it; only the plot leaves them out.
    var moves: Bool { false }

    /// Its steps in letter order, the thing itself among them.
    var spots: [DiagramSpot] {
        seq ?? [DiagramSpot(letter: "A", x: x, y: y, rot: rot, beat: beat, pose: pose, turn: false, home: true)]
    }
    /// Where the thing itself sits among its steps.
    var homeIndex: Int { min(lead, steps.count) }
    /// It takes more than one step.
    var hasSteps: Bool { !steps.isEmpty }

    /// The step it is on at a beat — the engine's `step_at`: the latest
    /// beat up to this one; before its first, the step that beat has.
    func step(at beat: Int) -> Int {
        let on = spots.enumerated().filter { $0.element.beat > 0 }
        if let i = on.filter({ $0.element.beat <= beat }).max(by: { $0.element.beat < $1.element.beat }) { return i.offset }
        if let i = on.min(by: { $0.element.beat < $1.element.beat }) { return i.offset }
        return homeIndex
    }

    /// Where it stands at a beat.
    func at(beat: Int) -> (x: Double, y: Double, rot: Double) {
        guard hasSteps else { return (x, y, rot) }
        let p = spots[step(at: beat)]
        return (p.x, p.y, p.rot)
    }

    func hasBeat(_ beat: Int) -> Bool { beat <= 1 || spots.contains { $0.beat == beat } }

    /// How a person is at a beat — the engine's `pose_at`.
    func pose(at beat: Int) -> String {
        guard hasSteps else { return pose }
        let on = spots.filter { $0.beat > 0 }.sorted { $0.beat < $1.beat }
        let upto = max(spots[step(at: beat)].beat, on.first?.beat ?? 0)
        var now = pose
        for p in on where p.beat <= upto && !p.pose.isEmpty { now = p.pose }
        return now
    }

    /// Its footprint at a beat, as drawn — the engine's `footprint`.
    func footprint(at beat: Int) -> (Double, Double) {
        kind == "cast" && pose(at: beat) == "lying" ? (h * 3.8, h) : (w, h)
    }

    // ---- a wall: one line with corners (`walls.rs`)

    var isWall: Bool { kind == "wall" }
    /// **The Ruler** (the `measure` kind): a line through markers, each free
    /// or locked to a piece by id (`pins`, one per corner; `settle_rulers`).
    var isRuler: Bool { kind == "measure" }
    var pins: [String]?
    /// Marker i's lock, or nil when it was placed by hand.
    func lock(_ i: Int) -> String? {
        guard let p = pins, i < p.count, !p[i].isEmpty else { return nil }
        return p[i]
    }
    /// Its corners in order — the engine's `walls::corners`.
    var corners: [CGPoint] {
        if points.count >= 2 { return points.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } }
        return [CGPoint(x: x, y: y), CGPoint(x: x2, y: y2)]
    }
    var isClosed: Bool { (closed ?? false) && corners.count >= 3 }
    /// Whether a closed path or room is filled.
    var isFilled: Bool {
        guard isClosed else { return false }
        let hex = (fill_color ?? "").hasPrefix("#")
        return isWall ? (hex || fill_color == "auto") : (hex || fill)
    }
    /// A path made with the Draw tool: a stroke whose corners are exact and may be smooth.
    var isPath: Bool { kind == "stroke" && !(handles ?? []).isEmpty }
    /// Corner `i`'s two handles, as offsets from it.
    func handle(_ i: Int) -> (inn: CGVector, out: CGVector) {
        guard let h = handles, i >= 0, i < h.count, h[i].count >= 4 else { return (.zero, .zero) }
        return (CGVector(dx: h[i][0], dy: h[i][1]), CGVector(dx: h[i][2], dy: h[i][3]))
    }
    /// Whether corner `i` is smooth — has a handle out.
    func isSmooth(_ i: Int) -> Bool {
        let h = handle(i)
        return abs(h.inn.dx) + abs(h.inn.dy) + abs(h.out.dx) + abs(h.out.dy) > 1e-9
    }
    /// Stretch `i` as a curve, when a handle at either end bends it.
    func stretchCubic(_ i: Int) -> (CGPoint, CGPoint, CGPoint, CGPoint)? {
        let c = corners
        guard c.count >= 2, i >= 0, i < (isClosed ? c.count : c.count - 1) else { return nil }
        let j = (i + 1) % c.count
        let (a, b) = (handle(i), handle(j))
        guard abs(a.out.dx) + abs(a.out.dy) + abs(b.inn.dx) + abs(b.inn.dy) > 1e-9 else { return nil }
        return (c[i], CGPoint(x: c[i].x + a.out.dx, y: c[i].y + a.out.dy),
                CGPoint(x: c[j].x + b.inn.dx, y: c[j].y + b.inn.dy), c[j])
    }
    static func cubic(_ p: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let (w0, w1, w2, w3) = (u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t)
        return CGPoint(x: w0 * p.0.x + w1 * p.1.x + w2 * p.2.x + w3 * p.3.x,
                       y: w0 * p.0.y + w1 * p.1.y + w2 * p.2.y + w3 * p.3.y)
    }
    /// The centre line through the curves, for a wall or path with smooth points.
    private var curvedRun: [CGPoint] {
        let c = corners
        let n = isClosed ? c.count : c.count - 1
        var out: [CGPoint] = []
        for i in 0..<max(n, 0) {
            out.append(c[i])
            if let cub = stretchCubic(i) { for k in 1..<24 { out.append(DiagramEl.cubic(cub, CGFloat(k) / 24)) } }
        }
        out.append(isClosed ? c[0] : c[c.count - 1])
        return out
    }
    /// Each stretch, corner to corner.
    var stretches: [(CGPoint, CGPoint)] {
        let c = corners
        let n = isClosed ? c.count : c.count - 1
        guard n > 0 else { return [] }
        return (0..<n).map { (c[$0], c[($0 + 1) % c.count]) }
    }
    /// The centre line as drawn — the engine's `walls::run`: a rounded corner
    /// a curve, a closed wall back to where it began.
    var run: [CGPoint] {
        if isWall || isPath, (0..<corners.count).contains(where: isSmooth) { return curvedRun }
        let c = corners
        let n = c.count
        if !isWall || (n == 2 && !(closed ?? false)) {
            guard abs(curve) > 1e-6, n == 2 else { return c }
            let (a, b) = (c[0], c[1])
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
            let (nx, ny) = (-(b.y - a.y) / len, (b.x - a.x) / len)
            let ctl = CGPoint(x: (a.x + b.x) / 2 + nx * curve * 2, y: (a.y + b.y) / 2 + ny * curve * 2)
            return (0...24).map { i in
                let t = CGFloat(i) / 24, u = 1 - t
                return CGPoint(x: u * u * a.x + 2 * u * t * ctl.x + t * t * b.x, y: u * u * a.y + 2 * u * t * ctl.y + t * t * b.y)
            }
        }
        let shut = isClosed
        let rounds = Set(round ?? [])
        var out: [CGPoint] = []
        func push(_ p: CGPoint) { if out.last.map({ hypot($0.x - p.x, $0.y - p.y) > 1e-9 }) ?? true { out.append(p) } }
        func rounded(_ a: CGPoint, _ at: CGPoint, _ b: CGPoint) {
            let s = CGPoint(x: (a.x + at.x) / 2, y: (a.y + at.y) / 2), e = CGPoint(x: (at.x + b.x) / 2, y: (at.y + b.y) / 2)
            for k in 0...12 {
                let t = CGFloat(k) / 12, u = 1 - t
                push(CGPoint(x: u * u * s.x + 2 * u * t * at.x + t * t * e.x, y: u * u * s.y + 2 * u * t * at.y + t * t * e.y))
            }
        }
        if !shut {
            push(c[0])
            for i in 1..<max(n - 1, 1) where i < n - 1 {
                if rounds.contains(i) { rounded(c[i - 1], c[i], c[i + 1]) } else { push(c[i]) }
            }
            push(c[n - 1])
        } else {
            for i in 0..<n {
                if rounds.contains(i) { rounded(c[(i + n - 1) % n], c[i], c[(i + 1) % n]) } else { push(c[i]) }
            }
            if let f = out.first { out.append(f) }
        }
        return out
    }
}

struct DiagramSun: Decodable, Equatable {
    var azimuth: Double?
    var altitude: Double?
    var minutes: Double?
    var why: String?
    /// The day's sun, in minutes after local midnight.
    var rise: Double?
    var set: Double?
    var noon: Double?
    var goldenMorning: Double?
    var goldenEvening: Double?
    /// Where its disc stands on the plan, when it is drawn.
    var x: Double?, y: Double?
}

struct DiagramSettings: Decodable, Equatable {
    var units: String = "ft"
    var grid: Bool = true
    var snap: Bool = true
    var dims: Bool = true
    /// Every wall's lengths, not only the picked wall's (View › Wall Lengths).
    var all_lengths: Bool = false
    /// A sketch over a picture: no grid, scale, lengths or sun.
    var sketch: Bool = false
    var cones: Bool = true
    var beams: Bool = true
    var labels: Bool = true
    var step: Double = 0.3048
    var north: Double = 0
    var sun: Bool = false
    var sun_rays: Bool = false
    /// `plot` (the default) or `picture`: how lights are drawn.
    var style: String = "plot"
    /// The plot's colours he set, by category (`Settings::colours`).
    var colours: [String: String] = [:]
    var sun_date: String = ""
    var sun_time: String = ""
    // Light levels (`DiagramLevels.swift`)
    var levels: Bool = false
    var light_units: String = "stops"
    var iso: Double = 800
    var shutter: Double = 48
    var stop: Double = 2.8
    var ambient: Double = 0
    var sun_lux: Double = 0
    // The sheet (Back to Paper, Batch 2, `DiagramPage.swift`): its paper
    // and way round, whether the Legend and the Notes block print, his
    // Sheet Notes, and the scale bar (off unless asked, his call G).
    var paper: String = "letter"
    var orientation: String = "landscape"
    var legend: Bool = true
    var notes: Bool = true
    var sheet_notes: String = ""
    var scale_bar: Bool = false
    /// A frame's cloth on the plan (View › Frame Fabric). On.
    var fabric: Bool = true
    /// View › Measurements: the rulers he laid, on screen and on paper.
    var measures: Bool = true
    /// **Labels as typed** (2026-10-17): All Caps draws them in capitals;
    /// Counts adds "3×" and "×2"; Show Unlabeled gives the legend its faint
    /// line. All off by default.
    var caps: Bool = false
    var counts: Bool = false
    var unlabeled: Bool = false

    enum CodingKeys: String, CodingKey { case units, grid, snap, dims, all_lengths, sketch, cones, beams, labels, step, north, sun, sun_rays, style, colours, sun_date, sun_time,
                                              levels, light_units, iso, shutter, stop, ambient, sun_lux,
                                              paper, orientation, legend, notes, sheet_notes, scale_bar, fabric, measures, caps, counts, unlabeled }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = try c.decodeIfPresent(String.self, forKey: .units) ?? "ft"
        grid = try c.decodeIfPresent(Bool.self, forKey: .grid) ?? true
        snap = try c.decodeIfPresent(Bool.self, forKey: .snap) ?? true
        dims = try c.decodeIfPresent(Bool.self, forKey: .dims) ?? true
        all_lengths = try c.decodeIfPresent(Bool.self, forKey: .all_lengths) ?? false
        sketch = try c.decodeIfPresent(Bool.self, forKey: .sketch) ?? false
        cones = try c.decodeIfPresent(Bool.self, forKey: .cones) ?? true
        beams = try c.decodeIfPresent(Bool.self, forKey: .beams) ?? true
        labels = try c.decodeIfPresent(Bool.self, forKey: .labels) ?? true
        step = try c.decodeIfPresent(Double.self, forKey: .step) ?? 0.3048
        north = try c.decodeIfPresent(Double.self, forKey: .north) ?? 0
        sun = try c.decodeIfPresent(Bool.self, forKey: .sun) ?? false
        sun_rays = try c.decodeIfPresent(Bool.self, forKey: .sun_rays) ?? false
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "plot"
        colours = try c.decodeIfPresent([String: String].self, forKey: .colours) ?? [:]
        sun_date = try c.decodeIfPresent(String.self, forKey: .sun_date) ?? ""
        sun_time = try c.decodeIfPresent(String.self, forKey: .sun_time) ?? ""
        levels = try c.decodeIfPresent(Bool.self, forKey: .levels) ?? false
        light_units = try c.decodeIfPresent(String.self, forKey: .light_units) ?? "stops"
        iso = try c.decodeIfPresent(Double.self, forKey: .iso) ?? 800
        shutter = try c.decodeIfPresent(Double.self, forKey: .shutter) ?? 48
        stop = try c.decodeIfPresent(Double.self, forKey: .stop) ?? 2.8
        ambient = try c.decodeIfPresent(Double.self, forKey: .ambient) ?? 0
        sun_lux = try c.decodeIfPresent(Double.self, forKey: .sun_lux) ?? 0
        paper = try c.decodeIfPresent(String.self, forKey: .paper) ?? "letter"
        orientation = try c.decodeIfPresent(String.self, forKey: .orientation) ?? "landscape"
        legend = try c.decodeIfPresent(Bool.self, forKey: .legend) ?? true
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? true
        sheet_notes = try c.decodeIfPresent(String.self, forKey: .sheet_notes) ?? ""
        scale_bar = try c.decodeIfPresent(Bool.self, forKey: .scale_bar) ?? false
        fabric = try c.decodeIfPresent(Bool.self, forKey: .fabric) ?? true
        measures = try c.decodeIfPresent(Bool.self, forKey: .measures) ?? true
        caps = try c.decodeIfPresent(Bool.self, forKey: .caps) ?? false
        counts = try c.decodeIfPresent(Bool.self, forKey: .counts) ?? false
        unlabeled = try c.decodeIfPresent(Bool.self, forKey: .unlabeled) ?? false
    }
}

/// One shape to paint. The engine's `Shape`, as it travels.
struct DiagramShape: Decodable {
    var e: String?
    var p: String
    var k: String
    var d: [Double]?
    var x: Double?, y: Double?
    var tx: String?
    var sz: Double?
    var an: String?
    var b: Bool?
    var r: Double?
    var fx: Bool?
    var h: Bool?
    var on: String?
    var m: String?
    var iw: Double?, ih: Double?
    var f: String?
    var s: String?
    var w: Double?
    var da: String?
    var a: Double?
    var fd: [Double]?
    /// A piece's name sits on a patch of paper (`render::place_names`).
    var pa: Bool?
    /// The ink of every line of words after the first — a callout's second
    /// line (its note, gels, Off) in grey. Absent, they all take `f`.
    var f2: String?
    /// How many lines lead in `f` before `f2` takes over: a Name typed on
    /// several lines (2026-10-17). Absent, one.
    var n1: Int?
    /// How far the plan moved a name off its spot under its piece to keep it
    /// clear, metres on the page — where a drag of it starts from.
    var nx: Double?, ny: Double?
}

struct DiagramPlan: Decodable {
    var els: [DiagramEl]
    var settings: DiagramSettings
    var roomFrom: String
    var lastBeat: Int
    var extent: [Double]?
    var shapes: [DiagramShape]
    var sun: DiagramSun?
    var sceneDate: String?
    /// The sheet's legend (Labs): each kind of lamp and its mark, and each
    /// colour in use and what it means.
    var legend: [DiagramLegendRow]?
    var legendColours: [DiagramLegendColour]?

    static let empty = DiagramPlan(els: [], settings: DiagramSettings(), roomFrom: "",
                                   lastBeat: 1, extent: nil, shapes: [], sun: nil, sceneDate: nil, legend: nil, legendColours: nil)
}

/// A colour in use on the sheet and what it means (`plot::colour_rows`).
struct DiagramLegendColour: Decodable, Identifiable, Equatable {
    var role: String
    var name: String
    var named: Bool
    var id: String { role }
}

/// One kind of lamp on the sheet, as the engine marks it (`plot::legend`).
struct DiagramLegendRow: Decodable, Identifiable, Equatable {
    /// The mark as one word, `chevron|added|open` (`plot::look_key`).
    var key: String
    /// What it stands for; empty until named or its lamps share a unit.
    var name: String
    var mark: String
    var ink: String
    var solid: Bool
    var count: Double
    /// He named it himself.
    var named: Bool
    var id: String { key }
}

struct DiagramSymbol: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var group: String
    var light: Bool
    var w: Double
    var h: Double
    var beam: Double
    var reach: Double
    var kelvin: Double
    /// Which library shows it (`light`, `grip`, `set`), its section there,
    /// who makes it, and the words a crew calls it by — the engine's
    /// `library.rs`.
    var lib: String = ""
    var kind: String = ""
    var maker: String = ""
    var aka: String = ""

    private enum CodingKeys: String, CodingKey { case id, name, group, light, w, h, beam, reach, kelvin, lib, kind, maker, aka }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        group = try c.decode(String.self, forKey: .group)
        light = try c.decode(Bool.self, forKey: .light)
        w = try c.decode(Double.self, forKey: .w)
        h = try c.decode(Double.self, forKey: .h)
        beam = try c.decode(Double.self, forKey: .beam)
        reach = try c.decode(Double.self, forKey: .reach)
        kelvin = try c.decode(Double.self, forKey: .kelvin)
        lib = try c.decodeIfPresent(String.self, forKey: .lib) ?? (light ? "light" : "set")
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? group
        maker = try c.decodeIfPresent(String.self, forKey: .maker) ?? ""
        aka = try c.decodeIfPresent(String.self, forKey: .aka) ?? ""
    }

    /// Answers to what was typed: every word found in its name, section,
    /// maker or nicknames — the engine's `library::matches`.
    func matches(_ query: String) -> Bool {
        let hay = [name, group, kind, maker, aka].joined(separator: " ").lowercased()
        return query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { hay.contains($0) }
    }
}

/// A frame's choices, as the engine lists them (`frame.rs`).
struct DiagramFrameChoices: Decodable {
    struct Material: Decodable, Identifiable, Hashable {
        var id: String, name: String, group: String, fill: String, alt: String, edge: String
    }
    struct Pipe: Decodable, Identifiable, Hashable { var id: String, name: String }
    var `default`: String
    var materials: [Material]
    var pipes: [Pipe]
    var grids: [Double]
}

struct DiagramSensor: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var width: Double
}

/// A body a camera can show, from the pack (`symbols::camera_bodies`).
struct DiagramBody: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
}

struct DiagramLibrary: Decodable {
    var symbols: [DiagramSymbol]
    var sensors: [DiagramSensor]
    var cameras: [DiagramBody]?
    var camera_default: String?
    var frames: DiagramFrameChoices?
    /// Each library's sections, in order, by library.
    var kinds: [String: [String]]?
}

// MARK: - the engine's diagram commands

extension Engine {
    /// The plan's zoom, points to the metre, as the engine is told it: names
    /// are kept apart at the size they are drawn (`render::place_names`).
    static var diagramZoom: Double = 60 / nameShrink(60)
    /// …and the zoom the shapes on screen were last worked out at.
    static var diagramZoomDrawn: Double = 60 / nameShrink(60)

    /// **Names give way as the plan gets small** (his note, 2026-10-01:
    /// *"when i zoom out — text should not take over like this — should be
    /// the opposite"*). At 100% and closer a name is its own size; zoomed
    /// out past 100% it shrinks with the plan, so the plan looks as it does
    /// at 100%, only smaller — nothing reshuffles — and once a name would
    /// be under 3 points it is not drawn at all. The engine is told the
    /// zoom the names are drawn at (60 points to the metre, all the way
    /// out), so it keeps them apart at the size they are.
    static let namesFullAt = 60.0
    static func nameShrink(_ ppm: Double) -> Double {
        ppm >= namesFullAt || ppm <= 0 ? 1 : ppm / namesFullAt
    }
    static func namesAt() -> String {
        diagramZoomDrawn = diagramZoom
        return zoomArgs + (diagramTyping.isEmpty ? "" : "\ttyping=" + diagramTyping)
    }
    /// **The plan lettered as its page letters it** (Ref 1511): with the
    /// sheet on screen, the zoom the engine is told is the page's, and its
    /// names, words and marks are drawn at the sheet's sizes for a plan
    /// shrunk that far (`render::lettering`) — so the screen shows what
    /// prints, a backyard's words as small against it as a room's.
    static var diagramPage = false
    /// The zoom and lettering, as every plan call and a click's hit test
    /// ask for them.
    static var zoomArgs: String {
        String(format: "ppm=%.2f", diagramZoom) + (diagramPage ? "\tpage=1" : "")
    }
    /// **The piece whose words are being typed on the plan** (fix round 2):
    /// the engine draws its name even when he hid it, so the cursor stands
    /// where the words go — and they stay hidden when he is done.
    static var diagramTyping = ""

    func diagram(scene: String, beat: Int, selected: [String], tween: Double = 0) -> DiagramPlan? {
        decodeDiagram(call("diagram", scene, "beat=\(beat)", "sel=\(selected.joined(separator: ","))", Engine.namesAt(),
                           "tween=\(tween)", "tz=\(TimeZone.current.secondsFromGMT() / 60)"))
    }

    /// One edit, one undo. Returns the ids it made and the plan after it.
    /// `join`: one step of undo with the edit before it — the same gesture.
    func diagramEdit(scene: String, op: [String: Any], beat: Int,
                     selected: [String], join: Bool = false) -> (made: [String], plan: DiagramPlan?)? {
        guard let json = DiagramOps.encode(op) else { return nil }
        let data = call("diagramedit", scene, json, "beat=\(beat)", "sel=\(selected.joined(separator: ","))",
                        "join=\(join ? 1 : 0)", Engine.namesAt(), "tz=\(TimeZone.current.secondsFromGMT() / 60)")
        struct Reply: Decodable { var made: [String]; var diagram: DiagramPlan }
        do {
            let r = try JSONDecoder().decode(Reply.self, from: data)
            return (r.made, r.diagram)
        } catch {
            Engine.complain(data, error)
            return nil
        }
    }

    /// What an edit *would* draw, written nowhere.
    func diagramPreview(scene: String, op: [String: Any], beat: Int,
                        selected: [String]) -> DiagramPlan? {
        guard let json = DiagramOps.encode(op) else { return nil }
        let data = call("diagrampreview", scene, json, "beat=\(beat)", "sel=\(selected.joined(separator: ","))", Engine.namesAt(),
                        "tz=\(TimeZone.current.secondsFromGMT() / 60)")
        return try? JSONDecoder().decode(DiagramPlan.self, from: data)
    }

    /// Who the cast tool offers: the scene's characters, then the rest of the film's.
    func diagramCast(scene: String) -> (scene: [String], film: [String]) {
        struct Reply: Decodable { var scene: [String]; var film: [String] }
        guard let r = try? JSONDecoder().decode(Reply.self, from: call("diagramcast", scene)) else { return ([], []) }
        return (r.scene, r.film)
    }

    func diagramHit(scene: String, x: Double, y: Double, tolerance: Double, beat: Int, skip: Set<String> = []) -> String? {
        struct Reply: Decodable { var id: String? }
        let data = call("diagramhit", scene, String(x), String(y), String(tolerance), "beat=\(beat)", Engine.zoomArgs,
                        "skip=\(skip.joined(separator: ","))")
        return (try? JSONDecoder().decode(Reply.self, from: data))?.id
    }

    func diagramWithin(scene: String, _ r: CGRect) -> [String] {
        struct Reply: Decodable { var ids: [String] }
        let data = call("diagramwithin", scene, String(Double(r.minX)), String(Double(r.minY)),
                        String(Double(r.maxX)), String(Double(r.maxY)))
        return (try? JSONDecoder().decode(Reply.self, from: data))?.ids ?? []
    }

    /// `step`: the grid as it is drawn now, which follows the zoom.
    /// `own`: a wall's corner being dragged or drawn — never its own target.
    /// `guides`: the lines on the plan a corner lined up along.
    func diagramSnap(scene: String, x: Double, y: Double, reach: Double,
                     skip: [String], step: Double = 0, own: (String, Int)? = nil)
        -> (x: Double, y: Double, caught: Bool, guides: [[CGPoint]]) {
        struct Reply: Decodable { var x: Double; var y: Double; var caught: Bool; var guides: [[Double]]? }
        var args: [String] = ["diagramsnap", scene, String(x), String(y), String(reach)]
        args.append("skip=" + skip.joined(separator: ","))
        args.append("step=\(step)")
        if let own { args.append("own=\(own.0):\(own.1)") }
        let data = call(args)
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else { return (x, y, false, []) }
        var lines: [[CGPoint]] = []
        for g in r.guides ?? [] where g.count == 4 {
            lines.append([CGPoint(x: g[0], y: g[1]), CGPoint(x: g[2], y: g[3])])
        }
        return (r.x, r.y, r.caught, lines)
    }

    /// Where a door, window or opening lands in a wall. With its width and
    /// a step, slid so its near edge is a whole number of steps from the
    /// nearer corner: `from` that distance, `face`→`edge` where it runs.
    struct InWall { var x: Double; var y: Double; var rot: Double; var thick: Double
        var from: Double?; var face: CGPoint?; var edge: CGPoint? }

    func diagramWall(scene: String, x: Double, y: Double, reach: Double, width: Double = 0, step: Double = 0) -> InWall? {
        struct Reply: Decodable { var x: Double?; var y: Double?; var rot: Double?; var thick: Double?
            var from: Double?; var fx: Double?; var fy: Double?; var ex: Double?; var ey: Double? }
        let data = call("diagramwall", scene, String(x), String(y), String(reach), "w=\(width)", "step=\(step)")
        guard let r = try? JSONDecoder().decode(Reply.self, from: data),
              let x = r.x, let y = r.y, let rot = r.rot, let thick = r.thick else { return nil }
        let face = r.fx.flatMap { fx in r.fy.map { CGPoint(x: fx, y: $0) } }
        let edge = r.ex.flatMap { ex in r.ey.map { CGPoint(x: ex, y: $0) } }
        return InWall(x: x, y: y, rot: rot, thick: thick, from: r.from, face: face, edge: edge)
    }

    func diagramLibrary() -> DiagramLibrary? {
        try? JSONDecoder().decode(DiagramLibrary.self, from: call("diagramlibrary"))
    }

    func diagramRoom(scene: String, location: String, path: String) -> Bool {
        struct Reply: Decodable { var made: Int }
        let data = call("diagramroom", scene, location, path)
        return ((try? JSONDecoder().decode(Reply.self, from: data))?.made ?? 0) > 0
    }

    func diagramCopy(scene: String, from: String) -> Int {
        struct Reply: Decodable { var copied: Int }
        let data = call("diagramcopy", scene, from)
        return (try? JSONDecoder().decode(Reply.self, from: data))?.copied ?? 0
    }

    func diagramSVG(scene: String, width: Int, paper: Bool, beat: Int) -> String? {
        struct Reply: Decodable { var svg: String }
        let data = call("diagramsvg", scene, "width=\(width)", "paper=\(paper ? 1 : 0)", "beat=\(beat)")
        return (try? JSONDecoder().decode(Reply.self, from: data))?.svg
    }

    fileprivate func decodeDiagram(_ data: Data) -> DiagramPlan? {
        guard !data.isEmpty else { return nil }
        do { return try JSONDecoder().decode(DiagramPlan.self, from: data) }
        catch { Engine.complain(data, error); return nil }
    }

    fileprivate static func complain(_ data: Data, _ error: Error) {
        let text = String(data: data.prefix(600), encoding: .utf8) ?? ""
        FileHandle.standardError.write(Data("diagram: \(error) — \(text)\n".utf8))
    }
}

/// Edits as the engine reads them (`diagram::apply`).
enum DiagramOps {
    static func encode(_ op: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(op),
              let data = try? JSONSerialization.data(withJSONObject: op, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        // The bridge splits on tabs; JSON never needs a raw one.
        return text.replacingOccurrences(of: "\t", with: "\\t")
    }

    static func move(_ ids: [String], dx: Double, dy: Double) -> [String: Any] {
        ["op": "move", "ids": ids, "dx": dx, "dy": dy]
    }
    static func update(_ ids: [String], _ set: [String: Any]) -> [String: Any] {
        ["op": "update", "ids": ids, "set": set]
    }
    static func beat(_ id: String, _ beat: Int, x: Double, y: Double, rot: Double? = nil) -> [String: Any] {
        var o: [String: Any] = ["op": "beat", "id": id, "beat": beat, "x": x, "y": y]
        if let rot { o["rot"] = rot }
        return o
    }
    static func batch(_ ops: [[String: Any]]) -> [String: Any] { ["op": "batch", "ops": ops] }
}

/// One point of a path being drawn: where it is, and its two handles as offsets.
struct PathNode: Equatable {
    var p: CGPoint
    var hin: CGVector = .zero
    var hout: CGVector = .zero
}

// MARK: - door kinds

/// **A door's kind** (his ask, 2026-10-17), as the engine names it
/// (`El::door_style`): set by its word, kept as the switches slide, pair and
/// pocket, so an older sliding door is Sliding.
enum DoorStyle: String, CaseIterable, Identifiable {
    case swing, double, sliding, center, pocket
    var id: String { rawValue }
    var title: String {
        switch self {
        case .swing: return "Swing"
        case .double: return "Double"
        case .sliding: return "Sliding"
        case .center: return "Center"
        case .pocket: return "Pocket"
        }
    }
    /// What the piece is called in the inspector's heading.
    var name: String {
        switch self {
        case .swing: return "Door"
        case .double: return "Double Door"
        case .sliding: return "Sliding Door"
        case .center: return "Center Sliding Door"
        case .pocket: return "Pocket Door"
        }
    }
    var slides: Bool { self == .sliding || self == .center || self == .pocket }
    /// A pair has no one hinge or way to slide: Flip turns it to the other side.
    var paired: Bool { self == .double || self == .center }
    static func of(_ e: DiagramEl) -> DoorStyle {
        switch (e.slide ?? false, e.pair ?? false, e.pocket ?? false) {
        case (false, false, _): return .swing
        case (false, true, _): return .double
        case (true, true, false): return .center
        case (true, _, true): return .pocket
        default: return .sliding
        }
    }
    /// The edit that makes a door this kind. Swinging to sliding keeps it
    /// shut or open as it was.
    func change(_ e: DiagramEl) -> [String: Any] {
        var set: [String: Any] = ["door": rawValue]
        if slides != DoorStyle.of(e).slides, e.swing > 0.5 { set["swing"] = 90 }
        return set
    }
}

// MARK: - the tools

enum DiagramTool: String, CaseIterable, Identifiable {
    case select, hand, camera, cast, light, grip, frame, wall, door, sliding, window, opening, set, track, road
    case text, arrow, connector, measure, shape, pen, cable, note, picture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .hand: return "Move View"
        case .camera: return "Camera"
        case .cast: return "Cast"
        case .light: return "Lamp"
        case .grip: return "Grip"
        case .frame: return "Frame"
        case .wall: return "Wall"
        case .door: return "Door"
        case .sliding: return "Sliding Door"
        case .window: return "Window"
        case .opening: return "Opening"
        case .set: return "Piece"
        case .track: return "Track"
        case .road: return "Street"
        case .text: return "Words"
        case .arrow: return "Arrow"
        case .connector: return "Connector"
        case .measure: return "Ruler"
        case .shape: return "Shape"
        case .pen: return "Draw"
        case .cable: return "Cable"
        case .note: return "Note"
        case .picture: return "Trace"
        }
    }

    /// **Set or Plot** (Ref 1498): the layer a tool makes things in — picked
    /// by its key, it switches the window's layer to match. Select and Move
    /// View work in either, and so does Cast: a person stands in the set and
    /// is aimed at from the plot (his ask, 2026-10-06).
    var layer: String? {
        switch self {
        case .select, .hand, .cast, .text, .arrow, .note: return nil
        case .wall, .door, .sliding, .window, .opening, .set, .road, .picture, .shape: return "set"
        default: return "plot"
        }
    }

    /// The key that picks it, when the plan has the keyboard.
    var key: String {
        switch self {
        case .select: return "v"
        case .hand: return "h"
        case .camera: return "c"
        case .cast: return "p"
        case .light: return "l"
        case .grip: return "q"
        case .frame: return "f"
        case .wall: return "w"
        case .door: return "d"
        case .sliding: return "x"
        case .window: return "i"
        case .opening: return "u"
        case .set: return "s"
        case .track: return "k"
        case .road: return "r"
        case .text: return "t"
        case .arrow: return "a"
        case .connector: return "j"
        case .measure: return "m"
        case .shape: return "o"
        case .pen: return "b"
        case .cable: return "e"
        case .note: return "n"
        case .picture: return "g"
        }
    }

    /// **A row of named tools for each layer** (Back to Paper, design/32
    /// item 10, Set and Plot): Set is Select · Wall, Door, Window, Street,
    /// Piece, Cast, Trace (people stand in the set, 2026-10-06); Plot is Select · Lamp, Frame, Camera · Words, Arrow,
    /// Draw. The rest keep their keys and live under More.
    static func groups(_ layer: String) -> [[DiagramTool]] {
        layer == "set"
            ? [[.select], [.wall, .door, .window, .road, .set, .cast, .picture], [.text, .arrow]]
            : [[.select], [.light, .frame, .camera], [.text, .arrow, .pen]]
    }
    /// Under More: what is used now and then on each layer.
    static func more(_ layer: String) -> [DiagramTool] {
        layer == "set" ? [.shape, .hand] : [.track, .cast, .connector, .measure, .hand]
    }
    static var offered: [DiagramTool] {
        var all: [DiagramTool] = []
        for t in (groups("set") + groups("plot")).flatMap({ $0 }) + more("set") + more("plot") where !all.contains(t) { all.append(t) }
        return all
    }

    /// The tool a key picks. N, the old sticky Note, makes Words now.
    static func forKey(_ ch: String) -> DiagramTool? {
        if ch == DiagramTool.note.key { return .text }
        return offered.first { $0.key == ch }
    }

    /// Picks something from a library before it can place anything.
    var usesLibrary: Bool { self == .set || self == .grip }
    /// The library it opens — what the engine calls each piece's `lib`.
    var library: String { self == .light ? "light" : self == .grip ? "grip" : "set" }
    /// Drawn by dragging from one end to the other.
    var drawsLine: Bool { [.track, .road, .arrow, .connector, .measure].contains(self) }
    /// Draws a line whose ends hold on to the pieces they start and end on.
    var pins: Bool { self == .arrow || self == .connector }
}


// MARK: - the controller

/// The Diagram mode of one window. Holds the engine's last answer, and the
/// window's own facts.
final class DiagramModel: ObservableObject {
    weak var state: ShellState?
    /// A film a newer Shotlister wrote: the plan can be looked at, picked and
    /// played, and nothing on it moves — the engine refuses the edit anyway,
    /// and a drag that springs back reads as a fault.
    var readOnly: Bool { state?.view?.project.readOnly == true }
    /// The canvas, so a checking run can put the mouse on it.
    weak var canvas: NSView?

    @Published private(set) var scene: String?
    @Published private(set) var plan: DiagramPlan = .empty
    /// Painted instead of `plan.shapes` while a drag is in flight.
    /// The plan as it would be mid-drag — drawn, and read for every piece's
    /// place — until the drag lets go and the edit is made.
    @Published var preview: DiagramPlan? {
        didSet { if preview == nil { liveNorth = nil } }
    }
    /// North while it is being turned — the compass held, the slider moving —
    /// so the plan turns under the hand before the turn is kept.
    var liveNorth: Double?

    /// **A group gone into** (his ask, 2026-10-02): double-click a piece in a
    /// group and the group is entered — a click on any of its pieces picks that
    /// piece alone, and a shift-click adds another, until the pick leaves it.
    @Published var enteredGroup: String?

    /// **Set or Plot** (Ref 1498, design/32 item 10): the layer this window
    /// works in — this window's choice, never stored in the film. On Plot the
    /// set is drawn grey and is locked, clicks and drags passing through it;
    /// on Set the plot fades and is locked the same way, and the dots show.
    @Published var layer = "plot" {
        didSet {
            guard layer != oldValue else { return }
            if let l = tool.layer, l != layer { tool = .select }
            let locked = layerLockedIds
            if selection.contains(where: locked.contains) { selection = selection.filter { !locked.contains($0) } }
            canvas?.needsDisplay = true
        }
    }
    /// The pieces of the layer this window is not working in: drawn back,
    /// and passed through by every click, drag and marquee.
    /// A person is never one of them: they stand in the set and are aimed at
    /// from the plot, so they work and show in either (his ask, 2026-10-06).
    var layerLockedIds: Set<String> { Set(plan.els.filter { $0.kind != "cast" && ($0.layer ?? "plot") != layer }.map(\.id)) }

    @Published var selection: [String] = [] {
        didSet {
            // Picked from elsewhere — the Layers list, the legend, a paste —
            // and all of the other layer: the window goes there with it.
            if !selection.isEmpty, selection != oldValue {
                let layers = Set(selection.compactMap { id -> String? in
                    guard let e = el(id), e.kind != "cast" else { return nil }
                    return e.layer ?? "plot"
                })
                if layers.count == 1, let l = layers.first, l != layer { layer = l }
            }
            if let g = enteredGroup, selection.isEmpty || !selection.allSatisfy({ el($0)?.group == g }) { enteredGroup = nil }
            if selection != oldValue {
                // A corner or stretch belongs to the one wall it was picked on.
                if selection.count != 1 || selection.first != oldValue.first || oldValue.count != 1 {
                    pickedCorner = nil
                    pickedStretch = nil
                }
                reloadShapes()
                pickedStep = nil
                // **Details never opens by itself** (Back to Paper, Batch 2)
                // **and, asked for, stays** (his note, 2026-10-17: "the
                // detail panel needs to be easier to pull up"): it follows
                // the pick, says No Selection between picks, and shuts only
                // when he shuts it.
                if let t = typing, !selection.contains(t.el), !t.lamps.contains(where: selection.contains) { endTyping(keep: true) }
                // Something picked brings Details to the front of the right
                // sidebar; nothing picked hands it back to Gear, if open.
                gearFront = selection.isEmpty
            }
        }
    }
    /// **One step of a thing, picked on its own** (his note, 2026-09-28: *"I
    /// should be able to select the second one just like I would the first
    /// one"* — and since 2026-10-01 every step, as many as it has). By its
    /// letter-order index; nil is the thing as it stands now. Its outline
    /// and knob, the arrow keys, Delete and the foot bar all speak about that
    /// step, and the rest stay where they are. A click on the thing picks
    /// it back.
    @Published var pickedStep: Int?
    /// **One corner of the picked wall**, picked on its own: dragged, broken
    /// open, rounded or taken out (master list 3). Nil: the whole wall.
    @Published var pickedCorner: Int?
    /// One stretch of the picked wall, for its length in Details.
    @Published var pickedStretch: Int?
    /// The wall the Wall tool is drawing now, corner by corner.
    var drawingWall: String?
    /// The one picked thing and its step, when a step is picked.
    var stepPick: (e: DiagramEl, i: Int, spot: DiagramSpot)? {
        guard let i = pickedStep, selection.count == 1, let e = el(selection[0]), e.hasSteps, e.spots.indices.contains(i) else { return nil }
        return (e, i, e.spots[i])
    }
    /// Pick one step of a thing.
    func pickStep(_ id: String, _ i: Int) {
        if selection != [id] { selection = [id] }
        pickedStep = i
    }
    /// Take away the picked step, leaving the thing — the step before it is
    /// picked next, so Delete pressed again goes on down the letters.
    func removePickedStep() {
        guard let (e, i, spot) = stepPick, !spot.home else { return }
        edit(["op": "step_remove", "id": e.id, "step": i])
        let left = el(e.id)?.spots.count ?? 1
        pickedStep = left > 1 ? max(0, min(i - 1, left - 1)) : nil
        if let n = pickedStep, el(e.id)?.spots[n].home == true { pickedStep = nil }
    }

    /// How far the foot bar has folded for width (0 everything … 3 the name
    /// alone), for a checking run to read. Not published: the bar sets it.
    var barLevel = 0
    /// A piece being swapped from the right-click menu: the library opens
    /// over the plan for it (design/26).
    @Published var swapping: String?
    /// **How bright the plan's paper is on this Mac's screen** (his ask,
    /// 2026-10-02): 0 dim … 1 white; `defaultBackdrop` is the paper as it was
    /// drawn before. Kept per Mac, like Show by Kind; paper exports keep the
    /// paper.
    @Published var backdrop: Double = UserDefaults.standard.object(forKey: "diagramBackdrop") as? Double ?? DiagramModel.defaultBackdrop {
        didSet { UserDefaults.standard.set(backdrop, forKey: "diagramBackdrop") }
    }
    /// The paper's E4E5E7, as a backdrop setting: its lightness, 0.894, on a
    /// scale from 0.55 (dim; walls still read) to 1 (white).
    static let defaultBackdrop = (0.894 - 0.55) / 0.45
    /// A plan colour lit for the screen's backdrop: the paper and the grid
    /// brighten and dim together, so the grid keeps its step.
    func lit(_ c: NSColor) -> NSColor {
        let k = (0.55 + 0.45 * backdrop) / 0.894
        guard abs(k - 1) > 0.001, let rgb = c.usingColorSpace(.sRGB) else { return c }
        return NSColor(srgbRed: min(rgb.redComponent * k, 1), green: min(rgb.greenComponent * k, 1),
                       blue: min(rgb.blueComponent * k, 1), alpha: rgb.alphaComponent)
    }
    /// The lone picked camera.
    var loneCamera: DiagramEl? {
        guard picked.count == 1, let e = picked.first, e.kind == "camera" else { return nil }
        return e
    }
    /// Whether Details shows down the right. **Only when asked** (Back to
    /// Paper, Batch 2; his Ref 1205: nothing pops up on a click): a
    /// double-click, More › Details… or View › Details. The bar at the foot
    /// steps aside while it is open.
    var detailsShown: Bool {
        detailsOpen && !selection.isEmpty
    }
    /// Details open on the right, picked or not — not while a picture is
    /// drawn on, which has the plan to itself.
    var detailsOpen: Bool { showingDetails && photoEditing == nil && !presenting }
    /// Open or shut Details, the header's button, ⌥⌘I, ⌃⌘2 and More ›
    /// Details… alike.
    func toggleDetails() {
        withAnimation(.easeOut(duration: 0.18)) {
            showingDetails.toggle()
            if showingDetails { gearFront = false }
        }
    }
    /// Details, asked for: the picked piece's exact numbers down the right.
    func openDetails() {
        withAnimation(.easeOut(duration: 0.18)) {
            showingDetails = true
            gearFront = false
        }
    }
    /// The right sidebar's tab — `details` or `gear` — or nil when it is
    /// shut. Details when something is picked; Gear when chosen.
    var rightTab: String? {
        if showingGear && (gearFront || !detailsShown) { return "gear" }
        if detailsOpen || showingGear { return "details" }
        return nil
    }
    /// How much of the canvas's right edge the right sidebar covers: the
    /// toolbar, the foot bar and the zoom centre themselves in what is left.
    var panelCover: CGFloat { rightTab == nil ? 0 : DiagramMode.rightWidth + 2 * DiagramMode.margin }
    /// …and with the sun's panel, which stands in the corner over the zoom,
    /// so the compass can stand clear of both rather than under them.
    var rightCover: CGFloat { panelCover + (showingSun ? 300 + DiagramMode.margin : 0) }
    /// The rail button under the pointer, whose name shows beside it.
    @Published var railHover: DiagramTool?
    @Published var tool: DiagramTool = .select {
        didSet {
            if readOnly, ![.select, .hand].contains(tool) { tool = .select; return }
            if tool != oldValue { armed = nil; armedCast = nil; armedShot = nil; pending.removeAll(); drawNodes.removeAll() }
            // Any tool, by key or by name, takes the window to its layer.
            if let l = tool.layer, l != layer { layer = l }
        }
    }
    /// **The Draw tool's path so far** (his ask, 2026-10-02): a click is a
    /// corner, a drag pulls a smooth curve out of the point.
    @Published var drawNodes: [PathNode] = []
    /// What a finished path is: a plain `line`, a curved `wall`, or an `object`
    /// (a filled shape).
    @Published var drawAs = "line"
    /// Whether a closed path is drawn with a fill (an Object always is).
    @Published var drawFill = false
    /// Who the cast tool puts down next, chosen from its button's menu — a
    /// character's name, or empty for a plain person. `nil`: the plan asks.
    @Published var armedCast: String?
    /// What the camera tool's next camera stands for, chosen from its
    /// button's menu: `new` a new shot, empty no shot, else a shot's id.
    @Published var armedShot: String?
    /// Where each toolbar button stands on the plan, so its menu opens
    /// under it.
    var toolSpots: [String: CGRect] = [:]
    @Published var shapeKind = "rect"
    /// Empty is the plan's own ink, which follows light and dark.
    @Published var penColour = ""
    /// The library entry a set-piece or light tool will place.
    @Published var armed: DiagramSymbol?
    /// The mark the Light tool puts down (`DiagramMarks.Look.key`).
    @Published var armedLook = "chevron|added|open"
    @Published var beat: Int = 1 {
        didSet {
            if beat != oldValue { reloadShapes() }
            if beat > 1, !beatMode { beatMode = true }
        }
    }
    /// **Beats are a mode** (his ruling, 2026-09-28). Outside it the plan
    /// stands at its first beat with every other position drawn at once,
    /// numbered, and a drag moves the thing itself — never a beat he did not
    /// mean to be in. Inside it, the beat bar steps through them and a drag
    /// sets where a thing is at this beat. Going to any beat past the first
    /// enters it; leaving goes back to the first.
    @Published var beatMode = false {
        didSet { if !beatMode, beat != 1 { beat = 1 } }
    }
    /// Part of the way to the next beat, while a move is being played.
    @Published var tween: Double = 0 {
        didSet { if tween != oldValue { reloadShapes() } }
    }
    @Published var library: DiagramLibrary?
    /// The film's nine favorites (`DiagramSpeed.swift`), where their slots
    /// are on the canvas, and the one a dragged piece is over.
    @Published var favorites: [DiagramFavorite?] = []
    var favoriteSlots: [Int: CGRect] = [:]
    @Published var favoriteHover: Int?
    /// **Words being typed on the plan, in the words themselves** (his call
    /// F, 2026-10-04): a Name, a Note, Words, a piece's name. No box, no
    /// Done; clicking away keeps them, Escape leaves them as they were.
    @Published var typing: DiagramTyping? {
        didSet {
            guard typing != oldValue else { return }
            typed = typing?.start
            // A name he hid, or every name with View › Labels off: drawn
            // while it is typed, where it goes, then hidden again.
            let on = typing.flatMap { $0.what == .text || $0.what == .sheet ? nil : $0.el } ?? ""
            if on != Engine.diagramTyping {
                let hidden = [on, Engine.diagramTyping].compactMap(el).contains { $0.label_hidden == true } || !settings.labels
                Engine.diagramTyping = on
                if hidden { reloadShapes() }
            }
            (canvas as? DiagramCanvasView)?.syncTypist()
        }
    }
    /// The words as they are being typed, for the bar to show as they go.
    @Published var typed: String?
    /// Lamps lit up on the plan while something about all of them is open —
    /// the Name list's Name All.
    @Published var glow: [String] = [] {
        didSet { if glow != oldValue { canvas?.needsDisplay = true } }
    }
    @Published var showingSun = false
    /// The View panel, open (`DiagramViewMenu`): it stays open while he clicks in it.
    @Published var viewOpen = false
    /// **View › Storyboard Frames** (Ref 1504, his words: "it should expose
    /// the storyboards if they are enabled on the cameras"): on, each camera
    /// whose own Frame on Plan is on shows its shot's picture on the plan;
    /// off, none do. Each camera keeps its own choice. His view, kept on this
    /// Mac, on until he turns it off.
    @Published var showFrames = UserDefaults.standard.object(forKey: "diagramStoryFrames") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFrames, forKey: "diagramStoryFrames"); canvas?.needsDisplay = true }
    }

    // The view: world metres at the middle of the canvas, and points per metre.
    @Published var centre = CGPoint(x: 2, y: 2)
    @Published var scale: CGFloat = 60 { didSet { zoomedForNames() } }
    var fitted = false
    /// The sheet the plan lies on (`DiagramPage.swift`).
    let pageState = DiagramPageState()

    /// Points drawn so far by a tool that takes several clicks — a chain of
    /// walls, a cable, a pen stroke.
    @Published var pending: [CGPoint] = []

    var engine: Engine? { state?.engine }

    // ---------------------------------------------------------- reading

    func open(scene id: String?) {
        guard id != scene else { return }
        scene = id
        typing = nil
        selection = []
        tween = 0
        beat = 1
        preview = nil
        pending = []
        fitted = false
        reload()
    }

    /// Ask the engine again — after anything that may have changed the plan,
    /// including an undo made anywhere in the program.
    func reload() {
        guard let engine, let scene else { plan = .empty; return }
        if library == nil { library = engine.diagramLibrary() }
        loadFavorites()
        if let fresh = engine.diagram(scene: scene, beat: beat, selected: selection) {
            plan = fresh
            let live = Set(fresh.els.map(\.id))
            let kept = selection.filter { live.contains($0) }
            if kept != selection { selection = kept }
            if pickedStep != nil, stepPick == nil { pickedStep = nil }
            // Undone away, or taken on another device, while being typed in.
            if let t = typing, t.what != .sheet, !live.contains(t.el) { typing = nil }
            if beat > max(fresh.lastBeat, 1) + 1 { beat = max(fresh.lastBeat, 1) }
        }
        preview = nil
        refreshPage()
    }

    func reloadShapes() {
        guard let engine, let scene else { return }
        if let fresh = engine.diagram(scene: scene, beat: beat, selected: selection, tween: tween) {
            plan = fresh
        }
    }

    /// **Names, marks and words at their page size** (Back to Paper, Batch 2:
    /// *what you see is what prints*). With the sheet on screen they are
    /// drawn as the page prints them, grown and shrunk with the page — zoomed
    /// out they never take over, and nothing clear on screen collides on
    /// paper. With no sheet, the old rule (`Engine.nameShrink`).
    var namesShrink: Double {
        if let s = page, s.scale > 0 { return Double(scale) / s.scale }
        return Engine.nameShrink(Double(scale))
    }
    /// The zoom the engine places names and sizes marks at: the page's own.
    var namesZoom: Double {
        if let s = page, s.scale > 0 { return s.scale }
        return Double(scale) / Engine.nameShrink(Double(scale))
    }

    /// **Names are placed for the zoom they are seen at.** A name that fits
    /// under its lamp close in may have to step aside zoomed out, where its
    /// words cover more of the plan; once a zoom settles, the plan is asked
    /// again at the new size.
    private func zoomedForNames() {
        Engine.diagramZoom = namesZoom
        Engine.diagramPage = page != nil
        namesReflow?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard let self, self.preview == nil else { return }
            let drawn = Engine.diagramZoomDrawn
            if abs(Engine.diagramZoom - drawn) / max(drawn, 1) > 0.04 { self.reloadShapes() }
        }
        namesReflow = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: job)
    }
    private var namesReflow: DispatchWorkItem?

    func el(_ id: String) -> DiagramEl? { plan.els.first { $0.id == id } }
    var picked: [DiagramEl] { selection.compactMap(el) }
    /// The plan on screen: mid-drag, as it would be.
    var shown: DiagramPlan { preview ?? plan }
    /// Whether the preview in flight is a setting — the hour, north — the
    /// one kind of change that is meant to move the sun.
    private var previewIsSetting = false
    /// What is painted. **The sun stands still while a piece is hauled** (his
    /// note, 2026-09-28: *"I can chase it with my items"*): mid-drag it stays
    /// where the kept plan has it, and only a setting moves it live.
    var shownShapes: [DiagramShape] {
        guard let p = preview else { return plan.shapes }
        if previewIsSetting { return p.shapes }
        return p.shapes.filter { $0.p != "sun" } + plan.shapes.filter { $0.p == "sun" }
    }
    /// What is picked, where it stands on screen right now.
    var shownPicked: [DiagramEl] { selection.compactMap { id in shown.els.first { $0.id == id } } }

    // ---------------------------------------------------------- writing

    /// One edit, as one step of undo, then the whole program's view model
    /// fetched so the change is saved and every other screen sees it.
    @discardableResult
    func edit(_ op: [String: Any], select: Bool = false, join: Bool = false) -> [String] {
        guard let engine, let scene else { return [] }
        if readOnly { preview = nil; return [] }
        burst = nil
        guard let result = engine.diagramEdit(scene: scene, op: op, beat: beat, selected: selection, join: join) else {
            NSSound.beep()
            reload()
            return []
        }
        if let fresh = result.plan { plan = fresh }
        preview = nil
        if pickedStep != nil, stepPick == nil { pickedStep = nil }
        state?.replace(engine.view())
        if select, !result.made.isEmpty {
            selection = result.made.filter { id in plan.els.contains { $0.id == id } }
        }
        return result.made
    }

    func previewing(_ op: [String: Any]) {
        guard let engine, let scene, !readOnly else { return }
        if let plan = engine.diagramPreview(scene: scene, op: op, beat: beat, selected: selection) {
            previewIsSetting = op["op"] as? String == "settings"
            preview = plan
            if op["op"] as? String == "settings", let north = (op["set"] as? [String: Any])?["north"] as? Double {
                liveNorth = north
            }
        }
    }

    /// **What can go to the other view** (`diagram::can_send`): all but the
    /// room's bones and a person, who is in both already.
    static func canSend(_ e: DiagramEl) -> Bool {
        !["wall", "door", "window", "opening", "road", "cast"].contains(e.kind)
    }

    /// Where Send to goes: the other view from the one these pieces are
    /// in, or from the one shown when they are in both.
    static func otherLayer(_ els: [DiagramEl], _ m: DiagramModel) -> String {
        let now = Set(els.map { $0.layer ?? "plot" })
        let from = now.count == 1 ? now.first! : m.layer
        return from == "set" ? "plot" : "set"
    }

    /// **Send to Set / Send to Plot** (his ask, 2026-10-17): the pieces go to
    /// the other view where they stand — one step of undo. `copy` leaves
    /// them here and sends a copy.
    func sendLayer(_ ids: [String], to: String, copy: Bool) {
        let ids = ids.filter { el($0).map(Self.canSend) ?? false }
        guard !ids.isEmpty, !readOnly else { return }
        edit(["op": "send_layer", "ids": ids, "to": to, "copy": copy])
        if !copy { selection = selection.filter { !ids.contains($0) } }
    }

    func update(_ ids: [String], _ set: [String: Any]) {
        guard !ids.isEmpty else { return }
        edit(DiagramOps.update(ids, set))
    }

    func remove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        edit(["op": "remove", "ids": ids])
        selection.removeAll { ids.contains($0) }
    }

    /// **Duplicate steps on** (Scenario's): the copy lands a step off, and a
    /// copy moved before the next ⌘D teaches the step — the next copy goes
    /// as far again from it, so a row builds itself.
    func duplicate() {
        guard !selection.isEmpty else { return }
        let step = settings.snap ? snapStep : settings.step
        var (dx, dy) = (step, step)
        if let last = lastDuplicate, last.made == selection, let now = extent(selection)?.origin {
            let (ox, oy) = (Double(now.x - last.from.x), Double(now.y - last.from.y))
            if hypot(ox, oy) > 1e-6 { (dx, dy) = (ox, oy) }
        }
        let from = extent(selection)?.origin
        edit(alone(["op": "duplicate", "ids": selection, "dx": dx, "dy": dy]), select: true)
        lastDuplicate = from.map { (made: selection, from: $0) }
    }
    /// The last duplicate's copies, and where what they were copied from stood.
    private var lastDuplicate: (made: [String], from: CGPoint)?

    func order(_ to: String) { if !selection.isEmpty { edit(["op": "order", "ids": selection, "to": to]) } }
    func group() { if selection.count > 1 { edit(["op": "group", "ids": selection]) } }
    /// Every member of a group, by the group's id.
    func members(ofGroup g: String) -> [DiagramEl] { g.isEmpty ? [] : plan.els.filter { $0.group == g } }
    func renameGroup(_ g: String, _ name: String) {
        let ids = members(ofGroup: g).map(\.id)
        let n = name.trimmingCharacters(in: .whitespaces)
        if !ids.isEmpty, !n.isEmpty { update(ids, ["group_name": n]) }
    }
    /// Pieces into a group, or out of every group with `g` empty. A group
    /// left with one piece is no group, and lets it go.
    /// `then` rides in the same undo step — a restack, from a drag in Layers.
    func regroup(_ ids: [String], into g: String, then: [String: Any]? = nil) {
        let name = members(ofGroup: g).first?.group_name ?? ""
        var ops: [[String: Any]] = [DiagramOps.update(ids, ["group": g, "group_name": g.isEmpty ? "" : name])]
        let leaving = Set(plan.els.filter { ids.contains($0.id) && !$0.group.isEmpty && $0.group != g }.map(\.group))
        for old in leaving {
            let left = members(ofGroup: old).filter { !ids.contains($0.id) }
            if left.count == 1 { ops.append(DiagramOps.update(left.map(\.id), ["group": "", "group_name": ""])) }
        }
        if let then { ops.append(then) }
        edit(["op": "batch", "ops": ops])
    }
    func ungroup() { if !selection.isEmpty { edit(["op": "ungroup", "ids": selection]) } }
    func align(_ to: String) { if selection.count > 1 { edit(["op": "align", "ids": selection, "to": to]) } }
    func distribute(_ axis: String) { if selection.count > 2 { edit(["op": "distribute", "ids": selection, "axis": axis]) } }
    func flip(_ axis: String) { if !selection.isEmpty { edit(alone(["op": "flip", "ids": selection, "axis": axis])) } }
    /// ⌘R and its menu: a quarter turn of the pick, about a point on the grid.
    func rotate(_ deg: Double) { if !selection.isEmpty { edit(turnPickOp(by: deg)) } }

    // ---------------------------------------------------------- inside a group

    /// Whether the pick is part of a group and not all of it — one piece
    /// double-clicked inside its group. Then a move, turn, flip or copy is
    /// that piece's own (`alone`), not the whole group's.
    var pickSplitsGroup: Bool {
        picked.contains { e in !e.group.isEmpty && !members(ofGroup: e.group).allSatisfy { selection.contains($0.id) } }
    }

    /// The op, said for the piece alone when the pick is inside a group.
    func alone(_ op: [String: Any]) -> [String: Any] {
        guard pickSplitsGroup else { return op }
        var o = op
        o["alone"] = true
        return o
    }

    /// Exactly the groups wholly picked, when the pick is nothing else.
    var pickedGroups: [String] {
        let gs = Array(Set(picked.map(\.group)))
        guard !gs.isEmpty, !gs.contains(""), !pickSplitsGroup else { return [] }
        return gs.sorted()
    }

    // ---------------------------------------------------------- turning

    /// The picture's own turn of the pick, as Details shows it: the first
    /// picked piece's — a wall's line, or a piece's heading.
    func heading(_ e: DiagramEl) -> Double {
        if e.isLine {
            // A wall's way is its picked stretch's, else its first's.
            let (p, q) = e.isWall ? (e.stretches[min(pickedStretch ?? 0, max(e.stretches.count - 1, 0))])
                                  : (CGPoint(x: e.x, y: e.y), CGPoint(x: e.x2, y: e.y2))
            let a = atan2(Double(q.y - p.y), Double(q.x - p.x)) * 180 / .pi
            // Kept to a hundredth: a wall turned 30° reads 30, not 30.000001.
            let d = ((a.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) * 100).rounded() / 100
            return d >= 360 ? 0 : d
        }
        return e.at(beat: beat).rot
    }

    /// Where the pick turns about: the middle of the box round it, put on the
    /// grid when Snap is on, so a quarter turn keeps the grid's pieces on it.
    func pivot(_ ids: [String]? = nil) -> CGPoint {
        guard let box = extent(ids ?? selection) else { return .zero }
        var c = CGPoint(x: box.midX, y: box.midY)
        if settings.snap {
            let s = snapStep
            c = CGPoint(x: (c.x / s).rounded() * s, y: (c.y / s).rounded() * s)
        }
        return c
    }

    /// The box round these pieces on the plan, as they stand now.
    func extent(_ ids: [String]) -> CGRect? {
        let els = ids.compactMap { id in shown.els.first { $0.id == id } }
        var xs: [Double] = [], ys: [Double] = []
        for e in els {
            if e.isWall { let r = e.run; xs += r.map { Double($0.x) }; ys += r.map { Double($0.y) } }
            else if e.isLine { xs += [e.x, e.x2]; ys += [e.y, e.y2] }
            else if e.isPolyline { xs += e.points.compactMap { $0.first }; ys += e.points.compactMap { $0.count > 1 ? $0[1] : nil } }
            else {
                let now = e.at(beat: beat)
                let (w, h) = e.footprint(at: beat)
                let r = now.rot * .pi / 180
                for (lx, ly) in [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)] {
                    xs.append(now.x + lx * cos(r) - ly * sin(r)); ys.append(now.y + lx * sin(r) + ly * cos(r))
                }
            }
        }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The pick turned by `deg` as one: a single piece about its own middle
    /// (beats and aims kept the way a knob turn keeps them); a wall, several
    /// or a group about `pivot`.
    func turnPickOp(by deg: Double, pivot at: CGPoint? = nil) -> [String: Any] {
        if selection.count == 1, let e = picked.first, !e.isLine, !e.isPolyline {
            let to = ((e.at(beat: beat).rot + deg).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            if e.aim.isEmpty { return turnOp(e, to: to) }
            return DiagramOps.batch([DiagramOps.update([e.id], ["aim": ""]), turnOp(e, to: to)])
        }
        let p = at ?? pivot()
        return alone(["op": "rotate", "ids": selection, "deg": deg, "px": Double(p.x), "py": Double(p.y)])
    }

    /// An angle turned by hand, kept to the steps Snap keeps: 5° with Snap
    /// on, a degree with it off, 15° with ⇧ — and caught at the four square
    /// turns when it comes near one.
    func stepped(_ deg: Double, shift: Bool, free: Bool) -> Double {
        var d = deg
        if shift { d = (d / 15).rounded() * 15 }
        else if settings.snap && !free { d = (d / 5).rounded() * 5 }
        else {
            d = d.rounded()
            let square = (d / 90).rounded() * 90
            if abs(d - square) <= 3 { d = square }
        }
        return (d.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    // ---------------------------------------------------------- bursts

    /// The last of a run of key presses — nudges, or ⌥-arrow turns — so the
    /// next one in the run joins it as one step of undo.
    var burst: (kind: String, ids: [String], at: Date, depth: Int)?

    /// One press of a run: joined to the press before when it is the same
    /// kind of press on the same pick, close behind it, and nothing else has
    /// been done since.
    func burstEdit(_ kind: String, _ op: [String: Any]) {
        guard let engine else { return }
        let now = Date()
        let prior = burst
        let joining = prior.map { $0.kind == kind && $0.ids == selection && now.timeIntervalSince($0.at) < 1.5
            && $0.depth == engine.history().depth } ?? false
        edit(op, join: joining)
        burst = (kind, selection, now, engine.history().depth)
    }

    /// ⌥← / ⌥→: the pick turned a step — 5° with Snap on, 1° off, 15° with ⇧.
    func turnKey(clockwise: Bool, shift: Bool) {
        let step = shift ? 15.0 : (settings.snap ? 5.0 : 1.0)
        if let (e, i, spot) = stepPick {
            burstEdit("turnstep", stepOp(e, i, rot: (spot.rot + (clockwise ? step : -step) + 360).truncatingRemainder(dividingBy: 360)))
            return
        }
        guard !selection.isEmpty else { return }
        burstEdit("turn", turnPickOp(by: clockwise ? step : -step))
    }

    /// A stretch's length, typed — the picked stretch, or a plain wall's
    /// only one. Its far corner moves along it; the engine carries what is
    /// joined there (`wall_length`). A closed room's is its inside face.
    func setWallLength(_ e: DiagramEl, _ want: Double, stretch: Int? = nil) {
        let s = stretch ?? pickedStretch ?? 0
        guard s < e.stretches.count else { return }
        edit(["op": "wall_length", "id": e.id, "stretch": s, "length": max(want, 0.05)])
    }

    /// A stretch's length as the plan shows it: a closed room's along its
    /// inside face (the engine's `shown_length`), else corner to corner.
    func shownLength(_ e: DiagramEl, _ s: Int) -> Double {
        let st = e.stretches
        guard s < st.count else { return 0 }
        if !e.isClosed { return hypot(st[s].1.x - st[s].0.x, st[s].1.y - st[s].0.y) }
        // The inside face: each corner's two faces, mitred, on the room's side.
        let c = e.corners, n = c.count
        var area = 0.0
        for i in 0..<n { area += Double(c[i].x * c[(i + 1) % n].y - c[(i + 1) % n].x * c[i].y) }
        let side: CGFloat = area >= 0 ? 1 : -1
        let half = CGFloat(e.thick / 2)
        func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let l = max(hypot(b.x - a.x, b.y - a.y), 1e-12)
            return CGPoint(x: -(b.y - a.y) / l, y: (b.x - a.x) / l)
        }
        func face(_ i: Int) -> CGPoint {
            let (a, b, d) = (c[(i + n - 1) % n], c[i], c[(i + 1) % n])
            let (n1, n2) = (normal(a, b), normal(b, d))
            let k = max(1 + n1.x * n2.x + n1.y * n2.y, 1e-6)
            return CGPoint(x: b.x + side * half * (n1.x + n2.x) / k, y: b.y + side * half * (n1.y + n2.y) / k)
        }
        let (a, b) = (face(s), face((s + 1) % n))
        return Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// A piece put at an exact spot (Details' X and Y): moved there the way a
    /// drag moves it — at this beat if it walks.
    func place(_ e: DiagramEl, at to: CGPoint) {
        let now = e.at(beat: beat)
        let (dx, dy) = (Double(to.x) - now.x, Double(to.y) - now.y)
        guard abs(dx) > 1e-9 || abs(dy) > 1e-9 else { return }
        edit(moveOp(ids: [e.id], dx: dx, dy: dy))
    }

    /// The wall's edits (`walls.rs`), each one step to take back.
    func wallOp(_ name: String, _ e: DiagramEl, _ more: [String: Any] = [:]) -> [String: Any] {
        var op: [String: Any] = ["op": name, "id": e.id]
        for (k, v) in more { op[k] = v }
        return op
    }

    /// The picked corner opened a door's width (Break), made a curve or a
    /// corner again (Curve), or taken out (Delete Corner).
    func breakCorner() {
        guard let e = picked.first, e.isWall, let i = pickedCorner else { return }
        let made = edit(wallOp("wall_break", e, ["corner": i]))
        pickedCorner = nil
        if !made.isEmpty { selection = [e.id] }
    }
    func roundCorner() {
        guard let e = picked.first, e.isWall, let i = pickedCorner else { return }
        edit(wallOp("wall_round", e, ["corner": i, "round": !(e.round ?? []).contains(i)]))
    }
    func removeCorner() {
        guard let e = picked.first, e.isWall || e.isPath, let i = pickedCorner else { return }
        edit(wallOp("wall_remove_corner", e, ["corner": i]))
        pickedCorner = nil
        pickedStretch = nil
    }
    /// An open wall whose two ends are a door's width and a bit apart — what a
    /// Break leaves — can close on itself (`walls.rs`, `join`).
    func canClose(_ e: DiagramEl) -> Bool {
        guard e.isWall, !e.isClosed, !e.locked, e.corners.count >= 3, let a = e.corners.first, let b = e.corners.last else { return false }
        let gap = settings.units == "m" ? 0.9 : 3 * 0.3048
        return Double(hypot(a.x - b.x, a.y - b.y)) <= gap * 1.7
    }

    /// Walls that meet end to end, made one — across the gap a Break left.
    func joinWalls() {
        let walls = picked.filter(\.isWall).map(\.id)
        guard !walls.isEmpty else { return }
        edit(["op": "wall_join", "ids": walls])
        selection = selection.filter { id in plan.els.contains { $0.id == id } }
    }

    /// The five thicknesses a wall takes in one tap, hairline to very thick —
    /// in feet: 1, 4, 6, 9 and 12 inches; in metres: 2.5, 10, 15, 23, 30 cm.
    var wallThicknesses: [Double] {
        settings.units == "m" ? [0.025, 0.1, 0.15, 0.23, 0.3] : [1, 4, 6, 9, 12].map { $0 * 0.0254 }
    }

    /// The Wall tool's first stretch: a new wall, picked so its lengths show
    /// while the rest is drawn.
    func startWall(_ a: CGPoint, _ b: CGPoint) {
        guard hypot(b.x - a.x, b.y - a.y) > 0.05 else { return }
        let made = edit(["op": "add", "els": [["kind": "wall", "x": a.x, "y": a.y, "x2": b.x, "y2": b.y]]], select: true)
        drawingWall = made.first
    }
    /// The next corner of the wall being drawn: one step to take back each.
    func extendWall(to p: CGPoint) {
        guard let id = drawingWall, let e = el(id), let last = e.corners.last,
              hypot(p.x - last.x, p.y - last.y) > 0.05 else { return }
        edit(["op": "wall_extend", "id": id, "end": "end", "x": p.x, "y": p.y])
    }
    /// The wall being drawn closed on its first corner.
    func closeWall() {
        guard let id = drawingWall, let e = el(id), e.corners.count >= 3 else { return }
        update([id], ["closed": true])
    }

    // ---------------------------------------------------------- the grid

    /// The grid steps there are, finest first: quarter, half and whole feet
    /// and on up; or five and ten centimetres, half a metre, and on up.
    private var ladder: [Double] {
        settings.units == "m" ? [0.05, 0.1, 0.5, 1, 5, 10, 50]
            : [0.25, 0.5, 1, 5, 10, 50, 100].map { $0 * 0.3048 }
    }

    /// **The step everything keeps to** — a drag, a drawn line's end, the
    /// grid drawn: the plan's own step (a foot, or half a metre), finer when
    /// zoomed close and coarser when zoomed far out, so what is drawn is
    /// always what is caught. A metric plan still on the old foot steps in
    /// half metres.
    var snapStep: Double {
        var base = max(settings.step, 0.01)
        if settings.units == "m", abs(base - 0.3048) < 1e-6 || abs(base - 0.1524) < 1e-6 { base = 0.5 }
        if settings.units != "m", abs(base - 0.5) < 1e-6 { base = 0.3048 }
        var steps = ladder
        if !steps.contains(where: { abs($0 - base) < 1e-9 }) { steps.append(base); steps.sort() }
        var i = steps.firstIndex { abs($0 - base) < 1e-9 } ?? 0
        let s = Double(scale)
        while i > 0, steps[i - 1] * s >= 40 { i -= 1 }
        while i < steps.count - 1, steps[i] * s < 7 { i += 1 }
        return steps[i]
    }

    /// How many steps between the grid's darker lines: a foot, five feet,
    /// ten — a metre, five.
    var gridEvery: Int {
        let s = snapStep
        if settings.units == "m" {
            switch s {
            case ..<0.075: return 2      // 5 cm → 10 cm
            case ..<0.3: return 10       // 10 cm → a metre
            case ..<0.75: return 2       // half a metre → a metre
            case ..<2: return 5          // a metre → five
            default: return 2
            }
        }
        let ft = s / 0.3048
        switch ft {
        case ..<0.4: return 4            // 3 in → a foot
        case ..<0.75: return 2           // 6 in → a foot
        case ..<2: return 5              // a foot → five
        case ..<7: return 2              // five → ten
        default: return 5
        }
    }

    /// An arrow key's small nudge: a quarter of the grid with Snap on, a
    /// tenth of a foot or of a metre with it off.
    var nudgeStep: Double {
        if settings.snap { return snapStep / 4 }
        return settings.units == "m" ? 0.1 : 0.03048
    }

    /// A setting on every scene of the film, as one step — Light Beams.
    func settingEverywhere(_ key: String, _ value: Any) {
        guard let engine, let scene, !readOnly,
              let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              var text = String(data: data, encoding: .utf8) else { return }
        text = String(text.dropFirst().dropLast())
        struct Reply: Decodable { var diagram: DiagramPlan }
        guard let r = try? JSONDecoder().decode(Reply.self, from: engine.call("diagrameverywhere", scene, key, text)) else {
            NSSound.beep(); return
        }
        plan = r.diagram
        state?.replace(engine.view())
    }

    func setting(_ key: String, _ value: Any) {
        var set: [String: Any] = [key: value]
        // The sun is read on this Mac's clock, for the day it is drawn for —
        // kept with the plan so the portal and paper draw the same sun.
        if key.hasPrefix("sun") {
            let day = DiagramSunPanel.day.date(from: key == "sun_date" ? (value as? String ?? "") : settings.sun_date) ?? Date()
            set["sun_tz"] = TimeZone.current.secondsFromGMT(for: day) / 60
        }
        edit(["op": "settings", "set": set])
        if key.hasPrefix("sun") || key == "north" { keepSunInView() }
    }

    /// A new hour, day or north can send the sun round to a side of the
    /// plan that is off screen or under a bar; the view slides just enough
    /// to bring it back into the clear, and no further.
    func keepSunInView() {
        guard let size = canvas?.bounds.size, size.width > 200, size.height > 200,
              let sun = plan.sun, let x = sun.x, let y = sun.y else { return }
        let p = toView(CGPoint(x: x, y: y), size: size)
        // Clear of the toolbar, the foot bar and zoom, and a right panel.
        let clear = CGRect(x: 40, y: 90, width: size.width - rightCover - 80, height: size.height - 90 - 150)
        guard clear.width > 60, clear.height > 60, !clear.contains(p) else { return }
        let dx = p.x < clear.minX ? clear.minX - p.x : (p.x > clear.maxX ? clear.maxX - p.x : 0)
        let dy = p.y < clear.minY ? clear.minY - p.y : (p.y > clear.maxY ? clear.maxY - p.y : 0)
        pan(by: CGPoint(x: dx, y: dy))
        canvas?.needsDisplay = true
    }

    var settings: DiagramSettings { plan.settings }

    /// Whether the plan shows a compass: once north has been turned, or the
    /// sun is on — the engine draws one then, for paper and the portal.
    var showsCompass: Bool { plan.shapes.contains { $0.p == "north" } || (liveNorth ?? 0) != 0 }

    /// Nudge what is picked — at the beat showing, for anything that walks.
    func nudge(dx: Double, dy: Double) {
        guard !selection.isEmpty else { return }
        // A run of presses is one step of undo.
        burstEdit("nudge", moveOp(ids: selection, dx: dx, dy: dy))
    }

    /// An arrow key's nudge, `dx`/`dy` as it points on screen: along the
    /// plan's own axis that looks nearest that way once the plan is turned,
    /// so a nudge keeps to the grid.
    func nudge(screen dx: Double, _ dy: Double) {
        let w = unturned(CGPoint(x: dx, y: dy))
        let len = hypot(dx, dy)
        if let (e, i, spot) = stepPick {
            // The step alone, along the plan's nearest axis; the rest stay.
            let (ex, ey) = abs(w.x) >= abs(w.y) ? (w.x < 0 ? -len : len, 0.0) : (0.0, w.y < 0 ? -len : len)
            burstEdit("nudgestep", stepOp(e, i, x: spot.x + ex, y: spot.y + ey))
            return
        }
        if abs(w.x) >= abs(w.y) { nudge(dx: w.x < 0 ? -len : len, dy: 0) } else { nudge(dx: 0, dy: w.y < 0 ? -len : len) }
    }

    /// A move, said the right way for the beat: at beat 1, or for something
    /// that has never walked, the thing itself moves (beats and all); at a
    /// later beat, anything that walks is moved *at that beat only*, which is
    /// how blocking is done — go to beat 2, drag Anya to the door.
    func moveOp(ids: [String], dx: Double, dy: Double) -> [String: Any] {
        let els = ids.compactMap(el)
        let walking = els.filter { walksAtThisBeat($0) }
        if walking.isEmpty { return alone(DiagramOps.move(ids, dx: dx, dy: dy)) }
        var ops: [[String: Any]] = []
        let still = els.filter { !walksAtThisBeat($0) }.map(\.id)
        if !still.isEmpty { ops.append(alone(DiagramOps.move(still, dx: dx, dy: dy))) }
        for e in walking {
            let now = e.at(beat: beat)
            ops.append(DiagramOps.beat(e.id, beat, x: now.x + dx, y: now.y + dy, rot: now.rot))
        }
        return DiagramOps.batch(ops)
    }

    /// Whether a move of this at the showing beat is a move *at this beat*.
    func walksAtThisBeat(_ e: DiagramEl) -> Bool {
        guard ["camera", "cast", "light"].contains(e.kind) || (e.kind == "set" && e.hasSteps) else { return false }
        if beat <= 1 { return e.hasSteps }
        return true
    }

    /// A turn at the showing beat.
    func turnOp(_ e: DiagramEl, to rot: Double) -> [String: Any] {
        if walksAtThisBeat(e) {
            let now = e.at(beat: beat)
            return DiagramOps.beat(e.id, beat, x: now.x, y: now.y, rot: rot)
        }
        return DiagramOps.update([e.id], ["rot": rot])
    }

    // ---------------------------------------------------------- adding

    /// The next colour a camera takes when it arrives — his own, from then on.
    func nextCameraColour() -> String {
        let used = plan.els.filter { $0.kind == "camera" }.count
        let palette = Columns.palette
        return "#" + palette[used % palette.count]
    }

    func addCamera(at p: CGPoint, rot: Double) {
        var el: [String: Any] = ["kind": "camera", "x": p.x, "y": p.y, "rot": rot, "color": nextCameraColour()]
        // Chosen from the Camera button's menu: a shot already in the
        // scene, or none; otherwise a camera brings a new shot.
        switch armedShot {
        case "": break
        case let shot? where shot != "new": el["shot"] = shot
        default: el["new_shot"] = true
        }
        edit(["op": "add", "els": [el]], select: true)
        tool = .select
    }

    /// A person put down: a character from the script, or, with no name, a
    /// plain one numbered after the others.
    func addCast(at p: CGPoint, rot: Double, character: String? = nil) {
        var el: [String: Any] = ["kind": "cast", "x": p.x, "y": p.y, "rot": rot]
        if let character, !character.isEmpty {
            el["label"] = character
            el["cast"] = character
        } else {
            el["label"] = "Cast \(plan.els.filter { $0.kind == "cast" }.count + 1)"
        }
        edit(["op": "add", "els": [el]], select: true)
        tool = .select
    }

    /// For the checks: who the next person put down is, in place of the menu.
    var castAs: String?

    /// The characters the cast tool offers here, and who is already on the plan.
    func castChoices() -> (scene: [String], film: [String], placed: Set<String>) {
        guard let engine, let scene else { return ([], [], []) }
        let (here, film) = engine.diagramCast(scene: scene)
        let placed = Set(plan.els.filter { $0.kind == "cast" }.map { ($0.cast.isEmpty ? $0.label : $0.cast).lowercased() })
        return (here, film, placed)
    }

    /// **One label for the picked lights** (Labs): a picked label among
    /// them is the one they join; else new words are put over them.
    func shareLabel() {
        let ids = Array(selection)
        // `ppm`: new words are put down clear of the others at the size
        // they are drawn (fix round 2).
        let made = edit(["op": "share_label", "ids": ids, "ppm": Engine.diagramZoom, "page": Engine.diagramPage])
        if let label = made.first { selection = [label] }
    }

    /// The label and the lamp, if a connector between these two pieces joins one to the other.
    func tiePair(_ a: String?, _ b: String?) -> [String]? {
        guard let a, let b, a != b, let x = el(a), let y = el(b) else { return nil }
        let pair = [x, y]
        guard let label = pair.first(where: { $0.kind == "text" }),
              let lamp = pair.first(where: { DiagramMarks.canShare($0) }) else { return nil }
        return [label.id, lamp.id]
    }

    /// **A connector drawn between a label and a lamp** ties the lamp to
    /// that label, as Same Lamp does. False when the two are not such a pair.
    func tieLabel(_ a: String?, _ b: String?) -> Bool {
        guard let ids = tiePair(a, b) else { return false }
        let made = edit(["op": "share_label", "ids": ids])
        guard let id = made.first else { return false }
        selection = [id]
        return true
    }

    /// **A lamp, put down as a mark** (Labs): no unit yet. The Light tool
    /// stays in hand for the next one.
    func addLamp(at p: CGPoint, rot: Double) {
        let look = DiagramMarks.Look(key: armedLook)
        // Its Type from the palette's top row: Film Light, Practical or
        // Existing — which is its ink.
        let type = DiagramMarks.type(ofInk: look.ink)
        // A mat lies flat, 4 × 2 ft, its width along the page until turned.
        let mat = DiagramMarks.isMat(look.mark)
        let el: [String: Any] = ["kind": "light", "sym": "", "x": p.x, "y": p.y, "rot": mat && rot == 270 ? 0 : rot,
                                 "w": mat ? DiagramMarks.matSize.w : 0.3,
                                 "h": mat ? DiagramMarks.matSize.h : DiagramMarks.isTube(look.mark) ? DiagramMarks.tubeDefault(look.mark) : 0.3,
                                 "mark": look.mark, "mark_fill": look.solid ? "solid" : "open",
                                 "practical": type == "practical", "existing": type == "existing"]
        // No label until he types one (his call, 2026-10-15).
        edit(["op": "add", "els": [el]], select: true)
    }

    /// **Name a lamp** (`name_lamp`): this one alone (his call, 2026-10-15:
    /// labels are just what you type). Never its symbol.
    func nameLamp(_ id: String, _ name: String, only: Bool = false) {
        edit(["op": "name_lamp", "id": id, "name": name.trimmingCharacters(in: .whitespaces), "only": only])
    }

    func addSymbol(_ sym: DiagramSymbol, at p: CGPoint, rot: Double) {
        // The library's Frame is the Frame tool's: lying flat, 8 × 8.
        if sym.id == DiagramFrames.sym {
            addFrame(at: p, rot: 0)
            DiagramRecent.use(sym.id, in: sym.lib)
            return
        }
        var e: [String: Any] = ["kind": sym.light ? "light" : "set", "sym": sym.id,
                                "x": p.x, "y": p.y, "rot": rot, "w": sym.w, "h": sym.h]
        if sym.light {
            e["beam"] = sym.beam
            e["reach"] = sym.reach
            e["kelvin"] = sym.kelvin
            e["beam_on"] = sym.beam > 0
        }
        edit(["op": "add", "els": [e]], select: true)
        DiagramRecent.use(sym.id, in: sym.lib)
        // **Put down, then back to the arrow** (his note, 2026-09-29): what
        // was just added is usually dragged straight away.
        tool = .select
    }

    /// Which way a piece faces when it is put down without a drag: a lamp
    /// or a bit of grip the way its library picture shows it — up the
    /// screen (2026-09-30) — a set piece square to the plan.
    var restingRot: Double { tool == .light ? 270 : tool.usesLibrary ? Self.restingRot(armed) : 0 }

    static func restingRot(_ sym: DiagramSymbol?) -> Double { sym?.light == true ? 270 : 0 }

    /// `sliding` is a door on a track, put down shut.
    func addOpening(_ kind: String, at p: CGPoint) {
        var e: [String: Any] = ["kind": kind == "sliding" ? "door" : kind, "x": p.x, "y": p.y]
        if kind == "sliding" { e["slide"] = true; e["swing"] = 0 }
        if let engine, let scene,
           let onto = engine.diagramWall(scene: scene, x: p.x, y: p.y, reach: 0.6) {
            e["x"] = onto.x; e["y"] = onto.y; e["rot"] = onto.rot; e["h"] = onto.thick
        }
        edit(["op": "add", "els": [e]], select: true)
        tool = .select
    }

    /// `connector`: an arrow with no head and a lighter line — a note tied
    /// to what it is about, two pieces joined (his ask, 2026-10-01).
    func addLine(_ kind: String, from a: CGPoint, to b: CGPoint, pins: (String?, String?) = (nil, nil), connector: Bool = false) {
        edit(["op": "add", "els": [Self.lineEl(kind, from: a, to: b, pins: pins, connector: connector, inSet: layer == "set")]], select: true)
        tool = .select
    }

    static func lineEl(_ kind: String, from a: CGPoint, to b: CGPoint, pins: (String?, String?), connector: Bool, inSet: Bool = false) -> [String: Any] {
        var e: [String: Any] = ["kind": kind, "x": a.x, "y": a.y, "x2": b.x, "y2": b.y]
        // An arrow stays in the view it was drawn in (Set or Plot).
        if kind == "arrow", inSet { e["in_set"] = true }
        if kind == "arrow" { e["head"] = connector ? "none" : "end" }
        if connector { e["weight"] = 0.8 }
        // An arrow drawn from or onto a piece is pinned to it (`settle_arrows`).
        if kind == "arrow", let on = pins.0 { e["start_on"] = on }
        if kind == "arrow", let on = pins.1 { e["end_on"] = on }
        // A ruler laid from or onto a piece: that end's marker is locked to it.
        if kind == "measure", pins.0 != nil || pins.1 != nil { e["pins"] = [pins.0 ?? "", pins.1 ?? ""] }
        return e
    }

    /// A whole room in one drag: one closed wall of four corners — one
    /// piece, so a click takes it whole and a corner is dragged on its own.
    func addRoom(_ r: CGRect) {
        guard r.width > 0.3, r.height > 0.3 else { return }
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        edit(["op": "add", "els": [["kind": "wall", "points": pts.map { [Double($0.x), Double($0.y)] }, "closed": true]]], select: true)
    }

    func addShape(_ r: CGRect) {
        let w = max(r.width, 0.2), h = max(r.height, 0.2)
        edit(["op": "add", "els": [["kind": "shape", "sym": shapeKind,
                                    "x": r.midX, "y": r.midY, "w": w, "h": h]]], select: true)
        tool = .select
    }

    /// A path drawn with the Draw tool, made what `drawAs` says. Closed, it
    /// is one shape; an open object is only an outline.
    func addPath(_ nodes: [PathNode], closed: Bool) {
        guard nodes.count >= 2 else { return }
        let shut = closed && nodes.count >= 3
        var e: [String: Any] = [
            "kind": drawAs == "wall" ? "wall" : "stroke",
            "points": nodes.map { [Double($0.p.x), Double($0.p.y)] },
            "handles": nodes.map { [Double($0.hin.dx), Double($0.hin.dy), Double($0.hout.dx), Double($0.hout.dy)] },
        ]
        if shut { e["closed"] = true }
        let filled = shut && (drawAs == "object" || drawFill)
        e["fill"] = filled && drawAs != "wall"
        // A colour picked for the pen is the fill's colour too; none is the plan's tint.
        if filled { e["fill_color"] = penColour.isEmpty ? (drawAs == "wall" ? "auto" : "") : penColour }
        if drawAs != "wall", !penColour.isEmpty { e["color"] = penColour }
        edit(["op": "add", "els": [e]], select: true)
        tool = .select
    }

    /// The fill of a closed path or room put on or off.
    func setFilled(_ e: DiagramEl, _ on: Bool) {
        if e.isWall { update([e.id], ["fill_color": on ? "auto" : ""]) }
        else { update([e.id], on ? ["fill": true] : ["fill": false, "fill_color": ""]) }
    }

    /// Its fill given a colour — empty for the plan's tint.
    func setFillColour(_ e: DiagramEl, _ c: String) {
        if e.isWall { update([e.id], ["fill_color": c.isEmpty ? "auto" : c]) }
        else { update([e.id], ["fill": true, "fill_color": c]) }
    }

    /// A path or wall drawn another way (`path_as`): a line, a wall, an object.
    func setPathKind(_ e: DiagramEl, _ kind: String) {
        edit(["op": "path_as", "id": e.id, "as": kind])
    }

    /// The picked corner made smooth, or sharp again.
    func smoothCorner() {
        guard let e = picked.first, e.isWall || e.isPath, let i = pickedCorner, i < e.corners.count else { return }
        edit(wallOp("wall_smooth", e, ["corner": i, "smooth": !e.isSmooth(i)]))
    }

    func addPolyline(_ kind: String, _ points: [CGPoint]) {
        guard points.count >= 2 else { return }
        var e: [String: Any] = ["kind": kind, "points": points.map { [Double($0.x), Double($0.y)] }]
        if kind == "stroke", !penColour.isEmpty { e["color"] = penColour }
        edit(["op": "add", "els": [e]], select: kind != "stroke")
    }

    /// **Words, put down and typed straight away** — on the plan, in the
    /// words themselves (his call F). The sticky Note is Words now.
    func addWords(_ kind: String, at p: CGPoint) {
        var words: [String: Any] = ["kind": "text", "x": p.x, "y": p.y, "text": "Words", "size": DiagramTyping.wordsRegular]
        if layer == "set" { words["in_set"] = true }   // words stay in the view they were put down in
        let made = edit(["op": "add", "els": [words]], select: true)
        tool = .select
        if let id = made.first { startTyping(id) }
    }

    /// A picture under the plan: a floor plan he was sent, a photograph of the
    /// room from above. Laid in the middle of what is on screen, a little
    /// narrower than the view, and picked so its corners can size it.
    func pickPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .pdf]
        panel.allowsMultipleSelection = false
        panel.title = "Add Picture"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addPicture(url)
    }

    func addPicture(_ url: URL) {
        guard let source = NSImage(contentsOf: url) else { NSSound.beep(); return }
        // Everything stored as PNG or JPEG: a PDF or a HEIC would draw nowhere
        // but here.
        guard let tiff = source.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { NSSound.beep(); return }
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                        : rep.representation(using: .png, properties: [:])
        guard let data else { NSSound.beep(); return }
        lay(data, ext: jpeg ? "jpg" : "png", pixels: (rep.pixelsWide, rep.pixelsHigh),
            filename: url.lastPathComponent, at: nil)
    }

    /// **Set Scale** on a picture: the next drag across it is a length he
    /// knows, and the picture is sized so that length is true (Scenario's
    /// known-distance scaling). The picture's id while it is waiting.
    @Published var calibrating: String?
    /// The gear list, a tab of the right sidebar.
    @Published var showingGear = false
    /// Gear in front of Details when both are open.
    @Published var gearFront = false
    /// The nine favorite slots, open under the toolbar's Favorites.
    @Published var showingFavorites = false
    /// The left sidebar on Layers (or Shots) rather than the scene list.
    @Published var showingLayers = false
    /// The left sidebar showing the scene's shots rather than the layers.
    @Published var showingShots = false
    /// The left sidebar on the plot's legend.
    @Published var showingLegend = false
    /// The plot's Colours panel.
    @Published var showingColours = false
    /// The left sidebar's tab: `scenes`, `legend`, `layers` or `shots`.
    var sideTab: String {
        get { showingLegend ? "legend" : !showingLayers ? "scenes" : (showingShots ? "shots" : "layers") }
        set {
            showingLegend = newValue == "legend"
            showingLayers = newValue != "scenes" && newValue != "legend"
            if showingLayers { showingShots = newValue == "shots" }
            if newValue != "scenes", state?.sidebarShown == false { state?.sidebarShown = true }
            if newValue != "scenes" { state?.diagramFolded = false }
        }
    }
    /// Details — what is picked, down the right side. Shut until asked for
    /// (Back to Paper, Batch 2); open, it stays open, on this Mac, from plan
    /// to plan and launch to launch (2026-10-17).
    @Published var showingDetails = UserDefaults.standard.bool(forKey: "diagramDetailsOpen") {
        didSet { if showingDetails != oldValue { UserDefaults.standard.set(showingDetails, forKey: "diagramDetailsOpen") } }
    }
    /// The Show panel: a switch per kind.
    @Published var showingShow = false
    /// Kinds this Mac is not showing (`DiagramShow`): not drawn, not
    /// hittable. Each person's own view, like Scenario's — never in the film.
    /// Only the switches the menu still has: one retired (Names, Cones —
    /// View › Labels and View › Cones now) never hides anything unseen.
    @Published var unseenKinds: Set<String> = Set((UserDefaults.standard.stringArray(forKey: "diagramUnseen") ?? [])
        .filter { k in DiagramShow.kinds.contains { $0.key == k } }) {
        didSet {
            UserDefaults.standard.set(Array(unseenKinds).sorted(), forKey: "diagramUnseen")
            let gone = unseenIds
            if selection.contains(where: gone.contains) { selection.removeAll(where: gone.contains) }
        }
    }
    /// The view before Present, to come back to.
    var beforePresent: (centre: CGPoint, scale: CGFloat)?

    /// Moved in the Layers list: just over (`above`) or under another piece.
    func restack(_ ids: [String], next: String, above: Bool) {
        edit(["op": "order", "ids": ids, "to": above ? "above" : "below", "next": next])
    }
    /// For the checks: the length to answer with, in place of asking.
    var calibrateAnswer: String?

    /// A length as typed — `12`, `12 ft`, `12'6"`, `3.5 m`, `90 cm`, `40 in` —
    /// in metres. A bare number is in the plan's own units.
    func parseLength(_ text: String) -> Double? {
        // One reader for every length typed — Details' and Set Scale's.
        guard let m = LengthField.parse(text, metric: settings.units == "m"), m > 0 else { return nil }
        return m
    }

    /// The picture sized about `a` so the drag from `a` to `b` is `metres` long.
    func calibrate(_ id: String, from a: CGPoint, to b: CGPoint, metres: Double) {
        let measured = Double(hypot(b.x - a.x, b.y - a.y))
        guard measured > 0.001, metres > 0, let e = el(id) else { return }
        let k = metres / measured
        update([id], ["w": e.w * k, "h": e.h * k,
                      "x": Double(a.x) + (e.x - Double(a.x)) * k, "y": Double(a.y) + (e.y - Double(a.y)) * k])
    }

    /// Whether a picture put down now is a loose photo over the plan, or a
    /// background under it — the switch at the head of the pictures panel.
    @Published var pictureAsPhoto = false

    /// **The picture being drawn on** (his ask, 2026-10-15), by id; nil on
    /// the plan. While it is set the plan steps back, the picture shows at
    /// full strength and `PhotoEditor` has the hand (`PhotoEditor.swift`).
    @Published var photoEditing: String?
    @Published var photoTool: PhotoTool = .select
    /// The mark picked on it, by its place in the picture's list.
    @Published var photoPicked: Int?
    /// While the Photo slider is held: the strength it is shown at.
    @Published var photoStrengthPreview: Double?
    /// What the hand is doing on it (`PhotoHand`).
    let photoHand = PhotoHand()
    /// The view to go back to when Done.
    var photoReturnView: (centre: CGPoint, scale: CGFloat)?

    /// A picture the film already holds, laid on the plan: at `at`, or the
    /// middle of what is on screen.
    func addProjectPicture(_ pic: DiagramProjectPicture, at: CGPoint? = nil) {
        guard let engine, let stored = engine.stored(hash: pic.hash, ext: pic.ext) else { NSSound.beep(); return }
        var data = stored.data, ext = stored.ext.lowercased()
        var pixels = (pic.width, pic.height)
        if !["png", "jpg", "jpeg"].contains(ext) || pixels.0 <= 0 || pixels.1 <= 0 {
            guard let rep = NSImage(data: data)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
                  let png = rep.representation(using: .png, properties: [:]) else { NSSound.beep(); return }
            if !["png", "jpg", "jpeg"].contains(ext) { data = png; ext = "png" }
            pixels = (rep.pixelsWide, rep.pixelsHigh)
        }
        lay(data, ext: ext == "jpeg" ? "jpg" : ext, pixels: pixels, filename: pic.filename, at: at)
    }

    private func lay(_ data: Data, ext: String, pixels: (Int, Int), filename: String, at: CGPoint?) {
        guard let engine, let scene else { NSSound.beep(); return }
        let size = canvas?.bounds.size ?? CGSize(width: 900, height: 600)
        let photo = pictureAsPhoto
        let wide = Double(size.width / scale) * (photo ? 0.2 : 0.6)
        let at = at ?? centre
        let line = ["diagramimage", scene, String(pixels.0), String(pixels.1), ext,
                    data.base64EncodedString(), filename, String(Double(at.x)), String(Double(at.y)),
                    String(max(wide, 1)), photo ? "photo" : ""].joined(separator: "\t")
        struct Reply: Decodable { var made: [String] }
        let reply = engine.callRaw(line)
        guard let made = try? JSONDecoder().decode(Reply.self, from: reply) else { NSSound.beep(); return }
        state?.replace(engine.view())
        reload()
        selection = made.made
    }

    /// Every picture the film holds that could go on this plan, in groups:
    /// the scene's own, its shots' frames, its locations', its boards', then
    /// every other location's and board's. A picture shows once, in the first
    /// group that has it.
    func projectPictures() -> [(String, [DiagramProjectPicture])] {
        guard let view = state?.view, let scene = view.scenes.first(where: { $0.id == self.scene }) else { return [] }
        var seen = Set<String>()
        var out: [(String, [DiagramProjectPicture])] = []
        func add(_ title: String, _ pics: [DiagramProjectPicture]) {
            let fresh = pics.filter { seen.insert($0.hash).inserted }
            if !fresh.isEmpty { out.append((title, fresh)) }
        }
        func pics(_ list: [ViewModel.Attachment]) -> [DiagramProjectPicture] {
            list.filter { $0.kind == "image" }.map {
                DiagramProjectPicture(hash: $0.hash, filename: $0.filename, width: $0.width, height: $0.height)
            }
        }
        add("This Scene", pics(scene.attachments))
        add("Shots", view.allRows.filter { $0.sceneId == scene.id }.flatMap { row in
            row.stills.filter { !$0.moving }.map {
                DiagramProjectPicture(hash: $0.hash, filename: $0.filename, width: 0, height: 0)
            }
        })
        let here = view.locations.filter { $0.scenes.contains(scene.id) }
        let boards = view.boards.filter { $0.scenes.contains(scene.id) }
        for l in here { add(l.name, pics(l.media)) }
        for b in boards { add(b.name, pics(b.media)) }
        for l in view.locations where !here.contains(where: { $0.id == l.id }) { add(l.name, pics(l.media)) }
        for b in view.boards where !boards.contains(where: { $0.id == b.id }) { add(b.name, pics(b.media)) }
        return out
    }

    // ---------------------------------------------------------- beats

    var lastBeat: Int { max(plan.lastBeat, 1) }

    /// A new beat after the last: nothing moves until something is dragged.
    func addBeat() { beat = lastBeat + 1 }

    // ---------------------------------------------------------- steps

    /// **Add Move** (his ruling, 2026-10-01: *"if I add a move to a camera or
    /// a person or a turn, then that becomes a programmable beat I can do
    /// later"*): the next step, a little on from the one it follows, on the
    /// next beat, picked to be dragged where the move really goes. After the
    /// picked step, or after the last with the thing itself picked; a Move
    /// From goes just before. As many as he likes — the letters run on past Z.
    func addMove(_ id: String, from: Bool) { addStep(id, from: from, turn: false) }

    /// **Add Turn** (his note, 2026-09-29): a step that stays where the one
    /// before it stands and only turns — a head turning to the door, a
    /// camera panning off — starting a quarter turn round, for its knob to
    /// be dragged where it really points.
    func addTurn(_ id: String, from: Bool) { addStep(id, from: from, turn: true) }

    private func addStep(_ id: String, from: Bool, turn: Bool) {
        guard let e = el(id), e.moves else { return }
        let picked = selection == [id] ? stepPick?.i : nil
        var op: [String: Any] = ["op": "step_add", "id": id]
        if turn { op["turn"] = true }
        let made: Int
        if from {
            let before = picked ?? e.homeIndex
            op["before"] = before
            made = before
        } else {
            let after = picked ?? (e.spots.count - 1)
            op["after"] = after
            made = after + 1
        }
        edit(op)
        if selection != [id] { selection = [id] }
        pickedStep = made
    }

    /// The op that changes one step — where it stands, how it faces, its beat.
    func stepOp(_ e: DiagramEl, _ i: Int, x: Double? = nil, y: Double? = nil, rot: Double? = nil, beat: Int? = nil) -> [String: Any] {
        var op: [String: Any] = ["op": "step_set", "id": e.id, "step": i]
        if let x { op["x"] = x }
        if let y { op["y"] = y }
        if let rot { op["rot"] = rot }
        if let beat { op["beat"] = beat }
        return op
    }

    func removeStep(_ id: String, _ i: Int) {
        edit(["op": "step_remove", "id": id, "step": i])
        if pickedStep == i { pickedStep = nil }
    }

    func removeBeat(_ n: Int, from id: String) {
        edit(["op": "unbeat", "id": id, "beat": n])
    }

    // ---------------------------------------------------------- the view

    func fit(in size: CGSize) {
        guard size.width > 40, size.height > 40 else { return }
        // The whole sheet, as it prints.
        if fitPage(in: size) { pageState.lastLeft = nil; return }
        guard let e = plan.extent, e.count == 4 else {
            centre = CGPoint(x: 2, y: 1.5)
            scale = 60
            fitted = true
            return
        }
        let w = max(e[2] - e[0], 1), h = max(e[3] - e[1], 1)
        let pad: CGFloat = 90
        scale = min(max(min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h), 8), 220)
        // The extent is the plan as shown, turned; its middle, back on the plan.
        centre = unturned(CGPoint(x: (e[0] + e[2]) / 2, y: (e[1] + e[3]) / 2))
        fitted = true
    }

    func zoom(by factor: CGFloat, around viewPoint: CGPoint? = nil, size: CGSize) {
        let old = scale
        let new = min(max(scale * factor, 4), 600)
        guard new != old else { return }
        if let p = viewPoint {
            // Keep the world point under the pointer where it is.
            let world = toWorld(p, size: size)
            scale = new
            let after = toWorld(p, size: size)
            centre.x += world.x - after.x
            centre.y += world.y - after.y
        } else {
            scale = new
        }
    }

    /// How far the plan is turned on screen, in radians clockwise: **never,
    /// now.** His note, 2026-09-29, taking back 2026-09-27's north-is-up:
    /// *"spinning the compass should not spin the set — the sun should move
    /// around the set as it stays put."* The compass's needle turns to
    /// north and the sun goes round; the set stands as it was drawn. Kept as
    /// a property, and every screen sum still runs through it, so the plan
    /// could be turned again for showing without finding them all.
    var turn: CGFloat { 0 }

    /// A step on the plan, as it points on screen — and back.
    func turned(_ p: CGPoint) -> CGPoint {
        let (c, s) = (cos(turn), sin(turn))
        return CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }
    func unturned(_ p: CGPoint) -> CGPoint {
        let (c, s) = (cos(turn), sin(turn))
        return CGPoint(x: p.x * c + p.y * s, y: -p.x * s + p.y * c)
    }

    /// Plan metres to screen points: `toView`'s whole sum, for painting.
    func transform(size: CGSize) -> CGAffineTransform {
        CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .rotated(by: turn)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    /// Slide the view by a distance on screen.
    func pan(by d: CGPoint) {
        let w = unturned(CGPoint(x: d.x / scale, y: d.y / scale))
        centre.x -= w.x
        centre.y -= w.y
    }

    func toWorld(_ p: CGPoint, size: CGSize) -> CGPoint {
        let w = unturned(CGPoint(x: (p.x - size.width / 2) / scale, y: (p.y - size.height / 2) / scale))
        return CGPoint(x: w.x + centre.x, y: w.y + centre.y)
    }

    func toView(_ p: CGPoint, size: CGSize) -> CGPoint {
        let v = turned(CGPoint(x: p.x - centre.x, y: p.y - centre.y))
        return CGPoint(x: v.x * scale + size.width / 2, y: v.y * scale + size.height / 2)
    }

    /// A length as he reads it.
    func length(_ metres: Double) -> String {
        if settings.units == "m" { return String(format: "%.2f m", metres) }
        // To the quarter inch, so a length typed as 6 1/2" reads back as it
        // was typed (`mod.rs` length_text, the plan's own labels, agrees).
        // Only a length that *is* a quarter inch (typed so) shows one; any
        // other reads to the whole inch, as it always did.
        let q = metres / 0.0254 * 4
        let quarters = abs(q - q.rounded()) < 0.02 ? Int(q.rounded()) : Int((q / 4).rounded()) * 4
        let ft = quarters / 48, rest = quarters % 48
        let inch = rest / 4
        let frac = ["", "¼", "½", "¾"][rest % 4]
        let inches = inch == 0 ? (frac.isEmpty ? "" : "\(frac) in") : "\(inch)\(frac.isEmpty ? "" : " " + frac) in"
        if ft == 0 { return inches.isEmpty ? "0 in" : inches }
        if inches.isEmpty { return "\(ft) ft" }
        return "\(ft) ft \(inches)"
    }

    // ---------------------------------------------------------- the clipboard

    static let pasteType = NSPasteboard.PasteboardType("com.example.shotlister.diagram")

    /// **Undo says what it undid** — "Undo Move", "Redo Add Light" — for a
    /// moment over the plan, then gone.
    @Published var toast: String?
    private var toastFade: DispatchWorkItem?
    func flash(_ line: String) {
        toast = line
        if Launch.checking { FileHandle.standardError.write(Data("toast: \(line)\n".utf8)) }
        toastFade?.cancel()
        let fade = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastFade = fade
        // A checking run holds it long enough to be photographed.
        DispatchQueue.main.asyncAfter(deadline: .now() + (Launch.checking ? 8 : 1.6), execute: fade)
    }

    /// Where the pointer is over the plan, in plan metres — nil when it is
    /// off it. A paste lands here.
    var pointer: CGPoint?
    /// The last paste: where it was aimed (the pointer, or nil for none)
    /// and how many have gone there in a row — the next one there steps on.
    private var pasteRun: (at: CGPoint?, n: Int)?

    func copy() {
        pasteRun = nil
        guard !selection.isEmpty else { return }
        let raw = rawElements(selection)
        guard !raw.isEmpty, let data = try? JSONSerialization.data(withJSONObject: raw) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: DiagramModel.pasteType)
    }

    func cut() {
        copy()
        remove(selection)
    }

    /// **Paste lands at the pointer** when it is over the plan, the copy's
    /// middle under it (on the grid with Snap on); off the plan, a step off
    /// the original. **Pasted again in the same place, each copy steps on**
    /// from the last instead of landing on it, so a row builds. Copies keep
    /// their aim — at a piece copied with them, at that piece's copy.
    func paste() {
        guard let data = NSPasteboard.general.data(forType: DiagramModel.pasteType),
              var els = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !els.isEmpty else { return }
        let unit = settings.snap ? snapStep : settings.step
        let target = pointer
        let same: Bool = {
            guard let run = pasteRun else { return false }
            switch (run.at, target) {
            case (nil, nil): return true
            case let (a?, b?): return hypot(a.x - b.x, a.y - b.y) < 1e-6
            default: return false
            }
        }()
        let n = same ? pasteRun!.n + 1 : (target == nil ? 1 : 0)
        pasteRun = (target, n)
        var sx = unit * Double(n), sy = unit * Double(n)
        if let target, let mid = Self.middle(els) {
            var ox = Double(target.x) - mid.x, oy = Double(target.y) - mid.y
            if settings.snap { ox = (ox / snapStep).rounded() * snapStep; oy = (oy / snapStep).rounded() * snapStep }
            sx += ox; sy += oy
        }
        // A pasted group is a group of its own — the copies must not join the
        // group they were copied from, or moving one would drag both.
        var regrouped: [String: String] = [:]
        let stamp = Int(Date().timeIntervalSince1970 * 1000) % 1_000_000_000
        for i in els.indices {
            if let g = els[i]["group"] as? String, !g.isEmpty {
                if regrouped[g] == nil { regrouped[g] = "p\(stamp)-\(regrouped.count)" }
                els[i]["group"] = regrouped[g]
            }
            // The id stays: the engine gives a copy a new one, and moves an
            // aim or a rig at it to the copy.
            els[i]["shot"] = nil
            for (k, d) in [("x", sx), ("y", sy), ("x2", sx), ("y2", sy)] {
                if let v = els[i][k] as? Double { els[i][k] = v + d }
            }
            if var pts = els[i]["points"] as? [[Double]] {
                pts = pts.map { [$0[0] + sx, $0[1] + sy] }
                els[i]["points"] = pts
            }
            els[i]["seq"] = nil
            if var steps = els[i]["steps"] as? [[String: Any]] {
                for j in steps.indices {
                    if let x = steps[j]["x"] as? Double { steps[j]["x"] = x + sx }
                    if let y = steps[j]["y"] as? Double { steps[j]["y"] = y + sy }
                }
                els[i]["steps"] = steps
            }
        }
        // A group only one of whose members was copied is no group at all.
        let counts = Dictionary(grouping: els.compactMap { $0["group"] as? String }, by: { $0 }).mapValues(\.count)
        for i in els.indices {
            if let g = els[i]["group"] as? String, (counts[g] ?? 0) < 2 { els[i]["group"] = "" }
        }
        edit(["op": "add", "els": els], select: true)
    }

    /// The middle of the box round copied pieces, plan metres.
    static func middle(_ els: [[String: Any]]) -> (x: Double, y: Double)? {
        var xs: [Double] = [], ys: [Double] = []
        for e in els {
            if let x = e["x"] as? Double, let y = e["y"] as? Double { xs.append(x); ys.append(y) }
            // Only a line's far end counts — every piece carries an x2, y2.
            if ["wall", "track", "road", "measure", "arrow"].contains(e["kind"] as? String ?? ""),
               let x = e["x2"] as? Double, let y = e["y2"] as? Double { xs.append(x); ys.append(y) }
            for p in (e["points"] as? [[Double]]) ?? [] where p.count > 1 { xs.append(p[0]); ys.append(p[1]) }
        }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        return ((x0 + x1) / 2, (y0 + y1) / 2)
    }

    /// The picked elements as plain JSON, for the clipboard.
    private func rawElements(_ ids: [String]) -> [[String: Any]] {
        guard let engine, let scene else { return [] }
        let data = engine.call("diagram", scene, "beat=1", "sel=")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let els = obj["els"] as? [[String: Any]] else { return [] }
        return els.filter { ids.contains(($0["id"] as? String) ?? "") }.map { e in
            var e = e
            for k in ["focal", "aov", "name"] { e[k] = nil }
            return e
        }
    }
}

// MARK: - the Ruler's markers

extension DiagramModel {
    /// Lock the picked marker of a ruler to a piece, or let it go (nil): it
    /// stays where it stands until moved.
    func lockMarker(_ e: DiagramEl, to id: String?) {
        guard let i = pickedCorner, i < e.corners.count else { return }
        let c = e.corners[i]
        edit(wallOp("wall_corner", e, ["corner": i, "x": c.x, "y": c.y, "on": id ?? ""]))
    }

    /// What a piece is called in a Lock To menu: its name, else its kind.
    func lockName(_ p: DiagramEl) -> String {
        if let n = p.name, !n.isEmpty { return n }
        if !p.label.isEmpty { return p.label }
        return p.kind.prefix(1).uppercased() + p.kind.dropFirst()
    }
}
