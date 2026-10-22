//! Print Frame and the arrow toolkit (2026-10-14, `design/45-print-frame.html`).

use shotlister_engine::arrow::{Arrow, ArrowDepth, ArrowLook, ArrowShape};
use shotlister_engine::doc::f;
use shotlister_engine::export::{html, rows::Sheet, FrameSize, Print};
use shotlister_engine::media::MediaKind;
use shotlister_engine::printframe::{Baked, Moment, PrintFrame};
use shotlister_engine::{sha256, DeviceId, Doc, GroupBy, Id, Query};

// ---- arrows -------------------------------------------------------------

fn toolkit_arrow() -> Arrow {
    let mut a = Arrow::through(&[(0.1, 0.2), (0.3, 0.1), (0.5, 0.4), (0.7, 0.15), (0.9, 0.3)]).unwrap();
    a.shape = ArrowShape::Corner;
    a.heads = 0;
    a.dashed = true;
    a.look = ArrowLook::Red;
    a.thickness = 1.4;
    a
}

#[test]
fn a_new_arrow_survives_the_stored_line() {
    let drawn = vec![toolkit_arrow(), Arrow::straight(0.1, 0.9, 0.8, 0.9)];
    let line = Arrow::encode(&drawn);
    let read = Arrow::parse(&line);
    assert_eq!(read.len(), 2);
    let a = &read[0];
    assert_eq!(a.pins.len(), 3);
    assert!((a.pins[1].0 - 0.5).abs() < 1e-4 && (a.pins[1].1 - 0.4).abs() < 1e-4);
    assert_eq!(a.shape, ArrowShape::Corner);
    assert_eq!(a.heads, 0);
    assert!(a.dashed);
    assert_eq!(a.look, ArrowLook::Red);
    assert_eq!(a.thickness, 1.4);
    assert!(line.contains(",w:L") && !line.contains("thick:"), "L is still written the old way: {line}");
    assert!(read[1].pins.is_empty());
    assert_eq!(read[1].heads, 1);
    // And again: the same line every time.
    assert_eq!(Arrow::encode(&read), line);
}

#[test]
fn an_arrow_drawn_before_pins_reads_as_before_and_keeps_its_line() {
    // A bend off the line is one pin at the curve's own middle.
    let old = "0.1000,0.8000,0.4000,0.5000,0.7500,0.3500,1";
    let read = Arrow::parse(old);
    assert_eq!(read[0].pins.len(), 1);
    let (px, py) = read[0].pins[0];
    assert!((px - (0.1 + 0.8 + 0.75) / 4.0).abs() < 1e-9);
    assert!((py - (0.8 + 1.0 + 0.35) / 4.0).abs() < 1e-9);
    assert_eq!(read[0].shape, ArrowShape::Smooth);
    assert!(!read[0].dashed);
    assert_eq!(read[0].look, ArrowLook::Light);
    assert_eq!(read[0].thickness, 1.0);
    assert_eq!(read[0].depth, ArrowDepth::Flat);
    // Nothing he drew changes: written back, it is the same seven numbers.
    assert_eq!(Arrow::encode(&read), old);

    // A bend on the straight line is no pin at all.
    let straight = Arrow::parse("0.1,0.1,0.5,0.5,0.9,0.9,2");
    assert!(straight[0].pins.is_empty());
    assert_eq!(straight[0].heads, 2);
}

/// `Arrow::parse` as it stood before pins (and as the installed iPhone build
/// and the portal still run it): split on `,`, keep what parses as a number,
/// use the first seven.
fn old_reader(line: &str) -> Vec<[f64; 7]> {
    line.split(';')
        .filter(|p| !p.trim().is_empty())
        .filter_map(|piece| {
            let n: Vec<f64> = piece.split(',').filter_map(|p| p.trim().parse::<f64>().ok()).collect();
            if n.len() < 6 || n.iter().any(|v| !v.is_finite()) {
                return None;
            }
            let heads = if n.len() > 6 && n[6] >= 2.0 { 2.0 } else { 1.0 };
            Some([n[0], n[1], n[2], n[3], n[4], n[5], heads])
        })
        .collect()
}

#[test]
fn an_older_reader_still_draws_a_sensible_arrow_from_the_new_line() {
    let line = Arrow::encode(&[toolkit_arrow(), Arrow::straight(0.2, 0.2, 0.6, 0.2)]);
    let old = old_reader(&line);
    assert_eq!(old.len(), 2, "an older reader must not drop a new arrow: {line}");
    let [x1, y1, bx, by, x2, y2, heads] = old[0];
    assert_eq!((x1, y1, x2, y2), (0.1, 0.2, 0.9, 0.3));
    assert_eq!(heads, 1.0, "no heads reads as one head to an older reader");
    // The old quadratic passes through the middle pin at its middle.
    let mid = ((x1 + 2.0 * bx + x2) / 4.0, (y1 + 2.0 * by + y2) / 4.0);
    assert!((mid.0 - 0.5).abs() < 1e-3 && (mid.1 - 0.4).abs() < 1e-3, "{mid:?}");
    // And Swift's `Double(_:)` refuses the same tokens Rust's parse does: none
    // of them is a bare number, `nan` or `inf`.
    for token in line.split([',', ';']) {
        let t = token.trim().to_lowercase();
        if t.parse::<f64>().is_err() {
            assert!(t.starts_with(|c: char| c.is_ascii_alphabetic() && c != 'i' && c != 'n'), "{t}");
        }
    }
}

