//! Pages: the share link, the printed document, the printed table.
//!
//! The engine decides what is on the page and in what order. How it reads is the
//! stylesheet's business, and the stylesheet is one function you can replace
//! without touching anything here — which is how the design work lands later
//! without a rewrite.
//!
//! PDFs are not generated here. The Mac app renders these pages to PDF using the
//! system, which produces better type and better page breaks than anything worth
//! writing by hand.
//!
//! Frames are supplied by the caller, since the engine never touches bytes. Pass
//! a function that turns a media id into an `src` — a data URI for a share page
//! that has to work with no network, a file path for printing.

use crate::docstyle::{Class, Style};
use crate::export::rows::{Marks, PrintPicture, Row, RowGroup, Script, Section, Sheet};
use crate::id::Id;
use crate::layout::FramePosition;
use crate::query::GroupBy;

/// **A picture the shell has handed over, and its shape.**
///
/// The shape is here because only the shell has the bytes, and without it a
/// page cannot work out which part of a photograph a crop keeps — that sum
/// needs the picture's own ratio and the frame box's, and the engine has only
/// one of them. `(0, 0)` is a shell that could not say; the page then covers
/// the box and keeps the middle.
#[derive(Clone, Debug, Default)]
pub struct Frame {
    pub src: String,
    pub width: f64,
    pub height: f64,
    /// **How many pictures this one picture is.** 1 for a still; 4 for a
    /// clip's strip — four moments baked two by two into one file by the
    /// Mac (`Filmstrip.swift`), which the page can take apart again
    /// (`quadrants`) when a row has the height to stack them.
    pub moments: u8,
}

/// **Which use of a clip is being drawn**, not just which file — the trim, in
/// seconds, or `None` for "play the whole thing".
///
/// A still ignores it. A clip does not: its four printed moments come from the
/// part he kept, and a strip made from the whole take is four moments of
/// footage he cut. His report, 2026-09-01.
pub type Trim = Option<(f64, f64)>;

/// Turns a media id, as used *here*, into a picture to draw. Returning `None`
/// simply leaves that frame out.
pub type Frames<'a> = &'a dyn Fn(Id, Trim) -> Option<Frame>;

/// **How much room a picture gets on the page.** His ask, 2026-09-01: the
/// table's picture column is about a tenth of a landscape page, which is
/// small for one frame and very small for a clip's four moments.
///
/// One dial, two effects, because both are the same question asked of two
/// pages: how wide the table's picture column is, and how tall a frame on
/// the storyboard page stands.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum FrameSize {
    Small,
    #[default]
    Medium,
    Large,
}

impl FrameSize {
    /// `small`, `medium`, `large` — anything else is the middle, which is what
    /// an older shell that does not know to ask will get.
    pub fn read(said: &str) -> FrameSize {
        match said.trim().to_lowercase().as_str() {
            "small" => FrameSize::Small,
            "large" => FrameSize::Large,
            _ => FrameSize::Medium,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            FrameSize::Small => "small",
            FrameSize::Medium => "medium",
            FrameSize::Large => "large",
        }
    }

    /// The picture column's share of the table, weighed against the other
    /// columns. **Small is what every export drew until 2026-09-01**, so a
    /// sheet that looked right before can still be had exactly.
    fn column_weight(&self) -> f64 {
        match self {
            FrameSize::Small => 1.4,
            // **1.8, not the 2.3 tried first.** Width on a landscape page is
            // zero-sum: at 2.3 an eleven-column sheet started breaking words
            // in half — `EQUIPMEN／T`, `Handhel／d` — which is a worse page
            // than a small picture. The default has to be safe on his widest
            // sheet; `Large` is where he trades text room for pictures on
            // purpose.
            FrameSize::Medium => 1.8,
            FrameSize::Large => 3.0,
        }
    }

    /// **How tall a storyboard frame stands, in rem** — the page's own unit,
    /// so the text dial scales the pictures with the words. A frame's width
    /// follows from the film's ratio (`frame_width_rem`), which is why the
    /// dial is a height: a vertical film's frames and a widescreen film's
    /// stand the same height on the same setting, as they do in the app.
    /// Medium is about a fifth of a landscape sheet's height; Large is a
    /// third; Small is what fits six shots on a page.
    fn frame_height_rem(&self) -> f64 {
        match self {
            FrameSize::Small => 6.5,
            FrameSize::Medium => 9.0,
            FrameSize::Large => 13.0,
        }
    }

    /// The width of one storyboard frame at this size, for a film of this
    /// ratio, in rem.
    fn frame_width_rem(&self, ratio: f64) -> f64 {
        self.frame_height_rem() * ratio.clamp(0.3, 4.0)
    }
}

/// **A picture with its storyboard arrows drawn over it.**
///
/// The arrows are an SVG laid exactly over the `<img>`, in the picture's own
/// pixel coordinates — so `preserveAspectRatio` is the only thing that has to
/// agree with the stylesheet, and it is passed in: `meet` where the picture is
/// shown whole (the table and the document, `height:auto`), `slice` where the
/// card crops it (`object-fit:cover`). Get that one word wrong and the arrows
/// drift off what they were drawn on.
///
/// No arrows means no wrapper and no SVG at all — the markup a page with no
/// marks on it produces is byte for byte what it produced before any of this
/// existed.
fn marked(src: &str, marks: &Marks, fit: &str) -> String {
    let img = format!("<img src=\"{}\" alt=\"\">", esc(src));
    let shapes = arrow_shapes(marks);
    if shapes.is_empty() {
        return img;
    }
    format!(
        "<span class=\"marked\">{img}<svg class=\"marks\" viewBox=\"0 0 {:.0} {:.0}\" \
         preserveAspectRatio=\"xMidYMid {fit}\">{shapes}</svg></span>",
        marks.width, marks.height
    )
}

/// Just the polygons, in the picture's own pixel coordinates. Empty for a
/// photograph nobody has drawn on, which is every photograph until somebody
/// does — and empty means no wrapper and no SVG anywhere it is used.
fn arrow_shapes(marks: &Marks) -> String {
    if marks.is_empty() {
        return String::new();
    }
    let mut shapes = String::new();
    for arrow in &marks.arrows {
        // Each arrow in its own look — fill, outline, weight, dashes — the
        // same pieces the Mac draws (`Arrow::pieces`).
        shapes.push_str(&arrow.svg(marks.width, marks.height));
    }
    shapes
}

/// **The picture inside a frame box, showing the part he chose to keep.**
///
/// His report, 2026-09-01: cropping a picture works on every screen in both
/// apps and was thrown away by every printed page — the worst place for it to
/// be wrong, because the PDF is the copy somebody else reads.
///
/// This is `Framed` in `studio/Sources/Moving.swift`, written out in
/// percentages: the picture is made big enough to cover the box, taken in by
/// however far he took it, then anchored so that the point `(x, y)` of the
/// picture lands on the point `(x, y)` of the box. Swift says that as an
/// offset from the middle and this says it as a left edge; they are the same
/// sum, `left = (box - picture) * x`. **If one changes the other has to.**
///
/// Returns the inner half only — the caller owns the box, because the pages
/// that draw one make it differently: a table cell sizes itself from its
/// column, a storyboard card already is one.
fn held(frame: &Frame, marks: &Marks, ratio: f64) -> String {
    let ratio = if ratio > 0.01 { ratio } else { 1.0 };
    let shape = if frame.height > 0.0 { frame.width / frame.height } else { 0.0 };
    let src = esc(&frame.src);
    if shape <= 0.0 {
        // The shell could not say what shape it is: cover the box and keep the
        // middle. Never a stretch, and never worse than it used to be.
        return format!("<img class=\"held cover\" src=\"{src}\" alt=\"\">");
    }
    let crop = marks.crop;
    let scale = if crop.scale >= 1.0 { crop.scale } else { 1.0 };
    let (x, y) = (crop.x.clamp(0.0, 1.0), crop.y.clamp(0.0, 1.0));

    // `Framed` in `studio/Sources/Moving.swift`, written out in percentages of
    // the frame box: the picture is made big enough to cover the box, taken in
    // by however far he took it, then anchored so the point `(x, y)` of the
    // picture lands on the point `(x, y)` of the box. Swift says that as an
    // offset from the middle and this says it as a left edge; they are the
    // same sum, `left = (box - picture) * x`. **If one changes the other has
    // to.**
    let (wide, tall) = if shape >= ratio {
        (100.0 * shape / ratio, 100.0)
    } else {
        (100.0, 100.0 * ratio / shape)
    };
    let (wide, tall) = (wide * scale, tall * scale);
    // `+ 0.0` is not decoration: without it a picture taken to the left edge
    // is placed at `-0.000%`, which is valid and reads like a mistake.
    let left = (100.0 - wide) * x + 0.0;
    let top = (100.0 - tall) * y + 0.0;

    // **One axis given, the other left to the picture — and it is the file
    // size that decides this.** Setting both axes, or covering with
    // `object-fit`, both draw correctly and both make WebKit write the *whole*
    // photograph into the PDF at its own resolution rather than the size it is
    // drawn at. Measured on one day's sheet: 216 KB the old way, 656 KB with
    // both axes, 773 KB with `object-fit`. An `<img>` whose size the layout
    // works out from one axis and its own ratio is one WebKit will downsample,
    // which is how every printed page has always kept its weight.
    let axis = if shape >= ratio {
        format!("height:{tall:.3}%")
    } else {
        format!("width:{wide:.3}%")
    };
    let picture = format!(
        "<img class=\"held\" style=\"left:{left:.3}%;top:{top:.3}%;{axis}\" \
src=\"{src}\" alt=\"\">"
    );

    let shapes = arrow_shapes(marks);
    if shapes.is_empty() {
        return picture;
    }
    // **The arrows go on the photograph, not on the frame** — the same
    // rectangle, so cropping in on a corner crops in on the arrow drawn there.
    // `preserveAspectRatio="none"` is exact rather than lazy: this rectangle
    // is already the picture's own ratio, so there is nothing left to fit.
    format!(
        "{picture}<svg class=\"marks\" style=\"left:{left:.3}%;top:{top:.3}%;\
width:{wide:.3}%;height:{tall:.3}%\" viewBox=\"0 0 {:.0} {:.0}\" \
preserveAspectRatio=\"none\">{shapes}</svg>",
        marks.width, marks.height
    )
}

pub fn no_frames(_: Id, _: Trim) -> Option<Frame> {
    None
}

/// Escape text for the page. Shared with the share exporter.
pub fn escape(s: &str) -> String {
    esc(s)
}

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            other => out.push(other),
        }
    }
    out
}

/// **The document page's measurements, in points on a 612 × 792 sheet.**
///
/// His instruction, 2026-09-01: *"Whatever I see in the document view in the
/// app, should be reflected in the export."* These are the numbers `Page` in
/// `studio/Sources/Document.swift` draws the editor with, and they are here so
/// the printed page is set from the same ones. **If one moves, the other
/// moves** — `engine/tests/export.rs` asserts every one of them reaches the
/// stylesheet, but nothing on this side can see the Swift file, so that half
/// is on you.
///
/// Everything is written into the sheet as a fraction of `ROOT`, so the export
/// dialog's Text size dial moves type, gutters and gaps together rather than
/// letting them drift apart. At 100% one rem is `ROOT` points and every number
/// below is itself.
pub mod doc {
    /// US Letter, portrait, at 72 points to the inch — his call, and the paper
    /// size does not follow the dial.
    pub const PAPER_W: f64 = 612.0;
    pub const PAPER_H: f64 = 792.0;
    /// One inch all round. `Printing.Kind.document.margin` in Swift is this
    /// number, and the printed rectangle is what gives the page its margins —
    /// which is why the page itself carries no padding of its own.
    pub const MARGIN: f64 = 72.0;
    /// The margin the shot numbers hang in, taken out of the measure.
    pub const GUTTER: f64 = 60.0;

    pub const BODY: f64 = 10.5;
    /// The short name over the sentence — the body, one point up, bold.
    pub const TITLE: f64 = 11.5;
    pub const SHOT_NUMBER: f64 = 9.0;
    pub const TECHNICAL: f64 = 8.5;
    pub const NOTES: f64 = 11.5;
    pub const SCENE_NUMBER: f64 = 10.5;
    pub const SCENE_HEADING: f64 = 11.0;
    pub const SHEET_TITLE: f64 = 13.0;
    /// The small capitals: SHOT LIST, 5 SHOTS, the credits under the title.
    pub const CAPTION: f64 = 8.0;

    /// Between the number, the frame and the words.
    pub const BESIDE_FRAME: f64 = 9.0;
    /// Between a frame and the words when the frame is above or below them.
    pub const UNDER_FRAME: f64 = 6.0;
    /// **Between one shot and the next.** The app applies it top and bottom,
    /// so the gap on the page is twice this; CSS margins between siblings
    /// collapse, so this side asks for the doubled number once.
    pub const BETWEEN_SHOTS: f64 = 5.0;
    /// Over a scene heading, and under it before the first shot.
    pub const OVER_SCENE: f64 = 13.0;

    /// One rem, in points, at 100%.
    pub const ROOT: f64 = 16.0;

    /// A measurement, as the stylesheet wants it.
    pub fn rem(points: f64) -> String {
        format!("{:.4}rem", points / ROOT)
    }

    /// What is left for a shot once the margins and the number column are out
    /// of the way — the width every frame's own fraction is a fraction *of*,
    /// on both sides.
    pub fn measure() -> f64 {
        PAPER_W - MARGIN * 2.0 - GUTTER
    }
}

