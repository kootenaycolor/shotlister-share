//! The rules that must never regress.
//!
//! Each of these is either something observed in a real shot list or something
//! the prototype got wrong and lost work over.

use shotlister_engine::doc::f;
use shotlister_engine::letters::LetterScheme;
use shotlister_engine::store::Change;
use shotlister_engine::vocab;
use shotlister_engine::{DeviceId, Doc};

fn doc() -> Doc {
    Doc::new(DeviceId(1))
}

// ---- lettering ---------------------------------------------------------

#[test]
fn letters_skip_i_and_p() {
    let scheme = LetterScheme::default();
    // Real lists run …G, H, J… and …N, O, Q…
    assert_eq!(scheme.nth(7), "H");
    assert_eq!(scheme.nth(8), "J");
    assert_eq!(scheme.nth(13), "O");
    assert_eq!(scheme.nth(14), "Q");
    assert!(!scheme.alphabet().contains(&'I'));
    assert!(!scheme.alphabet().contains(&'P'));
    assert_eq!(scheme.alphabet().len(), 24);
}

#[test]
fn letters_continue_past_z() {
    let scheme = LetterScheme::default();
    assert_eq!(scheme.nth(23), "Z");
    assert_eq!(scheme.nth(24), "AA");
    assert_eq!(scheme.nth(25), "AB");
}

#[test]
fn letter_positions_round_trip() {
    let scheme = LetterScheme::default();
    for n in 0..200 {
        let letter = scheme.nth(n);
        assert_eq!(scheme.position(&letter), Some(n), "letter {letter}");
    }
    // A letter the scheme skips is not a valid position.
    assert_eq!(scheme.position("I"), None);
}

#[test]
fn letters_do_not_reflow_when_a_neighbour_goes() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);

    assert_eq!(d.display_number(a).unwrap(), "34A");
    assert_eq!(d.display_number(b).unwrap(), "34B");
    assert_eq!(d.display_number(c).unwrap(), "34C");

    d.delete(b);

    // C stays C. Deleting a shot does not rename the ones after it.
    assert_eq!(d.display_number(c).unwrap(), "34C");
    assert_eq!(d.display_number(a).unwrap(), "34A");
}

#[test]
fn a_freed_letter_comes_back_into_play() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (_, _a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, _c) = d.add_shot_to_scene(scene);

    d.delete(b);

    let (_, fresh) = d.add_shot_to_scene(scene);
    assert_eq!(d.display_number(fresh).unwrap(), "34B");
}

// ---- placements --------------------------------------------------------

#[test]
fn one_shot_in_two_scenes_gets_a_letter_in_each() {
    let mut d = doc();
    let s34 = d.create_scene("34");
    let s40 = d.create_scene("40");

    // Fill scene 40 so the shared shot does not simply land on A in both.
    d.add_shot_to_scene(s40);
    d.add_shot_to_scene(s40);

    let (shot, in_34) = d.add_shot_to_scene(s34);
    let in_40 = d.place(shot, s40);

    assert_eq!(d.display_number(in_34).unwrap(), "34A");
    assert_eq!(d.display_number(in_40).unwrap(), "40C");
    assert_eq!(d.placements_of_shot(shot).len(), 2);
}

#[test]
fn editing_a_shared_shot_changes_it_everywhere() {
    let mut d = doc();
    let s1 = d.create_scene("4");
    let s2 = d.create_scene("9");
    let (shot, _) = d.add_shot_to_scene(s1);
    d.place(shot, s2);

    d.set(shot, f::LENS, "37mm");

    // One record, so there is no second copy to fall out of step.
    assert_eq!(d.get(shot).unwrap().text(f::LENS), Some("37mm"));
    assert_eq!(d.placements_of_shot(shot).len(), 2);
}

