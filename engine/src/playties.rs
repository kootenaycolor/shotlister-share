//! **A shot tied to the words of a film's screenplay** — Ref 1553.
//!
//! `quoting.rs` ties a shot to a stretch of a commercial's script, a text the
//! film keeps. A film's screenplay is different: it is a draft taken in
//! (`revisions.rs`), kept beside the media by its hash, and a new one arrives
//! every week of prep. So a tie here is the same idea — *highlight the words
//! and they are the shot's* (his ruling of 2026-09-19, in `quoting.rs`) — with
//! one change that follows from where the text lives: **a tie keeps its own
//! words.**
//!
//! A stretch is `(from, to, words)`: UTF-16 offsets into the draft as it is
//! laid out on pages (`Draft`), and the words that were there. The offsets
//! are only where to look first. Every reading checks the words: still there,
//! the stretch stands; moved (a new draft, a line added above, a page that
//! wraps differently), they are found again in the same scene, nearest where
//! they were; **gone, the stretch is reported as lost and kept**, so a later
//! draft that puts the words back finds them again. The same words in some
//! other scene are not a match: "Morning." is in every script. Nothing here ever moves a tie silently onto other words,
//! and nothing deletes one but a person letting it go. *Report, never invent,
//! and never destroy.*
//!
//! Because a stretch carries its words, a tie can be made with no draft in
//! hand at all (the web connector has no files): it is written with no
//! place, and found on the first reading, in the shot's scene first.
//!
//! The draft's text is every line the writer wrote, as laid out, joined by
//! line breaks; the paginator's own `(MORE)` and `(CONT'D)` are left out, so
//! a page that breaks differently next week does not lose a tie. Words are
//! compared with every run of blank space as one, so a line that wraps at a
//! different word still matches.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::pages::Paginated;
use crate::screenplay::Screenplay;
use crate::value::Value;

/// On a shot: the draft its stretches were last written against (hex id).
pub const PLAY_OF: &str = "play_of";
/// On a shot: `[from, to, from, to, …]`, one pair per stretch.
pub const PLAY_SPANS: &str = "play_spans";
/// On a shot: the words of each stretch, in the same order.
pub const PLAY_WORDS: &str = "play_words";
/// On a shot: the scene each stretch was in, in the same order ("" when it
/// was tied with no draft in hand).
pub const PLAY_SCENES: &str = "play_scenes";

/// A draft as text a tie can point into.
#[derive(Clone, Debug, Default)]
pub struct Draft {
    /// The writer's lines, as laid out, joined by `\n`.
    pub text: String,
    /// For each page, for each of its lines: the line's UTF-16 range in
    /// `text`, or `None` for the paginator's own words.
    pub lines: Vec<Vec<Option<(usize, usize)>>>,
    /// Each scene's label and the range from its first line to its last.
    pub scenes: Vec<(String, usize, usize)>,
}

impl Draft {
    /// A laid-out screenplay as a draft.
    pub fn of(screenplay: &Screenplay, laid: &Paginated) -> Draft {
        let mut text = String::new();
        let mut at = 0usize;
        let mut lines = Vec::with_capacity(laid.pages.len());
        let mut scenes: Vec<(String, usize, usize)> = Vec::new();
        let mut current: Option<usize> = None;
        for page in &laid.pages {
            let mut here = Vec::with_capacity(page.lines.len());
            for line in &page.lines {
                if line.added {
                    here.push(None);
                    continue;
                }
                if !text.is_empty() {
                    text.push('\n');
                    at += 1;
                }
                let from = at;
                text.push_str(&line.text);
                at += line.text.encode_utf16().count();
                here.push(Some((from, at)));
                if let Some(index) = line.scene {
                    if current == Some(index) {
                        if let Some(last) = scenes.last_mut() {
                            last.2 = at;
                        }
                    } else if let Some(scene) = screenplay.scenes.get(index) {
                        scenes.push((scene.label.clone(), from, at));
                        current = Some(index);
                    }
                }
            }
            lines.push(here);
        }
        Draft { text, lines, scenes }
    }

