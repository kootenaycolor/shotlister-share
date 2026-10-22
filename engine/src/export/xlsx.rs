//! The spreadsheet.
//!
//! The escape hatch: a file that opens in Google Sheets already looking like the
//! working template, for the days when somebody does not want to use the app.
//!
//! What it carries: the columns in the order the real sheets use them, a green
//! header, frozen so it stays put, filters on every column, grouping with a
//! count in the band, striped rows, cameras in their own colour, struck shots
//! ruled through, dropdowns on the vocabulary columns driven by the project's
//! own master lists, and the shot's frames combined into the one picture the
//! Image column can hold.
//!
//! Angle and Tags deliberately get no dropdown — they hold several values at
//! once, and a single-select list would be a lie about what the field is.
//!
//! Two shapes come out of here. `write` is the quick one sheet, used where a
//! single table is all that is wanted. `workbook` is his own file, exactly:
//! four tabs — Master Shot List, Group by Day, Group by Sequence, Ranges —
//! measured off `DAYBREAK - SHOT LIST.xlsx` rather than guessed.
//!
//! Bytes come from the caller, as everywhere else in the engine. The engine says
//! which frames a row has and in what order; the caller composites them.

use std::collections::HashMap;

use crate::columns::label_for;
use crate::export::rows::Sheet;
use crate::export::zip::ZipWriter;
use crate::id::Id;
use crate::query::GroupBy;
use crate::vocab;

/// Never toggled, never part of `sheet.columns` — a spreadsheet wants a
/// stable identity on the left no matter which content columns the project
/// has configured. There is no `Struck` column here either: a struck shot
/// keeps its place and is ruled through instead, which is what his sheets
/// do too — see `main_sheet`'s filter on `sheet.columns`.
///
/// **`Order` lived here and is gone** — his call, 2026-08-28. It had no
/// equivalent anywhere in the app, was blank on write, and existed only
/// because his own working file happened to have a column for a first AD's
/// shooting order. Removing it is exactly the same reasoning that put Title
/// back in: this file's columns are the project's, not a template's.
const FIXED_HEADERS: [(&str, f32); 2] = [("Scene #", 11.0), ("Shot #", 12.0)];

/// Width in characters for a project-configured column — everything after
/// `FIXED_HEADERS`. His ask, 2026-08-27: "the project informs what's in the
/// xls," so this file's columns follow `sheet.columns` exactly, in the app's
/// own order, rather than a fixed list measured off one working file.
/// Widened generously on the long-text fields, 2026-08-28 — his report that
/// text was bunching up — rather than measured tight against one sample.
fn column_width(field: &str) -> f32 {
    match field {
        "day" => 7.0,
        "image" => 22.0,
        "title" => 28.0,
        "description" => 56.0,
        "script" => 48.0,
        "size" => 14.0,
        "angle" => 14.0,
        "movement" => 17.0,
        "camera" => 18.0,
        "lens" => 16.0,
        "modifiers" => 16.0,
        "lens_filters" => 16.0,
        "support" => 17.0,
        "notes" => 32.0,
        "tags" => 24.0,
        "sequence" => 16.0,
        _ => 16.0,
    }
}

/// How many lines of wrapped text a field needs at its own column's width —
/// a greedy word-wrap simulation, the same shape a real layout does, so a
/// row with a picture but a long description does not end up too short for
/// its own text. His ask, 2026-08-28: images should set the row's height
/// *unless* a text field needs more.
fn wrapped_lines(text: &str, column_chars: f32) -> u32 {
    let budget = column_chars.max(4.0) as usize;
    let mut lines = 1u32;
    let mut col = 0usize;
    for word in text.split_whitespace() {
        let word_len = word.chars().count();
        if col > 0 && col + 1 + word_len > budget {
            lines += 1;
            col = 0;
        }
        if col > 0 {
            col += 1;
        }
        col += word_len;
        // A single word longer than the column keeps wrapping within itself
        // rather than stretching the estimate to one enormous line.
        while col > budget {
            lines += 1;
            col -= budget;
        }
    }
    lines.max(1)
}

/// The tallest a row's own text needs to be, across whichever long-text
/// fields are actually on this sheet — only these three wrap to more than a
/// line or two in practice, the same fields `column_width` gives real room.
const WRAPPING_TEXT_FIELDS: [&str; 3] = ["title", "description", "notes"];

/// Which Ranges column a project-configured column's dropdown draws from —
/// `None` for a column with no dropdown at all. Angle and Tags hold several
/// values at once, so neither is here even though his own sheet gives Tags
/// one: a single-select list on a multi-value cell would overwrite the
/// others the moment it was used.
fn dropdown_list_name(field: &str) -> Option<&'static str> {
    match field {
        "size" => Some("Shot Size"),
        "movement" => Some("Movement"),
        "camera" => Some("Camera"),
        "lens" => Some("Lens"),
        "support" => Some("Equipment"),
        "sequence" => Some("Sequences"),
        _ => None,
    }
}

