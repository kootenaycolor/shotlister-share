//! **The script as text, and the stretch of it each shot quotes.**
//!
//! His ruling, 2026-09-19 night, reversing the same evening's beats: *"don't
//! break up every paragraph line into a beat. I just want to be able to
//! highlight text on the right side bar and assign that to a shot. Doesn't
//! need to be systematic — I or the MCP will manually do it given the text.
//! Some things can overlap or have multiple shots per beat. So I just click
//! and drag and that assigns that text to a shot."*
//!
//! So a section (or the film, when it has none) holds **one script as plain
//! text**, and a **shot quotes a range of it** — `from` and `to`, in UTF-16
//! units, the one unit JavaScript, Swift's `utf16` view and Rust can all
//! agree on. Ranges may overlap, and any number of shots may quote the same
//! stretch. Nothing is parsed; nothing is split.
//!
//! **Editing the text keeps the ties.** A shot's excerpt is looked for in
//! the new text — the same words, nearest to where they were — and the range
//! moves with them. Words that are gone leave the shot untied, and the edit
//! says how many.
//!
//! **Plain or AV** — his ask, 2026-09-30: *"I can either just do a plain
//! script or an AV script with two side by side options."* An AV script is
//! the same one text with two marks in it: `AV_CELL` between a row's Video
//! and its Audio, `AV_ROW` between rows. One text means one set of offsets,
//! so everything above — a tie, its re-anchoring, the MCP's tie by words —
//! works on an AV script unchanged, and a reader that swaps each mark for a
//! line break (`readable`) keeps every offset where it was. The marks never
//! reach a person: the panel draws them as a table, the editor as rows.
//!
//! **Several stretches to one shot** — his ask, 2026-10-05: *"a way to add
//! multiple spread out lines in a av script to a shot."* A shot's first
//! stretch stays where it always was (`script_from`/`script_to`, so a
//! reader that knows only one still reads the first), and the rest ride in
//! `script_more`, a flat list `[from, to, from, to, …]`. All of a shot's
//! stretches are in one script, sorted, never overlapping (`spans_of`).
//! Selecting words the shot already holds lets them go (`toggle_tie`); a
//! click on one of its stretches lets that one go (`untie_at`).
//!
//! **Tonight's beats become this, once** (`adopt_beats_as_script`): a
//! section's text is its beats joined by blank lines, each shot tied to a
//! beat quotes that beat's words, and the beats go.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::store::Kind;
use crate::value::Value;

/// Where a script's text lives on its section or project record.
pub const AV_SCRIPT: &str = "av_script";
/// On a shot: which script (a section id, or empty for the film's), and the
/// UTF-16 range quoted.
pub const SCRIPT_OF: &str = "script_of";
pub const SCRIPT_FROM: &str = "script_from";
pub const SCRIPT_TO: &str = "script_to";
/// On a shot: its stretches after the first, `[from, to, from, to, …]`.
pub const SCRIPT_MORE: &str = "script_more";

/// A shot's quotation: the script it is in and the range.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Quote {
    pub section: Option<Id>,
    pub from: usize,
    pub to: usize,
}

/// Between a row's Video and its Audio, in an AV script.
pub const AV_CELL: char = '\u{1d}';
/// Between one row of an AV script and the next.
pub const AV_ROW: char = '\u{1e}';

/// Is this script's text an AV script — Video beside Audio?
pub fn is_av(text: &str) -> bool {
    text.contains(AV_CELL)
}

/// An AV script's rows, `(video, audio)`, in order. A plain text is one row
/// of audio — what a plain commercial script almost always is.
pub fn av_rows(text: &str) -> Vec<(String, String)> {
    if !is_av(text) {
        return if text.is_empty() { Vec::new() } else { vec![(String::new(), text.to_string())] };
    }
    text.split(AV_ROW)
        .map(|row| match row.split_once(AV_CELL) {
            Some((video, audio)) => (video.to_string(), audio.replace(AV_CELL, "\n")),
            None => (row.to_string(), String::new()),
        })
        .collect()
}

/// Rows into an AV script's text. No rows is one empty row, so an AV
/// script with nothing in it yet is still an AV script.
pub fn av_text(rows: &[(String, String)]) -> String {
    let clean = |s: &str| s.replace([AV_CELL, AV_ROW], "\n");
    if rows.is_empty() {
        return AV_CELL.to_string();
    }
    rows.iter()
        .map(|(video, audio)| format!("{}{AV_CELL}{}", clean(video), clean(audio)))
        .collect::<Vec<_>>()
        .join(&AV_ROW.to_string())
}

