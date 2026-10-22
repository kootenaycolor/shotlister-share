import SwiftUI

/// **The film's own icon, drawn rather than fetched.**
///
/// His instruction, 2026-09-05: *"lets have the desktop app respect what the
/// web app is doing. using the project accent color, and icon."*
///
/// The website already wears both. `hub/refresh.py` reads the film's Notion
/// row, keeps the **outline** of its icon rather than the address of it, and
/// every page of that film is drawn in the colour the icon came in. This is the
/// same two facts on the Mac, read off the copy his Projects Console already
/// keeps on this disk — so the browser and the app cannot disagree, and nothing
/// here asks the network for anything.
///
/// **Why an outline and not a picture.** AppKit cannot open an SVG at all; the
/// icon has to take a colour it is told rather than one baked into it; and it
/// has to stay sharp at thirteen points in the top bar and at any size a list
/// wants. A path does all three and a bitmap does none of them.
enum Outline {

    /// The drawing, in the icon's own twenty-by-twenty space.
    ///
    /// **Kept, because it is parsed once and drawn on every pass.** The top bar
    /// redraws on anything at all, and walking three hundred characters of path
    /// data each time is the same waste `Brand`'s colour memo exists to stop.
    private static let drawings = Memo<String, Path>()

    static func drawing(_ d: String) -> Path {
        drawings.value(for: d) { read($0) }
    }

    /// One Notion icon, as a shape any view can fill.
    ///
    /// It fits the square it is given and keeps its proportions — an icon
    /// squashed to a rectangle reads as a rendering fault, and every one of
    /// these is square to begin with.
    struct Shape: SwiftUI.Shape {
        let d: String

        func path(in rect: CGRect) -> Path {
            let side = min(rect.width, rect.height)
            guard side > 0 else { return Path() }
            let scale = side / 20
            var move = CGAffineTransform(
                translationX: rect.minX + (rect.width - side) / 2,
                y: rect.minY + (rect.height - side) / 2)
            move = move.scaledBy(x: scale, y: scale)
            return drawing(d).applying(move)
        }
    }

    // ---- reading the path data ---------------------------------------------

