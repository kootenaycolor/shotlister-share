//! Locations: the places the crew actually goes, and the rooms inside them.
//!
//! Not the script's word for where a scene happens — that is the scene's
//! `location` text and belongs to the script. These are the records the
//! Locations mode keeps: an address, a pin, notes on getting in, photographs,
//! and which scenes are shot there. One level of nesting, never more, exactly
//! as the engine enforces it.

use shotlister_engine::{f, Doc, Id};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "locations",
        description: "The project's locations — the places the crew goes, not the script's words for where a scene happens. Each with its address, pin (latitude, longitude), notes, how many photographs, the scenes shot there, and the rooms inside it (a room with no address of its own uses the house's). `shoot` (its name, or 2 for Shoot 2) narrows it to one shoot when the project shoots more than once; with one shoot it is ignored. One shoot's are the locations its scenes are shot at.",
        arguments: &[("shoot", "string", false)],
    },
    Tool {
        name: "add_location",
        description: "Add a location. `inside` makes it a room of another (one level only: a room of a room lands beside it). `address`, `notes`, `latitude` and `longitude` are optional.",
        arguments: &[
            ("name", "string", true),
            ("inside", "string", false),
            ("address", "string", false),
            ("notes", "string", false),
            ("latitude", "string", false),
            ("longitude", "string", false),
        ],
    },
    Tool {
        name: "update_location",
        description: "Change a location, named as it reads (`Hillcrest House`, or `Hillcrest House — Kitchen` for a room). Only the fields given change; \"\" clears one. `inside` moves it into another location, \"\" makes it stand on its own. `sync_with_drive` says whether its photographs go to Google Drive. `tags` (comma-separated, the one tag list shots and scenes share) replaces its tags.",
        arguments: &[
            ("location", "string", true),
            ("name", "string", false),
            ("inside", "string", false),
            ("address", "string", false),
            ("notes", "string", false),
            ("latitude", "string", false),
            ("longitude", "string", false),
            ("sync_with_drive", "boolean", false),
            ("tags", "string", false),
        ],
    },
    Tool {
        name: "delete_location",
        description: "Take a location away. Scenes shot there lose the link and nothing else; its rooms stay and stand on their own; its photographs go unless something else holds them. One with scenes, rooms or photographs is refused, saying what hangs on it, unless `even_if_used` is true — ask him first.",
        arguments: &[("location", "string", true), ("even_if_used", "boolean", false)],
    },
    Tool {
        name: "set_scene_locations",
        description: "Say which locations a scene is shot at — the Locations mode's link, separate from the script's own words in the heading. `locations` replaces the scene's list (first is its main one); [] clears it. `add` or `remove` change one without touching the rest.",
        arguments: &[
            ("scene", "string", true),
            ("locations", "array", false),
            ("add", "string", false),
            ("remove", "string", false),
        ],
    },
];

/// A location by its full name, its own name, or an id.
pub(super) fn find_location(doc: &Doc, said: &str) -> Result<Id, String> {
    let said = said.trim();
    if let Some(id) = Id::from_hex(said) {
        if doc.get(id).is_some() {
            return Ok(id);
        }
    }
    let all = doc.locations_in_order();
    let squash = |s: &str| s.to_lowercase().replace(['—', '–'], "-").split_whitespace().collect::<Vec<_>>().join(" ");
    let wanted = squash(said);
    if let Some(place) = all.iter().find(|p| squash(&doc.location_full_name(**p)) == wanted) {
        return Ok(*place);
    }
    let own: Vec<Id> = all
        .iter()
        .copied()
        .filter(|p| doc.get(*p).and_then(|r| r.text(f::LABEL)).map(squash) == Some(wanted.clone()))
        .collect();
    match own.len() {
        1 => Ok(own[0]),
        0 => Err(if all.is_empty() {
            "This project has no locations yet — add_location makes one.".to_string()
        } else {
            format!(
                "There is no location {said}. The locations are {}.",
                all.iter().map(|p| doc.location_full_name(*p)).collect::<Vec<_>>().join("; ")
            )
        }),
        _ => Err(format!(
            "More than one location is called {said}: {}. Say which.",
            own.iter().map(|p| doc.location_full_name(*p)).collect::<Vec<_>>().join("; ")
        )),
    }
}

