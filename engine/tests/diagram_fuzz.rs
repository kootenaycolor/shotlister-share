//! Two thousand edits, picked at random, on the sample plan — and after every
//! one the plan must still be one a shell can draw: every number a real
//! number, every id its own, the stored form reading back as itself, and
//! the drawing made without a panic or an impossible coordinate.

use shotlister_engine::diagram::{apply, render, sample, wire, Diagram};
use shotlister_engine::json;

struct Dice(u64);
impl Dice {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn pick<'a, T>(&mut self, from: &'a [T]) -> &'a T {
        &from[(self.next() % from.len() as u64) as usize]
    }
}

const NUMBERS: &[&str] = &["0", "1.5", "-3", "0.0001", "360.5", "-720", "1e6", "-1e6", "1e300", "-1e300", "1e308", "4294967296", "12", "2"];
const KINDS: &[&str] = &["wall", "door", "window", "opening", "set", "camera", "cast", "light", "track", "road", "text", "measure", "arrow", "shape", "cable", "stroke", "image", "note"];
const FIELDS: &[&str] = &["x", "y", "x2", "y2", "w", "h", "rot", "lens", "reach", "beam", "thick", "curve", "size", "opacity", "kelvin", "swing", "lanes", "dim", "label_dx", "label_dy", "label_size", "frame_dx", "frame_dy", "frame_w"];

