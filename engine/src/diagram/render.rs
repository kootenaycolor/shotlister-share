//! The diagram, worked out into shapes.
//!
//! This is the view model: a flat list of paths, words, badges and pictures,
//! each saying which element it belongs to and which *ink* it wants. An ink is
//! a role (`wall`, `cast`, `beam`…) or a colour he set by hand; each shell
//! turns roles into its own palette — the Mac's light and dark, the portal's
//! dark, paper's white. Everything geometric is decided here, once.
//!
//! Lengths are metres, except what is marked **fixed**: words, pills and
//! badges that stay the same size on screen at every zoom, the way labels on
//! a map do. A fixed thing is anchored at a point on the plan and sized in
//! points.

use super::{frame, gels, lampscale, lens, length_text, norm_deg, plot, symbols, Diagram, El, Kind};

// ---------------------------------------------------------------- the list

#[derive(Clone, Debug, PartialEq)]
pub enum Ink {
    None,
    /// A palette role, looked up by whoever draws.
    Role(&'static str),
    /// `#rrggbb`, and how much of it.
    Hex(String, f64),
}

impl Ink {
    pub fn hex(h: &str) -> Ink {
        Ink::Hex(h.to_string(), 1.0)
    }
    pub fn with_alpha(self, a: f64) -> Ink {
        match self {
            Ink::Hex(h, _) => Ink::Hex(h, a),
            other => other,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Seg {
    M(f64, f64),
    L(f64, f64),
    C(f64, f64, f64, f64, f64, f64),
    Z,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Geom {
    Path(Vec<Seg>),
    /// Words. `size` is metres of height when drawn with the plan, points when
    /// fixed. `rot` is degrees clockwise.
    Text {
        x: f64,
        y: f64,
        text: String,
        size: f64,
        anchor: &'static str,
        bold: bool,
        rot: f64,
        fixed: bool,
        /// A band of paper behind it, so a dimension reads over a line.
        halo: bool,
        /// A patch of paper behind the whole name, so whatever line it lies
        /// across — a wall, the grid, a beam's edge — breaks round it.
        patch: bool,
        /// How far the plan moved a piece's name off its spot under the
        /// piece to keep it clear (`place_names`), metres on the page. A
        /// shell that lets the name be dragged starts from here.
        shift: (f64, f64),
        /// **The second line in grey** (Back to Paper, 2026-10-04): the ink
        /// every line after the first is drawn in — a callout's note, gels
        /// and Off under its name. `Ink::None` draws them all in the fill.
        under: Ink,
        /// How many lines lead in the first ink before `under` takes over:
        /// a Name of several lines (2026-10-17). One for most.
        lead: usize,
    },
    /// A fixed rounded label: a shot's number, a person's name.
    Pill { x: f64, y: f64, text: String, size: f64, ink: Ink },
    /// A fixed round number: which beat a ghost is.
    Badge { x: f64, y: f64, text: String, ink: Ink },
    Image { media: String, x: f64, y: f64, w: f64, h: f64, rot: f64 },
}

#[derive(Clone, Debug, PartialEq)]
pub struct Shape {
    /// The element it belongs to, or empty for the plan's own furniture.
    pub el: String,
    /// What part of it: `body`, `cone`, `beam`, `ghost`, `path`, `label`,
    /// `tag`, `dim`, `cut`. A shell uses it to hit a tag, or to leave the
    /// cones out of a thumbnail.
    pub part: &'static str,
    pub geom: Geom,
    pub fill: Ink,
    pub stroke: Ink,
    /// Stroke weight in points, the same at every zoom.
    pub line: f64,
    /// Empty, `dash` or `dot`.
    pub dash: &'static str,
    pub alpha: f64,
    /// A radial fade: the fill is full at (x, y) and gone at radius r.
    pub fade: Option<(f64, f64, f64)>,
}

impl Shape {
    pub fn new(el: &str, part: &'static str, geom: Geom) -> Shape {
        Shape {
            el: el.to_string(),
            part,
            geom,
            fill: Ink::None,
            stroke: Ink::None,
            line: 1.0,
            dash: "",
            alpha: 1.0,
            fade: None,
        }
    }
}

/// What the plan needs to know about the film around it.
#[derive(Clone, Debug, Default)]
pub struct Context {
    /// shot id → (its number, as printed; its Lens as typed)
    pub shots: Vec<(String, String, String)>,
    /// cast id → name
    pub cast: Vec<(String, String)>,
    /// shot id → its lead frame, by media name (`<hash>.<ext>`, as pictures
    /// are named), and its height over its width — for a camera that lays
    /// its frame on the plan. Only shots with a still picture.
    pub frames: Vec<(String, String, f64)>,
    /// Where the scene is shot, as latitude and longitude — for the sun.
    pub place: Option<(f64, f64)>,
    /// The scene's shoot day (`2026-09-27`) and its time of day (`DAY`).
    pub date: String,
    pub time_of_day: String,
    /// Minutes ahead of UTC at the place, when the shell knows; otherwise
    /// guessed from the longitude.
    pub utc_offset: Option<f64>,
    /// Each character's colour, as the Cast column's chip wears it: a name
    /// (lower case) and a hex. A name not listed wears `cast_ink`.
    pub cast_colours: Vec<(String, String)>,
    /// The Cast column's own colour, for a character given none of their
    /// own — empty when the film has no Cast column.
    pub cast_ink: String,
    /// The film's cameras: id, name, and the sensor he typed for it.
    pub units: Vec<(String, String, Option<lens::Gate>)>,
    /// shot id → its camera (unit id), and a zoom's focal length on it.
    pub shot_units: Vec<(String, String)>,
    pub shot_focals: Vec<(String, f64)>,
    /// The film's frame, width over height (2.39, 0.5625 for 9:16); 0 when
    /// unknown. The cone is the part of the sensor that frame covers.
    pub ratio: f64,
}

impl Context {
    pub fn shot(&self, id: &str) -> Option<(&str, &str)> {
        self.shots
            .iter()
            .find(|s| s.0 == id)
            .map(|s| (s.1.as_str(), s.2.as_str()))
    }
    pub fn shot_unit(&self, shot: &str) -> Option<&str> {
        self.shot_units.iter().find(|s| s.0 == shot).map(|s| s.1.as_str())
    }
    pub fn shot_focal(&self, shot: &str) -> Option<f64> {
        self.shot_focals.iter().find(|s| s.0 == shot).map(|s| s.1)
    }
    pub fn frame(&self, shot: &str) -> Option<(&str, f64)> {
        self.frames.iter().find(|f| f.0 == shot).map(|f| (f.1.as_str(), f.2))
    }
    pub fn cast_name(&self, id: &str) -> Option<&str> {
        self.cast.iter().find(|c| c.0 == id).map(|c| c.1.as_str())
    }
    /// A character's colour, by name, the way their chip shows it.
    pub fn character_colour(&self, name: &str) -> Option<&str> {
        let want = name.trim().to_lowercase();
        if want.is_empty() {
            return None;
        }
        self.cast_colours
            .iter()
            .find(|c| c.0 == want)
            .map(|c| c.1.as_str())
            .or_else(|| (!self.cast_ink.is_empty()).then_some(self.cast_ink.as_str()))
    }
}

#[derive(Clone, Debug)]
pub struct Options {
    /// Which beat to stand everything at. Everything else it does is a ghost.
    pub beat: u32,
    /// How far from this beat toward the next, 0 to 1 — playback, where a
    /// move is watched happening rather than jumped between.
    pub tween: f64,
    pub sel: Vec<String>,
    /// Paper: every cone alike, nothing picked, no ghosts' numbers greyed.
    pub paper: bool,
    /// How big the plan is shown, in points to the metre, so names are
    /// kept apart at the size they are drawn. 0 for the Mac's opening zoom.
    pub scale: f64,
    /// **The piece whose words are being typed on the plan** (Back to
    /// Paper, Batch 2, fix round 2): its name is placed and drawn even if
    /// he hid it, so the cursor stands where the words will be. On screen
    /// only; empty otherwise.
    pub typing: String,
    /// **Lettered as the sheet letters it** (Ref 1511): `scale` is the
    /// page's own, and names, words and marks are drawn at the sheet's
    /// sizes for a plan shrunk that far (`lettering`). Off, they are their
    /// full page size: a screen that shrinks them itself, the portal's
    /// picture.
    pub page: bool,
}

impl Default for Options {
    fn default() -> Options {
        Options { beat: 1, tween: 0.0, sel: Vec::new(), paper: false, scale: 0.0, typing: String::new(), page: false }
    }
}

/// How big a plan's words and marks stand against their full page size
/// (`NAME_PT`, `plot::MARK_PT`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Lettering {
    pub words: f64,
    pub marks: f64,
}

/// A callout's size on a sheet whose plan stands at 40 points to the metre
/// or larger — a room — in points: the Proposal's (design/32), and a
/// printed plot's.
pub const PAGE_WORDS_PT: f64 = 8.0;
/// …and the smallest it gets, however far a plan is shrunk to fit: still
/// read on a printed page at arm's length.
pub const PAGE_WORDS_MIN_PT: f64 = 6.5;
/// The smallest a lamp's mark gets on a sheet, points: a plan shrunk to a
/// backyard still shows every lamp.
pub const PAGE_MARK_MIN_PT: f64 = 7.0;

/// **The sheet's lettering** (Ref 1511, 2026-10-04): the sheet fits a plan
/// to one page, so a backyard is drawn at a third of the scale of a room;
/// were its words and marks the same size on the page as a room's, they
/// would dwarf the set, as they did on Call Her Back's scene 14. So:
///
/// - **Words** — every name, callout, length and Words — are 8 points on
///   a plan at 40 points to the metre or larger, and ease down as the plan
///   is shrunk, with the cube root of how far, never under 6.5 points.
/// - **Marks** — a lamp's mark, a camera — keep the size against the plan
///   that the screen gave them before the sheet (Back to Paper, Batch 1:
///   their 20 points at 60 points to the metre, a third of a metre), never
///   under 7 points on the page, never over their full 20.
///
/// Off the sheet (`Options::page` false), both are 1.
pub fn lettering(opt: &Options) -> Lettering {
    if !opt.page {
        return Lettering { words: 1.0, marks: 1.0 };
    }
    page_lettering(opt.scale)
}

/// The sheet's lettering for a plan drawn at `scale` points to the metre.
pub fn page_lettering(scale: f64) -> Lettering {
    let s = if scale > 0.0 { scale } else { NOMINAL_SCALE };
    let words = (PAGE_WORDS_PT * (s / 40.0).cbrt()).clamp(PAGE_WORDS_MIN_PT, PAGE_WORDS_PT) / NAME_PT;
    let marks = (s / NOMINAL_SCALE).clamp(PAGE_MARK_MIN_PT / plot::MARK_PT, 1.0);
    Lettering { words, marks }
}

// ---------------------------------------------------------------- geometry

/// Turn and place local points.
#[derive(Clone, Copy)]
pub struct Xf {
    cx: f64,
    cy: f64,
    c: f64,
    s: f64,
}

impl Xf {
    pub fn new(cx: f64, cy: f64, rot_deg: f64) -> Xf {
        let r = rot_deg.to_radians();
        Xf { cx, cy, c: r.cos(), s: r.sin() }
    }
    /// A shape drawn about the origin, moved and turned into place: a
    /// path point by point, a picture by its centre and its turn.
    pub fn shape(&self, s: &mut Shape) {
        match &mut s.geom {
            Geom::Path(p) => *p = self.path(p),
            Geom::Image { x, y, rot, .. } => {
                let (nx, ny) = self.p(*x, *y);
                *x = nx;
                *y = ny;
                *rot += self.s.atan2(self.c).to_degrees();
            }
            // Words move with it and stay level.
            Geom::Text { x, y, .. } => {
                let (nx, ny) = self.p(*x, *y);
                *x = nx;
                *y = ny;
            }
            _ => {}
        }
    }
    pub fn p(&self, x: f64, y: f64) -> (f64, f64) {
        (self.cx + x * self.c - y * self.s, self.cy + x * self.s + y * self.c)
    }
    pub fn seg(&self, s: Seg) -> Seg {
        match s {
            Seg::M(x, y) => {
                let (a, b) = self.p(x, y);
                Seg::M(a, b)
            }
            Seg::L(x, y) => {
                let (a, b) = self.p(x, y);
                Seg::L(a, b)
            }
            Seg::C(x1, y1, x2, y2, x, y) => {
                let (a1, b1) = self.p(x1, y1);
                let (a2, b2) = self.p(x2, y2);
                let (a, b) = self.p(x, y);
                Seg::C(a1, b1, a2, b2, a, b)
            }
            Seg::Z => Seg::Z,
        }
    }
    pub fn path(&self, segs: &[Seg]) -> Vec<Seg> {
        segs.iter().map(|s| self.seg(*s)).collect()
    }
}

pub fn rect(x: f64, y: f64, w: f64, h: f64) -> Vec<Seg> {
    vec![Seg::M(x, y), Seg::L(x + w, y), Seg::L(x + w, y + h), Seg::L(x, y + h), Seg::Z]
}

/// A rectangle with its corners rounded by `r`.
pub fn rrect(x: f64, y: f64, w: f64, h: f64, r: f64) -> Vec<Seg> {
    let r = r.min(w / 2.0).min(h / 2.0).max(0.0);
    if r <= 0.0 {
        return rect(x, y, w, h);
    }
    let k = 0.5523 * r;
    vec![
        Seg::M(x + r, y),
        Seg::L(x + w - r, y),
        Seg::C(x + w - r + k, y, x + w, y + r - k, x + w, y + r),
        Seg::L(x + w, y + h - r),
        Seg::C(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h),
        Seg::L(x + r, y + h),
        Seg::C(x + r - k, y + h, x, y + h - r + k, x, y + h - r),
        Seg::L(x, y + r),
        Seg::C(x, y + r - k, x + r - k, y, x + r, y),
        Seg::Z,
    ]
}

pub fn ellipse(cx: f64, cy: f64, rx: f64, ry: f64) -> Vec<Seg> {
    let (kx, ky) = (0.5523 * rx, 0.5523 * ry);
    vec![
        Seg::M(cx + rx, cy),
        Seg::C(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry),
        Seg::C(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy),
        Seg::C(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry),
        Seg::C(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy),
        Seg::Z,
    ]
}

pub fn circle(cx: f64, cy: f64, r: f64) -> Vec<Seg> {
    ellipse(cx, cy, r, r)
}

pub fn line(x1: f64, y1: f64, x2: f64, y2: f64) -> Vec<Seg> {
    vec![Seg::M(x1, y1), Seg::L(x2, y2)]
}

pub fn poly(pts: &[(f64, f64)], closed: bool) -> Vec<Seg> {
    let mut out = Vec::with_capacity(pts.len() + 1);
    for (i, (x, y)) in pts.iter().enumerate() {
        out.push(if i == 0 { Seg::M(*x, *y) } else { Seg::L(*x, *y) });
    }
    if closed && !out.is_empty() {
        out.push(Seg::Z);
    }
    out
}

/// An arc of a circle as cubic pieces, starting with a move unless `join`.
/// Angles in degrees, clockwise; it runs from `a0` to `a1` whichever way.
pub fn arc(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, join: bool) -> Vec<Seg> {
    let mut out = Vec::new();
    let sweep = a1 - a0;
    let n = ((sweep.abs() / 90.0).ceil() as usize).max(1);
    let step = sweep / n as f64;
    let at = |a: f64| (cx + r * a.to_radians().cos(), cy + r * a.to_radians().sin());
    let (sx, sy) = at(a0);
    out.push(if join { Seg::L(sx, sy) } else { Seg::M(sx, sy) });
    for i in 0..n {
        let t0 = (a0 + step * i as f64).to_radians();
        let t1 = (a0 + step * (i + 1) as f64).to_radians();
        let k = 4.0 / 3.0 * ((t1 - t0) / 4.0).tan();
        let (p0x, p0y) = (cx + r * t0.cos(), cy + r * t0.sin());
        let (p3x, p3y) = (cx + r * t1.cos(), cy + r * t1.sin());
        out.push(Seg::C(
            p0x - k * r * t0.sin(),
            p0y + k * r * t0.cos(),
            p3x + k * r * t1.sin(),
            p3y - k * r * t1.cos(),
            p3x,
            p3y,
        ));
    }
    out
}

/// A smooth curve through points (Catmull–Rom, as cubic pieces).
pub fn smooth(pts: &[(f64, f64)]) -> Vec<Seg> {
    if pts.len() < 3 {
        return poly(pts, false);
    }
    let mut out = vec![Seg::M(pts[0].0, pts[0].1)];
    for i in 0..pts.len() - 1 {
        let p0 = if i == 0 { pts[0] } else { pts[i - 1] };
        let p1 = pts[i];
        let p2 = pts[i + 1];
        let p3 = if i + 2 < pts.len() { pts[i + 2] } else { pts[i + 1] };
        out.push(Seg::C(
            p1.0 + (p2.0 - p0.0) / 6.0,
            p1.1 + (p2.1 - p0.1) / 6.0,
            p2.0 - (p3.0 - p1.0) / 6.0,
            p2.1 - (p3.1 - p1.1) / 6.0,
            p2.0,
            p2.1,
        ));
    }
    out
}

/// A line element's run, bent by its curve, as points close enough to draw
/// rails, lanes and hits along.
pub fn line_points(e: &El) -> Vec<(f64, f64)> {
    if e.kind == Kind::Wall {
        return super::walls::run(e);
    }
    // A ruler runs through its markers.
    if e.kind == Kind::Measure && e.points.len() >= 2 {
        return super::walls::corners(e);
    }
    super::walls::bent((e.x, e.y), (e.x2, e.y2), e.curve)
}

/// A line offset sideways by `d` (left of travel is negative).
fn offset(pts: &[(f64, f64)], d: f64) -> Vec<(f64, f64)> {
    let n = pts.len();
    (0..n)
        .map(|i| {
            let a = pts[i.saturating_sub(1)];
            let b = pts[(i + 1).min(n - 1)];
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let len = (dx * dx + dy * dy).sqrt().max(1e-9);
            (pts[i].0 - dy / len * d, pts[i].1 + dx / len * d)
        })
        .collect()
}

fn band(pts: &[(f64, f64)], half: f64) -> Vec<Seg> {
    let left = offset(pts, -half);
    let mut right = offset(pts, half);
    right.reverse();
    let mut all = left;
    all.extend(right);
    poly(&all, true)
}

fn walk(pts: &[(f64, f64)]) -> f64 {
    pts.windows(2)
        .map(|w| ((w[1].0 - w[0].0).powi(2) + (w[1].1 - w[0].1).powi(2)).sqrt())
        .sum()
}

/// A point and the heading at a distance along a run.
fn along(pts: &[(f64, f64)], at: f64) -> ((f64, f64), f64) {
    let mut left = at;
    for w in pts.windows(2) {
        let l = ((w[1].0 - w[0].0).powi(2) + (w[1].1 - w[0].1).powi(2)).sqrt();
        let heading = (w[1].1 - w[0].1).atan2(w[1].0 - w[0].0).to_degrees();
        if left <= l || l == 0.0 {
            let t = if l == 0.0 { 0.0 } else { left / l };
            return ((w[0].0 + (w[1].0 - w[0].0) * t, w[0].1 + (w[1].1 - w[0].1) * t), heading);
        }
        left -= l;
    }
    let n = pts.len();
    let h = if n >= 2 { (pts[n - 1].1 - pts[n - 2].1).atan2(pts[n - 1].0 - pts[n - 2].0).to_degrees() } else { 0.0 };
    (pts[n - 1], h)
}

/// An arrowhead at a tip, pointing along `heading`, `size` metres long.
fn head(tip: (f64, f64), heading: f64, size: f64) -> Vec<Seg> {
    let x = Xf::new(tip.0, tip.1, heading);
    let a = x.p(-size, -size * 0.55);
    let b = x.p(-size, size * 0.55);
    poly(&[a, tip, b, (x.p(-size * 0.7, 0.0))], true)
}

/// Words turned to lie along a heading, but never upside down.
fn readable(deg: f64) -> f64 {
    let d = norm_deg(deg);
    if d > 90.0 && d < 270.0 {
        d - 180.0
    } else if d >= 270.0 {
        d - 360.0
    } else {
        d
    }
}

/// A beam's tint, from its colour temperature: tungsten amber through to
/// daylight blue.
pub fn kelvin_hex(k: f64) -> &'static str {
    if k <= 0.0 {
        return "#F2B33D";
    }
    match k as i64 {
        ..=2400 => "#FF9E3D",
        2401..=2900 => "#FFB04A",
        2901..=3500 => "#FFC062",
        3501..=4200 => "#FFD690",
        4201..=5000 => "#FFEBC4",
        5001..=6000 => "#DDEBFF",
        _ => "#C4DCFF",
    }
}

/// Whether white or ink reads better on a colour.
pub fn text_on(hex: &str) -> &'static str {
    let h = hex.trim_start_matches('#');
    if h.len() < 6 {
        return "#FFFFFF";
    }
    let v = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0) as f64 / 255.0;
    let lum = 0.2126 * v(0) + 0.7152 * v(2) + 0.0722 * v(4);
    if lum > 0.62 {
        "#17171A"
    } else {
        "#FFFFFF"
    }
}

fn is_hex(s: &str) -> bool {
    let h = s.trim_start_matches('#');
    s.starts_with('#') && (h.len() == 6 || h.len() == 3) && h.chars().all(|c| c.is_ascii_hexdigit())
}

/// An element's own colour if he set one, else the role.
fn own(e: &El, role: &'static str) -> Ink {
    if is_hex(&e.color) {
        Ink::hex(&e.color)
    } else {
        Ink::Role(role)
    }
}

// ---------------------------------------------------------------- drawing

struct Out {
    tiers: Vec<Vec<Shape>>,
    /// Pieces' names, waiting to be placed clear of each other once every
    /// piece is drawn (`place_names`).
    names: Vec<Name>,
    /// **View › Labels** (Back to Paper, Batch 2): off, no piece wears its
    /// name — a lamp's, a frame's, a set piece's, a person's, a road's, an
    /// arrow's, a shape's. Lengths and Words are not names and stay.
    labels: bool,
    /// The piece whose words are being typed (`Options::typing`): its name
    /// is asked for even when hidden or View › Labels is off.
    typing: String,
    /// How big words are drawn against their page size (`lettering`):
    /// every fixed word and pill put down is this much its size.
    words: f64,
    /// Pieces that share a label: named there, not each on its own.
    tied: Vec<String>,
    /// Plan Settings › Counts: "3× Key Light" (2026-10-17, off by default).
    counts: bool,
    /// Plan Settings › All Caps: words in capitals (off: as typed).
    caps: bool,
}

// The passes, bottom to top.
const FLOOR: usize = 0;
const SET: usize = 1;
const LIGHT: usize = 2;
const WALLS: usize = 3;
const CUTS: usize = 4;
const PATHS: usize = 5;
const STANDING: usize = 6;
const WORDS: usize = 7;
const LABELS: usize = 8;

impl Out {
    /// Put a shape down: its words at the sheet's size (`lettering`).
    fn put(&mut self, tier: usize, mut s: Shape) {
        if (self.words - 1.0).abs() > 1e-9 {
            match &mut s.geom {
                Geom::Text { size, fixed: true, .. } | Geom::Pill { size, .. } => *size *= self.words,
                _ => {}
            }
        }
        self.tiers[tier].push(s);
    }
}

fn filled(el: &str, part: &'static str, segs: Vec<Seg>, fill: Ink, stroke: Ink, line: f64) -> Shape {
    let mut s = Shape::new(el, part, Geom::Path(segs));
    s.fill = fill;
    s.stroke = stroke;
    s.line = line;
    s
}

fn stroked(el: &str, part: &'static str, segs: Vec<Seg>, stroke: Ink, line: f64, dash: &'static str) -> Shape {
    let mut s = Shape::new(el, part, Geom::Path(segs));
    s.stroke = stroke;
    s.line = line;
    s.dash = dash;
    s
}

fn fixed_text(el: &str, part: &'static str, x: f64, y: f64, text: &str, size: f64, ink: Ink, anchor: &'static str, rot: f64, halo: bool) -> Shape {
    let mut s = Shape::new(
        el,
        part,
        Geom::Text { x, y, text: text.to_string(), size, anchor, bold: false, rot, fixed: true, halo, patch: false, shift: (0.0, 0.0), under: Ink::None, lead: 1 },
    );
    s.fill = ink;
    s
}

/// **A piece's name over its Note** (his note, 2026-10-05: *"alll items
/// should be able to have a note"*): the Note, `caption`, on the line under
/// the name, or alone when it has no name. A lamp's and a frame's Note is
/// their `label` and is written by `lamp_lines` and `frame_lines`.
pub fn with_note(e: &El, name: &str) -> String {
    let note = e.caption.trim();
    match (name.trim().is_empty(), note.is_empty()) {
        (_, true) => name.to_string(),
        (true, false) => note.to_string(),
        (false, false) => format!("{name}\n{note}"),
    }
}

/// Whether a piece has words to wear: a name or a Note.
fn has_words(e: &El) -> bool {
    !e.label.trim().is_empty() || !e.caption.trim().is_empty()
}

/// A piece's own words drawn where its kind puts them: its name, and its
/// Note under it in grey.
fn label_text(e: &El, x: f64, y: f64, name: &str, size: f64, ink: Ink, rot: f64) -> Shape {
    let mut t = fixed_text(&e.id, "label", x, y, &with_note(e, name), size, ink, "middle", rot, true);
    if let Geom::Text { under, lead, .. } = &mut t.geom {
        *under = Ink::Role("ink2");
        *lead = lines_in(name).max(1);
    }
    t
}

/// **Lamps throw no light on the plan for now** — his call, 2026-10-01:
/// *"just kill the entire beam idea right now, except for the sunlight one
/// across the board … we need to calculate the beam diameters of every
/// single light on this list."* A beam is not a point: a soft panel throws
/// from its whole face, a spot from a pinhole, and a mat pointed down
/// lights straight down. Until each lamp has its real size of source, no
/// beams, bounce, beam notes or light levels — every lamp's settings are
/// kept in the film, untouched, for when this comes back. The sun stays.
pub const LAMP_BEAMS: bool = false;

/// Whether lamps' beams are drawn on this plan.
pub fn beams_on(d: &Diagram) -> bool {
    LAMP_BEAMS && d.settings.beams
}

/// **A lighting plot, not a picture** (his ruling, 2026-10-03): lights
/// that give light are drawn as a small mark and named by a callout.
pub fn plot_on(_d: &Diagram) -> bool {
    true
}

/// What a plot writes under a light's name: what is done to an existing
/// one.
pub fn plot_action(e: &El) -> &'static str {
    match e.action.as_str() {
        "off" => "Off",
        "swap" => "Swap",
        "dim" => "Dim",
        _ => "",
    }
}

