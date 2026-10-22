//! **A new film, made on the server** — the Projects Console's New Film with
//! the Mac off (2026-10-11, Projects Console without the Mac, stage 3 step 5).
//!
//! On the Mac, New Film asks Shotlister Studio to make one
//! (`--newfilm <title> --link <project>`): `storage::create_as` starts the
//! film — its project record, the lists he works from
//! (`seed_standing_vocabularies`), a clean history — the title is written, and
//! `Linking.link` ties it to the project (`console_page`, `console_name`,
//! `drive_url`, then `drive_folder` once the Mac has found the folder).
//!
//! This is the same, into an empty film the host has begun (`start`, no logs,
//! `settle`): the same engine calls, in the same order, saved as one log for
//! the host to keep under the film's new name in the bucket, with the manifest
//! a film on disk would carry (`package::Manifest`). A device that fetches it
//! from the relay gets exactly what a film made on another Mac and synced
//! gives it.
//!
//! Takes `{"title", "page", "name", "drive_url", "drive_folder"}` and answers
//! `{"ok": true, "project": <the project record's id>, "manifest": <text>}`
//! or `{"error": …}`. Refused into a film that already has a project record:
//! this makes films, it never remakes one.

use shotlister_engine::json::Json;
use shotlister_engine::mark::{Mark, Source};
use shotlister_engine::package::Manifest;
use shotlister_mcp::films::Films;

use super::{give, taken, Bucket, SERVER};

/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn new_film(ptr: *const u8, len: usize) -> *mut u8 {
    let asked = taken(ptr, len);
    let said = SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => make_film(server.films_mut(), &asked),
        None => Err("No film is open.".to_string()),
    });
    give(match said {
        Ok(text) => text,
        Err(text) => Json::object(vec![("error", Json::text(text))]).encode(),
    })
}

pub fn make_film(films: &mut Bucket, asked: &str) -> Result<String, String> {
    let asked = shotlister_engine::json::parse(asked).ok_or("That is not JSON.")?;
    if films.read_only() {
        return Err("You may look at this film, not change it.".to_string());
    }
    // The Mac's rule (`backend.new_film`, `StudioApp.newFilm`): a title that
    // is only spaces is no title; anything else names a film.
    let title = asked.str_field("title").trim().to_string();
    if title.is_empty() {
        return Err("a film needs a title".to_string());
    }
    let doc = films.doc_mut()?;
    if doc.project_id().is_some() {
        return Err("there is a film here already".to_string());
    }
    // `storage::create_as`: the record, the lists, a clean history.
    let project = doc.create_project(&title);
    doc.seed_standing_vocabularies();
    doc.clear_history();
    // `Linking.link`: the three, always, as the Mac writes them; the folder
    // only when it is known, as `--link` writes it only when it found one.
    doc.set(project, "console_page", asked.str_field("page").as_str());
    // The Mac stamps the project's icon and colour the moment the page is
    // written (`mark: mirrored`, source `console`), and its manifest carries
    // them, so the relay's film list draws it. Half a pair is none.
    if let Some(mark) = asked.get("mark") {
        let wanted = Mark { path: mark.str_field("path"), colour: mark.str_field("colour") };
        if !wanted.path.is_empty() || !wanted.colour.is_empty() {
            if !doc.set_mark(Some(&wanted), Source::Console) {
                return Err("that icon and colour would not go on the film".to_string());
            }
        }
    }
    doc.set(project, "console_name", asked.str_field("name").as_str());
    doc.set(project, "drive_url", asked.str_field("drive_url").as_str());
    let folder = asked.str_field("drive_folder");
    if !folder.is_empty() {
        doc.set(project, "drive_folder", folder.as_str());
    }
    films.save()?;
    if films.pending().is_empty() {
        return Err("the film was not written".to_string());
    }
    let mut manifest = Manifest::new(&title, Some(project));
    if let Some(mark) = films.doc_mut()?.mark() {
        manifest.mark_path = mark.path;
        manifest.mark_colour = mark.colour;
    }
    let manifest = manifest.encode();
    Ok(Json::object(vec![
        ("ok", Json::Bool(true)),
        ("project", Json::text(project.to_hex())),
        ("manifest", Json::text(manifest)),
    ])
    .encode())
}

