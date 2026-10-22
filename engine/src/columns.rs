//! Column order and visibility.
//!
//! Both belong to the project rather than to the app, because the order of the
//! columns is also the order of the technical line in Document view — one order,
//! set in one place, so the table and the page cannot disagree about whether
//! lens comes before support.
//!
//! Hidden columns keep their position, so showing one again puts it back where
//! it was rather than at the end.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::store::Kind;
use crate::value::Value;

/// The columns a shot list has, in the order the working sheets use them.
pub const DEFAULT_ORDER: [&str; 15] = [
    "image",
    "title",
    "description",
    // **The stretch of the script this shot quotes** (2026-09-19). Never
    // shown on a film; on a commercial, shown once the film has a script.
    // `hidden_columns` keeps it off a film.
    "script",
    "size",
    "angle",
    "movement",
    "camera",
    "lens",
    // Filters and modifiers have no column: they live under the Lens chip
    // (Lens Stack, always on). His ruling, 2026-10-15: "Filters and Modifiers
    // columns are also not needed anymore." An older file whose saved order
    // names them still opens: `column_order` drops what it does not list.
    "support",
    "notes",
    "tags",
    "day",
    "sequence",
    "struck",
];

/// **What each built-in column is called.** Ref 249.
///
/// These names were written out on the Mac and again on the phone, which meant
/// the same list existed in two places and could disagree with itself — the
/// same shape of problem as the address lookup (Ref 143) and the scan
/// explanation (Ref 181). The engine knows every one of them, so it says them
/// and both shells stop guessing.
///
/// The scene fields at the end have no column of their own but keep lists, and
/// the project's settings screen names them.
pub const BUILT_IN_LABELS: [(&str, &str); 20] = [
    ("image", "Storyboard"),
    ("title", "Title"),
    ("description", "Description"),
    ("script", "Script"),
    ("size", "Shot Size"),
    ("angle", "Shot Angle"),
    ("movement", "Movement"),
    // **"Camera", not "Camera Gear"** — his correction, 2026-08-23, and the
    // name is the whole of what went wrong here. *Camera Gear* reads as gear,
    // which is what the column below it holds, so the two looked like one
    // thing with two names and were briefly merged into one. They are not:
    // this is **which body shot it**, for a multicam day or a second camera on
    // set, and Equipment is what the camera is sitting on.
    ("camera", "Camera"),
    ("lens", "Lens"),
    ("modifiers", "Modifiers"),
    ("lens_filters", "Filters"),
    // **"Equipment", not "Support"** — his word, 2026-08-22, and the one the
    // list under it is in: Handheld, Sticks, Dana Dolly, Jib. The field keeps
    // its own name (`support`) because renaming a field renames it in every
    // project file ever written; only what it is *called* changes.
    ("support", "Equipment"),
    ("notes", "Notes"),
    ("tags", "Tags"),
    ("day", "Shoot Day"),
    ("sequence", "Sequence"),
    // **Shot, not Cut** — his ruling 2026-09-16: a crossed-out shot is one
    // we got, which is what `strike` has always meant in `doc.rs`.
    ("struck", "Shot"),
    ("pov", "POV"),
    ("priority", "Priority"),
    ("time_of_day", "Time of day"),
];

/// What to call a field — a project's own label when it has one, the built-in
/// name otherwise, and the slug itself when it is neither.
pub fn label_for(field: &str) -> &str {
    BUILT_IN_LABELS
        .iter()
        .find(|(name, _)| *name == field)
        .map(|(_, label)| *label)
        .unwrap_or(field)
}

/// The ones that make up the technical line under a shot in Document view.
pub const TECHNICAL: [&str; 8] =
    ["size", "angle", "movement", "camera", "lens", "modifiers", "lens_filters", "support"];