/// The text with each mark a line break — one unit for one unit, so every
/// offset into the script is an offset into this.
pub fn readable(text: &str) -> String {
    text.replace([AV_CELL, AV_ROW], "\n")
}

/// **A plain script laid out as AV.** A pasted table (any tab in it) keeps
/// its columns — the label, when the table had one, heads the Video. Any
/// other text is a row per paragraph, all of it Audio, for the Video to be
/// written beside it.
pub fn av_from_plain(text: &str) -> String {
    if is_av(text) {
        return text.to_string();
    }
    let rows: Vec<(String, String)> = if text.contains('\t') {
        crate::avscript::read(text)
            .into_iter()
            .map(|r| {
                let video = match (r.label.trim().is_empty(), r.video.trim().is_empty()) {
                    (true, _) => r.video,
                    (false, true) => r.label,
                    (false, false) => format!("{}\n{}", r.label, r.video),
                };
                (video, r.audio)
            })
            .collect()
    } else {
        paragraphs(text).into_iter().map(|p| (String::new(), p)).collect()
    };
    av_text(&rows)
}

/// **An AV script as plain text**: each row's Video, then its Audio, a
/// blank line between rows. The words all stay; only the columns go.
pub fn plain_from_av(text: &str) -> String {
    if !is_av(text) {
        return text.to_string();
    }
    av_rows(text)
        .into_iter()
        .map(|(video, audio)| {
            [video.trim(), audio.trim()].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join("\n")
        })
        .filter(|row| !row.is_empty())
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn paragraphs(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut now: Vec<&str> = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            if !now.is_empty() {
                out.push(now.join("\n"));
                now.clear();
            }
        } else {
            now.push(line.trim_end());
        }
    }
    if !now.is_empty() {
        out.push(now.join("\n"));
    }
    out
}

fn utf16_slice(text: &str, from: usize, to: usize) -> String {
    let units: Vec<u16> = text.encode_utf16().collect();
    let to = to.min(units.len());
    let from = from.min(to);
    String::from_utf16_lossy(&units[from..to])
}

/// Whitespace, or one of an AV script's marks — nothing a person reads.
fn is_blank_unit(u: u16) -> bool {
    matches!(u, 0x20 | 0x09 | 0x0a | 0x0d | 0xa0 | 0x1d | 0x1e)
}

fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

/// Every UTF-16 offset at which `needle` occurs in `hay`.
fn utf16_finds(hay: &str, needle: &str) -> Vec<usize> {
    let mut out = Vec::new();
    if needle.is_empty() {
        return out;
    }
    let mut start = 0;
    while let Some(at) = hay[start..].find(needle) {
        let byte_at = start + at;
        out.push(utf16_len(&hay[..byte_at]));
        start = byte_at + needle.len().max(1);
        if start > hay.len() {
            break;
        }
    }
    out
}

impl Doc {
    fn script_holder(&self, section: Option<Id>) -> Option<Id> {
        match section {
            Some(s) => self.get(s).map(|_| s),
            None => self.project_id(),
        }
    }

    /// The script of a section, or the film's when `None`.
    pub fn av_script(&self, section: Option<Id>) -> String {
        self.script_holder(section)
            .and_then(|h| self.get(h))
            .and_then(|r| r.text(AV_SCRIPT))
            .unwrap_or_default()
            .to_string()
    }

    /// Every script the film holds, in section order, the film's own first
    /// when it has one: `(section, text)`.
    pub fn av_scripts(&self) -> Vec<(Option<Id>, String)> {
        let mut out = Vec::new();
        let own = self.av_script(None);
        if !own.is_empty() {
            out.push((None, own));
        }
        for s in self.sequences_in_order() {
            let text = self.av_script(Some(s));
            if !text.is_empty() {
                out.push((Some(s), text));
            }
        }
        out
    }

    /// **Set a section's script.** Ties re-anchor by their words; the ones
    /// whose words are gone are untied. Returns `(kept, lost)`. One step.
    pub fn set_av_script(&mut self, section: Option<Id>, text: &str) -> (usize, usize) {
        let Some(holder) = self.script_holder(section) else {
            return (0, 0);
        };
        let old = self.av_script(section);
        let tx = self.begin("Edit script");
        self.set(holder, AV_SCRIPT, text);
        let (mut kept, mut lost) = (0, 0);
        for shot in self.shots_quoting(section) {
            let mut moved = Vec::new();
            let mut had = 0;
            for (from, to) in self.spans_of(shot) {
                let words = utf16_slice(&old, from, to);
                if words.trim().is_empty() {
                    continue;
                }
                had += 1;
                let finds = utf16_finds(text, &words);
                if let Some(at) = finds.iter().min_by_key(|at| (**at as i64 - from as i64).abs()) {
                    moved.push((*at, *at + utf16_len(&words)));
                }
            }
            if had == 0 {
                continue;
            }
            if moved.is_empty() {
                self.clear_quote(shot);
                lost += 1;
            } else {
                self.write_spans(shot, section, text, moved);
                kept += 1;
            }
        }
        self.end(tx);
        (kept, lost)
    }

