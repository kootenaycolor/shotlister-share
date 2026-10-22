//! **Loose plans** — a diagram that belongs to no scene (his ruling,
//! 2026-10-01: *"loose plans (which you can import any 3d scan into)"*). A
//! recce sketch, a plan drawn before there is a script, a lighting setup used
//! again and again.
//!
//! A plan is a record of its own (`Kind::Plan`) with a name and a place in
//! the list, and **its pieces are kept exactly as a scene's are**: each
//! `DiagramItem` points at its owner through `f::SCENE`, and the plan's
//! settings sit in its own `f::DIAGRAM`. So everything that reads or edits a
//! diagram — `diagram`, `diagram_edit`, copying, laying a scanned room,
//! pictures, favorites — takes a plan's id as readily as a scene's, and
//! nothing about a scene's plan had to change. What a plan has not got: shots
//! (a camera on it stands for none), a location or a shoot day (no sun
//! position of its own), and characters of its own (the cast tool offers the
//! film's).

use crate::diagram::copy;
use crate::doc::{f, Doc};
use crate::id::Id;
use crate::order;
use crate::store::Kind as RecordKind;

impl Doc {
    /// Whether `id` is a loose plan.
    pub fn is_plan(&self, id: Id) -> bool {
        self.get(id).map(|r| r.kind == RecordKind::Plan && !r.is_deleted() && r.ref_id(super::scenediagrams::OF_SCENE).is_none()).unwrap_or(false)
    }

    /// Whether `id` owns a diagram: a live scene or a loose plan.
    pub fn owns_diagram(&self, id: Id) -> bool {
        self.get(id).map(|r| !r.is_deleted() && matches!(r.kind, RecordKind::Scene | RecordKind::Plan)).unwrap_or(false)
    }

    /// Every loose plan, in the order they were made. A nameless one is the
    /// husk Undo leaves of a plan taken back (undo here is field-level, as
    /// `boards_in_order` says), and is skipped.
    pub fn plans_in_order(&self) -> Vec<Id> {
        let mut all: Vec<_> = self
            .store()
            .of_kind(&RecordKind::Plan)
            .into_iter()
            // A scene's further diagrams (`scenediagrams`) are the scene's, not loose.
            .filter(|r| !r.is_deleted() && !r.text(f::LABEL).unwrap_or_default().is_empty() && r.ref_id(super::scenediagrams::OF_SCENE).is_none())
            .collect();
        all.sort_by(|a, b| order::compare(a.float(f::ORDER).unwrap_or(0.0), b.float(f::ORDER).unwrap_or(0.0)).then(a.id.cmp(&b.id)));
        all.into_iter().map(|r| r.id).collect()
    }

    pub fn plan_name(&self, plan: Id) -> String {
        self.get(plan).and_then(|r| r.text(f::LABEL).map(str::to_string)).unwrap_or_default()
    }

    /// A loose plan by name, ignoring case.
    pub fn plan_named(&self, name: &str) -> Option<Id> {
        let name = name.trim();
        self.plans_in_order().into_iter().find(|p| self.plan_name(*p).eq_ignore_ascii_case(name))
    }

    /// A new loose plan, at the end of the list. A blank name becomes
    /// `Plan 1`, `Plan 2`… — never empty, since an empty one reads as gone.
    /// `from`: a scene or plan whose diagram it starts as a copy of. One
    /// undo step.
    pub fn add_plan(&mut self, name: &str, from: Option<Id>) -> Id {
        self.add_plan_with(None, name, from)
    }