/// Whether light levels are worked out on this plan.
pub fn levels_on(d: &Diagram) -> bool {
    LAMP_BEAMS && d.settings.levels
}

/// Every shape the plan is made of, bottom to top.
pub fn render(d: &Diagram, ctx: &Context, opt: &Options) -> Vec<Shape> {
    // **A plot draws no moves** (his call, 2026-10-03: camera and actor
    // moves are cut). They stay in the film, untouched; only the drawing
    // leaves them out.
    let still;
    let d: &Diagram = if d.els.iter().any(|e| !e.steps.is_empty()) {
        let mut c = d.clone();
        for e in &mut c.els {
            e.steps.clear();
            e.lead = 0;
            e.beat = 1;
        }
        still = c;
        &still
    } else {
        d
    };
    let marks = Marks { looks: plot::looks(d) };
    let typing = if opt.paper { String::new() } else { opt.typing.clone() };
    let tied: Vec<String> = d.els.iter().filter(|e| tied_to(d, e).is_some()).map(|e| e.id.clone()).collect();
    let mut out = Out { tiers: vec![Vec::new(); 9], names: Vec::new(), labels: d.settings.labels, typing, words: lettering(opt).words, tied, counts: d.settings.counts, caps: d.settings.caps };
    for e in d.els.iter().filter(|e| !e.hidden) {
        let before: Vec<usize> = out.tiers.iter().map(|t| t.len()).collect();
        match e.kind {
            Kind::Wall => wall(&mut out, e, d, opt),
            Kind::Door | Kind::Window | Kind::Opening => opening(&mut out, e, opt),
            Kind::Set => set(&mut out, e, opt),
            Kind::Camera => camera(&mut out, e, d, ctx, opt),
            Kind::Cast => cast(&mut out, e, ctx, opt),
            Kind::Light => light(&mut out, e, d, opt, &marks),
            Kind::Track => track(&mut out, e, d),
            Kind::Road => road(&mut out, e, d),
            Kind::Text if shared_label(d, e) => label_for_many(&mut out, e, d, ctx, opt, &marks),
            Kind::Text => text(&mut out, e),
            Kind::Measure if !d.settings.measures => {}
            Kind::Measure => measure(&mut out, e, d, opt),
            Kind::Arrow => arrow(&mut out, e),
            Kind::Shape => shape(&mut out, e),
            Kind::Cable | Kind::Stroke => polyline(&mut out, e),
            Kind::Image => image(&mut out, e),
            Kind::Note => note(&mut out, e),
        }
        name_styled(&mut out, e, d, opt, &before);
        // **Underneath** (his ask, 2026-10-03): a piece he sent under,
        // drawn below everything — a ruler out of the furniture's way.
        if e.under {
            let mut low = Vec::new();
            for (t, from) in before.iter().enumerate() {
                if t == FLOOR {
                    continue;
                }
                let mut i = *from;
                while i < out.tiers[t].len() {
                    if out.tiers[t][i].el == e.id {
                        low.push(out.tiers[t].remove(i));
                    } else {
                        i += 1;
                    }
                }
            }
            out.tiers[FLOOR].extend(low);
        }
        // What a picked piece is aimed at: a fine dashed line to it, on
        // screen only.
        if !opt.paper && !e.aim.is_empty() && opt.sel.contains(&e.id) {
            if let Some(t) = d.els.iter().find(|t| t.id == e.aim) {
                let (x, y, _) = placed(e, opt);
                let (tx, ty) = if t.kind.is_line() { t.centre() } else { let p = placed(t, opt); (p.0, p.1) };
                out.put(LABELS, stroked(&e.id, "aim", line(x, y, tx, ty), Ink::Role("dim"), 1.0, "dash"));
                // How far: a camera to the person it is on, a lamp to what
                // it lights — written on the line, in the film's units.
                if let Some(s) = aim_distance(e, t, (x, y), (tx, ty), &d.settings.units) {
                    out.put(LABELS, s);
                }
            }
        }
        // **Opacity fades the piece, never its name** (his note, 2026-10-01:
        // *"that doesn't mean the label changes opacity"*): a dimmed mat
        // still says what it is. Names placed later (`place_names`) are
        // never touched; those drawn here are passed over.
        // Lamps and frames fade too (Ref 1505, his words: "opacity is
        // good, more for frames though because they cover a large area"):
        // Batch 1's dashed "overhead" lamp is gone.
        if e.opacity < 1.0 {
            for (t, from) in before.iter().enumerate() {
                for s in &mut out.tiers[t][*from..] {
                    // A picture's marks stay at full strength (2026-10-15).
                    if !matches!(s.part, "label" | "tag" | "tie" | "mark") {
                        s.alpha *= e.opacity;
                    }
                }
            }
        }
    }
    place_names(&mut out, d, opt);
    if d.settings.sun || d.settings.north.abs() > 1e-9 {
        sun_and_north(&mut out, d, ctx);
    }
    let mut shapes: Vec<Shape> = out.tiers.into_iter().flatten().collect();
    // **Capitals, as the references write** (his note, 2026-10-03) — only
    // when he asks for them (2026-10-17: *"no caps if i want"*): Plan
    // Settings › All Caps. Off, every word is drawn as it was typed.
    {
        if d.settings.caps {
            for s in &mut shapes {
                if let Geom::Text { text, .. } = &mut s.geom {
                    *text = text.to_uppercase();
                }
            }
        }
        // His colours for the plot's categories, where he set them; the
        // rest in **three inks** (Back to Paper, his call 2026-10-04): red
        // for what we bring, blue for the camera, grey for what is there.
        let mine = |i: &mut Ink| {
            if let Ink::Role(r) = i {
                let r: &'static str = *r;
                // A practical's words follow the colour he gave practicals.
                let key = if r == "practicalword" { "practical" } else { r };
                *i = match d.settings.colours.iter().find(|(k, _)| k == key) {
                    Some((_, hex)) => Ink::hex(hex),
                    None => Ink::Role(plot::three_inks(r)),
                };
            }
        };
        for s in &mut shapes {
            mine(&mut s.fill);
            mine(&mut s.stroke);
            if let Geom::Pill { ink, .. } = &mut s.geom {
                mine(ink);
            }
        }
    }
    shapes
}

/// How big a plot's marks are, in metres, at the scale it is drawn.
pub fn mark_m(opt: &Options) -> f64 {
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    plot::MARK_PT * lettering(opt).marks / k
}

/// **The distance along an aim line** (SL-1318, Scenario's way): a small
/// pill at the line's middle, level, on its patch of paper — camera to the
/// person it is aimed at, a lamp to whatever it is aimed at. Nothing for
/// anything else, or when the two all but touch.
pub fn aim_distance(e: &El, t: &El, from: (f64, f64), to: (f64, f64), units: &str) -> Option<Shape> {
    let counts = (e.kind == Kind::Camera && t.kind == Kind::Cast) || e.kind == Kind::Light;
    let far = (to.0 - from.0).hypot(to.1 - from.1);
    if !counts || far < 0.3 {
        return None;
    }
    let mut s = fixed_text(&e.id, "aim", (from.0 + to.0) / 2.0, (from.1 + to.1) / 2.0, &length_text(far, units), 9.5, Ink::Role("ink2"), "middle", 0.0, false);
    if let Geom::Text { patch, .. } = &mut s.geom {
        *patch = true;
    }
    Some(s)
}

/// The clock the sun's time is read in, minutes ahead of UTC: the plan's own
/// saved zone, else the shell's moved to the sun's day (`sun::zone`, Ref
/// 1513), so the screen and the printed page read the same hour.
pub fn sun_zone(d: &Diagram, ctx: &Context, lat: f64, lon: f64, date: (i64, i64, i64), today: Option<(i64, i64, i64)>) -> f64 {
    d.settings.sun_tz.unwrap_or_else(|| super::sun::zone(lat, lon, date, ctx.utc_offset, today))
}

/// The sun's answer for this plan: its bearing and height, or why there is
/// none — no place, or night, or below the horizon.
pub fn sun_now(d: &Diagram, ctx: &Context) -> Result<(super::sun::Sun, f64), &'static str> {
    let (lat, lon) = ctx.place.ok_or("No location with an address")?;
    let date = if d.settings.sun_date.is_empty() { ctx.date.as_str() } else { d.settings.sun_date.as_str() };
    let (y, m, day) = super::sun::parse_date(date).ok_or("No shoot day")?;
    let minutes = if d.settings.sun_time.is_empty() {
        super::sun::time_for(&ctx.time_of_day).ok_or("Night")?
    } else {
        super::sun::parse_time(&d.settings.sun_time).ok_or("No time")?
    };
    let offset = sun_zone(d, ctx, lat, lon, (y, m, day), super::sun::today());
    Ok((super::sun::position(lat, lon, y, m, day, minutes, offset), minutes))
}

/// The day's sun for this plan's place and day — whatever the time says.
pub fn sun_day(d: &Diagram, ctx: &Context) -> Option<super::sun::Day> {
    let (lat, lon) = ctx.place?;
    let date = if d.settings.sun_date.is_empty() { ctx.date.as_str() } else { d.settings.sun_date.as_str() };
    let (y, m, day) = super::sun::parse_date(date)?;
    let offset = sun_zone(d, ctx, lat, lon, (y, m, day), super::sun::today());
    Some(super::sun::day(lat, lon, y, m, day, offset))
}

/// How far the plan is turned where it is shown, in degrees clockwise:
/// **not at all, now.** His note of 2026-09-29 took back 2026-09-27's
/// north-is-always-up: *"spinning the compass should not spin the set — the
/// sun should move around the set as it stays put."* The set stands as it
/// was drawn; the north arrow points wherever north is (`north_bearing`) and
/// the sun comes round to its true bearing. Kept, and every sum that shows
/// the plan still asks it, so turning the view for showing again would be
/// one line.
pub fn view_turn(_d: &Diagram) -> f64 {
    0.0
}

/// Where north lies on the plan as it is shown, in degrees clockwise from
/// straight up the page — the plan's own north less however the view is
/// turned. A compass bearing (the sun's azimuth) is drawn this much further
/// round.
pub fn north_bearing(d: &Diagram) -> f64 {
    norm_deg(d.settings.north + view_turn(d))
}

/// A point on the plan, where it is shown once the plan is turned `deg`
/// about the plan's origin. `turn_point(p, -deg)` takes it back.
pub fn turn_point(x: f64, y: f64, deg: f64) -> (f64, f64) {
    Xf::new(0.0, 0.0, deg).p(x, y)
}

/// Every shape turned the way the plan is shown. Words that ride along a
/// line turn with it and are kept from reading upside down; a label that
/// stands upright stays upright.
pub fn turn_shapes(shapes: &mut [Shape], deg: f64) {
    if deg.abs() < 1e-9 {
        return;
    }
    let xf = Xf::new(0.0, 0.0, deg);
    for s in shapes.iter_mut() {
        if let Some((x, y, r)) = s.fade {
            let (nx, ny) = xf.p(x, y);
            s.fade = Some((nx, ny, r));
        }
        match &mut s.geom {
            Geom::Path(p) => *p = xf.path(p),
            Geom::Text { x, y, rot, fixed, anchor, .. } => {
                let (nx, ny) = xf.p(*x, *y);
                *x = nx;
                *y = ny;
                if !*fixed || rot.abs() > 1e-9 {
                    *rot = if *anchor == "middle" { readable(*rot + deg) } else { norm_deg(*rot + deg) };
                }
            }
            Geom::Pill { x, y, .. } | Geom::Badge { x, y, .. } => {
                let (nx, ny) = xf.p(*x, *y);
                *x = nx;
                *y = ny;
            }
            Geom::Image { x, y, rot, .. } => {
                let (nx, ny) = xf.p(*x, *y);
                *x = nx;
                *y = ny;
                *rot = norm_deg(*rot + deg);
            }
        }
    }
}

/// North, always when it has been turned; and, when asked, the sun.
///
/// Worked out where the plan is *shown* — turned so north is straight up —
/// and put back onto the plan, so every shell that turns the plan for
/// showing finds the compass off its top right, pointing up, and the sun at
/// its true bearing round the edge.
fn sun_and_north(out: &mut Out, d: &Diagram, ctx: &Context) {
    let turn = view_turn(d);
    // Shown → plan.
    let back = Xf::new(0.0, 0.0, -turn);
    let b = shown_bounds(d, turn, |_| true).unwrap_or(super::Aabb { x1: 0.0, y1: 0.0, x2: 4.0, y2: 3.0 });
    let r = ((b.x2 - b.x1).hypot(b.y2 - b.y1) / 2.0).max(1.5);

    // Sized to the plan, not to a person: a room gets a small compass and a
    // street a bigger one, and neither shouts over what is on it.
    let k = (r * 0.05).clamp(0.12, 1.2);
    // The north arrow, off the top right, pointing to north.
    let (nx, ny) = (b.x2 + k * 3.0, b.y1 - k * 1.5);
    let north = north_bearing(d);
    let up = Xf::new(nx, ny, -90.0 + north);
    let at = |p: (f64, f64)| back.p(p.0, p.1);
    out.put(LABELS, stroked("", "north", back.path(&circle(nx, ny, k)), Ink::Role("ink2"), 1.0, ""));
    let arrow = up.path(&poly(&[(k * 0.85, 0.0), (-k * 0.6, -k * 0.38), (-k * 0.35, 0.0), (-k * 0.6, k * 0.38)], true));
    out.put(LABELS, filled("", "north", back.path(&arrow), Ink::Role("ink2"), Ink::None, 0.0));
    let label = at(up.p(k * 1.7, 0.0));
    out.put(LABELS, fixed_text("", "north", label.0, label.1, "N", 10.0, Ink::Role("ink2"), "middle", 0.0, false));

    if !d.settings.sun {
        return;
    }
    let (nlx, nly) = at((nx, ny + k * 2.2));
    match sun_now(d, ctx) {
        // Drawn until it has gone: at sunrise and sunset its middle is just
        // under the horizon, and that is when its bearing matters most.
        Ok((sun, minutes)) if sun.altitude > -0.9 => {
            // A compass bearing, measured round from wherever north lies.
            let toward = -90.0 + sun.azimuth + north;
            let (dx, dy) = (toward.to_radians().cos(), toward.to_radians().sin());
            let ring = sun_ring(d);
            let (sk, (sx, sy), side) = (ring.k, ring.at(dx, dy), ring.side(dx, dy));
            if d.settings.sun_rays {
                rays(out, d, &b, (sx, sy), toward, r, sk, &back);
            }
            // The sun where it stands: a disc in a soft ring.
            let (px, py) = at((sx, sy));
            let mut glow = filled("", "sun", circle(px, py, sk * 1.9), Ink::Role("sun"), Ink::None, 0.0);
            glow.alpha = 0.22;
            out.put(LABELS, glow);
            out.put(LABELS, filled("", "sun", circle(px, py, sk), Ink::Role("sun"), Ink::None, 0.0));
            let clock = format!("{:02}:{:02}", (minutes / 60.0) as u32, (minutes % 60.0) as u32);
            let words = if sun.altitude < 0.5 { format!("Sun {clock} · on the horizon") } else { format!("Sun {clock} · {:.0}° up", sun.altitude) };
            // On the far side of the disc from the plan, so the words stay
            // off what is drawn: beside it on the left and right, over or
            // under it on the top and bottom.
            let (lx, ly, anchor) = if side {
                let (x, y) = at((sx + dx.signum() * sk * 2.3, sy));
                (x, y, if dx > 0.0 { "start" } else { "end" })
            } else {
                let (x, y) = at((sx, sy + if dy < 0.0 { -sk * 3.0 } else { sk * 3.0 }));
                (x, y, "middle")
            };
            out.put(LABELS, fixed_text("", "sun", lx, ly, &words, 10.0, Ink::Role("sunink"), anchor, 0.0, true));
        }
        Ok(_) => out.put(LABELS, fixed_text("", "sun", nlx, nly, "Sun Down", 10.0, Ink::Role("ink2"), "middle", 0.0, true)),
        Err(why) => out.put(LABELS, fixed_text("", "sun", nlx, nly, why, 10.0, Ink::Role("ink2"), "middle", 0.0, true)),
    }
}

/// Where the elements `take` keeps reach, as the plan is shown.
fn shown_bounds(d: &Diagram, turn: f64, take: impl Fn(&El) -> bool) -> Option<super::Aabb> {
    let mut b = super::Aabb { x1: f64::MAX, y1: f64::MAX, x2: f64::MIN, y2: f64::MIN };
    for e in d.els.iter().filter(|e| !e.hidden && take(e)) {
        let a = super::aabb(e);
        for (x, y) in [(a.x1, a.y1), (a.x2, a.y1), (a.x2, a.y2), (a.x1, a.y2)] {
            let (sx, sy) = turn_point(x, y, turn);
            b.x1 = b.x1.min(sx);
            b.y1 = b.y1.min(sy);
            b.x2 = b.x2.max(sx);
            b.y2 = b.y2.max(sy);
        }
    }
    (b.x1 <= b.x2).then_some(b)
}

