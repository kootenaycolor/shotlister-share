//! Shots beyond their cells: where they sit, copies of them, the cameras that
//! shoot them, and the columns the table shows them in.

use shotlister_engine::{f, Doc, Id};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "order_shot",
        description: "Move a shot within its scene's running order: `after` or `before` another shot in the scene, or `position` (1 is first). Before the first shoot day, letters follow position, so shots can be renamed by this — the reply gives the scene's order as it now reads. To move a shot to another scene, move_shot.",
        arguments: &[
            ("shot", "string", true),
            ("after", "string", false),
            ("before", "string", false),
            ("position", "number", false),
        ],
    },
    Tool {
        name: "duplicate_shot",
        description: "Copy shots — everything on them, frames included, but not the Shot mark or an A/B tie. Each copy lands just after its original, or in scene `into` (after shot `after` there, else last). `count` makes several copies of one shot.",
        arguments: &[
            ("shots", "array", true),
            ("into", "string", false),
            ("after", "string", false),
            ("count", "number", false),
        ],
    },
    Tool {
        name: "cameras",
        description: "The project's cameras — which body shot it, for a multicam day or a second camera — each with its name, body, colour and how many shots name it.",
        arguments: &[],
    },
    Tool {
        name: "add_camera",
        description: "Add a camera: `name` (\"A-Cam\"), optional `body` (\"Alexa 35\"), `colour` (red, orange, green, blue, purple, pink or hex; without one it takes the next in turn), and the sensor it reads: `sensor_name` (\"Alexa Mini LF Open Gate\"), `sensor_w` and `sensor_h` in mm. Every shot on it, and its lens cone on a diagram, reads that sensor. A shot names it with update_shot camera.",
        arguments: &[("name", "string", true), ("body", "string", false), ("colour", "string", false),
                     ("sensor_name", "string", false), ("sensor_w", "number", false), ("sensor_h", "number", false)],
    },
    Tool {
        name: "update_camera",
        description: "Rename a camera, change its body, recolour it, or set the sensor it reads (`sensor_name`, `sensor_w`, `sensor_h` in mm; sensor_w 0 clears it). Every shot naming it follows, and so does every lens cone on a diagram.",
        arguments: &[
            ("camera", "string", true),
            ("name", "string", false),
            ("body", "string", false),
            ("colour", "string", false),
            ("sensor_name", "string", false),
            ("sensor_w", "number", false),
            ("sensor_h", "number", false),
        ],
    },
    Tool {
        name: "delete_camera",
        description: "Take a camera away. Shots naming it keep everything else and simply stop naming a camera. One that shots name is refused, saying how many, unless `even_if_used` is true — ask him first.",
        arguments: &[("camera", "string", true), ("even_if_used", "boolean", false)],
    },
    Tool {
        name: "columns",
        description: "The shot list's columns in order: each one's name, whether it shows, and for the project's own columns their kind and how many shots have something in them. A pick-list column's choices are a list — see lists.",
        arguments: &[],
    },
    Tool {
        name: "add_column",
        description: "Add a column of the project's own to the shot list. `kind`: text (words), single (one choice from its own list), multi (several), check (a tick). Values go on with update_shot fields.",
        arguments: &[("name", "string", true), ("kind", "string", false)],
    },
    Tool {
        name: "update_column",
        description: "Change a column: `name` renames one of the project's own (the built-in ones keep theirs); `visible` shows or hides any column — hiding moves nothing and loses nothing; `position` moves it (1 is first).",
        arguments: &[
            ("column", "string", true),
            ("name", "string", false),
            ("visible", "boolean", false),
            ("position", "number", false),
        ],
    },
    Tool {
        name: "delete_column",
        description: "Take away a column the project made, and everything written in it. One that shots have values in is refused, saying how many, unless `even_with_values` is true — ask him first. Built-in columns cannot be deleted; hide them with update_column.",
        arguments: &[("column", "string", true), ("even_with_values", "boolean", false)],
    },
];

