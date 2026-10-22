//! The diagram: an overhead of one scene.
//!
//! Walls, set pieces, cameras, cast, lights, arrows and words on a floor plan —
//! the thing Cadrage calls a Diagram and OpenShotDesigner calls a floor plan.
//! His ruling of 2026-08-23 made it a *mode* of the program; his answers of
//! 2026-09-26 settled three things this module keeps:
//!
//! - **A camera's colour is set by hand**, usually one per shot. A project's
//!   accent colour never touches it.
//! - **A camera is a shot** when it is linked to one: it reads the shot's lens,
//!   its number and its fields. Unlinked, it is only a camera.
//! - **The portal only looks.** Every edit is made here, by the Mac.
//!
//! **Why all of it is in the engine.** The law is that the engine is the truth
//! and hands back something to draw. For a diagram that means the engine works
//! out every line — a lens's cone from its focal length and the sensor, a door's
//! swing, a dolly track's rails, a beat's ghost — and hands back a list of
//! shapes (`render.rs`). The Mac paints that list; the portal and paper get the
//! same list written as SVG (`svg.rs`). Nothing is drawn two different ways, so
//! the three cannot disagree about where a camera stands.
//!
//! Everything is in **metres**, like the scanned room it may start from; feet
//! and inches happen at the edge, where a number is written. Angles are in
//! degrees, **clockwise from east**, because the page's y grows downward.
//!
//! A diagram is stored whole, as one JSON document per scene, and the last
//! writer wins (`design/DECISIONS.md`, 2026-08-17: *"a drawing is one person's
//! hand; merging strokes is complexity with no customer"*).

pub mod copy;
pub mod frame;
pub mod fso;
pub mod fso_outline;
pub mod gear;
pub mod gels;
pub mod lampscale;
pub mod lens;
pub mod levels;
pub mod library;
pub mod output;
pub mod photomarks;
pub mod plans;
pub mod plot;
pub mod portal;
pub mod print;
pub mod favorites;
pub mod render;
pub mod rigging;
pub mod scenediagrams;
pub mod shade;
pub mod sheet;
pub mod stored;
pub mod sun;
pub mod svg;
pub mod symbols;
pub mod walls;
pub mod wire;

/// **Set, then Plot** (Back to Paper, Batch 3, Ref 1498): the two layers a
/// plan is drawn in. The set is the room laid once — walls, doors, windows,
/// openings, the street, set pieces (rooms, buildings, areas, stairs,
/// furniture, vehicles, props), a floor plan picture or a room scan to trace
/// over. The plot is what the DP puts on it — lamps, frames and grip,
/// cameras, cast, words, arrows and connectors, track, rulers and drawn lines.
/// A shape and a closed, filled drawn path (an Object) are furniture, so set.
/// **Cast is plot, but works in either**: the screens never lock or fade a
/// person (his ask, 2026-10-06: actors belong in Set too). Where a kind is
/// unclear it goes where a DP would look for it:
/// a set piece from the library's Camera Support (dolly, slider, crane) or
/// Electric (distro, generator), or any grip, is plot; a photo laid on top
/// of the plan is plot, a picture under it is set. Nothing is stored: a
/// piece's layer is its kind, so old plans open untouched.
pub fn layer(e: &El) -> &'static str {
    // Sent to the other view by hand.
    if can_send(e) {
        match e.on_layer.as_str() {
            SET_LAYER => return SET_LAYER,
            PLOT_LAYER => return PLOT_LAYER,
            _ => {}
        }
    }
    kind_layer(e)
}

/// **What can go to the other view** (Send to Set / Send to Plot, his ask
/// 2026-10-17): everything but the room's own bones — walls, doors,
/// windows, openings and the street stay in Set — and a person, who is in
/// both already.
pub fn can_send(e: &El) -> bool {
    !matches!(e.kind, Kind::Wall | Kind::Door | Kind::Window | Kind::Opening | Kind::Road | Kind::Cast)
}

/// Put a piece in `to` (`set` or `plot`): words, arrows and notes by
/// `in_set`, anything else by `on_layer`, which is cleared when `to` is its
/// kind's own.
pub fn send_to(e: &mut El, to: &str) {
    if !can_send(e) {
        return;
    }
    e.on_layer.clear();
    if matches!(e.kind, Kind::Text | Kind::Arrow | Kind::Note) {
        e.in_set = to == SET_LAYER;
    }
    if kind_layer(e) != to {
        e.on_layer = to.to_string();
    }
}

/// The layer a piece's kind puts it in.
fn kind_layer(e: &El) -> &'static str {
    match e.kind {
        Kind::Wall | Kind::Door | Kind::Window | Kind::Opening | Kind::Road => SET_LAYER,
        // His ask, 2026-10-07: a rectangle drawn as a table is furniture. A
        // shape, and a drawn path closed and filled (Draw › Object), are set;
        // an open line or an outline stays plot.
        Kind::Shape => SET_LAYER,
        Kind::Stroke if e.fill && walls::closed(e) => SET_LAYER,
        Kind::Image if e.role == "photo" => PLOT_LAYER,
        Kind::Image => SET_LAYER,
        // Words and arrows go where they were made: either view can place them.
        Kind::Text | Kind::Arrow | Kind::Note if e.in_set => SET_LAYER,
        Kind::Set => {
            let place = symbols::find(&e.sym).map(library::of_sym).or_else(|| fso::find(&e.sym).map(library::of_art));
            match place {
                Some(p) if p.lib != library::SET || matches!(p.kind, "Camera Support" | "Electric") => PLOT_LAYER,
                _ => SET_LAYER,
            }
        }
        _ => PLOT_LAYER,
    }
}
pub const SET_LAYER: &str = "set";
pub const PLOT_LAYER: &str = "plot";

use crate::json::{self, Json};

// ---------------------------------------------------------------- the model

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Wall,
    Door,
    Window,
    Opening,
    Set,
    Camera,
    Cast,
    Light,
    Track,
    Road,
    Text,
    Measure,
    Arrow,
    Shape,
    Cable,
    Stroke,
    Image,
    Note,
}

impl Kind {
    pub const ALL: [Kind; 18] = [
        Kind::Wall,
        Kind::Door,
        Kind::Window,
        Kind::Opening,
        Kind::Set,
        Kind::Camera,
        Kind::Cast,
        Kind::Light,
        Kind::Track,
        Kind::Road,
        Kind::Text,
        Kind::Measure,
        Kind::Arrow,
        Kind::Shape,
        Kind::Cable,
        Kind::Stroke,
        Kind::Image,
        Kind::Note,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Wall => "wall",
            Kind::Door => "door",
            Kind::Window => "window",
            Kind::Opening => "opening",
            Kind::Set => "set",
            Kind::Camera => "camera",
            Kind::Cast => "cast",
            Kind::Light => "light",
            Kind::Track => "track",
            Kind::Road => "road",
            Kind::Text => "text",
            Kind::Measure => "measure",
            Kind::Arrow => "arrow",
            Kind::Shape => "shape",
            Kind::Cable => "cable",
            Kind::Stroke => "stroke",
            Kind::Image => "image",
            Kind::Note => "note",
        }
    }

    pub fn parse(s: &str) -> Option<Kind> {
        Kind::ALL.iter().copied().find(|k| k.as_str() == s)
    }

    /// Drawn from one end to the other rather than placed and turned.
    pub fn is_line(self) -> bool {
        matches!(
            self,
            Kind::Wall | Kind::Track | Kind::Road | Kind::Measure | Kind::Arrow
        )
    }

    /// Drawn as a run of points.
    pub fn is_polyline(self) -> bool {
        matches!(self, Kind::Cable | Kind::Stroke)
    }

    /// Sits in a wall.
    pub fn is_opening(self) -> bool {
        matches!(self, Kind::Door | Kind::Window | Kind::Opening)
    }

    /// Can walk: has beats.
    pub fn moves(self) -> bool {
        matches!(self, Kind::Camera | Kind::Cast | Kind::Light | Kind::Set)
    }

    /// Where it sits in the stack when nobody has said otherwise: the floor
    /// first, then the room, then what stands in it, then words on top.
    pub fn tier(self) -> u8 {
        match self {
            Kind::Image => 0,
            Kind::Road | Kind::Shape => 1,
            Kind::Set | Kind::Track | Kind::Stroke | Kind::Cable => 2,
            Kind::Wall | Kind::Door | Kind::Window | Kind::Opening => 3,
            Kind::Light | Kind::Cast | Kind::Camera => 4,
            Kind::Arrow | Kind::Measure | Kind::Text | Kind::Note => 5,
        }
    }
}

/// **One step a thing takes** — his ruling of 2026-10-01: *"I can add as many
/// steps as I want any object to take. Sometimes A and B could go up to Z, or
/// pass Z… then I would assign those different things manually to different
/// beats, so I could animate the sequence."* A move or a turn is not a preset
/// pair; every one he adds is the next step, lettered as it comes (`letter`),
/// and played on whichever beat he puts it on.
///
/// The thing's own `x`, `y`, `rot` is one of its steps too — the solid one,
/// where it stands outside Beats — and `El::lead` says how many steps come
/// before it (a Move From puts one there). The rest are drawn as ghosts.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Step {
    pub x: f64,
    pub y: f64,
    pub rot: f64,
    /// Cast only: how they are at this step, when it differs — lying in bed
    /// at the start, standing by the door at the end. Empty keeps the pose
    /// they had.
    pub pose: Pose,
    /// **A turn** (his note, 2026-09-29: "turn to/from"): it stays where the
    /// step before it stands — the one after, for a first step — and only
    /// turns. `x`/`y` are kept on that spot (`El::tame`), so it follows.
    pub turn: bool,
    /// The beat it plays on. Nought is none: a step kept on the plan and not
    /// played (every move made before steps had beats comes in so).
    pub beat: u32,
}

impl Step {
    fn to_json(self, full: bool) -> Json {
        let mut o = vec![
            ("x".into(), Json::Number(round(self.x))),
            ("y".into(), Json::Number(round(self.y))),
            ("rot".into(), Json::Number(round(self.rot))),
            ("beat".into(), Json::Number(self.beat as f64)),
        ];
        if full || self.pose != Pose::Same {
            o.push(("pose".into(), Json::text(self.pose.as_str())));
        }
        if full || self.turn {
            o.push(("turn".into(), Json::Bool(self.turn)));
        }
        Json::Object(o)
    }

    fn from_json(v: &Json, rot: f64) -> Option<Step> {
        let n = |k: &str| v.get(k).and_then(|x| x.as_f64()).filter(|x| x.is_finite());
        Some(Step {
            x: n("x")?,
            y: n("y")?,
            rot: n("rot").unwrap_or(rot),
            pose: Pose::parse(v.get("pose").and_then(|x| x.as_str()).unwrap_or("")),
            turn: v.get("turn").and_then(|t| t.as_bool()) == Some(true),
            beat: n("beat").map(|b| b.max(0.0) as u32).unwrap_or(0),
        })
    }
}

/// **A step's letter**: A to Z, then AA, AB… on past ZZ, as far as he goes.
pub fn letter(i: usize) -> String {
    let mut n = i + 1;
    let mut out = Vec::new();
    while n > 0 {
        n -= 1;
        out.push((b'A' + (n % 26) as u8) as char);
        n /= 26;
    }
    out.iter().rev().collect()
}

/// One step as the plan shows it, in letter order: the thing itself
/// (`home`) among its ghosts.
#[derive(Clone, Debug, PartialEq)]
pub struct Spot {
    pub x: f64,
    pub y: f64,
    pub rot: f64,
    pub beat: u32,
    pub pose: Pose,
    pub turn: bool,
    pub home: bool,
}

/// How a person is: standing, seated or lying. Stored as a word.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Pose {
    #[default]
    Same,
    Standing,
    Seated,
    Lying,
}

impl Pose {
    pub fn parse(s: &str) -> Pose {
        match s {
            "standing" => Pose::Standing,
            "seated" => Pose::Seated,
            "lying" => Pose::Lying,
            _ => Pose::Same,
        }
    }
    pub fn as_str(self) -> &'static str {
        match self {
            Pose::Same => "",
            Pose::Standing => "standing",
            Pose::Seated => "seated",
            Pose::Lying => "lying",
        }
    }
}

/// Anything on the plan. One shape for every kind, the way a spreadsheet row
/// has every column: a field a kind does not use stays at its default and is
/// never written out. That keeps a patch (`update`) a plain merge of keys.
#[derive(Clone, Debug, PartialEq)]
pub struct El {
    pub id: String,
    pub kind: Kind,
    /// Its middle, or — for a line — where it starts.
    pub x: f64,
    pub y: f64,
    /// Where a line ends.
    pub x2: f64,
    pub y2: f64,
    /// Degrees clockwise from east.
    pub rot: f64,
    /// Its footprint, before turning: length along `rot`, and depth across it.
    pub w: f64,
    pub h: f64,
    /// A line's bend: how far its middle is pushed sideways, in metres.
    pub curve: f64,
    /// A wall's thickness, a road's width.
    pub thick: f64,
    /// A wall that runs back to its first corner (`walls.rs`).
    pub closed: bool,
    /// A wall's rounded corners, by their place in `points`.
    pub round: Vec<usize>,
    /// **Smooth points** (his ask, 2026-10-02): for each corner of a wall or a
    /// drawn path, `[in_dx, in_dy, out_dx, out_dy]` — where the two curve
    /// handles sit, as offsets from the corner. All nought is a sharp corner;
    /// empty means no corner of it is smooth. A stretch with a handle at
    /// either end is a curve (`walls::run`).
    pub handles: Vec<[f64; 4]>,
    pub label: String,
    /// A frame's Name as typed, for a few hours on 2026-10-05; then his
    /// rule became size and cloth on the first line (`render::frame_lines`).
    /// Kept, not drawn.
    pub title: String,
    /// **Any piece's Note** (his note, 2026-10-05: *"alll items should be
    /// able to have a note"*): written under its name in grey. A lamp's and
    /// a frame's Note is their `label`.
    pub caption: String,
    /// **Marks drawn on a picture** (his ask, 2026-10-15: annotate photos to
    /// show perspective): arrows, lines, boxes, ovals, drawing and words, as
    /// fractions of the picture, so they move and size with it
    /// (`photomarks`). Empty on anything else.
    pub marks: String,
    /// **A picture's perspective helper**: `<horizon y>:<vanishing x>`,
    /// fractions of the picture; empty is off (`photomarks::Perspective`).
    pub perspective: String,
    /// `#rrggbb`, or empty for the kind's own ink.
    pub color: String,
    pub fill: bool,
    /// What a closed path or room is filled with: `#rrggbb`, `auto` for the
    /// plan's own tint, or empty. A drawn path is also filled when `fill` is on.
    pub fill_color: String,
    /// How solid that fill is, 0–1; nought is the fill's own (a tint is light,
    /// a colour firmer).
    pub fill_alpha: f64,
    pub dash: String,
    /// A stroke's weight in points at 100%.
    pub weight: f64,
    pub opacity: f64,
    pub locked: bool,
    pub hidden: bool,
    pub group: String,
    /// The group's name, carried by every member ("Group 2" until renamed).
    pub group_name: String,
    pub note: String,
    /// Which drawing, from `symbols.rs`: `bed`, `fresnel`, `sofa`…
    pub sym: String,

    // a camera
    pub shot: String,
    /// Millimetres. Zero reads the linked shot's Lens.
    pub lens: f64,
    /// A generic sensor key (`lens::SENSORS`) an older plan chose. Read only
    /// while the camera has no film camera with a sensor of its own.
    pub sensor: String,
    /// For a camera with no shot: which of the film's cameras it is (a unit
    /// id) and a lens off the film's Lens list (`Tribe7 Blackwings 50`), read
    /// as a shot's are. A camera with a shot reads both off the shot.
    pub unit: String,
    pub lens_name: String,
    /// How far the cone reaches, in metres.
    pub reach: f64,
    pub cone: bool,
    pub height: String,
    pub rig: String,

    // cast
    pub cast: String,
    pub pose: String,

    // a light
    pub kelvin: f64,
    /// The beam's full spread, in degrees.
    pub beam: f64,
    pub beam_on: bool,
    /// The dimmer, 0–100 per cent: how much of the unit's output it gives.
    pub dim: f64,
    /// **How many times its page size a lamp's mark is drawn** (his note,
    /// 2026-10-17: lamps size up when he scales them). 1 as put down; a
    /// resize of the lamp multiplies it (`lampscale`).
    pub mark_k: f64,
    pub role: String,

    // a door
    pub swing: f64,
    pub hinge: String,
    pub flip: bool,
    /// A door that slides along its wall instead of swinging: `swing` then
    /// says how far it is open, 0 shut, 90 and over all the way.
    pub slide: bool,
    /// **A pair of doors** (his ask, 2026-10-17): two leaves meeting in the
    /// middle. With `slide` off they swing from the middle (double doors);
    /// with it on they part from the centre and slide out each way.
    pub pair: bool,
    /// **A pocket door**: it slides into the wall (with `slide`); `hinge`
    /// says which side the pocket is, both sides with `pair`.
    pub pocket: bool,
    /// **Words and arrows made in the Set view** stay in it: the layer of
    /// a word or an arrow is the view it was placed in (plot unless this
    /// says set), so an older plan's words are where they were.
    pub in_set: bool,
    /// **Sent to the other view** (his ask, 2026-10-17: *"allow there to be
    /// an option to send those kind of items between the two modes"*):
    /// `set` or `plot` over the layer its kind would put it in; empty is the
    /// kind's own (`layer`). Words, arrows and notes keep `in_set`.
    pub on_layer: String,

    // words
    pub text: String,
    pub size: f64,
    pub bold: bool,
    pub align: String,

    // an arrow
    pub head: String,

    // a road
    pub marking: String,
    pub lanes: u32,
    pub walks: bool,

    pub points: Vec<(f64, f64)>,
    /// Every other step it takes, in letter order (`Step`): the first `lead`
    /// of them come before the thing itself, the rest after.
    pub steps: Vec<Step>,
    /// How many of its steps come before it — a Move From's.
    pub lead: usize,
    /// The beat the thing itself plays on: 1 unless steps before it took
    /// the start, nought for none.
    pub beat: u32,
    /// A picture's file, by the hash the film already keeps media under.
    pub media: String,
    /// **Aimed at** another piece, by its id: a light, a camera or a person
    /// that turns to face it whenever either moves (Scenario's targeting).
    /// Empty is turned by hand.
    pub aim: String,
    /// **An arrow's ends, pinned** to pieces by id (his Spicy Somme plan's
    /// notes with arrows to what they mean): the start (`x`, `y`) and the end
    /// (`x2`, `y2`) follow the piece wherever it goes, stopping at its
    /// outline (`settle_arrows`). Empty is a free end.
    pub start_on: String,
    pub end_on: String,

    // a frame, and gels (`frame.rs`, `gels.rs`)
    /// Gels clipped on a light or in a frame, by id, in the order put on.
    pub gels: Vec<String>,
    /// **A ruler's markers, locked or free** (his ask, 2026-10-01): one per
    /// corner (`walls::corners`) — the id of the piece that marker is locked
    /// to, which it follows (`settle_rulers`), or empty for a marker he
    /// placed by hand.
    pub pins: Vec<String>,
    /// A frame's skin, pipe and egg crate (degrees; nought is none).
    pub material: String,
    pub pipe: String,
    pub grid: f64,
    /// A frame's lean, 0 lying flat to 90 standing, and its height — the
    /// edge that leans (nought: as tall as it is wide).
    pub tilt: f64,
    pub tall: f64,

    // its name on the plan (`render::name_styled`)
    /// Where its name sits, moved from where the kind puts it: metres on the
    /// page as it is shown, north up — right and down.
    pub label_dx: f64,
    pub label_dy: f64,
    /// Its name's size in points; nought is the kind's own.
    pub label_size: f64,
    pub label_bold: bool,
    pub label_hidden: bool,

    // a camera's frame, laid on the plan (`render::shot_frame`)
    /// The linked shot's frame drawn at plan scale beside the camera, its
    /// middle `frame_dx`, `frame_dy` from the camera on the page as shown,
    /// `frame_w` metres wide; it moves with the camera.
    pub frame_on: bool,
    pub frame_dx: f64,
    pub frame_dy: f64,
    pub frame_w: f64,
    /// **Rides** another piece, by its id: a light, camera, flag or frame on
    /// a stand, a track, a frame or a set piece (`rigging.rs`). Moving or
    /// turning that piece carries this one. Empty stands on its own.
    pub rig_on: String,

