//! Getting the list out: rows, CSV, and the pages.

use shotlister_engine::doc::f;
use shotlister_engine::docstyle::Style;
use shotlister_engine::export::{csv, html, rows::Sheet, FrameSize, Print};
use shotlister_engine::media::{Arrow, MediaKind};
use shotlister_engine::{sha256, DeviceId, Doc, GroupBy, Id, Query};

fn sample() -> (Doc, Id, Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let project = d.project_id().unwrap();
    d.set(project, f::DIRECTOR, "A Director");

    let a_cam = d.create_unit("A-Cam", "Alexa35");
    d.set(a_cam, f::COLOUR, "#b00020");

    let scene = d.create_scene("34");
    d.set(scene, f::INT_EXT, "INT");
    d.set(scene, f::LOCATION, "car");
    d.set(scene, f::TIME_OF_DAY, "day");

    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::TITLE, "Frontal Dirty Single on Milo");
    d.set(shot, f::DESCRIPTION, "Frontal Dirty Single on Milo through Front Window");
    d.set_vocab_field(shot, "size", "M/OTS");
    d.set_vocab_list(shot, "angle", &["Short-Sided"]);
    d.set_vocab_field(shot, "movement", "Static");
    d.set_vocab_field(shot, "lens", "37mm");
    d.set_vocab_field(shot, "support", "Handheld");
    d.set(shot, f::UNIT, a_cam);
    d.set(shot, f::NOTES, "Frame is a way to hide 2 cameras cross coverage");
    d.set_vocab_list(shot, "tags", &["Cross Coverage"]);

    (d, scene, shot)
}

fn sheet(d: &Doc) -> Sheet {
    d.sheet(&Query::grouped_by(GroupBy::Scene))
}

// ---- rows --------------------------------------------------------------

#[test]
fn a_row_resolves_everything_the_exporters_need() {
    let (d, _, _) = sample();
    let s = sheet(&d);
    let row = s.rows().next().unwrap();

    assert_eq!(row.number, "34A");
    assert_eq!(row.scene_heading, "INT. CAR - DAY");
    assert_eq!(row.size, "M/OTS");
    assert_eq!(row.angle, vec!["Short-Sided"]);
    assert_eq!(row.camera.as_ref().unwrap().display(), "A-Cam Alexa35");
    assert_eq!(row.camera.as_ref().unwrap().colour.as_deref(), Some("#b00020"));
    assert_eq!(s.project_title, "Daybreak");
    assert_eq!(s.director, "A Director");
}

#[test]
fn the_technical_line_reads_the_way_the_lists_do() {
    let (d, _, _) = sample();
    let s = sheet(&d);
    let row = s.rows().next().unwrap();

    assert_eq!(
        row.technical_line(),
        "M/OTS – Short-Sided – Static – A-Cam Alexa35 – 37mm – Handheld"
    );
}

#[test]
fn a_row_with_nothing_filled_in_does_not_produce_stray_separators() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Untitled");
    let scene = d.create_scene("1");
    d.add_shot_to_scene(scene);

    let s = sheet(&d);
    assert_eq!(s.rows().next().unwrap().technical_line(), "");
}

#[test]
fn groups_carry_their_counts() {
    let (mut d, scene, _) = sample();
    d.add_shot_to_scene(scene);
    let s = sheet(&d);

    assert_eq!(s.groups.len(), 1);
    assert_eq!(s.groups[0].label, "Scene 34");
    assert_eq!(s.groups[0].count(), 2);
    assert_eq!(s.total(), 2);
}

// ---- csv ---------------------------------------------------------------

#[test]
fn csv_has_the_expected_columns() {
    let (d, _, _) = sample();
    let text = csv::write(&sheet(&d));
    let header = text.lines().next().unwrap();

    assert!(header.starts_with("Day,Scene #,Shot #,Shot Description"));
    assert_eq!(header.split(',').count(), csv::COLUMNS.len());
}

#[test]
fn csv_escapes_what_would_otherwise_break_the_row() {
    let (mut d, _, shot) = sample();
    // The prototype quoted everything and escaped nothing, so a note with a
    // quote mark in it corrupted every column after it.
    d.set(shot, f::NOTES, "He says \"go\", then we cut, mid-line");

    let text = csv::write(&sheet(&d));
    let line = text.lines().nth(1).unwrap();

    assert!(line.contains("\"He says \"\"go\"\", then we cut, mid-line\""));
    // Quoting keeps the column count intact despite the commas inside.
    assert_eq!(text.lines().count(), 2);
}

#[test]
fn csv_repeats_the_group_on_every_row() {
    let (mut d, scene, _) = sample();
    let day = d.create_day();
    for placement in d.placements_in_scene(scene) {
        d.schedule(placement, day);
    }
    d.add_shot_to_scene(scene);

    let text = csv::write(&d.sheet(&Query::grouped_by(GroupBy::Day)));
    let scheduled: Vec<&str> = text
        .lines()
        .skip(1)
        .filter(|l| l.starts_with("Day 1,"))
        .collect();

    // Someone else will sort this sheet; a row must carry its own day.
    assert_eq!(scheduled.len(), 1);
}

