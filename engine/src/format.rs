//! The change log's on-disk representation.
//!
//! This is the longest-lived contract in the project: files written today must
//! still open years from now, by builds nobody has written yet. So the format is
//! spelled out by hand rather than derived from the shape of a struct, which is
//! how formats quietly drift.
//!
//! One change per line, tab-separated, append-only — adding a change means
//! adding a line, never rewriting the file.
//!
//! ```text
//! shotlister-log 1
//! <millis>\t<counter>\t<device>\tC\t<id>\t<kind>
//! <millis>\t<counter>\t<device>\tS\t<id>\t<field>\t<value>
//! W\t<from millis>\t<from counter>\t<device>:<millis>:<counter>,…
//! ```
//!
//! The `W` line is how far the device had caught up, and from which point that
//! became true — a watermark, not a change. It is written as its own line and
//! not as extra columns on a change, because a build that predates it must still
//! read every change in the file rather than choking on a longer line. Such a
//! build sees `W` as a line it cannot interpret, and so preserves it verbatim.
//! It carries the point it applies from rather than relying on where it sits, so
//! shuffling the lines of a log cannot silently change what it means.
//!
//! **A line this build cannot read is kept, not dropped.** Unrecognised and even
//! malformed lines are preserved verbatim and written back out untouched. That is
//! the file-level form of the same rule that governs unknown fields: an older
//! build must never be the reason work disappears.
//!
//! No file system here — this is strings in, strings out, so it works the same in
//! a Mac app, on the phone, and in a browser. Reading and writing files belongs
//! to the shells.

use crate::id::Id;
use crate::stamp::{DeviceId, Seen, Stamp, Watermark};
use crate::store::{Change, Kind, Op};
use crate::value::Value;

pub const LOG_HEADER: &str = "shotlister-log";
const WATERMARK: &str = "W";

const SEP: char = '\t';
const LIST_SEP: char = '\u{1f}';

#[derive(Debug, PartialEq)]
pub enum DecodeError {
    MissingHeader,
    UnsupportedFormat(u32),
    /// The line is well-formed but uses something this build does not know.
    Unrecognised,
    Malformed,
}

#[derive(Debug, Clone)]
pub struct Log {
    pub format: u32,
    pub changes: Vec<Change>,
    /// Lines this build could not interpret, kept exactly as they were read.
    pub preserved: Vec<String>,
}

impl Log {
    pub fn new(format: u32) -> Log {
        Log {
            format,
            changes: Vec::new(),
            preserved: Vec::new(),
        }
    }
}

// ---- escaping ----------------------------------------------------------

pub(crate) fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            LIST_SEP => out.push_str("\\u"),
            other => out.push(other),
        }
    }
    out
}

pub(crate) fn unescape(s: &str) -> Result<String, DecodeError> {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
            continue;
        }
        match chars.next() {
            Some('\\') => out.push('\\'),
            Some('t') => out.push('\t'),
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('u') => out.push(LIST_SEP),
            _ => return Err(DecodeError::Malformed),
        }
    }
    Ok(out)
}

// ---- values ------------------------------------------------------------

/// Lists hold scalars only, which covers every multi-value field in the model
/// (angle, tags, pov, ordered media references). A nested list is refused rather
/// than written in a shape a later reader might misread.
pub fn encode_value(value: &Value) -> Result<String, DecodeError> {
    Ok(match value {
        Value::Null => "n".to_string(),
        Value::Text(s) => format!("t:{}", escape(s)),
        Value::Int(i) => format!("i:{i}"),
        Value::Float(f) => format!("f:{f:?}"),
        Value::Bool(b) => format!("b:{}", if *b { 1 } else { 0 }),
        Value::Ref(id) => format!("r:{}", id.to_hex()),
        Value::List(items) => {
            let mut parts = Vec::with_capacity(items.len());
            for item in items {
                if matches!(item, Value::List(_)) {
                    return Err(DecodeError::Malformed);
                }
                parts.push(escape(&encode_value(item)?));
            }
            format!("l:{}", parts.join(&LIST_SEP.to_string()))
        }
    })
}

