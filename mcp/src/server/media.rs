//! What hangs on things — frames on a shot, pictures on a scene, a location or
//! a reference board — and the reference boards themselves.
//!
//! Bringing a *new* file in wants its bytes, which is `attach` on the Mac (the
//! web connector has no disk). Everything else — a caption, the order, the
//! lead frame, taking one off, hanging a file the film already holds
//! somewhere else — is the engine's alone, and so works through either door.

use shotlister_engine::{f, Doc, Id};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "update_attachment",
        description: "Change one thing pinned to a shot, scene, location, reference board or edit reference — name its owner (`shot` 34A, `scene` 34, `location`, `board`, or `edit_reference` by its name) and which one (`attachment`: its position from attachments, 1 first, or its name). `caption` is what shows under it (\"\" clears); `name` renames this use (the file's type is kept); `position` moves it (1 is first); `lead`=true makes it the frame that stands for a shot in the table and on paper. `crop` frames a picture where it is drawn cropped (the iPhone's Crop): {\"x\": 0–1, \"y\": 0–1, the point that sits in the middle, \"scale\": 1 whole width to 8}; `clear_crop`=true puts it back. `trim` sets the part of a clip this use plays: {\"start\": seconds, \"end\": seconds}; `clear_trim`=true plays it whole. Neither touches the file.",
        arguments: &[
            ("shot", "string", false),
            ("scene", "string", false),
            ("location", "string", false),
            ("board", "string", false),
            ("edit_reference", "string", false),
            ("attachment", "string", true),
            ("caption", "string", false),
            ("name", "string", false),
            ("position", "number", false),
            ("lead", "boolean", false),
            ("crop", "object", false),
            ("clear_crop", "boolean", false),
            ("trim", "object", false),
            ("clear_trim", "boolean", false),
        ],
    },
    Tool {
        name: "remove_attachment",
        description: "Take one thing off a shot, scene, location, reference board or edit reference (owner and `attachment` as update_attachment names them). The file stays while anything else still holds it; the last use of a file going means the file goes too — the reply says which.",
        arguments: &[
            ("shot", "string", false),
            ("scene", "string", false),
            ("location", "string", false),
            ("board", "string", false),
            ("edit_reference", "string", false),
            ("attachment", "string", true),
        ],
    },
    Tool {
        name: "copy_attachment",
        description: "Hang something already in the project somewhere else — no upload, so it works on the web: from an owner (`shot`, `scene`, `location`, `board` or `edit_reference`) and its `attachment`, onto `to_shot`, `to_scene`, `to_location`, `to_board` or `to_edit_reference` (an edit reference's clip or stills: a clip the project already holds, from a reference board, say). The caption and name come with it. `move`=true takes it off where it was.",
        arguments: &[
            ("shot", "string", false),
            ("scene", "string", false),
            ("location", "string", false),
            ("board", "string", false),
            ("edit_reference", "string", false),
            ("attachment", "string", true),
            ("to_shot", "string", false),
            ("to_scene", "string", false),
            ("to_location", "string", false),
            ("to_board", "string", false),
            ("to_edit_reference", "string", false),
            ("move", "boolean", false),
        ],
    },
    Tool {
        name: "media",
        description: "Every picture and clip the project holds, biggest first: `id`, `file`, `kind`, `bytes`, where each is used (`used_on`: Shot 12B, a location, Mood Board · Night, Diagram · Scene 4) or empty when nothing uses it, and how many saved versions show it. `show`: all (default), used, unused or deleted — deleted lists the names, sizes and dates deleted pictures left behind. The Media window on the Mac, Film Settings › Media on the iPhone.",
        arguments: &[("show", "string", false), ("limit", "number", false)],
    },
    Tool {
        name: "delete_media",
        description: "Delete pictures or clips for real — every use goes, the file goes from every device, and only the name stays (an old version that showed it shows a gap with the name). Not undoable: say what it costs and ask him first. `media`: ids from media, or file names, separated by commas. A file name several pictures share is refused with their ids.",
        arguments: &[("media", "string", true)],
    },
    Tool {
        name: "delete_unused_media",
        description: "Delete for real every picture and clip nothing in the project uses — the Media window's Delete Unused. Not undoable: list them with media show=unused and ask him first. Answers how many went and the room freed.",
        arguments: &[],
    },
    Tool {
        name: "reference_boards",
        description: "The project's reference boards (the References mode — walls of pictures, not the portal's pin boards): each with how many pictures and which scenes hang it. `attachments` with `board` lists one board's pictures.",
        arguments: &[],
    },
    Tool {
        name: "add_reference_board",
        description: "Add a reference board. Pictures go on with attach (a file on the Mac) or copy_attachment (one the project already holds).",
        arguments: &[("name", "string", true)],
    },
    Tool {
        name: "update_reference_board",
        description: "Rename a reference board, move it (`position`, 1 first), or say which scenes hang it: `scenes` replaces the list, `add_scene` / `remove_scene` change one. `tiles` is how the wall fills each tile: original (each picture its own shape), square, or project (the project's frame). `sync_with_drive` says whether its pictures go to Google Drive. `tags` (comma-separated, the one tag list shots and scenes share) replaces its tags; \"\" clears them.",
        arguments: &[
            ("board", "string", true),
            ("name", "string", false),
            ("position", "number", false),
            ("scenes", "array", false),
            ("add_scene", "string", false),
            ("remove_scene", "string", false),
            ("tiles", "string", false),
            ("sync_with_drive", "boolean", false),
            ("tags", "string", false),
        ],
    },
    Tool {
        name: "delete_reference_board",
        description: "Take a reference board away. Scenes lose the link; its pictures go unless something else holds them. One with pictures or scenes is refused, saying what hangs on it, unless `even_if_used` is true — ask him first.",
        arguments: &[("board", "string", true), ("even_if_used", "boolean", false)],
    },
];

