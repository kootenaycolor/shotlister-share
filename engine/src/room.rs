//! A scanned room, read back as something flat you can draw.
//!
//! **Why this is in the engine and not in either app.** His instruction of
//! 2026-08-21: *"iOS has been handling the floor plan creation. I just need you
//! to display it, or you guys should just share the same engine."* Both apps
//! need the same answer about the same room, and two programs measuring one
//! room slightly differently is worse than one program that cannot measure it
//! at all. The engine is the thing the Mac, the phone and Claude all build, so
//! the arithmetic lives here and the *drawing* stays in each app — which is the
//! only part that genuinely differs.
//!
//! The phone worked all of this out first, on a real room, and found four bugs
//! in it that no amount of reasoning had (`handoff/from-phone.md`). Every one of
//! those findings is preserved here and carries the note that earned it.
//!
//! Everything is in metres, as RoomPlan gives it. Feet and inches happen at the
//! very edge, where a number is written on screen.

use crate::json::Json;

// ---------------------------------------------------------------- the model

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part {
    Wall,
    Door,
    Window,
    Opening,
    Object,
}

impl Part {
    pub fn as_str(self) -> &'static str {
        match self {
            Part::Wall => "wall",
            Part::Door => "door",
            Part::Window => "window",
            Part::Opening => "opening",
            Part::Object => "object",
        }
    }
}

/// What a thing in a room is, as far as a plan cares.
///
/// RoomPlan knows more categories than this; several of them want the same
/// drawing, and a plan with fifteen bespoke symbols is harder to read than one
/// with seven.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Furnishing {
    Bed,
    Seat,
    Sofa,
    Table,
    Storage,
    Screen,
    Appliance,
    Plumbing,
    Stairs,
    Other,
}

impl Furnishing {
    /// From RoomPlan's own case name, which is what its JSON carries.
    pub fn parse(category: &str) -> Furnishing {
        match category {
            "bed" => Furnishing::Bed,
            "chair" => Furnishing::Seat,
            "sofa" => Furnishing::Sofa,
            "table" => Furnishing::Table,
            "storage" => Furnishing::Storage,
            "television" => Furnishing::Screen,
            "refrigerator" | "stove" | "oven" | "dishwasher" | "washerDryer" => {
                Furnishing::Appliance
            }
            "toilet" | "bathtub" | "sink" => Furnishing::Plumbing,
            "stairs" => Furnishing::Stairs,
            _ => Furnishing::Other,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Furnishing::Bed => "bed",
            Furnishing::Seat => "seat",
            Furnishing::Sofa => "sofa",
            Furnishing::Table => "table",
            Furnishing::Storage => "storage",
            Furnishing::Screen => "screen",
            Furnishing::Appliance => "appliance",
            Furnishing::Plumbing => "plumbing",
            Furnishing::Stairs => "stairs",
            Furnishing::Other => "other",
        }
    }
}

/// One thing, flattened onto the floor.
#[derive(Clone, Debug)]
pub struct Item {
    pub part: Part,
    /// Where its middle is, looking straight down.
    pub centre: (f32, f32),
    /// How long it is, and how thick, from above — **as scanned**.
    ///
    /// RoomPlan reports walls with a thickness of exactly zero: they are planes,
    /// not slabs. Inflating them here would put that invented thickness into the
    /// room's own dimensions, so this keeps the truth and the drawing does the
    /// inflating.
    pub size: (f32, f32),
    /// How tall, in metres. Kept because a room's height decides what can be
    /// rigged in it, and it is the one measurement a plan cannot draw.
    pub height: f32,
    /// Turned this far anticlockwise from east, in radians.
    pub angle: f32,
    pub furnishing: Furnishing,
    /// RoomPlan's own name for an object, as it wrote it (`washerDryer`,
    /// `oven`): what a plan piece is matched by, and what a piece the
    /// library has no drawing for is labelled. Empty on a surface.
    pub category: String,
    /// What the scan says about its shape, from iOS 17's attributes, one
    /// word: a chair's `stool` or `swivel`, a sofa's `lShaped` or
    /// `singleSeat`, a table's `circularElliptic` or `coffee`, storage's
    /// `shelf`. Empty when it said nothing.
    pub detail: String,
    /// A door the scan saw standing open (iOS 17 on); `None` when it did
    /// not say.
    pub open: Option<bool>,
    /// **A door in a wall that also holds a window** — a glass wall, the
    /// clearest sign a scan gives of a slider (`parentIdentifier`).
    pub glass_wall: bool,
}