/// `Arrow::outline` as it stood before pins — the shape every arrow he has
/// drawn so far was printed with.
fn old_outline(a: (f64, f64), b: (f64, f64), c: (f64, f64), heads: u8) -> Vec<(f64, f64)> {
    let mut points = Vec::new();
    let mut lengths = vec![0.0];
    for i in 0..=40 {
        let t = i as f64 / 40.0;
        let u = 1.0 - t;
        let p = (u * u * a.0 + 2.0 * u * t * b.0 + t * t * c.0, u * u * a.1 + 2.0 * u * t * b.1 + t * t * c.1);
        if let Some(last) = points.last() {
            let l: &(f64, f64) = last;
            lengths.push(lengths[lengths.len() - 1] + (p.0 - l.0).hypot(p.1 - l.1));
        }
        points.push(p);
    }
    let total = *lengths.last().unwrap();
    let head_length = total * 0.17;
    let head_half = head_length * 0.62;
    let neck_half = head_half * 0.62;
    let tail_half = if heads >= 2 { neck_half } else { head_half * 0.30 };
    let step = |d: f64| {
        for (i, len) in lengths.iter().enumerate() {
            if *len >= d {
                return i.max(1);
            }
        }
        lengths.len() - 1
    };
    let starts_at = if heads >= 2 { head_length } else { 0.0 };
    let ends_at = total - head_length;
    let (first, last) = (step(starts_at), step(ends_at));
    let normal = |i: usize| {
        let before = points[i.saturating_sub(1)];
        let after = points[(i + 1).min(points.len() - 1)];
        let (dx, dy) = (after.0 - before.0, after.1 - before.1);
        let len = dx.hypot(dy).max(0.0001);
        (-dy / len, dx / len)
    };
    let half = |i: usize| {
        let along = (lengths[i] - starts_at) / (ends_at - starts_at).max(0.0001);
        tail_half + (neck_half - tail_half) * along.clamp(0.0, 1.0)
    };
    let (n_in, n_out) = (normal(first), normal(last));
    let (tail, neck, tip) = (points[first], points[last], points[points.len() - 1]);
    let mut out = Vec::new();
    for i in first..=last {
        let (n, d) = (normal(i), half(i));
        out.push((points[i].0 + n.0 * d, points[i].1 + n.1 * d));
    }
    out.push((neck.0 + n_out.0 * head_half, neck.1 + n_out.1 * head_half));
    out.push(tip);
    out.push((neck.0 - n_out.0 * head_half, neck.1 - n_out.1 * head_half));
    for i in (first..=last).rev() {
        let (n, d) = (normal(i), half(i));
        out.push((points[i].0 - n.0 * d, points[i].1 - n.1 * d));
    }
    if heads >= 2 {
        out.push((tail.0 - n_in.0 * head_half, tail.1 - n_in.1 * head_half));
        out.push(points[0]);
        out.push((tail.0 + n_in.0 * head_half, tail.1 + n_in.1 * head_half));
    }
    out
}

#[test]
fn an_arrow_drawn_before_pins_prints_exactly_as_it_did() {
    let (w, h) = (1600.0, 900.0);
    for (line, heads) in [("0.2,0.8,0.4,0.5,0.6,0.35,1", 1u8), ("0.3,0.3,0.5,0.1,0.7,0.3,2", 2)] {
        let n: Vec<f64> = line.split(',').map(|s| s.parse().unwrap()).collect();
        let before = old_outline((n[0] * w, n[1] * h), (n[2] * w, n[3] * h), (n[4] * w, n[5] * h), heads);
        let now = Arrow::parse(line)[0].outline(w, h);
        assert_eq!(before.len(), now.len());
        for (a, b) in before.iter().zip(&now) {
            assert!((a.0 - b.0).abs() < 1e-6 && (a.1 - b.1).abs() < 1e-6, "{a:?} vs {b:?}");
        }
    }
}

#[test]
fn a_dashed_arrow_is_dashes_and_a_headless_one_has_no_head() {
    let mut a = Arrow::straight(0.1, 0.5, 0.9, 0.5);
    a.dashed = true;
    let pieces = a.pieces(1000.0, 1000.0);
    assert!(pieces.len() > 3, "dashes then a head: {}", pieces.len());
    assert_eq!(pieces.last().unwrap().len(), 3, "the head is a triangle");

    let mut bare = Arrow::straight(0.1, 0.5, 0.9, 0.5);
    bare.heads = 0;
    let solid = bare.pieces(1000.0, 1000.0);
    assert_eq!(solid.len(), 1);
    // Nothing reaches past the line's own end: the far tip is the shaft's edge.
    assert!(solid[0].iter().all(|p| p.0 <= 900.0 + 1e-6));

    let mut red = Arrow::straight(0.1, 0.5, 0.9, 0.5);
    red.look = ArrowLook::Red;
    assert!(red.svg(1000.0, 1000.0).contains("fill=\"#D44C47\""));
    let corner = Arrow::through(&[(0.1, 0.9), (0.1, 0.1), (0.9, 0.1)]).map(|mut a| {
        a.shape = ArrowShape::Corner;
        a
    });
    assert_eq!(corner.unwrap().pieces(1000.0, 1000.0).len(), 1);
}

#[test]
fn a_dashed_shaft_is_a_thin_even_dashed_line_that_meets_its_head() {
    // Straight, left to right along y = 500: every dash is a rectangle.
    let mut a = Arrow::straight(0.1, 0.5, 0.9, 0.5);
    a.dashed = true;
    let pieces = a.pieces(1000.0, 1000.0);
    let head = pieces.last().unwrap();
    let dashes = &pieces[..pieces.len() - 1];
    let solid = Arrow::straight(0.1, 0.5, 0.9, 0.5).pieces(1000.0, 1000.0);
    let solid_width = solid[0].iter().filter(|p| p.0 > 765.0 && p.0 < 772.0 && (p.1 - 500.0).abs() < 60.0).map(|p| (p.1 - 500.0).abs()).fold(0.0, f64::max) * 2.0;
    let mut widths = Vec::new();
    for d in dashes {
        let ys: Vec<f64> = d.iter().map(|p| p.1).collect();
        let xs: Vec<f64> = d.iter().map(|p| p.0).collect();
        let width = ys.iter().cloned().fold(f64::MIN, f64::max) - ys.iter().cloned().fold(f64::MAX, f64::min);
        let long = xs.iter().cloned().fold(f64::MIN, f64::max) - xs.iter().cloned().fold(f64::MAX, f64::min);
        assert!(long > width * 2.2 && long < width * 4.0, "a dash is about three widths long: {long} by {width}");
        widths.push(width);
    }
    assert!(widths.iter().all(|w| (w - widths[0]).abs() < 1e-6), "constant width");
    assert!((widths[0] / solid_width - 0.6).abs() < 0.05, "about 60% of a solid shaft: {} vs {}", widths[0], solid_width);
    let first_start = dashes[0].iter().map(|p| p.0).fold(f64::MAX, f64::min);
    let last_end = dashes.last().unwrap().iter().map(|p| p.0).fold(f64::MIN, f64::max);
    let neck = head[0].0; // the base of the head
    assert!((first_start - 100.0).abs() < 1e-6, "starts at the tail");
    assert!((last_end - neck).abs() < 1e-6, "the last dash meets the head: {last_end} vs {neck}");
}

// ---- Print Frame ---------------------------------------------------------

fn a_shot_with_pictures() -> (Doc, Id, Id, Id, Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let still = d.add_media(sha256(b"a still"), MediaKind::Image, 1600, 900, 1000, "still.jpg");
    let clip = d.add_media(sha256(b"a clip"), MediaKind::Video, 1280, 856, 9000, "take.mov");
    let still_use = d.attach_media(shot, still, "");
    let clip_use = d.attach_media(shot, clip, "");
    (d, shot, still_use, clip_use, still)
}

fn spec(still_use: Id, clip_use: Id) -> PrintFrame {
    PrintFrame {
        layout: "side".into(),
        frames: vec![
            Moment { media_ref: clip_use, at: Some(3.25) },
            Moment { media_ref: still_use, at: None },
            Moment { media_ref: clip_use, at: Some(12.0) },
        ],
        numbers: true,
        arrows: vec![toolkit_arrow()],
    }
}

