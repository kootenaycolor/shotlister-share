//! Two devices, one list.
//!
//! The merge itself is covered in `converging.rs` — that everything lands, in any
//! order, identically. This is about the one thing the merge cannot decide on its
//! own: whether the value that lost was somebody's considered edit or just an
//! older keystroke.

use shotlister_engine::doc::f;
use shotlister_engine::format::{decode_log, encode_log};
use shotlister_engine::{DeviceId, Doc, Id, Value};

/// A shot on two devices that have both seen everything up to that point —
/// which is where the day starts before anyone goes out of range.
/// The lens lives on the shot; the letter lives on its placement. Both ids come
/// back because a clash is about the first and is named after the second.
fn in_step() -> (Doc, Doc, Id) {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Daybreak");
    let scene = mac.create_scene("34");
    let (shot, _placement) = mac.add_shot_to_scene(scene);
    mac.set(shot, f::LENS, "37mm");

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mac.changes().to_vec());

    (mac, phone, shot)
}

#[test]
fn nothing_to_report_when_the_day_has_gone_normally() {
    let (mac, _phone, _placement) = in_step();
    assert!(mac.clashes().is_empty());
}

#[test]
fn two_devices_editing_the_same_cell_out_of_range_is_reported() {
    let (mut mac, mut phone, placement) = in_step();

    // Out of range of each other, both make a call about the same lens.
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");

    // They meet.
    let from_phone = phone.changes().to_vec();
    let from_mac = mac.changes().to_vec();
    mac.merge(from_phone);
    phone.merge(from_mac);

    let clashes = mac.clashes();
    assert_eq!(clashes.len(), 1, "one cell, one clash");
    let clash = &clashes[0];
    assert_eq!(clash.record, placement);
    assert_eq!(clash.field, f::LENS);

    // Whichever won, the other value is the one being reported, and it is the
    // one that is not on screen.
    let on_screen = mac.get(placement).unwrap().text(f::LENS).unwrap();
    assert_eq!(clash.kept, Value::text(on_screen));
    assert_ne!(clash.kept, clash.other);
    assert_ne!(clash.kept_device(), clash.other_device());

    // Both devices reach the same conclusion, because it is read from the log
    // rather than from who pulled from whom.
    assert_eq!(phone.clashes(), clashes);
}

#[test]
fn editing_after_seeing_the_other_value_is_ordinary_work() {
    let (mut mac, mut phone, placement) = in_step();

    mac.set(placement, f::LENS, "40mm");
    // The phone hears about it before deciding otherwise. That is a person
    // overruling a value they have seen, which is not a disagreement.
    phone.merge(mac.changes().to_vec());
    phone.set(placement, f::LENS, "50mm");

    mac.merge(phone.changes().to_vec());

    assert_eq!(mac.get(placement).unwrap().text(f::LENS), Some("50mm"));
    assert!(
        mac.clashes().is_empty(),
        "seeing a value and then changing it is not a clash"
    );
}

#[test]
fn different_fields_never_clash() {
    let (mut mac, mut phone, placement) = in_step();

    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::DESCRIPTION, "Wide on the door");

    mac.merge(phone.changes().to_vec());

    assert!(mac.clashes().is_empty());
    assert_eq!(mac.get(placement).unwrap().text(f::LENS), Some("40mm"));
    assert_eq!(
        mac.get(placement).unwrap().text(f::DESCRIPTION),
        Some("Wide on the door")
    );
}

#[test]
fn agreeing_is_not_disagreeing() {
    let (mut mac, mut phone, placement) = in_step();

    // Both had the same thought at the same time. There is nothing to tell
    // anybody: the value they both wanted is the value that is there.
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "40mm");

    mac.merge(phone.changes().to_vec());

    assert!(mac.clashes().is_empty());
    assert_eq!(mac.get(placement).unwrap().text(f::LENS), Some("40mm"));
}

#[test]
fn deciding_settles_it_and_leaves_the_decision_in_the_log() {
    let (mut mac, mut phone, placement) = in_step();

    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    let clash = mac.clashes()[0].clone();
    let rejected = clash.other.clone();

    mac.take_theirs(&clash);

    assert_eq!(
        mac.get(placement).unwrap().get(f::LENS),
        Some(&rejected),
        "the value we chose is the value that is there"
    );
    assert!(
        mac.clashes().is_empty(),
        "a decision made in knowledge of both sides ends the disagreement"
    );

    // And it is a normal edit, so it can be taken back like any other.
    assert!(mac.can_undo());
}