/// Everything visual, in one place. Replace this and the pages change; nothing
/// else has to.
///
/// `scale` is the one dial for "everything is too cramped" — his report,
/// 2026-08-24, next to a Google Sheets export with room to spare. Every size
/// in this sheet is `rem` or `em`, relative to the root, so one root font
/// size scales the whole page — type, padding, gaps — together rather than
/// letting the text and the boxes it sits in drift apart.
pub fn stylesheet(print: Print, scale: f64, size: FrameSize, style: &Style) -> String {
    let page_rule = match print {
        Print::Screen => String::new(),
        // Inert on the path a PDF is actually made by — `Printing` cuts the
        // sheets itself — but a number here that disagrees with
        // `doc::MARGIN` is a trap for whoever prints this page any other way.
        Print::Document => format!(
            "@page {{ size: letter portrait; margin: {:.2}in; }}",
            doc::MARGIN / 72.0
        ),
        Print::Table => "@page { size: letter landscape; margin: 0.4in; }".to_string(),
        Print::Storyboard => "@page { size: letter landscape; margin: 0.5in; }".to_string(),
        Print::Script => "@page { size: letter portrait; margin: 0.75in; }".to_string(),
    };
    // The floor was 0.35 until his report, 2026-08-27: eleven columns on a
    // shoot-day page need to go smaller than that to stop wrapping. 0.15 is
    // close to the smallest anything on a letter page can read at all.
    //
    // **100% means "as this page was designed", not "as big as 16 pixels"** —
    // his instruction, 2026-09-01: *"default export size should be 100% and
    // 100% should be what it looks like in the document view within the app."*
    // The document page is drawn at exactly the app's own measurements, so its
    // base is 1. The table and the storyboard were being exported at 0.85 by
    // everybody every time, which is what their designed size actually is, so
    // that number moved here and their 100% is unchanged. A share page is read
    // on a screen where a point is 4/3 of a pixel, and 4/3 is what keeps it the
    // size it has always been.
    let base = match print {
        Print::Screen => 4.0 / 3.0,
        Print::Document | Print::Script => 1.0,
        Print::Table | Print::Storyboard => 0.85,
    };
    let root_size = doc::ROOT * base * scale.clamp(0.15, 2.5);
    // The storyboard page sizes its frames per shot, inline (`card`), because
    // how wide one stands depends on how many stand in the row. The dial
    // itself is read there; nothing in the stylesheet needs it.
    let _ = size;

    // ---- the document page's own measurements, from `doc` ------------------
    // **From the project, not from a constant.** `docstyle::standard` still
    // holds every one of the old numbers and is what an untouched film draws;
    // what changed is that there is now one owner of them rather than two.
    let s_body = style.get(Class::Body);
    let s_title = style.get(Class::ShotTitle);
    let s_number = style.get(Class::ShotNumber);
    let s_tech = style.get(Class::Technical);
    let s_notes = style.get(Class::Notes);
    let s_scene_number = style.get(Class::SceneNumber);
    let s_scene_heading = style.get(Class::SceneHeading);
    let s_sheet_title = style.get(Class::SheetTitle);
    let s_caption = style.get(Class::Credits);

    let d_body = doc::rem(s_body.size);
    let d_title = doc::rem(s_title.size);
    let d_number = doc::rem(s_number.size);
    let d_tech = doc::rem(s_tech.size);
    let d_notes = doc::rem(s_notes.size);
    let d_scene_number = doc::rem(s_scene_number.size);
    let d_scene_heading = doc::rem(s_scene_heading.size);
    let d_sheet_title = doc::rem(s_sheet_title.size);
    let d_caption = doc::rem(s_caption.size);

    // **No case on the three he types into.** `Class::takes_case` says which,
    // and the reason is there: a page that shouts back words he wrote himself
    // is a page disagreeing with the file.
    let f_body = s_body.face.css();
    let f_title = s_title.face.css();
    let (f_number, c_number) = (s_number.face.css(), s_number.case.css());
    let (f_tech, c_tech) = (s_tech.face.css(), s_tech.case.css());
    let f_notes = s_notes.face.css();
    let (f_scene_number, c_scene_number) = (s_scene_number.face.css(), s_scene_number.case.css());
    let (f_scene_heading, c_scene_heading) =
        (s_scene_heading.face.css(), s_scene_heading.case.css());
    let (f_sheet_title, c_sheet_title) = (s_sheet_title.face.css(), s_sheet_title.case.css());
    let (f_caption, c_caption) = (s_caption.face.css(), s_caption.case.css());
    // **The ink each class is drawn in** — his ask, 2026-09-03. The document
    // page's own greys used to be `var(--muted)` here and `Brand.ink3` in the
    // app, which is the same drift the sizes had; now both read the class.
    let k_body = s_body.colour.css();
    let k_title = s_title.colour.css();
    let k_number = s_number.colour.css();
    let k_tech = s_tech.colour.css();
    let k_notes = s_notes.colour.css();
    let k_scene_number = s_scene_number.colour.css();
    let k_scene_heading = s_scene_heading.colour.css();
    let k_sheet_title = s_sheet_title.colour.css();
    let k_caption = s_caption.colour.css();
    let d_gutter = doc::rem(doc::GUTTER);
    let d_numcol = doc::rem(doc::GUTTER - doc::BESIDE_FRAME);
    let d_beside = doc::rem(doc::BESIDE_FRAME);
    let d_under = doc::rem(doc::UNDER_FRAME);
    let d_between = doc::rem(doc::BETWEEN_SHOTS * 2.0);
    let d_half_between = doc::rem(doc::BETWEEN_SHOTS);
    let d_over_scene = doc::rem(doc::OVER_SCENE);
    let d_frame_gap = doc::rem(5.0);
    // Between the title, the words, the technical line and the note — the
    // spacing of the app's own paragraph stack.
    let d_line = doc::rem(3.0);
    // The Script page's cell gutter: half the Document's number margin
    // either side of the rule between the two columns.
    let d_gutter_half = doc::rem(doc::GUTTER / 4.0);
    // A screen has no printed rectangle to give the page its margins, so the
    // share page draws them itself. On paper they come from the print rect —
    // `Printing.Kind.document.margin` — and a second inch here would be two.
    let scrollbar = if print == Print::Screen {
        String::new()
    } else {
        "html { scrollbar-width: none; }\n         ::-webkit-scrollbar { width: 0; height: 0; }"
            .to_string()
    };
    let d_pad = if print == Print::Screen {
        format!("{} {}", doc::rem(doc::MARGIN), doc::rem(doc::MARGIN))
    } else {
        "0".to_string()
    };

    format!(
        r#"{page_rule}
html {{ font-size: {root_size:.2}px; }}
:root {{
  /* **Neutral, and the same neutral the app draws.** This was `#16201b`, a
     green-black, while `Brand.ink` in the app was `#17171A` — one page set in
     two blacks depending on which surface drew it. */
  --ink: #17171a; --muted: #5c5c63; --rule: #d8dad9;
  /* Neutral, not the app's green — his call, 2026-08-24: colour on this page
     belongs to the time-of-day dot, and nowhere else, so the dot is the one
     thing your eye has to sort out. */
  --header: #1c1c1c; --stripe: #f4f7f5; --strike: #a93b2c;
  /* **The system serif first, by name and by keyword.** The app's page asks
     the system for its serif design, which is New York; naming Palatino first
     meant the two surfaces set the same paragraph in two different faces. */
  --serif: ui-serif, "New York", "Iowan Old Style", "Palatino", Georgia, serif;
  --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --mono: "SF Mono", ui-monospace, Menlo, "Roboto Mono", monospace;
}}
* {{ box-sizing: border-box; }}
/* **No scrollbar gutter on a page that is going to be paper.** The web view
   a PDF is cut out of is exactly the printable rectangle wide, and a
   scrollbar took sixteen of those points off the right-hand side of every
   sheet — so a full-width frame came out 392 points against the 408 the app
   drew, and every line broke a word earlier. Nothing on paper scrolls. */
{scrollbar}
body {{
  margin: 0; color: var(--ink); background: #fff;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  font-size: .75rem; line-height: 1.5; -webkit-font-smoothing: antialiased;
}}
.masthead {{ padding: 2rem 1.5rem 1rem; border-bottom: 2px solid var(--ink); }}
.masthead .project {{
  color: var(--muted); font-family: var(--mono); font-size: .62rem;
  letter-spacing: .14em; text-transform: uppercase; margin-bottom: .3rem;
}}
.masthead h1 {{
  margin: 0; font-size: 1.5rem; letter-spacing: -.025em; font-weight: 660;
}}
.masthead .credits {{
  color: var(--muted); font-family: var(--mono); font-size: .6rem;
  letter-spacing: .12em; text-transform: uppercase; margin-top: .35rem;
}}
/* Day or night, at a glance — the same dot the sidebar wears. Sized in `em`
   so it scales with whichever heading it sits beside, root font included. */
.tod-dot {{
  display: inline-block; width: .5em; height: .5em; border-radius: 50%;
  margin-right: .5em; vertical-align: middle;
}}
.wrap {{ padding: 1.5rem; }}
.group {{ margin-bottom: 2rem; break-inside: auto; }}
/* ---- a section, told apart ---------------------------------------------
   His ask, 2026-09-20: the printed page told a commercial's scripts apart
   with a dot and a title that could be missed on a fast leaf. Now it does
   what the app's table and the portal do: the section's head is a band
   tinted with its ink with the title set in it, and the same ink runs as a
   spine down the left of every scene and card in the run (`.insec`), so a
   page from the middle of a day still says which script it is. `--sec` and
   `--sec-rgb` come in on the elements themselves, from `section_ink`. */
.section-head {{
  display: flex; align-items: center; gap: .5rem;
  margin: 1.4rem 0 .6rem; padding: .45rem .7rem;
  background: rgba(var(--sec-rgb, 128,128,128), .10);
  font-size: 1.05rem; font-weight: 700; letter-spacing: -.01em;
  color: var(--sec, var(--ink));
  break-after: avoid; page-break-after: avoid; break-inside: avoid;
  /* One full-width row of the Storyboard page's grid, as `.group-head` is. */
  grid-column: 1 / -1;
}}
.section-head:first-child {{ margin-top: 0; }}
.section-head .section-bar {{ display: none; }}
.insec {{ padding-left: 0; }}  /* no coloured side bar: the head's tint and title carry the section */
/* Inside a day, one scene's stretch of rows: its own heading, one rank
   under the day's, and the section's spine beside it. */
.run {{ margin-bottom: 1rem; }}
.run-head {{
  display: flex; align-items: baseline; gap: .6rem;
  margin: .6rem 0 .4rem; padding-bottom: .2rem; border-bottom: 1px solid var(--rule);
  break-after: avoid; page-break-after: avoid;
  grid-column: 1 / -1;
}}
.run-head .no {{ font-family: var(--mono); font-size: .8rem; font-weight: 600; }}
.run-head h3 {{ margin: 0; font-size: .85rem; font-weight: 600; letter-spacing: -.01em; }}
.run-head .count {{
  color: var(--muted); font-family: var(--mono); font-size: .58rem;
  letter-spacing: .11em; text-transform: uppercase; margin-left: auto;
}}
.run-head + table {{ margin-top: 0; }}
.group-head {{
  display: flex; align-items: baseline; gap: .75rem; flex-wrap: wrap;
  border-bottom: 2px solid var(--ink); padding-bottom: .35rem; margin-bottom: .75rem;
  break-after: avoid; page-break-after: avoid;
  /* A no-op inside the Table page's own `<section>` — only meaningful where
     this sits directly in a grid, which is the Storyboard page's `.board`.
     Without it, a header between two scenes' cards would land inside the
     grid as one more card-sized cell instead of a header. */
  grid-column: 1 / -1;
}}
.group-head h2 {{ margin: 0; font-size: .95rem; letter-spacing: -.015em; font-weight: 660; }}
.group-head .seq {{
  color: var(--muted); font-family: var(--mono); font-size: .58rem;
  letter-spacing: .11em; text-transform: uppercase;
}}
.group-head .count {{
  color: var(--muted); font-family: var(--mono); font-size: .58rem;
  letter-spacing: .11em; text-transform: uppercase; margin-left: auto;
}}
/* `table-layout: fixed` plus a `<colgroup>` of percentages that always sum to
   100% is what keeps this table on the page — its columns take the share
   they are given rather than the share their own content would ask for, so
   eleven columns on a landscape page and four on a portrait one both fit.
   `overflow-wrap` is the second half of that promise: a word too long for
   its column breaks rather than pushing the column wider than its share. */
table {{ width: 100%; border-collapse: collapse; table-layout: fixed; }}
thead {{ display: table-header-group; }}
th {{
  background: var(--header); color: #fff; text-align: left; font-size: .56rem;
  letter-spacing: .03em; text-transform: uppercase; padding: .45rem .4rem; font-weight: 600;
  overflow-wrap: normal; word-break: normal; hyphens: none; line-height: 1.25;
}}
td {{
  padding: .4rem .45rem; vertical-align: top; border-bottom: 1px solid var(--rule);
  overflow-wrap: break-word; hyphens: auto; -webkit-hyphens: auto; font-size: .75rem;
  /* **Nothing leaves its column.** `table-layout: fixed` decides the widths
     and then lets the content overflow them anyway — which nobody saw while
     the widths were ours, and everybody would the moment he narrowed one.
     A cell that has been given less room than its words need cuts them off;
     it does not print them over the next column. */
  overflow: hidden;
}}
tbody tr:nth-child(even) {{ background: var(--stripe); }}
tr {{ break-inside: avoid; page-break-inside: avoid; }}
/* **The one column that is never cut off.** Everything else is clipped to
   its column so a narrowed one cannot print over its neighbour — but the shot
   number is what somebody reads out loud on the day, and it has always sat a
   point or two wider than its share and quietly overhung into the gap before
   the storyboard picture. Clipping it turned `33A` into `33`. It cannot wrap
   and it is five characters at the very most, so it keeps the overhang. */
td.num {{ font-weight: 600; white-space: nowrap; overflow: visible; }}
/* The one column meant to be read first — his ask, 2026-08-24: more weight
   and punch than a plain cell, the way a headline sits over its body text. */
td.title {{ font-weight: 700; font-size: .85rem; letter-spacing: -.01em; color: var(--ink); }}
/* **A frame box, not a loose picture.** Until 2026-09-01 the table drew the
   photograph whole at whatever shape it happened to be, while every screen in
   the app drew it in the film's own ratio keeping the part he chose. The page
   agrees with the app now: the box is the film's ratio and `.held` inside it
   carries the crop. */
.shotframe {{
  position: relative; display: block; width: 100%; overflow: hidden;
  border: 1px solid var(--rule); background: #f0f0f0;
}}
.shotframe img.held, .card-frame img.held {{ position: absolute; display: block; }}
/* ---- a tall row's picture column (`pictures`, `FILL_ROWS`) --------------
   The key picture at rest; under it, hidden, a clip's four moments as four
   boxes and the shot's other frames. The page's script shows what fits. */
.pictures {{ display: block; }}
.pictures .q {{
  display: block; position: relative; overflow: hidden; box-sizing: border-box;
  border: 1px solid var(--rule); background: #f0f0f0; margin-top: .25rem;
}}
.pictures .q img {{ position: absolute; display: block; }}
.pictures.stacked .shotframe.key {{ display: none; }}
.pictures.stacked .q:nth-of-type(2) {{ margin-top: 0; }}
.pictures .shotframe.more {{ margin-top: .25rem; }}
.pictures .shotframe.more[hidden] {{ display: none; }}
/* The one case with no framing to honour: a picture whose shape the shell
   could not tell us. Cover the box and keep the middle. */
.shotframe img.held.cover, .card-frame img.held.cover {{
  inset: 0; width: 100%; height: 100%; object-fit: cover;
}}
/* The marks are placed on the photograph by hand, so the blanket `inset: 0`
   below must not fight the left and top they are given. */
.shotframe > svg.marks, .card-frame > svg.marks {{ inset: auto; }}
/* **Storyboard arrows.** The SVG lies exactly over the picture it was drawn
   on; the wrapper is what gives it something to lie over. `inline-block` and
   `line-height: 0` so the wrapper is the picture's size and nothing else. */
.marked {{ position: relative; display: inline-block; line-height: 0; max-width: 100%; }}
.marked img {{ display: block; }}
svg.marks {{ position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }}
.tag {{
  display: inline-block; font-size: .62rem; padding: .1em .4em; margin: 0 .2em .2em 0;
  border: 1px solid var(--rule); border-radius: 2px; color: var(--muted);
  /* A chip is the one thing on the page that refuses to be narrower than its
     own longest word, so in a column he has pulled in it was the first thing
     to climb out of its cell. Held to the cell and cut off there — letting it
     *break* instead set one letter per line and made the row a foot tall,
     which is a worse answer than a clipped word. */
  max-width: 100%; white-space: nowrap;
}}
.camera {{ font-weight: 600; white-space: nowrap; }}
.lensmain {{ display: block; font-weight: 600; }}
.lensunder {{ display: block; font-size: 0.88em; opacity: 0.65; }}
/* **Pills** — the app's coloured tags, set for paper. The ink and the tint
   are given on each one (a value's colour is his, not the stylesheet's); this
   is the shape. Light ground only, a hairline in the same ink so a pill still
   reads where a printer drops tints, and `print-color-adjust` so the tint is
   kept where it does not. A pill wraps inside its cell and is never cut. */
.pills {{ display: flex; flex-wrap: wrap; gap: .22rem .25rem; align-items: flex-start; }}
.pill {{
  display: inline-block; box-sizing: border-box; max-width: 100%;
  font-size: .7rem; font-weight: 600; line-height: 1.2;
  padding: .1em .34em; border-radius: .3em; border: 1px solid transparent;
  white-space: normal; overflow-wrap: break-word; word-break: normal; hyphens: auto; -webkit-hyphens: auto;
  -webkit-print-color-adjust: exact; print-color-adjust: exact;
}}
table.fitted td, table.fitted .pill {{ hyphens: manual; -webkit-hyphens: manual; }}
.pillrow {{ display: flex; flex-wrap: wrap; gap: .22rem .4rem; align-items: baseline; }}
.pillnote {{ font-size: .66rem; color: var(--muted); font-variant-numeric: tabular-nums; }}
/* **Lens Stack, the second line**: filters (a ring) and modifiers (a
   diamond) in the lens colour turned down, no box. */
.stackline {{
  display: flex; flex-wrap: wrap; gap: .1rem .6rem; margin-top: .25rem;
  font-size: .62rem; line-height: 1.3;
}}
.stackline .it {{ display: inline-flex; align-items: baseline; gap: .3em; max-width: 100%; overflow-wrap: anywhere; }}
.stackline .ring, .stackline .dia {{
  display: inline-block; flex: none; width: .5em; height: .5em;
  border: 1px solid currentColor; position: relative; top: .02em;
}}
.stackline .ring {{ border-radius: 50%; }}
.stackline .dia {{ transform: rotate(45deg) scale(.82); }}
.struck {{ opacity: .55; }}
.struck td.num, .struck td.desc {{ text-decoration: line-through; }}

/* ---- the document page ------------------------------------------------
   **This is the app's Document view, set in CSS.** Every number below comes
   out of `doc` up in this file, which holds the same points `Page` in
   `studio/Sources/Document.swift` draws the editor with. Nothing here is
   chosen for the printed page alone; if it looks wrong, it looks wrong on
   screen too, and both move together.

   Three faces doing three jobs, which is what makes a page of shots
   readable rather than a wall: the description in a serif because it is the
   only thing you actually read; the technical line in mono because it is
   instrument data and should scan without being read; and the shot number
   hanging out in the margin in mono, so the text block keeps a clean left
   edge all the way down the page. */
/* **Columns, so nothing collapses.** Between a shot and the scene heading
   after it the app puts 10 points and then 13; ordinary CSS margins between
   siblings collapse to the larger of the two, so the printed page was
   shorter than the screen by 10 points a scene and the two disagreed about
   where a page ends. A flex column never collapses a margin. */
.doc-wrap {{ padding: {d_pad}; display: flex; flex-direction: column; }}
.doc-wrap .group {{ display: flex; flex-direction: column; margin-bottom: 0; }}
.shot {{
  margin: 0 0 {d_between}; padding-left: {d_gutter}; position: relative;
  break-inside: avoid; page-break-inside: avoid;
}}
.shot-letter {{
  position: absolute; left: 0; top: .1rem; width: {d_numcol}; text-align: right;
  font-family: {f_number}; font-size: {d_number}; font-weight: 600;
  letter-spacing: -.01em; color: {k_number}; font-variant-numeric: tabular-nums;
  text-transform: {c_number};
}}
/* The title reads first and reads AS a title — the body one point up, bold,
   in the same serif, which is what the page does. */
.shot-title {{
  font-family: {f_title}; font-weight: 700; font-size: {d_title};
  letter-spacing: -.01em; margin-bottom: {d_line}; color: {k_title};
}}
/* **Not upper-cased, and not tracked.** The page draws the words that are
   actually in the fields; small capitals here shouted a lens focal length
   back at him in a form the app never uses. */
.shot-tech {{
  font-family: {f_tech}; font-size: {d_tech}; text-transform: {c_tech};
  color: {k_tech}; font-style: normal; margin: {d_line} 0 0;
}}
.shot-desc {{
  font-family: {f_body}; font-size: {d_body}; line-height: 1.5;
  hanging-punctuation: first; color: {k_body};
}}
.shot-notes {{
  margin-top: {d_line}; font-family: {f_notes}; font-size: {d_notes};
  color: {k_notes}; font-style: italic; 
}}
/* The stretch of the script a shot quotes — the script's own face, quiet. */
.shot-quote {{
  margin-top: {d_line}; font-family: {f_body}; font-size: {d_notes}; line-height: 1.45;
  color: {k_notes}; padding-left: .6em; border-left: 1.5px solid var(--rule);
}}
.shot-quote p {{ margin: 0 0 .35em; }}
.shot-quote p:last-child {{ margin-bottom: 0; }}
/* A row, never a column and never wrapped — the page lays a shot's frames
   out side by side however many there are, and so does this. */
.frames {{
  display: flex; flex-wrap: nowrap; gap: {d_frame_gap}; margin-top: {d_under};
}}
/* Alongside: the frame takes its share of the measure and the text keeps the
   rest, which is what `frame_width` means on both sides. */
.shot.left, .shot.right {{ display: flex; gap: {d_beside}; align-items: flex-start; }}
/* **The words come first in the markup**, so anything listening rather than
   looking reads the shot before its pictures — which means the frame on the
   LEFT is the reversed one. It was the other way round until 2026-09-01, and
   every frame he put on the left came out of the export on the right. */
.shot.left {{ flex-direction: row-reverse; }}
.shot.left .shot-body, .shot.right .shot-body {{ flex: 1 1 auto; min-width: 0; }}
/* **It takes its share and does not give any of it back.** Left to shrink, a
   frame asked to be a third of the measure came out closer to a fifth beside
   a long description — the app hands the frame its width and lets the words
   have the rest, and this now does the same. The inline `flex-basis` beats
   the `auto` here, which is the point. */
.shot.left .frames, .shot.right .frames {{ margin-top: 0; flex: 0 0 auto; }}
.shot.above .frames {{ margin-top: 0; margin-bottom: {d_under}; }}
/* A shoot day is handed out on its own, so it starts a fresh page. */
.group.fresh-page {{ break-before: page; page-break-before: always; }}
/* A day's own sheet on the Storyboard, when the export asks for one. */
.day-sheet {{ break-before: page; page-break-before: always; }}
.frames .shotframe {{ flex: 1 1 0; min-width: 0; }}
/* A frame on the page is a rounded box and nothing else. The table's own
   `.shotframe` keeps its hairline; a document draws pictures, not cells. */
.shot .shotframe {{ border: 0; border-radius: 3px; }}
/* A scene heading is a slug line, so it is set as one: the number in mono,
   the heading in small capitals under a rule, the count out on the right —
   and never left stranded at the foot of a page. */
.scene-head, .group-head {{
  margin: {d_over_scene} 0 {d_between}; padding-bottom: {d_half_between};
  border-bottom: .5px solid var(--rule);
  display: flex; align-items: baseline; gap: {d_beside};
  break-after: avoid; page-break-after: avoid;
}}
.scene-head .no, .group-head .no {{
  font-family: {f_scene_number}; font-size: {d_scene_number}; font-weight: 700;
  text-transform: {c_scene_number}; color: {k_scene_number};
}}
.scene-head h3, .group-head h2 {{
  margin: 0; font-family: {f_scene_heading}; font-size: {d_scene_heading};
  font-weight: 700; text-transform: {c_scene_heading}; letter-spacing: .04em;
  color: {k_scene_heading};
  text-decoration: underline; text-underline-offset: .18em;
}}
.scene-head .meta, .group-head .count, .group-head .seq {{
  color: {k_caption}; font-family: {f_caption};
  font-size: {d_caption}; letter-spacing: .06em; text-transform: {c_caption};
}}
.scene-head .count, .group-head .count {{ margin-left: auto; }}
/* A section's chapter head on the Document page — the Mac's own: a bar
   in the section's ink, the title at sheet-title size, air above. No tint
   and no spine here; a document is read, not scanned. */
.doc-wrap .section-head {{
  margin: calc({d_over_scene} * 1.5) 0 2px; padding: 0; border: 0; background: none;
  display: flex; align-items: center; gap: {d_beside};
  font-family: {f_sheet_title}; font-size: {d_sheet_title}; font-weight: 700;
  letter-spacing: -.015em; text-transform: {c_sheet_title}; color: {k_sheet_title};
  break-after: avoid; page-break-after: avoid;
}}
.doc-wrap .section-head .section-bar {{
  display: block; width: 5px; height: 1.15em; border-radius: 1.5px; flex: 0 0 auto;
  background: var(--sec, var(--rule));
}}
.doc-wrap .section-head + .group, .doc-wrap .section-head + .scene-head {{ margin-top: 0; }}
.doc-wrap .section-head + .scene-head {{ margin-top: calc({d_over_scene} * .5); }}
/* A commercial scene's Video and Audio, two columns under its heading —
   what the band draws, in the body face. */
.av {{ display: flex; gap: {d_beside}; margin: 0 0 {d_between}; }}
.av .av-col {{ flex: 1 1 0; min-width: 0; }}
.av .av-label {{
  font-family: {f_caption}; font-size: {d_caption}; letter-spacing: .06em;
  text-transform: {c_caption}; color: {k_caption}; margin-bottom: .25em;
}}
.av p {{ margin: 0 0 .5em; font-family: {f_body}; font-size: {d_body}; line-height: 1.4; color: {k_body}; }}
.av p:last-child {{ margin-bottom: 0; }}
td p {{ margin: 0 0 .4em; }}
td p:last-child {{ margin-bottom: 0; }}

/* ---- the script page ----------------------------------------------------
   **The script is the spine; the shots hang off it.** His observation from
   set, 2026-09-22: the director's own document — the words down one column,
   the frames and a note beside each beat, one page-set per version — was
   the sheet everyone actually reached for. This is that sheet, drawn from
   what the film already knows: a section's script, cut wherever a shot's
   quoted stretch begins or ends, and beside each stretch the shots that
   cover it. A stretch no shot covers says so, which is the one thing his
   document could not.

   Set in the Document page's own classes and faces (`docstyle`), so the
   two read as one product: the script in the body face a shade up, the
   cue over a shot in the credits' small capitals, number and title as the
   Document draws them, frames two across at the film's ratio. Rules are
   hairlines; the page is a table because that is what reads on set. */
.sc-wrap {{ display: flex; flex-direction: column; }}
.sc-chapter {{ display: flex; flex-direction: column; }}
.sc-chapter .section-head {{
  margin: calc({d_over_scene} * 1.5) 0 {d_between}; padding: 0; border: 0; background: none;
  display: flex; align-items: center; gap: {d_beside};
  font-family: {f_sheet_title}; font-size: {d_sheet_title}; font-weight: 700;
  letter-spacing: -.015em; text-transform: {c_sheet_title}; color: {k_sheet_title};
  break-after: avoid; page-break-after: avoid;
}}
.sc-chapter .section-head .section-bar {{
  display: block; width: 5px; height: 1.15em; border-radius: 1.5px; flex: 0 0 auto;
  background: var(--sec, var(--rule));
}}
.sc-chapter .section-head .count {{
  margin-left: auto; font-family: {f_caption}; font-size: {d_caption};
  font-weight: 400; letter-spacing: .1em; text-transform: {c_caption}; color: {k_caption};
}}
.sc {{ width: 100%; border-collapse: collapse; table-layout: fixed; }}
/* **No zebra here.** `tbody tr:nth-child(even)` up in the table page's rules
   paints every other row, and this page is a real table — so a stretch with
   three lines of script and a tall row of frames beside it came out as a grey
   slab half a sheet high. The shot list stripes because eleven columns need
   the eye led across; two columns with a rule between them do not. */
.sc tbody tr {{ background: none; }}
/* **A stretch may run onto the next sheet.** Every other table keeps a
   row whole; here a long stretch with its shots beside it left most of a
   sheet blank rather than start below the last one — and asking each shot
   card to stay whole pushed a chapter's first stretch off its first sheet,
   leaving the title alone on it. Each Video/Audio row stays whole. */
.sc tr {{ break-inside: auto; page-break-inside: auto; }}
.sc col.sc-a {{ width: 37%; }}
/* An AV script: Video and Audio side by side take the wider half. */
.sc-isav col.sc-a {{ width: 50%; }}
.sc-hgrid {{ display: grid; grid-template-columns: 1fr 1fr; column-gap: {d_gutter_half}; }}
.sc-hgrid span + span {{ padding-left: {d_gutter_half}; }}
.sc-avrow {{
  display: grid; grid-template-columns: 1fr 1fr; column-gap: {d_gutter_half};
  padding: 0 0 .55em; break-inside: avoid; page-break-inside: avoid;
}}
.sc-avrow + .sc-avrow {{ padding-top: .55em; border-top: .5px dotted var(--rule); }}
.sc-avrow:last-child {{ padding-bottom: 0; }}
.sc-avrow .sc-au {{ padding-left: {d_gutter_half}; border-left: .5px solid var(--rule); }}
/* A size down, so two columns of words beside the shots do not make
   every row a page tall — his ask, 2026-10-05. */
.sc-isav .sc-script p {{
  font-size: calc({d_body} * .9); line-height: 1.4; margin-bottom: .5em;
}}
.sc th {{
  background: none; text-align: left; padding: 0 0 {d_half_between}; vertical-align: bottom;
  font-family: {f_caption}; font-size: {d_caption}; font-weight: 400;
  letter-spacing: .1em; text-transform: {c_caption}; color: {k_caption};
  border-bottom: 1px solid var(--ink);
}}
.sc th.sc-b {{ padding-left: {d_gutter_half}; }}
.sc td {{
  vertical-align: top; padding: {d_between} 0 {d_over_scene};
  border-bottom: .5px solid var(--rule);
}}
.sc td.sc-script {{ padding-right: {d_gutter_half}; }}
.sc td.sc-shots {{ padding-left: {d_gutter_half}; border-left: .5px solid var(--rule); }}
/* The words that get said — the body face, a shade up, because on this
   page they are the thing everyone reads first. */
/* **A beat is separated by a blank line, not by a bigger line gap.** At .7em
   against a 1.5 line the paragraphs read as one block, and on this page the
   paragraph break is the beat — it is what the shot beside it answers to. */
.sc-script p {{
  margin: 0 0 1em; font-family: {f_body}; font-size: {d_body};
  line-height: 1.45; color: {k_body}; hanging-punctuation: first;
}}
.sc-script p:last-child {{ margin-bottom: 0; }}
/* The place a shot without a quote is listed under — the scene, as a cue. */
.sc-where, .sc-cue {{
  font-family: {f_caption}; font-size: {d_caption}; letter-spacing: .1em;
  text-transform: {c_caption}; color: {k_caption}; line-height: 1.5;
}}
.sc-cue {{ margin-bottom: {d_line}; }}
.sc-cue .slug, .sc-where .slug {{
  display: block; margin-top: .15em;
  font-family: {f_tech}; font-size: {d_tech}; letter-spacing: 0; text-transform: none;
  color: {k_tech};
}}
.sc-shot {{ margin: 0 0 {d_over_scene}; }}
.sc-shot:last-child {{ margin-bottom: 0; }}
.sc-head {{ display: flex; align-items: baseline; gap: {d_beside}; }}
.sc-num {{
  font-family: {f_number}; font-size: {d_number}; font-weight: 600; flex: 0 0 auto;
  letter-spacing: -.01em; color: {k_number}; font-variant-numeric: tabular-nums;
  text-transform: {c_number};
}}
.sc-title {{
  font-family: {f_title}; font-weight: 700; font-size: {d_title};
  letter-spacing: -.01em; color: {k_title}; min-width: 0;
}}
.sc-tech {{
  font-family: {f_tech}; font-size: {d_tech}; text-transform: {c_tech};
  color: {k_tech}; margin-top: {d_line};
}}
.sc-desc {{
  margin-top: {d_line}; font-family: {f_body}; font-size: {d_body}; line-height: 1.5;
  color: {k_body};
}}
.sc-desc p {{ margin: 0 0 .4em; }}
.sc-desc p:last-child {{ margin-bottom: 0; }}
.sc-notes {{
  margin-top: {d_line}; font-family: {f_notes}; font-size: {d_notes};
  color: {k_notes}; font-style: italic;
}}
.sc-notes p {{ margin: 0 0 .3em; }}
.sc-notes p:last-child {{ margin-bottom: 0; }}
/* Two across, every frame the same size, a clip's four moments two by two
   — the boxes are the storyboard's own (`.card-frame`, `.held`). */
/* **Small, and beside the words** (2026-10-05, Let's Bake at 28 pages): a
   tall frame 7rem high, a wide one 6rem across (`--pic`, set per chapter
   from the film's frame), two across at most, a clip's moments two by two. */
.sc-shot.pics {{ display: grid; grid-template-columns: minmax(0, 1fr) auto; column-gap: {d_gutter_half}; }}
.sc-shot.pics .sc-cue {{ grid-column: 1 / -1; }}
.sc-frames {{
  display: flex; flex-wrap: wrap; gap: {d_frame_gap}; align-content: flex-start;
  justify-content: flex-end; width: max-content;
  max-width: calc(var(--pic, 6rem) * 2 + {d_frame_gap});
}}
.sc-frames .card-pic {{ width: var(--pic, 6rem); }}
.sc-frames .card-strip {{ display: contents; }}
.sc-shot.again {{ margin-bottom: {d_line}; }}
/* The shots, a size down beside the script — this page is for reading
   what covers which line, not for each card at full size. */
.sc-shots .sc-title {{ font-size: calc({d_title} * .82); }}
.sc-shots .sc-desc {{ font-size: calc({d_body} * .9); line-height: 1.4; }}
.sc-shots .sc-notes {{ font-size: calc({d_notes} * .92); }}
.sc-shot.again .sc-title {{ font-weight: 400; }}
.sc-shot.struck .sc-num, .sc-shot.struck .sc-title {{ text-decoration: line-through; }}
/* A stretch nobody covers. The one sentence on the page, and it is a
   warning, which is what a sentence is for. */
.sc-none {{
  font-family: {f_notes}; font-size: {d_notes}; color: var(--strike); font-style: italic;
}}
/* The whole script again at the end, to hand to whoever is saying it —
   free to run onto as many sheets as it needs (it sat in `.shot`, which
   will not break across a page, so a long one was cut off). */
.sc-body {{ margin: 0 0 {d_between}; }}
.sc-full p {{
  margin: 0 0 .8em; font-family: {f_body}; font-size: calc({d_body} * 1.12);
  line-height: 1.55; color: {k_body}; max-width: 30rem; hanging-punctuation: first;
}}

/* An AV script in full: Video beside Audio, a rule under each row. */
.sc-av {{ width: 100%; border-collapse: collapse; table-layout: fixed; }}
.sc-av col {{ width: 50%; }}
.sc-av tbody tr {{ background: none; }}
.sc-av tr {{ break-inside: avoid; page-break-inside: avoid; }}
.sc-av th {{
  background: none;
  text-align: left; padding: 0 0 {d_half_between}; font-family: {f_caption};
  font-size: {d_caption}; font-weight: 400; letter-spacing: .1em;
  text-transform: {c_caption}; color: {k_caption}; border-bottom: 1px solid var(--ink);
}}
.sc-av td {{
  vertical-align: top; padding: {d_half_between} {d_gutter_half} {d_half_between} 0;
  border-bottom: .5px solid var(--rule);
}}
.sc-av td + td, .sc-av th + th {{ padding-left: {d_gutter_half}; border-left: .5px solid var(--rule); }}
.sc-av p {{
  margin: 0 0 .5em; font-family: {f_body}; font-size: calc({d_body} * .95);
  line-height: 1.45; color: {k_body}; hanging-punctuation: first;
}}
.sc-av p:last-child {{ margin-bottom: 0; }}

/* ---- the document's masthead -------------------------------------------
   The app's own sheet head, to the point: the film, what this document is,
   and what order it is in — then the credits, then a rule. */
.sheet-head {{ border-bottom: 1px solid var(--ink); padding-bottom: 2px; }}
.sheet-head .line {{ display: flex; align-items: baseline; gap: {d_beside}; }}
.sheet-head h1 {{
  margin: 0; font-family: {f_sheet_title}; font-size: {d_sheet_title};
  font-weight: 700; letter-spacing: -.02em; text-transform: {c_sheet_title};
  color: {k_sheet_title};
}}
.sheet-head .what, .sheet-head .order, .sheet-head .project, .sheet-head .credits {{
  color: {k_caption}; font-family: {f_caption}; font-size: {d_caption};
  letter-spacing: .1em; text-transform: {c_caption};
}}
/* **One class, one ink.** SHOT LIST used to be drawn in `--ink` while the
   credits beside it were `--muted` — three colours for one kind of words, and
   the app made its own third choice again. They all read Credits now. */
.sheet-head .what {{ letter-spacing: .175em; }}
.sheet-head .order {{ margin-left: auto; }}
.sheet-head .project {{ margin-bottom: 3px; }}
.sheet-head .credits {{ margin: 3px 0 3px; }}

/* ---- the storyboard page ----------------------------------------------
   **A storyboard, not a grid of thumbnails.** His ask, 2026-09-20: *"lays
   out the frames like a proper storyboard … if there's a video with four
   frames … laid out side by side horizontally, in a row, with the details
   underneath it … make those images the centerpiece."* One shot is one
   `.card`: every frame it has in a row — a clip's four moments as four
   frames — then the words, in full, nothing clamped. The words sit beside
   the pictures when the row is short (one still, the classic frame-left,
   notes-right board) and drop underneath when the row is wide. */
.board {{ display: block; margin-bottom: .9rem; }}
.card {{
  display: flex; flex-wrap: wrap; align-items: flex-start; gap: .55rem 1.1rem;
  padding: .7rem 0 .8rem; border-bottom: 1px solid var(--rule);
  break-inside: avoid; page-break-inside: avoid;
}}
.board > .card:last-child {{ border-bottom: 0; }}
/* Room between the section's spine and the frames — his note on the first
   printed board, 2026-09-20: everything was "slammed against the coloured
   border". The spine's own gap (`.insec`, .6rem) is right for a table row
   and too tight for a row of pictures. */
.card.insec {{ padding-left: 1.2rem; }}
.card-frames {{ display: flex; flex-wrap: wrap; gap: .5rem; max-width: 100%; }}
.card-strip {{ display: contents; }}
.card-frames.wide {{ width: 100%; }}
/* One frame: the outer span is the width (`card` sets it, inline, from the
   dial, the film's ratio and how many stand in the row); the inner box is
   the film's ratio, `padding-top` a share of that width. The picture is
   placed by `held`, exactly as the table's is — the rules they share are up
   beside `.shotframe`. */
.card-pic {{ flex: 0 0 auto; }}
.card-frame {{
  position: relative; display: block; width: 100%; background: #f0f0f0;
  border: 1px solid var(--rule); overflow: hidden; box-sizing: border-box;
}}
/* The words: never narrower than this beside the pictures — wrap under
   them instead. */
.card-text {{ flex: 1 1 17rem; min-width: 0; }}
.card-head {{ display: flex; align-items: baseline; gap: .5rem; }}
.card-number {{
  font-family: var(--mono); font-size: .82rem; font-weight: 600; color: var(--ink);
  white-space: nowrap;
}}
.card-title {{ font-size: .88rem; font-weight: 700; letter-spacing: -.01em; }}
.card-desc {{ font-size: .72rem; line-height: 1.45; color: var(--ink); margin-top: .3rem; }}
.card-desc p {{ margin: 0 0 .3em; }}
.card-desc p:last-child {{ margin-bottom: 0; }}
.card-quote {{
  font-size: .68rem; line-height: 1.45; color: var(--muted); margin-top: .35rem;
  padding-left: .6em; border-left: 1.5px solid var(--rule);
}}
.card-quote p {{ margin: 0 0 .3em; }}
.card-quote p:last-child {{ margin-bottom: 0; }}
/* Every other column on the sheet, labelled — the table's headers, as small
   caps over the value, wrapped in as many as fit a line. */
.card-fields {{ display: flex; flex-wrap: wrap; gap: .35rem 1.3rem; margin-top: .5rem; }}
.card-fields .f {{ display: flex; flex-direction: column; gap: .08rem; max-width: 100%; }}
.card-fields .f.wide {{ flex-basis: 100%; }}
.card-fields .k {{
  font-family: var(--mono); font-size: .5rem; letter-spacing: .1em;
  text-transform: uppercase; color: var(--muted);
}}
.card-fields .v {{ font-size: .68rem; line-height: 1.4; color: var(--ink); overflow-wrap: break-word; }}
.struck .card-number, .struck .card-title {{ text-decoration: line-through; }}
.empty {{ color: var(--muted); padding: 3rem 0; text-align: center; }}
/* A file cannot know the list moved on, so it says when it was made. */
.snapshot {{
  margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--rule);
  color: var(--muted); font-size: .75rem;
}}
@media print {{ body {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }} }}
"#
    )
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Print {
    Screen,
    Document,
    Table,
    Storyboard,
    /// **The script down the left, the shots that cover it on the right.**
    /// His observation from set, 2026-09-22: the director's own two-column
    /// document was more use to everyone than the shot list. See `script`.
    Script,
}

