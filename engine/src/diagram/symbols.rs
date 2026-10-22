//! What things look like from above.
//!
//! Every set piece, vehicle, fixture and bit of grip the plan can hold, drawn
//! in its own footprint: `w` along its length (the way it faces, for anything
//! that faces), `h` across. Furniture has its back at the top (−y) and its
//! front toward the bottom; vehicles, fixtures and cameras face east (+x), the
//! way a turned thing at 0° faces.
//!
//! **The Film Set Objects pack comes first** (his ruling, 2026-09-27): every
//! picture in it is a library item, drawn exactly as the pack drew it
//! (`fso.rs`, written by `tools/fso_import.py`). What is drawn here is only
//! what the pack lacks, in the pack's own flat greys, charcoal, wood and
//! green (the paper palette in `svg.rs`), so the two sit together as one set.
//! Our older drawings of things the pack has stay drawable for plans that
//! hold them, but leave the library (`PACKED`).
//!
//! `CATALOG` is the library the Mac shows: every drawing, its name, its group
//! and the size it arrives at.

use super::fso;
use super::gear::{self, Board, Cloth, Front, Look, Tone};
use super::library;
use super::render::{circle, ellipse, line, poly, rect, rrect, Geom, Ink, Seg, Shape};
use super::El;

pub struct Sym {
    pub id: &'static str,
    pub name: &'static str,
    pub group: &'static str,
    /// A light (it can have a beam), rather than a set piece. Grip that
    /// shapes light — flags, rags, boards — lives with the lights too.
    pub light: bool,
    pub w: f64,
    pub h: f64,
    /// For a light: beam spread in degrees (360 = all round), reach in
    /// metres, colour temperature.
    pub beam: f64,
    pub reach: f64,
    pub kelvin: f64,
    /// How it is drawn: by its name, or as one of the gear families.
    pub look: Look,
}

const fn s(id: &'static str, name: &'static str, group: &'static str, w: f64, h: f64) -> Sym {
    Sym { id, name, group, light: false, w, h, beam: 0.0, reach: 0.0, kelvin: 0.0, look: Look::Named }
}

/// A set piece of the film's own — a stand, a dolly, a generator.
const fn g(id: &'static str, name: &'static str, group: &'static str, look: Look, w: f64, h: f64) -> Sym {
    Sym { id, name, group, light: false, w, h, beam: 0.0, reach: 0.0, kelvin: 0.0, look }
}

/// A light: beam, reach, Kelvin.
#[allow(clippy::too_many_arguments)]
const fn l(id: &'static str, name: &'static str, group: &'static str, look: Look, w: f64, h: f64, beam: f64, reach: f64, kelvin: f64) -> Sym {
    Sym { id, name, group, light: true, w, h, beam, reach, kelvin, look }
}

/// Grip that shapes light and gives none.
const fn k(id: &'static str, name: &'static str, group: &'static str, look: Look, w: f64, h: f64) -> Sym {
    Sym { id, name, group, light: true, w, h, beam: 0.0, reach: 0.0, kelvin: 0.0, look }
}

const TU: Look = Look::Fresnel(Tone::Tungsten);
const HF: Look = Look::Fresnel(Tone::Hmi);
const LF: Look = Look::Fresnel(Tone::Led);
const CAN: Look = Look::Can(Tone::Hmi);
const REF: Look = Look::Head(Front::Reflector);
const LENS: Look = Look::Head(Front::Fresnel);
const DOME: Look = Look::Head(Front::Dome);

