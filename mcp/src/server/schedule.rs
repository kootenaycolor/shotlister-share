//! The schedule: shoot days, and what is shot on each.
//!
//! His rule, 2026-09-30: anything he can do in the app, Claude can do here.
//! Until then the connector could only *read* which day a shot was on — no day
//! could be made, named, dated, moved or taken away, and nothing could be put
//! on one. Every verb here is one the Schedule mode already has, calling the
//! same engine function its drag or menu calls.

use shotlister_engine::{f, Doc, Id, Value};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "schedule",
        description: "The shoot schedule: every day in order — `Day 1`, its date and name if it has them — with the scenes shot that day in running order, each with its shots there, and `run`, the day's shots in the order they are shot. Then `waiting`: scenes with shots on no day yet. A scene split across days says where else it is. `shoot` (its name, or 2 for Shoot 2) narrows it to one shoot when the project shoots more than once; with one shoot it is ignored.",
        arguments: &[("shoot", "string", false)],
    },
    Tool {
        name: "add_day",
        description: "Add a shoot day at the end of the schedule, or at `position` (1 is first). `date` is YYYY-MM-DD; `name` is what the day is for (\"Pickups\", \"Second unit\") and sits beside its number, never replacing it. Days are numbered by place, so adding one ahead renumbers those after. Dating matters: from the first shoot date on, shot letters stop moving.",
        arguments: &[("date", "string", false), ("name", "string", false), ("position", "number", false)],
    },
    Tool {
        name: "update_day",
        description: "Change a shoot day, named as `Day 3`, `3`, its date or its name. `date` (YYYY-MM-DD) and `name` take \"\" to clear. `position` moves it (1 is first) — the days renumber by place.",
        arguments: &[
            ("day", "string", true),
            ("date", "string", false),
            ("name", "string", false),
            ("position", "number", false),
        ],
    },
    Tool {
        name: "delete_day",
        description: "Take a shoot day away. Its shots keep everything and go back to waiting; the days after it move up a number. A day with shots on it is refused, saying how many, unless `even_with_shots` is true — ask him first.",
        arguments: &[("day", "string", true), ("even_with_shots", "boolean", false)],
    },
    Tool {
        name: "order_days",
        description: "Put the shoot days in order: `days`, the days in the order wanted (any left out follow in their order), or `sort`=date — dated days into date order, an undated day keeping its place. Days are numbered by place, so they renumber.",
        arguments: &[("days", "array", false), ("sort", "string", false)],
    },
    Tool {
        name: "schedule_scene",
        description: "Put scenes on a shoot day, as dragging them from the Schedule's scene list does — ahead of the scene `before` on that day, or last; several go in the order given. A scene partly scheduled already (`schedule`'s `waiting` shows what is left) brings only its shots still on no day (the Mac's Schedule Remaining), and the ones already on a day stay there; a scene with nothing left comes whole. `day`=\"\" takes them off every day. `from` names a day a split scene is already on, to move only that part. Moving a scene within its day is the same call. A scene with no shots cannot go on a day. One undo step.",
        arguments: &[
            ("scenes", "array", true),
            ("day", "string", true),
            ("before", "string", false),
            ("from", "string", false),
        ],
    },
    Tool {
        name: "schedule_shot",
        description: "Put single shots on a shoot day — splitting a scene across days, as dragging shots out of a scene opened in the Schedule's list does. A shot whose scene already has a strip on that day joins it; the rest stand together ahead of scene `before`'s strip, or last. `position` (1 is first) places them in the day's running order instead. `day`=\"\" takes shots off their day. One undo step.",
        arguments: &[
            ("shots", "array", true),
            ("day", "string", true),
            ("before", "string", false),
            ("position", "number", false),
        ],
    },
    Tool {
        name: "order_day",
        description: "Set a shoot day's shooting order in one go, as the Mac Schedule's Shooting Order drag does: `shots` in the order they will be shot, from the top of the day. Shots on another day or none come onto this one; the day's other shots follow in their present order. One undo. Moving one shot to a place is schedule_shot with `position`.",
        arguments: &[("day", "string", true), ("shots", "array", true)],
    },
    Tool {
        name: "move_to_shoot",
        description: "Put scenes into one of the project's shoots, as Move to Shoot… on a scene's menu does (Mac and iPhone): `scenes` (numbers) and `shoot` (its name, its number — 2 for Shoot 2 — or its id). A moved scene's shots sitting on another shoot's day go back to waiting; ones already on a day of this shoot keep it. Needs the project's shoots on its record (from his Notion Shoots rows). One undo step.",
        arguments: &[("scenes", "array", true), ("shoot", "string", true)],
    },
    Tool {
        name: "new_shoot",
        description: "Set up another shoot on this project in one step, as Projects Console's New Shoot does: save a version, add the shoot's section, add a dated day named after the shoot, and put pickup scenes on it. With `shoot` (the project's Shoots row id) the day belongs to that shoot and follows its dates, and no section is added: sections are his own. `date` (YYYY-MM-DD) and `name` (\"Shoot 3\") are needed. `section` defaults to `Shoot 3 · November 3`; a section whose title differs only in case, spaces, or a dash or dot between words is the same section and is used, never doubled. A day with that date and name already there is used too. `pickups` are scenes: their shots not marked Shot move onto the new day, and shots marked Shot stay on the day they were got. `version` defaults to `Before Shoot 3 setup`, saved only when something changes. `preview`=true says what it would do and changes nothing. Anything it cannot do refuses the whole step, saying why, and nothing changes. The answer is JSON: `steps` in plain words, then `section`, `day`, `pickups` and `version`.",
        arguments: &[
            ("date", "string", true),
            ("name", "string", true),
            ("section", "string", false),
            ("pickups", "array", false),
            ("version", "string", false),
            ("preview", "boolean", false),
            ("shoot", "string", false),
        ],
    },
];

