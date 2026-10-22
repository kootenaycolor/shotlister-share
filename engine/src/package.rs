//! The shape of a project on disk.
//!
//! A project is a package — a folder macOS presents as one file. What goes where
//! inside it, what the manifest says, and whether this build may write to it are
//! all decisions, and decisions belong in the engine so every shell agrees.
//!
//! The actual reading and writing does not live here. This module deals in names
//! and text, which is what keeps the engine runnable on the Mac, the phone and
//! in a browser alike.
//!
//! ```text
//! Daybreak.shotlist/
//!   manifest.json          what this is, and what wrote it
//!   changes/               append-only logs, one per device per session
//!   media/proxies/         always present, always offline
//!   media/originals/       cached on demand
//! ```

use crate::id::Id;
use crate::stamp::DeviceId;
use crate::{FORMAT_VERSION, MIN_WRITABLE_FORMAT};

pub const EXTENSION: &str = "shotlist";
pub const MANIFEST: &str = "manifest.json";
pub const CHANGES_DIR: &str = "changes";
pub const PROXY_DIR: &str = "media/proxies";
pub const ORIGINALS_DIR: &str = "media/originals";
pub const LOG_EXTENSION: &str = "log";
/// The mark an installation leaves beside its diaries. Ref 186.
pub const DEVICE_MARK_EXTENSION: &str = "device";
/// What a fold retired and what it rewrote — see `fold_record_name`.
pub const FOLD_RECORD_EXTENSION: &str = "folded";

// ---- what this build may do with a project -----------------------------

/// Why a project cannot be opened or written.
#[derive(Clone, Debug, PartialEq)]
pub enum Problem {
    /// Written by a newer build than this one.
    TooNew { found: u32, understood: u32 },
    /// Older than anything this build still knows how to read.
    TooOld { found: u32, floor: u32 },
    /// The manifest is missing or unreadable.
    Unreadable(String),
}

impl Problem {
    /// Said the way it should appear on screen — plainly, with what to do.
    pub fn message(&self) -> String {
        match self {
            Problem::TooNew { found, .. } => format!(
                "This project was made by a newer version of Shotlister (format {found}). \
                 Update to open it."
            ),
            Problem::TooOld { found, floor } => format!(
                "This project is in an old format ({found}) that this version can no longer \
                 write to. Open it in version {floor} or later to bring it forward."
            ),
            Problem::Unreadable(why) => format!("This project could not be read: {why}"),
        }
    }
}

/// What this build is allowed to do with a project at this format version.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Access {
    /// Normal.
    ReadWrite,
    /// Readable, but writing would risk data this build does not understand.
    /// The app goes read-only and says so rather than guessing.
    ReadOnly,
}

pub fn access(format: u32) -> Result<Access, Problem> {
    if format > FORMAT_VERSION {
        // A newer build wrote this. We can still show it — unknown fields are
        // carried through — but writing could drop what we cannot see.
        return Err(Problem::TooNew {
            found: format,
            understood: FORMAT_VERSION,
        });
    }
    if format < MIN_WRITABLE_FORMAT {
        return Ok(Access::ReadOnly);
    }
    Ok(Access::ReadWrite)
}

// ---- the manifest ------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub struct Manifest {
    pub format: u32,
    /// The project record's id, so a folder can be identified without reading
    /// every change in it.
    pub project: Option<Id>,
    pub title: String,
    /// Which build last wrote here — useful when something has gone wrong.
    pub engine: String,
    /// **The film's icon and colour, said on the outside of the package.**
    ///
    /// The pair lives on the project record like every other fact about a film
    /// (`crate::mark`); this is a copy of it written where it can be read
    /// **without opening the film**. That is the whole reason it is here: the
    /// project switcher draws a row per film and must not open eleven
    /// documents to do it, and the relay keeps one manifest per film so a Mac
    /// that has never downloaded a film can still draw it correctly.
    ///
    /// Empty on a film with no mark, and empty in every manifest written before
    /// this existed — `parse` defaults it, and an older build ignores a key it
    /// does not know, so nothing already on disk is disturbed either way.
    pub mark_path: String,
    /// The colour that goes with `mark_path`, `#RRGGBB`.
    pub mark_colour: String,
}

