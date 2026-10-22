import SwiftUI

/// **What sync has done, in a list.**
///
/// His ask, 2026-08-31: *"somewhere have a sync history"*. Reached by
/// right-clicking the Sync button, because it is this Mac's own account of its
/// comings and goings rather than anything about the film.
///
/// **What is in it is deliberately not everything.** The list keeps itself level
/// every five minutes; recording each of those would be 288 entries a day of
/// nothing happening, which is a log nobody reads. So this holds what moved and
/// what failed. See `shared/SyncHistory.swift` for why the *time* of the last
/// sync is kept separately from that.
struct SyncHistoryView: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var entries: [SyncHistory.Entry] = []

    var body: some View {
        Sheet(title: "Sync History", subtitle: SyncHistory.said,
              width: .narrow, height: 360, scrolls: false) {
            if entries.isEmpty {
                // An empty state says what is missing, in one line, and stops.
                EmptyState(title: "Nothing has moved yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in row(entry) }
                    }
                    .padding(.vertical, 6)
                }
            }
        } leading: {
            // The one sentence this screen earns: it explains an absence,
            // which is the thing a person cannot work out by looking.
        } trailing: {
            Button("Done") { state.showingSyncHistory = false }
                .buttonStyle(.primary)
                .keyboardShortcut(.cancelAction)
        }
        .onAppear { entries = SyncHistory.entries }
    }

    private func row(_ entry: SyncHistory.Entry) -> some View {
        HStack(spacing: 10) {
            // Only the mark that carries a fact stays: trouble.
            if !entry.worked {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trouble ?? entry.said).sans(13)
                    .foregroundStyle(Brand.ink(dark))
                    .lineLimit(2)
                Text(when(entry)).sans(10).foregroundStyle(Brand.ink3(dark))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// The moment, and whether he asked for it — "it hasn't synced since
    /// Tuesday" means something different if he pressed nothing since Tuesday.
    private func when(_ entry: SyncHistory.Entry) -> String {
        let shape = DateFormatter()
        shape.dateFormat = Calendar.current.isDateInToday(entry.when)
            ? "HH:mm" : "d MMM 'at' HH:mm"
        return shape.string(from: entry.when) + (entry.byHand ? "" : " · on its own")
    }
}
