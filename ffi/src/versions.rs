//! Versions: the film as it stood at a moment. Every command here is about
//! them, and all of them live here rather than in `dispatch`.
//!
//! - `versions` — every one, newest first, each with what has changed since.
//! - `saveversion <name> [day]` — keep the film as it stands now.
//! - `renameversion <id> <name>`, `deleteversion <id>`.
//! - `dailyversion [day]` — the start-of-day one, if one is due. Answers
//!   `{saved}` with the id, or empty.
//! - `lookat <id>` — show that version instead of now. Answers the view.
//! - `looknow` — back to now. Answers the view.
//! - `bringback <version> <id,id,…>` — those things back as they were, one
//!   undo step. Leaves looking, since what came back is in now.
//! - `goback <version> [day]` — the whole film back as it was; saves a
//!   version of now first. Leaves looking.
//! - `copyversion <version> <folder> <title>` — the film as it was, written
//!   as a new film into `<folder>` (a `.shotlist` the shell has already made
//!   and cloned the pictures into). Answers `{copied}` with the folder.
//!
//! ## Looking at an old version
//!
//! **The film being looked at and the film being kept are two documents,
//! and they never trade places for longer than one command.** The old one
//! waits in `Handle::looking`. A command that only *shows* something is run
//! with it swapped into the project for the length of that command
//! (`LOOKING_SHOWS`); a command that keeps the film — saving, syncing,
//! pulling another device's work in — runs on the real one as always
//! (`LOOKING_KEEPS`), so the relay, the phone and the disk carry on exactly
//! as if nobody were looking; **and anything else is refused**, which is
//! every edit, and every command added later that nobody has thought about
//! here. Refusing is the safe answer for a command nobody has classified:
//! the screen shows the old film, and an edit would land in today's.

use shotlister_engine::doc::Doc;
use shotlister_engine::jsonw::Json;
use shotlister_engine::versions::{Made, Version};
use shotlister_engine::Id;

use super::{error, id_from, view, writable, Handle};

/// The version being looked at, and the film as it stood then.
pub struct Looking {
    pub version: Id,
    pub doc: Doc,
}

/// What may run while an old version is on screen, against the old version.
/// Every one only reads.
pub const LOOKING_SHOWS: &[&str] = &[
    "view", "group", "filter", "facet", "sort", "vocab", "board", "lists", "colours",
    "gallery", "missing", "media", "clips", "strip", "movies", "original", "colwidths",
    "readscript", "revisions", "scriptpages", "readheading", "floorplan", "share", "print",
    "xlsx", "history", "diagram", "diagramcast", "diagrampreview", "diagramhit",
    "diagramwithin", "diagramsnap", "diagramwall", "diagramfavorites", "diagramfavoriteat",
    "diagramsvg", "diagramlibrary", "diagramart", "diagramsheet", "exportinfo",
];

/// What may run while an old version is on screen, against today's film:
/// keeping it on disk and in step with every other device.
pub const LOOKING_KEEPS: &[&str] = &[
    "save", "incoming", "syncplan", "pull", "strays", "have", "storage", "prune", "clashes",
    "retiredlocations", "shelf", "card",
];

pub fn is_ours(cmd: &str) -> bool {
    matches!(
        cmd,
        "versions"
            | "saveversion"
            | "renameversion"
            | "deleteversion"
            | "dailyversion"
            | "lookat"
            | "looknow"
            | "bringback"
            | "goback"
            | "copyversion"
    )
}

pub fn refused() -> String {
    error("Looking at an earlier version. Go back to now to change anything.")
}