/// A project-configured column's plain-text value for one row. `image` is not
/// here — the picture sits over that cell instead, placed separately.
fn field_text(row: &crate::export::rows::Row, field: &str) -> String {
    match field {
        "title" => row.title.clone(),
        "description" => row.description.clone(),
        "script" => row.script.clone(),
        "size" => row.size.clone(),
        "angle" => row.angle.join(", "),
        "movement" => row.movement.clone(),
        "camera" => row.camera.as_ref().map(|c| c.display()).unwrap_or_default(),
        "lens" => row.lens_cell(),
        "modifiers" => row.modifiers.join(", "),
        "lens_filters" => row.lens_filters.join(", "),
        "support" => row.support.clone(),
        "notes" => row.notes.clone(),
        "tags" => row.tags.join(", "),
        "day" => row.day_label.clone().unwrap_or_default(),
        "sequence" => row.sequence.clone().unwrap_or_default(),
        // One the project made for itself, by its slug.
        other => row
            .own
            .iter()
            .find(|(slug, _)| slug == other)
            .map(|(_, words)| words.clone())
            .unwrap_or_default(),
    }
}

/// His own header green, measured off `DAYBREAK - SHOT LIST.xlsx`.
const HEADER_GREEN: &str = "FF356854";
const STRIPE: &str = "FFF4F7F5";
const GROUP_BAND: &str = "FFE3EDE6";

/// Frames are drawn at this width, and shortened if that would make them too
/// tall for a row anybody wants to scroll past.
const FRAME_WIDTH_PX: u32 = 118;
const FRAME_MAX_HEIGHT_PX: u32 = 92;

/// Spreadsheets measure in English Metric Units. 9525 to the pixel at 96dpi.
const EMU_PER_PX: u32 = 9525;
const PT_PER_PX: f32 = 0.75;
/// A wrapped line of the 10pt body text, with its own leading — used only to
/// estimate how tall a row's text needs to be, never to draw anything.
const LINE_HEIGHT_PT: f32 = 12.5;

/// A frame, supplied by the caller. The engine never reads a file.
#[derive(Clone, Debug)]
pub struct Frame {
    pub bytes: Vec<u8>,
    /// `png`, `jpeg`, `gif` — used for the part name and the content type.
    pub extension: String,
    pub width: u32,
    pub height: u32,
    /// Where this picture can be fetched from, when it can be.
    ///
    /// **Given, the frame becomes the cell's own value instead of a sticker
    /// over it** — see `formula`. Absent, nothing changes: the bytes are
    /// carried in the file and pasted over the grid, which is what a workbook
    /// nobody can reach the internet from still needs.
    pub url: Option<String>,
}

/// Turns a shot's frames into the one picture that goes in its Image cell.
///
/// A sheet has one picture per row — that is all a spreadsheet can do — but a
/// shot with four storyboard panels should not have three of them thrown away.
/// The caller is given every frame on the shot and composites them side by side;
/// the engine says which frames and in what order, and never touches bytes.
///
/// Returning `None` leaves that cell empty.
pub type Frames<'a> = &'a dyn Fn(&[Id]) -> Option<Frame>;

/// For a sheet of data with no pictures in it.
pub fn no_frames(_: &[Id]) -> Option<Frame> {
    None
}

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            // Control characters are not legal in XML and will refuse to open.
            c if (c as u32) < 0x20 && c != '\t' && c != '\n' && c != '\r' => out.push(' '),
            other => out.push(other),
        }
    }
    out
}

/// 0 -> A, 25 -> Z, 26 -> AA
fn column_letter(index: usize) -> String {
    let mut n = index + 1;
    let mut out = Vec::new();
    while n > 0 {
        n -= 1;
        out.push((b'A' + (n % 26) as u8) as char);
        n /= 26;
    }
    out.iter().rev().collect()
}

/// Displayed size for a frame, keeping its shape.
fn frame_size(width: u32, height: u32) -> (u32, u32) {
    if width == 0 || height == 0 {
        return (FRAME_WIDTH_PX, FRAME_MAX_HEIGHT_PX);
    }
    let scaled_height = (FRAME_WIDTH_PX as f64 * height as f64 / width as f64).round() as u32;
    if scaled_height <= FRAME_MAX_HEIGHT_PX {
        (FRAME_WIDTH_PX, scaled_height.max(1))
    } else {
        // Tall frame — fit the height and let it be narrower.
        let scaled_width =
            (FRAME_MAX_HEIGHT_PX as f64 * width as f64 / height as f64).round() as u32;
        (scaled_width.max(1), FRAME_MAX_HEIGHT_PX)
    }
}

// ---- styles ------------------------------------------------------------

#[derive(Default)]
struct Styles {
    fonts: Vec<String>,
    xfs: Vec<(usize, usize, usize, bool)>,
    seen: HashMap<(usize, usize, usize, bool), usize>,
    colour_fonts: HashMap<String, usize>,
}

/// Fill slots. The first two are fixed by the format and cannot be reused.
const FILL_NONE: usize = 0;
const FILL_HEADER: usize = 2;
const FILL_STRIPE: usize = 3;
const FILL_GROUP: usize = 4;

const BORDER_NONE: usize = 0;
const BORDER_BOTTOM: usize = 1;

