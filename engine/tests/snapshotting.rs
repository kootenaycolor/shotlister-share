//! A document put back from a snapshot is the document that was replayed.
//!
//! The worker on the hub replays every change log of a film before answering
//! anything. A snapshot is the state saved after that replay, so the next
//! request restores it and applies only what is new. These prove the two ways
//! of arriving at a film cannot be told apart — in what is drawn, in what the
//! records hold, and in what the clock has heard.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use shotlister_engine::doc::f;
use shotlister_engine::format::{decode_log, encode_log, DecodeError};
use shotlister_engine::snapshot::{SNAPSHOT_HEADER, SNAPSHOT_VERSION};
use shotlister_engine::view::{self, Asked, Standing};
use shotlister_engine::{DeviceId, Doc, Stamp, Watermark, FORMAT_VERSION};

fn daybreak() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../studio/fixtures/Daybreak.shotlist/changes")
}

/// A film's logs, in name order — the order the hub feeds them in.
fn logs_in(folder: &Path) -> Vec<String> {
    let mut names: Vec<PathBuf> = fs::read_dir(folder)
        .expect("the fixture is there")
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().map(|e| e == "log").unwrap_or(false))
        .collect();
    names.sort();
    names.into_iter().map(|p| fs::read_to_string(p).unwrap()).collect()
}

fn replayed(device: DeviceId, logs: &[String]) -> Doc {
    let mut doc = Doc::new(device);
    for log in logs {
        doc.merge(decode_log(log).expect("a readable log").changes);
    }
    doc
}

fn drawn(doc: &Doc) -> String {
    view::describe(
        doc,
        &Asked::default().looking(),
        &Standing {
            read_only: true,
            unsaved: 0,
            device_clash: None,
        },
    )
}

const READER: DeviceId = DeviceId(0x1);

#[test]
fn restored_daybreak_is_replayed_daybreak() {
    let logs = logs_in(&daybreak());
    let whole = replayed(READER, &logs);

    let text = whole.snapshot();
    assert!(text.starts_with(&format!("{SNAPSHOT_HEADER} {SNAPSHOT_VERSION}\n")));
    let back = Doc::restore(READER, &text).expect("restores");

    assert_eq!(drawn(&back), drawn(&whole), "the same film is drawn");
    assert_eq!(
        back.store().fingerprint(),
        whole.store().fingerprint(),
        "every record holds the same values"
    );
    assert_eq!(back.store().frontier(), whole.store().frontier(), "the same devices heard, as far");
    assert_eq!(back.snapshot(), text, "a restored film saves as the same text");
    assert!(back.changes().is_empty(), "nothing was applied to get there");
}

#[test]
fn restored_plus_the_tail_is_the_whole() {
    let logs = logs_in(&daybreak());
    assert!(logs.len() >= 3, "the fixture has several logs");
    let whole = replayed(READER, &logs);

    // A snapshot of the film before its last two logs existed, then the two
    // arriving on top — a new log, and the end of one that grew.
    let (early, late) = logs.split_at(logs.len() - 2);
    let saved = replayed(READER, early).snapshot();
    let mut back = Doc::restore(READER, &saved).expect("restores");
    for log in late {
        back.merge(decode_log(log).unwrap().changes);
    }
    assert_eq!(drawn(&back), drawn(&whole));
    assert_eq!(back.store().fingerprint(), whole.store().fingerprint());
    assert_eq!(back.store().frontier(), whole.store().frontier());
}