/// The name on every page this app prints — his own standing credit, not a
/// project field. He is the cinematographer on everything this app is for.
const CINEMATOGRAPHER: &str = "Nathaniel Regier";

/// A scene's own PDF is titled by the scene, the way it reads at the top of
/// the Table view — `"2 INT. REMOTE MANSION (BEDROOM) - MORNING"`, not the
/// project's name repeated with a "Scene 2" buried in the body. Anything
/// wider than one scene keeps the project's own title.
fn title_line(sheet: &Sheet) -> String {
    match sheet.single_scene() {
        Some((number, heading)) if !heading.is_empty() => format!("{number} {heading}"),
        _ => sheet.project_title.clone(),
    }
}

/// The time of day, at a glance — the same colours the scene list's own dots
/// use (`Brand.timeKeyInk` in `Theme.swift`), read off the heading itself
/// rather than a separate field, since the heading already says "DAY" or
/// "NIGHT" or "DUSK" and a scene heading in an export has no other field to
/// ask.
///
/// A temperature scale over four times of day, not three buckets: night the
/// coolest, sunrise second, day the brightest, sunset the warmest. **Order
/// matters and is not alphabetical** — `NIGHTFALL` before `NIGHT`, `DAYBREAK`
/// before `DAY`, and the two-word hours before any of them.
///
/// Far more words are read here than there are answers, on purpose. MORNING,
/// AFTERNOON, EVENING, DUSK and MAGIC HOUR stopped being times of day, but a
/// printed heading is the script's own raw text and may still say any of them.
///
/// The printed sheet is paper, so there is only the light half of the ramp
/// here; the app lifts the same seven for its dark ground.
fn time_of_day_colour(heading: &str) -> Option<&'static str> {
    const WORDS: [(&str, &str); 19] = [
        ("MAGIC", "#DC7324"),
        ("GOLDEN", "#DC7324"),
        ("SUNSET", "#DC7324"),
        ("SUNDOWN", "#DC7324"),
        ("EVENING", "#DC7324"),
        ("NIGHTFALL", "#DC7324"),
        ("TWILIGHT", "#DC7324"),
        ("DUSK", "#DC7324"),
        ("SUNRISE", "#6E9BD1"),
        ("DAYBREAK", "#6E9BD1"),
        ("SUNUP", "#6E9BD1"),
        ("DAWN", "#6E9BD1"),
        ("MIDNIGHT", "#2B4E9E"),
        ("NIGHT", "#2B4E9E"),
        ("MORNING", "#E8B14A"),
        ("AFTERNOON", "#E8B14A"),
        ("NOON", "#E8B14A"),
        ("MIDDAY", "#E8B14A"),
        ("DAY", "#E8B14A"),
    ];
    let word = heading.to_uppercase();
    WORDS.iter().find(|(needle, _)| word.contains(needle)).map(|(_, ink)| *ink)
}

