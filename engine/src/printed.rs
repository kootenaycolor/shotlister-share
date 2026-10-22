//! Reading a script off printed pages.
//!
//! A PDF is what he actually has, and a PDF is a picture of a page: not a
//! screenplay, but a heap of little runs of text each knowing where it sits.
//! The bytes are decoded by the shell — PDFKit on a Mac, pdf.js in a browser —
//! and what arrives here is [`Page`]s of [`Run`]s. Everything after that is
//! screenplay thinking and belongs in Rust, where it can be tested without a
//! PDF anywhere in sight. See decision 1 in `design/phases/phase-2-script.md`.
//!
//! **The point of positions.** Reading plain text, the reader has to guess a
//! character cue from capitals and blank lines, and it is wrong on any line of
//! action somebody shouted. On a printed page there is no guessing: a cue sits
//! 3.7 inches from the paper's edge and action sits at 1.5, and the column is
//! the answer. That is the whole reason to take the harder input.
//!
//! **One reader, not two.** This module does not build a screenplay. It decides
//! what each line is and then writes the script back out with Fountain's own
//! forcing marks on it — `@` for a cue, `!` for action, `>` for a transition —
//! and hands that to [`screenplay::read_with`]. The marks mean exactly *"I know
//! what this line is, do not guess"*, which is precisely what a column tells us.
//! So there is still one set of rules about what a scene is, and the positioned
//! path is the text path with better information rather than a rival to it.
//!
//! Headings and bare room names are deliberately left **unmarked**, because
//! forcing them would skip the detection rules — the numbering, the repeats,
//! the lettering of rooms under their parent — that exist for exactly this
//! input.
//!
//! **What it does not do.** Dual dialogue printed as two columns side by side
//! is read as two consecutive speeches, in the order the runs arrive. Getting
//! it right means noticing two blocks sharing a vertical range and splitting
//! the page in half, and it is rare enough in his work not to buy that yet.

use crate::screenplay::{self, Detection, Screenplay};
use crate::script;

/// One run of text off a page, in points, with the origin at the **top left**.
///
/// PDFKit measures from the bottom left, so the shell flips `y` on the way in.
/// It is one line of a conversion rather than a rule anybody has to remember,
/// and it means everything here reads down the page the way a person does.
#[derive(Clone, Debug, PartialEq)]
pub struct Run {
    pub x: f32,
    pub y: f32,
    pub text: String,
}

impl Run {
    pub fn new(x: f32, y: f32, text: impl Into<String>) -> Run {
        Run {
            x,
            y,
            text: text.into(),
        }
    }
}

/// One page, and what is on it.
#[derive(Clone, Debug, Default)]
pub struct Page {
    /// Points. US Letter is 612 × 792.
    pub width: f32,
    pub height: f32,
    pub runs: Vec<Run>,
}

impl Page {
    /// A US Letter page carrying these runs.
    pub fn letter(runs: Vec<Run>) -> Page {
        Page {
            width: 612.0,
            height: 792.0,
            runs,
        }
    }
}

/// Seventy-two points to the inch, which is the only unit conversion in here.
const INCH: f32 = 72.0;

/// How far apart two runs' baselines may be and still be the same line.
const SAME_LINE: f32 = 3.0;

