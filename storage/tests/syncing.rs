//! Two devices on one folder.
//!
//! This is what a synced folder actually looks like from the engine's side:
//! nobody sends anything anywhere, change files just appear, and each device
//! notices them when it next looks. Whether the folder is iCloud Drive, a share
//! over Tailscale, or a stick carried across a car park makes no difference
//! here, which is the point.

use std::fs;
use std::path::PathBuf;

use shotlister_engine::doc::f;
use shotlister_engine::{package, DeviceId};
use shotlister_storage as storage;

struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Scratch {
        let path = std::env::temp_dir().join(format!("shotlister-sync-{name}-{}", std::process::id()));
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

const MAC: DeviceId = DeviceId(1);
const PHONE: DeviceId = DeviceId(2);

#[test]
fn a_second_device_sees_what_the_first_one_wrote() {
    let scratch = Scratch::new("appears");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    let (_shot, placement) = mac.doc_mut().add_shot_to_scene(scene);
    mac.doc_mut().set(placement, f::LENS, "37mm");
    mac.save().expect("saves");

    // The phone opens the same folder.
    let mut phone = storage::open(mac.path(), PHONE).expect("opens");
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        Some("37mm")
    );

    // The Mac carries on working while the phone has it open.
    mac.doc_mut().set(placement, f::LENS, "40mm");
    mac.save().expect("saves");

    // Nothing has reached the phone until it looks.
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        Some("37mm")
    );

    let pull = phone.pull().expect("pulls");
    assert!(!pull.is_empty(), "something arrived");
    assert_eq!(pull.devices, vec![MAC]);
    assert!(!pull.needs_attention(), "and it was uneventful");
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        Some("40mm")
    );
}

#[test]
fn pulling_twice_brings_nothing_the_second_time() {
    let scratch = Scratch::new("idempotent");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    mac.doc_mut().add_shot_to_scene(scene);
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");
    mac.doc_mut().create_scene("35");
    mac.save().expect("saves");

    let first = phone.pull().expect("pulls");
    assert!(first.merged > 0);

    let second = phone.pull().expect("pulls");
    assert_eq!(second.merged, 0, "nothing arrives twice");
    assert!(second.is_empty());
}

#[test]
fn a_device_never_writes_another_devices_changes_into_its_own_log() {
    let scratch = Scratch::new("own-log");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    mac.doc_mut().create_scene("34");
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");

    // The Mac writes a lot; the phone pulls it in and then writes one thing.
    for number in ["35", "36", "37"] {
        mac.doc_mut().create_scene(number);
    }
    mac.save().expect("saves");
    phone.pull().expect("pulls");
    phone.doc_mut().create_scene("38");
    phone.save().expect("saves");

    // Every line in the phone's log is the phone's.
    let logs = fs::read_dir(phone.path().join(package::CHANGES_DIR)).expect("changes");
    let mut phone_lines = 0;
    for entry in logs.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.starts_with(&format!("{:016x}", PHONE.0)) {
            continue;
        }
        for line in fs::read_to_string(entry.path()).expect("reads").lines() {
            let columns: Vec<&str> = line.split('\t').collect();
            if columns.len() < 6 || line.starts_with("shotlister-log") || line.starts_with('W') {
                continue;
            }
            assert_eq!(
                columns[2],
                PHONE.0.to_string(),
                "a device's log holds only its own changes: {line}"
            );
            phone_lines += 1;
        }
    }
    assert!(phone_lines > 0, "the phone did write something");

    // And the scene the Mac made is still there for everyone.
    let reopened = storage::open(mac.path(), DeviceId(9)).expect("opens");
    assert_eq!(reopened.doc().scenes_in_order().len(), 5);
}