    /// Is this section's script (the film's, for `None`) an AV script?
    pub fn script_is_av(&self, section: Option<Id>) -> bool {
        is_av(&self.av_script(section))
    }

    /// **Make a script Plain or AV.** The words stay and every tie follows
    /// them (`set_av_script`); only the layout changes. A section with no
    /// script yet becomes an empty AV script, ready for rows. One step.
    pub fn set_script_av(&mut self, section: Option<Id>, av: bool) -> (usize, usize) {
        let had = self.av_script(section);
        if is_av(&had) == av {
            return (0, 0);
        }
        let now = if av { av_from_plain(&had) } else { plain_from_av(&had) };
        self.set_av_script(section, &now)
    }

    /// **Add to the end of a script** — a paste. The script keeps the
    /// layout it has; one with nothing yet takes `av` (else the paste's
    /// own). What arrives is laid out to match. Returns `(kept, lost)`.
    pub fn add_to_script(&mut self, section: Option<Id>, text: &str, av: Option<bool>) -> (usize, usize) {
        let had = self.av_script(section);
        let empty = av_rows(&had).iter().all(|(v, a)| v.trim().is_empty() && a.trim().is_empty());
        let as_av = if empty { av.unwrap_or(is_av(text)) } else { is_av(&had) };
        let whole = if as_av {
            let incoming = av_from_plain(text);
            if empty { incoming } else { format!("{had}{AV_ROW}{incoming}") }
        } else {
            let incoming = plain_from_av(text);
            if empty { incoming } else { format!("{had}\n\n{incoming}") }
        };
        self.set_av_script(section, &whole)
    }

    /// The stretch a shot quotes, if any.
    pub fn quote_of(&self, shot: Id) -> Option<Quote> {
        let r = self.get(shot)?;
        let from = r.get(SCRIPT_FROM)?.as_int()? as usize;
        let to = r.get(SCRIPT_TO)?.as_int()? as usize;
        if to <= from {
            return None;
        }
        let section = r.ref_id(SCRIPT_OF).filter(|s| self.get(*s).is_some());
        Some(Quote { section, from, to })
    }

    /// **Every stretch a shot quotes**, in order, the first one first. Empty
    /// when it quotes nothing.
    pub fn spans_of(&self, shot: Id) -> Vec<(usize, usize)> {
        let Some(q) = self.quote_of(shot) else { return Vec::new() };
        let mut out = vec![(q.from, q.to)];
        let more = self.get(shot).and_then(|r| r.get(SCRIPT_MORE)).and_then(|v| v.as_list()).unwrap_or(&[]);
        for pair in more.chunks(2) {
            if let [a, b] = pair {
                if let (Some(a), Some(b)) = (a.as_int(), b.as_int()) {
                    if b > a && a >= 0 {
                        out.push((a as usize, b as usize));
                    }
                }
            }
        }
        out.sort();
        out
    }

    /// The words a shot quotes — read off the script every time. Several
    /// stretches are joined by an ellipsis, in script order.
    pub fn shot_excerpt(&self, shot: Id) -> String {
        let Some(q) = self.quote_of(shot) else { return String::new() };
        let text = self.av_script(q.section);
        self.spans_of(shot)
            .into_iter()
            .map(|(from, to)| readable(&utf16_slice(&text, from, to)).trim().to_string())
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join(" … ")
    }

    /// **Tie a shot to a stretch of a script**, in place of whatever it
    /// quoted. An empty or backwards range unties. One step.
    pub fn tie_shot(&mut self, shot: Id, section: Option<Id>, from: usize, to: usize) {
        let tx = self.begin("Tie shot");
        if to <= from {
            self.clear_quote(shot);
        } else {
            let text = self.av_script(section);
            self.write_spans(shot, section, &text, vec![(from, to)]);
        }
        self.end(tx);
    }

    /// **Add a stretch to the ones a shot already quotes.** A stretch in a
    /// different script than the shot's takes the place of what it had —
    /// a shot quotes one script. Touching or overlapping stretches join.
    /// One step.
    pub fn add_tie(&mut self, shot: Id, section: Option<Id>, from: usize, to: usize) {
        if to <= from {
            return;
        }
        let tx = self.begin("Tie shot");
        let mut spans = self.spans_in(shot, section);
        spans.push((from, to));
        let text = self.av_script(section);
        self.write_spans(shot, section, &text, spans);
        self.end(tx);
    }