const FONT_BASE: usize = 0;
const FONT_HEADER: usize = 1;
const FONT_GROUP: usize = 2;
const FONT_STRUCK: usize = 3;
/// **The one column meant to be read first** — same reasoning as `td.title`
/// in `html.rs`, his ask there on 2026-08-24 and again here on 2026-08-28:
/// more weight than a plain cell, the way a headline sits over its body.
const FONT_TITLE: usize = 4;

impl Styles {
    fn new() -> Styles {
        let mut styles = Styles {
            fonts: vec![
                r#"<font><sz val="10"/><name val="Helvetica Neue"/></font>"#.to_string(),
                r#"<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Helvetica Neue"/></font>"#.to_string(),
                r#"<font><b/><sz val="11"/><color rgb="FF16201B"/><name val="Helvetica Neue"/></font>"#.to_string(),
                r#"<font><strike/><sz val="10"/><color rgb="FF75827A"/><name val="Helvetica Neue"/></font>"#.to_string(),
                r#"<font><b/><sz val="10"/><name val="Helvetica Neue"/></font>"#.to_string(),
            ],
            ..Default::default()
        };
        // Slot 0 is the default style and must stay plain.
        styles.xf(FONT_BASE, FILL_NONE, BORDER_NONE, false);
        styles
    }

    fn xf(&mut self, font: usize, fill: usize, border: usize, wrap: bool) -> usize {
        let key = (font, fill, border, wrap);
        if let Some(existing) = self.seen.get(&key) {
            return *existing;
        }
        let index = self.xfs.len();
        self.xfs.push(key);
        self.seen.insert(key, index);
        index
    }

    /// A bold font in a camera's own colour, so A-Cam and B-Cam read apart at a
    /// glance the way they do in the sheets.
    fn colour_font(&mut self, hex: &str) -> usize {
        let rgb = normalise_colour(hex);
        if let Some(existing) = self.colour_fonts.get(&rgb) {
            return *existing;
        }
        let index = self.fonts.len();
        self.fonts.push(format!(
            r#"<font><b/><sz val="10"/><color rgb="{rgb}"/><name val="Helvetica Neue"/></font>"#
        ));
        self.colour_fonts.insert(rgb, index);
        index
    }

    fn to_xml(&self) -> String {
        let fills = format!(
            r#"<fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="{HEADER_GREEN}"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="{STRIPE}"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="{GROUP_BAND}"/><bgColor indexed="64"/></patternFill></fill></fills>"#
        );
        let borders = r#"<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFD8E0DA"/></bottom><diagonal/></border></borders>"#;

        let mut cell_xfs = String::new();
        for (font, fill, border, wrap) in &self.xfs {
            let alignment = if *wrap {
                r#"<alignment vertical="top" wrapText="1"/>"#
            } else {
                r#"<alignment vertical="top"/>"#
            };
            cell_xfs.push_str(&format!(
                r#"<xf numFmtId="0" fontId="{font}" fillId="{fill}" borderId="{border}" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">{alignment}</xf>"#
            ));
        }

        format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="{}">{}</fonts>{fills}{borders}<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="{}">{cell_xfs}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#,
            self.fonts.len(),
            self.fonts.join(""),
            self.xfs.len()
        )
    }
}

/// Accepts `#rrggbb`, `rrggbb` or `AARRGGBB` and returns the eight-digit form
/// the format wants. Anything unreadable falls back to the body colour rather
/// than producing a file that will not open.
fn normalise_colour(hex: &str) -> String {
    let trimmed = hex.trim().trim_start_matches('#');
    match trimmed.len() {
        6 if trimmed.chars().all(|c| c.is_ascii_hexdigit()) => {
            format!("FF{}", trimmed.to_uppercase())
        }
        8 if trimmed.chars().all(|c| c.is_ascii_hexdigit()) => trimmed.to_uppercase(),
        _ => "FF16201B".to_string(),
    }
}

// ---- cells -------------------------------------------------------------

