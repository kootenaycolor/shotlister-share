//! A scene that happens **inside and outside** — `INT./EXT.`, `INT/EXT`, `I/E`,
//! `EXT./INT.` — is a real scene heading and has to be counted as both. His
//! ruling, 2026-10-09.

use shotlister_engine::doc::f;
use shotlister_engine::{DeviceId, Doc, GroupBy, Query};
use shotlister_engine::script::{parse, read_heading};

#[test]
fn a_draft_with_every_spelling_of_both_reads_each_as_both() {
    let draft = "\
1 INT./EXT. CAR - DAY\n\nHe drives out.\n\n\
2 I/E GARAGE - DAY\n\nThe door lifts.\n\n\
3 EXT./INT. PORCH - NIGHT\n\nShe leans in.\n\n\
4 INT. / EXT. DOORWAY - NIGHT\n\nHe stops.\n\n\
5 INT. KITCHEN - DAY\n\nTea.\n\n\
6 EXT. YARD - DAY\n\nRain.\n";
    let scenes = parse(draft);
    let held: Vec<(&str, &str)> = scenes
        .iter()
        .map(|s| (s.int_ext.as_str(), s.location.as_str()))
        .collect();
    assert_eq!(
        held,
        vec![
            ("INT/EXT", "CAR"),
            ("INT/EXT", "GARAGE"),
            ("INT/EXT", "PORCH"),
            ("INT/EXT", "DOORWAY"),
            ("INT", "KITCHEN"),
            ("EXT", "YARD"),
        ]
    );
    // The heading stays exactly as the script wrote it.
    assert_eq!(scenes[2].heading, "EXT./INT. PORCH - NIGHT");
}

#[test]
fn a_typed_heading_reads_it_too() {
    let scene = read_heading("12 I/E. LOBBY - DAY");
    assert_eq!(scene.number.as_deref(), Some("12"));
    assert_eq!(scene.int_ext, "INT/EXT");
    assert_eq!(scene.location, "LOBBY");
}

fn film() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Both");
    for (number, int_ext) in [("1", "INT"), ("2", "EXT"), ("3", "INT/EXT"), ("4", "INT./EXT.")] {
        let scene = d.create_scene(number);
        d.set(scene, f::INT_EXT, int_ext);
        d.add_shot_to_scene(scene);
    }
    d
}

fn numbers(d: &Doc, ask: &str) -> Vec<String> {
    let q = Query::grouped_by(GroupBy::Scene).scene_is(f::INT_EXT, ask);
    let mut out = Vec::new();
    for scene in d.visible_scenes(&q) {
        out.push(d.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or_default().to_string());
    }
    out
}

#[test]
fn filtering_to_inside_or_outside_includes_the_scenes_that_are_both() {
    let d = film();
    assert_eq!(numbers(&d, "INT"), ["1", "3", "4"]);
    assert_eq!(numbers(&d, "EXT"), ["2", "3", "4"]);
    assert_eq!(numbers(&d, "INT/EXT"), ["3", "4"]);
    assert_eq!(numbers(&d, "I/E"), ["3", "4"]);
}

#[test]
fn picking_it_in_the_settings_stores_one_spelling_and_prints_the_slug_whole() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Both");
    let scene = d.create_scene("7");
    d.set(scene, f::HEADING, "INT. GARAGE - DAY");
    d.set(scene, f::LOCATION, "GARAGE");
    d.set(scene, f::TIME_OF_DAY, "DAY");

    d.set_scene_field(scene, f::INT_EXT, "INT./EXT.");
    assert_eq!(d.get(scene).unwrap().text(f::INT_EXT), Some("INT/EXT"));
    assert_eq!(d.scene_heading(scene).as_deref(), Some("INT./EXT. GARAGE - DAY"));

    d.set_scene_field(scene, f::INT_EXT, "e");
    assert_eq!(d.get(scene).unwrap().text(f::INT_EXT), Some("EXT"));
    assert_eq!(d.scene_heading(scene).as_deref(), Some("EXT. GARAGE - DAY"));
}

#[test]
fn a_rule_that_asks_for_int_or_ext_lets_i_slash_e_through() {
    use shotlister_engine::screenplay::{read_with, Detection};
    let draft = "1 I/E. CAR - DAY\n\nHe drives.\n\n2 INT. KITCHEN - DAY\n\nTea.\n";
    let rule = Detection {
        must_contain: vec!["INT".into(), "EXT".into()],
        ..Detection::default()
    };
    let read = read_with(draft, &rule);
    let found: Vec<&str> = read.scenes.iter().map(|s| s.script.int_ext.as_str()).collect();
    assert_eq!(found, ["INT/EXT", "INT"]);
}

#[test]
fn every_shot_row_says_what_its_scene_answers_to() {
    use shotlister_engine::view::{self, Asked, Standing};
    let d = film();
    let drawn = view::describe(
        &d,
        &Asked::default().looking(),
        &Standing { read_only: true, unsaved: 0, device_clash: None },
    );
    // Scene 3 is INT/EXT: its shot is under INT, EXT and INT/EXT. Scene 1 (INT)
    // is under INT alone.
    assert!(drawn.contains(r#""int_ext":["INT","EXT","INT/EXT"]"#), "{drawn}");
    assert!(drawn.contains(r#""int_ext":["INT"]"#));
    assert!(drawn.contains(r#""int_ext":["EXT"]"#));
}

#[test]
fn a_scene_that_is_both_is_drawn_as_i_slash_e_and_stored_as_it_was_written() {
    use shotlister_engine::insideout::{shown_heading, short};
    assert_eq!(shown_heading("INT./EXT. CAR - DAY"), "I/E. CAR - DAY");
    assert_eq!(shown_heading("EXT./INT. PORCH - NIGHT"), "I/E. PORCH - NIGHT");
    assert_eq!(shown_heading("I/E GARAGE - DAY"), "I/E. GARAGE - DAY");
    assert_eq!(shown_heading("INT. KITCHEN - DAY"), "INT. KITCHEN - DAY");
    assert_eq!(shown_heading("EXT. YARD - DAY"), "EXT. YARD - DAY");
    assert_eq!(shown_heading("Hero Unboxes the Camera"), "Hero Unboxes the Camera");
    assert_eq!(short("INT/EXT"), "I/E");
    assert_eq!(short("INT"), "INT");

    let mut d = Doc::new(DeviceId(1));
    d.create_project("Both");
    let scene = d.create_scene("7");
    d.set(scene, f::HEADING, "INT./EXT. CAR - DAY");
    assert_eq!(d.scene_heading(scene).as_deref(), Some("INT./EXT. CAR - DAY"));
    assert_eq!(d.scene_heading_shown(scene).as_deref(), Some("I/E. CAR - DAY"));
}
