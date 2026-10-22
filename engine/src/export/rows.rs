//! The flattened list.
//!
//! Every exporter — spreadsheet, printed document, share page — wants the same
//! thing: the list as rows, with everything already worked out. Derived values
//! are resolved once, here, so three exporters cannot come to three different
//! answers about what shot 34A's number is.
//!
//! This is also the seam the design work sits behind. What is on the page and in
//! what order is decided here; how it reads is a stylesheet's business.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::media::Arrow;
use crate::layout::FramePosition;
use crate::query::{GroupBy, Query};
use crate::quoting::Quote;
use crate::value::Value;

/// **Which part of a picture to keep when it is drawn in a frame box.**
///
/// `x` and `y` are the point that ends up in the middle, each from nought to
/// one; `scale` is how far in, where one is the whole picture. The middle at
/// full width is what a photograph nobody has framed draws as, and is the
/// default.
///
/// **The same three numbers `set_media_crop` stores** and the same arithmetic
/// `Framed` draws with in Swift. Both are written out in
/// `export::html::held` — if one changes the other has to.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Framing {
    pub x: f64,
    pub y: f64,
    pub scale: f64,
}

impl Default for Framing {
    fn default() -> Self {
        Framing { x: 0.5, y: 0.5, scale: 1.0 }
    }
}

impl Framing {
    pub fn is_middle(&self) -> bool {
        (self.x - 0.5).abs() < 1e-6 && (self.y - 0.5).abs() < 1e-6 && (self.scale - 1.0).abs() < 1e-6
    }
}

/// **How one use of a picture is drawn: the part kept, the arrows over it, and
/// the picture's own size.**
///
/// All of it belongs to the *use*, not to the file — the same photograph can
/// be framed one way on one shot and another way on the next. An arrow is a
/// fraction of the picture, so drawing one needs to know what shape that is,
/// which is why the size travels with them.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Marks {
    pub arrows: Vec<Arrow>,
    pub width: f64,
    pub height: f64,
    /// Which part of it he chose to keep. **Read even when there are no
    /// arrows** — a picture nobody has drawn on can still be framed, and for
    /// three weeks the printed page threw that away.
    pub crop: Framing,
}

impl Marks {
    pub fn is_empty(&self) -> bool {
        self.arrows.is_empty() || self.width <= 0.0 || self.height <= 0.0
    }
}

/// A camera, as it appears on the page.
#[derive(Clone, Debug, PartialEq)]
pub struct Camera {
    pub label: String,
    pub body: String,
    pub colour: Option<String>,
}

impl Camera {
    /// `A-Cam Alexa35`, the way it reads in the sheets.
    pub fn display(&self) -> String {
        if self.body.is_empty() {
            self.label.clone()
        } else {
            format!("{} {}", self.label, self.body)
        }
    }
}

/// **A shot's baked Print Frame, on its way to a page.** Its own shape,
/// which the page keeps — a board is never cropped to the film's ratio.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct PrintPicture {
    /// What it is filed under: its SHA-256 in hex, and its extension.
    pub hash: String,
    pub ext: String,
    pub width: f64,
    pub height: f64,
    /// What the page draws — a data URI or a path — filled by the shell.
    pub src: String,
}

impl PrintPicture {
    /// Whether a page can draw it: it has a picture and a shape.
    pub fn is_usable(&self) -> bool {
        !self.src.is_empty() && self.width > 0.0 && self.height > 0.0
    }
}

#[derive(Clone, Debug)]
pub struct Row {
    pub placement: Id,
    pub shot: Id,
    pub scene: Id,

    /// `34A`
    pub number: String,
    pub scene_number: String,
    pub scene_heading: String,
    pub day_label: Option<String>,
    pub sequence: Option<String>,
    /// **The section the scene is in, with its colour** — what a page
    /// grouped by anything other than scene reads to say which script a
    /// shot belongs to. His ask, 2026-09-20: a shoot day mixes scripts, and
    /// *"it needs to be clear what 'script' each shot is apart of still."*
    /// `sequence` is the same section's name as a column cell.
    pub section: Option<Section>,
    /// The same section by id — what the Script page matches a shot that
    /// quotes nothing against, to list it under its script anyway.
    pub section_id: Option<Id>,
    /// The shot's values in the project's own columns, as words — a check
    /// is a tick or nothing, a list is joined with commas.
    pub own: Vec<(String, String)>,
    /// The values of the project's own pick-one and pick-many columns, one
    /// by one — `own` joins them with commas, which a pill cannot be cut
    /// back out of when a term has a comma in it.
    pub own_pills: Vec<(String, Vec<String>)>,

