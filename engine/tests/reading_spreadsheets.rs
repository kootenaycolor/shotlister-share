//! Reading `.xlsx` — decompression, the archive, and the sheet.
//!
//! The fixtures are deliberately not ours. `third-party-shotlist.xlsx` was
//! written by openpyxl and `shared-strings-shotlist.xlsx` uses a shared string
//! table the way Google Sheets and Excel do. Both are compressed, which is the
//! whole reason this code exists — we may write stored entries, but nothing
//! coming back will be.

use shotlister_engine::export::{csv as export_csv, xlsx as export_xlsx};
use shotlister_engine::import::{apply, inflate::inflate, xlsx, zip};
use shotlister_engine::{DeviceId, Doc, GroupBy, Query};

const THIRD_PARTY: &[u8] = include_bytes!("fixtures/third-party-shotlist.xlsx");
const SHARED_STRINGS: &[u8] = include_bytes!("fixtures/shared-strings-shotlist.xlsx");

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

// ---- the archive -------------------------------------------------------

#[test]
fn a_compressed_archive_opens() {
    let archive = zip::read(THIRD_PARTY).expect("reads");
    assert!(archive.contains("xl/worksheets/sheet1.xml"));
    assert!(archive.contains("[Content_Types].xml"));

    // Every part came out as well-formed XML, which only happens if the
    // decompressor is right — one wrong bit and this is noise.
    let sheet = archive.text("xl/worksheets/sheet1.xml").unwrap();
    assert!(sheet.starts_with("<worksheet") || sheet.contains("<worksheet"));
    assert!(sheet.trim_end().ends_with("</worksheet>"));
}

#[test]
fn our_own_stored_archive_reads_back() {
    // We write stored entries; the reader must not assume compression.
    let d = project();
    let bytes = export_xlsx::write(
        &d.sheet(&Query::grouped_by(GroupBy::Scene)),
        &|name| d.vocabulary(name),
        &export_xlsx::no_frames,
    );

    let archive = zip::read(&bytes).expect("reads");
    assert!(archive.contains("xl/worksheets/sheet1.xml"));
    assert!(archive.contains("xl/worksheets/sheet2.xml"));
}

#[test]
fn something_that_is_not_an_archive_is_refused_cleanly() {
    assert_eq!(
        zip::read(b"this is a PDF, actually").err(),
        Some(zip::ZipError::NotAnArchive)
    );
    assert_eq!(zip::read(&[]).err(), Some(zip::ZipError::NotAnArchive));
}

#[test]
fn truncated_compressed_data_is_an_error_not_a_panic() {
    // A partial download must fail, not crash or return nonsense.
    assert!(inflate(&[0x78, 0x01, 0xff]).is_err());
    assert!(inflate(&[]).is_err());
}

// ---- the sheet ---------------------------------------------------------

#[test]
fn a_sheet_written_by_another_tool_reads() {
    let table = xlsx::read(THIRD_PARTY).expect("reads");

    assert_eq!(table.headers[0], "Day");
    assert_eq!(table.headers[2], "Shot #");
    assert_eq!(table.rows.len(), 3);
    assert_eq!(table.rows[0][2], "34A");
    // Commas and quotes inside values survive the trip.
    assert_eq!(
        table.rows[0][4],
        "Frontal Dirty Single on Milo, through the window"
    );
    assert!(table.rows[1][4].contains("\"you need them?\""));
    assert_eq!(table.rows[2][6], "Front On, Eye Level");
}

#[test]
fn a_shared_string_table_is_followed() {
    // Google Sheets and Excel store text once and reference it by index.
    let table = xlsx::read(SHARED_STRINGS).expect("reads");

    assert_eq!(table.headers, vec!["Scene #", "Shot #", "Shot Description", "Size", "Lens"]);
    assert_eq!(table.rows.len(), 2);
    assert_eq!(table.rows[0][1], "34A");
    assert_eq!(table.rows[0][2], "Wide of the car, pulls away");
    assert_eq!(table.rows[1][2], "Reverse — \"did you tell them?\"");
}

#[test]
fn a_sheet_we_wrote_reads_back_as_what_we_wrote() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, shotlister_engine::f::DESCRIPTION, "Wide of the car");
    d.set_vocab_field(shot, "lens", "37mm");

    let bytes = export_xlsx::write(
        &d.sheet(&Query::grouped_by(GroupBy::Scene)),
        &|name| d.vocabulary(name),
        &export_xlsx::no_frames,
    );
    let table = xlsx::read(&bytes).expect("reads");

    assert!(table.headers.contains(&"Shot #".to_string()));
    assert_eq!(table.rows.len(), 1, "the group band is not a row of data");
    assert!(table.rows[0].contains(&"34A".to_string()));
    assert!(table.rows[0].contains(&"Wide of the car".to_string()));
}

// ---- and into a list ---------------------------------------------------

#[test]
fn a_spreadsheet_from_somebody_else_becomes_a_list() {
    let mut d = project();
    let table = xlsx::read(THIRD_PARTY).expect("reads");
    let report = apply(&mut d, &table);

    assert_eq!(report.shots_created, 3);
    assert_eq!(report.scenes_created, vec!["34", "54"]);
    assert!(report.cameras_created.contains(&"A-Cam Alexa35".to_string()));

    // The same rules as CSV, because it is the same apply layer.
    assert!(d.vocabulary_contains("lens", "27mm"));
    assert!(d.vocabulary_contains("angle", "Eye Level"));
    let scenes = d.scenes_in_order();
    assert_eq!(d.display_number(d.placements_in_scene(scenes[0])[0]).unwrap(), "34A");
}

#[test]
fn a_spreadsheet_round_trips_without_duplicating() {
    let mut d = project();
    let scene = d.create_scene("34");
    for _ in 0..3 {
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set_vocab_field(shot, "lens", "37mm");
    }

    let bytes = export_xlsx::write(
        &d.sheet(&Query::grouped_by(GroupBy::Scene)),
        &|name| d.vocabulary(name),
        &export_xlsx::no_frames,
    );
    let report = apply(&mut d, &xlsx::read(&bytes).expect("reads"));

    assert_eq!(report.shots_created, 0, "nothing new");
    assert_eq!(report.shots_updated, 3);
    assert_eq!(d.placements_in_scene(scene).len(), 3);
}

#[test]
fn both_formats_land_in_the_same_place() {
    // The apply layer is shared, so a list should not care which door it came
    // through.
    let mut from_xlsx = project();
    apply(&mut from_xlsx, &xlsx::read(THIRD_PARTY).expect("reads"));

    let mut from_csv = project();
    let as_csv = export_csv::write(&from_xlsx.sheet(&Query::grouped_by(GroupBy::Scene)));
    apply(&mut from_csv, &shotlister_engine::import::parse(&as_csv));

    assert_eq!(
        from_xlsx.count(&Query::grouped_by(GroupBy::Flat)),
        from_csv.count(&Query::grouped_by(GroupBy::Flat))
    );
    assert_eq!(from_csv.scenes_in_order().len(), 2);
}