    fn len(&self) -> usize {
        self.text.encode_utf16().count()
    }

    /// The words between two offsets.
    pub fn slice(&self, from: usize, to: usize) -> String {
        let units: Vec<u16> = self.text.encode_utf16().collect();
        let to = to.min(units.len());
        let from = from.min(to);
        String::from_utf16_lossy(&units[from..to])
    }

    /// The scene a place in the draft is in.
    pub fn scene_at(&self, at: usize) -> Option<&str> {
        self.scenes.iter().find(|(_, a, b)| *a <= at && at < *b).map(|(l, _, _)| l.as_str())
    }

    fn scene_range(&self, label: &str) -> Option<(usize, usize)> {
        self.scenes
            .iter()
            .find(|(l, _, _)| crate::natural::same(l, label))
            .map(|(_, a, b)| (*a, *b))
    }

    /// Every place these words are, blank space matched loosely: `(from, to)`.
    pub fn finds(&self, words: &str) -> Vec<(usize, usize)> {
        let needle = squeeze(words.trim());
        if needle.is_empty() {
            return Vec::new();
        }
        let (hay, map) = squeezed(&self.text);
        let mut out = Vec::new();
        for (byte, _) in hay.match_indices(needle.as_str()) {
            let first = map.partition_point(|m| m.0 < byte);
            let last_byte = byte + needle.len();
            let last = map.partition_point(|m| m.0 < last_byte);
            if first < map.len() && last > first {
                out.push((map[first].1, map[last - 1].2));
            }
        }
        out
    }
}

/// Every run of blank space as one space.
fn squeeze(s: &str) -> String {
    squeezed(s).0
}

/// `s` with each run of blank space one space, and for each char of the
/// result: its byte in the result, and the UTF-16 range it stands for in `s`.
fn squeezed(s: &str) -> (String, Vec<(usize, usize, usize)>) {
    let mut out = String::with_capacity(s.len());
    let mut map: Vec<(usize, usize, usize)> = Vec::with_capacity(s.len());
    let mut unit = 0usize;
    let mut blank_run: Option<usize> = None;
    for c in s.chars() {
        let width = c.len_utf16();
        if c.is_whitespace() {
            match blank_run {
                Some(i) => map[i].2 = unit + width,
                None => {
                    blank_run = Some(map.len());
                    map.push((out.len(), unit, unit + width));
                    out.push(' ');
                }
            }
        } else {
            blank_run = None;
            map.push((out.len(), unit, unit + width));
            out.push(c);
        }
        unit += width;
    }
    (out, map)
}

/// One stretch a shot holds.
#[derive(Clone, Debug, PartialEq)]
pub struct Stretch {
    pub from: usize,
    pub to: usize,
    pub words: String,
    /// The scene the words were in, by number; empty when not known.
    pub scene: String,
}

impl Stretch {
    /// The words as a person reads them: a line the page wrapped is one line.
    pub fn plain(&self) -> String {
        squeeze(self.words.trim())
    }
}

/// A shot's stretches read against one draft: the ones found, in draft order,
/// and the words of the ones that are not in it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Reading {
    pub found: Vec<(usize, usize)>,
    pub lost: Vec<String>,
}

impl Doc {
    /// The stretches a shot holds, as kept. Empty when it holds none.
    pub fn play_stretches(&self, shot: Id) -> Vec<Stretch> {
        let Some(record) = self.get(shot) else { return Vec::new() };
        let spans = record.get(PLAY_SPANS).and_then(|v| v.as_list()).unwrap_or(&[]);
        let words = record.get(PLAY_WORDS).and_then(|v| v.as_list()).unwrap_or(&[]);
        let scenes = record.get(PLAY_SCENES).and_then(|v| v.as_list()).unwrap_or(&[]);
        words
            .iter()
            .enumerate()
            .filter_map(|(i, w)| {
                let w = w.as_text()?.to_string();
                if w.trim().is_empty() {
                    return None;
                }
                let from = spans.get(i * 2).and_then(|v| v.as_int()).unwrap_or(0).max(0) as usize;
                let to = spans.get(i * 2 + 1).and_then(|v| v.as_int()).unwrap_or(0).max(0) as usize;
                let scene = scenes.get(i).and_then(|v| v.as_text()).unwrap_or_default().to_string();
                Some(Stretch { from, to: to.max(from), words: w, scene })
            })
            .collect()
    }