pub const CATALOG: &[Sym] = &[
    // ---- set pieces
    g("bed", "Bed", "Furniture", Look::Bed(0), 1.5, 2.0),
    g("bed-one", "Bed, One in It", "Furniture", Look::Bed(1), 1.62, 1.9),
    g("bed-two", "Bed, Two in It", "Furniture", Look::Bed(2), 1.62, 1.9),
    g("bed-single", "Single Bed", "Furniture", Look::Bed(0), 0.95, 1.95),
    g("bed-king", "King Bed", "Furniture", Look::Bed(0), 1.95, 2.05),
    g("sofa", "Sofa", "Furniture", Look::Couch(3), 2.2, 0.88),
    g("loveseat", "Loveseat", "Furniture", Look::Couch(2), 1.8, 0.85),
    s("sofa-l", "Corner Sofa", "Furniture", 2.7, 1.8),
    g("armchair", "Armchair", "Furniture", Look::Couch(1), 1.0, 0.85),
    g("chair", "Chair", "Furniture", Look::Chair, 0.45, 0.48),
    g("office-chair", "Office Chair", "Furniture", Look::OfficeChair, 0.6, 0.55),
    s("stool", "Stool", "Furniture", 0.4, 0.4),
    g("table", "Table", "Furniture", Look::Table(false), 1.6, 0.9),
    g("table-square", "Square Table", "Furniture", Look::Table(false), 1.2, 1.2),
    g("table-round", "Round Table", "Furniture", Look::Table(true), 1.1, 1.1),
    g("table-round-l", "Large Round Table", "Furniture", Look::Table(true), 1.5, 1.5),
    // 60" across, 30" deep: a true half circle (`HALF_ROUND`).
    g("table-half-round", "Half Round", "Furniture", Look::HalfRound, 1.524, 0.762),
    g("side-table", "Side Table", "Furniture", Look::Table(true), 0.57, 0.57),
    s("dining", "Dining Table", "Furniture", 2.4, 1.8),
    g("coffee-table", "Coffee Table", "Furniture", Look::Table(false), 1.1, 0.6),
    s("desk", "Desk", "Furniture", 1.4, 0.7),
    s("nightstand", "Nightstand", "Furniture", 0.5, 0.45),
    s("dresser", "Dresser", "Furniture", 1.4, 0.5),
    s("wardrobe", "Wardrobe", "Furniture", 1.2, 0.62),
    s("bookshelf", "Bookshelf", "Furniture", 1.0, 0.35),
    s("cabinet", "Cabinet", "Furniture", 1.0, 0.5),
    s("tv", "Television", "Furniture", 1.25, 0.25),
    s("piano", "Piano", "Furniture", 1.55, 0.6),
    s("rug", "Rug", "Furniture", 2.4, 1.7),
    s("counter", "Counter", "Kitchen & Bath", 2.4, 0.65),
    s("island", "Kitchen Island", "Kitchen & Bath", 1.8, 0.95),
    s("fridge", "Fridge", "Kitchen & Bath", 0.8, 0.75),
    s("stove", "Stove", "Kitchen & Bath", 0.76, 0.65),
    s("sink", "Sink", "Kitchen & Bath", 0.8, 0.55),
    s("toilet", "Toilet", "Kitchen & Bath", 0.42, 0.7),
    s("bathtub", "Bathtub", "Kitchen & Bath", 1.7, 0.8),
    s("shower", "Shower", "Kitchen & Bath", 0.9, 0.9),
    s("bar", "Bar", "Kitchen & Bath", 2.6, 1.2),
    s("stairs", "Stairs", "Structure", 1.0, 3.0),
    // Stairs that turn (his ask, 2026-10-04): up a flight, a landing, and on.
    s("stairs-l", "Stairs, L Turn", "Structure", 3.0, 3.0),
    s("stairs-u", "Stairs, U Turn", "Structure", 2.4, 3.0),
    s("column", "Column", "Structure", 0.4, 0.4),
    s("fireplace", "Fireplace", "Structure", 1.5, 0.55),
    s("elevator", "Elevator", "Structure", 1.6, 1.6),
    s("box", "Box", "Structure", 1.0, 1.0),
    g("car", "Car", "Vehicles", Look::Car, 4.6, 1.85),
    g("suv", "SUV", "Vehicles", Look::Car, 4.9, 2.0),
    g("pickup", "Pickup Truck", "Vehicles", Look::Pickup, 5.5, 2.0),
    g("van", "Van", "Vehicles", Look::Car, 5.4, 2.05),
    s("truck", "Truck", "Vehicles", 7.0, 2.5),
    s("bus", "Bus", "Vehicles", 12.0, 2.55),
    s("motorbike", "Motorbike", "Vehicles", 2.1, 0.8),
    s("bicycle", "Bicycle", "Vehicles", 1.8, 0.6),
    // **Exteriors on a plot** (his ask, 2026-10-04, after the Las Vegas and
    // Backyard Chase plots): a building's footprint with its name inside, and
    // an area to shade with a note ("Street lights off in this area").
    s("building", "Building", "Outdoors", 12.0, 9.0),
    s("area", "Area", "Outdoors", 6.0, 6.0),
    g("tree", "Tree", "Outdoors", Look::Tree, 3.5, 3.5),
    g("hedge", "Hedge", "Outdoors", Look::Hedge, 3.0, 1.0),
    g("stump", "Tree Stump", "Outdoors", Look::Stump, 0.6, 0.6),
    g("sidewalk", "Sidewalk", "Outdoors", Look::Sidewalk, 3.9, 1.0),
    s("plant", "Plant", "Outdoors", 0.6, 0.6),
    s("bench", "Bench", "Outdoors", 1.6, 0.5),
    s("fence", "Fence", "Outdoors", 3.0, 0.1),
    s("umbrella", "Umbrella", "Outdoors", 2.5, 2.5),
    s("tent", "Tent", "Outdoors", 3.0, 3.0),
    s("stage", "Stage", "Stage", 6.0, 4.0),
    s("riser", "Riser", "Stage", 2.4, 1.2),
    s("drum-kit", "Drum Kit", "Stage", 2.2, 1.8),
    s("speaker", "Speaker", "Stage", 0.6, 0.5),
    s("mic-stand", "Mic Stand", "Stage", 0.5, 0.5),
    s("screen", "Screen", "Stage", 4.0, 0.3),
    g("seamless-white", "12' Seamless, White", "Stage", Look::Seamless(0), 3.6, 1.1),
    g("seamless-black", "12' Seamless, Black", "Stage", Look::Seamless(1), 3.6, 1.1),
    g("seamless-grey", "12' Seamless, Grey", "Stage", Look::Seamless(2), 3.6, 1.1),
    g("seamless-green", "12' Seamless, Green", "Stage", Look::Seamless(3), 3.6, 1.1),
    g("seamless-navy", "12' Seamless, Navy", "Stage", Look::Seamless(4), 3.6, 1.1),
    g("seamless-pink", "12' Seamless, Pink", "Stage", Look::Seamless(5), 3.6, 1.1),
    g("seamless-brown", "12' Seamless, Brown", "Stage", Look::Seamless(6), 3.6, 1.1),
    g("cyc-white", "White Cyc", "Stage", Look::Cyc(false), 5.4, 4.3),
    g("cyc-white-l", "Large White Cyc", "Stage", Look::Cyc(false), 11.85, 6.34),
    g("cyc-green", "Green Cyc", "Stage", Look::Cyc(true), 5.4, 4.3),
    g("cyc-green-l", "Large Green Cyc", "Stage", Look::Cyc(true), 11.85, 6.34),
    // ---- film gear. Sizes from the Film Set Objects pack and the makers.
    g("c-stand", "C-Stand", "Stands", Look::CStand, 0.9, 0.9),
    g("baby-stand", "Baby Stand", "Stands", Look::Combo, 0.7, 0.7),
    g("combo-stand", "Combo Stand", "Stands", Look::Combo, 1.1, 1.1),
    g("high-roller", "High Roller", "Stands", Look::Roller, 1.3, 1.3),
    g("crank-stand", "Crank Stand", "Stands", Look::Crank, 1.2, 1.2),
    g("sticks", "Sticks", "Stands", Look::Sticks, 0.85, 0.85),
    g("sticks-light", "Lightweight Sticks", "Stands", Look::Sticks, 0.75, 0.75),
    g("polecat-4", "4' Polecat", "Stands", Look::Polecat, 1.22, 0.06),
    g("polecat-6", "6' Polecat", "Stands", Look::Polecat, 1.83, 0.06),
    g("polecat-8", "8' Polecat", "Stands", Look::Polecat, 2.44, 0.06),
    g("dolly", "Dolly", "Dollies & Cranes", Look::Chapman, 0.99, 0.8),
    g("fisher", "Fisher Dolly", "Dollies & Cranes", Look::Fisher, 1.3, 0.82),
    g("chapman", "Chapman PeeWee", "Dollies & Cranes", Look::Chapman, 0.99, 0.8),
    g("doorway-dolly", "Doorway Dolly", "Dollies & Cranes", Look::Doorway, 1.52, 0.76),
    g("dana-dolly", "Dana Dolly", "Dollies & Cranes", Look::Dana, 2.59, 0.62),
    g("crane", "Crane", "Dollies & Cranes", Look::Jib, 4.0, 1.2),
    g("jib", "Portable Jib", "Dollies & Cranes", Look::Jib, 2.36, 0.79),
    g("technocrane", "Technocrane", "Dollies & Cranes", Look::Technocrane, 7.0, 1.6),
    g("menace-arm", "Menace Arm", "Dollies & Cranes", Look::Menace, 4.5, 1.0),
    g("russian-arm", "Russian Arm", "Dollies & Cranes", Look::Arm, 7.0, 2.0),
    g("easyrig", "Easyrig", "Dollies & Cranes", Look::Easyrig, 0.5, 0.55),
    g("condor", "Condor", "Dollies & Cranes", Look::Condor, 9.0, 2.5),
    g("scissor-lift", "Scissor Lift", "Dollies & Cranes", Look::Lift, 1.87, 0.88),
    g("track-4", "4' Track", "Track & Rail", Look::Track, 1.22, 0.62),
    g("track-8", "8' Track", "Track & Rail", Look::Track, 2.44, 0.62),
    g("curve-10", "10' Radius Curve", "Track & Rail", Look::Curve, 2.18, 0.93),
    g("curve-20", "20' Radius Curve", "Track & Rail", Look::Curve, 2.23, 0.84),
    g("circle-track", "Circle Track", "Track & Rail", Look::Circle, 2.95, 2.95),
    g("slider-3", "3' Slider", "Track & Rail", Look::Slider, 0.96, 0.2),
    g("slider-6", "6' Slider", "Track & Rail", Look::Slider, 1.85, 0.2),
    g("speed-rail-4", "4' Speed Rail", "Track & Rail", Look::Rail, 1.22, 0.06),
    g("speed-rail-8", "8' Speed Rail", "Track & Rail", Look::Rail, 2.44, 0.06),
    g("speed-rail-12", "12' Speed Rail", "Track & Rail", Look::Rail, 3.66, 0.06),
    g("box-truss-4", "4' Box Truss", "Track & Rail", Look::Truss(2), 1.22, 0.3),
    g("box-truss-8", "8' Box Truss", "Track & Rail", Look::Truss(2), 2.44, 0.3),
    g("triangle-truss", "Triangle Truss", "Track & Rail", Look::Truss(3), 2.44, 0.3),
    s("apple-box", "Apple Box", "Film Gear", 0.5, 0.3),
    s("sandbag", "Sandbag", "Film Gear", 0.45, 0.25),
    s("video-village", "Video Village", "Film Gear", 1.4, 0.9),
    s("director-chair", "Director's Chair", "Film Gear", 0.55, 0.5),
    g("monitor", "Monitor", "Film Gear", Look::Monitor, 0.61, 0.6),
    g("projector", "Projector", "Film Gear", Look::Projector, 0.58, 0.54),
    s("boom", "Boom", "Film Gear", 2.5, 0.35),
    g("easy-cart", "DIT Cart", "Film Gear", Look::Cart, 1.3, 0.75),
    g("hazer", "Hazer", "Film Gear", Look::Hazer, 0.42, 0.28),
    g("fan", "Industrial Fan", "Film Gear", Look::Fan, 0.49, 0.48),
    s("generator", "Generator", "Base Camp", 2.4, 1.2),
    g("generator-portable", "Portable Generator", "Base Camp", Look::PortableGen, 0.53, 0.75),
    g("tow-generator", "Tow Generator", "Base Camp", Look::TowGen, 2.97, 1.66),
    g("distro-400", "400A Distro", "Base Camp", Look::Distro, 0.59, 0.28),
    g("lunch-box", "100A Lunch Box", "Base Camp", Look::Distro, 0.33, 0.2),
    g("gang-box", "60A Gang Box", "Base Camp", Look::Distro, 0.23, 0.14),
    g("crafty", "Crafty Table", "Base Camp", Look::Crafty, 1.72, 0.82),
    g("canopy", "10×10 Canopy", "Base Camp", Look::Canopy, 3.05, 3.05),
    g("cone", "Traffic Cone", "Base Camp", Look::Cone, 0.3, 0.3),

    // ---- lights, plain: a stand-in for any unit the pack does not have,
    // OpenShotDesigner's set of kinds, drawn with our own families. Shown
    // first among the lights; the few the pack has unbranded are `PACKED`.
    l("generic-fresnel", "Fresnel", "Generic", TU, 0.34, 0.29, 40.0, 4.5, 3200.0),
    l("generic-open-face", "Open Face", "Generic", Look::OpenFace, 0.35, 0.39, 60.0, 5.5, 3200.0),
    l("generic-par", "Par Can", "Generic", Look::Par, 0.4, 0.4, 25.0, 6.0, 3200.0),
    l("generic-ellipsoidal", "Ellipsoidal", "Generic", Look::Ellipsoidal, 0.68, 0.22, 26.0, 9.0, 3200.0),
    l("generic-hmi", "HMI", "Generic", HF, 0.61, 0.58, 35.0, 8.0, 5600.0),
    l("generic-cob", "COB Light", "Generic", REF, 0.47, 0.22, 55.0, 4.0, 5600.0),
    l("generic-panel", "LED Panel", "Generic", Look::Panel, 0.14, 0.7, 100.0, 3.5, 5600.0),
    l("generic-kino", "Kino", "Generic", Look::Kino, 0.2, 1.49, 110.0, 3.0, 5600.0),
    l("generic-tube", "Tube", "Generic", Look::Tube, 0.06, 1.2, 150.0, 2.2, 5600.0),
    l("generic-mat", "LED Mat", "Generic", Look::Mat, 0.06, 0.6, 110.0, 2.5, 5600.0),
    l("generic-softbox", "Softbox", "Generic", Look::Softbox, 0.55, 0.9, 90.0, 3.0, 5600.0),
    l("generic-china-ball", "China Ball", "Generic", Look::Ball, 0.42, 0.42, 360.0, 2.2, 3200.0),
    l("generic-spacelight", "Space Light", "Generic", Look::Spacelight, 0.76, 0.76, 360.0, 4.0, 3200.0),
    l("generic-practical", "Practical", "Generic", Look::Shade, 0.35, 0.35, 360.0, 1.6, 2700.0),
    // ---- lights by size, the way a gaffer asks for one (2026-09-30): "a
    // 4K PAR", "a 20K". The plain drawings, at each unit's real size.
    l("hmi-fresnel-18k", "18K HMI Fresnel", "Generic", HF, 1.0, 0.9, 30.0, 18.0, 5600.0),
    l("hmi-fresnel-12k", "12K HMI Fresnel", "Generic", HF, 0.9, 0.8, 30.0, 16.0, 5600.0),
    l("hmi-fresnel-6k", "6K HMI Fresnel", "Generic", HF, 0.72, 0.66, 32.0, 13.0, 5600.0),
    l("hmi-fresnel-4k", "4K HMI Fresnel", "Generic", HF, 0.6, 0.56, 35.0, 11.0, 5600.0),
    l("hmi-fresnel-2.5k", "2.5K HMI Fresnel", "Generic", HF, 0.5, 0.46, 35.0, 9.0, 5600.0),
    l("hmi-fresnel-1.2k", "1.2K HMI Fresnel", "Generic", HF, 0.42, 0.38, 35.0, 7.0, 5600.0),
    l("hmi-fresnel-575", "575W HMI Fresnel", "Generic", HF, 0.32, 0.3, 40.0, 5.0, 5600.0),
    l("hmi-par-18k", "18K HMI PAR", "Generic", CAN, 1.08, 1.04, 25.0, 22.0, 5600.0),
    l("hmi-par-12k", "12K HMI PAR", "Generic", CAN, 0.95, 0.9, 25.0, 19.0, 5600.0),
    l("hmi-par-6k", "6K HMI PAR", "Generic", CAN, 0.8, 0.76, 25.0, 16.0, 5600.0),
    l("hmi-par-4k", "4K HMI PAR", "Generic", CAN, 0.76, 0.73, 25.0, 14.0, 5600.0),
    l("hmi-par-2.5k", "2.5K HMI PAR", "Generic", CAN, 0.62, 0.6, 25.0, 12.0, 5600.0),
    l("hmi-par-1.8k", "1.8K HMI PAR", "Generic", CAN, 0.61, 0.58, 25.0, 11.0, 5600.0),
    l("hmi-par-1.2k", "1.2K HMI PAR", "Generic", CAN, 0.5, 0.48, 25.0, 9.0, 5600.0),
    l("hmi-par-575", "575W HMI PAR", "Generic", CAN, 0.38, 0.36, 25.0, 7.0, 5600.0),
    l("tungsten-fresnel-20k", "20K Tungsten Fresnel", "Generic", TU, 1.15, 1.0, 35.0, 16.0, 3200.0),
    l("tungsten-fresnel-10k", "10K Tungsten Fresnel", "Generic", TU, 0.75, 0.64, 35.0, 12.0, 3200.0),
    l("tungsten-fresnel-5k", "5K Tungsten Fresnel", "Generic", TU, 0.6, 0.52, 40.0, 9.0, 3200.0),
    l("tungsten-fresnel-2k", "2K Tungsten Fresnel", "Generic", TU, 0.44, 0.38, 40.0, 6.5, 3200.0),
    l("tungsten-fresnel-1k", "1K Tungsten Fresnel", "Generic", TU, 0.34, 0.29, 40.0, 5.0, 3200.0),
    l("tungsten-fresnel-650", "650W Tungsten Fresnel", "Generic", TU, 0.29, 0.23, 40.0, 3.5, 3200.0),
    l("tungsten-fresnel-300", "300W Tungsten Fresnel", "Generic", TU, 0.26, 0.21, 45.0, 2.5, 3200.0),
    l("tungsten-fresnel-150", "150W Tungsten Fresnel", "Generic", TU, 0.25, 0.15, 45.0, 2.0, 3200.0),
    k("generic-bounce", "Bounce", "Generic", Look::Board(Board::Foam), 0.08, 1.2),
    k("generic-flag", "Flag", "Generic", Look::Flag(Cloth::Solid), 0.06, 0.6),
    k("generic-frame", "Overhead Frame", "Generic", Look::Rag(Cloth::Silk), 1.83, 1.83),
    // Scenario's Frame: any size, any skin, standing or lying (`frame.rs`).
    k("frame", "Frame", "Generic", Look::Named, 2.44, 2.44),

    // ---- lights: beam, reach, Kelvin
    l("fresnel-650", "650 Fresnel", "Tungsten", TU, 0.29, 0.23, 40.0, 3.5, 3200.0),
    l("fresnel", "1K Fresnel", "Tungsten", TU, 0.34, 0.29, 40.0, 4.5, 3200.0),
    l("fresnel-2k", "2K Fresnel", "Tungsten", TU, 0.44, 0.38, 40.0, 6.0, 3200.0),
    l("fresnel-5k", "5K Fresnel", "Tungsten", TU, 0.6, 0.52, 40.0, 8.0, 3200.0),
    l("fresnel-10k", "10K Fresnel", "Tungsten", TU, 0.75, 0.64, 35.0, 10.0, 3200.0),
    l("arri-150", "Arri 150", "Tungsten", TU, 0.25, 0.15, 45.0, 2.0, 3200.0),
    l("arri-300", "Arri 300", "Tungsten", TU, 0.26, 0.21, 45.0, 2.5, 3200.0),
    l("arri-650", "Arri 650", "Tungsten", TU, 0.29, 0.23, 40.0, 3.5, 3200.0),
    l("arri-t12", "Arri T12", "Tungsten", TU, 0.81, 0.68, 35.0, 12.0, 3200.0),
    l("arri-t24", "Arri T24", "Tungsten", TU, 1.02, 0.88, 35.0, 15.0, 3200.0),
    l("mole-tweenie", "Mole Tweenie", "Tungsten", TU, 0.28, 0.24, 40.0, 3.2, 3200.0),
    l("mole-baby", "Mole Baby", "Tungsten", TU, 0.36, 0.3, 40.0, 4.5, 3200.0),
    l("mole-junior", "Mole Junior", "Tungsten", TU, 0.44, 0.38, 40.0, 6.0, 3200.0),
    l("arrilite-750", "Arrilite 750", "Tungsten", Look::OpenFace, 0.28, 0.22, 60.0, 4.0, 3200.0),
    l("arrilite-2k", "Arrilite 2K", "Tungsten", Look::OpenFace, 0.35, 0.39, 60.0, 5.5, 3200.0),
    l("skypan-5k", "SkyPan 5K", "Tungsten", Look::OpenFace, 0.4, 0.76, 90.0, 6.0, 3200.0),
    l("par", "PAR", "Tungsten", Look::Par, 0.4, 0.4, 25.0, 6.0, 3200.0),
    l("par-64", "Par 64", "Tungsten", Look::Par, 0.5, 0.23, 15.0, 7.0, 3200.0),
    l("mole-par-1k", "Mole 1K Par", "Tungsten", Look::Par, 0.42, 0.33, 20.0, 6.0, 3200.0),
    l("mole-par-2k", "Mole 2K Par", "Tungsten", Look::Par, 0.56, 0.43, 20.0, 8.0, 3200.0),
    l("mole-par-5k", "Mole 5K Par", "Tungsten", Look::Par, 0.73, 0.54, 20.0, 11.0, 3200.0),
    l("molefay-6", "Molefay 6-Light", "Tungsten", Look::Cluster(3, 2), 0.3, 0.62, 30.0, 8.0, 3200.0),
    l("molefay-9", "Molefay 9-Light", "Tungsten", Look::Cluster(3, 3), 0.32, 0.62, 30.0, 10.0, 3200.0),
    l("maxi-6", "6K Molepar", "Tungsten", Look::Cluster(3, 2), 0.4, 0.78, 25.0, 12.0, 3200.0),
    l("maxi-9", "9K Molepar", "Tungsten", Look::Cluster(3, 3), 0.42, 0.85, 25.0, 14.0, 3200.0),
    l("molebeam-5k", "Molebeam 5K", "Tungsten", Look::Beam, 0.75, 0.7, 8.0, 20.0, 3200.0),
    l("molebeam-10k", "Molebeam 10K", "Tungsten", Look::Beam, 0.95, 0.9, 8.0, 25.0, 3200.0),
    l("molebeam-20k", "Molebeam 20K", "Tungsten", Look::Beam, 1.2, 1.1, 8.0, 30.0, 3200.0),
    l("ellipsoidal", "Ellipsoidal", "Tungsten", Look::Ellipsoidal, 0.68, 0.22, 26.0, 9.0, 3200.0),
    l("followspot", "Followspot", "Tungsten", Look::Ellipsoidal, 1.1, 0.35, 12.0, 12.0, 5600.0),
    l("hmi", "1.8K HMI", "HMI", HF, 0.61, 0.58, 35.0, 8.0, 5600.0),
    l("hmi-4k", "4K HMI", "HMI", HF, 0.76, 0.73, 30.0, 10.0, 5600.0),
    l("hmi-18k", "18K HMI", "HMI", HF, 1.0, 0.84, 25.0, 16.0, 5600.0),
    l("arri-1812", "Arri 18/12 Fresnel", "HMI", HF, 1.0, 0.84, 25.0, 18.0, 5600.0),
    l("arri-m8", "Arri M8", "HMI", CAN, 0.38, 0.36, 35.0, 7.0, 5600.0),
    l("arri-m18", "Arri M18", "HMI", CAN, 0.61, 0.58, 35.0, 9.0, 5600.0),
    l("arri-m40", "Arri M40", "HMI", CAN, 0.76, 0.73, 30.0, 12.0, 5600.0),
    l("arri-m90", "Arri M90", "HMI", CAN, 0.83, 0.79, 30.0, 15.0, 5600.0),
    l("arrimax", "Arrimax 18/12", "HMI", CAN, 1.08, 1.04, 25.0, 18.0, 5600.0),
    l("mole-par-12k", "Mole 12K Par", "HMI", Look::Par, 1.05, 0.81, 18.0, 16.0, 5600.0),
    l("joker-200", "Joker 200", "HMI", Look::Joker, 0.22, 0.16, 30.0, 4.0, 5600.0),
    l("joker-400", "Joker 400", "HMI", Look::Joker, 0.32, 0.22, 30.0, 5.0, 5600.0),
    l("joker-800", "Joker 800", "HMI", Look::Joker, 0.4, 0.32, 30.0, 7.0, 5600.0),
    l("joker-1600", "Joker 1600", "HMI", Look::Joker, 0.5, 0.41, 30.0, 9.0, 5600.0),
    l("joker-800-softube", "Joker 800 Softube", "HMI", Look::Softube, 1.16, 0.26, 180.0, 4.5, 5600.0),
    l("joker-1600-softube", "Joker 1600 Softube", "HMI", Look::Softube, 1.53, 0.35, 180.0, 6.0, 5600.0),
    l("cob", "COB Light", "LED", REF, 0.47, 0.22, 55.0, 4.0, 5600.0),
    l("aputure-120d", "Aputure 120D", "LED", REF, 0.38, 0.2, 55.0, 3.5, 5600.0),
    l("aputure-300d", "Aputure 300D", "LED", REF, 0.47, 0.22, 55.0, 4.5, 5600.0),
    l("aputure-600d", "Aputure 600D", "LED", REF, 0.52, 0.3, 55.0, 6.0, 5600.0),
    l("aputure-600d-fresnel", "600D with Fresnel", "LED", LENS, 0.55, 0.41, 25.0, 8.0, 5600.0),
    l("aputure-1200d", "Aputure 1200D", "LED", REF, 0.6, 0.37, 55.0, 8.0, 5600.0),
    l("aputure-1200d-fresnel", "1200D with F10 Fresnel", "LED", LENS, 0.7, 0.45, 25.0, 11.0, 5600.0),
    l("aputure-cs15", "Aputure CS15", "LED", REF, 0.79, 0.5, 45.0, 11.0, 5600.0),
    l("aputure-xt26", "Aputure XT26", "LED", REF, 0.9, 0.56, 40.0, 13.0, 5600.0),
    l("light-dome", "Light Dome II", "LED", DOME, 0.75, 0.9, 90.0, 5.0, 5600.0),
    l("light-dome-mini", "Light Dome Mini", "LED", DOME, 0.45, 0.6, 90.0, 3.5, 5600.0),
    l("forza-60", "Nanlite Forza 60", "LED", REF, 0.3, 0.18, 55.0, 3.0, 5600.0),
    l("forza-300", "Nanlite Forza 300", "LED", REF, 0.4, 0.24, 55.0, 4.5, 5600.0),
    l("forza-500", "Nanlite Forza 500", "LED", REF, 0.46, 0.28, 55.0, 5.5, 5600.0),
    l("evoke-1200", "Nanlux Evoke 1200", "LED", REF, 0.62, 0.4, 45.0, 9.0, 5600.0),
    l("evoke-2400", "Nanlux Evoke 2400", "LED", REF, 0.72, 0.48, 45.0, 12.0, 5600.0),
    l("arri-l5", "Arri L5", "LED", LF, 0.28, 0.22, 35.0, 3.5, 5600.0),
    l("arri-l7", "Arri L7", "LED", LF, 0.41, 0.32, 35.0, 5.0, 5600.0),
    l("arri-l10", "Arri L10", "LED", LF, 0.57, 0.45, 35.0, 7.0, 5600.0),
    l("arri-orbiter", "Arri Orbiter", "LED", REF, 0.4, 0.37, 50.0, 7.0, 5600.0),
    l("mole-senior-led", "Mole SeniorLED", "LED", LF, 0.46, 0.41, 40.0, 8.0, 5600.0),
    l("mole-tenor-led", "Mole TenorLED", "LED", LF, 0.56, 0.5, 35.0, 10.0, 5600.0),
    l("source-four-led", "Source Four LED", "LED", Look::Ellipsoidal, 0.67, 0.22, 26.0, 8.0, 5600.0),
    l("panel", "LED Panel", "LED Panels", Look::Panel, 0.14, 0.7, 100.0, 3.5, 5600.0),
    l("panel-l", "Large LED Panel", "LED Panels", Look::Panel, 0.14, 1.31, 100.0, 4.5, 5600.0),
    l("skypanel-s30", "SkyPanel S30", "LED Panels", Look::Panel, 0.14, 0.75, 110.0, 3.5, 5600.0),
    l("skypanel-s60", "SkyPanel S60", "LED Panels", Look::Panel, 0.14, 0.86, 110.0, 4.5, 5600.0),
    l("skypanel-s120", "SkyPanel S120", "LED Panels", Look::Panel, 0.14, 1.31, 110.0, 5.5, 5600.0),
    l("skypanel-s360", "SkyPanel S360", "LED Panels", Look::Panel, 0.16, 1.45, 110.0, 8.0, 5600.0),
    l("skypanel-x", "SkyPanel X", "LED Panels", Look::Panel, 0.18, 0.82, 110.0, 7.0, 5600.0),
    l("astra", "Astra 1x1", "LED Panels", Look::Panel, 0.09, 0.41, 50.0, 3.0, 5600.0),
    l("celeb-250", "Kino Celeb 250", "LED Panels", Look::Panel, 0.08, 0.76, 90.0, 3.5, 5600.0),
    l("celeb-450", "Kino Celeb 450", "LED Panels", Look::Panel, 0.08, 1.3, 90.0, 4.5, 5600.0),
    l("celeb-850", "Kino Celeb 850", "LED Panels", Look::Panel, 0.1, 1.45, 90.0, 5.5, 5600.0),
    l("vortex-4", "Creamsource Vortex 4", "LED Panels", Look::Panel, 0.15, 0.6, 100.0, 5.0, 5600.0),
    l("vortex-8", "Creamsource Vortex 8", "LED Panels", Look::Panel, 0.15, 0.84, 100.0, 6.5, 5600.0),
    l("dyno-650", "Nanlite Dyno 650", "LED Panels", Look::Panel, 0.14, 0.9, 100.0, 5.5, 5600.0),
    l("dyno-1200", "Nanlite Dyno 1200", "LED Panels", Look::Panel, 0.14, 1.05, 100.0, 7.0, 5600.0),
    l("mixpanel-60", "Nanlite Mixpanel 60", "LED Panels", Look::Panel, 0.16, 0.45, 100.0, 3.0, 5600.0),
    l("mixpanel-150", "Nanlite Mixpanel 150", "LED Panels", Look::Panel, 0.2, 0.62, 100.0, 4.0, 5600.0),
    l("ds6", "Digital Sputnik DS6", "LED Panels", Look::Panel, 0.3, 0.6, 30.0, 8.0, 5600.0),
    l("kino", "Kino Flo", "LED Panels", Look::Kino, 0.2, 1.49, 110.0, 3.0, 5600.0),
    l("kino-4-bank", "Kino 4' 4-Bank", "LED Panels", Look::Kino, 0.2, 1.49, 100.0, 3.5, 5600.0),
    l("kino-2-bank", "Kino 2' 4-Bank", "LED Panels", Look::Kino, 0.18, 0.7, 100.0, 2.5, 5600.0),
    l("diva-400", "Diva-Lite 400", "LED Panels", Look::Kino, 0.2, 0.8, 100.0, 3.0, 5600.0),
    l("zip-2k", "Mole 2K Zip Softlite", "LED Panels", Look::Kino, 0.5, 0.7, 90.0, 4.0, 3200.0),
    l("mat", "LED Mat", "Mats & Tubes", Look::Mat, 0.06, 0.6, 110.0, 2.5, 5600.0),
    l("litemat-1x1", "1×1 LiteMat", "Mats & Tubes", Look::Mat, 0.05, 0.33, 110.0, 2.0, 5600.0),
    l("litemat-2x2", "2×2 LiteMat", "Mats & Tubes", Look::Mat, 0.05, 0.61, 110.0, 3.0, 5600.0),
    l("litemat-4x1", "4×1 LiteMat", "Mats & Tubes", Look::Mat, 0.05, 1.15, 110.0, 3.0, 5600.0),
    l("litemat-4x2", "4×2 LiteMat", "Mats & Tubes", Look::Mat, 0.05, 1.14, 110.0, 3.5, 5600.0),
    l("litetile-2x4", "2×4 LiteTile", "Mats & Tubes", Look::Mat, 0.05, 1.26, 110.0, 3.5, 5600.0),
    l("litetile-2x8", "2×8 LiteTile", "Mats & Tubes", Look::Mat, 0.05, 2.47, 110.0, 4.0, 5600.0),
    l("infinimat-1x4", "Infinimat 1×4", "Mats & Tubes", Look::Mat, 0.05, 1.22, 110.0, 3.0, 5600.0),
    l("infinimat-2x4", "Infinimat 2×4", "Mats & Tubes", Look::Mat, 0.05, 1.22, 110.0, 3.5, 5600.0),
    l("infinimat-4x4", "Infinimat 4×4 Overhead", "Mats & Tubes", Look::Mat, 1.25, 1.29, 120.0, 4.0, 5600.0),
    l("infinimat-8x8", "Infinimat 8×8 Overhead", "Mats & Tubes", Look::Mat, 2.24, 2.24, 120.0, 5.0, 5600.0),
    l("tube", "LED Tube", "Mats & Tubes", Look::Tube, 0.06, 1.2, 150.0, 2.2, 5600.0),
    l("tube-s", "Short Tube", "Mats & Tubes", Look::Tube, 0.05, 0.6, 150.0, 1.6, 5600.0),
    l("quasar-2", "Quasar 2'", "Mats & Tubes", Look::Tube, 0.06, 0.65, 150.0, 1.8, 5600.0),
    l("quasar-4", "Quasar 4'", "Mats & Tubes", Look::Tube, 0.06, 1.29, 150.0, 2.4, 5600.0),
    l("quasar-8", "Quasar 8'", "Mats & Tubes", Look::Tube, 0.05, 2.44, 150.0, 3.0, 5600.0),
    l("astera-titan", "Astera Titan", "Mats & Tubes", Look::Tube, 0.05, 1.06, 150.0, 2.5, 5600.0),
    l("astera-helios", "Astera Helios", "Mats & Tubes", Look::Tube, 0.05, 0.55, 150.0, 1.8, 5600.0),
    l("pavo-15", "Nanlite Pavo 15", "Mats & Tubes", Look::Tube, 0.06, 0.79, 150.0, 1.8, 5600.0),
    l("pavo-30", "Nanlite Pavo 30", "Mats & Tubes", Look::Tube, 0.06, 1.25, 150.0, 2.4, 5600.0),
    l("infinibar-pb6", "Infinibar PB6", "Mats & Tubes", Look::Tube, 0.09, 0.6, 150.0, 1.8, 5600.0),
    l("infinibar-pb12", "Infinibar PB12", "Mats & Tubes", Look::Tube, 0.09, 1.19, 150.0, 2.4, 5600.0),
    l("kino-tube", "Kino Tube 4'", "Mats & Tubes", Look::Tube, 0.06, 1.3, 180.0, 1.8, 5600.0),
    l("softbox", "Softbox", "Soft", Look::Softbox, 0.55, 0.9, 90.0, 3.0, 5600.0),
    l("softbox-s", "Small Softbox", "Soft", Look::Softbox, 0.48, 0.85, 90.0, 2.5, 5600.0),
    l("softbox-l", "Large Softbox", "Soft", Look::Softbox, 0.73, 1.28, 90.0, 4.0, 5600.0),
    l("pancake", "Pancake", "Soft", Look::Softbox, 0.39, 0.81, 100.0, 3.0, 5600.0),
    l("lantern", "Lantern", "Soft", Look::Ball, 0.7, 0.7, 360.0, 2.5, 3200.0),
    l("china-ball", "China Ball", "Soft", Look::Ball, 0.42, 0.42, 360.0, 2.2, 3200.0),
    l("china-ball-l", "Large China Ball", "Soft", Look::Ball, 0.75, 0.75, 360.0, 3.0, 3200.0),
    l("spacelight", "Space Light", "Soft", Look::Spacelight, 0.76, 0.76, 360.0, 4.0, 3200.0),
    l("spacelight-6k", "6K Space Light", "Soft", Look::Spacelight, 1.2, 1.2, 360.0, 6.0, 3200.0),
    l("briese-100", "Briese Focus 100", "Soft", Look::Parabolic, 0.55, 1.0, 90.0, 6.0, 5600.0),
    l("briese-180", "Briese Focus 180", "Soft", Look::Parabolic, 0.95, 1.8, 90.0, 9.0, 5600.0),
    l("briese-220", "Briese Focus 220", "Soft", Look::Parabolic, 1.15, 2.2, 90.0, 10.0, 5600.0),
    l("briese-330", "Briese Focus 330", "Soft", Look::Parabolic, 1.7, 3.3, 90.0, 13.0, 5600.0),
    l("mozzie", "Spider Mozzie", "Soft", Look::Softbox, 1.0, 0.9, 90.0, 4.0, 5600.0),
    l("redback", "Spider Redback", "Soft", Look::Softbox, 1.26, 1.26, 90.0, 6.0, 5600.0),
    l("practical", "Practical", "Practicals", Look::Shade, 0.35, 0.35, 360.0, 1.6, 2700.0),
    l("bulb", "Bulb", "Practicals", Look::Bulb, 0.12, 0.12, 360.0, 1.2, 2700.0),
    l("lamp-shade", "Lamp with Shade", "Practicals", Look::Shade, 0.45, 0.45, 360.0, 2.0, 2700.0),
    l("street-sodium", "Street Light, Sodium", "Practicals", Look::StreetLight, 2.0, 0.35, 100.0, 8.0, 2000.0),
    l("street-mercury", "Street Light, Mercury", "Practicals", Look::StreetLight, 2.0, 0.35, 100.0, 8.0, 4200.0),
    l("wall-light", "Wall Utility Light", "Practicals", Look::WallLight, 0.16, 0.33, 120.0, 4.0, 3000.0),
    l("flashlight", "Flashlight", "Practicals", Look::Torch, 0.17, 0.06, 20.0, 3.0, 5600.0),
    // ---- grip
    k("flag", "Flag", "Flags & Nets", Look::Flag(Cloth::Solid), 0.06, 0.6),
    k("floppy", "Floppy", "Flags & Nets", Look::Flag(Cloth::Solid), 0.06, 1.2),
    k("cutter", "Cutter", "Flags & Nets", Look::Flag(Cloth::Solid), 0.06, 1.1),
    k("net", "Net", "Flags & Nets", Look::Flag(Cloth::Single), 0.06, 0.6),
    k("silk", "Silk", "Flags & Nets", Look::Flag(Cloth::Silk), 0.06, 1.2),
    k("flag-18x24", "18×24 Flag", "Flags & Nets", Look::Flag(Cloth::Solid), 0.05, 0.61),
    k("single-18x24", "18×24 Single", "Flags & Nets", Look::Flag(Cloth::Single), 0.05, 0.61),
    k("double-18x24", "18×24 Double", "Flags & Nets", Look::Flag(Cloth::Double), 0.05, 0.61),
    k("silk-18x24", "18×24 Silk", "Flags & Nets", Look::Flag(Cloth::Silk), 0.05, 0.61),
    k("flag-24x36", "24×36 Flag", "Flags & Nets", Look::Flag(Cloth::Solid), 0.05, 0.91),
    k("single-24x36", "24×36 Single", "Flags & Nets", Look::Flag(Cloth::Single), 0.05, 0.91),
    k("double-24x36", "24×36 Double", "Flags & Nets", Look::Flag(Cloth::Double), 0.05, 0.91),
    k("silk-24x36", "24×36 Silk", "Flags & Nets", Look::Flag(Cloth::Silk), 0.05, 0.91),
    k("artsilk-24x36", "24×36 Artificial Silk", "Flags & Nets", Look::Flag(Cloth::ArtSilk), 0.05, 0.91),
    k("flag-4x4", "4×4 Floppy", "Flags & Nets", Look::Flag(Cloth::Solid), 0.06, 1.22),
    k("single-4x4", "4×4 Single", "Flags & Nets", Look::Flag(Cloth::Single), 0.06, 1.22),
    k("double-4x4", "4×4 Double", "Flags & Nets", Look::Flag(Cloth::Double), 0.06, 1.22),
    k("silk-4x4", "4×4 Silk", "Flags & Nets", Look::Flag(Cloth::Silk), 0.06, 1.22),
    k("artsilk-4x4", "4×4 Artificial Silk", "Flags & Nets", Look::Flag(Cloth::ArtSilk), 0.06, 1.22),
    k("bounce", "Bounce", "Boards", Look::Board(Board::Foam), 0.08, 1.2),
    k("negative", "Negative Fill", "Boards", Look::Board(Board::Neg), 0.08, 1.2),
    k("foam-4x4", "4×4 Foam Core", "Boards", Look::Board(Board::Foam), 0.04, 1.22),
    k("foam-4x8", "4×8 Foam Core", "Boards", Look::Board(Board::Foam), 0.04, 2.44),
    k("neg-4x4", "4×4 Neg", "Boards", Look::Board(Board::Neg), 0.04, 1.22),
    k("shiny-4x4", "4×4 Shiny Board", "Boards", Look::Board(Board::Shiny), 0.08, 1.22),
    k("showcard", "Showcard", "Boards", Look::Board(Board::Card), 0.02, 0.76),
    k("crls-100", "CRLS C-100", "Boards", Look::Board(Board::Reflector), 0.05, 1.0),
    k("crls-50", "CRLS C-DIFF 50", "Boards", Look::Board(Board::Reflector), 0.05, 0.5),
    k("crls-25", "CRLS C-DIFF 25", "Boards", Look::Board(Board::Reflector), 0.05, 0.25),
    k("frame-6", "6×6 Frame", "Rags 6×6", Look::Rag(Cloth::Silk), 1.83, 1.83),
    k("frame-8", "8×8 Frame", "Rags 8×8", Look::Rag(Cloth::Silk), 2.44, 2.44),
    k("frame-12", "12×12 Frame", "Rags 12×12", Look::Rag(Cloth::Silk), 3.66, 3.66),
    k("frame-20", "20×20 Frame", "Rags 20×20", Look::Rag(Cloth::Silk), 6.1, 6.1),
    k("rag-6-solid", "6×6 Solid", "Rags 6×6", Look::Rag(Cloth::Solid), 1.83, 1.83),
    k("rag-6-grid", "6×6 Grid Cloth", "Rags 6×6", Look::Rag(Cloth::Grid), 1.83, 1.83),
    k("rag-6-bounce", "6×6 Ultrabounce", "Rags 6×6", Look::Rag(Cloth::Bounce), 1.83, 1.83),
    k("rag-6-muslin", "6×6 Muslin", "Rags 6×6", Look::Rag(Cloth::Muslin), 1.83, 1.83),
    k("rag-6-silk", "6×6 Silk", "Rags 6×6", Look::Rag(Cloth::Silk), 1.83, 1.83),
    k("rag-6-single", "6×6 Single Net", "Rags 6×6", Look::Rag(Cloth::Single), 1.83, 1.83),
    k("rag-6-double", "6×6 Double Net", "Rags 6×6", Look::Rag(Cloth::Double), 1.83, 1.83),
    k("rag-6-lcd", "6×6 LCD", "Rags 6×6", Look::Rag(Cloth::Lcd), 1.83, 1.83),
    k("rag-8-solid", "8×8 Solid", "Rags 8×8", Look::Rag(Cloth::Solid), 2.44, 2.44),
    k("rag-8-grid", "8×8 Grid Cloth", "Rags 8×8", Look::Rag(Cloth::Grid), 2.44, 2.44),
    k("rag-8-bounce", "8×8 Ultrabounce", "Rags 8×8", Look::Rag(Cloth::Bounce), 2.44, 2.44),
    k("rag-8-muslin", "8×8 Muslin", "Rags 8×8", Look::Rag(Cloth::Muslin), 2.44, 2.44),
    k("rag-8-silk", "8×8 Silk", "Rags 8×8", Look::Rag(Cloth::Silk), 2.44, 2.44),
    k("rag-8-single", "8×8 Single Net", "Rags 8×8", Look::Rag(Cloth::Single), 2.44, 2.44),
    k("rag-8-double", "8×8 Double Net", "Rags 8×8", Look::Rag(Cloth::Double), 2.44, 2.44),
    k("rag-8-lcd", "8×8 LCD", "Rags 8×8", Look::Rag(Cloth::Lcd), 2.44, 2.44),
    k("rag-12-solid", "12×12 Solid", "Rags 12×12", Look::Rag(Cloth::Solid), 3.66, 3.66),
    k("rag-12-grid", "12×12 Grid Cloth", "Rags 12×12", Look::Rag(Cloth::Grid), 3.66, 3.66),
    k("rag-12-bounce", "12×12 Ultrabounce", "Rags 12×12", Look::Rag(Cloth::Bounce), 3.66, 3.66),
    k("rag-12-muslin", "12×12 Muslin", "Rags 12×12", Look::Rag(Cloth::Muslin), 3.66, 3.66),
    k("rag-12-silk", "12×12 Silk", "Rags 12×12", Look::Rag(Cloth::Silk), 3.66, 3.66),
    k("rag-12-single", "12×12 Single Net", "Rags 12×12", Look::Rag(Cloth::Single), 3.66, 3.66),
    k("rag-12-double", "12×12 Double Net", "Rags 12×12", Look::Rag(Cloth::Double), 3.66, 3.66),
    k("rag-12-lcd", "12×12 LCD", "Rags 12×12", Look::Rag(Cloth::Lcd), 3.66, 3.66),
    k("rag-12x20-solid", "12×20 Solid", "Rags 12×20", Look::Rag(Cloth::Solid), 3.66, 6.1),
    k("rag-12x20-grid", "12×20 Grid Cloth", "Rags 12×20", Look::Rag(Cloth::Grid), 3.66, 6.1),
    k("rag-12x20-bounce", "12×20 Ultrabounce", "Rags 12×20", Look::Rag(Cloth::Bounce), 3.66, 6.1),
    k("rag-12x20-muslin", "12×20 Muslin", "Rags 12×20", Look::Rag(Cloth::Muslin), 3.66, 6.1),
    k("rag-12x20-silk", "12×20 Silk", "Rags 12×20", Look::Rag(Cloth::Silk), 3.66, 6.1),
    k("rag-12x20-single", "12×20 Single Net", "Rags 12×20", Look::Rag(Cloth::Single), 3.66, 6.1),
    k("rag-12x20-double", "12×20 Double Net", "Rags 12×20", Look::Rag(Cloth::Double), 3.66, 6.1),
    k("rag-12x20-lcd", "12×20 LCD", "Rags 12×20", Look::Rag(Cloth::Lcd), 3.66, 6.1),
    k("rag-20-solid", "20×20 Solid", "Rags 20×20", Look::Rag(Cloth::Solid), 6.1, 6.1),
    k("rag-20-grid", "20×20 Grid Cloth", "Rags 20×20", Look::Rag(Cloth::Grid), 6.1, 6.1),
    k("rag-20-bounce", "20×20 Ultrabounce", "Rags 20×20", Look::Rag(Cloth::Bounce), 6.1, 6.1),
    k("rag-20-muslin", "20×20 Muslin", "Rags 20×20", Look::Rag(Cloth::Muslin), 6.1, 6.1),
    k("rag-20-silk", "20×20 Silk", "Rags 20×20", Look::Rag(Cloth::Silk), 6.1, 6.1),
    k("rag-20-single", "20×20 Single Net", "Rags 20×20", Look::Rag(Cloth::Single), 6.1, 6.1),
    k("rag-20-double", "20×20 Double Net", "Rags 20×20", Look::Rag(Cloth::Double), 6.1, 6.1),
    k("rag-20-lcd", "20×20 LCD", "Rags 20×20", Look::Rag(Cloth::Lcd), 6.1, 6.1),
];