fn bake(d: &mut Doc, shot: Id, digest: &str) {
    let hash = sha256(b"the baked board").to_hex();
    d.set_print_frame_baked(shot, &Baked { hash, ext: "jpg".into(), width: 1600, height: 1000, digest: digest.into() });
}

#[test]
fn a_print_frame_is_kept_read_back_and_undone() {
    let (mut d, shot, still_use, clip_use, _) = a_shot_with_pictures();
    assert!(d.print_frame(shot).is_none());
    let made = spec(still_use, clip_use);
    d.set_print_frame(shot, &made);
    let read = d.print_frame(shot).unwrap();
    assert_eq!(read.layout, "side");
    assert_eq!(read.frames.len(), 3);
    assert_eq!(read.frames[0].at, Some(3.25));
    assert_eq!(read.frames[1].at, None);
    assert!(read.numbers);
    assert_eq!(read.arrows.len(), 1);
    assert_eq!(read.digest(), made.digest(), "the same spec is the same text");

    d.undo();
    assert!(d.print_frame(shot).is_none());
}

#[test]
fn a_print_frame_travels_to_another_device() {
    let (mut mac, shot, still_use, clip_use, _) = a_shot_with_pictures();
    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mac.changes().to_vec());
    mac.set_print_frame(shot, &spec(still_use, clip_use));
    bake(&mut mac, shot, &spec(still_use, clip_use).digest());
    phone.merge(mac.changes().to_vec());
    assert_eq!(phone.print_frame(shot), mac.print_frame(shot));
    assert!(phone.print_frame_is_current(shot));
    let view = phone.print_frame_view(shot).unwrap();
    assert!(view.contains("\"stale\":false"), "{view}");
    assert!(view.contains("\"live\":true"));
}

#[test]
fn a_bake_goes_stale_when_the_spec_changes_and_the_view_says_so() {
    let (mut d, shot, still_use, clip_use, _) = a_shot_with_pictures();
    d.set_print_frame(shot, &spec(still_use, clip_use));
    assert!(!d.print_frame_is_current(shot), "nothing baked yet");
    let digest = d.print_frame(shot).unwrap().digest();
    bake(&mut d, shot, &digest);
    assert!(d.print_frame_is_current(shot));
    assert!(d.print_frame_picture(shot).is_some());

    // Changed without a new bake — Claude's connector, say.
    let mut changed = spec(still_use, clip_use);
    changed.layout = "under".into();
    d.set_print_frame(shot, &changed);
    assert!(!d.print_frame_is_current(shot));
    assert!(d.print_frame_view(shot).unwrap().contains("\"stale\":true"));

    // Undone, the old bake stands again; the bake itself is no undo step.
    d.undo();
    assert!(d.print_frame_is_current(shot));

    // A frame taken off the shot makes it stale too.
    d.detach_media(still_use);
    assert!(!d.print_frame_is_current(shot));
    assert!(d.print_frame_view(shot).unwrap().contains("\"live\":false"));

    d.clear_print_frame(shot);
    assert!(d.print_frame(shot).is_none());
    assert!(d.print_frame_baked(shot).is_none());
}

#[test]
fn the_view_carries_a_shots_print_frame() {
    let (mut d, shot, still_use, clip_use, _) = a_shot_with_pictures();
    d.set_print_frame(shot, &spec(still_use, clip_use));
    use shotlister_engine::view::{describe, Asked, Standing};
    let view = describe(&d, &Asked::default().looking(), &Standing { read_only: false, unsaved: 0, device_clash: None });
    assert!(view.contains("\"printFrame\":{\"layout\":\"side\""), "no printFrame in the view");
}

#[test]
fn a_baked_picture_is_not_swept_as_a_stray() {
    let (mut d, shot, still_use, clip_use, _) = a_shot_with_pictures();
    d.set_print_frame(shot, &spec(still_use, clip_use));
    bake(&mut d, shot, "x");
    let stem: String = sha256(b"the baked board").to_hex().chars().take(32).collect();
    let name = format!("{stem}.jpg");
    assert!(d.stray_media_names([name.as_str()]).is_empty());
}

#[test]
fn a_copied_shot_brings_its_print_frame_onto_its_own_pictures() {
    let (mut d, shot, still_use, clip_use, _) = a_shot_with_pictures();
    d.set_print_frame(shot, &spec(still_use, clip_use));
    let digest = d.print_frame(shot).unwrap().digest();
    bake(&mut d, shot, &digest);
    let placement = d.store().referring_to(&shotlister_engine::store::Kind::Placement, f::SHOT, shot)[0].id;
    let (copy, _) = d.duplicate_shot(placement).unwrap();
    let copied = d.print_frame(copy).unwrap();
    let own = d.media_refs(copy);
    assert!(copied.frames.iter().all(|m| own.contains(&m.media_ref)));
    assert!(d.print_frame_is_current(copy));
}

// ---- the printed page ----------------------------------------------------

fn sheet(d: &Doc) -> Sheet {
    let mut s = d.sheet(&Query::grouped_by(GroupBy::Scene));
    s.fill_print_frames(|_, _| Some(("data:image/jpeg;base64,BAKED".to_string(), 0.0, 0.0)));
    s
}