    /// The draft a shot's stretches were last written against.
    pub fn play_of(&self, shot: Id) -> Option<Id> {
        self.get(shot).and_then(|r| r.text(PLAY_OF)).and_then(Id::from_hex)
    }

    /// The words a shot holds, its stretches joined by an ellipsis — no
    /// draft needed, because they are kept.
    pub fn play_excerpt(&self, shot: Id) -> String {
        self.play_stretches(shot).iter().map(Stretch::plain).collect::<Vec<_>>().join(" … ")
    }

    /// The scene a shot is in, by number: its first placement's.
    fn play_scene(&self, shot: Id) -> Option<String> {
        let placement = *self.placements_of_shot(shot).first()?;
        let scene = self.get(placement)?.ref_id(f::SCENE)?;
        self.get(scene)?.text(f::NUMBER).map(str::to_string)
    }

    /// **One stretch found in a draft.** Where it was, if its words are
    /// still there; else its words in the same scene, nearest where they
    /// were. A scene this draft does not have (renumbered, or cut) takes the
    /// words only where they appear once in the whole draft. A stretch tied
    /// with no draft in hand looks in the shot's scene first, then anywhere.
    /// None when the words are gone: never words that merely match
    /// somewhere else.
    fn find_stretch(&self, stretch: &Stretch, shot_scene: Option<(usize, usize)>, draft: &Draft) -> Option<(usize, usize)> {
        let placed = stretch.to > stretch.from;
        let within = |(a, b): (usize, usize), range: Option<(usize, usize)>| range.is_some_and(|(sa, sb)| a >= sa && b <= sb);
        let known = !stretch.scene.trim().is_empty();
        let own = if known { draft.scene_range(&stretch.scene) } else { None };
        let distance = |place: &(usize, usize)| {
            if placed { (place.0 as i64 - stretch.from as i64).unsigned_abs() } else { 0 }
        };
        if placed
            && squeeze(draft.slice(stretch.from, stretch.to).trim()) == squeeze(stretch.words.trim())
            && (own.is_none() || within((stretch.from, stretch.to), own))
        {
            return Some((stretch.from, stretch.to));
        }
        let finds = draft.finds(&stretch.words);
        match (known, own) {
            (true, Some(range)) => finds.into_iter().filter(|p| within(*p, Some(range))).min_by_key(|p| (distance(p), p.0)),
            (true, None) => (finds.len() == 1).then(|| finds[0]),
            (false, _) => finds.into_iter().min_by_key(|p| (!within(*p, shot_scene), distance(p), p.0)),
        }
    }

    /// **A shot's stretches in one draft.**
    pub fn play_reading(&self, shot: Id, draft: &Draft) -> Reading {
        let stretches = self.play_stretches(shot);
        if stretches.is_empty() {
            return Reading::default();
        }
        let scene = self.play_scene(shot).and_then(|n| draft.scene_range(&n));
        let mut reading = Reading::default();
        for stretch in &stretches {
            match self.find_stretch(stretch, scene, draft) {
                Some(place) => reading.found.push(place),
                None => reading.lost.push(stretch.plain()),
            }
        }
        reading.found.sort();
        reading.found.dedup();
        reading
    }

    /// Every shot holding words of the screenplay, in story order.
    pub fn shots_holding_lines(&self) -> Vec<Id> {
        let mut seen = Vec::new();
        for placement in self.all_placements() {
            let Some(shot) = self.get(placement).and_then(|r| r.ref_id(f::SHOT)) else { continue };
            if !seen.contains(&shot) && !self.play_stretches(shot).is_empty() {
                seen.push(shot);
            }
        }
        seen
    }

