//! **Edit Reference, the first mod** (2026-10-17): a clip, stills or an
//! animatic joined to a run of shots, drawn as a gold bracket in the shot list
//! while the project has the mod on (the `mods` tool switches it). The clip
//! itself is brought in on the Mac (Add Edit Reference…); everything else —
//! which shots, where each starts, its name and link — works through either
//! door.

use shotlister_engine::{Doc, Id};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "edit_references",
        description: "The project's edit references (the Edit Reference mod): each with its shots in cut order and where each starts in the clip (seconds), its length, link and clip or stills. Shown in the shot list only while the project has the mod on (`mods`).",
        arguments: &[],
    },
    Tool {
        name: "add_edit_reference",
        description: "Join a run of shots to an edit reference: `shots` in cut order (34A, 34B…), a `name`, and a `link` when the cut lives elsewhere. A new clip or stills file is brought in on the Mac (right-click the shots ▸ Add Edit Reference…, or `attach` with `edit_reference` on the Mac's connector); one the project already holds is hung on it with copy_attachment `to_edit_reference`. Its clip and stills are listed with attachments `edit_reference`.",
        arguments: &[("name", "string", true), ("shots", "array", true), ("link", "string", false)],
    },
    Tool {
        name: "update_edit_reference",
        description: "Change an edit reference (`edit_reference`: its name): `name` renames it, `shots` replaces its shots in cut order, `starts` sets where each shot starts in the clip in seconds (one per shot, never going back), `link` sets or clears (\"\") its link.",
        arguments: &[
            ("edit_reference", "string", true),
            ("name", "string", false),
            ("shots", "array", false),
            ("starts", "array", false),
            ("link", "string", false),
        ],
    },
    Tool {
        name: "delete_edit_reference",
        description: "Take an edit reference away. Its shots stay; its clip goes unless something else holds it. Ask him first.",
        arguments: &[("edit_reference", "string", true)],
    },
];

pub(super) fn find(doc: &Doc, said: &str) -> Result<Id, String> {
    let said = said.trim();
    if let Some(id) = Id::from_hex(said) {
        if doc.is_edit_ref(id) {
            return Ok(id);
        }
    }
    let all = doc.edit_refs_in_order();
    all.iter()
        .copied()
        .find(|e| doc.edit_ref(*e).map(|r| r.name.eq_ignore_ascii_case(said)) == Some(true))
        .ok_or_else(|| {
            let names: Vec<String> = all.iter().filter_map(|e| doc.edit_ref(*e)).map(|r| r.name).collect();
            if names.is_empty() {
                format!("There is no edit reference {said}. This project has none yet.")
            } else {
                format!("There is no edit reference {said}. They are {}.", names.join(", "))
            }
        })
}

fn shots(doc: &Doc, said: &[String]) -> Result<Vec<Id>, String> {
    let mut out = Vec::new();
    for one in said.iter().map(|s| s.trim()).filter(|s| !s.is_empty()) {
        let placement = tools::find_placement(doc, one).ok_or(format!("There is no shot {one} in this project."))?;
        out.push(tools::shot_of(doc, placement).ok_or(format!("There is no shot {one} in this project."))?);
    }
    if out.is_empty() {
        return Err("Name the shots, in cut order.".to_string());
    }
    Ok(out)
}

fn number(doc: &Doc, shot: Id) -> String {
    doc.placements_of_shot(shot).first().and_then(|p| doc.display_number(*p)).unwrap_or_default()
}

fn said(doc: &Doc, e: Id) -> String {
    let Some(r) = doc.edit_ref(e) else { return String::new() };
    let run: Vec<String> = r.shots.iter().map(|s| number(doc, *s)).collect();
    format!("{} joins {}.", r.name, run.join(", "))
}

impl<F: Films> Server<F> {
    pub(super) fn editref_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "edit_references" => self.films.doc().map(|doc| {
                Json::Array(
                    doc.edit_refs_in_order()
                        .into_iter()
                        .filter_map(|e| doc.edit_ref(e))
                        .map(|r| {
                            Json::object(vec![
                                ("name", Json::text(r.name.clone())),
                                (
                                    "shots",
                                    Json::Array(
                                        r.shots
                                            .iter()
                                            .zip(r.starts.iter())
                                            .map(|(s, at)| Json::object(vec![("shot", Json::text(number(doc, *s))), ("start", Json::Number(*at))]))
                                            .collect(),
                                    ),
                                ),
                                ("length", Json::Number(r.length)),
                                ("link", Json::text(r.link.clone())),
                                ("media", Json::Array(r.media.iter().map(|m| Json::text(doc.media_ref_name(*m))).collect())),
                            ])
                        })
                        .collect(),
                )
                .encode()
            }),
            "add_edit_reference" => {
                let label = arguments.str_field("name").trim().to_string();
                let list = tools::list_arg(arguments, "shots").unwrap_or_default();
                let link = arguments.str_field("link");
                self.change("Add Edit Reference", move |doc| {
                    let run = shots(doc, &list)?;
                    let e = doc.create_edit_ref(&label, &run);
                    if !link.trim().is_empty() {
                        doc.set_edit_ref_link(e, &link);
                    }
                    Ok(format!("Added. {}", said(doc, e)))
                })
            }
            "update_edit_reference" => {
                let wanted = arguments.str_field("edit_reference");
                let arguments = arguments.clone();
                self.change("Change Edit Reference", move |doc| {
                    let e = find(doc, &wanted)?;
                    let mut touched = false;
                    if let Some(label) = arguments.get("name").and_then(|v| v.as_str()).map(str::trim) {
                        if label.is_empty() {
                            return Err("An edit reference needs a name.".to_string());
                        }
                        doc.rename_edit_ref(e, label);
                        touched = true;
                    }
                    if let Some(list) = tools::list_arg(&arguments, "shots") {
                        let run = shots(doc, &list)?;
                        doc.set_edit_ref_shots(e, &run);
                        touched = true;
                    }
                    if let Some(list) = arguments.get("starts").and_then(|v| v.as_array()) {
                        let starts: Vec<f64> = list.iter().filter_map(|v| v.as_f64()).collect();
                        if !doc.set_edit_ref_starts(e, &starts) {
                            return Err("One start for each shot, in seconds, never going back.".to_string());
                        }
                        touched = true;
                    }
                    if let Some(link) = arguments.get("link").and_then(|v| v.as_str()) {
                        doc.set_edit_ref_link(e, link);
                        touched = true;
                    }
                    if !touched {
                        return Err("Say what to change: name, shots, starts or link.".to_string());
                    }
                    Ok(said(doc, e))
                })
            }
            "delete_edit_reference" => {
                let wanted = arguments.str_field("edit_reference");
                self.change("Delete Edit Reference", move |doc| {
                    let e = find(doc, &wanted)?;
                    let name = doc.edit_ref(e).map(|r| r.name).unwrap_or_default();
                    doc.delete_edit_ref(e);
                    Ok(format!("Deleted {name}. Its shots stay."))
                })
            }
            _ => return None,
        })
    }
}
