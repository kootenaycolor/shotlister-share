//! The Media window: every picture, where it is used, deleting for real, and
//! the name a deleted picture leaves behind. `engine::shelf`, SL-1687.

use shotlister_engine::doc::f;
use shotlister_engine::hash::sha256;
use shotlister_engine::media::MediaKind;
use shotlister_engine::{DeviceId, Doc};

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Call Her Back");
    d.set_today(Some("2026-10-10"));
    d.clear_history();
    d
}

#[test]
fn every_picture_says_where_it_is_used_biggest_first() {
    let mut d = project();
    let scene = d.create_scene("12");
    let (shot, _) = d.add_shot_to_scene(scene);
    let place = d.create_location("Ellis House");
    let board = d.create_board("Night");
    let small = d.add_media(sha256(b"a"), MediaKind::Image, 10, 10, 100, "a.jpg");
    let big = d.add_media(sha256(b"b"), MediaKind::Video, 10, 10, 9000, "b.mov");
    let loose = d.add_media(sha256(b"c"), MediaKind::Image, 10, 10, 500, "c.jpg");
    d.attach_media(shot, big, "");
    d.attach_media(place, big, "");
    d.attach_media(board, small, "");

    let shelf = d.shelf();
    assert_eq!(shelf.iter().map(|s| s.media).collect::<Vec<_>>(), vec![big, loose, small]);
    let labels: Vec<&str> = shelf[0].uses.iter().map(|u| u.label.as_str()).collect();
    assert_eq!(labels, vec!["Ellis House", "Shot 12A"]);
    assert_eq!(shelf[0].uses[1].detail, "Scene 12");
    assert_eq!(shelf[2].uses[0].label, "Mood Board \u{b7} Night");
    assert!(!shelf[1].used());
    assert_eq!(d.unused_media(), vec![loose]);
}

#[test]
fn deleting_takes_every_use_and_keeps_the_name() {
    let mut d = project();
    let scene = d.create_scene("4");
    let (shot, _) = d.add_shot_to_scene(scene);
    let pic = d.add_media(sha256(b"frame"), MediaKind::Image, 10, 10, 2048, "IMG_4410.HEIC");
    d.attach_media(shot, pic, "");

    let hashes = d.delete_media(&[pic]);
    assert_eq!(hashes, vec![sha256(b"frame").to_hex()]);
    assert!(d.media_refs(shot).is_empty(), "the shot lost it");
    assert!(d.shelf().is_empty());
    let gone = d.gone_media();
    assert_eq!(gone.len(), 1);
    assert_eq!(gone[0].filename, "IMG_4410.HEIC");
    assert_eq!(gone[0].bytes, 2048);
    assert!(!d.can_undo(), "a real delete; undo would only bring back a hole");
    assert!(d.orphaned_media().is_empty(), "the open-time tidy-up must not take the name");
    let name = format!("{}.heic", &sha256(b"frame").to_hex()[..32]);
    assert_eq!(d.stray_media_names([name.as_str()]), vec![name.clone()], "its files are strays");
}

#[test]
fn going_back_brings_a_gap_with_the_name_and_dropping_it_in_again_fills_it() {
    let mut d = project();
    let scene = d.create_scene("9");
    let (shot, _) = d.add_shot_to_scene(scene);
    let pic = d.add_media(sha256(b"clip"), MediaKind::Video, 10, 10, 22, "IMG_4410.MOV");
    d.attach_media(shot, pic, "");
    let v = d.save_version("Friday");
    assert_eq!(d.shelf()[0].versions, 1);

    d.delete_media(&[pic]);
    d.go_back_to(v).unwrap();
    assert_eq!(d.media_refs(shot).len(), 1, "the use is back");
    assert!(d.media_is_gone(pic), "the picture is not");
    assert_eq!(d.get(pic).unwrap().text(f::FILENAME), Some("IMG_4410.MOV"));

    let again = d.add_media(sha256(b"clip"), MediaKind::Video, 10, 10, 22, "IMG_4410.MOV");
    assert_eq!(again, pic);
    assert!(!d.media_is_gone(pic));
    assert_eq!(d.shelf()[0].uses.len(), 1);
}

#[test]
fn a_use_whose_shot_is_gone_counts_as_unused() {
    let mut d = project();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    let pic = d.add_media(sha256(b"x"), MediaKind::Image, 10, 10, 1, "x.png");
    let use_ = d.attach_media(shot, pic, "");
    // A shot removed on a device that left its use behind.
    d.delete(shot);
    assert!(d.get(use_).is_some());
    assert_eq!(d.unused_media(), vec![pic]);
    d.delete_media(&[pic]);
    assert!(d.get(use_).is_none());
}