/// Hidden by default — present, but more than most lists need on screen.
///
/// **Camera is here because it is optional, not because it is minor** — his
/// word, 2026-08-23. It earns its place on a multicam day, or when there is a
/// second body on set, and on every other film it is a column of one repeated
/// answer. Hidden means present and one click away, which is what optional
/// has to mean when a column's values still belong to the project.
/// Present, but more than most lists need on screen.
///
/// The title is *not* in here. A shot has a short name and a sentence
/// describing it — "ChatGPT Screen" against "ECU insert on the ChatGPT screen"
/// — and the working sheets carry both. Hiding one of them by default meant the
/// app quietly had nowhere to put half of what somebody writes.
const HIDDEN_BY_DEFAULT: [&str; 3] = ["camera", "sequence", "struck"];

const F_ORDER: &str = "column_order";
const F_HIDDEN: &str = "columns_hidden";
/// **Lens Stack** — filters and modifiers are always drawn under the lens, in
/// the Lens column. Nothing is hidden in `columns_hidden` and no shot changes;
/// the two columns simply never appear on their own. (Files written while this
/// was a per-project setting may still carry a `lens_stack` field; it is ignored.)
/// The two columns the stack takes into the Lens column.
pub const STACKED_INTO_LENS: [&str; 2] = ["modifiers", "lens_filters"];

fn list(values: &[String]) -> Value {
    Value::List(values.iter().map(|v| Value::text(v)).collect())
}

impl Doc {
    fn project_list(&self, field: &str) -> Option<Vec<String>> {
        let project = self.project_id()?;
        let value = self.get(project)?.get(field)?;
        value.as_list().map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_text().map(|s| s.to_string()))
                .collect()
        })
    }

    /// Every column, in order. Anything the project has not said about keeps its
    /// default place, so a build that adds a column does not lose it.
    pub fn column_order(&self) -> Vec<String> {
        let custom: Vec<String> = self.custom_columns().into_iter().map(|c| c.field).collect();
        let stored = self.project_list(F_ORDER).unwrap_or_default();
        let mut order: Vec<String> = stored
            .into_iter()
            .filter(|name| {
                DEFAULT_ORDER.contains(&name.as_str()) || custom.iter().any(|c| c == name)
            })
            .collect();
        // A column this project has never heard of — because a later build
        // added it — goes in at *its own* default position rather than on the
        // end. Appending would put a title column after the strike mark, which
        // is not where anybody would look for it, and the person would have to
        // drag it back on every project they own.
        for (at, name) in DEFAULT_ORDER.iter().enumerate() {
            if order.iter().any(|kept| kept == name) {
                continue;
            }
            let insert_at = order.len().min(at);
            order.insert(insert_at, name.to_string());
        }
        // A custom column the stored order has never heard of goes on the end —
        // it has no default place; where it was made is the only place it has.
        for field in custom {
            if !order.iter().any(|kept| *kept == field) {
                order.push(field);
            }
        }
        order
    }

    pub fn set_column_order(&mut self, order: &[&str]) {
        let project = match self.project_id() {
            Some(id) => id,
            None => return,
        };
        let custom: Vec<String> = self.custom_columns().into_iter().map(|c| c.field).collect();
        let kept: Vec<String> = order
            .iter()
            .filter(|name| {
                DEFAULT_ORDER.contains(name) || custom.iter().any(|c| c == *name)
            })
            .map(|name| name.to_string())
            .collect();
        self.set(project, F_ORDER, list(&kept));
    }

    pub fn hidden_columns(&self) -> Vec<String> {
        let mut hidden = self
            .project_list(F_HIDDEN)
            .unwrap_or_else(|| HIDDEN_BY_DEFAULT.iter().map(|s| s.to_string()).collect());
        // A film has no script of this kind, so it never shows the Script
        // column — whatever its list says; a commercial shows it once it
        // has a script (his ask, 2026-09-19: no empty column).
        let film = self.kind() == crate::kind::Kind::Film;
        if (film || self.av_scripts().is_empty()) && !hidden.iter().any(|h| h == "script") {
            hidden.push("script".to_string());
        }
        hidden
    }

    pub fn is_column_visible(&self, name: &str) -> bool {
        if STACKED_INTO_LENS.contains(&name) {
            return false;
        }
        !self.hidden_columns().iter().any(|hidden| hidden == name)
    }

    /// Filters and modifiers always sit inside the Lens column.
    pub fn lens_stacked(&self) -> bool {
        true
    }

    /// Hiding a column does not move it. Showing it again puts it back where it
    /// was rather than at the end.
    pub fn set_column_visible(&mut self, name: &str, visible: bool) {
        let project = match self.project_id() {
            Some(id) => id,
            None => return,
        };
        let mut hidden = self.hidden_columns();
        let present = hidden.iter().any(|existing| existing == name);
        match (visible, present) {
            (true, true) => hidden.retain(|existing| existing != name),
            (false, false) => hidden.push(name.to_string()),
            _ => return,
        }
        self.set(project, F_HIDDEN, list(&hidden));
    }

    /// The columns on screen, in order — which is also what a share page
    /// carries, and the order the technical line reads in.
    pub fn visible_columns(&self) -> Vec<String> {
        let hidden = self.hidden_columns();
        self.column_order()
            .into_iter()
            .filter(|name| !hidden.iter().any(|h| h == name))
            .filter(|name| !STACKED_INTO_LENS.contains(&name.as_str()))
            .collect()
    }

    /// The technical fields that are on screen, in column order.
    pub fn technical_columns(&self) -> Vec<String> {
        self.visible_columns()
            .into_iter()
            .filter(|name| TECHNICAL.contains(&name.as_str()))
            .collect()
    }
}