impl Manifest {
    pub fn new(title: &str, project: Option<Id>) -> Manifest {
        Manifest {
            format: FORMAT_VERSION,
            project,
            title: title.to_string(),
            engine: env!("CARGO_PKG_VERSION").to_string(),
            mark_path: String::new(),
            mark_colour: String::new(),
        }
    }

    pub fn encode(&self) -> String {
        let project = match self.project {
            Some(id) => format!("\"{}\"", id.to_hex()),
            None => "null".to_string(),
        };
        format!(
            "{{\n  \"format\": {},\n  \"project\": {project},\n  \"title\": \"{}\",\n  \"engine\": \"{}\",\n  \"markPath\": \"{}\",\n  \"markColour\": \"{}\"\n}}\n",
            self.format,
            escape(&self.title),
            escape(&self.engine),
            escape(&self.mark_path),
            escape(&self.mark_colour)
        )
    }

    pub fn parse(text: &str) -> Result<Manifest, Problem> {
        let format = number(text, "format")
            .ok_or_else(|| Problem::Unreadable("no format version".to_string()))?;
        Ok(Manifest {
            format: format as u32,
            project: string(text, "project").and_then(|hex| Id::from_hex(&hex)),
            title: string(text, "title").unwrap_or_default(),
            engine: string(text, "engine").unwrap_or_default(),
            mark_path: string(text, "markPath").unwrap_or_default(),
            mark_colour: string(text, "markColour").unwrap_or_default(),
        })
    }
}

fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push(' '),
            other => out.push(other),
        }
    }
    out
}

fn unescape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some(other) => out.push(other),
            None => break,
        }
    }
    out
}

/// Pull one string value out of a flat object. The manifest is ours and small,
/// so this is enough — anything richer belongs in a real parser.
fn string(text: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\"");
    let at = text.find(&needle)? + needle.len();
    let rest = text[at..].trim_start();
    let rest = rest.strip_prefix(':')?.trim_start();
    let rest = rest.strip_prefix('"')?;
    let mut value = String::new();
    let mut chars = rest.chars();
    while let Some(ch) = chars.next() {
        match ch {
            '\\' => {
                value.push('\\');
                if let Some(next) = chars.next() {
                    value.push(next);
                }
            }
            '"' => return Some(unescape(&value)),
            other => value.push(other),
        }
    }
    None
}

fn number(text: &str, key: &str) -> Option<u64> {
    let needle = format!("\"{key}\"");
    let at = text.find(&needle)? + needle.len();
    let rest = text[at..].trim_start().strip_prefix(':')?.trim_start();
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

// ---- names -------------------------------------------------------------

/// A file name for a project title that will survive being copied between a Mac,
/// a phone, a Windows machine and a Drive folder.
pub fn package_name(title: &str) -> String {
    let mut cleaned = String::new();
    let mut last_was_space = false;
    for ch in title.chars() {
        let replacement = match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => ' ',
            c if (c as u32) < 0x20 => ' ',
            other => other,
        };
        if replacement == ' ' {
            if !last_was_space && !cleaned.is_empty() {
                cleaned.push(' ');
            }
            last_was_space = true;
        } else {
            cleaned.push(replacement);
            last_was_space = false;
        }
    }
    // A leading dot would hide it; a trailing dot or space upsets Windows.
    let mut cleaned = cleaned.trim().trim_matches('.').trim().to_string();
    if cleaned.chars().count() > 60 {
        cleaned = cleaned.chars().take(60).collect::<String>().trim().to_string();
    }
    if cleaned.is_empty() {
        cleaned = "Untitled".to_string();
    }
    format!("{cleaned}.{EXTENSION}")
}

/// The log a device writes during one session. One writer per file is what keeps
/// appending safe — two devices never touch the same log.
pub fn log_name(device: DeviceId, session: u64) -> String {
    format!("{:016x}-{:016x}.{LOG_EXTENSION}", device.0, session)
}

pub fn is_log_name(name: &str) -> bool {
    name.ends_with(&format!(".{LOG_EXTENSION}")) && !name.starts_with('.')
}

