//! Floor plans — the arithmetic that turns a scan into a drawing.
//!
//! This moved into the engine on his instruction of 2026-08-21: *"iOS has been
//! handling the floor plan creation. I just need you to display it, or you guys
//! should just share the same engine."* The phone had it in Swift and the Mac
//! was about to have a second copy; both apps build this crate, so one copy is
//! possible and two is a choice nobody should make.
//!
//! The room every test uses is the one the phone hand-built to check its own
//! drawing: an L-shape, scanned crooked at 23°, with a door, a window and four
//! kinds of furniture. Its awkwardness is the point — a rectangle scanned square
//! passes everything.

use shotlister_engine::room::{self, Furnishing, Part};

/// Feet, to a tenth, for asserting on a length a person would say out loud.
fn feet(metres: f32) -> f32 {
    (metres * 3.28084 * 10.0).round() / 10.0
}

#[test]
fn a_room_scanned_crooked_is_drawn_straight() {
    let plan = room::sample().expect("the sample room builds");

    // Turned back by 23°, whichever way round the longest wall happened to lie.
    let straightened = plan.straightened_by.to_degrees();
    assert!(
        (straightened.abs() - 23.0).abs() < 0.01,
        "turned by {straightened}°, wanted 23"
    );

    // Every wall now lies along an axis. That is the whole claim: a plan drawn
    // crooked makes every dimension on it look approximate even when it is
    // exact.
    for wall in plan.walls() {
        let quarter = wall.angle.to_degrees().rem_euclid(90.0);
        let off = quarter.min(90.0 - quarter);
        assert!(off < 0.01, "a wall sits {off}° off square");
    }
}

#[test]
fn the_room_measures_what_it_was_built_as() {
    let plan = room::sample().unwrap();
    let (across, down) = plan.extent();
    // 4.0 × 3.2 metres — 13 ft 1 in by 10 ft 6 in.
    assert!((feet(across) - 13.1).abs() < 0.15, "{} ft across", feet(across));
    assert!((feet(down) - 10.5).abs() < 0.15, "{} ft down", feet(down));
}

#[test]
fn every_wall_keeps_its_own_length() {
    let plan = room::sample().unwrap();
    let mut lengths: Vec<f32> = plan.walls().map(|w| (w.size.0 * 100.0).round() / 100.0).collect();
    lengths.sort_by(|a, b| a.partial_cmp(b).unwrap());
    // The L's six walls: 1.2, 1.4, 2.0, 2.6, 3.2, 4.0.
    assert_eq!(lengths, vec![1.2, 1.4, 2.0, 2.6, 3.2, 4.0]);
}

/// **The outer extent describes a room that does not exist.** An L-shaped room
/// has six walls, and its bounding box is a four-walled rectangle enclosing
/// floor the room does not have. Quoting "13 ft 1 in × 10 ft 6 in" and stopping
/// there is how somebody turns up with a dolly track that does not fit — which
/// is why every wall carries its own number on the drawing.
#[test]
fn the_outer_extent_is_not_the_room() {
    let plan = room::sample().unwrap();
    assert_eq!(plan.walls().count(), 6, "an L, not a box");

    let (across, down) = plan.extent();
    let box_area = across * down;

    // The two walls the bounding box cannot account for: the return into the
    // notch and the wall behind it, both far shorter than either side of it.
    let shortest = plan.walls().map(|w| w.size.0).fold(f32::MAX, f32::min);
    assert!(
        shortest < across.min(down) / 2.0,
        "the shortest wall is {shortest}, and neither side of the box is near it"
    );

    // And the floor is smaller than the box by the notch that was cut out.
    let notch = 1.4 * 1.2;
    assert!(
        (box_area - notch - 11.12).abs() < 0.05,
        "the room's floor is {} m², the box claims {box_area}",
        box_area - notch
    );
}

/// **Furniture must not widen the room.** A chair against a wall and a table
/// half under a counter both sit outside nothing; if the bounds were fitted to
/// everything, a scan would grow every time somebody moved a stool.
#[test]
fn furniture_does_not_move_the_walls() {
    let plan = room::sample().unwrap();
    let (across, down) = plan.extent();

    let mut fatter = plan.items.clone();
    fatter.push(shotlister_engine::room::Item::plain(Part::Object, (99.0, 99.0), (2.0, 2.0), 1.0, 0.0, Furnishing::Sofa));
    let grown = room::Plan::from_items(fatter).unwrap();
    let (a2, d2) = grown.extent();
    assert!((a2 - across).abs() < 0.01 && (d2 - down).abs() < 0.01,
            "a sofa a hundred metres away changed the room to {a2} × {d2}");
}

