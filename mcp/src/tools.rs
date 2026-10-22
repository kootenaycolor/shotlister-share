//! What Claude can do to a project.

use shotlister_engine::doc::f;
use shotlister_engine::docstyle;
use shotlister_engine::export::html::FrameSize;
use shotlister_engine::export::{csv, html, xlsx, Print};
use shotlister_engine::{Doc, GroupBy, Id, Query};


use crate::json::Json;

/// Resolve the way somebody would say it: `34` is a scene, `34A` is a shot, and
/// a raw id still works for anything that has passed through here already.
pub fn find_scene(doc: &Doc, reference: &str) -> Option<Id> {
    let reference = reference.trim();
    if let Some(id) = Id::from_hex(reference) {
        if doc.get(id).is_some() {
            return Some(id);
        }
    }
    doc.scenes_in_order()
        .into_iter()
        .find(|scene| doc.get(*scene).and_then(|r| r.text(f::NUMBER)) == Some(reference))
}

/// Returns the placement — where a shot sits — since that is what a number names.
pub fn find_placement(doc: &Doc, reference: &str) -> Option<Id> {
    let reference = reference.trim();
    if let Some(id) = Id::from_hex(reference) {
        if doc.get(id).is_some() {
            return Some(id);
        }
    }
    doc.all_placements().into_iter().find(|placement| {
        doc.display_number(*placement)
            .map(|number| number.eq_ignore_ascii_case(reference))
            .unwrap_or(false)
    })
}

/// The shot a placement names. A number names where a shot sits, so almost
/// everything arrives as a placement and has to be turned into the shot itself.
pub fn shot_of(doc: &Doc, placement: Id) -> Option<Id> {
    doc.get(placement)?.ref_id(f::SHOT)
}

// ---- describing --------------------------------------------------------

/// What a film is, in one object.
///
/// **Told what it is called and where it lives rather than reading it off a
/// folder**, since 2026-09-01 — a worker has no folder, and the two homes name
/// a film differently: a path on a Mac, an id in the relay's bucket.
pub fn summary(doc: &Doc, title: &str, whereabouts: &str, read_only: bool) -> Json {
    let scenes = doc.scenes_in_order();
    let shots = doc.count(&Query::grouped_by(GroupBy::Flat));
    // **The film's vitals, for whoever is drawing a page about it.**
    //
    // Added 2026-09-01 for the collaborators' portal, whose card has to say
    // "2.39 : 1" and "7 locations" without opening the film a second time
    // somewhere else to find out. The engine knows all of this already; asking
    // once is cheaper and truer than three tools that each replay the same
    // document, and additive, so nothing that reads this reply today notices.
    let project = doc.project_id().and_then(|id| doc.get(id));
    let said = |field: &str| project.and_then(|r| r.text(field)).unwrap_or("").to_string();
    Json::object(vec![
        ("title", Json::text(title)),
        ("path", Json::text(whereabouts)),
        ("kind", Json::text(doc.kind().as_str())),
        ("director", Json::text(doc.fact(f::DIRECTOR))),
        ("producer", Json::text(doc.fact(f::PRODUCER))),
        ("client", Json::text(doc.fact(f::CLIENT))),
        ("agency", Json::text(doc.fact(f::AGENCY))),
        // Where the four names above (and the name the film is shown by)
        // come from: `record` — the project record, changed in Projects
        // Console — or `film`, its own. One-record plan, 2026-10-05.
        ("facts", Json::text(if doc.facts_from_record() || doc.card().is_some() { "record" } else { "film" })),
        ("shown_title", Json::text(doc.shown_title())),
        (
            "ratio",
            Json::Number(project.and_then(|r| r.float(f::ASPECT_RATIO)).unwrap_or(2.39)),
        ),
        ("scenes", Json::Number(scenes.len() as f64)),
        ("shots", Json::Number(shots as f64)),
        ("locations", Json::Number(doc.locations_in_order().len() as f64)),
        ("boards", Json::Number(doc.boards_in_order().len() as f64)),
        ("days", Json::Number(doc.days_in_order().len() as f64)),
        (
            "lettering",
            Json::text(match doc.lettering_regime() {
                shotlister_engine::Regime::Prep => "prep — reordering renumbers",
                shotlister_engine::Regime::Locked => "locked — letters do not move",
            }),
        ),
        ("read_only", Json::Bool(read_only)),
    ])
}

pub fn scenes(doc: &Doc) -> Json {
    // **A commercial's scenes carry their title and the AV pair.** A film's
    // do not — `video` is the scene's script excerpt, and a hundred and
    // twenty of those in one reply is a screenplay nobody asked for.
    let commercial = doc.kind() == shotlister_engine::FilmKind::Commercial;
    Json::Array(
        doc.scenes_in_order()
            .into_iter()
            .map(|scene| {
                let record = doc.get(scene);
                let mut fields = vec![
                    (
                        "number",
                        Json::text(
                            record
                                .and_then(|r| r.text(f::NUMBER))
                                .unwrap_or_default()
                                .to_string(),
                        ),
                    ),
                    ("heading", Json::text(doc.scene_heading(scene).unwrap_or_default())),
                    (
                        "description",
                        Json::text(
                            record
                                .and_then(|r| r.text(f::DESCRIPTION))
                                .unwrap_or_default()
                                .to_string(),
                        ),
                    ),
                    ("shots", Json::Number(doc.shot_count_in_scene(scene) as f64)),
                    ("split_across_days", Json::Bool(doc.scene_is_split(scene))),
                    // Known once a draft has been taken in, and worth having
                    // here: the length is what a day is planned around.
                    (
                        "length",
                        match doc.scene_length(scene) {
                            Some(length) => Json::text(length),
                            None => Json::Null,
                        },
                    ),
                    (
                        "cast",
                        Json::Array(
                            doc.scene_cast(scene)
                                .into_iter()
                                .map(Json::text)
                                .collect(),
                        ),
                    ),
                ];
                let tags = shotlister_engine::view::list(doc, scene, f::TAGS);
                if !tags.is_empty() {
                    fields.push(("tags", Json::text(tags.join(", "))));
                }
                // Where the crew goes for it — the Locations mode's records,
                // not the heading's words.
                let places = doc.scene_locations(scene);
                if !places.is_empty() {
                    fields.push((
                        "locations",
                        Json::Array(places.into_iter().map(|p| Json::text(doc.location_full_name(p))).collect()),
                    ));
                }
                fields.push((
                    "section",
                    match section_of(doc, scene) {
                        Some(title) => Json::text(title),
                        None => Json::Null,
                    },
                ));
                if commercial {
                    let said = |field: &str| {
                        Json::text(record.and_then(|r| r.text(field)).unwrap_or_default().to_string())
                    };
                    fields.push(("title", Json::text(doc.scene_title(scene))));
                    fields.push(("slug", Json::text(doc.scene_slug(scene).unwrap_or_default())));
                    fields.push(("video", said(f::SCRIPT)));
                    fields.push(("audio", said(f::AUDIO)));
                }
                Json::object(fields)
            })
            .collect(),
    )
}

