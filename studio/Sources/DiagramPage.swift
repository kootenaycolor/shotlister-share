import SwiftUI
import AppKit

// **The sheet on screen** (Back to Paper, Batch 2, design/32 item 9, his
// call C): the page that prints, lying on the desk. The engine lays it out
// once (`engine/src/diagram/sheet.rs`, `ffi diagramsheet`) — the title with
// the film, the day and north, the plan in its window, the band of Notes,
// Legend and Shots — and the Mac, Export, the Print window, the portal and
// Claude's paper picture all draw that one layout.
//
// Here the plan stays where it is on the canvas, in metres, and the page is
// put round it: the sheet says where the plan's origin lands on the paper
// and at how many points to the metre, so the paper's corners are found on
// the plan and the sheet's own words and marks drawn over them. The page
// takes the paper's gentle grey and the Backdrop setting (Refs 1256, 1404);
// on paper it is white.
//
// A legend line picks every lamp of its kind (the bar then acts on all of
// them), a frame size its frames, a camera's line its camera; the Notes
// block and a group head are typed into on the page itself (his call F).

/// The sheet, as `diagramsheet` sends it.
struct DiagramPage: Decodable, Equatable {
    var w: Double
    var h: Double
    var margin: Double
    var paper: String
    var orientation: String
    /// Points on the paper to a metre on the plan, and where the plan's
    /// origin lands on the paper.
    var scale: Double
    var ox: Double
    var oy: Double
    var window: [Double]
    var stated: String
    var bar: Bool
    /// How big its words and marks are drawn against their full size
    /// (`render::page_lettering`, Ref 1511).
    var words: Double?
    var marks: Double?
    var shapes: [DiagramShape]
    var items: [Item]
    var gear: [Gear]

    struct Item: Decodable, Equatable {
        /// `legend`, `head`, `frames`, `notes`, `shot`.
        var kind: String
        var key: String
        var name: String
        var count: Double
        var ids: [String]
        var box: [Double]

        var rect: CGRect {
            guard box.count == 4 else { return .zero }
            return CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        }
        /// What the click is: a legend line, a frame size or a shot picks;
        /// the notes and a lamp group's head are typed into.
        var typed: Bool { kind == "notes" || (kind == "head" && key.hasPrefix("colour:")) }
        var id: String { kind + ":" + key + ":" + ids.joined(separator: ",") }
    }

    struct Gear: Decodable, Equatable {
        var group: String
        var name: String
        var count: Double
    }

    static func == (a: DiagramPage, b: DiagramPage) -> Bool {
        a.w == b.w && a.h == b.h && a.scale == b.scale && a.ox == b.ox && a.oy == b.oy && a.items == b.items
    }
}

/// What the canvas keeps about the page between draws.
final class DiagramPageState {
    var page: DiagramPage?
    /// The sheet line under the pointer.
    var hover: String?
    /// Where the canvas's left edge was in its window, and how wide it was —
    /// so the plan stays still on screen when the sidebar folds away.
    var lastLeft: CGFloat?
    var lastWidth: CGFloat?
}

extension DiagramModel {
    var page: DiagramPage? { pageState.page }

    /// Asked again with the plan (`reload`), never mid-drag: the page fits
    /// itself to the plan, and would creep under the hand.
    func refreshPage() {
        guard let engine, let scene else { pageState.page = nil; return }
        let data = engine.call("diagramsheet", scene, "screen=1", "beat=\(max(beat, 1))",
                               "tz=\(TimeZone.current.secondsFromGMT() / 60)")
        let was = pageState.page
        pageState.page = try? JSONDecoder().decode(DiagramPage.self, from: data)
        // Another paper, or turned the other way: the new page fitted whole.
        if let was, let now = pageState.page, was.w != now.w || was.h != now.h { fitted = false; canvas?.needsDisplay = true }
        // The plan's names and marks are placed at the page's own scale and
        // lettered as it letters them (Ref 1511); a page at a new scale, or
        // the page come or gone, asks for them again, once.
        let lettered = Engine.diagramPage
        Engine.diagramZoom = namesZoom
        Engine.diagramPage = pageState.page != nil
        if abs(Engine.diagramZoomDrawn - namesZoom) / max(namesZoom, 1) > 0.002 || lettered != Engine.diagramPage { reloadShapes() }
    }

