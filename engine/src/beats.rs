//! **The beats of an AV script, and the shot tied to each.**
//!
//! His ruling, 2026-09-19, reversing the morning's scene-level Video / Audio:
//! *"the AV script in the scene header just doesn't work for me — it's too
//! much information and it kind of defies what an AV script is, which is
//! combining a specific image with a piece of audio. It's more of a shot
//! level thing. Scenes are still a thing since locations and stuff make that
//! possible, but putting it in the scene header doesn't make sense. Every
//! shot is tied to a section of the script."*
//!
//! So a pasted script becomes **beats** — one record each, in order, in a
//! section — and a **shot points at one beat**. A scene is a place or a
//! setup a person makes by hand; it carries no script. A shot's Video and
//! Audio are its beat's, read fresh (`view.rs`, `export/rows.rs`), never
//! copied onto the shot: change the beat and every shot tied to it says the
//! new words.
//!
//! **What the morning's films keep.** A commercial whose scenes carry
//! Video / Audio from before is adopted once at open (`adopt_scene_beats`):
//! each such scene's words become a beat in the scene's section, the scene's
//! shots are tied to it, and the scene's own copy is cleared — moved, not
//! destroyed, and the film reads exactly as it did.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::order;
use crate::store::Kind;
use crate::value::Value;

impl Doc {
    /// Every beat, in the order the script has them.
    pub fn beats_in_order(&self) -> Vec<Id> {
        let mut beats = self.store().of_kind(&Kind::Beat);
        beats.sort_by(|a, b| {
            order::compare(a.float(f::ORDER).unwrap_or(0.0), b.float(f::ORDER).unwrap_or(0.0))
        });
        beats.iter().map(|r| r.id).collect()
    }

    /// The beats in one section, in order — or the ones in none.
    pub fn beats_in_section(&self, section: Option<Id>) -> Vec<Id> {
        self.beats_in_order()
            .into_iter()
            .filter(|b| self.get(*b).and_then(|r| r.ref_id(f::SEQUENCE)) == section)
            .collect()
    }

    /// **A new beat at the end of its section's run** — or at the end of the
    /// script when it has no section. Undoable on its own; a paste wraps
    /// many in one step.
    pub fn create_beat(&mut self, label: &str, video: &str, audio: &str, section: Option<Id>) -> Id {
        let tx = self.begin("Add beat");
        let all = self.beats_in_order();
        let last_in_run = match section {
            Some(s) => all
                .iter()
                .rev()
                .find(|b| self.get(**b).and_then(|r| r.ref_id(f::SEQUENCE)) == Some(s))
                .copied(),
            None => all.last().copied(),
        };
        let position = match last_in_run {
            Some(last) => {
                let at = all.iter().position(|b| *b == last).unwrap_or(0);
                let before = self.get(last).and_then(|r| r.float(f::ORDER));
                let after = all.get(at + 1).and_then(|b| self.get(*b)).and_then(|r| r.float(f::ORDER));
                order::between(before, after)
            }
            None => {
                let positions: Vec<f64> =
                    all.iter().filter_map(|b| self.get(*b).and_then(|r| r.float(f::ORDER))).collect();
                order::after_last(&positions)
            }
        };
        let id = self.create(Kind::Beat);
        self.set(id, f::ORDER, Value::Float(position));
        if !label.trim().is_empty() {
            self.set(id, f::TITLE, label.trim());
        }
        self.set(id, f::SCRIPT, video);
        self.set(id, f::AUDIO, audio);
        if let Some(section) = section {
            self.set(id, f::SEQUENCE, section);
        }
        self.end(tx);
        id
    }

    pub fn beat_label(&self, beat: Id) -> String {
        self.get(beat).and_then(|r| r.text(f::TITLE)).unwrap_or_default().trim().to_string()
    }

    pub fn beat_video(&self, beat: Id) -> String {
        self.get(beat).and_then(|r| r.text(f::SCRIPT)).unwrap_or_default().to_string()
    }

    pub fn beat_audio(&self, beat: Id) -> String {
        self.get(beat).and_then(|r| r.text(f::AUDIO)).unwrap_or_default().to_string()
    }

