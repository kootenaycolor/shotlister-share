//! Room from Scan built from the plan's own pieces, and a door's kind in one
//! click (his asks, 2026-10-17).
use super::*;
use crate::json::{self, Json};
use crate::room::{Furnishing, Item, Part};

fn op(text: &str) -> Json {
    json::parse(text).expect("an op")
}

fn door(w: f32, height: f32, glass: bool) -> Item {
    let mut i = Item::plain(Part::Door, (0.0, 0.0), (w, 0.0), height, 0.0, Furnishing::Other);
    i.glass_wall = glass;
    i
}

fn object(category: &str, detail: &str, size: (f32, f32)) -> Item {
    let mut i = Item::plain(Part::Object, (0.0, 0.0), size, 0.8, 0.0, Furnishing::parse(category));
    i.category = category.into();
    i.detail = detail.into();
    i
}

#[test]
fn a_scanned_door_slides_when_it_is_wide_or_in_glass() {
    // An ordinary door swings.
    assert_eq!(scanned_door(&door(0.86, 2.1, false)), "swing");
    // Too wide for one leaf, in a plain wall: a pair.
    assert_eq!(scanned_door(&door(1.3, 2.1, false)), "double");
    // The same width in a wall of glass, or tall: a slider.
    assert_eq!(scanned_door(&door(1.24, 2.1, true)), "sliding");
    assert_eq!(scanned_door(&door(1.24, 3.05, false)), "sliding");
    // Five feet and over always slides.
    assert_eq!(scanned_door(&door(1.72, 2.7, false)), "sliding");
    // Call Her Back's eighteen-foot glass parts from the centre, and is never
    // a hinged swing.
    assert_eq!(scanned_door(&door(5.51, 2.74, false)), "center");
    assert_eq!(scanned_door(&door(3.77, 3.08, false)), "center");
    // A pair is one door of its kind (2026-10-17), drawing both panels.
    let mut el = El::new(Kind::Door, "d");
    el.set_door_style("center");
    assert_eq!(el.door_style(), "center");
}

#[test]
fn every_roomplan_category_becomes_a_library_piece_or_a_labelled_box() {
    let cases: &[(&str, &str, (f32, f32), &str, &str)] = &[
        ("bed", "", (1.5, 2.0), "bed", ""),
        ("bed", "", (0.95, 2.0), "bed-single", ""),
        ("bed", "", (1.95, 2.1), "bed-king", ""),
        ("chair", "dining", (0.5, 0.5), "chair", ""),
        ("chair", "stool", (0.4, 0.4), "stool", ""),
        ("chair", "swivel", (0.6, 0.6), "office-chair", ""),
        ("sofa", "rectangular", (2.2, 0.9), "sofa", ""),
        ("sofa", "rectangular", (1.6, 0.9), "loveseat", ""),
        ("sofa", "singleSeat", (1.0, 0.9), "armchair", ""),
        ("sofa", "lShaped", (2.7, 1.8), "sofa-l", ""),
        ("table", "dining", (1.6, 0.9), "table", ""),
        ("table", "coffee", (1.1, 0.6), "coffee-table", ""),
        ("table", "circularElliptic", (1.1, 1.1), "table-round", ""),
        ("table", "circularElliptic", (1.8, 1.8), "table-round-l", ""),
        ("storage", "cabinet", (1.0, 0.5), "cabinet", ""),
        ("storage", "shelf", (1.0, 0.35), "bookshelf", ""),
        ("refrigerator", "", (0.9, 0.75), "fridge", ""),
        ("stove", "", (0.76, 0.65), "stove", ""),
        ("sink", "", (0.8, 0.55), "sink", ""),
        ("toilet", "", (0.42, 0.7), "toilet", ""),
        ("bathtub", "", (1.7, 0.8), "bathtub", ""),
        ("fireplace", "", (1.5, 0.55), "fireplace", ""),
        ("stairs", "", (1.0, 3.0), "stairs", ""),
        ("television", "", (1.2, 0.1), "tv", ""),
        ("oven", "", (0.6, 0.6), "box", "Oven"),
        ("dishwasher", "", (0.6, 0.6), "box", "Dishwasher"),
        ("washerDryer", "", (0.68, 0.68), "box", "Washer/Dryer"),
        // A category a later iOS adds: a box that says what it is.
        ("pianoBench", "", (1.0, 0.4), "box", "Piano Bench"),
    ];
    for (category, detail, size, sym, label) in cases {
        let (got, words) = scanned_piece(&object(category, detail, *size));
        assert_eq!((got, words.as_str()), (*sym, *label), "{category} {detail}");
        assert!(got == "box" || symbols::find(got).is_some(), "{got} is a library piece");
    }
}

