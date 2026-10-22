//! **The Export window's pages, asked for from anywhere** (2026-10-17). His
//! ask: an AI anywhere can export a project "the way Studio's Export tab
//! makes it" and have it land in the project's Google Drive, with no Mac on.
//!
//! The pages are the engine's own (`html::table`, `storyboard`, `document`,
//! `script`), laid out by the same Auto (`autolayout::solve`) and narrowed by
//! the same Order and Days rules the Mac's Export window sends to `ffi`'s
//! `print` (`Options::arranged`). What a server has no copy of is the Mac's
//! *live* Table — its search, facets and sort — so Order "As in Table" reads
//! as script order here, and the Table's filter is never applied.
//!
//! Two unlisted tools, used by the portal's `export` (`hub/src/exporting.js`),
//! which turns the pages into a PDF the way `studio/Sources/Printing.swift`
//! does and files it in Drive:
//!
//! - `export_pages` — every file's pages as HTML, pictures pointed at `base`;
//! - `export_sheet` — the spreadsheet (his working workbook) or a CSV, as
//!   base64.
//!
//! The days rules (Next Day, This Week, Shoot 2, Days 3–7…) are
//! `shared/ExportPresets.swift`'s `ExportDays`, said again here; **if one
//! changes the other has to.**

use shotlister_engine::doc::f;
use shotlister_engine::docstyle;
use shotlister_engine::export::autolayout;
use shotlister_engine::export::html::{self, ColumnWidths, FrameSize, Print};
use shotlister_engine::export::share;
use shotlister_engine::export::{csv, xlsx};
use shotlister_engine::query::{DayFilter, GroupBy};
use shotlister_engine::view;
use shotlister_engine::{Doc, Id, Query};

use super::Server;
use crate::films::Films;
use crate::json::Json;
use crate::tools;

/// Pages an export can carry here. The Diagram page wants the Film Set
/// Objects pack the worker build leaves out, and the Script page proper is
/// sliced out of the PDF he imported on the Mac.
pub const PAGES: &[&str] = &["table", "storyboard", "document", "avscript"];

const UNSCHEDULED: &str = "unscheduled";