    /// **A beat goes; the shots tied to it are untied and keep everything
    /// else.** Report, never invent — and never destroy a shot for a line.
    pub fn delete_beat(&mut self, beat: Id) -> usize {
        let tied = self.shots_on_beat(beat);
        let tx = self.begin("Delete beat");
        for shot in &tied {
            self.set(*shot, f::BEAT, Value::Null);
        }
        self.delete(beat);
        self.end(tx);
        tied.len()
    }

    /// **A beat moved to sit just after another** — or first, given `None`.
    /// It takes the section of the beat it lands after.
    pub fn move_beat_after(&mut self, beat: Id, after: Option<Id>) {
        let list: Vec<Id> = self.beats_in_order().into_iter().filter(|b| *b != beat).collect();
        let position = |id: Id| self.get(id).and_then(|r| r.float(f::ORDER));
        let at = match after {
            None => 0,
            Some(a) => match list.iter().position(|b| *b == a) {
                Some(i) => i + 1,
                None => return,
            },
        };
        let before = if at == 0 { None } else { position(list[at - 1]) };
        let next = list.get(at).and_then(|b| position(*b));
        let section = after.and_then(|a| self.get(a)).and_then(|r| r.ref_id(f::SEQUENCE))
            .or_else(|| list.get(at).and_then(|b| self.get(*b)).and_then(|r| r.ref_id(f::SEQUENCE)));
        let tx = self.begin("Move beat");
        self.set(beat, f::ORDER, Value::Float(order::between(before, next)));
        match section {
            Some(s) => self.set(beat, f::SEQUENCE, s),
            None => self.set(beat, f::SEQUENCE, Value::Null),
        }
        self.end(tx);
    }

    /// The beat a shot is tied to, if any.
    pub fn beat_of_shot(&self, shot: Id) -> Option<Id> {
        let beat = self.get(shot)?.ref_id(f::BEAT)?;
        self.get(beat).map(|_| beat)
    }

    /// Every shot tied to this beat, in story order.
    pub fn shots_on_beat(&self, beat: Id) -> Vec<Id> {
        let mut seen = Vec::new();
        for placement in self.all_placements() {
            let Some(shot) = self.get(placement).and_then(|r| r.ref_id(f::SHOT)) else { continue };
            if seen.contains(&shot) {
                continue;
            }
            if self.get(shot).and_then(|r| r.ref_id(f::BEAT)) == Some(beat) {
                seen.push(shot);
            }
        }
        seen
    }

    /// **Tie a shot to a beat**, or untie it with `None`. One step.
    pub fn set_shot_beat(&mut self, shot: Id, beat: Option<Id>) {
        let tx = self.begin(if beat.is_some() { "Tie shot to beat" } else { "Untie shot" });
        match beat {
            Some(b) => self.set(shot, f::BEAT, b),
            None => self.set(shot, f::BEAT, Value::Null),
        }
        self.end(tx);
    }

    /// **The morning's scene-level script becomes beats, once.** For a
    /// commercial: every scene carrying Video or Audio gets a beat in its
    /// section with those words, its shots are tied to it, and the scene's
    /// copy is cleared — so nothing is said twice and nothing is lost.
    /// **The beat takes no label**: the scene's name is the scene's, and his
    /// script *"isn't divided by scenes — just audio really"*; a heading the
    /// script never wrote must not appear in it. Returns how many beats were
    /// made. A film, or a commercial with no such scene, is untouched.
    pub fn adopt_scene_beats(&mut self) -> usize {
        if self.kind() != crate::kind::Kind::Commercial {
            return 0;
        }
        let scenes: Vec<Id> = self
            .scenes_in_order()
            .into_iter()
            .filter(|s| {
                let r = self.get(*s);
                let has = |field: &str| r.and_then(|r| r.text(field)).map(|t| !t.trim().is_empty()).unwrap_or(false);
                has(f::SCRIPT) || has(f::AUDIO)
            })
            .collect();
        if scenes.is_empty() {
            return 0;
        }
        let tx = self.begin("Adopt script beats");
        let mut made = 0;
        for scene in scenes {
            let record = self.get(scene);
            let video = record.and_then(|r| r.text(f::SCRIPT)).unwrap_or_default().to_string();
            let audio = record.and_then(|r| r.text(f::AUDIO)).unwrap_or_default().to_string();
            let section = record.and_then(|r| r.ref_id(f::SEQUENCE));
            let beat = self.create_beat("", &video, &audio, section);
            for placement in self.placements_in_scene(scene) {
                if let Some(shot) = self.get(placement).and_then(|r| r.ref_id(f::SHOT)) {
                    if self.get(shot).and_then(|r| r.ref_id(f::BEAT)).is_none() {
                        self.set(shot, f::BEAT, beat);
                    }
                }
            }
            self.set(scene, f::SCRIPT, Value::Null);
            self.set(scene, f::AUDIO, Value::Null);
            made += 1;
        }
        self.end(tx);
        made
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kind::Kind as FilmKind;
    use crate::stamp::DeviceId;

    fn commercial() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Instant");
        d.set_kind(FilmKind::Commercial);
        d.clear_history();
        d
    }