    /// **Every tie, read against one draft**: `(shot, reading)` for each shot
    /// that holds lines.
    pub fn play_ties_in(&self, draft: &Draft) -> Vec<(Id, Reading)> {
        self.shots_holding_lines().into_iter().map(|shot| (shot, self.play_reading(shot, draft))).collect()
    }

    /// Write a shot's stretches in a draft: the found ones sorted, joined
    /// where they touch, trimmed of blank ends, their words read off the
    /// draft; then the lost ones, exactly as they were. None left unties.
    fn write_play(&mut self, shot: Id, revision: Option<Id>, draft: &Draft, found: Vec<(usize, usize)>, lost: &[Stretch]) {
        let units: Vec<u16> = draft.text.encode_utf16().collect();
        let mut sorted: Vec<(usize, usize)> = found.into_iter().map(|(a, b)| (a, b.min(units.len()))).filter(|(a, b)| b > a).collect();
        sorted.sort();
        let mut clean: Vec<(usize, usize)> = Vec::new();
        for (a, b) in sorted {
            match clean.last_mut() {
                Some(last) if a <= last.1 => last.1 = last.1.max(b),
                _ => clean.push((a, b)),
            }
        }
        let blank = |u: u16| matches!(u, 0x20 | 0x09 | 0x0a | 0x0d | 0xa0);
        let mut stretches: Vec<Stretch> = clean
            .into_iter()
            .filter_map(|(mut a, mut b)| {
                while a < b && blank(units[a]) {
                    a += 1;
                }
                while b > a && blank(units[b - 1]) {
                    b -= 1;
                }
                (b > a).then(|| Stretch {
                    from: a,
                    to: b,
                    words: draft.slice(a, b),
                    scene: draft.scene_at(a).unwrap_or_default().to_string(),
                })
            })
            .collect();
        stretches.extend(lost.iter().cloned());
        self.write_stretches(shot, revision, &stretches);
    }

    fn write_stretches(&mut self, shot: Id, revision: Option<Id>, stretches: &[Stretch]) {
        if stretches.is_empty() {
            self.clear_play(shot);
            return;
        }
        match revision {
            Some(r) => self.set(shot, PLAY_OF, Value::text(r.to_hex())),
            None => self.set(shot, PLAY_OF, Value::Null),
        }
        let spans = stretches.iter().flat_map(|s| [Value::Int(s.from as i64), Value::Int(s.to as i64)]).collect();
        self.set(shot, PLAY_SPANS, Value::List(spans));
        let words = stretches.iter().map(|s| Value::text(&s.words)).collect();
        self.set(shot, PLAY_WORDS, Value::List(words));
        let scenes = stretches.iter().map(|s| Value::text(&s.scene)).collect();
        self.set(shot, PLAY_SCENES, Value::List(scenes));
    }

    /// The shot's stretches in a draft, split into places found and the
    /// stretches whose words are not there.
    fn play_split(&self, shot: Id, draft: &Draft) -> (Vec<(usize, usize)>, Vec<Stretch>) {
        let scene = self.play_scene(shot).and_then(|n| draft.scene_range(&n));
        let mut found = Vec::new();
        let mut lost = Vec::new();
        for stretch in self.play_stretches(shot) {
            match self.find_stretch(&stretch, scene, draft) {
                Some(place) => found.push(place),
                None => lost.push(stretch),
            }
        }
        (found, lost)
    }