#[test]
fn both_sides_of_a_disagreement_survive_the_round_trip_and_it_is_reported_once() {
    let scratch = Scratch::new("clash");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    let (_shot, placement) = mac.doc_mut().add_shot_to_scene(scene);
    mac.doc_mut().set(placement, f::LENS, "37mm");
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");

    // Both go out of range and make a call about the same lens.
    mac.doc_mut().set(placement, f::LENS, "40mm");
    mac.save().expect("saves");
    phone.doc_mut().set(placement, f::LENS, "50mm");
    phone.save().expect("saves");

    let pull = phone.pull().expect("pulls");
    assert!(pull.needs_attention(), "this one is worth a word");
    assert_eq!(pull.clashes.len(), 1);
    let clash = pull.clashes[0].clone();
    assert_eq!(clash.field, f::LENS);
    assert_eq!(clash.record, placement);

    // Said in words, with both values and both devices in it.
    let message = phone.doc().clash_message(&clash, |device| {
        if device == MAC { "This Mac".to_string() } else { "iPhone".to_string() }
    });
    assert!(message.contains("40mm") && message.contains("50mm"), "{message}");
    assert!(
        message.contains("This Mac") && message.contains("iPhone"),
        "each value is attributed to the machine that actually wrote it: {message}"
    );

    // Pulling again does not say it a second time — it is already on screen.
    let again = phone.pull().expect("pulls");
    assert!(
        again.clashes.is_empty(),
        "a disagreement is announced once, not on every check"
    );

    // But it is still there to be dealt with.
    assert_eq!(phone.doc().clash_count(), 1);

    // Deciding ends it, and the decision reaches the other device like any edit.
    phone.doc_mut().take_theirs(&clash);
    phone.save().expect("saves");
    assert_eq!(phone.doc().clash_count(), 0);

    let pull = mac.pull().expect("pulls");
    assert!(!pull.needs_attention(), "a settled question is not re-opened");
    assert_eq!(mac.doc().clash_count(), 0);
    assert_eq!(
        mac.doc().get(placement).and_then(|r| r.text(f::LENS)),
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        "and both devices show the same value"
    );
}

#[test]
fn pulling_does_not_disturb_work_in_hand() {
    let scratch = Scratch::new("unsaved");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    let (_shot, placement) = mac.doc_mut().add_shot_to_scene(scene);
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");

    mac.doc_mut().set(placement, f::DESCRIPTION, "Wide on the door");
    mac.save().expect("saves");

    // The phone is mid-edit and has not saved.
    phone.doc_mut().set(placement, f::NOTES, "watch the boom");
    assert!(phone.has_unsaved());
    let waiting = phone.unsaved();

    phone.pull().expect("pulls");

    assert_eq!(phone.unsaved(), waiting, "the unsaved edit is still unsaved");
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::NOTES)),
        Some("watch the boom"),
        "and still there"
    );
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::DESCRIPTION)),
        Some("Wide on the door"),
        "alongside what arrived"
    );

    phone.save().expect("saves");
    let reopened = storage::open(phone.path(), DeviceId(9)).expect("opens");
    assert_eq!(
        reopened.doc().get(placement).and_then(|r| r.text(f::NOTES)),
        Some("watch the boom")
    );
    assert_eq!(
        reopened.doc().get(placement).and_then(|r| r.text(f::DESCRIPTION)),
        Some("Wide on the door")
    );
}

#[test]
fn three_devices_all_end_up_the_same() {
    let scratch = Scratch::new("three");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    let (_a, first) = mac.doc_mut().add_shot_to_scene(scene);
    let (_b, second) = mac.doc_mut().add_shot_to_scene(scene);
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");
    let mut ipad = storage::open(mac.path(), DeviceId(3)).expect("opens");

    mac.doc_mut().set(first, f::LENS, "40mm");
    phone.doc_mut().set(second, f::LENS, "27mm");
    ipad.doc_mut().set(first, f::NOTES, "handheld");
    mac.save().expect("saves");
    phone.save().expect("saves");
    ipad.save().expect("saves");

    // Everyone catches up, in whatever order they happen to.
    for _ in 0..2 {
        ipad.pull().expect("pulls");
        mac.pull().expect("pulls");
        phone.pull().expect("pulls");
    }

    let mac_print = mac.doc().store().fingerprint();
    assert_eq!(phone.doc().store().fingerprint(), mac_print);
    assert_eq!(ipad.doc().store().fingerprint(), mac_print);
    assert!(mac.doc().clashes().is_empty(), "nobody stepped on anybody");
}