pub fn find(id: &str) -> Option<&'static Sym> {
    CATALOG.iter().find(|s| s.id == id)
}

/// Gives off light at all.
/// What a piece is called on the plan when nobody has named it: its library
/// name, short — the unit, not what is hung on it ("Aputure 600D", not
/// "Aputure 600D with Fresnel").
pub fn plan_name(id: &str) -> String {
    let full = fso::find(id).map(|a| a.name).or_else(|| find(id).map(|s| s.name)).unwrap_or("");
    let short = full.split(" with ").next().unwrap_or(full);
    short.trim_end_matches(" Top").trim_end_matches(" Front").trim().to_string()
}

/// **A half round** (his ask, 2026-10-02): any size, always half a circle —
/// across is its diameter, deep its radius (`settle`, and an `update` that
/// sizes it) — and named on the plan by its diameter, as rentals say it.
pub const HALF_ROUND: &str = "table-half-round";

pub fn is_half_round(e: &El) -> bool {
    e.sym == HALF_ROUND
}

/// A half round's diameter, to the whole inch, as it is written inside it:
/// `60"`.
pub fn half_round_size(e: &El) -> String {
    format!("{}\"", (e.w / (super::FOOT / 12.0)).round() as i64)
}

/// A half round as a list says it: `60" Half Round`.
pub fn half_round_name(e: &El) -> String {
    format!("{} {}", half_round_size(e), find(HALF_ROUND).map(|s| s.name).unwrap_or("Half Round"))
}