    /// **Let go of part of what a shot quotes** — the range comes out of
    /// any stretch it crosses, which can split one in two. One step.
    pub fn untie_range(&mut self, shot: Id, from: usize, to: usize) {
        let Some(q) = self.quote_of(shot) else { return };
        if to <= from {
            return;
        }
        let tx = self.begin("Untie shot");
        let mut left = Vec::new();
        for (a, b) in self.spans_of(shot) {
            if b <= from || a >= to {
                left.push((a, b));
                continue;
            }
            if a < from {
                left.push((a, from));
            }
            if b > to {
                left.push((to, b));
            }
        }
        let text = self.av_script(q.section);
        self.write_spans(shot, q.section, &text, left);
        self.end(tx);
    }

    /// **The highlighter's gesture**: a selection the shot already holds,
    /// every word of it, is let go; anything else is added. True when it
    /// added. One step.
    pub fn toggle_tie(&mut self, shot: Id, section: Option<Id>, from: usize, to: usize) -> bool {
        self.toggle_ties(shot, section, &[(from, to)])
    }

    /// The same for a selection in several pieces — a drag down one column
    /// of an AV script is one piece per row (his ask, 2026-10-05: *"select
    /// audio only or video only lines"*). All held: all let go; else all
    /// added. One step either way.
    pub fn toggle_ties(&mut self, shot: Id, section: Option<Id>, ranges: &[(usize, usize)]) -> bool {
        let ranges: Vec<(usize, usize)> = ranges.iter().copied().filter(|(a, b)| b > a).collect();
        if ranges.is_empty() {
            return false;
        }
        let spans = self.spans_in(shot, section);
        let text = self.av_script(section);
        let units: Vec<u16> = text.encode_utf16().collect();
        let held = |at: usize| spans.iter().any(|(a, b)| *a <= at && at < *b);
        let words = ranges
            .iter()
            .flat_map(|(from, to)| *from..(*to).min(units.len()))
            .filter(|at| !is_blank_unit(units[*at]))
            .collect::<Vec<_>>();
        let letting_go = !spans.is_empty() && !words.is_empty() && words.iter().all(|at| held(*at));
        let tx = self.begin(if letting_go { "Untie shot" } else { "Tie shot" });
        for (from, to) in &ranges {
            if letting_go {
                self.untie_range(shot, *from, *to);
            } else {
                self.add_tie(shot, section, *from, *to);
            }
        }
        self.end(tx);
        !letting_go
    }

    /// **Let go of the stretch under a click.** False when the click is
    /// not on one of the shot's stretches. One step.
    pub fn untie_at(&mut self, shot: Id, at: usize) -> bool {
        let Some(&(from, to)) = self.spans_of(shot).iter().find(|(a, b)| *a <= at && at < *b) else {
            return false;
        };
        self.untie_range(shot, from, to);
        true
    }

    /// The shot's stretches when they are in this script; none otherwise.
    fn spans_in(&self, shot: Id, section: Option<Id>) -> Vec<(usize, usize)> {
        match self.quote_of(shot) {
            Some(q) if q.section == section => self.spans_of(shot),
            _ => Vec::new(),
        }
    }

    /// Write a shot's stretches: sorted, joined where they touch, trimmed of
    /// blank ends, the ones that are only blanks dropped. None left unties.
    fn write_spans(&mut self, shot: Id, section: Option<Id>, text: &str, spans: Vec<(usize, usize)>) {
        let units: Vec<u16> = text.encode_utf16().collect();
        let mut clean: Vec<(usize, usize)> = Vec::new();
        let mut sorted: Vec<(usize, usize)> = spans.into_iter().filter(|(a, b)| b > a).collect();
        sorted.sort();
        for (a, b) in sorted {
            match clean.last_mut() {
                Some(last) if a <= last.1 => last.1 = last.1.max(b),
                _ => clean.push((a, b)),
            }
        }
        // Blank ends off, so a drag that ran into the gutter does not keep
        // the line break it caught — unless the script is not known (no
        // text), when the ranges stand as given.
        if !units.is_empty() {
            clean = clean
                .into_iter()
                .filter_map(|(mut a, mut b)| {
                    b = b.min(units.len());
                    while a < b && is_blank_unit(units[a]) {
                        a += 1;
                    }
                    while b > a && is_blank_unit(units[b - 1]) {
                        b -= 1;
                    }
                    (b > a).then_some((a, b))
                })
                .collect();
        }
        let Some(&(from, to)) = clean.first() else {
            self.clear_quote(shot);
            return;
        };
        match section {
            Some(s) => self.set(shot, SCRIPT_OF, s),
            None => self.set(shot, SCRIPT_OF, Value::Null),
        }
        self.set(shot, SCRIPT_FROM, Value::Int(from as i64));
        self.set(shot, SCRIPT_TO, Value::Int(to as i64));
        if clean.len() > 1 {
            let more = clean[1..].iter().flat_map(|(a, b)| [Value::Int(*a as i64), Value::Int(*b as i64)]).collect();
            self.set(shot, SCRIPT_MORE, Value::List(more));
        } else if self.get(shot).and_then(|r| r.get(SCRIPT_MORE)).is_some() {
            self.set(shot, SCRIPT_MORE, Value::Null);
        }
    }