    /// A point on the paper (points), on the plan (metres) — and back.
    func pageToWorld(_ p: CGPoint) -> CGPoint {
        guard let s = page, s.scale > 0 else { return p }
        return CGPoint(x: (p.x - s.ox) / s.scale, y: (p.y - s.oy) / s.scale)
    }
    func worldToPage(_ p: CGPoint) -> CGPoint {
        guard let s = page else { return p }
        return CGPoint(x: s.ox + p.x * s.scale, y: s.oy + p.y * s.scale)
    }

    /// The paper's edges, on the plan.
    var pageWorld: CGRect? {
        guard let s = page, s.scale > 0 else { return nil }
        let a = pageToWorld(.zero)
        return CGRect(x: a.x, y: a.y, width: s.w / s.scale, height: s.h / s.scale)
    }

    /// Where the plan stands on the paper, on the plan: the dots go there
    /// and nowhere else — not under the title, nor the legend.
    var windowWorld: CGRect? {
        guard let s = page, s.window.count == 4, s.scale > 0 else { return nil }
        let a = pageToWorld(CGPoint(x: s.window[0], y: s.window[1]))
        return CGRect(x: a.x, y: a.y, width: s.window[2] / s.scale, height: s.window[3] / s.scale)
    }

    /// Paper points to screen points, at this zoom.
    func pageTransform(size: CGSize) -> CGAffineTransform? {
        guard let s = page, s.scale > 0 else { return nil }
        return CGAffineTransform(translationX: -s.ox, y: -s.oy)
            .concatenating(CGAffineTransform(scaleX: 1 / s.scale, y: 1 / s.scale))
            .concatenating(transform(size: size))
    }

    /// **The page fitted to the window** — the whole sheet, clear of the
    /// toolbar over it and the bar under it, as it would print.
    func fitPage(in size: CGSize) -> Bool {
        guard let r = pageWorld, r.width > 0, r.height > 0 else { return false }
        let right = presenting ? 0 : panelCover
        let (top, bottom, side): (CGFloat, CGFloat, CGFloat) = presenting ? (24, 24, 24) : (70, 66, 28)
        let k = min((size.width - right - 2 * side) / r.width, (size.height - top - bottom) / r.height)
        scale = min(max(k, 4), 600)
        // The page's middle in the middle of what the panels leave.
        let mid = CGPoint(x: r.midX + right / 2 / scale, y: r.midY + (bottom - top) / 2 / scale)
        centre = unturned(mid)
        fitted = true
        return true
    }

    /// The sheet's line or block at a point on the plan.
    func pageItem(at world: CGPoint) -> DiagramPage.Item? {
        guard let s = page else { return nil }
        let p = worldToPage(world)
        return s.items.first { $0.rect.insetBy(dx: -1, dy: -0.5).contains(p) }
    }

    /// The lamps, frames or camera a sheet line stands for; the FRAMES head
    /// is every frame.
    func ids(of item: DiagramPage.Item) -> [String] {
        if item.kind == "head", item.key == "frames" {
            return page?.items.filter { $0.kind == "frames" }.flatMap(\.ids) ?? []
        }
        let live = Set(plan.els.map(\.id))
        return item.ids.filter(live.contains)
    }

    /// **A click on the sheet**: a line picks what it counts; the notes or a
    /// head is typed into, right there.
    func pick(_ item: DiagramPage.Item) {
        if item.typed {
            guard !readOnly else { return }
            startTypingSheet(item.kind == "notes" ? "notes" : item.key)
            return
        }
        let ids = ids(of: item)
        guard !ids.isEmpty else { return }
        selection = ids
    }