/// The dot itself, or nothing when the heading says no time of day at all.
fn tod_dot(heading: &str) -> String {
    match time_of_day_colour(heading) {
        Some(colour) => format!("<span class=\"tod-dot\" style=\"background:{colour}\"></span>"),
        None => String::new(),
    }
}

fn masthead(sheet: &Sheet) -> String {
    let mut credits = vec![format!("Cinematography by {CINEMATOGRAPHER}")];
    if !sheet.director.is_empty() {
        credits.push(format!("Directed by {}", esc(&sheet.director)));
    }
    if !sheet.producer.is_empty() {
        credits.push(format!("Produced by {}", esc(&sheet.producer)));
    }
    // A scene's own PDF titles itself by the scene — but the project it
    // belongs to still has to be somewhere on the page, so it rides above
    // the title as a small kicker rather than being dropped. Wider than one
    // scene, the title already *is* the project name; saying it twice would
    // be the same mistake the "Scene 2" header was.
    let kicker = match sheet.single_scene() {
        Some(_) if !sheet.project_title.is_empty() => {
            format!("<div class=\"project\">{}</div>", esc(&sheet.project_title))
        }
        _ => String::new(),
    };
    let dot = match sheet.single_scene() {
        Some((_, heading)) => tod_dot(heading),
        None => String::new(),
    };
    format!(
        "<header class=\"masthead\">{kicker}<h1>{dot}{}</h1><div class=\"credits\">{}</div></header>",
        esc(&title_line(sheet)),
        credits.join(" · ")
    )
}

/// **The document's own masthead — the app's sheet head, exactly.**
///
/// The film, the words SHOT LIST, and what order the list is in, on one line;
/// the credits under it; a rule under that. `caption` is what the app writes
/// in its own top-right corner — `SCRIPT ORDER`, `BY SHOOT DAY · 2 SCENES NOT
/// SHOWN` — and it comes from the shell because only the shell knows how the
/// scene list is being read. Given nothing, the line is simply not drawn.
fn doc_masthead(sheet: &Sheet, caption: &str) -> String {
    doc_masthead_saying(sheet, "Shot list", caption)
}

/// The same head with a different word beside the title — `Script` for
/// the Script page — and no order line, since a script has one order.
fn doc_masthead_titled(sheet: &Sheet, what: &str) -> String {
    doc_masthead_saying(sheet, what, "")
}

fn doc_masthead_saying(sheet: &Sheet, what: &str, caption: &str) -> String {
    let mut credits = vec![format!("Cinematography by {CINEMATOGRAPHER}")];
    if !sheet.director.is_empty() {
        credits.push(format!("Directed by {}", esc(&sheet.director)));
    }
    if !sheet.producer.is_empty() {
        credits.push(format!("Produced by {}", esc(&sheet.producer)));
    }
    // A scene's own PDF titles itself by the scene — but the project it
    // belongs to still has to be somewhere on the page, so it rides above
    // the title as a small kicker rather than being dropped.
    let kicker = match sheet.single_scene() {
        Some(_) if !sheet.project_title.is_empty() => {
            format!("<div class=\"project\">{}</div>", esc(&sheet.project_title))
        }
        _ => String::new(),
    };
    let dot = match sheet.single_scene() {
        Some((_, heading)) => tod_dot(heading),
        None => String::new(),
    };
    let order = if caption.is_empty() {
        String::new()
    } else {
        format!("<span class=\"order\">{}</span>", esc(caption))
    };
    format!(
        "<header class=\"sheet-head\">{kicker}\
         <div class=\"line\"><h1>{dot}{}</h1>\
         <span class=\"what\">{}</span>{order}</div>\
         <div class=\"credits\">{}</div></header>",
        esc(&title_line(sheet)),
        esc(what),
        credits.join(" · ")
    )
}

/// The `<title>` tag — the scene's own heading needs no suffix explaining
/// what kind of page it is; a whole project's does.
fn page_title(sheet: &Sheet, suffix: &str) -> String {
    match sheet.single_scene() {
        Some(_) => title_line(sheet),
        None => format!("{} — {suffix}", sheet.project_title),
    }
}

/// **The colour a column's pills wear** — mirrored from `Brand.columnInks` in
/// `studio/Sources/Theme.swift`, and the same eight hues (`Swatches.inks`) a
/// column he made himself is hashed into, so the page and the app agree.
const COLUMN_INKS: [(&str, &str); 10] = [
    ("size", "2B6CB0"), ("angle", "7B4BC4"), ("movement", "9A6B10"),
    ("lens", "2C7A7B"), ("modifiers", "2C7A7B"), ("lens_filters", "2C7A7B"),
    ("support", "B4531B"), ("tags", "A33574"), ("priority", "4C51BF"), ("pov", "2F7A44"),
];
const SWATCH_INKS: [&str; 8] = ["2C7A7B", "2B6CB0", "4C51BF", "7B4BC4", "A33574", "9A6B10", "2F7A44", "B4531B"];

fn column_ink(field: &str) -> String {
    if let Some((_, hex)) = COLUMN_INKS.iter().find(|(f, _)| *f == field) {
        return hex.to_string();
    }
    let key = field.trim().to_lowercase();
    if key.is_empty() {
        return "5C5C63".to_string();
    }
    let mut hash: u64 = 5381;
    for byte in key.bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(byte as u64);
    }
    SWATCH_INKS[(hash % SWATCH_INKS.len() as u64) as usize].to_string()
}

/// A term he has coloured by hand keeps that colour; everything else wears
/// its column's (`Brand.chipInk`).
fn pill_ink(sheet: &Sheet, field: &str, value: &str) -> String {
    let wanted = value.trim().to_lowercase();
    sheet
        .term_inks
        .iter()
        .find(|(f, term, _)| f == field && *term == wanted)
        .map(|(_, _, hex)| hex.clone())
        .unwrap_or_else(|| column_ink(field))
}

/// `RRGGBB` (or `#rgb`) as three bytes; a colour that is not one is grey.
fn ink_rgb(hex: &str) -> (u8, u8, u8) {
    let said = if hex.trim().starts_with('#') { hex.trim().to_string() } else { format!("#{}", hex.trim()) };
    hex_rgb(&said).unwrap_or((0x5c, 0x5c, 0x63))
}

/// One pill: the ink for the words, a light tint of it behind, a hairline of
/// it round the edge. The app's own recipe is ink at 13% over the page.
fn pill(text: &str, hex: &str) -> String {
    let (r, g, b) = ink_rgb(hex);
    format!(
        "<span class=\"pill\" style=\"color:rgb({r},{g},{b});background:rgba({r},{g},{b},.13);\
         border-color:rgba({r},{g},{b},.45)\">{}</span>",
        esc(text)
    )
}

fn pills_of(sheet: &Sheet, field: &str, values: &[String]) -> String {
    let all: String = values
        .iter()
        .filter(|v| !v.trim().is_empty())
        .map(|v| pill(v, &pill_ink(sheet, field, v)))
        .collect();
    if all.is_empty() { all } else { format!("<span class=\"pills\">{all}</span>") }
}

/// Lens Stack's second line: a ring per filter, a diamond per modifier, in
/// the lens colour, under the lens pill.
fn stack_line(row: &Row, ink: &str) -> String {
    let (r, g, b) = ink_rgb(ink);
    let item = |class: &str, name: &String| format!("<span class=\"it\"><i class=\"{class}\"></i>{}</span>", esc(name));
    let items: String = row
        .lens_filters
        .iter()
        .map(|n| item("ring", n))
        .chain(row.modifiers.iter().map(|n| item("dia", n)))
        .collect();
    format!("<div class=\"stackline\" style=\"color:rgba({r},{g},{b},.9)\">{items}</div>")
}

fn page(title: &str, print: Print, scale: f64, size: FrameSize, body: String,
        style: &Style) -> String {
    page_with_columns(title, print, scale, size, body, &[], style)
}

fn page_with_columns(
    title: &str,
    print: Print,
    scale: f64,
    size: FrameSize,
    body: String,
    columns: &[String],
    style: &Style,
) -> String {
    // What was on screen when this was made. A reader can hide columns within
    // this set and no wider — you cannot reveal what was never shared.
    let carried = if columns.is_empty() {
        String::new()
    } else {
        format!(" data-columns=\"{}\"", esc(&columns.join(" ")))
    };
    format!(
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n\
         <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n\
         <title>{}</title>\n<style>{}</style>\n</head>\n<body{carried}>\n{}\n</body>\n</html>\n",
        esc(title),
        stylesheet(print, scale, size, style),
        body
    )
}

// ---- table --------------------------------------------------------------

/// How much of the table's width a column is worth relative to the others —
/// so the table always fits the page it prints on, whatever the paper size
/// and however many columns happen to be on screen when it is made. Used to
/// build a `<colgroup>` of percentages that sum to 100% every time, which is
/// the fix for a table that used to size every column to its own content and
/// run the right-hand ones off the edge of the page — his report, 2026-08-24,
/// on a Notes column that came back as a strip of first letters.
/// **His own say over how wide a column prints.**
///
/// His ask, 2026-09-01: *"i would love to be able to adjust column sizes
/// manually during export for table."* The weights below are good defaults and
/// were never his to change — but the right share depends on the film, and on
/// an eleven-column sheet it is also the only thing that stops a header word
/// breaking in half.
///
/// **A multiplier, not a width.** He sets "one and a half times whatever this
/// page thinks Description is worth", so the shell never has to know or copy
/// the numbers below — which is what keeps this the only place they live. The
/// page still normalises everything to 100% at the end, so the columns cannot
/// stop adding up to a sheet of paper however hard he pulls.
#[derive(Clone, Debug, Default)]
pub struct ColumnWidths {
    factors: Vec<(String, f64)>,
    /// **Auto's own shares, exactly** (`autolayout::Plan`), in percent by
    /// field. When given they are the widths, and the weights and
    /// multipliers are not consulted at all.
    shares: Vec<(String, f64)>,
    /// **Every word fits** — Auto found a sheet with no word cut, so the
    /// page turns hyphenation off (`table.fitted`). Left off when some word
    /// cannot fit, where a proper hyphen is better than a raw split.
    pub fitted: bool,
}

impl ColumnWidths {
    /// `description:1.5,notes:0.7` — what the shell sends. Anything
    /// unparseable is skipped rather than failing the export: a bad dial is
    /// not a reason to refuse somebody their shot list.
    pub fn read(said: &str) -> ColumnWidths {
        let mut factors = Vec::new();
        for part in said.split(',').filter(|p| !p.trim().is_empty()) {
            let Some((field, value)) = part.split_once(':') else { continue };
            let Ok(factor) = value.trim().parse::<f64>() else { continue };
            if factor.is_finite() && factor > 0.0 {
                // Clamped here rather than trusted: a column at forty times
                // its share leaves the others a hairline, and `table-layout:
                // fixed` would draw exactly that.
                factors.push((field.trim().to_string(), factor.clamp(0.2, 5.0)));
            }
        }
        ColumnWidths { factors, shares: Vec::new(), fitted: false }
    }