/// What a delete says back: how many, and the room freed where this host
/// has files.
fn deleted_said(n: usize, freed: u64) -> String {
    let what = if n == 1 { "1 picture".to_string() } else { format!("{n} pictures") };
    if freed > 0 {
        format!("Deleted {what}, {:.1} MB freed. Their names are kept.", freed as f64 / 1_048_576.0)
    } else {
        format!("Deleted {what}. The files go from every device at its next sync; their names are kept.")
    }
}

/// A day, as `2026-10-10`, from milliseconds since 1970.
fn day(millis: i64) -> String {
    let days = millis.div_euclid(86_400_000);
    // Civil date from days since 1970 (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:04}-{:02}-{:02}", if m <= 2 { y + 1 } else { y }, m, d)
}

/// A reference board by its name, or an id.
pub(super) fn find_board(doc: &Doc, said: &str) -> Result<Id, String> {
    let said = said.trim();
    if let Some(id) = Id::from_hex(said) {
        if doc.get(id).is_some() {
            return Ok(id);
        }
    }
    doc.board_named(said).ok_or_else(|| {
        let all: Vec<String> = doc.boards_in_order().into_iter().map(|b| doc.board_name(b)).collect();
        if all.is_empty() {
            format!("There is no reference board {said}. This project has none yet — add_reference_board makes one.")
        } else {
            format!("There is no reference board {said}. The boards are {}.", all.join(", "))
        }
    })
}

