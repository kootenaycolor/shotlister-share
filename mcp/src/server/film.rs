//! The film itself: its name and its people, and how its scenes and sections
//! are told apart.

use shotlister_engine::{f, Doc, Value};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "update_project",
        description: "Change the project's details, as Settings → General does: `title`, `director`, `producer`, `client` and `agency` (a commercial's), and the aspect ratio. With the project's aspect ratios on its spec sheet (each a name and a ratio, no resolution), `frame` picks the one Studio draws at by name (Delivery, Social), independently of the portal's Main, and `frame_guides`=true shows the others as guide lines; `aspect_ratio` then picks the one at that ratio. A project with none takes `aspect_ratio` as any ratio: 2.39, 1.85:1, 2.76, 16:9, 9:16 (vertical), 4096x1716. The aspect ratios themselves are edited in the spec sheet (set_spec_sheet's `aspect_ratio`). Only what is given changes; \"\" clears a name. summary reads them back.",
        arguments: &[
            ("title", "string", false),
            ("director", "string", false),
            ("producer", "string", false),
            ("client", "string", false),
            ("agency", "string", false),
            ("aspect_ratio", "string", false),
            ("frame", "string", false),
            ("frame_guides", "boolean", false),
        ],
    },
    Tool {
        name: "document_page",
        description: "The Document page (the shot list laid out as a page of words and frames): how its type is set and where a shot's frame sits. With nothing given it answers every kind of words on the page — title, credits, scene_heading, scene_number, shot_title, body, technical, notes, shot_number — each with its size (points), face (serif, sans or mono), case (as, upper or lower; not on shot_title, body or notes, which keep what he typed) and colour (six hex digits). `class` with any of `size` (4–48), `face`, `case`, `colour` changes that one, as the page's Aa menu does; `reset`=true puts the whole page back to the standard type. `shot` with `frame` (below, above, left or right of the words) and/or `frame_width` (0.1–1, a fraction of the line) places that shot's frame, as the Frames menu does. One undo step.",
        arguments: &[
            ("class", "string", false),
            ("size", "number", false),
            ("face", "string", false),
            ("case", "string", false),
            ("colour", "string", false),
            ("reset", "boolean", false),
            ("shot", "string", false),
            ("frame", "string", false),
            ("frame_width", "number", false),
        ],
    },
    Tool {
        name: "settle_times",
        description: "Turn the scenes' CONTINUED and LATER times of day into the time they follow on from, as Settle Times of Day on the scene list's menu does — for a script taken in before that was read properly. Answers how many scenes changed. One undo step.",
        arguments: &[],
    },
];

/// The section colours the app offers — the same eight a term can wear.
const SECTION_COLOURS: [&str; 8] = ["2C7A7B", "2B6CB0", "4C51BF", "7B4BC4", "A33574", "9A6B10", "2F7A44", "B4531B"];

/// A section's colour as he says it: one of the eight by its place (1–8) or
/// any six hex digits.
pub(super) fn section_colour(said: &str) -> Result<String, String> {
    let said = said.trim().trim_start_matches('#');
    if let Ok(n) = said.parse::<usize>() {
        if (1..=8).contains(&n) {
            return Ok(SECTION_COLOURS[n - 1].to_string());
        }
    }
    if said.len() == 6 && said.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(said.to_uppercase());
    }
    Err(format!(
        "A section's colour is one of {} (or 1–8 for those in order), or six hex digits — not {said}.",
        SECTION_COLOURS.join(" ")
    ))
}

/// The ratio a person types — `2.39`, `2.39:1`, `9:16`, `4096x1716` — as the
/// number. The engine's own reading, so the connector and the app agree.
fn ratio(said: &str) -> Result<f64, String> {
    shotlister_engine::ratio::parse(said)
        .ok_or_else(|| format!("An aspect ratio reads like 2.39, 1.85:1 or 9:16 — not {said}."))
}

