//! The C boundary the Mac app calls across.
//!
//! Four functions rather than sixty bindings. Swift sends a tab-delimited
//! command and gets JSON back; everything goes through the engine, so the app
//! obeys the same validation, writes the same change records, and is as undoable
//! as anything typed by hand. There is no rule in here that the engine does not
//! already have.

use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;

use shotlister_engine::doc::f;
use shotlister_engine::export::autolayout;
use shotlister_engine::export::html::{self, ColumnWidths, FrameSize, Print};
use shotlister_engine::export::share::{self, ShareFrame, ShareOptions};
use shotlister_engine::export::xlsx;
use shotlister_engine::layout::FramePosition;
use shotlister_engine::query::GroupBy;
use shotlister_engine::media::{Arrow, MediaKind};
use shotlister_engine::printframe::{self, PrintFrame};
use shotlister_engine::hash::Hash256;
use shotlister_engine::sha256;
use shotlister_engine::package;
use shotlister_engine::store::Kind;
use shotlister_engine::value::Value;
use shotlister_engine::{DeviceId, Doc, Id, Query};
use shotlister_storage::{write_whole, Project};

mod b64;

/// Exposed for the seed_frame example, which does the app's encoding job from
/// the command line so the drawing half can be checked on its own.
pub fn encode_for_test(bytes: &[u8]) -> String {
    b64::encode(bytes)
}
mod demo;
mod diagram;
mod versions;

use shotlister_engine::jsonw::Json;
use shotlister_engine::view;

pub struct Handle {
    project: Project,
    group_by: GroupBy,
    /// What is being looked for, and whether cut shots are being shown. Filtering
    /// is the only thing in the app that removes a row from sight, so it is kept
    /// in one place and applied to every payload rather than per screen.
    search: String,
    hide_struck: bool,
    /// Narrowing by what a scene *is* — interior or exterior, where, when, how
    /// urgent. The original app filtered the film this way and it is how a long
    /// list is made short enough to work in.
    facets: Vec<(String, String)>,
    /// Which day, and which sequence. Kept apart from the facets because they
    /// are references rather than words.
    day: Option<Id>,
    unscheduled_only: bool,
    sequence: Option<Id>,
    /// **The shoot the picker is on** (piece D): every list, the schedule's
    /// days and the locations narrow to it. `None` is All Shoots.
    shoot: Option<String>,
    /// Reading each scene in one column's order rather than the list's own.
    sort: Option<(String, bool)>,
    /// **An earlier version on screen instead of now**, and the film as it
    /// stood then. See `versions`: it is swapped in for one command at a time
    /// and never saved.
    looking: Option<versions::Looking>,
    /// True for the length of a command that is showing the old version, so
    /// the view it answers says the film cannot be changed.
    showing_old: bool,
}

impl Handle {
    /// What is being asked for, in the engine's own words.
    ///
    /// **The building of it moved to `engine::view::Asked`** when the hub had
    /// to search too — a second copy of "what a search means" would have
    /// drifted inside a week, and the one nobody was sitting in front of would
    /// have been the one that drifted.
    fn asked(&self) -> view::Asked {
        view::Asked {
            group_by: self.group_by,
            search: self.search.clone(),
            hide_struck: self.hide_struck,
            facets: self.facets.clone(),
            day: self.day,
            unscheduled_only: self.unscheduled_only,
            sequence: self.sequence,
            shoot: self.shoot.clone(),
            sort: self.sort.clone(),
        }
    }

    fn query(&self) -> Query {
        self.asked().query()
    }

}

// ---------------------------------------------------------------- reading








/// A media's own bytes, or its poster if it is a movie or GIF and one has
/// been kept — the same poster-first order `Table.swift`'s `image(_:from:)`
/// already reads by (his own bug, 2026-08-22: a clip's own bytes are never a
/// picture, so asking for them first and falling back never actually
/// reaches the poster). Every export that draws a still goes through this
/// now, so none of them can go back to trying to embed a video's raw bytes
/// as an image — the failure that used to leave the cell blank in a
/// spreadsheet and a broken image in a PDF alike.
///
/// A poster is a still whatever the medium itself is — JPEG now, PNG in
/// films written before 2026-09-15 — so the extension returned alongside is
/// not always the file's own.
// ---------------------------------------------------------- reading a record
//
// **The real ones live in `engine::view` now** (2026-09-01), because the
// browser draws the same screens and cannot reach anything in here — this file
// reads and writes files, and a browser does neither. These are the same
// functions with a `Project` in front of them, so every caller in this crate
// is untouched.

fn text(p: &Project, id: Id, field: &str) -> String {
    view::text(p.doc(), id, field)
}

fn float(p: &Project, id: Id, field: &str) -> Option<f64> {
    view::float(p.doc(), id, field)
}

fn reference(p: &Project, id: Id, field: &str) -> Option<Id> {
    view::reference(p.doc(), id, field)
}

fn framing(p: &Project, j: &mut Json, mref: Id) {
    view::framing(p.doc(), j, mref)
}

fn arrows(p: &Project, j: &mut Json, mref: Id) {
    view::arrows(p.doc(), j, mref)
}

/// Everything the table draws, in one payload — built by `engine::view` and
/// handed the few things only an open project knows.
fn view(h: &Handle) -> String {
    let p = &h.project;
    let asked = h.asked();
    view::describe(
        p.doc(),
        &asked.looking(),
        &view::Standing {
            read_only: p.is_read_only() || h.showing_old,
            unsaved: p.unsaved(),
            device_clash: p.identity_clash().map(|clash| clash.message()),
        },
    )
}

fn frame_bytes(p: &Project, media: Id) -> Option<(Vec<u8>, String)> {
    let hex = text(p, media, f::HASH);
    let moving = p.doc().media_kind(media).map(|k| k.is_moving()).unwrap_or(false);
    if moving {
        // JPEG since 2026-09-15, PNG before; a film opened on an older device
        // can hold either, and a clip that came off the phone on an older
        // build still does.
        for ext in ["jpg", "png"] {
            if let Ok(Some(bytes)) = p.read_proxy(&hex, ext) {
                return Some((bytes, ext.to_string()));
            }
        }
    }
    let filename = text(p, media, f::FILENAME);
    let ext = filename.rsplit('.').next().unwrap_or("png").to_lowercase();
    let bytes = p.read_proxy(&hex, &ext).ok().flatten()?;
    Some((bytes, ext))
}

/// Where a picture can be fetched from, given the address pictures live at.
///
/// **The name is already decided and we do not choose it here.** The relay
/// stores media as the first 32 characters of its hash and its extension
/// (`engine/src/package.rs` writes that shape, `relay/src/worker.js` enforces
/// it), so the address of a frame is a fact about a frame rather than
/// something to be arranged. Nothing is uploaded and nothing is looked up —
/// if the film has been synced the picture is there, and if it has not, it
/// is not.
///
/// `None` when the base is not known or the hash is not the shape a name is
/// made of, which leaves the frame to be pasted over the cell as before.
fn frame_url(p: &Project, media: Id, ext: &str, base: Option<&str>) -> Option<String> {
    let base = base?;
    let hex = text(p, media, f::HASH);
    let stem = hex.get(..32)?;
    if !stem.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    Some(format!("{}/{}.{}", base.trim_end_matches('/'), stem, ext))
}

/// **A clip's four moments, when one has been made for it.**
///
/// His ask, 2026-09-01 (Ref 514): a video in an exported PDF is one frozen
/// still, so nothing on the page says the shot moves. A GIF does not fix that
/// — checked, through the app's own renderer: WebKit rasterises a fifty-frame
/// GIF to frame one, and what comes out is byte-identical in meaning to the
/// still we already drew. So the motion has to be *in the picture*: four
/// moments from across the clip, laid two by two in the same box a single
/// frame filled.
///
/// The Mac makes it — reading a frame out of an H.264 file is AVFoundation's
/// job and the engine never touches bytes — and files it beside the movie
/// under the same hash with the `strip` extension, the same bargain the
/// poster already strikes. `find_proxy` never hands it back unasked: it is
/// not a moving picture, so a request for the clip itself still finds the
/// movie.
///
/// **A marked clip keeps its single frame.** Arrows are drawn on one picture
/// in that picture's own fractions; four pictures in the same box would put
/// every mark somewhere it was never placed. A clip he has drawn on has
/// already said how it moves.
/// **`trim` is the range on *this use* of the clip**, and it decides which
/// strip is asked for. His report, 2026-09-01: the four moments were sampled
/// across the whole file, so a thirty-second take cut down to two seconds
/// printed four moments of footage he had thrown away.
///
/// A trim belongs to the attachment and a file can be attached twice with two
/// different ranges, so a strip is filed under `package::strip_key`, which
/// folds the range into the name. **No fall back to the untrimmed strip** when
/// one is asked for and missing: that strip is four moments of the wrong part
/// of the clip, which is the fault being fixed. Answering `None` sends the
/// page to the single poster frame instead, which is what it drew before
/// strips existed.
fn strip_bytes(p: &Project, media: Id, trim: Option<(f64, f64)>) -> Option<(Vec<u8>, String)> {
    let moving = p.doc().media_kind(media).map(|k| k.is_moving()).unwrap_or(false);
    if !moving {
        return None;
    }
    if !text(p, media, f::ARROWS).is_empty() {
        return None;
    }
    let hex = text(p, media, f::HASH);
    let bytes = p
        .read_proxy(&package::strip_key(&hex, trim), "strip")
        .ok()
        .flatten()?;
    if bytes.is_empty() {
        return None;
    }
    // Always a JPEG, whatever the clip itself is — four photographs in one
    // picture, which is the case JPEG exists for.
    Some((bytes, "jpg".to_string()))
}

/// A frame's own shape, read off its bytes rather than asked of a caller who
/// does not have it either — the engine never touches files, and the proxy on
/// disk carries no dimensions beside it. `(0, 0)` for anything unrecognised;
/// `xlsx::frame_size` already treats that as "draw a sensible box".
fn image_dimensions(bytes: &[u8], extension: &str) -> (u32, u32) {
    // **The bytes decide, not the name.** A file is named by its contents in
    // this project and the extension it carries is a label — his fixture keeps
    // JPEGs called `.png`, and a picture re-encoded on the way in is stored
    // under what it *became* while still called what it *came as*. Trusting
    // the label here was worth a whole afternoon on 2026-09-01: every one of
    // those pictures reported no size at all, so the printed page fell back to
    // covering the box and threw the crop away — the very fault being fixed.
    if let Some(size) = png_dimensions(bytes).or_else(|| jpeg_dimensions(bytes)) {
        return size;
    }
    match extension {
        "png" => png_dimensions(bytes).unwrap_or((0, 0)),
        "jpg" | "jpeg" => jpeg_dimensions(bytes).unwrap_or((0, 0)),
        _ => (0, 0),
    }
}

fn png_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    const SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if bytes.len() < 24 || bytes[0..8] != SIGNATURE {
        return None;
    }
    // The IHDR chunk is always first: 8-byte signature, 4-byte length, 4-byte
    // "IHDR", then width and height as big-endian u32s.
    let width = u32::from_be_bytes(bytes[16..20].try_into().ok()?);
    let height = u32::from_be_bytes(bytes[20..24].try_into().ok()?);
    Some((width, height))
}

/// Walks the marker chain to the first frame header (SOF0–SOF15, excluding
/// the DHT/DAC marker numbers that share the range), which is where a JPEG
/// keeps its shape. Most photographs are baseline (SOF0) or progressive
/// (SOF2); the walk covers every variant rather than assuming one.
fn jpeg_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8 {
        return None;
    }
    let mut i = 2usize;
    while i + 4 <= bytes.len() {
        if bytes[i] != 0xFF {
            i += 1;
            continue;
        }
        let marker = bytes[i + 1];
        // Markers with no payload: padding and the restart markers.
        if marker == 0xFF {
            i += 1;
            continue;
        }
        if marker == 0xD8 || marker == 0xD9 || (0xD0..=0xD7).contains(&marker) {
            i += 2;
            continue;
        }
        let length = u16::from_be_bytes(bytes[i + 2..i + 4].try_into().ok()?) as usize;
        let is_sof = (0xC0..=0xCF).contains(&marker)
            && marker != 0xC4
            && marker != 0xC8
            && marker != 0xCC;
        if is_sof {
            if i + 9 > bytes.len() {
                return None;
            }
            let height = u16::from_be_bytes(bytes[i + 5..i + 7].try_into().ok()?) as u32;
            let width = u16::from_be_bytes(bytes[i + 7..i + 9].try_into().ok()?) as u32;
            return Some((width, height));
        }
        if length < 2 {
            return None;
        }
        i += 2 + length;
    }
    None
}


// ---------------------------------------------------------------- the view




// ---------------------------------------------------------------- the board

/// One strip: a scene's presence on one day, or its absence from all of them.
///
/// A scene split across two days is two strips, each carrying only the shots
/// that fall on that day. That is the case the prototype could not express at
/// all, and it is the ordinary one — a scene rarely finishes in an afternoon.
fn strip(
    p: &Project,
    j: &mut Json,
    scene: Id,
    count: usize,
    elsewhere: &[String],
    shots: &[Id],
) {
    let d = p.doc();
    j.obj()
        .kv("scene", &scene.0.to_string())
        .kv("number", &text(p, scene, f::NUMBER))
        .kv("heading", &d.scene_heading_shown(scene).unwrap_or_default())
        .kv("intExt", &shotlister_engine::insideout::canonical(&text(p, scene, f::INT_EXT)))
        .kv("location", &text(p, scene, f::LOCATION))
        .kv("timeOfDay", &text(p, scene, f::TIME_OF_DAY))
        .ki("count", count as i64);

    match reference(p, scene, f::SEQUENCE) {
        Some(seq) => {
            j.kv("sequence", &text(p, seq, f::TITLE))
                .kv("colour", &text(p, seq, f::COLOUR));
        }
        None => {
            j.key("sequence").null().kv("colour", "");
        }
    }

    // "also Day 2" — the band that tells you this scene is not finished here
    j.key("elsewhere").arr();
    for label in elsewhere {
        j.str(label);
    }
    j.end_arr();

    // the shots this strip stands for, so one can be pulled out onto another day
    // without leaving the board
    j.key("shots").arr();
    for placement in shots {
        let placement = *placement;
        j.obj().kv("placement", &placement.0.to_string());
        j.kv("number", &d.display_number(placement).unwrap_or_default());
        match reference(p, placement, f::SHOT) {
            Some(shot) => {
                j.kv("title", &text(p, shot, f::TITLE))
                    .kv("description", &text(p, shot, f::DESCRIPTION));
            }
            None => {
                j.kv("title", "").kv("description", "");
            }
        }
        j.end_obj();
    }
    j.end_arr();

    // image-first is a switch, not the default, so the frame rides along unused
    // until it is turned on
    let frames = d.scene_key_frames(scene, 1);
    match frames.first().and_then(|mref| reference(p, *mref, f::MEDIA)) {
        Some(media) => {
            j.key("frame").obj();
            j.kv("hash", &text(p, media, f::HASH)).kv(
                "filename",
                &frames
                    .first()
                    .map(|mref| d.media_ref_name(*mref))
                    .unwrap_or_default(),
            );
            if let Some(mref) = frames.first() {
                if let Some(start) = float(p, *mref, f::TRIM_START) {
                    j.kn("trimStart", start);
                }
                if let Some(end) = float(p, *mref, f::TRIM_END) {
                    j.kn("trimEnd", end);
                }
                framing(p, j, *mref);
                arrows(p, j, *mref);
            }
            j.end_obj();
        }
        None => {
            j.key("frame").null();
        }
    }
    j.end_obj();
}

/// One shot in a day's running order, as the shoot-day list draws it.
fn day_shot(p: &Project, j: &mut Json, placement: Id) {
    let d = p.doc();
    j.obj().kv("placement", &placement.0.to_string());
    j.kv("number", &d.display_number(placement).unwrap_or_default());
    match reference(p, placement, f::SCENE) {
        Some(scene) => {
            j.kv("scene", &scene.0.to_string())
                .kv("heading", &d.scene_heading_shown(scene).unwrap_or_default());
        }
        None => {
            j.kv("scene", "").kv("heading", "");
        }
    }
    match reference(p, placement, f::SHOT) {
        Some(shot) => {
            // The words and the picture come from the master when this shot
            // stands in for one, exactly as the table's row does.
            let said = d.described_by(shot);
            j.kv("shot", &shot.0.to_string())
                .kv("title", &text(p, said, f::TITLE))
                .kv("description", &text(p, said, f::DESCRIPTION))
                .kb("struck", d.get(shot).map(|r| r.bool(f::STRUCK)).unwrap_or(false));
            let key_ref = reference(p, said, f::KEY_MEDIA)
                .or_else(|| d.media_refs(said).first().copied());
            match key_ref.and_then(|mref| reference(p, mref, f::MEDIA)) {
                Some(media) => {
                    j.key("frame").obj();
                    j.kv("hash", &text(p, media, f::HASH)).kv(
                        "filename",
                        &key_ref.map(|r| d.media_ref_name(r)).unwrap_or_default(),
                    );
                    if let Some(mref) = key_ref {
                        if let Some(start) = float(p, mref, f::TRIM_START) {
                            j.kn("trimStart", start);
                        }
                        if let Some(end) = float(p, mref, f::TRIM_END) {
                            j.kn("trimEnd", end);
                        }
                        framing(p, j, mref);
                        arrows(p, j, mref);
                    }
                    j.end_obj();
                }
                None => {
                    j.key("frame").null();
                }
            }
        }
        None => {
            j.kv("shot", "")
                .kv("title", "")
                .kv("description", "")
                .kb("struck", false)
                .key("frame")
                .null();
        }
    }
    j.end_obj();
}

/// Days as lanes of strips, plus everything not on a day yet.
fn board(h: &Handle) -> String {
    let p = &h.project;
    let d = p.doc();
    let mut j = Json::new();
    j.obj();

    let on = h.shoot.as_deref();
    j.key("days").arr();
    for day in d.days_in_order() {
        if !d.day_in(day, on) {
            continue;
        }
        j.obj()
            .kv("id", &day.0.to_string())
            .kv("label", &d.day_label(day).unwrap_or_default())
            .kv("date", &d.day_date(day))
            .kv("shoot", &d.day_shoot(day).unwrap_or_default())
            .kv("title", &text(p, day, f::TITLE))
            .ki("count", d.shot_count_on_day(day) as i64)
            .kb("wrapped", d.day_wrapped(day));

        // scenes in the order the day runs them, each carrying only today's shots
        let mut seen: Vec<Id> = Vec::new();
        let mut shots: Vec<Vec<Id>> = Vec::new();
        for placement in d.placements_on_day(day) {
            if let Some(scene) = reference(p, placement, f::SCENE) {
                match seen.iter().position(|s| *s == scene) {
                    Some(at) => shots[at].push(placement),
                    None => {
                        seen.push(scene);
                        shots.push(vec![placement]);
                    }
                }
            }
        }
        j.key("strips").arr();
        for (scene, on_day) in seen.iter().zip(shots.iter()) {
            let elsewhere: Vec<String> = d
                .other_days_of_scene(*scene, day)
                .into_iter()
                .filter_map(|other| d.day_label(other))
                .collect();
            strip(p, &mut j, *scene, on_day.len(), &elsewhere, on_day);
        }
        j.end_arr();

        // **The day as a flat run of shots, in the order it runs them** — the
        // shoot-day list on the phone (2026-09-16). A strip groups by scene
        // and so cannot say that 12C is shot before 8A; this can. Each shot
        // carries whether it has been struck, which on the day means *got
        // it*, and its own frame, so the list reads like the table does.
        j.key("run").arr();
        for placement in d.placements_on_day(day) {
            day_shot(p, &mut j, placement);
        }
        j.end_arr();
        j.end_obj();
    }
    j.end_arr();

    // anything with shots still waiting for a day, in script order
    j.key("unscheduled").arr();
    for scene in d.scenes_in_order() {
        if !d.scene_in(scene, on) {
            continue;
        }
        let waiting: Vec<Id> = d
            .placements_in_scene(scene)
            .into_iter()
            .filter(|pl| reference(p, *pl, f::DAY).is_none())
            .collect();
        if !waiting.is_empty() {
            let elsewhere: Vec<String> = d
                .days_of_scene(scene)
                .into_iter()
                .filter_map(|day| d.day_label(day))
                .collect();
            strip(p, &mut j, scene, waiting.len(), &elsewhere, &waiting);
        }
    }
    j.end_arr();

    j.end_obj();
    j.finish()
}

/// Every list the project keeps, with how many shots lean on each value.
///
/// The count is what makes a list safe to edit: removing a value that nine
/// shots use is a different act from removing one nothing uses, and the screen
/// should be able to say which is which before anything happens.
fn lists(h: &Handle) -> String {
    let d = h.project.doc();
    let mut j = Json::new();
    j.obj().key("lists").arr();
    for field in shotlister_engine::vocab::ALL {
        j.obj()
            .kv("field", field)
            .kb("locked", d.vocabulary_locked(field))
            .key("values")
            .arr();
        let used: Vec<(String, usize)> = d.vocab_usage(field);
        for value in d.vocabulary(field) {
            let count = used
                .iter()
                .find(|(v, _)| v.eq_ignore_ascii_case(&value))
                .map(|(_, n)| *n)
                .unwrap_or(0);
            j.obj().kv("value", &value).ki("used", count as i64).end_obj();
        }
        j.end_arr().end_obj();
    }
    j.end_arr().end_obj();
    j.finish()
}

/// **Every colour a term has been given**, across the standing lists and the
/// project's own columns alike — Ref 55.
///
/// One call rather than one per chip: a table draws hundreds of chips per
/// repaint and each one needs to know whether its word has been given a colour.
/// There are only ever a handful of these, because a term with no stored colour
/// is not in here at all — it falls back to the hash, which is the default and
/// remains the right one.
fn colours(h: &Handle) -> String {
    let d = h.project.doc();
    let mut j = Json::new();
    j.obj().key("colours").arr();
    let custom: Vec<String> = d.custom_columns().into_iter().map(|c| c.field).collect();
    let fields = shotlister_engine::vocab::ALL
        .iter()
        .map(|f| f.to_string())
        .chain(custom);
    for field in fields {
        for (term, hex) in d.term_colours(&field) {
            j.obj()
                .kv("field", &field)
                .kv("term", &term)
                .kv("hex", &hex)
                .end_obj();
        }
    }
    j.end_arr().end_obj();
    j.finish()
}

/// **A draft, read the way the project reads drafts**: the revision asked
/// for (the latest when none is), its screenplay, its pages, and its text
/// as ties point into it (Ref 1553).
///
/// Read with the project's own rules, exactly as the import did, not the
/// plain defaults. A script nobody numbered is numbered by position on the
/// way in (`read_with`), and the scenes it made carry 1, 2, 3; read plainly,
/// the same headings came back with no numbers at all, and every scene on
/// every device said *Not in the script* for a script it was in. Mirrorland,
/// 2026-09-18. His ruling: it works with or without scene numbers.
fn read_draft(
    h: &Handle,
    wanted: Option<shotlister_engine::Id>,
) -> Result<
    (
        shotlister_engine::Revision,
        shotlister_engine::Screenplay,
        shotlister_engine::Paginated,
        shotlister_engine::playties::Draft,
    ),
    String,
> {
    let revision = match wanted {
        Some(id) => h.project.doc().revision(id),
        None => h.project.doc().latest_revision(),
    };
    let Some(revision) = revision else {
        return Err("this project has no script yet".to_string());
    };
    let text = match h.project.read_script(&revision.hash, "txt") {
        Ok(Some(bytes)) => String::from_utf8_lossy(&bytes).to_string(),
        Ok(None) => return Err("that revision's script is not on this Mac yet".to_string()),
        Err(e) => return Err(format!("that revision could not be read: {}", e.message())),
    };
    let detection = h.project.doc().detection();
    let screenplay = shotlister_engine::screenplay::read_with(&text, &detection);
    let laid = shotlister_engine::lay_out(&screenplay);
    let draft = shotlister_engine::playties::Draft::of(&screenplay, &laid);
    Ok((revision, screenplay, laid, draft))
}

fn error(message: &str) -> String {
    let mut j = Json::new();
    j.obj().kv("error", message).end_obj();
    j.finish()
}

fn ok() -> String {
    let mut j = Json::new();
    j.obj().kb("ok", true).end_obj();
    j.finish()
}

// ---------------------------------------------------------------- commands

fn id_from(s: &str) -> Option<Id> {
    s.parse::<u128>().ok().map(Id)
}

/// The trailing `key=value` arguments the export commands take.
///
/// **Why these are named rather than positional.** `print` grew four
/// trailing positions in two days, and a caller that wanted only the last
/// had to pass empty placeholders for everything before it. Keys do not
/// care about order, a new one breaks no existing caller, and a call site
/// reads as what it means. Anything unrecognised is ignored on purpose: an
/// older engine meeting a newer app's option should draw the page it can
/// rather than refuse the whole export over a word it does not know.
struct Options<'a> {
    pairs: Vec<(&'a str, &'a str)>,
}

impl<'a> Options<'a> {
    fn read(parts: impl Iterator<Item = &'a str>) -> Options<'a> {
        Options {
            pairs: parts.filter_map(|part| part.split_once('=')).collect(),
        }
    }

    fn get(&self, key: &str) -> Option<&'a str> {
        self.pairs
            .iter()
            .find(|(k, _)| *k == key)
            .map(|(_, v)| *v)
            .filter(|v| !v.is_empty())
    }

    fn number(&self, key: &str) -> Option<f64> {
        self.get(key).and_then(|v| v.parse().ok())
    }

    fn list(&self, key: &str) -> Option<Vec<String>> {
        self.get(key)
            .map(|v| v.split(',').filter(|s| !s.is_empty()).map(String::from).collect())
    }

    fn ids(&self, key: &str) -> Vec<Id> {
        self.get(key)
            .map(|v| v.split(',').filter_map(id_from).collect())
            .unwrap_or_default()
    }

    /// What this export is *about*, as a query.
    ///
    /// `scenes=` and `day=` each narrow from the whole project rather than
    /// from the live filters — a scene's own PDF should not go missing shots
    /// because something is typed in the search box, and one day's package
    /// should hold that whole day. Given neither, the export follows what is
    /// on screen, which is what the share page and the printed pages have
    /// always done.
    ///
    /// **A day's page is in the day's running order.** His ask, 2026-09-19:
    /// *"I should be able to export a shot list in the order that they are
    /// in inside the schedule (ordered inside a day, not just in days)."*
    /// Until then a day's export was grouped by scene — story order with
    /// the day as a filter — so the order he had arranged on the board
    /// never reached paper. Grouped by day, the page reads the board.
    fn query_narrowing(&self, h: &Handle) -> Result<Query, String> {
        if let Some(arrange) = self.get("arrange") {
            return self.arranged(h, arrange);
        }
        let scenes = self.ids("scenes");
        match (scenes.is_empty(), self.get("day")) {
            (true, None) => Ok(h.query()),
            (false, None) => Ok(Query::grouped_by(GroupBy::Scene).for_scenes(scenes)),
            (true, Some("unscheduled")) => Ok(Query::grouped_by(GroupBy::Day).unscheduled()),
            (true, Some(day)) => match id_from(day) {
                Some(day) => Ok(Query::grouped_by(GroupBy::Day).on_day(day)),
                None => Err(error("that is not a shoot day this project has")),
            },
            // Both at once has no honest meaning — a day already says which
            // shots, and a scene list says a different set. Refusing beats
            // silently picking one.
            (false, Some(_)) => Err(error("ask for scenes or a day, not both")),
        }
    }

    /// **The export box's own narrowing** (2026-10-15), asked with
    /// `arrange=table|script|schedule`:
    ///
    /// - `filter=table` keeps the Table's filter (search, facets, day,
    ///   sequence, shoot, cut shots hidden); anything else starts from the
    ///   whole project. The same rule for a scene pick and a day's file, so
    ///   nothing on screen is silently ignored by one and kept by another.
    /// - `arrange=table` reads the list the way the Table does — its grouping
    ///   and its sort; `script` is story order, scene by scene; `schedule`
    ///   is shooting order, day by day, the unscheduled last.
    /// - `days=<id>,…,unscheduled` narrows a schedule to the days picked.
    ///   The Days picker then governs which days, so a day the Table filter
    ///   names is not applied on top of it.
    fn arranged(&self, h: &Handle, arrange: &str) -> Result<Query, String> {
        let mut asked = if self.get("filter") == Some("table") {
            h.asked()
        } else {
            view::Asked::default()
        };
        let table_sort = h.sort.clone();
        let table_group = h.group_by;
        asked.sort = None;
        asked.group_by = GroupBy::Scene;
        let mut q = asked.query();
        let scenes = self.ids("scenes");
        let day = self.get("day");
        if !scenes.is_empty() && day.is_some() {
            return Err(error("ask for scenes or a day, not both"));
        }
        if let Some(day) = day {
            q.day = if day == "unscheduled" {
                shotlister_engine::query::DayFilter::Unscheduled
            } else {
                match id_from(day) {
                    Some(day) => shotlister_engine::query::DayFilter::On(day),
                    None => return Err(error("that is not a shoot day this project has")),
                }
            };
            q.group_by = GroupBy::Day;
            return Ok(q);
        }
        if !scenes.is_empty() {
            q = q.for_scenes(scenes);
        }
        match arrange {
            "schedule" => {
                q.group_by = GroupBy::Day;
                if let Some(list) = self.get("days") {
                    let picked: Vec<&str> = list.split(',').filter(|s| !s.is_empty()).collect();
                    let days: Vec<Id> = picked.iter().filter_map(|d| id_from(d)).collect();
                    q.days = Some((days, picked.contains(&"unscheduled")));
                    q.day = shotlister_engine::query::DayFilter::Any;
                }
            }
            "script" => q.group_by = GroupBy::Scene,
            _ => {
                // A scene pick stays scene by scene; the Table's shooting
                // order is its grouping, and any other sort reads inside it.
                q.group_by = if scenes_given(self) { GroupBy::Scene } else { table_group };
                if let Some((column, descending)) = table_sort {
                    q = q.sorted_by(&column, descending);
                }
            }
        }
        Ok(q)
    }
}

fn scenes_given(options: &Options) -> bool {
    !options.ids("scenes").is_empty()
}

/// One place to refuse a change, so a project written by a newer Studio
/// cannot be edited by an older one through some command nobody thought about.
fn writable(h: &Handle) -> Option<String> {
    h.project
        .is_read_only()
        .then(|| error("This project is read only — a newer Studio wrote it."))
}


/// One value onto one field of one shot, routed by what the field is — the
/// single place a typed string becomes a stored value, shared by `set` and
/// `setmany` so a paste onto forty rows cannot drift from a keystroke onto
/// one. Returns the error reply if the value is refused.
fn set_field(d: &mut Doc, id: Id, field: &str, value: &str) -> Option<String> {
    // **The three fields a slug line is made of, on a scene, go through the
    // door a person types through** — Ref 257's follow-up. Editing where a
    // scene happens should move its heading; a draft conforming a time of day
    // must not. `set_scene_field` is the first; `set` is the second, and
    // everything that conforms calls that.
    if [f::INT_EXT, f::LOCATION, f::TIME_OF_DAY].contains(&field)
        && d.get(id).map(|r| r.kind == Kind::Scene) == Some(true)
    {
        d.set_scene_field(id, field, value);
        return None;
    }
    // **The film's mark is three fields that only make sense together**, and
    // there is one door onto them — `setmark`, which refuses a colour that is
    // not a colour and keeps the three in step. A plain `set` here could write
    // an outline with no colour, or a colour nobody could draw, so it does not.
    if [f::MARK_PATH, f::MARK_COLOUR, f::MARK_SOURCE].contains(&field) {
        return Some(error("the film's icon is set with setmark"));
    }
    // **The project record's facts have one door too** — `recordfacts`, the
    // console's mirror. And once a film takes its facts from the record, its
    // director, producer, client and agency are the record's: a plain `set`
    // from any screen is turned away, so the film never drifts from the
    // record again. The place to change one is Projects Console.
    // The kit is the spec sheet's word, set only by `recordkit` (Ref 1627).
    if field == shotlister_engine::kit::KIT {
        return Some(error("the film's kit is set with recordkit, from its spec sheet"));
    }
    if [f::FACTS_SOURCE, f::RECORD_TITLE].contains(&field) {
        return Some(error("the film's record facts are set with recordfacts"));
    }
    if shotlister_engine::recordfacts::owned(field)
        && d.project_id() == Some(id)
        && d.facts_from_record()
    {
        return Some(error("that comes from the project record — change it in Projects Console"));
    }
    match field {

                f::SIZE | f::MOVEMENT | f::LENS | f::SUPPORT | f::PRIORITY => {
                    d.set_vocab_field(id, field, value);
                }
                // where a zoom is set, in mm — a number, or nothing
                f::FOCAL => match value.trim().trim_end_matches("mm").trim() {
                    "" => d.set(id, field, Value::Null),
                    v => match v.parse::<f64>() {
                        Ok(mm) if mm.is_finite() && mm > 0.0 => d.set(id, field, Value::Float(mm)),
                        _ => return Some(error("a focal length reads like 35 or 35mm")),
                    },
                },
                // Point of view holds more than one, and was being written as a
                // single value while being read as a list — so it could be set
                // and would then never appear.
                f::ANGLE | f::TAGS | f::POV | f::MODIFIERS | f::LENS_FILTERS => {
                    let items: Vec<&str> =
                        value.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
                    d.set_vocab_list(id, field, &items);
                }
                // typed, not chosen — he asked for a field he can put 1.66 in
                f::ASPECT_RATIO => match shotlister_engine::ratio::parse(value) {
                    Some(r) => d.set(id, field, Value::Float(r)),
                    None => return Some(error("an aspect ratio reads like 2.39, 1.85:1 or 9:16")),
                },
                // a reference field is given an id, not a word
                f::SEQUENCE | f::UNIT => match id_from(value) {
                    Some(target) => d.set(id, field, target),
                    None if value.is_empty() => {
                        d.set(id, field, Value::Null)
                    }
                    None => return Some(error("that is not something this project has")),
                },
                _ => {
                    // A custom column knows its own shape, and the shape says
                    // how typed text becomes a value: single teaches the
                    // project like lens does, multi splits like angle does,
                    // check reads as a flag — anything else is text.
                    match d.custom_column_kind(field).as_deref() {
                        Some("single") => {
                            d.set_vocab_field(id, field, value);
                        }
                        Some("multi") => {
                            let items: Vec<&str> = value
                                .split(',')
                                .map(|s| s.trim())
                                .filter(|s| !s.is_empty())
                                .collect();
                            d.set_vocab_list(id, field, &items);
                        }
                        Some("check") => {
                            let on = !value.is_empty() && value != "0" && value != "false";
                            d.set(id, field, Value::Bool(on));
                        }
                        _ => {
                            d.set(id, field, value);
                        }
                    }
                }
    }
    None
}

/// Tab-delimited in, JSON out. Both ends of this boundary are ours, so a format
/// that cannot be mis-escaped beats one that can.
fn dispatch(h: &mut Handle, line: &str) -> String {
    let mut parts = line.split('\t');
    let cmd = parts.next().unwrap_or("");
    match cmd {
        "view" => view(h),

        // The diagram's own commands, kept in `diagram.rs`.
        c if c.starts_with("diagram") || c.starts_with("scenediagram") => diagram::command(h, c, parts),

        // Versions — the film as it stood at a moment — kept in `versions.rs`.
        c if versions::is_ours(c) => versions::command(h, c, parts),

        "group" => {
            h.group_by = match parts.next().unwrap_or("scene") {
                "day" => GroupBy::Day,
                "sequence" => GroupBy::Sequence,
                // one flat run of shots — the engine always knew how
                "flat" | "none" => GroupBy::Flat,
                _ => GroupBy::Scene,
            };
            view(h)
        }

        // set <shotId> <field> <value>
        "set" => {
            let (id, field, value) = (parts.next(), parts.next(), parts.next().unwrap_or(""));
            let id = match id.and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            let field = match field {
                Some(f) if !f.is_empty() => f,
                _ => return error("no field given"),
            };
            if let Some(problem) = writable(h) {
                return problem;
            }
            // **An edit to a shot standing in for a master edits the master.**
            // That is the whole of "tied together with auto update": there is
            // one description, and it does not matter which of its faces you
            // type into. Only the describing fields travel — its number, its
            // scene and whether it is cut are this shot's own.
            let id = if shotlister_engine::Doc::DESCRIBING.contains(&field) {
                h.project.doc().described_by(id)
            } else {
                id
            };
            if let Some(problem) = set_field(h.project.doc_mut(), id, field, value) {
                return problem;
            }
            view(h)
        }

        // scriptpdf <revisionId> [<base64>] — the PDF a revision came from,
        // read or kept.
        //
        // **A revision should keep the file it came from.** It kept the text
        // and threw the pages away, so the only way to read the script as it
        // was printed was our own drawing of it. His call, 2026-08-22: the
        // button should open the actual file in Preview. It is stored beside
        // the text, under the same hash, addressed by contents like everything
        // else — so the same draft imported twice is one file.
        "scriptpdf" => {
            let Some(revision) = parts.next().and_then(id_from) else {
                return error("that revision id is not one this project has");
            };
            let Some(hash) = h.project.doc().revision(revision).map(|r| r.hash.clone())
            else {
                return error("that revision id is not one this project has");
            };
            match parts.next() {
                Some(payload) if !payload.is_empty() => {
                    if let Some(problem) = writable(h) {
                        return problem;
                    }
                    let Some(bytes) = b64::decode(payload) else {
                        return error("nothing decodable in that file");
                    };
                    if let Err(e) = h.project.write_script(&hash, "pdf", &bytes) {
                        return error(&e.message());
                    }
                    "{\"ok\":true}".to_string()
                }
                _ => match h.project.read_script(&hash, "pdf") {
                    Ok(Some(bytes)) => {
                        let mut j = Json::new();
                        j.obj();
                        j.kv("data", &b64::encode(&bytes));
                        j.end_obj();
                        j.finish()
                    }
                    // Not an error: a revision taken in before the pages were
                    // kept simply has none, and the shell has somewhere else to
                    // go when that is so.
                    Ok(None) => "{\"data\":\"\"}".to_string(),
                    Err(e) => error(&e.message()),
                },
            }
        }

        // sortscenes — put the scenes back in the order their numbers say.
        // Asked for from the scene list's own menu, never automatic.
        "sortscenes" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            h.project.doc_mut().sort_scenes_by_number();
            view(h)
        }

        // settletimes — turn CONTINUED and LATER into the time they point at,
        // for a film imported before Ref 257 was fixed.
        "settletimes" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            h.project.doc_mut().settle_scene_times();
            view(h)
        }

        // master <shot> <0|1> — make a shot one that others may stand in for,
        // or stop it being one. Stopping cuts its followers loose *whole*: what
        // they were showing is copied onto them first.
        "master" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(shot) = parts.next().and_then(id_from) else {
                return error("that shot id is not one this project has");
            };
            let on = parts.next().unwrap_or("1") != "0";
            h.project.doc_mut().set_master(shot, on);
            view(h)
        }

        // link <shot> <master|none> — point a shot at a master, or cut it loose.
        "link" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(shot) = parts.next().and_then(id_from) else {
                return error("that shot id is not one this project has");
            };
            let target = parts.next().unwrap_or("");
            let master = if target.is_empty() || target == "none" {
                None
            } else {
                match id_from(target) {
                    Some(id) => Some(id),
                    None => return error("that is not a shot this project has"),
                }
            };
            h.project.doc_mut().link_shot(shot, master);
            view(h)
        }

        // clearcells <field=id,id|field=id,id> — empties a rectangle of
        // cells in one transaction: Delete over a drag-selected range is one
        // thing to take back, however many columns it crossed.
        "clearcells" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let spec = parts.next().unwrap_or("");
            let mut groups: Vec<(String, Vec<Id>)> = Vec::new();
            for group in spec.split('|') {
                let mut halves = group.splitn(2, '=');
                let field = halves.next().unwrap_or("").trim().to_string();
                let ids: Vec<Id> = halves
                    .next()
                    .unwrap_or("")
                    .split(',')
                    .filter_map(|s| id_from(s.trim()))
                    .collect();
                if !field.is_empty() && !ids.is_empty() {
                    groups.push((field, ids));
                }
            }
            if groups.is_empty() {
                return error("nothing to clear");
            }
            let d = h.project.doc_mut();
            let tx = d.begin("Clear cells");
            let mut problem = None;
            'outer: for (field, ids) in &groups {
                for id in ids {
                    if let Some(p) = set_field(d, *id, field, "") {
                        problem = Some(p);
                        break 'outer;
                    }
                }
            }
            d.end(tx);
            if let Some(p) = problem {
                return p;
            }
            view(h)
        }

        // setmany <shotId[,shotId…]> <field> <value> — one value onto many
        // shots, one transaction: a paste onto a selection is one thing to
        // take back, the same law as delete and strike.
        "setmany" => {
            let ids: Vec<Id> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| id_from(s.trim()))
                .collect();
            if ids.is_empty() {
                return error("that shot id is not one this project has");
            }
            let field = match parts.next() {
                Some(f) if !f.is_empty() => f,
                _ => return error("no field given"),
            };
            let value = parts.next().unwrap_or("");
            if let Some(problem) = writable(h) {
                return problem;
            }
            let d = h.project.doc_mut();
            let label = if ids.len() == 1 {
                "Change shot".to_string()
            } else {
                format!("Change {} shots", ids.len())
            };
            let tx = d.begin(&label);
            let mut problem = None;
            for id in &ids {
                if let Some(p) = set_field(d, *id, field, value) {
                    problem = Some(p);
                    break;
                }
            }
            d.end(tx);
            if let Some(p) = problem {
                return p;
            }
            view(h)
        }

        // undoopen <label> … undoclose — whatever is written between the two
        // is one step to take back. A paste of a block is several `setmany`
        // calls (the engine sets one value across many shots, not many
        // values at once) and still one ⌘Z. A command inside joins it, so
        // the two can wrap anything. `undoclose` with nothing open does
        // nothing.
        "undoopen" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let label = parts.next().unwrap_or("Change");
            h.project.doc_mut().begin(label);
            view(h)
        }
        "undoclose" => {
            h.project.doc_mut().end(true);
            view(h)
        }

        // strike <shotId[,shotId…]> <0|1> — one or many, one transaction.
        "strike" => {
            let ids: Vec<Id> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| id_from(s.trim()))
                .collect();
            if ids.is_empty() {
                return error("that shot id is not one this project has");
            }
            let on = parts.next().unwrap_or("1") != "0";
            h.project.doc_mut().strike_many(&ids, on);
            view(h)
        }

        // vocab <field> — the project's list, for the dropdown
        // docstyle <class> <size> <face> <case>  |  docstyle reset
        //
        // **How the document page is set.** One class at a time, folded into
        // whatever is already there — the app never writes the stored string
        // itself, which is what keeps its shape a private matter between
        // `docstyle` and itself.
        //
        // Goes through the ordinary `set`, so changing the page's type undoes,
        // saves and syncs like any other edit.
        "docstyle" => {
            if h.project.is_read_only() {
                return error("This project is read only — a newer Studio wrote it.");
            }
            let Some(project) = h.project.doc().project_id() else {
                return error("this file has no project record");
            };
            let now = shotlister_engine::docstyle::of(h.project.doc(), project);
            let what = parts.next().unwrap_or("");
            let next = if what == "reset" {
                shotlister_engine::docstyle::Style::standard_style()
            } else if what == "apply" {
                // **A whole page in one word.** How a default set on one film
                // reaches another: the app hands back the string this engine
                // gave it, having never looked inside.
                shotlister_engine::docstyle::Style::decode(parts.next().unwrap_or(""))
            } else {
                use shotlister_engine::docstyle::{Case, Class, Face, Setting};
                let Some(class) = Class::read(what) else {
                    return error("that is not a kind of words on the page");
                };
                let Ok(size) = parts.next().unwrap_or("").parse::<f64>() else {
                    return error("that is not a size");
                };
                if !(4.0..=48.0).contains(&size) {
                    return error("a size has to be between 4 and 48");
                }
                let Some(face) = Face::read(parts.next().unwrap_or("")) else {
                    return error("that is not one of the faces");
                };
                let Some(case) = Case::read(parts.next().unwrap_or("")) else {
                    return error("that is not one of the cases");
                };
                // **The colour is optional on the wire.** A shell that has not
                // learned about it yet keeps the ink the class has always had
                // rather than being told, silently, that it wanted black.
                let said = parts.next().unwrap_or("");
                let colour = if said.is_empty() {
                    shotlister_engine::docstyle::standard(class).colour
                } else {
                    match shotlister_engine::docstyle::Colour::read(said) {
                        Some(c) => c,
                        None => return error("that is not a colour"),
                    }
                };
                now.with(class, Setting { size, face, case, colour })
            };
            h.project.doc_mut().set(
                project,
                shotlister_engine::doc::f::DOC_STYLE,
                Value::text(next.encode()),
            );
            view(h)
        }

        // setmark <path> <colour> <source> — the film's own icon and colour.
        //
        // His call, 2026-09-11: the pair belongs to the film, not to a Mac, so
        // it travels with the film through the sync that already carries the
        // shots and the photographs. See `shotlister_engine::mark`.
        //
        // `source` is `console` (mirrored off his Notion row, and refreshed
        // whenever it changes) or `hand` (his own choice, which nothing
        // automatic overwrites). An empty path clears the mark and the source
        // with it.
        //
        // **One door, so there is one place to refuse a bad colour** — a plain
        // `set` onto these three fields is turned away below for the same
        // reason.
        "setmark" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().project_id().is_none() {
                return error("this file has no project record");
            }
            let path = parts.next().unwrap_or("").trim().to_string();
            let colour = parts.next().unwrap_or("").trim().to_string();
            let source = shotlister_engine::mark::Source::read(parts.next().unwrap_or(""));
            if path.is_empty() {
                h.project.doc_mut().set_mark(None, source);
                return view(h);
            }
            if shotlister_engine::mark::colour(&colour).is_none() {
                return error("a colour reads like #D44C47");
            }
            if shotlister_engine::mark::outline(&path).is_none() {
                return error("that is not an icon outline");
            }
            let mark = shotlister_engine::mark::Mark { path, colour };
            h.project.doc_mut().set_mark(Some(&mark), source);
            view(h)
        }

        // recordfacts <word> <value> [<word> <value>…] — the project record's
        // facts, mirrored into the film (one-record plan, 2026-10-05). The
        // words are `title` (the name the film is shown by), `director`,
        // `producer`, `client`, `agency`; only those given are written, and
        // the film then takes its facts from the record (`facts_source`
        // `console`). `recordfacts none` lets go: the film keeps the words
        // it has and owns them again. Touches nothing but the project
        // record. See `shotlister_engine::recordfacts`.
        "recordfacts" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().project_id().is_none() {
                return error("this file has no project record");
            }
            let rest: Vec<String> = parts.by_ref().map(|p| p.to_string()).collect();
            if rest.len() == 1 && rest[0].trim() == "none" {
                h.project.doc_mut().let_go_of_record_facts();
                return view(h);
            }
            if rest.is_empty() || rest.len() % 2 != 0 {
                return error("recordfacts takes a word and a value, in pairs");
            }
            let given: Vec<(String, String)> =
                rest.chunks(2).map(|pair| (pair[0].clone(), pair[1].clone())).collect();
            if let Err(why) = h.project.doc_mut().take_record_facts(&given) {
                return error(&why);
            }
            view(h)
        }

        // card <json> — the project's card, laid over the film for this
        // session (stage 5 step 4): its facts, mark and kind (from Type) are
        // shown instead of the film's own; nothing is written, so a read-only
        // film takes one too. `card none` takes it off. See
        // `shotlister_engine::card`. Answers the view.
        "card" => {
            let said = parts.next().unwrap_or("").trim().to_string();
            if said == "none" || said.is_empty() {
                h.project.doc_mut().set_card(None);
                return view(h);
            }
            match shotlister_engine::card::Card::read(&said) {
                Some(card) => {
                    h.project.doc_mut().set_card(Some(card));
                    view(h)
                }
                None => error("that is not a card"),
            }
        }

        // recordkit <json> — the film's kit off its Camera Spec Sheets (Ref
        // 1627): each shoot's lenses as picks and its cameras as name and
        // body, as the portal's kit door gives them. Lenses go on the Lens
        // list, cameras get their bodies; nothing is removed, and no undo
        // step is made (it is the sheet's word, not his edit). `recordkit
        // none` lets go of the kit and keeps the list and the cameras. See
        // `shotlister_engine::kit`. Answers the view.
        "recordkit" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().project_id().is_none() {
                return error("this file has no project record");
            }
            let said = parts.next().unwrap_or("").trim().to_string();
            if said == "none" {
                h.project.doc_mut().let_go_of_kit();
                return view(h);
            }
            if let Err(why) = h.project.doc_mut().take_kit(&said) {
                return error(&why);
            }
            view(h)
        }

        // kitmode off|ask|follow — the film's Spec Sheet switch (2026-10-13).
        // Off, nothing flows between the sheet and the film; Ask, the shells
        // show what changed and take it on a click; Follow, they take it on
        // open and every few minutes. Undoable. See `shotlister_engine::kit`.
        "kitmode" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().project_id().is_none() {
                return error("this file has no project record");
            }
            let said = parts.next().unwrap_or("").trim();
            if !["off", "ask", "follow"].contains(&said) {
                return error("the spec sheet switch is off, ask or follow");
            }
            h.project.doc_mut().set_kit_mode(shotlister_engine::kit::KitMode::read(said));
            view(h)
        }

        // frame <name> — **the frame Studio draws at** (piece E): one of the
        // project's frames off its spec sheet, by name. One undo step; its
        // ratio also goes into the film's own `aspect_ratio` for readers with
        // no card. Refused when the card brings no frames or none is called
        // that. See `shotlister_engine::frames`. Answers the view.
        "frame" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().frames().is_none() {
                return error("this project's frames come from its spec sheet, which is not here");
            }
            let said = parts.next().unwrap_or("").trim().to_string();
            if !h.project.doc_mut().pick_frame(&said) {
                return error("this project has no frame called that");
            }
            view(h)
        }

        // frameguides on|off — show the project's other frames as guide
        // lines (piece E). One undo step. Answers the view.
        "frameguides" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let on = match parts.next().unwrap_or("").trim() {
                "on" => true,
                "off" => false,
                _ => return error("frame guides are on or off"),
            };
            if !h.project.doc_mut().set_frame_guides(on) {
                return error("this file has no project record");
            }
            view(h)
        }

        // ---- a commercial kind of film ---------------------------------------
        //
        // Four doors, and `crate::kind` in the engine owns what they mean.
        // A commercial's Kind, title, video and audio all go through the plain
        // `set` above like any other field; these are the things a `set`
        // cannot say.

        // kind film|commercial — what sort of film this is. Undoable; changes
        // no other record.
        "kind" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().project_id().is_none() {
                return error("this file has no project record");
            }
            let said = parts.next().unwrap_or("").trim();
            if !["film", "commercial"].contains(&said) {
                return error("a kind is film or commercial");
            }
            h.project.doc_mut().set_kind(shotlister_engine::FilmKind::read(said));
            view(h)
        }

        // addtitled <title> [<field> <value>]… — a scene made from a title,
        // the commercial way: it takes the next whole number and lands last.
        // The pairs are `addscene`'s pairs; `place` points it at a location.
        // One transaction, like `addscene`, for the same reason.
        "addtitled" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let title = parts.next().unwrap_or("").trim().to_string();
            let extras: Vec<(String, String)> = {
                let rest: Vec<&str> = parts.collect();
                rest.chunks(2)
                    .filter(|pair| pair.len() == 2 && !pair[1].trim().is_empty())
                    .map(|pair| (pair[0].to_string(), pair[1].to_string()))
                    .collect()
            };
            if title.is_empty() && extras.is_empty() {
                return error("a scene needs a title");
            }
            let d = h.project.doc_mut();
            let tx = d.begin("Add scene");
            let scene = d.create_scene_titled(&title);
            let mut problem = None;
            for (field, value) in &extras {
                match field.as_str() {
                    "place" => match id_from(value) {
                        Some(place) => {
                            d.add_scene_location(scene, place);
                        }
                        None => {
                            problem = Some(error("that is not a location this project has"));
                        }
                    },
                    _ => problem = set_field(d, scene, field, value),
                }
                if problem.is_some() {
                    break;
                }
            }
            d.end(tx);
            if let Some(p) = problem {
                return p;
            }
            view(h)
        }

        // renumber — every scene numbered by its place in the list, 1 to n.
        // A person's decision the shell has already said the cost of. Answers
        // how many changed, then the shell asks for its view.
        "renumber" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let changed = h.project.doc_mut().renumber_in_order();
            let mut j = Json::new();
            j.obj().ki("changed", changed as i64).end_obj();
            j.finish()
        }

        // setscript <section|""> <text> [append=1] — the section's script
        // as text (the film's own when no section). Ties re-anchor by their
        // words; the reply says how many kept and how many lost. Tabs in the
        // text are carried as \x1f. `newsection=<title>` makes the section
        // first, in the same step.
        "setscript" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let who = parts.next().unwrap_or("").to_string();
            let text = parts.next().unwrap_or("").replace('\u{1f}', "\t");
            let options = Options::read(parts);
            let d = h.project.doc_mut();
            let tx = d.begin("Edit script");
            let section = match options.get("newsection").map(str::trim) {
                Some(title) if !title.is_empty() => Some(d.create_sequence(title)),
                _ => if who.is_empty() { None } else { id_from(&who) },
            };
            // `av=1` / `av=0`: the layout an empty script takes from this
            // paste. A script with words in it keeps its own.
            let av = options.get("av").map(|v| v.trim() == "1");
            let (kept, lost) = if options.get("append").is_some() {
                d.add_to_script(section, &text, av)
            } else {
                d.set_av_script(section, &text)
            };
            d.end(tx);
            let mut j = Json::new();
            j.obj().ki("kept", kept as i64).ki("lost", lost as i64).end_obj();
            j.finish()
        }

        // scriptlayout <section|""> <av|plain> — the script's words laid out
        // as Video beside Audio, or as plain text. Ties follow the words.
        "scriptlayout" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let who = parts.next().unwrap_or("").to_string();
            let av = parts.next().unwrap_or("").trim() == "av";
            let section = if who.is_empty() { None } else { id_from(&who) };
            let (kept, lost) = h.project.doc_mut().set_script_av(section, av);
            let mut j = Json::new();
            j.obj().ki("kept", kept as i64).ki("lost", lost as i64).end_obj();
            j.finish()
        }

        "vocab" => {
            let field = parts.next().unwrap_or("");
            let mut j = Json::new();
            j.obj().key("values").arr();
            for v in h.project.doc().vocabulary(field) {
                j.str(&v);
            }
            j.end_arr().end_obj();
            j.finish()
        }

        // paste <shotId> <width> <height> <ext> <base64> [kind] [seconds] [name] [source]
        // The app has already sized and encoded the picture — that is a shell's
        // job. All the engine is told is what it is and what it hashes to.
        // A moving file says so: kind "video" or "gif", and a video carries
        // its length. The bytes stored under the ext are the medium itself;
        // a video's poster frame arrives separately through `poster`.
        "paste" => {
            if h.project.is_read_only() {
                return error("This project is read only — a newer Studio wrote it.");
            }
            let shot = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            let width: u32 = parts.next().unwrap_or("0").parse().unwrap_or(0);
            let height: u32 = parts.next().unwrap_or("0").parse().unwrap_or(0);
            let ext = parts.next().unwrap_or("png").to_string();
            let bytes = match parts.next().and_then(b64::decode) {
                Some(b) if !b.is_empty() => b,
                _ => return error("nothing decodable in the paste"),
            };

            let hash = sha256(&bytes);
            let hex = hash.to_hex();
            // stored by what is in it, so the same frame on ten shots is one file
            if let Err(e) = h.project.write_proxy(&hex, &ext, &bytes) {
                return error(&e.message());
            }
            // An explicit kind is honoured — including "other", which is the
            // right answer for a PDF and was being coerced to "image" by a
            // filter meant only to catch a missing argument. With nothing
            // given, the name decides; a clipboard paste with no name at all
            // is a picture, which is what a clipboard paste in fact is.
            let said = parts.next().unwrap_or("").trim();
            let kind = if said.is_empty() {
                MediaKind::Image
            } else {
                MediaKind::parse(said)
            };
            let seconds: f64 = parts.next().unwrap_or("0").parse().unwrap_or(0.0);
            // A file keeps the name it came with when it has one. A screenshot
            // pasted from the clipboard has none, and "pasted.png" is honest
            // for that — but a permit dropped on a scene must not be renamed
            // to it, which is exactly what a scene's attachments are for.
            let given = parts.next().unwrap_or("").trim();
            let filename = if given.is_empty() {
                format!("pasted.{ext}")
            } else {
                // **And its extension says what its bytes are** — Ref 193. A
                // photograph off the phone arrives called `IMG_4523.HEIC` and
                // is re-encoded to JPEG on the way in; keeping the promise of
                // HEIC on the name is how JPEG bytes ended up in Google Drive
                // wearing a `.heic`. The stem — the part his rule is about —
                // is untouched.
                shotlister_engine::name_with_extension(given, &ext)
            };
            // A named file's own extension is better evidence than a caller's
            // default: a shell that forgot to say "other" still cannot turn a
            // PDF into a picture.
            let kind = if said.is_empty() && !given.is_empty() {
                MediaKind::guess_from_name(&filename)
            } else {
                kind
            };
            let media = h.project.doc_mut().add_media(
                hash,
                kind,
                width,
                height,
                bytes.len() as u64,
                &filename,
            );
            if seconds > 0.0 {
                h.project.doc_mut().set_media_duration(media, seconds);
            }
            // **What this was made from, when it is a smaller copy of
            // something** — Ref 211. A shell that shrank a clip on the way in
            // says so here, and the next time that same clip arrives the
            // project recognises it before any encoder runs. Nothing to say
            // for a file kept exactly as it came: its own name is the answer,
            // and recording it would only be the hash twice.
            if let Some(source) = parts.next().map(str::trim).filter(|s| !s.is_empty()) {
                if let Some(from) = Hash256::from_hex(source) {
                    if from != hash {
                        h.project.doc_mut().remember_media_source(media, from);
                    }
                }
            }
            let mref = h.project.doc_mut().attach_media(shot, media, "");
            // **This use wears the name it arrived with.** The file keeps the
            // name it was first stored under, which is the right answer for the
            // file; it is the wrong answer for a second use of it, because the
            // caller has just decided what *this* one should be called — a
            // location renames its photographs, a mood board does not (Ref 273).
            // Without this line the second use silently wore the first's name.
            h.project.doc_mut().set_media_ref_name(mref, &filename);
            // Only a shot has a lead frame. The same command attaches a file
            // to a scene (the Notes tab's attachments), and stamping
            // `key_media` on a scene would invent a frame nothing draws.
            //
            // **Unless somebody has already said which frame they want.** A
            // new picture taking over the lead frame is right — dropping a clip
            // on a shot should show the clip — but it used to happen even when
            // a person had deliberately chosen one, which silently undid their
            // decision with no way back. `key_frame_was_chosen` tells a
            // decision from a shot merely falling into its first frame.
            let is_shot = h.project.doc().get(shot).map(|r| r.kind.clone()) == Some(Kind::Shot);
            let chosen = h.project.doc().key_frame_was_chosen(shot);
            if is_shot && !chosen {
                h.project.doc_mut().set(shot, f::KEY_MEDIA, mref);
            }
            view(h)
        }

        // poster <hash> <base64 jpeg> — the still that stands for a movie
        // wherever a picture is drawn. Stored beside the movie under the same
        // hash with the jpg extension, so a reader asks for the medium and
        // falls back to the poster.
        //
        // **JPEG since 2026-09-15.** It was PNG, and a PNG of a video frame
        // at 1600 wide is 1.6 MB where the JPEG is 200 KB — Call Her Back was
        // carrying 50 MB of posters for 29 clips. A poster written now
        // retires the PNG one under the same name, so a clip never has two
        // stills and the readers, which take either, find the new one.
        "poster" => {
            let hex = parts.next().unwrap_or("");
            if hex.is_empty() {
                return error("no hash given");
            }
            let bytes = match parts.next().and_then(b64::decode) {
                Some(b) if !b.is_empty() => b,
                _ => return error("nothing decodable in the poster"),
            };
            if let Err(e) = h.project.write_proxy(hex, "jpg", &bytes) {
                return error(&e.message());
            }
            let _ = h.project.remove_proxy(hex, "png");
            ok()
        }

        // reclip <mediaId> <width> <height> <ext> <base64> — the same clip,
        // made smaller after the fact. The record keeps its identity and every
        // use of it; only its bytes change (`Doc::replace_media_bytes`). The
        // old movie, its poster and its strips are removed here and their
        // names answered, so the shell can tell the relay the same. **The
        // poster is the shell's to carry across**: it read the old one before
        // asking, and writes it again under the new name with `poster`.
        "reclip" => {
            if h.project.is_read_only() {
                return error("This project is read only — a newer Studio wrote it.");
            }
            let media = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that media id is not one this project has"),
            };
            let width: u32 = parts.next().unwrap_or("0").parse().unwrap_or(0);
            let height: u32 = parts.next().unwrap_or("0").parse().unwrap_or(0);
            let ext = parts.next().unwrap_or("mp4").trim().to_string();
            let bytes = match parts.next().and_then(b64::decode) {
                Some(b) if !b.is_empty() => b,
                _ => return error("nothing decodable in the clip"),
            };
            let moving = h
                .project
                .doc()
                .media_kind(media)
                .map(|k| k.is_moving())
                .unwrap_or(false);
            if !moving {
                return error("only a clip can be re-encoded in place");
            }
            let hash = sha256(&bytes);
            let hex = hash.to_hex();
            if let Err(e) = h.project.write_proxy(&hex, &ext, &bytes) {
                return error(&e.message());
            }
            let before = match h.project.doc_mut().replace_media_bytes(
                media,
                hash,
                width,
                height,
                bytes.len() as u64,
            ) {
                Some(before) => before,
                None => return error("that media id is not one this project has"),
            };
            // The same bytes again — an encoder that changed nothing — must
            // not remove what it just wrote.
            let gone = if before == hex {
                Vec::new()
            } else {
                h.project.remove_stored(&before)
            };
            let mut j = Json::new();
            j.obj().kv("hash", &hex).kv("before", &before).key("gone").arr();
            for name in gone {
                j.str(&name);
            }
            j.end_arr().end_obj();
            j.finish()
        }

        // movies — every moving picture this film holds, as records: the id
        // `reclip` takes, the hash it is filed under, its name and its size.
        // For the pass that revisits clips stored at the old bitrate.
        "movies" => {
            let d = h.project.doc();
            let mut j = Json::new();
            j.arr();
            for record in d.store().of_kind(&Kind::Media) {
                if !d.media_kind(record.id).map(|k| k.is_moving()).unwrap_or(false) {
                    continue;
                }
                j.obj()
                    .kv("media", &record.id.0.to_string())
                    .kv("hash", record.text(f::HASH).unwrap_or(""))
                    .kv("filename", record.text(f::FILENAME).unwrap_or(""))
                    .ki("bytes", record.get(f::BYTES).and_then(|v| v.as_int()).unwrap_or(0))
                    .end_obj();
            }
            j.end_arr();
            j.finish()
        }

        // strays <relay media json> — of the files a media folder holds,
        // the ones this film no longer names (`Doc::stray_media_names`). The
        // argument is the relay's own `/media` answer, the same text
        // `syncplan` takes. Judgement only; the relay listing carries when
        // each file arrived, and how long to wait is the shell's rule.
        "strays" => {
            let media = parts.next().unwrap_or("");
            let there = shotlister_remote::parse_state("", media);
            let strays = h
                .project
                .doc()
                .stray_media_names(there.media.iter().map(|e| e.name.as_str()));
            let mut j = Json::new();
            j.arr();
            for name in strays {
                j.str(&name);
            }
            j.end_arr();
            j.finish()
        }

        // strip <hash> <base64 jpeg> — a clip's four moments, two by two, in
        // the same box one frame filled. Written beside the movie under its
        // own hash with the `strip` extension; only the printed page reads
        // it, and only when the clip carries no arrows. See `strip_bytes`.
        // clips — **every use of a moving picture in this film**, so the Mac
        // knows which four-moment strips to make and what to file each under.
        //
        // A use, not a file: the trim lives on the media ref, so one movie
        // attached to two shots with two different in/out points owes two
        // strips. `key` is `package::strip_key` already worked out here, so
        // the Mac writes the file the engine will later read without ever
        // computing the name itself — there is no second copy of that
        // arithmetic to drift.
        //
        // Uses with arrows drawn on them are left out: a marked clip keeps its
        // single frame, because marks are placed in the fractions of one
        // picture and four pictures in the same box would scatter them.
        // colwidths [columns=… frames=…] — **what each column of the printed
        // table is worth before he touches anything.** The export dialog needs
        // it to show the share a column is about to take, and asking rather
        // than keeping its own copy is what stops the two drifting: the
        // weights live in exactly one place, `html::base_column_weight`, and
        // the dial he moves is a multiplier on whatever they say.
        "colwidths" => {
            let options = Options::read(parts);
            let size = FrameSize::read(options.get("frames").unwrap_or(""));
            let p = &h.project;
            let query = match options.query_narrowing(h) {
                Ok(q) => q,
                Err(problem) => return problem,
            };
            let mut sheet = p.doc().sheet(&query);
            if let Some(columns) = options.list("columns") {
                sheet.columns = columns;
            }
            let mut j = Json::new();
            j.arr();
            for (field, weight) in html::default_column_weights(&sheet, size) {
                j.obj().kv("field", &field).kn("weight", weight).end_obj();
            }
            j.end_arr();
            j.finish()
        }

        // tablelayout [scenes=… day=… columns=…] — **Auto, for the printed
        // table**: which way round, how big the text and the pictures, and
        // every column's share, worked out from what is in the cells
        // (`export::autolayout`). The export box asks this and then prints
        // with exactly what comes back, so Auto and the dials it hands over
        // to on a switch to Manual are the same sheet.
        "tablelayout" => {
            let options = Options::read(parts);
            let query = match options.query_narrowing(h) {
                Ok(q) => q,
                Err(problem) => return problem,
            };
            let mut sheet = h.project.doc().sheet(&query);
            if let Some(columns) = options.list("columns") {
                sheet.columns = columns;
            }
            // `size=1.20` and `paper=landscape|portrait`: his Size and his
            // paper on Auto. Neither said is Auto's own pick.
            let size = options.get("size").and_then(|v| v.parse::<f64>().ok()).unwrap_or(1.0);
            let landscape = match options.get("paper") {
                Some("landscape") => Some(true),
                Some("portrait") => Some(false),
                _ => None,
            };
            let problem = autolayout::Problem::asked(&sheet, autolayout::Ask::new(size, landscape));
            let before = autolayout::assess_default(&problem, &sheet);
            // `defer=1`: measure here, decide elsewhere. The measured sheet is
            // parked under a ticket and `sl_solve_layout` decides it on
            // whatever thread asks — so the export box's preview never waits
            // on the deciding.
            if options.get("defer") == Some("1") {
                let ticket = park_layout(problem, before);
                let mut j = Json::new();
                j.obj().ki("ticket", ticket as i64).end_obj();
                return j.finish();
            }
            let plan = autolayout::solve(&problem);
            if options.get("explain").is_some() {
                return format!("{}\n{}", problem.describe(), plan_json(&plan, Some(&before)));
            }
            plan_json(&plan, Some(&before))
        }

        "clips" => {
            let d = h.project.doc();
            let mut seen: Vec<String> = Vec::new();
            let mut j = Json::new();
            j.arr();
            for record in d.store().of_kind(&Kind::MediaRef) {
                let Some(media) = record.ref_id(f::MEDIA) else { continue };
                if !d.media_kind(media).map(|k| k.is_moving()).unwrap_or(false) {
                    continue;
                }
                if !d.marks_on(record.id).is_empty() {
                    continue;
                }
                let hex = d
                    .get(media)
                    .and_then(|r| r.text(f::HASH).map(|s| s.to_string()))
                    .unwrap_or_default();
                if hex.is_empty() {
                    continue;
                }
                let trim = d.media_trim(record.id);
                let key = package::strip_key(&hex, trim);
                // The same clip on ten shots at the same trim is one strip.
                if seen.contains(&key) {
                    continue;
                }
                seen.push(key.clone());
                j.obj()
                    .kv("stem", &package::strip_key(&hex, None))
                    .kv("key", &key)
                    .kn("start", trim.map(|t| t.0).unwrap_or(0.0))
                    .kn("end", trim.map(|t| t.1).unwrap_or(0.0))
                    .end_obj();
            }
            j.end_arr();
            j.finish()
        }

        "strip" => {
            let hex = parts.next().unwrap_or("");
            if hex.is_empty() {
                return error("no hash given");
            }
            let bytes = match parts.next().and_then(b64::decode) {
                Some(b) if !b.is_empty() => b,
                _ => return error("nothing decodable in the strip"),
            };
            if let Err(e) = h.project.write_proxy(hex, "strip", &bytes) {
                return error(&e.message());
            }
            ok()
        }

        // media <hash> <ext> — the proxy bytes, for drawing
        // media <hash> [ext] — the stored bytes. The extension is a hint
        // only: what is actually on disk wins, because a file re-encoded on
        // the way in is stored under the extension it *became*, while keeping
        // the name it *came with*.
        "media" => {
            let hex = parts.next().unwrap_or("");
            // An absent extension must not quietly become `png`. That is the
            // extension a clip's poster is stored under, so defaulting to it
            // is how asking for a clip handed back the still that stands for
            // it — and a player given a still draws a black rectangle.
            let asked = parts.next().unwrap_or("").trim();
            let hint = if asked.is_empty() { None } else { Some(asked) };
            if let Ok(Some((found, bytes))) = h.project.find_proxy(hex, hint) {
                let mut j = Json::new();
                j.obj()
                    .kv("ext", &found)
                    .kv("data", &b64::encode(&bytes))
                    .end_obj();
                return j.finish();
            }
            match h.project.read_proxy(hex, hint.unwrap_or("png")) {
                Ok(Some(bytes)) => {
                    let mut j = Json::new();
                    j.obj().kv("data", &b64::encode(&bytes)).end_obj();
                    j.finish()
                }
                Ok(None) => error("no proxy stored for that frame"),
                Err(e) => error(&e.message()),
            }
        }

        // ---- looking for something ----------------------------------------
        // filter <hide struck 0|1> <text>
        "filter" => {
            h.hide_struck = parts.next().unwrap_or("0") == "1";
            h.search = parts.next().unwrap_or("").to_string();
            view(h)
        }

        // facet <field> <value>  — an empty value clears that one, and the
        // field `all` clears every kind of narrowing at once.
        "facet" => {
            let field = parts.next().unwrap_or("").to_string();
            let value = parts.next().unwrap_or("").trim().to_string();
            match field.as_str() {
                "all" => {
                    h.facets.clear();
                    h.day = None;
                    h.unscheduled_only = false;
                    h.sequence = None;
                    h.search.clear();
                    h.hide_struck = false;
                }
                "day" => {
                    h.unscheduled_only = value == "none";
                    h.day = if h.unscheduled_only { None } else { id_from(&value) };
                }
                "sequence" => h.sequence = id_from(&value),
                // **The shoot picker** (piece D): a shoot's id, or empty for
                // All Shoots. New scenes and days are born into it.
                "shoot" => {
                    let on = shotlister_engine::shoots::bare(&value);
                    h.shoot = if on.is_empty() { None } else { Some(on) };
                    let born = h.shoot.clone();
                    h.project.doc_mut().set_born_in(born.as_deref());
                }
                _ => {
                    h.facets.retain(|(name, _)| *name != field);
                    if !value.is_empty() {
                        h.facets.push((field, value));
                    }
                }
            }
            view(h)
        }

        // shootmove <shootId> <sceneId,sceneId,…> — **Move to Shoot…** (piece
        // D): the scenes into one of the project's shoots, one undo step.
        // Shots on another shoot's day go back to Unscheduled. Answers the view.
        "shootmove" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let to = parts.next().unwrap_or("").trim().to_string();
            let scenes: Vec<Id> = parts.next().unwrap_or("").split(',').filter_map(id_from).collect();
            if h.project.doc().shoot(&to).is_none() {
                return error("that shoot is not one this project has");
            }
            h.project.doc_mut().move_scenes_to_shoot(&scenes, &to);
            view(h)
        }

        // shootplan [apply] — **the one-time converter** (piece D): section
        // headings that name a shoot ("Shoot 1 — July 9") become real shoot
        // assignments; strays go to the first shoot, days by date. Bare, a dry
        // run that writes nothing; `apply` writes it in one undo step.
        // Answers {applied, plan}.
        "shootplan" => {
            let apply = parts.next().unwrap_or("").trim() == "apply";
            if apply {
                if let Some(problem) = writable(h) {
                    return problem;
                }
            }
            if h.project.doc().shoots().is_empty() {
                return error("this project's card lists no shoots");
            }
            let plan = h.project.doc().shoots_from_sections();
            let applied = if apply { h.project.doc_mut().apply_shoot_plan(&plan) } else { 0 };
            format!("{{\"applied\":{},\"plan\":{}}}", applied, h.project.doc().shoot_plan_json(&plan))
        }

        // sort <column> <asc|desc> — reading order only. Nothing is written and
        // no letter moves; an empty column puts the list back in its own order.
        // sort <column> [asc|desc] — read the list in a column's order. Empty
        // is the script's own order. **`shootingorder` is the shooting order**
        // (2026-10-06): the list grouped by day, each day's shots in the order
        // they are shot, the unscheduled last — the engine's day grouping,
        // reached from the Sort menu because that is where he looks for it.
        // Any other sort reads by scene again.
        "sort" => {
            let column = parts.next().unwrap_or("").trim().to_string();
            let descending = parts.next().unwrap_or("asc") == "desc";
            if column == "shootingorder" {
                h.group_by = GroupBy::Day;
                h.sort = None;
            } else {
                if h.group_by == GroupBy::Day {
                    h.group_by = GroupBy::Scene;
                }
                h.sort = if column.is_empty() { None } else { Some((column, descending)) };
            }
            view(h)
        }

        // exportinfo — **what the export box says about the Table**
        // (2026-10-15): the Table's filter in words ("Day 3", "INT"), its
        // sort, and every shoot day of the film whatever the shoot picker is
        // on, with the shoots, for the Days picker.
        "exportinfo" => {
            let d = h.project.doc();
            let mut words: Vec<String> = Vec::new();
            if !h.search.trim().is_empty() {
                words.push(format!("\u{201c}{}\u{201d}", h.search.trim()));
            }
            if let Some(shoot) = h.shoot.as_deref().and_then(|s| d.shoot(s)) {
                words.push(if shoot.label.is_empty() { shoot.kind.clone() } else { shoot.label.clone() });
            }
            if let Some(day) = h.day {
                words.push(d.day_label(day).unwrap_or_else(|| "A day".into()));
            } else if h.unscheduled_only {
                words.push("Unscheduled".into());
            }
            if let Some(sequence) = h.sequence.and_then(|id| d.get(id)) {
                words.push(sequence.text(f::TITLE).unwrap_or("Section").to_string());
            }
            for (_, value) in &h.facets {
                let named = id_from(value).and_then(|id| d.get(id)).and_then(|r| {
                    [f::TITLE, f::LABEL, "name"].iter().find_map(|k| r.text(k).filter(|t| !t.is_empty()).map(String::from))
                });
                words.push(named.unwrap_or_else(|| value.clone()));
            }
            if h.hide_struck {
                words.push("No cut shots".into());
            }
            let loose = d
                .all_placements()
                .into_iter()
                .filter(|p| d.get(*p).map(|r| r.ref_id(f::DAY).is_none()).unwrap_or(false))
                .count();
            let mut j = Json::new();
            j.obj();
            j.key("filter").arr();
            for w in &words {
                j.str(w);
            }
            j.end_arr();
            let (sort, down) = h.sort.clone().unwrap_or_default();
            j.kv("sort", &sort).kb("descending", down).kb("shooting", h.group_by == GroupBy::Day);
            j.ki("unscheduled", loose as i64);
            j.key("days").arr();
            for id in d.days_in_order() {
                j.obj()
                    .kv("id", &id.0.to_string())
                    .kv("label", &d.day_label(id).unwrap_or_default())
                    .kv("date", &d.day_date(id))
                    .ki("count", d.shot_count_on_day(id) as i64)
                    .kb("wrapped", d.day_wrapped(id))
                    .kv("shoot", &d.day_shoot(id).unwrap_or_default())
                    .end_obj();
            }
            j.end_arr();
            j.key("shoots").arr();
            for shoot in d.shoots() {
                j.obj()
                    .kv("id", &shoot.id)
                    .kv("label", if shoot.kind.is_empty() { &shoot.label } else { &shoot.kind })
                    .end_obj();
            }
            j.end_arr();
            j.end_obj();
            j.finish()
        }

        // shootbefore <placement> <day|""> [<before>] — a shot into the
        // shooting order just in front of another shot on that day, or at the
        // day's end; no day takes it off every day. The shot list's drag when
        // it is sorted by Shooting Order. Its number never changes. One undo.
        "shootbefore" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(placement) = parts.next().and_then(id_from) else {
                return error("that shot id is not one this project has");
            };
            let day = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            let before = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            h.project.doc_mut().shoot_before(placement, day, before);
            view(h)
        }

        // ---- frames on a shot ---------------------------------------------
        // detach <mediaRefId> — takes the frame off this shot. The file stays;
        // it may be on another shot, and it is named by its contents.
        "detach" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that frame is not one this shot has"),
            };
            h.project.doc_mut().detach_media(mref);
            view(h)
        }

        // movemedia <mediaRefId> <index> — the order frames read in
        "movemedia" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that frame is not one this shot has"),
            };
            let index: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
            h.project.doc_mut().move_media_to(mref, index);
            view(h)
        }

        // duplicate <placementId> — the same shot again, one letter along
        "duplicate" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let placement = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            if h.project.doc_mut().duplicate_shot(placement).is_none() {
                return error("that shot could not be duplicated");
            }
            view(h)
        }

        // ---- the sample list ------------------------------------------------
        // A new project is empty, as it should be. This fills one on request,
        // which is how the first run gets something to look at.
        "demo" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if h.project.doc().scenes_in_order().is_empty() {
                demo::seed(h.project.doc_mut());
                let _ = h.project.save();
            }
            view(h)
        }

        // ---- bringing a sheet back in ---------------------------------------
        // import <path> — a list can leave for a spreadsheet, be worked on by
        // somebody without the app, and come back. What happened is reported
        // rather than assumed: a clean import is quiet, one with something to
        // say stops and says it.
        "import" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let path = parts.next().unwrap_or("");
            let bytes = match std::fs::read(path) {
                Ok(b) => b,
                Err(e) => return error(&format!("could not read that file: {e}")),
            };
            let lower = path.to_lowercase();
            let table = if lower.ends_with(".xlsx") {
                match shotlister_engine::import::read_xlsx(&bytes) {
                    Ok(t) => t,
                    Err(_) => return error("that spreadsheet could not be read"),
                }
            } else {
                match String::from_utf8(bytes) {
                    Ok(text) => shotlister_engine::import::parse(&text),
                    Err(_) => return error("that file is not text this can read"),
                }
            };
            if table.is_empty() {
                return error("there are no rows in that file");
            }

            let report = shotlister_engine::apply_import(h.project.doc_mut(), &table);
            let mut j = Json::new();
            j.obj();
            j.kv("summary", &report.summary())
                .ki("added", report.shots_created as i64)
                .ki("updated", report.shots_updated as i64);
            j.key("scenes").arr();
            for scene in &report.scenes_created {
                j.str(scene);
            }
            j.end_arr();
            // a number the sheet asked for and could not have, and what it got
            j.key("renumbered").arr();
            for (asked, given) in &report.renumbered {
                j.obj().kv("asked", asked).kv("given", given).end_obj();
            }
            j.end_arr();
            j.key("daysNotFound").arr();
            for day in &report.days_not_found {
                j.str(day);
            }
            j.end_arr();
            j.key("skipped").arr();
            for (row, why) in &report.skipped {
                j.obj().ki("row", *row as i64).kv("why", why).end_obj();
            }
            j.end_arr();
            j.end_obj();
            let report = j.finish();
            let body = view(h);
            format!("{{\"import\":{report},\"view\":{body}}}")
        }

        // readscript\t<settings>\n page/run lines — read a script off printed
        // pages and **report**, changing nothing. The shell decodes the PDF
        // (PDFKit, or pdf.js on the web) and hands over each run of text with
        // where it sits; every judgement about what those runs mean is made in
        // the engine, where it is tested without a PDF in sight.
        //
        // The payload is lines rather than JSON because both ends of this
        // boundary are ours and there is no JSON reader on this side — the same
        // reasoning that made the rest of it tab-delimited.
        //
        //   page\t<width>\t<height>
        //   run\t<x>\t<y>\t<text>
        //
        // `y` counts **down** from the top of the page. PDFKit measures up from
        // the bottom, so the shell flips it: one line there, and everything
        // here reads down the page the way a person does.
        // readscript\t<settings>\t<merging>\t<minimumSpeeches>\n<pages>
        //
        // The cast options are trailing and optional, and they are here for the
        // same reason the detection dials are: **a control that changes what
        // gets imported has to change what the sheet shows, or the list on
        // screen stops describing the import.** The Mac's Characters tab had no
        // Name Merging control at all until this took them.
        "readscript" => {
            let (head, payload) = line.split_once('\n').unwrap_or((line, ""));
            let mut asked = head.split('\t');
            asked.next();
            let detection = detection_from(asked.next().unwrap_or(""), h.project.doc().detection());
            let cast_options = shotlister_engine::CastOptions {
                merging: match asked.next().unwrap_or("") {
                    "none" => shotlister_engine::Merging::None,
                    "hard" => shotlister_engine::Merging::Aggressive,
                    _ => shotlister_engine::Merging::Regular,
                },
                minimum_speeches: asked.next().and_then(|n| n.parse().ok()).unwrap_or(0),
            };
            let pages = pages_from(payload);
            if pages.iter().all(|page| page.runs.is_empty()) {
                return error("there is no text on those pages");
            }

            let screenplay = shotlister_engine::printed::read(&pages, &detection);
            // How long each scene is, measured off the layout rather than off
            // the pages it happened to be printed on: a draft set in some other
            // program's margins still has to give the number an AD would write.
            let laid = shotlister_engine::lay_out(&screenplay);
            let diff = h.project.doc().diff_script(&screenplay.accepted());
            let cast = shotlister_engine::cast::read(&screenplay, cast_options);

            let mut j = Json::new();
            j.obj();
            j.ki("pages", pages.len() as i64)
                .ki("pagesLaidOut", laid.pages_long() as i64)
                .ki("duplicatesIgnored", screenplay.duplicates_ignored as i64);
            // **The script itself, as this reading marked it up.**
            //
            // `takescript` takes *text*, not pages — and until this line
            // nothing handed the text over, so the Mac could report on a PDF
            // and then had nothing to apply. It would have had to send the runs
            // twice and hope the second reading matched the first, which is the
            // kind of seam that produces an import that differs from the report
            // it showed.
            //
            // This is `printed::as_script` — the same string the reading was
            // made from — so the report and the import are two views of one
            // reading rather than two readings.
            j.kv("script", &shotlister_engine::printed::as_script(&pages));

            j.key("scenes").obj();
            j.ki("detected", screenplay.scenes.len() as i64)
                .ki("matched", (diff.changed.len() + diff.unchanged) as i64)
                .ki("new", diff.added.len() as i64)
                .ki("omitted", diff.gone.len() as i64);
            j.key("rows").arr();
            for (index, scene) in screenplay.scenes.iter().enumerate() {
                j.obj();
                j.kv("label", &scene.label)
                    .kv("heading", &scene.script.heading)
                    .kv("location", &scene.script.location)
                    .kv("timeOfDay", &scene.script.time_of_day)
                    .kv("intExt", &scene.script.int_ext);
                match scene.script.number.as_deref() {
                    Some(number) => {
                        j.kv("number", number);
                    }
                    None => {
                        j.key("number").null();
                    }
                }
                match scene.status {
                    shotlister_engine::screenplay::Status::Scene => {
                        j.kv("status", "scene");
                        j.key("under").null();
                    }
                    shotlister_engine::screenplay::Status::SubSlug { under } => {
                        j.kv("status", "room");
                        j.kv("under", &screenplay.scenes[under].label);
                    }
                }
                let known = scene
                    .script
                    .number
                    .as_deref()
                    .and_then(|number| h.project.doc().scene_numbered(number))
                    .is_some();
                j.kb("accepted", scene.accepted).kb("matched", known);
                // What it costs to shoot, in the unit the trade uses.
                match laid.extent_of(index) {
                    Some(extent) => {
                        j.kv("length", &extent.length())
                            .ki("eighths", extent.eighths as i64)
                            .ki("startsOnPage", extent.starts_on as i64);
                    }
                    None => {
                        j.key("length").null();
                        j.ki("eighths", 0).ki("startsOnPage", 0);
                    }
                }
                j.end_obj();
            }
            j.end_arr();
            // The scenes the project has that this draft no longer mentions.
            // Reported with the work that would go with them, and archived
            // rather than deleted if anybody says so — never from here.
            // **Scenes that appear to have moved to a new number** — Ref 241.
            //
            // Reported against *every* scene the draft brings, because the
            // sheet has not been ticked yet and the person choosing needs to
            // see the pairs before deciding which of them to take. Nothing
            // acts on this: taking a move needs its index sent back through
            // `takescript`.
            j.key("movedNumber").arr();
            {
                let everything = shotlister_engine::revisions::Taking {
                    scenes: (0..screenplay.scenes.len()).collect(),
                    ..Default::default()
                };
                for moved in h.project.doc().moved_scenes(&screenplay, &everything) {
                    j.obj()
                        .ki("index", moved.index as i64)
                        .kv("from", &moved.from)
                        .kv("to", &moved.to)
                        .kv("heading", &moved.heading)
                        .ki("shots", moved.shots as i64)
                        .end_obj();
                }
            }
            j.end_arr();
            j.key("goneFromTheDraft").arr();
            for gone in &diff.gone {
                j.obj()
                    .kv("number", &gone.number)
                    .kv("heading", &gone.heading)
                    .ki("shots", gone.shots as i64)
                    .end_obj();
            }
            j.end_arr();
            j.end_obj();

            j.key("characters").obj();
            j.ki("detected", cast.len() as i64)
                .ki("matched", 0)
                .ki("new", cast.len() as i64);
            j.key("rows").arr();
            for member in &cast {
                j.obj();
                j.kv("name", &member.name)
                    .kv("display", &member.display)
                    .ki("speeches", member.speeches as i64);
                j.key("scenes").arr();
                for scene in &member.scenes {
                    j.str(&screenplay.scenes[*scene].label);
                }
                j.end_arr();
                j.key("aliases").arr();
                for alias in &member.aliases {
                    j.str(alias);
                }
                j.end_arr();
                j.end_obj();
            }
            j.end_arr();
            j.end_obj();

            j.end_obj();
            j.finish()
        }

        // detection [<settings>] — read back the dials this project reads
        // scripts with, or set them. Given no settings it only reports.
        "detection" => {
            let settings = parts.next().unwrap_or("");
            if !settings.is_empty() {
                if let Some(problem) = writable(h) {
                    return problem;
                }
                let wanted = detection_from(settings, h.project.doc().detection());
                h.project.doc_mut().set_detection(&wanted);
            }
            let d = h.project.doc().detection();
            let mut j = Json::new();
            j.obj();
            j.kb("mustHaveANumber", d.must_have_a_number)
                .kb("ignoreDuplicateNumbers", d.ignore_duplicate_numbers)
                .kb("findSubSlugs", d.find_sub_slugs);
            j.key("mustContain").arr();
            for word in &d.must_contain {
                j.str(word);
            }
            j.end_arr();
            j.key("neverContains").arr();
            for word in &d.never_contains {
                j.str(word);
            }
            j.end_arr();
            j.end_obj();
            j.finish()
        }

        // revisions — every draft the project has taken in, newest first, with
        // which one is latest. A revision is a thing the project keeps, not an
        // action it performed once.
        "revisions" => {
            let doc = h.project.doc();
            let latest = doc.latest_revision().map(|r| r.id);
            let mut j = Json::new();
            j.obj();
            j.key("revisions").arr();
            for revision in doc.revisions() {
                j.obj()
                    .kv("id", &revision.id.0.to_string())
                    .kv("name", &revision.name)
                    .kv("filename", &revision.filename)
                    .kv("importedAt", &revision.imported_at)
                    .kv("hash", &revision.hash)
                    .kb("latest", Some(revision.id) == latest)
                    .end_obj();
            }
            j.end_arr();
            j.end_obj();
            j.finish()
        }

        // renamerevision <id> <name> — the only thing about a revision anybody
        // edits. Where it came from and when it landed are facts.
        "renamerevision" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(revision) = parts.next().and_then(id_from) else {
                return error("that revision id is not one this project has");
            };
            let name = parts.next().unwrap_or("").trim().to_string();
            if name.is_empty() {
                return error("a revision needs a name");
            }
            h.project.doc_mut().rename_revision(revision, &name);
            let body = view(h);
            format!("{{\"ok\":true,\"view\":{body}}}")
        }

        // takescript\t<name>\t<filename>\t<importedAt>\t<scenes>\t<cast>\t<archive>
        //           \t<merging>\t<minimumSpeeches>\t<settings>\n<text>
        //
        // Take a draft in. `scenes` is the indices ticked, comma-separated, as
        // they were numbered in the report `readscript` gave back; `cast` is the
        // names ticked, separated by `|`; `archive` is `1` to move scenes the
        // draft no longer mentions into the archive.
        //
        // Pass `weigh` as the name to be told what *would* happen and have
        // nothing done — which is the confirm screen, computed by the same code
        // that does the work so the two cannot drift apart.
        "takescript" => {
            let (head, text) = line.split_once('\n').unwrap_or((line, ""));
            let mut fields = head.split('\t');
            fields.next();
            let name = fields.next().unwrap_or("").to_string();
            let filename = fields.next().unwrap_or("").to_string();
            let imported_at = fields.next().unwrap_or("").to_string();
            let mut taking = shotlister_engine::Taking {
                scenes: fields
                    .next()
                    .unwrap_or("")
                    .split(',')
                    .filter_map(|n| n.trim().parse().ok())
                    .collect(),
                cast: fields
                    .next()
                    .unwrap_or("")
                    .split('|')
                    .map(|n| n.trim().to_string())
                    .filter(|n| !n.is_empty())
                    .collect(),
                archive_omitted: fields.next().unwrap_or("") == "1",
                // The dials the cast list was read with, so what lands on a
                // scene is spelled the way the ticked list is.
                cast_options: shotlister_engine::CastOptions {
                    merging: match fields.next().unwrap_or("") {
                        "none" => shotlister_engine::Merging::None,
                        "hard" => shotlister_engine::Merging::Aggressive,
                        _ => shotlister_engine::Merging::Regular,
                    },
                    minimum_speeches: fields.next().and_then(|n| n.parse().ok()).unwrap_or(0),
                },
                moves: Vec::new(),
            };

            // **The same rules the report was read under.**
            //
            // `readscript` reads the *pages* with the dials the import sheet is
            // showing; this reads the *text* those pages were marked up into,
            // and it used to do it under `Detection::default()` — every dial
            // off. That is not a cosmetic difference: with sub-slugs off, a
            // bare room name stops being a scene, so every index after it in
            // the list means a different scene than the one the sheet ticked,
            // and with `CONTINUED:` allowed through, a paginated script gains
            // phantom scenes that shift them further. Caught on 2026-08-22 by
            // the first end-to-end import: the sheet said three scenes matched,
            // the import linked two and archived a scene that was still in the
            // draft.
            //
            // A trailing field, so anything that does not send it — the tests
            // above, an older shell — falls back to the project's own dials
            // rather than to nothing at all.
            let settings = fields.next().unwrap_or("");
            // **Which of the moves were ticked**, by draft index — Ref 241.
            //
            // Added *after* the settings rather than before them, so that
            // every caller that already sends settings keeps working
            // unchanged. A field inserted in the middle would have silently
            // read the detection dials as a list of scene indexes and turned
            // every dial off, which is the sort of break that looks like a
            // reader bug for an afternoon.
            //
            // Absent means nothing moves, which is what taking a draft has
            // always done.
            taking.moves = fields
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|n| n.trim().parse().ok())
                .collect();
            let detection = detection_from(settings, h.project.doc().detection());
            let screenplay = shotlister_engine::screenplay::read_with(text, &detection);
            let weighing = name == "weigh";
            if !weighing {
                if let Some(problem) = writable(h) {
                    return problem;
                }
            }

            let plan = if weighing {
                h.project.doc().plan_revision(&screenplay, &taking)
            } else {
                // **The project keeps the rules its script was read with.**
                // The import sheet saves the dials on its own a moment after
                // the take; anything else that takes a draft did not, and the
                // pages are read back with the project's rules — so a draft
                // taken one way and read another came back with different
                // scenes. Remembered here, at the moment they were used.
                h.project.doc_mut().set_detection(&detection);
                let hash = shotlister_engine::sha256(text.as_bytes());
                let hash = hash.to_hex();
                // The text lives beside the media, addressed by its contents,
                // for the reason media does: a screenplay is far too big to sit
                // in a log that syncs line by line.
                if let Err(e) = h.project.write_script(&hash, "txt", text.as_bytes()) {
                    return error(&format!("the script could not be kept: {}", e.message()));
                }
                let revision = shotlister_engine::Revision {
                    id: shotlister_engine::Id::new(),
                    name,
                    filename,
                    imported_at,
                    hash,
                };
                h.project
                    .doc_mut()
                    .take_revision(&screenplay, &taking, &revision)
            };

            // **Lines a shot holds that this draft no longer has** (Ref
            // 1553): said on the confirm screen and after, and nothing done
            // about them. The tie keeps its words for a draft that has them.
            let lost_lines = {
                let laid = shotlister_engine::lay_out(&screenplay);
                let draft = shotlister_engine::playties::Draft::of(&screenplay, &laid);
                h.project.doc().play_ties_in(&draft).iter().filter(|(_, r)| !r.lost.is_empty()).count()
            };
            let mut j = Json::new();
            j.obj();
            j.kb("weighed", weighing);
            j.key("sentences").arr();
            for sentence in plan.sentences() {
                if lost_lines > 0 && sentence == "Nothing would change." {
                    continue;
                }
                j.str(&sentence);
            }
            if lost_lines > 0 {
                j.str(&format!(
                    "{} {} lines this draft no longer has. {} kept, and found again in any draft that has them.",
                    lost_lines,
                    if lost_lines == 1 { "shot holds" } else { "shots hold" },
                    if lost_lines == 1 { "Its tie is" } else { "Their ties are" },
                ));
            }
            j.end_arr();
            j.ki("linesLost", lost_lines as i64);
            j.ki("linked", plan.linked.len() as i64)
                .ki("created", plan.created.len() as i64)
                .ki("archived", plan.archived.len() as i64)
                .ki("castAdded", plan.cast_added.len() as i64);
            j.key("leftAlone").arr();
            for (number, shots) in &plan.left_alone {
                j.obj().kv("number", number).ki("shots", *shots as i64).end_obj();
            }
            j.end_arr();
            j.end_obj();
            let report = j.finish();
            if weighing {
                return report;
            }
            let body = view(h);
            format!("{{\"take\":{report},\"view\":{body}}}")
        }

        // scriptpages [<revisionId>] — the script laid out, ready to draw.
        // Rows and indents are worked out here; the shell positions and paints
        // and does no measuring of its own.
        "scriptpages" => {
            let wanted = parts.next().and_then(id_from);
            let (revision, screenplay, laid, draft) = match read_draft(h, wanted) {
                Ok(read) => read,
                Err(problem) => return error(&problem),
            };
            // **Which shots hold which lines** (Ref 1553), read against this
            // draft: a tie whose words moved is found where they went, and
            // one whose words are gone is listed under `lost`, never drawn
            // somewhere else.
            let doc = h.project.doc();
            let ties = doc.play_ties_in(&draft);
            let number_of = |shot: shotlister_engine::Id| {
                doc.placements_of_shot(shot)
                    .first()
                    .and_then(|p| doc.display_number(*p))
                    .unwrap_or_default()
            };

            let mut j = Json::new();
            j.obj();
            j.kv("revision", &revision.id.0.to_string())
                .kv("name", &revision.name)
                .ki("pages", laid.pages_long() as i64)
                .ki("linesPerPage", shotlister_engine::pages::LINES_PER_PAGE as i64)
                .ki("measure", shotlister_engine::pages::MEASURE as i64);

            j.key("scenes").arr();
            for extent in &laid.scenes {
                let heading = screenplay
                    .scenes
                    .get(extent.scene)
                    .map(|scene| scene.script.heading.clone())
                    .unwrap_or_default();
                j.obj()
                    .kv("label", &extent.label)
                    .kv("heading", &heading)
                    .kv("length", &extent.length())
                    .ki("eighths", extent.eighths as i64)
                    .ki("startsOnPage", extent.starts_on as i64)
                    .end_obj();
            }
            j.end_arr();

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
                    // Where the line sits in the draft's text, and the shots
                    // whose lines cover it: what a shell needs to draw a
                    // mark beside it and to turn a selection into a tie.
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
                    match pl.scene.and_then(|at| screenplay.scenes.get(at)) {
                        Some(scene) => {
                            j.kv("scene", &scene.label);
                        }
                        None => {
                            j.key("scene").null();
                        }
                    }
                    j.end_obj();
                }
                j.end_arr();
                j.end_obj();
            }
            j.end_arr();

            // Every tie, found or not: `ties` the shots and their stretches
            // in this draft, `lost` the words a shot holds that this draft
            // no longer has. Kept on the shot, said here, moved nowhere.
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

        // playtie <shot> <revision|""> <from> <to> [<from> <to> …] — the
        // highlighter on a film's screenplay (Ref 1553): offsets into the
        // draft's text as `scriptpages` gives it (`from`/`to` on each line).
        // A selection the shot already holds is let go; anything else is
        // added. The latest draft when none is named. Answers the view.
        //
        // playuntieat <shot> <revision|""> <at> — the shot's stretch under
        // that offset is let go. Answers the view.
        //
        // playwords <shot> <replace|add|remove> <words> — by words: the
        // shot's own scene first, else the first place they appear in the
        // latest draft. An empty `<words>` with replace unties all. Answers
        // the view, or an error when the words are not there.
        "playtie" | "playuntieat" | "playwords" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(shot) = parts.next().and_then(id_from) else {
                return error("that shot id is not one this project has");
            };
            if cmd == "playwords" {
                let mode = parts.next().unwrap_or("replace").to_string();
                let words = parts.collect::<Vec<_>>().join("\t");
                if words.trim().is_empty() {
                    if mode == "remove" {
                        return error("say which words to let go");
                    }
                    h.project.doc_mut().untie_play(shot);
                    return view(h);
                }
                let (revision, _, _, draft) = match read_draft(h, None) {
                    Ok(read) => read,
                    Err(problem) => return error(&problem),
                };
                let doc = h.project.doc_mut();
                let done = if mode == "remove" {
                    doc.untie_play_words(shot, Some(revision.id), Some(&draft), &words)
                } else {
                    doc.tie_play_words(shot, Some(revision.id), Some(&draft), &words, mode == "add")
                };
                if !done {
                    return error(if mode == "remove" {
                        "the shot does not hold those words"
                    } else {
                        "those words are not in the script"
                    });
                }
                return view(h);
            }
            let wanted = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            let (revision, _, _, draft) = match read_draft(h, wanted) {
                Ok(read) => read,
                Err(problem) => return error(&problem),
            };
            let numbers: Vec<usize> = parts.map(|p| p.parse().unwrap_or(0)).collect();
            if cmd == "playuntieat" {
                let at = numbers.first().copied().unwrap_or(0);
                h.project.doc_mut().untie_play_at(shot, Some(revision.id), &draft, at);
            } else {
                let ranges: Vec<(usize, usize)> = numbers
                    .chunks(2)
                    .filter_map(|c| match c {
                        [a, b] => Some((*a, *b)),
                        _ => None,
                    })
                    .collect();
                h.project.doc_mut().toggle_play(shot, Some(revision.id), &draft, &ranges);
            }
            view(h)
        }

        // reorder <placementId> <index> — where a shot sits in the reading the
        // table is currently in. Story order and shooting order are different
        // facts, so which one this moves depends on what you are looking at.
        "reorder" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let placement = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            let index: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
            match h.group_by {
                GroupBy::Day => h.project.doc_mut().move_in_day_to(placement, index),
                _ => h.project.doc_mut().move_in_scene_to(placement, index),
            }
            view(h)
        }

        // columnorder <a,b,c> — the order of the table, which is also the order
        // the document page's technical line reads in
        "columnorder" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let names = parts.next().unwrap_or("");
            let order: Vec<&str> = names.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
            h.project.doc_mut().set_column_order(&order);
            view(h)
        }

        // tie <shotA> <shotB> — two cameras on one moment. A setup has no record
        // kind of its own in the engine, so the first shot's id stands as the
        // key both shots point at; `setup_siblings` only cares that it is shared.
        "tie" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let (a, b) = (parts.next().and_then(id_from), parts.next().and_then(id_from));
            let (a, b) = match (a, b) {
                (Some(a), Some(b)) if a != b => (a, b),
                _ => return error("a setup needs two different shots"),
            };
            // whichever key either shot already carries, so tying a third camera
            // to a pair joins the pair rather than starting a new one
            let key = reference(&h.project, a, f::SETUP)
                .or_else(|| reference(&h.project, b, f::SETUP))
                .unwrap_or(a);
            h.project.doc_mut().set(a, f::SETUP, key);
            h.project.doc_mut().set(b, f::SETUP, key);
            view(h)
        }

        "untie" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let shot = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            h.project.doc_mut().set(shot, f::SETUP, Value::Null);
            view(h)
        }

        // ---- the board ----------------------------------------------------
        "board" => board(h),

        // scene <sceneId> <dayId|none> — dragging a whole strip onto a day,
        // which is the ordinary gesture: you schedule scenes, not shots
        // sceneinday <scene> <day> [<before scene>] — the scene's shots on
        // that day move as one block to sit before another scene's, or last.
        // Answers the board, the way `scene` does.
        "sceneinday" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let (scene, day) = (parts.next().and_then(id_from), parts.next().and_then(id_from));
            let before = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            match (scene, day) {
                (Some(scene), Some(day)) => {
                    h.project.doc_mut().move_scene_in_day(scene, day, before);
                    board(h)
                }
                _ => error("that is not a scene and a day this project has"),
            }
        }

        // putscenes <day|none> <from day|""> <before scene|""> <scene,scene,…>
        // — what a drag on the Schedule does when it lets go: the scenes go
        // onto the day ahead of `before` (or last), or off every day with
        // `none`. `from` names the day the strips were lifted off, so a split
        // scene moves only the half that was dragged. One undo step.
        "putscenes" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let day = match parts.next().unwrap_or("none") {
                "none" | "" => None,
                other => match id_from(other) {
                    Some(day) => Some(day),
                    None => return error("that day id is not one this project has"),
                },
            };
            let from = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            let before = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            let scenes: Vec<Id> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| id_from(s.trim()))
                .collect();
            if scenes.is_empty() {
                return error("that is not a scene this project has");
            }
            h.project.doc_mut().put_scenes_on_day(&scenes, from, day, before);
            board(h)
        }

        // putshot <placement> <day> [<before scene>] — one shot out of its
        // scene onto a day, standing where it was let go. One undo step.
        "putshot" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let (placement, day) = (parts.next().and_then(id_from), parts.next().and_then(id_from));
            let before = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            match (placement, day) {
                (Some(placement), Some(day)) => {
                    h.project.doc_mut().put_shot_on_day(placement, day, before);
                    board(h)
                }
                _ => error("that is not a shot and a day this project has"),
            }
        }

        // putshots <day> <before scene|""> <placement,placement,…> — several
        // shots onto a day at once: a scene's remainder opened in the scene
        // list, or a few of its shots picked there. One undo step.
        "putshots" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(day) = parts.next().and_then(id_from) else {
                return error("that day id is not one this project has");
            };
            let before = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            let shots: Vec<Id> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| id_from(s.trim()))
                .collect();
            if shots.is_empty() {
                return error("that is not a shot this project has");
            }
            h.project.doc_mut().put_shots_on_day(&shots, day, before);
            board(h)
        }

        "scene" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let scene = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that scene id is not one this project has"),
            };
            match parts.next().unwrap_or("none") {
                "none" | "" => h.project.doc_mut().unschedule_scene(scene),
                day => match id_from(day) {
                    Some(day) => h.project.doc_mut().schedule_scene(scene, day),
                    None => return error("that day id is not one this project has"),
                },
            }
            board(h)
        }

        // place <placementId> <dayId|none> — pulling one shot out of its scene
        // onto another day, for when a scene splits
        "place" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let placement = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            match parts.next().unwrap_or("none") {
                "none" | "" => h.project.doc_mut().unschedule(placement),
                day => match id_from(day) {
                    Some(day) => h.project.doc_mut().schedule(placement, day),
                    None => return error("that day id is not one this project has"),
                },
            }
            board(h)
        }

        // day new [YYYY-MM-DD] | day move <dayId> <index> | day sortbydate
        // day name <dayId> <name> | day date <dayId> <YYYY-MM-DD> | day remove <dayId>
        //
        // A day already *carried* a name and a date — the board drew both, and
        // the fixture's days really did read "Fri 12 Sep" — while nothing in
        // either app could set either one, and a day could not be taken away at
        // all. So an *Add shoot day* pressed by accident was permanent past the
        // end of the session. Ref 341.
        "day" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            match parts.next().unwrap_or("") {
                // A date beside `new` is a calendar click: the day is born
                // already dated, in one undo step. Bare `new` is untouched.
                "new" => match parts.next() {
                    Some(date) if !date.trim().is_empty() => {
                        h.project.doc_mut().create_day_dated(date);
                    }
                    _ => {
                        h.project.doc_mut().create_day();
                    }
                },
                "sortbydate" => {
                    h.project.doc_mut().sort_days_by_date();
                }
                // day shoot <dayId> <shootId> — the day into one of the
                // project's shoots (piece D); its date then follows the shoot.
                "shoot" => {
                    let day = match parts.next().and_then(id_from) {
                        Some(i) => i,
                        None => return error("that day id is not one this project has"),
                    };
                    let to = parts.next().unwrap_or("").trim().to_string();
                    if !h.project.doc_mut().set_day_shoot(day, &to) {
                        return error("that shoot is not one this project has");
                    }
                }
                "move" => {
                    let day = match parts.next().and_then(id_from) {
                        Some(i) => i,
                        None => return error("that day id is not one this project has"),
                    };
                    let index: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
                    h.project.doc_mut().move_day_to(day, index);
                }
                // day order <placementId> <index> — where a shot sits in its
                // day's running order, answered with the board. `reorder`
                // does the same only while the table is grouped by day; the
                // phone's shoot-day list is not the table, so it asks here.
                "order" => {
                    let placement = match parts.next().and_then(id_from) {
                        Some(i) => i,
                        None => return error("that shot id is not one this project has"),
                    };
                    let index: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
                    h.project.doc_mut().move_in_day_to(placement, index);
                }
                // day put <placementId> <dayId> <index> — a shot onto a day at
                // a place in its running order, from another day or none: the
                // Mac Schedule's Shooting Order drop, in one undo step.
                "put" => {
                    let placement = match parts.next().and_then(id_from) {
                        Some(i) => i,
                        None => return error("that shot id is not one this project has"),
                    };
                    let day = match parts.next().and_then(id_from) {
                        Some(i) => i,
                        None => return error("that day id is not one this project has"),
                    };
                    let index: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
                    h.project.doc_mut().schedule_at(placement, day, index);
                }
                // Naming and dating both take the empty string to mean
                // *clear it*, so the same command undoes itself and the menu
                // needs no second verb.
                what @ ("name" | "date" | "remove") => {
                    let day = match parts.next().and_then(id_from) {
                        Some(i) => i,
                        None => return error("that day id is not one this project has"),
                    };
                    match what {
                        "name" => h
                            .project
                            .doc_mut()
                            .rename_day(day, parts.next().unwrap_or("")),
                        "date" => h
                            .project
                            .doc_mut()
                            .set_day_date(day, parts.next().unwrap_or("")),
                        _ => {
                            h.project.doc_mut().delete_day(day);
                        }
                    }
                }
                other => return error(&format!("no day command called {other}")),
            }
            board(h)
        }

        // ---- the document page --------------------------------------------
        // layout <shotId> <below|above|left|right> <width fraction>
        "layout" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let shot = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            let position = FramePosition::parse(parts.next().unwrap_or("below"));
            h.project.doc_mut().set_frame_position(shot, position);
            if let Some(width) = parts.next().and_then(|w| w.parse::<f64>().ok()) {
                h.project.doc_mut().set_frame_width(shot, width);
            }
            view(h)
        }

        // keyframe <shotId> <mediaRefId> — which of a shot's frames stands for it
        "keyframe" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let shot = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that frame is not one this shot has"),
            };
            h.project.doc_mut().set_key_frame(shot, mref);
            view(h)
        }

        // ---- adding ---------------------------------------------------------
        // addscene <number> | addshot <sceneId>
        // ---- taking things out ---------------------------------------------
        //
        // The engine owns what deleting means: a shot that also lives in another
        // scene keeps its other place, letters close up in prep and stay put
        // once the shoot has started, and either is one thing to take back.
        // delete <placementId[,placementId…]> — one or many, one transaction
        // either way, so a selection's deletion is one thing to take back.
        "delete" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let ids: Vec<Id> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(|s| id_from(s.trim()))
                .collect();
            if ids.is_empty() {
                return error("that shot id is not one this project has");
            }
            h.project.doc_mut().delete_placements(&ids);
            view(h)
        }

        // archivescene <sceneId> <0|1> — set aside or bring back. The scene
        // keeps everything and stays listed; only its place in the working
        // day changes.
        "archivescene" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let scene = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that scene id is not one this project has"),
            };
            let on = parts.next().unwrap_or("1") != "0";
            h.project.doc_mut().archive_scene(scene, on);
            view(h)
        }

        "deletescene" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            // **Archived first.** His ask of 2026-08-22 was to be able to
            // delete a scene *after* archiving it; archiving is the reversible
            // step and taking it first is what keeps a film safe from one
            // click. Nothing reached this command from the Mac before, so the
            // guard costs nobody anything.
            match parts.next().and_then(id_from) {
                Some(scene) => match h.project.doc_mut().delete_archived_scene(scene) {
                    Some(_) => view(h),
                    None => error("a scene has to be archived before it can be deleted"),
                },
                None => error("that scene id is not one this project has"),
            }
        }

        // **Copies of several shots landed in one scene, as one undo step.**
        // `copyshots <a,b,c> <scene> [after]` — the app's "copy these shots and
        // paste them there". Not a cell paste: a shot carries its frames and
        // everything else, and pasting its columns as text loses all of it.
        "copyshots" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let placements: Vec<_> = parts
                .next()
                .unwrap_or("")
                .split(',')
                .filter_map(id_from)
                .collect();
            let scene = parts.next().and_then(id_from);
            let after = parts.next().and_then(id_from);
            match scene {
                Some(scene) if !placements.is_empty() => {
                    h.project
                        .doc_mut()
                        .duplicate_shots_into(&placements, scene, after);
                    view(h)
                }
                _ => error("that is not a scene this project has"),
            }
        }
        "movescene" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let (placement, scene) = (
                parts.next().and_then(id_from),
                parts.next().and_then(id_from),
            );
            match (placement, scene) {
                (Some(placement), Some(scene)) => {
                    h.project.doc_mut().move_placement_to_scene(placement, scene);
                    view(h)
                }
                _ => error("that is not a shot and a scene this project has"),
            }
        }

        // readheading <line> — what a typed slug line says, without writing
        // anything. The New scene box on the Mac shows the parts back as they
        // are typed, and it asks the engine rather than reading the line
        // itself, so a heading typed by hand and a heading read out of a draft
        // are never understood two different ways.
        "readheading" => {
            let scene = shotlister_engine::script::read_heading(parts.next().unwrap_or(""));
            let mut j = Json::new();
            j.obj()
                .kv("number", scene.number.as_deref().unwrap_or(""))
                .kv("intExt", &scene.int_ext)
                .kv("location", &scene.location)
                .kv("timeOfDay", &scene.time_of_day)
                .end_obj();
            j.finish()
        }

        // addscene <number> [<field> <value>]… — a scene and everything a
        // person typed about it, as **one** change.
        //
        // It used to take a number and nothing else, which is why a new scene
        // arrived blank and had to be opened and filled in afterwards. The
        // pairs are the same field names `set` takes, plus `place`, which is
        // an assignment rather than a word: it points the scene at a location
        // record.
        //
        // **No `day` here on purpose.** A scene's shoot day lives on its
        // *shots* — `schedule_scene` seats every placement — so a scene that
        // has none cannot be put on a day at all, and a pair that quietly did
        // nothing would be worse than no pair.
        //
        // One transaction, because it is one gesture: filling the box in and
        // pressing Add is a single thing a person did, and ⌘Z should take back
        // a single thing.
        "addscene" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let number = parts.next().unwrap_or("").trim().to_string();
            if number.is_empty() {
                return error("a scene needs a number");
            }
            let extras: Vec<(String, String)> = {
                let rest: Vec<&str> = parts.collect();
                rest.chunks(2)
                    .filter(|pair| pair.len() == 2 && !pair[1].trim().is_empty())
                    .map(|pair| (pair[0].to_string(), pair[1].to_string()))
                    .collect()
            };
            let d = h.project.doc_mut();
            let tx = d.begin("Add scene");
            let scene = d.create_scene(&number);
            let mut problem = None;
            for (field, value) in &extras {
                match field.as_str() {
                    "place" => match id_from(value) {
                        Some(place) => {
                            d.add_scene_location(scene, place);
                        }
                        None => {
                            problem = Some(error("that is not a location this project has"));
                        }
                    },
                    _ => problem = set_field(d, scene, field, value),
                }
                if problem.is_some() {
                    break;
                }
            }
            d.end(tx);
            if let Some(p) = problem {
                return p;
            }
            view(h)
        }

        "addshot" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let scene = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that scene id is not one this project has"),
            };
            // Created and seated in one transaction — control-return is one
            // gesture, and one gesture is one undo.
            let after = parts.next().and_then(id_from);
            h.project.doc_mut().add_shot_to_scene_after(scene, after);
            view(h)
        }

        // addunit <label> <colour> — a new camera, born with the colour it
        // will wear in every cell that names it.
        "addunit" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let label = parts.next().unwrap_or("").trim();
            if label.is_empty() {
                return error("a camera needs a name");
            }
            let colour = parts.next().unwrap_or("").trim();
            h.project.doc_mut().create_unit_coloured(label, "", colour);
            view(h)
        }

        // unit name|colour|remove <unitId> [value] — the rest of a camera's
        // life, after `addunit` gave it one.
        //
        // **Shaped like `day`, on purpose.** That command took `<verb> <id>
        // [value]` a few hours before this one was written, and two records
        // that answer the same three questions should not answer them in two
        // different grammars. `addunit` keeps its own name because it predates
        // both and the phone sends it.
        //
        // Removing reports how many shots named the camera, in the same line
        // shape as everything else that costs something, so the Mac can say the
        // number *before* it asks.
        "unit" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let what = parts.next().unwrap_or("");
            let unit = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that camera id is not one this project has"),
            };
            match what {
                "name" => {
                    let label = parts.next().unwrap_or("");
                    if !h.project.doc_mut().rename_unit(unit, label) {
                        return error("a camera needs a name");
                    }
                }
                "colour" => {
                    let colour = parts.next().unwrap_or("");
                    if !h.project.doc_mut().recolour_unit(unit, colour) {
                        return error("that camera id is not one this project has");
                    }
                }
                "remove" => {
                    h.project.doc_mut().delete_unit(unit);
                }
                // unit sensor <id> <w> <h> <name…> — the sensor he typed for
                // this camera, in mm; a width of 0 clears it.
                "sensor" => {
                    // The spec sheet's sensor mode stands for this camera
                    // (piece E): Studio shows it and never types over it.
                    if h.project.doc().sensor_from_sheet(unit) {
                        return error("this camera's sensor comes from the spec sheet");
                    }
                    let w: f64 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0.0);
                    let hgt: f64 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0.0);
                    let name = parts.next().unwrap_or("");
                    if !h.project.doc_mut().set_unit_sensor(unit, name, w, hgt) {
                        return error("that camera id is not one this project has");
                    }
                }
                other => return error(&format!("no camera command called {other}")),
            }
            view(h)
        }

        // addsequence <title> — a sequence is the one grouping the *script*
        // does not dictate: it is his own reading of the film ("the drive",
        // "girlfriend breakup"), so it has to be possible to make one by
        // naming it, wherever the name is being typed. Returns the view, with
        // the new record in it; the shell then points the scene at it.
        // `floorplan <path>` — a scanned room, turned into something an app can
        // draw. With no path it hands back the hand-built sample room, which is
        // the only way to see a floor plan on a machine with no LiDAR in it.
        //
        // **The arithmetic is the engine's, on his instruction of 2026-08-21**:
        // *"iOS has been handling the floor plan creation. I just need you to
        // display it, or you guys should just share the same engine."* The Mac
        // and the phone both draw from this one answer; only the drawing itself
        // is written twice, because only the drawing genuinely differs.
        "floorplan" => {
            let path = parts.next().unwrap_or("").trim().to_string();
            let plan = if path.is_empty() {
                shotlister_engine::room::sample()
            } else {
                match std::fs::read_to_string(&path) {
                    Ok(text) => shotlister_engine::room::read(&text),
                    Err(_) => return error("that scan could not be read"),
                }
            };
            match plan {
                Some(plan) => shotlister_engine::room::as_json(&plan).encode(),
                None => error("there is no room in that file"),
            }
        }

        // registerscans — the rooms the phone has just written into
        // `locations/<folder>/scans/`, into the film now rather than at the
        // next sync. The same call `syncplan` makes first; here so a phone
        // can show a room back the moment it is scanned. Ref 939.
        "registerscans" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let papers = h.project.register_attachments().unwrap_or(0);
            match h.project.register_scans() {
                Ok(added) => {
                    if added + papers > 0 {
                        let _ = h.project.save();
                    }
                    view(h)
                }
                Err(_) => error("the scans folder could not be read"),
            }
        }

        // renameuse <mediaRefId> <name> — what this use of a file is called,
        // keeping the extension the stored bytes have. A scanned room is two
        // uses sharing a stem, and renaming the room is renaming both. Ref 939.
        "renameuse" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that file is not one this project has"),
            };
            let name = parts.next().unwrap_or("").trim();
            if name.is_empty() {
                return error("a name is needed");
            }
            let stored = h.project.doc().media_ref_name(mref);
            let ext = stored.rsplit('.').next().unwrap_or("").to_string();
            // The extension is the stored file's, whatever the name says —
            // `Kitchen 2.0` is a name, not a request to become a `.0` file.
            let named = if ext.is_empty() || !stored.contains('.') {
                name.to_string()
            } else {
                format!("{name}.{ext}")
            };
            h.project.doc_mut().set_media_ref_name(mref, &named);
            view(h)
        }

        // -------------------------------------------------------- locations
        //
        // Ref 57. The phone has been writing `locations/<id>/location.json`
        // beside the project because there was nowhere in the engine to put a
        // location; these are that somewhere. Field names match its JSON, so
        // reading those files in is a copy rather than a translation.
        //
        // **These were `addplace`/`setplace`/`deleteplace`/`sceneplace` until
        // 2026-08-21.** `place` was already taken, a few hundred lines up, for
        // putting a shot on a shoot day — one word, two meanings, in one
        // dispatch table. Renamed on his call that the feature is "Locations".

        // addlocation <name>
        "addlocation" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let name = parts.next().unwrap_or("").trim();
            if name.is_empty() {
                return error("a location needs a name");
            }
            h.project.doc_mut().create_location(name);
            view(h)
        }

        // addarea <parentLocationId> <name> — a room inside a location.
        // Ref 269: one house, one address, many rooms each with their own
        // scan and their own photographs.
        "addarea" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let parent = parts.next().and_then(id_from);
            let name = parts.next().unwrap_or("").trim().to_string();
            if name.is_empty() {
                return error("an area needs a name");
            }
            match parent {
                Some(parent) if h.project.doc().get(parent).is_some() => {
                    h.project.doc_mut().create_location_in(parent, &name);
                    view(h)
                }
                _ => error("that is not a location this project has"),
            }
        }

        // movelocation <locationId> <parentLocationId|""> — put a location
        // inside another, or let it out to stand on its own.
        "movelocation" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let place = parts.next().and_then(id_from);
            let parent = parts.next().and_then(id_from);
            match place {
                Some(place) => {
                    if h.project.doc_mut().set_location_parent(place, parent) {
                        view(h)
                    } else {
                        // Refused rather than failed: one level deep, always.
                        error("a location can only hold locations that hold none")
                    }
                }
                None => error("that is not a location this project has"),
            }
        }

        // setlocation <locationId> <field> <value> — name, address,
        // latitude, longitude, notes, captured_by, folder.
        "setlocation" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let (id, field, value) = (
                parts.next().and_then(id_from),
                parts.next().unwrap_or("").to_string(),
                parts.next().unwrap_or("").to_string(),
            );
            let Some(id) = id else {
                return error("that is not a location this project has");
            };
            let field = match field.as_str() {
                "name" | "label" => f::LABEL,
                "address" => f::ADDRESS,
                "latitude" => f::LATITUDE,
                "longitude" => f::LONGITUDE,
                "notes" => f::NOTES,
                "captured_by" | "capturedBy" => f::CAPTURED_BY,
                "created_at" | "createdAt" => f::CREATED_AT,
                "folder" => f::FOLDER,
                "drive_folder" | "driveFolder" => f::DRIVE_FOLDER,
                // **Whether this place's photographs go to Drive** — Ref 229.
                // `1` or `0`; clearing it puts the place back to undecided,
                // which is not the same as off.
                "sync_with_drive" | "syncWithDrive" => f::SYNC_WITH_DRIVE,
                _ => return error("a location does not carry that"),
            };
            h.project.doc_mut().set(id, field, value.as_str());
            view(h)
        }

        // retiredlocations — the Drive folders of locations that have been
        // deleted. `[{id, driveFolder}]`. The bridge asks before it turns a
        // loose folder in Drive into a location: one of these is a deletion's
        // leftover, to be moved aside, not a place somebody made by hand.
        "retiredlocations" => {
            let mut j = Json::new();
            j.arr();
            for (id, held) in h.project.doc().retired_drive_folders() {
                j.obj()
                    .kv("id", &id.0.to_string())
                    .kv("driveFolder", &held)
                    .end_obj();
            }
            j.end_arr();
            j.finish()
        }

        // forgetretired <locationId> — the bridge has moved that deleted
        // location's folder aside; the tombstone stops naming it.
        "forgetretired" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            match parts.next().and_then(id_from) {
                Some(id) => {
                    h.project.doc_mut().forget_retired_drive_folder(id);
                    ok()
                }
                None => error("that is not a place this project has"),
            }
        }

        // deletelocation <locationId> — the scenes lose the pointer and
        // nothing else.
        "deletelocation" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            match parts.next().and_then(id_from) {
                Some(id) => {
                    h.project.doc_mut().delete_location(id);
                    view(h)
                }
                None => error("that is not a place this project has"),
            }
        }

        // ---- edit references (the Edit Reference mod) -----------------------
        //
        // A name and a run of shots; its clip or stills reach it through
        // `paste`, as a board's pictures do. Every command answers the view.

        // addeditref <name> <shotId,shotId,…>
        "addeditref" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let name = parts.next().unwrap_or("").to_string();
            let shots: Vec<Id> = parts.next().unwrap_or("").split(',').filter_map(id_from).collect();
            if shots.is_empty() {
                return error("an edit reference needs shots");
            }
            h.project.doc_mut().create_edit_ref(&name, &shots);
            view(h)
        }

        // editrefshots <id> <shotId,…> · editrefstarts <id> <s,s,…> ·
        // renameeditref <id> <name> · editreflink <id> <url> · deleteeditref <id>
        "editrefshots" | "editrefstarts" | "renameeditref" | "editreflink" | "deleteeditref" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(id) = parts.next().and_then(id_from).filter(|i| h.project.doc().is_edit_ref(*i)) else {
                return error("that is not an edit reference this project has");
            };
            let said = parts.next().unwrap_or("");
            let doc = h.project.doc_mut();
            match cmd {
                "editrefshots" => {
                    let shots: Vec<Id> = said.split(',').filter_map(id_from).collect();
                    if shots.is_empty() {
                        return error("an edit reference needs shots");
                    }
                    doc.set_edit_ref_shots(id, &shots);
                }
                "editrefstarts" => {
                    let starts: Vec<f64> = said.split(',').filter_map(|x| x.trim().parse().ok()).collect();
                    if !doc.set_edit_ref_starts(id, &starts) {
                        return error("one start for each shot, in order");
                    }
                }
                "renameeditref" => doc.rename_edit_ref(id, said),
                "editreflink" => doc.set_edit_ref_link(id, said),
                _ => doc.delete_edit_ref(id),
            }
            view(h)
        }

        // ---- mood boards ---------------------------------------------------
        //
        // A board is a name and a wall. Pictures reach it through the media
        // commands every other owner already uses — there is deliberately no
        // `addboardphoto`, because a board is an owner like any other and a
        // second door onto the same act is how two doors drift apart.

        // addboard <name>
        "addboard" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let name = parts.next().unwrap_or("").trim();
            if name.is_empty() {
                return error("a mood board needs a name");
            }
            h.project.doc_mut().create_board(name);
            view(h)
        }

        // renameboard <boardId> <name>
        "renameboard" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(id) = parts.next().and_then(id_from) else {
                return error("that is not a mood board this project has");
            };
            let name = parts.next().unwrap_or("").trim();
            if name.is_empty() {
                return error("a mood board needs a name");
            }
            h.project.doc_mut().rename_board(id, name);
            view(h)
        }

        // moveboard <boardId> <index> — a reference board dragged to a new
        // place in the sidebar, the index counted with it lifted out.
        "moveboard" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(id) = parts.next().and_then(id_from) else {
                return error("that is not a mood board this project has");
            };
            let index: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
            h.project.doc_mut().move_board_to(id, index);
            view(h)
        }

        // deleteboard <boardId> — takes the wall, never the photographs. They
        // are addressed by their contents and may hang elsewhere too.
        "deleteboard" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            match parts.next().and_then(id_from) {
                Some(id) => {
                    h.project.doc_mut().delete_board(id);
                    view(h)
                }
                None => error("that is not a mood board this project has"),
            }
        }

        // addsceneboard <sceneId> <boardId> — link one more mood board to
        // this scene, kept after the ones already there. Ref SL-348.
        "addsceneboard" | "removesceneboard" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(scene) = parts.next().and_then(id_from) else {
                return error("that is not a scene this project has");
            };
            let Some(board) = parts.next().and_then(id_from) else {
                return error("that is not a mood board this project has");
            };
            if cmd == "addsceneboard" {
                h.project.doc_mut().add_scene_board(scene, board);
            } else {
                h.project.doc_mut().remove_scene_board(scene, board);
            }
            view(h)
        }

        // addscenelocation <sceneId> <locationId> — one more place this scene
        // is shot at, kept after the ones already on it. Ref 303.
        "addscenelocation" | "removescenelocation" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(scene) = parts.next().and_then(id_from) else {
                return error("that is not a scene this project has");
            };
            let Some(place) = parts.next().and_then(id_from) else {
                return error("that is not a location this project has");
            };
            if cmd == "addscenelocation" {
                h.project.doc_mut().add_scene_location(scene, place);
            } else {
                h.project.doc_mut().remove_scene_location(scene, place);
            }
            view(h)
        }

        // scenelocation <sceneId> <locationId|""> — where the crew actually
        // goes. Never touches the scene's `location`, the script's own word.
        // **Setting one replaces them all**: it is the door for "this scene is
        // shot here", and a scene shot in two places is built up with
        // `addscenelocation`.
        "scenelocation" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let scene = parts.next().and_then(id_from);
            let place = parts.next().and_then(id_from);
            match scene {
                Some(scene) => {
                    h.project.doc_mut().set_scene_location(scene, place);
                    view(h)
                }
                None => error("that is not a scene this project has"),
            }
        }

        // deletesequence <id> — the section goes; its scenes stay and leave
        // it. Answers how many left, then the view.
        "deletesequence" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            match parts.next().and_then(id_from) {
                Some(seq) => {
                    h.project.doc_mut().delete_sequence(seq);
                    view(h)
                }
                None => error("that is not a sequence this project has"),
            }
        }

        // tieshot <shot> <section|""> <from> <to> — the shot quotes that
        // UTF-16 range of the section's script; `to` at or below `from`
        // unties. Answers the view.
        "tieshot" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(shot) = parts.next().and_then(id_from) else {
                return error("that shot id is not one this project has");
            };
            let section = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            let from: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
            let to: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
            h.project.doc_mut().tie_shot(shot, section, from, to);
            view(h)
        }

        // toggletie <shot> <section|""> <from> <to> [<from> <to> …] — the
        // highlighter, in one or more pieces: a
        // range the shot already holds, every word, is let go; anything else
        // is added to its stretches. Answers the view.
        //
        // untieat <shot> <at> — the stretch of the shot's under that offset
        // is let go. Answers the view.
        "toggletie" | "untieat" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(shot) = parts.next().and_then(id_from) else {
                return error("that shot id is not one this project has");
            };
            if cmd == "untieat" {
                let at: usize = parts.next().unwrap_or("0").parse().unwrap_or(0);
                h.project.doc_mut().untie_at(shot, at);
            } else {
                // Pairs after the section: a selection in several pieces.
                let section = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
                let numbers: Vec<usize> = parts.map(|p| p.parse().unwrap_or(0)).collect();
                let ranges: Vec<(usize, usize)> = numbers.chunks(2).filter_map(|c| match c {
                    [a, b] => Some((*a, *b)),
                    _ => None,
                }).collect();
                h.project.doc_mut().toggle_ties(shot, section, &ranges);
            }
            view(h)
        }

        // sceneafter <scene> [<after>] — the scene moves to sit just after
        // `after`, or first when none is given. Order only; numbers stay.
        "sceneafter" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(scene) = parts.next().and_then(id_from) else {
                return error("that scene id is not one this project has");
            };
            let after = parts.next().filter(|s| !s.is_empty()).and_then(id_from);
            h.project.doc_mut().move_scene_after(scene, after);
            view(h)
        }

        "addsequence" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let title = parts.next().unwrap_or("").trim();
            if title.is_empty() {
                return error("a sequence needs a name");
            }
            h.project.doc_mut().create_sequence(title);
            view(h)
        }

        // addcolumn <kind> <label> — a column of the project's own
        "addcolumn" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let kind = parts.next().unwrap_or("").trim();
            let label = parts.next().unwrap_or("").trim();
            match h.project.doc_mut().add_column(label, kind) {
                Some(_) => view(h),
                None => error("a column needs a name and a kind this build knows"),
            }
        }

        // deletecolumn <field> — the column and everything written in it, in
        // one breath so it is one ⌘Z. Only a column the project made.
        "deletecolumn" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let field = parts.next().unwrap_or("").trim().to_string();
            if !h.project.doc_mut().delete_column(&field) {
                return error("that is not a column this project made");
            }
            view(h)
        }

        // renamecolumn <field> <label> — the values stay where they are
        "renamecolumn" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let field = parts.next().unwrap_or("").trim().to_string();
            let label = parts.next().unwrap_or("").trim();
            if label.is_empty() {
                return error("a column cannot be renamed to nothing");
            }
            h.project.doc_mut().rename_column(&field, label);
            view(h)
        }

        // ---- the lists ------------------------------------------------------
        "lists" => lists(h),
        "colours" => colours(h),

        // gallery [text] — every picture the project already holds, grouped by
        // where it is used.
        //
        // His ask, Ref 228: when adding a picture anywhere, be able to pull one
        // that is already in the project rather than finding the file again.
        // Grouped, never one undifferentiated wall — a section per scene, per
        // shot and per location, in the order the sidebar has them, and an
        // optional word to narrow by filename.
        //
        // Nothing is copied by using one of these: a picture is filed by its
        // contents, so attaching the same hash somewhere else is one file on
        // disk and one in Drive however many places point at it. `uses` says
        // how many places that is, which is what lets a shell answer both of
        // the questions left open on that row — whether a picture says it is
        // used elsewhere, and whether removing it should warn.
        "gallery" => {
            let wanted = parts.next().unwrap_or("").trim().to_lowercase();
            let p = &h.project;
            let d = p.doc();

            // How many places point at each file, counted once for the whole
            // answer rather than per group.
            let mut uses: std::collections::HashMap<Id, i64> = std::collections::HashMap::new();
            for record in d.store().of_kind(&Kind::MediaRef) {
                if let Some(media) = record.ref_id(f::MEDIA) {
                    *uses.entry(media).or_insert(0) += 1;
                }
            }

            let mut j = Json::new();
            j.obj().key("groups").arr();
            let mut shown = 0i64;

            let group = |j: &mut Json, kind: &str, id: Id, label: &str, parent: &str| {
                let refs = d.media_refs(id);
                let mut items: Vec<(Id, Id)> = Vec::new();
                for mref in refs {
                    let Some(media) = d.get(mref).and_then(|r| r.ref_id(f::MEDIA)) else {
                        continue;
                    };
                    let filename = d
                        .get(media)
                        .and_then(|r| r.text(f::FILENAME))
                        .unwrap_or_default()
                        .to_lowercase();
                    if wanted.is_empty() || filename.contains(&wanted) {
                        items.push((mref, media));
                    }
                }
                // A section with nothing in it is noise, especially once a
                // word has been typed.
                if items.is_empty() {
                    return 0;
                }
                let count = items.len() as i64;
                j.obj()
                    .kv("kind", kind)
                    .kv("id", &id.0.to_string())
                    .kv("label", label)
                    // **Which group this one sits inside** — a shot names its
                    // scene, so the picker can fold a scene up and take its
                    // shots with it. Empty for a group that stands alone.
                    .kv("parent", parent)
                    .key("items")
                    .arr();
                for (mref, media) in items {
                    j.obj()
                        .kv("ref", &mref.0.to_string())
                        .kv("hash", &text(p, media, f::HASH))
                        .kv("filename", &d.media_ref_name(mref))
                        .kv(
                            "kind",
                            d.media_kind(media).unwrap_or(MediaKind::Other).as_str(),
                        )
                        .kv("caption", &text(p, mref, f::CAPTION))
                        .ki("uses", *uses.get(&media).unwrap_or(&1))
                        .end_obj();
                }
                j.end_arr().end_obj();
                count
            };

            // Scenes in story order, each one followed by its own shots, so
            // the picker reads down the film the way the sidebar does.
            for scene in d.scenes_in_order() {
                let heading = d.scene_heading_shown(scene).unwrap_or_default();
                let number = text(p, scene, f::NUMBER);
                let label = if heading.is_empty() {
                    number.clone()
                } else {
                    format!("{number} {heading}").trim().to_string()
                };
                shown += group(&mut j, "scene", scene, &label, "");
                for placement in d.placements_in_scene(scene) {
                    let Some(shot) = d.get(placement).and_then(|r| r.ref_id(f::SHOT)) else {
                        continue;
                    };
                    let label = d.display_number(placement).unwrap_or_default();
                    shown += group(&mut j, "shot", shot, &label, &scene.0.to_string());
                }
            }
            // **Mood boards belong in the picker too** — his report,
            // 2026-08-24: they were missing from it, which is exactly the
            // "organised by mood board, location, or scene" he asked for in
            // Ref 228 and did not get, because boards did not exist yet when
            // this command was written.
            for board in d.boards_in_order() {
                let label = d.board_name(board);
                shown += group(&mut j, "board", board, &label, "");
            }
            for place in d.locations_in_order() {
                let label = d.location_full_name(place);
                shown += group(&mut j, "location", place, &label, "");
            }

            j.end_arr().ki("pictures", shown).end_obj();
            j.finish()
        }

        // missing — the frames whose picture is not in this folder.
        //
        // A frame's record and its picture travel separately between devices,
        // so a record can be here while the bytes are still on their way, or
        // never come at all. The apps draw a grey box for those and could not
        // say why. This answers by hash, which is what a drawn frame already
        // carries, so a shell can mark exactly the right ones.
        "missing" => {
            let absent = h.project.missing_media();
            let d = h.project.doc();
            // Deleted from the Media window is today's fact, even while an
            // old version is on screen: that version never heard of the
            // delete, and would call the picture missing rather than gone.
            let today = match (&h.looking, h.showing_old) {
                (Some(looking), true) => &looking.doc,
                _ => d,
            };
            let gone = today.gone_media();
            let gone_hashes: std::collections::HashSet<&str> =
                gone.iter().map(|g| g.hash.as_str()).collect();
            let mut j = Json::new();
            j.obj().key("missing").arr();
            for media in absent {
                if let Some(record) = d.get(media) {
                    if gone_hashes.contains(record.text(f::HASH).unwrap_or_default()) {
                        continue;
                    }
                    j.obj()
                        .kv("hash", record.text(f::HASH).unwrap_or_default())
                        .kv("filename", record.text(f::FILENAME).unwrap_or_default())
                        .end_obj();
                }
            }
            for g in &gone {
                j.obj()
                    .kv("hash", &g.hash)
                    .kv("filename", &g.filename)
                    .kb("gone", true)
                    .end_obj();
            }
            j.end_arr().end_obj();
            j.finish()
        }

        // shelf — every picture and clip in the film, biggest first, with
        // where each is used, how many saved versions show it, and the names
        // deleted ones left behind. The Media window. (`engine::shelf`)
        //
        // `bytes` is what it takes on this device — stored copy, poster,
        // strips and original — because that is what deleting gives back.
        "shelf" => {
            let sizes = h.project.stored_sizes();
            let d = h.project.doc();
            let size_of = |hash: &str| -> i64 {
                sizes.get(hash.get(..18).unwrap_or("")).copied().unwrap_or(0) as i64
            };
            let shelf = d.shelf();
            let mut total = 0i64;
            let mut unused = 0i64;
            let mut unused_bytes = 0i64;
            let mut j = Json::new();
            j.obj().key("items").arr();
            let mut rows: Vec<(i64, &shotlister_engine::shelf::Shelved)> =
                shelf.iter().map(|s| (size_of(&s.hash), s)).collect();
            rows.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.filename.cmp(&b.1.filename)));
            for (bytes, s) in rows {
                total += bytes;
                if !s.used() {
                    unused += 1;
                    unused_bytes += bytes;
                }
                j.obj()
                    .kv("media", &s.media.0.to_string())
                    .kv("hash", &s.hash)
                    .kv("filename", &s.filename)
                    .kv("kind", s.kind.as_str())
                    .ki("bytes", bytes)
                    .ki("width", s.width)
                    .ki("height", s.height)
                    .kn("seconds", s.seconds)
                    .ki("versions", s.versions as i64)
                    .key("uses")
                    .arr();
                for u in &s.uses {
                    j.obj()
                        .kv("ref", &u.media_ref.0.to_string())
                        .kv("owner", &u.owner.0.to_string())
                        .kv("kind", u.kind)
                        .kv("label", &u.label)
                        .kv("detail", &u.detail)
                        .kv("scene", &u.scene.map(|s| s.0.to_string()).unwrap_or_default())
                        .end_obj();
                }
                j.end_arr().end_obj();
            }
            j.end_arr().key("gone").arr();
            for g in d.gone_media() {
                j.obj()
                    .kv("media", &g.media.0.to_string())
                    .kv("hash", &g.hash)
                    .kv("filename", &g.filename)
                    .ki("bytes", g.bytes as i64)
                    .ki("on", g.on)
                    .end_obj();
            }
            j.end_arr()
                .ki("count", shelf.len() as i64)
                .ki("bytes", total)
                .ki("unused", unused)
                .ki("unusedBytes", unused_bytes)
                .end_obj();
            j.finish()
        }

        // deletemedia <id>… | deletemedia unused — delete pictures for real.
        // Every use goes, the record stays as a name, the files go from this
        // device now. Answers what was freed and the stored names removed.
        // Not undoable. (`engine::shelf`, `storage::delete_media`)
        "deletemedia" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let rest: Vec<&str> = parts.collect();
            let ids: Vec<Id> = if rest.first().map(|w| w.trim()) == Some("unused") {
                h.project.doc().unused_media()
            } else {
                rest.iter().filter_map(|w| id_from(w)).collect()
            };
            match h.project.delete_media(&ids) {
                Ok((freed, names)) => {
                    let mut j = Json::new();
                    j.obj()
                        .ki("deleted", freed.pictures as i64)
                        .ki("freedBytes", freed.bytes as i64)
                        .key("removed")
                        .arr();
                    for n in names {
                        j.str(&n);
                    }
                    j.end_arr().end_obj();
                    j.finish()
                }
                Err(e) => error(&e.message()),
            }
        }

        // list rename <field> <from> <to> | list remove <field> <value>
        "list" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let action = parts.next().unwrap_or("");
            let field = parts.next().unwrap_or("").to_string();
            match action {
                "rename" => {
                    let from = parts.next().unwrap_or("").to_string();
                    let to = parts.next().unwrap_or("").trim().to_string();
                    if to.is_empty() {
                        return error("a value cannot be renamed to nothing");
                    }
                    // renaming reaches every shot using the old value, which is
                    // the whole reason to rename rather than add and delete
                    let touched = h
                        .project
                        .doc_mut()
                        .rename_vocabulary_value(&field, &from, &to);
                    let mut j = Json::new();
                    j.obj().ki("changed", touched as i64).end_obj();
                    j.finish()
                }
                "remove" => {
                    let value = parts.next().unwrap_or("").to_string();
                    let touched = h.project.doc_mut().remove_vocabulary_value(&field, &value);
                    let mut j = Json::new();
                    j.obj().ki("changed", touched as i64).end_obj();
                    j.finish()
                }
                "add" => {
                    let value = parts.next().unwrap_or("").trim().to_string();
                    if value.is_empty() {
                        return error("nothing to add");
                    }
                    // Refused rather than silently ignored. A lock the person
                    // set is a decision, and the way past it is to unlock —
                    // one click, on the same page the lock is on.
                    if h.project.doc().vocabulary_locked(&field) {
                        return error("that list is locked — unlock it to add to it");
                    }
                    h.project.doc_mut().learn(&field, &value);
                    ok()
                }
                // list colour <field> <term> <RRGGBB|> — Ref 55. An empty
                // colour hands the term back to the hash, which is the only
                // way out of a colour you have decided against.
                "colour" => {
                    let term = parts.next().unwrap_or("").trim().to_string();
                    if term.is_empty() {
                        return error("nothing to colour");
                    }
                    let hex = parts.next().unwrap_or("").trim().to_string();
                    h.project.doc_mut().set_term_colour(&field, &term, &hex);
                    ok()
                }
                // list lock <field> <0|1>
                "lock" => {
                    let on = parts.next().unwrap_or("1").trim() != "0";
                    h.project.doc_mut().set_vocabulary_locked(&field, on);
                    ok()
                }
                other => error(&format!("no list command called {other}")),
            }
        }

        // column <name> <0|1>
        "column" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let name = parts.next().unwrap_or("").to_string();
            let visible = parts.next().unwrap_or("1") != "0";
            h.project.doc_mut().set_column_visible(&name, visible);
            view(h)
        }

        // ---- sharing --------------------------------------------------------
        // share <path> <made-on> <notes 0|1> <struck 0|1> <technical 0|1>
        //
        // One file with the frames inside it. The date comes from the app
        // because the engine has no calendar and should not invent one.
        "share" => {
            let path = parts.next().unwrap_or("");
            if path.is_empty() {
                return error("no path to write the page to");
            }
            let made_on = parts.next().unwrap_or("");
            let mut options = ShareOptions::made_on(made_on);
            if parts.next().unwrap_or("1") == "0" {
                options = options.without_notes();
            }
            if parts.next().unwrap_or("1") == "0" {
                options = options.without_struck();
            }
            if parts.next().unwrap_or("1") == "0" {
                options = options.without_technical();
            }

            // a share page carries what you were looking at, filters and all
            let p = &h.project;
            let sheet = p.doc().sheet(&h.query());
            let frames = |media: Id| -> Option<ShareFrame> {
                let (bytes, ext) = frame_bytes(p, media)?;
                let mime = match ext.as_str() {
                    "jpg" | "jpeg" => "image/jpeg",
                    "heic" => "image/heic",
                    _ => "image/png",
                };
                let (width, height) = image_dimensions(&bytes, &ext);
                Some(ShareFrame {
                    bytes,
                    mime: mime.to_string(),
                    width: width as f64,
                    height: height as f64,
                })
            };
            let html = share::page(&sheet, &frames, &options);
            match write_whole(std::path::Path::new(path), html.as_bytes()) {
                Ok(()) => {
                    let mut j = Json::new();
                    j.obj().kv("path", path).end_obj();
                    j.finish()
                }
                Err(e) => error(&format!("could not write the page: {e}")),
            }
        }

        // print <document|table|storyboard|avscript> <path> [key=value ...]
        // — writes the page the PDF is made from.
        //
        // **Named options, not positions.** This grew four trailing
        // positional arguments in two days (scenes, columns, scale, and then
        // a day), each one forcing every caller that wanted the *last* of
        // them to pass empty placeholders for the ones between. Keys instead:
        //
        //   scenes=<id>[,<id>...]  exactly those scenes, whatever is searched
        //                          or filtered on screen — a scene's own PDF
        //                          asks for that scene and nothing else
        //   day=<id>|unscheduled   one shoot day's shots, for per-day export
        //   columns=<name>[,...]   overrides the columns on screen — the
        //                          export dialog's own picker, wider or
        //                          narrower than the Table view
        //   scale=<f64>            multiplies the root font size, 1.0 normal
        //   frames=<size>          small|medium|large — how much of the table
        //                          a picture column takes, and how many
        //                          storyboard cards stand across a row
        //
        // `scenes` and `day` both narrow from the whole project rather than
        // from what is on screen; given neither, the page follows the live
        // filters exactly as the share page always has.
        //
        // The engine draws both pages and the app turns them into a PDF with
        // the system, which sets type and breaks pages better than anything
        // worth hand-writing here. Frames go in as data so the file stands on
        // its own and the printer never waits on the disk.
        "print" => {
            let which = parts.next().unwrap_or("document");
            let path = parts.next().unwrap_or("");
            if path.is_empty() {
                return error("no path to write the page to");
            }
            let options = Options::read(parts);
            let scale = options.number("scale").filter(|s| *s > 0.0).unwrap_or(1.0);
            // How much room a picture gets — `small`, `medium`, `large`. An
            // older shell that does not say gets the middle.
            let size = FrameSize::read(options.get("frames").unwrap_or(""));
            // `widths=description:1.5,notes:0.7` — his own say over the
            // printed table's columns, as a multiplier on the weight the page
            // already gives each one. A multiplier so the shell never keeps a
            // copy of those weights; the page normalises at the end, so the
            // columns cannot stop adding up to a sheet of paper.
            let mut widths = ColumnWidths::read(options.get("widths").unwrap_or(""));
            // `shares=number:4.1,image:18.2,…` — Auto's own widths, exactly,
            // as `tablelayout` handed them out. They win over `widths=`.
            if let Some(shares) = options.get("shares").filter(|s| !s.is_empty()) {
                widths = ColumnWidths::exact(shares);
                widths.fitted = options.get("fitted") == Some("1");
            }

            let p = &h.project;
            let query = match options.query_narrowing(h) {
                Ok(q) => q,
                Err(problem) => return problem,
            };
            let mut sheet = p.doc().sheet(&query);
            if let Some(columns) = options.list("columns") {
                sheet.columns = columns;
            }
            sheet.day_pages = options.get("daypages") == Some("1");
            // **A shot's baked Print Frame goes in as its one picture**, when
            // the Mac has baked a current one and its bytes are here; a shot
            // without one prints exactly as before. (`engine/src/printframe.rs`)
            sheet.fill_print_frames(|hash, ext| {
                let bytes = p.read_proxy(hash, ext).ok().flatten().filter(|b| !b.is_empty())?;
                let mime = if ext == "png" { "image/png" } else { "image/jpeg" };
                let (width, height) = image_dimensions(&bytes, ext);
                Some((share::data_uri(&bytes, mime), width as f64, height as f64))
            });
            let frames = |media: Id, trim: html::Trim| -> Option<html::Frame> {
                // The strip first, then the single frame it falls back to.
                // Only the printed page asks this way: a spreadsheet cell and
                // the share page both want one picture. **The trim comes with
                // the ask** because it belongs to the use, not to the file.
                let strip = strip_bytes(p, media, trim);
                let moments: u8 = if strip.is_some() { 4 } else { 1 };
                let (bytes, ext) = strip.or_else(|| frame_bytes(p, media))?;
                let mime = match ext.as_str() {
                    "jpg" | "jpeg" => "image/jpeg",
                    "heic" => "image/heic",
                    _ => "image/png",
                };
                // **The shape goes with the bytes.** Only this side has the
                // file, and without its ratio the page cannot work out which
                // part of it a crop keeps. `(0, 0)` for a format nothing here
                // reads — the page then covers the box and keeps the middle,
                // which is what it always did.
                let (width, height) = image_dimensions(&bytes, &ext);
                Some(html::Frame {
                    src: share::data_uri(&bytes, mime),
                    width: width as f64,
                    height: height as f64,
                    moments,
                })
            };

            let style = match h.project.doc().project_id() {
                Some(project) => shotlister_engine::docstyle::of(h.project.doc(), project),
                None => shotlister_engine::docstyle::Style::standard_style(),
            };
            let html = match which {
                // The diagram's own page — one sheet a scene, its plan and
                // its shot key. The scenes asked for, or every scene with one.
                "diagram" => {
                    let title = h.project.doc().project_id()
                        .and_then(|id| h.project.doc().get(id))
                        .and_then(|r| r.text(f::TITLE).map(String::from))
                        .unwrap_or_default();
                    // A picture laid under a plan travels inside the page.
                    // A clip's frame is named by its poster; a film written
                    // before posters were JPEG keeps it as a PNG, and the
                    // movie beside it is never the picture.
                    let picture = |name: &str| -> Option<String> {
                        let (hash, ext) = name.split_once('.')?;
                        let still = |e: &str| ["jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff"].contains(&e);
                        let (found, bytes) = match p.find_proxy(hash, Some(ext)).ok().flatten() {
                            Some((found, bytes)) if still(&found.to_lowercase()) => (found, bytes),
                            _ => ["jpg", "png"].iter().find_map(|e| p.read_proxy(hash, e).ok().flatten().map(|b| (e.to_string(), b)))?,
                        };
                        let mime = if found == "jpg" || found == "jpeg" { "image/jpeg" } else { "image/png" };
                        Some(share::data_uri(&bytes, mime))
                    };
                    // The Share page's switches; one it leaves out
                    // is the plan's own (the way round, the scale bar).
                    let show = shotlister_engine::diagram::print::Show {
                        landscape: options.get("orientation").map(|o| o != "portrait"),
                        scale_bar: options.get("bar").map(|b| b == "1"),
                        dims: options.get("dims") != Some("0"),
                        cones: options.get("cones") != Some("0"),
                        dark: options.get("dark") == Some("1"),
                        key: options.get("key") != Some("0"),
                        printed: options.get("printed").unwrap_or("").to_string(),
                        // The clock the screen draws the sun by (`diagram`'s
                        // `tz=`), so a place whose zone the longitude does
                        // not give (the mountains) reads the same on paper.
                        tz: options.number("tz"),
                    };
                    // `day=` is a per-day export (Ref 1503): that day's scenes
                    // only, or the unscheduled; a day with none is an empty page.
                    match options.get("day") {
                        Some(day) if options.ids("scenes").is_empty() => {
                            let day = if day == "unscheduled" { None } else { id_from(day) };
                            if day.is_none() && options.get("day") != Some("unscheduled") {
                                return error("that is not a shoot day this project has");
                            }
                            shotlister_engine::diagram::print::page_for_day(h.project.doc(), day, show, &picture)
                        }
                        Some(_) => return error("ask for scenes or a day, not both"),
                        None => shotlister_engine::diagram::print::page(h.project.doc(), &options.ids("scenes"), show, &title, &picture),
                    }
                }
                "table" => html::table(&sheet, &frames, Print::Table, scale, size, &widths),
                "storyboard" => html::storyboard(&sheet, &frames, Print::Storyboard, scale, size),
                // The script down the left and the shots that cover it on
                // the right — his ask from set, 2026-09-22. Set in the
                // project's own document style, like the Document page.
                "avscript" => html::script(&sheet, &frames, Print::Script, scale, &style),
                // `order=` is what the app has written in its own top-right
                // corner — SCRIPT ORDER, BY SHOOT DAY, and what it is leaving
                // out. Only the shell knows it, because only the shell knows
                // how the scene list is being read; given nothing, the page
                // simply does not draw that line.
                // **The page is set the way he set it in the app.** This is
                // the whole point of `docstyle` living in the engine: the
                // exported document and the one on screen read from one
                // place, so they cannot drift the way two copies of the same
                // numbers did.
                _ => html::document(
                    &sheet,
                    &frames,
                    Print::Document,
                    scale,
                    options.get("order").unwrap_or(""),
                    &style,
                ),
            };
            match std::fs::write(path, html) {
                Ok(()) => {
                    let mut j = Json::new();
                    j.obj().kv("path", path).kv("kind", which).end_obj();
                    j.finish()
                }
                Err(e) => error(&format!("could not write the page: {e}")),
            }
        }

        // xlsx <path> [key=value ...] — his working file, exactly: Master
        // Shot List, Group by Day, Group by Sequence, Ranges. Three views of
        // the one filtered list, built off the same narrowing the on-screen
        // list is under — the way the share page and the printed pages
        // already work.
        //
        // Takes the same `scenes=` / `day=` narrowing `print` does, so a
        // per-day export can ask for one day's workbook beside one day's
        // pages and get two files about exactly the same shots.
        "xlsx" => {
            let path = parts.next().unwrap_or("");
            if path.is_empty() {
                return error("no path to write the workbook to");
            }
            let options = Options::read(parts);

            let p = &h.project;
            let mut q = match options.query_narrowing(h) {
                Ok(q) => q,
                Err(problem) => return problem,
            };
            // Same override `print` applies — an explicit list wins over
            // whatever is on screen. Missed here until 2026-08-27: the
            // per-day export was asking for this (drop the now-redundant
            // Shoot Day column) and the columns it asked for were silently
            // ignored, three tabs over.
            let columns = options.list("columns");
            q.group_by = GroupBy::Flat;
            let mut master = p.doc().sheet(&q);
            q.group_by = GroupBy::Day;
            let mut by_day = p.doc().sheet(&q);
            q.group_by = GroupBy::Sequence;
            let mut by_sequence = p.doc().sheet(&q);
            if let Some(columns) = columns {
                master.columns = columns.clone();
                by_day.columns = columns.clone();
                by_sequence.columns = columns;
            }

            // Where a frame can be fetched from, when the app knows. Given, the
            // Image column becomes a formula the sheet resolves for itself
            // rather than a picture pasted over the grid — the difference
            // being that a formula is the cell's contents and so survives his
            // sorting and filtering. Unset (an older app, or a film with no
            // relay behind it) and nothing changes.
            let pictures_at = options.get("pictures");

            let frames = |ids: &[Id]| -> Option<xlsx::Frame> {
                // v1: the shot's key frame stands for the row, exactly as his
                // own template does — one picture per cell is all a
                // spreadsheet can hold anyway. Compositing every frame on a
                // shot into one picture is a follow-up, not this row.
                let media = *ids.first()?;
                let (bytes, ext) = frame_bytes(p, media)?;
                // Only formats a spreadsheet can actually draw. A HEIC frame
                // (or a movie with no poster kept yet) leaves the cell blank
                // rather than embedding bytes Excel cannot open —
                // `xlsx::Frames` already treats `None` that way.
                if !["png", "jpg", "jpeg", "gif"].contains(&ext.as_str()) {
                    return None;
                }
                let (width, height) = image_dimensions(&bytes, &ext);
                let url = frame_url(p, media, &ext, pictures_at);
                Some(xlsx::Frame { bytes, extension: ext, width, height, url })
            };
            let vocabulary = |name: &str| p.doc().vocabulary(name);

            let bytes = xlsx::workbook(&master, &by_day, &by_sequence, &vocabulary, &frames);
            // **Atomic, not a plain write** — Ref 375's own auto-update timer
            // rewrites this exact path every few seconds while the project is
            // open, often inside a folder something else (Drive, a sync
            // client) is watching. A plain `fs::write` truncates the file
            // before the new bytes land; a reader that peeks in that window
            // sees a half-written spreadsheet, and a half-written xlsx is not
            // a small xlsx — it is one Google Sheets and Excel alike may
            // refuse to open as anything but a locked, "recovered" husk.
            // `write_whole` is the same write-to-a-scratch-name-then-rename
            // the project's own save file has always used, for the same
            // reason.
            match write_whole(std::path::Path::new(path), &bytes) {
                Ok(()) => {
                    let mut j = Json::new();
                    j.obj().kv("path", path).end_obj();
                    j.finish()
                }
                Err(e) => error(&format!("could not write the workbook: {e}")),
            }
        }

        // ---- catching up with the other devices ----------------------------
        //
        // `incoming` costs a glance at the folder and no reading, so the app
        // can ask on every window focus. `pull` does the work, and only says
        // something when two people changed the same thing without knowing.
        "incoming" => {
            let mut j = Json::new();
            j.obj().kb("waiting", h.project.has_incoming()).end_obj();
            j.finish()
        }

        // Every disagreement standing right now, whether it arrived through a
        // pull or was already in the log when the project opened.
        //
        // Opening a project merges every log in the folder, silently — which
        // is right, because merging never loses anything. But it meant the one
        // case worth a word (two machines decided the same field without
        // seeing each other) was swallowed whenever it arrived while the app
        // was closed, which is the ordinary way it arrives. Clashes are
        // derived from the log, so they can be asked for at any moment; this
        // is that question.
        "clashes" => {
            let clashes = h.project.doc().clashes();
            let mut j = Json::new();
            j.obj().ki("count", clashes.len() as i64);
            j.key("clashes").arr();
            for clash in &clashes {
                j.obj()
                    .kv("record", &clash.record.0.to_string())
                    .kv("field", &clash.field)
                    // **Both values, so the shell can offer either.** Ref 231:
                    // the notice could only ever keep what was on screen, and
                    // the whole point of saying something was decided twice is
                    // that the other answer might be the right one. Said in
                    // the engine's own words, so a button cannot spell a value
                    // differently from the sentence above it.
                    .kv("kept", &shotlister_engine::sync::shown(&clash.kept))
                    .kv("other", &shotlister_engine::sync::shown(&clash.other))
                    .kv(
                        "said",
                        &h.project.doc().clash_message(clash, |device| {
                            // Said the way a person would: this machine, or
                            // the other one. A raw number means nothing to
                            // anybody reading a banner — and until a project
                            // carries real machine names, "another machine"
                            // is the truthful thing to call it.
                            if device == h.project.device() {
                                "This Mac".to_string()
                            } else {
                                "Another machine".to_string()
                            }
                        }),
                    )
                    .end_obj();
            }
            j.end_arr();
            j.end_obj();
            j.finish()
        }

        // syncplan <state json> <media json> — what should move between this
        // project and the relay, given what the relay says it holds.
        //
        // **The deciding is here; the carrying is Swift's.** URLSession is the
        // only way to get a transfer that survives the app going to the
        // background or a signal dropping halfway up a logging road, so the
        // app does the fetching and putting. What it must not do is work out
        // *what* to move: two answers to that question would drift, and the
        // one that drifted would be the one nobody tested.
        //
        // Both arguments are exactly what the relay replied with. They cannot
        // contain a tab — JSON escapes one inside a string and has none
        // between tokens — so passing them through this tab-delimited line is
        // safe.
        //
        // Afterwards the app writes what it fetched into `changes/` and calls
        // `pull`, which is the same merge that has always run. Nothing about
        // this makes a new way for a change to arrive.
        "syncplan" => {
            // **The rooms the phone scanned join the film before anything is
            // weighed up.**
            //
            // A scan arrives as two files in `locations/<folder>/scans/` and
            // nothing used to put them in the document, so nothing carried
            // them: a room was visible only on a machine holding that folder,
            // which meant the phone that made it could not show it back and
            // the web could not know the room had been scanned at all.
            // Registering them makes each one media, exactly like a
            // photograph, and every rule below already knows how to move a
            // photograph.
            //
            // **Here because this is where both apps ask.** The Mac and the
            // phone carry their own bytes and only ask the engine what should
            // move; `courier::sync` is the Rust side of the same question and
            // does this too. It has to happen before the folder is listed, or
            // the log naming the new rooms is written after the inventory that
            // decides what to send, and sits on this device until next time.
            //
            // Quiet on failure by design: a scans folder that cannot be read
            // is a reason to carry the day's work anyway, not to refuse it.
            if !h.project.is_read_only() {
                let scans = h.project.register_scans().unwrap_or(0);
                let papers = h.project.register_attachments().unwrap_or(0);
                if scans + papers > 0 {
                    let _ = h.project.save();
                }
            }
            let state = parts.next().unwrap_or("");
            let media = parts.next().unwrap_or("");
            let there = shotlister_remote::parse_state(state, media);
            let here = shotlister_remote::local::local_inventory(h.project.path());
            let wanted = shotlister_remote::local::wanted_stems(&h.project);
            let folded = shotlister_remote::local::folded(h.project.path());
            let mut plan = shotlister_remote::plan(&here, &there, &wanted, &folded);
            // **Never send a file the film no longer names.** 2026-09-15: a
            // clip replaced by a smaller copy of itself (`reclip`) leaves its
            // old self on any device that has not yet swept it, and "send
            // whatever the relay lacks" put 257 MB of retired clips straight
            // back on the relay within the hour. The engine judges
            // (`stray_media_names`); a stray goes nowhere.
            let strays = h
                .project
                .doc()
                .stray_media_names(here.media.iter().map(|e| e.name.as_str()));
            plan.upload_media.retain(|name| !strays.contains(name));

            let mut j = Json::new();
            j.obj()
                .ki("steps", plan.steps() as i64)
                .kb("incoming", plan.has_incoming())
                .kb("outgoing", plan.has_outgoing());
            for (key, list) in [
                ("uploadLogs", &plan.upload_logs),
                ("rewriteLogs", &plan.rewrite_logs),
                ("downloadLogs", &plan.download_logs),
                ("uploadMedia", &plan.upload_media),
                ("downloadMedia", &plan.download_media),
            ] {
                j.key(key).arr();
                for name in list {
                    j.str(name);
                }
                j.end_arr();
            }
            j.end_obj();
            j.finish()
        }

        // settle — end every standing disagreement by keeping what is on
        // screen.
        //
        // **There is no dismissal, on purpose** — see `resolve_clash`: a clash
        // stops standing because somebody decided, and deciding is a write
        // made with knowledge of both sides. The Mac's banner had an OK that
        // emptied a Swift array and told the engine nothing, so the next open
        // asked this same question, got the same answer off the same log, and
        // said the same thing. Every launch, for ever.
        //
        // Keeping what is on screen changes no value on screen. It records
        // that the question was answered, and it is one undoable step per
        // field like any other edit.
        // takeother <record> <field> — settle one disagreement the *other*
        // way: take the value that was only in the log. Ref 231.
        //
        // Matched by record and field rather than by position, because the
        // list is rebuilt on every view and a position would settle whichever
        // clash happened to have moved into that slot.
        "takeother" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let record = parts.next().and_then(id_from);
            let field = parts.next().unwrap_or("").to_string();
            let Some(record) = record else {
                return error("that is not a record this project has");
            };
            let found = h
                .project
                .doc()
                .clashes()
                .into_iter()
                .find(|c| c.record == record && c.field == field);
            if let Some(clash) = found {
                h.project.doc_mut().take_theirs(&clash);
            }
            // A clash already settled — by another window, or by the other
            // device deciding first — is nothing left to do rather than an
            // error to show him.
            view(h)
        }

        "settle" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            // With a record and a field, settle that one disagreement only —
            // the banner answers them a row at a time. Without, all of them.
            let record = parts.next().and_then(id_from);
            let field = parts.next().unwrap_or("").to_string();
            let standing = h.project.doc().clashes();
            for clash in &standing {
                if record.is_some_and(|r| clash.record != r || clash.field != field) {
                    continue;
                }
                h.project.doc_mut().keep_mine(clash);
            }
            view(h)
        }

        "pull" => {
            let pull = match h.project.pull() {
                Ok(pull) => pull,
                Err(e) => return error(&e.message()),
            };
            let mut j = Json::new();
            j.obj()
                .ki("merged", pull.merged as i64)
                .ki("devices", pull.devices.len() as i64)
                .kb("needsAttention", pull.needs_attention());
            j.key("clashes").arr();
            for clash in &pull.clashes {
                j.obj()
                    .kv("record", &clash.record.0.to_string())
                    .kv("field", &clash.field)
                    // **Both values, so the shell can offer either.** Ref 231:
                    // the notice could only ever keep what was on screen, and
                    // the whole point of saying something was decided twice is
                    // that the other answer might be the right one. Said in
                    // the engine's own words, so a button cannot spell a value
                    // differently from the sentence above it.
                    .kv("kept", &shotlister_engine::sync::shown(&clash.kept))
                    .kv("other", &shotlister_engine::sync::shown(&clash.other))
                    .kv(
                        "said",
                        &h.project.doc().clash_message(clash, |device| {
                            // Said the way a person would: this machine, or
                            // the other one. A raw number means nothing to
                            // anybody reading a banner — and until a project
                            // carries real machine names, "another machine"
                            // is the truthful thing to call it.
                            if device == h.project.device() {
                                "This Mac".to_string()
                            } else {
                                "Another machine".to_string()
                            }
                        }),
                    )
                    .end_obj();
            }
            j.end_arr();
            j.end_obj();
            j.finish()
        }

        // bulkplan <name>\x1f<name>… — what a folder of pictures would do,
        // before it does any of it. The order is the one on screen, because
        // "in order" can only mean the order the person is looking at.
        "bulkplan" => {
            let names: Vec<String> = parts
                .next()
                .unwrap_or("")
                .split('\u{1f}')
                .filter(|n| !n.trim().is_empty())
                .map(|n| n.to_string())
                .collect();
            let placements: Vec<Id> = h
                .project
                .doc()
                .run(&h.query())
                .into_iter()
                .flat_map(|group| group.placements)
                .collect();
            let plan = h.project.doc().plan_bulk_media(&names, &placements);

            let mut j = Json::new();
            j.obj()
                .kv("summary", &plan.summary())
                .kb("needsConfirming", plan.needs_confirming())
                .ki("spare", plan.spare_files.len() as i64)
                .ki("without", plan.shots_left_over as i64);
            j.key("pairs").arr();
            for pair in &plan.pairings {
                j.obj()
                    .kv("filename", &pair.filename)
                    .kv("placement", &pair.placement.0.to_string())
                    .kv("number", &pair.number)
                    .kb("hasFrames", pair.already_has_frames)
                    .end_obj();
            }
            j.end_arr();
            j.end_obj();
            j.finish()
        }

        // use <ownerId> <mediaId> — put a file the project already stores on
        // another shot or scene.
        //
        // Ref 211's other half. Once `have` says the file is here, nothing
        // needs to move: the bytes are on disk under a name made from
        // themselves, and a second use is a record, not a copy. Handing the
        // same megabytes back through the door they came in — which is what a
        // shell would otherwise have to do — costs three times their size in
        // text on a phone.
        //
        // Same lead-frame rule as `paste`, and for the same reason: a new
        // picture taking over the lead frame is right, unless somebody has
        // deliberately chosen one.
        "use" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let owner = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that shot id is not one this project has"),
            };
            let media = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that file is not one this project has"),
            };
            if h.project.doc().get(media).map(|r| r.kind.clone()) != Some(Kind::Media) {
                return error("that is not a stored file");
            }
            let mref = h.project.doc_mut().attach_media(owner, media, "");
            // A name for *this* use, when the caller has one. A file already
            // here is being hung somewhere new, and where it is going may call
            // it something else — the same rule `paste` follows. With nothing
            // given it wears the file's own name, which is what it did before.
            if let Some(name) = parts.next().map(str::trim).filter(|s| !s.is_empty()) {
                // The stored bytes decide the extension, not the caller — Ref
                // 193, the same line `paste` holds. What arrives as
                // `IMG_4523.HEIC` is already here as JPEG, and the name given
                // for this use must say so.
                let stored = h
                    .project
                    .doc()
                    .get(media)
                    .and_then(|r| r.text(f::FILENAME))
                    .unwrap_or_default()
                    .to_string();
                let ext = stored.rsplit('.').next().unwrap_or("").to_string();
                let named = if ext.is_empty() {
                    name.to_string()
                } else {
                    shotlister_engine::name_with_extension(name, &ext)
                };
                h.project.doc_mut().set_media_ref_name(mref, &named);
            }
            let is_shot = h.project.doc().get(owner).map(|r| r.kind.clone()) == Some(Kind::Shot);
            let chosen = h.project.doc().key_frame_was_chosen(owner);
            if is_shot && !chosen {
                h.project.doc_mut().set(owner, f::KEY_MEDIA, mref);
            }
            view(h)
        }

        // have <hash> — does this project already hold this file?
        //
        // Ref 211. Asked *before* encoding anything, with the hash of the file
        // as it arrived. Two files answer yes: one stored exactly as it came,
        // and one made from it — a clip shrunk to 720p is filed under the hash
        // of the small copy, not of the clip, so the clip's own hash would
        // otherwise find nothing and the same four seconds would be encoded
        // and stored a second time.
        // movepictureto <mediaRefId> <ownerId> — the same use of a picture,
        // hanging somewhere else. Carries its caption and its name with it,
        // because it is the same use rather than a new one.
        "movepictureto" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that picture is not one this project has"),
            };
            let owner = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that board is not one this project has"),
            };
            h.project.doc_mut().move_media_use(mref, owner);
            view(h)
        }

        // caption <mediaRefId> <words> — what is said under a picture. On the
        // use, not the file, so the same photograph can mean one thing on a
        // board and another on a shot.
        "caption" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that picture is not one this project has"),
            };
            let said = parts.next().unwrap_or("").trim().to_string();
            let tx = h.project.doc_mut().begin("Caption picture");
            if said.is_empty() {
                h.project.doc_mut().set(mref, f::CAPTION, Value::Null);
            } else {
                h.project.doc_mut().set(mref, f::CAPTION, Value::text(&said));
            }
            h.project.doc_mut().end(tx);
            view(h)
        }

        // trim <mediaRefId> <start> <end> — the in/out range this use of a
        // clip plays back, in seconds. Never touches the file on disk.
        // trim <mediaRefId> clear — back to playing the whole clip.
        "trim" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that clip is not one this project has"),
            };
            let arg = parts.next().unwrap_or("").trim().to_string();
            if arg == "clear" {
                h.project.doc_mut().clear_media_trim(mref);
            } else {
                let start: f64 = match arg.parse() {
                    Ok(v) => v,
                    Err(_) => return error("that trim range didn't make sense"),
                };
                let end: f64 = match parts.next().and_then(|s| s.trim().parse().ok()) {
                    Some(v) => v,
                    None => return error("that trim range didn't make sense"),
                };
                h.project.doc_mut().set_media_trim(mref, start, end);
            }
            view(h)
        }

        // crop <mediaRefId> <x> <y> [scale] — which part of this use of a
        // picture is kept when it is drawn cropped, and how far in. Never
        // touches the file.
        // crop <mediaRefId> clear — back to the middle, at full width.
        "crop" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that picture is not one this project has"),
            };
            let arg = parts.next().unwrap_or("").trim().to_string();
            if arg == "clear" {
                h.project.doc_mut().clear_media_crop(mref);
            } else {
                let x: f64 = match arg.parse() {
                    Ok(v) => v,
                    Err(_) => return error("that crop didn't make sense"),
                };
                let y: f64 = match parts.next().and_then(|s| s.trim().parse().ok()) {
                    Some(v) => v,
                    None => return error("that crop didn't make sense"),
                };
                // How far in is optional: dragging a picture about without
                // ever zooming is the ordinary case, and it means one.
                let scale: f64 = parts
                    .next()
                    .and_then(|s| s.trim().parse().ok())
                    .unwrap_or(1.0);
                h.project.doc_mut().set_media_crop(mref, x, y, scale);
            }
            view(h)
        }

        // arrows <mediaRefId> <x1,y1,bx,by,x2,y2,heads;…> — the storyboard
        // arrows drawn over this use of a picture. Every number is a fraction
        // of the picture, so an arrow stays on what it was drawn on however
        // the picture is cropped or how big it is drawn.
        // arrows <mediaRefId> clear — back to a bare photograph.
        "arrows" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mref = match parts.next().and_then(id_from) {
                Some(i) => i,
                None => return error("that picture is not one this project has"),
            };
            // The rest of the line, whitespace and all — arrows are separated
            // by semicolons, not spaces, but a caller that puts a space after
            // one should not lose the arrow behind it.
            let rest: String = parts.collect::<Vec<_>>().join(" ");
            if rest.trim() == "clear" {
                h.project.doc_mut().clear_media_arrows(mref);
            } else {
                let drawn = Arrow::parse(&rest);
                h.project.doc_mut().set_media_arrows(mref, &drawn);
            }
            view(h)
        }

        // printframe <shotId> <json> — sets the shot's Print Frame, the board
        // that stands for it on paper (`engine/src/printframe.rs`):
        //   {"layout":"grid22","numbers":true,
        //    "frames":[{"use":"<mediaRefId>","at":3.2},{"use":"<mediaRefId>"}],
        //    "arrows":"<arrow line, fractions of the board>"}
        // `at` is seconds from the start of the whole clip, on a clip's frame
        // only. Every frame must be a picture on this shot. One undo step.
        // printframe <shotId> clear — no Print Frame; the shot prints as before.
        // Answers the view. A shot standing in for a master sets the master's,
        // the shot its pictures belong to.
        "printframe" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let shot = match parts.next().and_then(id_from) {
                Some(i) if h.project.doc().get(i).map(|r| r.kind == Kind::Shot) == Some(true) => i,
                _ => return error("that shot id is not one this project has"),
            };
            let shot = h.project.doc().described_by(shot);
            let rest: String = parts.collect::<Vec<_>>().join("\t");
            if rest.trim() == "clear" {
                h.project.doc_mut().clear_print_frame(shot);
                return view(h);
            }
            let spec = match PrintFrame::parse(rest.trim()) {
                Some(spec) => spec,
                None => return error("that Print Frame did not make sense"),
            };
            if !printframe::LAYOUTS.contains(&spec.layout.as_str()) {
                return error(&format!("no layout called {}", spec.layout));
            }
            if spec.frames.is_empty() {
                return error("a Print Frame needs at least one frame");
            }
            let on_shot = h.project.doc().media_refs(shot);
            if spec.frames.iter().any(|m| !on_shot.contains(&m.media_ref)) {
                return error("every frame has to be a picture on this shot");
            }
            h.project.doc_mut().set_print_frame(shot, &spec);
            view(h)
        }

        // printframeview <shotId> — the shot's Print Frame as the view gives
        // it (`printFrame` on a shot), or `null` when it has none.
        "printframeview" => {
            let shot = match parts.next().and_then(id_from) {
                Some(i) => h.project.doc().described_by(i),
                None => return error("that shot id is not one this project has"),
            };
            h.project.doc().print_frame_view(shot).unwrap_or_else(|| "null".to_string())
        }

        // printframebake <shotId> <digest> <width> <height> <ext> <base64> —
        // the Mac's picture of the board, filed beside the film's other
        // pictures under its own hash and recorded on the shot with the
        // digest of the spec it was baked from (the `digest` the view gave).
        // Not an undo step. Answers the shot's `printFrame` JSON, whose
        // `stale` is false when the bake matches the spec as it stands now.
        "printframebake" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let shot = match parts.next().and_then(id_from) {
                Some(i) if h.project.doc().get(i).map(|r| r.kind == Kind::Shot) == Some(true) => i,
                _ => return error("that shot id is not one this project has"),
            };
            let shot = h.project.doc().described_by(shot);
            let digest = parts.next().unwrap_or("").trim().to_string();
            let width: u32 = parts.next().unwrap_or("0").trim().parse().unwrap_or(0);
            let height: u32 = parts.next().unwrap_or("0").trim().parse().unwrap_or(0);
            let ext = match parts.next().unwrap_or("jpg").trim().to_lowercase().as_str() {
                "png" => "png".to_string(),
                _ => "jpg".to_string(),
            };
            let bytes = match parts.next().and_then(b64::decode) {
                Some(b) if !b.is_empty() => b,
                _ => return error("nothing decodable in the picture"),
            };
            if h.project.doc().print_frame(shot).is_none() {
                return error("that shot has no Print Frame");
            }
            let (width, height) = if width > 0 && height > 0 {
                (width, height)
            } else {
                image_dimensions(&bytes, &ext)
            };
            let hex = sha256(&bytes).to_hex();
            if let Err(e) = h.project.write_proxy(&hex, &ext, &bytes) {
                return error(&e.message());
            }
            let baked = printframe::Baked { hash: hex, ext, width, height, digest };
            h.project.doc_mut().set_print_frame_baked(shot, &baked);
            h.project.doc().print_frame_view(shot).unwrap_or_else(|| "null".to_string())
        }

        "have" => {
            let hex = parts.next().unwrap_or("").trim();
            let held = Hash256::from_hex(hex)
                .and_then(|arriving| h.project.doc().media_already_here(arriving));
            let mut j = Json::new();
            j.obj().kb("here", held.is_some());
            match held {
                Some(id) => {
                    j.kv("media", &id.0.to_string());
                    // What it is stored as, so a caller can reach the bytes
                    // without asking a second question.
                    if let Some(record) = h.project.doc().get(id) {
                        j.kv("hash", record.text(f::HASH).unwrap_or(""))
                            .kv("filename", record.text(f::FILENAME).unwrap_or(""));
                    }
                }
                None => {
                    j.kv("media", "");
                }
            }
            j.end_obj();
            j.finish()
        }

        // keep <hash> <ext> <base64> — the full-resolution file, alongside the
        // small copy the app draws.
        //
        // A clip goes into a project as it arrived, which for a phone clip is
        // hundreds of megabytes that then sync to every machine and into Drive
        // (Ref 155). The answer is the one photographs already get: keep a
        // small copy for looking at. But "the app keeps a smaller version" is
        // only honest if there is an answer to *where is the real one*, and
        // there was no door to one. This is it.
        //
        // Originals are a cache, not the record: `prune` drops the least
        // recently used, and dropping one never touches the small copy, so a
        // shot never goes blank for want of room.
        "keep" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let hex = parts.next().unwrap_or("");
            if hex.is_empty() {
                return error("no hash given");
            }
            let ext = parts.next().unwrap_or("").trim();
            if ext.is_empty() {
                return error("no extension given");
            }
            let bytes = match parts.next().and_then(b64::decode) {
                Some(b) if !b.is_empty() => b,
                _ => return error("nothing decodable in the file"),
            };
            match h.project.write_original(hex, ext, &bytes) {
                Ok(()) => ok(),
                Err(e) => error(&e.message()),
            }
        }

        // original <hash> <ext> — the full-resolution file, if this machine
        // still has it. Not having it is an ordinary answer, not an error: it
        // may have been pruned here, or never have reached this device.
        "original" => {
            let hex = parts.next().unwrap_or("");
            let ext = parts.next().unwrap_or("").trim();
            if hex.is_empty() || ext.is_empty() {
                return error("say which file, and what it is called");
            }
            match h.project.read_original(hex, ext) {
                Ok(Some(bytes)) => {
                    let mut j = Json::new();
                    j.obj()
                        .kb("here", true)
                        .kv("data", &b64::encode(&bytes))
                        .end_obj();
                    j.finish()
                }
                Ok(None) => {
                    let mut j = Json::new();
                    j.obj().kb("here", false).end_obj();
                    j.finish()
                }
                Err(e) => error(&e.message()),
            }
        }

        // storage — how much room the full-resolution copies take, and keeping
        // them inside a budget. Proxies are never counted or touched: every
        // device keeps all of them, which is what makes this work with no
        // signal.
        "storage" => {
            let mut j = Json::new();
            j.obj().ki("originalBytes", h.project.originals_bytes() as i64).end_obj();
            j.finish()
        }

        "prune" => {
            let megabytes: u64 = parts.next().unwrap_or("2000").parse().unwrap_or(2000);
            match h.project.prune_originals(megabytes.saturating_mul(1_000_000)) {
                Ok(freed) => {
                    let mut j = Json::new();
                    j.obj().ki("freedBytes", freed as i64).end_obj();
                    j.finish()
                }
                Err(e) => error(&e.message()),
            }
        }

        "save" => match h.project.save() {
            Ok(()) => ok(),
            Err(e) => error(&e.message()),
        },

        // What undo would do next, and what redo would put back. The engine keeps
        // the stack; it does not hand out its labels beyond the top one, so this
        // is as much history as can honestly be shown.
        "history" => {
            let d = h.project.doc();
            let mut j = Json::new();
            j.obj()
                .kb("canUndo", d.can_undo())
                .kv("undoLabel", d.undo_label().unwrap_or(""))
                .kb("canRedo", d.can_redo())
                .kv("redoLabel", d.redo_label().unwrap_or(""))
                .ki("depth", d.undo_depth() as i64);
            j.end_obj();
            j.finish()
        }

        "redo" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let outcome = h.project.doc_mut().redo();
            let mut j = Json::new();
            j.obj();
            match &outcome {
                Some(o) => {
                    j.kb("did", true)
                        .kv("label", &o.label)
                        .ki("restored", o.restored as i64)
                        .ki("skipped", o.skipped as i64)
                        .kb("complete", o.complete());
                }
                None => {
                    j.kb("did", false).kv("label", "");
                }
            }
            j.end_obj();
            let head = j.finish();
            let body = view(h);
            format!("{{\"undo\":{head},\"view\":{body}}}")
        }

        "undo" => {
            // the engine owns what undo means; this only asks for it, and says
            // plainly when part of it was held back by another device
            let outcome = h.project.doc_mut().undo();
            let mut j = Json::new();
            j.obj();
            match &outcome {
                Some(o) => {
                    j.kb("did", true)
                        .kv("label", &o.label)
                        .ki("restored", o.restored as i64)
                        .ki("skipped", o.skipped as i64)
                        .kb("complete", o.complete());
                }
                None => {
                    j.kb("did", false).kv("label", "");
                }
            }
            j.end_obj();
            let head = j.finish();
            let body = view(h);
            format!("{{\"undo\":{head},\"view\":{body}}}")
        }

        other => error(&format!("no command called {other}")),
    }
}

// ---------------------------------------------------------------- the C edge

fn to_c(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("{\"error\":\"unencodable reply\"}").unwrap())
        .into_raw()
}

/// Opens the project at `path`, creating an empty one if nothing is there yet.
/// Returns null if it could not be opened at all.
///
/// A new project is empty on purpose. The sample list is a separate request, so
/// making a real project never puts somebody else's shots in it.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn sl_open(path: *const c_char) -> *mut Handle {
    sl_open_as(path, 1)
}

/// Open a project **as a named device**.
///
/// Every machine must call itself something different, and until now every one
/// of them said `DeviceId(1)`. Two Macs on one iCloud folder would therefore
/// have shared an identity, and the whole of sync rests on telling devices
/// apart: a clash is "we both changed this without seeing each other", which
/// cannot be detected between two devices wearing the same name, and the rule
/// that a device never writes another's changes into its own log
/// (`storage::ours`) would have re-written the other Mac's work as ours.
///
/// The id is the shell's to keep — one per machine, made once and remembered —
/// because identity is a fact about the computer, not about the document.
/// `sl_open` stays as the one-device door for anything that has no opinion.
#[no_mangle]
pub unsafe extern "C" fn sl_open_as(path: *const c_char, device: u64) -> *mut Handle {
    sl_open_as_installed(path, device, 0)
}

/// Open a project as a named device, **saying which machine that name belongs
/// to**. Ref 186.
///
/// The name and the machine are two different facts and the difference is the
/// whole point. A name is remembered in preferences — which is precisely what
/// Migration Assistant copies onto a new Mac, so two machines end up insisting
/// they are the same device. The machine is the hardware itself, and cannot be
/// copied anywhere.
///
/// The engine leaves the machine's mark beside the diaries and reads everybody
/// else's. Two machines claiming one name is reported in the view as
/// `project.deviceClash`, and the app should say so: edits made on both in the
/// same moment are dropped as duplicates of each other, with nothing said and
/// no way to notice afterwards.
///
/// Zero means the shell has no opinion. Then no mark is left, nothing is
/// claimed, and nothing is checked — which is what every build before this one
/// did, so an old app and a new one can share a folder safely.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn sl_open_as_installed(
    path: *const c_char,
    device: u64,
    installation: u64,
) -> *mut Handle {
    if path.is_null() {
        return std::ptr::null_mut();
    }
    let path = match CStr::from_ptr(path).to_str() {
        Ok(s) => PathBuf::from(s),
        Err(_) => return std::ptr::null_mut(),
    };
    // Zero is not a device. A shell that has not decided yet gets the old
    // behaviour rather than an id that sorts before every real one.
    let device = DeviceId(if device == 0 { 1 } else { device });

    let project = if path.exists() {
        shotlister_storage::open_as(&path, device, installation)
    } else {
        let parent = path.parent().map(PathBuf::from).unwrap_or_default();
        let title = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Untitled")
            .to_string();
        match shotlister_storage::create_as(&parent, &title, device, installation) {
            Ok(mut fresh) => {
                let _ = fresh.save();
                Ok(fresh)
            }
            Err(e) => Err(e),
        }
    };

    match &project {
        Ok(_) => set_problem(""),
        // Why it could not be opened, kept where the app can ask for it. A
        // project written by a newer build has to *say so* rather than simply
        // failing to appear, and the reason is lost the moment this returns a
        // null pointer.
        Err(e) => set_problem(&e.message()),
    }

    match project {
        Ok(project) => Box::into_raw(Box::new(Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        })),
        Err(_) => std::ptr::null_mut(),
    }
}

static LAST_PROBLEM: std::sync::Mutex<String> = std::sync::Mutex::new(String::new());

fn set_problem(message: &str) {
    if let Ok(mut held) = LAST_PROBLEM.lock() {
        *held = message.to_string();
    }
}

/// Why the last open failed, said the way it should appear on screen. Empty
/// when the last one worked.
///
/// # Safety
///
/// The caller owns the string and must hand it back to `sl_free`.
#[no_mangle]
pub unsafe extern "C" fn sl_problem() -> *mut c_char {
    let held = LAST_PROBLEM.lock().map(|m| m.clone()).unwrap_or_default();
    to_c(held)
}

/// Sends one command and returns its JSON reply. The caller owns the reply and
/// must hand it back to `sl_free`.
///
/// # Safety
/// `handle` must have come from `sl_open` and not yet been closed.
#[no_mangle]
pub unsafe extern "C" fn sl_call(handle: *mut Handle, line: *const c_char) -> *mut c_char {
    if handle.is_null() || line.is_null() {
        return to_c(error("no project open"));
    }
    let h = &mut *handle;
    let line = match CStr::from_ptr(line).to_str() {
        Ok(s) => s,
        Err(_) => return to_c(error("command was not valid text")),
    };
    // **A panic in the engine is an error reply, not the end of the app.**
    // Unwinding across this boundary aborts the process — which is how a
    // curly quote in a pasted script took Shotlister down on Save
    // (2026-09-19). The document is left as the panic found it: every
    // change is inside a transaction that was not ended, and the next
    // `view` reads the records as they stand. The message reaches the
    // shell, which says it, and the checking run's stderr.
    to_c(route(h, line))
}

/// Measured sheets waiting to be decided, by ticket. Only the last few are
/// kept: a ticket nobody came back for is a preview that was overtaken.
static PARKED: std::sync::Mutex<Vec<(u64, autolayout::Problem, autolayout::Plan)>> =
    std::sync::Mutex::new(Vec::new());
static NEXT_TICKET: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

fn park_layout(problem: autolayout::Problem, before: autolayout::Plan) -> u64 {
    let ticket = NEXT_TICKET.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    if let Ok(mut parked) = PARKED.lock() {
        parked.push((ticket, problem, before));
        let excess = parked.len().saturating_sub(4);
        parked.drain(..excess);
    }
    ticket
}

/// Decide a parked sheet. See the header: no project is touched.
#[no_mangle]
pub extern "C" fn sl_solve_layout(ticket: u64) -> *mut c_char {
    let taken = PARKED.lock().ok().and_then(|mut parked| {
        let at = parked.iter().position(|(t, _, _)| *t == ticket)?;
        Some(parked.remove(at))
    });
    let reply = match taken {
        Some((_, problem, before)) => {
            let solved = std::panic::catch_unwind(|| autolayout::solve(&problem));
            match solved {
                Ok(plan) => plan_json(&plan, Some(&before)),
                Err(_) => error("could not work out the layout"),
            }
        }
        None => error("no such layout ticket"),
    };
    to_c(reply)
}

/// Auto's plan as the shell reads it: the sheet, the shares to print with,
/// the multipliers Manual starts from, and why — the terms of the score, and
/// today's default scored the same way when there is one to compare.
fn plan_json(plan: &autolayout::Plan, before: Option<&autolayout::Plan>) -> String {
    let mut j = Json::new();
    j.obj()
        .kv("orientation", if plan.candidate.landscape { "landscape" } else { "portrait" })
        .kn("scale", plan.candidate.scale)
        .kv("frames", plan.frames().name())
        .kn("picture", plan.candidate.picture_in)
        .ki("pages", plan.pages as i64)
        .ki("cut", plan.cut_words as i64)
        .kn("narrowest", plan.narrowest_chars)
        .kn("score", plan.score);
    j.key("shares").obj();
    for (field, share) in &plan.shares {
        j.kn(field, *share);
    }
    j.end_obj();
    j.key("factors").obj();
    for (field, factor) in plan.factors() {
        j.kn(&field, factor);
    }
    j.end_obj();
    j.key("terms").obj();
    for (term, value) in &plan.terms {
        j.kn(term, *value);
    }
    j.end_obj();
    if let Some(b) = before {
        j.key("default").obj()
            .kn("picture", b.candidate.picture_in)
            .ki("pages", b.pages as i64)
            .ki("cut", b.cut_words as i64)
            .kn("narrowest", b.narrowest_chars)
            .kn("score", b.score);
        j.key("terms").obj();
        for (term, value) in &b.terms {
            j.kn(term, *value);
        }
        j.end_obj();
        j.end_obj();
    }
    j.end_obj();
    j.finish()
}

/// **Every command's one way in**: what an earlier version on screen allows,
/// then the command, with a panic turned into an error reply.
///
/// While a version is being looked at, a command that only shows something
/// runs against the film as it stood then — swapped in here and swapped back
/// here, **outside** the panic guard, so a fault in the middle of showing
/// cannot leave the old film where the real one belongs. See `versions`.
fn route(h: &mut Handle, line: &str) -> String {
    let name: String = line.split('\t').next().unwrap_or("").to_string();
    let mut showing = false;
    if h.looking.is_some() && !versions::is_ours(&name) {
        if versions::LOOKING_SHOWS.contains(&name.as_str()) {
            showing = true;
        } else if !versions::LOOKING_KEEPS.contains(&name.as_str()) {
            return versions::refused();
        }
    }
    if showing {
        show_old(h, true);
    }
    let reply = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(h, line)));
    if showing {
        show_old(h, false);
    }
    match reply {
        Ok(reply) => reply,
        Err(cause) => {
            let said = cause
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| cause.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "something went wrong inside".to_string());
            eprintln!("engine panic in {name}: {said}");
            error(&format!("The engine hit a fault in {name}: {said}"))
        }
    }
}

/// Trade the film on screen for the one being looked at, or back. The only
/// place the two ever change places.
fn show_old(h: &mut Handle, on: bool) {
    if h.showing_old == on {
        return;
    }
    if let Some(looking) = h.looking.as_mut() {
        // The card stays laid over whichever film is on screen (`card`).
        let card = h.project.doc().card().cloned();
        looking.doc.set_card(card);
        std::mem::swap(h.project.doc_mut(), &mut looking.doc);
        h.showing_old = on;
    }
}

/// The view of the version being looked at.
fn looking_view(h: &mut Handle) -> String {
    show_old(h, true);
    let reply = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| view(h)));
    show_old(h, false);
    reply.unwrap_or_else(|_| error("The engine hit a fault showing that version"))
}

/// # Safety
/// `s` must have come from `sl_call`.
#[no_mangle]
pub unsafe extern "C" fn sl_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// # Safety
/// `handle` must have come from `sl_open` and not yet been closed.
#[no_mangle]
pub unsafe extern "C" fn sl_close(handle: *mut Handle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}


/// `number=1,duplicates=1,rooms=1,contains=INT|EXT,forbid=CONTINUED:|OMITTED`
///
/// Empty means whatever this project was last told, which for an untouched one
/// is the settings a printed script wants. A film that prints oddly prints
/// oddly in every revision, so being explained once should be enough.
fn detection_from(settings: &str, base: shotlister_engine::Detection) -> shotlister_engine::Detection {
    let mut detection = base;
    for setting in settings.split(',') {
        let Some((name, value)) = setting.split_once('=') else {
            continue;
        };
        let on = value == "1" || value.eq_ignore_ascii_case("true");
        let words = || -> Vec<String> {
            value
                .split('|')
                .map(|word| word.trim().to_string())
                .filter(|word| !word.is_empty())
                .collect()
        };
        match name.trim() {
            "number" => detection.must_have_a_number = on,
            "duplicates" => detection.ignore_duplicate_numbers = on,
            "rooms" => detection.find_sub_slugs = on,
            "contains" => detection.must_contain = words(),
            "forbid" => detection.never_contains = words(),
            _ => {}
        }
    }
    detection
}

/// The `page` / `run` lines a shell sends after decoding a PDF.
fn pages_from(payload: &str) -> Vec<shotlister_engine::printed::Page> {
    let mut pages: Vec<shotlister_engine::printed::Page> = Vec::new();
    for line in payload.lines() {
        let mut parts = line.split('\t');
        match parts.next() {
            Some("page") => {
                let width = parts.next().and_then(|n| n.parse().ok()).unwrap_or(612.0);
                let height = parts.next().and_then(|n| n.parse().ok()).unwrap_or(792.0);
                pages.push(shotlister_engine::printed::Page {
                    width,
                    height,
                    runs: Vec::new(),
                });
            }
            Some("run") => {
                let Some(page) = pages.last_mut() else { continue };
                let x = parts.next().and_then(|n| n.parse().ok()).unwrap_or(0.0);
                let y = parts.next().and_then(|n| n.parse().ok()).unwrap_or(0.0);
                // Everything left is the text, tabs and all — a run is the last
                // field and is never split on.
                let text: String = parts.collect::<Vec<_>>().join("\t");
                if !text.trim().is_empty() {
                    page.runs.push(shotlister_engine::printed::Run::new(x, y, text));
                }
            }
            _ => {}
        }
    }
    pages
}

#[cfg(test)]
mod tests {
    use super::*;

    fn open_demo(dir: &std::path::Path) -> Handle {
        let device = DeviceId(1);
        let mut project = shotlister_storage::create(dir, "Daybreak", device).unwrap();
        demo::seed(project.doc_mut());
        Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        }
    }

    /// A scratch folder of this test's own — **and this process's own.**
    ///
    /// Ref 234: one test failed once in three runs and passed every time
    /// since, and 65 runs here could not make it happen again. The name is
    /// why. Without the process id, two `cargo test` runs going at once share
    /// every scratch directory, and the first thing each test does is *delete*
    /// its folder — so one run wipes the other's project out from under it,
    /// and the test that notices is whichever happened to be reading at that
    /// moment. **Several threads share this one checkout**, which is exactly
    /// how two runs come to overlap. `storage`'s version already did this.
    fn tmp(name: &str) -> PathBuf {
        let p = std::env::temp_dir()
            .join(format!("shotlister-ffi-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    /// **A commercial, end to end across the boundary.** The kind is set,
    /// a scene is made from a title and lands last with the next number, an
    /// AV script pasted with its tabs carried as \x1f makes the rest and
    /// reports, and the view says `kind`, `title`, `slug` and `audio`.
    #[test]
    fn a_commercial_kind_of_film_across_the_boundary() {
        let dir = tmp("commercial");
        let mut h = open_demo(&dir);

        assert!(dispatch(&mut h, "kind\tmusic video").contains("error"));
        let out = dispatch(&mut h, "kind\tcommercial");
        assert!(out.contains("\"kind\":\"commercial\""), "{out}");

        let before = h.project.doc().scenes_in_order().len();
        let out = dispatch(&mut h, "addtitled\tParty Montage\taudio\tMusic up. No VO.");
        assert!(out.contains("\"title\":\"Party Montage\""), "{out}");
        assert!(out.contains("\"audio\":\"Music up. No VO.\""), "{out}");
        assert!(out.contains("\"slug\":\"\""), "an untouched slug reads empty: {out}");
        let scenes = h.project.doc().scenes_in_order();
        assert_eq!(scenes.len(), before + 1);
        let last = *scenes.last().unwrap();
        assert_eq!(h.project.doc().scene_title(last), "Party Montage");
        assert_eq!(h.project.doc().scene_heading(last).as_deref(), Some("Party Montage"));

        // **The script is text** (2026-09-19): set on the film, quoted by
        // a shot, and the scene count does not move.
        let out = dispatch(&mut h, "setscript\t\tParty Montage. Quick cuts.\n\nThe camera on black.");
        assert!(out.contains("\"kept\":0"), "{out}");
        assert_eq!(h.project.doc().scenes_in_order().len(), before + 1);
        assert_eq!(h.project.doc().av_script(None), "Party Montage. Quick cuts.\n\nThe camera on black.");
        let placement = match h.project.doc().placements_in_scene(last).first().copied() {
            Some(p) => p,
            None => h.project.doc_mut().add_shot_to_scene(last).1,
        };
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        let view = dispatch(&mut h, &format!("tieshot\t{}\t\t15\t26", shot.0));
        assert!(view.contains("\"script\":\"Quick cuts.\""), "the shot quotes its words: {}", &view[..200]);

        let out = dispatch(&mut h, "renumber");
        assert!(out.contains("\"changed\":"), "{out}");
        let view = dispatch(&mut h, "view");
        assert!(view.contains("\"number\":\"1\",\"archived\":false,\"heading\":\"EXT. COUNTY JAIL"), "renumbered from 33 to 1");

        // and back to a film: nothing was lost, the old fallback returns
        dispatch(&mut h, "kind\tfilm");
        assert_eq!(h.project.doc().scene_title(last), "Party Montage");
        assert_ne!(h.project.doc().scene_heading(last).as_deref(), Some("Party Montage"));
    }

    /// The whole import, across the boundary: weigh it, take it, find it in the
    /// list, then ask for it laid out to draw.
    #[test]
    fn a_draft_is_weighed_then_taken_then_kept_then_drawn() {
        let dir = tmp("takescript");
        let mut h = open_demo(&dir);

        let draft = "33   INT. NEW PLACE - DAY\n\nShe waits.\n\nMELISSA\nYou're up early.\n";
        let ask = |name: &str, archive: &str| {
            format!("takescript\t{name}\tDRAFTJP.pdf\t2026-08-20T11:56:00Z\t0\tMELISSA\t{archive}\n{draft}")
        };

        // Weighing changes nothing at all, and says so in sentences.
        let before = dispatch(&mut h, "view");
        let weighed = dispatch(&mut h, &ask("weigh", "0"));
        assert!(weighed.contains("\"weighed\":true"), "{weighed}");
        assert!(weighed.contains("will be linked to the new revision"), "{weighed}");
        assert!(weighed.contains("Nothing will happen to"), "{weighed}");
        assert_eq!(dispatch(&mut h, "view"), before, "weighing wrote something");
        assert!(dispatch(&mut h, "revisions").contains("\"revisions\":[]"));

        // Taking it does what the weighing said.
        let taken = dispatch(&mut h, &ask("Revision (8/20/26)", "0"));
        assert!(taken.contains("\"weighed\":false"), "{taken}");
        assert!(taken.contains("\"linked\":1"), "{taken}");

        // And the project keeps it.
        let kept = dispatch(&mut h, "revisions");
        assert!(kept.contains("Revision (8/20/26)"), "{kept}");
        assert!(kept.contains("\"filename\":\"DRAFTJP.pdf\""), "{kept}");
        assert!(kept.contains("\"latest\":true"), "{kept}");

        // And it can be asked for as pages, ready to draw.
        let pages = dispatch(&mut h, "scriptpages");
        assert!(pages.contains("\"linesPerPage\":55"), "{pages}");
        assert!(pages.contains("\"kind\":\"character\""), "{pages}");
        assert!(pages.contains("\"indent\":22"), "{pages}");
        assert!(pages.contains("\"length\":"), "{pages}");
    }

    /// **A shot holds lines of the screenplay** (Ref 1553): tied by a
    /// selection's offsets and by words, drawn beside its lines in
    /// `scriptpages`, found again in a new draft, and reported (never moved)
    /// when a draft cuts its words.
    #[test]
    fn a_shot_holds_lines_of_the_screenplay_across_drafts() {
        let dir = tmp("playties");
        let mut h = open_demo(&dir);
        let draft = "33   INT. NEW PLACE - DAY\n\nShe waits.\n\nMELISSA\nYou're up early.\n";
        let take = |name: &str, at: &str, text: &str| {
            format!("takescript\t{name}\tCHB.pdf\t{at}\t0\t\t0\n{text}")
        };
        dispatch(&mut h, &take("One", "2026-10-06T10:00:00Z", draft));
        let scene = h.project.doc().scene_numbered("33").unwrap();
        let (shot, _) = h.project.doc_mut().add_shot_to_scene(scene);

        // The line's own range, as the pages give it, tied by a selection.
        let (_, _, _, read) = read_draft(&h, None).unwrap();
        let (from, to) = read.finds("She waits.")[0];
        let pages = dispatch(&mut h, "scriptpages");
        assert!(pages.contains(&format!("\"text\":\"She waits.\",\"added\":false,\"from\":{from},\"to\":{to},\"shots\":[]")), "{pages}");
        let view = dispatch(&mut h, &format!("playtie\t{}\t\t{from}\t{to}", shot.0));
        assert!(view.contains("\"playLines\":[\"She waits.\"]"), "{}", &view[..200.min(view.len())]);
        let pages = dispatch(&mut h, "scriptpages");
        assert!(pages.contains(&format!("\"from\":{from},\"to\":{to},\"shots\":[\"{}\"]", shot.0)), "{pages}");
        assert!(pages.contains("\"ties\":[{\"shot\":"), "{pages}");
        assert!(pages.contains("\"lost\":[]"), "{pages}");

        // By words, added; then a click lets the first go.
        let view = dispatch(&mut h, &format!("playwords\t{}\tadd\tYou're up early.", shot.0));
        assert!(view.contains("\"playLines\":[\"She waits.\",\"You're up early.\"]"), "{view}");
        assert!(dispatch(&mut h, &format!("playwords\t{}\tadd\tNot in it.", shot.0)).contains("not in the script"));
        dispatch(&mut h, &format!("playuntieat\t{}\t\t{}", shot.0, from + 1));
        assert_eq!(h.project.doc().play_excerpt(shot), "You're up early.");

        // A new draft without the words: weighed and taken, it says so; the
        // pages list the words as lost and draw them nowhere.
        let cut = "33   INT. NEW PLACE - DAY\n\nShe waits.\n\nMELISSA\nMorning.\n";
        let weighed = dispatch(&mut h, &take("weigh", "2026-10-07T10:00:00Z", cut));
        assert!(weighed.contains("1 shot holds lines this draft no longer has"), "{weighed}");
        assert!(weighed.contains("\"linesLost\":1"), "{weighed}");
        dispatch(&mut h, &take("Two", "2026-10-07T10:00:00Z", cut));
        let pages = dispatch(&mut h, "scriptpages");
        assert!(pages.contains("\"ties\":[]"), "{pages}");
        assert!(pages.contains("\"words\":[\"You're up early.\"]"), "{pages}");
        assert_eq!(h.project.doc().play_excerpt(shot), "You're up early.");

        // The old draft still draws it beside its line.
        let one = h.project.doc().revisions().into_iter().find(|r| r.name == "One").unwrap();
        let pages = dispatch(&mut h, &format!("scriptpages\t{}", one.id.0));
        assert!(pages.contains(&format!("\"shots\":[\"{}\"]", shot.0)), "{pages}");
    }

    /// **A script nobody numbered is in the script too.** Mirrorland,
    /// 2026-09-18: three headings with no numbers came in as scenes 1, 2, 3
    /// — numbered by position, which `read_with` does when the dials say a
    /// heading needs a number and none has one — and then every one of them
    /// said *Not in the script* on every device, because the pages were read
    /// back plainly and the same headings came out with no numbers at all.
    /// His ruling: *"it should work with or without scene numbers."*
    #[test]
    fn an_unnumbered_script_still_finds_its_scenes_on_the_page() {
        let dir = tmp("unnumbered");
        let mut h = open_demo(&dir);

        let draft = "INT. DANNY'S FAMILY DEN - NIGHT\n\nA framed photo.\n\nCARRIE\nAww.\n\n\
                     INT. SITTING ROOM - NIGHT\n\nThey sit.\n\n\
                     EXT. MARY & LARRY'S HOUSE - MOMENTS LATER\n\nA door.\n";
        // The dials a PDF gets: a heading must have a number.
        let take = format!(
            "takescript\tRevision (9/18/26)\tMIRRORLAND.pdf\t2026-09-18T16:38:00Z\t0,1,2\t\t0\t\
             number=1,duplicates=1,rooms=1\n{draft}"
        );
        let taken = dispatch(&mut h, &take);
        assert!(taken.contains("\"weighed\":false"), "{taken}");

        // The film's scenes were numbered by position on the way in.
        let view = dispatch(&mut h, "view");
        for number in ["\"number\":\"1\"", "\"number\":\"2\"", "\"number\":\"3\""] {
            assert!(view.contains(number), "the take did not number by position: {view}");
        }

        // And the pages, read back, carry the same numbers — so the panel
        // finds every scene rather than calling each one not in the script.
        let pages = dispatch(&mut h, "scriptpages");
        for label in ["\"label\":\"1\"", "\"label\":\"2\"", "\"label\":\"3\""] {
            assert!(pages.contains(label), "the pages lost the numbers: {pages}");
        }
        assert!(!pages.contains("\"label\":\"\""), "a scene came back unnumbered: {pages}");

        // The rules the draft was read with are the project's now.
        let dials = dispatch(&mut h, "detection");
        assert!(dials.contains("\"mustHaveANumber\":true"), "{dials}");
    }

    /// CONTINUOUS reaches the scene as the time it points at — Ref 257.
    ///
    /// The engine test covers the reading; this one covers the half that
    /// actually matters to him, which is what ends up *stored on the scene*
    /// and drawn in the column.
    #[test]
    fn a_scene_that_says_continuous_is_stored_as_the_time_before_it() {
        let dir = tmp("timeofday");
        let mut h = open_demo(&dir);

        let draft = "\
70   INT. KITCHEN - MORNING

She puts the kettle on.

71   INT. HALLWAY - CONTINUOUS

He is already at the door.

72   EXT. DRIVEWAY - MAGIC HOUR

The car is gone.
";
        // **`0,1,2` is the list of scenes ticked**, and it is the field that
        // caught me out writing this: passing `0` alone imported one scene and
        // looked exactly like the time-of-day reading having failed. The dials
        // are spelled out rather than inherited for the same reason — the demo
        // project carries its own, and a test that quietly read this draft
        // under them would be a test of the fixture.
        dispatch(
            &mut h,
            &format!(
                "takescript\tRevision\tDRAFTJP.pdf\t2026-08-22T11:56:00Z\t0,1,2\t\t0\tregular\t0\tnumber=0,rooms=0,contains=,forbid=\n{draft}"
            ),
        );

        let doc = h.project.doc();
        let times: Vec<String> = ["70", "71", "72"]
            .iter()
            .map(|number| {
                doc.scenes_in_order()
                    .into_iter()
                    .find(|id| doc.get(*id).and_then(|r| r.text(f::NUMBER)) == Some(number))
                    .and_then(|id| doc.get(id).and_then(|r| r.text(f::TIME_OF_DAY)))
                    .unwrap_or_default()
                    .to_string()
            })
            .collect();
        assert_eq!(
            times,
            vec!["DAY", "DAY", "SUNSET"],
            "CONTINUOUS takes the day; MAGIC HOUR snaps to a time the app offers"
        );
    }

    /// Every column carries a name, and so do the fields that are named
    /// without being columns — Ref 249.
    #[test]
    fn the_engine_says_what_every_field_is_called() {
        let dir = tmp("fieldnames");
        let mut h = open_demo(&dir);
        let v = dispatch(&mut h, "view");
        for (field, label) in [
            ("image", "Storyboard"),
            ("size", "Shot Size"),
            ("angle", "Shot Angle"),
            ("camera", "Camera"),
            ("day", "Shoot Day"),
            ("struck", "Shot"),
            // Named on screen without being a column of its own.
            ("pov", "POV"),
        ] {
            assert!(
                v.contains(&format!("\"{field}\":\"{label}\"")),
                "the engine did not name {field}"
            );
        }

        // A column somebody made carries a `kind` as well as a label, and that
        // is the only thing that tells the two apart. Reading a *label* as
        // "this is a custom column" made all fifteen built-ins custom on the
        // Mac the first time this shipped.
        // Kind first, then label — the order this command has always taken,
        // and the one I got backwards writing this.
        dispatch(&mut h, "addcolumn\ttext\tRigging");
        let v = dispatch(&mut h, "view");
        assert!(
            v.contains("\"label\":\"Rigging\",\"kind\":\"text\""),
            "a column somebody made carries both"
        );
        assert!(
            !v.contains("\"label\":\"Shot Angle\",\"kind\""),
            "a built-in column must not carry a kind"
        );
    }

    #[test]
    fn asking_for_pages_before_there_is_a_script_says_so() {
        let dir = tmp("nopages");
        let mut h = open_demo(&dir);
        assert!(dispatch(&mut h, "scriptpages").contains("no script yet"));
    }

    /// A relay that has never seen this film should be told everything.
    #[test]
    fn a_relay_with_nothing_on_it_is_offered_the_whole_list() {
        let dir = tmp("syncplan-empty");
        let mut h = open_demo(&dir);
        h.project.save().expect("saves");

        let plan = dispatch(
            &mut h,
            "syncplan\t{\"logs\":[]}\t{\"media\":[]}",
        );
        assert!(plan.contains("\"outgoing\":true"), "{plan}");
        assert!(plan.contains("\"incoming\":false"), "{plan}");
        assert!(plan.contains(".log"), "the session's own log should be offered: {plan}");
    }

    /// And one that already has exactly what we have should be told nothing.
    /// **Silence is the normal answer**, and a sync that always finds work to
    /// do is one that uploads the same file for ever.
    #[test]
    fn a_relay_that_is_already_up_to_date_asks_for_nothing() {
        let dir = tmp("syncplan-same");
        let mut h = open_demo(&dir);
        h.project.save().expect("saves");

        // Say the relay holds precisely what is in `changes/`, at the same
        // lengths — which for an append-only log means the same bytes.
        let here = shotlister_remote::local::local_inventory(h.project.path());
        let logs: Vec<String> = here
            .logs
            .iter()
            .map(|entry| format!("{{\"name\":\"{}\",\"size\":{}}}", entry.name, entry.size))
            .collect();
        let state = format!("{{\"logs\":[{}]}}", logs.join(","));

        let plan = dispatch(&mut h, &format!("syncplan\t{state}\t{{\"media\":[]}}"));
        assert!(plan.contains("\"steps\":0"), "{plan}");
        assert!(plan.contains("\"outgoing\":false"), "{plan}");
    }

    /// A log the relay has and this device does not is the whole point.
    #[test]
    fn another_devices_work_is_offered_for_collection() {
        let dir = tmp("syncplan-incoming");
        let mut h = open_demo(&dir);
        h.project.save().expect("saves");

        let theirs = "00000000000040e5-000000000000beef.log";
        let plan = dispatch(
            &mut h,
            &format!("syncplan\t{{\"logs\":[{{\"name\":\"{theirs}\",\"size\":400}}]}}\t{{\"media\":[]}}"),
        );
        assert!(plan.contains("\"incoming\":true"), "{plan}");
        assert!(plan.contains(theirs), "{plan}");
    }

    /// **Rubbish from the relay must never read as "the project is empty".**
    /// That is the answer that would look exactly like everything having been
    /// deleted, and the app must not act on it.
    #[test]
    fn a_broken_answer_from_the_relay_asks_for_nothing_to_come_down() {
        let dir = tmp("syncplan-rubbish");
        let mut h = open_demo(&dir);
        h.project.save().expect("saves");

        let plan = dispatch(&mut h, "syncplan\t<html>502 Bad Gateway</html>\t");
        assert!(plan.contains("\"incoming\":false"), "{plan}");
        assert!(!plan.contains("\"downloadLogs\":[\""), "{plan}");
    }

    #[test]
    fn a_scene_the_draft_dropped_is_archived_only_when_asked_and_keeps_its_shots() {
        let dir = tmp("archiving");
        let mut h = open_demo(&dir);

        let gone = h.project.doc().scene_numbered("34").expect("the demo has 34");
        let had = h.project.doc().placements_in_scene(gone).len();
        assert!(had > 0, "the scene has to have work on it for this to mean anything");

        let draft = "33   INT. NEW PLACE - DAY\n\nShe waits.\n";
        let take = format!(
            "takescript\tRevision\ta.pdf\t2026-08-20T11:56:00Z\t0\t\t1\n{draft}"
        );
        let taken = dispatch(&mut h, &take);
        assert!(taken.contains("moved to archived scenes"), "{taken}");

        let doc = h.project.doc();
        let still = doc.scene_numbered("34").expect("archived, never deleted");
        assert!(doc.is_archived(still));
        assert_eq!(doc.placements_in_scene(still).len(), had, "with its work on it");
    }

    #[test]
    fn a_revision_can_be_renamed_and_where_it_came_from_cannot() {
        let dir = tmp("renaming");
        let mut h = open_demo(&dir);
        let draft = "33   INT. NEW PLACE - DAY\n\nShe waits.\n";
        dispatch(
            &mut h,
            &format!("takescript\tFirst\ta.pdf\t2026-08-20T11:56:00Z\t0\t\t0\n{draft}"),
        );
        let id = h.project.doc().latest_revision().unwrap().id.0.to_string();

        dispatch(&mut h, &format!("renamerevision\t{id}\tFirst white"));
        let kept = dispatch(&mut h, "revisions");
        assert!(kept.contains("First white"), "{kept}");
        assert!(kept.contains("\"filename\":\"a.pdf\""), "{kept}");
    }

    /// The door the shell knocks on after decoding a PDF. The shell's whole job
    /// is turning a page into `run` lines; every judgement about what those
    /// runs mean is made below this, in the engine, and this proves the two
    /// halves meet.
    #[test]
    fn a_script_read_off_printed_pages_is_reported_and_nothing_is_written() {
        let dir = tmp("readscript");
        let mut h = open_demo(&dir);
        let before = dispatch(&mut h, "view");

        // Column 0 is an inch in, where scene numbers print; every character
        // after that is a tenth of an inch. So 5 is the 1.5" text block, 15 is
        // dialogue, and 27 is a character cue at 3.7".
        let page = "\
1    INT. KITCHEN - DAY                                        1

     She waits by the window.

     BATHROOM.

     Steam.

                         MELISSA
                   You're up early.

99   INT. NOWHERE - NEVER                                      99

     Nothing at all.
";
        let mut payload = String::from("readscript\t\npage\t612\t792\n");
        for (index, line) in page.lines().enumerate() {
            let y = 36.0 + index as f32 * 12.0;
            let trimmed = line.trim_start();
            if trimmed.is_empty() {
                continue;
            }
            let column = line.len() - trimmed.len();
            let x = 72.0 + column as f32 * 7.2;
            payload.push_str(&format!("run\t{x}\t{y}\t{trimmed}\n"));
        }

        let report = dispatch(&mut h, &payload);

        // Two numbered scenes and one room offered under the first.
        assert!(report.contains("\"detected\":3"), "{report}");
        assert!(report.contains("\"label\":\"1A\""), "{report}");
        assert!(report.contains("\"status\":\"room\""), "{report}");
        assert!(report.contains("\"accepted\":false"), "{report}");
        // The demo project has scene 1 and has never heard of 99.
        assert!(report.contains("\"new\":1"), "{report}");
        // And it found who is in it.
        assert!(report.contains("\"display\":\"Melissa\""), "{report}");
        // And it says what each scene costs, in the unit he works in.
        assert!(report.contains("\"length\":"), "{report}");
        assert!(report.contains("\"startsOnPage\":1"), "{report}");

        // Report, never invent: reading a draft changes nothing at all.
        assert_eq!(dispatch(&mut h, "view"), before);
    }

    #[test]
    fn pages_with_nothing_on_them_say_so_rather_than_reporting_an_empty_film() {
        let dir = tmp("readscript-empty");
        let mut h = open_demo(&dir);
        let report = dispatch(&mut h, "readscript\t\npage\t612\t792\n");
        assert!(report.contains("no text"), "{report}");
    }

    #[test]
    fn the_settings_reach_the_reader() {
        let dir = tmp("readscript-settings");
        let mut h = open_demo(&dir);
        let page = "\
1    INT. KITCHEN - DAY                                        1

     She waits.

     BATHROOM.

     Steam.
";
        let payload = |settings: &str| {
            let mut out = format!("readscript\t{settings}\npage\t612\t792\n");
            for (index, line) in page.lines().enumerate() {
                let y = 36.0 + index as f32 * 12.0;
                let trimmed = line.trim_start();
                if trimmed.is_empty() {
                    continue;
                }
                let x = 72.0 + (line.len() - trimmed.len()) as f32 * 7.2;
                out.push_str(&format!("run\t{x}\t{y}\t{trimmed}\n"));
            }
            out
        };

        let looking = dispatch(&mut h, &payload(""));
        assert!(looking.contains("\"status\":\"room\""), "{looking}");

        let not_looking = dispatch(&mut h, &payload("rooms=0"));
        assert!(!not_looking.contains("\"status\":\"room\""), "{not_looking}");
    }

    /// Two machines edited the same field while apart. Merging keeps both —
    /// nothing is ever lost — but one value is on screen and the other is only
    /// in the log, and somebody decided that without seeing the other. That is
    /// the one case worth saying out loud, and it has to be answerable **at
    /// any moment**: it usually arrives while the app is closed, so a question
    /// only asked after a pull would never see it. (The derivation itself is
    /// storage's, and proven there; this is the door the shell knocks on.)
    #[test]
    fn a_field_two_machines_decided_apart_can_be_asked_about_at_any_time() {
        let dir = tmp("clashes");
        let mac = DeviceId(1);
        let phone = DeviceId(2);

        let mut first = shotlister_storage::create(&dir, "Daybreak", mac).unwrap();
        let scene = first.doc_mut().create_scene("34");
        let (_shot, placement) = first.doc_mut().add_shot_to_scene(scene);
        first.doc_mut().set(placement, "lens", "37mm");
        first.save().unwrap();

        // The other machine opens the same folder, then both go out of range
        // and make a call about the same lens.
        let mut second = shotlister_storage::open(first.path(), phone).unwrap();
        first.doc_mut().set(placement, "lens", "40mm");
        first.save().unwrap();
        second.doc_mut().set(placement, "lens", "50mm");
        second.save().unwrap();
        second.pull().unwrap();

        let mut h = Handle {
            project: second,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };

        let out = dispatch(&mut h, "clashes");
        assert!(out.contains("\"count\":1"), "expected one clash, got {out}");
        assert!(out.contains("lens"), "the clash names its field: {out}");
        assert!(
            out.contains("40mm") && out.contains("50mm"),
            "both values are said, so a person can choose: {out}"
        );

        // Asked again it is still there — this is a standing question about
        // the log, not an announcement that gets used up.
        let again = dispatch(&mut h, "clashes");
        assert!(again.contains("\"count\":1"), "still standing: {again}");
    }

    /// **His complaint, 2026-08-21:** the same sync notice on every launch,
    /// however many times it had been clicked away. Because a clash is derived
    /// from the log rather than stored, nothing a shell does to its own copy
    /// of the list can end one — and the Mac's OK emptied a Swift array. The
    /// answer has to reach the log, which is what settling is.
    #[test]
    fn a_settled_clash_does_not_come_back_when_the_project_is_opened_again() {
        let dir = tmp("settle");
        let mac = DeviceId(1);
        let phone = DeviceId(2);

        let mut first = shotlister_storage::create(&dir, "Daybreak", mac).unwrap();
        let scene = first.doc_mut().create_scene("33");
        let (_shot, placement) = first.doc_mut().add_shot_to_scene(scene);
        first.doc_mut().set(placement, "lens", "37mm");
        first.save().unwrap();

        // Two machines decide the same three fields while out of range of
        // each other — his Shot 33A, exactly.
        let mut second = shotlister_storage::open(first.path(), phone).unwrap();
        for (field, mine, theirs) in [
            ("lens", "37mm", "47mm"),
            ("size", "W/OTS", "M/OTS"),
            ("movement", "Static", "Tracking Backward"),
        ] {
            first.doc_mut().set(placement, field, mine);
            second.doc_mut().set(placement, field, theirs);
        }
        first.save().unwrap();
        second.save().unwrap();
        second.pull().unwrap();

        let path = second.path().to_path_buf();
        let mut h = Handle {
            project: second,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };

        let standing = dispatch(&mut h, "clashes");
        assert!(standing.contains("\"count\":3"), "three to answer: {standing}");

        // Both values reach the shell, so the notice can offer either — Ref
        // 231. Before this it could only ever keep what was on screen.
        assert!(standing.contains("\"other\":"), "the other value is sent: {standing}");

        dispatch(&mut h, "settle");
        let after = dispatch(&mut h, "clashes");
        assert!(after.contains("\"count\":0"), "settled, so none stand: {after}");

        // The whole of the complaint: it has to survive being put away and
        // opened again, because that is when it kept coming back.
        h.project.save().unwrap();
        drop(h);
        let reopened = shotlister_storage::open(&path, phone).unwrap();
        assert_eq!(
            reopened.doc().clashes().len(),
            0,
            "a settled disagreement does not return on the next launch"
        );
    }

    #[test]
    fn the_view_carries_the_real_list() {
        let dir = tmp("view");
        let h = open_demo(&dir);
        let out = view(&h);
        assert!(out.contains("\"title\":\"Daybreak\""));
        assert!(out.contains("Frontal Dirty Single on Milo"));
        // the letters that matter, in script order under their scene
        assert!(out.contains("\"number\":\"34A\""));
        assert!(out.contains("\"number\":\"34E\""));
        // two cameras on one moment
        assert!(out.contains("A-Cam"));
        assert!(out.contains("B-Cam"));
    }

    #[test]
    fn grouping_by_day_gives_the_shooting_order() {
        let dir = tmp("day");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "group\tday");
        let first = out.find("\"number\":\"33A\"").unwrap();
        let c = out.find("\"number\":\"34C\"").unwrap();
        let a = out.find("\"number\":\"34A\"").unwrap();
        // 34C is shot before 34A even though its letter comes after
        assert!(first < c && c < a, "day order should not be letter order");
    }

    #[test]
    fn setting_a_lens_goes_through_the_engine() {
        let dir = tmp("set");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "view");
        let shot = out
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        let after = dispatch(&mut h, &format!("set\t{shot}\tlens\t40mm"));
        assert!(after.contains("40mm"), "the new lens should be in the view");
    }

    #[test]
    fn an_unknown_command_says_so_rather_than_dying() {
        let dir = tmp("unknown");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "wibble");
        assert!(out.contains("no command called wibble"));
    }
}

#[cfg(test)]
mod board_tests {
    use super::*;

    /// The same, and the same reason — see the copy above (Ref 234).
    fn tmp(name: &str) -> PathBuf {
        let p = std::env::temp_dir()
            .join(format!("shotlister-ffi-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    fn open_demo(dir: &std::path::Path) -> Handle {
        let device = DeviceId(1);
        let mut project = shotlister_storage::create(dir, "Daybreak", device).unwrap();
        demo::seed(project.doc_mut());
        Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        }
    }

    /// Pull the value of a key out of JSON without a parser — enough for a test
    /// to say what it means about a payload this shape.
    fn after(text: &str, needle: &str) -> String {
        text.split(needle)
            .nth(1)
            .unwrap_or("")
            .split(['"', ',', '}'])
            .find(|s| !s.is_empty())
            .unwrap_or("")
            .to_string()
    }

    /// **A day is also a flat run of shots** — the shoot-day list on the
    /// phone. Each carries `struck`, and `day order` moves one within the day
    /// and answers with the board so the list can redraw from it.
    #[test]
    fn a_day_lists_its_shots_in_order_and_one_can_be_moved_or_struck() {
        let dir = tmp("dayshots");
        let mut h = open_demo(&dir);
        let board = dispatch(&mut h, "board");
        // the first day's flat list — the fixture seats every shot on day one
        let first_day = board.split("\"run\":[").nth(1).unwrap();
        let numbers: Vec<String> = first_day
            .split("\"number\":\"")
            .skip(1)
            .map(|s| s.split('"').next().unwrap().to_string())
            .take(3)
            .collect();
        assert!(numbers.len() >= 2, "the day carries its shots flat: {first_day}");
        assert!(first_day.contains("\"struck\":false"), "nothing is struck yet");

        // move the second shot to the front of the day
        let second = first_day
            .split("\"placement\":\"")
            .nth(2)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        let out = dispatch(&mut h, &format!("day\torder\t{second}\t0"));
        assert!(out.contains("\"days\":["), "answered with the board: {out}");
        let moved = out.split("\"run\":[").nth(1).unwrap();
        let now_first = moved
            .split("\"placement\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap();
        assert_eq!(now_first, second, "the moved shot leads the day");

        // strike it, and the board says so
        let shot = moved
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        dispatch(&mut h, &format!("strike\t{shot}\t1"));
        let board = dispatch(&mut h, "board");
        let led = board.split("\"run\":[").nth(1).unwrap();
        let first_entry = led.split("},{").next().unwrap();
        assert!(first_entry.contains("\"struck\":true"), "got: {first_entry}");
    }

    /// **Sorted by Shooting Order, the list is the days in order** and a drop
    /// before another shot seats it there — the number stays its own.
    #[test]
    fn shooting_order_sorts_by_day_and_a_drop_lands_before_its_neighbour() {
        let dir = tmp("shootbefore");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "sort\tshootingorder");
        assert!(out.contains("\"groupBy\":\"day\""), "grouped by day: {}", &out[..out.len().min(400)]);
        let days = h.project.doc().days_in_order();
        let first = days[0];
        let on_first = h.project.doc().placements_on_day(first);
        assert!(on_first.len() >= 3, "the fixture seats shots on day one");
        let (a, c) = (on_first[0], on_first[2]);
        let number = h.project.doc().display_number(a);

        dispatch(&mut h, &format!("shootbefore\t{}\t{}\t{}", a.0, first.0, c.0));
        let now = h.project.doc().placements_on_day(first);
        assert_eq!(now.iter().position(|p| *p == a).unwrap() + 1, now.iter().position(|p| *p == c).unwrap());
        assert_eq!(h.project.doc().display_number(a), number, "the shot keeps its number");

        // To the end of a day, then off every day; one undo each.
        dispatch(&mut h, &format!("shootbefore\t{}\t{}\t", a.0, first.0));
        assert_eq!(h.project.doc().placements_on_day(first).last(), Some(&a));
        dispatch(&mut h, &format!("shootbefore\t{}\t\t", a.0));
        assert!(!h.project.doc().placements_on_day(first).contains(&a));
        dispatch(&mut h, "undo");
        assert_eq!(h.project.doc().placements_on_day(first).last(), Some(&a));

        // Any other sort reads by scene again.
        let out = dispatch(&mut h, "sort\t");
        assert!(out.contains("\"groupBy\":\"scene\""));
    }

    /// **`day put` seats a shot on a day at a place in its running order** —
    /// from another day, or within its own — and one undo takes it back.
    #[test]
    fn day_put_seats_a_shot_at_its_place_on_any_day() {
        let dir = tmp("dayput");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "day\tnew");
        let days = h.project.doc().days_in_order();
        let (first, last) = (days[0], *days.last().unwrap());
        let on_first = h.project.doc().placements_on_day(first);
        assert!(on_first.len() >= 3, "the fixture seats shots on day one");
        let (a, b) = (on_first[1], on_first[2]);

        let out = dispatch(&mut h, &format!("day\tput\t{}\t{}\t0", a.0, last.0));
        assert!(out.contains("\"days\":["), "answered with the board: {out}");
        dispatch(&mut h, &format!("day\tput\t{}\t{}\t0", b.0, last.0));
        assert_eq!(h.project.doc().placements_on_day(last), vec![b, a]);
        assert!(!h.project.doc().placements_on_day(first).contains(&a), "it left day one");

        dispatch(&mut h, &format!("day\tput\t{}\t{}\t1", b.0, last.0));
        assert_eq!(h.project.doc().placements_on_day(last), vec![a, b]);

        dispatch(&mut h, "undo");
        assert_eq!(h.project.doc().placements_on_day(last), vec![b, a], "one put, one undo");
    }

    /// **Mood boards.** A name, a wall, and the promise that deleting the wall
    /// does not take the pictures off it.
    #[test]
    fn a_mood_board_is_made_named_and_read_back() {
        let dir = tmp("moodboard");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "addboard\tNight Exteriors");
        assert!(out.contains("\"boards\":["), "the view model carries boards");
        assert!(out.contains("Night Exteriors"), "the board is named: {out}");
    }

    /// **The trap this crate keeps falling into** — a mutating command that
    /// leaves `unsaved` at nought is silent data loss on the phone, which has
    /// no list of which commands write and saves on that number alone.
    #[test]
    fn every_mood_board_command_says_the_project_changed() {
        let dir = tmp("moodboardunsaved");
        let mut h = open_demo(&dir);

        let out = dispatch(&mut h, "addboard\tAnya");
        assert_ne!(after(&out, "\"unsaved\":"), "0", "addboard must report");
        let id = after(&out, "\"boards\":[{\"id\":\"");
        assert!(!id.is_empty(), "a board was made: {out}");

        h.project.save().unwrap();
        let out = dispatch(&mut h, &format!("renameboard\t{id}\tThe Diner"));
        assert_ne!(after(&out, "\"unsaved\":"), "0", "renameboard must report");
        assert!(out.contains("The Diner"));

        h.project.save().unwrap();
        let out = dispatch(&mut h, &format!("deleteboard\t{id}"));
        assert_ne!(after(&out, "\"unsaved\":"), "0", "deleteboard must report");
        assert!(!out.contains("The Diner"), "the board is gone: {out}");
    }

    #[test]
    fn a_mood_board_needs_a_name() {
        let dir = tmp("moodboardnameless");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "addboard\t");
        assert!(out.contains("needs a name"), "refused: {out}");
    }

    #[test]
    fn the_board_has_lanes_and_a_place_for_the_unscheduled() {
        let dir = tmp("board");
        let h = open_demo(&dir);
        let out = board(&h);
        assert!(out.contains("\"days\":["), "days are the lanes");
        assert!(out.contains("\"unscheduled\":["));
        // scenes carry the heading a strip board reads by
        assert!(out.contains("INT.") || out.contains("EXT."));
        // Every field the app reads has to be here. A shot on a strip lost its
        // title when the title column was added, and because the app reads the
        // whole board or none of it, the board simply came up empty — a film
        // with everything scheduled looked like a film with nothing scheduled.
        for field in [
            "\"placement\":", "\"number\":", "\"title\":", "\"description\":",
        ] {
            assert!(out.contains(field), "a strip's shots are missing {field}");
        }
    }

    #[test]
    fn dragging_a_scene_onto_a_day_moves_all_of_its_shots() {
        let dir = tmp("assign");
        let mut h = open_demo(&dir);
        let scenes = h.project.doc().scenes_in_order();
        let days = h.project.doc().days_in_order();
        let (scene, day) = (scenes[0], days[1]);
        let shots = h.project.doc().shot_count_in_scene(scene);

        dispatch(&mut h, &format!("scene\t{}\t{}", scene.0, day.0));

        let on_day = h
            .project
            .doc()
            .placements_on_day(day)
            .into_iter()
            .filter(|p| reference(&h.project, *p, f::SCENE) == Some(scene))
            .count();
        assert_eq!(on_day, shots, "the whole scene went, not part of it");
    }

    #[test]
    fn a_scene_split_over_two_days_says_so_on_both() {
        let dir = tmp("split");
        let mut h = open_demo(&dir);
        // a scene only splits if it has shots to split — 33 is a single setup
        let scene = h
            .project
            .doc()
            .scenes_in_order()
            .into_iter()
            .find(|s| h.project.doc().shot_count_in_scene(*s) > 1)
            .unwrap();
        let days = h.project.doc().days_in_order();
        dispatch(&mut h, &format!("scene\t{}\t{}", scene.0, days[0].0));

        // pull one shot out onto the other day, the way a long scene really goes
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let out = dispatch(&mut h, &format!("place\t{}\t{}", placement.0, days[1].0));

        assert!(
            out.contains("\"elsewhere\":[\"Day"),
            "each half should name the day the other half is on: {out}"
        );
    }

    #[test]
    fn unscheduling_a_scene_puts_it_back_in_the_waiting_column() {
        let dir = tmp("unschedule");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let days = h.project.doc().days_in_order();
        dispatch(&mut h, &format!("scene\t{}\t{}", scene.0, days[0].0));
        let out = dispatch(&mut h, &format!("scene\t{}\tnone", scene.0));

        let waiting = out.split("\"unscheduled\":").nth(1).unwrap();
        assert!(waiting.contains(&format!("\"scene\":\"{}\"", scene.0)));
    }

    #[test]
    fn a_frame_can_take_any_of_the_four_sides() {
        let dir = tmp("layout");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();

        let out = dispatch(&mut h, &format!("layout\t{shot}\tright\t0.4"));
        assert!(out.contains("\"framePosition\":\"right\""));
        assert!(out.contains("\"frameWidth\":0.4"));

        // and a width outside the readable range is clamped, not refused
        let out = dispatch(&mut h, &format!("layout\t{shot}\tbelow\t9"));
        assert!(out.contains("\"frameWidth\":1"));
    }

    #[test]
    fn the_technical_line_follows_the_tables_columns() {
        let dir = tmp("technical");
        let mut h = open_demo(&dir);
        let before = dispatch(&mut h, "view");
        assert!(before.contains("37mm"), "the lens is in the line");

        // hide the lens column and the line loses it too — one order, one place
        dispatch(&mut h, "column\tlens\t0");
        let out = dispatch(&mut h, "view");
        let line = after(&out, "\"technical\":\"");
        assert!(!line.contains("37mm"), "a hidden column is not in the line");
    }

    /// **The film's icon and colour go in the film**, which is the whole of
    /// the fix: they used to be read off a cache file one Mac happened to
    /// have. Written here, they are in the view every shell draws from, and in
    /// the manifest the switcher and the relay read without opening anything.
    #[test]
    fn a_film_keeps_its_own_icon_and_colour() {
        let dir = tmp("mark");
        let mut h = open_demo(&dir);

        let out = dispatch(&mut h, "setmark\tM10 2 L18 18 L2 18 Z\t#d44c47\thand");
        assert!(!out.contains("\"error\""), "got: {out}");
        assert!(out.contains("\"markColour\":\"#D44C47\""), "not in the view: {out}");
        assert!(out.contains("\"markSource\":\"hand\""), "no source in the view: {out}");

        // On the outside of the package too, so a row in the switcher can be
        // drawn without opening the film.
        h.project.save().unwrap();
        let package = dir.join("Daybreak.shotlist");
        let manifest = std::fs::read_to_string(package.join("manifest.json")).unwrap();
        assert!(manifest.contains("\"markColour\": \"#D44C47\""), "got: {manifest}");
        assert!(manifest.contains("M10 2 L18 18 L2 18 Z"), "got: {manifest}");

        // And it comes back the same on the next opening.
        let reopened = shotlister_storage::open(&package, DeviceId(2)).unwrap();
        assert_eq!(
            reopened.doc().mark().map(|m| m.colour),
            Some("#D44C47".to_string())
        );
    }

    #[test]
    fn a_colour_nobody_could_draw_is_refused_and_nothing_is_written() {
        let dir = tmp("markbad");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "setmark\tM10 2 L18 18 L2 18 Z\tvermilion\thand");
        assert!(out.contains("a colour reads like"), "got: {out}");
        assert!(h.project.doc().mark().is_none(), "half a mark was written");

        // And the three fields have one door. A plain `set` onto them says so
        // rather than writing an outline with no colour.
        let project = h.project.doc().project_id().unwrap().0.to_string();
        let said = dispatch(&mut h, &format!("set\t{project}\tmark_colour\t#D44C47"));
        assert!(said.contains("set with setmark"), "got: {said}");
    }

    #[test]
    fn clearing_the_icon_leaves_the_film_saying_nothing() {
        let dir = tmp("markclear");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "setmark\tM10 2 L18 18 L2 18 Z\t#D44C47\tconsole");
        let out = dispatch(&mut h, "setmark\t\t\t");
        assert!(!out.contains("\"error\""), "got: {out}");
        assert!(out.contains("\"markPath\":\"\""), "got: {out}");
        assert!(out.contains("\"markSource\":\"\""), "got: {out}");
    }

    /// **The kit off the spec sheets** (Ref 1627): `recordkit` puts the
    /// sheet's lenses on the Lens list and its bodies on the cameras, shows
    /// the kit in the view, and marks a shot whose lens is not on it. A plain
    /// `set` cannot write the kit, and `recordkit none` lets it go.
    #[test]
    fn a_film_takes_its_kit_from_the_spec_sheet() {
        let dir = tmp("recordkit");
        let mut h = open_demo(&dir);
        let kit = r#"[{"name":"Shoot 1","start":"","end":"","sheet":"0123456789abcdef0123456789abcdef","lead":true,"cameras":[{"label":"A Cam","body":"Alexa 35"}],"lenses":["18mm","Angenieux 45-165mm"]}]"#;
        // the switch is Off on a film that never set it, and Off offers nothing
        let out = dispatch(&mut h, "kitmode\tfollow");
        assert!(out.contains("\"kitMode\":\"follow\""), "got: {out}");
        assert!(dispatch(&mut h, "kitmode\tsometimes").contains("\"error\""));
        let undo_before = h.project.doc().undo_label().map(str::to_string);
        let out = dispatch(&mut h, &format!("recordkit\t{kit}"));
        assert!(!out.contains("\"error\""), "got: {out}");
        assert!(out.contains("\"kit\":[{\"name\":\"Shoot 1\""), "got: {out}");
        assert!(out.contains("\"offKit\":{"), "a demo shot's lens is not on a two-lens sheet: {out}");
        let off = dispatch(&mut h, "kitmode\toff");
        assert!(!off.contains("\"offKit\""), "Off: no shot offers Add to Spec Sheet: {off}");
        dispatch(&mut h, "kitmode\tfollow");
        assert!(h.project.doc().vocabulary("lens").iter().any(|l| l == "Angenieux 45-165mm"));
        let _ = undo_before;
        assert_eq!(h.project.doc().undo_label(), Some("Set spec sheet switch"), "taking the kit adds no undo step of its own");
        let project = h.project.doc().project_id().unwrap().0.to_string();
        let said = dispatch(&mut h, &format!("set\t{project}\tkit\t[]"));
        assert!(said.contains("set with recordkit"), "got: {said}");
        let said = dispatch(&mut h, "recordkit\tnot json");
        assert!(said.contains("\"error\""), "got: {said}");
        let out = dispatch(&mut h, "recordkit\tnone");
        assert!(out.contains("\"kit\":[]"), "got: {out}");
        assert!(!out.contains("\"offKit\""), "no kit, nothing to offer: {out}");
    }

    /// **The project record's facts, mirrored into the film** — the
    /// console's door (one-record plan, 2026-10-05). The record's name is
    /// what the film is shown by, its people are the film's, and from then on
    /// a plain `set` from any screen cannot type over them.
    #[test]
    fn a_film_takes_its_facts_from_the_project_record() {
        let dir = tmp("recordfacts");
        let mut h = open_demo(&dir);
        let scenes_before = h.project.doc().scenes_in_order().len();
        let out = dispatch(
            &mut h,
            "recordfacts\ttitle\tLet's Bake\tdirector\tOllie Hart Brennan\tproducer\tMarta Delgado\tclient\tAcme Express\tagency\tFabrica",
        );
        assert!(!out.contains("\"error\""), "got: {out}");
        assert!(out.contains("\"displayTitle\":\"Let's Bake\""), "got: {out}");
        assert!(out.contains("\"title\":\"Daybreak\""), "the film's own title stays: {out}");
        assert!(out.contains("\"director\":\"Ollie Hart Brennan\""), "got: {out}");
        assert!(out.contains("\"producer\":\"Marta Delgado\""), "got: {out}");
        assert!(out.contains("\"client\":\"Acme Express\""), "got: {out}");
        assert!(out.contains("\"agency\":\"Fabrica\""), "got: {out}");
        assert!(out.contains("\"factsSource\":\"console\""), "got: {out}");
        assert_eq!(h.project.doc().scenes_in_order().len(), scenes_before);

        // Kept, and the same on the next opening.
        h.project.save().unwrap();
        let reopened = shotlister_storage::open(&dir.join("Daybreak.shotlist"), DeviceId(2)).unwrap();
        assert!(reopened.doc().facts_from_record());
        assert_eq!(reopened.doc().shown_title(), "Let's Bake");

        // Any screen typing over the record is turned away.
        let project = h.project.doc().project_id().unwrap().0.to_string();
        let said = dispatch(&mut h, &format!("set\t{project}\tproducer\tDaniel Fairweather"));
        assert!(said.contains("change it in Projects Console"), "got: {said}");
        let said = dispatch(&mut h, &format!("set\t{project}\tfacts_source\t"));
        assert!(said.contains("set with recordfacts"), "got: {said}");
        // The film's own title is still the film's.
        let said = dispatch(&mut h, &format!("set\t{project}\ttitle\tDaybreak Two"));
        assert!(!said.contains("\"error\""), "got: {said}");
    }

    #[test]
    fn a_card_is_laid_over_the_film_and_kept_out_of_its_logs() {
        let dir = tmp("cardlaid");
        let mut h = open_demo(&dir);
        let before = h.project.doc().changes().len();
        let out = dispatch(
            &mut h,
            r##"card	{"facts":{"title":"Let's Bake","director":"Ollie Hart Brennan","producer":"Marta Delgado","client":"Acme Express"},"mark":{"path":"M1 1 L2 2 Z","colour":"#D44C47"},"type":"Music Video"}"##,
        );
        assert!(!out.contains("\"error\""), "got: {}", &out[..out.len().min(600)]);
        assert!(out.contains("\"displayTitle\":\"Let's Bake\""), "got: {}", &out[..out.len().min(600)]);
        assert!(out.contains("\"title\":\"Daybreak\""), "the film's own title stays");
        assert!(out.contains("\"director\":\"Ollie Hart Brennan\""), "got: {}", &out[..out.len().min(600)]);
        assert!(out.contains("\"kind\":\"commercial\""), "Music Video is a commercial");
        assert!(out.contains("\"markColour\":\"#D44C47\""), "got: {}", &out[..out.len().min(600)]);
        assert!(out.contains("\"card\":true"), "got: {}", &out[..out.len().min(600)]);
        assert_eq!(h.project.doc().changes().len(), before, "nothing written");

        // Saved and opened again with no card: the film's own words.
        h.project.save().unwrap();
        let reopened = shotlister_storage::open(&dir.join("Daybreak.shotlist"), DeviceId(2)).unwrap();
        assert_eq!(reopened.doc().shown_title(), "Daybreak");
        assert_eq!(reopened.doc().kind(), shotlister_engine::FilmKind::Film);

        // An earlier version on screen wears the card too.
        let saved = dispatch(&mut h, "saveversion\tBefore");
        assert!(!saved.contains("\"error\""), "got: {}", &saved[..saved.len().min(600)]);
        let id = saved.split("\"saved\":\"").nth(1).unwrap().split('"').next().unwrap().to_string();
        let looked = dispatch(&mut h, &format!("lookat\t{id}"));
        assert!(looked.contains("\"displayTitle\":\"Let's Bake\""), "got: {}", &looked[..looked.len().min(600)]);

        // Off again.
        dispatch(&mut h, "looknow");
        let off = dispatch(&mut h, "card\tnone");
        assert!(off.contains("\"displayTitle\":\"Daybreak\""), "got: {}", &off[..off.len().min(600)]);
        assert!(off.contains("\"card\":false"), "got: {}", &off[..off.len().min(600)]);
        let bad = dispatch(&mut h, "card\tnot a card");
        assert!(bad.contains("not a card"), "got: {}", &bad[..bad.len().min(600)]);
    }

    #[test]
    fn the_shoot_picker_narrows_and_move_to_shoot_writes_one_step() {
        let dir = tmp("shoots");
        let mut h = open_demo(&dir);
        let s1 = "4acab7b3b555897c7c58dce7762aca55";
        let s2 = "50ad95105a93869dd1c97f9e1a45a05a";
        let card = format!(
            r#"card	{{"facts":{{}},"type":"Commercial","shoots":[{{"id":"{s1}","label":"Shoot 1","kind":"Shoot 1","n":1,"start":"2026-07-09","state":"Wrapped"}},{{"id":"{s2}","label":"Style Server","kind":"Shoot 2","n":2,"start":"2026-10-06","end":"2026-10-07","state":"Next"}}]}}"#
        );
        let all = dispatch(&mut h, &card);
        assert!(all.contains(r#""label":"Style Server""#), "the view lists the shoots");
        let scenes = h.project.doc().scenes_in_order();
        assert!(scenes.len() >= 2);
        let before = h.project.doc().changes().len();
        // Nothing of Shoot 2's yet: every scene falls back to the first.
        let on2 = dispatch(&mut h, &format!("facet	shoot	{s2}"));
        assert!(on2.contains(&format!(r#""shootOn":"{s2}""#)), "got: {}", &on2[..on2.len().min(400)]);
        assert!(!on2.contains(&format!(r#""id":"{}","shoot""#, scenes[0].0)));
        assert_eq!(h.project.doc().changes().len(), before, "picking writes nothing");
        // Move to Shoot…
        let moved = dispatch(&mut h, &format!("shootmove	{s2}	{}", scenes[0].0));
        assert!(moved.contains(&format!(r#""id":"{}","shoot":"{s2}""#, scenes[0].0)), "got: {}", &moved[..moved.len().min(400)]);
        assert!(h.project.doc().can_undo());
        let bad = dispatch(&mut h, &format!("shootmove	ffffffff	{}", scenes[1].0));
        assert!(bad.contains("not one this project has"));
        // A scene made while Shoot 2 is picked is born into it.
        let id = h.project.doc_mut().create_scene("99");
        assert_eq!(h.project.doc().own_shoot(id).as_deref(), Some(s2));
        // All Shoots again.
        let back = dispatch(&mut h, "facet	shoot	");
        assert!(back.contains(r#""shootOn":"""#));
        // The converter's dry run writes nothing.
        let n = h.project.doc().changes().len();
        let dry = dispatch(&mut h, "shootplan");
        assert!(dry.starts_with(r#"{"applied":0,"plan":{"#), "got: {}", &dry[..dry.len().min(300)]);
        assert_eq!(h.project.doc().changes().len(), n);
        // No shoots on the card: the converter has nothing to go by.
        dispatch(&mut h, "card	none");
        assert!(dispatch(&mut h, "shootplan").contains("lists no shoots"));
    }

    #[test]
    fn a_word_that_is_not_a_record_fact_is_refused_and_letting_go_hands_them_back() {
        let dir = tmp("recordfactsbad");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "recordfacts\tdirector\tSomeone\tlens\t35mm");
        assert!(out.contains("not a fact the record gives a film"), "got: {out}");
        assert!(!h.project.doc().facts_from_record(), "half a set was written");
        let out = dispatch(&mut h, "recordfacts\tdirector");
        assert!(out.contains("in pairs"), "got: {out}");

        dispatch(&mut h, "recordfacts\tproducer\tMarta Delgado");
        let out = dispatch(&mut h, "recordfacts\tnone");
        assert!(out.contains("\"factsSource\":\"\""), "got: {out}");
        assert!(out.contains("\"producer\":\"Marta Delgado\""), "the words stay: {out}");
        let project = h.project.doc().project_id().unwrap().0.to_string();
        let said = dispatch(&mut h, &format!("set\t{project}\tproducer\tDaniel Fairweather"));
        assert!(!said.contains("\"error\""), "the film owns it again: {said}");
    }

    /// The export commands' named options — the narrowing, not the drawing.
    /// **The page's type reaches the printed page.** Two owners of these
    /// numbers is what this replaced, so the only test worth having is that
    /// the export actually reads them.
    #[test]
    fn the_document_page_is_set_the_way_the_project_says() {
        let dir = tmp("docstyle");
        let mut h = open_demo(&dir);

        let did = dispatch(&mut h, "docstyle\tbody\t14\tsans\tas");
        assert!(!did.contains("\"error\""), "got: {did}");
        // Said back in the view, resolved, so the app never keeps its own copy
        // of what standard means.
        assert!(did.contains("\"class\":\"body\""), "no docStyle in the view");
        assert!(did.contains("\"size\":14"), "the size did not reach the view: {did}");

        let out = dir.join("document.html");
        let wrote = dispatch(
            &mut h,
            &format!("print\tdocument\t{}", out.to_string_lossy()),
        );
        assert!(!wrote.contains("error"), "got: {wrote}");
        let css = std::fs::read_to_string(&out).unwrap();
        // 14 points against a 16-point root, written the way `doc::rem`
        // writes it.
        assert!(css.contains("0.8750rem"), "the body size never reached the page");
        assert!(css.contains("font-family: var(--sans)"),
                "the face never reached the page");

        // **A case, on a class that can honestly take one.** `uppercase` is in
        // this stylesheet whatever happens — the credits have been upper-cased
        // since the page was first drawn — so asserting it proves nothing.
        // Lower-casing them is a thing only this can have done.
        assert!(!css.contains("text-transform: lowercase"), "not yet");
        let cased = dispatch(&mut h, "docstyle\tcredits\t8\tmono\tlower");
        assert!(!cased.contains("\"error\""), "got: {cased}");
        let wrote = dispatch(
            &mut h,
            &format!("print\tdocument\t{}", out.to_string_lossy()),
        );
        assert!(!wrote.contains("error"), "got: {wrote}");
        let css = std::fs::read_to_string(&out).unwrap();
        assert!(css.contains("text-transform: lowercase"),
                "the case never reached the page");

        // **And a case cannot be forced on words he types.** The engine drops
        // it, so the page can never shout back a sentence he wrote.
        let refused = dispatch(&mut h, "docstyle\tbody\t14\tsans\tupper");
        assert!(!refused.contains("\"error\""), "got: {refused}");
        assert!(refused.contains("\"class\":\"body\""));
        let body_case = refused
            .split("\"class\":\"body\"")
            .nth(1)
            .and_then(|s| s.split("\"case\":\"").nth(1))
            .and_then(|s| s.split('"').next())
            .unwrap_or("");
        assert_eq!(body_case, "as", "a typed class must not take a case");
        let _ = std::fs::remove_file(&out);
    }

    #[test]
    fn an_export_can_be_asked_for_one_day_or_for_scenes_but_not_both() {
        let dir = tmp("export-options");
        let mut h = open_demo(&dir);

        // The fixture ships two days: the first holds all sixteen shots, the
        // second is empty. That pair is what makes this test honest — asking
        // for the empty day has to come back genuinely empty, not merely
        // "smaller", which a page could be for any number of reasons.
        // **A day's id is the one followed by its label.** Taking every
        // `"id"` by position broke the day a strip's picture began carrying
        // one of its own (2026-09-19): the second id on the page was a
        // frame, not Day 2, and the "empty day" was a media record.
        let board = dispatch(&mut h, "board");
        let ids: Vec<String> = board
            .split("\"id\":\"")
            .skip(1)
            .filter(|s| s.split('"').nth(2) == Some("label"))
            .map(|s| s.split('"').next().unwrap().to_string())
            .collect();
        let (busy, empty) = (&ids[0], &ids[1]);

        let write = |h: &mut Handle, name: &str, option: &str| {
            let path = dir.join(name);
            let out = dispatch(h, &format!("print\ttable\t{}\t{option}", path.display()));
            assert!(out.contains("\"path\""), "got: {out}");
            std::fs::read_to_string(&path).unwrap()
        };

        let busy_page = write(&mut h, "busy.html", &format!("day={busy}"));
        let empty_page = write(&mut h, "empty.html", &format!("day={empty}"));

        // **A cell, not a mention.** The stylesheet's own comments have said
        // `33A` since 2026-09-17 (the number column's story), so a bare
        // `contains` found the shot on a page with no shots on it.
        assert!(busy_page.contains(">33A<"), "the day with the shots should carry them");
        assert!(!empty_page.contains(">33A<"), "the empty day should carry none");
        assert!(empty_page.contains("Nothing matches these filters"));

        // Unscheduled is a real answer, not an absence — and with every shot
        // on day one, it is legitimately empty here too.
        let loose = write(&mut h, "loose.html", "day=unscheduled");
        assert!(!loose.contains(">33A<"));

        // Both at once has no honest meaning and is refused rather than
        // silently resolved to one of them.
        let both = dispatch(
            &mut h,
            &format!("print\ttable\t{}\tday={busy}\tscenes=1", dir.join("x.html").display()),
        );
        assert!(both.contains("not both"), "got: {both}");
    }

    /// **The export box's Order, Filter and Days** (2026-10-15): As in Table
    /// carries the Table's sort, a schedule narrows to exactly the days
    /// picked out of sixty, and several days in one file put each day on a
    /// sheet of its own in the Table but not in the Document.
    #[test]
    fn the_export_box_orders_filters_and_picks_days() {
        let dir = tmp("export-arrange");
        let mut h = open_demo(&dir);
        // Sixty days, the sixteen shots spread across them three days apart.
        for n in 0..60 {
            let date = format!("2026-11-{:02}", (n % 28) + 1);
            dispatch(&mut h, &format!("day\tnew\t{date}"));
        }
        let days: Vec<Id> = h.project.doc().days_in_order();
        assert!(days.len() >= 60, "{} days", days.len());
        let shots = h.project.doc().all_placements();
        for p in &shots {
            h.project.doc_mut().unschedule(*p);
        }
        for (i, p) in shots.iter().enumerate().take(15) {
            h.project.doc_mut().schedule(*p, days[i * 4]);
        }
        let label = |h: &Handle, i: usize| h.project.doc().day_label(days[i]).unwrap();
        let page = |h: &mut Handle, name: &str, which: &str, options: &str| {
            let path = dir.join(name);
            let out = dispatch(h, &format!("print\t{which}\t{}\t{options}", path.display()));
            assert!(out.contains("\"path\""), "got: {out}");
            std::fs::read_to_string(&path).unwrap()
        };
        // Days 12 to 18 and 22 (positions 11..=17 and 21): shots sit on
        // positions 12, 16 and 20 — so 12 and 16 are in, 20 is not.
        let picked: Vec<String> = (11..=17).chain([21]).map(|i| days[i].0.to_string()).collect();
        let sched = page(&mut h, "sched.html", "table",
                         &format!("arrange=schedule\tdays={}\tdaypages=1", picked.join(",")));
        let heads: Vec<String> = (0..days.len()).map(|i| format!("<h2>{}</h2>", label(&h, i))).collect();
        let head = |i: usize| heads[i].clone();
        assert!(sched.contains(&head(12)), "day 13 by position holds a shot");
        assert!(sched.contains(&head(16)));
        assert!(!sched.contains(&head(20)), "an unpicked day stays out");
        assert!(!sched.contains(&head(8)), "an unpicked day stays out");
        assert!(!sched.contains("Unscheduled"), "the unscheduled were not picked");
        assert_eq!(sched.matches("group fresh-page").count(), 1, "two days, the second on a fresh sheet");
        // The unscheduled go last when ticked.
        let with_loose = page(&mut h, "loose.html", "table",
                              &format!("arrange=schedule\tdays={},unscheduled", picked.join(",")));
        let at_loose = with_loose.rfind("Unscheduled").expect("unscheduled is there");
        assert!(at_loose > with_loose.find(&head(16)).unwrap(), "and last");
        // The Document runs on: no fresh sheet per day when days share a file.
        let doc = page(&mut h, "doc.html", "document",
                       &format!("arrange=schedule\tdays={}\tdaypages=1", picked.join(",")));
        assert!(!doc.contains("group fresh-page"), "the document does not break by day");

        // As in Table carries the Table's sort; Script does not.
        dispatch(&mut h, "sort\tdescription\tdesc");
        let numbers: Vec<String> =
            shots.iter().filter_map(|p| h.project.doc().display_number(*p)).collect();
        let order = |page: &str| -> Vec<String> {
            let mut found: Vec<(usize, String)> = numbers.iter()
                .filter_map(|n| page.find(&format!(">{n}<")).map(|at| (at, n.clone())))
                .collect();
            found.sort();
            found.into_iter().map(|(_, n)| n).collect()
        };
        let table = page(&mut h, "astable.html", "table", "arrange=table");
        let script = page(&mut h, "script.html", "table", "arrange=script");
        let direct = page(&mut h, "direct.html", "table", "");
        assert_eq!(order(&table), order(&direct), "As in Table reads like the Table");
        assert_ne!(order(&table), order(&script), "Script order does not take the sort");

        // The Table's filter is kept with filter=table and dropped without.
        dispatch(&mut h, "sort\t\tasc");
        dispatch(&mut h, &format!("facet\tday\t{}", days[12].0));
        let kept = page(&mut h, "kept.html", "table", "arrange=table\tfilter=table");
        let cleared = page(&mut h, "cleared.html", "table", "arrange=table");
        assert!(order(&kept).len() < order(&cleared).len(), "the filter narrows only when kept");
        let info = dispatch(&mut h, "exportinfo");
        assert!(info.contains(&format!("\"filter\":[\"{}\"]", label(&h, 12))), "got: {info}");
        assert!(info.matches("\"label\"").count() >= 60);
    }

    #[test]
    fn export_options_are_order_free_and_ignore_what_they_do_not_know() {
        let dir = tmp("export-order");
        let mut h = open_demo(&dir);

        // Reversed, and carrying an option this engine has never heard of —
        // an older engine meeting a newer app still draws the page.
        let path = dir.join("p.html");
        let out = dispatch(
            &mut h,
            &format!("print\ttable\t{}\tscale=1.5\tfuture=42\tcolumns=description", path.display()),
        );
        assert!(out.contains("\"path\""), "got: {out}");

        let page = std::fs::read_to_string(&path).unwrap();
        assert!(page.contains("<th>Description</th>"));
        assert!(!page.contains("<th>Shot Size</th>"), "columns= should narrow the table");

        // **The ratio, not the number.** This asserted `font-size: 24.00px`,
        // which was `ROOT * scale` back when every page was exported at the
        // root size. It is not any more: each kind of page now carries its own
        // designed base — 1 for the document, 0.85 for the table and the
        // storyboard, 4/3 for a share page — so that 100% means "as this page
        // was designed" (his instruction, 2026-09-01) rather than "16 pixels".
        // A table at 1.5 is 20.40px now, and would move again the next time a
        // page is redesigned, which is not a thing this test is about.
        //
        // What it is about is that `scale=` reaches the root size at all. So it
        // exports the same page twice and checks the sizes stand in the ratio
        // asked for, which stays true however the page is drawn.
        let plain = dir.join("plain.html");
        dispatch(
            &mut h,
            &format!("print\ttable\t{}\tscale=1.0\tcolumns=description", plain.display()),
        );
        let root_of = |html: &str| -> f64 {
            let at = html.find("html { font-size: ").expect("no root size on the page");
            let rest = &html[at + "html { font-size: ".len()..];
            rest[..rest.find("px").expect("root size is not in pixels")]
                .parse()
                .expect("root size is not a number")
        };
        let one = root_of(&std::fs::read_to_string(&plain).unwrap());
        let half_again = root_of(&page);
        assert!(one > 0.0, "the page has no root size at all");
        assert!(
            (half_again - one * 1.5).abs() < 0.01,
            "scale= should reach the root size: {one} at 1.0 became {half_again} at 1.5"
        );
    }

    /// `xlsx` never applied its own `columns=` option — `print` did, three
    /// lines below the same `Options` struct, and `xlsx` simply did not
    /// carry them over. Silent until the spreadsheet started mirroring
    /// `sheet.columns` for real (2026-08-27): the per-day export asks for
    /// columns without `day` in them, and the day column kept showing up
    /// anyway. This is the same fact as the `print` test above, proven for
    /// the other writer.
    #[test]
    fn xlsx_also_honours_its_own_columns_option() {
        let dir = tmp("xlsx-columns");
        let mut h = open_demo(&dir);

        let path = dir.join("narrow.xlsx");
        let out = dispatch(
            &mut h,
            &format!("xlsx\t{}\tcolumns=description", path.display()),
        );
        assert!(out.contains("\"path\""), "got: {out}");
        let bytes = std::fs::read(&path).unwrap();
        // Sheet1's own header row only — the hidden Ranges tab always lists
        // every vocabulary field's name for its own dropdowns, "Shot Size"
        // included, whether or not that column is on the main sheet.
        let start = bytes.windows(9).position(|w| w == b"<row r=\"1").unwrap();
        let end = start + bytes[start..].windows(6).position(|w| w == b"</row>").unwrap() + 6;
        let header_row = std::str::from_utf8(&bytes[start..end]).unwrap();
        assert!(header_row.contains(">Description<"), "the column that was asked for should be there");
        assert!(!header_row.contains(">Shot Size<"), "columns= should narrow the workbook same as print");
    }

    #[test]
    fn the_workbook_can_be_asked_for_one_day() {
        let dir = tmp("xlsx-day");
        let mut h = open_demo(&dir);
        // Same pair as the page test: day one holds all sixteen, day two none.
        let board = dispatch(&mut h, "board");
        let ids: Vec<String> = board
            .split("\"id\":\"")
            .skip(1)
            .map(|s| s.split('"').next().unwrap().to_string())
            .collect();

        let busy = dir.join("busy.xlsx");
        let empty = dir.join("empty.xlsx");
        let out = dispatch(&mut h, &format!("xlsx\t{}\tday={}", busy.display(), ids[0]));
        assert!(out.contains("\"path\""), "got: {out}");
        dispatch(&mut h, &format!("xlsx\t{}\tday={}", empty.display(), ids[1]));

        // A workbook is a zip, so its bytes are not readable here — but a
        // day with sixteen rows and pictures in it cannot weigh the same as
        // a day with none, and that difference is the filter doing its job.
        let busy = std::fs::metadata(&busy).unwrap().len();
        let empty = std::fs::metadata(&empty).unwrap().len();
        assert!(busy > empty, "a full day should outweigh an empty one: {busy} vs {empty}");
    }

    /// The path the live link writes to rides on the project record, the same
    /// way the Drive links already do — set through the ordinary `set`, read
    /// back off the project.
    #[test]
    fn the_linked_workbook_path_is_remembered_on_the_project() {
        let dir = tmp("excel-path");
        let mut h = open_demo(&dir);
        assert!(dispatch(&mut h, "view").contains("\"excelPath\":\"\""));

        let project = h.project.doc().project_id().unwrap();
        let out = dispatch(&mut h, &format!("set\t{}\texcel_path\t/tmp/Daybreak.xlsx", project.0));
        assert!(out.contains("\"excelPath\":\"/tmp/Daybreak.xlsx\""), "got: {out}");

        // Unlinking is emptying it, not a second concept.
        let cleared = dispatch(&mut h, &format!("set\t{}\texcel_path\t", project.0));
        assert!(cleared.contains("\"excelPath\":\"\""));
    }

    /// Where the file lives and whether it keeps itself current are two
    /// separate facts on the project record — his ask, 2026-08-27: a location
    /// and an on/off switch. Neither implies the other.
    #[test]
    fn the_workbook_can_be_linked_without_being_kept_current() {
        let dir = tmp("excel-auto");
        let mut h = open_demo(&dir);
        assert!(dispatch(&mut h, "view").contains("\"excelAuto\":\"\""));

        let project = h.project.doc().project_id().unwrap();
        dispatch(&mut h, &format!("set\t{}\texcel_path\t/tmp/Daybreak.xlsx", project.0));
        let out = dispatch(&mut h, &format!("set\t{}\texcel_auto\t1", project.0));
        assert!(out.contains("\"excelAuto\":\"1\""), "got: {out}");
        assert!(out.contains("\"excelPath\":\"/tmp/Daybreak.xlsx\""), "a location set earlier should survive changing the switch: {out}");

        let off = dispatch(&mut h, &format!("set\t{}\texcel_auto\t0", project.0));
        assert!(off.contains("\"excelAuto\":\"0\""));
        assert!(off.contains("\"excelPath\":\"/tmp/Daybreak.xlsx\""), "turning the switch off should not drop the location: {off}");
    }

    #[test]
    fn a_ratio_is_typed_rather_than_chosen() {
        let dir = tmp("ratio");
        let mut h = open_demo(&dir);
        let project = h.project.doc().project_id().unwrap();
        let out = dispatch(&mut h, &format!("set\t{}\taspect_ratio\t1.85", project.0));
        assert!(out.contains("\"ratio\":1.85"));

        let refused = dispatch(&mut h, &format!("set\t{}\taspect_ratio\twide", project.0));
        assert!(refused.contains("reads like 2.39"));
    }

    #[test]
    fn studio_picks_one_of_the_sheets_frames_and_the_sheet_owns_the_sensor() {
        let dir = tmp("frames");
        let mut h = open_demo(&dir);
        let refused = dispatch(&mut h, "frame\tSocial");
        assert!(refused.contains("spec sheet"), "{refused}");
        let card = r#"{"facts":{},"sheet":{"frames":[{"name":"Delivery","ratio":"2.39:1","main":true},{"name":"Social","ratio":"9:16"}],"sensors":[{"label":"A Cam","name":"Open Gate","width":36.7,"height":25.54}]}}"#;
        let laid = dispatch(&mut h, &format!("card\t{card}"));
        assert!(laid.contains("\"frames\":[{\"name\":\"Delivery\""), "{laid}");
        let picked = dispatch(&mut h, "frame\tSocial");
        assert!(picked.contains("\"frame\":\"Social\""), "{picked}");
        assert!(picked.contains("\"ratio\":0.5625"), "{picked}");
        assert!(dispatch(&mut h, "frame\tNope").contains("no frame called"));
        let guides = dispatch(&mut h, "frameguides\ton");
        assert!(guides.contains("\"frameGuides\":true"), "{guides}");
        let unit = h.project.doc_mut().create_unit("A-Cam", "");
        let typed = dispatch(&mut h, &format!("unit\tsensor\t{}\t24.89\t18.66\tSuper 35", unit.0));
        assert!(typed.contains("comes from the spec sheet"), "{typed}");
    }

    #[test]
    fn the_lists_screen_knows_what_leans_on_each_value() {
        let dir = tmp("lists");
        let mut h = open_demo(&dir);
        let out = lists(&h);
        assert!(out.contains("\"field\":\"lens\""));
        assert!(out.contains("\"value\":\"37mm\""));

        // renaming reaches the shots, which is the point of renaming
        let changed = dispatch(&mut h, "list\trename\tlens\t37mm\t35mm");
        let n: i64 = after(&changed, "\"changed\":").parse().unwrap();
        assert!(n > 0, "shots on 37mm should have moved to 35mm");
        assert!(dispatch(&mut h, "view").contains("35mm"));
    }

    #[test]
    fn a_share_page_carries_its_frames_inside_it() {
        let dir = tmp("share");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        let encoded = b64::encode(b"foobar");
        dispatch(&mut h, &format!("paste\t{shot}\t100\t42\tpng\t{encoded}"));

        let out_path = dir.join("share.html");
        let reply = dispatch(
            &mut h,
            &format!("share\t{}\t16 August 2026\t1\t1\t1", out_path.display()),
        );
        assert!(reply.contains("\"path\""), "{reply}");

        let page = std::fs::read_to_string(&out_path).unwrap();
        // no folder of images alongside it — the frame is in the file
        assert!(page.contains("data:image/png;base64,Zm9vYmFy"));
        // and it says what it is rather than pretending to be live
        assert!(page.contains("snapshot"));
    }

    #[test]
    fn a_share_page_can_hold_back_the_crew_shorthand() {
        let dir = tmp("share-notes");
        let mut h = open_demo(&dir);
        let out_path = dir.join("share.html");
        dispatch(
            &mut h,
            &format!("share\t{}\t16 August 2026\t0\t1\t1", out_path.display()),
        );
        let page = std::fs::read_to_string(&out_path).unwrap();
        assert!(
            !page.contains("Frame is a way to hide 2 cameras"),
            "notes were held back and should not be in the file"
        );
    }

    #[test]
    fn the_workbook_writes_his_four_tabs_with_a_frame_inside_it() {
        let dir = tmp("xlsx");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        // A real PNG signature and IHDR, so image_dimensions has something
        // genuine to read rather than a stand-in the test made up.
        let mut png = vec![0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        png.extend([0, 0, 0, 0x0D]); // IHDR length
        png.extend(b"IHDR");
        png.extend(4u32.to_be_bytes()); // width
        png.extend(3u32.to_be_bytes()); // height
        png.extend([0u8; 5]); // rest of IHDR, unread
        let encoded = b64::encode(&png);
        dispatch(&mut h, &format!("paste\t{shot}\t4\t3\tpng\t{encoded}"));

        let out_path = dir.join("shots.xlsx");
        let reply = dispatch(&mut h, &format!("xlsx\t{}", out_path.display()));
        assert!(reply.contains("\"path\""), "{reply}");

        let bytes = std::fs::read(&out_path).unwrap();
        let contains = |needle: &str| {
            bytes.windows(needle.len()).any(|w| w == needle.as_bytes())
        };
        for tab in ["Master Shot List", "Group by Day", "Group by Sequence", "Ranges"] {
            assert!(contains(tab), "missing tab {tab}");
        }
        assert!(contains("xl/media/image1.png"), "the frame should be embedded");
        assert!(!contains("state=\"hidden\""), "Ranges should be visible");
    }

    #[test]
    fn a_heic_frame_leaves_the_workbook_cell_blank_rather_than_broken() {
        let dir = tmp("xlsx-heic");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        let encoded = b64::encode(b"not really heic bytes");
        dispatch(&mut h, &format!("paste\t{shot}\t100\t100\theic\t{encoded}"));

        let out_path = dir.join("shots.xlsx");
        let reply = dispatch(&mut h, &format!("xlsx\t{}", out_path.display()));
        assert!(reply.contains("\"path\""), "{reply}");
        let bytes = std::fs::read(&out_path).unwrap();
        assert!(
            !bytes.windows(9).any(|w| w == b"<drawing "),
            "a format Excel cannot draw should not produce a drawing part"
        );
    }

    #[test]
    fn looking_for_something_narrows_the_list_and_says_what_it_hid() {
        let dir = tmp("filter");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "filter\t0\tpharmacy");
        // the outline still holds the whole film — it is the rows that narrow
        let rows = out.split("\"groups\":").nth(1).unwrap();
        assert!(rows.contains("PHARMACY"));
        assert!(!rows.contains("COUNTY JAIL"), "the jail does not match");
        // and the outline can say so rather than the film quietly getting shorter
        let hidden: i64 = after(&out, "\"hiddenScenes\":").parse().unwrap();
        assert!(hidden > 0, "scenes went out of sight and should be counted");

        // **And it says which ones.** A count cannot tell the app whether the
        // scene somebody is sitting on is one of them — and if it is, the app
        // falls back to the first scene in the film without saying so. Ref 101.
        let named = out
            .split("\"hiddenSceneIds\":[")
            .nth(1)
            .expect("the filter names what it hid")
            .split(']')
            .next()
            .unwrap();
        assert_eq!(
            named.split(',').filter(|s| !s.trim().is_empty()).count() as i64,
            hidden,
            "as many named as counted: {named}"
        );

        let cleared = dispatch(&mut h, "filter\t0\t");
        let rows = cleared.split("\"groups\":").nth(1).unwrap();
        assert!(rows.contains("COUNTY JAIL"));
        // Nothing narrowing means nothing hidden, and nothing named.
        assert!(
            cleared.contains("\"hiddenSceneIds\":[]"),
            "with no filter, no scene is out of sight"
        );
    }

    #[test]
    fn a_cut_shot_can_be_kept_out_of_sight() {
        let dir = tmp("struck");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        dispatch(&mut h, &format!("strike\t{shot}\t1"));

        let showing = dispatch(&mut h, "filter\t0\t");
        assert!(showing.contains("\"struck\":true"));
        let hiding = dispatch(&mut h, "filter\t1\t");
        assert!(!hiding.contains("\"struck\":true"), "cut shots were hidden");
    }

    #[test]
    fn a_new_project_is_empty_until_the_sample_is_asked_for() {
        let dir = tmp("empty");
        let device = DeviceId(1);
        let project = shotlister_storage::create(&dir, "Untitled", device).unwrap();
        let mut h = Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };
        assert!(!view(&h).contains("Frontal Dirty Single"), "nobody else's shots");

        let filled = dispatch(&mut h, "demo");
        assert!(filled.contains("Frontal Dirty Single"));
    }

    /// The record goes with its last use (his ruling, 2026-09-19) — and
    /// the same bytes pasted again are therefore encoded afresh, not
    /// handed the old copy back.
    #[test]
    fn taking_a_frame_off_a_shot_takes_the_files_record_with_it() {
        let dir = tmp("detach");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        let encoded = b64::encode(b"a frame");
        let after_paste = dispatch(&mut h, &format!("paste\t{shot}\t10\t4\tpng\t{encoded}"));
        let mref = after(&after_paste, "\"ref\":\"");

        let before = h.project.doc().store().count_of_kind(&Kind::Media);
        let out = dispatch(&mut h, &format!("detach\t{mref}"));
        assert!(out.contains("\"stills\":[]"), "the shot has no frames now");
        // nothing else used it, so the record went too
        assert_eq!(h.project.doc().store().count_of_kind(&Kind::Media), before - 1);
        // …and the same bytes are not "already stored" any more
        let again = dispatch(&mut h, &format!("paste\t{shot}\t10\t4\tpng\t{encoded}"));
        assert!(again.contains("\"ref\":\""), "{again}");
        assert_eq!(h.project.doc().store().count_of_kind(&Kind::Media), before);
    }

    #[test]
    fn a_sheet_can_come_back_in_and_says_what_it_did() {
        let dir = tmp("import");
        let mut h = open_demo(&dir);
        let file = dir.join("back.csv");
        std::fs::write(
            &file,
            "Scene,Shot,Description,Size,Lens\n\
             34,34A,Milo French Over — run until \"Did you tell them that you need them?\",M/OTS,40mm\n\
             99,99A,A shot from a scene this project has never heard of,W,27mm\n",
        )
        .unwrap();

        let out = dispatch(&mut h, &format!("import\t{}", file.display()));
        assert!(out.contains("\"import\""), "{out}");
        // the report and the list are siblings — nesting one inside the other is
        // exactly the bug that made the app decode nothing at all
        assert!(
            out.contains("},\"view\":{"),
            "the list comes back beside the report, not inside it"
        );
        // the existing shot took the new lens rather than being added twice
        assert!(out.contains("40mm"));
        assert!(out.contains("99"), "the new scene was made");
    }

    #[test]
    fn two_cameras_on_one_moment_know_about_each_other() {
        let dir = tmp("setup");
        let h = open_demo(&dir);
        let out = view(&h);
        // the demo carries the real list's cross-coverage pairs
        let ties = out.matches("\"setupId\":\"").count();
        assert!(ties >= 4, "the French Overs and the frontal dirties are tied");

        // and a tied pair shares one key, which is what the bracket is drawn from
        let a = after(&out, "\"number\":\"34A\"");
        assert!(!a.is_empty());
    }

    #[test]
    fn tying_a_third_camera_joins_the_pair_rather_than_starting_a_new_one() {
        let dir = tmp("tie");
        let mut h = open_demo(&dir);
        let shots: Vec<String> = view(&h)
            .split("\"shot\":\"")
            .skip(1)
            .take(3)
            .map(|s| s.split('"').next().unwrap().to_string())
            .collect();

        dispatch(&mut h, &format!("tie\t{}\t{}", shots[0], shots[1]));
        dispatch(&mut h, &format!("tie\t{}\t{}", shots[1], shots[2]));

        let first = id_from(&shots[0]).unwrap();
        let siblings = h.project.doc().setup_siblings(first);
        assert_eq!(siblings.len(), 2, "all three roll at the same moment");

        dispatch(&mut h, &format!("untie\t{}", shots[2]));
        assert_eq!(h.project.doc().setup_siblings(first).len(), 1);
    }

    #[test]
    fn moving_a_shot_moves_it_in_the_reading_you_are_in() {
        let dir = tmp("reorder");
        let mut h = open_demo(&dir);
        let scene = h
            .project
            .doc()
            .scenes_in_order()
            .into_iter()
            .find(|s| h.project.doc().shot_count_in_scene(*s) > 2)
            .unwrap();
        let placements = h.project.doc().placements_in_scene(scene);
        let last = *placements.last().unwrap();
        let wanted = h.project.doc().display_number(last).unwrap();

        // in story order it moves in the scene
        let out = dispatch(&mut h, &format!("reorder\t{}\t0", last.0));
        let first_in_scene = h.project.doc().placements_in_scene(scene)[0];
        assert_eq!(first_in_scene, last, "it went to the top of its scene");
        // and its letter did not change — letters belong to the placement, not
        // to where it sits in the running order
        assert!(out.contains(&format!("\"number\":\"{wanted}\"")));
    }

    #[test]
    fn an_archived_scene_is_flagged_and_kept() {
        let dir = tmp("archive");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let shots_before = h.project.doc().shot_count_in_scene(scene);

        let out = dispatch(&mut h, &format!("archivescene\t{}\t1", scene.0));
        assert!(out.contains("\"archived\":true"), "the flag rides the scene");
        // nothing was destroyed: the shots are all still there
        assert_eq!(h.project.doc().shot_count_in_scene(scene), shots_before);

        let out = dispatch(&mut h, &format!("archivescene\t{}\t0", scene.0));
        assert!(!out.contains("\"archived\":true"));
    }

    #[test]
    fn a_shot_wears_its_colour_in_the_view() {
        let dir = tmp("shotcolour");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let out = dispatch(&mut h, &format!("set\t{}\tcolour\tE5484D", shot.0));
        assert!(
            out.contains("\"colour\":\"E5484D\""),
            "the row carries the colour the shot was given"
        );
        // and clearing it takes the key out of the row entirely
        let out = dispatch(&mut h, &format!("set\t{}\tcolour\t", shot.0));
        assert!(!out.contains("\"colour\":\"E5484D\""));
    }

    #[test]
    fn a_camera_can_be_created_and_a_blank_husk_cannot_be_seen() {
        let dir = tmp("addunit");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "addunit\tC-Cam\t7B4BC4");
        assert!(out.contains("\"label\":\"C-Cam\""));
        assert!(out.contains("\"colour\":\"7B4BC4\""));
        // undoing the creation leaves a field-stripped husk, which the view
        // must not offer as a camera
        let out = dispatch(&mut h, "undo");
        assert!(!out.contains("\"label\":\"C-Cam\""));
    }

    /// The id of a camera in the view, found by the name it wears. `"id"` is
    /// serialised immediately before `"label"` in a unit, so walking back from
    /// the label is safe and does not need a JSON parser in the tests.
    fn unit_id(out: &str, label: &str) -> String {
        let at = out
            .find(&format!("\"label\":\"{label}\""))
            .unwrap_or_else(|| panic!("no camera called {label} in the view"));
        let head = &out[..at];
        let id_at = head.rfind("\"id\":\"").expect("a unit carries its id first");
        let rest = &head[id_at + 6..];
        rest[..rest.find('"').unwrap()].to_string()
    }

    #[test]
    fn a_camera_can_be_renamed_recoloured_and_taken_away() {
        let dir = tmp("unitedit");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "addunit\tC-Cam\t7B4BC4");
        let unit = unit_id(&out, "C-Cam");

        let out = dispatch(&mut h, &format!("unit\tname\t{unit}\tC Camera"));
        assert!(out.contains("\"label\":\"C Camera\""));
        assert!(!out.contains("\"label\":\"C-Cam\""), "the old name should be gone");

        // **A camera with no name is refused rather than obeyed.** The view
        // skips nameless units as husks, so obeying would make a camera vanish
        // from the app while still sitting in the file.
        let refused = dispatch(&mut h, &format!("unit\tname\t{unit}\t"));
        assert!(refused.contains("\"error\""), "{refused}");
        let out = dispatch(&mut h, "view");
        assert!(out.contains("\"label\":\"C Camera\""), "the name should have held");

        let out = dispatch(&mut h, &format!("unit\tcolour\t{unit}\tE5484D"));
        assert!(out.contains("\"colour\":\"E5484D\""));

        let out = dispatch(&mut h, &format!("unit\tremove\t{unit}"));
        assert!(!out.contains("\"label\":\"C Camera\""), "the camera should be gone");
    }

    #[test]
    fn taking_a_camera_away_leaves_the_shots_that_named_it() {
        let dir = tmp("unitgone");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "addunit\tC-Cam\t7B4BC4");
        let unit = unit_id(&out, "C-Cam");

        let out = dispatch(&mut h, "view");
        let shot = out
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        dispatch(&mut h, &format!("set\t{shot}\tlens\t40mm"));
        let out = dispatch(&mut h, &format!("set\t{shot}\tunit\t{unit}"));
        assert!(out.contains("C-Cam"), "the shot should name the camera");

        // **Report, never destroy.** The camera goes; the shot keeps its lens
        // and everything else of its own, and simply stops naming a camera.
        let out = dispatch(&mut h, &format!("unit\tremove\t{unit}"));
        assert!(!out.contains("C-Cam"), "no shot should still name it");
        assert!(out.contains("40mm"), "the shot should keep its own lens");
        assert!(
            out.contains(&format!("\"shot\":\"{shot}\"")),
            "the shot itself should still be there"
        );
    }

    #[test]
    fn the_column_order_can_be_set_and_the_line_follows_it() {
        let dir = tmp("colorder");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "columnorder\tlens,size,description,image");
        let lens = out.find("\"name\":\"lens\"").unwrap();
        let size = out.find("\"name\":\"size\"").unwrap();
        assert!(lens < size, "lens was asked for first");

        // the document page's technical line reads in the same order
        let line = after(&out, "\"technical\":\"");
        assert!(line.starts_with("37mm") || line.starts_with("27mm"), "{line}");
    }

    #[test]
    fn priority_is_a_project_list_like_any_other() {
        let dir = tmp("priority");
        let mut h = open_demo(&dir);
        let shot = view(&h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string();
        let out = dispatch(&mut h, &format!("set\t{shot}\tpriority\tMust Have"));
        assert!(out.contains("\"priority\":\"Must Have\""));
        // typing one the project has not seen teaches it, as anywhere else
        assert!(dispatch(&mut h, "vocab\tpriority").contains("Must Have"));
    }

    #[test]
    fn adding_a_shot_gives_it_the_next_free_letter() {
        let dir = tmp("addshot");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let before = h.project.doc().shot_count_in_scene(scene);
        dispatch(&mut h, &format!("addshot\t{}", scene.0));
        assert_eq!(h.project.doc().shot_count_in_scene(scene), before + 1);
    }

    /// Ref 57, from the door the phone actually knocks on. Everything the phone
    /// writes into `location.json` has to survive the round trip, and the scene
    /// has to keep the script's own word for where it happens.
    #[test]
    fn a_location_survives_the_round_trip_and_reaches_the_view() {
        let dir = tmp("locations");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "addlocation\tCounty Jail");
        let place = h.project.doc().locations_in_order()[0];
        for (field, value) in [
            ("address", "1 Jail Rd, Barstow CA"),
            ("latitude", "34.0500"),
            ("longitude", "-118.2500"),
            ("notes", "Ask about the gate code"),
            ("capturedBy", "iPhone"),
        ] {
            dispatch(&mut h, &format!("setlocation\t{}\t{}\t{}", place.0, field, value));
        }

        let scene = h.project.doc().scenes_in_order()[0];
        h.project.doc_mut().set(scene, f::LOCATION, "CAR");
        dispatch(&mut h, &format!("scenelocation\t{}\t{}", scene.0, place.0));

        let seen = dispatch(&mut h, "view");
        assert!(seen.contains("County Jail"), "the location reaches the view");
        assert!(seen.contains("1 Jail Rd, Barstow CA"));
        assert!(seen.contains("34.0500"));
        assert_eq!(h.project.doc().location_of_scene(scene), Some(place));
        assert_eq!(
            h.project.doc().get(scene).unwrap().text(f::LOCATION),
            Some("CAR"),
            "the slugline's word is a different fact and is untouched"
        );

        // And taking the location away leaves the scene whole.
        dispatch(&mut h, &format!("deletelocation\t{}", place.0));
        assert!(h.project.doc().get(place).is_none());
        assert_eq!(h.project.doc().location_of_scene(scene), None);
        assert_eq!(
            h.project.doc().get(scene).unwrap().text(f::LOCATION),
            Some("CAR")
        );
    }

    /// A scene that moved to a new number, all the way across the boundary —
    /// Ref 241.
    ///
    /// The half worth pinning here is the **field order**: `moves` was added
    /// after the detection settings on purpose, so a caller that sends
    /// settings and no moves still gets its settings.
    #[test]
    fn a_moved_scene_is_reported_and_only_carried_across_when_ticked() {
        let dir = tmp("moved");
        let mut h = open_demo(&dir);

        // Give scene 54 words of its own, so there is something to recognise
        // it by, and print the same scene at 60.
        let fifty_four = h
            .project
            .doc()
            .scenes_in_order()
            .into_iter()
            .find(|id| h.project.doc().get(*id).and_then(|r| r.text(f::NUMBER)) == Some("54"))
            .expect("scene 54");
        h.project.doc_mut().set(
            fifty_four,
            f::SCRIPT,
            "They walk in through the crowd and the noise takes the room away.",
        );
        let shots = h.project.doc().placements_in_scene(fifty_four).len();
        assert!(shots > 0, "scene 54 carries the work this is about");

        let draft = "\
60   INT. FIGHT VENUE - NIGHT

They walk in through the crowd and the noise takes the room away.
";
        let ask = |moves: &str| {
            format!(
                "takescript\tRevision\tDRAFTJP.pdf\t2026-08-22T11:56:00Z\t0\t\t0\tregular\t0\tnumber=0,rooms=0\t{moves}\n{draft}"
            )
        };

        // Weighed with nothing ticked: it is still a new scene, and 54 is
        // still standing. Found is all finding does.
        let weighed = dispatch(&mut h, &format!("takescript\tweigh\tDRAFTJP.pdf\t2026-08-22T11:56:00Z\t0\t\t0\tregular\t0\tnumber=0,rooms=0\t\n{draft}"));
        assert!(weighed.contains("1 new scene will be created."), "{weighed}");

        // Ticked, it carries across: same record, new number, shots intact.
        dispatch(&mut h, &ask("0"));
        assert_eq!(h.project.doc().scene_numbered("60"), Some(fifty_four));
        assert_eq!(h.project.doc().scene_numbered("54"), None);
        assert_eq!(
            h.project.doc().placements_in_scene(fifty_four).len(),
            shots,
            "the work came with it"
        );
    }

    /// Settling a disagreement the *other* way actually changes the value —
    /// Ref 231.
    #[test]
    fn taking_the_other_value_puts_it_on_screen_and_ends_the_question() {
        let dir = tmp("takeother");
        let mac = DeviceId(1);
        let phone = DeviceId(2);

        let mut first = shotlister_storage::create(&dir, "Daybreak", mac).unwrap();
        let scene = first.doc_mut().create_scene("33");
        let (_shot, placement) = first.doc_mut().add_shot_to_scene(scene);
        first.doc_mut().set(placement, "lens", "37mm");
        first.save().unwrap();

        let mut second = shotlister_storage::open(first.path(), phone).unwrap();
        first.doc_mut().set(placement, "lens", "27mm");
        second.doc_mut().set(placement, "lens", "85mm");
        first.save().unwrap();
        second.save().unwrap();
        second.pull().unwrap();

        let mut h = Handle {
            project: second,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };

        let standing = dispatch(&mut h, "clashes");
        assert!(standing.contains("\"count\":1"), "one to answer: {standing}");
        let held = h
            .project
            .doc()
            .get(placement)
            .and_then(|r| r.text("lens"))
            .unwrap_or_default()
            .to_string();

        dispatch(&mut h, &format!("takeother\t{}\tlens", placement.0));

        let now = h
            .project
            .doc()
            .get(placement)
            .and_then(|r| r.text("lens"))
            .unwrap_or_default()
            .to_string();
        assert_ne!(now, held, "the other value is now the one on screen");
        assert!(
            dispatch(&mut h, "clashes").contains("\"count\":0"),
            "and the question is answered, not merely hidden"
        );

        // Asking again is not an error — another window, or the other device,
        // may have decided first.
        assert!(!dispatch(&mut h, &format!("takeother\t{}\tlens", placement.0)).contains("error"));
    }

    /// Keeping what is on screen, one row at a time: settling one
    /// disagreement leaves the others standing.
    #[test]
    fn settle_can_answer_one_disagreement_alone() {
        let dir = tmp("settleone");
        let mut first = shotlister_storage::create(&dir, "Daybreak", DeviceId(1)).unwrap();
        let scene = first.doc_mut().create_scene("33");
        let (_shot, placement) = first.doc_mut().add_shot_to_scene(scene);
        first.doc_mut().set(placement, "lens", "37mm");
        first.save().unwrap();
        let mut second = shotlister_storage::open(first.path(), DeviceId(2)).unwrap();
        first.doc_mut().set(placement, "lens", "27mm");
        first.doc_mut().set(placement, "notes", "Static");
        second.doc_mut().set(placement, "lens", "85mm");
        second.doc_mut().set(placement, "notes", "Push in");
        first.save().unwrap();
        second.save().unwrap();
        second.pull().unwrap();
        let mut h = Handle {
            project: second,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };
        assert!(dispatch(&mut h, "clashes").contains("\"count\":2"));
        dispatch(&mut h, &format!("settle\t{}\tlens", placement.0));
        let left = dispatch(&mut h, "clashes");
        assert!(left.contains("\"count\":1"), "one answered, one left: {left}");
        assert!(left.contains("\"field\":\"notes\""), "the one left is notes: {left}");
        dispatch(&mut h, "settle");
        assert!(dispatch(&mut h, "clashes").contains("\"count\":0"));
    }

    /// A room inside a house, all the way out to the view — Ref 269.
    ///
    /// The thing this is really guarding is the pair of address keys: the
    /// record's own `address` stays empty on a room, and `effectiveAddress`
    /// carries the house's. Collapse those two into one and the Mac's editor
    /// would stamp a borrowed address onto every room the moment anybody
    /// clicked in the field.
    #[test]
    fn a_room_reaches_the_view_wearing_the_house_it_is_in() {
        let dir = tmp("areas");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "addlocation\tHillcrest House");
        let house = h.project.doc().locations_in_order()[0];
        dispatch(
            &mut h,
            &format!("setlocation\t{}\taddress\t2140 Hillcrest Rd", house.0),
        );
        dispatch(&mut h, &format!("addarea\t{}\tKitchen", house.0));

        let kitchen = h
            .project
            .doc()
            .areas_of(house)
            .first()
            .copied()
            .expect("the kitchen is inside the house");

        let scene = h.project.doc().scenes_in_order()[0];
        dispatch(&mut h, &format!("scenelocation\t{}\t{}", scene.0, kitchen.0));

        let seen = dispatch(&mut h, "view");
        assert!(seen.contains("\"fullName\":\"Hillcrest House — Kitchen\""));
        assert!(seen.contains("\"effectiveAddress\":\"2140 Hillcrest Rd\""));
        assert!(
            seen.contains(&format!("\"parent\":\"{}\"", house.0)),
            "the room says which house it is in"
        );

        // Refused, not obeyed: one level, always.
        let refused = dispatch(&mut h, &format!("movelocation\t{}\t{}", house.0, kitchen.0));
        assert!(refused.contains("error"), "a house cannot move into its own room");
        assert_eq!(h.project.doc().parent_of_location(house), None);

        // Letting the room out keeps everything of its own.
        dispatch(&mut h, &format!("movelocation\t{}\t", kitchen.0));
        assert_eq!(h.project.doc().parent_of_location(kitchen), None);
        assert_eq!(h.project.doc().scenes_at_location(kitchen), vec![scene]);
    }
}

#[cfg(test)]
mod media_tests {
    use super::*;

    /// The same, and the same reason — see the copy above (Ref 234).
    fn tmp(name: &str) -> PathBuf {
        let p = std::env::temp_dir()
            .join(format!("shotlister-ffi-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    fn open_demo(dir: &std::path::Path) -> Handle {
        let device = DeviceId(1);
        let mut project = shotlister_storage::create(dir, "Daybreak", device).unwrap();
        demo::seed(project.doc_mut());
        Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        }
    }

    fn first_shot(h: &Handle) -> String {
        view(h)
            .split("\"shot\":\"")
            .nth(1)
            .unwrap()
            .split('"')
            .next()
            .unwrap()
            .to_string()
    }

    #[test]
    fn a_pasted_frame_survives_the_round_trip() {
        let dir = tmp("paste");
        let mut h = open_demo(&dir);
        let shot = first_shot(&h);
        let bytes: Vec<u8> = (0..=255u8).collect();
        let encoded = b64::encode(&bytes);

        let after = dispatch(&mut h, &format!("paste\t{shot}\t1920\t800\tpng\t{encoded}"));
        assert!(after.contains("\"frame\":{"), "the row should now carry a frame");

        // and it comes back out byte for byte
        let hash = after.split("\"hash\":\"").nth(1).unwrap().split('"').next().unwrap();
        let got = dispatch(&mut h, &format!("media\t{hash}\tpng"));
        let data = got.split("\"data\":\"").nth(1).unwrap().split('"').next().unwrap();
        assert_eq!(b64::decode(data).unwrap(), bytes);
    }

    #[test]
    fn the_same_picture_twice_is_stored_once() {
        let dir = tmp("dedupe");
        let mut h = open_demo(&dir);
        let bytes = b"a frame".to_vec();
        let encoded = b64::encode(&bytes);
        let shots: Vec<String> = view(&h)
            .split("\"shot\":\"")
            .skip(1)
            .take(2)
            .map(|s| s.split('"').next().unwrap().to_string())
            .collect();
        for shot in &shots {
            dispatch(&mut h, &format!("paste\t{shot}\t10\t10\tpng\t{encoded}"));
        }
        let media_count = h.project.doc().store().count_of_kind(&Kind::Media);
        assert_eq!(media_count, 1, "content addressing should store it once");
    }

    #[test]
    fn a_field_hands_back_the_projects_own_list() {
        let dir = tmp("vocab");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "vocab\tlens");
        // this production's lenses, not a default set
        assert!(out.contains("37mm") && out.contains("20.7mm"));
        assert!(!out.contains("24mm"), "that is The Turning's set, not Daybreak's");
    }

    #[test]
    fn a_column_of_the_projects_own_reaches_the_view_with_its_kind() {
        let dir = tmp("addcolumn");
        let mut h = open_demo(&dir);

        let out = dispatch(&mut h, "addcolumn\tsingle\tSound");
        assert!(out.contains("\"label\":\"Sound\""), "the view names it");
        assert!(out.contains("\"kind\":\"single\""), "and says its shape");

        let field = h.project.doc().custom_columns()[0].field.clone();
        // typing into it goes through the same set path as everything else,
        // and a single-choice column teaches the project the way lens does
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        let out = dispatch(&mut h, &format!("set\t{}\t{}\tSync", shot.0, field));
        assert!(out.contains("\"custom\":{"), "rows carry their custom values");
        assert!(out.contains("[\"Sync\"]"));
        assert_eq!(h.project.doc().vocabulary(&field), vec!["Sync".to_string()]);

        // a kind nothing understands is refused, not stored
        let out = dispatch(&mut h, "addcolumn\thologram\tMystery");
        assert!(out.contains("error"));
    }

    #[test]
    fn a_multi_column_of_the_projects_own_holds_several() {
        let dir = tmp("addcolumn-multi");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "addcolumn\tmulti\tRigs");
        let field = h.project.doc().custom_columns()[0].field.clone();
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let out = dispatch(&mut h, &format!("set\t{}\t{}\tCrane, Remote Head", shot.0, field));
        assert!(out.contains("[\"Crane\",\"Remote Head\"]"));

        // and a check column reads as a flag: present when on, absent when off
        dispatch(&mut h, "addcolumn\tcheck\tApproved");
        let check = h
            .project
            .doc()
            .custom_columns()
            .into_iter()
            .find(|c| c.kind == "check")
            .unwrap()
            .field;
        let out = dispatch(&mut h, &format!("set\t{}\t{}\t1", shot.0, check));
        assert!(out.contains(&format!("\"{check}\":[\"1\"]")));
        let out = dispatch(&mut h, &format!("set\t{}\t{}\t0", shot.0, check));
        assert!(out.contains(&format!("\"{check}\":[]")));
    }

    #[test]
    fn renaming_a_column_keeps_what_was_typed_into_it() {
        let dir = tmp("renamecolumn");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "addcolumn\ttext\tSound");
        let field = h.project.doc().custom_columns()[0].field.clone();
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        dispatch(&mut h, &format!("set\t{}\t{}\tMOS", shot.0, field));

        let out = dispatch(&mut h, &format!("renamecolumn\t{}\tAudio", field));
        assert!(out.contains("\"label\":\"Audio\""));
        assert!(out.contains("[\"MOS\"]"), "the values stay where they are");
    }

    #[test]
    fn default_list_terms_rename_and_colour() {
        let dir = tmp("defaultterms");
        let mut h = open_demo(&dir);
        let lists = dispatch(&mut h, "lists");
        eprintln!("LISTS {}", &lists[..lists.len().min(900)]);
        let first = h.project.doc().vocabulary("size");
        eprintln!("SIZE {:?}", first);
        let term = first.first().cloned().unwrap_or("Wide".into());
        let out = dispatch(&mut h, &format!("list\trename\tsize\t{term}\tZZ Renamed"));
        eprintln!("RENAME {out}");
        eprintln!("AFTER {:?}", h.project.doc().vocabulary("size"));
        let out = dispatch(&mut h, "list\tcolour\tsize\tZZ Renamed\t2B6CB0");
        eprintln!("COLOUR {out} {}", dispatch(&mut h, "colours"));
    }

    #[test]
    fn colouring_a_tag_and_renaming_a_default_column_stick() {
        let dir = tmp("colourstick");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "list\tadd\ttags\tmoody");
        let out = dispatch(&mut h, "list\tcolour\ttags\tmoody\t2B6CB0");
        assert!(!out.contains("error"), "{out}");
        let colours = dispatch(&mut h, "colours");
        assert!(colours.contains("moody") && colours.contains("2B6CB0"), "{colours}");
        let out = dispatch(&mut h, "renamecolumn\tlens\tGlass");
        assert!(out.contains("Glass"), "{out}");
        dispatch(&mut h, "save");
        let again = shotlister_storage::open(&dir.join("Daybreak.shotlist"), DeviceId(2)).unwrap();
        assert_eq!(again.doc().term_colour("tags", "moody"), Some("2B6CB0".to_string()));
        assert_eq!(again.doc().column_label_override("lens"), Some("Glass".to_string()));
    }

    #[test]
    fn a_new_scene_arrives_holding_what_was_typed_about_it() {
        let dir = tmp("addscene");
        let mut h = open_demo(&dir);
        let before = h.project.doc().scenes_in_order().len();

        let out = dispatch(
            &mut h,
            "addscene\t207\tint_ext\tINT\tlocation\tCAB\ttime_of_day\tNIGHT\tdescription\tShe drives.",
        );
        assert!(out.contains("\"number\":\"207\""));
        assert_eq!(h.project.doc().scenes_in_order().len(), before + 1);

        let scene = *h
            .project
            .doc()
            .scenes_in_order()
            .iter()
            .find(|s| h.project.doc().get(**s).unwrap().text(f::NUMBER) == Some("207"))
            .unwrap();
        let record = h.project.doc().get(scene).unwrap().clone();
        assert_eq!(record.text(f::INT_EXT), Some("INT"));
        assert_eq!(record.text(f::LOCATION), Some("CAB"));
        assert_eq!(record.text(f::TIME_OF_DAY), Some("NIGHT"));
        assert_eq!(record.text(f::DESCRIPTION), Some("She drives."));
    }

    #[test]
    fn a_room_written_beside_a_place_is_registered_named_and_taken_off_by_its_use() {
        let dir = tmp("registerscans");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "addlocation\tThe Bedroom");
        let place = *h
            .project
            .doc()
            .store()
            .of_kind(&Kind::Location)
            .iter()
            .map(|r| &r.id)
            .last()
            .unwrap();
        // The phone's layout: a place with no folder files under its own id.
        let scans = h.project.path().join("locations").join(place.0.to_string()).join("scans");
        std::fs::create_dir_all(&scans).unwrap();
        std::fs::write(scans.join("RoomScan_2026-09-10T120000.usdz"), b"not really a usdz").unwrap();
        std::fs::write(scans.join("RoomScan_2026-09-10T120000.json"), b"{\"walls\":[]}").unwrap();

        let out = dispatch(&mut h, "registerscans");
        // Named for where it was taken (2026-10-17), its files' own name and
        // the day kept beside it.
        assert!(out.contains("\"name\":\"The Bedroom · Scan 1\""), "{out}");
        assert!(out.contains("\"file\":\"RoomScan_2026-09-10T120000\""), "{out}");
        assert!(out.contains("\"taken\":\"Sep 10, 2026 at 12:00 PM\""), "{out}");
        assert!(out.contains("\"shape\":{\"ref\":\""), "each half says which use it is: {out}");
        assert_eq!(h.project.doc().scans_of(place).len(), 1);
        // Asking twice adds nothing.
        dispatch(&mut h, "registerscans");
        assert_eq!(h.project.doc().scans_of(place).len(), 1);

        // Renaming the room renames both uses and keeps each file's own extension.
        let refs: Vec<Id> = h.project.doc().media_refs(place);
        assert_eq!(refs.len(), 2);
        for r in &refs {
            dispatch(&mut h, &format!("renameuse\t{}\tBedroom 2.0", r.0));
        }
        let rooms = h.project.doc().scans_of(place);
        assert_eq!(rooms.len(), 1, "one room, not two halves: {rooms:?}");
        assert_eq!(rooms[0].name, "Bedroom 2.0");
        assert!(rooms[0].shape.is_some() && rooms[0].plan.is_some());

        // Taking it off is `detach`, the way a photograph comes off.
        for r in &refs {
            dispatch(&mut h, &format!("detach\t{}", r.0));
        }
        assert!(h.project.doc().scans_of(place).is_empty());
        // A file still on disk is registered again — the folder is the phone's
        // record of what was scanned, so deleting a room means the files go
        // too, and then it stays gone.
        dispatch(&mut h, "registerscans");
        assert_eq!(h.project.doc().scans_of(place).len(), 1, "the files are still there");
        for r in h.project.doc().media_refs(place) {
            dispatch(&mut h, &format!("detach\t{}", r.0));
        }
        std::fs::remove_dir_all(&scans).unwrap();
        dispatch(&mut h, "registerscans");
        assert!(h.project.doc().scans_of(place).is_empty(), "a deleted room stays deleted");
    }

    #[test]
    fn a_new_scene_can_be_given_a_priority_and_pointed_at_a_place() {
        let dir = tmp("addscene-place");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "addlocation\tThe Drive-In");
        let place = *h
            .project
            .doc()
            .store()
            .of_kind(&Kind::Location)
            .iter()
            .map(|r| &r.id)
            .last()
            .unwrap();

        dispatch(
            &mut h,
            &format!(
                "addscene\t207\tlocation\tCAB\tpriority\tHigh\tplace\t{}",
                place.0
            ),
        );

        let scene = *h
            .project
            .doc()
            .scenes_in_order()
            .iter()
            .find(|s| h.project.doc().get(**s).unwrap().text(f::NUMBER) == Some("207"))
            .unwrap();
        assert_eq!(h.project.doc().get(scene).unwrap().text(f::PRIORITY), Some("High"));
        assert!(
            h.project.doc().scene_locations(scene).contains(&place),
            "the scene should point at the place the box picked"
        );
    }

    #[test]
    fn filling_the_new_scene_box_in_is_one_thing_to_take_back() {
        let dir = tmp("addscene-undo");
        let mut h = open_demo(&dir);
        let before = h.project.doc().scenes_in_order().len();

        dispatch(
            &mut h,
            "addscene\t207\tint_ext\tINT\tlocation\tCAB\ttime_of_day\tNIGHT\tdescription\tShe drives.",
        );
        assert_eq!(h.project.doc().scenes_in_order().len(), before + 1);

        // One ⌘Z, not five. Pressing Add is one gesture.
        dispatch(&mut h, "undo");
        assert_eq!(
            h.project.doc().scenes_in_order().len(),
            before,
            "one undo should take the whole scene back"
        );
    }

    #[test]
    fn a_typed_heading_is_read_by_the_engine_rather_than_by_the_app() {
        let dir = tmp("readheading");
        let mut h = open_demo(&dir);
        let out = dispatch(&mut h, "readheading\t34 int. car - dawn");
        assert!(out.contains("\"number\":\"34\""), "{out}");
        assert!(out.contains("\"intExt\":\"INT\""), "{out}");
        assert!(out.contains("\"location\":\"CAR\""), "{out}");
        assert!(out.contains("\"timeOfDay\":\"SUNRISE\""), "{out}");
    }

    /// A section's script set as text, a shot quoting a stretch of it, an
    /// edit that keeps the tie, and one undo taking the lot back.
    #[test]
    fn a_script_is_text_and_a_shot_quotes_a_stretch_of_it() {
        let dir = tmp("quoting");
        let mut h = open_demo(&dir);
        dispatch(&mut h, "kind\tcommercial");
        let out = dispatch(&mut h, "setscript\t\tThank you Denis.\n\nWhat you are about to see.\tnewsection=HLA");
        assert!(out.contains("\"kept\":0"), "{out}");
        let t = h.project.doc().sequences_in_order().into_iter()
            .find(|s| h.project.doc().get(*s).unwrap().text(f::TITLE) == Some("HLA")).unwrap();
        assert_eq!(h.project.doc().av_script(Some(t)), "Thank you Denis.\n\nWhat you are about to see.");

        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        let view = dispatch(&mut h, &format!("tieshot\t{}\t{}\t0\t16", shot.0, t.0));
        assert!(view.contains("\"script\":\"Thank you Denis.\""), "{}", &view[..300]);
        assert!(view.contains("\"scripts\":[{"), "the view carries the scripts");

        let out = dispatch(&mut h, &format!("setscript\t{}\tINTRO\n\nThank you Denis.\n\nWhat you are about to see.", t.0));
        assert!(out.contains("\"kept\":1"), "{out}");
        assert_eq!(h.project.doc().quote_of(shot).unwrap().from, 7);

        let out = dispatch(&mut h, &format!("setscript\t{}\tGone.", t.0));
        assert!(out.contains("\"lost\":1"), "{out}");
        dispatch(&mut h, "undo");
        assert_eq!(h.project.doc().shot_excerpt(shot), "Thank you Denis.");

        // Untie by an empty range.
        let view = dispatch(&mut h, &format!("tieshot\t{}\t{}\t3\t3", shot.0, t.0));
        assert!(view.contains("\"scriptFrom\":null"), "{}", &view[..300]);
    }

    #[test]
    fn a_paste_onto_many_rows_is_one_thing_to_take_back() {
        let dir = tmp("setmany");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placements = h.project.doc().placements_in_scene(scene);
        let shots: Vec<_> = placements
            .iter()
            .take(3)
            .map(|p| h.project.doc().get(*p).unwrap().ref_id(f::SHOT).unwrap())
            .collect();
        let before: Vec<String> = shots
            .iter()
            .map(|s| {
                h.project
                    .doc()
                    .get(*s)
                    .and_then(|r| r.get(f::TAGS).cloned())
                    // Undo restores a never-set field as Null rather than
                    // absent — field-level undo's husk shape. Both read as
                    // empty everywhere a value is shown, so both are "".
                    .filter(|v| !matches!(v, Value::Null))
                    .map(|v| format!("{v:?}"))
                    .unwrap_or_default()
            })
            .collect();

        let ids = shots.iter().map(|s| s.0.to_string()).collect::<Vec<_>>().join(",");
        let out = dispatch(&mut h, &format!("setmany\t{ids}\ttags\tVFX, Drone"));
        // every row now holds the pasted value — replaced, not toggled
        let hits = out.matches("[\"VFX\",\"Drone\"]").count();
        assert!(
            hits >= shots.len(),
            "wanted {} rows holding the paste, saw {} — reply head: {}",
            shots.len(),
            hits,
            &out[..out.len().min(300)]
        );

        // and one undo puts all three back the way they were
        h.project.doc_mut().undo();
        let after: Vec<String> = shots
            .iter()
            .map(|s| {
                h.project
                    .doc()
                    .get(*s)
                    .and_then(|r| r.get(f::TAGS).cloned())
                    // Undo restores a never-set field as Null rather than
                    // absent — field-level undo's husk shape. Both read as
                    // empty everywhere a value is shown, so both are "".
                    .filter(|v| !matches!(v, Value::Null))
                    .map(|v| format!("{v:?}"))
                    .unwrap_or_default()
            })
            .collect();
        assert_eq!(before, after, "one ⌘Z takes the whole paste back");
    }

    #[test]
    fn a_block_of_different_values_pasted_is_one_thing_to_take_back() {
        let dir = tmp("undogroup");
        let mut h = open_demo(&dir);
        let placements: Vec<_> = h
            .project
            .doc()
            .scenes_in_order()
            .into_iter()
            .flat_map(|s| h.project.doc().placements_in_scene(s))
            .collect();
        let shot = |i: usize| h.project.doc().get(placements[i]).unwrap().ref_id(f::SHOT).unwrap();
        let (a, b) = (shot(0).0.to_string(), shot(1).0.to_string());
        let depth = |h: &Handle| h.project.doc().undo_depth();
        let start = depth(&h);

        // Two different values, two `setmany` calls, one group.
        dispatch(&mut h, "undoopen\tPaste");
        dispatch(&mut h, &format!("setmany\t{a}\tnotes\tfirst"));
        dispatch(&mut h, &format!("setmany\t{b}\tnotes\tsecond"));
        dispatch(&mut h, "undoclose");
        assert_eq!(depth(&h), start + 1, "the group is one step of history");

        // Without the group they are two.
        dispatch(&mut h, &format!("setmany\t{a}\tnotes\tthird"));
        dispatch(&mut h, &format!("setmany\t{b}\tnotes\tfourth"));
        assert_eq!(depth(&h), start + 3);

        // A close with nothing open changes nothing.
        dispatch(&mut h, "undoclose");
        assert_eq!(depth(&h), start + 3);

        // And undoing the group takes both values back.
        h.project.doc_mut().undo();
        h.project.doc_mut().undo();
        h.project.doc_mut().undo();
        let notes = |h: &Handle, id: &str| {
            let id = shotlister_engine::Id(id.parse().unwrap());
            h.project.doc().get(id).and_then(|r| r.get(f::NOTES).cloned())
                .filter(|v| !matches!(v, Value::Null))
                .map(|v| format!("{v:?}")).unwrap_or_default()
        };
        assert!(!notes(&h, &a).contains("first"), "first is gone");
        assert!(!notes(&h, &b).contains("second"), "second is gone");
    }

    #[test]
    fn clearing_a_rectangle_of_cells_is_one_thing_to_take_back() {
        let dir = tmp("clearcells");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        dispatch(&mut h, &format!("set\t{}\tsize\tW", shot.0));
        dispatch(&mut h, &format!("set\t{}\tlens\t37mm", shot.0));

        let out = dispatch(
            &mut h,
            &format!("clearcells\tsize={id}|lens={id}", id = shot.0),
        );
        assert!(out.contains("\"size\":\"\""), "size emptied");
        assert!(out.contains("\"lens\":\"\""), "lens emptied");

        // both columns come back on ONE undo — the whole point of the command
        h.project.doc_mut().undo();
        let d = h.project.doc();
        assert_eq!(d.get(shot).and_then(|r| r.get("size")).and_then(|v| v.as_text()), Some("W"));
        assert_eq!(d.get(shot).and_then(|r| r.get("lens")).and_then(|v| v.as_text()), Some("37mm"));
    }

    #[test]
    fn a_movie_lands_with_its_kind_and_its_poster_stands_for_it() {
        let dir = tmp("video");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let movie = b64::encode(b"not really a movie but bytes all the same");
        let out = dispatch(
            &mut h,
            &format!("paste\t{}\t1920\t1080\tmov\t{}\tvideo\t12.5", shot.0, movie),
        );
        assert!(out.contains("pasted.mov"), "the movie is the medium stored");

        let media = h.project.doc_mut().media_of(shot)[0];
        assert_eq!(h.project.doc().media_kind(media), Some(MediaKind::Video));

        // the poster stands beside it under the same hash — as a JPEG, and a
        // PNG one already there under that name is retired by it
        let hash = sha256(b"not really a movie but bytes all the same").to_hex();
        h.project.write_proxy(&hash, "png", b"the old png poster").unwrap();
        let poster = b64::encode(b"jpeg bytes");
        dispatch(&mut h, &format!("poster\t{}\t{}", hash, poster));
        assert_eq!(
            h.project.read_proxy(&hash, "jpg").unwrap().as_deref(),
            Some(b"jpeg bytes".as_slice())
        );
        assert!(h.project.read_proxy(&hash, "png").unwrap().is_none(), "one still per clip");
        // and the movie itself is still readable under its own extension
        assert!(h.project.read_proxy(&hash, "mov").unwrap().is_some());
        // a reader that still asks for the poster the old way gets the poster
        let asked = dispatch(&mut h, &format!("media\t{}\tpng", hash));
        assert!(asked.contains("\"ext\":\"jpg\""), "the still, not the movie: {asked}");

        // **The shot's frames say what kind of thing they are.** They used to
        // carry only a name, so the phone guessed from the filename and drew a
        // clip named oddly as a photograph.
        let drawn = view(&h);
        let still = drawn
            .split("\"stills\":[")
            .nth(1)
            .expect("the shot draws its frames")
            .split(']')
            .next()
            .unwrap();
        assert!(
            still.contains("\"kind\":\"video\""),
            "a frame must say it is a clip: {still}"
        );

        // **And asking for the clip hands back the clip, not its poster.**
        // Both live under one name; the folder decides nothing.
        let asked = dispatch(&mut h, &format!("media\t{hash}"));
        assert!(
            asked.contains("\"ext\":\"mov\""),
            "a player asking for a clip must not be given the still: {asked}"
        );
        // Somebody who wants the poster can still say so — and gets the
        // JPEG whichever still name they asked by.
        let wanted = dispatch(&mut h, &format!("media\t{hash}\tpng"));
        assert!(wanted.contains("\"ext\":\"jpg\""), "{wanted}");

        // **The same clip, made smaller after the fact.** Its record, its
        // place on the shot and its poster survive; its old files do not.
        let smaller = b64::encode(b"the same clip, quieter");
        let out = dispatch(
            &mut h,
            &format!("reclip\t{}\t1280\t720\tmp4\t{}", media.0, smaller),
        );
        let new_hash = sha256(b"the same clip, quieter").to_hex();
        assert!(out.contains(&format!("\"hash\":\"{new_hash}\"")), "{out}");
        assert!(out.contains(&format!("\"before\":\"{hash}\"")), "{out}");
        assert!(out.contains(&format!("{}.mov", &hash[..32])), "the old movie is named as gone: {out}");
        assert!(out.contains(&format!("{}.jpg", &hash[..32])), "and its poster: {out}");
        assert!(h.project.read_proxy(&hash, "mov").unwrap().is_none());
        assert!(h.project.read_proxy(&new_hash, "mp4").unwrap().is_some());
        assert_eq!(h.project.doc().media_of(shot), vec![media], "the shot still holds the same record");
        assert_eq!(
            h.project.doc().get(media).unwrap().text(f::HASH),
            Some(new_hash.as_str())
        );
        // A photograph may not be re-encoded this way.
        let photo = b64::encode(b"a still");
        dispatch(&mut h, &format!("paste\t{}\t1600\t900\tjpg\t{}\timage\t0\twall.jpg", shot.0, photo));
        let still_id = h.project.doc().media_of(shot)[1];
        let refused = dispatch(&mut h, &format!("reclip\t{}\t1\t1\tjpg\t{}", still_id.0, photo));
        assert!(refused.contains("only a clip"), "{refused}");

        // And the relay's listing, judged: the old names are strays, the new
        // and the photograph's are not, and a name not shaped like a stored
        // file is nobody's to judge.
        let listing = format!(
            "{{\"media\":[{{\"name\":\"{}.mov\",\"size\":1}},{{\"name\":\"{}.png\",\"size\":1}},{{\"name\":\"{}.mp4\",\"size\":1}},{{\"name\":\"{}.jpg\",\"size\":1}},{{\"name\":\"cover.png\",\"size\":1}}]}}",
            &hash[..32], &hash[..32], &new_hash[..32], &sha256(b"a still").to_hex()[..32]
        );
        let strays = dispatch(&mut h, &format!("strays\t{listing}"));
        assert!(strays.contains(&format!("{}.mov", &hash[..32])), "{strays}");
        assert!(strays.contains(&format!("{}.png", &hash[..32])), "{strays}");
        assert!(!strays.contains(&format!("{}.mp4", &new_hash[..32])), "{strays}");
        assert!(!strays.contains("cover.png"), "{strays}");
        assert!(!strays.contains(&sha256(b"a still").to_hex()[..32]), "{strays}");

        // **And a sync never sends a stray.** Put the retired clip back on
        // disk, as a device that has not swept yet would have it; the plan
        // against an empty relay offers the new clip and not the old one.
        h.project.write_proxy(&hash, "mov", b"not really a movie but bytes all the same").unwrap();
        let plan = dispatch(&mut h, "syncplan\t{\"logs\":[]}\t{\"media\":[]}");
        assert!(plan.contains(&format!("{}.mp4", &new_hash[..32])), "the new clip goes up: {plan}");
        assert!(!plan.contains(&format!("{}.mov", &hash[..32])), "the retired one does not: {plan}");

    }

    /// His ask, 2026-08-28: a video or GIF in a static export (PDF, Excel)
    /// needs a real still standing in for it, not a blank cell or an
    /// attempt to embed the clip's own bytes as a picture. The mechanism was
    /// already there for the auto-generated case (`poster`, above); this is
    /// the same fix `Table.swift`'s `image(_:from:)` got on 2026-08-22,
    /// ported to every export that draws a frame.
    #[test]
    fn xlsx_export_draws_a_movies_poster_not_its_own_bytes() {
        let dir = tmp("video-export");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let movie = b64::encode(b"not really a movie but bytes all the same");
        dispatch(&mut h, &format!("paste\t{}\t1920\t1080\tmov\t{}\tvideo\t12.5", shot.0, movie));
        let hash = sha256(b"not really a movie but bytes all the same").to_hex();
        dispatch(&mut h, &format!("poster\t{}\t{}", hash, b64::encode(b"POSTERBYTES")));

        let path = dir.join("with-poster.xlsx");
        let out = dispatch(&mut h, &format!("xlsx\t{}", path.display()));
        assert!(out.contains("\"path\""), "got: {out}");
        let bytes = std::fs::read(&path).unwrap();
        let contains = |needle: &[u8]| bytes.windows(needle.len()).any(|w| w == needle);
        assert!(contains(b"POSTERBYTES"), "the poster's bytes should be embedded");
        assert!(
            !contains(b"not really a movie"),
            "the raw movie bytes must never be embedded as a picture"
        );
    }

    #[test]
    fn a_shot_can_be_told_which_of_its_frames_stands_for_it() {
        let dir = tmp("keyframe");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let paste = |h: &mut Handle, word: &str| {
            let bytes = b64::encode(word.as_bytes());
            dispatch(
                h,
                &format!("paste\t{}\t1600\t900\tpng\t{}\timage", shot.0, bytes),
            );
        };
        paste(&mut h, "first");
        paste(&mut h, "second");
        let refs = h.project.doc().media_refs(shot);
        assert_eq!(refs.len(), 2, "two frames on the shot");

        let media_of = |h: &Handle, mref: Id| -> Option<Id> {
            h.project.doc().get(mref).and_then(|r| r.ref_id(f::MEDIA))
        };
        // Which frame the shot draws, read off the view the way a shell does.
        let marked = |h: &Handle| -> String {
            view(h)
                .split("\"stills\":[")
                .nth(1)
                .unwrap()
                .split(']')
                .next()
                .unwrap()
                .split("},{")
                .find(|part| part.contains("\"key\":true"))
                .unwrap_or("none")
                .split("\"ref\":\"")
                .nth(1)
                .unwrap_or("none")
                .split('"')
                .next()
                .unwrap()
                .to_string()
        };

        // **Until somebody chooses, the newest picture leads.** Dropping a
        // clip on a shot that already has a storyboard frame should show the
        // clip — that is what a person means by adding it.
        assert_eq!(
            h.project.doc().key_frame(shot),
            media_of(&h, refs[1]),
            "with nothing chosen, the picture just added is the one shown"
        );
        assert!(!h.project.doc().key_frame_was_chosen(shot));

        // Choose the first one, and the shot draws that instead.
        dispatch(&mut h, &format!("keyframe\t{}\t{}", shot.0, refs[0].0));
        assert!(h.project.doc().key_frame_was_chosen(shot), "that was a decision");
        assert_eq!(h.project.doc().key_frame(shot), media_of(&h, refs[0]));
        assert_eq!(marked(&h), refs[0].0.to_string(), "the chosen frame is marked");

        // **A third picture must not throw the choice away.** Attaching one
        // used to stamp it as the shot's frame every time, so dropping a
        // reference on a shot silently undid a decision somebody had made.
        paste(&mut h, "third");
        assert_eq!(
            h.project.doc().key_frame(shot),
            media_of(&h, refs[0]),
            "a new frame must not take over from the one that was chosen"
        );

        // The choice is a change like any other, so undo takes it back.
        dispatch(&mut h, &format!("keyframe\t{}\t{}", shot.0, refs[1].0));
        assert_eq!(h.project.doc().key_frame(shot), media_of(&h, refs[1]));
        dispatch(&mut h, "undo");
        assert_eq!(h.project.doc().key_frame(shot), media_of(&h, refs[0]));

        // And taking the chosen frame off the shot makes it a fallback again,
        // so the next picture added is free to lead.
        let chosen_ref = h.project.doc().media_refs(shot)[0];
        dispatch(&mut h, &format!("detach\t{}", chosen_ref.0));
        assert!(
            !h.project.doc().key_frame_was_chosen(shot),
            "the decision went with the frame it was about"
        );
    }

    #[test]
    fn a_frame_whose_picture_never_arrived_can_be_named() {
        let dir = tmp("missing");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let bytes = b"a real picture";
        dispatch(
            &mut h,
            &format!(
                "paste\t{}\t1600\t900\tpng\t{}\timage\t0\there.png",
                shot.0,
                b64::encode(bytes)
            ),
        );
        assert!(
            dispatch(&mut h, "missing").contains("\"missing\":[]"),
            "a picture that is here is not missing"
        );

        // Now the case this exists for: the record arrives and the picture
        // does not. Between two devices that is an ordinary few seconds; it
        // becomes permanent when a folder is copied without its media.
        let hash = sha256(b"a picture that never came").to_hex();
        let media = h.project.doc_mut().add_media(
            sha256(b"a picture that never came"),
            MediaKind::Image,
            1280,
            535,
            5885,
            "gone.png",
        );
        h.project.doc_mut().attach_media(shot, media, "");

        let said = dispatch(&mut h, "missing");
        assert!(said.contains(&hash), "the hollow frame is named: {said}");
        assert!(said.contains("gone.png"), "and so is what it was called");
        assert!(
            !said.contains("here.png"),
            "the frame that is here is left out: {said}"
        );
    }

    #[test]
    fn the_project_can_list_what_pictures_it_already_holds() {
        let dir = tmp("gallery");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        // Nothing yet — an empty project offers an empty picker, not a lie.
        assert!(dispatch(&mut h, "gallery").contains("\"pictures\":0"));

        // One picture on a shot, one on the scene, and the *same* picture used
        // a second time — which is the case the whole feature exists for.
        let stair = b64::encode(b"a staircase");
        dispatch(
            &mut h,
            &format!("paste\t{}\t1600\t900\tpng\t{stair}\timage\t0\tstaircase.png", shot.0),
        );
        dispatch(
            &mut h,
            &format!(
                "paste\t{}\t1600\t900\tpng\t{}\timage\t0\tpermit.pdf",
                scene.0,
                b64::encode(b"a permit")
            ),
        );
        dispatch(
            &mut h,
            &format!("paste\t{}\t1600\t900\tpng\t{stair}\timage\t0\tstaircase.png", scene.0),
        );

        let out = dispatch(&mut h, "gallery");
        assert!(out.contains("\"pictures\":3"), "three uses listed: {out}");
        assert!(out.contains("staircase.png"));
        assert!(out.contains("permit.pdf"));
        // Grouped by where each one is used, never one undifferentiated wall.
        assert!(out.contains("\"kind\":\"shot\""), "a section for the shot");
        assert!(out.contains("\"kind\":\"scene\""), "a section for the scene");
        // And it says a picture is in more than one place, which is what lets
        // the app warn before somebody removes it from one of them.
        assert!(out.contains("\"uses\":2"), "the staircase is used twice: {out}");
        assert!(out.contains("\"uses\":1"), "the permit is used once");

        // One file on disk, not two — the same contents filed under one name.
        let hash = sha256(b"a staircase").to_hex();
        assert!(h.project.read_proxy(&hash, "png").unwrap().is_some());

        // A word narrows it by filename, and empty sections drop out.
        let narrowed = dispatch(&mut h, "gallery\tperm");
        assert!(narrowed.contains("permit.pdf"));
        assert!(
            !narrowed.contains("staircase.png"),
            "the word narrowed it: {narrowed}"
        );
        assert!(narrowed.contains("\"pictures\":1"));

        // A word nothing matches is an honest nothing.
        assert!(dispatch(&mut h, "gallery\tzzz").contains("\"pictures\":0"));
    }

    /// Ref 211. The same clip added twice must not be stored twice, even
    /// though the small copy the app files is not the file that arrived.
    #[test]
    fn a_clip_already_here_is_recognised_before_it_is_encoded_again() {
        let dir = tmp("have");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        let clip = sha256(b"four seconds of a car, as it came off the phone").to_hex();
        assert!(
            dispatch(&mut h, &format!("have\t{clip}")).contains("\"here\":false"),
            "nothing here yet"
        );

        // The shell shrinks it and stores the small copy, saying what it was
        // made from.
        let small = b64::encode(b"the same four seconds, at 720p");
        dispatch(
            &mut h,
            &format!("paste\t{}\t1280\t720\tmp4\t{small}\tvideo\t4\tcar.mov\t{clip}", shot.0),
        );

        // Now the *clip's* hash finds it, which is the whole point: the file
        // on disk is filed under the small copy's hash and would never have
        // been found by asking for the clip.
        let answer = dispatch(&mut h, &format!("have\t{clip}"));
        assert!(answer.contains("\"here\":true"), "the clip is recognised: {answer}");
        // **`car.mp4`, not `car.mov`** — Ref 193. The shell re-encoded a
        // QuickTime clip to MP4 on the way in, so the file this project holds
        // is an MP4 and its name now says so. The stem is what his rule is
        // about and it is untouched; only the promise the extension makes has
        // been brought back into line with the bytes.
        assert!(answer.contains("car.mp4"), "and says what it is: {answer}");
        assert!(
            !answer.contains(&format!("\"hash\":\"{clip}\"")),
            "filed under the small copy's name, not the clip's — that is what \
             lets a stored file check itself: {answer}"
        );

        // A file kept exactly as it arrived is found by the same question,
        // through the other door.
        let whole = b64::encode(b"a small photograph, kept whole");
        dispatch(
            &mut h,
            &format!(
                "paste\t{}\t1600\t900\tpng\t{whole}\timage\t0\tgate.png",
                scene.0
            ),
        );
        let gate = sha256(b"a small photograph, kept whole").to_hex();
        assert!(dispatch(&mut h, &format!("have\t{gate}")).contains("\"here\":true"));

        // And something nobody has added is still an honest no.
        let never = sha256(b"never added").to_hex();
        assert!(dispatch(&mut h, &format!("have\t{never}")).contains("\"here\":false"));

        // **And the second use moves no bytes.** `have` says which record it
        // is; `use` puts that record on another shot. Nothing is stored twice
        // and nothing goes back through the door it came in.
        let media = {
            let answer = dispatch(&mut h, &format!("have\t{clip}"));
            let at = answer.find("\"media\":\"").expect("a media id") + 9;
            let rest = &answer[at..];
            rest[..rest.find('"').expect("closing quote")].to_string()
        };
        let before = h.project.doc().store().of_kind(&Kind::Media).len();
        let (other_shot, _) = h.project.doc_mut().add_shot_to_scene(scene);
        dispatch(&mut h, &format!("use\t{}\t{media}", other_shot.0));
        assert_eq!(
            h.project.doc().store().of_kind(&Kind::Media).len(),
            before,
            "no second file"
        );
        assert_eq!(
            h.project.doc().media_of(other_shot).len(),
            1,
            "and the other shot has it"
        );

        // A record that is not a stored file is refused rather than attached.
        assert!(dispatch(&mut h, &format!("use\t{}\t{}", other_shot.0, scene.0))
            .contains("error"));
    }

    #[test]
    fn the_full_size_original_can_be_kept_and_asked_for_again() {
        let dir = tmp("original");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();

        // The small copy the app draws is what a project files a clip under,
        // and the real file is kept beside it under that same name.
        let full = b"pretend this is four hundred megabytes of clip";
        let small = b"the small copy";
        let hash = sha256(small).to_hex();
        dispatch(
            &mut h,
            &format!(
                "paste\t{}\t1920\t1080\tmov\t{}\tvideo\t12.5",
                shot.0,
                b64::encode(small)
            ),
        );
        assert!(
            dispatch(&mut h, &format!("keep\t{hash}\tmov\t{}", b64::encode(full)))
                .contains("\"ok\""),
            "the real one is kept"
        );

        let back = dispatch(&mut h, &format!("original\t{hash}\tmov"));
        assert!(back.contains("\"here\":true"), "and can be asked for: {back}");
        assert!(back.contains(&b64::encode(full)), "byte for byte");

        // Not having it is an ordinary answer, not an error — it may have been
        // pruned here, or never have reached this device at all.
        let absent = dispatch(&mut h, "original\t0123456789abcdef\tmov");
        assert!(absent.contains("\"here\":false"), "{absent}");
        assert!(!absent.contains("error"), "absence is not a fault: {absent}");

        // Pruning drops the real one and never the small copy, so the shot
        // still draws something.
        let freed = dispatch(&mut h, "prune\t0");
        assert!(freed.contains("freedBytes"), "{freed}");
        assert!(
            dispatch(&mut h, &format!("original\t{hash}\tmov")).contains("\"here\":false"),
            "the real one went"
        );
        let drawn = dispatch(&mut h, &format!("media\t{hash}"));
        assert!(
            drawn.contains(&b64::encode(small)),
            "the small copy the app draws survived the prune: {drawn}"
        );
    }

    #[test]
    fn a_locked_list_stops_learning_and_says_so() {
        let dir = tmp("locklist");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        dispatch(&mut h, &format!("set\t{}\tlens\t37mm", shot.0));

        // The lists report whether each one is closed.
        assert!(dispatch(&mut h, "lists").contains("\"locked\":false"));

        dispatch(&mut h, "list\tlock\tlens\t1");
        assert!(dispatch(&mut h, "lists").contains("\"locked\":true"));

        // Typing a term the list has never seen no longer teaches it, and no
        // longer lands on the shot either.
        dispatch(&mut h, &format!("set\t{}\tlens\t50mm", shot.0));
        let d = h.project.doc();
        assert!(
            !d.vocabulary("lens").contains(&"50mm".to_string()),
            "the list did not grow: {:?}",
            d.vocabulary("lens")
        );
        assert_eq!(
            d.get(shot).and_then(|r| r.get("lens")).and_then(|v| v.as_text()),
            Some("37mm"),
            "and the unknown term did not land on the shot"
        );

        // Adding to it deliberately is refused in words, not ignored.
        let refused = dispatch(&mut h, "list\tadd\tlens\t85mm");
        assert!(refused.contains("locked"), "it says why: {refused}");

        // And unlocking puts it back the way it was.
        dispatch(&mut h, "list\tlock\tlens\t0");
        dispatch(&mut h, "list\tadd\tlens\t85mm");
        assert!(h.project.doc().vocabulary("lens").contains(&"85mm".to_string()));
    }

    #[test]
    fn a_scene_keeps_its_notes_and_what_is_pinned_to_them() {
        let dir = tmp("scenenotes");
        let mut h = open_demo(&dir);
        let scene = h.project.doc().scenes_in_order()[0];

        // Notes are written through the same generic `set` every field uses —
        // the record is a scene rather than a shot, and nothing else changes.
        let out = dispatch(&mut h, &format!("set\t{}\tnotes\tWatch the 4pm sun", scene.0));
        assert!(out.contains("Watch the 4pm sun"));
        let out = dispatch(&mut h, &format!("set\t{}\tnotes_rich\tUlJURg==", scene.0));
        assert!(out.contains("\"notesRich\":\"UlJURg==\""), "emphasis rides beside the words");

        // A file pinned to a scene is the same machinery as a shot's frame,
        // and the view lists it under the scene.
        let bytes = b64::encode(b"a location plan");
        let out = dispatch(
            &mut h,
            &format!("paste\t{}\t900\t600\tpng\t{}\timage\t0\tsite-plan.png", scene.0, bytes),
        );
        assert!(out.contains("\"attachments\":["), "the scene lists what it carries");
        assert!(out.contains("site-plan.png"), "a pinned file keeps its own name");

        // A PDF is not a picture. The kind travels either by being said or by
        // the file's own name — never coerced to "image", which would tell
        // every reader to draw a call sheet as a thumbnail and stop there.
        let paper = b64::encode(b"%PDF-1.4 pretend");
        let out = dispatch(
            &mut h,
            &format!("paste\t{}\t0\t0\tpdf\t{}\t\t0\tcall-sheet.pdf", scene.0, paper),
        );
        assert!(out.contains("call-sheet.pdf"), "the paper is pinned");
        assert!(out.contains("\"kind\":\"other\""), "and it is not called a picture");
        let hash = sha256(b"a location plan").to_hex();
        assert!(out.contains(&hash));

        // …but a scene has no lead frame, and must not have been given one.
        let stamped = h.project.doc().get(scene).and_then(|r| r.get(f::KEY_MEDIA)).cloned();
        let kind = h.project.doc().get(scene).map(|r| r.kind.clone());
        assert!(
            stamped.is_none(),
            "a scene is not a shot and cannot wear a key frame — kind {kind:?}, held {stamped:?}"
        );

        // A shot pasted the same way still does get its lead frame.
        let placement = h.project.doc().placements_in_scene(scene)[0];
        let shot = h.project.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap();
        let more = b64::encode(b"a frame for the shot");
        dispatch(&mut h, &format!("paste\t{}\t100\t42\tpng\t{}", shot.0, more));
        assert!(h.project.doc().get(shot).and_then(|r| r.get(f::KEY_MEDIA)).is_some());
    }
}


#[cfg(test)]
mod print_frame_tests {
    use super::*;

    fn open(name: &str) -> (PathBuf, Handle) {
        let dir = std::env::temp_dir().join(format!("shotlister-ffi-printframe-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let project = shotlister_storage::create(&dir, "Daybreak", DeviceId(1)).unwrap();
        let h = Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };
        (dir, h)
    }

    /// Set, read, bake, print — the whole road the Mac takes, across the
    /// boundary.
    #[test]
    fn a_print_frame_set_baked_and_printed() {
        let (dir, mut h) = open("road");
        let d = h.project.doc_mut();
        let scene = d.create_scene("4");
        let (shot, _) = d.add_shot_to_scene(scene);
        let still = d.add_media(sha256(b"still"), MediaKind::Image, 1600, 900, 5, "still.jpg");
        let clip = d.add_media(sha256(b"clip"), MediaKind::Video, 1280, 856, 5, "take.mov");
        let still_use = d.attach_media(shot, still, "");
        let clip_use = d.attach_media(shot, clip, "");

        let spec = format!(
            r#"{{"layout":"across","numbers":false,"frames":[{{"use":"{}","at":1.5}},{{"use":"{}"}}],"arrows":"0.1,0.5,0.5,0.5,0.9,0.5,1,dashed,look:red"}}"#,
            clip_use.0, still_use.0
        );
        let view = dispatch(&mut h, &format!("printframe\t{}\t{spec}", shot.0));
        assert!(view.contains("\"printFrame\":{\"layout\":\"across\""), "{}", &view[..view.len().min(300)]);
        assert!(dispatch(&mut h, &format!("printframe\t{}\t{{\"layout\":\"spiral\",\"frames\":[]}}", shot.0)).contains("error"));
        assert!(dispatch(&mut h, &format!("printframe\t{}\t{{\"layout\":\"one\",\"frames\":[{{\"use\":\"1\"}}]}}", shot.0)).contains("error"));

        let pf = dispatch(&mut h, &format!("printframeview\t{}", shot.0));
        assert!(pf.contains("\"stale\":true") && pf.contains("\"baked\":null"), "{pf}");
        let digest = PrintFrame::parse(&spec).unwrap().digest();
        assert!(pf.contains(&digest));

        // A picture the Mac baked: any bytes do here, its shape is given.
        let bytes = b"\xff\xd8\xffbaked board".to_vec();
        let out = dispatch(&mut h, &format!("printframebake\t{}\t{digest}\t1600\t500\tjpg\t{}", shot.0, b64::encode(&bytes)));
        assert!(out.contains("\"stale\":false") && out.contains("\"width\":1600"), "{out}");

        let page = dir.join("table.html");
        let printed = dispatch(&mut h, &format!("print\ttable\t{}", page.to_str().unwrap()));
        assert!(!printed.contains("error"), "{printed}");
        let html = std::fs::read_to_string(&page).unwrap();
        assert!(html.contains(&b64::encode(&bytes)), "the bake is the shot's picture");
        assert!(html.contains("padding-top:31.25%"), "in its own shape");

        assert!(!dispatch(&mut h, &format!("printframe\t{}\tclear", shot.0)).contains("printFrame"));
        assert_eq!(dispatch(&mut h, &format!("printframeview\t{}", shot.0)), "null");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
