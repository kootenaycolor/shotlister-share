//! Where a diagram lives in the film.
//!
//! Each element is a `diagram_item` record: `scene` (which scene's plan),
//! `order` (where it sits in the stack) and `body` (the element, as JSON,
//! without its id — the record's id is its id). The scene carries the plan's
//! settings in its `diagram` field.
//!
//! An edit is worked out on a whole `Diagram` by `diagram::apply`, then the
//! difference is written back record by record inside one undo step. So the
//! arithmetic of an edit never has to know how it is stored, and a drag that
//! moves one camera writes one field.

use super::render::Context;
use super::{apply, copy, Diagram, EditError, El};
use crate::doc::{f, Doc};
use crate::id::Id;
use crate::Value;
use crate::json::{self, Json};
use crate::order;
use crate::store::Kind as RecordKind;

const BODY: &str = "body";

fn id_text(id: Id) -> String {
    id.0.to_string()
}

fn id_of(text: &str) -> Option<Id> {
    text.parse::<u128>().ok().map(Id)
}

impl Doc {
    /// The scene's plan, as it stands — a plan saved while lights' names
    /// lived on their symbols read with the names on its lights
    /// (`plot::own_names`); the move is written with its next edit.
    pub fn diagram(&self, scene: Id) -> Diagram {
        let mut d = self.diagram_stored(scene);
        super::plot::own_names(&mut d);
        d
    }

    /// The scene's plan exactly as stored.
    fn diagram_stored(&self, scene: Id) -> Diagram {
        let stored = self.get(scene).and_then(|r| r.text(f::DIAGRAM));
        let mut d = match stored {
            Some(text) => Diagram::parse(text),
            None => Diagram::default(),
        };
        d.els.clear();
        let mut items: Vec<(f64, Id, El)> = self
            .store()
            .referring_to(&RecordKind::DiagramItem, f::SCENE, scene)
            .iter()
            .filter_map(|r| {
                let body = json::parse(r.text(BODY)?)?;
                let mut with_id = match body {
                    Json::Object(pairs) => pairs,
                    _ => return None,
                };
                with_id.retain(|(k, _)| k != "id");
                with_id.push(("id".into(), Json::text(id_text(r.id))));
                let el = El::from_json(&Json::Object(with_id))?;
                Some((r.float(f::ORDER).unwrap_or(0.0), r.id, el))
            })
            .collect();
        // Stack order, and creation order where two claim the same place —
        // two devices adding at once.
        items.sort_by(|a, b| order::compare(a.0, b.0).then(a.1.cmp(&b.1)));
        d.els = items.into_iter().map(|(_, _, el)| el).collect();
        // Nothing stored and nothing on it: a plan not begun, which starts
        // quiet (`Settings::fresh`).
        if stored.is_none() && d.els.is_empty() {
            d.settings = super::Settings::fresh();
        }
        d
    }

    /// Scenes that have a plan with anything on it — live scenes, not set
    /// aside and not deleted, so a count agrees with the list it counts.
    pub fn scenes_with_diagrams(&self) -> Vec<Id> {
        let mut out: Vec<Id> = self
            .store()
            .of_kind(&RecordKind::DiagramItem)
            .iter()
            .filter_map(|r| r.ref_id(f::SCENE))
            // A scene's further diagrams count as the scene's.
            .map(|s| self.diagram_scene(s))
            // Scenes only: a loose plan's pieces point the same way.
            .filter(|s| self.get(*s).map(|r| !r.is_deleted() && r.kind == RecordKind::Scene).unwrap_or(false) && !self.is_archived(*s))
            .collect();
        out.sort();
        out.dedup();
        out
    }

    /// How many things are on every scene's plan, in one pass over the film.
    pub fn diagram_counts(&self) -> std::collections::HashMap<Id, usize> {
        let mut out = std::collections::HashMap::new();
        for r in self.store().of_kind(&RecordKind::DiagramItem) {
            if let Some(scene) = r.ref_id(f::SCENE) {
                *out.entry(scene).or_insert(0) += 1;
            }
        }
        out
    }

    /// How many things are on a scene's plan.
    pub fn diagram_count(&self, scene: Id) -> usize {
        self.store().referring_to(&RecordKind::DiagramItem, f::SCENE, scene).len()
    }

