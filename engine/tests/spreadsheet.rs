//! The spreadsheet writer.
//!
//! Entries are stored rather than compressed, so the XML sits in the archive as
//! plain bytes and these tests can read it without a zip reader.

use shotlister_engine::doc::f;
use shotlister_engine::export::xlsx::{self, Frame};
use shotlister_engine::export::{zip::crc32, zip::ZipWriter};
use shotlister_engine::Id;
use shotlister_engine::{DeviceId, Doc, GroupBy, Query};

fn contains(bytes: &[u8], needle: &str) -> bool {
    bytes
        .windows(needle.len())
        .any(|window| window == needle.as_bytes())
}

fn sample() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let a_cam = d.create_unit("A-Cam", "Alexa35");
    d.set(a_cam, f::COLOUR, "#b00020");

    let scene = d.create_scene("34");
    d.set(scene, f::INT_EXT, "INT");
    d.set(scene, f::LOCATION, "car");
    d.set(scene, f::TIME_OF_DAY, "day");

    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Frontal Dirty Single on Milo");
    d.set_vocab_field(shot, "size", "M/OTS");
    d.set_vocab_field(shot, "lens", "37mm");
    d.set(shot, f::UNIT, a_cam);
    d
}

fn book(d: &Doc) -> Vec<u8> {
    xlsx::write(
        &d.sheet(&Query::grouped_by(GroupBy::Day)),
        &|name| d.vocabulary(name),
        &xlsx::no_frames,
    )
}

/// Stands in for a real still. The engine never looks at the bytes.
fn frame(tag: &[u8]) -> Frame {
    Frame {
        bytes: tag.to_vec(),
        extension: "png".to_string(),
        width: 1600,
        height: 900,
        url: None,
    }
}

/// Sheet1's own header row, and only that — the hidden Lists/Ranges sheet
/// carries its own list of column names (Camera among them) regardless of
/// what the main sheet is showing, so a check for "is this column present"
/// has to look at the main sheet's header, not the whole archive.
fn main_sheet_header_row(bytes: &[u8]) -> String {
    let start = bytes.windows(9).position(|w| w == b"<row r=\"1").unwrap();
    let end = start + bytes[start..].windows(6).position(|w| w == b"</row>").unwrap() + 6;
    std::str::from_utf8(&bytes[start..end]).unwrap().to_string()
}

// ---- the archive -------------------------------------------------------

#[test]
fn crc32_matches_the_published_vector() {
    assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    assert_eq!(crc32(b""), 0);
}

#[test]
fn an_archive_has_the_shape_a_reader_expects() {
    let mut zip = ZipWriter::new();
    zip.add("hello.txt", b"world");
    let bytes = zip.finish();

    assert_eq!(&bytes[0..4], &[0x50, 0x4b, 0x03, 0x04], "local header");
    assert!(contains(&bytes, "hello.txt"));
    assert!(contains(&bytes, "world"));
    // End of central directory, which is what a reader looks for first.
    assert_eq!(&bytes[bytes.len() - 22..bytes.len() - 18], &[0x50, 0x4b, 0x05, 0x06]);
}

#[test]
fn the_same_list_exports_to_identical_bytes() {
    let d = sample();
    // No timestamps anywhere, so exports are reproducible and diffable.
    assert_eq!(book(&d), book(&d));
}

#[test]
fn every_part_a_workbook_needs_is_present() {
    let bytes = book(&sample());
    for part in [
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/styles.xml",
        "xl/worksheets/sheet1.xml",
        "xl/worksheets/sheet2.xml",
    ] {
        assert!(contains(&bytes, part), "missing {part}");
    }
}

// ---- the sheet ---------------------------------------------------------

/// The columns a fresh project shows by default — `Scene #` and `Shot #` are
/// the fixed identity block with no on-screen equivalent, and everything
/// after follows `crate::columns::DEFAULT_ORDER` with the hidden-by-default
/// three (Camera, Sequence, Shot/struck) left out. His ask, 2026-08-27: "the
/// project informs what's in the xls" — so a column this project has not
/// shown does not appear here either, exactly like it already does not
/// appear in a PDF or HTML export. `Order` was a third fixed column, removed
/// 2026-08-28 — it had no equivalent in the app at all. A regression here is
/// a silent column shift or a column reappearing that the project hid.
const DEFAULT_COLUMN_ORDER: [&str; 13] = [
    "Scene #", "Shot #", "Storyboard", "Title", "Description", "Shot Size",
    "Shot Angle", "Movement", "Lens", "Equipment", "Notes", "Tags", "Shoot Day",
];

