import SwiftUI

/// **What sync has done on the phone, and the menu's sync line.**
///
/// A sync *button* sat on every tab's bar from 2026-08-31 to 2026-09-16
/// (*"i dont see a sync button on ios"*). His ask on the 16th put it back in
/// the ⋯ menu — *"the sync relay button should always be in the … menu"* —
/// as `Sync now` in `ProjectMenu`, whose glyph turns while a sync runs.
/// From 2026-10-09 (`design/42-one-home`) Sync Now is on the film's own
/// menu under its name, which turns instead; this history is the phone's,
/// so it opens from Projects ▸ Settings.

/// **What sync has done, on the phone.** The twin of the Mac's
/// `SyncHistoryView`, reading the same `shared/SyncHistory.swift`.
struct SyncHistoryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [SyncHistory.Entry] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    // An empty state says what is missing, in one line.
                    ContentUnavailableView("Nothing has moved yet",
                                           systemImage: "clock.arrow.circlepath")
                } else {
                    List {
                        Section {
                            ForEach(entries) { entry in row(entry) }
                        }
                    }
                }
            }
            .navigationTitle("Sync History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Sync History").font(.kitRowStrong)
                        Text(SyncHistory.said).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { entries = SyncHistory.entries }
        }
    }

    private func row(_ entry: SyncHistory.Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.worked
                  ? (entry.byHand ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath")
                  : "exclamationmark.triangle")
                .foregroundStyle(entry.worked ? Color.secondary : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.trouble ?? entry.said).font(.kitRow)
                Text(when(entry)).font(.kitLabel).foregroundStyle(.secondary)
            }
        }
    }

    private func when(_ entry: SyncHistory.Entry) -> String {
        let shape = DateFormatter()
        shape.dateFormat = Calendar.current.isDateInToday(entry.when)
            ? "HH:mm" : "d MMM 'at' HH:mm"
        return shape.string(from: entry.when) + (entry.byHand ? "" : " · on its own")
    }
}