/// A RoomPlan file in miniature: a room with a glass wall holding a window
/// and a 1.3 m door, a plain wall with a 0.9 m door, and a washer.
fn little_scan() -> String {
    let t = |x: f32, z: f32, turn: f32| {
        let (c, s) = (turn.cos(), turn.sin());
        format!("[{c},0,{s},0, 0,1,0,0, {},0,{c},0, {x},1.2,{z},1]", -s)
    };
    let wall = |id: &str, x: f32, z: f32, turn: f32, len: f32| {
        format!(r#"{{"identifier":"{id}","category":{{"wall":{{}}}},"dimensions":[{len},2.4,0],"transform":{}}}"#, t(x, z, turn))
    };
    let q = std::f32::consts::FRAC_PI_2;
    format!(
        r#"{{"walls":[{},{},{},{}],
        "doors":[{{"identifier":"d1","parentIdentifier":"glass","category":{{"door":{{"isOpen":false}}}},"dimensions":[1.3,2.1,0],"transform":{}}},
                 {{"identifier":"d2","parentIdentifier":"plain","category":{{"door":{{"isOpen":true}}}},"dimensions":[0.9,2.1,0],"transform":{}}}],
        "windows":[{{"identifier":"w1","parentIdentifier":"glass","category":{{"window":{{}}}},"dimensions":[1.2,1.2,0],"transform":[1,0,0,0, 0,1,0,0, 0,0,1,0, 3.5,1.6,0,1]}}],
        "openings":[],
        "objects":[{{"category":{{"washerDryer":{{}}}},"dimensions":[0.68,0.9,0.68],"transform":[1,0,0,0, 0,1,0,0, 0,0,1,0, 4,0.45,3,1]}}],
        "sections":[{{"label":"kitchen","center":[2.5,0,2],"story":0}}]}}"#,
        wall("glass", 2.5, 0.0, 0.0, 5.0),
        wall("east", 5.0, 2.0, q, 4.0),
        wall("plain", 2.5, 4.0, 0.0, 5.0),
        wall("west", 0.0, 2.0, q, 4.0),
        t(1.2, 0.0, 0.0).replace(",1.2,", ",1.05,"),
        t(2.5, 4.0, 0.0).replace(",1.2,", ",1.05,"),
    )
}

#[test]
fn a_scan_reads_its_rooms_its_glass_and_its_doors() {
    let plan = crate::room::read(&little_scan()).expect("a room");
    let doors: Vec<&Item> = plan.items.iter().filter(|i| i.part == Part::Door).collect();
    assert_eq!(doors.len(), 2);
    let glass = doors.iter().find(|d| (d.size.0 - 1.3).abs() < 1e-3).unwrap();
    let plain = doors.iter().find(|d| (d.size.0 - 0.9).abs() < 1e-3).unwrap();
    assert!(glass.glass_wall, "the door shares its wall with a window");
    assert!(!plain.glass_wall);
    assert_eq!((glass.open, plain.open), (Some(false), Some(true)));
    let washer = plan.items.iter().find(|i| i.part == Part::Object).unwrap();
    assert_eq!(washer.category, "washerDryer");
    assert_eq!(plan.rooms.len(), 1);
    assert_eq!(plan.rooms[0].0, "kitchen");
}

