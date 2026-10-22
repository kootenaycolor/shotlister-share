//! **An AV script, pasted in.**
//!
//! A commercial's script, when it has one, is usually a two-column table —
//! VIDEO beside AUDIO, one row per beat, no sluglines — living in a Google
//! Doc or a Word file. Copying that table puts tab-separated text on the
//! clipboard, one row per line, cells that hold more than one paragraph
//! wrapped in double quotes. This reads that text into rows, and applies the
//! rows to a film as scenes.
//!
//! ## What a row becomes
//!
//! - Three or more cells: the first is the row's **label**, then Video, then
//!   Audio (anything past the third cell is folded into Audio, because a
//!   fourth column is usually notes about the sound).
//! - Two cells: Video and Audio; no label.
//! - One cell: Video.
//!
//! A label that is only a number — `1`, `2.`, `04` — is a **row number, not a
//! title**, and is dropped: the scene's number is ours, and a title of `3`
//! would be worse than no title. A header row (`VIDEO`, `AUDIO`, `#`, `SHOT`,
//! `SCENE`) is skipped.
//!
//! ## Not every commercial script is a table
//!
//! His note, 2026-09-14: *"not all commercial scripts are AV - keep that in
//! mind."* A treatment is paragraphs. A director's list is numbered beats.
//! An agency doc is headed blocks — `PARTY MONTAGE` on its own line, then
//! what happens. `read_any` takes all of them and the AV table too, and
//! decides by the text's own shape, never by asking:
//!
//! - **Any tab** in the text: it is a table, read as above.
//! - **Numbered lines** — `1.`, `2)`, `03`, `Scene 4:`, `SHOT 4 —` — start a
//!   beat each; the lines under one belong to it. The number is dropped
//!   (ours to give); the rest of that line is the title if it is short and
//!   headline-shaped, else the first line of the video.
//! - **Otherwise blank lines** split beats. A beat whose first line is short
//!   (under sixty characters), has no full stop at the end and is either
//!   ALL CAPS, ends in `:` or `—`, or stands over further lines, has that
//!   line as its title.
//! - A line beginning `VO:`, `V.O.`, `AUDIO:`, `SFX:`, `MUSIC:`, `SOUND:`
//!   or `SUPER:` goes to **audio**, whichever form the script is in. The
//!   label stays on the line — `VO: "You remember your first."` reads as it
//!   was written.
//!
//! ## Report, never invent — and never destroy
//!
//! Applying rows **matches before it makes**. A row whose label equals an
//! existing scene's title (case-insensitive, trimmed) updates that scene's
//! Video and Audio and makes nothing. A row with no label matches a scene
//! whose Video already says exactly the same thing, so pasting the same
//! script twice makes no duplicates. Everything else becomes a new scene at
//! the end of the list, in the order the table had. **Nothing is ever
//! removed** — a scene the new paste no longer mentions is a fact for a
//! person to act on, and the report says how many there are.
//!
//! ## One job, several scripts
//!
//! His ask, 2026-09-19: *"I have multiple scripts with different alts that
//! I need to account for, and I want to be able to make the shotlist for all
//! three of them… I need a way to integrate multiple scripts."* Three spots
//! on one job share the days and the crew, so they are one project — and a
//! project already has **sections** (a sequence, in a commercial's words) to
//! label a run of scenes. So a paste can name the section it belongs to:
//!
//! - **Matching stays inside the section.** Three spots will all have an
//!   `OPEN` and a `TAG`; without this, the second script's `OPEN` would
//!   overwrite the first's instead of becoming its own scene.
//! - **A new scene joins the section**, and lands after the section's last
//!   scene rather than at the end of the whole list — so pasting a revised
//!   script A after B and C are in keeps A's scenes together.
//! - **Unmentioned is counted inside the section too.** B's paste has no
//!   opinion about A's scenes.
//!
//! A paste with no section is exactly what it was: the whole list.

use crate::doc::{f, Doc};
use crate::id::Id;

/// One row of the table, as read.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Row {
    pub label: String,
    pub video: String,
    pub audio: String,
}

/// What applying a paste did.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Report {
    /// Rows the text held, after headers and blanks were dropped.
    pub read: usize,
    /// Scenes that already existed and were updated in place.
    pub matched: usize,
    /// Scenes made new.
    pub made: usize,
    /// Beats the section has that no row mentioned. Never touched by a
    /// paste; reported so a person can decide.
    pub unmentioned: usize,
    /// Beats an *edit* removed — `replace_av_script_in` only.
    pub removed: usize,
}

