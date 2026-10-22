import Foundation

/// **How cells travel on the clipboard**, the way a sheet writes them: tabs
/// between cells, a line between rows, and a cell that holds a tab, a line
/// or a quote wrapped in quotes with its own quotes doubled.
///
/// Before this, a Notes cell with two lines copied as two lines, and pasting
/// it anywhere read them as two rows — one copy landed in two shots. And a
/// block copied out of Sheets ends in a line break, which read as one more,
/// empty row and cleared the cell under the block.
enum CellClip {
    /// Rows of cells, as the text that goes on the clipboard. A lone plain
    /// value is written as itself, so it pastes into any other program as
    /// the words it is.
    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(quoted).joined(separator: "\t") }
            .joined(separator: "\n")
    }

    private static func quoted(_ value: String) -> String {
        guard value.contains(where: { "\t\n\r\"".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The cells in the text, row by row. A quoted cell keeps its tabs and
    /// lines; one final line break ends the last row rather than starting
    /// another.
    static func decode(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var inQuotes = false
        var wasQuoted = false
        var atStart = true
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n"))
        var at = 0
        func endCell() { row.append(cell); cell = ""; wasQuoted = false; atStart = true }
        while at < chars.count {
            let c = chars[at]
            if inQuotes {
                if c == "\"" {
                    if at + 1 < chars.count, chars[at + 1] == "\"" {
                        cell.append("\""); at += 2; continue
                    }
                    inQuotes = false
                } else {
                    cell.append(c)
                }
            } else if c == "\"" && atStart && closes(chars, from: at) {
                inQuotes = true; wasQuoted = true; atStart = false
            } else if c == "\t" {
                endCell()
            } else if c == "\n" {
                endCell()
                rows.append(row); row = []
            } else {
                cell.append(c); atStart = false
            }
            at += 1
        }
        // The last row has no line break after it, or has just had its one.
        if !(row.isEmpty && cell.isEmpty && !wasQuoted && !rows.isEmpty) {
            endCell()
            rows.append(row)
        }
        return rows.isEmpty ? [[""]] : rows
    }

    /// Whether the quote at `from` opens a quoted cell: one that closes and
    /// is then followed by a tab, a line or the end. Words that merely begin
    /// with a quote ("Quiet," he said) stay as typed.
    private static func closes(_ chars: [Character], from: Int) -> Bool {
        var at = from + 1
        while at < chars.count {
            if chars[at] == "\"" {
                if at + 1 < chars.count, chars[at + 1] == "\"" { at += 2; continue }
                return at + 1 == chars.count || chars[at + 1] == "\t" || chars[at + 1] == "\n"
            }
            at += 1
        }
        return false
    }

    /// Whether the clipboard holds more than one cell's worth.
    static func spills(_ text: String) -> Bool {
        let grid = decode(text)
        return grid.count > 1 || (grid.first?.count ?? 0) > 1
    }
}