pub fn emits(id: &str) -> bool {
    if let Some(a) = fso::find(id) {
        return a.role == "light" && a.beam > 0.0;
    }
    find(id).map(|s| s.light && s.beam > 0.0).unwrap_or(true)
}

/// Gives off light all round rather than forward.
pub fn omni(id: &str) -> bool {
    if let Some(a) = fso::find(id) {
        return a.beam >= 300.0;
    }
    find(id).map(|s| s.beam >= 300.0).unwrap_or(false)
}

// ---------------------------------------------------------------- the pack

/// How far a pack picture is turned to face east, the way the plan faces
/// things. The pack draws most lamps and cameras facing the top of the page,
/// some lamps the bottom or a side, and people the bottom; `fso.rs` holds
/// each one's turn, checked by eye.
fn turn(a: &fso::Art) -> f64 {
    a.turn
}

/// A quarter turn swaps a picture's width and depth on the plan.
fn quarter(a: &fso::Art) -> bool {
    (a.turn.abs() - 90.0).abs() < 1e-9
}

/// A pack picture's footprint on the plan: along the way it faces, across.
pub fn art_size(a: &fso::Art) -> (f64, f64) {
    if quarter(a) {
        (a.h, a.w)
    } else {
        (a.w, a.h)
    }
}

/// A pack picture, untouched, filling a `w` by `h` footprint about the
/// origin. His ruling, 2026-09-27: the pack as the pack drew it.
pub fn art(a: &fso::Art, w: f64, h: f64) -> Shape {
    let t = turn(a);
    let (iw, ih) = if quarter(a) { (h, w) } else { (w, h) };
    Shape {
        el: String::new(),
        part: "body",
        geom: Geom::Image { media: format!("fso:{}", a.id), x: 0.0, y: 0.0, w: iw, h: ih, rot: t },
        fill: Ink::None,
        stroke: Ink::None,
        line: 0.0,
        dash: "",
        alpha: 1.0,
        fade: None,
    }
}