    // **A lighting plot's facts** (his ask, 2026-10-03, after Deakins's
    // plots): how many of the unit stand here under one name ("3× 2K
    // Blonde"); whether it is the location's own light rather than one we
    // bring; and what is done to an existing one — `off`, `swap`, `dim`,
    // or empty to keep it as it is.
    pub count: u32,
    pub existing: bool,
    pub action: String,
    /// **The lamp's mark on a plot**, as he picked it (Labs, his ask
    /// 2026-10-03: *"just chose the symbol and click where i want to add
    /// lights, then assign them what light they are later"*): `chevron`,
    /// `wedge`, `bar`, `double-bar`, `ring`, `dot`, `arrow`, `square`,
    /// `letter-B`; empty is worked out from the unit (`plot::looks`). Its
    /// ink — `added` red, `ink` black, `blue` — and `solid` or `open`;
    /// empty for the mark's own.
    pub mark: String,
    pub mark_ink: String,
    pub mark_fill: String,
    /// **A light's Name is its own** (his call, 2026-10-05: *"i might have
    /// 3 different kinds of panel lights in a setup"*): "SkyPanel S60". The
    /// symbol says the family, this says the unit; empty is its unit's
    /// name, else none (`plot::lamp_name`).
    pub lamp_name: String,
    /// **One label for many lights** (his ask, 2026-10-03): the id of the
    /// words this lamp's callout is shared with — one label, a line out of
    /// it to every lamp tied to it. Empty is a lamp with its own.
    pub tie_to: String,
    /// **A practical** (his words, 2026-10-03: *"lights that are 'in scene'
    /// are called Practicals vs other film lights that will be hidden"*):
    /// a lamp seen in the shot, often the art department's. A lamp is a
    /// film light, a practical, or `existing` — the location's own.
    pub practical: bool,
    /// **A string of lamps** (his ask, 2026-10-04, after the Fausto Estate
    /// and Wild Pony plots): `line` spreads `count` marks evenly along the
    /// lamp's long side, bowed by `curve` metres; `ring` puts them round an
    /// oval its size. Empty is one lamp at one spot.
    pub spread: String,
    /// Drawn underneath everything else — a ruler he wants out of the way
    /// under the furniture and lights.
    pub under: bool,
}

impl El {
    /// A fresh one of a kind, with the defaults a person would pick.
    pub fn new(kind: Kind, id: &str) -> El {
        let mut el = El {
            id: id.to_string(),
            kind,
            x: 0.0,
            y: 0.0,
            x2: 0.0,
            y2: 0.0,
            rot: 0.0,
            w: 1.0,
            h: 1.0,
            curve: 0.0,
            thick: 0.0,
            closed: false,
            round: Vec::new(),
            label: String::new(),
            title: String::new(),
            caption: String::new(),
            marks: String::new(),
            perspective: String::new(),
            color: String::new(),
            fill: true,
            fill_color: String::new(),
            fill_alpha: 0.0,
            dash: String::new(),
            weight: 0.0,
            opacity: 1.0,
            locked: false,
            hidden: false,
            group: String::new(),
            group_name: String::new(),
            note: String::new(),
            sym: String::new(),
            shot: String::new(),
            lens: 0.0,
            unit: String::new(),
            lens_name: String::new(),
            sensor: String::new(),
            reach: 0.0,
            cone: true,
            height: String::new(),
            rig: String::new(),
            cast: String::new(),
            pose: String::new(),
            kelvin: 0.0,
            beam: 0.0,
            beam_on: true,
            dim: 100.0,
            mark_k: 1.0,
            role: String::new(),
            swing: 90.0,
            hinge: String::new(),
            flip: false,
            slide: false,
            pair: false,
            pocket: false,
            in_set: false,
            on_layer: String::new(),
            text: String::new(),
            size: 0.0,
            bold: false,
            align: String::new(),
            head: String::new(),
            marking: String::new(),
            lanes: 0,
            walks: false,
            points: Vec::new(),
            handles: Vec::new(),
            steps: Vec::new(),
            lead: 0,
            beat: 1,
            media: String::new(),
            aim: String::new(),
            start_on: String::new(),
            end_on: String::new(),
            gels: Vec::new(),
            pins: Vec::new(),
            material: String::new(),
            pipe: String::new(),
            grid: 0.0,
            tilt: 90.0,
            tall: 0.0,
            label_dx: 0.0,
            label_dy: 0.0,
            label_size: 0.0,
            label_bold: true,
            label_hidden: false,
            frame_on: false,
            frame_dx: 0.0,
            frame_dy: 0.0,
            frame_w: 0.0,
            rig_on: String::new(),
            count: 1,
            existing: false,
            action: String::new(),
            mark: String::new(),
            mark_ink: String::new(),
            mark_fill: String::new(),
            lamp_name: String::new(),
            tie_to: String::new(),
            practical: false,
            under: false,
            spread: String::new(),
        };
        match kind {
            Kind::Wall => el.thick = WALL,
            Kind::Door => {
                el.w = 0.9;
                el.h = WALL;
            }
            Kind::Window => {
                el.w = 1.2;
                el.h = WALL;
            }
            Kind::Opening => {
                el.w = 1.0;
                el.h = WALL;
            }
            Kind::Camera => {
                // The Film Set Objects pack's Alexa Mini, as the pack drew it:
                // lens to back, and across.
                el.w = 0.39;
                el.h = 0.37;
                // Its frame, when he lays it on the plan: under the camera,
                // a metre and a half wide.
                el.frame_dy = 1.4;
                el.frame_w = 1.5;
            }
            Kind::Cast => {
                // A person from above: chest to back, and across the shoulders.
                el.w = 0.28;
                el.h = 0.46;
                el.pose = "standing".into();
            }
            Kind::Light => {
                el.sym = "fresnel".into();
                el.w = 0.45;
                el.h = 0.45;
                el.beam = 40.0;
                el.reach = 3.0;
            }
            Kind::Track => el.thick = 0.6,
            Kind::Road => {
                // A street, 30 ft kerb to kerb.
                el.thick = 9.144;
                el.lanes = 2;
                el.marking = "dashed".into();
            }
            Kind::Text => el.size = 14.0,
            Kind::Shape => {
                el.sym = "rect".into();
                el.w = 2.0;
                el.h = 1.5;
                // **Quiet by default** (Back to Paper, 2026-10-04): a shape
                // is an outline until he turns Filled on. A shape that never
                // said either way reads as an outline too; one he filled by
                // hand keeps its fill, and nothing stored is rewritten.
                el.fill = false;
            }
            Kind::Stroke | Kind::Arrow | Kind::Cable => el.weight = 2.0,
            Kind::Note => {
                el.w = 0.4;
                el.h = 0.4;
            }
            _ => {}
        }
        el
    }

    pub fn from_json(v: &Json) -> Option<El> {
        let kind = Kind::parse(v.get("kind")?.as_str()?)?;
        let id = v.get("id")?.as_str()?;
        let mut el = El::new(kind, id);
        let n = |k: &str, d: f64| v.get(k).and_then(|x| x.as_f64()).filter(|x| x.is_finite()).unwrap_or(d);
        let s = |k: &str, d: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or(d).to_string();
        let b = |k: &str, d: bool| v.get(k).and_then(|x| x.as_bool()).unwrap_or(d);
        el.x = n("x", el.x);
        el.y = n("y", el.y);
        el.x2 = n("x2", el.x2);
        el.y2 = n("y2", el.y2);
        el.rot = n("rot", el.rot);
        el.w = n("w", el.w).max(0.01);
        el.h = n("h", el.h).max(0.01);
        el.curve = n("curve", el.curve);
        el.thick = n("thick", el.thick).max(0.0);
        el.closed = b("closed", el.closed);
        if let Some(r) = v.get("round").and_then(|r| r.as_array()) {
            el.round = r.iter().filter_map(|i| i.as_f64()).filter(|i| i.is_finite() && *i >= 0.0 && *i < 100_000.0).map(|i| i as usize).collect();
        }
        if let Some(h) = v.get("handles").and_then(|h| h.as_array()) {
            el.handles = h
                .iter()
                .take(100_000)
                .map(|row| {
                    let a = row.as_array();
                    let g = |i: usize| a.and_then(|a| a.get(i)).and_then(|x| x.as_f64()).filter(|x| x.is_finite()).unwrap_or(0.0);
                    [g(0), g(1), g(2), g(3)]
                })
                .collect();
        }
        el.label = s("label", &el.label);
        el.title = s("title", &el.title);
        el.caption = s("caption", &el.caption);
        el.marks = s("marks", &el.marks).chars().take(200_000).collect();
        el.perspective = s("perspective", &el.perspective);
        el.color = s("color", &el.color);
        el.fill = b("fill", el.fill);
        el.fill_color = s("fill_color", &el.fill_color);
        el.fill_alpha = n("fill_alpha", el.fill_alpha).clamp(0.0, 1.0);
        el.dash = s("dash", &el.dash);
        el.weight = n("weight", el.weight).max(0.0);
        el.opacity = n("opacity", el.opacity).clamp(0.0, 1.0);
        el.locked = b("locked", el.locked);
        el.hidden = b("hidden", el.hidden);
        el.group = s("group", &el.group);
        el.group_name = s("group_name", &el.group_name);
        el.note = s("note", &el.note);
        el.sym = s("sym", &el.sym);
        el.shot = s("shot", &el.shot);
        el.lens = n("lens", el.lens).max(0.0);
        el.sensor = s("sensor", &el.sensor);
        el.lens_name = s("lens_name", &el.lens_name);
        el.unit = s("unit", &el.unit);
        el.reach = n("reach", el.reach).max(0.0);
        el.cone = b("cone", el.cone);
        el.height = s("height", &el.height);
        el.rig = s("rig", &el.rig);
        el.cast = s("cast", &el.cast);
        el.pose = s("pose", &el.pose);
        el.kelvin = n("kelvin", el.kelvin).max(0.0);
        el.beam = n("beam", el.beam).clamp(0.0, 180.0);
        el.beam_on = b("beam_on", el.beam_on);
        el.dim = n("dim", el.dim).clamp(0.0, 100.0);
        el.mark_k = n("mark_k", el.mark_k).clamp(lampscale::MIN, lampscale::MAX);
        el.role = s("role", &el.role);
        el.swing = n("swing", el.swing).clamp(0.0, 180.0);
        el.hinge = s("hinge", &el.hinge);
        el.flip = b("flip", el.flip);
        el.slide = b("slide", el.slide);
        el.pair = b("pair", el.pair);
        el.pocket = b("pocket", el.pocket);
        // **One word for a door's kind** (`door`: swing, double, sliding,
        // center, pocket), for the connector and room scans; it sets the
        // three switches above and is not kept itself.
        if let Some(style) = v.get("door").and_then(|x| x.as_str()) {
            el.set_door_style(style);
        }
        el.in_set = b("in_set", el.in_set);
        el.on_layer = match s("on_layer", &el.on_layer).trim() {
            l @ (SET_LAYER | PLOT_LAYER) => l.to_string(),
            _ => String::new(),
        };
        el.text = s("text", &el.text);
        el.size = n("size", el.size).max(0.0);
        el.bold = b("bold", el.bold);
        el.align = s("align", &el.align);
        el.head = s("head", &el.head);
        el.marking = s("marking", &el.marking);
        el.aim = s("aim", &el.aim);
        el.rig_on = s("rig_on", &el.rig_on);
        el.start_on = s("start_on", &el.start_on);
        el.end_on = s("end_on", &el.end_on);
        el.lanes = n("lanes", el.lanes as f64).clamp(0.0, 12.0) as u32;
        el.count = n("count", el.count as f64).round().clamp(1.0, 999.0) as u32;
        el.existing = b("existing", el.existing);
        el.tie_to = s("tie_to", &el.tie_to);
        el.under = b("under", el.under);
        el.practical = b("practical", el.practical);
        el.spread = match s("spread", &el.spread).trim() {
            "line" => "line".into(),
            "ring" => "ring".into(),
            _ => String::new(),
        };
        el.mark = s("mark", &el.mark).trim().to_lowercase();
        if !el.mark.is_empty() && plot::Mark::parse(&el.mark).is_none() {
            el.mark.clear();
        }
        el.mark_ink = plot::ink_word(s("mark_ink", &el.mark_ink).trim()).unwrap_or("").to_string();
        el.mark_fill = match s("mark_fill", &el.mark_fill).trim() {
            f @ ("solid" | "open") => f.to_string(),
            _ => String::new(),
        };
        el.lamp_name = s("lamp_name", &el.lamp_name).trim().to_string();
        el.action = match s("action", &el.action).trim().to_lowercase().as_str() {
            a @ ("off" | "swap" | "dim") => a.to_string(),
            _ => String::new(),
        };
        el.walks = b("walks", el.walks);
        el.media = s("media", &el.media);
        el.material = s("material", &el.material);
        el.pipe = s("pipe", &el.pipe);
        el.grid = n("grid", el.grid);
        el.tilt = n("tilt", el.tilt);
        el.tall = n("tall", el.tall);
        el.label_dx = n("label_dx", el.label_dx);
        el.label_dy = n("label_dy", el.label_dy);
        el.label_size = n("label_size", el.label_size);
        el.label_bold = b("label_bold", el.label_bold);
        el.label_hidden = b("label_hidden", el.label_hidden);
        el.frame_on = b("frame_on", el.frame_on);
        el.frame_dx = n("frame_dx", el.frame_dx);
        el.frame_dy = n("frame_dy", el.frame_dy);
        el.frame_w = n("frame_w", el.frame_w);
        if let Some(p) = v.get("pins").and_then(|p| p.as_array()) {
            el.pins = p.iter().map(|x| x.as_str().unwrap_or("").trim().to_string()).collect();
        }
        if let Some(g) = v.get("gels").and_then(|g| g.as_array()) {
            el.gels = g.iter().filter_map(|x| x.as_str()).map(|x| x.trim().to_string()).filter(|x| !x.is_empty()).collect();
        }
        if let Some(pts) = v.get("points").and_then(|p| p.as_array()) {
            el.points = pts
                .iter()
                .filter_map(|p| {
                    let a = p.as_array()?;
                    let x = a.first()?.as_f64()?;
                    let y = a.get(1)?.as_f64()?;
                    (x.is_finite() && y.is_finite()).then_some((x, y))
                })
                .collect();
        }
        let count = |k: &str| v.get(k).and_then(|x| x.as_f64()).filter(|x| x.is_finite()).map(|x| x.max(0.0));
        if let Some(steps) = v.get("steps").and_then(|p| p.as_array()) {
            el.steps = steps.iter().filter_map(|p| Step::from_json(p, el.rot)).collect();
            el.lead = count("lead").map(|n| n as usize).unwrap_or(0);
            el.beat = count("beat").map(|n| n as u32).unwrap_or(1);
        } else {
            // **Written before steps** (2026-10-01): its beats 2 and on as a
            // `path`, and one A → B as a `move` — which never played, so it
            // comes in on no beat, and the plan plays as it always did.
            if let Some(path) = v.get("path").and_then(|p| p.as_array()) {
                let mut beats: Vec<Step> = path
                    .iter()
                    .filter_map(|p| Step::from_json(p, el.rot))
                    .map(|mut b| {
                        b.beat = b.beat.max(2);
                        b.turn = false;
                        b
                    })
                    .collect();
                beats.sort_by_key(|b| b.beat);
                beats.dedup_by_key(|b| b.beat);
                el.steps = beats;
            }
            if let Some(mut t) = v.get("move").and_then(|m| Step::from_json(m, el.rot)) {
                t.beat = 0;
                t.pose = Pose::Same;
                if v.get("move").and_then(|m| m.get("dir")).and_then(|d| d.as_str()) == Some("from") {
                    el.steps.insert(0, t);
                    el.lead = 1;
                } else {
                    el.steps.push(t);
                }
            }
        }
        el.tame();
        Some(el)
    }

    /// **Kept to a plan's size.** Nothing on a set stands a hundred
    /// kilometres from the middle, nor needs a thousand beats; a number past
    /// either came from a slip — a typed `1e9`, a drag that ran away — and
    /// left alone it overflows on the way to the page and the whole plan
    /// fails to draw. Held here, after every edit and every read.
    pub fn tame(&mut self) {
        // Held to what the file keeps, too — a tenth of a millimetre — so the
        // plan in memory and the plan read back are the same plan, and an
        // edit never rewrites a piece for a difference nobody could see.
        let at = |v: &mut f64| *v = if v.is_finite() { round(v.clamp(-FAR, FAR)) } else { 0.0 };
        let size = |v: &mut f64| *v = if v.is_finite() { round(v.clamp(0.0, FAR)) } else { 1.0 };
        let within = |v: &mut f64, lo: f64, hi: f64, or: f64| *v = if v.is_finite() { round(v.clamp(lo, hi)) } else { or };
        let turn = |v: &mut f64| *v = if v.is_finite() { round(norm_deg(*v)) % 360.0 } else { 0.0 };
        at(&mut self.x);
        at(&mut self.y);
        at(&mut self.x2);
        at(&mut self.y2);
        at(&mut self.curve);
        size(&mut self.w);
        size(&mut self.h);
        size(&mut self.thick);
        size(&mut self.reach);
        size(&mut self.size);
        within(&mut self.weight, 0.0, 100.0, 1.0);
        within(&mut self.opacity, 0.0, 1.0, 1.0);
        within(&mut self.lens, 0.0, 5000.0, 0.0);
        within(&mut self.kelvin, 0.0, 100_000.0, 0.0);
        within(&mut self.beam, 0.0, 180.0, 0.0);
        within(&mut self.dim, 0.0, 100.0, 100.0);
        within(&mut self.mark_k, lampscale::MIN, lampscale::MAX, 1.0);
        within(&mut self.swing, 0.0, 180.0, 90.0);
        within(&mut self.fill_alpha, 0.0, 1.0, 0.0);
        within(&mut self.tilt, 0.0, 90.0, 90.0);
        within(&mut self.grid, 0.0, 90.0, 0.0);
        size(&mut self.tall);
        // A name is moved about beside its piece, never kilometres off.
        within(&mut self.label_dx, -NEAR, NEAR, 0.0);
        within(&mut self.label_dy, -NEAR, NEAR, 0.0);
        within(&mut self.label_size, 0.0, 96.0, 0.0);
        within(&mut self.frame_dx, -NEAR, NEAR, 0.0);
        within(&mut self.frame_dy, -NEAR, NEAR, 0.0);
        within(&mut self.frame_w, 0.0, NEAR, 0.0);
        if self.kind != Kind::Camera {
            self.frame_on = false;
        }
        self.gels.truncate(gels::MOST);
        if self.kind != Kind::Measure {
            self.pins.clear();
        }
        self.pins.truncate(64);
        self.gels.retain(|g| g.chars().count() <= gels::LONGEST);
        if frame::is_frame(self) {
            frame::settle(self);
        }
        if symbols::is_half_round(self) {
            self.h = self.w / 2.0;
        }
        self.lanes = self.lanes.min(12);
        turn(&mut self.rot);
        for p in &mut self.points {
            at(&mut p.0);
            at(&mut p.1);
        }
        for b in &mut self.steps {
            at(&mut b.x);
            at(&mut b.y);
            turn(&mut b.rot);
            b.beat = b.beat.min(MOST_BEATS);
        }
        self.beat = self.beat.min(MOST_BEATS);
        // A wall's ends on its first and last corner; its rounded corners
        // only where there are corners to round.
        walls::settle(self);
        // Only a thing that stands on the floor makes a move.
        if !self.kind.moves() {
            self.steps.clear();
            self.beat = 1;
        }
        self.steps.truncate(MOST_STEPS);
        self.lead = self.lead.min(self.steps.len());
        self.settle_steps();
    }

    /// Its steps kept honest: one step to a beat — the first in letter order
    /// keeps it, a later one on the same beat plays on none — and a turn on
    /// the spot of the step before it (after it, for a first step), so it
    /// follows wherever that one is put.
    fn settle_steps(&mut self) {
        // With no other step, there is nothing to put on a beat but the start.
        if self.steps.is_empty() {
            self.lead = 0;
            self.beat = 1;
            return;
        }
        let home = self.lead;
        let n = self.steps.len() + 1;
        let mut taken = std::collections::HashSet::new();
        for i in 0..n {
            let b = if i == home { &mut self.beat } else { &mut self.steps[if i < home { i } else { i - 1 }].beat };
            if *b > 0 && !taken.insert(*b) {
                *b = 0;
            }
        }
        // A turn's spot: the nearest step before it that is not a turn, else
        // the nearest after. The thing itself never turns in place, so
        // there is always one.
        let spots: Vec<(f64, f64, bool)> = (0..n)
            .map(|i| if i == home { (self.x, self.y, false) } else { let s = self.steps[if i < home { i } else { i - 1 }]; (s.x, s.y, s.turn) })
            .collect();
        for i in 0..n {
            if i == home || !spots[i].2 {
                continue;
            }
            let from = (0..i).rev().chain(i + 1..n).find(|&j| !spots[j].2).unwrap_or(home);
            let s = &mut self.steps[if i < home { i } else { i - 1 }];
            (s.x, s.y) = (spots[from].0, spots[from].1);
        }
    }

