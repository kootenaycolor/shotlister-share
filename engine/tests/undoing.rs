//! Undo and redo.
//!
//! The prototype had none, and lost work repeatedly. What matters here is not
//! just that undo works but that it refuses to overreach: undoing your own typo
//! must never roll back what another device did in between.

use shotlister_engine::doc::f;
use shotlister_engine::{DeviceId, Doc, GroupBy, Query};

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d.clear_history();
    d
}

// ---- the basics --------------------------------------------------------

#[test]
fn nothing_to_undo_at_the_start() {
    let d = project();
    assert!(!d.can_undo());
    assert!(!d.can_redo());
    assert_eq!(d.undo_label(), None);
}

#[test]
fn a_change_can_be_taken_back_and_put_again() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.clear_history();

    d.set_vocab_field(shot, "lens", "37mm");
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("37mm"));

    d.undo();
    assert_eq!(d.get(shot).unwrap().text("lens"), None);

    d.redo();
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("37mm"));
}

#[test]
fn undo_puts_back_the_previous_value_not_nothing() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "37mm");
    d.clear_history();

    d.set_vocab_field(shot, "lens", "50mm");
    d.undo();

    assert_eq!(d.get(shot).unwrap().text("lens"), Some("37mm"));
}

#[test]
fn writing_the_value_that_is_already_there_is_nothing_to_undo() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "37mm");
    d.clear_history();

    // Picking the same lens off the menu again, or retyping what is in the
    // cell, changes nothing — so pressing undo afterwards must take back the
    // last thing that *did* change, not spend a keystroke doing nothing.
    let logged = d.changes().len();
    d.set(shot, "lens", "37mm");
    assert!(!d.can_undo(), "a write that changed nothing is not a step");
    // The write itself still happens — it is only the undo pile that is
    // spared. A device saying what it believes is worth something to a merge.
    assert!(
        d.changes().len() > logged,
        "the log still carries what was written"
    );

    d.set(shot, "lens", "50mm");
    d.set(shot, "lens", "50mm");
    assert_eq!(d.undo_depth(), 1, "the second write added no step");
    d.undo();
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("37mm"));

}

#[test]
fn undo_never_removes_a_change_from_the_log() {
    let mut d = project();
    let scene = d.create_scene("34");
    let before = d.changes().len();

    d.set(scene, f::LOCATION, "car");
    d.undo();

    // The log is the record of what happened; putting a value back is another
    // thing that happened, not the erasure of the first.
    assert!(d.changes().len() > before + 1);
}

// ---- one action, one undo ----------------------------------------------

#[test]
fn adding_a_shot_is_one_undo_not_a_dozen() {
    let mut d = project();
    let scene = d.create_scene("34");
    d.clear_history();

    d.add_shot_to_scene(scene);
    assert_eq!(d.undo_depth(), 1, "one action");
    assert_eq!(d.undo_label(), Some("Add shot"));

    d.undo();
    assert!(d.placements_in_scene(scene).is_empty());
}

#[test]
fn a_shot_undone_comes_back_whole() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, placement) = d.add_shot_to_scene(scene);
    d.set(shot, f::DESCRIPTION, "Wide of the car");
    d.clear_history();

    d.transact("Delete shot", |d| {
        d.delete(placement);
        d.delete(shot);
    });
    assert!(d.get(shot).is_none());

    d.undo();
    // Nothing was destroyed, so it returns with everything on it.
    assert_eq!(d.get(shot).unwrap().text(f::DESCRIPTION), Some("Wide of the car"));
    assert_eq!(d.display_number(placement).unwrap(), "34A");
}

#[test]
fn a_grouped_action_is_one_step_however_much_it_touched() {
    let mut d = project();
    let scene = d.create_scene("34");
    for _ in 0..40 {
        d.add_shot_to_scene(scene);
    }
    let day = d.create_day();
    d.clear_history();

    d.schedule_scene(scene, day);
    assert_eq!(d.undo_depth(), 1);

    d.undo();
    assert!(d.placements_on_day(day).is_empty());
}

#[test]
fn a_dated_day_is_one_step_to_take_back() {
    let mut d = project();
    d.create_day_dated("2026-09-20");

    assert_eq!(d.undo_depth(), 1);
    assert_eq!(d.undo_label(), Some("Add shoot day"));

    d.undo();
    assert!(d.days_in_order().is_empty());
}

#[test]
fn the_label_says_what_would_be_undone() {
    let mut d = project();
    let scene = d.create_scene("34");
    assert_eq!(d.undo_label(), Some("Add scene"));

    d.add_shot_to_scene(scene);
    assert_eq!(d.undo_label(), Some("Add shot"));

    d.undo();
    assert_eq!(d.redo_label(), Some("Add shot"));
    assert_eq!(d.undo_label(), Some("Add scene"));
}

// ---- the part that matters ---------------------------------------------

#[test]
fn undo_leaves_alone_what_somebody_else_changed_since() {
    let mut mine = Doc::new(DeviceId(1));
    mine.create_project("Daybreak");
    let scene = mine.create_scene("34");
    let (shot, _) = mine.add_shot_to_scene(scene);

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mine.changes().to_vec());

    // I set a lens, then the phone changes it while I am not looking.
    mine.set_vocab_field(shot, "lens", "37mm");
    let mine_so_far: Vec<_> = mine.changes().to_vec();
    phone.merge(mine_so_far);
    phone.set_vocab_field(shot, "lens", "50mm");
    mine.merge(phone.changes().to_vec());

    // Now I hit undo on my own edit, half an hour later.
    let outcome = mine.undo().unwrap();

    assert_eq!(mine.get(shot).unwrap().text("lens"), Some("50mm"));
    assert!(outcome.skipped > 0, "it should report holding back");
    assert!(!outcome.complete());
}

