import Foundation

/// **What a file is called once it is in a project.**
///
/// Called `FileNames` rather than `Naming` because the Mac already has a
/// `Naming` — a small record used when a room is being named — and two things
/// of one name in one compile is an error rather than a shrug.
///
/// Ref 273, and his words: *"Photos in mood boards should keep their own names.
/// Photos in locations should be renamed based on the location and area (if
/// there is an area) that they are located in — `mansion-kitchen-01.jpg`."*
///
/// Both apps take photographs onto a location — the Mac by dropping a file on
/// one, the phone by pointing a camera at the room — so the rule cannot live in
/// either of them. This is the half that is pure arithmetic on a string; each
/// shell still decides *when* to apply it, because each knows its own owners.
enum FileNames {
    /// `Hillcrest House — Kitchen` → `hillcrest-house-kitchen`.
    ///
    /// Every run of anything that is not a letter or a number becomes one dash,
    /// so an em dash, a comma and three spaces all collapse to the same thing
    /// and the name stays typeable.
    static func slug(_ text: String) -> String {
        var out = ""
        var lastWasDash = true
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// `hillcrest-house-kitchen-03.jpg` — the next free number on that place.
    ///
    /// Numbered from what the place already holds and bumped past anything
    /// taken, so two photographs added in the same second cannot land on one
    /// name. Returns nil when there is nothing to make a name out of, and the
    /// caller falls back to whatever the file arrived as.
    static func onLocation(_ placeName: String, ext: String,
                           taken: [String], from count: Int) -> String? {
        let stem = slug(placeName)
        guard !stem.isEmpty else { return nil }
        let used = Set(taken.map { $0.lowercased() })
        var at = max(1, count + 1)
        while at < 1000 {
            let name = String(format: "%@-%02d.%@", stem, at, ext)
            if !used.contains(name.lowercased()) { return name }
            at += 1
        }
        return nil
    }
}

/// **Where a location's files live.**
///
/// A location has a `folder` — a name given once when it is made, so that
/// renaming the place cannot strand its scans and its papers. The trouble is
/// that only the phone ever gave one: a location or a room made on the Mac has
/// no folder at all, and every path the phone builds starts with it.
///
/// The result, found on 2026-08-22: a room scanned on the phone wrote itself to
/// `locations/scans/` — one shared bucket, outside any location — and the list
/// that draws a place's scans returns nothing for a nameless folder, so the
/// scan appeared to vanish the moment he tapped Done scanning.
///
/// **The location's own id is the answer when there is no folder.** It is
/// already unique, already permanent, and every device works it out the same
/// way without writing anything down — so two devices cannot each invent a
/// different folder for one room and strand half its files.
extension FileNames {
    static func locationFolder(id: String, folder: String) -> String {
        let named = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty ? id : named
    }
}

/// **What an exported file is called** — his ask from set, 2026-10-06: "smart
/// naming for all exported files that describes the file in detail, so i dont
/// have to do that manually. use a professional system".
///
/// The system is the one productions hand round: fixed fields in a fixed
/// order, underscores between fields, hyphens inside them, no spaces, a
/// sortable date last.
///
///     Film_Document_Scope_Issued.ext
///     Lets-Bake_Shot-List-Storyboard_Day-03-Oct-07_2026-10-06.pdf
///     Lets-Bake_Shot-List_Sc-12-Int-Kitchen-Day_2026-10-06.pdf
///     Lets-Bake_Shot-List_2026-10-06_v2.pdf
///
/// Scope is left out for the whole film. A name already in the folder is never
/// written over: the next one is `_v2`, then `_v3`, the way a revision is.
extension FileNames {
    static func export(film: String, document: String, scope: String? = nil,
                       issued: Date = Date(), ext: String) -> String {
        let fields = [part(film, longest: 32), document, scope.map { part($0, longest: 40) } ?? "",
                      isoDate(issued)]
        return fields.filter { !$0.isEmpty }.joined(separator: "_") + "." + ext
    }

    /// The document field, from the pages that are in the file, in order:
    /// `table` `storyboard` `document` `script` `avscript` `diagram`.
    static func document(sections: [String]) -> String {
        var words: [String] = []
        for section in sections {
            let word: String
            switch section {
            case "table": word = "Shot-List"
            case "document": word = sections.contains("table") ? "Doc" : "Shot-List-Doc"
            case "storyboard": word = "Storyboard"
            case "script", "avscript": word = "Script"
            case "diagram": word = "Diagram"
            case "workbook": word = "Shot-List"
            default: word = part(section, longest: 20)
            }
            if !words.contains(word) { words.append(word) }
        }
        return words.isEmpty ? "Shot-List" : words.joined(separator: "-")
    }

    /// `Day 3` on `2026-10-07` → `Day-03-Oct-07`. The number padded so a
    /// folder of days sorts in shooting order past Day 9.
    static func day(label: String, date: String) -> String {
        var out = label.split(separator: " ").map { word -> String in
            if let n = Int(word), n < 100 { return String(format: "%02d", n) }
            return String(word)
        }.joined(separator: " ")
        let read = DateFormatter()
        read.locale = Locale(identifier: "en_US_POSIX")
        read.dateFormat = "yyyy-MM-dd"
        if let when = read.date(from: date) {
            let say = DateFormatter()
            say.locale = Locale(identifier: "en_US_POSIX")
            say.dateFormat = "MMM-dd"
            out += " " + say.string(from: when)
        }
        return out
    }