impl<F: Films> Server<F> {
    pub(super) fn export_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        match name {
            "export_pages" => Some(self.films.doc().and_then(|doc| pages(doc, arguments)).map(|j| j.encode())),
            "export_sheet" => Some(self.films.doc().and_then(|doc| sheet_file(doc, arguments)).map(|j| j.encode())),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------- the days

/// One shoot day, as the Export window's Days picker knows it.
struct Day {
    id: Id,
    date: String,
    wrapped: bool,
    shoot: String,
}

struct Info {
    days: Vec<Day>,
    shoots: Vec<String>,
    unscheduled: usize,
}

fn info(doc: &Doc) -> Info {
    let days = doc
        .days_in_order()
        .into_iter()
        .map(|id| Day {
            id,
            date: doc.day_date(id),
            wrapped: doc.day_wrapped(id),
            shoot: doc.day_shoot(id).unwrap_or_default(),
        })
        .collect();
    let unscheduled = doc
        .all_placements()
        .into_iter()
        .filter(|p| doc.get(*p).map(|r| r.ref_id(f::DAY).is_none()).unwrap_or(false))
        .count();
    Info { days, shoots: doc.shoots().iter().map(|s| s.id.clone()).collect(), unscheduled }
}

/// Days since 1970-01-01 for a `YYYY-MM-DD` (its first ten characters).
fn day_number(text: &str) -> Option<i64> {
    let t = text.get(..10)?;
    let y: i64 = t.get(0..4)?.parse().ok()?;
    let m: i64 = t.get(5..7)?.parse().ok()?;
    let d: i64 = t.get(8..10)?.parse().ok()?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    // Howard Hinnant's days_from_civil.
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146097 + doe - 719468)
}

/// The Monday on or before a day (1970-01-01 was a Thursday).
fn monday(day: i64) -> i64 {
    day - (day + 3).rem_euclid(7)
}

/// The Days rule, read from a preset's `{kind, from, to, numbers, shoot,
/// unscheduled}` or from words: `all`, `next`, `this week`, `next week`,
/// `shoot 2`, `3-7`, `1,4,6`, `unscheduled`.
struct Rule {
    kind: String,
    from: Option<i64>,
    to: Option<i64>,
    numbers: Vec<i64>,
    shoot: Option<i64>,
    unscheduled: Option<bool>,
}

fn rule_of(said: Option<&Json>) -> Result<Rule, String> {
    let mut rule = Rule { kind: "all".into(), from: None, to: None, numbers: Vec::new(), shoot: None, unscheduled: None };
    let Some(said) = said else { return Ok(rule) };
    if let Json::Object(_) = said {
        rule.kind = said.str_field("kind");
        if rule.kind.is_empty() {
            rule.kind = "all".into();
        }
        rule.from = said.get("from").and_then(|v| v.as_f64()).map(|n| n as i64);
        rule.to = said.get("to").and_then(|v| v.as_f64()).map(|n| n as i64);
        rule.shoot = said.get("shoot").and_then(|v| v.as_f64()).map(|n| n as i64);
        rule.unscheduled = said.get("unscheduled").and_then(|v| v.as_bool());
        rule.numbers = said
            .get("numbers")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().filter_map(|n| n.as_f64()).map(|n| n as i64).collect())
            .unwrap_or_default();
        return Ok(rule);
    }
    let words = said.as_str().unwrap_or("").trim().to_lowercase();
    let words = words.trim_start_matches("days").trim_start_matches("day").trim();
    let (words, loose) = match words.strip_suffix("+ unscheduled") {
        Some(rest) => (rest.trim(), Some(true)),
        None => (words, None),
    };
    rule.unscheduled = loose;
    match words {
        "" | "all" | "all days" => {}
        "next" | "next day" | "tomorrow" => rule.kind = "next".into(),
        "this week" | "thisweek" => rule.kind = "thisweek".into(),
        "next week" | "nextweek" => rule.kind = "nextweek".into(),
        UNSCHEDULED => {
            rule.kind = "numbers".into();
            rule.unscheduled = Some(true);
        }
        other if other.starts_with("shoot") => {
            rule.kind = "shoot".into();
            rule.shoot = Some(other.trim_start_matches("shoot").trim().parse().map_err(|_| format!("Say which shoot: \"shoot 2\", not \"{other}\"."))?);
        }
        other => {
            let range = other.replace('\u{2013}', "-").replace(" to ", "-");
            if let Some((a, b)) = range.split_once('-').filter(|_| !range.contains(',')) {
                rule.kind = "range".into();
                rule.from = a.trim().parse().ok();
                rule.to = b.trim().parse().ok();
                if rule.from.is_none() || rule.to.is_none() {
                    return Err(format!("I could not read the days \"{other}\"."));
                }
            } else {
                rule.kind = "numbers".into();
                for n in range.split(|c: char| c == ',' || c.is_whitespace()).filter(|s| !s.is_empty()) {
                    rule.numbers.push(n.parse().map_err(|_| format!("I could not read the days \"{other}\". Say all, next, this week, next week, shoot 2, 3-7 or 1,4,6."))?);
                }
            }
        }
    }
    Ok(rule)
}

