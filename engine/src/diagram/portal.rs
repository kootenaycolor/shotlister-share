//! **The portal's diagram edits that are not a plan's own** (his ask,
//! 2026-10-17: *"the portal should be able to edit the diagrams as much as
//! the Mac"*). A scene's several diagrams — new, rename, move, delete and
//! back again — scenes hidden from the Diagram's list by hand, and a cast
//! member's colour for the whole project, as JSON
//! edits the Diagrams page makes on its own copy and its server makes again
//! on the film (`web` and `mcpweb`, `special_edit`). Written once, here, so
//! the page and the server can never make them differently.
//!
//! Each answers the edits that take it back, because the plan's own undo
//! (`undo_ops`, a before-and-after of one plan) cannot see a diagram that is
//! gone or a colour that lives on the project.

use super::{Diagram, Settings};
use crate::doc::Doc;
use crate::id::Id;
use crate::json::Json;

/// What one of these edits made, and the edits that take it back.
pub struct Special {
    pub made: Vec<String>,
    pub undo: Vec<Json>,
}

fn obj(pairs: Vec<(&str, Json)>) -> Json {
    Json::Object(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

fn id_of(op: &Json, key: &str) -> Option<Id> {
    op.str_field(key).trim().parse::<u128>().ok().map(Id)
}

/// Every setting, defaults included — so an undo can put back a value that
/// was the default (the plan's own JSON leaves those out).
pub fn settings_full(s: &Settings) -> Json {
    let t = |v: &str| Json::text(v);
    let mut o: Vec<(String, Json)> = vec![
        ("units".into(), t(&s.units)),
        ("grid".into(), Json::Bool(s.grid)),
        ("snap".into(), Json::Bool(s.snap)),
        ("dims".into(), Json::Bool(s.dims)),
        ("all_lengths".into(), Json::Bool(s.all_lengths)),
        ("sketch".into(), Json::Bool(s.sketch)),
        ("cones".into(), Json::Bool(s.cones)),
        ("beams".into(), Json::Bool(s.beams)),
        ("labels".into(), Json::Bool(s.labels)),
        ("step".into(), Json::Number(s.step)),
        ("north".into(), Json::Number(s.north)),
        ("sun".into(), Json::Bool(s.sun)),
        ("sun_rays".into(), Json::Bool(s.sun_rays)),
        ("sun_date".into(), t(&s.sun_date)),
        ("sun_time".into(), t(&s.sun_time)),
        ("levels".into(), Json::Bool(s.levels)),
        ("light_units".into(), t(&s.light_units)),
        ("iso".into(), Json::Number(s.iso)),
        ("shutter".into(), Json::Number(s.shutter)),
        ("stop".into(), Json::Number(s.stop)),
        ("ambient".into(), Json::Number(s.ambient)),
        ("sun_lux".into(), Json::Number(s.sun_lux)),
        ("colours".into(), Json::Object(s.colours.iter().map(|(k, v)| (k.clone(), Json::text(v))).collect())),
        // The sheet (Back to Paper, Batch 2).
        ("paper".into(), t(&s.paper)),
        ("orientation".into(), t(&s.orientation)),
        ("legend".into(), Json::Bool(s.legend)),
        ("notes".into(), Json::Bool(s.notes)),
        ("sheet_notes".into(), t(&s.sheet_notes)),
        ("scale_bar".into(), Json::Bool(s.scale_bar)),
        ("fabric".into(), Json::Bool(s.fabric)),
    ];
    if let Some(tz) = s.sun_tz {
        o.push(("sun_tz".into(), Json::Number(tz)));
    }
    Json::Object(o)
}

/// **The edits that take `after` back to `before`** — the portal's undo.
///
/// The film's truth is on the server, and every edit from the portal lands
/// there as its own change log, so a browser's own undo history cannot take
/// one back. Undo is therefore another edit: pieces made are removed, pieces
/// removed come back whole, pieces changed are put back field for field, the
/// stack is restored, and the plan's settings too. Only what the edit
/// touched is written, so somebody else's work in between is left alone.
/// (Moved here from `web` on 2026-10-17 so the server can say how to take
/// back a link visitor's edit too.)
pub fn undo_ops(before: &Diagram, after: &Diagram) -> Vec<Json> {
    let mut ops = Vec::new();
    let had = |id: &str| before.els.iter().any(|e| e.id == id);
    let has = |id: &str| after.els.iter().any(|e| e.id == id);
    let made: Vec<Json> = after.els.iter().filter(|e| !had(&e.id)).map(|e| Json::text(&e.id)).collect();
    if !made.is_empty() {
        ops.push(obj(vec![("op", Json::text("remove")), ("ids", Json::Array(made))]));
    }
    let gone: Vec<Json> = before.els.iter().filter(|e| !has(&e.id)).map(|e| e.to_json_full()).collect();
    if !gone.is_empty() {
        ops.push(obj(vec![("op", Json::text("add")), ("els", Json::Array(gone.clone()))]));
    }
    for b in &before.els {
        if let Some(a) = after.els.iter().find(|e| e.id == b.id) {
            let (bj, aj) = (b.to_json_full(), a.to_json_full());
            if bj.encode() != aj.encode() {
                let set = match bj {
                    Json::Object(pairs) => Json::Object(pairs.into_iter().filter(|(k, _)| k != "id" && k != "kind").collect()),
                    other => other,
                };
                ops.push(obj(vec![("op", Json::text("update")), ("ids", Json::Array(vec![Json::text(&b.id)])), ("set", set)]));
            }
        }
    }
    // The stack as it was: if the pieces both plans hold stand in another
    // order, or a piece comes back (an add puts it at its kind's tier, not
    // where it was), each goes to the front, bottom of the old stack first —
    // which rebuilds the old stack exactly.
    let kept_before: Vec<&str> = before.els.iter().map(|e| e.id.as_str()).filter(|id| has(id)).collect();
    let kept_after: Vec<&str> = after.els.iter().map(|e| e.id.as_str()).filter(|id| had(id)).collect();
    if before.els.len() > 1 && (kept_before != kept_after || !gone.is_empty()) {
        for e in &before.els {
            ops.push(obj(vec![("op", Json::text("order")), ("ids", Json::Array(vec![Json::text(&e.id)])), ("to", Json::text("front"))]));
        }
    }
    if settings_full(&before.settings).encode() != settings_full(&after.settings).encode() {
        ops.push(obj(vec![("op", Json::text("settings")), ("set", settings_full(&before.settings))]));
    }
    ops
}

/// Whether an edit takes a whole diagram away: deleting one, clearing one,
/// or another plan copied over one that has pieces. A link visitor's server
/// keeps these only when the page says it asked first (`confirmed`).
pub fn wipes(doc: &Doc, scene: Id, op: &Json) -> bool {
    match op.get("op").and_then(|o| o.as_str()).unwrap_or("") {
        "plan_delete" | "diagram_delete" | "clear" => true,
        "copy_from" => op.str_field("mode") == "replace" && doc.diagram_count(scene) > 0,
        "send" => {
            op.str_field("mode") == "replace"
                && op
                    .get("to")
                    .and_then(|t| t.as_array())
                    .map(|a| a.iter().filter_map(|v| v.as_str()).filter_map(|t| t.trim().parse::<u128>().ok()).any(|t| doc.diagram_count(Id(t)) > 0))
                    .unwrap_or(false)
        }
        _ => false,
    }
}

impl Doc {
    /// **The portal's own edits** — `None` for anything else. `scene` is
    /// the diagram the page has open; an edit naming another of the same
    /// scene's diagrams says so with `id`.
    ///
    /// - `diagram_new {id?, name, from?}` — a further diagram on the scene,
    ///   under the page's id, a copy of `from` when given.
    /// - `diagram_rename {id, name}`, `diagram_move {id, index}`
    /// - `diagram_delete {id}` — never the last one.
    /// - `diagram_restore {id, name, index, els, settings}` — a deleted one
    ///   back, as its undo.
    /// - `cast_colour {name, color}` — one colour for a cast member across
    ///   the project (empty: back to the billing-order colour).
    pub fn portal_edit(&mut self, scene: Id, op: &Json) -> Option<Result<Special, String>> {
        let kind = op.get("op").and_then(|o| o.as_str()).unwrap_or("").to_string();
        let owner = self.diagram_scene(scene);
        let target = id_of(op, "id").unwrap_or(scene);
        Some(match kind.as_str() {
            "diagram_new" => {
                let from = id_of(op, "from");
                match self.add_scene_diagram_with(owner, id_of(op, "id"), &op.str_field("name"), from) {
                    Some(made) => Ok(Special {
                        made: vec![made.0.to_string()],
                        undo: vec![obj(vec![("op", Json::text("diagram_delete")), ("id", Json::text(made.0.to_string())), ("confirmed", Json::Bool(true))])],
                    }),
                    None => Err("a loose plan has no scene to add a diagram to".into()),
                }
            }
            "diagram_rename" => {
                let was = self.scene_diagram_name(target);
                if !self.rename_scene_diagram(target, &op.str_field("name")) {
                    return Some(Err("that diagram is gone".into()));
                }
                Ok(Special {
                    made: Vec::new(),
                    undo: vec![obj(vec![("op", Json::text("diagram_rename")), ("id", Json::text(target.0.to_string())), ("name", Json::text(was))])],
                })
            }
            "diagram_move" => {
                let ids = self.scene_diagram_ids(self.diagram_scene(target));
                let Some(at) = ids.iter().position(|x| *x == target) else { return Some(Err("that diagram is gone".into())) };
                let index = op.get("index").and_then(|v| v.as_f64()).filter(|v| v.is_finite()).map(|v| v.max(0.0) as usize).unwrap_or(at);
                if !self.move_scene_diagram(target, index) {
                    return Some(Err("that diagram is gone".into()));
                }
                Ok(Special {
                    made: Vec::new(),
                    undo: vec![obj(vec![("op", Json::text("diagram_move")), ("id", Json::text(target.0.to_string())), ("index", Json::Number(at as f64))])],
                })
            }
            "diagram_delete" => {
                let of = self.diagram_scene(target);
                let ids = self.scene_diagram_ids(of);
                let Some(at) = ids.iter().position(|x| *x == target) else { return Some(Err("that diagram is gone".into())) };
                if ids.len() < 2 {
                    return Some(Err("the last diagram on a scene can only be cleared".into()));
                }
                let plan = self.diagram(target);
                let name = self.scene_diagram_name(target);
                if !self.delete_scene_diagram(target) {
                    return Some(Err("that diagram could not be deleted".into()));
                }
                // Back as a further diagram in the same place, with its
                // name, pieces and settings; a new id, made now so the page
                // and the server both use it.
                let back = Id::new();
                Ok(Special {
                    made: Vec::new(),
                    undo: vec![obj(vec![
                        ("op", Json::text("diagram_restore")),
                        ("id", Json::text(back.0.to_string())),
                        ("of", Json::text(of.0.to_string())),
                        ("name", Json::text(name)),
                        ("index", Json::Number(at as f64)),
                        ("els", Json::Array(plan.els.iter().map(|e| e.to_json_full()).collect())),
                        ("settings", settings_full(&plan.settings)),
                    ])],
                })
            }
            "diagram_restore" => {
                let of = id_of(op, "of").map(|s| self.diagram_scene(s)).unwrap_or(owner);
                let Some(id) = self.add_scene_diagram_with(of, id_of(op, "id"), &op.str_field("name"), None) else {
                    return Some(Err("that scene is gone".into()));
                };
                if let Some(els) = op.get("els").filter(|e| e.as_array().map(|a| !a.is_empty()).unwrap_or(false)) {
                    let add = obj(vec![("op", Json::text("add")), ("els", els.clone())]);
                    if let Err(e) = self.diagram_edit(id, &add) {
                        return Some(Err(e.to_string()));
                    }
                }
                if let Some(set) = op.get("settings").filter(|s| matches!(s, Json::Object(_))) {
                    let _ = self.diagram_edit(id, &obj(vec![("op", Json::text("settings")), ("set", set.clone())]));
                }
                if let Some(index) = op.get("index").and_then(|v| v.as_f64()).filter(|v| v.is_finite()) {
                    self.move_scene_diagram(id, index.max(0.0) as usize);
                }
                Ok(Special {
                    made: vec![id.0.to_string()],
                    undo: vec![obj(vec![("op", Json::text("diagram_delete")), ("id", Json::text(id.0.to_string())), ("confirmed", Json::Bool(true))])],
                })
            }
            "diagram_hide" => {
                // `{ids: [scene…], hidden}` — the Diagram list's Hide from
                // Diagrams / Show. The undo names only the scenes it changed.
                let hidden = op.get("hidden").and_then(|v| v.as_bool()).unwrap_or(true);
                let ids: Vec<Id> = op
                    .get("ids")
                    .and_then(|a| a.as_array())
                    .map(|a| a.iter().filter_map(|v| v.as_str()).filter_map(|t| t.trim().parse::<u128>().ok()).map(Id).collect())
                    .unwrap_or_default();
                let changing: Vec<Id> = ids.iter().map(|i| self.diagram_scene(*i)).filter(|s| self.scene_diagram_hidden(*s) != hidden).collect();
                self.set_scenes_diagram_hidden(&changing, hidden);
                Ok(Special {
                    made: Vec::new(),
                    undo: if changing.is_empty() {
                        Vec::new()
                    } else {
                        vec![obj(vec![
                            ("op", Json::text("diagram_hide")),
                            ("ids", Json::Array(changing.iter().map(|i| Json::text(i.0.to_string())).collect())),
                            ("hidden", Json::Bool(!hidden)),
                        ])]
                    },
                })
            }
            "cast_colour" => {
                let who = op.str_field("name").trim().to_string();
                if who.is_empty() {
                    return Some(Err("say whose colour".into()));
                }
                let field = self.cast_field().unwrap_or_else(|| "cast".to_string());
                let was = self
                    .stored_term_colours(&field)
                    .into_iter()
                    .find(|(t, _)| t.eq_ignore_ascii_case(&who))
                    .map(|(_, h)| format!("#{}", h.trim_start_matches('#')))
                    .unwrap_or_default();
                self.set_term_colour(&field, &who, &op.str_field("color"));
                Ok(Special {
                    made: Vec::new(),
                    undo: vec![obj(vec![("op", Json::text("cast_colour")), ("name", Json::text(who)), ("color", Json::text(was))])],
                })
            }
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json;

    fn film() -> (Doc, Id) {
        let mut doc = Doc::new(crate::stamp::DeviceId(7));
        doc.create_project("Portal");
        let scene = doc.create_scene("1");
        doc.clear_history();
        (doc, scene)
    }

    fn op(text: &str) -> Json {
        json::parse(text).expect("json")
    }

    #[test]
    fn a_scenes_diagrams_are_made_named_moved_deleted_and_brought_back() {
        let (mut doc, scene) = film();
        let wall = op(r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#);
        doc.diagram_edit(scene, &wall).unwrap();
        let id = Id::new();
        let made = doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_new","id":"{}","name":"Reverse","from":"{}"}}"#, id.0, scene.0))).unwrap().unwrap();
        assert_eq!(made.made, vec![id.0.to_string()], "made under the page's id");
        assert_eq!(doc.scene_diagram_ids(scene), vec![scene, id]);
        assert_eq!(doc.diagram_count(id), 1, "a copy of the first");
        // Again under the same id: the same one, not a second.
        doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_new","id":"{}","name":"Reverse"}}"#, id.0))).unwrap().unwrap();
        assert_eq!(doc.scene_diagram_ids(scene).len(), 2);

        let renamed = doc.portal_edit(id, &op(&format!(r#"{{"op":"diagram_rename","id":"{}","name":"Night"}}"#, id.0))).unwrap().unwrap();
        assert_eq!(doc.scene_diagram_name(id), "Night");
        doc.portal_edit(id, &renamed.undo[0]).unwrap().unwrap();
        assert_eq!(doc.scene_diagram_name(id), "Reverse", "rename taken back");

        let moved = doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_move","id":"{}","index":0}}"#, id.0))).unwrap().unwrap();
        assert_eq!(doc.scene_diagram_ids(scene), vec![id, scene]);
        doc.portal_edit(scene, &moved.undo[0]).unwrap().unwrap();
        assert_eq!(doc.scene_diagram_ids(scene), vec![scene, id]);

        let gone = doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_delete","id":"{}"}}"#, id.0))).unwrap().unwrap();
        assert_eq!(doc.scene_diagram_ids(scene), vec![scene]);
        let last = doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_delete","id":"{}"}}"#, scene.0))).unwrap();
        assert!(last.is_err(), "the last one stays");
        let back = doc.portal_edit(scene, &gone.undo[0]).unwrap().unwrap();
        let again = Id(back.made[0].parse().unwrap());
        assert_eq!(doc.scene_diagram_ids(scene), vec![scene, again]);
        assert_eq!(doc.scene_diagram_name(again), "Reverse");
        assert_eq!(doc.diagram_count(again), 1, "its pieces came back");

        // Hide from Diagrams / Show, and the edit that takes it back.
        let hid = doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_hide","ids":["{}"],"hidden":true}}"#, scene.0))).unwrap().unwrap();
        assert!(doc.scene_diagram_hidden(scene));
        doc.portal_edit(scene, &hid.undo[0]).unwrap().unwrap();
        assert!(!doc.scene_diagram_hidden(scene), "Hide taken back");
        let again_hid = doc.portal_edit(scene, &op(&format!(r#"{{"op":"diagram_hide","ids":["{}"],"hidden":false}}"#, scene.0))).unwrap().unwrap();
        assert!(again_hid.undo.is_empty(), "nothing changed, nothing to take back");
    }

    #[test]
    fn a_cast_colour_is_set_for_the_project_and_taken_back() {
        let (mut doc, scene) = film();
        doc.add_column("Cast", "multi");
        let field = doc.cast_field().expect("a Cast column");
        doc.set_vocabulary(&field, &["Maya", "Leo"]);
        let said = doc.portal_edit(scene, &op(r##"{"op":"cast_colour","name":"Leo","color":"#16A34A"}"##)).unwrap().unwrap();
        assert_eq!(doc.stored_term_colours(&field), vec![("Leo".to_string(), "16A34A".to_string())]);
        // Taken back: no colour of his own, so billing order again.
        doc.portal_edit(scene, &said.undo[0]).unwrap().unwrap();
        assert!(doc.stored_term_colours(&field).is_empty());
    }

    #[test]
    fn a_wipe_is_known_before_it_is_made() {
        let (mut doc, scene) = film();
        assert!(!wipes(&doc, scene, &op(r#"{"op":"copy_from","from":"1","mode":"replace"}"#)), "onto an empty plan nothing is lost");
        doc.diagram_edit(scene, &op(r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#)).unwrap();
        assert!(wipes(&doc, scene, &op(r#"{"op":"copy_from","from":"1","mode":"replace"}"#)));
        assert!(!wipes(&doc, scene, &op(r#"{"op":"copy_from","from":"1","mode":"add"}"#)));
        assert!(wipes(&doc, scene, &op(r#"{"op":"clear"}"#)));
        assert!(wipes(&doc, scene, &op(r#"{"op":"diagram_delete","id":"5"}"#)));
        assert!(!wipes(&doc, scene, &op(r#"{"op":"remove","ids":["a"]}"#)));
    }
}
