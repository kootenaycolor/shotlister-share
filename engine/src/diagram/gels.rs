//! **Gels**, on a light or a frame (Scenario's built-in set, 2026-09-28):
//! colour correction (CTO, CTB), neutral density, green and magenta, and the
//! white diffusions. A piece carries them as a list of ids in `gels`, in the
//! order they were clipped on.
//!
//! What one does to the beam, and nothing more: a colour gel moves the
//! Kelvin the beam is tinted by (in mireds, the way gel makers state it); an
//! ND or a diffusion costs stops, which draw the beam fainter and shorter
//! (inverse square: a stop is the reach over √2); a diffusion also spreads
//! it. The numbers are Lee's published ones, rounded — a plan, not a meter.
//!
//! The Mac's Gels menu names the same list (`DiagramGels` in
//! `DiagramFrame.swift`); keep the two in step.

/// One gel: its id, its name on the plan, the mired shift (+ warms), what
/// it costs in stops, how far it pushes toward green (+) or magenta (−),
/// and how many degrees it spreads a beam.
pub struct Gel {
    pub id: &'static str,
    pub name: &'static str,
    pub mired: f64,
    pub stops: f64,
    pub green: f64,
    pub spread: f64,
}

const fn g(id: &'static str, name: &'static str, mired: f64, stops: f64, green: f64, spread: f64) -> Gel {
    Gel { id, name, mired, stops, green, spread }
}

pub const GELS: &[Gel] = &[
    g("cto-quarter", "¼ CTO", 64.0, 0.3, 0.0, 0.0),
    g("cto-half", "½ CTO", 109.0, 0.5, 0.0, 0.0),
    g("cto-3q", "¾ CTO", 131.0, 0.7, 0.0, 0.0),
    g("cto-full", "Full CTO", 159.0, 0.85, 0.0, 0.0),
    g("ctb-quarter", "¼ CTB", -35.0, 0.5, 0.0, 0.0),
    g("ctb-half", "½ CTB", -78.0, 0.9, 0.0, 0.0),
    g("ctb-full", "Full CTB", -137.0, 1.5, 0.0, 0.0),
    g("nd3", "ND .3", 0.0, 1.0, 0.0, 0.0),
    g("nd6", "ND .6", 0.0, 2.0, 0.0, 0.0),
    g("nd9", "ND .9", 0.0, 3.0, 0.0, 0.0),
    g("plus-green-quarter", "¼ Plus Green", 0.0, 0.15, 0.25, 0.0),
    g("plus-green-half", "½ Plus Green", 0.0, 0.3, 0.5, 0.0),
    g("minus-green-quarter", "¼ Minus Green", 0.0, 0.15, -0.25, 0.0),
    g("minus-green-half", "½ Minus Green", 0.0, 0.3, -0.5, 0.0),
    g("opal", "Opal", 0.0, 0.3, 0.0, 8.0),
    g("216", "216", 0.0, 1.5, 0.0, 40.0),
    g("250", "250", 0.0, 0.8, 0.0, 25.0),
    g("hampshire", "Hampshire", 0.0, 0.3, 0.0, 10.0),
];

pub fn find(id: &str) -> Option<&'static Gel> {
    GELS.iter().find(|g| g.id == id)
}

/// A gel's name on the plan; one we do not know is shown as it was stored.
pub fn name(id: &str) -> String {
    find(id).map(|g| g.name.to_string()).unwrap_or_else(|| id.to_string())
}

/// The most gels one piece holds, and the longest id kept — a slip, not a
/// real stack, past either.
pub const MOST: usize = 12;
pub const LONGEST: usize = 40;

/// Everything a stack of gels does, added up.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Sum {
    pub mired: f64,
    pub stops: f64,
    pub green: f64,
    pub spread: f64,
    /// Any colour gel at all — a lamp of unknown Kelvin is then read as
    /// tungsten, so a CTB on it still cools it.
    pub colours: bool,
}

pub fn sum(ids: &[String]) -> Sum {
    let mut s = Sum::default();
    for g in ids.iter().filter_map(|i| find(i)) {
        s.mired += g.mired;
        s.stops += g.stops;
        s.green += g.green;
        s.spread += g.spread;
        s.colours |= g.mired != 0.0 || g.green != 0.0;
    }
    s
}

impl Sum {
    pub fn add(self, o: Sum) -> Sum {
        Sum {
            mired: self.mired + o.mired,
            stops: self.stops + o.stops,
            green: self.green + o.green,
            spread: self.spread + o.spread,
            colours: self.colours || o.colours,
        }
    }

    /// The Kelvin a lamp of `k` reads through these. Unknown (0) stays
    /// unknown unless a colour gel asks for a number.
    pub fn kelvin(&self, k: f64) -> f64 {
        if self.mired == 0.0 {
            return k;
        }
        let base = if k > 0.0 { k } else { 3200.0 };
        let m = (1e6 / base + self.mired).max(50.0);
        (1e6 / m).clamp(1000.0, 20_000.0)
    }
}

/// How much fainter a beam is drawn for so many stops lost: visible at a
/// half stop, never quite gone.
pub fn faint(stops: f64) -> f64 {
    if !stops.is_finite() || stops <= 0.0 {
        return 1.0;
    }
    2f64.powf(-0.6 * stops).max(0.25)
}

/// How far a beam still reaches for so many stops lost: inverse square.
pub fn reach(r: f64, stops: f64) -> f64 {
    if !stops.is_finite() || stops <= 0.0 {
        return r;
    }
    r * 2f64.powf(-stops / 2.0)
}

/// A beam's tint pushed toward green or magenta.
pub fn tinted(hex: &str, green: f64) -> String {
    if green.abs() < 1e-9 {
        return hex.to_string();
    }
    let h = hex.trim_start_matches('#');
    if h.len() != 6 {
        return hex.to_string();
    }
    let v = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0) as f64;
    let to: (f64, f64, f64) = if green > 0.0 { (110.0, 215.0, 110.0) } else { (225.0, 120.0, 210.0) };
    let k = (green.abs() * 0.6).min(0.6);
    let mix = |a: f64, b: f64| (a + (b - a) * k).round().clamp(0.0, 255.0) as u8;
    format!("#{:02X}{:02X}{:02X}", mix(v(0), to.0), mix(v(2), to.1), mix(v(4), to.2))
}

/// The colour a gel shows as, clipped in a frame — its fill, over the cloth.
pub fn swatch(id: &str) -> Option<&'static str> {
    let g = find(id)?;
    Some(if g.mired > 0.0 {
        "#F2A444"
    } else if g.mired < 0.0 {
        "#5F8FDB"
    } else if g.green > 0.0 {
        "#6CC46C"
    } else if g.green < 0.0 {
        "#D46CC2"
    } else if g.spread > 0.0 {
        return None;
    } else {
        "#6E6E6E"
    })
}
