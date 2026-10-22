//! **A film linked to a project, from the server** — the Projects Console's
//! Link on a film suggestion with the Mac asleep (2026-10-13, Projects Console
//! without the Mac, stage 4 step D).
//!
//! On the Mac, Link asks Shotlister Studio to do it (`--project <film>
//! --link <project>`): `Linking.link` writes `console_page`, `console_name`
//! and `drive_url` through the engine, then `drive_folder` once the Mac has
//! found the project's folder on its own disk. This is the same, on the
//! film's relay copy: the same four fields, in the same order, saved as one
//! log for the host to keep. The icon and colour that Shotlister mirrors once
//! a film carries a page are left to the server's film marks (`mirror_record`),
//! which keep the same rule (never over a mark he set by hand).
//!
//! Takes `{"page", "name", "drive_url", "drive_folder"}` and answers
//! `{"ok": true, "project": <the record's id>, "was": <the page it carried>}`
//! or `{"error": …}`. Refused for a film with no project record (that is New
//! Film's job), and for a film that already carries another project's page:
//! moving a film is a different act from adopting a spare, as the Mac's
//! `unlinked_films` says.

use shotlister_engine::json::Json;
use shotlister_mcp::films::Films;

use super::{give, taken, Bucket, SERVER};

/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn link_film(ptr: *const u8, len: usize) -> *mut u8 {
    let asked = taken(ptr, len);
    let said = SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => link_into_film(server.films_mut(), &asked),
        None => Err("No film is open.".to_string()),
    });
    give(match said {
        Ok(text) => text,
        Err(text) => Json::object(vec![("error", Json::text(text))]).encode(),
    })
}

/// `claimed` is every page a project still has (the Mac's `claimed`): a film
/// carrying one of those is another project's; a film carrying a page no
/// project has any more is a spare, and may be linked.
pub fn link_into_film(films: &mut Bucket, asked: &str) -> Result<String, String> {
    let asked = shotlister_engine::json::parse(asked).ok_or("That is not JSON.")?;
    if films.read_only() {
        return Err("You may look at this film, not change it.".to_string());
    }
    let bare = |s: &str| s.chars().filter(|c| *c != '-').collect::<String>().to_lowercase();
    let page = asked.str_field("page");
    if bare(&page).len() != 32 {
        return Err("a project's page is needed to link a film".to_string());
    }
    let doc = films.doc_mut()?;
    let project = doc.project_id().ok_or("this film has no project record")?;
    let was = doc.get(project).and_then(|r| r.text("console_page")).unwrap_or("").to_string();
    let claimed: Vec<String> = asked
        .get("claimed")
        .and_then(|v| v.as_array())
        .map(|list| list.iter().filter_map(|v| v.as_str()).map(bare).collect())
        .unwrap_or_default();
    if !was.is_empty() && bare(&was) != bare(&page) && claimed.contains(&bare(&was)) {
        return Err("this film is linked to another project".to_string());
    }
    // `Linking.link`: the three, always; the folder only when it is known, as
    // `--link` writes it only when it found one.
    doc.set(project, "console_page", page.as_str());
    doc.set(project, "console_name", asked.str_field("name").as_str());
    doc.set(project, "drive_url", asked.str_field("drive_url").as_str());
    let folder = asked.str_field("drive_folder");
    if !folder.is_empty() {
        doc.set(project, "drive_folder", folder.as_str());
    }
    films.save()?;
    Ok(Json::object(vec![
        ("ok", Json::Bool(true)),
        ("project", Json::text(project.to_hex())),
        ("was", Json::text(was)),
    ])
    .encode())
}

#[cfg(test)]
mod tests {
    use super::*;
    use shotlister_engine::DeviceId;

    const PAGE: &str = "27fd41c6-9232-85ef-fb41-4614bf2884e0";
    const OTHER: &str = "11111111222233334444555566667777";

