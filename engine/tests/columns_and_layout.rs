//! Column order and visibility, and where a frame sits.

use shotlister_engine::docstyle::Style;
use shotlister_engine::columns;
use shotlister_engine::doc::f;
use shotlister_engine::export::{html, FrameSize, Print};
use shotlister_engine::layout::FramePosition;
use shotlister_engine::{DeviceId, Doc, GroupBy, Id, Query, Value};

fn project() -> (Doc, Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Frontal Dirty Single on Milo");
    d.set_vocab_field(shot, "size", "M/OTS");
    d.set_vocab_list(shot, "angle", &["Short-Sided"]);
    d.set_vocab_field(shot, "movement", "Static");
    d.set_vocab_field(shot, "lens", "37mm");
    d.set_vocab_field(shot, "support", "Handheld");
    (d, shot)
}

// ---- columns -----------------------------------------------------------

#[test]
fn a_project_starts_with_the_order_the_sheets_use() {
    let (d, _) = project();
    let order = d.column_order();
    assert_eq!(order, columns::DEFAULT_ORDER.map(String::from).to_vec());
    assert_eq!(order[0], "image");
}

#[test]
fn the_order_can_be_changed_and_is_remembered() {
    let (mut d, _) = project();
    d.set_column_order(&["description", "lens", "size", "image"]);

    let order = d.column_order();
    // What was asked for stays in the order it was asked for, wherever the
    // columns nobody mentioned end up around it.
    let asked = ["description", "lens", "size", "image"];
    let places: Vec<usize> = asked
        .iter()
        .map(|name| order.iter().position(|kept| kept == name).expect("kept"))
        .collect();
    assert!(places.windows(2).all(|pair| pair[0] < pair[1]), "{order:?}");
    // Columns not mentioned keep their default place rather than vanishing, so
    // a build that adds one does not lose it.
    assert_eq!(order.len(), columns::DEFAULT_ORDER.len());
    assert!(order.contains(&"notes".to_string()));
}

#[test]
fn hiding_a_column_does_not_move_it() {
    let (mut d, _) = project();
    let before = d.column_order();

    d.set_column_visible("lens", false);
    assert!(!d.is_column_visible("lens"));
    assert!(!d.visible_columns().contains(&"lens".to_string()));

    d.set_column_visible("lens", true);
    // Back where it was, not appended to the end.
    assert_eq!(d.column_order(), before);
}

#[test]
fn the_technical_line_follows_the_column_order() {
    let (mut d, _) = project();
    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    assert_eq!(
        sheet.rows().next().unwrap().technical_line_for(&sheet.columns),
        "M/OTS – Short-Sided – Static – 37mm – Handheld"
    );

    // Move lens to the front and the line follows, because there is one order
    // and it is set in one place.
    d.set_column_order(&["lens", "size", "angle", "movement", "support"]);
    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    assert_eq!(
        sheet.rows().next().unwrap().technical_line_for(&sheet.columns),
        "37mm – M/OTS – Short-Sided – Static – Handheld"
    );
}

#[test]
fn a_hidden_column_is_not_in_the_technical_line_either() {
    let (mut d, _) = project();
    d.set_column_visible("lens", false);

    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    let line = sheet.rows().next().unwrap().technical_line_for(&sheet.columns);

    assert!(!line.contains("37mm"));
    assert!(line.contains("M/OTS"));
}

#[test]
fn a_sheet_carries_the_columns_it_was_made_with() {
    let (mut d, _) = project();
    d.set_column_visible("notes", false);

    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    // A share page carries what you were looking at rather than everything.
    assert!(!sheet.columns.contains(&"notes".to_string()));
    assert!(sheet.columns.contains(&"description".to_string()));
}

// ---- where the frame sits ----------------------------------------------