    /// `number:4.1,image:18.2,…` — Auto's shares, in percent, as the shell
    /// hands them back. Unparseable parts are skipped, like `read`.
    pub fn exact(said: &str) -> ColumnWidths {
        let shares = said
            .split(',')
            .filter_map(|part| {
                let (field, value) = part.split_once(':')?;
                let v = value.trim().parse::<f64>().ok()?;
                (v.is_finite() && v > 0.0).then(|| (field.trim().to_string(), v))
            })
            .collect();
        ColumnWidths { factors: Vec::new(), shares, fitted: false }
    }

    /// Whether exact shares are given for every one of these columns.
    fn has_exact(&self, columns: &[&str]) -> bool {
        !self.shares.is_empty() && columns.iter().all(|c| self.shares.iter().any(|(f, _)| f == c))
    }

    /// The same, from a plan in hand.
    pub fn from_shares(shares: &[(String, f64)]) -> ColumnWidths {
        ColumnWidths { factors: Vec::new(), shares: shares.to_vec(), fitted: false }
    }

    pub fn is_empty(&self) -> bool {
        self.factors.is_empty() && self.shares.is_empty()
    }

    fn factor(&self, field: &str) -> f64 {
        self.factors
            .iter()
            .find(|(name, _)| name == field)
            .map(|(_, f)| *f)
            .unwrap_or(1.0)
    }
}

/// What each column of the printed table is worth before he touches anything —
/// so the export dialog can show him the share a column is about to take
/// without keeping its own copy of the numbers.
pub fn default_column_weights(sheet: &Sheet, size: FrameSize) -> Vec<(String, f64)> {
    table_columns(sheet)
        .into_iter()
        .map(|c| (c.to_string(), column_weight(c, size, &ColumnWidths::default())))
        .collect()
}

/// A column's own weight at a picture size, before any multiplier — what
/// Auto's shares are turned back into multipliers against (`autolayout`).
pub(crate) fn base_weight(field: &str, size: FrameSize) -> f64 {
    base_column_weight(field, size)
}

/// The shares the page prints with when nobody has touched a width — today's
/// default, for Auto to be measured against.
pub(crate) fn default_shares(sheet: &Sheet, size: FrameSize) -> Vec<f64> {
    let columns = table_columns(sheet);
    let plain = ColumnWidths::default();
    pill_floors(&columns, column_shares(&columns, size, &plain), &plain)
}

fn column_weight(field: &str, size: FrameSize, widths: &ColumnWidths) -> f64 {
    base_column_weight(field, size) * widths.factor(field)
}

fn base_column_weight(field: &str, size: FrameSize) -> f64 {
    match field {
        "number" => 0.55,
        "description" => 2.8,
        "script" => 2.4,
        "notes" => 1.5,
        "title" => 1.2,
        // **Pills carry padding and a hairline, so the columns that hold them
        // are a little wider than plain words needed**: a pill whose word does
        // not fit breaks it, which is the one thing it must not do.
        "tags" => 1.7,
        "size" => 1.25,
        "angle" => 1.35,
        "lens" => 1.3,
        // The one column with a dial on it, because it is the one whose right
        // size depends on what is in it — one still, or a clip's four moments.
        "image" => size.column_weight(),
        // **Only the two that genuinely hold more than a token.** Taking
        // width *from* `size` and `lens` to give it to `support` was tried
        // and made things worse in both directions — width here is zero-sum,
        // and at eleven columns none of them has any to spare. What actually
        // buys room is smaller type, which is the caller's `scale` to set;
        // a per-day sheet asks for less than a single scene's page does.
        "support" => 1.6,   // Handheld, Dana Dolly
        "movement" => 1.35, // Tracking Backward, Follow Action
        "day" => 0.8,       // Day 1, and never longer
        _ => 1.0,
    }
}

/// Every column this table prints, leading with the shot number — never
/// optional, never hidden — followed by whatever the on-screen Table view is
/// showing, in its own order. What lands on the page is exactly what was on
/// screen when it was made, title included.
pub(crate) fn table_columns(sheet: &Sheet) -> Vec<&str> {
    let mut out = vec!["number"];
    out.extend(sheet.columns.iter().map(|c| c.as_str()));
    out
}

pub(crate) fn column_header<'a>(sheet: &'a Sheet, field: &'a str) -> &'a str {
    match field {
        "number" => "#",
        "sequence" if sheet.commercial => "Section",
        other => sheet
            .own_columns
            .iter()
            .find(|(slug, _)| slug == other)
            .map(|(_, label)| label.as_str())
            .unwrap_or_else(|| crate::columns::label_for(other)),
    }
}

/// An AV script's marks as paragraph breaks — a stretch that runs from a
/// row's Video into its Audio reads as the two things it is.
fn av_words(text: &str) -> String {
    text.replace([crate::quoting::AV_CELL, crate::quoting::AV_ROW], "\n\n")
}

/// **The whole script, as it was written**: plain text as paragraphs, an
/// AV script as its two columns, Video beside Audio, a row to a row.
fn full_script(text: &str) -> String {
    if !crate::quoting::is_av(text) {
        return paragraphs(text);
    }
    let mut out = String::from(
        "<table class=\"sc-av\"><colgroup><col><col></colgroup>\
         <thead><tr><th>Video</th><th>Audio</th></tr></thead><tbody>",
    );
    for (video, audio) in crate::quoting::av_rows(text) {
        if video.trim().is_empty() && audio.trim().is_empty() {
            continue;
        }
        out.push_str(&format!("<tr><td>{}</td><td>{}</td></tr>", paragraphs(&video), paragraphs(&audio)));
    }
    out.push_str("</tbody></table>");
    out
}

/// Blank-line paragraphs kept as paragraphs; single breaks as breaks.
fn paragraphs(text: &str) -> String {
    text.split("\n\n")
        .map(str::trim)
        .filter(|p| !p.is_empty())
        .map(|p| format!("<p>{}</p>", esc(p).replace('\n', "<br>")))
        .collect()
}

fn table_cell_class(field: &str) -> &str {
    match field {
        "number" => " class=\"num\"",
        "image" => " class=\"frame\"",
        "description" => " class=\"desc\"",
        "title" => " class=\"title\"",
        _ => "",
    }
}

/// **The picture column of a table row — and what it becomes when the row
/// is tall.** His idea, 2026-09-20: *"if the rows are taller than the media
/// card and the shot has more than one frame or a video broken up into 4
/// frames, it should arrange the frames in the best way possible to use the
/// space … it should dynamically adapt depending on the size of text and
/// how much space there is."*
///
/// The cell carries more than it shows: the key picture as always, then a
/// clip's four moments as four boxes each showing one quarter of the same
/// strip (`quadrants`), and every other frame on the shot, hidden. Nothing
/// here knows how tall the row will be — the words in the other columns
/// decide that, after layout — so the page's own script (`FILL_ROWS`)
/// measures each row once it is drawn and turns on what fits: the four
/// moments in whichever arrangement makes each biggest, then as many of
/// the other frames as fit under. A row never grows for it; only the
/// white space goes.
fn pictures(row: &Row, frames: Frames, ratio: f64) -> String {
    // **A baked Print Frame is the shot's one picture** — its own shape,
    // never cropped, and no marks of its own: the board already carries them.
    if let Some(pf) = row.print_frame.as_ref().filter(|p| p.is_usable()) {
        return format!("<span class=\"pictures\">{}</span>", print_frame_box("shotframe key", pf));
    }
    let Some(key) = row.key_frame.and_then(|id| frames(id, row.key_frame_trim)) else {
        return String::new();
    };
    let box_top = 100.0 / ratio.max(0.01);
    // A strip carries the geometry of its quarters; the script builds the
    // four boxes from the one picture only when it stacks them. **The
    // picture is in the page once and drawn as an `<img>`** — as a CSS
    // background WebKit wrote it into the PDF at full size, and a day's
    // table weighed three times its document (52 MB against 17).
    let quarters = if key.moments == 4 {
        format!(" data-moments=\"4\" data-quarter=\"{}\"", quarter_geometry(&key, ratio))
    } else {
        String::new()
    };
    let mut out = format!(
        "<span class=\"pictures\"{quarters}>\
         <span class=\"shotframe key\" style=\"padding-top:{box_top:.2}%\">{}</span>",
        held(&key, &row.key_frame_marks, ratio)
    );
    // The shot's other frames, in order, hidden until the row's height says
    // there is room. A clip among them is one still here, not a strip: the
    // strip belongs to the key alone.
    for id in row.frames.iter().filter(|id| Some(**id) != row.key_frame) {
        let Some(frame) = frames(*id, None) else { continue };
        out.push_str(&format!(
            "<span class=\"shotframe more\" hidden style=\"padding-top:{box_top:.2}%\">{}</span>",
            held(&frame, &Marks::default(), ratio)
        ));
    }
    out.push_str("</span>");
    out
}

/// **A baked Print Frame in its box.** The box is the picture's own shape —
/// `padding-top` is its height over its width — so the board is drawn whole,
/// edge to edge, never cropped to the film's ratio and never stretched.
fn print_frame_box(class: &str, pf: &PrintPicture) -> String {
    format!(
        "<span class=\"{class} printframe\" style=\"padding-top:{:.2}%\">\
         <img class=\"held\" style=\"left:0%;top:0%;width:100%\" src=\"{}\" alt=\"\"></span>",
        100.0 * pf.height / pf.width,
        esc(&pf.src)
    )
}

/// **The geometry of a strip's four quarters**, for the script that draws
/// them: the quarter's height as a share of its width, and the strip's
/// width and height as a percentage of one quarter's — how big the one
/// picture is drawn inside a quarter-sized box, pinned to the matching
/// corner, so the box shows exactly that quarter and none of the gutter.
/// The Mac lays the four moments two by two with a gutter of 2.8% of the
/// longer side between them (`Filmstrip.gutterShare` — **if one changes
/// the other has to**), so each quarter is `(W − g) / 2` by `(H − g) / 2`.
fn quarter_geometry(strip: &Frame, ratio: f64) -> String {
    let (w, h) = if strip.width > 0.0 && strip.height > 0.0 {
        (strip.width, strip.height)
    } else {
        (ratio.max(0.01) * 1000.0, 1000.0)
    };
    let gutter = (w.max(h) * 0.028).round();
    let (qw, qh) = ((w - gutter) / 2.0, (h - gutter) / 2.0);
    format!(
        "{:.4} {:.2} {:.2}",
        if qw > 0.0 { qh / qw } else { 1.0 / ratio.max(0.01) },
        100.0 * w / qw.max(1.0),
        100.0 * h / qh.max(1.0)
    )
}

/// **The script the table page carries, which fills a tall row's picture
/// column after layout.** It runs once the page is drawn — in the Mac's
/// renderer before it measures the rows to cut sheets, on the phone, and in
/// a browser — and only ever shows what already fits, so no row grows.
/// A clip's four moments take whichever arrangement makes each one
/// biggest: two by two, or one column as wide as the row's height allows.
const FILL_ROWS: &str = r#"<script>
(() => {
  const gap = parseFloat(getComputedStyle(document.documentElement).fontSize) * 0.25;
  for (const tr of document.querySelectorAll('tbody tr')) {
    const box = tr.querySelector('td .pictures');
    if (!box) continue;
    const key = box.querySelector('.shotframe.key');
    if (!key) continue;
    const cell = box.closest('td');
    const pad = getComputedStyle(cell);
    const avail = tr.getBoundingClientRect().height
      - parseFloat(pad.paddingTop) - parseFloat(pad.paddingBottom);
    const width = key.getBoundingClientRect().width;
    const unit = key.getBoundingClientRect().height;
    if (!(unit > 0) || !(width > 0)) continue;
    let used = unit;
    const img = key.querySelector('img');
    if (box.dataset.moments === '4' && box.dataset.quarter && img) {
      // **Whichever arrangement makes each picture biggest.** His rule,
      // 2026-09-20. Two by two gives each moment half the column. One
      // column gives each the whole width if four stand in the row's
      // height, and otherwise as wide as the height allows — which still
      // beats half the column whenever the row is more than twice a
      // picture tall. Four across never wins in a column this narrow.
      const [tall, wide, high] = box.dataset.quarter.split(' ').map(Number);
      const byWidth = width;
      const byHeight = ((avail - 3 * gap) / 4) / tall;
      const stackedWide = Math.min(byWidth, byHeight);
      const twoByTwo = (width - gap) / 2;
      if (stackedWide > twoByTwo) {
        // The four quarters, built here from the one picture: the same
        // source, so it is decoded once and drawn at the size it is shown.
        const corners = [[0, 0], [1, 0], [0, 1], [1, 1]];
        for (const [x, y] of corners) {
          const q = document.createElement('span');
          q.className = 'q';
          q.style.width = stackedWide + 'px';
          q.style.paddingTop = (stackedWide * tall) + 'px';
          const pic = document.createElement('img');
          pic.src = img.src;
          pic.alt = '';
          pic.style.width = wide + '%';
          pic.style.left = (-(wide - 100) * x) + '%';
          pic.style.top = (-(high - 100) * y) + '%';
          q.appendChild(pic);
          box.appendChild(q);
        }
        box.classList.add('stacked');
        used = 4 * stackedWide * tall + 3 * gap;
      }
    }
    // Then the shot's other frames, at the column's width, as many as
    // fit under what is already drawn.
    for (const more of box.querySelectorAll('.shotframe.more')) {
      if (used + gap + unit > avail + 0.5) break;
      more.hidden = false;
      used += gap + unit;
    }
  }
})();
</script>"#;

/// **The script the storyboard page carries**, which hands a strip's three
/// other quarters the picture the first one holds. The strip is in the page
/// once (`frame_boxes`); the boxes and their geometry are all in the markup,
/// so the layout — and the Mac's measuring of it — is the same with or
/// without this. Only the pictures in boxes two to four need it.
const FILL_STRIPS: &str = r#"<script>
(() => {
  for (const strip of document.querySelectorAll('.card-strip')) {
    const first = strip.querySelector('img[src]');
    if (!first) continue;
    for (const img of strip.querySelectorAll('img:not([src])')) img.src = first.src;
  }
})();
</script>"#;

fn table_cell(sheet: &Sheet, row: &Row, field: &str, frames: Frames, ratio: f64) -> String {
    match field {
        "number" => esc(&row.number),
        // **A frame box at the film's ratio**, keeping the part he chose —
        // the same picture the app's own table draws. It used to be the whole
        // photograph at whatever shape it happened to be, which threw the crop
        // away and made a portrait still tower over its row.
        "image" => pictures(row, frames, ratio),
        "title" => esc(&row.title),
        "description" => esc(&row.description),
        // The quoted script, paragraph by paragraph.
        "script" => paragraphs(&row.script),
        "size" => pills_of(sheet, "size", std::slice::from_ref(&row.size)),
        "angle" => pills_of(sheet, "angle", &row.angle),
        "movement" => pills_of(sheet, "movement", std::slice::from_ref(&row.movement)),
        // The unit's label in the unit's own colour, its body quiet beside it.
        "camera" => row
            .camera
            .as_ref()
            .map(|c| {
                let ink = c.colour.clone().filter(|h| !h.trim().is_empty()).unwrap_or_default();
                let body = if c.body.is_empty() || c.label.is_empty() {
                    String::new()
                } else {
                    format!("<span class=\"pillnote\">{}</span>", esc(&c.body))
                };
                let label = if c.label.is_empty() { &c.body } else { &c.label };
                format!("<span class=\"pillrow\">{}{body}</span>", pill(label, &ink))
            })
            .unwrap_or_default(),
        "lens" => {
            // The lens as a pill — a zoom's set length plain beside it, as the
            // app draws it — and, with Lens Stack on, its filters and
            // modifiers on a quiet line under.
            let main = if row.lens.trim().is_empty() {
                String::new()
            } else {
                let set = match row.focal {
                    Some(mm) => format!("<span class=\"pillnote\">{}mm</span>", mm.round() as i64),
                    None => String::new(),
                };
                format!(
                    "<span class=\"pillrow\">{}{set}</span>",
                    pill(&row.lens, &pill_ink(sheet, "lens", &row.lens))
                )
            };
            if row.stack_parts().is_empty() {
                main
            } else {
                format!("{main}{}", stack_line(row, &column_ink("lens")))
            }
        }
        "modifiers" => pills_of(sheet, "modifiers", &row.modifiers),
        "lens_filters" => pills_of(sheet, "lens_filters", &row.lens_filters),
        "support" => pills_of(sheet, "support", std::slice::from_ref(&row.support)),
        "notes" => esc(&row.notes),
        "tags" => pills_of(sheet, "tags", &row.tags),
        "day" => row.day_label.as_deref().map(esc).unwrap_or_default(),
        "sequence" => row.sequence.as_deref().map(esc).unwrap_or_default(),
        "struck" => if row.struck { pill("SHOT", "9A6B10") } else { String::new() },
        other => match row.own_pills.iter().find(|(slug, _)| slug == other) {
            // A project's own pick-one or pick-many column: pills, like the app.
            Some((slug, parts)) => pills_of(sheet, slug, parts),
            None => row
                .own
                .iter()
                .find(|(slug, _)| slug == other)
                .map(|(_, words)| esc(words))
                .unwrap_or_default(),
        },
    }
}