/// `ExportDays.pick`: the day ids a rule names, and whether the unscheduled
/// come too. `today` is days since 1970.
fn pick(rule: &Rule, info: &Info, today: i64) -> (Vec<Id>, bool) {
    let days = &info.days;
    let numbered = |keep: &dyn Fn(usize, &Day) -> bool| -> Vec<Id> {
        days.iter().enumerate().filter(|(at, d)| keep(*at, d)).map(|(_, d)| d.id).collect()
    };
    let out = match rule.kind.as_str() {
        "next" => {
            let open: Vec<&Day> = days.iter().filter(|d| !d.wrapped).collect();
            if let Some(dated) = open.iter().find(|d| day_number(&d.date).map(|n| n >= today).unwrap_or(false)) {
                vec![dated.id]
            } else if open.iter().all(|d| day_number(&d.date).is_none()) {
                open.first().map(|d| vec![d.id]).unwrap_or_default()
            } else {
                Vec::new()
            }
        }
        "thisweek" | "nextweek" => {
            let week = monday(today) + if rule.kind == "nextweek" { 7 } else { 0 };
            numbered(&|_, d| day_number(&d.date).map(|n| monday(n) == week).unwrap_or(false))
        }
        "shoot" => {
            let wanted = rule.shoot.unwrap_or(1) - 1;
            match usize::try_from(wanted).ok().and_then(|w| info.shoots.get(w)) {
                Some(shoot) => numbered(&|_, d| &d.shoot == shoot),
                None => Vec::new(),
            }
        }
        "range" => {
            let (from, to) = (rule.from.unwrap_or(1), rule.to.unwrap_or(days.len() as i64));
            let (lo, hi) = (from.min(to), from.max(to));
            numbered(&|at, _| (at as i64 + 1) >= lo && (at as i64 + 1) <= hi)
        }
        "numbers" => numbered(&|at, _| rule.numbers.contains(&(at as i64 + 1))),
        _ => days.iter().map(|d| d.id).collect(),
    };
    let loose = rule.unscheduled.unwrap_or(rule.kind == "all") && info.unscheduled > 0;
    (out, loose)
}

fn numbers_of(picked: &[Id], info: &Info) -> Vec<usize> {
    info.days.iter().enumerate().filter(|(_, d)| picked.contains(&d.id)).map(|(at, _)| at + 1).collect()
}

fn runs(numbers: &[usize]) -> Vec<(usize, usize)> {
    let mut out: Vec<(usize, usize)> = Vec::new();
    for &n in numbers {
        match out.last_mut() {
            Some(last) if last.1 + 1 == n => last.1 = n,
            _ => out.push((n, n)),
        }
    }
    out
}

/// `ExportDays.summary`: "Days 12–18, 22 (8 days)", "All 30 days + Unscheduled".
fn summary(picked: &[Id], loose: bool, info: &Info) -> String {
    let numbers = numbers_of(picked, info);
    if numbers.is_empty() {
        return if loose { "Unscheduled only".into() } else { "No days".into() };
    }
    let mut said = if numbers.len() == info.days.len() {
        format!("All {} day{}", numbers.len(), if numbers.len() == 1 { "" } else { "s" })
    } else {
        let parts: Vec<String> = runs(&numbers)
            .into_iter()
            .map(|(a, b)| if a == b { a.to_string() } else { format!("{a}\u{2013}{b}") })
            .collect();
        let mut s = format!("{}{}", if numbers.len() == 1 { "Day " } else { "Days " }, parts.join(", "));
        if numbers.len() > 1 {
            s += &format!(" ({} days)", numbers.len());
        }
        s
    };
    if loose {
        said += " + Unscheduled";
    }
    said
}

/// `ExportDays.nameWords`: `day-3`, `days-12-18-22`.
fn name_words(picked: &[Id], loose: bool, info: &Info) -> String {
    let numbers = numbers_of(picked, info);
    if numbers.is_empty() {
        return if loose { UNSCHEDULED.into() } else { String::new() };
    }
    if numbers.len() == 1 {
        return format!("day-{}", numbers[0]);
    }
    let parts: Vec<String> = runs(&numbers)
        .into_iter()
        .flat_map(|(a, b)| if a == b { vec![a.to_string()] } else { vec![a.to_string(), b.to_string()] })
        .collect();
    format!("days-{}", parts.join("-"))
}

/// `FileNames.documentWords`: `table` → `shot-list`; two pages name both,
/// three or more take the lead page's name.
fn document_words(pages: &[String]) -> String {
    let mut words: Vec<&str> = Vec::new();
    for page in pages {
        let word = match page.as_str() {
            "table" | "workbook" => "shot-list",
            "storyboard" => "storyboard",
            "document" => "document",
            "script" | "avscript" => "script",
            "diagram" => "diagram",
            _ => continue,
        };
        if !words.contains(&word) {
            words.push(word);
        }
    }
    if words.is_empty() {
        return "shot-list".into();
    }
    if words.len() > 2 {
        return if words.contains(&"shot-list") { "shot-list".into() } else { "full-set".into() };
    }
    words.join("-")
}