/// A field's words whether it holds one value or several.
fn list_words(doc: &Doc, record: Id, field: &str) -> String {
    match doc.get(record).and_then(|r| r.get(field).cloned()) {
        Some(shotlister_engine::Value::List(items)) => {
            items.iter().filter_map(|i| i.as_text()).collect::<Vec<_>>().join(", ")
        }
        Some(shotlister_engine::Value::Text(t)) => t,
        _ => String::new(),
    }
}

pub fn shots(doc: &Doc, scene: Option<Id>) -> Json {
    let placements = match scene {
        Some(scene) => doc.placements_in_scene(scene),
        None => doc.all_placements(),
    };
    shots_of(doc, placements)
}

/// These shots, in the shape `shots` answers.
pub fn shots_of(doc: &Doc, placements: Vec<Id>) -> Json {
    Json::Array(
        placements
            .into_iter()
            .filter_map(|placement| {
                let row = doc.row(placement)?;
                Some(Json::object(vec![
                    ("number", Json::text(row.number.clone())),
                    ("scene", Json::text(row.scene_number.clone())),
                    ("description", Json::text(row.description.clone())),
                    ("size", Json::text(row.size.clone())),
                    ("angle", Json::text(row.angle.join(", "))),
                    ("movement", Json::text(row.movement.clone())),
                    (
                        "camera",
                        Json::text(row.camera.as_ref().map(|c| c.display()).unwrap_or_default()),
                    ),
                    ("lens", Json::text(row.lens.clone())),
                    ("focal", row.focal.map(Json::Number).unwrap_or(Json::Null)),
                    ("modifiers", Json::text(row.modifiers.join(", "))),
                    ("lens_filters", Json::text(row.lens_filters.join(", "))),
                    ("support", Json::text(row.support.clone())),
                    ("notes", Json::text(row.notes.clone())),
                    ("day", Json::text(row.day_label.clone().unwrap_or_default())),
                    ("struck", Json::Bool(row.struck)),
                    ("title", Json::text(row.title.clone())),
                    ("tags", Json::text(row.tags.join(", "))),
                    ("pov", Json::text(list_words(doc, row.shot, f::POV))),
                    ("priority", Json::text(list_words(doc, row.shot, f::PRIORITY))),
                    ("colour", Json::text(doc.get(row.shot).and_then(|r| r.text(f::COLOUR)).unwrap_or_default())),
                    (
                        "fields",
                        Json::Object(
                            row.own
                                .iter()
                                .filter(|(_, words)| !words.is_empty())
                                .map(|(field, words)| (list_title(doc, field), Json::text(words.clone())))
                                .collect(),
                        ),
                    ),
                    ("master", Json::Bool(doc.is_master(row.shot))),
                    (
                        "follows",
                        Json::text(
                            doc.master_of(row.shot)
                                .and_then(|m| doc.placements_of_shot(m).first().copied())
                                .and_then(|p| doc.display_number(p))
                                .unwrap_or_default(),
                        ),
                    ),
                    (
                        "rolls_with",
                        Json::Array(
                            row.siblings
                                .iter()
                                .filter_map(|s| doc.placements_of_shot(*s).first().copied())
                                .filter_map(|p| doc.display_number(p))
                                .map(Json::text)
                                .collect(),
                        ),
                    ),
                    ("frames", Json::Number(row.frames.len() as f64)),
                    // **The beat this shot is tied to, and its words.** On a
                    // film, or untied: null and two empty strings.
                    ("script", Json::text(row.script.clone())),
                ]))
            })
            .collect(),
    )
}

// ---- changing ----------------------------------------------------------

/// Fields a scene accepts, and where they go.
const SCENE_FIELDS: [(&str, &str); 9] = [
    // A commercial scene's own three — its title, and the two columns of an
    // AV script. `video` is the scene's `script` field under the name the
    // AV script gives it.
    ("title", f::TITLE),
    ("video", f::SCRIPT),
    ("audio", f::AUDIO),
    ("int_ext", f::INT_EXT),
    ("location", f::LOCATION),
    ("time_of_day", f::TIME_OF_DAY),
    ("description", f::DESCRIPTION),
    ("notes", f::NOTES),
    ("shooting_location", f::SHOOTING_LOCATION),
];

/// Shot fields that are plain text.
const SHOT_TEXT: [(&str, &str); 3] = [
    ("description", f::DESCRIPTION),
    ("title", f::TITLE),
    ("notes", f::NOTES),
];

/// Shot fields that belong to a master list, so setting one teaches the project.
const SHOT_VOCAB: [&str; 4] = ["size", "movement", "lens", "support"];

