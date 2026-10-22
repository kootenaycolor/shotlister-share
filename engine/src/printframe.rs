//! **A shot's Print Frame** — the one picture that stands for a shot in every
//! PDF (the table's picture column and the storyboard page). His ask,
//! 2026-10-14; the design is `design/45-print-frame.html`.
//!
//! Built from the shot's own pictures: a still as it is, or any moment of one
//! of its clips, laid out on a board (`layout`), with or without numbers,
//! with arrows drawn across the whole board. **The Mac bakes** that board into
//! one picture and hands it here (`set_print_frame_baked`); the printed page
//! uses it in place of the shot's own picture while it is current.
//!
//! Two fields on the shot, each one line of text so a change is one entry in
//! the log and two devices merge it the way they merge any other field:
//!
//! - `print_frame` — the spec, as JSON, always written in one canonical form
//!   (`PrintFrame::encode`) so the same spec is the same text everywhere:
//!   `{"layout":"grid22","numbers":true,"frames":[{"use":"<ref id>","at":3.2}],"arrows":"<arrow line>"}`.
//!   `at` (seconds from the start of the whole clip) only on a clip's frame;
//!   `arrows` only when there are some, in the arrow line of `crate::arrow`,
//!   every number a fraction of the board's width and height.
//! - `print_frame_baked` — what the Mac last baked, as JSON:
//!   `{"hash":"<sha-256 hex>","ext":"jpg","width":1600,"height":1120,"digest":"<16 hex>"}`.
//!   `digest` is `PrintFrame::digest` of the spec it was baked from. A spec
//!   that changes without a new bake (set by Claude's connector, undone, or
//!   arriving from another device) no longer matches, which is what *stale*
//!   means: the Mac bakes again the next time it has the film open, and until
//!   then the printed page draws the shot exactly as it did before Print
//!   Frames existed.
//!
//! Absent spec means no Print Frame, which is every shot until somebody makes
//! one — and such a shot prints exactly as it always has.

use crate::arrow::Arrow;
use crate::doc::{f, Doc};
use crate::id::Id;
use crate::store::Kind;
use crate::value::Value;

/// Every layout a board can take (`layout()` in the mockup, ported to the Mac).
pub const LAYOUTS: &[&str] = &[
    "one", "across", "stacked", "grid22", "grid32", "grid23", "side", "under", "rows", "cols",
];

/// The most frames one board holds.
pub const MOST_FRAMES: usize = 16;

/// One frame on the board: a use of a picture on this shot, and for a clip
/// the moment, in seconds from the start of the whole clip.
#[derive(Clone, Debug, PartialEq)]
pub struct Moment {
    pub media_ref: Id,
    pub at: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PrintFrame {
    pub layout: String,
    pub frames: Vec<Moment>,
    pub numbers: bool,
    /// On the whole board, in fractions of its width and height.
    pub arrows: Vec<Arrow>,
}

/// What the Mac last baked for a shot.
#[derive(Clone, Debug, PartialEq)]
pub struct Baked {
    /// The picture's SHA-256, in hex — what it is filed under beside the
    /// film's other pictures (the first 32 characters name the file).
    pub hash: String,
    pub ext: String,
    pub width: u32,
    pub height: u32,
    /// The digest of the spec it was baked from.
    pub digest: String,
}

impl Baked {
    /// The 32 characters its file is named by.
    pub fn stem(&self) -> String {
        self.hash.chars().take(32).collect()
    }

    pub fn encode(&self) -> String {
        let mut j = crate::jsonw::Json::new();
        j.obj()
            .kv("hash", &self.hash)
            .kv("ext", &self.ext)
            .ki("width", self.width as i64)
            .ki("height", self.height as i64)
            .kv("digest", &self.digest)
            .end_obj();
        j.finish()
    }

