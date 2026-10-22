//! **Several diagrams on one scene** (his ask, 2026-10-17: *"be able to do
//! multiple diagrams per scene"*) — a Wide Setup, a Reverse, a Night Version.
//!
//! **The scene's own diagram is always one of them**, so nothing about a
//! film made before this had to move: the scene still holds its pieces and
//! settings exactly as it did. Every further diagram is a `Kind::Plan` record
//! carrying `of_scene`, a pointer at the scene it belongs to — kept like a
//! loose plan (`plans.rs`), so drawing, beats, pictures and copying all take
//! its id unchanged — but left out of the loose plans' list, and read as the
//! scene for everything a scene gives a diagram: its shots, where and when it
//! is shot, its cast.
//!
//! Each has a name he types (his free-labels rule, 2026-10-17); an unnamed
//! one shows "Diagram N" by its place as a placeholder only. They sit in an
//! order he can change, the scene's own included (`diagram_order` on the
//! scene; `order` on the others). Deleting one he is asked about first; the
//! last one on a scene cannot be deleted, only cleared. Deleting the scene's
//! own diagram while others remain moves the next one's pieces into its
//! place — re-pointed, not copied — so cameras keep their shots.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::order;
use crate::store::Kind as RecordKind;
use crate::Value;

/// On a further diagram: the scene it belongs to.
pub const OF_SCENE: &str = "of_scene";
/// On a scene: the name he gave its own diagram.
pub const DIAGRAM_NAME: &str = "diagram_name";
/// On a scene: where its own diagram sits among the scene's others.
pub const DIAGRAM_ORDER: &str = "diagram_order";
/// On a scene: left out of the Diagram's scene list, by hand (his ask,
/// 2026-10-17: *"manually hide scenes in the diagram bar"*). A scene fact, so
/// it is the same on the Mac, the iPhone and the portal. It touches nothing
/// else: the shot list, the schedule and the diagrams themselves stay.
pub const DIAGRAM_HIDDEN: &str = "diagram_hidden";

/// One of a scene's diagrams, as the screens list it.
#[derive(Debug, Clone, PartialEq)]
pub struct SceneDiagram {
    /// The owner every diagram command takes: the scene itself for its own.
    pub id: Id,
    /// As he typed it; empty when he has not named it.
    pub name: String,
    /// What a screen or a sheet calls it: the name, else `Diagram N`.
    pub title: String,
    pub count: usize,
}

impl Doc {
    /// Whether he hid this scene from the Diagram's list.
    pub fn scene_diagram_hidden(&self, scene: Id) -> bool {
        self.get(scene).map(|r| r.kind == RecordKind::Scene && !r.is_deleted() && r.bool(DIAGRAM_HIDDEN)).unwrap_or(false)
    }

    /// Hide `scenes` from the Diagram's list, or show them again. One undo
    /// step; answers how many changed. Anything that is not a live scene is
    /// skipped (a diagram's id is taken as its scene's).
    pub fn set_scenes_diagram_hidden(&mut self, scenes: &[Id], hidden: bool) -> usize {
        let mut todo: Vec<Id> = Vec::new();
        for id in scenes {
            let scene = self.diagram_scene(*id);
            let live = self.get(scene).map(|r| r.kind == RecordKind::Scene && !r.is_deleted()).unwrap_or(false);
            if live && self.scene_diagram_hidden(scene) != hidden && !todo.contains(&scene) {
                todo.push(scene);
            }
        }
        if todo.is_empty() {
            return 0;
        }
        let tx = self.begin(if hidden { "Hide from Diagrams" } else { "Show in Diagrams" });
        for scene in &todo {
            self.set(*scene, DIAGRAM_HIDDEN, if hidden { Value::from(true) } else { Value::Null });
        }
        self.end(tx);
        todo.len()
    }

    /// Whether `id` is one of a scene's further diagrams.
    pub fn is_scene_diagram(&self, id: Id) -> bool {
        self.get(id)
            .map(|r| r.kind == RecordKind::Plan && !r.is_deleted() && r.ref_id(OF_SCENE).is_some())
            .unwrap_or(false)
    }

    /// The scene a diagram belongs to: the scene itself, the scene a further
    /// diagram points at, or `id` unchanged for a loose plan.
    pub fn diagram_scene(&self, id: Id) -> Id {
        match self.get(id) {
            Some(r) if r.kind == RecordKind::Plan && !r.is_deleted() => r.ref_id(OF_SCENE).unwrap_or(id),
            _ => id,
        }
    }

    /// The further diagrams of `scene`, not in order.
    fn extra_diagrams(&self, scene: Id) -> Vec<Id> {
        self.store().referring_to(&RecordKind::Plan, OF_SCENE, scene).iter().map(|r| r.id).collect()
    }

