//! **One storyboard arrow, lying on a picture** — and, since 2026-10-14, on a
//! shot's Print Frame board.
//!
//! His ask, 2026-08-31: mark a still with the arrows a storyboard has always
//! used, to say how the shot moves or how a character crosses the frame. The
//! toolkit grew on 2026-10-14 (`design/45-print-frame.html`, section H): any
//! number of pins the shaft passes through, a smooth or a cornered shaft,
//! nought, one or two heads, a dashed line, four looks and three weights.
//! The same evening the three weights became a thickness anywhere from half
//! to three times the old medium, and an arrow gained a depth: drawn flat, or
//! growing as it travels (coming toward camera) or shrinking (going away).
//!
//! **Every number is a fraction of the picture**, nought to one, left to right
//! and top to bottom — of the photograph for an arrow on a picture, of the
//! whole board for an arrow on a Print Frame. Not of the tile it happens to be
//! drawn in: a tile can be any shape and any size, and the arrow was drawn on
//! the thing in the photograph.
//!
//! ## The stored line
//!
//! Arrows are separated by `;`. Each arrow is comma-separated tokens:
//!
//! ```text
//! x1,y1,bx,by,x2,y2,heads[,p<x>:<y>]…[,corner][,dashed][,look:<dark|red|yellow>][,w:<S|L>]
//!   [,thick:<t>][,depth:<toward|away>[:<s>]][,widths:<shaft>:<head>]
//! ```
//!
//! **The first seven are exactly what every older reader understands** —
//! tail, one quadratic control point ("the bend"), head, and the head count.
//! An older reader (the installed iPhone build, the portal's engine) splits on
//! `,`, keeps whatever parses as a number and uses the first seven, so the
//! tokens after them — none of which parse as a number in Rust, Swift or
//! JavaScript, because each starts with a letter that is not `i` or `n` — are
//! simply ignored, and it draws a sensible tail → bend → head arrow.
//!
//! - `heads` is 0, 1 or 2. An older reader draws 0 as one head.
//! - `bx,by` is written so the old quadratic passes through the middle pin
//!   (`bend()` below): the midpoint of tail and head for a straight arrow.
//! - `p<x>:<y>` is one pin, in order from tail to head. **When no `p` token is
//!   present the pins come from the bend** — an arrow written before pins
//!   existed: no pin when the bend sits on the straight line, otherwise one pin
//!   at the curve's own middle, `(tail + 2·bend + head) / 4`, which draws the
//!   identical curve (see `centre_line`). A writer may always write the `p`
//!   tokens; the engine leaves them out when the seven numbers already bring
//!   the pins back, so an arrow nobody has touched since keeps its old line.
//! - Absent `corner` is smooth; absent `dashed` is solid; absent `look` is
//!   light; absent `w` is M. Unknown tokens are ignored.
//! - **Thickness** is one number, `thick:<t>`, half to three times M. The old
//!   weights are thicknesses — S 0.7, M 1, L 1.4 — and an arrow at exactly
//!   one of those is written the old way (`w:S`, nothing, `w:L`), so a line
//!   nobody has touched keeps its bytes. Any other thickness writes `thick:`
//!   **and** the nearest weight before it (`w:S` under 0.85, `w:L` over 1.2),
//!   so a reader from before thickness (the 10-14 builds, which know `w:` and
//!   ignore `thick:`) draws it at the nearest weight it knows. `thick:` wins
//!   over `w:` whatever the order.
//! - **Depth** is `depth:toward` or `depth:away`, with the strength after a
//!   second colon when it is not the usual 0.5 (`depth:away:0.80`). Absent is
//!   flat. A reader from before depth ignores it and draws the arrow flat.
//! - **Widths** set by hand are `widths:<shaft>:<head>`, two half-widths as
//!   fractions of the picture's longer side at thickness 1 (see
//!   `Arrow::widths`): the shaft's, and the head's base. Absent, the depth
//!   sets them. A reader from before widths ignores the token (it is not
//!   `w:`) and draws the depth's own. The first build of widths (2026-10-15,
//!   build 2004) wrote three numbers, tail, middle, head: those are still
//!   read, as shaft = the middle one, head = the head.
//! - A zoom mark may carry `view:<x1>:<y1>:<x2>:<y2>`, the part of the
//!   picture that shows (the film's frame); its arrows start from those
//!   corners. Absent is the whole picture. A reader from before ignores it.
//! - **Stance** (2026-10-15) is `stance:standing` on a Toward or Away arrow
//!   that stands up facing the lens; absent is Floor, lying on the ground.
//!   Written only on a deep arrow. A reader from before stance ignores it and
//!   draws the arrow as it always did.
//! - None of the new tokens starts with a digit, `p`, `i` or `n`, so no reader
//!   of any age takes one for a number or a pin.

mod solid;
pub use solid::Face;

/// The shaft between the pins.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ArrowShape {
    /// Curved through every pin — the storyboard arrow.
    #[default]
    Smooth,
    /// Straight segments with a hard turn at each pin.
    Corner,
}

/// The fill and the outline. Light is the one every arrow had until
/// 2026-10-14: a white shape with a black edge, which reads over a bright
/// photograph and a dark one alike.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ArrowLook {
    #[default]
    Light,
    Dark,
    Red,
    Yellow,
}

/// The three weights the toolkit first had — now just three thicknesses,
/// kept because the stored line and Claude's tools still say them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ArrowWeight {
    S,
    #[default]
    M,
    L,
}

impl ArrowShape {
    pub fn name(self) -> &'static str {
        match self {
            ArrowShape::Smooth => "smooth",
            ArrowShape::Corner => "corner",
        }
    }
    pub fn read(said: &str) -> Option<ArrowShape> {
        match said.trim().to_lowercase().as_str() {
            "smooth" | "curve" | "curved" => Some(ArrowShape::Smooth),
            "corner" | "cornered" => Some(ArrowShape::Corner),
            _ => None,
        }
    }
}

impl ArrowLook {
    pub fn name(self) -> &'static str {
        match self {
            ArrowLook::Light => "light",
            ArrowLook::Dark => "dark",
            ArrowLook::Red => "red",
            ArrowLook::Yellow => "yellow",
        }
    }
    pub fn read(said: &str) -> Option<ArrowLook> {
        match said.trim().to_lowercase().as_str() {
            "light" | "white" => Some(ArrowLook::Light),
            "dark" | "black" => Some(ArrowLook::Dark),
            "red" => Some(ArrowLook::Red),
            "yellow" => Some(ArrowLook::Yellow),
            _ => None,
        }
    }
    /// The inside of the shape.
    pub fn fill(self) -> &'static str {
        match self {
            ArrowLook::Light => "#FFFFFF",
            ArrowLook::Dark => "#141414",
            ArrowLook::Red => "#D44C47",
            ArrowLook::Yellow => "#F3C844",
        }
    }
    /// The side face of a solid Toward or Away arrow: a darker tint of the
    /// fill — lighter for Dark, where darker would not show.
    pub fn shade(self) -> &'static str {
        match self {
            ArrowLook::Light => "#A6A6AB",
            ArrowLook::Dark => "#3C3C3E",
            ArrowLook::Red => "#8F2F2B",
            ArrowLook::Yellow => "#B08A1E",
        }
    }
    /// The outline round it.
    pub fn line(self) -> &'static str {
        match self {
            ArrowLook::Light => "#000000",
            ArrowLook::Dark => "#F4F4F2",
            ArrowLook::Red | ArrowLook::Yellow => "#141414",
        }
    }
}

impl ArrowWeight {
    pub fn name(self) -> &'static str {
        match self {
            ArrowWeight::S => "S",
            ArrowWeight::M => "M",
            ArrowWeight::L => "L",
        }
    }
    pub fn read(said: &str) -> Option<ArrowWeight> {
        match said.trim().to_uppercase().as_str() {
            "S" | "SMALL" | "LIGHT" | "THIN" => Some(ArrowWeight::S),
            "M" | "MEDIUM" => Some(ArrowWeight::M),
            "L" | "LARGE" | "HEAVY" | "THICK" => Some(ArrowWeight::L),
            _ => None,
        }
    }
    /// The factor every size is multiplied by.
    pub fn factor(self) -> f64 {
        match self {
            ArrowWeight::S => 0.7,
            ArrowWeight::M => 1.0,
            ArrowWeight::L => 1.4,
        }
    }
}

/// **Depth** — the storyboard perspective arrow. Flat is every arrow drawn
/// before 2026-10-14's evening.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ArrowDepth {
    #[default]
    Flat,
    /// Narrow at the tail, wide at the head: coming toward camera, moving in.
    Toward,
    /// Wide at the tail, narrowing to a small head: going away.
    Away,
}

