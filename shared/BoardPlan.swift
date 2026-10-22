import SwiftUI

/// **How the Storyboard lays its cards out** — rows that share a picture
/// height, each card as wide as its own picture is. His ask, 2026-10-15: the
/// board formats itself to the shape of each shot's picture area, which is the
/// shot's own Print Frame when it has one and the film's frame when it does
/// not. This is only arithmetic, so it can be asked without a window.
///
/// With one shape on the board it is the old grid: the same number of equal
/// cards on a row, stretched to fill it.
enum BoardPlan {
    /// A card's width that is not picture: its padding (8 + 8) and the air
    /// either side of the picture (3 + 3).
    static let chrome: CGFloat = 22

    struct Slot: Equatable {
        var index: Int
        /// The whole card.
        var width: CGFloat
        /// The picture area, in its own shape. Never wider than the card's
        /// inside; centred when the card is wider (a narrow picture gets a
        /// card wide enough to read).
        var pictureWidth: CGFloat
        var pictureHeight: CGFloat
    }

    /// The narrowest a card may be, so its words still read.
    static func narrowest(_ cardWidth: CGFloat) -> CGFloat { min(cardWidth, 150) }

    /// A picture area's shape: the baked Print Frame's, else the film's.
    static func shape(_ baked: (CGFloat, CGFloat)?, film: CGFloat) -> CGFloat {
        if let (w, h) = baked, w > 0, h > 0 { return w / h }
        return max(film, 0.05)
    }

    static func rows(ratios: [CGFloat], width W: CGFloat, cardWidth: CGFloat,
                     film: CGFloat, gutter G: CGFloat, chrome C: CGFloat = chrome) -> [[Slot]] {
        guard !ratios.isEmpty else { return [] }
        let film = max(film, 0.05)
        let lowest = narrowest(cardWidth)
        // The height a card of the film's shape has at the slider's width.
        let h0 = max(1, (cardWidth - C) / film)
        func wide(_ r: CGFloat, _ h: CGFloat) -> CGFloat { max(lowest, h * r + C) }

        // Which cards share a row: as many as fit at the natural height — the
        // adaptive grid's own rule when the shapes agree.
        var lines: [[Int]] = []
        var line: [Int] = []
        var used: CGFloat = 0
        for (i, r) in ratios.enumerated() {
            let w = min(wide(r, h0), W)
            let need = line.isEmpty ? w : w + G
            if !line.isEmpty && used + need > W + 0.5 {
                lines.append(line); line = []; used = 0
            }
            used += line.isEmpty ? w : w + G
            line.append(i)
        }
        if !line.isEmpty { lines.append(line) }

        // The height that makes a line fill the width exactly.
        func fill(_ line: [Int]) -> CGFloat {
            let room = W - G * CGFloat(line.count - 1)
            var lo = h0, hi = max(h0, W * 4)
            if line.reduce(0, { $0 + wide(ratios[$1], lo) }) >= room { return lo }
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if line.reduce(0, { $0 + wide(ratios[$1], mid) }) > room { hi = mid } else { lo = mid }
            }
            return lo
        }
        // What a full row of the film's own shape would stand at: the cap for
        // a short last row, so it keeps its neighbours' size instead of
        // blowing up to fill.
        let across = max(1, Int((W + G) / (cardWidth + G)))
        let full = max(h0, ((W - G * CGFloat(across - 1)) / CGFloat(across) - C) / film)

        var out: [[Slot]] = []
        var previous: CGFloat?
        for (n, members) in lines.enumerated() {
            var h = fill(members)
            if n == lines.count - 1 { h = min(h, previous ?? full) }
            previous = h
            out.append(members.map { i in
                let w = min(wide(ratios[i], h), W)
                let pw = min(h * ratios[i], w - C)
                return Slot(index: i, width: w, pictureWidth: max(1, pw),
                            pictureHeight: max(1, pw / ratios[i]))
            })
        }
        return out
    }

    /// ↑ / ↓ across rows of different lengths: the card in the next row whose
    /// middle is nearest this one's. Falls back to a fixed count per row
    /// while the layout has not reported.
    static func step(_ dir: Int, from id: String, rows: [[String]],
                     frames: [String: CGRect], shown: [String], fallback per: Int) -> Int {
        let at = shown.firstIndex(of: id) ?? 0
        guard let r = rows.firstIndex(where: { $0.contains(id) }) else {
            return at + dir * per
        }
        let to = r + dir
        guard rows.indices.contains(to), !rows[to].isEmpty else { return at }
        let here = frames[id]?.midX
        let pick: String
        if let here {
            pick = rows[to].min { abs((frames[$0]?.midX ?? .infinity) - here)
                                   < abs((frames[$1]?.midX ?? .infinity) - here) } ?? rows[to][0]
        } else {
            pick = rows[to][min(rows[r].firstIndex(of: id) ?? 0, rows[to].count - 1)]
        }
        return shown.firstIndex(of: pick) ?? at
    }
}