// ---- pages -------------------------------------------------------------

#[test]
fn the_document_page_carries_the_shots() {
    let (d, _, _) = sample();
    let page = html::document(&sheet(&d), &html::no_frames, Print::Document, 1.0, "", &Style::standard_style());

    assert!(page.starts_with("<!doctype html>"));
    // One scene, so the scene itself titles the page — his ask, 2026-08-24 —
    // and the group header under it, which would say the same thing twice,
    // is left out.
    assert!(page.contains("34 INT. CAR - DAY"));
    assert!(!page.contains("Scene 34: INT. CAR - DAY"));
    assert!(page.contains("34A"));
    assert!(page.contains("M/OTS – Short-Sided – Static"));
    assert!(page.contains("Cinematography by Nathaniel Regier"));
    assert!(page.contains("@page"), "print rules must be present");
}

#[test]
fn a_project_wide_page_keeps_the_project_title_and_its_scene_headers() {
    let (mut d, _, _) = sample();
    let other = d.create_scene("40");
    d.add_shot_to_scene(other);

    let page = html::document(&d.sheet(&Query::grouped_by(GroupBy::Scene)), &html::no_frames, Print::Document, 1.0, "", &Style::standard_style());
    assert!(page.contains("Daybreak"));
    // **The app's own heading, not a sentence.** The number is a cell of its
    // own in mono and the slug line stands beside it — `34  INT. CAR - DAY` —
    // which is what the Document view draws. It read `Scene 34: INT. CAR -
    // DAY` until 2026-09-01, and no screen in the app has ever said that.
    assert!(page.contains("<span class=\"no\">34</span>"));
    assert!(page.contains("INT. CAR - DAY</h2>"));
}

#[test]
fn the_storyboard_page_carries_a_card_per_shot() {
    let (d, _, _) = sample();
    let page = html::storyboard(&sheet(&d), &html::no_frames, Print::Storyboard, 1.0, FrameSize::default());

    assert!(page.starts_with("<!doctype html>"));
    assert!(page.contains("34 INT. CAR - DAY"));
    assert!(page.contains("34A"));
    // **Every column as a labelled field, not a squashed line** — his ask,
    // 2026-09-20: the card cut off descriptions and "field views". The
    // table's own header stands over each value.
    // The values are the app's coloured pills (the cell is shared with the table).
    for (key, value) in [("Shot Size", "M/OTS"), ("Shot Angle", "Short-Sided"), ("Movement", "Static")] {
        let at = page.find(&format!("<span class=\"k\">{key}</span><span class=\"v\">")).expect(key);
        let cell = &page[at..at + 400];
        assert!(cell.contains("class=\"pill\"") && cell.contains(&format!(">{value}</span>")), "{key}: {cell}");
    }
    assert!(!page.contains("M/OTS – Short-Sided – Static"), "no technical line on a card any more");
    assert!(!page.contains("line-clamp"), "nothing on the storyboard page is cut off");
    assert!(page.contains("class=\"board\""));
    assert!(page.contains("landscape"));
}

/// His ask, 2026-08-28: exporting several scenes' boards together left
/// nothing saying where one scene's cards ended and the next began. Not a
/// clean sheet break — the same standard header `table_rows` already draws
/// between groups, now shared with the board too.
#[test]
fn the_storyboard_page_carries_scene_headers_across_several_scenes() {
    let (mut d, _, _) = sample();
    let second = d.create_scene("35");
    d.set(second, f::INT_EXT, "EXT");
    d.set(second, f::LOCATION, "yard");
    d.set(second, f::TIME_OF_DAY, "night");
    d.add_shot_to_scene(second);

    let page = html::storyboard(&sheet(&d), &html::no_frames, Print::Storyboard, 1.0, FrameSize::default());
    assert!(page.contains("class=\"group-head\""), "a multi-scene board should say which scene each card belongs to");
    assert!(page.contains("34: INT. CAR - DAY"));
    assert!(page.contains("35: EXT. YARD - NIGHT"));
}

/// A scene's own board already names itself in the masthead — repeating it
/// as a group header would say the same thing twice, same rule the table
/// page has followed since Ref 376.
#[test]
fn a_single_scenes_own_storyboard_has_no_repeated_header() {
    let (d, _, _) = sample();
    let page = html::storyboard(&sheet(&d), &html::no_frames, Print::Storyboard, 1.0, FrameSize::default());
    assert!(!page.contains("class=\"group-head\""));
}