/// A day the way he says it: `Day 3`, `3`, `2026-10-03`, `Pickups`, or an id.
pub(super) fn find_day(doc: &Doc, said: &str) -> Result<Id, String> {
    let said = said.trim();
    if let Some(id) = Id::from_hex(said) {
        if doc.get(id).is_some() {
            return Ok(id);
        }
    }
    let days = doc.days_in_order();
    let number = said
        .to_ascii_lowercase()
        .trim_start_matches("day")
        .trim()
        .parse::<usize>()
        .ok();
    if let Some(n) = number {
        if n >= 1 && n <= days.len() {
            return Ok(days[n - 1]);
        }
    }
    let field = |day: Id, name: &str| doc.get(day).and_then(|r| r.text(name)).unwrap_or_default().to_string();
    if let Some(day) = days.iter().find(|d| !said.is_empty() && field(**d, f::DATE) == said) {
        return Ok(*day);
    }
    if let Some(day) = days.iter().find(|d| !said.is_empty() && field(**d, f::TITLE).eq_ignore_ascii_case(said)) {
        return Ok(*day);
    }
    Err(if days.is_empty() {
        "This project has no shoot days yet — add_day makes one.".to_string()
    } else {
        format!(
            "There is no shoot day {said}. The days are {}.",
            days.iter().map(|d| day_named(doc, *d)).collect::<Vec<_>>().join("; ")
        )
    })
}

/// `Day 2 (2026-10-03, Pickups)`.
pub(super) fn day_named(doc: &Doc, day: Id) -> String {
    let label = doc.day_label(day).unwrap_or_default();
    let extra: Vec<String> = [f::DATE, f::TITLE]
        .iter()
        .filter_map(|name| doc.get(day).and_then(|r| r.text(name)).filter(|t| !t.is_empty()).map(str::to_string))
        .collect();
    if extra.is_empty() {
        label
    } else {
        format!("{label} ({})", extra.join(", "))
    }
}

fn number_of_scene(doc: &Doc, scene: Id) -> String {
    doc.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or_default().to_string()
}

fn scene_of(doc: &Doc, placement: Id) -> Option<Id> {
    doc.get(placement).and_then(|r| r.ref_id(f::SCENE))
}

/// Scenes in the order a list of placements runs them, each with its own
/// placements from the list.
fn strips(doc: &Doc, placements: &[Id]) -> Vec<(Id, Vec<Id>)> {
    let mut out: Vec<(Id, Vec<Id>)> = Vec::new();
    for placement in placements {
        let Some(scene) = scene_of(doc, *placement) else { continue };
        match out.iter_mut().find(|(s, _)| *s == scene) {
            Some((_, held)) => held.push(*placement),
            None => out.push((scene, vec![*placement])),
        }
    }
    out
}

fn numbers(doc: &Doc, placements: &[Id]) -> Json {
    Json::Array(
        placements
            .iter()
            .map(|p| Json::text(doc.display_number(*p).unwrap_or_default()))
            .collect(),
    )
}

fn strip_json(doc: &Doc, scene: Id, placements: &[Id], besides: Option<Id>) -> Json {
    let elsewhere: Vec<Json> = doc
        .days_of_scene(scene)
        .into_iter()
        .filter(|d| Some(*d) != besides)
        .filter_map(|d| doc.day_label(d))
        .map(Json::text)
        .collect();
    let mut pairs = vec![
        ("scene", Json::text(number_of_scene(doc, scene))),
        ("heading", Json::text(doc.scene_heading(scene).unwrap_or_default())),
        ("shots", numbers(doc, placements)),
    ];
    if !elsewhere.is_empty() {
        pairs.push(("also_on", Json::Array(elsewhere)));
    }
    Json::object(pairs)
}

