//! **Edit Reference, the first mod**: a clip joined to a run of shots, the
//! brackets drawn from it, and what an older or a mod-less film answers.

use shotlister_engine::hash::sha256;
use shotlister_engine::json;
use shotlister_engine::media::MediaKind;
use shotlister_engine::store::Kind;
use shotlister_engine::view::{describe, Asked, Standing};
use shotlister_engine::{DeviceId, Doc, Id};

fn film() -> (Doc, Id, Vec<Id>) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("ZZ Mods");
    let scene = d.create_scene("34");
    let shots: Vec<Id> = (0..5).map(|_| d.add_shot_to_scene(scene).0).collect();
    (d, scene, shots)
}

fn view(d: &Doc) -> String {
    describe(d, &Asked::default().looking(), &Standing { read_only: false, unsaved: 0, device_clash: None })
}

fn clip(d: &mut Doc, owner: Id, seconds: f64) -> Id {
    let media = d.add_media(sha256(b"car cut"), MediaKind::Video, 1920, 1080, 9_000_000, "car_argument_ref.mov");
    d.set_media_duration(media, seconds);
    d.attach_media(owner, media, "")
}

#[test]
fn a_film_with_none_answers_exactly_as_before() {
    let (d, _, _) = film();
    let v = view(&d);
    assert!(!v.contains("editRefs") && !v.contains("editSpans"), "no new keys for a film with no edit reference");
}

#[test]
fn one_joins_shots_in_cut_order_and_shares_the_clip_evenly() {
    let (mut d, _, s) = film();
    let e = d.create_edit_ref("Car cut", &[s[0], s[1], s[2], s[3]]);
    clip(&mut d, e, 12.0);
    let got = d.edit_ref(e).unwrap();
    assert_eq!(got.name, "Car cut");
    assert_eq!(got.shots, vec![s[0], s[1], s[2], s[3]]);
    assert_eq!(got.length, 12.0);
    assert_eq!(got.starts, vec![0.0, 3.0, 6.0, 9.0]);
    assert_eq!(d.edit_refs_of_shot(s[2]), vec![e]);
    assert!(d.edit_refs_of_shot(s[4]).is_empty());
}

#[test]
fn starts_set_by_hand_must_go_forwards_and_fit_the_shots() {
    let (mut d, _, s) = film();
    let e = d.create_edit_ref("Car cut", &[s[0], s[1], s[2], s[3]]);
    clip(&mut d, e, 12.0);
    assert!(!d.set_edit_ref_starts(e, &[0.0, 3.0]));
    assert!(!d.set_edit_ref_starts(e, &[0.0, 5.0, 3.0, 9.0]));
    assert!(d.set_edit_ref_starts(e, &[0.0, 3.0, 5.0, 9.0]));
    assert_eq!(d.edit_ref(e).unwrap().starts, vec![0.0, 3.0, 5.0, 9.0]);
    // a different run of shots starts evenly again
    d.set_edit_ref_shots(e, &[s[0], s[1]]);
    assert_eq!(d.edit_ref(e).unwrap().starts, vec![0.0, 6.0]);
}

#[test]
fn the_bracket_spans_each_run_of_rows_it_joins() {
    let (mut d, _, s) = film();
    let e = d.create_edit_ref("Car cut", &[s[0], s[1], s[3]]);
    assert_eq!(d.edit_spans(&s), vec![(e, 0, 1), (e, 3, 3)]);
    let v = json::parse(&view(&d)).unwrap();
    let group = &v.get("groups").unwrap().as_array().unwrap()[0];
    let spans = group.get("editSpans").unwrap().as_array().unwrap();
    assert_eq!(spans.len(), 2);
    assert_eq!(spans[0].get("from").unwrap().as_f64(), Some(0.0));
    assert_eq!(spans[0].get("to").unwrap().as_f64(), Some(1.0));
    let refs = v.get("editRefs").unwrap().as_array().unwrap();
    assert_eq!(refs[0].get("name").unwrap().as_str(), Some("Car cut"));
    assert_eq!(refs[0].get("shots").unwrap().as_array().unwrap().len(), 3);
}