    #[test]
    fn beats_are_made_in_their_sections_tied_to_shots_and_read_off_by_them() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        let b = d.create_sequence("Spot B");
        let open = d.create_beat("OPEN", "The kitchen.", "Music in.", Some(a));
        let tag_b = d.create_beat("TAG", "Logo.", "Sting.", Some(b));
        let tag_a = d.create_beat("TAG", "Logo.", "Sting.", Some(a));
        // A's second beat lands at the end of A's run, before B's.
        assert_eq!(d.beats_in_order(), vec![open, tag_a, tag_b]);
        assert_eq!(d.beats_in_section(Some(a)), vec![open, tag_a]);

        let scene = d.create_scene_titled("Kitchen");
        let (shot, _) = d.add_shot_to_scene(scene);
        assert_eq!(d.beat_of_shot(shot), None);
        d.set_shot_beat(shot, Some(open));
        assert_eq!(d.beat_of_shot(shot), Some(open));
        assert_eq!(d.shots_on_beat(open), vec![shot]);
        assert_eq!(d.beat_video(open), "The kitchen.");

        d.move_beat_after(tag_a, None);
        assert_eq!(d.beats_in_order(), vec![tag_a, open, tag_b]);
        assert_eq!(d.get(tag_a).unwrap().ref_id(f::SEQUENCE), Some(a), "first: keeps the run it lands before");

        assert_eq!(d.delete_beat(open), 1);
        assert_eq!(d.beat_of_shot(shot), None, "untied, not deleted");
        d.undo();
        assert_eq!(d.beat_of_shot(shot), Some(open));
    }

    #[test]
    fn a_commercial_from_the_morning_is_adopted_once() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        let scene = d.create_scene_titled("OPEN");
        d.set(scene, f::SEQUENCE, a);
        d.set(scene, f::SCRIPT, "The kitchen.");
        d.set(scene, f::AUDIO, "Music in.");
        let (shot, _) = d.add_shot_to_scene(scene);
        let plain = d.create_scene_titled("Nothing written");
        d.add_shot_to_scene(plain);

        assert_eq!(d.adopt_scene_beats(), 1);
        let beats = d.beats_in_order();
        assert_eq!(beats.len(), 1);
        assert_eq!(d.beat_label(beats[0]), "", "the scene's name stays the scene's");
        assert_eq!(d.beat_audio(beats[0]), "Music in.");
        assert_eq!(d.get(beats[0]).unwrap().ref_id(f::SEQUENCE), Some(a));
        assert_eq!(d.beat_of_shot(shot), Some(beats[0]));
        assert!(d.get(scene).unwrap().text(f::SCRIPT).map(|t| t.is_empty()).unwrap_or(true));
        // Again: nothing to do.
        assert_eq!(d.adopt_scene_beats(), 0);

        // A film is left alone.
        let mut film = Doc::new(DeviceId(2));
        film.create_project("Daybreak");
        let s = film.create_scene("34");
        film.set(s, f::SCRIPT, "INT. KITCHEN");
        assert_eq!(film.adopt_scene_beats(), 0);
    }
}
