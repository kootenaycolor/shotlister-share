//! Locations, from a chat.

mod common;
use common::*;

#[test]
fn a_house_with_rooms_and_the_scenes_shot_there() {
    let (_x, mut s) = opened("places");
    ok(&mut s, "add_scene", &[("number", "12")]);
    ok(&mut s, "add_scene", &[("number", "14")]);
    let said = ok(&mut s, "add_location", &[("name", "Hillcrest House"), ("address", "12 Hillcrest Rd"), ("latitude", "51.51"), ("longitude", "-0.13")]);
    assert_eq!(said, "Added Hillcrest House.");
    assert_eq!(ok(&mut s, "add_location", &[("name", "Kitchen"), ("inside", "hillcrest house")]), "Added Hillcrest House — Kitchen.");
    // A room of a room lands beside it.
    assert_eq!(ok(&mut s, "add_location", &[("name", "Pantry"), ("inside", "Kitchen")]), "Added Hillcrest House — Pantry.");

    let said = ok(&mut s, "set_scene_locations", &[("scene", "12"), ("locations", "Hillcrest House - Kitchen, Pantry")]);
    assert_eq!(said, "Scene 12 is shot at Hillcrest House — Kitchen; Hillcrest House — Pantry.");
    assert!(ok(&mut s, "scenes", &[]).contains(r#""locations":["Hillcrest House — Kitchen","Hillcrest House — Pantry"]"#));

    let all = ok(&mut s, "locations", &[]);
    assert!(all.contains(r#""rooms":[{"name":"Kitchen","address":"12 Hillcrest Rd""#), "a room reads the house's address: {all}");
    assert!(all.contains(r#""scenes":["12"]"#), "{all}");

    ok(&mut s, "set_scene_locations", &[("scene", "12"), ("remove", "Pantry")]);
    ok(&mut s, "set_scene_locations", &[("scene", "14"), ("add", "Hillcrest House")]);
    ok(&mut s, "update_location", &[("location", "Kitchen"), ("notes", "Park on the street"), ("name", "Big Kitchen")]);
    assert!(ok(&mut s, "locations", &[]).contains(r#""name":"Big Kitchen","address":"12 Hillcrest Rd","notes":"Park on the street""#));

    let refused = no(&mut s, "update_location", &[("location", "Hillcrest House"), ("inside", "Big Kitchen")]);
    assert!(refused.contains("one level only"), "{refused}");
    ok(&mut s, "update_location", &[("location", "Pantry"), ("inside", "")]);
}

#[test]
fn a_location_with_work_on_it_is_not_removed_without_asking() {
    let (_x, mut s) = opened("places-delete");
    ok(&mut s, "add_scene", &[("number", "3")]);
    ok(&mut s, "add_location", &[("name", "Barn")]);
    ok(&mut s, "add_location", &[("name", "Loft"), ("inside", "Barn")]);
    ok(&mut s, "set_scene_locations", &[("scene", "3"), ("locations", "Barn")]);
    let refused = no(&mut s, "delete_location", &[("location", "Barn")]);
    assert!(refused.contains("scene 3, 1 room"), "{refused}");
    assert_eq!(ok(&mut s, "delete_location", &[("location", "Barn"), ("even_if_used", "true")]), "Removed Barn.");
    let all = ok(&mut s, "locations", &[]);
    assert!(all.contains(r#""name":"Loft""#) && !all.contains("Barn"), "the room stands on its own: {all}");
    assert!(!ok(&mut s, "scenes", &[]).contains("locations"));
    assert!(no(&mut s, "update_location", &[("location", "Barn"), ("notes", "x")]).contains("The locations are Loft"));
}
