//! Reading a list back in.
//!
//! The case that matters most is the round trip: a list goes out to a
//! spreadsheet, somebody without the app works on it, and it comes back.

use shotlister_engine::doc::f;
use shotlister_engine::export::csv as export_csv;
use shotlister_engine::import::{apply, csv, Table};
use shotlister_engine::{DeviceId, Doc, GroupBy, Query};

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

fn sheet(text: &str) -> Table {
    csv::parse(text)
}

// ---- parsing -----------------------------------------------------------

#[test]
fn a_field_can_contain_the_delimiter() {
    let table = sheet("Scene #,Shot Description\n34,\"Wide, then push in\"\n");
    assert_eq!(table.rows[0][1], "Wide, then push in");
}

#[test]
fn a_field_can_contain_quotes_and_line_breaks() {
    // The prototype split on commas and lost a column to every sentence.
    let table = sheet(
        "Scene #,Notes\n34,\"He says \"\"go\"\", then\nwe cut\"\n",
    );
    assert_eq!(table.rows.len(), 1);
    assert_eq!(table.rows[0][1], "He says \"go\", then\nwe cut");
}

#[test]
fn both_line_ending_conventions_read_the_same() {
    let unix = sheet("Scene #,Size\n34,CU\n35,W\n");
    let windows = sheet("Scene #,Size\r\n34,CU\r\n35,W\r\n");
    assert_eq!(unix.rows, windows.rows);
    assert_eq!(unix.rows.len(), 2);
}

#[test]
fn a_trailing_newline_is_not_a_row() {
    let table = sheet("Scene #,Size\n34,CU\n\n");
    assert_eq!(table.rows.len(), 1);
}

// ---- creating ----------------------------------------------------------

#[test]
fn a_sheet_becomes_a_list() {
    let mut d = project();
    let table = sheet(
        "Scene #,Shot #,Shot Description,Size,Lens\n\
         34,34A,Frontal Dirty Single,M/OTS,37mm\n\
         34,34B,Reverse,CU/OTS,27mm\n",
    );

    let report = apply(&mut d, &table);

    assert_eq!(report.shots_created, 2);
    assert_eq!(report.scenes_created, vec!["34"]);
    let scene = d.scenes_in_order()[0];
    let placements = d.placements_in_scene(scene);
    assert_eq!(d.display_number(placements[0]).unwrap(), "34A");
    assert_eq!(d.display_number(placements[1]).unwrap(), "34B");
}

#[test]
fn a_new_scene_is_marked_unknown_rather_than_guessed() {
    let mut d = project();
    apply(&mut d, &sheet("Scene #,Shot #\n34,34A\n"));

    let scene = d.scenes_in_order()[0];
    // Obvious that it still needs filling in, rather than plausibly wrong.
    assert_eq!(d.scene_heading(scene).unwrap(), "INT. UNKNOWN - DAY");
}

#[test]
fn values_the_project_has_not_seen_join_its_lists() {
    let mut d = project();
    apply(
        &mut d,
        &sheet("Scene #,Shot #,Size,Lens,Angle\n34,34A,COWBOY/OTS,20.7mm,\"Front On, Eye Level\"\n"),
    );

    assert!(d.vocabulary_contains("size", "COWBOY/OTS"));
    assert!(d.vocabulary_contains("lens", "20.7mm"));
    // A multi-value cell splits rather than landing as one long string.
    assert!(d.vocabulary_contains("angle", "Front On"));
    assert!(d.vocabulary_contains("angle", "Eye Level"));
}

#[test]
fn a_camera_the_project_has_not_seen_joins_it_too() {
    let mut d = project();
    let report = apply(
        &mut d,
        &sheet("Scene #,Shot #,Camera\n34,34A,B-Cam Alexa35\n"),
    );

    assert_eq!(report.cameras_created, vec!["B-Cam Alexa35"]);
    let sheet_out = d.sheet(&Query::grouped_by(GroupBy::Scene));
    let row = sheet_out.rows().next().unwrap();
    assert_eq!(row.camera.as_ref().unwrap().display(), "B-Cam Alexa35");
}

#[test]
fn sequences_are_created_and_attached_to_the_scene() {
    let mut d = project();
    let report = apply(
        &mut d,
        &sheet("Scene #,Shot #,Sequence\n34,34A,Hospital Chase\n"),
    );

    assert_eq!(report.sequences_created, vec!["Hospital Chase"]);
    let scene = d.scenes_in_order()[0];
    assert!(d.get(scene).unwrap().ref_id(f::SEQUENCE).is_some());
}

// ---- updating rather than duplicating ----------------------------------

#[test]
fn a_row_that_already_exists_updates_in_place() {
    let mut d = project();
    apply(&mut d, &sheet("Scene #,Shot #,Lens\n34,34A,37mm\n"));

    // The sheet comes back with one cell changed.
    let report = apply(&mut d, &sheet("Scene #,Shot #,Lens\n34,34A,50mm\n"));

    assert_eq!(report.shots_created, 0);
    assert_eq!(report.shots_updated, 1);
    let scene = d.scenes_in_order()[0];
    assert_eq!(d.placements_in_scene(scene).len(), 1, "must not duplicate");
    let shot = d
        .get(d.placements_in_scene(scene)[0])
        .unwrap()
        .ref_id(f::SHOT)
        .unwrap();
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("50mm"));
}

