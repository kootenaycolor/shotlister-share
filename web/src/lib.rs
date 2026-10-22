//! The engine, in a browser.
//!
//! A film is append-only change logs. Every device replays all of them and
//! writes only its own — so a browser is not a new kind of thing, it is another
//! device. This crate is the shell around the engine that a page talks to, and
//! it does exactly what `storage::open` does on a Mac, minus the disk: take in
//! logs, merge them, and answer questions about what they add up to.
//!
//! **The boundary is pointers, not a binding generator.** Strings go in as
//! (pointer, length); results come back as a pointer to a length-prefixed
//! buffer the caller frees. That is the whole ABI, and it keeps this crate as
//! dependency-free as the engine it wraps.
//!
//! **The clock and the seed must be set first.** A browser has no system clock
//! the engine can reach — see `engine::id`. `set_now` and `set_seed` are the
//! host handing over what it alone knows.

use std::cell::RefCell;

use shotlister_engine::doc::f;
use shotlister_engine::docstyle;
use shotlister_engine::export::html::{self, ColumnWidths, Frame, FrameSize, Print};
use shotlister_engine::format::decode_log;
use shotlister_engine::query::GroupBy;
use shotlister_engine::store::Kind;
use shotlister_engine::json;
use shotlister_engine::media::Arrow;
use shotlister_engine::view::{self, Asked, Standing};
use shotlister_engine::value::Value;
use shotlister_engine::{DeviceId, Doc, Id, Query};

thread_local! {
    static FILM: RefCell<Film> = RefCell::new(Film::new());
}

/// A film, opened. **The whole of this crate's thinking is here**, in plain
/// Rust with no pointers in sight, so that the same code can be run natively —
/// which is how the browser's answer gets checked against the Mac's.
pub struct Film {
    pub doc: Doc,
    /// Lines the logs held that this build could not read. Counted and reported
    /// rather than dropped quietly, exactly as the Mac counts them.
    pub unreadable: usize,
}

impl Default for Film {
    fn default() -> Film {
        Film::new()
    }
}

impl Film {
    pub fn new() -> Film {
        Film {
            // A reader's device name. It matters only when this browser starts
            // writing its own log, which is a later stage; until then every
            // device replays to the same state regardless of what it is called.
            doc: Doc::new(DeviceId(0)),
            unreadable: 0,
        }
    }

    /// Take in one change log, exactly as the Mac takes in one file in
    /// `changes/`. Returns lines it could not read, or -1 for an unreadable log.
    pub fn take(&mut self, text: &str) -> i32 {
        match decode_log(text) {
            Ok(parsed) => {
                let preserved = parsed.preserved.len();
                self.doc.merge(parsed.changes);
                self.unreadable += preserved;
                preserved as i32
            }
            Err(_) => -1,
        }
    }

    /// Every log is in. History belongs to a session.
    pub fn settle(&mut self) {
        self.doc.clear_history();
    }

    /// The store's own fingerprint — every field of every record, sorted. Two
    /// devices that took in the same changes agree on this exactly.
    pub fn fingerprint(&self) -> String {
        self.doc.store().fingerprint()
    }

    /// The film in one line: what it is called and how much of it there is.
    pub fn summary(&self) -> String {
        let d = &self.doc;
        let title = d
            .project_id()
            .map(|id| field(d, id, f::TITLE))
            .unwrap_or_default();
        let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
        let mut out = String::from("{");
        push_pair(&mut out, "title", &title);
        out.push(',');
        push_number(&mut out, "scenes", d.store().count_of_kind(&Kind::Scene));
        out.push(',');
        push_number(&mut out, "shots", sheet.total());
        out.push(',');
        push_number(&mut out, "locations", d.store().count_of_kind(&Kind::Location));
        out.push(',');
        push_number(&mut out, "days", d.store().count_of_kind(&Kind::ShootDay));
        out.push(',');
        push_number(&mut out, "media", d.store().count_of_kind(&Kind::Media));
        out.push(',');
        push_number(&mut out, "changes", d.changes().len());
        out.push(',');
        push_number(&mut out, "unreadable", self.unreadable);
        out.push('}');
        out
    }

    /// **The whole film, described exactly as the Mac app receives it.**
    ///
    /// The same `engine::view` the Mac's own screens are drawn from — the
    /// table, the scene sidebar, the schedule, the locations, the boards. It is
    /// what a browser needs in order to draw those screens rather than a
    /// printed page, and it is shared rather than copied so the two can never
    /// come to describe the same film differently.
    ///
    /// `read_only` is the viewer's, not the film's: a collaborator who may look
    /// and not touch is read-only whatever the file says. Nothing here enforces
    /// that — the server refuses the write — this only stops the screen
    /// offering what will be refused.
    pub fn describe(&self, read_only: bool, asking: &str) -> String {
        view::describe(
            &self.doc,
            &asked_from(asking).looking(),
            &Standing {
                read_only,
                // Nothing of this browser's is unwritten: it has not written.
                unsaved: 0,
                // Two machines wearing one name is something a shell with a
                // disk finds out. A browser has no marks to read.
                device_clash: None,
            },
        )
    }

    /// **A screenplay draft, laid out in pages, with the shots' marks on it**
    /// (Ref 1568, the portal's half). The draft's text comes from the host (the
    /// bucket keeps it beside the PDF); the film says which shots hold which of
    /// its lines (Ref 1553). The same answer the Mac's `scriptpages` gives its
    /// Whole Script window and the phone's Script tab: each line's place in the
    /// draft and the shots covering it, every tie as the stretches it holds in
    /// *this* draft, and the words a draft no longer has under `lost`. Nothing
    /// about where a mark goes is worked out in JavaScript.
    pub fn script_marks(&self, text: &str) -> String {
        use shotlister_engine::jsonw::Json as Writer;
        use shotlister_engine::{lay_out, playties, screenplay};
        let doc = &self.doc;
        let play = screenplay::read_with(text, &doc.detection());
        let laid = lay_out(&play);
        let draft = playties::Draft::of(&play, &laid);
        let ties = doc.play_ties_in(&draft);
        let number_of = |shot: Id| {
            doc.placements_of_shot(shot)
                .first()
                .and_then(|p| doc.display_number(*p))
                .unwrap_or_default()
        };

        let mut j = Writer::new();
        j.obj();
        j.ki("pages", laid.pages_long() as i64)
            .ki("linesPerPage", shotlister_engine::pages::LINES_PER_PAGE as i64)
            .ki("measure", shotlister_engine::pages::MEASURE as i64);
        j.key("pageList").arr();
        for (page_at, page) in laid.pages.iter().enumerate() {
            j.obj().ki("number", page.number as i64);
            j.key("lines").arr();
            for (line_at, pl) in page.lines.iter().enumerate() {
                j.obj()
                    .ki("row", pl.row as i64)
                    .ki("indent", pl.indent as i64)
                    .kv("kind", pl.kind.name())
                    .kv("text", &pl.text)
                    .kb("added", pl.added);
                let range = draft.lines.get(page_at).and_then(|l| l.get(line_at)).copied().flatten();
                if let Some((from, to)) = range {
                    j.ki("from", from as i64).ki("to", to as i64);
                    j.key("shots").arr();
                    for (shot, reading) in &ties {
                        if reading.found.iter().any(|(a, b)| *a < to && from < *b) {
                            j.str(&shot.0.to_string());
                        }
                    }
                    j.end_arr();
                }
                j.end_obj();
            }
            j.end_arr();
            j.end_obj();
        }
        j.end_arr();
        j.key("ties").arr();
        for (shot, reading) in ties.iter().filter(|(_, r)| !r.found.is_empty()) {
            j.obj().kv("shot", &shot.0.to_string()).kv("number", &number_of(*shot));
            j.key("spans").arr();
            for (from, to) in &reading.found {
                j.arr().int(*from as i64).int(*to as i64).end_arr();
            }
            j.end_arr();
            j.end_obj();
        }
        j.end_arr();
        j.key("lost").arr();
        for (shot, reading) in ties.iter().filter(|(_, r)| !r.lost.is_empty()) {
            j.obj().kv("shot", &shot.0.to_string()).kv("number", &number_of(*shot));
            j.key("words").arr();
            for words in &reading.lost {
                j.str(words);
            }
            j.end_arr();
            j.end_obj();
        }
        j.end_arr();
        j.end_obj();
        j.finish()
    }

    /// The shot list as a page, with pictures pointed at wherever the host says
    /// they live. **This is the one place the browser differs from the Mac's
    /// own page**: the Mac bakes the pictures into the file, and here they are
    /// addresses the page fetches — which is what makes a film of two hundred
    /// photographs open at all.
    pub fn page(&self, kind: &str, base: &str) -> String {
        let d = &self.doc;
        let sheet = d.sheet(&Query::grouped_by(GroupBy::Scene));
        // **Width and height are nought, and that is honest.** On a Mac the
        // shell reads a picture's shape off its own bytes before handing it
        // over; here the picture is an *address* the browser will fetch, and
        // nothing in this process has ever seen it. `html.rs` already treats a
        // height of nought as "shape unknown" rather than dividing by it.
        // **The trim is ignored here, and that is the honest answer.** A trim
        // asks for a strip cut out of a clip, which the Mac can do because it
        // holds the bytes. This side hands back an *address* the browser will
        // fetch, so there is one picture per clip and no cutting to be done.
        // **One moment, because a poster is one picture.** The Mac bakes a
        // clip's four moments into one strip and says so; here a clip is its
        // poster, an address the portal serves, and the page must not try to
        // cut it into quarters. `moments` arrived on `Frame` with the strip
        // work (7bc5014) and this line was not updated — the third time this
        // closure has broken the browser build, after `caption` and `style`
        // (see the note below).
        let frames = |media: Id, _trim: html::Trim| -> Option<Frame> {
            picture_at(d, media, base).map(|src| Frame { src, width: 0.0, height: 0.0, moments: 1 })
        };
        match kind {
            // **Default widths, because a live page has no width dial.** The
            // per-column multipliers are an export option the share sheet
            // sends; nobody is setting one here.
            "table" => html::table(&sheet, &frames, Print::Screen, 1.0, FrameSize::default(), &ColumnWidths::default()),
            "storyboard" => html::storyboard(&sheet, &frames, Print::Screen, 1.0, FrameSize::default()),
            // **The film's own type, not a default.** `style` arrived on
            // `html::document` with the doc-style work and this call site was
            // not updated, so `main` stopped building the browser engine
            // altogether — **the second time this exact line has done that**,
            // the first being `caption` with the document-view rewrite
            // (accf697), which the note above this one recorded. Two breaks
            // from the same cause is a pattern: `web/` is the only caller of
            // these outside the engine's own workspace members, so `cargo
            // test` in `engine/` and `ffi/` passes while the browser half does
            // not compile at all.
            //
            // The style is read off the project record the same way `ffi`
            // reads it, so a document page in a browser wears the type he set
            // on the Mac rather than the standard one. A film with no project
            // record — which is only ever a fixture — falls back, as there.
            //
            // `caption` stays empty: a masthead caption belongs to an export
            // somebody asked for, and this is the live page.
            _ => {
                let style = match d.project_id() {
                    Some(project) => docstyle::of(d, project),
                    None => docstyle::Style::standard_style(),
                };
                html::document(&sheet, &frames, Print::Screen, 1.0, "", &style)
            }
        }
    }
}

