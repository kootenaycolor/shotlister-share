//! The same day as `storage`'s `two_devices`, but with a relay in the middle
//! instead of a shared folder.
//!
//! This is the proof the whole idea rests on: **nothing about merging changes.**
//! Two devices that never see each other's disk end up agreeing, and the one
//! case worth a word — two people changing the same lens while out of range —
//! is still noticed, still explained, and still nobody's edit is lost.
//!
//! It needs a relay running on this machine. `remote/checks.sh` starts one and
//! runs this against it, which is the way to run it:
//!
//! ```text
//! remote/checks.sh
//! ```

use std::fs;

use shotlister_engine::doc::f;
use shotlister_engine::DeviceId;
use shotlister_remote::courier::{self, Relay};
use shotlister_storage as storage;

const MAC: DeviceId = DeviceId(0x9a17);
const PHONE: DeviceId = DeviceId(0x40e5);
const PROJECT: &str = "00000000000000000000000000000042";

fn main() {
    let base = std::env::var("RELAY").unwrap_or_else(|_| "http://127.0.0.1:8799".to_string());
    let token = std::env::var("RELAY_TOKEN").unwrap_or_else(|_| "checking-token-not-a-secret".to_string());
    let relay = Relay::new(&base, &token, PROJECT);

    let scratch = std::env::temp_dir().join("shotlister-over-a-relay");
    let _ = fs::remove_dir_all(&scratch);
    fs::create_dir_all(&scratch).expect("scratch");

    // ---- the Mac, at home the night before ------------------------------
    let mut mac = storage::create(&scratch.join("mac"), "Daybreak", MAC).expect("creates");
    let scene = mac.doc_mut().create_scene("34");
    mac.doc_mut().set(scene, f::LOCATION, "JAIL CORRIDOR");
    let (_shot, placement) = mac.doc_mut().add_shot_to_scene(scene);
    mac.doc_mut()
        .set(placement, f::DESCRIPTION, "Wide, corridor, push in");
    mac.doc_mut().set(placement, f::LENS, "37mm");
    mac.save().expect("saves");

    let sent = courier::sync(&mut mac, &relay).expect("the Mac pushes");
    println!("Mac sent {} log(s) up.", sent.sent_logs);

    // ---- a phone that has never had this film ---------------------------
    //
    // Not a copy of a folder and not a wait — it asks the relay and builds it.
    let mut phone = courier::clone_project(&relay, &scratch.join("phone"), PHONE, 0x51de)
        .expect("the phone brings it down");
    println!(
        "Phone had never seen this film. It now reads the lens as {:?}",
        phone.doc().get(placement).and_then(|r| r.text(f::LENS))
    );
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        Some("37mm"),
        "the phone should have the Mac's lens"
    );

    // ---- both go out of range and change the same thing -----------------
    mac.doc_mut().set(placement, f::LENS, "40mm");
    mac.doc_mut().set(placement, f::NOTES, "watch the boom");
    mac.save().expect("saves");

    phone.doc_mut().set(placement, f::LENS, "50mm");
    phone.save().expect("saves");

    // ---- the Mac gets signal first --------------------------------------
    courier::sync(&mut mac, &relay).expect("the Mac pushes again");

    // ---- and then the phone does ----------------------------------------
    let met = courier::sync(&mut phone, &relay).expect("the phone syncs");
    println!(
        "\nPhone took in {} change(s) across {} log(s).",
        met.merged, met.received_logs
    );

    let clashes = phone.doc().clashes();
    assert_eq!(clashes.len(), 1, "one lens, changed twice, is one disagreement");
    for clash in &clashes {
        println!(
            "\n  ⚠  {}\n",
            phone.doc().clash_message(clash, |device| match device {
                MAC => "This Mac".to_string(),
                PHONE => "iPhone".to_string(),
                other => format!("device {}", other.0),
            })
        );
    }

    // **Nothing was lost.** The note the Mac made travelled even though the
    // lens is the thing being argued about — a disagreement is per field, and
    // the rest of the work simply arrives.
    assert_eq!(
        phone.doc().get(placement).and_then(|r| r.text(f::NOTES)),
        Some("watch the boom"),
        "the Mac's note should have arrived alongside the disagreement"
    );

    // ---- and the Mac hears the phone's side -----------------------------
    let back = courier::sync(&mut mac, &relay).expect("the Mac syncs");
    println!("Mac took in {} change(s) back.", back.merged);
    assert_eq!(
        mac.doc().clashes().len(),
        1,
        "both devices report the same disagreement, from the same log"
    );

    // ---- settling it ----------------------------------------------------
    //
    // Taking a side is an ordinary edit with knowledge of both, so it wins and
    // the disagreement is gone because it was decided, not because it was hidden.
    let clash = phone.doc().clashes()[0].clone();
    phone.doc_mut().take_theirs(&clash);
    phone.save().expect("saves");
    courier::sync(&mut phone, &relay).expect("the phone pushes the decision");
    courier::sync(&mut mac, &relay).expect("the Mac hears it");

    println!(
        "\nSettled. Both now read the lens as {:?} and {:?}, with {} and {} disagreements left.",
        mac.doc().get(placement).and_then(|r| r.text(f::LENS)),
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        mac.doc().clashes().len(),
        phone.doc().clashes().len(),
    );
    assert_eq!(mac.doc().clashes().len(), 0);
    assert_eq!(phone.doc().clashes().len(), 0);
    assert_eq!(
        mac.doc().get(placement).and_then(|r| r.text(f::LENS)),
        phone.doc().get(placement).and_then(|r| r.text(f::LENS)),
        "two devices that took in the same changes must read the same"
    );

    println!("\nBoth devices agree, over a relay, having never shared a folder.");
}
