//! **Edit Reference, the first mod** (2026-10-17; his plan of 2026-10-15,
//! mockup option A, the gold bracket).
//!
//! An edit reference is a clip, a run of stills or an animatic showing how
//! several shots cut together. It joins a run of shots, says where each one
//! starts in the clip, and plays from the shot list, the phone and the portal.
//!
//! **A record of its own** (`Kind::EditRef`), the way a setup joins shots: a
//! name, the shots in cut order (`edit_shots`), each one's start in seconds
//! (`edit_starts`, the same length; empty means evenly shared), and a pasted
//! link (`edit_link`) when the cut lives somewhere else. The clip and stills
//! are `Kind::Media` through `Kind::MediaRef`, exactly as a board's pictures
//! are, so they sync, keep and go to Drive by the machinery already there.
//!
//! **Whether it shows is the project's** — the record's `mods` fact, which the
//! shells read off the card. The engine keeps and answers the data either way;
//! a project that never made one answers nothing new at all.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::media::MediaKind;
use crate::order;
use crate::store::Kind;
use crate::value::Value;

/// The shots, in cut order.
pub const EDIT_SHOTS: &str = "edit_shots";
/// Where each shot starts in the clip, in seconds, one per shot.
pub const EDIT_STARTS: &str = "edit_starts";
/// A link to the cut, when it lives somewhere else (Vimeo, Frame.io…).
pub const EDIT_LINK: &str = "edit_link";

/// One edit reference, read.
#[derive(Clone, Debug, PartialEq)]
pub struct EditRef {
    pub id: Id,
    pub name: String,
    pub link: String,
    pub shots: Vec<Id>,
    /// One per shot: where it starts in the clip, seconds. Evenly shared over
    /// the clip's length when none were set.
    pub starts: Vec<f64>,
    /// The clip's or the stills' total length in seconds, nought when unknown.
    pub length: f64,
    /// Every picture and clip on it, in order (`MediaRef` ids).
    pub media: Vec<Id>,
}

impl Doc {
    /// **Make an edit reference** joining these shots, in this order.
    pub fn create_edit_ref(&mut self, name: &str, shots: &[Id]) -> Id {
        let tx = self.begin("Add Edit Reference");
        let existing: Vec<f64> = self
            .store()
            .of_kind(&Kind::EditRef)
            .iter()
            .filter_map(|r| r.float(f::ORDER))
            .collect();
        let id = self.create(Kind::EditRef);
        let name = name.trim();
        self.set(id, f::LABEL, if name.is_empty() { "Edit Reference" } else { name });
        self.set(id, f::ORDER, order::after_last(&existing));
        self.write_edit_shots(id, shots);
        self.end(tx);
        id
    }

    fn write_edit_shots(&mut self, id: Id, shots: &[Id]) {
        let mut seen = Vec::new();
        for s in shots {
            if !seen.contains(s) && self.get(*s).map(|r| r.kind == Kind::Shot) == Some(true) {
                seen.push(*s);
            }
        }
        self.set(id, EDIT_SHOTS, Value::List(seen.iter().map(|s| Value::Ref(*s)).collect()));
    }

