use super::render::{self, Context, Geom, Ink, Options, Seg, Shape};
use super::*;

fn op(text: &str) -> Json {
    json::parse(text).expect("test op parses")
}

/// A plan drawn the old way, each unit's picture (a plot is the default).
fn pictures(mut d: Diagram) -> Diagram {
    d.settings.style = "picture".into();
    d
}

/// How many pieces a label's lines reach: the dots at their ends, the
/// junction's left out (2026-10-17, tidy lines).
fn tie_ends<'a>(shapes: impl Iterator<Item = &'a Shape>) -> usize {
    let dots = shapes.filter(|s| s.part == "tie" && s.fill == Ink::Role("ink2") && s.stroke == Ink::None).count();
    if dots > 1 { dots - 1 } else { dots }
}

fn plan_with(els: &str) -> Diagram {
    let mut d = Diagram::default();
    apply(&mut d, &op(&format!(r#"{{"op":"add","els":{els}}}"#))).unwrap();
    // Read as a plan saved before labels were typed (2026-10-15): a unit
    // with no Name takes its unit's, as the app shows it.
    plot::typed_labels(&mut d);
    // And before every piece took a typed label (2026-10-17), read with the
    // old look on: capitals, counts and the Unlabeled line.
    plot::free_names(&mut d);
    d.settings.caps = true;
    d.settings.counts = true;
    d.settings.unlabeled = true;
    d
}

/// Every plan is a plot (the picture style is retired, 2026-10-03); kept
/// so the plot's checks read as they were written.
fn plotted(d: Diagram) -> Diagram {
    d
}

#[test]
fn an_element_round_trips_and_writes_only_what_differs() {
    let mut e = El::new(Kind::Camera, "c1");
    e.x = 2.5;
    e.shot = "123".into();
    e.steps.push(Step { x: 3.0, y: 1.0, rot: 90.0, pose: Pose::Standing, turn: false, beat: 2 });
    e.steps.insert(0, Step { x: -3.0, y: 1.0, rot: 0.0, pose: Pose::Same, turn: false, beat: 0 });
    e.lead = 1;
    let text = e.to_json().encode();
    assert!(!text.contains("\"cone\""), "a default is not written: {text}");
    assert!(!text.contains("\"sensor\""), "{text}");
    let back = El::from_json(&json::parse(&text).unwrap()).unwrap();
    assert_eq!(back, e);
}

#[test]
fn a_whole_plan_round_trips() {
    let mut d = plan_with(r##"[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"camera","x":1,"y":2,"rot":45,"color":"#E0625A"}]"##);
    d.settings.units = "m".into();
    d.settings.dims = false;
    let back = Diagram::parse(&d.encode());
    assert_eq!(back, d);
}

#[test]
fn a_broken_plan_reads_as_an_empty_one_not_a_crash() {
    assert!(Diagram::parse("not json").is_empty());
    assert!(Diagram::parse(r#"{"els":[{"kind":"wizard","id":"x"}]}"#).is_empty());
    let d = Diagram::parse(r#"{"els":[{"kind":"set","id":"a","x":"nope"}]}"#);
    assert_eq!(d.els.len(), 1);
    assert_eq!(d.els[0].x, 0.0);
}

#[test]
fn two_elements_with_one_id_keep_the_first() {
    let d = Diagram::parse(r#"{"els":[{"kind":"set","id":"a","x":1},{"kind":"set","id":"a","x":2}]}"#);
    assert_eq!(d.els.len(), 1);
    assert_eq!(d.els[0].x, 1.0);
}

#[test]
fn adding_makes_ids_and_puts_things_in_their_layer() {
    let mut d = plan_with(r#"[{"kind":"camera","x":1,"y":1}]"#);
    let made = apply(&mut d, &op(r#"{"op":"add","els":[{"kind":"rug"},{"kind":"set","sym":"rug"},{"kind":"wall","x2":3}]}"#)).unwrap();
    // "rug" is not a kind: it is skipped, not guessed at.
    assert_eq!(made.len(), 2);
    let kinds: Vec<Kind> = d.els.iter().map(|e| e.kind).collect();
    assert_eq!(kinds, vec![Kind::Set, Kind::Wall, Kind::Camera], "the camera stays on top");
}

#[test]
fn an_update_merges_and_cannot_change_what_a_thing_is() {
    let mut d = plan_with(r#"[{"kind":"camera","id":"c","x":1}]"#);
    apply(&mut d, &op(r#"{"op":"update","id":"c","set":{"lens":85,"kind":"wall","id":"hijack"}}"#)).unwrap();
    let c = d.get("c").expect("still called c");
    assert_eq!(c.kind, Kind::Camera);
    assert_eq!(c.lens, 85.0);
    assert_eq!(c.x, 1.0);
}

#[test]
fn updating_something_that_is_not_there_says_so() {
    let mut d = Diagram::default();
    let r = apply(&mut d, &op(r#"{"op":"update","id":"ghost","set":{"x":1}}"#));
    assert_eq!(r, Err(EditError::Missing("ghost".into())));
}

#[test]
fn moving_one_member_of_a_group_moves_the_group_but_not_a_locked_one() {
    let mut d = plan_with(r#"[{"kind":"set","id":"a","x":0},{"kind":"set","id":"b","x":1},{"kind":"set","id":"c","x":2,"locked":true},{"kind":"set","id":"z","x":9}]"#);
    apply(&mut d, &op(r#"{"op":"group","ids":["a","b","c"]}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"move","ids":["a"],"dx":1,"dy":2}"#)).unwrap();
    assert_eq!((d.get("a").unwrap().x, d.get("a").unwrap().y), (1.0, 2.0));
    assert_eq!(d.get("b").unwrap().x, 2.0);
    assert_eq!(d.get("c").unwrap().x, 2.0, "locked stays");
    assert_eq!(d.get("z").unwrap().x, 9.0);
}

#[test]
fn moving_the_thing_leaves_its_other_steps_and_duplicating_brings_them() {
    // Each step is a place of its own (his note of 2026-09-28, of A → B).
    let mut d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0,"path":[{"beat":2,"x":3,"y":0}]}]"#);
    apply(&mut d, &op(r#"{"op":"move","ids":["a"],"dx":1,"dy":0}"#)).unwrap();
    assert_eq!((d.get("a").unwrap().x, d.get("a").unwrap().steps[0].x), (1.0, 3.0));
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["a"],"dx":1,"dy":0}"#)).unwrap();
    assert_eq!(d.get(&made[0]).unwrap().steps[0].x, 4.0, "a copy is the whole blocking, moved");
}

#[test]
fn turning_a_pair_turns_them_about_their_shared_middle() {
    let mut d = plan_with(r#"[{"kind":"set","id":"a","x":0,"y":0,"w":0.2,"h":0.2},{"kind":"set","id":"b","x":2,"y":0,"w":0.2,"h":0.2}]"#);
    apply(&mut d, &op(r#"{"op":"rotate","ids":["a","b"],"deg":90}"#)).unwrap();
    let (a, b) = (d.get("a").unwrap(), d.get("b").unwrap());
    assert!((a.x - 1.0).abs() < 1e-9 && (a.y + 1.0).abs() < 1e-9, "{a:?}");
    assert!((b.x - 1.0).abs() < 1e-9 && (b.y - 1.0).abs() < 1e-9, "{b:?}");
    assert_eq!(a.rot, 90.0);
}

#[test]
fn a_copied_camera_is_not_a_second_place_for_its_shot() {
    let mut d = plan_with(r#"[{"kind":"camera","id":"c","shot":"42"}]"#);
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["c"]}"#)).unwrap();
    assert_eq!(made.len(), 1);
    assert_eq!(d.get(&made[0]).unwrap().shot, "");
    assert_eq!(d.camera_for("42").unwrap().id, "c");
}

#[test]
fn a_copied_group_is_its_own_group() {
    let mut d = plan_with(r#"[{"kind":"set","id":"a"},{"kind":"set","id":"b"}]"#);
    apply(&mut d, &op(r#"{"op":"group","ids":["a","b"]}"#)).unwrap();
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["a"]}"#)).unwrap();
    assert_eq!(made.len(), 2, "the whole group comes");
    let g = &d.get(&made[0]).unwrap().group;
    assert_ne!(g, &d.get("a").unwrap().group);
    assert_eq!(g, &d.get(&made[1]).unwrap().group);
}

#[test]
fn front_and_back() {
    let mut d = plan_with(r#"[{"kind":"set","id":"a"},{"kind":"set","id":"b"},{"kind":"set","id":"c"}]"#);
    apply(&mut d, &op(r#"{"op":"order","ids":["a"],"to":"front"}"#)).unwrap();
    assert_eq!(d.els.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(), ["b", "c", "a"]);
    apply(&mut d, &op(r#"{"op":"order","ids":["a"],"to":"backward"}"#)).unwrap();
    assert_eq!(d.els.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(), ["b", "a", "c"]);
    apply(&mut d, &op(r#"{"op":"order","ids":["c"],"to":"back"}"#)).unwrap();
    assert_eq!(d.els.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(), ["c", "b", "a"]);
}

#[test]
fn aligning_and_spacing() {
    let mut d = plan_with(r#"[{"kind":"set","id":"a","x":0,"y":0,"w":1,"h":1},{"kind":"set","id":"b","x":5,"y":3,"w":1,"h":1},{"kind":"set","id":"c","x":1,"y":9,"w":1,"h":1}]"#);
    apply(&mut d, &op(r#"{"op":"align","ids":["a","b","c"],"to":"left"}"#)).unwrap();
    assert!(d.els.iter().all(|e| (e.x - 0.0).abs() < 1e-9));
    apply(&mut d, &op(r#"{"op":"distribute","ids":["a","b","c"],"axis":"y"}"#)).unwrap();
    assert!((d.get("b").unwrap().y - 4.5).abs() < 1e-9);
}

#[test]
fn a_beat_is_set_moved_and_forgotten() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0}]"#);
    apply(&mut d, &op(r#"{"op":"beat","id":"a","beat":3,"x":4,"y":1}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"beat","id":"a","beat":2,"x":2,"y":1}"#)).unwrap();
    let a = d.get("a").unwrap();
    assert_eq!(a.steps.iter().map(|b| b.beat).collect::<Vec<_>>(), [2, 3], "made in beat order");
    assert_eq!(a.at_beat(1), (0.0, 0.0, 0.0));
    assert_eq!(a.at_beat(2).0, 2.0);
    assert_eq!(a.at_beat(9).0, 4.0, "after its last beat it stays put");
    assert_eq!(d.last_beat(), 3);
    apply(&mut d, &op(r#"{"op":"beat","id":"a","beat":1,"x":-1,"y":0}"#)).unwrap();
    assert_eq!(d.get("a").unwrap().x, -1.0);
    apply(&mut d, &op(r#"{"op":"unbeat","id":"a","beat":2}"#)).unwrap();
    assert_eq!(d.get("a").unwrap().steps.len(), 1);
}

#[test]
fn flipping_mirrors_turns_and_hinges() {
    let mut d = plan_with(r#"[{"kind":"door","id":"d","x":1,"y":0,"rot":0},{"kind":"set","id":"s","x":3,"y":0,"rot":30}]"#);
    apply(&mut d, &op(r#"{"op":"flip","ids":["d","s"],"axis":"x"}"#)).unwrap();
    assert_eq!(d.get("d").unwrap().hinge, "right");
    assert_eq!(d.get("s").unwrap().rot, 150.0);
    assert!((d.get("s").unwrap().x - d.get("d").unwrap().x + 2.0).abs() < 1e-6);
}

#[test]
fn settings_merge() {
    let mut d = Diagram::default();
    apply(&mut d, &op(r#"{"op":"settings","set":{"units":"m","grid":false}}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"settings","set":{"dims":false}}"#)).unwrap();
    assert_eq!(d.settings.units, "m");
    assert!(!d.settings.grid && !d.settings.dims && d.settings.cones);
}

#[test]
fn an_unknown_edit_is_refused_by_name() {
    let mut d = Diagram::default();
    assert_eq!(apply(&mut d, &op(r#"{"op":"explode"}"#)), Err(EditError::Unknown("explode".into())));
}

#[test]
fn hitting_finds_the_top_thing_and_a_wall_by_its_thickness() {
    let d = plan_with(r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":4,"y2":0,"thick":0.2},{"kind":"set","id":"s","x":2,"y":0,"w":1,"h":1}]"#);
    assert_eq!(hit(&d, 2.0, 0.0, 0.05, 1).as_deref(), Some("w"), "walls sit above set pieces");
    assert_eq!(hit(&d, 3.5, 0.08, 0.0, 1).as_deref(), Some("w"));
    assert_eq!(hit(&d, 2.0, 0.4, 0.0, 1).as_deref(), Some("s"));
    assert_eq!(hit(&d, 9.0, 9.0, 0.1, 1), None);
}

#[test]
fn a_moving_thing_is_hit_where_it_stands_at_the_beat() {
    let d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0,"path":[{"beat":2,"x":5,"y":0}]}]"#);
    assert_eq!(hit(&d, 5.0, 0.0, 0.0, 2).as_deref(), Some("a"));
    assert_eq!(hit(&d, 5.0, 0.0, 0.0, 1), None);
}

#[test]
fn snapping_catches_a_wall_end_before_the_grid() {
    let d = plan_with(r#"[{"kind":"wall","id":"w","x":0.1,"y":0.1,"x2":4,"y2":0.1}]"#);
    let (p, caught) = snap_point(&d, 0.2, 0.15, 0.25, &[]);
    assert!(caught);
    assert_eq!(p, (0.1, 0.1));
    let (p, caught) = snap_point(&d, 2.0, 2.0, 0.25, &[]);
    assert!(!caught);
    assert!((p.0 / FOOT - (p.0 / FOOT).round()).abs() < 1e-9);
}

#[test]
fn with_snap_off_a_point_is_not_pulled_onto_a_table() {
    // His report, 2026-10-06: measuring from a table's edge jumped to its
    // corner or middle however Snap was set. A table is a box (a set piece).
    let mut d = plan_with(r#"[{"kind":"set","id":"t","sym":"table","x":2,"y":2,"w":2,"h":1}]"#);
    d.settings.snap = true;
    let (p, caught) = snap_point(&d, 3.02, 2.52, 0.25, &[]);
    assert!(caught, "Snap on: the table's corner takes it");
    assert_eq!(p, (3.0, 2.5));
    d.settings.snap = false;
    let (p, caught) = snap_point(&d, 3.02, 2.52, 0.25, &[]);
    assert!(!caught, "Snap off: nothing takes it");
    assert_eq!(p, (3.02, 2.52), "it stays where the hand put it");
    let (p, _) = snap_point(&d, 3.0, 2.2, 0.25, &[]);
    assert_eq!(p, (3.0, 2.2), "and a point on the table's edge stays on it");
}

#[test]
fn a_door_dropped_near_a_wall_lands_in_it() {
    let d = plan_with(r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":0,"y2":4,"thick":0.2}]"#);
    let (x, y, rot, thick) = onto_wall(&d, 0.3, 2.0, 0.5).unwrap();
    assert_eq!((x, y, thick), (0.0, 2.0, 0.2));
    assert_eq!(rot, 90.0);
    assert!(onto_wall(&d, 3.0, 2.0, 0.5).is_none());
}

#[test]
fn lengths_read_the_way_he_measures() {
    assert_eq!(length_text(3.7338, "ft"), "12 ft 3 in");
    assert_eq!(length_text(0.3048, "ft"), "1 ft");
    assert_eq!(length_text(0.1, "ft"), "4 in");
    assert_eq!(length_text(3.7338, "m"), "3.73 m");
    // To the quarter inch, as typed: 36' 6 1/2", and 6 1/2" alone.
    assert_eq!(length_text(36.0 * 0.3048 + 6.5 * 0.0254, "ft"), "36 ft 6 ½ in");
    assert_eq!(length_text(6.5 * 0.0254, "ft"), "6 ½ in");
    assert_eq!(length_text(0.25 * 0.0254, "ft"), "¼ in");
    // Anything else, to the whole inch: 4.5 m is 14 ft 9 in, not 14 ft 9 ¼.
    assert_eq!(length_text(4.5, "ft"), "14 ft 9 in");
}

// ---------------------------------------------------------------- drawing

fn ctx() -> Context {
    Context {
        shots: vec![("s1".into(), "1A".into(), "85mm".into())],
        ..Default::default()
    }
}

#[test]
fn a_linked_camera_is_named_by_its_shot_and_sees_through_its_lens() {
    let d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"shot":"s1"},{"kind":"camera","id":"d","x":5,"y":0,"label":"B"}]"#);
    let shapes = render::render(&d, &ctx(), &Options::default());
    let tag = shapes.iter().find(|s| s.el == "c" && s.part == "label").expect("a name");
    assert!(matches!(&tag.geom, Geom::Text { text, .. } if text == "1A"));
    let other = shapes.iter().find(|s| s.el == "d" && s.part == "label").expect("a name");
    assert!(matches!(&other.geom, Geom::Text { text, .. } if text == "B"));
    assert_eq!(render::camera_focal(d.get("c").unwrap(), &ctx()), 85.0);
    assert_eq!(render::camera_focal(d.get("d").unwrap(), &ctx()), 35.0, "unlinked, a 35");
    assert!(shapes.iter().any(|s| s.el == "c" && s.part == "cone"));
}

#[test]
fn every_catalogue_drawing_draws_something() {
    for sym in symbols::CATALOG {
        let e = El::new(Kind::Set, "x");
        assert!(!symbols::draw(sym.id, sym.w, sym.h, &e).is_empty(), "{}", sym.id);
    }
    assert!(!symbols::draw("nonsense", 1.0, 1.0, &El::new(Kind::Set, "x")).is_empty());
}

#[test]
fn every_kind_renders_without_trouble() {
    let mut d = Diagram::default();
    for (i, kind) in Kind::ALL.iter().enumerate() {
        let mut e = El::new(*kind, &format!("e{i}"));
        e.x = i as f64;
        e.x2 = i as f64 + 2.0;
        e.y2 = 1.0;
        e.text = "Words".into();
        e.label = "Label".into();
        e.points = vec![(0.0, 0.0), (1.0, 1.0), (2.0, 0.0)];
        d.els.push(e);
    }
    let shapes = render::render(&d, &ctx(), &Options::default());
    for kind in Kind::ALL {
        let id = format!("e{}", Kind::ALL.iter().position(|k| *k == kind).unwrap());
        assert!(shapes.iter().any(|s| s.el == id), "{kind:?} drew nothing");
    }
    let svg = svg::svg(&d, &ctx(), &Options::default(), &svg::Frame::default(), "t");
    assert!(svg.starts_with("<svg") && svg.ends_with("</svg>"));
    assert!(!svg.contains("NaN") && !svg.contains("inf"), "{svg}");
}

#[test]
fn an_empty_plan_still_makes_a_picture() {
    let svg = svg::svg(&Diagram::default(), &Context::default(), &Options::default(), &svg::Frame::default(), "e");
    assert!(svg.contains("<svg") && svg.contains("</svg>"));
}

#[test]
fn the_picture_says_which_element_each_shape_is_and_escapes_words() {
    let d = plan_with(r#"[{"kind":"text","id":"t","text":"<b>&"},{"kind":"camera","id":"c","shot":"s1"}]"#);
    let svg = svg::svg(&d, &ctx(), &Options::default(), &svg::Frame::default(), "p");
    assert!(svg.contains(r#"data-el="c""#));
    assert!(svg.contains("&lt;B&gt;&amp;"), "escaped, and in a plot's capitals");
    assert!(!svg.contains("<b>"));
}

#[test]
fn new_pieces_in_a_film_in_feet_come_in_feet_and_a_new_frame_lies_flat() {
    let d = plan_with(
        r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":4,"y2":0},{"kind":"door","id":"d","x":1,"y":0},{"kind":"window","id":"n","x":3,"y":0},
            {"kind":"light","id":"f","sym":"frame","x":0,"y":2,"h":2.4384}]"#,
    );
    let ft = |id: &str, v: fn(&El) -> f64| (v(d.get(id).unwrap()) / FOOT * 100.0).round() / 100.0;
    assert_eq!(ft("w", |e| e.thick), 0.5);
    assert_eq!(ft("d", |e| e.w), 3.0);
    assert_eq!(ft("n", |e| e.w), 4.0);
    let f = d.get("f").unwrap();
    assert_eq!((f.tilt, ft("f", |e| e.w)), (0.0, 8.0), "flat: as long as it is tall");
    // Written, so it reads back flat; a copy of a standing frame (its worked-
    // out `w`, no `tilt`) stays standing.
    let back = El::from_json(&f.to_json()).unwrap();
    assert_eq!(back.tilt, 0.0);
    let mut standing = f.clone();
    standing.tilt = 90.0;
    frame::settle(&mut standing);
    let copy = plan_with(&format!("[{}]", standing.to_json().encode()));
    assert_eq!(copy.els[0].tilt, 90.0);
    // In metres, the old sizes.
    let mut m = Diagram::default();
    m.settings.units = "m".into();
    apply(&mut m, &op(r#"{"op":"add","els":[{"kind":"door","id":"d","x":1,"y":0}]}"#)).unwrap();
    assert_eq!(m.get("d").unwrap().w, 0.9);
}

#[test]
fn a_frame_sized_with_snap_on_is_whole_feet() {
    let mut d = plan_with(r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":2.4384}]"#);
    d.settings.snap = true;
    apply(&mut d, &op(r#"{"op":"update","ids":["f"],"set":{"h":2.9,"tall":1.7}}"#)).unwrap();
    let f = d.get("f").unwrap();
    assert_eq!(((f.h / FOOT).round(), (f.tall / FOOT).round()), (10.0, 6.0));
    assert!((f.h / FOOT - 10.0).abs() < 1e-3 && (f.tall / FOOT - 6.0).abs() < 1e-3);
    assert_eq!(frame::plan_name(f), "10×6 Medium Diffusion");
}

/// His note, 2026-10-01: a tilted frame "feels too 2D". Leaning, it is
/// drawn as Scenario's is — its raised back edge full width and heavier,
/// its front edge narrower — and standing, one straight line.
#[test]
fn a_leaning_frame_narrows_toward_its_front_and_its_raised_edge_is_heavier() {
    // The skin's outline: the across-spread at the back (-x) and front (+x).
    let spread = |tilt: f64, width: f64| {
        let d = plan_with(&format!(r#"[{{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":{width},"tilt":{tilt},"pipe":"open"}}]"#));
        let f = d.get("f").unwrap();
        let shapes = frame::draw(f, f.w, f.h);
        let Geom::Path(segs) = &shapes[0].geom else { panic!("the skin is a path") };
        let pts: Vec<(f64, f64)> = segs.iter().filter_map(|s| match s {
            render::Seg::M(x, y) | render::Seg::L(x, y) => Some((*x, *y)),
            _ => None,
        }).collect();
        let at = |back: bool| {
            let x = if back { -f.w / 2.0 } else { f.w / 2.0 };
            let ys: Vec<f64> = pts.iter().filter(|p| (p.0 - x).abs() < 1e-9).map(|p| p.1).collect();
            ys.iter().cloned().fold(f64::MIN, f64::max) - ys.iter().cloned().fold(f64::MAX, f64::min)
        };
        let heavy = shapes.iter().map(|s| s.line).fold(0.0, f64::max);
        (at(true), at(false), heavy)
    };
    let (back, front, heavy0) = spread(0.0, 2.4384);
    assert!((back - front).abs() < 1e-9, "flat: square-on");
    // His Let's Bake frames: 12' at 80°, still leaning.
    let (back, front, _) = spread(80.0, 3.66);
    assert!(front < back * 0.9, "12' at 80°: back {back}, front {front}");
    let (back, front, heavy) = spread(75.0, 2.4384);
    assert!((back - 2.4384).abs() < 1e-9 && front < back * 0.9 && front > back * 0.8, "75°: back {back}, front {front}");
    assert!(heavy > heavy0 * 1.5, "the raised edge is heavier: {heavy} against {heavy0}");
    // Upright it is its pipe: straight, not a trapezoid.
    let (back, front, _) = spread(90.0, 2.4384);
    assert!((back - front).abs() < 1e-9, "standing: {back} vs {front}");
    assert_eq!((frame::taper(0.0), frame::taper(90.0)), (1.0, 0.8));
}

#[test]
fn the_library_sorts_lamps_grip_and_set_and_finds_them_by_nickname() {
    let all = symbols::offered();
    let place = |id: &str| all.iter().find(|o| o.0 == id).map(|o| o.5.clone()).unwrap_or_else(|| panic!("{id}"));
    assert_eq!((place("fso-arri-m18").lib, place("fso-arri-m18").kind, place("fso-arri-m18").maker), ("light", "HMI", "ARRI"));
    assert_eq!(place("fso-china-ball").kind, "Soft");
    assert_eq!(place("fso-kino-bare-4ft-daylight").kind, "Fluorescent");
    assert_eq!((place("frame").lib, place("frame").kind), ("grip", "Frames & Rags"));
    // The pack's rags and flags are the Frame's to make (2026-10-01); its boards stay.
    assert!(all.iter().all(|o| o.0 != "fso-12x12-flag-with-frame"), "the Frame makes a 12×12 flag");
    assert_eq!((place("fso-4x4-foam-core").lib, place("fso-4x4-foam-core").kind), ("grip", "Boards & Cards"));
    assert_eq!(place("fso-cto-roll").kind, "Rolls");
    assert_eq!((place("fso-10ft-speed-rail").lib, place("fso-10ft-speed-rail").kind), ("grip", "Stands & Rigging"));
    assert_eq!((place("fso-condor").lib, place("fso-condor").kind), ("grip", "Lifts"));
    assert_eq!((place("fso-chapman-dolly").lib, place("fso-chapman-dolly").kind), ("set", "Camera Support"));
    assert_eq!((place("fso-400a-distro").lib, place("fso-400a-distro").kind), ("set", "Electric"));
    assert_eq!(place("fso-dit-cart").kind, "Props");
    assert_eq!(place("fso-car").kind, "Vehicles");
    assert_eq!(place("hmi-par-4k").kind, "HMI");
    // Every lamp is in the light library, and nothing else is.
    for o in &all {
        assert_eq!(o.5.lib == "light", symbols::emits(o.0) || fso::find(o.0).map(|a| a.role == "fixture").unwrap_or(false), "{}", o.0);
    }
    let find = |q: &str| -> Vec<&str> { all.iter().filter(|o| library::matches(q, o.1, o.2, &o.5)).map(|o| o.1).collect() };
    assert!(find("m18").contains(&"Arri M18"));
    assert!(find("4k par").contains(&"4K HMI PAR") && find("4k par").contains(&"Arri M40"));
    assert!(find("kino").contains(&"Kino Bare 4' Daylight"));
    assert!(find("titan").iter().any(|n| n.starts_with("Astera")));
    assert!(find("chinaball").contains(&"China Ball"));
    assert!(find("skypanel s60").contains(&"Arri S60c"));
    // The Frame stands in for the rags and flags that left, so it answers to them.
    for q in ["floppy", "flag", "solid", "cutter", "silk", "net", "rag", "butterfly"] {
        assert!(find(q).contains(&"Frame"), "{q} finds the Frame");
    }
}

#[test]
fn a_scanned_room_lands_right_way_up_and_replaces_the_last_one() {
    let plan = crate::room::sample().expect("the sample room");
    let mut d = plan_with(r#"[{"kind":"camera","id":"mine","x":1,"y":1}]"#);
    let first = import_room(&mut d, &plan, "loc1");
    assert!(first.len() >= 4);
    // The six walls of the L are one wall, closed, as the Wall tool draws a room.
    let walls: Vec<&El> = d.els.iter().filter(|e| e.kind == Kind::Wall).collect();
    assert_eq!(walls.len(), 1, "{walls:?}");
    assert!(walls[0].closed && super::walls::corners(walls[0]).len() >= 6);
    let count = d.els.len();
    import_room(&mut d, &plan, "loc1");
    assert_eq!(d.els.len(), count, "a second import replaces the first");
    assert!(d.get("mine").is_some(), "what he drew stays");
    assert_eq!(d.room_from, "loc1");
    for e in d.els.iter().filter(|e| e.kind == Kind::Wall) {
        assert!(e.x >= -0.01 && e.y >= -0.01, "{e:?}");
    }
}

/// The room comes across as the location's own floor plan draws it — never
/// mirrored. The Den on *Mirrorland* came in back to front (2026-09-27)
/// because the import flipped the scan top to bottom.
#[test]
fn a_scanned_room_is_not_mirrored() {
    let plan = crate::room::sample().expect("the sample room");
    let ((minx, miny), _) = plan.bounds;
    let placed = room_elements(&plan, &Diagram::default());
    assert_eq!(placed.len(), plan.items.len());
    for (item, el) in plan.items.iter().zip(&placed) {
        let (x, y) = if el.kind == Kind::Wall {
            ((el.x + el.x2) / 2.0, (el.y + el.y2) / 2.0)
        } else {
            (el.x, el.y)
        };
        assert!((x - (item.centre.0 - minx) as f64).abs() < 1e-3, "{el:?}");
        assert!((y - (item.centre.1 - miny) as f64).abs() < 1e-3, "{el:?}");
        if el.kind != Kind::Wall {
            let turn = (el.rot - (item.angle as f64).to_degrees()).rem_euclid(360.0);
            assert!(turn < 1e-3 || turn > 360.0 - 1e-3, "{el:?} {}", item.angle);
        }
    }
}

#[test]
fn the_wire_is_json_a_reader_can_take() {
    let d = sample();
    let text = wire::payload(&d, &Context::default(), &Options::default());
    let v = json::parse(&text).expect("the payload is JSON");
    assert_eq!(v.get("els").unwrap().as_array().unwrap().len(), d.els.len());
    assert!(v.get("shapes").unwrap().as_array().unwrap().len() > 50);
    assert_eq!(v.get("lastBeat").unwrap().as_f64(), Some(2.0));
    let cam = v.get("els").unwrap().as_array().unwrap().iter().find(|e| e.str_field("kind") == "camera").unwrap();
    assert!(cam.get("aov").is_some() && cam.get("focal").is_some());
    let lib = json::parse(&wire::library()).expect("the library is JSON");
    assert!(lib.get("symbols").unwrap().as_array().unwrap().len() > 60);
}

#[test]
fn a_set_piece_the_library_hides_is_still_sent_by_its_own_name() {
    // A scanned room lays our `table`, which the pack's drawings hide from
    // the library; the Mac's lists must still say Table, not Set Piece.
    let d = plan_with(r#"[{"kind":"set","id":"t","sym":"table","x":0,"y":0,"w":1.6,"h":0.9},
                          {"kind":"set","id":"n","sym":"","x":2,"y":0,"w":1,"h":1}]"#);
    let v = json::parse(&wire::payload(&d, &Context::default(), &Options::default())).unwrap();
    let els = v.get("els").unwrap().as_array().unwrap();
    let by = |id: &str| els.iter().find(|e| e.str_field("id") == id).unwrap().clone();
    assert_eq!(by("t").str_field("name"), "Table");
    assert!(by("n").get("name").is_none(), "no drawing, no name");
}

#[test]
fn playing_a_move_passes_through_the_middle_and_turns_the_short_way() {
    let d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0,"rot":350,"path":[{"beat":2,"x":4,"y":0,"rot":10}]}]"#);
    let e = d.get("a").unwrap();
    let half = render::placed(e, &Options { beat: 1, tween: 0.5, ..Default::default() });
    assert!((half.0 - 2.0).abs() < 1e-9, "{half:?}");
    assert!(half.2 < 1e-6 || half.2 > 359.999, "turns through north, not the long way: {half:?}");
    let start = render::placed(e, &Options { beat: 1, tween: 0.0, ..Default::default() });
    assert_eq!(start, (0.0, 0.0, 350.0));
    // Past its last beat nothing moves.
    let after = render::placed(e, &Options { beat: 2, tween: 0.5, ..Default::default() });
    assert_eq!(after.0, 4.0);
}

#[test]
fn the_sun_falls_across_the_plan_from_where_it_stands() {
    let mut d = plan_with(r#"[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]"#);
    d.settings.sun = true;
    d.settings.sun_date = "2026-09-22".into();
    d.settings.sun_time = "13:00".into();
    let mut c = ctx();
    let none = render::render(&d, &c, &Options::default());
    assert!(none.iter().any(|s| matches!(&s.geom, Geom::Text { text, .. } if text == "NO LOCATION WITH AN ADDRESS")));
    c.place = Some((34.05, -118.25));
    c.utc_offset = Some(-420.0);
    let shapes = render::render(&d, &c, &Options::default());
    let label = shapes.iter().find_map(|s| match &s.geom { Geom::Text { text, .. } if text.starts_with("SUN ") => Some(text.clone()), _ => None });
    assert!(label.as_deref().unwrap_or("").starts_with("SUN 13:00 · 5"), "{label:?}");
    // Due south at noon, with north straight up: the disc sits below the plan.
    let (x, y) = sun_disc(&shapes);
    assert!(y > 0.3 && (x - 2.0).abs() < 1.0, "{x},{y}");
    d.settings.sun_time = "23:30".into();
    let night = render::render(&d, &c, &Options::default());
    assert!(night.iter().any(|s| matches!(&s.geom, Geom::Text { text, .. } if text == "SUN DOWN")));
}

/// The sun's disc, where it is drawn.
fn sun_disc(shapes: &[render::Shape]) -> (f64, f64) {
    let disc = shapes.iter().rev().find(|s| s.part == "sun" && s.fill == Ink::Role("sun") && s.alpha > 0.5).expect("a sun");
    let b = render::bounds(std::slice::from_ref(disc)).unwrap();
    ((b.x1 + b.x2) / 2.0, (b.y1 + b.y2) / 2.0)
}

#[test]
fn the_sun_stands_still_while_things_move_near_it() {
    // His note, 2026-09-28: "I can chase it with my items". A room, a person
    // in it, and the late sun off to the west.
    let mut d = plan_with(
        r#"[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"wall","x":4,"y":0,"x2":4,"y2":3},
            {"kind":"wall","x":4,"y":3,"x2":0,"y2":3},{"kind":"wall","x":0,"y":3,"x2":0,"y2":0},
            {"kind":"cast","x":2,"y":1.5}]"#,
    );
    d.settings.sun = true;
    d.settings.sun_date = "2026-09-22".into();
    d.settings.sun_time = "17:30".into();
    let c = Context { place: Some((34.05, -118.25)), utc_offset: Some(-420.0), ..Default::default() };
    let first = sun_disc(&render::render(&d, &c, &Options::default()));
    assert!(first.0 < 0.0, "the late sun is not off to the west: {first:?}");
    // Walk the person out of the room, right up to the sun and past it.
    let id = d.els[4].id.clone();
    for x in [0.0, -0.5, -1.0, -1.5, -2.0, -3.0] {
        let i = d.els.iter().position(|e| e.id == id).unwrap();
        d.els[i].x = x;
        let now = sun_disc(&render::render(&d, &c, &Options::default()));
        assert!((now.0 - first.0).abs() < 1e-9 && (now.1 - first.1).abs() < 1e-9, "the sun moved to {now:?} with the person at {x}");
    }
    // Nothing standing still: measured off everything, on a coarse grid —
    // a small step is not followed.
    let mut open = plan_with(r#"[{"kind":"cast","x":0,"y":0},{"kind":"cast","x":3,"y":2},{"kind":"camera","x":1,"y":3}]"#);
    open.settings = d.settings.clone();
    let before = sun_disc(&render::render(&open, &c, &Options::default()));
    open.els[1].x = 3.2;
    assert_eq!(sun_disc(&render::render(&open, &c, &Options::default())), before);
    // Every hour of the day is inside what the screen fits.
    let reach = render::sun_ring(&d).reach();
    for t in ["06:50", "09:00", "12:00", "15:00", "18:40"] {
        d.settings.sun_time = t.into();
        let (x, y) = sun_disc(&render::render(&d, &c, &Options::default()));
        assert!(x > reach.x1 && x < reach.x2 && y > reach.y1 && y < reach.y2, "{t}: the sun at {x},{y} is outside {reach:?}");
        // …and never over the room.
        assert!(!(x > -0.1 && x < 4.1 && y > -0.1 && y < 3.1), "{t}: the sun is over the room at {x},{y}");
    }
}

#[test]
fn the_sun_goes_round_the_whole_set_not_just_its_walls() {
    // His note, 2026-10-02: in Call Her Back the sun sat in the middle of the
    // set. A house of walls, and a lawn (a stroke) and a table (a set piece)
    // spread well past it.
    let mut d = plan_with(
        r#"[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"wall","x":4,"y":0,"x2":4,"y2":3},
            {"kind":"wall","x":4,"y":3,"x2":0,"y2":3},{"kind":"wall","x":0,"y":3,"x2":0,"y2":0},
            {"kind":"stroke","points":[[0,4],[-6,9],[8,10],[0,4]]},
            {"kind":"set","x":-7,"y":6,"w":2,"h":1},
            {"kind":"cast","x":30,"y":30}]"#,
    );
    d.settings.sun = true;
    d.settings.sun_date = "2026-09-22".into();
    let c = Context { place: Some((34.05, -118.25)), utc_offset: Some(-420.0), ..Default::default() };
    for t in ["08:00", "12:45", "16:00", "17:30"] {
        d.settings.sun_time = t.into();
        let (x, y) = sun_disc(&render::render(&d, &c, &Options::default()));
        // Outside everything that is the place: the lawn and the table too.
        assert!(!(x > -8.1 && x < 8.1 && y > -0.1 && y < 10.1), "{t}: the sun is inside the set at {x},{y}");
    }
    // A person off in the distance is not part of the set.
    let ring = render::sun_ring(&d);
    assert!(ring.cx + ring.a < 20.0 && ring.cy + ring.b < 20.0, "a person far away stretched the orbit: {}, {}", ring.a, ring.b);
}

#[test]
fn north_and_the_sun_settings_round_trip() {
    let mut d = Diagram::default();
    apply(&mut d, &op(r#"{"op":"settings","set":{"north":400,"sun":true,"sun_date":"2026-10-01","sun_time":"16:00"}}"#)).unwrap();
    assert_eq!(d.settings.north, 40.0);
    // The rays are off unless asked for, and not written down until they are.
    assert!(!d.settings.sun_rays);
    assert!(!d.encode().contains("sun_rays"));
    let back = Diagram::parse(&d.encode());
    assert_eq!(back.settings, d.settings);
    apply(&mut d, &op(r#"{"op":"settings","set":{"sun_rays":true}}"#)).unwrap();
    assert!(Diagram::parse(&d.encode()).settings.sun_rays);
    // Anything but a yes is a no.
    apply(&mut d, &op(r#"{"op":"settings","set":{"sun_rays":"yes"}}"#)).unwrap();
    assert!(!d.settings.sun_rays);
}

/// Where a shape reaches, as the plan is shown.
fn shown_box(shapes: &[render::Shape], part: &str, turn: f64) -> super::Aabb {
    let mut these: Vec<render::Shape> = shapes.iter().filter(|s| s.part == part).cloned().collect();
    render::turn_shapes(&mut these, turn);
    render::bounds(&these).expect("something drawn")
}

#[test]
fn the_set_stays_put_and_north_and_the_sun_go_round_it() {
    // His note, 2026-09-29, taking back 2026-09-27's north-is-up: "spinning
    // the compass should not spin the set — the sun should move around the
    // set as it stays put."
    let mut d = plan_with(r#"[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"wall","x":4,"y":0,"x2":4,"y2":3}]"#);
    // The sun on, so the compass is drawn at north 0 as well.
    d.settings.sun = true;
    for north in [0.0, 40.0, 90.0, 200.0, 315.0] {
        d.settings.north = north;
        assert_eq!(render::view_turn(&d), 0.0, "north {north}: the plan is turned for showing");
        let shapes = render::render(&d, &ctx(), &Options::default());
        // The arrow's point lies toward north, measured clockwise from up.
        let arrow: Vec<render::Shape> =
            shapes.iter().filter(|s| s.part == "north" && s.fill == Ink::Role("ink2")).cloned().collect();
        let Geom::Path(segs) = &arrow[0].geom else { panic!("the arrow is a path") };
        let pts: Vec<(f64, f64)> = segs.iter().filter_map(|s| match *s { render::Seg::M(x, y) | render::Seg::L(x, y) => Some((x, y)), _ => None }).collect();
        let (cx, cy) = (pts.iter().map(|p| p.0).sum::<f64>() / pts.len() as f64, pts.iter().map(|p| p.1).sum::<f64>() / pts.len() as f64);
        let pointing = (pts[0].1 - cy).atan2(pts[0].0 - cx).to_degrees();
        let off = super::norm_deg(pointing - (-90.0 + north));
        assert!(off.min(360.0 - off) < 1.0, "north {north}: the arrow points {pointing}");
        // Off the top right of the plan, which is drawn as it stands.
        let walls = shown_box(&shapes, "body", 0.0);
        let compass = shown_box(&shapes, "north", 0.0);
        assert!(compass.x1 > walls.x2 - 1e-6 && compass.y2 < walls.y1 + 0.5, "north {north}: the compass is not off the top right");
        // Nothing on the plan itself moved.
        assert_eq!((d.els[0].x2, d.els[1].y2), (4.0, 3.0));
    }
    // The extent is the plan as it stands: turning north does not stand a
    // long wall on end.
    d.settings.north = 90.0;
    let e = render::extent(&d, &ctx()).unwrap();
    assert!(e.x2 - e.x1 > e.y2 - e.y1, "{e:?}");
    // The sun goes round the set by as much as north is turned.
    let (mut d, c) = sunny_room("");
    let bearing = |d: &Diagram| {
        let (sx, sy) = render::sun_spot(d, &c).expect("the sun is up");
        let ring = render::sun_ring(d);
        (sy - ring.cy).atan2(sx - ring.cx).to_degrees()
    };
    d.settings.north = 0.0;
    let at0 = bearing(&d);
    d.settings.north = 90.0;
    let at90 = bearing(&d);
    let moved = super::norm_deg(at90 - at0);
    assert!((moved - 90.0).abs() < 1.0, "the sun moved {moved}° for a quarter turn of north");
}

#[test]
fn a_shown_word_never_reads_upside_down() {
    let d = plan_with(r#"[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]"#);
    let mut shapes = render::render(&d, &ctx(), &Options::default());
    render::turn_shapes(&mut shapes, 170.0);
    for s in &shapes {
        if let Geom::Text { rot, fixed, anchor, .. } = &s.geom {
            if *anchor == "middle" && (!*fixed || rot.abs() > 1e-9) {
                assert!((-90.0..=90.0).contains(rot), "a word at {rot}°");
            }
        }
    }
}

/// A closed room four metres by three, and the noon sun over Los Angeles.
fn sunny_room(openings: &str) -> (Diagram, Context) {
    let mut d = plan_with(&format!(
        r#"[{{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}},{{"kind":"wall","x":4,"y":0,"x2":4,"y2":3}},
            {{"kind":"wall","x":4,"y":3,"x2":0,"y2":3}},{{"kind":"wall","x":0,"y":3,"x2":0,"y2":0}}{openings}]"#
    ));
    d.settings.sun = true;
    d.settings.sun_rays = true;
    d.settings.sun_date = "2026-09-22".into();
    d.settings.sun_time = "12:45".into();
    let c = Context { place: Some((34.05, -118.25)), utc_offset: Some(-420.0), ..Default::default() };
    (d, c)
}

#[test]
fn the_sun_words_fit_inside_what_the_screen_fits() {
    // Ref 1437: the sun's words (Sun 16:40 · 3° up) hang off its disc at a
    // fixed size, and ran past the picture's edge when the sun stood at the
    // left or right.
    let (mut d, c) = sunny_room("");
    let mut sides = 0;
    for t in ["06:50", "08:00", "12:45", "16:40", "17:55", "18:20"] {
        d.settings.sun_time = t.into();
        let shapes = render::render(&d, &c, &Options::default());
        let Some(words) = shapes.iter().find(|s| s.part == "sun" && matches!(s.geom, Geom::Text { .. })) else { continue };
        let Geom::Text { x, y, text, size, anchor, .. } = &words.geom else { unreachable!() };
        let view = 700.0;
        let e = render::extent_in(&d, &c, view).unwrap();
        // The scale the view would show it at, and the words at that scale.
        let k = (view / (e.x2 - e.x1)).min(view * 0.62 / (e.y2 - e.y1));
        let (w, h) = render::words_box_pt(&text.to_uppercase(), *size);
        let (w, h) = (w / k, h / k);
        let x1 = match *anchor { "start" => *x, "end" => x - w, _ => x - w / 2.0 };
        let eps = 0.02;
        assert!(x1 >= e.x1 - eps && x1 + w <= e.x2 + eps && y - h / 2.0 >= e.y1 - eps && y + h / 2.0 <= e.y2 + eps, "{t}: {text:?} at {x1:.2}..{:.2} is outside {e:?}", x1 + w);
        if *anchor != "middle" {
            sides += 1;
        }
    }
    assert!(sides > 0, "a time with the sun at the side was tried");
    // Without the sun, the extent is the plan's own.
    d.settings.sun = false;
    let plain = render::extent(&d, &c).unwrap();
    assert!(plain.x2 - plain.x1 < 8.0, "{plain:?}");
}

#[test]
fn the_suns_clock_follows_the_suns_own_day() {
    // Ref 1513: a test project's sun, set for 2026-11-02, read 26° up on the
    // screen and 16° on paper: the Mac sent October's offset (summer time) and
    // paper sent none.
    use super::sun;
    assert_eq!((sun::in_dst(sun::Dst::NorthAmerica, 2026, 3, 7), sun::in_dst(sun::Dst::NorthAmerica, 2026, 3, 8)), (false, true), "second Sunday of March 2026 is the 8th");
    assert_eq!((sun::in_dst(sun::Dst::NorthAmerica, 2026, 10, 31), sun::in_dst(sun::Dst::NorthAmerica, 2026, 11, 1)), (true, false), "first Sunday of November 2026 is the 1st");
    assert_eq!((sun::in_dst(sun::Dst::Europe, 2026, 3, 28), sun::in_dst(sun::Dst::Europe, 2026, 3, 29)), (false, true));
    assert_eq!((sun::in_dst(sun::Dst::Europe, 2026, 10, 24), sun::in_dst(sun::Dst::Europe, 2026, 10, 25)), (true, false));
    let (la, today) = ((34.05, -118.25), Some((2026, 10, 6)));
    let at = |p: (f64, f64), date, shell| sun::zone(p.0, p.1, date, shell, today);
    // The Mac's October offset, moved to a November day and a July one.
    assert_eq!(at(la, (2026, 11, 2), Some(-420.0)), -480.0);
    assert_eq!(at(la, (2026, 7, 4), Some(-420.0)), -420.0);
    // Told nothing, as Export is: the same hours.
    assert_eq!(at(la, (2026, 11, 2), None), -480.0);
    assert_eq!(at(la, (2026, 7, 4), None), -420.0);
    // From a winter day too.
    assert_eq!(sun::zone(la.0, la.1, (2026, 7, 4), Some(-480.0), Some((2026, 1, 15))), -420.0);
    // Berlin, and a place with no rule the engine knows: the shell's own.
    assert_eq!(at((52.5, 13.4), (2026, 7, 4), None), 120.0);
    assert_eq!(at((52.5, 13.4), (2026, 12, 4), None), 60.0);
    assert_eq!(at((33.5, -112.0), (2026, 7, 4), Some(-420.0)), -420.0, "Phoenix keeps its clock");
    assert_eq!(at((19.4, 72.8), (2026, 7, 4), Some(330.0)), 330.0);
    // A plan's own saved zone is the answer, whatever the shell says.
    let (mut d, c) = sunny_room("");
    d.settings.sun_tz = Some(-420.0);
    assert_eq!(render::sun_zone(&d, &Context { utc_offset: Some(60.0), ..c.clone() }, la.0, la.1, (2026, 11, 2), today), -420.0);
    // Screen and paper read the same sun on the same day.
    d.settings.sun_tz = None;
    let screen = Context { utc_offset: Some(-420.0), ..c.clone() };
    let paper = Context { utc_offset: None, ..c };
    assert_eq!(render::sun_zone(&d, &screen, la.0, la.1, (2026, 11, 2), today), render::sun_zone(&d, &paper, la.0, la.1, (2026, 11, 2), today));
}

#[test]
fn every_fixed_word_fits_inside_what_the_screen_fits() {
    // Ref 1577: a frame's name (12×12 Ultra Bounce · 45°) stood off its
    // piece at a fixed size and ran past the picture's edge when the piece
    // was the plan's leftmost or rightmost; only the sun's words had room.
    let d = plan_with(
        r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":3.6576,"material":"ultra-bounce","tilt":45,"caption":"Bounce for the Key Light"},
            {"kind":"cast","id":"c","x":9,"y":2,"label":"Maya the Long-Named Lead","caption":"Enters from the kitchen"}]"#,
    );
    let c = ctx();
    let shapes = render::render(&d, &c, &Options { paper: true, ..Options::default() });
    let plain = render::bounds(&shapes).unwrap();
    let view = 700.0;
    let e = render::extent_in(&d, &c, view).unwrap();
    assert!(e.x1 < plain.x1 - 0.2 || e.x2 > plain.x2 + 0.2, "room was made for the words: {plain:?} -> {e:?}");
    let k = (view / (e.x2 - e.x1)).min(view * 0.62 / (e.y2 - e.y1));
    let mut seen = 0;
    for s in &shapes {
        let Geom::Text { x, y, text, size, anchor, fixed: true, rot, bold, .. } = &s.geom else { continue };
        if rot.abs() > 1e-9 {
            continue;
        }
        let (w, h) = render::words_box_pt(&text.to_uppercase(), *size);
        let w = if *bold { w * 1.08 } else { w };
        let (w, h) = ((w + 2.0 * render::PATCH_PAD) / k, (h + render::PATCH_PAD) / k);
        let x1 = match *anchor { "start" => *x, "end" => x - w, _ => x - w / 2.0 };
        let eps = 0.02;
        assert!(x1 >= e.x1 - eps && x1 + w <= e.x2 + eps && y - h / 2.0 >= e.y1 - eps && y + h / 2.0 <= e.y2 + eps, "{text:?} at {x1:.2}..{:.2} is outside {e:?}", x1 + w);
        seen += 1;
    }
    assert!(seen >= 2, "both pieces' names were looked at");
}

#[test]
fn the_sun_comes_in_through_a_window_and_not_through_a_wall() {
    let pool = |d: &Diagram, c: &Context| {
        render::render(d, c, &Options::default())
            .into_iter()
            .filter(|s| s.part == "sunlight" && s.alpha < 0.5)
            .collect::<Vec<_>>()
    };
    // Rays off: nothing falls across the plan.
    let (mut d, c) = sunny_room("");
    d.settings.sun_rays = false;
    assert!(render::render(&d, &c, &Options::default()).iter().all(|s| s.part != "sunlight"));
    // Walls all round: lines outside, no light on the floor inside.
    let (d, c) = sunny_room("");
    assert!(render::render(&d, &c, &Options::default()).iter().any(|s| s.part == "sunlight"));
    assert!(pool(&d, &c).is_empty(), "light came through a wall");
    // A window in the south wall: a pool inside the room, the window's width.
    let (d, c) = sunny_room(r#",{"kind":"window","x":2,"y":3,"w":1.2}"#);
    let lit = pool(&d, &c);
    assert_eq!(lit.len(), 1);
    let b = render::bounds(&lit).unwrap();
    assert!(b.x1 > 0.0 && b.x2 < 4.0 && b.y1 >= -0.05 && b.y2 <= 3.05, "{b:?}");
    assert!(b.x2 - b.x1 < 2.2, "wider than its window: {b:?}");
    // A window on the north side, away from the noon sun, lets none in.
    let (d, c) = sunny_room(r#",{"kind":"window","x":2,"y":0,"w":1.2}"#);
    assert!(pool(&d, &c).is_empty(), "the noon sun came in a north window");
    // And sunlight never widens the picture.
    let (mut d, c) = sunny_room("");
    let with = render::extent(&d, &c).unwrap();
    d.settings.sun_rays = false;
    assert_eq!(render::extent(&d, &c).unwrap(), with);
}

#[test]
fn a_door_goes_where_its_wall_goes() {
    let mut d = Diagram::default();
    let made = apply(&mut d, &json::parse(r#"{"op":"add","els":[
        {"id":"w","kind":"wall","x":0,"y":0,"x2":4,"y2":0},
        {"id":"door","kind":"door","x":1,"y":0,"w":0.9},
        {"id":"chair","kind":"set","sym":"chair","x":1,"y":0.5}]}"#).unwrap()).unwrap();
    assert_eq!(made.len(), 3);
    // Moved: the door comes too, the chair stays.
    apply(&mut d, &json::parse(r#"{"op":"move","ids":["w"],"dx":0,"dy":2}"#).unwrap()).unwrap();
    let door = d.get("door").unwrap();
    assert!((door.x - 1.0).abs() < 1e-9 && (door.y - 2.0).abs() < 1e-9, "{},{}", door.x, door.y);
    assert_eq!(d.get("chair").unwrap().y, 0.5);
    // Its far end swung round to straight down: the door keeps its quarter of
    // the way along, and turns with it.
    apply(&mut d, &json::parse(r#"{"op":"update","ids":["w"],"set":{"x2":0,"y2":6}}"#).unwrap()).unwrap();
    let door = d.get("door").unwrap();
    assert!((door.x - 0.0).abs() < 1e-9 && (door.y - 3.0).abs() < 1e-9, "{},{}", door.x, door.y);
    assert!((door.rot - 90.0).abs() < 1e-6, "{}", door.rot);
    // Wall and door dragged together: the door moves once, not twice.
    apply(&mut d, &json::parse(r#"{"op":"move","ids":["w","door"],"dx":1,"dy":0}"#).unwrap()).unwrap();
    assert!((d.get("door").unwrap().x - 1.0).abs() < 1e-9);
}

#[test]
fn every_colour_on_paper_has_one_in_the_dark() {
    for (role, _) in super::svg::PAPER {
        assert!(super::svg::DARK.iter().any(|(r, _)| r == role), "no dark colour for {role}");
    }
}

#[test]
fn no_piece_draws_without_end_however_far_it_is_stretched() {
    for sym in super::symbols::CATALOG {
        let kind = if sym.light { "light" } else { "set" };
        let d = plan_with(&format!(r#"[{{"kind":"{kind}","sym":"{}","w":100000,"h":100000}}]"#, sym.id));
        let n = render::render(&d, &Context::default(), &Options::default()).len();
        assert!(n < 400, "{} at 100 km draws {n} shapes", sym.id);
    }
    let d = plan_with(r#"[{"kind":"track","x":-100000,"y":0,"x2":100000,"y2":0}]"#);
    assert!(render::render(&d, &Context::default(), &Options::default()).len() < 500);
}

// ---------------------------------------------------------------- walls stop light

/// The farthest a light's beam or glow reaches from a point, over every
/// corner of its outline.
fn beam_points(d: &Diagram, id: &str) -> Vec<(f64, f64)> {
    // Beams are off by default (2026-09-28); these are about beams.
    let mut d = d.clone();
    d.settings.beams = true;
    let shapes = render::render(&d, &ctx(), &Options::default());
    let beam = shapes.iter().find(|s| s.el == id && s.part == "beam").expect("a beam");
    let Geom::Path(segs) = &beam.geom else { panic!("a beam is a path") };
    segs.iter()
        .filter_map(|s| match s {
            render::Seg::M(x, y) | render::Seg::L(x, y) => Some((*x, *y)),
            render::Seg::C(_, _, _, _, x, y) => Some((*x, *y)),
            render::Seg::Z => None,
        })
        .collect()
}

#[test]
#[ignore = "lamp beams are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_wall_stops_a_lamps_beam() {
    // A lamp a metre west of a wall, facing it, reaching four.
    let d = plan_with(
        r#"[{"kind":"wall","id":"w","x":1,"y":-3,"x2":1,"y2":3},
            {"kind":"light","id":"l","x":-0.2,"y":0,"rot":0,"w":0.4,"h":0.4,"beam":40,"reach":4}]"#,
    );
    let pts = beam_points(&d, "l");
    assert!(pts.iter().all(|p| p.0 <= 1.0 + 1e-6), "no light past the wall: {pts:?}");
    assert!(pts.iter().any(|p| (p.0 - 1.0).abs() < 1e-6), "it reaches the wall");
}

#[test]
#[ignore = "lamp beams are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn light_goes_through_a_window_and_an_open_door_but_not_a_shut_one() {
    let wall = r#"{"kind":"wall","id":"w","x":1,"y":-3,"x2":1,"y2":3}"#;
    let lamp = r#"{"kind":"light","id":"l","x":-0.2,"y":0,"rot":0,"w":0.4,"h":0.4,"beam":40,"reach":4}"#;
    let far = |d: &Diagram| beam_points(d, "l").iter().map(|p| p.0).fold(f64::MIN, f64::max);
    for (gap, passes) in [
        (r#"{"kind":"window","x":1,"y":0,"rot":90,"w":1.2}"#, true),
        (r#"{"kind":"opening","x":1,"y":0,"rot":90,"w":1.0}"#, true),
        (r#"{"kind":"door","x":1,"y":0,"rot":90,"w":0.9}"#, true),
        (r#"{"kind":"door","x":1,"y":0,"rot":90,"w":0.9,"swing":0}"#, false),
    ] {
        let d = plan_with(&format!("[{wall},{gap},{lamp}]"));
        let reach = far(&d);
        if passes {
            assert!(reach > 3.0, "light passes {gap}: reached x={reach}");
        } else {
            assert!(reach <= 1.0 + 1e-6, "light stopped by {gap}: reached x={reach}");
        }
    }
}

#[test]
#[ignore = "lamp beams are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_glow_in_a_room_stays_in_the_room() {
    let d = plan_with(
        r#"[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0},{"kind":"wall","x":3,"y":0,"x2":3,"y2":3},
            {"kind":"wall","x":3,"y":3,"x2":0,"y2":3},{"kind":"wall","x":0,"y":3,"x2":0,"y2":0},
            {"kind":"light","id":"p","sym":"practical","x":1.5,"y":1.5,"w":0.3,"h":0.3,"beam":360,"reach":5}]"#,
    );
    let pts = beam_points(&d, "p");
    assert!(pts.len() > 8);
    for p in pts {
        assert!((-1e-6..=3.0 + 1e-6).contains(&p.0) && (-1e-6..=3.0 + 1e-6).contains(&p.1), "{p:?} is outside the room");
    }
}

#[test]
#[ignore = "lamp beams are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn with_no_wall_near_a_beam_keeps_its_round_edge() {
    let mut d = plan_with(
        r#"[{"kind":"wall","x":50,"y":50,"x2":60,"y2":50},
            {"kind":"light","id":"l","x":0,"y":0,"rot":0,"w":0.4,"h":0.4,"beam":40,"reach":4}]"#,
    );
    d.settings.beams = true;
    let shapes = render::render(&d, &ctx(), &Options::default());
    let beam = shapes.iter().find(|s| s.el == "l" && s.part == "beam").unwrap();
    let Geom::Path(segs) = &beam.geom else { panic!() };
    assert!(segs.iter().any(|s| matches!(s, render::Seg::C(..))), "still an arc");
    assert!(beam.fade.is_some(), "the fade stays");
}

// ---------------------------------------------------------------- steps

/// The letters and beats of a thing's steps, in letter order.
fn seq(d: &Diagram, id: &str) -> Vec<(String, u32)> {
    d.get(id).unwrap().sequence().iter().enumerate().map(|(i, p)| (letter(i), p.beat)).collect()
}

#[test]
fn letters_run_a_to_z_and_on_past_it() {
    assert_eq!(letter(0), "A");
    assert_eq!(letter(1), "B");
    assert_eq!(letter(25), "Z");
    assert_eq!(letter(26), "AA");
    assert_eq!(letter(27), "AB");
    assert_eq!(letter(701), "ZZ");
    assert_eq!(letter(702), "AAA");
}

#[test]
fn every_move_is_the_next_step_on_the_next_beat_as_many_as_he_likes() {
    // His ruling, 2026-10-01: not A and B, but as many steps as he wants.
    let mut d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"rot":0}]"#);
    assert!(!d.encode().contains("\"steps\""), "nothing written when it has none");
    for _ in 0..30 {
        apply(&mut d, &op(r#"{"op":"step_add","id":"c"}"#)).unwrap();
    }
    let s = seq(&d, "c");
    assert_eq!(s.len(), 31);
    assert_eq!(s[0], ("A".into(), 1), "the thing itself is A, on the first beat");
    assert_eq!(s[1], ("B".into(), 2));
    assert_eq!(s[26], ("AA".into(), 27), "on past Z");
    assert_eq!(s[30], ("AE".into(), 31));
    assert_eq!(d.last_beat(), 31);
    // Each a little on from the last, the way it faces.
    let c = d.get("c").unwrap();
    assert!(c.steps[0].x > 1.0 && c.steps[1].x > c.steps[0].x);
    // It plays: at beat 2 it stands on B.
    assert_eq!(c.at_beat(2).0, c.steps[0].x);
    let back = Diagram::parse(&d.encode());
    assert_eq!(back, d, "it reads back as itself");
}

#[test]
fn a_step_put_in_between_takes_its_place_in_the_beats() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0}]"#);
    apply(&mut d, &op(r#"{"op":"step_add","id":"a","x":1,"y":0}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"step_add","id":"a","x":2,"y":0}"#)).unwrap();
    // After B: the new one is C on beat 3, and what was C moves up to D on 4.
    apply(&mut d, &op(r#"{"op":"step_add","id":"a","after":1,"x":9,"y":9}"#)).unwrap();
    assert_eq!(seq(&d, "a"), [("A".into(), 1), ("B".into(), 2), ("C".into(), 3), ("D".into(), 4)]);
    assert_eq!(d.get("a").unwrap().steps[1].x, 9.0);
    // A Move From: a new first step, so where it stands is now B, a beat on.
    apply(&mut d, &op(r#"{"op":"step_add","id":"a","before":0,"x":-5,"y":0}"#)).unwrap();
    let a = d.get("a").unwrap();
    assert_eq!(a.lead, 1);
    assert_eq!(seq(&d, "a")[0], ("A".into(), 1));
    assert_eq!(seq(&d, "a")[1], ("B".into(), 2));
    assert_eq!(a.at_beat(1).0, -5.0, "it comes from there");
    assert_eq!(a.at_beat(2).0, 0.0, "to where it stands");
}

#[test]
fn a_step_is_put_on_any_beat_and_trades_with_the_one_there() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0}]"#);
    for x in [1, 2, 3] {
        apply(&mut d, &op(&format!(r#"{{"op":"step_add","id":"a","x":{x},"y":0}}"#))).unwrap();
    }
    // D on beat 2: B, which had it, takes D's old 4.
    apply(&mut d, &op(r#"{"op":"step_set","id":"a","step":3,"beat":2}"#)).unwrap();
    assert_eq!(seq(&d, "a").iter().map(|s| s.1).collect::<Vec<_>>(), [1, 4, 3, 2]);
    let a = d.get("a").unwrap();
    assert_eq!(a.at_beat(2).0, 3.0, "D plays second");
    assert_eq!(a.at_beat(4).0, 1.0, "B plays last");
    // Off every beat: kept on the plan, never played.
    apply(&mut d, &op(r#"{"op":"step_set","id":"a","step":3,"beat":0}"#)).unwrap();
    let a = d.get("a").unwrap();
    assert_eq!(a.at_beat(2).0, 0.0, "nothing on 2: it waits at A");
    assert_eq!(a.at_beat(3).0, 2.0);
    // Moved and turned on its own.
    apply(&mut d, &op(r#"{"op":"step_set","id":"a","step":2,"x":7,"y":7,"rot":45}"#)).unwrap();
    let a = d.get("a").unwrap();
    assert_eq!((a.steps[1].x, a.steps[1].y, a.steps[1].rot), (7.0, 7.0, 45.0));
    assert_eq!(a.x, 0.0, "the thing itself stays");
    // Taken away: the rest keep their letters' order.
    apply(&mut d, &op(r#"{"op":"step_remove","id":"a","step":1}"#)).unwrap();
    assert_eq!(d.get("a").unwrap().steps.len(), 2);
    apply(&mut d, &op(r#"{"op":"step_remove","id":"a","step":0}"#)).unwrap();
    assert_eq!(d.get("a").unwrap().steps.len(), 2, "the thing itself is never removed as a step");
}

#[test]
fn before_its_first_beat_it_waits_where_that_beat_has_it() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"a","x":0,"y":0}]"#);
    apply(&mut d, &op(r#"{"op":"step_add","id":"a","x":5,"y":0,"beat":4}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"step_set","id":"a","step":0,"beat":3}"#)).unwrap();
    let a = d.get("a").unwrap();
    assert_eq!((a.at_beat(1).0, a.at_beat(3).0, a.at_beat(4).0), (0.0, 0.0, 5.0));
    assert_eq!(d.last_beat(), 4);
}

#[test]
fn a_plan_made_before_steps_reads_in_and_plays_as_it_did() {
    // Beats 2 and 3 as a path, and an A → B that never played.
    let d = plan_with(
        r#"[{"kind":"cast","id":"a","x":0,"y":0,"path":[{"beat":3,"x":3,"y":0},{"beat":2,"x":2,"y":0,"pose":"seated"}],"move":{"x":0,"y":5,"rot":90}},
            {"kind":"camera","id":"c","x":5,"y":0,"move":{"x":0,"y":0,"rot":0,"dir":"from"}},
            {"kind":"camera","id":"t","x":1,"y":1,"rot":0,"move":{"x":5,"y":5,"rot":90,"turn":true}}]"#,
    );
    assert_eq!(seq(&d, "a"), [("A".into(), 1), ("B".into(), 2), ("C".into(), 3), ("D".into(), 0)]);
    let a = d.get("a").unwrap();
    assert_eq!((a.at_beat(2).0, a.at_beat(3).0, a.at_beat(9).0), (2.0, 3.0, 3.0), "the old move does not play");
    assert_eq!(a.pose_at(2), "seated");
    let c = d.get("c").unwrap();
    assert_eq!((c.lead, c.steps[0].x, c.x), (1, 0.0, 5.0), "a Move From comes first");
    assert_eq!(c.at_beat(1).0, 5.0, "and still does not play");
    let t = d.get("t").unwrap();
    assert!(t.steps[0].turn);
    assert_eq!((t.steps[0].x, t.steps[0].y, t.steps[0].rot), (1.0, 1.0, 90.0), "a turn stands where the thing does");
    // Written back as steps, and read again the same.
    let text = d.encode();
    assert!(text.contains("\"steps\"") && !text.contains("\"move\"") && !text.contains("\"path\""), "{text}");
    assert_eq!(Diagram::parse(&text), d);
}

#[test]
fn steps_flip_with_their_thing_are_kept_to_the_plan_and_only_standing_things_take_them() {
    let mut d = plan_with(
        r#"[{"kind":"light","id":"l","x":0,"y":0,"steps":[{"x":2,"y":0,"rot":0,"beat":2}]},
            {"kind":"wall","id":"w","x":0,"y":0,"x2":3,"y2":0,"steps":[{"x":2,"y":0,"beat":2}]}]"#,
    );
    assert!(d.get("w").unwrap().steps.is_empty(), "a wall does not travel");
    apply(&mut d, &op(r#"{"op":"step_add","id":"w"}"#)).unwrap();
    assert!(d.get("w").unwrap().steps.is_empty());
    apply(&mut d, &op(r#"{"op":"flip","ids":["l"],"axis":"x"}"#)).unwrap();
    let e = d.get("l").unwrap();
    assert_eq!((e.x, e.steps[0].x), (0.0, -2.0), "mirrored with it, about its own middle");
    apply(&mut d, &op(r#"{"op":"step_set","id":"l","step":1,"x":1e300,"y":-1e300,"rot":1e9,"beat":1e9}"#)).unwrap();
    let t = d.get("l").unwrap().steps[0];
    assert!(t.x <= FAR && t.y >= -FAR && (0.0..360.0).contains(&t.rot) && t.beat <= MOST_BEATS);
    assert!(apply(&mut d, &op(r#"{"op":"step_set","id":"l","step":9,"x":1}"#)).is_err(), "no such step");
}

#[test]
#[ignore = "lamp beams are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_dimmer_is_kept_per_light_and_fades_its_beam() {
    let mut d = plan_with(r#"[{"kind":"light","id":"k","sym":"fresnel","x":0,"y":0,"beam":40,"reach":3}]"#);
    assert_eq!(d.els[0].dim, 100.0, "a light comes on full");
    assert!(!d.els[0].to_json().encode().contains("\"dim\""), "full is the default, not written");
    let alpha = |d: &Diagram| {
        let mut d = d.clone();
        d.settings.beams = true;
        render::render(&d, &ctx(), &Options::default())
            .iter()
            .find(|s| s.el == "k" && s.part == "beam")
            .map(|s| match &s.fill {
                Ink::Hex(_, a) => *a,
                _ => f64::NAN,
            })
    };
    let full = alpha(&d).expect("a beam at full");
    apply(&mut d, &op(r#"{"op":"update","ids":["k"],"set":{"dim":50}}"#)).unwrap();
    assert_eq!(d.els[0].dim, 50.0);
    assert!((alpha(&d).unwrap() - full / 2.0).abs() < 1e-9, "half the dimmer, half the beam");
    let back = El::from_json(&json::parse(&d.els[0].to_json().encode()).unwrap()).unwrap();
    assert_eq!(back.dim, 50.0, "the dimmer round-trips");
    apply(&mut d, &op(r#"{"op":"update","ids":["k"],"set":{"dim":250}}"#)).unwrap();
    assert_eq!(d.els[0].dim, 100.0, "held to 100");
    apply(&mut d, &op(r#"{"op":"update","ids":["k"],"set":{"dim":-4}}"#)).unwrap();
    assert_eq!(d.els[0].dim, 0.0, "held to 0");
}

#[test]
fn a_character_wears_their_colour_and_a_stranger_stays_grey() {
    // His note, 2026-09-29: "characters should appear their color, not just
    // their tag."
    let d = plan_with(r#"[{"id":"a","kind":"cast","cast":"Anna","label":"Anna","x":1,"y":1},
                         {"id":"b","kind":"cast","cast":"Ben","label":"Ben","x":3,"y":1},
                         {"id":"p","kind":"cast","label":"Cast 3","x":5,"y":1}]"#);
    let c = Context { cast_colours: vec![("anna".into(), "E5484D".into())], cast_ink: "2B6CB0".into(), ..Default::default() };
    let shapes = render::render(&d, &c, &Options::default());
    // On a plot a person is outlined in their colour (2026-10-17: over a
    // paper oval that keeps them readable on any floor).
    let body = |id: &str| shapes.iter().find(|s| s.el == id && s.part == "body" && s.stroke != render::Ink::None).map(|s| s.stroke.clone());
    assert_eq!(body("a"), Some(render::Ink::hex("#E5484D")), "her own colour");
    assert_eq!(body("b"), Some(render::Ink::hex("#2B6CB0")), "the Cast column's colour");
    // A person who is no character: a firm grey since 2026-10-01 (his
    // master list: people were faint at a normal zoom).
    assert_eq!(body("p"), Some(render::Ink::hex(render::PERSON_GREY)), "a person who is no character");
}

// ---- where names land (2026-10-01) ----

/// Each piece's name: its words, its middle, and the box its paper takes,
/// in metres at the plan's opening zoom.
fn names(shapes: &[render::Shape]) -> Vec<(String, String, (f64, f64), (f64, f64, f64, f64))> {
    let k = render::NOMINAL_SCALE;
    shapes
        .iter()
        .filter(|s| s.part == "label")
        .filter_map(|s| match &s.geom {
            // A placed name: its second line, if any, in grey.
            Geom::Text { x, y, text, size, under: Ink::Role("ink2"), .. } => {
                let (w, h) = render::words_box_pt(text, *size);
                let (w, h) = ((w + 2.0 * render::PATCH_PAD) / k, (h + render::PATCH_PAD) / k);
                Some((s.el.clone(), text.clone(), (*x, *y), (x - w / 2.0, y - h / 2.0, x + w / 2.0, y + h / 2.0)))
            }
            _ => None,
        })
        .collect()
}

fn apart(a: (f64, f64, f64, f64), b: (f64, f64, f64, f64)) -> bool {
    a.2 <= b.0 + 1e-6 || b.2 <= a.0 + 1e-6 || a.3 <= b.1 + 1e-6 || b.3 <= a.1 + 1e-6
}

#[test]
fn two_close_lights_do_not_stack_their_names() {
    // His M18 and S60c, 60 cm apart: Scenario stacks them; we do not.
    let d = plan_with(
        r#"[{"kind":"light","id":"m","sym":"fso-arri-m18","x":0,"y":0,"rot":-90,"w":0.5847,"h":0.6096},
            {"kind":"light","id":"s","sym":"fso-arri-s60c","x":0.6,"y":0,"rot":-90,"w":0.8645,"h":0.5918},
            {"kind":"camera","id":"c","x":0,"y":2,"label":"1A"},
            {"kind":"cast","id":"p","x":0.5,"y":2,"label":"MAYA"},
            {"kind":"cast","id":"q","x":0.9,"y":2,"label":"JOHN"}]"#,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let got = names(&shapes);
    assert_eq!(got.len(), 5);
    for (i, a) in got.iter().enumerate() {
        for b in &got[i + 1..] {
            assert!(apart(a.3, b.3), "{} on {}: {:?} {:?}", a.1, b.1, a.3, b.3);
        }
        // …and none on another piece.
        for e in d.els.iter().filter(|e| e.id != a.0) {
            let pb = super::aabb(e);
            let inset = (pb.x1 + 0.02, pb.y1 + 0.02, pb.x2 - 0.02, pb.y2 - 0.02);
            assert!(apart(a.3, inset), "{} on {}", a.1, e.id);
        }
    }
    // A name moved off its spot under its piece says how far.
    assert!(shapes.iter().any(|s| s.part == "label" && matches!(s.geom, Geom::Text { shift, .. } if shift != (0.0, 0.0))));
    // Closer in, the words are smaller on the plan, and the M18's name has
    // room under it again.
    let near = render::render(&d, &Context::default(), &Options { scale: 240.0, ..Default::default() });
    assert!(near.iter().any(|s| s.el == "m" && matches!(s.geom, Geom::Text { shift, .. } if shift == (0.0, 0.0))));
}

#[test]
fn a_dragged_name_keeps_its_offset_and_a_thin_line_back() {
    let mut d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"label":"1A"}]"#);
    let tie = |d: &Diagram| render::render(d, &Context::default(), &Options::default()).into_iter().any(|s| s.el == "c" && s.part == "tie");
    assert!(!tie(&d), "next to it: no line");
    d.get_mut("c").unwrap().label_dx = 0.04;
    assert!(!tie(&d), "nudged a little: still none");
    d.get_mut("c").unwrap().label_dx = 1.2;
    d.get_mut("c").unwrap().label_dy = 0.8;
    assert!(tie(&d), "away from it: tied back");
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let Some(Geom::Path(p)) = shapes.iter().find(|s| s.part == "tie").map(|s| s.geom.clone()) else { panic!() };
    let render::Seg::M(x, y) = p[0] else { panic!() };
    let half = d.get("c").unwrap().w.max(d.get("c").unwrap().h) / 2.0;
    assert!(x.abs() <= half + 1e-6 && y.abs() <= half + 1e-6, "starts at the camera's outline");
}

#[test]
fn every_grip_piece_and_frame_is_named() {
    let d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"generic-frame","x":0,"y":0,"w":1.83,"h":1.83},
            {"kind":"light","id":"b","sym":"fso-6x6-lcd","x":4,"y":0,"w":1.83,"h":1.83},
            {"kind":"light","id":"c","sym":"frame","x":8,"y":0,"tilt":0,"h":2.44,"tall":2.44}]"#,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let got = names(&shapes);
    let words: Vec<&str> = got.iter().map(|n| n.1.as_str()).collect();
    assert!(words.contains(&"OVERHEAD FRAME") && words.contains(&"6X6 LCD"), "{words:?}");
    assert!(got.iter().any(|n| n.0 == "c"), "the frame is named");
}

#[test]
fn a_name_on_paper_has_no_plate_only_a_halo() {
    // Back to Paper (2026-10-04): no box behind a name; a thin halo of
    // paper so the wall it crosses breaks round it; regular weight.
    let d = plan_with(r#"[{"kind":"wall","x":-2,"y":0.4,"x2":2,"y2":0.4},{"kind":"light","id":"l","sym":"fresnel","x":0,"y":0,"w":0.3,"h":0.3,"label":"Key"}]"#);
    let svg = super::svg::svg(&d, &Context::default(), &Options::default(), &super::svg::Frame::default(), "t");
    assert!(!svg.contains("--dia-patch"), "no plate: {svg}");
    let at = svg.find(r#"data-el="l" data-part="label""#).expect("named");
    let tag = &svg[svg[..at].rfind("<text").unwrap()..at];
    assert!(tag.contains("paint-order:stroke"), "a halo: {tag}");
    assert!(!tag.contains("font-weight:600"), "regular weight: {tag}");
    assert!(svg.contains(".dia text{font-weight:400}"));
    // Its second line, the note, in grey.
    assert!(svg.contains(r#"<tspan x="#) && svg.contains(r#" style="fill:var(--d-ink2)">KEY</tspan>"#), "{svg}");
}

#[test]
fn switching_units_switches_the_grid() {
    let mut d = Diagram::default();
    assert!((d.settings.step - FOOT).abs() < 1e-12);
    apply(&mut d, &op(r#"{"op":"settings","set":{"units":"m"}}"#)).unwrap();
    assert_eq!(d.settings.step, 0.5, "half a metre in metres");
    apply(&mut d, &op(r#"{"op":"settings","set":{"units":"ft"}}"#)).unwrap();
    assert!((d.settings.step - FOOT).abs() < 1e-12, "a foot in feet");
    apply(&mut d, &op(r#"{"op":"settings","set":{"units":"m","step":0.1}}"#)).unwrap();
    assert_eq!(d.settings.step, 0.1, "a step named with the switch is kept");
    apply(&mut d, &op(r#"{"op":"settings","set":{"dims":false}}"#)).unwrap();
    assert_eq!(d.settings.step, 0.1, "any other setting leaves the step alone");
}

#[test]
fn a_point_snaps_to_the_step_it_is_given() {
    let d = Diagram::default();
    let ((x, y), caught) = snap_point_to(&d, 0.37, 0.12, 0.01, &[], 0.5);
    assert!(!caught);
    assert_eq!((x, y), (0.5, 0.0));
    let ((x, _), _) = snap_point(&d, 0.37, 0.12, 0.01, &[]);
    assert!((x - FOOT).abs() < 1e-12);
}

#[test]
fn a_member_picked_alone_moves_and_turns_without_its_group() {
    let mut d = plan_with(r#"[{"id":"a","kind":"set","sym":"box","x":0,"y":0},{"id":"b","kind":"set","sym":"box","x":2,"y":0}]"#);
    apply(&mut d, &op(r#"{"op":"group","ids":["a","b"]}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"move","ids":["a"],"dx":1,"dy":0,"alone":true}"#)).unwrap();
    assert_eq!((d.get("a").unwrap().x, d.get("b").unwrap().x), (1.0, 2.0));
    apply(&mut d, &op(r#"{"op":"rotate","ids":["a"],"deg":90,"alone":true}"#)).unwrap();
    assert_eq!((d.get("a").unwrap().rot, d.get("b").unwrap().rot), (90.0, 0.0));
    apply(&mut d, &op(r#"{"op":"move","ids":["a"],"dx":1,"dy":0}"#)).unwrap();
    assert_eq!((d.get("a").unwrap().x, d.get("b").unwrap().x), (2.0, 3.0), "without it, the group goes too");
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["a"],"dx":0,"dy":1,"alone":true}"#)).unwrap();
    assert_eq!(made.len(), 1, "only the one member is copied");
    assert_eq!(d.get(&made[0]).unwrap().group, d.get("a").unwrap().group, "and the copy stays in its group");
}

#[test]
fn a_group_turned_about_a_grid_point_keeps_its_walls_on_the_grid() {
    let f = FOOT;
    let mut d = plan_with(&format!(
        r#"[{{"id":"w1","kind":"wall","x":0,"y":0,"x2":{a},"y2":0}},{{"id":"w2","kind":"wall","x":{a},"y":0,"x2":{a},"y2":{b}}}]"#,
        a = 11.0 * f,
        b = 8.0 * f
    ));
    apply(&mut d, &op(r#"{"op":"group","ids":["w1","w2"]}"#)).unwrap();
    apply(&mut d, &op(&format!(r#"{{"op":"rotate","ids":["w1"],"deg":90,"px":{},"py":{}}}"#, 6.0 * f, 4.0 * f))).unwrap();
    for e in &d.els {
        for v in [e.x, e.y, e.x2, e.y2] {
            let k = v / f;
            assert!((k - k.round()).abs() < 1e-9, "{} off the grid: {v}", e.id);
        }
    }
}

// ---------------------------------------------------------------- pinned arrows (SL-1231)

fn pinned_plan() -> Diagram {
    // A note with three arrows fanning to a sofa, a person and a lamp.
    let mut d = plan_with(
        r#"[{"kind":"note","id":"n","x":0,"y":0,"text":"Hide the tubes"},
            {"kind":"set","id":"s","sym":"sofa","x":4,"y":0,"w":2,"h":1},
            {"kind":"cast","id":"p","x":0,"y":4},
            {"kind":"light","id":"l","x":-3,"y":-3}]"#,
    );
    for (i, to) in ["s", "p", "l"].iter().enumerate() {
        apply(&mut d, &op(&format!(r#"{{"op":"add","els":[{{"kind":"arrow","id":"a{i}","x":0,"y":0,"x2":1,"y2":1,"start_on":"n","end_on":"{to}"}}]}}"#))).unwrap();
    }
    d
}

#[test]
fn a_pinned_arrow_runs_from_outline_to_outline() {
    let d = pinned_plan();
    let a = d.get("a0").unwrap();
    assert_eq!((a.start_on.as_str(), a.end_on.as_str()), ("n", "s"));
    // The sofa is 2 m long about x 4: its near edge is at 3, the head a hair short of it.
    assert!((a.x2 - (3.0 - PIN_GAP)).abs() < 1e-6 && a.y2.abs() < 1e-6, "head at the sofa's edge: {},{}", a.x2, a.y2);
    // …and the tail leaves the note's outline, not its middle.
    assert!(a.x > 0.19 && a.x < 0.3 && a.y.abs() < 1e-6, "{},{}", a.x, a.y);
    // A person is round: straight down, across the shoulders, the head stops at their side.
    let b = d.get("a1").unwrap();
    assert!(b.x2.abs() < 1e-6 && (b.y2 - (4.0 - 0.23 - PIN_GAP)).abs() < 1e-6, "{},{}", b.x2, b.y2);
    let c = d.get("a2").unwrap();
    assert!(c.x2 > -3.0 && c.y2 > -3.0 && c.x2 < -2.7, "toward the note from the lamp: {},{}", c.x2, c.y2);
}

#[test]
fn a_pinned_arrow_follows_the_piece_and_lets_go_when_dragged_off() {
    let mut d = pinned_plan();
    apply(&mut d, &op(r#"{"op":"move","ids":["s"],"dx":0,"dy":3}"#)).unwrap();
    let a = d.get("a0").unwrap();
    assert_eq!(a.end_on, "s", "still pinned");
    assert!(a.y2 > 2.0 && (a.x2 - 4.0).hypot(a.y2 - 3.0) < 1.2, "followed the sofa: {},{}", a.x2, a.y2);
    // The note moves: all three tails go with it.
    apply(&mut d, &op(r#"{"op":"move","ids":["n"],"dx":-1,"dy":0}"#)).unwrap();
    assert!(["a0", "a1", "a2"].iter().all(|id| d.get(id).unwrap().x < 0.0), "every tail followed the note");
    // His end dragged away from the sofa: the end is where he left it, free.
    apply(&mut d, &op(r#"{"op":"update","id":"a0","set":{"x2":8,"y2":8}}"#)).unwrap();
    let a = d.get("a0").unwrap();
    assert_eq!((a.end_on.as_str(), a.x2, a.y2), ("", 8.0, 8.0));
    assert_eq!(a.start_on, "n", "the other end stays pinned");
    // Dropped on the person instead: pinned there.
    apply(&mut d, &op(r#"{"op":"update","id":"a0","set":{"x2":0,"y2":4,"end_on":"p"}}"#)).unwrap();
    assert_eq!(d.get("a0").unwrap().end_on, "p");
    // The whole arrow dragged: both ends let go, the arrow where it was put.
    let before = d.get("a1").unwrap().clone();
    apply(&mut d, &op(r#"{"op":"move","ids":["a1"],"dx":5,"dy":0}"#)).unwrap();
    let a = d.get("a1").unwrap();
    assert!(a.start_on.is_empty() && a.end_on.is_empty());
    assert!((a.x - before.x - 5.0).abs() < 1e-9);
    // The piece taken away: the pin lets go and the end stays put.
    let end = (d.get("a2").unwrap().x2, d.get("a2").unwrap().y2);
    apply(&mut d, &op(r#"{"op":"remove","ids":["l"]}"#)).unwrap();
    let a = d.get("a2").unwrap();
    assert!(a.end_on.is_empty() && (a.x2, a.y2) == end);
}

#[test]
fn a_copied_arrow_keeps_pins_only_to_what_came_with_it() {
    let mut d = pinned_plan();
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["a0"]}"#)).unwrap();
    let c = d.get(&made[0]).unwrap();
    assert!(c.start_on.is_empty() && c.end_on.is_empty(), "loose: {c:?}");
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["a0","s"]}"#)).unwrap();
    let arrow = made.iter().find(|id| d.get(id).unwrap().kind == Kind::Arrow).unwrap();
    let sofa = made.iter().find(|id| d.get(id).unwrap().kind == Kind::Set).unwrap();
    let copy = d.get(arrow).unwrap();
    assert_eq!(&copy.end_on, sofa, "pinned to the copied sofa");
    assert!(copy.start_on.is_empty());
}

#[test]
fn a_pinned_arrow_round_trips() {
    let d = pinned_plan();
    assert_eq!(Diagram::parse(&d.encode()), d);
}

// ---------------------------------------------------------------- camera bodies (SL-1217)

#[test]
fn a_camera_shows_the_body_it_is_given_at_its_own_size() {
    let mut d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"lens":35}]"#);
    let bodies = symbols::camera_bodies();
    assert!(bodies.len() >= 13 && bodies.iter().any(|b| b.0 == "fso-sony-venice"), "{bodies:?}");
    apply(&mut d, &op(r#"{"op":"swap","ids":["c"],"sym":"fso-red-komodo"}"#)).unwrap();
    let c = d.get("c").unwrap();
    assert_eq!((c.kind, c.sym.as_str(), c.lens), (Kind::Camera, "fso-red-komodo", 35.0));
    assert!(c.w < 0.25 && c.h < 0.25, "a Komodo is small: {}x{}", c.w, c.h);
    // A lamp is not a camera body: nothing happens.
    apply(&mut d, &op(r#"{"op":"swap","ids":["c"],"sym":"fresnel-2k"}"#)).unwrap();
    assert_eq!(d.get("c").unwrap().kind, Kind::Camera);
    assert!(wire::library().contains(r#""cameras":[{"id":"fso-arri-alexa-mini-lf""#));
}

// ---------------------------------------------------------------- distance on an aim (SL-1318)

#[test]
fn a_picked_camera_aimed_at_a_person_writes_the_distance_on_its_aim_line() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"p","x":3.048,"y":0},{"kind":"camera","id":"c","x":0,"y":0,"aim":"p"},{"kind":"light","id":"l","x":0,"y":1.524,"aim":"p"}]"#);
    d.settings.units = "ft".into();
    let words = |d: &Diagram, sel: &[&str]| -> Vec<String> {
        let opt = Options { sel: sel.iter().map(|s| s.to_string()).collect(), ..Default::default() };
        render::render(d, &ctx(), &opt)
            .into_iter()
            .filter(|s| s.part == "aim")
            .filter_map(|s| match s.geom {
                Geom::Text { text, patch, .. } => patch.then_some(text),
                _ => None,
            })
            .collect()
    };
    assert_eq!(words(&d, &["c"]), vec!["10 FT".to_string()]);
    assert_eq!(words(&d, &["l"]).len(), 1, "a lamp on its subject too");
    assert!(words(&d, &[]).is_empty(), "only for what is picked");
    d.settings.units = "m".into();
    assert_eq!(words(&d, &["c"]), vec!["3.05 M".to_string()]);
}

#[test]
fn a_copy_put_at_a_point_has_its_middle_there_and_keeps_its_aim() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"p","x":4,"y":0},{"kind":"light","id":"l","sym":"generic-fresnel","x":0,"y":0,"aim":"p"}]"#);
    // Both copied: the lamp's copy aims at the person's copy.
    let made = apply(&mut d, &op(r#"{"op":"duplicate","ids":["p","l"],"x":10,"y":10}"#)).unwrap();
    assert_eq!(made.len(), 2);
    let (mx, my) = middle_of(&d, &made);
    assert!((mx - 10.0).abs() < 1e-9 && (my - 10.0).abs() < 1e-9, "{mx},{my}");
    let lamp = d.els.iter().find(|e| made.contains(&e.id) && e.kind == Kind::Light).unwrap();
    let who = d.els.iter().find(|e| made.contains(&e.id) && e.kind == Kind::Cast).unwrap();
    assert_eq!(lamp.aim, who.id);
    // The lamp alone: its copy aims at the same person the original does.
    let one = apply(&mut d, &op(r#"{"op":"duplicate","ids":["l"],"dx":1,"dy":0}"#)).unwrap();
    assert_eq!(d.get(&one[0]).unwrap().aim, "p");
}

#[test]
fn a_paste_of_what_is_still_there_gets_new_ids_and_its_aim_follows() {
    let mut d = plan_with(r#"[{"kind":"cast","id":"p","x":4,"y":0},{"kind":"light","id":"l","sym":"generic-fresnel","x":0,"y":0,"aim":"p"}]"#);
    let made = apply(
        &mut d,
        &op(r#"{"op":"add","els":[{"kind":"cast","id":"p","x":4,"y":5},{"kind":"light","id":"l","sym":"generic-fresnel","x":0,"y":5,"aim":"p"}]}"#),
    )
    .unwrap();
    assert_eq!(made.len(), 2);
    assert!(!made.contains(&"p".to_string()) && !made.contains(&"l".to_string()), "{made:?}");
    assert_eq!(d.get(&made[1]).unwrap().aim, made[0]);
    assert_eq!(d.get("l").unwrap().aim, "p", "the original is untouched");
}

#[test]
#[ignore = "lamp beams are off for now (render::LAMP_BEAMS, his call 2026-10-01)"]
fn a_picked_lamp_shows_its_beam_and_spread_with_beams_off() {
    let d = plan_with(r#"[{"kind":"light","id":"l","sym":"generic-fresnel","x":0,"y":0,"beam":40,"reach":4,"dim":50}]"#);
    assert!(!d.settings.beams, "beams are off for a new film");
    let unpicked = render::render(&d, &ctx(), &Options::default());
    assert!(!unpicked.iter().any(|s| s.part == "beamline" || s.part == "beamnote" || s.part == "beam"));
    let picked = render::render(&d, &ctx(), &Options { sel: vec!["l".into()], ..Default::default() });
    let line = picked.iter().find(|s| s.el == "l" && s.part == "beamline").expect("its beam's edges");
    assert_eq!(line.dash, "dot");
    let note = picked.iter().find(|s| s.el == "l" && s.part == "beamnote").expect("its spread and dimmer");
    assert!(matches!(&note.geom, Geom::Text { text, .. } if text == "40° · 50%"), "{:?}", note.geom);
    // On paper, nothing picked shows.
    let paper = render::render(&d, &ctx(), &Options { sel: vec!["l".into()], paper: true, ..Default::default() });
    assert!(!paper.iter().any(|s| s.part == "beamline"));
}

#[test]
fn a_pasted_arrow_keeps_pins_only_to_what_was_pasted_with_it() {
    let mut d = pinned_plan();
    let raw = |d: &Diagram, ids: &[&str]| -> String {
        let items: Vec<String> = ids.iter().map(|id| d.get(id).unwrap().to_json().encode()).collect();
        format!(r#"{{"op":"add","els":[{}]}}"#, items.join(","))
    };
    let one = op(&raw(&d, &["a0"]));
    let made = apply(&mut d, &one).unwrap();
    let c = d.get(&made[0]).unwrap();
    assert!(c.start_on.is_empty() && c.end_on.is_empty(), "loose: {c:?}");
    let two = op(&raw(&d, &["a0", "s"]));
    let made = apply(&mut d, &two).unwrap();
    let arrow = made.iter().find(|id| d.get(id).unwrap().kind == Kind::Arrow).unwrap();
    let sofa = made.iter().find(|id| d.get(id).unwrap().kind == Kind::Set).unwrap();
    assert_eq!(&d.get(arrow).unwrap().end_on, sofa);
}

// ---------------------------------------------------------------- walls as one line (master list 3)

fn wall_of(d: &Diagram, id: &str) -> Vec<(f64, f64)> {
    walls::corners(d.get(id).unwrap())
}

fn near(a: (f64, f64), b: (f64, f64)) -> bool {
    (a.0 - b.0).abs() < 1e-6 && (a.1 - b.1).abs() < 1e-6
}

#[test]
fn a_wall_line_keeps_its_corners_and_a_plain_wall_stays_as_it_was_written() {
    let d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true,"round":[2]},{"id":"w","kind":"wall","x":0,"y":5,"x2":4,"y2":5}]"#);
    let r = d.get("r").unwrap();
    assert_eq!(walls::corners(r).len(), 4);
    assert!(walls::closed(r) && r.round == vec![2]);
    assert_eq!((r.x, r.y, r.x2, r.y2), (0.0, 0.0, 0.0, 3.0), "its ends are its first and last corner");
    let text = d.encode();
    let back = Diagram::parse(&text);
    assert_eq!(back, d, "{text}");
    let plain = d.get("w").unwrap().to_json().encode();
    assert!(!plain.contains("points") && !plain.contains("closed"), "{plain}");
    // A closed room's line runs back to where it began, its round corner a curve.
    let run = walls::run(r);
    assert!(near(run[0], run[run.len() - 1]));
    assert!(run.len() > 10, "the rounded corner is drawn as a curve");
    assert!((d.get("w").unwrap().len() - 4.0).abs() < 1e-9);
}

#[test]
fn a_corner_is_added_grown_on_moved_rounded_and_taken_out() {
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","x":0,"y":0,"x2":4,"y2":0}]"#);
    apply(&mut d, &op(r#"{"op":"wall_insert","id":"w","stretch":0}"#)).unwrap();
    assert_eq!(wall_of(&d, "w"), vec![(0.0, 0.0), (2.0, 0.0), (4.0, 0.0)]);
    apply(&mut d, &op(r#"{"op":"wall_extend","id":"w","end":"end","x":4,"y":3}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"wall_extend","id":"w","end":"start","x":0,"y":-1}"#)).unwrap();
    assert_eq!(wall_of(&d, "w"), vec![(0.0, -1.0), (0.0, 0.0), (2.0, 0.0), (4.0, 0.0), (4.0, 3.0)]);
    apply(&mut d, &op(r#"{"op":"wall_corner","id":"w","corner":2,"x":2,"y":1}"#)).unwrap();
    assert!(near(wall_of(&d, "w")[2], (2.0, 1.0)), "the stretches either side follow: they run to it");
    apply(&mut d, &op(r#"{"op":"wall_round","id":"w","corner":2,"round":true}"#)).unwrap();
    assert_eq!(d.get("w").unwrap().round, vec![2]);
    apply(&mut d, &op(r#"{"op":"wall_remove_corner","id":"w","corner":0}"#)).unwrap();
    assert_eq!(d.get("w").unwrap().round, vec![1], "a rounded corner keeps its roundness as the count shifts");
    assert_eq!(wall_of(&d, "w").len(), 4);
}

#[test]
fn a_break_opens_a_door_wide_gap() {
    // A closed room, in feet: opened at its first corner.
    let mut d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true}]"#);
    apply(&mut d, &op(r#"{"op":"wall_break","id":"r","corner":0}"#)).unwrap();
    let r = d.get("r").unwrap();
    assert!(!walls::closed(r));
    let c = walls::corners(r);
    assert_eq!(c.len(), 5);
    assert!(near(c[0], (1.5 * FOOT, 0.0)) && near(c[4], (0.0, 1.5 * FOOT)), "{c:?}");
    // An open wall broken at a corner it has inserted mid-stretch: two walls,
    // a three-foot gap between them.
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","x":0,"y":0,"x2":6,"y2":0}]"#);
    apply(&mut d, &op(r#"{"op":"wall_insert","id":"w","stretch":0}"#)).unwrap();
    let made = apply(&mut d, &op(r#"{"op":"wall_break","id":"w","corner":1}"#)).unwrap();
    assert_eq!(made.len(), 1);
    let (a, b) = (wall_of(&d, "w"), wall_of(&d, &made[0]));
    assert!((b[0].0 - a[a.len() - 1].0 - 3.0 * FOOT).abs() < 1e-6, "{a:?} {b:?}");
}

#[test]
fn a_stretch_given_a_length_moves_its_far_corner_and_a_room_measures_inside() {
    let mut d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true,"thick":0.2}]"#);
    let r = d.get("r").unwrap();
    assert!((walls::shown_length(r, 0) - 3.8).abs() < 1e-9, "inside: 4 less a wall's thickness");
    apply(&mut d, &op(r#"{"op":"wall_length","id":"r","stretch":0,"length":5}"#)).unwrap();
    let c = wall_of(&d, "r");
    assert!(near(c[1], (5.2, 0.0)) && near(c[2], (5.2, 3.0)), "the far side moves out whole: {c:?}");
    assert!((walls::shown_length(d.get("r").unwrap(), 0) - 5.0).abs() < 1e-9);
    // An open wall: the corners past it ride along.
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","points":[[0,0],[2,0],[2,2]]}]"#);
    apply(&mut d, &op(r#"{"op":"wall_length","id":"w","stretch":0,"length":3}"#)).unwrap();
    assert_eq!(wall_of(&d, "w"), vec![(0.0, 0.0), (3.0, 0.0), (3.0, 2.0)]);
}

#[test]
fn a_corner_joined_to_another_wall_goes_with_it_unless_pulled_free() {
    // A T: the stem's end on the middle of the long wall; and an L of two
    // separate walls sharing a corner.
    let mut d = plan_with(r#"[{"id":"a","kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"id":"t","kind":"wall","x":2,"y":0,"x2":2,"y2":3},{"id":"l","kind":"wall","x":4,"y":0,"x2":4,"y2":-3}]"#);
    apply(&mut d, &op(r#"{"op":"move","ids":["a"],"dx":0,"dy":1}"#)).unwrap();
    assert!(near(wall_of(&d, "t")[0], (2.0, 1.0)), "the T stays on the wall: {:?}", wall_of(&d, "t"));
    assert!(near(wall_of(&d, "t")[1], (2.0, 3.0)), "its far end stays");
    assert!(near(wall_of(&d, "l")[0], (4.0, 1.0)), "the corner it shares goes with it");
    // A corner dragged: what meets there follows; pulled free, nothing does.
    apply(&mut d, &op(r#"{"op":"wall_corner","id":"a","corner":1,"x":5,"y":1}"#)).unwrap();
    assert!(near(wall_of(&d, "l")[0], (5.0, 1.0)));
    apply(&mut d, &op(r#"{"op":"wall_corner","id":"a","corner":1,"x":6,"y":1,"free":true}"#)).unwrap();
    assert!(near(wall_of(&d, "l")[0], (5.0, 1.0)));
    // The T's host stretched along its own line: the T keeps its place on it.
    let t = wall_of(&d, "t")[0];
    assert!(walls::nearest_on(d.get("a").unwrap(), t).unwrap().1 < 1e-9);
}

#[test]
fn a_door_rides_its_stretch_of_a_wall_line() {
    let mut d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true},{"id":"door","kind":"door","x":4,"y":1.5,"rot":90}]"#);
    // The right side pulled out a metre: its door goes with it.
    apply(&mut d, &op(r#"{"op":"wall_length","id":"r","stretch":0,"length":5}"#)).unwrap();
    let door = d.get("door").unwrap();
    let x = wall_of(&d, "r")[1].0;
    assert!((door.x - x).abs() < 1e-9 && (door.y - 1.5).abs() < 1e-9, "{},{}", door.x, door.y);
    // A corner added elsewhere leaves it be.
    apply(&mut d, &op(r#"{"op":"wall_insert","id":"r","stretch":2}"#)).unwrap();
    assert!((d.get("door").unwrap().x - x).abs() < 1e-9);
}

#[test]
fn a_corner_lines_up_with_other_corners_lands_on_a_wall_and_closes_a_room() {
    let d = plan_with(r#"[{"id":"w","kind":"wall","points":[[0,0],[4,0],[4,3]]}]"#);
    // Near level with the third corner and under the first: square to both.
    let s = walls::snap(&d, 0.07, 2.93, 0.1, 0.3048, &[], None);
    assert!(near(s.at, (0.0, 3.0)) && s.guides.len() == 2 && !s.caught, "{s:?}");
    // Near the middle of a stretch: dead on its line, and on the grid along it.
    let s = walls::snap(&d, 2.03, 0.06, 0.1, 0.3048, &[], None);
    assert!(near(s.at, (7.0 * 0.3048, 0.0)) && s.caught, "{s:?}");
    // On a corner.
    let s = walls::snap(&d, 0.04, 0.03, 0.1, 0.3048, &[], None);
    assert!(near(s.at, (0.0, 0.0)) && s.caught);
    // Dragging its own corner: that corner is no target.
    let s = walls::snap(&d, 4.02, 2.98, 0.1, 0.0, &[], Some(("w", 2)));
    assert!(near(s.at, (4.0, 2.98)), "lined up with its neighbour above it: {s:?}");
}

#[test]
fn a_door_steps_from_the_nearer_corner_by_the_grid() {
    let f = FOOT;
    let d = plan_with(&format!(r#"[{{"id":"r","kind":"wall","points":[[0,0],[{w},0],[{w},{h}],[0,{h}]],"closed":true}}]"#, w = 12.0 * f, h = 10.0 * f));
    // A three-foot door dropped a little over three feet along the top wall.
    let at = walls::in_wall(&d, 4.9 * f, 0.1, 0.5, 3.0 * f, f).unwrap();
    assert!((at.from - 3.0 * f).abs() < 1e-9, "three feet from the corner's face: {}", at.from / f);
    // Its middle: a half-thickness face, three feet, then half the door.
    assert!((at.x - (0.25 * f + 3.0 * f + 1.5 * f)).abs() < 1e-9 && at.y.abs() < 1e-9);
    assert!(near(at.face, (0.25 * f, 0.0)));
}

#[test]
fn walls_that_meet_end_to_end_join_into_one_and_an_end_told_where_to_go_moves_its_corner() {
    let mut d = plan_with(r#"[{"id":"a","kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"id":"b","kind":"wall","x":4,"y":3,"x2":4,"y2":0},{"id":"c","kind":"wall","x":4,"y":3,"x2":0,"y2":3},{"id":"e","kind":"wall","x":0,"y":3,"x2":0,"y2":0}]"#);
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["a","b","c","e"]}"#)).unwrap();
    assert_eq!(d.els.len(), 1);
    let a = d.get("a").unwrap();
    assert!(walls::closed(a));
    assert_eq!(walls::corners(a), vec![(0.0, 0.0), (4.0, 0.0), (4.0, 3.0), (0.0, 3.0)]);
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","points":[[0,0],[2,0],[2,2]]}]"#);
    apply(&mut d, &op(r#"{"op":"update","id":"w","set":{"x2":3,"y2":2}}"#)).unwrap();
    assert_eq!(wall_of(&d, "w"), vec![(0.0, 0.0), (2.0, 0.0), (3.0, 2.0)]);
}

#[test]
fn a_box_drawn_inside_a_room_does_not_catch_its_walls() {
    let d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true},{"id":"c","kind":"set","sym":"chair","x":2,"y":1.5}]"#);
    assert_eq!(within(&d, Aabb { x1: 1.0, y1: 1.0, x2: 3.0, y2: 2.0 }), vec!["c".to_string()]);
    assert_eq!(within(&d, Aabb { x1: 1.0, y1: -0.5, x2: 3.0, y2: 0.5 }), vec!["r".to_string()], "across its top stretch");
}

/// **Lamps throw no light for now; the sun still does** (his call,
/// 2026-10-01). A lamp with its beam on, Beams and Levels on, draws no beam,
/// no beam line and no ring — and keeps every beam setting it had.
#[test]
fn lamps_throw_no_beam_for_now_and_keep_their_settings() {
    let mut d = plan_with(r#"[{"kind":"light","id":"l","sym":"fso-arri-m18","x":0,"y":0,"rot":0,"beam":40,"reach":6,"beam_on":true,"dim":50}]"#);
    d.settings.beams = true;
    d.settings.levels = true;
    let mut opt = Options::default();
    opt.sel = vec!["l".to_string()];
    let shapes = render::render(&d, &ctx(), &opt);
    assert!(!shapes.iter().any(|s| matches!(s.part, "beam" | "beamline" | "beamnote" | "level")), "no lamp light drawn");
    let l = d.els.iter().find(|e| e.id == "l").unwrap();
    assert_eq!((l.beam, l.reach, l.beam_on, l.dim), (40.0, 6.0, true, 50.0), "its settings are kept");
}

#[test]
fn a_camera_reads_its_shots_camera_and_lens() {
    // His design, 2026-10-01: the film's camera carries the sensor he typed;
    // a camera on the plan is its shot and reads both off it.
    let lf = super::lens::Gate { id: "u1".into(), name: "Alexa Mini LF Open Gate".into(), w: 36.70, h: 25.54 };
    let c = Context {
        shots: vec![("s1".into(), "1A".into(), "Signature Prime 50mm".into())],
        units: vec![("u1".into(), "A-Cam".into(), Some(lf)), ("u2".into(), "B-Cam".into(), None)],
        shot_units: vec![("s1".into(), "u1".into())],
        ..Default::default()
    };
    let d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"shot":"s1"}]"#);
    let o = render::camera_optics(d.get("c").unwrap(), &c);
    assert_eq!((o.unit_label.as_str(), o.gate.name.as_str(), o.sensor_set), ("A-Cam", "Alexa Mini LF Open Gate", true));
    assert!((o.aov - 40.3).abs() < 0.05, "{}", o.aov);

    // A camera with no sensor of its own reads Super 35, and says so.
    let c2 = Context { shot_units: vec![("s1".into(), "u2".into())], ..c.clone() };
    let o = render::camera_optics(d.get("c").unwrap(), &c2);
    assert_eq!((o.gate.id.as_str(), o.sensor_set), ("s35", false));

    // A zoom is set by the shot's focal length, held inside its range.
    let z = Context { shots: vec![("s1".into(), "1A".into(), "24-70mm".into())], shot_focals: vec![("s1".into(), 35.0)], ..c.clone() };
    let o = render::camera_optics(d.get("c").unwrap(), &z);
    assert_eq!((o.zoom, o.focal), (Some((24.0, 70.0)), 35.0));
    let z = Context { shot_focals: vec![("s1".into(), 200.0)], ..z };
    assert_eq!(render::camera_optics(d.get("c").unwrap(), &z).focal, 70.0);
    let z = Context { shot_focals: vec![], ..z };
    assert_eq!(render::camera_optics(d.get("c").unwrap(), &z).focal, 24.0, "unset, its wide end");

    // A 2× anamorphic in the Lens doubles the width it sees.
    let a = Context { shots: vec![("s1".into(), "1A".into(), "Hawk 2x 50mm".into())], ..c.clone() };
    let o = render::camera_optics(d.get("c").unwrap(), &a);
    assert_eq!(o.squeeze, 2.0);
    assert!((o.aov - 2.0 * (36.70f64 * 2.0 / 100.0).atan().to_degrees()).abs() < 0.05);
}

#[test]
fn a_camera_with_no_shot_picks_a_film_camera_and_a_lens_off_the_list() {
    let lf = super::lens::Gate { id: "u1".into(), name: "LF".into(), w: 36.70, h: 25.54 };
    let c = Context { units: vec![("u1".into(), "A-Cam".into(), Some(lf))], ..Default::default() };
    let d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"unit":"u1","lens_name":"Hawk V-Lite 2x 40mm"}]"#);
    let o = render::camera_optics(d.get("c").unwrap(), &c);
    assert_eq!((o.unit_label.as_str(), o.focal, o.squeeze), ("A-Cam", 40.0, 2.0));
    // On a zoom, its own focal length is the slider's.
    let d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"lens_name":"24-70mm","lens":50}]"#);
    assert_eq!(render::camera_focal(d.get("c").unwrap(), &c), 50.0);
    let d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"lens_name":"Tribe7 Blackwings 50"}]"#);
    assert_eq!(render::camera_focal(d.get("c").unwrap(), &c), 50.0);
}

#[test]
fn a_shape_or_an_arrow_name_pulled_away_points_back() {
    let mut d = plan_with(
        r#"[{"kind":"shape","id":"s","x":0,"y":0,"w":2,"h":1.5,"label":"Video Village"},
            {"kind":"arrow","id":"a","x":5,"y":0,"x2":9,"y2":0,"label":"Truck"}]"#,
    );
    let ties = |d: &Diagram| -> Vec<Shape> {
        render::render(d, &Context::default(), &Options::default()).into_iter().filter(|s| s.part == "tie").collect()
    };
    assert!(ties(&d).is_empty(), "where they were put: no lines");
    d.get_mut("s").unwrap().label_dx = 0.3;
    assert!(ties(&d).is_empty(), "moved about inside its shape: none");
    d.get_mut("s").unwrap().label_dx = 3.0;
    d.get_mut("s").unwrap().label_dy = -2.0;
    d.get_mut("a").unwrap().label_dy = -1.5;
    let t = ties(&d);
    let from = |id: &str| -> (f64, f64) {
        let Some(Geom::Path(p)) = t.iter().find(|s| s.el == id).map(|s| s.geom.clone()) else { panic!("{id} is tied back") };
        let Seg::M(x, y) = p[0] else { panic!() };
        (x, y)
    };
    let (x, y) = from("s");
    assert!(x <= 1.0 + 1e-6 && y >= -0.75 - 1e-6 && (x - 1.0).abs().min((y + 0.75).abs()) < 1e-6, "starts on the shape's edge: {x},{y}");
    let (x, y) = from("a");
    assert!((5.0..=9.0).contains(&x) && y.abs() < 1e-6, "starts on the arrow: {x},{y}");
}

#[test]
fn opacity_fades_a_piece_but_not_its_name() {
    let d = plan_with(
        r#"[{"kind":"light","id":"l","sym":"fso-litemat-8","x":0,"y":0,"w":1.08,"h":1.05,"label":"Overhead","opacity":0.3},
            {"kind":"shape","id":"s","x":5,"y":0,"w":2,"h":1.5,"label":"Rug","opacity":0.3}]"#,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    for id in ["l", "s"] {
        let label = shapes.iter().find(|s| s.el == id && s.part == "label").expect("named");
        assert!((label.alpha - 1.0).abs() < 1e-9, "{id}'s name stays whole: {}", label.alpha);
    }
    let body = shapes.iter().find(|s| s.el == "s" && s.part == "body").expect("drawn");
    assert!((body.alpha - 0.3).abs() < 1e-6 || body.alpha < 0.3, "the rug itself fades: {}", body.alpha);
    // A lamp fades too (Ref 1505), its name whole.
    assert!(shapes.iter().filter(|s| s.el == "l" && s.part == "body").all(|s| s.alpha <= 0.3 + 1e-6));
    assert_eq!(d.get("l").unwrap().opacity, 0.3);
}

#[test]
fn the_cone_is_the_part_of_the_sensor_the_films_frame_covers() {
    // His question, 2026-10-01 (Let's Bake, 9:16): the frame's shape counts.
    // Let's Bake's camera: 20.05 × 35.64, upright — the whole width is the frame.
    assert!((render::framed_width(20.05, 35.64, 1.0, 9.0 / 16.0) - 20.05).abs() < 0.01);
    // The same sensor typed lying down, 35.64 × 20.05: a 9:16 frame is the
    // height × 9/16 — 11.28 mm, not 35.64.
    assert!((render::framed_width(35.64, 20.05, 1.0, 9.0 / 16.0) - 11.278).abs() < 0.01);
    // 2.39 on Open Gate keeps the full width.
    assert_eq!(render::framed_width(36.70, 25.54, 1.0, 2.39), 36.70);
    // A 2× anamorphic on 23.76 × 17.82 for 2.39: 17.82 × 2.39, not 47.52.
    assert!((render::framed_width(23.76, 17.82, 2.0, 2.39) - 42.59).abs() < 0.01);
    // No height known: the width as typed.
    assert_eq!(render::framed_width(24.89, 0.0, 1.0, 0.5625), 24.89);

    // Through a camera: a 50 on the sideways sensor in a 9:16 film sees 12.9°.
    let side = super::lens::Gate { id: "u1".into(), name: "LF".into(), w: 35.64, h: 20.05 };
    let c = Context {
        shots: vec![("s1".into(), "1A".into(), "50mm".into())],
        units: vec![("u1".into(), "A-Cam".into(), Some(side))],
        shot_units: vec![("s1".into(), "u1".into())],
        ratio: 9.0 / 16.0,
        ..Default::default()
    };
    let d = plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"shot":"s1"}]"#);
    let o = render::camera_optics(d.get("c").unwrap(), &c);
    assert!((o.aov - 2.0 * (11.278f64 / 100.0).atan().to_degrees()).abs() < 0.05, "{}", o.aov);
}

#[test]
fn a_ruler_lays_down_markers_free_and_locked_and_says_each_distance() {
    // His ask, 2026-10-01: a ruler with markers, manual ones and ones that
    // lock to a person or object, saying the distance between the ends.
    let mut d = plan_with(r#"[{"kind":"camera","id":"cam","x":0,"y":0},{"kind":"cast","id":"anna","x":3,"y":0},
        {"kind":"measure","id":"r","x":0.2,"y":0.1,"x2":5,"y2":0,"pins":["cam",""]}]"#);
    // Its start went onto the camera it was laid on.
    let r = d.get("r").unwrap();
    assert_eq!((r.x, r.y), (0.0, 0.0));
    assert_eq!(r.pins, vec!["cam".to_string(), String::new()]);

    // A marker added on the first stretch, locked to Anna: it stands on her.
    apply(&mut d, &op(r#"{"op":"wall_insert","id":"r","stretch":0,"x":2.5,"y":0.4,"on":"anna"}"#)).unwrap();
    let r = d.get("r").unwrap();
    assert_eq!(walls::corners(r), vec![(0.0, 0.0), (3.0, 0.0), (5.0, 0.0)]);
    assert_eq!(r.pins[1], "anna");
    assert!((r.len() - 5.0).abs() < 1e-9);

    // Anna moves: her marker goes with her.
    apply(&mut d, &op(r#"{"op":"update","id":"anna","set":{"x":2,"y":0}}"#)).unwrap();
    assert_eq!(walls::corners(d.get("r").unwrap())[1], (2.0, 0.0));

    // Dragged by hand, the marker lets go of her.
    apply(&mut d, &op(r#"{"op":"wall_corner","id":"r","corner":1,"x":2.5,"y":1.0}"#)).unwrap();
    let r = d.get("r").unwrap();
    assert_eq!(r.pins[1], "");
    apply(&mut d, &op(r#"{"op":"update","id":"anna","set":{"x":4,"y":4}}"#)).unwrap();
    assert_eq!(walls::corners(d.get("r").unwrap())[1], (2.5, 1.0), "a free marker stays where it was put");

    // Drawn: a length on each stretch, the whole, and a marker dot.
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let words: Vec<String> = shapes.iter().filter(|s| s.el == "r").filter_map(|s| match &s.geom { Geom::Text { text, .. } => Some(text.clone()), _ => None }).collect();
    assert_eq!(words.iter().filter(|w| !w.starts_with("TOTAL")).count(), 2, "{words:?}");
    assert!(words.iter().any(|w| w.starts_with("TOTAL ")), "{words:?}");
    assert!(shapes.iter().any(|s| s.el == "r" && s.part == "marker"));

    // The camera goes: its lock lets go, the marker stays.
    apply(&mut d, &op(r#"{"op":"remove","ids":["cam"]}"#)).unwrap();
    let r = d.get("r").unwrap();
    assert!(r.pins.iter().all(|p| p.is_empty()));
    assert_eq!(walls::corners(r)[0], (0.0, 0.0));
}

/// His ask, 2026-10-02: half rounds, any size. One arrives at 60" across
/// and 30" deep, says 60" inside it, and stays half a circle however it is
/// sized.
#[test]
fn a_half_round_is_named_by_its_diameter_and_stays_half_a_circle() {
    let inch = FOOT / 12.0;
    let s = symbols::find(symbols::HALF_ROUND).expect("in the library");
    let mut d = plan_with(&format!(r#"[{{"kind":"set","id":"t","sym":"{}","x":0,"y":0,"w":{},"h":{}}}]"#, s.id, s.w, s.h));
    let t = d.get("t").unwrap();
    assert!((t.w - 60.0 * inch).abs() < 1e-9 && (t.h - 30.0 * inch).abs() < 1e-9);
    let shapes = render::render(&d, &ctx(), &Options::default());
    let tag = shapes.iter().find(|s| s.el == "t" && s.part == "label").expect("a name");
    assert!(matches!(&tag.geom, Geom::Text { text, x, y, .. } if text == "60\"" && x.abs() < 1e-9 && y.abs() < 1e-9), "{:?}", tag.geom);
    let v = json::parse(&wire::payload(&d, &Context::default(), &Options::default())).unwrap();
    assert_eq!(v.get("els").unwrap().as_array().unwrap()[0].str_field("name"), "60\" Half Round");

    // Its width typed: 72" across, 36" deep, its back where it was.
    let back = |d: &Diagram| d.get("t").map(|t| t.y - t.h / 2.0).unwrap();
    let at = back(&d);
    apply(&mut d, &op(&format!(r#"{{"op":"update","ids":["t"],"set":{{"w":{}}}}}"#, 72.0 * inch))).unwrap();
    let t = d.get("t").unwrap();
    assert!((t.w - 72.0 * inch).abs() < 1e-9 && (t.h - 36.0 * inch).abs() < 1e-9);
    assert!((back(&d) - at).abs() < 1e-9, "the back stays on its wall");
    // Its depth typed: 24" deep is 48" across.
    apply(&mut d, &op(&format!(r#"{{"op":"update","ids":["t"],"set":{{"h":{}}}}}"#, 24.0 * inch))).unwrap();
    assert!((d.get("t").unwrap().w - 48.0 * inch).abs() < 1e-9);

    // A front corner dragged out, as the Mac sends it: the box the hand
    // made (not half a circle), centred between the held back corner and the
    // hand. It is read along the diagonal, and the held corner stays put.
    let t = d.get("t").unwrap().clone();
    let held = (t.x - t.w / 2.0, t.y - t.h / 2.0);
    let (w, h) = (66.0 * inch, 40.0 * inch);
    let set = format!(r#"{{"op":"update","ids":["t"],"set":{{"w":{w},"h":{h},"x":{},"y":{}}}}}"#, held.0 + w / 2.0, held.1 + h / 2.0);
    apply(&mut d, &op(&set)).unwrap();
    let t = d.get("t").unwrap();
    assert!((t.h - t.w / 2.0).abs() < 1e-9, "half a circle: {} × {}", t.w, t.h);
    assert!(t.w > 48.0 * inch, "it grew: {}", t.w / inch);
    assert!((t.x - t.w / 2.0 - held.0).abs() < 1e-9 && (t.y - t.h / 2.0 - held.1).abs() < 1e-9, "the held corner stays");
    // With Snap on in feet, a drag lands on six inches.
    d.settings.snap = true;
    apply(&mut d, &op(&set)).unwrap();
    let t = d.get("t").unwrap();
    assert!(((t.w / inch / 6.0).round() * 6.0 - t.w / inch).abs() < 1e-6, "{}", t.w / inch);
    assert_eq!(symbols::half_round_size(t), format!("{}\"", (t.w / inch).round()));
}

/// **Join is Break's opposite** (his ask, 2026-10-02): the two walls a Break
/// made, or an open wall whose ends a door's width apart, meet again.
#[test]
fn join_closes_the_gap_a_break_left() {
    // Broken mid-stretch: two walls, a three-foot gap. Joined: one wall again.
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","x":0,"y":0,"x2":6,"y2":0}]"#);
    apply(&mut d, &op(r#"{"op":"wall_insert","id":"w","stretch":0}"#)).unwrap();
    let made = apply(&mut d, &op(r#"{"op":"wall_break","id":"w","corner":1}"#)).unwrap();
    assert_eq!(d.els.iter().filter(|e| e.kind == Kind::Wall).count(), 2);
    apply(&mut d, &op(&format!(r#"{{"op":"wall_join","ids":["w","{}"]}}"#, made[0]))).unwrap();
    assert_eq!(d.els.iter().filter(|e| e.kind == Kind::Wall).count(), 1);
    let c = wall_of(&d, "w");
    assert!(near(c[0], (0.0, 0.0)) && near(c[c.len() - 1], (6.0, 0.0)), "{c:?}");
    // A room broken at a corner: the one open wall, named alone, closes.
    let mut d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true}]"#);
    apply(&mut d, &op(r#"{"op":"wall_break","id":"r","corner":0}"#)).unwrap();
    assert!(!walls::closed(d.get("r").unwrap()));
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["r"]}"#)).unwrap();
    assert!(walls::closed(d.get("r").unwrap()));
    // Two walls far apart stay two.
    let mut d = plan_with(r#"[{"id":"a","kind":"wall","x":0,"y":0,"x2":2,"y2":0},{"id":"b","kind":"wall","x":9,"y":0,"x2":11,"y2":0}]"#);
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["a","b"]}"#)).unwrap();
    assert_eq!(d.els.iter().filter(|e| e.kind == Kind::Wall).count(), 2);
    // A long straight wall named alone does not close on itself.
    let mut d = plan_with(r#"[{"id":"a","kind":"wall","points":[[0,0],[4,0],[4,3]]}]"#);
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["a"]}"#)).unwrap();
    assert!(!walls::closed(d.get("a").unwrap()));
}

#[test]
fn join_puts_back_the_corner_a_break_took_out() {
    let mut d = plan_with(r#"[{"id":"r","kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true}]"#);
    apply(&mut d, &op(r#"{"op":"wall_break","id":"r","corner":0}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["r"]}"#)).unwrap();
    let r = d.get("r").unwrap();
    assert!(walls::closed(r));
    let c = walls::corners(r);
    assert_eq!(c.len(), 4, "{c:?}");
    assert!(c.iter().any(|p| near(*p, (0.0, 0.0))), "the corner is back: {c:?}");
    // Two walls at a right angle, a gap between: they meet at the corner.
    let mut d = plan_with(r#"[{"id":"a","kind":"wall","x":0,"y":0,"x2":3,"y2":0},{"id":"b","kind":"wall","x":4,"y":1,"x2":4,"y2":4}]"#);
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["a","b"]}"#)).unwrap();
    let c = wall_of(&d, "a");
    assert_eq!(c.len(), 3, "{c:?}");
    assert!(near(c[1], (4.0, 0.0)), "{c:?}");
}

// ---------------------------------------------------------------- Draw: smooth points

fn near_line(p: (f64, f64), run: &[(f64, f64)]) -> f64 {
    run.windows(2).map(|w| seg_dist(p.0, p.1, w[0], w[1])).fold(f64::MAX, f64::min)
}

/// **Smooth points** (his ask, 2026-10-02): a corner with handles bends the
/// stretches either side of it, and the wall is drawn along the curve.
#[test]
fn a_wall_with_handles_runs_along_the_curve() {
    let d = plan_with(r#"[{"id":"w","kind":"wall","points":[[0,0],[4,0]],"handles":[[0,0,0,2],[0,2,0,0]]}]"#);
    let w = d.get("w").unwrap();
    assert!(walls::curved(w));
    let run = walls::run(w);
    assert!(run.len() > 20, "a curve is many points: {}", run.len());
    assert!(near(run[0], (0.0, 0.0)) && near(run[run.len() - 1], (4.0, 0.0)));
    assert!(near_line((2.0, 1.5), &run) < 1e-3, "the middle of the curve is (2, 1.5)");
    assert!(walls::length(w) > 4.5);
    // A hit on the curve is a hit on the wall; a hit on the straight chord is not.
    assert!(hits(w, 2.0, 1.5, 0.05, 1));
    assert!(!hits(w, 2.0, 0.0, 0.05, 1));
    // It comes back through a file.
    let back = El::from_json(&json::parse(&w.to_json().encode()).unwrap()).unwrap();
    assert_eq!(back.handles, w.handles);
}

#[test]
fn a_corner_is_made_smooth_and_sharp_again_and_a_handle_drags_its_twin_along() {
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","points":[[0,0],[3,0],[3,3]]}]"#);
    apply(&mut d, &op(r#"{"op":"wall_smooth","id":"w","corner":1}"#)).unwrap();
    let w = d.get("w").unwrap();
    assert!(walls::curved(w));
    let h = w.handles[1];
    // Along the line from the corner before to the corner after: (3,3)-(0,0).
    assert!((h[0] + h[1]).abs() < 1e-9 || (h[0] - h[1]).abs() < 1e-9, "{h:?}");
    assert!(h[2] > 0.0 && h[3] > 0.0 && h[0] < 0.0 && h[1] < 0.0, "{h:?}");
    // The out handle dragged: the in handle swings to the opposite side.
    apply(&mut d, &op(r#"{"op":"wall_handle","id":"w","corner":1,"side":"out","x":3,"y":5}"#)).unwrap();
    let h = d.get("w").unwrap().handles[1];
    assert!(h[2].abs() < 1e-9 && (h[3] - 5.0).abs() < 1e-9, "{h:?}");
    assert!((h[0]).abs() < 1e-9 && h[1] < 0.0, "in handle opposite: {h:?}");
    // Free, the twin stays.
    apply(&mut d, &op(r#"{"op":"wall_handle","id":"w","corner":1,"side":"out","x":5,"y":3,"free":true}"#)).unwrap();
    let g = d.get("w").unwrap().handles[1];
    assert!((g[0] - h[0]).abs() < 1e-9 && (g[1] - h[1]).abs() < 1e-9);
    // Sharp again: no handles left at all.
    apply(&mut d, &op(r#"{"op":"wall_smooth","id":"w","corner":1,"smooth":false}"#)).unwrap();
    assert!(d.get("w").unwrap().handles.is_empty());
    // A drawn path with sharp corners only is still a path, not a freehand line.
    let mut d = plan_with(r#"[{"id":"s","kind":"stroke","points":[[0,0],[2,0],[2,2]],"handles":[[0,0,0,0],[0,0,0,0],[0,0,0,0]]}]"#);
    assert_eq!(d.get("s").unwrap().handles.len(), 3);
    apply(&mut d, &op(r#"{"op":"wall_smooth","id":"s","corner":1}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"wall_smooth","id":"s","corner":1,"smooth":false}"#)).unwrap();
    assert_eq!(d.get("s").unwrap().handles.len(), 3, "still a path");
}

#[test]
fn a_point_added_in_a_curve_keeps_the_curve() {
    let mut d = plan_with(r#"[{"id":"w","kind":"wall","points":[[0,0],[4,0]],"handles":[[0,0,0,2],[0,2,0,0]]}]"#);
    let before = walls::run(d.get("w").unwrap());
    apply(&mut d, &op(r#"{"op":"wall_insert","id":"w","stretch":0}"#)).unwrap();
    let w = d.get("w").unwrap();
    assert_eq!(walls::corners(w).len(), 3);
    assert_eq!(w.handles.len(), 3);
    let after = walls::run(w);
    let worst = after.iter().map(|p| near_line(*p, &before)).fold(0.0, f64::max);
    assert!(worst < 0.01, "same curve, off by {worst}");
    assert!(near(walls::corners(w)[1], (2.0, 1.5)));
    // A corner taken out takes its handles.
    apply(&mut d, &op(r#"{"op":"wall_remove_corner","id":"w","corner":1}"#)).unwrap();
    assert_eq!(d.get("w").unwrap().handles.len(), 2);
}

#[test]
fn handles_turn_and_flip_with_their_piece() {
    let mut d = plan_with(r#"[{"id":"s","kind":"stroke","points":[[0,0],[4,0]],"handles":[[0,0,0,2],[0,2,0,0]]}]"#);
    apply(&mut d, &op(r#"{"op":"rotate","ids":["s"],"deg":90}"#)).unwrap();
    let h = d.get("s").unwrap().handles[0];
    assert!((h[2] + 2.0).abs() < 1e-6 && h[3].abs() < 1e-6, "{h:?}");
    apply(&mut d, &op(r#"{"op":"flip","ids":["s"],"axis":"x"}"#)).unwrap();
    assert_eq!(d.get("s").unwrap().handles.len(), 2);
}

/// One drawn path, three ways to use it.
#[test]
fn a_path_is_a_wall_an_object_or_a_line() {
    let mut d = plan_with(r#"[{"id":"p","kind":"stroke","closed":true,"points":[[0,0],[4,0],[4,3],[0,3]],"handles":[[0,0,0,0],[0,0,0,1],[0,-1,0,0],[0,0,0,0]]}]"#);
    assert!(walls::closed(d.get("p").unwrap()));
    // An object is filled and hit anywhere inside it.
    apply(&mut d, &op(r#"{"op":"path_as","id":"p","as":"object"}"#)).unwrap();
    let p = d.get("p").unwrap();
    assert!(p.fill && p.kind == Kind::Stroke);
    assert!(hits(p, 1.0, 1.5, 0.05, 1), "inside");
    assert!(!hits(p, 9.0, 9.0, 0.05, 1));
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(shapes.iter().any(|s| s.el == "p" && s.alpha < 1.0), "a wash");
    // A wall takes its thickness, its handles and its closing; doors can sit in it.
    apply(&mut d, &op(r#"{"op":"path_as","id":"p","as":"wall"}"#)).unwrap();
    let p = d.get("p").unwrap();
    assert!(p.kind == Kind::Wall && p.thick > 0.0 && !p.fill && walls::closed(p) && walls::curved(p));
    // And a line is the outline alone.
    apply(&mut d, &op(r#"{"op":"path_as","id":"p","as":"line"}"#)).unwrap();
    let p = d.get("p").unwrap();
    assert!(p.kind == Kind::Stroke && !p.fill && walls::closed(p) && walls::curved(p) && p.points.len() == 4);
}

#[test]
fn joining_curved_walls_keeps_their_curves() {
    let mut d = plan_with(
        r#"[{"id":"a","kind":"wall","points":[[0,0],[3,0]],"handles":[[0,0,0,1],[0,1,0,0]]},
            {"id":"b","kind":"wall","points":[[3,0],[6,0]],"handles":[[0,-1,0,0],[0,0,0,-1]]}]"#,
    );
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["a","b"]}"#)).unwrap();
    let w = d.get("a").unwrap();
    assert_eq!(walls::corners(w).len(), 3);
    assert_eq!(w.handles.len(), 3);
    assert!(walls::curved(w));
    // Laid the other way round, handles change places: b's far end is joined first.
    let mut d = plan_with(
        r#"[{"id":"a","kind":"wall","points":[[0,0],[3,0]],"handles":[[0,0,0,1],[0,1,0,0]]},
            {"id":"b","kind":"wall","points":[[6,0],[3,0]],"handles":[[0,0,0,-1],[0,-1,0,0]]}]"#,
    );
    apply(&mut d, &op(r#"{"op":"wall_join","ids":["a","b"]}"#)).unwrap();
    let w = d.get("a").unwrap();
    assert_eq!(walls::corners(w).len(), 3);
    assert!(near(walls::corners(w)[2], (6.0, 0.0)));
    // b read backwards: its first corner (6,0) had out (0,-1); reversed it is the in handle at the end.
    assert!((w.handles[2][1] + 1.0).abs() < 1e-9 || (w.handles[2][1] - 1.0).abs() < 1e-9, "{:?}", w.handles);
}

/// **A fill out of a shape** (his ask, 2026-10-02): a closed path takes a
/// fill of any colour and firmness, a room takes one as a floor, and an
/// outline without one stays clear.
#[test]
fn a_closed_path_or_room_can_be_filled_with_a_colour() {
    let washes = |d: &Diagram, id: &str| -> Vec<Shape> { render::render(d, &ctx(), &Options::default()).into_iter().filter(|s| s.el == id && s.alpha < 1.0).collect() };
    // A drawn outline, no fill: nothing inside.
    let mut d = plan_with(r#"[{"id":"p","kind":"stroke","closed":true,"fill":false,"points":[[0,0],[4,0],[4,3],[0,3]],"handles":[[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]]}]"#);
    assert!(washes(&d, "p").is_empty());
    assert!(!hits(d.get("p").unwrap(), 2.0, 1.5, 0.05, 1), "an outline is not hit inside");
    // Filled with a colour: firmer than a tint; its own firmness if given.
    apply(&mut d, &op(r##"{"op":"update","id":"p","set":{"fill":true,"fill_color":"#E5484D"}}"##)).unwrap();
    let w = washes(&d, "p");
    assert_eq!(w.len(), 1);
    assert!((w[0].alpha - 0.55).abs() < 1e-9 && w[0].fill == Ink::hex("#E5484D"), "{:?}", w[0].alpha);
    assert!(hits(d.get("p").unwrap(), 2.0, 1.5, 0.05, 1));
    apply(&mut d, &op(r#"{"op":"update","id":"p","set":{"fill_alpha":0.9}}"#)).unwrap();
    assert!((washes(&d, "p")[0].alpha - 0.9).abs() < 1e-9);
    let back = El::from_json(&json::parse(&d.get("p").unwrap().to_json().encode()).unwrap()).unwrap();
    assert_eq!((back.fill_color.as_str(), back.fill_alpha), ("#E5484D", 0.9));
    // A room is filled only when told: walls have always had `fill` on.
    let mut d = plan_with(r#"[{"id":"r","kind":"wall","closed":true,"points":[[0,0],[4,0],[4,3],[0,3]]}]"#);
    assert!(washes(&d, "r").is_empty());
    apply(&mut d, &op(r#"{"op":"update","id":"r","set":{"fill_color":"auto"}}"#)).unwrap();
    assert_eq!(washes(&d, "r").len(), 1);
    // A line again: the fill goes.
    apply(&mut d, &op(r#"{"op":"path_as","id":"r","as":"object"}"#)).unwrap();
    assert_eq!(washes(&d, "r").len(), 1, "an object keeps its floor as its fill");
    apply(&mut d, &op(r#"{"op":"path_as","id":"r","as":"line"}"#)).unwrap();
    assert!(washes(&d, "r").is_empty());
}

// ---------------------------------------------------------------- the plot

fn bodies<'a>(shapes: &'a [Shape], id: &str) -> Vec<&'a Shape> {
    shapes.iter().filter(|s| s.el == id && s.part == "body").collect()
}

fn name_of(shapes: &[Shape], id: &str) -> String {
    shapes
        .iter()
        .filter(|s| s.el == id && s.part == "label")
        .find_map(|s| match &s.geom {
            Geom::Text { text, .. } => Some(text.clone()),
            _ => None,
        })
        .unwrap_or_default()
}

#[test]
fn a_plan_is_always_a_plot() {
    let mut d = Diagram::default();
    assert_eq!(d.settings.style, "plot");
    assert!(!d.encode().contains("style"), "nothing written for it");
    // Asked for pictures — by an old plan, or a stray edit — it stays a plot.
    apply(&mut d, &op(r#"{"op":"settings","set":{"style":"picture"}}"#)).unwrap();
    assert_eq!(d.settings.style, "plot");
    assert_eq!(Diagram::parse(r#"{"els":[],"settings":{"style":"picture"}}"#).settings.style, "plot");
}

#[test]
fn a_plot_marks_a_lamp_in_red_and_counts_it() {
    let d = plotted(plan_with(r#"[{"kind":"light","id":"a","sym":"tungsten-fresnel-1k","x":0,"y":0,"count":3}]"#));
    let shapes = render::render(&d, &ctx(), &Options::default());
    let marks = bodies(&shapes, "a");
    assert!(!marks.is_empty());
    assert!(marks.iter().any(|s| s.stroke == Ink::Role("added") || s.fill == Ink::Role("added")), "a light we bring is red");
    assert!(marks.iter().all(|s| !matches!(s.geom, Geom::Image { .. })), "no picture on a plot");
    assert!(name_of(&shapes, "a").starts_with("3× "), "{}", name_of(&shapes, "a"));
    assert_eq!(name_of(&shapes, "a"), name_of(&shapes, "a").to_uppercase(), "a plot writes in capitals");
}

#[test]
fn an_existing_light_is_dark_and_says_what_is_done_to_it() {
    let d = plotted(plan_with(r#"[{"kind":"light","id":"p","sym":"bulb","existing":true,"action":"off"},
                          {"kind":"light","id":"q","sym":"bulb","existing":true,"action":"Swap"}]"#));
    let shapes = render::render(&d, &ctx(), &Options::default());
    let p = bodies(&shapes, "p");
    assert!(p.iter().all(|s| s.stroke != Ink::Role("added") && s.fill != Ink::Role("added")));
    // Off is crossed out: two more strokes than a lamp left on.
    assert_eq!(p.len(), bodies(&shapes, "q").len() + 2);
    assert!(name_of(&shapes, "p").ends_with("OFF"), "{}", name_of(&shapes, "p"));
    assert!(name_of(&shapes, "q").ends_with("SWAP"), "{}", name_of(&shapes, "q"));
}

#[test]
fn the_plot_fields_round_trip_and_unknown_actions_are_dropped() {
    let d = plan_with(r#"[{"kind":"light","id":"a","sym":"bulb","count":6,"existing":true,"action":"dim"},
                          {"kind":"light","id":"b","sym":"bulb","action":"explode","count":0}]"#);
    let back = Diagram::parse(&d.encode());
    assert_eq!(back, d);
    let a = &back.els[0];
    assert_eq!((a.count, a.existing, a.action.as_str()), (6, true, "dim"));
    let b = &back.els[1];
    assert_eq!((b.count, b.action.as_str()), (1, ""));
}

#[test]
#[ignore = "draws a sample plot to PLOT_OUT for a person to look at"]
fn zz_sample_plot_picture() {
    let Ok(dir) = std::env::var("PLOT_OUT") else { return };
    let els = r#"[
      {"kind":"wall","points":[[0,0],[10,0],[10,7],[0,7]],"closed":true},
      {"kind":"wall","x":4,"y":2,"x2":4,"y2":7},{"kind":"wall","x":4,"y":2,"x2":7.5,"y2":2},{"kind":"wall","x":7.5,"y":2,"x2":7.5,"y2":7},
      {"kind":"door","x":5.5,"y":2,"w":0.9,"rot":0,"swing":90},
      {"kind":"door","x":2,"y":7,"w":0.9,"rot":0,"swing":90,"flip":true},
      {"kind":"window","x":10,"y":4,"w":1.2,"rot":90},
      {"kind":"window","x":2,"y":0,"w":1.5,"rot":0},
      {"kind":"set","sym":"fso-bed","x":5.7,"y":4.4,"w":1.52,"h":2.03},
      {"kind":"set","sym":"fso-triple-couch","x":0.55,"y":3,"w":2.5,"h":0.85,"rot":90},
      {"kind":"set","sym":"fso-small-rectangle-table","x":2.4,"y":3,"w":1.2,"h":0.55,"rot":90},
      {"kind":"set","sym":"fso-large-circular-table","x":8.7,"y":5.2,"w":1.2,"h":1.2},
      {"kind":"set","sym":"stove","x":9.4,"y":0.6,"w":0.76,"h":0.65},
      {"kind":"set","sym":"fso-tree","x":-3,"y":2,"w":3,"h":3},
      {"kind":"set","sym":"fso-hedge","x":6,"y":8.4,"w":3,"h":1},
      {"kind":"set","sym":"fso-car","x":-2.5,"y":7,"w":1.55,"h":3.27},
      {"kind":"light","id":"fl","sym":"lamp-shade","x":2.6,"y":1.4,"existing":true,"action":"dim","label":"Floor Lamp 150W"},
      {"kind":"light","id":"cl","sym":"bulb","x":5.8,"y":1,"existing":true,"action":"swap","label":"150W Tungsten in Ceiling"},
      {"kind":"light","id":"st","sym":"bulb","x":9,"y":1.4,"existing":true,"action":"off","label":"Stove Light"},
      {"kind":"light","id":"ti","sym":"generic-tube","x":11,"y":4,"rot":180,"w":0.06,"h":1.2,"label":"4' Titan, Uplight Hedge"},
      {"kind":"light","id":"he","sym":"astera-helios","x":6,"y":7.6,"rot":-90,"count":2,"w":0.05,"h":0.55,"label":"2' Helios, Uplight Bushes"},
      {"kind":"light","id":"m18","sym":"fso-arri-m18","x":5.7,"y":2.7,"rot":90,"label":"MSR60 for Bounce"},
      {"kind":"light","id":"b1","sym":"tungsten-fresnel-1k","x":13,"y":0.5,"rot":180,"label":"2K Blonde"},
      {"kind":"light","id":"b2","sym":"tungsten-fresnel-1k","x":13,"y":2.5,"rot":180,"label":"2K Blonde"},
      {"kind":"light","id":"b3","sym":"tungsten-fresnel-1k","x":13,"y":4.5,"rot":180,"label":"2K Blonde"},
      {"kind":"light","id":"sky","sym":"skypanel-s60","x":1.2,"y":5.6,"rot":0,"label":"S60 Fill"},
      {"kind":"light","id":"fr","sym":"frame","x":6.6,"y":3.2,"h":1.22,"tilt":90,"label":"4x4 Full Grid"},
      {"kind":"light","id":"ov","sym":"frame","x":5.7,"y":4.4,"h":2.44,"tilt":0,"material":"bounce-white","label":"8x8 Ultrabounce Overhead"},
      {"kind":"light","id":"f2","sym":"frame","x":15.5,"y":2,"rot":180,"h":3.66,"tilt":45,"material":"grid-cloth","label":"12x12 Grid Cloth"},
      {"kind":"light","id":"f3","sym":"frame","x":15.5,"y":6.5,"rot":180,"h":2.44,"tilt":20,"material":"diff-medium","label":"8x8 Silk"},
      {"kind":"light","id":"f4","sym":"frame","x":-1,"y":-2.5,"h":1.83,"tilt":0,"material":"solid","label":"6x6 Solid"},
      {"kind":"light","id":"f5","sym":"frame","x":2,"y":-2.5,"h":1.83,"tilt":60,"rot":90,"material":"double-net","label":"6x6 Double"},
      {"kind":"camera","x":7,"y":5.6,"rot":200,"lens":32},
      {"kind":"cast","x":5.2,"y":5.6,"rot":-30,"label":"Maya"}
    ]"#;
    let mut d = plotted(plan_with(els));
    let frame = super::svg::Frame {
        width: 1500.0, margin: 40.0, grid: false, scale_bar: true, media: String::new(), area: None, max_scale: 400.0,
        fades: false, max_height: None, hrefs: Vec::new(), art: String::new(), window: None,
    };
    std::fs::write(format!("{dir}/plot.svg"), super::svg::svg(&d, &ctx(), &Options { paper: true, ..Default::default() }, &frame, "p")).unwrap();
    d.settings.style = "picture".into();
    std::fs::write(format!("{dir}/picture.svg"), super::svg::svg(&d, &ctx(), &Options { paper: true, ..Default::default() }, &frame, "q")).unwrap();
}


#[test]
fn units_of_one_family_share_its_symbol_and_their_names_tell_them_apart() {
    // Two hard heads (both chevrons by family), a tube, a practical of the
    // location's own and a second of the first kind.
    let d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"tungsten-fresnel-1k","count":2},
            {"kind":"light","id":"b","sym":"tungsten-fresnel-20k"},
            {"kind":"light","id":"t","sym":"generic-tube","w":0.06,"h":1.2},
            {"kind":"light","id":"p","sym":"bulb","existing":true},
            {"kind":"light","id":"a2","sym":"tungsten-fresnel-1k"}]"#,
    ));
    let lg = plot::legend(&d);
    assert_eq!(lg.len(), 4, "{lg:?}");
    assert_eq!(lg[0].count, 3, "counts summed across pieces");
    assert_eq!(lg[0].name, "1K Tungsten Fresnel", "named by the unit until he names it");
    assert_eq!(lg[0].look.mark, plot::Mark::Chevron);
    // His call, 2026-10-05: three kinds of panel are three panels.
    assert_eq!(lg[0].look, lg[1].look, "two hard heads share the chevron");
    assert_ne!(lg[0].name, lg[1].name, "and their names tell them apart");
    assert_eq!(lg[2].look.mark, plot::Mark::Bar);
    assert_eq!((lg[3].look.mark, lg[3].look.ink), (plot::Mark::Ring, "ink"), "the location's own is black");
}

#[test]
fn a_mark_is_picked_first_and_named_later() {
    // Three chevrons and a wedge, put down with no unit at all.
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron"},{"kind":"light","id":"b","sym":"","mark":"chevron"},
            {"kind":"light","id":"c","sym":"","mark":"chevron","count":2},{"kind":"light","id":"w","sym":"","mark":"wedge","mark_ink":"blue"}]"#,
    ));
    let lg = plot::legend(&d);
    assert_eq!(lg.len(), 2);
    assert_eq!((lg[0].count, lg[0].name.as_str()), (4, ""), "unnamed until he says");
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "a"), "", "a bare mark has no callout");
    // Named once in the legend: every chevron is a 2K Blonde.
    let key = lg[0].key.clone();
    apply(&mut d, &op(&format!(r#"{{"op":"legend","key":"{key}","name":"2K Blonde"}}"#))).unwrap();
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "b"), "2K BLONDE");
    assert_eq!(name_of(&shapes, "c"), "2× 2K BLONDE");
    assert!(name_of(&shapes, "w").is_empty(), "the wedge is still its own kind");
    // Re-marked from the legend: every chevron becomes an arrow, its name going too.
    apply(&mut d, &op(&format!(r#"{{"op":"legend","key":"{key}","to":"arrow|added|open"}}"#))).unwrap();
    let back = Diagram::parse(&d.encode());
    assert!(back.els.iter().filter(|e| e.id != "w").all(|e| e.mark == "arrow"));
    let lg = plot::legend(&back);
    assert_eq!((lg[0].look.mark, lg[0].name.as_str()), (plot::Mark::Arrow, "2K Blonde"));
}

#[test]
fn a_plot_draws_walls_as_a_thin_line_and_no_lengths_unless_picked() {
    let d = plotted(plan_with(r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":4,"y2":0}]"#));
    let shapes = render::render(&d, &ctx(), &Options { paper: true, ..Default::default() });
    let w: Vec<&Shape> = shapes.iter().filter(|s| s.el == "w" && s.part == "body").collect();
    assert!(w.iter().any(|s| s.stroke == Ink::Role("plan") && s.fill == Ink::None));
    assert!(!shapes.iter().any(|s| s.part == "dim"), "no lengths on paper unless asked");
    let picked = render::render(&d, &ctx(), &Options { sel: vec!["w".into()], ..Default::default() });
    assert!(picked.iter().any(|s| s.part == "dim"), "the picked wall says its length");
}

#[test]
fn a_plot_draws_no_moves_but_keeps_them() {
    let mut d = plotted(plan_with(r#"[{"kind":"cast","id":"c","x":0,"y":0}]"#));
    d.els[0].steps.push(Step { x: 3.0, y: 0.0, rot: 0.0, pose: Pose::Same, turn: false, beat: 2 });
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(!shapes.iter().any(|s| s.part == "ghost" || s.part == "path"));
    assert_eq!(d.els[0].steps.len(), 1, "the film still holds the move");
}

#[test]
fn a_plot_frame_is_a_line_and_says_its_lean() {
    let d = plotted(plan_with(r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":2.4384,"tilt":45,"material":"grid-cloth"}]"#));
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(name_of(&shapes, "f").contains("45°"), "{}", name_of(&shapes, "f"));
    // **Quiet** (Back to Paper, 2026-10-04): leaning, it is its raised edge
    // — one line, in the red of what we bring — with no hatching, no
    // perspective and nothing filled.
    let f: Vec<&Shape> = shapes.iter().filter(|s| s.el == "f" && s.part == "body").collect();
    let drawn: Vec<&&Shape> = f.iter().filter(|s| s.stroke != Ink::None && s.alpha >= 1.0).collect();
    assert_eq!(drawn.len(), 1, "one line: {drawn:?}");
    assert_eq!(drawn[0].stroke, Ink::Role("added"), "grip in the film lights' red");
    assert!(f.iter().all(|s| s.fill == Ink::None || s.fill == plot::clear() || s.alpha < 0.5), "nothing filled but its faint cloth");
    // Lying flat it is its dashed outline; standing, a double line.
    let flat = plotted(plan_with(r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":2.4384,"tilt":0,"material":"silk"}]"#));
    let shapes = render::render(&flat, &ctx(), &Options::default());
    let lines: Vec<&Shape> = shapes.iter().filter(|s| s.el == "f" && s.part == "body" && s.stroke != Ink::None).collect();
    assert!(lines.len() == 1 && lines[0].dash == "dash", "{lines:?}");
    // Its cloth stays on, faint, unpicked and on paper (his note, 2026-10-05).
    assert!(shapes.iter().any(|s| s.el == "f" && s.alpha < 0.5 && s.fill != Ink::None && s.fill != plot::clear()), "its cloth, faint");
    let paper = render::render(&flat, &ctx(), &Options { paper: true, ..Default::default() });
    assert!(paper.iter().filter(|s| s.el == "f" && s.alpha < 0.5).count() > 3, "on paper too");
    // Frame Fabric off: the outline alone.
    let mut bare = flat.clone();
    apply(&mut bare, &op(r#"{"op":"settings","set":{"fabric":false}}"#)).unwrap();
    let shapes = render::render(&bare, &ctx(), &Options::default());
    assert!(!shapes.iter().any(|s| s.el == "f" && s.alpha < 1.0), "no cloth");
    // Picked on screen, its lean and its cloth show as before.
    let picked = render::render(&d, &ctx(), &Options { sel: vec!["f".into()], ..Default::default() });
    let f: Vec<&Shape> = picked.iter().filter(|s| s.el == "f").collect();
    assert!(f.iter().any(|s| s.dash == "dash"), "its low edges dashed");
    assert!(f.iter().filter(|s| s.stroke == Ink::Role("added")).count() > 10, "a cross-hatch");
    // Never full strength on paper.
    let paper = render::render(&d, &ctx(), &Options { sel: vec!["f".into()], paper: true, ..Default::default() });
    assert_eq!(paper.iter().filter(|s| s.el == "f" && s.part == "body" && s.stroke != Ink::None && s.alpha >= 1.0).count(), 1);
}

#[test]
fn a_plot_camera_is_a_symbol_with_its_view_to_scale() {
    let d = plotted(plan_with(r#"[{"kind":"camera","id":"c","x":0,"y":0,"lens":50}]"#));
    let shapes = render::render(&d, &ctx(), &Options::default());
    let view: Vec<&Shape> = shapes.iter().filter(|s| s.el == "c" && s.part == "cone").collect();
    assert_eq!(view.len(), 2, "two view lines, no filled cone");
    assert!(view.iter().all(|s| s.fill == Ink::None && s.dash == "dash"));
}

#[test]
fn a_plot_takes_his_colours_by_category() {
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron"},{"kind":"light","id":"e","sym":"","mark":"dot","existing":true},
            {"kind":"wall","id":"w","x":0,"y":0,"x2":3,"y2":0}]"#,
    ));
    apply(&mut d, &op(r##"{"op":"settings","set":{"colours":{"added":"#ff8800","existing":"#334455","plan":"#nothex","bogus":"#123456"}}}"##)).unwrap();
    assert_eq!(d.settings.colours, vec![("added".to_string(), "#FF8800".to_string()), ("existing".to_string(), "#334455".to_string())]);
    let back = Diagram::parse(&d.encode());
    assert_eq!(back.settings.colours, d.settings.colours);
    let shapes = render::render(&back, &ctx(), &Options::default());
    let inks = |id: &str| shapes.iter().filter(|s| s.el == id && s.part == "body").flat_map(|s| [s.fill.clone(), s.stroke.clone()]).collect::<Vec<_>>();
    assert!(inks("a").contains(&Ink::hex("#FF8800")));
    assert!(inks("e").contains(&Ink::hex("#334455")));
    assert!(inks("w").contains(&Ink::Role("plan")), "a category he left alone keeps the shell's colour");
}

#[test]
fn a_camera_locks_to_track_and_slides_only_along_it() {
    let mut d = plotted(plan_with(
        r#"[{"kind":"track","id":"t","x":0,"y":0,"x2":7.3152,"y2":0},{"kind":"camera","id":"c","x":2,"y":1.5}]"#,
    ));
    assert!(d.get("c").unwrap().rig_on.is_empty(), "a camera near track is not locked until asked");
    apply(&mut d, &op(r#"{"op":"ride","id":"c"}"#)).unwrap();
    let c = d.get("c").unwrap();
    assert_eq!((c.rig_on.as_str(), c.x, c.y), ("t", 2.0, 0.0), "on the track's line");
    // Dragged off to one side, it stays on the line.
    apply(&mut d, &op(r#"{"op":"move","ids":["c"],"dx":1,"dy":3}"#)).unwrap();
    let c = d.get("c").unwrap();
    assert_eq!((c.rig_on.as_str(), c.x, c.y), ("t", 3.0, 0.0));
    // The track moves: the camera goes with it.
    apply(&mut d, &op(r#"{"op":"move","ids":["t"],"dx":0,"dy":2}"#)).unwrap();
    assert_eq!(d.get("c").unwrap().y, 2.0);
    // Unlocked, it is free.
    apply(&mut d, &op(r#"{"op":"update","id":"c","set":{"rig_on":""}}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"move","ids":["c"],"dx":0,"dy":3}"#)).unwrap();
    assert_eq!((d.get("c").unwrap().rig_on.as_str(), d.get("c").unwrap().y), ("", 5.0));
    // The track says how long it is and what it takes.
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(name_of(&shapes, "t").contains("24 FT · 3 × 8'"), "{}", name_of(&shapes, "t"));
    assert_eq!(plot::track_sections(28.0 * FOOT), "3 × 8' + 4'");
    assert_eq!(plot::track_sections(10.0 * FOOT), "8' + 2'");
}

#[test]
fn one_label_serves_many_lamps_and_any_can_let_go() {
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0},{"kind":"light","id":"b","sym":"","mark":"chevron","x":8,"y":0},
            {"kind":"light","id":"c","sym":"","mark":"chevron","x":4,"y":6,"count":2}]"#,
    ));
    let key = plot::legend(&d)[0].key.clone();
    apply(&mut d, &op(&format!(r#"{{"op":"legend","key":"{key}","name":"2K Blonde"}}"#))).unwrap();
    let made = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b","c"]}"#)).unwrap();
    let label = made[0].clone();
    let shapes = render::render(&d, &ctx(), &Options::default());
    for id in ["a", "b", "c"] {
        assert_eq!(name_of(&shapes, id), "", "{id} is named on the shared label, not on its own");
    }
    let words: Vec<String> = shapes.iter().filter(|s| s.el == label).filter_map(|s| match &s.geom {
        Geom::Text { text, .. } => Some(text.clone()),
        _ => None,
    }).collect();
    assert_eq!(words, vec!["4× 2K BLONDE".to_string()]);
    assert_eq!(tie_ends(shapes.iter().filter(|s| s.el == label)), 3, "a line to each lamp");
    // One lets go: it is named on its own again, and the label has two lines.
    apply(&mut d, &op(r#"{"op":"own_label","ids":["c"]}"#)).unwrap();
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "c"), "2× 2K BLONDE");
    assert_eq!(tie_ends(shapes.iter().filter(|s| s.el == label)), 2);
    // Round trip keeps the ties.
    assert_eq!(Diagram::parse(&d.encode()).get("a").unwrap().tie_to, label);
}

#[test]
fn a_ruler_can_go_under_everything() {
    let mut d = plotted(plan_with(r#"[{"kind":"measure","id":"r","x":0,"y":0,"x2":3,"y2":0},{"kind":"set","id":"s","sym":"bed","x":1.5,"y":0,"w":2,"h":1.5}]"#));
    let at = |d: &Diagram| {
        let shapes = render::render(d, &ctx(), &Options::default());
        let r = shapes.iter().position(|s| s.el == "r").unwrap();
        let s = shapes.iter().position(|s| s.el == "s").unwrap();
        r < s
    };
    assert!(!at(&d), "a ruler is drawn over things");
    apply(&mut d, &op(r#"{"op":"update","id":"r","set":{"under":true}}"#)).unwrap();
    assert!(at(&d), "sent under, it is drawn below them");
}

#[test]
fn the_legend_says_what_each_colour_means() {
    // A lamp's colour is its Type (his call, 2026-10-04): a blue written on
    // a mark is not a colour any more.
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron"},{"kind":"light","id":"b","sym":"","mark":"dot","mark_ink":"blue"},
            {"kind":"light","id":"f","sym":"frame","h":1.2}]"#,
    ));
    let rows = plot::colour_rows(&d);
    let roles: Vec<&str> = rows.iter().map(|r| r.0.as_str()).collect();
    assert_eq!(roles, vec!["added", "gripink"]);
    apply(&mut d, &op(r#"{"op":"legend","key":"colour:added","name":"Our Lights"}"#)).unwrap();
    let back = Diagram::parse(&d.encode());
    assert_eq!(plot::colour_rows(&back)[0], ("added".to_string(), "Our Lights".to_string(), true));
}

#[test]
fn a_light_is_a_film_light_a_practical_or_existing() {
    let d = plotted(plan_with(
        r#"[{"kind":"light","id":"f","sym":"","mark":"chevron"},{"kind":"light","id":"p","sym":"","mark":"ring","practical":true,"action":"off"},
            {"kind":"light","id":"e","sym":"","mark":"ring","existing":true}]"#,
    ));
    let looks = plot::looks(&d);
    let ink = |id: &str| looks.iter().find(|(i, _)| i == id).unwrap().1.ink;
    assert_eq!((ink("f"), ink("p"), ink("e")), ("added", "practical", "ink"));
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(name_of(&shapes, "p").ends_with("OFF"), "a practical can be turned off");
    let roles: Vec<String> = plot::colour_rows(&d).into_iter().map(|r| r.1).collect();
    assert_eq!(roles, vec!["Film Lights", "Practicals", "Existing Lights"]);
    assert!(Diagram::parse(&d.encode()).get("p").unwrap().practical);
}

#[test]
fn a_wall_wears_the_label_he_gave_it() {
    let d = plotted(plan_with(r#"[{"kind":"wall","id":"w","points":[[0,0],[4,0]],"label":"Kitchen Wall"},
                          {"kind":"wall","id":"v","points":[[0,2],[4,2]]}]"#));
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "w").to_lowercase(), "kitchen wall");
    assert!(name_of(&shapes, "v").is_empty(), "an unnamed wall stays bare");
}

#[test]
fn a_panel_is_a_box_and_a_tube_is_a_thin_bar() {
    use super::plot::{mark, Look, Mark};
    let width = |m: Mark| {
        let shapes = mark(Look { mark: m, ink: "added", solid: true }, 1.0, 1.2, Ink::Role("added"));
        assert_eq!(shapes.len(), 1, "one body");
        match &shapes[0].geom {
            Geom::Path(segs) => {
                let xs: Vec<f64> = segs
                    .iter()
                    .filter_map(|s| match s {
                        Seg::M(x, _) | Seg::L(x, _) => Some(*x),
                        _ => None,
                    })
                    .collect();
                xs.iter().cloned().fold(f64::MIN, f64::max) - xs.iter().cloned().fold(f64::MAX, f64::min)
            }
            _ => panic!("a path"),
        }
    };
    assert!(width(Mark::DoubleBar) > width(Mark::Bar) * 2.0, "a panel is a good deal deeper than a tube");
}

#[test]
fn one_control_per_job_for_lights() {
    // His call, 2026-10-04: Type is the colour; 2026-10-05: the Name is
    // the light's own, and a shared label never changes a symbol.
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron"},{"kind":"light","id":"b","sym":"","mark":"chevron"},
            {"kind":"light","id":"c","sym":"","mark":"chevron"},{"kind":"light","id":"w","sym":"","mark":"wedge"}]"#,
    ));
    apply(&mut d, &op(r#"{"op":"legend","key":"chevron|added|open","name":"2K Blonde"}"#)).unwrap();
    // Changing Type keeps the name; the colour follows the Type.
    apply(&mut d, &op(r#"{"op":"update","ids":["c"],"set":{"existing":true,"mark_ink":"added"}}"#)).unwrap();
    let lg = plot::legend(&d);
    let c = lg.iter().find(|x| x.look.ink == "ink").expect("an existing chevron in black");
    assert_eq!(c.name, "2K Blonde", "a 2K Blonde made Existing is still a 2K Blonde");
    // Its own words are a note under the symbol's name, never instead of it.
    apply(&mut d, &op(r#"{"op":"update","ids":["b"],"set":{"label":"Uplight Trees"}}"#)).unwrap();
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "b"), "2K BLONDE\nUPLIGHT TREES");
    assert_eq!(lg.iter().filter(|x| x.name == "2K Blonde").map(|x| x.count).sum::<u32>(), 3);
    // A shared label keeps each lamp's symbol and counts each kind.
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"w","name":"Joker 800"}"#)).unwrap();
    let made = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","w"]}"#)).unwrap();
    assert_eq!(d.get("w").unwrap().mark, "wedge");
    let t = d.get(&made[0]).unwrap().clone();
    assert_eq!(render::shared_label_words(&d, &t).unwrap(), "2K BLONDE + JOKER 800");
    // One of them re-marked: that one alone.
    apply(&mut d, &op(r#"{"op":"update","ids":["w"],"set":{"mark":"double-bar"}}"#)).unwrap();
    assert_eq!(d.get("a").unwrap().mark, "chevron");
    // A label deleted lets its lamps go.
    apply(&mut d, &op(&format!(r#"{{"op":"remove","ids":["{}"]}}"#, t.id))).unwrap();
    assert!(d.els.iter().all(|e| e.tie_to.is_empty()));
}

#[test]
fn exteriors_on_a_plot() {
    // His ask, 2026-10-04: streets as two kerbs, open where they cross;
    // a building and an area named inside.
    let d = plotted(plan_with(
        r#"[{"kind":"road","id":"a","x":-20,"y":0,"x2":20,"y2":0,"label":"Douglas Ave"},
            {"kind":"road","id":"b","x":0,"y":-20,"x2":0,"y2":20,"label":"7th Street"},
            {"kind":"set","id":"h","sym":"building","x":-10,"y":-10,"w":8,"h":6,"label":"Bank"},
            {"kind":"set","id":"z","sym":"area","x":10,"y":10,"w":6,"h":6,"label":"Lights off"}]"#,
    ));
    let shapes = render::render(&d, &ctx(), &Options::default());
    let kerbs = shapes.iter().filter(|s| s.el == "a" && s.part == "body" && matches!(s.geom, Geom::Path(_)) && s.fill == Ink::None).count();
    assert_eq!(kerbs, 4, "each kerb is cut in two by the crossing street");
    let words = |id: &str| shapes.iter().filter(|s| s.el == id && s.part == "label").find_map(|s| match &s.geom {
        Geom::Text { text, x, y, .. } => Some((text.clone(), *x, *y)),
        _ => None,
    });
    let (na, xa, _) = words("a").unwrap();
    let (nb, _, yb) = words("b").unwrap();
    assert_eq!((na.as_str(), nb.as_str()), ("DOUGLAS AVE", "7TH STREET"));
    assert!(xa.abs() > 5.0 && yb.abs() > 5.0, "names stay off the crossing");
    assert_eq!(words("h").unwrap().0, "BANK");
    assert_eq!((words("h").unwrap().1, words("h").unwrap().2), (-10.0, -10.0), "a building's name sits inside it");
    assert_eq!(words("z").unwrap().0, "LIGHTS OFF");
    assert_eq!(library::of_sym(symbols::find("building").unwrap()).kind, "Outdoors");
    assert_eq!(El::new(Kind::Road, "r").thick, 9.144);
}

#[test]
fn a_driveway_stops_at_the_building_and_a_group_is_one_favorite() {
    // His ask, 2026-10-04: a curved driveway into a square, grouped as one object.
    let mut d = plotted(plan_with(
        r#"[{"kind":"road","id":"drive","x":0,"y":0,"x2":10,"y2":0,"thick":3.048},
            {"kind":"set","id":"house","sym":"building","x":10,"y":0,"w":6,"h":6,"label":"709"}]"#,
    ));
    let shapes = render::render(&d, &ctx(), &Options::default());
    let reach = shapes
        .iter()
        .filter(|s| s.el == "drive" && s.fill == Ink::None)
        .filter_map(|s| match &s.geom {
            Geom::Path(segs) => Some(
                segs.iter()
                    .filter_map(|g| match g {
                        Seg::M(x, _) | Seg::L(x, _) => Some(*x),
                        _ => None,
                    })
                    .fold(f64::MIN, f64::max),
            ),
            _ => None,
        })
        .fold(f64::MIN, f64::max);
    assert!((reach - 7.0).abs() < 0.05, "the kerbs end at the wall, x = 7: {reach}");
    apply(&mut d, &op(r#"{"op":"group","ids":["drive","house"],"name":"Driveway and House"}"#)).unwrap();
    let pieces: Vec<El> = d.els.clone();
    let kept = super::favorites::keep_group(&pieces, "Driveway and House");
    assert_eq!(super::favorites::name(&kept), "Driveway and House");
    let put = super::favorites::placed_op(&kept, 50.0, 50.0).unwrap();
    let made = apply(&mut d, &put).unwrap();
    assert_eq!(made.len(), 2);
    let copies: Vec<&El> = d.els.iter().filter(|e| made.contains(&e.id)).collect();
    assert!(copies.iter().all(|e| !e.group.is_empty() && e.group == copies[0].group && e.group_name == "Driveway and House"));
    assert!(copies.iter().all(|e| e.id != "f1" && e.id != "f2"), "fresh ids");
    let house = copies.iter().find(|e| e.kind == Kind::Set).unwrap();
    assert!((house.x - 52.5).abs() < 1e-6 && (house.y - 50.0).abs() < 1e-6, "placed about its middle: {},{}", house.x, house.y);
}

#[test]
fn any_line_end_catches_on_any_piece() {
    // His ask, 2026-10-04: lines connect with anything, cleanly.
    let d = plotted(plan_with(
        r#"[{"kind":"road","id":"r","x":0,"y":0,"x2":10,"y2":0},
            {"kind":"set","id":"h","sym":"building","x":20,"y":0,"w":6,"h":4},
            {"kind":"arrow","id":"a","x":0,"y":10,"x2":5,"y2":10}]"#,
    ));
    let at = |x: f64, y: f64| super::walls::snap(&d, x, y, 0.3, 0.0, &[], None);
    assert_eq!(at(10.1, 0.2).at, (10.0, 0.0), "a road's end");
    assert_eq!(at(17.1, 1.0).at, (17.0, 1.0), "a building's side");
    assert_eq!(at(16.9, -2.1).at, (17.0, -2.0), "a building's corner");
    assert_eq!(at(2.5, 10.2).at, (2.5, 10.0), "an arrow's run");
    assert!(!at(30.0, 30.0).caught, "nothing near, nothing caught");
}

#[test]
fn a_string_of_lamps_is_one_piece_with_many_marks() {
    // His ask, 2026-10-04: bulbs along a drive, globes round a table.
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"s","sym":"","mark":"dot","x":0,"y":0,"w":0.3,"h":10,"count":6,"spread":"line","curve":1},
            {"kind":"light","id":"r","sym":"","mark":"ring","x":20,"y":0,"w":4,"h":4,"count":8,"spread":"ring"}]"#,
    ));
    let line = render::string_spots(d.get("s").unwrap()).unwrap();
    assert_eq!(line.len(), 6);
    assert!((line[0].1 + 5.0).abs() < 1e-9 && (line[5].1 - 5.0).abs() < 1e-9, "end to end along its length");
    assert!(line[0].0.abs() < 1e-9 && line[2].0 > 0.8, "bowed in the middle, not at the ends");
    let ring = render::string_spots(d.get("r").unwrap()).unwrap();
    assert_eq!(ring.len(), 8);
    assert!(ring.iter().all(|(x, y)| ((x * x + y * y).sqrt() - 2.0).abs() < 1e-9));
    apply(&mut d, &op(r#"{"op":"legend","key":"dot|added|solid","name":"Bulb"}"#)).unwrap();
    let lg = plot::legend(&d);
    assert_eq!(lg.iter().find(|x| x.name == "Bulb").unwrap().count, 6, "the legend counts every bulb");
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "s"), "6× BULB");
    assert_eq!(Diagram::parse(&d.encode()).get("s").unwrap().spread, "line", "kept");
}

#[test]
fn a_sketch_has_no_grid_scale_lengths_or_sun() {
    // His ask, 2026-10-04: callouts over a location photo or a drawing.
    let mut d = plotted(plan_with(r#"[{"kind":"light","id":"a","sym":"","mark":"chevron"}]"#));
    apply(&mut d, &op(r#"{"op":"settings","set":{"sketch":true}}"#)).unwrap();
    let s = &d.settings;
    assert!(s.sketch && !s.grid && !s.snap && !s.dims && !s.sun);
    let back = Diagram::parse(&d.encode());
    assert!(back.settings.sketch, "kept");
    let pic = super::svg::svg(&back, &ctx(), &Options::default(), &super::svg::Frame::default(), "t");
    assert!(!pic.contains(r#"class="scale""#), "no scale bar on a sketch");
    apply(&mut d, &op(r#"{"op":"settings","set":{"sketch":false}}"#)).unwrap();
    assert!(d.settings.grid && d.settings.snap, "a plan again");
}

#[test]
fn a_shared_label_keeps_name_notes_and_modifiers() {
    // His ask, 2026-10-04: sharing a label must not lose what each lamp said.
    let mut d = plotted(plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron","label":"Uplight Trees","gels":["cto-half"]},
            {"kind":"light","id":"b","sym":"","mark":"chevron","x":3}]"#,
    ));
    apply(&mut d, &op(r#"{"op":"legend","key":"chevron|added|open","name":"2K Blonde"}"#)).unwrap();
    let made = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b"]}"#)).unwrap();
    let t = d.get(&made[0]).unwrap().clone();
    let words = render::shared_label_words(&d, &t).unwrap();
    assert!(words.starts_with("2× 2K BLONDE\nUPLIGHT TREES"), "{words}");
    assert!(words.contains("CTO"), "the gel too: {words}");
    // A note changed on one lamp is the label's.
    apply(&mut d, &op(r#"{"op":"update","ids":["b"],"set":{"label":"Wash Trees"}}"#)).unwrap();
    assert_eq!(d.get("a").unwrap().label, "Wash Trees");
    let words = render::shared_label_words(&d, &t).unwrap();
    assert!(words.contains("WASH TREES") && !words.contains("UPLIGHT"), "{words}");
}

// ---------------------------------------------------------------- Back to Paper, Batch 1

/// Every word the plan writes for a piece, by part.
fn words_of<'a>(shapes: &'a [Shape], id: &str) -> Vec<&'a Shape> {
    shapes.iter().filter(|s| s.el == id && matches!(s.geom, Geom::Text { .. })).collect()
}

#[test]
fn callouts_are_ink_one_size_one_weight() {
    // Back to Paper (his call, 2026-10-04): every name and callout dark,
    // one size, regular weight; colour lives on the mark; a stored size or
    // bold is kept in the film and not drawn.
    let d = plan_with(
        r##"[{"kind":"light","id":"l","sym":"fresnel","x":0,"y":0,"label":"Key","label_size":18,"label_bold":true,"color":"#E5484D","gels":["full-cto"]},
            {"kind":"light","id":"p","sym":"","mark":"ring","x":4,"y":0,"practical":true,"label":"Table Lamp","label_size":7,"label_bold":false},
            {"kind":"light","id":"f","sym":"frame","x":8,"y":0,"h":2.4,"label_size":14},
            {"kind":"light","id":"g","sym":"fso-6x6-lcd","x":12,"y":0,"w":1.8,"h":1.8},
            {"kind":"camera","id":"c","x":0,"y":5,"label":"A","color":"#00AA00","label_size":16},
            {"kind":"set","id":"b","sym":"building","x":6,"y":8,"w":4,"h":3,"label":"Bank","label_size":20},
            {"kind":"set","id":"s","sym":"sofa","x":12,"y":8,"w":2,"h":0.9,"label":"Couch"},
            {"kind":"road","id":"r","x":-5,"y":14,"x2":15,"y2":14,"label":"Douglas Ave","label_size":15}]"##,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    for id in ["l", "p", "f", "g", "c", "b", "s", "r"] {
        let w = words_of(&shapes, id);
        let names: Vec<&&Shape> = w.iter().filter(|s| s.part == "label").collect();
        assert!(!names.is_empty(), "{id} is named");
        for s in names {
            let Geom::Text { size, bold, patch, .. } = &s.geom else { unreachable!() };
            // A building's and an area's name belong to the set: its grey
            // (Ref 1511).
            // A lamp's, a frame's, grip's and a camera's Name in its mark's
            // colour (his call, 2026-10-05); a practical's a deeper gold.
            let want = match id {
                "b" => Ink::Role("ink2"),
                "l" => Ink::hex("#E5484D"),
                "p" => Ink::Role("practicalword"),
                "f" | "g" => Ink::Role("added"),
                "c" => Ink::hex("#00AA00"),
                _ => Ink::Role("ink"),
            };
            assert_eq!(s.fill, want, "{id} in its ink");
            assert_eq!(*size, render::NAME_PT, "{id} one size");
            assert!(!*bold, "{id} regular weight");
            assert!(!*patch, "{id} with nothing behind it");
        }
    }
    // The lamp's second line — its note and its gel — in grey.
    let l = words_of(&shapes, "l").into_iter().find(|s| s.part == "label").unwrap();
    let Geom::Text { text, under, .. } = &l.geom else { unreachable!() };
    assert!(text.contains('\n'), "{text}");
    assert_eq!(*under, Ink::Role("ink2"));
    // Colour lives on the mark: his red on the lamp, his green on the camera.
    assert!(shapes.iter().any(|s| s.el == "l" && s.part == "body" && (s.fill == Ink::hex("#E5484D") || s.stroke == Ink::hex("#E5484D"))));
    assert!(shapes.iter().any(|s| s.el == "c" && s.part == "body" && s.stroke == Ink::hex("#00AA00")));
    // Stored as he left them.
    assert_eq!((d.get("l").unwrap().label_size, d.get("l").unwrap().label_bold), (18.0, true));
    assert_eq!((d.get("p").unwrap().label_size, d.get("p").unwrap().label_bold), (7.0, false));
    let back = Diagram::parse(&d.encode());
    assert_eq!(back.get("b").unwrap().label_size, 20.0);
    assert!(!back.get("p").unwrap().label_bold);
}

#[test]
fn a_shared_label_is_an_ink_callout_with_grey_leaders() {
    let mut d = plan_with(
        r##"[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0,"label":"Uplight"},{"kind":"light","id":"b","sym":"","mark":"chevron","x":6,"y":0}]"##,
    );
    apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b"]}"#)).unwrap();
    let t = d.els.iter().find(|e| e.kind == Kind::Text).unwrap().id.clone();
    // A size and a colour stored on the label stay stored, and are not drawn.
    d.get_mut(&t).unwrap().size = 22.0;
    d.get_mut(&t).unwrap().color = "#2F5DB8".into();
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let label = shapes.iter().find(|s| s.el == t && s.part == "body").expect("its words");
    let Geom::Text { size, bold, patch, under, .. } = &label.geom else { panic!() };
    // Its first line in its lamps' red, not the label's stored blue (2026-10-05).
    assert_eq!((label.fill.clone(), *size, *bold, *patch), (Ink::Role("added"), render::NAME_PT, false, false));
    assert_eq!(*under, Ink::Role("ink2"));
    let ties: Vec<&Shape> = shapes.iter().filter(|s| s.el == t && s.part == "tie").collect();
    assert_eq!(tie_ends(ties.iter().copied()), 2);
    assert!(ties.iter().all(|s| s.stroke == Ink::Role("ink2") || s.fill == Ink::Role("ink2")));
    assert_eq!(d.get(&t).unwrap().size, 22.0);
}

#[test]
fn three_inks_by_default() {
    // Red for what we bring, blue for the camera and its move, grey for the
    // set and what is already there (his call A, 2026-10-04); practicals
    // yellow (his call, 2026-10-05).
    let d = plan_with(
        r##"[{"kind":"light","id":"film","sym":"","mark":"chevron","x":0,"y":0},
            {"kind":"light","id":"prac","sym":"","mark":"ring","x":2,"y":0,"practical":true},
            {"kind":"light","id":"own","sym":"","mark":"dot","x":4,"y":0,"existing":true},
            {"kind":"light","id":"frame","sym":"frame","x":6,"y":0,"h":1.2},
            {"kind":"light","id":"flag","sym":"fso-6x6-lcd","x":8,"y":0,"w":1.8,"h":1.8},
            {"kind":"camera","id":"cam","x":0,"y":4},
            {"kind":"track","id":"trk","x":0,"y":6,"x2":5,"y2":6},
            {"kind":"wall","id":"wall","x":-2,"y":-2,"x2":10,"y2":-2},
            {"kind":"door","id":"door","x":3,"y":-2,"w":0.9},
            {"kind":"set","id":"sofa","sym":"sofa","x":3,"y":9,"w":2,"h":0.9}]"##,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let inks = |id: &str| -> Vec<Ink> {
        shapes
            .iter()
            .filter(|s| s.el == id && s.part == "body" && matches!(s.geom, Geom::Path(_)))
            .flat_map(|s| [s.fill.clone(), s.stroke.clone()])
            .filter(|i| matches!(i, Ink::Role(r) if *r != "paper"))
            .collect()
    };
    for (id, want) in [("film", "added"), ("prac", "practical"), ("frame", "added"), ("flag", "added"), ("cam", "camink"), ("trk", "camink"), ("own", "plan"), ("wall", "plan"), ("door", "plan"), ("sofa", "prop")] {
        let got = inks(id);
        assert!(!got.is_empty() && got.iter().all(|i| *i == Ink::Role(want)), "{id}: {got:?}");
    }
    // Practicals keep their own line in the legend.
    let rows: Vec<String> = plot::colour_rows(&d).into_iter().map(|r| r.0).collect();
    assert!(rows.contains(&"practical".to_string()) && rows.contains(&"added".to_string()), "{rows:?}");
    // Colours stays an override, one category at a time.
    let mut his = d.clone();
    apply(&mut his, &op(r##"{"op":"settings","set":{"colours":{"practical":"#B86A00","existing":"#17171A"}}}"##)).unwrap();
    let shapes = render::render(&his, &Context::default(), &Options::default());
    let has = |id: &str, ink: Ink| shapes.iter().any(|s| s.el == id && (s.fill == ink || s.stroke == ink));
    assert!(has("prac", Ink::hex("#B86A00")) && has("own", Ink::hex("#17171A")));
    assert!(has("film", Ink::Role("added")) && has("frame", Ink::Role("added")), "the rest keep their three inks");
    // The paper palette agrees.
    let paper = |r: &str| super::svg::PAPER.iter().find(|(k, _)| *k == r).unwrap().1;
    assert_ne!(paper("practical"), paper("added"), "practicals are amber");
    assert_eq!(paper("practicalword"), "#A35E00");
    // His practical colour reaches their words too.
    let prac_words = shapes.iter().find(|s| s.el == "prac" && s.part == "label").map(|s| s.fill.clone());
    assert!(prac_words.is_none() || prac_words == Some(Ink::hex("#B86A00")), "{prac_words:?}");
    assert_eq!(paper("gripink"), paper("added"));
    assert_eq!(paper("existing"), paper("plan"));
}

#[test]
fn faded_marks_fade_and_a_thin_track() {
    let d = plan_with(
        r##"[{"kind":"light","id":"mat","sym":"fso-litemat-8","x":0,"y":0,"w":1.6,"h":1.6,"opacity":0.38,"color":"#E5484D"},
            {"kind":"light","id":"tube","sym":"","mark":"bar","mark_fill":"solid","x":3,"y":0,"w":0.3,"h":1.2,"opacity":0.5},
            {"kind":"track","id":"t","x":0,"y":4,"x2":6.7,"y2":4}]"##,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    for id in ["mat", "tube"] {
        let body: Vec<&Shape> = shapes.iter().filter(|s| s.el == id && s.part == "body").collect();
        // Opacity fades the mark (Ref 1505); no overhead dashes.
        assert!(body.iter().all(|s| s.alpha < 1.0), "{id} faded");
        assert!(!body.iter().any(|s| s.dash == "dash"), "{id} not dashed");
    }
    // The track: two thin rails and their ties (2026-10-05: one line with
    // ticks read as a ruler), nothing filled.
    let t: Vec<&Shape> = shapes.iter().filter(|s| s.el == "t" && s.part == "body").collect();
    assert!(t.iter().all(|s| s.fill == Ink::None), "no slab");
    let drawn: Vec<&&Shape> = t.iter().filter(|s| s.stroke == Ink::Role("camink")).collect();
    assert_eq!(drawn.len(), 3, "two rails and their ties");
    assert!(drawn.iter().all(|s| s.line <= 1.4));
    // Its length quiet: grey, small, regular.
    let words = shapes.iter().find(|s| s.el == "t" && s.part == "label").expect("its length");
    let Geom::Text { size, bold, text, .. } = &words.geom else { panic!() };
    assert_eq!((words.fill.clone(), *size, *bold), (Ink::Role("ink2"), render::MEASURE_PT, false));
    assert!(text.contains("22"), "{text}");
    // A Ruler he laid stays, quiet.
    let r = plan_with(r#"[{"kind":"measure","id":"m","x":0,"y":0,"x2":3,"y2":0}]"#);
    let shapes = render::render(&r, &Context::default(), &Options::default());
    let words = shapes.iter().find(|s| s.el == "m" && s.part == "label").expect("its length");
    let Geom::Text { size, bold, .. } = &words.geom else { panic!() };
    assert_eq!((words.fill.clone(), *size, *bold), (Ink::Role("ink2"), render::MEASURE_PT, false));
}

#[test]
fn a_new_plan_starts_without_measurements_and_an_old_one_keeps_them() {
    // Ref 1452: measurements off by default — for a plan not begun. What a
    // stored plan's silence has always meant does not change.
    assert!(!Settings::fresh().dims);
    assert!(Settings::default().dims, "a stored plan with nothing said keeps its lengths");
    assert!(Diagram::parse(r#"{"els":[],"settings":{"grid":false}}"#).settings.dims);
    let mut fresh = Diagram { settings: Settings::fresh(), ..Default::default() };
    apply(&mut fresh, &op(r#"{"op":"add","els":[{"kind":"wall","id":"w","x":0,"y":0,"x2":3,"y2":0}]}"#)).unwrap();
    let back = Diagram::parse(&fresh.encode());
    assert!(!back.settings.dims, "written down, it stays off: {}", fresh.encode());
    // With Dimensions off, a picked wall says nothing; on, it does.
    let picked = Options { sel: vec!["w".into()], ..Default::default() };
    assert!(!render::render(&back, &Context::default(), &picked).iter().any(|s| s.part == "dim"));
    let mut on = back.clone();
    apply(&mut on, &op(r#"{"op":"settings","set":{"dims":true}}"#)).unwrap();
    assert!(render::render(&on, &Context::default(), &picked).iter().any(|s| s.part == "dim"));
    assert!(!render::render(&on, &Context::default(), &Options::default()).iter().any(|s| s.part == "dim"), "only the picked wall");
}

#[test]
fn an_old_plan_keeps_every_stored_value() {
    // A plan stored before Back to Paper: its own sizes, bold, colours,
    // opacity and Dimensions, all kept through a read, a render and a write.
    let text = r##"{"els":[{"id":"l","kind":"light","x":1,"y":2,"sym":"fso-litemat-8","w":1.6,"h":1.6,"label":"Soft Overhead","label_size":14,"label_bold":false,"opacity":0.38,"color":"#E5484D"},{"id":"t","kind":"text","x":0,"y":3,"text":"Key Book Light","size":18,"bold":true,"color":"#C8261C"},{"id":"f","kind":"light","sym":"frame","x":4,"y":0,"h":3.6,"tilt":80,"material":"grid-cloth","label_size":12}],"settings":{"dims":false,"colours":{"plan":"#1A1A1A","practical":"#B86A00"}}}"##;
    let d = Diagram::parse(text);
    let _ = render::render(&d, &Context::default(), &Options::default());
    let _ = super::svg::svg(&d, &Context::default(), &Options::default(), &super::svg::Frame::default(), "o");
    let l = d.get("l").unwrap();
    assert_eq!((l.label_size, l.label_bold, l.opacity, l.color.as_str()), (14.0, false, 0.38, "#E5484D"));
    let t = d.get("t").unwrap();
    assert_eq!((t.size, t.bold, t.color.as_str()), (18.0, true, "#C8261C"));
    assert_eq!(d.get("f").unwrap().label_size, 12.0);
    assert!(!d.settings.dims);
    assert_eq!(d.settings.colours, vec![("plan".to_string(), "#1A1A1A".to_string()), ("practical".to_string(), "#B86A00".to_string())]);
    let again = Diagram::parse(&d.encode());
    assert_eq!(again, d, "written back the same");
    // His hand-set text keeps its colour; its stored 18 and bold stay in
    // the film and it is drawn Large, plain (Ref 1511).
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let words = shapes.iter().find(|s| s.el == "t").unwrap();
    assert_eq!(words.fill, Ink::hex("#C8261C"));
    assert!(matches!(words.geom, Geom::Text { size, bold: false, fixed: true, .. } if (size - render::WORDS_LARGE_PT).abs() < 1e-9));
    // His walls' colour still wins.
    let walls = plan_with(r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":3,"y2":0}]"#);
    let mut walls = walls;
    walls.settings.colours = d.settings.colours.clone();
    assert!(render::render(&walls, &Context::default(), &Options::default()).iter().any(|s| s.el == "w" && s.stroke == Ink::hex("#1A1A1A")));
}

#[test]
fn the_grid_is_faint_dots_a_step_apart() {
    let d = plan_with(r#"[{"kind":"wall","x":0,"y":0,"x2":3,"y2":0}]"#);
    let frame = super::svg::Frame::default();
    let svg = super::svg::svg(&d, &Context::default(), &Options::default(), &frame, "g");
    assert!(svg.contains(r#"<pattern id="g-dots""#) && svg.contains("fill:url(#g-dots)"), "{svg}");
    assert!(!svg.contains("stroke:var(--d-grid"), "no graph paper");
    let scale: f64 = svg.split("data-scale=\"").nth(1).unwrap().split('"').next().unwrap().parse().unwrap();
    let cell = format!(r#"width="{:.3}""#, d.settings.step * scale);
    assert!(svg.contains(&cell), "one dot every grid step: {cell}");
    let mut off = d.clone();
    off.settings.grid = false;
    assert!(!super::svg::svg(&off, &Context::default(), &Options::default(), &frame, "g").contains("-dots"));
}

/// **Quiet fills and an overhead lamp** (Back to Paper, 2026-10-04, round 1
/// of the check): a shape he never filled is an outline — the orange
/// backdrop and the lighting troughs of Let's Bake — one he filled keeps its
/// wash; a lamp he faded keeps its mark and fades (Ref 1505).
#[test]
fn shapes_are_outlines_and_a_faded_lamp_fades() {
    let d = plan_with(
        r##"[{"id":"s","kind":"shape","x":0,"y":0,"w":3,"h":1,"color":"#D97706"},
            {"id":"f","kind":"shape","x":5,"y":0,"w":3,"h":1,"color":"#E5484D","fill":true},
            {"id":"o","kind":"light","sym":"","mark":"double-bar","x":0,"y":4,"w":0.3,"h":1.2,"opacity":0.38},
            {"id":"p","kind":"light","sym":"","mark":"double-bar","x":4,"y":4,"w":0.3,"h":1.2},
            {"id":"h","kind":"set","sym":"table-half-round","x":8,"y":4,"w":1.524,"h":0.762}]"##,
    );
    let shapes = render::render(&d, &ctx(), &Options::default());
    let washes = |id: &str| shapes.iter().filter(|s| s.el == id && s.part == "body" && s.alpha < 1.0).count();
    assert_eq!(washes("s"), 0, "a shape never filled is an outline");
    assert_eq!(washes("f"), 1, "a shape he filled keeps its wash");
    // Stored as he left them: the plain one says nothing of fill, the filled one says so.
    assert!(!d.get("s").unwrap().fill && d.get("f").unwrap().fill);
    assert!(!d.get("s").unwrap().to_json().encode().contains("\"fill\""));
    assert!(Diagram::parse(&d.encode()).get("f").unwrap().fill);
    // The faded panel: the same mark as the full one, faded; its name not.
    let solid = |id: &str| shapes.iter().any(|s| s.el == id && s.part == "body" && matches!(s.fill, Ink::Role(_)) && s.stroke == Ink::None);
    let dashed = |id: &str| shapes.iter().any(|s| s.el == id && s.part == "body" && s.stroke != Ink::None && s.dash == "dash");
    assert!(solid("o") && !dashed("o"), "a faded lamp keeps its mark, no overhead dashes");
    assert!(solid("p") && !dashed("p"), "a lamp at full strength keeps its solid mark");
    assert!(shapes.iter().filter(|s| s.el == "o" && s.part == "body").all(|s| (s.alpha - 0.38).abs() < 1e-6 || s.alpha < 0.38), "the faded lamp fades");
    assert!(shapes.iter().filter(|s| s.el == "o" && s.part == "label").all(|s| s.alpha >= 1.0 - 1e-9), "its name does not");
    assert!((d.get("o").unwrap().opacity - 0.38).abs() < 1e-9);
    // The half round: paper inside its skirted edge, no cloth tint.
    let h: Vec<&Shape> = shapes.iter().filter(|s| s.el == "h" && s.part == "body").collect();
    assert!(!h.is_empty() && h.iter().all(|s| s.fill != Ink::Role("muslin")));
    assert!(h.iter().any(|s| s.fill == Ink::Role("paper") && s.stroke == Ink::Role("prop")));
}

// ---------------------------------------------------------------- Back to Paper, Batch 2

#[test]
fn an_old_plan_reads_the_sheets_settings_as_they_have_always_been() {
    // Stored before the sheet: letter, landscape, legend and notes on, no
    // words, no scale bar — and nothing new written back.
    let d = Diagram::parse(r#"{"els":[],"settings":{"grid":false}}"#);
    let s = &d.settings;
    assert_eq!((s.paper.as_str(), s.orientation.as_str()), ("letter", "landscape"));
    assert!(s.legend && s.notes && !s.scale_bar && s.sheet_notes.is_empty());
    assert!(!d.encode().contains("paper") && !d.encode().contains("sheet_notes"), "{}", d.encode());
    // Set, they keep.
    let mut d = d;
    apply(&mut d, &op(r#"{"op":"settings","set":{"paper":"tabloid","orientation":"portrait","legend":false,"notes":false,"scale_bar":true,"sheet_notes":"All lamps to dimmers"}}"#)).unwrap();
    let back = Diagram::parse(&d.encode());
    assert_eq!(back.settings, d.settings);
    assert_eq!((back.settings.paper.as_str(), back.settings.orientation.as_str()), ("tabloid", "portrait"));
    assert!(!back.settings.legend && !back.settings.notes && back.settings.scale_bar);
    assert_eq!(back.settings.sheet_notes, "All lamps to dimmers");
    // A paper nobody knows reads as letter.
    assert_eq!(Diagram::parse(r#"{"els":[],"settings":{"paper":"napkin"}}"#).settings.paper, "letter");
    assert!(!Settings::fresh().scale_bar, "no scale bar on a new plan either");
}

#[test]
fn a_lamps_name_is_its_own() {
    // His call, 2026-10-15: labels are just what you type — one lamp at a
    // time, never its mirrorland, never another called the same.
    let mut d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"bar","mark_fill":"solid","x":0,"y":0},{"kind":"light","id":"b","sym":"","mark":"bar","mark_fill":"solid","x":3,"y":0},
            {"kind":"light","id":"c","sym":"","mark":"chevron","x":6,"y":0},{"kind":"set","id":"s","sym":"sofa","x":9,"y":0}]"#,
    );
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"a","name":"4' Titan Tube"}"#)).unwrap();
    assert_eq!(plot::lamp_name(d.get("a").unwrap()), "4' Titan Tube");
    assert_eq!(plot::lamp_name(d.get("b").unwrap()), "", "its lookalike stays unlabelled");
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "a"), "4' TITAN TUBE");
    // The same words typed on the other: two lamps, one legend line.
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"b","name":"4' Titan Tube"}"#)).unwrap();
    let lg = plot::legend(&d);
    let tube = lg.iter().find(|x| x.look.mark == plot::Mark::Bar).unwrap();
    assert_eq!((tube.name.as_str(), tube.count), ("4' Titan Tube", 2));
    // Renamed: that lamp alone — no silent rename of the other.
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"b","name":"2' Titan Tube"}"#)).unwrap();
    assert_eq!((d.get("b").unwrap().mark.as_str(), d.get("b").unwrap().mark_fill.as_str()), ("bar", "solid"), "its symbol stays");
    assert_eq!(plot::lamp_name(d.get("a").unwrap()), "4' Titan Tube", "the other keeps its name");
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert_eq!(name_of(&shapes, "b"), "2' TITAN TUBE");
    // Two labels on one symbol: two legend lines.
    let lg = plot::legend(&d);
    let bars: Vec<&plot::Entry> = lg.iter().filter(|x| x.look.mark == plot::Mark::Bar).collect();
    assert_eq!(bars.iter().map(|x| x.name.as_str()).collect::<Vec<_>>(), vec!["4' Titan Tube", "2' Titan Tube"]);
    assert_ne!(bars[0].key, bars[1].key);
    // `only` (the old Name This One) still reads, and is the same.
    apply(&mut d, &op(r#"{"op":"add","els":[{"kind":"light","id":"e","sym":"","mark":"bar","mark_fill":"solid","lamp_name":"4' Titan Tube","x":0,"y":3}]}"#)).unwrap();
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"a","name":"4ft Titan Tube","only":true}"#)).unwrap();
    assert_eq!(plot::lamp_name(d.get("e").unwrap()), "4' Titan Tube");
    // A legend line renamed renames the lamps on it — the line is the thing.
    let key = plot::legend(&d).iter().find(|x| x.name == "2' Titan Tube").unwrap().key.clone();
    apply(&mut d, &op(&format!(r#"{{"op":"legend","key":"{key}","name":"2ft Titan Tube"}}"#))).unwrap();
    assert_eq!(plot::lamp_name(d.get("b").unwrap()), "2ft Titan Tube");
    // An empty name clears it; a set piece is no lamp.
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"c","name":"2K Blonde"}"#)).unwrap();
    assert_eq!(d.get("c").unwrap().mark, "chevron");
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"c","name":""}"#)).unwrap();
    assert!(plot::legend(&d).iter().find(|x| x.ids.contains(&"c".to_string())).unwrap().name.is_empty());
    assert!(apply(&mut d, &op(r#"{"op":"name_lamp","id":"s","name":"Couch"}"#)).is_err());
}

#[test]
fn a_new_lamp_starts_with_no_label_and_an_old_plan_keeps_its_units_names() {
    // His pick, 2026-10-15: a lamp he never named showed its unit's name;
    // that stays, as an ordinary label. Lamps put down after start blank.
    let mut d = Diagram::parse(
        r#"{"els":[{"kind":"light","id":"m","sym":"fso-arri-m18"},{"kind":"light","id":"k","sym":"fso-arri-m18","lamp_name":"Key"},
            {"kind":"light","id":"x","sym":"","mark":"chevron"},{"kind":"light","id":"f","sym":"frame","h":3.6576}],"settings":{"lamp_names":true}}"#,
    );
    assert!(!d.settings.typed_labels);
    plot::own_names(&mut d);
    assert!(d.settings.typed_labels);
    assert_eq!(plot::lamp_name(d.get("m").unwrap()), "Arri M18", "the unit's name, written on");
    assert_eq!(plot::lamp_name(d.get("k").unwrap()), "Key", "his own stays");
    assert_eq!(plot::lamp_name(d.get("x").unwrap()), "", "a bare mark had none and has none");
    assert_eq!(d.get("f").unwrap().lamp_name, "12×12 Medium Diffusion", "a frame's size, written on as its Name (2026-10-17)");
    // Written with the plan, and once only.
    assert!(Diagram::parse(&d.encode()).settings.typed_labels);
    apply(&mut d, &op(r#"{"op":"add","els":[{"kind":"light","id":"n","sym":"fso-arri-m18"}]}"#)).unwrap();
    plot::own_names(&mut d);
    assert_eq!(plot::lamp_name(d.get("n").unwrap()), "", "a new lamp starts blank");
    // He can change the written-on one like any label.
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"m","name":"Back Light"}"#)).unwrap();
    assert_eq!(plot::lamp_name(d.get("m").unwrap()), "Back Light");
    // A new plan starts typed: nothing to write on.
    assert!(Settings::fresh().typed_labels);
    // The gear list still counts the blank one by its unit.
    let g = super::sheet::gear(&d);
    assert!(g.iter().any(|x| x.group == "Lights" && x.name == "Arri M18" && x.count == 1), "{g:?}");
    assert!(g.iter().any(|x| x.name == "Back Light"), "{g:?}");
}

#[test]
fn name_this_one_names_one_lamp_even_on_a_shared_label() {
    let mut d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0},{"kind":"light","id":"b","sym":"","mark":"chevron","x":3,"y":0},
            {"kind":"light","id":"c","sym":"","mark":"chevron","x":6,"y":0}]"#,
    );
    let t = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b"]}"#)).unwrap()[0].clone();
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"a","name":"Joker 800","only":true}"#)).unwrap();
    assert_eq!(plot::lamp_name(d.get("a").unwrap()), "Joker 800");
    assert_eq!(plot::lamp_name(d.get("b").unwrap()), "", "the other lamp on the label keeps its own");
    assert!(d.els.iter().filter(|e| plot::is_lamp(e)).all(|e| e.mark == "chevron" && e.mark_fill.is_empty()), "no symbol moves");
    let words = render::shared_label_words(&d, d.get(&t).unwrap()).unwrap();
    assert!(words.starts_with("JOKER 800"), "{words}");
}

#[test]
fn three_kinds_of_panel_under_one_label_and_one_legend_symbol() {
    // His ask, 2026-10-05: "i might have 3 different kinds of panel lights".
    let mut d = plan_with(
        r#"[{"kind":"light","id":"s1","sym":"","mark":"double-bar","lamp_name":"SkyPanel S60","x":0,"y":0},
            {"kind":"light","id":"s2","sym":"","mark":"double-bar","lamp_name":"SkyPanel S60","x":2,"y":0},
            {"kind":"light","id":"l","sym":"","mark":"double-bar","lamp_name":"LiteMat 4","x":4,"y":0},
            {"kind":"light","id":"x","sym":"","mark":"double-bar","lamp_name":"Astra 1x1","x":6,"y":0}]"#,
    );
    let t = apply(&mut d, &op(r#"{"op":"share_label","ids":["s1","s2","l","x"]}"#)).unwrap()[0].clone();
    assert!(d.els.iter().filter(|e| plot::is_lamp(e)).all(|e| e.mark == "double-bar"), "every one keeps the panel");
    assert_eq!(render::shared_label_words(&d, d.get(&t).unwrap()).unwrap(), "2× SKYPANEL S60 + LITEMAT 4 + ASTRA 1X1");
    let lg = plot::legend(&d);
    assert_eq!(lg.iter().map(|x| (x.name.as_str(), x.count)).collect::<Vec<_>>(), vec![("SkyPanel S60", 2), ("LiteMat 4", 1), ("Astra 1x1", 1)]);
    assert!(lg.iter().all(|x| x.look == lg[0].look));
}

#[test]
fn an_old_plans_symbol_names_move_onto_its_lights() {
    // Saved while names lived on symbols: a named chevron, and two units
    // that stepped apart (the second solid).
    let mut d = Diagram::parse(
        r#"{"els":[{"kind":"light","id":"a","sym":"","mark":"chevron"},{"kind":"light","id":"b","sym":"","mark":"chevron"},
            {"kind":"light","id":"f1","sym":"tungsten-fresnel-1k"},{"kind":"light","id":"f2","sym":"tungsten-fresnel-20k"}],
            "legend":[{"key":"chevron|added|open","name":"2K Blonde"},{"key":"colour:added","name":"Ours"}]}"#,
    );
    assert!(!d.settings.lamp_names);
    let before: Vec<plot::Look> = d.els.iter().map(|e| plot::chosen(e).unwrap_or(plot::Look { mark: plot::Mark::Dot, ink: "added", solid: false })).collect();
    plot::own_names(&mut d);
    assert!(d.settings.lamp_names);
    assert_eq!(plot::lamp_name(d.get("a").unwrap()), "2K Blonde");
    assert_eq!(plot::lamp_name(d.get("b").unwrap()), "2K Blonde");
    // The units' worked-out marks are kept as they were drawn.
    assert_ne!(d.get("f1").unwrap().mark_fill, d.get("f2").unwrap().mark_fill, "still apart");
    assert_eq!(before[0].mark, plot::chosen(d.get("a").unwrap()).unwrap().mark);
    // Symbol names spent; a colour's meaning stays.
    assert_eq!(d.legend.iter().map(|x| x.key.as_str()).collect::<Vec<_>>(), vec!["colour:added"]);
    // Once only.
    d.get_mut("a").unwrap().lamp_name.clear();
    plot::own_names(&mut d);
    assert_eq!(plot::lamp_name(d.get("a").unwrap()), "");
    // Written with the plan.
    assert!(Diagram::parse(&d.encode()).settings.lamp_names);
}

#[test]
fn every_way_of_sharing_a_label_runs_one_rule() {
    // The Connector tool's call — the label and one more lamp — and a label
    // picked with lamps: the joining lamp keeps its own symbol (2026-10-05),
    // and its note and gels merge with theirs.
    let mut d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"bar","mark_fill":"solid","x":0,"y":0,"label":"Uplight on BG"},{"kind":"light","id":"b","sym":"","mark":"bar","mark_fill":"solid","x":2,"y":0},
            {"kind":"light","id":"n","sym":"","mark":"wedge","x":6,"y":0,"label":"Kicker","gels":["cto-half"]}]"#,
    );
    let label = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b"]}"#)).unwrap()[0].clone();
    apply(&mut d, &op(&format!(r#"{{"op":"share_label","ids":["{label}","n"]}}"#))).unwrap();
    let n = d.get("n").unwrap();
    assert_eq!((n.mark.as_str(), n.tie_to.as_str()), ("wedge", label.as_str()), "its own symbol, the label's tie");
    for id in ["a", "b", "n"] {
        let e = d.get(id).unwrap();
        assert_eq!(e.label, "Uplight on BG · Kicker", "{id}");
        assert_eq!(e.gels, vec!["cto-half".to_string()], "{id}");
    }
    // Two lamps picked, one already on a label: the other joins that label.
    apply(&mut d, &op(r#"{"op":"add","els":[{"kind":"light","id":"m","sym":"","mark":"dot","x":9,"y":0}]}"#)).unwrap();
    let texts = d.els.iter().filter(|e| e.kind == Kind::Text).count();
    let made = apply(&mut d, &op(r#"{"op":"share_label","ids":["m","a"]}"#)).unwrap();
    assert_eq!(made, vec![label.clone()]);
    assert_eq!(d.els.iter().filter(|e| e.kind == Kind::Text).count(), texts, "no second label");
    assert_eq!(d.get("m").unwrap().mark, "dot");
}

#[test]
fn a_shared_label_obeys_labels_and_hide_label() {
    let mut d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0},{"kind":"light","id":"b","sym":"","mark":"chevron","x":6,"y":0},{"kind":"light","id":"c","sym":"","mark":"chevron","x":3,"y":4}]"#,
    );
    let t = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b","c"]}"#)).unwrap()[0].clone();
    let drawn = |d: &Diagram| render::render(d, &ctx(), &Options::default()).into_iter().filter(|s| s.el == t).collect::<Vec<_>>();
    assert_eq!(tie_ends(drawn(&d).iter()), 3);
    // One lamp's own label hidden (fix round 2): its own callout is not
    // worn while it shares this one, so its line stays — one set of words
    // with a fine line to each lamp.
    apply(&mut d, &op(r#"{"op":"update","ids":["c"],"set":{"label_hidden":true}}"#)).unwrap();
    assert_eq!(tie_ends(drawn(&d).iter()), 3);
    // The label hidden: no words, no lines; the ties stay in the film.
    apply(&mut d, &op(&format!(r#"{{"op":"update","ids":["{t}"],"set":{{"label_hidden":true}}}}"#))).unwrap();
    assert!(drawn(&d).is_empty());
    assert_eq!(d.get("a").unwrap().tie_to, t);
    apply(&mut d, &op(&format!(r#"{{"op":"update","ids":["{t}"],"set":{{"label_hidden":false}}}}"#))).unwrap();
    assert!(!drawn(&d).is_empty());
    // View › Labels off: gone too.
    apply(&mut d, &op(r#"{"op":"settings","set":{"labels":false}}"#)).unwrap();
    assert!(drawn(&d).is_empty());
}

#[test]
fn words_come_in_the_sheets_two_sizes_and_old_words_keep_theirs_stored() {
    // Ref 1511: Call Her Back's room names, stored at 13, were drawn at 19.5
    // points and dwarfed the backyard. Words are drawn Regular (a name's
    // size) or Large (a step over it), plain; Large ones he left uncoloured
    // name places, in the set's grey.
    let d = plan_with(
        r##"[{"kind":"text","id":"old","text":"Living Room","size":13,"bold":true},{"kind":"text","id":"r","text":"Key","size":6.6667},
            {"kind":"text","id":"l","text":"Key","size":9.3333},{"kind":"text","id":"red","text":"Red Curtain","size":10,"color":"#E5484D"}]"##,
    );
    let shapes = render::render(&d, &ctx(), &Options { scale: 30.0, ..Default::default() });
    let drawn = |id: &str| match shapes.iter().find(|s| s.el == id) {
        Some(s) => match &s.geom {
            Geom::Text { size, fixed: true, bold, .. } => (*size, *bold, s.fill.clone()),
            other => panic!("{id}: {other:?}"),
        },
        None => panic!("{id} not drawn"),
    };
    assert_eq!(drawn("old"), (render::WORDS_LARGE_PT, false, Ink::Role("ink2")), "a room's name: Large, plain, grey");
    assert_eq!(drawn("r"), (render::NAME_PT, false, Ink::Role("ink")), "Regular is a name's size, in ink");
    assert_eq!(drawn("l").0, render::WORDS_LARGE_PT);
    assert_eq!(drawn("red"), (render::WORDS_LARGE_PT, false, Ink::hex("#E5484D")), "his colour wins");
    assert!(render::WORDS_LARGE_PT < 15.0, "under the sheet's title");
    // Stored as they were.
    assert_eq!((d.get("old").unwrap().size, d.get("old").unwrap().bold), (13.0, true));
    assert!((render::words_pt(render::WORDS_REGULAR) - render::NAME_PT).abs() < 1e-9);
    assert!(!render::words_large(render::WORDS_REGULAR) && render::words_large(render::WORDS_LARGE) && render::words_large(14.0));
}

#[test]
fn the_sheet_letters_a_shrunk_plan_smaller_with_a_floor() {
    // Ref 1511. A room (Let's Bake 8, 38 points to the metre on Letter):
    // callouts about 8 points, marks the size against the plan the screen
    // gave them in Batch 1 (a third of a metre).
    let room = render::page_lettering(38.0);
    assert!((render::NAME_PT * room.words - 7.9).abs() < 0.15, "{room:?}");
    assert!((plot::MARK_PT * room.marks / 38.0 - plot::MARK_PT / render::NOMINAL_SCALE).abs() < 1e-9);
    // A backyard (Call Her Back 14, 20 points to the metre): words at their
    // floor, marks at theirs, both readable.
    let yard = render::page_lettering(19.9);
    assert!((render::NAME_PT * yard.words - render::PAGE_WORDS_MIN_PT).abs() < 1e-9, "{yard:?}");
    assert!((plot::MARK_PT * yard.marks - render::PAGE_MARK_MIN_PT).abs() < 1e-9);
    // Never larger than a callout's 8 points or a mark's full 20, however
    // large the plan is drawn; easing, never jumping.
    let big = render::page_lettering(400.0);
    assert!((render::NAME_PT * big.words - render::PAGE_WORDS_PT).abs() < 1e-9 && (big.marks - 1.0).abs() < 1e-9);
    let mut was = 0.0;
    for k in 1..200 {
        let w = render::page_lettering(k as f64).words;
        assert!(w >= was - 1e-12);
        was = w;
    }
    // Off the sheet, nothing changes.
    assert_eq!(render::lettering(&Options::default()), render::Lettering { words: 1.0, marks: 1.0 });
    // On the plan: a name and a mark at the sheet's size.
    let d = plan_with(r#"[{"kind":"light","id":"l","sym":"","mark":"chevron","x":0,"y":0,"label":"Key"},{"kind":"wall","id":"w","x":-20,"y":-10,"x2":20,"y2":-10}]"#);
    let shapes = render::render(&d, &ctx(), &Options { scale: 19.9, page: true, paper: true, ..Default::default() });
    let name = shapes.iter().find(|s| s.el == "l" && s.part == "label").expect("named");
    assert!(matches!(name.geom, Geom::Text { size, .. } if (size - render::PAGE_WORDS_MIN_PT).abs() < 1e-9));
    assert!((render::mark_m(&Options { scale: 19.9, page: true, ..Default::default() }) - render::PAGE_MARK_MIN_PT / 19.9).abs() < 1e-9);
}

#[test]
fn the_sheet_fits_the_plan_with_its_words_and_the_sun_inside_the_window() {
    // Ref 1511: on a backyard the sun's time hung off the plan's window and
    // over the legend. Every word the plan draws stands inside its window.
    use super::sheet::Ask;
    let mut d = plan_with(
        r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":40,"y2":0},{"kind":"wall","id":"w2","x":0,"y":0,"x2":0,"y2":25},
            {"kind":"light","id":"l","sym":"","mark":"bar","x":39,"y":24,"label":"Glowing Bounce into Ceiling"},
            {"kind":"text","id":"t","x":20,"y":12,"text":"Living Room","size":13}]"#,
    );
    d.settings.sun = true;
    d.settings.sun_date = "2026-11-02".into();
    d.settings.sun_time = "15:30".into();
    let mut c = ctx();
    c.place = Some((34.0, -118.4));
    let s = super::sheet::layout(&d, &c, &super::sheet::Title::default(), &[], &Ask::default());
    let shapes = super::sheet::plan_shapes(&d, &c, &s, 1);
    assert!(shapes.iter().any(|x| x.part == "sun"), "the sun is drawn");
    let win = s.window;
    for x in &shapes {
        if let Geom::Text { x: tx, y: ty, text, size, fixed: true, anchor, .. } = &x.geom {
            let (w, h) = render::words_box_pt(&text.to_uppercase(), *size);
            let (px, py) = (s.ox + tx * s.scale, s.oy + ty * s.scale);
            let x1 = match *anchor {
                "start" => px,
                "end" => px - w,
                _ => px - w / 2.0,
            };
            assert!(x1 >= win.x - 0.5 && x1 + w <= win.x + win.w + 0.5 && py - h / 2.0 >= win.y - 0.5 && py + h / 2.0 <= win.y + win.h + 0.5, "{text} inside the window");
        }
    }
}

#[test]
fn a_click_takes_what_is_drawn() {
    // Ref 1511: a lamp is drawn as its mark, larger than a small fixture's
    // footprint; Words as their words. A click on what is drawn takes it.
    let d = plan_with(
        r#"[{"kind":"light","id":"l","sym":"","mark":"chevron","x":0,"y":0,"w":0.1,"h":0.1},
            {"kind":"text","id":"t","x":5,"y":0,"text":"Living Room","size":13},
            {"kind":"camera","id":"c","x":0,"y":5,"w":0.1,"h":0.1}]"#,
    );
    let opt = Options { scale: 20.0, page: true, ..Default::default() };
    let m = render::mark_m(&opt);
    assert!(m > 0.3, "a mark of {m} m");
    assert_eq!(hit(&d, m * 0.45, 0.0, 0.0, 1), None, "the footprint alone misses");
    assert_eq!(hit_drawn(&d, m * 0.45, 0.0, 0.0, 1, &opt).as_deref(), Some("l"));
    assert_eq!(hit_drawn(&d, m * 0.5, 5.0, 0.0, 1, &opt).as_deref(), Some("c"));
    // "LIVING ROOM" at Large, 6.5 × 1.25 points at 20 to the metre: about
    // two metres across.
    let (w, _) = render::drawn_size(d.get("t").unwrap(), &d, &opt).unwrap();
    assert!(w > 1.6 && w < 3.0, "{w}");
    assert_eq!(hit_drawn(&d, 5.0 + w * 0.45, 0.0, 0.0, 1, &opt).as_deref(), Some("t"));
    assert_eq!(hit_drawn(&d, 5.0 + w * 0.6, 0.0, 0.0, 1, &opt), None);
    // A pick's outline goes round it: the wire says how big it is drawn.
    let wire = super::wire::payload(&d, &ctx(), &opt);
    assert!(wire.contains(r#""drawn":["#), "{}", &wire[..200.min(wire.len())]);
}

#[test]
fn a_lamp_says_its_name_and_note_on_the_wire() {
    let mut d = plan_with(r#"[{"kind":"light","id":"a","sym":"","mark":"bar","mark_fill":"solid","count":4,"label":"Uplight on BG","gels":["cto-half"]}]"#);
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"a","name":"4' Titan Tube"}"#)).unwrap();
    let wire = super::wire::payload(&d, &ctx(), &Options::default());
    let v = json::parse(&wire).unwrap();
    let a = v.get("els").and_then(|e| e.as_array()).unwrap().iter().find(|e| e.str_field("id") == "a").unwrap();
    assert_eq!(a.str_field("lamp_name"), "4' Titan Tube");
    let lines: Vec<String> = a.get("label_lines").and_then(|l| l.as_array()).unwrap().iter().filter_map(|l| l.as_str().map(String::from)).collect();
    assert_eq!(lines[0], "4× 4' Titan Tube");
    assert!(lines[1].starts_with("Uplight on BG · ") && lines[1].contains("CTO"), "{lines:?}");
    let legend = v.get("legend").and_then(|l| l.as_array()).unwrap();
    assert_eq!(legend[0].get("ids").and_then(|i| i.as_array()).map(|a| a.len()), Some(1));
    let st = v.get("settings").unwrap();
    assert_eq!(st.str_field("paper"), "letter");
    assert_eq!(st.get("scale_bar").and_then(|b| b.as_bool()), Some(false));
}

/// A plan with three Types, a frame, a camera and an overhead lamp, laid on
/// a sheet.
fn sheet_plan() -> Diagram {
    plan_with(
        r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":6,"y2":0},{"kind":"wall","id":"w2","x":0,"y":0,"x2":0,"y2":4},
            {"kind":"light","id":"t1","sym":"","mark":"bar","mark_fill":"solid","x":1,"y":1,"count":2},{"kind":"light","id":"t2","sym":"","mark":"bar","mark_fill":"solid","x":2,"y":1},
            {"kind":"light","id":"up","sym":"","mark":"bar","mark_fill":"solid","x":3,"y":1,"opacity":0.4},
            {"kind":"light","id":"p","sym":"","mark":"ring","x":4,"y":2,"practical":true},{"kind":"light","id":"x","sym":"","mark":"dot","x":5,"y":3,"existing":true},
            {"kind":"light","id":"f1","sym":"frame","x":2,"y":3,"h":3.6576},{"kind":"light","id":"f2","sym":"frame","x":3,"y":3,"h":3.6576},
            {"kind":"camera","id":"cam","x":1,"y":3,"lens":35}]"#,
    )
}

fn laid(d: &Diagram, ask: &super::sheet::Ask) -> super::sheet::Sheet {
    let title = super::sheet::Title { scene: "8 · Style & Spice".into(), film: "Let's Bake · Day 2".into() };
    let shots = vec![super::sheet::ShotLine { camera: "cam".into(), number: "8A".into(), ink: String::new(), facts: vec!["Wide".into(), "35mm".into()] }];
    super::sheet::layout(d, &ctx(), &title, &shots, ask)
}

fn sheet_words(s: &super::sheet::Sheet) -> Vec<String> {
    s.furniture.iter().filter_map(|f| match &f.geom {
        Geom::Text { text, .. } => Some(text.clone()),
        _ => None,
    }).collect()
}

#[test]
fn the_sheet_has_a_title_a_window_a_legend_and_shots() {
    use super::sheet::{self, Ask};
    let mut d = sheet_plan();
    for id in ["t1", "t2", "up"] {
        apply(&mut d, &op(&format!(r#"{{"op":"name_lamp","id":"{id}","name":"4' Titan Tube"}}"#))).unwrap();
    }
    let s = laid(&d, &Ask::default());
    assert_eq!((s.w, s.h), (792.0, 612.0), "letter, landscape");
    let words = sheet_words(&s);
    assert!(words.contains(&"8 · STYLE & SPICE".to_string()), "{words:?}");
    assert!(words.contains(&"LET'S BAKE · DAY 2".to_string()), "{words:?}");
    assert!(words.contains(&"N".to_string()), "north");
    // Grouped by Type, heads because there are three; each line its name and count.
    for w in ["LEGEND", "FILM LIGHTS", "PRACTICALS", "EXISTING", "4' TITAN TUBE ×4", "UNLABELED ×1", "FRAMES", "12×12 MEDIUM DIFFUSION ×2", "SHOTS", "8A"] {
        assert!(words.iter().any(|x| x == w), "{w} in {words:?}");
    }
    // No scale bar, no scale written (his call G).
    assert!(!s.bar && s.stated.is_empty());
    assert!(!words.iter().any(|w| w.contains("SCALE") || w.ends_with(" FT")), "{words:?}");
    // The window sits inside the margins, above the band, and holds the plan.
    let win = s.window;
    assert!(win.x >= sheet::MARGIN && win.x + win.w <= s.w - sheet::MARGIN + 1e-9 && win.y + win.h <= s.h - sheet::MARGIN);
    let at = |x: f64, y: f64| (s.ox + x * s.scale, s.oy + y * s.scale);
    for (x, y) in [(0.0, 0.0), (6.0, 4.0)] {
        let (px, py) = at(x, y);
        assert!(win.contains(px, py), "({x},{y}) at ({px},{py}) in {win:?}");
    }
    // A legend line picks every lamp of its kind, a faded one too (Ref 1505).
    let tubes = s.items.iter().find(|i| i.kind == "legend" && i.count == 4).unwrap();
    assert_eq!(tubes.ids, vec!["t1".to_string(), "t2".to_string(), "up".to_string()]);
    let hit = sheet::item_at(&s, tubes.rect.x + 20.0, tubes.rect.y + tubes.rect.h / 2.0).unwrap();
    assert_eq!(hit.ids, tubes.ids);
    assert!(s.items.iter().any(|i| i.kind == "head" && i.key == "colour:practical"));
    assert!(s.items.iter().any(|i| i.kind == "frames" && i.ids.len() == 2));
    assert!(s.items.iter().any(|i| i.kind == "shot" && i.ids == vec!["cam".to_string()]));
    // The gear list: names times Count, frames by size and skin; the
    // location's own not brought.
    let tubes = s.gear.iter().find(|g| g.name == "4' Titan Tube").unwrap();
    assert_eq!((tubes.group, tubes.count), ("Lights", 4));
    assert!(s.gear.iter().any(|g| g.group == "Practicals"));
    assert!(s.gear.iter().any(|g| g.group == "Frames" && g.count == 2));
    assert!(!s.gear.iter().any(|g| g.group == "Existing"));
}

#[test]
fn the_legend_draws_a_faded_lamp_plainly() {
    // Ref 1505: no Overhead line and no dashes; the legend draws the mark plainly.
    let d = plan_with(r#"[{"kind":"light","id":"m","sym":"","mark":"double-bar","mark_fill":"solid","x":0,"y":0,"opacity":0.38}]"#);
    let lg = plot::legend(&d);
    assert_eq!(lg[0].count, 1);
    let s = laid(&d, &super::sheet::Ask::default());
    let marks: Vec<&Shape> = s.furniture.iter().filter(|f| matches!(f.geom, Geom::Path(_)) && f.stroke != Ink::None && f.stroke != Ink::Role("tagline") && f.stroke != Ink::Role("ink")).collect();
    assert!(!marks.iter().any(|m| m.dash == "dash"), "plain in the legend");
    assert!(!s.furniture.iter().any(|f| matches!(&f.geom, Geom::Text { text, .. } if text.contains("OVERHEAD"))));
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(!shapes.iter().any(|x| x.el == "m" && x.dash == "dash"), "nor on the plan");
}

#[test]
fn an_upright_mark_stays_inside_its_legend_row() {
    // Ref 1509: a bar or panel is drawn upright, as tall as the mark is
    // wide, and a row is barely taller: it ran into the line below.
    use super::sheet::Ask;
    let d = plan_with(
        r#"[{"kind":"light","id":"b","sym":"","mark":"bar","mark_fill":"open","x":0,"y":0},
            {"kind":"light","id":"d","sym":"","mark":"double-bar","mark_fill":"solid","x":1,"y":0},
            {"kind":"light","id":"e","sym":"","mark":"double-bar","mark_fill":"open","x":2,"y":0},
            {"kind":"light","id":"c","sym":"","mark":"chevron","mark_fill":"solid","x":3,"y":0}]"#,
    );
    let s = laid(&d, &Ask::default());
    let rows: Vec<_> = s.items.iter().filter(|i| i.kind == "legend").collect();
    assert!(rows.len() >= 3, "{} legend rows", rows.len());
    for row in rows {
        let (top, foot) = (row.rect.y, row.rect.y + row.rect.h);
        let mut seen = 0;
        for f in s.furniture.iter().filter(|f| f.part == "sheet" && matches!(f.geom, Geom::Path(_))) {
            let Some(b) = render::bounds(std::slice::from_ref(f)) else { continue };
            let mid = (b.y1 + b.y2) / 2.0;
            if b.x1 < row.rect.x - 1.0 || b.x2 > row.rect.x + 12.0 || mid < top || mid > foot {
                continue;
            }
            seen += 1;
            let half = f.line / 2.0;
            assert!(b.y1 - half >= top && b.y2 + half <= foot, "{}'s mark runs out of its row: {:.1}..{:.1} against {top:.1}..{foot:.1}", row.name, b.y1 - half, b.y2 + half);
        }
        assert!(seen > 0, "{} has a mark", row.name);
    }
}

#[test]
fn the_scale_bar_and_the_notes_show_only_when_asked() {
    use super::sheet::Ask;
    let mut d = sheet_plan();
    // Nothing typed: no Notes on paper; on screen a faint one to click.
    let paper = laid(&d, &Ask::default());
    assert!(!paper.items.iter().any(|i| i.kind == "notes"));
    let screen = laid(&d, &Ask { screen: true, ..Default::default() });
    let notes = screen.items.iter().find(|i| i.kind == "notes").expect("on screen");
    assert!(screen.furniture.iter().any(|f| matches!(&f.geom, Geom::Text { text, .. } if text == "NOTES") && f.alpha < 1.0), "faint");
    assert!(notes.rect.w > 0.0);
    apply(&mut d, &op(r#"{"op":"settings","set":{"sheet_notes":"All lamps to dimmers"}}"#)).unwrap();
    let s = laid(&d, &Ask::default());
    assert!(sheet_words(&s).contains(&"ALL LAMPS TO DIMMERS".to_string()));
    assert!(s.items.iter().any(|i| i.kind == "notes"));
    // Notes and the legend turned off.
    apply(&mut d, &op(r#"{"op":"settings","set":{"notes":false,"legend":false}}"#)).unwrap();
    let s = laid(&d, &Ask::default());
    assert!(!s.items.iter().any(|i| matches!(i.kind, "notes" | "legend" | "head" | "frames")));
    // The bar: a standard scale, written in the title.
    apply(&mut d, &op(r#"{"op":"settings","set":{"scale_bar":true}}"#)).unwrap();
    let s = laid(&d, &Ask::default());
    assert!(s.bar && s.stated.ends_with("= 1'-0\""), "{}", s.stated);
    assert!(super::sheet::standard_scale(s.scale + 1e-6, "ft").0 == s.scale);
    let words = sheet_words(&s);
    assert!(words.iter().any(|w| w.contains("SCALE ")) && words.iter().any(|w| w.ends_with(" FT")), "{words:?}");
    // Export's own switch wins; a sketch never has one.
    assert!(!laid(&d, &Ask { scale_bar: Some(false), ..Default::default() }).bar);
    apply(&mut d, &op(r#"{"op":"settings","set":{"sketch":true}}"#)).unwrap();
    assert!(!laid(&d, &Ask::default()).bar);
    // Metres say a ratio.
    let mut m = sheet_plan();
    apply(&mut m, &op(r#"{"op":"settings","set":{"units":"m","scale_bar":true}}"#)).unwrap();
    assert!(laid(&m, &Ask::default()).stated.starts_with("1:"));
}

#[test]
fn the_sheet_follows_its_paper_and_holds_still() {
    use super::sheet::Ask;
    let mut d = sheet_plan();
    apply(&mut d, &op(r#"{"op":"settings","set":{"paper":"tabloid","orientation":"portrait"}}"#)).unwrap();
    let s = laid(&d, &Ask::default());
    assert_eq!((s.w, s.h, s.landscape), (792.0, 1224.0, false));
    // Export's way round wins.
    let l = laid(&d, &Ask { landscape: Some(true), ..Default::default() });
    assert_eq!((l.w, l.h), (1224.0, 792.0));
    // A small change at the plan's edge leaves the scale where it was.
    let d = sheet_plan();
    let before = laid(&d, &Ask::default()).scale;
    let mut nudged = d.clone();
    apply(&mut nudged, &op(r#"{"op":"update","ids":["w"],"set":{"x2":6.02}}"#)).unwrap();
    assert_eq!(laid(&nudged, &Ask::default()).scale, before);
    assert!((super::sheet::steady(37.0) - 37.0).abs() / 37.0 < 0.05 && super::sheet::steady(37.0) <= 37.0);
}

#[test]
fn the_sheet_as_a_picture_carries_the_plan_and_its_furniture() {
    use super::sheet::{self, Ask};
    let d = sheet_plan();
    let ask = Ask::default();
    let s = laid(&d, &ask);
    let frame = super::svg::Frame { fades: false, grid: false, scale_bar: false, ..Default::default() };
    let pic = sheet::svg_of(&d, &ctx(), &s, &ask, 0.0, false, &frame, "t");
    assert!(pic.starts_with("<svg class=\"dia sheet\"") && pic.contains("viewBox=\"0.00 0.00 792.00 612.00\""));
    assert!(pic.contains("data-el=\"t1\""), "the plan's pieces");
    assert!(pic.contains(">LEGEND<") && pic.contains(">8 · STYLE &amp; SPICE<"));
    assert!(!pic.contains("data-part=\"north\""), "north once, in the title");
    // Without its margin, for the Mac's cutter.
    let cut = sheet::svg_of(&d, &ctx(), &s, &ask, 0.0, true, &frame, "t");
    assert!(cut.contains("viewBox=\"36.00 36.00 720.00 539.00\"") && cut.contains("width=\"720.0\""));
    // The sheet for the Mac: its paper, window, scale, shapes and picks.
    let v = json::parse(&sheet::json(&s)).unwrap();
    assert_eq!(v.get("w").and_then(|x| x.as_f64()), Some(792.0));
    assert!(v.get("window").and_then(|x| x.as_array()).map(|a| a.len()) == Some(4));
    assert!(v.get("shapes").and_then(|x| x.as_array()).map(|a| !a.is_empty()).unwrap_or(false));
    assert!(v.get("items").and_then(|x| x.as_array()).map(|a| a.iter().any(|i| i.str_field("kind") == "legend")).unwrap_or(false));
    assert!(v.get("gear").is_some());
}

#[test]
fn labels_off_takes_every_name_but_keeps_words_and_lengths() {
    // The checker's case (Batch 2, fix round 1): View › Labels off left a
    // person's and a shape's names on the plan.
    let mut d = plan_with(
        r#"[{"kind":"cast","id":"p","x":0,"y":0,"label":"Talent"},
            {"kind":"shape","id":"s","sym":"rect","x":4,"y":0,"w":2,"h":1,"label":"Lighting Trough"},
            {"kind":"set","id":"t","sym":"table","x":8,"y":0,"w":1,"h":1,"label":"Table"},
            {"kind":"arrow","id":"a","x":0,"y":3,"x2":3,"y2":3,"label":"To Window"},
            {"kind":"text","id":"w","text":"Red Curtain","x":0,"y":6},
            {"kind":"measure","id":"m","x":0,"y":8,"x2":3,"y2":8}]"#,
    );
    let names = |d: &Diagram| {
        render::render(d, &ctx(), &Options::default()).into_iter().filter(|s| s.part == "label" && ["p", "s", "t", "a"].contains(&s.el.as_str())).count()
    };
    assert!(names(&d) >= 4, "each piece wears its name");
    apply(&mut d, &op(r#"{"op":"settings","set":{"labels":false}}"#)).unwrap();
    assert_eq!(names(&d), 0, "View › Labels off: no names at all");
    let shapes = render::render(&d, &ctx(), &Options::default());
    assert!(shapes.iter().any(|s| s.el == "w" && matches!(s.geom, Geom::Text { .. })), "Words stay");
    assert!(shapes.iter().any(|s| s.el == "m" && matches!(s.geom, Geom::Text { .. })), "a ruler writes its length");
    // Nothing stored is lost.
    assert_eq!(d.get("p").unwrap().label, "Talent");
    assert_eq!(d.get("s").unwrap().label, "Lighting Trough");
}

#[test]
fn the_sheet_leaves_room_at_its_foot_for_the_running_line() {
    // Export and Print stamp the date and Page 1 of 1 under every page, about
    // 24 to 34 points up from the paper's edge; the legend's last line once
    // sat right on it (Batch 2, fix round 1).
    use super::sheet::{Ask, MARGIN};
    let d = sheet_plan();
    let s = laid(&d, &Ask::default());
    let lowest = s.items.iter().map(|i| i.rect.y + i.rect.h).fold(0.0, f64::max);
    assert!(lowest > 0.0);
    assert!(s.h - lowest >= MARGIN + 12.0 - 1e-6, "the band ends {} points above the paper's edge", s.h - lowest);
    // No band at all: the plan's window keeps clear of it as well.
    let mut bare = sheet_plan();
    apply(&mut bare, &op(r#"{"op":"settings","set":{"legend":false,"notes":false}}"#)).unwrap();
    let s = laid(&bare, &Ask { key: false, ..Ask::default() });
    assert!(s.h - (s.window.y + s.window.h) >= MARGIN + 12.0 - 1e-6);
}

#[test]
fn a_shared_label_ties_lamps_whose_own_labels_were_hidden() {
    // Scene 8 (Batch 2, fix round 2): four tubes, each label hidden for his
    // hand-built callout, shared one label — and it floated with no lines.
    let mut d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"bar","x":0,"y":0,"label_hidden":true},{"kind":"light","id":"b","sym":"","mark":"bar","x":2,"y":0,"label_hidden":true},
            {"kind":"light","id":"c","sym":"","mark":"bar","x":2,"y":2,"label_hidden":true}]"#,
    );
    let t = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b","c"]}"#)).unwrap()[0].clone();
    let ties = tie_ends(render::render(&d, &ctx(), &Options::default()).iter().filter(|s| s.el == t));
    assert_eq!(ties, 3, "a line to every lamp");
    // Their own hidden flags are kept for when they have their own labels again.
    assert!(d.get("a").unwrap().label_hidden);
}

#[test]
fn a_new_shared_label_lands_clear_of_other_words() {
    // Scene 8 (Batch 2, fix round 2): Share Label put its words just over
    // the lamps, on top of three other names at once.
    let mut d = plan_with(
        r#"[{"kind":"light","id":"a","sym":"","mark":"bar","x":0,"y":0},{"kind":"light","id":"b","sym":"","mark":"bar","x":2,"y":0},
            {"kind":"text","id":"w1","text":"Lighting Trough","x":1,"y":-1.2},
            {"kind":"text","id":"w2","text":"Red Curtain BG","x":1,"y":-1.6},
            {"kind":"text","id":"w3","text":"Arri S60C","x":1,"y":-0.8}]"#,
    );
    apply(&mut d, &op(r#"{"op":"name_lamp","id":"a","name":"Astera Tube"}"#)).unwrap();
    let t = apply(&mut d, &op(r#"{"op":"share_label","ids":["a","b"]}"#)).unwrap()[0].clone();
    let shapes = render::render(&d, &ctx(), &Options::default());
    let k = render::NOMINAL_SCALE;
    let boxed = |s: &Shape| match &s.geom {
        Geom::Text { x, y, text, size, .. } => {
            let (w, h) = render::words_box_pt(text, *size);
            Some((x - w / k / 2.0, y - h / k / 2.0, x + w / k / 2.0, y + h / k / 2.0))
        }
        _ => None,
    };
    let label = shapes.iter().find(|s| s.el == t && s.part == "body").and_then(boxed).expect("the label is drawn");
    for w in ["w1", "w2", "w3"] {
        let o = shapes.iter().find(|s| s.el == w).and_then(boxed).unwrap();
        let clear = label.2 <= o.0 || o.2 <= label.0 || label.3 <= o.1 || o.3 <= label.1;
        assert!(clear, "the shared label sits on {w}: {label:?} {o:?}");
    }
    // Still by its lamps.
    let at = d.get(&t).unwrap();
    assert!((at.x - 1.0).abs() < 4.0 && at.y.abs() < 4.0, "{} {}", at.x, at.y);
}

#[test]
fn a_moved_name_stays_where_he_put_it() {
    // His note, 2026-10-05: "let me put text where i want it to - i dont
    // need collision barriers". A name he moved onto his own Words stays
    // there, and nothing steps aside for it.
    let d = plan_with(
        r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"w":3.6,"h":0.12,"label":"12x12 Sider","label_dx":0,"label_dy":-0.6},
            {"kind":"text","id":"w","text":"Key Book Light","x":0,"y":-0.15,"bold":true},
            {"kind":"light","id":"l","sym":"","mark":"chevron","x":0.4,"y":-0.9,"label":"Key"}]"#,
    );
    let shapes = render::render(&d, &ctx(), &Options::default());
    let name = shapes.iter().find(|s| s.el == "f" && s.part == "label").expect("named");
    let Geom::Text { shift, y, .. } = &name.geom else { unreachable!() };
    assert!(shift.0.abs() + shift.1.abs() < 1e-9, "not stepped: {shift:?}");
    // Exactly under-spot plus his offset: the same with the Words gone.
    let mut bare = d.clone();
    apply(&mut bare, &op(r#"{"op":"remove","ids":["w","l"]}"#)).unwrap();
    let alone = render::render(&bare, &ctx(), &Options::default());
    let Geom::Text { y: y2, .. } = &alone.iter().find(|s| s.el == "f" && s.part == "label").unwrap().geom else { unreachable!() };
    assert!((y - y2).abs() < 1e-9, "{y} {y2}");
    assert!((d.get("f").unwrap().label_dy + 0.6).abs() < 1e-9);
}

#[test]
fn a_hidden_name_is_drawn_while_it_is_typed() {
    // Fix round 2: typing a Name on a lamp whose label he hid put the cursor
    // under the lamp, then the words jumped to their spot and the label was
    // turned on. Now the plan places them while typed; the flag stays.
    let mut d = plan_with(r#"[{"kind":"light","id":"a","sym":"","mark":"bar","x":0,"y":0,"label":"Uplight","label_hidden":true,"label_dx":2,"label_dy":0}]"#);
    let named = |d: &Diagram, typing: &str| {
        render::render(d, &ctx(), &Options { typing: typing.into(), ..Default::default() }).into_iter().any(|s| s.el == "a" && s.part == "label")
    };
    assert!(!named(&d, ""));
    assert!(named(&d, "a"));
    assert!(!render::render(&d, &ctx(), &Options { typing: "a".into(), paper: true, ..Default::default() }).iter().any(|s| s.el == "a" && s.part == "label"), "never on paper");
    apply(&mut d, &op(r#"{"op":"settings","set":{"labels":false}}"#)).unwrap();
    assert!(named(&d, "a"), "View › Labels off: still placed while typed");
}

#[test]
fn every_kind_is_set_or_plot() {
    // Ref 1498: the room is the set, what the DP puts on it the plot; the
    // layer is the kind, never stored.
    let d = plan_with(
        r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":4,"y2":0},{"kind":"door","id":"d","x":1,"y":0},
            {"kind":"road","id":"r","x":0,"y":5,"x2":9,"y2":5},{"kind":"set","id":"b","sym":"building","x":3,"y":3},
            {"kind":"image","id":"i","x":0,"y":0,"w":5,"h":4},{"kind":"image","id":"ph","role":"photo","x":0,"y":0,"w":1,"h":1},
            {"kind":"light","id":"l","sym":"","x":1,"y":1},{"kind":"camera","id":"c","x":2,"y":2},
            {"kind":"shape","id":"sh","sym":"rect","x":2,"y":2,"w":1,"h":1},
            {"kind":"text","id":"t","text":"HI","x":0,"y":0},{"kind":"track","id":"k","x":0,"y":1,"x2":3,"y2":1}]"#,
    );
    let of = |id: &str| super::layer(d.get(id).unwrap());
    for id in ["w", "d", "r", "b", "i", "sh"] {
        assert_eq!(of(id), "set", "{id}");
    }
    for id in ["ph", "l", "c", "t", "k"] {
        assert_eq!(of(id), "plot", "{id}");
    }
    assert!(!d.get("w").unwrap().to_json().encode().contains("layer"), "never stored");
}

#[test]
fn a_frame_writes_its_size_and_cloth_over_its_note() {
    // His notes, 2026-10-05: "a frames size adn then fabric/material name
    // goes in first line / then the note is the line after".
    let mut d = plan_with(r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":3.6576,"material":"ultra-bounce","tilt":45}]"#);
    assert_eq!(render::frame_lines(d.get("f").unwrap(), true), ("12×12 Ultra Bounce · 45°".to_string(), String::new()));
    apply(&mut d, &op(r#"{"op":"update","ids":["f"],"set":{"label":"Bounce for Key"}}"#)).unwrap();
    assert_eq!(render::frame_lines(d.get("f").unwrap(), true), ("12×12 Ultra Bounce · 45°".to_string(), "Bounce for Key".to_string()));
    // An old frame named in its label keeps every word: as its Note.
    let old = plan_with(r#"[{"kind":"light","id":"f","sym":"frame","x":0,"y":0,"h":3.6576,"material":"solid","label":"12x12 Sider"}]"#);
    assert_eq!(render::frame_lines(old.get("f").unwrap(), true), ("12×12 Solid".to_string(), "12x12 Sider".to_string()));
    // Drawn: the first line in grip's ink, the Note grey.
    let shapes = render::render(&d, &ctx(), &Options::default());
    let l = shapes.iter().find(|s| s.el == "f" && s.part == "label").unwrap();
    let Geom::Text { text, under, .. } = &l.geom else { unreachable!() };
    assert_eq!(text, "12×12 ULTRA BOUNCE · 45°\nBOUNCE FOR KEY");
    assert_eq!((l.fill.clone(), under.clone()), (Ink::Role("added"), Ink::Role("ink2")));
    let sheet = super::sheet::gear(&d);
    assert!(sheet.iter().any(|g| g.group == "Frames" && g.name.contains("Ultra Bounce")), "{sheet:?}");
}

#[test]
fn every_piece_can_wear_a_note() {
    // His note, 2026-10-05: "alll items should be able to have a note".
    let d = plan_with(
        r#"[{"kind":"set","id":"s","sym":"sofa","x":0,"y":0,"w":2,"h":0.9,"label":"Couch","caption":"Strike for 8B"},
            {"kind":"cast","id":"c","x":4,"y":0,"label":"Maya","caption":"Enters from kitchen"},
            {"kind":"camera","id":"k","x":8,"y":0,"label":"A","caption":"On sticks"},
            {"kind":"shape","id":"o","x":12,"y":0,"w":1,"h":1,"caption":"Hold area"},
            {"kind":"arrow","id":"a","x":0,"y":5,"x2":4,"y2":5,"label":"Push","caption":"Slow"},
            {"kind":"wall","id":"w","x":0,"y":9,"x2":6,"y2":9,"label":"Flat","caption":"Wild"}]"#,
    );
    let shapes = render::render(&d, &ctx(), &Options::default());
    for (id, want) in [("s", "COUCH\nSTRIKE FOR 8B"), ("c", "MAYA\nENTERS FROM KITCHEN"), ("k", "A\nON STICKS"), ("o", "HOLD AREA"), ("a", "PUSH\nSLOW"), ("w", "FLAT\nWILD")] {
        let l = shapes.iter().find(|s| s.el == id && s.part == "label").unwrap_or_else(|| panic!("{id} named"));
        let Geom::Text { text, under, .. } = &l.geom else { unreachable!() };
        assert_eq!(text, want, "{id}");
        assert_eq!(*under, Ink::Role("ink2"), "{id}'s note grey");
    }
    assert_eq!(Diagram::parse(&d.encode()).get("s").unwrap().caption, "Strike for 8B");
}


#[test]
fn a_mat_hung_pointing_down_is_its_size_crossed_and_says_top() {
    // His ask, 2026-10-05: a LiteMat 8 over the set, pointing straight down.
    let d = plan_with(
        r##"[{"kind":"light","id":"mat","sym":"fso-litemat-8","x":0,"y":0,"rot":0,"w":1.05,"h":1.08,"tilt":0,"height":"8'"},
            {"kind":"light","id":"side","sym":"fso-litemat-8","x":5,"y":0,"rot":0,"w":1.05,"h":1.08}]"##,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let body = |id: &str| -> Vec<&Shape> { shapes.iter().filter(|s| s.el == id && s.part == "body").collect() };
    // Down: its outline at true size and a cross — four corners and two lines.
    let lines = body("mat").iter().filter(|s| s.stroke != Ink::None && s.line > 0.0).count();
    assert!(lines >= 3, "outline and cross: {lines}");
    // Standing (the default) is still the panel mark, not crossed.
    assert!(body("side").len() != body("mat").len(), "a standing mat keeps its mark");
    let (_, under) = render::lamp_lines(d.get("mat").unwrap(), "LiteMat 8", true);
    assert_eq!(under, "Top · 8'");
    let (_, under) = render::lamp_lines(d.get("side").unwrap(), "LiteMat 8", true);
    assert_eq!(under, "");
}

#[test]
fn frames_and_set_pieces_share_a_label() {
    // His ask, 2026-10-05: "frames and any object can share the same label".
    let mut d = plan_with(
        r##"[{"kind":"light","id":"f1","sym":"frame","x":0,"y":0,"w":3.66,"h":3.66,"tilt":0,"material":"ultra-bounce"},
            {"kind":"light","id":"f2","sym":"frame","x":5,"y":0,"w":3.66,"h":3.66,"tilt":0,"material":"ultra-bounce","label":"Bounce for key"},
            {"kind":"set","id":"s1","sym":"sofa","x":0,"y":6,"w":2,"h":0.9,"label":"Sofa"},
            {"kind":"wall","id":"w","x":0,"y":10,"x2":4,"y2":10}]"##,
    );
    let made = apply(&mut d, &op(r#"{"op":"share_label","ids":["f1","f2","w"]}"#)).unwrap();
    let label = made[0].clone();
    assert_eq!(d.get("f1").unwrap().tie_to, label);
    assert_eq!(d.get("f2").unwrap().tie_to, label);
    assert!(d.get("w").unwrap().tie_to.is_empty(), "a wall shares nothing");
    // The note one had is now both's.
    assert_eq!(d.get("f1").unwrap().label, "Bounce for key");
    let words = render::shared_label_words(&d, d.get(&label).unwrap()).unwrap();
    assert!(words.starts_with("2× "), "{words}");
    assert!(words.contains("BOUNCE FOR KEY"), "{words}");
    // A set piece joins the same label.
    apply(&mut d, &op(&format!(r#"{{"op":"share_label","ids":["{label}","s1"]}}"#))).unwrap();
    let words = render::shared_label_words(&d, d.get(&label).unwrap()).unwrap();
    assert!(words.contains("+ SOFA"), "{words}");
    // Tied, the frames and the sofa wear no names of their own.
    let shapes = render::render(&d, &Context::default(), &Options::default());
    for id in ["f1", "f2", "s1"] {
        assert!(!shapes.iter().any(|s| s.el == id && s.part == "label"), "{id} named at the label only");
    }
    // A Note set on one is set on all.
    apply(&mut d, &op(r#"{"op":"update","ids":["f1"],"set":{"label":"Top bounce"}}"#)).unwrap();
    assert_eq!(d.get("f2").unwrap().label, "Top bounce");
    assert_eq!(d.get("s1").unwrap().caption, "Top bounce");
}

#[test]
fn measurements_turn_off_from_the_view_menu() {
    let mut d = plan_with(r#"[{"kind":"measure","id":"m","x":0,"y":0,"x2":3,"y2":0}]"#);
    let drawn = |d: &Diagram| render::render(d, &Context::default(), &Options::default()).iter().any(|s| s.el == "m");
    assert!(drawn(&d));
    apply(&mut d, &op(r#"{"op":"settings","set":{"measures":false}}"#)).unwrap();
    assert!(!d.settings.measures);
    assert!(!drawn(&d), "kept, not drawn");
    assert!(d.get("m").is_some());
}

#[test]
fn connecting_lines_run_under_the_pieces() {
    // His note, 2026-10-05: connecting lines go under lights, as a shared
    // label's do. A connector is an arrow with no head.
    let d = plan_with(
        r##"[{"kind":"light","id":"lamp","sym":"","mark":"chevron","x":3,"y":0,"w":0.3,"h":0.3},
            {"kind":"arrow","id":"c","x":0,"y":0,"x2":6,"y2":0,"head":"none","weight":0.8},
            {"kind":"arrow","id":"a","x":0,"y":1,"x2":6,"y2":1}]"##,
    );
    let shapes = render::render(&d, &Context::default(), &Options::default());
    let first = |id: &str| shapes.iter().position(|s| s.el == id && s.part == "body").unwrap();
    assert!(first("c") < first("lamp"), "the connector is drawn before (under) the lamp");
    assert!(first("a") > first("lamp"), "an arrow still points over it");
}

#[test]
fn a_sliding_door_is_drawn_as_two_panels_on_tracks() {
    let d = plan_with(r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":12,"y2":0},
        {"kind":"door","id":"a","x":1.5,"y":0,"w":1.8,"slide":true,"swing":0,"hinge":"right"},
        {"kind":"door","id":"b","x":4.5,"y":0,"w":1.8,"slide":true,"swing":45,"hinge":"right"},
        {"kind":"door","id":"c","x":7.5,"y":0,"w":1.8,"slide":true,"swing":90,"hinge":"left","flip":true},
        {"kind":"door","id":"s","x":10.5,"y":0,"w":0.9},
        {"kind":"window","id":"n","x":11.8,"y":0}]"#);
    if let Ok(path) = std::env::var("SLIDING_PREVIEW") {
        let svg = svg::svg(&d, &ctx(), &Options::default(), &svg::Frame::default(), "t");
        std::fs::write(path, svg).unwrap();
    }
    let shapes = render::render(&d, &ctx(), &Options::default());
    for id in ["a", "b", "c"] {
        let filled = shapes.iter().filter(|s| s.el == id && s.part == "body" && s.fill != Ink::None).count();
        assert!(filled >= 3, "door {id}: two panels and an arrowhead, got {filled}");
    }
    let svg = svg::svg(&d, &ctx(), &Options::default(), &svg::Frame::default(), "t");
    assert!(!svg.contains("NaN"));
}

#[test]
fn every_door_kind_draws_and_an_older_sliding_door_stays_sliding() {
    // His ask, 2026-10-17: doors that swing from the middle, panels that part
    // from the centre; an older plan's sliding door keeps its meaning.
    let d = plan_with(r#"[{"kind":"wall","id":"w","x":0,"y":0,"x2":20,"y2":0},
        {"kind":"door","id":"old","x":1.5,"y":0,"w":1.8,"slide":true,"swing":45,"hinge":"right"},
        {"kind":"door","id":"swing","x":4,"y":0,"w":0.9},
        {"kind":"door","id":"double","x":6.5,"y":0,"w":1.6,"door":"double"},
        {"kind":"door","id":"center","x":9.5,"y":0,"w":1.8,"door":"center","swing":45},
        {"kind":"door","id":"pocket","x":12.5,"y":0,"w":0.9,"door":"pocket","swing":0},
        {"kind":"door","id":"pp","x":15.5,"y":0,"w":1.6,"door":"pocketpair","swing":90},
        {"kind":"door","id":"shut","x":18.5,"y":0,"w":0.9,"swing":0}]"#);
    let style = |id: &str| d.get(id).unwrap().door_style();
    assert_eq!(style("old"), "sliding", "an older sliding door is Sliding");
    for id in ["swing", "double", "center", "pocket", "pp"] {
        assert_eq!(style(id), id.replace("pp", "pocketpair"));
    }
    // The word is not kept: the three switches are, so older builds still
    // draw something close (a double as a door, a centre slider as sliding).
    let j = d.get("center").unwrap().to_json().encode();
    assert!(j.contains("\"slide\":true") && j.contains("\"pair\":true") && !j.contains("\"door\":"), "{j}");
    assert!(!d.get("old").unwrap().to_json().encode().contains("pair"), "an older door gains nothing");
    let shapes = render::render(&d, &ctx(), &Options::default());
    let count = |id: &str| shapes.iter().filter(|s| s.el == id && s.part == "body").count();
    // Double: two leaves and two arcs, beside the two jambs.
    assert_eq!(count("double"), 2 + 4, "double");
    assert!(count("swing") == 2 + 2 && count("shut") == 2 + 2, "a shut door still shows its swing");
    // Centre: two panels with their glass lines, a track and two arrows.
    assert!(count("center") >= 2 + 4 + 1 + 4, "center: {}", count("center"));
    // A shut door's arc is dashed.
    assert!(shapes.iter().any(|s| s.el == "shut" && s.dash == "dash"));
    // Changing the kind by its word, as the connector and room scans do.
    let mut d = d;
    apply(&mut d, &op(r#"{"op":"update","ids":["old"],"set":{"door":"double"}}"#)).unwrap();
    assert_eq!(d.get("old").unwrap().door_style(), "double");
    apply(&mut d, &op(r#"{"op":"update","ids":["old"],"set":{"door":"nonsense"}}"#)).unwrap();
    assert_eq!(d.get("old").unwrap().door_style(), "double", "an unknown word changes nothing");
    let svg = svg::svg(&d, &ctx(), &Options::default(), &svg::Frame::default(), "t");
    assert!(!svg.contains("NaN"));
}

#[test]
fn a_person_points_the_way_they_face() {
    let d = plan_with(r##"[{"id":"p","kind":"cast","x":0,"y":0,"rot":90,"color":"#D64545"}]"##);
    let shapes = render::render(&d, &ctx(), &Options::default());
    // The furthest point of the person is the nose, straight down the
    // screen for a person turned 90°.
    let mut far = (0.0f64, 0.0f64);
    for s in shapes.iter().filter(|s| s.el == "p" && s.part == "body") {
        if let render::Geom::Path(segs) = &s.geom {
            for seg in segs {
                if let render::Seg::L(x, y) = seg {
                    if x.hypot(*y) > far.0.hypot(far.1) {
                        far = (*x, *y);
                    }
                }
            }
        }
    }
    assert!(far.1 > 0.15 && far.0.abs() < 1e-6, "nose at {far:?}");
}

#[test]
fn words_and_arrows_stay_in_the_view_they_were_made_in() {
    let d = plan_with(r#"[{"kind":"text","id":"p","text":"HI","x":0,"y":0},{"kind":"text","id":"s","text":"HI","x":1,"y":0,"in_set":true},
        {"kind":"arrow","id":"ap","x":0,"y":1,"x2":2,"y2":1},{"kind":"arrow","id":"as","x":0,"y":2,"x2":2,"y2":2,"in_set":true}]"#);
    for (id, want) in [("p", "plot"), ("s", "set"), ("ap", "plot"), ("as", "set")] {
        assert_eq!(super::layer(d.get(id).unwrap()), want, "{id}");
    }
    // Older words say nothing; only a Set one writes the flag, and it survives a round trip.
    assert!(!d.get("p").unwrap().to_json().encode().contains("in_set"));
    let back = El::from_json(&json::parse(&d.get("s").unwrap().to_json().encode()).unwrap()).unwrap();
    assert!(back.in_set);
    // Both views draw both: the layer is only which one is being edited.
    let shapes = render::render(&d, &ctx(), &Options::default());
    for id in ["p", "s", "ap", "as"] {
        assert!(shapes.iter().any(|s| s.el == id), "{id} drew nothing");
    }
}

#[test]
fn a_mat_is_a_soft_panel_drawn_at_its_own_size() {
    // His ask, 2026-10-15: a rectangle light from above, any size. 4 × 2 ft,
    // turned: its drawn box is its own w × h, in the lamp's own turn.
    let ft = 0.3048;
    let d = plan_with(&format!(
        r#"[{{"kind":"light","id":"m","sym":"","mark":"mat","x":3,"y":3,"rot":0,"w":{},"h":{}}},
            {{"kind":"light","id":"n","sym":"","mark":"mat","x":8,"y":3,"rot":90,"w":{},"h":{}}}]"#,
        4.0 * ft, 2.0 * ft, 4.0 * ft, 2.0 * ft
    ));
    assert_eq!(d.get("m").unwrap().mark, "mat", "the mark is kept");
    let shapes = render::render(&d, &ctx(), &Options::default());
    let mine: Vec<Shape> = shapes.iter().filter(|s| s.el == "m").cloned().collect();
    let b = render::bounds(&mine).unwrap();
    assert!(((b.x2 - b.x1) - 4.0 * ft).abs() < 0.08 && ((b.y2 - b.y1) - 2.0 * ft).abs() < 0.08, "{b:?}");
    // Turned a quarter, the same panel stands on its end.
    let theirs: Vec<Shape> = shapes.iter().filter(|s| s.el == "n").cloned().collect();
    let t = render::bounds(&theirs).unwrap();
    assert!(((t.y2 - t.y1) - 4.0 * ft).abs() < 0.08 && ((t.x2 - t.x1) - 2.0 * ft).abs() < 0.08, "{t:?}");
    // The box a pick wears is its size.
    let (w, h) = render::drawn_size(d.get("m").unwrap(), &d, &Options::default()).unwrap();
    assert!((w - 4.0 * ft).abs() < 1e-6 && (h - 2.0 * ft).abs() < 1e-6);
    // The legend names it.
    let lg = plot::legend(&d);
    assert!(lg.iter().any(|x| x.key.starts_with("mat|")), "{:?}", lg.iter().map(|x| x.key.clone()).collect::<Vec<_>>());
    let s = laid(&d, &super::sheet::Ask::default());
    assert!(s.items.iter().any(|i| i.kind == "legend"));
}

#[test]
fn a_mat_resizes_freely_and_an_unknown_mark_is_dropped() {
    let mut d = plan_with(r#"[{"kind":"light","id":"m","sym":"","mark":"mat","x":0,"y":0,"w":1.2,"h":0.6}]"#);
    apply(&mut d, &op(r#"{"op":"update","ids":["m"],"set":{"w":2.5,"h":0.4}}"#)).unwrap();
    let m = d.get("m").unwrap();
    assert_eq!((m.w, m.h, m.mark.as_str()), (2.5, 0.4, "mat"), "no locked ratio");
    // A mark this build has never heard of is dropped, as before.
    apply(&mut d, &op(r#"{"op":"update","ids":["m"],"set":{"mark":"futuristic"}}"#)).unwrap();
    assert_eq!(d.get("m").unwrap().mark, "");
}

#[test]
fn a_pictures_marks_move_size_and_turn_with_it() {
    // His ask, 2026-10-15: marks drawn on a photo stay on it.
    let line = super::photomarks::Mark::encode(&[
        super::photomarks::Mark::Shape { kind: super::photomarks::Kind::Box, a: (0.25, 0.25), b: (0.75, 0.75), look: crate::arrow::ArrowLook::Yellow, thick: 1.0, dashed: false },
        super::photomarks::Mark::Arrow(crate::arrow::Arrow::straight(0.1, 0.5, 0.9, 0.5)),
        super::photomarks::Mark::Words { at: (0.1, 0.1), text: "Window".into(), look: crate::arrow::ArrowLook::Light, size: 0.05 },
    ]);
    let mut d = plan_with(&format!(r#"[{{"kind":"image","id":"p","media":"x.jpg","role":"photo","x":5,"y":5,"w":4,"h":3,"opacity":0.5,"marks":"{line}"}}]"#));
    let marks = |d: &Diagram| -> Vec<Shape> { render::render(d, &ctx(), &Options::default()).into_iter().filter(|s| s.el == "p" && s.part == "mark").collect() };
    let bounds = |m: &[Shape]| {
        let mut b = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for s in m {
            if let Geom::Path(segs) = &s.geom {
                for g in segs {
                    if let render::Seg::L(x, y) | render::Seg::M(x, y) = g {
                        b = (b.0.min(*x), b.1.min(*y), b.2.max(*x), b.3.max(*y));
                    }
                }
            }
        }
        b
    };
    let m = marks(&d);
    assert!(m.len() >= 3, "{m:?}");
    assert!(m.iter().all(|s| (s.alpha - 1.0).abs() < 1e-9), "full strength though the photo is at half");
    assert!(m.iter().any(|s| matches!(&s.geom, Geom::Text { text, .. } if text == "WINDOW")));
    let b = bounds(&m);
    assert!(b.0 > 3.0 - 0.01 && b.2 < 7.0 + 0.01 && b.1 > 3.5 - 0.01 && b.3 < 6.5 + 0.01, "on the photo: {b:?}");
    // Moved and made twice as big: the marks come along, twice as big.
    apply(&mut d, &op(r#"{"op":"update","id":"p","set":{"x":15,"w":8,"h":6}}"#)).unwrap();
    let b2 = bounds(&marks(&d));
    assert!(((b2.2 - b2.0) - 2.0 * (b.2 - b.0)).abs() < 0.05, "{b:?} {b2:?}");
    assert!(((b2.0 + b2.2) / 2.0 - 15.0).abs() < 0.3, "{b2:?}");
    // Kept with the plan.
    assert_eq!(Diagram::parse(&d.encode()).get("p").unwrap().marks, line);
}

#[test]
fn attach_to_photo_gathers_the_marks_lying_on_it() {
    let mut d = plan_with(
        r##"[{"kind":"image","id":"p","media":"x.jpg","role":"photo","x":5,"y":5,"w":4,"h":3},
            {"kind":"arrow","id":"a","x":4,"y":5,"x2":6,"y2":5.5},
            {"kind":"shape","id":"o","sym":"ellipse","x":5,"y":4.5,"w":1,"h":0.6,"color":"#F3C844"},
            {"kind":"stroke","id":"s","points":[[3.5,6],[4,6.2],[4.5,6]]},
            {"kind":"text","id":"t","x":4,"y":4,"text":"Window"},
            {"kind":"arrow","id":"far","x":4,"y":5,"x2":20,"y2":5}]"##,
    );
    apply(&mut d, &op(r#"{"op":"attach_marks","id":"p"}"#)).unwrap();
    let marks = super::photomarks::Mark::parse(&d.get("p").unwrap().marks);
    assert_eq!(marks.len(), 4, "{marks:?}");
    assert!(d.get("far").is_some(), "one running off the photo stays on the plan");
    for id in ["a", "o", "s", "t"] {
        assert!(d.get(id).is_none(), "{id} moved onto the photo");
    }
    let Some(super::photomarks::Mark::Arrow(a)) = marks.iter().find(|m| matches!(m, super::photomarks::Mark::Arrow(_))) else { panic!("an arrow: {marks:?}") };
    assert!((a.x1 - 0.25).abs() < 1e-6 && (a.y1 - 0.5).abs() < 1e-6 && (a.x2 - 0.75).abs() < 1e-6, "{a:?}");
    assert!(marks.iter().any(|m| matches!(m, super::photomarks::Mark::Shape { kind: super::photomarks::Kind::Oval, look: crate::arrow::ArrowLook::Yellow, .. })), "{marks:?}");
    assert!(apply(&mut d, &op(r#"{"op":"attach_marks","id":"far"}"#)).is_err(), "only a picture takes marks");
}