    /// The sheet's own words typed into: `notes`, or a group head's key
    /// (`colour:added`).
    func startTypingSheet(_ key: String) {
        guard !readOnly, !presenting else { return }
        if typing != nil { endTyping(keep: true) }
        let start: String
        if key == "notes" {
            start = settings.sheet_notes
        } else {
            start = page?.items.first { $0.kind == "head" && $0.key == key }?.name ?? ""
        }
        if !selection.isEmpty { selection = [] }
        typing = DiagramTyping(el: DiagramTyping.sheet + key, what: .sheet, start: start)
    }

    /// What typing on the sheet writes: the Sheet Notes, or what that ink
    /// is called at the head of its legend lines.
    func sheetEdit(_ el: String, _ text: String) -> [String: Any]? {
        let key = String(el.dropFirst(DiagramTyping.sheet.count))
        if key == "notes" { return ["op": "settings", "set": ["sheet_notes": text]] }
        if key.hasPrefix("colour:") { return ["op": "legend", "key": key, "name": text] }
        return nil
    }
}

/// **The gear the plan uses, counted** — Copy › Gear List. The engine's
/// count (`sheet::gear`): every kind of lamp by its legend name times its
/// Count, Film Lights then Practicals, then frames by size, then grip.
enum DiagramGear {
    static func lines(_ model: DiagramModel) -> [DiagramPage.Gear] {
        if let page = model.page { return page.gear }
        guard let engine = model.engine, let scene = model.scene else { return [] }
        return (try? JSONDecoder().decode(DiagramPage.self, from: engine.call("diagramsheet", scene)))?.gear ?? []
    }

    static func text(_ model: DiagramModel) -> String {
        let all = lines(model)
        var groups: [String] = []
        for g in all where !groups.contains(g.group) { groups.append(g.group) }
        return groups.map { group in
            ([group] + all.filter { $0.group == group }.map { "\(Int($0.count)) × \($0.name)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func copy(_ model: DiagramModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(model), forType: .string)
    }
}

// MARK: - drawing it

extension DiagramCanvasView {
    /// **The desk, and the page on it.** The desk the app's own ground; the
    /// page the plan's paper, lit as the Backdrop has it.
    func drawDesk(_ cg: CGContext, _ m: DiagramModel, _ size: CGSize, paper: NSColor) {
        holdPlanStill(m, size)
        guard let r = m.pageWorld else {
            cg.setFillColor(paper.cgColor)
            cg.fill(bounds)
            return
        }
        let desk = deskDark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.122, alpha: 1)
                            : m.lit(NSColor(srgbRed: 0.79, green: 0.796, blue: 0.808, alpha: 1))
        cg.setFillColor(desk.cgColor)
        cg.fill(bounds)
        let T = m.transform(size: size)
        let sheet = r.applying(T)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 5), blur: 22,
                     color: NSColor.black.withAlphaComponent(deskDark ? 0.5 : 0.22).cgColor)
        cg.setFillColor(paper.cgColor)
        cg.fill(sheet)
        cg.restoreGState()
    }

    /// The faint dots only where the plan stands on the paper, never on the
    /// desk, the title or the legend.
    func onPage(_ cg: CGContext, _ m: DiagramModel, _ size: CGSize, _ draw: () -> Void) {
        cg.saveGState()
        if let r = m.windowWorld ?? m.pageWorld { cg.clip(to: r.applying(m.transform(size: size))) }
        draw()
        cg.restoreGState()
    }

