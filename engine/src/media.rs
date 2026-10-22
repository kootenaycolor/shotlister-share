//! Media: identity, ordering, framing and cache policy.
//!
//! The engine owns the decisions; the shells own the bytes. Deciding *that* a
//! video wants a 720p proxy, *which* originals to drop when the cache is full,
//! and *where* a 2.39 frame crops out of a 16:9 still is all pure logic that has
//! to behave identically on every platform. Actually encoding a frame or reading
//! a file is platform work and lives outside.
//!
//! Three ideas from the spec show up here:
//!
//!   - **A file is identified by its contents.** The same reference used across
//!     eight shots is one stored file, and sync never sends it twice.
//!   - **A file and a use of a file are different things.** The caption and the
//!     position belong to the use, so the same frame can appear on two shots
//!     saying different things.
//!   - **Proxies are always resident; originals are cached.** That is what keeps
//!     a project small enough to carry and still complete when you need it.

use crate::doc::{f, Doc};
use crate::hash::Hash256;
use crate::id::Id;
use crate::order;
use crate::store::Kind;
use crate::value::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MediaKind {
    Image,
    /// Animated, so it cannot be reduced to a single frame without losing the point.
    Gif,
    Video,
    /// **A scanned room — the `.usdz` you look at.** Ref 145 settled that the
    /// bytes stay as files rather than going into the document, and they still
    /// do: this is a `Kind::Media` like every photograph, so what the document
    /// holds is a hash and a name, and the room itself sits in `media/` beside
    /// the pictures. What it buys is that a scan can *travel* — until this
    /// existed a scan was reachable only from the one Mac holding the folder,
    /// so the phone that made it could not show it and the web could not know
    /// it was there.
    Scan,
    /// **The same room as measurements** — RoomPlan's walls and openings, which
    /// `crate::room` reads. The phone's rule since 2026-08-21: a scan is a pair
    /// of files sharing one name, the `.usdz` is what you look at and the JSON
    /// is the valuable half, because a floor plan can only be built from the
    /// second.
    ScanShape,
    Other,
}

impl MediaKind {
    pub fn as_str(self) -> &'static str {
        match self {
            MediaKind::Image => "image",
            MediaKind::Gif => "gif",
            MediaKind::Video => "video",
            MediaKind::Scan => "scan",
            MediaKind::ScanShape => "scan_shape",
            MediaKind::Other => "other",
        }
    }

    pub fn parse(s: &str) -> MediaKind {
        match s {
            "image" => MediaKind::Image,
            "gif" => MediaKind::Gif,
            "video" => MediaKind::Video,
            "scan" => MediaKind::Scan,
            "scan_shape" => MediaKind::ScanShape,
            _ => MediaKind::Other,
        }
    }

    /// Guessing from a file name is a fallback. The shells should say what a file
    /// actually is rather than trusting its extension — the prototype sniffed
    /// extensions and mislabelled anything served from a URL without one.
    pub fn guess_from_name(name: &str) -> MediaKind {
        let ext = name.rsplit('.').next().unwrap_or("").to_lowercase();
        match ext.as_str() {
            // `heif` sits beside `heic` — the same format, the other spelling.
            // It was missing, so an iPhone photograph saved under that name
            // guessed as "other" rather than as a picture.
            "jpg" | "jpeg" | "png" | "webp" | "heic" | "heif" | "tif" | "tiff" => MediaKind::Image,
            "gif" => MediaKind::Gif,
            "mp4" | "mov" | "m4v" | "webm" | "avi" => MediaKind::Video,
            // **A `.usdz` is a room and nothing else here makes one.** Its
            // measurements cannot be guessed the same way — a `.json` beside a
            // scan and a `.json` somebody dropped on a scene are the same
            // extension — so `ScanShape` is only ever set out loud.
            "usdz" => MediaKind::Scan,
            _ => MediaKind::Other,
        }
    }

    pub fn is_moving(self) -> bool {
        matches!(self, MediaKind::Video | MediaKind::Gif)
    }

    /// **Half of a scanned room, either half.** Nothing draws these as
    /// photographs, so every wall of pictures asks this first.
    pub fn is_scan(self) -> bool {
        matches!(self, MediaKind::Scan | MediaKind::ScanShape)
    }
}

/// **One scanned room, as two files that share a name.**
///
/// Either half may be missing and the room is still a room: without the shape
/// there is nothing to turn over, without the measurements there is no floor
/// plan and nothing can be measured. Saying which is missing is the difference
/// between a plan that failed and one that was never possible — the Mac has
/// said so since 2026-08-21 and the web says the same words.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Scan {
    /// The name the two files share, with no extension on it.
    pub name: String,
    /// The `.usdz`.
    pub shape: Option<Id>,
    /// The measurements `crate::room` reads.
    pub plan: Option<Id>,
    /// **The name its files were made with**, with no extension —
    /// `RoomScan_2026-08-27T131847`, whatever the room has been called
    /// since. A room's name is his to change; this is how its files are
    /// still found beside it, and it says when the room was scanned.
    pub file: String,
}

/// **When a room was scanned**, from the name the phone gives its files
/// (`RoomScan_2026-08-27T131847`): year, month, day, hour, minute. `None`
/// for a file named anything else.
pub fn scan_taken(file: &str) -> Option<(u32, u32, u32, u32, u32)> {
    let stamp = file.trim().strip_prefix("RoomScan_")?;
    let digits: String = stamp.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() < 12 {
        return None;
    }
    let n = |a: usize, b: usize| digits[a..b].parse::<u32>().ok();
    let when = (n(0, 4)?, n(4, 6)?, n(6, 8)?, n(8, 10)?, n(10, 12)?);
    ((1..=12).contains(&when.1) && (1..=31).contains(&when.2)).then_some(when)
}

/// When a room was scanned, as a list says it under its name: `Aug 27,
/// 2026 at 1:18 PM` — the time too, because four scans of one bathroom are
/// often taken the same afternoon. Empty when the file does not say.
pub fn scan_date_text(file: &str) -> String {
    const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    match scan_taken(file) {
        Some((y, m, d, h, min)) => {
            let (hour, half) = match h {
                0 => (12, "AM"),
                1..=11 => (h, "AM"),
                12 => (12, "PM"),
                _ => (h - 12, "PM"),
            };
            format!("{} {d}, {y} at {hour}:{min:02} {half}", MONTHS[(m - 1) as usize])
        }
        None => String::new(),
    }
}