/// A section by its title, case-insensitive. Sections are named the way
/// he says them — "Spot B" — never by id.
pub fn find_section(doc: &Doc, title: &str) -> Option<Id> {
    let wanted = title.trim().to_lowercase();
    doc.sequences_in_order().into_iter().find(|id| {
        doc.get(*id)
            .and_then(|r| r.text(f::TITLE))
            .map(|t| t.trim().to_lowercase() == wanted)
            .unwrap_or(false)
    })
}

/// The title of the section a scene is in, or nothing.
pub fn section_of(doc: &Doc, scene: Id) -> Option<String> {
    doc.get(scene)
        .and_then(|r| r.ref_id(f::SEQUENCE))
        .and_then(|s| doc.get(s))
        .and_then(|r| r.text(f::TITLE))
        .map(str::to_string)
}

/// Every section in order, with its scene count.
pub fn sections(doc: &Doc) -> Json {
    let scenes = doc.scenes_in_order();
    Json::Array(
        doc.sequences_in_order()
            .into_iter()
            .map(|section| {
                let held = scenes
                    .iter()
                    .filter(|s| doc.get(**s).and_then(|r| r.ref_id(f::SEQUENCE)) == Some(section))
                    .count();
                Json::object(vec![
                    (
                        "title",
                        Json::text(doc.get(section).and_then(|r| r.text(f::TITLE)).unwrap_or_default().to_string()),
                    ),
                    ("scenes", Json::Number(held as f64)),
                ])
            })
            .collect(),
    )
}

/// `section` on add_scene / update_scene: the scene joins the section by
/// that title, made if the film has none; an empty string takes it out.
pub fn apply_section(doc: &mut Doc, scene: Id, arguments: &Json) {
    let Some(wanted) = arguments.get("section").and_then(|v| v.as_str()) else {
        return;
    };
    let wanted = wanted.trim();
    if wanted.is_empty() {
        doc.set(scene, f::SEQUENCE, shotlister_engine::Value::Null);
        return;
    }
    let section = find_section(doc, wanted).unwrap_or_else(|| doc.create_sequence(wanted));
    doc.set(scene, f::SEQUENCE, section);
}

pub fn apply_scene_fields(doc: &mut Doc, scene: Id, arguments: &Json) {
    for (name, field) in SCENE_FIELDS {
        if let Some(value) = arguments.get(name).and_then(|v| v.as_str()) {
            // **A person's edit, so the heading follows** — the three parts of
            // a slug go through the door the table's cell uses, which rewrites
            // a printed heading to match. Plain `set` is a draft conforming,
            // and left a scene moved to the garage still reading KITCHEN
            // (Ref 498).
            if [f::INT_EXT, f::LOCATION, f::TIME_OF_DAY].contains(&field) {
                doc.set_scene_field(scene, field, value);
            } else {
                doc.set(scene, field, value);
            }
        }
    }
}

/// The scripts as text, each with the shots quoting it and their words.
pub fn script(doc: &Doc) -> Json {
    Json::Array(
        doc.av_scripts()
            .into_iter()
            .map(|(section, text)| {
                let title = section
                    .and_then(|s| doc.get(s))
                    .and_then(|r| r.text(f::TITLE))
                    .map(str::to_string);
                let quoting: Vec<Json> = doc
                    .shots_quoting(section)
                    .into_iter()
                    .filter_map(|shot| {
                        let number = doc.placements_of_shot(shot).first().and_then(|p| doc.display_number(*p))?;
                        Some(Json::object(vec![
                            ("shot", Json::text(number)),
                            ("text", Json::text(doc.shot_excerpt(shot))),
                        ]))
                    })
                    .collect();
                Json::object(vec![
                    (
                        "section",
                        match title {
                            Some(t) => Json::text(t),
                            None => Json::Null,
                        },
                    ),
                    ("layout", Json::text(if shotlister_engine::quoting::is_av(&text) { "av" } else { "plain" })),
                    (
                        "rows",
                        if shotlister_engine::quoting::is_av(&text) {
                            Json::Array(
                                shotlister_engine::quoting::av_rows(&text)
                                    .into_iter()
                                    .map(|(video, audio)| {
                                        Json::object(vec![("video", Json::text(video)), ("audio", Json::text(audio))])
                                    })
                                    .collect(),
                            )
                        } else {
                            Json::Null
                        },
                    ),
                    ("text", Json::text(shotlister_engine::quoting::readable(&text))),
                    ("shots", Json::Array(quoting)),
                ])
            })
            .collect(),
    )
}

/// `script` (and `section`) on add_shot / update_shot / tie_shot: the words
/// tie the shot to the first place they appear; empty unties.
pub fn apply_quote(doc: &mut Doc, shot: Id, arguments: &Json) -> Result<(), String> {
    let words = match arguments.get("script").or_else(|| arguments.get("text")).and_then(|v| v.as_str()) {
        Some(w) => w.to_string(),
        None => return Ok(()),
    };
    let wanted = arguments.get("section").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    if words.trim().is_empty() {
        doc.tie_shot(shot, None, 0, 0);
        return Ok(());
    }
    // tie_shot's mode: add these words to the shot's stretches, or let
    // just these go. Anything else (or none) replaces.
    let mode = arguments.get("mode").and_then(|v| v.as_str()).unwrap_or("").trim().to_ascii_lowercase();
    if mode == "remove" {
        return if doc.untie_words(shot, &words) {
            Ok(())
        } else {
            Err(format!("The shot does not quote those words: {}", words.trim()))
        };
    }
    let add = mode == "add";
    // Which script: the named section; else whichever holds the words.
    let candidates: Vec<Option<Id>> = if wanted.is_empty() {
        doc.av_scripts().into_iter().map(|(s, _)| s).collect()
    } else {
        vec![Some(find_section(doc, &wanted).ok_or(format!("There is no section called {wanted}."))?)]
    };
    // Adding: the shot's own script first, so a second line lands beside
    // the first rather than in another script that happens to share words.
    let mut candidates = candidates;
    if add {
        if let Some(q) = doc.quote_of(shot) {
            if let Some(at) = candidates.iter().position(|s| *s == q.section) {
                let own = candidates.remove(at);
                candidates.insert(0, own);
            }
        }
    }
    for section in candidates {
        if doc.tie_words(shot, section, &words, add) {
            return Ok(());
        }
    }
    Err(format!("Those words are not in the script: {}", words.trim()))
}

