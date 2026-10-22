import SwiftUI
import AppKit

// Scenario's speed features (Lane C, 2026-09-28): Favorites, one-key adds,
// Swap, alignment guides while moving, and rigging. The engine keeps all of
// it — favorites on the film (`diagram/favorites.rs`), who rides what and
// the swap in every edit (`diagram/rigging.rs`); this file only draws the
// strip, asks, and works out where guides fall on screen.

// MARK: - favorites, as the engine sends them

/// One slot's piece: enough to draw its thumbnail.
struct DiagramFavoriteEl: Decodable, Equatable {
    var kind: String
    var sym: String?
    var w: Double?
    var h: Double?
    var text: String?
}

struct DiagramFavorite: Decodable, Equatable {
    var name: String
    var el: DiagramFavoriteEl
}

extension Engine {
    func diagramFavorites(scene: String) -> [DiagramFavorite?] {
        struct Reply: Decodable { var slots: [DiagramFavorite?] }
        return (try? JSONDecoder().decode(Reply.self, from: call("diagramfavorites", scene)))?.slots ?? []
    }

    /// A piece into a slot (nil empties it). The slots after.
    func diagramSetFavorite(scene: String, slot: Int, id: String?) -> [DiagramFavorite?]? {
        struct Reply: Decodable { var slots: [DiagramFavorite?] }
        return (try? JSONDecoder().decode(Reply.self, from: call("diagramfavoriteset", scene, String(slot), id ?? "-")))?.slots
    }

    /// A slot's add, ready to run with its middle at `p`: one piece, or a
    /// group's pieces put down as one group.
    func diagramFavoriteAt(scene: String, slot: Int, _ p: CGPoint) -> [String: Any]? {
        let data = call("diagramfavoriteat", scene, String(slot), String(Double(p.x)), String(Double(p.y)))
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["op"] as? [String: Any]
    }
}

extension DiagramModel {
    static let favoriteCount = 9

    func loadFavorites() {
        guard let engine, let scene else { favorites = []; return }
        let now = engine.diagramFavorites(scene: scene)
        if now != favorites { favorites = now }
    }

    func favorite(_ slot: Int) -> DiagramFavorite? {
        favorites.indices.contains(slot) ? favorites[slot] : nil
    }

    /// What the picked can be kept as: one piece, or one whole group (the
    /// engine keeps every piece of a group as one favorite).
    var favoriteSource: String? {
        guard let first = selection.first else { return nil }
        if selection.count == 1 { return first }
        let groups = Set(selection.compactMap { el($0)?.group })
        guard groups.count == 1, let g = groups.first, !g.isEmpty,
              selection.allSatisfy({ !(el($0)?.group ?? "").isEmpty }) else { return nil }
        return first
    }

    /// A piece into a slot, or `nil` to empty it — kept in the film.
    func setFavorite(_ slot: Int, from id: String?) {
        guard let engine, let scene, !readOnly, (0..<Self.favoriteCount).contains(slot) else { return }
        if let now = engine.diagramSetFavorite(scene: scene, slot: slot, id: id) {
            favorites = now
            state?.replace(engine.view())
        }
    }

    /// A slot's piece put down with its middle here, and picked.
    func dropFavorite(_ slot: Int, at p: CGPoint) {
        guard let engine, let scene, !readOnly else { return }
        guard let op = engine.diagramFavoriteAt(scene: scene, slot: slot, p) else { NSSound.beep(); return }
        edit(op, select: true)
        tool = .select
    }

    /// Another drawing from the library in these pieces' place.
    func swap(_ ids: [String], to sym: String) {
        guard !ids.isEmpty else { return }
        edit(["op": "swap", "ids": ids, "sym": sym])
    }

    /// **A camera's body** (SL-1217): the pack's cameras, and which one it shows.
    var bodies: [DiagramBody] { library?.cameras ?? [] }
    func body(_ e: DiagramEl) -> DiagramBody? {
        let id = e.sym.isEmpty ? (library?.camera_default ?? "") : e.sym
        return bodies.first { $0.id == id }
    }