impl Item {
    /// A thing with nothing said about it beyond where it is.
    pub fn plain(part: Part, centre: (f32, f32), size: (f32, f32), height: f32, angle: f32, furnishing: Furnishing) -> Item {
        Item {
            part,
            centre,
            size,
            height,
            angle,
            furnishing,
            category: String::new(),
            detail: String::new(),
            open: None,
            glass_wall: false,
        }
    }

    /// The four corners, in world metres, at whatever thickness is asked for.
    /// `None` keeps the scan's own answer, which is what bounds and measurements
    /// must use.
    pub fn corners(&self, thickness: Option<f32>) -> [(f32, f32); 4] {
        let across = self.size.1.max(thickness.unwrap_or(0.0));
        let (c, s) = (self.angle.cos(), self.angle.sin());
        let half = (self.size.0 / 2.0, across / 2.0);
        let local = [
            (-half.0, -half.1),
            (half.0, -half.1),
            (half.0, half.1),
            (-half.0, half.1),
        ];
        let mut out = [(0.0, 0.0); 4];
        for (i, (x, y)) in local.iter().enumerate() {
            out[i] = (
                self.centre.0 + x * c - y * s,
                self.centre.1 + x * s + y * c,
            );
        }
        out
    }

    fn turned(&self, angle: f32, pivot: (f32, f32)) -> Item {
        let (c, s) = (angle.cos(), angle.sin());
        let d = (self.centre.0 - pivot.0, self.centre.1 - pivot.1);
        let mut moved = self.clone();
        moved.centre = (pivot.0 + d.0 * c - d.1 * s, pivot.1 + d.0 * s + d.1 * c);
        moved.angle += angle;
        moved
    }
}

/// A whole room, straightened and measured.
#[derive(Clone, Debug)]
pub struct Plan {
    pub items: Vec<Item>,
    /// How far the room was turned to bring it square to the page, kept so a
    /// measurement can still be traced back to the wall it came from.
    pub straightened_by: f32,
    pub bounds: ((f32, f32), (f32, f32)),
    /// **The rooms RoomPlan named inside the scan** (iOS 17's `sections`):
    /// `kitchen`, `livingRoom`… with where each one's middle is, straightened
    /// with the rest. What a scan's suggested name reads its room from when
    /// the location does not say.
    pub rooms: Vec<(String, (f32, f32))>,
}

impl Plan {
    pub fn walls(&self) -> impl Iterator<Item = &Item> {
        self.items.iter().filter(|i| i.part == Part::Wall)
    }

    /// How high the ceiling is — the commonest wall height, which is the honest
    /// answer when a scanner reports six walls that agree to the centimetre.
    pub fn ceiling(&self) -> f32 {
        let mut heights: Vec<f32> = self.walls().map(|w| w.height).collect();
        if heights.is_empty() {
            return 0.0;
        }
        heights.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        heights[heights.len() / 2]
    }

    /// Whether the walls disagree enough to be worth saying so. **A stepped or
    /// sloped ceiling is a real fact about a location** and should not be
    /// flattened into one number without a word — the phone's finding, and it
    /// only shows up on a real room.
    pub fn ceiling_varies(&self) -> bool {
        let (low, high) = self.ceiling_range();
        high - low > 0.08
    }

    pub fn ceiling_range(&self) -> (f32, f32) {
        let mut low = f32::MAX;
        let mut high = f32::MIN;
        for wall in self.walls() {
            low = low.min(wall.height);
            high = high.max(wall.height);
        }
        if low > high {
            (0.0, 0.0)
        } else {
            (low, high)
        }
    }