/// Tab-separated rows, quoted cells and all, into `Row`s.
pub fn read(text: &str) -> Vec<Row> {
    cells_of(text)
        .into_iter()
        .filter(|cells| cells.iter().any(|c| !c.trim().is_empty()))
        .filter(|cells| !is_header(cells))
        .map(|cells| {
            let mut cells: Vec<String> = cells.into_iter().map(|c| tidy(&c)).collect();
            match cells.len() {
                0 => Row::default(),
                1 => Row { video: cells.remove(0), ..Row::default() },
                2 => {
                    let audio = cells.remove(1);
                    Row { video: cells.remove(0), audio, ..Row::default() }
                }
                _ => {
                    let label = cells.remove(0);
                    let video = cells.remove(0);
                    let audio = cells
                        .into_iter()
                        .filter(|c| !c.is_empty())
                        .collect::<Vec<_>>()
                        .join("\n");
                    let label = if is_row_number(&label) { String::new() } else { label };
                    Row { label, video, audio }
                }
            }
        })
        .filter(|row| !(row.label.is_empty() && row.video.is_empty() && row.audio.is_empty()))
        .collect()
}

/// Which shape the text turned out to be, so the sheet can say so.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shape {
    /// Tab-separated cells — an AV table.
    Table,
    /// Lines that start with a number, each a beat.
    Numbered,
    /// Blocks split by blank lines.
    Blocks,
}

impl Shape {
    pub fn as_str(self) -> &'static str {
        match self {
            Shape::Table => "table",
            Shape::Numbered => "numbered",
            Shape::Blocks => "blocks",
        }
    }
}

/// **Any commercial script**, by its own shape — see the module head.
/// **An audio-only script.** His case, 2026-09-19: *"I'm literally just
/// going to paste an audio script."* Read plainly, a paragraph is video; here
/// every row with nothing in its audio column has its words moved there.
pub fn as_audio_only(rows: Vec<Row>) -> Vec<Row> {
    rows.into_iter()
        .map(|mut r| {
            if r.audio.trim().is_empty() && !r.video.trim().is_empty() {
                r.audio = std::mem::take(&mut r.video);
            }
            r
        })
        .collect()
}

pub fn read_any(text: &str) -> (Shape, Vec<Row>) {
    if text.contains('\t') {
        return (Shape::Table, read(text));
    }
    let lines: Vec<&str> = text.lines().collect();
    let numbered = lines.iter().filter(|l| number_prefix(l).is_some()).count();
    if numbered >= 2 {
        return (Shape::Numbered, read_numbered(&lines));
    }
    (Shape::Blocks, read_blocks(&lines))
}

/// `1. Hero opens the box` → the rest after the number, when a line starts
/// with one: `1.`, `2)`, `3:`, `4 —`, `Scene 4`, `SHOT 4:`, `01 …`.
///
/// A bare number with only a space after it is a count, not a beat — *300
/// people fill the square* — unless it is written with a leading zero
/// (`01 Hero…`, a director's-list habit) or a word says it is one (`Scene 4
/// Photo develops`). `4K` and `3D` are words.
fn number_prefix(line: &str) -> Option<&str> {
    let line = line.trim_start();
    let mut rest = line;
    let mut worded = false;
    for word in ["scene", "shot", "beat", "sc"] {
        // **Never slice a line by byte count.** A line opening with a curly
        // quote — three bytes — split inside the character and the whole
        // app died on Save (his crash, 2026-09-19). Compare on a boundary
        // or not at all.
        if rest.len() > word.len()
            && rest.is_char_boundary(word.len())
            && rest[..word.len()].eq_ignore_ascii_case(word)
        {
            let after = &rest[word.len()..];
            if after.starts_with(' ') || after.starts_with('.') {
                rest = after.trim_start_matches('.').trim_start();
                worded = true;
                break;
            }
        }
    }
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() || digits.len() > 3 {
        return None;
    }
    let after = &rest[digits.len()..];
    let mut chars = after.chars();
    match chars.next() {
        None => Some(""),
        Some(c) if c.is_ascii_alphabetic() => None,
        Some('.') | Some(')') | Some(':') | Some('—') | Some('–') | Some('-') => {
            Some(chars.as_str().trim())
        }
        Some(' ') => {
            let leading_zero = digits.len() == 2 && digits.starts_with('0');
            if worded || leading_zero {
                Some(after.trim())
            } else {
                None
            }
        }
        Some(_) => None,
    }
}

