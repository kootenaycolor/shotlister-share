import SwiftUI

/// **What holding a shot offers** — the Mac's right-click, the parts the
/// iPhone lacked (2026-10-09, his list): Highlight in the Mac's six colours,
/// and master shots. Drawn in any `.contextMenu`, so the list, the
/// storyboard and a scene's page offer the same.
struct ShotActions: View {
    @EnvironmentObject private var session: Session
    let row: Engine.Row

    var body: some View {
        // **Looking at an old version**: the one thing to do with a shot is
        // bring it back as it was. Everything else would be refused.
        if session.looking != nil {
            Button { session.bringBack([row.shot]) } label: {
                Label("Bring Back Shot", systemImage: "arrow.uturn.backward")
            }
        } else {
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        Menu {
            ForEach(Array(Swatches.highlight.enumerated()), id: \.offset) { at, hex in
                Button { session.highlight(row, hex) } label: {
                    Label {
                        Text(Swatches.highlightNames[at])
                    } icon: {
                        Image(uiImage: Swatch.dot(hex, ticked: (row.colour ?? "").uppercased() == hex))
                    }
                }
            }
            if !(row.colour ?? "").isEmpty {
                Divider()
                Button("No Highlight") { session.highlight(row, "") }
            }
        } label: {
            Label("Highlight", systemImage: "paintbrush")
        }
        .accessibilityIdentifier("shot.highlight")

        // **Copy, Paste after, Duplicate, Clear** (the Mac's right-click).
        Section {
            Button { session.copiedShots = [row.placement] } label: {
                Label("Copy Shot", systemImage: "doc.on.doc")
            }
            if !session.copiedShots.isEmpty {
                Button { session.pasteShots(after: row) } label: {
                    Label(session.copiedShots.count == 1 ? "Paste Shot After" : "Paste \(session.copiedShots.count) Shots After",
                          systemImage: "doc.on.clipboard")
                }
            }
            Button { session.duplicateShots([row]) } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button { session.clearShots([row]) } label: {
                Label("Clear Shot", systemImage: "eraser")
            }
        }

        // **Master shots.** A film comes back to the same setup; rather than
        // describe it twice, one shot is the master and the others stand in
        // for it, showing what it says.
        if let to = row.linkedTo {
            Button { session.link(row, to: nil) } label: {
                Label("Unlink from \(to)", systemImage: "link.badge.plus")
            }
        } else {
            Button { session.makeMaster(row, !row.isMaster) } label: {
                Label(row.isMaster ? "Remove Master" : "Make Master", systemImage: "m.square")
            }
            let masters = session.masters(besides: row)
            if !masters.isEmpty {
                Menu {
                    ForEach(masters) { master in
                        Button("\(master.number)  \(String(master.title.isEmpty ? master.description.prefix(40) : master.title.prefix(40)))") {
                            session.link(row, to: master)
                        }
                    }
                } label: {
                    Label("Link to Master", systemImage: "link")
                }
            }
        }
    }
}

/// **M, or →34A, beside the number** — the Mac's two marks: a master, and
/// a shot standing in for one.
struct MasterMark: View {
    let row: Engine.Row

    var body: some View {
        if let to = row.linkedTo {
            mark("→\(to)", word: .accentColor, ground: Color.accentColor.opacity(0.18))
                .accessibilityLabel("Stands in for \(to)")
        } else if row.isMaster {
            mark("M", word: Style.ink2, ground: Style.ink3.opacity(0.25))
                .accessibilityLabel("Master")
        }
    }

    private func mark(_ text: String, word: Color, ground: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(word)
            .background(ground, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}