/// **A room's name, from where it was scanned** (his ask, 2026-10-17:
/// scans named for the place they belong to, not at random):
/// `Call Her Back House · Kitchen · Scan 2` — the house, the room, and which
/// of that room's scans it is. A place with no house above it gives its own
/// name, then the rooms RoomPlan saw in the scan when it named any
/// (`Barn · Living Room · Scan 1`), else just `Barn · Scan 1`.
pub fn scan_name(house: &str, room: &str, seen: &[String], number: usize) -> String {
    let mut parts: Vec<String> = Vec::new();
    for p in [house, room] {
        let p = p.trim();
        if !p.is_empty() && !parts.iter().any(|q| q.eq_ignore_ascii_case(p)) {
            parts.push(p.to_string());
        }
    }
    if parts.len() < 2 {
        let mut named: Vec<String> = Vec::new();
        for r in seen {
            let r = r.trim();
            if r.is_empty() || r == "unidentified" {
                continue;
            }
            let words = crate::diagram::words_of(r);
            if !named.contains(&words) {
                named.push(words);
            }
        }
        if !named.is_empty() && named.len() <= 2 {
            parts.push(named.join(" & "));
        }
    }
    parts.push(format!("Scan {}", number.max(1)));
    parts.join(" · ")
}

// ---- proxies -----------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProxyFormat {
    /// A single still.
    Still,
    /// Animated but short and small — kept as-is rather than re-encoded, since
    /// re-encoding a GIF usually costs more than it saves.
    Animation,
    /// Re-encoded video, roughly 720p.
    Video,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProxySpec {
    pub format: ProxyFormat,
    /// Longest edge for stills, or height for video. Zero means "leave alone".
    pub target: u32,
}

pub const STILL_MAX_EDGE: u32 = 1600;
pub const VIDEO_PROXY_HEIGHT: u32 = 720;
pub const GIF_MAX_EDGE: u32 = 800;

/// What a proxy of this file should be. Something already smaller than the
/// target is left alone rather than re-encoded into something larger.
pub fn proxy_for(kind: MediaKind, width: u32, height: u32) -> ProxySpec {
    let longest = width.max(height);
    match kind {
        MediaKind::Image => ProxySpec {
            format: ProxyFormat::Still,
            target: if longest <= STILL_MAX_EDGE {
                0
            } else {
                STILL_MAX_EDGE
            },
        },
        MediaKind::Gif => ProxySpec {
            format: ProxyFormat::Animation,
            target: if longest <= GIF_MAX_EDGE { 0 } else { GIF_MAX_EDGE },
        },
        MediaKind::Video => ProxySpec {
            format: ProxyFormat::Video,
            target: if height <= VIDEO_PROXY_HEIGHT {
                0
            } else {
                VIDEO_PROXY_HEIGHT
            },
        },
        // A room is kept exactly as it arrived. There is no smaller version of
        // a set of measurements, and re-encoding geometry is not a thing.
        MediaKind::Scan | MediaKind::ScanShape | MediaKind::Other => ProxySpec {
            format: ProxyFormat::Still,
            target: 0,
        },
    }
}

// ---- aspect masking ----------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

/// The centred crop that makes a frame read at the project's ratio, so the board
/// looks like the film rather than like a pile of mismatched stills.
pub fn crop_to_ratio(width: u32, height: u32, ratio: f64) -> Rect {
    if width == 0 || height == 0 || ratio <= 0.0 {
        return Rect {
            x: 0,
            y: 0,
            width,
            height,
        };
    }
    let source = width as f64 / height as f64;
    if (source - ratio).abs() < f64::EPSILON {
        return Rect {
            x: 0,
            y: 0,
            width,
            height,
        };
    }
    if source > ratio {
        // Too wide: take a full-height slice out of the middle.
        let target_width = (height as f64 * ratio).round().max(1.0) as u32;
        let target_width = target_width.min(width);
        Rect {
            x: (width - target_width) / 2,
            y: 0,
            width: target_width,
            height,
        }
    } else {
        // Too tall: take a full-width slice out of the middle.
        let target_height = (width as f64 / ratio).round().max(1.0) as u32;
        let target_height = target_height.min(height);
        Rect {
            x: 0,
            y: (height - target_height) / 2,
            width,
            height: target_height,
        }
    }
}

// ---- cache policy ------------------------------------------------------