fn is_audio_line(line: &str) -> bool {
    let l = line.trim_start().to_ascii_lowercase();
    ["vo:", "v.o.", "v/o", "audio:", "sfx:", "music:", "sound:", "super:", "narrator:", "voice over:", "voiceover:"]
        .iter()
        .any(|p| l.starts_with(p))
}

/// Short, no full stop, and shaped like a headline: all caps, or ending in
/// a colon or dash, or standing over more lines.
fn is_title_line(line: &str, has_more: bool) -> bool {
    let t = line.trim();
    if t.is_empty() || t.chars().count() > 60 || t.ends_with('.') || t.ends_with('!') || t.ends_with('?') {
        return false;
    }
    let letters: Vec<char> = t.chars().filter(|c| c.is_alphabetic()).collect();
    let all_caps = !letters.is_empty() && letters.iter().all(|c| c.is_uppercase());
    all_caps || t.ends_with(':') || t.ends_with('—') || t.ends_with('–') || has_more
}

/// `AUDIO:` is a marker, not a word of the script — the editor writes it in
/// front of a heard line so the reader knows, and it comes off again here.
/// `VO:`, `SFX:` and the rest are the script's own and stay.
fn unmarked(line: &str) -> &str {
    let lower = line.to_ascii_lowercase();
    if lower.starts_with("audio:") {
        line["audio:".len()..].trim_start()
    } else {
        line
    }
}

/// Lines into a paragraph: a blank line is a paragraph break, kept (a beat
/// of three paragraphs stays three — the numbered form the editor writes
/// relies on it); runs of blanks are one break; leading and trailing blanks
/// go.
fn paragraphs(lines: &[&str]) -> String {
    let mut out = String::new();
    let mut pending_break = false;
    for line in lines {
        if line.is_empty() {
            pending_break = !out.is_empty();
            continue;
        }
        if !out.is_empty() {
            out.push_str(if pending_break { "\n\n" } else { "\n" });
        }
        pending_break = false;
        out.push_str(line);
    }
    out
}

fn beat_from(first: &str, rest: &[&str], first_may_be_title: bool) -> Row {
    let rest: Vec<&str> = rest.iter().map(|l| l.trim()).collect();
    let has_more = rest.iter().any(|l| !l.is_empty());
    let mut row = Row::default();
    let mut body: Vec<&str> = Vec::new();
    let mut heard: Vec<&str> = Vec::new();
    let first = first.trim();
    if !first.is_empty() {
        if is_audio_line(first) {
            heard.push(unmarked(first));
        } else if first_may_be_title && is_title_line(first, has_more) {
            row.label = first.trim_end_matches([':', '—', '–']).trim().to_string();
        } else {
            body.push(first);
        }
    }
    for line in rest {
        if line.is_empty() {
            // A blank line breaks whichever paragraph is being written.
            if !heard.is_empty() && (body.is_empty() || heard.last() != Some(&"")) {
                heard.push("");
            }
            if !body.is_empty() {
                body.push("");
            }
        } else if is_audio_line(line) {
            heard.push(unmarked(line));
        } else {
            body.push(line);
        }
    }
    row.video = paragraphs(&body);
    row.audio = paragraphs(&heard);
    row
}

fn read_numbered(lines: &[&str]) -> Vec<Row> {
    let mut rows = Vec::new();
    let mut current: Option<(String, Vec<&str>)> = None;
    for line in lines {
        if let Some(after) = number_prefix(line) {
            if let Some((first, rest)) = current.take() {
                rows.push(beat_from(&first, &rest, true));
            }
            current = Some((after.to_string(), Vec::new()));
        } else if let Some((_, rest)) = current.as_mut() {
            rest.push(line);
        }
        // Lines before the first number are a heading or a note, not a beat.
    }
    if let Some((first, rest)) = current.take() {
        rows.push(beat_from(&first, &rest, true));
    }
    rows.into_iter().filter(|r| !(r.label.is_empty() && r.video.is_empty() && r.audio.is_empty())).collect()
}

fn read_blocks(lines: &[&str]) -> Vec<Row> {
    let mut rows = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    let mut flush = |block: &mut Vec<&str>| {
        if block.is_empty() {
            return;
        }
        let first = block[0];
        let row = beat_from(first, &block[1..], true);
        if !(row.label.is_empty() && row.video.is_empty() && row.audio.is_empty()) {
            rows.push(row);
        }
        block.clear();
    };
    for line in lines {
        if line.trim().is_empty() {
            flush(&mut block);
        } else {
            block.push(line);
        }
    }
    flush(&mut block);
    rows
}

/// A cell's text, with the quoting the clipboard adds taken back off and
/// the ends trimmed. Paragraph breaks inside a cell survive.
fn tidy(cell: &str) -> String {
    cell.replace("\r\n", "\n").replace('\r', "\n").trim().to_string()
}