/// The six colours a shot (or a new camera) can wear — the table's own
/// palette, by the names its menu says.
pub const SHOT_COLOURS: [(&str, &str); 6] = [
    ("red", "E5484D"),
    ("orange", "D97706"),
    ("green", "16A34A"),
    ("blue", "0A6CE8"),
    ("purple", "7B4BC4"),
    ("pink", "DB2777"),
];

/// A colour as he says it — `blue`, or six hex digits — into hex. "" is none.
pub fn colour_named(said: &str) -> Result<String, String> {
    let said = said.trim().trim_start_matches('#');
    if said.is_empty() {
        return Ok(String::new());
    }
    if let Some((_, hex)) = SHOT_COLOURS.iter().find(|(name, _)| name.eq_ignore_ascii_case(said)) {
        return Ok(hex.to_string());
    }
    if said.len() == 6 && said.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(said.to_uppercase());
    }
    Err(format!(
        "A colour is {} or six hex digits — not {said}.",
        SHOT_COLOURS.iter().map(|(n, _)| *n).collect::<Vec<_>>().join(", ")
    ))
}

/// Every camera, in the order they were added, husks left out.
pub fn cameras_in_order(doc: &Doc) -> Vec<Id> {
    let mut all = doc.store().of_kind(&shotlister_engine::store::Kind::Unit);
    all.retain(|r| r.text(f::LABEL).map(|l| !l.trim().is_empty()).unwrap_or(false));
    all.into_iter().map(|r| r.id).collect()
}

/// `A-Cam Alexa 35` — its name, and its body when it has one.
pub fn camera_named(doc: &Doc, unit: Id) -> String {
    let text = |field: &str| doc.get(unit).and_then(|r| r.text(field)).unwrap_or_default().trim().to_string();
    let (label, body) = (text(f::LABEL), text(f::BODY));
    if body.is_empty() { label } else { format!("{label} {body}") }
}

/// A camera by its name, by its name and body, or an id.
pub fn find_camera(doc: &Doc, said: &str) -> Option<Id> {
    let said = said.trim();
    if let Some(id) = Id::from_hex(said) {
        if doc.get(id).map(|r| r.kind == shotlister_engine::store::Kind::Unit) == Some(true) {
            return Some(id);
        }
    }
    let cameras = cameras_in_order(doc);
    cameras
        .iter()
        .find(|u| doc.get(**u).and_then(|r| r.text(f::LABEL)).map(|l| l.trim().eq_ignore_ascii_case(said)) == Some(true))
        .or_else(|| cameras.iter().find(|u| camera_named(doc, **u).eq_ignore_ascii_case(said)))
        .copied()
}

/// A shot's own column by its name.
fn own_column(doc: &Doc, said: &str) -> Option<shotlister_engine::columns::CustomColumn> {
    let wanted = said.trim();
    doc.custom_columns()
        .into_iter()
        .find(|c| c.label.eq_ignore_ascii_case(wanted) || c.field == wanted)
}

