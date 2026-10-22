//! The kit, from a chat (Ref 1627): the spec sheets' lenses and cameras into
//! the film, and the shots that use something the sheets lack.

mod common;
use common::*;
use shotlister_mcp::json::{self, Json};

const KIT: &str = r#"[{"name":"Shoot 1","start":"2026-07-09","end":"","sheet":"aaaa","lead":true,
  "cameras":[{"label":"A Cam","body":"Alexa 35"}],"lenses":["18mm","25mm","Angenieux 45-165mm"]}]"#;

fn take(s: &mut Open) -> String {
    let given = json::parse(KIT).unwrap();
    s.call("take_kit", &Json::Object(vec![("kit".into(), given)])).unwrap_or_else(|e| panic!("take_kit refused: {e}"))
}

#[test]
fn the_kit_fills_the_lens_list_and_the_cameras() {
    let (_x, mut s) = opened("kit-take");
    assert!(ok(&mut s, "kit", &[]).contains("no spec sheet yet"));
    let said = take(&mut s);
    assert!(said.contains("Lens list: 18mm, 25mm, Angenieux 45-165mm added"), "{said}");
    assert!(said.contains("Cameras made: A Cam Alexa 35"), "{said}");
    assert!(ok(&mut s, "cameras", &[]).contains("Alexa 35"));
    assert_eq!(take(&mut s), "The film already has this kit.");
    assert!(no(&mut s, "take_kit", &[]).contains("Say the kit"));
}

#[test]
fn a_shot_off_the_kit_is_named_with_the_sheet_it_would_go_on() {
    let (_x, mut s) = opened("kit-off");
    take(&mut s);
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_shot", &[("scene", "1"), ("lens", "25mm")]);
    ok(&mut s, "add_shot", &[("scene", "1"), ("lens", "85mm")]);
    let said = ok(&mut s, "kit", &[]);
    assert!(said.contains(r#""shot":"1B","sheet":"Shoot 1","lens":"85mm""#), "{said}");
    assert!(!said.contains(r#""shot":"1A""#), "25mm is on the sheet: {said}");
}

const CARRIED: &str = r#"[{"name":"Shoot 1","start":"2026-07-09","end":"","sheet":"aaaa","lead":true,
  "cameras":[],"lenses":["45-165mm"],"modifiers":["Atlas LF Extender 1.6x"],
  "filters":["Tiffen ND .6","Polarizer 138mm"]}]"#;

#[test]
fn modifiers_and_filters_come_off_the_sheet_and_a_shot_picks_them() {
    let (_x, mut s) = opened("kit-modifiers");
    let given = json::parse(CARRIED).unwrap();
    let said = s.call("take_kit", &Json::Object(vec![("kit".into(), given)])).unwrap();
    assert!(said.contains("Modifiers list: Atlas LF Extender 1.6x added"), "{said}");
    assert!(said.contains("Filters list: Tiffen ND .6, Polarizer 138mm added"), "{said}");
    assert!(ok(&mut s, "lists", &[("list", "extender")]).contains("Atlas LF Extender 1.6x"));
    assert!(ok(&mut s, "lists", &[("list", "filters")]).contains("Polarizer 138mm"));

    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_shot", &[("scene", "1"), ("lens", "45-165mm")]);
    ok(&mut s, "update_shot", &[
        ("shot", "1A"),
        ("modifiers", "Atlas LF Extender 1.6x"),
        ("lens_filters", "Tiffen ND .6, Black Pro-Mist 1/8"),
    ]);
    let shots = ok(&mut s, "shots", &[("scene", "1")]);
    assert!(shots.contains(r#""modifiers":"Atlas LF Extender 1.6x""#), "{shots}");
    assert!(shots.contains(r#""lens_filters":"Tiffen ND .6, Black Pro-Mist 1/8""#), "{shots}");
    let kit = ok(&mut s, "kit", &[]);
    assert!(kit.contains(r#""shot":"1A","sheet":"Shoot 1","filters":["Black Pro-Mist 1/8"]"#), "{kit}");
    assert!(kit.contains(r#""modifiers":["Atlas LF Extender 1.6x"]"#), "the shoot carries it: {kit}");
}
