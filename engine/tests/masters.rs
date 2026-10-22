//! **A shot other shots stand in for.**
//!
//! A film breaks a scene up and comes back to the same setup later. Describing
//! it twice is how two descriptions of one thing drift apart, so one shot is
//! the master and the others point at it and show what it shows. His ask,
//! 2026-08-22, carried over from the old app: *"they were tied together with
//! auto update, and you would know what shot it was referring to, even if it
//! was in another scene."*
//!
//! What is pinned here is mostly what must **not** happen: no chains, no shot
//! standing in for itself, and nothing lost when a link is cut.

use shotlister_engine::doc::f;
use shotlister_engine::{DeviceId, Doc, Value};

fn film() -> (Doc, shotlister_engine::Id, shotlister_engine::Id) {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Masters");
    let one = doc.create_scene("1");
    let two = doc.create_scene("2");
    let (master, _) = doc.add_shot_to_scene(one);
    doc.set(master, f::DESCRIPTION, Value::text("Wide of the room"));
    doc.set(master, f::SIZE, Value::text("W"));
    let (follower, _) = doc.add_shot_to_scene(two);
    doc.set(follower, f::DESCRIPTION, Value::text("something else"));
    (doc, master, follower)
}

#[test]
fn a_linked_shot_is_described_by_its_master() {
    let (mut doc, master, follower) = film();
    doc.link_shot(follower, Some(master));

    assert_eq!(doc.master_of(follower), Some(master));
    assert_eq!(doc.described_by(follower), master);
    // The master is one by the act of being linked to.
    assert!(doc.is_master(master));
    // And the shot standing in for it is not itself a master.
    assert!(!doc.is_master(follower));
}

#[test]
fn a_master_never_stands_in_for_anything() {
    let (mut doc, master, follower) = film();
    doc.link_shot(follower, Some(master));
    // Making the follower a master has to cut its own link, or it would be
    // both at once and a reader could go round for ever.
    doc.set_master(follower, true);
    assert_eq!(doc.master_of(follower), None);
    assert!(doc.is_master(follower));
}

#[test]
fn linking_to_a_linked_shot_links_to_what_it_stands_in_for() {
    let (mut doc, master, follower) = film();
    doc.link_shot(follower, Some(master));
    let first = doc.scenes_in_order()[0];
    let (third, _) = doc.add_shot_to_scene(first);
    doc.link_shot(third, Some(follower));
    assert_eq!(doc.master_of(third), Some(master), "a chain formed");
}

#[test]
fn a_shot_cannot_stand_in_for_itself() {
    let (mut doc, master, _) = film();
    doc.link_shot(master, Some(master));
    assert_eq!(doc.master_of(master), None);
}

#[test]
fn cutting_a_link_keeps_what_was_being_shown() {
    let (mut doc, master, follower) = film();
    doc.link_shot(follower, Some(master));
    doc.link_shot(follower, None);

    assert_eq!(doc.master_of(follower), None);
    // **Report, never destroy.** Unlinking leaves the shot saying what it was
    // saying a moment ago, not what it said before it was ever linked.
    let said = doc
        .get(follower)
        .and_then(|r| r.text(f::DESCRIPTION).map(str::to_string));
    assert_eq!(said.as_deref(), Some("Wide of the room"));
    assert_eq!(
        doc.get(follower).and_then(|r| r.text(f::SIZE)),
        Some("W"),
        "the technical fields come across too"
    );
}

#[test]
fn a_master_that_stops_being_one_lets_its_followers_go_whole() {
    let (mut doc, master, follower) = film();
    doc.link_shot(follower, Some(master));
    doc.set_master(master, false);

    assert!(!doc.is_master(master));
    assert_eq!(doc.master_of(follower), None);
    assert_eq!(
        doc.get(follower).and_then(|r| r.text(f::DESCRIPTION)),
        Some("Wide of the room"),
        "a follower cut loose keeps what it was showing"
    );
}

/// **The page and the sheet say what the table says.** A shot standing in for
/// a master printed blank on the PDF and in Excel while the table showed it
/// full, because the export row read the shot's own record (2026-09-30).
#[test]
fn a_follower_prints_its_masters_words_and_keeps_its_own_number() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("8");
    let (master, _) = d.add_shot_to_scene(scene);
    let (follower, follower_at) = d.add_shot_to_scene(scene);
    d.set(master, f::DESCRIPTION, "The wide");
    d.set_vocab_field(master, "lens", "24mm");
    d.link_shot(follower, Some(master));
    d.strike(follower, true);

    let row = d.row(follower_at).expect("a row");
    assert_eq!(row.description, "The wide");
    assert_eq!(row.lens, "24mm");
    assert_eq!(row.number, "8B", "its own number");
    assert!(row.struck, "its own Shot mark");
}
