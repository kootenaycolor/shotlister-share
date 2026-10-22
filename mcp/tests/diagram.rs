//! Diagram mode through the connector: the guide, a picture, which scenes
//! have a plan, favorites, the cast, a scanned room and a picture under it.

mod common;
use common::*;

use shotlister_engine::media::MediaKind;
use shotlister_mcp::films::Films;

const ROOM: &str = r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"wall","x":4,"y":0,"x2":4,"y2":3},{"kind":"cast","cast":"ANNA","x":2,"y":1.5},{"kind":"light","sym":"fresnel","x":3,"y":2.5,"rot":225},{"kind":"camera","x":1,"y":2.5,"rot":300,"new_shot":true}]}"#;

fn drawn(name: &str) -> (Scratch, Open) {
    let (x, mut s) = opened(name);
    ok(&mut s, "add_scene", &[("number", "1")]);
    ok(&mut s, "add_scene", &[("number", "2")]);
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", ROOM)]);
    (x, s)
}

/// The id of the first piece of a kind on scene 1's plan.
fn first(s: &mut Open, kind: &str) -> String {
    let plan = json::parse(&ok(s, "diagram", &[("scene", "1")])).unwrap();
    plan.get("els")
        .and_then(|e| e.as_array())
        .and_then(|els| els.iter().find(|e| e.str_field("kind") == kind))
        .map(|e| e.str_field("id"))
        .unwrap_or_else(|| panic!("no {kind}"))
}

#[test]
fn the_guide_names_every_kind_and_every_edit() {
    let (_x, mut s) = opened("diagram-guide");
    let guide = ok(&mut s, "diagram_guide", &[]);
    for kind in shotlister_engine::diagram::Kind::ALL {
        assert!(guide.contains(&format!("- {}", kind.as_str())) || guide.contains(&format!("/ {}", kind.as_str())), "guide misses {}", kind.as_str());
    }
    for op in ["add", "update", "remove", "move", "rotate", "flip", "order", "duplicate", "swap", "group", "align", "distribute", "beat", "unbeat", "settings", "clear", "batch"] {
        assert!(guide.contains(&format!("- {op} ")) || guide.contains(&format!("{op} {{")), "guide misses {op}");
    }
}

