//! Reading a ZIP archive.
//!
//! Entries are found through the central directory rather than by walking local
//! headers, because a file written by another tool may put its sizes in a
//! trailing descriptor the local header does not have. The central directory
//! always knows.

use std::collections::HashMap;

use crate::import::inflate::{inflate, InflateError};

#[derive(Debug, PartialEq)]
pub enum ZipError {
    NotAnArchive,
    Truncated,
    UnsupportedMethod(u16),
    Corrupt,
}

impl From<InflateError> for ZipError {
    fn from(_: InflateError) -> ZipError {
        ZipError::Corrupt
    }
}

const CENTRAL_HEADER: u32 = 0x0201_4b50;
const END_OF_CENTRAL: u32 = 0x0605_4b50;

fn u16_at(data: &[u8], at: usize) -> Result<u16, ZipError> {
    Ok(u16::from_le_bytes([
        *data.get(at).ok_or(ZipError::Truncated)?,
        *data.get(at + 1).ok_or(ZipError::Truncated)?,
    ]))
}

fn u32_at(data: &[u8], at: usize) -> Result<u32, ZipError> {
    Ok(u32::from_le_bytes([
        *data.get(at).ok_or(ZipError::Truncated)?,
        *data.get(at + 1).ok_or(ZipError::Truncated)?,
        *data.get(at + 2).ok_or(ZipError::Truncated)?,
        *data.get(at + 3).ok_or(ZipError::Truncated)?,
    ]))
}

/// Every entry, by name, already decompressed.
pub struct Archive {
    entries: HashMap<String, Vec<u8>>,
}

impl Archive {
    pub fn get(&self, name: &str) -> Option<&[u8]> {
        self.entries.get(name).map(|bytes| bytes.as_slice())
    }

    pub fn text(&self, name: &str) -> Option<String> {
        self.get(name)
            .map(|bytes| String::from_utf8_lossy(bytes).into_owned())
    }

    pub fn names(&self) -> Vec<&str> {
        self.entries.keys().map(|name| name.as_str()).collect()
    }

    pub fn contains(&self, name: &str) -> bool {
        self.entries.contains_key(name)
    }
}

/// Read an archive whole. A shot list is small enough that streaming would buy
/// complexity and nothing else.
pub fn read(data: &[u8]) -> Result<Archive, ZipError> {
    // The end-of-central-directory record sits at the back, after a comment of
    // unknown length, so it has to be searched for.
    let mut end = None;
    let lower = data.len().saturating_sub(66_000);
    for at in (lower..data.len().saturating_sub(21)).rev() {
        if u32_at(data, at)? == END_OF_CENTRAL {
            end = Some(at);
            break;
        }
    }
    let end = end.ok_or(ZipError::NotAnArchive)?;

    let count = u16_at(data, end + 10)? as usize;
    let mut at = u32_at(data, end + 16)? as usize;

    let mut entries = HashMap::new();
    for _ in 0..count {
        if u32_at(data, at)? != CENTRAL_HEADER {
            return Err(ZipError::Corrupt);
        }
        let method = u16_at(data, at + 10)?;
        let compressed = u32_at(data, at + 20)? as usize;
        let name_length = u16_at(data, at + 28)? as usize;
        let extra_length = u16_at(data, at + 30)? as usize;
        let comment_length = u16_at(data, at + 32)? as usize;
        let local = u32_at(data, at + 42)? as usize;

        let name_bytes = data
            .get(at + 46..at + 46 + name_length)
            .ok_or(ZipError::Truncated)?;
        let name = String::from_utf8_lossy(name_bytes).into_owned();

        // The local header repeats the name and may carry a different extra
        // field, so its length has to be read again rather than assumed.
        let local_name = u16_at(data, local + 26)? as usize;
        let local_extra = u16_at(data, local + 28)? as usize;
        let from = local + 30 + local_name + local_extra;
        let raw = data
            .get(from..from + compressed)
            .ok_or(ZipError::Truncated)?;

        let bytes = match method {
            0 => raw.to_vec(),
            8 => inflate(raw)?,
            other => return Err(ZipError::UnsupportedMethod(other)),
        };

        // Directory entries are stored as zero-length names ending in a slash.
        if !name.ends_with('/') {
            entries.insert(name, bytes);
        }

        at += 46 + name_length + extra_length + comment_length;
    }

    Ok(Archive { entries })
}