    pub fn parse(text: &str) -> Option<Baked> {
        let json = crate::json::parse(text)?;
        let hash = json.get("hash")?.as_str()?.to_lowercase();
        if hash.len() < 32 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        Some(Baked {
            hash,
            ext: json.get("ext").and_then(|v| v.as_str()).unwrap_or("jpg").to_string(),
            width: json.get("width").and_then(|v| v.as_f64()).unwrap_or(0.0).max(0.0) as u32,
            height: json.get("height").and_then(|v| v.as_f64()).unwrap_or(0.0).max(0.0) as u32,
            digest: json.get("digest").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        })
    }
}

impl PrintFrame {
    /// The same spec, held to what can be drawn: a moment is never before
    /// the start, the board holds at most `MOST_FRAMES`, a frame is not on
    /// the board twice at the same moment, and every arrow is held on the
    /// board. An unknown layout is kept as written — a newer Mac may know it.
    pub fn held(&self) -> PrintFrame {
        let mut frames: Vec<Moment> = Vec::new();
        for m in &self.frames {
            let at = m.at.filter(|t| t.is_finite()).map(|t| (t.max(0.0) * 1000.0).round() / 1000.0);
            let moment = Moment { media_ref: m.media_ref, at };
            if !frames.contains(&moment) && frames.len() < MOST_FRAMES {
                frames.push(moment);
            }
        }
        PrintFrame {
            layout: self.layout.trim().to_string(),
            frames,
            numbers: self.numbers,
            arrows: self.arrows.iter().map(|a| a.held()).collect(),
        }
    }

    /// The canonical stored text. The same spec is always the same text.
    pub fn encode(&self) -> String {
        let held = self.held();
        let mut j = crate::jsonw::Json::new();
        j.obj().kv("layout", &held.layout).kb("numbers", held.numbers);
        j.key("frames").arr();
        for m in &held.frames {
            j.obj().kv("use", &m.media_ref.0.to_string());
            if let Some(at) = m.at {
                j.kn("at", at);
            }
            j.end_obj();
        }
        j.end_arr();
        if !held.arrows.is_empty() {
            j.kv("arrows", &Arrow::encode(&held.arrows));
        }
        j.end_obj();
        j.finish()
    }

    /// Forgiving: a frame whose use cannot be read is dropped, a missing
    /// layout reads as `one`.
    pub fn parse(text: &str) -> Option<PrintFrame> {
        let json = crate::json::parse(text)?;
        let layout = json.get("layout").and_then(|v| v.as_str()).unwrap_or("one").to_string();
        let numbers = json.get("numbers").and_then(|v| v.as_bool()).unwrap_or(false);
        let frames = json
            .get("frames")
            .and_then(|v| v.as_array())
            .unwrap_or(&[])
            .iter()
            .filter_map(|m| {
                let said = match m.get("use")? {
                    crate::json::Json::Text(t) => t.trim().to_string(),
                    crate::json::Json::Number(n) => format!("{}", *n as u128),
                    _ => return None,
                };
                let id = said.parse::<u128>().ok().map(Id)?;
                Some(Moment { media_ref: id, at: m.get("at").and_then(|v| v.as_f64()) })
            })
            .collect();
        let arrows = json.get("arrows").and_then(|v| v.as_str()).map(Arrow::parse).unwrap_or_default();
        Some(PrintFrame { layout, frames, numbers, arrows }.held())
    }

    /// **The fingerprint a bake is checked against**: the first sixteen hex
    /// characters of the SHA-256 of the canonical text (`encode`).
    pub fn digest(&self) -> String {
        crate::hash::sha256(self.encode().as_bytes()).short()
    }
}

impl Doc {
    /// This shot's Print Frame, if anybody has made one.
    pub fn print_frame(&self, shot: Id) -> Option<PrintFrame> {
        let text = self.get(shot)?.get(f::PRINT_FRAME)?.as_text()?.to_string();
        PrintFrame::parse(&text)
    }

    /// Sets this shot's Print Frame — one step to undo. The bake is left
    /// where it is: it simply stops matching, and the Mac bakes again.
    pub fn set_print_frame(&mut self, shot: Id, spec: &PrintFrame) {
        let tx = self.begin("Change Print Frame");
        self.set(shot, f::PRINT_FRAME, Value::text(spec.encode()));
        self.end(tx);
    }

    /// No Print Frame: the shot prints exactly as it did before they existed.
    /// The bake goes with it, so nothing stale is left to sweep later.
    pub fn clear_print_frame(&mut self, shot: Id) {
        let tx = self.begin("Reset Print Frame");
        self.set(shot, f::PRINT_FRAME, Value::Null);
        self.set(shot, f::PRINT_FRAME_BAKED, Value::Null);
        self.end(tx);
    }