pub(super) fn schedule(doc: &Doc, pick: Option<&super::shootpick::ShootPick>) -> Json {
    let text = |id: Id, name: &str| doc.get(id).and_then(|r| r.text(name)).unwrap_or_default().to_string();
    let days: Vec<Json> = doc
        .days_in_order()
        .into_iter()
        .filter(|day| pick.map(|p| p.days.contains(day)).unwrap_or(true))
        .map(|day| {
            let run = doc.placements_on_day(day);
            Json::object(vec![
                ("day", Json::text(doc.day_label(day).unwrap_or_default())),
                ("date", Json::text(text(day, f::DATE))),
                ("name", Json::text(text(day, f::TITLE))),
                (
                    "scenes",
                    Json::Array(strips(doc, &run).iter().map(|(s, p)| strip_json(doc, *s, p, Some(day))).collect()),
                ),
                ("run", numbers(doc, &run)),
            ])
        })
        .collect();
    let waiting: Vec<Json> = doc
        .scenes_in_order()
        .into_iter()
        .filter_map(|scene| {
            let left: Vec<Id> = doc
                .placements_in_scene(scene)
                .into_iter()
                .filter(|p| doc.get(*p).and_then(|r| r.ref_id(f::DAY)).is_none())
                .filter(|p| pick.map(|k| k.placements.contains(p)).unwrap_or(true))
                .collect();
            (!left.is_empty()).then(|| strip_json(doc, scene, &left, None))
        })
        .collect();
    Json::object(vec![("days", Json::Array(days)), ("waiting", Json::Array(waiting))])
}

/// `position` as he counts, 1 first, into the engine's index.
fn position_arg(arguments: &Json) -> Result<Option<usize>, String> {
    match tools::number_arg(arguments, "position") {
        None => Ok(None),
        Some(n) if n >= 1.0 => Ok(Some(n as usize - 1)),
        Some(n) => Err(format!("position counts from 1, not {n}.")),
    }
}

/// A day's text field set only when asked: `Some("")` clears it.
fn text_arg(arguments: &Json, key: &str) -> Option<String> {
    arguments.get(key).and_then(|v| v.as_str()).map(|s| s.trim().to_string())
}

fn check_date(date: &Option<String>) -> Result<(), String> {
    if let Some(date) = date {
        let ok = date.is_empty()
            || (date.len() == 10
                && date.chars().enumerate().all(|(i, c)| if i == 4 || i == 7 { c == '-' } else { c.is_ascii_digit() }));
        if !ok {
            return Err(format!("A date is written YYYY-MM-DD, like 2026-10-03 — not {date}."));
        }
    }
    Ok(())
}

// ------------------------------------------------------------- a new shoot
//
// **One step, for Projects Console's New Shoot** (SL-1402, R116, 2026-10-02).
// The console never writes a film itself; it asks this, through the hub's
// console door, and the change lands as one change log like any other.
//
// Planned first, from the film as it stands, and only then made: a refusal
// found halfway would leave half a shoot behind, and on the web connector
// whatever a call changed is kept even when it ends refused. So every lookup
// that can say no is in `plan_shoot`, and `make_shoot` only does what the
// plan already found possible. `preview` is the plan said, and nothing made.

/// A pickup scene: which of its shots move, which stay where they were got.
struct Pickup {
    number: String,
    /// Not marked Shot, not on the shoot's day yet: these move.
    moving: Vec<Id>,
    /// Marked Shot: they stay on the day they were got.
    staying: Vec<Id>,
    /// Not marked Shot and already on the shoot's day.
    already: Vec<Id>,
}

struct ShootPlan {
    date: String,
    name: String,
    section_title: String,
    /// The section that already has this title, if one does.
    section: Option<Id>,
    /// How many sections answer to the title. More than one is said, never mended.
    same_title: usize,
    /// The day already dated and named for this shoot, if there is one.
    day: Option<Id>,
    pickups: Vec<Pickup>,
    version: String,
    /// A dated day that falls after this shoot but runs before it.
    later: Option<Id>,
    /// **The shoot the day belongs to** (stage 5 step 4, piece E): its
    /// Shoots row id, bare. The day follows the shoot's dates, and no
    /// section is made.
    shoot: Option<String>,
    /// The shoot's day is there but does not name the shoot yet.
    tie: bool,
}

impl ShootPlan {
    fn changes_anything(&self) -> bool {
        (self.shoot.is_none() && self.section.is_none()) || self.day.is_none() || self.tie || self.pickups.iter().any(|p| !p.moving.is_empty())
    }
}

const MONTHS: [&str; 12] = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
];

/// `2026-11-03` → `November 3`.
fn month_day(date: &str) -> String {
    let month: usize = date[5..7].parse().unwrap_or(1);
    let day: u32 = date[8..10].parse().unwrap_or(1);
    format!("{} {day}", MONTHS[month.clamp(1, 12) - 1])
}

