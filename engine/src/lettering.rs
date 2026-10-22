//! When letters move, and when they stop.
//!
//! §04 describes letters as permanent: assigned once, never reflowed. That is
//! true once the shoot is under way, and it is the whole point — a letter is how
//! a shot is referred to out loud, and it must not change under somebody reading
//! it off a printed page.
//!
//! But it is not true during prep, and pretending otherwise made the app worse
//! at the part of the job where you are still moving things around. So there are
//! two regimes:
//!
//! - **Prep** — reordering shots within a scene reflows the letters to match, so
//!   story order and letters agree while you are still building the list.
//! - **Locked** — from the first shoot day's *date arriving* onward. Letters
//!   freeze and §04 applies exactly as written.
//!
//! The trigger is the date arriving, not the day being scheduled. All of
//! planning and all of scheduling happen in prep; the lock falls on the morning
//! of the first day. Nathaniel chose this knowing a callsheet printed the week
//! before can disagree with the app.
//!
//! The engine has no clock, so today is supplied. What happens when no day has a
//! date, and whether pushing a date later should unlock, are both open — this
//! derives the regime and nothing more.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::value::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Regime {
    /// Still building. Letters follow position.
    Prep,
    /// Shooting. Letters are how shots are named, and names do not move.
    Locked,
}

impl Doc {
    /// Tell the engine what day it is, as `YYYY-MM-DD`. Set on opening a project
    /// and again when the date changes under a running app.
    ///
    /// Dates are compared as text, which is exactly right in this format and
    /// saves the engine having to know anything about calendars.
    pub fn set_today(&mut self, today: Option<&str>) {
        self.today = today.map(|date| date.trim().to_string()).filter(|d| !d.is_empty());
    }

    pub fn today(&self) -> Option<&str> {
        self.today.as_deref()
    }

    /// The earliest date on any shoot day — the morning everything locks.
    pub fn first_shoot_date(&self) -> Option<String> {
        self.days_in_order()
            .into_iter()
            .map(|day| self.day_date(day))
            .filter(|date| !date.trim().is_empty())
            .min()
    }

    /// Prep until the first shoot day's date has arrived.
    ///
    /// With no dated day, or with no idea what day it is, this stays in prep —
    /// locking on a guess would be worse than not locking.
    pub fn lettering_regime(&self) -> Regime {
        let (today, first) = match (self.today(), self.first_shoot_date()) {
            (Some(today), Some(first)) => (today.to_string(), first),
            _ => return Regime::Prep,
        };
        if today >= first {
            Regime::Locked
        } else {
            Regime::Prep
        }
    }

    pub fn letters_are_locked(&self) -> bool {
        self.lettering_regime() == Regime::Locked
    }

    /// Make the letters in a scene match the order the shots are in.
    ///
    /// Only writes the ones that actually change, so a reorder near the end of a
    /// long scene stays cheap. Does nothing once letters are locked.
    /// Take a shot out of a scene.
    ///
    /// The letter closes up behind it during prep — delete 34B and what was 34C
    /// becomes 34B — for the same reason reordering reflows: while nobody has
    /// the list on paper, letters following position is what keeps story order
    /// and numbering agreeing. Once letters are locked the gap stays open, and
    /// the freed letter goes back into play for the next shot added, which is
    /// what §04 has always said.
    ///
    /// A shot that also lives in another scene **survives** — only its place
    /// here goes. A shot placed nowhere else goes with it, because a shot that
    /// appears in no scene is not a shot anybody can find.
    pub fn delete_placement(&mut self, placement: Id) -> usize {
        let Some(scene) = self.get(placement).and_then(|r| r.ref_id(f::SCENE)) else {
            return 0;
        };
        let shot = self.get(placement).and_then(|r| r.ref_id(f::SHOT));
        let elsewhere = shot
            .map(|shot| {
                self.placements_of_shot(shot)
                    .into_iter()
                    .filter(|other| *other != placement)
                    .count()
            })
            .unwrap_or(0);

        let tx = self.begin("Delete shot");
        self.delete(placement);
        if elsewhere == 0 {
            if let Some(shot) = shot {
                // Its frames go too, unless a board or another shot holds
                // the same file (`release_media_use`, his ruling 2026-09-19).
                self.release_media_uses(shot);
                self.delete(shot);
            }
        }
        let closed = self.reflow_letters(scene);
        self.end(tx);
        closed
    }

    /// Take out a whole scene, and its shots with it — except any shot that also
    /// appears somewhere else, which keeps its other placement and its other
    /// number. One thing to take back, however many shots it held.
    pub fn delete_scene(&mut self, scene: Id) -> usize {
        let placements = self.placements_in_scene(scene);
        let tx = self.begin("Delete scene");
        for placement in &placements {
            self.delete_placement(*placement);
        }
        self.diagram_forget(scene);
        self.scene_diagrams_forget(scene);
        self.delete(scene);
        self.end(tx);
        placements.len()
    }

    pub fn reflow_letters(&mut self, scene: Id) -> usize {
        if self.letters_are_locked() {
            return 0;
        }

        let placements = self.placements_in_scene(scene);
        let wanted: Vec<(Id, String)> = placements
            .iter()
            .enumerate()
            .map(|(index, placement)| (*placement, self.letters().nth(index)))
            .filter(|(placement, letter)| {
                self.get(*placement)
                    .and_then(|r| r.text(f::LETTER))
                    .map(|current| current != letter)
                    .unwrap_or(true)
            })
            .collect();

        if wanted.is_empty() {
            return 0;
        }

        let tx = self.begin("Renumber shots");
        // Two passes, because a letter being taken by its new owner while its old
        // owner still holds it would collide in the middle of the run.
        for (placement, letter) in &wanted {
            self.set(*placement, f::LETTER, Value::text(format!("~{letter}")));
        }
        for (placement, letter) in &wanted {
            self.set(*placement, f::LETTER, Value::text(letter));
        }
        self.end(tx);

        wanted.len()
    }
}