/// Everything a shot's cells take, the way the table's `set` takes it.
///
/// Returns what did not land, as sentences — a locked list keeps a value off
/// the shot without a word from the engine, and a reply of "Updated" over a
/// lens that never landed is how a thread ends up believing a shot says 40mm.
/// An `Err` is a mistake in the asking (a camera, column or shot that does not
/// exist) and the whole call is refused.
pub fn apply_shot_fields(doc: &mut Doc, shot: Id, arguments: &Json) -> Result<Vec<String>, String> {
    let mut kept_off: Vec<String> = Vec::new();
    let refused = |kept_off: &mut Vec<String>, doc: &Doc, name: &str, term: &str| {
        if !term.trim().is_empty() && doc.vocabulary_locked(name) && !doc.vocabulary_contains(name, term.trim()) {
            let title = list_title(doc, name);
            kept_off.push(format!(
                "{title} {} was not set: the {} list is locked and does not hold it.",
                term.trim(),
                title.to_lowercase()
            ));
        }
    };
    let text = |key: &str| arguments.get(key).and_then(|v| v.as_str()).map(str::to_string);

    for (name, field) in SHOT_TEXT {
        if let Some(value) = text(name) {
            doc.set(shot, field, value.as_str());
        }
    }
    for name in SHOT_VOCAB.iter().chain(["priority"].iter()) {
        if let Some(value) = text(name) {
            refused(&mut kept_off, doc, name, &value);
            doc.set_vocab_field(shot, name, &value);
        }
    }
    // Angle, tags and point of view hold several values, written the way the
    // sheets write them.
    for name in ["angle", "tags", "pov", "modifiers", "lens_filters"] {
        if let Some(value) = text(name) {
            let parts: Vec<&str> = value.split(',').map(|p| p.trim()).filter(|p| !p.is_empty()).collect();
            for part in &parts {
                refused(&mut kept_off, doc, name, part);
            }
            doc.set_vocab_list(shot, name, &parts);
        }
    }
    // **A camera is a record, not a word.** A name the film has never had
    // makes one — what the table's camera picker does — coloured from the
    // palette in turn, so two cameras never arrive wearing one colour.
    if let Some(said) = text("camera") {
        if said.trim().is_empty() {
            doc.set(shot, f::UNIT, shotlister_engine::Value::Null);
        } else {
            let unit = match find_camera(doc, &said) {
                Some(unit) => unit,
                None => {
                    let colour = SHOT_COLOURS[cameras_in_order(doc).len() % SHOT_COLOURS.len()].1;
                    kept_off.push(format!("{} is a new camera.", said.trim()));
                    doc.create_unit_coloured(said.trim(), "", colour)
                }
            };
            doc.set(shot, f::UNIT, unit);
        }
    }
    // Where a zoom is set, in mm: a number, "35mm", or "" to clear.
    if let Some(v) = arguments.get("focal") {
        let mm = match v {
            Json::Number(n) => Some(*n),
            Json::Text(t) if t.trim().is_empty() => None,
            Json::Text(t) => Some(t.trim().trim_end_matches("mm").trim().parse::<f64>().map_err(|_| "focal is a focal length in mm, like 35.".to_string())?),
            _ => return Err("focal is a focal length in mm, like 35.".to_string()),
        };
        match mm {
            Some(mm) if mm.is_finite() && mm > 0.0 => doc.set(shot, f::FOCAL, shotlister_engine::Value::Float(mm)),
            Some(_) => return Err("focal is a focal length in mm, like 35.".to_string()),
            None => doc.set(shot, f::FOCAL, shotlister_engine::Value::Null),
        }
    }
    if let Some(said) = text("colour") {
        let hex = colour_named(&said)?;
        if hex.is_empty() {
            doc.set(shot, f::COLOUR, shotlister_engine::Value::Null);
        } else {
            doc.set(shot, f::COLOUR, hex.as_str());
        }
    }
    // The project's own columns, by their names.
    if let Some(fields) = arguments.get("fields") {
        let fields = match fields {
            Json::Text(written) => crate::json::parse(written).ok_or("fields is not JSON.")?,
            other => other.clone(),
        };
        let Json::Object(pairs) = fields else {
            return Err("fields is an object: {\"column name\": \"value\"}.".to_string());
        };
        for (said, value) in pairs {
            let column = own_column(doc, &said).ok_or_else(|| {
                let names: Vec<String> = doc.custom_columns().into_iter().map(|c| c.label).collect();
                if names.is_empty() {
                    format!("This project has no column called {said} — it has none of its own. add_column makes one.")
                } else {
                    format!("This project has no column called {said}. Its own columns are {}.", names.join(", "))
                }
            })?;
            let value = match &value {
                Json::Text(t) => t.clone(),
                Json::Bool(b) => if *b { "1".to_string() } else { String::new() },
                Json::Number(n) => n.to_string(),
                Json::Array(items) => items.iter().filter_map(|i| i.as_str()).collect::<Vec<_>>().join(", "),
                _ => String::new(),
            };
            match column.kind.as_str() {
                "single" => {
                    refused(&mut kept_off, doc, &column.field, &value);
                    doc.set_vocab_field(shot, &column.field, &value);
                }
                "multi" => {
                    let parts: Vec<&str> = value.split(',').map(|p| p.trim()).filter(|p| !p.is_empty()).collect();
                    for part in &parts {
                        refused(&mut kept_off, doc, &column.field, part);
                    }
                    doc.set_vocab_list(shot, &column.field, &parts);
                }
                "check" => {
                    let on = !value.is_empty() && value != "0" && !value.eq_ignore_ascii_case("false");
                    doc.set(shot, &column.field, shotlister_engine::Value::Bool(on));
                }
                _ => doc.set(shot, &column.field, value.as_str()),
            }
        }
    }
    // **Shot, as in got** — the strike the Mac and the phone put on a shot
    // on set (his ruling 2026-09-16: struck means got, labelled Shot). The
    // portal marks a shot through this door since 2026-09-22.
    if let Some(done) = bool_arg(arguments, "shot_done") {
        doc.strike(shot, done);
    }
    // A master is a shot others stand in for; `follows` points one at it.
    if let Some(on) = bool_arg(arguments, "master") {
        doc.set_master(shot, on);
    }
    if let Some(said) = text("follows") {
        if said.trim().is_empty() {
            doc.link_shot(shot, None);
        } else {
            let placement = find_placement(doc, &said).ok_or(format!("There is no shot {} in this project.", said.trim()))?;
            let master = shot_of(doc, placement).ok_or(format!("There is no shot {} in this project.", said.trim()))?;
            if master == shot {
                return Err("A shot cannot follow itself.".to_string());
            }
            doc.link_shot(shot, Some(master));
        }
    }
    // Two cameras on one moment. "" takes this one out of its setup.
    if let Some(said) = text("rolls_with") {
        if said.trim().is_empty() {
            doc.untie_setup(shot);
        } else {
            let placement = find_placement(doc, &said).ok_or(format!("There is no shot {} in this project.", said.trim()))?;
            let other = shot_of(doc, placement).ok_or(format!("There is no shot {} in this project.", said.trim()))?;
            if doc.tie_setup(shot, other).is_none() {
                return Err("A shot cannot roll with itself.".to_string());
            }
        }
    }
    Ok(kept_off)
}

// ---- exporting ---------------------------------------------------------

pub fn export(doc: &Doc, format: &str, group: GroupBy) -> Result<(String, Vec<u8>), String> {
    let sheet = doc.sheet(&Query::grouped_by(group));
    match format {
        "csv" => Ok(("csv".to_string(), csv::write(&sheet).into_bytes())),
        "xlsx" => Ok((
            "xlsx".to_string(),
            xlsx::write(&sheet, &|name| doc.vocabulary(name), &xlsx::no_frames),
        )),
        "document" => Ok((
            "html".to_string(),
            // **The film's own type, not a default** — read off the project
            // record the way `ffi` reads it, so a document exported by an AI
            // wears the type he set on the Mac.
            //
            // **This line has now broken the build twice, and so has its twin
            // in `web/`.** `caption` arrived with the document-view rewrite
            // (accf697) and was missed; `style` arrived with the doc-style work
            // and was missed again. Neither crate is reached by a `cargo test`
            // in `engine/` or `ffi/`, so the signature can change and every
            // check still passes while two crates do not compile at all.
            // Empty caption, as every other caller passes.
            html::document(&sheet, &html::no_frames, Print::Document, 1.0, "", &style_of(doc))
                .into_bytes(),
        )),
        "table" => Ok((
            "html".to_string(),
            // Default widths: the per-column multipliers are an option the
            // Mac's share sheet sends, and nothing here sets one.
            html::table(&sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(),
                &html::ColumnWidths::default())
                .into_bytes(),
        )),
        other => Err(format!(
            "Unknown format {other}. Try csv, xlsx, document or table."
        )),
    }
}