    /// **Its steps in letter order**, the thing itself among them.
    pub fn sequence(&self) -> Vec<Spot> {
        let mut out: Vec<Spot> = self
            .steps
            .iter()
            .map(|s| Spot { x: s.x, y: s.y, rot: s.rot, beat: s.beat, pose: s.pose, turn: s.turn, home: false })
            .collect();
        let pose = Pose::parse(&self.pose);
        out.insert(
            self.lead.min(self.steps.len()),
            Spot { x: self.x, y: self.y, rot: self.rot, beat: self.beat, pose, turn: false, home: true },
        );
        out
    }

    /// **A new step at a letter-order index** (0 puts it first), on the
    /// beat it carries.
    pub fn insert_step(&mut self, at: usize, step: Step) {
        let at = at.min(self.steps.len() + 1);
        if at <= self.lead {
            self.steps.insert(at, step);
            self.lead += 1;
        } else {
            self.steps.insert(at - 1, step);
        }
    }

    /// Take a step away by its letter-order index. The thing itself stays.
    pub fn remove_step(&mut self, i: usize) {
        if let Some(k) = self.step_index(i) {
            self.steps.remove(k);
            if i < self.lead {
                self.lead -= 1;
            }
        }
    }

    /// Put one step somewhere, by its letter-order index. A turn dragged off
    /// its spot becomes a move.
    pub fn place_step(&mut self, i: usize, x: Option<f64>, y: Option<f64>, rot: Option<f64>, pose: Option<Pose>) {
        match self.step_index(i) {
            None => {
                self.x = x.unwrap_or(self.x);
                self.y = y.unwrap_or(self.y);
                self.rot = rot.unwrap_or(self.rot);
            }
            Some(k) => {
                let s = &mut self.steps[k];
                let (nx, ny) = (x.unwrap_or(s.x), y.unwrap_or(s.y));
                if s.turn && (nx - s.x).hypot(ny - s.y) > 1e-3 {
                    s.turn = false;
                }
                (s.x, s.y) = (nx, ny);
                s.rot = rot.unwrap_or(s.rot);
                if let Some(p) = pose {
                    s.pose = p;
                }
            }
        }
    }

    fn beat_of(&mut self, i: usize) -> Option<&mut u32> {
        match self.step_index(i) {
            None if i == self.lead => Some(&mut self.beat),
            None => None,
            Some(k) => Some(&mut self.steps[k].beat),
        }
    }

    /// **Put one step on a beat** (nought: on none). A beat holds one step
    /// of a thing, so a step already on it takes this one's old beat — two
    /// steps trade places in the sequence.
    pub fn give_beat(&mut self, i: usize, beat: u32) {
        let beat = beat.min(MOST_BEATS);
        let Some(old) = self.beat_of(i).map(|b| *b) else { return };
        if beat > 0 {
            if let Some(j) = self.sequence().iter().position(|p| p.beat == beat) {
                if j != i {
                    if let Some(b) = self.beat_of(j) {
                        *b = old;
                    }
                }
            }
        }
        if let Some(b) = self.beat_of(i) {
            *b = beat;
        }
    }

    /// **A new step's beat**, so it plays straight away and in its place: the
    /// beat of the next step after it that is on one — that step and every
    /// later beat of this thing moving up one to make room — or, with none
    /// after it, the beat after its last.
    pub fn next_beat(&mut self, i: usize) {
        let seq = self.sequence();
        let beat = match seq.iter().skip(i + 1).find(|p| p.beat > 0).map(|p| p.beat) {
            Some(next) => {
                for k in 0..seq.len() {
                    if k != i {
                        if let Some(b) = self.beat_of(k).filter(|b| **b >= next) {
                            *b = (*b + 1).min(MOST_BEATS);
                        }
                    }
                }
                next
            }
            None => seq.iter().map(|p| p.beat).max().unwrap_or(0) + 1,
        };
        if let Some(b) = self.beat_of(i) {
            *b = beat.min(MOST_BEATS);
        }
    }

    /// Which of `steps` a letter-order index is, or `None` for the thing
    /// itself.
    pub fn step_index(&self, i: usize) -> Option<usize> {
        match i.cmp(&self.lead) {
            std::cmp::Ordering::Less => Some(i),
            std::cmp::Ordering::Equal => None,
            std::cmp::Ordering::Greater => Some(i - 1).filter(|&k| k < self.steps.len()),
        }
    }

    /// Only what differs from a fresh one of its kind is written.
    pub fn to_json(&self) -> Json {
        let d = El::new(self.kind, &self.id);
        let mut o: Vec<(String, Json)> = vec![
            ("id".into(), Json::text(&self.id)),
            ("kind".into(), Json::text(self.kind.as_str())),
        ];
        let num = |o: &mut Vec<(String, Json)>, k: &str, v: f64, dv: f64| {
            if (v - dv).abs() > 1e-9 {
                o.push((k.into(), Json::Number(round(v))));
            }
        };
        num(&mut o, "x", self.x, d.x);
        num(&mut o, "y", self.y, d.y);
        num(&mut o, "x2", self.x2, d.x2);
        num(&mut o, "y2", self.y2, d.y2);
        num(&mut o, "rot", self.rot, d.rot);
        num(&mut o, "w", self.w, d.w);
        num(&mut o, "h", self.h, d.h);
        num(&mut o, "curve", self.curve, d.curve);
        num(&mut o, "thick", self.thick, d.thick);
        num(&mut o, "weight", self.weight, d.weight);
        num(&mut o, "opacity", self.opacity, d.opacity);
        num(&mut o, "lens", self.lens, d.lens);
        num(&mut o, "reach", self.reach, d.reach);
        num(&mut o, "kelvin", self.kelvin, d.kelvin);
        num(&mut o, "beam", self.beam, d.beam);
        num(&mut o, "dim", self.dim, d.dim);
        num(&mut o, "mark_k", self.mark_k, d.mark_k);
        num(&mut o, "swing", self.swing, d.swing);
        num(&mut o, "fill_alpha", self.fill_alpha, d.fill_alpha);
        num(&mut o, "size", self.size, d.size);
        num(&mut o, "lanes", self.lanes as f64, d.lanes as f64);
        num(&mut o, "count", self.count as f64, d.count as f64);
        num(&mut o, "grid", self.grid, d.grid);
        num(&mut o, "tilt", self.tilt, d.tilt);
        num(&mut o, "tall", self.tall, d.tall);
        num(&mut o, "label_dx", self.label_dx, d.label_dx);
        num(&mut o, "label_dy", self.label_dy, d.label_dy);
        num(&mut o, "label_size", self.label_size, d.label_size);
        num(&mut o, "frame_dx", self.frame_dx, d.frame_dx);
        num(&mut o, "frame_dy", self.frame_dy, d.frame_dy);
        num(&mut o, "frame_w", self.frame_w, d.frame_w);
        let strs: Vec<(&str, &String, &String)> = vec![
            ("label", &self.label, &d.label),
            ("color", &self.color, &d.color),
            ("fill_color", &self.fill_color, &d.fill_color),
            ("dash", &self.dash, &d.dash),
            ("group", &self.group, &d.group),
            ("group_name", &self.group_name, &d.group_name),
            ("note", &self.note, &d.note),
            ("sym", &self.sym, &d.sym),
            ("shot", &self.shot, &d.shot),
            ("sensor", &self.sensor, &d.sensor),
            ("lens_name", &self.lens_name, &d.lens_name),
            ("unit", &self.unit, &d.unit),
            ("height", &self.height, &d.height),
            ("rig", &self.rig, &d.rig),
            ("cast", &self.cast, &d.cast),
            ("pose", &self.pose, &d.pose),
            ("role", &self.role, &d.role),
            ("hinge", &self.hinge, &d.hinge),
            ("text", &self.text, &d.text),
            ("align", &self.align, &d.align),
            ("head", &self.head, &d.head),
            ("marking", &self.marking, &d.marking),
            ("media", &self.media, &d.media),
            ("aim", &self.aim, &d.aim),
            ("rig_on", &self.rig_on, &d.rig_on),
            ("action", &self.action, &d.action),
            ("mark", &self.mark, &d.mark),
            ("mark_ink", &self.mark_ink, &d.mark_ink),
            ("mark_fill", &self.mark_fill, &d.mark_fill),
            ("lamp_name", &self.lamp_name, &d.lamp_name),
            ("on_layer", &self.on_layer, &d.on_layer),
            ("tie_to", &self.tie_to, &d.tie_to),
            ("spread", &self.spread, &d.spread),
            ("title", &self.title, &d.title),
            ("caption", &self.caption, &d.caption),
            ("marks", &self.marks, &d.marks),
            ("perspective", &self.perspective, &d.perspective),
            ("start_on", &self.start_on, &d.start_on),
            ("end_on", &self.end_on, &d.end_on),
            ("material", &self.material, &d.material),
            ("pipe", &self.pipe, &d.pipe),
        ];
        for (k, v, dv) in strs {
            if v != dv {
                o.push((k.into(), Json::text(v.as_str())));
            }
        }
        let bools = [
            ("fill", self.fill, d.fill),
            ("locked", self.locked, d.locked),
            ("hidden", self.hidden, d.hidden),
            ("cone", self.cone, d.cone),
            ("beam_on", self.beam_on, d.beam_on),
            ("flip", self.flip, d.flip),
            ("slide", self.slide, d.slide),
            ("pair", self.pair, d.pair),
            ("pocket", self.pocket, d.pocket),
            ("in_set", self.in_set, d.in_set),
            ("bold", self.bold, d.bold),
            ("walks", self.walks, d.walks),
            ("label_bold", self.label_bold, d.label_bold),
            ("label_hidden", self.label_hidden, d.label_hidden),
            ("frame_on", self.frame_on, d.frame_on),
            ("closed", self.closed, d.closed),
            ("existing", self.existing, d.existing),
            ("under", self.under, d.under),
            ("practical", self.practical, d.practical),
        ];
        for (k, v, dv) in bools {
            if v != dv {
                o.push((k.into(), Json::Bool(v)));
            }
        }
        if !self.points.is_empty() {
            o.push((
                "points".into(),
                Json::Array(
                    self.points
                        .iter()
                        .map(|(x, y)| Json::Array(vec![Json::Number(round(*x)), Json::Number(round(*y))]))
                        .collect(),
                ),
            ));
        }
        if !self.round.is_empty() {
            o.push(("round".into(), Json::Array(self.round.iter().map(|i| Json::Number(*i as f64)).collect())));
        }
        if !self.handles.is_empty() {
            o.push(("handles".into(), self.handles_json()));
        }
        if !self.steps.is_empty() {
            o.push(("steps".into(), Json::Array(self.steps.iter().map(|s| s.to_json(false)).collect())));
            if self.lead > 0 {
                o.push(("lead".into(), Json::Number(self.lead as f64)));
            }
        }
        if self.beat != 1 {
            o.push(("beat".into(), Json::Number(self.beat as f64)));
        }
        if self.pins.iter().any(|p| !p.is_empty()) {
            o.push(("pins".into(), Json::Array(self.pins.iter().map(|p| Json::text(p.as_str())).collect())));
        }
        if !self.gels.is_empty() {
            o.push(("gels".into(), Json::Array(self.gels.iter().map(|g| Json::text(g.as_str())).collect())));
        }
        Json::Object(o)
    }

    /// Every field, defaults and all — for a shell that should not have to
    /// know what the defaults are.
    pub fn to_json_full(&self) -> Json {
        let mut o: Vec<(String, Json)> = vec![
            ("id".into(), Json::text(&self.id)),
            ("kind".into(), Json::text(self.kind.as_str())),
        ];
        for (k, v) in [
            ("x", self.x), ("y", self.y), ("x2", self.x2), ("y2", self.y2), ("rot", self.rot),
            ("w", self.w), ("h", self.h), ("curve", self.curve), ("thick", self.thick),
            ("weight", self.weight), ("opacity", self.opacity), ("lens", self.lens),
            ("reach", self.reach), ("kelvin", self.kelvin), ("beam", self.beam), ("dim", self.dim), ("mark_k", self.mark_k),
            ("swing", self.swing), ("fill_alpha", self.fill_alpha), ("size", self.size), ("lanes", self.lanes as f64), ("count", self.count as f64),
            ("grid", self.grid), ("tilt", self.tilt), ("tall", self.tall),
            ("label_dx", self.label_dx), ("label_dy", self.label_dy), ("label_size", self.label_size),
            ("frame_dx", self.frame_dx), ("frame_dy", self.frame_dy), ("frame_w", self.frame_w),
        ] {
            o.push((k.into(), Json::Number(round(v))));
        }
        for (k, v) in [
            ("label", &self.label), ("color", &self.color), ("fill_color", &self.fill_color), ("dash", &self.dash), ("group", &self.group),
            ("group_name", &self.group_name), ("note", &self.note), ("sym", &self.sym), ("shot", &self.shot), ("sensor", &self.sensor), ("lens_name", &self.lens_name), ("unit", &self.unit),
            ("height", &self.height), ("rig", &self.rig), ("cast", &self.cast), ("pose", &self.pose),
            ("role", &self.role), ("hinge", &self.hinge), ("text", &self.text), ("align", &self.align),
            ("head", &self.head), ("marking", &self.marking), ("media", &self.media), ("aim", &self.aim),
            ("material", &self.material), ("pipe", &self.pipe), ("rig_on", &self.rig_on),
            ("start_on", &self.start_on), ("end_on", &self.end_on), ("action", &self.action),
            ("mark", &self.mark), ("mark_ink", &self.mark_ink), ("mark_fill", &self.mark_fill), ("lamp_name", &self.lamp_name), ("tie_to", &self.tie_to),
            ("spread", &self.spread),
            ("on_layer", &self.on_layer),
            ("title", &self.title),
            ("caption", &self.caption),
            ("marks", &self.marks),
            ("perspective", &self.perspective),
        ] {
            o.push((k.into(), Json::text(v.as_str())));
        }
        for (k, v) in [
            ("fill", self.fill), ("locked", self.locked), ("hidden", self.hidden), ("cone", self.cone),
            ("beam_on", self.beam_on), ("flip", self.flip), ("slide", self.slide), ("pair", self.pair), ("pocket", self.pocket), ("in_set", self.in_set), ("bold", self.bold), ("walks", self.walks),
            ("label_bold", self.label_bold), ("label_hidden", self.label_hidden), ("frame_on", self.frame_on),
            ("closed", self.closed), ("existing", self.existing), ("under", self.under), ("practical", self.practical),
        ] {
            o.push((k.into(), Json::Bool(v)));
        }
        o.push(("gels".into(), Json::Array(self.gels.iter().map(|g| Json::text(g.as_str())).collect())));
        o.push(("pins".into(), Json::Array(self.pins.iter().map(|p| Json::text(p.as_str())).collect())));
        o.push(("round".into(), Json::Array(self.round.iter().map(|i| Json::Number(*i as f64)).collect())));
        o.push(("handles".into(), self.handles_json()));
        o.push((
            "points".into(),
            Json::Array(self.points.iter().map(|(x, y)| Json::Array(vec![Json::Number(round(*x)), Json::Number(round(*y))])).collect()),
        ));
        o.push(("steps".into(), Json::Array(self.steps.iter().map(|s| s.to_json(true)).collect())));
        o.push(("lead".into(), Json::Number(self.lead as f64)));
        o.push(("beat".into(), Json::Number(self.beat as f64)));
        // Its steps as the plan shows them, so no shell works out letters,
        // the thing's place among them or where a turn stands on its own.
        if let Some(seq) = self.seq_json() {
            o.push(("seq".into(), seq));
        }
        Json::Object(o)
    }

    /// **The step it is on at a beat**, by letter-order index: the one with
    /// the latest beat up to this one; before its first beat, the step that
    /// first beat belongs to (it waits there); the thing itself when none
    /// of its steps is on a beat.
    pub fn step_at(&self, beat: u32) -> usize {
        let seq = self.sequence();
        let on: Vec<(usize, u32)> = seq.iter().enumerate().filter(|(_, p)| p.beat > 0).map(|(i, p)| (i, p.beat)).collect();
        on.iter()
            .filter(|(_, b)| *b <= beat)
            .max_by_key(|(_, b)| *b)
            .or_else(|| on.iter().min_by_key(|(_, b)| *b))
            .map(|(i, _)| *i)
            .unwrap_or(self.lead.min(self.steps.len()))
    }

    /// **Its steps in letter order, as words for a shell or Claude**: each
    /// one's letter, place, heading, beat, pose and whether it is a turn or
    /// the thing itself. `None` with no other step.
    pub fn seq_json(&self) -> Option<Json> {
        if self.steps.is_empty() {
            return None;
        }
        Some(Json::Array(
            self.sequence()
                .iter()
                .enumerate()
                .map(|(i, p)| {
                    Json::Object(vec![
                        ("letter".into(), Json::text(&letter(i))),
                        ("x".into(), Json::Number(round(p.x))),
                        ("y".into(), Json::Number(round(p.y))),
                        ("rot".into(), Json::Number(round(p.rot))),
                        ("beat".into(), Json::Number(p.beat as f64)),
                        ("pose".into(), Json::text(p.pose.as_str())),
                        ("turn".into(), Json::Bool(p.turn)),
                        ("home".into(), Json::Bool(p.home)),
                    ])
                })
                .collect(),
        ))
    }

    /// Where it stands at a beat.
    pub fn at_beat(&self, beat: u32) -> (f64, f64, f64) {
        if self.steps.is_empty() {
            return (self.x, self.y, self.rot);
        }
        let p = &self.sequence()[self.step_at(beat)];
        (p.x, p.y, p.rot)
    }

    /// How a person is at a beat: the last pose named by then, in beat order,
    /// else their own.
    pub fn pose_at(&self, beat: u32) -> String {
        if self.steps.is_empty() {
            return self.pose.clone();
        }
        let seq = self.sequence();
        let mut on: Vec<&Spot> = seq.iter().filter(|p| p.beat > 0).collect();
        on.sort_by_key(|p| p.beat);
        let upto = seq[self.step_at(beat)].beat.max(on.first().map(|p| p.beat).unwrap_or(0));
        let mut pose = self.pose.clone();
        for p in on.iter().filter(|p| p.beat <= upto && p.pose != Pose::Same) {
            pose = p.pose.as_str().to_string();
        }
        pose
    }

    /// The beats its steps are on, the latest last.
    pub fn beats(&self) -> Vec<u32> {
        let mut b: Vec<u32> = self.steps.iter().map(|s| s.beat).chain(std::iter::once(self.beat)).filter(|b| *b > 0).collect();
        b.sort_unstable();
        b
    }

