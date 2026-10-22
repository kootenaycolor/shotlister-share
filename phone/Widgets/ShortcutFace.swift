import WidgetKit
import SwiftUI

/// How a shortcut looks, in each size and each of the three looks
/// (`design/43-widgets.html`: Badge, Film Colour, Eyebrow). Compiled into the
/// app as well, so a checking run can photograph every size without a lock
/// screen (`--widgetfaces`).
///
/// **The safe zone** (his rule, 2026-10-09: *"text never gets close to the
/// border"*): no words inside a round widget at all (a number in a ring is
/// the one exception, and it is short); wide widgets keep `edge` all round
/// and use a page's short name before cutting anything; square ones keep
/// the system's margin, which the checking door draws too.
struct ShortcutFace: View {
    @Environment(\.widgetFamily) private var given
    let shortcut: LockShortcut
    /// Set only by the checking door, which has no widget family of its own.
    var size: WidgetFamily? = nil

    static let edge: CGFloat = 12
    private var family: WidgetFamily { size ?? given }
    private var look: WidgetLook { shortcut.shownLook }
    private var tint: Color { Color(markHex: shortcut.markColour ?? "#0A84FF") }
    private var big: String { shortcut.film == nil ? shortcut.title : shortcut.subtitle }
    private var bigShort: String { shortcut.film == nil ? shortcut.title : shortcut.shortSubtitle }
    private var small: String { shortcut.film ?? shortcut.subtitle }