/// The frame the sun goes round, as the plan is shown: a box a little
/// outside the plan, the sun where its bearing from the middle meets it.
///
/// **It hangs off what stands still** (his note, 2026-09-28: *"I can chase it
/// with my items"*). Measured off everything, the sun backed away from any
/// piece brought near it and slid off its bearing as the middle moved. So it
/// is measured off the place itself — walls, doors, windows, openings,
/// roads, a floor picture — and a person, a camera, a lamp or a piece of
/// furniture moved about never moves it. A plan with none of those is
/// measured off everything, on a coarse grid, so a small move is not
/// followed either.
pub struct SunRing {
    pub cx: f64,
    pub cy: f64,
    /// Half the frame's width and height: the plan's, and the margin.
    pub a: f64,
    pub b: f64,
    /// The sun's own size.
    pub k: f64,
}

impl SunRing {
    /// Where the sun stands for a bearing `(dx, dy)` as shown.
    pub fn at(&self, dx: f64, dy: f64) -> (f64, f64) {
        let t = (self.a / dx.abs().max(1e-9)).min(self.b / dy.abs().max(1e-9));
        (self.cx + dx * t, self.cy + dy * t)
    }
    /// Whether that is on the frame's left or right side, not its top or foot.
    pub fn side(&self, dx: f64, dy: f64) -> bool {
        self.a / dx.abs().max(1e-9) <= self.b / dy.abs().max(1e-9)
    }
    /// Everywhere the sun and its glow can be, whatever the hour.
    pub fn reach(&self) -> super::Aabb {
        let pad = self.k * 3.6;
        super::Aabb { x1: self.cx - self.a - pad, y1: self.cy - self.b - pad, x2: self.cx + self.a + pad, y2: self.cy + self.b + pad }
    }
}

/// Where the sun's disc stands on the plan (not as shown), when it is drawn.
pub fn sun_spot(d: &Diagram, ctx: &Context) -> Option<(f64, f64)> {
    let (sun, _) = sun_now(d, ctx).ok().filter(|(s, _)| s.altitude > -0.9)?;
    let toward = (-90.0 + sun.azimuth + north_bearing(d)).to_radians();
    let (x, y) = sun_ring(d).at(toward.cos(), toward.sin());
    Some(turn_point(x, y, -view_turn(d)))
}

/// See `SunRing`.
pub fn sun_ring(d: &Diagram) -> SunRing {
    let turn = view_turn(d);
    let standing = |e: &El| {
        matches!(e.kind, Kind::Wall | Kind::Door | Kind::Window | Kind::Opening | Kind::Road)
            || (e.kind == Kind::Image && e.role != "photo")
    };
    // Out to the next step of a coarse grid, so a small move is not followed.
    // `fine`: how many steps across half the box — scenery is rounded finer
    // than a plan with nothing standing, which has nothing else to hang on.
    let coarse = |b: super::Aabb, fine: f64| {
        let half = ((b.x2 - b.x1).hypot(b.y2 - b.y1) / 2.0).max(1.5);
        let step = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0].into_iter().find(|s| *s >= half / fine).unwrap_or(500.0);
        super::Aabb {
            x1: (b.x1 / step).floor() * step,
            y1: (b.y1 / step).floor() * step,
            x2: (b.x2 / step).ceil() * step,
            y2: (b.y2 / step).ceil() * step,
        }
    };
    // **The whole set** (his note, 2026-10-02: the sun sat inside a test project's
    // lawn and pavilion, which are lines, shapes and set pieces, not
    // walls). The scenery counts too — on the coarse grid, so a chair nudged
    // about still does not drag the sun with it. People, cameras, lamps and
    // annotations never count.
    let scenery = |e: &El| matches!(e.kind, Kind::Set | Kind::Shape | Kind::Stroke) || (e.kind == Kind::Arrow && e.head == "none");
    let b = match shown_bounds(d, turn, standing) {
        Some(walls) => match shown_bounds(d, turn, scenery).map(|b| coarse(b, 12.0)) {
            Some(s) => super::Aabb { x1: walls.x1.min(s.x1), y1: walls.y1.min(s.y1), x2: walls.x2.max(s.x2), y2: walls.y2.max(s.y2) },
            None => walls,
        },
        None => match shown_bounds(d, turn, |_| true) {
            Some(b) => coarse(b, 3.0),
            None => super::Aabb { x1: 0.0, y1: 0.0, x2: 4.0, y2: 3.0 },
        },
    };
    let r = ((b.x2 - b.x1).hypot(b.y2 - b.y1) / 2.0).max(1.5);
    let k = (r * 0.05).clamp(0.12, 1.2);
    // Clear of the dimension lines that stand off the walls.
    let margin = k * 4.0 + 0.3;
    SunRing { cx: (b.x1 + b.x2) / 2.0, cy: (b.y1 + b.y2) / 2.0, a: (b.x2 - b.x1) / 2.0 + margin, b: (b.y2 - b.y1) / 2.0 + margin, k }
}

/// The sun's light across the plan, in its colour: a few fine lines for
/// which way it falls, fading as they go; and, where it comes in through a
/// window, an opening or an open door, the pool it lays on the floor inside
/// — the light a scene is lit by. Walls stop it. Under the walls, like a
/// lamp's beam.
///
/// Worked out where the plan is shown; `back` puts it on the plan.
#[allow(clippy::too_many_arguments)]
fn rays(out: &mut Out, d: &Diagram, b: &super::Aabb, sun: (f64, f64), toward: f64, r: f64, k: f64, back: &Xf) {
    let turn = view_turn(d);
    let shown = |segs: Vec<((f64, f64), (f64, f64))>| -> Vec<((f64, f64), (f64, f64))> {
        segs.into_iter().map(|(p, q)| (turn_point(p.0, p.1, turn), turn_point(q.0, q.1, turn))).collect()
    };
    // What stops it, and every wall's whole line, gaps and all — crossing a
    // wall's line where it is not stopped is coming in through a gap.
    let solid = shown(super::shade::blockers(d));
    let lines_of_walls = shown(
        d.els
            .iter()
            .filter(|e| e.kind == Kind::Wall && !e.hidden)
            .flat_map(|w| line_points(w).windows(2).map(|p| (p[0], p[1])).collect::<Vec<_>>())
            .collect(),
    );
    // Along the light (`u`, away from the sun) and across it (`v`).
    let a = (toward + 180.0).to_radians();
    let (ux, uy) = (a.cos(), a.sin());
    let (vx, vy) = (-uy, ux);
    let pad = k * 1.5;
    let bx = [(b.x1 - pad, b.y1 - pad), (b.x2 + pad, b.y1 - pad), (b.x2 + pad, b.y2 + pad), (b.x1 - pad, b.y2 + pad)];
    let along = |p: &(f64, f64)| p.0 * ux + p.1 * uy;
    let across = |p: &(f64, f64)| p.0 * vx + p.1 * vy;
    let (u0, u1) = bx.iter().map(along).fold((f64::MAX, f64::MIN), |(lo, hi), u| (lo.min(u), hi.max(u)));
    let (v0, v1) = bx.iter().map(across).fold((f64::MAX, f64::MIN), |(lo, hi), v| (lo.min(v), hi.max(v)));
    let at = |u: f64, v: f64| (ux * u + vx * v, uy * u + vy * v);
    // Where a ray from the front crosses these lines, nearest first.
    let hits = |v: f64, segs: &[((f64, f64), (f64, f64))]| -> Vec<f64> {
        let (ox, oy) = at(u0, v);
        let mut ts: Vec<f64> = segs
            .iter()
            .filter_map(|(p, q)| {
                let (ex, ey) = (q.0 - p.0, q.1 - p.1);
                let den = ux * ey - uy * ex;
                if den.abs() < 1e-12 {
                    return None;
                }
                let (wx, wy) = (p.0 - ox, p.1 - oy);
                let t = (wx * ey - wy * ex) / den;
                let s = (wx * uy - wy * ux) / den;
                (t > 0.0 && (-1e-9..=1.0 + 1e-9).contains(&s)).then_some(t)
            })
            .collect();
        ts.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        ts
    };
    let stop = |v: f64| hits(v, &solid).first().copied().unwrap_or(u1 - u0);
    // The pool along one ray: from the gap it comes in by to the next wall
    // line it meets, if it gets in at all.
    let pool = |v: f64| -> Option<(f64, f64)> {
        let end = stop(v);
        let crossings = hits(v, &lines_of_walls);
        let enter = *crossings.iter().find(|t| **t < end - 1e-6)?;
        let leave = crossings.iter().copied().find(|t| *t > enter + 0.05).unwrap_or(end).min(end);
        (leave > enter + 0.02).then_some((enter, leave))
    };
    let (fx, fy) = back.p(sun.0, sun.1);
    let reach = (r * 2.0 + k * 6.0).max(u1 - u0);

    // The pools: fine strips, so a window lets in a beam its own width.
    let strips = (((v1 - v0) / 0.05).ceil() as usize).clamp(24, 200);
    let w = (v1 - v0) / strips as f64;
    let edges: Vec<Option<(f64, f64)>> = (0..=strips).map(|i| pool(v0 + w * i as f64)).collect();
    let mut wash: Vec<Seg> = Vec::new();
    for i in 0..strips {
        if let (Some((ea, la)), Some((eb, lb))) = (edges[i], edges[i + 1]) {
            let (va, vb) = (v0 + w * i as f64, v0 + w * (i + 1) as f64);
            let pts = [at(u0 + ea, va), at(u0 + la, va), at(u0 + lb, vb), at(u0 + eb, vb)];
            wash.extend(back.path(&poly(&pts, true)));
        }
    }
    if !wash.is_empty() {
        let mut s = filled("", "sunlight", wash, Ink::Role("sun"), Ink::None, 0.0);
        s.fade = Some((fx, fy, reach));
        s.alpha = 0.36;
        out.put(LIGHT, s);
    }

    // The fine lines, inside the plan's frame, stopped by walls.
    let framed = |pts: &[(f64, f64)]| -> Vec<(f64, f64)> {
        let mut p = clip(pts, |q| q.0 - bx[0].0);
        p = clip(&p, |q| bx[2].0 - q.0);
        p = clip(&p, |q| q.1 - bx[0].1);
        clip(&p, |q| bx[2].1 - q.1)
    };
    let lines = 7;
    for i in 0..lines {
        let v = v0 + (v1 - v0) * (i as f64 + 0.5) / lines as f64;
        let len = stop(v);
        let half = k * 0.035;
        let pts = framed(&[at(u0, v - half), at(u0 + len, v - half), at(u0 + len, v + half), at(u0, v + half)]);
        if pts.len() < 3 {
            continue;
        }
        let mut l = filled("", "sunlight", back.path(&poly(&pts, true)), Ink::Role("sun"), Ink::None, 0.0);
        l.fade = Some((fx, fy, reach));
        l.alpha = 0.75;
        out.put(LIGHT, l);
    }
}

/// A polygon cut to where `inside` is not negative.
fn clip(pts: &[(f64, f64)], inside: impl Fn((f64, f64)) -> f64) -> Vec<(f64, f64)> {
    let mut out = Vec::new();
    for i in 0..pts.len() {
        let (p, q) = (pts[i], pts[(i + 1) % pts.len()]);
        let (fp, fq) = (inside(p), inside(q));
        if fp >= 0.0 {
            out.push(p);
        }
        if (fp >= 0.0) != (fq >= 0.0) {
            let t = fp / (fp - fq);
            out.push((p.0 + (q.0 - p.0) * t, p.1 + (q.1 - p.1) * t));
        }
    }
    out
}

fn wall(out: &mut Out, e: &El, d: &Diagram, opt: &Options) {
    use super::walls as wl;
    let pts = wl::run(e);
    if pts.len() < 2 {
        return;
    }
    // **A plot's walls are a thin line** (his ask, 2026-10-03: *"the
    // simplicity of the walls"*): the wall's middle, in the plan's quiet
    // grey; its lengths only when it is picked or he asks for them all.

    let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("plan") };
    let segs = if wl::closed(e) { poly(&pts[..pts.len() - 1], true) } else { poly(&pts, false) };
    if wl::closed(e) {
        if let Some(wash) = fill_wash(e, segs.clone(), &own(e, "wall")) {
            out.put(FLOOR, wash);
        }
    }
    out.put(WALLS, stroked(&e.id, "body", segs.clone(), ink, 1.8, ""));
    // Something to pick it by, as wide as the wall is.
    out.put(WALLS, stroked(&e.id, "body", segs, plot::clear(), 6.0, ""));
    if d.settings.dims && (d.settings.all_lengths || (!opt.paper && opt.sel.contains(&e.id))) {
        wall_lengths(out, e, d);
    }
    // **A wall he named** (his ask, 2026-10-03: any object takes a label of
    // his own): a room's in the middle of it, any other wall's at the
    // middle of its run.
    if d.settings.labels && has_words(e) {
        let closed = wl::closed(e);
        let run: &[(f64, f64)] = if closed { &pts[..pts.len() - 1] } else { &pts };
        let at = if closed {
            let n = run.len() as f64;
            (run.iter().map(|p| p.0).sum::<f64>() / n, run.iter().map(|p| p.1).sum::<f64>() / n)
        } else {
            let total: f64 = run.windows(2).map(|w| ((w[1].0 - w[0].0).powi(2) + (w[1].1 - w[0].1).powi(2)).sqrt()).sum();
            let mut left = total / 2.0;
            let mut mid = run[0];
            for w in run.windows(2) {
                let seg = ((w[1].0 - w[0].0).powi(2) + (w[1].1 - w[0].1).powi(2)).sqrt();
                if seg >= left && seg > 0.0 {
                    let t = left / seg;
                    mid = (w[0].0 + (w[1].0 - w[0].0) * t, w[0].1 + (w[1].1 - w[0].1) * t);
                    break;
                }
                left -= seg;
                mid = w[1];
            }
            mid
        };
        ask_name(out, e, e.label.trim(), (at.0, at.1, 0.0), (0.1, 0.1), closed);
    }
}

/// Each stretch's length beside it: a closed room's along its inside face,
/// inside the room, saying so; any other wall's along its centre line.
fn wall_lengths(out: &mut Out, e: &El, d: &Diagram) {
    use super::walls as wl;
    let half = e.thick.max(0.02) / 2.0;
    let units = &d.settings.units;
    let dim = |out: &mut Out, a: (f64, f64), b: (f64, f64), text: String| {
        let heading = (b.1 - a.1).atan2(b.0 - a.0).to_degrees();
        out.put(LABELS, stroked("", "dim", line(a.0, a.1, b.0, b.1), Ink::Role("dim"), 0.6, ""));
        for p in [a, b] {
            let tick = Xf::new(p.0, p.1, heading + 90.0);
            out.put(LABELS, stroked("", "dim", poly(&[tick.p(-0.09, 0.0), tick.p(0.09, 0.0)], false), Ink::Role("dim"), 0.6, ""));
        }
        let m = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
        out.put(LABELS, fixed_text(&e.id, "dim", m.0, m.1, &text, MEASURE_PT, Ink::Role("dim"), "middle", readable(heading), true));
    };
    let c = wl::corners(e);
    if c.len() == 2 && e.curve.abs() > 1e-6 {
        // A bent wall: one length, along its bend.
        let pts = wl::run(e);
        if walk(&pts) < 0.4 {
            return;
        }
        let side = offset(&pts, -(half + 0.28));
        let (a, b) = (side[0], side[side.len() - 1]);
        let (m, heading) = along(&side, walk(&side) / 2.0);
        out.put(LABELS, stroked("", "dim", poly(&side, false), Ink::Role("dim"), 0.6, ""));
        for p in [a, b] {
            let tick = Xf::new(p.0, p.1, heading + 90.0);
            out.put(LABELS, stroked("", "dim", poly(&[tick.p(-0.09, 0.0), tick.p(0.09, 0.0)], false), Ink::Role("dim"), 0.6, ""));
        }
        out.put(LABELS, fixed_text(&e.id, "dim", m.0, m.1, &length_text(walk(&pts), units), MEASURE_PT, Ink::Role("dim"), "middle", readable(heading), true));
        return;
    }
    match wl::inside_side(e) {
        Some(s) => {
            for (i, (a, b)) in wl::stretch_faces(e, s).into_iter().enumerate() {
                let len = ((b.0 - a.0).powi(2) + (b.1 - a.1).powi(2)).sqrt();
                if len < 0.2 || wl::stretch_curved(e, i) {
                    continue;
                }
                let (nx, ny) = (-(b.1 - a.1) / len * s * 0.28, (b.0 - a.0) / len * s * 0.28);
                dim(out, (a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), format!("{} inside", length_text(len, units)));
            }
        }
        None => {
            for (i, (a, b)) in wl::stretches(e).into_iter().enumerate() {
                let len = ((b.0 - a.0).powi(2) + (b.1 - a.1).powi(2)).sqrt();
                if len < 0.2 || wl::stretch_curved(e, i) {
                    continue;
                }
                let k = -(half + 0.28) / len;
                let (nx, ny) = (-(b.1 - a.1) * k, (b.0 - a.0) * k);
                dim(out, (a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), length_text(len, units));
            }
        }
    }
}

fn opening(out: &mut Out, e: &El, opt: &Options) {
    let x = Xf::new(e.x, e.y, e.rot);
    let (w, t) = (e.w, e.h.max(0.05) + 0.02);

    // **A clean break in the wall** (doors redrawn, 2026-10-17: *"I don't
    // really know what it is when I look at it"*): the wall cut away, a
    // jamb across its whole thickness at each side, then what fills it — a
    // window two fine lines, an opening its header dashed, a door its
    // leaves or panels drawn the way a floor plan draws them.
    let ink = Ink::Role("plan");
    let face = t / 2.0 - 0.01;
    out.put(CUTS, filled(&e.id, "cut", x.path(&rect(-w / 2.0, -t / 2.0, w, t)), Ink::Role("paper"), Ink::None, 0.0));
    for sx in [-w / 2.0, w / 2.0] {
        out.put(CUTS, stroked(&e.id, "body", x.path(&line(sx, -face.max(0.06), sx, face.max(0.06))), ink.clone(), 1.2, ""));
    }
    match e.kind {
        Kind::Window => {
            for y in [-0.035, 0.035] {
                out.put(CUTS, stroked(&e.id, "body", x.path(&line(-w / 2.0, y, w / 2.0, y)), ink.clone(), 1.0, ""));
            }
        }
        Kind::Opening => {
            // The header over the gap, as plans dash what is overhead.
            for y in [-face, face] {
                let mut s = stroked(&e.id, "body", x.path(&line(-w / 2.0, y, w / 2.0, y)), ink.clone(), 0.6, "dash");
                s.alpha = 0.7;
                out.put(CUTS, s);
            }
        }
        Kind::Door => door(out, e, &x, w, t, opt),
        _ => {}
    }
}

