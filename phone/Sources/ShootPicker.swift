import SwiftUI

/// **The shoot picker, on the phone** (stage 5 step 4, piece D): the same
/// one as Studio on the Mac, the console and the portal. ‹ Shoot · dates ▾ ›
/// under the title of every tab; the menu lists All Shoots and each shoot
/// with its dates and Wrapped / Next / Upcoming. Picking narrows every list —
/// the engine does it (`facet shoot`). Nothing drawn with fewer than two.
struct ShootPickerBar: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        if session.manyShoots {
            let order: [String?] = [nil] + session.shoots.map(\.id)
            let at = order.firstIndex { $0 == session.shootOn?.id } ?? 0
            HStack(spacing: 4) {
                Button { session.stepShoot(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(at == 0)
                    .accessibilityLabel("Previous Shoot")
                Menu {
                    Button { session.pickShoot(nil) } label: {
                        Label("All Shoots", systemImage: session.shootOn == nil ? "checkmark" : "")
                    }
                    ForEach(session.shoots) { shoot in
                        Button { session.pickShoot(shoot.id) } label: {
                            Text(shoot.label + (session.shootOn?.id == shoot.id ? "  ✓" : ""))
                            Text(PhoneShootWords.line(shoot))
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let on = session.shootOn {
                            Text(on.label).fontWeight(.semibold)
                            Text(PhoneShootWords.range(on.start, on.end)).foregroundStyle(.secondary)
                            let word = PhoneShootWords.status(on)
                            if !word.isEmpty {
                                Text(word).font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(.quaternary))
                            }
                        } else {
                            Text("All Shoots").fontWeight(.semibold)
                            Text("\(session.shoots.count) shoots").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().strokeBorder(.quaternary))
                }
                .accessibilityIdentifier("shoot.picker")
                Button { session.stepShoot(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(at == order.count - 1)
                    .accessibilityLabel("Next Shoot")
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}

enum PhoneShootWords {
    static func status(_ s: Engine.Shoot) -> String {
        let w = s.state.lowercased()
        if w == "to wrap" { return "To Wrap" }
        return w.isEmpty ? "" : w.prefix(1).uppercased() + w.dropFirst()
    }

    static func line(_ s: Engine.Shoot) -> String {
        let base = !s.kind.isEmpty && s.kind != s.label ? s.kind : ""
        return [base, range(s.start, s.end), status(s)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

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
}