/// The shapes a custom column's values can take. Media and location are in the
/// schema from birth so a file made today opens correctly in the build that
/// learns to draw them — the table shows their text until then.
pub const COLUMN_KINDS: [&str; 6] = ["text", "single", "multi", "check", "media", "location"];

/// One column the project made for itself.
pub struct CustomColumn {
    pub id: Id,
    /// The slug shot records store values under — `c_` plus the record's own
    /// id, so renaming the label never orphans the values.
    pub field: String,
    pub label: String,
    pub kind: String,
}

impl Doc {
    /// A new column, appended to the order so it appears where it was made.
    /// The kind must be one this build knows; an unknown kind is refused
    /// rather than stored, because a column whose shape nothing understands
    /// is a cell that eats what is typed into it.
    pub fn add_column(&mut self, label: &str, kind: &str) -> Option<Id> {
        let label = label.trim();
        if label.is_empty() || !COLUMN_KINDS.contains(&kind) {
            return None;
        }
        let tx = self.begin("Add column");
        let id = self.create(Kind::Column);
        let field = format!("c_{id}");
        self.set(id, f::LABEL, Value::text(label));
        self.set(id, f::FIELD, Value::text(&field));
        self.set(id, f::COLUMN_KIND, Value::text(kind));
        // `column_order()` already appends a custom field the stored order has
        // never heard of, and the record exists as of the lines above — so the
        // order is read, not pushed to, or the new field would be in it twice.
        let order = self.column_order();
        let refs: Vec<&str> = order.iter().map(|s| s.as_str()).collect();
        self.set_column_order(&refs);
        self.end(tx);
        Some(id)
    }

    /// Every custom column that exists. An undone creation survives as an
    /// empty husk — undo is field-level — and a column with no name is
    /// nothing to draw, so husks stay out, the same answer as units.
    pub fn custom_columns(&self) -> Vec<CustomColumn> {
        self.store()
            .of_kind(&Kind::Column)
            .iter()
            .filter_map(|r| {
                let label = r.get(f::LABEL)?.as_text()?.to_string();
                if label.is_empty() {
                    return None;
                }
                let field = r.get(f::FIELD)?.as_text()?.to_string();
                let kind = r
                    .get(f::COLUMN_KIND)
                    .and_then(|v| v.as_text())
                    .unwrap_or("text")
                    .to_string();
                Some(CustomColumn { id: r.id, field, label, kind })
            })
            .collect()
    }