// ----------------------------------------------------------------- the ABI

/// Room for the caller to write a string into. Paired with `dealloc`.
///
/// **A boxed slice rather than a `Vec`, deliberately.** `Vec::with_capacity`
/// may hand back more room than was asked for, and giving memory back with the
/// wrong capacity is undefined behaviour — the kind that works for months and
/// then corrupts something. A boxed slice's length *is* its capacity, so the
/// number the caller passes to `dealloc` is always the right one.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let buffer = vec![0u8; len].into_boxed_slice();
    Box::into_raw(buffer) as *mut u8
}

/// Give back what `alloc` handed out.
///
/// # Safety
/// `ptr` and `len` must be exactly what a previous `alloc` returned and asked for.
#[no_mangle]
pub unsafe extern "C" fn dealloc(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
    }
}

/// A result the caller reads and then frees: four bytes of length, then UTF-8.
fn give(text: String) -> *mut u8 {
    let bytes = text.into_bytes();
    let mut out = Vec::with_capacity(bytes.len() + 4);
    out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(&bytes);
    // Exact length, for the reason spelled out on `alloc`.
    Box::into_raw(out.into_boxed_slice()) as *mut u8
}

/// Free a buffer `give` produced. It reads its own length back off the front.
///
/// # Safety
/// `ptr` must be a pointer returned by one of the result-returning functions
/// here, freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn free_result(ptr: *mut u8) {
    if ptr.is_null() {
        return;
    }
    let mut length = [0u8; 4];
    std::ptr::copy_nonoverlapping(ptr, length.as_mut_ptr(), 4);
    let len = u32::from_le_bytes(length) as usize + 4;
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
}

/// # Safety
/// `ptr` must point at `len` bytes of UTF-8 the caller still owns.
unsafe fn taken(ptr: *const u8, len: usize) -> String {
    let slice = std::slice::from_raw_parts(ptr, len);
    String::from_utf8_lossy(slice).into_owned()
}

// -------------------------------------------------------- what the host tells us

/// What time it is, in milliseconds since 1970. The browser's `Date.now()`.
#[no_mangle]
pub extern "C" fn set_now(millis: f64) {
    shotlister_engine::id::set_now_millis(millis as u64);
}

/// Seed the id generator. Must be random per session, or two sessions could
/// mint the same id — see `engine::id::set_seed`.
#[no_mangle]
pub extern "C" fn set_seed(seed: f64) {
    shotlister_engine::id::set_seed(seed as u64);
}

// ------------------------------------------------------------- reading a film

/// Start again with nothing. Called before the logs of a film are fed in.
#[no_mangle]
pub extern "C" fn reset() {
    FILM.with(|film| *film.borrow_mut() = Film::new());
}

/// Take in one change log, exactly as the Mac takes in one file in `changes/`.
/// Returns the number of lines it could not read, or -1 if the whole log was
/// unreadable.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn add_log(ptr: *const u8, len: usize) -> i32 {
    let text = taken(ptr, len);
    FILM.with(|film| film.borrow_mut().take(&text))
}

/// Every log is in. History belongs to a session, so what came off the wire is
/// not undoable — the same call the Mac makes at the end of opening a film.
#[no_mangle]
pub extern "C" fn settle() {
    FILM.with(|film| film.borrow_mut().settle());
}

// --------------------------------------------------------------- answering

/// The store's own fingerprint. Two devices that took in the same changes agree
/// on this, which is what makes it the proof that a browser replayed a film the
/// same way a Mac did.
#[no_mangle]
pub extern "C" fn fingerprint() -> *mut u8 {
    FILM.with(|film| give(film.borrow().fingerprint()))
}

/// The film in one line: what it is called and how much of it there is.
#[no_mangle]
pub extern "C" fn summary() -> *mut u8 {
    FILM.with(|film| give(film.borrow().summary()))
}

/// The whole film, described as the Mac app receives it. Pass 1 for a viewer
/// who may only look, and JSON saying what is being looked at.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn view(read_only: i32, ptr: *const u8, len: usize) -> *mut u8 {
    let asking = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(film.borrow().describe(read_only != 0, &asking)))
}

/// Read what the page is asking for.
///
/// **Every field is optional and a missing one means the default**, so a page
/// that knows nothing about filtering can send `{}` — or nothing at all — and
/// get the whole film. The shape is the browser's half of `engine::view::Asked`;
/// the engine turns it into a query, so a search here means exactly what a
/// search means on the Mac.
fn asked_from(text: &str) -> Asked {
    let mut asked = Asked::default();
    let parsed = match json::parse(text) {
        Some(parsed) => parsed,
        None => return asked,
    };
    asked.search = parsed.str_field("search");
    // **`groupBy: "day"` is the shooting order** — the same day groups the
    // Mac's Table draws, each day's placements in the order the Schedule
    // arranged them. His ask, 2026-09-20 (Ref 1136). Anything else is
    // script order, as always.
    if parsed.get("groupBy").and_then(|v| v.as_str()) == Some("day") {
        asked.group_by = GroupBy::Day;
    }
    asked.hide_struck = parsed.get("hideStruck").and_then(|v| v.as_bool()).unwrap_or(false);
    if let Some(column) = parsed.get("sortColumn").and_then(|v| v.as_str()) {
        if !column.is_empty() {
            let down = parsed.get("sortDescending").and_then(|v| v.as_bool()).unwrap_or(false);
            asked.sort = Some((column.to_string(), down));
        }
    }
    if let Some(list) = parsed.get("facets").and_then(|v| v.as_array()) {
        for facet in list {
            let field = facet.str_field("field");
            let value = facet.str_field("value");
            if !field.is_empty() {
                asked.facets.push((field, value));
            }
        }
    }
    asked
}

/// **A screenplay draft with the shots' marks on its lines** (Ref 1568): the
/// draft's text in, the pages and each line's shots out. See `Film::script_marks`.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn script_marks(ptr: *const u8, len: usize) -> *mut u8 {
    let text = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(film.borrow().script_marks(&text)))
}

/// The shot list as a page, with pictures pointed at wherever the host says
/// they live. **This is the one place the browser differs from the Mac's own
/// page**: the Mac bakes the pictures into the file, and here they are
/// addresses the page fetches — which is what makes a film of 200 photographs
/// open at all.
///
/// # Safety
/// Both pointer/length pairs must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn page(
    kind_ptr: *const u8,
    kind_len: usize,
    base_ptr: *const u8,
    base_len: usize,
) -> *mut u8 {
    let kind = taken(kind_ptr, kind_len);
    let base = taken(base_ptr, base_len);
    FILM.with(|film| give(film.borrow().page(&kind, &base)))
}

/// **The storyboard arrows drawn on one picture, as an SVG.**
///
/// The browser never works out where an arrow goes. `Arrow::outline` is the
/// engine's own arithmetic — the same shape SwiftUI strokes on the Mac and the
/// same polygons the exported page prints — and this hands it over as a
/// finished picture the page can lay over a photograph.
///
/// `w` and `h` are the **photograph's** own pixels, not the box it is drawn in:
/// an arrow is stored as a fraction of the picture, so its shape belongs to the
/// picture's shape and travels with it through any crop. The SVG carries those
/// same numbers as its size, which is what lets a page place it with exactly
/// the rules it places the photograph with — `object-fit: cover` and the crop's
/// own `object-position`, and nothing else to keep in step.
///
/// A photograph nobody has drawn on comes back as an empty string, which is
/// every photograph until somebody does.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn arrows(ptr: *const u8, len: usize, w: f64, h: f64) -> *mut u8 {
    let line = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    give(arrow_picture(&line, w, h))
}

/// **A scene's diagram, as a picture the portal can show and tap.**
///
/// The same shapes the Mac paints (`diagram::render`), written by
/// `diagram::svg` at `width` pixels with every shape carrying the element it
/// belongs to, so a tapped camera can say which shot it is. The palette is
/// left to the page's CSS (`--dia-*`), which is how the portal's dark reaches
/// it. Beside the picture, the cameras — their names, colours and shots — so
/// the page can list them without reading the SVG.
///
/// A scene with nothing on its plan answers `{}`.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn diagram(ptr: *const u8, len: usize, width: f64, height: f64, beat: f64) -> *mut u8 {
    let scene = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(diagram_picture(&film.borrow().doc, &scene, width, height, beat)))
}