#[test]
fn setups_group_shots_that_roll_together() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let setup = d.create_shot(); // stand-in id for the shared setup
    let (a_cam, _) = d.add_shot_to_scene(scene);
    let (b_cam, _) = d.add_shot_to_scene(scene);

    d.set(a_cam, f::SETUP, setup);
    d.set(b_cam, f::SETUP, setup);

    assert_eq!(d.setup_siblings(a_cam), vec![b_cam]);
    assert_eq!(d.setup_siblings(b_cam), vec![a_cam]);
    // Still two separate shots with two separate numbers.
    assert_ne!(a_cam, b_cam);
}

// ---- derived values ----------------------------------------------------

#[test]
fn renaming_a_scene_renumbers_every_shot_in_it() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    assert_eq!(d.display_number(a).unwrap(), "34A");

    // Script renumbering happens. Nothing about the shots should need touching.
    d.set(scene, f::NUMBER, "34A");

    assert_eq!(d.display_number(a).unwrap(), "34AA");
    assert_eq!(d.display_number(b).unwrap(), "34AB");
}

#[test]
fn scene_heading_is_derived() {
    let mut d = doc();
    let scene = d.create_scene("12");
    d.set(scene, f::INT_EXT, "INT");
    d.set(scene, f::LOCATION, "bedroom");
    d.set(scene, f::TIME_OF_DAY, "night");

    assert_eq!(d.scene_heading(scene).unwrap(), "INT. BEDROOM - NIGHT");
}

#[test]
fn day_labels_follow_the_manual_order() {
    let mut d = doc();
    let one = d.create_day();
    let two = d.create_day();
    let three = d.create_day();

    assert_eq!(d.day_label(one).unwrap(), "Day 1");
    assert_eq!(d.day_label(three).unwrap(), "Day 3");

    // Drag the third day to the front.
    let first_pos = d.get(one).unwrap().float(f::ORDER).unwrap();
    d.set(three, f::ORDER, first_pos - 1.0);

    assert_eq!(d.day_label(three).unwrap(), "Day 1");
    assert_eq!(d.day_label(one).unwrap(), "Day 2");
    assert_eq!(d.day_label(two).unwrap(), "Day 3");
}

#[test]
fn a_date_on_a_day_does_not_reorder_anything() {
    let mut d = doc();
    let one = d.create_day();
    let two = d.create_day();

    // Day 2 is earlier in the calendar. The manual order still wins.
    d.set(one, f::DATE, "2026-10-30");
    d.set(two, f::DATE, "2026-10-28");

    assert_eq!(d.day_label(one).unwrap(), "Day 1");
    assert_eq!(d.day_label(two).unwrap(), "Day 2");
}

#[test]
fn a_day_can_be_born_dated() {
    let mut d = doc();
    let one = d.create_day_dated("2026-09-20");
    let two = d.create_day_dated("2026-09-10");

    assert_eq!(d.get(one).unwrap().text(f::DATE), Some("2026-09-20"));
    assert_eq!(d.get(two).unwrap().text(f::DATE), Some("2026-09-10"));
    // Numbered in the order picked, not the order of the calendar.
    assert_eq!(d.day_label(one).unwrap(), "Day 1");
    assert_eq!(d.day_label(two).unwrap(), "Day 2");
}

#[test]
fn sorting_days_by_date_moves_dated_days_and_leaves_the_rest() {
    let mut d = doc();
    let sep_20 = d.create_day_dated("2026-09-20");
    let undated = d.create_day();
    let sep_10 = d.create_day_dated("2026-09-10");

    assert!(d.sort_days_by_date());

    // The dated days swap among the positions dated days held; the undated
    // day keeps its exact place in the middle.
    assert_eq!(d.day_label(sep_10).unwrap(), "Day 1");
    assert_eq!(d.day_label(undated).unwrap(), "Day 2");
    assert_eq!(d.day_label(sep_20).unwrap(), "Day 3");

    // Already in order: nothing to do, and it says so.
    assert!(!d.sort_days_by_date());
}

// ---- ordering ----------------------------------------------------------