fn scene_of(doc: &Doc, placement: Id) -> Option<Id> {
    doc.get(placement).and_then(|r| r.ref_id(f::SCENE))
}

fn scene_run(doc: &Doc, scene: Id) -> String {
    doc.placements_in_scene(scene)
        .into_iter()
        .filter_map(|p| doc.display_number(p))
        .collect::<Vec<_>>()
        .join(", ")
}

fn position_arg(arguments: &Json) -> Result<Option<usize>, String> {
    match tools::number_arg(arguments, "position") {
        None => Ok(None),
        Some(n) if n >= 1.0 => Ok(Some(n as usize - 1)),
        Some(n) => Err(format!("position counts from 1, not {n}.")),
    }
}

fn plural(n: usize, one: &str) -> String {
    format!("{n} {one}{}", if n == 1 { "" } else { "s" })
}

// ---- columns -------------------------------------------------------------

/// What the table calls a column.
fn column_label(doc: &Doc, field: &str) -> String {
    if field == "sequence" && doc.kind() == shotlister_engine::FilmKind::Commercial {
        return "Section".to_string();
    }
    doc.custom_columns()
        .into_iter()
        .find(|c| c.field == field)
        .map(|c| c.label)
        .unwrap_or_else(|| shotlister_engine::columns::label_for(field).to_string())
}

/// A column by what the table calls it, or by its field.
fn find_column(doc: &Doc, said: &str) -> Result<String, String> {
    let wanted = said.trim();
    let order = doc.column_order();
    order
        .iter()
        .find(|field| field.as_str() == wanted || column_label(doc, field).eq_ignore_ascii_case(wanted))
        .cloned()
        .ok_or_else(|| {
            format!(
                "There is no column {wanted}. The columns are {}.",
                order.iter().map(|f| column_label(doc, f)).collect::<Vec<_>>().join(", ")
            )
        })
}

fn columns(doc: &Doc) -> Json {
    let customs = doc.custom_columns();
    Json::Array(
        doc.column_order()
            .into_iter()
            .map(|field| {
                let mut pairs = vec![
                    ("name", Json::text(column_label(doc, &field))),
                    ("field", Json::text(field.clone())),
                    ("visible", Json::Bool(doc.is_column_visible(&field))),
                ];
                if let Some(own) = customs.iter().find(|c| c.field == field) {
                    pairs.push(("kind", Json::text(own.kind.clone())));
                    pairs.push(("shots_with_values", Json::Number(doc.shots_with_value(&field) as f64)));
                }
                Json::object(pairs)
            })
            .collect(),
    )
}

fn column_kind(said: &str) -> Result<&'static str, String> {
    Ok(match said.trim().to_ascii_lowercase().as_str() {
        "" | "text" | "words" => "text",
        "single" | "choice" | "pick" | "select" | "dropdown" => "single",
        "multi" | "choices" | "multiple" | "multi-select" | "several" => "multi",
        "check" | "checkbox" | "tick" | "yes/no" => "check",
        other => return Err(format!("A column's kind is text, single, multi or check — not {other}.")),
    })
}