#[cfg(test)]
mod tests {
    use super::*;
    use shotlister_engine::{DeviceId, Doc};

    const PAGE: &str = "27fd41c6-9232-85ef-fb41-4614bf2884e0";

    fn empty(device: u64) -> Bucket {
        shotlister_engine::id::set_now_millis(1_760_200_000_000);
        shotlister_engine::id::set_seed(device * 7 + 1);
        let mut b = Bucket::new("ab".repeat(16).as_str(), "Halcyon", false, DeviceId(device));
        b.settle();
        b
    }

    fn asked(title: &str) -> String {
        let title = title.replace('\\', r"\\").replace('"', r#"\""#);
        format!(
            r#"{{"title":"{title}","page":"{PAGE}","name":"Halcyon","drive_url":"https://drive.google.com/drive/folders/1abc","drive_folder":"/Users/x/My Drive/cinematography/projects/halcyon"}}"#
        )
    }

    /// The film as another device sees it, from the log alone.
    fn fetched(log: &str) -> Bucket {
        let mut b = Bucket::new("ab".repeat(16).as_str(), "", false, DeviceId(99));
        assert_eq!(b.take(log), 0, "every line reads");
        b.settle();
        b
    }

    #[test]
    fn a_film_is_made_linked_to_its_project_in_one_log() {
        let mut b = empty(5);
        let said = shotlister_engine::json::parse(&make_film(&mut b, &asked("Halcyon")).unwrap()).unwrap();
        assert_eq!(said.get("ok").and_then(|v| v.as_bool()), Some(true));
        let log = b.pending().to_string();
        assert!(log.lines().count() > 3, "the record, its words and the lists: {log}");
        let other = fetched(&log);
        let doc = other.doc().unwrap();
        let project = doc.project_id().expect("a project record");
        let record = doc.get(project).unwrap();
        assert_eq!(record.text("title"), Some("Halcyon"));
        assert_eq!(record.text("console_page"), Some(PAGE));
        assert_eq!(record.text("console_name"), Some("Halcyon"));
        assert_eq!(record.text("drive_url"), Some("https://drive.google.com/drive/folders/1abc"));
        assert_eq!(record.text("drive_folder"), Some("/Users/x/My Drive/cinematography/projects/halcyon"));
        assert_eq!(said.get("project").and_then(|v| v.as_str()), Some(project.to_hex().as_str()));
    }

    #[test]
    fn the_manifest_is_the_one_a_film_on_disk_carries() {
        let mut b = empty(6);
        let said = shotlister_engine::json::parse(&make_film(&mut b, &asked("Let's \"Cook\"")).unwrap()).unwrap();
        let text = said.get("manifest").and_then(|v| v.as_str()).unwrap().to_string();
        let m = Manifest::parse(&text).unwrap();
        assert_eq!(m.title, "Let's \"Cook\"");
        assert_eq!(m.format, shotlister_engine::FORMAT_VERSION);
        assert_eq!(m.project.map(|p| p.to_hex()), said.get("project").and_then(|v| v.as_str()).map(String::from));
        assert_eq!(shotlister_engine::package::access(m.format), Ok(shotlister_engine::package::Access::ReadWrite));
    }

    #[test]
    fn it_carries_the_same_lists_a_film_made_on_the_mac_starts_with() {
        let mut b = empty(7);
        make_film(&mut b, &asked("Halcyon")).unwrap();
        let ours = fetched(b.pending());
        // `storage::create_as`, in memory.
        let mut mac = Doc::new(DeviceId(8));
        mac.create_project("Halcyon");
        mac.seed_standing_vocabularies();
        let lists = |doc: &Doc| {
            use shotlister_engine::vocab::{ANGLE, MOVEMENT, SIZE, SUPPORT};
            [SIZE, ANGLE, MOVEMENT, SUPPORT]
                .iter()
                .map(|field| (field.to_string(), doc.vocabulary(field)))
                .collect::<Vec<_>>()
        };
        let theirs = lists(&mac);
        assert!(theirs.iter().any(|(_, v)| !v.is_empty()), "the Mac's film starts with lists");
        assert_eq!(lists(ours.doc().unwrap()), theirs);
    }

    #[test]
    fn the_icon_and_colour_go_on_at_birth_and_on_the_manifest_as_the_macs_link_puts_them() {
        let mut b = empty(13);
        let path = "M17.5 10.625h-2.187v6.25h-3.75v-5H8.437v5h-3.75v-6.25H2.5v-1.25l7.5-7.5 2.813 2.813V2.5h2.5v4.688L17.5 9.375z";
        let asked = format!(
            r##"{{"title":"Halcyon","page":"{PAGE}","name":"Halcyon","drive_url":"","mark":{{"path":"{path}","colour":"#C14C8A"}}}}"##
        );
        let said = shotlister_engine::json::parse(&make_film(&mut b, &asked).unwrap()).unwrap();
        let other = fetched(b.pending());
        let doc = other.doc().unwrap();
        let mark = doc.mark().expect("a mark");
        assert_eq!(mark.colour, "#C14C8A");
        assert_eq!(mark.path, path);
        let record = doc.get(doc.project_id().unwrap()).unwrap();
        assert_eq!(record.text("mark_source"), Some("console"));
        let m = Manifest::parse(said.get("manifest").and_then(|v| v.as_str()).unwrap()).unwrap();
        assert_eq!((m.mark_path.as_str(), m.mark_colour.as_str()), (path, "#C14C8A"));
        // Half a pair is refused, with nothing written.
        let mut half = empty(14);
        let asked = format!(r##"{{"title":"Halcyon","page":"{PAGE}","mark":{{"path":"","colour":"#C14C8A"}}}}"##);
        assert!(make_film(&mut half, &asked).is_err());
    }

    #[test]
    fn the_folder_is_left_out_when_it_is_not_known() {
        let mut b = empty(9);
        make_film(&mut b, &format!(r#"{{"title":"Oddity","page":"{PAGE}","name":"Oddity","drive_url":""}}"#)).unwrap();
        let other = fetched(b.pending());
        let doc = other.doc().unwrap();
        let record = doc.get(doc.project_id().unwrap()).unwrap();
        assert_eq!(record.text("drive_folder").unwrap_or(""), "");
        assert_eq!(record.text("console_page"), Some(PAGE));
    }

    #[test]
    fn nothing_is_made_without_a_title_into_a_film_or_when_only_reading() {
        let mut b = empty(10);
        assert!(make_film(&mut b, r#"{"title":"  "}"#).unwrap_err().contains("needs a title"));
        assert_eq!(b.pending(), "");
        make_film(&mut b, &asked("Halcyon")).unwrap();
        let log = b.pending().to_string();
        let mut again = fetched(&log);
        assert!(make_film(&mut again, &asked("Halcyon")).unwrap_err().contains("already"));
        assert_eq!(again.pending(), "");
        let mut looking = Bucket::new("cd".repeat(16).as_str(), "", true, DeviceId(11));
        looking.settle();
        assert!(make_film(&mut looking, &asked("Halcyon")).is_err());
    }

    #[test]
    fn the_server_can_write_its_facts_into_it_afterwards() {
        let mut b = empty(12);
        make_film(&mut b, &asked("Halcyon")).unwrap();
        let mut later = fetched(b.pending());
        let bare: String = PAGE.chars().filter(|c| *c != '-').collect();
        let said = super::super::mirror_into_film(&mut later, &format!(r#"{{"link":"{bare}","facts":{{"director":"Ivy Sterling"}}}}"#)).unwrap();
        assert!(said.contains("director"), "{said}");
    }
}