/// Where each kind of line sits, in inches from the left of the **text block**
/// rather than from the paper — so the numbers survive a script with unusual
/// margins, and a page whose crop box is offset.
///
/// These are the standard: action at 1.5" from the paper, dialogue at 2.5",
/// parenthetical at 3.1", character at 3.7", transition at 6.0".
const COLUMNS: [(f32, Column); 5] = [
    (0.0, Column::Left),
    (1.0, Column::Dialogue),
    (1.6, Column::Parenthetical),
    (2.2, Column::Character),
    (4.5, Column::Transition),
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Column {
    /// Action, and scene headings, which share the left edge of the block.
    Left,
    Dialogue,
    Parenthetical,
    Character,
    Transition,
}

/// Read a screenplay off printed pages.
pub fn read(pages: &[Page], detection: &Detection) -> Screenplay {
    screenplay::read_with(&as_script(pages), detection)
}

/// The same reading, as the marked-up script it hands on — which is the thing
/// worth looking at when something has gone wrong, and what the tests assert.
pub fn as_script(pages: &[Page]) -> String {
    let lines: Vec<Line> = pages
        .iter()
        .enumerate()
        .flat_map(|(at, page)| gather(page, at))
        .collect();
    if lines.is_empty() {
        return String::new();
    }

    let left = left_margin(&lines);
    let leading = leading(&lines);
    let blocks = into_blocks(&lines, left, leading);

    let mut out = String::new();
    for block in &blocks {
        if !out.is_empty() {
            out.push('\n');
        }
        block.write(&mut out);
    }
    out
}

// ---- runs into lines -----------------------------------------------------

#[derive(Clone, Debug)]
struct Line {
    page: usize,
    y: f32,
    /// Where the line's own words start, ignoring a scene number printed out in
    /// the margin beside them.
    body_x: f32,
    text: String,
}

/// Everything on one page, as lines, with the page's furniture left off.
fn gather(page: &Page, number: usize) -> Vec<Line> {
    let mut runs: Vec<&Run> = page
        .runs
        .iter()
        .filter(|run| {
            let text = run.text.trim();
            // A revision mark sits out in the margin on the same baseline as
            // the line it marks, so it has to go before the line is assembled
            // or it arrives inside the sentence.
            !text.is_empty() && !text.chars().all(|c| c == '*')
        })
        .collect();
    runs.sort_by(|a, b| {
        a.y.partial_cmp(&b.y)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal))
    });

    // Assembled with their parts kept, because *which* part a line's own words
    // begin at is a question the parts can answer and the finished string
    // cannot.
    let mut lines: Vec<Line> = Vec::new();
    let mut parts: Vec<Vec<(f32, String)>> = Vec::new();
    for run in runs {
        let text = run.text.trim().to_string();
        match lines.last_mut() {
            Some(line) if (run.y - line.y).abs() <= SAME_LINE => {
                if let Some(part) = parts.last_mut() {
                    part.push((run.x, text));
                }
            }
            _ => {
                lines.push(Line {
                    page: number,
                    y: run.y,
                    body_x: run.x,
                    text: String::new(),
                });
                parts.push(vec![(run.x, text)]);
            }
        }
    }

    for (line, parts) in lines.iter_mut().zip(&parts) {
        // A scene number is printed out in the margin beside its slug, and on a
        // numbered script it is printed *twice*, once at each edge. A reader
        // that hands back lines rather than words gives both of those as their
        // own piece of the line, so the line's own words start at the first
        // piece that is not a number — never at the first piece.
        line.body_x = parts
            .iter()
            .find(|(_, text)| !is_a_scene_number_group(text))
            .map(|(x, _)| *x)
            .unwrap_or(parts.first().map(|(x, _)| *x).unwrap_or(line.body_x));

        let joined = parts
            .iter()
            .map(|(_, text)| text.as_str())
            .collect::<Vec<_>>()
            .join(" ");
        line.text = collapse_repeated_number(&joined);
    }

    lines.retain(|line| !is_furniture(line, page));
    lines
}

/// A page number, a carried-over marker, or anything else the printer put there
/// that the writer did not.
fn is_furniture(line: &Line, page: &Page) -> bool {
    let text = line.text.trim();
    if text.is_empty() {
        return true;
    }
    // What a paginator writes when a scene or a speech runs over the bottom of
    // a page, and picks up again at the top of the next. Matched **whole**, not
    // as a word inside a line: a character may perfectly well say the word
    // continued, and a scene may be called THE MORE THINGS CHANGE.
    let bare = text
        .trim_start_matches('(')
        .trim_end_matches(')')
        .trim_end_matches(':')
        .trim();
    if matches!(bare.to_uppercase().as_str(), "CONTINUED" | "MORE" | "CONT'D") {
        return true;
    }
    let near_the_top = line.y < INCH * 0.75;
    let near_the_bottom = line.y > page.height - INCH * 0.75;
    if !near_the_top && !near_the_bottom {
        return false;
    }
    // Up there, a short thing with a number in it is a page number — `23.`,
    // `2.`, `Page 4`. A slug is never short and never up there.
    text.split_whitespace().count() <= 2
        && text.chars().any(|c| c.is_ascii_digit())
        && crate::script::read_slug(text).is_none()
}

fn is_a_scene_number(word: &str) -> bool {
    let cleaned = word.trim_end_matches('.');
    !cleaned.is_empty()
        && cleaned.chars().next().is_some_and(|c| c.is_ascii_digit())
        && cleaned.chars().all(|c| c.is_ascii_alphanumeric())
        && cleaned.len() <= 6
}

