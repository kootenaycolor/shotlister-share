import AppKit
import SwiftUI

/// **The shoot picker** (stage 5 step 4, piece D; his approved design of
/// 2026-10-14, the same in Studio, the console and the portal).
///
///     ‹  Style Server  Shoot 2 · Oct 6–7  Next ▾  ›
///
/// Beside the project's name. Its menu: All Shoots, each shoot with its dates
/// and Wrapped / Next / Upcoming, and New Shoot…. Picking one narrows every
/// mode — the Shot List, the Schedule's days, Locations and the Diagram — and
/// new scenes and days are born into it. **All Shoots** groups the sidebar by
/// shoot, with wrapped shoots folded away. **No picker with one shoot.**
///
/// The shoots are the project's, off the card (`ProjectCards`, the server's
/// `studioshoots` switch); the engine narrows (`engine/src/shoots.rs`). The
/// pick is kept per film on this Mac; first time in, the next shoot, else
/// the last — the console's rule.
extension ShellState {
    var shoots: [ViewModel.Shoot] { view?.shoots ?? [] }
    var manyShoots: Bool { shoots.count >= 2 }
    /// The shoot being looked at, nil for All Shoots (or no picker).
    var shootOn: ViewModel.Shoot? {
        let on = view?.shootOn ?? ""
        return on.isEmpty ? nil : shoots.first { $0.id == on }
    }

    private var shootKey: String? {
        guard let path = projectPath else { return nil }
        return "shootPick." + (Relay.projectId(at: path) ?? path.lastPathComponent)
    }

    /// The shoot the picker starts on: the next (or today's), else the last.
    func defaultShoot() -> ViewModel.Shoot? {
        shoots.first { ["next", "today"].contains($0.state.lowercased()) } ?? shoots.last
    }

    /// **After a card is laid on**: the remembered pick, or the default. With
    /// fewer than two shoots, nothing is narrowed.
    func applyShootPick() {
        guard let engine else { return }
        guard manyShoots else {
            if !(view?.shootOn ?? "").isEmpty { replace(engine.pickShoot("")) }
            return
        }
        var want = ""
        if Launch.checking, let at = CommandLine.arguments.firstIndex(of: "--shoot"), at + 1 < CommandLine.arguments.count {
            let said = CommandLine.arguments[at + 1]
            if said == "all" { want = "" } else if let n = Int(said), n >= 1, n <= shoots.count { want = shoots[n - 1].id } else { want = said }
        } else if let key = shootKey, let kept = defaults.string(forKey: key) {
            want = kept == "all" ? "" : (shoots.contains { $0.id == kept } ? kept : (defaultShoot()?.id ?? ""))
        } else {
            want = defaultShoot()?.id ?? ""
        }
        if want != (view?.shootOn ?? "") { replace(engine.pickShoot(want)); refreshBoard() }
        if Launch.checking {
            FileHandle.standardError.write(Data("shoots: \(shoots.map { "\($0.label)[\($0.scenes) scenes, \($0.days) days\($0.wrapped ? ", wrapped" : "")]" }.joined(separator: " · ")) on: \(shootOn?.label ?? "All Shoots") scenes shown: \(view?.scenes.count ?? 0) days shown: \(view?.days.count ?? 0)\n".utf8))
        }
    }

    /// Pick a shoot, or All Shoots (nil). Kept for this film.
    func pickShoot(_ id: String?) {
        guard let engine else { return }
        replace(engine.pickShoot(id ?? ""))
        refreshBoard()
        if let key = shootKey { defaults.set(id ?? "all", forKey: key) }
        // A scene that is not in this shoot is no place to stand.
        if let at = sceneId, !(view?.scenes.contains { $0.id == at } ?? true) {
            sceneId = view?.scenes.first { !$0.archived }?.id ?? view?.scenes.first?.id
        }
    }