#[test]
fn a_project_opened_twice_by_one_device_still_only_holds_one_copy() {
    let scratch = Scratch::new("reopen");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    mac.doc_mut().create_scene("34");
    mac.save().expect("saves");
    let path = mac.path().to_path_buf();
    drop(mac);

    // A second session on the same device, which writes a log of its own.
    let mut again = storage::open(&path, MAC).expect("opens");
    again.doc_mut().create_scene("35");
    again.save().expect("saves");

    let reopened = storage::open(&path, DeviceId(9)).expect("opens");
    assert_eq!(reopened.doc().scenes_in_order().len(), 2);
    assert!(reopened.doc().clashes().is_empty());
}

// ---- checking often, cheaply --------------------------------------------

#[test]
fn checking_costs_nothing_until_something_actually_lands() {
    let scratch = Scratch::new("cheap");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    let (_shot, placement) = mac.doc_mut().add_shot_to_scene(scene);
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");
    assert!(
        !phone.has_incoming(),
        "having just read everything, there is nothing waiting"
    );

    // The phone's own work does not look like somebody else's.
    phone.doc_mut().set(placement, f::NOTES, "watch the boom");
    phone.save().expect("saves");
    assert!(!phone.has_incoming());

    // The Mac writes.
    mac.doc_mut().set(placement, f::LENS, "40mm");
    mac.save().expect("saves");
    assert!(phone.has_incoming(), "and now there is");

    let pull = phone.pull().expect("pulls");
    assert_eq!(pull.merged, 1);
    assert!(
        !phone.has_incoming(),
        "taken in, so there is nothing waiting again"
    );
}

#[test]
fn a_pull_with_nothing_waiting_is_a_no_op() {
    let scratch = Scratch::new("noop");

    let mut mac = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    mac.doc_mut().create_scene("34");
    mac.save().expect("saves");

    let mut phone = storage::open(mac.path(), PHONE).expect("opens");
    let before = phone.doc().changes().len();

    // What the app would do on every window focus, all day.
    for _ in 0..50 {
        let pull = phone.pull().expect("pulls");
        assert!(pull.is_empty());
    }

    assert_eq!(
        phone.doc().changes().len(),
        before,
        "checking repeatedly does not grow the log"
    );
}

// ---- two machines wearing one name -------------------------------------
//
// Ref 186. The whole of sync rests on every device having a name of its own,
// and until now nothing enforced that rule or could notice when it broke. A
// Mac set up from another with Migration Assistant carries the old one's
// preferences across, name included; the Drive bridge used to have its name
// written into the program; and Claude's server worked its name out the same
// way on every machine it ran on. When two share one, a change each makes in
// the same millisecond is one stamp, and the second is dropped as a duplicate.

const SECOND_MAC: u64 = 0xBBBB_BBBB_BBBB_BBBB;
const THIS_MAC: u64 = 0xAAAA_AAAA_AAAA_AAAA;

#[test]
fn a_cloned_machine_is_noticed() {
    let scratch = Scratch::new("cloned");
    let made = storage::create_as(&scratch.0, "Daybreak", MAC, THIS_MAC).expect("creates");
    let path = made.path().to_path_buf();
    drop(made);

    // Nothing wrong yet: one machine, one name.
    let alone = storage::open_as(&path, MAC, THIS_MAC).expect("opens");
    assert!(alone.identity_clash().is_none(), "one machine is not a clash");
    drop(alone);

    // Migration Assistant has copied this Mac's preferences onto a new one, so
    // a different machine now opens the same film calling itself the same name.
    let second = storage::open_as(&path, MAC, SECOND_MAC).expect("opens");
    let clash = second.identity_clash().expect("two machines, one name");
    assert_eq!(clash.device, MAC);
    assert_eq!(clash.machines, 2);
    assert!(clash.ours, "the machine noticing is one of the two");
    assert!(
        clash.message().contains("same name"),
        "says what is wrong in words: {}",
        clash.message()
    );

    // And the original notices next time it opens, without the second one
    // having to tell it anything.
    drop(second);
    let first_again = storage::open_as(&path, MAC, THIS_MAC).expect("opens");
    assert_eq!(first_again.identity_clash().map(|c| c.machines), Some(2));
}

