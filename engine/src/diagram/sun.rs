//! Where the sun is, for a place and a moment.
//!
//! OpenShotDesigner draws the sun across a plan; so does this. For a DP it is
//! the question a window, a courtyard or a car interior turns on: which way
//! does the light come in at 4 p.m. on the day we shoot? Also his row SL-59,
//! *"Sun position and overheads alongside the list"*.
//!
//! The arithmetic is NOAA's solar position approximation (the one their
//! spreadsheet uses) — within a fraction of a degree, which is well inside what
//! a plan drawn by hand can show.

/// Where the sun stands: `azimuth` clockwise from true north, `altitude` above
/// the horizon, both in degrees.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Sun {
    pub azimuth: f64,
    pub altitude: f64,
}

/// Days from the civil calendar date to 1970-01-01 (proleptic Gregorian).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// A daylight-saving rule the engine knows: North America's (second Sunday
/// of March to first Sunday of November) or Europe's (last Sunday of March to
/// last Sunday of October).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Dst {
    NorthAmerica,
    Europe,
}

/// Which rule a place keeps, when it is somewhere the engine knows one. Boxes,
/// not borders: Arizona and Saskatchewan, which keep the clock still all
/// year, are left out; anywhere else, the plan's own saved zone (`sun_tz`) is
/// the answer.
pub fn dst_rule(lat: f64, lon: f64) -> Option<Dst> {
    let inside = |la: (f64, f64), lo: (f64, f64)| lat >= la.0 && lat <= la.1 && lon >= lo.0 && lon <= lo.1;
    if inside((30.0, 72.0), (-170.0, -52.0)) && !inside((31.3, 37.0), (-114.8, -109.0)) && !inside((49.0, 60.0), (-110.0, -101.3)) {
        Some(Dst::NorthAmerica)
    } else if inside((36.0, 71.0), (-10.0, 28.5)) {
        Some(Dst::Europe)
    } else {
        None
    }
}

/// The day of the month of the `n`th Sunday (1-based; 0 for the last) of a month.
fn sunday(y: i64, m: i64, n: i64) -> i64 {
    // 1970-01-01 was a Thursday; 0 is Sunday.
    let weekday = |d: i64| (days_from_civil(y, m, d) + 4).rem_euclid(7);
    if n == 0 {
        let last = [31, if y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][(m - 1) as usize];
        last - weekday(last)
    } else {
        let first = 1 + (7 - weekday(1)) % 7;
        first + 7 * (n - 1)
    }
}

/// Whether a date falls in a rule's summer time.
pub fn in_dst(rule: Dst, y: i64, m: i64, d: i64) -> bool {
    let (from, to) = match rule {
        Dst::NorthAmerica => ((3, sunday(y, 3, 2)), (11, sunday(y, 11, 1))),
        Dst::Europe => ((3, sunday(y, 3, 0)), (10, sunday(y, 10, 0))),
    };
    (m, d) >= from && (m, d) < to
}

/// Today, for a clock that has no say in a plan's sun: native builds only
/// (the browser's builds are not told a zone either).
#[cfg(all(not(target_arch = "wasm32"), not(test)))]
pub fn today() -> Option<(i64, i64, i64)> {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok()?.as_secs() as i64;
    let z = secs.div_euclid(86_400) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    Some((yoe + era * 400 + (m <= 2) as i64, m, d))
}

#[cfg(target_arch = "wasm32")]
pub fn today() -> Option<(i64, i64, i64)> {
    None
}

/// Under test, always the day the checks were written, so a run in January
/// reads a plan's sun as one in October does.
#[cfg(test)]
pub fn today() -> Option<(i64, i64, i64)> {
    Some((2026, 10, 6))
}

/// **The zone to read the clock in on a given day**, minutes ahead of UTC
/// (Ref 1513). The shell's `shell` offset is its zone *today* — summer or
/// winter time as it is now — so for a day in the other half of the year it
/// is an hour out wherever a rule applies; this moves it by the difference
/// between today and that day. Told nothing, the place's own hour-wide zone,
/// summer time as the rule has it.
pub fn zone(lat: f64, lon: f64, date: (i64, i64, i64), shell: Option<f64>, today: Option<(i64, i64, i64)>) -> f64 {
    let standard = (lon / 15.0).round() * 60.0;
    let hour = |on: bool| if on { 60.0 } else { 0.0 };
    match (dst_rule(lat, lon), shell, today) {
        (Some(rule), Some(o), Some(t)) => o + hour(in_dst(rule, date.0, date.1, date.2)) - hour(in_dst(rule, t.0, t.1, t.2)),
        (None, Some(o), _) | (Some(_), Some(o), None) => o,
        (Some(rule), None, _) => standard + hour(in_dst(rule, date.0, date.1, date.2)),
        (None, None, _) => standard,
    }
}

