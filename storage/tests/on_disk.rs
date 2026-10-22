//! Projects on disk: opening, saving, and not losing anything on the way.

use std::fs;
use std::path::PathBuf;

use shotlister_engine::doc::f;
use shotlister_engine::package;
use shotlister_engine::{sha256, DeviceId, MediaKind};
use shotlister_storage as storage;

/// A directory of its own per test, cleaned up afterwards.
struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Scratch {
        let path = std::env::temp_dir().join(format!("shotlister-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("scratch");
        Scratch(path)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

// ---- creating and reopening --------------------------------------------

#[test]
fn a_new_project_is_a_folder_with_everything_in_its_place() {
    let scratch = Scratch::new("create");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");

    assert!(project.path().ends_with("Daybreak.shotlist"));
    assert!(project.path().join(package::MANIFEST).exists());
    assert!(project.path().join(package::CHANGES_DIR).is_dir());
    assert!(project.path().join(package::PROXY_DIR).is_dir());
    assert_eq!(project.manifest().title, "Daybreak");
    // A brand new project has nothing to undo.
    assert!(!project.doc().can_undo());
}

#[test]
fn a_list_survives_being_closed_and_opened() {
    let scratch = Scratch::new("reopen");
    let path = {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        let scene = project.doc_mut().create_scene("34");
        project.doc_mut().set(scene, f::LOCATION, "car");
        let (shot, _) = project.doc_mut().add_shot_to_scene(scene);
        project.doc_mut().set_vocab_field(shot, "lens", "37mm");
        project.save().expect("saves");
        project.path().to_path_buf()
    };

    let reopened = storage::open(&path, DeviceId(1)).expect("opens");
    let doc = reopened.doc();
    let scene = doc.scenes_in_order()[0];

    assert_eq!(doc.get(scene).unwrap().text(f::LOCATION), Some("car"));
    assert_eq!(doc.display_number(doc.placements_in_scene(scene)[0]).unwrap(), "34A");
    assert_eq!(doc.vocabulary("lens"), vec!["37mm"]);
    // Last week's work is not this session's to undo.
    assert!(!reopened.doc().can_undo());
}

#[test]
fn saving_appends_rather_than_rewriting() {
    let scratch = Scratch::new("append");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    project.doc_mut().create_scene("34");
    project.save().expect("saves");

    let log = fs::read_dir(project.path().join(package::CHANGES_DIR))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let first = fs::read_to_string(&log).unwrap();

    project.doc_mut().create_scene("35");
    project.save().expect("saves");
    let second = fs::read_to_string(&log).unwrap();

    // Everything written before is still there, byte for byte, at the front.
    assert!(second.starts_with(&first));
    assert!(second.len() > first.len());
}

#[test]
fn saving_twice_with_nothing_in_between_writes_nothing() {
    let scratch = Scratch::new("nochange");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    project.doc_mut().create_scene("34");
    project.save().expect("saves");

    let log = fs::read_dir(project.path().join(package::CHANGES_DIR))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let before = fs::read_to_string(&log).unwrap();

    assert!(!project.has_unsaved());
    project.save().expect("saves");

    assert_eq!(fs::read_to_string(&log).unwrap(), before);
}

#[test]
fn unsaved_work_is_countable() {
    let scratch = Scratch::new("unsaved");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    assert!(!project.has_unsaved());

    project.doc_mut().create_scene("34");
    assert!(project.has_unsaved());

    project.save().expect("saves");
    assert!(!project.has_unsaved());
}

// ---- two devices, one folder -------------------------------------------

#[test]
fn two_devices_write_to_their_own_logs_and_both_survive() {
    let scratch = Scratch::new("twodevices");
    let path = {
        let mut mac = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        mac.doc_mut().create_scene("34");
        mac.save().expect("saves");
        mac.path().to_path_buf()
    };

    // The phone opens the same folder and adds its own work.
    {
        let mut phone = storage::open(&path, DeviceId(2)).expect("opens");
        phone.doc_mut().create_scene("35");
        phone.save().expect("saves");
    }

    let logs: Vec<_> = fs::read_dir(path.join(package::CHANGES_DIR))
        .unwrap()
        .filter_map(|entry| entry.ok())
        .collect();
    assert_eq!(logs.len(), 2, "one log per device per session");

    // And whoever opens it next sees both.
    let both = storage::open(&path, DeviceId(3)).expect("opens");
    assert_eq!(both.doc().scenes_in_order().len(), 2);
}

// ---- refusing rather than guessing -------------------------------------

#[test]
fn a_project_from_a_newer_build_is_refused_with_something_to_do() {
    let scratch = Scratch::new("future");
    let path = {
        let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.path().to_path_buf()
    };
    // As if a later version had written it.
    let manifest = fs::read_to_string(path.join(package::MANIFEST)).unwrap();
    fs::write(
        path.join(package::MANIFEST),
        manifest.replace("\"format\": 1", "\"format\": 99"),
    )
    .unwrap();

    let message = match storage::open(&path, DeviceId(1)) {
        Ok(_) => panic!("a project from the future should not open"),
        Err(error) => error.message(),
    };
    assert!(message.contains("newer version"), "{message}");
    assert!(message.contains("Update"), "{message}");
}

#[test]
fn a_folder_that_is_not_a_project_is_refused_cleanly() {
    let scratch = Scratch::new("notaproject");
    let message = match storage::open(&scratch.0, DeviceId(1)) {
        Ok(_) => panic!("an ordinary folder is not a project"),
        Err(error) => error.message(),
    };
    assert!(message.contains("could not be read"), "{message}");
}

#[test]
fn a_line_this_build_cannot_read_is_written_back_out() {
    let scratch = Scratch::new("preserve");
    let path = {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.doc_mut().create_scene("34");
        project.save().expect("saves");
        project.path().to_path_buf()
    };

    // Something a later build wrote and this one has never heard of.
    let log = fs::read_dir(path.join(package::CHANGES_DIR))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let from_the_future =
        "1700000000000\t0\t99\tX\t000000000000000000000000000f00d5\tsomething";
    fs::write(
        &log,
        format!("{}{from_the_future}\n", fs::read_to_string(&log).unwrap()),
    )
    .unwrap();

    // This build opens it, works, and saves.
    {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene("35");
        project.save().expect("saves");
    }

    // The line it could not read is still in the project somewhere.
    let all: String = fs::read_dir(path.join(package::CHANGES_DIR))
        .unwrap()
        .filter_map(|entry| entry.ok())
        .map(|entry| fs::read_to_string(entry.path()).unwrap_or_default())
        .collect();
    assert!(all.contains(from_the_future), "an older build must not be why work disappears");
}

#[test]
fn a_session_that_edited_nothing_leaves_no_file_behind() {
    let scratch = Scratch::new("idle");
    let path;
    {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        let scene = project.doc_mut().create_scene("34");
        project.doc_mut().add_shot_to_scene(scene);
        project.save().expect("saves");
        path = project.path().to_path_buf();
    }
    let diaries = || -> usize {
        fs::read_dir(path.join("changes"))
            .map(|listing| listing.flatten().count())
            .unwrap_or(0)
    };
    let after_work = diaries();
    assert!(after_work >= 1, "the session that did something wrote it down");

    // Open it three more times and change nothing — looking something up,
    // which is the commonest thing anybody does with a project.
    for _ in 0..3 {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        assert!(!project.doc().scenes_in_order().is_empty(), "it read the work");
        project.save().expect("saves");
    }
    assert_eq!(
        diaries(),
        after_work,
        "opening a project and changing nothing must not leave a diary behind"
    );

    // And a session that *does* edit still writes one.
    {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene("35");
        project.save().expect("saves");
    }
    assert!(
        diaries() > after_work,
        "a session that changed something still writes it down"
    );

    // What it wrote is really there on the next open, which is the thing an
    // over-eager "write nothing" would break.
    let again = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(again.doc().scenes_in_order().len(), 2, "both scenes came back");
}

// ---- media -------------------------------------------------------------

#[test]
fn media_is_filed_and_found_by_its_contents() {
    let scratch = Scratch::new("media");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");

    let bytes = b"a frame, pretend";
    let hash = sha256(bytes).to_hex();
    project.write_proxy(&hash, "png", bytes).expect("writes");

    assert_eq!(
        project.read_proxy(&hash, "png").expect("reads").as_deref(),
        Some(bytes.as_slice())
    );
    // A frame nobody has stored is simply absent, not an error.
    let missing = sha256(b"never seen").to_hex();
    assert!(project.read_proxy(&missing, "png").expect("reads").is_none());

    // And the engine agrees about where it went.
    let scene = project.doc_mut().create_scene("34");
    let (shot, _) = project.doc_mut().add_shot_to_scene(scene);
    let media = project.doc_mut().add_media(
        sha256(bytes),
        MediaKind::Image,
        1600,
        900,
        bytes.len() as u64,
        "frame.png",
    );
    project.doc_mut().attach_media(shot, media, "");
    assert_eq!(project.doc().media_of(shot), vec![media]);
}

#[test]
fn a_clip_is_found_before_the_still_that_stands_for_it() {
    let scratch = Scratch::new("poster");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");

    // A clip is stored twice under one name: the movie, and the poster drawn
    // wherever a picture is wanted. Which one a folder listing hands back
    // first is not defined, so this used to be a coin toss — and a player
    // given a poster draws a black rectangle.
    let movie = b"the clip itself";
    let hash = sha256(movie).to_hex();
    project.write_proxy(&hash, "mp4", movie).expect("writes");
    project.write_proxy(&hash, "png", b"the poster").expect("writes");

    // Nobody said what they wanted: the moving picture wins, because the still
    // is only ever a stand-in for it.
    let (ext, bytes) = project.find_proxy(&hash, None).expect("reads").expect("found");
    assert_eq!(ext, "mp4", "asking for a clip must not hand back its poster");
    assert_eq!(bytes, movie);

    // Somebody said what they wanted: they get it, either way round.
    let (ext, bytes) = project
        .find_proxy(&hash, Some("png"))
        .expect("reads")
        .expect("found");
    assert_eq!(ext, "png", "a caller that asked for the poster gets the poster");
    assert_eq!(bytes, b"the poster");
    let (ext, _) = project
        .find_proxy(&hash, Some("mp4"))
        .expect("reads")
        .expect("found");
    assert_eq!(ext, "mp4");

    // An extension nobody stored is a hint that missed, not an error: fall
    // back to the same preference as saying nothing at all.
    let (ext, _) = project
        .find_proxy(&hash, Some("mov"))
        .expect("reads")
        .expect("found");
    assert_eq!(ext, "mp4");

    // The same again with a clip whose extension sorts *after* the poster's,
    // so alphabetical order alone would hand back the still. Without the
    // moving-beats-still rule this is the assertion that fails.
    let other = b"a second clip";
    let second = sha256(other).to_hex();
    project.write_proxy(&second, "webm", other).expect("writes");
    project.write_proxy(&second, "png", b"its poster").expect("writes");
    let (ext, bytes) = project
        .find_proxy(&second, None)
        .expect("reads")
        .expect("found");
    assert_eq!(ext, "webm", "a clip must win even when its name sorts last");
    assert_eq!(bytes, other);

    // A lone photograph is still found, preference or not.
    let photo = b"a still on its own";
    let only = sha256(photo).to_hex();
    project.write_proxy(&only, "png", photo).expect("writes");
    let (ext, bytes) = project.find_proxy(&only, None).expect("reads").expect("found");
    assert_eq!((ext.as_str(), bytes.as_slice()), ("png", photo.as_slice()));
}

#[test]
fn dropping_an_original_keeps_the_proxy() {
    let scratch = Scratch::new("evict");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let hash = sha256(b"big file").to_hex();

    project.write_proxy(&hash, "jpg", b"small").expect("writes");
    project.write_original(&hash, "jpg", b"large").expect("writes");
    project.evict_original(&hash, "jpg").expect("evicts");

    // Losing the picture entirely would be worse than losing the resolution.
    assert!(project.read_original(&hash, "jpg").expect("reads").is_none());
    assert_eq!(
        project.read_proxy(&hash, "jpg").expect("reads").as_deref(),
        Some(b"small".as_slice())
    );
    // Evicting something already gone is not a failure.
    project.evict_original(&hash, "jpg").expect("evicts again");
}

#[test]
fn the_manifest_keeps_up_with_the_title() {
    let scratch = Scratch::new("retitle");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let id = project.doc().project_id().unwrap();
    project.doc_mut().set(id, f::TITLE, "Daybreak (final)");
    project.refresh_manifest().expect("writes");

    let text = fs::read_to_string(project.path().join(package::MANIFEST)).unwrap();
    assert!(text.contains("Daybreak (final)"));
}

// ---- keeping the originals inside a budget -------------------------------

#[test]
fn originals_are_dropped_least_recently_used_first_and_proxies_never() {
    let scratch = Scratch::new("prune");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");

    // Three originals of a hundred kilobytes each, and a proxy for one of them.
    let big = vec![0u8; 100_000];
    let hashes: Vec<String> = (0..3)
        .map(|n| shotlister_engine::sha256(format!("frame {n}").as_bytes()).to_hex())
        .collect();
    for hash in &hashes {
        project.write_original(hash, "png", &big).expect("writes");
    }
    project.write_proxy(&hashes[0], "png", b"a small proxy").expect("writes");

    assert!(project.originals_bytes() >= 300_000);

    // Room for two of them.
    let freed = project.prune_originals(250_000).expect("prunes");

    assert!(freed >= 100_000, "something was dropped: {freed}");
    assert!(
        project.originals_bytes() <= 250_000,
        "and what is left fits: {}",
        project.originals_bytes()
    );
    assert!(
        project.read_proxy(&hashes[0], "png").expect("reads").is_some(),
        "a proxy is never touched — every device keeps all of them"
    );
}

#[test]
fn a_budget_big_enough_drops_nothing() {
    let scratch = Scratch::new("prune-none");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let hash = shotlister_engine::sha256(b"a frame").to_hex();
    project.write_original(&hash, "png", &vec![0u8; 1000]).expect("writes");

    assert_eq!(project.prune_originals(10_000_000).expect("prunes"), 0);
    assert!(project.read_original(&hash, "png").expect("reads").is_some());
}

/// **The manifest follows the title, by itself.**
///
/// It was written once when the project was made and never again, so a film
/// renamed afterwards kept its old name inside while its folder said otherwise.
/// Found through the MCP, which reads the manifest rather than the list.
#[test]
fn renaming_a_project_reaches_the_manifest_on_the_next_save() {
    let scratch = Scratch::new("manifest-follows");
    let mut project =
        storage::create(&scratch.0, "Untitled 2", DeviceId(1)).expect("made");
    assert_eq!(project.manifest().title, "Untitled 2");

    let id = project.doc().project_id().expect("a project record");
    project
        .doc_mut()
        .set(id, f::TITLE, shotlister_engine::Value::text("Call Her Back"));
    project.save().expect("saves");

    assert_eq!(project.manifest().title, "Call Her Back");
    let written = std::fs::read_to_string(project.path().join(package::MANIFEST)).expect("read");
    assert!(written.contains("Call Her Back"), "{written}");
    assert!(!written.contains("Untitled 2"), "{written}");
}

/// And an ordinary save does not rewrite it — the manifest is touched only when
/// it has actually fallen behind.
#[test]
fn a_save_that_changes_no_title_leaves_the_manifest_alone() {
    let scratch = Scratch::new("manifest-quiet");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("made");
    project.save().expect("saves");
    let before = std::fs::metadata(project.path().join(package::MANIFEST))
        .and_then(|m| m.modified())
        .expect("stamped");

    let scene = project.doc_mut().create_scene("7");
    let _ = scene;
    project.save().expect("saves again");

    let after = std::fs::metadata(project.path().join(package::MANIFEST))
        .and_then(|m| m.modified())
        .expect("stamped");
    assert_eq!(before, after, "the manifest was rewritten for nothing");
}

// ---------------------------------------------------------------------------
// A crash mid-write must not leave a file broken for good — Ref 187.

#[test]
fn a_half_written_picture_is_repaired_rather_than_trusted_forever() {
    let scratch = Scratch::new("torn-media");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");

    let bytes = b"a whole photograph, all of it";
    let hash = sha256(bytes).to_hex();
    project.write_proxy(&hash, "jpg", bytes).expect("written");

    // Stand in for the crash: leave half a file where the whole one was. This
    // is exactly what a machine going down mid-write leaves behind.
    let path = project
        .path()
        .join(package::proxy_name(&hash, "jpg"));
    fs::write(&path, &bytes[..7]).expect("torn");

    // Writing it again has to notice and repair. Before Ref 187 the check was
    // "does the path exist?", so this file stayed seven bytes long for the
    // life of the project — and synced that way to every device.
    project.write_proxy(&hash, "jpg", bytes).expect("rewritten");
    assert_eq!(
        fs::read(&path).expect("readable"),
        bytes,
        "a short file under a content-addressed name is a torn write, not a fact"
    );

    // And a file that is already whole is left alone rather than rewritten.
    let stamped = fs::metadata(&path).and_then(|m| m.modified()).expect("stamped");
    project.write_proxy(&hash, "jpg", bytes).expect("no-op");
    assert_eq!(
        fs::metadata(&path).and_then(|m| m.modified()).expect("stamped"),
        stamped,
        "a whole file was rewritten for nothing"
    );
}

#[test]
fn nothing_is_left_beside_the_manifest_after_writing_it() {
    let scratch = Scratch::new("manifest-swap");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let id = project.doc().project_id().expect("a project");
    project.doc_mut().set(id, f::TITLE, "Call Her Back");
    project.refresh_manifest().expect("refreshed");

    // The manifest is written beside and swapped in, so the folder must hold
    // the manifest and no scratch file — a `.manifest.json.1234.writing` left
    // lying about would sync to Drive and to the phone.
    let litter: Vec<String> = fs::read_dir(project.path())
        .expect("readable")
        .flatten()
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|name| name.contains(".writing"))
        .collect();
    assert!(litter.is_empty(), "left behind: {litter:?}");

    let written = fs::read_to_string(project.path().join(package::MANIFEST)).expect("manifest");
    assert!(written.contains("Call Her Back"), "{written}");
}

// ---- folding old diaries together --------------------------------------

/// Make every one of this device's logs ancient, by renaming them to sessions
/// long before anything was ever shot. The name carries the session, so this
/// is the whole of what "old" means to a fold.
fn age_the_logs(path: &std::path::Path, device: DeviceId) -> usize {
    let dir = path.join(package::CHANGES_DIR);
    let mut names: Vec<PathBuf> = fs::read_dir(&dir)
        .expect("changes")
        .flatten()
        .map(|entry| entry.path())
        .collect();
    names.sort();
    let mut session = 1;
    for old in names {
        let Some(name) = old.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let Some((wrote, was)) = package::log_parts(name) else {
            continue;
        };
        // Already aged by an earlier call.
        if wrote != device || was < 1_000_000 {
            continue;
        }
        fs::rename(&old, dir.join(package::log_name(device, session))).expect("renames");
        session += 1;
    }
    logs_in(path)
}

fn logs_in(path: &std::path::Path) -> usize {
    fs::read_dir(path.join(package::CHANGES_DIR))
        .expect("changes")
        .flatten()
        .filter(|entry| {
            entry
                .file_name()
                .to_str()
                .map(package::is_log_name)
                .unwrap_or(false)
        })
        .count()
}

/// Ref 192. A launch a day for a fortnight leaves a fortnight's files; opening
/// it once puts them in one, and every scene is still there.
#[test]
fn a_pile_of_old_diaries_becomes_one_file() {
    let scratch = Scratch::new("fold");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    for number in 0..13 {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene(&number.to_string());
        project.save().expect("saves");
    }

    let before = age_the_logs(&path, DeviceId(1));
    assert!(before > 8, "a fortnight of launches leaves a pile: {before}");

    // Opening it is what folds them.
    let opened = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(opened.doc().scenes_in_order().len(), 13, "every scene survives the fold");
    assert_eq!(logs_in(&path), 1, "and the pile is one file");
    drop(opened);

    // And it still reads that way from cold, which is the only proof that
    // matters: the fold rewrote what is on disk, not what was in hand.
    let cold = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(cold.doc().scenes_in_order().len(), 13);
}

/// **A fold says what it did, because nothing else can work it out.** Ref 192,
/// and the reason it matters: the relay refuses a rewritten log outright, and
/// fetches back every log this device deleted. Both halves of that are fixed by
/// reading this file, so a fold that does not write it jams sync.
#[test]
fn a_fold_writes_down_what_it_retired_and_what_it_wrote_over() {
    let scratch = Scratch::new("fold-record");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    for number in 0..13 {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene(&number.to_string());
        project.save().expect("saves");
    }
    let before = age_the_logs(&path, DeviceId(1));
    let _ = storage::open(&path, DeviceId(1)).expect("opens");

    let record = fs::read_to_string(
        path.join(package::CHANGES_DIR)
            .join(package::fold_record_name(DeviceId(1))),
    )
    .expect("a fold leaves a record");
    let record = package::decode_fold_record(&record);

    assert_eq!(record.rewritten.len(), 1, "one log took them all");
    assert_eq!(
        record.retired.len(),
        before - 1,
        "and every other one is named as finished"
    );
    assert!(
        !record.retired.contains(&record.rewritten[0]),
        "the log that took them is not one of the ones it took"
    );
}

/// **Folding twice gives the same bytes twice.** Not tidiness. The logs a fold
/// retires live on at the relay; one that comes back would be folded in a
/// second time, and a fold that does not notice would carry every earlier
/// round's copy with it and grow without end.
#[test]
fn folding_the_same_pile_again_changes_nothing() {
    let scratch = Scratch::new("fold-twice");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    for number in 0..13 {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene(&number.to_string());
        project.save().expect("saves");
    }
    age_the_logs(&path, DeviceId(1));
    let _ = storage::open(&path, DeviceId(1)).expect("opens");

    let folded = |path: &std::path::Path| -> Vec<(String, Vec<u8>)> {
        let mut all: Vec<(String, Vec<u8>)> = fs::read_dir(path.join(package::CHANGES_DIR))
            .expect("changes")
            .flatten()
            .filter(|entry| {
                entry
                    .file_name()
                    .to_str()
                    .map(package::is_log_name)
                    .unwrap_or(false)
            })
            .map(|entry| {
                (
                    entry.file_name().to_string_lossy().to_string(),
                    fs::read(entry.path()).expect("reads"),
                )
            })
            .collect();
        all.sort();
        all
    };
    let once = folded(&path);

    // The relay hands the retired ones back, exactly as it does today.
    let target = once[0].0.clone();
    age_the_logs(&path, DeviceId(1));
    for number in 900..910 {
        fs::write(
            path.join(package::CHANGES_DIR)
                .join(package::log_name(DeviceId(1), number)),
            &once[0].1,
        )
        .expect("writes");
    }
    let _ = storage::open(&path, DeviceId(1)).expect("opens");

    let twice = folded(&path);
    let after = twice
        .iter()
        .find(|(name, _)| *name == target || twice.len() == 1)
        .map(|(_, bytes)| bytes.len())
        .unwrap_or_else(|| twice[0].1.len());
    assert!(
        after <= once[0].1.len(),
        "folding the same changes again grew the file: {} then {after}",
        once[0].1.len()
    );
}

/// A handful of files is not clutter, and folding them would cost more than
/// leaving them.
#[test]
fn a_few_old_diaries_are_left_where_they_are() {
    let scratch = Scratch::new("fold-few");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    for number in 0..3 {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene(&number.to_string());
        project.save().expect("saves");
    }
    let before = age_the_logs(&path, DeviceId(1));
    let _ = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(logs_in(&path), before, "nothing was folded");
}

/// **Another device's diary is never touched**, however old it is. That rule
/// is the whole reason two machines on one synced folder need no locking.
#[test]
fn another_devices_diary_is_never_folded() {
    let scratch = Scratch::new("fold-theirs");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    // Twelve ancient logs belonging to the other machine.
    let dir = path.join(package::CHANGES_DIR);
    for session in 1..=12 {
        fs::write(
            dir.join(package::log_name(DeviceId(2), session)),
            "shotlister-log 1\n",
        )
        .expect("writes");
    }
    let before = logs_in(&path);

    let _ = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(logs_in(&path), before, "we do not rewrite what we did not write");
}

/// **A diary holding a line this build cannot read is left exactly where it
/// is.** Ref 192. Folding rewrites a file under our own version header, and
/// doing that to somebody else's work would be a lie about who wrote it — so
/// the fold goes around it and takes the rest.
#[test]
fn a_diary_with_a_line_from_the_future_is_not_folded() {
    let scratch = Scratch::new("fold-future");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    for number in 0..13 {
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        project.doc_mut().create_scene(&number.to_string());
        project.save().expect("saves");
    }
    let _ = age_the_logs(&path, DeviceId(1));

    // An operation letter from a build that does not exist yet, in one of our
    // own logs — which is what a project edited by a newer Shotlister and
    // brought back here looks like.
    let from_the_future =
        "1786900000000\t0\t1\tX\t01a00b57e8790941866a989900000000\tsomething\tt:new";
    let marked = path
        .join(package::CHANGES_DIR)
        .join(package::log_name(DeviceId(1), 2));
    let mut text = fs::read_to_string(&marked).expect("reads");
    text.push_str(from_the_future);
    text.push('\n');
    fs::write(&marked, text).expect("writes");

    let opened = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(opened.unreadable_lines(), 1, "and we still say so");
    drop(opened);

    assert!(marked.exists(), "the one we cannot read whole stays put");
    assert_eq!(logs_in(&path), 2, "the other twelve became one beside it");

    let mut on_disk = String::new();
    for entry in fs::read_dir(path.join(package::CHANGES_DIR))
        .expect("changes")
        .flatten()
    {
        on_disk.push_str(&fs::read_to_string(entry.path()).expect("reads"));
    }
    assert_eq!(
        on_disk.matches(from_the_future).count(),
        1,
        "exactly one of it — neither dropped nor copied"
    );

    let cold = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(cold.doc().scenes_in_order().len(), 13, "and nothing of ours went");
}

// ---- giving back the room a deleted picture was taking ------------------

/// **The last use takes the record with it, and the bytes follow at the next
/// open once an hour has passed.** His ruling, 2026-09-19: a file added to
/// the shot list and then taken off is deleted for good. The record goes in
/// the same undoable step as the use (`release_media_use`), so nothing can
/// be handed the old copy back; the bytes are the stray sweep's, with its
/// hour of grace, so undo within the session still finds the picture.
///
/// This replaces Ref 192's rule — reclaim only once every device had merged
/// the deletion — which was written for the shared iCloud folder. Since
/// 2026-09-15 every device keeps its own folder and the relay carries files,
/// so deleting bytes here can no longer hollow a frame on the phone.
#[test]
fn a_picture_nothing_points_at_gives_its_room_back() {
    let scratch = Scratch::new("reclaim");
    let bytes = b"a frame, pretend, and a big one";
    let hash = shotlister_engine::sha256(bytes);

    let path = {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.write_proxy(&hash.to_hex(), "png", bytes).expect("writes");
        let scene = project.doc_mut().create_scene("34");
        let (shot, _) = project.doc_mut().add_shot_to_scene(scene);
        let media = project.doc_mut().add_media(
            hash,
            MediaKind::Image,
            1600,
            900,
            bytes.len() as u64,
            "frame.png",
        );
        let used = project.doc_mut().attach_media(shot, media, "");
        project.save().expect("saves");

        // Opening it now must NOT reclaim: the picture is still on the shot.
        let path = project.path().to_path_buf();
        drop(project);
        let mut project = storage::open(&path, DeviceId(1)).expect("opens");
        assert!(
            project.read_proxy(&hash.to_hex(), "png").expect("reads").is_some(),
            "a picture something points at is not a stray"
        );

        // Take the frame off the shot: the record goes with the use, and
        // one undo brings both back.
        project.doc_mut().detach_media(used);
        assert!(project.doc().get(media).is_none(), "its only use went, so the record went");
        project.doc_mut().undo();
        assert!(project.doc().get(media).is_some());
        assert!(project.read_proxy(&hash.to_hex(), "png").expect("reads").is_some(), "undo finds the bytes");
        project.doc_mut().detach_media(used);
        project.save().expect("saves");
        path
    };

    // The bytes are still there for an hour — undo within a session, and a
    // file that landed a moment before its record was saved, both live here.
    let reopened = storage::open(&path, DeviceId(1)).expect("opens");
    assert!(
        reopened.read_proxy(&hash.to_hex(), "png").expect("reads").is_some(),
        "a fresh stray waits its hour"
    );
    assert!(reopened.missing_media().is_empty(), "no record, so no hollow frame");
    drop(reopened);

    // An hour on, the next open takes the bytes.
    let proxies = path.join(package::PROXY_DIR);
    let old = std::time::SystemTime::now() - std::time::Duration::from_secs(3 * 60 * 60);
    for entry in fs::read_dir(&proxies).expect("proxies").flatten() {
        let handle = fs::File::options().write(true).open(entry.path()).expect("opens");
        handle.set_modified(old).expect("ages");
    }
    let cold = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(cold.read_proxy(&hash.to_hex(), "png").expect("reads"), None, "the room comes back");
    assert!(cold.missing_media().is_empty());
    assert_eq!(cold.doc().scenes_in_order().len(), 1, "the shot list is untouched");
}

/// **A file still used elsewhere keeps its record and its bytes**, however
/// many times another use of it goes — the half of his ruling that keeps a
/// board's photograph when the shot that also had it is cleared.
#[test]
fn a_picture_still_used_elsewhere_is_kept_when_one_use_goes() {
    let scratch = Scratch::new("reclaim-two");
    let bytes = b"a frame the board still believes in";
    let hash = shotlister_engine::sha256(bytes);
    let stored = hash.to_hex();

    let mut mac = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    mac.write_proxy(&stored, "png", bytes).expect("writes");
    let scene = mac.doc_mut().create_scene("34");
    let (shot, _) = mac.doc_mut().add_shot_to_scene(scene);
    let board = mac.doc_mut().create_board("Anya");
    let media = mac.doc_mut().add_media(hash, MediaKind::Image, 1600, 900, bytes.len() as u64, "frame.png");
    let on_shot = mac.doc_mut().attach_media(shot, media, "");
    mac.doc_mut().attach_media(board, media, "");
    mac.doc_mut().detach_media(on_shot);
    assert!(mac.doc().get(media).is_some(), "the board still holds it");
    mac.save().expect("saves");
    let path = mac.path().to_path_buf();
    drop(mac);

    // Aged past the hour, it is still not a stray: a record names it.
    let proxies = path.join(package::PROXY_DIR);
    let old = std::time::SystemTime::now() - std::time::Duration::from_secs(3 * 60 * 60);
    for entry in fs::read_dir(&proxies).expect("proxies").flatten() {
        let handle = fs::File::options().write(true).open(entry.path()).expect("opens");
        handle.set_modified(old).expect("ages");
    }
    let again = storage::open(&path, DeviceId(1)).expect("opens");
    assert!(again.read_proxy(&stored, "png").expect("reads").is_some(), "a named picture stays");
    assert!(again.missing_media().is_empty());
}

/// Ref 326, undone. A film the gear-column merge reached is repaired the next
/// time it opens: the camera comes out of its Equipment cell, and Camera is a
/// column again.
#[test]
fn a_film_the_merge_reached_is_put_back_on_open() {
    let scratch = Scratch::new("unmerge");
    let path = {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        let scene = project.doc_mut().create_scene("34");
        let (shot, _) = project.doc_mut().add_shot_to_scene(scene);
        let unit = project.doc_mut().create_unit("A-Cam", "Alexa35");
        project.doc_mut().set(shot, f::UNIT, unit);

        // Exactly what the merge left behind: both in one cell, the camera in
        // the Equipment list, and the mark saying it was done.
        project.doc_mut().set(shot, "support", "Handheld, A-Cam");
        project.doc_mut().set_vocabulary("support", &["Handheld", "A-Cam"]);
        let id = project.doc().project_id().expect("a project");
        project.doc_mut().set(id, "gear_columns_merged", true);
        project.save().expect("saves");
        project.path().to_path_buf()
    };

    let reopened = storage::open(&path, DeviceId(1)).expect("opens");
    let shot = {
        let scene = reopened.doc().scenes_in_order()[0];
        let placement = reopened.doc().placements_in_scene(scene)[0];
        reopened.doc().get(placement).unwrap().ref_id(f::SHOT).unwrap()
    };
    assert_eq!(
        reopened.doc().get(shot).unwrap().text("support"),
        Some("Handheld"),
        "the camera is out of the Equipment cell"
    );
    assert!(
        !reopened.doc().vocabulary("support").iter().any(|t| t == "A-Cam"),
        "and out of the Equipment list"
    );
    assert!(
        reopened.doc().column_order().iter().any(|c| c == "camera"),
        "and Camera is a column again"
    );
    drop(reopened);

    // It stays repaired, and repairing does not happen twice.
    let cold = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(cold.doc().get(shot).unwrap().text("support"), Some("Handheld"));
}

/// **A log that changes on disk is re-read, and must not be re-recorded.**
///
/// A guard, and honest about what it is: **this passes with or without the
/// deduplication in `Store::apply`**, because `pull` already filters a re-read
/// log against the stamps the document holds before merging any of it. It was
/// written while chasing the runaway on his *Call Her Back* — a change file that
/// reached a megabyte holding 639 distinct changes — on the theory that `pull`
/// was the way duplicates got in. That theory is wrong, and the test is kept to
/// say so: whatever fed them in, it was not this path, so don't spend the
/// afternoon here again.
///
/// The two filters are worth keeping both of. `pull`'s is cheap and stops the
/// work; `Store::apply`'s is the invariant, at the one place the log can grow.
#[test]
fn a_log_re_read_from_disk_is_not_recorded_twice() {
    let scratch = Scratch::new("re-read");
    let path = storage::create(&scratch.0, "Daybreak", DeviceId(1))
        .expect("creates")
        .path()
        .to_path_buf();

    // One session writes some work and closes, leaving a log behind.
    {
        let mut first = storage::open(&path, DeviceId(1)).expect("opens");
        let scene = first.doc_mut().create_scene("34");
        first.doc_mut().set(scene, f::TITLE, "INT. KITCHEN - DAY");
        first.save().expect("saves");
    }

    // Named before the next session opens, so it is unmistakably the older one
    // rather than the log the new session is writing to — `pull` skips its own.
    let older = fs::read_dir(path.join(package::CHANGES_DIR))
        .expect("changes")
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .find(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(package::is_log_name)
                .unwrap_or(false)
        })
        .expect("the first session left a log");

    // The next session merges that log at open, and writes to a log of its own.
    let mut project = storage::open(&path, DeviceId(1)).expect("opens");
    let before = project.doc().changes().len();
    assert!(before >= 2, "the fixture should leave a couple of changes");

    // The older log moves on disk without its contents changing — exactly what
    // iCloud does when it finishes delivering a file another device is writing.
    let bytes = fs::read(&older).expect("reads");
    fs::write(&older, &bytes).expect("rewrites the same bytes");

    project.pull().expect("pulls");
    assert_eq!(
        project.doc().changes().len(),
        before,
        "re-reading a log the document already holds recorded its changes again"
    );

    // And it compounds, which is what made it run away rather than merely
    // double.
    for _ in 0..3 {
        fs::write(&older, &bytes).expect("rewrites");
        project.pull().expect("pulls");
    }
    assert_eq!(project.doc().changes().len(), before, "the log grew on every pull");
}

// ---- the rooms the phone scanned ---------------------------------------

/// Write a scan into a location's folder the way the phone does: two files
/// sharing one name, under `locations/<folder>/scans/`.
fn leave_a_scan(project: &storage::Project, folder: &str, name: &str, room: &str) {
    let dir = project
        .path()
        .join("locations")
        .join(folder)
        .join("scans");
    fs::create_dir_all(&dir).expect("the scans folder");
    fs::write(dir.join(format!("{name}.usdz")), format!("usdz-{name}")).expect("the shape");
    fs::write(dir.join(format!("{name}.json")), room).expect("the measurements");
}

#[test]
fn a_scanned_room_becomes_part_of_the_film() {
    let scratch = Scratch::new("scans");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let place = project.doc_mut().create_location("The Ellis House");
    // **A location made here has no folder of its own**, so its scans land
    // under its id — Ref 305's rule, and the one this used to get wrong.
    leave_a_scan(&project, &place.0.to_string(), "RoomScan_1", "{\"walls\":[]}");

    assert_eq!(project.register_scans().expect("reads"), 2);
    let scans = project.doc().scans_of(place);
    assert_eq!(scans.len(), 1, "two files sharing a name are one room");
    // Named for where it was taken (2026-10-17); its files keep their name.
    assert_eq!(scans[0].name, "The Ellis House · Scan 1");
    assert_eq!(scans[0].file, "RoomScan_1");
    assert!(scans[0].shape.is_some() && scans[0].plan.is_some());

    // **The bytes are in the media store**, which is the whole point: that is
    // the folder sync carries, and nothing had to be taught about rooms.
    let shape = scans[0].shape.expect("a shape");
    let hash = project.doc().get(shape).and_then(|r| r.text(f::HASH).map(str::to_string)).expect("a hash");
    assert!(matches!(project.find_proxy(&hash, Some("usdz")), Ok(Some(_))));
    assert_eq!(project.doc().media_kind(shape), Some(MediaKind::Scan));
    assert_eq!(
        project.doc().media_kind(scans[0].plan.expect("measurements")),
        Some(MediaKind::ScanShape)
    );

    // **A scan is not a photograph.** Both are attached the same way, so a
    // wall of pictures that asked for every file would hang a broken image for
    // the room and a second one for its measurements.
    assert!(project.doc().picture_refs(place).is_empty());

    // Safe to run again: a file already on this location is left alone.
    assert_eq!(project.register_scans().expect("reads"), 0);
    assert_eq!(project.doc().scans_of(place).len(), 1);
}

#[test]
fn a_scan_with_no_measurements_beside_it_is_still_a_room() {
    let scratch = Scratch::new("scans-half");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let place = project.doc_mut().create_location("The Shop");
    let dir = project.path().join("locations").join(place.0.to_string()).join("scans");
    fs::create_dir_all(&dir).expect("the scans folder");
    fs::write(dir.join("RoomScan_2.usdz"), "usdz-only").expect("the shape");

    assert_eq!(project.register_scans().expect("reads"), 1);
    let scans = project.doc().scans_of(place);
    assert_eq!(scans.len(), 1);
    assert!(scans[0].shape.is_some());
    assert!(scans[0].plan.is_none(), "and the panel says the measurements are missing");
}

#[test]
fn one_room_scanned_into_two_places_is_stored_once() {
    let scratch = Scratch::new("scans-twice");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let one = project.doc_mut().create_location("Kitchen");
    let two = project.doc_mut().create_location("Pantry");
    // The same bytes under both — which is what moving a scan between
    // locations by hand produces, and he has done exactly that (Ref 385).
    leave_a_scan(&project, &one.0.to_string(), "RoomScan_3", "{\"walls\":[]}");
    leave_a_scan(&project, &two.0.to_string(), "RoomScan_3", "{\"walls\":[]}");

    assert_eq!(project.register_scans().expect("reads"), 4);
    assert_eq!(project.doc().scans_of(one).len(), 1);
    assert_eq!(project.doc().scans_of(two).len(), 1);
    // One file, addressed by its contents, used twice — the rule photographs
    // have always followed.
    let stored = fs::read_dir(project.path().join(package::PROXY_DIR))
        .expect("the media store")
        .filter_map(|e| e.ok())
        .count();
    assert_eq!(stored, 2, "one shape and one set of measurements, not four files");
}

// ---- a clip made smaller after the fact, and the files it leaves ---------

/// Posters became JPEG on 2026-09-15. A reader that still asks for a clip's
/// still as `png` must get the still, not the movie.
#[test]
fn a_poster_asked_for_by_the_other_still_name_is_still_the_poster() {
    let scratch = Scratch::new("poster-either-way");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let movie = b"the clip itself";
    let hash = sha256(movie).to_hex();
    project.write_proxy(&hash, "mp4", movie).expect("writes");
    project.write_proxy(&hash, "jpg", b"the poster, jpeg").expect("writes");

    let (ext, bytes) = project.find_proxy(&hash, Some("png")).expect("reads").expect("found");
    assert_eq!((ext.as_str(), bytes.as_slice()), ("jpg", b"the poster, jpeg".as_slice()));
    let (ext, _) = project.find_proxy(&hash, Some("jpg")).expect("reads").expect("found");
    assert_eq!(ext, "jpg");
    // And the movie still wins when nobody asked for a still.
    let (ext, _) = project.find_proxy(&hash, None).expect("reads").expect("found");
    assert_eq!(ext, "mp4");
    let (ext, _) = project.find_proxy(&hash, Some("mov")).expect("reads").expect("found");
    assert_eq!(ext, "mp4", "a movie asked for by the wrong movie name is still the movie");
}

#[test]
fn removing_a_clips_stored_files_takes_its_poster_and_strips_too() {
    let scratch = Scratch::new("remove-stored");
    let project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let hash = sha256(b"the clip").to_hex();
    let other = sha256(b"another clip").to_hex();
    project.write_proxy(&hash, "mov", b"movie").expect("writes");
    project.write_proxy(&hash, "png", b"poster").expect("writes");
    project.write_proxy(&hash, "strip", b"strip").expect("writes");
    project
        .write_proxy(&package::strip_key(&hash, Some((1.0, 3.0))), "strip", b"trimmed")
        .expect("writes");
    project.write_proxy(&other, "mov", b"other movie").expect("writes");

    let mut gone = project.remove_stored(&hash);
    gone.sort();
    assert_eq!(gone.len(), 4, "the movie, the poster, and both strips: {gone:?}");
    assert!(project.read_proxy(&hash, "mov").expect("reads").is_none());
    assert!(project.read_proxy(&other, "mov").expect("reads").is_some(), "another clip is untouched");
}

/// A file no record names is a stray and goes at open — unless it is fresh,
/// because a picture lands a moment before the log that names it.
#[test]
fn stray_files_go_at_open_but_fresh_ones_wait() {
    let scratch = Scratch::new("strays");
    let named = b"a frame somebody uses";
    let named_hash = sha256(named);
    let stray = b"a clip replaced last week";
    let stray_hash = sha256(stray).to_hex();
    let fresh = b"a picture that arrived a moment ago";
    let fresh_hash = sha256(fresh).to_hex();

    let path = {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.write_proxy(&named_hash.to_hex(), "jpg", named).expect("writes");
        project.write_proxy(&stray_hash, "mov", stray).expect("writes");
        project.write_proxy(&stray_hash, "png", b"its poster").expect("writes");
        project.write_proxy(&fresh_hash, "jpg", fresh).expect("writes");
        let scene = project.doc_mut().create_scene("34");
        let (shot, _) = project.doc_mut().add_shot_to_scene(scene);
        let media = project.doc_mut().add_media(
            named_hash,
            MediaKind::Image,
            1600,
            900,
            named.len() as u64,
            "frame.jpg",
        );
        project.doc_mut().attach_media(shot, media, "");
        project.save().expect("saves");
        project.path().to_path_buf()
    };

    // Age the stray, not the fresh one.
    let proxies = path.join(package::PROXY_DIR);
    let old = std::time::SystemTime::now() - std::time::Duration::from_secs(3 * 60 * 60);
    for name in fs::read_dir(&proxies).expect("proxies").flatten() {
        let file = name.path();
        let stem = file.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        if stray_hash.starts_with(stem) {
            let handle = fs::File::options().write(true).open(&file).expect("opens");
            handle.set_modified(old).expect("ages");
        }
    }

    let reopened = storage::open(&path, DeviceId(1)).expect("opens");
    assert!(reopened.read_proxy(&stray_hash, "mov").expect("reads").is_none(), "the stray movie is gone");
    assert!(reopened.read_proxy(&stray_hash, "png").expect("reads").is_none(), "and its poster");
    assert!(reopened.read_proxy(&named_hash.to_hex(), "jpg").expect("reads").is_some(), "a named picture stays");
    assert!(reopened.read_proxy(&fresh_hash, "jpg").expect("reads").is_some(), "a fresh stray waits");
}

// ---- the script travels --------------------------------------------------

/// A revision's text and PDF used to be written to `originals/`, which the
/// relay never carries; since 2026-09-15 they live with the proxies. A film
/// from before is adopted at open, a device that lacks them asks for them,
/// and a sweep never takes them.
#[test]
fn a_script_is_filed_with_the_proxies_and_an_old_one_is_adopted() {
    use shotlister_engine::{Id, Revision, Taking};
    let scratch = Scratch::new("script-travels");
    let text = "INT. KITCHEN - DAY\n\nMELISSA pours coffee.\n";
    let hash = sha256(text.as_bytes()).to_hex();

    let path = {
        let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        // The old way: text and PDF in originals, and a revision naming them.
        project.write_original(&hash, "txt", text.as_bytes()).expect("writes");
        project.write_original(&hash, "pdf", b"%PDF pretend").expect("writes");
        let screenplay = shotlister_engine::screenplay::read(text);
        let revision = Revision {
            id: Id::new(),
            name: "First draft".to_string(),
            filename: "daybreak.pdf".to_string(),
            imported_at: "2026-09-15T00:00:00Z".to_string(),
            hash: hash.clone(),
        };
        project.doc_mut().take_revision(&screenplay, &Taking::default(), &revision);
        project.save().expect("saves");
        assert_eq!(project.missing_scripts(), vec![hash[..32].to_string()], "not in the proxies yet");
        project.path().to_path_buf()
    };

    let reopened = storage::open(&path, DeviceId(1)).expect("opens");
    assert_eq!(
        reopened.read_proxy(&hash, "txt").expect("reads").as_deref(),
        Some(text.as_bytes()),
        "adopted into the proxies at open"
    );
    assert!(reopened.read_proxy(&hash, "pdf").expect("reads").is_some());
    assert!(reopened.missing_scripts().is_empty(), "nothing missing once adopted");
    // The engine counts the revision's hash as a name, so the sweep leaves it.
    let names = [format!("{}.txt", &hash[..32]), format!("{}.pdf", &hash[..32])];
    assert!(reopened.doc().stray_media_names(names.iter().map(String::as_str)).is_empty());
    // And a read goes through the same door.
    assert_eq!(reopened.read_script(&hash, "txt").expect("reads").as_deref(), Some(text.as_bytes()));
}

/// A paper the phone pinned to a location — `locations/<folder>/attachments/`
/// — is registered with the film the way a scan is, so it travels.
#[test]
fn a_paper_pinned_to_a_location_is_registered_and_travels() {
    use shotlister_engine::store::Kind;
    let scratch = Scratch::new("attachments");
    let mut project = storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
    let place = project.doc_mut().create_location("The Ellis House");
    let dir = project.path().join("locations").join(place.0.to_string()).join("attachments");
    fs::create_dir_all(&dir).expect("folder");
    fs::write(dir.join("permit.pdf"), b"%PDF a permit").expect("writes");
    fs::write(dir.join(".DS_Store"), b"noise").expect("writes");

    assert_eq!(project.register_attachments().expect("registers"), 1);
    assert_eq!(project.register_attachments().expect("registers"), 0, "not twice");
    let media = project.doc().media_of(place);
    assert_eq!(media.len(), 1);
    assert_eq!(project.doc().media_kind(media[0]), Some(MediaKind::Other));
    let hash = sha256(b"%PDF a permit").to_hex();
    assert!(project.read_proxy(&hash, "pdf").expect("reads").is_some(), "filed with the proxies");
    let held = project.doc().media_refs(place)[0];
    assert_eq!(project.doc().media_ref_name(held), "permit.pdf");
    assert_eq!(project.doc().store().of_kind(&Kind::Media).len(), 1);
}

// ---- Print Frames travel -------------------------------------------------

/// A bake is a picture no media record names, so a device that lacked one
/// never asked the relay for it, and the iPhone drew no Print Frames for a
/// real synced film (2026-10-16). A current bake missing here is asked for;
/// once it is here, or once it is stale, it is not.
#[test]
fn a_device_without_a_print_frame_asks_for_it() {
    use shotlister_engine::printframe::{Baked, Moment, PrintFrame};
    let scratch = Scratch::new("print-frame-travels");
    let mut project = storage::create(&scratch.0, "Call Her Back", DeviceId(2)).expect("creates");
    let board = sha256(b"the baked board").to_hex();
    let (shot, spec) = {
        let d = project.doc_mut();
        let scene = d.create_scene("1");
        let (shot, _) = d.add_shot_to_scene(scene);
        let still = d.add_media(sha256(b"a still"), MediaKind::Image, 1600, 900, 1000, "still.jpg");
        let used = d.attach_media(shot, still, "");
        let spec = PrintFrame {
            layout: "one".into(),
            frames: vec![Moment { media_ref: used, at: None }],
            numbers: false,
            arrows: vec![],
        };
        d.set_print_frame(shot, &spec);
        d.set_print_frame_baked(
            shot,
            &Baked { hash: board.clone(), ext: "jpg".into(), width: 2000, height: 1500, digest: spec.digest() },
        );
        (shot, spec)
    };
    assert_eq!(project.missing_print_frames(), vec![board[..32].to_string()]);

    project.write_proxy(&board, "jpg", b"jpeg pretend").expect("writes");
    assert!(project.missing_print_frames().is_empty(), "here now");

    // A stale bake is never drawn, so nothing goes looking for it.
    project.remove_proxy(&board, "jpg").ok();
    let mut changed = spec.clone();
    changed.numbers = true;
    project.doc_mut().set_print_frame(shot, &changed);
    assert!(project.missing_print_frames().is_empty(), "stale: not asked for");
}