/// Whether a piece of a line is nothing but scene numbers — `34`, or `34 34`
/// where both margins' numbers arrived together.
fn is_a_scene_number_group(text: &str) -> bool {
    let mut any = false;
    for word in text.split_whitespace() {
        if !is_a_scene_number(word) {
            return false;
        }
        any = true;
    }
    any
}

/// `34 34 INT. KITCHEN - DAY` → `34 INT. KITCHEN - DAY`.
///
/// The number at each margin of a numbered page is the *same* number, and a
/// reader that gives a line's pieces in reading order hands both of them over
/// before the slug. Left in, the second one sits between the number and the
/// `INT.` and stops it being a slug at all — which is the difference between
/// finding twenty-one scenes and finding none.
fn collapse_repeated_number(text: &str) -> String {
    let mut words: Vec<&str> = text.split_whitespace().collect();
    while words.len() >= 2 && is_a_scene_number(words[0]) && words[0] == words[1] {
        words.remove(0);
    }
    words.join(" ")
}

// ---- learning the page ---------------------------------------------------

/// The left edge of the text block, learned rather than assumed.
///
/// Action and scene headings share it and there are always plenty of both, so
/// the leftmost column that several lines start at is it. Learning beats
/// assuming here: a script printed with wider margins, or a PDF whose page box
/// is offset, would put every fixed number out by the same amount and every
/// line in the wrong column.
fn left_margin(lines: &[Line]) -> f32 {
    let mut starts: Vec<f32> = lines.iter().map(|line| line.body_x).collect();
    starts.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let wanted = 3.min(starts.len());
    let mut at = 0;
    while at < starts.len() {
        let mut to = at;
        while to < starts.len() && starts[to] - starts[at] <= INCH / 5.0 {
            to += 1;
        }
        if to - at >= wanted {
            return starts[at];
        }
        at = to;
    }
    starts.first().copied().unwrap_or(0.0)
}

/// The distance between one line and the next, learned from the page.
///
/// Twelve points is the standard and almost always right, but a script set a
/// little loose would otherwise read as one long paragraph with no breaks in
/// it, so it is measured rather than assumed.
///
/// The awkward case is a **sparse page** — one where no two lines are adjacent,
/// because nothing on it wrapped and nothing was said at length. Then every gap
/// on the page is a double space, the smallest gap is not the leading, and
/// taking it as one glues the whole page into a single paragraph. There is no
/// way to tell from the page which it is, so the tie is broken by what a
/// screenplay is actually like: a page of separate short paragraphs is
/// ordinary, and a page that is one sixty-line paragraph is not.
fn leading(lines: &[Line]) -> f32 {
    let mut gaps: Vec<f32> = lines
        .windows(2)
        .filter(|pair| pair[0].page == pair[1].page)
        .map(|pair| pair[1].y - pair[0].y)
        .filter(|gap| *gap > 1.0 && *gap < INCH / 2.0)
        .collect();
    if gaps.is_empty() {
        return 12.0;
    }
    gaps.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let smallest = gaps[0];
    // Something standing about twice as far off as the closest pair is the
    // blank line between paragraphs, and its presence is what proves the
    // closest pair really were shoulder to shoulder.
    let doubled = gaps
        .iter()
        .any(|gap| (*gap - smallest * 2.0).abs() <= smallest * 0.4);
    if doubled {
        smallest
    } else {
        smallest / 2.0
    }
}

/// Which column a line is standing in.
fn column_of(line: &Line, left: f32) -> Column {
    let offset = (line.body_x - left) / INCH;
    let mut best = Column::Left;
    let mut nearest = f32::MAX;
    for (at, column) in COLUMNS {
        let apart = (offset - at).abs();
        if apart < nearest {
            nearest = apart;
            best = column;
        }
    }
    best
}

// ---- lines into blocks ---------------------------------------------------

#[derive(Debug)]
enum Block {
    /// Left unmarked on purpose, so the detection rules get to decide.
    Plain(String),
    Action(String),
    Transition(String),
    Speech {
        who: String,
        said: Vec<String>,
    },
}

