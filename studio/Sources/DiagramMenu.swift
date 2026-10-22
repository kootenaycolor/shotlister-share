import SwiftUI
import AppKit

// **One menu for a pick** (Back to Paper, Batch 2, design/32 item 8): the
// bar's More and the right-click are the same menu, built here. Each kind
// first — what is rarely changed, in the order the bar would have it — then
// what every piece has: Swap, Favorites, the clipboard, Arrange, Lock, Hide,
// Delete. Details… opens the side panel, the one way to exact numbers.

/// What is picked, as the bar and its menu see it.
enum DiagramPick {
    case none
    /// One lamp with a label of its own.
    case lamp(DiagramEl)
    /// A shared label, or one of its lamps: the label, and every lamp on it.
    case shared(label: DiagramEl, lamps: [DiagramEl])
    /// Several lamps of one kind — a legend line picked, or a hand's pick.
    case kind([DiagramEl])
    case one(DiagramEl)
    case several([DiagramEl])

    static func of(_ picked: [DiagramEl], _ m: DiagramModel) -> DiagramPick {
        guard !picked.isEmpty else { return .none }
        let lamps = picked.filter { DiagramMarks.isLamp($0, m) }
        // A shared label: the label, any of its lamps, or both.
        let labels = Set(picked.compactMap { e -> String? in
            if m.isSharedLabel(e) { return e.id }
            if DiagramMarks.canShare(e), let l = m.sharedLabel(of: e) { return l.id }
            return nil
        })
        if labels.count == 1, let id = labels.first, let label = m.el(id),
           picked.allSatisfy({ $0.id == id || $0.tie_to == id }) {
            return .shared(label: label, lamps: m.tied(to: id))
        }
        if picked.count == 1, let e = picked.first {
            return DiagramMarks.isLamp(e, m) ? .lamp(e) : .one(e)
        }
        // Several lamps of one kind: one legend line — one symbol and one
        // Name (2026-10-05).
        if lamps.count == picked.count, let first = lamps.first {
            let key = first.legend_key ?? first.look ?? ""
            if lamps.allSatisfy({ ($0.legend_key ?? $0.look ?? "") == key }) { return .kind(lamps) }
        }
        return .several(picked)
    }

    /// The lamps a lamp setting acts on.
    var lamps: [DiagramEl] {
        switch self {
        case .lamp(let e): return [e]
        case .shared(_, let lamps): return lamps
        case .kind(let lamps): return lamps
        default: return []
        }
    }
}