pub fn command<'a>(h: &mut Handle, cmd: &str, mut parts: impl Iterator<Item = &'a str>) -> String {
    match cmd {
        "versions" => list(h),

        "saveversion" => {
            if let Some(p) = writable(h) {
                return p;
            }
            if h.looking.is_some() {
                return refused();
            }
            let name = parts.next().unwrap_or("");
            let day = parts.next();
            let id = h.project.doc_mut().save_version_on(name, Made::Hand, day);
            let _ = h.project.save();
            let mut j = Json::new();
            j.obj().kv("saved", &id.0.to_string()).end_obj();
            j.finish()
        }

        "renameversion" | "deleteversion" => {
            if let Some(p) = writable(h) {
                return p;
            }
            let Some(id) = parts.next().and_then(id_from) else {
                return error("that is not a version this film has");
            };
            let done = if cmd == "renameversion" {
                h.project.doc_mut().rename_version(id, parts.next().unwrap_or(""))
            } else {
                h.project.doc_mut().delete_version(id)
            };
            if !done {
                return error("that is not a version this film has");
            }
            let _ = h.project.save();
            list(h)
        }

        "dailyversion" => {
            if h.project.is_read_only() || h.looking.is_some() {
                return saved(None);
            }
            let made = h.project.doc_mut().daily_version_on(parts.next());
            let _ = h.project.save();
            saved(made)
        }

        "lookat" => {
            let Some(id) = parts.next().and_then(id_from) else {
                return error("that is not a version this film has");
            };
            let Some(doc) = h.project.doc().as_of(id) else {
                return error("that is not a version this film has");
            };
            h.looking = Some(Looking { version: id, doc });
            super::looking_view(h)
        }

        "looknow" => {
            h.looking = None;
            view(h)
        }

        "bringback" => {
            if let Some(p) = writable(h) {
                return p;
            }
            let Some(version) = parts.next().and_then(id_from) else {
                return error("that is not a version this film has");
            };
            let roots: Vec<Id> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| id_from(s.trim()))
                .collect();
            if roots.is_empty() {
                return error("nothing chosen to bring back");
            }
            h.looking = None;
            match h.project.doc_mut().bring_back(version, &roots) {
                Some(b) => {
                    let _ = h.project.save();
                    brought(h, b.records, b.fields, None)
                }
                None => error("that is not a version this film has"),
            }
        }

        "goback" => {
            if let Some(p) = writable(h) {
                return p;
            }
            let Some(version) = parts.next().and_then(id_from) else {
                return error("that is not a version this film has");
            };
            let day = parts.next();
            h.looking = None;
            match h.project.doc_mut().go_back_to_on(version, day) {
                Some(b) => {
                    let _ = h.project.save();
                    brought(h, b.records, b.fields, b.saved)
                }
                None => error("that is not a version this film has"),
            }
        }

        "copyversion" => {
            let Some(version) = parts.next().and_then(id_from) else {
                return error("that is not a version this film has");
            };
            let Some(v) = h.project.doc().version(version) else {
                return error("that is not a version this film has");
            };
            let folder = std::path::PathBuf::from(parts.next().unwrap_or(""));
            let title = parts.next().unwrap_or("").trim().to_string();
            if folder.as_os_str().is_empty() || title.is_empty() {
                return error("a copy needs a place and a name");
            }
            match copy_out(h, &v, &folder, &title) {
                Ok(()) => {
                    let mut j = Json::new();
                    j.obj().kv("copied", &folder.to_string_lossy()).end_obj();
                    j.finish()
                }
                Err(said) => error(&said),
            }
        }

        other => error(&format!("no command called {other}")),
    }
}

/// **A version, written out as a film of its own.**
///
/// Each of the film's change logs is copied under its own name, holding only
/// the changes inside the version's cut — so the new film is exactly the
/// package a backup taken at that moment would have been, history and older
/// versions included. The manifest comes across and is then rewritten from
/// the copy's own record. Never the relay link (`remote.json`), never a fold
/// record: those belong to the film it came from. Then the copy is opened,
/// given its own name and cut loose from Drive, and saved.
fn copy_out(h: &Handle, v: &Version, folder: &std::path::Path, title: &str) -> Result<(), String> {
    use shotlister_engine::package::{is_log_name, CHANGES_DIR, MANIFEST};
    use shotlister_engine::{decode_log, encode_log, FORMAT_VERSION};

    let from = h.project.path();
    let into = folder.join(CHANGES_DIR);
    if folder.join(MANIFEST).exists() {
        return Err("there is already a film there".to_string());
    }
    std::fs::create_dir_all(&into).map_err(|e| e.to_string())?;
    let listing = std::fs::read_dir(from.join(CHANGES_DIR)).map_err(|e| e.to_string())?;
    let mut written = 0;
    for entry in listing.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !is_log_name(&name) {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(entry.path()) else { continue };
        let Ok(log) = decode_log(&text) else { continue };
        let kept: Vec<_> = log.changes.into_iter().filter(|c| v.cut.holds(&c.stamp)).collect();
        if kept.is_empty() {
            continue;
        }
        shotlister_storage::write_whole(&into.join(&name), encode_log(FORMAT_VERSION, &kept, &[]).as_bytes())
            .map_err(|e| e.to_string())?;
        written += 1;
    }
    if written == 0 {
        return Err("that version holds nothing to copy".to_string());
    }
    std::fs::copy(from.join(MANIFEST), folder.join(MANIFEST)).map_err(|e| e.to_string())?;

    let mut copy = shotlister_storage::open_as(folder, h.project.device(), h.project.installation())
        .map_err(|e| e.message())?;
    copy.doc_mut().become_a_copy(title);
    copy.save().map_err(|e| e.message())?;
    copy.refresh_manifest().map_err(|e| e.message())?;
    Ok(())
}