#[derive(Clone, Copy, Debug)]
pub struct CacheEntry {
    pub media: Id,
    pub bytes: u64,
    /// Any monotonic stamp; only the ordering matters.
    pub last_used: u64,
    /// Pinned for the field — a shoot day taken somewhere with no signal.
    pub pinned: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct CachePlan {
    pub keep: Vec<Id>,
    pub evict: Vec<Id>,
    pub kept_bytes: u64,
    /// True when pinned files alone exceed the budget. Nothing pinned is ever
    /// dropped — the honest answer is to say the budget is too small, not to
    /// quietly discard what was asked for.
    pub over_budget: bool,
}

/// Decide what to keep. Pinned first, then most recently used, until the budget
/// is spent. Only originals go through this; proxies are always resident.
pub fn plan_cache(entries: &[CacheEntry], budget_bytes: u64) -> CachePlan {
    let mut plan = CachePlan::default();

    let mut ordered: Vec<&CacheEntry> = entries.iter().collect();
    ordered.sort_by(|a, b| {
        b.pinned
            .cmp(&a.pinned)
            .then(b.last_used.cmp(&a.last_used))
            .then(a.media.cmp(&b.media))
    });

    for entry in ordered {
        let fits = plan.kept_bytes.saturating_add(entry.bytes) <= budget_bytes;
        if entry.pinned {
            plan.kept_bytes = plan.kept_bytes.saturating_add(entry.bytes);
            plan.keep.push(entry.media);
            if !fits {
                plan.over_budget = true;
            }
        } else if fits && !plan.over_budget {
            plan.kept_bytes = plan.kept_bytes.saturating_add(entry.bytes);
            plan.keep.push(entry.media);
        } else {
            plan.evict.push(entry.media);
        }
    }

    plan
}

// ---- a name that tells the truth about its bytes -----------------------

/// **Two extensions that mean one format.** `photo.jpeg` and `photo.jpg` are
/// the same picture, and rewriting one into the other would be churn for its
/// own sake.
fn same_format(one: &str, two: &str) -> bool {
    fn canonical(ext: &str) -> String {
        match ext.to_ascii_lowercase().as_str() {
            "jpeg" => "jpg".to_string(),
            "tiff" => "tif".to_string(),
            "heif" => "heic".to_string(),
            other => other.to_string(),
        }
    }
    canonical(one) == canonical(two)
}

/// **A file's name should say what its bytes actually are.** Ref 193.
///
/// A photograph off an iPhone arrives as `IMG_4523.HEIC` and is re-encoded to
/// JPEG on the way in, because HEIC is a format half the world cannot open. Its
/// *name* was kept exactly as it came — his rule, and the right one — but the
/// extension is part of the name, and so the project ended up holding JPEG
/// bytes under a name promising HEIC. The Drive bridge then wrote that name
/// into Google Drive, where anything opening it by extension gets a file that
/// is not what it says it is.
///
/// **The stem is untouched**, which is the part his rule is actually about:
/// `IMG_4523.HEIC` becomes `IMG_4523.jpg`, never `pasted.jpg`.
///
/// `stored` is what the proxy was written as, so it is the truth by
/// construction — the bytes are on disk under that extension whatever anybody
/// calls them.
pub fn name_with_extension(filename: &str, stored: &str) -> String {
    let stored = stored.trim().trim_start_matches('.');
    if stored.is_empty() {
        return filename.to_string();
    }
    match filename.rsplit_once('.') {
        // A name whose extension already names the format is left exactly
        // alone — including its capitals, which are somebody's file and not
        // ours to tidy.
        Some((_, had)) if same_format(had, stored) => filename.to_string(),
        // **An extension is only ever replaced within a family**, never across
        // one. This is the guard rail, and there is a real case behind it: a
        // permit dropped on a scene arrives as `permit.pdf` from a shell whose
        // `ext` argument is still its default of `png`, and renaming that to
        // `permit.png` would be a far worse lie than the one being fixed. The
        // engine already holds that a named file's own extension is better
        // evidence than a caller's default; this keeps to it.
        //
        // Within a family the shell's word is the truth, because the only way
        // an image ends up stored as a *different* image format is that
        // something deliberately re-encoded it.
        Some((stem, had))
            if !stem.is_empty()
                && MediaKind::guess_from_name(had) == MediaKind::guess_from_name(stored) =>
        {
            format!("{stem}.{stored}")
        }
        Some(_) => filename.to_string(),
        // No extension at all. Adding one cannot destroy anything, so it needs
        // no such caution — `permit` becomes `permit.pdf`.
        None => format!("{filename}.{stored}"),
    }
}

// ---- the document side -------------------------------------------------

impl Doc {
    /// Register a file. Two imports of the same bytes are one record, whatever
    /// they were called on disk.
    pub fn add_media(
        &mut self,
        hash: Hash256,
        kind: MediaKind,
        width: u32,
        height: u32,
        bytes: u64,
        filename: &str,
    ) -> Id {
        if let Some(existing) = self.media_with_hash(hash) {
            // Deleted from the Media window and dropped in again: the same
            // picture, back. (`crate::shelf`)
            self.revive_media(existing);
            return existing;
        }
        let id = self.create_record(Kind::Media);
        self.set(id, f::HASH, Value::text(hash.to_hex()));
        self.set(id, f::MEDIA_KIND, Value::text(kind.as_str()));
        self.set(id, f::WIDTH, Value::Int(width as i64));
        self.set(id, f::HEIGHT, Value::Int(height as i64));
        self.set(id, f::BYTES, Value::Int(bytes as i64));
        self.set(id, f::FILENAME, Value::text(filename));
        id
    }

    pub fn set_media_duration(&mut self, media: Id, seconds: f64) {
        self.set(media, f::DURATION, Value::Float(seconds));
    }

    pub fn media_with_hash(&self, hash: Hash256) -> Option<Id> {
        let wanted = hash.to_hex();
        self.store()
            .of_kind(&Kind::Media)
            .iter()
            .find(|r| r.text(f::HASH) == Some(wanted.as_str()))
            .map(|r| r.id)
    }

    /// **Remember the file a stored one was made from.** Ref 211.
    ///
    /// Set when a shell had to make a smaller copy on the way in — a clip
    /// re-encoded to 720p, a photograph shrunk. A file kept exactly as it
    /// arrived needs none of this: its own name already is the answer.
    pub fn remember_media_source(&mut self, media: Id, source: Hash256) {
        self.set(media, f::SOURCE, Value::text(source.to_hex()));
    }

    pub fn media_from_source(&self, source: Hash256) -> Option<Id> {
        let wanted = source.to_hex();
        self.store()
            .of_kind(&Kind::Media)
            .iter()
            .find(|r| r.text(f::SOURCE) == Some(wanted.as_str()))
            .map(|r| r.id)
    }

    /// **Does this project already hold this file?** Ref 211 — ask before
    /// encoding anything.
    ///
    /// The measured fault: the same four-second clip added to a shot and then
    /// to a location produced two stored files of identical size and different
    /// names. It happens because the small copy is what gets filed, and one
    /// encoder run is not byte-for-byte the same as the next — so the project,
    /// which knows a file by what is in it, correctly sees two different
    /// files.
    ///
    /// Filing the small copy under the *original's* name would fix it and cost
    /// more than it is worth: a stored file can currently check itself,
    /// because what is on disk hashes to the name it is filed under, and a
    /// torn one is detectable. This keeps that and answers the question
    /// anyway.
    ///
    /// Both doors, in the order they are cheap: the file may be here as it
    /// arrived, which covers everything small enough to keep whole, or it may
    /// be here as something made from it.
    pub fn media_already_here(&self, arriving: Hash256) -> Option<Id> {
        self.media_with_hash(arriving)
            .or_else(|| self.media_from_source(arriving))
    }

