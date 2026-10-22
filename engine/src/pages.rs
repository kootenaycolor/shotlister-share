//! Laying a screenplay out on pages, and measuring what that costs in eighths.
//!
//! A screenplay's page is not a description of a screenplay, it is a **unit of
//! work**. "Two and three eighths" is how long a scene takes to shoot, how much
//! of a day it eats, and what a first AD writes on a strip. It only means
//! anything because everybody's page is the same page: 12-point Courier, ten
//! characters to the inch, six lines to the inch, a text block an inch and a
//! half in and six inches across, fifty-five lines to a sheet. Change any of
//! those and the number stops being comparable to anybody else's.
//!
//! So this is arithmetic with a right answer, and it lives here rather than in
//! the UI. The shell receives pages of lines that already know their row and
//! their indent, and draws them. No measuring in a view.
//!
//! **What the paginator adds of its own.** When a speech runs over the bottom
//! of a page it writes `(MORE)` under it and `CHARACTER (CONT'D)` at the top of
//! the next — words that are not in the script. They are flagged [`Line::added`]
//! so that a search never finds them, and so anything reading the script back
//! out can leave them behind.
//!
//! Three rules about where a page may not break, all of them the trade's:
//!
//! - A character cue never parts from the first thing they say.
//! - A scene heading never sits alone at the foot of a page.
//! - A parenthetical never parts from the line it qualifies.

use crate::screenplay::{Element, Kind, Screenplay};

/// Lines on a sheet of US Letter at six to the inch, with an inch of margin top
/// and bottom, less the line the page number sits on.
pub const LINES_PER_PAGE: usize = 55;

/// Characters across the text block: six inches at ten to the inch.
pub const MEASURE: usize = 60;

/// Eighths in a page. The whole point of the unit.
pub const EIGHTHS: usize = 8;

/// One line, placed.
#[derive(Clone, Debug, PartialEq)]
pub struct Line {
    /// Which row of the page it sits on, from 0. Blank space is the rows that
    /// are missing rather than lines with nothing in them.
    pub row: usize,
    /// Characters in from the left edge of the text block.
    pub indent: usize,
    pub kind: Kind,
    pub text: String,
    pub scene: Option<usize>,
    /// `(MORE)` and `CHARACTER (CONT'D)`: the paginator's words, not the
    /// writer's.
    pub added: bool,
}

/// One page of the script.
#[derive(Clone, Debug, Default)]
pub struct Page {
    /// As printed, from 1.
    pub number: usize,
    pub lines: Vec<Line>,
}

/// How long one scene is, and where it starts.
#[derive(Clone, Debug, PartialEq)]
pub struct Extent {
    pub scene: usize,
    pub label: String,
    /// The page its heading is printed on.
    pub starts_on: usize,
    /// Rows of page it occupies, heading included.
    pub lines: usize,
    /// The same length in eighths of a page. Never zero: a scene that exists at
    /// all is an eighth, which is the trade's own floor.
    pub eighths: usize,
}

impl Extent {
    /// As an AD writes it: `2 3/8`, `1`, `5/8`.
    pub fn length(&self) -> String {
        let pages = self.eighths / EIGHTHS;
        let rest = self.eighths % EIGHTHS;
        match (pages, rest) {
            (0, rest) => format!("{rest}/8"),
            (pages, 0) => format!("{pages}"),
            (pages, rest) => format!("{pages} {rest}/8"),
        }
    }
}

/// A screenplay, laid out.
#[derive(Clone, Debug, Default)]
pub struct Paginated {
    pub pages: Vec<Page>,
    pub scenes: Vec<Extent>,
}

impl Paginated {
    /// How long the whole thing is.
    pub fn pages_long(&self) -> usize {
        self.pages.len()
    }

    pub fn extent_of(&self, scene: usize) -> Option<&Extent> {
        self.scenes.iter().find(|extent| extent.scene == scene)
    }

    /// The pages one scene is printed across, first and last.
    pub fn pages_of(&self, scene: usize) -> Option<(usize, usize)> {
        let first = self
            .pages
            .iter()
            .find(|page| page.lines.iter().any(|line| line.scene == Some(scene)))?;
        let last = self
            .pages
            .iter()
            .rev()
            .find(|page| page.lines.iter().any(|line| line.scene == Some(scene)))?;
        Some((first.number, last.number))
    }
}

/// Where each kind of line sits and how wide it runs, in characters from the
/// left edge of the text block. The standard, and the reason a page count means
/// the same thing to two people.
fn shape(kind: Kind) -> (usize, usize) {
    match kind {
        Kind::SceneHeading | Kind::Action | Kind::Centered => (0, MEASURE),
        Kind::Dialogue | Kind::Lyric => (10, 40),
        Kind::Parenthetical => (16, 24),
        Kind::Character => (22, 38),
        Kind::Transition => (45, 15),
        // Never printed, so never measured.
        Kind::Section | Kind::Synopsis | Kind::PageBreak => (0, MEASURE),
    }
}

