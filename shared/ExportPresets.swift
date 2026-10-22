import Foundation
import SwiftUI

// MARK: - What the engine says about the Table

/// **The Table as the export box sees it** — the engine's `exportinfo`: the
/// filter in words, the sort, and every shoot day of the film (whatever the
/// shoot picker is on), with the shoots, for the Days picker. 2026-10-15.
struct ExportInfo: Decodable, Equatable {
    struct Day: Decodable, Identifiable, Hashable {
        var id: String
        var label: String
        var date: String
        var count: Int
        var wrapped: Bool
        var shoot: String
    }
    struct Shoot: Decodable, Hashable {
        var id: String
        var label: String
    }
    var filter: [String]
    var sort: String
    var descending: Bool
    var shooting: Bool
    var unscheduled: Int
    var days: [Day]
    var shoots: [Shoot]

    static let empty = ExportInfo(filter: [], sort: "", descending: false, shooting: false,
                                  unscheduled: 0, days: [], shoots: [])
}

/// The three orders the export can be read in.
enum ExportArrange: String, CaseIterable, Codable {
    case table, script, schedule
}

// MARK: - Days

/// **Which days, as a rule, never as day ids** — so a preset works on any
/// film. A hand-picked set is kept by day number (its place in the
/// schedule), which every film has.
struct DaysRule: Codable, Equatable {
    /// `all`, `next`, `thisweek`, `nextweek`, `shoot`, `range`, `numbers`.
    var kind: String
    var from: Int? = nil
    var to: Int? = nil
    var numbers: [Int]? = nil
    var shoot: Int? = nil
    /// Whether the unscheduled come along. Ticked unless said otherwise.
    var unscheduled: Bool? = nil

    static let all = DaysRule(kind: "all")

    var title: String {
        switch kind {
        case "all": return "All Days"
        case "next": return "Next Day"
        case "thisweek": return "This Week"
        case "nextweek": return "Next Week"
        case "shoot": return "Shoot \(shoot ?? 1)"
        case "range": return "Days \(from ?? 1)–\(to ?? 1)"
        default: return "Picked days"
        }
    }
}

enum ExportDays {
    static let unscheduled = "unscheduled"