/// **A door, by its kind** (`El::door_style`). `swing` is how far open: a
/// swinging leaf's angle (0 shut, 90 square, up to 180), a sliding
/// panel's share of its travel (0 shut, 90 and over all the way). `flip`
/// is which side of the wall it opens to or runs on; `hinge` which jamb a
/// single leaf hangs on, which way a sliding panel goes, or which side a
/// pocket is.
fn door(out: &mut Out, e: &El, x: &Xf, w: f64, t: f64, opt: &Options) {
    let ink = Ink::Role("plan");
    let side = if e.flip { -1.0 } else { 1.0 };
    let right = e.hinge == "right";
    let face = t / 2.0 - 0.01;
    let open = (e.swing / 90.0).clamp(0.0, 1.0);
    // A leaf or a panel: a thin slab, paper inside, so it reads as a door
    // up close and as a firm line far off.
    let slab = |out: &mut Out, pts: [(f64, f64); 4]| {
        out.put(CUTS, filled(&e.id, "body", x.path(&poly(&pts, true)), Ink::Role("paper"), ink.clone(), 1.4));
    };
    // A sliding panel is glass-tinted, so it stands apart from the wall
    // line it runs beside.
    let pane = |out: &mut Out, x0: f64, y: f64, len: f64, th: f64| {
        out.put(CUTS, filled(&e.id, "body", x.path(&rect(x0, y - th / 2.0, len, th)), Ink::Role("glass"), ink.clone(), 1.4));
        out.put(CUTS, stroked(&e.id, "body", x.path(&line(x0 + th * 0.6, y, x0 + len - th * 0.6, y)), ink.clone(), 0.5, ""));
    };
    // **Never thinner than the eye can take** (his Call Her Back plan at
    // 50%: a big sliding door was two hairlines): a leaf, a panel and an
    // arrow keep a few points on screen however far out the plan is shown,
    // and never more than the door itself.
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    let on = |points: f64| points / k;
    let lt = (t * 0.3).clamp(0.03, 0.045).max(on(2.5)).min(w * 0.12);
    let pt = (t * 0.36).clamp(0.04, 0.06).max(on(4.0)).min(w * 0.15);
    let gap = 0.1f64.max(on(7.0));
    // A sliding arrow: a fine shaft and an open head, out beside the wall
    // where it has room to read.
    let arrow = |out: &mut Out, from: f64, to: f64, y: f64| {
        if (to - from).abs() < 0.08 {
            return;
        }
        let dir = (to - from).signum();
        let size = ((to - from).abs() * 0.35).clamp(0.05, 0.1).max(on(7.0)).min((to - from).abs() * 0.6);
        out.put(CUTS, stroked(&e.id, "body", x.path(&line(from, y, to - dir * size * 0.6, y)), ink.clone(), 1.1, ""));
        out.put(CUTS, filled(&e.id, "body", x.path(&head((to, y), if dir > 0.0 { 0.0 } else { 180.0 }, size)), ink.clone(), ink.clone(), 0.4));
    };
    match e.door_style() {
        "swing" | "double" => {
            // **Leaves on hinges**: each leaf hangs at a jamb on the face it
            // opens to, drawn at its angle, with the thin arc its edge
            // sweeps back to shut. Shut, the leaf lies across the gap and
            // its arc is dashed, so the way it opens still shows.
            let leaves: Vec<(bool, f64)> = if e.door_style() == "double" { vec![(false, w / 2.0), (true, w / 2.0)] } else { vec![(right, w)] };
            for (r, len) in leaves {
                let hinge = (if r { w / 2.0 } else { -w / 2.0 }, side * face);
                let closed: f64 = if r { 180.0 } else { 0.0 };
                let shown = if e.swing < 0.5 { 0.0 } else { e.swing };
                let a = closed + if r { -shown * side } else { shown * side };
                let (c, sn) = (a.to_radians().cos(), a.to_radians().sin());
                // Thickness toward the wall when shut, toward the gap when open.
                let k = if r { -side } else { side };
                let n = (k * sn * lt, -k * c * lt);
                let tip = (hinge.0 + len * c, hinge.1 + len * sn);
                slab(out, [hinge, tip, (tip.0 + n.0, tip.1 + n.1), (hinge.0 + n.0, hinge.1 + n.1)]);
                let swept = if e.swing < 0.5 { 90.0 } else { e.swing };
                let to = closed + if r { -swept * side } else { swept * side };
                let mut s = stroked(&e.id, "body", x.path(&arc(hinge.0, hinge.1, len, closed, to, false)), ink.clone(), 0.7, if e.swing < 0.5 { "dash" } else { "" });
                s.alpha = if e.swing < 0.5 { 0.6 } else { 0.85 };
                out.put(CUTS, s);
            }
        }
        "sliding" => {
            // **Two panels on two tracks** in the wall's thickness, a little
            // longer than half so they overlap shut: one fixed at the end
            // it slides toward, the other riding past it as it opens. Each
            // panel has its glass line; the arrow says which way.
            let s = if right { 1.0 } else { -1.0 };
            let lane = pt * 0.62;
            let (ly, fy) = (side * lane, -side * lane);
            let p = w * 0.55;
            let fixed = if s > 0.0 { w / 2.0 - p } else { -w / 2.0 };
            let travel = open * (w - p);
            let start = -s * w / 2.0 + s * travel;
            let moving = if s > 0.0 { start } else { start - p };
            for (x0, y) in [(fixed, fy), (moving, ly)] {
                pane(out, x0, y, p, pt);
            }
            if w >= 0.5 {
                let ay = side * (lane + pt / 2.0 + gap);
                let mid = moving + p / 2.0;
                let len = (w * 0.3).min(0.45).max(on(24.0)).min(p * 0.9);
                arrow(out, mid - s * len / 2.0, mid + s * len / 2.0, ay);
            }
        }
        "center" => {
            // **Two panels parting from the centre** on one track along
            // the wall's face: shut they meet in the middle of the gap,
            // open each has slid out over the wall its own way. The track
            // runs as far as they go; two arrows point out from the middle.
            let y = side * (t / 2.0 - 0.01 + pt / 2.0);
            let track = stroked(&e.id, "body", x.path(&line(-w, y + side * pt * 0.75, w, y + side * pt * 0.75)), ink.clone(), 0.5, "dash");
            out.put(CUTS, Shape { alpha: 0.6, ..track });
            let p = w / 2.0;
            let shift = open * p;
            for x0 in [-p - shift, shift] {
                pane(out, x0, y, p, pt);
            }
            if w >= 0.6 {
                let ay = side * (t / 2.0 + pt * 1.5 + gap * 0.8);
                let len = (w * 0.22).min(0.4).max(on(20.0)).min(w * 0.45);
                arrow(out, -0.04, -0.04 - len, ay);
                arrow(out, 0.04, 0.04 + len, ay);
            }
        }
        style => {
            // **A pocket door**: the panel slides into the wall, whose
            // pocket is drawn as a hollow dashed slot beside the gap — one
            // side, or both for a pair.
            let pair = style == "pocketpair";
            let sides: Vec<f64> = if pair { vec![-1.0, 1.0] } else { vec![if right { 1.0 } else { -1.0 }] };
            let p = if pair { w / 2.0 } else { w };
            for s in sides {
                let (a, b) = (s * w / 2.0, s * (w / 2.0 + p));
                let (x0, x1) = (a.min(b), a.max(b));
                let pocket = filled(&e.id, "body", x.path(&rect(x0, -lt, x1 - x0, lt * 2.0)), Ink::Role("paper"), ink.clone(), 0.6);
                out.put(CUTS, Shape { dash: "dash", ..pocket });
                // Shut it spans its share of the gap; open it is in the wall.
                let shut0 = if s > 0.0 { w / 2.0 - p } else { -w / 2.0 };
                let x0 = shut0 + s * open * p;
                slab(out, [(x0, -lt / 2.0), (x0 + p, -lt / 2.0), (x0 + p, lt / 2.0), (x0, lt / 2.0)]);
                if w >= 0.5 {
                    let ay = side * (t / 2.0 + gap);
                    let len = (p * 0.5).min(0.4).max(on(20.0)).min(p * 0.9);
                    let from = if pair { s * 0.04 } else { -s * len / 2.0 };
                    arrow(out, from, from + s * len, ay);
                }
            }
        }
    }
}

fn set(out: &mut Out, e: &El, opt: &Options) {
    let (x, y, rot) = placed(e, opt);
    let xf = Xf::new(x, y, rot);
    let drawn = if symbols::is_half_round(e) { symbols::draw(&e.sym, e.w, e.h, e) } else { plot::object(&e.sym, e.w, e.h) };
    for mut s in drawn {
        // **The set, unfilled** (Back to Paper, 2026-10-04): a half round
        // keeps its skirted edge but drawn as the rest of the furniture is,
        // in the set's ink on the paper, not a tinted cloth.
        if s.fill == Ink::Role("muslin") {
            s.fill = Ink::Role("paper");
        }
        if s.stroke == Ink::Role("setline") {
            s.stroke = Ink::Role("prop");
            s.line = s.line.max(1.2);
        }
        xf.shape(&mut s);
        s.el = e.id.clone();
        s.part = "body";
        out.put(SET, s);
    }
    // A building and an area wear their name inside them, as the plots do:
    // "709", "BANK", "STREET LIGHTS OFF" — in the set's quiet grey, plain:
    // they belong to the set, not to what we bring (Ref 1511).
    if e.sym == "building" || e.sym == "area" {
        if out.labels && has_words(e) && !e.label_hidden {
            out.put(LABELS, label_text(e, x + e.label_dx, y + e.label_dy, e.label.trim(), NAME_PT, Ink::Role("ink2"), 0.0));
        }
        return;
    }
    // A half round once wore its diameter until he named it; since
    // 2026-10-17 every piece wears only what he typed (an older plan's
    // diameters were written on as labels, `plot::free_names`).
    ask_name(out, e, e.label.trim(), (x, y, rot), e.footprint(opt.beat), symbols::is_half_round(e) && e.w >= 0.6);
}

/// Where a thing stands now: at the beat, or part of the way to the next one.
/// The turn takes the short way round.
pub fn placed(e: &El, opt: &Options) -> (f64, f64, f64) {
    let a = e.at_beat(opt.beat);
    if opt.tween <= 0.0 || e.steps.is_empty() {
        return a;
    }
    let b = e.at_beat(opt.beat + 1);
    let t = opt.tween.clamp(0.0, 1.0);
    // Eased, the way a person or a dolly starts and stops.
    let t = t * t * (3.0 - 2.0 * t);
    let mut turn = (b.2 - a.2) % 360.0;
    if turn > 180.0 {
        turn -= 360.0;
    } else if turn < -180.0 {
        turn += 360.0;
    }
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, norm_deg(a.2 + turn * t))
}

/// The lens a camera is on, as words: its shot's Lens — the shot list is
/// the truth once there is one — else its own pick off the Lens list.
pub fn camera_lens_text<'a>(e: &'a El, ctx: &'a Context) -> &'a str {
    match ctx.shot(&e.shot).map(|(_, t)| t).filter(|t| !t.trim().is_empty()) {
        Some(t) => t,
        None => &e.lens_name,
    }
}

pub fn camera_focal(e: &El, ctx: &Context) -> f64 {
    camera_optics(e, ctx).focal
}

/// Everything a camera's cone is worked out from — **one place**, read by
/// the plan, the Mac's panels, the portal and the connector alike.
///
/// His design, 2026-10-01: the film defines its cameras (each with the
/// sensor he typed) and its lenses (the Lens list); a camera on the plan is
/// its shot, and reads both off it. A zoom (`24-70mm`) is set by the shot's
/// focal length; a prime says its own; a squeeze comes off the name (`2x`).
pub struct Optics {
    /// The drawing: one camera for all (his ruling — no list of bodies).
    pub body: &'static str,
    /// Which of the film's cameras, by id and name ("" when none).
    pub unit: String,
    pub unit_label: String,
    pub gate: lens::Gate,
    /// False when the camera has no sensor of its own and Super 35 (or an
    /// older plan's generic pick) stands in.
    pub sensor_set: bool,
    pub lens: String,
    /// A zoom's range, low end first.
    pub zoom: Option<(f64, f64)>,
    pub focal: f64,
    /// 1 for a spherical lens.
    pub squeeze: f64,
    /// The full horizontal angle, in degrees.
    pub aov: f64,
}

/// **How wide the frame is on the sensor**, in spherical millimetres — the
/// width the cone is worked out from. His question, 2026-10-01: does the angle
/// know the frame's shape? The film's ratio is fitted into the sensor as the
/// camera desqueezes it: a frame wider than the sensor's shape keeps the full
/// width and loses height (2.39 on Open Gate); a narrower one keeps the full
/// height and loses width — 9:16 from a sensor lying on its side is
/// height × 9/16, not the whole width. With no height or no ratio known, the
/// width as typed.
pub fn framed_width(w: f64, h: f64, squeeze: f64, ratio: f64) -> f64 {
    let wide = w * squeeze.max(1.0);
    if h > 0.0 && ratio > 0.0 {
        wide.min(h * ratio)
    } else {
        wide
    }
}

pub fn camera_optics(e: &El, ctx: &Context) -> Optics {
    let linked = ctx.shot(&e.shot).is_some();
    let unit = if linked { ctx.shot_unit(&e.shot).unwrap_or("") } else { e.unit.as_str() }.to_string();
    let cam = ctx.units.iter().find(|u| u.0 == unit);
    let unit_label = cam.map(|u| u.1.clone()).unwrap_or_default();
    let (gate, sensor_set) = match cam.and_then(|u| u.2.clone()) {
        Some(g) => (g, true),
        None => (lens::gate(&e.sensor), false),
    };
    let lens_text = camera_lens_text(e, ctx).to_string();
    let zoom = lens::zoom_from_text(&lens_text);
    let typed = (e.lens > 0.0).then_some(e.lens);
    let focal = match zoom {
        Some((lo, hi)) => {
            let set = if linked { ctx.shot_focal(&e.shot) } else { typed };
            set.unwrap_or(lo).clamp(lo, hi)
        }
        None => lens::focal_from_text(&lens_text).or(typed).unwrap_or(35.0),
    };
    let squeeze = lens::squeeze_from_text(&lens_text).unwrap_or(1.0);
    // The old generic "Anamorphic 2×" sensor has its squeeze in its width.
    let squeeze = if gate.id == "ana" { 1.0 } else { squeeze };
    let aov = lens::aov(focal, framed_width(gate.w, gate.h, squeeze, ctx.ratio), 1.0);
    Optics { body: symbols::DEFAULT_BODY, unit, unit_label, gate, sensor_set, lens: lens_text, zoom, focal, squeeze, aov }
}

/// What a camera is called on the plan: its shot's number, else its own label,
/// else nothing.
pub fn camera_name(e: &El, ctx: &Context) -> String {
    // What he typed wins (2026-10-17); else the shot's number.
    if !e.label.trim().is_empty() {
        return e.label.trim().to_string();
    }
    if let Some((number, _)) = ctx.shot(&e.shot) {
        if !number.is_empty() {
            return number.to_string();
        }
    }
    e.label.clone()
}

fn camera(out: &mut Out, e: &El, d: &Diagram, ctx: &Context, opt: &Options) {
    let optics = camera_optics(e, ctx);
    let focal = optics.focal;
    let (x, y, rot) = placed(e, opt);
    // **On a plot, a camera is a symbol** with its view to scale (his notes,
    // 2026-10-03): a small box, lens toward where it looks, a readable size
    // at any zoom; two thin dashed lines at the true angle for its lens.

    let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("camink") };
    let m = mark_m(opt) * 1.15;
    let xf = Xf::new(x, y, rot);
    if e.cone && d.settings.cones {
        let reach = if e.reach > 0.0 { e.reach } else { lens::default_reach(focal) };
        for mut s in plot::view(xf.p(m * 0.55, 0.0), rot, optics.aov, reach, ink.clone()) {
            s.el = e.id.clone();
            out.put(LIGHT, s);
        }
    }
    // Locked to a track: a dolly under it.
    if d.get(&e.rig_on).map(super::rigging::is_track).unwrap_or(false) {
        let mut dolly = Shape::new(&e.id, "body", Geom::Path(Xf::new(x, y, rot).path(&rrect(-m * 0.85, -m * 0.65, m * 1.7, m * 1.3, m * 0.18))));
        dolly.fill = Ink::Role("paper");
        dolly.stroke = ink.clone();
        dolly.line = 1.2;
        dolly.dash = "dash";
        out.put(STANDING, dolly);
    }
    for mut s in plot::camera(m, ink.clone()) {
        xf.shape(&mut s);
        s.el = e.id.clone();
        out.put(STANDING, s);
    }
    if d.settings.labels {
        let name = camera_name(e, ctx);
        ask_name_in(out, e, &name, (x, y, rot), (m, m), false, ink.clone(), lines_in(&name));
    }
    if e.frame_on {
        shot_frame(out, e, d, ctx, (x, y));
    }
    }

/// **A camera's frame, laid on the plan** — Scenario's frame image: the
/// linked shot's lead frame at plan scale where he put it, upright on the
/// page however north is turned, with a thin line back to the camera. Its
/// place is kept from the camera, so it goes where the camera goes. With no
/// picture on the shot, an empty box says so.
fn shot_frame(out: &mut Out, e: &El, d: &Diagram, ctx: &Context, at: (f64, f64)) {
    let picture = ctx.frame(&e.shot);
    let w = if e.frame_w > 0.0 { e.frame_w } else { 1.5 };
    let aspect = picture.map(|p| p.1).filter(|a| a.is_finite() && *a > 0.05 && *a < 20.0).unwrap_or(9.0 / 16.0);
    let h = w * aspect;
    let (fdx, fdy) = (e.frame_dx, e.frame_dy);
    let (ox, oy) = unturn(d, fdx, fdy);
    let (cx, cy) = (at.0 + ox, at.1 + oy);
    let upright = -view_turn(d);
    match picture {
        Some((media, _)) => {
            out.put(WORDS, Shape::new(&e.id, "shotframe", Geom::Image { media: media.to_string(), x: cx, y: cy, w, h, rot: upright }));
        }
        None => {
            out.put(LABELS, fixed_text(&e.id, "shotframe", cx, cy, "No Frame", 10.0, Ink::Role("ink2"), "middle", 0.0, false));
        }
    }
    let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("setline") };
    let page = |px: f64, py: f64| {
        let (a, b) = unturn(d, px, py);
        (cx + a, cy + b)
    };
    let (hw, hh) = (w / 2.0, h / 2.0);
    let box_pts = [page(-hw, -hh), page(hw, -hh), page(hw, hh), page(-hw, hh)];
    out.put(WORDS, stroked(&e.id, "shotframe", poly(&box_pts, true), ink.clone(), 1.2, if picture.is_some() { "" } else { "dash" }));
    // The line: from the camera's edge to the frame's, on the page.
    let len = fdx.hypot(fdy);
    let reach = e.w.max(e.h) / 2.0 + 0.05;
    if len > reach + 1e-6 {
        let (ux, uy) = (fdx / len, fdy / len);
        // Where the line from the frame's middle toward the camera leaves it.
        let t = [if ux.abs() > 1e-9 { hw / ux.abs() } else { f64::MAX }, if uy.abs() > 1e-9 { hh / uy.abs() } else { f64::MAX }]
            .into_iter()
            .fold(f64::MAX, f64::min);
        let edge = len - t;
        if edge > reach {
            let a = unturn(d, ux * reach, uy * reach);
            let b = unturn(d, ux * edge, uy * edge);
            out.put(WORDS, stroked(&e.id, "shotframe", line(at.0 + a.0, at.1 + a.1, at.0 + b.0, at.1 + b.1), ink, 0.8, ""));
        }
    }
}

/// **A name moved or hidden** by hand — Scenario's text label. Whatever a
/// kind draws as its name (`label`, or a camera's or a person's `tag`) is
/// stepped `label_dx`, `label_dy` on the page as shown, and left out when
/// hidden. Its size and weight are the plan's, never the piece's (Back to
/// Paper, 2026-10-04). Worked on the
/// shapes the element just drew, so every kind is served the same way.
fn name_styled(out: &mut Out, e: &El, d: &Diagram, opt: &Options, before: &[usize]) {
    let moved = e.label_dx.abs() > 1e-9 || e.label_dy.abs() > 1e-9;
    // **Words are ink, one size and one weight** (Back to Paper,
    // 2026-10-04): a name is moved or hidden by hand, never sized or
    // emboldened here — `label_size` and `label_bold` stay stored.
    if !moved && !e.label_hidden {
        return;
    }
    let (dx, dy) = unturn(d, e.label_dx, e.label_dy);
    // Where each moved name now stands, for the line back to its piece.
    let mut ties: Vec<((f64, f64), String, f64, f64)> = Vec::new();
    for (tier, from) in before.iter().enumerate() {
        let shapes = &mut out.tiers[tier];
        let mut i = *from;
        while i < shapes.len() {
            let s = &mut shapes[i];
            if s.el != e.id || !(s.part == "label" || s.part == "tag") {
                i += 1;
                continue;
            }
            if e.label_hidden {
                shapes.remove(i);
                continue;
            }
            match &mut s.geom {
                Geom::Text { x, y, size, fixed, text, .. } => {
                    *x += dx;
                    *y += dy;
                    if moved && *fixed && s.part == "label" {
                        ties.push(((*x, *y), text.clone(), *size, s.alpha));
                    }
                }
                Geom::Pill { x, y, size, .. } => {
                    *x += dx;
                    *y += dy;
                    if e.label_size > 0.0 {
                        *size = e.label_size * out.words;
                    }
                }
                _ => {}
            }
            i += 1;
        }
    }
    for (at, text, size, alpha) in ties {
        if let Some(mut s) = tie_back(e, opt, at, (dx, dy), &text, size) {
            s.alpha = alpha;
            // Under the pieces, as every line to a label is (2026-10-05).
            out.put(PATHS, s);
        }
    }
}

/// **A name pulled off its piece points back to it** (his ask, 2026-10-01:
/// *"all labels and names for any object should automatically have a line
/// pointing to the thing that they're about once I pull it away far
/// enough"*). The pieces `place_names` serves are tied there; this is the
/// rest — a shape's name in its middle, an arrow's, a cable's, a track's
/// or a road's along it. The line runs from the nearest point of the piece
/// to the edge of the name's paper, once the name stands further off the
/// piece than it did where it was first put by `TIE_AFTER` points.
fn tie_back(e: &El, opt: &Options, at: (f64, f64), step: (f64, f64), text: &str, size: f64) -> Option<Shape> {
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    let (tw, th) = words_box_pt(text, size);
    let (bw, bh) = ((tw + 2.0 * PATCH_PAD) / k, (th + PATCH_PAD) / k);
    // The nearest point of the piece to a spot, and how far the name's
    // paper there stands off the piece.
    let near = |c: (f64, f64)| -> Option<((f64, f64), f64)> {
        let b = Bx::at(c, bw, bh);
        let p = match e.kind {
            Kind::Shape | Kind::Set | Kind::Image => {
                let (w, h) = (e.w.max(0.0) / 2.0, e.h.max(0.0) / 2.0);
                let q = quad((e.x, e.y), e.rot, (w, h));
                if inside_quad(c, &q) {
                    return Some((c, 0.0));
                }
                let (vx, vy) = (c.0 - e.x, c.1 - e.y);
                let len = vx.hypot(vy).max(1e-9);
                let u = (vx / len, vy / len);
                let r = leaves_quad((w, h), e.rot, u);
                let edge = (e.x + u.0 * r, e.y + u.1 * r);
                return Some((edge, box_off(&b, edge)));
            }
            _ => {
                let pts = if e.kind.is_polyline() { e.points.clone() } else { line_points(e) };
                nearest_on(&pts, c)?
            }
        };
        Some((p, box_off(&b, p)))
    };
    let (from, off) = near(at)?;
    let (_, was) = near((at.0 - step.0, at.1 - step.1))?;
    if off <= was + TIE_AFTER / k {
        return None;
    }
    // To the edge of the paper, along the line from the piece.
    let (vx, vy) = (at.0 - from.0, at.1 - from.1);
    let len = vx.hypot(vy);
    if len < 1e-9 {
        return None;
    }
    let u = (vx / len, vy / len);
    let tx = if u.0.abs() > 1e-9 { bw / 2.0 / u.0.abs() } else { f64::MAX };
    let ty = if u.1.abs() > 1e-9 { bh / 2.0 / u.1.abs() } else { f64::MAX };
    let to = len - tx.min(ty);
    if to <= 1e-9 {
        return None;
    }
    // To the middle of the name's side that faces the piece (2026-10-17).
    let b = label_side(at, (bw / 2.0, bh / 2.0), from);
    let mut segs = line(from.0, from.1, b.0, b.1);
    // A small dot where it meets the piece.
    let r = 1.5 / k;
    segs.extend(circle(from.0, from.1, r));
    let mut s = stroked(&e.id, "tie", segs, Ink::Role("ink2"), 0.7, "");
    s.fill = Ink::Role("ink2");
    Some(s)
}