pub fn grouping(name: &str) -> GroupBy {
    match name {
        "day" => GroupBy::Day,
        "sequence" => GroupBy::Sequence,
        "none" | "flat" => GroupBy::Flat,
        _ => GroupBy::Scene,
    }
}

/// What is pinned to a scene or a shot, and what each thing is — so an agent
/// filing references from elsewhere can see what is already here rather than
/// pinning the same lookbook page four times.
pub fn attachments(doc: &Doc, owner: Id) -> Json {
    let lead = doc.key_media_ref(owner);
    let is_shot = doc.get(owner).map(|r| r.kind == shotlister_engine::store::Kind::Shot) == Some(true);
    Json::Array(
        doc.media_refs(owner)
            .into_iter()
            .enumerate()
            .filter_map(|(at, mref)| {
                let media = doc.get(mref)?.ref_id(f::MEDIA)?;
                let record = doc.get(media)?;
                let mut pairs = vec![
                    ("position", Json::Number((at + 1) as f64)),
                    ("name", Json::text(doc.media_ref_name(mref))),
                    ("file", Json::text(record.text(f::FILENAME).unwrap_or_default())),
                    (
                        "kind",
                        Json::text(
                            doc.media_kind(media)
                                .map(|k| k.as_str().to_string())
                                .unwrap_or_default(),
                        ),
                    ),
                    (
                        "caption",
                        Json::text(doc.get(mref).and_then(|r| r.text(f::CAPTION)).unwrap_or_default()),
                    ),
                ];
                if is_shot {
                    pairs.push(("lead", Json::Bool(lead == Some(mref))));
                }
                // How this use is framed and cut, when somebody has: the file
                // is never touched, so this is the only place it shows.
                if let Some((start, end)) = doc.media_trim(mref) {
                    pairs.push(("trim", Json::object(vec![("start", Json::Number(start)), ("end", Json::Number(end))])));
                }
                if let Some(r) = doc.get(mref) {
                    if let (Some(x), Some(y)) = (r.float(f::CROP_X), r.float(f::CROP_Y)) {
                        let scale = r.float(f::CROP_SCALE).unwrap_or(1.0);
                        pairs.push(("crop", Json::object(vec![("x", Json::Number(x)), ("y", Json::Number(y)), ("scale", Json::Number(scale))])));
                    }
                }
                Some(Json::object(pairs))
            })
            .collect(),
    )
}

// ---- reading a screenplay ------------------------------------------------

/// What a screenplay says, as the report an import screen is built from.
///
/// The MCP is handed **text**, never a PDF: turning a PDF into positioned text
/// is the Mac's job (it has a decoder worth using and this server does not), so
/// a script arriving here has already been read off the page or was text all
/// along. Everything below is the same code the app's own import runs.
pub fn read_screenplay(doc: &Doc, text: &str, options: shotlister_engine::CastOptions) -> Json {
    let detection = doc.detection();
    let screenplay = shotlister_engine::screenplay::read_with(text, &detection);
    let laid = shotlister_engine::lay_out(&screenplay);
    let diff = doc.diff_script(&screenplay.accepted());
    let cast = shotlister_engine::cast::read(&screenplay, options);

    let scenes: Vec<Json> = screenplay
        .scenes
        .iter()
        .enumerate()
        .map(|(at, scene)| {
            let extent = laid.extent_of(at);
            Json::object(vec![
                ("index", Json::Number(at as f64)),
                ("label", Json::text(scene.label.clone())),
                ("heading", Json::text(scene.script.heading.clone())),
                (
                    "kind",
                    Json::text(match scene.status {
                        shotlister_engine::screenplay::Status::Scene => "scene",
                        shotlister_engine::screenplay::Status::SubSlug { .. } => "room",
                    }),
                ),
                // A room is offered rather than taken: the rule that finds one
                // cannot tell BATHROOM. from A LOUD BANG.
                ("offered_not_taken", Json::Bool(!scene.accepted)),
                (
                    "already_in_the_project",
                    Json::Bool(
                        scene
                            .script
                            .number
                            .as_deref()
                            .and_then(|n| doc.scene_numbered(n))
                            .is_some(),
                    ),
                ),
                (
                    "length",
                    match extent {
                        Some(e) => Json::text(e.length()),
                        None => Json::Null,
                    },
                ),
                (
                    "starts_on_page",
                    Json::Number(extent.map(|e| e.starts_on).unwrap_or(0) as f64),
                ),
            ])
        })
        .collect();

    let people: Vec<Json> = cast
        .iter()
        .map(|member| {
            Json::object(vec![
                ("name", Json::text(member.name.clone())),
                ("reads_as", Json::text(member.display.clone())),
                ("speeches", Json::Number(member.speeches as f64)),
                (
                    "scenes",
                    Json::Array(
                        member
                            .scenes
                            .iter()
                            .map(|at| Json::text(screenplay.scenes[*at].label.clone()))
                            .collect(),
                    ),
                ),
                (
                    "spelled",
                    Json::Array(member.aliases.iter().cloned().map(Json::text).collect()),
                ),
            ])
        })
        .collect();

    let gone: Vec<Json> = diff
        .gone
        .iter()
        .map(|scene| {
            Json::object(vec![
                ("number", Json::text(scene.number.clone())),
                ("heading", Json::text(scene.heading.clone())),
                ("shots_that_would_go_with_it", Json::Number(scene.shots as f64)),
            ])
        })
        .collect();

    Json::object(vec![
        ("pages_long", Json::Number(laid.pages_long() as f64)),
        (
            "repeated_headings_ignored",
            Json::Number(screenplay.duplicates_ignored as f64),
        ),
        ("scenes_found", Json::Number(screenplay.scenes.len() as f64)),
        (
            "already_in_the_project",
            Json::Number((diff.changed.len() + diff.unchanged) as f64),
        ),
        ("new_to_the_project", Json::Number(diff.added.len() as f64)),
        ("scenes", Json::Array(scenes)),
        ("cast", Json::Array(people)),
        (
            "in_the_project_but_not_in_this_draft",
            Json::Array(gone),
        ),
        (
            "note",
            Json::text(
                "Nothing here has changed anything. A room is offered rather than taken. \
                 A scene the draft no longer mentions is reported and never removed — \
                 archiving one is a person's decision, taken with the shot count in front \
                 of them.",
            ),
        ),
    ])
}