    /// What the Mac last baked for this shot, current or not.
    pub fn print_frame_baked(&self, shot: Id) -> Option<Baked> {
        let text = self.get(shot)?.get(f::PRINT_FRAME_BAKED)?.as_text()?.to_string();
        Baked::parse(&text)
    }

    /// **The Mac's bake, filed.** Not a step to undo — the Mac does this on
    /// his behalf, after the change he made, and ⌘Z taking back a bake would
    /// undo nothing he did. It still travels like any other change.
    pub fn set_print_frame_baked(&mut self, shot: Id, baked: &Baked) {
        self.write_without_recording(shot, f::PRINT_FRAME_BAKED, Value::text(baked.encode()));
    }

    /// Whether the bake on file was made from the spec on file, and every
    /// frame it names is still on the shot.
    pub fn print_frame_is_current(&self, shot: Id) -> bool {
        let (Some(spec), Some(baked)) = (self.print_frame(shot), self.print_frame_baked(shot)) else {
            return false;
        };
        baked.digest == spec.digest() && spec.frames.iter().all(|m| self.frame_is_on(shot, m.media_ref))
    }

    /// **The picture a printed page draws for this shot**, when there is a
    /// current one. `None` means print it the way it always printed.
    pub fn print_frame_picture(&self, shot: Id) -> Option<Baked> {
        if self.print_frame_is_current(shot) {
            self.print_frame_baked(shot)
        } else {
            None
        }
    }

    fn frame_is_on(&self, shot: Id, media_ref: Id) -> bool {
        self.get(media_ref)
            .filter(|r| r.kind == Kind::MediaRef)
            .and_then(|r| r.ref_id(f::OWNER))
            == Some(shot)
    }

    /// The stems every bake on file is named by — so a sweep of files the
    /// film no longer names leaves them alone.
    pub fn print_frame_stems(&self) -> Vec<String> {
        self.store()
            .of_kind(&Kind::Shot)
            .iter()
            .filter_map(|r| r.get(f::PRINT_FRAME_BAKED).and_then(|v| v.as_text()).and_then(Baked::parse))
            .map(|b| b.stem())
            .collect()
    }

    /// **The Print Frame as the Mac and the phone read it**, as one JSON
    /// object, or `None` when the shot has none:
    ///
    /// ```text
    /// {"layout":"grid22","numbers":true,
    ///  "frames":[{"use":"<ref id>","at":3.2,"live":true}, …],
    ///  "arrows":"<arrow line>",            // only when there are some
    ///  "digest":"<16 hex>",                // of the spec as it stands
    ///  "baked":{"hash":…,"ext":…,"width":…,"height":…,"digest":…} | null,
    ///  "stale":false}
    /// ```
    ///
    /// `live` is false for a frame whose picture has since come off the shot.
    /// `stale` is true whenever the printed page would not use the bake —
    /// none yet, made from another spec, or naming a frame that has gone —
    /// which is the Mac's cue to bake again.
    pub fn print_frame_view(&self, shot: Id) -> Option<String> {
        let spec = self.print_frame(shot)?;
        let baked = self.print_frame_baked(shot);
        let mut j = crate::jsonw::Json::new();
        j.obj().kv("layout", &spec.layout).kb("numbers", spec.numbers);
        j.key("frames").arr();
        for m in &spec.frames {
            j.obj().kv("use", &m.media_ref.0.to_string());
            if let Some(at) = m.at {
                j.kn("at", at);
            }
            j.kb("live", self.frame_is_on(shot, m.media_ref)).end_obj();
        }
        j.end_arr();
        if !spec.arrows.is_empty() {
            j.kv("arrows", &Arrow::encode(&spec.arrows));
        }
        j.kv("digest", &spec.digest());
        match &baked {
            Some(b) => {
                j.key("baked").raw(&b.encode());
            }
            None => {
                j.key("baked").null();
            }
        }
        j.kb("stale", !self.print_frame_is_current(shot));
        j.end_obj();
        Some(j.finish())
    }
}