/// The middle of the side of a label (middle `at`, half size `half`) that
/// faces `p` — where every line out of a label leaves it (2026-10-17).
fn label_side(at: (f64, f64), half: (f64, f64), p: (f64, f64)) -> (f64, f64) {
    let (dx, dy) = (p.0 - at.0, p.1 - at.1);
    if dy.abs() * half.0 >= dx.abs() * half.1 {
        (at.0, at.1 + dy.signum() * half.1)
    } else {
        (at.0 + dx.signum() * half.0, at.1)
    }
}

/// How far a point stands off a box; nought inside it.
fn box_off(b: &Bx, p: (f64, f64)) -> f64 {
    (b.x1 - p.0).max(p.0 - b.x2).max(0.0).hypot((b.y1 - p.1).max(p.1 - b.y2).max(0.0))
}

/// The point of a line nearest a spot.
fn nearest_on(pts: &[(f64, f64)], c: (f64, f64)) -> Option<(f64, f64)> {
    if pts.len() == 1 {
        return Some(pts[0]);
    }
    let mut best: Option<((f64, f64), f64)> = None;
    for w in pts.windows(2) {
        let (a, b) = (w[0], w[1]);
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let l2 = dx * dx + dy * dy;
        let t = if l2 < 1e-12 { 0.0 } else { (((c.0 - a.0) * dx + (c.1 - a.1) * dy) / l2).clamp(0.0, 1.0) };
        let p = (a.0 + dx * t, a.1 + dy * t);
        let dist = (p.0 - c.0).hypot(p.1 - c.1);
        if best.map_or(true, |(_, bd)| dist < bd) {
            best = Some((p, dist));
        }
    }
    best.map(|(p, _)| p)
}

// ---------------------------------------------------------------- names

/// **Where a piece's name lands** (his ask of 2026-09-30, *"where labels
/// land when they are added in"*). Every piece — lamp, grip, set piece,
/// camera, person — is named the same way: plain ink, one size, centred a
/// small fixed gap under its outline as it stands, level however it turns,
/// on a patch of paper so a wall, the grid or a beam's edge breaks round it.
/// A new name never lands on another name or on a piece: it tries under,
/// then right, left and over, then steps further out (`place_names`). One
/// he has dragged stays where he put it, tied back to its piece by a thin
/// line once it is away from it.
struct Name {
    el: String,
    text: String,
    size: f64,
    bold: bool,
    /// Plain ink, always: a camera's colour is on its body.
    ink: Ink,
    /// The piece's middle and its outline, as it stands at this beat.
    centre: (f64, f64),
    rot: f64,
    half: (f64, f64),
    /// His own step off the spot under the piece, on the page.
    moved: Option<(f64, f64)>,
    /// A frame lying down wears its name in its middle.
    inside: bool,
    /// The lines of its Name, in its ink; the rest in grey.
    lead: usize,
}

/// Points to the metre when the shell has not said: the Mac's opening zoom.
pub const NOMINAL_SCALE: f64 = 60.0;
/// **One size for every name and callout on the plan**, in points (Back to
/// Paper, 2026-10-04): a lamp's callout, a shared label, grip, set pieces,
/// buildings, roads, cameras.
pub const NAME_PT: f64 = 10.0;
/// The quiet words that measure: a Ruler's lengths, a track's, a wall's.
pub const MEASURE_PT: f64 = 9.0;
/// The paper round a name's words, in points: across, and over and under
/// together.
pub const PATCH_PAD: f64 = 2.0;
/// From a piece's outline to its name's paper, in points.
const NAME_GAP: f64 = 2.5;
/// How far a name must stand off its piece before a line ties it back.
const TIE_AFTER: f64 = 6.0;

/// The box words take, in points — across and down — as the shells set
/// them: semibold system type, a line and a fifth to the line. Measured
/// here so the plan keeps names apart at the size they are drawn, and the
/// paper's patch matches the screen's.
pub fn words_box_pt(text: &str, size: f64) -> (f64, f64) {
    let lines: Vec<&str> = text.split('\n').collect();
    let wide = lines
        .iter()
        .map(|l| {
            l.chars()
                .map(|c| match c {
                    ' ' => 0.27,
                    'i' | 'l' | 'j' | '|' | '.' | ',' | ':' | ';' | '\'' | '!' | '·' => 0.28,
                    'f' | 't' | 'r' | 'I' => 0.38,
                    'm' | 'w' => 0.86,
                    'M' | 'W' => 0.9,
                    c if c.is_ascii_digit() => 0.62,
                    c if c.is_uppercase() => 0.7,
                    _ => 0.58,
                })
                .sum::<f64>()
        })
        .fold(0.0, f64::max);
    (wide * size, lines.len() as f64 * size * 1.2)
}

/// Words as the plan draws them: in capitals with Plan Settings › All Caps
/// on, else as typed (his ask, 2026-10-17).
pub fn cased(caps: bool, text: &str) -> String {
    if caps { text.to_uppercase() } else { text.to_string() }
}

/// A piece's name, asked for where it is drawn and placed once every piece
/// is down. Nothing when it has none or it is hidden.
fn ask_name(out: &mut Out, e: &El, text: &str, at: (f64, f64, f64), size: (f64, f64), inside: bool) {
    ask_name_in(out, e, text, at, size, inside, Ink::Role("ink"), lines_in(text));
}

/// A piece's name in its mark's ink: **the Name line takes its mark's
/// colour, the Note under it stays grey** (his call, 2026-10-05: *"are we
/// sure text color shouldnt match icon color? helps separate things"*).
fn ask_name_in(out: &mut Out, e: &El, text: &str, at: (f64, f64, f64), size: (f64, f64), inside: bool, ink: Ink, lead: usize) {
    // Every piece's Note under its name (2026-10-05); a lamp's and a
    // frame's are in `text` already.
    let noted;
    let text = if plot::is_lamp(e) || frame::is_frame(e) {
        text
    } else {
        noted = with_note(e, text);
        noted.as_str()
    };
    let typed = !out.typing.is_empty() && out.typing == e.id;
    if text.trim().is_empty() || (!typed && (!out.labels || e.label_hidden)) {
        return;
    }
    // A piece that shares a label is named there, not here.
    if out.tied.contains(&e.id) {
        return;
    }
    let moved = (e.label_dx.abs() > 1e-9 || e.label_dy.abs() > 1e-9).then_some((e.label_dx, e.label_dy));
    // **Words are ink** (Back to Paper, his call 2026-10-04): every name
    // one size, regular weight; a lamp's, a frame's and a camera's first
    // line in its mark's ink (2026-10-05), the rest dark. A stored
    // `label_size` and `label_bold` stay in the film untouched and are not
    // drawn.
    out.names.push(Name {
        el: e.id.clone(),
        text: text.to_string(),
        size: NAME_PT,
        bold: false,
        ink,
        centre: (at.0, at.1),
        rot: at.2,
        half: (size.0.max(0.0) / 2.0, size.1.max(0.0) / 2.0),
        moved,
        inside,
        lead,
    });
}

/// How many lines words take; none for none.
fn lines_in(text: &str) -> usize {
    if text.is_empty() { 0 } else { text.split('\n').count() }
}

/// A box on the page, metres.
#[derive(Clone, Copy, Debug)]
struct Bx {
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
}

impl Bx {
    fn at(c: (f64, f64), w: f64, h: f64) -> Bx {
        Bx { x1: c.0 - w / 2.0, y1: c.1 - h / 2.0, x2: c.0 + w / 2.0, y2: c.1 + h / 2.0 }
    }
    /// How much two boxes share, as an area.
    fn shared(&self, o: &Bx) -> f64 {
        let w = self.x2.min(o.x2) - self.x1.max(o.x1);
        let h = self.y2.min(o.y2) - self.y1.max(o.y1);
        if w > 0.0 && h > 0.0 { w * h } else { 0.0 }
    }
}

/// A turned rectangle's corners.
fn quad(c: (f64, f64), rot: f64, half: (f64, f64)) -> [(f64, f64); 4] {
    let x = Xf::new(c.0, c.1, rot);
    [x.p(-half.0, -half.1), x.p(half.0, -half.1), x.p(half.0, half.1), x.p(-half.0, half.1)]
}

fn quad_box(q: &[(f64, f64); 4]) -> Bx {
    let mut b = Bx { x1: f64::MAX, y1: f64::MAX, x2: f64::MIN, y2: f64::MIN };
    for (x, y) in q {
        b.x1 = b.x1.min(*x);
        b.y1 = b.y1.min(*y);
        b.x2 = b.x2.max(*x);
        b.y2 = b.y2.max(*y);
    }
    b
}

/// Whether a box and a turned rectangle overlap — no line between them on
/// any of their four sides' directions.
fn hits(b: &Bx, q: &[(f64, f64); 4]) -> bool {
    let bc = [(b.x1, b.y1), (b.x2, b.y1), (b.x2, b.y2), (b.x1, b.y2)];
    let axes = [(1.0, 0.0), (0.0, 1.0), (q[1].0 - q[0].0, q[1].1 - q[0].1), (q[3].0 - q[0].0, q[3].1 - q[0].1)];
    axes.iter().all(|(ax, ay)| {
        let span = |pts: &[(f64, f64)]| {
            pts.iter().map(|(x, y)| x * ax + y * ay).fold((f64::MAX, f64::MIN), |(lo, hi), v| (lo.min(v), hi.max(v)))
        };
        let (a0, a1) = span(&bc);
        let (b0, b1) = span(q);
        a1 > b0 + 1e-9 && b1 > a0 + 1e-9
    })
}

fn inside_quad(p: (f64, f64), q: &[(f64, f64); 4]) -> bool {
    let side = |i: usize| {
        let (a, b) = (q[i], q[(i + 1) % 4]);
        (b.0 - a.0) * (p.1 - a.1) - (b.1 - a.1) * (p.0 - a.0)
    };
    (0..4).all(|i| side(i) >= -1e-9) || (0..4).all(|i| side(i) <= 1e-9)
}

/// The pieces a name keeps off, each with its outline as it stands now.
fn name_obstacles(d: &Diagram, opt: &Options) -> Vec<(String, [(f64, f64); 4])> {
    let mut v = Vec::new();
    for e in d.els.iter().filter(|e| !e.hidden) {
        match e.kind {
            Kind::Light | Kind::Set | Kind::Camera | Kind::Cast | Kind::Note | Kind::Shape => {
                let (x, y, rot) = placed(e, opt);
                let (mut w, mut h) = e.footprint(opt.beat);
                // A lamp's mark and a camera are drawn at their page size,
                // larger than a small fixture's own (fix round 2: a name
                // kept clear of the fixture still sat on its mark).
                if (e.kind == Kind::Light && e.sym != "frame") || e.kind == Kind::Camera {
                    let m = mark_m(opt);
                    w = w.max(m);
                    h = h.max(m);
                }
                v.push((e.id.clone(), quad((x, y), rot, (w / 2.0, h / 2.0))));
            }
            Kind::Wall => {
                // Every stretch of a wall-line (`walls.rs`), each its own box.
                for w in super::walls::run(e).windows(2) {
                    let (dx, dy) = (w[1].0 - w[0].0, w[1].1 - w[0].1);
                    let len = dx.hypot(dy);
                    if len > 1e-6 {
                        let rot = dy.atan2(dx).to_degrees();
                        let c = ((w[0].0 + w[1].0) / 2.0, (w[0].1 + w[1].1) / 2.0);
                        v.push((e.id.clone(), quad(c, rot, (len / 2.0, e.thick.max(0.05) / 2.0))));
                    }
                }
            }
            _ => {}
        }
    }
    v
}

/// How far a ray from a turned rectangle's middle runs along `u` before it
/// leaves it.
fn leaves_quad(half: (f64, f64), rot: f64, u: (f64, f64)) -> f64 {
    let r = (-rot).to_radians();
    let (lx, ly) = (u.0 * r.cos() - u.1 * r.sin(), u.0 * r.sin() + u.1 * r.cos());
    let tx = if lx.abs() > 1e-9 { half.0 / lx.abs() } else { f64::MAX };
    let ty = if ly.abs() > 1e-9 { half.1 / ly.abs() } else { f64::MAX };
    tx.min(ty)
}

/// Every piece's name, put where it reads: see `Name`.
fn place_names(out: &mut Out, d: &Diagram, opt: &Options) {
    let names = std::mem::take(&mut out.names);
    if names.is_empty() {
        return;
    }
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    let pieces = name_obstacles(d, opt);
    // **Words go where he puts them** (his note, 2026-10-05: *"let me put
    // text where i want it to - i dont need collision barriers"*). A name
    // he moved is drawn exactly there, over whatever is under it; nothing
    // steps it aside, and nothing else steps aside for it. Only a name he
    // never placed is given a spot: under its piece, else beside it, clear
    // of the other names the plan placed and of other pieces. Lengths, his
    // Words and the names he placed are no obstacle to it.
    let mut taken: Vec<Bx> = Vec::new();
    let gap = NAME_GAP / k;
    let mut done: Vec<(usize, (f64, f64), (f64, f64), (f64, f64))> = Vec::new();
    // Measured at the size they will be put down (`Out::put`).
    let wf = out.words;
    for (i, n) in names.iter().enumerate() {
        let (tw, th) = words_box_pt(&cased(out.caps, &n.text), n.size * wf);
        let (bw, bh) = ((tw + 2.0 * PATCH_PAD) / k, (th + PATCH_PAD) / k);
        let ob = quad_box(&quad(n.centre, n.rot, n.half));
        let under = (n.centre.0, ob.y2 + gap + bh / 2.0);
        if n.inside {
            done.push((i, n.centre, (bw, bh), (0.0, 0.0)));
            continue;
        }
        if let Some((dx, dy)) = n.moved {
            let (dx, dy) = unturn(d, dx, dy);
            done.push((i, (under.0 + dx, under.1 + dy), (bw, bh), (0.0, 0.0)));
            continue;
        }
        let right = (ob.x2 + gap + bw / 2.0, n.centre.1);
        let left = (ob.x1 - gap - bw / 2.0, n.centre.1);
        let over = (n.centre.0, ob.y1 - gap - bh / 2.0);
        let mut tries = vec![under, right, left, over];
        let step = bh + gap;
        for j in 1..=6 {
            let f = j as f64;
            tries.push((under.0, under.1 + f * step));
            tries.push((right.0, right.1 + f * step));
            tries.push((left.0, left.1 + f * step));
            tries.push((over.0, over.1 - f * step));
            tries.push((under.0 + f * bw * 0.5, under.1));
            tries.push((under.0 - f * bw * 0.5, under.1));
        }
        // What a spot costs: on a name, dearly; on a piece, a little. A
        // piece the name's own stands on or in — a rug, a car, the frame
        // over a lamp — is no obstacle.
        let cost = |c: (f64, f64)| {
            let b = Bx::at(c, bw, bh);
            let on_names: f64 = taken.iter().map(|t| t.shared(&b)).sum();
            let on_pieces: f64 = pieces
                .iter()
                .filter(|(id, q)| *id != n.el && !inside_quad(n.centre, q) && hits(&b, q))
                .map(|(_, q)| quad_box(q).shared(&b).max(1e-6))
                .sum();
            on_names * 10.0 + on_pieces
        };
        let mut best = (f64::MAX, under);
        for c in tries {
            let v = cost(c);
            if v <= 1e-12 {
                best = (0.0, c);
                break;
            }
            if v < best.0 - 1e-12 {
                best = (v, c);
            }
        }
        let at = best.1;
        taken.push(Bx::at(at, bw, bh));
        // How far the plan put it from under its piece: a drag starts from
        // where it is drawn.
        done.push((i, at, (bw, bh), (at.0 - under.0, at.1 - under.1)));
    }
    // A name away from its piece is tied back to it by a thin line, from
    // its outline to the name's paper.
    for (i, at, (bw, bh), _) in &done {
        let n = &names[*i];
        if n.inside {
            continue;
        }
        let (vx, vy) = (at.0 - n.centre.0, at.1 - n.centre.1);
        let len = vx.hypot(vy);
        if len < 1e-9 {
            continue;
        }
        let u = (vx / len, vy / len);
        let from = leaves_quad(n.half, n.rot, u);
        let tx = if u.0.abs() > 1e-9 { bw / 2.0 / u.0.abs() } else { f64::MAX };
        let ty = if u.1.abs() > 1e-9 { bh / 2.0 / u.1.abs() } else { f64::MAX };
        let to = len - tx.min(ty);
        // Away means clear of the piece's whole footprint, not of the
        // middle of a lamp turned on its corner.
        let ob = quad_box(&quad(n.centre, n.rot, n.half));
        let b = Bx::at(*at, *bw, *bh);
        let off = (b.x1 - ob.x2).max(ob.x1 - b.x2).max(0.0).hypot((b.y1 - ob.y2).max(ob.y1 - b.y2).max(0.0));
        if off > TIE_AFTER / k && to > from {
            // From the middle of the name's side that faces its piece, to
            // the piece's edge, a small dot there (2026-10-17: tidy lines).
            let side = label_side(*at, (*bw / 2.0, *bh / 2.0), n.centre);
            let (wx, wy) = (side.0 - n.centre.0, side.1 - n.centre.1);
            let wl = wx.hypot(wy);
            if wl > 1e-9 {
                let w = (wx / wl, wy / wl);
                let edge = leaves_quad(n.half, n.rot, w);
                if wl > edge {
                    let a = (n.centre.0 + w.0 * edge, n.centre.1 + w.1 * edge);
                    // Under the pieces, as every line to a label is (2026-10-05).
                    out.tiers[PATHS].push(stroked(&n.el, "tie", line(a.0, a.1, side.0, side.1), Ink::Role("ink2"), 0.7, ""));
                    out.tiers[PATHS].push(filled(&n.el, "tie", circle(a.0, a.1, 1.5 / k), Ink::Role("ink2"), Ink::None, 0.0));
                }
            }
        }
    }
    // **No plate behind a name** (Back to Paper): the words on the paper,
    // with a thin halo of paper so a line they cross breaks round them; a
    // second line in grey.
    for (i, at, _, shift) in done {
        let n = &names[i];
        let mut s = fixed_text(&n.el, "label", at.0, at.1, &n.text, n.size, n.ink.clone(), "middle", 0.0, true);
        if let Geom::Text { bold, shift: sh, under, lead, .. } = &mut s.geom {
            *bold = n.bold;
            *sh = shift;
            *under = Ink::Role("ink2");
            *lead = n.lead.max(1);
        }
        out.put(LABELS, s);
    }
}

/// A person with no colour of their own.
pub const PERSON_GREY: &str = "#5F656D";

fn cast(out: &mut Out, e: &El, ctx: &Context, opt: &Options) {
    // **In their colour** (his note, 2026-09-29: "characters should appear
    // their color, not just their tag"): the piece's own colour, else the
    // character's, as the Cast column's chip shows it. A person who is no
    // character, with no colour of their own, stays the pack's grey.
    let tint: Option<String> = if is_hex(&e.color) {
        Some(e.color.clone())
    } else if !e.cast.is_empty() {
        let who = ctx.cast_name(&e.cast).unwrap_or(&e.cast);
        ctx.character_colour(who).map(|h| if h.starts_with('#') { h.to_string() } else { format!("#{h}") })
    } else {
        None
    };
    // **No colour of their own: a firm grey**, not the pack's pale one —
    // people are what he looks for first on a plan (Scenario draws them
    // black), and they were faint at a normal zoom.
    let tint = tint.or_else(|| Some(PERSON_GREY.to_string()));
    let (x, y, rot) = placed(e, opt);
    let xf = Xf::new(x, y, rot);
    let ink = tint.as_deref().map(Ink::hex).unwrap_or(Ink::Role("ink"));
    // **Readable when the plan is far out** (2026-10-17): a person keeps
    // about fourteen points across the shoulders on screen, up to half as
    // big again as life.
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    let grow = (14.0 / (e.h.max(0.3) * k)).clamp(1.0, 1.5);
    for mut s in plot::person(e.w * grow, e.h * grow, ink) {
        xf.shape(&mut s);
        s.el = e.id.clone();
        out.put(STANDING, s);
    }
    let name = cast_label(e, ctx);
    ask_name(out, e, &name, (x, y, rot), e.footprint(opt.beat), false);
}

/// A person's name on the plan: what he typed on them (2026-10-17), else
/// the character they play.
pub fn cast_label(e: &El, ctx: &Context) -> String {
    let own = e.label.trim();
    if !own.is_empty() {
        return own.to_string();
    }
    ctx.cast_name(&e.cast).map(|s| s.to_string()).unwrap_or_default()
}

fn light(out: &mut Out, e: &El, d: &Diagram, opt: &Options, marks: &Marks) {
    let at = placed(e, opt);
    plot_light(out, e, d, opt, marks, at);
}