    /// What a piece can be swapped for: the rest of its library group.
    func swapChoices(_ e: DiagramEl) -> [DiagramSymbol] {
        guard ["set", "light"].contains(e.kind), let all = library?.symbols,
              let mine = all.first(where: { $0.id == e.sym }) else { return [] }
        return all.filter { $0.group == mine.group && $0.id != mine.id }
    }
}

// MARK: - the strip

/// Where each slot is on the canvas, so a piece dragged on the plan can be
/// let go onto one.
struct DiagramFavoriteSlots: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// **Favorites** — nine slots, opened under the toolbar's last button
/// (design/24). Drag a piece from the plan (or a row of Layers) onto one to
/// keep it; click one, drag it out, or press its number to put it down —
/// the keys work whether the slots are open or not.
struct DiagramFavoritesStrip: View {
    @ObservedObject var model: DiagramModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    @State private var dropOn: Int?

    /// Its width: nine slots, the gaps between them, its edge.
    static let width: CGFloat = 9 * 42 + 8 * 3 + 10

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<DiagramModel.favoriteCount, id: \.self) { i in slot(i) }
        }
        .padding(5)
        .background(DiagramFloat(dark: dark, radius: 14))
        .onAppear { model.loadFavorites() }
    }

    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        let fav = model.favorite(i)
        let lit = model.favoriteHover == i || dropOn == i
        let tile = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fav == nil ? Brand.rule(dark).opacity(0.35) : (DiagramInk.color("paper", dark: false).map { Color(nsColor: $0) } ?? .white))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(lit ? Color(nsColor: DiagramInk.pick) : Brand.rule2(dark), lineWidth: lit ? 2 : 1)
            // The number down the left, the piece's own drawing beside it.
            if let fav { picture(fav).padding(.leading, 10).padding([.top, .bottom, .trailing], 3) }
            Text("\(i + 1)").sans(Brand.Size.tiny, weight: .semibold)
                .foregroundStyle(fav == nil ? Brand.ink2(dark) : Brand.ink2(false))
                .padding(.leading, 5).padding(.top, 3)
        }
        .frame(width: 42, height: 34)
        .contentShape(Rectangle())
        .background(GeometryReader { g in
            Color.clear.preference(key: DiagramFavoriteSlots.self, value: [i: g.frame(in: .named(DiagramMode.space))])
        })

        let base = tile
            .onTapGesture { if fav != nil { dropInView(i) } }
            .help(fav?.name ?? "")
            .contextMenu {
                if fav != nil { Button("Remove from Favorites") { model.setFavorite(i, from: nil) } }
                if let one = model.favoriteSource {
                    Button(model.selection.count > 1 ? "Add Picked Group" : "Add Picked Item") { model.setFavorite(i, from: one) }
                }
            }
            .onDrop(of: [.text], delegate: LayerDrop(slot: i, model: model, dropOn: $dropOn))
        if fav != nil {
            base.diagramDragOut("fav:\(i)") { picture(fav!).frame(width: 34, height: 34) }
        } else {
            base
        }
    }

    @ViewBuilder
    private func picture(_ fav: DiagramFavorite) -> some View {
        let e = fav.el
        if ["set", "light", "camera", "cast", "shape"].contains(e.kind) {
            DiagramGlyph(kind: e.kind, sym: e.sym ?? "", w: e.w ?? 1, h: e.h ?? 1,
                         rot: e.kind == "light" || e.kind == "camera" ? -90 : 0, engine: model.engine)
                .padding(3)
        } else {
            Text(fav.name).sans(Brand.Size.tiny).foregroundStyle(Brand.ink2(false))
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(2)
        }
    }

    /// Clicked: put down in the middle of what is on screen.
    private func dropInView(_ i: Int) {
        guard let canvas = model.canvas else { return }
        let size = canvas.bounds.size
        model.dropFavorite(i, at: model.toWorld(CGPoint(x: size.width / 2, y: size.height / 2), size: size))
    }

    /// A row of Layers dropped on a slot keeps that piece there.
    private struct LayerDrop: DropDelegate {
        let slot: Int
        let model: DiagramModel
        @Binding var dropOn: Int?

        func validateDrop(info: DropInfo) -> Bool { !model.readOnly }
        func dropEntered(info: DropInfo) { dropOn = slot }
        func dropExited(info: DropInfo) { if dropOn == slot { dropOn = nil } }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
        func performDrop(info: DropInfo) -> Bool {
            dropOn = nil
            guard let item = info.itemProviders(for: [.text]).first else { return false }
            item.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String, s.hasPrefix(DiagramLayers.dragPrefix),
                      let id = s.dropFirst(DiagramLayers.dragPrefix.count).split(separator: ",").first else { return }
                DispatchQueue.main.async { model.setFavorite(slot, from: String(id)) }
            }
            return true
        }
    }
}