impl ArrowDepth {
    pub fn name(self) -> &'static str {
        match self {
            ArrowDepth::Flat => "flat",
            ArrowDepth::Toward => "toward",
            ArrowDepth::Away => "away",
        }
    }
    pub fn read(said: &str) -> Option<ArrowDepth> {
        match said.trim().to_lowercase().as_str() {
            "flat" | "none" => Some(ArrowDepth::Flat),
            "toward" | "towards" | "in" | "forward" | "near" => Some(ArrowDepth::Toward),
            "away" | "out" | "back" | "backward" | "far" => Some(ArrowDepth::Away),
            _ => None,
        }
    }
}

/// **Where a Toward or Away arrow is in the scene** (2026-10-15): a slab
/// lying on the floor, or one standing up and turned to face the lens. Means
/// nothing on a flat arrow.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ArrowStance {
    #[default]
    Floor,
    Standing,
}

impl ArrowStance {
    pub fn name(self) -> &'static str {
        match self {
            ArrowStance::Floor => "floor",
            ArrowStance::Standing => "standing",
        }
    }
    pub fn read(said: &str) -> Option<ArrowStance> {
        match said.trim().to_lowercase().as_str() {
            "floor" | "ground" | "lying" => Some(ArrowStance::Floor),
            "standing" | "stand" | "upright" | "air" => Some(ArrowStance::Standing),
            _ => None,
        }
    }
}

/// **A zoom mark** (2026-10-15): the storyboard way of showing a focal-length
/// change, a smaller frame inset in the picture with four arrows running
/// between the matching corners — inward for In, outward for Out.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ZoomDir {
    In,
    Out,
}

impl ZoomDir {
    pub fn name(self) -> &'static str {
        match self {
            ZoomDir::In => "in",
            ZoomDir::Out => "out",
        }
    }
    pub fn read(said: &str) -> Option<ZoomDir> {
        match said.trim().to_lowercase().as_str() {
            "in" | "zoom in" => Some(ZoomDir::In),
            "out" | "zoom out" => Some(ZoomDir::Out),
            _ => None,
        }
    }
}

/// The smallest and largest an inner zoom frame is, as a fraction of the
/// picture's width (and of its height: the frame has the picture's shape).
pub const LEAST_ZOOM: f64 = 0.10;
pub const MOST_ZOOM: f64 = 0.95;

/// The thinnest and thickest an arrow is drawn, as a multiple of M.
pub const THINNEST: f64 = 0.5;
pub const THICKEST: f64 = 3.0;
/// How strong a depth is when nobody said: the middle of the slider.
pub const USUAL_DEPTH: f64 = 0.5;
/// The weakest and strongest depth.
pub const LEAST_DEPTH: f64 = 0.1;
pub const MOST_DEPTH: f64 = 1.0;
/// The narrowest and widest a hand-set width is, as a fraction of the
/// picture's longer side (half-widths, at thickness 1).
pub const LEAST_WIDTH: f64 = 0.001;
pub const MOST_WIDTH: f64 = 0.75;

/// The most pins one arrow keeps. More than this is not a mark anybody drew.
pub const MOST_PINS: usize = 32;

/// **One storyboard arrow.**
#[derive(Clone, Debug, PartialEq)]
pub struct Arrow {
    /// Where the movement starts.
    pub x1: f64,
    pub y1: f64,
    /// Where the movement ends, and where the head is drawn.
    pub x2: f64,
    pub y2: f64,
    /// The points the shaft passes through, tail to head. None is a straight
    /// arrow.
    pub pins: Vec<(f64, f64)>,
    pub shape: ArrowShape,
    /// 0, 1 (at the head) or 2 (at both ends: back and forth).
    pub heads: u8,
    pub dashed: bool,
    pub look: ArrowLook,
    /// A multiple of M, `THINNEST` to `THICKEST`. 1 is every arrow drawn
    /// before 2026-10-14; S was 0.7 and L 1.4.
    pub thickness: f64,
    pub depth: ArrowDepth,
    /// How much a Toward or Away arrow widens, `LEAST_DEPTH` to `MOST_DEPTH`.
    /// Means nothing on a flat one.
    pub depth_strength: f64,
    /// **Widths set by hand** (2026-10-15): the shaft's half-width (at its
    /// middle; a Toward or Away shaft still tapers around it as the depth
    /// does, a flat one is an even rectangle) and the head's half-width (the
    /// wide base of the triangle) — fractions of the picture's longer side,
    /// at thickness 1, so the Thickness slider still scales them. None draws
    /// the depth's own widths.
    pub widths: Option<[f64; 2]>,
    /// Floor or Standing, for a Toward or Away arrow (step 8 of `pieces`).
    pub stance: ArrowStance,
    /// **A zoom mark** rather than an arrow: `(x1, y1)` to `(x2, y2)` is the
    /// inner frame, always the picture's own shape. Everything about pins,
    /// heads, dashes and depth means nothing on one; look and thickness do.
    pub zoom: Option<ZoomDir>,
    /// **The part of the picture that shows** where a zoom mark was laid —
    /// the film's frame on a photograph of another shape — as `[x1, y1, x2,
    /// y2]` fractions. The four arrows start from its corners, so none is cut
    /// off at the edge of what is seen. None is the whole picture.
    pub view: Option<[f64; 4]>,
}

impl Arrow {
    /// A straight one-headed arrow between two points, in today's look.
    pub fn straight(x1: f64, y1: f64, x2: f64, y2: f64) -> Arrow {
        Arrow {
            x1,
            y1,
            x2,
            y2,
            pins: Vec::new(),
            shape: ArrowShape::Smooth,
            heads: 1,
            dashed: false,
            look: ArrowLook::Light,
            thickness: 1.0,
            depth: ArrowDepth::Flat,
            depth_strength: USUAL_DEPTH,
            widths: None,
            stance: ArrowStance::Floor,
            zoom: None,
            view: None,
        }
    }

    /// **A zoom mark** dropped on the picture: the inner frame the picture's
    /// own shape, 60% of it, centred.
    pub fn zoom_mark(dir: ZoomDir) -> Arrow {
        let mut a = Arrow::straight(0.2, 0.2, 0.8, 0.8);
        a.heads = 0;
        a.zoom = Some(dir);
        a
    }

    /// An arrow through these pins (tail and head included: at least two
    /// points), in today's look.
    pub fn through(points: &[(f64, f64)]) -> Option<Arrow> {
        if points.len() < 2 {
            return None;
        }
        let (a, c) = (points[0], points[points.len() - 1]);
        let mut arrow = Arrow::straight(a.0, a.1, c.0, c.1);
        arrow.pins = points[1..points.len() - 1].to_vec();
        Some(arrow)
    }

    /// **An arrow as it was stored before pins**: tail, the one quadratic
    /// control point, head, and a head count. The control point becomes a pin
    /// at the curve's own middle, or no pin when it sits on the straight line.
    pub fn bent(x1: f64, y1: f64, bx: f64, by: f64, x2: f64, y2: f64, heads: u8) -> Arrow {
        let mut arrow = Arrow::straight(x1, y1, x2, y2);
        arrow.heads = heads.min(2);
        if let Some(pin) = pin_from_bend((x1, y1), (bx, by), (x2, y2)) {
            arrow.pins.push(pin);
        }
        arrow
    }

    /// **The one control point an older reader bends the shaft with**: the
    /// quadratic whose middle (t = ½) is the middle pin — or, for an even
    /// count, the point halfway between the two middle pins. The midpoint of
    /// tail and head for a straight arrow. Held inside the picture, as an
    /// older reader holds it anyway.
    pub fn bend(&self) -> (f64, f64) {
        let (a, c) = ((self.x1, self.y1), (self.x2, self.y2));
        let n = self.pins.len();
        if n == 0 {
            return ((a.0 + c.0) / 2.0, (a.1 + c.1) / 2.0);
        }
        let m = if n % 2 == 1 {
            self.pins[n / 2]
        } else {
            let (p, q) = (self.pins[n / 2 - 1], self.pins[n / 2]);
            ((p.0 + q.0) / 2.0, (p.1 + q.1) / 2.0)
        };
        (
            (2.0 * m.0 - (a.0 + c.0) / 2.0).clamp(0.0, 1.0),
            (2.0 * m.1 - (a.1 + c.1) / 2.0).clamp(0.0, 1.0),
        )
    }