#[test]
fn the_printed_page_uses_a_current_bake_and_falls_back_otherwise() {
    let (mut d, shot, still_use, clip_use, still) = a_shot_with_pictures();
    let supply = |id: Id, _: html::Trim| {
        (id == still).then(|| html::Frame { src: "data:image/png;base64,STILL".into(), width: 1600.0, height: 900.0, moments: 1 })
    };
    let pages = |d: &Doc| {
        (
            html::table(&sheet(d), &supply, Print::Table, 1.0, FrameSize::default(), &Default::default()),
            html::storyboard(&sheet(d), &supply, Print::Storyboard, 1.0, FrameSize::default()),
        )
    };

    // None: exactly as before.
    let (table, board) = pages(&d);
    assert!(table.contains("STILL") && !table.contains("BAKED"));
    assert!(board.contains("STILL") && !board.contains("BAKED"));

    // Set but not baked: still as before.
    d.set_print_frame(shot, &spec(still_use, clip_use));
    let (table, _) = pages(&d);
    assert!(!table.contains("BAKED"));

    // Baked and current: the board, in its own shape (1000 / 1600 = 62.50%).
    let digest = d.print_frame(shot).unwrap().digest();
    bake(&mut d, shot, &digest);
    let (table, board) = pages(&d);
    assert!(table.contains("BAKED") && !table.contains("STILL"), "the table draws the bake alone");
    assert!(table.contains("padding-top:62.50%"), "the box follows the board's own shape");
    assert!(board.contains("BAKED") && !board.contains("STILL"));
    assert!(board.contains("padding-top:62.50%"));

    // Stale: back to before.
    let mut changed = spec(still_use, clip_use);
    changed.numbers = false;
    d.set_print_frame(shot, &changed);
    let (table, board) = pages(&d);
    assert!(table.contains("STILL") && !table.contains("BAKED"));
    assert!(board.contains("STILL") && !board.contains("BAKED"));

    // Current, but the picture is not on this device: as before.
    let digest = d.print_frame(shot).unwrap().digest();
    bake(&mut d, shot, &digest);
    let mut missing = d.sheet(&Query::grouped_by(GroupBy::Scene));
    missing.fill_print_frames(|_, _| None);
    let table = html::table(&missing, &supply, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(table.contains("STILL") && !table.contains("BAKED"));
}

#[test]
fn a_tall_board_on_the_storyboard_page_stays_within_twice_the_dials_height() {
    let (mut d, shot, still_use, clip_use, still) = a_shot_with_pictures();
    let supply = |id: Id, _: html::Trim| {
        (id == still).then(|| html::Frame { src: "data:image/png;base64,STILL".into(), width: 1600.0, height: 900.0, moments: 1 })
    };
    d.set_print_frame(shot, &spec(still_use, clip_use));
    let digest = d.print_frame(shot).unwrap().digest();
    let hash = sha256(b"the baked board").to_hex();
    d.set_print_frame_baked(shot, &Baked { hash, ext: "jpg".into(), width: 1000, height: 1600, digest });
    let page = html::storyboard(&sheet(&d), &supply, Print::Storyboard, 1.0, FrameSize::Medium);
    // 1000 x 1600 (0.625): the dial's frame is 9rem high, so the board's own
    // width is 5.625rem. A film frame's width (the old floor, 21.5rem) made it
    // nearly 35rem high; twice the dial's height is 11.25rem wide.
    let at = page.find("class=\"card-pic\"").expect("the board's box");
    assert!(page[at..][..80].contains("width:11.25rem"), "{}", &page[at..][..120]);
}

// ---- thickness and depth (2026-10-14, evening) ---------------------------

/// `parse_one` as the 10-14 toolkit builds run it — they know `w:` and not
/// `thick:` or `depth:`. Only the parts the new tokens could disturb.
fn toolkit_reader(line: &str) -> Vec<(usize, f64, bool, String)> {
    line.split(';')
        .filter(|p| !p.trim().is_empty())
        .map(|piece| {
            let (mut numbers, mut pins, mut weight, mut dashed, mut look) = (0, 0, 1.0, false, "light".to_string());
            for token in piece.split(',').map(str::trim) {
                if token.parse::<f64>().is_ok() {
                    numbers += 1;
                    continue;
                }
                if let Some(rest) = token.strip_prefix('p') {
                    if rest.split_once(':').is_some() {
                        pins += 1;
                    }
                    continue;
                }
                match token {
                    "dashed" => dashed = true,
                    "corner" | "smooth" => {}
                    _ => {
                        if let Some(said) = token.strip_prefix("look:") {
                            look = said.to_string();
                        } else if let Some(said) = token.strip_prefix("w:") {
                            weight = match said { "S" => 0.7, "L" => 1.4, "M" => 1.0, _ => weight };
                        }
                    }
                }
            }
            assert_eq!(numbers, 7, "only the seven numbers parse as numbers: {piece}");
            (pins, weight, dashed, look)
        })
        .collect()
}

fn deep(depth: ArrowDepth, strength: f64) -> Arrow {
    let mut a = Arrow::straight(0.5, 0.9, 0.5, 0.1);
    a.depth = depth;
    a.depth_strength = strength;
    a
}

#[test]
fn thickness_and_depth_survive_the_stored_line() {
    let mut a = toolkit_arrow();
    a.thickness = 2.35;
    a.depth = ArrowDepth::Away;
    a.depth_strength = 0.8;
    let mut b = Arrow::straight(0.1, 0.1, 0.9, 0.9);
    b.thickness = 0.55;
    b.depth = ArrowDepth::Toward;
    let line = Arrow::encode(&[a.clone(), b.clone()]);
    assert!(line.contains(",w:L,thick:2.35,depth:away:0.80"), "{line}");
    assert!(line.contains(",w:S,thick:0.55,depth:toward") && !line.contains("toward:"), "{line}");
    let read = Arrow::parse(&line);
    assert_eq!(read, vec![a, b]);
    assert_eq!(Arrow::encode(&read), line);
    // `thick:` wins over `w:` whichever comes first; out of range is held.
    let r = Arrow::parse("0.1,0.1,0.5,0.5,0.9,0.9,1,thick:1.7,w:S;0.1,0.1,0.5,0.5,0.9,0.9,1,thick:9,depth:sideways");
    assert_eq!(r[0].thickness, 1.7);
    assert_eq!(r[1].thickness, 3.0);
    assert_eq!(r[1].depth, ArrowDepth::Flat, "an unknown depth is flat");
}

#[test]
fn the_old_weights_read_as_their_thicknesses_and_keep_their_bytes() {
    for (token, t) in [(",w:S", 0.7), ("", 1.0), (",w:L", 1.4)] {
        let line = format!("0.1000,0.5000,0.5000,0.5000,0.9000,0.5000,1{token}");
        let read = Arrow::parse(&line);
        assert_eq!(read[0].thickness, t);
        assert_eq!(Arrow::encode(&read), line, "untouched, it is the same line");
    }
}

#[test]
fn every_older_reader_draws_a_sensible_arrow_from_thickness_and_depth() {
    let mut a = toolkit_arrow();
    a.thickness = 2.6;
    a.depth = ArrowDepth::Toward;
    a.depth_strength = 0.9;
    let mut thin = Arrow::straight(0.2, 0.2, 0.6, 0.2);
    thin.thickness = 0.6;
    thin.depth = ArrowDepth::Away;
    let line = Arrow::encode(&[a, thin]);
    // Before the toolkit: seven numbers each, nothing dropped.
    assert_eq!(old_reader(&line).len(), 2, "{line}");
    // The toolkit's own first builds: pins, look and line kept, the nearest weight.
    let read = toolkit_reader(&line);
    assert_eq!(read[0], (3, 1.4, true, "red".to_string()));
    assert_eq!(read[1], (0, 0.7, false, "light".to_string()));
    for token in line.split([',', ';']) {
        let t = token.trim().to_lowercase();
        if t.parse::<f64>().is_err() {
            assert!(t.starts_with(|c: char| c.is_ascii_alphabetic() && c != 'i' && c != 'n'), "{t}");
        }
    }
}

/// The shaft's half-width where it crosses the line y = `y` — read straight
/// off the outline of an upright arrow (tail low, head high).
fn width_at(piece: &[(f64, f64)], y: f64) -> f64 {
    let mut xs: Vec<f64> = Vec::new();
    for i in 0..piece.len() {
        let (p, q) = (piece[i], piece[(i + 1) % piece.len()]);
        if (p.1 - y) * (q.1 - y) < 0.0 {
            xs.push(p.0 + (q.0 - p.0) * (y - p.1) / (q.1 - p.1));
        }
    }
    xs.iter().cloned().fold(f64::MIN, f64::max) - xs.iter().cloned().fold(f64::MAX, f64::min)
}

/// An upright deep arrow `len` of a 1000-pixel picture long, centred.
fn upright(depth: ArrowDepth, len: f64) -> Arrow {
    let mut a = Arrow::straight(0.5, 0.5 + len / 2.0, 0.5, 0.5 - len / 2.0);
    a.depth = depth;
    a
}

/// The widest the outline is, across the shaft, and how long it is.
fn spread(piece: &[(f64, f64)]) -> (f64, f64) {
    let xs = piece.iter().map(|q| q.0);
    let ys = piece.iter().map(|q| q.1);
    (
        xs.clone().fold(f64::MIN, f64::max) - xs.fold(f64::MAX, f64::min),
        ys.clone().fold(f64::MIN, f64::max) - ys.fold(f64::MAX, f64::min),
    )
}

#[test]
fn widths_set_by_hand_draw_and_survive_the_stored_line() {
    let (w, h) = (1000.0, 1000.0);
    let mut a = Arrow::straight(0.5, 0.9, 0.5, 0.1);
    a.widths = Some([0.03, 0.06]);
    // Kept, read back, and absent ones stay absent.
    let line = Arrow::encode(&[a.clone(), Arrow::straight(0.1, 0.1, 0.9, 0.9)]);
    assert!(line.contains(",widths:0.0300:0.0600"), "{line}");
    let read = Arrow::parse(&line);
    assert_eq!(read[0].widths, Some([0.03, 0.06]));
    assert_eq!(read[1].widths, None);
    assert_eq!(Arrow::encode(&read), line);
    // Flat: the shaft is an even rectangle 2 x 30 across, the head's base 2 x 60.
    let p = &a.pieces(w, h)[0];
    for y in [801.0, 601.0, 401.0, 251.0] {
        assert!((width_at(p, y) - 60.0).abs() < 1.0, "shaft at {y}: {}", width_at(p, y));
    }
    let head = p.iter().map(|q| q.0).fold(f64::MIN, f64::max) - 500.0;
    assert!((head - 60.0).abs() < 0.01, "head {head}");
    // Thickness still scales both.
    let mut thick = a.clone();
    thick.thickness = 2.0;
    let q = &thick.pieces(w, h)[0];
    let head2 = q.iter().map(|q| q.0).fold(f64::MIN, f64::max) - 500.0;
    assert!((head2 - 120.0).abs() < 0.01, "{head2}");
    assert!((width_at(q, 601.0) - 120.0).abs() < 1.0, "{}", width_at(q, 601.0));
    // Out of range is held; nonsense is dropped.
    let r = Arrow::parse("0.1,0.1,0.5,0.5,0.9,0.9,1,widths:0:0.5;0.1,0.1,0.5,0.5,0.9,0.9,1,widths:1;0.1,0.1,0.5,0.5,0.9,0.9,1,widths:1:2:3:4");
    assert_eq!(r[0].widths, Some([0.001, 0.5]));
    assert_eq!(r[1].widths, None);
    assert_eq!(r[2].widths, None);
    // The widths the Mac's handles start from are what is drawn.
    let mut deep = upright(ArrowDepth::Toward, 0.3);
    let auto = deep.pieces(w, h);
    let px = deep.widths_px(w, h);
    deep.widths = Some(px.map(|v| v / 1000.0));
    assert_eq!(deep.pieces(w, h).len(), auto.len());
    for (x, y) in deep.pieces(w, h)[0].iter().zip(auto[0].iter()) {
        assert!((x.0 - y.0).abs() < 1e-6 && (x.1 - y.1).abs() < 1e-6);
    }
}

#[test]
fn the_first_build_s_three_widths_still_read_as_the_nearest_two() {
    // Build 2004 wrote tail:middle:head. Read as shaft = middle, head = head.
    let r = Arrow::parse("0.5,0.9,0.5,0.5,0.5,0.1,1,widths:0.0100:0.0400:0.0600");
    assert_eq!(r[0].widths, Some([0.04, 0.06]));
    // Written back in the new form.
    assert!(Arrow::encode(&r).contains(",widths:0.0400:0.0600"));
    // And it draws: shaft 2 x 40 at the back, narrowing into a neck under the
    // head's 2 x 60 base (a shaft over 62% of the head now narrows evenly).
    let p = &r[0].pieces(1000.0, 1000.0)[0];
    assert!((width_at(p, 851.0) - 80.0).abs() < 1.5, "{}", width_at(p, 851.0));
    assert!(width_at(p, 250.0) <= 75.0);
    // Nothing else changes in the line for an untouched arrow.
    let plain = Arrow::encode(&[Arrow::straight(0.1, 0.1, 0.9, 0.9)]);
    assert!(!plain.contains("widths"));
    assert_eq!(Arrow::encode(&Arrow::parse(&plain)), plain);
}

#[test]
fn thickness_scales_the_whole_arrow() {
    let (w, h) = (1000.0, 1000.0);
    let mut thick = deep(ArrowDepth::Flat, 0.5);
    thick.thickness = 2.0;
    let one = deep(ArrowDepth::Flat, 0.5);
    let r = width_at(&thick.pieces(w, h)[0], 601.0) / width_at(&one.pieces(w, h)[0], 601.0);
    // The flat taper runs to the neck, which sits further back on a thicker
    // arrow, so a little over twice.
    assert!((r - 2.0).abs() < 0.2, "{r}");
    assert!((thick.stroke(w, h) / one.stroke(w, h) - 2.0).abs() < 1e-9);
}


// ---- solid Toward / Away arrows (step 8, 2026-10-15) ----------------------

use shotlister_engine::arrow::ArrowStance;

/// The faces that are the arrow itself, not its sides.
fn caps(a: &Arrow, w: f64, h: f64) -> Vec<Vec<(f64, f64)>> {
    a.faces(w, h).into_iter().filter(|f| !f.side).map(|f| f.points).collect()
}

#[test]
fn toward_grows_as_it_travels_and_away_shrinks() {
    let (w, h) = (1000.0, 1000.0);
    for stance in [ArrowStance::Floor, ArrowStance::Standing] {
        let mut toward = deep(ArrowDepth::Toward, 0.5);
        let mut away = deep(ArrowDepth::Away, 0.5);
        toward.stance = stance;
        away.stance = stance;
        let (t, a) = (caps(&toward, w, h).remove(0), caps(&away, w, h).remove(0));
        // Tail at y 900, head at y 100. Toward: the shaft is wider near the head.
        let (t0, t1) = (width_at(&t, 851.0), width_at(&t, 351.0));
        let (a0, a1) = (width_at(&a, 851.0), width_at(&a, 351.0));
        assert!(t1 > t0 * 1.5, "{stance:?} toward widens: {t0} → {t1}");
        assert!(a0 > a1 * 1.5, "{stance:?} away narrows: {a0} → {a1}");
        // Straight sides: perspective keeps a straight edge straight.
        let tm = width_at(&t, 601.0);
        assert!((tm - (t0 + t1) / 2.0).abs() < 0.08 * t1, "{t0} {tm} {t1}");
        // The near head is the big one.
        let head = |x: &Arrow| {
            let [c, p] = x.handle_spots(w, h)[1];
            (p.0 - c.0).hypot(p.1 - c.1)
        };
        assert!(head(&toward) > head(&away) * 1.3, "{} {}", head(&toward), head(&away));
        // Stronger is more.
        let mut strong = deep(ArrowDepth::Toward, 1.0);
        strong.stance = stance;
        let s = caps(&strong, w, h).remove(0);
        assert!(width_at(&s, 351.0) / width_at(&s, 851.0) > t1 / t0);
    }
}

#[test]
fn a_solid_arrow_has_a_shaded_side_and_ends_where_it_was_drawn() {
    let (w, h) = (1600.0, 900.0);
    for stance in [ArrowStance::Floor, ArrowStance::Standing] {
        for depth in [ArrowDepth::Toward, ArrowDepth::Away] {
            let mut a = Arrow::straight(0.2, 0.85, 0.45, 0.3);
            a.depth = depth;
            a.stance = stance;
            let faces = a.faces(w, h);
            assert!(faces.iter().any(|f| f.side), "{stance:?} {depth:?}: a side shows");
            assert_eq!(faces.iter().filter(|f| !f.side).count(), 1, "one face on top");
            assert!(!faces.last().unwrap().side, "the face is drawn last");
            // The tip is exactly the head he dragged.
            let cap = &faces.last().unwrap().points;
            let tip = (0.45 * w, 0.3 * h);
            assert!(cap.iter().any(|p| (p.0 - tip.0).abs() < 1e-6 && (p.1 - tip.1).abs() < 1e-6));
            let svg = a.svg(w, h);
            assert!(svg.contains(ArrowLook::Light.shade()) && svg.contains("#FFFFFF"), "{svg}");
            assert_eq!(a.pieces(w, h).len(), faces.len());
        }
    }
    // Floor and Standing are different solids.
    let mut floor = Arrow::straight(0.2, 0.85, 0.45, 0.3);
    floor.depth = ArrowDepth::Away;
    let mut standing = floor.clone();
    standing.stance = ArrowStance::Standing;
    assert_ne!(floor.faces(w, h), standing.faces(w, h));
}

#[test]
fn the_stance_survives_the_stored_line_and_older_readers_ignore_it() {
    let mut a = deep(ArrowDepth::Away, 0.5);
    a.stance = ArrowStance::Standing;
    let floor = deep(ArrowDepth::Toward, 0.5);
    let line = Arrow::encode(&[a.clone(), floor.clone()]);
    assert!(line.starts_with("0.5000,0.9000,0.5000,0.5000,0.5000,0.1000,1,depth:away,stance:standing;"), "{line}");
    assert!(!line.split(';').nth(1).unwrap().contains("stance"), "Floor is the default: {line}");
    assert_eq!(Arrow::parse(&line), vec![a, floor]);
    assert_eq!(old_reader(&line).len(), 2);
    // A flat arrow never writes it, and an unknown stance is Floor.
    let mut flat = Arrow::straight(0.1, 0.1, 0.9, 0.9);
    flat.stance = ArrowStance::Standing;
    assert!(!Arrow::encode(&[flat]).contains("stance"));
    let r = Arrow::parse("0.1,0.1,0.5,0.5,0.9,0.9,1,depth:toward,stance:sideways");
    assert_eq!(r[0].stance, ArrowStance::Floor);
}

#[test]
fn the_far_end_is_always_a_real_arrowhead() {
    let (w, h) = (1000.0, 1000.0);
    for stance in [ArrowStance::Floor, ArrowStance::Standing] {
        for thick in [0.6f64, 1.0, 2.0] {
            for len in [0.04, 0.08, 0.16, 0.3, 0.55, 0.85] {
                let mut away = upright(ArrowDepth::Away, len);
                away.thickness = thick;
                away.stance = stance;
                let spots = away.handle_spots(w, h);
                assert_eq!(spots.len(), 2);
                let [shaft_c, shaft_h] = spots[0];
                let [neck, barb] = spots[1];
                let half = (barb.0 - neck.0).hypot(barb.1 - neck.1);
                let shaft = (shaft_h.0 - shaft_c.0).hypot(shaft_h.1 - shaft_c.1);
                let tip = (away.x2 * w, away.y2 * h);
                let long = (tip.0 - neck.0).hypot(tip.1 - neck.1);
                // Never a needle, never a squashed bar, never under a few pixels.
                // (The shortest have the least room for a head.)
                let shape = if len < 0.1 { 0.9 } else { 1.05 };
                assert!(long >= shape * half, "{stance:?} {thick} {len}: {long} vs {half}");
                assert!(half >= 0.012 * 1000.0 * thick.sqrt() - 0.5, "{stance:?} {thick} {len}: {half}");
                assert!(half > shaft * 1.1, "the head is wider than the shaft: {half} {shaft}");
            }
        }
    }
}

#[test]
fn thickness_still_weighs_a_deep_arrow() {
    let (w, h) = (1000.0, 1000.0);
    let one = upright(ArrowDepth::Toward, 0.3);
    let mut two = one.clone();
    two.thickness = 2.0;
    let r = spread(&caps(&two, w, h)[0]).0 / spread(&caps(&one, w, h)[0]).0;
    assert!((r - 2.0).abs() < 0.15, "{r}");
    assert!(two.stroke(w, h) > one.stroke(w, h) * 1.9);
}

#[test]
fn the_two_handles_each_move_only_their_own_part() {
    let (w, h) = (1000.0, 1000.0);
    let base = upright(ArrowDepth::Toward, 0.7);
    let [shaft, head] = base.widths_px(w, h);
    let at = |s: f64, hd: f64| {
        let mut a = base.clone();
        a.widths = Some([s / 1000.0, hd / 1000.0]);
        a
    };
    // Untouched and set to its own widths draw the same.
    assert_eq!(at(shaft, head).faces(w, h).len(), base.faces(w, h).len());
    for (p, q) in at(shaft, head).pieces(w, h).iter().flatten().zip(base.pieces(w, h).iter().flatten()) {
        assert!((p.0 - q.0).abs() < 1e-6 && (p.1 - q.1).abs() < 1e-6);
    }
    // The handles apply at the near end: Toward's head is near, so its
    // handle sits where the head is drawn, at the width he set.
    let reach = |a: &Arrow, k: usize| {
        let [c, p] = a.handle_spots(w, h)[k];
        (p.0 - c.0).hypot(p.1 - c.1)
    };
    let same = at(shaft, head);
    assert!((reach(&same, 1) - head).abs() < 0.12 * head, "{} vs {head}", reach(&same, 1));
    let wide = at(shaft, head * 1.5);
    assert!((reach(&wide, 1) / reach(&same, 1) - 1.5).abs() < 0.08);
    assert!((reach(&wide, 0) / reach(&same, 0) - 1.0).abs() < 0.08);
    // (A head is never under 1.6 times the shaft, so the shaft grows a fifth.)
    let thick = at(shaft * 1.2, head);
    assert!((reach(&thick, 0) / reach(&same, 0) - 1.2).abs() < 0.08);
    assert!((reach(&thick, 1) / reach(&same, 1) - 1.0).abs() < 0.08);
    // No head, one handle.
    let mut none = base.clone();
    none.heads = 0;
    assert_eq!(none.handle_spots(w, h).len(), 1);
}

#[test]
fn a_dashed_deep_arrow_has_dashes_that_grow_with_it() {
    let mut a = deep(ArrowDepth::Toward, 0.7);
    a.dashed = true;
    a.heads = 2;
    let all = caps(&a, 1000.0, 1000.0);
    // Drawn far to near: the back head (far, small) is among the first, the
    // front head (near, big) is last.
    let span = |p: &Vec<(f64, f64)>| {
        let ys = p.iter().map(|q| q.1);
        ys.clone().fold(f64::MIN, f64::max) - ys.fold(f64::MAX, f64::min)
    };
    let wide = |p: &Vec<(f64, f64)>| spread(p).0;
    let front = all.last().unwrap();
    assert!(front.len() == 3 && wide(front) > 60.0, "{front:?}");
    let dashes: Vec<&Vec<(f64, f64)>> = all.iter().filter(|p| p.len() > 3).collect();
    assert!(dashes.len() >= 3, "{}", dashes.len());
    for pair in dashes.windows(2) {
        assert!(span(pair[1]) > span(pair[0]), "{} then {}", span(pair[0]), span(pair[1]));
    }
    // Toward from y 900 (far) to y 100 (near): the back head's point is the tail.
    assert!(front.iter().any(|q| (q.1 - 100.0).abs() < 1e-6));
    let back = all.iter().find(|p| p.len() == 3 && p.iter().any(|q| (q.1 - 900.0).abs() < 1e-6)).unwrap();
    assert!(wide(front) > wide(back) * 1.5, "{} {}", wide(front), wide(back));
}

// ---- zoom marks ---------------------------------------------------------

use shotlister_engine::arrow::ZoomDir;

#[test]
fn a_zoom_mark_survives_the_stored_line_and_an_older_reader_drops_it() {
    let mut zin = Arrow::zoom_mark(ZoomDir::In);
    zin.look = ArrowLook::Red;
    zin.thickness = 1.6;
    let mut zout = Arrow::zoom_mark(ZoomDir::Out);
    zout.x1 = 0.3;
    zout.y1 = 0.1;
    zout.x2 = 0.7;
    zout.y2 = 0.5;
    let line = Arrow::encode(&[Arrow::straight(0.1, 0.9, 0.8, 0.9), zin.held(), zout.held()]);
    let read = Arrow::parse(&line);
    assert_eq!(read.len(), 3);
    assert_eq!(read[1].zoom, Some(ZoomDir::In));
    assert_eq!(read[1].look, ArrowLook::Red);
    assert!((read[1].thickness - 1.6).abs() < 0.01);
    assert_eq!(read[2].zoom, Some(ZoomDir::Out));
    assert!((read[2].x1 - 0.3).abs() < 1e-4 && (read[2].y2 - 0.5).abs() < 1e-4);
    assert_eq!(read[0].zoom, None);
    // An older reader needs six numbers and a zoom entry gives it four.
    for piece in line.split(';').skip(1) {
        let numbers = piece.split(',').filter(|t| t.trim().parse::<f64>().is_ok()).count();
        assert!(numbers < 6, "{piece}");
    }
}

#[test]
fn a_zoom_frame_always_has_the_pictures_shape_and_stays_inside() {
    let mut z = Arrow::zoom_mark(ZoomDir::In);
    z.x1 = 0.9;
    z.y1 = 0.95;
    z.x2 = 1.4;
    z.y2 = 1.0;
    let z = z.held();
    assert!(((z.x2 - z.x1) - (z.y2 - z.y1)).abs() < 1e-9);
    assert!(z.x1 >= 0.0 && z.y1 >= 0.0 && z.x2 <= 1.0 + 1e-9 && z.y2 <= 1.0 + 1e-9);
    let tiny = {
        let mut t = Arrow::zoom_mark(ZoomDir::Out);
        t.x2 = t.x1 + 0.001;
        t.held()
    };
    assert!(tiny.x2 - tiny.x1 >= 0.1 - 1e-9);
}

#[test]
fn a_zoom_mark_is_a_clean_frame_and_four_arrows_pointing_the_right_way() {
    let (w, h) = (960.0, 540.0);
    for dir in [ZoomDir::In, ZoomDir::Out] {
        let z = Arrow::zoom_mark(dir);
        let shapes = z.zoom_shapes(w, h).unwrap();
        assert_eq!(shapes.arrows.len(), 4);
        // The frame is two closed rectangles, the inner inside the outer.
        let [outer, inner] = &shapes.ring;
        assert_eq!(outer.len(), 4);
        assert_eq!(inner.len(), 4);
        assert!(outer[0].0 < inner[0].0 && outer[0].1 < inner[0].1 && outer[2].0 > inner[2].0);
        // Each arrow's tip is the point farthest along its direction: toward
        // the inner frame for In, toward the picture's corner for Out.
        let corners = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)];
        for (poly, corner) in shapes.arrows.iter().zip(corners) {
            let (cx, cy) = (z.x1 * w + (corner.0 / w) * (z.x2 - z.x1) * w, z.y1 * h + (corner.1 / h) * (z.y2 - z.y1) * h);
            let near = |p: &(f64, f64), t: (f64, f64)| (p.0 - t.0).hypot(p.1 - t.1);
            let tip = poly.iter().cloned().min_by(|a, b| {
                let key = |p: &(f64, f64)| if dir == ZoomDir::In { near(p, (cx, cy)) } else { near(p, corner) };
                key(a).partial_cmp(&key(b)).unwrap()
            }).unwrap();
            let far_from_tip = poly.iter().cloned().max_by(|a, b| near(a, tip).partial_cmp(&near(b, tip)).unwrap()).unwrap();
            // The tail end sits at the other side of the arrow.
            let toward_inner = |p: &(f64, f64)| near(p, (cx, cy));
            if dir == ZoomDir::In {
                assert!(toward_inner(&tip) < toward_inner(&far_from_tip));
            } else {
                assert!(toward_inner(&tip) > toward_inner(&far_from_tip));
            }
        }
        // Frame lines are unbroken: no arrow touches the band.
        for poly in &shapes.arrows {
            for p in poly {
                let inside_outer = p.0 > outer[0].0 && p.0 < outer[2].0 && p.1 > outer[0].1 && p.1 < outer[2].1;
                assert!(!inside_outer, "arrow point {p:?} touches the frame");
            }
        }
        let svg = z.svg(w, h);
        assert!(svg.contains("fill-rule=\"evenodd\""));
        assert_eq!(svg.matches("<polygon").count(), 4);
        assert_eq!(svg.matches("<path").count(), 1);
    }
}