#[test]
fn reordering_writes_exactly_one_change() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);

    let before = d.changes().len();

    // Move C between A and B.
    let pos_a = d.get(a).unwrap().float(f::ORDER_IN_SCENE).unwrap();
    let pos_b = d.get(b).unwrap().float(f::ORDER_IN_SCENE).unwrap();
    d.move_in_scene(c, Some(pos_a), Some(pos_b));

    // The prototype rewrote every shot in the project for this.
    assert_eq!(d.changes().len() - before, 1);
    assert_eq!(d.placements_in_scene(scene), vec![a, c, b]);
}

#[test]
fn story_order_and_shoot_order_are_independent() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let day = d.create_day();
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);

    // Shot them out of story order, as on a real day.
    d.schedule(c, day);
    d.schedule(a, day);
    d.schedule(b, day);

    assert_eq!(d.placements_in_scene(scene), vec![a, b, c]);
    assert_eq!(d.placements_on_day(day), vec![c, a, b]);
}

// ---- merge -------------------------------------------------------------

#[test]
fn merging_is_order_independent() {
    let mut a = Doc::new(DeviceId(1));
    let scene = a.create_scene("34");
    let (shot, _) = a.add_shot_to_scene(scene);
    let base: Vec<Change> = a.changes().to_vec();

    let mut b = Doc::new(DeviceId(2));
    b.merge(base.clone());

    // Both devices edit the same field while apart.
    a.set(shot, f::LENS, "37mm");
    b.set(shot, f::LENS, "40mm");

    let from_a: Vec<Change> = a.changes().to_vec();
    let from_b: Vec<Change> = b.changes().to_vec();

    let mut x = Doc::new(DeviceId(3));
    x.merge(from_a.clone());
    x.merge(from_b.clone());

    let mut y = Doc::new(DeviceId(4));
    y.merge(from_b);
    y.merge(from_a);

    // Which value wins is decided by the stamp; that both devices agree is the
    // property that matters.
    assert_eq!(
        x.get(shot).unwrap().text(f::LENS),
        y.get(shot).unwrap().text(f::LENS)
    );
}

#[test]
fn edits_to_different_fields_both_land() {
    let mut a = Doc::new(DeviceId(1));
    let scene = a.create_scene("34");
    let (shot, _) = a.add_shot_to_scene(scene);
    let mut b = Doc::new(DeviceId(2));
    b.merge(a.changes().to_vec());

    a.set(shot, f::LENS, "37mm");
    b.set(shot, f::SIZE, "W/OTS");

    let from_b: Vec<Change> = b.changes().to_vec();
    a.merge(from_b);

    // Different fields are not a conflict, so nothing has to be chosen.
    let record = a.get(shot).unwrap();
    assert_eq!(record.text(f::LENS), Some("37mm"));
    assert_eq!(record.text(f::SIZE), Some("W/OTS"));
}

#[test]
fn replaying_changes_twice_changes_nothing() {
    let mut a = Doc::new(DeviceId(1));
    let scene = a.create_scene("34");
    let (shot, _) = a.add_shot_to_scene(scene);
    a.set(shot, f::LENS, "37mm");

    let changes: Vec<Change> = a.changes().to_vec();

    let mut b = Doc::new(DeviceId(2));
    b.merge(changes.clone());
    b.merge(changes.clone());
    b.merge(changes);

    assert_eq!(b.get(shot).unwrap().text(f::LENS), Some("37mm"));
    assert_eq!(b.placements_in_scene(scene).len(), 1);
}

#[test]
fn an_unknown_field_survives_a_device_that_does_not_understand_it() {
    // Stands in for a newer build writing a field an older one has never heard
    // of. The older build must carry it through untouched rather than drop it.
    let mut newer = Doc::new(DeviceId(1));
    let scene = newer.create_scene("34");
    let (shot, _) = newer.add_shot_to_scene(scene);
    newer.set(shot, "colour_temperature", "3200K");

    let mut older = Doc::new(DeviceId(2));
    older.merge(newer.changes().to_vec());

    // Older device edits something it does understand.
    older.set(shot, f::LENS, "37mm");

    let mut back = Doc::new(DeviceId(3));
    back.merge(older.changes().to_vec());

    let record = back.get(shot).unwrap();
    assert_eq!(record.text("colour_temperature"), Some("3200K"));
    assert_eq!(record.text(f::LENS), Some("37mm"));
}