    /// Make one edit to a scene's plan, as one step of undo. Returns the ids
    /// the edit made — new elements' record ids, or a group's name.
    ///
    /// **A camera added with `"new_shot": true` brings its shot with it** —
    /// Cadrage's gesture, and the row he filed (SL-60): *"add a camera, get a
    /// shot."* The shot is made at the end of the scene and the camera stands
    /// for it, both in the one step undo takes back.
    pub fn diagram_edit(&mut self, scene: Id, op: &Json) -> Result<Vec<String>, EditError> {
        if op.get("op").and_then(|o| o.as_str()) == Some("camera_shot") {
            return self.diagram_camera_shot(scene, op);
        }
        // What is stored, so the names moved onto an old plan's lights
        // (`own_names`) are written with this edit.
        let before = self.diagram_stored(scene);
        let mut after = before.clone();
        super::plot::own_names(&mut after);
        let mut op = op.clone();
        // Asked for on each camera, or once for the whole add — then every
        // camera in it that names no shot of its own gets one.
        let for_all = op.get("new_shot").and_then(|b| b.as_bool()) == Some(true);
        let asks = move |e: &Json| {
            e.get("new_shot").and_then(|b| b.as_bool()) == Some(true)
                || (for_all && e.get("kind").and_then(|k| k.as_str()) == Some("camera") && e.get("shot").is_none())
        };
        // A loose plan has no shots for a camera to stand for.
        // A scene's further diagram makes the scene's shots.
        let of = self.diagram_scene(scene);
        let wants_shots = self.get(of).map(|r| r.kind == RecordKind::Scene).unwrap_or(false)
            && op.get("op").and_then(|o| o.as_str()) == Some("add")
            && op.get("els").and_then(|e| e.as_array()).map(|a| a.iter().any(asks)).unwrap_or(false);
        // **A picture has to be a picture this film holds.** Ref 1615: a plan
        // was given `{"kind":"image","media":"<hash>.jpg"}` for a file
        // uploaded straight to the bucket, so no media record was ever made.
        // Nothing refused it. The portal drew it — it fetches the bucket by
        // name — and the Mac and the phone never could: they learn a file
        // exists from its record, so `missing_media` could not see it,
        // `wanted_stems` never asked for it, and sync said "Up to date" for
        // ever. The picture was blank on his Mac with nothing anywhere saying
        // why. A named file the film has no record of is refused here, at the
        // one door every edit comes through.
        if let Some(name) = self.names_no_picture(&op) {
            return Err(EditError::NoSuchPicture(name));
        }
        // Try the edit first on a copy, so a refused edit writes nothing — not
        // even a shot.
        apply(&mut after.clone(), &op)?;
        let label = label_for(&op, &before, &after);
        let tx = self.begin(&label);
        if wants_shots {
            if let Json::Object(pairs) = &mut op {
                for (k, v) in pairs.iter_mut() {
                    if k != "els" {
                        continue;
                    }
                    if let Json::Array(els) = v {
                        for e in els.iter_mut() {
                            if !asks(e) {
                                continue;
                            }
                            let (shot, _) = self.add_shot_to_scene(of);
                            if let Json::Object(fields) = e {
                                fields.retain(|(k, _)| k != "new_shot" && k != "shot");
                                fields.push(("shot".into(), Json::text(id_text(shot))));
                            }
                        }
                    }
                }
            }
        }
        let made = match apply(&mut after, &op) {
            Ok(m) => m,
            Err(e) => {
                self.end(tx);
                return Err(e);
            }
        };
        let renamed = self.diagram_store(scene, &before, &after, &label);
        self.end(tx);
        Ok(made
            .into_iter()
            .map(|id| renamed.iter().find(|(from, _)| *from == id).map(|(_, to)| to.clone()).unwrap_or(id))
            .collect())
    }