fn cell(reference: &str, style: usize, text: &str) -> String {
    if text.is_empty() {
        // Still emitted, so the stripe and the borders carry across the row.
        format!(r#"<c r="{reference}" s="{style}"/>"#)
    } else {
        format!(
            r#"<c r="{reference}" s="{style}" t="inlineStr"><is><t xml:space="preserve">{}</t></is></c>"#,
            esc(text)
        )
    }
}

/// A cell the spreadsheet works out for itself.
///
/// **This is the whole of "a picture inside a cell".** A spreadsheet file has
/// no way to make a picture the *contents* of a cell — every picture in one is
/// a drawing floating over the grid, pinned to a corner, which is why sorting
/// a list has always left the frames behind. A formula is contents, so a frame
/// written as `IMAGE(...)` travels with its row, resizes with it and filters
/// with it, because it is no longer a separate thing that happens to be on top.
///
/// **It only comes alive in Google Sheets**, which is where his workbook lives.
/// Measured 2026-09-04 against his own account: both `IMAGE(...)` and Excel's
/// `_xlfn.IMAGE(...)` render from an `.xlsx`, a Z→A sort carried every picture
/// with its row, and Sheets refuses a picture carried inside the formula
/// ("is not a valid url") — which is why the address has to be real and
/// reachable. Numbers and LibreOffice have no such function and will show an
/// error here instead of a frame; his ruling, 2026-09-04, is that this is the
/// right trade because the file is opened in Sheets.
fn formula(reference: &str, style: usize, body: &str) -> String {
    // **Quotes are left alone here, unlike everywhere else in this file.** A
    // formula is full of them, `"` needs no escaping in element text, and
    // `esc` turns every one into `&quot;` — legal, and resolved by any
    // conforming parser, but it makes the one part of the file a person might
    // ever read by hand unreadable and asks a formula parser to depend on
    // entity handling it has no reason to be good at. Only the three
    // characters that genuinely cannot appear in text are replaced.
    let mut body_xml = String::with_capacity(body.len());
    for ch in body.chars() {
        match ch {
            '&' => body_xml.push_str("&amp;"),
            '<' => body_xml.push_str("&lt;"),
            '>' => body_xml.push_str("&gt;"),
            c if (c as u32) < 0x20 => body_xml.push(' '),
            other => body_xml.push(other),
        }
    }
    format!(r#"<c r="{reference}" s="{style}"><f>{body_xml}</f></c>"#)
}

// ---- the hidden list sheet ---------------------------------------------

struct Lists {
    columns: Vec<(String, Vec<String>)>,
}

impl Lists {
    fn column_of(&self, name: &str) -> Option<usize> {
        self.columns.iter().position(|(n, _)| n == name)
    }

    fn to_xml(&self, styles: &mut Styles) -> String {
        let header = styles.xf(FONT_HEADER, FILL_HEADER, BORDER_NONE, false);
        let body = styles.xf(FONT_BASE, FILL_NONE, BORDER_NONE, false);

        let longest = self.columns.iter().map(|(_, v)| v.len()).max().unwrap_or(0);
        let mut rows = String::new();

        let mut head = String::new();
        for (index, (name, _)) in self.columns.iter().enumerate() {
            head.push_str(&cell(&format!("{}1", column_letter(index)), header, name));
        }
        rows.push_str(&format!(r#"<row r="1">{head}</row>"#));

        for line in 0..longest {
            let mut cells = String::new();
            for (index, (_, values)) in self.columns.iter().enumerate() {
                if let Some(value) = values.get(line) {
                    cells.push_str(&cell(
                        &format!("{}{}", column_letter(index), line + 2),
                        body,
                        value,
                    ));
                }
            }
            if !cells.is_empty() {
                rows.push_str(&format!(r#"<row r="{}">{cells}</row>"#, line + 2));
            }
        }

        format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>{rows}</sheetData></worksheet>"#
        )
    }
}

fn gather_lists(sheet: &Sheet, vocabulary: &dyn Fn(&str) -> Vec<String>) -> Lists {
    // Cameras and sequences come from what the shots actually use rather than
    // from a list, so each dropdown offers exactly what this production has —
    // the same reasoning for both, so they are gathered together.
    let mut cameras: Vec<String> = Vec::new();
    let mut sequences: Vec<String> = Vec::new();
    for row in sheet.rows() {
        if let Some(camera) = &row.camera {
            let display = camera.display();
            if !display.is_empty() && !cameras.contains(&display) {
                cameras.push(display);
            }
        }
        if let Some(sequence) = &row.sequence {
            if !sequence.is_empty() && !sequences.contains(sequence) {
                sequences.push(sequence.clone());
            }
        }
    }

    // **Exactly the lists Project Settings calls "Lists"** — his ask,
    // 2026-08-27: "RANGES are what are in our Lists within Project
    // Settings." `vocab::ALL` is the same fields that rail shows, in
    // their own words (`label_for`), so Priority and POV appear here now —
    // they never did before. Camera and Sequence are not simple word-lists —
    // one is a record with a colour, the other an actual sequence a shot
    // points at — so those two stay gathered from what the shots actually
    // use rather than a master list, exactly as before.
    let mut columns: Vec<(String, Vec<String>)> = vocab::ALL
        .iter()
        .map(|field| (label_for(field).to_string(), vocabulary(field)))
        .collect();
    columns.push(("Camera".to_string(), cameras));
    columns.push(("Sequences".to_string(), sequences));

    Lists { columns }
}

// ---- pictures ----------------------------------------------------------

/// A frame, and the row it sits on.
struct Placed {
    row: u32,
    image: usize,
    width_px: u32,
    height_px: u32,
}

/// The distinct pictures used, so the same set of frames on eight rows is
/// stored once.
struct Pictures {
    /// Where the Image column actually landed this time — it moves with
    /// `sheet.columns`, same as everything else now, so the drawing has to
    /// be told rather than assuming a fixed spot.
    image_column: usize,
    files: Vec<Frame>,
    by_frames: HashMap<String, usize>,
    placed: Vec<Placed>,
}

impl Pictures {
    fn new(image_column: usize) -> Pictures {
        Pictures {
            image_column,
            files: Vec::new(),
            by_frames: HashMap::new(),
            placed: Vec::new(),
        }
    }

    fn place(&mut self, key: String, frame: Frame, row: u32) -> u32 {
        let index = match self.by_frames.get(&key) {
            Some(existing) => *existing,
            None => {
                let index = self.files.len();
                self.by_frames.insert(key, index);
                self.files.push(frame.clone());
                index
            }
        };
        let (width_px, height_px) = frame_size(frame.width, frame.height);
        self.placed.push(Placed {
            row,
            image: index,
            width_px,
            height_px,
        });
        height_px
    }

    fn is_empty(&self) -> bool {
        self.placed.is_empty()
    }

    fn drawing_xml(&self) -> String {
        let mut anchors = String::new();
        for (n, placed) in self.placed.iter().enumerate() {
            let cx = placed.width_px * EMU_PER_PX;
            let cy = placed.height_px * EMU_PER_PX;
            let rel = placed.image + 1;
            let col = self.image_column;
            anchors.push_str(&format!(
                r#"<xdr:oneCellAnchor><xdr:from><xdr:col>{col}</xdr:col><xdr:colOff>28575</xdr:colOff><xdr:row>{}</xdr:row><xdr:rowOff>28575</xdr:rowOff></xdr:from><xdr:ext cx="{cx}" cy="{cy}"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="{}" name="Frame {}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId{rel}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>"#,
                placed.row - 1,
                n + 1,
                n + 1
            ));
        }
        format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">{anchors}</xdr:wsDr>"#
        )
    }

    fn drawing_rels(&self) -> String {
        let mut rels = String::new();
        for (index, frame) in self.files.iter().enumerate() {
            rels.push_str(&format!(
                r#"<Relationship Id="rId{}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image{}.{}"/>"#,
                index + 1,
                index + 1,
                frame.extension
            ));
        }
        format!(
            r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{rels}</Relationships>"#
        )
    }

    fn extensions(&self) -> Vec<String> {
        let mut seen: Vec<String> = Vec::new();
        for frame in &self.files {
            if !seen.contains(&frame.extension) {
                seen.push(frame.extension.clone());
            }
        }
        seen
    }
}

fn content_type_for(extension: &str) -> &'static str {
    match extension {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        _ => "application/octet-stream",
    }
}

// ---- the main sheet ----------------------------------------------------

fn main_sheet(
    sheet: &Sheet,
    lists: &Lists,
    // The tab a dropdown's formula points at — "Lists" in the quick
    // single-sheet export, "Ranges" in his four-tab workbook. Getting this
    // wrong does not error; Excel just shows no list at all, which is what
    // happened before this was a parameter.
    lists_sheet_name: &str,
    styles: &mut Styles,
    frames: Frames,
) -> (String, Pictures) {
    let header_style = styles.xf(FONT_HEADER, FILL_HEADER, BORDER_NONE, true);
    let group_style = styles.xf(FONT_GROUP, FILL_GROUP, BORDER_BOTTOM, false);
    let plain = styles.xf(FONT_BASE, FILL_NONE, BORDER_BOTTOM, true);
    let striped = styles.xf(FONT_BASE, FILL_STRIPE, BORDER_BOTTOM, true);
    let struck_plain = styles.xf(FONT_STRUCK, FILL_NONE, BORDER_BOTTOM, true);
    let struck_striped = styles.xf(FONT_STRUCK, FILL_STRIPE, BORDER_BOTTOM, true);
    let title_plain = styles.xf(FONT_TITLE, FILL_NONE, BORDER_BOTTOM, true);
    let title_striped = styles.xf(FONT_TITLE, FILL_STRIPE, BORDER_BOTTOM, true);

    // **The project informs what's in the xls** — his ask, 2026-08-27.
    // `sheet.columns` is the on-screen Table view, exactly, in its own
    // order; the fixed identity block ahead of it has no on-screen
    // equivalent to follow. `struck` is dropped even when it is showing on
    // screen — a cut shot is already ruled through below, and a text column
    // saying so again would say it twice.
    let dynamic: Vec<&str> = sheet
        .columns
        .iter()
        .map(|s| s.as_str())
        .filter(|c| *c != "struck")
        .collect();
    let column_count = FIXED_HEADERS.len() + dynamic.len();
    let image_column = dynamic.iter().position(|c| *c == "image").map(|i| i + FIXED_HEADERS.len());

    let mut pictures = Pictures::new(image_column.unwrap_or(0));
    let mut body = String::new();
    let mut merges: Vec<String> = Vec::new();
    let mut line = 1u32;

    let mut header_cells = String::new();
    for (index, (name, _)) in FIXED_HEADERS.iter().enumerate() {
        header_cells.push_str(&cell(&format!("{}1", column_letter(index)), header_style, name));
    }
    for (offset, field) in dynamic.iter().enumerate() {
        header_cells.push_str(&cell(
            &format!("{}1", column_letter(FIXED_HEADERS.len() + offset)),
            header_style,
            sheet
                .own_columns
                .iter()
                .find(|(slug, _)| slug == field)
                .map(|(_, label)| label.as_str())
                .unwrap_or_else(|| label_for(field)),
        ));
    }
    body.push_str(&format!(
        r#"<row r="1" ht="22" customHeight="1">{header_cells}</row>"#
    ));

    // Striping restarts inside each group, so the band always reads as row one.
    // Flat is not a group — it is the whole list read straight through — so it
    // gets no band at all, matching the Master tab in his own file, which is a
    // plain table starting at row two.
    let mut stripe;
    for group in &sheet.groups {
        if sheet.grouped_by != GroupBy::Flat {
            line += 1;
            let label = format!("{} — {} shots", group.label, group.count());
            let mut cells = cell(&format!("A{line}"), group_style, &label);
            for index in 1..column_count {
                cells.push_str(&cell(
                    &format!("{}{}", column_letter(index), line),
                    group_style,
                    "",
                ));
            }
            body.push_str(&format!(
                r#"<row r="{line}" ht="20" customHeight="1">{cells}</row>"#
            ));
            merges.push(format!("A{line}:{}{line}", column_letter(column_count - 1)));
        }
        stripe = false;

        for row in &group.rows {
            line += 1;
            let row_striped = stripe;
            stripe = !stripe;

            let base = match (row.struck, row_striped) {
                (true, true) => struck_striped,
                (true, false) => struck_plain,
                (false, true) => striped,
                (false, false) => plain,
            };

            // Every frame on the shot goes to the caller, which composites them
            // into the one picture the Image column can hold. The row grows to
            // fit whatever comes back — only when there is an Image column to
            // hold it at all; a project that has hidden Storyboard should not
            // get a picture floating over whichever cell took its place.
            let mut row_height: Option<u32> = None;
            let mut image_formula: Option<String> = None;
            if image_column.is_some() && !row.frames.is_empty() {
                if let Some(frame) = frames(&row.frames) {
                    match &frame.url {
                        // **Reachable, so it belongs to the cell.** Nothing is
                        // carried in the file at all in this case — the row is
                        // still grown to the size the picture will draw at, so
                        // the sheet looks the same either way.
                        Some(address) => {
                            let (_, height_px) = frame_size(frame.width, frame.height);
                            image_formula = Some(format!(r#"IMAGE("{address}")"#));
                            row_height = Some(height_px);
                        }
                        // Keyed by the whole set, so two rows showing the same
                        // frames share one picture and two rows showing different
                        // ones do not collide.
                        None => {
                            let key = row
                                .frames
                                .iter()
                                .map(|id| id.to_hex())
                                .collect::<Vec<_>>()
                                .join(",");
                            let height = pictures.place(key, frame, line);
                            row_height = Some(height);
                        }
                    }
                }
            }

            // A struck row keeps its rule-through rather than gaining a colour
            // or, for Title, weight — both below follow the same rule.
            let camera_style = match (&row.camera, row.struck) {
                (Some(camera), false) => match &camera.colour {
                    Some(colour) => {
                        let font = styles.colour_font(colour);
                        let fill = if row_striped { FILL_STRIPE } else { FILL_NONE };
                        styles.xf(font, fill, BORDER_BOTTOM, true)
                    }
                    None => base,
                },
                _ => base,
            };
            let title_style = if row.struck {
                base
            } else if row_striped {
                title_striped
            } else {
                title_plain
            };

            let mut cells = cell(&format!("A{line}"), base, &row.scene_number);
            cells.push_str(&cell(&format!("B{line}"), base, &row.number));
            for (offset, field) in dynamic.iter().enumerate() {
                let index = FIXED_HEADERS.len() + offset;
                let reference = format!("{}{line}", column_letter(index));
                if *field == "image" {
                    // A picture with an address is what this cell *is*; one
                    // without still floats over an empty cell, as it always did.
                    cells.push_str(&match &image_formula {
                        Some(body) => formula(&reference, base, body),
                        None => cell(&reference, base, ""),
                    });
                    continue;
                }
                let (text, style) = match *field {
                    "camera" => (
                        row.camera.as_ref().map(|c| c.display()).unwrap_or_default(),
                        camera_style,
                    ),
                    "title" => (row.title.clone(), title_style),
                    other => (field_text(row, other), base),
                };
                cells.push_str(&cell(&reference, style, &text));
            }

            // **The image sets the row's height — unless a long text field
            // needs more.** Before this, a picture pinned the row to exactly
            // its own size (`customHeight` stops the usual auto-fit), so a
            // short frame beside a long description cut the text off rather
            // than the row growing for it. Only compared when there is a
            // picture at all — a text-only row already auto-fits correctly
            // and is left alone.
            let height_attr = match row_height {
                Some(px) => {
                    let image_height_pt = px as f32 * PT_PER_PX + 8.0;
                    let text_lines = dynamic
                        .iter()
                        .filter(|field| WRAPPING_TEXT_FIELDS.contains(field))
                        .map(|field| wrapped_lines(&field_text(row, field), column_width(field)))
                        .max()
                        .unwrap_or(1);
                    let text_height_pt = text_lines as f32 * LINE_HEIGHT_PT + 8.0;
                    format!(r#" ht="{:.0}" customHeight="1""#, image_height_pt.max(text_height_pt))
                }
                None => String::new(),
            };
            body.push_str(&format!(r#"<row r="{line}"{height_attr}>{cells}</row>"#));
        }
    }

    let last_column = column_letter(column_count - 1);
    let last_row = line.max(2);

    let mut columns = String::new();
    for (index, (_, width)) in FIXED_HEADERS.iter().enumerate() {
        columns.push_str(&format!(
            r#"<col min="{n}" max="{n}" width="{width}" customWidth="1"/>"#,
            n = index + 1
        ));
    }
    for (offset, field) in dynamic.iter().enumerate() {
        let width = column_width(field);
        columns.push_str(&format!(
            r#"<col min="{n}" max="{n}" width="{width}" customWidth="1"/>"#,
            n = FIXED_HEADERS.len() + offset + 1
        ));
    }

    // Dropdowns for the single-value vocabulary columns only — see
    // `dropdown_list_name`. Only for a column that is actually here: a
    // project that hides Lens on screen gets no Lens dropdown to leave
    // dangling in the file either.
    let mut validations = String::new();
    let mut validation_count = 0;
    for (offset, field) in dynamic.iter().enumerate() {
        let Some(list) = dropdown_list_name(field) else { continue };
        let Some(source) = lists.column_of(list) else { continue };
        let values = &lists.columns[source].1;
        if values.is_empty() {
            continue;
        }
        let letter = column_letter(FIXED_HEADERS.len() + offset);
        let source_letter = column_letter(source);
        validations.push_str(&format!(
            r#"<dataValidation type="list" allowBlank="1" showInputMessage="1" showErrorMessage="0" sqref="{letter}2:{letter}{last_row}"><formula1>{lists_sheet_name}!${source_letter}$2:${source_letter}${}</formula1></dataValidation>"#,
            values.len() + 1
        ));
        validation_count += 1;
    }
    let validations = if validation_count == 0 {
        String::new()
    } else {
        format!(r#"<dataValidations count="{validation_count}">{validations}</dataValidations>"#)
    };

    let merge_xml = if merges.is_empty() {
        String::new()
    } else {
        format!(
            r#"<mergeCells count="{}">{}</mergeCells>"#,
            merges.len(),
            merges
                .iter()
                .map(|r| format!(r#"<mergeCell ref="{r}"/>"#))
                .collect::<Vec<_>>()
                .join("")
        )
    };

    let drawing = if pictures.is_empty() {
        String::new()
    } else {
        r#"<drawing r:id="rId1"/>"#.to_string()
    };
    let namespace = if pictures.is_empty() {
        String::new()
    } else {
        r#" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#
            .to_string()
    };

    // **Frozen both ways** — the header row, same as before, and now the
    // identity block (Order, Scene #, Shot #) too, so scrolling right through
    // however many content columns the project has never loses track of
    // which shot a cell belongs to. His ask, 2026-08-27: "stand on its own"
    // in Google Sheets, which honours a frozen pane on import same as Excel.
    let split_at = column_letter(FIXED_HEADERS.len());
    let pane = format!(
        r#"<pane xSplit="{}" ySplit="1" topLeftCell="{split_at}2" activePane="bottomRight" state="frozen"/>"#,
        FIXED_HEADERS.len()
    );

    // Element order is fixed by the format: cols, sheetData, autoFilter,
    // mergeCells, dataValidations, then drawing. Out of order and it will not
    // open.
    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"{namespace}><dimension ref="A1:{last_column}{last_row}"/><sheetViews><sheetView workbookViewId="0">{pane}</sheetView></sheetViews><sheetFormatPr defaultRowHeight="14"/><cols>{columns}</cols><sheetData>{body}</sheetData><autoFilter ref="A1:{last_column}{last_row}"/>{merge_xml}{validations}{drawing}</worksheet>"#
    );

    (xml, pictures)
}

// ---- assembly ----------------------------------------------------------

fn content_types(pictures: &Pictures, sheet_count: usize) -> String {
    let mut defaults = String::from(
        r#"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>"#,
    );
    for extension in pictures.extensions() {
        defaults.push_str(&format!(
            r#"<Default Extension="{extension}" ContentType="{}"/>"#,
            content_type_for(&extension)
        ));
    }
    let mut sheets = String::new();
    for n in 1..=sheet_count {
        sheets.push_str(&format!(
            r#"<Override PartName="/xl/worksheets/sheet{n}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        ));
    }
    let drawing = if pictures.is_empty() {
        String::new()
    } else {
        r#"<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>"#.to_string()
    };
    format!(
        r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">{defaults}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>{sheets}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>{drawing}</Types>"#
    )
}

const ROOT_RELS: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#;

const WORKBOOK_RELS: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#;

const SHEET_RELS: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>"#;

const WORKBOOK: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Shot List" sheetId="1" r:id="rId1"/><sheet name="Lists" sheetId="2" state="hidden" r:id="rId2"/></sheets></workbook>"#;

// ---- the four-sheet workbook -------------------------------------------
//
// His working file, exactly: Master Shot List (script order, with pictures),
// Group by Day, Group by Sequence, and Ranges — the vocabulary lists, left
// visible rather than hidden, since that sheet is where his own template
// keeps them.

const WORKBOOK_RELS_4: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/><Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#;

const WORKBOOK_4: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Master Shot List" sheetId="1" r:id="rId1"/><sheet name="Group by Day" sheetId="2" r:id="rId2"/><sheet name="Group by Sequence" sheetId="3" r:id="rId3"/><sheet name="Ranges" sheetId="4" r:id="rId4"/></sheets></workbook>"#;

/// Write the four-sheet workbook.
///
/// `master` should be flat (`GroupBy::Flat`, script order), `by_day` and
/// `by_sequence` the same underlying rows read through `GroupBy::Day` and
/// `GroupBy::Sequence` — three views of one filtered list, exactly like the
/// three tabs it produces. Pictures are drawn on the Master sheet only, as in
/// his own file: the same picture repeated across three tabs would triple the
/// file for no reason anyone would look at.
pub fn workbook(
    master: &Sheet,
    by_day: &Sheet,
    by_sequence: &Sheet,
    vocabulary: &dyn Fn(&str) -> Vec<String>,
    frames: Frames,
) -> Vec<u8> {
    let mut styles = Styles::new();
    let lists = gather_lists(master, vocabulary);

    // Order matters: sheet 1 registers most of the styles, and only sheet 1
    // is handed the frames callback — the other two ask for none.
    let (sheet1, pictures) = main_sheet(master, &lists, "Ranges", &mut styles, frames);
    let (sheet2, _) = main_sheet(by_day, &lists, "Ranges", &mut styles, &no_frames);
    let (sheet3, _) = main_sheet(by_sequence, &lists, "Ranges", &mut styles, &no_frames);
    let sheet4 = lists.to_xml(&mut styles);
    let styles_xml = styles.to_xml();

    let mut zip = ZipWriter::new();
    zip.add("[Content_Types].xml", content_types(&pictures, 4).as_bytes());
    zip.add("_rels/.rels", ROOT_RELS.as_bytes());
    zip.add("xl/workbook.xml", WORKBOOK_4.as_bytes());
    zip.add("xl/_rels/workbook.xml.rels", WORKBOOK_RELS_4.as_bytes());
    zip.add("xl/styles.xml", styles_xml.as_bytes());
    zip.add("xl/worksheets/sheet1.xml", sheet1.as_bytes());
    zip.add("xl/worksheets/sheet2.xml", sheet2.as_bytes());
    zip.add("xl/worksheets/sheet3.xml", sheet3.as_bytes());
    zip.add("xl/worksheets/sheet4.xml", sheet4.as_bytes());

    if !pictures.is_empty() {
        zip.add("xl/worksheets/_rels/sheet1.xml.rels", SHEET_RELS.as_bytes());
        zip.add("xl/drawings/drawing1.xml", pictures.drawing_xml().as_bytes());
        zip.add(
            "xl/drawings/_rels/drawing1.xml.rels",
            pictures.drawing_rels().as_bytes(),
        );
        for (index, frame) in pictures.files.iter().enumerate() {
            zip.add(
                &format!("xl/media/image{}.{}", index + 1, frame.extension),
                &frame.bytes,
            );
        }
    }

    zip.finish()
}

/// Write the spreadsheet.
///
/// `vocabulary` supplies the master lists that drive the dropdowns — pass
/// `|name| doc.vocabulary(name)`. `frames` supplies picture bytes; pass
/// `&no_frames` for a sheet of data only.
pub fn write(
    sheet: &Sheet,
    vocabulary: &dyn Fn(&str) -> Vec<String>,
    frames: Frames,
) -> Vec<u8> {
    let mut styles = Styles::new();
    let lists = gather_lists(sheet, vocabulary);

    // Order matters: the main sheet registers most of the styles.
    let (sheet_xml, pictures) = main_sheet(sheet, &lists, "Lists", &mut styles, frames);
    let lists_xml = lists.to_xml(&mut styles);
    let styles_xml = styles.to_xml();

    let mut zip = ZipWriter::new();
    zip.add("[Content_Types].xml", content_types(&pictures, 2).as_bytes());
    zip.add("_rels/.rels", ROOT_RELS.as_bytes());
    zip.add("xl/workbook.xml", WORKBOOK.as_bytes());
    zip.add("xl/_rels/workbook.xml.rels", WORKBOOK_RELS.as_bytes());
    zip.add("xl/styles.xml", styles_xml.as_bytes());
    zip.add("xl/worksheets/sheet1.xml", sheet_xml.as_bytes());
    zip.add("xl/worksheets/sheet2.xml", lists_xml.as_bytes());

    if !pictures.is_empty() {
        zip.add("xl/worksheets/_rels/sheet1.xml.rels", SHEET_RELS.as_bytes());
        zip.add("xl/drawings/drawing1.xml", pictures.drawing_xml().as_bytes());
        zip.add(
            "xl/drawings/_rels/drawing1.xml.rels",
            pictures.drawing_rels().as_bytes(),
        );
        for (index, frame) in pictures.files.iter().enumerate() {
            zip.add(
                &format!("xl/media/image{}.{}", index + 1, frame.extension),
                &frame.bytes,
            );
        }
    }

    zip.finish()
}