fn op(dice: &mut Dice, d: &Diagram) -> String {
    let ids: Vec<&str> = d.els.iter().map(|e| e.id.as_str()).collect();
    let some = |dice: &mut Dice| -> String {
        if ids.is_empty() {
            return "[]".into();
        }
        let n = 1 + dice.next() % 3;
        let picked: Vec<String> = (0..n).map(|_| format!("\"{}\"", dice.pick(&ids))).collect();
        format!("[{}]", picked.join(","))
    };
    let one = |dice: &mut Dice| ids.get((dice.next() % ids.len().max(1) as u64) as usize).copied().unwrap_or("none").to_string();
    let n = |dice: &mut Dice| dice.pick(NUMBERS).to_string();
    match dice.next() % 23 {
        0 => format!(
            r#"{{"op":"add","els":[{{"kind":"{}","x":{},"y":{},"x2":{},"y2":{},"w":{},"sym":"sofa","shot":"x"}}]}}"#,
            dice.pick(KINDS), n(dice), n(dice), n(dice), n(dice), n(dice)
        ),
        1 => format!(r#"{{"op":"update","ids":{},"set":{{"{}":{}}}}}"#, some(dice), dice.pick(FIELDS), n(dice)),
        2 => format!(r#"{{"op":"move","ids":{},"dx":{},"dy":{}}}"#, some(dice), n(dice), n(dice)),
        3 => format!(r#"{{"op":"rotate","ids":{},"deg":{}}}"#, some(dice), n(dice)),
        4 => format!(r#"{{"op":"flip","ids":{},"axis":"{}"}}"#, some(dice), dice.pick(&["x", "y"])),
        5 => format!(r#"{{"op":"order","ids":{},"to":"{}"}}"#, some(dice), dice.pick(&["front", "back", "forward", "backward"])),
        6 => format!(r#"{{"op":"group","ids":{}}}"#, some(dice)),
        7 => format!(r#"{{"op":"ungroup","ids":{}}}"#, some(dice)),
        8 => format!(r#"{{"op":"align","ids":{},"to":"{}"}}"#, some(dice), dice.pick(&["left", "right", "top", "bottom", "centre", "middle"])),
        9 => format!(r#"{{"op":"distribute","ids":{},"axis":"{}"}}"#, some(dice), dice.pick(&["x", "y"])),
        10 => format!(r#"{{"op":"beat","id":"{}","beat":{},"x":{},"y":{}}}"#, one(dice), n(dice), n(dice), n(dice)),
        11 => format!(r#"{{"op":"unbeat","id":"{}","beat":{}}}"#, one(dice), n(dice)),
        12 => format!(r#"{{"op":"duplicate","ids":{},"dx":{},"dy":{}}}"#, some(dice), n(dice), n(dice)),
        13 => format!(r#"{{"op":"remove","ids":{}}}"#, some(dice)),
        // A step: added anywhere, before or after any step, a move or a
        // turn; put anywhere, on any beat; taken away.
        14 => format!(
            r#"{{"op":"step_add","id":"{}","{}":{},"turn":{},"x":{},"y":{},"rot":{}}}"#,
            one(dice), dice.pick(&["after", "before"]), n(dice), dice.pick(&["true", "false"]), n(dice), n(dice), n(dice)
        ),
        15 => match dice.next() % 3 {
            0 => format!(r#"{{"op":"step_remove","id":"{}","step":{}}}"#, one(dice), n(dice)),
            1 => format!(r#"{{"op":"step_set","id":"{}","step":{},"beat":{}}}"#, one(dice), dice.next() % 4, n(dice)),
            _ => format!(r#"{{"op":"step_set","id":"{}","step":{},"x":{},"y":{},"rot":{}}}"#, one(dice), dice.next() % 4, n(dice), n(dice), n(dice)),
        },
        // A frame of any skin, lean and size, gelled, anywhere — and gels,
        // real or not, clipped on whatever is there.
        16 => format!(
            r#"{{"op":"add","els":[{{"kind":"light","sym":"frame","x":{},"y":{},"rot":{},"h":{},"tall":{},"tilt":{},"grid":{},"material":"{}","pipe":"{}","gels":["{}"],"aim":"{}"}}]}}"#,
            n(dice), n(dice), n(dice), n(dice), n(dice), n(dice), n(dice),
            dice.pick(&["solid", "single-net", "double-net", "diff-light", "diff-heavy", "silk", "bounce-white", "bounce-gold", "muslin", "nonsense", ""]),
            dice.pick(&["open", "butterfly", "speed-rail", "none", "?"]),
            dice.pick(&["cto-full", "nd9", "216", "plus-green-half", "made-up"]),
            one(dice)
        ),
        // A name moved, sized, hidden; a camera's frame laid on or off.
        17 => format!(
            r#"{{"op":"update","ids":{},"set":{{"label_hidden":{},"label_bold":{},"frame_on":{},"frame_w":{}}}}}"#,
            some(dice), dice.pick(&["true", "false", "1"]), dice.pick(&["true", "false", "null"]), dice.pick(&["true", "false", "\"on\""]), n(dice)
        ),
        18 => format!(
            r#"{{"op":"update","ids":{},"set":{{"gels":{},"aim":"{}","height":"{}"}}}}"#,
            some(dice), dice.pick(&["[]", "[\"ctb-full\",\"nd3\"]", "null", "[1,2]", "\"cto-half\""]), one(dice),
            dice.pick(&["7 ft", "1e308 m", "Eye Level", "", "-3'", "9999999999999999999999 in", ".", "2.1"])
        ),
        // Rigging: a stand, a frame or a table with a lamp or camera set down
        // on it, anywhere; a rig named by hand, to anything or nothing; and a
        // swap to any drawing, real or not, on whatever is there.
        19 => {
            let (x, y) = (n(dice), n(dice));
            format!(
                r#"{{"op":"add","els":[{{"kind":"{}","sym":"{}","x":{x},"y":{y},"w":{},"h":{}}},{{"kind":"{}","sym":"frame","x":{x},"y":{y},"h":{}}}]}}"#,
                dice.pick(&["set", "track", "light"]), dice.pick(&["c-stand", "table", "rug", "frame", "fso-4ft-speed-rail"]),
                n(dice), n(dice), dice.pick(&["light", "camera"]), n(dice)
            )
        }
        20 => format!(r#"{{"op":"update","ids":{},"set":{{"rig_on":"{}"}}}}"#, some(dice), one(dice)),
        21 => format!(
            r#"{{"op":"swap","ids":{},"sym":"{}"}}"#,
            some(dice), dice.pick(&["sofa", "hmi-18k", "frame", "fso-combo-stand", "fso-car", "fso-alexa-mini", "nope", ""])
        ),
        _ => format!(
            r#"{{"op":"settings","set":{{"step":{},"north":{},"grid":{},"sun":{},"sun_rays":{},"sun_time":"{:02}:{:02}","levels":{},"light_units":"{}","iso":{},"stop":{},"ambient":{},"sun_lux":{}}}}}"#,
            n(dice), n(dice), n(dice), dice.pick(&["true", "false", "1"]), dice.pick(&["true", "false", "\"yes\""]), dice.next() % 24, dice.next() % 60,
            dice.pick(&["true", "true", "false"]), dice.pick(&["stops", "lux", "fc", "??"]), n(dice), n(dice), n(dice), n(dice)
        ),
    }
}

fn sound(d: &Diagram, after: &str) {
    let mut seen = std::collections::HashSet::new();
    for e in &d.els {
        assert!(seen.insert(e.id.clone()), "two elements called {} after {after}", e.id);
        for (name, v) in [("x", e.x), ("y", e.y), ("x2", e.x2), ("y2", e.y2), ("w", e.w), ("h", e.h), ("rot", e.rot)] {
            assert!(v.is_finite(), "{} {name} = {v} after {after}", e.id);
        }
        assert!(e.lead <= e.steps.len(), "{} leads with {} of {} steps after {after}", e.id, e.lead, e.steps.len());
        for b in &e.steps {
            assert!(b.x.is_finite() && b.y.is_finite() && b.rot.is_finite(), "{} step on beat {} after {after}", e.id, b.beat);
            assert!(b.beat <= 999, "{} has beat {} after {after}", e.id, b.beat);
        }
        let on: Vec<u32> = e.beats();
        let mut once = on.clone();
        once.dedup();
        assert_eq!(on, once, "{} has two steps on one beat after {after}", e.id);
    }
    let stored = d.encode();
    assert!(!stored.contains("null"), "a number that is not one, stored, after {after}: {stored}");
    let back = Diagram::parse(&stored);
    if back.encode() != stored {
        for (a, b) in d.els.iter().zip(back.els.iter()) {
            if a.to_json().encode() != b.to_json().encode() {
                panic!("reads back differently after {after}:\n{a:?}\n{b:?}");
            }
        }
        panic!("reads back differently after {after}");
    }
    // Drawn and sent: a coordinate that is not a number goes out as `null`,
    // and the Mac then cannot read the plan at all.
    let sent = wire::payload(d, &render::Context::default(), &render::Options::default());
    assert!(json::parse(&sent).is_some(), "the payload does not parse after {after}");
    assert!(!sent.replace("\"extent\":null", "").contains("null"), "an impossible number drawn after {after}");
    // With a place and a day, the sun and its light across whatever walls
    // there are — turned whichever way north is — draw nothing impossible,
    // and the picture the portal and paper show says no number it cannot.
    let sunny = render::Context {
        place: Some((49.3, -117.7)),
        date: "2026-06-21".into(),
        utc_offset: Some(-420.0),
        shots: vec![("x".into(), "1A".into(), "50mm".into())],
        frames: vec![("x".into(), "abc.jpg".into(), 0.5625)],
        ..Default::default()
    };
    let sent = wire::payload(d, &sunny, &render::Options::default());
    assert!(json::parse(&sent).is_some(), "the sunny payload does not parse after {after}");
    assert!(!sent.replace("\"extent\":null", "").contains("null"), "an impossible number in the sun after {after}");
    let mut shown = render::render(d, &sunny, &render::Options::default());
    render::turn_shapes(&mut shown, render::view_turn(d));
    if let Some(b) = render::bounds(&shown) {
        assert!([b.x1, b.y1, b.x2, b.y2].iter().all(|v| v.is_finite()), "the plan as shown reaches nowhere after {after}");
    }
}

#[test]
fn a_plan_survives_thousands_of_random_edits() {
    for seed in 1..=16u64 {
        let mut d = sample();
        let mut dice = Dice(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15));
        for _ in 0..120 {
            let text = op(&mut dice, &d);
            let parsed = json::parse(&text).expect("the test writes JSON");
            let _ = apply(&mut d, &parsed);
            sound(&d, &text);
        }
    }
}

/// Kept in the film, and taken back: however many edits, of whatever kind,
/// Undo all the way returns the plan it started from, and Redo all the way
/// the plan it ended on — the diff writer and the history never lose a piece.
#[test]
fn every_edit_undoes_and_redoes_exactly() {
    use shotlister_engine::{DeviceId, Doc};
    for seed in 1..=6u64 {
        let mut doc = Doc::new(DeviceId(1));
        doc.create_project("Call Her Back");
        let scene = doc.create_scene("1");
        let start: Vec<json::Json> = sample().els.iter().map(|e| e.to_json()).collect();
        doc.diagram_edit(scene, &json::Json::object(vec![("op", json::Json::text("add")), ("els", json::Json::Array(start))])).unwrap();
        let began = doc.diagram(scene).encode();
        let depth = doc.undo_depth();
        let mut dice = Dice(seed.wrapping_mul(0x2545_F491_4F6C_DD1D));
        for _ in 0..80 {
            let plan = doc.diagram(scene);
            let text = op(&mut dice, &plan);
            let _ = doc.diagram_edit(scene, &json::parse(&text).unwrap());
        }
        let ended = doc.diagram(scene).encode();
        let steps = doc.undo_depth() - depth;
        assert!(steps > 20, "only {steps} steps to take back, seed {seed}");
        assert_ne!(began, ended);
        for _ in 0..steps {
            doc.undo().expect("a step to take back");
        }
        assert_eq!(doc.diagram(scene).encode(), began, "undo all the way, seed {seed}");
        for _ in 0..steps {
            doc.redo().expect("a step to put back");
        }
        assert_eq!(doc.diagram(scene).encode(), ended, "redo all the way, seed {seed}");
    }
}

/// Two devices, each editing the same plan on its own, then trading what they
/// did, over and over: they always end on one plan, whatever the edits were.
#[test]
fn two_devices_editing_at_random_always_agree() {
    use shotlister_engine::{DeviceId, Doc};
    for seed in 1..=6u64 {
        let mut mac = Doc::new(DeviceId(1));
        mac.create_project("Call Her Back");
        let scene = mac.create_scene("1");
        let start: Vec<json::Json> = sample().els.iter().map(|e| e.to_json()).collect();
        mac.diagram_edit(scene, &json::Json::object(vec![("op", json::Json::text("add")), ("els", json::Json::Array(start))])).unwrap();
        let mut other = Doc::new(DeviceId(2));
        other.merge(mac.changes().to_vec());
        let mut dice = Dice(seed.wrapping_mul(0xD1B5_4A32_D192_ED03));
        for round in 0..8 {
            for _ in 0..(1 + dice.next() % 6) {
                let text = op(&mut dice, &mac.diagram(scene));
                let _ = mac.diagram_edit(scene, &json::parse(&text).unwrap());
            }
            for _ in 0..(1 + dice.next() % 6) {
                let text = op(&mut dice, &other.diagram(scene));
                let _ = other.diagram_edit(scene, &json::parse(&text).unwrap());
            }
            let (a, b) = (mac.changes().to_vec(), other.changes().to_vec());
            mac.merge(b);
            other.merge(a);
            let (p, q) = (mac.diagram(scene), other.diagram(scene));
            assert_eq!(p.encode(), q.encode(), "seed {seed}, round {round}: the two disagree");
            sound(&p, &format!("seed {seed}, round {round}, merged"));
        }
    }
}