    /// The same arrow, held inside the picture. A coordinate outside nought
    /// to one is a mark nobody can see.
    pub fn held(&self) -> Arrow {
        if self.zoom.is_some() {
            return self.held_zoom();
        }
        let hold = |v: f64| if v.is_finite() { v.clamp(0.0, 1.0) } else { 0.5 };
        Arrow {
            x1: hold(self.x1),
            y1: hold(self.y1),
            x2: hold(self.x2),
            y2: hold(self.y2),
            pins: self.pins.iter().take(MOST_PINS).map(|p| (hold(p.0), hold(p.1))).collect(),
            shape: self.shape,
            heads: self.heads.min(2),
            dashed: self.dashed,
            look: self.look,
            thickness: if self.thickness.is_finite() { self.thickness.clamp(THINNEST, THICKEST) } else { 1.0 },
            depth: self.depth,
            depth_strength: if self.depth_strength.is_finite() {
                self.depth_strength.clamp(LEAST_DEPTH, MOST_DEPTH)
            } else {
                USUAL_DEPTH
            },
            widths: self.widths.and_then(|w| {
                if w.iter().all(|v| v.is_finite()) {
                    Some(w.map(|v| v.clamp(LEAST_WIDTH, MOST_WIDTH)))
                } else {
                    None
                }
            }),
            stance: self.stance,
            zoom: None,
            view: None,
        }
    }

    /// A zoom mark held: the inner frame has the picture's shape (equal
    /// fractions across and down), `LEAST_ZOOM` to `MOST_ZOOM`, and sits
    /// wholly inside the picture.
    fn held_zoom(&self) -> Arrow {
        let fin = |v: f64| if v.is_finite() { v } else { 0.5 };
        let (xa, xb) = (fin(self.x1).min(fin(self.x2)), fin(self.x1).max(fin(self.x2)));
        let size = (xb - xa).clamp(LEAST_ZOOM, MOST_ZOOM);
        let x = xa.clamp(0.0, 1.0 - size);
        let y = fin(self.y1).min(fin(self.y2)).clamp(0.0, 1.0 - size);
        let mut a = Arrow::straight(x, y, x + size, y + size);
        a.heads = 0;
        a.look = self.look;
        a.thickness = if self.thickness.is_finite() { self.thickness.clamp(THINNEST, THICKEST) } else { 1.0 };
        a.zoom = self.zoom;
        a.view = self.view.and_then(|v| {
            if !v.iter().all(|x| x.is_finite()) {
                return None;
            }
            let (l, r) = (v[0].min(v[2]).clamp(0.0, 1.0), v[0].max(v[2]).clamp(0.0, 1.0));
            let (t, b) = (v[1].min(v[3]).clamp(0.0, 1.0), v[1].max(v[3]).clamp(0.0, 1.0));
            let whole = l < 0.0005 && t < 0.0005 && r > 0.9995 && b > 0.9995;
            if whole || r - l < 0.05 || b - t < 0.05 { None } else { Some([l, t, r, b]) }
        });
        a
    }

    /// Back to a straight arrow — Straighten on the arrow's bar.
    pub fn straightened(&self) -> Arrow {
        Arrow { pins: Vec::new(), ..self.clone() }
    }

    /// Tail, pins and head, in order.
    pub fn points(&self) -> Vec<(f64, f64)> {
        let mut out = vec![(self.x1, self.y1)];
        out.extend(self.pins.iter().copied());
        out.push((self.x2, self.y2));
        out
    }

    /// The stored line — see the module's own comment for its grammar.
    pub fn encode(arrows: &[Arrow]) -> String {
        arrows.iter().map(Arrow::encode_one).collect::<Vec<_>>().join(";")
    }

    fn encode_one(&self) -> String {
        if let Some(dir) = self.zoom {
            // Four numbers: an older reader needs six, so it drops the entry.
            let mut out = format!(
                "zoom:{},{:.4},{:.4},{:.4},{:.4}",
                dir.name(), self.x1, self.y1, self.x2, self.y2
            );
            if let Some([l, t, r, b]) = self.view {
                out.push_str(&format!(",view:{:.4}:{:.4}:{:.4}:{:.4}", l, t, r, b));
            }
            self.encode_look(&mut out);
            return out;
        }
        let (bx, by) = self.bend();
        let mut out = format!(
            "{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{}",
            self.x1, self.y1, bx, by, self.x2, self.y2, self.heads.min(2)
        );
        // Pins only when the seven numbers would not bring them back — so an
        // arrow drawn before pins keeps exactly the line it was stored as.
        let rounded = |v: f64| (v * 10_000.0).round() / 10_000.0;
        let from_bend = pin_from_bend(
            (rounded(self.x1), rounded(self.y1)),
            (rounded(bx), rounded(by)),
            (rounded(self.x2), rounded(self.y2)),
        );
        let recovered = match (self.pins.len(), from_bend) {
            (0, None) => true,
            (1, Some(p)) => (p.0 - self.pins[0].0).abs() < 0.0005 && (p.1 - self.pins[0].1).abs() < 0.0005,
            _ => false,
        };
        if !recovered {
            for p in &self.pins {
                out.push_str(&format!(",p{:.4}:{:.4}", p.0, p.1));
            }
        }
        if self.shape == ArrowShape::Corner {
            out.push_str(",corner");
        }
        if self.dashed {
            out.push_str(",dashed");
        }
        self.encode_look(&mut out);
        if self.depth != ArrowDepth::Flat {
            out.push_str(&format!(",depth:{}", self.depth.name()));
            let s = (self.depth_strength * 100.0).round() / 100.0;
            if (s - USUAL_DEPTH).abs() >= 0.005 {
                out.push_str(&format!(":{:.2}", s));
            }
            if self.stance == ArrowStance::Standing {
                out.push_str(",stance:standing");
            }
        }
        if let Some([s, h]) = self.widths {
            out.push_str(&format!(",widths:{:.4}:{:.4}", s, h));
        }
        out
    }

    /// The look and the thickness, the two things a zoom mark shares.
    fn encode_look(&self, out: &mut String) {
        if self.look != ArrowLook::Light {
            out.push_str(&format!(",look:{}", self.look.name()));
        }
        let t = (self.thickness * 100.0).round() / 100.0;
        let near = |v: f64| (t - v).abs() < 0.005;
        if near(0.7) {
            out.push_str(",w:S");
        } else if near(1.4) {
            out.push_str(",w:L");
        } else if !near(1.0) {
            // The nearest old weight first, for a reader from before thickness.
            if t < 0.85 {
                out.push_str(",w:S");
            } else if t > 1.2 {
                out.push_str(",w:L");
            }
            out.push_str(&format!(",thick:{:.2}", t));
        }
    }

    /// How wide the arrow is drawn at its tail and at its tip, as multiples
    /// of a flat one: `(1, 1)` flat; Toward `(far, near)`, Away `(near,
    /// far)`, where near = 1 + 1.2·s and far = 1 / (1 + 2.4·s).
    pub fn depth_ends(&self) -> (f64, f64) {
        let s = self.depth_strength.clamp(LEAST_DEPTH, MOST_DEPTH);
        let near = 1.0 + 1.2 * s;
        let far = 1.0 / (1.0 + 2.4 * s);
        match self.depth {
            ArrowDepth::Flat => (1.0, 1.0),
            ArrowDepth::Toward => (far, near),
            ArrowDepth::Away => (near, far),
        }
    }

    /// The other direction, forgivingly. An arrow that does not parse is
    /// dropped and the rest are kept; six numbers without a head count is
    /// read as the ordinary one-headed arrow; a token this version does not
    /// know is ignored.
    pub fn parse(line: &str) -> Vec<Arrow> {
        line.split(';')
            .filter(|piece| !piece.trim().is_empty())
            .filter_map(Arrow::parse_one)
            .collect()
    }