    /// Every diagram a scene has, in his order — always at least its own.
    pub fn scene_diagram_ids(&self, scene: Id) -> Vec<Id> {
        let own = self.get(scene).and_then(|r| r.float(DIAGRAM_ORDER)).unwrap_or(f64::NEG_INFINITY);
        let mut all: Vec<(f64, Id)> = vec![(own, scene)];
        for id in self.extra_diagrams(scene) {
            all.push((self.get(id).and_then(|r| r.float(f::ORDER)).unwrap_or(0.0), id));
        }
        all.sort_by(|a, b| order::compare(a.0, b.0).then(if a.1 == scene { std::cmp::Ordering::Less } else if b.1 == scene { std::cmp::Ordering::Greater } else { a.1.cmp(&b.1) }));
        all.into_iter().map(|(_, id)| id).collect()
    }

    /// The name he gave one of a scene's diagrams; empty when unnamed.
    pub fn scene_diagram_name(&self, id: Id) -> String {
        let field = if self.is_scene_diagram(id) { f::LABEL } else { DIAGRAM_NAME };
        self.get(id).and_then(|r| r.text(field)).unwrap_or("").trim().to_string()
    }

    /// Every diagram a scene has, named and counted.
    pub fn scene_diagrams(&self, scene: Id) -> Vec<SceneDiagram> {
        self.scene_diagram_ids(scene)
            .into_iter()
            .enumerate()
            .map(|(i, id)| {
                let name = self.scene_diagram_name(id);
                let title = if name.is_empty() { format!("Diagram {}", i + 1) } else { name.clone() };
                SceneDiagram { id, name, title, count: self.diagram_count(id) }
            })
            .collect()
    }

    /// How many pieces a scene holds across all its diagrams — whether it
    /// has been started.
    pub fn scene_diagram_total(&self, scene: Id) -> usize {
        self.scene_diagram_ids(scene).into_iter().map(|id| self.diagram_count(id)).sum()
    }

    /// A new diagram on `scene`, at the end of its row, named `name` (blank:
    /// unnamed, shown as a placeholder). `from`: one whose pieces it starts
    /// as a copy of — cameras come loose from their shots, as every copy
    /// does. One undo step. `None` when `scene` is not a live scene.
    pub fn add_scene_diagram(&mut self, scene: Id, name: &str, from: Option<Id>) -> Option<Id> {
        self.add_scene_diagram_with(scene, None, name, from)
    }

    /// The same, under an id the caller chose — the portal's page and its
    /// server make the same diagram (`portal.rs`). An id already taken is
    /// answered as made, as `add_plan_with` does.
    pub fn add_scene_diagram_with(&mut self, scene: Id, id: Option<Id>, name: &str, from: Option<Id>) -> Option<Id> {
        if !self.get(scene).map(|r| r.kind == RecordKind::Scene && !r.is_deleted()).unwrap_or(false) {
            return None;
        }
        if let Some(id) = id.filter(|i| self.get(*i).is_some()) {
            return Some(id);
        }
        let tx = self.begin("New Diagram");
        let mut orders: Vec<f64> = self.extra_diagrams(scene).iter().filter_map(|id| self.get(*id).and_then(|r| r.float(f::ORDER))).collect();
        orders.push(self.get(scene).and_then(|r| r.float(DIAGRAM_ORDER)).unwrap_or(0.0));
        let id = match id {
            Some(id) => self.create_as(RecordKind::Plan, id),
            None => self.create_record(RecordKind::Plan),
        };
        self.set(id, OF_SCENE, Value::Ref(scene));
        self.set(id, f::LABEL, name.trim());
        self.set(id, f::ORDER, order::after_last(&orders));
        if let Some(from) = from.filter(|s| self.owns_diagram(*s)) {
            self.diagram_copy(from, &[], &[id], super::copy::Mode::Replace);
        }
        self.end(tx);
        Some(id)
    }

    /// Rename one of a scene's diagrams. A blank name makes it unnamed again.
    pub fn rename_scene_diagram(&mut self, id: Id, name: &str) -> bool {
        let field = if self.is_scene_diagram(id) {
            f::LABEL
        } else if self.get(id).map(|r| r.kind == RecordKind::Scene).unwrap_or(false) {
            DIAGRAM_NAME
        } else {
            return false;
        };
        let tx = self.begin("Rename Diagram");
        self.set(id, field, name.trim());
        self.end(tx);
        true
    }

