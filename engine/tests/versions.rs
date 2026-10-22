//! Versions: the film as it stood at a moment, looked at and brought back.
//!
//! What has to hold, in the order he will lean on it: an old version shows
//! exactly what was there then and nothing since; a scene deleted since comes
//! back with its shots and pictures; going back over the whole film is one
//! undo and leaves today saved as a version; and a picture a version shows is
//! never swept away.

use shotlister_engine::doc::f;
use shotlister_engine::hash::sha256;
use shotlister_engine::media::MediaKind;
use shotlister_engine::versions::{Cut, Made};
use shotlister_engine::{DeviceId, Doc};

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Call Her Back");
    d.set_today(Some("2026-09-29"));
    d.clear_history();
    d
}

fn lens(d: &Doc, shot: shotlister_engine::Id) -> Option<String> {
    d.get(shot).and_then(|r| r.text("lens").map(str::to_string))
}

#[test]
fn a_cut_survives_being_written_down() {
    let mut d = project();
    d.create_scene("1");
    let cut = Cut::of(&d.store().frontier());
    assert_eq!(Cut::decode(&cut.encode()), Some(cut));
    assert_eq!(Cut::decode("1.2"), None);
}

#[test]
fn an_old_version_shows_what_was_there_and_nothing_since() {
    let mut d = project();
    let scene = d.create_scene("12");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "35mm");
    let v = d.save_version("Before restructure");

    d.set_vocab_field(shot, "lens", "85mm");
    let later = d.create_scene("13");

    let then = d.as_of(v).expect("the version rebuilds");
    assert_eq!(lens(&then, shot).as_deref(), Some("35mm"));
    assert!(then.get(later).is_none(), "made after: not there");
    assert!(then.versions().is_empty(), "a version does not hold itself");
    // And today is untouched by looking.
    assert_eq!(lens(&d, shot).as_deref(), Some("85mm"));
}

#[test]
fn saving_one_is_not_something_undo_takes_back() {
    let mut d = project();
    let scene = d.create_scene("1");
    d.clear_history();
    d.set(scene, "notes", "a");
    d.save_version("Mine");
    d.undo();
    assert_eq!(d.versions().len(), 1, "undo went past the version to the edit");
    assert_eq!(d.get(scene).unwrap().text("notes"), None);
}

#[test]
fn the_list_is_newest_first_and_says_who_made_each() {
    let mut d = project();
    d.create_scene("1");
    let a = d.save_version("First");
    d.create_scene("2");
    let b = d.save_version_made("", Made::Daily);
    let all = d.versions();
    assert_eq!(all.len(), 2);
    assert!(all.iter().any(|v| v.id == a && v.made == Made::Hand && v.name == "First"));
    assert!(all.iter().any(|v| v.id == b && v.made == Made::Daily && v.day == "2026-09-29"));
    assert!(all[0].taken >= all[1].taken);

    assert!(d.rename_version(a, "  Renamed "));
    assert_eq!(d.version(a).unwrap().name, "Renamed");
    assert!(d.delete_version(b));
    assert_eq!(d.versions().len(), 1);
}

#[test]
fn a_deleted_scene_comes_back_with_its_shots_and_pictures() {
    let mut d = project();
    let scene = d.create_scene("12");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "35mm");
    let pic = d.add_media(sha256(b"frame"), MediaKind::Image, 100, 100, 10, "f.png");
    d.attach_media(shot, pic, "");
    let other = d.create_scene("40");
    let v = d.save_version("Before");

    d.delete_scene(scene);
    d.set(other, "notes", "kept");
    assert!(d.get(scene).is_none());
    assert!(d.get(pic).is_none(), "its last use went, so the file's record went too");

    d.clear_history();
    let brought = d.bring_back(v, &[scene]).unwrap();
    assert!(brought.records > 0);
    assert!(d.get(scene).is_some());
    assert!(d.placements_in_scene(scene).len() == 1, "its shot is in it again");
    assert_eq!(lens(&d, shot).as_deref(), Some("35mm"));
    assert!(d.get(pic).is_some(), "and its picture");
    assert_eq!(d.media_refs(shot).len(), 1);
    assert_eq!(d.get(other).unwrap().text("notes"), Some("kept"), "nothing else touched");

    // One step to take back.
    d.undo();
    assert!(d.get(scene).is_none());
    assert!(!d.can_undo());
}

#[test]
fn a_piece_comes_back_as_it_was_not_a_mixture() {
    let mut d = project();
    let scene = d.create_scene("7");
    let (a, _) = d.add_shot_to_scene(scene);
    let v = d.save_version("Before");
    let (b, _) = d.add_shot_to_scene(scene);
    assert_eq!(d.placements_in_scene(scene).len(), 2);

    d.bring_back(v, &[scene]);
    let shots: Vec<_> = d
        .placements_in_scene(scene)
        .into_iter()
        .filter_map(|p| d.get(p).and_then(|r| r.ref_id(f::SHOT)))
        .collect();
    assert_eq!(shots, vec![a], "the shot added since is not in it: {b}");
}