    /// Its footprint at a beat, as drawn: a person lying down is a body long,
    /// not a pair of shoulders — and the box a hand clicks and a picked thing
    /// wears has to be the one the eye sees.
    /// **A door's kind, as one word** (2026-10-17): `swing` (one leaf on
    /// hinges), `double` (two leaves swinging from the middle), `sliding`
    /// (two panels on two tracks, one riding past the other), `center`
    /// (two panels parting from the centre), `pocket` (into the wall) and
    /// `pocketpair`. An older plan's sliding door is `sliding`.
    pub fn door_style(&self) -> &'static str {
        match (self.slide, self.pair, self.pocket) {
            (false, false, _) => "swing",
            (false, true, _) => "double",
            (true, false, false) => "sliding",
            (true, true, false) => "center",
            (true, false, true) => "pocket",
            (true, true, true) => "pocketpair",
        }
    }

    /// Set a door's kind from its word (`door_style`); an unknown word
    /// leaves it as it is. A sliding kind keeps how far open it is.
    pub fn set_door_style(&mut self, style: &str) {
        let (slide, pair, pocket) = match style.trim().to_lowercase().replace([' ', '-', '_'], "").as_str() {
            "swing" | "hinged" | "single" => (false, false, false),
            "double" | "french" => (false, true, false),
            "sliding" | "slide" | "bypass" => (true, false, false),
            "center" | "centre" | "centersliding" | "centresliding" | "biparting" | "bipart" => (true, true, false),
            "pocket" => (true, false, true),
            "pocketpair" | "doublepocket" => (true, true, true),
            _ => return,
        };
        self.slide = slide;
        self.pair = pair;
        self.pocket = pocket;
    }

    pub fn footprint(&self, beat: u32) -> (f64, f64) {
        if self.kind == Kind::Cast && self.pose_at(beat) == "lying" {
            (self.h * LYING, self.h)
        } else {
            (self.w, self.h)
        }
    }

    fn handles_json(&self) -> Json {
        Json::Array(self.handles.iter().map(|h| Json::Array(h.iter().map(|v| Json::Number(round(*v))).collect())).collect())
    }

    /// Its middle, whatever its kind.
    pub fn centre(&self) -> (f64, f64) {
        if self.kind == Kind::Wall {
            walls::centre(self)
        } else if self.kind.is_line() {
            ((self.x + self.x2) / 2.0, (self.y + self.y2) / 2.0)
        } else if self.kind.is_polyline() && !self.points.is_empty() {
            let (mut sx, mut sy) = (0.0, 0.0);
            for (x, y) in &self.points {
                sx += x;
                sy += y;
            }
            let n = self.points.len() as f64;
            (sx / n, sy / n)
        } else {
            (self.x, self.y)
        }
    }

    /// Slide it, beats and all.
    pub fn translate(&mut self, dx: f64, dy: f64) {
        self.x += dx;
        self.y += dy;
        if self.kind.is_line() {
            self.x2 += dx;
            self.y2 += dy;
        }
        for p in &mut self.points {
            p.0 += dx;
            p.1 += dy;
        }
        for b in &mut self.steps {
            b.x += dx;
            b.y += dy;
        }
    }

    /// Turn it about a point, beats and all.
    pub fn rotate_about(&mut self, deg: f64, px: f64, py: f64) {
        let (c, s) = (deg.to_radians().cos(), deg.to_radians().sin());
        let turn = |x: f64, y: f64| {
            let (dx, dy) = (x - px, y - py);
            (px + dx * c - dy * s, py + dx * s + dy * c)
        };
        (self.x, self.y) = turn(self.x, self.y);
        if self.kind.is_line() {
            (self.x2, self.y2) = turn(self.x2, self.y2);
        } else {
            self.rot = norm_deg(self.rot + deg);
        }
        for p in &mut self.points {
            *p = turn(p.0, p.1);
        }
        // A handle is a way and a length from its corner: it turns, it does not move.
        for h in &mut self.handles {
            let (i, o) = ((h[0] * c - h[1] * s, h[0] * s + h[1] * c), (h[2] * c - h[3] * s, h[2] * s + h[3] * c));
            *h = [i.0, i.1, o.0, o.1];
        }
        for b in &mut self.steps {
            (b.x, b.y) = turn(b.x, b.y);
            b.rot = norm_deg(b.rot + deg);
        }
    }

    pub fn len(&self) -> f64 {
        if self.kind == Kind::Wall {
            return walls::length(self);
        }
        if self.kind == Kind::Measure {
            return walls::corners(self).windows(2).map(|w| (w[1].0 - w[0].0).hypot(w[1].1 - w[0].1)).sum();
        }
        ((self.x2 - self.x).powi(2) + (self.y2 - self.y).powi(2)).sqrt()
    }
}

/// A wall's thickness when nobody has measured it: a stud wall and its
/// plaster. The phone draws scanned walls at the same (`FloorPlan.swift`).
pub const WALL: f64 = 0.15;
/// The farthest anything on a plan may stand from the middle, in metres.
pub const FAR: f64 = 100_000.0;
/// The most beats a plan's blocking may run to.
pub const MOST_BEATS: u32 = 999;
/// The most steps one thing may take.
pub const MOST_STEPS: usize = 999;
/// The farthest a name or a laid-on frame stands from its piece, in metres.
pub const NEAR: f64 = 200.0;

/// How much longer a person is lying than across the shoulders.
pub const LYING: f64 = 3.8;

pub fn norm_deg(d: f64) -> f64 {
    let r = d % 360.0;
    if r < 0.0 {
        r + 360.0
    } else {
        r
    }
}

fn round(v: f64) -> f64 {
    (v * 10_000.0).round() / 10_000.0
}

/// How the plan is shown and measured. Stored with it, so it opens the way it
/// was left.
#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    /// `ft` or `m` — only ever how a number is written.
    pub units: String,
    pub grid: bool,
    pub snap: bool,
    pub dims: bool,
    /// Every wall's lengths on screen, not only the picked wall's (View ›
    /// Wall Lengths › All). Paper always shows them all while `dims` is on.
    pub all_lengths: bool,
    /// **A sketch, not a plan** (his ask, 2026-10-04: callouts over a
    /// location photo or a drawing): no grid, no scale, no lengths, no sun —
    /// a picture with lamp marks and words on it.
    pub sketch: bool,
    pub cones: bool,
    pub beams: bool,
    pub labels: bool,
    /// The grid's step, in metres. A foot, unless he works in metres.
    pub step: f64,
    /// Which way north is on the page, in degrees clockwise from straight up.
    pub north: f64,
    /// Draw the sun: which way its light falls, for the scene's place.
    pub sun: bool,
    /// Its light drawn falling across the plan, not only where it stands.
    /// Off unless asked for (his note, 2026-09-27).
    pub sun_rays: bool,
    /// The day and the clock time to draw it for — `2026-09-27`, `14:30`.
    /// Empty reads the scene's shoot day and its time of day.
    pub sun_date: String,
    pub sun_time: String,
    /// The clock the time is read on — minutes ahead of UTC — kept from the
    /// Mac that set it, so the portal and paper draw the same sun.
    pub sun_tz: Option<f64>,
    /// **Light levels** (`levels.rs`): drawn on the plan only when on.
    /// How they read — `stops`, `lux` or `fc` — and the camera they are read
    /// for: ISO, shutter (the 48 of 1/48) and the stop he wants the midtone
    /// at; the room's own light and the sun's, in lux (nought: by its height).
    pub levels: bool,
    pub light_units: String,
    pub iso: f64,
    pub shutter: f64,
    pub stop: f64,
    pub ambient: f64,
    pub sun_lux: f64,
    /// **How lights are drawn** (his ruling, 2026-10-03: *"plot style is
    /// default"*): `plot` — a small mark and a written callout, the way
    /// Deakins draws a lighting plot — or `picture`, each unit's drawing.
    pub style: String,
    /// **A plot's colours by category** (his ask, 2026-10-03: *"set the
    /// default colors across the board for categories"*): `added` lights we
    /// bring, `existing` the location's own, `blue` the third ink,
    /// `gripink` frames and grip, `camink` cameras, `plan` walls, `prop`
    /// furniture and props — each `#rrggbb`. One left out keeps the
    /// shell's own colour for it.
    pub colours: Vec<(String, String)>,
    /// **The sheet** (Back to Paper, Batch 2, his calls C and G,
    /// 2026-10-04): the page the plan is drawn on, on screen and on paper
    /// (`sheet.rs`). The paper — `letter`, `tabloid` or `a4` — and which
    /// way round it stands, `landscape` or `portrait`.
    pub paper: String,
    pub orientation: String,
    /// The legend on the sheet (View › Legend). On.
    pub legend: bool,
    /// The Notes block on the sheet (View › Sheet Notes). On; printed only
    /// when it has words in it.
    pub notes: bool,
    /// His own words for the whole setup — "ALL LAMPS TO DIMMERS" — printed
    /// under the legend. Never the per-piece `note` a room scan uses.
    pub sheet_notes: String,
    /// A scale bar on the sheet and the scale written in its title (View ›
    /// Sheet › Scale Bar). Off (his call G): the words carry the sizes.
    pub scale_bar: bool,
    /// **A frame's cloth drawn on the plan** (View › Frame Fabric, his note
    /// 2026-10-05): quietly when unpicked, on screen and on paper. On.
    pub fabric: bool,
    /// **View › Measurements** (his ask, 2026-10-05): the rulers he laid,
    /// on screen and on paper. Off, they are kept and not drawn.
    pub measures: bool,
    /// Lights carry their own Names (2026-10-05). False on a plan saved
    /// before, whose names lived on its symbols: `plot::own_names` moves
    /// them onto its lights the first time it is read.
    pub lamp_names: bool,
    /// **Labels are what he types** (his call, 2026-10-15). False on a plan
    /// saved before, where a lamp with no Name showed its unit's: the first
    /// read writes that unit's name on as an ordinary label
    /// (`plot::own_names`), so nothing on the paper changes; lamps put down
    /// after start with none.
    pub typed_labels: bool,
    /// **Labels as he types them** (his ask, 2026-10-17: *"no caps if i
    /// want"*): off draws every word in the case it was typed; on, in
    /// capitals as the references write (Plan Settings › All Caps).
    pub caps: bool,
    /// **Counts on labels and the legend** (2026-10-17: *"not tied to
    /// automatic numbers and counting"*): "3× Key Light", "Key Light ×2".
    /// Off by default (Plan Settings › Counts).
    pub counts: bool,
    /// **Pieces with no label shown as such** (2026-10-17): the legend's
    /// faint "Unlabeled" line. Off, a piece with no label shows nothing.
    pub unlabeled: bool,
    /// **Every piece is named by what he types** (2026-10-17): false on a
    /// plan saved before, whose frames, grip and half rounds wrote their
    /// size, cloth or kind themselves — the first read writes those words
    /// on as ordinary labels (`plot::free_names`), so its paper reads the
    /// same; a piece put down after starts with none.
    pub free_names: bool,
}

/// The papers a sheet prints on.
pub const PAPERS: &[&str] = &["letter", "tabloid", "a4"];

/// The categories a plot's colours can be set for.
pub const PLOT_COLOURS: &[&str] = &["added", "practical", "existing", "blue", "gripink", "camink", "plan", "prop"];

impl Default for Settings {
    fn default() -> Settings {
        Settings {
            units: "ft".into(),
            grid: true,
            snap: true,
            dims: true,
            all_lengths: false,
            sketch: false,
            cones: true,
            // Off until he asks for them, and then for the whole film at once
            // (his ruling, 2026-09-28) — `diagram_setting_everywhere`.
            beams: false,
            labels: true,
            step: FOOT,
            north: 0.0,
            sun: false,
            sun_rays: false,
            sun_date: String::new(),
            sun_time: String::new(),
            sun_tz: None,
            levels: false,
            light_units: "stops".into(),
            iso: 800.0,
            shutter: 48.0,
            stop: 2.8,
            ambient: 0.0,
            sun_lux: 0.0,
            style: "plot".into(),
            colours: Vec::new(),
            paper: "letter".into(),
            orientation: "landscape".into(),
            legend: true,
            notes: true,
            sheet_notes: String::new(),
            scale_bar: false,
            fabric: true,
            measures: true,
            lamp_names: false,
            typed_labels: false,
            caps: false,
            counts: false,
            unlabeled: false,
            free_names: false,
        }
    }
}

impl Settings {
    /// **A plan never drawn on starts quiet** (Back to Paper, his call
    /// 2026-10-04, after Ref 1452's "measurements off by default"): no
    /// lengths until he turns Dimensions on. `Default` stays what a stored
    /// plan's missing values have always meant, so a plan made before this
    /// opens exactly as it was left; a new plan's own settings are written
    /// with its first edit (`Doc::diagram_store`).
    pub fn fresh() -> Settings {
        Settings { dims: false, lamp_names: true, typed_labels: true, free_names: true, ..Settings::default() }
    }
}

pub const FOOT: f64 = 0.3048;

