import SwiftUI

/// **Mods** (2026-10-17): small add-ons from one shared shelf, switched on per
/// project. Off by default; a project with none on draws exactly as before.
/// The switch is the project record's (`hub/src/studiomods.js`), the same one
/// the console card turns. Mirrored by hand in the hub, the console and the
/// phone, the way the modes are.
enum Mods {
    struct Mod: Identifiable, Hashable {
        let key: String
        let title: String
        let addsTo: SideTab
        var id: String { key }
    }

    static let editReference = "edit_reference"

    /// The shelf.
    static let shelf: [Mod] = [
        Mod(key: editReference, title: "Edit Reference", addsTo: .scenes),
    ]

    /// **The one gold every mod draws in**, in every app (his answer,
    /// 2026-10-15): never a project's colour, never a tag's.
    static func gold(_ dark: Bool) -> Color {
        dark ? Color(.sRGB, red: 0xE5 / 255, green: 0xB5 / 255, blue: 0x3A / 255)
             : Color(.sRGB, red: 0xB8 / 255, green: 0x86 / 255, blue: 0x0B / 255)
    }
}

extension ShellState {
    /// Whether this project has a mod on.
    func modOn(_ key: String) -> Bool { modsOn.contains(key) }

    /// **Switch a mod** for this film's project, through the server.
    func setMod(_ key: String, on: Bool) {
        let relay = projectPath.flatMap { Relay.projectId(at: $0) }
        let page = view?.project.consolePage ?? ""
        let was = modsOn
        modsOn = on ? Array(Set(was + [key])).sorted() : was.filter { $0 != key }
        Task { @MainActor in
            let got = await ProjectCards.shared.setMod(key, on: on, film: relay, page: page)
            if let list = got.mods {
                modsOn = list
            } else {
                modsOn = was
                note(got.why ?? "Not changed.")
            }
            if Launch.checking {
                FileHandle.standardError.write(Data("mods: \(modsOn.joined(separator: ","))\n".utf8))
            }
        }
    }
}

/// **Project Settings ▸ Mods**: the shelf, one switch each.
struct ModsPage: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsBox {
                ForEach(Array(Mods.shelf.enumerated()), id: \.element) { at, mod in
                    if at > 0 { Divider().overlay(Brand.rule(dark)) }
                    HStack(spacing: 10) {
                        Image(systemName: "play.square")
                            .font(.system(size: 13))
                            .foregroundStyle(state.modOn(mod.key) ? Mods.gold(dark) : Brand.ink3(dark))
                            .frame(width: 16)
                        Text(mod.title).sans(Brand.Size.body).foregroundStyle(Brand.ink(dark))
                        Text(mod.addsTo.title).sans(Brand.Size.small).foregroundStyle(Brand.ink3(dark))
                        Spacer(minLength: 0)
                        Toggle(mod.title, isOn: Binding(get: { state.modOn(mod.key) },
                                                        set: { state.setMod(mod.key, on: $0) }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                            .tint(Mods.gold(dark))
                            .accessibilityIdentifier("mods.\(mod.key)")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }
}