fn is_header(cells: &[String]) -> bool {
    const WORDS: [&str; 8] = ["video", "audio", "#", "shot", "scene", "vo", "visual", "sound"];
    let named = cells
        .iter()
        .map(|c| c.trim().trim_end_matches(':').to_ascii_lowercase())
        .filter(|c| !c.is_empty())
        .collect::<Vec<_>>();
    !named.is_empty() && named.iter().all(|c| WORDS.contains(&c.as_str()))
}

fn is_row_number(label: &str) -> bool {
    let bare = label.trim().trim_end_matches(['.', ')', ':']);
    !bare.is_empty() && bare.chars().all(|c| c.is_ascii_digit())
}

/// Split clipboard text into rows of cells. Handles the one thing plain
/// `split('\t')` cannot: a cell wrapped in double quotes because it holds a
/// newline or a tab, with `""` standing for a quote inside it.
fn cells_of(text: &str) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut row = Vec::new();
    let mut cell = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    cell.push('"');
                } else {
                    quoted = false;
                }
            } else {
                cell.push(c);
            }
            continue;
        }
        match c {
            '"' if cell.is_empty() => quoted = true,
            '\t' => row.push(std::mem::take(&mut cell)),
            '\n' | '\r' => {
                if c == '\r' && chars.peek() == Some(&'\n') {
                    chars.next();
                }
                row.push(std::mem::take(&mut cell));
                rows.push(std::mem::take(&mut row));
            }
            _ => cell.push(c),
        }
    }
    if !cell.is_empty() || !row.is_empty() {
        row.push(cell);
        rows.push(row);
    }
    rows
}

impl Doc {
    /// **Apply pasted rows to the film as beats.** One transaction — one
    /// paste is one gesture, and ⌘Z takes back the whole of it. See the
    /// module head for what matches and what is made.
    ///
    /// **Beats, not scenes, since 2026-09-19** — his ruling: the AV script
    /// is shot-level; a scene is a place or a setup a person makes. A row
    /// whose label equals a beat's in the section updates it; a row with no
    /// label matches a beat saying exactly the same video; the rest are new
    /// beats at the end of the section's run. Nothing is ever removed.
    pub fn apply_av_script(&mut self, rows: &[Row]) -> Report {
        self.apply_av_script_in(rows, None)
    }

    pub fn apply_av_script_in(&mut self, rows: &[Row], section: Option<Id>) -> Report {
        let mut report = Report { read: rows.len(), ..Report::default() };
        if rows.is_empty() {
            report.unmentioned = self.beats_in_section(section).len();
            return report;
        }
        let tx = self.begin("Paste script");
        let mut mentioned: Vec<Id> = Vec::new();
        for row in rows {
            let found = self.match_av_row(row, section, &mentioned);
            let beat = match found {
                Some(id) => {
                    report.matched += 1;
                    self.set(id, f::SCRIPT, row.video.as_str());
                    self.set(id, f::AUDIO, row.audio.as_str());
                    id
                }
                None => {
                    report.made += 1;
                    self.create_beat(&row.label, &row.video, &row.audio, section)
                }
            };
            mentioned.push(beat);
        }
        self.end(tx);
        report.unmentioned = self
            .beats_in_section(section)
            .into_iter()
            .filter(|id| !mentioned.contains(id))
            .count();
        report
    }

    /// **The section's script, replaced by this text** — a person editing
    /// the script itself (Project Settings → Script, 2026-09-19). Matched
    /// beats are updated, new ones made, and **beats the text no longer
    /// holds are deleted** (their shots untied): the person struck the line
    /// out, and keeping it would be inventing. One transaction.
    pub fn replace_av_script_in(&mut self, rows: &[Row], section: Option<Id>) -> Report {
        // The beats no row mentions, judged before anything is made — the
        // same matching the paste uses.
        let mut taken: Vec<Id> = Vec::new();
        for row in rows {
            if let Some(id) = self.match_av_row(row, section, &taken) {
                taken.push(id);
            }
        }
        let unmentioned: Vec<Id> = self
            .beats_in_section(section)
            .into_iter()
            .filter(|b| !taken.contains(b))
            .collect();
        let tx = self.begin("Edit script");
        let mut report = self.apply_av_script_in(rows, section);
        for b in &unmentioned {
            self.delete_beat(*b);
        }
        self.end(tx);
        report.unmentioned = 0;
        report.removed = unmentioned.len();
        report
    }