#[test]
fn zoom_marks_take_look_and_thickness_and_ride_a_print_frame_board() {
    let (w, h) = (960.0, 540.0);
    let thin = Arrow::zoom_mark(ZoomDir::In);
    let mut thick = thin.clone();
    thick.thickness = 2.5;
    assert!(thick.stroke(w, h) > thin.stroke(w, h) * 2.0);
    let mut red = thin.clone();
    red.look = ArrowLook::Red;
    assert!(red.svg(w, h).contains(ArrowLook::Red.fill()));
    let board = PrintFrame { layout: "one".into(), frames: Vec::new(), numbers: false, arrows: vec![thin.clone()] };
    let back = PrintFrame::parse(&board.encode()).unwrap();
    assert_eq!(back.arrows.len(), 1);
    assert_eq!(back.arrows[0].zoom, Some(ZoomDir::In));
}

#[test]
fn a_zoom_mark_s_arrows_stay_inside_what_is_seen() {
    // A square picture in a 2.39 film: only the middle band shows.
    let (w, h) = (1000.0, 1000.0);
    let band = (0.5 - 0.5 / 2.39, 0.5 + 0.5 / 2.39);
    for dir in [ZoomDir::In, ZoomDir::Out] {
        let mut z = Arrow::zoom_mark(dir);
        z.x1 = 0.4;
        z.y1 = 0.4;
        z.x2 = 0.6;
        z.y2 = 0.6;
        z.view = Some([0.0, band.0, 1.0, band.1]);
        let line = Arrow::encode(&[z.clone()]);
        assert!(line.contains(",view:0.0000:0.2908:1.0000:0.7092"), "{line}");
        let back = Arrow::parse(&line);
        let (a, b) = (back[0].view.unwrap(), z.held().view.unwrap());
        assert!(a.iter().zip(b.iter()).all(|(x, y)| (x - y).abs() < 1e-4));
        let shapes = back[0].zoom_shapes(w, h).unwrap();
        assert_eq!(shapes.arrows.len(), 4);
        for poly in &shapes.arrows {
            for p in poly {
                assert!(p.1 >= band.0 * h + shapes.stroke / 2.0 - 0.5 && p.1 <= band.1 * h - shapes.stroke / 2.0 + 0.5, "{dir:?} {p:?}");
            }
        }
    }
    // The whole picture is the same as none.
    let mut z = Arrow::zoom_mark(ZoomDir::In);
    z.view = Some([0.0, 0.0, 1.0, 1.0]);
    assert_eq!(z.held().view, None);
    assert!(!Arrow::encode(&[z.held()]).contains("view"));
}

