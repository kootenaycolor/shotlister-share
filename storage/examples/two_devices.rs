//! A day on two devices, printed.
//!
//! Run it to watch a folder behave the way a synced folder does:
//!
//! ```text
//! cargo run --example two_devices
//! ```
//!
//! It writes into a temporary folder, shows the logs both devices produced, and
//! ends on the one case that is worth a word — two people changing the same lens
//! while out of range of each other.

use std::fs;

use shotlister_engine::doc::f;
use shotlister_engine::{package, DeviceId};
use shotlister_storage as storage;

const MAC: DeviceId = DeviceId(0x9a17);
const PHONE: DeviceId = DeviceId(0x40e5);

fn main() {
    let scratch = std::env::temp_dir().join("shotlister-two-devices");
    let _ = fs::remove_dir_all(&scratch);
    fs::create_dir_all(&scratch).expect("scratch");

    // ---- the Mac, at home the night before ------------------------------
    let mut mac = storage::create(&scratch, "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    mac.doc_mut().set(scene, f::LOCATION, "JAIL CORRIDOR");
    let (_shot, placement) = mac.doc_mut().add_shot_to_scene(scene);
    mac.doc_mut()
        .set(placement, f::DESCRIPTION, "Wide, corridor, push in");
    mac.doc_mut().set(placement, f::LENS, "37mm");
    mac.save().expect("saves");
    println!("Mac wrote {}\n", mac.path().display());

    // ---- the phone opens the same folder --------------------------------
    let mut phone = storage::open(mac.path(), PHONE).expect("opens");
    println!(
        "Phone opened it and reads the lens as {:?}\n",
        phone.doc().get(placement).and_then(|r| r.text(f::LENS))
    );

    // ---- both go out of range and change the same thing -----------------
    mac.doc_mut().set(placement, f::LENS, "40mm");
    mac.doc_mut().set(placement, f::NOTES, "watch the boom");
    mac.save().expect("saves");

    phone.doc_mut().set(placement, f::LENS, "50mm");
    phone.save().expect("saves");

    // ---- they meet ------------------------------------------------------
    let pull = phone.pull().expect("pulls");
    println!(
        "Phone pulled {} changes from {} other device(s).",
        pull.merged,
        pull.devices.len()
    );

    if pull.clashes.is_empty() {
        println!("Nothing worth saying.");
    } else {
        for clash in &pull.clashes {
            println!(
                "\n  ⚠  {}\n",
                phone.doc().clash_message(clash, |device| match device {
                    MAC => "This Mac".to_string(),
                    PHONE => "iPhone".to_string(),
                    other => format!("device {}", other.0),
                })
            );
        }
    }

    println!(
        "The note the Mac made arrived without a word: {:?}",
        phone.doc().get(placement).and_then(|r| r.text(f::NOTES))
    );

    // ---- what is actually on disk ---------------------------------------
    println!("\n--- the change files ---");
    let changes = mac.path().join(package::CHANGES_DIR);
    let mut logs: Vec<_> = fs::read_dir(&changes)
        .expect("changes")
        .flatten()
        .map(|entry| entry.path())
        .collect();
    logs.sort();
    for log in logs {
        println!("\n{}", log.file_name().unwrap().to_string_lossy());
        for line in fs::read_to_string(&log).expect("reads").lines() {
            println!("  {}", line.replace('\t', " ⇥ "));
        }
    }

    let _ = fs::remove_dir_all(&scratch);
}