pub fn decode_value(text: &str) -> Result<Value, DecodeError> {
    if text == "n" {
        return Ok(Value::Null);
    }
    let (tag, rest) = text.split_once(':').ok_or(DecodeError::Malformed)?;
    match tag {
        "t" => Ok(Value::Text(unescape(rest)?)),
        "i" => rest
            .parse::<i64>()
            .map(Value::Int)
            .map_err(|_| DecodeError::Malformed),
        "f" => rest
            .parse::<f64>()
            .map(Value::Float)
            .map_err(|_| DecodeError::Malformed),
        "b" => match rest {
            "1" => Ok(Value::Bool(true)),
            "0" => Ok(Value::Bool(false)),
            _ => Err(DecodeError::Malformed),
        },
        "r" => Id::from_hex(rest)
            .map(Value::Ref)
            .ok_or(DecodeError::Malformed),
        "l" => {
            if rest.is_empty() {
                return Ok(Value::List(Vec::new()));
            }
            let mut items = Vec::new();
            for part in rest.split(LIST_SEP) {
                items.push(decode_value(&unescape(part)?)?);
            }
            Ok(Value::List(items))
        }
        // A value type introduced by a later build.
        _ => Err(DecodeError::Unrecognised),
    }
}

// ---- changes -----------------------------------------------------------

pub fn encode_change(change: &Change) -> Result<String, DecodeError> {
    let Stamp {
        millis,
        counter,
        device,
    } = change.stamp;
    let head = format!("{millis}{SEP}{counter}{SEP}{}", device.0);
    Ok(match &change.op {
        Op::Create { kind, id } => {
            format!("{head}{SEP}C{SEP}{}{SEP}{}", id.to_hex(), escape(kind.as_str()))
        }
        Op::Set { id, field, value } => format!(
            "{head}{SEP}S{SEP}{}{SEP}{}{SEP}{}",
            id.to_hex(),
            escape(field),
            encode_value(value)?
        ),
    })
}

pub fn decode_change(line: &str) -> Result<Change, DecodeError> {
    let parts: Vec<&str> = line.split(SEP).collect();
    if parts.len() < 6 {
        return Err(DecodeError::Malformed);
    }
    let millis = parts[0].parse::<u64>().map_err(|_| DecodeError::Malformed)?;
    let counter = parts[1].parse::<u32>().map_err(|_| DecodeError::Malformed)?;
    let device = DeviceId(parts[2].parse::<u64>().map_err(|_| DecodeError::Malformed)?);
    let id = Id::from_hex(parts[4]).ok_or(DecodeError::Malformed)?;
    let stamp = Stamp {
        millis,
        counter,
        device,
    };

    match parts[3] {
        "C" => Ok(Change::new(
            stamp,
            Op::Create {
                kind: Kind::parse(&unescape(parts[5])?),
                id,
            },
        )),
        "S" => {
            if parts.len() < 7 {
                return Err(DecodeError::Malformed);
            }
            // The value may itself contain no tabs, so the remainder is one field.
            let raw_value = parts[6..].join(&SEP.to_string());
            Ok(Change::new(
                stamp,
                Op::Set {
                    id,
                    field: unescape(parts[5])?,
                    value: decode_value(&raw_value)?,
                },
            ))
        }
        // An operation introduced by a later build.
        _ => Err(DecodeError::Unrecognised),
    }
}

// ---- watermarks --------------------------------------------------------

/// Where a watermark takes effect: the position in the total order from which
/// the device knew that much. Kept as (millis, counter) because a watermark is
/// a point in time rather than one device's write.
type From = (u64, u32);