#[test]
fn a_blank_cell_leaves_what_is_there_alone() {
    let mut d = project();
    apply(
        &mut d,
        &sheet("Scene #,Shot #,Lens,Notes\n34,34A,37mm,Hide the second camera\n"),
    );

    // Somebody else's copy of the sheet has no Notes column filled in.
    apply(&mut d, &sheet("Scene #,Shot #,Lens,Notes\n34,34A,50mm,\n"));

    let scene = d.scenes_in_order()[0];
    let shot = d
        .get(d.placements_in_scene(scene)[0])
        .unwrap()
        .ref_id(f::SHOT)
        .unwrap();
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("50mm"));
    assert_eq!(
        d.get(shot).unwrap().text(f::NOTES),
        Some("Hide the second camera"),
        "an empty column must not wipe work"
    );
}

#[test]
fn a_letter_the_project_cannot_give_is_reported_not_forced() {
    let mut d = project();
    apply(&mut d, &sheet("Scene #,Shot #\n34,34A\n"));

    // Somebody typed a letter of their own for a brand new row.
    let report = apply(&mut d, &sheet("Scene #,Shot #\n34,34Z\n"));

    assert_eq!(report.shots_created, 1);
    assert_eq!(report.renumbered, vec![("34Z".to_string(), "34B".to_string())]);
}

// ---- the round trip ----------------------------------------------------

#[test]
fn a_list_survives_going_out_and_coming_back() {
    let mut d = project();
    let scene = d.create_scene("34");
    d.set(scene, f::INT_EXT, "INT");
    d.set(scene, f::LOCATION, "car");
    d.set(scene, f::TIME_OF_DAY, "day");
    let a_cam = d.create_unit("A-Cam", "Alexa35");
    for letter in 0..3 {
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set(shot, f::DESCRIPTION, format!("Shot number {letter}"));
        d.set_vocab_field(shot, "size", "M/OTS");
        d.set_vocab_field(shot, "lens", "37mm");
        d.set(shot, f::UNIT, a_cam);
    }

    let exported = export_csv::write(&d.sheet(&Query::grouped_by(GroupBy::Scene)));
    let report = apply(&mut d, &sheet(&exported));

    // Everything matched; nothing was added.
    assert_eq!(report.shots_created, 0);
    assert_eq!(report.shots_updated, 3);
    assert_eq!(d.placements_in_scene(scene).len(), 3);
    assert!(report.scenes_created.is_empty());
    // And the scene it already had was not reset to UNKNOWN.
    assert_eq!(d.scene_heading(scene).unwrap(), "INT. CAR - DAY");
}

// ---- being forgiving, and being strict ---------------------------------

#[test]
fn headings_do_not_have_to_match_exactly() {
    let mut d = project();
    // Somebody's own template: different words, different case, no hash.
    let report = apply(
        &mut d,
        &sheet("scene,shot no,description,framing,focal length\n34,34A,A wide,W,27mm\n"),
    );

    assert_eq!(report.shots_created, 1);
    let scene = d.scenes_in_order()[0];
    let shot = d
        .get(d.placements_in_scene(scene)[0])
        .unwrap()
        .ref_id(f::SHOT)
        .unwrap();
    assert_eq!(d.get(shot).unwrap().text("size"), Some("W"));
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("27mm"));
}

#[test]
fn one_bad_row_does_not_cost_the_others() {
    let mut d = project();
    let report = apply(
        &mut d,
        &sheet("Scene #,Shot #\n34,34A\n,34B\n35,35A\n"),
    );

    assert_eq!(report.shots_created, 2);
    assert_eq!(report.skipped.len(), 1);
    assert_eq!(report.skipped[0].0, 3, "reports the spreadsheet line number");
}

#[test]
fn a_sheet_with_no_scene_column_is_refused_rather_than_half_applied() {
    let mut d = project();
    let report = apply(&mut d, &sheet("Shot #,Size\n34A,CU\n"));

    assert_eq!(report.shots_created, 0);
    assert!(report.skipped[0].1.contains("Scene"));
}

#[test]
fn a_day_the_project_does_not_have_is_reported_rather_than_invented() {
    let mut d = project();
    d.create_day(); // Day 1 exists
    let report = apply(
        &mut d,
        &sheet("Day,Scene #,Shot #\nDay 1,34,34A\nDay 7,34,34B\n"),
    );

    // Day 1 scheduled; Day 7 left alone, because which day something shoots is
    // a decision and not one an import gets to make.
    assert_eq!(report.days_not_found, vec!["Day 7"]);
    let day = d.days_in_order()[0];
    assert_eq!(d.placements_on_day(day).len(), 1);
}

#[test]
fn the_report_reads_like_a_sentence() {
    let mut d = project();
    let report = apply(&mut d, &sheet("Scene #,Shot #\n34,34A\n34,34B\n"));
    assert_eq!(report.summary(), "2 added, 1 new scenes");

    let nothing = apply(&mut project(), &sheet("Scene #,Shot #\n"));
    assert_eq!(nothing.summary(), "Nothing to import");
}