/// **Which device wrote a log, and when it started.** The name carries both,
/// which is what makes folding old logs together possible without reading a
/// single one of them first: a device may only ever rewrite its own, and only
/// once they are old enough that every other device has certainly taken them
/// in. Ref 192.
///
/// `None` for anything that is not one of ours — including a name of the right
/// shape with something other than hexadecimal in it, which is somebody else's
/// file that happens to end in `.log`.
pub fn log_parts(name: &str) -> Option<(DeviceId, u64)> {
    if !is_log_name(name) {
        return None;
    }
    let stem = name.strip_suffix(&format!(".{LOG_EXTENSION}"))?;
    let (device, session) = stem.split_once('-')?;
    if device.len() != 16 || session.len() != 16 {
        return None;
    }
    Some((
        DeviceId(u64::from_str_radix(device, 16).ok()?),
        u64::from_str_radix(session, 16).ok()?,
    ))
}

// ---- who is writing under which name ----------------------------------

/// **The mark one installation leaves to say "this device id is me".** Ref 186.
///
/// The whole of sync rests on every device having a name of its own. Nothing
/// enforced that rule, and there was no way to notice when it broke: two
/// machines wearing one name write stamps that can land in the same
/// millisecond with the same counter, and the second one is then discarded as
/// a duplicate of the first. Silently, and with no trace afterwards.
///
/// **Why a file of its own rather than a line in the diary.** A diary's first
/// line is the format version, and a build older than this one refuses to open
/// a project whose diary it cannot parse — so widening that line would have
/// made an old phone unable to open his films at all. Nothing anywhere reads a
/// file in `changes/` that does not end in `.log`, so a mark is invisible to
/// every build that came before and costs nothing to ignore.
///
/// **Both halves are in the name and the file is empty**, which is what makes
/// it safe in a folder two machines are syncing: it is only ever created, never
/// written to and never rewritten, so there is nothing for two devices to
/// disagree about.
///
/// The installation is a fact about the *hardware* — on a Mac the platform
/// UUID — rather than something remembered in preferences. That is deliberate:
/// preferences are exactly what Migration Assistant copies when a new Mac is
/// set up from an old one, which is the most likely way for two machines to end
/// up wearing one name in the first place.
pub fn device_mark_name(device: DeviceId, installation: u64) -> String {
    format!(
        "{:016x}-{:016x}.{DEVICE_MARK_EXTENSION}",
        device.0, installation
    )
}

/// **What a fold left behind, so sync is never asked to undo it.** Ref 192.
///
/// Folding rewrites one log and deletes the others. The relay has never been
/// told, and it holds two rules that make that a problem on its own: a log may
/// only ever grow, so the rewritten one is refused outright; and a log the
/// relay has and this device has not is fetched, so the deleted ones come
/// straight back and are folded again on the next launch, for ever.
///
/// This is the fold saying what it did, in the only place both halves can see
/// it. **A file per device, never rewritten by anybody else**, exactly like the
/// identity mark above and for the same reason: two machines share one folder
/// and must never need to agree about a file. Nothing that came before reads
/// anything in `changes/` that does not end in `.log`, so an older build
/// ignores it at no cost.
pub fn fold_record_name(device: DeviceId) -> String {
    format!("{:016x}.{FOLD_RECORD_EXTENSION}", device.0)
}

pub fn is_fold_record_name(name: &str) -> bool {
    name.ends_with(&format!(".{FOLD_RECORD_EXTENSION}")) && !name.starts_with('.')
}

/// The two things a fold has to say, and nothing else.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct FoldRecord {
    /// Logs folded into another and deleted here. **Never fetch these again.**
    /// Their every change is inside the log named in `rewritten`, so bringing
    /// one back adds nothing and undoes the tidying.
    pub retired: Vec<String>,
    /// Logs a fold wrote over. **These go up with `?rewrite=1`** — the relay's
    /// one documented exception to a log only ever growing.
    ///
    /// Safe because of what the plan will and will not send: a log is only
    /// carried up when this device's copy is *longer* than the relay's, so the
    /// exception can never replace a good copy with a shorter one. And a fold
    /// only ever touches this device's own logs, which nothing else writes.
    pub rewritten: Vec<String>,
}

const FOLD_RECORD_HEADER: &str = "shotlister-folded";