/// `height` is the tallest the picture may be; a phone asks for a tall box, a
/// desk a wide one, and the plan is fitted inside whichever.
pub fn diagram_picture(doc: &Doc, scene: &str, width: f64, height: f64, beat: f64) -> String {
    use shotlister_engine::diagram::{render, svg, Kind as DiagramKind};
    use shotlister_engine::jsonw::Json as Writer;
    let Some(id) = scene.trim().parse::<u128>().ok().map(Id) else { return "{}".into() };
    let plan = doc.diagram(id);
    if plan.els.is_empty() {
        return "{}".into();
    }
    let ctx = doc.diagram_context(id);
    let beat = if beat.is_finite() && beat >= 1.0 { beat as u32 } else { 1 };
    // As big as the page's box allows: the width asked for, and no taller
    // than a screen's worth (sixteen by ten), so a tall plan is not a
    // scroll.
    let width = if width.is_finite() && width >= 200.0 { width.min(4000.0) } else { 1000.0 };
    let tallest = if height.is_finite() && height >= 200.0 { height } else { width * 0.62 };
    // Pictures under the plan are the film's own media, fetched from beside
    // the page like every other picture it shows.
    let frame = svg::Frame { width, max_scale: 400.0, max_height: Some(tallest), media: "media/{hash}".into(), art: "/fso/{id}.png".into(), ..Default::default() };
    let picture = svg::svg(&plan, &ctx, &render::Options { beat, tween: 0.0, sel: Vec::new(), paper: false, scale: 0.0, typing: String::new(), page: false }, &frame, &format!("d{}", id.0 % 100000));
    let mut j = Writer::new();
    j.obj().kv("svg", &picture).ki("lastBeat", plan.last_beat() as i64);
    j.key("cams").arr();
    for e in plan.els.iter().filter(|e| e.kind == DiagramKind::Camera) {
        j.obj()
            .kv("id", &e.id)
            .kv("name", &render::camera_name(e, &ctx))
            .kv("color", &e.color)
            .kv("shot", &e.shot)
            .kn("focal", render::camera_focal(e, &ctx))
            .end_obj();
    }
    j.end_arr().end_obj();
    j.finish()
}

/// **A scene's plan, the way the Diagrams page is looking at it** — any part
/// of it, at any zoom, at any moment between two beats.
///
/// The page asks in JSON and every field is optional:
///
/// ```text
/// { "scene": "…", "width": 1200, "height": 800,
///   "beat": 2, "tween": 0.4,            // playback: part way to the next beat
///   "area": [x1, y1, x2, y2],           // metres, as shown (north up); none = fit
///   "sel": ["el id"],                   // drawn picked, as the Mac draws it
///   "off": ["cones", "beams", "levels", "grid", "sun", "dims"] }
/// ```
///
/// `off` is the viewer's own Show switches — a copy of the plan is drawn with
/// them turned off, and the film is never touched. **Everything the page
/// lists beside the plan comes from here too** — every piece with its name
/// and kind (Layers), the cameras and the shots they stand for — so the page
/// never reads the SVG to learn what is on the plan, and a later editing page
/// can pick by the same ids the engine edits by.
///
/// A scene with nothing on its plan answers `{}`.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan(ptr: *const u8, len: usize) -> *mut u8 {
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(plan_view(&film.borrow().doc, &ask)))
}

pub fn plan_view(doc: &Doc, ask: &str) -> String {
    use shotlister_engine::diagram::{render, svg, Aabb, Kind as DiagramKind};
    use shotlister_engine::jsonw::Json as Writer;
    let Some(asked) = json::parse(ask) else { return "{}".into() };
    let num = |k: &str| asked.get(k).and_then(|v| v.as_f64()).filter(|n| n.is_finite());
    let Some(id) = asked.str_field("scene").trim().parse::<u128>().ok().map(Id) else { return "{}".into() };
    let mut plan = doc.diagram(id);
    // **A drag, shown before it is let go** — the Mac's `diagrampreview`: the
    // edit made on a copy and drawn, nothing kept.
    // One edit, or several in order (a room's corner moves two walls).
    if let Some(op) = asked.get("preview") {
        let ops: Vec<&json::Json> = match op.as_array() {
            Some(list) => list.iter().collect(),
            None => vec![op],
        };
        for op in ops {
            if shotlister_engine::diagram::apply(&mut plan, op).is_err() {
                return "{}".into();
            }
        }
    }
    if plan.els.is_empty() && asked.get("empty").and_then(|v| v.as_bool()) != Some(true) {
        return "{}".into();
    }
    let ctx = doc.diagram_context(id);
    let off: Vec<String> = asked
        .get("off")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let is_off = |k: &str| off.iter().any(|o| o == k);
    // The viewer's switches, on a copy. Only ever turned off: a thing the
    // film has switched off stays off, as it does on paper.
    let kept_step = plan.settings.step;
    let s = &mut plan.settings;
    if is_off("cones") { s.cones = false; }
    if is_off("beams") { s.beams = false; }
    if is_off("levels") { s.levels = false; }
    if is_off("grid") { s.grid = false; }
    if is_off("sun") { s.sun = false; s.sun_rays = false; }
    if is_off("dims") { s.dims = false; }
    // The grid drawn is the step the page snaps to, which follows its zoom
    // (the Mac's `snapStep`) — drawn only; the plan keeps its own.
    if let Some(g) = num("grid_step").filter(|g| *g > 0.01) { s.step = g; }
    let last = plan.last_beat().max(1);
    let beat = num("beat").map(|b| (b.max(1.0) as u32).min(last)).unwrap_or(1);
    let tween = num("tween").unwrap_or(0.0).clamp(0.0, 1.0);
    let sel: Vec<String> = asked
        .get("sel")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let width = num("width").filter(|w| *w >= 100.0).unwrap_or(1000.0).min(6000.0);
    let height = num("height").filter(|h| *h >= 100.0).unwrap_or(width * 0.62).min(6000.0);
    // **The plan as shown**, north up — what "fit" fits and what an area is
    // measured in.
    let extent = render::extent(&plan, &ctx).unwrap_or(Aabb { x1: 0.0, y1: 0.0, x2: 6.0, y2: 4.0 });
    // An area comes back exactly as asked: `svg` pads whatever it is given
    // by 0.6 m for words hanging off the edge, so the pad is taken off here
    // first, and there is no margin — the page's box is the plan's edge.
    const PAD: f64 = 0.6;
    let area = asked.get("area").and_then(|v| v.as_array()).and_then(|a| {
        let n: Vec<f64> = a.iter().filter_map(|v| v.as_f64()).filter(|n| n.is_finite()).collect();
        (n.len() == 4 && n[2] - n[0] > 2.0 * PAD + 0.01 && n[3] - n[1] > 2.0 * PAD + 0.01)
            .then(|| Aabb { x1: n[0] + PAD, y1: n[1] + PAD, x2: n[2] - PAD, y2: n[3] - PAD })
    });
    // On paper (Print, Save Picture) the plan carries its scale; on screen
    // the page draws its own, which follows the zoom.
    let paper_bar = area.is_none() && asked.get("scale_bar").and_then(|v| v.as_bool()) == Some(true);
    // **On the page** (the Mac's sheet on screen): lettered at the sheet's
    // scale (`page_scale`, points to the metre, Ref 1511), no paper of its
    // own, the dots inside the sheet's window (`window`, as shown).
    let page_scale = num("page_scale").filter(|k| *k > 0.0);
    let window = asked.get("window").and_then(|v| v.as_array()).and_then(|a| {
        let n: Vec<f64> = a.iter().filter_map(|v| v.as_f64()).filter(|n| n.is_finite()).collect();
        (n.len() == 4).then(|| Aabb { x1: n[0], y1: n[1], x2: n[2], y2: n[3] })
    });
    let frame = svg::Frame {
        width,
        margin: if area.is_some() { 0.0 } else { 28.0 },
        max_scale: 4000.0,
        max_height: Some(height),
        area,
        scale_bar: paper_bar,
        media: "media/{hash}".into(),
        // Beside the page, like the film's own pictures, so the film's own
        // door decides who may have them (Ref 1216).
        art: "fso/{id}.png".into(),
        window: if page_scale.is_some() { window } else { None },
        ..Default::default()
    };
    let opt = render::Options { beat, tween, sel, paper: false, scale: page_scale.unwrap_or(0.0), typing: String::new(), page: page_scale.is_some() };
    let picture = svg::svg(&plan, &ctx, &opt, &frame, &format!("p{}", id.0 % 100000));
    // The settings said back are the plan's own: its step, not the one drawn.
    plan.settings.step = kept_step;
    let mut j = Writer::new();
    j.obj()
        .kv("svg", &picture)
        .kv("hex", &id.to_hex())
        .ki("lastBeat", last as i64)
        .kn("turn", render::view_turn(&plan))
        .kv("units", &plan.settings.units)
        .kb("roomFrom", !plan.room_from.is_empty());
    j.key("settings").raw(&shotlister_engine::diagram::portal::settings_full(&plan.settings).encode());
    j.key("extent").arr();
    for n in [extent.x1, extent.y1, extent.x2, extent.y2] {
        j.num(n);
    }
    j.end_arr();
    j.key("cams").arr();
    for e in plan.els.iter().filter(|e| e.kind == DiagramKind::Camera && !e.hidden) {
        // What the cone is worked out from (`render::camera_optics`), so the
        // Details panel says the sensor, view and squeeze in use.
        let o = render::camera_optics(e, &ctx);
        j.obj()
            .kv("id", &e.id)
            .kv("name", &render::camera_name(e, &ctx))
            .kv("color", &e.color)
            .kv("shot", &e.shot)
            .kn("focal", o.focal)
            .kn("aov", (o.aov * 10.0).round() / 10.0)
            .kv("unit", &o.unit)
            .kv("unit_label", &o.unit_label)
            .kv("lens", &o.lens)
            .kv("gate", &o.gate.id)
            .kv("gate_name", if o.sensor_set { o.gate.name.as_str() } else { "Super 35" })
            .kn("squeeze", o.squeeze);
        if let Some((lo, hi)) = o.zoom {
            j.key("zoom").arr();
            j.num(lo);
            j.num(hi);
            j.end_arr();
        }
        j.end_obj();
    }
    j.end_arr();
    // The film's cameras, each with the sensor he typed for it. Not `units`:
    // that is the plan's feet or metres, said above, and a second `units`
    // took its place in the page's reading (metric plans read in feet).
    j.key("filmCams").arr();
    for (id, label, gate) in &ctx.units {
        j.obj().kv("id", id).kv("label", label);
        if let Some(g) = gate {
            j.kv("sensor", &format!("{} · {}", g.name, if g.h > 0.0 { format!("{:.2} × {:.2} mm", g.w, g.h) } else { format!("{:.2} mm", g.w) }));
        }
        j.end_obj();
    }
    j.end_arr();
    // The film's Lens list, for a camera with no shot to pick from.
    j.key("lenses").arr();
    for v in doc.vocabulary("lens") {
        j.str(&v);
    }
    j.end_arr();
    // The film's Size and Movement lists, for a camera's shot (Edit, his ask
    // of 2026-10-02); written through `camera_shot`.
    // And the rest the Mac's Details offers for a camera's shot: Shot Angle
    // and Equipment, and every list column of the film's own (its Cast).
    for (key, field) in [("sizes", "size"), ("movements", "movement"), ("angles", "angle"), ("supports", "support")] {
        j.key(key).arr();
        for v in doc.vocabulary(field) {
            j.str(&v);
        }
        j.end_arr();
    }
    j.key("lists").obj();
    for c in doc.custom_columns() {
        if c.kind == "single" || c.kind == "multi" {
            j.key(&c.field).obj().kv("label", &c.label).kv("kind", &c.kind);
            j.key("terms").arr();
            for v in doc.vocabulary(&c.field) {
                j.str(&v);
            }
            j.end_arr().end_obj();
        }
    }
    j.end_obj();
    // Top of the stack first, the way Layers lists them — every field of
    // every piece (the Details panel edits them), its name and Show switch,
    // and where it stands at the beat being looked at (`at`: x, y, turn).
    // **The lighting plot's legend** (2026-10-03): each mark in use, what it
    // stands for and how many; each colour in use and what it means.
    use shotlister_engine::diagram::plot;
    j.key("legend").arr();
    for x in plot::legend(&plan) {
        j.obj().kv("key", &x.key).kv("name", &x.name).kv("mark", &x.look.mark.as_str()).kv("ink", x.look.ink)
            .kb("solid", x.look.solid).kn("count", x.count as f64).kb("named", x.named);
        // Its lamps (Back to Paper, Batch 2): a legend line picks every one.
        j.key("ids").arr();
        for id in &x.ids {
            j.str(id);
        }
        j.end_arr().end_obj();
    }
    j.end_arr();
    j.key("legendColours").arr();
    for (role, name, named) in plot::colour_rows(&plan) {
        j.obj().kv("role", &role).kv("name", &name).kb("named", named).end_obj();
    }
    j.end_arr();
    // **Where the sun is**, or why it cannot be said, and the day's
    // sunrise, noon, sunset and golden hours — the Sun and North panel's
    // quick picks (the Mac's `wire::payload`).
    if plan.settings.sun {
        let rr = |v: f64| (v * 100.0).round() / 100.0;
        j.key("sun").obj();
        match render::sun_now(&plan, &ctx) {
            Ok((sun, minutes)) => {
                j.kn("azimuth", rr(sun.azimuth)).kn("altitude", rr(sun.altitude)).kn("minutes", minutes);
            }
            Err(why) => {
                j.kv("why", why);
            }
        }
        if let Some(day) = render::sun_day(&plan, &ctx) {
            j.kn("noon", day.noon.round());
            for (key, at) in [("rise", day.rise), ("set", day.set), ("goldenMorning", day.golden_morning), ("goldenEvening", day.golden_evening)] {
                if let Some(m) = at {
                    j.kn(key, m.round());
                }
            }
        }
        j.end_obj();
    }
    j.kv("sceneDate", &ctx.date);
    let looks = plot::looks(&plan);
    let named = plot::legend(&plan);
    j.key("els").arr();
    for e in plan.els.iter().rev() {
        let mut full = e.to_json_full();
        // A lamp is called by its Name, else its Note, else Lamp — never by
        // its Note as though that were its name when it has one.
        let mut lamp_title: Option<String> = None;
        if let json::Json::Object(pairs) = &mut full {
            if let Some((_, l)) = looks.iter().find(|(id, _)| *id == e.id) {
                let key = plot::look_key(l);
                // **Name and Note**: its Name is its own (2026-10-05), else
                // its unit's; its legend line; the two lines its label writes.
                let name = plot::lamp_name(e);
                let line = named.iter().find(|x| x.ids.contains(&e.id)).map(|x| x.key.clone()).unwrap_or_else(|| key.clone());
                let (first, under) = render::lamp_lines(e, &name, plan.settings.counts);
                pairs.retain(|(k, _)| k != "lamp_name");
                pairs.push(("look".into(), json::Json::text(&key)));
                pairs.push(("legend_key".into(), json::Json::text(&line)));
                pairs.push(("lamp_name".into(), json::Json::text(&name)));
                pairs.push(("label_lines".into(), json::Json::Array(vec![json::Json::text(&first), json::Json::text(&under)])));
                lamp_title = Some(if !name.trim().is_empty() { name.trim().to_string() } else if !e.label.trim().is_empty() { e.label.trim().to_string() } else { "Lamp".into() });
            }
            // A frame's two lines (2026-10-05): its size and cloth, its Note.
            if shotlister_engine::diagram::frame::is_frame(e) {
                let (first, under) = render::frame_lines(e, plan.settings.counts);
                pairs.push(("label_lines".into(), json::Json::Array(vec![json::Json::text(&first), json::Json::text(&under)])));
            }
            if let Some(words) = render::shared_label_words(&plan, e) {
                pairs.push(("shown".into(), json::Json::text(&words)));
            }
        }
        let (ax, ay, arot) = render::placed(e, &opt);
        if let json::Json::Object(pairs) = &mut full {
            pairs.push(("show".into(), json::Json::text(plan_show(e))));
            // Set or Plot (Ref 1498): the layer the editor draws and picks it in.
            pairs.push(("layer".into(), json::Json::text(shotlister_engine::diagram::layer(e))));
            pairs.push(("name".into(), json::Json::text(&lamp_title.clone().unwrap_or_else(|| plan_name(e, &ctx, &plan.settings.units)))));
            pairs.push(("groupName".into(), json::Json::text(&e.group_name)));
            pairs.push(("at".into(), json::Json::Array(vec![json::Json::Number(ax), json::Json::Number(ay), json::Json::Number(arot)])));
            pairs.push(("emits".into(), json::Json::Bool(e.kind == DiagramKind::Light && shotlister_engine::diagram::symbols::emits(&e.sym))));
            // **A lamp drawn as a mark is picked and sized by its mark**
            // (`lampscale::hugs`, 2026-10-17): how big it is drawn, so the
            // page's outline and corners go round what he sees.
            if shotlister_engine::diagram::lampscale::hugs(e) {
                if let Some((w, h)) = render::drawn_size(e, &plan, &opt) {
                    let n = |v: f64| json::Json::Number((v * 1000.0).round() / 1000.0);
                    pairs.push(("drawn".into(), json::Json::Array(vec![n(w), n(h)])));
                    pairs.push(("hug".into(), json::Json::Bool(true)));
                }
            }
        }
        j.raw(&full.encode());
    }
    j.end_arr().end_obj();
    j.finish()
}