fn saved(id: Option<Id>) -> String {
    let mut j = Json::new();
    j.obj().kv("saved", &id.map(|i| i.0.to_string()).unwrap_or_default()).end_obj();
    j.finish()
}

fn brought(h: &Handle, records: usize, fields: usize, saved: Option<Id>) -> String {
    let mut j = Json::new();
    j.obj()
        .ki("records", records as i64)
        .ki("fields", fields as i64)
        .kv("saved", &saved.map(|i| i.0.to_string()).unwrap_or_default())
        .end_obj();
    let head = j.finish();
    let body = view(h);
    format!("{{\"brought\":{head},\"view\":{body}}}")
}

/// Every version, newest first, with what is different now from each —
/// and which one is on screen, if any.
fn list(h: &Handle) -> String {
    let doc = h.project.doc();
    let mut j = Json::new();
    j.obj();
    j.kv(
        "looking",
        &h.looking.as_ref().map(|l| l.version.0.to_string()).unwrap_or_default(),
    );
    j.key("versions").arr();
    for v in doc.versions() {
        one(&mut j, doc, &v);
    }
    j.end_arr().end_obj();
    j.finish()
}

fn one(j: &mut Json, doc: &Doc, v: &Version) {
    j.obj()
        .kv("id", &v.id.0.to_string())
        .kv("name", &v.name)
        .ki("taken", v.taken as i64)
        .kv("day", &v.day)
        .kv("made", v.made.as_str());
    j.key("since").arr();
    for said in doc.since(v.id).map(|s| s.words()).unwrap_or_default() {
        j.str(&said);
    }
    j.end_arr();
    j.end_obj();
}

#[cfg(test)]
mod tests {
    use super::super::{route, Handle};
    use shotlister_engine::query::GroupBy;
    use shotlister_engine::DeviceId;

