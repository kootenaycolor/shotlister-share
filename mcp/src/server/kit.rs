//! **The kit** (Ref 1627): the film's Camera Spec Sheets as what its shots
//! pick from, and the shots that use something the sheets lack. The film half
//! — the sheets themselves live in Notion and are read and changed on the
//! portal (`hub/src/kittools.js`: `spec_sheet`, `set_spec_sheet`,
//! `add_to_spec_sheet`). See `shotlister_engine::kit`.

use shotlister_engine::kit::{self, KitShoot};
use shotlister_engine::Doc;

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "kit",
        description: "The project's kit: each shoot's Camera Spec Sheet as the lenses, cameras, modifiers and filters its shots pick from (as last taken from the portal), and every shot whose lens, camera's body, modifiers or filters are not on the sheet of the shoot its day falls in (the whole project's sheets when its day is in no shoot). `off_kit` names the sheet add_to_spec_sheet would put it on. Nothing is added by reading. `shoot` (its name, or 2 for Shoot 2) narrows it to one shoot when the project shoots more than once; with one shoot it is ignored. One shoot's is its own sheet and its shots off it.",
        arguments: &[("shoot", "string", false)],
    },
    Tool {
        name: "take_kit",
        description: "Take the spec sheets' kit into the project, as the Mac does on its own: each shoot's lenses go on the Lens list (named as the sheet names them, \"Master Prime 25mm\"; a shot's typed \"25mm\" still matches) and its cameras get their bodies (\"A Cam: Alexa 35\" → A-Cam, made if missing). Modifiers and filters go on the Modifiers and Filters lists by the sheet's name. A lens, modifier or filter taken off the sheet since last time comes off its list when no shot uses it; a name glued from a whole box (\"A, B, C\") is split. Cameras are never removed, a locked list is not grown, and it leaves no undo step. On the portal leave `kit` out: it is read from the project's spec sheets. Elsewhere `kit` is a list of shoots: {name, start, end, sheet, lead, cameras: [{label, body}], lenses: [\"Master Prime 25mm\", …], modifiers: [\"Atlas LF Extender 1.6x\"], filters: [\"Tiffen ND .6\", …]}. The project's Spec Sheet switch (spec_sheet_switch) does not stop this: he asked for it.",
        arguments: &[("kit", "array", false)],
    },
    Tool {
        name: "spec_sheet_switch",
        description: "The project's Spec Sheet switch, as in Project Settings › Spec Sheet: `off` (nothing flows between the Notion spec sheet and the project, and no shot offers Add to Spec Sheet), `ask` (Shotlister says what changed on the sheet and he takes it with a click) or `follow` (the project takes the sheet on open and every few minutes). Every film is Off until he turns it on. Leave `mode` out to read it.",
        arguments: &[("mode", "string", false)],
    },
];

fn shoot_said(s: &KitShoot) -> Json {
    Json::object(vec![
        ("shoot", Json::text(if s.name.is_empty() { "The project's" } else { s.name.as_str() })),
        ("dates", Json::text(if s.end.is_empty() || s.end == s.start { s.start.clone() } else { format!("{} to {}", s.start, s.end) })),
        ("lead", Json::Bool(s.lead)),
        ("lenses", Json::Array(s.lenses.iter().map(Json::text).collect())),
        ("modifiers", Json::Array(s.modifiers.iter().map(Json::text).collect())),
        ("filters", Json::Array(s.filters.iter().map(Json::text).collect())),
        (
            "cameras",
            Json::Array(
                s.cameras
                    .iter()
                    .map(|c| Json::text(if c.label.is_empty() { c.body.clone() } else { format!("{}: {}", c.label, c.body) }))
                    .collect(),
            ),
        ),
    ])
}