/// The grid a plan in these units starts on: a foot, or half a metre.
pub fn unit_step(units: &str) -> f64 {
    if units == "m" {
        0.5
    } else {
        FOOT
    }
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Diagram {
    /// Bottom of the stack first.
    pub els: Vec<El>,
    pub settings: Settings,
    /// Where the Mac last left the view: middle x, middle y, zoom.
    pub view: Option<(f64, f64, f64)>,
    /// The location whose scan the room came from, if it did.
    pub room_from: String,
    /// **What each mark stands for on this sheet** (Labs, 2026-10-03): a
    /// mark's name — "2K Blonde" — by its look (`plot::look_key`). Every
    /// lamp drawn with that mark is that kind of light.
    pub legend: Vec<LegendName>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LegendName {
    pub key: String,
    pub name: String,
}

impl Diagram {
    pub fn parse(text: &str) -> Diagram {
        json::parse(text).map(|v| Diagram::from_json(&v)).unwrap_or_default()
    }

    pub fn from_json(v: &Json) -> Diagram {
        let mut d = Diagram::default();
        if let Some(els) = v.get("els").and_then(|e| e.as_array()) {
            let mut seen = std::collections::HashSet::new();
            for e in els {
                if let Some(el) = El::from_json(e) {
                    if seen.insert(el.id.clone()) {
                        d.els.push(el);
                    }
                }
            }
        }
        if let Some(s) = v.get("settings") {
            let b = |k: &str, dv: bool| s.get(k).and_then(|x| x.as_bool()).unwrap_or(dv);
            let def = Settings::default();
            d.settings = Settings {
                units: match s.get("units").and_then(|u| u.as_str()) {
                    Some("m") => "m".into(),
                    _ => "ft".into(),
                },
                grid: b("grid", def.grid),
                snap: b("snap", def.snap),
                dims: b("dims", def.dims),
                all_lengths: b("all_lengths", def.all_lengths),
                sketch: b("sketch", def.sketch),
                cones: b("cones", def.cones),
                beams: b("beams", def.beams),
                labels: b("labels", def.labels),
                step: s
                    .get("step")
                    .and_then(|x| x.as_f64())
                    .filter(|x| x.is_finite() && *x > 0.01)
                    .map(|x| x.min(100.0))
                    .unwrap_or(def.step),
                north: s.get("north").and_then(|x| x.as_f64()).filter(|x| x.is_finite()).map(norm_deg).unwrap_or(0.0),
                sun: b("sun", def.sun),
                sun_rays: b("sun_rays", def.sun_rays),
                sun_date: s.str_field("sun_date"),
                sun_time: s.str_field("sun_time"),
                sun_tz: s.get("sun_tz").and_then(|x| x.as_f64()).filter(|x| x.is_finite() && x.abs() <= 16.0 * 60.0),
                levels: b("levels", def.levels),
                light_units: match s.get("light_units").and_then(|u| u.as_str()) {
                    Some(u @ ("lux" | "fc")) => u.into(),
                    _ => def.light_units.clone(),
                },
                iso: levels::within(s.get("iso"), 3.0, 409_600.0, def.iso),
                shutter: levels::within(s.get("shutter"), 1.0, 8_000.0, def.shutter),
                stop: levels::within(s.get("stop"), 0.5, 64.0, def.stop),
                ambient: levels::within(s.get("ambient"), 0.0, 200_000.0, def.ambient),
                sun_lux: levels::within(s.get("sun_lux"), 0.0, 200_000.0, def.sun_lux),
                // Always a plot: the picture style is retired (his call,
                // 2026-10-03; archive/picture-style). A plan that said
                // `picture` opens as a plot.
                style: def.style.clone(),
                colours: match s.get("colours") {
                    Some(Json::Object(pairs)) => pairs
                        .iter()
                        .filter(|(k, _)| PLOT_COLOURS.contains(&k.as_str()))
                        .filter_map(|(k, v)| {
                            let h = v.as_str()?.trim();
                            let ok = h.len() == 7 && h.starts_with('#') && h[1..].chars().all(|c| c.is_ascii_hexdigit());
                            ok.then(|| (k.clone(), h.to_uppercase()))
                        })
                        .collect(),
                    _ => Vec::new(),
                },
                // The sheet. A plan from before reads the paper it always
                // printed on, landscape, legend and notes on, no bar.
                paper: match s.get("paper").and_then(|u| u.as_str()).map(str::trim) {
                    Some(p) if PAPERS.contains(&p) => p.into(),
                    _ => def.paper.clone(),
                },
                orientation: match s.get("orientation").and_then(|u| u.as_str()) {
                    Some("portrait") => "portrait".into(),
                    _ => def.orientation.clone(),
                },
                legend: b("legend", def.legend),
                notes: b("notes", def.notes),
                sheet_notes: s.get("sheet_notes").and_then(|x| x.as_str()).map(|t| t.chars().take(4000).collect::<String>()).unwrap_or_default(),
                scale_bar: b("scale_bar", def.scale_bar),
                fabric: b("fabric", def.fabric),
                measures: b("measures", def.measures),
                lamp_names: b("lamp_names", def.lamp_names),
                typed_labels: b("typed_labels", def.typed_labels),
                caps: b("caps", def.caps),
                counts: b("counts", def.counts),
                unlabeled: b("unlabeled", def.unlabeled),
                free_names: b("free_names", def.free_names),
            };
        }
        if let Some(view) = v.get("view").and_then(|x| x.as_array()) {
            if let (Some(x), Some(y), Some(z)) = (
                view.first().and_then(|a| a.as_f64()),
                view.get(1).and_then(|a| a.as_f64()),
                view.get(2).and_then(|a| a.as_f64()),
            ) {
                if x.is_finite() && y.is_finite() && z.is_finite() && z > 0.0 {
                    d.view = Some((x, y, z));
                }
            }
        }
        d.room_from = v.str_field("room_from");
        if let Some(rows) = v.get("legend").and_then(|l| l.as_array()) {
            for r in rows {
                let (key, name) = (r.str_field("key"), r.str_field("name"));
                if (plot::parse_key(&key).is_some() || plot::colour_key(&key).is_some()) && !name.trim().is_empty() {
                    d.legend.retain(|x| x.key != key);
                    d.legend.push(LegendName { key, name: name.trim().to_string() });
                }
            }
        }
        d
    }

    pub fn to_json(&self) -> Json {
        let mut o = vec![(
            "els".to_string(),
            Json::Array(self.els.iter().map(|e| e.to_json()).collect()),
        )];
        let s = &self.settings;
        let def = Settings::default();
        let mut so: Vec<(String, Json)> = Vec::new();
        if s.units != def.units {
            so.push(("units".into(), Json::text(&s.units)));
        }
        for (k, v, dv) in [
            ("grid", s.grid, def.grid),
            ("snap", s.snap, def.snap),
            ("dims", s.dims, def.dims),
            ("all_lengths", s.all_lengths, def.all_lengths),
            ("sketch", s.sketch, def.sketch),
            ("cones", s.cones, def.cones),
            ("beams", s.beams, def.beams),
            ("labels", s.labels, def.labels),
            ("legend", s.legend, def.legend),
            ("notes", s.notes, def.notes),
            ("scale_bar", s.scale_bar, def.scale_bar),
            ("fabric", s.fabric, def.fabric),
            ("measures", s.measures, def.measures),
            ("lamp_names", s.lamp_names, def.lamp_names),
            ("typed_labels", s.typed_labels, def.typed_labels),
            ("caps", s.caps, def.caps),
            ("counts", s.counts, def.counts),
            ("unlabeled", s.unlabeled, def.unlabeled),
            ("free_names", s.free_names, def.free_names),
        ] {
            if v != dv {
                so.push((k.into(), Json::Bool(v)));
            }
        }
        if s.paper != def.paper {
            so.push(("paper".into(), Json::text(&s.paper)));
        }
        if s.orientation != def.orientation {
            so.push(("orientation".into(), Json::text(&s.orientation)));
        }
        if !s.sheet_notes.is_empty() {
            so.push(("sheet_notes".into(), Json::text(&s.sheet_notes)));
        }
        if (s.step - def.step).abs() > 1e-9 {
            so.push(("step".into(), Json::Number(round(s.step))));
        }
        if s.north.abs() > 1e-9 {
            so.push(("north".into(), Json::Number(round(s.north))));
        }
        if s.sun {
            so.push(("sun".into(), Json::Bool(true)));
        }
        if s.sun_rays {
            so.push(("sun_rays".into(), Json::Bool(true)));
        }
        if !s.sun_date.is_empty() {
            so.push(("sun_date".into(), Json::text(&s.sun_date)));
        }
        if !s.sun_time.is_empty() {
            so.push(("sun_time".into(), Json::text(&s.sun_time)));
        }
        if let Some(tz) = s.sun_tz {
            so.push(("sun_tz".into(), Json::Number(tz)));
        }
        if s.levels {
            so.push(("levels".into(), Json::Bool(true)));
        }
        if s.light_units != def.light_units {
            so.push(("light_units".into(), Json::text(&s.light_units)));
        }
        for (k, v, dv) in [("iso", s.iso, def.iso), ("shutter", s.shutter, def.shutter), ("stop", s.stop, def.stop), ("ambient", s.ambient, def.ambient), ("sun_lux", s.sun_lux, def.sun_lux)] {
            if (v - dv).abs() > 1e-9 {
                so.push((k.into(), Json::Number(round(v))));
            }
        }
        if !s.colours.is_empty() {
            so.push(("colours".into(), Json::Object(s.colours.iter().map(|(k, v)| (k.clone(), Json::text(v))).collect())));
        }
        if !so.is_empty() {
            o.push(("settings".into(), Json::Object(so)));
        }
        if let Some((x, y, z)) = self.view {
            o.push((
                "view".into(),
                Json::Array(vec![Json::Number(round(x)), Json::Number(round(y)), Json::Number(round(z))]),
            ));
        }
        if !self.legend.is_empty() {
            o.push((
                "legend".into(),
                Json::Array(
                    self.legend
                        .iter()
                        .map(|x| {
                            Json::Object(vec![("key".into(), Json::text(&x.key)), ("name".into(), Json::text(&x.name))])
                        })
                        .collect(),
                ),
            ));
        }
        if !self.room_from.is_empty() {
            o.push(("room_from".into(), Json::text(&self.room_from)));
        }
        Json::Object(o)
    }

    pub fn encode(&self) -> String {
        self.to_json().encode()
    }

    pub fn is_empty(&self) -> bool {
        self.els.is_empty()
    }

    pub fn get(&self, id: &str) -> Option<&El> {
        self.els.iter().find(|e| e.id == id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut El> {
        self.els.iter_mut().find(|e| e.id == id)
    }

    /// The camera standing for a shot, if one does.
    pub fn camera_for(&self, shot: &str) -> Option<&El> {
        self.els
            .iter()
            .find(|e| e.kind == Kind::Camera && !shot.is_empty() && e.shot == shot)
    }

    /// The highest beat anything reaches — the end of the scene's blocking.
    pub fn last_beat(&self) -> u32 {
        self.els
            .iter()
            .flat_map(|e| e.beats())
            .max()
            .unwrap_or(1)
            .max(1)
    }

    /// Everything that moves together with these: the ids asked for, and every
    /// other member of any group they are in.
    pub fn with_groups(&self, ids: &[String]) -> Vec<String> {
        let groups: Vec<&str> = self
            .els
            .iter()
            .filter(|e| ids.contains(&e.id) && !e.group.is_empty())
            .map(|e| e.group.as_str())
            .collect();
        self.els
            .iter()
            .filter(|e| ids.contains(&e.id) || (!e.group.is_empty() && groups.contains(&e.group.as_str())))
            .map(|e| e.id.clone())
            .collect()
    }

    /// A fresh id no element here has.
    pub fn fresh_id(&self, kind: Kind) -> String {
        let stem = kind.as_str();
        let mut n = self.els.len() + 1;
        loop {
            let id = format!("{stem}-{n}");
            if self.get(&id).is_none() {
                return id;
            }
            n += 1;
        }
    }

    /// Put a new element where its kind belongs in the stack: above everything
    /// on its own tier and below the tier over it.
    fn insert_at_tier(&mut self, el: El) {
        let tier = el.kind.tier();
        let at = self
            .els
            .iter()
            .rposition(|e| e.kind.tier() <= tier)
            .map(|i| i + 1)
            .unwrap_or(0);
        self.els.insert(at, el);
    }
}

// ---------------------------------------------------------------- edits
//
// Every edit is one of these, handed in as JSON by whichever shell is asking.
// Each returns the ids it made, so a paste or a duplicate can select them.

#[derive(Debug, PartialEq)]
pub enum EditError {
    Unreadable,
    Unknown(String),
    Missing(String),
    /// A picture element naming a file this film has no record of.
    NoSuchPicture(String),
}

impl std::fmt::Display for EditError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EditError::Unreadable => write!(f, "that edit could not be read"),
            EditError::Unknown(op) => write!(f, "no edit called {op}"),
            EditError::Missing(id) => write!(f, "nothing on the plan called {id}"),
            EditError::NoSuchPicture(name) => write!(
                f,
                "this film has no picture {name}. Lay a picture with floor_picture, \
                 which puts the file in the film first — a picture named here by hand \
                 draws on nothing"
            ),
        }
    }
}

/// Apply one edit. `op` is `{"op": "...", ...}`.
///
/// - `add` `{els:[…]}` — new elements; ids are made when missing or taken.
/// - `update` `{id, set:{…}}` or `{ids, set}` — merge keys into each.
/// - `remove` `{ids}`
/// - `move` `{ids, dx, dy}` — groups come along.
/// - `rotate` `{ids, deg, px?, py?}` — about their shared middle unless told.
/// - `order` `{ids, to: front|back|forward|backward}`, or `{ids, to: above|below, next}` — just over or under `next`
/// - `duplicate` `{ids, dx?, dy?}` — the copies are returned.
/// - `group` `{ids, name?}` (named "Group n" if not) / `ungroup` `{ids}`
/// - `align` `{ids, to: left|right|top|bottom|hcentre|vcentre}`
/// - `distribute` `{ids, axis: x|y}`
/// - `flip` `{ids, axis: x|y}`
/// - `beat` `{id, beat, x, y, rot?, pose?}` — set where it stands at a beat:
///   the step on that beat moves, or a new step is made on it.
/// - `unbeat` `{id, beat}` — take away the step on a beat.
/// - `step_add` `{id, after?|before?, turn?, x?, y?, rot?, pose?, beat?}` — a
///   new step after (or before) the step at that letter-order index, after
///   the last if neither; placed a little ahead unless told, and on the next
///   beat unless told (`El::next_beat`).
/// - `step_set` `{id, step, x?, y?, rot?, pose?, beat?, turn?}` — change one
///   step, by letter-order index (the thing itself is one of them). A beat
///   another step holds is traded with it.
/// - `step_remove` `{id, step}` — take one step away.
/// - `swap` `{ids, sym}` — another drawing from the library in its place,
///   keeping where it stands, its name, colour, aim, beats and gels.
/// - `settings` `{set:{…}}`, `view` `{x,y,zoom}`
/// - `clear` — an empty plan.
pub fn apply(d: &mut Diagram, op: &Json) -> Result<Vec<String>, EditError> {
    let was = walls::before(d);
    let poses = rigging::poses(d);
    let pins = arrow_pins(d);
    let made = apply_op(d, op)?;
    // Corners joined to a wall the edit moved go with it, then doors go
    // where their walls went — unless a corner was pulled loose on purpose.
    walls::carry(d, &was, op.get("free").and_then(|f| f.as_bool()) == Some(true));
    rigging::carry(d, &poses, &made);
    settle_aims(d);
    loosen_arrows(d, &pins, op);
    settle_arrows(d);
    settle_rulers(d);
    let ties: Vec<String> = d.els.iter().filter(|e| e.kind == Kind::Text).map(|e| e.id.clone()).collect();
    for e in &mut d.els {
        // A label gone lets its lamps go: no tie to words that are not there.
        if !e.tie_to.is_empty() && !ties.contains(&e.tie_to) {
            e.tie_to.clear();
        }
        e.tame();
    }
    Ok(made)
}

/// **Aimed things keep facing what they are aimed at.** A light, camera or
/// person whose `aim` names another piece is turned to face it — where it
/// starts, and at every beat it has, toward where the target is at that
/// beat — after every edit, so moving either one keeps the aim. An aim at
/// something gone, or at itself, lets go.
pub fn settle_aims(d: &mut Diagram) {
    for i in 0..d.els.len() {
        if d.els[i].aim.is_empty() {
            continue;
        }
        let aimer = d.els[i].id.clone();
        let target = d.els.iter().find(|t| t.id == d.els[i].aim && t.id != aimer).cloned();
        let e = &mut d.els[i];
        let Some(t) = target.filter(|_| aims(e.kind)) else {
            e.aim.clear();
            continue;
        };
        let spot = |beat: u32| -> (f64, f64) {
            if t.kind.is_line() {
                t.centre()
            } else {
                let (x, y, _) = t.at_beat(beat);
                (x, y)
            }
        };
        let face = |from: (f64, f64), to: (f64, f64)| -> Option<f64> {
            let (dx, dy) = (to.0 - from.0, to.1 - from.1);
            (dx.hypot(dy) > 1e-6).then(|| norm_deg(dy.atan2(dx).to_degrees()))
        };
        if let Some(r) = face((e.x, e.y), spot(e.beat.max(1))) {
            e.rot = r;
        }
        for b in e.steps.iter_mut() {
            if let Some(r) = face((b.x, b.y), spot(b.beat.max(1))) {
                b.rot = r;
            }
        }
    }
}

/// An arrow's pinned ends as they stood before an edit: the arrow, each
/// end's point, and where the piece it is pinned to stood.
type Pins = Vec<(String, [(f64, f64); 2], [Option<(f64, f64, f64, f64, f64)>; 2])>;

fn arrow_pins(d: &Diagram) -> Pins {
    let pose = |id: &str| d.get(id).map(|t| (t.x, t.y, t.rot, t.x2, t.y2));
    d.els
        .iter()
        .filter(|e| e.kind == Kind::Arrow && (!e.start_on.is_empty() || !e.end_on.is_empty()))
        .map(|e| {
            let on = |id: &str| if id.is_empty() { None } else { pose(id) };
            (e.id.clone(), [(e.x, e.y), (e.x2, e.y2)], [on(&e.start_on), on(&e.end_on)])
        })
        .collect()
}

/// Whether an edit names a field anywhere in it — a batch included.
fn mentions(op: &Json, key: &str) -> bool {
    match op {
        Json::Object(pairs) => pairs.iter().any(|(k, v)| k == key || mentions(v, key)),
        Json::Array(items) => items.iter().any(|v| mentions(v, key)),
        _ => false,
    }
}

/// **Dragging a pinned end off frees it.** An end the edit moved by hand —
/// the end dragged away, the whole arrow moved — while the piece it was
/// pinned to stayed put lets go of that piece. An edit that names the pin
/// itself (`start_on`, `end_on`) is taken at its word.
fn loosen_arrows(d: &mut Diagram, before: &Pins, op: &Json) {
    let named = [mentions(op, "start_on"), mentions(op, "end_on")];
    for (id, ends, poses) in before {
        let now: Vec<Option<(f64, f64, f64, f64, f64)>> = {
            let Some(e) = d.get(id) else { continue };
            [&e.start_on, &e.end_on].iter().map(|t| d.get(t).map(|t| (t.x, t.y, t.rot, t.x2, t.y2))).collect()
        };
        let Some(e) = d.get_mut(id) else { continue };
        let points = [(e.x, e.y), (e.x2, e.y2)];
        for i in 0..2 {
            if named[i] {
                continue;
            }
            let moved = (points[i].0 - ends[i].0).hypot(points[i].1 - ends[i].1) > 1e-6;
            let stayed = poses[i].is_some() && poses[i] == now[i];
            if moved && stayed {
                if i == 0 {
                    e.start_on.clear();
                } else {
                    e.end_on.clear();
                }
            }
        }
    }
}

/// How far short of a piece's outline a pinned arrow stops, metres.
pub const PIN_GAP: f64 = 0.06;

/// **Pinned arrows follow what they point at.** Each pinned end goes to
/// the outline of its piece, on the line from the arrow's other end (or
/// the middle of the piece that end is pinned to) — so the head stops at
/// the edge rather than in the middle, and a note's arrows fan out to
/// several pieces. A pin to something gone, to itself or to another arrow
/// lets go.
pub fn settle_arrows(d: &mut Diagram) {
    for i in 0..d.els.len() {
        let e = &d.els[i];
        if e.kind != Kind::Arrow || (e.start_on.is_empty() && e.end_on.is_empty()) {
            continue;
        }
        let find = |id: &str| -> Option<El> {
            (!id.is_empty()).then(|| d.els.iter().find(|t| t.id == id && t.id != e.id && t.kind != Kind::Arrow).cloned()).flatten()
        };
        let (a, b) = (find(&e.start_on), find(&e.end_on));
        let anchor_a = a.as_ref().map(pin_middle).unwrap_or((e.x, e.y));
        let anchor_b = b.as_ref().map(pin_middle).unwrap_or((e.x2, e.y2));
        // A bent arrow leaves each end toward its bend.
        let (ref_a, ref_b) = if e.curve.abs() > 1e-6 {
            let (mx, my) = ((anchor_a.0 + anchor_b.0) / 2.0, (anchor_a.1 + anchor_b.1) / 2.0);
            let (dx, dy) = (anchor_b.0 - anchor_a.0, anchor_b.1 - anchor_a.1);
            let len = dx.hypot(dy).max(1e-9);
            let c = (mx - dy / len * e.curve * 2.0, my + dx / len * e.curve * 2.0);
            (c, c)
        } else {
            (anchor_b, anchor_a)
        };
        let start = a.as_ref().map(|t| pin_point(t, ref_a));
        let end = b.as_ref().map(|t| pin_point(t, ref_b));
        let e = &mut d.els[i];
        if a.is_none() {
            e.start_on.clear();
        }
        if b.is_none() {
            e.end_on.clear();
        }
        if let Some((x, y)) = start {
            (e.x, e.y) = (x, y);
        }
        if let Some((x, y)) = end {
            (e.x2, e.y2) = (x, y);
        }
    }
}

/// **A ruler's locked markers stand on what they are locked to** — the
/// middle of the person or object — wherever it has gone. A lock to
/// something gone, to the ruler itself, or to another ruler or arrow lets go.
/// The list of locks always has one entry per marker.
pub fn settle_rulers(d: &mut Diagram) {
    for i in 0..d.els.len() {
        if d.els[i].kind != Kind::Measure {
            continue;
        }
        let mut c = walls::corners(&d.els[i]);
        let mut pins = d.els[i].pins.clone();
        pins.resize(c.len(), String::new());
        let me = d.els[i].id.clone();
        for (k, pin) in pins.iter_mut().enumerate() {
            if pin.is_empty() {
                continue;
            }
            match d.els.iter().find(|t| t.id == *pin && t.id != me && !matches!(t.kind, Kind::Measure | Kind::Arrow)) {
                Some(t) => c[k] = pin_middle(t),
                None => pin.clear(),
            }
        }
        let e = &mut d.els[i];
        if pins.iter().all(|p| p.is_empty()) {
            pins.clear();
        }
        e.pins = pins;
        walls::set_corners(e, c);
    }
}

/// Words' box on the plan, metres: their middle, and across × down before
/// turning.
fn words_box(t: &El) -> ((f64, f64), f64, f64) {
    let size = if t.size > 0.0 { t.size } else { 14.0 } / 40.0;
    let (w, h) = render::words_box_pt(if t.text.is_empty() { " " } else { &t.text }, size);
    let shift = match t.align.as_str() {
        "left" => w / 2.0,
        "right" => -w / 2.0,
        _ => 0.0,
    };
    let r = t.rot.to_radians();
    ((t.x + r.cos() * shift, t.y + r.sin() * shift), w, h)
}

/// The middle a pinned arrow aims for.
fn pin_middle(t: &El) -> (f64, f64) {
    if t.kind == Kind::Text {
        words_box(t).0
    } else {
        t.centre()
    }
}

/// Where a line from `toward` meets a piece's outline, a hair outside it.
pub fn pin_point(t: &El, toward: (f64, f64)) -> (f64, f64) {
    if t.kind.is_line() || t.kind.is_polyline() {
        let pts: Vec<(f64, f64)> = if t.kind.is_line() { render::line_points(t) } else { t.points.clone() };
        let mut best = (pin_middle(t), f64::MAX);
        for w in pts.windows(2) {
            let (a, b) = (w[0], w[1]);
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let l2 = dx * dx + dy * dy;
            let k = if l2 < 1e-12 { 0.0 } else { (((toward.0 - a.0) * dx + (toward.1 - a.1) * dy) / l2).clamp(0.0, 1.0) };
            let p = (a.0 + dx * k, a.1 + dy * k);
            let dist = (p.0 - toward.0).hypot(p.1 - toward.1);
            if dist < best.1 {
                best = (p, dist);
            }
        }
        return best.0;
    }
    let (c, w, h) = if t.kind == Kind::Text {
        words_box(t)
    } else {
        let (w, h) = t.footprint(1);
        ((t.x, t.y), w, h)
    };
    let (dx, dy) = (toward.0 - c.0, toward.1 - c.1);
    let len = dx.hypot(dy);
    if len < 1e-9 {
        return c;
    }
    let (ux, uy) = (dx / len, dy / len);
    let r = t.rot.to_radians();
    let (lx, ly) = (ux * r.cos() + uy * r.sin(), -ux * r.sin() + uy * r.cos());
    let (hw, hh) = ((w / 2.0).max(0.02), (h / 2.0).max(0.02));
    let round = t.kind == Kind::Cast || (t.kind == Kind::Shape && matches!(t.sym.as_str(), "ellipse" | "circle"));
    let reach = if round {
        1.0 / ((lx / hw).powi(2) + (ly / hh).powi(2)).sqrt()
    } else {
        let tx = if lx.abs() > 1e-9 { hw / lx.abs() } else { f64::MAX };
        let ty = if ly.abs() > 1e-9 { hh / ly.abs() } else { f64::MAX };
        tx.min(ty)
    };
    let k = reach + PIN_GAP;
    (c.0 + ux * k, c.1 + uy * k)
}

/// What can be aimed: the things that face a way and look or shine at
/// something.
pub fn aims(k: Kind) -> bool {
    matches!(k, Kind::Light | Kind::Camera | Kind::Cast)
}

/// A group id no piece here carries yet.
fn fresh_group(d: &Diagram) -> String {
    let mut gid = format!("g{}", d.els.len() + d.els.iter().filter(|e| !e.group.is_empty()).count());
    while d.els.iter().any(|e| e.group == gid) {
        gid.push('x');
    }
    gid
}

fn apply_op(d: &mut Diagram, op: &Json) -> Result<Vec<String>, EditError> {
    let name = op.get("op").and_then(|o| o.as_str()).ok_or(EditError::Unreadable)?;
    let ids = |key: &str| -> Vec<String> {
        op.get(key)
            .and_then(|x| x.as_array())
            .map(|a| a.iter().filter_map(|i| i.as_str().map(String::from)).collect())
            .or_else(|| op.get("id").and_then(|x| x.as_str()).map(|s| vec![s.to_string()]))
            .unwrap_or_default()
    };
    let num = |key: &str| op.get(key).and_then(|x| x.as_f64()).filter(|x| x.is_finite());
    // `alone`: one piece picked inside its group (a double-click on the
    // Mac) is moved, turned or flipped by itself, not with its group.
    let alone = op.get("alone").and_then(|a| a.as_bool()) == Some(true);
    let grouped = |d: &Diagram, ids: Vec<String>| if alone { ids } else { d.with_groups(&ids) };
    match name {
        "add" => {
            let els = op.get("els").and_then(|e| e.as_array()).ok_or(EditError::Unreadable)?;
            let mut made = Vec::new();
            // A piece that comes with an id already taken — a paste of
            // what is still on the plan — takes a new one; what aims at it
            // or rides it in the same add follows it to the copy.
            let mut renamed: Vec<(String, String)> = Vec::new();
            // `fresh`: every piece takes a new id, its own only naming the
            // ties inside the add (a favorite group put down).
            let fresh_all = op.get("fresh").and_then(|f| f.as_bool()) == Some(true);
            for e in els {
                let Some(mut el) = parse_new(e, d) else { continue };
                if el.id.is_empty() || fresh_all || d.get(&el.id).is_some() {
                    let fresh = d.fresh_id(el.kind);
                    if !el.id.is_empty() {
                        renamed.push((el.id.clone(), fresh.clone()));
                    }
                    el.id = fresh;
                }
                made.push(el.id.clone());
                d.insert_at_tier(el);
            }
            if !renamed.is_empty() {
                for el in d.els.iter_mut().filter(|e| made.contains(&e.id)) {
                    if let Some((_, to)) = renamed.iter().find(|(from, _)| *from == el.aim) {
                        el.aim = to.clone();
                    }
                    if let Some((_, to)) = renamed.iter().find(|(from, _)| *from == el.rig_on) {
                        el.rig_on = to.clone();
                    }
                    if let Some((_, to)) = renamed.iter().find(|(from, _)| *from == el.tie_to) {
                        el.tie_to = to.clone();
                    }
                    // A pasted arrow stays pinned to what was pasted with
                    // it, and lets go of what was not.
                    if el.kind == Kind::Arrow && renamed.iter().any(|(_, to)| *to == el.id) {
                        for pin in [&mut el.start_on, &mut el.end_on] {
                            match renamed.iter().find(|(from, _)| from == pin) {
                                Some((_, to)) => *pin = to.clone(),
                                None => pin.clear(),
                            }
                        }
                    }
                }
            }
            // Added as one group, named — a room drawn in one drag is
            // "Room", and a click on any wall of it takes the whole room.
            if let Some(gname) = op.get("group_name").and_then(|n| n.as_str()).map(str::trim).filter(|n| !n.is_empty()) {
                if made.len() > 1 {
                    let gid = fresh_group(d);
                    for el in d.els.iter_mut().filter(|e| made.contains(&e.id)) {
                        el.group = gid.clone();
                        el.group_name = gname.to_string();
                    }
                }
            }
            Ok(made)
        }
        "update" => {
            let set = op.get("set").ok_or(EditError::Unreadable)?;
            let targets = ids("ids");
            for id in &targets {
                let el = d.get(id).ok_or_else(|| EditError::Missing(id.clone()))?;
                // A wall with corners told only where its ends go (an older
                // shell, or the portal's end handles): its first or last
                // corner moves, and the rest stay.
                let owned;
                let set = if el.kind == Kind::Wall && el.points.len() >= 2 && set.get("points").is_none()
                    && ["x", "y", "x2", "y2"].iter().any(|k| set.get(k).is_some())
                {
                    let mut c = walls::corners(el);
                    let last = c.len() - 1;
                    let f = |k: &str, v: f64| set.get(k).and_then(|x| x.as_f64()).filter(|x| x.is_finite()).unwrap_or(v);
                    c[0] = (f("x", c[0].0), f("y", c[0].1));
                    c[last] = (f("x2", c[last].0), f("y2", c[last].1));
                    let pts = Json::Array(c.iter().map(|(x, y)| Json::Array(vec![Json::Number(*x), Json::Number(*y)])).collect());
                    owned = merge_plain(set, &Json::Object(vec![("points".into(), pts)]));
                    &owned
                } else {
                    set
                };
                let was = (el.x, el.y, el.w, el.h);
                let merged = merge(&el.to_json(), set, id, el.kind);
                if let Some(mut new) = El::from_json(&merged) {
                    if symbols::is_half_round(&new) {
                        keep_half(&mut new, was, set, d.settings.snap && d.settings.units == "ft");
                    }
                    // **A frame sized with Snap on is whole feet** in a film
                    // in feet, Scenario's way: "resize to whole numbers".
                    if frame::is_frame(&new) && d.settings.snap && d.settings.units == "ft" {
                        let whole = |m: f64| (m / FOOT).round().max(1.0) * FOOT;
                        if set.get("h").is_some() {
                            new.h = whole(new.h);
                        }
                        if set.get("tall").is_some() && new.tall > 0.0 {
                            new.tall = whole(new.tall);
                        }
                        frame::settle(&mut new);
                    }
                    // **A lamp sized is drawn bigger** (his note, 2026-10-17).
                    lampscale::resized(el, &mut new, set);
                    *d.get_mut(id).unwrap() = new;
                }
            }
            // **A shared label's notes and modifiers are the label's** (his
            // ask, 2026-10-04): a note, gels, Off or a Type set on one of
            // its lamps is set on all of them.
            let shared_keys = ["label", "caption", "gels", "action", "existing", "practical"];
            if shared_keys.iter().any(|k| set.get(k).is_some()) {
                for id in &targets {
                    let Some(e) = d.get(id).filter(|e| !e.tie_to.is_empty() && plot::can_share(e)).cloned() else { continue };
                    // **Any piece's Note** (his ask, 2026-10-05: frames and
                    // any object share labels): the Note set on one is the
                    // Note of all of them — a lamp's and a frame's in
                    // `label`, anything else's in `caption`.
                    let noted = if plot::is_lamp(&e) || frame::is_frame(&e) { set.get("label").is_some() } else { set.get("caption").is_some() };
                    if noted {
                        let note = render::note_of(&e).to_string();
                        for o in d.els.iter_mut().filter(|o| o.tie_to == e.tie_to && o.id != e.id && plot::can_share(o)) {
                            if plot::is_lamp(o) || frame::is_frame(o) { o.label = note.clone(); } else { o.caption = note.clone(); }
                        }
                    }
                    if !plot::is_lamp(&e) {
                        continue;
                    }
                    for o in d.els.iter_mut().filter(|o| o.tie_to == e.tie_to && o.id != e.id && plot::is_lamp(o)) {
                        if set.get("gels").is_some() { o.gels = e.gels.clone(); }
                        if set.get("action").is_some() { o.action = e.action.clone(); }
                        if set.get("existing").is_some() || set.get("practical").is_some() {
                            o.existing = e.existing;
                            o.practical = e.practical;
                        }
                    }
                }
            }
            // A new symbol for one lamp of a shared label is for that lamp
            // alone (2026-10-05): the label is not one unit.
            Ok(Vec::new())
        }
        "remove" => {
            let targets = ids("ids");
            d.els.retain(|e| !targets.contains(&e.id));
            Ok(Vec::new())
        }
        "move" => {
            let (dx, dy) = (num("dx").unwrap_or(0.0), num("dy").unwrap_or(0.0));
            let targets = grouped(d, ids("ids"));
            for el in d.els.iter_mut().filter(|e| targets.contains(&e.id) && !e.locked) {
                // Each step is a place of its own, picked and moved on its
                // own (his note, 2026-09-28, of A → B's far end): moving the
                // thing leaves the rest where they stand.
                let far = std::mem::take(&mut el.steps);
                el.translate(dx, dy);
                el.steps = far;
            }
            Ok(Vec::new())
        }
        "rotate" => {
            let deg = num("deg").unwrap_or(0.0);
            let targets = grouped(d, ids("ids"));
            let (px, py) = match (num("px"), num("py")) {
                (Some(x), Some(y)) => (x, y),
                _ => middle_of(d, &targets),
            };
            for el in d.els.iter_mut().filter(|e| targets.contains(&e.id) && !e.locked) {
                el.rotate_about(deg, px, py);
            }
            Ok(Vec::new())
        }
        "flip" => {
            let horizontal = op.get("axis").and_then(|a| a.as_str()) != Some("y");
            let targets = grouped(d, ids("ids"));
            let (px, py) = middle_of(d, &targets);
            for el in d.els.iter_mut().filter(|e| targets.contains(&e.id) && !e.locked) {
                mirror(el, horizontal, px, py);
            }
            Ok(Vec::new())
        }
        "order" => {
            let targets = ids("ids");
            let to = op.get("to").and_then(|t| t.as_str()).unwrap_or("front");
            if to == "above" || to == "below" {
                // Dragged in the Layers list: just over or under one piece.
                let next = op.get("next").and_then(|t| t.as_str()).unwrap_or("").to_string();
                restack_by(d, &targets, &next, to == "above");
            } else {
                reorder(d, &targets, to);
            }
            Ok(Vec::new())
        }
        "duplicate" => {
            // A stand's lamp comes with it, rigged to the copy.
            let targets = rigging::with_riders(d, &grouped(d, ids("ids")));
            // `x`, `y`: the copies' middle put there — a paste where the
            // pointer is. Else `dx`, `dy` off the originals.
            let (dx, dy) = match (num("x"), num("y")) {
                (Some(x), Some(y)) => {
                    let (mx, my) = middle_of(d, &targets);
                    (x - mx, y - my)
                }
                _ => (num("dx").unwrap_or(0.5), num("dy").unwrap_or(0.5)),
            };
            let mut regroup: Vec<(String, String)> = Vec::new();
            let mut made = Vec::new();
            let copies: Vec<El> = d.els.iter().filter(|e| targets.contains(&e.id)).cloned().collect();
            let mut pairs: Vec<(String, String)> = Vec::new();
            for mut el in copies {
                let old = el.id.clone();
                el.id = d.fresh_id(el.kind);
                pairs.push((old, el.id.clone()));
                el.translate(dx, dy);
                // A copy of a shot's camera is a new camera, not a second
                // place for the same shot.
                el.shot.clear();
                // A member copied inside its group stays in that group.
                if !el.group.is_empty() && !alone {
                    let fresh = match regroup.iter().find(|(old, _)| *old == el.group) {
                        Some((_, new)) => new.clone(),
                        None => {
                            let new = format!("{}-copy{}", el.group, d.els.len());
                            regroup.push((el.group.clone(), new.clone()));
                            new
                        }
                    };
                    el.group = fresh;
                }
                made.push(el.id.clone());
                d.els.push(el);
            }
            rigging::rerig_copies(d, &targets, &made);
            // A copied arrow stays pinned to what was copied with it, and
            // lets go of what was not.
            for el in d.els.iter_mut().filter(|e| e.kind == Kind::Arrow && made.contains(&e.id)) {
                for pin in [&mut el.start_on, &mut el.end_on] {
                    match pairs.iter().find(|(old, _)| old == pin) {
                        Some((_, new)) => *pin = new.clone(),
                        None => pin.clear(),
                    }
                }
            }
            // **Copies keep their aim**: aimed at something copied with
            // them, the copy aims at that thing's copy; else at the same
            // thing the original faces.
            let originals: Vec<String> = d.els.iter().filter(|e| targets.contains(&e.id)).map(|e| e.id.clone()).collect();
            for e in d.els.iter_mut().filter(|e| made.contains(&e.id)) {
                if let Some(i) = originals.iter().position(|o| *o == e.aim) {
                    e.aim = made[i].clone();
                }
            }
            Ok(made)
        }
        "swap" => {
            let sym = op.get("sym").and_then(|s| s.as_str()).ok_or(EditError::Unreadable)?;
            rigging::swap(d, &ids("ids"), sym);
            Ok(Vec::new())
        }
        "group" => {
            let targets = ids("ids");
            if targets.len() < 2 {
                return Ok(Vec::new());
            }
            let gid = fresh_group(d);
            // Named in the order groups are made — "Group 3" — unless the op
            // names it; renamed by an update of `group_name` on its members.
            let name = match op.get("name").and_then(|n| n.as_str()).map(str::trim).filter(|n| !n.is_empty()) {
                Some(n) => n.to_string(),
                None => {
                    let mut seen: Vec<&str> = d.els.iter().filter(|e| !e.group.is_empty()).map(|e| e.group.as_str()).collect();
                    seen.sort_unstable();
                    seen.dedup();
                    let mut n = seen.len() + 1;
                    while d.els.iter().any(|e| e.group_name == format!("Group {n}")) {
                        n += 1;
                    }
                    format!("Group {n}")
                }
            };
            for el in d.els.iter_mut().filter(|e| targets.contains(&e.id)) {
                el.group = gid.clone();
                el.group_name = name.clone();
            }
            Ok(vec![gid])
        }
        "ungroup" => {
            let targets = d.with_groups(&ids("ids"));
            for el in d.els.iter_mut().filter(|e| targets.contains(&e.id)) {
                el.group.clear();
                el.group_name.clear();
            }
            Ok(Vec::new())
        }
        "align" => {
            let targets = ids("ids");
            let to = op.get("to").and_then(|t| t.as_str()).unwrap_or("left");
            align(d, &targets, to);
            Ok(Vec::new())
        }
        "distribute" => {
            let targets = ids("ids");
            let horizontal = op.get("axis").and_then(|a| a.as_str()) != Some("y");
            distribute(d, &targets, horizontal);
            Ok(Vec::new())
        }
        "beat" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?;
            let beat = num("beat").unwrap_or(1.0).max(1.0) as u32;
            let (x, y) = (num("x").ok_or(EditError::Unreadable)?, num("y").ok_or(EditError::Unreadable)?);
            let el = d.get_mut(id).ok_or_else(|| EditError::Missing(id.into()))?;
            let rot = norm_deg(num("rot").unwrap_or_else(|| el.at_beat(beat).2));
            let pose = op.get("pose").and_then(|p| p.as_str()).map(Pose::parse);
            // The step on this beat, if it has one; else a new step on it,
            // put in letter order before the first step on a later beat.
            let seq = el.sequence();
            match seq.iter().position(|p| p.beat == beat) {
                Some(i) => el.place_step(i, Some(x), Some(y), Some(rot), pose),
                None if beat == 1 && el.steps.is_empty() => el.place_step(el.lead, Some(x), Some(y), Some(rot), None),
                None => {
                    let at = seq.iter().position(|p| p.beat > beat).unwrap_or(seq.len());
                    el.insert_step(at, Step { x, y, rot, pose: pose.unwrap_or(Pose::Same), turn: false, beat });
                }
            }
            Ok(Vec::new())
        }
        "unbeat" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?;
            let beat = num("beat").unwrap_or(0.0) as u32;
            let el = d.get_mut(id).ok_or_else(|| EditError::Missing(id.into()))?;
            if let Some(i) = el.sequence().iter().position(|p| p.beat == beat && beat > 0 && !p.home) {
                el.remove_step(i);
            }
            Ok(Vec::new())
        }
        "step_add" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?;
            let el = d.get_mut(id).ok_or_else(|| EditError::Missing(id.into()))?;
            if !el.kind.moves() {
                return Ok(Vec::new());
            }
            let last = el.steps.len();
            let before = num("before").map(|n| (n.max(0.0) as usize).min(last));
            let anchor = before.unwrap_or_else(|| num("after").map(|n| (n.max(0.0) as usize).min(last)).unwrap_or(last));
            let at = if before.is_some() { anchor } else { anchor + 1 };
            let turn = op.get("turn").and_then(|t| t.as_bool()) == Some(true);
            let from = el.sequence()[anchor].clone();
            let ahead = if before.is_some() { -1.0 } else { 1.0 };
            // A turn starts a quarter turn round; a move a couple of metres
            // on the way the step it follows faces (back, for one before),
            // to be dragged where it really goes.
            let (gx, gy, grot) = if turn {
                (from.x, from.y, norm_deg(from.rot + 90.0 * ahead))
            } else {
                let far = (el.w.max(el.h) * 2.5).max(1.5) * ahead;
                let r = from.rot.to_radians();
                (from.x + r.cos() * far, from.y + r.sin() * far, from.rot)
            };
            let step = Step {
                x: num("x").unwrap_or(gx),
                y: num("y").unwrap_or(gy),
                rot: norm_deg(num("rot").unwrap_or(grot)),
                pose: Pose::parse(op.get("pose").and_then(|p| p.as_str()).unwrap_or("")),
                turn,
                beat: 0,
            };
            el.insert_step(at, step);
            match num("beat") {
                Some(b) => el.give_beat(at, b.max(0.0) as u32),
                None => el.next_beat(at),
            }
            Ok(Vec::new())
        }
        "step_set" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?;
            let el = d.get_mut(id).ok_or_else(|| EditError::Missing(id.into()))?;
            let i = num("step").ok_or(EditError::Unreadable)?.max(0.0) as usize;
            if i > el.steps.len() {
                return Err(EditError::Missing(format!("{id} step {}", letter(i))));
            }
            let pose = op.get("pose").and_then(|p| p.as_str()).map(Pose::parse);
            el.place_step(i, num("x"), num("y"), num("rot").map(norm_deg), pose);
            if let (Some(k), Some(t)) = (el.step_index(i), op.get("turn").and_then(|t| t.as_bool())) {
                el.steps[k].turn = t;
            }
            if let Some(b) = num("beat") {
                el.give_beat(i, b.max(0.0) as u32);
            }
            Ok(Vec::new())
        }
        "step_remove" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?;
            let el = d.get_mut(id).ok_or_else(|| EditError::Missing(id.into()))?;
            let i = num("step").ok_or(EditError::Unreadable)?.max(0.0) as usize;
            el.remove_step(i);
            Ok(Vec::new())
        }
        "settings" => {
            let set = op.get("set").ok_or(EditError::Unreadable)?;
            let was_units = d.settings.units.clone();
            let mut current = d.to_json();
            let merged_settings = match current.get("settings") {
                Some(s) => merge_plain(s, set),
                None => set.clone(),
            };
            if let Json::Object(pairs) = &mut current {
                pairs.retain(|(k, _)| k != "settings");
                pairs.push(("settings".into(), merged_settings));
            }
            d.settings = Diagram::from_json(&current).settings;
            // Feet and metres each have their own grid: a foot, or half a
            // metre — unless the same edit names a step of its own.
            if d.settings.units != was_units && set.get("step").is_none() {
                d.settings.step = unit_step(&d.settings.units);
            }
            // Made a sketch: the plan's measuring things go; made a plan
            // again, the grid and Snap come back.
            if let Some(on) = set.get("sketch").and_then(|v| v.as_bool()) {
                d.settings.grid = !on;
                d.settings.snap = !on;
                if on {
                    d.settings.dims = false;
                    d.settings.sun = false;
                }
            }
            Ok(Vec::new())
        }
        // **One label for these lamps** (`share_label` `{ids}`): a label
        // among the ids is the one they share; else new words are put down
        // over the lamps, empty so the plot writes what they are. Answers
        // the label's id.
        "share_label" => {
            let want: Vec<String> = op.get("ids").and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
            // **Any piece, not only lamps** (his ask, 2026-10-05): frames,
            // grip, set pieces, cameras, people.
            let lamps: Vec<String> = d.els.iter().filter(|e| want.contains(&e.id) && plot::can_share(e)).map(|e| e.id.clone()).collect();
            if lamps.is_empty() {
                return Err(EditError::Unreadable);
            }
            // New words: put down clear of the plan's others once the lamps
            // are tied (below).
            let mut fresh: Option<Vec<(f64, f64)>> = None;
            let label = match d.els.iter().find(|e| want.contains(&e.id) && e.kind == Kind::Text) {
                Some(t) => t.id.clone(),
                // **One join rule** (Back to Paper, Batch 2): lamps picked
                // with a lamp that already shares a label join that label,
                // the way a label picked with them would.
                None if d.els.iter().any(|e| lamps.contains(&e.id) && render::tied_to(d, e).is_some()) => {
                    let first = d.els.iter().filter(|e| lamps.contains(&e.id)).find(|e| !e.tie_to.is_empty() && d.get(&e.tie_to).map(|t| t.kind == Kind::Text).unwrap_or(false)).unwrap();
                    first.tie_to.clone()
                }
                None => {
                    // A lamp by its spot; a frame, a sofa, anything with a
                    // size of its own by its corners, so the words land
                    // clear of it rather than on its edge.
                    let pts: Vec<(f64, f64)> = d
                        .els
                        .iter()
                        .filter(|e| lamps.contains(&e.id))
                        .flat_map(|e| {
                            if plot::is_lamp(e) && !plot::points_down(e) {
                                vec![(e.x, e.y)]
                            } else {
                                let (hw, hh, r) = (e.w / 2.0, e.h / 2.0, e.rot.to_radians());
                                [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
                                    .iter()
                                    .map(|(a, b)| (e.x + a * r.cos() - b * r.sin(), e.y + a * r.sin() + b * r.cos()))
                                    .collect()
                            }
                        })
                        .collect();
                    let n = pts.len() as f64;
                    let cx = pts.iter().map(|p| p.0).sum::<f64>() / n;
                    let top = pts.iter().map(|p| p.1).fold(f64::MAX, f64::min);
                    let id = d.fresh_id(Kind::Text);
                    let mut t = El::new(Kind::Text, &id);
                    t.x = cx;
                    t.y = top - 1.2;
                    t.size = 12.0;
                    d.els.push(t);
                    fresh = Some(pts);
                    id
                }
            };
            // **One join rule** (Back to Paper, Batch 2): Share Label, the
            // Connector tool drawn from a label onto a lamp, and a label
            // picked with lamps all do the same. The lamps the label
            // already holds are part of it: a lamp joining takes **their**
            // kind (his Ref 1483: they are the same lamp), and its note and
            // gels merge with theirs.
            let held: Vec<String> = d.els.iter().filter(|e| e.tie_to == label && plot::can_share(e) && !lamps.contains(&e.id)).map(|e| e.id.clone()).collect();
            let mut lamps = lamps;
            lamps.splice(0..0, held.iter().cloned());
            // **A shared label never changes a light's symbol or Name**
            // (his call, 2026-10-05, reversing 2026-10-04's Same Lamp): it
            // counts each kind — "2× SkyPanel S60 + 1× LiteMat 4".
            // Nothing he wrote is lost: the label carries every lamp's note
            // and gels, and whatever is done to them.
            let mut notes: Vec<String> = Vec::new();
            let mut gels: Vec<String> = Vec::new();
            let mut action = String::new();
            let in_order: Vec<&El> = lamps.iter().filter_map(|id| d.get(id)).collect();
            for e in in_order {
                let n = render::note_of(e).to_string();
                if !n.is_empty() && !notes.contains(&n) {
                    notes.push(n);
                }
                for g in &e.gels {
                    if !gels.contains(g) {
                        gels.push(g.clone());
                    }
                }
                if action.is_empty() {
                    action = e.action.clone();
                }
            }
            let note = notes.join(" · ");
            for e in d.els.iter_mut().filter(|e| lamps.contains(&e.id)) {
                e.tie_to = label.clone();
                if !plot::is_lamp(e) {
                    if frame::is_frame(e) { e.label = note.clone(); } else { e.caption = note.clone(); }
                    continue;
                }
                e.label = note.clone();
                e.gels = gels.clone();
                if e.existing || e.practical {
                    e.action = action.clone();
                }
            }
            // **New words land clear** (Back to Paper, Batch 2, fix round
            // 2): not on another name, his own Words or a piece — on scene 8
            // they had dropped onto LIGHTING TROUGH, RED CURTAIN BG and
            // ARRI S60C at once. `ppm`: the shell's zoom, so they are kept
            // clear at the size they are drawn.
            if let Some(pts) = fresh {
                let ppm = op.get("ppm").and_then(|v| v.as_f64()).filter(|v| v.is_finite() && *v > 0.0).unwrap_or(0.0);
                // `page`: the zoom is the sheet's, lettered as it letters.
                let page = op.get("page").and_then(|v| v.as_bool()).unwrap_or(false);
                let words = d.get(&label).and_then(|t| render::shared_label_words(d, t)).unwrap_or_default();
                let at = render::clear_spot(d, ppm, page, &words, &pts, &label);
                if let Some(t) = d.els.iter_mut().find(|e| e.id == label) {
                    t.x = at.0;
                    t.y = at.1;
                }
            }
            Ok(vec![label])
        }
        // **Its own label again** (`own_label` `{ids}`): these lamps let go
        // of the label they shared. The label stays — never destroy.
        "own_label" => {
            let want: Vec<String> = op.get("ids").and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
            for e in d.els.iter_mut().filter(|e| want.contains(&e.id) || want.contains(&e.tie_to)) {
                e.tie_to.clear();
            }
            Ok(Vec::new())
        }
        // **Lock a camera to the nearest track** (`ride` `{id}`); `rig_on`
        // "" lets it go.
        "ride" => {
            let id = op.get("id").and_then(|i| i.as_str()).ok_or(EditError::Unreadable)?.to_string();
            if !rigging::ride(d, &id) {
                return Err(EditError::Unreadable);
            }
            Ok(Vec::new())
        }
        // **A mark on this sheet** (`key`, its look): `name` says what kind
        // of light it stands for (empty clears it); `to`, another look,
        // re-marks every lamp drawn with it, its name going too.
        "legend" => {
            let key = op.get("key").and_then(|k| k.as_str()).map(str::trim).unwrap_or("").to_string();
            // A colour's meaning: `colour:added` and a name.
            if plot::colour_key(&key).is_some() {
                let name = op.get("name").and_then(|n| n.as_str()).unwrap_or("").trim().to_string();
                d.legend.retain(|x| x.key != key);
                if !name.is_empty() {
                    d.legend.push(LegendName { key, name });
                }
                return Ok(Vec::new());
            }
            // **A legend line is a Name and its symbol** (his call,
            // 2026-10-05): `name` renames the lamps on that line, `to`
            // gives them another symbol. A key of a look alone reaches the
            // line of that look not named yet, else its first.
            let from = plot::parse_key(&key).ok_or(EditError::Unreadable)?;
            let lines = plot::legend(d);
            let line = lines.iter().find(|x| x.key == key).or_else(|| lines.iter().find(|x| plot::same_symbol(&x.look, &from))).cloned();
            let ids: Vec<String> = line.map(|x| x.ids).unwrap_or_default();
            if let Some(name) = op.get("name").and_then(|n| n.as_str()) {
                for e in d.els.iter_mut().filter(|e| ids.contains(&e.id)) {
                    e.lamp_name = name.trim().to_string();
                }
            }
            if let Some(to) = op.get("to").and_then(|t| t.as_str()) {
                let to = plot::parse_key(to).ok_or(EditError::Unreadable)?;
                for e in d.els.iter_mut().filter(|e| ids.contains(&e.id)) {
                    plot::set_look(e, to);
                }
            }
            Ok(Vec::new())
        }
        // **A piece's Name** (`name_lamp` / `name_piece` `{id, name}`; his
        // calls, 2026-10-15 and 2026-10-17: labels are what he types, on
        // every kind — *"I still can't manually just label a silk"*). This
        // piece alone — never another called the same, never its symbol. A
        // lamp's and a frame's Name is its `lamp_name` (their `label` is
        // their Note), anything else's its `label`. Several lines as typed;
        // empty leaves it with none. `only` is still read and changes nothing.
        "name_lamp" | "name_piece" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?.to_string();
            let e = d.get(&id).ok_or_else(|| EditError::Missing(id.clone()))?;
            if name == "name_lamp" && !plot::is_lamp(e) && !frame::is_frame(e) {
                return Err(EditError::Unreadable);
            }
            let typed = op.get("name").and_then(|n| n.as_str()).unwrap_or("").trim().to_string();
            if let Some(o) = d.get_mut(&id) {
                if plot::is_lamp(o) || frame::is_frame(o) {
                    o.lamp_name = typed;
                } else if matches!(o.kind, Kind::Text | Kind::Note) {
                    o.text = typed;
                } else {
                    o.label = typed;
                }
            }
            Ok(Vec::new())
        }
        // **Send to Set / Send to Plot** (`send_layer` `{ids, to, copy}`,
        // his ask 2026-10-17): the pieces moved to the other view where they
        // stand, turned and named as they were; `copy` leaves them and sends
        // a copy in place. Pieces that cannot go (walls, doors, the street)
        // are passed over. Answers the copies' ids.
        "send_layer" => {
            let to = match op.get("to").and_then(|t| t.as_str()) {
                Some(SET_LAYER) => SET_LAYER,
                Some(PLOT_LAYER) => PLOT_LAYER,
                _ => return Err(EditError::Unreadable),
            };
            let want: Vec<String> = ids("ids").into_iter().filter(|id| d.get(id).map(can_send).unwrap_or(false)).collect();
            if want.is_empty() {
                return Err(EditError::Unreadable);
            }
            let copy = op.get("copy").and_then(|c| c.as_bool()) == Some(true);
            let targets = if copy {
                let ids = Json::Array(want.iter().map(|i| Json::text(i.as_str())).collect());
                let dup = Json::Object(vec![
                    ("op".into(), Json::text("duplicate")),
                    ("ids".into(), ids),
                    ("dx".into(), Json::Number(0.0)),
                    ("dy".into(), Json::Number(0.0)),
                    ("alone".into(), Json::Bool(true)),
                ]);
                let made = apply_op(d, &dup)?;
                // A copy shares no label and rides nothing of the other view.
                for e in d.els.iter_mut().filter(|e| made.contains(&e.id)) {
                    e.tie_to.clear();
                }
                made
            } else {
                want
            };
            for e in d.els.iter_mut().filter(|e| targets.contains(&e.id)) {
                send_to(e, to);
            }
            Ok(if copy { targets } else { Vec::new() })
        }
        // **Attach to Photo** (`attach_marks` `{id}`, 2026-10-15): the marks
        // lying wholly on a picture moved onto it (`photomarks::attach`).
        "attach_marks" => {
            let id = op.get("id").and_then(|x| x.as_str()).ok_or(EditError::Unreadable)?.to_string();
            if d.get(&id).map(|e| e.kind != Kind::Image).unwrap_or(true) {
                return Err(EditError::Missing(id));
            }
            photomarks::attach(d, &id);
            Ok(Vec::new())
        }
        "view" => {
            if let (Some(x), Some(y), Some(z)) = (num("x"), num("y"), num("zoom")) {
                if z > 0.0 {
                    d.view = Some((x, y, z));
                }
            }
            Ok(Vec::new())
        }
        "batch" => {
            // Several edits as one: a drag of three people at beat 2 is three
            // `beat` edits and one thing to take back.
            let ops = op.get("ops").and_then(|o| o.as_array()).ok_or(EditError::Unreadable)?;
            let mut made = Vec::new();
            for inner in ops {
                if inner.get("op").and_then(|o| o.as_str()) == Some("batch") {
                    return Err(EditError::Unreadable);
                }
                made.extend(apply(d, inner)?);
            }
            Ok(made)
        }
        name if name.starts_with("wall_") || name == "path_as" => walls::edit(d, name, op),
        "clear" => {
            d.els.clear();
            d.room_from.clear();
            Ok(Vec::new())
        }
        other => Err(EditError::Unknown(other.into())),
    }
}