    /// **The same file, made smaller after the fact.** 2026-09-15.
    ///
    /// A clip stored at 720p in the first weeks went in at seven to ten
    /// megabits a second — a streaming service's number, not a shot list's —
    /// and Call Her Back was carrying 390 MB of clips that a phone screen
    /// cannot tell from 100. The encoder is quieter now, and this is how a
    /// clip already in a film gets the same treatment: the record keeps its
    /// identity, so every use of it — its frames, its trims, its arrows, its
    /// place as a shot's lead — is untouched, and only what it *is* changes.
    ///
    /// The shell has already written the new bytes under their own name; the
    /// old file is the shell's to remove, because the engine never touches
    /// files. What it was made from (`f::SOURCE`) is kept: a second drop of
    /// the same original still finds this record.
    ///
    /// Answers the hash the record held before, so the caller knows which
    /// files are now nobody's.
    pub fn replace_media_bytes(
        &mut self,
        media: Id,
        hash: Hash256,
        width: u32,
        height: u32,
        bytes: u64,
    ) -> Option<String> {
        let before = self.get(media)?.text(f::HASH).map(str::to_string)?;
        self.set(media, f::HASH, Value::text(hash.to_hex()));
        if width > 0 && height > 0 {
            self.set(media, f::WIDTH, Value::Int(width as i64));
            self.set(media, f::HEIGHT, Value::Int(height as i64));
        }
        self.set(media, f::BYTES, Value::Int(bytes as i64));
        Some(before)
    }

    /// **Which stored files nothing in the film names any more.**
    ///
    /// Given the names in a media folder — this device's, or the relay's — the
    /// ones no record accounts for. A file is accounted for when its stem is
    /// the stored name of a media record, or when it is a strip whose name
    /// begins the way `package::strip_key` begins one for a moving picture
    /// this film has. Anything not named like a stored file at all (a
    /// portal's `cover.png`, say) is not this film's to judge and is never
    /// answered.
    ///
    /// Strays come from two places: a clip replaced by a smaller copy of
    /// itself (`replace_media_bytes`) leaves its old movie, poster and strips
    /// behind under the old name; and a picture removed from every shot is
    /// reclaimed on the device that notices (Ref 192) but stayed on the relay
    /// for ever, because nothing there ever asked this question.
    ///
    /// Only the question is answered here. Whether to act on it — and how long
    /// to wait first, since a file can arrive a moment before the log that
    /// names it — is the caller's.
    ///
    /// One more: **a clip's PNG poster beside its JPEG one.** Posters became
    /// JPEG on 2026-09-15, and a device that took the new poster over the
    /// wire keeps the old one under the same name — the engine's `poster`
    /// retires it on the device that wrote the JPEG, and nowhere else.
    pub fn stray_media_names<'a>(&self, names: impl IntoIterator<Item = &'a str>) -> Vec<String> {
        let mut stems: Vec<String> = Vec::new();
        let mut moving_stems: Vec<String> = Vec::new();
        let mut strip_heads: Vec<String> = Vec::new();
        for record in self.store().of_kind(&Kind::Media) {
            // A deleted picture's record is only its name now; its files are
            // strays wherever they still are. (`crate::shelf`)
            if self.media_is_gone(record.id) {
                continue;
            }
            let Some(hash) = record.text(f::HASH) else { continue };
            stems.push(hash.chars().take(32).collect());
            let moving = record
                .text(f::MEDIA_KIND)
                .map(|k| MediaKind::parse(k).is_moving())
                .unwrap_or(false);
            if moving {
                moving_stems.push(hash.chars().take(32).collect());
                strip_heads.push(hash.chars().take(18).collect());
            }
        }
        // A script's text and PDF are filed under the revision's hash, beside
        // the pictures, since 2026-09-15 — so a revision names a stem too.
        for revision in self.revisions() {
            stems.push(revision.hash.chars().take(32).collect());
        }
        // **And every picture a saved version still shows**, removed since or
        // not. Without this a frame taken off a shot today is swept from this
        // Mac within the hour and from the relay within the week, and last
        // Tuesday's version comes back with a hole in it. (`crate::versions`)
        for media in self.media_kept_by_versions() {
            if self.media_is_gone(media) {
                continue;
            }
            let Some(record) = self.store().get_raw(media) else { continue };
            let Some(hash) = record.text(f::HASH) else { continue };
            stems.push(hash.chars().take(32).collect());
            let moving = record
                .text(f::MEDIA_KIND)
                .map(|k| MediaKind::parse(k).is_moving())
                .unwrap_or(false);
            if moving {
                moving_stems.push(hash.chars().take(32).collect());
                strip_heads.push(hash.chars().take(18).collect());
            }
        }
        // **And every Print Frame the Mac has baked** — a picture no media
        // record names, filed beside the others under its own hash.
        // (`crate::printframe`)
        stems.extend(self.print_frame_stems());
        let names: Vec<&str> = names.into_iter().collect();
        let has_jpeg_poster = |stem: &str| {
            names.iter().any(|n| {
                n.rsplit_once('.')
                    .map(|(s, e)| s == stem && e.eq_ignore_ascii_case("jpg"))
                    .unwrap_or(false)
            })
        };
        names
            .iter()
            .copied()
            .filter(|name| {
                let Some((stem, ext)) = name.rsplit_once('.') else { return false };
                let stored_shape = stem.len() == 32 && stem.chars().all(|c| c.is_ascii_hexdigit());
                if !stored_shape {
                    return false;
                }
                if ext.eq_ignore_ascii_case("png")
                    && moving_stems.iter().any(|s| s == stem)
                    && has_jpeg_poster(stem)
                {
                    return true;
                }
                if stems.iter().any(|s| s == stem) {
                    return false;
                }
                if ext.eq_ignore_ascii_case("strip")
                    && strip_heads.iter().any(|head| stem.starts_with(head.as_str()))
                {
                    return false;
                }
                true
            })
            .map(str::to_string)
            .collect()
    }