    pub fn extent(&self) -> (f32, f32) {
        (
            self.bounds.1 .0 - self.bounds.0 .0,
            self.bounds.1 .1 - self.bounds.0 .1,
        )
    }

    /// Straighten, then fit. Both halves are decisions the phone reached on a
    /// real scan and both are load-bearing.
    pub fn from_items(found: Vec<Item>) -> Option<Plan> {
        Plan::from_items_and_rooms(found, Vec::new())
    }

    /// The same, carrying the rooms RoomPlan named, turned with the rest.
    pub fn from_items_and_rooms(found: Vec<Item>, rooms: Vec<(String, (f32, f32))>) -> Option<Plan> {
        if found.is_empty() {
            return None;
        }

        // A room is scanned at whatever angle he happened to be standing, and
        // comes back at that angle. Nobody draws a plan crooked — and a crooked
        // plan makes every dimension on it look approximate even when it is
        // exact. Turn it until its longest wall lies flat.
        let turn = -dominant_angle(&found);
        let pivot = middle(&found);
        let items: Vec<Item> = found.iter().map(|i| i.turned(turn, pivot)).collect();

        // Fitted to the **structure alone**. A chair pushed against a wall must
        // not widen the room, and a table half under a counter must not move it.
        let structural: Vec<&Item> = items.iter().filter(|i| i.part != Part::Object).collect();
        let measured: Vec<&Item> = if structural.is_empty() {
            items.iter().collect()
        } else {
            structural
        };
        let mut low = (f32::MAX, f32::MAX);
        let mut high = (f32::MIN, f32::MIN);
        for item in measured {
            for corner in item.corners(None) {
                low = (low.0.min(corner.0), low.1.min(corner.1));
                high = (high.0.max(corner.0), high.1.max(corner.1));
            }
        }

        Some(Plan {
            items,
            straightened_by: turn,
            bounds: (low, high),
            rooms: rooms
                .into_iter()
                .map(|(name, at)| {
                    let (c, s) = (turn.cos(), turn.sin());
                    let d = (at.0 - pivot.0, at.1 - pivot.1);
                    (name, (pivot.0 + d.0 * c - d.1 * s, pivot.1 + d.0 * s + d.1 * c))
                })
                .collect(),
        })
    }
}

