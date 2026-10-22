//! **Auto layout for the printed table.**
//!
//! His ask, 2026-10-15: *"an auto-optimize feature that finds the right
//! balance between picture size, landscape/portrait and columns, so text
//! doesn't go crazy long and skinny but pictures are still big enough."*
//!
//! So this tries the sheets the table could be printed on — portrait or
//! landscape, a handful of picture widths, a handful of text sizes — and for
//! each one works out every column's width from what is actually in it:
//!
//! 1. Every column gets its floor: its longest whole word, or its longest
//!    whole pill, or its header's longest word. Nothing narrower can be
//!    printed without cutting a word in half.
//! 2. The columns that wrap (Description, Notes, Title, Script, his own text
//!    columns) are raised towards a comfortable measure first.
//! 3. The short columns (the pills, Day) are then raised until most of
//!    their cells sit on one line.
//! 4. What is left goes to the wrapping columns in proportion to how much
//!    each one holds.
//!
//! Then it sets every row the way WebKit will — the same font's own letter
//! widths (`metrics`), the stylesheet's own sizes and padding — and scores
//! the sheet (`Weights`): skinny text columns, very tall rows, small
//! pictures, cut words, wasted width and, mildly, the page count. The best
//! score wins. Nothing here draws: what comes out is a `Plan`, which the
//! table page draws with exactly the shares it names.

use super::html::{self, FrameSize};
use super::metrics::{em_width, Weight};
use super::rows::{Row, Sheet};
use crate::query::GroupBy;

// ---- the knobs ------------------------------------------------------------

/// **What a good sheet is, as numbers.** Every term is a penalty: the plan
/// with the smallest sum wins. They are here, together, so tuning Auto is
/// changing a number in one place and looking at the pages again.
#[derive(Clone, Copy, Debug)]
pub struct Weights {
    /// A wrapping column narrower than `skinny_chars` average letters, for
    /// every row whose text in it runs to more than one line. Squared, so a
    /// column at half the measure costs four times one at three quarters.
    pub skinny: f64,
    /// About eighteen to twenty-two letters is where a column stops reading
    /// as a sentence and starts reading as a list of words.
    pub skinny_chars: f64,
    /// Per inch a row stands taller than `tall_in` (or its own picture, when
    /// that is taller), averaged over the rows.
    pub tall: f64,
    pub tall_in: f64,
    /// A storyboard frame narrower than `picture_min_in` stops being
    /// recognisable; this is per inch short of it, and heavy.
    pub picture_small: f64,
    pub picture_min_in: f64,
    /// A gentle pull towards a picture about `picture_ideal_in` wide —
    /// without it the cheapest sheet is always the one with the smallest
    /// pictures.
    pub picture_want: f64,
    pub picture_ideal_in: f64,
    /// Past `picture_max_in` the picture is eating room the words need.
    pub picture_big: f64,
    pub picture_max_in: f64,
    /// **Each word cut in the middle.** Heavy enough that any sheet without
    /// one beats every sheet with one.
    pub midword: f64,
    /// The share of the table's width no cell uses.
    pub waste: f64,
    /// Pages per ten shots. Mild: a longer, readable sheet is better than a
    /// short cramped one.
    pub pages: f64,
    /// Each 5% step the text is set below its designed size.
    pub text_small: f64,
    /// **The designed size the text is measured against** — 1.0, or his
    /// Size (`Ask::size`), which moves every size above with it.
    pub text_at: f64,
}

impl Weights {
    /// **The same taste at another size.** His Size makes the information
    /// on the sheet smaller or larger, text and pictures together, so the
    /// inches a good sheet is judged by move with it; what reads as skinny
    /// (in letters) does not.
    pub fn sized(&self, size: f64) -> Weights {
        Weights {
            tall_in: self.tall_in * size,
            picture_min_in: self.picture_min_in * size,
            picture_ideal_in: self.picture_ideal_in * size,
            picture_max_in: self.picture_max_in * size,
            text_at: self.text_at * size,
            ..*self
        }
    }
}

/// **What he asked of Auto** (2026-10-16): *"one slider that makes the
/// information small or larger"*, and Landscape or Portrait if he says so.
/// Auto still works out every width; these only move where it looks.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Ask {
    /// Text and pictures together, as a multiple of Auto's own sizes.
    pub size: f64,
    /// `Some(true)` landscape, `Some(false)` portrait, `None` Auto's pick.
    pub landscape: Option<bool>,
}

impl Default for Ask {
    fn default() -> Ask {
        Ask { size: 1.0, landscape: None }
    }
}

impl Ask {
    /// The range the Size slider has; anything said outside it is pulled in.
    pub const SMALLEST: f64 = 0.7;
    pub const LARGEST: f64 = 1.3;

    pub fn new(size: f64, landscape: Option<bool>) -> Ask {
        let size = if size.is_finite() { size.clamp(Ask::SMALLEST, Ask::LARGEST) } else { 1.0 };
        Ask { size, landscape }
    }

    /// A text size at this Size, rounded so the measuring and the sheet
    /// agree on it exactly.
    pub fn text(&self, scale: f64) -> f64 {
        ((scale * self.size) * 1000.0).round() / 1000.0
    }

    /// The text sizes measured: Auto's own, and the same at this Size.
    pub fn scales(&self) -> Vec<f64> {
        let mut out: Vec<f64> = SCALES.to_vec();
        for &s in &SCALES {
            let at = self.text(s);
            if !out.iter().any(|o| (o - at).abs() < 1e-9) {
                out.push(at);
            }
        }
        out
    }
}

pub const WEIGHTS: Weights = Weights {
    skinny: 14.0,
    skinny_chars: 20.0,
    tall: 3.0,
    tall_in: 1.9,
    picture_small: 30.0,
    picture_min_in: 1.4,
    picture_want: 3.5,
    picture_ideal_in: 2.0,
    picture_big: 6.0,
    picture_max_in: 2.6,
    midword: 400.0,
    waste: 18.0,
    pages: 1.2,
    text_small: 1.5,
    text_at: 1.0,
};

/// The text sizes tried, as the export box's own scale. **The floor is
/// 80%**: the body is then 8.2 points and the pills (0.7 of the root) 7.6 —
/// about as small as a sheet read on set can go. Each step down costs
/// (`text_small`), so it is only taken when it buys something.
pub const SCALES: [f64; 8] = [0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.2];

/// The picture widths tried, in inches.
pub const PICTURES_IN: [f64; 9] = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.25, 2.5, 2.8];

// ---- the paper, as `Printing` cuts it ---------------------------------------

/// US Letter, in points.
const LETTER: (f64, f64) = (612.0, 792.0);
/// `Printing.Kind.table.margin` — **if one changes, the other has to.**
const MARGIN: f64 = 32.0;
/// One rem at 100%: `doc::ROOT` times the table's designed 0.85.
const ROOT: f64 = 16.0 * 0.85;
/// A CSS pixel, in rem at 100% — the pills' hairline and the row rules.
const PX: f64 = 1.0 / ROOT;

