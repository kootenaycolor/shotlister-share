//! Sort positions.
//!
//! Order is data, and moving one row must write one change — not renumber every
//! row after it. That was the single worst performance bug in the prototype,
//! where reordering a scene rewrote every shot in the project one call at a time.
//!
//! A position is a float; inserting between two rows takes the midpoint. Floats
//! run out of precision after roughly fifty consecutive inserts into the *same*
//! gap, so `needs_renormalize` flags it and `renormalize` respaces that list.
//! Rare, and unlike the prototype it is the exception rather than every move.
//!
//! The public shape here is deliberately narrow so the implementation can be
//! swapped for string fractional indexing later without touching callers.

pub const STEP: f64 = 1024.0;
const MIN_GAP: f64 = 1e-9;

/// A position between two neighbours. `None` means "the end".
pub fn between(before: Option<f64>, after: Option<f64>) -> f64 {
    match (before, after) {
        (None, None) => 0.0,
        (Some(a), None) => a + STEP,
        (None, Some(b)) => b - STEP,
        (Some(a), Some(b)) => {
            if b <= a {
                // Callers passed neighbours out of order; stay to the right of
                // `a` rather than silently producing a position that sorts wrong.
                a + STEP
            } else {
                a + (b - a) / 2.0
            }
        }
    }
}

/// Position for appending to the end of a list.
pub fn after_last(positions: &[f64]) -> f64 {
    let max = positions.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    if max.is_finite() {
        max + STEP
    } else {
        0.0
    }
}

/// True when any adjacent pair has collapsed to the point where another insert
/// between them would not produce a distinct value.
pub fn needs_renormalize(sorted: &[f64]) -> bool {
    sorted.windows(2).any(|w| (w[1] - w[0]).abs() < MIN_GAP)
}

/// Evenly respaced positions for a list already in the desired order.
pub fn renormalize(count: usize) -> Vec<f64> {
    (0..count).map(|i| i as f64 * STEP).collect()
}

/// Sort helper that keeps ordering stable and never panics on NaN, which a
/// corrupt or hand-edited change file could otherwise introduce.
pub fn compare(a: f64, b: f64) -> std::cmp::Ordering {
    a.partial_cmp(&b).unwrap_or(std::cmp::Ordering::Equal)
}

// ---------------------------------------------------- moving things by hand
//
// **Three moves the Mac makes with a drag, each one undo step.** They live
// here rather than beside the lists they move because `doc.rs` was being
// rewritten by another thread the day they were written (2026-09-29); they
// use nothing of the document's but its public doors, so they could live
// anywhere, and "where things sit in a list" is what this module is about.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::value::Value;

impl Doc {
    /// **A reference board moved in the list**, to sit at `index` of the
    /// boards as they read now — counted once the board is lifted out, the
    /// way every list in the app counts a drop. One undo step.
    ///
    /// Boards made before they carried an order all read `0.0`, and a
    /// midpoint between two zeros is no place at all — so a list with ties or
    /// gaps is respaced first, in the order it already reads, inside the same
    /// step. Nothing visible moves but the board that was dragged.
    pub fn move_board_to(&mut self, board: Id, index: usize) {
        let boards = self.boards_in_order();
        let Some(from) = boards.iter().position(|b| *b == board) else {
            return;
        };
        let others: Vec<Id> = boards.iter().copied().filter(|b| *b != board).collect();
        let index = index.min(others.len());
        if index == from {
            return;
        }
        let tx = self.begin("Move reference board");
        let orders: Vec<Option<f64>> = boards
            .iter()
            .map(|b| self.get(*b).and_then(|r| r.float(f::ORDER)))
            .collect();
        let tidy = orders.iter().all(|o| o.is_some()) && {
            let mut sorted: Vec<f64> = orders.iter().flatten().copied().collect();
            sorted.sort_by(|a, b| compare(*a, *b));
            sorted.windows(2).all(|w| w[1] > w[0]) && !needs_renormalize(&sorted)
        };
        if !tidy {
            for (b, position) in boards.iter().zip(renormalize(boards.len())) {
                self.set(*b, f::ORDER, Value::Float(position));
            }
        }
        let at = |i: usize| -> Option<f64> {
            others.get(i).and_then(|id| self.get(*id)).and_then(|r| r.float(f::ORDER))
        };
        let before = if index == 0 { None } else { at(index - 1) };
        let position = between(before, at(index));
        self.set(board, f::ORDER, Value::Float(position));
        self.end(tx);
    }