    fn tmp(name: &str) -> std::path::PathBuf {
        let p = std::env::temp_dir()
            .join(format!("shotlister-ffi-versions-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    fn handle(project: shotlister_storage::Project) -> Handle {
        Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        }
    }

    fn saved_id(reply: &str) -> String {
        let at = reply.find("\"saved\":\"").expect(reply) + 9;
        reply[at..].split('"').next().unwrap().to_string()
    }

    #[test]
    fn looking_shows_then_keeps_now_and_refuses_edits() {
        let dir = tmp("look");
        let mut project = shotlister_storage::create(&dir, "Call Her Back", DeviceId(7)).unwrap();
        let path = project.path().to_path_buf();
        let d = project.doc_mut();
        let scene = d.create_scene("12");
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set_vocab_field(shot, "lens", "35mm");
        project.save().unwrap();
        let mut h = handle(project);

        let v = saved_id(&route(&mut h, "saveversion\tBefore restructure\t2026-09-29"));
        h.project.doc_mut().delete_scene(scene);
        let later = h.project.doc_mut().create_scene("99");
        h.project.save().unwrap();

        // Looking: the old film, and it says it cannot be changed.
        let seen = route(&mut h, &format!("lookat\t{v}"));
        assert!(seen.contains(&scene.0.to_string()), "the deleted scene is on screen");
        assert!(!seen.contains(&later.0.to_string()), "the one made since is not");
        assert!(seen.contains("\"readOnly\":true"));
        assert!(route(&mut h, "view").contains(&scene.0.to_string()));

        // Edits are refused, whatever door they come through.
        for edit in [
            format!("set\t{}\tlens\t85mm", shot.0.to_string()),
            "addscene\t100".to_string(),
            format!("deletescene\t{}", scene.0.to_string()),
            "undo".to_string(),
            "somethingnobodyhasclassified".to_string(),
        ] {
            assert!(route(&mut h, &edit).contains("Looking at an earlier version"), "{edit}");
        }

        // Keeping the film still works — and keeps *today's*.
        assert!(!route(&mut h, "save").contains("error"));
        let reopened = shotlister_storage::open(&path, DeviceId(8)).unwrap();
        assert!(reopened.doc().get(scene).is_none(), "the old film was never saved over now");
        assert!(reopened.doc().get(later).is_some());
        assert!(h.project.doc().get(later).is_some(), "and today's is back in its place");

        // Back to now.
        let now = route(&mut h, "looknow");
        assert!(now.contains("\"readOnly\":false"));
        assert!(!now.contains(&scene.0.to_string()));

        // The list, with what changed since.
        let list = route(&mut h, "versions");
        assert!(list.contains("Before restructure"), "{list}");
        assert!(list.contains("1 scene added") && list.contains("1 scene removed"), "{list}");

        // Bring the scene back from inside the look.
        route(&mut h, &format!("lookat\t{v}"));
        let back = route(&mut h, &format!("bringback\t{v}\t{}", scene.0.to_string()));
        assert!(back.contains("\"brought\""), "{back}");
        assert!(h.looking.is_none(), "bringing back leaves the look");
        assert!(h.project.doc().get(scene).is_some());
        assert!(h.project.doc().get(later).is_some(), "nothing else touched");

        // And the whole film.
        let gone = route(&mut h, &format!("goback\t{v}\t2026-09-30"));
        assert!(!saved_id(&gone).is_empty());
        assert!(h.project.doc().get(later).is_none());
        let reopened = shotlister_storage::open(&path, DeviceId(8)).unwrap();
        assert!(reopened.doc().get(later).is_none(), "and it reached the disk");
        assert_eq!(reopened.doc().versions().len(), 2);
    }

    #[test]
    fn a_version_copied_out_is_a_film_of_its_own() {
        use shotlister_engine::doc::f;
        use shotlister_engine::store::Kind;
        let dir = tmp("copy");
        let mut project = shotlister_storage::create(&dir, "Call Her Back", DeviceId(7)).unwrap();
        let d = project.doc_mut();
        let scene = d.create_scene("12");
        let place = d.create_location("The House");
        d.set(place, f::DRIVE_FOLDER, "The House");
        d.set(place, f::SYNC_WITH_DRIVE, "1");
        project.save().unwrap();
        std::fs::write(project.path().join("remote.json"), "{}").unwrap();
        let mut h = handle(project);
        let v = saved_id(&route(&mut h, "saveversion\tBefore"));
        h.project.doc_mut().delete_scene(scene);
        let later = h.project.doc_mut().create_scene("99");
        h.project.save().unwrap();

        let into = dir.join("Call Her Back (Before).shotlist");
        let said = route(&mut h, &format!("copyversion\t{v}\t{}\tCall Her Back (Before)", into.display()));
        assert!(said.contains("\"copied\""), "{said}");
        assert!(!into.join("remote.json").exists(), "never the relay link");

        let copy = shotlister_storage::open(&into, DeviceId(8)).unwrap();
        assert!(copy.doc().get(scene).is_some(), "the film as it was");
        assert!(copy.doc().get(later).is_none());
        let film = copy.doc().store().of_kind(&Kind::Project)[0].id;
        assert_eq!(copy.doc().get(film).unwrap().text(f::TITLE), Some("Call Her Back (Before)"));
        assert_eq!(copy.doc().get(place).unwrap().text(f::DRIVE_FOLDER), Some(""));
        assert_eq!(copy.doc().get(place).unwrap().text(f::SYNC_WITH_DRIVE), Some("0"));
        assert!(std::fs::read_to_string(into.join("manifest.json")).unwrap().contains("Call Her Back (Before)"));
        // And the original is untouched.
        assert_eq!(h.project.doc().get(place).unwrap().text(f::DRIVE_FOLDER), Some("The House"));
        assert!(h.project.doc().get(later).is_some());
        // Twice into the same place is refused, not overwritten.
        assert!(route(&mut h, &format!("copyversion\t{v}\t{}\tAgain", into.display())).contains("error"));
    }

    #[test]
    fn a_daily_version_through_the_door() {
        let dir = tmp("daily");
        let mut project = shotlister_storage::create(&dir, "Film", DeviceId(7)).unwrap();
        project.doc_mut().create_scene("1");
        let mut h = handle(project);
        assert!(!saved_id(&route(&mut h, "dailyversion\t2026-09-29")).is_empty());
        assert!(route(&mut h, "dailyversion\t2026-09-29").contains("\"saved\":\"\""));
    }
}