    var body: some View {
        face
            .padding(size == nil || family != .systemSmall ? 0 : 16)
            .containerBackground(for: .widget) {
                if family == .systemSmall && look == .colour { tint } else { Color(white: 0.075) }
            }
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline:
            Label(shortcut.film.map { "\($0) · \(shortcut.shortSubtitle)" } ?? shortcut.title, systemImage: shortcut.glyph)
        case .accessoryRectangular: rectangular
        default: square
        }
    }

    // ---- round: the icon and what it opens, no words ------------------------

    /// The project's icon, and in its lower right a small badge with the
    /// page's symbol (his note, 2026-10-10: a round widget must say what it
    /// opens). The badge sits inside the circle with a margin of its own.
    private var circular: some View {
        GeometryReader { box in
            let d = min(box.size.width, box.size.height)
            let opens = shortcut.film != nil && shortcut.symbol != nil
            let marked = shortcut.markPath != nil
            ZStack {
                if look == .eyebrow {
                    Circle().strokeBorder(.primary.opacity(0.55), lineWidth: max(1.5, d * 0.028))
                } else {
                    AccessoryWidgetBackground()
                }
                Group {
                    if opens && !marked, let title = shortcut.film {
                        // No icon of its own: its initials, so the badge is
                        // not the same symbol twice.
                        Text(PageBadge.initials(title))
                            .font(.system(size: d * 0.26, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(width: d * 0.42)
                            .widgetAccentable()
                            .offset(x: -d * 0.03, y: -d * 0.01)
                    } else {
                        FilmGlyph(shortcut: shortcut, side: d * (opens ? 0.4 : (look == .colour ? 0.5 : 0.44)), tinted: false)
                    }
                }
                .offset(x: opens ? -d * 0.07 : 0, y: opens ? -d * 0.07 : 0)
                if opens, let symbol = shortcut.symbol {
                    PageBadge(symbol: symbol, side: d * 0.36)
                        .offset(x: d * 0.17, y: d * 0.17)
                }
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ---- wide ---------------------------------------------------------------

    @ViewBuilder
    private var rectangular: some View {
        switch look {
        case .badge:
            HStack(spacing: 10) {
                FilmGlyph(shortcut: shortcut, side: 26, tinted: false)
                    .frame(width: 44, height: 44)
                    .background(AccessoryWidgetBackground().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                VStack(alignment: .leading, spacing: 0) {
                    Fit(big, bigShort, size: 17)
                    Text(small).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.edge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .colour:
            ZStack(alignment: .topTrailing) {
                AccessoryWidgetBackground().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Fit(big, bigShort, size: 22).padding(.trailing, 24)
                    Text(small).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, Self.edge + 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                FilmGlyph(shortcut: shortcut, side: 18, tinted: false).padding(Self.edge)
            }
        case .eyebrow:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    FilmGlyph(shortcut: shortcut, side: 13, tinted: false)
                    Text(small.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.8).lineLimit(1)
                }
                .foregroundStyle(.secondary)
                Fit(big, bigShort, size: 24)
            }
            .padding(.horizontal, Self.edge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // ---- home screen square -------------------------------------------------

    @ViewBuilder
    private var square: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch look {
            case .badge:
                FilmGlyph(shortcut: shortcut, side: 24, tinted: false, onColour: true)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            case .colour:
                FilmGlyph(shortcut: shortcut, side: 30, tinted: false, onColour: true)
            case .eyebrow:
                HStack(spacing: 6) {
                    FilmGlyph(shortcut: shortcut, side: 16, tinted: true)
                    Text(small.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.8).lineLimit(1)
                        .foregroundStyle(ShortcutFace.readable(tint))
                }
            }
            Spacer(minLength: 0)
            Fit(big, bigShort, size: look == .badge ? 20 : 22, lines: 2)
                .foregroundStyle(look == .colour ? .white : .primary)
            if look != .eyebrow {
                Text(small).font(.system(size: 13)).lineLimit(1)
                    .foregroundStyle(look == .colour ? Color.white.opacity(0.75) : .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A line of large type: whole when it fits, else its short form, and only
/// then smaller. Never `Reference Ima…`.
struct Fit: View {
    let whole: String
    let short: String
    let size: CGFloat
    var lines = 1

    init(_ whole: String, _ short: String, size: CGFloat, lines: Int = 1) {
        self.whole = whole; self.short = short; self.size = size; self.lines = lines
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(whole).fixedSize(horizontal: lines == 1, vertical: false)
            line(short).fixedSize(horizontal: lines == 1, vertical: false)
            line(short)
        }
    }

    private func line(_ words: String) -> some View {
        Text(words)
            .font(.system(size: size, weight: .bold))
            .lineLimit(lines)
            .minimumScaleFactor(0.75)
            .widgetAccentable()
    }
}

/// The film's own icon, or the page's symbol for a film with none, or the
/// app's for the app itself. In its colour where colour shows; white on a
/// film-coloured tile; the lock screen's one tint elsewhere.
struct FilmGlyph: View {
    let shortcut: LockShortcut
    let side: CGFloat
    /// In the film's own colour (the Eyebrow square's capitals).
    var tinted: Bool
    var onColour = false

    var body: some View {
        if let path = shortcut.markPath {
            Outline.Shape(d: path)
                .fill(fill)
                .frame(width: side, height: side)
                .widgetAccentable()
        } else {
            Image(systemName: shortcut.glyph)
                .font(.system(size: side * 0.8, weight: .medium))
                .foregroundStyle(fill)
                .frame(width: side, height: side)
        }
    }

    private var fill: AnyShapeStyle {
        if onColour { return AnyShapeStyle(Color.white) }
        if tinted { return AnyShapeStyle(ShortcutFace.readable(Color(markHex: shortcut.markColour ?? "#0A84FF"))) }
        return AnyShapeStyle(.primary)
    }
}

extension ShortcutFace {
    /// A colour drawn as small type on the dark card: a dark one (Notion's
    /// brown, a deep red) is lifted toward white until it reads.
    static func readable(_ colour: Color) -> Color {
        let ui = UIColor(colour)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let light = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard light < 0.45 else { return colour }
        let lift = min(0.6, (0.45 - light) * 1.4)
        return Color(.sRGB, red: r + (1 - r) * lift, green: g + (1 - g) * lift, blue: b + (1 - b) * lift)
    }
}

/// The page a shortcut opens, as a small badge: a filled disc with the page's
/// symbol cut out of it and a thin gap around it, so on the lock screen's one
/// tint it reads as a knock-out over the project's icon.
struct PageBadge: View {
    let symbol: String
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.black).frame(width: side + side * 0.16, height: side + side * 0.16)
            Circle().fill(.primary).frame(width: side, height: side)
            Image(systemName: symbol)
                .font(.system(size: side * 0.52, weight: .bold))
                .foregroundStyle(Color.black)
        }
        .widgetAccentable()
    }

    /// "Harbour Light Affair" → "TC": the first letters of the first two
    /// words that are not "The" or "A".
    static func initials(_ title: String) -> String {
        let skip: Set<String> = ["the", "a", "an"]
        let words = title.split(separator: " ").filter { !skip.contains($0.lowercased()) }
        let letters = (words.isEmpty ? title.split(separator: " ") : words).prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}