    /// `2026-11-17` → a date, at noon so no time zone tips it a day.
    static func date(_ text: String) -> Date? {
        let say = DateFormatter()
        say.locale = Locale(identifier: "en_US_POSIX")
        say.timeZone = .current
        say.dateFormat = "yyyy-MM-dd"
        guard let day = say.date(from: String(text.prefix(10))) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: day)
    }

    /// The Monday a date's week starts on.
    static func monday(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// `Mon Nov 2`
    static func short(_ date: Date) -> String {
        let say = DateFormatter()
        say.locale = Locale(identifier: "en_US_POSIX")
        say.dateFormat = "EEE MMM d"
        return say.string(from: date)
    }

    /// `Nov 2`
    static func monthDay(_ date: Date) -> String {
        let say = DateFormatter()
        say.locale = Locale(identifier: "en_US_POSIX")
        say.dateFormat = "MMM d"
        return say.string(from: date)
    }

    /// **The days a rule picks**, by id, on this film, today. The
    /// unscheduled ride along unless the rule says not.
    static func pick(_ rule: DaysRule, in info: ExportInfo, today: Date = Date()) -> Set<String> {
        let days = info.days
        var out: Set<String> = []
        let number = { (at: Int) in at + 1 }
        switch rule.kind {
        case "next":
            let start = Calendar.current.startOfDay(for: today)
            let open = days.filter { !$0.wrapped }
            if let dated = open.first(where: { (date($0.date) ?? .distantPast) >= start }) {
                out = [dated.id]
            } else if open.allSatisfy({ date($0.date) == nil }), let first = open.first {
                out = [first.id]
            }
        case "thisweek", "nextweek":
            var week = monday(today)
            if rule.kind == "nextweek" {
                week = Calendar.current.date(byAdding: .day, value: 7, to: week) ?? week
            }
            out = Set(days.filter { day in
                guard let at = date(day.date) else { return false }
                return monday(at) == week
            }.map(\.id))
        case "shoot":
            let wanted = (rule.shoot ?? 1) - 1
            if info.shoots.indices.contains(wanted) {
                let shoot = info.shoots[wanted].id
                out = Set(days.filter { $0.shoot == shoot }.map(\.id))
            }
        case "range":
            let from = rule.from ?? 1, to = rule.to ?? days.count
            out = Set(days.enumerated().filter { number($0.offset) >= min(from, to) && number($0.offset) <= max(from, to) }.map(\.element.id))
        case "numbers":
            let wanted = Set(rule.numbers ?? [])
            out = Set(days.enumerated().filter { wanted.contains(number($0.offset)) }.map(\.element.id))
        default:
            out = Set(days.map(\.id))
        }
        // The unscheduled go with All Days, and with any rule that says so.
        let loose = rule.unscheduled ?? (rule.kind == "all")
        if loose, info.unscheduled > 0 { out.insert(unscheduled) }
        return out
    }

    /// **The rule a hand pick amounts to**: one of the quick picks or a
    /// range when it is exactly that, else the day numbers.
    static func rule(for picked: Set<String>, in info: ExportInfo, today: Date = Date()) -> DaysRule {
        let loose = picked.contains(unscheduled)
        for kind in ["all", "next", "thisweek", "nextweek"] {
            let rule = DaysRule(kind: kind, unscheduled: loose)
            if !info.days.isEmpty, pick(rule, in: info, today: today) == picked { return rule }
        }
        for n in info.shoots.indices where info.shoots.count >= 2 {
            let rule = DaysRule(kind: "shoot", shoot: n + 1, unscheduled: loose)
            if pick(rule, in: info, today: today) == picked { return rule }
        }
        let numbers = numbersOf(picked, in: info)
        if let first = numbers.first, let last = numbers.last, numbers.count == last - first + 1, numbers.count > 1 {
            return DaysRule(kind: "range", from: first, to: last, unscheduled: loose)
        }
        return DaysRule(kind: "numbers", numbers: numbers, unscheduled: loose)
    }

    /// The day numbers picked, in order.
    static func numbersOf(_ picked: Set<String>, in info: ExportInfo) -> [Int] {
        info.days.enumerated().filter { picked.contains($0.element.id) }.map { $0.offset + 1 }
    }

    /// `[12,13,14,15,16,17,18,22]` → `[(12,18),(22,22)]`
    static func runs(_ numbers: [Int]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for n in numbers.sorted() {
            if let last = out.last, last.1 + 1 == n { out[out.count - 1].1 = n } else { out.append((n, n)) }
        }
        return out
    }

    /// **"Days 12–18, 22 (8 days)"** — what is picked, in one line.
    static func summary(_ picked: Set<String>, in info: ExportInfo) -> String {
        let numbers = numbersOf(picked, in: info)
        let loose = picked.contains(unscheduled) && info.unscheduled > 0
        if numbers.isEmpty { return loose ? "Unscheduled only" : "No days" }
        let all = numbers.count == info.days.count
        var said: String
        if all {
            said = "All \(numbers.count) day\(numbers.count == 1 ? "" : "s")"
        } else {
            let parts = runs(numbers).map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)–\($0.1)" }
            said = (numbers.count == 1 ? "Day " : "Days ") + parts.joined(separator: ", ")
            if numbers.count > 1 { said += " (\(numbers.count) days)" }
        }
        if loose { said += " + Unscheduled" }
        return said
    }

    /// `days-12-18-22`, `day-3` — the file name's part.
    static func nameWords(_ picked: Set<String>, in info: ExportInfo) -> String {
        let numbers = numbersOf(picked, in: info)
        guard !numbers.isEmpty else { return picked.contains(unscheduled) ? "unscheduled" : "" }
        if numbers.count == 1 { return "day-\(numbers[0])" }
        let parts = runs(numbers).flatMap { $0.0 == $0.1 ? ["\($0.0)"] : ["\($0.0)", "\($0.1)"] }
        return "days-" + parts.joined(separator: "-")
    }

    /// **The list, grouped**: by shoot when there are several, then by week.
    struct Week: Identifiable {
        var id: String
        var title: String
        var days: [(number: Int, day: ExportInfo.Day)]
    }
    struct Group: Identifiable {
        var id: String
        var title: String
        var weeks: [Week]
    }

    static func groups(of info: ExportInfo) -> [Group] {
        let numbered = info.days.enumerated().map { (number: $0.offset + 1, day: $0.element) }
        func weeks(_ days: [(number: Int, day: ExportInfo.Day)], prefix: String) -> [Week] {
            var out: [Week] = []
            for entry in days {
                let title: String
                if let at = date(entry.day.date) { title = "Week of " + monthDay(monday(at)) } else { title = "No date" }
                let id = prefix + title
                if let last = out.last, last.id == id { out[out.count - 1].days.append(entry) }
                else { out.append(Week(id: id, title: title, days: [entry])) }
            }
            return out
        }
        if info.shoots.count >= 2 {
            var out: [Group] = []
            for shoot in info.shoots {
                let mine = numbered.filter { $0.day.shoot == shoot.id }
                if !mine.isEmpty { out.append(Group(id: shoot.id, title: shoot.label, weeks: weeks(mine, prefix: shoot.id))) }
            }
            let known = Set(info.shoots.map(\.id))
            let rest = numbered.filter { !known.contains($0.day.shoot) }
            if !rest.isEmpty { out.append(Group(id: "noshoot", title: "No Shoot", weeks: weeks(rest, prefix: "noshoot"))) }
            return out
        }
        return [Group(id: "all", title: "", weeks: weeks(numbered, prefix: ""))]
    }
}