/// **A lamp that reads on any fill, and shows which way it faces**
/// (SL-1334, 2026-10-01: *"Titan tubes just disappear into the frame"*).
/// Scenario's lamps are black line on a white body; the pack's pictures are
/// pale greys with no edge, so on an orange trough a tube was nothing. The
/// picture stays the pack's own, untouched: behind it a patch of paper cut
/// to its shape (`fso_outline.rs`) with an ink edge, and across its front a
/// heavy ink line — the face the light leaves by. A lamp that shines all
/// round has no front, unless it is long (a tube faces off its long side).
fn lamp(a: &fso::Art, w: f64, h: f64, pic: Shape) -> Vec<Shape> {
    let Some(rings) = super::fso_outline::find(a.id) else { return vec![pic] };
    let (iw, ih) = if quarter(a) { (h, w) } else { (w, h) };
    let (sin, cos) = turn(a).to_radians().sin_cos();
    let at = |u: f32, v: f32| {
        let (x, y) = ((u as f64 - 0.5) * iw, (v as f64 - 0.5) * ih);
        (x * cos - y * sin, x * sin + y * cos)
    };
    let pts: Vec<Vec<(f64, f64)>> = rings.iter().map(|r| r.iter().map(|&(u, v)| at(u, v)).collect()).collect();
    let mut out: Vec<Shape> = Vec::new();
    for r in &pts {
        let mut s = shape(poly(r, true), Ink::Role("paper"), Ink::Role("ink"), 0.9);
        s.part = "body";
        out.push(s);
    }
    out.push(pic);
    if faces(a, w, h) {
        let front = pts.iter().flatten().map(|p| p.0).fold(f64::MIN, f64::max);
        let near = front - (w * 0.06).max(0.004);
        let ys: Vec<f64> = pts.iter().flatten().filter(|p| p.0 >= near).map(|p| p.1).collect();
        let (y0, y1) = ys.iter().fold((f64::MAX, f64::MIN), |(lo, hi), y| (lo.min(*y), hi.max(*y)));
        if y1 > y0 {
            let mut s = shape(line(front, y0, front, y1), Ink::None, Ink::Role("ink"), 2.6);
            s.part = "front";
            out.push(s);
        }
    }
    out
}

/// Whether a lamp has a front to mark: it gives light, and either throws it
/// forward or is long enough that its long side is its face.
pub fn faces(a: &fso::Art, w: f64, h: f64) -> bool {
    a.role == "light" && a.beam > 0.0 && (a.beam < 300.0 || h > w * 2.5)
}

/// The pack's picture fitted inside a footprint without being squashed —
/// for a camera or a person, whose size is the thing's own.
fn art_fit(a: &fso::Art, w: f64, h: f64) -> Shape {
    let (aw, ah) = art_size(a);
    let k = (w / aw).min(h / ah);
    art(a, aw * k, ah * k)
}

/// The default camera body: what a camera with no `sym` shows.
pub const DEFAULT_BODY: &str = "fso-arri-alexa-mini";

/// The camera bodies a camera can show, in the pack's order: id and name.
pub fn camera_bodies() -> Vec<(&'static str, &'static str)> {
    fso::ART.iter().filter(|a| a.role == "camera").map(|a| (a.id, a.name)).collect()
}

/// A camera's body: the pack camera `body` names (`render::camera_optics`
/// decides which), else the pack's Alexa Mini.
pub fn camera_body(e: &El, body: &str) -> Vec<Shape> {
    let a = fso::find(body).filter(|a| a.role == "camera").or_else(|| fso::find(DEFAULT_BODY));
    match a {
        Some(a) => vec![art_fit(a, e.w, e.h)],
        None => camera(e.w, e.h, Ink::Role("cam")),
    }
}

/// A person in the pack's pose, sized by the shoulders (`h`, across), so a
/// person stays a person whatever their footprint says. Lying is not in the
/// pack; that one is drawn.
pub fn person_art(pose: &str, shoulders: f64) -> Option<Shape> {
    let a = fso::ART.iter().find(|a| a.role == "person" && a.pose == if pose.is_empty() { "standing" } else { pose })?;
    let (aw, ah) = art_size(a);
    let k = shoulders / ah;
    Some(art(a, aw * k, ah * k))
}

// ---------------------------------------------------------------- drawing

fn body(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("set"), Ink::Role("setline"), 1.0)
}
fn soft(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("setsoft"), Ink::Role("setline"), 0.8)
}
fn detail(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::None, Ink::Role("setink"), 0.8)
}
fn solid(segs: Vec<Seg>, role: &'static str) -> Shape {
    shape(segs, Ink::Role(role), Ink::None, 0.0)
}
fn shape(segs: Vec<Seg>, fill: Ink, stroke: Ink, line_w: f64) -> Shape {
    Shape {
        el: String::new(),
        part: "body",
        geom: Geom::Path(segs),
        fill,
        stroke,
        line: line_w,
        dash: "",
        alpha: 1.0,
        fade: None,
    }
}

