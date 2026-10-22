//! The share page: one file, frames inside it, and honest about what it is.

use shotlister_engine::doc::f;
use shotlister_engine::export::share::{self, ShareFrame, ShareOptions};
use shotlister_engine::media::MediaKind;
use shotlister_engine::{sha256, DeviceId, Doc, GroupBy, Id, Query};

fn project() -> (Doc, Id, Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    d.set(scene, f::LOCATION, "car");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Frontal Dirty Single on Milo");
    d.set(shot, f::NOTES, "Frame is a way to hide 2 cameras");
    d.set_vocab_field(shot, "size", "M/OTS");
    d.set_vocab_field(shot, "lens", "37mm");
    (d, scene, shot)
}

fn page(d: &Doc, options: &ShareOptions) -> String {
    share::page(
        &d.sheet(&Query::grouped_by(GroupBy::Scene)),
        &share::no_frames,
        options,
    )
}

// ---- encoding ----------------------------------------------------------

#[test]
fn base64_matches_the_published_vectors() {
    assert_eq!(share::base64(b""), "");
    assert_eq!(share::base64(b"f"), "Zg==");
    assert_eq!(share::base64(b"fo"), "Zm8=");
    assert_eq!(share::base64(b"foo"), "Zm9v");
    assert_eq!(share::base64(b"foob"), "Zm9vYg==");
    assert_eq!(share::base64(b"fooba"), "Zm9vYmE=");
    assert_eq!(share::base64(b"foobar"), "Zm9vYmFy");
}

#[test]
fn a_frame_becomes_part_of_the_page() {
    let (mut d, _, shot) = project();
    let media = d.add_media(sha256(b"x"), MediaKind::Image, 1600, 900, 3, "f.png");
    d.attach_media(shot, media, "");

    let out = share::page(
        &d.sheet(&Query::grouped_by(GroupBy::Scene)),
        &|id| {
            (id == media).then(|| ShareFrame {
                bytes: b"foobar".to_vec(),
                mime: "image/png".to_string(),
                width: 1600.0,
                height: 900.0,
            })
        },
        &ShareOptions::made_on("16 August 2026"),
    );

    // No network, no folder of files alongside — the frame is in the file.
    assert!(out.contains("data:image/png;base64,Zm9vYmFy"));
    assert!(!out.contains("src=\"f.png\""));
}

// ---- what it says about itself -----------------------------------------

#[test]
fn the_page_says_when_it_was_made_and_what_it_is() {
    let (d, _, _) = project();
    let out = page(&d, &ShareOptions::made_on("16 August 2026"));

    assert!(out.contains("Shared 16 August 2026"));
    // A file cannot know the list moved on, so it must not imply otherwise.
    assert!(out.contains("<footer"));
    assert!(out.contains("a snapshot of the list"));
    assert!(out.contains("not a live view"));
}

#[test]
fn without_a_date_there_is_no_claim_at_all() {
    let (d, _, _) = project();
    let out = page(&d, &ShareOptions::default());
    // The word lives in the stylesheet too, so check for the element itself.
    assert!(!out.contains("<footer"));
}

// ---- what leaves the building ------------------------------------------

#[test]
fn everything_goes_out_unless_it_is_held_back() {
    let (d, _, _) = project();
    let out = page(&d, &ShareOptions::made_on("today"));

    assert!(out.contains("Frontal Dirty Single on Milo"));
    assert!(out.contains("Frame is a way to hide 2 cameras"));
    assert!(out.contains("M/OTS"));
}

#[test]
fn crew_shorthand_can_stay_in_the_building() {
    let (d, _, _) = project();
    let out = page(&d, &ShareOptions::made_on("today").without_notes());

    assert!(!out.contains("hide 2 cameras"));
    // The shot itself still goes out.
    assert!(out.contains("Frontal Dirty Single on Milo"));
}

#[test]
fn the_technical_line_can_stay_in_the_building() {
    let (d, _, _) = project();
    let out = page(&d, &ShareOptions::made_on("today").without_technical());

    assert!(!out.contains("M/OTS"));
    assert!(!out.contains("37mm"));
    assert!(out.contains("Frontal Dirty Single on Milo"));
}

#[test]
fn a_cut_shot_can_be_kept_to_yourself() {
    let (mut d, scene, shot) = project();
    let (kept, _) = d.add_shot_to_scene(scene);
    d.set(kept, f::DESCRIPTION, "The one we are still doing");
    d.strike(shot, true);

    let shown = page(&d, &ShareOptions::made_on("today"));
    assert!(shown.contains("Frontal Dirty Single on Milo"));

    let hidden = page(&d, &ShareOptions::made_on("today").without_struck());
    assert!(!hidden.contains("Frontal Dirty Single on Milo"));
    assert!(hidden.contains("The one we are still doing"));
}

#[test]
fn a_group_left_empty_by_a_choice_does_not_appear() {
    let (mut d, _, shot) = project();
    d.strike(shot, true);

    let out = page(&d, &ShareOptions::made_on("today").without_struck());
    // The only shot in scene 34 was struck, so the scene should not show as an
    // empty heading.
    assert!(!out.contains("Scene 34"));
}

#[test]
fn the_page_has_no_way_to_write_anything() {
    let (d, _, _) = project();
    let out = page(&d, &ShareOptions::made_on("today"));

    // Not the editor with its buttons hidden — there is nothing to reach.
    assert!(!out.contains("<input"));
    assert!(!out.contains("<button"));
    assert!(!out.contains("<form"));
    assert!(!out.contains("contenteditable"));
    assert!(!out.contains("<script"));
}