    /// What shape a field's values are, when the field is a custom column.
    pub fn custom_column_kind(&self, field: &str) -> Option<String> {
        self.custom_columns()
            .into_iter()
            .find(|c| c.field == field)
            .map(|c| c.kind)
    }

    /// **How many shots have anything in this column.** What a delete would
    /// take with it, counted before it is offered — his note on the row: *"needs
    /// to say what it takes with it first."*
    pub fn shots_with_value(&self, field: &str) -> usize {
        self.store()
            .of_kind(&Kind::Shot)
            .iter()
            .filter(|r| match r.get(field) {
                Some(Value::Text(s)) => !s.trim().is_empty(),
                Some(Value::List(items)) => !items.is_empty(),
                Some(Value::Null) | None => false,
                Some(_) => true,
            })
            .count()
    }

    /// **Take a column away, and everything written in it.**
    ///
    /// Only a column the project made: the built-in ones are the app's shape
    /// and a project cannot delete its own Shot Size. Refused rather than
    /// half-done, so nothing is cleared for a field that then stays on screen.
    ///
    /// One transaction, so it is one ⌘Z — and the undo puts the values back as
    /// well as the column, because they go in the same breath.
    pub fn delete_column(&mut self, field: &str) -> bool {
        let Some(column) = self.custom_columns().into_iter().find(|c| c.field == field)
        else {
            return false;
        };
        let tx = self.begin("Delete column");
        let shots: Vec<Id> = self
            .store()
            .of_kind(&Kind::Shot)
            .iter()
            .filter(|r| r.get(field).is_some())
            .map(|r| r.id)
            .collect();
        for shot in shots {
            self.set(shot, field, Value::Null);
        }
        // The order is rewritten without it, or the column comes back as a
        // header with nothing behind it.
        let order: Vec<String> = self
            .column_order()
            .into_iter()
            .filter(|name| name != field)
            .collect();
        let refs: Vec<&str> = order.iter().map(|s| s.as_str()).collect();
        self.set_column_order(&refs);
        // The record itself goes last: `custom_columns` reads it, and the
        // order rewrite above needs it gone from nothing but the list.
        self.delete(column.id);
        self.end(tx);
        true
    }

    /// The name this film gave a built-in column, if it gave one.
    pub fn column_label_override(&self, field: &str) -> Option<String> {
        let id = self.project_id()?;
        let text = self
            .store()
            .get(id)?
            .get(&format!("column_label_{field}"))?
            .as_text()?
            .to_string();
        (!text.is_empty()).then_some(text)
    }

    /// A new name on the same column. The values stay where they are: the
    /// field slug is the identity, and the label is only what the header says.
    pub fn rename_column(&mut self, field: &str, label: &str) {
        let label = label.trim();
        if label.is_empty() {
            return;
        }
        let id = match self.custom_columns().into_iter().find(|c| c.field == field) {
            Some(c) => c.id,
            None => {
                // A built-in column keeps its field name; only what it is
                // called is stored, on the project, so every device agrees.
                // Naming it back to its own word clears the override.
                if !BUILT_IN_LABELS.iter().any(|(name, _)| *name == field) {
                    return;
                }
                let Some(project) = self.project_id() else { return };
                let tx = self.begin("Rename column");
                let stored = if label == label_for(field) { "" } else { label };
                self.set(project, &format!("column_label_{field}"), Value::text(stored));
                self.end(tx);
                return;
            }
        };
        let tx = self.begin("Rename column");
        self.set(id, f::LABEL, Value::text(label));
        self.end(tx);
    }
}

// ---- putting the two gear columns back ---------------------------------

/// The mark left by the merge that briefly made these one column. Kept only so
/// the merge can be undone on a film that already had it done.
const GEAR_MERGED: &str = "gear_columns_merged";