impl<F: Films> Server<F> {
    pub(super) fn shot_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "order_shot" => (|| {
                let reference = arguments.str_field("shot");
                let after = arguments.str_field("after");
                let before = arguments.str_field("before");
                let position = position_arg(arguments)?;
                let asked = [!after.trim().is_empty(), !before.trim().is_empty(), position.is_some()]
                    .iter()
                    .filter(|x| **x)
                    .count();
                if asked != 1 {
                    return Err("Say one of after, before or position.".to_string());
                }
                self.change("Move shot", move |doc| {
                    let placement = tools::find_placement(doc, &reference)
                        .ok_or(format!("There is no shot {reference} in this project."))?;
                    let scene = scene_of(doc, placement).ok_or(format!("{reference} is in no scene."))?;
                    let others: Vec<Id> = doc.placements_in_scene(scene).into_iter().filter(|p| *p != placement).collect();
                    let beside = |said: &str| -> Result<usize, String> {
                        let other = tools::find_placement(doc, said)
                            .ok_or(format!("There is no shot {} in this project.", said.trim()))?;
                        others
                            .iter()
                            .position(|p| *p == other)
                            .ok_or(format!("{} is not beside {reference} in its scene.", said.trim()))
                    };
                    let index = if !after.trim().is_empty() {
                        beside(&after)? + 1
                    } else if !before.trim().is_empty() {
                        beside(&before)?
                    } else {
                        position.unwrap_or(0).min(others.len())
                    };
                    doc.move_in_scene_to(placement, index);
                    let now = doc.display_number(placement).unwrap_or_default();
                    Ok(format!(
                        "{}Scene runs: {}.",
                        if now.eq_ignore_ascii_case(reference.trim()) { String::new() } else { format!("{reference} is {now} now. ") },
                        scene_run(doc, scene)
                    ))
                })
            })(),
            "duplicate_shot" => (|| {
                let shots = tools::list_arg(arguments, "shots").or_else(|| tools::list_arg(arguments, "shot")).unwrap_or_default();
                if shots.iter().all(|s| s.trim().is_empty()) {
                    return Err("Say which shots: shots.".to_string());
                }
                let into = arguments.str_field("into");
                let after = arguments.str_field("after");
                let count = tools::number_arg(arguments, "count").unwrap_or(1.0);
                if !(1.0..=50.0).contains(&count) {
                    return Err("count is 1 to 50.".to_string());
                }
                let count = count as usize;
                self.change(if shots.len() * count == 1 { "Copy shot" } else { "Copy shots" }, move |doc| {
                    let mut originals = Vec::new();
                    for said in shots.iter().filter(|s| !s.trim().is_empty()) {
                        originals.push(tools::find_placement(doc, said).ok_or(format!("There is no shot {} in this project.", said.trim()))?);
                    }
                    let mut made = Vec::new();
                    if into.trim().is_empty() {
                        for original in &originals {
                            let mut last = *original;
                            for _ in 0..count {
                                let Some((_, copy)) = doc.duplicate_shot(last) else { continue };
                                made.push(copy);
                                last = copy;
                            }
                        }
                    } else {
                        let scene = tools::find_scene(doc, &into).ok_or(format!("There is no scene {into} in this project."))?;
                        let mut at = if after.trim().is_empty() {
                            None
                        } else {
                            let p = tools::find_placement(doc, &after).ok_or(format!("There is no shot {after} in this project."))?;
                            if scene_of(doc, p) != Some(scene) {
                                return Err(format!("{after} is not in scene {into}."));
                            }
                            Some(p)
                        };
                        for _ in 0..count {
                            let landed = doc.duplicate_shots_into(&originals, scene, at);
                            at = landed.last().copied().or(at);
                            made.extend(landed);
                        }
                    }
                    let names: Vec<String> = made.iter().filter_map(|p| doc.display_number(*p)).collect();
                    Ok(format!("Made {}.", names.join(", ")))
                })
            })(),
            "cameras" => self.films.doc().map(|doc| {
                Json::Array(
                    tools::cameras_in_order(doc)
                        .into_iter()
                        .map(|unit| {
                            let text = |field: &str| doc.get(unit).and_then(|r| r.text(field)).unwrap_or_default().to_string();
                            let mut one = vec![
                                ("name", Json::text(text(f::LABEL))),
                                ("body", Json::text(text(f::BODY))),
                                ("colour", Json::text(text(f::COLOUR))),
                                (
                                    "sensor",
                                    doc.unit_sensor(unit)
                                        .map(|(name, w, h)| Json::object(vec![("name", Json::text(name)), ("w", Json::Number(w)), ("h", Json::Number(h))]))
                                        .unwrap_or(Json::Null),
                                ),
                            ];
                            // Off the spec sheet's sensor mode (piece E), never typed.
                            if doc.sensor_from_sheet(unit) {
                                one.push(("sensor_from_sheet", Json::Bool(true)));
                            }
                            one.push(("shots", Json::Number(doc.shots_with_unit(unit).len() as f64)));
                            Json::object(one)
                        })
                        .collect(),
                )
                .encode()
            }),
            "add_camera" => (|| {
                let label = arguments.str_field("name").trim().to_string();
                if label.is_empty() {
                    return Err("A camera needs a name.".to_string());
                }
                let body = arguments.str_field("body").trim().to_string();
                let colour = tools::colour_named(&arguments.str_field("colour"))?;
                let sensor_name = arguments.str_field("sensor_name").trim().to_string();
                let sensor_w = tools::number_arg(arguments, "sensor_w");
                let sensor_h = tools::number_arg(arguments, "sensor_h").unwrap_or(0.0);
                self.change("Add camera", move |doc| {
                    if tools::find_camera(doc, &label).is_some() {
                        return Err(format!("There is already a camera called {label}."));
                    }
                    let colour = if colour.is_empty() {
                        tools::SHOT_COLOURS[tools::cameras_in_order(doc).len() % tools::SHOT_COLOURS.len()].1.to_string()
                    } else {
                        colour
                    };
                    let unit = doc.create_unit_coloured(&label, &body, &colour);
                    if let Some(w) = sensor_w {
                        doc.set_unit_sensor(unit, &sensor_name, w, sensor_h);
                    }
                    Ok(format!("Added {}.", tools::camera_named(doc, unit)))
                })
            })(),
            "update_camera" => (|| {
                let wanted = arguments.str_field("camera");
                let label = arguments.get("name").and_then(|v| v.as_str()).map(|s| s.trim().to_string());
                let body = arguments.get("body").and_then(|v| v.as_str()).map(|s| s.trim().to_string());
                let colour = match arguments.get("colour").and_then(|v| v.as_str()) {
                    Some(said) => Some(tools::colour_named(said)?),
                    None => None,
                };
                let sensor_name = arguments.str_field("sensor_name").trim().to_string();
                let sensor_w = tools::number_arg(arguments, "sensor_w");
                let sensor_h = tools::number_arg(arguments, "sensor_h").unwrap_or(0.0);
                if label.is_none() && body.is_none() && colour.is_none() && sensor_w.is_none() {
                    return Err("Say what to change: name, body, colour or sensor_w.".to_string());
                }
                self.change("Change camera", move |doc| {
                    let unit = tools::find_camera(doc, &wanted).ok_or_else(|| no_camera(doc, &wanted))?;
                    if let Some(label) = &label {
                        if !doc.rename_unit(unit, label) {
                            return Err("A camera needs a name.".to_string());
                        }
                    }
                    if let Some(body) = &body {
                        doc.set(unit, f::BODY, body.as_str());
                    }
                    if let Some(colour) = &colour {
                        doc.recolour_unit(unit, colour);
                    }
                    if let Some(w) = sensor_w {
                        if doc.sensor_from_sheet(unit) {
                            return Err("This camera's sensor comes from the spec sheet's sensor mode. Change it there.".to_string());
                        }
                        doc.set_unit_sensor(unit, &sensor_name, w, sensor_h);
                    }
                    Ok(format!("It is {} now.", tools::camera_named(doc, unit)))
                })
            })(),
            "delete_camera" => {
                let wanted = arguments.str_field("camera");
                let anyway = tools::bool_arg(arguments, "even_if_used").unwrap_or(false);
                self.change("Remove camera", move |doc| {
                    let unit = tools::find_camera(doc, &wanted).ok_or_else(|| no_camera(doc, &wanted))?;
                    let named = tools::camera_named(doc, unit);
                    let used = doc.shots_with_unit(unit).len();
                    if used > 0 && !anyway {
                        return Err(format!(
                            "{} name {named}. Nothing was removed. They would keep everything else — ask him, then call again with even_if_used=true.",
                            plural(used, "shot")
                        ));
                    }
                    doc.delete_unit(unit);
                    Ok(format!("Removed {named}."))
                })
            }
            "columns" => self.films.doc().map(|doc| columns(doc).encode()),
            "add_column" => (|| {
                let label = arguments.str_field("name").trim().to_string();
                if label.is_empty() {
                    return Err("A column needs a name.".to_string());
                }
                let kind = column_kind(&arguments.str_field("kind"))?;
                self.change("Add column", move |doc| {
                    if find_column(doc, &label).is_ok() {
                        return Err(format!("There is already a column called {label}."));
                    }
                    doc.add_column(&label, kind).ok_or("That column could not be made.".to_string())?;
                    Ok(format!("Added the {label} column ({kind})."))
                })
            })(),
            "update_column" => (|| {
                let wanted = arguments.str_field("column");
                let label = arguments.get("name").and_then(|v| v.as_str()).map(|s| s.trim().to_string());
                let visible = tools::bool_arg(arguments, "visible");
                let position = position_arg(arguments)?;
                if label.is_none() && visible.is_none() && position.is_none() {
                    return Err("Say what to change: name, visible or position.".to_string());
                }
                self.change("Change column", move |doc| {
                    let field = find_column(doc, &wanted)?;
                    if let Some(label) = &label {
                        if !doc.custom_columns().iter().any(|c| c.field == field) {
                            return Err(format!("{} is a built-in column and keeps its name.", column_label(doc, &field)));
                        }
                        if label.is_empty() {
                            return Err("A column needs a name.".to_string());
                        }
                        doc.rename_column(&field, label);
                    }
                    if let Some(on) = visible {
                        doc.set_column_visible(&field, on);
                    }
                    if let Some(at) = position {
                        let mut order: Vec<String> = doc.column_order().into_iter().filter(|c| *c != field).collect();
                        order.insert(at.min(order.len()), field.clone());
                        let refs: Vec<&str> = order.iter().map(|s| s.as_str()).collect();
                        doc.set_column_order(&refs);
                    }
                    let shown: Vec<String> = doc.visible_columns().iter().map(|c| column_label(doc, c)).collect();
                    Ok(format!("The table shows: {}.", shown.join(", ")))
                })
            })(),
            "delete_column" => {
                let wanted = arguments.str_field("column");
                let anyway = tools::bool_arg(arguments, "even_with_values").unwrap_or(false);
                self.change("Delete column", move |doc| {
                    let field = find_column(doc, &wanted)?;
                    let label = column_label(doc, &field);
                    if !doc.custom_columns().iter().any(|c| c.field == field) {
                        return Err(format!("{label} is a built-in column and cannot be deleted — update_column visible=false hides it."));
                    }
                    let held = doc.shots_with_value(&field);
                    if held > 0 && !anyway {
                        return Err(format!(
                            "{} have something in {label}. Nothing was removed. Deleting it takes what is written there too — ask him, then call again with even_with_values=true.",
                            plural(held, "shot")
                        ));
                    }
                    doc.delete_column(&field);
                    Ok(format!("Removed the {label} column."))
                })
            }
            _ => return None,
        })
    }
}

fn no_camera(doc: &Doc, said: &str) -> String {
    let all: Vec<String> = tools::cameras_in_order(doc).into_iter().map(|u| tools::camera_named(doc, u)).collect();
    if all.is_empty() {
        format!("There is no camera {}. This project has none yet — add_camera makes one.", said.trim())
    } else {
        format!("There is no camera {}. The cameras are {}.", said.trim(), all.join(", "))
    }
}