/// **The sheet** (Back to Paper, Batch 2, his call C) — the page a plan
/// prints on, built once in the engine (`diagram::sheet`), so the portal's
/// Print and Save Picture are the Mac's Export page and Claude's paper
/// picture, line for line; and the legend and notes a viewer reads beside
/// the plan are the sheet's own lines.
///
/// ```text
/// { "scene": "…", "svg": true, "width": 1584, "beat": 1, "printed": "Oct 4, 2026" }
/// ```
///
/// Answers `{sheet, svg?}`: the sheet as `sheet::json` lays it out — the
/// paper, its window, its lines (`items`: head, legend, frames, notes,
/// shot, each with the lamps it stands for) and the gear list — and, when
/// asked, the whole page as a picture (`width` pixels across; nought, a
/// point a pixel). A plan with nothing on it answers `{}`.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan_sheet(ptr: *const u8, len: usize) -> *mut u8 {
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(plan_sheet_view(&film.borrow().doc, &ask)))
}

pub fn plan_sheet_view(doc: &Doc, ask: &str) -> String {
    use shotlister_engine::diagram::{sheet, svg};
    use shotlister_engine::jsonw::Json as Writer;
    let Some(asked) = json::parse(ask) else { return "{}".into() };
    let Some(id) = asked.str_field("scene").trim().parse::<u128>().ok().map(Id) else { return "{}".into() };
    if doc.diagram(id).els.is_empty() {
        return "{}".into();
    }
    let num = |k: &str| asked.get(k).and_then(|v| v.as_f64()).filter(|n| n.is_finite());
    let yes = |k: &str| asked.get(k).and_then(|v| v.as_bool()) == Some(true);
    let a = sheet::Ask {
        beat: num("beat").map(|b| b.max(1.0) as u32).unwrap_or(1),
        printed: asked.str_field("printed").trim().to_string(),
        screen: yes("screen"),
        tz: num("tz"),
        ..Default::default()
    };
    let (laid, plan, ctx) = sheet::of(doc, id, &a);
    let mut j = Writer::new();
    j.obj();
    if yes("furniture") {
        let frame = svg::Frame { media: "media/{hash}".into(), art: "fso/{id}.png".into(), ..Default::default() };
        j.kv("furniture", &sheet::furniture_svg(&laid, &frame, &format!("f{}", id.0 % 100000)));
    }
    if yes("svg") {
        // Paper: no fades (a PDF maker prints them solid), no grid, the
        // sheet's own bar or none; pictures by name, fetched beside the page.
        let frame = svg::Frame { fades: false, grid: false, scale_bar: false, media: "media/{hash}".into(), art: "fso/{id}.png".into(), ..Default::default() };
        let width = num("width").filter(|w| *w >= 100.0).unwrap_or(0.0).min(6000.0);
        j.kv("svg", &sheet::svg_of(&plan, &ctx, &laid, &a, width, false, &frame, &format!("s{}", id.0 % 100000)));
    }
    j.key("sheet").raw(&sheet::json(&laid));
    j.end_obj();
    j.finish()
}

/// **The edits that take `after` back to `before`** — the portal's undo, now
/// the engine's own (`diagram::portal::undo_ops`), so the server can say how
/// to take back a link visitor's edit the same way.
pub fn plan_undo(before: &shotlister_engine::diagram::Diagram, after: &shotlister_engine::diagram::Diagram) -> Vec<json::Json> {
    shotlister_engine::diagram::portal::undo_ops(before, after)
}