#[test]
fn a_grown_log_is_taken_in_from_where_it_was() {
    // The hub hands the engine the *tail* of a log that grew — the bytes after
    // the length the snapshot covered — under the log's own header. Prove
    // that lands the same as the whole log would.
    let logs = logs_in(&daybreak());
    let biggest = logs.iter().max_by_key(|l| l.len()).unwrap().clone();
    let lines: Vec<&str> = biggest.lines().collect();
    assert!(lines.len() > 20, "a log worth cutting");
    let cut_at = lines.len() / 2;
    let head_text = format!("{}\n", lines[..cut_at].join("\n"));
    let tail_text = format!("{}\n", lines[cut_at..].join("\n"));
    assert_eq!(format!("{head_text}{tail_text}"), biggest, "the cut loses nothing");

    let whole = replayed(READER, &[biggest.clone()]);

    let saved = replayed(READER, &[head_text]).snapshot();
    let mut back = Doc::restore(READER, &saved).unwrap();
    let header = lines[0];
    back.merge(decode_log(&format!("{header}\n{tail_text}")).unwrap().changes);

    assert_eq!(drawn(&back), drawn(&whole));
    assert_eq!(back.store().fingerprint(), whole.store().fingerprint());
    assert_eq!(back.store().frontier(), whole.store().frontier());
}

#[test]
fn a_restored_document_has_heard_everything() {
    // Two devices. B writes a field; A overwrites it later. B's stamp is on no
    // record any more — only the frontier remembers it. A third device that
    // restores the snapshot and writes must still claim to have heard B, or
    // every write it makes reads as a clash with B on the Mac.
    let mut b = Doc::new(DeviceId(0xB));
    let project = b.create_project("Clash");
    b.set(project, f::DIRECTOR, "from B");
    let mut a = Doc::new(DeviceId(0xA));
    a.merge(b.changes().to_vec());
    a.set(project, f::DIRECTOR, "from A");

    let mut replayed_c = Doc::new(DeviceId(0xC));
    replayed_c.merge(a.changes().to_vec());
    let mut restored_c = Doc::restore(DeviceId(0xC), &replayed_c.snapshot()).unwrap();

    replayed_c.set(project, f::DIRECTOR, "from C, replayed");
    restored_c.set(project, f::DIRECTOR, "from C, restored");

    let last = |doc: &Doc| doc.changes().last().unwrap().clone();
    let (on_replay, on_restore) = (last(&replayed_c), last(&restored_c));
    assert_eq!(
        on_restore.seen, on_replay.seen,
        "the write claims exactly what a replayed device's would"
    );
    let b_stamp = b.changes().last().unwrap().stamp;
    let a_stamp = a.changes().last().unwrap().stamp;
    assert!(on_restore.seen.covers(&b_stamp, DeviceId(0xC)), "heard B, whose write lost");
    assert!(on_restore.seen.covers(&a_stamp, DeviceId(0xC)), "heard A, whose write won");
    assert!(
        on_restore.stamp > a_stamp && on_restore.stamp > b_stamp,
        "the write sorts after everything in the film"
    );
    assert!(matches!(on_restore.seen, Watermark::Heard(_)));

    // And the Mac, merging that write, sees no clash.
    a.merge(restored_c.changes().to_vec());
    assert!(a.store().clashes().is_empty(), "no clash is reported: {:?}", a.store().clashes());
}

#[test]
fn a_tombstone_survives_the_round_trip() {
    let mut d = Doc::new(DeviceId(0xA));
    d.create_project("Gone");
    let scene = d.create_scene("1");
    let (shot, _placement) = d.add_shot_to_scene(scene);
    d.delete(shot);
    let back = Doc::restore(DeviceId(0xA), &d.snapshot()).unwrap();
    assert!(back.get(shot).is_none(), "still deleted");
    assert!(back.store().get_raw(shot).is_some(), "the tombstone is held, not dropped");

    // An older write to the deleted record arriving after the restore still
    // loses, because the tombstone kept its stamp.
    let old_stamp = Stamp {
        millis: 1,
        counter: 0,
        device: DeviceId(0xB),
    };
    let mut late = back;
    late.merge(vec![shotlister_engine::Change::new(
        old_stamp,
        shotlister_engine::Op::Set {
            id: shot,
            field: "deleted".to_string(),
            value: shotlister_engine::Value::Bool(false),
        },
    )]);
    assert!(late.get(shot).is_none(), "an older undelete does not bring it back");
}

