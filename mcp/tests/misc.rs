//! Redo, a draft's name, and the Diagram's film-wide moves.

mod common;
use common::*;

#[test]
fn redo_puts_back_what_undo_took() {
    let (_x, mut s) = opened("redo");
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_shot", &[("scene", "1")]);
    ok(&mut s, "undo", &[]);
    assert_eq!(ok(&mut s, "shots", &[("scene", "1")]), "[]");
    assert_eq!(ok(&mut s, "redo", &[]), "Redid Add shot.");
    assert!(ok(&mut s, "shots", &[("scene", "1")]).contains("1A"));
    assert_eq!(ok(&mut s, "redo", &[]), "There is nothing to redo.");
}

#[test]
fn a_draft_is_renamed() {
    let (_x, mut s) = opened("draft-name");
    ok(&mut s, "apply_draft", &[("text", "INT. KITCHEN - DAY\n\nTea.\n"), ("revision_name", "Pink")]);
    assert_eq!(ok(&mut s, "rename_draft", &[("draft", "latest"), ("name", "Pink, 30 Sep")]), "Pink is Pink, 30 Sep now.");
    assert!(ok(&mut s, "revisions", &[]).contains(r#""name":"Pink, 30 Sep""#));
    assert!(no(&mut s, "rename_draft", &[("draft", "Blue"), ("name", "x")]).contains("The drafts are Pink, 30 Sep"));
}

#[test]
fn a_diagram_is_copied_and_a_switch_flipped_everywhere() {
    let (_x, mut s) = opened("diagram-copy");
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_scene", &[("number", "2")]);
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"wall","x":4,"y":0,"x2":4,"y2":3}]}"#)]);
    assert_eq!(ok(&mut s, "copy_diagram", &[("scene", "2"), ("from", "1")]), "2 things now on scene 2.");
    assert!(no(&mut s, "copy_diagram", &[("scene", "2"), ("from", "1")]).contains("scene 2 has 2 things"));
    ok(&mut s, "copy_diagram", &[("scene", "2"), ("from", "1"), ("even_if_drawn", "true")]);
    // Add on top keeps what is there.
    assert_eq!(ok(&mut s, "copy_diagram", &[("scene", "2"), ("from", "1"), ("mode", "add")]), "2 things added to scene 2.");
    assert_eq!(ok(&mut s, "diagram_scenes", &[]).matches(r#""things":4"#).count(), 1);
    ok(&mut s, "undo", &[]);
    // Sent to several scenes at once, and some pieces only.
    ok(&mut s, "add_scene", &[("number", "3")]);
    assert_eq!(ok(&mut s, "send_diagram", &[("scene", "1"), ("to", "2, 3")]), "2 things added to scenes 2, 3.");
    let wall = ok(&mut s, "diagram", &[("scene", "1")]);
    let id = wall.split(r#""id":""#).nth(1).unwrap().split('"').next().unwrap().to_string();
    assert_eq!(ok(&mut s, "send_diagram", &[("scene", "1"), ("to", "3"), ("ids", &id)]), "1 thing added to scene 3.");
    assert!(no(&mut s, "send_diagram", &[("scene", "1"), ("to", "2"), ("mode", "replace")]).contains("scene 2 has 4 things"));
    assert!(no(&mut s, "send_diagram", &[("scene", "1"), ("to", "1")]).contains("onto itself"));
    assert_eq!(ok(&mut s, "diagram_everywhere", &[("setting", "beams"), ("value", "true")]), "beams is set on 3 scenes.");
    assert!(ok(&mut s, "diagram", &[("scene", "2")]).contains(r#""beams":true"#));
}

#[test]
fn a_loose_plan_is_drawn_copied_renamed_and_deleted() {
    let (_x, mut s) = opened("diagram-plans");
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"camera","x":1,"y":1,"new_shot":true}]}"#)]);
    assert_eq!(ok(&mut s, "new_plan", &[("name", "Recce")]), "Made the plan Recce.");
    // A camera on a plan stands for no shot, even asked for one.
    ok(&mut s, "edit_diagram", &[("scene", "Recce"), ("op", r#"{"op":"add","els":[{"kind":"camera","x":0,"y":0,"new_shot":true}]}"#)]);
    let plan = ok(&mut s, "diagram", &[("scene", "plan: Recce")]);
    assert!(plan.contains(r#""kind":"camera""#) && !plan.contains(r#""shot":""#) && plan.contains(r#""shots":[]"#), "{plan}");
    assert_eq!(ok(&mut s, "new_plan", &[("from", "1")]), "Made the plan Plan 1, a copy of 1: 2 things.");
    assert_eq!(ok(&mut s, "plans", &[]), r#"[{"plan":"Recce","things":1},{"plan":"Plan 1","things":2}]"#);
    assert_eq!(ok(&mut s, "send_diagram", &[("scene", "Plan 1"), ("to", "Recce")]), "2 things added to scene Recce.");
    assert!(no(&mut s, "new_plan", &[("name", "recce")]).contains("already"));
    assert_eq!(ok(&mut s, "rename_plan", &[("plan", "Recce"), ("name", "Warehouse")]), "Recce is Warehouse now.");
    assert_eq!(ok(&mut s, "delete_plan", &[("plan", "Warehouse")]), "Deleted the plan Warehouse and the 3 things on it.");
    assert_eq!(ok(&mut s, "plans", &[]), r#"[{"plan":"Plan 1","things":2}]"#);
    ok(&mut s, "undo", &[]);
    assert!(ok(&mut s, "plans", &[]).contains("Warehouse"));
    // A scene's own list of plans does not count a loose one.
    assert_eq!(ok(&mut s, "diagram_scenes", &[]).matches(r#""scene":"#).count(), 1);
}

#[test]
fn a_draft_taken_in_without_a_date_is_still_listed() {
    let (_x, mut s) = opened("draft-dated");
    ok(&mut s, "apply_draft", &[("text", "1 INT. KITCHEN - DAY 1\n\nTea.\n")]);
    let drafts = ok(&mut s, "revisions", &[]);
    assert!(drafts.contains(r#""latest":true"#), "{drafts}");
    assert!(drafts.contains(r#""dated":"20"#), "stamped with today: {drafts}");
}

#[test]
fn a_shot_holds_lines_of_a_films_screenplay() {
    let (_x, mut s) = opened("script-lines");
    let one = "1 INT. KITCHEN - DAY 1\n\nANNA pours tea.\n\nANNA\nMorning.\n\n2 INT. HALL - NIGHT 2\n\nBEN\nMorning.\n";
    ok(&mut s, "apply_draft", &[("text", one), ("revision_name", "White")]);
    ok(&mut s, "add_shot", &[("scene", "2")]);
    // The shot's own scene first: scene 2's Morning, not scene 1's.
    assert_eq!(ok(&mut s, "tie_lines", &[("shot", "2A"), ("text", "Morning.")]), "2A holds: Morning. (p. 1).");
    let lines = ok(&mut s, "script_lines", &[]);
    assert!(lines.contains(r#""scene":"2""#), "{lines}");
    assert_eq!(ok(&mut s, "tie_lines", &[("shot", "2A"), ("text", "BEN"), ("mode", "add")]), "2A holds: BEN … Morning. (p. 1).");
    assert!(no(&mut s, "tie_lines", &[("shot", "2A"), ("text", "not in it")]).contains("not in the script"));
    assert_eq!(ok(&mut s, "tie_lines", &[("shot", "2A"), ("text", "BEN"), ("mode", "remove")]), "2A holds: Morning. (p. 1).");
    // A new draft cuts the words: reported, kept.
    ok(&mut s, "apply_draft", &[("text", &one.replace("BEN\nMorning.", "BEN\nHello?")), ("revision_name", "Blue"), ("dated", "2099-01-01T00:00:00Z")]);
    let lines = ok(&mut s, "script_lines", &[]);
    assert!(lines.contains(r#""not_in_this_draft":["Morning."]"#), "{lines}");
    assert!(ok(&mut s, "script_lines", &[("draft", "White")]).contains(r#""scene":"2""#));
    assert_eq!(ok(&mut s, "tie_lines", &[("shot", "2A"), ("text", "")]), "2A holds no lines.");
}