    fn parse_one(piece: &str) -> Option<Arrow> {
        let mut n: Vec<f64> = Vec::new();
        let mut pins: Vec<(f64, f64)> = Vec::new();
        let mut shape = ArrowShape::Smooth;
        let mut dashed = false;
        let mut look = ArrowLook::Light;
        let mut weight: Option<f64> = None;
        let mut thick: Option<f64> = None;
        let mut depth = ArrowDepth::Flat;
        let mut depth_strength = USUAL_DEPTH;
        let mut widths: Option<[f64; 2]> = None;
        let mut zoom: Option<ZoomDir> = None;
        let mut stance = ArrowStance::Floor;
        let mut view: Option<[f64; 4]> = None;
        for token in piece.split(',').map(str::trim) {
            if let Ok(v) = token.parse::<f64>() {
                n.push(v);
                continue;
            }
            if let Some(rest) = token.strip_prefix('p') {
                if let Some((x, y)) = rest.split_once(':') {
                    if let (Ok(x), Ok(y)) = (x.trim().parse::<f64>(), y.trim().parse::<f64>()) {
                        if x.is_finite() && y.is_finite() {
                            pins.push((x, y));
                        }
                    }
                }
                continue;
            }
            match token {
                "corner" => shape = ArrowShape::Corner,
                "smooth" => shape = ArrowShape::Smooth,
                "dashed" => dashed = true,
                _ => {
                    if let Some(said) = token.strip_prefix("view:") {
                        let v: Vec<f64> = said.split(':').filter_map(|x| x.trim().parse::<f64>().ok()).collect();
                        if v.len() == 4 {
                            view = Some([v[0], v[1], v[2], v[3]]);
                        }
                    } else if let Some(said) = token.strip_prefix("zoom:") {
                        zoom = ZoomDir::read(said).or(zoom);
                    } else if let Some(said) = token.strip_prefix("look:") {
                        look = ArrowLook::read(said).unwrap_or(look);
                    } else if let Some(said) = token.strip_prefix("w:") {
                        weight = ArrowWeight::read(said).map(ArrowWeight::factor).or(weight);
                    } else if let Some(said) = token.strip_prefix("thick:") {
                        thick = said.trim().parse::<f64>().ok().filter(|v| v.is_finite()).or(thick);
                    } else if let Some(said) = token.strip_prefix("widths:") {
                        let v: Vec<f64> = said.split(':').filter_map(|x| x.trim().parse::<f64>().ok()).collect();
                        if v.iter().all(|x| x.is_finite()) {
                            match v.len() {
                                2 => widths = Some([v[0], v[1]]),
                                // The first build: tail, middle, head.
                                3 => widths = Some([v[1], v[2]]),
                                _ => {}
                            }
                        }
                    } else if let Some(said) = token.strip_prefix("stance:") {
                        stance = ArrowStance::read(said).unwrap_or(stance);
                    } else if let Some(said) = token.strip_prefix("depth:") {
                        let (kind, strength) = match said.split_once(':') {
                            Some((k, s)) => (k, s.trim().parse::<f64>().ok().filter(|v| v.is_finite())),
                            None => (said, None),
                        };
                        if let Some(d) = ArrowDepth::read(kind) {
                            depth = d;
                            depth_strength = strength.unwrap_or(USUAL_DEPTH);
                        }
                    }
                }
            }
        }
        if let Some(dir) = zoom {
            if n.len() < 4 || n.iter().take(4).any(|v| !v.is_finite()) {
                return None;
            }
            let mut mark = Arrow::zoom_mark(dir);
            mark.x1 = n[0];
            mark.y1 = n[1];
            mark.x2 = n[2];
            mark.y2 = n[3];
            mark.look = look;
            mark.thickness = thick.or(weight).unwrap_or(1.0);
            mark.view = view;
            return Some(mark.held());
        }
        if n.len() < 6 || n.iter().take(7).any(|v| !v.is_finite()) {
            return None;
        }
        let heads = if n.len() > 6 {
            if n[6] >= 2.0 {
                2
            } else if n[6] < 0.5 {
                0
            } else {
                1
            }
        } else {
            1
        };
        let mut arrow = if pins.is_empty() {
            Arrow::bent(n[0], n[1], n[2], n[3], n[4], n[5], heads)
        } else {
            let mut a = Arrow::straight(n[0], n[1], n[4], n[5]);
            a.heads = heads;
            a.pins = pins;
            a
        };
        arrow.shape = shape;
        arrow.dashed = dashed;
        arrow.look = look;
        arrow.thickness = thick.or(weight).unwrap_or(1.0);
        arrow.depth = depth;
        arrow.depth_strength = depth_strength;
        arrow.widths = widths;
        arrow.stance = stance;
        Some(arrow.held())
    }
}

/// The pin an old control point stands for: the quadratic's own middle,
/// `(a + 2b + c) / 4` — or none when the control point sits on the straight
/// line from tail to head (within a thousandth of the picture).
fn pin_from_bend(a: (f64, f64), b: (f64, f64), c: (f64, f64)) -> Option<(f64, f64)> {
    let (dx, dy) = (c.0 - a.0, c.1 - a.1);
    let len = dx.hypot(dy);
    let off = if len < 1e-9 {
        (b.0 - a.0).hypot(b.1 - a.1)
    } else {
        ((b.0 - a.0) * dy - (b.1 - a.1) * dx).abs() / len
    };
    if off < 0.001 {
        return None;
    }
    Some(((a.0 + 2.0 * b.0 + c.0) / 4.0, (a.1 + 2.0 * b.1 + c.1) / 4.0))
}