impl Block {
    fn write(&self, out: &mut String) {
        match self {
            Block::Plain(text) => {
                out.push_str(text);
                out.push('\n');
            }
            Block::Action(text) => {
                out.push('!');
                out.push_str(text);
                out.push('\n');
            }
            Block::Transition(text) => {
                out.push('>');
                out.push_str(text);
                out.push('\n');
            }
            Block::Speech { who, said } => {
                out.push('@');
                out.push_str(who);
                out.push('\n');
                for line in said {
                    out.push_str(line);
                    out.push('\n');
                }
            }
        }
    }
}

fn into_blocks(lines: &[Line], left: f32, leading: f32) -> Vec<Block> {
    // A little over one line's distance: the same paragraph carried on, rather
    // than a new one started.
    let carried_on = leading * 1.6;

    let mut blocks: Vec<Block> = Vec::new();
    let mut at = 0;

    while at < lines.len() {
        let line = &lines[at];
        let column = column_of(line, left);

        // Position proposes and text disposes, in the two places where text is
        // the surer witness: a slug says what it is in words, and a bracketed
        // line is a parenthetical wherever somebody's software chose to set it.
        // A number printed in the margin is the script naming a scene, and it
        // says so however many words follow. Without this, `1 OVER BLACK - THE
        // SOUND OF A ROTARY PHONE RINGING.` is too long to be taken for a room
        // and becomes a paragraph of action.
        let heading = script::read_slug(&line.text).is_some()
            || script::read_numbered_heading(&line.text).is_some();

        if heading || (column == Column::Left && stands_alone(lines, at, carried_on)) {
            blocks.push(Block::Plain(line.text.clone()));
            at += 1;
            continue;
        }

        match column {
            Column::Character => {
                let who = line.text.clone();
                let mut said = Vec::new();
                let mut to = at + 1;
                while to < lines.len() && follows(&lines[to - 1], &lines[to], carried_on) {
                    let next = column_of(&lines[to], left);
                    let spoken = matches!(next, Column::Dialogue | Column::Parenthetical)
                        || lines[to].text.starts_with('(');
                    if !spoken {
                        break;
                    }
                    said.push(lines[to].text.clone());
                    to += 1;
                }
                // A cue with nothing under it is a heading somebody set in the
                // middle of the page. Let the text rules have it.
                if said.is_empty() {
                    blocks.push(Block::Plain(who));
                } else {
                    blocks.push(Block::Speech { who, said });
                }
                at = to;
            }
            Column::Transition => {
                blocks.push(Block::Transition(line.text.clone()));
                at += 1;
            }
            // Dialogue with no cue above it, and action: both are a paragraph
            // that runs until the spacing opens up.
            _ => {
                let (text, to) = paragraph(lines, at, carried_on);
                blocks.push(Block::Action(text));
                at = to;
            }
        }
    }
    blocks
}

/// Whether one line carries straight on from the one above it.
fn follows(above: &Line, line: &Line, carried_on: f32) -> bool {
    above.page == line.page && line.y - above.y <= carried_on
}

/// A run of lines at one column, joined back into the paragraph they were
/// wrapped out of. The line breaks in a PDF are the printer's, not the
/// writer's, so putting them back is losing nothing.
fn paragraph(lines: &[Line], at: usize, carried_on: f32) -> (String, usize) {
    let mut text = lines[at].text.clone();
    let mut to = at + 1;
    while to < lines.len()
        && follows(&lines[to - 1], &lines[to], carried_on)
        && (lines[to].body_x - lines[at].body_x).abs() <= INCH / 5.0
        // A heading sits at the same column as the action around it, so the
        // only thing keeping a paragraph from swallowing one is asking.
        && script::read_slug(&lines[to].text).is_none()
        && script::read_numbered_heading(&lines[to].text).is_none()
    {
        text.push(' ');
        text.push_str(&lines[to].text);
        to += 1;
    }
    (text, to)
}

/// Whether a line at the left edge is standing by itself, with space above and
/// below — which is what a bare room name looks like, and what nothing else at
/// that column does. Left unmarked so the sub-slug rule can consider it.
fn stands_alone(lines: &[Line], at: usize, carried_on: f32) -> bool {
    let alone_above = at == 0 || !follows(&lines[at - 1], &lines[at], carried_on);
    let alone_below = at + 1 >= lines.len() || !follows(&lines[at], &lines[at + 1], carried_on);
    if !(alone_above && alone_below) {
        return false;
    }
    let text = lines[at].text.trim();
    text.split_whitespace().count() <= 5
        && text.chars().any(|c| c.is_alphabetic())
        && !text.chars().any(|c| c.is_lowercase())
}