    pub fn media_kind(&self, media: Id) -> Option<MediaKind> {
        self.get(media)
            .and_then(|r| r.text(f::MEDIA_KIND).map(MediaKind::parse))
    }

    /// Attach a file to a shot or a scene. The caption belongs here rather than
    /// on the file, so the same frame can mean different things in two places.
    ///
    /// The first thing attached to a shot becomes its key frame — the one that
    /// stands for it in the table and in the spreadsheet.
    pub fn attach_media(&mut self, owner: Id, media: Id, caption: &str) -> Id {
        let tx = self.begin("Add frame");

        let positions: Vec<f64> = self
            .media_refs(owner)
            .iter()
            .filter_map(|id| self.get(*id).and_then(|r| r.float(f::ORDER)))
            .collect();
        let had_any = !positions.is_empty();

        let id = self.create_record(Kind::MediaRef);
        self.set(id, f::MEDIA, media);
        self.set(id, f::OWNER, owner);
        self.set(id, f::CAPTION, Value::text(caption));
        self.set(id, f::ORDER, order::after_last(&positions));

        // The first file on a **shot** becomes its lead frame — the one the
        // table and the storyboard draw. A scene owns attachments rather than
        // frames (its Notes tab), and a scene's standing picture is computed
        // from its shots, so crowning one here would invent a lead nothing
        // reads and quietly outrank the shots' own.
        let owner_is_shot = self.get(owner).map(|r| r.kind.clone()) == Some(Kind::Shot);
        if owner_is_shot && !had_any
            && self.get(owner).and_then(|r| r.ref_id(f::KEY_MEDIA)).is_none() {
            self.set(owner, f::KEY_MEDIA, id);
        }
        self.end(tx);
        id
    }

    /// **What this *use* of a file is called**, falling back to the file's own
    /// name when the use has not been given one.
    ///
    /// The caption has always lived on the use rather than on the file, "so the
    /// same frame can mean different things in two places" — the note on
    /// `attach_media` above. The name has to live there for the same reason,
    /// and until 2026-08-23 it did not, which put two of his rules in direct
    /// conflict the moment one photograph was used twice:
    ///
    /// > *"Photos in mood boards should keep their own names. Photos in
    /// > locations should be renamed based on the location and area."* (Ref 273)
    ///
    /// > *"There easily could be repeated images in a project — same photo in a
    /// > mood board and on a shot. Rather than duplicating it, they should
    /// > share the same photo."*
    ///
    /// One file wearing one name cannot do both: a photograph scouted at
    /// Hillcrest House and later hung on a wall of references came out on that
    /// wall called `hillcrest-house-01.jpg`. Measured on the committed build,
    /// 2026-08-23, and it is what he was reporting. A name per use settles it
    /// without storing the picture twice.
    pub fn media_ref_name(&self, media_ref: Id) -> String {
        if let Some(own) = self
            .get(media_ref)
            .and_then(|r| r.text(f::FILENAME))
            .filter(|s| !s.is_empty())
        {
            return own.to_string();
        }
        self.get(media_ref)
            .and_then(|r| r.ref_id(f::MEDIA))
            .and_then(|media| self.get(media).and_then(|r| r.text(f::FILENAME)))
            .unwrap_or_default()
            .to_string()
    }

    /// **Hangs this use of a picture on a different owner.** His ask: drag a
    /// picture from one mood board to another.
    ///
    /// The *use* moves rather than being destroyed and remade, which is the
    /// whole point: taking it off one wall and pasting it onto the next would
    /// lose the caption written under it and the name this use wears, and would
    /// look to the sync log like a deletion racing a creation. Rewriting the
    /// owner is one field, so it merges the way every other edit does.
    ///
    /// It lands at the end of the wall it arrives on. Nothing else moves.
    pub fn move_media_use(&mut self, media_ref: Id, owner: Id) {
        let already = self.get(media_ref).and_then(|r| r.ref_id(f::OWNER));
        if already == Some(owner) {
            return;
        }
        let tx = self.begin("Move picture");
        let positions: Vec<f64> = self
            .media_refs(owner)
            .iter()
            .filter_map(|id| self.get(*id).and_then(|r| r.float(f::ORDER)))
            .collect();
        self.set(media_ref, f::OWNER, Value::Ref(owner));
        self.set(media_ref, f::ORDER, order::after_last(&positions));
        self.end(tx);
    }

    /// Names this use of a file. Empty puts it back to wearing the file's own
    /// name rather than storing an empty one.
    pub fn set_media_ref_name(&mut self, media_ref: Id, name: &str) {
        let tx = self.begin("Name picture");
        if name.is_empty() {
            self.set(media_ref, f::FILENAME, Value::Null);
        } else {
            self.set(media_ref, f::FILENAME, Value::text(name));
        }
        self.end(tx);
    }

    /// **A use goes, and when it was the last, the file's record goes with
    /// it.** His ruling, 2026-09-19: *"if I add a piece of media to a shot
    /// list and it's only present in the shot list, then I delete it, it
    /// should delete it for good."* Until then only the use was deleted; the
    /// `Kind::Media` stayed, so the stray sweep (which judges by records)
    /// never touched the file, it synced to every device for ever, and the
    /// same original dropped again was quietly given the old copy back
    /// (Ref 211's dedupe) — which is how a green clip survived being
    /// re-imported. A file still in use somewhere else — a board, a
    /// location, another shot — keeps its record. The file itself is the
    /// sweep's: an hour's grace on disk, a week on the relay.
    pub fn release_media_use(&mut self, media_ref: Id) {
        let media = self.get(media_ref).and_then(|r| r.ref_id(f::MEDIA));
        self.delete(media_ref);
        if let Some(media) = media {
            let still_used = !self.store().referring_to(&Kind::MediaRef, f::MEDIA, media).is_empty();
            // A deleted picture's name is kept for the Media window's
            // Deleted list, gap or no gap. (`crate::shelf`)
            if !still_used && !self.media_is_gone(media) {
                self.delete(media);
            }
        }
    }