#[test]
fn a_set_arriving_before_its_create_still_lands() {
    // Change files can arrive in any order from any transport.
    let mut a = Doc::new(DeviceId(1));
    let scene = a.create_scene("34");
    let (shot, _) = a.add_shot_to_scene(scene);
    a.set(shot, f::LENS, "37mm");

    let mut changes: Vec<Change> = a.changes().to_vec();
    changes.reverse();

    let mut b = Doc::new(DeviceId(2));
    b.merge(changes);

    assert_eq!(b.get(shot).unwrap().text(f::LENS), Some("37mm"));
    assert_eq!(b.display_number(b.placements_of_shot(shot)[0]).unwrap(), "34A");
}

// ---- deletion and strike ----------------------------------------------

#[test]
fn deleting_is_reversible() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set(shot, f::LENS, "37mm");

    d.delete(shot);
    assert!(d.get(shot).is_none());

    d.undelete(shot);
    // Nothing was thrown away, so it comes back whole.
    assert_eq!(d.get(shot).unwrap().text(f::LENS), Some("37mm"));
}

#[test]
fn striking_a_shot_changes_nothing_else() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);

    d.strike(shot, true);

    assert!(d.get(shot).unwrap().bool(f::STRUCK));
    assert_eq!(d.display_number(placement).unwrap(), "34A");
    assert_eq!(d.placements_in_scene(scene), vec![placement]);
}

// ---- counts ------------------------------------------------------------

#[test]
fn counts_are_derived_not_stored() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let day = d.create_day();
    for _ in 0..16 {
        let (_, p) = d.add_shot_to_scene(scene);
        d.schedule(p, day);
    }

    assert_eq!(d.shot_count_in_scene(scene), 16);
    assert_eq!(d.shot_count_on_day(day), 16);

    let victim = d.placements_in_scene(scene)[0];
    d.delete(victim);

    // No stored total to fall out of step with reality.
    assert_eq!(d.shot_count_in_scene(scene), 15);
    assert_eq!(d.shot_count_on_day(day), 15);
}

// ---- copying and moving ------------------------------------------------

#[test]
fn a_copied_shot_carries_everything_but_its_identity() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Frontal Dirty Single on Milo");
    d.set(shot, f::SIZE, "M/OTS");
    d.set(shot, f::LENS, "37mm");

    let (copy, new_placement) = d.duplicate_shot(placement).expect("copies");

    assert_ne!(copy, shot);
    assert_eq!(
        d.get(copy).unwrap().text(f::DESCRIPTION),
        Some("Frontal Dirty Single on Milo")
    );
    assert_eq!(d.get(copy).unwrap().text(f::LENS), Some("37mm"));
    // Its own number, not the original's.
    assert_eq!(d.display_number(placement).unwrap(), "34A");
    assert_eq!(d.display_number(new_placement).unwrap(), "34B");
}

#[test]
fn a_copy_sits_next_to_what_it_came_from() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (_, first) = d.add_shot_to_scene(scene);
    let (_, second) = d.add_shot_to_scene(scene);
    let (_, third) = d.add_shot_to_scene(scene);

    let (_, copy) = d.duplicate_shot(first).expect("copies");

    // Straight after the original rather than at the end of the scene.
    assert_eq!(
        d.placements_in_scene(scene),
        vec![first, copy, second, third]
    );
}

#[test]
fn a_copy_takes_the_frames_without_taking_the_strike() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);
    let frame = d.add_media(
        shotlister_engine::sha256(b"panel"),
        shotlister_engine::MediaKind::Image,
        1600,
        900,
        10,
        "p.png",
    );
    d.attach_media(shot, frame, "storyboard panel 1");
    d.strike(shot, true);

    let (copy, _) = d.duplicate_shot(placement).expect("copies");

    // Media is stored by its contents, so carrying the frames costs nothing.
    assert_eq!(d.media_of(copy), vec![frame]);
    assert_eq!(
        d.get(d.media_refs(copy)[0]).unwrap().text(f::CAPTION),
        Some("storyboard panel 1")
    );
    // A copy is work still to do.
    assert!(!d.get(copy).unwrap().bool(f::STRUCK));
    assert!(d.get(shot).unwrap().bool(f::STRUCK));
}