#[test]
fn a_frame_has_four_places_it_can_go() {
    let (mut d, shot) = project();
    for position in [
        FramePosition::Above,
        FramePosition::Below,
        FramePosition::Left,
        FramePosition::Right,
    ] {
        d.set_frame_position(shot, position);
        assert_eq!(d.frame_position(shot), position);
    }
}

#[test]
fn the_old_name_for_alongside_still_reads() {
    // Projects written before there were two sides said "beside".
    assert_eq!(FramePosition::parse("beside"), FramePosition::Left);
    assert_eq!(FramePosition::parse("right"), FramePosition::Right);
    assert_eq!(FramePosition::parse("above"), FramePosition::Above);
    assert_eq!(FramePosition::parse("anything"), FramePosition::Below);

    assert!(FramePosition::Left.is_alongside());
    assert!(FramePosition::Right.is_alongside());
    assert!(!FramePosition::Above.is_alongside());
}

#[test]
fn each_position_renders_as_itself() {
    let (mut d, shot) = project();
    let frame = d.add_media(
        shotlister_engine::sha256(b"f"),
        shotlister_engine::MediaKind::Image,
        1600,
        900,
        10,
        "f.png",
    );
    d.attach_media(shot, frame, "");

    let page = |d: &Doc| {
        html::document(
            &d.sheet(&Query::grouped_by(GroupBy::Scene)),
            &|_, _| Some(html::Frame { src: "f.png".to_string(), width: 1600.0, height: 900.0, moments: 1 }),
            Print::Document,
            1.0,"",
            &Style::standard_style(),
        )
    };

    d.set_frame_position(shot, FramePosition::Right);
    let right = page(&d);
    assert!(right.contains("class=\"shot right\""));
    assert!(right.contains("shot-body"), "text keeps its own column");

    d.set_frame_position(shot, FramePosition::Above);
    let above = page(&d);
    assert!(above.contains("class=\"shot above\""));
    // The frame is the first thing in the shot. Look at the body only — the
    // stylesheet mentions every class name too, and earlier in the file.
    let body = &above[above.find("<body>").unwrap()..];
    let frames_at = body.find("class=\"frames").unwrap();
    let head_at = body.find("shot-letter").unwrap();
    assert!(frames_at < head_at, "the frame should come first");

    d.set_frame_position(shot, FramePosition::Below);
    let below = page(&d);
    assert!(below.contains("class=\"shot\""));
}

// ---- custom columns ----------------------------------------------------

#[test]
fn a_project_can_make_a_column_of_its_own() {
    let (mut d, shot) = project();
    let id = d.add_column("Sound", "single").expect("a known kind is accepted");
    let made = d.custom_columns();
    assert_eq!(made.len(), 1);
    assert_eq!(made[0].label, "Sound");
    assert_eq!(made[0].kind, "single");
    assert_eq!(made[0].id, id);

    // It stands at the end of the order, where it was made, and the order
    // survives being rearranged around it.
    let order = d.column_order();
    assert_eq!(order.last().unwrap(), &made[0].field);
    d.set_column_order(&[&made[0].field, "description", "image"]);
    assert_eq!(d.column_order()[0], made[0].field);

    // Values go under the field slug through the same generic path as
    // everything else, and a single-choice column teaches the project.
    d.set_vocab_field(shot, &made[0].field, "Sync");
    assert_eq!(d.vocabulary(&made[0].field), vec!["Sync".to_string()]);
}

#[test]
fn a_kind_nothing_understands_is_refused() {
    let (mut d, _) = project();
    assert!(d.add_column("Mystery", "hologram").is_none());
    assert!(d.add_column("   ", "text").is_none());
    assert!(d.custom_columns().is_empty());
    assert_eq!(d.column_order().len(), 15);
}

