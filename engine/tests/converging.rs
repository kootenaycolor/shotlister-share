//! Merge, put under pressure.
//!
//! The other tests check merge with two or three changes and a known answer.
//! These generate hundreds of edits across several devices, exchange them in
//! scrambled orders, and check the properties that have to hold *whatever*
//! happened — because the real failure mode is not the case somebody thought of,
//! it is the one nobody did.
//!
//! The generator is deterministic. A failure here can be reproduced exactly by
//! its seed rather than being a story about a test that went red once.

use shotlister_engine::store::Change;
use shotlister_engine::{DeviceId, Doc, Id};

/// A small reproducible generator. No dependency, and a seed is enough to get
/// the same run back.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        // xorshift64*
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn below(&mut self, limit: usize) -> usize {
        if limit == 0 {
            0
        } else {
            (self.next() % limit as u64) as usize
        }
    }

    fn shuffle<T>(&mut self, items: &mut [T]) {
        for index in (1..items.len()).rev() {
            let other = self.below(index + 1);
            items.swap(index, other);
        }
    }
}

const LENSES: [&str; 5] = ["20.7mm", "27mm", "37mm", "47mm", "57mm"];
const SIZES: [&str; 4] = ["W", "M/OTS", "CU", "TS"];

/// Make a device do a plausible run of work.
fn work(doc: &mut Doc, rng: &mut Rng, rounds: usize, scenes: &mut Vec<Id>, shots: &mut Vec<Id>) {
    for _ in 0..rounds {
        match rng.below(8) {
            0 => {
                let number = format!("{}", rng.below(90) + 10);
                scenes.push(doc.create_scene(&number));
            }
            1 | 2 => {
                if let Some(scene) = scenes.get(rng.below(scenes.len().max(1))).copied() {
                    let (shot, _) = doc.add_shot_to_scene(scene);
                    shots.push(shot);
                }
            }
            3 | 4 => {
                if let Some(shot) = shots.get(rng.below(shots.len().max(1))).copied() {
                    let lens = LENSES[rng.below(LENSES.len())];
                    doc.set_vocab_field(shot, "lens", lens);
                }
            }
            5 => {
                if let Some(shot) = shots.get(rng.below(shots.len().max(1))).copied() {
                    let size = SIZES[rng.below(SIZES.len())];
                    doc.set_vocab_field(shot, "size", size);
                }
            }
            6 => {
                if let Some(shot) = shots.get(rng.below(shots.len().max(1))).copied() {
                    doc.strike(shot, rng.below(2) == 0);
                }
            }
            _ => {
                if shots.len() > 3 {
                    let victim = shots.remove(rng.below(shots.len()));
                    doc.delete(victim);
                }
            }
        }
    }
}

fn fingerprint(doc: &Doc) -> String {
    doc.store().fingerprint()
}

// ---- the properties ----------------------------------------------------

#[test]
fn devices_that_see_the_same_work_agree_however_it_arrives() {
    for seed in 1..=25u64 {
        let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15));

        // Three devices, each doing their own work from a shared start.
        let mut origin = Doc::new(DeviceId(0));
        origin.create_project("Daybreak");
        let mut scenes = Vec::new();
        let mut shots = Vec::new();
        work(&mut origin, &mut rng, 12, &mut scenes, &mut shots);
        let base: Vec<Change> = origin.changes().to_vec();

        let mut streams: Vec<Vec<Change>> = Vec::new();
        for device in 1..=3u64 {
            let mut doc = Doc::new(DeviceId(device));
            doc.merge(base.clone());
            let mut own_scenes = scenes.clone();
            let mut own_shots = shots.clone();
            work(&mut doc, &mut rng, 20, &mut own_scenes, &mut own_shots);
            streams.push(doc.changes().to_vec());
        }

        // Everybody eventually sees everything, in whatever order it reaches them.
        let mut fingerprints = Vec::new();
        for device in 0..4u64 {
            let mut doc = Doc::new(DeviceId(100 + device));
            let mut all: Vec<Change> = streams.iter().flatten().cloned().collect();
            rng.shuffle(&mut all);
            doc.merge(all);
            fingerprints.push(fingerprint(&doc));
        }

        for other in &fingerprints[1..] {
            assert_eq!(
                &fingerprints[0], other,
                "devices disagreed after merging the same work (seed {seed})"
            );
        }
    }
}

#[test]
fn seeing_the_same_work_twice_changes_nothing() {
    for seed in 1..=15u64 {
        let mut rng = Rng(seed.wrapping_mul(0xD1B5_4A32_D192_ED03));

        let mut doc = Doc::new(DeviceId(1));
        doc.create_project("Daybreak");
        let mut scenes = Vec::new();
        let mut shots = Vec::new();
        work(&mut doc, &mut rng, 25, &mut scenes, &mut shots);
        let changes: Vec<Change> = doc.changes().to_vec();

        let mut once = Doc::new(DeviceId(2));
        once.merge(changes.clone());

        let mut thrice = Doc::new(DeviceId(3));
        thrice.merge(changes.clone());
        thrice.merge(changes.clone());
        let mut scrambled = changes;
        rng.shuffle(&mut scrambled);
        thrice.merge(scrambled);

        // A transport that redelivers, or a file read twice, must be harmless.
        assert_eq!(fingerprint(&once), fingerprint(&thrice), "seed {seed}");
    }
}