    /// **What a paste would do, without doing it** — for each row, the beat
    /// it would update, or nothing where it would make one. Same matching
    /// as `apply_av_script_in`, run dry, so the sheet's preview and the
    /// paste cannot disagree.
    pub fn plan_av_script(&self, rows: &[Row]) -> Vec<Option<Id>> {
        self.plan_av_script_in(rows, None)
    }

    pub fn plan_av_script_in(&self, rows: &[Row], section: Option<Id>) -> Vec<Option<Id>> {
        let mut taken: Vec<Id> = Vec::new();
        rows.iter()
            .map(|row| {
                let found = self.match_av_row(row, section, &taken);
                if let Some(id) = found {
                    taken.push(id);
                }
                found
            })
            .collect()
    }

    fn match_av_row(&self, row: &Row, section: Option<Id>, taken: &[Id]) -> Option<Id> {
        let beats: Vec<Id> = self
            .beats_in_section(section)
            .into_iter()
            .filter(|id| !taken.contains(id))
            .collect();
        if !row.label.is_empty() {
            let wanted = row.label.to_lowercase();
            return beats.iter().copied().find(|id| self.beat_label(*id).to_lowercase() == wanted);
        }
        // An unlabelled row is the same beat as one saying the same words —
        // its video when it has any, else its audio (an audio-only script
        // has nothing else to go on; before this an edit of one remade every
        // beat and untied every shot, 2026-09-19).
        let (video, audio) = (row.video.trim(), row.audio.trim());
        if video.is_empty() && audio.is_empty() {
            return None;
        }
        beats.iter().copied().find(|id| {
            self.beat_label(*id).is_empty()
                && if !video.is_empty() {
                    self.beat_video(*id).trim() == video
                } else {
                    self.beat_video(*id).trim().is_empty() && self.beat_audio(*id).trim() == audio
                }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kind::Kind;
    use crate::stamp::DeviceId;

    fn commercial() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Instant");
        d.set_kind(Kind::Commercial);
        d.clear_history();
        d
    }

    const PASTE: &str = "#\tVIDEO\tAUDIO\n\
        1\tMaya at the kitchen table, the box still sealed.\tVO: \"You remember your first.\"\n\
        2\t\"Maya lifts the camera.\nThe flash pops.\"\t\"VO: \"\"Some things are worth waiting for.\"\"\"\n\
        \n\
        3\tQuick cuts.\t\n";

    #[test]
    fn reads_headers_quotes_and_row_numbers() {
        let rows = read(PASTE);
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].label, "");
        assert_eq!(rows[0].video, "Maya at the kitchen table, the box still sealed.");
        assert_eq!(rows[0].audio, "VO: \"You remember your first.\"");
        assert_eq!(rows[1].video, "Maya lifts the camera.\nThe flash pops.");
        assert_eq!(rows[1].audio, "VO: \"Some things are worth waiting for.\"");
        assert_eq!(rows[2].video, "Quick cuts.");
        assert_eq!(rows[2].audio, "");
    }

    #[test]
    fn two_columns_are_video_and_audio_and_a_word_label_is_a_title() {
        let rows = read("Unboxing\tShe opens the box.\tMusic in.\nShe smiles.\tSting.");
        assert_eq!(rows[0].label, "Unboxing");
        assert_eq!(rows[1], Row { label: "".into(), video: "She smiles.".into(), audio: "Sting.".into() });
    }

    #[test]
    fn a_paste_makes_beats_in_order_and_a_second_paste_makes_none() {
        let mut d = commercial();
        let first = d.apply_av_script(&read(PASTE));
        assert_eq!(first, Report { read: 3, matched: 0, made: 3, unmentioned: 0, removed: 0 });
        let beats = d.beats_in_order();
        assert_eq!(beats.len(), 3);
        assert_eq!(d.beat_audio(beats[1]), "VO: \"Some things are worth waiting for.\"");
        assert_eq!(d.beat_video(beats[2]), "Quick cuts.");
        assert!(d.scenes_in_order().is_empty(), "a paste makes no scene");

        let again = d.apply_av_script(&read(PASTE));
        assert_eq!(again, Report { read: 3, matched: 3, made: 0, unmentioned: 0, removed: 0 });
        assert_eq!(d.beats_in_order().len(), 3);
    }