fn encode_watermark(seen: &Watermark, from: From) -> String {
    let heard: Vec<String> = seen
        .heard()
        .iter()
        .map(|s| format!("{}:{}:{}", s.device.0, s.millis, s.counter))
        .collect();
    // A line with no devices on it still means something — "this device had
    // heard from nobody" — and is not the same as no line at all, which means a
    // build that did not record any of this.
    format!(
        "{WATERMARK}{SEP}{}{SEP}{}{SEP}{}",
        from.0,
        from.1,
        heard.join(",")
    )
}

fn decode_watermark(line: &str) -> Option<(Watermark, From)> {
    let parts: Vec<&str> = line.split(SEP).collect();
    if parts.len() != 4 || parts[0] != WATERMARK {
        return None;
    }
    let from = (parts[1].parse().ok()?, parts[2].parse().ok()?);
    let mut heard = Vec::new();
    if !parts[3].is_empty() {
        for entry in parts[3].split(',') {
            let mut fields = entry.split(':');
            heard.push(Seen {
                device: DeviceId(fields.next()?.parse().ok()?),
                millis: fields.next()?.parse().ok()?,
                counter: fields.next()?.parse().ok()?,
            });
        }
    }
    Some((Watermark::Heard(heard), from))
}

/// Changes as lines, with a watermark line wherever the writing device's
/// knowledge moved on. Both a whole log and an appended block go through here,
/// so the two cannot drift.
pub fn encode_changes(changes: &[Change]) -> String {
    let mut out = String::new();
    let mut current: Option<&Watermark> = None;
    for change in changes {
        if let Ok(line) = encode_change(change) {
            if change.seen.is_known() && current != Some(&change.seen) {
                let from = (change.stamp.millis, change.stamp.counter);
                out.push_str(&encode_watermark(&change.seen, from));
                out.push('\n');
                current = Some(&change.seen);
            }
            out.push_str(&line);
            out.push('\n');
        }
    }
    out
}

// ---- whole logs --------------------------------------------------------

pub fn encode_log(format: u32, changes: &[Change], preserved: &[String]) -> String {
    let mut out = String::new();
    out.push_str(LOG_HEADER);
    out.push(' ');
    out.push_str(&format.to_string());
    out.push('\n');
    out.push_str(&encode_changes(changes));
    // Lines from a build we do not understand go back out exactly as they came in.
    for line in preserved {
        out.push_str(line);
        out.push('\n');
    }
    out
}

pub fn decode_log(text: &str) -> Result<Log, DecodeError> {
    let mut lines = text.lines();
    let header = lines.next().ok_or(DecodeError::MissingHeader)?;
    let (name, version) = header.split_once(' ').ok_or(DecodeError::MissingHeader)?;
    if name != LOG_HEADER {
        return Err(DecodeError::MissingHeader);
    }
    let format = version
        .trim()
        .parse::<u32>()
        .map_err(|_| DecodeError::MissingHeader)?;

    let mut log = Log::new(format);
    let mut marks: Vec<(From, Watermark)> = Vec::new();
    for line in lines {
        if line.trim().is_empty() {
            continue;
        }
        if let Some((seen, from)) = decode_watermark(line) {
            marks.push((from, seen));
            continue;
        }
        match decode_change(line) {
            Ok(change) => log.changes.push(change),
            // Never discard. A line we cannot read is still somebody's work.
            Err(_) => log.preserved.push(line.to_string()),
        }
    }

    // Each change takes the last watermark that had come into effect by the time
    // it was written. Read from the markers' own contents rather than from where
    // they sit, so a reordered file still means what it meant.
    if !marks.is_empty() {
        marks.sort_by_key(|(from, _)| *from);
        for change in &mut log.changes {
            let at = (change.stamp.millis, change.stamp.counter);
            let mark = marks.partition_point(|(from, _)| *from <= at);
            if mark > 0 {
                change.seen = marks[mark - 1].1.clone();
            }
        }
    }
    Ok(log)
}