// MARK: - What the choices ask for, said once for both apps

/// **The Order, Filter and Days, as the engine and the file name hear
/// them** — one place for the Mac and the iPhone, so the same choices send
/// the engine the same words and draw the same page.
struct ExportChoice {
    var arrange: ExportArrange
    var useFilter: Bool
    var picked: Set<String>
    /// The whole film, rather than scenes picked.
    var whole: Bool
    var info: ExportInfo
    /// A column's name as he reads it (`size` → `Shot Size`).
    var label: (String) -> String

    var allDays: Set<String> {
        var all = Set(info.days.map(\.id))
        if info.unscheduled > 0 { all.insert(ExportDays.unscheduled) }
        return all
    }

    var daysAreAll: Bool { picked == allDays }

    /// `arrange=`, `filter=table`, `days=`, `daypages=1`.
    var narrowing: [String] {
        var out = ["arrange=\(arrange.rawValue)"]
        if useFilter { out.append("filter=table") }
        if arrange == .schedule {
            if whole, !daysAreAll {
                out.append("days=" + (picked.isEmpty ? "none" : picked.sorted().joined(separator: ",")))
            }
            out.append("daypages=1")
        }
        return out
    }

    /// `Shot Size`, `Shooting Order`, or nothing.
    var tableSortName: String {
        if info.shooting { return "Shooting Order" }
        return info.sort.isEmpty ? "" : label(info.sort)
    }

    /// **The Document page's corner, saying the real order** and what the
    /// file is narrowed to.
    var caption: String {
        var said: String
        switch arrange {
        case .table:
            if info.shooting { said = "SHOOTING ORDER" }
            else if !info.sort.isEmpty { said = "SORTED BY " + label(info.sort).uppercased() }
            else { said = "SCRIPT ORDER" }
        case .script: said = "SCRIPT ORDER"
        case .schedule:
            said = "SHOOTING ORDER"
            if whole, !daysAreAll { said += " · " + ExportDays.summary(picked, in: info).uppercased() }
        }
        if useFilter, !info.filter.isEmpty {
            said += " · " + info.filter.joined(separator: ", ").uppercased()
        }
        return said
    }

    /// **The order, as the name says it** — `sorted-by-shot-size`,
    /// `script-order`, `schedule-order`, or the days picked (`days-12-18`).
    var orderWords: String {
        switch arrange {
        case .table:
            var said: String
            if info.shooting { said = "schedule-order" }
            else if !info.sort.isEmpty { said = "sorted-by-" + FileNames.plain(label(info.sort)) }
            else { said = "script-order" }
            if useFilter, let day = info.filter.first(where: { $0.hasPrefix("Day ") }) {
                said += "-" + FileNames.plain(day)
            }
            return said
        case .script: return "script-order"
        case .schedule:
            if !whole || daysAreAll { return "schedule-order" }
            return ExportDays.nameWords(picked, in: info)
        }
    }