/// **Make an edit, here** — the Mac's `diagramedit`, on this browser's own
/// copy of the film, so the page answers at once; the same edit goes to the
/// server, which keeps it as a change log in the editor's name, and the next
/// read replaces this copy with the film as kept. Answers the ids made and
/// the edits that would take it back (`plan_undo`).
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan_edit(ptr: *const u8, len: usize) -> *mut u8 {
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(plan_edit_in(&mut film.borrow_mut().doc, &ask)))
}


/// **The edits that are not the plan's own** — the Mac's other diagram
/// commands, as edits the portal can send like any other: a plan copied from
/// another scene or sent to others, a room laid from a location's scan, a setting on every
/// scene, a favorite slot kept. `None` for an ordinary plan edit. The same
/// function is in `mcpweb` (`special_edit`) — the server makes them exactly as
/// the page did.
fn special_edit(doc: &mut Doc, scene: Id, op: &json::Json) -> Option<Result<Vec<String>, String>> {
    use shotlister_engine::diagram::El;
    match op.get("op").and_then(|o| o.as_str()).unwrap_or("") {
        // Another scene's plan, or the pieces `ids` of it, onto this one —
        // replacing what is here, or `mode: "add"` on top of it.
        "copy_from" | "send" => {
            use shotlister_engine::diagram::copy::Mode;
            let Some(mode) = Mode::parse(&op.str_field("mode")) else {
                return Some(Err("mode is replace or add".into()));
            };
            let list = |k: &str| -> Vec<String> {
                op.get(k).and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect()).unwrap_or_default()
            };
            let ids = list("ids");
            let scene_of = |t: &str| t.trim().parse::<u128>().ok().map(Id);
            // `send`: this plan, or the pieces `ids`, onto the scenes `to`.
            let (from, to) = if op.get("op").and_then(|o| o.as_str()) == Some("send") {
                (scene, list("to").iter().filter_map(|t| scene_of(t)).collect::<Vec<Id>>())
            } else {
                (scene_of(&op.str_field("from"))?, vec![scene])
            };
            if doc.get(from).is_none() || to.iter().any(|t| doc.get(*t).is_none()) {
                return Some(Err("that scene is gone".into()));
            }
            Some(Ok(doc.diagram_copy(from, &ids, &to, mode)))
        }
        // **Loose plans** (`diagram::plans`), from the portal: `plan_new`
        // makes one under the id the page chose (so the page and the server
        // make the same one), starting as a copy of `from` when given;
        // `plan_rename` and `plan_delete` act on the plan `scene` names.
        "plan_new" => {
            let id = op.str_field("id").trim().parse::<u128>().ok().map(Id);
            let from = op.str_field("from").trim().parse::<u128>().ok().map(Id);
            let made = doc.add_plan_with(id, &op.str_field("name"), from);
            Some(Ok(vec![made.0.to_string()]))
        }
        "plan_rename" => {
            if !doc.is_plan(scene) {
                return Some(Err("that is not a plan".into()));
            }
            doc.rename_plan(scene, &op.str_field("name"));
            Some(Ok(Vec::new()))
        }
        "plan_delete" => {
            if !doc.is_plan(scene) {
                return Some(Err("that plan is gone".into()));
            }
            doc.delete_plan(scene);
            Some(Ok(Vec::new()))
        }
        "room" => {
            let Some(plan) = shotlister_engine::room::read(&op.str_field("scan")) else {
                return Some(Err("there is no room in that scan".into()));
            };
            Some(Ok(doc.diagram_import_room(scene, &plan, &op.str_field("location"))))
        }
        // **Add Shot** (the Mac's Shots tab): a new shot at the end of the
        // scene, not yet on the plan — its camera is placed later, or never.
        "add_shot" => {
            if doc.get(scene).map(|r| r.kind == shotlister_engine::store::Kind::Scene) != Some(true) {
                return Some(Err("a loose plan has no scene to add a shot to".into()));
            }
            let (shot, _) = doc.add_shot_to_scene(scene);
            Some(Ok(vec![shot.0.to_string()]))
        }
        "everywhere" => {
            let value = op.get("value")?.clone();
            doc.diagram_setting_everywhere(&op.str_field("key"), value);
            Some(Ok(Vec::new()))
        }
        "picture" => {
            // A picture chosen from the computer: already kept among the
            // film's pictures by its hash (`PUT api/picture`); here it gets
            // its record and is laid on the plan — `diagram_add_image`, the
            // Mac's own step.
            let hash = shotlister_engine::Hash256::from_hex(&op.str_field("hash"))?;
            let n = |k: &str| op.get(k).and_then(|v| v.as_f64()).filter(|v| v.is_finite()).unwrap_or(0.0);
            let ext = op.str_field("ext");
            let made = doc.diagram_add_image(
                scene, hash, if ext.is_empty() { "jpg" } else { &ext }, (n("pw").max(0.0) as u32, n("ph").max(0.0) as u32),
                n("bytes").max(0.0) as u64, &op.str_field("filename"), (n("x"), n("y")), n("width").max(0.5),
                op.get("photo").and_then(|v| v.as_bool()).unwrap_or(false),
            );
            Some(made.map(|id| vec![id]).ok_or_else(|| "the picture could not be laid on the plan".to_string()))
        }
        "favorite" => {
            let slot = op.get("slot").and_then(|s| s.as_f64()).map(|s| s as usize).unwrap_or(usize::MAX);
            let piece = op.get("el").filter(|e| !e.is_null()).and_then(El::from_json);
            if !doc.set_diagram_favorite_from(slot, scene, piece.as_ref()) {
                return Some(Err("no such slot".into()));
            }
            Some(Ok(Vec::new()))
        }
        _ => None,
    }
}

pub fn plan_edit_in(doc: &mut Doc, ask: &str) -> String {
    use shotlister_engine::jsonw::Json as Writer;
    let problem = |said: &str| {
        let mut j = Writer::new();
        j.obj().kv("error", said).end_obj();
        j.finish()
    };
    let Some(asked) = json::parse(ask) else { return problem("that edit could not be read") };
    let Some(id) = asked.str_field("scene").trim().parse::<u128>().ok().map(Id) else { return problem("which scene?") };
    if doc.get(id).is_none() {
        return problem("that is not a scene this film has");
    }
    let Some(op) = asked.get("op") else { return problem("say what to change") };
    // A scene's several diagrams and a cast member's colour: the engine's
    // own portal edits, which say how they are taken back.
    if let Some(done) = doc.portal_edit(id, op) {
        return match done {
            Ok(sp) => {
                let mut j = Writer::new();
                j.obj().key("made").arr();
                for m in &sp.made {
                    j.str(m);
                }
                j.end_arr().key("undo").arr();
                for u in &sp.undo {
                    j.raw(&u.encode());
                }
                j.end_arr().end_obj();
                j.finish()
            }
            Err(e) => problem(&e),
        };
    }
    let before = doc.diagram(id);
    let made = match special_edit(doc, id, op) {
        Some(Ok(made)) => made,
        Some(Err(e)) => return problem(&e),
        None => match doc.diagram_edit(id, op) {
            Ok(made) => made,
            Err(e) => return problem(&e.to_string()),
        },
    };
    let after = doc.diagram(id);
    let mut j = Writer::new();
    j.obj().key("made").arr();
    for m in &made {
        j.str(m);
    }
    j.end_arr().key("undo").arr();
    for u in plan_undo(&before, &after) {
        j.raw(&u.encode());
    }
    j.end_arr().end_obj();
    j.finish()
}

/// **Where things are, for the pointer** — hit, snap and walls, all in the
/// plan as shown (north up); the engine's own rules, as the Mac uses them.
///
/// `{scene, what: "hit"|"snap"|"wall"|"within", x, y, tol, beat, skip, rect}`
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan_where(ptr: *const u8, len: usize) -> *mut u8 {
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| give(plan_where_in(&film.borrow().doc, &ask)))
}

pub fn plan_where_in(doc: &Doc, ask: &str) -> String {
    use shotlister_engine::diagram::{self as dg, render};
    use shotlister_engine::jsonw::Json as Writer;
    let Some(asked) = json::parse(ask) else { return "{}".into() };
    let Some(id) = asked.str_field("scene").trim().parse::<u128>().ok().map(Id) else { return "{}".into() };
    let mut plan = doc.diagram(id);
    let turn = render::view_turn(&plan);
    let num = |k: &str| asked.get(k).and_then(|v| v.as_f64()).filter(|n| n.is_finite());
    let skip: Vec<String> = asked
        .get("skip")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let (sx, sy) = (num("x").unwrap_or(0.0), num("y").unwrap_or(0.0));
    // Shown → as stored, and back.
    let (x, y) = render::turn_point(sx, sy, -turn);
    let out = |px: f64, py: f64| render::turn_point(px, py, turn);
    let mut j = Writer::new();
    j.obj();
    match asked.str_field("what").as_str() {
        "hit" => {
            plan.els.retain(|e| !skip.contains(&e.id));
            let beat = num("beat").map(|b| b.max(1.0) as u32).unwrap_or(1);
            // On the page, what is drawn is what is clicked (Ref 1511).
            let hit = match num("page_scale").filter(|k| *k > 0.0) {
                Some(k) => dg::hit_drawn(&plan, x, y, num("tol").unwrap_or(0.05), beat, &render::Options { scale: k, page: true, ..Default::default() }),
                None => dg::hit(&plan, x, y, num("tol").unwrap_or(0.05), beat),
            };
            match hit {
                Some(hit) => { j.kv("id", &hit); }
                None => { j.key("id").null(); }
            }
        }
        "snap" => {
            // The Mac's `diagramsnap`: a corner, a wall's line, lined up
            // square with a corner (`guides`, as stored), else the grid of
            // `step` — the page's, which follows its zoom. `own`: the wall
            // corner being dragged or drawn, `{id, corner}`.
            let step = num("step").filter(|s| *s > 1e-6).unwrap_or(plan.settings.step);
            let own_id = asked.get("own").map(|o| o.str_field("id")).unwrap_or_default();
            let own_at = asked.get("own").and_then(|o| o.get("corner")).and_then(|c| c.as_f64()).map(|c| c.max(0.0) as usize);
            let own = own_at.filter(|_| !own_id.is_empty()).map(|c| (own_id.as_str(), c));
            let s = dg::walls::snap(&plan, x, y, num("reach").unwrap_or(0.2), step, &skip, own);
            let (qx, qy) = out(s.at.0, s.at.1);
            j.kn("x", qx).kn("y", qy).kb("caught", s.caught).kn("sx", s.at.0).kn("sy", s.at.1);
            j.key("guides").arr();
            for (a, b) in &s.guides {
                j.arr().num(a.0).num(a.1).num(b.0).num(b.1).end_arr();
            }
            j.end_arr();
        }
        "wall" => match dg::walls::in_wall(&plan, x, y, num("reach").unwrap_or(0.4), num("w").unwrap_or(0.0).max(0.0), num("step").unwrap_or(0.0).max(0.0)) {
            // The Mac's `diagramwall`: where a door lands in a wall, slid by
            // `step` from the nearer corner's face (`from`, `face`, `edge`).
            Some(at) => {
                let (qx, qy) = out(at.x, at.y);
                j.kn("x", qx).kn("y", qy).kn("rot", at.rot).kn("thick", at.thick).kn("sx", at.x).kn("sy", at.y);
                j.kv("wall", &at.wall).kn("stretch", at.stretch as f64).kn("from", at.from);
                j.kn("fx", at.face.0).kn("fy", at.face.1).kn("ex", at.edge.0).kn("ey", at.edge.1);
            }
            None => { j.key("x").null(); }
        },
        _ => {}
    }
    j.end_obj();
    j.finish()
}

