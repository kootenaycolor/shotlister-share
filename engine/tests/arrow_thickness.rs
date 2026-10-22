//! **An arrow's thickness stays with the arrow** (2026-10-15: "the thickness
//! slider on arrows doesn't stay — it always resets to its default").
//!
//! Every edit the arrow's bar makes, every save through the record, and every
//! reload must leave the thickness exactly as it was (to the 0.01 the line
//! writes). Reset Widths resets widths only.

use shotlister_engine::arrow::{Arrow, ArrowDepth, ArrowLook, ArrowShape, ArrowStance};
use shotlister_engine::hash::{Hash256, Sha256};
use shotlister_engine::media::MediaKind;
use shotlister_engine::{DeviceId, Doc};

fn still(bytes: &[u8]) -> Hash256 {
    let mut h = Sha256::new();
    h.update(bytes);
    h.finish()
}

fn a_use(d: &mut Doc) -> shotlister_engine::id::Id {
    let scene = d.create_scene("34");
    let file = d.add_media(still(b"a frame"), MediaKind::Image, 1920, 1080, 400_000, "frame.jpg");
    d.attach_media(scene, file, "")
}

fn thick(t: f64) -> Arrow {
    let mut a = Arrow::straight(0.2, 0.8, 0.7, 0.3);
    a.thickness = t;
    a
}

fn same(a: f64, b: f64) -> bool {
    (a - b).abs() < 0.0051
}

#[test]
fn every_thickness_survives_the_stored_line() {
    let mut t = 0.5;
    while t <= 3.0001 {
        for build in [
            thick(t),
            { let mut a = thick(t); a.depth = ArrowDepth::Away; a.stance = ArrowStance::Standing; a },
            { let mut a = thick(t); a.widths = Some([0.03, 0.06]); a },
            { let mut a = thick(t); a.look = ArrowLook::Red; a.dashed = true; a.heads = 2; a },
            { let mut a = Arrow::zoom_mark(shotlister_engine::arrow::ZoomDir::In); a.thickness = t; a.held() },
        ] {
            let line = Arrow::encode(&[build.clone()]);
            let read = Arrow::parse(&line);
            assert_eq!(read.len(), 1, "{line}");
            assert!(same(read[0].thickness, t), "{t} became {} in {line}", read[0].thickness);
            // …and again: reading and writing it a second time moves nothing.
            let again = Arrow::parse(&Arrow::encode(&read));
            assert!(same(again[0].thickness, t), "{t} drifted to {} in {line}", again[0].thickness);
        }
        t += 0.05;
    }
}

#[test]
fn every_edit_of_the_bar_keeps_the_thickness() {
    let edits: Vec<(&str, Box<dyn Fn(&mut Arrow)>)> = vec![
        ("Toward", Box::new(|a| { a.depth = ArrowDepth::Toward; a.widths = None; })),
        ("Away", Box::new(|a| { a.depth = ArrowDepth::Away; a.widths = None; })),
        ("Flat", Box::new(|a| { a.depth = ArrowDepth::Flat; a.widths = None; })),
        ("Standing", Box::new(|a| a.stance = ArrowStance::Standing)),
        ("Floor", Box::new(|a| a.stance = ArrowStance::Floor)),
        ("Reset Widths", Box::new(|a| a.widths = None)),
        ("widths dragged", Box::new(|a| a.widths = Some([0.05, 0.02]))),
        ("Straighten", Box::new(|a| a.pins.clear())),
        ("Corner", Box::new(|a| { a.shape = ArrowShape::Corner; a.pins = vec![(0.5, 0.5)]; })),
        ("colour", Box::new(|a| a.look = ArrowLook::Yellow)),
        ("dashed", Box::new(|a| a.dashed = true)),
        ("both ends", Box::new(|a| a.heads = 2)),
        ("end dragged", Box::new(|a| { a.x2 = 0.9; a.y2 = 0.1; })),
    ];
    for t in [0.5, 0.75, 1.3, 2.0, 2.65, 3.0] {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Daybreak");
        let use_of_it = a_use(&mut d);
        d.set_media_arrows(use_of_it, &[thick(t)]);
        for (name, edit) in &edits {
            let mut read = d.media_arrows(use_of_it);
            edit(&mut read[0]);
            d.set_media_arrows(use_of_it, &read);
            let back = d.media_arrows(use_of_it);
            assert!(same(back[0].thickness, t), "{name} turned thickness {t} into {}", back[0].thickness);
        }
    }
}

#[test]
fn reset_widths_resets_widths_and_nothing_else() {
    let mut a = thick(2.2);
    a.widths = Some([0.04, 0.08]);
    a.depth = ArrowDepth::Toward;
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let u = a_use(&mut d);
    d.set_media_arrows(u, &[a]);
    let mut read = d.media_arrows(u);
    assert!(read[0].widths.is_some());
    read[0].widths = None;
    d.set_media_arrows(u, &read);
    let back = d.media_arrows(u);
    assert!(back[0].widths.is_none());
    assert!(same(back[0].thickness, 2.2));
    assert_eq!(back[0].depth, ArrowDepth::Toward);
}

#[test]
fn a_second_arrow_does_not_disturb_the_first_ones_thickness() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let u = a_use(&mut d);
    d.set_media_arrows(u, &[thick(2.4)]);
    let mut all = d.media_arrows(u);
    all.push(thick(1.0));
    all.push(thick(0.6));
    d.set_media_arrows(u, &all);
    let back = d.media_arrows(u);
    assert!(same(back[0].thickness, 2.4) && same(back[1].thickness, 1.0) && same(back[2].thickness, 0.6));
}

#[test]
fn an_older_line_without_thick_still_reads_and_an_unknown_token_costs_nothing() {
    // A newer writer's extra token is ignored; the thickness beside it holds.
    let r = Arrow::parse("0.1,0.1,0.5,0.5,0.9,0.9,1,w:L,thick:2.40,somethingnew:1:2");
    assert!(same(r[0].thickness, 2.4));
}