/// A section title as two people typing it would both mean it: case, spacing,
/// and the dash or dot between words set aside. Let's Bake grew three
/// "Shoot 2 – October 6" sections by hand that differed in exactly these.
fn title_key(title: &str) -> String {
    title
        .chars()
        .map(|c| match c {
            '-' | '\u{2010}' | '\u{2011}' | '\u{2012}' | '\u{2013}' | '\u{2014}' | '\u{2015}' | '\u{00b7}' | '\u{2022}'
            | '|' | ':' | ',' => ' ',
            c => c,
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn plan_shoot(doc: &Doc, arguments: &Json) -> Result<ShootPlan, String> {
    let nothing = "Nothing was changed.";
    let date = arguments.str_field("date").trim().to_string();
    let name = arguments.str_field("name").trim().to_string();
    if name.is_empty() {
        return Err(format!("Say the shoot's name, like Shoot 3. {nothing}"));
    }
    if date.is_empty() {
        return Err(format!("Say the shoot's date, written YYYY-MM-DD. {nothing}"));
    }
    check_date(&Some(date.clone())).map_err(|e| format!("{e} {nothing}"))?;
    let month: u32 = date[5..7].parse().unwrap_or(0);
    let day_of: u32 = date[8..10].parse().unwrap_or(0);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day_of) {
        return Err(format!("{date} is not a date. {nothing}"));
    }

    let section_title = match text_arg(arguments, "section") {
        Some(title) if !title.is_empty() => title,
        _ => format!("{name} \u{00b7} {}", month_day(&date)),
    };
    let key = title_key(&section_title);
    let same: Vec<Id> = doc
        .sequences_in_order()
        .into_iter()
        .filter(|s| doc.get(*s).and_then(|r| r.text(f::TITLE)).map(title_key) == Some(key.clone()))
        .collect();

    let text = |id: Id, field: &str| doc.get(id).and_then(|r| r.text(field)).unwrap_or_default().trim().to_string();
    let shoot = match text_arg(arguments, "shoot") {
        Some(said) if !said.is_empty() => {
            let bare = shotlister_engine::shoots::bare(&said);
            if bare.is_empty() {
                return Err(format!("{said} is not a shoot's id. {nothing}"));
            }
            Some(bare)
        }
        _ => None,
    };
    // A day that already names the shoot is its day; else one dated and named for it.
    let day = shoot
        .as_ref()
        .and_then(|sh| doc.days_in_order().into_iter().find(|d| doc.said_shoot(*d) == *sh))
        .or_else(|| {
            doc.days_in_order()
                .into_iter()
                .find(|d| text(*d, f::DATE) == date && text(*d, f::TITLE).eq_ignore_ascii_case(&name))
        });
    let tie = match (&shoot, day) {
        (Some(sh), Some(d)) => doc.said_shoot(d) != *sh,
        _ => false,
    };
    let later = if day.is_none() {
        doc.days_in_order().into_iter().find(|d| {
            let theirs = text(*d, f::DATE);
            !theirs.is_empty() && theirs > date
        })
    } else {
        None
    };

    let mut pickups: Vec<Pickup> = Vec::new();
    let mut seen: Vec<Id> = Vec::new();
    for said in tools::list_arg(arguments, "pickups").unwrap_or_default() {
        let said = said.trim();
        if said.is_empty() {
            continue;
        }
        let scene = tools::find_scene(doc, said).ok_or(format!("There is no scene {said} in this project. {nothing}"))?;
        if seen.contains(&scene) {
            continue;
        }
        seen.push(scene);
        let number = number_of_scene(doc, scene);
        if doc.get(scene).map(|r| r.bool(f::ARCHIVED)).unwrap_or(false) {
            return Err(format!("Scene {number} is archived. Bring it back first. {nothing}"));
        }
        let placements = doc.placements_in_scene(scene);
        if placements.is_empty() {
            return Err(format!("Scene {number} has no shots, so it cannot go on a day. {nothing}"));
        }
        let mut pickup = Pickup { number: number.clone(), moving: vec![], staying: vec![], already: vec![] };
        for p in placements {
            let struck = tools::shot_of(doc, p)
                .and_then(|shot| doc.get(shot))
                .map(|r| r.bool(f::STRUCK))
                .unwrap_or(false);
            let on = doc.get(p).and_then(|r| r.ref_id(f::DAY));
            if struck {
                pickup.staying.push(p);
            } else if day.is_some() && on == day {
                pickup.already.push(p);
            } else {
                pickup.moving.push(p);
            }
        }
        if pickup.moving.is_empty() && pickup.already.is_empty() {
            return Err(format!(
                "Every shot in scene {number} is marked Shot, so there is nothing to pick up. Untick the ones to shoot again. {nothing}"
            ));
        }
        pickups.push(pickup);
    }

    let version = match text_arg(arguments, "version") {
        Some(v) if !v.is_empty() => v,
        _ => format!("Before {name} setup"),
    };
    Ok(ShootPlan {
        date,
        name,
        section_title,
        section: same.first().copied(),
        same_title: same.len(),
        day,
        pickups,
        version,
        later,
        shoot,
        tie,
    })
}

/// The plan in plain words, as it would be (`done` false) or as it went.
/// `day` is the shoot's day once made; before that the plan says where it will land.
fn shoot_said(doc: &Doc, plan: &ShootPlan, done: bool, day: Option<Id>) -> Json {
    let quoted = |t: &str| format!("\u{201c}{t}\u{201d}");
    let mut steps: Vec<String> = Vec::new();
    let changing = plan.changes_anything();
    if !changing {
        steps.push("Nothing to do: the section, the day and the pickups are already there.".to_string());
    } else if done {
        steps.push(format!("Saved version {}.", quoted(&plan.version)));
    } else {
        steps.push(format!("Save version {}.", quoted(&plan.version)));
    }

    let section_title = plan
        .section
        .and_then(|s| doc.get(s).and_then(|r| r.text(f::TITLE)).map(str::to_string))
        .unwrap_or_else(|| plan.section_title.clone());
    if plan.shoot.is_none() {
        let mut section_line = match (plan.section.is_some(), done) {
            (true, _) => format!("Section {} is already there.", quoted(&section_title)),
            (false, true) => format!("Added section {}.", quoted(&section_title)),
            (false, false) => format!("Add section {}.", quoted(&section_title)),
        };
        if plan.same_title > 1 {
            section_line.push_str(&format!(" {} sections have that title; this is the first.", plan.same_title));
        }
        steps.push(section_line);
    }

    let label = match day.or(plan.day) {
        Some(d) => doc.day_label(d).unwrap_or_default(),
        None => format!("Day {}", doc.days_in_order().len() + 1),
    };
    steps.push(match (plan.day.is_some(), done) {
        (true, _) => format!("{label} is already {}, {}.", plan.date, plan.name),
        (false, true) => format!("{label} is {}, {}.", plan.date, plan.name),
        (false, false) => format!("Add {label}: {}, {}.", plan.date, plan.name),
    });
    if plan.shoot.is_some() && (plan.day.is_none() || plan.tie) {
        steps.push(format!("It belongs to {} and follows its dates.", plan.name));
    }
    if let Some(later) = plan.later {
        let theirs = doc.get(later).and_then(|r| r.text(f::DATE)).unwrap_or_default();
        let them = doc.day_label(later).unwrap_or_default();
        steps.push(format!(
            "{them} is dated later ({theirs}) but runs before it. Sort the days by date in Shotlister to put them in order."
        ));
    }

    let numbers = |ps: &[Id]| ps.iter().map(|p| doc.display_number(*p).unwrap_or_default()).collect::<Vec<_>>();
    for pickup in &plan.pickups {
        let moving = numbers(&pickup.moving).join(", ");
        let mut line = if pickup.moving.is_empty() {
            format!("Scene {} is already on {label}.", pickup.number)
        } else if done {
            format!("Scene {} is on {label}: {moving}.", pickup.number)
        } else {
            format!("Put scene {} on {label}: {moving}.", pickup.number)
        };
        if !pickup.staying.is_empty() {
            let staying = numbers(&pickup.staying).join(", ");
            let one = pickup.staying.len() == 1;
            let (is, it) = if one { ("is", "it was") } else { ("are", "they were") };
            let stay = match (done, one) {
                (true, _) => "stayed",
                (false, true) => "stays",
                (false, false) => "stay",
            };
            line.push_str(&format!(" {staying} {is} marked Shot and {stay} where {it} got."));
        }
        steps.push(line);
    }

    let pickups = Json::Array(
        plan.pickups
            .iter()
            .map(|p| {
                Json::object(vec![
                    ("scene", Json::text(p.number.clone())),
                    ("moving", Json::Array(numbers(&p.moving).into_iter().map(Json::text).collect())),
                    ("staying", Json::Array(numbers(&p.staying).into_iter().map(Json::text).collect())),
                    ("already", Json::Array(numbers(&p.already).into_iter().map(Json::text).collect())),
                ])
            })
            .collect(),
    );
    Json::object(vec![
        ("preview", Json::Bool(!done)),
        ("changes", Json::Bool(changing)),
        ("said", Json::text(steps.join(" "))),
        ("steps", Json::Array(steps.into_iter().map(Json::text).collect())),
        (
            "section",
            Json::object(vec![
                ("title", Json::text(section_title)),
                ("new", Json::Bool(plan.section.is_none())),
                ("same_title", Json::Number(plan.same_title as f64)),
            ]),
        ),
        ("shoot", plan.shoot.clone().map(Json::text).unwrap_or(Json::Null)),
        (
            "day",
            Json::object(vec![
                ("day", Json::text(label)),
                ("date", Json::text(plan.date.clone())),
                ("name", Json::text(plan.name.clone())),
                ("new", Json::Bool(plan.day.is_none())),
            ]),
        ),
        ("pickups", pickups),
        ("version", if changing { Json::text(plan.version.clone()) } else { Json::Null }),
    ])
}

/// What the plan found possible, made. Nothing in here can refuse.
fn make_shoot(doc: &mut Doc, plan: &ShootPlan) -> Id {
    if plan.section.is_none() && plan.shoot.is_none() {
        doc.create_sequence(&plan.section_title);
    }
    let day = match plan.day {
        Some(day) => day,
        None => {
            let day = doc.create_day_dated(&plan.date);
            doc.rename_day(day, &plan.name);
            day
        }
    };
    // **Written once, belonging to the shoot** (piece E): the shoot's first
    // day, which follows the shoot's dates wherever the card lists it.
    if let Some(shoot) = &plan.shoot {
        if plan.day.is_none() || plan.tie {
            doc.set(day, f::SHOOT, Value::text(shoot.clone()));
            doc.set(day, f::SHOOT_DAY, Value::Int(0));
        }
    }
    for pickup in &plan.pickups {
        for p in &pickup.moving {
            doc.put_shot_on_day(*p, day, None);
        }
    }
    day
}

impl<F: Films> Server<F> {
    pub(super) fn schedule_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "schedule" => (|| {
                let doc = self.films.doc()?;
                let pick = super::shootpick::pick(doc, arguments)?;
                Ok(schedule(doc, pick.as_ref()).encode())
            })(),
            "add_day" => (|| {
                let date = text_arg(arguments, "date");
                check_date(&date)?;
                let name = text_arg(arguments, "name").unwrap_or_default();
                let position = position_arg(arguments)?;
                self.change("Add shoot day", move |doc| {
                    let day = match date.as_deref() {
                        Some(date) if !date.is_empty() => doc.create_day_dated(date),
                        _ => doc.create_day(),
                    };
                    if !name.is_empty() {
                        doc.rename_day(day, &name);
                    }
                    if let Some(at) = position {
                        doc.move_day_to(day, at);
                    }
                    Ok(format!("Added {}.", day_named(doc, day)))
                })
            })(),
            "update_day" => (|| {
                let wanted = arguments.str_field("day");
                let date = text_arg(arguments, "date");
                check_date(&date)?;
                let name = text_arg(arguments, "name");
                let position = position_arg(arguments)?;
                if date.is_none() && name.is_none() && position.is_none() {
                    return Err("Say what to change: date, name or position.".to_string());
                }
                self.change("Change shoot day", move |doc| {
                    let day = find_day(doc, &wanted)?;
                    if let Some(date) = &date {
                        doc.set_day_date(day, date);
                    }
                    if let Some(name) = &name {
                        doc.rename_day(day, name);
                    }
                    if let Some(at) = position {
                        doc.move_day_to(day, at);
                    }
                    Ok(format!("It is {} now.", day_named(doc, day)))
                })
            })(),
            "delete_day" => {
                let wanted = arguments.str_field("day");
                let anyway = tools::bool_arg(arguments, "even_with_shots").unwrap_or(false);
                self.change("Remove day", move |doc| {
                    let day = find_day(doc, &wanted)?;
                    let named = day_named(doc, day);
                    let on = doc.shot_count_on_day(day);
                    if on > 0 && !anyway {
                        return Err(format!(
                            "{named} has {on} shot{} on it. Nothing was removed. Its shots would keep everything and go back to waiting — ask him, then call again with even_with_shots=true.",
                            if on == 1 { "" } else { "s" }
                        ));
                    }
                    let freed = doc.delete_day(day);
                    Ok(if freed == 0 {
                        format!("Removed {named}.")
                    } else {
                        format!("Removed {named}; its {freed} shot{} are waiting for a day.", if freed == 1 { "" } else { "s" })
                    })
                })
            }
            "order_days" => (|| {
                let named = tools::list_arg(arguments, "days").unwrap_or_default();
                let sort = arguments.str_field("sort").trim().to_ascii_lowercase();
                let naming = named.iter().any(|d| !d.trim().is_empty());
                if naming == !sort.is_empty() {
                    return Err("Give either days (the order you want) or sort=date.".to_string());
                }
                if !sort.is_empty() && sort != "date" && sort != "dates" {
                    return Err(format!("Days sort by date, not {sort}."));
                }
                self.change("Order days", move |doc| {
                    if naming {
                        // Found before any moves: a label names a place, and
                        // the places change as days move.
                        let mut wanted: Vec<Id> = Vec::new();
                        for said in named.iter().filter(|d| !d.trim().is_empty()) {
                            let day = find_day(doc, said)?;
                            if !wanted.contains(&day) {
                                wanted.push(day);
                            }
                        }
                        for (at, day) in wanted.iter().enumerate() {
                            doc.move_day_to(*day, at);
                        }
                    } else if !doc.sort_days_by_date() {
                        return Ok("The dated days were already in date order.".to_string());
                    }
                    Ok(format!(
                        "The days: {}.",
                        doc.days_in_order().into_iter().map(|d| day_named(doc, d)).collect::<Vec<_>>().join("; ")
                    ))
                })
            })(),
            "schedule_scene" => (|| {
                let scenes = tools::list_arg(arguments, "scenes")
                    .or_else(|| tools::list_arg(arguments, "scene"))
                    .unwrap_or_default();
                if scenes.iter().all(|s| s.trim().is_empty()) {
                    return Err("Say which scenes: scenes.".to_string());
                }
                let wanted_day = arguments.str_field("day");
                let before = arguments.str_field("before");
                let from = arguments.str_field("from");
                self.change("Schedule scenes", move |doc| {
                    let day = if wanted_day.trim().is_empty() || wanted_day.trim().eq_ignore_ascii_case("none") {
                        None
                    } else {
                        Some(find_day(doc, &wanted_day)?)
                    };
                    let from = if from.trim().is_empty() { None } else { Some(find_day(doc, &from)?) };
                    let before = if before.trim().is_empty() {
                        None
                    } else {
                        let scene = tools::find_scene(doc, &before)
                            .ok_or(format!("There is no scene {before} in this project."))?;
                        if let Some(day) = day {
                            if !doc.placements_on_day(day).iter().any(|p| scene_of(doc, *p) == Some(scene)) {
                                return Err(format!("Scene {before} is not on {}.", day_named(doc, day)));
                            }
                        }
                        Some(scene)
                    };
                    let mut found = Vec::new();
                    let mut empty = Vec::new();
                    for said in scenes.iter().filter(|s| !s.trim().is_empty()) {
                        let scene = tools::find_scene(doc, said)
                            .ok_or(format!("There is no scene {} in this project.", said.trim()))?;
                        if doc.placements_in_scene(scene).is_empty() {
                            empty.push(said.trim().to_string());
                        } else {
                            found.push(scene);
                        }
                    }
                    if found.is_empty() {
                        return Err(format!(
                            "Scene {} has no shots, so there is nothing to put on a day. Add a shot first.",
                            empty.join(", ")
                        ));
                    }
                    doc.put_scenes_on_day(&found, from, day, before);
                    let named: Vec<String> = found.iter().map(|s| number_of_scene(doc, *s)).collect();
                    let mut said = match day {
                        None => format!("Scene {} off the schedule; its shots are waiting.", named.join(", ")),
                        Some(day) => {
                            let order: Vec<String> = strips(doc, &doc.placements_on_day(day))
                                .iter()
                                .map(|(s, _)| number_of_scene(doc, *s))
                                .collect();
                            format!("{}: scenes {}.", day_named(doc, day), order.join(", "))
                        }
                    };
                    if !empty.is_empty() {
                        said.push_str(&format!(" Scene {} has no shots, so it stayed off.", empty.join(", ")));
                    }
                    Ok(said)
                })
            })(),
            "schedule_shot" => (|| {
                let shots = tools::list_arg(arguments, "shots")
                    .or_else(|| tools::list_arg(arguments, "shot"))
                    .unwrap_or_default();
                if shots.iter().all(|s| s.trim().is_empty()) {
                    return Err("Say which shots: shots.".to_string());
                }
                let wanted_day = arguments.str_field("day");
                let before = arguments.str_field("before");
                let position = position_arg(arguments)?;
                self.change("Schedule shot", move |doc| {
                    let day = if wanted_day.trim().is_empty() || wanted_day.trim().eq_ignore_ascii_case("none") {
                        None
                    } else {
                        Some(find_day(doc, &wanted_day)?)
                    };
                    let before = if before.trim().is_empty() {
                        None
                    } else {
                        Some(tools::find_scene(doc, &before).ok_or(format!("There is no scene {before} in this project."))?)
                    };
                    let mut placements = Vec::new();
                    for said in shots.iter().filter(|s| !s.trim().is_empty()) {
                        placements.push(
                            tools::find_placement(doc, said)
                                .ok_or(format!("There is no shot {} in this project.", said.trim()))?,
                        );
                    }
                    match day {
                        None => {
                            for p in &placements {
                                doc.unschedule(*p);
                            }
                            Ok(format!("{} off the schedule.", numbers_said(doc, &placements)))
                        }
                        Some(day) => {
                            // **Several at once stand together** (2026-10-17,
                            // `put_shots_on_day`), as the Mac's drag of shots
                            // picked in an opened scene does; one is the old
                            // single-shot split.
                            if placements.len() > 1 && position.is_none() {
                                doc.put_shots_on_day(&placements, day, before);
                            }
                            for (i, p) in placements.iter().enumerate() {
                                if placements.len() == 1 || position.is_some() {
                                    doc.put_shot_on_day(*p, day, before);
                                }
                                if let Some(at) = position {
                                    doc.move_in_day_to(*p, at + i);
                                }
                            }
                            let run = doc.placements_on_day(day);
                            Ok(format!("{} runs: {}.", day_named(doc, day), numbers_said(doc, &run)))
                        }
                    }
                })
            })(),
            "order_day" => (|| {
                let shots = tools::list_arg(arguments, "shots")
                    .or_else(|| tools::list_arg(arguments, "shot"))
                    .unwrap_or_default();
                if shots.iter().all(|s| s.trim().is_empty()) {
                    return Err("Say the shots in the order they are shot: shots.".to_string());
                }
                let wanted_day = arguments.str_field("day");
                self.change("Order day", move |doc| {
                    let day = find_day(doc, &wanted_day)?;
                    let mut wanted: Vec<Id> = Vec::new();
                    for said in shots.iter().filter(|s| !s.trim().is_empty()) {
                        let p = tools::find_placement(doc, said)
                            .ok_or(format!("There is no shot {} in this project.", said.trim()))?;
                        if !wanted.contains(&p) {
                            wanted.push(p);
                        }
                    }
                    // Each to its place from the top, in turn: once the first
                    // k are seated, the next lands right after them.
                    for (at, p) in wanted.iter().enumerate() {
                        doc.schedule_at(*p, day, at);
                    }
                    let run = doc.placements_on_day(day);
                    Ok(format!("{} runs: {}.", day_named(doc, day), numbers_said(doc, &run)))
                })
            })(),
            "move_to_shoot" => (|| {
                let scenes = tools::list_arg(arguments, "scenes")
                    .or_else(|| tools::list_arg(arguments, "scene"))
                    .unwrap_or_default();
                if scenes.iter().all(|s| s.trim().is_empty()) {
                    return Err("Say which scenes: scenes.".to_string());
                }
                let asked = arguments.get("shoot").and_then(|v| match v {
                    Json::Number(n) => Some(format!("{}", *n as i64)),
                    other => other.as_str().map(str::to_string),
                });
                let asked = asked.unwrap_or_default();
                if asked.trim().is_empty() {
                    return Err("Say which shoot: shoot.".to_string());
                }
                self.change("Move to Shoot", move |doc| {
                    let (id, name) = super::shootpick::card_shoot(doc, &asked)?;
                    let mut found = Vec::new();
                    for said in scenes.iter().filter(|s| !s.trim().is_empty()) {
                        found.push(tools::find_scene(doc, said).ok_or(format!("There is no scene {} in this project.", said.trim()))?);
                    }
                    let moved = doc.move_scenes_to_shoot(&found, &id);
                    let named: Vec<String> = found.iter().map(|s| number_of_scene(doc, *s)).collect();
                    Ok(if moved == 0 {
                        format!("Scene {} {} already in {name}.", named.join(", "), if named.len() == 1 { "is" } else { "are" })
                    } else {
                        format!("Scene {} {} in {name}.", named.join(", "), if named.len() == 1 { "is now" } else { "are now" })
                    })
                })
            })(),
            "new_shoot" => (|| {
                let preview = tools::bool_arg(arguments, "preview").unwrap_or(false);
                let plan = plan_shoot(self.films.doc()?, arguments)?;
                // A preview of a film that may not be changed says so, rather
                // than showing a plan the real press would refuse.
                if self.films.read_only() {
                    return Err("This project is open for reading only. Nothing was changed.".to_string());
                }
                if preview || !plan.changes_anything() {
                    let doc = self.films.doc()?;
                    return Ok(shoot_said(doc, &plan, !preview, plan.day).encode());
                }
                // **The version first, as its own step**, so it is a moment
                // before the shoot was set up and survives the shoot's undo.
                let version = plan.version.clone();
                self.change("Save Version", move |doc| {
                    doc.save_version(&version);
                    Ok(String::new())
                })?;
                let made = std::cell::Cell::new(None);
                self.change("New Shoot", |doc| {
                    made.set(Some(make_shoot(doc, &plan)));
                    Ok(String::new())
                })?;
                let doc = self.films.doc()?;
                Ok(shoot_said(doc, &plan, true, made.get()).encode())
            })(),
            _ => return None,
        })
    }
}

fn numbers_said(doc: &Doc, placements: &[Id]) -> String {
    placements
        .iter()
        .map(|p| doc.display_number(*p).unwrap_or_default())
        .collect::<Vec<_>>()
        .join(", ")
}
