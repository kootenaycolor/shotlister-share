//! **Tidying the folder must not stop the day's work reaching the relay.**
//!
//! Ref 192 folds this device's settled logs into one and deletes the rest. The
//! relay has never been told, and it holds two rules that turn that tidying
//! into a jam:
//!
//! - a log may only ever grow, so the folded one is refused outright — and the
//!   refusal used to end the whole run, holding back every log behind it;
//! - a log the relay has and this device has not is fetched, so the deleted
//!   ones come straight back and are folded again on the next launch.
//!
//! On 2026-09-04 that happened to *Call Her Back*: an afternoon of work sat on
//! his Mac while the web drew the film as it had been at 5:14pm.
//!
//! This plays the whole thing out against a real relay. `remote/checks.sh`
//! starts one and runs it, which is the way to run it.

use std::fs;

use shotlister_engine::package;
use shotlister_engine::DeviceId;
use shotlister_remote::courier::{self, Relay};
use shotlister_remote::local;
use shotlister_storage as storage;

const MAC: DeviceId = DeviceId(0x9a17);
/// Sharing the folder over iCloud, and never folding anything of the Mac's.
const PHONE: DeviceId = DeviceId(0x40e5);
const PROJECT: &str = "00000000000000000000000000000192";

/// Make every one of this device's logs old enough to fold, by renaming them to
/// sessions long before anything was ever shot. The name carries the session,
/// which is the whole of what "old" means to a fold.
fn age_the_logs(path: &std::path::Path, device: DeviceId) {
    let dir = path.join(package::CHANGES_DIR);
    let mut names: Vec<_> = fs::read_dir(&dir)
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
        if wrote != device || was < 1_000_000 {
            continue;
        }
        fs::rename(&old, dir.join(package::log_name(device, session))).expect("renames");
        session += 1;
    }
}

fn logs_here(path: &std::path::Path) -> Vec<String> {
    let mut found: Vec<String> = fs::read_dir(path.join(package::CHANGES_DIR))
        .expect("changes")
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().to_string())
        .filter(|name| package::is_log_name(name))
        .collect();
    found.sort();
    found
}

fn main() {
    let base = std::env::var("RELAY").unwrap_or_else(|_| "http://127.0.0.1:8798".to_string());
    let token =
        std::env::var("RELAY_TOKEN").unwrap_or_else(|_| "checking-token-not-a-secret".to_string());
    let relay = Relay::new(&base, &token, PROJECT);

    let scratch = std::env::temp_dir().join("shotlister-fold-and-relay");
    let _ = fs::remove_dir_all(&scratch);
    fs::create_dir_all(&scratch).expect("scratch");
    let path = scratch.join("mac");

    // ---- a fortnight of launches, each one its own log ------------------
    let mut project = storage::create(&path, "Call Her Back", MAC).expect("creates");
    project.doc_mut().create_scene("1");
    project.save().expect("saves");
    let path = project.path().to_path_buf();
    drop(project);

    for number in 2..14 {
        // A log is named after the millisecond its session started, so a dozen
        // launches inside one millisecond are one log. A real fortnight has
        // plenty of daylight between its launches; this is how you get a
        // fortnight's worth of files in a fraction of a second.
        std::thread::sleep(std::time::Duration::from_millis(2));
        let mut project = storage::open(&path, MAC).expect("opens");
        project.doc_mut().create_scene(&number.to_string());
        project.save().expect("saves");
    }

    // **They settle where the relay can see them.** Aged first and pushed
    // afterwards, so the names the relay holds are the very names the fold is
    // about to retire — which is the whole situation and the only way to test
    // it. The push is the phone's, sharing the folder over iCloud: it carries
    // the Mac's logs onward and folds nothing of theirs, exactly as it would on
    // a real morning.
    age_the_logs(&path, MAC);
    let mut phone = storage::open(&path, PHONE).expect("the phone opens the same folder");
    courier::sync(&mut phone, &relay).expect("the phone carries them up");
    drop(phone);

    let before = logs_here(&path);
    assert!(before.len() > 8, "a fortnight leaves a pile: {}", before.len());
    let held = relay.inventory(&scratch).expect("the relay says what it has");
    for name in &before {
        assert!(
            held.logs.iter().any(|e| &e.name == name),
            "the relay should be holding this already: {name}"
        );
    }
    println!("{} logs, every one of them on the relay.", before.len());

    // ---- and the next launch tidies them up -----------------------------
    let mut project = storage::open(&path, MAC).expect("opens — and folds");
    let after = logs_here(&path);
    assert!(
        after.len() < before.len(),
        "the fold should have left fewer files: {} then {}",
        before.len(),
        after.len()
    );
    println!("Folded to {} — and the relay still holds all {}.", after.len(), before.len());

    let folded = local::folded(&path);
    assert!(!folded.rewritten.is_empty(), "the fold should say what it wrote over");
    assert!(!folded.retired.is_empty(), "and what it retired");
    for name in folded.retired.iter().chain(folded.rewritten.iter()) {
        assert!(
            held.logs.iter().any(|e| &e.name == name),
            "this check is only worth running on logs the relay already holds: {name}"
        );
    }

    // ---- and then he does an afternoon's work ---------------------------
    let scene = project.doc_mut().create_scene("14");
    project.doc_mut().set(scene, "heading", "EXT. MALIBU DIRT ROAD - DAY");
    project.save().expect("saves");

    // **The whole point.** Before this was fixed the relay refused the folded
    // log — a log may only ever grow — and the refusal ended the run, so the
    // afternoon never left the Mac.
    let report = courier::sync(&mut project, &relay).expect("the fold must not jam the relay");
    println!(
        "Sync after the fold: {} up, {} down.",
        report.sent_logs, report.received_logs
    );

    // ---- what the relay ended up holding --------------------------------
    let held = relay.inventory(&scratch).expect("the relay says what it has");
    let names: Vec<&str> = held.logs.iter().map(|e| e.name.as_str()).collect();
    for name in &folded.rewritten {
        assert!(
            names.contains(&name.as_str()),
            "the folded log should be on the relay: {name}"
        );
        let here = fs::metadata(path.join(package::CHANGES_DIR).join(name))
            .expect("the folded log")
            .len();
        let there = held
            .logs
            .iter()
            .find(|e| &e.name == name)
            .map(|e| e.size)
            .unwrap_or(0);
        assert_eq!(there, here, "and it should be the folded copy, not the old one");
    }

    // ---- and the retired ones stay retired ------------------------------
    //
    // The relay still has them; nothing was deleted from anybody's server. What
    // changed is that this device no longer asks for them back, so the folder
    // stays tidy instead of filling up again on the next sync.
    let settled = logs_here(&path);
    for name in &folded.retired {
        assert!(
            !settled.contains(name),
            "a retired log came back from the relay: {name}"
        );
    }
    println!("{} retired logs stayed retired.", folded.retired.len());

    // ---- twice more, to be sure it has settled --------------------------
    for _ in 0..2 {
        drop(project);
        project = storage::open(&path, MAC).expect("opens");
        courier::sync(&mut project, &relay).expect("and it keeps working");
    }
    assert_eq!(
        logs_here(&path),
        settled,
        "opening and syncing again should change nothing"
    );
    println!("\nOpened and synced twice more. Nothing moved, nothing grew.");
}