impl Arrow {
    /// **The arrow as closed outlines**, in the pixels of a picture `w` by
    /// `h` — the shapes an exported page draws, each one an SVG polygon
    /// filled with `look.fill()` and outlined in `look.line()` at
    /// `stroke(w, h)`, round joins. A solid arrow is one outline; a dashed one
    /// is one per dash, then its heads.
    ///
    /// **This is the arithmetic the Mac and the phone draw with
    /// (`studio/Sources/Arrows.swift`, `phone/Sources/Arrows.swift`),
    /// deliberately.** Several runtimes draw these and none can call the
    /// others on a per-frame budget, so it is written out here exactly, in
    /// the order to do it. **If one changes the others have to.**
    ///
    /// ```text
    /// A = (x1·w, y1·h), C = (x2·w, y2·h), each pin Pk = (px·w, py·h)
    /// P = [A, P1 … Pn, C]
    ///
    /// 1. The centre line, `points` (see `centre_line`):
    ///    · n = 0, or shape corner — for each segment i (P[i] → P[i+1]),
    ///      for k in 0 ..< 24 push P[i] + (P[i+1] − P[i])·k/24; then push C.
    ///    · smooth, n = 1 — the quadratic through the pin at its middle:
    ///      Q = 2·P1 − (A + C)/2; for i in 0 ... 40, t = i/40, push
    ///      (1−t)²·A + 2(1−t)t·Q + t²·C.  (Exactly the pre-pin arrow.)
    ///    · smooth, n ≥ 2 — uniform Catmull-Rom: for each segment
    ///      i in 0 ..< n+1, p0 = P[max(i−1, 0)], p1 = P[i], p2 = P[i+1],
    ///      p3 = P[min(i+2, n+1)]; for k in 0 ..< 24, t = k/24, push
    ///      ½·(2p1 + (−p0+p2)t + (2p0−5p1+4p2−p3)t² + (−p0+3p1−3p2+p3)t³);
    ///      then push C.
    ///    lengths[0] = 0, lengths[i] = lengths[i−1] + |points[i] − points[i−1]|;
    ///    total = the last length. total ≤ 1 → nothing is drawn.
    ///
    /// 2. Sizes. f = thickness (S 0.7, M 1, L 1.4; 0.5 to 3);
    ///    size = min(total, 0.75·max(w, h));
    ///    head_length = min(size·0.17·f, total·0.45)
    ///    head_half = head_length·0.62;  neck_half = head_half·0.62
    ///    tail_half = (heads = 1 and solid) ? head_half·0.30 : neck_half
    ///    stroke = max(size·0.020·f, 0.7)
    ///    **Steps 2 to 5 are a flat arrow with no hand-set widths** — every
    ///    arrow drawn before 2026-10-14's depth, unchanged. A flat arrow
    ///    whose widths were set by hand is step 6; a deep one (Toward, Away)
    ///    is step 8, a solid slab in perspective (`arrow/solid.rs`), since
    ///    2026-10-15 afternoon. Step 6's deep widths are kept only because an
    ///    older build still draws them.
    ///
    /// 3. starts_at = (heads = 2) ? head_length : 0
    ///    ends_at   = (heads ≥ 1) ? total − head_length : total
    ///    If ends_at ≤ starts_at: draw `head_only` (a lone triangle) and stop.
    ///    step(d) = the first i with lengths[i] ≥ d, but at least 1; the last
    ///    index when none is. first = step(starts_at), last = step(ends_at).
    ///    normal(i): before = points[max(i−1, 0)], after = points[min(i+1, end)],
    ///      (dx, dy) = after − before, len = max(|(dx, dy)|, 0.0001),
    ///      normal = (−dy/len, dx/len).
    ///    half(i) = neck_half when first = last, else
    ///      tail_half + (neck_half − tail_half)·clamp((lengths[i] − starts_at)
    ///      / max(ends_at − starts_at, 0.0001), 0, 1).
    ///    neck = points[last], tip = points[end], n_out = normal(last);
    ///    tail = points[first], n_in = normal(first).
    ///
    /// 4. Solid — one polygon:
    ///    points[i] + normal(i)·half(i) for i = first … last;
    ///    if heads ≥ 1: neck + n_out·head_half, tip, neck − n_out·head_half;
    ///    points[i] − normal(i)·half(i) for i = last … first (backwards);
    ///    if heads = 2: tail − n_in·head_half, points[0], tail + n_in·head_half.
    ///
    /// 5. Dashed — the shaft is thinner than a solid one and constant:
    ///    dash_half = neck_half·0.60, width = 2·dash_half.
    ///    The run is from = (heads = 2) ? lengths[first] : 0 to
    ///      to = (heads ≥ 1) ? lengths[last] : total — tail and neck, where
    ///      the heads' bases sit.
    ///    The rhythm (`dash_rhythm`): run = to − from;
    ///      dash = width·3, gap = width·1.6;
    ///      count = max(round((run + gap) / (dash + gap)), 1);
    ///      k = run / (count·dash + (count − 1)·gap); dash ·= k, gap ·= k
    ///      — so the first dash starts at the tail and the last ends at the
    ///      head's base.
    ///    d = from; while d < to − 0.01: e = min(d + dash, to);
    ///      if e − d > 0.01, one polygon: the centre positions are at(d), then
    ///      every points[i] with d < lengths[i] < e (using normal(i)), then
    ///      at(e); left side p + n·dash_half forwards, right side
    ///      p − n·dash_half backwards. d = e + gap.
    ///    at(s): i = the first index ≥ 1 with lengths[i] ≥ s (the last when
    ///      none is); u = clamp((s − lengths[i−1]) / max(lengths[i] −
    ///      lengths[i−1], 0.0001), 0, 1); p = points[i−1] + (points[i] −
    ///      points[i−1])·u; n = the unit perpendicular (−dy, dx)/len of
    ///      points[i] − points[i−1] (len floored at 0.0001).
    ///    Then the heads as separate triangles: if heads ≥ 1,
    ///    [neck + n_out·head_half, tip, neck − n_out·head_half]; if heads = 2,
    ///    [tail − n_in·head_half, points[0], tail + n_in·head_half].
    ///
    /// 6. **Deep or hand-set: the arrow laid flat on the ground** (2026-10-15).
    ///    The storyboard way (Mark Simon): a Toward or Away arrow shows the
    ///    move along the camera by its width changing along its length —
    ///    Toward narrow at the tail and wide at the head, Away the reverse.
    ///    The length never squashes the width: a short one is just a short
    ///    arrow that widens (or narrows) tail to head, drawn as if it were
    ///    never under 0.10·B long so it cannot become a sliver.
    ///    B = max(w, h); size = min(total, 0.75·B); lie = max(size, 0.10·B);
    ///    Four widths (wt, wm, we, wh) = `laid_widths`: the shaft's half-width
    ///      at the tail, in the middle and where it meets the head, and the
    ///      head's half-width (the shaft's at the end when heads = 0):
    ///      · deep, not hand-set: base = lie·0.17·f; (m0, m1) =
    ///        `depth_ends()`; head(m) = m when m ≥ 1, else (1 + m)/2;
    ///        wt = base·0.3844·m0; wh = heads ≥ 1 ? base·0.62·head(m1) : base·
    ///        0.3844·m1; we = heads ≥ 1 ? 0.62·wh : wh; wm = (wt + we)/2.
    ///      · hand-set [s, hd]: shaft = s·B·f, head = hd·B·f. Flat:
    ///        wt = wm = we = shaft (an even rectangle), wh = head. Deep: the
    ///        depth's own shaft shape scaled to the shaft width: wm = shaft,
    ///        wt = shaft·wt/wm, we = shaft·we/wm (the not-hand-set values).
    ///      back_half (the tail head, heads = 2) = wt / 0.62, hand-set:
    ///        head·(wt/0.62)/wh of the not-hand-set values.
    ///      (Flat with no hand-set widths is steps 2–5, not this.) All
    ///      floored at 0.25.
    ///    tip_half = wh; back_half as above;
    ///    tip_length = (heads ≥ 1) ? tip_half / 0.62 : 0;
    ///    back_length = (heads = 2) ? back_half / 0.62 : 0;
    ///    when tip_length + back_length > 0.6·total both are scaled by
    ///      0.6·total / (tip_length + back_length).
    ///    starts_at = back_length; ends_at = total − tip_length;
    ///    mid = (starts_at + ends_at)/2.
    ///    W(d), the shaft's half-width at distance d: straight lines through
    ///      the knots (0, wt), (starts_at, wt), (mid, wm), (ends_at, we),
    ///      (total, we); every width floored at 0.25.
    ///    first, last, normal, neck, tip, tail as step 3; half(i) =
    ///      W(lengths[i]). Solid: step 4 with tip_half at the tip and
    ///      back_half at the tail.
    ///    Dashed: dash_half(d) = 0.6·W(d). Dashes grow with the width, so the
    ///      rhythm is laid in a stretched distance τ(d) = ∫₀ᵈ wm / W(s) ds,
    ///      knot to knot: a piece from (a, Wa) with slope k = (Wb − Wa)/(b − a)
    ///      adds wm·L/Wa when |k| < 1e-12, else (wm/k)·ln((Wa + k·L)/Wa), L
    ///      the part of the piece covered. Back again: in a piece, τ-offset t
    ///      is a + t·Wa/wm, or a + Wa·(e^(k·t/wm) − 1)/k; past the last knot,
    ///      total + t·we/wm. dash, gap = dash_rhythm(τ(to) − τ(from),
    ///      0.6·wm); then step 5's loop in τ: t = τ(from); u = min(t + dash,
    ///      τ(to)); d = d(t); e = (u ≥ τ(to)) ? to : d(u); sides p ± n·
    ///      dash_half(s); t = u + gap. Heads as triangles, as step 5.
    ///    stroke = max(size·0.020·f, 0.7).
    /// ```
    pub fn pieces(&self, w: f64, h: f64) -> Vec<Vec<(f64, f64)>> {
        if let Some(zoom) = self.zoom_shapes(w, h) {
            return zoom.arrows;
        }
        let (points, lengths) = centre_line(self, w, h);
        let total = *lengths.last().unwrap_or(&0.0);
        if total <= 1.0 || points.len() < 2 {
            return Vec::new();
        }
        if self.depth != ArrowDepth::Flat {
            return self.solid_faces(&points, &lengths, w, h).into_iter().map(|f| f.points).collect();
        }
        if self.widths.is_some() {
            return self.laid_pieces(&points, &lengths, w, h);
        }
        let f = self.thickness;
        let size = total.min(0.75 * w.max(h));
        let head_length = (size * 0.17 * f).min(total * 0.45);
        let head_half = head_length * 0.62;
        let neck_half = head_half * 0.62;
        let tail_half = if self.heads == 1 && !self.dashed { head_half * 0.30 } else { neck_half };

        let end = points.len() - 1;
        let step = |distance: f64| -> usize {
            for (i, len) in lengths.iter().enumerate() {
                if *len >= distance {
                    return i.max(1);
                }
            }
            end
        };
        let starts_at = if self.heads >= 2 { head_length } else { 0.0 };
        let ends_at = if self.heads >= 1 { total - head_length } else { total };
        if ends_at <= starts_at {
            return vec![head_only(&points, head_half)];
        }
        let first = step(starts_at);
        let last = step(ends_at);
        let half = |i: usize| -> f64 {
            if first == last {
                return neck_half;
            }
            let along = (lengths[i] - starts_at) / (ends_at - starts_at).max(0.0001);
            tail_half + (neck_half - tail_half) * along.clamp(0.0, 1.0)
        };
        let (head_at_tip, head_at_tail) = heads_at(&points, first, last, head_half, head_half);

        if !self.dashed {
            return vec![solid_outline(self.heads, &points, first, last, &half, &head_at_tip, &head_at_tail)];
        }
        let dash_half = neck_half * 0.60;
        let from = if self.heads >= 2 { lengths[first] } else { 0.0 };
        let to = if self.heads >= 1 { lengths[last] } else { total };
        let (dash, gap) = dash_rhythm(to - from, dash_half);
        let mut out: Vec<Vec<(f64, f64)>> = Vec::new();
        let mut d = from;
        while d < to - 0.01 && dash > 0.0 {
            let e = (d + dash).min(to);
            if e - d > 0.01 {
                out.push(dash_piece(&points, &lengths, d, e, &|_| dash_half));
            }
            d = e + gap;
        }
        if self.heads >= 1 {
            out.push(head_at_tip);
        }
        if self.heads >= 2 {
            out.push(head_at_tail);
        }
        out
    }