    /// `add_plan` under an id given — the portal's page names its new plan
    /// so the server, making it again, makes the same one. A plan already
    /// there under that id is left as it is.
    pub fn add_plan_with(&mut self, id: Option<Id>, name: &str, from: Option<Id>) -> Id {
        if let Some(id) = id.filter(|i| self.get(*i).is_some()) {
            return id;
        }
        let tx = self.begin("Add Plan");
        let existing: Vec<f64> = self.store().of_kind(&RecordKind::Plan).iter().filter_map(|r| r.float(f::ORDER)).collect();
        let name = match name.trim() {
            "" => {
                let mut n = 1;
                while self.plan_named(&format!("Plan {n}")).is_some() {
                    n += 1;
                }
                format!("Plan {n}")
            }
            given => given.to_string(),
        };
        let id = match id {
            Some(id) => self.create_as(RecordKind::Plan, id),
            None => self.create_record(RecordKind::Plan),
        };
        self.set(id, f::LABEL, name.as_str());
        self.set(id, f::ORDER, order::after_last(&existing));
        if let Some(from) = from.filter(|s| self.owns_diagram(*s)) {
            self.diagram_copy(from, &[], &[id], copy::Mode::Replace);
        }
        self.end(tx);
        id
    }

    pub fn rename_plan(&mut self, plan: Id, name: &str) {
        let name = name.trim();
        if name.is_empty() || !self.is_plan(plan) {
            return;
        }
        let tx = self.begin("Rename Plan");
        self.set(plan, f::LABEL, name);
        self.end(tx);
    }

    /// A plan and everything on it, as one step Undo brings back. Asked of
    /// him first, always: deleting is his decision.
    pub fn delete_plan(&mut self, plan: Id) {
        if !self.is_plan(plan) {
            return;
        }
        let tx = self.begin("Delete Plan");
        self.diagram_forget(plan);
        self.delete(plan);
        self.end(tx);
    }
}

#[cfg(test)]
mod tests {
    use crate::diagram::copy::Mode;
    use crate::doc::Doc;
    use crate::json;
    use crate::stamp::DeviceId;

    fn film() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Film");
        d.clear_history();
        d
    }

    fn wall() -> crate::json::Json {
        json::parse(r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"camera","x":1,"y":1,"new_shot":true}]}"#).unwrap()
    }

    #[test]
    fn a_plan_holds_a_diagram_of_its_own() {
        let mut doc = film();
        let plan = doc.add_plan("", None);
        assert_eq!(doc.plan_name(plan), "Plan 1");
        let second = doc.add_plan(" ", None);
        assert_eq!(doc.plan_name(second), "Plan 2");
        doc.diagram_edit(plan, &wall()).unwrap();
        let d = doc.diagram(plan);
        assert_eq!(d.els.len(), 2);
        // No scene, so no shot: the camera stands for nothing.
        assert!(d.els.iter().all(|e| e.shot.is_empty()));
        assert!(doc.scenes_with_diagrams().is_empty(), "a plan is not a scene");
        assert_eq!(doc.diagram_counts().get(&plan), Some(&2));
    }

    #[test]
    fn plans_and_scenes_copy_both_ways() {
        let mut doc = film();
        let scene = doc.create_scene("1");
        doc.diagram_edit(scene, &wall()).unwrap();
        let plan = doc.add_plan("Kitchen", Some(scene));
        assert_eq!(doc.diagram(plan).els.len(), 2);
        assert!(doc.diagram(plan).els.iter().all(|e| e.shot.is_empty()));
        let other = doc.create_scene("2");
        assert_eq!(doc.diagram_copy(plan, &[], &[other], Mode::Add).len(), 2);
        assert_eq!(doc.diagram(other).els.len(), 2);
    }

    #[test]
    fn renamed_deleted_and_brought_back() {
        let mut doc = film();
        let plan = doc.add_plan("Recce", None);
        doc.diagram_edit(plan, &wall()).unwrap();
        doc.rename_plan(plan, "Warehouse");
        assert_eq!(doc.plan_named("warehouse"), Some(plan));
        doc.rename_plan(plan, "  ");
        assert_eq!(doc.plan_name(plan), "Warehouse", "a blank name is refused");
        doc.delete_plan(plan);
        assert!(doc.plans_in_order().is_empty());
        assert_eq!(doc.diagram_count(plan), 0);
        doc.undo();
        assert_eq!(doc.plans_in_order(), vec![plan]);
        assert_eq!(doc.diagram(plan).els.len(), 2);
    }

    #[test]
    fn undoing_a_new_plan_leaves_no_row() {
        let mut doc = film();
        doc.add_plan("Gone", None);
        doc.undo();
        assert!(doc.plans_in_order().is_empty());
    }
}
