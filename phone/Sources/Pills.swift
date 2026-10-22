import SwiftUI

/// A value, as the Mac draws one: a pill.
///
/// His instruction — keep the Mac's pills and its formatting. They are also the
/// right shape for a thumb: a word in a rounded box is a target you can hit
/// without looking, which a row in a list is not.
struct Pill: View {
    let text: String
    var chosen: Bool = false
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(chosen ? tint.opacity(0.18) : Color(.tertiarySystemFill))
            }
            .overlay {
                Capsule().strokeBorder(chosen ? tint.opacity(0.55) : .clear, lineWidth: 1)
            }
            .foregroundStyle(chosen ? tint : Color.primary)
    }
}

/// Pills laid out the way words are: along a line, then onto the next.
///
/// SwiftUI has no wrapping stack, and a horizontal scroller is the wrong answer
/// here — it hides half the choices behind a gesture, and the whole point is
/// that every choice is *visible* so setting one is a single tap.
struct Flow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, within: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indexes: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let wouldBe = row.width == 0 ? size.width : row.width + spacing + size.width
            if wouldBe > width, !row.indexes.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.indexes.append(index)
            row.width = row.width == 0 ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indexes.isEmpty { rows.append(row) }
        return rows
    }
}

/// **One tap sets a value.**
///
/// Every answer the project has ever used for this field is on screen at once.
/// There is no sheet to open, nothing to dismiss, and no list to scroll past —
/// which is the whole difference between four taps and one.
///
/// Tapping the value that is already set clears it, because the other way to
/// spend a minute on a set is hunting for how to unsay something.
struct PillField: View {
    let label: String
    let options: [String]
    /// What is set. More than one for the fields that hold more than one —
    /// angle and tags are lists in the engine, and were being written as single
    /// values on the Mac once already.
    let selected: [String]
    var multiple: Bool = false
    var tint: Color = .accentColor
    var onChange: ([String]) -> Void
    /// **Nothing when the list is closed.** A project can lock a column's terms,
    /// and offering to add one that would then be refused is worse than not
    /// offering.
    var onNew: (() -> Void)?
    /// How an option reads on screen. The value that is chosen and written is
    /// still the option itself — this is only the word on the pill.
    var drawn: (String) -> String = { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.kitLabel.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if let onNew {
                    Button(action: onNew) {
                        Image(systemName: "plus.circle").font(.footnote)
                    }
                    .accessibilityLabel("Add \(label)")
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Flow {
                ForEach(shown, id: \.self) { option in
                    Button { choose(option) } label: {
                        Pill(text: drawn(option), chosen: selected.contains(option), tint: tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The project's list, plus anything already set that is not in it — a value
    /// from a script import or from the Mac belongs on screen even before the
    /// project has learned it.
    private var shown: [String] {
        options + selected.filter { !$0.isEmpty && !options.contains($0) }
    }

    private func choose(_ option: String) {
        if multiple {
            onChange(selected.contains(option)
                     ? selected.filter { $0 != option }
                     : selected + [option])
        } else {
            // Tapping what is already set clears it. The other way to lose a
            // minute on a set is hunting for how to unsay something.
            onChange(selected.contains(option) ? [] : [option])
        }
    }
}