    pub title: String,
    pub description: String,
    /// **The stretch of the script this shot quotes** (2026-09-19), read
    /// off the script every time. Empty on a film and on a shot tied to
    /// nothing.
    pub script: String,
    /// **Where in which script that stretch is** — the Script page cuts a
    /// script at these and lays each shot beside the words it quotes.
    /// `None` on a shot tied to nothing.
    pub quote: Option<Quote>,
    /// **Every stretch it quotes**, the first one too — a shot can quote
    /// several lines far apart (2026-10-05). Empty on a shot tied to nothing.
    pub spans: Vec<(usize, usize)>,
    /// A commercial scene's slug under its title — `EXT. FRONT ENTRANCE -
    /// TWILIGHT` — the Script page's cue over a shot. Empty on a film,
    /// where the heading already is the slug.
    pub scene_slug: String,
    pub size: String,
    /// Several values, as in the real lists.
    pub angle: Vec<String>,
    pub movement: String,
    pub camera: Option<Camera>,
    pub lens: String,
    /// Where a zoom is set, in mm — only while the Lens is a zoom.
    pub focal: Option<f64>,
    /// Extenders and the like on the lens for this shot; several.
    pub modifiers: Vec<String>,
    /// Filters this shot uses; several.
    pub lens_filters: Vec<String>,
    /// Lens Stack is on: the Lens cell carries the filters and modifiers
    /// (`stack_parts`), and the two columns are not drawn.
    pub stacked: bool,
    pub support: String,
    pub notes: String,
    pub tags: Vec<String>,

    /// The frame that stands for this shot. Bytes are the shells' business.
    pub key_frame: Option<Id>,
    /// **The storyboard arrows on that frame, and the picture's own size.**
    /// The arrows belong to the *use* of the file, which `key_frame` has
    /// already thrown away — so they are worked out here, beside it, rather
    /// than looked up from a file id that cannot answer.
    pub key_frame_marks: Marks,
    /// **The trim on that use of the clip**, in seconds, when there is one.
    /// The same story as the arrows and for the same reason: a trim belongs to
    /// this attachment, not to the file, and `key_frame` has already thrown
    /// the attachment away. A printed page needs it because a clip's four
    /// moments are sampled from the part he kept, not the whole take.
    pub key_frame_trim: Option<(f64, f64)>,
    /// Every frame on the shot, in order.
    pub frames: Vec<Id>,
    /// The arrows on each of them, in the same order.
    pub frame_marks: Vec<Marks>,
    /// The trim on each of them, in the same order. **Zipped, never
    /// filtered** — same trap the marks carry: dropping one frame without
    /// dropping its trim slides every later clip's range onto the wrong film.
    pub frame_trims: Vec<Option<(f64, f64)>>,
    /// Frame width as a fraction of the text measure, never an absolute size.
    pub frame_width: f64,
    pub frame_position: FramePosition,
    /// **The shot's Print Frame, when the Mac has baked a current one** —
    /// the one picture that stands for the shot on paper, in place of its
    /// key frame and its marks (`crate::printframe`). `None` prints the shot
    /// exactly as before. `src` is empty until the shell fills it
    /// (`Sheet::fill_print_frames`), since the engine never touches bytes.
    pub print_frame: Option<PrintPicture>,

    pub struck: bool,
    /// Shots rolling at the same moment on other cameras.
    pub siblings: Vec<Id>,
}

impl Row {
    /// The Lens as a page prints it: `24-70mm · 35mm` for a zoom where it is
    /// set, else the lens.
    pub fn lens_said(&self) -> String {
        match self.focal {
            Some(mm) if !self.lens.is_empty() => format!("{} · {}mm", self.lens, mm.round() as i64),
            _ => self.lens.clone(),
        }
    }

    /// What rides under the lens when the stack is on: filters, then
    /// modifiers, each as the shot names it. Empty when the stack is off.
    pub fn stack_parts(&self) -> Vec<String> {
        if !self.stacked {
            return Vec::new();
        }
        self.lens_filters.iter().chain(self.modifiers.iter()).cloned().collect()
    }

    /// The Lens cell as plain text: `27mm · 1/8 Pro-Mist · Diopter +½` while
    /// stacked, the lens alone otherwise.
    pub fn lens_cell(&self) -> String {
        let mut parts = Vec::new();
        let lens = self.lens_said();
        if !lens.is_empty() {
            parts.push(lens);
        }
        parts.extend(self.stack_parts());
        parts.join(" · ")
    }