// ---------------------------------------------------------------- the pages

/// One view's dial (`Printing.Look`): which way round, how big the text, how
/// big the pictures. What a view gets when nothing is said: its own paper,
/// 100%, medium pictures.
struct Look {
    landscape: bool,
    scale: f64,
    frames: FrameSize,
}

fn standard_look(section: &str) -> Look {
    Look { landscape: !(section == "document" || section == "avscript"), scale: 1.0, frames: FrameSize::Medium }
}

fn look_of(looks: Option<&Json>, section: &str) -> Look {
    let mut look = standard_look(section);
    if let Some(said) = looks.and_then(|l| l.get(section)) {
        match said.str_field("orientation").as_str() {
            "portrait" => look.landscape = false,
            "landscape" => look.landscape = true,
            _ => {}
        }
        if let Some(scale) = said.get("scale").and_then(|v| v.as_f64()).filter(|s| *s > 0.1 && *s < 4.0) {
            look.scale = scale;
        }
        let frames = said.str_field("frames");
        if !frames.is_empty() {
            look.frames = FrameSize::read(&frames);
        }
    }
    // **The document page is never scaled from the exporter** (`Printing.Job`).
    if section == "document" || section == "avscript" {
        look.scale = 1.0;
    }
    look
}

fn strings(said: Option<&Json>) -> Option<Vec<String>> {
    let list = said?.as_array()?;
    Some(list.iter().filter_map(|v| v.as_str()).map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
}

/// What the files are about: the Order, the scenes, one day or a set of days.
#[derive(Clone)]
enum Narrow {
    /// The whole project (or the scenes given) in script order.
    Script(Vec<Id>),
    /// Shooting order, day by day — these days, and the unscheduled or not;
    /// `None` is every day.
    Schedule(Vec<Id>, Option<(Vec<Id>, bool)>),
    /// One day's file of a File per Day export.
    OneDay(Option<Id>),
}

/// `Options::arranged`, without the Table: nothing on screen is kept.
fn query_of(narrow: &Narrow) -> Query {
    let mut asked = view::Asked::default();
    asked.sort = None;
    asked.group_by = GroupBy::Scene;
    let mut q = asked.query();
    match narrow {
        Narrow::Script(scenes) => {
            if !scenes.is_empty() {
                q = q.for_scenes(scenes.clone());
            }
            q.group_by = GroupBy::Scene;
        }
        Narrow::Schedule(scenes, days) => {
            if !scenes.is_empty() {
                q = q.for_scenes(scenes.clone());
            }
            q.group_by = GroupBy::Day;
            if let Some(days) = days {
                q.days = Some(days.clone());
                q.day = DayFilter::Any;
            }
        }
        Narrow::OneDay(day) => {
            q.day = match day {
                Some(id) => DayFilter::On(*id),
                None => DayFilter::Unscheduled,
            };
            q.group_by = GroupBy::Day;
        }
    }
    q
}

/// A picture as the portal serves it: `<base>/<hash's first 32>.<ext>`, a
/// clip by its poster — `picture_at` in `web/src/lib.rs`, and the shape the
/// film's record keeps for it, so the page can crop it as the Mac does.
fn frame_at(doc: &Doc, media: Id, base: &str) -> Option<html::Frame> {
    let record = doc.get(media)?;
    let hash = record.text(f::HASH).unwrap_or("");
    if hash.is_empty() {
        return None;
    }
    let moving = doc.media_kind(media).map(|k| k.is_moving()).unwrap_or(false);
    let ext = if moving {
        "jpg".to_string()
    } else {
        record.text(f::FILENAME).unwrap_or("").rsplit('.').next().unwrap_or("png").to_lowercase()
    };
    let ext: String = ext.chars().filter(|c| c.is_ascii_alphanumeric()).take(8).collect();
    let short: String = hash.chars().take(32).collect();
    let width = record.get(f::WIDTH).and_then(|v| v.as_int()).unwrap_or(0) as f64;
    let height = record.get(f::HEIGHT).and_then(|v| v.as_int()).unwrap_or(0) as f64;
    Some(html::Frame {
        src: format!("{}/{}.{}", base.trim_end_matches('/'), short, if ext.is_empty() { "png" } else { &ext }),
        width,
        height,
        moments: 1,
    })
}

fn style_of(doc: &Doc) -> docstyle::Style {
    match doc.project_id() {
        Some(project) => docstyle::of(doc, project),
        None => docstyle::Style::standard_style(),
    }
}

/// Everything that decides one file, the same for each of its pages.
struct Ask<'a> {
    pages: Vec<String>,
    columns: Option<Vec<String>>,
    except: Vec<String>,
    auto: bool,
    size: f64,
    paper: Option<bool>,
    looks: Option<&'a Json>,
    widths: String,
    caption: String,
    day_pages: bool,
    base: String,
}

