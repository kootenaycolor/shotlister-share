//! Versions: the whole project at a moment, kept so it can be gone back to.
//!
//! The Mac's File → Save Version and Versions window. On the web connector,
//! which has no undo, this is also the way back from a change that should
//! not have been made.

use shotlister_engine::versions::{Made, Version};
use shotlister_engine::{Doc, Id};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "versions",
        description: "The project's saved versions, newest first — the whole project at a moment. Each with its name, when it was saved, and why: by hand, the day's first, before a script draft, or before going back. Give `version` (a name, a day like 2026-09-29, or latest) to hear what has changed since it.",
        arguments: &[("version", "string", false)],
    },
    Tool {
        name: "save_version",
        description: "Save a version of the whole project as it stands now, under a name — before a big restructure, say. It costs almost nothing: it marks a moment in the project's history, it copies nothing.",
        arguments: &[("name", "string", true)],
    },
    Tool {
        name: "bring_back",
        description: "Bring some things back as they were in a version — scenes, shots, reference boards or locations, named as they were then — each with what belongs to it (a scene's shots, pictures and diagram; a shot's frames). Brings back what was deleted, and undoes changes to just those things. Nothing else is touched.",
        arguments: &[
            ("version", "string", true),
            ("scenes", "array", false),
            ("shots", "array", false),
            ("boards", "array", false),
            ("locations", "array", false),
        ],
    },
    Tool {
        name: "go_back_to_version",
        description: "Put the whole project back as it was at a version. A version of now is saved first, so today is one step away too. It changes everything made since, so it is refused — saying what would change — unless `sure` is true. Ask him first.",
        arguments: &[("version", "string", true), ("sure", "boolean", false)],
    },
    Tool {
        name: "rename_version",
        description: "Rename a saved version, as Rename… on a version in the Versions list does (Mac and iPhone). `version` as `versions` names it (its name, a day, or latest); `name` the new name.",
        arguments: &[("version", "string", true), ("name", "string", true)],
    },
    Tool {
        name: "delete_version",
        description: "Delete a saved version, as Delete… in the Versions list does: only the bookmark goes — the project's history is untouched and nothing it pointed at is lost; pictures only it was holding may then be tidied away. Ask him first, naming it.",
        arguments: &[("version", "string", true)],
    },
];

fn made_said(made: Made) -> &'static str {
    match made {
        Made::Hand => "saved by hand",
        Made::Daily => "the day's first",
        Made::Draft => "before a script draft",
        Made::GoingBack => "before going back",
    }
}

fn named(v: &Version) -> String {
    if v.name.trim().is_empty() {
        format!("{} ({})", v.day, made_said(v.made))
    } else {
        format!("\u{201c}{}\u{201d}", v.name.trim())
    }
}

/// A version by its name, a day (the newest saved that day), `latest`, or an id.
fn find_version(doc: &Doc, said: &str) -> Result<Version, String> {
    let said = said.trim();
    let all = doc.versions();
    if let Some(id) = Id::from_hex(said) {
        if let Some(v) = doc.version(id) {
            return Ok(v);
        }
    }
    let newest_first = |mut vs: Vec<Version>| {
        vs.sort_by(|a, b| b.taken.cmp(&a.taken));
        vs
    };
    let all = newest_first(all);
    if said.eq_ignore_ascii_case("latest") {
        return all.into_iter().next().ok_or("This project has no versions yet — save_version makes one.".to_string());
    }
    if let Some(v) = all.iter().find(|v| v.name.trim().eq_ignore_ascii_case(said)) {
        return Ok(v.clone());
    }
    if let Some(v) = all.iter().find(|v| v.day == said) {
        return Ok(v.clone());
    }
    Err(if all.is_empty() {
        "This project has no versions yet — save_version makes one.".to_string()
    } else {
        format!(
            "There is no version {said}. The newest are {}.",
            all.iter().take(8).map(named).collect::<Vec<_>>().join("; ")
        )
    })
}

fn since_said(doc: &Doc, v: &Version) -> String {
    match doc.since(v.id) {
        Some(since) if !since.is_empty() => since.words().join(", "),
        _ => "nothing".to_string(),
    }
}