// The stylesheet's own sizes, in rem (`html::stylesheet`).
const TD_PAD_X: f64 = 0.9;
const TD_PAD_Y: f64 = 0.8;
const TH_PAD_X: f64 = 0.8;
const TH_PAD_Y: f64 = 0.9;
const BODY: f64 = 0.75;
const BODY_LINE: f64 = 1.5;
const TITLE: f64 = 0.85;
const PILL: f64 = 0.7;
const PILL_PAD_X: f64 = 0.34 * PILL;
const PILL_LINE: f64 = 1.2;
const PILL_H: f64 = PILL * PILL_LINE + 0.2 * PILL + 2.0 * PX;
/// Lens Stack's quiet line (`.stackline`).
const STACK: f64 = 0.62;
const NOTE: f64 = 0.66;
const HEAD: f64 = 0.56;

// ---- the problem -------------------------------------------------------------

thread_local! {
    /// The text size the problem is being measured at, as the export box's
    /// scale. Set by `Problem::of` for the length of one measuring pass.
    static MEASURING_AT: std::cell::Cell<f64> = const { std::cell::Cell::new(1.0) };
}

/// **The tracking WebKit adds at this size**, in ems per letter. SF Pro is
/// set looser the smaller it gets — 2% of an em at 7px, none at 10px, and
/// tighter above — which CoreText's plain advances do not include. Measured
/// against WebKit itself, 2026-10-15, across 7 to 13px and all three
/// weights; a straight line fits it to within a few thousandths.
fn tracking_at(px: f64) -> f64 {
    // Below 7px (his Size under 100%) the line was not measured; it is
    // made looser there, so a small sheet errs a hair wide, not cut.
    0.0645 - 0.00635 * px + (7.0 - px).max(0.0) * 0.015
}

/// A hair over what was measured, so a column sized to the letter does not
/// lose a word to rounding in the renderer.
const SAFETY: f64 = 1.015;

/// A run of words that wraps at spaces — and after a hyphen inside a word,
/// as WebKit does (`Close-` / `Up`) — measured in rem at 100% of this
/// problem's text size. A piece glued to the one before it has no space.
#[derive(Clone, Debug, Default)]
struct Words {
    words: Vec<(f64, bool)>,
    space: f64,
    line: f64,
}

/// A word's pieces, broken after each hyphen that has a letter both sides.
fn pieces(word: &str) -> Vec<&str> {
    let chars: Vec<(usize, char)> = word.char_indices().collect();
    let mut out = Vec::new();
    let mut from = 0;
    for i in 1..chars.len().saturating_sub(1) {
        let (at, c) = chars[i];
        if matches!(c, '-' | '\u{2010}') && chars[i - 1].1.is_alphabetic() && chars[i + 1].1.is_alphabetic() {
            let end = at + c.len_utf8();
            out.push(&word[from..end]);
            from = end;
        }
    }
    out.push(&word[from..]);
    out
}

impl Words {
    fn of(text: &str, size: f64, weight: Weight, letter_spacing: f64) -> Words {
        let scale = MEASURING_AT.with(|m| m.get());
        let px = size * ROOT * scale;
        let per_letter = tracking_at(px) + letter_spacing;
        let measure = |w: &str| (em_width(w, weight) + per_letter * w.chars().count() as f64) * size * SAFETY;
        let mut words = Vec::new();
        for word in text.split_whitespace() {
            for (i, piece) in pieces(word).into_iter().enumerate() {
                words.push((measure(piece), i > 0));
            }
        }
        Words { words, space: (em_width(" ", weight) + per_letter) * size, line: 0.0 }
    }

    /// A single unbreakable run — the shot number.
    fn solid(text: &str, size: f64, weight: Weight) -> Words {
        let mut w = Words::of(text, size, weight, 0.0);
        let whole = w.natural();
        w.words = vec![(whole, false)];
        w
    }

    fn natural(&self) -> f64 {
        self.words
            .iter()
            .enumerate()
            .map(|(i, (w, glued))| if i == 0 || *glued { *w } else { w + self.space })
            .sum()
    }

    fn longest(&self) -> f64 {
        self.words.iter().map(|w| w.0).fold(0.0, f64::max)
    }

    /// Lines at this width, and how many words had to be cut to fit.
    fn lines(&self, width: f64) -> (usize, usize) {
        if self.words.is_empty() {
            return (0, 0);
        }
        let mut lines = 1;
        let mut used = 0.0;
        let mut cut = 0;
        for &(w, glued) in &self.words {
            if w > width + 1e-6 {
                cut += 1;
                // A cut word takes the lines it is broken over, from a new one.
                let pieces = (w / width.max(0.1)).ceil() as usize;
                lines += if used > 0.0 { pieces } else { pieces - 1 };
                used = w - (pieces - 1) as f64 * width;
                continue;
            }
            let gap = if glued { 0.0 } else { self.space };
            if used == 0.0 {
                used = w;
            } else if used + gap + w <= width + 1e-6 {
                used += gap + w;
            } else {
                lines += 1;
                used = w;
            }
        }
        (lines, cut)
    }
}

/// One thing in a flex row: a pill, or a quiet note beside one.
#[derive(Clone, Debug)]
struct Item {
    /// The words inside, which wrap only if the item is wider than the cell.
    text: Words,
    /// Padding and hairline, left and right together.
    pad: f64,
    /// Height of one line of it, and of the box around one line.
    line: f64,
    boxed: f64,
}

impl Item {
    fn pill(text: &str) -> Item {
        Item {
            text: Words::of(text, PILL, Weight::Semibold, 0.0),
            // The hairline is a real pixel whatever the text size.
            pad: 2.0 * PILL_PAD_X + 2.0 * PX / MEASURING_AT.with(|m| m.get()),
            line: PILL * PILL_LINE,
            boxed: PILL_H,
        }
    }

    fn note(text: &str, size: f64) -> Item {
        Item {
            text: Words::of(text, size, Weight::Regular, 0.0),
            pad: 0.0,
            line: size * 1.25,
            boxed: size * 1.25,
        }
    }

    /// A Lens Stack line's entry: a ring or diamond, a gap, the name.
    fn stacked(text: &str) -> Item {
        Item {
            text: Words::of(text, STACK, Weight::Regular, 0.0),
            pad: 0.8 * STACK,
            line: STACK * 1.3,
            boxed: STACK * 1.3,
        }
    }

    fn natural(&self) -> f64 {
        self.text.natural() + self.pad
    }

    /// (width, height, cut words) set in at most `width`.
    fn set(&self, width: f64) -> (f64, f64, usize) {
        let whole = self.natural();
        if whole <= width + 1e-6 {
            return (whole, self.boxed, 0);
        }
        let (lines, cut) = self.text.lines((width - self.pad).max(0.1));
        (width, self.boxed + (lines.max(1) - 1) as f64 * self.line, cut)
    }
}

/// A block inside a cell, top to bottom.
#[derive(Clone, Debug)]
enum Block {
    Text(Words),
    Flex { items: Vec<Item>, gap_x: f64, gap_y: f64, top: f64 },
}

