//! Locations — the record a scene is shot at.
//!
//! Ref 57, and the thing the phone thread has been blocked on. The field names
//! are the phone's JSON field names on purpose (`handoff/from-phone.md`), so
//! reading `locations/<id>/location.json` in is a copy rather than a
//! translation.

use shotlister_engine::doc::f;
use shotlister_engine::{DeviceId, Doc};

fn doc() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

#[test]
fn a_location_holds_what_the_phone_captures() {
    let mut d = doc();
    let location = d.create_location("County Jail");

    d.set(location, f::ADDRESS, "1 Jail Rd, Barstow CA");
    d.set(location, f::LATITUDE, "34.0500");
    d.set(location, f::LONGITUDE, "-118.2500");
    d.set(location, f::NOTES, "Ask about the gate code");
    d.set(location, f::CAPTURED_BY, "iPhone");

    let record = d.get(location).unwrap();
    assert_eq!(record.text(f::LABEL), Some("County Jail"));
    assert_eq!(record.text(f::ADDRESS), Some("1 Jail Rd, Barstow CA"));
    assert_eq!(record.text(f::LATITUDE), Some("34.0500"));
    assert_eq!(record.text(f::CAPTURED_BY), Some("iPhone"));
}

#[test]
fn a_scene_points_at_a_location_without_losing_the_scripts_word() {
    let mut d = doc();
    let scene = d.create_scene("34");
    // The slugline's own word. Never ours to change.
    d.set(scene, f::LOCATION, "CAR");
    let location = d.create_location("Barstow — Route 66 pull-off");

    d.set_scene_location(scene, Some(location));

    assert_eq!(d.location_of_scene(scene), Some(location));
    assert_eq!(
        d.get(scene).unwrap().text(f::LOCATION),
        Some("CAR"),
        "the script's location is a different fact and stays put"
    );
}

#[test]
fn a_location_knows_which_scenes_hang_on_it() {
    let mut d = doc();
    let location = d.create_location("County Jail");
    let a = d.create_scene("33");
    let b = d.create_scene("34");
    let c = d.create_scene("35");
    d.set_scene_location(a, Some(location));
    d.set_scene_location(c, Some(location));

    assert_eq!(d.scenes_at_location(location), vec![a, c]);
    assert_eq!(d.location_of_scene(b), None);
}

#[test]
fn deleting_a_location_takes_nothing_of_the_scenes_with_it() {
    let mut d = doc();
    let scene = d.create_scene("34");
    d.set(scene, f::LOCATION, "CAR");
    d.set(scene, f::DESCRIPTION, "They drive.");
    let location = d.create_location("Barstow");
    d.set_scene_location(scene, Some(location));

    d.delete_location(location);

    assert!(d.get(location).is_none());
    assert_eq!(d.location_of_scene(scene), None, "the pointer goes");
    let record = d.get(scene).unwrap();
    assert_eq!(record.text(f::LOCATION), Some("CAR"), "the scene does not");
    assert_eq!(record.text(f::DESCRIPTION), Some("They drive."));
}

#[test]
fn locations_keep_the_order_they_were_added_in() {
    let mut d = doc();
    let first = d.create_location("County Jail");
    let second = d.create_location("Pharmacy");
    let third = d.create_location("The Fight Venue");

    assert_eq!(d.locations_in_order(), vec![first, second, third]);
    assert_eq!(d.location_named("pharmacy"), Some(second));
    assert_eq!(d.location_named("nowhere"), None);
}

#[test]
fn a_location_carries_photographs_the_same_way_a_shot_does() {
    let mut d = doc();
    let location = d.create_location("County Jail");
    // Media is addressed by its contents and shared by everything that uses it;
    // a location that invented its own way to hold a picture would be a second
    // answer to a question already answered.
    let photo = d.add_media(
        shotlister_engine::sha256(b"the gate"),
        shotlister_engine::MediaKind::Image,
        1280,
        720,
        24,
        "gate.jpg",
    );
    d.attach_media(location, photo, "The gate");

    let refs = d.media_refs(location);
    assert_eq!(refs.len(), 1);
    assert_eq!(
        d.get(refs[0]).unwrap().text(f::CAPTION),
        Some("The gate")
    );
}

// ---------------------------------------------------------------------------
// Rooms inside a location — Ref 269.
//
// *Call Her Back* is one house with one address, and inside it a kitchen, a
// master bedroom and a garage, each scanned separately and each with its own
// photographs. The tests below are the four things that ask has to mean.

