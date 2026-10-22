//! The film's own details, and scenes and sections told apart.

mod common;
use common::*;

#[test]
fn the_films_details_as_settings_has_them() {
    let (_x, mut s) = opened("film");
    let said = ok(&mut s, "update_project", &[("director", "Jo Park"), ("producer", "Sam Lee"), ("aspect_ratio", "1.85 : 1")]);
    assert_eq!(said, "Title: Daybreak. Director: Jo Park. Producer: Sam Lee. Frame: 1.85 : 1.");
    let summary = ok(&mut s, "summary", &[]);
    assert!(summary.contains(r#""director":"Jo Park""#) && summary.contains(r#""ratio":1.85"#), "{summary}");
    assert!(no(&mut s, "update_project", &[("aspect_ratio", "wide")]).contains("2.39"));
    ok(&mut s, "update_project", &[("aspect_ratio", "9:16")]);
    assert!(ok(&mut s, "summary", &[]).contains(r#""ratio":0.5625"#), "a vertical frame is width over height");
    assert!(no(&mut s, "update_project", &[("title", "")]).contains("needs a title"));
    ok(&mut s, "update_project", &[("director", "")]);
    assert!(ok(&mut s, "summary", &[]).contains(r#""director":"""#));
}

#[test]
fn a_scene_moved_somewhere_else_reads_it_in_its_heading() {
    let (_x, mut s) = opened("heading");
    let draft = "INT. KITCHEN - DAY\n\nAnna makes tea.\n\nEXT. GARDEN - NIGHT\n\nRain.\n";
    ok(&mut s, "apply_draft", &[("text", draft)]);
    let scenes = ok(&mut s, "scenes", &[]);
    let first = json::parse(&scenes).unwrap().as_array().unwrap()[0].get("number").unwrap().as_str().unwrap().to_string();
    let said = ok(&mut s, "update_scene", &[("scene", &first), ("location", "GARAGE")]);
    assert!(said.contains("INT. GARAGE - DAY"), "the heading follows: {said}");
}

#[test]
fn scene_numbers_priority_and_pov_and_a_sections_colour() {
    let (_x, mut s) = opened("scenes-more");
    ok(&mut s, "add_scene", &[("number", "12")]);
    ok(&mut s, "add_scene", &[("number", "13")]);
    assert!(no(&mut s, "update_scene", &[("scene", "12"), ("number", "13")]).contains("already a scene 13"));
    let said = ok(&mut s, "update_scene", &[("scene", "12"), ("number", "12A"), ("priority", "Must Have"), ("pov", "Anna, Ben")]);
    assert!(said.starts_with("Scene 12A is now"), "{said}");
    let lists = ok(&mut s, "lists", &[("list", "pov")]);
    assert!(lists.contains(r#""term":"Ben""#), "{lists}");

    ok(&mut s, "add_section", &[("title", "Act One")]);
    assert_eq!(ok(&mut s, "rename_section", &[("section", "Act One"), ("colour", "3")]), "Its colour is 4C51BF.");
    assert_eq!(ok(&mut s, "rename_section", &[("section", "act one"), ("title", "Act 1")]), "act one is Act 1 now.");
    assert!(no(&mut s, "rename_section", &[("section", "Act 1"), ("colour", "teal")]).contains("six hex digits"));
}

/// **A film that takes its facts from the project record** (one-record plan,
/// 2026-10-05): the app shows them and will not let them be typed over, so
/// the connector will not either. The frame and the film's own title stay
/// the film's.
#[test]
fn the_records_facts_are_not_the_connectors_to_change() {
    let scratch = Scratch::new("film-record");
    let path = {
        let mut project = shotlister_storage::create(&scratch.0, "Lets Bake", shotlister_engine::DeviceId(1)).expect("creates");
        let given: Vec<(String, String)> = [("title", "Let's Bake"), ("director", "Ollie Hart Brennan"), ("producer", "Marta Delgado")]
            .iter()
            .map(|(a, b)| (a.to_string(), b.to_string()))
            .collect();
        project.doc_mut().take_record_facts(&given).expect("takes them");
        project.save().expect("saves");
        project.path().to_path_buf()
    };
    let mut s: Open = shotlister_mcp::Server::new(shotlister_engine::DeviceId(2));
    s.call("open_project", &args(&[("path", path.to_str().unwrap())])).expect("opens");

    let summary = ok(&mut s, "summary", &[]);
    assert!(summary.contains(r#""facts":"record""#), "{summary}");
    assert!(summary.contains(r#""shown_title":"Let's Bake""#), "{summary}");
    assert!(summary.contains(r#""producer":"Marta Delgado""#), "{summary}");

    let said = no(&mut s, "update_project", &[("producer", "Owen Fairweather")]);
    assert!(said.contains("Projects Console"), "{said}");
    assert!(ok(&mut s, "summary", &[]).contains(r#""producer":"Marta Delgado""#), "nothing was written");
    ok(&mut s, "update_project", &[("aspect_ratio", "16:9")]);
}

/// **The project's frames, off its spec sheet** (stage 5 step 4, piece E):
/// `frame` picks the one Studio draws at, `aspect_ratio` picks the frame at
/// that ratio, `frame_guides` shows the others; and a camera's sensor that
/// the sheet names is the sheet's, never typed over.
#[test]
fn the_frame_is_one_of_the_sheets_and_the_sensor_is_the_sheets() {
    use shotlister_mcp::Films;
    let (_x, mut s) = opened("frames");
    ok(&mut s, "add_camera", &[("name", "A Cam")]);
    assert!(no(&mut s, "update_project", &[("frame", "Social")]).contains("no aspect ratios"));
    {
        let doc = s.films_mut().doc_mut().unwrap();
        let card = r#"{"facts":{},"sheet":{"frames":[{"name":"Delivery","ratio":"2.39:1","main":true},{"name":"Social","ratio":"9:16"}],"sensors":[{"label":"A-Cam","name":"Open Gate","width":36.7,"height":25.54}]}}"#;
        doc.set_card(shotlister_engine::card::Card::read(card));
    }
    let said = ok(&mut s, "update_project", &[("frame", "social")]);
    assert!(said.contains("Frame: Social 9:16"), "{said}");
    let said = ok(&mut s, "update_project", &[("aspect_ratio", "2.39"), ("frame_guides", "true")]);
    assert!(said.contains("Frame: Delivery 2.39:1, others as guides"), "{said}");
    let refused = no(&mut s, "update_project", &[("aspect_ratio", "1.85")]);
    assert!(refused.contains("Delivery 2.39:1, Social 9:16"), "{refused}");
    let refused = no(&mut s, "update_camera", &[("camera", "A Cam"), ("sensor_w", "24.89"), ("sensor_h", "18.66")]);
    assert!(refused.contains("spec sheet"), "{refused}");
    assert!(ok(&mut s, "cameras", &[]).contains("\"sensor_from_sheet\":true"));
}
