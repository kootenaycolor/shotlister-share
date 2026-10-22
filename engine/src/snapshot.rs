//! A saved state, so a reader does not replay every change.
//!
//! A document is its change log: open a film and every change in every log is
//! applied, one after the other, before the first question is answered. On a
//! Mac that happens once, when the film opens. In a worker it happens on
//! **every request**, because a worker keeps nothing between them — his
//! largest film is ten thousand changes, replayed for every tool call and
//! every look at a film's card. His row, 2026-09-16: a saved current state per
//! film, keyed by the log lengths, so a request replays only what is new.
//!
//! This is that state. **The records, with the stamp each field was written
//! under, and the furthest stamp heard from each device.** Restoring it puts
//! the records back without applying a change and leaves the clock having
//! heard everything the snapshot covers — so a change written afterwards sorts
//! after everything already in the film rather than being dropped as stale,
//! and does not accuse a device it has in fact heard from (`stamp::Watermark`,
//! and Ref 339 for the shape of the bug when a device has *not* heard).
//!
//! **It is a cache, never a record.** Nothing on disk changes: a `.shotlist`
//! still holds its logs and nothing else, the log format is untouched, and a
//! snapshot that is missing, stale or unreadable costs nothing but the replay
//! it would have saved. That is also why a line this build cannot read makes
//! the whole snapshot unreadable rather than being preserved: a log line is
//! somebody's work and must survive; a snapshot line is a copy of it and must
//! not be guessed at.
//!
//! **What it does not carry: the log itself.** A restored document holds the
//! state the log produced, not the log — so what is derived from the log
//! rather than from the records is empty after a restore: `clashes`,
//! `settled_orphans`, `changes().len()`. The worker never asks for any of
//! those; a Mac never restores. If one day something does both, the snapshot
//! is the wrong tool for it and this is where it says so.
//!
//! ```text
//! shotlister-snapshot 1
//! D\t<device>\t<millis>\t<counter>                  the frontier, per device
//! R\t<id>\t<kind>                                   a record
//! F\t<field>\t<millis>\t<counter>\t<device>\t<value>  a field of the record above
//! Z\t<records>\t<fields>                            the end, with the counts
//! ```
//!
//! Records in id order and fields in name order, so the same state is always
//! the same text — two documents can be compared by their snapshots.

use crate::doc::Doc;
use crate::format::{decode_value, encode_value, escape, unescape, DecodeError};
use crate::id::Id;
use crate::stamp::{DeviceId, Stamp};
use crate::store::{Kind, Store};
use crate::value::Value;

pub const SNAPSHOT_HEADER: &str = "shotlister-snapshot";
/// Moves when the text above changes shape. A reader refuses any other
/// number, and the caller replays — nothing is lost, only the shortcut.
pub const SNAPSHOT_VERSION: u32 = 1;

const SEP: char = '\t';

impl Store {
    /// The whole state as text: every record, tombstones included, and the
    /// frontier. See the module note for the shape.
    pub fn snapshot(&self) -> String {
        let mut out = String::new();
        out.push_str(SNAPSHOT_HEADER);
        out.push(' ');
        out.push_str(&SNAPSHOT_VERSION.to_string());
        out.push('\n');

        for stamp in self.frontier() {
            out.push_str(&format!(
                "D{SEP}{}{SEP}{}{SEP}{}\n",
                stamp.device.0, stamp.millis, stamp.counter
            ));
        }

        let mut records = 0usize;
        let mut fields = 0usize;
        for record in self.all_records() {
            records += 1;
            out.push_str(&format!(
                "R{SEP}{}{SEP}{}\n",
                record.id.to_hex(),
                escape(record.kind.as_str())
            ));
            let mut held: Vec<(&str, &Value, Stamp)> = record.fields_with_stamps().collect();
            held.sort_by(|a, b| a.0.cmp(b.0));
            for (name, value, stamp) in held {
                // A value the log format cannot spell cannot be in a record:
                // every value here arrived through a log or was written by a
                // build that refuses nested lists. Skipping one would make a
                // snapshot that restores to a different film, so it is a
                // reason to give up on the whole text instead.
                let Ok(spelled) = encode_value(value) else {
                    return String::new();
                };
                fields += 1;
                out.push_str(&format!(
                    "F{SEP}{}{SEP}{}{SEP}{}{SEP}{}{SEP}{}\n",
                    escape(name),
                    stamp.millis,
                    stamp.counter,
                    stamp.device.0,
                    spelled
                ));
            }
        }
        out.push_str(&format!("Z{SEP}{records}{SEP}{fields}\n"));
        out
    }