#[test]
fn an_undone_column_is_a_husk_and_husks_are_invisible() {
    let (mut d, _) = project();
    d.add_column("Sound", "single").unwrap();
    assert_eq!(d.column_order().len(), 16);

    // Undo strips the fields but keeps the record — field-level undo. A
    // column with no label is nothing to draw, so it leaves the order too.
    d.undo();
    assert!(d.custom_columns().is_empty());
    assert_eq!(d.column_order().len(), 15);

    d.redo();
    assert_eq!(d.custom_columns().len(), 1);
    assert_eq!(d.column_order().len(), 16);
}

#[test]
fn renaming_a_column_keeps_its_values() {
    let (mut d, shot) = project();
    d.add_column("Sound", "text").unwrap();
    let field = d.custom_columns()[0].field.clone();
    d.set(shot, field.as_str(), "MOS");

    d.rename_column(&field, "Audio");
    let made = d.custom_columns();
    assert_eq!(made[0].label, "Audio");
    assert_eq!(made[0].field, field);
    assert_eq!(
        d.get(shot).and_then(|r| r.get(&field)).and_then(|v| v.as_text()),
        Some("MOS")
    );
}

#[test]
fn a_custom_column_can_be_hidden_like_any_other() {
    let (mut d, _) = project();
    d.add_column("Sound", "check").unwrap();
    let field = d.custom_columns()[0].field.clone();
    d.set_column_visible(&field, false);
    assert!(!d.is_column_visible(&field));
    assert!(!d.visible_columns().contains(&field));
    d.set_column_visible(&field, true);
    assert!(d.visible_columns().contains(&field));
}

/// **A column the project made can be taken away — with what is written in it.**
///
/// His note on the row: *"needs to say what it takes with it first."* The count
/// is what a person is shown before agreeing; the delete is what happens after.
#[test]
fn deleting_a_column_takes_its_values_with_it() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Columns");
    let scene = doc.create_scene("1");
    let column = doc.add_column("Rigging", "text").expect("made");
    let field = doc
        .custom_columns()
        .into_iter()
        .find(|c| c.id == column)
        .expect("is there")
        .field;

    let (one, _) = doc.add_shot_to_scene(scene);
    let (two, _) = doc.add_shot_to_scene(scene);
    let (three, _) = doc.add_shot_to_scene(scene);
    doc.set(one, &field, Value::text("low mode"));
    doc.set(two, &field, Value::text("steadicam"));
    let _ = three;

    // Counted before it is offered.
    assert_eq!(doc.shots_with_value(&field), 2);

    assert!(doc.delete_column(&field));
    assert!(
        doc.custom_columns().iter().all(|c| c.field != field),
        "the column is gone"
    );
    assert!(
        !doc.column_order().iter().any(|name| *name == field),
        "and it is out of the order, or it comes back as an empty header"
    );
    assert_eq!(doc.shots_with_value(&field), 0, "and so are its values");
}

/// A built-in column is the app's shape, not the project's, so it is refused
/// rather than half-deleted.
#[test]
fn a_built_in_column_is_not_the_projects_to_delete() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Columns");
    assert!(!doc.delete_column("size"));
    assert!(!doc.delete_column("nothing_like_this"));
}

/// Taking a column away is one thing to take back — the column and every value
/// in it come back together.
#[test]
fn deleting_a_column_is_one_undo() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Columns");
    let scene = doc.create_scene("1");
    doc.add_column("Rigging", "text").expect("made");
    let field = doc.custom_columns()[0].field.clone();
    let (one, _) = doc.add_shot_to_scene(scene);
    doc.set(one, &field, Value::text("low mode"));

    doc.delete_column(&field);
    doc.undo();

    assert_eq!(doc.custom_columns().len(), 1, "the column is back");
    assert_eq!(
        doc.get(one).and_then(|r| r.text(&field)),
        Some("low mode"),
        "and what was written in it"
    );
}

// ---- the two gear columns, put back --------------------------------------