/// The one measurement a plan cannot show by drawing.
#[test]
fn the_ceiling_is_reported_and_a_stepped_one_is_said_out_loud() {
    let plan = room::sample().unwrap();
    assert!((feet(plan.ceiling()) - 8.1).abs() < 0.15, "{} ft", feet(plan.ceiling()));
    assert!(!plan.ceiling_varies(), "every wall in the sample is 2.48");

    let mut stepped = plan.items.clone();
    if let Some(wall) = stepped.iter_mut().find(|i| i.part == Part::Wall) {
        wall.height = 3.1;
    }
    let plan = room::Plan::from_items(stepped).unwrap();
    assert!(plan.ceiling_varies(), "a stepped ceiling is a real fact about a location");
    let (low, high) = plan.ceiling_range();
    assert!((low - 2.48).abs() < 0.01 && (high - 3.1).abs() < 0.01);
}

// --------------------------------------------------- reading RoomPlan's file

/// One surface in RoomPlan's own encoding. The shape is measured rather than
/// guessed — see the note on `room::read`.
fn surface(category: &str, x: f32, z: f32, length: f32, height: f32, angle: f32,
           depth: f32) -> String {
    surface_at(category, x, z, length, height, angle, depth, 0.0)
}

/// The same, with its bottom edge `bottom` metres up in RoomPlan's world.
#[allow(clippy::too_many_arguments)]
fn surface_at(category: &str, x: f32, z: f32, length: f32, height: f32, angle: f32,
           depth: f32, bottom: f32) -> String {
    let (c, s) = (angle.cos(), angle.sin());
    let y = bottom + height / 2.0;
    format!(
        r#"{{"category":{{"{category}":{{}}}},"confidence":{{"high":{{}}}},
            "dimensions":[{length},{height},{depth}],
            "transform":[{c},0,{s},0, 0,1,0,0, {ns},0,{c},0, {x},{y},{z},1],
            "identifier":"11111111-2222-3333-4444-555555555555",
            "parentIdentifier":null,"story":0,"attributes":{{}},
            "completedEdges":[],"curve":null,"polygonCorners":[]}}"#,
        ns = -s
    )
}

fn a_real_shaped_file() -> String {
    let quarter = std::f32::consts::FRAC_PI_2;
    let walls = [
        surface("wall", 2.0, 0.0, 4.0, 2.48, 0.0, 0.0),
        surface("wall", 4.0, 1.6, 3.2, 2.48, quarter, 0.0),
        surface("wall", 2.0, 3.2, 4.0, 2.48, 0.0, 0.0),
        surface("wall", 0.0, 1.6, 3.2, 2.48, quarter, 0.0),
    ]
    .join(",");
    let door = surface("door", 3.2, 0.0, 0.9, 2.05, 0.0, 0.0);
    let window = surface_at("window", 0.0, 2.2, 1.2, 1.24, quarter, 0.0, 0.9);
    let bed = surface("bed", 1.15, 1.05, 1.4, 0.62, quarter, 2.0);
    let telly = surface("television", 3.9, 1.4, 1.0, 0.59, quarter, 0.09);
    format!(
        r#"{{"version":1,"identifier":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","story":0,
            "referenceOriginTransform":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
            "walls":[{walls}],"doors":[{door}],"windows":[{window}],
            "openings":[],"floors":[],"sections":[],"objects":[{bed},{telly}]}}"#
    )
}

#[test]
fn a_roomplan_file_reads_into_a_plan() {
    let plan = room::read(&a_real_shaped_file()).expect("it reads");
    assert_eq!(plan.walls().count(), 4);
    assert_eq!(plan.items.len(), 8);

    let (across, down) = plan.extent();
    assert!((feet(across) - 13.1).abs() < 0.15, "{} ft across", feet(across));
    assert!((feet(down) - 10.5).abs() < 0.15, "{} ft down", feet(down));
    assert!((feet(plan.ceiling()) - 8.1).abs() < 0.15);
}

/// **A category is an object with one key, not a string.** Getting this wrong
/// draws every bed as a plain rectangle and nothing looks broken.
#[test]
fn furniture_keeps_what_roomplan_called_it() {
    let plan = room::read(&a_real_shaped_file()).unwrap();
    let things: Vec<Furnishing> = plan
        .items
        .iter()
        .filter(|i| i.part == Part::Object)
        .map(|i| i.furnishing)
        .collect();
    assert!(things.contains(&Furnishing::Bed));
    assert!(things.contains(&Furnishing::Screen));
}