@MainActor
enum DiagramMenu {
    /// Right-click with nothing picked.
    static func nothing(_ m: DiagramModel, fit: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureItem("Paste") { m.paste() })
        menu.addItem(ClosureItem("Select All", key: "a") { m.selection = m.plan.els.filter { !$0.locked && !$0.hidden }.map(\.id) })
        let hidden = m.plan.els.filter(\.hidden).map(\.id)
        if !hidden.isEmpty {
            menu.addItem(ClosureItem(hidden.count == 1 ? "Show Hidden Item" : "Show \(hidden.count) Hidden Items") {
                m.update(hidden, ["hidden": false])
                m.selection = hidden
            })
        }
        let locked = m.plan.els.filter(\.locked).map(\.id)
        if !locked.isEmpty {
            menu.addItem(ClosureItem("Unlock All") { m.update(locked, ["locked": false]) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureItem("Zoom to Fit", key: "0", run: fit))
        return menu
    }

    /// **The pick's menu**: More on the bar and the right-click both. `folded`:
    /// what the bar had no room for, first.
    static func picked(_ m: DiagramModel, folded: [NSMenuItem] = []) -> NSMenu {
        let menu = NSMenu()
        folded.forEach(menu.addItem)
        if !folded.isEmpty { menu.addItem(.separator()) }
        own(menu, m)
        details(menu, m)
        menu.addItem(.separator())
        common(menu, m)
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }

    // MARK: each kind's own

    private static func own(_ menu: NSMenu, _ m: DiagramModel) {
        let pick = DiagramPick.of(m.picked, m)
        switch pick {
        case .none: return
        case .lamp(let e):
            menu.addItem(spread(e, m))
            labelItems(menu, [e], m)
            aimItem(menu, e, m)
            if !m.readOnly { menu.addItem(opacity(e, m)) }
        case .shared(let label, _):
            let lone = m.picked.count == 1 ? m.picked.first : nil
            if let lamp = lone, lamp.id != label.id {
                menu.addItem(ClosureItem("Own Label") { m.edit(["op": "own_label", "ids": [lamp.id]]) })
                menu.addItem(count(lamp, m))
            } else {
                menu.addItem(ClosureItem("Own Label") { m.edit(["op": "own_label", "ids": [label.id]]) })
            }
            labelItems(menu, [label], m)
        case .kind(let lamps):
            menu.addItem(type(lamps, m))
            menu.addItem(gels(lamps, m))
            colourMany(menu, lamps, m)
            if lamps.count >= 2 { menu.addItem(ClosureItem("Share Label") { m.shareLabel() }) }
            if lamps.contains(where: { !($0.tie_to ?? "").isEmpty }) {
                menu.addItem(ClosureItem("Own Label") { m.edit(["op": "own_label", "ids": lamps.map(\.id)]) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureItem("Copy Gear List") { DiagramGear.copy(m) })
            // Picked from the sheet's legend: the legend itself can go.
            if m.settings.legend, !m.readOnly {
                menu.addItem(ClosureItem("Hide Legend") { m.setting("legend", false) })
            }
        case .several(let all):
            colourMany(menu, all, m)
            if all.count > 2 {
                menu.addItem(sub("Space Evenly", [ClosureItem("Across") { m.distribute("x") }, ClosureItem("Down") { m.distribute("y") }]))
            }
            let lamps = all.filter { DiagramMarks.canShare($0) }
            if lamps.count >= 2 { menu.addItem(ClosureItem("Share Label") { m.shareLabel() }) }
            if lamps.contains(where: { !($0.tie_to ?? "").isEmpty }) {
                menu.addItem(ClosureItem("Own Label") { m.edit(["op": "own_label", "ids": lamps.map(\.id)]) })
            }
            let named = all.filter(DiagramNames.hasName)
            if !named.isEmpty { labelItems(menu, named, m) }
        case .one(let e):
            oneOwn(menu, e, m)
        }
    }

    private static func oneOwn(_ menu: NSMenu, _ e: DiagramEl, _ m: DiagramModel) {
        switch e.kind {
        case "light" where e.sym == DiagramFrames.sym:
            // Its Note (2026-10-05): the first line is its size and cloth.
            // Pipe and Grid are kept on the frame but draw nothing on a plot.
            menu.addItem(ClosureItem("Note…") { m.startTyping(e.id, .note) })
            colour(menu, e, m)
            menu.addItem(sub("Lean", [("Flat", 0.0), ("Half", 45.0), ("Upright", 90.0)].map { n, v in
                choice(n, on: abs(e.tilt - v) < 0.5) { m.update([e.id], ["tilt": v]) }
            }))
            labelItems(menu, [e], m)
        case "light":
            // Grip: a flag, a net, a stand.
            colour(menu, e, m)
            labelItems(menu, [e], m)
        case "camera":
            menu.addItem(toggle("Lens Cone", e.cone) { m.update([e.id], ["cone": !e.cone]) })
            menu.addItem(toggle("Frame on Plan", e.frame_on ?? false) { DiagramNames.setFrame(!(e.frame_on ?? false), e, model: m) })
            let onTrack = m.el(e.rig_on ?? "").map { $0.kind == "track" || ($0.kind == "set" && $0.sym.contains("circle-track")) } ?? false
            let anyTrack = m.plan.els.contains { $0.kind == "track" || ($0.kind == "set" && $0.sym.contains("circle-track")) }
            if onTrack { menu.addItem(ClosureItem("Unlock from Track") { m.update([e.id], ["rig_on": ""]) }) }
            else if anyTrack { menu.addItem(ClosureItem("Ride Track") { m.edit(["op": "ride", "id": e.id]) }) }
            colour(menu, e, m)
            labelItems(menu, [e], m)
            aimItem(menu, e, m)
            if !e.shot.isEmpty { menu.addItem(ClosureItem("Show in Shot List") { [weak m] in m?.showInShotList(e.shot) }) }
        case "cast":
            colour(menu, e, m)
            menu.addItem(ClosureItem("Larger") { m.update([e.id], ["w": e.w * 1.25, "h": e.h * 1.25]) })
            menu.addItem(ClosureItem("Smaller") { m.update([e.id], ["w": max(e.w * 0.8, 0.05), "h": max(e.h * 0.8, 0.05)]) })
            labelItems(menu, [e], m)
            aimItem(menu, e, m)
        case "text", "note":
            colour(menu, e, m)
            menu.addItem(sub("Align", [("left", "Left"), ("", "Centre"), ("right", "Right")].map { v, n in
                choice(n, on: (e.align == "centre" || e.align == "center" ? "" : e.align) == v) { m.update([e.id], ["align": v]) }
            }))
        case _ where e.isWall || e.isPath:
            menu.addItem(ClosureItem("Name…") { m.startTyping(e.id) })
            menu.addItem(sub("Kind", [("line", "Line"), ("wall", "Wall"), ("object", "Object")].map { v, n in
                choice(n, on: (e.isWall ? "wall" : (e.fill && e.isClosed ? "object" : "line")) == v) { m.setPathKind(e, v) }
            }))
            if e.isClosed { menu.addItem(toggle("Fill", e.isFilled) { m.setFilled(e, !e.isFilled) }) }
            colour(menu, e, m)
            if e.isWall, m.pickedCorner.map({ $0 < e.corners.count }) == true {
                menu.addItem(ClosureItem("Delete Corner") { m.removeCorner() })
            }
        case "door":
            let style = DoorStyle.of(e)
            menu.addItem(sub("Style", DoorStyle.allCases.map { k in
                choice(k.title, on: style == k) { m.update([e.id], k.change(e)) }
            }))
            menu.addItem(ClosureItem("Flip Side") { m.update([e.id], ["flip": !e.flip]) })
        case "window", "opening":
            menu.addItem(ClosureItem("Flip Side") { m.update([e.id], ["flip": !e.flip]) })
        case "set":
            // A set piece on a plot is drawn in the set's grey, never its
            // own colour or fill (kept, not offered: 2026-10-05).
            menu.addItem(ClosureItem("Larger") { m.update([e.id], ["w": e.w * 1.25, "h": e.h * 1.25]) })
            menu.addItem(ClosureItem("Smaller") { m.update([e.id], ["w": max(e.w * 0.8, 0.05), "h": max(e.h * 0.8, 0.05)]) })
            labelItems(menu, [e], m)
        case "image":
            // Its strength stays as he set it (2026-10-15), whichever it shows as.
            menu.addItem(sub("Show As", [(false, "Background"), (true, "Photo")].map { photo, n in
                choice(n, on: (e.role == "photo") == photo) { m.update([e.id], ["role": photo ? "photo" : ""]) }
            }))
            if !m.readOnly {
                menu.addItem(ClosureItem("Draw on Photo") { m.drawOnPhoto(e.id) })
                if m.marksLyingOn(e) > 0 {
                    menu.addItem(ClosureItem("Attach to Photo") { m.attachMarks(to: e.id) })
                }
            }
            if !e.locked { menu.addItem(ClosureItem("Set Scale…") { m.calibrating = e.id }) }
        case "measure":
            menu.addItem(toggle("Behind Everything", e.under ?? false) { m.update([e.id], ["under": !(e.under ?? false)]) })
            if let i = m.pickedCorner, i < e.corners.count {
                if e.lock(i) != nil { menu.addItem(ClosureItem("Unlock Marker") { m.lockMarker(e, to: nil) }) }
                if e.corners.count > 2 {
                    menu.addItem(ClosureItem("Delete Marker") {
                        m.edit(m.wallOp("wall_remove_corner", e, ["corner": i])); m.pickedCorner = nil
                    })
                }
            }
        case "track", "road":
            menu.addItem(ClosureItem("Name…") { m.startTyping(e.id) })
        case "arrow":
            menu.addItem(ClosureItem("Name…") { m.startTyping(e.id) })
            colour(menu, e, m)
            menu.addItem(sub("Weight", [0.8, 1.2, 2.0, 3.0].map { w in
                choice(w == w.rounded() ? "\(Int(w)) pt" : String(format: "%.1f pt", w), on: abs(e.weight - w) < 0.05) { m.update([e.id], ["weight": w]) }
            }))
        case "shape":
            menu.addItem(ClosureItem("Name…") { m.startTyping(e.id) })
            colour(menu, e, m)
        case "cable", "stroke":
            if e.kind == "cable" { menu.addItem(ClosureItem("Name…") { m.startTyping(e.id) }) }
            colour(menu, e, m)
        default:
            break
        }
    }

    // MARK: pieces of it

    /// Hide Label / Show Label, Reset Label — for what has a name on the plan.
    private static func labelItems(_ menu: NSMenu, _ els: [DiagramEl], _ m: DiagramModel) {
        // A lamp of a shared label wears that label: Hide Label hides it,
        // as the portal does (fix round 2).
        var seen = Set<String>()
        let worn = els.map { m.sharedLabel(of: $0) ?? $0 }.filter { seen.insert($0.id).inserted }
        let named = worn.filter { DiagramNames.hasName($0) || m.isSharedLabel($0) }
        guard !named.isEmpty else { return }
        let hidden = named.allSatisfy { $0.label_hidden == true }
        menu.addItem(ClosureItem(hidden ? "Show Label" : "Hide Label") { m.update(named.map(\.id), ["label_hidden": !hidden]) })
        if named.contains(where: { ($0.label_dx ?? 0) != 0 || ($0.label_dy ?? 0) != 0 }) {
            menu.addItem(ClosureItem("Reset Label") { m.update(named.map(\.id), ["label_dx": 0, "label_dy": 0]) })
        }
    }

    /// **Send to Set / Send to Plot, Copy to …** (his ask, 2026-10-17): for
    /// one or several picked pieces that can stand in either view.
    static func layerItems(_ menu: NSMenu, _ m: DiagramModel) {
        guard !m.readOnly else { return }
        let ids = m.picked.filter(DiagramModel.canSend).map(\.id)
        guard !ids.isEmpty else { return }
        let to = DiagramModel.otherLayer(m.picked.filter(DiagramModel.canSend), m)
        let name = to == "set" ? "Set" : "Plot"
        menu.addItem(ClosureItem("Send to \(name)") { m.sendLayer(ids, to: to, copy: false) })
        menu.addItem(ClosureItem("Copy to \(name)") { m.sendLayer(ids, to: to, copy: true) })
    }

    /// **One Color for several** (his ask, 2026-10-17): every picked piece
    /// takes it, one step of undo; ticked only when they all wear it.
    static func colourMany(_ menu: NSMenu, _ els: [DiagramEl], _ m: DiagramModel) {
        guard !m.readOnly, els.count > 1 else { return }
        let ids = els.map(\.id)
        let now = Set(els.map { $0.color.uppercased() })
        let one = now.count == 1 ? now.first : nil
        var items: [NSMenuItem] = []
        if now.count > 1 {
            let mixed = NSMenuItem(title: "Mixed", action: nil, keyEquivalent: "")
            mixed.isEnabled = false
            items.append(mixed)
        }
        items.append(choice("None", on: one == "") { m.update(ids, ["color": ""]) })
        for (i, hex) in Columns.palette.enumerated() {
            let tag = "#" + hex.uppercased()
            items.append(choice(Columns.paletteNames[i], on: one == tag) { m.update(ids, ["color": tag]) })
        }
        items.append(.separator())
        items.append(ClosureItem("Other Color…") { ColourPanel.shared.open(one ?? "") { m.update(ids, ["color": $0]) } })
        menu.addItem(sub("Color", items))
    }

    private static func aimItem(_ menu: NSMenu, _ e: DiagramEl, _ m: DiagramModel) {
        if !e.aim.isEmpty { menu.addItem(ClosureItem("Stop Aiming") { m.update([e.id], ["aim": ""]) }) }
    }

    /// Details…, ticked while it is open.
    private static func details(_ menu: NSMenu, _ m: DiagramModel) {
        let item = ClosureItem("Details…") { m.toggleDetails() }
        item.state = m.detailsShown ? .on : .off
        menu.addItem(.separator())
        menu.addItem(item)
    }

    /// A string of lamps: One, Line or Ring.
    static func spread(_ e: DiagramEl, _ m: DiagramModel) -> NSMenuItem {
        let now = e.spread ?? ""
        return sub("Spread", [("", "One"), ("line", "Line"), ("ring", "Ring")].map { v, n in
            choice(n, on: now == v) { setSpread(e, v, m) }
        })
    }

    /// A lamp made one, a line or a ring, sized to start as one.
    static func setSpread(_ e: DiagramEl, _ v: String, _ m: DiagramModel) {
        let now = e.spread ?? ""
        var set: [String: Any] = ["spread": v]
        if v == "line", now != "line" { set["w"] = 0.3; set["h"] = max(e.h, 3.0); set["curve"] = 0.0; set["count"] = max(e.count ?? 1, 6) }
        if v == "ring", now != "ring" { set["w"] = 3.0; set["h"] = 3.0; set["count"] = max(e.count ?? 1, 8) }
        if v == "", now != "" { set["w"] = 0.3; set["h"] = 0.3; set["curve"] = 0.0 }
        m.update([e.id], set)
    }

    /// How many units under one mark.
    static func count(_ e: DiagramEl, _ m: DiagramModel) -> NSMenuItem {
        let now = Int(e.count ?? 1)
        return sub("Count · \(now)", (1...12).map { n in choice("\(n)", on: now == n) { m.update([e.id], ["count": Double(n)]) } })
    }

    /// Film Light, Practical, Existing — for every one of these lamps.
    static func type(_ lamps: [DiagramEl], _ m: DiagramModel) -> NSMenuItem {
        let now = Set(lamps.map(DiagramMarks.type(of:)))
        return sub("Type", DiagramMarks.types.map { t in
            choice(t.title, on: now == [t.key]) { m.update(lamps.map(\.id), DiagramMarks.typeSet(t.key)) }
        })
    }

    /// Gels on every one of these lamps: a gel all of them have comes off,
    /// else goes on.
    static func gels(_ lamps: [DiagramEl], _ m: DiagramModel) -> NSMenuItem {
        sub("Gel", DiagramGels.groups.flatMap { group, gels -> [NSMenuItem] in
            let head = NSMenuItem(title: group, action: nil, keyEquivalent: "")
            head.isEnabled = false
            return [head] + gels.map { g in
                let all = lamps.allSatisfy { $0.gels.contains(g.id) }
                return choice(g.name, on: all) {
                    for l in lamps {
                        let next = all ? l.gels.filter { $0 != g.id } : (l.gels.contains(g.id) ? l.gels : l.gels + [g.id])
                        m.setGels([l.id], next)
                    }
                }
            }
        })
    }

    static func colour(_ menu: NSMenu, _ e: DiagramEl, _ m: DiagramModel) {
        var items: [NSMenuItem] = []
        if DiagramActions.colours(e) != false { items.append(choice("None", on: e.color.isEmpty) { m.update([e.id], ["color": ""]) }) }
        for (i, hex) in Columns.palette.enumerated() {
            let tag = "#" + hex.uppercased()
            items.append(choice(Columns.paletteNames[i], on: e.color.uppercased() == tag) { m.update([e.id], ["color": tag]) })
        }
        items.append(.separator())
        items.append(ClosureItem("Other Color…") { ColourPanel.shared.open(e.color) { m.update([e.id], ["color": $0]) } })
        menu.addItem(sub("Color", items))
    }

    // MARK: what every piece has

    private static func common(_ menu: NSMenu, _ m: DiagramModel) {
        let one = m.picked.count == 1 ? m.picked.first : nil
        if let e = one, !e.locked {
            // Swap… opens the whole library, searchable.
            if !m.swapChoices(e).isEmpty { menu.addItem(ClosureItem("Swap…") { m.swapping = e.id }) }
            let favs = NSMenu()
            for i in 0..<DiagramModel.favoriteCount {
                favs.addItem(ClosureItem("\(i + 1)  " + (m.favorite(i)?.name ?? "Empty")) { m.setFavorite(i, from: e.id) })
            }
            let item = NSMenuItem(title: "Add to Favorites", action: nil, keyEquivalent: "")
            item.submenu = favs
            menu.addItem(item)
            menu.addItem(.separator())
        } else if one == nil, let id = m.favoriteSource {
            // **A whole group into one slot** (his custom objects, 2026-10-04).
            let favs = NSMenu()
            for i in 0..<DiagramModel.favoriteCount {
                favs.addItem(ClosureItem("\(i + 1)  " + (m.favorite(i)?.name ?? "Empty")) { m.setFavorite(i, from: id) })
            }
            let item = NSMenuItem(title: "Add Group to Favorites", action: nil, keyEquivalent: "")
            item.submenu = favs
            menu.addItem(item)
            menu.addItem(.separator())
        }
        menu.addItem(ClosureItem("Cut", key: "x") { m.cut() })
        menu.addItem(ClosureItem("Copy", key: "c") { m.copy() })
        menu.addItem(ClosureItem("Paste", key: "v") { m.paste() })
        menu.addItem(ClosureItem("Duplicate", key: "d") { m.duplicate() })
        if !DiagramCopy.targets(m).isEmpty {
            menu.addItem(ClosureItem("Send To…") { DiagramCopy.to(model: m, ids: m.selection) })
        }
        layerItems(menu, m)
        menu.addItem(.separator())
        let arrange = NSMenu()
        arrange.addItem(ClosureItem("Bring to Front", key: "]", mods: [.command, .option]) { m.order("front") })
        arrange.addItem(ClosureItem("Bring Forward", key: "]") { m.order("forward") })
        arrange.addItem(ClosureItem("Send Backward", key: "[") { m.order("backward") })
        arrange.addItem(ClosureItem("Send to Back", key: "[", mods: [.command, .option]) { m.order("back") })
        arrange.addItem(.separator())
        arrange.addItem(ClosureItem("Rotate 90° Right", key: "r") { m.rotate(90) })
        arrange.addItem(ClosureItem("Rotate 90° Left", key: "r", mods: [.command, .shift]) { m.rotate(-90) })
        arrange.addItem(ClosureItem("Flip Horizontal", key: "h", mods: .shift) { m.flip("x") })
        arrange.addItem(ClosureItem("Flip Vertical", key: "v", mods: .shift) { m.flip("y") })
        let arrangeItem = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: "")
        arrangeItem.submenu = arrange
        menu.addItem(arrangeItem)
        if m.selection.count > 1 { menu.addItem(ClosureItem("Group", key: "g") { m.group() }) }
        if m.picked.contains(where: { !$0.group.isEmpty }) {
            menu.addItem(ClosureItem("Ungroup", key: "g", mods: [.command, .shift]) { m.ungroup() })
        }
        let locked = m.picked.allSatisfy(\.locked)
        menu.addItem(ClosureItem(locked ? "Unlock" : "Lock", key: "l") { m.update(m.selection, ["locked": !locked]) })
        menu.addItem(ClosureItem("Hide", key: "h", mods: [.command, .shift]) { m.update(m.selection, ["hidden": true]); m.selection = [] })
        menu.addItem(.separator())
        menu.addItem(ClosureItem("Delete", key: "\u{8}", mods: []) { m.remove(m.selection) })
    }

    // MARK: menu makings

    /// **Opacity** (Ref 1505): fades a piece, never its name — a frame over
    /// a large area most of all. The picked pieces all take it.
    static func opacity(_ e: DiagramEl, _ m: DiagramModel) -> NSMenuItem {
        let ids = m.picked.contains(where: { $0.id == e.id }) ? m.picked.map(\.id) : [e.id]
        return sub("Opacity", [100, 85, 70, 50, 30].map { n in
            choice("\(n)%", on: Int((e.opacity * 100).rounded()) == n) { m.update(ids, ["opacity": Double(n) / 100]) }
        })
    }

    static func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    static func choice(_ title: String, on: Bool, _ run: @escaping () -> Void) -> NSMenuItem {
        let i = ClosureItem(title, run: run)
        i.state = on ? .on : .off
        return i
    }

    static func toggle(_ title: String, _ on: Bool, _ run: @escaping () -> Void) -> NSMenuItem {
        choice(title, on: on, run)
    }
}