#[test]
fn a_second_window_is_not_a_clash() {
    // ⌘N opens another window on the same film. That is two sessions writing
    // two diaries under one name at the same moment — which is exactly what a
    // naive collision check would fire on, and it is perfectly ordinary. The
    // mark names the *machine*, so this cannot be mistaken for two of them.
    let scratch = Scratch::new("second-window");
    let made = storage::create_as(&scratch.0, "Daybreak", MAC, THIS_MAC).expect("creates");
    let path = made.path().to_path_buf();
    drop(made);

    let one = storage::open_as(&path, MAC, THIS_MAC).expect("opens");
    let two = storage::open_as(&path, MAC, THIS_MAC).expect("opens");
    assert!(one.identity_clash().is_none());
    assert!(two.identity_clash().is_none(), "a second window is not a second machine");

    // Two logs, one mark: the diaries are per session, the mark is per machine.
    let dir = path.join(package::CHANGES_DIR);
    let marks = fs::read_dir(&dir)
        .expect("changes")
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.file_name()
                .to_str()
                .map(package::is_device_mark_name)
                .unwrap_or(false)
        })
        .count();
    assert_eq!(marks, 1, "one machine leaves one mark however many windows");
}

#[test]
fn the_phone_and_the_mac_are_not_a_clash() {
    // Different names, different machines — the ordinary case, and the one
    // that must never produce a warning.
    let scratch = Scratch::new("two-devices");
    let made = storage::create_as(&scratch.0, "Daybreak", MAC, THIS_MAC).expect("creates");
    let path = made.path().to_path_buf();
    drop(made);

    let phone = storage::open_as(&path, PHONE, SECOND_MAC).expect("opens");
    assert!(phone.identity_clash().is_none());
}

#[test]
fn a_shell_that_says_nothing_claims_nothing() {
    // An older app, or a checking harness, passes no machine. It should leave
    // no mark rather than a misleading one — and must still open normally.
    let scratch = Scratch::new("silent");
    let made = storage::create(&scratch.0, "Daybreak", MAC).expect("creates");
    let path = made.path().to_path_buf();
    drop(made);

    let quiet = storage::open(&path, MAC).expect("opens");
    assert_eq!(quiet.installation(), 0);
    assert!(quiet.identity_clash().is_none());

    let dir = path.join(package::CHANGES_DIR);
    let marks = fs::read_dir(&dir)
        .expect("changes")
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.file_name()
                .to_str()
                .map(package::is_device_mark_name)
                .unwrap_or(false)
        })
        .count();
    assert_eq!(marks, 0);
}

#[test]
fn a_mark_is_invisible_to_the_rest_of_the_project() {
    // The reason it is a file of its own rather than a line in a diary: no
    // build, this one included, may mistake it for a change log.
    let scratch = Scratch::new("invisible");
    let mut made = storage::create_as(&scratch.0, "Daybreak", MAC, THIS_MAC).expect("creates");
    let scene = made.doc_mut().create_scene("34");
    made.doc_mut().set(scene, f::TITLE, "INT. KITCHEN - DAY");
    made.save().expect("saves");
    let path = made.path().to_path_buf();
    drop(made);

    let reopened = storage::open_as(&path, MAC, THIS_MAC).expect("opens");
    assert_eq!(reopened.unreadable_lines(), 0, "a mark is not an unread line");
    assert_eq!(reopened.doc().scenes_in_order().len(), 1);
}