/// **A copy owns its own picture, and taking it off one leaves the other alone.**
///
/// His report, Ref 489: duplicate a shot carrying a clip, take the clip off one
/// of them, and it went from both — then from the copy altogether. The cause was
/// that `KEY_MEDIA` was carried across verbatim, and it names a *media ref*, so
/// the copy's lead frame was the original's own use of the file.
#[test]
fn a_copy_owns_its_own_frames() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);
    let clip = d.add_media(
        shotlister_engine::sha256(b"clip"),
        shotlister_engine::MediaKind::Video,
        1920,
        1080,
        40,
        "c.mov",
    );
    d.attach_media(shot, clip, "the take");

    let (copy, _) = d.duplicate_shot(placement).expect("copies");

    let original_ref = d.media_refs(shot)[0];
    let copy_ref = d.media_refs(copy)[0];
    assert_ne!(original_ref, copy_ref, "two shots, two uses of the file");
    assert_eq!(
        d.get(copy).unwrap().ref_id(f::KEY_MEDIA),
        Some(copy_ref),
        "the copy leads with its own frame, never the original's"
    );

    // Take it off the original. The copy keeps everything.
    d.detach_media(original_ref);
    assert!(d.media_refs(shot).is_empty());
    assert_eq!(d.media_of(copy), vec![clip]);
    assert_eq!(d.get(copy).unwrap().ref_id(f::KEY_MEDIA), Some(copy_ref));
}

/// A crop, a trim and any arrows live on the ref, so a copy that carried only
/// the file drew the middle of an untrimmed clip with no marks on it.
#[test]
fn a_copy_keeps_how_the_frame_was_framed() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);
    let clip = d.add_media(
        shotlister_engine::sha256(b"framed"),
        shotlister_engine::MediaKind::Video,
        1920,
        1080,
        40,
        "c.mov",
    );
    let was = d.attach_media(shot, clip, "the take");
    d.set(was, f::CROP_X, 0.25);
    d.set(was, f::TRIM_START, 1.5);
    d.set(was, f::ARROWS, "0.1 0.2 0.3 0.4 0.5 0.6 0.0");

    let (copy, _) = d.duplicate_shot(placement).expect("copies");

    let now = d.media_refs(copy)[0];
    assert_eq!(d.get(now).unwrap().float(f::CROP_X), Some(0.25));
    assert_eq!(d.get(now).unwrap().float(f::TRIM_START), Some(1.5));
    assert_eq!(
        d.get(now).unwrap().text(f::ARROWS),
        Some("0.1 0.2 0.3 0.4 0.5 0.6 0.0")
    );
}

#[test]
fn a_copy_does_not_join_the_originals_camera_setup() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let setup = d.create_shot();
    let (a_cam, placement) = d.add_shot_to_scene(scene);
    let (b_cam, _) = d.add_shot_to_scene(scene);
    d.set(a_cam, f::SETUP, setup);
    d.set(b_cam, f::SETUP, setup);

    let (copy, _) = d.duplicate_shot(placement).expect("copies");

    // Otherwise copying one of a two-camera pair quietly makes it three.
    assert!(d.get(copy).unwrap().ref_id(f::SETUP).is_none());
    assert_eq!(d.setup_siblings(a_cam), vec![b_cam]);
}

#[test]
fn copying_is_one_thing_to_take_back() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Wide of the car");
    d.clear_history();

    d.duplicate_shot(placement).expect("copies");
    assert_eq!(d.undo_depth(), 1);

    d.undo();
    assert_eq!(d.placements_in_scene(scene), vec![placement]);
}