// ---- arguments, read forgivingly ----------------------------------------
//
// The other end of this is a language model, and a model asked for a number
// will as often as not send `"2"`. A tool that silently ignores an argument it
// was plainly given is worse than one that refuses it: nothing looks wrong, the
// filter simply does not happen. So each of these takes the right type, or a
// string that plainly means it.

/// A number, whether it arrived as one or as digits in quotes.
pub fn number_arg(arguments: &crate::json::Json, key: &str) -> Option<f64> {
    let value = arguments.get(key)?;
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|text| text.trim().parse().ok()))
}

/// A flag, whether it arrived as one or as the word.
pub fn bool_arg(arguments: &crate::json::Json, key: &str) -> Option<bool> {
    let value = arguments.get(key)?;
    if let Some(flag) = value.as_bool() {
        return Some(flag);
    }
    match value.as_str()?.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}

/// A list of words, whether it arrived as an array, as an array written out in
/// a string, or as one comma-separated line.
pub fn list_arg(arguments: &crate::json::Json, key: &str) -> Option<Vec<String>> {
    let value = arguments.get(key)?;
    if let Some(items) = value.as_array() {
        return Some(
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect(),
        );
    }
    let text = value.as_str()?.trim();
    if text.is_empty() {
        return Some(Vec::new());
    }
    if let Some(parsed) = crate::json::parse(text).and_then(|json| {
        json.as_array().map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect::<Vec<String>>()
        })
    }) {
        if !parsed.is_empty() {
            return Some(parsed);
        }
    }
    Some(
        text.split(',')
            .map(|word| word.trim().trim_matches('"').to_string())
            .filter(|word| !word.is_empty())
            .collect(),
    )
}

/// How a cast list was asked for.
pub fn cast_options(arguments: &crate::json::Json) -> shotlister_engine::CastOptions {
    shotlister_engine::CastOptions {
        merging: match arguments.str_field("merge_names").as_str() {
            "none" => shotlister_engine::Merging::None,
            "hard" => shotlister_engine::Merging::Aggressive,
            _ => shotlister_engine::Merging::Regular,
        },
        minimum_speeches: number_arg(arguments, "at_least").unwrap_or(0.0) as usize,
    }
}

/// The type a film's document page is written in.
///
/// **One place, so the next change to `html::document` has one caller to find
/// here.** A film with no project record — only ever a fixture — takes the
/// standard style, the same fallback `ffi` uses.
fn style_of(doc: &Doc) -> docstyle::Style {
    match doc.project_id() {
        Some(project) => docstyle::of(doc, project),
        None => docstyle::Style::standard_style(),
    }
}

// ---- master lists ------------------------------------------------------

/// The eight lists, the way the app titles them. `support` is Equipment on
/// screen, so both names reach it.
const LISTS: [(&str, &str); 10] = [
    ("size", "Size"),
    ("angle", "Angle"),
    ("movement", "Movement"),
    ("lens", "Lens"),
    ("modifiers", "Modifiers"),
    ("lens_filters", "Filters"),
    ("support", "Equipment"),
    ("priority", "Priority"),
    ("pov", "POV"),
    ("tags", "Tags"),
];

/// A list the way somebody names it — `lens`, `lenses`, `Equipment` — or a
/// pick-list column the project made for itself, by its name. Anything else is
/// a sentence naming what there is.
pub fn list_named(doc: &Doc, said: &str) -> Result<String, String> {
    let wanted = said.trim().to_lowercase();
    // A film may have made its own "Filter" column before Filters was built
    // in; its own column keeps the word.
    if matches!(wanted.as_str(), "filter" | "filters") {
        if let Some(column) = pick_columns(doc).into_iter().find(|c| c.label.to_lowercase() == wanted) {
            return Ok(column.field);
        }
    }
    let alias = match wanted.as_str() {
        "modifier" | "extender" | "extenders" | "lens modifiers" => "modifiers",
        "filter" | "filters" | "lens filter" | "lens filters" => "lens_filters",
        "lenses" | "glass" => "lens",
        "sizes" | "shot size" | "shot sizes" => "size",
        "angles" | "shot angle" | "shot angles" => "angle",
        "movements" | "camera movement" => "movement",
        "equipment" | "gear" | "supports" => "support",
        "priorities" => "priority",
        "tag" => "tags",
        other => other,
    };
    if let Some((name, _)) = LISTS.iter().find(|(name, _)| *name == alias) {
        return Ok(name.to_string());
    }
    if let Some(column) = pick_columns(doc)
        .into_iter()
        .find(|c| c.label.to_lowercase() == wanted || c.field == said.trim())
    {
        return Ok(column.field);
    }
    let mut names: Vec<String> = LISTS.iter().map(|(n, _)| n.to_string()).collect();
    names.extend(pick_columns(doc).into_iter().map(|c| c.label));
    Err(format!("There is no {} list. The lists are {}.", said.trim(), names.join(", ")))
}