    /// Every use this owner holds, released — a shot, a board or a location
    /// on its way out.
    pub fn release_media_uses(&mut self, owner: Id) {
        for media_ref in self.media_refs(owner) {
            self.release_media_use(media_ref);
        }
    }

    pub fn detach_media(&mut self, media_ref: Id) {
        let tx = self.begin("Remove frame");

        let owner = self.get(media_ref).and_then(|r| r.ref_id(f::OWNER));
        self.release_media_use(media_ref);

        // If the key frame just went, fall back to whatever is now first rather
        // than leaving the shot looking empty in the table.
        if let Some(owner) = owner {
            let is_stale = self
                .get(owner)
                .and_then(|r| r.ref_id(f::KEY_MEDIA))
                .map(|current| current == media_ref)
                .unwrap_or(false);
            if is_stale {
                let next = self.media_refs(owner).first().copied();
                match next {
                    Some(next) => self.set(owner, f::KEY_MEDIA, next),
                    None => self.set(owner, f::KEY_MEDIA, Value::Null),
                }
                // The frame that was picked has gone, so what stands for the
                // shot now is a fallback again, not a decision — and the next
                // picture added should be free to take it over.
                self.set(owner, f::KEY_CHOSEN, Value::Null);
            }
        }
        self.end(tx);
    }

    /// Uses of files by this shot or scene, in order. Storyboard panels, scout
    /// frames, a reference clip.
    pub fn media_refs(&self, owner: Id) -> Vec<Id> {
        let mut refs = self.store().referring_to(&Kind::MediaRef, f::OWNER, owner);
        refs.sort_by(|a, b| {
            order::compare(
                a.float(f::ORDER).unwrap_or(0.0),
                b.float(f::ORDER).unwrap_or(0.0),
            )
        });
        refs.iter().map(|r| r.id).collect()
    }

    /// **Photographs only** — every use of a file on this owner except the
    /// halves of a scanned room.
    ///
    /// A scan is attached the same way a picture is, because it is a file and
    /// the document already knows exactly one way to hold one. That makes it
    /// arrive, uninvited, in every wall of pictures: a `.usdz` drawn as a
    /// photograph is a broken image, and its measurements are a second one.
    /// Every picture wall asks for this list instead.
    pub fn picture_refs(&self, owner: Id) -> Vec<Id> {
        self.media_refs(owner)
            .into_iter()
            .filter(|id| !self.media_ref_is_scan(*id))
            .collect()
    }

    /// Whether this *use* of a file is one half of a scan.
    pub fn media_ref_is_scan(&self, media_ref: Id) -> bool {
        self.get(media_ref)
            .and_then(|r| r.ref_id(f::MEDIA))
            .and_then(|media| self.media_kind(media))
            .map(MediaKind::is_scan)
            .unwrap_or(false)
    }

    /// **The scanned rooms at a location, newest first.**
    ///
    /// The pairing rule is the phone's, and it is read here the same way the
    /// Mac reads the folder: *a scan is a pair of files sharing one name*.
    /// Nothing records the relationship, so nothing has to be kept in step —
    /// the shape is found and its measurements are looked for beside it.
    ///
    /// **Measurements without a shape are still a scan.** A room can be carried
    /// as its measurements alone — they are the half a floor plan is built
    /// from, and they are the half small enough that a device short of room
    /// would keep them. Requiring the `.usdz` would have made those rooms
    /// invisible rather than flat.
    pub fn scans_of(&self, owner: Id) -> Vec<Scan> {
        let mut found: Vec<Scan> = Vec::new();
        let mut at: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        for media_ref in self.media_refs(owner) {
            let Some(media) = self.get(media_ref).and_then(|r| r.ref_id(f::MEDIA)) else {
                continue;
            };
            let kind = self.media_kind(media).unwrap_or(MediaKind::Other);
            if !kind.is_scan() {
                continue;
            }
            let name = self.media_ref_name(media_ref);
            let stem = name.rsplit_once('.').map(|(s, _)| s).unwrap_or(&name).to_string();
            let slot = *at.entry(stem.clone()).or_insert_with(|| {
                // The file's own name, under whatever this use is called.
                let made = media_ref_file(self, media_ref);
                found.push(Scan { name: stem.clone(), shape: None, plan: None, file: made });
                found.len() - 1
            });
            match kind {
                MediaKind::Scan => found[slot].shape = Some(media),
                _ => found[slot].plan = Some(media),
            }
        }
        // The phone names a scan for the moment it was taken, so the name sorts
        // the way the Mac's own list does — newest room first.
        found.sort_by(|a, b| b.name.cmp(&a.name));
        found
    }

    /// **What a room at this place would be called**, numbered `number`
    /// among the place's rooms (`scan_name`), with `seen` the rooms RoomPlan
    /// named inside the scan.
    pub fn scan_name_at(&self, place: Id, number: usize, seen: &[String]) -> String {
        let own = self.get(place).and_then(|r| r.text(f::LABEL).map(str::to_string)).unwrap_or_default();
        match self.parent_of_location(place) {
            Some(house) => {
                let house = self.get(house).and_then(|r| r.text(f::LABEL).map(str::to_string)).unwrap_or_default();
                scan_name(&house, &own, seen, number)
            }
            None => scan_name(&own, "", seen, number),
        }
    }

    /// **Suggested names for the rooms already scanned at a place**, oldest
    /// first, numbered in the order they were scanned: `(room, suggested)`.
    /// Nothing is renamed; `rename_scan` does that once he has seen them.
    /// `seen` gives the rooms RoomPlan named in a scan, by its `file`.
    pub fn suggested_scan_names(&self, place: Id, seen: &dyn Fn(&Scan) -> Vec<String>) -> Vec<(Scan, String)> {
        let mut rooms = self.scans_of(place);
        rooms.sort_by(|a, b| scan_taken(&a.file).cmp(&scan_taken(&b.file)).then(a.file.cmp(&b.file)));
        rooms
            .into_iter()
            .enumerate()
            .map(|(i, scan)| {
                let name = self.scan_name_at(place, i + 1, &seen(&scan));
                (scan, name)
            })
            .collect()
    }