#[test]
fn a_shot_moved_to_another_scene_is_renumbered_by_where_it_lands() {
    let mut d = doc();
    let from = d.create_scene("34");
    let to = d.create_scene("40");
    d.add_shot_to_scene(from);
    let (shot, placement) = d.add_shot_to_scene(from); // 34B
    d.add_shot_to_scene(to); // 40A
    d.set(shot, f::DESCRIPTION, "Wide of the car");

    assert_eq!(d.display_number(placement).unwrap(), "34B");
    let number = d.move_placement_to_scene(placement, to).expect("moves");

    assert_eq!(number, "40B");
    // The shot itself is untouched — only where it sits changed.
    assert_eq!(
        d.get(shot).unwrap().text(f::DESCRIPTION),
        Some("Wide of the car")
    );
    assert_eq!(d.placements_in_scene(from).len(), 1);
    assert_eq!(d.placements_in_scene(to).len(), 2);
}

#[test]
fn moving_a_shot_out_closes_the_letters_behind_it() {
    let mut d = doc();
    let from = d.create_scene("34");
    let to = d.create_scene("40");
    let (_, a) = d.add_shot_to_scene(from);
    let (_, b) = d.add_shot_to_scene(from);

    d.move_placement_to_scene(a, to);

    // **This test used to assert the opposite** — that B stayed 34B and the
    // freed A waited for the next shot added. Nathaniel was asked directly and
    // chose the other answer: "no gap — it should close up yes." It matches
    // what `delete_placement` has always done, and the reason is the same: in
    // prep, nobody has the list on paper yet, so letters follow position.
    assert_eq!(d.display_number(b).unwrap(), "34A");
    let (_, fresh) = d.add_shot_to_scene(from);
    assert_eq!(d.display_number(fresh).unwrap(), "34B");
}

#[test]
fn moving_a_shot_is_not_the_same_as_sharing_it() {
    let mut d = doc();
    let from = d.create_scene("34");
    let to = d.create_scene("40");
    let (shot, placement) = d.add_shot_to_scene(from);

    d.move_placement_to_scene(placement, to);

    // Moved, not copied into both — one placement still.
    assert_eq!(d.placements_of_shot(shot).len(), 1);
    assert!(d.placements_in_scene(from).is_empty());
}

#[test]
fn moving_a_shot_to_where_it_already_is_changes_nothing() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (_, placement) = d.add_shot_to_scene(scene);
    let before = d.changes().len();

    let number = d.move_placement_to_scene(placement, scene).expect("no-op");

    assert_eq!(number, "34A");
    assert_eq!(d.changes().len(), before);
}

#[test]
fn copying_shots_into_another_scene_is_one_thing_to_undo() {
    let mut d = doc();
    let from = d.create_scene("34");
    let to = d.create_scene("40");
    let (_, a) = d.add_shot_to_scene(from);
    let (_, b) = d.add_shot_to_scene(from);
    d.set(d.get(a).unwrap().ref_id(f::SHOT).unwrap(), f::DESCRIPTION, "first");
    d.set(d.get(b).unwrap().ref_id(f::SHOT).unwrap(), f::DESCRIPTION, "second");
    d.add_shot_to_scene(to);

    let landed = d.duplicate_shots_into(&[a, b], to, None);

    assert_eq!(landed.len(), 2);
    assert_eq!(d.placements_in_scene(to).len(), 3, "both copies arrived");
    assert_eq!(d.placements_in_scene(from).len(), 2, "the originals stayed put");
    // The run keeps its order, and the words came with it — a shot copied is
    // the shot, not a smear of its columns.
    let words: Vec<String> = d
        .placements_in_scene(to)
        .iter()
        .filter_map(|p| d.get(*p)?.ref_id(f::SHOT))
        .filter_map(|shot| d.get(shot)?.text(f::DESCRIPTION).map(String::from))
        .collect();
    assert_eq!(words, vec!["first", "second"]);

    // **One press.** Four shots copied is one gesture and one thing to take
    // back; per-shot undo steps are what made undo feel arbitrary.
    d.undo();
    assert_eq!(d.placements_in_scene(to).len(), 1, "one ⌘Z put all of it back");
}

// ---------------------------------------------------------------------------
// Deleting a scene, once it is archived — his ask, 2026-08-22.