fn columns_for(doc: &Doc, q: &Query, ask: &Ask) -> Option<Vec<String>> {
    if let Some(columns) = &ask.columns {
        return Some(columns.clone());
    }
    if ask.except.is_empty() {
        return None;
    }
    Some(doc.sheet(q).columns.into_iter().filter(|c| !ask.except.contains(c)).collect())
}

/// One file's pages: `[{section, orientation, html}]`, and Auto's plan for
/// its table when it had one.
fn file_pages(doc: &Doc, narrow: &Narrow, ask: &Ask) -> Json {
    let q = query_of(narrow);
    let columns = columns_for(doc, &q, ask);
    let style = style_of(doc);
    let frames = |media: Id, _trim: html::Trim| frame_at(doc, media, &ask.base);
    let mut plan_said = Json::Null;
    let mut jobs = Vec::new();
    for section in &ask.pages {
        let mut sheet = doc.sheet(&q);
        if let Some(columns) = &columns {
            sheet.columns = columns.clone();
        }
        let mut look = look_of(ask.looks, section);
        let mut widths = ColumnWidths::read(&ask.widths);
        if section == "table" && ask.auto {
            // `tablelayout` exactly: the sheet before its day pages are set.
            let problem = autolayout::Problem::asked(&sheet, autolayout::Ask::new(ask.size, ask.paper));
            let plan = autolayout::solve(&problem);
            look = Look { landscape: plan.candidate.landscape, scale: plan.candidate.scale, frames: plan.frames() };
            let mut shares: Vec<(String, f64)> = plan.shares.clone();
            shares.sort_by(|a, b| a.0.cmp(&b.0));
            let said: Vec<String> = shares.iter().map(|(k, v)| format!("{k}:{v:.4}")).collect();
            widths = ColumnWidths::exact(&said.join(","));
            widths.fitted = plan.cut_words == 0;
            plan_said = Json::object(vec![
                ("orientation", Json::text(if plan.candidate.landscape { "landscape" } else { "portrait" })),
                ("scale", Json::Number(plan.candidate.scale)),
                ("frames", Json::text(plan.frames().name())),
                ("pages", Json::Number(plan.pages as f64)),
            ]);
        }
        sheet.day_pages = ask.day_pages;
        let base = ask.base.trim_end_matches('/').to_string();
        sheet.fill_print_frames(|hash, ext| {
            let short: String = hash.chars().take(32).collect();
            if short.is_empty() {
                return None;
            }
            Some((format!("{base}/{short}.{ext}"), 0.0, 0.0))
        });
        let page = match section.as_str() {
            "table" => html::table(&sheet, &frames, Print::Table, look.scale, look.frames, &widths),
            "storyboard" => html::storyboard(&sheet, &frames, Print::Storyboard, look.scale, look.frames),
            "avscript" => html::script(&sheet, &frames, Print::Script, look.scale, &style),
            _ => html::document(&sheet, &frames, Print::Document, look.scale, &ask.caption, &style),
        };
        let rows: usize = sheet.groups.iter().map(|g| g.rows.len()).sum();
        jobs.push(Json::object(vec![
            ("section", Json::text(section.clone())),
            ("orientation", Json::text(if look.landscape { "landscape" } else { "portrait" })),
            ("shots", Json::Number(rows as f64)),
            ("html", Json::text(page)),
        ]));
    }
    Json::object(vec![("jobs", Json::Array(jobs)), ("auto", plan_said)])
}