/// The angle the room is built on, taken from its longest wall — and reduced to
/// a quarter turn, because a wall lying north–south is just as square to the
/// page as one lying east–west.
fn dominant_angle(items: &[Item]) -> f32 {
    let walls: Vec<&Item> = items.iter().filter(|i| i.part == Part::Wall).collect();
    let pool: Vec<&Item> = if walls.is_empty() {
        items.iter().collect()
    } else {
        walls
    };
    let longest = pool
        .iter()
        .max_by(|a, b| {
            a.size
                .0
                .partial_cmp(&b.size.0)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .copied();
    let Some(longest) = longest else { return 0.0 };
    let quarter = std::f32::consts::FRAC_PI_2;
    let mut angle = longest.angle % quarter;
    if angle > quarter / 2.0 {
        angle -= quarter;
    }
    if angle < -quarter / 2.0 {
        angle += quarter;
    }
    angle
}

fn middle(items: &[Item]) -> (f32, f32) {
    let mut low = (f32::MAX, f32::MAX);
    let mut high = (f32::MIN, f32::MIN);
    for item in items {
        for corner in item.corners(None) {
            low = (low.0.min(corner.0), low.1.min(corner.1));
            high = (high.0.max(corner.0), high.1.max(corner.1));
        }
    }
    if low.0 > high.0 {
        return (0.0, 0.0);
    }
    ((low.0 + high.0) / 2.0, (low.1 + high.1) / 2.0)
}

// ------------------------------------------------------- RoomPlan's own file

/// Read a `CapturedRoom` as RoomPlan writes it.
///
/// **These field names are measured, not guessed.** RoomPlan encodes by hand
/// rather than by synthesis, so the shape is not in its public interface — so on
/// 2026-08-21 it was asked directly: a scrap of a program built for the iOS
/// simulator tried `JSONDecoder().decode(CapturedRoom.self, …)` on a candidate
/// and printed the error, and Swift's decoding errors name the key they wanted
/// and where. Twelve rounds walked out the shape, and the last one decoded and
/// printed the framework's own canonical encoding back.
///
/// Three things that would otherwise have been guesses, and two of the three
/// guesses would have been wrong:
///
/// - `transform` is **sixteen flat floats, column-major** — not four arrays of
///   four, which is the likelier reading of `simd_float4x4` being Codable.
/// - `category` is an object with **one key named for the case**: `{"wall":{}}`,
///   `{"door":{"isOpen":true}}`. Not a string.
/// - `dimensions` is `[width, height, depth]` in the thing's own frame.
pub fn read(text: &str) -> Option<Plan> {
    let room = crate::json::parse(text)?;
    // Each thing, with how high its bottom edge sits in RoomPlan's world,
    // its own identifier and the wall it sits in.
    let mut found: Vec<(Item, f32, String, String)> = Vec::new();
    for (key, part) in [
        ("walls", Part::Wall),
        ("doors", Part::Door),
        ("windows", Part::Window),
        ("openings", Part::Opening),
        ("objects", Part::Object),
    ] {
        let Some(list) = room.get(key).and_then(|v| v.as_array()) else {
            continue;
        };
        for entry in list {
            if let Some((item, bottom)) = surface(entry, part) {
                let own = entry.get("identifier").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let parent = entry.get("parentIdentifier").and_then(|v| v.as_str()).unwrap_or("").to_string();
                found.push((item, bottom, own, parent));
            }
        }
    }
    let floor = {
        let pairs: Vec<(Item, f32)> = found.iter().map(|(i, b, _, _)| (i.clone(), *b)).collect();
        floor_level(&room, &pairs)
    };
    let mut placed: Vec<(Item, String)> = Vec::new();
    for (mut item, bottom, _, parent) in found {
        // **A door does not stand off the floor.** RoomPlan calls a big
        // window a door more often than not — tall glass reads to it as a
        // way through — and his scans kept coming back with huge doors
        // where the windows are (his note, 2026-09-27). A door reaches the
        // floor; anything it calls a door whose bottom sits a sill's height
        // above the floor is a window.
        if item.part == Part::Door {
            if let Some(floor) = floor {
                if bottom - floor > SILL {
                    item.part = Part::Window;
                }
            }
        }
        placed.push((item, parent));
    }
    // The walls that hold a window: a door in one of them is in glass.
    let glazed: Vec<String> = placed
        .iter()
        .filter(|(i, p)| i.part == Part::Window && !p.is_empty())
        .map(|(_, p)| p.clone())
        .collect();
    let items: Vec<Item> = placed
        .into_iter()
        .map(|(mut item, parent)| {
            if item.part == Part::Door {
                item.glass_wall = !parent.is_empty() && glazed.contains(&parent);
            }
            item
        })
        .collect();
    let rooms: Vec<(String, (f32, f32))> = room
        .get("sections")
        .and_then(|v| v.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|s| {
                    let label = s.get("label")?.as_str()?.to_string();
                    let c = s.get("center")?.as_array()?;
                    let (x, z) = (c.first()?.as_f64()? as f32, c.get(2)?.as_f64()? as f32);
                    Some((label, (x, z)))
                })
                .collect()
        })
        .unwrap_or_default();
    Plan::from_items_and_rooms(items, rooms)
}

/// How far above the floor a "door" has to start before it is taken for a
/// window: a foot. A threshold, a step up to a patio, a scan's own wobble all
/// sit well under it; a window sill sits well over.
pub const SILL: f32 = 0.3;

/// Where the floor is in RoomPlan's world — its height is wherever the phone
/// happened to start, not zero. The scan's own floor when it has one (iOS 17
/// on), else where the walls stand: the middle of their bottom edges, which
/// is the honest answer when one wall's bottom is scanned a little short.
fn floor_level(room: &Json, found: &[(Item, f32)]) -> Option<f32> {
    let mut floors: Vec<f32> = room
        .get("floors")
        .and_then(|v| v.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|f| f.get("transform")?.as_array()?.get(13)?.as_f64())
                .map(|y| y as f32)
                .collect()
        })
        .unwrap_or_default();
    if floors.is_empty() {
        floors = found.iter().filter(|(i, _)| i.part == Part::Wall).map(|(_, b)| *b).collect();
    }
    floors.retain(|y| y.is_finite());
    if floors.is_empty() {
        return None;
    }
    floors.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    Some(floors[floors.len() / 2])
}

