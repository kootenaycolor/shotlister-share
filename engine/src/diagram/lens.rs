//! What a lens sees from above.
//!
//! A camera's cone on the plan is its **horizontal** angle of view: the width
//! of the sensor it is actually reading from, against the focal length — and,
//! behind an anamorphic, that width times the squeeze. That is the one number
//! that decides whether a wall is in the shot, so it is worked out rather than
//! drawn by eye — OpenShotDesigner does the same.
//!
//! **Which width** is his to say. His ruling, 2026-10-01: *"I can find out
//! the sensor size of any sensor I want … I can create a custom camera sensor
//! by typing in the millimeters, and then I can save it as a name and as a
//! preset … Every camera has different sensor modes, which equals 1,000
//! different variables you'd have to account for, and I don't need them
//! all."* So there is no table of cameras: each of the film's cameras keeps
//! the sensor he typed (`Doc::set_unit_sensor` — A-Cam reads 36.70 × 25.54),
//! and a camera with none is read as Super 35.

/// The generic sensors an older plan may name on a camera (`El::sensor`),
/// by the width read for a normal flat frame, in millimetres. Nothing offers
/// them any more; a plan that chose one keeps reading it until its camera
/// has a sensor of its own.
pub const SENSORS: [(&str, &str, f64); 7] = [
    ("s35", "Super 35", 24.89),
    ("ff", "Full Frame", 36.0),
    ("lf", "Large Format", 36.7),
    ("65", "65 mm", 54.12),
    ("s16", "Super 16", 12.52),
    ("mft", "Micro Four Thirds", 17.3),
    // A 2× anamorphic on a 4:3 Super 35 gate: 22 mm of glass-width, doubled.
    ("ana", "Anamorphic 2×", 44.0),
];

/// A sensor, or the part of it read: millimetres across and down (down is 0
/// for the generic ones, which only ever said their width).
#[derive(Clone, Debug, PartialEq)]
pub struct Gate {
    pub id: String,
    pub name: String,
    pub w: f64,
    pub h: f64,
}

fn generic(s: &(&str, &str, f64)) -> Gate {
    Gate { id: s.0.into(), name: s.1.into(), w: s.2, h: 0.0 }
}

/// A generic sensor by its key, else Super 35.
pub fn gate(sensor: &str) -> Gate {
    generic(SENSORS.iter().find(|s| s.0 == sensor).unwrap_or(&SENSORS[0]))
}

pub fn sensor_width(key: &str) -> f64 {
    gate(key).w
}

/// The full horizontal angle of view, in degrees, on a gate this many
/// millimetres wide, behind a lens squeezing this much (1 for spherical).
pub fn aov(focal_mm: f64, width_mm: f64, squeeze: f64) -> f64 {
    let f = focal_mm.clamp(4.0, 2000.0);
    let s = if squeeze >= 1.0 { squeeze } else { 1.0 };
    2.0 * (width_mm * s / (2.0 * f)).atan().to_degrees()
}

/// The full horizontal angle of view, in degrees, on a generic sensor.
pub fn angle_of_view(focal_mm: f64, sensor: &str) -> f64 {
    aov(focal_mm, sensor_width(sensor), 1.0)
}

/// Every number in a lens's name, with what sits either side of it: the
/// letter it is glued to (`T` of `T1.3`, `S` of `S4/i`, the `7` of `Tribe7`)
/// and what follows (`mm`, `x`, `-`).
fn numbers(text: &str) -> Vec<(f64, bool, String)> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_ascii_digit() {
            let glued = i > 0 && chars[i - 1].is_alphabetic();
            let start = i;
            while i < chars.len() && (chars[i].is_ascii_digit() || (chars[i] == '.' && i + 1 < chars.len() && chars[i + 1].is_ascii_digit())) {
                i += 1;
            }
            let digits: String = chars[start..i].iter().collect();
            let after: String = chars[i..].iter().take(3).collect::<String>().trim_start().to_lowercase();
            if let Ok(v) = digits.parse() {
                out.push((v, glued, after));
            }
        } else {
            i += 1;
        }
    }
    out
}

/// A focal length out of what a person typed in the Lens column: `50mm`,
/// `85`, `24-70mm` (the long end is not what the shot is on, so the first
/// number wins), `Ultra Prime 32`. A number that names something else is
/// passed over — a stop (`T1.3`), a series (`Cooke S4/i`, `Tribe7`), a squeeze
/// (`2x`) — so `Hawk V-Lite 2x 50mm` is a 50. `None` when there is no number.
pub fn focal_from_text(text: &str) -> Option<f64> {
    let ok = |v: f64| (4.0..=2000.0).contains(&v);
    let nums = numbers(text);
    let squeeze = |after: &str| after.starts_with('x') || after.starts_with('×');
    // Said in millimetres: the first such, or the start of its range.
    for (k, (v, _, after)) in nums.iter().enumerate() {
        if after.starts_with("mm") && ok(*v) {
            if k > 0 {
                let (p, glued, pafter) = &nums[k - 1];
                if !glued && pafter.starts_with('-') && ok(*p) {
                    return Some(*p);
                }
            }
            return Some(*v);
        }
    }
    nums.into_iter().find(|(v, glued, after)| !glued && !squeeze(after) && ok(*v)).map(|n| n.0)
}