    /// Move one of a scene's diagrams to `index` in its row. One undo step.
    pub fn move_scene_diagram(&mut self, id: Id, index: usize) -> bool {
        let scene = self.diagram_scene(id);
        let mut ids = self.scene_diagram_ids(scene);
        let Some(at) = ids.iter().position(|x| *x == id) else { return false };
        ids.remove(at);
        ids.insert(index.min(ids.len()), id);
        let tx = self.begin("Move Diagram");
        for (i, x) in ids.iter().enumerate() {
            let field = if *x == scene { DIAGRAM_ORDER } else { f::ORDER };
            self.set(*x, field, i as f64 * order::STEP);
        }
        self.end(tx);
        true
    }

    /// Delete one of a scene's diagrams and everything on it, as one step
    /// Undo brings back. The last one a scene has stays (`false`). The
    /// scene's own, deleted while others remain, takes the next one's
    /// pieces, settings, name and place.
    pub fn delete_scene_diagram(&mut self, id: Id) -> bool {
        let scene = self.diagram_scene(id);
        let ids = self.scene_diagram_ids(scene);
        if ids.len() < 2 || !ids.contains(&id) {
            return false;
        }
        let tx = self.begin("Delete Diagram");
        if id == scene {
            let next = ids.into_iter().find(|x| *x != scene).expect("two or more");
            self.diagram_forget(scene);
            let items: Vec<Id> = self.store().referring_to(&RecordKind::DiagramItem, f::SCENE, next).iter().map(|r| r.id).collect();
            for item in items {
                self.set(item, f::SCENE, Value::Ref(scene));
            }
            let settings = self.get(next).and_then(|r| r.text(f::DIAGRAM)).map(str::to_string);
            self.set(scene, f::DIAGRAM, settings.map(Value::from).unwrap_or(Value::Null));
            let name = self.scene_diagram_name(next);
            self.set(scene, DIAGRAM_NAME, name.as_str());
            let at = self.get(next).and_then(|r| r.float(f::ORDER)).unwrap_or(0.0);
            self.set(scene, DIAGRAM_ORDER, at);
            self.delete(next);
        } else {
            self.diagram_forget(id);
            self.delete(id);
        }
        self.end(tx);
        true
    }

    /// A scene on its way out takes its further diagrams with it.
    pub(crate) fn scene_diagrams_forget(&mut self, scene: Id) {
        for id in self.extra_diagrams(scene) {
            self.diagram_forget(id);
            self.delete(id);
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::doc::Doc;
    use crate::json;
    use crate::stamp::DeviceId;

    fn film() -> (Doc, crate::id::Id) {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Film");
        let s = d.create_scene("5");
        d.clear_history();
        (d, s)
    }

    fn wall_and_camera() -> json::Json {
        json::parse(r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"camera","x":1,"y":1,"new_shot":true}]}"#).unwrap()
    }