/// **A light on a plot** (Labs, 2026-10-03): a lamp as its legend's mark
/// at a readable size, named in the mark's ink with its count and what is
/// done to it; a frame as its true footprint; anything else that rides
/// with the lights — a stand, a flag that is not a frame — as a plain
/// outline.
fn plot_light(out: &mut Out, e: &El, d: &Diagram, opt: &Options, marks: &Marks, at: (f64, f64, f64)) {
    let (x, y, rot) = at;
    let m = mark_m(opt);
    if frame::is_frame(e) {
        // **Grip in its own ink** (his call, 2026-10-03), unless he gave
        // the frame a colour.
        let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("gripink") };
        let standing = e.tilt >= 85.0 || e.w < e.h * 0.06;
        let xf = Xf::new(x, y, rot);
        // **Quiet** (Back to Paper, 2026-10-04): a line or a double line,
        // its cloth faint across it (his note, 2026-10-05); its lean in
        // perspective and its cloth at full strength once picked.
        let full = !opt.paper && opt.sel.contains(&e.id);
        for mut s in plot::frame(e.w, e.h, standing, e.tilt, frame::material_id(e), ink.clone(), full, d.settings.fabric) {
            xf.shape(&mut s);
            s.el = e.id.clone();
            out.put(STANDING, s);
        }
        // **Name and Note, like a lamp's** (his note, 2026-10-05): "12×12"
        // over "BOUNCE FOR KEY · ULTRABOUNCE · 45°".
        let (mut name, under) = frame_lines(e, out.counts);
        let lead = lines_in(&name);
        if !under.is_empty() {
            if !name.is_empty() {
                name.push('\n');
            }
            name.push_str(&under);
        }
        if d.settings.labels || out.typing == e.id {
            ask_name_in(out, e, &name, (x, y, rot), (e.w, e.h), false, ink.clone(), lead);
        }
        return;
    }
    if !plot::is_lamp(e) {
        // Grip is what we bring: drawn in grip's ink (red, by the three
        // inks), or the colour he gave it.
        let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("gripink") };
        let xf = Xf::new(x, y, rot);
        for mut s in plot::object(&e.sym, e.w, e.h) {
            for i in [&mut s.fill, &mut s.stroke] {
                if matches!(i, Ink::Role("prop") | Ink::Role("plan")) {
                    *i = ink.clone();
                }
            }
            xf.shape(&mut s);
            s.el = e.id.clone();
            out.put(STANDING, s);
        }
        // Grip that is not a frame — a flag, an LCD, a stand — wears what
        // he typed on it, and nothing until he does (2026-10-17).
        let name = e.label.trim().to_string();
        if d.settings.labels && !name.is_empty() {
            ask_name_in(out, e, &name, (x, y, rot), (e.w, e.h), false, ink.clone(), lines_in(&name));
        }
        return;
    }
    let look = marks.looks.iter().find(|(id, _)| *id == e.id).map(|(_, l)| *l).unwrap_or(plot::Look {
        mark: plot::Mark::Chevron,
        ink: "added",
        solid: false,
    });
    let draw = plot::mark;
    // The location's own black is its own category, so its colour can be set.
    let ink = if is_hex(&e.color) {
        Ink::hex(&e.color)
    } else if look.ink == "ink" {
        Ink::Role("existing")
    } else {
        look.ink()
    };
    if let Some(spots) = string_spots(e) {
        // **A string of lamps**: the same mark at every spot, one name.
        let xf = Xf::new(x, y, rot);
        for (lx, ly) in &spots {
            let (px, py) = xf.p(*lx, *ly);
            let at = Xf::new(px, py, rot);
            let mut shapes = draw(look, m, 0.0, ink.clone());
            if (e.existing || e.practical) && e.action == "off" {
                shapes.extend(plot::crossed(m, ink.clone()));
            }
            for mut sh in shapes {
                at.shape(&mut sh);
                sh.el = e.id.clone();
                out.put(STANDING, sh);
            }
        }
        // Picked anywhere along it, or anywhere in its ring.
        let hit = if e.spread == "ring" { ellipse(0.0, 0.0, e.w / 2.0 + m * 0.5, e.h / 2.0 + m * 0.5) } else { rect(-e.w / 2.0 - m * 0.5, -e.h / 2.0 - m * 0.5, e.w + m, e.h + m) };
        let mut sh = Shape::new(&e.id, "body", Geom::Path(hit));
        sh.fill = plot::clear();
        xf.shape(&mut sh);
        out.put(STANDING, sh);
    } else if look.mark == plot::Mark::Mat {
        // **A soft panel from above**: its own size, turned with the lamp,
        // the same hung or across.
        let xf = Xf::new(x, y, rot);
        let (mw, mh) = plot::mat_size(e, m);
        let mut shapes = plot::mat(mw, mh, look.solid, ink.clone());
        if (e.existing || e.practical) && e.action == "off" {
            shapes.extend(plot::crossed(m, ink.clone()));
        }
        for mut s in shapes {
            xf.shape(&mut s);
            s.el = e.id.clone();
            out.put(STANDING, s);
        }
    } else if plot::points_down(e) && !matches!(look.mark, plot::Mark::Ring | plot::Mark::Dot) {
        // **Hung pointing straight down** (his ask, 2026-10-05): its true
        // size from above, crossed, no front edge — a ball or a practical
        // faces no way already and keeps its mark.
        let lettered = matches!(look.mark, plot::Mark::Letter(_));
        let xf = Xf::new(x, y, rot);
        let mut shapes = plot::down(e.w.max(m * 0.8), e.h.max(m * 0.8), look.solid, !lettered, ink.clone());
        if (e.existing || e.practical) && e.action == "off" {
            shapes.extend(plot::crossed(m, ink.clone()));
        }
        for mut s in shapes {
            xf.shape(&mut s);
            s.el = e.id.clone();
            out.put(STANDING, s);
        }
        if let plot::Mark::Letter(c) = look.mark {
            let mut t = fixed_text(&e.id, "body", x, y + m * 0.02, &c.to_string(), plot::MARK_PT * 0.55 * lettering(opt).marks, ink.clone(), "middle", 0.0, false);
            if let Geom::Text { bold, .. } = &mut t.geom {
                *bold = true;
            }
            out.tiers[STANDING].push(t);
        }
    } else {
        // A bar lies across the way the lamp faces, as long as the unit; a
        // unit drawn long the other way turns it.
        let (long, turn) = if e.h >= e.w { (e.h, 0.0) } else { (e.w, 90.0) };
        let bar = matches!(look.mark, plot::Mark::Bar | plot::Mark::DoubleBar);
        // **A tube to scale** (his ask, 2026-10-03: tube lights' length matters on
        // a top-down plan): a bare bar mark is as long as the lamp is, once that
        // is more than a mark — a default lamp (0.3 m) stays a mark.
        let unit_long = if e.sym.is_empty() && long <= 0.4 { 0.0 } else { long };
        // **Sized up, drawn bigger** (his note, 2026-10-17): the mark at its
        // page size times how far he has sized the lamp (`lampscale`).
        let m = m * lampscale::mark_scale(e);
        let xf = Xf::new(x, y, if bar { rot + turn } else { rot });
        let mut shapes = draw(look, m, if bar { unit_long } else { 0.0 }, ink.clone());
        // Something to pick it by, the size of its mark.
        shapes.push({
            // A tube is picked along its whole length.
            let hit = if bar && unit_long > m { rect(-m * 0.55, -unit_long / 2.0, m * 1.1, unit_long) } else { circle(0.0, 0.0, m * 0.55) };
            let mut s = Shape::new("", "body", Geom::Path(hit));
            s.fill = plot::clear();
            s
        });
        if (e.existing || e.practical) && e.action == "off" {
            shapes.extend(plot::crossed(m, ink.clone()));
        }
        for mut s in shapes {
            xf.shape(&mut s);
            s.el = e.id.clone();
            out.put(STANDING, s);
        }
        if let plot::Mark::Letter(c) = look.mark {
            // Part of the mark: its size goes with the mark's, not the words'.
            let k = m / mark_m(opt);
            let mut t = fixed_text(&e.id, "body", x, y + m * 0.02, &c.to_string(), plot::MARK_PT * 0.55 * lettering(opt).marks * k, ink.clone(), "middle", 0.0, false);
            if let Geom::Text { bold, .. } = &mut t.geom {
                *bold = true;
            }
            out.tiers[STANDING].push(t);
        }
    }
    // Its name: what he typed on it, else what its mark stands for —
    // counted, gelled, and what is done to it. "3× 2K Blonde" over "½ CTO ·
    // Dim". A mark that stands for nothing yet is drawn bare.
    // **A lamp's name is its symbol's** (his call, 2026-10-04: one control
    // per job), so the plan and the legend never disagree. What he wrote on
    // the lamp itself is a note under it: "Uplight Trees".
    // Its own Name (2026-10-05), not its symbol's.
    let named = plot::lamp_name(e);
    let (mut name, under) = lamp_lines(e, &named, out.counts);
    let lead = lines_in(&name);
    if !under.is_empty() {
        if !name.is_empty() {
            name.push('\n');
        }
        name.push_str(&under);
    }
    // A lamp that shares a label is named there, not here.
    let tied = !e.tie_to.is_empty() && d.get(&e.tie_to).map(|t| t.kind == Kind::Text).unwrap_or(false);
    if (d.settings.labels || out.typing == e.id) && !name.is_empty() && !tied {
        let size = if look.mark == plot::Mark::Mat {
            // Clear of its heavy edge.
            let (mw, mh) = plot::mat_size(e, m);
            (mw + m * 0.12, mh + m * 0.12)
        } else if plot::points_down(e) {
            // Named clear of its box, not over it.
            (e.w.max(m * 0.8), e.h.max(m * 0.8))
        } else if e.spread.is_empty() {
            let k = lampscale::mark_scale(e);
            (m * k, m * k)
        } else {
            (e.w.max(m) + m, e.h.max(m) + m)
        };
        // A practical's words in a deeper amber than its mark, so they read.
        let words = match &ink {
            Ink::Role("practical") => Ink::Role("practicalword"),
            i => i.clone(),
        };
        ask_name_in(out, e, &name, (x, y, rot), size, false, words, lead);
    }
}

/// **A lamp's two lines** (Back to Paper, Batch 2: Name and Note): the
/// first, its count and its symbol's Name — "4× 4' TITAN TUBE" — and the
/// one under it, its Note, gels and Off joined by a middle dot — "UPLIGHT
/// ON BG · ½ CTO". As typed; the plan puts them in capitals. `name` is
/// what its symbol is named on this sheet.
pub fn lamp_lines(e: &El, name: &str, counts: bool) -> (String, String) {
    let note = e.label.trim();
    let note = if note.eq_ignore_ascii_case(name) { "" } else { note };
    // Its count only with Plan Settings › Counts on (2026-10-17).
    let first = if counts && e.count > 1 {
        if name.is_empty() { format!("{}×", e.count) } else { format!("{}× {}", e.count, name) }
    } else {
        name.to_string()
    };
    let mut under = hung(e);
    if !note.is_empty() {
        under.push(note.to_string());
    }
    under.extend(e.gels.iter().map(|g| gels::name(g)));
    if (e.existing || e.practical) && !plot_action(e).is_empty() {
        under.push(plot_action(e).to_string());
    }
    (first, under.join(" · "))
}

/// **A lamp pointing down says so first** (his ask, 2026-10-05): "TOP ·
/// 8'" — Top, and the height it hangs at when he gave one.
fn hung(e: &El) -> Vec<String> {
    if !plot::points_down(e) {
        return Vec::new();
    }
    let mut v = vec!["Top".to_string()];
    let h = e.height.trim();
    if !h.is_empty() {
        v.push(h.to_string());
    }
    v
}

/// **A frame's two lines** (his notes, 2026-10-05: *"a frames size adn
/// then fabric/material name goes in first line / then the note is the line
/// after"*): its size and cloth — "12×12 ULTRA BOUNCE", counted when there
/// are more, its lean after a middle dot — over its Note, the `label`. A
/// `title` typed on 10-05 under the brief Name rule is kept, not drawn.
/// **Since 2026-10-17 the first line is his** (*"I still can't manually
/// just label a silk"*): the frame's Name as typed (`lamp_name`), nothing
/// when he has typed none — never a size or cloth written for him. An
/// older plan's size-and-cloth line was written on as that Name
/// (`frame_spec`, `plot::free_names`).
pub fn frame_lines(e: &El, counts: bool) -> (String, String) {
    let mut first = e.lamp_name.trim().to_string();
    if counts && e.count > 1 {
        first = if first.is_empty() { format!("{}×", e.count) } else { format!("{}× {}", e.count, first) };
    }
    (first, e.label.trim().to_string())
}

/// What a frame wrote for itself before 2026-10-17: its size and cloth and
/// its lean — "12×12 Ultra Bounce · 45°" — or nothing when none was set.
pub fn frame_spec(e: &El) -> String {
    let mut first = frame_name(e);
    if first == "Frame" {
        first.clear();
    }
    let standing = e.tilt >= 85.0 || e.w < e.h * 0.06;
    if !first.is_empty() && !standing && e.tilt > 1.0 {
        first.push_str(&format!(" · {}°", e.tilt.round() as i64));
    }
    first
}

/// A frame's size and cloth, uncounted: "12×12 Ultra Bounce".
fn frame_name(e: &El) -> String {
    let skin = match frame::material_id(e) {
        "none" if e.grid > 0.0 => "Egg Crate",
        "none" | "undecided" => "",
        id => frame::material_name(id),
    };
    let size = frame::size_name(e);
    let first = [size.as_str(), skin].iter().filter(|w| !w.is_empty()).copied().collect::<Vec<_>>().join(" ");
    if first.is_empty() { "Frame".into() } else { first }
}

/// **Where a string's lamps stand**, about its middle, facing east: `count`
/// of them evenly along its long side, bowed `curve` metres toward the way
/// it faces (a drive's curve); or round the oval of its size. None for one
/// lamp at one spot.
pub fn string_spots(e: &El) -> Option<Vec<(f64, f64)>> {
    let n = e.count.max(1) as usize;
    match e.spread.as_str() {
        "ring" => Some(
            (0..n)
                .map(|i| {
                    let a = std::f64::consts::TAU * i as f64 / n as f64 - std::f64::consts::FRAC_PI_2;
                    (e.w / 2.0 * a.cos(), e.h / 2.0 * a.sin())
                })
                .collect(),
        ),
        "line" => {
            let along_y = e.h >= e.w;
            let l = e.w.max(e.h);
            Some(
                (0..n)
                    .map(|i| {
                        let t = if n == 1 { 0.0 } else { -l / 2.0 + l * i as f64 / (n - 1) as f64 };
                        let k = if l > 1e-9 { 2.0 * t / l } else { 0.0 };
                        let bow = e.curve * (1.0 - k * k);
                        if along_y { (bow, t) } else { (t, bow) }
                    })
                    .collect(),
            )
        }
        _ => None,
    }
}

/// **How big a piece is drawn**, where that is more than its footprint
/// (Ref 1511): metres, across and down in its own turn, at `opt`'s zoom and
/// lettering — a lamp by its mark, a camera by its body, Words and a shared
/// label by their words. So a click takes, and a pick outlines, what is on
/// the paper. None: drawn as its footprint.
pub fn drawn_size(e: &El, d: &Diagram, opt: &Options) -> Option<(f64, f64)> {
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    let m = mark_m(opt);
    match e.kind {
        Kind::Light if plot::is_lamp(e) => {
            if string_spots(e).is_some() {
                Some((e.w + m, e.h + m))
            } else if plot::chosen(e).map(|l| l.mark) == Some(plot::Mark::Mat) {
                Some(plot::mat_size(e, m))
            } else if lampscale::hugs(e) {
                // Round the mark alone, sized as he sized it.
                let m = m * lampscale::mark_scale(e);
                Some((m * 1.1, m * 1.1))
            } else {
                let m = m * lampscale::mark_scale(e);
                Some((e.w.max(m * 1.1), e.h.max(m * 1.1)))
            }
        }
        // The body and lens (`plot::camera`, at `camera`'s size); a dolly
        // under it when it rides a track.
        Kind::Camera => {
            let s = m * 1.15;
            let (w, h) = if d.get(&e.rig_on).map(super::rigging::is_track).unwrap_or(false) { (m * 1.7, m * 1.3) } else { (s * 1.1, s * 0.75) };
            Some((e.w.max(w), e.h.max(h)))
        }
        Kind::Text => {
            let (words, size) = match shared_label_words(d, e) {
                Some(w) => (w, NAME_PT),
                None => (e.text.clone(), words_drawn_pt(e.size)),
            };
            let (w, h) = words_box_pt(&cased(d.settings.caps, &words), size * lettering(opt).words);
            Some(((w + 2.0 * PATCH_PAD) / k, (h + PATCH_PAD) / k))
        }
        _ => None,
    }
}

/// Whether words are a label pieces share.
fn shared_label(d: &Diagram, t: &El) -> bool {
    !held(d, t).is_empty()
}

/// The pieces a label is shared by, shown ones only.
fn held<'a>(d: &'a Diagram, t: &El) -> Vec<&'a El> {
    d.els.iter().filter(|e| e.tie_to == t.id && plot::can_share(e) && !e.hidden).collect()
}

/// The label a piece shares, if it shares one.
pub fn tied_to<'a>(d: &'a Diagram, e: &El) -> Option<&'a El> {
    if e.tie_to.is_empty() || !plot::can_share(e) {
        return None;
    }
    d.get(&e.tie_to).filter(|t| t.kind == Kind::Text)
}

/// **One label for many lamps** (his ask, 2026-10-03: *"multiple lines
/// and connectors coming out of one label"*): the words where he put them
/// — what he typed, else what the lamps are, counted ("4× 2K BLONDE") —
/// and a fine grey line from the label's edge to every lamp tied to it.
/// **In ink, one size, its second line grey, nothing behind it** (Back to
/// Paper, 2026-10-04): a callout like any lamp's. The label's stored size
/// and colour stay in the film.
fn label_for_many(out: &mut Out, t: &El, d: &Diagram, ctx: &Context, opt: &Options, marks: &Marks) {
    // **It obeys View › Labels and Hide Label** like every other label
    // (Back to Paper, Batch 2): hidden, its words and its lines go; the
    // label and its lamps' ties stay in the film.
    let typed = !out.typing.is_empty() && out.typing == t.id;
    if !typed && (!d.settings.labels || t.label_hidden) {
        return;
    }
    let lamps = held(d, t);
    let words = shared_words(t, &lamps, ctx, out.counts);
    let size = NAME_PT;
    // Its first line in its pieces' colour when they share one (2026-10-05),
    // else in ink.
    let inks: Vec<Ink> = lamps.iter().map(|e| piece_words_ink(e, marks)).collect();
    let ink = match inks.first() {
        Some(first) if inks.iter().all(|i| i == first) => first.clone(),
        _ => Ink::Role("ink"),
    };
    let mut label = fixed_text(&t.id, "body", t.x, t.y, &words, size, ink, "middle", 0.0, true);
    let named = shared_name_lines(t, &lamps, ctx);
    if let Geom::Text { under, lead, .. } = &mut label.geom {
        *under = Ink::Role("ink2");
        *lead = named.max(1);
    }
    out.put(LABELS, label);
    // **Tidy lines** (his note, 2026-10-17: *"labels' lines should have nice
    // intersections so things don't get too messy"*): one line leaves the
    // label from the middle of the side that faces its pieces, runs a short
    // trunk to one junction, and splits there — a straight branch to each
    // piece, or one clean elbow round the label when a piece is behind it.
    // Branches from one point never cross each other. One thin weight; a
    // small dot where each ends, and one on the junction.
    let k = if opt.scale > 0.0 { opt.scale } else { NOMINAL_SCALE };
    let (tw, th) = words_box_pt(&cased(out.caps, &words), size * out.words);
    let (hw, hh) = ((tw + 2.0 * PATCH_PAD) / k / 2.0, (th + PATCH_PAD) / k / 2.0);
    let m = mark_m(opt);
    // **A fine line to each lamp** (Ref 1492), every one: a lamp's own
    // Hide Label is for its own callout, which it does not wear while it
    // shares this one. Hide Label on a lamp of a shared label hides the
    // label (the app and the portal send it there).
    let ends: Vec<((f64, f64), &El, f64)> = lamps
        .iter()
        .map(|e| {
            let (x, y, rot) = placed(e, opt);
            ((x, y), *e, rot)
        })
        .collect();
    let paths = leader_paths(&ends.iter().map(|(p, _, _)| *p).collect::<Vec<_>>(), (t.x, t.y), (hw, hh), m, |i, from| {
        let ((x, y), e, rot) = ends[i];
        let (vx, vy) = (x - from.0, y - from.1);
        let len = vx.hypot(vy).max(1e-9);
        let (ux, uy) = (vx / len, vy / len);
        // Short of a lamp's mark; at the edge of a frame, a sofa, a
        // camera — anything with a size of its own on the plan.
        if plot::is_lamp(e) && !plot::points_down(e) {
            m * 0.6
        } else {
            let (pw, ph) = drawn_size(e, d, opt).unwrap_or((e.w, e.h));
            let r = (-rot).to_radians();
            let (lx, ly) = (ux * r.cos() - uy * r.sin(), ux * r.sin() + uy * r.cos());
            let edge = (if lx.abs() > 1e-9 { pw / 2.0 / lx.abs() } else { f64::MAX }).min(if ly.abs() > 1e-9 { ph / 2.0 / ly.abs() } else { f64::MAX });
            edge.min(len).max(m * 0.6) + m * 0.1
        }
    });
    let dot = 1.5 / k;
    for p in &paths.lines {
        out.put(PATHS, stroked(&t.id, "tie", poly(p, false), Ink::Role("ink2"), 0.7, ""));
    }
    for (i, c) in paths.dots.iter().enumerate() {
        let r = if paths.junction && i == 0 { dot * 1.15 } else { dot };
        out.put(PATHS, filled(&t.id, "tie", circle(c.0, c.1, r), Ink::Role("ink2"), Ink::None, 0.0));
    }
}

/// A label's lines, laid out (`leader_paths`): each a run of points, and
/// the dots — the junction first when there is one, then each end.
#[derive(Debug, Default)]
pub struct Leaders {
    pub lines: Vec<Vec<(f64, f64)>>,
    pub dots: Vec<(f64, f64)>,
    pub junction: bool,
}