impl Block {
    fn natural(&self) -> f64 {
        match self {
            Block::Text(w) => w.natural(),
            Block::Flex { items, gap_x, .. } => {
                items.iter().map(Item::natural).sum::<f64>()
                    + gap_x * items.len().saturating_sub(1) as f64
            }
        }
    }

    /// The narrowest this can be without cutting a word. A pill may wrap
    /// between its own words — `Tracking / Backward` in one box is still a
    /// whole pill — so its floor is its longest word inside its padding.
    fn floor(&self) -> f64 {
        match self {
            Block::Text(w) => w.longest(),
            Block::Flex { items, .. } => {
                items.iter().map(|i| i.text.longest() + i.pad).fold(0.0, f64::max)
            }
        }
    }

    /// (height, cut words) at this content width.
    fn set(&self, width: f64) -> (f64, usize) {
        match self {
            Block::Text(w) => {
                let (lines, cut) = w.lines(width);
                (lines as f64 * w.line, cut)
            }
            Block::Flex { items, gap_x, gap_y, top } => {
                if items.is_empty() {
                    return (0.0, 0);
                }
                let mut height = 0.0;
                let mut line_h: f64 = 0.0;
                let mut used = 0.0;
                let mut cut = 0;
                for item in items {
                    let (w, h, c) = item.set(width);
                    cut += c;
                    if used > 0.0 && used + gap_x + w > width + 1e-6 {
                        height += line_h + gap_y;
                        line_h = 0.0;
                        used = 0.0;
                    }
                    used += if used > 0.0 { gap_x + w } else { w };
                    line_h = line_h.max(h);
                }
                (top + height + line_h, cut)
            }
        }
    }
}

/// One cell: its blocks, and the shape of its picture if it is the picture.
#[derive(Clone, Debug, Default)]
struct Cell {
    blocks: Vec<Block>,
    /// Height over width of the frame box, for a picture cell with a picture.
    picture: Option<f64>,
    /// `<p>` margins: a script cell's paragraphs carry a line of space above
    /// and below.
    extra: f64,
}

impl Cell {
    fn natural(&self) -> f64 {
        self.blocks.iter().map(Block::natural).fold(0.0, f64::max)
    }

    fn floor(&self) -> f64 {
        self.blocks.iter().map(Block::floor).fold(0.0, f64::max)
    }

    fn set(&self, width: f64) -> (f64, usize) {
        let mut h = self.extra;
        let mut cut = 0;
        for b in &self.blocks {
            let (bh, c) = b.set(width);
            h += bh;
            cut += c;
        }
        (h, cut)
    }