/// A new element from what a shell handed in: the kind's defaults, with the
/// keys given laid over them.
fn parse_new(e: &Json, d: &Diagram) -> Option<El> {
    let kind = Kind::parse(e.get("kind")?.as_str()?)?;
    let id = e.get("id").and_then(|i| i.as_str()).unwrap_or("").to_string();
    let base = El::new(kind, if id.is_empty() { "new" } else { &id }).to_json();
    let merged = merge(&base, e, if id.is_empty() { "new" } else { &id }, kind);
    let mut el = El::from_json(&merged)?;
    if id.is_empty() {
        el.id.clear();
    }
    let given = |k: &str| e.get(k).is_some();
    // **In a film in feet, the new pieces come in feet** (2026-09-30): a
    // 3' door, a 4' window, a 6" wall — not 2' 11" and 3' 11", off the grid
    // before anything is drawn. What a plan already holds is left as it is:
    // the file keeps only what differs from `El::new`, so these are written.
    if d.settings.units == "ft" {
        let thin = 0.5 * FOOT;
        match el.kind {
            Kind::Wall if !given("thick") => el.thick = thin,
            Kind::Door | Kind::Opening if !given("w") => el.w = 3.0 * FOOT,
            Kind::Window if !given("w") => el.w = 4.0 * FOOT,
            _ => {}
        }
        if matches!(el.kind, Kind::Door | Kind::Window | Kind::Opening) && !given("h") {
            el.h = thin;
        }
    }
    // **A new frame lies flat** (his ruling, 2026-09-30: "flat by default,
    // like Scenario") — a big square to see and grab, tilted up by its knob.
    // `El::new` keeps standing as the default a file leaves unsaid, so every
    // frame already drawn stays standing — and a copy, a paste or a favorite
    // of a standing one (which carries its worked-out `w` but no `tilt`)
    // stays standing too.
    if frame::is_frame(&el) && !given("tilt") && !given("w") {
        el.tilt = 0.0;
        frame::settle(&mut el);
    }
    Some(el)
}