fn scene_number(doc: &Doc, scene: Id) -> String {
    doc.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or_default().to_string()
}

fn place_json(doc: &Doc, place: Id) -> Json {
    let own = |field: &str| doc.get(place).and_then(|r| r.text(field)).unwrap_or_default().to_string();
    let mut pairs = vec![
        ("name", Json::text(own(f::LABEL))),
        ("address", Json::text(doc.location_address(place))),
        ("notes", Json::text(doc.location_notes(place))),
    ];
    if let Some((lat, lon)) = doc.location_pin(place) {
        pairs.push(("latitude", Json::text(lat)));
        pairs.push(("longitude", Json::text(lon)));
    }
    pairs.push(("photographs", Json::Number(doc.media_refs(place).len() as f64)));
    pairs.push((
        "scenes",
        Json::Array(doc.scenes_at_location(place).into_iter().map(|s| Json::text(scene_number(doc, s))).collect()),
    ));
    if let Some(on) = doc.get(place).and_then(|r| r.get(f::SYNC_WITH_DRIVE).cloned()) {
        let on = on.as_bool().or_else(|| on.as_text().map(|t| t == "1" || t == "true"));
        if let Some(on) = on {
            pairs.push(("sync_with_drive", Json::Bool(on)));
        }
    }
    let tags = shotlister_engine::view::list(doc, place, f::TAGS);
    if !tags.is_empty() {
        pairs.push(("tags", Json::text(tags.join(", "))));
    }
    let rooms = doc.areas_of(place);
    if !rooms.is_empty() {
        pairs.push(("rooms", Json::Array(rooms.into_iter().map(|r| place_json(doc, r)).collect())));
    }
    Json::object(pairs)
}

fn text_arg(arguments: &Json, key: &str) -> Option<String> {
    arguments.get(key).and_then(|v| v.as_str()).map(|s| s.trim().to_string())
}

/// The plain fields a location takes, as the ffi's `setlocation` names them.
const FIELDS: [(&str, &str); 4] = [
    ("address", f::ADDRESS),
    ("notes", f::NOTES),
    ("latitude", f::LATITUDE),
    ("longitude", f::LONGITUDE),
];