    /// ‹ and ›: through All Shoots, then each shoot, in order.
    func stepShoot(_ by: Int) {
        let order: [String?] = [nil] + shoots.map(\.id)
        let at = order.firstIndex { $0 == shootOn?.id } ?? 0
        let next = max(0, min(order.count - 1, at + by))
        if next != at { pickShoot(order[next]) }
    }

    /// **Move to Shoot…** — the scenes into another shoot, one undo step.
    func moveScenes(_ scenes: [String], toShoot shoot: ViewModel.Shoot) {
        guard let engine, !scenes.isEmpty else { return }
        replace(engine.moveToShoot(shoot.id, scenes: scenes))
        // The Schedule's strips are read on their own: a moved scene leaves
        // the old shoot's day at once, not when the tab is next opened.
        refreshBoard()
        if Launch.checking {
            FileHandle.standardError.write(Data("moved \(scenes.count) to \(shoot.label)\n".utf8))
        }
    }

    /// One shoot's run of scenes under All Shoots.
    struct ShootGroup: Identifiable {
        var shoot: ViewModel.Shoot
        var scenes: [ViewModel.Scene]
        var id: String { shoot.id }
    }

    /// Whether the sidebar groups by shoot: All Shoots, with two or more.
    var groupingByShoot: Bool { manyShoots && shootOn == nil }

    /// The sidebar's scenes, shoot by shoot (a scene naming no shoot the
    /// card knows goes with the first).
    var shootGroups: [ShootGroup] {
        let list = scenes
        let known = Set(shoots.map(\.id))
        return shoots.enumerated().map { at, shoot in
            ShootGroup(shoot: shoot, scenes: list.filter { $0.shoot == shoot.id || (at == 0 && !known.contains($0.shoot)) })
        }
    }

    /// In All Shoots, whether a shoot's scenes are folded away: wrapped ones
    /// are, until opened.
    func shootFolded(_ shoot: ViewModel.Shoot) -> Bool {
        shootFolds[shoot.id] ?? shoot.wrapped
    }

    func toggleShootFold(_ shoot: ViewModel.Shoot) {
        shootFolds[shoot.id] = !shootFolded(shoot)
    }
}

/// How a shoot is said: its name, then its number and dates, then its state.
enum ShootWords {
    static func status(_ s: ViewModel.Shoot) -> String {
        switch s.state.lowercased() {
        case "to wrap": return "To Wrap"
        case "": return ""
        default: return s.state.prefix(1).uppercased() + s.state.dropFirst()
        }
    }

    static func sub(_ s: ViewModel.Shoot) -> String {
        let base = !s.kind.isEmpty && s.kind != s.label ? s.kind : ""
        return [base, range(s.start, s.end)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `Oct 6`, `Oct 6–7`, `Oct 30 – Nov 2`, `Dec 30, 2026 – Jan 2, 2027` —
    /// the console's `prettyRange`.
    static func range(_ start: String, _ end: String) -> String {
        func parts(_ d: String) -> (Int, Int, Int)? {
            let p = d.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 && (1...12).contains(p[1]) ? (p[0], p[1], p[2]) : nil
        }
        guard let a = parts(start) else { return "" }
        guard let b = parts(end), (b.0, b.1, b.2) > (a.0, a.1, a.2) else { return "\(months[a.1 - 1]) \(a.2)" }
        if a.0 != b.0 { return "\(months[a.1 - 1]) \(a.2), \(a.0) – \(months[b.1 - 1]) \(b.2), \(b.0)" }
        if a.1 != b.1 { return "\(months[a.1 - 1]) \(a.2) – \(months[b.1 - 1]) \(b.2)" }
        return "\(months[a.1 - 1]) \(a.2)–\(b.2)"
    }

    static func lead(_ s: ViewModel.Shoot) -> Bool {
        ["next", "today"].contains(s.state.lowercased())
    }
}

/// The small Wrapped / Next / Upcoming word.
struct ShootTag: View {
    var shoot: ViewModel.Shoot
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let word = ShootWords.status(shoot)
        let dark = scheme == .dark
        if !word.isEmpty {
            Text(word)
                .sans(Brand.Size.tiny, weight: .semibold)
                .foregroundStyle(ShootWords.lead(shoot) ? Brand.accent(dark) : Brand.ink2(dark))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(ShootWords.lead(shoot) ? Brand.accentTint(dark) : Brand.selectionQuiet(dark)))
                .fixedSize()
        }
    }
}