/// The one thing a call names as the owner, with its prefix (`""` or `to_`),
/// and how to say it. A shot is its record, not where it sits.
pub(super) fn owner_of(doc: &Doc, arguments: &Json, prefix: &str) -> Result<Option<(Id, String)>, String> {
    let said = |key: &str| arguments.get(&format!("{prefix}{key}")).and_then(|v| v.as_str()).map(str::trim).filter(|s| !s.is_empty()).map(str::to_string);
    let given: Vec<(&str, String)> = ["shot", "scene", "location", "board", "edit_reference"]
        .into_iter()
        .filter_map(|k| said(k).map(|v| (k, v)))
        .collect();
    let Some((kind, value)) = given.first().cloned() else {
        return Ok(None);
    };
    if given.len() > 1 {
        return Err(format!("Name one {}owner: shot, scene, location, board or edit_reference.", if prefix.is_empty() { "" } else { "new " }));
    }
    Ok(Some(match kind {
        "shot" => {
            let placement = tools::find_placement(doc, &value).ok_or(format!("There is no shot {value} in this project."))?;
            (tools::shot_of(doc, placement).ok_or(format!("There is no shot {value} in this project."))?, format!("shot {value}"))
        }
        "scene" => (tools::find_scene(doc, &value).ok_or(format!("There is no scene {value} in this project."))?, format!("scene {value}")),
        "location" => {
            let place = super::places::find_location(doc, &value)?;
            (place, doc.location_full_name(place))
        }
        // **An edit reference's clip and stills** (the Edit Reference mod)
        // hang on it as on any owner, so a clip the project already holds can
        // be put on one from the web.
        "edit_reference" => {
            let e = super::editref::find(doc, &value)?;
            (e, format!("the {} edit reference", doc.edit_ref(e).map(|r| r.name).unwrap_or_default()))
        }
        _ => {
            let board = find_board(doc, &value)?;
            (board, format!("the {} board", doc.board_name(board)))
        }
    }))
}

fn owner_needed(doc: &Doc, arguments: &Json) -> Result<(Id, String), String> {
    owner_of(doc, arguments, "")?.ok_or_else(|| "Say whose: shot, scene, location, board or edit_reference.".to_string())
}

/// One use on an owner, by its position (1 first) or its name.
pub(super) fn find_use(doc: &Doc, owner: Id, whose: &str, said: &str) -> Result<Id, String> {
    let uses = doc.media_refs(owner);
    let said = said.trim();
    if let Ok(n) = said.parse::<usize>() {
        if n >= 1 && n <= uses.len() {
            return Ok(uses[n - 1]);
        }
    }
    let by_name = |mref: &Id, exact: bool| {
        let name = doc.media_ref_name(*mref);
        if exact {
            name.eq_ignore_ascii_case(said)
        } else {
            name.rsplit_once('.').map(|(stem, _)| stem).unwrap_or(&name).eq_ignore_ascii_case(said)
        }
    };
    uses.iter()
        .find(|m| by_name(m, true))
        .or_else(|| uses.iter().find(|m| by_name(m, false)))
        .copied()
        .ok_or_else(|| {
            if uses.is_empty() {
                format!("Nothing is pinned to {whose}.")
            } else {
                format!(
                    "{whose} has no {said}. It holds: {}.",
                    uses.iter().enumerate().map(|(i, m)| format!("{} {}", i + 1, doc.media_ref_name(*m))).collect::<Vec<_>>().join(", ")
                )
            }
        })
}

fn scene(doc: &Doc, said: &str) -> Result<Id, String> {
    tools::find_scene(doc, said).ok_or(format!("There is no scene {} in this project.", said.trim()))
}

fn scene_number(doc: &Doc, scene: Id) -> String {
    doc.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or_default().to_string()
}