    /// **Scenes put down on a day where the hand let go** — ahead of
    /// `before`'s strip on that day, or last — or taken off the board
    /// altogether, given no day. One undo step however many scenes and shots
    /// travel.
    ///
    /// `from` is the day the strips were lifted off. Given one, only the
    /// scene's shots on *that* day travel, so a scene split across two days
    /// moves the half that was dragged and leaves the other where it is.
    ///
    /// Given none — a scene dragged in from the scene list — **only the
    /// shots still on no day travel**, and the ones already on a day stay
    /// where they are. His report, 2026-10-17: Call Her Back's scene 16 read
    /// "Day 3 · 3 left", and dragging it onto another day pulled its two Day 3
    /// shots along with the three he meant, so the remainder could never be
    /// put anywhere but beside them. A scene with nothing left to place comes
    /// whole, as it always did, apart from any of it already on the day.
    ///
    /// It used to be two calls, *schedule* then *move in day*, each its own
    /// undo step and each its own trip through the view model; one ⌘Z took
    /// back half a drop.
    pub fn put_scenes_on_day(
        &mut self,
        scenes: &[Id],
        from: Option<Id>,
        day: Option<Id>,
        before: Option<Id>,
    ) {
        let tx = self.begin(match (day, scenes.len()) {
            (None, 1) => "Remove scene from day",
            (None, _) => "Remove scenes from day",
            (Some(_), 1) => "Schedule scene",
            _ => "Schedule scenes",
        });
        for scene in scenes {
            let shots = self.placements_in_scene(*scene);
            let on = |d: &Self, p: &Id| d.get(*p).and_then(|r| r.ref_id(f::DAY));
            // From the list onto a day: the remainder, when there is one.
            let remainder = from.is_none()
                && day.is_some()
                && shots.iter().any(|p| on(self, p).is_none());
            let travelling: Vec<Id> = shots
                .into_iter()
                .filter(|p| {
                    let on = on(self, p);
                    match from {
                        Some(from) => on == Some(from),
                        None if remainder => on.is_none(),
                        None => on != day || on.is_none(),
                    }
                })
                .collect();
            match day {
                None => {
                    for p in travelling {
                        if self.get(p).and_then(|r| r.ref_id(f::DAY)).is_some() {
                            self.unschedule(p);
                        }
                    }
                }
                Some(day) => {
                    if from != Some(day) {
                        for p in travelling {
                            self.schedule(p, day);
                        }
                    }
                    if Some(*scene) != before {
                        self.move_scene_in_day(*scene, day, before);
                    } else if remainder {
                        // Let go on its own strip: the remainder joins it
                        // there, rather than trailing at the day's end.
                        let next = self.scene_after_on_day(*scene, day);
                        self.move_scene_in_day(*scene, day, next);
                    }
                }
            }
        }
        self.end(tx);
    }

    /// The scene whose strip follows `scene`'s on `day`, if any.
    fn scene_after_on_day(&self, scene: Id, day: Id) -> Option<Id> {
        let mut seen: Vec<Id> = Vec::new();
        for p in self.placements_on_day(day) {
            if let Some(s) = self.get(p).and_then(|r| r.ref_id(f::SCENE)) {
                if !seen.contains(&s) {
                    seen.push(s);
                }
            }
        }
        let at = seen.iter().position(|s| *s == scene)?;
        seen.get(at + 1).copied()
    }

    /// **Several shots onto a day at once** — the remainder of a scene
    /// opened in the scene list, one shot or a handful picked there. Each
    /// shot whose scene already has a strip on the day joins it; the rest
    /// stand together where the hand let go, ahead of `before`'s strip or
    /// last. Shots already on the day stay put. One undo step.
    pub fn put_shots_on_day(&mut self, placements: &[Id], day: Id, before: Option<Id>) {
        let scene_of = |d: &Self, p: Id| d.get(p).and_then(|r| r.ref_id(f::SCENE));
        let mut standing: Vec<Id> = Vec::new();
        for p in placements {
            let Some(scene) = scene_of(self, *p) else { continue };
            let joins = self
                .placements_on_day(day)
                .iter()
                .any(|q| !placements.contains(q) && scene_of(self, *q) == Some(scene));
            if !joins && !standing.contains(&scene) {
                standing.push(scene);
            }
        }
        let tx = self.begin(if placements.len() == 1 { "Schedule shot" } else { "Schedule shots" });
        for p in placements {
            if self.get(*p).and_then(|r| r.ref_id(f::DAY)) != Some(day) {
                self.schedule(*p, day);
            }
        }
        for scene in standing {
            if Some(scene) != before {
                self.move_scene_in_day(scene, day, before);
            }
        }
        self.end(tx);
    }

    /// **One shot out of its scene onto a day** — the half of splitting a
    /// scene that the open strip's shot rows drag. When the scene has no
    /// strip on that day yet, the new strip stands where the hand let go
    /// (ahead of `before`, or last); when it has one, the shot joins it. One
    /// undo step.
    pub fn put_shot_on_day(&mut self, placement: Id, day: Id, before: Option<Id>) {
        let Some(scene) = self.get(placement).and_then(|r| r.ref_id(f::SCENE)) else {
            return;
        };
        let joins = self.placements_on_day(day).iter().any(|p| {
            *p != placement && self.get(*p).and_then(|r| r.ref_id(f::SCENE)) == Some(scene)
        });
        let tx = self.begin("Schedule shot");
        if self.get(placement).and_then(|r| r.ref_id(f::DAY)) != Some(day) {
            self.schedule(placement, day);
        }
        if !joins && Some(scene) != before {
            self.move_scene_in_day(scene, day, before);
        }
        self.end(tx);
    }
}