/// Ref 326, undone. Camera is a column again — an optional one — and a camera
/// name the merge wrote into an Equipment cell comes back out of it.
#[test]
fn a_camera_is_taken_back_out_of_equipment() {
    let (mut d, shot) = project();
    let project = d.project_id().unwrap();
    let unit = d.create_unit("A-Cam", "Alexa35");
    d.set(shot, f::UNIT, unit);

    // A film the merge reached: the cell says both, and the list learned the
    // camera's name.
    d.set(shot, "support", Value::text("Handheld, A-Cam"));
    d.set_vocabulary("support", &["Handheld", "Sticks", "A-Cam"]);
    d.set(project, "gear_columns_merged", Value::Bool(true));

    assert!(d.unmerge_gear_columns(), "the first time puts it back");
    assert_eq!(d.get(shot).unwrap().text("support"), Some("Handheld"),
        "the camera is out of the cell and what he had is still there");
    assert!(!d.vocabulary("support").iter().any(|t| t == "A-Cam"),
        "and the Equipment list stops offering a camera body");
    assert_eq!(d.get(shot).unwrap().ref_id(f::UNIT), Some(unit),
        "the camera itself was never gone");
    assert!(!d.unmerge_gear_columns(), "the second time does nothing");
}

/// Camera is present, and off unless he asks for it — his word: optional, for
/// a multicam day or a second body on set.
#[test]
fn camera_is_a_column_again_and_starts_hidden() {
    let (d, _) = project();
    assert!(d.column_order().iter().any(|c| c == "camera"), "it is a column");
    assert!(!d.is_column_visible("camera"), "and it is not on until asked for");
    assert!(d.is_column_visible("support"), "Equipment is a different column, and is on");
    assert_eq!(columns::label_for("camera"), "Camera");
    assert_eq!(columns::label_for("support"), "Equipment");
}

/// **Only the exact shape the merge wrote is taken out.** Anything else in
/// that cell is somebody's typing.
#[test]
fn typing_that_merely_mentions_a_camera_is_left_alone() {
    let (mut d, shot) = project();
    let project = d.project_id().unwrap();
    let unit = d.create_unit("A-Cam", "");
    d.set(shot, f::UNIT, unit);
    d.set(shot, "support", Value::text("A-Cam mount on the hood"));
    d.set(project, "gear_columns_merged", Value::Bool(true));

    d.unmerge_gear_columns();
    assert_eq!(d.get(shot).unwrap().text("support"), Some("A-Cam mount on the hood"));
}

/// A camera on its own in the cell leaves it empty, not with a stray comma.
#[test]
fn a_camera_alone_leaves_an_empty_cell() {
    let (mut d, shot) = project();
    let project = d.project_id().unwrap();
    let unit = d.create_unit("B-Cam", "");
    d.set(shot, f::UNIT, unit);
    d.set(shot, "support", Value::text("B-Cam"));
    d.set(project, "gear_columns_merged", Value::Bool(true));

    d.unmerge_gear_columns();
    assert_eq!(d.get(shot).unwrap().text("support"), None);
}


/// **A commercial shows the Script column once it has a script**, and a
/// film never does. His ask, 2026-09-19: no empty column.
#[test]
fn the_script_column_appears_with_the_script() {
    let (mut d, _) = project();
    d.set_kind(shotlister_engine::FilmKind::Commercial);
    assert!(!d.visible_columns().iter().any(|c| c == "script"), "no script: no column");
    d.set_av_script(None, "Thank you Denis.");
    assert!(d.visible_columns().iter().any(|c| c == "script"));
    d.set_kind(shotlister_engine::FilmKind::Film);
    assert!(!d.visible_columns().iter().any(|c| c == "script"));
}

// ---- lens stack --------------------------------------------------------