    /// `W/OTS - Short-Sided - Static - 37mm - Handheld`.
    ///
    /// The order follows the table's columns, so there is one order set in one
    /// place and the table and the page cannot disagree about whether lens comes
    /// before support. A column that is hidden is not in the line either.
    pub fn technical_line_for(&self, columns: &[String]) -> String {
        let mut parts: Vec<String> = Vec::new();
        for column in columns {
            let part = match column.as_str() {
                "size" => self.size.clone(),
                "angle" => self.angle.join(", "),
                "movement" => self.movement.clone(),
                "camera" => self.camera.as_ref().map(|c| c.display()).unwrap_or_default(),
                "lens" => self.lens_cell(),
                // No part of their own: the lens cell already carries them.
                "support" => self.support.clone(),
                _ => continue,
            };
            if !part.is_empty() {
                parts.push(part);
            }
        }
        parts.join(" – ")
    }

    /// The line in the default order, for callers with no project to hand.
    pub fn technical_line(&self) -> String {
        let default: Vec<String> = crate::columns::TECHNICAL
            .iter()
            .map(|s| s.to_string())
            .collect();
        self.technical_line_for(&default)
    }
}

#[derive(Clone, Debug)]
pub struct RowGroup {
    pub label: String,
    pub key: Option<Id>,
    pub rows: Vec<Row>,
    /// **Grouped by scene: the section (a film says sequence) the scene is
    /// in, and whether it begins a run of them.** The app draws a section
    /// head over the first scene of a run and nothing over the rest; the
    /// printed page and the portal do the same off these two. Three spots
    /// on one job, pasted into three sections, print as three headed runs.
    pub section: Option<Section>,
    pub section_starts: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Section {
    pub title: String,
    pub colour: String,
}

impl RowGroup {
    /// The count the sheets carry in every group header.
    pub fn count(&self) -> usize {
        self.rows.len()
    }
}

#[derive(Clone, Debug)]
pub struct Sheet {
    /// The columns on screen when this was made, in order. A share page carries
    /// what you were looking at rather than everything.
    pub columns: Vec<String>,
    pub project_title: String,
    pub director: String,
    pub producer: String,
    /// The project's frame box — every card on the storyboard page draws at
    /// it, same as the app's own Storyboard tab.
    pub project_ratio: f64,
    pub grouped_by: GroupBy,
    pub groups: Vec<RowGroup>,
    /// Whether this is a commercial — which changes what a scene's heading
    /// is, what sits under it, and what the sequence column is called.
    pub commercial: bool,
    /// **The project's own columns, by slug and name.** The export box
    /// could tick one from 2026-09-19 (9035866) and the page then printed
    /// its slug as the header and nothing in the cell.
    pub own_columns: Vec<(String, String)>,
    /// **Every script the film holds**, in section order, the film's own
    /// first — what the Script page is a page of. Empty on a film that has
    /// never had a script pasted.
    pub scripts: Vec<Script>,
    /// **The colours he has given terms by hand** — `(column, term in lower
    /// case, RRGGBB)`. Everything else wears its column's colour, which the
    /// table page works out itself the way `Brand.chipInk` does.
    pub term_inks: Vec<(String, String, String)>,
    /// **Each shoot day on a sheet of its own** — the export's Schedule
    /// order with several days in one file (2026-10-15): the Table and the
    /// Storyboard start every day on a fresh page, and the Document runs on
    /// without breaking. False is the page as it always was.
    pub day_pages: bool,
}

/// One script and whose it is: a section's, titled and coloured by that
/// section, or the film's own with no section at all.
#[derive(Clone, Debug, PartialEq)]
pub struct Script {
    pub section: Option<Id>,
    pub title: String,
    pub colour: String,
    pub text: String,
}

impl Sheet {
    pub fn total(&self) -> usize {
        self.groups.iter().map(|g| g.count()).sum()
    }

    pub fn rows(&self) -> impl Iterator<Item = &Row> {
        self.groups.iter().flat_map(|g| g.rows.iter())
    }

    pub fn is_empty(&self) -> bool {
        self.total() == 0
    }

    /// **Hands every baked Print Frame its picture** — `src` turns a hash and
    /// an extension into what a page draws, with the picture's own shape when
    /// the record did not carry one, or `None` when the bytes are not on this
    /// device. A shot whose picture cannot be found prints as it always did.
    pub fn fill_print_frames(&mut self, src: impl Fn(&str, &str) -> Option<(String, f64, f64)>) {
        for group in self.groups.iter_mut() {
            for row in group.rows.iter_mut() {
                let Some(pf) = row.print_frame.as_mut() else { continue };
                match src(&pf.hash, &pf.ext) {
                    Some((found, width, height)) => {
                        pf.src = found;
                        if pf.width <= 0.0 || pf.height <= 0.0 {
                            pf.width = width;
                            pf.height = height;
                        }
                    }
                    None => pf.src.clear(),
                }
                if !pf.is_usable() {
                    row.print_frame = None;
                }
            }
        }
    }

