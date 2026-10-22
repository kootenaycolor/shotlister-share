//! What hangs on things, and the reference boards.

mod common;
use common::*;

/// A shot with two frames, a location and a board, the files real on disk.
fn pinned(name: &str) -> (Scratch, Open) {
    let (scratch, mut s) = opened(name);
    ok(&mut s, "add_scene", &[("number", "4")]);
    ok(&mut s, "add_shot", &[("scene", "4")]);
    ok(&mut s, "add_location", &[("name", "Barn")]);
    ok(&mut s, "add_reference_board", &[("name", "Night Exteriors")]);
    for (file, bytes) in [("wide.jpg", b"one picture".as_slice()), ("close.jpg", b"another picture".as_slice())] {
        let path = scratch.0.join(file);
        std::fs::write(&path, bytes).unwrap();
        ok(&mut s, "attach", &[("shot", "4A"), ("path", path.to_str().unwrap())]);
    }
    (scratch, s)
}

#[test]
fn a_shots_frames_captioned_ordered_and_led() {
    let (_x, mut s) = pinned("frames");
    let listed = ok(&mut s, "attachments", &[("shot", "4A")]);
    assert!(listed.contains(r#""position":1,"name":"wide.jpg""#) && listed.contains(r#""lead":true"#), "{listed}");

    let said = ok(&mut s, "update_attachment", &[("shot", "4A"), ("attachment", "close"), ("caption", "Tighter"), ("position", "1"), ("lead", "true")]);
    assert_eq!(said, "close.jpg on shot 4A: captioned, moved to 1, the lead frame.");
    let listed = ok(&mut s, "attachments", &[("shot", "4A")]);
    assert!(listed.contains(r#"{"position":1,"name":"close.jpg","file":"close.jpg","kind":"image","caption":"Tighter","lead":true}"#), "{listed}");

    ok(&mut s, "update_attachment", &[("shot", "4A"), ("attachment", "2"), ("name", "Master")]);
    assert!(ok(&mut s, "attachments", &[("shot", "4A")]).contains(r#""name":"Master.jpg""#));
    assert!(no(&mut s, "update_attachment", &[("scene", "4"), ("attachment", "1"), ("lead", "true")]).contains("Nothing is pinned to scene 4"));
    assert!(no(&mut s, "update_attachment", &[("shot", "4A"), ("attachment", "9"), ("caption", "x")]).contains("It holds: 1 close.jpg, 2 Master.jpg"));
}

#[test]
fn a_picture_hangs_somewhere_else_without_an_upload() {
    let (_x, mut s) = pinned("copy");
    assert_eq!(ok(&mut s, "copy_attachment", &[("shot", "4A"), ("attachment", "1"), ("to_location", "Barn")]), "wide.jpg is on Barn too.");
    assert_eq!(ok(&mut s, "copy_attachment", &[("shot", "4A"), ("attachment", "wide.jpg"), ("to_board", "night exteriors")]), "wide.jpg is on the Night Exteriors board too.");
    assert!(ok(&mut s, "locations", &[]).contains(r#""photographs":1"#));

    // Three uses of one file: taking one off keeps the file.
    let said = ok(&mut s, "remove_attachment", &[("location", "Barn"), ("attachment", "1")]);
    assert!(said.contains("still used elsewhere"), "{said}");
    let said = ok(&mut s, "copy_attachment", &[("shot", "4A"), ("attachment", "close.jpg"), ("to_scene", "4"), ("move", "true")]);
    assert_eq!(said, "Moved close.jpg from shot 4A to scene 4.");
    let said = ok(&mut s, "remove_attachment", &[("scene", "4"), ("attachment", "close")]);
    assert!(said.contains("the file goes too"), "{said}");
    assert!(no(&mut s, "copy_attachment", &[("shot", "4A"), ("attachment", "1")]).contains("Say where it goes"));
}

#[test]
fn reference_boards_made_moved_linked_and_removed() {
    let (_x, mut s) = pinned("boards");
    ok(&mut s, "add_reference_board", &[("name", "Kitchen")]);
    assert!(no(&mut s, "add_reference_board", &[("name", "kitchen")]).contains("already"));
    ok(&mut s, "add_scene", &[("number", "5")]);
    let said = ok(&mut s, "update_reference_board", &[("board", "Kitchen"), ("position", "1"), ("scenes", "4, 5")]);
    assert_eq!(said, "The Kitchen board hangs on scenes 4, 5.");
    ok(&mut s, "update_reference_board", &[("board", "Kitchen"), ("remove_scene", "4")]);
    let boards = ok(&mut s, "reference_boards", &[]);
    assert!(boards.starts_with(r#"[{"name":"Kitchen","pictures":0,"scenes":["5"]}"#), "{boards}");
    assert!(no(&mut s, "delete_reference_board", &[("board", "Kitchen")]).contains("scene 5"));
    ok(&mut s, "delete_reference_board", &[("board", "Kitchen"), ("even_if_used", "true")]);
    assert!(no(&mut s, "update_reference_board", &[("board", "Kitchen"), ("name", "x")]).contains("The boards are Night Exteriors"));
}

/// The Media window's three, through the connector (SL-1687): every picture
/// with where it is used, Delete Unused, and the names left behind.
#[test]
fn media_listed_and_deleted_for_real() {
    let (scratch, mut s) = pinned("library");
    let listed = ok(&mut s, "media", &[]);
    assert!(listed.contains(r#""count":2"#) && listed.contains(r#""unused":0"#), "{listed}");
    assert!(listed.contains(r#""used_on":["Shot 4A"]"#), "{listed}");

    // Taken off its shot, the picture is unused but still there.
    ok(&mut s, "remove_attachment", &[("shot", "4A"), ("attachment", "close")]);
    let listed = ok(&mut s, "media", &[("show", "unused")]);
    assert!(!listed.contains("close.jpg"), "a removed last use takes the record: {listed}");

    // Deleted by name: its use goes, the name stays.
    let said = ok(&mut s, "delete_media", &[("media", "wide.jpg")]);
    assert!(said.starts_with("Deleted 1 picture"), "{said}");
    let listed = ok(&mut s, "media", &[]);
    assert!(listed.contains(r#""count":0"#), "{listed}");
    let gone = ok(&mut s, "media", &[("show", "deleted")]);
    assert!(gone.contains(r#""file":"wide.jpg""#) && gone.contains("deleted_on"), "{gone}");
    assert!(no(&mut s, "delete_media", &[("media", "wide.jpg")]).contains("already deleted"));
    assert!(no(&mut s, "delete_media", &[("media", "nothing.jpg")]).contains("no picture called"));
    assert_eq!(ok(&mut s, "delete_unused_media", &[]), "Nothing is unused.");
    drop(scratch);
}

// ---- Print Frame and picture arrows (2026-10-14) ------------------------

fn call(s: &mut Open, tool: &str, json: &str) -> Result<String, String> {
    s.call(tool, &json::parse(json).expect("test arguments are JSON"))
}

#[test]
fn a_print_frame_set_read_and_cleared() {
    let (x, mut s) = pinned("printframe");
    let clip = x.0.join("take.mov");
    std::fs::write(&clip, b"a moving picture").unwrap();
    ok(&mut s, "attach", &[("shot", "4A"), ("path", clip.to_str().unwrap())]);

    let read = ok(&mut s, "print_frame", &[("shot", "4A")]);
    assert!(read.contains(r#""print_frame":null"#) && read.contains(r#""name":"take.mov""#), "{read}");

    let said = call(&mut s, "set_print_frame", r#"{"shot":"4A","frames":[{"attachment":3,"at":2.5},{"attachment":"wide"},{"attachment":3,"at":9}],"layout":"side",
        "arrows":[{"points":[[0.1,0.5],[0.5,0.3],[0.9,0.5]],"dashed":true,"look":"red"}]}"#).unwrap();
    assert!(said.contains("3 frames, side, numbered") && said.contains("when the Mac next opens the project"), "{said}");
    let read = ok(&mut s, "print_frame", &[("shot", "4A")]);
    assert!(read.contains(r#""layout":"side""#) && read.contains(r#""at":2.5"#) && read.contains(r#""printed":false"#), "{read}");
    assert!(read.contains(r#""look":"red""#) && read.contains(r#""dashed":true"#), "{read}");

    // A still takes no time; a layout that does not exist is refused.
    assert!(call(&mut s, "set_print_frame", r#"{"shot":"4A","frames":[{"attachment":1,"at":3}]}"#).unwrap_err().contains("still"));
    assert!(no(&mut s, "set_print_frame", &[("shot", "4A"), ("layout", "spiral")]).contains("No layout spiral"));
    // Only the layout: the frames and arrows stay.
    ok(&mut s, "set_print_frame", &[("shot", "4A"), ("layout", "under")]);
    let read = ok(&mut s, "print_frame", &[("shot", "4A")]);
    assert!(read.contains(r#""layout":"under""#) && read.contains(r#""at":9"#) && read.contains(r#""look":"red""#), "{read}");

    ok(&mut s, "set_print_frame", &[("shot", "4A"), ("clear", "true")]);
    assert!(ok(&mut s, "print_frame", &[("shot", "4A")]).contains(r#""print_frame":null"#));
}

#[test]
fn arrows_on_a_picture_set_and_read() {
    let (_x, mut s) = pinned("picturearrows");
    let said = call(&mut s, "picture_arrows", r#"{"shot":"4A","attachment":"1","arrows":[
        {"points":[[0.2,0.6],[0.2,0.25],[0.8,0.25]],"shape":"corner","heads":2,"weight":"L"},
        {"points":[[0.1,0.1],[0.9,0.1]]},
        {"points":[[0.5,0.9],[0.5,0.2]],"thickness":2.2,"depth":"toward","strength":0.8}]}"#).unwrap();
    assert_eq!(said, "3 arrows on wide.jpg on shot 4A.");
    let read = ok(&mut s, "picture_arrows", &[("shot", "4A"), ("attachment", "1")]);
    assert!(read.contains(r#""points":[[0.2,0.6],[0.2,0.25],[0.8,0.25]],"shape":"corner","heads":2"#), "{read}");
    assert!(read.contains(r#""thickness":1.4"#), "{read}");
    assert!(read.contains(r#""thickness":2.2,"depth":"toward","strength":0.8"#), "{read}");
    assert!(call(&mut s, "picture_arrows", r#"{"shot":"4A","attachment":"1","arrows":[{"points":[[0.1,0.1],[0.2,0.2]],"depth":"sideways"}]}"#).is_err());
    assert!(call(&mut s, "picture_arrows", r#"{"shot":"4A","attachment":"1","arrows":[{"points":[[0.1,0.1],[0.2,0.2]],"thickness":7}]}"#).is_err());
    assert!(call(&mut s, "picture_arrows", r#"{"shot":"4A","attachment":"1","arrows":[{"points":[[0.1,0.1]]}]}"#).is_err());
    ok(&mut s, "picture_arrows", &[("shot", "4A"), ("attachment", "1"), ("clear", "true")]);
    assert!(ok(&mut s, "picture_arrows", &[("shot", "4A"), ("attachment", "1")]).contains(r#""arrows":[]"#));
}