    /// **Everything SVG path data can say, and nothing it cannot.**
    ///
    /// Notion's own icons use `M m L l H h V v C c S s Q q A a z` between them,
    /// including the compact spellings — a number may begin with `-` or `.`
    /// with no separator before it, and a command's arguments may repeat
    /// without the letter being said again. All of that is ordinary SVG and all
    /// of it appears in his eleven projects, so all of it is read here.
    ///
    /// **It never throws and never half-draws.** Anything it cannot make sense
    /// of ends the walk and hands back what it had — a film whose icon is
    /// malformed gets no icon, which is the same as a film with no icon, rather
    /// than a crash or a scribble.
    private static func read(_ d: String) -> Path {
        var path = Path()
        var reader = Reader(Array(d))
        var here = CGPoint.zero
        var opened = CGPoint.zero
        var cubic: CGPoint?
        var quad: CGPoint?
        var command: Character = " "
        var drawn = false

        func point(_ x: CGFloat, _ y: CGFloat, _ relative: Bool) -> CGPoint {
            relative ? CGPoint(x: here.x + x, y: here.y + y) : CGPoint(x: x, y: y)
        }
        /// The mirror of the last control point through the current point —
        /// what `S` and `T` mean by "carry on smoothly".
        func mirrored(_ last: CGPoint?) -> CGPoint {
            guard let last else { return here }
            return CGPoint(x: 2 * here.x - last.x, y: 2 * here.y - last.y)
        }

        walk: while true {
            reader.skipSeparators()
            if reader.done { break }
            if reader.peekIsLetter {
                command = reader.takeLetter()
            } else if command == "M" {
                // A move with more than one pair of numbers draws lines with
                // the rest of them. This is the one implicit command that is
                // not simply the last one repeated.
                command = "L"
            } else if command == "m" {
                command = "l"
            } else if command == " " {
                break
            }

            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                guard let x = reader.number(), let y = reader.number() else { break walk }
                here = point(x, y, relative)
                opened = here
                path.move(to: here)
                drawn = true
                cubic = nil; quad = nil

            case "L":
                guard drawn, let x = reader.number(), let y = reader.number() else { break walk }
                here = point(x, y, relative)
                path.addLine(to: here)
                cubic = nil; quad = nil

            case "H":
                guard drawn, let x = reader.number() else { break walk }
                here = CGPoint(x: relative ? here.x + x : x, y: here.y)
                path.addLine(to: here)
                cubic = nil; quad = nil

            case "V":
                guard drawn, let y = reader.number() else { break walk }
                here = CGPoint(x: here.x, y: relative ? here.y + y : y)
                path.addLine(to: here)
                cubic = nil; quad = nil

            case "C":
                guard drawn,
                      let x1 = reader.number(), let y1 = reader.number(),
                      let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { break walk }
                let one = point(x1, y1, relative)
                let two = point(x2, y2, relative)
                here = point(x, y, relative)
                path.addCurve(to: here, control1: one, control2: two)
                cubic = two; quad = nil

            case "S":
                guard drawn,
                      let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { break walk }
                let one = mirrored(cubic)
                let two = point(x2, y2, relative)
                here = point(x, y, relative)
                path.addCurve(to: here, control1: one, control2: two)
                cubic = two; quad = nil

            case "Q":
                guard drawn,
                      let x1 = reader.number(), let y1 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { break walk }
                let one = point(x1, y1, relative)
                here = point(x, y, relative)
                path.addQuadCurve(to: here, control: one)
                quad = one; cubic = nil

            case "T":
                guard drawn, let x = reader.number(), let y = reader.number() else { break walk }
                let one = mirrored(quad)
                here = point(x, y, relative)
                path.addQuadCurve(to: here, control: one)
                quad = one; cubic = nil

            case "A":
                guard drawn,
                      let rx = reader.number(), let ry = reader.number(),
                      let turn = reader.number(),
                      let large = reader.flag(), let sweep = reader.flag(),
                      let x = reader.number(), let y = reader.number() else { break walk }
                let to = point(x, y, relative)
                arc(from: here, to: to, rx: rx, ry: ry, turn: turn,
                    large: large, sweep: sweep, into: &path)
                here = to
                cubic = nil; quad = nil

            case "Z":
                guard drawn else { break walk }
                path.closeSubpath()
                here = opened
                cubic = nil; quad = nil

            default:
                break walk
            }
        }
        return path
    }

    /// **An elliptical arc, as curves.**
    ///
    /// `Path` can draw a circle round a centre and nothing else; SVG says where
    /// the arc *ends* and leaves the centre to be worked out. This is that
    /// working-out — the conversion the SVG specification itself sets down —
    /// followed by cutting the sweep into quarter turns, which is the largest
    /// piece a cubic carries without visible error.
    private static func arc(from start: CGPoint, to end: CGPoint,
                            rx: CGFloat, ry: CGFloat, turn: CGFloat,
                            large: Bool, sweep: Bool, into path: inout Path) {
        if start == end { return }
        var rx = abs(rx), ry = abs(ry)
        // A radius of nothing is a straight line, and the specification says so
        // rather than leaving it to be divided by.
        guard rx > 0, ry > 0 else { path.addLine(to: end); return }

        let angle = turn * .pi / 180
        let cosT = cos(angle), sinT = sin(angle)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosT * dx + sinT * dy
        let y1 = -sinT * dx + cosT * dy

        // Radii too small to reach the far end are grown until they just do.
        let stretch = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if stretch > 1 {
            let by = sqrt(stretch)
            rx *= by; ry *= by
        }

        let bottom = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let top = max(0, rx * rx * ry * ry - bottom)
        let reach = bottom == 0 ? 0 : (large == sweep ? -1.0 : 1.0) * sqrt(top / bottom)
        let cx1 = reach * rx * y1 / ry
        let cy1 = -reach * ry * x1 / rx
        let cx = cosT * cx1 - sinT * cy1 + (start.x + end.x) / 2
        let cy = sinT * cx1 + cosT * cy1 + (start.y + end.y) / 2

        func between(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard length > 0 else { return 0 }
            var found = acos(min(1, max(-1, (ux * vx + uy * vy) / length)))
            if ux * vy - uy * vx < 0 { found = -found }
            return found
        }
        let fromX = (x1 - cx1) / rx, fromY = (y1 - cy1) / ry
        let toX = (-x1 - cx1) / rx, toY = (-y1 - cy1) / ry
        let opening = between(1, 0, fromX, fromY)
        var across = between(fromX, fromY, toX, toY)
        if !sweep, across > 0 { across -= 2 * .pi }
        if sweep, across < 0 { across += 2 * .pi }

        let pieces = max(1, Int(ceil(abs(across) / (.pi / 2))))
        let step = across / CGFloat(pieces)
        let pull = 4.0 / 3.0 * tan(step / 4)
        var at = opening
        for _ in 0..<pieces {
            let next = at + step
            func on(_ t: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * cos(t) * cosT - ry * sin(t) * sinT,
                        y: cy + rx * cos(t) * sinT + ry * sin(t) * cosT)
            }
            func along(_ t: CGFloat) -> CGPoint {
                CGPoint(x: -rx * sin(t) * cosT - ry * cos(t) * sinT,
                        y: -rx * sin(t) * sinT + ry * cos(t) * cosT)
            }
            let a = on(at), b = on(next)
            let da = along(at), db = along(next)
            path.addCurve(
                to: b,
                control1: CGPoint(x: a.x + pull * da.x, y: a.y + pull * da.y),
                control2: CGPoint(x: b.x - pull * db.x, y: b.y - pull * db.y))
            at = next
        }
    }

    /// A walk along the path data, one number at a time.
    private struct Reader {
        private let said: [Character]
        private var at = 0

        init(_ characters: [Character]) { said = characters }

        var done: Bool { at >= said.count }
        var peekIsLetter: Bool { !done && said[at].isLetter }

        mutating func takeLetter() -> Character {
            let letter = said[at]
            at += 1
            return letter
        }

        mutating func skipSeparators() {
            while !done, said[at] == " " || said[at] == "," || said[at] == "\n"
                || said[at] == "\r" || said[at] == "\t" {
                at += 1
            }
        }

        /// One number, in any of the spellings path data allows: `12`, `-.5`,
        /// `1.5e-3`. **A second full stop begins a second number** — `.5.5` is
        /// two of them, which is how the compact form saves its bytes.
        mutating func number() -> CGFloat? {
            skipSeparators()
            let from = at
            if !done, said[at] == "+" || said[at] == "-" { at += 1 }
            var digits = false
            while !done, said[at].isNumber { at += 1; digits = true }
            if !done, said[at] == "." {
                at += 1
                while !done, said[at].isNumber { at += 1; digits = true }
            }
            guard digits else { at = from; return nil }
            // An exponent only counts when something follows it; otherwise the
            // `e` belongs to whatever comes next.
            if !done, said[at] == "e" || said[at] == "E" {
                let mark = at
                at += 1
                if !done, said[at] == "+" || said[at] == "-" { at += 1 }
                var power = false
                while !done, said[at].isNumber { at += 1; power = true }
                if !power { at = mark }
            }
            guard let value = Double(String(said[from..<at])) else { return nil }
            return CGFloat(value)
        }

        /// An arc's two flags, which are one character each and are allowed to
        /// arrive with nothing between them — `a1 1 0 011 0-2.5` is legal.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard !done, said[at] == "0" || said[at] == "1" else { return nil }
            let one = said[at] == "1"
            at += 1
            return one
        }
    }
}

/// The film's mark, at the size asked for, in the colour it came in.
///
/// Nothing when the film has none — a film without an icon gets its name and no
/// gap where a picture should be, which is what the website does.
struct FilmIcon: View {
    let mark: Console.Mark
    var size: CGFloat = 14

    var body: some View {
        Outline.Shape(d: mark.path)
            .fill(Brand.hex(mark.colour))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
