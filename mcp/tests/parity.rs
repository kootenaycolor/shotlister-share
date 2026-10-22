//! **Anything he can do, the connector can** (2026-10-17, the parity pass):
//! the tools and options that pass added — Move to Shoot, Schedule Remaining,
//! several shots onto a day together, Rename Scan, an edit reference's clip,
//! crop and trim, a reference board's tiles, Drive switch and tags, tags on
//! scenes and locations, version rename and delete, the Document page's type
//! and frames, and Settle Times of Day.

mod common;
use common::*;
use shotlister_engine::media::MediaKind;
use shotlister_mcp::Films;

fn day_run(said: &str, day: &str) -> String {
    said.lines().find(|l| l.starts_with(day)).unwrap_or(said).to_string()
}

#[test]
fn a_part_scheduled_scene_brings_only_what_is_left() {
    let (_x, mut s) = opened("parity-remaining");
    ok(&mut s, "add_scene", &[("number", "15")]);
    ok(&mut s, "add_shot", &[("scene", "15")]);
    ok(&mut s, "add_scene", &[("number", "16")]);
    for _ in 0..5 {
        ok(&mut s, "add_shot", &[("scene", "16")]);
    }
    ok(&mut s, "add_day", &[("date", "2026-11-02")]);
    ok(&mut s, "add_day", &[("date", "2026-11-03")]);
    ok(&mut s, "schedule_scene", &[("scenes", "15"), ("day", "Day 1")]);
    ok(&mut s, "schedule_shot", &[("shots", "16B, 16C"), ("day", "Day 2")]);
    let said = ok(&mut s, "schedule_scene", &[("scenes", "16"), ("day", "Day 1"), ("before", "15")]);
    assert_eq!(said, "Day 1 (2026-11-02): scenes 16, 15.");
    let sched = ok(&mut s, "schedule", &[]);
    // Day 2 kept its two; the three left went to Day 1.
    assert!(sched.contains(r#""run":["16B","16C"]"#), "{sched}");
    assert!(sched.contains(r#""run":["16A","16D","16E","15A"]"#), "{sched}");
}

#[test]
fn several_shots_onto_a_day_stand_together() {
    let (_x, mut s) = opened("parity-shots");
    for n in ["1", "2", "3"] {
        ok(&mut s, "add_scene", &[("number", n)]);
        ok(&mut s, "add_shot", &[("scene", n)]);
        ok(&mut s, "add_shot", &[("scene", n)]);
    }
    ok(&mut s, "add_day", &[("date", "2026-11-02")]);
    ok(&mut s, "schedule_scene", &[("scenes", "1"), ("day", "Day 1")]);
    let said = ok(&mut s, "schedule_shot", &[("shots", "3A, 2B"), ("day", "Day 1"), ("before", "1")]);
    // Two scenes with no strip on the day: they stand together ahead of 1.
    assert_eq!(said, "Day 1 (2026-11-02) runs: 3A, 2B, 1A, 1B.");
    let sched = ok(&mut s, "schedule", &[]);
    let one = sched.find(r#""scene":"1""#).unwrap();
    let three = sched.find(r#""scene":"3""#).unwrap();
    let two = sched.find(r#""scene":"2""#).unwrap();
    assert!(three < one && two < one, "{sched}");
    let _ = day_run(&said, "Day 1");
}

#[test]
fn scenes_move_to_a_shoot() {
    const S1: &str = "b211a308026286ea6fba6436ae9b4891";
    const S2: &str = "4acab7b3b555897c7c58dce7762aca55";
    let (_x, mut s) = opened("parity-shoot");
    for n in ["1", "2"] {
        ok(&mut s, "add_scene", &[("number", n)]);
        ok(&mut s, "add_shot", &[("scene", n)]);
    }
    assert!(no(&mut s, "move_to_shoot", &[("scenes", "1"), ("shoot", "2")]).contains("no shoots"));
    {
        let doc = s.films_mut().doc_mut().unwrap();
        doc.set_card(shotlister_engine::card::Card::read(&format!(
            r#"{{"facts":{{}},"shoots":[{{"id":"{S1}","label":"Shoot 1","kind":"Shoot 1","n":1,"start":"2026-07-09","state":"Wrapped"}},{{"id":"{S2}","label":"Style Server","kind":"Shoot 2","n":2,"start":"2026-10-06","state":"Next"}}]}}"#
        )));
    }
    assert_eq!(ok(&mut s, "move_to_shoot", &[("scenes", "2"), ("shoot", "2")]), "Scene 2 is now in Shoot 2.");
    assert_eq!(ok(&mut s, "move_to_shoot", &[("scenes", "1"), ("shoot", "style server")]), "Scene 1 is now in Shoot 2.");
    assert_eq!(ok(&mut s, "move_to_shoot", &[("scenes", "1"), ("shoot", S2)]), "Scene 1 is already in Shoot 2.");
    assert_eq!(ok(&mut s, "move_to_shoot", &[("scenes", "1"), ("shoot", "Shoot 1")]), "Scene 1 is now in Shoot 1.");
    assert!(no(&mut s, "move_to_shoot", &[("scenes", "1"), ("shoot", "Malibu")]).contains("Shoot 1, Shoot 2"));
    assert_eq!(
        {
            let raw = ok(&mut s, "scenes", &[("shoot", "2")]);
            raw.matches(r#""number":"#).count()
        },
        1
    );
}

#[test]
fn a_scan_is_renamed_and_listed_by_location() {
    let (_x, mut s) = opened("parity-scan");
    ok(&mut s, "add_location", &[("name", "Ellis House")]);
    let text = r#"{"walls":[]}"#;
    let hash = shotlister_engine::sha256(text.as_bytes());
    s.films_mut().keep_media(&hash.to_hex(), "json", text.as_bytes()).unwrap();
    {
        let doc = s.films_mut().doc_mut().unwrap();
        let place = doc.locations_in_order()[0];
        let plan = doc.add_media(hash, MediaKind::ScanShape, 0, 0, text.len() as u64, "Kitchen 0930.json");
        doc.attach_media(place, plan, "");
    }
    let listed = ok(&mut s, "room_scans", &[("location", "Ellis House")]);
    assert!(listed.contains(r#""scan":"Kitchen 0930""#), "{listed}");
    assert!(no(&mut s, "room_scans", &[]).contains("Say which scene, or which location"));
    assert_eq!(ok(&mut s, "rename_scan", &[("location", "Ellis House"), ("scan", "kitchen 0930"), ("name", "Kitchen")]), "Kitchen 0930 is now Kitchen.");
    assert!(ok(&mut s, "room_scans", &[("location", "Ellis House")]).contains(r#""scan":"Kitchen""#));
    assert!(no(&mut s, "rename_scan", &[("location", "Ellis House"), ("scan", "Attic"), ("name", "X")]).contains("Its scans: Kitchen"));
}

#[test]
fn an_edit_reference_takes_a_clip_the_project_holds() {
    let (x, mut s) = opened("parity-editref");
    ok(&mut s, "add_scene", &[("number", "4")]);
    ok(&mut s, "add_shot", &[("scene", "4")]);
    ok(&mut s, "add_shot", &[("scene", "4")]);
    ok(&mut s, "add_reference_board", &[("name", "Cuts")]);
    let clip = x.0.join("cut.mov");
    std::fs::write(&clip, b"a moving picture").unwrap();
    ok(&mut s, "attach", &[("board", "Cuts"), ("path", clip.to_str().unwrap())]);
    ok(&mut s, "add_edit_reference", &[("name", "Opening"), ("shots", "4A, 4B")]);
    let said = ok(&mut s, "copy_attachment", &[("board", "Cuts"), ("attachment", "1"), ("to_edit_reference", "opening")]);
    assert_eq!(said, "cut.mov is on the Opening edit reference too.");
    let listed = ok(&mut s, "attachments", &[("edit_reference", "Opening")]);
    assert!(listed.contains(r#""name":"cut.mov""#) && listed.contains(r#""kind":"video""#), "{listed}");
    assert!(ok(&mut s, "edit_references", &[]).contains("cut.mov"));
    // Its own use of the clip can be captioned, and taken off again.
    assert_eq!(ok(&mut s, "update_attachment", &[("edit_reference", "Opening"), ("attachment", "1"), ("caption", "v2")]), "cut.mov on the Opening edit reference: captioned.");
    assert!(ok(&mut s, "remove_attachment", &[("edit_reference", "Opening"), ("attachment", "1")]).contains("still used elsewhere"));
}

#[test]
fn a_picture_is_cropped_and_a_clip_trimmed() {
    let (x, mut s) = opened("parity-crop");
    ok(&mut s, "add_scene", &[("number", "4")]);
    ok(&mut s, "add_shot", &[("scene", "4")]);
    let still = x.0.join("wide.jpg");
    std::fs::write(&still, b"one picture").unwrap();
    let clip = x.0.join("take.mov");
    std::fs::write(&clip, b"a moving picture").unwrap();
    ok(&mut s, "attach", &[("shot", "4A"), ("path", still.to_str().unwrap())]);
    ok(&mut s, "attach", &[("shot", "4A"), ("path", clip.to_str().unwrap())]);

    let call = |s: &mut Open, json: &str| s.call("update_attachment", &json::parse(json).unwrap());
    let said = call(&mut s, r#"{"shot":"4A","attachment":"1","crop":{"x":0.3,"y":0.6,"scale":2}}"#).unwrap();
    assert_eq!(said, "wide.jpg on shot 4A: cropped at 0.30, 0.60 ×2.");
    let listed = ok(&mut s, "attachments", &[("shot", "4A")]);
    assert!(listed.contains(r#""crop":{"x":0.3,"y":0.6,"scale":2}"#), "{listed}");
    assert!(call(&mut s, r#"{"shot":"4A","attachment":"1","trim":{"start":1,"end":2}}"#).unwrap_err().contains("not a clip"));
    let said = call(&mut s, r#"{"shot":"4A","attachment":"take","trim":{"start":1.5,"end":4}}"#).unwrap();
    assert_eq!(said, "take.mov on shot 4A: plays 1.5s to 4s.");
    assert!(ok(&mut s, "attachments", &[("shot", "4A")]).contains(r#""trim":{"start":1.5,"end":4}"#));
    assert!(call(&mut s, r#"{"shot":"4A","attachment":"take","trim":{"start":4,"end":1}}"#).unwrap_err().contains("ends after it starts"));
    call(&mut s, r#"{"shot":"4A","attachment":"take","clear_trim":true}"#).unwrap();
    call(&mut s, r#"{"shot":"4A","attachment":"1","clear_crop":true}"#).unwrap();
    let listed = ok(&mut s, "attachments", &[("shot", "4A")]);
    assert!(!listed.contains("\"trim\"") && !listed.contains("\"crop\""), "{listed}");
}

#[test]
fn boards_scenes_and_locations_take_their_settings_and_tags() {
    let (_x, mut s) = opened("parity-tags");
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_location", &[("name", "Barn")]);
    ok(&mut s, "add_reference_board", &[("name", "Night")]);
    let said = ok(&mut s, "update_reference_board", &[("board", "Night"), ("tiles", "square"), ("sync_with_drive", "true"), ("tags", "night, exterior")]);
    assert!(!said.is_empty());
    assert!(no(&mut s, "update_reference_board", &[("board", "Night"), ("tiles", "round")]).contains("original, square or project"));
    ok(&mut s, "update_scene", &[("scene", "1"), ("tags", "night, stunt")]);
    assert!(ok(&mut s, "scenes", &[]).contains(r#""tags":"night, stunt""#));
    ok(&mut s, "update_location", &[("location", "Barn"), ("tags", "exterior")]);
    assert!(ok(&mut s, "locations", &[]).contains(r#""tags":"exterior""#));
    // One tag list for all of them.
    let tags = ok(&mut s, "lists", &[("list", "tags")]);
    for t in ["night", "exterior", "stunt"] {
        assert!(tags.contains(t), "{tags}");
    }
    let doc = s.films_mut().doc().unwrap();
    let board = doc.boards_in_order()[0];
    let r = doc.get(board).unwrap();
    assert_eq!(r.text("board_ratio"), Some("square"));
    assert_eq!(r.text("sync_with_drive"), Some("1"));
}

#[test]
fn a_version_is_renamed_and_deleted() {
    let (_x, mut s) = opened("parity-versions");
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "save_version", &[("name", "Before")]);
    assert_eq!(ok(&mut s, "rename_version", &[("version", "before"), ("name", "Before the Pickups")]), "\u{201c}Before\u{201d} is now \u{201c}Before the Pickups\u{201d}.");
    assert!(ok(&mut s, "versions", &[]).contains("Before the Pickups"));
    ok(&mut s, "delete_version", &[("version", "Before the Pickups")]);
    assert!(!ok(&mut s, "versions", &[]).contains("Before the Pickups"));
    assert!(no(&mut s, "delete_version", &[("version", "Nope")]).contains("There is no version Nope") || no(&mut s, "delete_version", &[("version", "Nope")]).contains("no versions"));
}

#[test]
fn the_document_page_is_set_and_reset() {
    let (_x, mut s) = opened("parity-document");
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_shot", &[("scene", "1")]);
    let read = ok(&mut s, "document_page", &[]);
    assert!(read.contains(r#"{"class":"body","label":"Body","size":10.5,"face":"serif","colour":"17171a"}"#), "{read}");
    let said = ok(&mut s, "document_page", &[("class", "body"), ("size", "12"), ("face", "sans")]);
    assert!(said.starts_with("Body: 12 pt sans"), "{said}");
    assert!(ok(&mut s, "document_page", &[]).contains(r#""class":"body","label":"Body","size":12,"face":"sans""#));
    assert!(no(&mut s, "document_page", &[("class", "body"), ("case", "upper")]).contains("keeps what he typed"));
    ok(&mut s, "document_page", &[("class", "Credits"), ("case", "lower"), ("colour", "#B4531B")]);
    assert!(ok(&mut s, "document_page", &[]).contains(r#""class":"credits","label":"Credits","size":8,"face":"mono","case":"lower","colour":"b4531b""#));
    let said = ok(&mut s, "document_page", &[("shot", "1A"), ("frame", "left"), ("frame_width", "0.4")]);
    assert_eq!(said, "1A's frame sits left at 40% of the line.");
    assert!(ok(&mut s, "document_page", &[("shot", "1A")]).contains(r#""shot":{"frame":"left","frame_width":0.4}"#));
    assert!(no(&mut s, "document_page", &[("shot", "1A"), ("frame", "middle")]).contains("below, above, left or right"));
    ok(&mut s, "document_page", &[("reset", "true")]);
    assert!(ok(&mut s, "document_page", &[]).contains(r#""class":"body","label":"Body","size":10.5"#));
}

#[test]
fn settle_times_says_what_it_did() {
    let (_x, mut s) = opened("parity-times");
    ok(&mut s, "add_scene", &[("number", "1"), ("time_of_day", "NIGHT")]);
    ok(&mut s, "add_scene", &[("number", "2"), ("time_of_day", "CONTINUOUS")]);
    let said = ok(&mut s, "settle_times", &[]);
    assert!(said.starts_with("Settled") || said.starts_with("No scene"), "{said}");
}

#[test]
fn diagram2_pieces_are_named_sent_and_coloured_through_edit_diagram() {
    let (_x, mut s) = opened("parity-diagram2");
    ok(&mut s, "add_scene", &[("number", "1")]);
    let call = |s: &mut Open, json: &str| s.call("edit_diagram", &json::parse(json).unwrap());
    call(&mut s, r#"{"scene":"1","op":{"op":"add","els":[{"kind":"set","sym":"sofa","x":1,"y":1,"w":2,"h":1},{"kind":"set","sym":"sofa","x":4,"y":1,"w":2,"h":1}]}}"#).unwrap();
    let plan = ok(&mut s, "diagram", &[("scene", "1")]);
    let ids: Vec<String> = match json::parse(&plan).unwrap().get("els").cloned() {
        Some(Json::Array(els)) => els.iter().map(|e| e.str_field("id")).collect(),
        other => panic!("{other:?}"),
    };
    assert_eq!(ids.len(), 2, "{plan}");
    call(&mut s, &format!(r#"{{"scene":"1","op":{{"op":"name_piece","id":"{}","name":"Hero Sofa"}}}}"#, ids[0])).unwrap();
    call(&mut s, &format!(r##"{{"scene":"1","op":{{"op":"batch","ops":[{{"op":"update","id":"{a}","set":{{"color":"#b4531b"}}}},{{"op":"update","id":"{b}","set":{{"color":"#b4531b"}}}}]}}}}"##, a = ids[0], b = ids[1])).unwrap();
    call(&mut s, &format!(r#"{{"scene":"1","op":{{"op":"send_layer","ids":["{}"],"to":"plot"}}}}"#, ids[1])).unwrap();
    let plan = ok(&mut s, "diagram", &[("scene", "1")]);
    assert!(plan.contains("Hero Sofa"), "{plan}");
    assert_eq!(plan.matches("#b4531b").count(), 2, "{plan}");
    assert!(plan.contains(r#""layer":"plot""#), "{plan}");
}