/// The sun, at a latitude and longitude (degrees, east positive), on a date,
/// at a local clock time in minutes after midnight, in a zone `utc_offset`
/// minutes ahead of UTC.
pub fn position(lat: f64, lon: f64, year: i64, month: i64, day: i64, minutes: f64, utc_offset: f64) -> Sun {
    let utc_minutes = minutes - utc_offset;
    let jd = days_from_civil(year, month, day) as f64 + 2_440_587.5 + utc_minutes / 1440.0;
    let t = (jd - 2_451_545.0) / 36_525.0;

    let l0 = (280.46646 + t * (36_000.76983 + t * 0.000_303_2)).rem_euclid(360.0);
    let m = 357.52911 + t * (35_999.05029 - 0.000_153_7 * t);
    let e = 0.016_708_634 - t * (0.000_042_037 + 0.000_000_126_7 * t);
    let mr = m.to_radians();
    let c = mr.sin() * (1.914602 - t * (0.004817 + 0.000014 * t))
        + (2.0 * mr).sin() * (0.019993 - 0.000101 * t)
        + (3.0 * mr).sin() * 0.000289;
    let true_long = l0 + c;
    let omega = 125.04 - 1934.136 * t;
    let lambda = true_long - 0.00569 - 0.00478 * omega.to_radians().sin();
    let eps0 = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0;
    let eps = eps0 + 0.00256 * omega.to_radians().cos();
    let decl = (eps.to_radians().sin() * lambda.to_radians().sin()).asin();

    let y = (eps.to_radians() / 2.0).tan().powi(2);
    let l0r = l0.to_radians();
    let eq_time = 4.0
        * (y * (2.0 * l0r).sin() - 2.0 * e * mr.sin() + 4.0 * e * y * mr.sin() * (2.0 * l0r).cos()
            - 0.5 * y * y * (4.0 * l0r).sin()
            - 1.25 * e * e * (2.0 * mr).sin())
        .to_degrees();

    let true_solar = (utc_minutes + eq_time + 4.0 * lon).rem_euclid(1440.0);
    let hour_angle = if true_solar / 4.0 < 0.0 { true_solar / 4.0 + 180.0 } else { true_solar / 4.0 - 180.0 };
    let latr = lat.to_radians();
    let har = hour_angle.to_radians();
    let zenith = (latr.sin() * decl.sin() + latr.cos() * decl.cos() * har.cos()).clamp(-1.0, 1.0).acos();
    let altitude = 90.0 - zenith.to_degrees();
    let az = {
        let denom = latr.cos() * zenith.sin();
        if denom.abs() < 1e-9 {
            0.0
        } else {
            let cos_az = ((latr.sin() * zenith.cos()) - decl.sin()) / denom;
            let a = cos_az.clamp(-1.0, 1.0).acos().to_degrees();
            if hour_angle > 0.0 {
                (a + 180.0).rem_euclid(360.0)
            } else {
                (540.0 - a).rem_euclid(360.0)
            }
        }
    };
    Sun { azimuth: az, altitude }
}

/// The day's sun at a place, in minutes after local midnight: when it rises
/// and sets (its upper edge on the horizon, with the air's bending), its
/// highest, and the golden hour either end — when it stands 4° up. `None`
/// where it never does that on the day: the pole in summer, or in winter.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Day {
    pub rise: Option<f64>,
    pub set: Option<f64>,
    pub noon: f64,
    pub golden_morning: Option<f64>,
    pub golden_evening: Option<f64>,
}

pub fn day(lat: f64, lon: f64, year: i64, month: i64, date: i64, utc_offset: f64) -> Day {
    const HORIZON: f64 = -0.833;
    const GOLDEN: f64 = 4.0;
    let alt: Vec<f64> = (0..=1440).map(|m| position(lat, lon, year, month, date, m as f64, utc_offset).altitude).collect();
    // The minute a height is crossed, going up or coming down, to the second.
    let cross = |level: f64, rising: bool| -> Option<f64> {
        let found = (0..1440).find(|&m| if rising { alt[m] < level && alt[m + 1] >= level } else { alt[m] >= level && alt[m + 1] < level });
        let found = if rising { found } else { (0..1440).rev().find(|&m| alt[m] >= level && alt[m + 1] < level) };
        found.map(|m| m as f64 + (level - alt[m]) / (alt[m + 1] - alt[m]))
    };
    let noon = (0..=1440).max_by(|a, b| alt[*a].partial_cmp(&alt[*b]).unwrap()).unwrap_or(720) as f64;
    Day {
        rise: cross(HORIZON, true),
        set: cross(HORIZON, false),
        noon,
        golden_morning: cross(GOLDEN, true),
        golden_evening: cross(GOLDEN, false),
    }
}