    /// The sheet's own words and marks — the title, north, the legend, the
    /// notes, the shots — and which of its lines is picked or pointed at.
    func drawPageFurniture(_ cg: CGContext, _ m: DiagramModel, _ size: CGSize) {
        guard let s = m.page, let P = m.pageTransform(size: size) else { return }
        var painter = DiagramPainter(dark: dark, scale: m.scale / CGFloat(s.scale), engine: m.engine)
        painter.ground = m.lit(DiagramInk.color("paper", dark: dark)!)
        // Words being typed into the sheet are the typist's until kept.
        let typed: CGRect? = {
            guard let t = m.typing, t.what == .sheet else { return nil }
            let key = String(t.el.dropFirst(DiagramTyping.sheet.count))
            guard let item = s.items.first(where: { key == "notes" ? $0.kind == "notes" : ($0.kind == "head" && $0.key == key) }) else { return nil }
            let r = item.rect
            // The notes' lines, not their NOTES over them.
            return item.kind == "notes" ? CGRect(x: r.minX - 1, y: r.minY + 10, width: r.width + 2, height: r.height) : r
        }()
        for shape in s.shapes {
            if let typed, shape.k == "text", let x = shape.x, let y = shape.y, typed.contains(CGPoint(x: x, y: y)) { continue }
            painter.paint(shape, cg, P)
        }
        // The pick, and the line under the pointer.
        let picked = Set(m.selection)
        for item in s.items where !item.typed || m.typing == nil {
            let ids = Set(m.ids(of: item))
            let on = !ids.isEmpty && ids == picked
            let over = pageState(m).hover == item.id && m.tool == .select
            guard on || over else { continue }
            let box = item.rect.insetBy(dx: -3, dy: -1).applying(P)
            let path = CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil)
            if over && !on {
                cg.addPath(path)
                cg.setFillColor(DiagramInk.pick.withAlphaComponent(0.08).cgColor)
                cg.fillPath()
            }
            cg.addPath(path)
            cg.setStrokeColor(DiagramInk.pick.withAlphaComponent(on ? 1 : 0.45).cgColor)
            cg.setLineWidth(on ? 1.2 : 1)
            cg.strokePath()
        }
    }

    private func pageState(_ m: DiagramModel) -> DiagramPageState { m.pageState }

    /// **The plan holds still when the sidebar folds** — the canvas grows
    /// on its left, and the view moves its middle so nothing on the plan
    /// moves under the hand.
    private func holdPlanStill(_ m: DiagramModel, _ size: CGSize) {
        let left = convert(CGPoint.zero, to: nil).x
        let st = m.pageState
        defer { st.lastLeft = left; st.lastWidth = size.width }
        guard let was = st.lastLeft, let wide = st.lastWidth, abs(was - left) > 0.5, m.scale > 0 else { return }
        let shift = ((was - left) + (wide - size.width) / 2) / m.scale
        m.centre.x -= shift
    }

    /// A click on the sheet, nothing on the plan under it: true when it was
    /// taken.
    func pageClick(_ world: CGPoint) -> Bool {
        guard let m = model, !m.presenting, let item = m.pageItem(at: world) else { return false }
        m.pick(item)
        needsDisplay = true
        return true
    }

    /// The sheet line under the pointer, lit as a piece is.
    func pageHover(_ world: CGPoint?) -> Bool {
        guard let m = model else { return false }
        let now = world.flatMap { m.pageItem(at: $0) }
        let id = now.flatMap { item in item.typed || !m.ids(of: item).isEmpty ? item.id : nil }
        if id != m.pageState.hover {
            m.pageState.hover = id
            needsDisplay = true
        }
        return id != nil
    }

    /// Right-click on a legend line: its lamps picked, then their menu.
    func pageMenuPick(_ world: CGPoint) {
        guard let m = model, let item = m.pageItem(at: world), !item.typed else { return }
        let ids = m.ids(of: item)
        if !ids.isEmpty { m.selection = ids }
    }

    /// The typist on the sheet: over the notes' first line, or the head.
    func placeSheetTypist(_ m: DiagramModel, _ t: DiagramTyping, _ v: DiagramTypist) {
        guard let s = m.page, let P = m.pageTransform(size: bounds.size) else { return }
        let key = String(t.el.dropFirst(DiagramTyping.sheet.count))
        guard let item = s.items.first(where: { key == "notes" ? $0.kind == "notes" : ($0.kind == "head" && $0.key == key) }) else { return }
        let k = m.scale / CGFloat(s.scale)
        let notes = item.kind == "notes"
        let pt = max((notes ? 8 : 7) * k, 6)
        let font = NSFont.systemFont(ofSize: pt, weight: notes ? .regular : .semibold)
        let lineH = font.ascender - font.descender + font.leading
        // The first line's middle: under the NOTES head, or the head's own.
        let mid = notes ? CGPoint(x: item.rect.minX, y: item.rect.minY + 21.75) : CGPoint(x: item.rect.minX, y: item.rect.midY)
        let at = mid.applying(P)
        let ink = DiagramInk.color(notes ? "ink" : "ink2", dark: dark) ?? .labelColor
        if v.font != font { v.font = font }
        v.textColor = ink
        v.insertionPointColor = ink
        v.drawsBackground = true
        v.backgroundColor = m.lit(DiagramInk.color("paper", dark: dark)!)
        v.typingAttributes = [.font: font, .foregroundColor: ink, .ligature: 0]
        v.alignment = .left
        v.anchor = "start"
        v.multiline = notes
        // The notes wrap where the sheet will wrap them: the widest the
        // Notes block grows (`sheet::layout`, a little over a quarter of the
        // band, 140 to 240 points).
        if notes {
            let band = s.w - 2 * s.margin
            let widest = CGFloat(min(max(band * 0.28, 140), 240)) * k
            if v.textContainer?.containerSize.width != widest {
                v.textContainer?.containerSize = CGSize(width: widest, height: 4000)
            }
        }
        v.spot = CGPoint(x: at.x, y: at.y - lineH / 2)
        v.fit()
    }
}