    /// A store put back from `snapshot`'s text. **No change is applied**; the
    /// log is empty afterwards and the records and frontier are what they
    /// were. Anything the text gets wrong — a header this build does not
    /// know, a line it cannot read, a count that does not match, an end that
    /// never comes — is `Err`, and the caller replays.
    pub fn restore(text: &str) -> Result<Store, DecodeError> {
        let mut lines = text.lines();
        let header = lines.next().ok_or(DecodeError::MissingHeader)?;
        let (name, version) = header.split_once(' ').ok_or(DecodeError::MissingHeader)?;
        if name != SNAPSHOT_HEADER {
            return Err(DecodeError::MissingHeader);
        }
        let version = version
            .trim()
            .parse::<u32>()
            .map_err(|_| DecodeError::MissingHeader)?;
        if version != SNAPSHOT_VERSION {
            return Err(DecodeError::UnsupportedFormat(version));
        }

        let mut store = Store::new();
        let mut current: Option<(Id, Kind)> = None;
        let mut pending: Vec<(String, Value, Stamp)> = Vec::new();
        let mut records = 0usize;
        let mut fields = 0usize;
        let mut ended = false;

        for line in lines {
            if ended {
                // Nothing may follow the end. Text after it is not this
                // snapshot, and is not read.
                return Err(DecodeError::Malformed);
            }
            let parts: Vec<&str> = line.split(SEP).collect();
            match parts[0] {
                "D" => {
                    if parts.len() != 4 {
                        return Err(DecodeError::Malformed);
                    }
                    store.hear(stamp_of(parts[2], parts[3], parts[1])?);
                }
                "R" => {
                    if parts.len() != 3 {
                        return Err(DecodeError::Malformed);
                    }
                    if let Some((id, kind)) = current.take() {
                        store.restore_record(id, kind, pending.drain(..));
                    }
                    let id = Id::from_hex(parts[1]).ok_or(DecodeError::Malformed)?;
                    current = Some((id, Kind::parse(&unescape(parts[2])?)));
                    records += 1;
                }
                "F" => {
                    if parts.len() < 6 || current.is_none() {
                        return Err(DecodeError::Malformed);
                    }
                    let stamp = stamp_of(parts[2], parts[3], parts[4])?;
                    // The value carries no tabs, so the rest is one field.
                    let raw_value = parts[5..].join(&SEP.to_string());
                    pending.push((unescape(parts[1])?, decode_value(&raw_value)?, stamp));
                    fields += 1;
                }
                "Z" => {
                    if parts.len() != 3 {
                        return Err(DecodeError::Malformed);
                    }
                    let said_records: usize = parts[1].parse().map_err(|_| DecodeError::Malformed)?;
                    let said_fields: usize = parts[2].parse().map_err(|_| DecodeError::Malformed)?;
                    if said_records != records || said_fields != fields {
                        return Err(DecodeError::Malformed);
                    }
                    ended = true;
                }
                "" => {}
                _ => return Err(DecodeError::Unrecognised),
            }
        }
        if !ended {
            return Err(DecodeError::Malformed);
        }
        if let Some((id, kind)) = current.take() {
            store.restore_record(id, kind, pending.drain(..));
        }
        Ok(store)
    }
}

fn stamp_of(millis: &str, counter: &str, device: &str) -> Result<Stamp, DecodeError> {
    Ok(Stamp {
        millis: millis.parse().map_err(|_| DecodeError::Malformed)?,
        counter: counter.parse().map_err(|_| DecodeError::Malformed)?,
        device: DeviceId(device.parse().map_err(|_| DecodeError::Malformed)?),
    })
}

impl Doc {
    /// The document's state as text, for a reader to restore instead of
    /// replaying. See the module note.
    pub fn snapshot(&self) -> String {
        self.store().snapshot()
    }

    /// A document put back from a snapshot, as `device`, **having heard
    /// everything the snapshot covers**: the clock is advanced to the
    /// frontier, so the first change this document writes sorts after every
    /// change already in the film. Changes that arrived after the snapshot
    /// was taken are merged on top in the ordinary way.
    pub fn restore(device: DeviceId, text: &str) -> Result<Doc, DecodeError> {
        let store = Store::restore(text)?;
        let mut doc = Doc::new(device);
        for stamp in store.frontier() {
            doc.hear(&stamp);
        }
        doc.put_store(store);
        Ok(doc)
    }
}