    /// Each day's own file in a File per day folder: `halcyon-shot-list-day-12-20261015`.
    func dayFileNames(project: String, document: String) -> [String: String] {
        var out: [String: String] = [:]
        for (at, day) in info.days.enumerated() {
            out[day.id] = FileNames.exportAuto(project: project, document: document, scope: "", order: "day-\(at + 1)")
        }
        out[ExportDays.unscheduled] = FileNames.exportAuto(project: project, document: document, scope: "",
                                                           order: "unscheduled")
        return out
    }

    /// A preset's name pattern, filled in.
    static func filled(_ pattern: String, project: String) -> String {
        pattern.replacingOccurrences(of: "{project}", with: project)
            .replacingOccurrences(of: "{date}", with: FileNames.compactDate(Date()))
    }

    /// His typed name as a pattern: the project and the date become the words
    /// that stand for them.
    static func pattern(from typed: String, project: String, ext: String) -> String {
        var out = typed.trimmingCharacters(in: .whitespaces)
        if out.lowercased().hasSuffix("." + ext) { out = String(out.dropLast(ext.count + 1)) }
        if !project.isEmpty { out = out.replacingOccurrences(of: project, with: "{project}") }
        return out.replacingOccurrences(of: FileNames.compactDate(Date()), with: "{date}")
    }
}

// MARK: - A preset

/// **One saved way of exporting** — his ask, 2026-10-15. Order, filter,
/// days *rule*, pages, columns, layout, paper and text size, one file or a
/// file a day, and the name pattern. Nothing in it is one film's: columns are
/// built-in names, days are a rule.
/// **What he asks of Auto** (2026-10-16): *"one slider that makes the
/// information small or larger"*, and Landscape or Portrait if he says.
/// Auto still works out every column's width; neither makes it Manual.
struct AutoAsk: Equatable {
    /// Text and pictures together, as a multiple of Auto's own sizes.
    var size: Double = 1.0
    /// `auto`, `landscape` or `portrait`.
    var paper: String = "auto"

    static let sizes: ClosedRange<Double> = 0.7...1.3
    static let papers = ["auto", "landscape", "portrait"]

    init(size: Double = 1.0, paper: String = "auto") {
        self.size = min(max(size.isFinite ? size : 1, AutoAsk.sizes.lowerBound), AutoAsk.sizes.upperBound)
        self.paper = AutoAsk.papers.contains(paper) ? paper : "auto"
    }

    /// The words `tablelayout` reads: nothing when it is Auto's own pick.
    var words: [String] {
        var out: [String] = []
        if abs(size - 1) > 0.001 { out.append(String(format: "size=%.2f", size)) }
        if paper != "auto" { out.append("paper=" + paper) }
        return out
    }
}

struct ExportPreset: Codable, Equatable, Identifiable {
    struct Dial: Codable, Equatable {
        var orientation: String
        var scale: Double
        var frames: String
    }

    var id: String
    var name: String
    var arrange: String = ExportArrange.table.rawValue
    /// `table` keeps the Table's filter; `none` exports without it.
    var filter: String = "table"
    /// What the Table's filter said when this was saved, so a film with no
    /// filter can say "Filter not used" rather than quietly print more.
    var filterWords: [String] = []
    var days: DaysRule? = nil
    var pages: [String] = ["table", "storyboard", "document"]
    /// Nil is the columns the Table is showing.
    var columns: [String]? = nil
    /// Every column the Table shows, but these.
    var columnsExcept: [String]? = nil
    var widths: [String: Double] = [:]
    /// The table laid out by Auto, or by the dials in `looks`.
    var auto: Bool = true
    /// Auto's Size, nil at 100% — so a preset saved before it reads the same.
    var autoSize: Double? = nil
    /// Auto's paper, nil when Auto picks it.
    var autoPaper: String? = nil
    var looks: [String: Dial] = [:]
    /// `one` or `perday`.
    var output: String = "one"
    /// `{project}-shot-list-next-day-{date}`; nil follows the settings.
    var pattern: String? = nil
    /// 0 PDF, 1 Flat PDF, 2 PNG.
    var fileKind: Int = 0
    var workbook: Bool = false