/// A cinema camera from above, facing east, after the Film Set Objects
/// pack: the body with its handle, the eyepiece on the operator's side, the
/// lens with its focus rings and the matte box — all in the shot's colour,
/// the detail picked out in the paper's.
pub fn camera(w: f64, h: f64, ink: Ink) -> Vec<Shape> {
    let (hw, hh) = (w / 2.0, h / 2.0);
    let body_end = -hw + w * 0.46;
    let lens_end = hw - w * 0.2;
    let paper = || Ink::Role("paper");
    let mut out = Vec::new();
    // The eyepiece on its arm, off the camera's left side.
    out.push(shape(rrect(-hw + w * 0.06, -hh, w * 0.2, h * 0.24, h * 0.06), ink.clone(), Ink::None, 0.0));
    out.push(shape(circle(-hw + w * 0.08, -hh + h * 0.12, h * 0.07), paper(), Ink::None, 0.0));
    // Body, and the handle along its top.
    out.push(shape(rrect(-hw, -hh * 0.62, body_end + hw, h * 0.62, h * 0.08), ink.clone(), Ink::None, 0.0));
    out.push(shape(rrect(-hw + w * 0.08, -h * 0.05, w * 0.3, h * 0.1, h * 0.04), Ink::None, paper(), 0.9));
    // Lens barrel with two focus rings.
    let mut lens = shape(rect(body_end - 0.001, -hh * 0.42, lens_end - body_end, h * 0.42), ink.clone(), Ink::None, 0.0);
    lens.alpha = 0.88;
    out.push(lens);
    for t in [0.35, 0.65] {
        let x = body_end + (lens_end - body_end) * t;
        out.push(shape(line(x, -hh * 0.42, x, hh * 0.42), Ink::None, paper(), 0.9));
    }
    // The matte box, opening forward.
    out.push(shape(poly(&[(lens_end, -hh * 0.5), (hw, -hh), (hw, hh), (lens_end, hh * 0.5)], true), ink.clone(), Ink::None, 0.0));
    out.push(shape(line(hw - w * 0.015, -hh * 0.85, hw - w * 0.015, hh * 0.85), Ink::None, paper(), 1.0));
    out
}