#[test]
fn a_scanned_room_is_made_of_the_pieces_he_draws() {
    let plan = crate::room::read(&little_scan()).expect("a room");
    let mut d = Diagram::parse(r#"{"settings":{"units":"ft"},"els":[]}"#);
    import_room(&mut d, &plan, "loc");
    // Four scanned walls, one closed room, 6" thick as the Wall tool draws.
    let walls: Vec<&El> = d.els.iter().filter(|e| e.kind == Kind::Wall).collect();
    assert_eq!(walls.len(), 1, "the walls are joined: {walls:?}");
    assert!(walls[0].closed, "and the room closes");
    assert!((walls[0].thick - 0.5 * FOOT).abs() < 1e-9);
    // The glass-wall door slides; the plain one swings.
    let doors: Vec<&El> = d.els.iter().filter(|e| e.kind == Kind::Door).collect();
    assert_eq!(doors.len(), 2);
    assert!(doors.iter().any(|e| e.slide && (e.w - 1.3).abs() < 1e-3 && e.swing == 0.0));
    assert!(doors.iter().any(|e| !e.slide && (e.w - 0.9).abs() < 1e-3));
    // Every door and window is as thick as its wall.
    for e in d.els.iter().filter(|e| matches!(e.kind, Kind::Door | Kind::Window)) {
        assert!((e.h - 0.5 * FOOT).abs() < 1e-9, "{e:?}");
    }
    // The washer is a box that says so, and its label is its own to change.
    let washer = d.els.iter().find(|e| e.kind == Kind::Set).unwrap().clone();
    assert_eq!((washer.sym.as_str(), washer.label.as_str()), ("box", "Washer/Dryer"));
    // Drawn exactly as stored (2026-10-17: capitals only with All Caps).
    let drawn: Vec<String> = super::render::render(&d, &Default::default(), &super::render::Options::default())
        .into_iter()
        .filter(|s| s.el == washer.id)
        .filter_map(|s| match s.geom { super::render::Geom::Text { text, .. } => Some(text), _ => None })
        .collect();
    assert!(drawn.iter().any(|t| t == "Washer/Dryer"), "{drawn:?}");
    apply(&mut d, &op(&format!(r#"{{"op":"update","ids":["{}"],"set":{{"label":"Laundry"}}}}"#, washer.id))).unwrap();
    assert_eq!(d.els.iter().find(|e| e.kind == Kind::Set).unwrap().label, "Laundry");
    // A second import replaces the room and leaves no strays.
    let count = d.els.len();
    import_room(&mut d, &plan, "loc");
    assert_eq!(d.els.len(), count);
}

#[test]
fn a_scan_is_named_for_the_house_and_room_it_was_taken_in() {
    use crate::media::{scan_date_text, scan_name, scan_taken};
    assert_eq!(scan_name("Mansion", "Bathroom", &[], 3), "Mansion · Bathroom · Scan 3");
    assert_eq!(scan_name("Mansion", "Kitchen/Living Room", &[], 1), "Mansion · Kitchen/Living Room · Scan 1");
    // A place on its own: the rooms RoomPlan saw, when it named any.
    assert_eq!(scan_name("Barn", "", &["livingRoom".into(), "unidentified".into()], 1), "Barn · Living Room · Scan 1");
    assert_eq!(scan_name("Barn", "", &["diningRoom".into(), "livingRoom".into()], 2), "Barn · Dining Room & Living Room · Scan 2");
    assert_eq!(scan_name("Barn", "", &["unidentified".into()], 1), "Barn · Scan 1");
    // A room named like its house is said once.
    assert_eq!(scan_name("Studio", "studio", &[], 1), "Studio · Scan 1");
    assert_eq!(scan_taken("RoomScan_2026-08-27T131847"), Some((2026, 8, 27, 13, 18)));
    assert_eq!(scan_date_text("RoomScan_2026-08-27T131847"), "Aug 27, 2026 at 1:18 PM");
    assert_eq!(scan_date_text("RoomScan_2026-09-17T005127"), "Sep 17, 2026 at 12:51 AM");
    assert_eq!(scan_date_text("Kitchen"), "");
}

#[test]
fn renaming_a_scan_keeps_its_two_halves_and_its_files() {
    use crate::doc::Doc;
    use crate::hash::sha256;
    use crate::media::MediaKind;
    let mut doc = Doc::new(crate::DeviceId(7));
    doc.create_project("Test");
    let house = doc.create_location("Mansion");
    let bath = doc.create_location_in(house, "Bathroom");
    let add = |doc: &mut Doc, name: &str, kind: MediaKind| {
        let m = doc.add_media(sha256(name.as_bytes()), kind, 0, 0, 10, name);
        doc.set(m, crate::doc::f::MEDIA_KIND, crate::value::Value::text(kind.as_str()));
        let r = doc.attach_media(bath, m, "");
        doc.set_media_ref_name(r, name);
    };
    for stamp in ["131504", "131406"] {
        add(&mut doc, &format!("RoomScan_2026-08-27T{stamp}.usdz"), MediaKind::Scan);
        add(&mut doc, &format!("RoomScan_2026-08-27T{stamp}.json"), MediaKind::ScanShape);
    }
    let names: Vec<String> = doc.suggested_scan_names(bath, &|_| Vec::new()).into_iter().map(|(_, n)| n).collect();
    assert_eq!(names, ["Mansion · Bathroom · Scan 1", "Mansion · Bathroom · Scan 2"], "numbered oldest first");
    assert!(doc.rename_scan(bath, "RoomScan_2026-08-27T131406", "Mansion · Bathroom · Scan 1"));
    let rooms = doc.scans_of(bath);
    assert_eq!(rooms.len(), 2, "still two rooms, not three halves: {rooms:?}");
    let renamed = rooms.iter().find(|s| s.name == "Mansion · Bathroom · Scan 1").expect("renamed");
    assert!(renamed.shape.is_some() && renamed.plan.is_some());
    assert_eq!(renamed.file, "RoomScan_2026-08-27T131406", "its files keep their own name");
    assert!(!doc.rename_scan(bath, "nothing here", "x"));
}