    /// **A camera's Camera, Lens and focal length** — `{"op":"camera_shot",
    /// "id":<camera>,"set":{"unit":<camera record id>,"lens":"24-70mm",
    /// "focal":35}}`, any of the three — and its shot's **Size** and
    /// **Movement** (`"size":"MCU"`, `"movement":"Push In"`), his ask of
    /// 2026-10-02 for the portal's Edit, as the Mac's shot card sets them.
    ///
    /// A camera on the plan is its shot (his design, 2026-10-01), so with a
    /// shot these are written to the shot — the shot list shows them — and
    /// without one, to the plan's camera (`unit`, `lens_name`, `lens`); a
    /// camera with no shot has no Size or Movement to set. One step of undo.
    /// `""` clears. A term off a locked list does not land.
    fn diagram_camera_shot(&mut self, scene: Id, op: &Json) -> Result<Vec<String>, EditError> {
        let id = op.get("id").and_then(|v| v.as_str()).ok_or(EditError::Unreadable)?.to_string();
        let set = op.get("set").ok_or(EditError::Unreadable)?;
        let before = self.diagram_stored(scene);
        let cam = before.get(&id).filter(|e| e.kind == super::Kind::Camera).ok_or_else(|| EditError::Missing(id.clone()))?.clone();
        let text = |k: &str| set.get(k).map(|v| v.as_str().map(str::to_string).unwrap_or_else(|| v.as_f64().map(|n| n.to_string()).unwrap_or_default()));
        let (unit, lens, focal) = (text("unit"), text("lens"), text("focal"));
        let (size, movement) = (text("size"), text("movement"));
        // The shot's own words and lists, as the Mac's Details sets them
        // (2026-10-09, the portal's Edit): its Title and Description, Shot
        // Angle (several), Equipment, and any of the film's own columns by
        // name (`columns`: {"Cast": "Gio, Anna"}), each as its column reads.
        let (title, description, angle, support) = (text("title"), text("description"), text("angle"), text("support"));
        let columns: Vec<(String, String)> = match set.get("columns") {
            Some(Json::Object(pairs)) => pairs.iter().map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string())).collect(),
            _ => Vec::new(),
        };
        let mm = |t: &str| -> Result<Option<f64>, EditError> {
            let t = t.trim().trim_end_matches("mm").trim();
            if t.is_empty() {
                return Ok(None);
            }
            t.parse::<f64>().ok().filter(|v| v.is_finite() && *v > 0.0).map(Some).ok_or(EditError::Unreadable)
        };
        let unit_id = match unit.as_deref().map(str::trim) {
            Some("") | None => None,
            Some(u) => Some(
                u.parse::<u128>().ok().map(Id).filter(|i| self.get(*i).map(|r| r.kind == RecordKind::Unit) == Some(true))
                    .ok_or_else(|| EditError::Missing(u.to_string()))?,
            ),
        };
        let focal_mm = match &focal { Some(t) => mm(t)?, None => None };
        let shot = id_of(&cam.shot).filter(|s| self.get(*s).is_some());
        let tx = self.begin("Camera");
        match shot {
            Some(shot) => {
                let said = self.described_by(shot);
                if unit.is_some() {
                    self.set(shot, f::UNIT, unit_id.map(Value::Ref).unwrap_or(Value::Null));
                }
                if let Some(lens) = &lens {
                    self.set_vocab_field(said, f::LENS, lens.trim());
                }
                if focal.is_some() {
                    self.set(said, f::FOCAL, focal_mm.map(Value::Float).unwrap_or(Value::Null));
                }
                if let Some(size) = &size {
                    self.set_vocab_field(said, f::SIZE, size.trim());
                }
                if let Some(movement) = &movement {
                    self.set_vocab_field(said, f::MOVEMENT, movement.trim());
                }
                if let Some(t) = &title {
                    self.set(said, f::TITLE, t.as_str());
                }
                if let Some(t) = &description {
                    self.set(said, f::DESCRIPTION, t.as_str());
                }
                if let Some(a) = &angle {
                    let parts: Vec<&str> = a.split(',').map(str::trim).filter(|p| !p.is_empty()).collect();
                    self.set_vocab_list(said, f::ANGLE, &parts);
                }
                if let Some(v) = &support {
                    self.set_vocab_field(said, f::SUPPORT, v.trim());
                }
                for (said_name, value) in &columns {
                    // By its slug, or by the name he gave it ("Cast").
                    let name = if self.custom_column_kind(said_name).is_some() {
                        said_name.clone()
                    } else {
                        self.custom_columns().into_iter().find(|c| c.label.eq_ignore_ascii_case(said_name.trim())).map(|c| c.field).unwrap_or_default()
                    };
                    let name = &name;
                    match self.custom_column_kind(name).as_deref() {
                        Some("single") => self.set_vocab_field(shot, name, value.trim()),
                        Some("multi") => {
                            let parts: Vec<&str> = value.split(',').map(str::trim).filter(|p| !p.is_empty()).collect();
                            self.set_vocab_list(shot, name, &parts);
                        }
                        Some("check") => {
                            let on = !value.is_empty() && value != "0" && value != "false";
                            self.set(shot, name, Value::Bool(on));
                        }
                        Some(_) => self.set(shot, name, value.as_str()),
                        // Not one of the film's columns: nothing written.
                        None => {}
                    }
                }
            }
            None if unit.is_none() && lens.is_none() && focal.is_none() => {}
            None => {
                let mut after = before.clone();
                super::plot::own_names(&mut after);
                let mut fields: Vec<(String, Json)> = Vec::new();
                if let Some(u) = &unit {
                    fields.push(("unit".into(), Json::text(u.trim())));
                }
                if let Some(l) = &lens {
                    fields.push(("lens_name".into(), Json::text(l.trim())));
                    fields.push(("lens".into(), Json::Number(0.0)));
                }
                if focal.is_some() {
                    fields.push(("lens".into(), Json::Number(focal_mm.unwrap_or(0.0))));
                }
                let put = Json::Object(vec![
                    ("op".into(), Json::text("update")),
                    ("ids".into(), Json::Array(vec![Json::text(&id)])),
                    ("set".into(), Json::Object(fields)),
                ]);
                if let Err(e) = apply(&mut after, &put) {
                    self.end(tx);
                    return Err(e);
                }
                self.diagram_store(scene, &before, &after, "Camera");
            }
        }
        self.end(tx);
        Ok(Vec::new())
    }

    /// Replace a scene's plan with another wholesale — a paste of a whole
    /// plan, or a plan copied from another scene. One undo step.
    pub fn diagram_replace(&mut self, scene: Id, with: &Diagram, label: &str) -> Vec<(String, String)> {
        let before = self.diagram_stored(scene);
        self.diagram_store(scene, &before, with, label)
    }

    /// Write the difference between two plans. New elements get records, and
    /// their temporary ids are returned beside their real ones.
    fn diagram_store(&mut self, scene: Id, before: &Diagram, after: &Diagram, label: &str) -> Vec<(String, String)> {
        let tx = self.begin(label);
        let mut renamed: Vec<(String, String)> = Vec::new();

        let settings_of = |d: &Diagram| {
            let mut j = d.to_json();
            if let Json::Object(pairs) = &mut j {
                pairs.retain(|(k, _)| k != "els" && k != "view");
            }
            j.encode()
        };
        // Measured against what is stored: a plan with no settings of its
        // own yet reads as the defaults, so a new plan's quiet start is
        // written with its first edit.
        let stored = self.get(scene).and_then(|r| r.text(f::DIAGRAM)).is_some();
        let old_settings = if stored { settings_of(before) } else { settings_of(&Diagram::default()) };
        let new_settings = settings_of(after);
        if old_settings != new_settings {
            self.set(scene, f::DIAGRAM, new_settings);
        }

        // Removed.
        for gone in before.els.iter().filter(|e| after.get(&e.id).is_none()) {
            if let Some(id) = id_of(&gone.id) {
                if self.get(id).map(|r| r.kind == RecordKind::DiagramItem).unwrap_or(false) {
                    // A picture lets go of its file; the file stays while
                    // anything else — a copy of it, a shot — still holds it.
                    self.release_media_uses(id);
                    self.delete(id);
                }
            }
        }

        // What is already stored where, so only what moved in the stack is
        // rewritten.
        let mut positions: Vec<(String, f64)> = before
            .els
            .iter()
            .filter_map(|e| {
                let id = id_of(&e.id)?;
                Some((e.id.clone(), self.get(id)?.float(f::ORDER).unwrap_or(0.0)))
            })
            .collect();

        // Every new piece gets its record first, so an aim at another new
        // piece — or a lamp riding a new stand — can be written with the id
        // it will really have.
        let existing = |el: &El, doc: &Self| before.get(&el.id).is_some() && id_of(&el.id).and_then(|id| doc.get(id)).is_some();
        let new_ones: Vec<String> = after.els.iter().filter(|el| !existing(el, self)).map(|el| el.id.clone()).collect();
        let mut fresh: Vec<(String, Id)> = Vec::new();
        for temp in new_ones {
            let id = self.create_record(RecordKind::DiagramItem);
            self.set(id, f::SCENE, scene);
            fresh.push((temp, id));
        }
        let aimed = |el: &El| -> El {
            let mut el = el.clone();
            if let Some((_, id)) = fresh.iter().find(|(from, _)| *from == el.aim) {
                el.aim = id_text(*id);
            }
            if let Some((_, id)) = fresh.iter().find(|(from, _)| *from == el.rig_on) {
                el.rig_on = id_text(*id);
            }
            // A lamp tied to a label made in the same edit (`share_label`).
            if let Some((_, id)) = fresh.iter().find(|(from, _)| *from == el.tie_to) {
                el.tie_to = id_text(*id);
            }
            for pin in [&mut el.start_on, &mut el.end_on] {
                if let Some((_, id)) = fresh.iter().find(|(from, _)| from == pin) {
                    *pin = id_text(*id);
                }
            }
            el
        };
        let mut real_ids: Vec<String> = Vec::with_capacity(after.els.len());
        for el in &after.els {
            let el = &aimed(el);
            if let Some(old) = before.get(&el.id).filter(|_| !fresh.iter().any(|(t, _)| *t == el.id)) {
                if old != el {
                    self.set(id_of(&el.id).unwrap(), BODY, body_of(el));
                }
                // **A picture swapped keeps hold of the right file.** The
                // element's hold was made when it was added and nothing moved
                // it, so swapping one picture for another left the element
                // holding the picture it no longer draws — and the one it does
                // draw held by nobody, free to be reclaimed as an orphan the
                // next time every device had heard. Ref 1615.
                if old.media != el.media {
                    if let Some(id) = id_of(&el.id) {
                        self.release_media_uses(id);
                        if let Some(media) = self.media_named(&el.media) {
                            self.attach_media(id, media, "");
                        }
                    }
                }
                real_ids.push(el.id.clone());
            } else {
                let id = fresh.iter().find(|(from, _)| *from == el.id).map(|(_, id)| *id).expect("made above");
                self.set(id, BODY, body_of(el));
                // A pasted, duplicated or copied picture holds its file in its
                // own right, so taking away the one it came from cannot take
                // the file from under it.
                if let Some(media) = self.media_named(&el.media) {
                    self.attach_media(id, media, "");
                }
                let real = id_text(id);
                if real != el.id {
                    renamed.push((el.id.clone(), real.clone()));
                }
                positions.push((real.clone(), f64::NAN));
                real_ids.push(real);
            }
        }

        // Stack order: walk the new order and give a fresh place only to what
        // is out of step with its neighbours.
        let place_of = |id: &str, positions: &[(String, f64)]| positions.iter().find(|p| p.0 == id).map(|p| p.1).unwrap_or(f64::NAN);
        let mut wanted: Vec<f64> = real_ids.iter().map(|id| place_of(id, &positions)).collect();
        let mut prev: Option<f64> = None;
        for i in 0..wanted.len() {
            let ok = wanted[i].is_finite() && prev.map(|p| wanted[i] > p).unwrap_or(true);
            if !ok {
                let next = wanted[i + 1..]
                    .iter()
                    .copied()
                    .find(|v| v.is_finite() && prev.map(|p| *v > p).unwrap_or(true));
                wanted[i] = order::between(prev, next);
            }
            prev = Some(wanted[i]);
        }
        if order::needs_renormalize(&wanted) {
            wanted = order::renormalize(wanted.len());
        }
        for (i, id) in real_ids.iter().enumerate() {
            let now = place_of(id, &positions);
            if !(now.is_finite() && (now - wanted[i]).abs() < 1e-12) {
                if let Some(rid) = id_of(id) {
                    self.set(rid, f::ORDER, wanted[i]);
                }
            }
        }
        self.end(tx);
        renamed
    }

    /// **The first picture an edit names that this film has no file for**, or
    /// `None` when every one of them is accounted for. Ref 1615.
    ///
    /// Only `add` and `update` are asked, because they are the only edits that
    /// introduce a *name* — a caller typing one in. `duplicate`, `copy_from`
    /// and `send` carry a name an element already has, and refusing those
    /// would make an already-hollow picture impossible to tidy up.
    fn names_no_picture(&self, op: &Json) -> Option<String> {
        let named = |value: Option<&Json>| -> Option<String> {
            let name = value?.as_str()?.trim();
            if name.is_empty() || self.media_named(name).is_some() {
                return None;
            }
            Some(name.to_string())
        };
        match op.get("op").and_then(|o| o.as_str()).unwrap_or("") {
            // A batch is every edit in it, in order.
            "batch" => op
                .get("ops")
                .and_then(|o| o.as_array())?
                .iter()
                .find_map(|one| self.names_no_picture(one)),
            "add" => op
                .get("els")
                .and_then(|e| e.as_array())?
                .iter()
                .filter(|e| e.get("kind").and_then(|k| k.as_str()) == Some("image"))
                .find_map(|e| named(e.get("media"))),
            // A picture swapped for another one under an element that is
            // already a picture.
            "update" => named(op.get("set").and_then(|s| s.get("media"))),
            _ => None,
        }
    }

    /// The film's file a picture element names — `hash32.ext`, the start of
    /// the file's hash.
    fn media_named(&self, name: &str) -> Option<Id> {
        let stem = name.split('.').next().filter(|s| s.len() >= 16)?;
        self.store()
            .of_kind(&RecordKind::Media)
            .iter()
            .find(|r| r.text(f::HASH).map(|h| h.starts_with(stem)).unwrap_or(false))
            .map(|r| r.id)
    }

    /// A scene on its way out takes its plan with it — part of the same
    /// undo step as the scene, so taking the scene back brings the plan.
    pub(crate) fn diagram_forget(&mut self, scene: Id) {
        let items: Vec<Id> = self
            .store()
            .referring_to(&RecordKind::DiagramItem, f::SCENE, scene)
            .iter()
            .map(|r| r.id)
            .collect();
        for id in items {
            self.release_media_uses(id);
            self.delete(id);
        }
    }

    /// Lay a scanned room on a scene's plan, replacing a room laid before.
    pub fn diagram_import_room(&mut self, scene: Id, plan: &crate::room::Plan, location: &str) -> Vec<String> {
        let before = self.diagram_stored(scene);
        let mut after = before.clone();
        super::plot::own_names(&mut after);
        let made = super::import_room(&mut after, plan, location);
        let renamed = self.diagram_store(scene, &before, &after, "Add Room");
        made.into_iter()
            .map(|id| renamed.iter().find(|(from, _)| *from == id).map(|(_, to)| to.clone()).unwrap_or(id))
            .collect()
    }

    /// Start a scene's plan from another scene's: the room, the furniture,
    /// the lights, the people — every camera comes too, but loose from its
    /// shot, because that scene's shots are not this one's. What is on this
    /// scene's plan already is replaced. One undo step.
    pub fn diagram_copy_from(&mut self, scene: Id, from: Id) -> usize {
        self.diagram_copy(from, &[], &[scene], copy::Mode::Replace).len()
    }

    /// **A plan, or the pieces `ids` of it, copied onto other scenes' plans**
    /// — Copy From, Copy To and Send to Scene (`copy::copied` says what
    /// comes across and how). `mode` says whether what each plan holds is
    /// replaced or added to. One undo step for every scene it lands on;
    /// `from` itself is skipped. Answers the new pieces' ids, scene by scene
    /// in the order given — the portal pairs its own copy's ids with the
    /// server's by them, so an Undo there reaches the film.
    pub fn diagram_copy(&mut self, from: Id, ids: &[String], to: &[Id], mode: copy::Mode) -> Vec<String> {
        let source = self.diagram(from);
        let label = if ids.is_empty() { "Copy Diagram" } else { "Send to Scene" };
        let tx = self.begin(label);
        let mut out = Vec::new();
        for &scene in to.iter().filter(|s| **s != from) {
            let before = self.diagram_stored(scene);
            let mut base = before.clone();
            super::plot::own_names(&mut base);
            let (after, made) = copy::copied(&source, ids, &base, mode);
            let renamed = self.diagram_store(scene, &before, &after, label);
            out.extend(made.into_iter().map(|id| renamed.iter().find(|(t, _)| *t == id).map(|(_, r)| r.clone()).unwrap_or(id)));
        }
        self.end(tx);
        out
    }

    /// One plan setting set on **every scene of the film at once** — the
    /// Light Beams switch is the film's, not one scene's (his ruling,
    /// 2026-09-28). One undo step. Scenes already so are left alone.
    pub fn diagram_setting_everywhere(&mut self, key: &str, value: Json) -> usize {
        let tx = self.begin(match key {
            "beams" => "Light Beams",
            "levels" => "Light Levels",
            "colours" => "Plot Colours",
            _ => "Plan Setting",
        });
        let op = Json::object(vec![
            ("op", Json::text("settings")),
            ("set", Json::object(vec![(key, value)])),
        ]);
        let mut n = 0;
        for scene in self.scenes_in_order() {
            for id in self.scene_diagram_ids(scene) {
                if self.diagram_edit(id, &op).is_ok() {
                    n += 1;
                }
            }
        }
        self.end(tx);
        n
    }

    /// **A picture laid under the plan** — a floor plan he was sent, a photo
    /// of the room from above — or, with `photo`, a loose one over it. The file is the film's like any other (added by
    /// its hash, so the same picture twice is one file); the element that
    /// shows it holds it, through a media use owned by the element's own
    /// record, so the picture lives exactly as long as the element does and
    /// never turns up among the scene's pinned references. One undo step.
    #[allow(clippy::too_many_arguments)]
    pub fn diagram_add_image(
        &mut self,
        scene: Id,
        hash: crate::hash::Hash256,
        ext: &str,
        pixels: (u32, u32),
        bytes: u64,
        filename: &str,
        at: (f64, f64),
        width_m: f64,
        photo: bool,
    ) -> Option<String> {
        let tx = self.begin("Add Picture");
        let media = self.add_media(hash, crate::media::MediaKind::Image, pixels.0, pixels.1, bytes, filename);
        let aspect = if pixels.0 > 0 && pixels.1 > 0 { pixels.1 as f64 / pixels.0 as f64 } else { 0.75 };
        let hex = hash.to_hex();
        let name = format!("{}.{}", &hex[..hex.len().min(32)], ext.trim_start_matches('.'));
        let op = Json::object(vec![
            ("op", Json::text("add")),
            (
                "els",
                Json::Array(vec![Json::object(vec![
                    ("kind", Json::text("image")),
                    ("x", Json::Number(at.0)),
                    ("y", Json::Number(at.1)),
                    ("w", Json::Number(width_m.max(0.5))),
                    ("h", Json::Number((width_m * aspect).max(0.3))),
                    ("media", Json::text(&name)),
                    // Full strength, a Background too (his pick, 2026-10-15).
                    ("opacity", Json::Number(1.0)),
                    ("role", Json::text(if photo { "photo" } else { "" })),
                ])]),
            ),
        ]);
        // The element holds the file as it is written — `diagram_store` gives
        // every new picture its own use.
        let _ = media;
        let made = self.diagram_edit(scene, &op).ok();
        self.end(tx);
        made?.first().cloned()
    }

    /// What a scene's plan needs to know about the film: its shots' numbers
    /// and lenses, and who is in the cast.
    /// Who can stand on this scene's plan: the characters the script puts in
    /// the scene, then every other character in the film — the Cast
    /// column's list and anyone the script names in another scene. Asked
    /// for when someone is placed, never while a plan is dragged: it walks
    /// every scene.
    pub fn diagram_characters(&self, scene: Id) -> (Vec<String>, Vec<String>) {
        let scene = self.diagram_scene(scene);
        let here = self.scene_cast(scene);
        let mut others: Vec<String> = Vec::new();
        let mut add = |name: String, others: &mut Vec<String>| {
            let name = name.trim().to_string();
            if !name.is_empty()
                && !here.iter().any(|h| h.eq_ignore_ascii_case(&name))
                && !others.iter().any(|o| o.eq_ignore_ascii_case(&name))
            {
                others.push(name);
            }
        };
        for name in self.cast_list() {
            add(name, &mut others);
        }
        for s in self.scenes_in_order() {
            for name in self.scene_cast(s) {
                add(name, &mut others);
            }
        }
        others.sort_by_key(|n| n.to_lowercase());
        (here, others)
    }

    /// **A shot's lead frame, as a plan names a picture**: `<hash>.<ext>` —
    /// the first 32 of the hash, and the extension the portal gives the same
    /// file (`extensionOf` in `film.js`), so the portal finds it among the
    /// film's pictures — and its height over its width.
    ///
    /// **A clip is its poster** (his note, 2026-09-28: *"videos are still not
    /// showing up in plan"*): the still every other place draws for it,
    /// kept beside the movie under the same hash as a `.jpg` (a `.png` in
    /// films written before 2026-09-15 — every reader takes either).
    pub fn diagram_frame(&self, shot: Id) -> Option<(String, f64)> {
        let said = self.described_by(shot);
        let use_ = self.key_media_ref(said)?;
        let media = self.get(use_)?.ref_id(f::MEDIA)?;
        let moving = match self.media_kind(media) {
            // A GIF draws as itself, its first frame.
            Some(crate::media::MediaKind::Image | crate::media::MediaKind::Gif) => false,
            Some(crate::media::MediaKind::Video) => true,
            _ => return None,
        };
        let record = self.get(media)?;
        let hash = record.text(f::HASH)?.to_string();
        if hash.is_empty() {
            return None;
        }
        let name = self.media_ref_name(use_);
        let ext: String = name
            .rsplit('.')
            .next()
            .filter(|_| name.contains('.'))
            .unwrap_or("")
            .to_lowercase()
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .take(8)
            .collect();
        let ext = if moving { "jpg".to_string() } else if ext.is_empty() { "png".to_string() } else { ext };
        let w = record.get(f::WIDTH).and_then(|v| v.as_int()).unwrap_or(0) as f64;
        let h = record.get(f::HEIGHT).and_then(|v| v.as_int()).unwrap_or(0) as f64;
        let aspect = if w > 0.0 && h > 0.0 { h / w } else { 9.0 / 16.0 };
        Some((format!("{}.{}", &hash[..hash.len().min(32)], ext), aspect))
    }

    pub fn diagram_context(&self, scene: Id) -> Context {
        let mut ctx = Context::default();
        let mut seen = std::collections::HashSet::new();
        // This scene's shots, and any other shot a camera here stands for — it
        // may have moved scene, and should still say which it is. Only those:
        // walking every scene in the film cost 10 ms a drag frame at 184 scenes.
        // A scene's further diagram reads as the scene (`scenediagrams`).
        let owner = scene;
        let scene = self.diagram_scene(owner);
        let mut placements: Vec<Id> = self.placements_in_scene(scene);
        let mut cameras: Vec<Id> = Vec::new();
        for e in self.diagram(owner).els {
            if let Some(shot) = id_of(&e.shot) {
                placements.extend(self.placements_of_shot(shot).into_iter().take(1));
                if e.kind == super::Kind::Camera && !cameras.contains(&shot) {
                    cameras.push(shot);
                }
            }
        }
        // Each camera's shot frame, for a camera that lays it on the plan.
        for shot in cameras {
            if let Some(frame) = self.diagram_frame(shot) {
                ctx.frames.push((id_text(shot), frame.0, frame.1));
            }
        }
        for placement in placements {
            let Some(shot) = self.get(placement).and_then(|r| r.ref_id(f::SHOT)) else { continue };
            if !seen.insert(shot) {
                continue;
            }
            let said = self.described_by(shot);
            let lens = self.get(said).and_then(|r| r.text(f::LENS)).unwrap_or("").to_string();
            let number = self.display_number(placement).unwrap_or_default();
            ctx.shots.push((id_text(shot), number, lens));
            // Its camera — its own, not the master's — and where a zoom is set.
            if let Some(unit) = self.get(shot).and_then(|r| r.ref_id(f::UNIT)) {
                ctx.shot_units.push((id_text(shot), id_text(unit)));
            }
            if let Some(mm) = self.get(said).and_then(|r| r.get(f::FOCAL)).and_then(|v| v.as_float()) {
                ctx.shot_focals.push((id_text(shot), mm));
            }
        }
        // For the sun: where the scene is shot, the day it is shot on, and the
        // time of day its heading says.
        ctx.place = self.location_of_scene(scene).and_then(|place| {
            let (lat, lon) = self.location_pin(place)?;
            Some((lat.trim().parse::<f64>().ok()?, lon.trim().parse::<f64>().ok()?))
        });
        ctx.date = self
            .days_of_scene(scene)
            .into_iter()
            .map(|day| self.day_date(day))
            .find(|date| !date.is_empty())
            .unwrap_or_default();
        // The film's cameras, with the sensor he typed for each.
        let units: Vec<Id> = self.store().of_kind(&RecordKind::Unit).iter().map(|r| r.id).collect();
        for unit in units {
            let label = self.get(unit).and_then(|r| r.text(f::LABEL)).unwrap_or("").trim().to_string();
            if label.is_empty() {
                continue;
            }
            let gate = self.unit_sensor(unit).map(|(name, w, h)| super::lens::Gate { id: id_text(unit), name, w, h });
            ctx.units.push((id_text(unit), label, gate));
        }
        // The frame Studio draws at (piece E), else the film's own.
        ctx.ratio = self.film_ratio_said().unwrap_or(0.0);
        ctx.time_of_day = self.get(scene).and_then(|r| r.text(f::TIME_OF_DAY)).unwrap_or("").to_string();
        // Each character's colour, as their Cast chip wears it: the one he
        // gave them, else the column's own (`Brand.chipInk` on the Mac).
        if let Some(field) = self.cast_field() {
            ctx.cast_colours = self.term_colours(&field).into_iter().map(|(name, hex)| (name.trim().to_lowercase(), hex)).collect();
            ctx.cast_ink = column_ink(&field).to_string();
        }
        ctx
    }
}