    #[test]
    fn a_labelled_row_updates_the_beat_with_that_label_and_never_removes() {
        let mut d = commercial();
        let kept = d.create_beat("Unboxing", "She opens the box.", "Music in.", None);
        let other = d.create_beat("End Card", "Logo.", "Sting.", None);
        let report = d.apply_av_script(&read(
            "unboxing\tShe tears the box open.\tMusic up.\nNew Beat\tA new thing.\t",
        ));
        assert_eq!(report, Report { read: 2, matched: 1, made: 1, unmentioned: 1, removed: 0 });
        assert_eq!(d.beat_video(kept), "She tears the box open.");
        assert_eq!(d.beat_audio(kept), "Music up.");
        assert_eq!(d.beat_video(other), "Logo.", "unmentioned, untouched");
        assert_eq!(d.beats_in_order().len(), 3);
    }


    #[test]
    fn a_numbered_list_is_beats_and_the_numbers_are_dropped() {
        let text = "INSTANT :30 — director's beats\n\n1. Hero Unboxes the Camera\nMaya at the kitchen table, the box still sealed.\nVO: \"You remember your first.\"\n2) First photo at the motel — the flash pops, she waves the print.\n3. PARTY MONTAGE\nQuick cuts.\nMusic up.\n";
        let (shape, rows) = read_any(text);
        assert_eq!(shape, Shape::Numbered);
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].label, "Hero Unboxes the Camera");
        assert_eq!(rows[0].video, "Maya at the kitchen table, the box still sealed.");
        assert_eq!(rows[0].audio, "VO: \"You remember your first.\"");
        // a long sentence after the number is video, not a title
        assert_eq!(rows[1].label, "");
        assert!(rows[1].video.starts_with("First photo at the motel"));
        assert_eq!(rows[2].label, "PARTY MONTAGE");
        assert_eq!(rows[2].video, "Quick cuts.\nMusic up.");
    }

    #[test]
    fn headed_blocks_and_plain_paragraphs() {
        let text = "PARTY MONTAGE\nQuick cuts — the photo passed hand to hand.\nSFX: laughter under.\n\nMacro on the turntable:\nThe camera on black, turning.\n\nThe print develops in her hand. Her face arrives out of the grey.\n\nEnd Card\n";
        let (shape, rows) = read_any(text);
        assert_eq!(shape, Shape::Blocks);
        assert_eq!(rows.len(), 4);
        assert_eq!(rows[0].label, "PARTY MONTAGE");
        assert_eq!(rows[0].video, "Quick cuts — the photo passed hand to hand.");
        assert_eq!(rows[0].audio, "SFX: laughter under.");
        assert_eq!(rows[1].label, "Macro on the turntable");
        assert_eq!(rows[1].video, "The camera on black, turning.");
        // a plain sentence is video with no title
        assert_eq!(rows[2].label, "");
        assert!(rows[2].video.starts_with("The print develops"));
        // a lone short line with nothing under it is video too — it is not
        // standing over anything, so nothing says it is a heading
        assert_eq!(rows[3].label, "");
        assert_eq!(rows[3].video, "End Card");
    }

    #[test]
    fn a_tab_anywhere_means_a_table() {
        let (shape, rows) = read_any("Unboxing\tShe opens the box.\tMusic in.");
        assert_eq!(shape, Shape::Table);
        assert_eq!(rows[0].label, "Unboxing");
    }

    #[test]
    fn a_line_opening_with_a_curly_quote_does_not_split_a_character() {
        // “ is three bytes; slicing five bytes off the front of this line
        // landed inside it. Reading must survive any first character.
        assert!(number_prefix("“Thank you Denis for the opportunity.”").is_none());
        assert!(number_prefix("’Tis the season").is_none());
        assert!(number_prefix("é").is_none());
        let (_, rows) = read_any("1.\n“Thank you Denis.”\n\n2.\n’Tis done.\n");
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[1].video, "’Tis done.");
    }

    #[test]
    fn counts_and_resolutions_are_not_beat_numbers() {
        assert!(number_prefix("300 people fill the square").is_none());
        assert!(number_prefix("4K master, 2.39").is_none());
        assert_eq!(number_prefix("Scene 4: Photo Develops"), Some("Photo Develops"));
        assert_eq!(number_prefix("03 End card"), Some("End card"));
        assert_eq!(number_prefix("2)"), Some(""));
        assert!(number_prefix("3 Hero opens the box").is_none());
        assert_eq!(number_prefix("Scene 4 Photo develops"), Some("Photo develops"));
    }

    #[test]
    fn nothing_pasted_makes_nothing() {
        let mut d = commercial();
        d.create_beat("A", "", "", None);
        assert!(read("  \n\t\n").is_empty());
        assert_eq!(d.apply_av_script(&[]), Report { read: 0, matched: 0, made: 0, unmentioned: 1, removed: 0 });
    }

    const SPOT: &str = "OPEN\tThe kitchen at dawn.\tMusic in.\n\
        PRODUCT\tThe box on the table.\tVO: \"Made here.\"\n\
        TAG\tLogo.\tSting.\n";

    #[test]
    fn two_scripts_with_the_same_beat_names_stay_apart_in_their_sections() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        let b = d.create_sequence("Spot B");
        let first = d.apply_av_script_in(&read(SPOT), Some(a));
        assert_eq!(first, Report { read: 3, matched: 0, made: 3, unmentioned: 0, removed: 0 });

        // Spot B has an OPEN and a TAG too. Without the section it would
        // overwrite A's; with it, B gets its own three beats.
        let second = d.apply_av_script_in(&read(SPOT), Some(b));
        assert_eq!(second, Report { read: 3, matched: 0, made: 3, unmentioned: 0, removed: 0 });
        let beats = d.beats_in_order();
        assert_eq!(beats.len(), 6);
        for x in &beats[..3] {
            assert_eq!(d.get(*x).unwrap().ref_id(f::SEQUENCE), Some(a));
        }
        for x in &beats[3..] {
            assert_eq!(d.get(*x).unwrap().ref_id(f::SEQUENCE), Some(b));
        }

        // Pasting A again updates A's three and makes nothing — and says
        // nothing about B's beats.
        let again = d.apply_av_script_in(&read(SPOT), Some(a));
        assert_eq!(again, Report { read: 3, matched: 3, made: 0, unmentioned: 0, removed: 0 });

        // A revised A with one more beat: it lands at the end of A's run.
        let revised = format!("{SPOT}BUTTON\tShe winks.\t\n");
        let third = d.apply_av_script_in(&read(&revised), Some(a));
        assert_eq!(third, Report { read: 4, matched: 3, made: 1, unmentioned: 0, removed: 0 });
        let beats = d.beats_in_order();
        assert_eq!(beats.len(), 7);
        assert_eq!(d.beat_label(beats[3]), "BUTTON");
        assert_eq!(d.get(beats[4]).unwrap().ref_id(f::SEQUENCE), Some(b));

        let plan_a = d.plan_av_script_in(&read(SPOT), Some(a));
        assert!(plan_a.iter().all(|p| p.is_some()));
        let c = d.create_sequence("Spot C");
        assert!(d.plan_av_script_in(&read(SPOT), Some(c)).iter().all(|p| p.is_none()));
    }

    #[test]
    fn a_scene_moves_in_the_list_and_a_section_can_be_taken_away() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        let (open, product, tag) = (
            d.create_scene_titled("OPEN"),
            d.create_scene_titled("PRODUCT"),
            d.create_scene_titled("TAG"),
        );
        for s in [open, product, tag] {
            d.set(s, f::SEQUENCE, a);
        }

        d.move_scene_after(tag, None);
        assert_eq!(d.scenes_in_order(), vec![tag, open, product]);
        d.move_scene_after(tag, Some(open));
        assert_eq!(d.scenes_in_order(), vec![open, tag, product]);
        assert_eq!(d.get(tag).unwrap().text(f::NUMBER), Some("3"));

        assert_eq!(d.delete_sequence(a), 3);
        assert!(d.sequences_in_order().is_empty());
        assert_eq!(d.scenes_in_order().len(), 3);
        assert_eq!(d.get(open).unwrap().ref_id(f::SEQUENCE), None);
        d.undo();
        assert_eq!(d.sequences_in_order(), vec![a]);
        assert_eq!(d.get(open).unwrap().ref_id(f::SEQUENCE), Some(a));
    }

    #[test]
    fn a_scene_moves_as_a_block_within_its_day_and_a_section_is_born_coloured() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        let b = d.create_sequence("Spot B");
        assert_eq!(d.get(a).unwrap().text(f::COLOUR), Some("#2B6CB0"));
        assert_eq!(d.get(b).unwrap().text(f::COLOUR), Some("#B4531B"));
        let (open, product, tag) = (
            d.create_scene_titled("OPEN"),
            d.create_scene_titled("PRODUCT"),
            d.create_scene_titled("TAG"),
        );
        d.add_shot_to_scene(open);
        d.add_shot_to_scene(open);
        d.add_shot_to_scene(product);
        d.add_shot_to_scene(tag);
        let day = d.create_day();
        for s in [open, product, tag] {
            d.schedule_scene(s, day);
        }
        let scene_of = |d: &Doc, p: Id| d.get(p).unwrap().ref_id(f::SCENE).unwrap();
        let order = |d: &Doc| d.placements_on_day(day).into_iter().map(|p| scene_of(d, p)).collect::<Vec<_>>();
        assert_eq!(order(&d), vec![open, open, product, tag]);

        d.move_scene_in_day(tag, day, Some(open));
        assert_eq!(order(&d), vec![tag, open, open, product]);
        d.move_scene_in_day(open, day, None);
        assert_eq!(order(&d), vec![tag, product, open, open]);
        d.undo();
        assert_eq!(order(&d), vec![tag, open, open, product]);
    }

    #[test]
    fn an_edit_replaces_the_sections_script_and_an_audio_script_reads_as_audio() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        d.apply_av_script_in(&read(SPOT), Some(a));
        let beats = d.beats_in_order();
        let scene = d.create_scene_titled("Kitchen");
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set_shot_beat(shot, Some(beats[1]));

        // PRODUCT struck out of the text: its beat goes, its shot is untied,
        // OPEN is updated, BUTTON is new. One undo brings it all back.
        let edited = "OPEN\tThe kitchen at noon.\tMusic in.\nTAG\tLogo.\tSting.\nBUTTON\tShe winks.\t\n";
        let report = d.replace_av_script_in(&read(edited), Some(a));
        assert_eq!(report, Report { read: 3, matched: 2, made: 1, unmentioned: 0, removed: 1 });
        assert_eq!(d.beats_in_section(Some(a)).len(), 3);
        assert_eq!(d.beat_video(beats[0]), "The kitchen at noon.");
        assert_eq!(d.beat_of_shot(shot), None);
        d.undo();
        assert_eq!(d.beats_in_section(Some(a)).len(), 3);
        assert_eq!(d.beat_of_shot(shot), Some(beats[1]));

        // An audio-only script: paragraphs are what we hear — and an edit
        // of it keeps the beats whose words did not change, ties and all.
        let (_, rows) = read_any("Thank you Denis for the opportunity.\n\nDirecting has been a labour of love.\n");
        let rows = as_audio_only(rows);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].video, "");
        assert_eq!(rows[0].audio, "Thank you Denis for the opportunity.");
        let t = d.create_sequence("HLA");
        d.apply_av_script_in(&rows, Some(t));
        let heard = d.beats_in_section(Some(t));
        d.set_shot_beat(shot, Some(heard[0]));
        let (_, edited) = read_any("Thank you Denis for the opportunity.\n\nWhat you are about to see.\n");
        let report = d.replace_av_script_in(&as_audio_only(edited), Some(t));
        assert_eq!(report, Report { read: 2, matched: 1, made: 1, unmentioned: 0, removed: 1 });
        assert_eq!(d.beat_of_shot(shot), Some(heard[0]), "the unchanged beat kept its shot");
    }

    #[test]
    fn the_editors_numbered_form_round_trips_paragraphs_and_the_audio_marker() {
        let text = "1. OPEN\nThe kitchen at dawn.\n\nShe comes in barefoot.\nAUDIO: Music in.\n\nAUDIO: VO: \"You remember.\"\n\n2.\nLogo.\nAUDIO: Sting.\n";
        let (shape, rows) = read_any(text);
        assert_eq!(shape, Shape::Numbered);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].label, "OPEN");
        assert_eq!(rows[0].video, "The kitchen at dawn.\n\nShe comes in barefoot.");
        assert_eq!(rows[0].audio, "Music in.\n\nVO: \"You remember.\"");
        assert_eq!(rows[1].label, "");
        assert_eq!(rows[1].video, "Logo.");
        assert_eq!(rows[1].audio, "Sting.");
        // A blocks-form paste keeps paragraphs inside a quoted table cell only;
        // an audio-only numbered paste puts every paragraph in what we hear.
        let (_, rows) = read_any("1.\nThank you Denis.\n\nDirecting has been a labour of love.\n\n2.\nWhat you're about to see.\n");
        let rows = as_audio_only(rows);
        assert_eq!(rows[0].audio, "Thank you Denis.\n\nDirecting has been a labour of love.");
        assert_eq!(rows[1].audio, "What you're about to see.");
    }

    #[test]
    fn a_paste_with_no_section_still_sees_the_whole_script() {
        let mut d = commercial();
        let a = d.create_sequence("Spot A");
        d.apply_av_script_in(&read(SPOT), Some(a));
        // With no section named, the whole script is in play — but beats
        // in a section are not the same beat as ones in none.
        let loose = d.apply_av_script(&read(SPOT));
        assert_eq!(loose, Report { read: 3, matched: 0, made: 3, unmentioned: 0, removed: 0 });
    }
}