fn surface(entry: &Json, part: Part) -> Option<(Item, f32)> {
    let dimensions = entry.get("dimensions")?.as_array()?;
    let transform = entry.get("transform")?.as_array()?;
    if dimensions.len() < 3 || transform.len() < 16 {
        return None;
    }
    let d: Vec<f32> = dimensions
        .iter()
        .map(|v| v.as_f64().unwrap_or(0.0) as f32)
        .collect();
    let t: Vec<f32> = transform
        .iter()
        .map(|v| v.as_f64().unwrap_or(0.0) as f32)
        .collect();

    // Looking straight down, RoomPlan puts height on y and the floor on x/z, so
    // the plan's second axis is the world's z. Column-major sixteen puts the
    // position in elements 12…14 and the thing's own x axis in 0…2.
    let centre = (t[12], t[14]);
    let angle = t[2].atan2(t[0]);

    let name = entry
        .get("category")
        .and_then(category_name)
        .unwrap_or_default();

    // Its middle's height, less half of how tall it is: its bottom edge.
    let bottom = t[13] - d[1] / 2.0;

    let mut item = Item::plain(
        part,
        centre,
        (d[0], d[2]),
        d[1],
        angle,
        if part == Part::Object { Furnishing::parse(&name) } else { Furnishing::Other },
    );
    if part == Part::Object {
        item.category = name;
        item.detail = detail(entry);
    }
    if part == Part::Door {
        item.open = entry
            .get("category")
            .and_then(|c| c.get("door"))
            .and_then(|d| d.get("isOpen"))
            .and_then(|v| v.as_bool());
    }
    Some((item, bottom))
}

/// The one word of iOS 17's attributes a plan piece is picked by: a chair's
/// type, a sofa's, a table's shape (else its type), storage's. `unidentified`
/// says nothing, so it is dropped.
fn detail(entry: &Json) -> String {
    let Some(Json::Object(pairs)) = entry.get("attributes") else { return String::new() };
    let get = |key: &str| {
        pairs
            .iter()
            .find(|(k, _)| k == key)
            .and_then(|(_, v)| v.as_str())
            .filter(|v| !v.is_empty() && *v != "unidentified")
            .map(str::to_string)
    };
    for key in ["ChairType", "SofaType", "StorageType"] {
        if let Some(v) = get(key) {
            return v;
        }
    }
    // A coffee table is a coffee table whatever its shape; otherwise a
    // round one is round.
    match (get("TableType"), get("TableShapeType")) {
        (Some(t), _) if t == "coffee" => t,
        (_, Some(shape)) => shape,
        (Some(t), None) => t,
        _ => String::new(),
    }
}

/// `{"bed":{}}` → `bed`. An unrecognised name is kept rather than dropped, so a
/// category added in a future iOS draws as a plain rectangle instead of
/// vanishing off the plan.
fn category_name(value: &Json) -> Option<String> {
    match value {
        Json::Object(pairs) => pairs.first().map(|(key, _)| key.clone()),
        Json::Text(name) => Some(name.clone()),
        _ => None,
    }
}

// ------------------------------------------------------------- handing it on