#[test]
fn a_deleted_shot_drops_out_and_deleting_it_leaves_the_shots() {
    let (mut d, _, s) = film();
    let e = d.create_edit_ref("Car cut", &[s[0], s[1], s[2]]);
    d.delete(s[1]);
    assert_eq!(d.edit_ref_shots(e), vec![s[0], s[2]]);
    d.delete_edit_ref(e);
    assert!(d.edit_refs_in_order().is_empty());
    assert!(d.get(s[0]).is_some() && d.get(s[2]).is_some());
}

#[test]
fn undo_takes_back_the_add() {
    let (mut d, _, s) = film();
    d.create_edit_ref("Car cut", &[s[0], s[1]]);
    assert_eq!(d.edit_refs_in_order().len(), 1);
    d.undo();
    assert!(d.edit_refs_in_order().is_empty());
}

#[test]
fn an_older_reader_keeps_it_whole() {
    assert_eq!(Kind::parse("edit_ref"), Kind::EditRef);
    assert_eq!(Kind::EditRef.as_str(), "edit_ref");
    // a newer kind than this reader knows is held as Other, never dropped
    assert_eq!(Kind::parse("song_map"), Kind::Other("song_map".into()));
}

#[test]
fn it_travels_through_the_log() {
    let (mut d, _, s) = film();
    let e = d.create_edit_ref("Car cut", &[s[0], s[1]]);
    d.set_edit_ref_link(e, "https://vimeo.com/1");
    let mut other = Doc::new(DeviceId(2));
    other.merge(d.changes().to_vec());
    let got = other.edit_ref(e).unwrap();
    assert_eq!(got.shots, vec![s[0], s[1]]);
    assert_eq!(got.link, "https://vimeo.com/1");
}

/// His note, 2026-10-17: 14A, 14B and 15A in one edit reference drew two
/// brackets, split at scene 15's heading. One run across the heading now.
#[test]
fn the_bracket_runs_across_a_scene_heading() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("ZZ Across");
    let s14 = d.create_scene("14");
    let a: Vec<Id> = (0..3).map(|_| d.add_shot_to_scene(s14).0).collect();
    let empty = d.create_scene("14X");
    let s15 = d.create_scene("15");
    let b: Vec<Id> = (0..2).map(|_| d.add_shot_to_scene(s15).0).collect();
    let _ = empty;
    let e = d.create_edit_ref("Anya", &[a[1], a[2], b[0]]);
    let across = d.edit_spans_across(&[a.clone(), vec![], b.clone()]);
    assert_eq!(across[0].spans.len(), 1);
    assert!(!across[0].spans[0].before && across[0].spans[0].after, "14 carries on below");
    assert_eq!(across[1].through, vec![e], "the empty scene between is passed through");
    assert!(across[2].spans[0].before && !across[2].spans[0].after, "15 carries on from above");
    // a run that stops short of the heading does not carry
    let f = d.create_edit_ref("Short", &[a[0], b[1]]);
    let across = d.edit_spans_across(&[a.clone(), b.clone()]);
    let short: Vec<_> = across.iter().flat_map(|g| g.spans.iter().filter(|s| s.edit == f)).collect();
    assert!(short.iter().all(|s| !s.before && !s.after));
    // and the view says so on each scene
    let v = json::parse(&view(&d)).unwrap();
    let groups = v.get("groups").unwrap().as_array().unwrap();
    let said: Vec<String> = groups
        .iter()
        .filter_map(|g| g.get("editSpans"))
        .flat_map(|s| s.as_array().unwrap().iter())
        .filter(|s| s.get("ref").unwrap().as_str() == Some(&e.0.to_string()))
        .map(|s| format!("{}{}", s.get("before").is_some(), s.get("after").is_some()))
        .collect();
    assert_eq!(said, vec!["falsetrue", "truefalse"]);
    // (a scene with no shots is no group in the view, so nothing passes it there)
}