/// **A line each, so two builds can add to one file without reading it.**
/// Anything unrecognised is skipped rather than refused, the same way a log
/// treats a line it cannot read.
pub fn decode_fold_record(text: &str) -> FoldRecord {
    let mut record = FoldRecord::default();
    for line in text.lines() {
        let Some((mark, name)) = line.split_once('\t') else {
            continue;
        };
        let name = name.trim();
        if !is_log_name(name) {
            continue;
        }
        match mark {
            "R" => record.retired.push(name.to_string()),
            "W" => record.rewritten.push(name.to_string()),
            _ => {}
        }
    }
    record.retired.sort();
    record.retired.dedup();
    record.rewritten.sort();
    record.rewritten.dedup();
    record
}

pub fn encode_fold_record(record: &FoldRecord) -> String {
    let mut out = format!("{FOLD_RECORD_HEADER} 1\n");
    for name in &record.retired {
        out.push_str(&format!("R\t{name}\n"));
    }
    for name in &record.rewritten {
        out.push_str(&format!("W\t{name}\n"));
    }
    out
}

pub fn is_device_mark_name(name: &str) -> bool {
    name.ends_with(&format!(".{DEVICE_MARK_EXTENSION}")) && !name.starts_with('.')
}

/// Which device id a mark claims, and which installation is claiming it.
///
/// `None` for anything that is not one of ours, including a name of the right
/// shape with something other than hexadecimal in it.
pub fn device_mark_parts(name: &str) -> Option<(DeviceId, u64)> {
    if !is_device_mark_name(name) {
        return None;
    }
    let stem = name.strip_suffix(&format!(".{DEVICE_MARK_EXTENSION}"))?;
    let (device, installation) = stem.split_once('-')?;
    if device.len() != 16 || installation.len() != 16 {
        return None;
    }
    Some((
        DeviceId(u64::from_str_radix(device, 16).ok()?),
        u64::from_str_radix(installation, 16).ok()?,
    ))
}

/// Media is named by its content, so the same frame is one file however many
/// times it was imported.
pub fn proxy_name(hash: &str, extension: &str) -> String {
    format!("{PROXY_DIR}/{}.{}", short(hash), safe_extension(extension))
}

/// **What a clip's four-moment strip is filed under.**
///
/// A strip belongs to a *use* of a clip rather than to the file: the trim
/// lives on the media ref, so one movie can owe two strips — the first four
/// seconds on one shot, the last three on another — and filing both under the
/// file's own hash would mean the second overwrote the first and both shots
/// printed whichever was made last.
///
/// So the trim goes in the name. It cannot go in the *extension* —
/// `safe_extension` keeps eight alphanumerics and would quietly truncate it
/// into a collision — so it goes in the stem, and the stem stays exactly the
/// thirty-two characters `proxy_name` is going to keep anyway: eighteen of the
/// hash, then the in and out points in milliseconds, seven hex digits each
/// (about seventy-four hours, which is longer than any clip).
///
/// **An untrimmed use is the bare short hash**, byte for byte the name strips
/// have always had, so nothing already on disk is orphaned.
///
/// This is the only place the name is worked out. The Mac makes the strips but
/// never computes this — it is handed the answer by the `clips` command — so
/// there is no second copy of this arithmetic to fall out of step.
pub fn strip_key(hash: &str, trim: Option<(f64, f64)>) -> String {
    let Some((start, end)) = trim else {
        return short(hash);
    };
    let ms = |seconds: f64| ((seconds.max(0.0) * 1000.0).round() as u64) & 0xFF_FFFFF;
    format!(
        "{}{:07x}{:07x}",
        hash.chars().take(18).collect::<String>(),
        ms(start),
        ms(end)
    )
}

pub fn original_name(hash: &str, extension: &str) -> String {
    format!(
        "{ORIGINALS_DIR}/{}.{}",
        short(hash),
        safe_extension(extension)
    )
}

fn short(hash: &str) -> String {
    hash.chars().take(32).collect()
}

fn safe_extension(extension: &str) -> String {
    let cleaned: String = extension
        .trim_start_matches('.')
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(8)
        .collect::<String>()
        .to_lowercase();
    if cleaned.is_empty() {
        "bin".to_string()
    } else {
        cleaned
    }
}
