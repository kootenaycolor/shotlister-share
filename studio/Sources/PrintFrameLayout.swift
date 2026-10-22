import CoreGraphics
import Foundation

/// **Where each frame of a Print Frame sits on its board** — a port of
/// `layout()`, `suggest()` and `mixed()` in `design/45-print-frame.html`,
/// which is the approved drawing. Change one, change the other.
///
/// Every frame keeps its own shape (`ratios`, width over height): nothing is
/// cropped or stretched, so the layout changes the *board's* shape instead.
/// Cells are in board units: the board is 1 wide and `height` tall, with a
/// gutter of 0.028 of the width between frames, as `Filmstrip.swift`.
enum PrintFrameLayout {
    static let gutter: CGFloat = 0.028

    struct Cell: Equatable {
        var x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        func rect(width: CGFloat) -> CGRect {
            CGRect(x: x * width, y: y * width, width: w * width, height: h * width)
        }
    }

    struct Board: Equatable {
        var cells: [Cell]
        /// The board's height when it is 1 wide.
        var height: CGFloat
    }

    /// The grids: columns × rows. They need every frame the same shape.
    static let grids: [String: (columns: Int, rows: Int)] =
        ["grid22": (2, 2), "grid32": (3, 2), "grid23": (2, 3)]

    /// Whether the frames are not all one shape (to three places, as the
    /// mockup's `toFixed(3)`).
    static func mixed(_ ratios: [CGFloat]) -> Bool {
        Set(ratios.map { String(format: "%.3f", Double($0)) }).count > 1
    }

    /// Whether `kind` places every one of `count` frames with no gap.
    static func fits(_ kind: String, count n: Int) -> Bool {
        guard n >= 1 else { return false }
        switch kind {
        case "one": return n == 1
        case "grid22": return n == 4
        case "grid32", "grid23": return n == 6
        case "side", "under": return n >= 2
        case "across", "stacked", "rows", "cols": return true
        default: return false
        }
    }

    /// A layout that can draw these frames: fits the count, and a grid only
    /// when every frame is one shape.
    static func usable(_ kind: String, _ ratios: [CGFloat]) -> Bool {
        fits(kind, count: ratios.count) && !(grids[kind] != nil && mixed(ratios))
    }

    // ---- the layouts ----------------------------------------------------------

    static func layout(_ kind: String, _ ratios: [CGFloat]) -> Board {
        let rs = ratios.map { max($0, 0.05) }
        let n = rs.count, g = gutter
        guard n > 0 else { return Board(cells: [], height: 1) }

        // Justified rows: one height per row, each row exactly the width.
        func rows(_ split: [Int]) -> Board {
            var y: CGFloat = 0, i = 0
            var out: [Cell] = []
            for k in split {
                let q = rs[i..<min(i + k, n)]
                let h = (1 - g * CGFloat(k - 1)) / q.reduce(0, +)
                var x: CGFloat = 0
                for r in q { out.append(Cell(x: x, y: y, w: h * r, h: h)); x += h * r + g }
                y += h + g
                i += k
            }
            return Board(cells: out, height: y - g)
        }
        // Justified columns: one width per column, every column the height.
        func cols(_ split: [Int]) -> Board {
            let k = split.count
            var i = 0
            var S: [CGFloat] = [], M: [Int] = []
            for m in split {
                S.append(rs[i..<min(i + m, n)].reduce(0) { $0 + 1 / $1 })
                M.append(m)
                i += m
            }
            var extra: CGFloat = 0
            for j in 0..<k { extra += CGFloat(M[j] - 1) / S[j] }
            let H = (1 - g * CGFloat(k - 1) + g * extra) / S.reduce(0) { $0 + 1 / $1 }
            var out: [Cell] = []
            var x: CGFloat = 0
            i = 0
            for (j, m) in split.enumerated() {
                let w = (H - g * CGFloat(m - 1)) / S[j]
                var y: CGFloat = 0
                for _ in 0..<m {
                    let h = w / rs[i]
                    out.append(Cell(x: x, y: y, w: w, h: h))
                    y += h + g
                    i += 1
                }
                x += w + g
            }
            return Board(cells: out, height: H)
        }

        switch kind {
        case "one":
            return rows([1])
        case "across":
            return rows([n])
        case "stacked":
            return cols([n])
        case "side" where n >= 2:
            let rL = rs[0], k = n - 1
            let S = rs[1...].reduce(0) { $0 + 1 / $1 }
            let Hb = (1 - g + g * CGFloat(k - 1) / S) / (rL + 1 / S)
            let wb = Hb * rL, ws = (Hb - g * CGFloat(k - 1)) / S
            var out = [Cell(x: 0, y: 0, w: wb, h: Hb)]
            var y: CGFloat = 0
            for i in 1..<n {
                let h = ws / rs[i]
                out.append(Cell(x: wb + g, y: y, w: ws, h: h))
                y += h + g
            }
            return Board(cells: out, height: Hb)
        case "under" where n >= 2:
            let hb = 1 / rs[0]
            let q = Array(rs[1...])
            let h = (1 - g * CGFloat(q.count - 1)) / q.reduce(0, +)
            var out = [Cell(x: 0, y: 0, w: 1, h: hb)]
            var x: CGFloat = 0
            for r in q { out.append(Cell(x: x, y: hb + g, w: h * r, h: h)); x += h * r + g }
            return Board(cells: out, height: hb + g + h)
        case "rows":
            return rows(split(n, lines: (n + 2) / 3))
        case "cols":
            return cols(split(n, lines: n == 1 ? 1 : max(2, (n + 2) / 3)))
        default:
            if let grid = grids[kind] {
                let c = grid.columns, ro = grid.rows
                let w = (1 - g * CGFloat(c - 1)) / CGFloat(c), h = w / rs[0]
                let out = (0..<n).map { i in
                    Cell(x: CGFloat(i % c) * (w + g), y: CGFloat(i / c) * (h + g), w: w, h: h)
                }
                return Board(cells: out, height: CGFloat(ro) * h + g * CGFloat(ro - 1))
            }
            return rows(split(n, lines: (n + 2) / 3))
        }
    }

