//! The portal's undo (`plan_undo`): every kind of edit, taken back by the
//! edits it answers, leaves the plan exactly as it was.
use shotlister_engine::{DeviceId, Doc};
use shotlister_web::{plan_edit_in, plan_view};

fn edit(doc: &mut Doc, scene: &str, op: &str) -> shotlister_engine::json::Json {
    let said = plan_edit_in(doc, &format!(r#"{{"scene":"{scene}","op":{op}}}"#));
    let got = shotlister_engine::json::parse(&said).unwrap();
    assert!(got.get("error").is_none(), "{op}: {said}");
    got
}

/// As the page does it: a piece brought back by an `add` has a new id, and
/// every later step of the same undo is told it (`planUndo` in diagram.js).
fn undo(doc: &mut Doc, scene: &str, got: &shotlister_engine::json::Json) {
    let mut renamed: Vec<(String, String)> = Vec::new();
    for op in got.get("undo").unwrap().as_array().unwrap() {
        let text = renamed.iter().fold(op.encode(), |t, (a, b)| t.replace(&format!("\"{a}\""), &format!("\"{b}\"")));
        let said = edit(doc, scene, &text);
        if op.get("op").and_then(|o| o.as_str()) == Some("add") {
            let asked: Vec<String> = op.get("els").unwrap().as_array().unwrap().iter().map(|e| e.str_field("id")).collect();
            let made: Vec<String> = said.get("made").unwrap().as_array().unwrap().iter().map(|m| m.as_str().unwrap().to_string()).collect();
            renamed.extend(asked.into_iter().zip(made));
        }
    }
}

/// The plan, less the pieces' own ids — a piece brought back by an undo is a
/// new record (the engine never brings a deleted one back), and the page
/// follows its new id.
fn shape_of(doc: &Doc, id: shotlister_engine::Id) -> String {
    let mut j = doc.diagram(id).to_json();
    if let shotlister_engine::json::Json::Object(pairs) = &mut j {
        for (k, v) in pairs.iter_mut() {
            if k != "els" { continue; }
            if let shotlister_engine::json::Json::Array(els) = v {
                for e in els.iter_mut() {
                    if let shotlister_engine::json::Json::Object(f) = e {
                        f.retain(|(k, _)| k != "id");
                    }
                }
            }
        }
    }
    j.encode()
}

#[test]
fn every_edit_is_taken_back_exactly() {
    let mut doc = Doc::new(DeviceId(7));
    doc.create_project("Test");
    let id = doc.create_scene("1");
    let s = id.0.to_string();
    edit(&mut doc, &s, r#"{"op":"add","els":[{"kind":"camera","x":1,"y":1,"lens":50},{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"set","sym":"sofa","x":2,"y":2,"w":2,"h":1},{"kind":"cast","x":3,"y":1}]}"#);
    let start = shape_of(&doc, id);
    let ids: Vec<String> = doc.diagram(id).els.iter().map(|e| e.id.clone()).collect();
    for op in [
        format!(r#"{{"op":"move","ids":["{}"],"dx":1.5,"dy":-0.5}}"#, ids[0]),
        format!(r#"{{"op":"rotate","ids":["{}","{}"],"deg":33}}"#, ids[0], ids[2]),
        format!(r#"{{"op":"remove","ids":["{}","{}"]}}"#, ids[1], ids[2]),
        format!(r#"{{"op":"order","ids":["{}"],"to":"back"}}"#, ids[3]),
        format!(r##"{{"op":"update","ids":["{}"],"set":{{"label":"Hero","color":"#ff0000","lens":85}}}}"##, ids[0]),
        format!(r#"{{"op":"duplicate","ids":["{}"],"dx":1,"dy":1}}"#, ids[2]),
        format!(r#"{{"op":"group","ids":["{}","{}"]}}"#, ids[0], ids[3]),
        format!(r#"{{"op":"beat","id":"{}","beat":2,"x":5,"y":5}}"#, ids[3]),
        r#"{"op":"settings","set":{"units":"m","grid":false,"north":40}}"#.to_string(),
        r#"{"op":"clear"}"#.to_string(),
    ] {
        // Ids as they stand now: an undo before this may have brought pieces
        // back under new ones.
        let now: Vec<String> = doc.diagram(id).els.iter().map(|e| e.id.clone()).collect();
        let op = ids.iter().zip(now.iter()).fold(op, |o, (a, b)| o.replace(a.as_str(), b.as_str()));
        let got = edit(&mut doc, &s, &op);
        assert_ne!(shape_of(&doc, id), start, "{op} changed nothing");
        undo(&mut doc, &s, &got);
        assert_eq!(shape_of(&doc, id), start, "{op} was not taken back");
    }
    // And the page's picture answers with every piece and its place.
    let view = plan_view(&doc, &format!(r#"{{"scene":"{s}","width":800,"height":600}}"#));
    let v = shotlister_engine::json::parse(&view).unwrap();
    assert_eq!(v.get("els").unwrap().as_array().unwrap().len(), 4);
    assert!(v.get("svg").unwrap().as_str().unwrap().starts_with("<svg"));
}
