import SwiftUI

/// **The Home Screen's order**, the console's three: by the next shoot, by
/// name, by when it was last opened here.
enum HomeSort: String, CaseIterable, Identifiable {
    case next, name, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .next: return "Next Shoot"
        case .name: return "Name"
        case .recent: return "Recently Opened"
        }
    }
}

/// **One project on the Home Screen**, drawn the way the Projects Console
/// draws it (`ProjectRow`): its own icon in its own colour on a soft tile, its
/// name, one quiet line under it, and on the right how many days to the next
/// shoot.
struct HomeRow: View {
    enum End { case chevron, cloud, busy }

    var name: String
    var mark: FilmMark?
    /// The project's colour when the film carries none of its own (hex).
    var colour: String
    /// What stands in for an icon: by the project's type.
    var type: String
    var line: String
    var days: Int?
    var end: End

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tint: Color {
        let hex = (mark?.colour.isEmpty == false ? mark?.colour : nil) ?? colour
        return hex.isEmpty ? Style.ink3 : Color(markHex: hex)
    }

    private var symbol: String {
        return ProjectTypes.symbol(type)
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 36 * 0.27, style: .continuous)
                    .fill(tint.opacity(0.16))
                if let mark, !mark.path.isEmpty {
                    FilmIcon(mark: FilmMark(path: mark.path, colour: mark.colour.isEmpty ? colour : mark.colour), size: 19)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Style.ink3)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            if end == .busy {
                ProgressView()
            } else if let days, !typeSize.isAccessibilitySize {
                Text(days == 0 ? "today" : "\(days)d")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(days <= 3 ? Color(.label) : Style.ink2)
                    .fixedSize()
            } else if end == .cloud {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.kitLabel.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// The count over a group of projects: `Active   3`.
struct HomeHeader: View {
    var title: String
    var count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Style.ink2)
        .textCase(nil)
        .padding(.top, 4)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Style.page)
        .accessibilityAddTraits(.isHeader)
    }
}