#[test]
fn keeping_your_own_value_settles_it_too() {
    let (mut mac, mut phone, placement) = in_step();

    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    let clash = mac.clashes()[0].clone();
    let kept = clash.kept.clone();
    mac.keep_mine(&clash);

    assert_eq!(mac.get(placement).unwrap().get(f::LENS), Some(&kept));
    assert!(mac.clashes().is_empty());
}

#[test]
fn a_third_device_that_missed_the_settlement_clashes_again() {
    let (mut mac, mut phone, placement) = in_step();

    let mut ipad = Doc::new(DeviceId(3));
    ipad.merge(mac.changes().to_vec());

    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());
    let clash = mac.clashes()[0].clone();
    mac.keep_mine(&clash);
    assert!(mac.clashes().is_empty());

    // The iPad was never in the room for any of it.
    ipad.set(placement, f::LENS, "27mm");
    mac.merge(ipad.changes().to_vec());

    assert_eq!(mac.clashes().len(), 1, "a new voice, a new disagreement");
    assert!(mac
        .clashes()
        .iter()
        .any(|c| c.kept == Value::text("27mm") || c.other == Value::text("27mm")));
}

#[test]
fn a_deleted_shot_stops_being_worth_arguing_about() {
    let (mut mac, mut phone, placement) = in_step();

    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());
    assert_eq!(mac.clashes().len(), 1);

    mac.delete(placement);
    assert!(
        mac.clashes().is_empty(),
        "nobody needs telling about a lens on a shot that is gone"
    );
}

#[test]
fn a_log_from_a_build_that_recorded_nothing_accuses_nobody() {
    let (mut mac, mut phone, placement) = in_step();
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());
    assert_eq!(mac.clashes().len(), 1);

    // Strip the watermark lines, which is exactly what a log written before
    // they existed looks like.
    let text = encode_log(1, mac.changes(), &[]);
    let older: String = text
        .lines()
        .filter(|line| !line.starts_with("W\t"))
        .collect::<Vec<_>>()
        .join("\n");

    let mut read_back = Doc::new(DeviceId(9));
    read_back.merge(decode_log(&older).expect("decodes").changes);

    assert!(
        read_back.clashes().is_empty(),
        "with nothing recorded about what was known, nothing is claimed"
    );
    assert_eq!(
        read_back.get(placement).unwrap().text(f::LENS),
        mac.get(placement).unwrap().text(f::LENS),
        "and the list itself is unaffected"
    );
}

#[test]
fn the_watermark_survives_a_trip_through_a_file() {
    let (mut mac, mut phone, placement) = in_step();
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    let text = encode_log(1, mac.changes(), &[]);
    let mut reopened = Doc::new(DeviceId(9));
    reopened.merge(decode_log(&text).expect("decodes").changes);

    assert_eq!(
        reopened.clashes(),
        mac.clashes(),
        "a disagreement is still there tomorrow morning"
    );
}

#[test]
fn shuffling_the_lines_of_a_log_does_not_change_what_it_means() {
    let (mut mac, mut phone, placement) = in_step();
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    let text = encode_log(1, mac.changes(), &[]);
    let mut lines: Vec<&str> = text.lines().collect();
    let header = lines.remove(0);
    lines.reverse();
    let shuffled = format!("{header}\n{}", lines.join("\n"));

    let mut reopened = Doc::new(DeviceId(9));
    reopened.merge(decode_log(&shuffled).expect("decodes").changes);

    assert_eq!(reopened.clashes(), mac.clashes());
}

#[test]
fn the_message_names_the_shot_the_field_and_both_values() {
    let (mut mac, mut phone, placement) = in_step();
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    let clash = mac.clashes()[0].clone();
    let message = mac.clash_message(&clash, |device| {
        if device == DeviceId(1) { "This Mac".to_string() } else { "iPhone".to_string() }
    });

    assert!(message.contains("34A"), "the shot by its number: {message}");
    assert!(message.contains("lens"), "the field: {message}");
    assert!(message.contains("40mm") && message.contains("50mm"));
    assert!(message.contains("This Mac") && message.contains("iPhone"));
    assert!(
        message.contains("Nothing was lost"),
        "and the reassurance that is actually true: {message}"
    );
}

#[test]
fn a_cell_can_be_asked_whether_it_is_in_disagreement() {
    let (mut mac, mut phone, placement) = in_step();
    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    assert!(mac.field_has_clash(placement, f::LENS));
    assert!(!mac.field_has_clash(placement, f::DESCRIPTION));
    assert_eq!(mac.clashes_on(placement).len(), 1);
    assert_eq!(mac.clash_count(), 1);
}