    /// One scene: `Sc-12-Int-Kitchen-Day`. A few: `Sc-04-07-12`. Many:
    /// `Sc-04-to-31`.
    static func scenes(_ numbers: [String], heading: String? = nil) -> String {
        guard let first = numbers.first else { return "" }
        if numbers.count == 1 {
            let words = (heading ?? "").trimmingCharacters(in: .whitespaces)
            return words.isEmpty ? "Sc \(first)" : "Sc \(first) \(words)"
        }
        if numbers.count <= 4 { return "Sc " + numbers.joined(separator: " ") }
        return "Sc \(first) to \(numbers.last ?? first)"
    }

    /// `2026-10-06`, the issue date — sorts as text exactly as it sorts as time.
    static func isoDate(_ date: Date) -> String {
        let say = DateFormatter()
        say.locale = Locale(identifier: "en_US_POSIX")
        say.dateFormat = "yyyy-MM-dd"
        return say.string(from: date)
    }

    /// One field: words kept with their capitals, apostrophes dropped, every
    /// other run of punctuation or space one hyphen. `Let's Bake` → `Lets-Bake`.
    static func part(_ text: String, longest: Int) -> String {
        var out = ""
        var lastWasDash = true
        for character in text where character != "'" && character != "\u{2019}" {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        // Cut at a word, not through one.
        if out.count > longest {
            out = String(out.prefix(longest))
            if let cut = out.lastIndex(of: "-"), out.distance(from: out.startIndex, to: cut) > longest / 2 {
                out = String(out[..<cut])
            }
        }
        return out
    }

    /// The name itself when the folder has no file by it; otherwise the next
    /// free `_v2`, `_v3`… `also` names other extensions that travel with it
    /// (a PDF's workbook), so the pair keeps one version number.
    static func unused(_ name: String, in folder: URL?, also: [String] = []) -> String {
        guard let folder else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let exts = [ext] + also
        func taken(_ candidate: String) -> Bool {
            exts.contains { FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(candidate + "." + $0).path) }
        }
        if !taken(stem) { return name }
        var version = 2
        while version < 100, taken("\(stem)_v\(version)") { version += 1 }
        return "\(stem)_v\(version).\(ext)"
    }
}


/// **The name the export box offers in its file-name field** — his rule,
/// 2026-10-15: professional, all lowercase, hyphens and no spaces, no
/// punctuation, the date as `YYYYMMDD`. Project, document, what it covers,
/// the order, the date:
///
///     lets-bake-shot-list-schedule-order-20261015.pdf
///     lets-bake-shot-list-sc-12-script-order-20261015.pdf
///
/// The project is its drive name (the slug) when it has one. A name he types
/// himself is never touched; this is only what the field starts as.
extension FileNames {
    /// `Let's Bake` → `lets-bake`; apostrophes vanish rather than split.
    static func plain(_ text: String) -> String {
        slug(text.replacingOccurrences(of: "'", with: "")
                 .replacingOccurrences(of: "\u{2019}", with: ""))
    }

    /// `20261015`
    static func compactDate(_ date: Date) -> String {
        let say = DateFormatter()
        say.locale = Locale(identifier: "en_US_POSIX")
        say.dateFormat = "yyyyMMdd"
        return say.string(from: date)
    }

    /// `table` → `shot-list`; the pages in the file, in order, at most two
    /// named — three or more takes the lead page's name.
    static func documentWords(sections: [String]) -> String {
        var words: [String] = []
        for section in sections {
            let word: String
            switch section {
            case "table", "workbook": word = "shot-list"
            case "storyboard": word = "storyboard"
            case "document": word = "document"
            case "script", "avscript": word = "script"
            case "diagram": word = "diagram"
            default: word = plain(section)
            }
            if !word.isEmpty, !words.contains(word) { words.append(word) }
        }
        if words.isEmpty { return "shot-list" }
        // Three or more: the shot list names it, as the page that leads.
        if words.count > 2 { return words.contains("shot-list") ? "shot-list" : "full-set" }
        return words.joined(separator: "-")
    }

    /// `sc-12`, `sc-04-07-12`, `sc-04-to-31`.
    static func sceneWords(_ numbers: [String]) -> String {
        guard let first = numbers.first else { return "" }
        let clean = numbers.map { plain($0) }
        if numbers.count == 1 { return "sc-\(clean[0])" }
        if numbers.count <= 4 { return "sc-" + clean.joined(separator: "-") }
        return "sc-\(plain(first))-to-\(clean.last ?? "")"
    }

    static func exportAuto(project: String, document: String, scope: String = "",
                           order: String, issued: Date = Date()) -> String {
        [project, document, scope, order, compactDate(issued)]
            .filter { !$0.isEmpty }.joined(separator: "-")
    }
}