/// A file from a RoomPlan we cannot read is worth failing on. Drawing half a
/// room is worse than saying there is no plan.
#[test]
fn a_file_that_is_not_a_room_is_refused_rather_than_half_drawn() {
    assert!(room::read("{}").is_none());
    assert!(room::read("not json at all").is_none());
    assert!(
        room::read(r#"{"version":1,"walls":[],"doors":[],"windows":[],"openings":[],"objects":[]}"#)
            .is_none(),
        "a room with nothing in it is not a room"
    );
}

/// What the apps actually receive.
#[test]
fn the_drawing_gets_everything_it_needs_and_no_corners() {
    let plan = room::sample().unwrap();
    let said = room::as_json(&plan).encode();
    for key in [
        "items", "part", "furnishing", "angle", "height", "minX", "maxY",
        "ceiling", "ceilingVaries", "straightenedBy",
    ] {
        assert!(said.contains(key), "the drawing needs {key}");
    }
    // **Corners are not sent.** The thickness a wall is drawn at is a drawing
    // convention; letting it cross this boundary is how an invented 12cm ends
    // up inside somebody's measurement.
    assert!(!said.contains("corners"));
}

/// **A big window is not a door.** RoomPlan calls tall glass a door more often
/// than not, and his scans kept coming back with huge doors where the windows
/// are (his note, 2026-09-27). A door reaches the floor; a "door" standing off
/// it is a window — measured from the scan's floor, wherever the phone put it.
#[test]
fn a_big_window_scanned_as_a_door_comes_in_as_a_window() {
    let quarter = std::f32::consts::FRAC_PI_2;
    // The phone started the scan held at chest height, so the floor is 1.3 m
    // below RoomPlan's zero.
    let floor = -1.3;
    let walls = [
        surface_at("wall", 2.0, 0.0, 4.0, 2.48, 0.0, 0.0, floor),
        surface_at("wall", 4.0, 1.6, 3.2, 2.48, quarter, 0.0, floor),
        surface_at("wall", 2.0, 3.2, 4.0, 2.48, 0.0, 0.0, floor),
        surface_at("wall", 0.0, 1.6, 3.2, 2.48, quarter, 0.0, floor),
    ]
    .join(",");
    let doors = [
        // A real door, to the floor.
        surface_at("door", 3.2, 0.0, 0.9, 2.05, 0.0, 0.0, floor),
        // A patio door over a step's threshold.
        surface_at("door", 2.0, 3.2, 1.8, 2.1, 0.0, 0.0, floor + 0.08),
        // A picture window 2.4 m wide and 1.6 tall, sill at 60 cm — the one
        // RoomPlan keeps calling a door.
        surface_at("door", 0.0, 1.6, 2.4, 1.6, quarter, 0.0, floor + 0.6),
    ]
    .join(",");
    let with_floor = |floors: &str| {
        format!(
            r#"{{"version":1,"walls":[{walls}],"doors":[{doors}],"windows":[],
                "openings":[],"floors":[{floors}],"objects":[]}}"#
        )
    };
    let floor_surface = surface_at("floor", 2.0, 1.6, 4.0, 0.0, 0.0, 3.2, floor);
    for text in [with_floor(""), with_floor(&floor_surface)] {
        let plan = room::read(&text).expect("it reads");
        let count = |part: Part| plan.items.iter().filter(|i| i.part == part).count();
        assert_eq!(count(Part::Door), 2, "the real door and the patio door stay doors");
        assert_eq!(count(Part::Window), 1, "the picture window is a window");
        let window = plan.items.iter().find(|i| i.part == Part::Window).unwrap();
        assert!((window.size.0 - 2.4).abs() < 0.01, "it keeps its width");

        // And on the diagram it is a window, not a door swinging into the room.
        let mut d = shotlister_engine::diagram::Diagram::default();
        shotlister_engine::diagram::import_room(&mut d, &plan, "loc");
        let kinds: Vec<&str> = d.els.iter().map(|e| e.kind.as_str()).collect();
        assert_eq!(kinds.iter().filter(|k| **k == "window").count(), 1, "{kinds:?}");
        assert_eq!(kinds.iter().filter(|k| **k == "door").count(), 2, "{kinds:?}");
    }
}