fn scenes_of(doc: &Doc, arguments: &Json) -> Result<Vec<Id>, String> {
    let mut out = Vec::new();
    for said in strings(arguments.get("scenes")).unwrap_or_default() {
        out.push(tools::find_scene(doc, &said).ok_or_else(|| format!("There is no scene {said} in this project."))?);
    }
    Ok(out)
}

fn pages(doc: &Doc, arguments: &Json) -> Result<Json, String> {
    let pages = strings(arguments.get("pages")).unwrap_or_else(|| vec!["table".into()]);
    let pages: Vec<String> = pages.into_iter().map(|p| match p.to_lowercase().as_str() {
        "shot list" | "shot-list" | "table" | "list" => "table".to_string(),
        "script" | "av script" | "avscript" => "avscript".to_string(),
        other => other.to_string(),
    }).collect();
    if pages.is_empty() {
        return Err("Say which pages: table, storyboard, document or avscript.".into());
    }
    if let Some(bad) = pages.iter().find(|p| !PAGES.contains(&p.as_str())) {
        return Err(format!("{bad} is not a page this can export. Pages: table, storyboard, document, avscript (the Diagram page exports from Studio on the Mac)."));
    }
    let arrange = match arguments.str_field("arrange").to_lowercase().as_str() {
        "schedule" | "shooting" | "shooting order" | "schedule order" => "schedule",
        _ => "script",
    };
    let scenes = scenes_of(doc, arguments)?;
    let whole = scenes.is_empty();
    let perday = arguments.str_field("output") == "perday";
    let info = info(doc);
    let today = day_number(&arguments.str_field("today")).unwrap_or(0);
    let rule = rule_of(arguments.get("days"))?;
    let (mut picked, loose) = pick(&rule, &info, today);
    // Days in the project's own order.
    picked.sort_by_key(|id| info.days.iter().position(|d| d.id == *id).unwrap_or(usize::MAX));
    let every = picked.len() == info.days.len() && (loose || info.unscheduled == 0);
    if (arrange == "schedule" || perday) && picked.is_empty() && !loose {
        let days: Vec<String> = info
            .days
            .iter()
            .enumerate()
            .map(|(at, d)| {
                let date = d.date.get(..10).unwrap_or("");
                let wrapped = if d.wrapped { ", wrapped" } else { "" };
                if date.is_empty() { format!("Day {}{wrapped}", at + 1) } else { format!("Day {} ({date}{wrapped})", at + 1) }
            })
            .collect();
        return Err(if days.is_empty() {
            "This project has no shoot days yet.".to_string()
        } else {
            format!("No shoot day matches that. This project's days: {}.", days.join(", "))
        });
    }

    let size = arguments.get("size").and_then(|v| v.as_f64()).filter(|s| *s > 0.3 && *s < 3.0).unwrap_or(1.0);
    let paper = match arguments.str_field("paper").as_str() {
        "landscape" => Some(true),
        "portrait" => Some(false),
        _ => None,
    };
    let widths = arguments
        .get("widths")
        .map(|w| match w {
            Json::Object(pairs) => pairs
                .iter()
                .filter_map(|(k, v)| v.as_f64().map(|n| format!("{k}:{n:.3}")))
                .collect::<Vec<_>>()
                .join(","),
            _ => String::new(),
        })
        .unwrap_or_default();

    // `ExportChoice.caption`, with no Table to read a sort or filter from.
    let mut caption = if arrange == "schedule" { "SHOOTING ORDER".to_string() } else { "SCRIPT ORDER".to_string() };
    let days_said = summary(&picked, loose, &info);
    if arrange == "schedule" && whole && !every {
        caption += &format!(" \u{b7} {}", days_said.to_uppercase());
    }
    let order_words = if arrange == "schedule" {
        if !whole || every { "schedule-order".to_string() } else { name_words(&picked, loose, &info) }
    } else {
        "script-order".to_string()
    };
    let mut ask = Ask {
        pages: pages.clone(),
        columns: strings(arguments.get("columns")),
        except: strings(arguments.get("columns_except")).unwrap_or_default(),
        auto: arguments.get("auto").and_then(|v| v.as_bool()).unwrap_or(true),
        size,
        paper,
        looks: arguments.get("looks"),
        widths,
        caption: caption.clone(),
        day_pages: arrange == "schedule",
        base: arguments.str_field("base"),
    };

    let mut files = Vec::new();
    if perday {
        if !whole {
            return Err("File per Day exports the whole project; leave out `scenes`.".into());
        }
        if info.days.is_empty() {
            return Err("This project has no shoot days to export by day.".into());
        }
        // **One file a day** (`Exporting.exportEachDay`): each in that day's
        // own running order, the unscheduled last.
        ask.day_pages = false;
        let mut wanted: Vec<(Option<Id>, String)> = info
            .days
            .iter()
            .enumerate()
            .filter(|(_, d)| picked.contains(&d.id))
            .map(|(at, d)| (Some(d.id), format!("day-{}", at + 1)))
            .collect();
        if loose {
            wanted.push((None, UNSCHEDULED.into()));
        }
        if wanted.is_empty() {
            return Err("No days picked.".into());
        }
        for (day, words) in wanted {
            let label = day.and_then(|d| doc.day_label(d)).unwrap_or_else(|| "Unscheduled".into());
            let mut said = match file_pages(doc, &Narrow::OneDay(day), &ask) {
                Json::Object(pairs) => pairs,
                _ => Vec::new(),
            };
            said.push(("order".into(), Json::text(words)));
            said.push(("day".into(), Json::text(label)));
            files.push(Json::Object(said));
        }
    } else {
        let narrow = if arrange == "schedule" {
            let days = if whole && !every { Some((picked.clone(), loose)) } else { None };
            Narrow::Schedule(scenes.clone(), days)
        } else {
            Narrow::Script(scenes.clone())
        };
        let mut said = match file_pages(doc, &narrow, &ask) {
            Json::Object(pairs) => pairs,
            _ => Vec::new(),
        };
        said.push(("order".into(), Json::text(order_words.clone())));
        files.push(Json::Object(said));
    }
    let scene_words = scene_words(doc, &scenes);
    Ok(Json::object(vec![
        ("document", Json::text(document_words(&pages))),
        ("order", Json::text(order_words)),
        ("scope", Json::text(scene_words)),
        ("caption", Json::text(caption)),
        ("days", Json::text(if arrange == "schedule" || perday { days_said } else { String::new() })),
        ("perday", Json::Bool(perday)),
        ("files", Json::Array(files)),
    ]))
}