    /// The one scene this sheet is entirely about, when it is about exactly
    /// one — a scene's own PDF export, not the whole picture. `(number,
    /// heading)`, the same pair the scene band already shows on screen.
    pub fn single_scene(&self) -> Option<(&str, &str)> {
        if self.grouped_by != GroupBy::Scene || self.groups.len() != 1 {
            return None;
        }
        let row = self.groups[0].rows.first()?;
        Some((&row.scene_number, &row.scene_heading))
    }
}

fn strings(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::List(items)) => items
            .iter()
            .filter_map(|i| i.as_text().map(|s| s.to_string()))
            .collect(),
        Some(Value::Text(s)) if !s.is_empty() => vec![s.clone()],
        _ => Vec::new(),
    }
}

fn text_of(value: Option<&Value>) -> String {
    text(value)
}

fn text(value: Option<&Value>) -> String {
    value
        .and_then(|v| v.as_text())
        .unwrap_or_default()
        .to_string()
}

impl Doc {
    /// Run a query and flatten the result into rows ready to be written out.
    pub fn sheet(&self, query: &Query) -> Sheet {
        let project = self.project_id().and_then(|id| self.get(id));

        let commercial = self.kind() == crate::kind::Kind::Commercial;
        let by_scene = query.group_by == GroupBy::Scene;
        let mut last_section: Option<Id> = None;
        let mut groups: Vec<RowGroup> = Vec::new();
        for (index, group) in self.run(query).into_iter().enumerate() {
            let scene = if by_scene { group.key } else { None };
            let section_id = scene
                .and_then(|s| self.get(s))
                .and_then(|r| r.ref_id(f::SEQUENCE));
            let section = section_id.and_then(|id| self.get(id)).map(|r| Section {
                title: text(r.get(f::TITLE)),
                colour: text(r.get(f::COLOUR)),
            });
            let section_starts = by_scene && section.is_some() && (index == 0 || section_id != last_section);
            if by_scene {
                last_section = section_id;
            }
            groups.push(RowGroup {
                label: group.label,
                key: group.key,
                rows: group
                    .placements
                    .into_iter()
                    .filter_map(|placement| self.row(placement))
                    .collect(),
                section,
                section_starts,
            });
        }

        Sheet {
            day_pages: false,
            columns: self.visible_columns(),
            // The name the film is shown by — the project record's, when the
            // film takes its facts from there (`crate::recordfacts`).
            project_title: if project.is_some() { self.shown_title() } else { String::new() },
            // The card's, when one is laid over the film (`crate::card`).
            director: if project.is_some() { self.fact(f::DIRECTOR) } else { String::new() },
            producer: if project.is_some() { self.fact(f::PRODUCER) } else { String::new() },
            // The frame Studio draws at (piece E), else the film's own.
            project_ratio: if project.is_some() { self.film_ratio() } else { 2.39 },
            grouped_by: query.group_by,
            groups,
            commercial,
            own_columns: self.custom_columns().into_iter().map(|c| (c.field, c.label)).collect(),
            term_inks: {
                let custom: Vec<String> = self.custom_columns().into_iter().map(|c| c.field).collect();
                crate::vocab::ALL
                    .iter()
                    .map(|f| f.to_string())
                    .chain(custom)
                    .flat_map(|field| {
                        self.term_colours(&field)
                            .into_iter()
                            .map(move |(term, hex)| (field.clone(), term.trim().to_lowercase(), hex))
                            .collect::<Vec<_>>()
                    })
                    .collect()
            },
            scripts: self
                .av_scripts()
                .into_iter()
                .map(|(section, text)| {
                    let holder = section.and_then(|id| self.get(id));
                    Script {
                        section,
                        title: holder.map(|r| text_of(r.get(f::TITLE))).unwrap_or_default(),
                        colour: holder.map(|r| text_of(r.get(f::COLOUR))).unwrap_or_default(),
                        text,
                    }
                })
                .collect(),
        }
    }