#[test]
fn arriving_in_pieces_is_the_same_as_arriving_at_once() {
    for seed in 1..=15u64 {
        let mut rng = Rng(seed.wrapping_mul(0xA076_1D64_78BD_642F));

        let mut doc = Doc::new(DeviceId(1));
        doc.create_project("Daybreak");
        let mut scenes = Vec::new();
        let mut shots = Vec::new();
        work(&mut doc, &mut rng, 30, &mut scenes, &mut shots);
        let mut changes: Vec<Change> = doc.changes().to_vec();
        rng.shuffle(&mut changes);

        let mut whole = Doc::new(DeviceId(2));
        whole.merge(changes.clone());

        // The same changes dribbling in over a bad connection.
        let mut piecemeal = Doc::new(DeviceId(3));
        let mut rest = changes.as_slice();
        while !rest.is_empty() {
            let take = (rng.below(7) + 1).min(rest.len());
            piecemeal.merge(rest[..take].to_vec());
            rest = &rest[take..];
        }

        assert_eq!(fingerprint(&whole), fingerprint(&piecemeal), "seed {seed}");
    }
}

#[test]
fn the_log_alone_is_enough_to_rebuild_the_state() {
    for seed in 1..=15u64 {
        let mut rng = Rng(seed.wrapping_mul(0x6C62_272E_07BB_0142));

        let mut doc = Doc::new(DeviceId(1));
        doc.create_project("Daybreak");
        let mut scenes = Vec::new();
        let mut shots = Vec::new();
        work(&mut doc, &mut rng, 40, &mut scenes, &mut shots);

        // State is a cache. Throwing it away and replaying must be lossless,
        // which is what makes the file format a log rather than a snapshot.
        let mut rebuilt = Doc::new(DeviceId(2));
        rebuilt.merge(doc.changes().to_vec());

        assert_eq!(fingerprint(&doc), fingerprint(&rebuilt), "seed {seed}");
    }
}

#[test]
fn a_log_survives_being_written_and_read_whatever_is_in_it() {
    use shotlister_engine::format::{decode_log, encode_log};
    use shotlister_engine::FORMAT_VERSION;

    for seed in 1..=15u64 {
        let mut rng = Rng(seed.wrapping_mul(0x8329_2A63_9FA9_1B71));

        let mut doc = Doc::new(DeviceId(1));
        doc.create_project("Daybreak");
        let mut scenes = Vec::new();
        let mut shots = Vec::new();
        work(&mut doc, &mut rng, 30, &mut scenes, &mut shots);

        let text = encode_log(FORMAT_VERSION, doc.changes(), &[]);
        let log = decode_log(&text).expect("valid log");
        assert!(
            log.preserved.is_empty(),
            "we should be able to read what we wrote (seed {seed})"
        );

        let mut reopened = Doc::new(DeviceId(2));
        reopened.merge(log.changes);

        assert_eq!(fingerprint(&doc), fingerprint(&reopened), "seed {seed}");
    }
}

#[test]
fn derived_values_agree_across_devices_too() {
    // Fingerprints compare stored fields; numbers and headings are computed, and
    // two devices that agree on the facts must also agree on the reading.
    for seed in 1..=10u64 {
        let mut rng = Rng(seed.wrapping_mul(0x2545_F491_4F6C_DD1D));

        let mut mac = Doc::new(DeviceId(1));
        mac.create_project("Daybreak");
        let mut scenes = Vec::new();
        let mut shots = Vec::new();
        work(&mut mac, &mut rng, 30, &mut scenes, &mut shots);

        let mut phone = Doc::new(DeviceId(2));
        let mut changes: Vec<Change> = mac.changes().to_vec();
        rng.shuffle(&mut changes);
        phone.merge(changes);

        let mac_numbers: Vec<String> = mac
            .all_placements()
            .iter()
            .filter_map(|p| mac.display_number(*p))
            .collect();
        let phone_numbers: Vec<String> = phone
            .all_placements()
            .iter()
            .filter_map(|p| phone.display_number(*p))
            .collect();

        assert_eq!(mac_numbers, phone_numbers, "seed {seed}");
        assert!(!mac_numbers.is_empty(), "the generator should do something");
    }
}

// ---- a log that is merged twice ----------------------------------------

/// **Merging a log this document already holds must not lengthen its log.**
///
/// Ref filed 2026-09-08, from his own *Call Her Back*: one change file had grown
/// to 732,702 bytes holding 649 distinct changes — the same set written out
/// about eleven times. `Store::apply` pushed every change it was handed onto
/// the log whatever happened to it, so re-merging a log the document already
/// had duplicated every change in it. `Project::save` then wrote the surplus
/// back out, the file grew, and the bigger file was merged again on the next
/// open. Unbounded, and it ended with the relay refusing the file for ever
/// because its copy of that name no longer matched.
///
/// The state was always right — `apply` settles records by stamp and a repeat
/// changes nothing. It is the *log* that grew, and the log is what is written
/// to disk and sent to the relay.
#[test]
fn merging_the_same_log_twice_adds_nothing() {
    let mut doc = Doc::new(DeviceId(1));
    let scene = doc.create_scene("34");
    doc.set(scene, "slug", "INT. KITCHEN - DAY");
    doc.set(scene, "slug", "INT. KITCHEN - NIGHT");

    let written: Vec<Change> = doc.changes().to_vec();
    let before = written.len();
    assert!(before >= 3, "the fixture should make a few changes");

    // The same log, arriving again — what a sync does every time a device
    // fetches back a log it already has.
    doc.merge(written.clone());
    assert_eq!(
        doc.changes().len(),
        before,
        "merging a log the document already holds duplicated its changes"
    );

    // And a third time, because growth compounds: this is the case that ran
    // away on his Mac.
    doc.merge(written.clone());
    doc.merge(doc.changes().to_vec());
    assert_eq!(
        doc.changes().len(),
        before,
        "the log grows every time it is merged with itself"
    );
}