/// The header a group of rows or cards gets, when a sheet has more than
/// one — a scene's own heading and time-of-day dot when grouped by scene,
/// otherwise the group's own label (a day, a sequence). Shared by the Table
/// and Storyboard pages so the two can never say a scene's name differently.
fn group_heading(sheet: &Sheet, group: &RowGroup) -> String {
    let dot = if sheet.grouped_by == GroupBy::Scene {
        group.rows.first().map(|row| tod_dot(&row.scene_heading)).unwrap_or_default()
    } else {
        String::new()
    };
    let heading = if sheet.grouped_by == GroupBy::Scene {
        group
            .rows
            .first()
            .map(|row| format!("{}: {}", group.label, row.scene_heading))
            .unwrap_or_else(|| group.label.clone())
    } else {
        group.label.clone()
    };
    format!(
        "<div class=\"group-head\"><h2>{dot}{}</h2>\
         <span class=\"count\">{} shot{}</span></div>\n",
        esc(&heading),
        group.count(),
        if group.count() == 1 { "" } else { "s" }
    )
}

/// **A stretch of one scene inside a group** — the unit the three pages
/// draw a heading over. Grouped by scene the group is one run and its own
/// heading; grouped by day (or anything else) a day's rows are cut where
/// the scene changes, in the order the board has them, so a day's page
/// reads the board and still says which scene, and which script, every
/// shot is in. His ask, 2026-09-20: *"when it comes to exporting a shoot
/// day … it needs to be clear what 'script' each shot is apart of still."*
struct Run<'a> {
    rows: &'a [Row],
    /// The section this scene is in — from the group when grouped by
    /// scene, from the rows otherwise — and whether it begins a run of
    /// scenes in that section, which is when the section's head is drawn.
    section: Option<&'a Section>,
    section_starts: bool,
    /// Whether this run needs a scene heading of its own — never when the
    /// group *is* the scene, whose heading is the group's.
    scene_starts: bool,
}

fn runs<'a>(sheet: &'a Sheet, group: &'a RowGroup) -> Vec<Run<'a>> {
    if sheet.grouped_by == GroupBy::Scene {
        return vec![Run {
            rows: &group.rows,
            section: group.section.as_ref(),
            section_starts: group.section_starts,
            scene_starts: false,
        }];
    }
    // Grouped by sequence the group *is* the section and says so in its
    // own heading; a head inside it would say the same thing twice. The
    // ink still runs down the scenes, as it does everywhere.
    let by_section = sheet.grouped_by == GroupBy::Sequence;
    let mut out: Vec<Run<'a>> = Vec::new();
    let mut from = 0;
    while from < group.rows.len() {
        let scene = group.rows[from].scene;
        let to = group.rows[from..]
            .iter()
            .position(|r| r.scene != scene)
            .map(|n| from + n)
            .unwrap_or(group.rows.len());
        let section = group.rows[from].section.as_ref();
        let last = out.last().and_then(|r: &Run| r.section);
        out.push(Run {
            rows: &group.rows[from..to],
            section,
            section_starts: !by_section && section.is_some() && section != last,
            scene_starts: true,
        });
        from = to;
    }
    out
}

/// **A section's head, over the first scene of its run** — and the same
/// ink runs down the left of every scene and card in the run
/// (`section_ink`), so a fast leaf through the sheets says which script
/// this is before a word is read. His ask, 2026-09-20: *"a clear
/// distinction between scripts and sections just like the web portal and
/// shotlister app do — right now it's a small banner that could easily get
/// lost."* The head is tinted with the section's ink and its title set in
/// it, as the app's band and the portal's `.sectionhead` are; on the
/// Document page the same element is the chapter head the Mac draws — a
/// bar in the ink, a big title, air above.
fn section_head(run: &Run) -> String {
    if !run.section_starts {
        return String::new();
    }
    let Some(section) = run.section else {
        return String::new();
    };
    format!(
        "<div class=\"section-head\"{}><span class=\"section-bar\"></span>\
         <span class=\"section-title\">{}</span></div>\n",
        section_ink(run),
        esc(&section.title)
    )
}

/// The section's ink, as a style attribute for whatever is in the run —
/// `--sec` the hex and `--sec-rgb` the same as `r,g,b` for the tint — the
/// two variables the portal's stylesheet reads by the same names. Empty on
/// a film scene in no section, or a section with no colour, so nothing is
/// drawn.
fn section_ink(run: &Run) -> String {
    let Some(section) = run.section else {
        return String::new();
    };
    let Some((r, g, b)) = hex_rgb(&section.colour) else {
        return String::new();
    };
    format!(
        " style=\"--sec:{};--sec-rgb:{r},{g},{b}\"",
        esc(section.colour.trim())
    )
}

/// The class a group, run or card in a section's run wears, beside its own.
fn section_class(run: &Run) -> &'static str {
    if section_ink(run).is_empty() { "" } else { " insec" }
}

/// **A scene's heading inside a group that is not the scene** — a day's
/// page, in the board's order. The same line the by-scene page draws as its
/// group heading, one rank down: number, time-of-day dot, heading, count.
fn run_heading(run: &Run) -> String {
    if !run.scene_starts {
        return String::new();
    }
    let Some(row) = run.rows.first() else {
        return String::new();
    };
    format!(
        "<div class=\"run-head\"><span class=\"no\">{}</span><h3>{}{}</h3>\
         <span class=\"count\">{} shot{}</span></div>\n",
        esc(&row.scene_number),
        tod_dot(&row.scene_heading),
        esc(&row.scene_heading),
        run.rows.len(),
        if run.rows.len() == 1 { "" } else { "s" }
    )
}

/// `#RRGGBB` or `#RGB` as three channels; anything else is no colour.
fn hex_rgb(colour: &str) -> Option<(u8, u8, u8)> {
    let hex = colour.trim().strip_prefix('#')?;
    let channel = |from: usize, width: usize| -> Option<u8> {
        let part = hex.get(from..from + width)?;
        let value = u8::from_str_radix(part, 16).ok()?;
        Some(if width == 1 { value * 17 } else { value })
    };
    match hex.len() {
        6 => Some((channel(0, 2)?, channel(2, 2)?, channel(4, 2)?)),
        3 => Some((channel(0, 1)?, channel(1, 1)?, channel(2, 1)?)),
        _ => None,
    }
}

/// **The shot number is never squeezed out.** It is the one column somebody
/// reads out loud on the day, and at 0.55 against ten other columns he has
/// widened it fell under the width of `134AB` and got cut off — `33A` printed
/// as `33`. A floor rather than a bigger weight, so on an ordinary sheet
/// nothing moves at all.
const NUMBER_FLOOR: f64 = 3.4;

/// Every column's share of the paper, summing to 100.
fn column_shares(columns: &[&str], size: FrameSize, widths: &ColumnWidths) -> Vec<f64> {
    // **Auto's shares are the widths.** Only when they name every column
    // printed — a column added since they were worked out falls back to the
    // page's own weights rather than to nothing.
    if !widths.shares.is_empty() {
        let found: Vec<Option<f64>> = columns
            .iter()
            .map(|c| widths.shares.iter().find(|(f, _)| f == c).map(|(_, v)| *v))
            .collect();
        if found.iter().all(Option::is_some) {
            let total: f64 = found.iter().flatten().sum();
            if total > 0.0 {
                return found.into_iter().flatten().map(|v| v / total * 100.0).collect();
            }
        }
    }
    let weights: Vec<f64> = columns.iter().map(|c| column_weight(c, size, widths)).collect();
    let total: f64 = weights.iter().sum();
    if total <= 0.0 {
        return vec![100.0 / columns.len().max(1) as f64; columns.len()];
    }
    let mut shares: Vec<f64> = weights.iter().map(|w| w / total * 100.0).collect();

    // The floor is paid for by everybody else, in proportion, so the row still
    // adds up to a sheet of paper.
    let Some(at) = columns.iter().position(|c| *c == "number") else { return shares };
    if shares[at] >= NUMBER_FLOOR {
        return shares;
    }
    let owed = NUMBER_FLOOR - shares[at];
    let rest: f64 = shares.iter().enumerate().filter(|(i, _)| *i != at).map(|(_, s)| *s).sum();
    if rest <= owed {
        return shares;
    }
    for (i, share) in shares.iter_mut().enumerate() {
        if i == at {
            *share = NUMBER_FLOOR;
        } else {
            *share -= owed * (*share / rest);
        }
    }
    shares
}

/// **No column is narrower than its longest word.** A pill wraps between
/// words only, so a column too narrow for `Handheld`, or a header too narrow
/// for `EQUIPMENT`, would cut the word in the middle. Pill columns get a floor
/// of their longest word; the free-text columns get one too, so that making
/// room for pills never leaves a description one letter wide. The room comes
/// from whatever is above its floor, in proportion. When the floors together
/// do not fit the page they all shrink together and a word that still does not
/// fit takes a proper hyphen, which is the last resort. A width he set in the
/// export box is his and is not raised.
fn pill_floor(field: &str) -> f64 {
    match field {
        "support" => 11.5,
        "movement" | "tags" => 11.0,
        "lens" | "camera" => 9.5,
        "size" => 9.0,
        "angle" => 8.5,
        "day" => 7.0,
        "description" => 12.0,
        "script" => 10.0,
        "title" | "notes" => 5.0,
        "number" | "image" => 0.0,
        f if f.starts_with("c_") => 9.0,
        _ => 6.0,
    }
}

/// Whether the floors would not fit the page at the normal type size. Kept
/// for the report: nothing shrinks type any more, the floors give way first.
const PILL_ROOM: f64 = 92.0;

fn pill_floors(columns: &[&str], mut shares: Vec<f64>, widths: &ColumnWidths) -> Vec<f64> {
    let mut floors: Vec<f64> = columns
        .iter()
        .zip(&shares)
        .map(|(c, share)| {
            let factor = widths.factor(c);
            // Asked for more than its share, it keeps what it was given;
            // asked for less, it is his call and no floor applies.
            if factor > 1.0 || *c == "image" || *c == "number" { *share } else if factor < 1.0 { 0.0 } else { pill_floor(c) }
        })
        .collect();
    let wanted: f64 = floors.iter().sum();
    if wanted > PILL_ROOM {
        let k = PILL_ROOM / wanted;
        floors.iter_mut().for_each(|f| *f *= k);
    }
    for (share, floor) in shares.iter_mut().zip(&floors) {
        if *share < *floor {
            *share = *floor;
        }
    }
    let excess = shares.iter().sum::<f64>() - 100.0;
    let slack: f64 = shares.iter().zip(&floors).map(|(s, f)| (s - f).max(0.0)).sum();
    if excess > 0.0 && slack > 0.0 {
        let take = excess.min(slack);
        for (share, floor) in shares.iter_mut().zip(&floors) {
            let room = (*share - floor).max(0.0);
            *share -= take * room / slack;
        }
    }
    shares
}

/// **A shoot day that starts a sheet of its own** on the Table and the
/// Storyboard — every day after the first, when the export asks for it.
fn day_page(sheet: &Sheet, index: usize) -> bool {
    sheet.day_pages && index > 0 && sheet.grouped_by == GroupBy::Day
}

fn table_rows(sheet: &Sheet, frames: Frames, size: FrameSize, widths: &ColumnWidths) -> String {
    let columns = table_columns(sheet);
    // Auto's shares already hold every floor, worked out from the words
    // themselves; the fixed floors below are for the weights.
    let shares = column_shares(&columns, size, widths);
    let exact = widths.has_exact(&columns);
    let fitted = exact && widths.fitted;
    let shares = if exact { shares } else { pill_floors(&columns, shares, widths) };
    // **Fitted by Auto, nothing is hyphenated.** Every column already holds
    // its longest word, so a hyphen there would only be WebKit filling a
    // line — `Sin-gle`, `Dri-ving` — which reads as a word cut in half.
    let table_class = if fitted { " class=\"fitted\"" } else { "" };
    let colgroup: String = shares
        .into_iter()
        .map(|share| format!("<col style=\"width:{share:.2}%\">"))
        .collect();
    let head: String = columns
        .iter()
        .map(|c| format!("<th>{}</th>", esc(column_header(sheet, c))))
        .collect();

    // A scene's own export already says which scene it is in the masthead —
    // repeating it here as a section header would say the same thing twice.
    let repeat_scene_header = sheet.single_scene().is_none();

    let by_scene = sheet.grouped_by == GroupBy::Scene;
    let mut out = String::new();
    for (index, group) in sheet.groups.iter().enumerate() {
        let runs = runs(sheet, group);
        // Grouped by scene the one run is the group: its section head sits
        // over the group and the ink runs down the whole of it.
        let own = if by_scene { runs.first() } else { None };
        out.push_str(&own.map(section_head).unwrap_or_default());
        out.push_str(&format!(
            "<section class=\"group{}{}\"{}>\n",
            if day_page(sheet, index) { " fresh-page" } else { "" },
            own.map(section_class).unwrap_or(""),
            own.map(section_ink).unwrap_or_default()
        ));
        if repeat_scene_header {
            out.push_str(&group_heading(sheet, group));
        }
        for run in &runs {
            if !by_scene {
                out.push_str(&section_head(run));
                out.push_str(&format!("<div class=\"run{}\"{}>\n", section_class(run), section_ink(run)));
                out.push_str(&run_heading(run));
            }
            out.push_str(&format!(
                "<table{table_class}><colgroup>{colgroup}</colgroup>\n<thead><tr>{head}</tr></thead>\n<tbody>\n"
            ));
            for row in run.rows {
                let cells: String = columns
                    .iter()
                    .map(|c| {
                        format!(
                            "<td{}>{}</td>",
                            table_cell_class(c),
                            table_cell(sheet, row, c, frames, sheet.project_ratio)
                        )
                    })
                    .collect();
                out.push_str(&format!(
                    "<tr{}>{cells}</tr>\n",
                    if row.struck { " class=\"struck\"" } else { "" }
                ));
            }
            out.push_str("</tbody>\n</table>\n");
            if !by_scene {
                out.push_str("</div>\n");
            }
        }
        out.push_str("</section>\n");
    }
    out
}

/// The dense landscape table, for printing or for a share link. `scale`
/// multiplies the root font size — 1.0 is the normal size, and the export
/// dialog can ask for anything from 0.5 to 2.5.
pub fn table(
    sheet: &Sheet,
    frames: Frames,
    print: Print,
    scale: f64,
    size: FrameSize,
    widths: &ColumnWidths,
) -> String {
    let body = if sheet.is_empty() {
        "<div class=\"wrap\"><p class=\"empty\">Nothing matches these filters.</p></div>".to_string()
    } else {
        format!("<div class=\"wrap\">{}</div>", table_rows(sheet, frames, size, widths))
    };
    // The table draws none of the document's classes, so its own standard is
    // all the stylesheet needs from here.
    page(
        &page_title(sheet, "Shot List"),
        print,
        scale,
        size,
        format!("{}{}{FILL_ROWS}", masthead(sheet), body),
        &Style::standard_style(),
    )
}

// ---- document -----------------------------------------------------------

