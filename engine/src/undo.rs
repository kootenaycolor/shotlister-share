//! Undo and redo.
//!
//! Undo does not remove a change. Nothing is ever removed — the log is the
//! record of what happened, and rewriting it would be a lie. Undo **writes a new
//! change that puts the old value back**, which is both honest and the only
//! thing that works once two devices are involved.
//!
//! That has one consequence worth stating plainly: **undo will not quietly
//! revert somebody else's work.** If a field you are undoing has been changed
//! again since — by you elsewhere, or by another device — that field is left
//! alone and reported. Undoing your typo half an hour later must not roll back
//! what the phone did in between.
//!
//! Undo is per-device. You undo what you did, not what arrived.

use crate::doc::Doc;
use crate::id::Id;
use crate::value::Value;

/// One field's worth of an undoable action.
#[derive(Clone, Debug)]
pub struct UndoEntry {
    pub id: Id,
    pub field: String,
    /// What the field held before. `Null` stands for "was not set", which reads
    /// the same to every getter.
    pub before: Value,
    /// What this action set it to. Undo only fires if it is still the value —
    /// otherwise something has happened since and is not ours to revert.
    pub after: Value,
}

/// One user action, however many fields it touched.
#[derive(Clone, Debug)]
pub struct UndoStep {
    pub label: String,
    pub entries: Vec<UndoEntry>,
}

/// What an undo actually did, since it may not be able to do all of it.
#[derive(Clone, Debug, PartialEq)]
pub struct UndoOutcome {
    pub label: String,
    pub restored: usize,
    /// Fields left alone because they had moved on since.
    pub skipped: usize,
}

impl UndoOutcome {
    pub fn complete(&self) -> bool {
        self.skipped == 0
    }
}

impl Doc {
    /// Group everything a closure does into one undoable action.
    ///
    /// Without this, adding a shot would be a dozen separate undos — one per
    /// field — which is not what anybody means by "undo that".
    pub fn transact<R>(&mut self, label: &str, body: impl FnOnce(&mut Doc) -> R) -> R {
        // A transaction inside a transaction joins the outer one rather than
        // starting a second, so a compound helper called from a shell's own
        // grouping stays one action.
        if self.recording.is_some() {
            return body(self);
        }

        self.recording = Some(Vec::new());
        self.recording_label = label.to_string();
        let result = body(self);
        let entries = self.recording.take().unwrap_or_default();

        if !entries.is_empty() {
            self.undo_stack.push(UndoStep {
                label: label.to_string(),
                entries,
            });
            // A new action makes the redo branch unreachable.
            self.redo_stack.clear();
        }
        result
    }

    /// Open a transaction without a closure, for the compound operations inside
    /// the engine — and for the ffi, whose commands own gestures the same way
    /// (`setmany` is one paste, so it must be one step to take back). Returns
    /// whether it actually opened one — a nested call joins the outer
    /// transaction instead, which is what lets a grouped command reuse the
    /// same single-shot methods without splitting the history.
    pub fn begin(&mut self, label: &str) -> bool {
        if self.recording.is_some() {
            return false;
        }
        self.recording = Some(Vec::new());
        self.recording_label = label.to_string();
        true
    }

    pub fn end(&mut self, opened: bool) {
        if !opened {
            return;
        }
        let label = std::mem::take(&mut self.recording_label);
        let entries = self.recording.take().unwrap_or_default();
        if !entries.is_empty() {
            self.undo_stack.push(UndoStep { label, entries });
            self.redo_stack.clear();
        }
    }

    /// Called by `set` and `create`. Outside a transaction, each change becomes
    /// its own single-step action.
    pub(crate) fn record(&mut self, label: &str, entry: UndoEntry) {
        match &mut self.recording {
            Some(entries) => entries.push(entry),
            None => {
                self.undo_stack.push(UndoStep {
                    label: label.to_string(),
                    entries: vec![entry],
                });
                self.redo_stack.clear();
            }
        }
    }

    /// The last action folded into the one before it, so one undo takes
    /// both back — a burst of arrow presses, or an ⌥-drag's copy and its
    /// move. Only the shell knows when two steps were one gesture, so it
    /// asks; the engine just joins. Returns whether there were two to join.
    pub fn join_last_steps(&mut self) -> bool {
        if self.undo_stack.len() < 2 {
            return false;
        }
        let top = self.undo_stack.pop().expect("two steps");
        self.undo_stack.last_mut().expect("one step").entries.extend(top.entries);
        true
    }

    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    /// What the next undo would undo — for the menu item.
    pub fn undo_label(&self) -> Option<&str> {
        self.undo_stack.last().map(|step| step.label.as_str())
    }

    pub fn redo_label(&self) -> Option<&str> {
        self.redo_stack.last().map(|step| step.label.as_str())
    }

    /// How deep the undo history goes.
    pub fn undo_depth(&self) -> usize {
        self.undo_stack.len()
    }

    /// Everything that could be taken back, the next one first — for a menu that
    /// lists the steps rather than only naming the top of the pile.
    ///
    /// This is the *session's* stack, which is not the same thing as the
    /// project's history: you cannot undo what happened last week, but you can
    /// still read it. History is `changes()`, and it outlives this.
    pub fn undo_labels(&self) -> Vec<&str> {
        self.undo_stack
            .iter()
            .rev()
            .map(|step| step.label.as_str())
            .collect()
    }

    pub fn redo_labels(&self) -> Vec<&str> {
        self.redo_stack
            .iter()
            .rev()
            .map(|step| step.label.as_str())
            .collect()
    }

    /// How many fields one step would put back — what lets a menu say "and four
    /// shots move back with it" rather than leaving the scope a surprise.
    pub fn undo_breadth(&self) -> usize {
        self.undo_stack.last().map(|s| s.entries.len()).unwrap_or(0)
    }

    fn current(&self, id: Id, field: &str) -> Value {
        self.store()
            .get_raw(id)
            .and_then(|record| record.get(field).cloned())
            .unwrap_or(Value::Null)
    }

    /// Put back what the last action changed.
    pub fn undo(&mut self) -> Option<UndoOutcome> {
        let step = self.undo_stack.pop()?;
        let mut restored = 0;
        let mut skipped = 0;

        // Backwards, so an action that set the same field twice ends on the
        // value it started with.
        for entry in step.entries.iter().rev() {
            if self.current(entry.id, &entry.field) == entry.after {
                self.write_without_recording(entry.id, &entry.field, entry.before.clone());
                restored += 1;
            } else {
                skipped += 1;
            }
        }

        self.redo_stack.push(step.clone());
        Some(UndoOutcome {
            label: step.label,
            restored,
            skipped,
        })
    }

    /// Do it again.
    pub fn redo(&mut self) -> Option<UndoOutcome> {
        let step = self.redo_stack.pop()?;
        let mut restored = 0;
        let mut skipped = 0;

        for entry in step.entries.iter() {
            if self.current(entry.id, &entry.field) == entry.before {
                self.write_without_recording(entry.id, &entry.field, entry.after.clone());
                restored += 1;
            } else {
                skipped += 1;
            }
        }

        self.undo_stack.push(step.clone());
        Some(UndoOutcome {
            label: step.label,
            restored,
            skipped,
        })
    }

    /// Forget the history without touching the list — for opening a project, or
    /// after a save point.
    pub fn clear_history(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
    }
}