    /// Tie a shot to the first place these words appear in a script — the
    /// MCP's door, given the text rather than offsets. False when the words
    /// are not there.
    pub fn tie_shot_to_words(&mut self, shot: Id, section: Option<Id>, words: &str) -> bool {
        self.tie_words(shot, section, words, false)
    }

    /// The same, `add`ing the words to what the shot already quotes rather
    /// than in its place.
    pub fn tie_words(&mut self, shot: Id, section: Option<Id>, words: &str, add: bool) -> bool {
        let text = self.av_script(section);
        let words = words.trim();
        let Some(at) = utf16_finds(&text, words).first().copied() else {
            return false;
        };
        if add {
            self.add_tie(shot, section, at, at + utf16_len(words));
        } else {
            self.tie_shot(shot, section, at, at + utf16_len(words));
        }
        true
    }

    /// Let go of these words from what a shot quotes — the place they
    /// appear inside one of its stretches. False when it holds no such words.
    pub fn untie_words(&mut self, shot: Id, words: &str) -> bool {
        let Some(q) = self.quote_of(shot) else { return false };
        let text = self.av_script(q.section);
        let words = words.trim();
        let len = utf16_len(words);
        let spans = self.spans_of(shot);
        let Some(at) = utf16_finds(&text, words)
            .into_iter()
            .find(|at| spans.iter().any(|(a, b)| *a < at + len && *at < *b))
        else {
            return false;
        };
        self.untie_range(shot, at, at + len);
        true
    }

    fn clear_quote(&mut self, shot: Id) {
        self.set(shot, SCRIPT_OF, Value::Null);
        self.set(shot, SCRIPT_FROM, Value::Null);
        self.set(shot, SCRIPT_TO, Value::Null);
        if self.get(shot).and_then(|r| r.get(SCRIPT_MORE)).is_some() {
            self.set(shot, SCRIPT_MORE, Value::Null);
        }
    }

    /// Every shot quoting this script, in story order.
    pub fn shots_quoting(&self, section: Option<Id>) -> Vec<Id> {
        let mut seen = Vec::new();
        for placement in self.all_placements() {
            let Some(shot) = self.get(placement).and_then(|r| r.ref_id(f::SHOT)) else { continue };
            if seen.contains(&shot) {
                continue;
            }
            if let Some(q) = self.quote_of(shot) {
                if q.section == section {
                    seen.push(shot);
                }
            }
        }
        seen
    }