#[test]
fn undo_still_works_on_the_parts_that_did_not_move() {
    let mut mine = Doc::new(DeviceId(1));
    mine.create_project("Daybreak");
    let scene = mine.create_scene("34");
    let (shot, _) = mine.add_shot_to_scene(scene);
    mine.clear_history();

    mine.transact("Change shot", |d| {
        d.set(shot, f::DESCRIPTION, "Wide of the car");
        d.set(shot, "lens", "37mm");
    });

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mine.changes().to_vec());
    phone.set(shot, "lens", "50mm");
    mine.merge(phone.changes().to_vec());

    let outcome = mine.undo().unwrap();

    // The description was mine alone and goes back; the lens moved on and stays.
    assert_eq!(mine.get(shot).unwrap().text(f::DESCRIPTION), None);
    assert_eq!(mine.get(shot).unwrap().text("lens"), Some("50mm"));
    assert_eq!(outcome.restored, 1);
    assert_eq!(outcome.skipped, 1);
}

#[test]
fn merging_someone_elses_work_is_not_something_you_can_undo() {
    let mut mine = Doc::new(DeviceId(1));
    mine.create_project("Daybreak");
    let scene = mine.create_scene("34");

    let mut phone = Doc::new(DeviceId(2));
    phone.merge(mine.changes().to_vec());
    phone.add_shot_to_scene(scene);

    mine.clear_history();
    mine.merge(phone.changes().to_vec());

    // Their shot arrived, and it is not mine to take back.
    assert_eq!(mine.placements_in_scene(scene).len(), 1);
    assert!(!mine.can_undo());
}

// ---- stacks behave -----------------------------------------------------

#[test]
fn a_new_action_closes_off_the_redo_branch() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.clear_history();

    d.set_vocab_field(shot, "lens", "37mm");
    d.undo();
    assert!(d.can_redo());

    d.set_vocab_field(shot, "lens", "27mm");
    assert!(!d.can_redo(), "the old branch is unreachable");
}

#[test]
fn undo_can_walk_back_several_steps() {
    let mut d = project();
    let scene = d.create_scene("34");
    d.clear_history();

    for _ in 0..5 {
        d.add_shot_to_scene(scene);
    }
    assert_eq!(d.undo_depth(), 5);

    for _ in 0..3 {
        d.undo();
    }
    assert_eq!(d.placements_in_scene(scene).len(), 2);

    for _ in 0..3 {
        d.redo();
    }
    assert_eq!(d.placements_in_scene(scene).len(), 5);
}

#[test]
fn undoing_past_the_beginning_is_simply_nothing() {
    let mut d = project();
    d.create_scene("34");
    d.clear_history();
    assert!(d.undo().is_none());
    assert!(d.redo().is_none());
}

#[test]
fn deleting_forty_shots_is_as_reversible_as_a_typo() {
    let mut d = project();
    let scene = d.create_scene("34");
    let mut placements = Vec::new();
    for _ in 0..40 {
        let (_, placement) = d.add_shot_to_scene(scene);
        placements.push(placement);
    }
    d.clear_history();

    d.transact("Delete 40 shots", |d| {
        for placement in &placements {
            d.delete(*placement);
        }
    });
    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat)), 0);

    let outcome = d.undo().unwrap();
    assert_eq!(outcome.label, "Delete 40 shots");
    assert_eq!(d.placements_in_scene(scene).len(), 40);
}

// ---- one gesture, one step ---------------------------------------------

#[test]
fn adding_a_shot_below_the_cursor_is_one_undo() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (_, first) = d.add_shot_to_scene(scene);
    let (_, _) = d.add_shot_to_scene(scene);
    d.clear_history();

    // Control-return's gesture: create and seat in one breath.
    let (_, seated) = d.add_shot_to_scene_after(scene, Some(first));
    let order = d.placements_in_scene(scene);
    assert_eq!(order.len(), 3);
    assert_eq!(order[1], seated, "the new shot sits below the cursor");

    // One undo takes the whole gesture back — created-then-moved as two
    // history steps meant one keystroke took two undos, and nobody means
    // that by "undo".
    d.undo();
    assert_eq!(d.placements_in_scene(scene).len(), 2);
    assert!(!d.can_undo(), "the gesture was one step, not two");
}

#[test]
fn a_unit_can_be_born_with_its_colour() {
    let mut d = project();
    d.clear_history();
    let unit = d.create_unit_coloured("C-Cam", "Komodo", "0A6CE8");
    assert_eq!(d.get(unit).and_then(|r| r.text(f::COLOUR)), Some("0A6CE8"));
    d.undo();
    // Undo is field-level: the record survives as an empty husk, and the
    // view is what keeps husks out of sight — a camera with no name is
    // nothing to offer in a picker.
    assert_eq!(
        d.get(unit).and_then(|r| r.text(f::LABEL)),
        None,
        "one step strips everything it wrote"
    );
}

#[test]
fn deleting_a_selection_is_one_thing_to_take_back() {
    let mut d = project();
    let scene = d.create_scene("34");
    let mut placements = Vec::new();
    for _ in 0..4 {
        let (_, p) = d.add_shot_to_scene(scene);
        placements.push(p);
    }
    d.clear_history();

    d.delete_placements(&placements[0..3]);
    assert_eq!(d.placements_in_scene(scene).len(), 1);

    // One undo, three shots back — a selection is one gesture.
    d.undo();
    assert_eq!(d.placements_in_scene(scene).len(), 4);
    assert!(!d.can_undo());
}