fn document_body(sheet: &Sheet, frames: Frames) -> String {
    let ratio = sheet.project_ratio.max(0.01);
    let mut out = String::new();
    for (index, group) in sheet.groups.iter().enumerate() {
        // A shoot day gets handed out on its own, so it starts a fresh page.
        // Not when the export put several days in one file on purpose: the
        // Document then runs on, and only the Table and Storyboard break.
        let fresh = index > 0 && sheet.grouped_by == GroupBy::Day && !sheet.day_pages;
        let heading = if sheet.grouped_by == GroupBy::Scene {
            group
                .rows
                .first()
                .map(|row| format!("{}: {}", group.label, row.scene_heading))
                .unwrap_or_else(|| group.label.clone())
        } else {
            group.label.clone()
        };
        let under = if sheet.grouped_by == GroupBy::Scene {
            group
                .rows
                .first()
                .and_then(|row| row.sequence.clone())
                .unwrap_or_default()
        } else {
            String::new()
        };
        let runs = runs(sheet, group);
        // Grouped by scene the one run is the group, and its section's
        // chapter head sits over the group; otherwise each run of scenes
        // in a section opens with one, inside the group, further down.
        let own = if sheet.grouped_by == GroupBy::Scene { runs.first() } else { None };
        out.push_str(&own.map(section_head).unwrap_or_default());
        out.push_str(&format!("<section class=\"group{}\">\n", if fresh { " fresh-page" } else { "" }));
        // A scene's own export already says which scene it is in the
        // masthead — repeating it here would say the same thing twice.
        if sheet.single_scene().is_none() {
            // **The number in its own mono cell, the heading beside it** —
            // the app's scene heading, which reads `33  EXT. COUNTY JAIL -
            // DAY … 1 SHOT`. Grouped by scene the label *is* the number, so
            // it comes out of the heading rather than being repeated in it.
            let (no, rest) = match (sheet.grouped_by, group.rows.first()) {
                // The label reads `Scene 34`; the app's heading is the bare
                // number in its own mono cell, so the number is taken from the
                // row rather than parsed back out of a sentence.
                (GroupBy::Scene, Some(row)) => {
                    (row.scene_number.clone(), row.scene_heading.clone())
                }
                _ => (String::new(), heading.clone()),
            };
            let dot = if sheet.grouped_by == GroupBy::Scene {
                group.rows.first().map(|row| tod_dot(&row.scene_heading)).unwrap_or_default()
            } else {
                String::new()
            };
            out.push_str(&format!(
                "<div class=\"group-head\">{}<h2>{dot}{}</h2>{}\
                 <span class=\"count\">{} shot{}</span></div>\n",
                if no.is_empty() {
                    String::new()
                } else {
                    format!("<span class=\"no\">{}</span>", esc(&no))
                },
                esc(&rest),
                if under.is_empty() {
                    String::new()
                } else {
                    format!("<span class=\"seq\">{}</span>", esc(&under))
                },
                group.count(),
                if group.count() == 1 { "" } else { "s" }
            ));
        }


        // Grouped by scene, the group *is* the scene — repeating the heading
        // underneath its own header says the same thing twice on every page.
        let group_is_the_scene = sheet.grouped_by == GroupBy::Scene;

        for run in &runs {
            if !group_is_the_scene {
                out.push_str(&section_head(run));
            }
            if let (true, Some(row)) = (run.scene_starts, run.rows.first()) {
                let here = run.rows.len();
                out.push_str(&format!(
                    "<div class=\"scene-head\"><span class=\"no\">{}</span>\
                     <h3>{}{}</h3>{}<span class=\"count\">{} shot{}</span></div>\n",
                    esc(&row.scene_number),
                    tod_dot(&row.scene_heading),
                    esc(&row.scene_heading),
                    row.sequence
                        .as_ref()
                        .map(|s| format!("<span class=\"meta\">{}</span>", esc(s)))
                        .unwrap_or_default(),
                    here,
                    if here == 1 { "" } else { "s" }
                ));
            }
        for row in run.rows {

            // **Zipped, not filtered then zipped.** The arrows are a list
            // beside the frames, in the same order; dropping a frame whose
            // bytes are missing without dropping its marks would slide every
            // later picture's arrows onto the wrong photograph.
            let images: Vec<String> = row
                .frames
                .iter()
                .enumerate()
                .filter_map(|(at, id)| {
                    let trim = row.frame_trims.get(at).copied().flatten();
                    frames(*id, trim).map(|frame| (at, frame))
                })
                .map(|(at, frame)| {
                    let marks = row.frame_marks.get(at).cloned().unwrap_or_default();
                    format!(
                        "<span class=\"shotframe\" style=\"padding-top:{:.2}%\">{}</span>",
                        100.0 / ratio,
                        held(&frame, &marks, ratio)
                    )
                })
                .collect();

            // Width is a fraction of the measure, so the page keeps its shape
            // whatever the paper is.
            let width = format!("{:.0}", (row.frame_width * 100.0).round());
            let alongside = row.frame_position.is_alongside();
            let frames_html = if images.is_empty() {
                String::new()
            } else {
                let sizing = if alongside {
                    format!("flex-basis:{width}%;max-width:{width}%")
                } else {
                    format!("width:{width}%")
                };
                format!(
                    "<div class=\"frames{}\" style=\"{sizing}\">{}</div>",
                    if images.len() == 1 { " single" } else { "" },
                    images.join("")
                )
            };

            let technical = row.technical_line_for(&sheet.columns);
            // The number hangs in the margin — it is placed, not laid out, so
            // the words keep a clean left edge whether or not a shot is
            // titled. The app draws the same two things the same way.
            let head = format!(
                "<span class=\"shot-letter\">{}</span>{}",
                esc(&row.number),
                if row.title.is_empty() {
                    String::new()
                } else {
                    format!("<div class=\"shot-title\">{}</div>", esc(&row.title))
                }
            );
            let tech = if technical.is_empty() {
                String::new()
            } else {
                format!("<div class=\"shot-tech\">{}</div>", esc(&technical))
            };
            let desc = if row.description.is_empty() {
                String::new()
            } else {
                format!("<div class=\"shot-desc\">{}</div>", esc(&row.description))
            };
            let notes = if row.notes.is_empty() {
                String::new()
            } else {
                format!("<div class=\"shot-notes\">{}</div>", esc(&row.notes))
            };
            // **The words of the script this shot quotes**, under its own
            // words — only when the Script column is on the sheet, so a
            // film's page is untouched (2026-09-19).
            let quote = if row.script.is_empty() || !sheet.columns.iter().any(|c| c == "script") {
                String::new()
            } else {
                format!("<div class=\"shot-quote\">{}</div>", paragraphs(&row.script))
            };

            // **Title, words, technical line, note** — the order the app's
            // page draws them in, which is also the order Tab walks. It was
            // technical-then-words here until 2026-09-01, so the export and
            // the screen read a shot in two different orders.
            //
            // A shot is never split across a page break — frame on one page and
            // its technical line on the next would be worse than a short page.
            let body = format!("{head}{desc}{quote}{tech}{notes}");
            let inner = if alongside {
                // Which side is a matter of flex direction, so the reading order
                // stays text-first for anything listening rather than looking.
                format!("<div class=\"shot-body\">{body}</div>{frames_html}")
            } else if row.frame_position == FramePosition::Above {
                format!("{frames_html}{body}")
            } else {
                format!("{body}{frames_html}")
            };
            out.push_str(&format!(
                "<article class=\"shot{}{}\" data-shot=\"{}\">{inner}</article>\n",
                if row.struck { " struck" } else { "" },
                match row.frame_position {
                    FramePosition::Below => "",
                    FramePosition::Above => " above",
                    FramePosition::Left => " left",
                    FramePosition::Right => " right",
                },
                row.shot.0,
            ));
        }
        }
        out.push_str("</section>\n");
    }
    out
}

/// The typographic page, with something appended after the list — used by the
/// share exporter to say when the snapshot was taken.
pub fn document_page(
    sheet: &Sheet,
    frames: Frames,
    print: Print,
    footer: &str,
    caption: &str,
    style: &Style,
) -> String {
    let inside = if sheet.is_empty() {
        "<p class=\"empty\">Nothing matches these filters.</p>".to_string()
    } else {
        format!("{}{footer}", document_body(sheet, frames))
    };
    page_with_columns(
        &page_title(sheet, "Shot List"),
        print,
        1.0,
        FrameSize::default(),
        format!(
            "<div class=\"doc-wrap\">{}{inside}</div>",
            doc_masthead(sheet, caption)
        ),
        &sheet.columns,
        style,
    )
}

// ---- storyboard -----------------------------------------------------------

/// Cards in a grid — and a scene change still gets the standard header
/// (his ask, 2026-08-28: exporting several scenes' boards together left
/// nothing saying where one scene's cards ended and the next began).
///
/// **Each run of cards is its own `.board`, with its heads as blocks above
/// it** — since 2026-09-20, when a day's page started cutting a day into
/// scene runs. Where a page is cut is not this file's business: the Mac
/// measures every row, card and head (`Printing.blockBoundsScript`) and
/// cuts between them, carrying a head over with what it heads.
fn storyboard_cards(sheet: &Sheet, frames: Frames, size: FrameSize) -> String {
    let repeat_scene_header = sheet.single_scene().is_none();
    let by_scene = sheet.grouped_by == GroupBy::Scene;
    let mut out = String::new();
    for (index, group) in sheet.groups.iter().enumerate() {
        let fresh = day_page(sheet, index);
        if fresh {
            out.push_str("<section class=\"day-sheet fresh-page\">\n");
        }
        let runs = runs(sheet, group);
        let own = if by_scene { runs.first() } else { None };
        // Grouped by scene the group is the run, and its heads are the
        // section's (if it starts one) and the scene's own.
        let mut group_heads = own.map(section_head).unwrap_or_default();
        if repeat_scene_header {
            group_heads.push_str(&group_heading(sheet, group).replacen(
                "<div class=\"group-head\">",
                &format!(
                    "<div class=\"group-head{}\"{}>",
                    own.map(section_class).unwrap_or(""),
                    own.map(section_ink).unwrap_or_default()
                ),
                1,
            ));
        }
        for (at, run) in runs.iter().enumerate() {
            let mut heads = if at == 0 { std::mem::take(&mut group_heads) } else { String::new() };
            if !by_scene {
                heads.push_str(&section_head(run));
                heads.push_str(&run_heading(run).replacen(
                    "<div class=\"run-head\">",
                    &format!("<div class=\"run-head{}\"{}>", section_class(run), section_ink(run)),
                    1,
                ));
            }
            out.push_str(&heads);
            out.push_str("<div class=\"board\">\n");
            for row in run.rows {
                out.push_str(&card(sheet, frames, run, row, size));
            }
            out.push_str("</div>\n");
        }
        if fresh {
            out.push_str("</section>\n");
        }
    }
    out
}

/// **The insides of one storyboard frame box, or four.** A still is one box
/// with the picture held in it, keeping the part he chose. A clip's strip —
/// four moments the Mac baked two by two into one picture — is four boxes,
/// each showing one quarter of that one picture, so the moments stand side
/// by side in the row the way a storyboard reads. The same cut the table's
/// `FILL_ROWS` makes after layout, made here up front: the geometry is
/// `quarter_geometry`'s, and the strip's corner numbers ride with their
/// quarters. A marked clip never has a strip (`strip_bytes`), so an arrow is
/// never cut in four.
fn frame_boxes(frame: &Frame, marks: &Marks, ratio: f64) -> Vec<String> {
    if frame.moments == 4 {
        let geometry = quarter_geometry(frame, ratio);
        let parts: Vec<f64> = geometry.split(' ').filter_map(|n| n.parse().ok()).collect();
        if let [tall, wide, high] = parts[..] {
            // **The strip's bytes go into the page once**, in the first
            // quarter; the other three are given their picture by
            // `FILL_STRIPS` once the page is drawn. Written four times, a
            // day's page was four times the weight and the export waited
            // on it (Call Her Back: 21 MB became 80). The same bargain the
            // table's `FILL_ROWS` strikes.
            let src = esc(&frame.src);
            return [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
                .iter()
                .enumerate()
                .map(|(at, (x, y))| {
                    let source = if at == 0 { format!(" src=\"{src}\"") } else { String::new() };
                    format!(
                        "<span class=\"card-frame\" style=\"padding-top:{:.2}%\">\
                         <img class=\"held\" style=\"width:{wide:.2}%;left:{:.2}%;top:{:.2}%\"\
                         {source} alt=\"\"></span>",
                        tall * 100.0,
                        -(wide - 100.0) * x + 0.0,
                        -(high - 100.0) * y + 0.0
                    )
                })
                .collect();
        }
    }
    vec![format!(
        "<span class=\"card-frame\" style=\"padding-top:{:.2}%\">{}</span>",
        100.0 / ratio.max(0.01),
        held(frame, marks, ratio)
    )]
}

/// **The words a storyboard card carries under (or beside) its frames**, in
/// the sheet's own column order: the number and title, the description in
/// full, the quoted script in full, then every other column that is on the
/// sheet as a labelled value — the table's header over the cell's words.
/// Nothing is clamped or cut off; that was the whole complaint.
fn card_text(sheet: &Sheet, row: &Row, frames: Frames) -> String {
    let mut out = format!(
        "<div class=\"card-text\"><div class=\"card-head\">\
         <span class=\"card-number\">{}</span><span class=\"card-title\">{}</span></div>",
        esc(&row.number),
        esc(&row.title)
    );
    if !row.description.is_empty() {
        out.push_str(&format!("<div class=\"card-desc\">{}</div>", paragraphs(&row.description)));
    }
    if !row.script.is_empty() && sheet.columns.iter().any(|c| c == "script") {
        out.push_str(&format!("<div class=\"card-quote\">{}</div>", paragraphs(&row.script)));
    }
    let mut fields = String::new();
    for field in &sheet.columns {
        // Already on the card, or the pictures themselves.
        if matches!(field.as_str(), "image" | "title" | "description" | "script") {
            continue;
        }
        let value = table_cell(sheet, row, field, frames, sheet.project_ratio);
        if value.is_empty() {
            continue;
        }
        let wide = if field == "notes" { " wide" } else { "" };
        fields.push_str(&format!(
            "<div class=\"f{wide}\"><span class=\"k\">{}</span><span class=\"v\">{value}</span></div>",
            esc(column_header(sheet, field))
        ));
    }
    if !fields.is_empty() {
        out.push_str(&format!("<div class=\"card-fields\">{fields}</div>"));
    }
    out.push_str("</div>");
    out
}

/// One card: every frame the shot has in a row, at the film's ratio, then
/// the words — beside the row when it is short, under it when it is wide.
///
/// **How wide a frame stands.** The dial says how tall (`frame_height_rem`)
/// and the film's ratio says how wide from that; then the row has to fit
/// the page. One or two frames stand at that size and the words sit beside
/// them if they fit (`.card-text` wants 17rem). Three or more take the whole
/// width, each frame the row's share of it, capped at the dial's size —
/// so a clip's four moments always stand in one row, on any paper.
fn card(sheet: &Sheet, frames: Frames, run: &Run, row: &Row, size: FrameSize) -> String {
    let ratio = sheet.project_ratio.max(0.01);
    // **A baked Print Frame stands alone**, in its own shape: as tall as the
    // dial's frame, and never narrower than one frame of the film.
    if let Some(pf) = row.print_frame.as_ref().filter(|p| p.is_usable()) {
        // **As tall as the dial's frame, never narrower than one frame of the
        // film — and never more than twice as tall as it.** A tall board
        // (two vertical frames stacked, a 9:16 picture) given a film frame's
        // width stood three pages high; capped at twice the dial's height it
        // is a tall card that still fits a sheet.
        let own = size.frame_height_rem() * pf.width / pf.height;
        let wide = own.max(size.frame_width_rem(ratio)).min(2.0 * own);
        return format!(
            "<article class=\"card{}{}\"{}>\
             <div class=\"card-frames\"><span class=\"card-pic\" style=\"width:{wide:.2}rem;max-width:100%\">{}</span></div>\
             {}\
             </article>\n",
            if row.struck { " struck" } else { "" },
            section_class(run),
            section_ink(run),
            print_frame_box("card-frame", pf),
            card_text(sheet, row, frames)
        );
    }
    // The shot's frames in their own order, a clip's strip cut into its four
    // moments. The key frame leads only when it is not among them.
    let mut groups: Vec<Vec<String>> = Vec::new();
    let mut seen_key = false;
    for (at, id) in row.frames.iter().enumerate() {
        let trim = row.frame_trims.get(at).copied().flatten();
        let Some(frame) = frames(*id, trim) else { continue };
        let marks = row.frame_marks.get(at).cloned().unwrap_or_default();
        if Some(*id) == row.key_frame {
            seen_key = true;
        }
        groups.push(frame_boxes(&frame, &marks, ratio));
    }
    if !seen_key {
        if let Some(key) = row.key_frame.and_then(|id| frames(id, row.key_frame_trim)) {
            groups.insert(0, frame_boxes(&key, &row.key_frame_marks, ratio));
        }
    }
    // A shot with nothing on it still gets its frame — an empty box at the
    // film's ratio is what a storyboard has before the drawing goes in.
    if groups.is_empty() {
        groups.push(vec![format!(
            "<span class=\"card-frame\" style=\"padding-top:{:.2}%\"></span>",
            100.0 / ratio
        )]);
    }
    let count: usize = groups.iter().map(Vec::len).sum();
    let wide = size.frame_width_rem(ratio);
    let (row_class, width) = if count >= 3 {
        // **Four in a row, always** — a clip's moments are never split
        // three and one. Past four, the frames go in even rows of up to
        // four (six is two rows of three, eight two of four), each frame
        // its row's share of the width, capped at the dial's size.
        let rows = count.div_ceil(4);
        let per_row = count.div_ceil(rows);
        (
            " wide",
            format!(
                "min(calc((100% - {:.2}rem) / {per_row}), {wide:.2}rem)",
                0.5 * (per_row as f64 - 1.0)
            ),
        )
    } else {
        ("", format!("{wide:.2}rem;max-width:100%"))
    };
    let pictures: String = groups
        .iter()
        .map(|group| {
            let pics: String = group
                .iter()
                .map(|inner| format!("<span class=\"card-pic\" style=\"width:{width}\">{inner}</span>"))
                .collect();
            // A strip's four stand in one wrapper the script can find; it
            // takes no part in the row (`display: contents`).
            if group.len() == 4 {
                format!("<span class=\"card-strip\">{pics}</span>")
            } else {
                pics
            }
        })
        .collect();
    format!(
        "<article class=\"card{}{}\"{}>\
         <div class=\"card-frames{row_class}\">{pictures}</div>\
         {}\
         </article>\n",
        if row.struck { " struck" } else { "" },
        section_class(run),
        section_ink(run),
        card_text(sheet, row, frames)
    )
}

/// The board — every shot as a card, frame first. The same content a scene's
/// own Storyboard tab shows, laid out for the page.
pub fn storyboard(
    sheet: &Sheet,
    frames: Frames,
    print: Print,
    scale: f64,
    size: FrameSize,
) -> String {
    let body = if sheet.is_empty() {
        "<div class=\"wrap\"><p class=\"empty\">Nothing matches these filters.</p></div>".to_string()
    } else {
        format!("<div class=\"wrap\">{}</div>{FILL_STRIPS}", storyboard_cards(sheet, frames, size))
    };
    page(
        &page_title(sheet, "Storyboard"),
        print,
        scale,
        size,
        format!("{}{}", masthead(sheet), body),
        &Style::standard_style(),
    )
}

/// The typographic page — each shot a paragraph with its frames.
pub fn document(
    sheet: &Sheet,
    frames: Frames,
    print: Print,
    scale: f64,
    caption: &str,
    style: &Style,
) -> String {
    let inside = if sheet.is_empty() {
        "<p class=\"empty\">Nothing matches these filters.</p>".to_string()
    } else {
        document_body(sheet, frames)
    };
    // **No frame-size dial here on purpose.** A document page already has one,
    // per shot and his to set: `frame_width`, the fraction of the measure a
    // picture takes. A second dial over the top of it would fight it.
    page(
        &page_title(sheet, "Shot List"),
        print,
        scale,
        FrameSize::default(),
        format!(
            "<div class=\"doc-wrap\">{}{inside}</div>",
            doc_masthead(sheet, caption)
        ),
        style,
    )
}

// ---- the script page -------------------------------------------------------

/// A stretch of a script and the rows that cover it — what one row of the
/// Script page is. `shots` are indices into the sheet's rows, in sheet order.
struct Stretch {
    text: String,
    shots: Vec<usize>,
    /// Where it sits in the script, in UTF-16 units.
    from: usize,
    to: usize,
}

/// **Cut a script wherever a quote begins or ends**, and say for each piece
/// which shots cover the whole of it. Pieces that are only white space are
/// dropped; neighbours covered by the same shots are one piece. Offsets are
/// UTF-16 units, the unit every quote is kept in (`quoting.rs`).
fn stretches(text: &str, quotes: &[(usize, usize, usize)]) -> Vec<Stretch> {
    let units: Vec<u16> = text.encode_utf16().collect();
    let len = units.len();
    let mut cuts: Vec<usize> = vec![0, len];
    for (_, from, to) in quotes {
        cuts.push((*from).min(len));
        cuts.push((*to).min(len));
    }
    cuts.sort_unstable();
    cuts.dedup();
    let mut out: Vec<Stretch> = Vec::new();
    for pair in cuts.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        if b <= a {
            continue;
        }
        let shots: Vec<usize> = quotes
            .iter()
            .filter(|(_, from, to)| *from <= a && *to >= b)
            .map(|(at, _, _)| *at)
            .collect();
        let piece = String::from_utf16_lossy(&units[a..b]);
        match out.last_mut() {
            Some(last) if last.shots == shots => {
                last.text.push_str(&piece);
                last.to = b;
            }
            _ => out.push(Stretch { text: piece, shots, from: a, to: b }),
        }
    }
    // An AV script's marks are not words: a piece that is only a mark (or
    // a mark and a line break) is no stretch at all.
    out.into_iter()
        .filter(|s| !s.text.replace([crate::quoting::AV_CELL, crate::quoting::AV_ROW], "").trim().is_empty())
        .collect()
}

