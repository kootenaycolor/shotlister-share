import SwiftUI

/// **Mods on the phone** (2026-10-17): the shared shelf (the hub's
/// `studiomods.js`, Studio's `Mods.swift`), switched per project from Project
/// Settings. Off by default; a project with none on draws as before.
enum PhoneMods {
    struct Mod: Identifiable, Hashable {
        let key: String
        let title: String
        let addsTo: String
        var id: String { key }
    }

    static let editReference = "edit_reference"
    static let shelf: [Mod] = [Mod(key: editReference, title: "Edit Reference", addsTo: "Shot List")]

    /// **The one gold every mod draws in**, the same in every app.
    static let gold = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0xE5 / 255, green: 0xB5 / 255, blue: 0x3A / 255, alpha: 1)
            : UIColor(red: 0xB8 / 255, green: 0x86 / 255, blue: 0x0B / 255, alpha: 1)
    })
}

extension Session {
    /// The mods this project has on, from its card.
    var modsOn: Set<String> {
        // A checking run lays the mod on without a server.
        if ProcessInfo.processInfo.arguments.contains("--modson") { return [PhoneMods.editReference] }
        return PhoneCards.shared.mods(film: Relay.projectId(at: folder.url), page: view?.project.consolePage ?? "")
    }
}

/// **Project Settings ▸ Mods**: one switch per shelf mod.
struct ModsSection: View {
    @EnvironmentObject private var session: Session
    @ObservedObject private var cards = PhoneCards.shared
    @State private var busy: String?
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(PhoneMods.shelf) { mod in
                Toggle(isOn: Binding(get: { session.modsOn.contains(mod.key) },
                                     set: { want in switchMod(mod.key, on: want) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mod.title)
                        Text(mod.addsTo).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .tint(PhoneMods.gold)
                .disabled(busy != nil)
                .accessibilityIdentifier("mods.\(mod.key)")
            }
        } header: {
            Text("Mods")
        } footer: {
            if let problem { Text(problem) }
        }
    }

    private func switchMod(_ key: String, on: Bool) {
        busy = key
        problem = nil
        Task { @MainActor in
            problem = await cards.setMod(key, on: on, film: Relay.projectId(at: session.folder.url),
                                         page: session.view?.project.consolePage ?? "")
            busy = nil
            session.objectWillChange.send()
        }
    }
}