/// The library — every drawing the plan can hold, the pack's first — and the
/// sensors a camera can name. The Mac's `diagramlibrary`.
#[no_mangle]
pub extern "C" fn plan_library() -> *mut u8 {
    give(plan_library_json())
}

/// The library as one JSON object (`plan_library`).
pub fn plan_library_json() -> String {
    use shotlister_engine::diagram::{frame, gels, wire};
    use shotlister_engine::jsonw::Json as Writer;
    // The Mac's library, and the lists its Details panel picks from — gels,
    // a frame's skins, pipes and grids — so the two can never disagree.
    let lib = wire::library();
    let mut j = Writer::new();
    j.obj().key("gels").arr();
    for g in gels::GELS {
        j.obj().kv("id", g.id).kv("name", g.name).end_obj();
    }
    j.end_arr().key("materials").arr();
    for (id, name, _) in frame::MATERIALS {
        j.obj().kv("id", id).kv("name", name).end_obj();
    }
    j.end_arr().key("pipes").arr();
    for (id, name) in frame::PIPES {
        j.obj().kv("id", id).kv("name", name).end_obj();
    }
    j.end_arr().key("grids").arr();
    for g in frame::GRIDS {
        j.num(*g);
    }
    j.end_arr().kv("frame", frame::SYM).kv("material", frame::DEFAULT_MATERIAL).end_obj();
    let extra = j.finish();
    // One object: the library's keys, then these. **Exactly one** brace off
    // each: the library now ends on an object of its own (`frames`), and
    // trimming every closing brace took that one too — the page got a
    // library it could not read, and every tile went blank.
    let lib = lib.trim_end();
    let extra = extra.trim_start();
    format!("{},{}", lib.strip_suffix('}').unwrap_or(lib), extra.strip_prefix('{').unwrap_or(extra))
}

/// The nine favorite slots: each empty, or the piece it keeps and its name.
/// With `x y`, the piece in `slot` made ready to put down there.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan_favorites(ptr: *const u8, len: usize) -> *mut u8 {
    use shotlister_engine::diagram::favorites;
    use shotlister_engine::jsonw::Json as Writer;
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| {
        let f = film.borrow();
        let slots = f.doc.diagram_favorites();
        let n: Vec<f64> = ask.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        let mut j = Writer::new();
        if n.len() == 3 {
            let fav = slots.into_iter().nth(n[0] as usize).flatten();
            match fav.and_then(|fav| favorites::placed_op(&fav, n[1], n[2])) {
                Some(op) => { j.obj().key("op").raw(&op.encode()).end_obj(); }
                None => { j.obj().kv("error", "that slot is empty").end_obj(); }
            }
            return give(j.finish());
        }
        j.obj().key("slots").arr();
        for slot in slots {
            match slot {
                Some(fav) => { j.obj().kv("name", &favorites::name(&fav)).key("el").raw(&fav.encode()).end_obj(); }
                None => { j.null(); }
            }
        }
        j.end_arr().end_obj();
        give(j.finish())
    })
}

/// Who the cast tool offers: this scene's characters, then the film's.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan_cast(ptr: *const u8, len: usize) -> *mut u8 {
    use shotlister_engine::jsonw::Json as Writer;
    let scene = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    FILM.with(|film| {
        let f = film.borrow();
        let mut j = Writer::new();
        j.obj();
        if let Some(id) = scene.trim().parse::<u128>().ok().map(Id) {
            let (here, others) = f.doc.diagram_characters(id);
            j.key("scene").arr();
            for n in &here { j.str(n); }
            j.end_arr().key("film").arr();
            for n in &others { j.str(n); }
            j.end_arr();
        }
        // **Each one's colour for the whole project** (his ask, 2026-10-17):
        // the ones he gave, else billing order — what every plan draws them in.
        // `own`: the ones he picked himself.
        let field = f.doc.cast_field().unwrap_or_else(|| "cast".to_string());
        let own: Vec<String> = f.doc.stored_term_colours(&field).into_iter().map(|(t, _)| t.to_lowercase()).collect();
        j.key("colours").obj();
        for (name, hex) in f.doc.term_colours(&field) {
            j.kv(&name, &format!("#{}", hex.trim_start_matches('#')));
        }
        j.end_obj().key("own").arr();
        for n in &own { j.str(n); }
        j.end_arr();
        j.end_obj();
        give(j.finish())
    })
}

/// One drawing on its own, as a small picture — a library tile or a tool's
/// face. The Mac's `diagramglyph`, drawn as SVG.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn plan_glyph(ptr: *const u8, len: usize, w: f64, h: f64, px: f64) -> *mut u8 {
    use shotlister_engine::diagram::{self as dg, render, svg};
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    let mut parts = ask.splitn(2, ' ');
    let kind = parts.next().unwrap_or("set");
    let sym = parts.next().unwrap_or("").to_string();
    let Some(k) = dg::Kind::parse(kind) else { return give(String::new()) };
    let mut el = dg::El::new(k, "glyph");
    el.sym = sym;
    el.w = if w.is_finite() { w.max(0.01) } else { 1.0 };
    el.h = if h.is_finite() { h.max(0.01) } else { 1.0 };
    el.cone = false;
    el.beam_on = false;
    el.label.clear();
    if k == dg::Kind::Door || k == dg::Kind::Window {
        el.h = 0.15;
    }
    if k.is_line() {
        el.x = -el.w / 2.0;
        el.x2 = el.w / 2.0;
        el.y = 0.0;
        el.y2 = 0.0;
    }
    let mut plan = dg::Diagram::default();
    plan.settings.labels = false;
    plan.settings.dims = false;
    plan.settings.grid = false;
    plan.els.push(el);
    let frame = svg::Frame { width: if px.is_finite() { px.max(16.0) } else { 64.0 }, margin: 4.0, grid: false, scale_bar: false,
        max_height: Some(if px.is_finite() { px.max(16.0) } else { 64.0 }), max_scale: 4000.0, art: "fso/{id}.png".into(), ..Default::default() };
    give(svg::svg(&plan, &render::Context::default(), &render::Options::default(), &frame, "g"))
}

/// Which Show switch a piece answers to — `DiagramShow.kind` on the Mac, the
/// same list: a lamp is a light only if it throws a beam, else it is grip.
fn plan_show(e: &shotlister_engine::diagram::El) -> &'static str {
    use shotlister_engine::diagram::{symbols, Kind as K};
    match e.kind {
        K::Camera => "cameras",
        K::Cast => "cast",
        K::Light => if symbols::emits(&e.sym) { "lights" } else { "grip" },
        K::Set => "set",
        K::Wall | K::Door | K::Window | K::Opening => "walls",
        K::Text | K::Note => "words",
        K::Image => "pictures",
        _ => "",
    }
}

/// A piece's name in Layers — `DiagramItems.name` on the Mac: a camera by its
/// shot, then its own label, a note by its words, a lamp or set piece by its
/// library name, else what kind of thing it is.
fn plan_name(e: &shotlister_engine::diagram::El, ctx: &shotlister_engine::diagram::render::Context, units: &str) -> String {
    use shotlister_engine::diagram::{render, symbols, Kind as K};
    if e.kind == K::Camera {
        let n = render::camera_name(e, ctx);
        if !n.is_empty() {
            return n;
        }
    }
    if e.kind == K::Cast {
        if let Some(n) = ctx.cast_name(&e.cast) {
            if !n.is_empty() {
                return n.to_string();
            }
        }
    }
    if !e.label.trim().is_empty() {
        return e.label.trim().to_string();
    }
    if matches!(e.kind, K::Text | K::Note) && !e.text.trim().is_empty() {
        return e.text.trim().chars().take(30).collect();
    }
    if matches!(e.kind, K::Set | K::Light) && !e.sym.is_empty() {
        let n = symbols::plan_name(&e.sym);
        if !n.is_empty() {
            return n;
        }
        return e.sym.split(['-', '_']).filter(|w| !w.is_empty()).map(|w| {
            let mut c = w.chars();
            c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
        }).collect::<Vec<_>>().join(" ");
    }
    if e.kind == K::Wall {
        return shotlister_engine::diagram::length_text((e.x2 - e.x).hypot(e.y2 - e.y), units);
    }
    // A door by its kind (2026-10-17), as the Mac's heading says it.
    if e.kind == K::Door {
        return match e.door_style() {
            "double" => "Double Door",
            "sliding" => "Sliding Door",
            "center" => "Center Sliding Door",
            "pocket" | "pocketpair" => "Pocket Door",
            _ => "Door",
        }
        .into();
    }
    match e.kind {
        K::Set => "Set Piece".into(),
        K::Image => "Picture".into(),
        K::Stroke => "Drawing".into(),
        k => {
            let w = k.as_str();
            w[..1].to_uppercase() + &w[1..]
        }
    }
}