    /// **The two widths the handles set** — the shaft's half-width (at its
    /// middle) and the head's half-width, in the picture's pixels (`w` ×
    /// `h`): the hand-set ones, else the depth's. Where the Mac's two handles
    /// start. Step 6 of `pieces`.
    pub fn widths_px(&self, w: f64, h: f64) -> [f64; 2] {
        if self.depth != ArrowDepth::Flat {
            let (_, lengths) = centre_line(self, w, h);
            return self.solid_widths_px(lengths.last().copied().unwrap_or(0.0), w, h);
        }
        let laid = self.default_laid(w, h);
        let big = w.max(h);
        match self.widths {
            Some([s, hd]) => [s * big * self.thickness, hd * big * self.thickness],
            None => [laid[1], laid[3]],
        }
    }

    /// The depth's own `[wt, wm, we, wh]` (step 6), before any hand-set widths.
    fn default_laid(&self, w: f64, h: f64) -> [f64; 4] {
        let (_, lengths) = centre_line(self, w, h);
        let total = lengths.last().copied().unwrap_or(0.0);
        let big = w.max(h);
        let f = self.thickness;
        let size = total.min(0.75 * big);
        if self.depth == ArrowDepth::Flat {
            let head_length = (size * 0.17 * f).min(total * 0.45);
            let head_half = head_length * 0.62;
            let neck_half = head_half * 0.62;
            let tail_half = if self.heads == 1 && !self.dashed { head_half * 0.30 } else { neck_half };
            let wh = if self.heads >= 1 { head_half } else { neck_half };
            return [tail_half, (tail_half + neck_half) / 2.0, neck_half, wh];
        }
        let lie = size.max(0.10 * big);
        let base = lie * 0.17 * f;
        let (m0, m1) = self.depth_ends();
        let head = |m: f64| if m >= 1.0 { m } else { (1.0 + m) / 2.0 };
        let wt = base * 0.3844 * m0;
        let wh = if self.heads >= 1 { base * 0.62 * head(m1) } else { base * 0.3844 * m1 };
        let we = if self.heads >= 1 { 0.62 * wh } else { wh };
        [wt, (wt + we) / 2.0, we, wh]
    }

    /// Step 6's `[wt, wm, we, wh, back_half]`, floored at 0.25.
    fn laid_widths(&self, w: f64, h: f64) -> [f64; 5] {
        let d = self.default_laid(w, h);
        let floor = |v: f64| v.max(0.25);
        let Some(_) = self.widths else {
            return [floor(d[0]), floor(d[1]), floor(d[2]), floor(d[3]), floor(d[0]) / 0.62];
        };
        let [shaft, head] = self.widths_px(w, h);
        let flat = self.depth == ArrowDepth::Flat;
        let (wt, we) = if flat {
            // A shaft wider than the head's neck narrows evenly into it, so
            // the head keeps its shoulders.
            (shaft, if self.heads >= 1 { shaft.min(0.62 * head) } else { shaft })
        } else {
            let wm0 = d[1].max(1e-9);
            (shaft * d[0] / wm0, shaft * d[2] / wm0)
        };
        let back = head * (d[0] / 0.62) / d[3].max(1e-9);
        let back = if flat { head } else { back };
        let wm = if flat && we < wt { (wt + we) / 2.0 } else { shaft };
        [floor(wt), floor(wm), floor(we), floor(head), floor(back)]
    }

    /// Step 6 of `pieces`: a deep arrow, or one with hand-set widths.
    fn laid_pieces(&self, points: &[(f64, f64)], lengths: &[f64], w: f64, h: f64) -> Vec<Vec<(f64, f64)>> {
        let total = *lengths.last().unwrap_or(&0.0);
        let [wt, wm, we, wh, back_half] = self.laid_widths(w, h);
        let tip_half = wh;
        let mut tip_length = if self.heads >= 1 { tip_half / 0.62 } else { 0.0 };
        let mut back_length = if self.heads >= 2 { back_half / 0.62 } else { 0.0 };
        let room = 0.6 * total;
        if tip_length + back_length > room {
            let k = room / (tip_length + back_length);
            tip_length *= k;
            back_length *= k;
        }
        let starts_at = back_length;
        let ends_at = total - tip_length;
        if ends_at <= starts_at {
            return vec![head_only(points, tip_half)];
        }
        let mid = (starts_at + ends_at) / 2.0;
        let knots = [(0.0, wt), (starts_at, wt), (mid, wm), (ends_at, we), (total, we)];
        let width = |d: f64| knot_width(&knots, d);

        let end = points.len() - 1;
        let step = |distance: f64| -> usize {
            for (i, len) in lengths.iter().enumerate() {
                if *len >= distance {
                    return i.max(1);
                }
            }
            end
        };
        let first = step(starts_at);
        let last = step(ends_at);
        let half = |i: usize| width(lengths[i]);
        let (head_at_tip, head_at_tail) = heads_at(points, first, last, tip_half, back_half);
        if !self.dashed {
            return vec![solid_outline(self.heads, points, first, last, &half, &head_at_tip, &head_at_tail)];
        }
        let from = if self.heads >= 2 { lengths[first] } else { 0.0 };
        let to = if self.heads >= 1 { lengths[last] } else { total };
        let (t_from, t_end) = (stretched(&knots, wm, from), stretched(&knots, wm, to));
        let (dash, gap) = dash_rhythm(t_end - t_from, 0.6 * wm);
        let mut out: Vec<Vec<(f64, f64)>> = Vec::new();
        let mut t = t_from;
        while t < t_end - 0.01 && dash > 0.0 {
            let u = (t + dash).min(t_end);
            let d = unstretched(&knots, wm, t);
            let e = if u >= t_end { to } else { unstretched(&knots, wm, u) };
            if e - d > 0.01 {
                out.push(dash_piece(points, lengths, d, e, &|s| 0.6 * width(s)));
            }
            t = u + gap;
        }
        if self.heads >= 1 {
            out.push(head_at_tip);
        }
        if self.heads >= 2 {
            out.push(head_at_tail);
        }
        out
    }

    /// **The solid arrow as one closed outline** — `pieces` for an arrow that
    /// is not dashed. Kept for the callers that drew one polygon per arrow.
    pub fn outline(&self, w: f64, h: f64) -> Vec<(f64, f64)> {
        let solid = Arrow { dashed: false, ..self.clone() };
        solid.pieces(w, h).into_iter().next().unwrap_or_default()
    }

    /// The outline's width in those same pixels — the whole reason the mark
    /// reads over a bright photograph as well as a dark one.
    pub fn stroke(&self, w: f64, h: f64) -> f64 {
        if self.zoom.is_some() {
            return self.zoom_stroke(w, h);
        }
        let (_, lengths) = centre_line(self, w, h);
        let total = lengths.last().copied().unwrap_or(0.0);
        let big = w.max(h);
        let size = total.min(0.75 * big);
        let pen = (size * 0.020 * self.thickness).max(0.7);
        if self.depth == ArrowDepth::Flat { pen } else { (pen * solid::SOLID_PEN).max(0.7) }
    }

    /// **The faces to draw, in order** — `pieces`, with which of them are side
    /// faces of a solid Toward or Away arrow (filled in `look.shade()`). A flat
    /// arrow has no side faces.
    pub fn faces(&self, w: f64, h: f64) -> Vec<Face> {
        if self.depth == ArrowDepth::Flat {
            return self.pieces(w, h).into_iter().map(|points| Face { points, side: false }).collect();
        }
        let (points, lengths) = centre_line(self, w, h);
        let total = *lengths.last().unwrap_or(&0.0);
        if total <= 1.0 || points.len() < 2 {
            return Vec::new();
        }
        self.solid_faces(&points, &lengths, w, h)
    }

    /// **Where the width handles sit**, in the pixels of a picture `w` by `h`:
    /// for the shaft (its middle) and, with a head, the head (its wide
    /// corner), the point on the centre line and the handle's own point. On a
    /// flat arrow the handle is `widths_px` out along the normal; on a solid
    /// one it is the projected corner (step 8).
    pub fn handle_spots(&self, w: f64, h: f64) -> Vec<[(f64, f64); 2]> {
        let (points, lengths) = centre_line(self, w, h);
        let total = *lengths.last().unwrap_or(&0.0);
        if total <= 1.0 || points.len() < 2 {
            return Vec::new();
        }
        if self.depth != ArrowDepth::Flat {
            return self.solid_handles(&points, &lengths, w, h);
        }
        Vec::new()
    }