// MARK: - rigging, for the lists

enum DiagramRigs {
    /// The pieces riding something on this plan (and in no group — a group
    /// lists its own).
    static func riding(_ els: [DiagramEl]) -> Set<String> {
        let ids = Set(els.map(\.id))
        return Set(els.filter { e in e.group.isEmpty && ids.contains(e.rig_on ?? "") && e.rig_on != e.id }.map(\.id))
    }

    /// What rides this piece, and what rides that, top of the stack first.
    static func riders(of id: String, in els: [DiagramEl], depth: Int = 0) -> [(DiagramEl, Int)] {
        guard depth < 8 else { return [] }
        var out: [(DiagramEl, Int)] = []
        for e in els.reversed() where e.rig_on == id && e.group.isEmpty && e.id != id {
            out.append((e, depth + 1))
            out += riders(of: e.id, in: els, depth: depth + 1)
        }
        return out
    }

    /// These pieces and everything riding them — what a move carries.
    static func carried(_ ids: [String], in els: [DiagramEl]) -> Set<String> {
        var out = Set(ids)
        var grew = true
        while grew {
            grew = false
            for e in els where !out.contains(e.id) && out.contains(e.rig_on ?? "") {
                out.insert(e.id)
                grew = true
            }
        }
        return out
    }
}

// MARK: - alignment guides

/// **Alignment guides**, Scenario's snap-align: while pieces are moved with
/// Snap on, a thin line where one of their points lines up with a point of
/// another piece on screen, and a pull onto it when within a few points —
/// ahead of the grid. A camera, lamp, person or words line up by their
/// middle; a set piece, frame, shape or picture by its corners and middle;
/// a wall, track or arrow by its ends and middle. Worked out on screen, so
/// they are true however the plan is turned. ⌘ held, or Snap off, moves free.
enum DiagramGuides {
    static let reach: CGFloat = 6