/// A zoom's range, when its name says one: `24-70mm`, `Optimo 24–290`,
/// `Canon 18 - 80 T4.4`. The low end first. `None` for a prime.
pub fn zoom_from_text(text: &str) -> Option<(f64, f64)> {
    let ok = |v: f64| (4.0..=2000.0).contains(&v);
    let nums = numbers(text);
    nums.windows(2).find_map(|w| {
        let ((lo, glued, after), (hi, glued2, _)) = (&w[0], &w[1]);
        let joined = after.starts_with('-') || after.starts_with('–') || after.starts_with("to");
        (joined && !glued && !glued2 && ok(*lo) && ok(*hi) && hi > lo).then_some((*lo, *hi))
    })
}

/// An anamorphic's squeeze, when its name says so: `2x`, `1.8x`, `1.5×`.
pub fn squeeze_from_text(text: &str) -> Option<f64> {
    numbers(text)
        .into_iter()
        .find(|(v, _, after)| (after.starts_with('x') || after.starts_with('×')) && *v > 1.0 && *v <= 2.5)
        .map(|n| n.0)
}

/// How far a cone reaches when nobody has said: long lenses see far, wide ones
/// near, so the cone is drawn to where a person would stand in a frame.
pub fn default_reach(focal_mm: f64) -> f64 {
    (focal_mm / 10.0).clamp(1.8, 9.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fifty_on_super_35_sees_about_twenty_eight_degrees() {
        let a = angle_of_view(50.0, "s35");
        assert!((a - 28.0).abs() < 0.3, "{a}");
    }

    #[test]
    fn full_frame_sees_wider_than_super_35_on_the_same_lens() {
        assert!(angle_of_view(35.0, "ff") > angle_of_view(35.0, "s35"));
    }

    #[test]
    fn an_unknown_sensor_is_super_35() {
        assert_eq!(angle_of_view(50.0, "?"), angle_of_view(50.0, "s35"));
    }

    #[test]
    fn a_lens_is_read_the_way_it_is_typed() {
        assert_eq!(focal_from_text("50mm"), Some(50.0));
        assert_eq!(focal_from_text("85"), Some(85.0));
        assert_eq!(focal_from_text("24-70mm"), Some(24.0));
        assert_eq!(focal_from_text("Ultra Prime 32"), Some(32.0));
        assert_eq!(focal_from_text("12.5mm"), Some(12.5));
        assert_eq!(focal_from_text("Wide"), None);
        assert_eq!(focal_from_text(""), None);
        assert_eq!(focal_from_text("2"), None);
    }

    #[test]
    fn a_lens_name_with_other_numbers_in_it_still_reads_its_focal_length() {
        assert_eq!(focal_from_text("Tribe7 Blackwings 50"), Some(50.0));
        assert_eq!(focal_from_text("Cooke S4/i 25mm"), Some(25.0));
        assert_eq!(focal_from_text("Zeiss Superspeed T1.3 50"), Some(50.0));
        assert_eq!(focal_from_text("Hawk V-Lite 2x 50mm"), Some(50.0));
        assert_eq!(focal_from_text("Atlas Orion 40mm 2x"), Some(40.0));
        assert_eq!(focal_from_text("Ultra Prime 32 T1.9"), Some(32.0));
        assert_eq!(focal_from_text("24 - 70mm"), Some(24.0));
    }

    #[test]
    fn a_zoom_says_its_range_and_a_prime_says_none() {
        assert_eq!(zoom_from_text("24-70mm"), Some((24.0, 70.0)));
        assert_eq!(zoom_from_text("Angenieux Optimo 24–290"), Some((24.0, 290.0)));
        assert_eq!(zoom_from_text("Canon 18 - 80 T4.4"), Some((18.0, 80.0)));
        assert_eq!(zoom_from_text("Tribe7 Blackwings 50"), None);
        assert_eq!(zoom_from_text("Cooke S4/i 25mm"), None);
        assert_eq!(zoom_from_text("Hawk 2x 50mm"), None);
    }

    #[test]
    fn a_squeeze_is_read_off_the_lens_name() {
        assert_eq!(squeeze_from_text("Hawk V-Lite 2x 50mm"), Some(2.0));
        assert_eq!(squeeze_from_text("Cooke Anamorphic/i 1.8x 40"), Some(1.8));
        assert_eq!(squeeze_from_text("Ultra Prime 32"), None);
    }

    #[test]
    fn a_sensor_he_typed_is_read_at_his_numbers() {
        // A 50 on 36.70 mm: 2·atan(36.70 / 100) = 40.3°.
        assert!((aov(50.0, 36.70, 1.0) - 40.3).abs() < 0.05);
        // A 2× anamorphic on 23.76 mm: 2·atan(23.76·2 / 100) = 50.8°.
        assert!((aov(50.0, 23.76, 2.0) - 50.8).abs() < 0.05);
        assert_eq!(gate("ff").w, 36.0);
        assert_eq!(gate("").id, "s35");
    }
}
