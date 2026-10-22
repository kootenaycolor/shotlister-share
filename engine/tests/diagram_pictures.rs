//! **A picture on a plan has to be a picture the film holds.** Ref 1615.
//!
//! A plan was given an image element naming `<hash>.jpg` for a file that had
//! been put straight into the bucket, so no media record was ever made for
//! it. The portal drew it — it fetches a file from the bucket by name — and
//! his Mac never could: a device learns a file exists from its record, so
//! `missing_media` could not see it, nothing ever asked the relay for it, and
//! sync said "Up to date" while the picture sat blank.

use shotlister_engine::diagram::{EditError, Kind};
use shotlister_engine::media::MediaKind;
use shotlister_engine::{json, DeviceId, Doc};

/// A film with one scene and one picture in it, ready to be laid on a plan.
fn film() -> (Doc, shotlister_engine::Id, String) {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Call Her Back");
    let scene = doc.create_scene("1");
    let hash = shotlister_engine::sha256(b"a photograph of a room");
    doc.add_media(hash, MediaKind::Image, 1920, 1080, 500_000, "room.jpg");
    let hex = hash.to_hex();
    let name = format!("{}.jpg", &hex[..32]);
    (doc, scene, name)
}

#[test]
fn a_picture_the_film_holds_goes_onto_the_plan() {
    let (mut doc, scene, name) = film();
    doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"add","els":[{{"kind":"image","x":0,"y":0,"w":4,"h":3,"media":"{name}"}}]}}"#)).unwrap(),
    )
    .expect("the film holds this one");
    let plan = doc.diagram(scene);
    assert_eq!(plan.els.len(), 1);
    assert_eq!(plan.els[0].media, name);
}

#[test]
fn a_picture_the_film_has_no_file_for_is_refused() {
    let (mut doc, scene, _) = film();
    let made_up = "699bec707ac0acb953e217e99c22dc1f.jpg";
    let said = doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"add","els":[{{"kind":"image","x":0,"y":0,"w":4,"h":3,"media":"{made_up}"}}]}}"#)).unwrap(),
    );
    assert!(matches!(&said, Err(EditError::NoSuchPicture(n)) if n == made_up), "refused, saying which file: {said:?}");
    assert!(doc.diagram(scene).els.is_empty(), "and nothing was written");
    // The sentence has to tell whoever asked what to do instead.
    let words = said.unwrap_err().to_string();
    assert!(words.contains(made_up) && words.contains("floor_picture"), "{words}");
}

#[test]
fn swapping_one_picture_for_a_file_the_film_lacks_is_refused() {
    let (mut doc, scene, name) = film();
    doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"add","els":[{{"kind":"image","x":0,"y":0,"w":4,"h":3,"media":"{name}"}}]}}"#)).unwrap(),
    )
    .unwrap();
    let id = doc.diagram(scene).els[0].id.clone();
    let said = doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"update","id":"{id}","set":{{"media":"d9f50d41da930b06bd36a04d6f341a72.jpg"}}}}"#)).unwrap(),
    );
    assert!(matches!(said, Err(EditError::NoSuchPicture(_))), "{said:?}");
    assert_eq!(doc.diagram(scene).els[0].media, name, "it still draws the picture it had");
}

#[test]
fn one_bad_picture_refuses_the_whole_batch() {
    let (mut doc, scene, name) = film();
    let said = doc.diagram_edit(
        scene,
        &json::parse(&format!(
            r#"{{"op":"batch","ops":[{{"op":"add","els":[{{"kind":"image","media":"{name}","x":0,"y":0,"w":4,"h":3}}]}},{{"op":"add","els":[{{"kind":"image","media":"deadbeefdeadbeefdeadbeefdeadbeef.jpg","x":9,"y":0,"w":4,"h":3}}]}}]}}"#
        ))
        .unwrap(),
    );
    assert!(matches!(said, Err(EditError::NoSuchPicture(_))), "{said:?}");
    assert!(doc.diagram(scene).els.is_empty(), "neither half was written");
}

#[test]
fn everything_else_still_goes_on_a_plan() {
    // The check must not stand in the way of pieces that are not pictures,
    // nor of a picture element carrying no file name at all.
    let (mut doc, scene, _) = film();
    doc.diagram_edit(
        scene,
        &json::parse(r#"{"op":"add","els":[{"kind":"light","sym":"","mark":"dot","x":0,"y":0},{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#).unwrap(),
    )
    .expect("lamps and walls name no file");
    assert_eq!(doc.diagram(scene).els.len(), 2);
}

#[test]
fn a_swapped_picture_moves_its_hold_to_the_new_file() {
    // Without this the element went on holding the picture it no longer
    // draws, and the one it does draw was held by nobody — free to be
    // reclaimed as an orphan once every device had heard.
    let (mut doc, scene, first) = film();
    let other = shotlister_engine::sha256(b"a second photograph");
    doc.add_media(other, MediaKind::Image, 1920, 1080, 400_000, "other.jpg");
    let second = format!("{}.jpg", &other.to_hex()[..32]);

    doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"add","els":[{{"kind":"image","x":0,"y":0,"w":4,"h":3,"media":"{first}"}}]}}"#)).unwrap(),
    )
    .unwrap();
    let id = doc.diagram(scene).els[0].id.clone();
    doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"update","id":"{id}","set":{{"media":"{second}"}}}}"#)).unwrap(),
    )
    .expect("the film holds the second one too");

    assert_eq!(doc.diagram(scene).els[0].media, second);

    // The picture it now draws is held by the element, so nothing counts it
    // an orphan. The one it dropped was held by nobody else, so letting go
    // took its record with it — which is what `release_media_use` does for
    // any owner that lets go, and is why the file can be reclaimed later.
    let records: Vec<String> = doc
        .store()
        .of_kind(&shotlister_engine::store::Kind::Media)
        .iter()
        .filter_map(|r| r.text(shotlister_engine::doc::f::HASH).map(|h| h.chars().take(32).collect()))
        .collect();
    assert!(records.iter().any(|h| *h == second[..32]), "the film still holds the picture on the plan");
    assert!(!records.iter().any(|h| *h == first[..32]), "and has let the dropped one go");
    assert!(doc.orphaned_media().is_empty(), "nothing is left held by nobody");
}

#[test]
fn a_picture_element_is_a_picture_when_it_is_drawn() {
    let (mut doc, scene, name) = film();
    doc.diagram_edit(
        scene,
        &json::parse(&format!(r#"{{"op":"add","els":[{{"kind":"image","x":0,"y":0,"w":4,"h":3,"media":"{name}"}}]}}"#)).unwrap(),
    )
    .unwrap();
    assert_eq!(doc.diagram(scene).els[0].kind, Kind::Image);
}