/// **The lines from one label to its pieces** (2026-10-17), metres: the
/// label's middle `at` and half size `half`; `ends` the pieces' middles;
/// `reach(i, from)` how far short of piece `i` a line coming from `from`
/// stops. One piece: a straight line from the label's nearest side. More:
/// a trunk from the middle of the side facing them to a junction, a branch
/// from there to each — straight, or one elbow when straight would run
/// back through the label.
pub fn leader_paths(ends: &[(f64, f64)], at: (f64, f64), half: (f64, f64), m: f64, reach: impl Fn(usize, (f64, f64)) -> f64) -> Leaders {
    let mut out = Leaders::default();
    if ends.is_empty() {
        return out;
    }
    let (hw, hh) = half;
    let label = Bx { x1: at.0 - hw, y1: at.1 - hh, x2: at.0 + hw, y2: at.1 + hh };
    // Where a line leaves the label toward `p`: the middle of the side
    // that faces it, and the way out of that side.
    let side = |p: (f64, f64)| -> ((f64, f64), (f64, f64)) {
        let (dx, dy) = (p.0 - at.0, p.1 - at.1);
        if dy.abs() * hw >= dx.abs() * hh {
            let s = dy.signum();
            ((at.0, at.1 + s * hh), (0.0, s))
        } else {
            let s = dx.signum();
            ((at.0 + s * hw, at.1), (s, 0.0))
        }
    };
    // Stop short of the piece along the last leg.
    let finish = |i: usize, from: (f64, f64)| -> Option<(f64, f64)> {
        let p = ends[i];
        let (vx, vy) = (p.0 - from.0, p.1 - from.1);
        let len = vx.hypot(vy);
        let r = reach(i, from);
        if len <= r + 1e-6 {
            return None;
        }
        Some((from.0 + vx / len * (len - r), from.1 + vy / len * (len - r)))
    };
    // A branch from `j`: straight, else one elbow that clears the label.
    let branch = |i: usize, j: (f64, f64)| -> Option<Vec<(f64, f64)>> {
        let p = ends[i];
        let straight = finish(i, j)?;
        let nudge = |q: (f64, f64)| (j.0 + (q.0 - j.0) * 0.999, j.1 + (q.1 - j.1) * 0.999);
        let start = nudge((j.0 + (straight.0 - j.0) * 0.02, j.1 + (straight.1 - j.1) * 0.02));
        if !crosses(start, straight, &label) {
            return Some(vec![j, straight]);
        }
        for elbow in [(p.0, j.1), (j.0, p.1)] {
            let s2 = (j.0 + (elbow.0 - j.0) * 0.02, j.1 + (elbow.1 - j.1) * 0.02);
            if crosses(s2, elbow, &label) || crosses(elbow, p, &label) {
                continue;
            }
            if let Some(end) = finish(i, elbow) {
                return Some(vec![j, elbow, end]);
            }
        }
        Some(vec![j, straight])
    };
    if ends.len() == 1 {
        let (a, _) = side(ends[0]);
        if let Some(b) = finish(0, a) {
            if (b.0 - a.0).hypot(b.1 - a.1) > m * 0.2 {
                out.lines.push(vec![a, b]);
                out.dots.push(b);
            }
        }
        return out;
    }
    let n = ends.len() as f64;
    let c = (ends.iter().map(|p| p.0).sum::<f64>() / n, ends.iter().map(|p| p.1).sum::<f64>() / n);
    let (a, way) = side(c);
    // The trunk: a short way out toward them — a third of the way to the
    // nearest piece along that side's way out, kept between a third and one
    // and a half marks.
    let ahead = ends.iter().map(|p| (p.0 - a.0) * way.0 + (p.1 - a.1) * way.1).filter(|v| *v > 0.0).fold(f64::MAX, f64::min);
    let trunk = if ahead == f64::MAX { m * 0.5 } else { (ahead * 0.35).clamp(m * 0.3, m * 1.5) };
    let j = (a.0 + way.0 * trunk, a.1 + way.1 * trunk);
    let mut branches = Vec::new();
    for i in 0..ends.len() {
        if let Some(b) = branch(i, j) {
            branches.push(b);
        }
    }
    if branches.is_empty() {
        return out;
    }
    out.lines.push(vec![a, j]);
    out.junction = true;
    out.dots.push(j);
    for b in branches {
        out.dots.push(*b.last().unwrap());
        out.lines.push(b);
    }
    out
}

/// The ink a piece's Name is written in: a lamp's as its mark's, a frame's
/// and grip's in grip's ink or his colour, anything else in ink.
fn piece_words_ink(e: &El, marks: &Marks) -> Ink {
    if plot::is_lamp(e) {
        lamp_words_ink(e, marks)
    } else if is_hex(&e.color) {
        Ink::hex(&e.color)
    } else if e.kind == Kind::Light {
        Ink::Role("gripink")
    } else {
        Ink::Role("ink")
    }
}

/// **The ink a lamp's Name is written in** (his call, 2026-10-05): its
/// mark's — his colour on it, the location's grey, the Type's ink — and a
/// practical's in a deeper amber than its mark, so it reads.
fn lamp_words_ink(e: &El, marks: &Marks) -> Ink {
    let look = marks.looks.iter().find(|(id, _)| *id == e.id).map(|(_, l)| *l);
    if is_hex(&e.color) {
        Ink::hex(&e.color)
    } else {
        match look.map(|l| l.ink).unwrap_or("added") {
            "ink" => Ink::Role("existing"),
            "practical" => Ink::Role("practicalword"),
            r => Ink::Role(r),
        }
    }
}

/// **What a shared label says** (his call, 2026-10-17: *"what happened to
/// manually writing out labels and not being tied to automatic numbers and
/// counting?"*): the words he typed on it, exactly, on as many lines as he
/// typed. With none typed, the Names its pieces carry, each once — "Key
/// Light + Fill" — counted only with Plan Settings › Counts ("2× Key
/// Light"). A piece with no Name adds nothing; nothing is written for him.
/// Under it, what is done to them: each piece's note, a lamp's gels and Off
/// or Dim, once each (his ask, 2026-10-04).
fn shared_words(t: &El, lamps: &[&El], ctx: &Context, counts: bool) -> String {
    let typed = t.text.trim();
    let mut groups: Vec<(String, u32)> = Vec::new();
    // Lamps first, then frames and grip, then everything else.
    let rank = |e: &El| if plot::is_lamp(e) { 0 } else if e.kind == Kind::Light { 1 } else { 2 };
    let mut lamps: Vec<&El> = lamps.to_vec();
    lamps.sort_by_key(|e| rank(e));
    for e in lamps.iter() {
        let n = piece_name(e, ctx);
        if n.is_empty() {
            continue;
        }
        let c = if plot::is_lamp(e) || frame::is_frame(e) { e.count.max(1) } else { 1 };
        match groups.iter_mut().find(|g| g.0 == n) {
            Some(g) => g.1 += c,
            None => groups.push((n, c)),
        }
    }
    let mut words = if !typed.is_empty() {
        typed.to_string()
    } else {
        groups.iter().map(|(n, c)| if counts && *c > 1 { format!("{c}× {n}") } else { n.clone() }).collect::<Vec<_>>().join(" + ")
    };
    let mut under: Vec<String> = Vec::new();
    for e in lamps {
        let note = note_of(e);
        let mut bits: Vec<String> = hung(e);
        if !note.is_empty() && !groups.iter().any(|(n, _)| n.eq_ignore_ascii_case(note)) && !note.eq_ignore_ascii_case(typed) {
            bits.push(note.to_string());
        }
        bits.extend(e.gels.iter().map(|g| gels::name(g)));
        if (e.existing || e.practical) && !plot_action(e).is_empty() {
            bits.push(plot_action(e).to_string());
        }
        for b in bits {
            if !under.contains(&b) {
                under.push(b);
            }
        }
    }
    if !under.is_empty() {
        if !words.is_empty() {
            words.push('\n');
        }
        words.push_str(&under.join(" · "));
    }
    words
}

/// How many of a shared label's lines are its words, before what is done
/// to its pieces.
fn shared_name_lines(t: &El, lamps: &[&El], ctx: &Context) -> usize {
    let typed = t.text.trim();
    if !typed.is_empty() {
        return lines_in(typed);
    }
    lamps.iter().map(|e| piece_name(e, ctx)).filter(|n| !n.is_empty()).map(|n| lines_in(&n)).max().unwrap_or(0)
}

/// **A piece's Name as he typed it** (2026-10-17): a lamp's and a frame's
/// `lamp_name`, a camera's label else its shot's number, a person's label
/// else their character, Words their text, anything else its `label`.
/// Empty when he has typed none — never its kind, size or cloth.
pub fn piece_name(e: &El, ctx: &Context) -> String {
    let n = if plot::is_lamp(e) || frame::is_frame(e) {
        plot::lamp_name(e)
    } else {
        match e.kind {
            Kind::Camera => camera_name(e, ctx),
            Kind::Cast => cast_label(e, ctx),
            Kind::Text | Kind::Note => e.text.clone(),
            _ => e.label.clone(),
        }
    };
    n.trim().to_string()
}

/// A piece's Note: a lamp's and a frame's under their name (`label`),
/// anything else's in its `caption`.
pub fn note_of(e: &El) -> &str {
    if plot::is_lamp(e) || frame::is_frame(e) { e.label.trim() } else { e.caption.trim() }
}

/// The words a shared label shows, for a shell sizing it; none for words
/// that are not one.
pub fn shared_label_words(d: &Diagram, t: &El) -> Option<String> {
    if t.kind != Kind::Text || !shared_label(d, t) {
        return None;
    }
    Some(cased(d.settings.caps, &shared_words(t, &held(d, t), &Context::default(), d.settings.counts)))
}

/// Whether the line from `a` to `b` runs through a box.
fn crosses(a: (f64, f64), b: (f64, f64), bx: &Bx) -> bool {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let (mut t0, mut t1) = (0.0f64, 1.0f64);
    for (p, q) in [(-dx, a.0 - bx.x1), (dx, bx.x2 - a.0), (-dy, a.1 - bx.y1), (dy, bx.y2 - a.1)] {
        if p.abs() < 1e-12 {
            if q < 0.0 {
                return false;
            }
        } else {
            let r = q / p;
            if p < 0.0 {
                t0 = t0.max(r);
            } else {
                t1 = t1.min(r);
            }
            if t0 > t1 {
                return false;
            }
        }
    }
    true
}

/// **Where new words go clear of the plan** (Back to Paper, Batch 2, fix
/// round 2): a spot for `text` by the points `around` — the lamps a shared
/// label is made for — where it sits on no other words and no piece, at
/// `scale` points to the metre (0: the Mac's opening zoom). Above them
/// first, then below, right and left, then further out; the least crowded
/// spot when nothing is clear. `skip`: the words being placed, not an
/// obstacle to themselves.
/// `page`: `scale` is the sheet's, and words are lettered as it letters
/// them (`Options::page`).
pub fn clear_spot(d: &Diagram, scale: f64, page: bool, text: &str, around: &[(f64, f64)], skip: &str) -> (f64, f64) {
    let opt = Options { scale, page, ..Options::default() };
    let wf = lettering(&opt).words;
    let k = if scale > 0.0 { scale } else { NOMINAL_SCALE };
    let shapes = render(d, &Context::default(), &opt);
    let mut taken: Vec<Bx> = Vec::new();
    for s in shapes.iter().filter(|s| s.el != skip) {
        if let Geom::Text { x, y, text, size, fixed: true, rot, anchor, bold, .. } = &s.geom {
            if rot.abs() < 45.0 || rot.abs() > 135.0 {
                let (w, h) = words_box_pt(text, *size);
                let w = if *bold { w * 1.08 } else { w };
                let (w, h) = ((w + 2.0 * PATCH_PAD) / k, (h + PATCH_PAD) / k);
                let cx = match *anchor {
                    "start" => x + w / 2.0,
                    "end" => x - w / 2.0,
                    _ => *x,
                };
                taken.push(Bx::at((cx, *y), w, h));
            } else {
                let (w, h) = words_box_pt(text, *size);
                let (w, h) = ((h + PATCH_PAD) / k, (w + 2.0 * PATCH_PAD) / k);
                taken.push(Bx::at((*x, *y), w, h));
            }
        }
    }
    let pieces: Vec<[(f64, f64); 4]> = name_obstacles(d, &opt).into_iter().filter(|(id, _)| id != skip).map(|(_, q)| q).collect();
    let (tw, th) = words_box_pt(&cased(d.settings.caps, text), NAME_PT * wf);
    let (bw, bh) = ((tw + 2.0 * PATCH_PAD) / k, (th + PATCH_PAD) / k);
    if around.is_empty() {
        return (0.0, 0.0);
    }
    let m = mark_m(&opt);
    let x1 = around.iter().map(|p| p.0).fold(f64::MAX, f64::min) - m / 2.0;
    let x2 = around.iter().map(|p| p.0).fold(f64::MIN, f64::max) + m / 2.0;
    let y1 = around.iter().map(|p| p.1).fold(f64::MAX, f64::min) - m / 2.0;
    let y2 = around.iter().map(|p| p.1).fold(f64::MIN, f64::max) + m / 2.0;
    let (cx, cy) = ((x1 + x2) / 2.0, (y1 + y2) / 2.0);
    let gap = 3.0 * NAME_GAP / k + m * 0.5;
    let bases = [
        (cx, y1 - gap - bh / 2.0),
        (cx, y2 + gap + bh / 2.0),
        (x2 + gap + bw / 2.0, cy),
        (x1 - gap - bw / 2.0, cy),
    ];
    let cost = |c: (f64, f64)| {
        let b = Bx::at(c, bw, bh);
        // With a line's breadth of air over and under other words.
        let air = Bx::at(c, bw, bh + 2.0 * NAME_PT * wf / k);
        let on_words: f64 = taken.iter().map(|t| t.shared(&air)).sum();
        let on_pieces: f64 = pieces.iter().filter(|q| hits(&b, q)).map(|q| quad_box(q).shared(&b).max(1e-6)).sum();
        on_words * 10.0 + on_pieces
    };
    // The plan as it stands: words put outside it grow the sheet and
    // shrink everything on it, so a spot inside is worth a longer line.
    let within = bounds(&shapes.iter().filter(|s| s.el != skip).cloned().collect::<Vec<_>>());
    let outside = |c: (f64, f64)| match &within {
        Some(a) => {
            let b = Bx::at(c, bw, bh);
            (a.x1 - b.x1).max(0.0) + (b.x2 - a.x2).max(0.0) + (a.y1 - b.y1).max(0.0) + (b.y2 - a.y2).max(0.0)
        }
        None => 0.0,
    };
    let (sx, sy) = (bw * 0.25, bh * 0.5);
    // Its fine lines run to every lamp: each one that would cross other
    // words counts as a metre further off.
    let crossings = |c: (f64, f64)| around.iter().map(|p| taken.iter().filter(|t| crosses(c, *p, t)).count()).sum::<usize>() as f64;
    // The clear spot nearest the lamps; else the least crowded.
    let mut clear: Option<(f64, (f64, f64))> = None;
    let mut crowded = (f64::MAX, bases[0]);
    for base in bases {
        for i in -14i32..=14 {
            for j in -14i32..=14 {
                let c = (base.0 + i as f64 * sx, base.1 + j as f64 * sy);
                let far = (c.0 - cx).hypot(c.1 - cy) + 2.0 * outside(c) + crossings(c);
                let v = cost(c);
                if v <= 1e-12 {
                    if clear.map(|(f, _)| far < f).unwrap_or(true) {
                        clear = Some((far, c));
                    }
                } else if v * (1.0 + far) < crowded.0 {
                    crowded = (v * (1.0 + far), c);
                }
            }
        }
    }
    clear.map(|(_, c)| c).unwrap_or(crowded.1)
}

/// Every lamp's mark on a plot and what each mark stands for, worked out
/// once for the whole sheet.
#[derive(Default)]
struct Marks {
    looks: Vec<(String, plot::Look)>,
}

/// A step that is `(dx, dy)` on the page as it is shown — north turned up —
/// given in the plan's own directions.
fn unturn(d: &Diagram, dx: f64, dy: f64) -> (f64, f64) {
    let r = (-view_turn(d)).to_radians();
    (dx * r.cos() - dy * r.sin(), dx * r.sin() + dy * r.cos())
}

fn track(out: &mut Out, e: &El, d: &Diagram) {
    let pts = line_points(e);
    let half = e.thick.max(0.2) / 2.0;
    // Track is camera gear: the cameras' colour.
    let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("camink") };
    let length = walk(&pts);
    {
        // Its length and the sections it takes: "24 FT · 3 × 8'" — quiet,
        // grey and small, as a measurement is (Back to Paper, 2026-10-04).
        let (m, h) = along(&pts, length / 2.0);
        let at = Xf::new(m.0, m.1, h).p(0.0, -half - 0.3);
        let mut words = format!("{} · {}", length_text(length, &d.settings.units), plot::track_sections(length));
        if !e.label.trim().is_empty() {
            words = format!("{} · {}", e.label.trim(), words);
        }
        out.put(LABELS, label_text(e, at.0, at.1, &words, MEASURE_PT, Ink::Role("ink2"), readable(h)));
    }
    // **Two rails and their ties** (his note, 2026-10-05: *"track doesnt
    // seem to lay dolly track but instead another measurement"*): the thin
    // centre line with ticks read as a ruler. Dolly track as a plan draws
    // it — two fine rails its gauge apart, a tie across them every two
    // feet (up to four hundred; past that they spread out). Still lines,
    // not the old slab.
    let gauge = half.min(0.4);
    out.put(SET, stroked(&e.id, "body", poly(&offset(&pts, -gauge), false), ink.clone(), 1.2, ""));
    out.put(SET, stroked(&e.id, "body", poly(&offset(&pts, gauge), false), ink.clone(), 1.2, ""));
    let every = (length / 400.0).max(2.0 * super::FOOT);
    let tie = gauge + 0.06;
    let mut at = every / 2.0;
    let mut ties = Vec::new();
    while at < length {
        let (p, h) = along(&pts, at);
        let xf = Xf::new(p.0, p.1, h);
        ties.extend(xf.path(&line(0.0, -tie, 0.0, tie)));
        at += every;
    }
    if !ties.is_empty() {
        out.put(SET, stroked(&e.id, "body", ties, ink.clone(), 0.8, ""));
    }
    out.put(SET, stroked(&e.id, "body", poly(&pts, false), plot::clear(), (half * 2.0 * NOMINAL_SCALE).clamp(6.0, 24.0), ""));
}