    /// **The highlighter, on a screenplay**: a selection the shot already
    /// holds, every word of it, is let go; anything else is added. True when
    /// it added. One step. (`Doc::toggle_ties`, for a film's draft.)
    pub fn toggle_play(&mut self, shot: Id, revision: Option<Id>, draft: &Draft, ranges: &[(usize, usize)]) -> bool {
        let len = draft.len();
        let ranges: Vec<(usize, usize)> =
            ranges.iter().map(|(a, b)| (*a.min(&len), *b.min(&len))).filter(|(a, b)| b > a).collect();
        if ranges.is_empty() {
            return false;
        }
        let (found, lost) = self.play_split(shot, draft);
        let units: Vec<u16> = draft.text.encode_utf16().collect();
        let held = |at: usize| found.iter().any(|(a, b)| *a <= at && at < *b);
        let words: Vec<usize> = ranges
            .iter()
            .flat_map(|(a, b)| *a..*b)
            .filter(|at| !matches!(units[*at], 0x20 | 0x09 | 0x0a | 0x0d | 0xa0))
            .collect();
        let letting_go = !found.is_empty() && !words.is_empty() && words.iter().all(|at| held(*at));
        let tx = self.begin(if letting_go { "Untie shot" } else { "Tie shot" });
        let now = if letting_go { cut(&found, &ranges) } else { [found, ranges].concat() };
        self.write_play(shot, revision, draft, now, &lost);
        self.end(tx);
        !letting_go
    }

    /// **Let go of the stretch under a click.** False when the click is not
    /// on one of the shot's stretches. One step.
    pub fn untie_play_at(&mut self, shot: Id, revision: Option<Id>, draft: &Draft, at: usize) -> bool {
        let (found, lost) = self.play_split(shot, draft);
        let Some(&hit) = found.iter().find(|(a, b)| *a <= at && at < *b) else { return false };
        let tx = self.begin("Untie shot");
        let left: Vec<(usize, usize)> = found.into_iter().filter(|s| *s != hit).collect();
        self.write_play(shot, revision, draft, left, &lost);
        self.end(tx);
        true
    }

    /// **Tie a shot to words of the screenplay** — the connector's door, given
    /// the words rather than offsets. With a draft, the words must be in it
    /// (the shot's scene first, then the first place they appear) and false
    /// says they are not; `add` keeps what it already holds. With no draft
    /// in hand, the words are kept with no place, to be found on reading.
    /// One step.
    pub fn tie_play_words(&mut self, shot: Id, revision: Option<Id>, draft: Option<&Draft>, words: &str, add: bool) -> bool {
        let words = words.trim();
        if words.is_empty() {
            return false;
        }
        let Some(draft) = draft else {
            let mut stretches = if add { self.play_stretches(shot) } else { Vec::new() };
            stretches.push(Stretch { from: 0, to: 0, words: words.to_string(), scene: String::new() });
            let tx = self.begin("Tie shot");
            self.write_stretches(shot, revision.or(self.play_of(shot)), &stretches);
            self.end(tx);
            return true;
        };
        let scene = self.play_scene(shot).and_then(|n| draft.scene_range(&n));
        let probe = Stretch { from: 0, to: 0, words: words.to_string(), scene: String::new() };
        let Some(place) = self.find_stretch(&probe, scene, draft) else { return false };
        let (found, lost) = if add { self.play_split(shot, draft) } else { (Vec::new(), Vec::new()) };
        let tx = self.begin("Tie shot");
        self.write_play(shot, revision, draft, [found, vec![place]].concat(), &lost);
        self.end(tx);
        true
    }

    /// Let go of these words from what a shot holds. With a draft, exactly
    /// those words (a stretch can split in two); without, every stretch
    /// whose words include them. False when it holds no such words.
    pub fn untie_play_words(&mut self, shot: Id, revision: Option<Id>, draft: Option<&Draft>, words: &str) -> bool {
        let needle = squeeze(words.trim());
        if needle.is_empty() {
            return false;
        }
        match draft {
            Some(draft) => {
                let (found, lost) = self.play_split(shot, draft);
                let Some(place) = draft
                    .finds(words)
                    .into_iter()
                    .find(|(a, b)| found.iter().any(|(fa, fb)| *fa < *b && *a < *fb))
                else {
                    return false;
                };
                let tx = self.begin("Untie shot");
                let left = cut(&found, &[place]);
                self.write_play(shot, revision, draft, left, &lost);
                self.end(tx);
                true
            }
            None => {
                let all = self.play_stretches(shot);
                let left: Vec<Stretch> = all.iter().filter(|s| !squeeze(&s.words).contains(&needle)).cloned().collect();
                if left.len() == all.len() {
                    return false;
                }
                let tx = self.begin("Untie shot");
                self.write_stretches(shot, self.play_of(shot), &left);
                self.end(tx);
                true
            }
        }
    }