    /// Every edit reference, in the order they were made. Nameless husks (an
    /// undone Add) are skipped, as boards' are.
    pub fn edit_refs_in_order(&self) -> Vec<Id> {
        let mut all: Vec<_> = self
            .store()
            .of_kind(&Kind::EditRef)
            .into_iter()
            .filter(|r| !r.text(f::LABEL).unwrap_or_default().is_empty())
            .collect();
        all.sort_by(|a, b| {
            a.float(f::ORDER)
                .unwrap_or(0.0)
                .partial_cmp(&b.float(f::ORDER).unwrap_or(0.0))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        all.into_iter().map(|r| r.id).collect()
    }

    pub fn is_edit_ref(&self, id: Id) -> bool {
        self.get(id).map(|r| r.kind == Kind::EditRef) == Some(true)
    }

    /// The shots it joins, in cut order — only shots that still exist.
    pub fn edit_ref_shots(&self, id: Id) -> Vec<Id> {
        let Some(list) = self.get(id).and_then(|r| r.get(EDIT_SHOTS)).and_then(|v| v.as_list()) else {
            return Vec::new();
        };
        list.iter()
            .filter_map(|v| v.as_ref_id())
            .filter(|s| self.get(*s).map(|r| r.kind == Kind::Shot) == Some(true))
            .collect()
    }

    /// The clip's (or the stills') length: the first clip's duration, else
    /// two seconds a still, else nought.
    fn edit_ref_length(&self, id: Id) -> f64 {
        let mut stills = 0.0;
        for mref in self.media_refs(id) {
            let Some(media) = self.get(mref).and_then(|r| r.ref_id(f::MEDIA)) else { continue };
            match self.media_kind(media) {
                Some(MediaKind::Video) | Some(MediaKind::Gif) => {
                    let secs = self.get(media).and_then(|r| r.float(f::DURATION)).unwrap_or(0.0);
                    if secs > 0.0 {
                        return secs;
                    }
                }
                Some(MediaKind::Image) => stills += 2.0,
                _ => {}
            }
        }
        stills
    }

    /// Read one, whole.
    pub fn edit_ref(&self, id: Id) -> Option<EditRef> {
        let r = self.get(id)?;
        if r.kind != Kind::EditRef {
            return None;
        }
        let shots = self.edit_ref_shots(id);
        let length = self.edit_ref_length(id);
        let said: Vec<f64> = r
            .get(EDIT_STARTS)
            .and_then(|v| v.as_list())
            .map(|l| l.iter().filter_map(|v| v.as_float()).collect())
            .unwrap_or_default();
        let starts = if said.len() == shots.len() && !said.is_empty() {
            said
        } else {
            let n = shots.len().max(1) as f64;
            (0..shots.len()).map(|i| length * i as f64 / n).collect()
        };
        Some(EditRef {
            id,
            name: r.text(f::LABEL).unwrap_or_default().to_string(),
            link: r.text(EDIT_LINK).unwrap_or_default().to_string(),
            shots,
            starts,
            length,
            media: self.media_refs(id),
        })
    }

    /// Every edit reference a shot is in.
    pub fn edit_refs_of_shot(&self, shot: Id) -> Vec<Id> {
        self.edit_refs_in_order()
            .into_iter()
            .filter(|e| self.edit_ref_shots(*e).contains(&shot))
            .collect()
    }

    pub fn rename_edit_ref(&mut self, id: Id, name: &str) {
        let name = name.trim();
        if name.is_empty() || !self.is_edit_ref(id) {
            return;
        }
        let tx = self.begin("Rename Edit Reference");
        self.set(id, f::LABEL, name);
        self.end(tx);
    }

    /// **The shots it joins**, in cut order. Starts set by hand are kept only
    /// while the shots stay the same; a different run starts evenly again.
    pub fn set_edit_ref_shots(&mut self, id: Id, shots: &[Id]) {
        if !self.is_edit_ref(id) {
            return;
        }
        let tx = self.begin("Edit Reference Shots");
        let before = self.edit_ref_shots(id);
        self.write_edit_shots(id, shots);
        if self.edit_ref_shots(id) != before {
            self.set(id, EDIT_STARTS, Value::List(Vec::new()));
        }
        self.end(tx);
    }

    /// **Where each shot starts in the clip**, seconds, one per shot, never
    /// going backwards. Anything else is refused (false).
    pub fn set_edit_ref_starts(&mut self, id: Id, starts: &[f64]) -> bool {
        let shots = self.edit_ref_shots(id);
        if shots.is_empty() || starts.len() != shots.len() {
            return false;
        }
        if starts.iter().any(|s| !s.is_finite() || *s < 0.0) || starts.windows(2).any(|w| w[1] < w[0]) {
            return false;
        }
        let tx = self.begin("Edit Reference Timing");
        self.set(id, EDIT_STARTS, Value::List(starts.iter().map(|s| Value::Float(*s)).collect()));
        self.end(tx);
        true
    }

    pub fn set_edit_ref_link(&mut self, id: Id, link: &str) {
        if !self.is_edit_ref(id) {
            return;
        }
        let tx = self.begin("Edit Reference Link");
        self.set(id, EDIT_LINK, link.trim());
        self.end(tx);
    }

    /// **Delete it.** The shots are untouched; its clip and stills go the way
    /// a board's pictures do (`release_media_uses`).
    pub fn delete_edit_ref(&mut self, id: Id) {
        if !self.is_edit_ref(id) {
            return;
        }
        let tx = self.begin("Delete Edit Reference");
        self.release_media_uses(id);
        self.delete(id);
        self.end(tx);
    }

    /// **The brackets in one run of rows** (socket A, the shot list's margin):
    /// for each edit reference, every stretch of consecutive rows whose shots
    /// it joins, as `(edit ref, first row, last row)`. `shots` are the rows'
    /// shots in the order drawn. Drawn the same by Studio, the phone and the
    /// portal because all three ask here.
    pub fn edit_spans(&self, shots: &[Id]) -> Vec<(Id, usize, usize)> {
        let mut out = Vec::new();
        for e in self.edit_refs_in_order() {
            let joined = self.edit_ref_shots(e);
            if joined.is_empty() {
                continue;
            }
            let mut start: Option<usize> = None;
            for (i, s) in shots.iter().enumerate() {
                if joined.contains(s) {
                    start.get_or_insert(i);
                } else if let Some(a) = start.take() {
                    out.push((e, a, i - 1));
                }
            }
            if let Some(a) = start {
                out.push((e, a, shots.len() - 1));
            }
        }
        out
    }

    /// **The brackets across the whole list** (his note, 2026-10-17: "i want
    /// all the shots that are selected to be connected … right now the scene
    /// heading splits"). `groups` are each group's rows' shots, in the order
    /// drawn. For each group: its spans, each saying whether it carries on
    /// from the group above (`before`) and into the group below (`after`) —
    /// the last row above and the first row here both joined, across the
    /// heading — and, for a group with no rows lying inside such a run, the
    /// edit references passing straight through it.
    pub fn edit_spans_across(&self, groups: &[Vec<Id>]) -> Vec<GroupEditSpans> {
        let refs: Vec<(Id, Vec<Id>)> = self
            .edit_refs_in_order()
            .into_iter()
            .map(|e| (e, self.edit_ref_shots(e)))
            .filter(|(_, s)| !s.is_empty())
            .collect();
        let joins = |e: Id, shot: Option<Id>| -> bool {
            shot.map_or(false, |s| refs.iter().any(|(r, shots)| *r == e && shots.contains(&s)))
        };
        let mut out = Vec::with_capacity(groups.len());
        for (gi, shots) in groups.iter().enumerate() {
            // the nearest rows above and below, past any empty group
            let above = groups[..gi].iter().rev().find_map(|g| g.last().copied());
            let below = groups[gi + 1..].iter().find_map(|g| g.first().copied());
            let mut here = GroupEditSpans::default();
            if shots.is_empty() {
                for (e, _) in &refs {
                    if joins(*e, above) && joins(*e, below) {
                        here.through.push(*e);
                    }
                }
            } else {
                for (e, from, to) in self.edit_spans(shots) {
                    here.spans.push(EditSpan {
                        edit: e,
                        from,
                        to,
                        before: from == 0 && joins(e, above),
                        after: to + 1 == shots.len() && joins(e, below),
                    });
                }
            }
            out.push(here);
        }
        out
    }
}

/// One run of rows an edit reference joins inside one group.
#[derive(Clone, Debug, PartialEq)]
pub struct EditSpan {
    pub edit: Id,
    pub from: usize,
    pub to: usize,
    /// The run carries on from the group above, across this heading.
    pub before: bool,
    /// The run carries on into the group below.
    pub after: bool,
}

/// One group's brackets: its runs, and what passes through it when empty.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct GroupEditSpans {
    pub spans: Vec<EditSpan>,
    pub through: Vec<Id>,
}