    /// **Renames a scanned room** — both its uses, each keeping its file's
    /// extension — in one undo step. Its files, and every plan laid from it,
    /// are untouched. `false` when the place has no room called `from`.
    pub fn rename_scan(&mut self, place: Id, from: &str, to: &str) -> bool {
        let to = to.trim().to_string();
        if to.is_empty() {
            return false;
        }
        let uses: Vec<(Id, String)> = self
            .media_refs(place)
            .into_iter()
            .filter(|r| self.media_ref_is_scan(*r))
            .filter_map(|r| {
                let name = self.media_ref_name(r);
                let (stem, ext) = name.rsplit_once('.').map(|(s, e)| (s.to_string(), e.to_string())).unwrap_or((name.clone(), String::new()));
                (stem == from).then_some((r, ext))
            })
            .collect();
        if uses.is_empty() {
            return false;
        }
        let tx = self.begin("Rename Scan");
        for (r, ext) in uses {
            let named = if ext.is_empty() { to.clone() } else { format!("{to}.{ext}") };
            self.set(r, f::FILENAME, Value::text(named));
        }
        self.end(tx);
        true
    }

    /// The files themselves, in the same order.
    pub fn media_of(&self, owner: Id) -> Vec<Id> {
        self.media_refs(owner)
            .iter()
            .filter_map(|id| self.get(*id).and_then(|r| r.ref_id(f::MEDIA)))
            .collect()
    }

    /// Move a frame to a position in its owner's strip. Index is where it should
    /// end up once it has been lifted out — which is what a drag reports.
    ///
    /// Prefer this to computing neighbour positions by hand: asking for a spot
    /// relative to the wrong pair is easy, and lands two frames on the same
    /// position where their order is then undefined.
    pub fn move_media_to(&mut self, media_ref: Id, index: usize) {
        let owner = match self.get(media_ref).and_then(|r| r.ref_id(f::OWNER)) {
            Some(owner) => owner,
            None => return,
        };
        let others: Vec<Id> = self
            .media_refs(owner)
            .into_iter()
            .filter(|id| *id != media_ref)
            .collect();
        let position_at = |slot: usize| -> Option<f64> {
            others
                .get(slot)
                .and_then(|id| self.get(*id))
                .and_then(|r| r.float(f::ORDER))
        };
        let before = if index == 0 {
            None
        } else {
            position_at(index - 1)
        };
        let after = position_at(index);
        let position = order::between(before, after);
        self.set(media_ref, f::ORDER, position);
    }

    /// Lower-level move, when the neighbours are already known.
    pub fn move_media(&mut self, media_ref: Id, before: Option<f64>, after: Option<f64>) {
        let position = order::between(before, after);
        self.set(media_ref, f::ORDER, position);
    }

    /// **A decision**, as opposed to the lead frame a shot falls into having.
    /// Marked as such so that adding another picture afterwards does not
    /// quietly undo it — see `f::KEY_CHOSEN`.
    pub fn set_key_frame(&mut self, owner: Id, media_ref: Id) {
        let tx = self.begin("Choose frame");
        self.set(owner, f::KEY_MEDIA, media_ref);
        self.set(owner, f::KEY_CHOSEN, true);
        self.end(tx);
    }

    /// Whether somebody picked this shot's lead frame, rather than it being
    /// whichever picture arrived first.
    pub fn key_frame_was_chosen(&self, owner: Id) -> bool {
        self.get(owner)
            .and_then(|r| r.get(f::KEY_CHOSEN))
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
    }

    /// The file that stands for this shot. Falls back to the first attachment so
    /// a shot with frames is never blank in the table.
    pub fn key_frame(&self, owner: Id) -> Option<Id> {
        let chosen = self.key_media_ref(owner)?;
        self.get(chosen).and_then(|r| r.ref_id(f::MEDIA))
    }

    /// **The *use* that stands for this shot**, rather than the file it points
    /// at. Anything belonging to the use rather than to the file — the trim,
    /// the crop, the storyboard arrows — has to be asked for by this and not
    /// by `key_frame`, which throws the use away on its last line.
    pub fn key_media_ref(&self, owner: Id) -> Option<Id> {
        self.get(owner)
            .and_then(|r| r.ref_id(f::KEY_MEDIA))
            .filter(|id| self.get(*id).is_some())
            .or_else(|| self.media_refs(owner).first().copied())
    }

    /// The first frames of a scene, in story order — a filmstrip for a collapsed
    /// scene in the outline. Shots with no frame are skipped rather than leaving
    /// gaps, so five frames means five frames.
    pub fn scene_key_frames(&self, scene: Id, limit: usize) -> Vec<Id> {
        self.placements_in_scene(scene)
            .into_iter()
            .filter_map(|placement| self.get(placement).and_then(|r| r.ref_id(f::SHOT)))
            .filter_map(|shot| self.key_frame(shot))
            .take(limit)
            .collect()
    }

    /// **The remembered in/out range for this use of a clip**, in seconds.
    /// `None` when it has never been trimmed, or was reset — which means
    /// play the whole thing, exactly as it always has.
    pub fn media_trim(&self, media_ref: Id) -> Option<(f64, f64)> {
        let record = self.get(media_ref)?;
        match (record.float(f::TRIM_START), record.float(f::TRIM_END)) {
            (Some(start), Some(end)) => Some((start, end)),
            _ => None,
        }
    }

    /// Sets this use's trim range. Never touches the file on disk — only
    /// which part of it this attachment plays. `end` is held to at least a
    /// tenth of a second past `start`, so a slip of the handles cannot save a
    /// range with nothing in it.
    pub fn set_media_trim(&mut self, media_ref: Id, start: f64, end: f64) {
        let tx = self.begin("Trim clip");
        let start = start.max(0.0);
        let end = end.max(start + 0.1);
        self.set(media_ref, f::TRIM_START, Value::Float(start));
        self.set(media_ref, f::TRIM_END, Value::Float(end));
        self.end(tx);
    }

    /// Back to playing the whole clip. The file was never touched, so there
    /// is nothing to restore — just the memory of where it was cut.
    pub fn clear_media_trim(&mut self, media_ref: Id) {
        let tx = self.begin("Reset trim");
        self.set(media_ref, f::TRIM_START, Value::Null);
        self.set(media_ref, f::TRIM_END, Value::Null);
        self.end(tx);
    }