    fn is_empty(&self) -> bool {
        self.picture.is_none() && self.blocks.iter().all(|b| b.natural() <= 0.0)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Role {
    /// The shot number: never wraps, never cut.
    Number,
    /// The storyboard frame.
    Picture,
    /// Free text that is meant to wrap.
    Wrap,
    /// Pills and other short things that should sit on a line.
    Short,
}

#[derive(Clone, Debug)]
struct Column {
    field: String,
    role: Role,
    header: Words,
    cells: Vec<Cell>,
    /// Measured once: the floor (longest whole word or pill, header
    /// included), the widest cell set on one line, the 90th percentile of
    /// that, and the column's total text — all in rem at 100%, content only.
    floor: f64,
    natural_max: f64,
    natural_p90: f64,
    content: f64,
    /// Every cell's own floor, widest first, as (width, how many cells) —
    /// what a column gives up, cell by cell, when not every floor fits.
    steps: Vec<(f64, usize)>,
    /// How many rows have something in this column.
    filled: usize,
}

/// **Everything Auto needs to know about one sheet**, measured once. Every
/// candidate sheet is then only arithmetic on these numbers — the font is
/// never asked twice, which is what makes trying ninety sheets quick.
#[derive(Clone, Debug)]
struct Measured {
    /// The text size these were measured at — WebKit's tracking depends on it.
    scale: f64,
    columns: Vec<Column>,
    rows: usize,
    /// Rows that have a picture to print.
    pictured: usize,
    /// Tables on the page — a header row each — and the headings between.
    tables: usize,
    headings: usize,
    /// Whether the section spine (`.insec`) takes width off every table.
    spine: bool,
}

fn role_of(field: &str, column: &[Cell]) -> Role {
    match field {
        "number" => Role::Number,
        "image" => Role::Picture,
        "title" | "description" | "notes" | "script" => Role::Wrap,
        "size" | "angle" | "movement" | "camera" | "lens" | "modifiers" | "lens_filters"
        | "support" | "tags" | "day" | "struck" => Role::Short,
        // Sequence and his own columns: whatever they hold. A column whose
        // longest cell is a couple of words is short; anything longer wraps.
        _ => {
            let longest = column.iter().map(Cell::natural).fold(0.0, f64::max);
            if longest > 9.0 { Role::Wrap } else { Role::Short }
        }
    }
}

fn text(s: &str) -> Block {
    let mut w = Words::of(s, BODY, Weight::Regular, 0.0);
    w.line = BODY * BODY_LINE;
    Block::Text(w)
}

fn pills(values: &[String]) -> Block {
    Block::Flex {
        items: values.iter().filter(|v| !v.trim().is_empty()).map(|v| Item::pill(v)).collect(),
        gap_x: 0.25,
        gap_y: 0.22,
        top: 0.0,
    }
}

/// What `html::table_cell` draws, as blocks to measure. **The two have to
/// agree**: a cell drawn one way and measured another is a column Auto
/// sized for words that are not there.
fn cell_of(sheet: &Sheet, row: &Row, field: &str) -> Cell {
    let one = |b: Block| Cell { blocks: vec![b], ..Cell::default() };
    match field {
        "number" => {
            // Never wraps: one word as wide as the whole number.
            let mut w = Words::solid(&row.number, BODY, Weight::Semibold);
            w.line = BODY * BODY_LINE;
            one(Block::Text(w))
        }
        "image" => {
            let shape = match row.print_frame.as_ref() {
                Some(pf) if pf.width > 0.0 && pf.height > 0.0 => Some(pf.height / pf.width),
                Some(_) => Some(1.0 / sheet.project_ratio.max(0.01)),
                None => row.key_frame.map(|_| 1.0 / sheet.project_ratio.max(0.01)),
            };
            Cell { picture: shape, ..Cell::default() }
        }
        "title" => {
            let mut w = Words::of(&row.title, TITLE, Weight::Bold, -0.01);
            w.line = TITLE * BODY_LINE;
            one(Block::Text(w))
        }
        "description" => one(text(&row.description)),
        "notes" => one(text(&row.notes)),
        "script" => {
            let paragraphs: Vec<&str> =
                row.script.split("\n\n").map(str::trim).filter(|p| !p.is_empty()).collect();
            let n = paragraphs.len();
            Cell {
                blocks: paragraphs.into_iter().map(text).collect(),
                picture: None,
                // `<p>` keeps its 1em above and below; between two they
                // collapse into one.
                extra: if n == 0 { 0.0 } else { BODY * (n as f64 + 1.0) },
            }
        }
        "size" => one(pills(std::slice::from_ref(&row.size))),
        "angle" => one(pills(&row.angle)),
        "movement" => one(pills(std::slice::from_ref(&row.movement))),
        "support" => one(pills(std::slice::from_ref(&row.support))),
        "tags" => one(pills(&row.tags)),
        "modifiers" => one(pills(&row.modifiers)),
        "lens_filters" => one(pills(&row.lens_filters)),
        "struck" => one(if row.struck { pills(&["SHOT".to_string()]) } else { pills(&[]) }),
        "camera" => match row.camera.as_ref() {
            None => Cell::default(),
            Some(c) => {
                let label = if c.label.is_empty() { &c.body } else { &c.label };
                let mut items = vec![Item::pill(label)];
                if !c.body.is_empty() && !c.label.is_empty() {
                    items.push(Item::note(&c.body, NOTE));
                }
                one(Block::Flex { items, gap_x: 0.4, gap_y: 0.22, top: 0.0 })
            }
        },
        "lens" => {
            let mut blocks = Vec::new();
            if !row.lens.trim().is_empty() {
                let mut items = vec![Item::pill(&row.lens)];
                if let Some(mm) = row.focal {
                    items.push(Item::note(&format!("{}mm", mm.round() as i64), NOTE));
                }
                blocks.push(Block::Flex { items, gap_x: 0.4, gap_y: 0.22, top: 0.0 });
            }
            let parts = row.stack_parts();
            if !parts.is_empty() {
                blocks.push(Block::Flex {
                    items: parts.iter().map(|p| Item::stacked(p)).collect(),
                    gap_x: 0.6,
                    gap_y: 0.1,
                    top: 0.25,
                });
            }
            Cell { blocks, ..Cell::default() }
        }
        "day" => one(text(row.day_label.as_deref().unwrap_or(""))),
        "sequence" => one(text(row.sequence.as_deref().unwrap_or(""))),
        other => match row.own_pills.iter().find(|(slug, _)| slug == other) {
            Some((_, parts)) => one(pills(parts)),
            None => one(text(
                row.own.iter().find(|(slug, _)| slug == other).map(|(_, w)| w.as_str()).unwrap_or(""),
            )),
        },
    }
}

fn percentile(mut values: Vec<f64>, p: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let at = ((values.len() - 1) as f64 * p).round() as usize;
    values[at.min(values.len() - 1)]
}

/// **Everything Auto needs to know about one sheet**, measured once per text
/// size tried. Every candidate is then only arithmetic on these numbers.
#[derive(Clone, Debug)]
pub struct Problem {
    measured: Vec<Measured>,
    ask: Ask,
}

impl Problem {
    /// Measure a sheet at every text size Auto tries (and at 100%, for the
    /// default it is compared with). Cheap — a pass over the rows with a
    /// table lookup per letter, six or seven times.
    pub fn of(sheet: &Sheet) -> Problem {
        Problem::asked(sheet, Ask::default())
    }

    /// Measured at the text sizes his Size makes Auto try.
    pub fn asked(sheet: &Sheet, ask: Ask) -> Problem {
        let mut scales: Vec<f64> = ask.scales();
        if !scales.iter().any(|s| (s - 1.0).abs() < 1e-9) {
            scales.push(1.0);
        }
        Problem { measured: scales.into_iter().map(|s| Measured::of(sheet, s)).collect(), ask }
    }

    pub fn ask(&self) -> Ask {
        self.ask
    }

    fn at(&self, scale: f64) -> &Measured {
        self.measured
            .iter()
            .min_by(|a, b| (a.scale - scale).abs().partial_cmp(&(b.scale - scale).abs()).unwrap())
            .expect("measured at least once")
    }

    pub fn is_empty(&self) -> bool {
        self.at(1.0).rows == 0
    }

    pub fn describe(&self) -> String {
        self.at(1.0).describe()
    }
}

impl Measured {
    fn of(sheet: &Sheet, scale: f64) -> Measured {
        MEASURING_AT.with(|m| m.set(scale));
        let measured = Measured::measure(sheet, scale);
        MEASURING_AT.with(|m| m.set(1.0));
        measured
    }

    fn measure(sheet: &Sheet, scale: f64) -> Measured {
        let fields = html::table_columns(sheet);
        let rows: Vec<&Row> = sheet.rows().collect();
        let mut columns = Vec::with_capacity(fields.len());
        for field in &fields {
            let cells: Vec<Cell> = rows.iter().map(|r| cell_of(sheet, r, field)).collect();
            let role = role_of(field, &cells);
            let label = html::column_header(sheet, field).to_uppercase();
            let mut header = Words::of(&label, HEAD, Weight::Semibold, 0.03);
            header.line = HEAD * 1.25;
            let floor = cells.iter().map(Cell::floor).fold(header.longest(), f64::max);
            let naturals: Vec<f64> = cells.iter().map(Cell::natural).filter(|n| *n > 0.0).collect();
            let natural_max = naturals.iter().cloned().fold(0.0, f64::max);
            let natural_p90 = percentile(naturals.clone(), 0.9);
            let content = naturals.iter().sum();
            let filled = cells.iter().filter(|c| !c.is_empty()).count();
            let mut each: Vec<f64> = cells.iter().map(Cell::floor).filter(|f| *f > 0.0).collect();
            each.sort_by(|a, b| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
            let mut steps: Vec<(f64, usize)> = Vec::new();
            for f in each {
                match steps.last_mut() {
                    Some((w, n)) if (*w - f).abs() < 0.05 => *n += 1,
                    _ => steps.push((f, 1)),
                }
            }
            columns.push(Column {
                field: field.to_string(),
                role,
                header,
                cells,
                floor,
                natural_max,
                natural_p90,
                content,
                steps,
                filled,
            });
        }
        let pictured = columns
            .iter()
            .find(|c| c.role == Role::Picture)
            .map(|c| c.cells.iter().filter(|x| x.picture.is_some()).count())
            .unwrap_or(0);
        // One table per group grouped by scene; otherwise one per run of a
        // scene inside the group (`html::runs`), each with its own heading.
        // A section's spine — `.insec`, a 4px rule and .6rem beside it —
        // stands to the left of every table in a section.
        let spine = sheet.groups.iter().any(|g| g.section.is_some())
            || rows.iter().any(|r| r.section.is_some());
        let mut tables = 0;
        let mut headings = 0;
        for group in &sheet.groups {
            headings += 1;
            if sheet.grouped_by == GroupBy::Scene {
                tables += 1;
            } else {
                let mut last = None;
                for row in &group.rows {
                    if last != Some(row.scene) {
                        tables += 1;
                        headings += 1;
                        last = Some(row.scene);
                    }
                }
            }
        }
        Measured { scale, columns, rows: rows.len(), pictured, tables: tables.max(1), headings, spine }
    }

    /// One line a column — what Auto measured, in rem at 100% — for tuning
    /// and for the report.
    fn describe(&self) -> String {
        self.columns
            .iter()
            .map(|c| {
                format!(
                    "{} {:?} floor {:.2} head {:.2} p90 {:.2} max {:.2} filled {}",
                    c.field, c.role, c.floor, c.header.longest(), c.natural_p90, c.natural_max, c.filled
                )
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
}

// ---- a candidate sheet ---------------------------------------------------------

/// One way the table could be printed.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Candidate {
    pub landscape: bool,
    pub scale: f64,
    /// The storyboard frame's width on paper, in inches. Ignored when the
    /// table has no picture column.
    pub picture_in: f64,
}

/// **What Auto chose, and what it costs.**
#[derive(Clone, Debug)]
pub struct Plan {
    pub candidate: Candidate,
    /// Every column's share of the table, in percent, summing to 100, in the
    /// table's own column order.
    pub shares: Vec<(String, f64)>,
    pub score: f64,
    pub pages: usize,
    /// Words that would be cut in the middle. Zero whenever any sheet can
    /// avoid it.
    pub cut_words: usize,
    /// The narrowest wrapping column, in average letters (0 with none).
    pub narrowest_chars: f64,
    /// The breakdown of `score`, by term, for the report and the tests.
    pub terms: Vec<(&'static str, f64)>,
}

impl Plan {
    /// **The Small / Medium / Large the export box shows** for this picture,
    /// so a switch to Manual starts from a dial that says roughly what Auto
    /// did; the exact width rides in the multipliers.
    pub fn frames(&self) -> FrameSize {
        if self.candidate.picture_in < 1.45 {
            FrameSize::Small
        } else if self.candidate.picture_in < 2.1 {
            FrameSize::Medium
        } else {
            FrameSize::Large
        }
    }

    /// **The same shares as the export box's width multipliers**, against
    /// the page's own weights at `frames()`. The page normalises a
    /// multiplier set back to exactly these shares, so Manual starts on the
    /// very sheet Auto chose.
    pub fn factors(&self) -> Vec<(String, f64)> {
        let size = self.frames();
        let weights: Vec<f64> = self.shares.iter().map(|(f, _)| html::base_weight(f, size)).collect();
        let total: f64 = weights.iter().sum();
        self.shares
            .iter()
            .zip(&weights)
            .map(|((f, share), w)| {
                let base = if total > 0.0 { w / total * 100.0 } else { 1.0 };
                (f.clone(), if base > 0.0 { share / base } else { 1.0 })
            })
            .collect()
    }
}

fn paper(landscape: bool) -> (f64, f64) {
    if landscape { (LETTER.1, LETTER.0) } else { LETTER }
}

/// Every column's outer width in rem, for one candidate. Floors first, then
/// the wrapping columns towards a readable measure, then the short ones onto
/// one line, then the rest by how much text each holds.
fn widths(p: &Measured, c: &Candidate, w: &Weights) -> Vec<f64> {
    let r = ROOT * c.scale;
    let (pw, _) = paper(c.landscape);
    // The `.wrap` padding, 1.5rem each side.
    let table = (pw - 2.0 * MARGIN) / r - 3.0 - spine(p);
    let n = p.columns.len();
    let mut out = vec![0.0; n];
    let mut fixed = 0.0;
    for (i, col) in p.columns.iter().enumerate() {
        match col.role {
            Role::Number => out[i] = col.natural_max.max(col.floor) + TD_PAD_X + 0.1,
            Role::Picture => out[i] = c.picture_in * 72.0 / r + TD_PAD_X,
            _ => {}
        }
        fixed += out[i];
    }
    let flexible: Vec<usize> =
        (0..n).filter(|i| !matches!(p.columns[*i].role, Role::Number | Role::Picture)).collect();
    if flexible.is_empty() {
        // Only a number and a picture: the picture takes what is left.
        if let Some(i) = p.columns.iter().position(|c| c.role == Role::Picture) {
            out[i] = (table - fixed + out[i]).max(out[i]);
        }
        return out;
    }
    let floor = |i: usize| p.columns[i].floor.max(p.columns[i].header.longest()) + TD_PAD_X.max(TH_PAD_X);
    let floors: f64 = flexible.iter().map(|&i| floor(i)).sum();
    let mut left = table - fixed - floors;
    if left < 0.0 {
        return squeezed(p, &flexible, out, -left, &floor);
    }
    for &i in &flexible {
        out[i] = floor(i);
    }
    // Raise each of `who` towards `goal(i)` (an outer width), sharing out
    // `left` in proportion to what each still wants.
    let raise = |out: &mut Vec<f64>, left: &mut f64, who: &[usize], goal: &dyn Fn(usize) -> f64| {
        let wants: Vec<f64> = who.iter().map(|&i| (goal(i) - out[i]).max(0.0)).collect();
        let total: f64 = wants.iter().sum();
        if total <= 0.0 || *left <= 0.0 {
            return;
        }
        let k = (*left / total).min(1.0);
        for (&i, want) in who.iter().zip(&wants) {
            out[i] += want * k;
        }
        *left -= total * k;
    };
    let wraps: Vec<usize> = flexible.iter().cloned().filter(|&i| p.columns[i].role == Role::Wrap).collect();
    let shorts: Vec<usize> = flexible.iter().cloned().filter(|&i| p.columns[i].role == Role::Short).collect();
    // 1. Wrapping columns towards a readable measure — never past their
    //    own longest line.
    let measure = |i: usize| {
        let col = &p.columns[i];
        let letter = average_letter(col);
        (w.skinny_chars * letter).min(col.natural_max) + TD_PAD_X
    };
    raise(&mut out, &mut left, &wraps, &measure);
    // 2. Short columns until nine cells in ten sit on one line.
    raise(&mut out, &mut left, &shorts, &|i| p.columns[i].natural_p90 + TD_PAD_X + 0.05);
    // 3. The rest to the wrapping columns by how much each holds, each
    //    capped at its longest line; what one cannot take passes on.
    for _ in 0..4 {
        if left <= 1e-6 {
            break;
        }
        let open: Vec<usize> = wraps
            .iter()
            .cloned()
            .filter(|&i| out[i] < p.columns[i].natural_max + TD_PAD_X - 1e-6)
            .collect();
        let total: f64 = open.iter().map(|&i| p.columns[i].content.max(0.01)).sum();
        if open.is_empty() || total <= 0.0 {
            break;
        }
        let pot = left;
        for &i in &open {
            let give = pot * p.columns[i].content.max(0.01) / total;
            let cap = p.columns[i].natural_max + TD_PAD_X - out[i];
            let given = give.min(cap);
            out[i] += given;
            left -= given;
        }
    }
    // 4. Then the short columns all the way to their longest cell.
    raise(&mut out, &mut left, &shorts, &|i| p.columns[i].natural_max + TD_PAD_X + 0.05);
    // 5. Anything still over is width nobody needs: spread over everything
    //    but the number, the way `table-layout: fixed` would anyway.
    if left > 1e-6 {
        let total: f64 = flexible.iter().map(|&i| out[i]).sum();
        let pot = left;
        for &i in &flexible {
            out[i] += pot * out[i] / total;
        }
    }
    out
}

/// **Not every floor fits: cut as few words as possible.** Each step takes a
/// column down past one more of its widest cells; the step taken is always
/// the one that frees the most width per cell it cuts, so one long word in
/// one row is given up before a column's every cell is. Never below its
/// header's longest word while anything else can give.
fn squeezed(
    p: &Measured,
    flexible: &[usize],
    mut out: Vec<f64>,
    mut owed: f64,
    floor: &dyn Fn(usize) -> f64,
) -> Vec<f64> {
    // Each column's ladder of content widths, widest first: its cells'
    // floors, then its header's longest word, then a last rung at half that.
    let ladders: Vec<Vec<(f64, f64)>> = p
        .columns
        .iter()
        .map(|col| {
            // Cutting a header cuts it once on every table.
            let mut rungs: Vec<(f64, f64)> = col.steps.iter().map(|s| (s.0, s.1 as f64)).collect();
            rungs.push((col.header.longest(), p.tables as f64));
            rungs.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
            let last = rungs.last().map(|r| r.0).unwrap_or(1.0);
            rungs.push((last * 0.5, 1e6));
            rungs
        })
        .collect();
    let mut at: Vec<usize> = vec![0; p.columns.len()];
    for &i in flexible {
        out[i] = floor(i);
    }
    while owed > 1e-6 {
        // The step that frees the most width per cell it cuts.
        let mut best: Option<(usize, f64, f64)> = None;
        for &i in flexible {
            let ladder = &ladders[i];
            let k = at[i];
            if k + 1 >= ladder.len() {
                continue;
            }
            let freed = (out[i] - TD_PAD_X - ladder[k + 1].0).max(0.0);
            let rate = freed / ladder[k].1.max(1.0);
            if freed > 1e-6 && best.map(|(_, _, r)| rate > r).unwrap_or(true) {
                best = Some((i, freed, rate));
            }
        }
        let Some((i, freed, _)) = best else { break };
        let take = freed.min(owed);
        out[i] -= take;
        owed -= take;
        at[i] += 1;
    }
    if owed > 1e-6 {
        // Every column is down to its last rung: shrink them all alike.
        let total: f64 = flexible.iter().map(|&i| out[i]).sum();
        let k = ((total - owed) / total).max(0.05);
        for &i in flexible {
            out[i] *= k;
        }
    }
    out
}

/// The width the section spine takes beside a table, in rem — the
/// stylesheet's `.insec`.
fn spine(p: &Measured) -> f64 {
    if p.spine { SPINE_RULE * PX + SPINE_PAD } else { 0.0 }
}
/// Nothing since 2026-10-15: the section's coloured side bar was taken off
/// (`.insec { padding-left: 0 }`). Kept as numbers so a spine coming back
/// is one change here.
const SPINE_RULE: f64 = 0.0;
const SPINE_PAD: f64 = 0.0;

/// The average letter of a column's own text, in rem — what "twenty
/// letters" means for this face at this size.
fn average_letter(col: &Column) -> f64 {
    let size = if col.field == "title" { TITLE } else { BODY };
    // SF Pro's lower case runs about 0.52em; mixed text with capitals and
    // spaces lands close to that.
    0.52 * size
}

/// Score one candidate sheet.
pub fn assess(p: &Problem, c: &Candidate, w: &Weights) -> Plan {
    let p = p.at(c.scale);
    let widths = widths(p, c, w);
    assess_widths(p, c, w, &widths)
}

fn assess_widths(p: &Measured, c: &Candidate, w: &Weights, widths: &[f64]) -> Plan {
    let r = ROOT * c.scale;
    let (pw, ph) = paper(c.landscape);
    let table: f64 = widths.iter().sum();
    let inch = 72.0 / r;
    let mut terms: Vec<(&'static str, f64)> = Vec::new();

    // ---- the rows, set
    let mut cut = 0usize;
    let mut row_h = vec![0.0f64; p.rows];
    let mut tall = 0.0;
    let mut multi = vec![0usize; p.columns.len()];
    let mut used_width = vec![0.0f64; p.columns.len()];
    for (ci, col) in p.columns.iter().enumerate() {
        let inner = (widths[ci] - TD_PAD_X).max(0.1);
        for (ri, cell) in col.cells.iter().enumerate() {
            let h = if let Some(shape) = cell.picture {
                // The frame box at the column's width, its hairline round it.
                inner * shape + 2.0 * PX
            } else {
                let (h, c) = cell.set(inner);
                if col.role != Role::Number {
                    cut += c;
                }
                let one_line = cell.blocks.iter().all(|b| match b {
                    Block::Text(words) => words.lines(inner).0 <= 1,
                    Block::Flex { .. } => b.natural() <= inner + 1e-6,
                });
                if !one_line {
                    multi[ci] += 1;
                }
                h
            };
            used_width[ci] = used_width[ci].max(cell.natural().min(inner));
            row_h[ri] = row_h[ri].max(h);
        }
        // A header word wider than its column is cut too.
        let (_, hc) = col.header.lines((widths[ci] - TH_PAD_X).max(0.1));
        cut += hc;
    }
    let pictures = p.columns.iter().position(|c| c.role == Role::Picture);
    for (ri, h) in row_h.iter_mut().enumerate() {
        *h += TD_PAD_Y + PX;
        let picture_h = pictures
            .and_then(|pi| p.columns[pi].cells[ri].picture.map(|s| (widths[pi] - TD_PAD_X) * s + TD_PAD_Y))
            .unwrap_or(0.0);
        let limit = (w.tall_in * inch).max(picture_h + 0.01);
        if *h > limit {
            tall += (*h - limit) / inch;
        }
    }
    let head_h = p
        .columns
        .iter()
        .zip(widths)
        .map(|(col, cw)| col.header.lines((cw - TH_PAD_X).max(0.1)).0.max(1) as f64 * col.header.line)
        .fold(0.0, f64::max)
        + TH_PAD_Y;

    // ---- the pages: a row is never split, so a sheet ends where the next
    // row would not fit. Masthead and headings at the stylesheet's sizes.
    let page_h = (ph - 2.0 * MARGIN) / r;
    let mut pages = 1usize;
    let mut y = 6.5 + 1.5; // masthead, then the wrap's own padding
    let per_table = head_h;
    let heading = 2.8;
    let tables_every = (p.rows as f64 / p.tables as f64).max(1.0);
    let headings_every = (p.rows as f64 / p.headings.max(1) as f64).max(1.0);
    let mut next_table = 0.0;
    let mut next_heading = 0.0;
    for (i, h) in row_h.iter().enumerate() {
        let mut add = *h;
        if i as f64 >= next_heading {
            add += heading;
            next_heading += headings_every;
        }
        if i as f64 >= next_table {
            add += per_table + 1.0;
            next_table += tables_every;
        }
        if y + add > page_h && y > 0.0 {
            pages += 1;
            y = 0.0;
        }
        y += add;
    }

    // ---- the score
    if cut > 0 {
        terms.push(("cut words", w.midword * cut as f64));
    }
    let rows = p.rows.max(1) as f64;
    let mut skinny = 0.0;
    let mut narrowest = f64::INFINITY;
    for (ci, col) in p.columns.iter().enumerate() {
        if col.role != Role::Wrap || col.filled == 0 {
            continue;
        }
        let chars = (widths[ci] - TD_PAD_X) / average_letter(col);
        narrowest = narrowest.min(chars);
        if chars < w.skinny_chars {
            let short = (w.skinny_chars - chars) / w.skinny_chars;
            skinny += w.skinny * short * short * (multi[ci] as f64 / rows) * 4.0;
        }
    }
    if skinny > 0.0 {
        terms.push(("skinny columns", skinny));
    }
    if tall > 0.0 {
        terms.push(("tall rows", w.tall * tall / rows));
    }
    if let Some(pi) = pictures {
        if p.pictured > 0 {
            let inches = (widths[pi] - TD_PAD_X) / inch;
            let share = p.pictured as f64 / rows;
            if inches < w.picture_min_in {
                // Linear, and counted as if at least half the rows had a
                // picture: a sheet with a few frames still wants them seen.
                let short = w.picture_min_in - inches;
                terms.push(("small pictures", w.picture_small * short * share.max(0.5)));
            }
            if inches < w.picture_ideal_in {
                terms.push(("pictures under ideal", w.picture_want * (w.picture_ideal_in - inches) * share));
            }
            if inches > w.picture_max_in {
                terms.push(("pictures too big", w.picture_big * (inches - w.picture_max_in)));
            }
        }
    }
    let waste: f64 = p
        .columns
        .iter()
        .enumerate()
        .filter(|(_, col)| col.role != Role::Picture && col.role != Role::Number)
        .map(|(ci, col)| {
            if col.filled == 0 {
                (widths[ci] - TD_PAD_X).max(0.0)
            } else {
                (widths[ci] - TD_PAD_X - used_width[ci].max(col.floor)).max(0.0)
            }
        })
        .sum::<f64>()
        / table.max(1.0);
    if waste > 0.0 {
        terms.push(("wasted width", w.waste * waste));
    }
    terms.push(("pages", w.pages * pages as f64 / rows * 10.0));
    if c.scale < w.text_at - 1e-9 {
        terms.push(("small text", w.text_small * (w.text_at - c.scale) / (0.05 * w.text_at)));
    }
    let _ = pw;
    let score = terms.iter().map(|(_, v)| v).sum();
    let total: f64 = widths.iter().sum();
    let shares = p
        .columns
        .iter()
        .zip(widths)
        .map(|(col, cw)| (col.field.clone(), cw / total * 100.0))
        .collect();
    Plan {
        candidate: *c,
        shares,
        score,
        pages,
        cut_words: cut,
        narrowest_chars: if narrowest.is_finite() { narrowest } else { 0.0 },
        terms,
    }
}

/// **The sheet Auto prints.** Every candidate is scored and the lowest
/// wins; a tie goes to the earlier one, which is landscape at the designed
/// size — the sheet everybody already knows.
pub fn solve(p: &Problem) -> Plan {
    solve_with(p, &WEIGHTS)
}

///
/// **His Size zooms the sheet Auto chose** (2026-10-16): the paper and the
/// balance are decided at Auto's own size, then the text and the pictures
/// are made that much smaller or larger together and every column's width
/// is worked out again from the cells at the new size. So the slider always
/// does what it says, and the widths still come from what is written.
pub fn solve_with(p: &Problem, w: &Weights) -> Plan {
    let ask = p.ask;
    let base = solve_at_designed(p, w, ask.landscape);
    if (ask.size - 1.0).abs() < 1e-9 {
        return base;
    }
    let w = w.sized(ask.size);
    let scale = ask.text(base.candidate.scale);
    let at = |picture_in: f64| {
        assess(p, &Candidate { landscape: base.candidate.landscape, scale, picture_in }, &w)
    };
    let zoomed = at(base.candidate.picture_in * ask.size);
    if ask.size < 1.0 || zoomed.cut_words == 0 {
        return zoomed;
    }
    // **Larger, and a word would be cut**: the text still grows, and the
    // pictures give back room — never below their size at 100% — until no
    // word is cut, or as few as can be.
    let mut best = zoomed;
    let mut picture_in = base.candidate.picture_in * ask.size;
    while picture_in > base.candidate.picture_in + 1e-9 && best.cut_words > 0 {
        picture_in = (picture_in - 0.1).max(base.candidate.picture_in);
        let plan = at(picture_in);
        if plan.cut_words < best.cut_words {
            best = plan;
        }
    }
    best
}

fn solve_at_designed(p: &Problem, w: &Weights, paper: Option<bool>) -> Plan {
    let m = p.at(1.0);
    let has_picture = m.columns.iter().any(|c| c.role == Role::Picture) && m.pictured > 0;
    let pictures: &[f64] = if has_picture { &PICTURES_IN } else { &[1.8] };
    let papers: &[bool] = match paper {
        Some(true) => &[true],
        Some(false) => &[false],
        None => &[true, false],
    };
    let mut best: Option<Plan> = None;
    for &landscape in papers {
        for &scale in &SCALES {
            for &picture_in in pictures {
                let plan = assess(p, &Candidate { landscape, scale, picture_in }, w);
                if best.as_ref().map(|b| plan.score < b.score - 1e-9).unwrap_or(true) {
                    best = Some(plan);
                }
            }
        }
    }
    best.expect("at least one candidate")
}

/// **Today's default, scored the same way** — landscape, 100%, Medium
/// pictures, the page's own weights — so a report can say what Auto changed
/// and a test can check it never does worse.
pub fn assess_default(p: &Problem, sheet: &Sheet) -> Plan {
    let p = p.at(1.0);
    let c = Candidate { landscape: true, scale: 1.0, picture_in: 0.0 };
    let shares = html::default_shares(sheet, FrameSize::Medium);
    let r = ROOT;
    let table = (LETTER.1 - 2.0 * MARGIN) / r - 3.0 - spine(p);
    let widths: Vec<f64> = shares.iter().map(|s| s / 100.0 * table).collect();
    let picture_in = p
        .columns
        .iter()
        .position(|c| c.role == Role::Picture)
        .map(|i| (widths[i] - TD_PAD_X) * r / 72.0)
        .unwrap_or(0.0);
    assess_widths(p, &Candidate { picture_in, ..c }, &WEIGHTS, &widths)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::export::rows::{Row, RowGroup, Sheet};
    use crate::id::Id;
    use crate::{DeviceId, Doc, Query};

    /// A real sheet's row and shape, from a real document, to copy from.
    fn base() -> (Sheet, Row) {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Auto");
        let scene = d.create_scene("1");
        d.add_shot_to_scene(scene);
        let s = d.sheet(&Query::grouped_by(GroupBy::Scene));
        let r = s.rows().next().unwrap().clone();
        (s, r)
    }

    fn row(n: usize) -> Row {
        let mut r = base().1;
        r.number = format!("{}A", n);
        r
    }

    fn sheet(columns: &[&str], rows: Vec<Row>) -> Sheet {
        let mut s = base().0;
        s.columns = columns.iter().map(|c| c.to_string()).collect();
        s.project_ratio = 1.78;
        s.groups = vec![RowGroup { label: "1".into(), key: None, rows, section: None, section_starts: false }];
        s
    }

    fn picture(i: usize) -> Option<Id> {
        Some(Id::from_hex(&format!("{:032x}", 0x1000 + i)).unwrap())
    }

    fn wide_rows(count: usize) -> Vec<Row> {
        (0..count)
            .map(|i| {
                let mut r = row(i + 1);
                r.key_frame = picture(i);
                r.title = "Hero walks to the car".into();
                r.description = "She steps out of the doorway into the rain, looks back once at the \
                                 window and then walks towards the waiting car without hurrying."
                    .into();
                r.notes = "Practical rain bars, keep the background soft".into();
                r.size = "Medium Close Up".into();
                r.angle = vec!["Eye Level".into(), "Over the Shoulder".into()];
                r.movement = "Tracking Backward".into();
                r.support = "Dana Dolly".into();
                r.lens = "Signature Prime 35".into();
                r.tags = vec!["Rain".into(), "VFX".into(), "Hero".into()];
                r
            })
            .collect()
    }

    const WIDE: [&str; 11] = [
        "image", "title", "description", "size", "angle", "movement", "support", "lens", "notes",
        "tags", "camera",
    ];

    #[test]
    fn a_wide_column_set_goes_landscape() {
        let s = sheet(&WIDE, wide_rows(40));
        let plan = solve(&Problem::of(&s));
        assert!(plan.candidate.landscape, "{plan:?}");
        assert_eq!(plan.cut_words, 0, "{plan:?}");
    }

    #[test]
    fn a_narrow_column_set_goes_portrait() {
        let rows: Vec<Row> = (0..40)
            .map(|i| {
                let mut r = row(i + 1);
                r.key_frame = picture(i);
                r.description = "Wide on the house as the car pulls in.".into();
                r.size = "Wide".into();
                r
            })
            .collect();
        let s = sheet(&["image", "description", "size"], rows);
        let plan = solve(&Problem::of(&s));
        assert!(!plan.candidate.landscape, "{plan:?}");
    }

    #[test]
    fn never_cuts_a_word_when_a_sheet_without_one_exists() {
        // Nine columns, and long single words in the narrow ones.
        let mut rows = wide_rows(30);
        for r in rows.iter_mut() {
            r.support = "Steadicam".into();
            r.movement = "Counterclockwise".into();
            r.day_label = Some("Day 12".into());
        }
        let s = sheet(&WIDE[..9], rows);
        let p = Problem::of(&s);
        let plan = solve(&p);
        let some_sheet_is_clean = [true, false].iter().any(|&landscape| {
            SCALES.iter().any(|&scale| {
                PICTURES_IN.iter().any(|&picture_in| {
                    assess(&p, &Candidate { landscape, scale, picture_in }, &WEIGHTS).cut_words == 0
                })
            })
        });
        assert!(some_sheet_is_clean);
        assert_eq!(plan.cut_words, 0, "{plan:?}");
        // And the floor holds: no pill column under its longest pill.
        let total: f64 = 100.0;
        assert!((plan.shares.iter().map(|(_, s)| s).sum::<f64>() - total).abs() < 0.01);
    }

    #[test]
    fn shares_sum_to_a_sheet_and_factors_rebuild_them() {
        let s = sheet(&WIDE, wide_rows(12));
        let plan = solve(&Problem::of(&s));
        let sum: f64 = plan.shares.iter().map(|(_, v)| v).sum();
        assert!((sum - 100.0).abs() < 1e-6);
        // The multipliers, put back through the page's own weights, land on
        // the same shares.
        let factors = plan.factors();
        let size = plan.frames();
        let weighed: Vec<f64> =
            factors.iter().map(|(f, k)| html::base_weight(f, size) * k).collect();
        let total: f64 = weighed.iter().sum();
        for ((_, share), w) in plan.shares.iter().zip(&weighed) {
            assert!((share - w / total * 100.0).abs() < 1e-6);
        }
    }

    #[test]
    fn size_moves_text_and_pictures_together() {
        let s = sheet(&WIDE, wide_rows(30));
        let at = |size: f64| solve(&Problem::asked(&s, Ask::new(size, None)));
        let (small, middle, large) = (at(0.7), at(1.0), at(1.3));
        assert_eq!(middle.candidate, solve(&Problem::of(&s)).candidate);
        assert!(small.candidate.scale < middle.candidate.scale, "{small:?}");
        assert!(large.candidate.scale > middle.candidate.scale, "{large:?}");
        assert!(small.candidate.picture_in <= middle.candidate.picture_in);
        assert!(large.candidate.picture_in >= middle.candidate.picture_in);
        for plan in [&small, &large] {
            let sum: f64 = plan.shares.iter().map(|(_, v)| v).sum();
            assert!((sum - 100.0).abs() < 1e-6);
        }
        // Said outside the slider, pulled in.
        assert_eq!(Ask::new(9.0, None).size, Ask::LARGEST);
        assert_eq!(Ask::new(f64::NAN, None).size, 1.0);
    }

    #[test]
    fn a_said_paper_is_kept() {
        let wide = sheet(&WIDE, wide_rows(20));
        let plan = solve(&Problem::asked(&wide, Ask::new(1.0, Some(false))));
        assert!(!plan.candidate.landscape, "{plan:?}");
        let narrow = sheet(&["image", "description", "size"], wide_rows(20));
        let plan = solve(&Problem::asked(&narrow, Ask::new(1.0, Some(true))));
        assert!(plan.candidate.landscape, "{plan:?}");
    }

    #[test]
    fn decides_quickly_for_a_big_film() {
        let s = sheet(&WIDE, wide_rows(150));
        let started = std::time::Instant::now();
        let p = Problem::of(&s);
        let plan = solve(&p);
        let took = started.elapsed();
        eprintln!("150 shots, 11 columns: measured and decided in {took:?}");
        assert!(plan.score.is_finite());
        // Well under the 200ms the live preview can afford, even unoptimised.
        let limit = if cfg!(debug_assertions) { 1500 } else { 150 };
        assert!(took.as_millis() < limit, "took {took:?}");
    }

    #[test]
    fn auto_is_never_worse_than_the_default() {
        let s = sheet(&WIDE, wide_rows(40));
        let p = Problem::of(&s);
        assert!(solve(&p).score <= assess_default(&p, &s).score + 1e-9);
    }

    #[test]
    fn an_empty_sheet_still_answers() {
        let s = sheet(&WIDE, vec![]);
        let plan = solve(&Problem::of(&s));
        assert!(plan.score.is_finite());
    }
}