/// **One stretch of an AV script, Video beside Audio for every row it
/// touches** — the portal's `avStretch`. A stretch is cut where quotes begin
/// and end, so it may start partway into a row's Audio; the side it starts
/// on is read from the marks before it.
fn av_stretch(text: &str, from: usize, to: usize) -> String {
    use crate::quoting::{AV_CELL, AV_ROW};
    let units: Vec<u16> = text.encode_utf16().collect();
    let (cell, row) = (AV_CELL as u16, AV_ROW as u16);
    let mut audio = units[..from.min(units.len())]
        .iter()
        .fold(false, |side, u| if *u == row { false } else if *u == cell { true } else { side });
    let mut rows: Vec<(Vec<u16>, Vec<u16>)> = vec![(Vec::new(), Vec::new())];
    for u in &units[from.min(units.len())..to.min(units.len())] {
        let last = rows.last_mut().expect("one row at least");
        if *u == row {
            rows.push((Vec::new(), Vec::new()));
            audio = false;
        } else if *u == cell {
            if audio {
                last.1.push(b'\n' as u16);
            }
            audio = true;
        } else if audio {
            last.1.push(*u);
        } else {
            last.0.push(*u);
        }
    }
    rows.into_iter()
        .map(|(v, a)| (String::from_utf16_lossy(&v), String::from_utf16_lossy(&a)))
        .filter(|(v, a)| !v.trim().is_empty() || !a.trim().is_empty())
        .map(|(v, a)| {
            format!(
                "<div class=\"sc-avrow\"><div class=\"sc-v\">{}</div><div class=\"sc-au\">{}</div></div>",
                paragraphs(&v),
                paragraphs(&a)
            )
        })
        .collect()
}

/// One shot as the Script page draws it: the cue over it when it is the
/// first of its scene in the cell, the number and title, the technical
/// line, the words, the note, then its frames two across.
fn script_shot(sheet: &Sheet, frames: Frames, row: &Row, cue: bool) -> String {
    let ratio = sheet.project_ratio.max(0.01);
    let cue = if cue && !row.scene_heading.is_empty() {
        let slug = if row.scene_slug.is_empty() || row.scene_slug == row.scene_heading {
            String::new()
        } else {
            format!("<span class=\"slug\">{}</span>", esc(&row.scene_slug))
        };
        format!("<div class=\"sc-cue\">{}{slug}</div>", esc(&row.scene_heading))
    } else {
        String::new()
    };
    let technical = row.technical_line_for(&sheet.columns);
    let head = format!(
        "<div class=\"sc-head\"><span class=\"sc-num\">{}</span>{}</div>",
        esc(&row.number),
        if row.title.is_empty() {
            String::new()
        } else {
            format!("<span class=\"sc-title\">{}</span>", esc(&row.title))
        }
    );
    let tech = if technical.is_empty() {
        String::new()
    } else {
        format!("<div class=\"sc-tech\">{}</div>", esc(&technical))
    };
    let desc = if row.description.trim().is_empty() {
        String::new()
    } else {
        format!("<div class=\"sc-desc\">{}</div>", paragraphs(&row.description))
    };
    let notes = if row.notes.trim().is_empty() {
        String::new()
    } else {
        format!("<div class=\"sc-notes\">{}</div>", paragraphs(&row.notes))
    };
    // The frames, the storyboard's way: every one the shot has, a clip's
    // strip as its four moments, the key first only when it is not among
    // them. Nothing drawn for a shot with no pictures — the words stand.
    let mut groups: Vec<Vec<String>> = Vec::new();
    let mut seen_key = false;
    for (at, id) in row.frames.iter().enumerate() {
        let trim = row.frame_trims.get(at).copied().flatten();
        let Some(frame) = frames(*id, trim) else { continue };
        let marks = row.frame_marks.get(at).cloned().unwrap_or_default();
        if Some(*id) == row.key_frame {
            seen_key = true;
        }
        groups.push(frame_boxes(&frame, &marks, ratio));
    }
    if !seen_key {
        if let Some(key) = row.key_frame.and_then(|id| frames(id, row.key_frame_trim)) {
            groups.insert(0, frame_boxes(&key, &row.key_frame_marks, ratio));
        }
    }
    let pictures = if groups.is_empty() {
        String::new()
    } else {
        let inner: String = groups
            .iter()
            .map(|group| {
                let pics: String = group
                    .iter()
                    .map(|b| format!("<span class=\"card-pic\">{b}</span>"))
                    .collect();
                if group.len() == 4 {
                    format!("<span class=\"card-strip\">{pics}</span>")
                } else {
                    pics
                }
            })
            .collect();
        format!("<div class=\"sc-frames\">{inner}</div>")
    };
    // The words in one column and the pictures small beside them — a 9:16
    // frame drawn the column's width was a third of a sheet (Let's Bake ran
    // to 28 pages).
    format!(
        "<div class=\"sc-shot{}{}\">{cue}<div class=\"sc-text\">{head}{tech}{desc}{notes}</div>{pictures}</div>",
        if row.struck { " struck" } else { "" },
        if pictures.is_empty() { "" } else { " pics" }
    )
}

/// **A shot already drawn in full in this chapter**: its number and title,
/// nothing more. A shot covering six lines was its whole card — words,
/// notes and pictures — six times over.
fn script_shot_again(row: &Row) -> String {
    format!(
        "<div class=\"sc-shot again{}\"><div class=\"sc-head\"><span class=\"sc-num\">{}</span>{}</div></div>",
        if row.struck { " struck" } else { "" },
        esc(&row.number),
        if row.title.is_empty() {
            String::new()
        } else {
            format!("<span class=\"sc-title\">{}</span>", esc(&row.title))
        }
    )
}

/// The shots in a cell, cued by scene where the scene changes.
/// `drawn` holds the shots already drawn in full in this chapter; a shot
/// met again is its number and title.
fn script_cell(sheet: &Sheet, frames: Frames, rows: &[&Row], drawn: &mut Vec<*const Row>) -> String {
    let mut out = String::new();
    let mut last_scene: Option<Id> = None;
    for row in rows {
        let at = *row as *const Row;
        if drawn.contains(&at) {
            out.push_str(&script_shot_again(row));
            continue;
        }
        drawn.push(at);
        let cue = last_scene != Some(row.scene);
        last_scene = Some(row.scene);
        out.push_str(&script_shot(sheet, frames, row, cue));
    }
    out
}

/// One script's chapter: its head, then the table of stretches, then the
/// shots of its scenes that quote nothing, under the scene they belong to.
fn script_chapter(sheet: &Sheet, frames: Frames, script: &Script, all: &[&Row]) -> String {
    // One quote for each of a shot's stretches; `at` is the shot.
    let quotes: Vec<(usize, usize, usize)> = all
        .iter()
        .enumerate()
        .filter(|(_, row)| row.quote.map(|q| q.section) == Some(script.section))
        .flat_map(|(at, row)| row.spans.iter().map(move |(from, to)| (at, *from, *to)))
        .collect();
    let untied: Vec<usize> = all
        .iter()
        .enumerate()
        .filter(|(_, row)| row.quote.is_none() && row.section_id == script.section)
        .map(|(at, _)| at)
        .collect();
    let covering: usize = {
        let mut shots: Vec<usize> = quotes.iter().map(|q| q.0).collect();
        shots.dedup();
        shots.len()
    };
    let count = covering + untied.len();

    // A picture's width: a tall frame 7rem high, a wide one 6rem across.
    let ratio = sheet.project_ratio.max(0.01);
    let pic = if ratio < 1.0 { 7.0 * ratio } else { 6.0 };
    let ink = hex_rgb(&script.colour)
        .map(|(r, g, b)| format!(" style=\"--pic:{pic:.2}rem;--sec:{};--sec-rgb:{r},{g},{b}\"", esc(script.colour.trim())))
        .unwrap_or_else(|| format!(" style=\"--pic:{pic:.2}rem\""));
    let mut drawn: Vec<*const Row> = Vec::new();
    let title = if script.title.is_empty() { sheet.project_title.clone() } else { script.title.clone() };
    // **An AV script keeps its two columns** — his ask, 2026-10-05: *"the
    // idea is to see both side by side — shrink the text if you need to."*
    // Video beside Audio, then the shots: the script half wider, its type a
    // size down.
    let av = crate::quoting::is_av(&script.text);
    let script_head = if av {
        "<div class=\"sc-hgrid\"><span>Video</span><span>Audio</span></div>"
    } else {
        "Script"
    };
    let mut out = format!(
        "<section class=\"sc-chapter fresh-page\"{ink}>\
         <div class=\"section-head\"><span class=\"section-bar\"></span>\
         <span class=\"section-title\">{}</span>\
         <span class=\"count\">{count} shot{}</span></div>\n\
         <table class=\"sc{}\"><colgroup><col class=\"sc-a\"><col class=\"sc-b\"></colgroup>\
         <tbody><tr class=\"sc-cols\"><th class=\"sc-a\">{script_head}</th><th class=\"sc-b\">Shots</th></tr>\n",
        esc(&title),
        if count == 1 { "" } else { "s" },
        if av { " sc-isav" } else { "" }
    );
    for stretch in stretches(&script.text, &quotes) {
        let rows: Vec<&Row> = stretch.shots.iter().map(|at| all[*at]).collect();
        let right = if rows.is_empty() {
            "<div class=\"sc-none\">No shot covers these lines</div>".to_string()
        } else {
            script_cell(sheet, frames, &rows, &mut drawn)
        };
        let left = if av {
            av_stretch(&script.text, stretch.from, stretch.to)
        } else {
            paragraphs(&av_words(&stretch.text))
        };
        out.push_str(&format!(
            "<tr><td class=\"sc-script\">{left}</td><td class=\"sc-shots\">{right}</td></tr>\n"
        ));
    }
    // Shots tied to no words, a row per scene, the scene as the left-hand
    // cue — an end card, a wide of the theatre, b-roll.
    let mut at = 0;
    while at < untied.len() {
        let scene = all[untied[at]].scene;
        let mut run: Vec<&Row> = Vec::new();
        while at < untied.len() && all[untied[at]].scene == scene {
            run.push(all[untied[at]]);
            at += 1;
        }
        let first = run[0];
        let slug = if first.scene_slug.is_empty() || first.scene_slug == first.scene_heading {
            String::new()
        } else {
            format!("<span class=\"slug\">{}</span>", esc(&first.scene_slug))
        };
        out.push_str(&format!(
            "<tr><td class=\"sc-script\"><div class=\"sc-where\">{}{slug}</div></td>\
             <td class=\"sc-shots\">{}</td></tr>\n",
            esc(&first.scene_heading),
            script_cell(sheet, frames, &run, &mut drawn)
        ));
    }
    out.push_str("</tbody></table></section>\n");
    out
}

/// **The Script page** — one chapter per script the film holds, each
/// starting a fresh sheet as the director's own document did, and the whole
/// of every script again at the end for whoever is saying the words. A film
/// with no script has no page: it says so and stops.
pub fn script(sheet: &Sheet, frames: Frames, print: Print, scale: f64, style: &Style) -> String {
    let all: Vec<&Row> = sheet.rows().collect();
    // **A script with no live shot on the sheet has no chapter.** A version
    // that was dropped keeps its script on an archived scene; printing its
    // words as a page of "no shot covers these lines" would be the page
    // disagreeing with the film.
    let scripts: Vec<&Script> = sheet
        .scripts
        .iter()
        .filter(|script| {
            all.iter().any(|row| {
                row.quote.map(|q| q.section) == Some(script.section)
                    || (row.quote.is_none() && row.section_id == script.section)
            })
        })
        .collect();
    let inside = if scripts.is_empty() {
        "<p class=\"empty\">No script</p>".to_string()
    } else {
        let mut out = String::new();
        for script in &scripts {
            out.push_str(&script_chapter(sheet, frames, script, &all));
        }
        // The scripts in full, together on one fresh sheet — the way the
        // director's own document ended.
        out.push_str("<section class=\"sc-full fresh-page\">");
        for script in &scripts {
            let ink = hex_rgb(&script.colour)
                .map(|(r, g, b)| format!(" style=\"--sec:{};--sec-rgb:{r},{g},{b}\"", esc(script.colour.trim())))
                .unwrap_or_default();
            let title = if script.title.is_empty() { sheet.project_title.clone() } else { script.title.clone() };
            out.push_str(&format!(
                "<div class=\"sc-chapter\"{ink}>\
                 <div class=\"section-head\"><span class=\"section-bar\"></span>\
                 <span class=\"section-title\">{}</span>\
                 <span class=\"count\">Full script</span></div>\n\
                 <div class=\"sc-body\">{}</div></div>\n",
                esc(&title),
                full_script(&script.text)
            ));
        }
        out.push_str("</section>\n");
        format!("{out}{FILL_STRIPS}")
    };
    page(
        &page_title(sheet, "Script"),
        print,
        scale,
        FrameSize::default(),
        format!(
            "<div class=\"doc-wrap sc-wrap\">{}{inside}</div>",
            doc_masthead_titled(sheet, "Script")
        ),
        style,
    )
}

#[cfg(test)]
mod script_page_tests {
    use super::stretches;

    fn shots(s: &super::Stretch) -> Vec<usize> {
        s.shots.clone()
    }

    #[test]
    fn a_script_is_cut_where_quotes_begin_and_end() {
        // "Hello there.\n\nGeneral Kenobi.\n\nYou are a bold one."
        let text = "Hello there.\n\nGeneral Kenobi.\n\nYou are a bold one.";
        // Shot 0 quotes the first line, shot 1 the second; the third is nobody's.
        let cut = stretches(text, &[(0, 0, 12), (1, 14, 29)]);
        assert_eq!(cut.len(), 3);
        assert_eq!(cut[0].text.trim(), "Hello there.");
        assert_eq!(shots(&cut[0]), vec![0]);
        assert_eq!(cut[1].text.trim(), "General Kenobi.");
        assert_eq!(shots(&cut[1]), vec![1]);
        assert_eq!(cut[2].text.trim(), "You are a bold one.");
        assert!(cut[2].shots.is_empty(), "the uncovered lines are their own piece");
    }

    #[test]
    fn overlapping_quotes_share_a_piece_and_whitespace_gaps_vanish() {
        let text = "One two three four";
        // Shot 0 covers all of it; shot 1 only "two three".
        let cut = stretches(text, &[(0, 0, 18), (1, 4, 13)]);
        assert_eq!(cut.len(), 3);
        assert_eq!(shots(&cut[0]), vec![0]);
        assert_eq!(shots(&cut[1]), vec![0, 1]);
        assert_eq!(shots(&cut[2]), vec![0]);
        // Only white space between two quotes is nobody's piece — so it is no piece.
        let cut = stretches("A\n\nB", &[(0, 0, 1), (1, 3, 4)]);
        assert_eq!(cut.len(), 2);
        assert_eq!(cut[0].text, "A");
        assert_eq!(cut[1].text, "B");
    }

    #[test]
    fn offsets_are_utf16_units_and_are_clamped() {
        // A curly quote is one UTF-16 unit; an emoji is two.
        let text = "It’s 🎬 time";
        let cut = stretches(text, &[(0, 0, 5), (1, 5, 99)]);
        assert_eq!(cut.len(), 2);
        assert_eq!(cut[0].text, "It’s ");
        assert_eq!(cut[1].text, "🎬 time");
    }
}