#[test]
fn the_columns_follow_what_is_shown_on_screen() {
    let bytes = book(&sample());
    let header_row = main_sheet_header_row(&bytes);
    for header in DEFAULT_COLUMN_ORDER {
        assert!(header_row.contains(header), "missing column {header}");
    }
    // There is no Struck column — a struck shot keeps its place and is ruled
    // through instead, which is what his sheets do.
    assert!(!header_row.contains(">Shot<"));
    // Camera and Sequence are hidden by default in the Table view, so a
    // fresh project's spreadsheet does not carry them as columns either —
    // the same rule an HTML or PDF export already follows. (Both still
    // appear on the hidden Lists sheet, which is not what this checks.)
    assert!(!header_row.contains(">Camera<"));
    assert!(!header_row.contains(">Sequence<"));
}

#[test]
fn a_column_shown_on_screen_appears_once_it_is_shown() {
    let mut d = sample();
    d.set_column_visible("camera", true);
    let bytes = book(&d);
    let header_row = main_sheet_header_row(&bytes);
    assert!(header_row.contains(">Camera<"), "shown on screen, should be in the file");
}

#[test]
fn the_header_row_is_in_the_projects_own_order() {
    let bytes = book(&sample());
    let header_row = main_sheet_header_row(&bytes);
    let positions: Vec<usize> = DEFAULT_COLUMN_ORDER
        .iter()
        .map(|h| header_row.find(h).unwrap_or_else(|| panic!("{h} missing from header row")))
        .collect();
    assert!(
        positions.windows(2).all(|w| w[0] < w[1]),
        "header row out of order: {header_row}"
    );
}

#[test]
fn the_data_is_there() {
    let bytes = book(&sample());
    assert!(contains(&bytes, "34A"));
    assert!(contains(&bytes, "Frontal Dirty Single on Milo"));
    assert!(contains(&bytes, "M/OTS"));
    assert!(contains(&bytes, "A-Cam Alexa35"));
}

#[test]
fn the_header_is_frozen_and_filterable() {
    let bytes = book(&sample());
    assert!(contains(&bytes, "state=\"frozen\""));
    assert!(contains(&bytes, "<autoFilter"));
}

#[test]
fn groups_get_a_band_carrying_their_count() {
    let mut d = sample();
    let scene = d.scenes_in_order()[0];
    let day = d.create_day();
    for placement in d.placements_in_scene(scene) {
        d.schedule(placement, day);
    }
    let bytes = book(&d);

    assert!(contains(&bytes, "Day 1 — 1 shots") || contains(&bytes, "Day 1"));
    assert!(contains(&bytes, "<mergeCell"), "band should span the row");
}

#[test]
fn vocabulary_columns_get_dropdowns_and_multi_value_ones_do_not() {
    let mut d = sample();
    d.set_vocabulary("lens", &["20.7mm", "27mm", "37mm"]);
    let bytes = book(&d);

    assert!(contains(&bytes, "dataValidation"));
    assert!(contains(&bytes, "Lists!"));
    // Default order: Scene # A, Shot # B, Storyboard C, Title D,
    // Description E, Size F, Angle G, Movement H, Lens I (with its filters and
    // modifiers), Equipment J, Notes K, Tags L, Shoot Day M. (Camera and
    // Sequence are hidden by default, so neither has a column here at all.)
    assert!(contains(&bytes, "sqref=\"I2"), "lens column should validate");
    assert!(contains(&bytes, "sqref=\"F2"), "size column should validate");
    // Angle holds several values at once; a single-select list there would
    // misrepresent the field. Tags does too, even though his own sheet gives
    // it a dropdown — see the comment in xlsx.rs on why we do not.
    assert!(!contains(&bytes, "sqref=\"G2"), "angle must not validate");
    assert!(!contains(&bytes, "sqref=\"L2"), "tags must not validate");
}

#[test]
fn sequence_gets_a_dropdown_sourced_from_what_is_in_use() {
    let mut d = sample();
    // Hidden by default — showing it is the same thing showing it in the
    // Table view would be, and this is the one place a dropdown could exist
    // to validate against.
    d.set_column_visible("sequence", true);
    let scene = d.scenes_in_order()[0];
    let sequence = d.create_sequence("Girlfriend Breakup");
    d.set(scene, f::SEQUENCE, sequence);
    let bytes = book(&d);

    assert!(contains(&bytes, "sqref=\"N2"), "sequence column should validate");
    assert!(contains(&bytes, "Girlfriend Breakup"));
}

