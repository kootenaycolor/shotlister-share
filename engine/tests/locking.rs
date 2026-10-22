//! **A finished list stays finished.**
//!
//! Two rules make a project's vocabulary work while it is being written: if a
//! term is not on the list it is not in a dropdown, and typing a new term
//! teaches the project. By the time a film is shooting, the second one is the
//! one that hurts — a stray "Handheld " or a mistyped "37mmm" becomes a
//! permanent near-duplicate of a term that was already right. Locking a list
//! says it is done: nothing new gets learned into it, by any door.

use shotlister_engine::{DeviceId, Doc};

fn project() -> (Doc, shotlister_engine::Id) {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    (d, shot)
}

#[test]
fn a_list_learns_until_it_is_locked() {
    let (mut d, _) = project();
    assert!(d.learn("lens", "37mm"));
    d.set_vocabulary_locked("lens", true);
    assert!(d.vocabulary_locked("lens"));
    assert!(!d.learn("lens", "50mm"), "a locked list must not learn");
    assert_eq!(d.vocabulary("lens"), vec!["37mm".to_string()]);

    d.set_vocabulary_locked("lens", false);
    assert!(d.learn("lens", "50mm"), "unlocking lets it learn again");
}

#[test]
fn a_locked_list_refuses_a_term_it_does_not_hold() {
    let (mut d, shot) = project();
    d.set_vocab_field(shot, "lens", "37mm");
    d.set_vocabulary_locked("lens", true);

    d.set_vocab_field(shot, "lens", "50mm");
    let held = d
        .get(shot)
        .and_then(|r| r.get("lens").cloned())
        .and_then(|v| v.as_text().map(String::from));
    assert_eq!(held, Some("37mm".to_string()),
               "a term off a locked list must not land on a shot either");

    // What is on the list still writes.
    d.set_vocab_field(shot, "lens", "37mm");

    // And clearing always works: emptying is not adding.
    d.set_vocab_field(shot, "lens", "");
    let cleared = d
        .get(shot)
        .and_then(|r| r.get("lens").cloned())
        .and_then(|v| v.as_text().map(String::from));
    assert_eq!(cleared, Some(String::new()));
}

#[test]
fn a_locked_multi_list_keeps_only_the_terms_it_knows() {
    let (mut d, shot) = project();
    d.set_vocab_list(shot, "tags", &["stunt", "vfx"]);
    d.set_vocabulary_locked("tags", true);
    d.set_vocab_list(shot, "tags", &["stunt", "brand new"]);

    let held: Vec<String> = d
        .get(shot)
        .and_then(|r| r.get("tags").cloned())
        .and_then(|v| v.as_list().map(|l| l.to_vec()))
        .unwrap_or_default()
        .iter()
        .filter_map(|v| v.as_text().map(String::from))
        .collect();
    assert_eq!(held, vec!["stunt".to_string()], "the unknown term does not land");
    assert_eq!(
        d.vocabulary("tags"),
        vec!["stunt".to_string(), "vfx".to_string()],
        "and the list did not grow"
    );
}

#[test]
fn locking_one_list_leaves_the_others_alone() {
    let (mut d, _) = project();
    d.set_vocabulary_locked("lens", true);
    assert!(d.learn("size", "M/OTS"), "another list is unaffected");
    assert!(!d.vocabulary_locked("size"));
}

// ---- the standing lists ------------------------------------------------

/// **A new film starts with the lists he actually works from**, and a film that
/// started before them gets them too — his ask, 2026-08-22: "add them to my
/// current projects as well since they didn't start out with them."
#[test]
fn a_project_is_given_the_standing_lists_once() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Call Her Back");
    // Something the project taught itself before the standing lists existed.
    assert!(d.learn("size", "Wide-ish"));

    assert!(d.seed_standing_vocabularies(), "the first time seeds");

    let sizes = d.vocabulary("size");
    assert_eq!(sizes.first().map(String::as_str), Some("ESTAB."));
    assert_eq!(sizes.len(), 17, "sixteen standing, and his own kept");
    assert!(
        sizes.contains(&"Wide-ish".to_string()),
        "nothing the project already knew is taken away"
    );
    assert_eq!(d.vocabulary("angle").first().map(String::as_str), Some("Front On"));
    assert_eq!(d.vocabulary("movement").first().map(String::as_str), Some("Loose Pan/Tilt"));
    assert_eq!(d.vocabulary("support").first().map(String::as_str), Some("Handheld"));

    // And never twice: a second open must not double the list, and must not
    // undo an edit he has since made.
    d.set_vocabulary("size", &["W", "M"]);
    assert!(!d.seed_standing_vocabularies(), "the second time does nothing");
    assert_eq!(d.vocabulary("size"), vec!["W".to_string(), "M".to_string()]);
}