/// A column's own colour when it names none of its values: one of the eight
/// chip inks, picked by a hash of its name — the Mac's `Brand.columnInk`,
/// sum for sum, so a character's figure on the plan and their chip in the
/// table are the same colour.
fn column_ink(field: &str) -> &'static str {
    const INKS: [&str; 8] = ["2C7A7B", "2B6CB0", "4C51BF", "7B4BC4", "A33574", "9A6B10", "2F7A44", "B4531B"];
    let key = field.trim().to_lowercase();
    let mut hash: u64 = 5381;
    for byte in key.bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(byte as u64);
    }
    INKS[(hash % INKS.len() as u64) as usize]
}

fn body_of(el: &El) -> String {
    let mut j = el.to_json();
    if let Json::Object(pairs) = &mut j {
        pairs.retain(|(k, _)| k != "id");
    }
    j.encode()
}

/// What the undo menu calls an edit.
fn label_for(op: &Json, before: &Diagram, after: &Diagram) -> String {
    let name = op.get("op").and_then(|o| o.as_str()).unwrap_or("");
    let kind_of_add = || {
        op.get("els")
            .and_then(|e| e.as_array())
            .and_then(|a| a.first())
            .and_then(|e| e.get("kind"))
            .and_then(|k| k.as_str())
            .unwrap_or("")
            .to_string()
    };
    match name {
        "add" => match kind_of_add().as_str() {
            "" => "Add to Diagram".into(),
            "light" if light_kind_is_grip(op) => "Add Grip".into(),
            k => format!("Add {}", title(k)),
        },
        "update" => update_label(op, before),
        "remove" => "Delete".into(),
        "move" => "Move".into(),
        "rotate" => "Rotate".into(),
        "flip" => "Flip".into(),
        "order" => "Arrange".into(),
        "duplicate" => "Duplicate".into(),
        "group" => "Group".into(),
        "ungroup" => "Ungroup".into(),
        "align" => "Align".into(),
        "distribute" => "Distribute".into(),
        "beat" => "Move Beat".into(),
        "unbeat" => "Remove Beat".into(),
        "step_add" if op.get("turn").and_then(|t| t.as_bool()) == Some(true) => "Add Turn".into(),
        "step_add" => "Add Move".into(),
        "step_set" if op.get("beat").is_some() && op.get("x").is_none() && op.get("rot").is_none() => "Set Beat".into(),
        "step_set" if op.get("x").is_none() && op.get("rot").is_some() => "Turn".into(),
        "step_set" => "Move Step".into(),
        "step_remove" => "Remove Step".into(),
        "swap" => "Swap".into(),
        "settings" => "Change Diagram".into(),
        "ride" => "Ride Track".into(),
        "share_label" => "Share Label".into(),
        "own_label" => "Own Label".into(),
        // A batch says what its first edit does — a turn that lets go of
        // an aim is a Turn, a move at a beat a Move.
        "batch" => op
            .get("ops")
            .and_then(|o| o.as_array())
            .and_then(|a| {
                let labels: Vec<String> = a.iter().map(|o| label_for(o, before, after)).collect();
                labels.iter().find(|l| *l != "Change Diagram" && *l != "Aim").or(labels.first()).cloned()
            })
            .unwrap_or_else(|| "Move".into()),
        "clear" => "Clear Diagram".into(),
        _ => "Change Diagram".into(),
    }
}