/// **A half round stays half a circle** however it is sized. Its width or
/// its depth alone sets the diameter, and its back stays where it was, so
/// one against a wall stays on the wall. A corner dragged (width and depth
/// at once, and where it now stands) grows it along its diagonal, and the
/// corner the hand held still stays still; with Snap on in a film in feet
/// the drag goes by six inches — 48", 54", 60", 72".
fn keep_half(new: &mut El, was: (f64, f64, f64, f64), set: &Json, snap: bool) {
    let size = |k: &str| set.get(k).and_then(|v| v.as_f64()).filter(|v| v.is_finite() && *v > 0.0);
    let (ox, oy, ow, oh) = was;
    let dragged = set.get("x").is_some() || set.get("y").is_some();
    let mut across = match (size("w"), size("h")) {
        (Some(w), None) => w,
        (None, Some(h)) => 2.0 * h,
        (Some(w), Some(h)) => (w * ow + h * oh) / (ow * ow + oh * oh).max(1e-9) * ow,
        (None, None) => return,
    };
    if snap && dragged {
        let step = FOOT / 2.0;
        across = (across / step).round().max(2.0) * step;
    }
    let (w, h) = (across.max(0.1), across.max(0.1) / 2.0);
    let (c, s) = (new.rot.to_radians().cos(), new.rot.to_radians().sin());
    let corner = |x: f64, y: f64, w: f64, h: f64, a: f64, b: f64| (x + a * w / 2.0 * c - b * h / 2.0 * s, y + a * w / 2.0 * s + b * h / 2.0 * c);
    // What stays put: the corner the drag held — whichever of the old box's
    // corners the dragged box still has — or else the middle of the back.
    let (a, b, at) = if dragged {
        let (sw, sh) = (size("w").unwrap_or(ow), size("h").unwrap_or(oh));
        [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
            .into_iter()
            .map(|(a, b)| {
                let (o, n) = (corner(ox, oy, ow, oh, a, b), corner(new.x, new.y, sw, sh, a, b));
                ((o.0 - n.0).hypot(o.1 - n.1), a, b, o)
            })
            .min_by(|p, q| p.0.total_cmp(&q.0))
            .map(|(_, a, b, o)| (a, b, o))
            .unwrap()
    } else {
        (0.0, -1.0, corner(ox, oy, ow, oh, 0.0, -1.0))
    };
    let from = corner(0.0, 0.0, w, h, a, b);
    new.x = at.0 - from.0;
    new.y = at.1 - from.1;
    new.w = w;
    new.h = h;
}

/// Lay `set`'s keys over an element's, never letting a patch change what it is
/// or what it is called.
fn merge(base: &Json, set: &Json, id: &str, kind: Kind) -> Json {
    let mut out = merge_plain(base, set);
    if let Json::Object(pairs) = &mut out {
        for (k, v) in pairs.iter_mut() {
            if k == "id" {
                *v = Json::text(id);
            }
            if k == "kind" {
                *v = Json::text(kind.as_str());
            }
        }
    }
    out
}

fn merge_plain(base: &Json, set: &Json) -> Json {
    let mut pairs = match base {
        Json::Object(p) => p.clone(),
        _ => Vec::new(),
    };
    if let Json::Object(extra) = set {
        for (k, v) in extra {
            if let Some(slot) = pairs.iter_mut().find(|(key, _)| key == k) {
                slot.1 = v.clone();
            } else {
                pairs.push((k.clone(), v.clone()));
            }
        }
    }
    Json::Object(pairs)
}

/// The middle of a set of elements' boxes.
pub fn middle_of(d: &Diagram, ids: &[String]) -> (f64, f64) {
    let boxes: Vec<Aabb> = d
        .els
        .iter()
        .filter(|e| ids.contains(&e.id))
        .map(aabb)
        .collect();
    match union(&boxes) {
        Some(b) => ((b.x1 + b.x2) / 2.0, (b.y1 + b.y2) / 2.0),
        None => (0.0, 0.0),
    }
}

fn mirror(el: &mut El, horizontal: bool, px: f64, py: f64) {
    let m = |x: f64, y: f64| {
        if horizontal {
            (2.0 * px - x, y)
        } else {
            (x, 2.0 * py - y)
        }
    };
    let mr = |r: f64| norm_deg(if horizontal { 180.0 - r } else { -r });
    (el.x, el.y) = m(el.x, el.y);
    if el.kind.is_line() {
        (el.x2, el.y2) = m(el.x2, el.y2);
        el.curve = -el.curve;
    } else {
        el.rot = mr(el.rot);
    }
    for p in &mut el.points {
        *p = m(p.0, p.1);
    }
    for h in &mut el.handles {
        if horizontal {
            h[0] = -h[0];
            h[2] = -h[2];
        } else {
            h[1] = -h[1];
            h[3] = -h[3];
        }
    }
    for b in &mut el.steps {
        (b.x, b.y) = m(b.x, b.y);
        b.rot = mr(b.rot);
    }
    if el.kind == Kind::Door {
        el.hinge = if el.hinge == "right" { String::new() } else { "right".into() };
    }
}

/// The chosen pieces lifted out and put back together just above (drawn over)
/// or below `next`, keeping their own order. `next` among them, or gone,
/// leaves the stack as it was.
fn restack_by(d: &mut Diagram, ids: &[String], next: &str, above: bool) {
    if ids.iter().any(|i| i == next) || d.get(next).is_none() {
        return;
    }
    let chosen: Vec<El> = d.els.iter().filter(|e| ids.contains(&e.id)).cloned().collect();
    if chosen.is_empty() {
        return;
    }
    d.els.retain(|e| !ids.contains(&e.id));
    let at = d.els.iter().position(|e| e.id == next).unwrap() + usize::from(above);
    d.els.splice(at..at, chosen);
}

fn reorder(d: &mut Diagram, ids: &[String], to: &str) {
    let chosen: Vec<El> = d.els.iter().filter(|e| ids.contains(&e.id)).cloned().collect();
    if chosen.is_empty() {
        return;
    }
    match to {
        "front" | "back" => {
            d.els.retain(|e| !ids.contains(&e.id));
            if to == "front" {
                d.els.extend(chosen);
            } else {
                let mut out = chosen;
                out.append(&mut d.els);
                d.els = out;
            }
        }
        "forward" => {
            for i in (0..d.els.len().saturating_sub(1)).rev() {
                if ids.contains(&d.els[i].id) && !ids.contains(&d.els[i + 1].id) {
                    d.els.swap(i, i + 1);
                }
            }
        }
        "backward" => {
            for i in 1..d.els.len() {
                if ids.contains(&d.els[i].id) && !ids.contains(&d.els[i - 1].id) {
                    d.els.swap(i, i - 1);
                }
            }
        }
        _ => {}
    }
}

fn align(d: &mut Diagram, ids: &[String], to: &str) {
    let boxes: Vec<(String, Aabb)> = d
        .els
        .iter()
        .filter(|e| ids.contains(&e.id) && !e.locked)
        .map(|e| (e.id.clone(), aabb(e)))
        .collect();
    let Some(all) = union(&boxes.iter().map(|b| b.1).collect::<Vec<_>>()) else { return };
    for (id, b) in boxes {
        let (dx, dy) = match to {
            "left" => (all.x1 - b.x1, 0.0),
            "right" => (all.x2 - b.x2, 0.0),
            "top" => (0.0, all.y1 - b.y1),
            "bottom" => (0.0, all.y2 - b.y2),
            "hcentre" => ((all.x1 + all.x2) / 2.0 - (b.x1 + b.x2) / 2.0, 0.0),
            "vcentre" => (0.0, (all.y1 + all.y2) / 2.0 - (b.y1 + b.y2) / 2.0),
            _ => (0.0, 0.0),
        };
        if let Some(el) = d.get_mut(&id) {
            el.translate(dx, dy);
        }
    }
}

fn distribute(d: &mut Diagram, ids: &[String], horizontal: bool) {
    let mut boxes: Vec<(String, Aabb)> = d
        .els
        .iter()
        .filter(|e| ids.contains(&e.id) && !e.locked)
        .map(|e| (e.id.clone(), aabb(e)))
        .collect();
    if boxes.len() < 3 {
        return;
    }
    let mid = |b: &Aabb| if horizontal { (b.x1 + b.x2) / 2.0 } else { (b.y1 + b.y2) / 2.0 };
    boxes.sort_by(|a, b| mid(&a.1).partial_cmp(&mid(&b.1)).unwrap_or(std::cmp::Ordering::Equal));
    let first = mid(&boxes[0].1);
    let last = mid(&boxes[boxes.len() - 1].1);
    let step = (last - first) / (boxes.len() - 1) as f64;
    for (i, (id, b)) in boxes.iter().enumerate() {
        let want = first + step * i as f64;
        let delta = want - mid(b);
        if let Some(el) = d.get_mut(id) {
            if horizontal {
                el.translate(delta, 0.0);
            } else {
                el.translate(0.0, delta);
            }
        }
    }
}

// ---------------------------------------------------------------- boxes

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Aabb {
    pub x1: f64,
    pub y1: f64,
    pub x2: f64,
    pub y2: f64,
}

pub fn union(boxes: &[Aabb]) -> Option<Aabb> {
    let mut it = boxes.iter();
    let first = *it.next()?;
    Some(it.fold(first, |a, b| Aabb {
        x1: a.x1.min(b.x1),
        y1: a.y1.min(b.y1),
        x2: a.x2.max(b.x2),
        y2: a.y2.max(b.y2),
    }))
}

/// The four corners of a placed thing's footprint, turned.
pub fn corners(cx: f64, cy: f64, w: f64, h: f64, rot: f64) -> [(f64, f64); 4] {
    let (c, s) = (rot.to_radians().cos(), rot.to_radians().sin());
    let (hw, hh) = (w / 2.0, h / 2.0);
    let local = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)];
    local.map(|(x, y)| (cx + x * c - y * s, cy + x * s + y * c))
}

/// An element's box on the page, square to the page — the one alignment and
/// fitting use. Its own drawing (a beam, a cone) is not counted: a light is
/// where the light is.
pub fn aabb(e: &El) -> Aabb {
    let pts: Vec<(f64, f64)> = if e.kind == Kind::Measure && e.points.len() >= 2 {
        walls::corners(e).iter().flat_map(|p| [(p.0 - 0.1, p.1 - 0.1), (p.0 + 0.1, p.1 + 0.1)]).collect()
    } else if e.kind == Kind::Wall {
        let pad = e.thick.max(0.1) / 2.0;
        walls::run(e).iter().flat_map(|p| [(p.0 - pad, p.1 - pad), (p.0 + pad, p.1 + pad)]).collect()
    } else if e.kind.is_line() {
        let pad = (e.thick.max(0.1)) / 2.0 + e.curve.abs();
        vec![
            (e.x.min(e.x2) - pad, e.y.min(e.y2) - pad),
            (e.x.max(e.x2) + pad, e.y.max(e.y2) + pad),
        ]
    } else if e.kind.is_polyline() {
        walls::path_points(e)
    } else {
        let (w, h) = e.footprint(1);
        corners(e.x, e.y, w, h, e.rot).to_vec()
    };
    let mut b = Aabb { x1: f64::MAX, y1: f64::MAX, x2: f64::MIN, y2: f64::MIN };
    for (x, y) in pts {
        b.x1 = b.x1.min(x);
        b.y1 = b.y1.min(y);
        b.x2 = b.x2.max(x);
        b.y2 = b.y2.max(y);
    }
    if b.x1 > b.x2 {
        b = Aabb { x1: e.x, y1: e.y, x2: e.x, y2: e.y };
    }
    b
}

