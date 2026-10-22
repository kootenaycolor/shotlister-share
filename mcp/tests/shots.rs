//! Every cell a shot has, and the things around a shot: where it sits,
//! copies, cameras, columns.

mod common;
use common::*;

fn shot_json(s: &mut Open, scene: &str, number: &str) -> Json {
    let all = ok(s, "shots", &[("scene", scene)]);
    let parsed = json::parse(&all).unwrap();
    parsed
        .as_array()
        .unwrap()
        .iter()
        .find(|shot| shot.get("number").and_then(|n| n.as_str()) == Some(number))
        .cloned()
        .unwrap_or_else(|| panic!("no {number} in {all}"))
}

fn field(shot: &Json, key: &str) -> String {
    shot.get(key).map(|v| v.as_str().map(str::to_string).unwrap_or_else(|| v.encode())).unwrap_or_default()
}

#[test]
fn every_cell_the_table_has() {
    let (_x, mut s) = opened("cells");
    ok(&mut s, "add_scene", &[("number", "5")]);
    ok(&mut s, "add_shot", &[("scene", "5")]);
    ok(&mut s, "add_column", &[("name", "Filter"), ("kind", "single")]);
    ok(&mut s, "add_column", &[("name", "VFX"), ("kind", "check")]);
    let said = ok(&mut s, "update_shot", &[
        ("shot", "5A"),
        ("title", "Hero wide"),
        ("camera", "A-Cam"),
        ("tags", "night, rain"),
        ("pov", "Anna"),
        ("priority", "Must Have"),
        ("colour", "blue"),
        ("fields", r#"{"Filter": "ND .6", "vfx": true}"#),
    ]);
    assert!(said.contains("A-Cam is a new camera"), "{said}");
    let shot = shot_json(&mut s, "5", "5A");
    assert_eq!(field(&shot, "title"), "Hero wide");
    assert_eq!(field(&shot, "camera"), "A-Cam");
    assert_eq!(field(&shot, "tags"), "night, rain");
    assert_eq!(field(&shot, "pov"), "Anna");
    assert_eq!(field(&shot, "priority"), "Must Have");
    assert_eq!(field(&shot, "colour"), "0A6CE8");
    assert_eq!(field(&shot, "fields"), r#"{"Filter":"ND .6","VFX":"✓"}"#);

    // A pick-list column's choices are a list like any other.
    assert!(ok(&mut s, "lists", &[("list", "Filter")]).contains(r#""term":"ND .6""#));
    ok(&mut s, "lock_list", &[("list", "filter")]);
    let said = ok(&mut s, "update_shot", &[("shot", "5A"), ("fields", r#"{"Filter": "Pola"}"#)]);
    assert!(said.contains("Filter Pola was not set"), "{said}");

    assert!(no(&mut s, "update_shot", &[("shot", "5A"), ("fields", r#"{"Diffusion": "1/8"}"#)]).contains("Its own columns are Filter, VFX"));
    assert!(no(&mut s, "update_shot", &[("shot", "5A"), ("colour", "mauve")]).contains("red, orange"));
    ok(&mut s, "update_shot", &[("shot", "5A"), ("camera", ""), ("colour", "")]);
    assert_eq!(field(&shot_json(&mut s, "5", "5A"), "camera"), "");
}

#[test]
fn masters_followers_and_two_cameras_at_once() {
    let (_x, mut s) = opened("links");
    ok(&mut s, "add_scene", &[("number", "8")]);
    ok(&mut s, "add_shot", &[("scene", "8"), ("description", "The master wide")]);
    ok(&mut s, "add_shot", &[("scene", "8")]);
    ok(&mut s, "add_shot", &[("scene", "8")]);
    ok(&mut s, "update_shot", &[("shot", "8B"), ("follows", "8A")]);
    assert_eq!(field(&shot_json(&mut s, "8", "8A"), "master"), "true");
    let b = shot_json(&mut s, "8", "8B");
    assert_eq!(field(&b, "follows"), "8A");
    assert_eq!(field(&b, "description"), "The master wide", "a follower shows its master's words");
    ok(&mut s, "update_shot", &[("shot", "8B"), ("follows", "")]);
    assert_eq!(field(&shot_json(&mut s, "8", "8B"), "description"), "The master wide", "cut loose, it keeps them");

    ok(&mut s, "update_shot", &[("shot", "8C"), ("rolls_with", "8A")]);
    assert_eq!(field(&shot_json(&mut s, "8", "8A"), "rolls_with"), r#"["8C"]"#);
    ok(&mut s, "update_shot", &[("shot", "8C"), ("rolls_with", "")]);
    assert_eq!(field(&shot_json(&mut s, "8", "8A"), "rolls_with"), "[]");
    assert!(no(&mut s, "update_shot", &[("shot", "8A"), ("follows", "8A")]).contains("cannot follow itself"));
}

#[test]
fn shots_go_where_they_are_put_and_copy() {
    let (_x, mut s) = opened("order");
    ok(&mut s, "add_scene", &[("number", "2")]);
    ok(&mut s, "add_scene", &[("number", "3")]);
    for d in ["one", "two", "three"] {
        ok(&mut s, "add_shot", &[("scene", "2"), ("description", d)]);
    }
    assert_eq!(ok(&mut s, "add_shot", &[("scene", "2"), ("after", "2A"), ("description", "between")]), "Added 2B.");
    assert_eq!(field(&shot_json(&mut s, "2", "2B"), "description"), "between");

    let said = ok(&mut s, "order_shot", &[("shot", "2D"), ("position", "1")]);
    assert!(said.ends_with("Scene runs: 2A, 2B, 2C, 2D."), "{said}");
    assert_eq!(field(&shot_json(&mut s, "2", "2A"), "description"), "three", "in prep, letters follow position");
    assert!(no(&mut s, "order_shot", &[("shot", "2A"), ("after", "2A")]).contains("not beside"));

    let said = ok(&mut s, "duplicate_shot", &[("shots", "2A"), ("count", "2")]);
    assert_eq!(said, "Made 2B, 2C.");
    let said = ok(&mut s, "duplicate_shot", &[("shots", "2A, 2F"), ("into", "3")]);
    assert_eq!(said, "Made 3A, 3B.");
    assert_eq!(field(&shot_json(&mut s, "3", "3B"), "description"), "two");
    assert!(ok(&mut s, "undo", &[]).contains("Copy shots"));
}

#[test]
fn cameras_and_columns() {
    let (_x, mut s) = opened("cameras");
    assert_eq!(ok(&mut s, "add_camera", &[("name", "A-Cam"), ("body", "Alexa 35")]), "Added A-Cam Alexa 35.");
    assert!(no(&mut s, "add_camera", &[("name", "a-cam")]).contains("already"));
    ok(&mut s, "add_camera", &[("name", "B-Cam"), ("colour", "green")]);
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_shot", &[("scene", "1"), ("camera", "a-cam alexa 35")]);
    let cams = ok(&mut s, "cameras", &[]);
    assert!(cams.contains(r#"{"name":"A-Cam","body":"Alexa 35","colour":"E5484D","sensor":null,"shots":1}"#), "{cams}");
    assert!(cams.contains(r#""colour":"16A34A""#), "{cams}");
    assert_eq!(ok(&mut s, "update_camera", &[("camera", "A-Cam"), ("name", "Main"), ("body", "Venice 2")]), "It is Main Venice 2 now.");
    assert_eq!(field(&shot_json(&mut s, "1", "1A"), "camera"), "Main Venice 2", "shots follow a rename");
    assert!(no(&mut s, "delete_camera", &[("camera", "Main")]).contains("1 shot name Main"));
    ok(&mut s, "delete_camera", &[("camera", "Main"), ("even_if_used", "true")]);
    assert!(no(&mut s, "update_camera", &[("camera", "Main"), ("name", "x")]).contains("The cameras are B-Cam"));

    ok(&mut s, "add_column", &[("name", "Stunt"), ("kind", "check")]);
    ok(&mut s, "update_shot", &[("shot", "1A"), ("fields", r#"{"Stunt": "yes"}"#)]);
    let cols = ok(&mut s, "columns", &[]);
    assert!(cols.contains(r#"{"name":"Stunt","field":"#) && cols.contains(r#""kind":"check","shots_with_values":1"#), "{cols}");
    assert!(cols.contains(r#"{"name":"Camera","field":"camera","visible":false}"#), "{cols}");
    let said = ok(&mut s, "update_column", &[("column", "Camera"), ("visible", "true"), ("position", "1")]);
    assert!(said.starts_with("The table shows: Camera, "), "{said}");
    assert!(no(&mut s, "update_column", &[("column", "Lens"), ("name", "Glass")]).contains("built-in"));
    ok(&mut s, "update_column", &[("column", "Stunt"), ("name", "Stunts")]);
    assert!(no(&mut s, "delete_column", &[("column", "Stunts")]).contains("1 shot have something in Stunts"));
    assert!(no(&mut s, "delete_column", &[("column", "Shot Size")]).contains("cannot be deleted"));
    ok(&mut s, "delete_column", &[("column", "Stunts"), ("even_with_values", "true")]);
    assert!(!ok(&mut s, "columns", &[]).contains("Stunt"));
}