    /// The points a piece lines up by, on screen, where it stands at the
    /// showing beat.
    static func points(_ e: DiagramEl, _ m: DiagramModel, _ size: CGSize) -> [CGPoint] {
        var pts: [CGPoint]
        if e.isWall {
            pts = e.corners
        } else if e.isLine {
            pts = [CGPoint(x: e.x, y: e.y), CGPoint(x: e.x2, y: e.y2), CGPoint(x: (e.x + e.x2) / 2, y: (e.y + e.y2) / 2)]
        } else if e.isPolyline {
            pts = e.points.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        } else {
            let now = e.at(beat: m.beat)
            pts = [CGPoint(x: now.x, y: now.y)]
            let centred = ["camera", "cast", "text"].contains(e.kind) || (e.kind == "light" && e.sym != DiagramFrames.sym)
            if !centred {
                let (w, h) = e.footprint(at: m.beat)
                let r = now.rot * .pi / 180
                let (c, s) = (cos(r), sin(r))
                pts += [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)].map { x, y in
                    CGPoint(x: now.x + x * c - y * s, y: now.y + x * s + y * c)
                }
            }
        }
        return pts.map { m.toView($0, size: size) }
    }

    /// The move, lined up with another piece where the hand (`raw`, before
    /// the grid) has it nearly lined up, and on the grid (`delta`) where it
    /// has not — plan metres — and the lines to draw on screen.
    /// `lock`: a way ⇧ holds still, never lined up along. `keep`: whether a
    /// line-up may be taken — along x or not, and the plan move it would make
    /// that way — which is how the grid wins over a line-up that would leave
    /// the piece off it.
    static func snap(_ m: DiagramModel, size: CGSize, ids: [String], raw: CGPoint, delta: CGPoint,
                     lock: (Bool, Bool) = (false, false),
                     keep: ((Bool, CGFloat) -> Bool)? = nil) -> (CGPoint, [[CGPoint]], [String]) {
        guard m.settings.snap else { return (delta, [], []) }
        let moving = DiagramRigs.carried(ids, in: m.plan.els)
        let unseen = m.unseenIds
        let mine = ids.compactMap { m.el($0) }.flatMap { points($0, m, size) }
        guard !mine.isEmpty else { return (delta, [], []) }
        // Each point with the piece it is of, so the piece lined up with can
        // light up.
        let owned = m.plan.els
            .filter { !moving.contains($0.id) && !$0.hidden && !unseen.contains($0.id) && $0.kind != "image" }
            .flatMap { e in points(e, m, size).map { ($0, e.id) } }
        let others = owned.map(\.0)
        let o = m.toView(.zero, size: size)
        let d = m.toView(delta, size: size), h = m.toView(raw, size: size)
        var off = CGPoint(x: h.x - o.x, y: h.y - o.y)

        func best(_ x: Bool) -> CGFloat? {
            if x ? lock.0 : lock.1 { return nil }
            var found: CGFloat?
            for want in others {
                for have in mine {
                    let gap = x ? want.x - (have.x + off.x) : want.y - (have.y + off.y)
                    guard abs(gap) <= reach, found == nil || abs(gap) < abs(found!) else { continue }
                    // The plan move this line-up makes that way (the plan is
                    // never turned on screen: `DiagramModel.turn`).
                    if let keep, !keep(x, ((x ? off.x : off.y) + gap) / m.scale) { continue }
                    found = gap
                }
            }
            return found
        }
        let bx = best(true), by = best(false)
        off.x = bx.map { off.x + $0 } ?? d.x - o.x
        off.y = by.map { off.y + $0 } ?? d.y - o.y
        let now = mine.map { CGPoint(x: $0.x + off.x, y: $0.y + off.y) }

        var lines: [[CGPoint]] = []
        var with: [String] = []
        for x in Set(now.map { ($0.x * 2).rounded() / 2 }) where bx != nil {
            let on = (now + others).filter { abs($0.x - x) < 0.5 }
            guard on.contains(where: { p in others.contains { $0 == p } }), let y0 = on.map(\.y).min(), let y1 = on.map(\.y).max() else { continue }
            lines.append([CGPoint(x: x, y: y0 - 8), CGPoint(x: x, y: y1 + 8)])
            for (p, id) in owned where abs(p.x - x) < 0.5 && !with.contains(id) { with.append(id) }
        }
        for y in Set(now.map { ($0.y * 2).rounded() / 2 }) where by != nil {
            let on = (now + others).filter { abs($0.y - y) < 0.5 }
            guard on.contains(where: { p in others.contains { $0 == p } }), let x0 = on.map(\.x).min(), let x1 = on.map(\.x).max() else { continue }
            lines.append([CGPoint(x: x0 - 8, y: y), CGPoint(x: x1 + 8, y: y)])
            for (p, id) in owned where abs(p.y - y) < 0.5 && !with.contains(id) { with.append(id) }
        }
        let a = m.toWorld(o, size: size)
        let b = m.toWorld(CGPoint(x: o.x + off.x, y: o.y + off.y), size: size)
        return (CGPoint(x: b.x - a.x, y: b.y - a.y), lines, with)
    }

    /// **Flush against a wall** (master list 3). A piece's edge near a wall's
    /// face — either face — lines up with it; a set piece or shape pushed
    /// into a wall stops at the face on its own side, rather than sinking to
    /// the wall's middle. Pulled right through, it goes through. After the
    /// grid: a face is half a wall off the grid, and the face wins. Square
    /// stretches only; ⌘ (the caller) lets it go free.
    static func faces(_ m: DiagramModel, size: CGSize, ids: [String], delta: CGPoint,
                      lock: (Bool, Bool) = (false, false)) -> (CGPoint, [[CGPoint]]) {
        let movingEls = ids.compactMap { m.el($0) }
        let bodies = movingEls.filter { !$0.isLine && !$0.isPolyline && !["door", "window", "opening", "image", "text", "note"].contains($0.kind) }
        guard !bodies.isEmpty, !movingEls.contains(where: \.isLine) else { return (delta, []) }
        let moving = DiagramRigs.carried(ids, in: m.plan.els)
        let mine = bodies.flatMap { points($0, m, size) }
        let o = m.toView(.zero, size: size)
        let dv = m.toView(delta, size: size)
        var off = CGPoint(x: dv.x - o.x, y: dv.y - o.y)
        guard let x0 = mine.map(\.x).min(), let x1 = mine.map(\.x).max(),
              let y0 = mine.map(\.y).min(), let y1 = mine.map(\.y).max() else { return (delta, []) }
        let box = CGRect(x: x0 + off.x, y: y0 + off.y, width: x1 - x0, height: y1 - y0)
        let pushes = bodies.contains { ["set", "shape"].contains($0.kind) }
        // Best adjustment each way: true is up and down (a level wall's face).
        var best: [Bool: (adj: CGFloat, stop: Bool, line: [CGPoint])] = [:]
        for w in m.plan.els where w.isWall && !moving.contains(w.id) && !w.hidden {
            let half = CGFloat(w.thick) / 2 * m.scale
            for st in w.stretches {
                let (va, vb) = (m.toView(st.0, size: size), m.toView(st.1, size: size))
                let level = abs(va.y - vb.y) < 0.5, upright = abs(va.x - vb.x) < 0.5
                guard level || upright, !(level ? lock.1 : lock.0) else { continue }
                let (lo, hi) = level ? (min(va.x, vb.x), max(va.x, vb.x)) : (min(va.y, vb.y), max(va.y, vb.y))
                let c = level ? va.y : va.x
                let (b0, b1) = level ? (box.minY, box.maxY) : (box.minX, box.maxX)
                let (s0, s1) = level ? (box.minX, box.maxX) : (box.minY, box.maxY)
                guard s1 > lo + 1, s0 < hi - 1 else { continue }
                var adj: CGFloat?
                var face: CGFloat = 0
                var stop = false
                let into = b1 > c - half + 0.5 && b0 < c + half - 0.5
                let through = b0 < c - half && b1 > c + half
                if pushes, into, !through {
                    if (b0 + b1) / 2 < c { adj = (c - half) - b1; face = c - half } else { adj = (c + half) - b0; face = c + half }
                    stop = true
                } else if !into {
                    for (edge, f) in [(b0, c - half), (b0, c + half), (b1, c - half), (b1, c + half)] where abs(f - edge) <= reach {
                        if adj == nil || abs(f - edge) < abs(adj!) { adj = f - edge; face = f }
                    }
                }
                guard let a = adj else { continue }
                if let cur = best[level], (cur.stop && !stop) || (cur.stop == stop && abs(cur.adj) <= abs(a)) { continue }
                let line = level ? [CGPoint(x: lo, y: face), CGPoint(x: hi, y: face)] : [CGPoint(x: face, y: lo), CGPoint(x: face, y: hi)]
                best[level] = (a, stop, line)
            }
        }
        if let h = best[true] { off.y += h.adj }
        if let v = best[false] { off.x += v.adj }
        let a = m.toWorld(o, size: size)
        let b = m.toWorld(CGPoint(x: o.x + off.x, y: o.y + off.y), size: size)
        return (CGPoint(x: b.x - a.x, y: b.y - a.y), best.values.map(\.line))
    }

    static func draw(_ lines: [[CGPoint]], _ cg: CGContext) {
        guard !lines.isEmpty else { return }
        cg.saveGState()
        cg.setStrokeColor(DiagramInk.pick.cgColor)
        cg.setLineWidth(1)
        for l in lines where l.count == 2 {
            cg.move(to: l[0])
            cg.addLine(to: l[1])
        }
        cg.strokePath()
        cg.restoreGState()
    }
}