fn kit_said(doc: &Doc, pick: Option<&super::shootpick::ShootPick>) -> Json {
    let kit = doc.kit();
    let mut off = Vec::new();
    for scene in doc.scenes_in_order() {
        for placement in doc.placements_in_scene(scene) {
            if pick.map(|k| !k.placements.contains(&placement)).unwrap_or(false) {
                continue;
            }
            let Some(o) = doc.off_kit(&kit, placement) else { continue };
            let mut pairs = vec![
                ("shot", Json::text(doc.display_number(placement).unwrap_or_default())),
                ("sheet", Json::text(kit.get(o.shoot).map(|s| if s.name.is_empty() { "The project's" } else { s.name.as_str() }).unwrap_or(""))),
            ];
            if let Some(lens) = &o.lens {
                pairs.push(("lens", Json::text(lens)));
            }
            if let Some((label, body)) = &o.camera {
                pairs.push(("camera", Json::text(format!("{label} {body}").trim().to_string())));
            }
            if !o.modifiers.is_empty() {
                pairs.push(("modifiers", Json::Array(o.modifiers.iter().map(Json::text).collect())));
            }
            if !o.filters.is_empty() {
                pairs.push(("filters", Json::Array(o.filters.iter().map(Json::text).collect())));
            }
            off.push(Json::object(pairs));
        }
    }
    Json::object(vec![
        ("switch", Json::text(doc.kit_mode().as_str())),
        // One shoot's sheet when one is asked and the kit has it by name; else every sheet.
        ("shoots", Json::Array({
            let mine: Vec<_> = kit.iter().filter(|s| pick.map(|k| super::shootpick::same_shoot(&s.name, &k.key)).unwrap_or(true)).collect();
            if mine.is_empty() { kit.iter().map(shoot_said).collect() } else { mine.into_iter().map(shoot_said).collect() }
        })),
        ("off_kit", Json::Array(off)),
        ("lens_list", Json::Array(doc.vocabulary("lens").iter().map(Json::text).collect())),
        ("modifier_list", Json::Array(doc.vocabulary("modifiers").iter().map(Json::text).collect())),
        ("filter_list", Json::Array(doc.vocabulary("lens_filters").iter().map(Json::text).collect())),
    ])
}

impl<F: Films> Server<F> {
    pub(super) fn kit_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "kit" => self.films.doc().map(|doc| {
                if doc.kit().is_empty() {
                    return "This project has no spec sheet yet: no kit has been taken. On the portal, spec_sheet reads its sheets and take_kit brings them in.".to_string();
                }
                match super::shootpick::pick(doc, arguments) {
                    Ok(pick) => kit_said(doc, pick.as_ref()).encode(),
                    Err(why) => why,
                }
            }),
            "take_kit" => (|| {
                let Some(given) = arguments.get("kit") else {
                    return Err("Say the kit: a list of shoots, each {name, lenses, cameras}. On the portal it is read from the spec sheets.".to_string());
                };
                let said = given.encode();
                kit::parse(&said)?;
                self.change("Take kit", move |doc| {
                    let taken = doc.take_kit(&said)?;
                    let mut out = Vec::new();
                    if !taken.lenses_added.is_empty() {
                        out.push(format!("Lens list: {} added", taken.lenses_added.join(", ")));
                    }
                    if !taken.lens_list_locked.is_empty() {
                        out.push(format!(
                            "The Lens list is locked, so {} stayed off it",
                            taken.lens_list_locked.join(", ")
                        ));
                    }
                    for (added, locked, list) in [
                        (&taken.modifiers_added, &taken.modifier_list_locked, "Modifiers"),
                        (&taken.filters_added, &taken.filter_list_locked, "Filters"),
                    ] {
                        if !added.is_empty() {
                            out.push(format!("{list} list: {} added", added.join(", ")));
                        }
                        if !locked.is_empty() {
                            out.push(format!("The {list} list is locked, so {} stayed off it", locked.join(", ")));
                        }
                    }
                    if !taken.camera_list_locked.is_empty() {
                        out.push(format!(
                            "The Camera list is locked, so {} stayed off it",
                            taken.camera_list_locked.join(", ")
                        ));
                    }
                    if !taken.cameras_made.is_empty() {
                        out.push(format!("Cameras made: {}", taken.cameras_made.join(", ")));
                    }
                    if !taken.bodies_set.is_empty() {
                        out.push(format!("Bodies: {}", taken.bodies_set.join(", ")));
                    }
                    if out.is_empty() {
                        out.push(if taken.kit_changed { "The kit is taken; the lists already held it".into() } else { "The film already has this kit".into() });
                    }
                    Ok(format!("{}.", out.join(". ")))
                })
            })(),
            "spec_sheet_switch" => {
                let said = arguments.str_field("mode").trim().to_ascii_lowercase();
                if said.is_empty() {
                    return Some(self.films.doc().map(|doc| format!("The Spec Sheet switch is {}.", title(doc.kit_mode().as_str()))));
                }
                if !["off", "ask", "follow"].contains(&said.as_str()) {
                    return Some(Err("The Spec Sheet switch is off, ask or follow.".to_string()));
                }
                self.change("Set spec sheet switch", move |doc| {
                    if doc.project_id().is_none() {
                        return Err("This project has no record, so it has no spec sheet to follow.".to_string());
                    }
                    doc.set_kit_mode(kit::KitMode::read(&said));
                    Ok(format!("The Spec Sheet switch is {} now.", title(&said)))
                })
            }
            _ => return None,
        })
    }
}

/// "ask" → "Ask".
fn title(said: &str) -> String {
    let mut c = said.chars();
    c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
}