/// The plan as JSON, for whichever app is drawing it.
///
/// Everything a drawing needs and nothing it does not: the corners are left to
/// be computed by the drawing, because the thickness a wall is *drawn* at is a
/// drawing convention and must never reach a measurement.
pub fn as_json(plan: &Plan) -> Json {
    let items: Vec<Json> = plan
        .items
        .iter()
        .map(|item| {
            Json::object(vec![
                ("part", Json::text(item.part.as_str())),
                ("x", Json::Number(item.centre.0 as f64)),
                ("y", Json::Number(item.centre.1 as f64)),
                ("length", Json::Number(item.size.0 as f64)),
                ("depth", Json::Number(item.size.1 as f64)),
                ("height", Json::Number(item.height as f64)),
                ("angle", Json::Number(item.angle as f64)),
                ("furnishing", Json::text(item.furnishing.as_str())),
                ("category", Json::text(&item.category)),
            ])
        })
        .collect();
    let (low, high) = plan.bounds;
    let (ceiling_low, ceiling_high) = plan.ceiling_range();
    Json::object(vec![
        ("items", Json::Array(items)),
        ("minX", Json::Number(low.0 as f64)),
        ("minY", Json::Number(low.1 as f64)),
        ("maxX", Json::Number(high.0 as f64)),
        ("maxY", Json::Number(high.1 as f64)),
        (
            "straightenedBy",
            Json::Number(plan.straightened_by as f64),
        ),
        ("ceiling", Json::Number(plan.ceiling() as f64)),
        ("ceilingLow", Json::Number(ceiling_low as f64)),
        ("ceilingHigh", Json::Number(ceiling_high as f64)),
        ("ceilingVaries", Json::Bool(plan.ceiling_varies())),
        (
            "rooms",
            Json::Array(plan.rooms.iter().map(|(name, _)| Json::text(name)).collect()),
        ),
    ])
}

// ------------------------------------------------- a room to check against

/// A room to check the drawing against, when there is no room to stand in.
///
/// The phone built this first (its Ref 140) for the reason that still holds
/// here: **a floor plan cannot be tested without a scan, and a scan needs
/// LiDAR** — which a Mac does not have and a simulator does not have. So this is
/// a hand-built room carrying every awkward property a real one has: an
/// **L-shape**, whose outer extent describes a wall that does not exist;
/// **scanned crooked** at 23°; a door, a window, and furniture of four kinds.
pub fn sample() -> Option<Plan> {
    let mut items: Vec<Item> = Vec::new();

    let mut wall = |from: (f32, f32), to: (f32, f32)| {
        let along = (to.0 - from.0, to.1 - from.1);
        items.push(Item::plain(
            Part::Wall,
            ((from.0 + to.0) / 2.0, (from.1 + to.1) / 2.0),
            ((along.0 * along.0 + along.1 * along.1).sqrt(), 0.0),
            2.48,
            along.1.atan2(along.0),
            Furnishing::Other,
        ));
    };
    // An L: 4.0 × 3.2 overall, with a 1.4 × 1.2 corner taken out of it.
    wall((0.0, 0.0), (4.0, 0.0));
    wall((4.0, 0.0), (4.0, 2.0));
    wall((4.0, 2.0), (2.6, 2.0));
    wall((2.6, 2.0), (2.6, 3.2));
    wall((2.6, 3.2), (0.0, 3.2));
    wall((0.0, 3.2), (0.0, 0.0));

    let quarter = std::f32::consts::FRAC_PI_2;
    items.push(Item::plain(Part::Door, (3.2, 0.0), (0.9, 0.0), 2.05, 0.0, Furnishing::Other));
    items.push(Item::plain(Part::Window, (0.0, 2.2), (1.2, 0.0), 1.24, quarter, Furnishing::Other));
    for (centre, size, height, angle, category) in [
        ((1.15, 1.05), (1.4, 2.0), 0.62, quarter, "bed"),
        ((2.9, 0.42), (1.7, 0.65), 0.76, 0.0, "table"),
        ((2.5, 1.25), (0.62, 0.62), 1.13, std::f32::consts::PI, "chair"),
        ((3.9, 1.4), (1.0, 0.09), 0.59, quarter, "television"),
    ] {
        let mut item = Item::plain(Part::Object, centre, size, height, angle, Furnishing::parse(category));
        item.category = category.into();
        items.push(item);
    }

    let crooked = 23.0_f32.to_radians();
    let pivot = (2.0_f32, 1.6_f32);
    Plan::from_items(items.iter().map(|i| i.turned(crooked, pivot)).collect())
}