    /// **Every piece as SVG**, filled and outlined in the arrow's look — what
    /// the printed page and the portal both lay over a picture. Empty for an
    /// arrow too short to draw.
    pub fn svg(&self, w: f64, h: f64) -> String {
        let stroke = self.stroke(w, h);
        let mut out = String::new();
        if let Some(zoom) = self.zoom_shapes(w, h) {
            // The frame is one path of two closed rectangles, filled
            // even-odd, so the band between them is the line and the outline
            // runs round both without a seam anywhere.
            let ring: Vec<String> = zoom
                .ring
                .iter()
                .map(|r| {
                    let pts: Vec<String> = r.iter().map(|(x, y)| format!("{:.1},{:.1}", x, y)).collect();
                    format!("M{}Z", pts.join("L"))
                })
                .collect();
            out.push_str(&format!(
                "<path d=\"{}\" fill-rule=\"evenodd\" fill=\"{}\" stroke=\"{}\" stroke-width=\"{:.2}\" stroke-linejoin=\"miter\"/>",
                ring.join(""),
                self.look.fill(),
                self.look.line(),
                stroke
            ));
        }
        for face in self.faces(w, h) {
            let piece = face.points;
            if piece.len() < 3 {
                continue;
            }
            let points: Vec<String> = piece.iter().map(|(x, y)| format!("{:.1},{:.1}", x, y)).collect();
            out.push_str(&format!(
                "<polygon points=\"{}\" fill=\"{}\" stroke=\"{}\" stroke-width=\"{:.2}\" stroke-linejoin=\"round\"/>",
                points.join(" "),
                if face.side { self.look.shade() } else { self.look.fill() },
                self.look.line(),
                stroke
            ));
        }
        out
    }
}

/// **A zoom mark as shapes**: the frame as two closed rectangles (outer and
/// inner edge of the band, drawn even-odd and outlined), and the four corner
/// arrows as ordinary polygons. All outlined at one `stroke`.
pub struct ZoomShapes {
    pub ring: [Vec<(f64, f64)>; 2],
    pub arrows: Vec<Vec<(f64, f64)>>,
    pub stroke: f64,
}

impl Arrow {
    /// The corner pairs of a zoom mark in pixels: outer corner (of `view`, else the
    /// picture) and the
    /// matching inner frame corner, top-left, top-right, bottom-right,
    /// bottom-left.
    fn zoom_corners(&self, w: f64, h: f64) -> [((f64, f64), (f64, f64)); 4] {
        let (x1, y1, x2, y2) = (self.x1 * w, self.y1 * h, self.x2 * w, self.y2 * h);
        let [l, t, r, b] = self.view.unwrap_or([0.0, 0.0, 1.0, 1.0]);
        let (l, t, r, b) = (l * w, t * h, r * w, b * h);
        [((l, t), (x1, y1)), ((r, t), (x2, y1)), ((r, b), (x2, y2)), ((l, b), (x1, y2))]
    }

    /// The outline width of a zoom mark: arrow arithmetic on the longest
    /// corner run, `max(min(run, 0.75·B)·0.020·f, 0.7)`.
    fn zoom_stroke(&self, w: f64, h: f64) -> f64 {
        let run = self
            .zoom_corners(w, h)
            .iter()
            .map(|(o, i)| (i.0 - o.0).hypot(i.1 - o.1))
            .fold(0.0, f64::max);
        (run.min(0.75 * w.max(h)) * 0.020 * self.thickness).max(0.7)
    }

    /// **The zoom mark, step 7 of `pieces`.** None unless this is a zoom mark.
    ///
    /// ```text
    /// s = zoom_stroke; band = 3.2·s (the frame line's width)
    /// R = (x1·w, y1·h) … (x2·w, y2·h)
    /// ring = [R grown by band/2 on every side, R shrunk by band/2],
    ///   each four corners clockwise from top-left
    /// for each corner pair (O the outer corner — of `view`, else of the picture — I the inner frame corner):
    ///   len = |I − O|; in = 0.10·len at the outer end, 0.10·len + 0.75·band
    ///   at the inner end; A, B = the two ends pulled in by those; then A is
    ///   held at least m = (Out ? hh : 0.30·hh) + s inside O across and down
    ///   (toward I), hh = 0.62·min(min(len, 0.75·max(w, h))·0.17·f, 0.45·len);
    ///   skip when |B − A| < 6·s; In: tail A, head B (inward). Out: tail B,
    ///   head A (outward). A straight one-headed arrow of the mark's
    ///   thickness (step 2 to 4), its one polygon.
    /// ```
    pub fn zoom_shapes(&self, w: f64, h: f64) -> Option<ZoomShapes> {
        let dir = self.zoom?;
        let stroke = self.zoom_stroke(w, h);
        let band = 3.2 * stroke;
        let (x1, y1, x2, y2) = (self.x1 * w, self.y1 * h, self.x2 * w, self.y2 * h);
        let rect = |g: f64| {
            let (a, b, c, d) = (x1 - g, y1 - g, x2 + g, y2 + g);
            let (c, d) = (c.max(a + 0.5), d.max(b + 0.5));
            vec![(a, b), (c, b), (c, d), (a, d)]
        };
        let ring = [rect(band / 2.0), rect(-band / 2.0)];
        let mut arrows = Vec::new();
        for (o, i) in self.zoom_corners(w, h) {
            let (dx, dy) = (i.0 - o.0, i.1 - o.1);
            let len = dx.hypot(dy);
            if len < 1.0 {
                continue;
            }
            let (ux, uy) = (dx / len, dy / len);
            let outer = 0.10 * len;
            let inner = 0.10 * len + 0.75 * band;
            let a = (o.0 + ux * outer, o.1 + uy * outer);
            // The outer end sits wholly inside what is seen: at least its own
            // half-width (the head's for Out, the tail's for In) and the pen
            // in from both edges.
            let size = len.min(0.75 * w.max(h));
            let head_half = 0.62 * (size * 0.17 * self.thickness).min(len * 0.45);
            let m = if dir == ZoomDir::Out { head_half } else { 0.30 * head_half } + stroke;
            let a = (
                if ux >= 0.0 { a.0.max(o.0 + m) } else { a.0.min(o.0 - m) },
                if uy >= 0.0 { a.1.max(o.1 + m) } else { a.1.min(o.1 - m) },
            );
            let b = (i.0 - ux * inner, i.1 - uy * inner);
            if (b.0 - a.0) * ux + (b.1 - a.1) * uy < 6.0 * stroke {
                continue;
            }
            let (tail, head) = if dir == ZoomDir::In { (a, b) } else { (b, a) };
            let mut arrow = Arrow::straight(tail.0 / w, tail.1 / h, head.0 / w, head.1 / h);
            arrow.thickness = self.thickness;
            if let Some(poly) = arrow.pieces(w, h).into_iter().next() {
                arrows.push(poly);
            }
        }
        Some(ZoomShapes { ring, arrows, stroke })
    }
}

/// The shaft's centre line, sampled, with the running length alongside —
/// step 1 of `pieces`.
fn centre_line(arrow: &Arrow, w: f64, h: f64) -> (Vec<(f64, f64)>, Vec<f64>) {
    let p: Vec<(f64, f64)> = arrow.points().iter().map(|(x, y)| (x * w, y * h)).collect();
    let n = p.len() - 2;
    let mut points: Vec<(f64, f64)> = Vec::new();
    if n == 0 || arrow.shape == ArrowShape::Corner {
        for i in 0..p.len() - 1 {
            for k in 0..24 {
                let t = k as f64 / 24.0;
                points.push((p[i].0 + (p[i + 1].0 - p[i].0) * t, p[i].1 + (p[i + 1].1 - p[i].1) * t));
            }
        }
        points.push(p[p.len() - 1]);
    } else if n == 1 {
        let (a, m, c) = (p[0], p[1], p[2]);
        let q = (2.0 * m.0 - (a.0 + c.0) / 2.0, 2.0 * m.1 - (a.1 + c.1) / 2.0);
        for i in 0..=40 {
            let t = i as f64 / 40.0;
            let u = 1.0 - t;
            points.push((
                u * u * a.0 + 2.0 * u * t * q.0 + t * t * c.0,
                u * u * a.1 + 2.0 * u * t * q.1 + t * t * c.1,
            ));
        }
    } else {
        let last = p.len() - 1;
        for i in 0..last {
            let p0 = p[i.saturating_sub(1)];
            let p1 = p[i];
            let p2 = p[i + 1];
            let p3 = p[(i + 2).min(last)];
            for k in 0..24 {
                let t = k as f64 / 24.0;
                let (t2, t3) = (t * t, t * t * t);
                let at = |a: f64, b: f64, c: f64, d: f64| {
                    0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)
                };
                points.push((at(p0.0, p1.0, p2.0, p3.0), at(p0.1, p1.1, p2.1, p3.1)));
            }
        }
        points.push(p[last]);
    }
    let mut lengths: Vec<f64> = vec![0.0];
    for i in 1..points.len() {
        let run = lengths[i - 1] + (points[i].0 - points[i - 1].0).hypot(points[i].1 - points[i - 1].1);
        lengths.push(run);
    }
    (points, lengths)
}