    /// **Which part of this picture to keep when it is drawn cropped.**
    ///
    /// `x` and `y` are the point that should end up in the middle, each from
    /// nought to one; `scale` is how far in, where one is the whole picture.
    /// Held inside those bounds here rather than in three shells: a value
    /// outside them is not a framing anybody can see, and two apps agreeing
    /// about that by accident is not an agreement.
    ///
    /// The file is never touched. This is the same bargain the trim strikes,
    /// on the same record, for the same reason.
    pub fn set_media_crop(&mut self, media_ref: Id, x: f64, y: f64, scale: f64) {
        let tx = self.begin("Crop picture");
        self.set(media_ref, f::CROP_X, Value::Float(x.clamp(0.0, 1.0)));
        self.set(media_ref, f::CROP_Y, Value::Float(y.clamp(0.0, 1.0)));
        self.set(media_ref, f::CROP_SCALE, Value::Float(scale.clamp(1.0, 8.0)));
        self.end(tx);
    }

    /// The middle of the picture, at full width — what it drew before anybody
    /// framed it.
    pub fn clear_media_crop(&mut self, media_ref: Id) {
        let tx = self.begin("Reset crop");
        self.set(media_ref, f::CROP_X, Value::Null);
        self.set(media_ref, f::CROP_Y, Value::Null);
        self.set(media_ref, f::CROP_SCALE, Value::Null);
        self.end(tx);
    }

    /// **The storyboard arrows drawn over this use of the picture.**
    ///
    /// Empty when nobody has drawn one, which is every picture until somebody
    /// does. Anything in the stored line that is not seven usable numbers is
    /// dropped rather than refused — a half-written field from a future
    /// version of this app should cost one arrow, never the whole picture.
    pub fn media_arrows(&self, media_ref: Id) -> Vec<Arrow> {
        let Some(record) = self.get(media_ref) else {
            return Vec::new();
        };
        match record.get(f::ARROWS).and_then(|v| v.as_text()) {
            Some(line) => Arrow::parse(line),
            None => Vec::new(),
        }
    }

    /// Draws this set of arrows over this use of the picture, replacing
    /// whatever was there. An empty set clears the field rather than storing
    /// an empty line: absent and "no arrows" have to be the same fact, or the
    /// two read differently on a device that has only ever seen one of them.
    ///
    /// Held inside the picture here rather than in three shells — an arrow
    /// whose head is off the edge is not a mark anybody can see, and two apps
    /// agreeing about that by accident is not an agreement.
    pub fn set_media_arrows(&mut self, media_ref: Id, arrows: &[Arrow]) {
        let tx = self.begin("Draw arrows");
        if arrows.is_empty() {
            self.set(media_ref, f::ARROWS, Value::Null);
        } else {
            let held: Vec<Arrow> = arrows.iter().map(|a| a.held()).collect();
            self.set(media_ref, f::ARROWS, Value::text(Arrow::encode(&held)));
        }
        self.end(tx);
    }

    /// Back to a bare photograph. The file was never marked, so there is
    /// nothing to restore — only the arrows to forget.
    pub fn clear_media_arrows(&mut self, media_ref: Id) {
        let tx = self.begin("Clear arrows");
        self.set(media_ref, f::ARROWS, Value::Null);
        self.end(tx);
    }

    /// **The arrows on this use, together with the picture's own size** — the
    /// pair an exporter needs, since an arrow is a fraction of the picture and
    /// cannot be drawn without knowing what shape that is.
    pub fn marks_on(&self, media_ref: Id) -> crate::export::rows::Marks {
        use crate::export::rows::Framing;
        // **No early return on "no arrows" any more.** There was one, and it
        // was why a printed page ignored the crop for three weeks: the whole
        // record was thrown away the moment nobody had drawn on the picture,
        // and the crop was in that record.
        let arrows = self.media_arrows(media_ref);
        let record = self.get(media_ref);
        let crop = record
            .as_ref()
            .map(|r| Framing {
                x: r.get(f::CROP_X).and_then(|v| v.as_float()).unwrap_or(0.5),
                y: r.get(f::CROP_Y).and_then(|v| v.as_float()).unwrap_or(0.5),
                scale: r.get(f::CROP_SCALE).and_then(|v| v.as_float()).unwrap_or(1.0),
            })
            .unwrap_or_default();
        let file = record.and_then(|r| r.ref_id(f::MEDIA));
        let (width, height) = file
            .and_then(|id| self.get(id))
            .map(|r| {
                (r.get(f::WIDTH).and_then(|v| v.as_int()).unwrap_or(0) as f64,
                 r.get(f::HEIGHT).and_then(|v| v.as_int()).unwrap_or(0) as f64)
            })
            .unwrap_or((0.0, 0.0));
        crate::export::rows::Marks { arrows, width, height, crop }
    }

    /// Files no use points at any more. Their bytes can go.
    pub fn orphaned_media(&self) -> Vec<Id> {
        let used: Vec<Id> = self
            .store()
            .of_kind(&Kind::MediaRef)
            .iter()
            .filter_map(|r| r.ref_id(f::MEDIA))
            .collect();
        // A picture only a saved version still shows is not an orphan: it
        // has somewhere to be. (`crate::versions`)
        let kept = self.media_kept_by_versions();
        self.store()
            .of_kind(&Kind::Media)
            .iter()
            .map(|r| r.id)
            .filter(|id| !used.contains(id) && !kept.contains(id) && !self.media_is_gone(*id))
            .collect()
    }
}

pub use crate::arrow::{Arrow, ArrowLook, ArrowShape, ArrowWeight};

/// A use's file's own name, with no extension: the name it was made with.
fn media_ref_file(doc: &Doc, media_ref: Id) -> String {
    let name = doc
        .get(media_ref)
        .and_then(|r| r.ref_id(f::MEDIA))
        .and_then(|media| doc.get(media).and_then(|r| r.text(f::FILENAME)).map(str::to_string))
        .unwrap_or_default();
    name.rsplit_once('.').map(|(s, _)| s.to_string()).unwrap_or(name)
}