/// **A road on a plot** (his ask, 2026-10-04, after the Las Vegas street
/// plots): its two kerbs in the walls' ink and nothing between them — no
/// grey, no lane lines — cut open wherever another road or a driveway meets
/// or crosses it, so a junction reads as one open space. Its name runs along
/// the middle in capitals: "DOUGLAS AVE".
fn road(out: &mut Out, e: &El, d: &Diagram) {
    let pts = line_points(e);
    let half = e.thick.max(0.5) / 2.0;
    let ink = if is_hex(&e.color) { Ink::hex(&e.color) } else { Ink::Role("plan") };
    let others: Vec<(Vec<(f64, f64)>, f64)> = d
        .els
        .iter()
        .filter(|o| o.kind == Kind::Road && o.id != e.id && !o.hidden)
        .map(|o| (line_points(o), o.thick.max(0.5) / 2.0))
        .collect();
    // **A driveway into a building stops at its wall** (his ask, 2026-10-04:
    // "curved driveways into ... squares"): no kerb is drawn inside a
    // building or a drawn box, so its end only has to reach inside.
    let blocks: Vec<&El> = d
        .els
        .iter()
        .filter(|o| !o.hidden && ((o.kind == Kind::Set && o.sym == "building") || o.kind == Kind::Shape))
        .collect();
    let inside = |o: &El, p: (f64, f64)| {
        let r = (-o.rot).to_radians();
        let (dx, dy) = (p.0 - o.x, p.1 - o.y);
        let (lx, ly) = (dx * r.cos() - dy * r.sin(), dx * r.sin() + dy * r.cos());
        let (hw, hh) = (o.w / 2.0, o.h / 2.0);
        if o.kind == Kind::Shape && matches!(o.sym.as_str(), "ellipse" | "circle") {
            (lx / hw.max(1e-6)).powi(2) + (ly / hh.max(1e-6)).powi(2) < 1.0
        } else {
            lx.abs() < hw - 1e-3 && ly.abs() < hh - 1e-3
        }
    };
    let open = |p: (f64, f64)| others.iter().any(|(c, h)| near_line(c, p) < *h - 0.02) || blocks.iter().any(|o| inside(o, p));
    for side in [-half, half] {
        let kerb = fine(&offset(&pts, side), (walk(&pts) / 2000.0).max(0.2));
        // Where a kerb meets another road's edge, exactly: halved between
        // the last point outside it and the first inside.
        let edge = |mut a: (f64, f64), mut b: (f64, f64)| {
            for _ in 0..14 {
                let m = ((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0);
                if open(m) == open(a) { a = m } else { b = m }
            }
            if open(a) { b } else { a }
        };
        let mut run: Vec<(f64, f64)> = Vec::new();
        let mut last: Option<(f64, f64)> = None;
        for p in kerb {
            if open(p) {
                if let (Some(l), false) = (last, run.is_empty()) {
                    run.push(edge(l, p));
                }
                if run.len() >= 2 {
                    out.put(FLOOR, stroked(&e.id, "body", poly(&run, false), ink.clone(), 1.4, ""));
                }
                run.clear();
            } else {
                if run.is_empty() {
                    if let Some(l) = last {
                        run.push(edge(l, p));
                    }
                }
                run.push(p);
            }
            last = Some(p);
        }
        if run.len() >= 2 {
            out.put(FLOOR, stroked(&e.id, "body", poly(&run, false), ink.clone(), 1.4, ""));
        }
    }
    // Something to pick it by across its whole width, drawing nothing.
    out.put(FLOOR, filled(&e.id, "body", band(&pts, half), plot::clear(), Ink::None, 0.0));
    if out.labels && has_words(e) && !e.label_hidden {
        // In the middle of its longest stretch clear of other roads, so two
        // names never sit on one crossing.
        let total = walk(&pts);
        let n = (total / 0.25).ceil().clamp(1.0, 2000.0) as usize;
        let (mut best, mut from, mut run_from) = ((0.0, total), 0.0, None::<f64>);
        for i in 0..=n {
            let at = total * i as f64 / n as f64;
            let clear = !open(along(&pts, at).0) && i < n;
            match (clear, run_from) {
                (true, None) => run_from = Some(at),
                (false, Some(a)) => {
                    if at - a > best.1 - best.0 || from == 0.0 {
                        best = (a, at);
                        from = 1.0;
                    }
                    run_from = None;
                }
                _ => {}
            }
        }
        let (m, h) = along(&pts, (best.0 + best.1) / 2.0);
        out.put(LABELS, label_text(e, m.0 + e.label_dx, m.1 + e.label_dy, e.label.trim(), NAME_PT, Ink::Role("ink"), readable(h)));
    }
}

/// A line's points again, never more than `step` apart.
fn fine(pts: &[(f64, f64)], step: f64) -> Vec<(f64, f64)> {
    let mut out = Vec::new();
    for w in pts.windows(2) {
        let (a, b) = (w[0], w[1]);
        let n = ((b.0 - a.0).hypot(b.1 - a.1) / step).ceil().max(1.0) as usize;
        for i in 0..n {
            let t = i as f64 / n as f64;
            out.push((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t));
        }
    }
    if let Some(l) = pts.last() {
        out.push(*l);
    }
    out
}

/// How far a point is from a line through `pts`.
fn near_line(pts: &[(f64, f64)], p: (f64, f64)) -> f64 {
    pts.windows(2)
        .map(|w| {
            let (a, b) = (w[0], w[1]);
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let l2 = dx * dx + dy * dy;
            let t = if l2 > 1e-12 { (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
            (p.0 - a.0 - dx * t).hypot(p.1 - a.1 - dy * t)
        })
        .fold(f64::MAX, f64::min)
}

/// **Words are page-size** (Back to Paper, Batch 2): free words stand the
/// same size on the sheet at any scale, like every name on it, rather than
/// growing and shrinking with the plan. A piece's stored `size` keeps its
/// old meaning — points at a zoom of 40 points to the metre — so an old
/// plan's words keep their look at the plan's own size (60 points to the
/// metre, a quarter inch to the foot): `size` × 1.5 points.
pub fn words_pt(size: f64) -> f64 {
    size.max(0.0) * NOMINAL_SCALE / 40.0
}

/// Words' two sizes, as stored (the bar's Regular and Large).
pub const WORDS_REGULAR: f64 = NAME_PT * 40.0 / NOMINAL_SCALE;
pub const WORDS_LARGE: f64 = 14.0 * 40.0 / NOMINAL_SCALE;
/// Large Words as drawn, points at full size: a step over a name
/// (`NAME_PT`), well under the sheet's title.
pub const WORDS_LARGE_PT: f64 = 12.5;

/// Whether stored words read as Large rather than Regular.
pub fn words_large(size: f64) -> bool {
    words_pt(size) >= 12.0
}

/// **Words as drawn** (Ref 1511): in the sheet's two sizes — Regular a
/// name's size, Large a step over it — whatever size an old plan stored
/// (Call Her Back's room names were stored at 13, drawn at 19.5 points, and
/// dwarfed the backyard); regular weight, like every word on the sheet. A
/// stored size and bold stay in the film, untouched.
pub fn words_drawn_pt(size: f64) -> f64 {
    if words_large(size) {
        WORDS_LARGE_PT
    } else {
        NAME_PT
    }
}

fn text(out: &mut Out, e: &El) {
    let large = words_large(e.size);
    let mut s = Shape::new(
        &e.id,
        "body",
        Geom::Text {
            x: e.x,
            y: e.y,
            text: e.text.clone(),
            size: words_drawn_pt(e.size),
            anchor: match e.align.as_str() {
                "left" => "start",
                "right" => "end",
                _ => "middle",
            },
            bold: false,
            rot: e.rot,
            fixed: true,
            halo: false,
            patch: false,
            shift: (0.0, 0.0),
            under: Ink::None,
            lead: 1,
        },
    );
    // **Large Words name places** — LIVING ROOM, POOL, DECK — and take the
    // set's quiet grey; Regular Words are notes, in ink. His colour wins
    // either way.
    s.fill = if large && !is_hex(&e.color) { Ink::Role("ink2") } else { own(e, "ink") };
    out.put(WORDS, s);
}

/// **The Ruler** (his ask, 2026-10-01): a line through its markers, ticked
/// every foot (or metre, the plan's units) with a longer tick every five,
/// each stretch saying its own length — *"the distance between the two ends
/// of whatever i lay down"* — and the whole when there are more than two
/// markers. A marker locked to a person or object (`El::pins`) is a filled
/// dot and stands where that piece stands at this beat; one placed by hand
/// is open.
fn measure(out: &mut Out, e: &El, d: &Diagram, opt: &Options) {
    let ink = own(e, "ink2");
    let mut c = super::walls::corners(e);
    for (k, pin) in e.pins.iter().enumerate() {
        if let (Some(p), Some(t)) = (c.get_mut(k), d.get(pin).filter(|_| !pin.is_empty())) {
            if !t.steps.is_empty() {
                let (x, y, _) = placed(t, opt);
                *p = (x, y);
            }
        }
    }
    if c.len() < 2 {
        return;
    }
    out.put(WORDS, stroked(&e.id, "body", poly(&c, false), ink.clone(), 1.2, ""));
    // Ticks along the whole line, counted from its start.
    let step: f64 = if d.settings.units == "m" { 1.0 } else { 0.3048 };
    let total: f64 = c.windows(2).map(|w| (w[1].0 - w[0].0).hypot(w[1].1 - w[0].1)).sum();
    let mut segs = Vec::new();
    let mut walked: f64 = 0.0;
    for w in c.windows(2) {
        let (a, b) = (w[0], w[1]);
        let len = (b.0 - a.0).hypot(b.1 - a.1);
        if len < 1e-9 {
            continue;
        }
        let h = (b.1 - a.1).atan2(b.0 - a.0).to_degrees();
        let mut n = (walked / step).ceil() as i64;
        while (n as f64) * step <= walked + len + 1e-9 && n < 2000 {
            let along = n as f64 * step - walked;
            let p = (a.0 + (b.0 - a.0) * along / len, a.1 + (b.1 - a.1) * along / len);
            let half = if n % 5 == 0 { 0.09 } else { 0.05 };
            let t = Xf::new(p.0, p.1, h + 90.0);
            segs.extend(line(t.p(-half, 0.0).0, t.p(-half, 0.0).1, t.p(half, 0.0).0, t.p(half, 0.0).1));
            n += 1;
        }
        walked += len;
    }
    if !segs.is_empty() {
        out.put(WORDS, stroked(&e.id, "body", segs, ink.clone(), 0.8, ""));
    }
    // The two ends: a bar across, as a measure has always had.
    let first = (c[1].1 - c[0].1).atan2(c[1].0 - c[0].0).to_degrees();
    let n = c.len();
    let last = (c[n - 1].1 - c[n - 2].1).atan2(c[n - 1].0 - c[n - 2].0).to_degrees();
    for (p, h) in [(c[0], first), (c[n - 1], last)] {
        let t = Xf::new(p.0, p.1, h + 90.0);
        out.put(WORDS, stroked(&e.id, "body", poly(&[t.p(-0.14, 0.0), t.p(0.14, 0.0)], false), ink.clone(), 1.4, ""));
    }
    // The markers: filled when locked to something, open when placed by hand.
    for (k, p) in c.iter().enumerate() {
        let locked = e.pins.get(k).map(|s| !s.is_empty()).unwrap_or(false);
        if !locked && (k == 0 || k + 1 == n) {
            continue;
        }
        let fill = if locked { ink.clone() } else { Ink::Role("paper") };
        out.put(WORDS, filled(&e.id, "marker", circle(p.0, p.1, 0.07), fill, ink.clone(), 1.0));
    }
    // Each stretch's own length at its middle, and the whole past the end.
    for w in c.windows(2) {
        let (a, b) = (w[0], w[1]);
        let len = (b.0 - a.0).hypot(b.1 - a.1);
        if len < 0.05 {
            continue;
        }
        let h = (b.1 - a.1).atan2(b.0 - a.0).to_degrees();
        let at = Xf::new((a.0 + b.0) / 2.0, (a.1 + b.1) / 2.0, h).p(0.0, -0.2);
        out.put(LABELS, fixed_text(&e.id, "label", at.0, at.1, &length_text(len, &d.settings.units), MEASURE_PT, ink.clone(), "middle", readable(h), true));
    }
    if n > 2 {
        // Under the last marker, across the line — clear of the + past its end.
        let at = Xf::new(c[n - 1].0, c[n - 1].1, last).p(0.0, 0.4);
        let words = format!("Total {}", length_text(total, &d.settings.units));
        out.put(LABELS, fixed_text(&e.id, "label", at.0, at.1, &words, MEASURE_PT, ink, "middle", readable(last), true));
    }
}

fn arrow(out: &mut Out, e: &El) {
    let pts = line_points(e);
    let ink = own(e, "ink");
    let weight = if e.weight > 0.0 { e.weight } else { 2.0 };
    let dash = match e.dash.as_str() {
        "dashed" | "dash" => "dash",
        "dotted" | "dot" => "dot",
        _ => "",
    };
    let size = 0.12 + weight * 0.03;
    let length = walk(&pts);
    // Stop the line short of its head, so a thick line keeps a sharp point.
    let draw = if pts.len() >= 2 && e.head != "none" && length > size {
        let mut p = pts.clone();
        let (end, _) = along(&pts, length - size * 0.7);
        *p.last_mut().unwrap() = end;
        p
    } else {
        pts.clone()
    };
    // **A connector runs under the pieces** (his note, 2026-10-05:
    // *"connecting lines should go underneath objects like lights, the
    // same way they do other labels"*): a line with no head goes where a
    // shared label's lines go; an arrow still points over them.
    let tier = if e.head == "none" { PATHS } else { WORDS };
    out.put(tier, stroked(&e.id, "body", poly(&draw, false), ink.clone(), weight, dash));
    if e.head != "none" && pts.len() >= 2 {
        let (tip, h) = along(&pts, length);
        out.put(WORDS, filled(&e.id, "body", head(tip, h, size), ink.clone(), Ink::None, 0.0));
        if e.head == "both" {
            let (tail, h0) = along(&pts, 0.0);
            out.put(WORDS, filled(&e.id, "body", head(tail, h0 + 180.0, size), ink.clone(), Ink::None, 0.0));
        }
    }
    if out.labels && has_words(e) {
        let (m, h) = along(&pts, length / 2.0);
        let at = Xf::new(m.0, m.1, h).p(0.0, -0.22);
        out.put(LABELS, label_text(e, at.0, at.1, &e.label, NAME_PT, Ink::Role("ink"), readable(h)));
    }
}

fn shape(out: &mut Out, e: &El) {
    let xf = Xf::new(e.x, e.y, e.rot);
    let (w, h) = (e.w, e.h);
    let local = match e.sym.as_str() {
        "ellipse" | "circle" => ellipse(0.0, 0.0, w / 2.0, h / 2.0),
        "triangle" => poly(&[(0.0, -h / 2.0), (w / 2.0, h / 2.0), (-w / 2.0, h / 2.0)], true),
        "diamond" => poly(&[(0.0, -h / 2.0), (w / 2.0, 0.0), (0.0, h / 2.0), (-w / 2.0, 0.0)], true),
        "hexagon" | "pentagon" | "star" => {
            let n = match e.sym.as_str() {
                "hexagon" => 6,
                "pentagon" => 5,
                _ => 10,
            };
            let pts: Vec<(f64, f64)> = (0..n)
                .map(|i| {
                    let a = (-90.0 + 360.0 * i as f64 / n as f64).to_radians();
                    let k = if e.sym == "star" && i % 2 == 1 { 0.45 } else { 1.0 };
                    (a.cos() * w / 2.0 * k, a.sin() * h / 2.0 * k)
                })
                .collect();
            poly(&pts, true)
        }
        "line" => line(-w / 2.0, 0.0, w / 2.0, 0.0),
        _ => rrect(-w / 2.0, -h / 2.0, w, h, if e.curve > 0.0 { e.curve } else { 0.0 }),
    };
    let ink = own(e, "zone");
    let dash = match e.dash.as_str() {
        "dashed" | "dash" => "dash",
        "dotted" | "dot" => "dot",
        _ => "",
    };
    // Filled: a wash of its colour, so what is under it — and its own name,
    // in the same colour — still reads. A role ink carries no alpha of its
    // own, so the wash is its own shape, faded, under the outline.
    if e.fill && e.sym != "line" {
        let mut wash = filled(&e.id, "body", xf.path(&local), if is_hex(&e.color) { ink.clone() } else { Ink::Role("zonefill") }, Ink::None, 0.0);
        wash.alpha = 0.16;
        out.put(SET, wash);
    }
    let mut s = filled(&e.id, "body", xf.path(&local), Ink::None, ink.clone(), if e.weight > 0.0 { e.weight } else { 1.4 });
    s.dash = dash;
    out.put(SET, s);
    if out.labels && has_words(e) {
        out.put(LABELS, label_text(e, e.x, e.y, &e.label, NAME_PT, Ink::Role("ink"), 0.0));
    }
}

/// **The wash inside a closed path or room**: its own fill colour, or the
/// plan's tint, as firm as `fill_alpha` says. None when it is not filled — a
/// drawn path by `fill`, a room only by a `fill_color`.
fn fill_wash(e: &El, segs: Vec<Seg>, ink: &Ink) -> Option<Shape> {
    let colour = is_hex(&e.fill_color);
    let on = if e.kind == Kind::Wall { colour || e.fill_color == "auto" } else { colour || e.fill };
    if !on || !super::walls::closed(e) {
        return None;
    }
    let (paint, default) = if colour {
        (Ink::hex(&e.fill_color), 0.55)
    } else if is_hex(&e.color) {
        (ink.clone(), 0.16)
    } else {
        (Ink::Role("zonefill"), 0.16)
    };
    let mut wash = filled(&e.id, "body", segs, paint, Ink::None, 0.0);
    wash.alpha = if e.fill_alpha > 0.0 { e.fill_alpha } else { default };
    Some(wash)
}

/// A drawn path as a drawing path: a straight stretch a line, a smooth one a
/// curve, and closed ones back to the start.
fn path_segs(e: &El) -> Vec<Seg> {
    let c = super::walls::corners(e);
    let n = c.len();
    let mut out = vec![Seg::M(c[0].0, c[0].1)];
    for i in 0..super::walls::stretch_count(e) {
        let (a, c1, c2, b) = super::walls::stretch_cubic(e, &c, i);
        let _ = a;
        if super::walls::stretch_curved(e, i) {
            out.push(Seg::C(c1.0, c1.1, c2.0, c2.1, b.0, b.1));
        } else {
            out.push(Seg::L(c[(i + 1) % n].0, c[(i + 1) % n].1));
        }
    }
    if super::walls::closed(e) {
        out.push(Seg::Z);
    }
    out
}

fn polyline(out: &mut Out, e: &El) {
    if e.points.is_empty() {
        return;
    }
    let ink = own(e, if e.kind == Kind::Cable { "cable" } else { "ink" });
    let weight = if e.weight > 0.0 { e.weight } else { 2.0 };
    // A path drawn with the Draw tool is exact: its corners and the curves it
    // was given. A freehand stroke, older than that, is smoothed through its points.
    let drawn = e.kind == Kind::Stroke && e.points.len() >= 2 && (!e.handles.is_empty() || e.closed);
    let segs = if drawn {
        path_segs(e)
    } else if e.kind == Kind::Stroke {
        smooth(&e.points)
    } else {
        poly(&e.points, false)
    };
    // A closed, filled path is an object: a wash inside, and its name.
    if let Some(wash) = fill_wash(e, segs.clone(), &ink).filter(|_| drawn) {
        out.put(SET, wash);
        if out.labels && has_words(e) {
            let (cx, cy) = e.centre();
            out.put(LABELS, label_text(e, cx, cy, &e.label, NAME_PT, Ink::Role("ink"), 0.0));
        }
    }
    let mut s = stroked(&e.id, "body", segs, ink.clone(), weight, if e.dash == "dashed" { "dash" } else { "" });
    if e.points.len() == 1 {
        let (x, y) = e.points[0];
        s = filled(&e.id, "body", circle(x, y, weight * 0.01), ink.clone(), Ink::None, 0.0);
    }
    out.put(SET, s);
    if out.labels && e.kind == Kind::Cable && has_words(e) {
        let (m, h) = along(&e.points, walk(&e.points) / 2.0);
        let at = Xf::new(m.0, m.1, h).p(0.0, -0.2);
        out.put(LABELS, label_text(e, at.0, at.1, &e.label, NAME_PT, Ink::Role("ink"), readable(h)));
    }
}

/// A picture is a **background** laid under the plan — a floor plan, the
/// room from above — unless its role is `photo`: a loose picture put
/// anywhere, drawn over the plan in a thin frame, like a print pinned to it.
fn image(out: &mut Out, e: &El) {
    let s = Shape::new(
        &e.id,
        "body",
        Geom::Image { media: e.media.clone(), x: e.x, y: e.y, w: e.w, h: e.h, rot: e.rot },
    );
    // Its marks go with it, drawn on it (`photomarks`).
    let marks = super::photomarks::shapes(e);
    if e.role != "photo" {
        out.put(FLOOR, s);
        for m in marks {
            out.put(FLOOR, m);
        }
        return;
    }
    out.put(WORDS, s);
    for m in marks {
        out.put(WORDS, m);
    }
    let xf = Xf::new(e.x, e.y, e.rot);
    let (hw, hh) = (e.w / 2.0, e.h / 2.0);
    let corners: Vec<(f64, f64)> = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].iter().map(|&(x, y)| xf.p(x, y)).collect();
    out.put(WORDS, stroked(&e.id, "frame", poly(&corners, true), Ink::Role("setline"), 1.0, ""));
}

fn note(out: &mut Out, e: &El) {
    let text = if e.text.is_empty() { "Note".to_string() } else { e.text.clone() };
    let mut p = Shape::new(&e.id, "body", Geom::Pill { x: e.x, y: e.y, text, size: 10.5, ink: Ink::Role("note") });
    p.fill = own(e, "note");
    p.stroke = Ink::Role("noteline");
    out.put(LABELS, p);
}

// ---------------------------------------------------------------- extent

/// How much of the plan there is to show: every element's box, and every cone
/// and beam, in metres. `None` for an empty plan.
/// The plan's bounds as it is shown — turned so north is up — with room for
/// every fixed-size word — the sun's, a piece's name, a place's — which hang
/// off their marks and keep their size on the page however far the plan is
/// zoomed (Refs 1437, 1577): a view about `FIT_VIEW_PT` points across is
/// assumed.
pub fn extent(d: &Diagram, ctx: &Context) -> Option<super::Aabb> {
    extent_in(d, ctx, FIT_VIEW_PT)
}

/// What a picture is assumed to be across, points, when the engine makes
/// room for words that stay one size however far the plan is zoomed.
pub const FIT_VIEW_PT: f64 = 700.0;

/// `extent`, for a view `view_pt` points across (the picture's width less its
/// margins): fixed-size words stay one size, so how many metres they take
/// depends on how far the plan is zoomed, which depends on how much room it
/// asks for. Worked to a steady answer.
pub fn extent_in(d: &Diagram, ctx: &Context, view_pt: f64) -> Option<super::Aabb> {
    let mut shapes = render(d, ctx, &Options { beat: 1, tween: 0.0, sel: Vec::new(), paper: true, scale: 0.0, typing: String::new(), page: false });
    // Sunlight is kept inside the plan's frame already; it never widens it.
    shapes.retain(|s| s.part != "sunlight");
    turn_shapes(&mut shapes, view_turn(d));
    let base = bounds(&shapes)?;
    let words: Vec<&Shape> = shapes.iter().filter(|s| matches!(s.geom, Geom::Text { fixed: true, .. })).collect();
    if words.is_empty() || view_pt < 50.0 {
        return Some(base);
    }
    let mut b = base;
    for _ in 0..5 {
        // Points to the metre the plan would be shown at with this much of it.
        let k = (view_pt / (b.x2 - b.x1).max(1.0)).min(view_pt * 0.62 / (b.y2 - b.y1).max(1.0)).max(1e-3);
        b = base;
        for s in &words {
            if let Geom::Text { x, y, text, size, anchor, rot, bold, .. } = &s.geom {
                let (w, h) = words_box_pt(text, *size);
                let w = if *bold { w * 1.08 } else { w };
                let (w, h) = ((w + 2.0 * PATCH_PAD) / k, (h + PATCH_PAD) / k);
                let (w, h) = if rot.abs() < 45.0 || rot.abs() > 135.0 { (w, h) } else { (h, w) };
                let x1 = match *anchor {
                    "start" => *x,
                    "end" => x - w,
                    _ => x - w / 2.0,
                };
                b.x1 = b.x1.min(x1);
                b.x2 = b.x2.max(x1 + w);
                b.y1 = b.y1.min(y - h / 2.0);
                b.y2 = b.y2.max(y + h / 2.0);
            }
        }
    }
    Some(b)
}

/// Where a list of shapes reaches.
pub fn bounds(shapes: &[Shape]) -> Option<super::Aabb> {
    let mut b = super::Aabb { x1: f64::MAX, y1: f64::MAX, x2: f64::MIN, y2: f64::MIN };
    let mut any = false;
    let mut take = |x: f64, y: f64| {
        b.x1 = b.x1.min(x);
        b.y1 = b.y1.min(y);
        b.x2 = b.x2.max(x);
        b.y2 = b.y2.max(y);
        any = true;
    };
    for s in shapes {
        match &s.geom {
            Geom::Path(segs) => {
                for seg in segs {
                    match *seg {
                        Seg::M(x, y) | Seg::L(x, y) => take(x, y),
                        Seg::C(_, _, _, _, x, y) => take(x, y),
                        Seg::Z => {}
                    }
                }
            }
            Geom::Text { x, y, .. } | Geom::Pill { x, y, .. } | Geom::Badge { x, y, .. } => take(*x, *y),
            Geom::Image { x, y, w, h, rot, .. } => {
                for (px, py) in super::corners(*x, *y, *w, *h, *rot) {
                    take(px, py);
                }
            }
        }
    }
    any.then_some(b)
}