#[test]
fn going_back_is_one_undo_and_keeps_today_as_a_version() {
    let mut d = project();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "35mm");
    let v = d.save_version("Friday");

    d.set_vocab_field(shot, "lens", "85mm");
    let added = d.create_scene("2");
    d.delete_scene(scene);
    d.clear_history();

    let brought = d.go_back_to(v).unwrap();
    let saved = brought.saved.expect("today was saved first");
    assert_eq!(d.version(saved).unwrap().made, Made::GoingBack);
    assert!(d.version(saved).unwrap().name.contains("Friday"));
    assert!(d.get(scene).is_some());
    assert!(d.get(added).is_none());
    assert_eq!(lens(&d, shot).as_deref(), Some("35mm"));
    assert_eq!(d.versions().len(), 2, "every version kept, the one about to be left included");

    // Today, still there under the version saved on the way.
    let today = d.as_of(saved).unwrap();
    assert!(today.get(added).is_some());
    assert!(today.get(scene).is_none());

    d.undo();
    assert!(d.get(added).is_some());
    assert!(d.get(scene).is_none());
    // The shot went with its scene, so it is read as a tombstone.
    let raw = d.store().get_raw(shot).unwrap();
    assert!(raw.is_deleted());
    assert_eq!(raw.text("lens"), Some("85mm"));
}

#[test]
fn going_back_leaves_the_films_name_and_icon_alone() {
    let mut d = project();
    let film = d.store().of_kind(&shotlister_engine::store::Kind::Project)[0].id;
    let v = d.save_version("Old");
    d.set(film, f::TITLE, "Call Her Back (recut)");
    d.set(film, f::DIRECTOR, "Someone");
    d.go_back_to(v);
    assert_eq!(d.get(film).unwrap().text(f::TITLE), Some("Call Her Back (recut)"));
    assert_eq!(d.get(film).unwrap().text(f::DIRECTOR), None, "but its settings go back");
}

#[test]
fn since_counts_what_changed() {
    let mut d = project();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    let v = d.save_version("Then");
    assert!(d.since(v).unwrap().is_empty());

    d.set_vocab_field(shot, "lens", "50mm");
    d.create_scene("2");
    d.create_scene("3");
    let words = d.since(v).unwrap().words();
    assert!(words.contains(&"2 scenes added".to_string()), "{words:?}");
    assert!(words.contains(&"1 shot changed".to_string()), "{words:?}");
}

#[test]
fn a_picture_a_version_shows_is_never_swept() {
    let mut d = project();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    let hash = sha256(b"the frame");
    let pic = d.add_media(hash, MediaKind::Image, 100, 100, 10, "f.jpg");
    let use_ = d.attach_media(shot, pic, "");
    let stem: String = hash.to_hex().chars().take(32).collect();
    let file = format!("{stem}.jpg");

    // Without a version: removed means swept.
    d.detach_media(use_);
    assert_eq!(d.stray_media_names([file.as_str()]), vec![file.clone()]);
    d.undo();

    // With one: the file stays named, and the record is no orphan.
    let v = d.save_version("With the frame");
    d.detach_media(use_);
    assert!(d.media_kept_by_versions().contains(&pic));
    assert!(d.stray_media_names([file.as_str()]).is_empty());
    assert!(d.orphaned_media().is_empty());

    // Put the version away and the picture is free to go.
    d.delete_version(v);
    assert_eq!(d.stray_media_names([file.as_str()]), vec![file]);
}

#[test]
fn a_daily_version_once_a_day_and_only_if_something_changed() {
    let mut d = project();
    let scene = d.create_scene("1");
    assert!(d.daily_version().is_some(), "changed, none today");
    assert!(d.daily_version().is_none(), "already one today");

    d.set_today(Some("2026-09-30"));
    assert!(d.daily_version().is_none(), "nothing changed since");
    d.set(scene, "notes", "new day");
    let daily = d.daily_version().expect("a new day and a change");
    assert_eq!(d.version(daily).unwrap().day, "2026-09-30");
    assert_eq!(d.version(daily).unwrap().name, "");
}

#[test]
fn a_new_draft_leaves_a_version_behind() {
    // Taking a draft goes through `take_revision`; its own tests cover what it
    // does. Here only that the film before it is kept, and named for it.
    let mut d = project();
    d.create_scene("1");
    d.save_version_made("Before draft \u{201c}Pink\u{201d}", Made::Draft);
    let v = &d.versions()[0];
    assert_eq!(v.made, Made::Draft);
    assert!(v.made.automatic());
}