#[test]
fn which_scenes_have_a_plan_and_what_is_on_it() {
    let (_x, mut s) = drawn("diagram-scenes");
    let said = ok(&mut s, "diagram_scenes", &[]);
    assert!(said.contains(r#""scene":"1""#) && !said.contains(r#""scene":"2""#), "{said}");
    assert!(said.contains(r#""things":5"#) && said.contains(r#""cameras":1"#) && said.contains(r#""people":1"#) && said.contains(r#""lights":1"#), "{said}");
}

#[test]
fn a_scene_can_be_hidden_from_the_diagram_list_and_shown_again() {
    let (_x, mut s) = drawn("diagram-hide-scenes");
    assert_eq!(ok(&mut s, "hide_scenes_from_diagrams", &[]), "[]", "nothing hidden yet");
    let said = ok(&mut s, "hide_scenes_from_diagrams", &[("scenes", "1, 2")]);
    assert!(said.starts_with("2 scenes hidden"), "{said}");
    let list = ok(&mut s, "hide_scenes_from_diagrams", &[]);
    assert!(list.contains(r#""scene":"1""#) && list.contains(r#""scene":"2""#), "{list}");
    // Only the list moves: the diagram and the scenes themselves are as they were.
    let scenes = ok(&mut s, "diagram_scenes", &[]);
    assert!(scenes.contains(r#""hidden":true"#) && scenes.contains(r#""things":5"#), "{scenes}");
    assert!(ok(&mut s, "diagram", &[("scene", "1")]).contains(r#""kind":"camera""#));
    assert!(ok(&mut s, "hide_scenes_from_diagrams", &[("scenes", "1")]).starts_with("Already hidden"));
    let back = ok(&mut s, "hide_scenes_from_diagrams", &[("scenes", "1"), ("hidden", "false")]);
    assert!(back.starts_with("1 scene back"), "{back}");
    assert!(ok(&mut s, "diagram_scenes", &[]).contains(r#""hidden":false"#));
    assert!(no(&mut s, "hide_scenes_from_diagrams", &[("scenes", "99")]).contains("no scene 99"));
}

#[test]
fn a_picture_carries_its_colours_and_comes_back_as_a_png() {
    let (x, mut s) = drawn("diagram-picture");
    let svg = ok(&mut s, "diagram_picture", &[("scene", "1"), ("width", "800")]);
    assert!(svg.starts_with("<svg") && svg.contains("--d-wall:#"), "{}", &svg[..200.min(svg.len())]);
    assert!(no(&mut s, "diagram_picture", &[("scene", "2")]).contains("no diagram yet"));

    // Through the protocol, as Claude asks: a picture, not markup.
    let reply = s
        .handle(r#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"diagram_picture","arguments":{"scene":"1"}}}"#)
        .unwrap();
    let reply = json::parse(&reply).unwrap();
    let content = &reply.get("result").unwrap().get("content").unwrap().as_array().unwrap()[0];
    assert_eq!(content.str_field("type"), "image", "{}", reply.encode().chars().take(300).collect::<String>());
    let png = base64_decode(&content.str_field("data"));
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G']));
    // Kept for a person to look at when SHOTLISTER_KEEP_PICTURE names a file.
    if let Ok(path) = std::env::var("SHOTLISTER_KEEP_PICTURE") {
        std::fs::write(path, &png).unwrap();
    }
    drop(x);
}

#[test]
fn a_favorite_is_kept_placed_and_emptied() {
    let (_x, mut s) = drawn("diagram-favorites");
    let light = first(&mut s, "light");
    assert!(ok(&mut s, "set_diagram_favorite", &[("scene", "1"), ("slot", "3"), ("id", &light)]).starts_with("Favorite 3 is "));
    let slots = ok(&mut s, "diagram_favorites", &[]);
    assert!(slots.contains(r#""slot":3,"name":""#) && slots.contains("1K Fresnel"), "{slots}");
    let made = ok(&mut s, "place_favorite", &[("scene", "2"), ("slot", "3"), ("x", "1"), ("y", "1")]);
    assert!(made.starts_with("Made "), "{made}");
    assert!(ok(&mut s, "diagram", &[("scene", "2")]).contains(r#""kind":"light""#));
    assert!(no(&mut s, "place_favorite", &[("scene", "2"), ("slot", "4"), ("x", "0"), ("y", "0")]).contains("Favorite 4 is empty"));
    assert!(no(&mut s, "set_diagram_favorite", &[("scene", "1"), ("slot", "10"), ("id", &light)]).contains("1 to 9"));
    assert_eq!(ok(&mut s, "set_diagram_favorite", &[("scene", "1"), ("slot", "3")]), "Favorite 3 is empty.");
    ok(&mut s, "undo", &[]);
    assert!(ok(&mut s, "diagram_favorites", &[]).contains("1K Fresnel"), "emptying a slot is one undo step");
}

#[test]
fn the_cast_tool_offers_the_scene_then_the_film() {
    let (_x, mut s) = opened("diagram-cast");
    ok(&mut s, "apply_draft", &[("text", "1 INT. KITCHEN - DAY 1\n\nANNA pours tea.\n\nANNA\nMorning.\n\n2 INT. HALL - NIGHT 2\n\nBEN\nHello?\n")]);
    let cast = ok(&mut s, "diagram_cast", &[("scene", "1")]);
    let parsed = json::parse(&cast).unwrap();
    let here = parsed.get("in_this_scene").unwrap().encode();
    let rest = parsed.get("rest_of_film").unwrap().encode();
    assert!(here.contains("ANNA") && !here.contains("BEN"), "{cast}");
    assert!(rest.contains("BEN"), "{cast}");
}

#[test]
fn a_picture_is_laid_under_the_plan_from_a_file_or_from_the_film() {
    let (x, mut s) = drawn("diagram-floor");
    // A real PNG: 2 × 1, from its header out.
    let png = tiny_png();
    let file = x.0.join("floor plan.png");
    std::fs::write(&file, &png).unwrap();
    let said = ok(&mut s, "floor_picture", &[("scene", "1"), ("path", file.to_str().unwrap()), ("width", "8")]);
    assert!(said.starts_with("Laid floor plan.png under scene 1's plan, 8 m wide"), "{said}");
    let plan = ok(&mut s, "diagram", &[("scene", "1")]);
    assert!(plan.contains(r#""kind":"image""#) && plan.contains(r#""h":4"#), "laid at the picture's own shape: {plan}");

    // One the film already holds, pinned to a location.
    ok(&mut s, "add_location", &[("name", "Ellis House")]);
    ok(&mut s, "attach", &[("location", "Ellis House"), ("path", file.to_str().unwrap())]);
    let said = ok(&mut s, "floor_picture", &[("scene", "2"), ("location", "Ellis House"), ("attachment", "1"), ("over", "true")]);
    assert!(said.contains("on scene 2's plan"), "{said}");
    assert!(no(&mut s, "floor_picture", &[("scene", "2")]).contains("Say which picture"));

    // The picture inside the plan's own picture, made whole off the film.
    let svg = ok(&mut s, "diagram_picture", &[("scene", "1")]);
    assert!(svg.contains("data:image/png;base64,"), "the floor picture travels inside");
}

#[test]
fn a_scanned_room_is_laid_and_replaces_the_last() {
    let (_x, mut s) = drawn("diagram-room");
    assert!(no(&mut s, "room_scans", &[("scene", "1")]).contains("not shot at any location"));
    ok(&mut s, "add_location", &[("name", "Ellis House")]);
    ok(&mut s, "set_scene_locations", &[("scene", "1"), ("locations", "Ellis House")]);
    assert_eq!(ok(&mut s, "room_scans", &[("scene", "1")]), "[]");
    assert!(no(&mut s, "lay_room", &[("scene", "1")]).contains("No room has been scanned"));

    // The phone's two files: the shape and its measurements, sharing a name.
    let text = room_json();
    let hash = shotlister_engine::sha256(text.as_bytes());
    s.films_mut().keep_media(&hash.to_hex(), "json", text.as_bytes()).unwrap();
    {
        let doc = s.films_mut().doc_mut().unwrap();
        let place = doc.locations_in_order()[0];
        let plan = doc.add_media(hash, MediaKind::ScanShape, 0, 0, text.len() as u64, "Kitchen 0930.json");
        doc.attach_media(place, plan, "");
    }
    let scans = ok(&mut s, "room_scans", &[("scene", "1")]);
    assert!(scans.contains(r#""scan":"Kitchen 0930""#) && scans.contains(r#""measurements":true"#), "{scans}");

    let said = ok(&mut s, "lay_room", &[("scene", "1")]);
    // The four scanned walls come in as one closed room, as the Wall tool draws one.
    assert!(said.starts_with("Laid the Kitchen 0930 room on scene 1: 1 piece"), "{said}");
    let before = ok(&mut s, "diagram_scenes", &[]);
    ok(&mut s, "lay_room", &[("scene", "1"), ("scan", "kitchen 0930")]);
    assert_eq!(ok(&mut s, "diagram_scenes", &[]), before, "a room laid again replaces the last");
    assert!(no(&mut s, "lay_room", &[("scene", "1"), ("scan", "Attic")]).contains("The scans are Kitchen 0930 at Ellis House"));
}

/// A 4 × 3 room as the iPhone's RoomPlan writes it: four walls, each a
/// sixteen-float column-major transform and its dimensions.
fn room_json() -> String {
    let along_x = |x: f64, z: f64| format!(r#"{{"category":{{"wall":{{}}}},"dimensions":[4,2.5,0],"transform":[1,0,0,0, 0,1,0,0, 0,0,1,0, {x},1.25,{z},1]}}"#);
    let along_z = |x: f64, z: f64| format!(r#"{{"category":{{"wall":{{}}}},"dimensions":[3,2.5,0],"transform":[0,0,-1,0, 0,1,0,0, 1,0,0,0, {x},1.25,{z},1]}}"#);
    format!(r#"{{"walls":[{},{},{},{}]}}"#, along_x(2.0, 0.0), along_x(2.0, 3.0), along_z(0.0, 1.5), along_z(4.0, 1.5))
}

fn tiny_png() -> Vec<u8> {
    // A 2 × 1 white PNG, written out by hand.
    vec![
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x7B, 0x40, 0xE8, 0xDD, 0x00, 0x00, 0x00, 0x0F, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
        0xF8, 0xFF, 0xFF, 0x3F, 0x03, 0x42, 0x00, 0x00, 0x13, 0xF8, 0x03, 0xFD, 0x3D, 0x5F, 0x7B, 0x8A, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
        0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]
}

fn base64_decode(text: &str) -> Vec<u8> {
    const A: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::new();
    let (mut acc, mut bits) = (0u32, 0);
    for c in text.bytes().filter(|c| *c != b'=') {
        let Some(v) = A.iter().position(|a| *a == c) else { continue };
        acc = (acc << 6) | v as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    out
}

#[test]
fn the_library_answers_by_library_kind_maker_and_nickname() {
    let (_x, mut s) = opened("diagram-library");
    let whole = ok(&mut s, "diagram_library", &[]);
    assert!(whole.contains(r#""lib":"grip""#) && whole.contains(r#""frames":"#) && whole.contains("Black Pipe"), "the whole library");
    let grip = ok(&mut s, "diagram_library", &[("library", "grip")]);
    assert!(grip.contains("Speed Rail") && grip.contains("Condor") && !grip.contains("Arri M18"), "{}", &grip[..300.min(grip.len())]);
    let lamps = ok(&mut s, "diagram_library", &[("search", "4k par")]);
    assert!(lamps.contains("4K HMI PAR") && lamps.contains("Arri M40"), "{lamps}");
    let arri = ok(&mut s, "diagram_library", &[("library", "light"), ("maker", "arri"), ("kind", "HMI")]);
    assert!(arri.contains("Arri M18") && !arri.contains("Joker"), "{arri}");
}

#[test]
fn a_frame_lands_flat_and_is_dressed_by_name() {
    let (_x, mut s) = drawn("diagram-frame");
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", r#"{"op":"add","els":[{"kind":"light","sym":"frame","x":2,"y":4,"h":2.4384}]}"#)]);
    let plan = json::parse(&ok(&mut s, "diagram", &[("scene", "1")])).unwrap();
    let f = plan.get("els").and_then(|e| e.as_array()).unwrap().iter().find(|e| e.str_field("sym") == "frame").unwrap().clone();
    let id = f.str_field("id");
    assert_eq!(f.get("tilt").and_then(|t| t.as_f64()), Some(0.0), "a new frame lies flat");
    let said = ok(&mut s, "set_frame", &[("scene", "1"), ("id", &id), ("material", "Single Net"), ("frame_type", "black-pipe"), ("grid", "45"), ("tilt", "33")]);
    assert!(said.contains("Single Net"), "{said}");
    let plan = ok(&mut s, "diagram", &[("scene", "1")]);
    assert!(
        plan.contains(r#""material":"single-net""#) && plan.contains(r#""pipe":"black-pipe""#) && plan.contains(r#""grid":45"#) && plan.contains(r#""tilt":35"#),
        "{plan}"
    );
    assert!(no(&mut s, "set_frame", &[("scene", "1"), ("id", &id), ("material", "velvet")]).contains("bounce-white"));
    assert!(no(&mut s, "set_frame", &[("scene", "1"), ("id", &id), ("grid", "35")]).contains("45"));
    let lamp = first(&mut s, "light");
    assert!(no(&mut s, "set_frame", &[("scene", "1"), ("id", &lamp), ("tilt", "10")]).contains("not a frame"));
}

#[test]
fn a_name_is_renamed_moved_tied_back_and_put_back() {
    let (_x, mut s) = drawn("diagram-names");
    let lamp = first(&mut s, "light");
    let tie = format!(r#"data-el="{lamp}" data-part="tie""#);
    let set = |s: &mut Open, fields: &str| {
        ok(s, "edit_diagram", &[("scene", "1"), ("op", &format!(r#"{{"op":"update","id":"{lamp}","set":{fields}}}"#))]);
        ok(s, "diagram_picture", &[("scene", "1"), ("width", "800")])
    };
    // Its label typed (a new lamp has none, 2026-10-15), and its note.
    let svg = set(&mut s, r#"{"label":"Key","lamp_name":"Arri M18"}"#);
    // A lamp's own words are a note under its symbol's name (2026-10-04), a
    // second line in grey (Back to Paper), as typed (2026-10-17: capitals
    // only with All Caps).
    assert!(svg.contains(r#"style="fill:var(--d-ink2)">Key</tspan>"#), "renamed, a grey second line as typed");
    assert!(!svg.contains(&tie), "under its piece: no line back");
    let svg = set(&mut s, r#"{"label_dx":1.5,"label_dy":1}"#);
    assert!(svg.contains(&tie), "moved away: tied back");
    let svg = set(&mut s, r#"{"label_dx":0,"label_dy":0}"#);
    assert!(!svg.contains(&tie), "put back");
    let svg = set(&mut s, r#"{"label_hidden":true}"#);
    assert!(!svg.contains(">Key<"), "hidden");
}

#[test]
fn a_note_points_at_three_pieces_and_its_arrows_follow_them() {
    let (_x, mut s) = drawn("diagram-arrows");
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", r#"{"op":"add","els":[{"kind":"note","x":0,"y":4,"text":"Hide the tubes"}]}"#)]);
    let (note, person, lamp, camera) = (first(&mut s, "note"), first(&mut s, "cast"), first(&mut s, "light"), first(&mut s, "camera"));
    let said = ok(&mut s, "point_arrows", &[("scene", "1"), ("from", &note), ("to", &format!("{person}, {lamp},{camera}")), ("dashed", "true")]);
    assert!(said.starts_with("Made "), "{said}");
    let arrows = |s: &mut Open| -> Vec<Json> {
        let plan = json::parse(&ok(s, "diagram", &[("scene", "1")])).unwrap();
        plan.get("els").and_then(|e| e.as_array()).unwrap().iter().filter(|e| e.str_field("kind") == "arrow").cloned().collect()
    };
    let three = arrows(&mut s);
    assert_eq!(three.len(), 3);
    assert!(three.iter().all(|a| a.str_field("start_on") == note && a.str_field("dash") == "dashed"), "{three:?} note {note}");
    let to_person = three.iter().find(|a| a.str_field("end_on") == person).unwrap();
    let y2 = to_person.get("y2").and_then(|v| v.as_f64()).unwrap();
    // The person is moved; the arrow's head goes with them.
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", &format!(r#"{{"op":"move","ids":["{person}"],"dx":0,"dy":-1}}"#))]);
    let moved = arrows(&mut s).into_iter().find(|a| a.str_field("end_on") == person).unwrap();
    assert!((moved.get("y2").and_then(|v| v.as_f64()).unwrap() - y2).abs() > 0.5, "the head followed: {moved:?}");
    assert!(no(&mut s, "point_arrows", &[("scene", "1"), ("from", &note), ("to", "nothing")]).contains("Nothing called"));
}

#[test]
fn a_camera_reads_its_shots_camera_lens_and_zoom() {
    // His design, 2026-10-01: the film's camera carries his sensor; a camera
    // on the plan is its shot and reads camera, lens and zoom off it.
    let (_x, mut s) = drawn("diagram-optics");
    ok(&mut s, "add_camera", &[("name", "A-Cam"), ("sensor_name", "Alexa Mini LF Open Gate"), ("sensor_w", "36.70"), ("sensor_h", "25.54")]);
    assert!(ok(&mut s, "cameras", &[]).contains("Alexa Mini LF Open Gate"));
    ok(&mut s, "update_shot", &[("shot", "1A"), ("camera", "A-Cam"), ("lens", "24-70mm"), ("focal", "35")]);
    let plan = ok(&mut s, "diagram", &[("scene", "1")]);
    assert!(plan.contains(r#""camera":"A-Cam""#), "{plan}");
    assert!(plan.contains(r#""zoom_mm":[24,70]"#), "{plan}");
    assert!(plan.contains(r#""focal":35"#), "{plan}");
    assert!(plan.contains(r#""sensor_name":"Alexa Mini LF Open Gate""#), "{plan}");
    assert!(plan.contains(r#""view_degrees":55.3"#), "{plan}");
    assert!(no(&mut s, "update_shot", &[("shot", "1A"), ("focal", "wide")]).contains("focal"));
}

#[test]
fn a_lamp_has_a_name_and_a_note_and_the_sheet_prints_them() {
    // Back to Paper, Batch 2: a lamp's Name is its symbol's (name_lamp), its
    // Note its own; the read says both lines; paper is the whole sheet.
    let (_x, mut s) = drawn("diagram-sheet");
    let guide = ok(&mut s, "diagram_guide", &[]);
    for words in ["name_lamp {id, name}", "NAME AND NOTE", "sheet_notes", "THE SHEET", "ONE JOIN RULE"] {
        assert!(guide.contains(words), "the guide misses {words}");
    }
    let lamp = first(&mut s, "light");
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", &format!(r#"{{"op":"name_lamp","id":"{lamp}","name":"2K Blonde"}}"#))]);
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", &format!(r#"{{"op":"update","id":"{lamp}","set":{{"label":"Uplight on BG"}}}}"#))]);
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", r#"{"op":"settings","set":{"sheet_notes":"All lamps to dimmers"}}"#)]);
    let plan = json::parse(&ok(&mut s, "diagram", &[("scene", "1")])).unwrap();
    let els = plan.get("els").and_then(|e| e.as_array()).unwrap();
    let it = els.iter().find(|e| e.str_field("id") == lamp).unwrap();
    assert_eq!(it.str_field("lamp_name"), "2K Blonde", "{it:?}");
    let lines: Vec<String> = it.get("label_lines").and_then(|l| l.as_array()).unwrap().iter().map(|l| l.as_str().unwrap().to_string()).collect();
    assert_eq!(lines, vec!["2K Blonde".to_string(), "Uplight on BG".to_string()]);
    let key = it.str_field("legend_key");
    let legend = plan.get("legend").and_then(|l| l.as_array()).unwrap();
    let line = legend.iter().find(|x| x.str_field("key") == key).unwrap();
    assert_eq!(line.str_field("name"), "2K Blonde");
    assert!(line.get("ids").and_then(|i| i.as_array()).unwrap().iter().any(|i| i.as_str() == Some(lamp.as_str())), "{line:?}");
    let sheet = plan.get("sheet").unwrap();
    assert_eq!(sheet.str_field("paper"), "letter");
    assert_eq!(sheet.str_field("sheet_notes"), "All lamps to dimmers");
    assert_eq!(sheet.get("scale_bar").and_then(|b| b.as_bool()), Some(false), "no scale bar unless asked (his call G)");
    let gear = plan.get("gear").and_then(|g| g.as_array()).unwrap();
    assert!(gear.iter().any(|g| g.str_field("name") == "2K Blonde" && g.str_field("group") == "Lights"), "{gear:?}");

    // Paper is the sheet, as it prints: title, legend and his notes.
    let paper = ok(&mut s, "diagram_picture", &[("scene", "1"), ("width", "1000"), ("paper", "true")]);
    assert!(paper.contains(r#"class="dia sheet""#), "{}", &paper[..200.min(paper.len())]);
    for words in ["Legend", "2K Blonde", "Notes", "All lamps to dimmers"] {
        assert!(paper.contains(words), "the sheet misses {words}");
    }
    assert!(paper.contains("--d-wall:#"), "it carries its colours");
    // Through the protocol: a picture of the sheet, whole.
    let reply = s
        .handle(r#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"diagram_picture","arguments":{"scene":"1","paper":true,"width":1000}}}"#)
        .unwrap();
    let reply = json::parse(&reply).unwrap();
    let content = &reply.get("result").unwrap().get("content").unwrap().as_array().unwrap()[0];
    assert_eq!(content.str_field("type"), "image", "{}", reply.encode().chars().take(300).collect::<String>());
    let png = base64_decode(&content.str_field("data"));
    assert!(png.starts_with(&[0x89, b'P', b'N', b'G']));
    if let Ok(path) = std::env::var("SHOTLISTER_KEEP_SHEET") {
        std::fs::write(path, &png).unwrap();
    }

    // Name This One: a second lamp of the same symbol named alone moves to a symbol of its own.
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", &format!(r#"{{"op":"duplicate","ids":["{lamp}"],"dx":1,"dy":0}}"#))]);
    let plan = json::parse(&ok(&mut s, "diagram", &[("scene", "1")])).unwrap();
    let twin = plan.get("els").and_then(|e| e.as_array()).unwrap().iter().filter(|e| e.str_field("kind") == "light").map(|e| e.str_field("id")).find(|id| *id != lamp).unwrap();
    ok(&mut s, "edit_diagram", &[("scene", "1"), ("op", &format!(r#"{{"op":"name_lamp","id":"{twin}","name":"Joker 800","only":true}}"#))]);
    let plan = json::parse(&ok(&mut s, "diagram", &[("scene", "1")])).unwrap();
    let els = plan.get("els").and_then(|e| e.as_array()).unwrap();
    let (a, b) = (els.iter().find(|e| e.str_field("id") == lamp).unwrap(), els.iter().find(|e| e.str_field("id") == twin).unwrap());
    assert_eq!(a.str_field("lamp_name"), "2K Blonde");
    assert_eq!(b.str_field("lamp_name"), "Joker 800");
    assert_ne!(a.str_field("legend_key"), b.str_field("legend_key"));
}