    /// **Tonight's beats become scripts, once.** Each section's (and the
    /// film's) beats are joined by blank lines into its text; a shot tied to
    /// a beat quotes that beat's words; the beats go. Returns how many
    /// scripts were written. Nothing to do on a film without beats.
    pub fn adopt_beats_as_script(&mut self) -> usize {
        let beats = self.store().of_kind(&Kind::Beat);
        if beats.is_empty() {
            return 0;
        }
        let mut holders: Vec<Option<Id>> = vec![None];
        holders.extend(self.sequences_in_order().into_iter().map(Some));
        let tx = self.begin("Adopt script");
        let mut written = 0;
        for section in holders {
            let beats = self.beats_in_section(section);
            if beats.is_empty() {
                continue;
            }
            let mut text = self.av_script(section);
            let mut ranges: Vec<(Id, usize, usize)> = Vec::new();
            for beat in &beats {
                let mut words = String::new();
                let label = self.beat_label(*beat);
                let video = self.beat_video(*beat);
                let audio = self.beat_audio(*beat);
                if !label.is_empty() {
                    words.push_str(&label);
                }
                for part in [video, audio] {
                    if part.trim().is_empty() {
                        continue;
                    }
                    if !words.is_empty() {
                        words.push('\n');
                    }
                    words.push_str(part.trim());
                }
                if words.is_empty() {
                    continue;
                }
                if !text.is_empty() {
                    text.push_str("\n\n");
                }
                let from = utf16_len(&text);
                text.push_str(&words);
                ranges.push((*beat, from, utf16_len(&text)));
            }
            let Some(holder) = self.script_holder(section) else { continue };
            self.set(holder, AV_SCRIPT, text.as_str());
            written += 1;
            for (beat, from, to) in &ranges {
                for shot in self.shots_on_beat(*beat) {
                    match section {
                        Some(s) => self.set(shot, SCRIPT_OF, s),
                        None => self.set(shot, SCRIPT_OF, Value::Null),
                    }
                    self.set(shot, SCRIPT_FROM, Value::Int(*from as i64));
                    self.set(shot, SCRIPT_TO, Value::Int(*to as i64));
                }
            }
            for beat in beats {
                self.delete_beat(beat);
            }
        }
        self.end(tx);
        written
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kind::Kind as FilmKind;
    use crate::stamp::DeviceId;

    fn commercial() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("HLA");
        d.set_kind(FilmKind::Commercial);
        d.clear_history();
        d
    }

    #[test]
    fn a_shot_quotes_a_stretch_of_the_script_and_the_tie_survives_an_edit() {
        let mut d = commercial();
        let t = d.create_sequence("HLA");
        let text = "“Thank you Denis for the opportunity.”\n\nDirecting has been a labour of love.\n\nWhat you’re about to see is a car chase.";
        d.set_av_script(Some(t), text);
        let scene = d.create_scene_titled("Lobby");
        let (a, _) = d.add_shot_to_scene(scene);
        let (b, _) = d.add_shot_to_scene(scene);
        let (c, _) = d.add_shot_to_scene(scene);

        assert!(d.tie_shot_to_words(a, Some(t), "Thank you Denis"));
        assert_eq!(d.shot_excerpt(a), "Thank you Denis");
        // Overlapping, and two shots on one stretch, are both fine.
        assert!(d.tie_shot_to_words(b, Some(t), "Denis for the opportunity"));
        assert!(d.tie_shot_to_words(c, Some(t), "Denis for the opportunity"));
        assert_eq!(d.shots_quoting(Some(t)), vec![a, b, c]);
        assert!(!d.tie_shot_to_words(c, Some(t), "not in the script"));

        // Words after a curly quote: the UTF-16 offsets hold.
        let q = d.quote_of(a).unwrap();
        assert_eq!(q.from, 1);
        assert_eq!(d.shot_excerpt(b), "Denis for the opportunity");

        // An edit above the quoted words moves them; the ties follow.
        let edited = "INTRO\n\n“Thank you Denis for the opportunity.”\n\nWhat you’re about to see is a car chase.";
        let (kept, lost) = d.set_av_script(Some(t), edited);
        assert_eq!((kept, lost), (3, 0));
        assert_eq!(d.shot_excerpt(a), "Thank you Denis");
        assert_eq!(d.quote_of(a).unwrap().from, 8);

        // Words struck out untie their shot and say so.
        let (kept, lost) = d.set_av_script(Some(t), "Something else entirely.");
        assert_eq!((kept, lost), (0, 3));
        assert_eq!(d.quote_of(a), None);
        d.undo();
        assert_eq!(d.shot_excerpt(a), "Thank you Denis");

        // Untie by an empty range.
        d.tie_shot(a, Some(t), 5, 5);
        assert_eq!(d.quote_of(a), None);
    }

