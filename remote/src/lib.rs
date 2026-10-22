//! What should move between this device and the relay.
//!
//! **It decides; it never does.** There is no HTTP client in here and that is
//! deliberate, not a gap. This crate works out *what* ought to be sent and
//! fetched; a shell then does it — `URLSession` on the Mac and the phone, which
//! is the only way to get transfers that survive the app going to the
//! background, and plain `curl` in a checking run.
//!
//! It is the same split that keeps the engine free of the file system, applied
//! once more: the decision is the part that can be wrong in an interesting way,
//! so it lives here where it can be tested without a server, a network, or a
//! film.
//!
//! ## The whole rule is "a log only ever grows"
//!
//! Every change log has exactly one writer for ever — that is what
//! `engine/src/package.rs` buys by putting the device and the session in the
//! name — and a writer only ever appends. So for any log **the longer copy is
//! the newer copy**, and comparing two numbers is a complete answer. No
//! hashing, no timestamps, no asking who wrote last.
//!
//! It is also why the two directions are one rule rather than two:
//!
//! - ours is longer → send it up
//! - theirs is longer → bring it down
//! - the same → there is nothing to do
//!
//! And why this device happily carries a log it did not write: a Mac that took
//! the phone's changes in over iCloud can push them onward, and the relay's own
//! "may only grow" rule makes that safe even if the phone pushes the same log
//! at the same moment.
//!
//! ## Media is named after its own contents
//!
//! So a name means one set of bytes for ever, and "do you have this?" is the
//! entire question. Nothing is ever re-uploaded, nothing is ever compared, and
//! an upload that was cut off halfway is safe to simply repeat.
//!
//! **Only the proxies travel.** The full-size originals stay where they are: a
//! per-device cache of the largest files in the project, which every device
//! currently drags down and none of them needs (Ref 332). The proxy is what
//! every screen and every export actually draws.

use std::collections::HashSet;

use shotlister_engine::json::{parse, Json};
use shotlister_engine::package;

#[cfg(feature = "courier")]
pub mod courier;
#[cfg(feature = "local")]
pub mod local;

/// A file the relay or the project holds, and how long it is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub size: u64,
}

impl Entry {
    pub fn new(name: impl Into<String>, size: u64) -> Entry {
        Entry {
            name: name.into(),
            size,
        }
    }
}

/// What one side holds.
#[derive(Clone, Debug, Default)]
pub struct Inventory {
    pub logs: Vec<Entry>,
    pub media: Vec<Entry>,
}

impl Inventory {
    fn log_size(&self, name: &str) -> Option<u64> {
        self.logs
            .iter()
            .find(|entry| entry.name == name)
            .map(|entry| entry.size)
    }

    fn media_names(&self) -> HashSet<&str> {
        self.media.iter().map(|entry| entry.name.as_str()).collect()
    }
}

/// What has to happen for the two sides to agree.
///
/// Four lists rather than a list of instructions, because the shell wants to
/// treat them differently: logs are tiny and go now, media is large and can go
/// in the background over a set day's bad signal.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Plan {
    pub upload_logs: Vec<String>,
    /// The subset of `upload_logs` that a fold wrote over, and which the relay
    /// must therefore be told to accept in place of what it holds. Ref 192.
    ///
    /// A separate list rather than a flag on each name because a carrier does
    /// one thing differently for these — it adds `?rewrite=1` — and because a
    /// list that is almost always empty says plainly that this is the rare case.
    pub rewrite_logs: Vec<String>,
    pub download_logs: Vec<String>,
    pub upload_media: Vec<String>,
    pub download_media: Vec<String>,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        self.upload_logs.is_empty()
            && self.download_logs.is_empty()
            && self.upload_media.is_empty()
            && self.download_media.is_empty()
    }

    /// How many files would move. What a progress bar counts.
    pub fn steps(&self) -> usize {
        self.upload_logs.len()
            + self.download_logs.len()
            + self.upload_media.len()
            + self.download_media.len()
    }

    /// Whether anything would arrive. The apps say *3 changes to push* and
    /// *something new to pull* separately, because they mean different things
    /// to somebody standing on a set.
    pub fn has_incoming(&self) -> bool {
        !self.download_logs.is_empty()
    }

    pub fn has_outgoing(&self) -> bool {
        !self.upload_logs.is_empty()
    }

    pub fn encode(&self) -> String {
        Json::object(vec![
            ("uploadLogs", strings(&self.upload_logs)),
            ("rewriteLogs", strings(&self.rewrite_logs)),
            ("downloadLogs", strings(&self.download_logs)),
            ("uploadMedia", strings(&self.upload_media)),
            ("downloadMedia", strings(&self.download_media)),
            ("steps", Json::Number(self.steps() as f64)),
        ])
        .encode()
    }
}