/// A scene's number is the script's. Two scenes under one number make every
/// shot number ambiguous, so a clash is refused.
pub(super) fn check_scene_number(doc: &Doc, scene: shotlister_engine::Id, number: &str) -> Result<(), String> {
    let number = number.trim();
    if number.is_empty() {
        return Err("A scene's number cannot be empty.".to_string());
    }
    let clash = doc
        .scenes_in_order()
        .into_iter()
        .any(|other| other != scene && doc.get(other).and_then(|r| r.text(f::NUMBER)).map(|n| n.eq_ignore_ascii_case(number)) == Some(true));
    if clash {
        return Err(format!("There is already a scene {number}."));
    }
    Ok(())
}

impl<F: Films> Server<F> {
    pub(super) fn film_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "update_project" => (|| {
                let text = |key: &str| arguments.get(key).and_then(|v| v.as_str()).map(|s| s.trim().to_string());
                let fields: Vec<(&'static str, String)> = [
                    ("title", f::TITLE),
                    ("director", f::DIRECTOR),
                    ("producer", f::PRODUCER),
                    ("client", f::CLIENT),
                    ("agency", f::AGENCY),
                ]
                .into_iter()
                .filter_map(|(key, field)| text(key).map(|v| (field, v)))
                .collect();
                let frame = match text("aspect_ratio") {
                    Some(said) => Some(ratio(&said)?),
                    None => None,
                };
                let named = text("frame").filter(|s| !s.is_empty());
                let guides = tools::bool_arg(arguments, "frame_guides");
                if fields.is_empty() && frame.is_none() && named.is_none() && guides.is_none() {
                    return Err("Say what to change: title, director, producer, client, agency, frame or aspect_ratio.".to_string());
                }
                if fields.iter().any(|(field, v)| *field == f::TITLE && v.is_empty()) {
                    return Err("A film needs a title.".to_string());
                }
                self.change("Change film", move |doc| {
                    let project = doc.project_id().ok_or("This project has no record to hold its details.")?;
                    // **The project record owns these once a film takes its
                    // facts from it** (one-record plan, 2026-10-05) — the app
                    // shows them and does not let them be typed over, so the
                    // connector does not either.
                    if doc.facts_from_record() {
                        let owned: Vec<&str> = fields
                            .iter()
                            .filter(|(field, _)| shotlister_engine::recordfacts::owned(field))
                            .map(|(field, _)| *field)
                            .collect();
                        if !owned.is_empty() {
                            return Err(format!(
                                "{} come{} from the project record — change {} in Projects Console.",
                                owned.join(", "),
                                if owned.len() == 1 { "s" } else { "" },
                                if owned.len() == 1 { "it" } else { "them" },
                            ));
                        }
                    }
                    for (field, value) in &fields {
                        doc.set(project, field, value.as_str());
                    }
                    // **The project's frames, off its spec sheet** (piece E):
                    // Studio picks one of them; a ratio picks the frame at it.
                    if let Some(frames) = doc.frames() {
                        let listed = || frames.iter().map(|x| format!("{} {}", x.name, x.said)).collect::<Vec<_>>().join(", ");
                        let mut want = named.clone();
                        if let Some(r) = frame {
                            match frames.iter().find(|x| (x.ratio - r).abs() < 0.005) {
                                Some(x) => want = Some(x.name.clone()),
                                None => return Err(format!("This project's aspect ratios are on its spec sheet: {}. Pick one with `frame`, or add one in the spec sheet.", listed())),
                            }
                        }
                        if let Some(name) = want {
                            if !doc.pick_frame(&name) {
                                return Err(format!("There is no aspect ratio called {name}. This project's aspect ratios: {}.", listed()));
                            }
                        }
                    } else {
                        if named.is_some() {
                            return Err("This project has no aspect ratios on a spec sheet; set `aspect_ratio` instead.".to_string());
                        }
                        if let Some(r) = frame {
                            doc.set(project, f::ASPECT_RATIO, Value::Float(r));
                        }
                    }
                    if let Some(on) = guides {
                        doc.set_frame_guides(on);
                    }
                    let record = doc.get(project);
                    let said = |field: &str| record.and_then(|r| r.text(field)).unwrap_or_default().to_string();
                    let mut out = vec![format!("Title: {}", said(f::TITLE))];
                    for (label, field) in [("Director", f::DIRECTOR), ("Producer", f::PRODUCER), ("Client", f::CLIENT), ("Agency", f::AGENCY)] {
                        let v = said(field);
                        if !v.is_empty() {
                            out.push(format!("{label}: {v}"));
                        }
                    }
                    match doc.picked_frame() {
                        Some(x) => out.push(format!("Frame: {} {}{}", x.name, x.said, if doc.frame_guides() { ", others as guides" } else { "" })),
                        None => {
                            if let Some(r) = record.and_then(|r| r.float(f::ASPECT_RATIO)) {
                                out.push(format!("Frame: {r} : 1"));
                            }
                        }
                    }
                    Ok(format!("{}.", out.join(". ")))
                })
            })(),
            "document_page" => self.document_page(arguments),
            "settle_times" => self.change("Settle Times of Day", |doc| {
                let n = doc.settle_scene_times();
                Ok(if n == 0 {
                    "No scene had a CONTINUED or LATER to settle.".to_string()
                } else {
                    format!("Settled the time of day on {n} scene{}.", if n == 1 { "" } else { "s" })
                })
            }),
            _ => return None,
        })
    }

    fn document_page(&mut self, arguments: &Json) -> Result<String, String> {
        use shotlister_engine::docstyle::{self, Case, Class, Colour, Face, Setting, Style};
        use shotlister_engine::FramePosition;
        let said = |s: &Setting, class: Class| {
            let mut pairs = vec![
                ("class", Json::text(class.key())),
                ("label", Json::text(class.label())),
                ("size", Json::Number(s.size)),
                ("face", Json::text(s.face.key())),
            ];
            if class.takes_case() {
                pairs.push(("case", Json::text(s.case.key())));
            }
            pairs.push(("colour", Json::text(s.colour.hex())));
            Json::object(pairs)
        };
        let wants_type = ["class", "size", "face", "case", "colour"].iter().any(|k| arguments.get(k).is_some())
            || tools::bool_arg(arguments, "reset") == Some(true);
        let shot_said = arguments.str_field("shot");
        let wants_frame = !shot_said.trim().is_empty() && (arguments.get("frame").is_some() || arguments.get("frame_width").is_some());
        if !wants_type && !wants_frame {
            let doc = self.films.doc()?;
            let project = doc.project_id().ok_or("This project has no record to hold its page's type.")?;
            let style = docstyle::of(doc, project);
            let mut out = vec![("type", Json::Array(style.all().iter().map(|(c, s)| said(s, *c)).collect()))];
            if !shot_said.trim().is_empty() {
                let placement = tools::find_placement(doc, &shot_said).ok_or(format!("There is no shot {shot_said} in this project."))?;
                let shot = tools::shot_of(doc, placement).ok_or(format!("There is no shot {shot_said} in this project."))?;
                out.push(("shot", Json::object(vec![
                    ("frame", Json::text(doc.frame_position(shot).as_str())),
                    ("frame_width", Json::Number(doc.frame_width(shot))),
                ])));
            }
            return Ok(Json::object(out).encode());
        }
        let arguments = arguments.clone();
        self.change("Document Page", move |doc| {
            let mut out = Vec::new();
            if wants_type {
                let project = doc.project_id().ok_or("This project has no record to hold its page's type.")?;
                let now = docstyle::of(doc, project);
                let next = if tools::bool_arg(&arguments, "reset") == Some(true) {
                    out.push("the page's type is back to standard".to_string());
                    Style::standard_style()
                } else {
                    let asked = arguments.str_field("class").trim().to_lowercase().replace([' ', '-'], "_");
                    let class = Class::read(&asked)
                        .or_else(|| Class::ALL.into_iter().find(|c| c.label().eq_ignore_ascii_case(arguments.str_field("class").trim())))
                        .ok_or_else(|| format!("Say which words: {}.", Class::ALL.iter().map(|c| c.key()).collect::<Vec<_>>().join(", ")))?;
                    let mut one = now.get(class);
                    if let Some(size) = tools::number_arg(&arguments, "size") {
                        if !(4.0..=48.0).contains(&size) {
                            return Err("A size is between 4 and 48 points.".to_string());
                        }
                        one.size = size;
                    }
                    if arguments.get("face").is_some() {
                        one.face = Face::read(&arguments.str_field("face").trim().to_lowercase()).ok_or("face is serif, sans or mono.")?;
                    }
                    if arguments.get("case").is_some() {
                        if !class.takes_case() {
                            return Err(format!("{} keeps what he typed; it takes no case.", class.label()));
                        }
                        let c = arguments.str_field("case").trim().to_lowercase();
                        let c = if c == "as typed" { "as".to_string() } else { c };
                        one.case = Case::read(&c).ok_or("case is as, upper or lower.")?;
                    }
                    if arguments.get("colour").is_some() {
                        one.colour = Colour::read(&arguments.str_field("colour")).ok_or("colour is six hex digits, like 17171a.")?;
                    }
                    out.push(format!("{}: {} pt {} {}{}", class.label(), one.size, one.face.key(), if class.takes_case() { format!("{} ", one.case.key()) } else { String::new() }, one.colour.hex()));
                    now.with(class, one)
                };
                doc.set(project, f::DOC_STYLE, Value::text(next.encode()));
            }
            if wants_frame {
                let placement = tools::find_placement(doc, &shot_said).ok_or(format!("There is no shot {shot_said} in this project."))?;
                let shot = tools::shot_of(doc, placement).ok_or(format!("There is no shot {shot_said} in this project."))?;
                if arguments.get("frame").is_some() {
                    let said = arguments.str_field("frame").trim().to_lowercase();
                    if !["below", "above", "left", "right"].contains(&said.as_str()) {
                        return Err("frame is below, above, left or right.".to_string());
                    }
                    doc.set_frame_position(shot, FramePosition::parse(&said));
                }
                if let Some(w) = tools::number_arg(&arguments, "frame_width") {
                    doc.set_frame_width(shot, w);
                }
                out.push(format!("{shot_said}'s frame sits {} at {:.0}% of the line", doc.frame_position(shot).as_str(), doc.frame_width(shot) * 100.0));
            }
            Ok(format!("{}.", out.join("; ")))
        })
    }
}

