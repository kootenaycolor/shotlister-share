import SwiftUI

/// **Changed on two machines** (the Mac's clash banner): one field set two
/// ways on two devices. Keep what is on screen, or Use the other; several at
/// once, Keep All. Every answer is the engine's own write, one undo each.
struct Clash: Decodable, Hashable {
    var record: String
    var field: String
    var said: String
    var kept: String = ""
    var other: String = ""

    var name: String {
        let what = said.components(separatedBy: " — ").first ?? ""
        var f = field.replacingOccurrences(of: "_", with: " ").capitalized
        if f.hasPrefix("Vocab ") { f = String(f.dropFirst(6)) + " List" }
        return what.isEmpty ? f : "\(what) · \(f)"
    }
}

extension Session {
    func clashes() -> [Clash] {
        struct R: Decodable { var clashes: [Clash] }
        guard let engine else { return [] }
        return (try? JSONDecoder().decode(R.self, from: engine.raw("clashes")))?.clashes ?? []
    }
    func keepMine(_ c: Clash) { _ = engine?.raw("settle", c.record, c.field); refresh() }
    func takeOther(_ c: Clash) { _ = engine?.raw("takeother", c.record, c.field); refresh() }
    func keepAll() { _ = engine?.raw("settle"); refresh() }
}

struct ClashBanner: View {
    @EnvironmentObject private var session: Session
    @State private var list: [Clash] = []
    @State private var later: [Clash] = []
    @State private var open = false

    var body: some View {
        Group {
            if !list.isEmpty, list != later {
                Button { open = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(list.count == 1 ? "Changed on Two Machines" : "\(list.count) Changed on Two Machines")
                            .font(.kitBody.weight(.semibold))
                        Spacer()
                        Text("Review").font(.kitBody.weight(.semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clash.banner")
            }
        }
        .onAppear { list = session.clashes() }
        .onChange(of: session.view?.project.unsaved) { _, _ in list = session.clashes() }
        .onChange(of: session.syncedAt) { _, _ in list = session.clashes() }
        .sheet(isPresented: $open) {
            NavigationStack {
                List {
                    ForEach(list, id: \.self) { c in
                        Section(c.name) {
                            Button { session.keepMine(c); list = session.clashes() } label: {
                                LabeledContent("Keep", value: c.kept.isEmpty ? "Nothing" : c.kept)
                            }
                            if !c.other.isEmpty {
                                Button { session.takeOther(c); list = session.clashes() } label: {
                                    LabeledContent("Use", value: c.other)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Changed on Two Machines")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Later") { later = list; open = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        if list.count > 1 { Button("Keep All") { session.keepAll(); list = session.clashes(); open = false } }
                        else { Button("Done") { open = false } }
                    }
                }
                .onChange(of: list) { _, now in if now.isEmpty { open = false } }
            }
        }
    }
}
