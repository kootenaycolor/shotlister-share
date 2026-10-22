//! Per-shot layout on the page, and the rules the printed page must share with
//! the screen.

use shotlister_engine::docstyle::Style;
use shotlister_engine::doc::f;
use shotlister_engine::export::{html, FrameSize, Print};
use shotlister_engine::layout::{FramePosition, MIN_FRAME_WIDTH};
use shotlister_engine::{DeviceId, Doc, GroupBy, Id, Query};

fn project() -> (Doc, Id, Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Frontal Dirty Single on Milo");
    (d, scene, shot)
}

fn page(d: &Doc, group_by: GroupBy) -> String {
    html::document(
            &d.sheet(&Query::grouped_by(group_by)),
        &|_, _| Some(html::Frame { src: "frame.png".to_string(), width: 1600.0, height: 900.0, moments: 1 }),
        Print::Document,
        1.0,"",
            &Style::standard_style(),
        )
}

// ---- the stored value --------------------------------------------------

#[test]
fn a_frame_is_full_measure_until_it_is_told_otherwise() {
    let (d, _, shot) = project();
    assert_eq!(d.frame_width(shot), 1.0);
    assert_eq!(d.frame_position(shot), FramePosition::Below);
}

#[test]
fn width_is_a_fraction_of_the_measure_not_a_size() {
    let (mut d, _, shot) = project();
    d.set_frame_width(shot, 0.4);

    // Stored as a fraction, so changing paper size or margins later cannot
    // silently rescale every frame in the project.
    assert_eq!(d.frame_width(shot), 0.4);
}

#[test]
fn dragging_past_either_end_is_clamped_rather_than_refused() {
    let (mut d, _, shot) = project();

    d.set_frame_width(shot, 3.0);
    assert_eq!(d.frame_width(shot), 1.0, "cannot exceed the measure");

    d.set_frame_width(shot, 0.0);
    assert_eq!(d.frame_width(shot), MIN_FRAME_WIDTH, "cannot vanish");

    d.set_frame_width(shot, f64::NAN);
    assert_eq!(d.frame_width(shot), 1.0, "nonsense falls back");
}

#[test]
fn the_side_the_frame_sits_on_is_remembered() {
    let (mut d, _, shot) = project();
    d.set_frame_position(shot, FramePosition::Left);
    assert_eq!(d.frame_position(shot), FramePosition::Left);

    assert_eq!(FramePosition::parse("beside"), FramePosition::Left);
    assert_eq!(FramePosition::parse("anything else"), FramePosition::Below);
}

// ---- the page agrees with the screen -----------------------------------

#[test]
fn the_printed_page_honours_the_width() {
    let (mut d, _, shot) = project();
    let frame = d.add_media(
        shotlister_engine::sha256(b"f"),
        shotlister_engine::MediaKind::Image,
        1600,
        900,
        10,
        "f.png",
    );
    d.attach_media(shot, frame, "");
    d.set_frame_width(shot, 0.4);

    assert!(page(&d, GroupBy::Scene).contains("width:40%"));
}

#[test]
fn alongside_text_puts_the_frame_in_its_own_column() {
    let (mut d, _, shot) = project();
    let frame = d.add_media(
        shotlister_engine::sha256(b"f"),
        shotlister_engine::MediaKind::Image,
        1600,
        900,
        10,
        "f.png",
    );
    d.attach_media(shot, frame, "");
    d.set_frame_position(shot, FramePosition::Left);
    d.set_frame_width(shot, 0.35);

    let out = page(&d, GroupBy::Scene);
    assert!(out.contains("class=\"shot left\""));
    assert!(out.contains("shot-body"), "text gets its own column");
    assert!(out.contains("flex-basis:35%"));
}

#[test]
fn a_shot_is_never_split_across_a_page_break() {
    let (d, _, _) = project();
    let out = page(&d, GroupBy::Scene);

    // Frame on one page and its technical line on the next would be worse than
    // a short page.
    assert!(out.contains(".shot {") || out.contains(".shot {{"));
    assert!(out.contains("break-inside: avoid"));
    assert!(out.contains("page-break-inside: avoid"));
}

#[test]
fn each_shoot_day_starts_a_fresh_page() {
    let (mut d, scene, _) = project();
    let monday = d.create_day();
    let tuesday = d.create_day();
    let first = d.placements_in_scene(scene)[0];
    d.schedule(first, monday);
    let (_, second) = d.add_shot_to_scene(scene);
    d.schedule(second, tuesday);

    let out = page(&d, GroupBy::Day);
    // The first day does not need one; every day after it does, so a day can be
    // handed out on its own.
    assert_eq!(out.matches("fresh-page").count(), 2, "one rule, one use");
}

#[test]
fn scenes_do_not_each_start_a_fresh_page() {
    let (mut d, _, _) = project();
    let other = d.create_scene("35");
    d.add_shot_to_scene(other);

    let out = page(&d, GroupBy::Scene);
    // Only the stylesheet rule appears; no group carries the class.
    assert_eq!(out.matches("fresh-page").count(), 1);
}