    #[test]
    fn a_script_turns_av_and_back_and_its_ties_follow_the_words() {
        let mut d = commercial();
        let t = d.create_sequence("Spot A");
        d.set_av_script(Some(t), "VO: You remember your first.\n\nSFX: A shutter.");
        let scene = d.create_scene_titled("Kitchen");
        let (a, _) = d.add_shot_to_scene(scene);
        assert!(d.tie_shot_to_words(a, Some(t), "A shutter"));
        assert!(!d.script_is_av(Some(t)));

        // Plain to AV: a row per paragraph, all Audio, the tie still on its words.
        assert_eq!(d.set_script_av(Some(t), true), (1, 0));
        assert!(d.script_is_av(Some(t)));
        let rows = av_rows(&d.av_script(Some(t)));
        assert_eq!(rows, vec![
            (String::new(), "VO: You remember your first.".to_string()),
            (String::new(), "SFX: A shutter.".to_string()),
        ]);
        assert_eq!(d.shot_excerpt(a), "A shutter");

        // Writing the Video beside it keeps the tie; a tie in the Video works the same.
        let text = av_text(&[
            ("Open on a Polaroid.".into(), "VO: You remember your first.".into()),
            ("Hands. The flash.".into(), "SFX: A shutter.".into()),
        ]);
        assert_eq!(d.set_av_script(Some(t), &text), (1, 0));
        let (b, _) = d.add_shot_to_scene(scene);
        assert!(d.tie_shot_to_words(b, Some(t), "The flash"));
        assert_eq!(d.shot_excerpt(b), "The flash");
        // Offsets read the same in the readable text.
        let q = d.quote_of(b).unwrap();
        assert_eq!(utf16_slice(&readable(&d.av_script(Some(t))), q.from, q.to), "The flash");
        // A drag across the two cells reads as words, never the marks.
        let whole = d.av_script(Some(t));
        d.tie_shot(b, Some(t), 0, utf16_len(&whole));
        assert!(!d.shot_excerpt(b).contains(AV_CELL) && !d.shot_excerpt(b).contains(AV_ROW));

        // And back: every word stays, Video before Audio.
        d.set_script_av(Some(t), false);
        assert_eq!(
            d.av_script(Some(t)),
            "Open on a Polaroid.\nVO: You remember your first.\n\nHands. The flash.\nSFX: A shutter."
        );
        assert_eq!(d.shot_excerpt(a), "A shutter");
        d.undo();
        assert!(d.script_is_av(Some(t)));
    }

    #[test]
    fn a_pasted_table_becomes_av_rows_and_a_paste_keeps_the_scripts_layout() {
        let mut d = commercial();
        // An empty script asked for AV: the table's columns, label over Video.
        d.add_to_script(None, "VIDEO\tAUDIO\nOpen on black.\tMusic in.\nThe car.\tVO: Drive.", Some(true));
        assert_eq!(av_rows(&d.av_script(None)), vec![
            ("Open on black.".to_string(), "Music in.".to_string()),
            ("The car.".to_string(), "VO: Drive.".to_string()),
        ]);
        // More pasted on is laid out to match: paragraphs as Audio rows.
        d.add_to_script(None, "VO: The end.", None);
        assert_eq!(av_rows(&d.av_script(None)).len(), 3);
        assert_eq!(av_rows(&d.av_script(None))[2], (String::new(), "VO: The end.".to_string()));

        // An empty AV script is still AV, and a paste into it fills it.
        let t = d.create_sequence("B");
        d.set_script_av(Some(t), true);
        assert!(d.script_is_av(Some(t)));
        d.add_to_script(Some(t), "Hello.", None);
        assert_eq!(av_rows(&d.av_script(Some(t))), vec![(String::new(), "Hello.".to_string())]);

        // A plain script stays plain.
        let p = d.create_sequence("C");
        d.add_to_script(Some(p), "One.", Some(false));
        d.add_to_script(Some(p), "Two.", Some(true));
        assert_eq!(d.av_script(Some(p)), "One.\n\nTwo.");
    }