// MARK: - checking it

/// The checks' verbs for the sheet on screen.
enum DiagramPageDrive {
    @MainActor
    static func perform(_ verb: String, _ args: [String], _ model: DiagramModel) -> Bool {
        func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        guard let view = model.canvas as? DiagramCanvasView else { return false }
        let size = view.bounds.size
        switch verb {
        case "page":
            // page — the sheet as drawn: paper, scale, and each line with where it is on screen
            guard let s = model.page, let P = model.pageTransform(size: size) else { say("page: none"); return true }
            let r = model.pageWorld.map { $0.applying(model.transform(size: size)) } ?? .zero
            say(String(format: "page: %@ %@ %.0fx%.0f scale %.2f bar %@ on screen %.0f,%.0f %.0fx%.0f notes \"%@\" folded %@",
                       s.paper, s.orientation, s.w, s.h, s.scale, s.bar ? "yes" : "no", r.minX, r.minY, r.width, r.height,
                       model.settings.sheet_notes, model.state?.diagramFolded == true ? "yes" : "no"))
            for (i, item) in s.items.enumerated() {
                let c = CGPoint(x: item.rect.midX, y: item.rect.midY).applying(P)
                say(String(format: "item %d: %@ %@ \"%@\" x%.0f ids %d at %.0f %.0f", i, item.kind, item.key, item.name, item.count, item.ids.count, c.x, c.y))
            }
        case "pageclick":
            // pageclick <n> [shift] — a real click on the sheet's nth line
            guard let n = args.first.flatMap(Int.init), let s = model.page, s.items.indices.contains(n),
                  let P = model.pageTransform(size: size), let window = view.window else { return true }
            let item = s.items[n]
            let c = CGPoint(x: item.rect.midX, y: item.rect.midY).applying(P)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: view.convert(c, to: nil), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
                    window.sendEvent(e)
                }
            }
        case "windowclick":
            // windowclick <x> <y> — a click anywhere in the window, in points from its top left (the top bar's buttons)
            guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]), let window = view.window,
                  let h = window.contentView?.bounds.height else { return true }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: h - y), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) {
                    window.sendEvent(e)
                }
            }
        case "gearlist":
            // gearlist — Copy › Gear List, as it would be copied
            say("gearlist: " + DiagramGear.text(model).replacingOccurrences(of: "\n", with: " | "))
        default:
            return false
        }
        return true
    }
}