/// Priority and POV on a scene — the scene's own lists — the way the table
/// writes them. Returns what a locked list kept off.
pub(super) fn apply_scene_lists(doc: &mut Doc, scene: shotlister_engine::Id, arguments: &Json) -> Vec<String> {
    let mut kept_off = Vec::new();
    let locked_out = |doc: &Doc, name: &str, term: &str| -> Option<String> {
        (!term.trim().is_empty() && doc.vocabulary_locked(name) && !doc.vocabulary_contains(name, term.trim())).then(|| {
            let title = tools::list_title(doc, name);
            format!("{title} {} was not set: the {} list is locked and does not hold it.", term.trim(), title.to_lowercase())
        })
    };
    if let Some(value) = arguments.get("priority").and_then(|v| v.as_str()) {
        kept_off.extend(locked_out(doc, "priority", value));
        doc.set_vocab_field(scene, "priority", value);
    }
    if let Some(value) = arguments.get("pov").and_then(|v| v.as_str()) {
        let parts: Vec<&str> = value.split(',').map(|p| p.trim()).filter(|p| !p.is_empty()).collect();
        for part in &parts {
            kept_off.extend(locked_out(doc, "pov", part));
        }
        doc.set_vocab_list(scene, "pov", &parts);
    }
    // A scene's own tags (the line under its heading), from the one tag list
    // the shots, boards and locations share.
    if let Some(value) = arguments.get("tags").and_then(|v| v.as_str()) {
        let parts: Vec<&str> = value.split(',').map(|p| p.trim()).filter(|p| !p.is_empty()).collect();
        for part in &parts {
            kept_off.extend(locked_out(doc, "tags", part));
        }
        doc.set_vocab_list(scene, "tags", &parts);
    }
    kept_off
}