/// A drawing by name, fitted to `w` × `h`. An unknown name is a labelled box,
/// never nothing — a thing on the plan is always somewhere to click.
pub fn draw(id: &str, w: f64, h: f64, e: &El) -> Vec<Shape> {
    if id == super::frame::SYM {
        return super::frame::draw(e, w, h);
    }
    if let Some(a) = fso::find(id) {
        let mut s = art(a, w, h);
        // **Every lamp and bit of grip in one plain ink** (2026-09-30): the
        // pack's picture shown in its own greys, never its blues and
        // ambers, so a plan reads as one drawing. Colour is for a gel.
        if matches!(a.role, "light" | "fixture" | "grip") {
            s.fill = Ink::Role(INKED);
        }
        if matches!(a.role, "light" | "fixture") {
            return lamp(a, w, h, s);
        }
        return vec![s];
    }
    if let Some(sym) = find(id) {
        if sym.look != Look::Named {
            let v = gear::draw(sym.look, w, h);
            return if sym.light && sym.beam > 0.0 { plain(v) } else { v };
        }
    }
    let (hw, hh) = (w / 2.0, h / 2.0);
    let _ = e;
    let mut v: Vec<Shape> = Vec::new();
    match id {
        "bed" | "bed-single" | "bed-king" => {
            v.push(body(rrect(-hw, -hh, w, h, 0.05)));
            v.push(soft(rect(-hw, -hh, w, h * 0.07)));
            let pillows = if w > 1.2 { 2 } else { 1 };
            let pw = (w - 0.2) / pillows as f64 - 0.06;
            for i in 0..pillows {
                let x = -hw + 0.1 + i as f64 * (pw + 0.12);
                v.push(body(rrect(x, -hh + h * 0.1, pw, h * 0.16, 0.08)));
            }
            v.push(soft(rect(-hw, -hh + h * 0.33, w, h * 0.67)));
            v.push(detail(line(-hw, -hh + h * 0.43, hw, -hh + h * 0.43)));
        }
        "sofa" | "armchair" => {
            let arm = (w * 0.12).min(0.2);
            v.push(body(rrect(-hw, -hh, w, h, 0.08)));
            v.push(soft(rrect(-hw, -hh, w, h * 0.26, 0.06)));
            v.push(soft(rrect(-hw, -hh, arm, h, 0.06)));
            v.push(soft(rrect(hw - arm, -hh, arm, h, 0.06)));
            let inner = w - 2.0 * arm;
            let n = repeats((inner / 0.7).round(), 1);
            for i in 1..n {
                let x = -hw + arm + inner * i as f64 / n as f64;
                v.push(detail(line(x, -hh + h * 0.26, x, hh)));
            }
        }
        "sofa-l" => {
            let d = 0.92f64.min(h * 0.55);
            let outline = poly(&[(-hw, -hh), (hw, -hh), (hw, hh), (hw - d, hh), (hw - d, -hh + d), (-hw, -hh + d)], true);
            v.push(body(outline));
            v.push(soft(rect(-hw, -hh, w, d * 0.26)));
            v.push(soft(rect(hw - d * 0.26, -hh, d * 0.26, h)));
            v.push(soft(rect(-hw, -hh, 0.18, d)));
            v.push(detail(line(-hw + (w - d) / 2.0, -hh + d * 0.26, -hw + (w - d) / 2.0, -hh + d)));
            v.push(detail(line(hw - d, -hh + d, hw - d * 0.26, -hh + d)));
        }
        "chair" | "director-chair" => {
            v.push(body(rrect(-hw, -hh + h * 0.18, w, h * 0.82, 0.05)));
            v.push(soft(rrect(-hw, -hh, w, h * 0.22, 0.05)));
            if id == "director-chair" {
                v.push(detail(line(-hw, -hh + h * 0.2, hw, hh)));
                v.push(detail(line(hw, -hh + h * 0.2, -hw, hh)));
            }
        }
        "stool" => {
            v.push(body(ellipse(0.0, 0.0, hw, hh)));
            v.push(detail(ellipse(0.0, 0.0, hw * 0.6, hh * 0.6)));
        }
        "table" | "desk" | "coffee-table" => {
            v.push(body(rrect(-hw, -hh, w, h, 0.03)));
            if id == "coffee-table" {
                v.push(detail(rrect(-hw + 0.06, -hh + 0.06, w - 0.12, h - 0.12, 0.02)));
            }
            if id == "desk" {
                v.push(soft(rect(-w * 0.2, -hh + 0.06, w * 0.4, 0.05)));
            }
        }
        "table-round" => v.push(body(ellipse(0.0, 0.0, hw, hh))),
        "dining" => {
            let (tw, th) = (w - 0.9, h - 0.9);
            let per = repeats((tw / 0.6).floor(), 1);
            for i in 0..per {
                let x = -tw / 2.0 + tw * (i as f64 + 0.5) / per as f64;
                v.push(soft(rrect(x - 0.21, -hh, 0.42, 0.4, 0.04)));
                v.push(soft(rrect(x - 0.21, hh - 0.4, 0.42, 0.4, 0.04)));
            }
            v.push(soft(rrect(-hw, -0.21, 0.4, 0.42, 0.04)));
            v.push(soft(rrect(hw - 0.4, -0.21, 0.4, 0.42, 0.04)));
            v.push(body(rrect(-tw / 2.0, -th / 2.0, tw, th, 0.03)));
        }
        "nightstand" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, hh - h * 0.25, hw, hh - h * 0.25)));
        }
        "dresser" | "cabinet" => {
            v.push(body(rect(-hw, -hh, w, h)));
            let n = repeats((w / 0.45).round(), 1);
            for i in 1..n {
                let x = -hw + w * i as f64 / n as f64;
                v.push(detail(line(x, -hh, x, hh)));
            }
            v.push(detail(line(-hw, hh - 0.05, hw, hh - 0.05)));
        }
        "wardrobe" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(0.0, -hh, 0.0, hh)));
            let mut rail = detail(line(-hw + 0.08, 0.0, hw - 0.08, 0.0));
            rail.dash = "dash";
            v.push(rail);
        }
        "bookshelf" => {
            v.push(body(rect(-hw, -hh, w, h)));
            let n = repeats((w / 0.3).round(), 1);
            for i in 0..n {
                let x = -hw + 0.03 + (w - 0.06) * i as f64 / n as f64;
                v.push(soft(rect(x, -hh + 0.04, (w - 0.06) / n as f64 - 0.02, h * 0.7)));
            }
        }
        "tv" | "screen" => {
            v.push(solid(rect(-hw, -hh, w, h * 0.45), "screen"));
            v.push(detail(rect(-w * 0.12, -hh + h * 0.45, w * 0.24, h * 0.55)));
        }
        "piano" => {
            v.push(body(rrect(-hw, -hh, w, h, 0.03)));
            v.push(soft(rect(-hw + 0.05, hh - h * 0.35, w - 0.1, h * 0.25)));
            let keys = 26;
            for i in 1..keys {
                let x = -hw + 0.05 + (w - 0.1) * i as f64 / keys as f64;
                v.push(detail(line(x, hh - h * 0.35, x, hh - h * 0.1)));
            }
        }
        "rug" => {
            let mut r = soft(rect(-hw, -hh, w, h));
            r.fill = Ink::Role("rug");
            v.push(r);
            let mut edge = detail(rect(-hw + 0.1, -hh + 0.1, w - 0.2, h - 0.2));
            edge.dash = "dot";
            v.push(edge);
        }
        "counter" | "island" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, hh - 0.06, hw, hh - 0.06)));
            if id == "island" {
                v.push(detail(rect(-hw + 0.08, -hh + 0.08, w - 0.16, h - 0.16)));
            }
        }
        "fridge" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, hh - h * 0.12, hw, hh - h * 0.12)));
            v.push(soft(rect(hw - w * 0.18, hh - h * 0.1, w * 0.1, h * 0.06)));
        }
        "stove" => {
            v.push(body(rect(-hw, -hh, w, h)));
            for (x, y) in [(-0.25, -0.22), (0.25, -0.22), (-0.25, 0.22), (0.25, 0.22)] {
                v.push(detail(circle(x * w, y * h * 1.4, w.min(h) * 0.16)));
            }
        }
        "sink" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(soft(rrect(-hw + w * 0.12, -hh + h * 0.25, w * 0.76, h * 0.65, 0.08)));
            v.push(detail(circle(0.0, -hh + h * 0.13, 0.03)));
        }
        "toilet" => {
            v.push(body(rrect(-hw, -hh, w, h * 0.3, 0.03)));
            v.push(body(ellipse(0.0, -hh + h * 0.62, hw * 0.92, h * 0.36)));
            v.push(detail(ellipse(0.0, -hh + h * 0.64, hw * 0.6, h * 0.25)));
        }
        "bathtub" => {
            v.push(body(rrect(-hw, -hh, w, h, 0.08)));
            v.push(soft(rrect(-hw + 0.08, -hh + 0.08, w - 0.16, h - 0.16, 0.25)));
            v.push(detail(circle(hw - 0.22, 0.0, 0.035)));
        }
        "shower" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, -hh, hw, hh)));
            v.push(detail(line(hw, -hh, -hw, hh)));
            v.push(soft(circle(0.0, 0.0, 0.05)));
        }
        "bar" => {
            v.push(body(rect(-hw, -hh, w, h * 0.5)));
            let n = repeats((w / 0.6).floor(), 1);
            for i in 0..n {
                let x = -hw + w * (i as f64 + 0.5) / n as f64;
                v.push(soft(circle(x, -hh + h * 0.78, (h * 0.18).min(0.2))));
            }
        }
        "stairs" => {
            v.push(body(rect(-hw, -hh, w, h)));
            let steps = repeats((h / 0.28).floor(), 2);
            for i in 1..steps {
                let y = -hh + h * i as f64 / steps as f64;
                v.push(detail(line(-hw, y, hw, y)));
            }
            v.push(detail(line(0.0, hh - 0.2, 0.0, -hh + 0.25)));
            v.push(detail(poly(&[(-0.12, -hh + 0.4), (0.0, -hh + 0.25), (0.12, -hh + 0.4)], false)));
        }
        "column" => v.push(solid(ellipse(0.0, 0.0, hw, hh), "wall")),
        "fireplace" => {
            v.push(soft(rect(-hw, -hh, w, h)));
            v.push(body(poly(&[(-hw * 0.6, hh), (-hw * 0.4, -hh + h * 0.3), (hw * 0.4, -hh + h * 0.3), (hw * 0.6, hh)], true)));
        }
        "elevator" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, -hh, hw, hh)));
            v.push(detail(line(hw, -hh, -hw, hh)));
            v.push(soft(rect(-w * 0.3, hh - 0.06, w * 0.6, 0.06)));
        }
        "car" | "suv" | "van" => {
            let r = h * 0.2;
            for (x, y) in [(-hw * 0.62, -hh), (hw * 0.62, -hh), (-hw * 0.62, hh), (hw * 0.62, hh)] {
                v.push(solid(rrect(x - w * 0.08, y - h * 0.07, w * 0.16, h * 0.14, 0.04), "tyre"));
            }
            let mut car = body(rrect(-hw, -hh, w, h, r));
            car.fill = Ink::Role("vehicle");
            v.push(car);
            let (front, back) = match id {
                "van" => (hw - w * 0.12, -hw + w * 0.04),
                "suv" => (hw - w * 0.24, -hw + w * 0.1),
                _ => (hw - w * 0.3, -hw + w * 0.2),
            };
            // Windscreen, roof, rear window.
            v.push(soft(poly(&[(front, -hh * 0.78), (front + w * 0.12, -hh * 0.85), (front + w * 0.12, hh * 0.85), (front, hh * 0.78)], true)));
            v.push(body(rrect(back, -hh * 0.78, front - back, h * 0.78, 0.08)));
            if id != "van" {
                v.push(soft(poly(&[(back, -hh * 0.72), (back - w * 0.07, -hh * 0.78), (back - w * 0.07, hh * 0.78), (back, hh * 0.72)], true)));
            }
            for y in [-hh - 0.08, hh + 0.08] {
                v.push(solid(ellipse(front + w * 0.03, y, 0.07, 0.05), "vehicle"));
            }
        }
        "truck" | "bus" => {
            let mut b = body(rrect(-hw, -hh, w, h, 0.12));
            b.fill = Ink::Role("vehicle");
            if id == "truck" {
                let cab = w * 0.25;
                v.push(solid(rrect(-hw, -hh, w - cab - 0.15, h, 0.05), "vehicle"));
                v.push(detail(rect(-hw + 0.08, -hh + 0.08, w - cab - 0.31, h - 0.16)));
                let mut c = body(rrect(hw - cab, -hh * 0.92, cab, h * 0.92, 0.2));
                c.fill = Ink::Role("vehicle");
                v.push(c);
                v.push(soft(rect(hw - cab * 0.3, -hh * 0.75, cab * 0.18, h * 0.75)));
            } else {
                v.push(b);
                v.push(soft(rect(hw - 0.5, -hh * 0.85, 0.3, h * 0.85)));
                let n = 8;
                for i in 1..n {
                    let x = -hw + (w - 0.8) * i as f64 / n as f64;
                    v.push(detail(line(x, -hh, x, -hh + 0.12)));
                    v.push(detail(line(x, hh, x, hh - 0.12)));
                }
            }
        }
        "motorbike" => {
            v.push(solid(rrect(-hw, -0.06, w * 0.2, 0.12, 0.05), "tyre"));
            v.push(solid(rrect(hw - w * 0.2, -0.06, w * 0.2, 0.12, 0.05), "tyre"));
            let mut b = body(ellipse(0.0, 0.0, hw * 0.65, hh * 0.45));
            b.fill = Ink::Role("vehicle");
            v.push(b);
            v.push(detail(line(hw * 0.55, -hh, hw * 0.55, hh)));
        }
        "bicycle" => {
            v.push(detail(line(-hw, 0.0, hw, 0.0)));
            v.push(solid(rrect(-hw, -0.03, w * 0.34, 0.06, 0.03), "tyre"));
            v.push(solid(rrect(hw - w * 0.34, -0.03, w * 0.34, 0.06, 0.03), "tyre"));
            v.push(detail(line(hw * 0.55, -hh, hw * 0.55, hh)));
            v.push(soft(ellipse(-w * 0.08, 0.0, 0.12, 0.07)));
        }
        "tree" => {
            let mut canopy = solid(ellipse(0.0, 0.0, hw, hh), "plant");
            canopy.alpha = 0.55;
            v.push(canopy);
            for i in 0..7 {
                let a = (i as f64 * 51.4f64).to_radians();
                v.push(detail(line(0.0, 0.0, a.cos() * hw * 0.8, a.sin() * hh * 0.8)));
            }
            v.push(solid(circle(0.0, 0.0, w.min(h) * 0.07), "trunk"));
        }
        "plant" => {
            for i in 0..6 {
                let a = (i as f64 * 60.0f64).to_radians();
                let mut leaf = solid(ellipse(a.cos() * hw * 0.45, a.sin() * hh * 0.45, hw * 0.42, hh * 0.42), "plant");
                leaf.alpha = 0.7;
                v.push(leaf);
            }
            v.push(body(circle(0.0, 0.0, w.min(h) * 0.22)));
        }
        "bench" => {
            v.push(body(rect(-hw, -hh, w, h)));
            for i in 1..4 {
                let y = -hh + h * i as f64 / 4.0;
                v.push(detail(line(-hw, y, hw, y)));
            }
        }
        "fence" => {
            v.push(detail(line(-hw, 0.0, hw, 0.0)));
            let n = repeats((w / 1.2).round(), 1);
            for i in 0..=n {
                let x = -hw + w * i as f64 / n as f64;
                v.push(body(rect(x - 0.05, -0.05, 0.1, 0.1)));
            }
        }
        "umbrella" => {
            let pts: Vec<(f64, f64)> = (0..8)
                .map(|i| {
                    let a = (i as f64 * 45.0f64 + 22.5).to_radians();
                    (a.cos() * hw, a.sin() * hh)
                })
                .collect();
            v.push(soft(poly(&pts, true)));
            for p in &pts {
                v.push(detail(line(0.0, 0.0, p.0, p.1)));
            }
        }
        "tent" => {
            v.push(soft(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, -hh, hw, hh)));
            v.push(detail(line(hw, -hh, -hw, hh)));
            for (x, y) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
                v.push(solid(circle(x, y, 0.06), "grip"));
            }
        }
        "c-stand" => {
            for i in 0..3 {
                let a = (i as f64 * 120.0f64 - 90.0).to_radians();
                v.push(shape(line(0.0, 0.0, a.cos() * hw, a.sin() * hh), Ink::None, Ink::Role("grip"), 1.6));
            }
            v.push(solid(circle(0.0, 0.0, 0.06), "grip"));
        }
        "apple-box" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(ellipse(-w * 0.25, 0.0, w * 0.1, h * 0.12)));
            v.push(detail(ellipse(w * 0.25, 0.0, w * 0.1, h * 0.12)));
        }
        "sandbag" => {
            let mut b = body(rrect(-hw, -hh, w, h, h * 0.4));
            b.fill = Ink::Role("setsoft");
            v.push(b);
            v.push(detail(line(0.0, -hh, 0.0, hh)));
        }
        "dolly" => {
            for (x, y) in [(-hw + 0.1, -hh), (hw - 0.1, -hh), (-hw + 0.1, hh), (hw - 0.1, hh)] {
                v.push(solid(rrect(x - 0.1, y - 0.06, 0.2, 0.12, 0.04), "tyre"));
            }
            let mut b = body(rrect(-hw, -hh, w, h, 0.06));
            b.fill = Ink::Role("setsoft");
            v.push(b);
            v.push(body(circle(w * 0.1, 0.0, h * 0.2)));
        }
        "crane" => {
            v.push(body(rrect(-hw, -hh, w * 0.3, h, 0.08)));
            let mut arm = body(poly(&[(-hw + w * 0.15, -0.12), (hw, -0.07), (hw, 0.07), (-hw + w * 0.15, 0.12)], true));
            arm.fill = Ink::Role("setsoft");
            v.push(arm);
            v.push(body(circle(-hw + w * 0.15, 0.0, h * 0.22)));
        }
        "video-village" => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(solid(rect(-w * 0.4, -hh + 0.08, w * 0.35, 0.06), "screen"));
            v.push(solid(rect(w * 0.05, -hh + 0.08, w * 0.35, 0.06), "screen"));
            for x in [-w * 0.25, w * 0.25] {
                v.push(soft(rrect(x - 0.22, hh + 0.05, 0.44, 0.4, 0.05)));
            }
        }
        "monitor" => {
            v.push(solid(rect(-hw, -hh, w, h * 0.3), "screen"));
            v.push(shape(line(0.0, -hh + h * 0.3, 0.0, hh), Ink::None, Ink::Role("grip"), 1.4));
        }
        "boom" => {
            v.push(shape(line(-hw, 0.0, hw - 0.3, 0.0), Ink::None, Ink::Role("grip"), 2.0));
            v.push(solid(rrect(hw - 0.35, -0.05, 0.35, 0.1, 0.05), "grip"));
            v.push(soft(circle(-hw + 0.25, 0.0, hh * 0.9)));
        }
        "generator" => {
            let mut b = body(rrect(-hw, -hh, w, h, 0.06));
            b.fill = Ink::Role("setsoft");
            v.push(b);
            for i in 1..8 {
                let x = -hw + w * 0.1 + w * 0.5 * i as f64 / 8.0;
                v.push(detail(line(x, -hh + 0.15, x, hh - 0.15)));
            }
        }
        "stage" | "riser" => {
            v.push(soft(rect(-hw, -hh, w, h)));
            v.push(shape(line(-hw, hh, hw, hh), Ink::None, Ink::Role("setline"), 2.0));
            if id == "riser" {
                let n = repeats(w / 0.3, 2);
                for i in 0..n {
                    let x = -hw + w * i as f64 / n as f64;
                    v.push(detail(line(x, -hh, (x + h * 0.4).min(hw), -hh + h * 0.4)));
                }
            }
        }
        "drum-kit" => {
            v.push(body(circle(0.0, h * 0.1, h * 0.26)));
            for (x, y, r) in [(-0.3, -0.2, 0.14), (0.0, -0.3, 0.13), (0.3, -0.18, 0.15), (-0.42, 0.25, 0.17), (0.42, 0.28, 0.2)] {
                v.push(body(circle(x * w, y * h, r * h)));
            }
            v.push(soft(circle(0.0, hh - 0.2, 0.18)));
        }
        "speaker" => {
            v.push(solid(rect(-hw, -hh, w, h), "screen"));
            v.push(detail(circle(0.0, 0.0, w.min(h) * 0.32)));
        }
        "mic-stand" => {
            v.push(solid(circle(0.0, 0.0, w.min(h) * 0.3), "grip"));
            v.push(shape(line(0.0, 0.0, hw, -hh), Ink::None, Ink::Role("grip"), 1.4));
            v.push(solid(circle(hw, -hh, 0.04), "grip"));
        }

        // ---- lights, facing east
        "fresnel-650" | "fresnel" | "fresnel-2k" | "fresnel-5k" | "hmi" | "hmi-4k" | "hmi-18k" | "par" | "cob" => {
            // From above: the housing, the lens across its front, the barn
            // doors standing open either side of the beam, and the yoke it
            // hangs in.
            let front = hw * 0.36;
            let body_h = h * 0.78;
            v.push(fixture(rrect(-hw, -body_h / 2.0, front + hw, body_h, (w * 0.08).min(0.05))));
            v.push(fixture_face(rect(front, -h * 0.43, w * 0.09, h * 0.86)));
            if id != "par" && id != "cob" {
                let lip = front + w * 0.09;
                v.push(fixture_line(line(lip, -h * 0.43, hw, -hh)));
                v.push(fixture_line(line(lip, h * 0.43, hw, hh)));
            }
            let yoke = -hw * 0.25;
            v.push(fixture_line(poly(&[(yoke - w * 0.12, -hh * 0.98), (yoke, -hh * 0.98), (yoke, hh * 0.98), (yoke - w * 0.12, hh * 0.98)], false)));
            if id.starts_with("hmi") {
                // A daylight head wears a second line across the housing — the
                // way it is told from a tungsten one on a plot.
                v.push(fixture_line(line(-hw * 0.72, -body_h / 2.0, -hw * 0.72, body_h / 2.0)));
            }
        }
        "followspot" => {
            v.push(fixture(rrect(-hw, -hh, w * 0.85, h, h * 0.4)));
            v.push(fixture_face(rect(hw - w * 0.15, -hh * 0.8, w * 0.12, h * 0.8)));
        }
        "panel" | "panel-l" | "mat" | "tube" | "tube-s" | "kino" => {
            v.push(fixture(rrect(-hw, -hh, w, h, (w * 0.3).min(0.03))));
            v.push(fixture_face(rect(hw - w * 0.22, -hh + 0.01, w * 0.2, h - 0.02)));
            if id == "kino" {
                for i in 1..4 {
                    let y = -hh + h * i as f64 / 4.0;
                    v.push(fixture_line(line(-hw, y, hw, y)));
                }
            }
            if id.starts_with("panel") || id == "kino" {
                v.push(fixture_line(line(-hw - 0.12, -hh * 0.6, -hw - 0.12, hh * 0.6)));
                v.push(fixture_line(line(-hw - 0.12, 0.0, -hw, 0.0)));
            }
        }
        "softbox" => {
            v.push(fixture(rect(-hw, -hh * 0.3, w * 0.25, h * 0.3)));
            v.push(fixture(poly(&[(-hw + w * 0.2, -hh * 0.35), (hw, -hh), (hw, hh), (-hw + w * 0.2, hh * 0.35)], true)));
            v.push(fixture_face(rect(hw - 0.03, -hh, 0.03, h)));
        }
        "lantern" | "china-ball" | "spacelight" => {
            let mut b = fixture(ellipse(0.0, 0.0, hw, hh));
            b.fill = Ink::Role("silk");
            v.push(b);
            v.push(fixture_line(ellipse(0.0, 0.0, hw * 0.55, hh * 0.55)));
            if id == "spacelight" {
                for i in 0..8 {
                    let a = (i as f64 * 45.0f64).to_radians();
                    v.push(fixture_line(line(a.cos() * hw * 0.55, a.sin() * hh * 0.55, a.cos() * hw, a.sin() * hh)));
                }
            }
        }
        "practical" => {
            v.push(fixture(ellipse(0.0, 0.0, hw, hh)));
            v.push(solid(ellipse(0.0, 0.0, hw * 0.45, hh * 0.45), "paper"));
        }
        "bulb" => v.push(fixture(ellipse(0.0, 0.0, hw, hh))),
        "flag" | "floppy" | "cutter" => {
            v.push(solid(rect(-hw, -hh, w, h), "grip"));
            v.push(shape(line(-hw, 0.0, -hw - 0.3, 0.0), Ink::None, Ink::Role("grip"), 1.2));
            v.push(solid(circle(-hw - 0.32, 0.0, 0.05), "grip"));
        }
        "net" => {
            let mut n = shape(rect(-hw, -hh, w, h), Ink::None, Ink::Role("grip"), 1.2);
            n.dash = "dot";
            v.push(n);
            v.push(shape(line(-hw, 0.0, -hw - 0.3, 0.0), Ink::None, Ink::Role("grip"), 1.2));
        }
        "silk" | "bounce" => {
            v.push(shape(rect(-hw, -hh, w, h), Ink::Role("silk"), Ink::Role("grip"), 1.0));
            v.push(shape(line(-hw, 0.0, -hw - 0.3, 0.0), Ink::None, Ink::Role("grip"), 1.2));
        }
        "negative" => {
            v.push(solid(rect(-hw, -hh, w, h), "screen"));
            v.push(shape(line(-hw, 0.0, -hw - 0.3, 0.0), Ink::None, Ink::Role("grip"), 1.2));
        }
        "frame-6" | "frame-8" | "frame-12" | "frame-20" => {
            let mut f = shape(rect(-hw, -hh, w, h), Ink::Role("silk"), Ink::Role("grip"), 2.0);
            f.alpha = 0.85;
            v.push(f);
            for (x, y) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
                v.push(solid(circle(x, y, 0.07), "grip"));
            }
        }
        // "box" and anything unknown
        _ => {
            v.push(body(rect(-hw, -hh, w, h)));
            v.push(detail(line(-hw, -hh, hw, hh)));
            v.push(detail(line(hw, -hh, -hw, hh)));
        }
    }
    v
}