/// normal(i) of step 3: the unit perpendicular across the centre line.
fn normal_at(points: &[(f64, f64)], i: usize) -> (f64, f64) {
    let end = points.len() - 1;
    let before = points[i.saturating_sub(1)];
    let after = points[(i + 1).min(end)];
    let (dx, dy) = (after.0 - before.0, after.1 - before.1);
    let len = dx.hypot(dy).max(0.0001);
    (-dy / len, dx / len)
}

/// The head at the tip (`tip_half` either side of the neck) and the one at
/// the tail (`back_half`) — steps 4 and 5.
fn heads_at(points: &[(f64, f64)], first: usize, last: usize, tip_half: f64, back_half: f64) -> (Vec<(f64, f64)>, Vec<(f64, f64)>) {
    let end = points.len() - 1;
    let (n_in, n_out) = (normal_at(points, first), normal_at(points, last));
    let (tail, neck, tip) = (points[first], points[last], points[end]);
    (
        vec![
            (neck.0 + n_out.0 * tip_half, neck.1 + n_out.1 * tip_half),
            tip,
            (neck.0 - n_out.0 * tip_half, neck.1 - n_out.1 * tip_half),
        ],
        vec![
            (tail.0 - n_in.0 * back_half, tail.1 - n_in.1 * back_half),
            points[0],
            (tail.0 + n_in.0 * back_half, tail.1 + n_in.1 * back_half),
        ],
    )
}

/// Step 4: one polygon, shaft and heads.
fn solid_outline(
    heads: u8,
    points: &[(f64, f64)],
    first: usize,
    last: usize,
    half: &dyn Fn(usize) -> f64,
    head_at_tip: &[(f64, f64)],
    head_at_tail: &[(f64, f64)],
) -> Vec<(f64, f64)> {
    let mut out: Vec<(f64, f64)> = Vec::new();
    for i in first..=last {
        let n = normal_at(points, i);
        let d = half(i);
        out.push((points[i].0 + n.0 * d, points[i].1 + n.1 * d));
    }
    if heads >= 1 {
        out.extend(head_at_tip.iter().copied());
    }
    for i in (first..=last).rev() {
        let n = normal_at(points, i);
        let d = half(i);
        out.push((points[i].0 - n.0 * d, points[i].1 - n.1 * d));
    }
    if heads >= 2 {
        out.extend(head_at_tail.iter().copied());
    }
    out
}

/// One dash from distance `d` to `e`, `half(s)` either side of the centre —
/// step 5's polygon.
fn dash_piece(points: &[(f64, f64)], lengths: &[f64], d: f64, e: f64, half: &dyn Fn(f64) -> f64) -> Vec<(f64, f64)> {
    let end = points.len() - 1;
    let at = |s: f64| -> ((f64, f64), (f64, f64)) {
        let mut i = end;
        for (k, len) in lengths.iter().enumerate().skip(1) {
            if *len >= s {
                i = k;
                break;
            }
        }
        let (p, q) = (points[i - 1], points[i]);
        let run = (lengths[i] - lengths[i - 1]).max(0.0001);
        let u = ((s - lengths[i - 1]) / run).clamp(0.0, 1.0);
        let (dx, dy) = (q.0 - p.0, q.1 - p.1);
        let len = dx.hypot(dy).max(0.0001);
        ((p.0 + dx * u, p.1 + dy * u), (-dy / len, dx / len))
    };
    let mut centre: Vec<((f64, f64), (f64, f64), f64)> = Vec::new();
    let (p, n) = at(d);
    centre.push((p, n, d));
    for i in 0..points.len() {
        if lengths[i] > d && lengths[i] < e {
            centre.push((points[i], normal_at(points, i), lengths[i]));
        }
    }
    let (p, n) = at(e);
    centre.push((p, n, e));
    let mut poly: Vec<(f64, f64)> = centre
        .iter()
        .map(|(p, n, s)| {
            let k = half(*s);
            (p.0 + n.0 * k, p.1 + n.1 * k)
        })
        .collect();
    poly.extend(centre.iter().rev().map(|(p, n, s)| {
        let k = half(*s);
        (p.0 - n.0 * k, p.1 - n.1 * k)
    }));
    poly
}

/// W(d) of step 6: straight lines through the knots.
fn knot_width(knots: &[(f64, f64)], d: f64) -> f64 {
    if d <= knots[0].0 {
        return knots[0].1;
    }
    for pair in knots.windows(2) {
        let ((a, wa), (b, wb)) = (pair[0], pair[1]);
        if d <= b {
            if b - a <= 1e-9 {
                return wb;
            }
            return wa + (wb - wa) * (d - a) / (b - a);
        }
    }
    knots[knots.len() - 1].1
}

/// τ(d) of step 6: distance stretched so every dash is the same.
fn stretched(knots: &[(f64, f64)], wm: f64, d: f64) -> f64 {
    let mut t = 0.0;
    for pair in knots.windows(2) {
        let ((a, wa), (b, wb)) = (pair[0], pair[1]);
        if b - a <= 1e-9 {
            continue;
        }
        let l = (d.min(b) - a).max(0.0);
        if l <= 0.0 {
            break;
        }
        let k = (wb - wa) / (b - a);
        t += if k.abs() < 1e-12 { wm * l / wa } else { (wm / k) * ((wa + k * l) / wa).ln() };
    }
    let last = knots[knots.len() - 1];
    if d > last.0 {
        t += wm * (d - last.0) / last.1;
    }
    t
}

/// d(τ) of step 6: back from the stretched distance.
fn unstretched(knots: &[(f64, f64)], wm: f64, t: f64) -> f64 {
    let mut left = t;
    for pair in knots.windows(2) {
        let ((a, wa), (b, wb)) = (pair[0], pair[1]);
        if b - a <= 1e-9 {
            continue;
        }
        let k = (wb - wa) / (b - a);
        let whole = if k.abs() < 1e-12 { wm * (b - a) / wa } else { (wm / k) * (wb / wa).ln() };
        if left <= whole {
            return if k.abs() < 1e-12 { a + left * wa / wm } else { a + wa * ((k * left / wm).exp() - 1.0) / k };
        }
        left -= whole;
    }
    let last = knots[knots.len() - 1];
    last.0 + left * last.1 / wm
}

/// **The dash and the gap** for a dashed shaft `run` long whose dashes are
/// `dash_half` either side of the centre — step 5 of `pieces`. A dash is
/// three shaft-widths and a gap 1.6, then both are stretched or squeezed
/// alike so a whole number of dashes fills the run exactly: the first
/// starts at the tail, the last ends at the head.
fn dash_rhythm(run: f64, dash_half: f64) -> (f64, f64) {
    let width = 2.0 * dash_half;
    let (dash, gap) = (width * 3.0, width * 1.6);
    if run <= 0.0 || dash <= 0.0 {
        return (0.0, 0.0);
    }
    let count = ((run + gap) / (dash + gap)).round().max(1.0);
    let k = run / (count * dash + (count - 1.0) * gap);
    (dash * k, gap * k)
}

/// An arrow drawn so short it is all head.
fn head_only(points: &[(f64, f64)], half: f64) -> Vec<(f64, f64)> {
    let tip = points[points.len() - 1];
    let back = points[points.len().saturating_sub(6)];
    let (dx, dy) = (tip.0 - back.0, tip.1 - back.1);
    let len = dx.hypot(dy).max(0.0001);
    let n = (-dy / len, dx / len);
    vec![
        (back.0 + n.0 * half, back.1 + n.1 * half),
        tip,
        (back.0 - n.0 * half, back.1 - n.1 * half),
    ]
}