/// `FileNames.sceneWords`: `sc-12`, `sc-04-07-12`, `sc-04-to-31`.
fn scene_words(doc: &Doc, scenes: &[Id]) -> String {
    let numbers: Vec<String> = scenes
        .iter()
        .filter_map(|s| doc.get(*s).and_then(|r| r.text(f::NUMBER)).map(|n| n.to_lowercase()))
        .collect();
    match numbers.len() {
        0 => String::new(),
        1..=3 => format!("sc-{}", numbers.join("-")),
        _ => format!("sc-{}-to-{}", numbers[0], numbers[numbers.len() - 1]),
    }
}

/// The workbook (`ffi`'s `xlsx`: Master Shot List, Group by Day, Group by
/// Sequence, Ranges) or a CSV, as base64. No pictures: a server holds them as
/// addresses, and a workbook wants their bytes.
fn sheet_file(doc: &Doc, arguments: &Json) -> Result<Json, String> {
    let format = arguments.str_field("format").to_lowercase();
    let scenes = scenes_of(doc, arguments)?;
    let arrange = arguments.str_field("arrange").to_lowercase();
    let narrow = if arrange == "schedule" { Narrow::Schedule(scenes, None) } else { Narrow::Script(scenes) };
    let mut q = query_of(&narrow);
    let ask_columns = strings(arguments.get("columns"));
    let except = strings(arguments.get("columns_except")).unwrap_or_default();
    let columns = match ask_columns {
        Some(c) => Some(c),
        None if !except.is_empty() => Some(doc.sheet(&q).columns.into_iter().filter(|c| !except.contains(c)).collect()),
        None => None,
    };
    let bytes = match format.as_str() {
        "csv" => {
            let mut sheet = doc.sheet(&q);
            if let Some(columns) = columns {
                sheet.columns = columns;
            }
            csv::write(&sheet).into_bytes()
        }
        "xlsx" | "excel" | "spreadsheet" | "workbook" => {
            q.group_by = GroupBy::Flat;
            let mut master = doc.sheet(&q);
            q.group_by = GroupBy::Day;
            let mut by_day = doc.sheet(&q);
            q.group_by = GroupBy::Sequence;
            let mut by_sequence = doc.sheet(&q);
            if let Some(columns) = columns {
                master.columns = columns.clone();
                by_day.columns = columns.clone();
                by_sequence.columns = columns;
            }
            xlsx::workbook(&master, &by_day, &by_sequence, &|name| doc.vocabulary(name), &xlsx::no_frames)
        }
        other => return Err(format!("{other} is not a spreadsheet format here: csv or xlsx.")),
    };
    Ok(Json::object(vec![
        ("ext", Json::text(if format == "csv" { "csv" } else { "xlsx" })),
        ("document", Json::text("shot-list")),
        ("order", Json::text(if arrange == "schedule" { "schedule-order" } else { "script-order" })),
        ("base64", Json::text(share::base64(&bytes))),
    ]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn days_since_1970() {
        assert_eq!(day_number("1970-01-01"), Some(0));
        assert_eq!(day_number("2026-10-17T00:00"), Some(20743));
        // 2026-10-17 is a Saturday; its Monday is the 12th.
        assert_eq!(monday(20743), day_number("2026-10-12").unwrap());
        assert_eq!(monday(day_number("2026-10-12").unwrap()), day_number("2026-10-12").unwrap());
        assert_eq!(day_number("not a date"), None);
    }

    #[test]
    fn rules_read_from_words() {
        let r = rule_of(Some(&Json::text("3-7"))).unwrap();
        assert_eq!((r.kind.as_str(), r.from, r.to), ("range", Some(3), Some(7)));
        let r = rule_of(Some(&Json::text("Days 1, 4, 6"))).unwrap();
        assert_eq!((r.kind.as_str(), r.numbers.clone()), ("numbers", vec![1, 4, 6]));
        let r = rule_of(Some(&Json::text("shoot 2"))).unwrap();
        assert_eq!((r.kind.as_str(), r.shoot), ("shoot", Some(2)));
        assert_eq!(rule_of(Some(&Json::text("next day"))).unwrap().kind, "next");
        assert_eq!(rule_of(Some(&Json::text("This Week"))).unwrap().kind, "thisweek");
        assert!(rule_of(Some(&Json::text("fortnight"))).is_err());
    }

    #[test]
    fn names_say_the_pages_and_days() {
        assert_eq!(document_words(&["table".into()]), "shot-list");
        assert_eq!(document_words(&["table".into(), "storyboard".into()]), "shot-list-storyboard");
        assert_eq!(document_words(&["table".into(), "storyboard".into(), "document".into()]), "shot-list");
        assert_eq!(runs(&[12, 13, 14, 22]), vec![(12, 14), (22, 22)]);
    }
}