impl<F: Films> Server<F> {
    pub(super) fn media_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "update_attachment" => {
                let arguments = arguments.clone();
                self.change("Change attachment", move |doc| {
                    let (owner, whose) = owner_needed(doc, &arguments)?;
                    let mref = find_use(doc, owner, &whose, &arguments.str_field("attachment"))?;
                    let mut said = Vec::new();
                    if let Some(caption) = arguments.get("caption").and_then(|v| v.as_str()) {
                        let caption = caption.trim();
                        if caption.is_empty() {
                            doc.set(mref, f::CAPTION, shotlister_engine::Value::Null);
                        } else {
                            doc.set(mref, f::CAPTION, caption);
                        }
                        said.push("captioned".to_string());
                    }
                    if let Some(name) = arguments.get("name").and_then(|v| v.as_str()).map(str::trim) {
                        if name.is_empty() {
                            return Err("A name is needed.".to_string());
                        }
                        // The stored file's type, whatever the name says.
                        let stored = doc.media_ref_name(mref);
                        let named = match stored.rsplit_once('.') {
                            Some((_, ext)) if !ext.is_empty() => format!("{name}.{ext}"),
                            _ => name.to_string(),
                        };
                        doc.set_media_ref_name(mref, &named);
                        said.push(format!("called {named}"));
                    }
                    if let Some(n) = tools::number_arg(&arguments, "position") {
                        if n < 1.0 {
                            return Err("position counts from 1.".to_string());
                        }
                        doc.move_media_to(mref, n as usize - 1);
                        said.push(format!("moved to {}", n as usize));
                    }
                    if tools::bool_arg(&arguments, "lead") == Some(true) {
                        if doc.get(owner).map(|r| r.kind == shotlister_engine::store::Kind::Shot) != Some(true) {
                            return Err("Only a shot has a lead frame.".to_string());
                        }
                        doc.set_key_frame(owner, mref);
                        said.push("the lead frame".to_string());
                    }
                    if tools::bool_arg(&arguments, "clear_crop") == Some(true) {
                        doc.clear_media_crop(mref);
                        said.push("crop cleared".to_string());
                    }
                    if let Some(crop) = arguments.get("crop") {
                        {
                            let x = tools::number_arg(crop, "x").ok_or("crop is {x, y, scale}.")?;
                            let y = tools::number_arg(crop, "y").ok_or("crop is {x, y, scale}.")?;
                            let scale = tools::number_arg(crop, "scale").unwrap_or(1.0);
                            doc.set_media_crop(mref, x, y, scale);
                            said.push(format!("cropped at {:.2}, {:.2} ×{scale}", x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)));
                        }
                    }
                    let trimming = arguments.get("trim").is_some() || tools::bool_arg(&arguments, "clear_trim") == Some(true);
                    if trimming {
                        let kind = doc.get(mref).and_then(|r| r.ref_id(f::MEDIA)).and_then(|m| doc.media_kind(m));
                        if kind.map(|k| k.as_str() == "video") != Some(true) {
                            return Err(format!("{} is not a clip, so it has no trim.", doc.media_ref_name(mref)));
                        }
                    }
                    if tools::bool_arg(&arguments, "clear_trim") == Some(true) {
                        doc.clear_media_trim(mref);
                        said.push("trim cleared".to_string());
                    }
                    if let Some(trim) = arguments.get("trim") {
                        {
                            let start = tools::number_arg(trim, "start").ok_or("trim is {start, end} in seconds.")?;
                            let end = tools::number_arg(trim, "end").ok_or("trim is {start, end} in seconds.")?;
                            if end <= start {
                                return Err("A trim ends after it starts.".to_string());
                            }
                            doc.set_media_trim(mref, start, end);
                            said.push(format!("plays {start}s to {end}s"));
                        }
                    }
                    if said.is_empty() {
                        return Err("Say what to change: caption, name, position, lead, crop or trim.".to_string());
                    }
                    Ok(format!("{} on {whose}: {}.", doc.media_ref_name(mref), said.join(", ")))
                })
            }
            "remove_attachment" => {
                let arguments = arguments.clone();
                self.change("Remove frame", move |doc| {
                    let (owner, whose) = owner_needed(doc, &arguments)?;
                    let mref = find_use(doc, owner, &whose, &arguments.str_field("attachment"))?;
                    let named = doc.media_ref_name(mref);
                    let media = doc.get(mref).and_then(|r| r.ref_id(f::MEDIA));
                    let held_elsewhere = media
                        .map(|m| doc.store().referring_to(&shotlister_engine::store::Kind::MediaRef, f::MEDIA, m).len() > 1)
                        .unwrap_or(false);
                    doc.detach_media(mref);
                    Ok(if held_elsewhere {
                        format!("Took {named} off {whose}; the file is still used elsewhere.")
                    } else {
                        format!("Took {named} off {whose}. Nothing else held it, so the file goes too.")
                    })
                })
            }
            "copy_attachment" => {
                let arguments = arguments.clone();
                let moving = tools::bool_arg(&arguments, "move").unwrap_or(false);
                self.change(if moving { "Move picture" } else { "Add frame" }, move |doc| {
                    let (owner, whose) = owner_needed(doc, &arguments)?;
                    let mref = find_use(doc, owner, &whose, &arguments.str_field("attachment"))?;
                    let (target, where_to) = owner_of(doc, &arguments, "to_")?
                        .ok_or("Say where it goes: to_shot, to_scene, to_location or to_board.")?;
                    if target == owner {
                        return Err(format!("It is already on {whose}."));
                    }
                    let named = doc.media_ref_name(mref);
                    if moving {
                        doc.move_media_use(mref, target);
                        return Ok(format!("Moved {named} from {whose} to {where_to}."));
                    }
                    let media = doc.get(mref).and_then(|r| r.ref_id(f::MEDIA)).ok_or("That attachment has no file.")?;
                    let caption = doc.get(mref).and_then(|r| r.text(f::CAPTION)).unwrap_or_default().to_string();
                    let copy = doc.attach_media(target, media, &caption);
                    doc.set_media_ref_name(copy, &named);
                    Ok(format!("{named} is on {where_to} too."))
                })
            }
            "media" => (|| {
                let doc = self.films.doc()?;
                let show = arguments.get("show").and_then(|v| v.as_str()).unwrap_or("all").trim().to_lowercase();
                let limit = tools::number_arg(arguments, "limit").map(|n| n.max(1.0) as usize).unwrap_or(usize::MAX);
                if show == "deleted" {
                    let gone = doc.gone_media();
                    return Ok(Json::object(vec![
                        ("deleted", Json::Number(gone.len() as f64)),
                        (
                            "items",
                            Json::Array(
                                gone.into_iter()
                                    .take(limit)
                                    .map(|g| {
                                        Json::object(vec![
                                            ("id", Json::text(g.media.to_hex())),
                                            ("file", Json::text(g.filename)),
                                            ("bytes", Json::Number(g.bytes as f64)),
                                            ("deleted_on", Json::text(day(g.on))),
                                        ])
                                    })
                                    .collect(),
                            ),
                        ),
                    ])
                    .encode());
                }
                let shelf = doc.shelf();
                let total: u64 = shelf.iter().map(|s| s.bytes).sum();
                let unused: Vec<_> = shelf.iter().filter(|s| !s.used()).collect();
                let unused_bytes: u64 = unused.iter().map(|s| s.bytes).sum();
                let unused_count = unused.len();
                let keep: Box<dyn Fn(&shotlister_engine::shelf::Shelved) -> bool> = match show.as_str() {
                    "all" | "" => Box::new(|_| true),
                    "used" | "in use" => Box::new(|s| s.used()),
                    "unused" | "not used" => Box::new(|s| !s.used()),
                    other => return Err(format!("show is all, used, unused or deleted, not {other}.")),
                };
                Ok(Json::object(vec![
                    ("count", Json::Number(shelf.len() as f64)),
                    ("bytes", Json::Number(total as f64)),
                    ("unused", Json::Number(unused_count as f64)),
                    ("unused_bytes", Json::Number(unused_bytes as f64)),
                    ("deleted", Json::Number(doc.gone_media().len() as f64)),
                    (
                        "items",
                        Json::Array(
                            shelf
                                .iter()
                                .filter(|s| keep(s))
                                .take(limit)
                                .map(|s| {
                                    Json::object(vec![
                                        ("id", Json::text(s.media.to_hex())),
                                        ("file", Json::text(s.filename.clone())),
                                        ("kind", Json::text(s.kind.as_str())),
                                        ("bytes", Json::Number(s.bytes as f64)),
                                        ("used_on", Json::Array(s.uses.iter().map(|u| Json::text(u.label.clone())).collect())),
                                        ("versions", Json::Number(s.versions as f64)),
                                    ])
                                })
                                .collect(),
                        ),
                    ),
                ])
                .encode())
            })(),
            "delete_media" => (|| {
                let said = arguments.str_field("media");
                let doc = self.films.doc()?;
                let shelf = doc.shelf();
                let mut ids = Vec::new();
                for one in said.split(',').map(str::trim).filter(|s| !s.is_empty()) {
                    if let Some(item) = Id::from_hex(one).and_then(|id| shelf.iter().find(|s| s.media == id)) {
                        ids.push(item.media);
                        continue;
                    }
                    let named: Vec<_> = shelf.iter().filter(|s| s.filename.eq_ignore_ascii_case(one)).collect();
                    match named.len() {
                        0 => {
                            return Err(if doc.gone_media().iter().any(|g| g.filename.eq_ignore_ascii_case(one)) {
                                format!("{one} is already deleted.")
                            } else {
                                format!("The film holds no picture called {one}. media lists them.")
                            })
                        }
                        1 => ids.push(named[0].media),
                        _ => {
                            let which: Vec<String> = named.iter().map(|s| s.media.to_hex()).collect();
                            return Err(format!("{} pictures are called {one}. Name one by id: {}.", named.len(), which.join(", ")));
                        }
                    }
                }
                if ids.is_empty() {
                    return Err("Say which: media takes ids or file names, separated by commas.".to_string());
                }
                ids.dedup();
                if self.films.read_only() {
                    return Err("This project is open for reading only.".to_string());
                }
                let (n, freed) = self.films.delete_media(&ids)?;
                Ok(deleted_said(n, freed))
            })(),
            "delete_unused_media" => (|| {
                let ids = self.films.doc()?.unused_media();
                if ids.is_empty() {
                    return Ok("Nothing is unused.".to_string());
                }
                if self.films.read_only() {
                    return Err("This project is open for reading only.".to_string());
                }
                let (n, freed) = self.films.delete_media(&ids)?;
                Ok(deleted_said(n, freed))
            })(),
            "reference_boards" => self.films.doc().map(|doc| {
                Json::Array(
                    doc.boards_in_order()
                        .into_iter()
                        .map(|board| {
                            Json::object(vec![
                                ("name", Json::text(doc.board_name(board))),
                                ("pictures", Json::Number(doc.media_refs(board).len() as f64)),
                                (
                                    "scenes",
                                    Json::Array(doc.scenes_with_board(board).into_iter().map(|s| Json::text(scene_number(doc, s))).collect()),
                                ),
                            ])
                        })
                        .collect(),
                )
                .encode()
            }),
            "add_reference_board" => (|| {
                let label = arguments.str_field("name").trim().to_string();
                if label.is_empty() {
                    return Err("A board needs a name.".to_string());
                }
                self.change("Add mood board", move |doc| {
                    if doc.board_named(&label).is_some() {
                        return Err(format!("There is already a board called {label}."));
                    }
                    doc.create_board(&label);
                    Ok(format!("Added the {label} board."))
                })
            })(),
            "update_reference_board" => {
                let wanted = arguments.str_field("board");
                let arguments = arguments.clone();
                self.change("Change mood board", move |doc| {
                    let board = find_board(doc, &wanted)?;
                    let mut touched = false;
                    if let Some(label) = arguments.get("name").and_then(|v| v.as_str()).map(str::trim) {
                        if label.is_empty() {
                            return Err("A board needs a name.".to_string());
                        }
                        if doc.board_named(label).map(|b| b != board) == Some(true) {
                            return Err(format!("There is already a board called {label}."));
                        }
                        doc.rename_board(board, label);
                        touched = true;
                    }
                    if let Some(n) = tools::number_arg(&arguments, "position") {
                        if n < 1.0 {
                            return Err("position counts from 1.".to_string());
                        }
                        doc.move_board_to(board, n as usize - 1);
                        touched = true;
                    }
                    if let Some(list) = tools::list_arg(&arguments, "scenes") {
                        let mut wanted = Vec::new();
                        for said in list.iter().filter(|s| !s.trim().is_empty()) {
                            wanted.push(scene(doc, said)?);
                        }
                        for held in doc.scenes_with_board(board) {
                            if !wanted.contains(&held) {
                                doc.remove_scene_board(held, board);
                            }
                        }
                        for s in wanted {
                            doc.add_scene_board(s, board);
                        }
                        touched = true;
                    }
                    let add = arguments.str_field("add_scene");
                    if !add.trim().is_empty() {
                        let s = scene(doc, &add)?;
                        doc.add_scene_board(s, board);
                        touched = true;
                    }
                    let remove = arguments.str_field("remove_scene");
                    if !remove.trim().is_empty() {
                        let s = scene(doc, &remove)?;
                        doc.remove_scene_board(s, board);
                        touched = true;
                    }
                    if let Some(shape) = arguments.get("tiles").and_then(|v| v.as_str()).map(|t| t.trim().to_lowercase()) {
                        let shape = match shape.as_str() {
                            "original" | "own" | "as shot" => "original",
                            "square" => "square",
                            "project" | "film" | "frame" => "project",
                            _ => return Err("tiles is original, square or project.".to_string()),
                        };
                        doc.set(board, f::BOARD_RATIO, shape);
                        touched = true;
                    }
                    if let Some(on) = tools::bool_arg(&arguments, "sync_with_drive") {
                        doc.set(board, f::SYNC_WITH_DRIVE, if on { "1" } else { "0" });
                        touched = true;
                    }
                    if let Some(tags) = arguments.get("tags").and_then(|v| v.as_str()) {
                        let items: Vec<&str> = tags.split(',').map(str::trim).filter(|t| !t.is_empty()).collect();
                        doc.set_vocab_list(board, f::TAGS, &items);
                        touched = true;
                    }
                    if !touched {
                        return Err("Say what to change: name, position, scenes, add_scene, remove_scene, tiles, sync_with_drive or tags.".to_string());
                    }
                    let scenes: Vec<String> = doc.scenes_with_board(board).into_iter().map(|s| scene_number(doc, s)).collect();
                    Ok(format!(
                        "The {} board{}.",
                        doc.board_name(board),
                        if scenes.is_empty() { String::new() } else { format!(" hangs on scene{} {}", if scenes.len() == 1 { "" } else { "s" }, scenes.join(", ")) }
                    ))
                })
            }
            "delete_reference_board" => {
                let wanted = arguments.str_field("board");
                let anyway = tools::bool_arg(arguments, "even_if_used").unwrap_or(false);
                self.change("Delete mood board", move |doc| {
                    let board = find_board(doc, &wanted)?;
                    let named = doc.board_name(board);
                    let pictures = doc.media_refs(board).len();
                    let scenes: Vec<String> = doc.scenes_with_board(board).into_iter().map(|s| scene_number(doc, s)).collect();
                    let mut hangs = Vec::new();
                    if pictures > 0 {
                        hangs.push(format!("{pictures} picture{}", if pictures == 1 { "" } else { "s" }));
                    }
                    if !scenes.is_empty() {
                        hangs.push(format!("scene{} {}", if scenes.len() == 1 { "" } else { "s" }, scenes.join(", ")));
                    }
                    if !hangs.is_empty() && !anyway {
                        return Err(format!(
                            "The {named} board has {} on it. Nothing was removed. Its pictures would go unless used elsewhere — ask him, then call again with even_if_used=true.",
                            hangs.join(" and ")
                        ));
                    }
                    doc.delete_board(board);
                    Ok(format!("Removed the {named} board."))
                })
            }
            _ => return None,
        })
    }
}