#[test]
fn reordering_shots_on_two_devices_is_not_worth_a_word() {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Daybreak");
    let scene = mac.create_scene("34");
    let (_a, first) = mac.add_shot_to_scene(scene);
    let (_b, second) = mac.add_shot_to_scene(scene);

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mac.changes().to_vec());

    // Both tidy the same scene while out of range. They will land in one order
    // or the other and nobody wants a banner about it.
    mac.move_in_scene_to(second, 0);
    phone.move_in_scene_to(first, 1);
    mac.merge(phone.changes().to_vec());

    assert!(
        mac.clashes().is_empty(),
        "a sort position is the app's bookkeeping, not a decision somebody made: {:?}",
        mac.clashes().iter().map(|c| c.field.clone()).collect::<Vec<_>>()
    );
}

#[test]
fn the_list_is_identical_on_both_devices_however_the_clash_fell() {
    let (mut mac, mut phone, placement) = in_step();
    mac.set(placement, f::LENS, "40mm");
    mac.set(placement, f::DESCRIPTION, "Wide on the door");
    phone.set(placement, f::LENS, "50mm");

    let from_phone = phone.changes().to_vec();
    let from_mac = mac.changes().to_vec();
    mac.merge(from_phone);
    phone.merge(from_mac);

    assert_eq!(
        mac.store().fingerprint(),
        phone.store().fingerprint(),
        "reporting a disagreement never means the two sides differ"
    );
}

/// The letters must not move because of a merge, whichever way the clash fell.
#[test]
fn a_clash_does_not_disturb_the_numbering() {
    let (mut mac, mut phone, placement) = in_step();
    let before = mac.display_number(placement);

    mac.set(placement, f::LENS, "40mm");
    phone.set(placement, f::LENS, "50mm");
    mac.merge(phone.changes().to_vec());

    assert_eq!(mac.display_number(placement), before);
}

// ---- two shots reaching for the same letter -----------------------------

/// The failure last-writer-wins cannot see. Each field settles correctly and the
/// two devices agree exactly — on a scene with two shots called 34B.
#[test]
fn two_devices_adding_a_shot_out_of_range_can_land_on_one_letter() {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Daybreak");
    // Locked, so letters are fixed and nothing quietly reflows underneath.
    let day = mac.create_day();
    mac.set(day, f::DATE, "2026-09-12");
    mac.set_today(Some("2026-09-12"));

    let scene = mac.create_scene("34");
    mac.add_shot_to_scene(scene);

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mac.changes().to_vec());
    phone.set_today(Some("2026-09-12"));

    assert!(mac.letters_are_locked() && phone.letters_are_locked());

    // Each adds a shot to scene 34 with no way of knowing about the other.
    mac.add_shot_to_scene(scene);
    phone.add_shot_to_scene(scene);

    let from_phone = phone.changes().to_vec();
    let from_mac = mac.changes().to_vec();
    mac.merge(from_phone);
    phone.merge(from_mac);

    assert_eq!(
        mac.store().fingerprint(),
        phone.store().fingerprint(),
        "the devices agree — that is not the problem"
    );

    let collisions = mac.letter_collisions();
    assert_eq!(collisions.len(), 1, "and they agree on a duplicate letter");
    assert_eq!(collisions[0].scene, scene);
    assert_eq!(collisions[0].placements.len(), 2);
    assert_eq!(phone.letter_collisions(), collisions);
}

#[test]
fn the_first_claim_keeps_its_letter_and_the_later_one_moves() {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Daybreak");
    let day = mac.create_day();
    mac.set(day, f::DATE, "2026-09-12");
    mac.set_today(Some("2026-09-12"));
    let scene = mac.create_scene("34");
    mac.add_shot_to_scene(scene);

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mac.changes().to_vec());
    phone.set_today(Some("2026-09-12"));

    mac.add_shot_to_scene(scene);
    phone.add_shot_to_scene(scene);
    mac.merge(phone.changes().to_vec());

    let collision = mac.letter_collisions()[0].clone();
    let first_claim = collision.placements[0];
    let kept = mac
        .get(first_claim)
        .and_then(|r| r.text(f::LETTER))
        .unwrap()
        .to_string();

    let moved = mac.resolve_letter_collisions(scene);

    assert_eq!(moved, 1, "one shot moves, not both");
    assert_eq!(
        mac.get(first_claim).and_then(|r| r.text(f::LETTER)),
        Some(kept.as_str()),
        "a number somebody may already have written down does not move"
    );
    assert!(mac.letter_collisions().is_empty());

    // Every shot in the scene now has a letter of its own.
    let letters: Vec<String> = mac
        .placements_in_scene(scene)
        .iter()
        .filter_map(|id| mac.get(*id).and_then(|r| r.text(f::LETTER)))
        .map(|s| s.to_string())
        .collect();
    let mut unique = letters.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(letters.len(), unique.len(), "{letters:?}");
}