#[test]
fn a_scene_can_only_be_deleted_after_it_has_been_archived() {
    use shotlister_engine::doc::f;
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Call Her Back");
    let scene = doc.create_scene("7");
    let (shot, _) = doc.add_shot_to_scene(scene);
    doc.add_shot_to_scene(scene);

    // Archiving is the reversible step, and it has to be taken first.
    assert_eq!(doc.delete_archived_scene(scene), None, "not archived, not deleted");
    assert!(doc.get(scene).is_some());

    doc.archive_scene(scene, true);
    assert_eq!(doc.delete_archived_scene(scene), Some(2), "and it says what went");
    assert!(doc.get(scene).is_none());
    assert!(doc.scenes_in_order().is_empty());

    // **A shot that stood only here goes with it**, which is what
    // `delete_placement` has always done and is right: a shot's existence *is*
    // its place in a scene, and one with nowhere to stand is nothing. A shot
    // that also stands in another scene keeps that place and survives.
    //
    // I asserted the opposite first, from assumption rather than from reading
    // the code, and the test failed rather than the app.
    assert!(doc.get(shot).is_none());

    // One step back, however much it took.
    doc.undo();
    assert!(doc.get(scene).is_some());
    assert_eq!(doc.placements_in_scene(scene).len(), 2);
    assert_eq!(doc.get(scene).and_then(|r| r.text(f::NUMBER)), Some("7"));
}

// ------------------------------------------------------------------ Ref 55

/// A term with no colour of its own answers nothing, and the app hashes the
/// word. That default is the point: it is right without anybody choosing.
#[test]
fn a_term_has_no_colour_until_one_is_given() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d.learn(vocab::LENS, "37mm");

    assert_eq!(d.term_colour(vocab::LENS, "37mm"), None);
    d.set_term_colour(vocab::LENS, "37mm", "#2B6CB0");
    assert_eq!(d.term_colour(vocab::LENS, "37mm"), Some("2B6CB0".to_string()));
    // Asked for the way it is drawn — case-blind, like everything else here.
    assert_eq!(d.term_colour(vocab::LENS, "37MM"), Some("2B6CB0".to_string()));
}

/// Emptying it is the only way back to the hash, and has to really work.
#[test]
fn a_colour_can_be_handed_back() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d.learn(vocab::LENS, "37mm");
    d.set_term_colour(vocab::LENS, "37mm", "2B6CB0");
    d.set_term_colour(vocab::LENS, "37mm", "");
    assert_eq!(d.term_colour(vocab::LENS, "37mm"), None);
}

/// **The colour belongs to the thing, not to the spelling.** A term that lost
/// its colour because somebody fixed a typo would teach people not to fix them.
#[test]
fn a_renamed_term_keeps_its_colour() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d.learn(vocab::LENS, "37mm");
    d.set_term_colour(vocab::LENS, "37mm", "2B6CB0");

    d.rename_vocabulary_value(vocab::LENS, "37mm", "37 mm");
    assert_eq!(d.term_colour(vocab::LENS, "37 mm"), Some("2B6CB0".to_string()));
    assert_eq!(d.term_colour(vocab::LENS, "37mm"), None);
}

/// And a term taken off the list takes its colour with it, or typing the word
/// again a month later brings back a colour nobody chose.
#[test]
fn a_removed_term_takes_its_colour_with_it() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d.learn(vocab::LENS, "37mm");
    d.set_term_colour(vocab::LENS, "37mm", "2B6CB0");

    d.remove_vocabulary_value(vocab::LENS, "37mm");
    d.learn(vocab::LENS, "37mm");
    assert_eq!(d.term_colour(vocab::LENS, "37mm"), None);
}

/// A term is allowed to have `=` in it — "1/4 = Pro-Mist" is a thing somebody
/// would type — so the split has to come from the right.
#[test]
fn a_term_may_contain_an_equals_sign() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d.set_term_colour(vocab::TAGS, "ND = 0.9", "9A6B10");
    assert_eq!(d.term_colour(vocab::TAGS, "ND = 0.9"), Some("9A6B10".to_string()));
}
