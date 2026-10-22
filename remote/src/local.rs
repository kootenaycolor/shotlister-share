//! Reading what this device already holds.
//!
//! The half of the courier that only ever *looks*: at the project folder, and
//! at the list, to answer "what have I got" and "what do I still need". No
//! network and nothing spawned, so it is as true on a phone as on a Mac —
//! which is the whole reason it is not next door in `courier`, where carrying
//! things means running `curl`.

use std::path::Path;

use shotlister_engine::doc::f;
use shotlister_engine::package;
use shotlister_storage::Project;

use crate::{Entry, Inventory};

/// The logs and the pictures in a project folder, as lengths.
///
/// Only what belongs to us is listed. A folder is a folder and somebody can
/// drop anything into it; carrying a stranger's file to the relay would be
/// presumptuous and is not what any of this is for.
pub fn local_inventory(path: &Path) -> Inventory {
    Inventory {
        logs: sizes(&path.join(package::CHANGES_DIR), |name| {
            package::log_parts(name).is_some() || package::device_mark_parts(name).is_some()
        }),
        media: sizes(&path.join(package::PROXY_DIR), |name| {
            // The shape the media folder writes: the hash's first 32
            // characters, then whatever it was stored as.
            match name.split_once('.') {
                Some((stem, ext)) => {
                    stem.len() == 32
                        && stem.chars().all(|c| c.is_ascii_hexdigit())
                        && !ext.is_empty()
                        && ext.len() <= 8
                }
                None => false,
            }
        }),
    }
}

/// **What every fold on this folder retired, and what it wrote over.** Ref 192.
///
/// One file per device, all of them read together: a log retired by one machine
/// is retired for the folder, and whichever device syncs next is the one that
/// should act on it.
///
/// A missing file is an empty record, which is the honest answer for a project
/// that has never been tidied.
pub fn folded(path: &Path) -> package::FoldRecord {
    let dir = path.join(package::CHANGES_DIR);
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return package::FoldRecord::default();
    };
    let mut all = package::FoldRecord::default();
    for entry in entries.filter_map(|entry| entry.ok()) {
        let name = entry.file_name().to_string_lossy().to_string();
        if !package::is_fold_record_name(&name) {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(entry.path()) else {
            continue;
        };
        let one = package::decode_fold_record(&text);
        all.retired.extend(one.retired);
        all.rewritten.extend(one.rewritten);
    }
    all.retired.sort();
    all.retired.dedup();
    all.rewritten.sort();
    all.rewritten.dedup();
    all.rewritten.retain(|name| !all.retired.contains(name));
    all
}

fn sizes(dir: &Path, keep: impl Fn(&str) -> bool) -> Vec<Entry> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut found: Vec<Entry> = entries
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            if !keep(&name) {
                return None;
            }
            let size = entry.metadata().ok()?.len();
            Some(Entry { name, size })
        })
        .collect();
    found.sort_by(|a, b| a.name.cmp(&b.name));
    found
}

/// The pictures this list points at and this device has not got.
///
/// Straight from `missing_media`, which is the engine's own answer to the same
/// question and already knows about the difference between a picture that was
/// deleted and one that simply has not arrived.
pub fn wanted_stems(project: &Project) -> Vec<String> {
    let mut wanted: Vec<String> = project
        .missing_media()
        .into_iter()
        .filter_map(|id| {
            let hash = project.doc().get(id)?.text(f::HASH)?;
            Some(hash.chars().take(32).collect::<String>())
        })
        .collect();
    // And the script: a revision's text and PDF travel with the pictures
    // since 2026-09-15, and a device that lacks them asks the same way.
    wanted.extend(project.missing_scripts());
    // And every current Print Frame the Mac baked (2026-10-16): a picture no
    // media record names, so without this no device ever fetched one.
    wanted.extend(project.missing_print_frames());
    wanted
}

