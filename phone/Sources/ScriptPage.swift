import Foundation

/// The script, for the scene he is standing in.
///
/// **The page, not a paraphrase.** A screenplay is laid out the way it is for a
/// reason — a character name is centred, dialogue is narrow, action runs the
/// width — and a cinematographer reading a scene on a set is reading the shape
/// as much as the words. The engine lays the pages out; this draws the lines
/// belonging to one scene, at the indents the engine gave them.
struct Script: Decodable {
    var revision: String
    var name: String
    var pages: Int
    var measure: Int
    var pageList: [Page]
    /// Every scene the script has, with the page it starts on — for jumping.
    /// Optional so an older engine's reply still reads.
    var scenes: [Extent]?
    /// **Which shots hold which lines** (Ref 1553), read by the engine against
    /// this draft: each shot's stretches here, and the words a shot holds
    /// that this draft no longer has. Optional so an older engine's reply
    /// still reads.
    var ties: [Tie]?
    var lost: [Lost]?

    struct Tie: Decodable {
        var shot: String
        var number: String
        var spans: [[Int]]
    }

    struct Lost: Decodable {
        var shot: String
        var number: String
        var words: [String]
    }

    struct Extent: Decodable {
        var label: String
        var heading: String
        var startsOnPage: Int
    }

    struct Page: Decodable {
        var number: Int
        var lines: [Line]
    }

    struct Line: Decodable {
        var row: Int
        var indent: Int
        var kind: String
        var text: String
        var scene: String?
        /// **The paginator's own words**, not the writer's — `(MORE)` at the
        /// foot of a page and `CHARACTER (CONT'D)` at the top of the next.
        var added: Bool
        /// Where the line sits in the draft's text (absent on the
        /// paginator's own words), and the shots whose lines cover it.
        var from: Int?
        var to: Int?
        var shots: [String]?
    }

    /// One line as it is actually drawn: on the monospaced grid, and knowing
    /// whether it is the writer's or the page's.
    struct Drawn: Identifiable {
        let id: Int
        let text: String
        let faded: Bool
    }

    /// Every line of one scene, **with the blank lines the layout actually
    /// has between them**.
    ///
    /// The gaps are the whole thing. A screenplay is mostly whitespace, and it
    /// is what makes an action block read as separate from the cue under it.
    /// The engine sends only the lines that have something on them, each with
    /// the row it sits on, so the empty rows are rebuilt from the numbers
    /// rather than guessed at.
    ///
    /// Without this the phone drew every line of a scene hard against the next
    /// one, and a page break — `(MORE)`, then `CHARACTER (CONT'D)` — came out
    /// as a stack of names with nothing under them. He saw it in a real script, scene 2, and said plainly that the Mac does not do it. The Mac
    /// has always rebuilt the gaps; this is `ScriptPanel.extract`.
    func drawn(ofScene label: String) -> [Drawn] {
        var out: [Drawn] = []
        var lastPage = -1
        var lastRow = -1
        var at = 0
        for page in pageList {
            for line in page.lines where line.scene == label {
                if lastPage == page.number, line.row > lastRow + 1 {
                    for _ in 0 ..< (line.row - lastRow - 1) {
                        out.append(Drawn(id: at, text: " ", faded: false)); at += 1
                    }
                } else if lastPage != -1, lastPage != page.number {
                    out.append(Drawn(id: at, text: " ", faded: false)); at += 1
                }
                // Indented with spaces rather than a margin: everything sits on
                // one monospaced grid, so a centred cue is centred where the
                // engine put it.
                out.append(Drawn(id: at,
                                 text: String(repeating: " ", count: max(0, line.indent)) + line.text,
                                 faded: line.added))
                at += 1
                lastPage = page.number
                lastRow = line.row
            }
        }
        return out
    }
}