    init(id: String = "p-" + UUID().uuidString.prefix(8).lowercased(), name: String) {
        self.id = id
        self.name = name
    }

    private enum Key: String, CodingKey {
        case id, name, arrange, filter, filterWords, days, pages, columns, columnsExcept,
             widths, auto, autoSize, autoPaper, looks, output, pattern, fileKind, workbook
    }

    /// Auto's Size and paper as one ask.
    var autoAsk: AutoAsk {
        get { AutoAsk(size: autoSize ?? 1, paper: autoPaper ?? "auto") }
        set {
            autoSize = abs(newValue.size - 1) > 0.001 ? newValue.size : nil
            autoPaper = newValue.paper == "auto" ? nil : newValue.paper
        }
    }

    /// **Forgiving**: a preset written by a later Studio, missing a field or
    /// carrying one this does not know, still reads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        arrange = (try? c.decodeIfPresent(String.self, forKey: .arrange)) ?? "table"
        filter = (try? c.decodeIfPresent(String.self, forKey: .filter)) ?? "table"
        filterWords = (try? c.decodeIfPresent([String].self, forKey: .filterWords)) ?? []
        days = (try? c.decodeIfPresent(DaysRule.self, forKey: .days)) ?? nil
        pages = (try? c.decodeIfPresent([String].self, forKey: .pages)) ?? ["table"]
        columns = (try? c.decodeIfPresent([String].self, forKey: .columns)) ?? nil
        columnsExcept = (try? c.decodeIfPresent([String].self, forKey: .columnsExcept)) ?? nil
        widths = (try? c.decodeIfPresent([String: Double].self, forKey: .widths)) ?? [:]
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? true
        autoSize = (try? c.decodeIfPresent(Double.self, forKey: .autoSize)) ?? nil
        autoPaper = (try? c.decodeIfPresent(String.self, forKey: .autoPaper)) ?? nil
        looks = (try? c.decodeIfPresent([String: Dial].self, forKey: .looks)) ?? [:]
        output = (try? c.decodeIfPresent(String.self, forKey: .output)) ?? "one"
        pattern = (try? c.decodeIfPresent(String.self, forKey: .pattern)) ?? nil
        fileKind = (try? c.decodeIfPresent(Int.self, forKey: .fileKind)) ?? 0
        workbook = (try? c.decodeIfPresent(Bool.self, forKey: .workbook)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(arrange, forKey: .arrange)
        try c.encode(filter, forKey: .filter)
        try c.encode(filterWords, forKey: .filterWords)
        try c.encodeIfPresent(days, forKey: .days)
        try c.encode(pages, forKey: .pages)
        try c.encodeIfPresent(columns, forKey: .columns)
        try c.encodeIfPresent(columnsExcept, forKey: .columnsExcept)
        try c.encode(widths, forKey: .widths)
        try c.encode(auto, forKey: .auto)
        try c.encodeIfPresent(autoSize, forKey: .autoSize)
        try c.encodeIfPresent(autoPaper, forKey: .autoPaper)
        try c.encode(looks, forKey: .looks)
        try c.encode(output, forKey: .output)
        try c.encodeIfPresent(pattern, forKey: .pattern)
        try c.encode(fileKind, forKey: .fileKind)
        try c.encode(workbook, forKey: .workbook)
    }

    /// The same settings, whatever it is called — what "Edited" compares.
    func sameSettings(as other: ExportPreset) -> Bool {
        var a = self, b = other
        a.id = ""; b.id = ""; a.name = ""; b.name = ""; a.filterWords = []; b.filterWords = []
        return a == b
    }