#[test]
fn the_camera_keeps_its_colour() {
    let bytes = book(&sample());
    // #b00020 becomes the eight-digit form the format wants.
    assert!(contains(&bytes, "FFB00020"));
}

/// His ask, 2026-08-28 — the one column meant to be read first should read
/// that way here too, the same reasoning `td.title` already carries in the
/// PDF/HTML export.
#[test]
fn the_title_column_is_bold() {
    let mut d = sample();
    let scene = d.scenes_in_order()[0];
    let placement = d.placements_in_scene(scene)[0];
    let shot = d.get(placement).unwrap().ref_id(f::SHOT).unwrap();
    d.set(shot, f::TITLE, "Milo VO");
    let bytes = book(&d);
    assert!(
        contains(&bytes, "<font><b/><sz val=\"10\"/><name val=\"Helvetica Neue\"/></font>"),
        "a plain bold font (no colour, no strike) should exist for Title"
    );
    assert!(contains(&bytes, "Milo VO"));
}

#[test]
fn a_struck_shot_is_ruled_through_rather_than_dropped() {
    let mut d = sample();
    let scene = d.scenes_in_order()[0];
    let placement = d.placements_in_scene(scene)[0];
    let shot = d.get(placement).unwrap().ref_id(f::SHOT).unwrap();
    d.strike(shot, true);

    let bytes = book(&d);
    assert!(contains(&bytes, "<strike/>"));
    assert!(contains(&bytes, "34A"), "still on the sheet");
}

#[test]
fn what_people_type_is_escaped() {
    let mut d = sample();
    let scene = d.scenes_in_order()[0];
    let placement = d.placements_in_scene(scene)[0];
    let shot = d.get(placement).unwrap().ref_id(f::SHOT).unwrap();
    d.set(shot, f::DESCRIPTION, "Wide <2 Shot> & \"reverse\"");

    let bytes = book(&d);
    assert!(contains(&bytes, "Wide &lt;2 Shot&gt; &amp; &quot;reverse&quot;"));
    // Raw angle brackets in cell text would make the file refuse to open.
    assert!(!contains(&bytes, "<2 Shot>"));
}

#[test]
fn an_empty_list_still_produces_a_valid_workbook() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Empty");
    let bytes = book(&d);

    assert!(contains(&bytes, "xl/workbook.xml"));
    assert!(contains(&bytes, "Description"));
}

// ---- frames in cells ---------------------------------------------------

fn with_frames(d: &Doc, supply: &dyn Fn(&[Id]) -> Option<Frame>) -> Vec<u8> {
    xlsx::write(
        &d.sheet(&Query::grouped_by(GroupBy::Day)),
        &|name| d.vocabulary(name),
        supply,
    )
}

fn frame_sample() -> (Doc, Id) {
    use shotlister_engine::media::MediaKind;
    use shotlister_engine::sha256;

    let mut d = sample();
    let scene = d.scenes_in_order()[0];
    let placement = d.placements_in_scene(scene)[0];
    let shot = d.get(placement).unwrap().ref_id(f::SHOT).unwrap();
    let media = d.add_media(sha256(b"a frame"), MediaKind::Image, 1600, 900, 900, "34a.png");
    d.attach_media(shot, media, "");
    (d, media)
}

#[test]
fn a_sheet_with_no_frames_carries_no_drawing_parts() {
    let bytes = book(&sample());
    assert!(!contains(&bytes, "xl/drawings/drawing1.xml"));
    assert!(!contains(&bytes, "<drawing"));
}

#[test]
fn the_key_frame_lands_in_the_image_column() {
    let (d, media) = frame_sample();
    let bytes = with_frames(&d, &|ids| ids.contains(&media).then(|| frame(b"PNGBYTES")));

    assert!(contains(&bytes, "xl/drawings/drawing1.xml"));
    assert!(contains(&bytes, "xl/media/image1.png"));
    assert!(contains(&bytes, "xl/worksheets/_rels/sheet1.xml.rels"));
    assert!(contains(&bytes, "PNGBYTES"), "the bytes must be embedded");
    // Column 2 (0-indexed) is Storyboard by default — Scene # and Shot # are
    // the two fixed columns ahead of it — and the anchor sits on the shot's
    // row.
    assert!(contains(&bytes, "<xdr:col>2</xdr:col>"));
    assert!(contains(&bytes, "oneCellAnchor"));
}