impl<F: Films> Server<F> {
    pub(super) fn place_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "locations" => (|| {
                let doc = self.films.doc()?;
                let pick = super::shootpick::pick(doc, arguments)?;
                Ok(Json::Array(
                    doc.top_locations()
                        .into_iter()
                        .filter(|p| match &pick {
                            Some(k) => doc.scenes_at_location_or_inside(*p).iter().any(|s| k.scenes.contains(s)),
                            None => true,
                        })
                        .map(|p| place_json(doc, p))
                        .collect(),
                )
                .encode())
            })(),
            "add_location" => (|| {
                let label = arguments.str_field("name").trim().to_string();
                if label.is_empty() {
                    return Err("A location needs a name.".to_string());
                }
                let inside = arguments.str_field("inside");
                let arguments = arguments.clone();
                self.change("Add location", move |doc| {
                    let place = if inside.trim().is_empty() {
                        doc.create_location(&label)
                    } else {
                        let parent = find_location(doc, &inside)?;
                        doc.create_location_in(parent, &label)
                    };
                    for (key, field) in FIELDS {
                        if let Some(value) = text_arg(&arguments, key) {
                            doc.set(place, field, value.as_str());
                        }
                    }
                    Ok(format!("Added {}.", doc.location_full_name(place)))
                })
            })(),
            "update_location" => {
                let wanted = arguments.str_field("location");
                let arguments = arguments.clone();
                self.change("Change location", move |doc| {
                    let place = find_location(doc, &wanted)?;
                    if let Some(label) = text_arg(&arguments, "name") {
                        if label.is_empty() {
                            return Err("A location needs a name.".to_string());
                        }
                        doc.set(place, f::LABEL, label.as_str());
                    }
                    for (key, field) in FIELDS {
                        if let Some(value) = text_arg(&arguments, key) {
                            doc.set(place, field, value.as_str());
                        }
                    }
                    if let Some(on) = tools::bool_arg(&arguments, "sync_with_drive") {
                        doc.set(place, f::SYNC_WITH_DRIVE, if on { "1" } else { "0" });
                    }
                    if let Some(tags) = arguments.get("tags").and_then(|v| v.as_str()) {
                        let items: Vec<&str> = tags.split(',').map(str::trim).filter(|t| !t.is_empty()).collect();
                        doc.set_vocab_list(place, f::TAGS, &items);
                    }
                    if let Some(inside) = text_arg(&arguments, "inside") {
                        let parent = if inside.is_empty() { None } else { Some(find_location(doc, &inside)?) };
                        if !doc.set_location_parent(place, parent) {
                            return Err(format!(
                                "{} cannot go there: locations nest one level only — a room cannot hold rooms, and a place with rooms cannot become one.",
                                doc.location_full_name(place)
                            ));
                        }
                    }
                    Ok(format!("Changed {}.", doc.location_full_name(place)))
                })
            }
            "delete_location" => {
                let wanted = arguments.str_field("location");
                let anyway = tools::bool_arg(arguments, "even_if_used").unwrap_or(false);
                self.change("Delete location", move |doc| {
                    let place = find_location(doc, &wanted)?;
                    let named = doc.location_full_name(place);
                    let scenes: Vec<String> = doc.scenes_at_location(place).into_iter().map(|s| scene_number(doc, s)).collect();
                    let rooms = doc.areas_of(place).len();
                    let photos = doc.media_refs(place).len();
                    let mut hangs = Vec::new();
                    if !scenes.is_empty() {
                        hangs.push(format!("scene{} {}", if scenes.len() == 1 { "" } else { "s" }, scenes.join(", ")));
                    }
                    if rooms > 0 {
                        hangs.push(format!("{rooms} room{}", if rooms == 1 { "" } else { "s" }));
                    }
                    if photos > 0 {
                        hangs.push(format!("{photos} photograph{}", if photos == 1 { "" } else { "s" }));
                    }
                    if !hangs.is_empty() && !anyway {
                        return Err(format!(
                            "{named} has {} on it. Nothing was removed. Scenes would lose the link, rooms would stand on their own, and its photographs would go — ask him, then call again with even_if_used=true.",
                            hangs.join(", ")
                        ));
                    }
                    doc.delete_location(place);
                    Ok(format!("Removed {named}."))
                })
            }
            "set_scene_locations" => (|| {
                let reference = arguments.str_field("scene");
                let list = tools::list_arg(arguments, "locations");
                let add = arguments.str_field("add");
                let remove = arguments.str_field("remove");
                if list.is_none() && add.trim().is_empty() && remove.trim().is_empty() {
                    return Err("Say locations, add or remove.".to_string());
                }
                self.change("Set location", move |doc| {
                    let scene = tools::find_scene(doc, &reference)
                        .ok_or(format!("There is no scene {reference} in this project."))?;
                    if let Some(list) = &list {
                        let mut places = Vec::new();
                        for said in list.iter().filter(|s| !s.trim().is_empty()) {
                            let place = find_location(doc, said)?;
                            if !places.contains(&place) {
                                places.push(place);
                            }
                        }
                        doc.set_scene_location(scene, places.first().copied());
                        for place in places.iter().skip(1) {
                            doc.add_scene_location(scene, *place);
                        }
                    }
                    if !add.trim().is_empty() {
                        let place = find_location(doc, &add)?;
                        doc.add_scene_location(scene, place);
                    }
                    if !remove.trim().is_empty() {
                        let place = find_location(doc, &remove)?;
                        if !doc.remove_scene_location(scene, place) {
                            return Err(format!("Scene {reference} is not shot at {}.", doc.location_full_name(place)));
                        }
                    }
                    let now: Vec<String> = doc.scene_locations(scene).into_iter().map(|p| doc.location_full_name(p)).collect();
                    Ok(if now.is_empty() {
                        format!("Scene {reference} is at no location.")
                    } else {
                        format!("Scene {reference} is shot at {}.", now.join("; "))
                    })
                })
            })(),
            _ => return None,
        })
    }
}