    /// **The three he can delete**, shipped as starters (his approval,
    /// 2026-10-15).
    static let starters: [ExportPreset] = {
        var ac = ExportPreset(id: "p-ac-sheet", name: "AC Sheet: Day by Day")
        ac.arrange = "schedule"
        ac.filter = "none"
        ac.days = .all
        ac.pages = ["table"]
        ac.columns = ["image", "title", "description", "size", "movement", "camera", "lens", "support"]
        ac.output = "perday"
        ac.pattern = "{project}-ac-sheet-by-day-{date}"

        var client = ExportPreset(id: "p-client-script", name: "Client: Script Order")
        client.arrange = "script"
        client.filter = "none"
        client.pages = ["storyboard", "table"]
        client.columnsExcept = ["notes"]
        client.pattern = "{project}-shot-list-script-order-{date}"

        var tomorrow = ExportPreset(id: "p-tomorrow", name: "Tomorrow")
        tomorrow.arrange = "schedule"
        tomorrow.filter = "none"
        tomorrow.days = DaysRule(kind: "next", unscheduled: false)
        tomorrow.pages = ["table"]
        tomorrow.pattern = "{project}-shot-list-next-day-{date}"
        return [ac, client, tomorrow]
    }()
}

// MARK: - Kept, and in step across Macs

/// **His presets, the same on the laptop and the Studio Mac.** Kept on the
/// portal's server as one small studio file (`/console/studio/exportpresets`,
/// `hub/src/exportpresets.js`), with a copy on this Mac so the menu is there
/// offline. A change made offline is sent the next time the server answers.
/// Two Macs saving at once: the later one wins, after reading the other's.
@MainActor
final class ExportPresets: ObservableObject {
    static let shared = ExportPresets()

    @Published private(set) var list: [ExportPreset] = []
    private var version = 0
    /// Changed here and not yet taken by the server.
    private var owed = false
    private var reading = false

    private struct Saved: Codable {
        var v: Int
        var presets: [ExportPreset]
        var owed: Bool?
    }

    /// The copy on this Mac. **A checking run keeps its own**, so no check
    /// ever reads or writes his.
    nonisolated static var file: URL {
        if let set = ProcessInfo.processInfo.environment["SHOTLISTER_PRESETS"], !set.isEmpty {
            return URL(fileURLWithPath: set)
        }
        if checking {
            return FileManager.default.temporaryDirectory.appending(path: "shotlister-check-export-presets.json")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: platformFolder + "export-presets.json")
    }