/// **What a shot's Equipment should say once a camera's name is taken back
/// out of it.** `None` when there is nothing to take out.
///
/// The exact inverse of what the merge wrote, and only that: the name on its
/// own, or the name after a comma at the end. Anything else is left alone,
/// because anything else is something a person typed.
fn unfolded_gear(held: &str, camera: &str) -> Option<String> {
    let camera = camera.trim();
    if camera.is_empty() {
        return None;
    }
    let held = held.trim();
    if held.eq_ignore_ascii_case(camera) {
        return Some(String::new());
    }
    let (rest, last) = held.rsplit_once(',')?;
    if last.trim().eq_ignore_ascii_case(camera) {
        Some(rest.trim_end().to_string())
    } else {
        None
    }
}

impl Doc {
    /// **Camera and Equipment are two columns again.** Ref 326, and this is the
    /// undo of what that row asked for eight hours earlier.
    ///
    /// The merge was built on a description of these two that was wrong, and
    /// the wrong description was mine: *Camera Gear* reads as gear, Equipment
    /// **is** gear, so they looked like one thing wearing two names. They are
    /// not. **Camera is which body shot it** — a multicam day, or a second
    /// body on set — and **Equipment is what the camera is sitting on**:
    /// handheld, sticks, a Dana Dolly. His correction, 2026-08-23.
    ///
    /// So this walks it back on any film the merge reached. A camera's name
    /// that was written into an Equipment cell is taken out of it, and only in
    /// the exact shape the merge wrote it — the name alone, or the name after
    /// a comma at the end. A cell that says anything else is somebody's
    /// typing and is left exactly as it is.
    ///
    /// **Nothing was ever lost either way**, which is the one comfort here:
    /// the merge never deleted a camera, it only stopped drawing the column,
    /// so putting the column back puts every camera back with it.
    ///
    /// Returns true if anything changed, so a caller knows whether to save.
    pub fn unmerge_gear_columns(&mut self) -> bool {
        let Some(project) = self.project_id() else {
            return false;
        };
        let merged = self
            .store()
            .get(project)
            .and_then(|r| r.get(GEAR_MERGED).cloned())
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if !merged {
            return false;
        }

        // Worked out in full before anything is written.
        let mut unfolded: Vec<(Id, String)> = Vec::new();
        for shot in self.store().of_kind(&Kind::Shot) {
            let Some(unit) = shot.ref_id(f::UNIT) else {
                continue;
            };
            let Some(camera) = self.store().get(unit).and_then(|u| u.text(f::LABEL)) else {
                continue;
            };
            let held = shot.get(f::SUPPORT).and_then(|v| v.as_text()).unwrap_or("");
            if let Some(value) = unfolded_gear(held, camera) {
                unfolded.push((shot.id, value));
            }
        }

        let names: Vec<String> = self
            .store()
            .of_kind(&Kind::Unit)
            .iter()
            .filter_map(|u| u.text(f::LABEL))
            .map(|label| label.trim().to_string())
            .filter(|label| !label.is_empty())
            .collect();

        for (shot, value) in unfolded {
            if value.is_empty() {
                self.set(shot, f::SUPPORT, Value::Null);
            } else {
                self.set(shot, f::SUPPORT, Value::text(&value));
            }
        }

        // And the Equipment list stops offering camera bodies. Only the ones
        // that are a camera's name — a term he happens to have typed that
        // matches one is his, not ours, and there is no way to tell them
        // apart, so the tie goes to leaving it.
        let list: Vec<String> = self
            .vocabulary(crate::vocab::SUPPORT)
            .into_iter()
            .filter(|term| !names.iter().any(|name| name.eq_ignore_ascii_case(term)))
            .collect();
        let borrowed: Vec<&str> = list.iter().map(|s| s.as_str()).collect();
        self.set_vocabulary(crate::vocab::SUPPORT, &borrowed);

        self.set(project, GEAR_MERGED, Value::Bool(false));
        true
    }
}