    /// `n` frames over `lines` rows (or columns), the longer ones last — the
    /// mockup's 4 → 2 + 2, 5 → 2 + 3, 6 → 3 + 3, carried on past six.
    private static func split(_ n: Int, lines: Int) -> [Int] {
        let k = max(1, min(lines, n))
        let base = n / k, extra = n % k
        return (0..<k).map { $0 >= k - extra ? base + 1 : base }
    }

    // ---- what is offered ---------------------------------------------------

    /// The layouts offered for a count, in the mockup's order (`LAYS`).
    static func options(count n: Int) -> [(kind: String, name: String)] {
        switch n {
        case ...1: return [("one", "One")]
        case 2: return [("across", "Two Across"), ("stacked", "Two Stacked")]
        case 3: return [("across", "Three Across"), ("side", "One + Two"),
                        ("under", "One + Two Under"), ("stacked", "Stacked"), ("cols", "Columns")]
        case 4: return [("grid22", "Grid"), ("across", "Four Across"),
                        ("under", "One + Three Under"), ("side", "One + Three"), ("rows", "Rows")]
        case 5: return [("under", "One + Four Under"), ("side", "One + Four"),
                        ("across", "Row"), ("rows", "Rows")]
        case 6: return [("grid32", "Grid 3 × 2"), ("grid23", "Grid 2 × 3"),
                        ("under", "One + Five Under"), ("across", "Row"), ("rows", "Rows")]
        default:
            let rest = word(n - 1)
            return [("under", "One + \(rest) Under"), ("side", "One + \(rest)"),
                    ("across", "Row"), ("rows", "Rows"), ("cols", "Columns")]
        }
    }

    private static func word(_ n: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
                     "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen"]
        return n < words.count ? words[n] : String(n)
    }

    /// **Suggested**: the frames print biggest without the board standing
    /// taller than it is wide (or than one frame, for a film that is itself
    /// tall). Nil when nothing offered fits under that.
    static func suggest(_ options: [(kind: String, name: String)], _ ratios: [CGFloat],
                        film r: CGFloat) -> String? {
        let cap = max(0.9, 1 / max(r, 0.01))
        var best: String?
        var score: CGFloat = -1
        for (kind, _) in options where usable(kind, ratios) {
            let board = layout(kind, ratios)
            if board.height > cap + 1e-6 { continue }
            let small = board.cells.map { $0.w * $0.h }.min() ?? 0
            if small > score { score = small; best = kind }
        }
        return best
    }

    /// The layout actually drawn: the one asked for when it can draw these
    /// frames, else the suggestion, else Rows (which takes anything).
    static func resolved(_ kind: String, _ ratios: [CGFloat], film r: CGFloat) -> String {
        if usable(kind, ratios) { return kind }
        let offered = options(count: ratios.count)
        return suggest(offered, ratios, film: r)
            ?? offered.first(where: { usable($0.kind, ratios) })?.kind
            ?? "rows"
    }

    /// How tall the board is against a single frame of the film.
    static func tallness(_ board: Board, film r: CGFloat) -> CGFloat { board.height * r }

    /// The narrowest frame, as a share of the board's width.
    static func smallest(_ board: Board) -> CGFloat { board.cells.map(\.w).min() ?? 1 }

    /// `0.5×`, `1.35×`, `2.0×` — the mockup's `fmtX`.
    static func times(_ v: CGFloat) -> String {
        var s = String(format: "%.2f", (Double(v) * 100).rounded() / 100)
        if s.hasSuffix("0") { s.removeLast() }
        return s + "\u{00D7}"
    }
}