extension DiagramMode {
    /// The canvas's own space, which the favorite slots report themselves in.
    static let space = "diagramCanvas"
}

// MARK: - the checks' verbs (`studio/diagram.sh`, block 13)

enum DiagramSpeedDrive {
    /// `fav <n>` the picked piece into slot n (the menu's Add to Favorites) ·
    /// `favclear <n>` · `favs` print the slots · `favdrag <n>` drag the
    /// picked piece onto slot n with the mouse · `swap <sym>` the menu's
    /// Swap With · `guides` the guides showing mid-drag, and where the picked
    /// piece is.
    /// Where `lineup` left the mouse held, for `letgo`.
    @MainActor static var held: (CGPoint, NSEvent.ModifierFlags)?

    @MainActor
    static func perform(_ verb: String, _ args: [String], _ model: DiagramModel,
                        pull: (CGPoint, Double, Double) -> Void,
                        post: (NSEvent.EventType, CGPoint, NSEvent.ModifierFlags) -> Void) {
        let n = args.first.flatMap(Int.init).map { $0 - 1 }
        func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        switch verb {
        case "fav": if let n, let id = model.selection.first { model.setFavorite(n, from: id) }
        case "favclear": if let n { model.setFavorite(n, from: nil) }
        case "favs":
            model.loadFavorites()
            say("favs: " + (0..<DiagramModel.favoriteCount).map { "\($0 + 1)=\(model.favorite($0)?.name ?? "-")" }.joined(separator: " | "))
        case "favdrag":
            // favdrag <n> — the first picked piece dragged onto slot n (the
            // slots must be open under Favorites: `favorites on` first)
            guard let n, let slot = model.favoriteSlots[n], let view = model.canvas as? DiagramCanvasView,
                  let id = model.selection.first, let p = view.pointOf(id) else { say("drive: no slot"); return }
            pull(p, slot.midX - p.x, slot.midY - p.y)
        case "favorites":
            // favorites <on|off> — the toolbar's Favorites, its slots open or shut
            model.showingFavorites = args.first != "off"
        case "swap": if let sym = args.first { model.swap(model.selection, to: sym) }
        case "lineup":
            // lineup <i> <j> <dx> <dy> [command] — take piece i by its middle
            // and drag it to dx, dy points off piece j's middle, and hold it
            // there (`letgo` lets go)
            let v = args.prefix(4).compactMap(Double.init)
            guard v.count == 4, let view = model.canvas as? DiagramCanvasView,
                  model.plan.els.indices.contains(Int(v[0])), model.plan.els.indices.contains(Int(v[1])),
                  let a = view.pointOf(model.plan.els[Int(v[0])].id), let b = view.pointOf(model.plan.els[Int(v[1])].id) else { return }
            let f: NSEvent.ModifierFlags = args.contains("command") ? [.command] : []
            let to = CGPoint(x: b.x + v[2], y: b.y + v[3])
            post(.leftMouseDown, a, f)
            for i in 1...8 {
                let k = CGFloat(i) / 8
                post(.leftMouseDragged, CGPoint(x: a.x + (to.x - a.x) * k, y: a.y + (to.y - a.y) * k), f)
            }
            held = (to, f)
        case "letgo":
            if let (p, f) = held { post(.leftMouseUp, p, f); held = nil }
        case "haulby":
            // haulby <index> <fx> <fy> <dx> <dy> — take a piece by a point of
            // its own (fx, fy from -1 to 1 across it: a stand by its leg, not
            // the lamp on top) and drag it this far
            let v = args.compactMap(Double.init)
            guard v.count >= 5, model.plan.els.indices.contains(Int(v[0])), let canvas = model.canvas else { return }
            let e = model.plan.els[Int(v[0])]
            let now = e.at(beat: model.beat)
            let r = now.rot * .pi / 180
            let (lx, ly) = (v[1] * e.w / 2, v[2] * e.h / 2)
            let p = model.toView(CGPoint(x: now.x + lx * cos(r) - ly * sin(r), y: now.y + lx * sin(r) + ly * cos(r)),
                                 size: canvas.bounds.size)
            pull(p, v[3], v[4])
        case "guides":
            let lines = (model.canvas as? DiagramCanvasView)?.guides ?? []
            let at = model.shownPicked.first.map { e -> String in
                let now = e.at(beat: model.beat)
                return String(format: "%.3f,%.3f", now.x, now.y)
            } ?? "-"
            // …and the pieces lined up with, by kind ("with cast light").
            let with = ((model.canvas as? DiagramCanvasView)?.linedUp ?? []).compactMap { model.el($0)?.kind }
            say("guides: \(lines.count) at \(at)" + (with.isEmpty ? "" : " with \(with.joined(separator: " "))"))
        default: break
        }
    }
}
