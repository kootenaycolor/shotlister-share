//! Versions, from a chat — and the way back on a connector with no undo.

mod common;
use common::*;

#[test]
fn a_deleted_shot_is_brought_back_from_a_version() {
    let (_x, mut s) = opened("versions");
    ok(&mut s, "add_scene", &[("number", "7")]);
    ok(&mut s, "add_shot", &[("scene", "7"), ("description", "Kept safe")]);
    ok(&mut s, "add_shot", &[("scene", "7"), ("description", "Also")]);
    assert_eq!(ok(&mut s, "save_version", &[("name", "Before the cut")]), "Saved the project as it stands as \u{201c}Before the cut\u{201d}.");
    ok(&mut s, "delete_shot", &[("shot", "7A")]);
    ok(&mut s, "update_shot", &[("shot", "7B"), ("description", "Rewritten")]);

    let listed = ok(&mut s, "versions", &[]);
    assert!(listed.contains(r#""name":"Before the cut""#) && listed.contains(r#""why":"saved by hand""#), "{listed}");
    let since = ok(&mut s, "versions", &[("version", "before the cut")]);
    // The engine's own summary, as the Mac's Versions window says it. It
    // counts shot records, and deleting a shot takes away where it sits, not
    // the record — so this reads "changed" (filed as its own row).
    assert!(since.starts_with("Since \u{201c}Before the cut\u{201d}: ") && since.contains("shot"), "{since}");

    let said = ok(&mut s, "bring_back", &[("version", "Before the cut"), ("shots", "7A")]);
    assert_eq!(said, "Brought back shot 7A as \u{201c}Before the cut\u{201d} had it.");
    let shots = ok(&mut s, "shots", &[("scene", "7")]);
    assert!(shots.contains("Kept safe") && shots.contains("Rewritten"), "only the shot asked for came back: {shots}");

    let refused = no(&mut s, "go_back_to_version", &[("version", "latest")]);
    assert!(refused.contains("Nothing was changed") && refused.contains("sure=true"), "{refused}");
    ok(&mut s, "go_back_to_version", &[("version", "Before the cut"), ("sure", "true")]);
    let shots = ok(&mut s, "shots", &[("scene", "7")]);
    assert!(shots.contains(r#""description":"Also""#), "the whole film went back: {shots}");
    assert!(ok(&mut s, "versions", &[]).contains("before going back"), "and now was kept");
    assert!(no(&mut s, "bring_back", &[("version", "Nope")]).contains("There is no version Nope"));
}