// ---------------------------------------------------------------- hits

/// What is under a point, top of the stack first. `tol` is how near counts, in
/// metres — the shell turns a few screen points into metres at its zoom.
/// Whether the plan draws this piece at all: View › Measurements off
/// keeps rulers and draws none, so none can be clicked.
fn shown(d: &Diagram, e: &El) -> bool {
    e.kind != Kind::Measure || d.settings.measures
}

pub fn hit(d: &Diagram, x: f64, y: f64, tol: f64, beat: u32) -> Option<String> {
    d.els
        .iter()
        .rev()
        .filter(|e| !e.hidden && shown(d, e))
        .find(|e| hits(e, x, y, tol, beat))
        .map(|e| e.id.clone())
}

/// **What a click takes, as drawn** (Ref 1511): the top piece under the
/// point, a lamp by its mark, a camera by its body and Words by their
/// words at `opt`'s zoom and lettering (`render::drawn_size`) — not only
/// by the footprint under them, which on a sheet is smaller than what is
/// drawn.
pub fn hit_drawn(d: &Diagram, x: f64, y: f64, tol: f64, beat: u32, opt: &render::Options) -> Option<String> {
    d.els
        .iter()
        .rev()
        .filter(|e| !e.hidden && shown(d, e))
        .find(|e| {
            if let Some((w, h)) = render::drawn_size(e, d, opt) {
                let (cx, cy, rot) = if e.kind.moves() { e.at_beat(beat) } else { (e.x, e.y, e.rot) };
                // Words set left or right run off their point.
                let shift = match (e.kind, e.align.as_str()) {
                    (Kind::Text, "left") => w / 2.0,
                    (Kind::Text, "right") => -w / 2.0,
                    _ => 0.0,
                };
                let r = rot.to_radians();
                if in_box(x, y, cx + r.cos() * shift, cy + r.sin() * shift, w + 2.0 * tol, h + 2.0 * tol, rot) {
                    return true;
                }
                if e.kind == Kind::Text {
                    return false;
                }
            }
            hits(e, x, y, tol, beat)
        })
        .map(|e| e.id.clone())
}

pub fn hits(e: &El, x: f64, y: f64, tol: f64, beat: u32) -> bool {
    if e.kind.is_line() {
        let half = match e.kind {
            Kind::Wall | Kind::Road | Kind::Track => e.thick / 2.0,
            _ => 0.0,
        };
        let pts = render::line_points(e);
        return pts.windows(2).any(|w| seg_dist(x, y, w[0], w[1]) <= half + tol);
    }
    if e.kind.is_polyline() {
        let pts = walls::path_points(e);
        // A closed shape that is filled is hit anywhere inside it.
        if e.fill && walls::closed(e) && walls::inside(&pts, (x, y)) {
            return true;
        }
        return pts.windows(2).any(|w| seg_dist(x, y, w[0], w[1]) <= tol + e.weight * 0.005)
            || (pts.len() == 1 && ((x - pts[0].0).powi(2) + (y - pts[0].1).powi(2)).sqrt() <= tol);
    }
    let (cx, cy, rot) = if e.kind.moves() { e.at_beat(beat) } else { (e.x, e.y, e.rot) };
    if e.kind == Kind::Text {
        // Words are measured by the shell; here, a generous box round the point.
        let w = (e.text.chars().count().max(1) as f64) * e.size * 0.012;
        let h = e.size * 0.025;
        return in_box(x, y, cx, cy, w + 2.0 * tol, h + 2.0 * tol, rot);
    }
    let (w, h) = e.footprint(beat);
    in_box(x, y, cx, cy, w + 2.0 * tol, h + 2.0 * tol, rot)
}

/// Every element wholly or partly inside a box — a marquee.
pub fn within(d: &Diagram, b: Aabb) -> Vec<String> {
    d.els
        .iter()
        .filter(|e| !e.hidden && !e.locked)
        .filter(|e| {
            // A wall by its line, not its box: a box drawn round furniture
            // inside a room does not catch the room's walls.
            if e.kind == Kind::Wall {
                let pad = e.thick / 2.0;
                let inside = |p: (f64, f64)| p.0 >= b.x1 - pad && p.0 <= b.x2 + pad && p.1 >= b.y1 - pad && p.1 <= b.y2 + pad;
                return walls::run(e).windows(2).any(|w| {
                    // A stretch crosses the box when an end is in it, or it
                    // passes through one of the box's sides.
                    if inside(w[0]) || inside(w[1]) {
                        return true;
                    }
                    let corners = [(b.x1, b.y1), (b.x2, b.y1), (b.x2, b.y2), (b.x1, b.y2)];
                    (0..4).any(|i| crosses(w[0], w[1], corners[i], corners[(i + 1) % 4]))
                });
            }
            let a = aabb(e);
            a.x1 < b.x2 && a.x2 > b.x1 && a.y1 < b.y2 && a.y2 > b.y1
        })
        .map(|e| e.id.clone())
        .collect()
}

/// Whether two segments cross.
fn crosses(a: (f64, f64), b: (f64, f64), c: (f64, f64), d: (f64, f64)) -> bool {
    let side = |p: (f64, f64), q: (f64, f64), r: (f64, f64)| (q.0 - p.0) * (r.1 - p.1) - (q.1 - p.1) * (r.0 - p.0);
    let (d1, d2) = (side(c, d, a), side(c, d, b));
    let (d3, d4) = (side(a, b, c), side(a, b, d));
    d1 * d2 <= 0.0 && d3 * d4 <= 0.0 && (d1 != 0.0 || d2 != 0.0 || d3 != 0.0 || d4 != 0.0)
}

fn in_box(x: f64, y: f64, cx: f64, cy: f64, w: f64, h: f64, rot: f64) -> bool {
    let (c, s) = (rot.to_radians().cos(), rot.to_radians().sin());
    let (dx, dy) = (x - cx, y - cy);
    let lx = dx * c + dy * s;
    let ly = -dx * s + dy * c;
    lx.abs() <= w / 2.0 && ly.abs() <= h / 2.0
}

pub fn seg_dist(px: f64, py: f64, a: (f64, f64), b: (f64, f64)) -> f64 {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let len2 = dx * dx + dy * dy;
    let t = if len2 == 0.0 { 0.0 } else { (((px - a.0) * dx + (py - a.1) * dy) / len2).clamp(0.0, 1.0) };
    let (qx, qy) = (a.0 + t * dx, a.1 + t * dy);
    ((px - qx).powi(2) + (py - qy).powi(2)).sqrt()
}

// ---------------------------------------------------------------- snapping

/// Where a point wants to be: a wall's corner or line within reach, lined up
/// with a corner, else the grid (`walls::snap`).
/// Returns the point and whether it caught on something other than the grid.
pub fn snap_point(d: &Diagram, x: f64, y: f64, reach: f64, skip: &[String]) -> ((f64, f64), bool) {
    snap_point_to(d, x, y, reach, skip, d.settings.step)
}

/// The same, on a grid of `step` — the Mac's grid follows its zoom, finer
/// close in and coarser far out.
pub fn snap_point_to(d: &Diagram, x: f64, y: f64, reach: f64, skip: &[String], step: f64) -> ((f64, f64), bool) {
    let s = walls::snap(d, x, y, reach, step, skip, None);
    (s.at, s.caught)
}

/// Where a door or window goes when dropped near a wall: onto its line, turned
/// to match it, as thick as it is.
pub fn onto_wall(d: &Diagram, x: f64, y: f64, reach: f64) -> Option<(f64, f64, f64, f64)> {
    walls::in_wall(d, x, y, reach, 0.0, 0.0).map(|w| (w.x, w.y, w.rot, w.thick))
}

// ---------------------------------------------------------------- a room

/// Walls, doors, windows and furniture from a scanned room, laid on the plan.
/// The scan is in metres, and its second axis is RoomPlan's z, which looking
/// down from above already grows toward the bottom of the page — the way the
/// location's own floor plan draws it on the Mac, the phone and the portal. So
/// it comes straight across, only moved to start at nought. It used to be
/// mirrored here on the belief that the scan's y grew north, and every room
/// laid on a plan came in back to front (the Den on *Mirrorland*,
/// 2026-09-27). Everything made carries `note: "scan"` so a second import can
/// replace the first without touching what he drew.
pub fn room_elements(plan: &crate::room::Plan, d: &Diagram) -> Vec<El> {
    use crate::room::Part;
    let mut out = Vec::new();
    let mut n = d.els.len() + 1;
    let mut id = |stem: &str| {
        loop {
            let candidate = format!("{stem}-scan-{n}");
            n += 1;
            if d.get(&candidate).is_none() {
                return candidate;
            }
        }
    };
    let ((minx, miny), _) = plan.bounds;
    let px = |x: f32| (x - minx) as f64;
    let py = |y: f32| (y - miny) as f64;
    // **Walls as thick as drawn ones** (his ask, 2026-10-17: a scanned room
    // made of the same pieces he draws by hand): a 6" wall in a film in feet,
    // 15 cm in metres, as the Wall tool puts down.
    let thick = if d.settings.units == "ft" { 0.5 * FOOT } else { WALL };
    for item in &plan.items {
        let (cx, cy) = (px(item.centre.0), py(item.centre.1));
        let rot = norm_deg((item.angle as f64).to_degrees());
        let len = item.size.0 as f64;
        let (c, s) = (rot.to_radians().cos(), rot.to_radians().sin());
        // A piece `along` metres from the middle, along the wall.
        let at = |along: f64| (cx + c * along, cy + s * along);
        match item.part {
            Part::Wall => {
                let mut el = El::new(Kind::Wall, &id("wall"));
                el.x = cx - c * len / 2.0;
                el.y = cy - s * len / 2.0;
                el.x2 = cx + c * len / 2.0;
                el.y2 = cy + s * len / 2.0;
                el.thick = thick;
                el.note = "scan".into();
                out.push(el);
            }
            Part::Door => {
                // **One door of its kind** (2026-10-17): a pair is one piece
                // that draws both leaves or both panels, as he places one.
                let style = scanned_door(item);
                let mut el = El::new(Kind::Door, &id("door"));
                (el.x, el.y) = at(0.0);
                el.rot = rot;
                el.w = len.max(0.3);
                el.h = thick;
                el.set_door_style(style);
                if style == "sliding" {
                    el.hinge = "right".into();
                }
                if el.slide {
                    el.swing = 0.0;
                }
                el.note = "scan".into();
                out.push(el);
            }
            Part::Window | Part::Opening => {
                let kind = if item.part == Part::Window { Kind::Window } else { Kind::Opening };
                let mut el = El::new(kind, &id(kind.as_str()));
                el.x = cx;
                el.y = cy;
                el.rot = rot;
                el.w = len.max(0.3);
                el.h = thick;
                el.note = "scan".into();
                out.push(el);
            }
            Part::Object => {
                let (sym, label) = scanned_piece(item);
                let mut el = El::new(Kind::Set, &id("set"));
                el.sym = sym.into();
                el.label = label;
                el.x = cx;
                el.y = cy;
                el.rot = rot;
                el.w = len.max(0.2);
                el.h = (item.size.1 as f64).max(0.2);
                el.note = "scan".into();
                out.push(el);
            }
        }
    }
    out
}

/// How wide a door has to be before it is taken for a slider: about five
/// feet. Nobody hangs a five-foot leaf on hinges; the glass doors on to a
/// deck are this wide or wider.
pub const SLIDER: f64 = 1.5;
/// Wider than this, a slider parts from the centre: two panels each way, as
/// a wall of glass on to a garden is built.
pub const SLIDER_PAIR: f64 = 3.6;

/// **What kind of door a scanned one is**, as one word of the door kinds
/// the plan draws: `swing`, `double` (two leaves from the middle),
/// `sliding`, or `center` (two panels parting from the middle).
///
/// RoomPlan gives a door's width and height, whether it stood open, and the
/// wall it is in — never which way it opens. So: a door wider than
/// [`SLIDER`], or one over three and a half feet wide in a wall that also
/// holds a window (a glass wall) or taller than a room's usual door, slides;
/// one wider than [`SLIDER_PAIR`] parts from the centre; a door too wide for
/// one leaf but not a slider is a pair; the rest swing. His note,
/// 2026-10-17: the big sliding doors on *Call Her Back* came in as 15-foot
/// hinged doors swinging out into the room.
pub fn scanned_door(item: &crate::room::Item) -> &'static str {
    let w = item.size.0 as f64;
    let glass = item.glass_wall || item.height as f64 >= 2.4;
    let slides = w >= SLIDER || (w >= 1.1 && glass);
    match (slides, w) {
        (true, w) if w >= SLIDER_PAIR => "center",
        (true, _) => "sliding",
        (false, w) if w >= 1.1 => "double",
        _ => "swing",
    }
}

/// **A scanned object as a library piece** — the piece's symbol, and a label
/// only when the library has no drawing of its own for it (a washer, a
/// dishwasher, a category a later iOS adds), so a plain box still says what
/// it is. The label is the piece's ordinary label: he retypes or clears it.
pub fn scanned_piece(item: &crate::room::Item) -> (&'static str, String) {
    let (a, b) = (item.size.0 as f64, item.size.1 as f64);
    let (small, big) = (a.min(b), a.max(b));
    let detail = item.detail.as_str();
    let category = if item.category.is_empty() { item.furnishing.as_str().to_string() } else { item.category.clone() };
    let sym = match category.as_str() {
        "bed" if small < 1.1 => "bed-single",
        "bed" if small > 1.8 => "bed-king",
        "bed" => "bed",
        "chair" | "seat" => match detail {
            "stool" => "stool",
            "swivel" => "office-chair",
            _ if small >= 0.75 => "armchair",
            _ => "chair",
        },
        "sofa" => match detail {
            "singleSeat" => "armchair",
            "lShaped" => "sofa-l",
            _ if big < 1.9 => "loveseat",
            _ => "sofa",
        },
        "table" => match detail {
            "coffee" => "coffee-table",
            "circularElliptic" if big > 1.3 => "table-round-l",
            "circularElliptic" => "table-round",
            _ if big < 0.65 => "side-table",
            _ => "table",
        },
        "storage" => match detail {
            "shelf" => "bookshelf",
            _ => "cabinet",
        },
        "refrigerator" => "fridge",
        "stove" => "stove",
        "sink" => "sink",
        "toilet" => "toilet",
        "bathtub" => "bathtub",
        "fireplace" => "fireplace",
        "stairs" => "stairs",
        "television" | "screen" => "tv",
        _ => "",
    };
    if !sym.is_empty() {
        return (sym, String::new());
    }
    let label = match category.as_str() {
        "washerDryer" => "Washer/Dryer".to_string(),
        "oven" => "Oven".to_string(),
        "dishwasher" => "Dishwasher".to_string(),
        "other" | "" => String::new(),
        other => words_of(other),
    };
    ("box", label)
}

/// `washerDryer` → `Washer Dryer`: a camel-cased name, as words.
pub fn words_of(name: &str) -> String {
    let mut out = String::new();
    for (i, ch) in name.chars().enumerate() {
        if i == 0 {
            out.extend(ch.to_uppercase());
        } else if ch.is_uppercase() {
            out.push(' ');
            out.push(ch);
        } else {
            out.push(ch);
        }
    }
    out
}


#[cfg(test)]
mod scan_tests;

/// Lay a scanned room onto the plan, replacing any room laid before.
pub fn import_room(d: &mut Diagram, plan: &crate::room::Plan, location: &str) -> Vec<String> {
    d.els.retain(|e| e.note != "scan");
    let els = room_elements(plan, d);
    let walls: Vec<String> = els.iter().filter(|e| e.kind == Kind::Wall).map(|e| e.id.clone()).collect();
    let ids: Vec<String> = els.iter().map(|e| e.id.clone()).collect();
    for el in els {
        d.insert_at_tier(el);
    }
    // **Walls that meet are one wall**, as the Wall tool draws a room: the
    // scan's separate planes joined at their corners, so a corner drags as
    // one and a room closes. A scan's corners miss by a few centimetres.
    walls::join_walls(d, &walls, 0.3);
    d.room_from = location.to_string();
    ids.into_iter().filter(|id| d.get(id).is_some()).collect()
}

// ---------------------------------------------------------------- lengths

/// A length as it is written: `12 ft 3 in`, or `3.73 m`.
pub fn length_text(metres: f64, units: &str) -> String {
    if units == "m" {
        return format!("{:.2} m", metres);
    }
    // To the quarter inch: a wall typed as 6 1/2" is labelled as typed (the
    // Mac's `DiagramModel.length` reads the same).
    // Only a length that is a quarter inch (typed so) shows one; any other
    // reads to the whole inch.
    let q = metres / 0.0254 * 4.0;
    let quarters = if (q - q.round()).abs() < 0.02 { q.round() as i64 } else { (q / 4.0).round() as i64 * 4 };
    let (ft, rest) = (quarters / 48, quarters % 48);
    let (inch, frac) = (rest / 4, ["", "¼", "½", "¾"][(rest % 4) as usize]);
    let inches = match (inch, frac.is_empty()) {
        (0, true) => String::new(),
        (0, false) => format!("{frac} in"),
        (i, true) => format!("{i} in"),
        (i, false) => format!("{i} {frac} in"),
    };
    match (ft, inches.is_empty()) {
        (0, true) => "0 in".into(),
        (0, false) => inches,
        (f, true) => format!("{f} ft"),
        (f, false) => format!("{f} ft {inches}"),
    }
}

#[cfg(test)]
mod tests;

// ---------------------------------------------------------------- a sample

/// A bedroom with a push-in on a dolly, a wide from the door, an insert on the
/// phone, a key through the window and Anya getting up and leaving — the
/// scene the mockup was drawn from. For checks, and for a plan to look at
/// without a film.
pub fn sample() -> Diagram {
    let text = r##"{"els":[
      {"id":"rug","kind":"set","sym":"rug","x":2.2,"y":2.05,"w":1.7,"h":1.2},
      {"id":"bed","kind":"set","sym":"bed","x":1.12,"y":1.3,"w":1.5,"h":2.05,"rot":-90},
      {"id":"ns","kind":"set","sym":"nightstand","x":0.3,"y":2.45,"w":0.5,"h":0.45,"rot":-90},
      {"id":"dresser","kind":"set","sym":"dresser","x":3.0,"y":0.3,"w":1.2,"h":0.5},
      {"id":"chair","kind":"set","sym":"armchair","x":3.25,"y":2.05,"w":0.9,"h":0.86,"rot":-90},
      {"id":"w1","kind":"wall","x":0,"y":0,"x2":3.73,"y2":0},
      {"id":"w2","kind":"wall","x":3.73,"y":0,"x2":3.73,"y2":3.25},
      {"id":"w3","kind":"wall","x":3.73,"y":3.25,"x2":0,"y2":3.25},
      {"id":"w4","kind":"wall","x":0,"y":3.25,"x2":0,"y2":0},
      {"id":"win","kind":"window","x":1.15,"y":0,"w":1.1},
      {"id":"door","kind":"door","x":2.3,"y":3.25,"w":0.85,"hinge":"right","flip":true},
      {"id":"key","kind":"light","sym":"hmi-18k","x":1.15,"y":-1.5,"rot":90,"w":0.95,"h":0.9,"beam":25,"reach":4.4,"kelvin":5600,"label":"18K HMI"},
      {"id":"fill","kind":"light","sym":"mat","x":2.25,"y":0.35,"rot":150,"w":0.08,"h":0.6,"beam":110,"reach":1.6,"kelvin":5600,"label":"Litemat 4"},
      {"id":"prac","kind":"light","sym":"practical","x":0.28,"y":2.4,"w":0.28,"h":0.28,"beam":360,"reach":0.9,"kelvin":2700},
      {"id":"track","kind":"track","x":2.2,"y":1.15,"x2":3.45,"y2":1.15},
      {"id":"anya","kind":"cast","label":"Anya","pose":"lying","x":1.1,"y":1.3,"rot":0,"w":0.28,"h":0.46,"path":[{"beat":2,"x":2.3,"y":2.75,"rot":90,"pose":"standing"}]},
      {"id":"cA","kind":"camera","label":"1A","x":2.45,"y":1.15,"rot":183,"lens":50,"color":"#D9483B","reach":2.2,"path":[{"beat":2,"x":3.2,"y":1.15,"rot":183}]},
      {"id":"cB","kind":"camera","label":"1B","x":3.4,"y":2.95,"rot":218,"lens":24,"color":"#3D7BD9","reach":3.0},
      {"id":"cC","kind":"camera","label":"1C","x":1.05,"y":2.65,"rot":200,"lens":85,"color":"#2E8B7A","reach":0.8},
      {"id":"note","kind":"note","x":1.15,"y":-0.55,"text":"Blackout for night"}
    ]}"##;
    Diagram::parse(text)
}
