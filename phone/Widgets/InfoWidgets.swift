import WidgetKit
import SwiftUI

/// **Widgets that carry information** (`design/43-widgets.html` D, his pick
/// 2026-10-09). Which film each follows is set in Settings → Lock Screen;
/// "Soonest Shoot" follows whichever film shoots next. The app writes what
/// they show (`WidgetPublisher`) each time an open film changes.

struct InfoEntry: TimelineEntry {
    let date: Date
    let film: FilmSnapshot?
}

/// Redrawn at midnight, when "today" moves, as well as whenever the app writes.
struct InfoProvider: TimelineProvider {
    let chosen: () -> String?

    func placeholder(in context: Context) -> InfoEntry { InfoEntry(date: .now, film: nil) }
    func getSnapshot(in context: Context, completion: @escaping (InfoEntry) -> Void) {
        completion(InfoEntry(date: .now, film: FilmSnapshots.followed(chosen())))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<InfoEntry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [InfoEntry(date: .now, film: FilmSnapshots.followed(chosen()))], policy: .after(midnight)))
    }
}

struct ShootDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShotlisterShootDay", provider: InfoProvider { InfoChoices.shootDayFilm }) { entry in
            ShootDayFace(film: entry.film)
                .widgetURL(entry.film.map { LockShortcut(slot: 0, film: $0.film, place: "schedule").url })
        }
        .configurationDisplayName("Shoot Day")
        .description("Counts down to the next shoot day; on the day, how many shots are got.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct NextShotsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShotlisterNextShots", provider: InfoProvider { InfoChoices.nextShotsFilm }) { entry in
            NextShotsFace(film: entry.film)
                .widgetURL(entry.film.map { LockShortcut(slot: 0, film: $0.film, place: "shotlist").url })
        }
        .configurationDisplayName("Next Shots")
        .description("The next three shots to get, with their frames.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Faces (compiled into the app as well, for the checking door)

private func glyph(_ film: FilmSnapshot) -> LockShortcut {
    LockShortcut(slot: 0, film: film.film, symbol: "calendar", markPath: film.markPath, markColour: film.markColour)
}

struct ShootDayFace: View {
    @Environment(\.widgetFamily) private var given
    let film: FilmSnapshot?
    var size: WidgetFamily? = nil
    private var family: WidgetFamily { size ?? given }

    var body: some View {
        content
            .padding(size == nil || family != .systemSmall ? 0 : 16)
            .containerBackground(for: .widget) { Color(white: 0.075) }
    }

    @ViewBuilder
    private var content: some View {
        if let film, let focus = film.focus, let date = focus.date, away(date) >= 1 {
            let said = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            CountdownBody(family: family, days: away(date), name: film.film,
                          detail: "\(focus.day.label) · \(said)",
                          short: date.formatted(.dateTime.month(.abbreviated).day()),
                          tint: Color(markHex: film.markColour ?? "#0A84FF")) { side, tinted in
                FilmGlyph(shortcut: glyph(film), side: side, tinted: tinted)
            }
        } else if let film, let focus = film.focus {
            let day = focus.day
            let isToday = focus.date.map { Calendar.current.isDateInToday($0) } ?? false
            let empty = day.count == 0
            let shots = empty ? "No shots yet" : day.count == 1 ? "1 shot" : "\(day.count) shots"
            let got = "\(day.got) of \(day.count) got"
            let when = focus.date.map { isToday ? "Today" : $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
            switch family {
            case .accessoryCircular where empty:
                ZStack {
                    AccessoryWidgetBackground()
                    FilmGlyph(shortcut: glyph(film), side: 30, tinted: false)
                }
            case .accessoryCircular:
                Gauge(value: Double(day.got), in: 0...Double(max(day.count, 1))) {
                    FilmGlyph(shortcut: glyph(film), side: 14, tinted: false)
                } currentValueLabel: {
                    Text("\(day.got)/\(day.count)").font(.system(size: 13, weight: .bold)).minimumScaleFactor(0.6)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryInline:
                Label("\(day.label) · \(isToday && !empty ? got : (empty ? (when ?? shots) : shots))", systemImage: "calendar")
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    FilmGlyph(shortcut: glyph(film), side: 26, tinted: false)
                        .frame(width: 44, height: 44)
                        .background(AccessoryWidgetBackground().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                    VStack(alignment: .leading, spacing: 0) {
                        Fit(day.label, day.label, size: 17)
                        ViewThatFits(in: .horizontal) {
                            caption([when, isToday && !empty ? got : shots].compactMap { $0 }.joined(separator: " · "))
                            caption(empty ? (when ?? shots) : isToday ? got : shots)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ShortcutFace.edge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    FilmGlyph(shortcut: glyph(film), side: 24, tinted: false, onColour: true)
                        .frame(width: 40, height: 40)
                        .background(Color(markHex: film.markColour ?? "#0A84FF"), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer(minLength: 0)
                    Fit(day.label, day.label, size: 26)
                    Text(when ?? film.film).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    if !empty {
                        ProgressView(value: Double(day.got), total: Double(max(day.count, 1)))
                            .tint(Color(markHex: film.markColour ?? "#0A84FF"))
                            .padding(.top, 6)
                    }
                    Text(empty ? shots : got).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).padding(.top, 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetEmpty(family: family, words: film == nil ? "Open a project in Studio" : "No shoot days")
        }
    }

    /// Whole days from today to a shoot day.
    private func away(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
    }

    private func caption(_ words: String) -> some View {
        Text(words).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
}

struct NextShotsFace: View {
    let film: FilmSnapshot?
    var size: WidgetFamily? = nil

    var body: some View {
        content
            .padding(size == nil ? 0 : 16)
            .containerBackground(for: .widget) { Color(white: 0.075) }
    }

    @ViewBuilder
    private var content: some View {
        if let film, !film.next.isEmpty {
            let tint = Color(markHex: film.markColour ?? "#0A84FF")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    FilmGlyph(shortcut: glyph(film), side: 15, tinted: true)
                    Text("\(film.film) · Next Up".uppercased())
                        .font(.system(size: 11, weight: .bold)).kerning(0.8).lineLimit(1)
                        .foregroundStyle(ShortcutFace.readable(tint))
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(film.next.prefix(3).enumerated()), id: \.offset) { _, shot in
                        VStack(alignment: .leading, spacing: 5) {
                            picture(shot)
                                .frame(maxWidth: .infinity)
                                .frame(height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            (Text(shot.number).bold().foregroundColor(.primary) + Text(" " + shot.title).foregroundColor(.secondary))
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(film.next.count..<3, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmpty(family: .systemMedium, words: film == nil ? "Open a project in Studio" : "Every shot is got")
        }
    }

    @ViewBuilder
    private func picture(_ shot: FilmSnapshot.Shot) -> some View {
        if let name = shot.picture, let folder = FilmSnapshots.frames,
           let image = UIImage(contentsOfFile: folder.appendingPathComponent(name).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.08)
                Text(shot.number).font(.system(size: 20, weight: .bold)).foregroundStyle(.secondary)
            }
        }
    }
}

/// One line saying what is missing, inside the margin.
struct WidgetEmpty: View {
    let family: WidgetFamily
    let words: String

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack { AccessoryWidgetBackground(); Image(systemName: "calendar").font(.system(size: 22)) }
        case .accessoryInline:
            Text(words)
        default:
            Text(words)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, family == .accessoryRectangular ? ShortcutFace.edge : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// **A countdown** (his note, 2026-10-10: *"more of a countdown if it's
/// counting to the date"*). The days are the widget, set large in rounded
/// figures like a timer; the project and the date sit beside or under them.
/// Round: an arc that closes over the last six weeks, the number in its
/// middle and the project's icon in the arc's gap.
struct CountdownBody<Glyph: View>: View {
    let family: WidgetFamily
    let days: Int
    /// The project or film, as small capitals.
    let name: String
    /// "Principal · Oct 26–31", and the shorter form when that will not fit.
    let detail: String
    let short: String
    let tint: Color
    var todo = 0
    /// The icon at a side, in the tint or not.
    let glyph: (CGFloat, Bool) -> Glyph

    private var unit: String { days == 1 ? "day" : "days" }
    private func figure(_ size: CGFloat) -> some View {
        Text("\(days)")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .widgetAccentable()
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(42 - min(days, 42)), in: 0...42) {
                glyph(13, false)
            } currentValueLabel: {
                figure(days > 99 ? 19 : 25)
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            Label("\(name) in \(days) \(unit)", systemImage: "hourglass")
        case .accessoryRectangular:
            // The project across the top at full width, so a long name is
            // not cut; under it the days, large, with the date beside them.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    glyph(12, false)
                    Text(name.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.6)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 6) {
                    figure(36).layoutPriority(1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(unit.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.8).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            Text(detail).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                            Text(short).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                            Text(short).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, ShortcutFace.edge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    glyph(16, true)
                    Text(name.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.8).lineLimit(2)
                        .foregroundStyle(ShortcutFace.readable(tint))
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    figure(58)
                    Text(unit).font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Text(short).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Text(short).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                if todo > 0 {
                    Text("\(todo) to do").font(.system(size: 12)).foregroundStyle(Color.orange).lineLimit(1).padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