impl<F: Films> Server<F> {
    pub(super) fn version_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "versions" => (|| {
                let doc = self.films.doc()?;
                let wanted = arguments.str_field("version");
                if !wanted.trim().is_empty() {
                    let v = find_version(doc, &wanted)?;
                    return Ok(format!("Since {}: {}.", named(&v), since_said(doc, &v)));
                }
                let mut all = doc.versions();
                all.sort_by(|a, b| b.taken.cmp(&a.taken));
                Ok(Json::Array(
                    all.iter()
                        .map(|v| {
                            Json::object(vec![
                                ("name", Json::text(v.name.clone())),
                                ("day", Json::text(v.day.clone())),
                                ("saved", Json::text(tools::iso_at_millis(v.taken))),
                                ("why", Json::text(made_said(v.made))),
                            ])
                        })
                        .collect(),
                )
                .encode())
            })(),
            "rename_version" => {
                let wanted = arguments.str_field("version");
                let label = arguments.str_field("name").trim().to_string();
                if label.is_empty() {
                    return Some(Err("Say its new name.".to_string()));
                }
                self.change("Rename Version", move |doc| {
                    let v = find_version(doc, &wanted)?;
                    let was = named(&v);
                    if !doc.rename_version(v.id, &label) {
                        return Err(format!("{was} could not be renamed."));
                    }
                    Ok(format!("{was} is now \u{201c}{label}\u{201d}."))
                })
            }
            "delete_version" => {
                let wanted = arguments.str_field("version");
                self.change("Delete Version", move |doc| {
                    let v = find_version(doc, &wanted)?;
                    let was = named(&v);
                    if !doc.delete_version(v.id) {
                        return Err(format!("{was} could not be deleted."));
                    }
                    Ok(format!("Deleted the version {was}. The project itself is unchanged."))
                })
            }
            "save_version" => {
                let label = arguments.str_field("name").trim().to_string();
                if label.is_empty() {
                    return Some(Err("A version needs a name.".to_string()));
                }
                self.change("Save Version", move |doc| {
                    doc.save_version(&label);
                    Ok(format!("Saved the project as it stands as \u{201c}{label}\u{201d}."))
                })
            }
            "bring_back" => {
                let wanted = arguments.str_field("version");
                let arguments = arguments.clone();
                self.change("Bring Back", move |doc| {
                    let v = find_version(doc, &wanted)?;
                    let then = doc.as_of(v.id).ok_or("That version could not be read.")?;
                    let mut roots = Vec::new();
                    let mut names = Vec::new();
                    for said in tools::list_arg(&arguments, "scenes").unwrap_or_default().iter().filter(|s| !s.trim().is_empty()) {
                        roots.push(tools::find_scene(&then, said).ok_or(format!("{} had no scene {}.", named(&v), said.trim()))?);
                        names.push(format!("scene {}", said.trim()));
                    }
                    for said in tools::list_arg(&arguments, "shots").unwrap_or_default().iter().filter(|s| !s.trim().is_empty()) {
                        let placement = tools::find_placement(&then, said).ok_or(format!("{} had no shot {}.", named(&v), said.trim()))?;
                        roots.push(tools::shot_of(&then, placement).ok_or(format!("{} had no shot {}.", named(&v), said.trim()))?);
                        names.push(format!("shot {}", said.trim()));
                    }
                    for said in tools::list_arg(&arguments, "boards").unwrap_or_default().iter().filter(|s| !s.trim().is_empty()) {
                        roots.push(then.board_named(said.trim()).ok_or(format!("{} had no board {}.", named(&v), said.trim()))?);
                        names.push(format!("the {} board", said.trim()));
                    }
                    for said in tools::list_arg(&arguments, "locations").unwrap_or_default().iter().filter(|s| !s.trim().is_empty()) {
                        roots.push(super::places::find_location(&then, said)?);
                        names.push(said.trim().to_string());
                    }
                    if roots.is_empty() {
                        return Err("Say what to bring back: scenes, shots, boards or locations.".to_string());
                    }
                    let brought = doc.bring_back(v.id, &roots).ok_or("That version could not be read.")?;
                    Ok(if brought.fields == 0 && brought.records == 0 {
                        format!("{} {} already as {} had it.", names.join(", "), if names.len() == 1 { "is" } else { "are" }, named(&v))
                    } else {
                        format!("Brought back {} as {} had it.", names.join(", "), named(&v))
                    })
                })
            }
            "go_back_to_version" => {
                let wanted = arguments.str_field("version");
                let sure = tools::bool_arg(arguments, "sure").unwrap_or(false);
                self.change("Go Back", move |doc| {
                    let v = find_version(doc, &wanted)?;
                    let changes = since_said(doc, &v);
                    if !sure {
                        return Err(format!(
                            "Nothing was changed. Going back to {} undoes everything since: {changes}. A version of now is saved first. Ask him, then call again with sure=true.",
                            named(&v)
                        ));
                    }
                    doc.go_back_to(v.id).ok_or("That version could not be read.")?;
                    Ok(format!("The film is as it was at {}. What it was a moment ago is saved as a version (before going back).", named(&v)))
                })
            }
            _ => return None,
        })
    }
}
