import SwiftUI

/// **The calendar** — the schedule's right-hand panel.
///
/// Days are made here by picking dates: a click on an empty date is a new
/// shoot day already wearing that date, one undo step, and the days number
/// themselves in the order they were picked because that is the order they
/// were made. A date the schedule already holds is marked with its day and
/// its shot count, and clicking it goes to that day rather than making
/// anything — removing a day stays a deliberate act on the band itself.
///
/// A day band dragged onto a date takes that date, the same `dropDay` path
/// `--putdate` checks.
///
/// Its own file on purpose: `Schedule.swift` documents what one more view in
/// that body costs the type-checker.
struct ScheduleCalendar: View {
    @ObservedObject var state: ShellState
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// The first of the month on show. Seeded on appearance — from the check's
    /// `--month` pin when there is one, else the schedule's earliest date, else
    /// today — and moved only by the chevrons after that.
    @State private var anchor: Date = .init()
    @State private var seeded = false
    /// A day held over a date lights it — the hand in `ScheduleHands.swift`
    /// says which, one answer for the whole window.
    @ObservedObject private var hands = BoardHands.shared

    /// Monday-first, because that is how a shoot week reads.
    private static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2
        return cal
    }()

    var body: some View {
        VStack(spacing: 0) {
            head
            weekdayRow
            ScrollView {
                grid
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            guard !seeded else { return }
            anchor = Self.seed(state)
            seeded = true
        }
        .onChange(of: state.calendarMonth) { _, _ in anchor = Self.seed(state) }
    }

    // ------------------------------------------------------------- the head

    private var head: some View {
        HStack(spacing: 6) {
            turner("chevron.left", by: -1)
            Spacer()
            Text(Self.monthTitle.string(from: anchor))
                .sans(13, weight: .semibold)
                .foregroundStyle(Brand.ink(dark))
            Spacer()
            turner("chevron.right", by: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func turner(_ icon: String, by months: Int) -> some View {
        Button {
            if let moved = Self.gregorian.date(byAdding: .month, value: months, to: anchor) {
                anchor = moved
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.ink3(dark))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                Text(["M", "T", "W", "T", "F", "S", "S"][i])
                    .mono(8, weight: .medium, tracking: 0.5)
                    .foregroundStyle(Brand.ink4(dark))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // ------------------------------------------------------------- the grid

    /// One slot per grid position — a blank or a day of the month — so the
    /// grid is a single `ForEach`. It was two, blanks then days, and the lazy
    /// grid silently drew the first few day cells empty; one list with one
    /// identity per slot is the arrangement it draws whole.
    private struct Slot: Identifiable {
        let id: Int
        let number: Int?
    }

    /// A cell per day of the month, after enough blanks to put the first day
    /// under its weekday.
    private var grid: some View {
        let days = state.stripBoard?.days ?? []
        var marked: [String: BoardModel.Lane] = [:]
        for day in days where !day.date.isEmpty { marked[day.date] = day }
        let blanks = (0..<leadingBlanks).map { Slot(id: -1 - $0, number: nil) }
        let slots = blanks + (1...daysInMonth).map { Slot(id: $0, number: $0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(slots) { slot in
                if let number = slot.number {
                    cell(number, marked: marked)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private var firstOfMonth: Date {
        let parts = Self.gregorian.dateComponents([.year, .month], from: anchor)
        return Self.gregorian.date(from: parts) ?? anchor
    }

    private var daysInMonth: Int {
        Self.gregorian.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
    }

    private var leadingBlanks: Int {
        let weekday = Self.gregorian.component(.weekday, from: firstOfMonth)
        return (weekday - Self.gregorian.firstWeekday + 7) % 7
    }

    private func stored(_ number: Int) -> String {
        guard let date = Self.gregorian.date(byAdding: .day, value: number - 1, to: firstOfMonth)
        else { return "" }
        return DateDay.stored.string(from: date)
    }

    private func cell(_ number: Int, marked: [String: BoardModel.Lane]) -> some View {
        let date = stored(number)
        let held = marked[date]
        let shape = RoundedRectangle(cornerRadius: Brand.radiusChip, style: .continuous)
        return Button {
            state.calendarTap(date)
        } label: {
            VStack(spacing: 2) {
                Text("\(number)")
                    .mono(10, weight: held == nil ? .regular : .semibold)
                    .foregroundStyle(held == nil ? Brand.ink2(dark) : Brand.ink(dark))
                if let held {
                    Text("\(short(held.label)) · \(held.count)")
                        .mono(8, weight: .semibold)
                        .foregroundStyle(Brand.accent(dark))
                } else {
                    Text(" ").mono(8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if held != nil { shape.fill(Brand.accent(dark).opacity(0.14)) }
            }
            .overlay {
                if hands.spot == .date(date) { shape.strokeBorder(Brand.accent(dark), lineWidth: 1.5) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(held.map { tip($0) } ?? "Add \(Schedule.said(date))")
        // **Only a day band lands here** — a day let go on a date takes the
        // date. A scene on a bare date has no meaning, so the hand never
        // offers one this place.
        .boardMark(.date(date))
    }

    /// `Day 3` at cell size. The full label is in the tooltip.
    private func short(_ label: String) -> String {
        label.replacingOccurrences(of: "Day ", with: "D")
    }

    private func tip(_ day: BoardModel.Lane) -> String {
        "\(day.label) · \(day.count) \(day.count == 1 ? "shot" : "shots")"
    }

    // ------------------------------------------------------------- seeding

    /// Where the calendar opens: the pinned month if a check set one, else the
    /// month of the schedule's earliest date, else this one.
    static func seed(_ state: ShellState) -> Date {
        if let pinned = state.calendarMonth {
            let parts = pinned.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2,
               let date = gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) {
                return date
            }
        }
        let dates = (state.stripBoard?.days ?? []).map(\.date).filter { !$0.isEmpty }.sorted()
        if let earliest = dates.first, let date = DateDay.stored.date(from: earliest) {
            return date
        }
        return Date()
    }

    private static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