#[test]
fn in_prep_a_collision_is_just_a_reflow() {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Daybreak");
    let scene = mac.create_scene("34");
    mac.add_shot_to_scene(scene);

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mac.changes().to_vec());

    mac.add_shot_to_scene(scene);
    phone.add_shot_to_scene(scene);
    mac.merge(phone.changes().to_vec());

    assert!(!mac.letters_are_locked());
    mac.resolve_letter_collisions(scene);
    assert!(mac.letter_collisions().is_empty());

    // In prep, letters follow position — so they come out in order.
    let letters: Vec<String> = mac
        .placements_in_scene(scene)
        .iter()
        .filter_map(|id| mac.get(*id).and_then(|r| r.text(f::LETTER)))
        .map(|s| s.to_string())
        .collect();
    assert_eq!(letters, vec!["A", "B", "C"]);
}

#[test]
fn an_ordinary_scene_has_no_collisions() {
    let mut mac = Doc::new(DeviceId(1));
    mac.create_project("Daybreak");
    let scene = mac.create_scene("34");
    mac.add_shot_to_scene(scene);
    mac.add_shot_to_scene(scene);
    mac.add_shot_to_scene(scene);

    assert!(mac.letter_collisions().is_empty());
}

// ---- setups -------------------------------------------------------------

#[test]
fn a_setup_is_a_record_of_its_own_not_one_of_the_shots() {
    use shotlister_engine::Kind;

    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);

    let setup = d.tie_setup(a, b).expect("ties");

    assert_ne!(setup, a, "a shot is not its own setup");
    assert_ne!(setup, b);
    assert_eq!(d.get(setup).map(|r| r.kind.clone()), Some(Kind::Setup));
    assert_eq!(d.setup_siblings(a), vec![b]);
    assert_eq!(d.setup_siblings(b), vec![a]);
}

#[test]
fn tying_a_third_camera_joins_the_pair_whichever_way_round_it_is_asked() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);
    let (c, _) = d.add_shot_to_scene(scene);

    let first = d.tie_setup(a, b).expect("ties");
    // Asked the other way round: the new camera named first.
    let joined = d.tie_setup(c, a).expect("ties");

    assert_eq!(joined, first, "one setup, not two");
    assert_eq!(d.setup_siblings(a).len(), 2);
    assert_eq!(d.setup_siblings(c).len(), 2);
}

#[test]
fn untying_the_third_leaves_the_pair_and_untying_the_second_ends_it() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);
    let (c, _) = d.add_shot_to_scene(scene);

    d.tie_setup(a, b);
    d.tie_setup(c, a);

    d.untie_setup(c);
    assert_eq!(d.setup_siblings(a), vec![b], "the pair survives");

    d.untie_setup(b);
    assert!(
        d.setup_siblings(a).is_empty(),
        "a setup of one is not a setup, so the last shot is released too"
    );
    assert!(d.get(a).and_then(|r| r.ref_id(f::SETUP)).is_none());
}

#[test]
fn tying_is_one_thing_to_take_back() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);

    let depth = d.undo_depth();
    d.tie_setup(a, b);
    assert_eq!(d.undo_depth(), depth + 1, "not one step per camera");

    d.undo();
    assert!(d.setup_siblings(a).is_empty());
}

#[test]
fn an_older_project_that_used_a_shots_id_still_shows_its_siblings() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);

    // How it was written before setups had a record: the first shot stands in.
    d.set(a, f::SETUP, Value::Ref(a));
    d.set(b, f::SETUP, Value::Ref(a));

    assert_eq!(d.setup_siblings(a), vec![b]);
    assert_eq!(d.setup_siblings(b), vec![a]);
}

#[test]
fn the_undo_menu_can_list_its_steps() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (_shot, placement) = d.add_shot_to_scene(scene);
    d.set(placement, f::LENS, "40mm");
    d.set(placement, f::NOTES, "handheld");

    let labels = d.undo_labels();
    assert_eq!(labels.len(), d.undo_depth());
    assert_eq!(
        labels.first().copied(),
        d.undo_label(),
        "the first is the one the menu already names"
    );
    assert!(labels[0].contains("notes"));
}