    /// One placement, with everything resolved.
    pub fn row(&self, placement: Id) -> Option<Row> {
        let record = self.get(placement)?;
        let shot_id = record.ref_id(f::SHOT)?;
        let shot = self.get(shot_id)?;
        // **Where the words come from** — the same answer the table gives
        // (`view.rs`): a shot standing in for a master prints the master's
        // description, technical fields and frames, and keeps its own number,
        // camera, columns and Shot mark. Until 2026-09-30 a follower printed
        // blank on the PDF and in Excel while the table showed it full.
        let said_id = self.described_by(shot_id);
        let said = self.get(said_id).unwrap_or(shot);
        let scene_id = record.ref_id(f::SCENE)?;
        let scene = self.get(scene_id)?;

        let camera = shot.ref_id(f::UNIT).and_then(|id| self.get(id)).map(|unit| Camera {
            label: text(unit.get(f::LABEL)),
            body: text(unit.get(f::BODY)),
            colour: unit.text(f::COLOUR).map(|s| s.to_string()),
        });

        let section = scene
            .ref_id(f::SEQUENCE)
            .and_then(|id| self.get(id))
            .map(|s| Section { title: text(s.get(f::TITLE)), colour: text(s.get(f::COLOUR)) });
        let sequence = section.as_ref().map(|s| s.title.clone()).filter(|t| !t.is_empty());
        let own_pills = self
            .custom_columns()
            .into_iter()
            .filter(|c| c.kind == "single" || c.kind == "multi")
            .map(|c| {
                let parts = if c.kind == "multi" {
                    strings(shot.get(&c.field))
                } else {
                    let one = text(shot.get(&c.field));
                    if one.is_empty() { Vec::new() } else { vec![one] }
                };
                (c.field, parts)
            })
            .collect();
        let own = self
            .custom_columns()
            .into_iter()
            .map(|c| {
                let words = match c.kind.as_str() {
                    "multi" => strings(shot.get(&c.field)).join(", "),
                    "check" => match shot.get(&c.field) {
                        Some(Value::Bool(true)) => "\u{2713}".to_string(),
                        _ => String::new(),
                    },
                    _ => text(shot.get(&c.field)),
                };
                (c.field, words)
            })
            .collect();

        Some(Row {
            placement,
            shot: shot_id,
            scene: scene_id,

            number: self.display_number(placement).unwrap_or_default(),
            scene_number: text(scene.get(f::NUMBER)),
            scene_heading: self.scene_heading(scene_id).unwrap_or_default(),
            day_label: record.ref_id(f::DAY).and_then(|d| self.day_label(d)),
            sequence,
            section,
            section_id: scene.ref_id(f::SEQUENCE),
            own,
            own_pills,

            title: text(said.get(f::TITLE)),
            description: text(said.get(f::DESCRIPTION)),
            script: self.shot_excerpt(said_id),
            quote: self.quote_of(said_id),
            spans: self.spans_of(said_id),
            scene_slug: if self.kind() == crate::kind::Kind::Commercial {
                self.scene_slug(scene_id).unwrap_or_default()
            } else {
                String::new()
            },
            size: text(said.get(f::SIZE)),
            angle: strings(said.get(f::ANGLE)),
            movement: text(said.get(f::MOVEMENT)),
            camera,
            lens: text(said.get(f::LENS)),
            focal: crate::diagram::lens::zoom_from_text(&text(said.get(f::LENS)))
                .and_then(|_| said.get(f::FOCAL).and_then(|v| v.as_float())),
            modifiers: strings(said.get(f::MODIFIERS)),
            lens_filters: strings(said.get(f::LENS_FILTERS)),
            stacked: self.lens_stacked(),
            support: text(said.get(f::SUPPORT)),
            notes: text(said.get(f::NOTES)),
            tags: strings(said.get(f::TAGS)),

            key_frame: self.key_frame(said_id),
            key_frame_marks: self
                .key_media_ref(said_id)
                .map(|r| self.marks_on(r))
                .unwrap_or_default(),
            key_frame_trim: self.key_media_ref(said_id).and_then(|r| self.media_trim(r)),
            frames: self.media_of(said_id),
            frame_marks: self
                .media_refs(said_id)
                .into_iter()
                .map(|r| self.marks_on(r))
                .collect(),
            frame_trims: self
                .media_refs(said_id)
                .into_iter()
                .map(|r| self.media_trim(r))
                .collect(),
            frame_width: self.frame_width(shot_id),
            frame_position: self.frame_position(shot_id),
            print_frame: self.print_frame_picture(said_id).map(|b| PrintPicture {
                hash: b.hash,
                ext: b.ext,
                width: b.width as f64,
                height: b.height as f64,
                src: String::new(),
            }),

            struck: shot.bool(f::STRUCK),
            siblings: self.setup_siblings(shot_id),
        })
    }
}