fn strings(list: &[String]) -> Json {
    Json::Array(list.iter().map(|name| Json::text(name.clone())).collect())
}

// ---- the decision ------------------------------------------------------

/// Which logs should move, and which way.
///
/// A name that is not one of ours is ignored on both sides. The relay refuses
/// them anyway, but a project folder is a folder somebody can drop a file into,
/// and a `.log` from something else is not ours to carry.
pub fn plan_logs(
    local: &Inventory,
    relay: &Inventory,
    folded: &package::FoldRecord,
) -> (Vec<String>, Vec<String>) {
    let mut up = Vec::new();
    let mut down = Vec::new();

    for entry in &local.logs {
        if !ours(&entry.name) {
            continue;
        }
        match relay.log_size(&entry.name) {
            None => up.push(entry.name.clone()),
            Some(there) if entry.size > there => up.push(entry.name.clone()),
            Some(_) => {}
        }
    }

    for entry in &relay.logs {
        if !ours(&entry.name) {
            continue;
        }
        // **A log this folder folded away is not missing, it is finished.**
        // Every change in it was written into the log that took its place, so
        // fetching it back adds nothing and undoes the tidying — and the next
        // launch would fold it in again, for ever. Ref 192.
        if folded.retired.contains(&entry.name) {
            continue;
        }
        // **And a log this device folded is not overwritten by the copy it
        // replaced.** "The longer copy is the newer copy" is true of a log that
        // only ever grows, and a fold is the one thing that breaks that: were
        // the relay's older copy the longer of the two, that rule would fetch
        // it back over the fold and undo it.
        if folded.rewritten.contains(&entry.name) && local.log_size(&entry.name).is_some() {
            continue;
        }
        match local.log_size(&entry.name) {
            None => down.push(entry.name.clone()),
            Some(here) if entry.size > here => down.push(entry.name.clone()),
            Some(_) => {}
        }
    }

    up.sort();
    down.sort();
    (up, down)
}

/// A change log, or the mark an installation leaves to say which device it is.
///
/// Marks matter as much as logs and are easy to forget: they are how two
/// machines writing under one name get noticed at all (Ref 186), and a warning
/// that only ever reaches the machine that already knew is no warning.
fn ours(name: &str) -> bool {
    package::log_parts(name).is_some() || package::device_mark_parts(name).is_some()
}

/// Which pictures should move.
///
/// `wanted` is the stems the list actually points at — from `missing_media`,
/// shortened the way the media folder names things. Everything else the relay
/// holds is left alone: a device fetches what it needs to draw, not the whole
/// film, which is the difference between opening a project on a phone in a
/// minute and in twenty.
pub fn plan_media(local: &Inventory, relay: &Inventory, wanted: &[String]) -> (Vec<String>, Vec<String>) {
    let there = relay.media_names();
    let here = local.media_names();

    let mut up: Vec<String> = local
        .media
        .iter()
        .filter(|entry| !there.contains(entry.name.as_str()))
        .map(|entry| entry.name.clone())
        .collect();

    let asked: HashSet<&str> = wanted.iter().map(|stem| stem.as_str()).collect();
    let mut down: Vec<String> = relay
        .media
        .iter()
        .filter(|entry| !here.contains(entry.name.as_str()))
        .filter(|entry| match entry.name.split_once('.') {
            Some((stem, _)) => asked.contains(stem),
            None => false,
        })
        .map(|entry| entry.name.clone())
        .collect();

    up.sort();
    down.sort();
    (up, down)
}

