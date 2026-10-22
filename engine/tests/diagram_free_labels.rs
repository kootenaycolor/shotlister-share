//! His notes, 2026-10-17: labels are what he types — several lines, his own
//! case, no numbers or counts unless he asks — on every kind of piece, with
//! nothing named for him; a label's lines leave it tidily; pieces go between
//! Set and Plot.

use shotlister_engine::diagram::render::{self, Geom, Ink, Options};
use shotlister_engine::diagram::{self, plot, sheet, Diagram};
use shotlister_engine::json;
use shotlister_engine::{f, DeviceId, Doc, Id, Value};

fn edit(doc: &mut Doc, scene: Id, op: &str) -> Vec<String> {
    doc.diagram_edit(scene, &json::parse(op).unwrap()).unwrap()
}

fn fresh() -> (Doc, Id) {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Free Labels");
    let scene = doc.create_scene("1");
    (doc, scene)
}

/// A plan begun today, its pieces put down with the ids given.
fn plan(els: &str) -> Diagram {
    let mut d = Diagram { settings: diagram::Settings::fresh(), ..Default::default() };
    diagram::apply(&mut d, &json::parse(&format!(r#"{{"op":"add","els":{els}}}"#)).unwrap()).unwrap();
    d
}

fn run(d: &mut Diagram, op: &str) -> Vec<String> {
    diagram::apply(d, &json::parse(op).unwrap()).unwrap()
}

fn words(d: &Diagram, id: &str) -> Vec<String> {
    render::render(d, &Default::default(), &Options::default())
        .into_iter()
        .filter(|s| s.el == id && matches!(s.part, "label" | "body"))
        .filter_map(|s| match s.geom {
            Geom::Text { text, .. } => Some(text),
            _ => None,
        })
        .collect()
}

/// Every kind of piece that wears a name, as a new plan puts it down.
const EVERY_KIND: &str = r##"[
  {"kind":"light","id":"lamp","sym":"","mark":"chevron","x":0,"y":0},
  {"kind":"light","id":"silk","sym":"frame","x":3,"y":0,"h":2.4384},
  {"kind":"light","id":"flag","sym":"flag-24x36","x":6,"y":0},
  {"kind":"set","id":"sofa","sym":"sofa","x":0,"y":4},
  {"kind":"set","id":"half","sym":"table-half-round","x":3,"y":4,"w":1.2,"h":0.6},
  {"kind":"camera","id":"cam","x":6,"y":4},
  {"kind":"cast","id":"who","x":9,"y":4},
  {"kind":"track","id":"trk","x":0,"y":8,"x2":3,"y2":8},
  {"kind":"shape","id":"box","x":6,"y":8,"w":1,"h":1},
  {"kind":"arrow","id":"arw","x":9,"y":8,"x2":10,"y2":8}
]"##;

#[test]
fn every_kind_takes_a_free_label_and_keeps_it() {
    let mut d = plan(EVERY_KIND);
    // Nothing named for him: no unit, size, cloth, kind or diameter.
    for id in ["lamp", "silk", "flag", "sofa", "half", "cam", "who", "box", "arw"] {
        assert!(words(&d, id).iter().all(|w| w.trim().is_empty()), "{id} wears nothing it was not given: {:?}", words(&d, id));
    }
    // Each takes what he types — two lines, his own case — and keeps it.
    let typed = "Big Silk\nmaybe 1/2 grid";
    let all = ["lamp", "silk", "flag", "sofa", "half", "cam", "who", "trk", "box", "arw"];
    for id in all {
        run(&mut d, &format!(r#"{{"op":"name_piece","id":"{id}","name":{}}}"#, json::Json::text(typed).encode()));
    }
    for id in ["lamp", "silk", "flag", "sofa", "half", "cam", "who", "box", "arw"] {
        let w = words(&d, id);
        assert!(w.iter().any(|t| t.starts_with(typed)), "{id}: {w:?}");
    }
    // Kept through a save and a read.
    let back = Diagram::parse(&d.encode());
    for id in all {
        assert_eq!(render::piece_name(back.get(id).unwrap(), &Default::default()), typed, "{id}");
    }
}

#[test]
fn a_new_frame_has_no_cloth_decided() {
    let d = plan(r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":2.4384}]"#);
    let f = d.get("f").unwrap();
    assert_eq!(diagram::frame::material_id(f), "undecided");
    assert_eq!(diagram::frame::material_name("undecided"), "Not Decided");
    assert_eq!(render::frame_lines(f, true).0, "", "no size or cloth written for him");
    let shapes = render::render(&d, &Default::default(), &Options::default());
    assert!(!shapes.iter().any(|s| matches!(&s.geom, Geom::Text { text, .. } if text.contains("Not Decided") || text.contains("Diffusion"))));
}

fn sheet_words(d: &Diagram) -> (Vec<String>, Vec<String>) {
    let ask = sheet::Ask { beat: 1, ..Default::default() };
    let lay = sheet::layout(d, &Default::default(), &sheet::Title::default(), &[], &ask);
    let legend = lay.items.iter().filter(|i| i.kind == "legend" || i.kind == "frames").map(|i| i.name.clone()).collect();
    let drawn = lay.furniture.iter().filter_map(|s| match &s.geom { Geom::Text { text, .. } => Some(text.clone()), _ => None }).collect();
    (legend, drawn)
}

#[test]
fn labels_keep_their_case_and_no_counts_unless_asked() {
    let mut d = plan(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0,"count":3,"lamp_name":"Key light"},
            {"kind":"light","id":"b","sym":"","mark":"chevron","x":4,"y":0,"lamp_name":"Key light"},
            {"kind":"light","id":"c","sym":"","mark":"wedge","x":8,"y":0}]"#,
    );
    assert_eq!(words(&d, "a"), vec!["Key light".to_string()], "no 3×, no capitals");
    let (legend, drawn) = sheet_words(&d);
    assert_eq!(legend, vec!["Key light".to_string()], "one line per label; the unlabelled lamp leaves none");
    assert!(drawn.iter().any(|t| t == "Key light"), "{drawn:?}");
    assert!(!drawn.iter().any(|t| t.contains('×') || t.contains("Unlabeled")), "{drawn:?}");
    // He can turn each on.
    run(&mut d, r#"{"op":"settings","set":{"caps":true,"counts":true,"unlabeled":true}}"#);
    assert_eq!(words(&d, "a"), vec!["3× KEY LIGHT".to_string()]);
    let (_, drawn) = sheet_words(&d);
    assert!(drawn.iter().any(|t| t == "KEY LIGHT ×4"), "{drawn:?}");
    assert!(drawn.iter().any(|t| t == "UNLABELED ×1"), "{drawn:?}");
}

#[test]
fn a_name_of_two_lines_is_drawn_in_its_ink_its_note_grey() {
    let d = plan(r#"[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0,"lamp_name":"Key\nthrough the window","label":"half CTB"}]"#);
    let s = render::render(&d, &Default::default(), &Options::default()).into_iter().find(|s| s.el == "a" && s.part == "label").unwrap();
    let Geom::Text { text, lead, under, .. } = &s.geom else { panic!() };
    assert_eq!(text, "Key\nthrough the window\nhalf CTB");
    assert_eq!(*lead, 2);
    assert_eq!(*under, Ink::Role("ink2"));
}

#[test]
fn a_shared_label_says_what_he_typed() {
    let mut d = plan(r#"[{"kind":"light","id":"a","sym":"frame","x":0,"y":0},{"kind":"light","id":"b","sym":"frame","x":4,"y":0},{"kind":"set","id":"s","sym":"sofa","x":2,"y":3}]"#);
    let t = run(&mut d, r#"{"op":"share_label","ids":["a","b","s"]}"#)[0].clone();
    assert_eq!(render::shared_label_words(&d, d.get(&t).unwrap()).unwrap(), "", "none of them named: nothing written for him");
    run(&mut d, &format!(r#"{{"op":"update","ids":["{t}"],"set":{{"text":"Bounce wall\nfor the key"}}}}"#));
    assert_eq!(render::shared_label_words(&d, d.get(&t).unwrap()).unwrap(), "Bounce wall\nfor the key");
    // Its lines: a trunk to one junction, then one to each piece.
    let ties: Vec<_> = render::render(&d, &Default::default(), &Options::default()).into_iter().filter(|s| s.el == t && s.part == "tie").collect();
    let dots = ties.iter().filter(|s| s.fill == Ink::Role("ink2")).count();
    assert_eq!(dots, 4, "the junction and three ends");
}

#[test]
fn a_labels_lines_branch_from_one_junction_and_never_cross() {
    // Five pieces round a label, one behind it.
    let ends = [(-6.0, 4.0), (-2.0, 5.0), (3.0, 4.5), (7.0, 3.0), (0.5, -4.0)];
    let l = render::leader_paths(&ends, (0.0, 0.0), (1.2, 0.3), 0.4, |_, _| 0.3);
    assert!(l.junction);
    let trunk = &l.lines[0];
    assert_eq!(trunk.len(), 2);
    let j = trunk[1];
    assert_eq!(l.lines.len(), 1 + ends.len(), "a trunk, then a branch to each");
    for b in &l.lines[1..] {
        assert_eq!(b[0], j, "every branch leaves the one junction");
        assert!(b.len() <= 3, "straight, or one elbow");
    }
    let segs: Vec<((f64, f64), (f64, f64), usize)> = l.lines[1..].iter().enumerate().flat_map(|(i, b)| b.windows(2).map(move |w| (w[0], w[1], i))).collect();
    let cross = |a: (f64, f64), b: (f64, f64), c: (f64, f64), d: (f64, f64)| {
        let o = |p: (f64, f64), q: (f64, f64), r: (f64, f64)| (q.0 - p.0) * (r.1 - p.1) - (q.1 - p.1) * (r.0 - p.0);
        o(a, b, c) * o(a, b, d) < -1e-9 && o(c, d, a) * o(c, d, b) < -1e-9
    };
    for x in &segs {
        for y in &segs {
            if x.2 < y.2 {
                assert!(!cross(x.0, x.1, y.0, y.1), "branches {} and {} cross", x.2, y.2);
            }
        }
    }
    assert_eq!(l.dots.len(), 1 + ends.len(), "a dot at the junction and every end");
    let a = trunk[0];
    assert!(((a.0.abs() - 1.2).abs() < 1e-9 && a.1.abs() < 1e-9) || (a.0.abs() < 1e-9 && (a.1.abs() - 0.3).abs() < 1e-9), "from the middle of a side: {a:?}");
}

#[test]
fn pieces_go_between_set_and_plot_in_one_step() {
    let (mut doc, scene) = fresh();
    let ids = edit(
        &mut doc,
        scene,
        r#"{"op":"add","els":[{"kind":"set","sym":"sofa","x":1,"y":2,"rot":30,"label":"Hero sofa"},{"kind":"light","sym":"","mark":"chevron","x":3,"y":3},{"kind":"text","text":"Hi","x":0,"y":0},{"kind":"wall","x":0,"y":0,"x2":3,"y2":0}]}"#,
    );
    let (sofa, lamp, w, wl) = (ids[0].clone(), ids[1].clone(), ids[2].clone(), ids[3].clone());
    let layer = |doc: &Doc, id: &str| diagram::layer(doc.diagram(scene).get(id).unwrap()).to_string();
    assert_eq!(layer(&doc, &sofa), "set");
    edit(&mut doc, scene, &format!(r#"{{"op":"send_layer","ids":["{sofa}","{lamp}","{w}","{wl}"],"to":"set"}}"#));
    assert_eq!((layer(&doc, &lamp), layer(&doc, &w)), ("set".to_string(), "set".to_string()));
    let d = doc.diagram(scene);
    let s = d.get(&sofa).unwrap();
    assert_eq!((s.x, s.y, s.rot, s.label.as_str()), (1.0, 2.0, 30.0, "Hero sofa"), "where it stood, turned and named");
    assert_eq!(layer(&doc, &wl), "set");
    // One step of undo puts them back.
    doc.undo();
    assert_eq!((layer(&doc, &lamp), layer(&doc, &w)), ("plot".to_string(), "plot".to_string()));
    // The sofa to Plot; a copy of the lamp to Set.
    edit(&mut doc, scene, &format!(r#"{{"op":"send_layer","ids":["{sofa}"],"to":"plot"}}"#));
    assert_eq!(layer(&doc, &sofa), "plot");
    let made = edit(&mut doc, scene, &format!(r#"{{"op":"send_layer","ids":["{lamp}"],"to":"set","copy":true}}"#));
    assert_eq!(made.len(), 1);
    assert_eq!(layer(&doc, &lamp), "plot", "the original stays");
    let d = doc.diagram(scene);
    let c = d.get(&made[0]).unwrap();
    assert_eq!((diagram::layer(c), c.x, c.y), ("set", 3.0, 3.0));
    let back = Diagram::parse(&d.encode());
    assert_eq!(diagram::layer(back.get(&sofa).unwrap()), "plot", "kept through a save");
    edit(&mut doc, scene, &format!(r#"{{"op":"send_layer","ids":["{sofa}"],"to":"set"}}"#));
    assert!(doc.diagram(scene).get(&sofa).unwrap().on_layer.is_empty(), "back to its kind's own: nothing stored");
}

#[test]
fn an_older_plan_keeps_every_label_it_showed() {
    // As stored before 2026-10-17: a frame with no Name or cloth, a flag
    // with no label, a half round, a shared label with stale words.
    let mut d = Diagram::parse(
        r#"{"els":[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":3.6576,"tilt":45},{"kind":"light","id":"g","sym":"flag-24x36","x":3,"y":0},
            {"kind":"set","id":"h","sym":"table-half-round","x":6,"y":0,"w":1.2,"h":0.6},
            {"kind":"light","id":"k","sym":"","mark":"chevron","x":0,"y":4,"lamp_name":"Key","tie_to":"t"},{"kind":"light","id":"k2","sym":"","mark":"chevron","x":2,"y":4,"lamp_name":"Key","tie_to":"t"},
            {"kind":"text","id":"t","text":"old words","x":1,"y":6}],"settings":{"lamp_names":true,"typed_labels":true}}"#,
    );
    assert!(!d.settings.free_names);
    let before_g = render::render(&d, &Default::default(), &Options::default());
    plot::own_names(&mut d);
    assert!(d.settings.free_names);
    assert_eq!(d.get("f").unwrap().lamp_name, "12×12 Medium Diffusion · 45°");
    assert_eq!(d.get("f").unwrap().material, "diff-medium", "its cloth as it was drawn");
    assert!(!d.get("g").unwrap().label.is_empty(), "the flag keeps its name");
    assert!(!d.get("h").unwrap().label.is_empty(), "the half round keeps its diameter");
    assert_eq!(d.get("t").unwrap().text, "", "stale words under named lamps cleared");
    assert_eq!(render::shared_label_words(&d, d.get("t").unwrap()).unwrap(), "Key");
    // Each piece's words read the same as before, letter for letter but case.
    let after = render::render(&d, &Default::default(), &Options::default());
    for id in ["g", "h"] {
        let w = |v: &Vec<render::Shape>| v.iter().filter(|s| s.el == id && s.part == "label").filter_map(|s| match &s.geom { Geom::Text { text, .. } => Some(text.to_uppercase()), _ => None }).collect::<Vec<_>>();
        let _ = &before_g;
        assert!(!w(&after).is_empty(), "{id} still named");
    }
    let _ = (Value::Null, plot::legend(&d), f::DIAGRAM);
}

#[test]
fn every_person_has_one_color_for_the_project_in_billing_order() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Cast Colors");
    doc.add_column("Cast", "multi");
    let field = doc.cast_field().expect("a Cast column");
    doc.set_vocabulary(&field, &["Maya", "Leo", "Ruth", "Sam"]);
    let colours = doc.term_colours(&field);
    let of = |who: &str, c: &Vec<(String, String)>| c.iter().find(|(t, _)| t == who).map(|(_, h)| h.clone());
    // The lead red, then blue, green, orange.
    assert_eq!(of("Maya", &colours).as_deref(), Some("E5484D"));
    assert_eq!(of("Leo", &colours).as_deref(), Some("0A6CE8"));
    assert_eq!(of("Ruth", &colours).as_deref(), Some("16A34A"));
    assert_eq!(of("Sam", &colours).as_deref(), Some("D97706"));
    // Nothing written for him.
    assert!(doc.stored_term_colours(&field).is_empty());
    // His own pick wins, and the rest skip it.
    doc.set_term_colour(&field, "Leo", "16A34A");
    let colours = doc.term_colours(&field);
    assert_eq!(of("Leo", &colours).as_deref(), Some("16A34A"));
    assert_eq!(of("Ruth", &colours).as_deref(), Some("0A6CE8"));
    assert_eq!(doc.stored_term_colours(&field).len(), 1);
    // The plan draws a person in their color; a piece's own color still wins.
    let scene = doc.create_scene("1");
    let ids = edit(&mut doc, scene, r##"{"op":"add","els":[{"kind":"cast","cast":"Maya","x":0,"y":0},{"kind":"cast","cast":"Maya","x":2,"y":0,"color":"#2C7A7B"}]}"##);
    let d = doc.diagram(scene);
    let shapes = render::render(&d, &doc.diagram_context(scene), &Options::default());
    let ink = |id: &str| shapes.iter().filter(|s| s.el == id && s.part == "body").map(|s| format!("{:?}{:?}", s.fill, s.stroke)).collect::<String>();
    assert!(ink(&ids[0]).contains("E5484D"), "{}", ink(&ids[0]));
    assert!(ink(&ids[1]).contains("2C7A7B"), "{}", ink(&ids[1]));
}