    #[test]
    fn a_shot_holds_several_stretches_and_lets_them_go_one_at_a_time() {
        let mut d = commercial();
        let text = av_text(&[
            ("Open on a Polaroid.".into(), "VO: You remember your first.".into()),
            ("Hands. The flash.".into(), "SFX: A shutter.".into()),
            ("The photo develops.".into(), "VO: Some things stay.".into()),
        ]);
        d.set_av_script(None, &text);
        let scene = d.create_scene_titled("Kitchen");
        let (a, _) = d.add_shot_to_scene(scene);
        let at = |w: &str| utf16_finds(&text, w)[0];
        let span = |w: &str| (at(w), at(w) + utf16_len(w));

        // Two lines far apart, added one after the other.
        let (f1, t1) = span("Open on a Polaroid.");
        let (f2, t2) = span("The photo develops.");
        assert!(d.toggle_tie(a, None, f1, t1));
        assert!(d.toggle_tie(a, None, f2, t2));
        assert_eq!(d.spans_of(a), vec![(f1, t1), (f2, t2)]);
        assert_eq!(d.shot_excerpt(a), "Open on a Polaroid. … The photo develops.");
        // The first stretch is where a one-stretch reader looks.
        assert_eq!(d.quote_of(a).map(|q| (q.from, q.to)), Some((f1, t1)));

        // Selecting the same words again lets them go; the other stays.
        assert!(!d.toggle_tie(a, None, f1, t1 + 1));
        assert_eq!(d.spans_of(a), vec![(f2, t2)]);
        assert_eq!(d.shot_excerpt(a), "The photo develops.");

        // A click on a stretch lets that one go.
        d.toggle_tie(a, None, f1, t1);
        assert!(d.untie_at(a, f2 + 3));
        assert_eq!(d.spans_of(a), vec![(f1, t1)]);
        assert!(!d.untie_at(a, f2 + 3));

        // A drag that half overlaps adds; touching stretches join.
        let (f3, t3) = span("VO: You remember your first.");
        d.add_tie(a, None, f3, t3);
        assert_eq!(d.spans_of(a), vec![(f1, t1), (f3, t3)]);
        d.add_tie(a, None, f1, t3);
        assert_eq!(d.spans_of(a), vec![(f1, t3)]);
        // A part from the middle splits it.
        let (fp, tp) = span("Polaroid");
        d.untie_range(a, fp, tp);
        assert_eq!(d.shot_excerpt(a), "Open on a … .\nVO: You remember your first.");

        // An edit above keeps every stretch on its words.
        let more = av_text(&[
            ("COLD OPEN".into(), "".into()),
            ("Open on a Polaroid.".into(), "VO: You remember your first.".into()),
            ("Hands. The flash.".into(), "SFX: A shutter.".into()),
            ("The photo develops.".into(), "VO: Some things stay.".into()),
        ]);
        d.toggle_tie(a, None, f2, t2);
        let before = d.shot_excerpt(a);
        assert_eq!(d.set_av_script(None, &more), (1, 0));
        assert_eq!(d.shot_excerpt(a), before);
        assert_eq!(d.spans_of(a).len(), 3);

        // A drag down the Video column: one piece per row, Video only.
        let now = |w: &str| {
            let at = utf16_finds(&more, w)[0];
            (at, at + utf16_len(w))
        };
        let (v1, _) = now("Open on a Polaroid.");
        let (_, v2) = now("Hands. The flash.");
        let (c, _) = d.add_shot_to_scene(scene);
        let video = [now("Open on a Polaroid."), now("Hands. The flash.")];
        assert!(d.toggle_ties(c, None, &video));
        assert_eq!(d.shot_excerpt(c), "Open on a Polaroid. … Hands. The flash.");
        assert!(v2 > v1);
        // The same drag again lets both go, in one undo.
        assert!(!d.toggle_ties(c, None, &video));
        assert_eq!(d.shot_excerpt(c), "");
        d.undo();
        assert_eq!(d.spans_of(c).len(), 2);

        // Words: add, and let go.
        let (b, _) = d.add_shot_to_scene(scene);
        assert!(d.tie_words(b, None, "Hands.", false));
        assert!(d.tie_words(b, None, "Some things stay.", true));
        assert_eq!(d.shot_excerpt(b), "Hands. … Some things stay.");
        assert!(d.untie_words(b, "Hands."));
        assert_eq!(d.shot_excerpt(b), "Some things stay.");
        assert!(!d.untie_words(b, "Hands."));
        // Tie in place of everything, then untie all.
        assert!(d.tie_words(b, None, "A shutter", false));
        assert_eq!(d.spans_of(b).len(), 1);
        d.tie_shot(b, None, 0, 0);
        assert!(d.spans_of(b).is_empty());
        assert_eq!(d.shot_excerpt(b), "");
        // One undo per gesture.
        d.undo();
        assert_eq!(d.shot_excerpt(b), "A shutter");
    }

    #[test]
    fn tonights_beats_become_the_sections_script_once() {
        let mut d = commercial();
        let t = d.create_sequence("HLA");
        let one = d.create_beat("", "", "Thank you Denis.", Some(t));
        let two = d.create_beat("OPEN", "The lobby.", "Music in.", Some(t));
        let loose = d.create_beat("", "", "A loose line.", None);
        let scene = d.create_scene_titled("Lobby");
        let (a, _) = d.add_shot_to_scene(scene);
        let (b, _) = d.add_shot_to_scene(scene);
        d.set_shot_beat(a, Some(one));
        d.set_shot_beat(b, Some(two));
        let _ = loose;

        assert_eq!(d.adopt_beats_as_script(), 2);
        assert_eq!(d.av_script(Some(t)), "Thank you Denis.\n\nOPEN\nThe lobby.\nMusic in.");
        assert_eq!(d.av_script(None), "A loose line.");
        assert_eq!(d.shot_excerpt(a), "Thank you Denis.");
        assert_eq!(d.shot_excerpt(b), "OPEN\nThe lobby.\nMusic in.");
        assert!(d.beats_in_order().is_empty());
        assert_eq!(d.adopt_beats_as_script(), 0);
    }
}