/// `2026-09-27` → (2026, 9, 27).
pub fn parse_date(s: &str) -> Option<(i64, i64, i64)> {
    let mut parts = s.trim().split('-');
    let y = parts.next()?.parse().ok()?;
    let m: i64 = parts.next()?.parse().ok()?;
    let d: i64 = parts.next()?.parse().ok()?;
    ((1..=12).contains(&m) && (1..=31).contains(&d)).then_some((y, m, d))
}

/// `14:30` → 870 minutes.
pub fn parse_time(s: &str) -> Option<f64> {
    let (h, m) = s.trim().split_once(':')?;
    let h: f64 = h.parse().ok()?;
    let m: f64 = m.parse().ok()?;
    ((0.0..24.0).contains(&h) && (0.0..60.0).contains(&m)).then_some(h * 60.0 + m)
}

/// A clock time a scene's time of day suggests, when nobody has set one.
/// Night has no sun to draw.
pub fn time_for(time_of_day: &str) -> Option<f64> {
    let t = time_of_day.to_lowercase();
    if t.contains("night") {
        return None;
    }
    Some(if t.contains("dawn") || t.contains("sunrise") {
        6.5 * 60.0
    } else if t.contains("morning") {
        9.0 * 60.0
    } else if t.contains("afternoon") {
        15.5 * 60.0
    } else if t.contains("sunset") || t.contains("dusk") || t.contains("magic") || t.contains("golden") {
        18.5 * 60.0
    } else if t.contains("evening") {
        18.0 * 60.0
    } else {
        13.0 * 60.0
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noon_in_los_angeles_at_the_equinox_is_high_in_the_south() {
        // 2026-09-22, 13:00 PDT (UTC-7), Los Angeles.
        let s = position(34.05, -118.25, 2026, 9, 22, 13.0 * 60.0, -7.0 * 60.0);
        assert!(s.azimuth > 170.0 && s.azimuth < 200.0, "{s:?}");
        assert!(s.altitude > 50.0 && s.altitude < 60.0, "{s:?}");
    }

    #[test]
    fn morning_sun_is_in_the_east_and_evening_in_the_west() {
        let am = position(49.28, -123.12, 2026, 6, 21, 8.0 * 60.0, -7.0 * 60.0);
        let pm = position(49.28, -123.12, 2026, 6, 21, 19.0 * 60.0, -7.0 * 60.0);
        assert!(am.azimuth > 45.0 && am.azimuth < 120.0, "{am:?}");
        assert!(pm.azimuth > 250.0 && pm.azimuth < 320.0, "{pm:?}");
        assert!(am.altitude > 0.0 && pm.altitude > 0.0);
    }

    #[test]
    fn a_day_in_los_angeles_rises_peaks_and_sets_in_order() {
        // 2026-09-22 in Los Angeles: sunrise about 6:45, sunset about 6:55 pm.
        let d = day(34.05, -118.25, 2026, 9, 22, -7.0 * 60.0);
        let (rise, set) = (d.rise.unwrap(), d.set.unwrap());
        assert!((rise - (6.0 * 60.0 + 45.0)).abs() < 10.0, "rise {rise}");
        assert!((set - (18.0 * 60.0 + 55.0)).abs() < 10.0, "set {set}");
        assert!(rise < d.golden_morning.unwrap() && d.golden_morning.unwrap() < d.noon);
        assert!(d.noon < d.golden_evening.unwrap() && d.golden_evening.unwrap() < set);
    }

    #[test]
    fn the_pole_in_summer_has_no_sunset() {
        let d = day(80.0, 15.0, 2026, 6, 21, 60.0);
        assert!(d.rise.is_none() && d.set.is_none());
    }

    #[test]
    fn midnight_is_below_the_horizon() {
        let s = position(51.5, -0.12, 2026, 12, 21, 0.0, 0.0);
        assert!(s.altitude < 0.0);
    }

    #[test]
    fn dates_times_and_times_of_day_are_read() {
        assert_eq!(parse_date("2026-09-27"), Some((2026, 9, 27)));
        assert_eq!(parse_date("27/09/2026"), None);
        assert_eq!(parse_time("14:30"), Some(870.0));
        assert_eq!(parse_time("25:00"), None);
        assert_eq!(time_for("NIGHT"), None);
        assert_eq!(time_for("DAY"), Some(780.0));
        assert_eq!(time_for("Sunset"), Some(1110.0));
    }
}