/// Everything, in one answer.
pub fn plan(
    local: &Inventory,
    relay: &Inventory,
    wanted: &[String],
    folded: &package::FoldRecord,
) -> Plan {
    let (upload_logs, download_logs) = plan_logs(local, relay, folded);
    let (upload_media, download_media) = plan_media(local, relay, wanted);
    let rewrite_logs = upload_logs
        .iter()
        .filter(|name| folded.rewritten.contains(name))
        .cloned()
        .collect();
    Plan {
        upload_logs,
        rewrite_logs,
        download_logs,
        upload_media,
        download_media,
    }
}

// ---- reading what the relay said ---------------------------------------

/// The relay's `/state` and `/media` replies, together.
///
/// Anything unreadable comes back as nothing held rather than as an error. That
/// is the safe direction: a relay that answered with rubbish leads to a device
/// that offers to send everything up, never to one that deletes or overwrites.
pub fn parse_state(state: &str, media: &str) -> Inventory {
    Inventory {
        logs: entries(state, "logs"),
        media: entries(media, "media"),
    }
}

fn entries(text: &str, key: &str) -> Vec<Entry> {
    let Some(root) = parse(text) else {
        return Vec::new();
    };
    let Some(list) = root.get(key).and_then(|found| found.as_array()) else {
        return Vec::new();
    };
    list.iter()
        .filter_map(|item| {
            let name = item.get("name")?.as_str()?.to_string();
            let size = item.get("size")?.as_f64()?;
            // A negative or absurd length is not a file; treat it as unreadable.
            if !(0.0..=(u64::MAX as f64)).contains(&size) {
                return None;
            }
            Some(Entry {
                name,
                size: size as u64,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: &str = "00000000000000aa-00000000000000b1.log";
    const B: &str = "00000000000000bb-00000000000000b2.log";
    const MARK: &str = "00000000000000aa-00000000000000c1.device";

    fn inv(logs: &[(&str, u64)], media: &[(&str, u64)]) -> Inventory {
        Inventory {
            logs: logs.iter().map(|(n, s)| Entry::new(*n, *s)).collect(),
            media: media.iter().map(|(n, s)| Entry::new(*n, *s)).collect(),
        }
    }

    /// A project nothing has ever folded.
    fn untouched() -> package::FoldRecord {
        package::FoldRecord::default()
    }

    #[test]
    fn the_same_length_means_the_same_bytes() {
        let local = inv(&[(A, 500)], &[]);
        let relay = inv(&[(A, 500)], &[]);
        assert_eq!(plan_logs(&local, &relay, &untouched()), (vec![], vec![]));
    }

    #[test]
    fn a_log_the_relay_has_never_seen_goes_up() {
        let local = inv(&[(A, 500)], &[]);
        let relay = inv(&[], &[]);
        assert_eq!(plan_logs(&local, &relay, &untouched()), (vec![A.to_string()], vec![]));
    }

    #[test]
    fn a_log_only_the_relay_has_comes_down() {
        let local = inv(&[], &[]);
        let relay = inv(&[(B, 90)], &[]);
        assert_eq!(plan_logs(&local, &relay, &untouched()), (vec![], vec![B.to_string()]));
    }

    #[test]
    fn the_longer_copy_is_the_newer_copy() {
        let local = inv(&[(A, 900), (B, 10)], &[]);
        let relay = inv(&[(A, 500), (B, 40)], &[]);
        let (up, down) = plan_logs(&local, &relay, &untouched());
        assert_eq!(up, vec![A.to_string()]);
        assert_eq!(down, vec![B.to_string()]);
    }

    /// **This device carries a log it did not write.** A Mac that took the
    /// phone's changes in over iCloud can push them onward, which is what keeps
    /// a phone that never reaches the relay from being a dead end.
    #[test]
    fn a_log_from_another_device_is_carried_too() {
        let local = inv(&[(B, 300)], &[]);
        let relay = inv(&[], &[]);
        assert_eq!(plan_logs(&local, &relay, &untouched()), (vec![B.to_string()], vec![]));
    }

    #[test]
    fn identity_marks_travel_like_logs() {
        let local = inv(&[(MARK, 0)], &[]);
        let relay = inv(&[], &[]);
        assert_eq!(plan_logs(&local, &relay, &untouched()), (vec![MARK.to_string()], vec![]));
    }

    /// **A log the fold retired is finished, not missing.** Without this the
    /// relay's copy comes straight back down, the next launch folds it in
    /// again, and the folder never gets tidier however often it is tidied.
    #[test]
    fn a_folded_away_log_is_not_fetched_back() {
        let local = inv(&[], &[]);
        let relay = inv(&[(A, 500)], &[]);
        let folded = package::FoldRecord {
            retired: vec![A.to_string()],
            rewritten: Vec::new(),
        };
        assert_eq!(plan_logs(&local, &relay, &folded), (vec![], vec![]));
    }

    /// Only the ones it names. A retired log is one name, not a licence to stop
    /// fetching.
    #[test]
    fn every_other_log_still_comes_down() {
        let local = inv(&[], &[]);
        let relay = inv(&[(A, 500), (B, 90)], &[]);
        let folded = package::FoldRecord {
            retired: vec![A.to_string()],
            rewritten: Vec::new(),
        };
        assert_eq!(
            plan_logs(&local, &relay, &folded),
            (vec![], vec![B.to_string()])
        );
    }

    /// The rule that a longer copy is a newer one is true of a log that only
    /// grows. A fold is the one thing that breaks it, so the copy it replaced
    /// must never come back over the top.
    #[test]
    fn the_copy_a_fold_replaced_is_not_fetched_back_over_it() {
        let local = inv(&[(A, 90)], &[]);
        let relay = inv(&[(A, 500)], &[]);
        let folded = package::FoldRecord {
            retired: Vec::new(),
            rewritten: vec![A.to_string()],
        };
        assert_eq!(plan_logs(&local, &relay, &folded), (vec![], vec![]));
    }

    /// But a device that has never had it still gets it. A fold on one machine
    /// is not a reason for another to go without.
    #[test]
    fn a_folded_log_this_device_lacks_still_comes_down() {
        let local = inv(&[], &[]);
        let relay = inv(&[(A, 500)], &[]);
        let folded = package::FoldRecord {
            retired: Vec::new(),
            rewritten: vec![A.to_string()],
        };
        assert_eq!(
            plan_logs(&local, &relay, &folded),
            (vec![], vec![A.to_string()])
        );
    }

    /// **The log a fold wrote over says so on its way up.** The relay refuses a
    /// rewrite unless it is asked for, and that refusal used to stop the run.
    #[test]
    fn a_rewritten_log_is_marked_as_one() {
        let local = inv(&[(A, 900), (B, 90)], &[]);
        let relay = inv(&[(A, 500)], &[]);
        let folded = package::FoldRecord {
            retired: Vec::new(),
            rewritten: vec![A.to_string()],
        };
        let plan = plan(&local, &relay, &[], &folded);
        assert_eq!(plan.upload_logs, vec![A.to_string(), B.to_string()]);
        assert_eq!(plan.rewrite_logs, vec![A.to_string()]);
    }

    /// A fold from a year ago is not a standing permission. Nothing is sent, so
    /// nothing is marked.
    #[test]
    fn a_rewrite_that_is_not_being_sent_is_not_marked() {
        let local = inv(&[(A, 500)], &[]);
        let relay = inv(&[(A, 500)], &[]);
        let folded = package::FoldRecord {
            retired: Vec::new(),
            rewritten: vec![A.to_string()],
        };
        let plan = plan(&local, &relay, &[], &folded);
        assert!(plan.upload_logs.is_empty());
        assert!(plan.rewrite_logs.is_empty());
    }

    #[test]
    fn somebody_elses_file_is_left_alone() {
        let local = inv(&[("notes.log", 20), ("readme.txt", 5)], &[]);
        let relay = inv(&[("whatever.log", 9)], &[]);
        assert_eq!(plan_logs(&local, &relay, &untouched()), (vec![], vec![]));
    }

    #[test]
    fn a_picture_the_relay_lacks_goes_up() {
        let stem = "a".repeat(32);
        let local = inv(&[], &[(&format!("{stem}.jpg"), 100)]);
        let relay = inv(&[], &[]);
        let (up, down) = plan_media(&local, &relay, &[]);
        assert_eq!(up, vec![format!("{stem}.jpg")]);
        assert!(down.is_empty());
    }

    /// A device fetches what it needs to draw, not the whole film.
    #[test]
    fn only_the_pictures_the_list_points_at_come_down() {
        let wanted = "b".repeat(32);
        let ignored = "c".repeat(32);
        let local = inv(&[], &[]);
        let relay = inv(
            &[],
            &[(&format!("{wanted}.jpg"), 10), (&format!("{ignored}.jpg"), 10)],
        );
        let (_, down) = plan_media(&local, &relay, &[wanted.clone()]);
        assert_eq!(down, vec![format!("{wanted}.jpg")]);
    }

    /// A clip is two files under one stem. Both are wanted, and asking for the
    /// stem has to bring both — the movie is useless without the still that
    /// stands for it in a table, and the still alone will not play.
    #[test]
    fn a_clip_brings_its_poster_with_it() {
        let stem = "d".repeat(32);
        let local = inv(&[], &[]);
        let relay = inv(
            &[],
            &[(&format!("{stem}.mp4"), 900), (&format!("{stem}.png"), 30)],
        );
        let (_, down) = plan_media(&local, &relay, &[stem.clone()]);
        assert_eq!(down, vec![format!("{stem}.mp4"), format!("{stem}.png")]);
    }

    #[test]
    fn a_picture_already_here_is_not_fetched_again() {
        let stem = "e".repeat(32);
        let name = format!("{stem}.jpg");
        let local = inv(&[], &[(&name, 100)]);
        let relay = inv(&[], &[(&name, 100)]);
        let (up, down) = plan_media(&local, &relay, &[stem]);
        assert!(up.is_empty());
        assert!(down.is_empty());
    }

    #[test]
    fn nothing_to_do_is_reported_as_nothing() {
        let both = inv(&[(A, 12)], &[]);
        assert!(plan(&both, &both, &[], &untouched()).is_empty());
    }

    #[test]
    fn the_relays_answer_is_read() {
        let state = format!("{{\"project\":\"ab\",\"logs\":[{{\"name\":\"{A}\",\"size\":512}}]}}");
        let media = "{\"media\":[{\"name\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg\",\"size\":9}]}";
        let held = parse_state(&state, media);
        assert_eq!(held.logs, vec![Entry::new(A, 512)]);
        assert_eq!(held.media.len(), 1);
    }

    /// Rubbish from the relay must never read as "the project is empty" — that
    /// is the answer that would look like everything having been deleted.
    #[test]
    fn an_unreadable_answer_holds_nothing_rather_than_lying() {
        let held = parse_state("<html>502 Bad Gateway</html>", "");
        assert!(held.logs.is_empty());
        assert!(held.media.is_empty());
        // And so nothing is proposed for deletion, because nothing ever is.
        let local = inv(&[(A, 40)], &[]);
        let plan = plan(&local, &held, &[], &untouched());
        assert_eq!(plan.upload_logs, vec![A.to_string()]);
        assert!(plan.download_logs.is_empty());
    }
}