    #[test]
    fn an_old_scene_keeps_its_one_diagram_first() {
        let (mut doc, scene) = film();
        doc.diagram_edit(scene, &wall_and_camera()).unwrap();
        let all = doc.scene_diagrams(scene);
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].id, scene);
        assert_eq!(all[0].title, "Diagram 1");
        assert_eq!(all[0].count, 2);
        assert_eq!(doc.scene_diagram_total(scene), 2);
    }

    #[test]
    fn a_second_diagram_is_the_scenes_not_a_loose_plan() {
        let (mut doc, scene) = film();
        let second = doc.add_scene_diagram(scene, "", None).unwrap();
        assert!(doc.plans_in_order().is_empty(), "not listed with the loose plans");
        assert!(doc.is_scene_diagram(second));
        assert!(!doc.is_plan(second));
        assert_eq!(doc.diagram_scene(second), scene);
        let all = doc.scene_diagrams(scene);
        assert_eq!(all.iter().map(|d| d.title.as_str()).collect::<Vec<_>>(), vec!["Diagram 1", "Diagram 2"]);
        assert_eq!(all[1].name, "", "a placeholder, never stored");
        // A camera on it brings a shot of the scene, as on the scene's own.
        doc.diagram_edit(second, &wall_and_camera()).unwrap();
        let cam = doc.diagram(second).els.into_iter().find(|e| e.kind == crate::diagram::Kind::Camera).unwrap();
        assert!(!cam.shot.is_empty(), "the camera stands for a shot");
        assert_eq!(doc.placements_in_scene(scene).len(), 1);
        assert_eq!(doc.scenes_with_diagrams(), vec![scene], "drawn on any of its diagrams counts as started");
        assert_eq!(doc.diagram_context(second).shots.len(), 1);
    }

    #[test]
    fn renamed_duplicated_moved_and_deleted() {
        let (mut doc, scene) = film();
        doc.diagram_edit(scene, &wall_and_camera()).unwrap();
        doc.rename_scene_diagram(scene, "Wide Setup");
        let rev = doc.add_scene_diagram(scene, "Reverse", Some(scene)).unwrap();
        assert_eq!(doc.diagram(rev).els.len(), 2, "duplicate copies every piece");
        let night = doc.add_scene_diagram(scene, "Night Version", None).unwrap();
        let names = |d: &Doc| d.scene_diagrams(scene).into_iter().map(|x| x.title).collect::<Vec<_>>();
        assert_eq!(names(&doc), vec!["Wide Setup", "Reverse", "Night Version"]);
        doc.move_scene_diagram(night, 0);
        assert_eq!(names(&doc), vec!["Night Version", "Wide Setup", "Reverse"]);
        doc.move_scene_diagram(scene, 2);
        assert_eq!(names(&doc), vec!["Night Version", "Reverse", "Wide Setup"]);
        assert!(doc.delete_scene_diagram(night));
        assert_eq!(names(&doc), vec!["Reverse", "Wide Setup"]);
        doc.undo();
        assert_eq!(names(&doc), vec!["Night Version", "Reverse", "Wide Setup"]);
        let _ = rev;
    }

    #[test]
    fn deleting_the_scenes_own_moves_the_next_into_its_place() {
        let (mut doc, scene) = film();
        doc.diagram_edit(scene, &json::parse(r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#).unwrap()).unwrap();
        let rev = doc.add_scene_diagram(scene, "Reverse", None).unwrap();
        doc.diagram_edit(rev, &wall_and_camera()).unwrap();
        let shot = doc.diagram(rev).els.iter().find(|e| e.kind == crate::diagram::Kind::Camera).unwrap().shot.clone();
        assert!(doc.delete_scene_diagram(scene));
        let all = doc.scene_diagrams(scene);
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].id, scene);
        assert_eq!(all[0].title, "Reverse");
        let els = doc.diagram(scene).els;
        assert_eq!(els.len(), 2);
        assert_eq!(els.iter().find(|e| e.kind == crate::diagram::Kind::Camera).unwrap().shot, shot, "the camera keeps its shot");
        assert!(!doc.delete_scene_diagram(scene), "the last one stays");
        doc.undo();
        assert_eq!(doc.scene_diagrams(scene).len(), 2);
        assert_eq!(doc.diagram(scene).els.len(), 1);
        assert_eq!(doc.diagram(rev).els.len(), 2);
    }

    #[test]
    fn a_scene_hidden_from_the_diagram_list_changes_nothing_else() {
        let (mut doc, scene) = film();
        let other = doc.create_scene("6");
        doc.diagram_edit(scene, &wall_and_camera()).unwrap();
        let before = doc.diagram(scene).els.len();
        let shots = doc.placements_in_scene(scene).len();
        assert!(!doc.scene_diagram_hidden(scene));
        assert_eq!(doc.set_scenes_diagram_hidden(&[scene, other], true), 2);
        assert!(doc.scene_diagram_hidden(scene) && doc.scene_diagram_hidden(other));
        assert_eq!(doc.set_scenes_diagram_hidden(&[scene], true), 0, "already hidden");
        assert_eq!(doc.diagram(scene).els.len(), before, "the diagram is as it was");
        assert_eq!(doc.placements_in_scene(scene).len(), shots, "so are the shots");
        assert_eq!(doc.scenes_with_diagrams(), vec![scene], "drawn is still drawn");
        assert_eq!(doc.set_scenes_diagram_hidden(&[scene], false), 1);
        assert!(!doc.scene_diagram_hidden(scene) && doc.scene_diagram_hidden(other));
        doc.undo();
        assert!(doc.scene_diagram_hidden(scene), "Show taken back");
        doc.undo();
        assert!(!doc.scene_diagram_hidden(scene) && !doc.scene_diagram_hidden(other), "Hide taken back in one step");
        // A further diagram's id stands for its scene.
        let rev = doc.add_scene_diagram(scene, "Reverse", None).unwrap();
        assert_eq!(doc.set_scenes_diagram_hidden(&[rev], true), 1);
        assert!(doc.scene_diagram_hidden(scene));
    }

    #[test]
    fn undoing_a_new_diagram_leaves_nothing() {
        let (mut doc, scene) = film();
        doc.add_scene_diagram(scene, "Gone", None);
        doc.undo();
        assert_eq!(doc.scene_diagrams(scene).len(), 1);
        assert!(doc.plans_in_order().is_empty());
    }

    #[test]
    fn a_deleted_scene_takes_its_diagrams() {
        let (mut doc, scene) = film();
        let rev = doc.add_scene_diagram(scene, "Reverse", None).unwrap();
        doc.diagram_edit(rev, &json::parse(r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#).unwrap()).unwrap();
        doc.delete_scene(scene);
        assert_eq!(doc.diagram_count(rev), 0);
        assert!(doc.plans_in_order().is_empty());
        doc.undo();
        assert_eq!(doc.diagram_count(rev), 1);
    }
}