/// Whether the first piece an add brings is grip — a light-kind piece that
/// gives no light.
fn light_kind_is_grip(op: &Json) -> bool {
    op.get("els")
        .and_then(|e| e.as_array())
        .and_then(|a| a.first())
        .and_then(|e| e.get("sym"))
        .and_then(|s| s.as_str())
        .map(|s| !super::symbols::emits(s))
        .unwrap_or(false)
}

/// **Undo says what it undid** (Scenario's "Undo Add Box"): an update is
/// named by what it changed.
fn update_label(op: &Json, before: &Diagram) -> String {
    let Some(Json::Object(set)) = op.get("set") else { return "Change Diagram".into() };
    let keys: Vec<&str> = set.iter().map(|(k, _)| k.as_str()).collect();
    if keys.is_empty() {
        return "Change Diagram".into();
    }
    let only = |allowed: &[&str]| keys.iter().all(|k| allowed.contains(k));
    let truthy = |k: &str| set.iter().find(|(n, _)| n == k).and_then(|(_, v)| v.as_bool()).unwrap_or(false);
    if only(&["x", "y"]) {
        return "Move".into();
    }
    if keys.contains(&"rot") && only(&["rot", "x", "y", "h"]) {
        return "Turn".into();
    }
    if keys.iter().any(|k| ["w", "h", "tall"].contains(k)) && only(&["w", "h", "tall", "x", "y"]) {
        return "Resize".into();
    }
    let one = if keys.len() == 1 { keys[0] } else { "" };
    let named = match one {
        "aim" => "Aim",
        "label" => "Rename",
        "locked" if truthy("locked") => "Lock",
        "locked" => "Unlock",
        "hidden" if truthy("hidden") => "Hide",
        "hidden" => "Show",
        "beam_on" => "Beam",
        "dim" => "Dimmer",
        "reach" => "Reach",
        "beam" => "Spread",
        "color" => "Colour",
        "curve" => "Bend",
        "tilt" => "Tilt",
        "gels" => "Gels",
        "text" => "Edit Text",
        "move" => "Move To",
        _ => "",
    };
    if !named.is_empty() {
        return named.into();
    }
    let id = op
        .get("ids")
        .and_then(|i| i.as_array())
        .and_then(|a| a.first())
        .and_then(|i| i.as_str())
        .or_else(|| op.get("id").and_then(|i| i.as_str()));
    match id.and_then(|id| before.get(id)) {
        Some(e) => format!("Change {}", title(e.kind.as_str())),
        None => "Change Diagram".into(),
    }
}

fn title(kind: &str) -> String {
    match kind {
        "set" => "Set Piece".into(),
        "cast" => "Cast".into(),
        other => {
            let mut c = other.chars();
            match c.next() {
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                None => String::new(),
            }
        }
    }
}