/// The project's own columns that choose from a list — one choice or several.
fn pick_columns(doc: &Doc) -> Vec<shotlister_engine::columns::CustomColumn> {
    doc.custom_columns().into_iter().filter(|c| c.kind == "single" || c.kind == "multi").collect()
}

pub fn list_title(doc: &Doc, name: &str) -> String {
    if let Some((_, title)) = LISTS.iter().find(|(n, _)| *n == name) {
        return title.to_string();
    }
    doc.custom_columns()
        .into_iter()
        .find(|c| c.field == name)
        .map(|c| c.label)
        .unwrap_or_else(|| name.to_string())
}

/// One list, whole: its terms in order with how much each is used, its lock,
/// the colours it has been given, and what shots carry that it does not hold.
pub fn list(doc: &Doc, name: &str) -> Json {
    let colours = doc.term_colours(name);
    let values: Vec<Json> = doc
        .vocab_usage(name)
        .into_iter()
        .map(|(term, used)| {
            let mut pairs = vec![("term", Json::text(term.clone())), ("used", Json::Number(used as f64))];
            if let Some((_, hex)) = colours.iter().find(|(t, _)| t.eq_ignore_ascii_case(&term)) {
                pairs.push(("colour", Json::text(hex.clone())));
            }
            Json::object(pairs)
        })
        .collect();
    let orphans: Vec<Json> = doc
        .vocabulary_orphans(name)
        .into_iter()
        .map(|(term, used)| Json::object(vec![("term", Json::text(term)), ("used", Json::Number(used as f64))]))
        .collect();
    Json::object(vec![
        ("list", Json::text(if LISTS.iter().any(|(n, _)| *n == name) { name.to_string() } else { list_title(doc, name) })),
        ("title", Json::text(list_title(doc, name))),
        ("locked", Json::Bool(doc.vocabulary_locked(name))),
        ("terms", Json::Array(values)),
        ("not_on_list", Json::Array(orphans)),
    ])
}

/// Every list, in the app's order, then the project's own pick-list columns.
pub fn lists(doc: &Doc) -> Json {
    let mut all: Vec<Json> = LISTS.iter().map(|(name, _)| list(doc, name)).collect();
    all.extend(pick_columns(doc).into_iter().map(|c| list(doc, &c.field)));
    Json::Array(all)
}

/// The shots and scenes carrying a term, by the numbers he says —
/// `5A`, `scene 12`.
pub fn carriers_named(doc: &Doc, name: &str, term: &str) -> Vec<String> {
    let mut said = Vec::new();
    for id in doc.carrying(name, term) {
        let Some(record) = doc.get(id) else { continue };
        match record.kind {
            shotlister_engine::store::Kind::Shot => {
                for placement in doc.placements_of_shot(id) {
                    if let Some(number) = doc.display_number(placement) {
                        said.push(number);
                    }
                }
            }
            shotlister_engine::store::Kind::Scene => {
                said.push(format!("scene {}", record.text(f::NUMBER).unwrap_or_default()));
            }
            _ => {}
        }
    }
    said
}

/// "3 shots (5A, 5B, 12C)" — a count, with the names when there are few
/// enough to read.
pub fn counted(names: &[String]) -> String {
    let n = names.len();
    let noun = if names.iter().all(|s| s.starts_with("scene ")) && n > 0 {
        if n == 1 { "scene" } else { "scenes" }
    } else if n == 1 {
        "shot"
    } else {
        "shots"
    };
    if n == 0 {
        "nothing".to_string()
    } else if n <= 8 {
        format!("{n} {noun} ({})", names.join(", "))
    } else {
        format!("{n} {noun}")
    }
}

/// A refusal from the engine, as a sentence about this list.
pub fn list_refusal(doc: &Doc, name: &str, refusal: shotlister_engine::vocab::ListRefusal) -> String {
    use shotlister_engine::vocab::ListRefusal;
    let title = list_title(doc, name).to_lowercase();
    match refusal {
        ListRefusal::NoProject => "This project has no record, so it has nowhere to keep a list.".to_string(),
        ListRefusal::Locked => format!(
            "The {title} list is locked, so nothing was added. Locking is his decision — \
             ask before unlocking it with lock_list."
        ),
        ListRefusal::NotOnList(term) => format!("{term} is not on the {title} list."),
    }
}

/// **Now, as a date a draft is stamped with** — `2026-09-30T18:04:05Z`.
///
/// A draft with no date is treated as a ghost of an undone import and never
/// listed (`Doc::revisions`), so `apply_draft` called without `dated` took a
/// script in that `revisions` then could not see. The engine's clock is the
/// one the host set (a worker has no other), turned into a civil date here.
pub fn iso_now() -> String {
    iso_at(shotlister_engine::id::now_millis())
}

/// A moment in milliseconds, as `iso_now` writes one.
pub fn iso_at_millis(millis: u64) -> String {
    iso_at(millis)
}

fn iso_at(millis: u64) -> String {
    let secs = (millis / 1000) as i64;
    let (days, rest) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Howard Hinnant's days-to-civil.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        rest / 3600,
        (rest % 3600) / 60,
        rest % 60
    )
}

#[cfg(test)]
mod dating {
    #[test]
    fn a_moment_as_a_civil_date() {
        assert_eq!(super::iso_at(0), "1970-01-01T00:00:00Z");
        assert_eq!(super::iso_at(1_756_700_000_000), "2025-09-01T04:13:20Z");
        assert_eq!(super::iso_at(1_709_164_800_000), "2024-02-29T00:00:00Z");
    }
}