/// The SVG itself, in plain Rust so the native run can check it too.
pub fn arrow_picture(line: &str, w: f64, h: f64) -> String {
    if !w.is_finite() || !h.is_finite() || w < 1.0 || h < 1.0 {
        return String::new();
    }
    let mut shapes = String::new();
    for arrow in Arrow::parse(line) {
        // The same pieces, fill, outline and width the printed page draws —
        // `Arrow::svg`, so a dashed red arrow is a dashed red arrow on both.
        shapes.push_str(&arrow.svg(w, h));
    }
    if shapes.is_empty() {
        return String::new();
    }
    format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{w:.0}\" height=\"{h:.0}\" \
         viewBox=\"0 0 {w:.0} {h:.0}\">{shapes}</svg>"
    )
}

/// What a clip's poster ends in. **`relay/layout.json` says `jpg`, and
/// `hub/checks.sh` checks this agrees** — this crate cannot read that file, so
/// it repeats the word and is measured against it.
const POSTER: &str = "jpg";

/// Where a picture lives, as an address rather than as bytes. The name is the
/// first 32 characters of the hash and the file's own extension — which is
/// already exactly how the relay stores it, so no translation happens here.
fn picture_at(d: &Doc, media: Id, base: &str) -> Option<String> {
    let hash = field(d, media, f::HASH);
    if hash.is_empty() {
        return None;
    }
    let moving = d.media_kind(media).map(|k| k.is_moving()).unwrap_or(false);
    // A clip is drawn by its poster, a JPEG since 2026-09-15. The portal
    // answers a `.jpg` address with the PNG under the same name when that is
    // what an older film holds (`hub/src/worker.js`, `media`).
    let extension = if moving {
        POSTER.to_string()
    } else {
        let filename = field(d, media, f::FILENAME);
        filename.rsplit('.').next().unwrap_or("png").to_lowercase()
    };
    let short: String = hash.chars().take(32).collect();
    let extension: String = extension
        .trim_start_matches('.')
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(8)
        .collect();
    Some(format!("{}/{}.{}", base.trim_end_matches('/'), short, extension))
}

fn field(d: &Doc, id: Id, name: &str) -> String {
    match d.get(id).and_then(|r| r.get(name)) {
        Some(Value::Text(s)) => s.clone(),
        Some(Value::Int(n)) => n.to_string(),
        Some(Value::Float(n)) => format!("{}", n),
        Some(Value::Bool(b)) => b.to_string(),
        _ => String::new(),
    }
}

fn push_pair(out: &mut String, key: &str, value: &str) {
    out.push('"');
    out.push_str(key);
    out.push_str("\":\"");
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn push_number(out: &mut String, key: &str, value: usize) {
    out.push('"');
    out.push_str(key);
    out.push_str("\":");
    out.push_str(&value.to_string());
}

// ------------------------------------------------------------- scanned rooms

/// **A scanned room, drawn flat.**
///
/// The measurements the phone's LiDAR wrote are read by `engine::room` — the
/// one copy of that arithmetic, which the Mac and the phone both ask — and this
/// turns the answer into an SVG the page can hang in a panel.
///
/// **The drawing is here rather than in JavaScript for the same reason
/// `arrow_picture` is**: a plan drawn by a second program is a second opinion
/// about a room, and `cargo test` can look at this one. The conventions are the
/// Mac's, kept deliberately: furniture goes *under* the walls, because a
/// scanner measures a wardrobe to its back panel and a wall to its face and
/// letting the wall cover the overlap is how a plan looks right without moving
/// anything; a door or window is cut out of the wall a shade wider than the
/// wall is drawn, so no sliver survives along its edge; a window is the two
/// lines of glass across the hole, which is how a plan has always drawn one;
/// and a door carries the quarter-circle it sweeps, because the question on a
/// location is whether the door fouls the shot.
///
/// **No colours are written here.** Every shape carries a class and the page's
/// own stylesheet paints it, so a plan follows the portal into dark exactly as
/// the rest of a film's page does.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn scan_plan(ptr: *const u8, len: usize, w: f64, h: f64) -> *mut u8 {
    let text = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    give(room_drawing(&text, w, h))
}