/// The picker itself, for the top bar. Draws nothing with fewer than two shoots.
struct ShootPicker: View {
    @ObservedObject var state: ShellState
    @State private var open = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        if state.manyShoots {
            let order: [String?] = [nil] + state.shoots.map(\.id)
            let at = order.firstIndex { $0 == state.shootOn?.id } ?? 0
            HStack(spacing: 2) {
                step("chevron.left", help: "Previous Shoot", enabled: at > 0) { state.stepShoot(-1) }
                Button { open.toggle() } label: {
                    HStack(spacing: 7) {
                        if let on = state.shootOn {
                            Text(on.label).sans(Brand.Size.title, weight: .semibold).foregroundStyle(Brand.ink(dark)).lineLimit(1)
                            let sub = ShootWords.sub(on)
                            if !sub.isEmpty {
                                Text(sub).sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                            }
                            ShootTag(shoot: on)
                        } else {
                            Text("All Shoots").sans(Brand.Size.title, weight: .semibold).foregroundStyle(Brand.ink(dark))
                            Text("\(state.shoots.count) shoots").sans(Brand.Size.body).foregroundStyle(Brand.ink3(dark))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Brand.ink4(dark))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surface(dark)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.rule2(dark), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Shoots")
                .popover(isPresented: $open, arrowEdge: .bottom) {
                    ShootMenu(state: state) { open = false }
                }
                step("chevron.right", help: "Next Shoot", enabled: at < order.count - 1) { state.stepShoot(1) }
            }
            .fixedSize()
            // A checking run photographs the menu laid open in the window
            // (`--shootmenu`): a popover is a window of its own.
            .overlay(alignment: .topLeading) {
                if Launch.checking && CommandLine.arguments.contains("--shootmenu") {
                    ShootMenu(state: state)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.surface(dark))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 4))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.rule2(dark), lineWidth: 0.5))
                        .fixedSize()
                        .offset(x: 20, y: 34)
                }
            }
        }
    }

    private func step(_ icon: String, help: String, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? Brand.ink3(dark) : Brand.ink4(dark).opacity(0.5))
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

/// The picker's menu: All Shoots, each shoot, New Shoot….
struct ShootMenu: View {
    @ObservedObject var state: ShellState
    var close: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row(title: "All Shoots", sub: "\(state.shoots.count) shoots", shoot: nil, on: state.shootOn == nil)
            ForEach(state.shoots) { s in
                row(title: s.label, sub: ShootWords.sub(s), shoot: s, on: state.shootOn?.id == s.id)
            }
            Rectangle().fill(Brand.rule(dark)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6)
            Button {
                close()
                state.newShoot()
            } label: {
                Text("New Shoot…").sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .frame(width: 280)
    }

    private func row(title: String, sub: String, shoot: ViewModel.Shoot?, on: Bool) -> some View {
        Button {
            close()
            state.pickShoot(shoot?.id)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).sans(Brand.Size.body, weight: .semibold).foregroundStyle(Brand.ink(dark)).lineLimit(1)
                    if !sub.isEmpty {
                        Text(sub).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let shoot { ShootTag(shoot: shoot) }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Brand.selectionQuiet(dark) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ShellState {
    /// **New Shoot…** is the console's: the project's own New Shoot, which
    /// makes the Shoots row, the folders and the rest. Studio opens it there.
    func newShoot() {
        guard let page = view?.project.consolePage, !page.isEmpty else {
            note("Not linked to a project.")
            return
        }
        if Launch.checking {
            FileHandle.standardError.write(Data("new shoot: console \(page)\n".utf8))
            return
        }
        Console.openProject(page: page)
    }
}