    /// A film made the way New Film makes one. Made once per test and the same
    /// text handed round: the engine's id counter runs on, so a second call
    /// would be a different film.
    fn film(link_page: &str) -> String {
        shotlister_engine::id::set_now_millis(1_760_200_000_000);
        shotlister_engine::id::set_seed(41);
        let mut b = Bucket::new("ab".repeat(16).as_str(), "Spare", false, DeviceId(5));
        b.settle();
        let asked = format!(r#"{{"title":"Spare","page":"{link_page}","name":"","drive_url":""}}"#);
        super::super::newfilm::make_film(&mut b, &asked).unwrap();
        b.pending().to_string()
    }

    /// Fetched later: the link is written after the film was made, as it is
    /// on the server (whose clock is set from the real one on every call).
    fn fetched(log: &str, device: u64) -> Bucket {
        let b = logs(&[log], device);
        shotlister_engine::id::set_now_millis(1_760_300_000_000);
        b
    }

    /// The film as another device sees it, from each log in turn.
    fn logs(each: &[&str], device: u64) -> Bucket {
        let mut b = Bucket::new("ab".repeat(16).as_str(), "", false, DeviceId(device));
        for log in each {
            assert_eq!(b.take(log), 0, "every line reads");
        }
        b.settle();
        b
    }

    fn asked(page: &str, claimed: &[&str]) -> String {
        let claimed = claimed.iter().map(|c| format!("\"{c}\"")).collect::<Vec<_>>().join(",");
        format!(
            r#"{{"page":"{page}","name":"Halcyon","drive_url":"https://drive.google.com/drive/folders/1abc","drive_folder":"/Users/x/My Drive/cinematography/projects/halcyon","claimed":[{claimed}]}}"#
        )
    }

    #[test]
    fn a_spare_film_takes_the_four_fields_in_one_log() {
        let made = film("");
        let mut b = fetched(&made, 6);
        let said = shotlister_engine::json::parse(&link_into_film(&mut b, &asked(PAGE, &[OTHER])).unwrap()).unwrap();
        assert_eq!(said.get("ok").and_then(|v| v.as_bool()), Some(true));
        let other = logs(&[&made, b.pending()], 7);
        let doc = other.doc().unwrap();
        let record = doc.get(doc.project_id().unwrap()).unwrap();
        assert_eq!(record.text("console_page"), Some(PAGE));
        assert_eq!(record.text("console_name"), Some("Halcyon"));
        assert_eq!(record.text("drive_url"), Some("https://drive.google.com/drive/folders/1abc"));
        assert_eq!(record.text("drive_folder"), Some("/Users/x/My Drive/cinematography/projects/halcyon"));
    }

    #[test]
    fn a_film_of_another_project_is_refused_and_nothing_written() {
        let mut b = fetched(&film(OTHER), 8);
        let err = link_into_film(&mut b, &asked(PAGE, &[OTHER])).unwrap_err();
        assert!(err.contains("another project"), "{err}");
        assert_eq!(b.pending(), "");
    }

    #[test]
    fn a_film_carrying_a_page_no_project_has_is_a_spare() {
        let mut b = fetched(&film(OTHER), 9);
        link_into_film(&mut b, &asked(PAGE, &[])).unwrap();
        assert!(!b.pending().is_empty());
    }

    #[test]
    fn the_folder_is_left_out_when_it_is_not_known() {
        let made = film("");
        let mut b = fetched(&made, 10);
        link_into_film(&mut b, &format!(r#"{{"page":"{PAGE}","name":"Halcyon","drive_url":""}}"#)).unwrap();
        let other = logs(&[&made, b.pending()], 11);
        let doc = other.doc().unwrap();
        let record = doc.get(doc.project_id().unwrap()).unwrap();
        assert_eq!(record.text("drive_folder").unwrap_or(""), "");
        assert_eq!(record.text("console_page"), Some(PAGE));
    }

    #[test]
    fn no_page_no_record_or_only_reading_is_refused() {
        let mut b = fetched(&film(""), 12);
        assert!(link_into_film(&mut b, r#"{"page":"","name":"x"}"#).is_err());
        let mut empty = Bucket::new("cd".repeat(16).as_str(), "", false, DeviceId(13));
        empty.settle();
        assert!(link_into_film(&mut empty, &asked(PAGE, &[])).unwrap_err().contains("no project record"));
        let mut looking = Bucket::new("ab".repeat(16).as_str(), "", true, DeviceId(14));
        looking.take(&film(""));
        looking.settle();
        assert!(link_into_film(&mut looking, &asked(PAGE, &[])).is_err());
    }
}
