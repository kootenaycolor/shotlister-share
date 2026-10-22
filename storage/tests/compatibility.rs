//! The gate.
//!
//! Section 11 says one test stands between a release and the work: write a
//! project with the newest engine, open it with the oldest one still supported,
//! save, and confirm nothing was lost. The rule it defends — *anything an app
//! does not understand, it carries through untouched* — is free if it is
//! designed in from the first line and impossible to retrofit, which is exactly
//! the kind of rule that quietly stops being true.
//!
//! There is only one codebase here, so "an older build" is played by a log
//! holding lines this build cannot interpret: an operation letter it has never
//! heard of, a record kind from later, a value type from later. If those survive
//! being opened, edited and saved, then so will a real older build's work.

use std::fs;
use std::path::PathBuf;

use shotlister_engine::doc::f;
use shotlister_engine::format::decode_log;
use shotlister_engine::package::{self, Problem};
use shotlister_engine::{DeviceId, Kind, Value};
use shotlister_storage as storage;

struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Scratch {
        let path =
            std::env::temp_dir().join(format!("shotlister-compat-{name}-{}", std::process::id()));
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

const US: DeviceId = DeviceId(1);
const THEM: DeviceId = DeviceId(2);

/// Lines written by a build that does not exist yet. Every one of them is
/// well-formed and none of them are readable here.
const FROM_THE_FUTURE: &[&str] = &[
    // An operation letter introduced later.
    "1786900000000\t0\t2\tX\t01a00b57e8790941866a989900000000\tsomething\tt:new",
    // A value type introduced later.
    "1786900000001\t0\t2\tS\t01a00b57e8790941866a989900000000\tmood\tq:9",
];

fn write_a_log_from_the_future(project: &std::path::Path) {
    let log = project
        .join(package::CHANGES_DIR)
        .join(package::log_name(THEM, 999));
    let mut text = String::from("shotlister-log 1\n");
    // A record kind from later, which *is* readable as a line and held as an
    // opaque kind rather than dropped.
    text.push_str("1786900000002\t0\t2\tC\t01a00b57e8790941866a989900000009\tmoodboard\n");
    for line in FROM_THE_FUTURE {
        text.push_str(line);
        text.push('\n');
    }
    fs::write(log, text).expect("writes");
}

#[test]
fn the_gate_nothing_is_lost_by_a_build_that_does_not_understand_it() {
    let scratch = Scratch::new("gate");

    let mut ours = storage::create(&scratch.0, "Daybreak", US).expect("creates");
    let scene = ours.doc_mut().create_scene("34");
    let (_shot, placement) = ours.doc_mut().add_shot_to_scene(scene);
    ours.doc_mut().set(placement, f::LENS, "37mm");
    ours.save().expect("saves");
    let path = ours.path().to_path_buf();
    drop(ours);

    write_a_log_from_the_future(&path);

    // Open it, notice we cannot read all of it, work anyway, and save.
    let mut reopened = storage::open(&path, US).expect("opens");
    assert_eq!(
        reopened.unreadable_lines(),
        FROM_THE_FUTURE.len(),
        "the app can say that something here was written by a newer version"
    );
    reopened.doc_mut().set(placement, f::LENS, "40mm");
    reopened.doc_mut().set(placement, f::NOTES, "handheld");
    reopened.save().expect("saves");

    // Every line from the future is still on disk, exactly as it was written.
    let mut on_disk = String::new();
    for entry in fs::read_dir(path.join(package::CHANGES_DIR))
        .expect("changes")
        .flatten()
    {
        on_disk.push_str(&fs::read_to_string(entry.path()).expect("reads"));
    }
    for line in FROM_THE_FUTURE {
        assert!(
            on_disk.contains(line),
            "a line this build could not read is still somebody's work: {line}"
        );
        assert_eq!(
            on_disk.matches(line).count(),
            1,
            "and there is exactly one of it — copying it forward would multiply it: {line}"
        );
    }

    // And our own work landed.
    let after = storage::open(&path, DeviceId(9)).expect("opens");
    assert_eq!(
        after.doc().get(placement).and_then(|r| r.text(f::LENS)),
        Some("40mm")
    );
    assert_eq!(
        after.doc().get(placement).and_then(|r| r.text(f::NOTES)),
        Some("handheld")
    );
}

#[test]
fn a_record_kind_from_later_is_held_rather_than_dropped() {
    let scratch = Scratch::new("kind");

    let mut ours = storage::create(&scratch.0, "Daybreak", US).expect("creates");
    ours.doc_mut().create_scene("34");
    ours.save().expect("saves");
    let path = ours.path().to_path_buf();
    drop(ours);

    write_a_log_from_the_future(&path);

    let mut reopened = storage::open(&path, US).expect("opens");
    reopened.doc_mut().create_scene("35");
    reopened.save().expect("saves");

    let after = storage::open(&path, DeviceId(9)).expect("opens");
    let unknown = shotlister_engine::Id::from_hex("01a00b57e8790941866a989900000009").expect("id");
    assert_eq!(
        after.doc().get(unknown).map(|r| r.kind.clone()),
        Some(Kind::Other("moodboard".to_string())),
        "a kind from a later build is carried, not guessed at and not discarded"
    );
}

#[test]
fn a_field_nobody_here_has_heard_of_survives_an_edit_to_its_neighbours() {
    let scratch = Scratch::new("field");

    let mut ours = storage::create(&scratch.0, "Daybreak", US).expect("creates");
    let scene = ours.doc_mut().create_scene("34");
    let (_shot, placement) = ours.doc_mut().add_shot_to_scene(scene);
    // A field from a later build. Records are bags of names, so this needs no
    // special handling anywhere — which is the whole point of the design.
    ours.doc_mut().set(placement, "colour_note", "push the greens");
    ours.doc_mut().set(placement, f::LENS, "37mm");
    ours.save().expect("saves");
    let path = ours.path().to_path_buf();
    drop(ours);

    let mut reopened = storage::open(&path, THEM).expect("opens");
    reopened.doc_mut().set(placement, f::LENS, "40mm");
    reopened.save().expect("saves");

    let after = storage::open(&path, DeviceId(9)).expect("opens");
    assert_eq!(
        after.doc().get(placement).and_then(|r| r.text("colour_note")),
        Some("push the greens"),
        "editing the lens left the field beside it exactly as it was found"
    );
}

#[test]
fn a_project_from_before_watermarks_opens_and_accuses_nobody() {
    let scratch = Scratch::new("old-format");

    let mut ours = storage::create(&scratch.0, "Daybreak", US).expect("creates");
    let scene = ours.doc_mut().create_scene("34");
    let (_shot, placement) = ours.doc_mut().add_shot_to_scene(scene);
    ours.doc_mut().set(placement, f::LENS, "37mm");
    ours.save().expect("saves");
    let path = ours.path().to_path_buf();
    drop(ours);

    // Rewrite every log the way a build from before any of this would have:
    // the same changes, none of the bookkeeping about who had seen what.
    let changes = path.join(package::CHANGES_DIR);
    for entry in fs::read_dir(&changes).expect("changes").flatten() {
        let text = fs::read_to_string(entry.path()).expect("reads");
        let stripped: Vec<&str> = text.lines().filter(|line| !line.starts_with("W\t")).collect();
        fs::write(entry.path(), format!("{}\n", stripped.join("\n"))).expect("writes");
    }

    let mut reopened = storage::open(&path, US).expect("opens");
    assert_eq!(
        reopened.doc().get(placement).and_then(|r| r.text(f::LENS)),
        Some("37mm"),
        "the list is exactly what it was"
    );
    assert!(
        reopened.doc().clashes().is_empty(),
        "with nothing recorded about what anybody knew, nothing is claimed"
    );

    // Carrying on from there works, and what we write does record it.
    reopened.doc_mut().set(placement, f::LENS, "40mm");
    reopened.save().expect("saves");

    let has_watermark = fs::read_dir(&changes)
        .expect("changes")
        .flatten()
        .any(|entry| {
            fs::read_to_string(entry.path())
                .map(|text| text.lines().any(|line| line.starts_with("W\t")))
                .unwrap_or(false)
        });
    assert!(has_watermark, "an old project is brought forward by being used");
}

#[test]
fn a_project_from_the_future_says_so_rather_than_being_guessed_at() {
    let scratch = Scratch::new("too-new");

    let mut ours = storage::create(&scratch.0, "Daybreak", US).expect("creates");
    ours.doc_mut().create_scene("34");
    ours.save().expect("saves");
    let path = ours.path().to_path_buf();
    drop(ours);

    let manifest = path.join(package::MANIFEST);
    let text = fs::read_to_string(&manifest).expect("reads");
    fs::write(&manifest, text.replace("\"format\": 1", "\"format\": 99")).expect("writes");

    match storage::open(&path, US) {
        Err(storage::Error::Project(Problem::TooNew { found, .. })) => {
            assert_eq!(found, 99);
        }
        Err(other) => panic!("wrong refusal: {}", other.message()),
        Ok(_) => panic!("a project from a newer build must not be opened for writing"),
    }
}

#[test]
fn every_log_a_release_writes_is_still_a_valid_log() {
    let scratch = Scratch::new("valid");

    let mut ours = storage::create(&scratch.0, "Daybreak", US).expect("creates");
    let scene = ours.doc_mut().create_scene("34");
    let (a, first) = ours.doc_mut().add_shot_to_scene(scene);
    let (b, _second) = ours.doc_mut().add_shot_to_scene(scene);
    ours.doc_mut().tie_setup(a, b);
    ours.doc_mut().set(first, f::LENS, "37mm");
    ours.doc_mut().set(first, f::ANGLE, Value::List(vec![Value::text("low"), Value::text("canted")]));
    ours.save().expect("saves");

    // Several saves, so appended blocks are covered as well as fresh files.
    ours.doc_mut().set(first, f::NOTES, "handheld");
    ours.save().expect("saves");
    ours.doc_mut().create_scene("35");
    ours.save().expect("saves");

    for entry in fs::read_dir(ours.path().join(package::CHANGES_DIR))
        .expect("changes")
        .flatten()
    {
        let text = fs::read_to_string(entry.path()).expect("reads");
        let log = decode_log(&text).expect("every log this build writes decodes");
        assert!(
            log.preserved.is_empty(),
            "a build cannot write a line it cannot read back: {:?}",
            log.preserved
        );
    }
}
