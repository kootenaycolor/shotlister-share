import SwiftUI

/// **Where photos from a Shortcuts action go** (his ask, 2026-10-09): the
/// film's locations, rooms with their house, then its reference boards. One
/// tap puts every photo there and goes to that page, so he sees them land.
struct PhotoDrop: View {
    let photos: [Data]
    /// Where to look once they are in.
    let landed: (Place) -> Void

    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    private var locations: [Engine.Location] { session.view?.locations ?? [] }
    private var boards: [Engine.Board] { session.view?.boards ?? [] }

    var body: some View {
        NavigationStack {
            List {
                if session.isReadOnly {
                    Text("Read Only. Made by a newer Studio.").foregroundStyle(.secondary)
                } else if locations.isEmpty && boards.isEmpty {
                    Text("No locations or boards yet").foregroundStyle(.secondary)
                }
                if !locations.isEmpty {
                    Section("Locations") {
                        ForEach(locations) { place in
                            Button {
                                photos.forEach { session.attach($0, toLocation: place.id) }
                                finish(.locations)
                            } label: {
                                Label(place.fullName ?? place.name, systemImage: "mappin.and.ellipse")
                            }
                            .accessibilityIdentifier("drop.location.\(place.name)")
                        }
                    }
                }
                if !boards.isEmpty {
                    Section("Reference Images") {
                        ForEach(boards) { board in
                            Button {
                                photos.forEach { session.attach($0, toBoard: board.id) }
                                finish(.references)
                            } label: {
                                Label(board.name, systemImage: "square.grid.2x2")
                            }
                        }
                    }
                }
            }
            .disabled(session.isReadOnly)
            .foregroundStyle(Color(.label))
            .navigationTitle(photos.count == 1 ? "Add 1 Photo" : "Add \(photos.count) Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func finish(_ place: Place) {
        dismiss()
        landed(place)
    }
}