    // Each app says these for itself (`ExportPresetsMac.swift`,
    // `phone/Sources/ExportPresetsPhone.swift`): whether this is a checking
    // run, how it reaches the server, what it is called, where its old
    // set-ups were kept.
    nonisolated static var checking: Bool { platformChecking }


    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            list = saved.presets
            version = saved.v
            owed = saved.owed ?? false
        } else {
            // **The first time**: the starters, and any set-up he saved in
            // the old Settings menu, carried across as a preset.
            list = ExportPreset.starters + Self.oldSetups()
            owed = !Self.oldSetups().isEmpty
        }
    }

    /// The old Settings menu's set-ups (look, pages, columns, widths, file
    /// kind), as presets. Days, order and name were never in them.
    private static func oldSetups() -> [ExportPreset] {
        let key = platformSetupsKey
        let store = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        let setups = store["setups"] as? [[String: Any]] ?? []
        return setups.compactMap { one in
            guard let name = one["name"] as? String, !name.isEmpty else { return nil }
            var p = ExportPreset(name: name)
            p.filter = "table"
            if let pages = one["included"] as? [String] { p.pages = pages }
            p.output = (one["delivery"] as? String) == "perDay" ? "perday" : "one"
            if p.output == "perday" { p.arrange = "schedule"; p.days = .all }
            p.workbook = one["alsoWorkbook"] as? Bool ?? false
            p.fileKind = (one["flat"] as? Bool ?? false) ? 1 : 0
            p.auto = one["tableAuto"] as? Bool ?? false
            if let columns = one["columns"] as? [String] { p.columns = columns }
            if let widths = one["widths"] as? [String: Double] { p.widths = widths }
            if let looks = one["looks"] as? [String: [String: Any]] {
                for (section, dial) in looks {
                    p.looks[section] = ExportPreset.Dial(
                        orientation: dial["orientation"] as? String ?? "landscape",
                        scale: dial["scale"] as? Double ?? 1,
                        frames: dial["frames"] as? String ?? "medium")
                }
            }
            return p
        }
    }

    private func keep() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Saved(v: version, presets: list, owed: owed)) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    func preset(_ id: String) -> ExportPreset? { list.first { $0.id == id } }
    func named(_ name: String) -> ExportPreset? { list.first { $0.name == name } }

    // ---- changes --------------------------------------------------------

    func replace(_ all: [ExportPreset]) {
        list = all
        owed = true
        keep()
        send()
    }

    /// Saved under a name; a name he already has is replaced, not doubled.
    @discardableResult
    func save(_ preset: ExportPreset) -> ExportPreset {
        var all = list
        var one = preset
        if let at = all.firstIndex(where: { $0.id == one.id || $0.name == one.name }) {
            one.id = all[at].id
            all[at] = one
        } else {
            all.append(one)
        }
        replace(all)
        return one
    }

    func rename(_ id: String, to name: String) {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, let at = list.firstIndex(where: { $0.id == id }) else { return }
        var all = list
        all[at].name = wanted
        replace(all)
    }

    func duplicate(_ id: String) {
        guard let at = list.firstIndex(where: { $0.id == id }) else { return }
        var copy = list[at]
        copy.id = "p-" + UUID().uuidString.prefix(8).lowercased()
        var name = copy.name + " Copy"
        var n = 2
        while list.contains(where: { $0.name == name }) { name = copy.name + " Copy \(n)"; n += 1 }
        copy.name = name
        var all = list
        all.insert(copy, at: at + 1)
        replace(all)
    }

    func delete(_ id: String) {
        replace(list.filter { $0.id != id })
    }

    func move(from: IndexSet, to: Int) {
        var all = list
        all.move(fromOffsets: from, toOffset: to)
        replace(all)
    }

    // ---- the server -----------------------------------------------------

    private struct Answer: Decodable {
        var v: Int?
        var presets: [ExportPreset]?
        var now: Now?
        struct Now: Decodable { var v: Int?; var presets: [ExportPreset]? }
    }

    private func request(_ method: String, body: Data? = nil) -> URLRequest? {
        guard !Self.checking, let (address, token) = Self.platformServer(),
              let url = URL(string: "\(address)/console/studio/exportpresets") else { return nil }
        var ask = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        ask.httpMethod = method
        ask.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            ask.httpBody = body
            ask.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return ask
    }

    /// **Read the server's copy.** Quiet: offline, or a server without the
    /// door yet, and the copy here stands.
    func refresh() {
        guard !reading, let ask = request("GET") else { return }
        reading = true
        Task { @MainActor in
            defer { reading = false }
            guard let (data, answer) = try? await URLSession.shared.data(for: ask),
                  (answer as? HTTPURLResponse)?.statusCode == 200,
                  let got = try? JSONDecoder().decode(Answer.self, from: data) else { return }
            let v = got.v ?? 0
            if owed {
                // Ours is newer than anything it has seen from here.
                version = v
                send()
            } else if let presets = got.presets, v != version {
                list = presets
                version = v
                keep()
            } else if got.presets == nil {
                // Never written there: this Mac's list becomes the first.
                owed = true
                send()
            }
        }
    }

    private func send(retry: Bool = true) {
        let body = try? JSONSerialization.data(withJSONObject: [
            "presets": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(list))) ?? [],
            "base": version,
            "by": Self.platformMachine,
        ])
        guard let body, let ask = request("PUT", body: body) else { return }
        Task { @MainActor in
            guard let (data, answer) = try? await URLSession.shared.data(for: ask),
                  let status = (answer as? HTTPURLResponse)?.statusCode else { return }
            let got = try? JSONDecoder().decode(Answer.self, from: data)
            if status == 200 {
                version = got?.v ?? version + 1
                owed = false
                keep()
            } else if status == 409, retry {
                // The other Mac wrote first. Ours was made after looking at
                // its menu, so ours goes on top of its version.
                version = got?.now?.v ?? version
                send(retry: false)
            }
        }
    }
}