#[test]
fn a_snapshot_it_cannot_trust_is_refused_whole() {
    let logs = logs_in(&daybreak());
    let text = replayed(READER, &logs).snapshot();

    // Cut short: no end line.
    let cut = &text[..text.len() / 2];
    assert!(Doc::restore(READER, cut).is_err(), "a truncated snapshot is refused");

    // Another build's version.
    let newer = text.replacen(
        &format!("{SNAPSHOT_HEADER} {SNAPSHOT_VERSION}"),
        &format!("{SNAPSHOT_HEADER} {}", SNAPSHOT_VERSION + 1),
        1,
    );
    assert_eq!(
        Doc::restore(READER, &newer).err(),
        Some(DecodeError::UnsupportedFormat(SNAPSHOT_VERSION + 1))
    );

    // A line it does not know — a log would keep it; a snapshot gives up.
    let strange = text.replacen("\nR\t", "\nQ\tsomething\nR\t", 1);
    assert_eq!(Doc::restore(READER, &strange).err(), Some(DecodeError::Unrecognised));

    // Not a snapshot at all.
    assert!(Doc::restore(READER, "").is_err());
    assert!(Doc::restore(READER, &encode_log(FORMAT_VERSION, &[], &[])).is_err());

    // Counts that disagree with what came before them.
    let miscounted = text.replacen("\nF\t", "\nF\tstray\t1\t0\t1\tn\nF\t", 1);
    assert!(Doc::restore(READER, &miscounted).is_err());
}

/// How long each road takes, said out loud (`--nocapture`). Nothing is
/// asserted about time; the numbers are for deciding, not for the battery.
#[test]
fn how_long_each_road_takes() {
    let mut films: Vec<(String, PathBuf)> = vec![("Daybreak".to_string(), daybreak())];
    if let Some(home) = std::env::var_os("HOME") {
        let his = Path::new(&home).join("Documents/Shotlister");
        if let Ok(entries) = fs::read_dir(&his) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map(|e| e == "shotlist").unwrap_or(false) {
                    let name = path.file_stem().unwrap().to_string_lossy().to_string();
                    films.push((name, path.join("changes")));
                }
            }
        }
    }
    for (name, folder) in films {
        if !folder.is_dir() {
            continue;
        }
        let logs = logs_in(&folder);
        let changes: usize = logs.iter().map(|l| decode_log(l).unwrap().changes.len()).sum();
        let runs = 20;

        let started = Instant::now();
        for _ in 0..runs {
            let doc = replayed(READER, &logs);
            std::hint::black_box(&doc);
        }
        let replay = started.elapsed() / runs;

        let whole = replayed(READER, &logs);
        let folded = encode_log(FORMAT_VERSION, whole.changes(), &[]);
        let started = Instant::now();
        for _ in 0..runs {
            let doc = replayed(READER, std::slice::from_ref(&folded));
            std::hint::black_box(&doc);
        }
        let fold = started.elapsed() / runs;

        let started = Instant::now();
        for _ in 0..runs {
            std::hint::black_box(whole.snapshot());
        }
        let save = started.elapsed() / runs;

        let text = whole.snapshot();
        let started = Instant::now();
        for _ in 0..runs {
            let doc = Doc::restore(READER, &text).unwrap();
            std::hint::black_box(&doc);
        }
        let restore = started.elapsed() / runs;

        let fields = text.lines().filter(|l| l.starts_with("F\t")).count();
        eprintln!(
            "{name}: {} logs, {changes} changes, {} bytes of log → snapshot {} bytes, {fields} fields\n  \
             replay {replay:?} · folded log {fold:?} · save {save:?} · restore {restore:?}",
            logs.len(),
            logs.iter().map(|l| l.len()).sum::<usize>(),
            text.len(),
        );
    }
}