#[test]
fn the_lens_stack_is_always_on_and_writes_nothing() {
    let (mut d, shot) = project();
    d.set_vocab_list(shot, "lens_filters", &["1/8 Pro-Mist", "ND 0.6"]);
    d.set_vocab_list(shot, "modifiers", &["Diopter +1/2"]);

    // Filters and modifiers never get columns of their own; the lens carries
    // them. Nothing is written to the hidden list or to any shot.
    assert!(d.lens_stacked());
    let hidden = d.hidden_columns();
    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    assert!(!sheet.columns.contains(&"modifiers".to_string()));
    assert!(!sheet.columns.contains(&"lens_filters".to_string()));
    assert!(!d.is_column_visible("modifiers"));
    assert!(!hidden.iter().any(|h| h == "modifiers" || h == "lens_filters"));
    let row = sheet.rows().next().unwrap();
    assert_eq!(row.lens_cell(), "37mm · 1/8 Pro-Mist · ND 0.6 · Diopter +1/2");
    assert!(row.technical_line_for(&sheet.columns).contains("37mm · 1/8 Pro-Mist"));
    let page = html::table(&sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    // The lens is a pill in the lens colour; its filters (rings) and
    // modifiers (diamond) sit on a quiet line under it.
    assert!(page.contains(">37mm</span>"));
    assert!(page.contains("color:rgb(44,122,123)"), "lens teal");
    assert!(page.contains("<i class=\"ring\"></i>1/8 Pro-Mist"));
    assert!(page.contains("<i class=\"ring\"></i>ND 0.6"));
    assert!(page.contains("<i class=\"dia\"></i>Diopter +1/2"));

    // The picks are still on the shot, exactly as stored.
    assert_eq!(row.modifiers, vec!["Diopter +1/2"]);
    assert_eq!(row.lens_filters, vec!["1/8 Pro-Mist", "ND 0.6"]);
}

// ---- pills on the exported table ----------------------------------------

#[test]
fn the_exported_table_draws_tags_as_coloured_pills() {
    let (mut d, shot) = project();
    d.set_vocab_list(shot, "tags", &["Hero", "Pickup"]);
    d.set_term_colour("tags", "Hero", "E5484D");
    let mut sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    if !sheet.columns.iter().any(|c| c == "tags") {
        sheet.columns.push("tags".to_string());
    }
    let page = html::table(&sheet, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default());
    // A term he coloured by hand keeps its colour; the rest wear the column's.
    assert!(page.contains("class=\"pill\" style=\"color:rgb(229,72,77);background:rgba(229,72,77,.13);border-color:rgba(229,72,77,.45)\">Hero</span>"));
    assert!(page.contains("color:rgb(163,53,116);background:rgba(163,53,116,.13);border-color:rgba(163,53,116,.45)\">Pickup</span>"));
    // Paper: the tint is kept where the printer would drop it.
    assert!(page.contains("print-color-adjust: exact"));
    // Sizes, angles and movement are pills too.
    assert!(page.contains("class=\"pill\""));
}

#[test]
fn filters_and_modifiers_are_not_columns_and_an_old_order_naming_them_still_opens() {
    let (mut d, shot) = project();
    d.set_vocab_list(shot, "lens_filters", &["ND 0.6"]);
    d.set_vocab_list(shot, "modifiers", &["Diopter +1/2"]);
    // An older file's saved order names both.
    let project_id = d.project_id().unwrap();
    d.set(project_id, "column_order", shotlister_engine::Value::List(
        ["image", "title", "lens", "modifiers", "lens_filters", "support"]
            .iter().map(|n| shotlister_engine::Value::text(*n)).collect()));
    let order = d.column_order();
    assert!(!order.iter().any(|c| c == "modifiers" || c == "lens_filters"), "{order:?}");
    assert!(order.iter().any(|c| c == "lens"));
    let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
    let row = sheet.rows().next().unwrap();
    // The data is kept, and the Lens cell carries it: lens · filters · modifiers.
    assert_eq!(row.lens_filters, vec!["ND 0.6"]);
    assert_eq!(row.lens_cell(), "37mm · ND 0.6 · Diopter +1/2");
    assert_eq!(row.technical_line_for(&["lens".to_string()]), "37mm · ND 0.6 · Diopter +1/2");
}