fn fixture(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("light"), Ink::Role("lightline"), 0.9)
}
fn fixture_face(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::Role("lightface"), Ink::Role("lightline"), 0.8)
}
fn fixture_line(segs: Vec<Seg>) -> Shape {
    shape(segs, Ink::None, Ink::Role("lightline"), 1.2)
}

/// The fill a pack picture wears to be drawn in plain ink: its own light
/// and shade in greys (`svg.rs`'s `-ink` filter; `DiagramPictures.inked` on
/// the Mac).
pub const INKED: &str = "artink";

/// One of our lamps in the same plain style as the pack's: a light body,
/// the plan's grey housing and line, no amber.
fn plain(v: Vec<Shape>) -> Vec<Shape> {
    v.into_iter()
        .map(|mut s| {
            s.fill = match s.fill {
                Ink::Role("light") | Ink::Role("lightface") => Ink::Role("silk"),
                Ink::Hex(..) => Ink::Role("fixture"),
                other => other,
            };
            s.stroke = match s.stroke {
                Ink::Role("lightline") => Ink::Role("fixtureline"),
                Ink::Hex(..) => Ink::Role("fixtureline"),
                other => other,
            };
            s
        })
        .collect()
}

/// Drawings a named one has replaced in the library. Plans that hold them
/// still draw them; they are only no longer offered.
const RETIRED: &[&str] = &[
    "flag", "net", "silk", "floppy", "frame-6", "frame-8", "frame-12", "frame-20",
    // 2026-10-01, doubles in the library: the Frame is any size and skin,
    // "Practical" was listed twice, and the plain Fresnel is the 1K's drawing
    // at the 1K's size.
    "generic-frame", "practical", "generic-fresnel",
    // A flag is a small Frame with a Solid skin.
    "generic-flag",
];

/// Our own drawings of things the Film Set Objects pack has: out of the
/// library since 2026-09-27, when he chose the pack's pictures over our
/// redraws. A plan that already holds one still draws it.
const PACKED: &[&str] = &[
    "seamless-white", "seamless-black", "seamless-grey", "seamless-green", "seamless-navy", "seamless-pink", "seamless-brown",
    "cyc-white", "cyc-white-l", "cyc-green", "cyc-green-l", "car", "truck", "monitor", "projector", "boom", "easy-cart", "hazer",
    "fan", "tree", "hedge", "stump", "sidewalk", "lamp-shade", "flashlight", "bulb", "combo-stand", "crank-stand", "sticks",
    "sticks-light", "polecat-4", "polecat-6", "polecat-8", "bed", "bed-one", "bed-two", "sofa", "loveseat", "armchair", "chair",
    "office-chair", "table", "table-square", "table-round", "table-round-l", "generator", "tow-generator", "distro-400",
    "lunch-box", "gang-box", "crafty", "canopy", "cone",
    // 2026-10-01: the pack has these too, at the same size.
    "street-sodium", "street-mercury", "wall-light", "generator-portable", "tent", "side-table",
    // Plain stand-ins the pack has unbranded: its China Ball, Ellipsoidal and
    // Spacelight at the same size, its Small Softbox within a few cm.
    "generic-china-ball", "generic-ellipsoidal", "generic-spacelight", "generic-softbox",
];
/// Whole groups of ours the pack covers.
const PACKED_GROUPS: &[&str] = &[
    "Tungsten", "HMI", "LED", "LED Panels", "Mats & Tubes", "Soft", "Flags & Nets", "Boards", "Rags 6×6", "Rags 8×8",
    "Rags 12×12", "Rags 20×20", "Rags 12×20", "Track & Rail", "Dollies & Cranes",
];

/// A pack picture in the library: not a camera or a person (their tools
/// draw them), and not a rag or flag the Frame makes (2026-10-01, his call:
/// "cut the extras that the frame tool covers"). Plans that hold one still
/// draw it.
fn offered_art(a: &fso::Art) -> bool {
    a.role != "camera" && a.role != "person" && super::frame::stand_in(a).is_none()
}

/// In the library: not retired, and not something the pack draws.
fn listed(s: &Sym) -> bool {
    !RETIRED.contains(&s.id) && !PACKED.contains(&s.id) && !PACKED_GROUPS.contains(&s.group)
}

/// The catalogue as JSON, for a shell's library panel: the pack first, as
/// the pack names and groups it, then our own drawings of what it lacks.
/// Cameras and people are not here — the camera and cast tools draw them.
pub fn catalog_json() -> String {
    let mut j = crate::jsonw::Json::new();
    j.arr();
    let mut ours: Vec<&Sym> = CATALOG.iter().filter(|s| listed(s)).collect();
    // The plain stand-ins lead the lights, ahead of the pack's named units.
    ours.sort_by_key(|s| s.group != "Generic");
    for s in ours.iter().filter(|s| s.group == "Generic") {
        sym_json(&mut j, s);
    }
    for a in fso::ART.iter().filter(|a| offered_art(a)) {
        let (w, h) = art_size(a);
        let p = library::of_art(a);
        j.obj()
            .kv("id", a.id)
            .kv("name", a.name)
            .kv("group", a.group)
            .kb("light", matches!(a.role, "light" | "fixture" | "grip"))
            .kn("w", (w * 1000.0).round() / 1000.0)
            .kn("h", (h * 1000.0).round() / 1000.0)
            .kn("beam", a.beam)
            .kn("reach", a.reach)
            .kn("kelvin", a.kelvin)
            .kv("lib", p.lib)
            .kv("kind", p.kind)
            .kv("maker", p.maker)
            .kv("aka", &p.aka)
            .end_obj();
    }
    for s in ours.iter().filter(|s| s.group != "Generic") {
        sym_json(&mut j, s);
    }
    j.end_arr();
    j.finish()
}

fn sym_json(j: &mut crate::jsonw::Json, s: &Sym) {
    let p = library::of_sym(s);
    j.obj()
        .kv("id", s.id)
        .kv("name", s.name)
        .kv("group", s.group)
        .kb("light", s.light)
        .kn("w", s.w)
        .kn("h", s.h)
        .kn("beam", s.beam)
        .kn("reach", s.reach)
        .kn("kelvin", s.kelvin)
        .kv("lib", p.lib)
        .kv("kind", p.kind)
        .kv("maker", p.maker)
        .kv("aka", &p.aka)
        .end_obj();
}

/// Every piece the library offers, with where it sits — for a search that
/// is not the Mac's panel (the connector's `diagram_library`).
pub fn offered() -> Vec<(&'static str, &'static str, &'static str, f64, f64, library::Place)> {
    let mut out = Vec::new();
    let mut ours: Vec<&Sym> = CATALOG.iter().filter(|s| listed(s)).collect();
    ours.sort_by_key(|s| s.group != "Generic");
    for s in &ours {
        out.push((s.id, s.name, s.group, s.w, s.h, library::of_sym(s)));
    }
    for a in fso::ART.iter().filter(|a| offered_art(a)) {
        let (w, h) = art_size(a);
        out.push((a.id, a.name, a.group, w, h, library::of_art(a)));
    }
    out
}

/// How many times a repeated part — a cushion, a chair, a shelf, a step —
/// is drawn: at least `least`, and never more than sixty, which no real
/// piece reaches (sixty seats is eighteen metres of sofa). A piece stretched
/// by a slip to a kilometre would otherwise draw a hundred thousand of them.
fn repeats(n: f64, least: usize) -> usize {
    if n.is_finite() { (n.max(0.0) as usize).clamp(least, 60) } else { least }
}