/// A picture the sheet can go and fetch belongs *in* the cell, not over it.
///
/// The whole point: a floating drawing is left behind by a sort, a formula is
/// carried by one. Measured against his own Google account on 2026-09-04.
#[test]
fn a_frame_with_an_address_is_written_into_the_cell() {
    let (d, media) = frame_sample();
    let address = "https://sync.example.studio/i/00000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png";
    let bytes = with_frames(&d, &|ids| {
        ids.contains(&media).then(|| Frame {
            url: Some(address.to_string()),
            ..frame(b"PNGBYTES")
        })
    });

    assert!(
        contains(&bytes, &format!(r#"<f>IMAGE("{address}")</f>"#)),
        "the cell should hold the formula that fetches the frame"
    );
    // **Nothing is carried in the file.** The picture is fetched, so embedding
    // it too would ship the same frame twice and draw one on top of the other.
    assert!(!contains(&bytes, "PNGBYTES"), "the bytes must not be embedded as well");
    assert!(!contains(&bytes, "xl/drawings/drawing1.xml"), "there is no drawing to make");
    assert!(!contains(&bytes, "oneCellAnchor"));
    // The row is still grown to the height the picture will draw at, so the
    // sheet looks the same whichever way the frame got there.
    assert!(contains(&bytes, r#"customHeight="1""#));
}

/// Without an address, nothing changes — a workbook that has to stand on its
/// own still carries its pictures.
#[test]
fn a_frame_with_no_address_is_still_pasted_over_the_cell() {
    let (d, media) = frame_sample();
    let bytes = with_frames(&d, &|ids| ids.contains(&media).then(|| frame(b"PNGBYTES")));

    assert!(contains(&bytes, "PNGBYTES"));
    assert!(contains(&bytes, "oneCellAnchor"));
    assert!(!contains(&bytes, "<f>IMAGE("));
}

#[test]
fn a_frame_used_on_several_rows_is_stored_once() {
    let (mut d, media) = frame_sample();
    let scene = d.scenes_in_order()[0];
    // Same frame on a second shot — content addressing should not pay twice.
    let (second, _) = d.add_shot_to_scene(scene);
    d.attach_media(second, media, "");

    let bytes = with_frames(&d, &|ids| ids.contains(&media).then(|| frame(b"ONLYONCE")));

    assert!(contains(&bytes, "xl/media/image1.png"));
    assert!(!contains(&bytes, "xl/media/image2.png"));
    let occurrences = bytes
        .windows(8)
        .filter(|w| *w == b"ONLYONCE")
        .count();
    assert_eq!(occurrences, 1, "bytes should appear once in the archive");
}

#[test]
fn a_frame_the_caller_cannot_supply_is_simply_absent() {
    let (d, _) = frame_sample();
    let bytes = with_frames(&d, &|_| None);

    assert!(!contains(&bytes, "<drawing"));
    // And the rest of the sheet is unaffected.
    assert!(contains(&bytes, "34A"));
}

#[test]
fn a_tall_frame_is_fitted_rather_than_stretched() {
    let (d, media) = frame_sample();
    let upright = Frame {
        bytes: b"TALL".to_vec(),
        extension: "png".to_string(),
        width: 1080,
        height: 1920,
        url: None,
        };
    let bytes = with_frames(&d, &|ids| ids.contains(&media).then(|| upright.clone()));

    // 92px tall at 9525 EMU per pixel; the width follows the shape.
    assert!(contains(&bytes, "cy=\"876300\""), "height should be capped");
}

/// The largest `ht="…"` found anywhere in the archive's raw XML — entries
/// are stored uncompressed (see the module doc), so this can scan the bytes
/// directly rather than unzipping.
fn max_row_height(bytes: &[u8]) -> f32 {
    let needle = b"ht=\"";
    let mut max = 0.0f32;
    let mut i = 0;
    while let Some(pos) = bytes[i..].windows(needle.len()).position(|w| w == needle) {
        let start = i + pos + needle.len();
        let Some(rel_end) = bytes[start..].iter().position(|&b| b == b'"') else { break };
        let end = start + rel_end;
        if let Ok(value) = std::str::from_utf8(&bytes[start..end]).unwrap_or("").parse::<f32>() {
            max = max.max(value);
        }
        i = end;
    }
    max
}

/// His ask, 2026-08-28: "images should be the determining size of the row
/// unless a text field is larger." Before this, a picture pinned the row to
/// exactly its own height (`customHeight` turns off the usual auto-fit), so
/// a short frame beside a long description cut the text off instead of the
/// row growing for it.
#[test]
fn a_long_description_grows_the_row_past_a_short_frame() {
    let (mut d, media) = frame_sample();
    let scene = d.scenes_in_order()[0];
    let placement = d.placements_in_scene(scene)[0];
    let shot = d.get(placement).unwrap().ref_id(f::SHOT).unwrap();
    let long = vec!["word"; 80].join(" ");
    d.set(shot, f::DESCRIPTION, long.as_str());
    // Short and wide — a frame this shape scales down to a handful of
    // points tall, nowhere near enough for eighty words of description.
    let short = Frame { bytes: b"SHORT".to_vec(), extension: "png".to_string(), width: 400, height: 40, url: None };
    let bytes = with_frames(&d, &|ids| ids.contains(&media).then(|| short.clone()));

    assert!(
        max_row_height(&bytes) > 60.0,
        "the row should have grown for the text, not stayed pinned to the short frame's own size"
    );
}

#[test]
fn the_image_content_type_is_declared() {
    let (d, media) = frame_sample();
    let bytes = with_frames(&d, &|ids| ids.contains(&media).then(|| frame(b"X")));
    assert!(contains(&bytes, r#"<Default Extension="png" ContentType="image/png"/>"#));
    assert!(contains(&bytes, "drawing+xml"));
}

// ---- the four-sheet workbook -------------------------------------------

fn book4(d: &Doc) -> Vec<u8> {
    xlsx::workbook(
        &d.sheet(&Query::grouped_by(GroupBy::Flat)),
        &d.sheet(&Query::grouped_by(GroupBy::Day)),
        &d.sheet(&Query::grouped_by(GroupBy::Sequence)),
        &|name| d.vocabulary(name),
        &xlsx::no_frames,
    )
}

#[test]
fn the_workbook_has_his_four_tabs() {
    let bytes = book4(&sample());
    for name in ["Master Shot List", "Group by Day", "Group by Sequence", "Ranges"] {
        assert!(contains(&bytes, name), "missing tab {name}");
    }
    assert!(!contains(&bytes, "state=\"hidden\""), "Ranges should be visible, not hidden");
    for part in [
        "xl/worksheets/sheet1.xml",
        "xl/worksheets/sheet2.xml",
        "xl/worksheets/sheet3.xml",
        "xl/worksheets/sheet4.xml",
    ] {
        assert!(contains(&bytes, part), "missing {part}");
    }
}

#[test]
fn the_same_project_exports_to_identical_workbook_bytes() {
    let d = sample();
    assert_eq!(book4(&d), book4(&d));
}

#[test]
fn pictures_are_drawn_on_the_master_sheet_only() {
    let (d, media) = frame_sample();
    let bytes = xlsx::workbook(
        &d.sheet(&Query::grouped_by(GroupBy::Flat)),
        &d.sheet(&Query::grouped_by(GroupBy::Day)),
        &d.sheet(&Query::grouped_by(GroupBy::Sequence)),
        &|name| d.vocabulary(name),
        &|ids| ids.contains(&media).then(|| frame(b"ONMASTERONLY")),
    );
    // One drawing, one relationship file — sheet1's. Repeating the picture on
    // the grouped tabs would triple the file for nothing anyone would see.
    assert!(contains(&bytes, "xl/drawings/drawing1.xml"));
    assert!(contains(&bytes, "xl/worksheets/_rels/sheet1.xml.rels"));
    assert!(!contains(&bytes, "xl/worksheets/_rels/sheet2.xml.rels"));
    assert!(!contains(&bytes, "xl/worksheets/_rels/sheet3.xml.rels"));
    // The frame's own bytes appear exactly once in the archive.
    let occurrences = bytes.windows(12).filter(|w| *w == b"ONMASTERONLY").count();
    assert_eq!(occurrences, 1);
}

#[test]
fn the_ranges_tab_carries_the_vocabulary_and_drives_the_dropdowns() {
    let mut d = sample();
    d.set_vocabulary("lens", &["20.7mm", "27mm", "37mm"]);
    let bytes = book4(&d);
    assert!(contains(&bytes, "37mm"));
    // The tab is called Ranges in the four-sheet workbook, not Lists — a
    // dropdown whose formula still says "Lists!" points at a sheet that does
    // not exist. Excel does not error on that; it just shows no list at all,
    // which is what shipped before this test existed to catch it.
    assert!(contains(&bytes, "Ranges!"), "dropdown formulas should point at Ranges");
    assert!(!contains(&bytes, "Lists!"), "there is no sheet called Lists in this workbook");
}