    /// The shot holds no words of the screenplay. One step.
    pub fn untie_play(&mut self, shot: Id) {
        if self.play_stretches(shot).is_empty() {
            return;
        }
        let tx = self.begin("Untie shot");
        self.clear_play(shot);
        self.end(tx);
    }

    fn clear_play(&mut self, shot: Id) {
        for field in [PLAY_OF, PLAY_SPANS, PLAY_WORDS, PLAY_SCENES] {
            if self.get(shot).and_then(|r| r.get(field)).is_some() {
                self.set(shot, field, Value::Null);
            }
        }
    }
}

/// `spans` with every range in `away` taken out of them.
fn cut(spans: &[(usize, usize)], away: &[(usize, usize)]) -> Vec<(usize, usize)> {
    let mut left: Vec<(usize, usize)> = spans.to_vec();
    for &(from, to) in away {
        let mut next = Vec::new();
        for (a, b) in left {
            if b <= from || a >= to {
                next.push((a, b));
                continue;
            }
            if a < from {
                next.push((a, from));
            }
            if b > to {
                next.push((to, b));
            }
        }
        left = next;
    }
    left
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::screenplay::{read_with, Detection};
    use crate::stamp::DeviceId;

    const ONE: &str = "1 INT. KITCHEN - NIGHT 1\n\nAnya picks up the phone. She listens, very still.\n\nANYA\nWho is this?\n\n2 INT. HALL - NIGHT 2\n\nThe book lies open on the floor.\n\nANYA\nWho is this?\n";

    fn draft(text: &str) -> Draft {
        let play = read_with(text, &Detection::default());
        let laid = crate::pages::lay_out(&play);
        Draft::of(&play, &laid)
    }

    fn at(d: &Draft, words: &str) -> (usize, usize) {
        d.finds(words)[0]
    }

    /// Scene 1's "Who is this?" (scene 2 says it too).
    fn d_who(d: &Draft) -> (usize, usize) {
        let place = d.finds("Who is this?")[0];
        assert_eq!(d.scene_at(place.0), Some("1"));
        place
    }

    fn film() -> (Doc, Id, Id, Id, Id) {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("CHB");
        let one = d.create_scene("1");
        let two = d.create_scene("2");
        let (a, _) = d.add_shot_to_scene(one);
        let (b, _) = d.add_shot_to_scene(two);
        d.clear_history();
        (d, one, two, a, b)
    }

    #[test]
    fn a_draft_is_its_writers_lines_and_knows_its_scenes() {
        let d = draft(ONE);
        assert!(d.text.contains("Anya picks up the phone."));
        assert_eq!(d.scenes.len(), 2);
        assert_eq!(d.scenes[0].0, "1");
        let (from, _) = at(&d, "The book lies open");
        assert_eq!(d.scene_at(from), Some("2"));
        // Every line's range reads back its own words.
        let laid = crate::pages::lay_out(&read_with(ONE, &Detection::default()));
        for (page, lines) in laid.pages.iter().zip(&d.lines) {
            for (line, range) in page.lines.iter().zip(lines) {
                if let Some((a, b)) = range {
                    assert_eq!(d.slice(*a, *b), line.text);
                }
            }
        }
        // Blank space is matched loosely: a line break reads as a space.
        assert_eq!(d.finds("Anya   picks\nup").len(), 1);
    }

    #[test]
    fn a_shot_holds_lines_and_lets_them_go() {
        let (mut d, _, _, a, b) = film();
        let draft1 = draft(ONE);
        let rev = Some(Id::new());
        let phone = at(&draft1, "Anya picks up the phone.");
        assert!(d.toggle_play(a, rev, &draft1, &[phone]));
        assert_eq!(d.play_excerpt(a), "Anya picks up the phone.");
        assert_eq!(d.play_reading(a, &draft1).found, vec![phone]);
        assert_eq!(d.play_of(a), rev);

        // A second stretch far off; the same words again let them go.
        let listen = at(&draft1, "She listens, very still.");
        assert!(d.toggle_play(a, rev, &draft1, &[listen]));
        assert_eq!(d.play_reading(a, &draft1).found.len(), 2);
        assert!(!d.toggle_play(a, rev, &draft1, &[(listen.0, listen.1 + 1)]));
        assert_eq!(d.play_excerpt(a), "Anya picks up the phone.");

        // A click on a stretch lets that one go; one undo brings it back.
        assert!(d.untie_play_at(a, rev, &draft1, phone.0 + 2));
        assert_eq!(d.play_excerpt(a), "");
        assert!(d.shots_holding_lines().is_empty());
        d.undo();
        assert_eq!(d.play_excerpt(a), "Anya picks up the phone.");

        // Words: in the shot's own scene before anywhere else.
        assert!(d.tie_play_words(b, rev, Some(&draft1), "Who is this?", false));
        let found = d.play_reading(b, &draft1).found;
        assert_eq!(draft1.scene_at(found[0].0), Some("2"));
        assert!(!d.tie_play_words(b, rev, Some(&draft1), "not in the script", true));
        assert!(d.untie_play_words(b, rev, Some(&draft1), "is"));
        assert_eq!(d.play_excerpt(b), "Who … this?");
        d.untie_play(b);
        assert_eq!(d.play_excerpt(b), "");
    }

    #[test]
    fn a_new_draft_finds_the_words_again_and_reports_the_lost_ones() {
        let (mut d, _, _, a, b) = film();
        let draft1 = draft(ONE);
        let rev = Some(Id::new());
        d.toggle_play(a, rev, &draft1, &[at(&draft1, "Anya picks up the phone.")]);
        d.toggle_play(b, rev, &draft1, &[at(&draft1, "The book lies open on the floor.")]);

        // A line added above: the words moved, and are found where they went.
        let two = ONE.replace("NIGHT 1\n\n", "NIGHT 1\n\nRain on the window.\n\n");
        let draft2 = draft(&two);
        let found = d.play_reading(a, &draft2).found;
        assert_eq!(draft2.slice(found[0].0, found[0].1), "Anya picks up the phone.");
        assert!(found[0].0 > at(&draft1, "Anya picks up the phone.").0);

        // A draft that cut the book: lost, said so, and kept.
        let three = two.replace("The book lies open on the floor.", "The hall is empty.");
        let draft3 = draft(&three);
        let reading = d.play_reading(b, &draft3);
        assert!(reading.found.is_empty());
        assert_eq!(reading.lost, vec!["The book lies open on the floor.".to_string()]);
        assert_eq!(d.play_excerpt(b), "The book lies open on the floor.");

        // A gesture in draft 3 keeps the lost words for a draft that has them.
        d.toggle_play(b, rev, &draft3, &[at(&draft3, "The hall is empty.")]);
        assert_eq!(d.play_reading(b, &draft3).lost.len(), 1);
        assert_eq!(d.play_reading(b, &draft1).found.len(), 1);
        assert_eq!(d.play_stretches(b).len(), 2);

        // Words cut from their scene are lost even where another scene has them.
        let (mut f, _, _, a2, _) = film();
        let who = d_who(&draft1);
        assert!(f.toggle_play(a2, rev, &draft1, &[who]));
        let four = ONE.replacen("ANYA\nWho is this?", "ANYA\nHello?", 1);
        let reading = f.play_reading(a2, &draft(&four));
        assert_eq!(reading.lost, vec!["Who is this?".to_string()]);

        // Ties made with no draft in hand are found on reading, in the shot's scene.
        let (mut e, _, _, _, b2) = film();
        assert!(e.tie_play_words(b2, None, None, "Who is this?", false));
        let found = e.play_reading(b2, &draft1).found;
        assert_eq!(draft1.scene_at(found[0].0), Some("2"));
        assert!(e.untie_play_words(b2, None, None, "Who"));
        assert!(e.play_stretches(b2).is_empty());
    }
}