/// Blank lines before this kind of element. A heading gets two, everything that
/// starts something gets one, and everything that continues a speech gets none.
fn space_before(kind: Kind) -> usize {
    match kind {
        Kind::SceneHeading => 2,
        Kind::Parenthetical | Kind::Dialogue | Kind::Lyric => 0,
        _ => 1,
    }
}

/// Lay a screenplay out.
pub fn lay_out(screenplay: &Screenplay) -> Paginated {
    let mut sheet = Sheet::new();
    let printed: Vec<&Element> = screenplay
        .elements
        .iter()
        .filter(|element| element.kind.is_printed())
        .collect();

    let mut at = 0;
    while at < printed.len() {
        let element = printed[at];

        if element.kind == Kind::PageBreak {
            sheet.turn_over();
            at += 1;
            continue;
        }

        if element.kind == Kind::Character {
            let mut to = at + 1;
            while to < printed.len() && printed[to].kind.is_speech() && printed[to].kind != Kind::Character {
                to += 1;
            }
            speech(&mut sheet, &printed[at..to]);
            at = to;
            continue;
        }

        let (indent, width) = shape(element.kind);
        let wrapped = wrap(&element.text, width);
        let space = space_before(element.kind);

        // A heading with nothing under it is a heading on the wrong page.
        let needs = if element.kind == Kind::SceneHeading {
            wrapped.len() + 2
        } else {
            1
        };
        if sheet.room() < space + needs {
            sheet.turn_over();
        } else {
            sheet.blank(space);
        }

        for line in wrapped {
            if sheet.room() == 0 {
                sheet.turn_over();
            }
            sheet.put(element.kind, indent, line, element.scene, false);
        }
        at += 1;
    }

    let pages = sheet.finish();
    let scenes = measure(&pages, screenplay);
    Paginated { pages, scenes }
}

/// A cue and everything said under it, which is the run a page may not part
/// carelessly.
fn speech(sheet: &mut Sheet, block: &[&Element]) {
    let cue = block[0];
    let (cue_indent, cue_width) = shape(Kind::Character);
    let name = wrap(&cue.text, cue_width);

    // Every line of what is said, remembering which element it came from so a
    // parenthetical is never left behind on its own.
    let mut said: Vec<(Kind, usize, String)> = Vec::new();
    for element in &block[1..] {
        let (indent, width) = shape(element.kind);
        for line in wrap(&element.text, width) {
            said.push((element.kind, indent, line));
        }
    }

    let space = space_before(Kind::Character);
    // The cue, and at least one line of what they say, or it goes over.
    if sheet.room() < space + name.len() + 1 {
        sheet.turn_over();
    } else {
        sheet.blank(space);
    }

    for line in &name {
        sheet.put(Kind::Character, cue_indent, line.clone(), cue.scene, false);
    }

    let mut at = 0;
    while at < said.len() {
        // Room for this line, plus the `(MORE)` that would have to follow it if
        // there were more to come.
        let last = at + 1 == said.len();
        let needed = if last { 1 } else { 2 };

        if sheet.room() < needed {
            sheet.put(
                Kind::Parenthetical,
                cue_indent,
                "(MORE)".to_string(),
                cue.scene,
                true,
            );
            sheet.turn_over();
            let carried = format!("{} (CONT'D)", strip_extension(&cue.text));
            sheet.put(Kind::Character, cue_indent, carried, cue.scene, true);
        }

        // A parenthetical is the last thing on a page only if what it qualifies
        // is coming with it.
        if said[at].0 == Kind::Parenthetical && sheet.room() < 2 && at + 1 < said.len() {
            sheet.put(
                Kind::Parenthetical,
                cue_indent,
                "(MORE)".to_string(),
                cue.scene,
                true,
            );
            sheet.turn_over();
            let carried = format!("{} (CONT'D)", strip_extension(&cue.text));
            sheet.put(Kind::Character, cue_indent, carried, cue.scene, true);
        }

        let (kind, indent, text) = said[at].clone();
        sheet.put(kind, indent, text, cue.scene, false);
        at += 1;
    }
}

/// `JIMMY (V.O.)` → `JIMMY`, so a carried-over cue does not end up wearing two
/// sets of brackets.
fn strip_extension(name: &str) -> &str {
    match name.split_once('(') {
        Some((before, _)) => before.trim_end(),
        None => name.trim(),
    }
}

// ---- the sheet -----------------------------------------------------------

struct Sheet {
    pages: Vec<Page>,
    lines: Vec<Line>,
    row: usize,
    number: usize,
}

impl Sheet {
    fn new() -> Sheet {
        Sheet {
            pages: Vec::new(),
            lines: Vec::new(),
            row: 0,
            number: 1,
        }
    }

    fn room(&self) -> usize {
        LINES_PER_PAGE.saturating_sub(self.row)
    }

    /// Blank rows, which are rows nothing is put on. Never at the top of a
    /// page: a page does not open with a gap.
    fn blank(&mut self, rows: usize) {
        if self.row == 0 {
            return;
        }
        self.row = (self.row + rows).min(LINES_PER_PAGE);
    }