#[test]
fn a_tail_wider_than_the_head_is_stored_drawn_and_read_back() {
    let (w, h) = (1000.0, 1000.0);
    for stance in [ArrowStance::Floor, ArrowStance::Standing] {
        // Away: the back (near) is the widest part, at least three times the head.
        let mut a = upright(ArrowDepth::Away, 0.7);
        a.stance = stance;
        a.widths = Some([0.12, 0.04]);
        let line = Arrow::encode(&[a.clone()]);
        assert!(line.contains(",widths:0.1200:0.0400"), "{line}");
        let read = Arrow::parse(&line);
        assert_eq!(read[0].widths, Some([0.12, 0.04]));
        assert_eq!(Arrow::encode(&read), line);
        let cap = &caps(&a, w, h)[0];
        let tail = width_at(cap, 835.0);
        let spots = a.handle_spots(w, h);
        let reach = |k: usize| (spots[k][1].0 - spots[k][0].0).hypot(spots[k][1].1 - spots[k][0].1);
        let head = 2.0 * reach(1);
        assert!(tail > 2.5 * head, "{stance:?}: tail {tail} head {head}");
        assert!((spread(cap).0 - tail).abs() < 0.08 * tail, "the back is the widest part: {} vs {tail}", spread(cap).0);
        // The sides still close in toward the far end, and the head is a head.
        assert!(width_at(cap, 600.0) < tail * 0.9 && width_at(cap, 400.0) < width_at(cap, 600.0));
        assert!(head > 8.0 && spread(cap).1 > 500.0);
        // The shaft's handle sits near the tail and follows the width set.
        assert!(spots[0][0].1 > 500.0, "{:?}", spots[0]);
        let mut wider = a.clone();
        wider.widths = Some([0.24, 0.04]);
        let w2 = wider.handle_spots(w, h);
        let r2 = (w2[0][1].0 - w2[0][0].0).hypot(w2[0][1].1 - w2[0][0].1);
        assert!((r2 / reach(0) - 2.0).abs() < 0.1, "{}", r2 / reach(0));
        // Toward and a dashed one draw with a wide shaft too.
        let mut t = upright(ArrowDepth::Toward, 0.7);
        t.stance = stance;
        t.widths = Some([0.12, 0.04]);
        assert!(!t.faces(w, h).is_empty());
        t.dashed = true;
        assert!(!t.faces(w, h).is_empty());
    }
    // Flat: a wide back narrowing into the head, never poking out past it.
    let mut f = Arrow::straight(0.5, 0.9, 0.5, 0.1);
    f.widths = Some([0.12, 0.04]);
    let p = &f.pieces(w, h)[0];
    assert!(width_at(p, 850.0) > 215.0 && width_at(p, 850.0) <= 240.0, "{}", width_at(p, 850.0));
    assert!(width_at(p, 400.0) < 0.75 * width_at(p, 850.0), "tapers strongly");
    assert!((spread(p).0 - 240.0).abs() < 2.0 || spread(p).0 > 215.0);
    let head = p.iter().filter(|q| q.1 < 166.0).map(|q| q.0).fold(f64::MIN, f64::max) - 500.0;
    assert!((head - 40.0).abs() < 1.0, "{head}");
    assert!(width_at(p, 400.0) < 235.0);
    // An old-style flat arrow with a shaft inside its head is not touched.
    let mut old = Arrow::straight(0.5, 0.9, 0.5, 0.1);
    old.widths = Some([0.03, 0.06]);
    assert!((width_at(&old.pieces(w, h)[0], 401.0) - 60.0).abs() < 1.0);
}
