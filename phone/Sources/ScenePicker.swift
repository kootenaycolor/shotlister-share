import SwiftUI

/// Which scene, out of the ones this film has.
///
/// Used for the two things that take a shot somewhere else — moving it and
/// copying it — so both ask the same question the same way.
struct ScenePicker: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// The scene the shot is already in, which is not an answer.
    let except: String
    /// Scenes that are already on whatever is asking — a board's own list, say.
    /// Offering one that is already there is offering a no-op.
    var hiding: Set<String> = []
    let onPick: (Engine.Scene) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.scenes.filter { $0.id != except && !hiding.contains($0.id) }) { scene in
                    Button {
                        onPick(scene)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(scene.number)
                                .font(.title3.weight(.bold).monospacedDigit())
                                .frame(minWidth: 34, alignment: .leading)
                            Text(scene.heading)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