    fn put(&mut self, kind: Kind, indent: usize, text: String, scene: Option<usize>, added: bool) {
        if self.room() == 0 {
            self.turn_over();
        }
        self.lines.push(Line {
            row: self.row,
            indent,
            kind,
            text,
            scene,
            added,
        });
        self.row += 1;
    }

    fn turn_over(&mut self) {
        if self.lines.is_empty() {
            // Nothing on it: turning over an empty page would print a blank one.
            self.row = 0;
            return;
        }
        self.pages.push(Page {
            number: self.number,
            lines: std::mem::take(&mut self.lines),
        });
        self.number += 1;
        self.row = 0;
    }

    fn finish(mut self) -> Vec<Page> {
        if !self.lines.is_empty() {
            self.pages.push(Page {
                number: self.number,
                lines: self.lines,
            });
        }
        self.pages
    }
}

// ---- measuring -----------------------------------------------------------

/// How much page each scene takes, in rows and then in eighths.
fn measure(pages: &[Page], screenplay: &Screenplay) -> Vec<Extent> {
    let mut extents = Vec::new();

    for (index, scene) in screenplay.scenes.iter().enumerate() {
        let mut first: Option<usize> = None;
        let mut last: Option<usize> = None;
        let mut starts_on = 0;

        for page in pages {
            for line in &page.lines {
                if line.scene != Some(index) {
                    continue;
                }
                // Counted from the top of the script rather than of the page,
                // so a scene running over a break measures the whole of what it
                // occupies.
                let absolute = (page.number - 1) * LINES_PER_PAGE + line.row;
                if first.is_none() {
                    first = Some(absolute);
                    starts_on = page.number;
                }
                last = Some(absolute);
            }
        }

        let (Some(first), Some(last)) = (first, last) else {
            continue;
        };
        let lines = last - first + 1;
        extents.push(Extent {
            scene: index,
            label: scene.label.clone(),
            starts_on,
            lines,
            eighths: eighths_for(lines),
        });
    }
    extents
}

/// Rows of page into eighths, rounded as a person would and never to nothing.
pub fn eighths_for(lines: usize) -> usize {
    let exact = lines as f64 * EIGHTHS as f64 / LINES_PER_PAGE as f64;
    (exact.round() as usize).max(1)
}

// ---- wrapping ------------------------------------------------------------

/// Break a line to its measure, on spaces.
fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut out = Vec::new();
    for written in reflow(text, width) {
        if written.is_empty() {
            out.push(String::new());
            continue;
        }
        let mut line = String::new();
        for word in written.split_whitespace() {
            if line.is_empty() {
                line.push_str(word);
            } else if line.chars().count() + 1 + word.chars().count() <= width {
                line.push(' ');
                line.push_str(word);
            } else {
                out.push(std::mem::take(&mut line));
                line.push_str(word);
            }
            // A word longer than the measure has to be broken somewhere, and
            // the end of the line is where a typewriter would have done it.
            while line.chars().count() > width {
                let head: String = line.chars().take(width).collect();
                let rest: String = line.chars().skip(width).collect();
                out.push(head);
                line = rest;
            }
        }
        if !line.is_empty() {
            out.push(line);
        }
    }
    out
}

/// Put back together the lines that were only ever broken by *somebody else's*
/// margin, and leave alone the ones the writer meant.
///
/// A screenplay arrives already wrapped more often than not — typed to a
/// seventy-character terminal, pasted out of another program, read off a page.
/// Wrapping an already-wrapped paragraph to a narrower measure gives the ragged
/// half-lines that give away a document nobody laid out, and, worse, it invents
/// rows: rows are what eighths are counted from, so a scene would be reported
/// longer than it is and somebody would schedule a day around the difference.
///
/// The tell is the right edge. A line broken by a margin ends *at* that margin,
/// so it is nearly as long as the longest line around it; a line the writer
/// broke on purpose ends early, because they meant it to. Both floors matter:
/// without the block's own widest line a paragraph wrapped narrow stays broken,
/// and without an absolute one a run of deliberately short lines — all equally
/// short, so all equally "long" — would be glued into a paragraph.
fn reflow(text: &str, width: usize) -> Vec<String> {
    let written: Vec<&str> = text.split('\n').map(|line| line.trim_end()).collect();
    if written.len() < 2 {
        return written.into_iter().map(str::to_string).collect();
    }

    let widest = written
        .iter()
        .map(|line| line.chars().count())
        .max()
        .unwrap_or(0) as f32;
    let full = (widest * 0.8).max(width as f32 * 0.5);

    let mut out: Vec<String> = Vec::new();
    let mut line = String::new();
    for (at, source) in written.iter().enumerate() {
        if line.is_empty() {
            line.push_str(source);
        } else {
            line.push(' ');
            line.push_str(source.trim_start());
        }
        let reaches_the_edge = source.chars().count() as f32 >= full;
        let more_to_come = at + 1 < written.len();
        if !(reaches_the_edge && more_to_come) {
            out.push(std::mem::take(&mut line));
        }
    }
    if !line.is_empty() {
        out.push(line);
    }
    out
}