/// The plan and what can be said about it, as JSON. Plain Rust so the native
/// run checks the same drawing the browser gets.
///
/// A room that cannot be read comes back as `{}` — which is the honest answer
/// for a `.json` that is not a scan, and the page says the measurements are
/// missing rather than drawing an empty box.
pub fn room_drawing(text: &str, w: f64, h: f64) -> String {
    if !w.is_finite() || !h.is_finite() || w < 1.0 || h < 1.0 {
        return "{}".into();
    }
    let Some(plan) = shotlister_engine::room::read(text) else {
        return "{}".into();
    };
    let (across, deep) = plan.extent();
    if across <= 0.0 || deep <= 0.0 {
        return "{}".into();
    }

    // One scale for both axes, or the room comes out stretched and every
    // measurement read off it becomes a lie.
    let margin = 10.0_f64;
    let fit = ((w - margin * 2.0) / across as f64).min((h - margin * 2.0) / deep as f64);
    let middle = (
        (plan.bounds.0 .0 + plan.bounds.1 .0) / 2.0,
        (plan.bounds.0 .1 + plan.bounds.1 .1) / 2.0,
    );
    let place = |p: (f32, f32)| -> (f64, f64) {
        (
            w / 2.0 + (p.0 - middle.0) as f64 * fit,
            h / 2.0 + (p.1 - middle.1) as f64 * fit,
        )
    };

    // RoomPlan calls a wall a plane with no thickness. A plan needs one, and
    // this is it — a drawing convention, never a measurement. The Mac's own
    // number, in metres so it holds at any scale.
    let thickness = (7.0 / fit.max(0.0001)) as f32;

    let mut shapes = String::new();
    // **Every measurable thing is drawn carrying its own name.** The pop-up
    // lists the walls and openings as rows you can copy a number off, and a row
    // that cannot point at the thing it measures is a number with no wall — so
    // the row and the shape share `p<n>`, the item's place in the plan.
    let poly = |item: &shotlister_engine::room::Item, thick: f32, class: &str, id: &str| -> String {
        let points: Vec<String> = item
            .corners(Some(thick))
            .iter()
            .map(|c| {
                let (x, y) = place(*c);
                format!("{:.1},{:.1}", x, y)
            })
            .collect();
        let named = if id.is_empty() {
            String::new()
        } else {
            format!(" data-part=\"{}\"", id)
        };
        format!(
            "<polygon class=\"{}\"{} points=\"{}\"/>",
            class,
            named,
            points.join(" ")
        )
    };

    use shotlister_engine::room::Part;
    for thing in plan.items.iter().filter(|i| i.part == Part::Object) {
        shapes.push_str(&poly(thing, thing.size.1.max(0.02), "pl-thing", ""));
    }
    for (at, wall) in plan.items.iter().enumerate().filter(|(_, i)| i.part == Part::Wall) {
        shapes.push_str(&poly(wall, thickness, "pl-wall", &format!("p{at}")));
    }
    for (at, hole) in plan
        .items
        .iter()
        .enumerate()
        .filter(|(_, i)| i.part != Part::Wall && i.part != Part::Object)
    {
        shapes.push_str(&poly(hole, thickness * 1.6, "pl-hole", &format!("p{at}")));
        let (c, s) = (hole.angle.cos(), hole.angle.sin());
        let half = hole.size.0 / 2.0;
        let start = (hole.centre.0 - half * c, hole.centre.1 - half * s);
        let end = (hole.centre.0 + half * c, hole.centre.1 + half * s);
        if hole.part == Part::Window {
            // The wall's own direction turned a quarter turn — where "across
            // the hole" points.
            let across = (-s * thickness / 3.0, c * thickness / 3.0);
            for sign in [1.0_f32, -1.0] {
                let a = place((start.0 + across.0 * sign, start.1 + across.1 * sign));
                let b = place((end.0 + across.0 * sign, end.1 + across.1 * sign));
                shapes.push_str(&format!(
                    "<line class=\"pl-glass\" x1=\"{:.1}\" y1=\"{:.1}\" x2=\"{:.1}\" y2=\"{:.1}\"/>",
                    a.0, a.1, b.0, b.1
                ));
            }
        }
        if hole.part == Part::Door {
            // **Which way a door opens is not in the scan**, so it is drawn
            // into the room — the arc is what answers whether it fouls a shot.
            let hinge = place(start);
            let reach = hole.size.0 as f64 * fit;
            let sweep = hole.angle as f64 + std::f64::consts::FRAC_PI_2;
            let tip = (
                hinge.0 + reach * sweep.cos(),
                hinge.1 + reach * sweep.sin(),
            );
            let from = place(end);
            shapes.push_str(&format!(
                "<path class=\"pl-swing\" d=\"M {:.1} {:.1} A {:.1} {:.1} 0 0 1 {:.1} {:.1}\"/>",
                from.0, from.1, reach, reach, tip.0, tip.1
            ));
        }
    }

    // **`data-scale` is how many drawing units are a metre**, so the page's
    // measure tool can turn two points pressed on the plan into a distance
    // without a second opinion about the room's size.
    let svg = format!(
        "<svg class=\"plan\" viewBox=\"0 0 {:.0} {:.0}\" xmlns=\"http://www.w3.org/2000/svg\" \
         data-scale=\"{:.4}\" role=\"img\" aria-label=\"Floor plan of a scanned room\">{}</svg>",
        w, h, fit, shapes
    );

    let mut out = String::from("{");
    push_pair(&mut out, "svg", &svg);
    out.push(',');
    push_pair(&mut out, "across", &feet_and_inches(across));
    out.push(',');
    push_pair(&mut out, "deep", &feet_and_inches(deep));
    out.push(',');
    push_pair(&mut out, "ceiling", &feet_and_inches(plan.ceiling()));
    out.push(',');
    push_number(&mut out, "walls", plan.walls().count());
    out.push(',');
    push_number(
        &mut out,
        "doors",
        plan.items.iter().filter(|i| i.part == Part::Door).count(),
    );
    out.push(',');
    push_number(
        &mut out,
        "windows",
        plan.items.iter().filter(|i| i.part == Part::Window).count(),
    );
    out.push(',');
    // **A stepped or sloped ceiling is a real fact about a location** and the
    // phone found it on a real room. One number for a room whose walls
    // disagree is a lie the panel should not tell.
    out.push_str("\"ceilingVaries\":");
    out.push_str(if plan.ceiling_varies() { "true" } else { "false" });

    // **How low and how high, when they disagree.** One number for a stepped
    // ceiling is the lie above; the pair is what a scout actually needs, and it
    // costs nothing to carry it always and let the page decide when to say it.
    let (low, high) = plan.ceiling_range();
    out.push(',');
    push_pair(&mut out, "ceilingLow", &feet_and_inches(low));
    out.push(',');
    push_pair(&mut out, "ceilingHigh", &feet_and_inches(high));

    // **Every wall and every opening, measured one at a time.** His ask of
    // 2026-09-09: the room opens into a pop-up "and copy any dimension they
    // would need down". The counts above answer *how many*; a number you can
    // copy has to be a number about one wall.
    //
    // **Longest first, within its kind.** A room's long wall is the one a dolly
    // goes down and the one somebody asks about; scan order is the order he
    // happened to walk, which is no order at all. The number in the label is
    // this list's own — `Wall 1` is the longest wall — and the plan lights the
    // wall up when the row is pointed at, which is what actually says which.
    out.push_str(",\"parts\":[");
    let mut wrote = 0;
    for (part, name) in [
        (Part::Wall, "Wall"),
        (Part::Door, "Door"),
        (Part::Window, "Window"),
        (Part::Opening, "Opening"),
    ] {
        let mut of_kind: Vec<(usize, &shotlister_engine::room::Item)> = plan
            .items
            .iter()
            .enumerate()
            .filter(|(_, i)| i.part == part)
            .collect();
        of_kind.sort_by(|a, b| {
            b.1.size
                .0
                .partial_cmp(&a.1.size.0)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        for (n, (at, item)) in of_kind.iter().enumerate() {
            if wrote > 0 {
                out.push(',');
            }
            wrote += 1;
            out.push('{');
            push_pair(&mut out, "id", &format!("p{at}"));
            out.push(',');
            push_pair(&mut out, "kind", part.as_str());
            out.push(',');
            push_pair(&mut out, "label", &format!("{name} {}", n + 1));
            out.push(',');
            push_pair(&mut out, "long", &feet_and_inches(item.size.0));
            out.push(',');
            push_pair(&mut out, "tall", &feet_and_inches(item.height));
            out.push('}');
        }
    }
    out.push(']');
    out.push('}');
    out
}

/// Feet and inches, the way a location scout says a room — "13 ft 3 in".
/// Character for character what `studio/Sources/Scan.swift` writes, so the
/// same room reads the same on both.
fn feet_and_inches(metres: f32) -> String {
    let total = (metres * 39.370_08).round() as i64;
    let (feet, inches) = (total / 12, total % 12);
    if feet == 0 {
        return format!("{inches} in");
    }
    if inches == 0 {
        return format!("{feet} ft");
    }
    format!("{feet} ft {inches} in")
}

/// **A picture's marks, for Draw on Photo on the portal** (his ask,
/// 2026-10-17: the portal edits diagrams as much as the Mac). The stored
/// line (`diagram::photomarks`) read into marks a page can move and restyle,
/// and written back — the engine's own reader and writer, so the portal, the
/// Mac and paper agree on every mark. The page sends the line back with the
/// plan's ordinary `update {marks}`.
///
/// `{"parse": "<line>"}` answers `{"marks": [...]}`; `{"encode": [...]}`
/// answers `{"line": "..."}`. A mark is
/// `{kind: arrow|line|box|oval|draw|words, look, …}`: an arrow carries its
/// own stored text as `src` (so what the page does not touch — hand-set
/// widths, a zoom — is kept) and `x1 y1 x2 y2 pins shape heads dashed
/// thickness depth`; a line, box or oval `a b thick dashed`; a drawing
/// `points thick`; words `at text size`.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn photo_marks(ptr: *const u8, len: usize) -> *mut u8 {
    use json::Json as J;
    use shotlister_engine::arrow::{ArrowDepth, ArrowLook, ArrowShape};
    use shotlister_engine::diagram::photomarks::{Kind as MarkKind, Mark};
    let ask = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    let Some(asked) = json::parse(&ask) else { return give(r#"{"error":"that could not be read"}"#.to_string()) };
    let num = |v: f64| J::Number((v * 10000.0).round() / 10000.0);
    let pt = |p: (f64, f64)| J::Array(vec![num(p.0), num(p.1)]);
    if let Some(line) = asked.get("parse").and_then(|l| l.as_str()) {
        let marks: Vec<J> = Mark::parse(line)
            .into_iter()
            .map(|m| match m {
                Mark::Arrow(a) => J::object(vec![
                    ("kind", J::text("arrow")),
                    ("src", J::text(Arrow::encode(std::slice::from_ref(&a)))),
                    ("x1", num(a.x1)),
                    ("y1", num(a.y1)),
                    ("x2", num(a.x2)),
                    ("y2", num(a.y2)),
                    ("pins", J::Array(a.pins.iter().map(|p| pt(*p)).collect())),
                    ("shape", J::text(a.shape.name())),
                    ("heads", J::Number(a.heads as f64)),
                    ("dashed", J::Bool(a.dashed)),
                    ("look", J::text(a.look.name())),
                    ("thickness", num(a.thickness)),
                    ("depth", J::text(a.depth.name())),
                    ("zoom", J::Bool(a.zoom.is_some())),
                ]),
                Mark::Shape { kind, a, b, look, thick, dashed } => J::object(vec![
                    ("kind", J::text(kind.name())),
                    ("a", pt(a)),
                    ("b", pt(b)),
                    ("look", J::text(look.name())),
                    ("thick", num(thick)),
                    ("dashed", J::Bool(dashed)),
                ]),
                Mark::Draw { points, look, thick } => J::object(vec![
                    ("kind", J::text("draw")),
                    ("points", J::Array(points.iter().map(|p| pt(*p)).collect())),
                    ("look", J::text(look.name())),
                    ("thick", num(thick)),
                ]),
                Mark::Words { at, text, look, size } => J::object(vec![
                    ("kind", J::text("words")),
                    ("at", pt(at)),
                    ("text", J::text(text)),
                    ("look", J::text(look.name())),
                    ("size", num(size)),
                ]),
            })
            .collect();
        return give(J::object(vec![("marks", J::Array(marks))]).encode());
    }
    let Some(list) = asked.get("encode").and_then(|l| l.as_array()) else {
        return give(r#"{"error":"say parse or encode"}"#.to_string());
    };
    let f = |m: &J, k: &str, or: f64| m.get(k).and_then(|v| v.as_f64()).filter(|v| v.is_finite()).unwrap_or(or);
    let p2 = |v: Option<&J>| -> Option<(f64, f64)> {
        let a = v?.as_array()?;
        Some((a.first()?.as_f64()?, a.get(1)?.as_f64()?))
    };
    let look = |m: &J| ArrowLook::read(&m.str_field("look")).unwrap_or(ArrowLook::Light);
    let mut marks: Vec<Mark> = Vec::new();
    for m in list {
        let kind = m.str_field("kind");
        match kind.as_str() {
            "arrow" => {
                let mut a = Arrow::parse(&m.str_field("src")).into_iter().next().unwrap_or_else(|| Arrow::straight(0.2, 0.5, 0.8, 0.5));
                a.x1 = f(m, "x1", a.x1);
                a.y1 = f(m, "y1", a.y1);
                a.x2 = f(m, "x2", a.x2);
                a.y2 = f(m, "y2", a.y2);
                if let Some(pins) = m.get("pins").and_then(|p| p.as_array()) {
                    a.pins = pins.iter().filter_map(|p| p2(Some(p))).collect();
                }
                if let Some(s) = ArrowShape::read(&m.str_field("shape")) {
                    a.shape = s;
                }
                if let Some(h) = m.get("heads").and_then(|v| v.as_f64()) {
                    a.heads = h.clamp(0.0, 2.0) as u8;
                }
                if let Some(d) = m.get("dashed").and_then(|v| v.as_bool()) {
                    a.dashed = d;
                }
                a.look = look(m);
                a.thickness = f(m, "thickness", a.thickness);
                if let Some(d) = ArrowDepth::read(&m.str_field("depth")) {
                    // A new depth draws its own widths (the Mac's `withDepth`).
                    if d != a.depth {
                        a.widths = None;
                    }
                    a.depth = d;
                }
                marks.push(Mark::Arrow(a.held()));
            }
            "line" | "box" | "oval" => {
                let k = match kind.as_str() { "line" => MarkKind::Line, "box" => MarkKind::Box, _ => MarkKind::Oval };
                let (Some(a), Some(b)) = (p2(m.get("a")), p2(m.get("b"))) else { continue };
                let dashed = m.get("dashed").and_then(|v| v.as_bool()).unwrap_or(false);
                marks.push(Mark::Shape { kind: k, a, b, look: look(m), thick: f(m, "thick", 1.0), dashed });
            }
            "draw" => {
                let points: Vec<(f64, f64)> = m.get("points").and_then(|p| p.as_array()).map(|a| a.iter().filter_map(|p| p2(Some(p))).collect()).unwrap_or_default();
                if points.len() >= 2 {
                    marks.push(Mark::Draw { points, look: look(m), thick: f(m, "thick", 1.0) });
                }
            }
            "words" => {
                let Some(at) = p2(m.get("at")) else { continue };
                let text = m.str_field("text");
                if !text.trim().is_empty() {
                    marks.push(Mark::Words { at, text, look: look(m), size: f(m, "size", shotlister_engine::diagram::photomarks::WORDS_SIZE) });
                }
            }
            _ => {}
        }
    }
    // Written, then read back: what the engine keeps is what the page gets.
    let line = Mark::encode(&marks);
    let line = Mark::encode(&Mark::parse(&line));
    give(J::object(vec![("line", J::text(line))]).encode())
}