#[test]
fn a_room_borrows_the_house_it_is_in() {
    let mut d = doc();
    let house = d.create_location("Hillcrest House");
    d.set(house, f::ADDRESS, "2140 Hillcrest Rd");
    d.set(house, f::LATITUDE, "51.5072");
    d.set(house, f::LONGITUDE, "-0.1276");
    d.set(house, f::NOTES, "Park on the street. Key is with the neighbour.");

    let kitchen = d.create_location_in(house, "Kitchen");

    // The whole point of the ask: the address and the how-to-get-in are typed
    // once, for the house, and every room in it reads them.
    assert_eq!(d.location_address(kitchen), "2140 Hillcrest Rd");
    assert_eq!(
        d.location_notes(kitchen),
        "Park on the street. Key is with the neighbour."
    );
    assert_eq!(
        d.location_pin(kitchen),
        Some(("51.5072".into(), "-0.1276".into()))
    );

    // And a room that genuinely is somewhere else says so, without the house
    // overruling it.
    let shed = d.create_location_in(house, "Shed");
    d.set(shed, f::ADDRESS, "2144 Hillcrest Rd");
    assert_eq!(d.location_address(shed), "2144 Hillcrest Rd");
    // It still borrows the notes it did not override.
    assert!(d.location_notes(shed).starts_with("Park on the street"));

    // Named away from its own screen, a room carries the house with it.
    assert_eq!(d.location_full_name(kitchen), "Hillcrest House — Kitchen");
    assert_eq!(d.location_full_name(house), "Hillcrest House");
}

#[test]
fn nesting_stops_at_one_level() {
    let mut d = doc();
    let house = d.create_location("Hillcrest House");
    let kitchen = d.create_location_in(house, "Kitchen");

    // A room cannot be put inside a room.
    let pantry = d.create_location("Pantry");
    assert!(!d.set_location_parent(pantry, Some(kitchen)));
    assert_eq!(d.parent_of_location(pantry), None);

    // Nor can a house that already has rooms be filed inside another house.
    let other = d.create_location("Neighbour's House");
    assert!(!d.set_location_parent(house, Some(other)));
    assert_eq!(d.parent_of_location(house), None);

    // Nor inside itself.
    assert!(!d.set_location_parent(house, Some(house)));

    // Asking for a room *of a room* lands it beside that room instead of under
    // it, so a mis-click makes a sibling rather than a grandchild nobody can
    // find.
    let sink = d.create_location_in(kitchen, "Sink corner");
    assert_eq!(d.parent_of_location(sink), Some(house));

    // And a room can always be let out to stand on its own.
    assert!(d.set_location_parent(kitchen, None));
    assert_eq!(d.parent_of_location(kitchen), None);
}

#[test]
fn the_house_counts_every_scene_inside_it_but_a_room_counts_only_its_own() {
    let mut d = doc();
    let house = d.create_location("Hillcrest House");
    let kitchen = d.create_location_in(house, "Kitchen");
    let bedroom = d.create_location_in(house, "Master Bedroom");

    let one = d.create_scene("1");
    let two = d.create_scene("2");
    let three = d.create_scene("3");
    d.set_scene_location(one, Some(kitchen));
    d.set_scene_location(two, Some(bedroom));
    d.set_scene_location(three, Some(house));

    // A room's own list stays exact — it must not swell with the rest of the
    // house.
    assert_eq!(d.scenes_at_location(kitchen), vec![one]);
    assert_eq!(d.scenes_at_location(house), vec![three]);

    // The house, asked how much of the film hangs on it, counts everything
    // under its roof.
    assert_eq!(
        d.scenes_at_location_or_inside(house),
        vec![one, two, three]
    );

    assert_eq!(d.top_locations(), vec![house]);
    assert_eq!(d.areas_of(house), vec![kitchen, bedroom]);
}

#[test]
fn deleting_a_house_lets_its_rooms_out_rather_than_taking_them_with_it() {
    let mut d = doc();
    let house = d.create_location("Hillcrest House");
    d.set(house, f::ADDRESS, "2140 Hillcrest Rd");
    let kitchen = d.create_location_in(house, "Kitchen");

    let scene = d.create_scene("1");
    d.set_scene_location(scene, Some(kitchen));

    d.delete_location(house);

    // Report, never destroy: the kitchen is still here, still holds its scene,
    // and has simply come up a level.
    assert!(d.get(kitchen).is_some());
    assert_eq!(d.parent_of_location(kitchen), None);
    assert_eq!(d.scenes_at_location(kitchen), vec![scene]);
    assert_eq!(d.top_locations(), vec![kitchen]);

    // What it does lose is the address it was borrowing — which is the thing
    // the Mac warns about before it deletes a house.
    assert_eq!(d.location_address(kitchen), "");
    assert_eq!(d.location_full_name(kitchen), "Kitchen");
}