#[test]
fn the_table_page_reflects_the_columns_on_screen_and_colours_the_camera() {
    let (mut d, _, _) = sample();

    // Camera is hidden by default, so it does not print until it is shown —
    // the table shows exactly the columns the Table view is showing, title
    // included, and nothing it is not.
    let hidden = html::table(&sheet(&d), &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(!hidden.contains("A-Cam"));

    d.set_column_visible("camera", true);
    let page = html::table(&sheet(&d), &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());

    assert!(page.contains("<th>Title</th>"));
    assert!(page.contains(">A-Cam</span>") && page.contains("Alexa35"));
    assert!(page.contains("color:rgb(176,0,32)"), "the camera pill wears the unit's colour");
    assert!(page.contains("landscape"));
    assert!(page.contains("table-layout: fixed"));
}

#[test]
fn pages_escape_what_people_type() {
    let (mut d, _, shot) = sample();
    d.set(shot, f::TITLE, "Wide <2 Shot> & \"reverse\"");

    let page = html::document(&sheet(&d), &html::no_frames, Print::Document, 1.0, "", &Style::standard_style());

    assert!(page.contains("Wide &lt;2 Shot&gt; &amp; &quot;reverse&quot;"));
    assert!(!page.contains("<2 Shot>"));
}

#[test]
fn frames_come_from_the_caller() {
    let (mut d, _, shot) = sample();
    let frame = d.add_media(
        sha256(b"a frame"),
        MediaKind::Image,
        1600,
        900,
        1000,
        "34a.jpg",
    );
    d.attach_media(shot, frame, "");

    let supply = |id: Id, _: html::Trim| {
        if id == frame {
            Some(html::Frame { src: "data:image/png;base64,AAAA".to_string(), width: 1600.0, height: 900.0, moments: 1 })
        } else {
            None
        }
    };
    let page = html::document(&sheet(&d), &supply, Print::Screen, 1.0, "", &Style::standard_style());
    assert!(page.contains("data:image/png;base64,AAAA"));

    // And a page asked for no frames simply has none.
    let bare = html::document(&sheet(&d), &html::no_frames, Print::Screen, 1.0, "", &Style::standard_style());
    assert!(!bare.contains("<img"));
}

#[test]
fn a_struck_shot_is_marked_rather_than_removed() {
    let (mut d, _, shot) = sample();
    d.strike(shot, true);

    let page = html::table(&sheet(&d), &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(page.contains("class=\"struck\""));
    // Still on the page — striking says "we got it", not "delete it".
    assert!(page.contains("34A"));
}

#[test]
fn an_empty_result_says_so() {
    let (d, _, _) = sample();
    let empty = d.sheet(&Query::grouped_by(GroupBy::Scene).matching("nothing here"));

    let page = html::document(&empty, &html::no_frames, Print::Screen, 1.0, "", &Style::standard_style());
    assert!(page.contains("Nothing matches these filters"));
}

#[test]
fn exports_follow_the_filters() {
    let (mut d, scene, _) = sample();
    let (other, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(other, "size", "W");

    let filtered = d.sheet(&Query::grouped_by(GroupBy::Scene).shot_is("size", "M/OTS"));
    assert_eq!(filtered.total(), 1);
    assert_eq!(csv::write(&filtered).lines().count(), 2);
}

// ---- storyboard arrows on an exported page -----------------------------

#[test]
fn storyboard_arrows_reach_the_printed_page() {
    // His ask, 2026-08-31. A board with motion arrows that cannot be printed
    // is half a board — every one of these pages is something he hands to
    // somebody on a set.
    let (mut d, _, shot) = sample();
    let frame = d.add_media(sha256(b"a frame"), MediaKind::Image, 1600, 900, 1000, "34a.jpg");
    let use_of_it = d.attach_media(shot, frame, "");
    d.set_media_arrows(use_of_it, &[Arrow::straight(0.18, 0.16, 0.74, 0.16)]);

    let supply = |id: Id, _: html::Trim| {
        if id == frame { Some(html::Frame { src: "data:image/png;base64,AAAA".to_string(), width: 1600.0, height: 900.0, moments: 1 }) } else { None }
    };

    // **All three pages place the picture the same way now** (2026-09-01), so
    // all three place its arrows the same way too: inside the span the
    // photograph itself is drawn in, at exactly its size. `meet` and `slice`
    // were a guess that had to agree with a stylesheet; `none` needs no
    // agreement, because the span is already the picture's own ratio.
    let document = html::document(&sheet(&d), &supply, Print::Screen, 1.0, "", &Style::standard_style());
    assert!(document.contains("<polygon"), "no arrow on the document page");
    assert!(document.contains("preserveAspectRatio=\"none\""));
    assert!(document.contains("viewBox=\"0 0 1600 900\""));
    // The marks are placed on the photograph itself, which in a 2.39 frame
    // stands taller than the frame: the same overflow, the same middle.
    assert!(document.contains("height:134.438%"), "the marks lie on the picture, not the frame");
    assert!(document.contains("top:-17.219%"));

    let table = html::table(&sheet(&d), &supply, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(table.contains("<polygon"), "no arrow on the table page");

    let board = html::storyboard(&sheet(&d), &supply, Print::Storyboard, 1.0, FrameSize::default());
    assert!(board.contains("<polygon"), "no arrow on the storyboard card");
    assert!(board.contains("preserveAspectRatio=\"none\""));
}

/// **The crop reaches the page.** Ref filed 2026-09-01 and fixed the same day:
/// choosing which part of a photograph to keep worked on every screen in both
/// apps and was thrown away by every printed page — the one copy somebody else
/// reads.
#[test]
fn the_part_he_chose_to_keep_reaches_the_printed_page() {
    let (mut d, _, shot) = sample();
    let frame = d.add_media(sha256(b"a frame"), MediaKind::Image, 1600, 900, 1000, "34a.jpg");
    let use_of_it = d.attach_media(shot, frame, "");
    let supply = |id: Id, _: html::Trim| {
        if id == frame {
            Some(html::Frame {
                src: "f.png".to_string(),
                width: 1600.0,
                height: 900.0,
                moments: 1,
            })
        } else {
            None
        }
    };

    // Untouched: a 16:9 picture in a 2.39 box covers it by being wider, and
    // sits centred — the left edge is half the overflow.
    let plain = html::table(&sheet(&d), &supply, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(plain.contains("class=\"shotframe key\""), "no frame box on the table page");
    // A 16:9 picture in a 2.39 frame covers it by standing taller, and an
    // untouched one sits in the middle — half the overflow above the frame.
    // Only the width is given; the height is the picture's own business, which
    // is what keeps the PDF's weight down (see `held`).
    assert!(plain.contains("width:100.000%"), "a 16:9 picture covers a 2.39 frame by its width");
    assert!(plain.contains("top:-17.219%"), "an untouched picture sits in the middle");

    // Taken to the top left corner and twice in: the picture is twice the size
    // and its left and top edges are the box's own.
    d.set_media_crop(use_of_it, 0.0, 0.0, 2.0);
    let cropped = html::table(&sheet(&d), &supply, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(cropped.contains("width:200.000%"), "twice in is twice the size");
    assert!(cropped.contains("left:0.000%") && cropped.contains("top:0.000%"),
            "and anchored to the corner he took it to");

    // And the storyboard card, which is the same sum in a box it already owns.
    let board = html::storyboard(&sheet(&d), &supply, Print::Storyboard, 1.0, FrameSize::default());
    assert!(board.contains("width:200.000%"));
}

/// The one dial he sets in the export dialog. Small is what every export drew
/// before it existed, so a sheet that looked right can still be had exactly.
#[test]
fn the_frame_size_changes_the_picture_column_and_the_cards() {
    let (d, _, _) = sample();
    let small = html::table(&sheet(&d), &html::no_frames, Print::Table, 1.0, FrameSize::Small, &Default::default());
    let large = html::table(&sheet(&d), &html::no_frames, Print::Table, 1.0, FrameSize::Large, &Default::default());
    assert_ne!(small, large, "the size dial must change the table");

    // On the storyboard the dial is a frame's height, and its width follows
    // the film's ratio — a film that has not said is 2.39:1, so Large (13rem
    // tall) is 31.07rem wide and Small (6.5rem) 15.54rem.
    let cards = html::storyboard(
        &sheet(&d),
        &html::no_frames,
        Print::Storyboard,
        1.0,
        FrameSize::Large,
    );
    assert!(cards.contains("width:31.07rem"), "a large frame is 13rem tall at 2.39:1");
    let more = html::storyboard(
        &sheet(&d),
        &html::no_frames,
        Print::Storyboard,
        1.0,
        FrameSize::Small,
    );
    assert!(more.contains("width:15.54rem"));
}

/// **A clip's four moments stand side by side on the storyboard page**, and
/// a shot's other frames join them in the row — his ask, 2026-09-20. The
/// Mac hands the page one strip picture (four moments two by two); the page
/// cuts it into four boxes each showing one quarter, in a row wide enough
/// that the words drop underneath it.
#[test]
fn a_clips_four_moments_stand_in_a_row_on_the_storyboard_page() {
    let (mut d, _, shot) = sample();
    let clip = d.add_media(sha256(b"a take"), MediaKind::Video, 1920, 1080, 90_000, "take.mov");
    d.attach_media(shot, clip, "");
    let strip = |id: Id, _trim: html::Trim| -> Option<html::Frame> {
        if id == clip {
            Some(html::Frame { src: "strip.jpg".into(), width: 1920.0, height: 1080.0, moments: 4 })
        } else {
            None
        }
    };
    let board = html::storyboard(&sheet(&d), &strip, Print::Storyboard, 1.0, FrameSize::default());
    assert_eq!(board.matches("class=\"card-frame\"").count(), 4, "four boxes for four moments");
    // The strip's bytes are in the page once; the page's own script hands
    // the other three quarters the picture once it is drawn.
    assert_eq!(board.matches("src=\"strip.jpg\"").count(), 1, "the strip is in the page once");
    assert_eq!(board.matches("class=\"card-strip\"").count(), 1, "its four boxes are grouped");
    assert!(board.contains("img:not([src])"), "and the page fills the other three itself");
    assert!(board.contains("left:0.00%;top:0.00%"), "the first quarter is the top left");
    assert!(board.contains("class=\"card-frames wide\""), "four across takes the whole width");
    assert!(board.contains("min(calc((100% - 1.50rem) / 4)"), "each a quarter of it");

    // Two clips on one shot: eight moments, in two even rows of four.
    let second = d.add_media(sha256(b"another take"), MediaKind::Video, 1920, 1080, 90_000, "two.mov");
    d.attach_media(shot, second, "");
    let strips = |_: Id, _: html::Trim| -> Option<html::Frame> {
        Some(html::Frame { src: "strip.jpg".into(), width: 1920.0, height: 1080.0, moments: 4 })
    };
    let board = html::storyboard(&sheet(&d), &strips, Print::Storyboard, 1.0, FrameSize::default());
    assert_eq!(board.matches("class=\"card-frame\"").count(), 8);
    assert_eq!(board.matches("class=\"card-strip\"").count(), 2);
    assert_eq!(board.matches("min(calc((100% - 1.50rem) / 4)").count(), 8, "two rows of four, not five and three");

    // One still is one box, at the dial's size, and the words may sit beside it.
    let still = |_: Id, _: html::Trim| -> Option<html::Frame> {
        Some(html::Frame { src: "one.jpg".into(), width: 1920.0, height: 1080.0, moments: 1 })
    };
    let (d, _, _) = sample();
    let board = html::storyboard(&sheet(&d), &still, Print::Storyboard, 1.0, FrameSize::default());
    assert_eq!(board.matches("class=\"card-frame\"").count(), 1);
    assert!(board.contains("class=\"card-frames\""), "one frame does not take the row");
    assert!(board.contains("width:21.51rem"), "medium is 9rem tall, 21.5rem wide at 2.39:1");
}

#[test]
fn a_picture_with_no_arrows_prints_exactly_what_it_always_did() {
    let (mut d, _, shot) = sample();
    let frame = d.add_media(sha256(b"a frame"), MediaKind::Image, 1600, 900, 1000, "34a.jpg");
    d.attach_media(shot, frame, "");
    let supply = |id: Id, _: html::Trim| {
        if id == frame { Some(html::Frame { src: "data:image/png;base64,AAAA".to_string(), width: 1600.0, height: 900.0, moments: 1 }) } else { None }
    };

    let page = html::document(&sheet(&d), &supply, Print::Screen, 1.0, "", &Style::standard_style());
    assert!(page.contains("src=\"data:image/png;base64,AAAA\""));
    // **No SVG anywhere.** A picture nobody has drawn on carries no marks
    // layer at all — the frame box it now sits in is a frame box, not a mark.
    assert!(!page.contains("<svg"));
    assert!(!page.contains("class=\"marked\""));
}

/// **The page and the print are one page.** His instruction, 2026-09-01:
/// *"Whatever I see in the document view in the app, should be reflected in
/// the export."* `html::doc` holds the measurements and
/// `studio/Sources/Document.swift`'s `Page` mirrors them; this only proves
/// the Rust half actually reaches the stylesheet — that every number is
/// written into the sheet as a fraction of the root rather than being
/// re-typed as a literal somewhere. Nothing here can see the Swift file, so
/// if you move a number there, move it here.
#[test]
fn the_printed_page_is_set_from_the_document_view_s_own_measurements() {
    use shotlister_engine::export::html::doc;

    let sheet = sheet(&sample().0);
    let page = html::document(&sheet, &html::no_frames, Print::Document, 1.0, "", &Style::standard_style());

    for (what, points) in [
        ("the body", doc::BODY),
        ("a shot's title", doc::TITLE),
        ("the number in the margin", doc::SHOT_NUMBER),
        ("the technical line", doc::TECHNICAL),
        ("a note", doc::NOTES),
        ("a scene's number", doc::SCENE_NUMBER),
        ("a scene's heading", doc::SCENE_HEADING),
        ("the sheet title", doc::SHEET_TITLE),
        ("the small capitals", doc::CAPTION),
        ("the gutter", doc::GUTTER),
    ] {
        let asked = doc::rem(points);
        assert!(page.contains(&asked), "{what} ({points}pt = {asked}) is not in the stylesheet");
    }

    // One inch of margin comes from the printed rectangle, so the page itself
    // must carry none — two inches is a different document.
    assert!(page.contains(".doc-wrap { padding: 0;"));
    // 612 − 144 − 60. Every frame's width is a fraction of this, on both
    // sides, or a picture is one size on screen and another on paper.
    assert_eq!(doc::measure(), 408.0);
}

/// The dial reads 100% and means "as designed", per kind. A document at 100%
/// is the app's page at its own points; the table and the storyboard keep the
/// size everybody was exporting them at anyway.
#[test]
fn a_hundred_per_cent_is_what_each_page_was_drawn_at() {
    use shotlister_engine::export::html::{stylesheet, FrameSize};

    let root = |print| {
        let sheet = stylesheet(print, 1.0, FrameSize::default(), &Style::standard_style());
        let at = sheet.find("font-size: ").unwrap() + "font-size: ".len();
        sheet[at..].split("px").next().unwrap().parse::<f64>().unwrap()
    };
    assert_eq!(root(Print::Document), 16.00);
    assert_eq!(root(Print::Table), 13.60);
    assert_eq!(root(Print::Storyboard), 13.60);
    // A point is 4/3 of a pixel on a screen, which is how the share page
    // stays the size it has always been.
    assert!((root(Print::Screen) - 21.33).abs() < 0.01);
}

/// His ask, 2026-09-03: *"we should include font color as an option across the
/// board"*. The class carries the ink and the printed page reads it, the same
/// way the size and the face already do — so what he sets on the document view
/// is what comes out of the printer.
#[test]
fn the_ink_he_sets_on_a_class_reaches_the_printed_page() {
    use shotlister_engine::docstyle::{Case, Class, Colour, Face, Setting};
    use shotlister_engine::export::html::{stylesheet, FrameSize};

    let red = Colour::read("#b3261e").unwrap();
    let style = Style::standard_style().with(
        Class::Notes,
        Setting { size: 11.5, face: Face::Serif, case: Case::AsTyped, colour: red },
    );
    let sheet = stylesheet(Print::Document, 1.0, FrameSize::default(), &style);
    let notes = sheet.split(".shot-notes {").nth(1).expect("the notes rule");
    let notes = notes.split('}').next().unwrap();
    assert!(notes.contains("color: #b3261e"), "the note kept the old grey: {notes}");

    // And a class he has not touched is still drawn in the ink it always was,
    // rather than inheriting his choice.
    let body = sheet.split(".shot-desc {").nth(1).unwrap().split('}').next().unwrap();
    assert!(body.contains("color: #17171a"), "the body moved with it: {body}");
}

/// His ask, 2026-09-01: *"i would love to be able to adjust column sizes
/// manually during export for table."* A multiplier on the page's own weight,
/// not a width — so the shell never keeps a copy of the numbers, and the
/// columns still add up to a sheet of paper however hard he pulls one.
#[test]
fn a_column_can_be_given_more_of_the_page() {
    use shotlister_engine::export::html::{default_column_weights, ColumnWidths};

    let (d, _, _) = sample();
    let s = sheet(&d);

    let share = |page: &str, of: usize| -> f64 {
        let at = page.match_indices("<col style=\"width:").nth(of).unwrap().0;
        page[at..].split('"').nth(1).unwrap()
            .trim_start_matches("width:").trim_end_matches('%')
            .parse().unwrap()
    };

    let plain = html::table(&s, &html::no_frames, Print::Table, 1.0,
                            FrameSize::default(), &Default::default());
    let wide = html::table(&s, &html::no_frames, Print::Table, 1.0, FrameSize::default(),
                           &ColumnWidths::read("description:2.0"));

    // Description is the third column — number, image, title, description…
    let columns = default_column_weights(&s, FrameSize::default());
    let at = columns.iter().position(|(c, _)| c == "description").unwrap();
    assert!(share(&wide, at) > share(&plain, at) * 1.5, "asking for twice should widen it");
    // Zero-sum: everything else gives way, and the page still fills the paper.
    let total: f64 = (0..columns.len()).map(|i| share(&wide, i)).sum();
    assert!((total - 100.0).abs() < 0.5, "the columns must still sum to the paper, got {total}");

    // A dial nobody has touched changes nothing at all.
    let untouched = html::table(&s, &html::no_frames, Print::Table, 1.0,
                                FrameSize::default(), &ColumnWidths::read(""));
    assert_eq!(untouched, plain);
    // And a nonsense one is skipped rather than refusing him his shot list.
    assert!(ColumnWidths::read("description:banana,notes:").is_empty());
}

// ---- a commercial with three scripts -------------------------------------

/// **Three spots on one job print as three headed runs**, and every shot
/// says the stretch of the script it quotes in a Script column — on all
/// three pages, which is also what the portal draws. His rulings,
/// 2026-09-19: sections per script; the script plain text, quoted by shots.
#[test]
fn a_commercials_sections_and_script_column_reach_every_page() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Three Spots");
    d.set_kind(shotlister_engine::FilmKind::Commercial);
    let a = d.create_sequence("Spot A");
    let b = d.create_sequence("Spot B");
    d.set_av_script(Some(a), "The kitchen at dawn.\n\nShe comes in barefoot.\n\nLogo. Sting.");
    d.set_av_script(Some(b), "The garage.\n\nLogo. Sting.");
    for (section, words) in [(a, ["The kitchen at dawn.\n\nShe comes in barefoot.", "Logo. Sting."]), (b, ["The garage.", "Logo. Sting."])] {
        for (n, name) in ["Kitchen", "Logo wall"].iter().enumerate() {
            let scene = d.create_scene_titled(name);
            d.set(scene, f::SEQUENCE, section);
            let (shot, _) = d.add_shot_to_scene(scene);
            assert!(d.tie_shot_to_words(shot, Some(section), words[n]));
        }
    }

    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    assert!(sheet.commercial);
    assert!(sheet.columns.iter().any(|c| c == "script"));
    let starts: Vec<bool> = sheet.groups.iter().map(|g| g.section_starts).collect();
    assert_eq!(starts, vec![true, false, true, false]);
    assert_eq!(sheet.groups[1].rows[0].script, "Logo. Sting.");

    let table = html::table(&sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    let board = html::storyboard(&sheet, &html::no_frames, Print::Storyboard, 1.0, FrameSize::default());
    let paper = html::document(&sheet, &html::no_frames, Print::Document, 1.0, "", &Style::standard_style());
    for (name, page) in [("table", &table), ("storyboard", &board), ("document", &paper)] {
        assert_eq!(page.matches("class=\"section-head\"").count(), 2, "{name}: two section heads");
        assert!(page.contains(">Spot A<") && page.contains(">Spot B<"), "{name}: names them");
    }
    assert!(table.contains("<th>Script</th>"));
    assert!(paper.contains("class=\"shot-quote\""), "the document page quotes under the words");
    assert!(board.contains("class=\"card-quote\""), "and so does a card");
    // Two paragraphs quoted stay two paragraphs, in the cell.
    assert!(table.contains("<p>The kitchen at dawn.</p><p>She comes in barefoot.</p>"), "{table}");

    // A film never shows the column, and keeps its sequence heads.
    d.set_kind(shotlister_engine::FilmKind::Film);
    let film_sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    assert!(!film_sheet.columns.iter().any(|c| c == "script"));
    let film = html::table(&film_sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert_eq!(film.matches("class=\"section-head\"").count(), 2);
}

/// **A shoot day's page reads the board, and every shot on it still says
/// which script it belongs to.** His ask, 2026-09-20: *"when it comes to
/// exporting a shoot day, I dont see it sorting the scenes in the pdf the
/// way that they are sorted in the schedule … and it needs to be clear what
/// 'script' each shot is apart of still when switching back and forth."*
/// Three scenes from two scripts, arranged on the day as C, A, B: the page
/// prints them in that order, with a head over each run of one script and
/// the script's colour down every scene.
#[test]
fn a_shoot_days_page_follows_the_board_and_names_every_scenes_script() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Two Spots");
    d.set_kind(shotlister_engine::FilmKind::Commercial);
    let spot_a = d.create_sequence("Spot A");
    let spot_b = d.create_sequence("Spot B");
    let a = d.create_scene_titled("Kitchen");
    let b = d.create_scene_titled("Garage");
    let c = d.create_scene_titled("Logo wall");
    d.set(a, f::SEQUENCE, spot_a);
    d.set(b, f::SEQUENCE, spot_b);
    d.set(c, f::SEQUENCE, spot_a);
    for scene in [a, b, c] {
        d.add_shot_to_scene(scene);
    }
    let day = d.create_day();
    for scene in [a, b, c] {
        d.schedule_scene(scene, day);
    }
    // Logo wall first, then Kitchen, then Garage — not the script's order.
    d.move_scene_in_day(c, day, Some(a));

    let sheet = d.sheet(&Query::grouped_by(GroupBy::Day).on_day(day));
    let titles: Vec<&str> = sheet.groups[0].rows.iter().map(|r| r.scene_heading.as_str()).collect();
    assert_eq!(titles, vec!["Logo wall", "Kitchen", "Garage"], "the board's order");

    let table = html::table(&sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    let board = html::storyboard(&sheet, &html::no_frames, Print::Storyboard, 1.0, FrameSize::default());
    let paper = html::document(&sheet, &html::no_frames, Print::Document, 1.0, "", &Style::standard_style());
    for (name, page) in [("table", &table), ("storyboard", &board), ("document", &paper)] {
        // Logo wall and Kitchen are both Spot A and sit together on the
        // board, then Garage is Spot B: two runs, two heads.
        assert_eq!(page.matches("class=\"section-head\"").count(), 2, "{name}: a head over every run of a script");
        assert_eq!(page.matches("class=\"run insec\"").count(), if name == "table" { 3 } else { 0 }, "{name}: the ink down every scene");
        let a_at = page.find(">Spot A<").expect(name);
        let b_at = page.find(">Spot B<").expect(name);
        assert!(a_at < b_at, "{name}: Spot A's run comes first, as the board has it");
        // The order on the page is the board's, not the script's.
        let logo = page.find("Logo wall").expect(name);
        let kitchen = page.find("Kitchen").expect(name);
        let garage = page.find("Garage").expect(name);
        assert!(logo < kitchen && kitchen < garage, "{name}: the board's order");
    }
}

/// **A column the project made for itself reaches paper by its name.** The
/// export box could tick one from 2026-09-19; the page then printed its
/// slug (`c_01a0…`) as the header and nothing in the cell. Seen on Thomas
/// Light Affair's day export, 2026-09-20.
#[test]
fn a_projects_own_column_prints_its_name_and_its_values() {
    let (mut d, _, _) = sample();
    let sound = d.add_column("Sound", "single").unwrap();
    let ok = d.add_column("Approved", "check").unwrap();
    let (sound_field, ok_field) = {
        let own = d.custom_columns();
        let by = |id| own.iter().find(|c| c.id == id).unwrap().field.clone();
        (by(sound), by(ok))
    };
    let shot = d.sheet(&Query::grouped_by(GroupBy::Scene)).rows().next().unwrap().shot;
    d.set(shot, sound_field.as_str(), "MOS");
    d.set(shot, ok_field.as_str(), true);
    // A made column joins the order on its own; only its visibility is set.
    d.set_column_visible(&sound_field, true);
    d.set_column_visible(&ok_field, true);

    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    assert!(sheet.columns.contains(&sound_field), "{:?}", sheet.columns);
    let table = html::table(&sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(table.contains("<th>Sound</th>") && table.contains("<th>Approved</th>"), "named, not slugged");
    assert!(!table.contains(&format!(">{sound_field}<")), "the slug never prints");
    assert!(table.contains(">MOS</span>"), "{table}");
    assert!(table.contains("<td>\u{2713}</td>"), "a check is a tick");
}

/// **A tall row's picture column carries what it could show.** His idea,
/// 2026-09-20: a row the words make tall should spend that height on the
/// pictures — a clip's four moments stacked, a shot's other frames under
/// the key. The engine cannot know a row's height (layout decides it), so
/// the page carries the strip's four quarters and the other frames hidden,
/// plus the script that turns them on once the page is drawn.
#[test]
fn a_tall_rows_pictures_are_in_the_page_waiting() {
    let (mut d, _, _) = sample();
    let s = sheet(&d);
    let row = s.rows().next().unwrap();
    let shot = row.shot;
    let clip = d.add_media(sha256(b"a take"), MediaKind::Video, 1920, 1080, 90_000, "take.mov");
    let still = d.add_media(sha256(b"a second still"), MediaKind::Image, 1600, 900, 1000, "two.jpg");
    d.attach_media(shot, clip, "");
    d.attach_media(shot, still, "");

    let s = sheet(&d);
    let row = s.rows().find(|r| r.shot == shot).unwrap();
    assert_eq!(row.frames.len(), 2);
    let key = row.key_frame.unwrap();
    let other = *row.frames.iter().find(|f| **f != key).unwrap();
    let supply = move |id: Id, _: html::Trim| {
        if id == key {
            // The key is a clip, drawn as its strip: four moments in one.
            Some(html::Frame { src: "data:image/jpeg;base64,STRIP".to_string(), width: 1600.0, height: 900.0, moments: 4 })
        } else if id == other {
            Some(html::Frame { src: "data:image/jpeg;base64,TWO".to_string(), width: 1600.0, height: 900.0, moments: 1 })
        } else {
            None
        }
    };
    let page = html::table(&s, &supply, Print::Table, 1.0, FrameSize::default(), &Default::default());
    assert!(page.contains("data-moments=\"4\""), "the page knows the key is four moments");
    // A quarter shows the strip at a little over twice its own width and
    // height, so the gutter between the moments stays out of the box.
    assert!(page.contains("data-quarter=\"0.5498 205.79 210.53\""), "{page}");
    assert_eq!(page.matches("base64,STRIP").count(), 1, "the strip's bytes are in the page once");
    assert!(page.contains("class=\"shotframe more\" hidden"), "the other frame waits, hidden");
    assert!(page.contains("base64,TWO"));
    assert!(page.contains("stackedWide > twoByTwo"), "and the script that decides is in the page");
    assert!(!page.contains("background-image"), "never a background: WebKit would write it at full size");
}

/// **An archived scene stays off paper.** His report, 2026-09-20: *"the
/// pdf is not honoring archived scenes!!"* The Mac hid them on its own
/// screens; the export read the query, which did not know.
#[test]
fn an_archived_scene_is_left_off_every_export() {
    let (mut d, _, _) = sample();
    let before = sheet(&d).total();
    let scene = d.scene_numbered("34").unwrap();
    let its = d.placements_in_scene(scene).len();
    assert!(its > 0);
    d.archive_scene(scene, true);
    let after = sheet(&d);
    assert_eq!(after.total(), before - its, "its shots are gone from the sheet");
    assert!(!after.groups.iter().any(|g| g.label == "Scene 34"));
    // Grouped by day and flat too — one filter, every grouping.
    for group_by in [GroupBy::Day, GroupBy::Flat, GroupBy::Sequence] {
        assert_eq!(d.sheet(&Query::grouped_by(group_by)).total(), before - its, "{group_by:?}");
    }
    // A screen still asks for them, to set aside its own way.
    assert_eq!(d.sheet(&Query::grouped_by(GroupBy::Scene).with_archived()).total(), before);
}
