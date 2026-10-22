//! Mood boards: a name, a wall of pictures, and what deleting one costs.

use shotlister_engine::hash::{sha256, Hash256};
use shotlister_engine::media::MediaKind;
use shotlister_engine::store::Kind;
use shotlister_engine::{DeviceId, Doc};

fn doc() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

fn picture(d: &mut Doc, bytes: &[u8], name: &str) -> (Hash256, shotlister_engine::id::Id) {
    let hash = sha256(bytes);
    let id = d.add_media(hash, MediaKind::Image, 1920, 1080, 500_000, name);
    (hash, id)
}

#[test]
fn a_board_is_made_named_and_found_again() {
    let mut d = doc();
    let board = d.create_board("Night Exteriors");
    assert_eq!(d.board_name(board), "Night Exteriors");
    assert_eq!(d.board_named("night exteriors"), Some(board));
    assert_eq!(d.boards_in_order(), vec![board]);
}

#[test]
fn boards_keep_the_order_they_were_made_in() {
    let mut d = doc();
    let first = d.create_board("Anya");
    let second = d.create_board("The Diner");
    let third = d.create_board("Night Exteriors");
    assert_eq!(d.boards_in_order(), vec![first, second, third]);
}

#[test]
fn renaming_a_board_does_not_make_a_second_one() {
    let mut d = doc();
    let board = d.create_board("Untitled");
    d.rename_board(board, "The Diner");
    assert_eq!(d.board_name(board), "The Diner");
    assert_eq!(d.boards_in_order().len(), 1);
    assert_eq!(d.board_named("Untitled"), None);
}

#[test]
fn a_board_holds_pictures_the_same_way_everything_else_does() {
    let mut d = doc();
    let board = d.create_board("Anya");
    let (_, media) = picture(&mut d, b"one", "still.png");
    d.attach_media(board, media, "");
    assert_eq!(d.media_of(board), vec![media]);
}

/// **A photograph on no other wall goes with its board; one also on a shot
/// stays.** His ruling, 2026-09-19: a file whose only use is deleted is
/// deleted for good. Before this the record survived every deletion and the
/// file with it, on every device, for ever.
#[test]
fn deleting_a_board_takes_its_own_photographs_and_keeps_shared_ones() {
    let mut d = doc();
    let board = d.create_board("Anya");
    let (only_hash, only_here) = picture(&mut d, b"one", "still.png");
    let (shared_hash, shared) = picture(&mut d, b"two", "shared.png");
    d.attach_media(board, only_here, "");
    d.attach_media(board, shared, "");
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.attach_media(shot, shared, "");

    d.delete_board(board);

    assert!(d.boards_in_order().is_empty());
    assert!(d.media_refs(board).is_empty());
    assert_eq!(d.media_with_hash(only_hash), None, "its only use went, so it goes");
    assert_eq!(d.media_with_hash(shared_hash), Some(shared), "the shot still holds it");

    // One thing to take back: the board, its uses and the record come back.
    d.undo();
    assert_eq!(d.media_with_hash(only_hash), Some(only_here));
    assert_eq!(d.media_of(board).len(), 2);
}

#[test]
fn a_board_deleted_does_not_take_another_boards_pictures() {
    let mut d = doc();
    let kept = d.create_board("The Diner");
    let gone = d.create_board("Anya");
    let (_, media) = picture(&mut d, b"one", "still.png");
    d.attach_media(kept, media, "");
    d.attach_media(gone, media, "");

    d.delete_board(gone);

    assert_eq!(d.media_of(kept), vec![media]);
    assert_eq!(d.boards_in_order(), vec![kept]);
}

#[test]
fn a_mood_board_record_reads_back_as_one() {
    let mut d = doc();
    let board = d.create_board("Night Exteriors");
    assert_eq!(Kind::parse(Kind::MoodBoard.as_str()), Kind::MoodBoard);
    assert_eq!(d.get(board).map(|r| r.kind.clone()), Some(Kind::MoodBoard));
}

/// Adding a board is one thing to take back, like everything else.
#[test]
fn adding_a_board_is_one_undo() {
    let mut d = doc();
    d.create_board("Anya");
    assert_eq!(d.boards_in_order().len(), 1);
    d.undo();
    assert!(d.boards_in_order().is_empty());
}

// ---- putting boards in order, by hand (2026-09-29) ----------------------

/// **A board dragged in the sidebar lands where it was let go** — his ask,
/// 2026-09-29: "need to be able to re-order reference boards". The index is
/// counted with the board lifted out, the way every drop in the app counts.
#[test]
fn a_board_moves_to_where_it_was_let_go() {
    let mut d = doc();
    let a = d.create_board("Anya");
    let b = d.create_board("The Diner");
    let c = d.create_board("Night Exteriors");

    d.move_board_to(c, 0);
    assert_eq!(d.boards_in_order(), vec![c, a, b]);

    d.move_board_to(c, 2);
    assert_eq!(d.boards_in_order(), vec![a, b, c]);

    d.move_board_to(a, 1);
    assert_eq!(d.boards_in_order(), vec![b, a, c]);

    // Past the end is the end, and its own place is no move at all.
    d.move_board_to(b, 99);
    assert_eq!(d.boards_in_order(), vec![a, c, b]);
    let steps = d.undo_labels().len();
    d.move_board_to(c, 1);
    assert_eq!(d.undo_labels().len(), steps, "a board let go where it was is nothing to undo");
}

/// One drag is one ⌘Z, and ⌘Z puts it back exactly.
#[test]
fn moving_a_board_is_one_undo() {
    let mut d = doc();
    let a = d.create_board("Anya");
    let b = d.create_board("The Diner");
    let c = d.create_board("Night Exteriors");

    d.move_board_to(a, 2);
    assert_eq!(d.boards_in_order(), vec![b, c, a]);
    d.undo();
    assert_eq!(d.boards_in_order(), vec![a, b, c]);
}

/// **Boards from before they had an order still move.** They all read `0`,
/// and the midpoint between two zeros is nowhere — so the list is respaced in
/// the order it already reads, inside the same step.
#[test]
fn boards_with_no_order_of_their_own_still_move() {
    let mut d = doc();
    let a = d.create_board("Anya");
    let b = d.create_board("The Diner");
    let c = d.create_board("Night Exteriors");
    for board in [a, b, c] {
        d.set(board, shotlister_engine::f::ORDER, shotlister_engine::value::Value::Float(0.0));
    }
    let before = d.boards_in_order();

    d.move_board_to(before[0], 1);
    assert_eq!(d.boards_in_order(), vec![before[1], before[0], before[2]]);
    d.move_board_to(before[2], 0);
    assert_eq!(d.boards_in_order(), vec![before[2], before[1], before[0]]);
}
