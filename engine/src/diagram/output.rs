//! **What a lamp puts out** (Scenario's light estimates, 2026-09-28): its
//! luminous intensity — candela, the light it throws straight down its
//! middle — at full spot and at full flood.
//!
//! Generic figures per kind of unit, the way Scenario's own library keeps
//! them: a 2K Fresnel is the average of the 2K Fresnels ARRI and Mole make,
//! an LED head is its standard reflector, and what is hung on the front (a
//! Fresnel lens, a narrow reflector, a dome) multiplies it. Rounded from
//! makers' published photometrics — a plan, not a meter.
//!
//! Every library lamp is here: ours by id (`UNITS`), the Film Set Objects
//! pack's by name (`by_name`). Anything else is read from the reach it was
//! given, so a lamp nobody listed still throws a sensible level.

use super::{fso, El};

/// A unit's output: its narrowest beam and the candela there, its widest
/// and the candela there. A unit that does not focus has the two the same.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Output {
    pub spot: f64,
    pub spot_cd: f64,
    pub flood: f64,
    pub flood_cd: f64,
}

const fn zoom(spot: f64, spot_cd: f64, flood: f64, flood_cd: f64) -> Output {
    Output { spot, spot_cd, flood, flood_cd }
}

const fn fixed(deg: f64, cd: f64) -> Output {
    Output { spot: deg, spot_cd: cd, flood: deg, flood_cd: cd }
}

impl Output {
    /// The candela at a beam of `deg`, between spot and flood: spread over
    /// the cone it lights, so read on the tangent of the half angle.
    pub fn at(&self, deg: f64) -> f64 {
        if (self.flood - self.spot).abs() < 1e-6 || self.spot_cd <= 0.0 || self.flood_cd <= 0.0 {
            return self.spot_cd.max(0.0);
        }
        let t = |d: f64| (d.clamp(1.0, 170.0) / 2.0).to_radians().tan().ln();
        let u = ((t(deg) - t(self.spot)) / (t(self.flood) - t(self.spot))).clamp(0.0, 1.0);
        if u <= 0.0 {
            return self.spot_cd;
        }
        if u >= 1.0 {
            return self.flood_cd;
        }
        (self.spot_cd.ln() + (self.flood_cd.ln() - self.spot_cd.ln()) * u).exp()
    }
}

/// Our own library's lamps (`symbols.rs`), by id.
pub const UNITS: &[(&str, Output)] = &[
    // Generic
    ("generic-fresnel", zoom(12.0, 68_000.0, 54.0, 8_300.0)),
    ("generic-open-face", zoom(30.0, 40_000.0, 75.0, 8_000.0)),
    ("generic-par", zoom(12.0, 250_000.0, 48.0, 40_000.0)),
    ("generic-ellipsoidal", fixed(26.0, 90_000.0)),
    ("generic-hmi", zoom(12.0, 400_000.0, 55.0, 40_000.0)),
    ("generic-cob", zoom(15.0, 60_000.0, 55.0, 12_000.0)),
    ("generic-panel", fixed(100.0, 3_000.0)),
    ("generic-kino", fixed(110.0, 1_500.0)),
    ("generic-tube", fixed(150.0, 400.0)),
    ("generic-mat", fixed(110.0, 1_500.0)),
    ("generic-softbox", fixed(90.0, 2_500.0)),
    ("generic-china-ball", fixed(360.0, 400.0)),
    ("generic-spacelight", fixed(360.0, 4_000.0)),
    ("generic-practical", fixed(360.0, 50.0)),
    // Tungsten
    ("fresnel-650", zoom(13.0, 31_500.0, 58.0, 3_400.0)),
    ("fresnel", zoom(12.0, 68_000.0, 54.0, 8_300.0)),
    ("fresnel-2k", zoom(12.0, 125_000.0, 56.0, 18_000.0)),
    ("fresnel-5k", zoom(10.0, 350_000.0, 56.0, 45_000.0)),
    ("fresnel-10k", zoom(10.0, 800_000.0, 50.0, 100_000.0)),
    ("arri-150", zoom(11.0, 6_800.0, 55.0, 900.0)),
    ("arri-300", zoom(15.0, 17_500.0, 62.0, 1_900.0)),
    ("arri-650", zoom(13.0, 31_500.0, 58.0, 3_400.0)),
    ("arri-t12", zoom(10.0, 800_000.0, 50.0, 100_000.0)),
    ("arri-t24", zoom(10.0, 1_500_000.0, 50.0, 200_000.0)),
    ("mole-tweenie", zoom(13.0, 30_000.0, 58.0, 3_300.0)),
    ("mole-baby", zoom(12.0, 65_000.0, 54.0, 8_000.0)),
    ("mole-junior", zoom(12.0, 120_000.0, 56.0, 17_000.0)),
    ("arrilite-750", zoom(30.0, 25_000.0, 75.0, 6_000.0)),
    ("arrilite-2k", zoom(30.0, 70_000.0, 75.0, 15_000.0)),
    ("skypan-5k", fixed(90.0, 20_000.0)),
    ("par", zoom(12.0, 250_000.0, 48.0, 40_000.0)),
    ("par-64", zoom(9.0, 330_000.0, 48.0, 40_000.0)),
    ("mole-par-1k", zoom(9.0, 330_000.0, 48.0, 40_000.0)),
    ("mole-par-2k", zoom(9.0, 650_000.0, 48.0, 80_000.0)),
    ("mole-par-5k", zoom(9.0, 1_600_000.0, 48.0, 200_000.0)),
    ("molefay-6", fixed(30.0, 70_000.0)),
    ("molefay-9", fixed(30.0, 110_000.0)),
    ("maxi-6", zoom(12.0, 1_500_000.0, 48.0, 240_000.0)),
    ("maxi-9", zoom(12.0, 2_200_000.0, 48.0, 360_000.0)),
    ("molebeam-5k", zoom(6.0, 2_500_000.0, 15.0, 500_000.0)),
    ("molebeam-10k", zoom(6.0, 5_000_000.0, 15.0, 1_000_000.0)),
    ("molebeam-20k", zoom(6.0, 10_000_000.0, 15.0, 2_000_000.0)),
    ("ellipsoidal", fixed(26.0, 90_000.0)),
    ("followspot", zoom(8.0, 1_500_000.0, 16.0, 400_000.0)),
    // HMI
    ("hmi", zoom(12.0, 400_000.0, 55.0, 40_000.0)),
    ("hmi-4k", zoom(12.0, 900_000.0, 55.0, 90_000.0)),
    ("hmi-18k", zoom(12.0, 4_500_000.0, 55.0, 450_000.0)),
    ("arri-1812", zoom(12.0, 4_500_000.0, 55.0, 450_000.0)),
    ("arri-m8", zoom(20.0, 100_000.0, 60.0, 12_000.0)),
    ("arri-m18", zoom(20.0, 400_000.0, 60.0, 40_000.0)),
    ("arri-m40", zoom(20.0, 1_000_000.0, 60.0, 100_000.0)),
    ("arri-m90", zoom(20.0, 2_500_000.0, 60.0, 250_000.0)),
    ("arrimax", zoom(15.0, 5_000_000.0, 60.0, 500_000.0)),
    ("mole-par-12k", zoom(8.0, 5_000_000.0, 50.0, 300_000.0)),
    ("joker-200", zoom(20.0, 60_000.0, 60.0, 8_000.0)),
    ("joker-400", zoom(20.0, 120_000.0, 60.0, 16_000.0)),
    ("joker-800", zoom(20.0, 240_000.0, 60.0, 32_000.0)),
    ("joker-1600", zoom(20.0, 480_000.0, 60.0, 64_000.0)),
    ("joker-800-softube", fixed(180.0, 5_000.0)),
    ("joker-1600-softube", fixed(180.0, 10_000.0)),
    // Lights by size (`symbols.rs`'s "18K HMI Fresnel" and the rest).
    ("hmi-fresnel-18k", zoom(12.0, 4_500_000.0, 55.0, 450_000.0)),
    ("hmi-fresnel-12k", zoom(12.0, 3_000_000.0, 55.0, 300_000.0)),
    ("hmi-fresnel-6k", zoom(12.0, 1_600_000.0, 55.0, 160_000.0)),
    ("hmi-fresnel-4k", zoom(12.0, 900_000.0, 55.0, 90_000.0)),
    ("hmi-fresnel-2.5k", zoom(12.0, 600_000.0, 55.0, 60_000.0)),
    ("hmi-fresnel-1.2k", zoom(12.0, 280_000.0, 55.0, 28_000.0)),
    ("hmi-fresnel-575", zoom(12.0, 120_000.0, 55.0, 12_000.0)),
    ("hmi-par-18k", zoom(15.0, 5_000_000.0, 60.0, 500_000.0)),
    ("hmi-par-12k", zoom(15.0, 3_800_000.0, 60.0, 380_000.0)),
    ("hmi-par-6k", zoom(20.0, 1_800_000.0, 60.0, 180_000.0)),
    ("hmi-par-4k", zoom(20.0, 1_000_000.0, 60.0, 100_000.0)),
    ("hmi-par-2.5k", zoom(20.0, 650_000.0, 60.0, 65_000.0)),
    ("hmi-par-1.8k", zoom(20.0, 400_000.0, 60.0, 40_000.0)),
    ("hmi-par-1.2k", zoom(20.0, 280_000.0, 60.0, 28_000.0)),
    ("hmi-par-575", zoom(20.0, 100_000.0, 60.0, 12_000.0)),
    ("tungsten-fresnel-20k", zoom(10.0, 1_600_000.0, 50.0, 200_000.0)),
    ("tungsten-fresnel-10k", zoom(10.0, 800_000.0, 50.0, 100_000.0)),
    ("tungsten-fresnel-5k", zoom(10.0, 350_000.0, 56.0, 45_000.0)),
    ("tungsten-fresnel-2k", zoom(12.0, 125_000.0, 56.0, 18_000.0)),
    ("tungsten-fresnel-1k", zoom(12.0, 68_000.0, 54.0, 8_300.0)),
    ("tungsten-fresnel-650", zoom(13.0, 31_500.0, 58.0, 3_400.0)),
    ("tungsten-fresnel-300", zoom(15.0, 17_500.0, 62.0, 1_900.0)),
    ("tungsten-fresnel-150", zoom(11.0, 6_800.0, 55.0, 900.0)),
    // LED heads: the standard reflector, and the Fresnels
    ("cob", zoom(15.0, 60_000.0, 55.0, 12_000.0)),
    ("aputure-120d", fixed(55.0, 7_000.0)),
    ("aputure-300d", fixed(55.0, 13_000.0)),
    ("aputure-600d", fixed(55.0, 25_000.0)),
    ("aputure-600d-fresnel", zoom(15.0, 180_000.0, 45.0, 27_000.0)),
    ("aputure-1200d", fixed(55.0, 50_000.0)),
    ("aputure-1200d-fresnel", zoom(15.0, 400_000.0, 45.0, 55_000.0)),
    ("aputure-cs15", fixed(55.0, 65_000.0)),
    ("aputure-xt26", fixed(55.0, 110_000.0)),
    ("light-dome", fixed(90.0, 3_500.0)),
    ("light-dome-mini", fixed(90.0, 1_500.0)),
    ("forza-60", fixed(55.0, 4_000.0)),
    ("forza-300", fixed(55.0, 12_000.0)),
    ("forza-500", fixed(55.0, 20_000.0)),
    ("evoke-1200", fixed(45.0, 60_000.0)),
    ("evoke-2400", fixed(45.0, 120_000.0)),
    ("arri-l5", zoom(15.0, 10_500.0, 50.0, 2_300.0)),
    ("arri-l7", zoom(15.0, 25_000.0, 50.0, 5_000.0)),
    ("arri-l10", zoom(15.0, 51_000.0, 50.0, 11_000.0)),
    ("arri-orbiter", zoom(15.0, 100_000.0, 60.0, 16_000.0)),
    ("mole-senior-led", zoom(12.0, 150_000.0, 55.0, 20_000.0)),
    ("mole-tenor-led", zoom(12.0, 300_000.0, 55.0, 40_000.0)),
    ("source-four-led", fixed(26.0, 50_000.0)),
    // Panels
    ("panel", fixed(100.0, 3_000.0)),
    ("panel-l", fixed(100.0, 6_000.0)),
    ("skypanel-s30", fixed(110.0, 3_500.0)),
    ("skypanel-s60", fixed(110.0, 7_500.0)),
    ("skypanel-s120", fixed(110.0, 15_000.0)),
    ("skypanel-s360", fixed(110.0, 45_000.0)),
    ("skypanel-x", fixed(110.0, 30_000.0)),
    ("astra", fixed(50.0, 3_500.0)),
    ("celeb-250", fixed(90.0, 2_000.0)),
    ("celeb-450", fixed(90.0, 4_000.0)),
    ("celeb-850", fixed(90.0, 8_000.0)),
    ("vortex-4", fixed(100.0, 8_000.0)),
    ("vortex-8", fixed(100.0, 16_000.0)),
    ("dyno-650", fixed(100.0, 12_000.0)),
    ("dyno-1200", fixed(100.0, 25_000.0)),
    ("mixpanel-60", fixed(100.0, 1_300.0)),
    ("mixpanel-150", fixed(100.0, 3_500.0)),
    ("ds6", fixed(30.0, 40_000.0)),
    ("kino", fixed(110.0, 1_500.0)),
    ("kino-4-bank", fixed(100.0, 2_000.0)),
    ("kino-2-bank", fixed(100.0, 800.0)),
    ("diva-400", fixed(100.0, 1_500.0)),
    ("zip-2k", fixed(90.0, 5_000.0)),
    // Mats and tubes
    ("mat", fixed(110.0, 1_500.0)),
    ("litemat-1x1", fixed(110.0, 700.0)),
    ("litemat-2x2", fixed(110.0, 1_500.0)),
    ("litemat-4x1", fixed(110.0, 1_500.0)),
    ("litemat-4x2", fixed(110.0, 3_000.0)),
    ("litetile-2x4", fixed(110.0, 2_500.0)),
    ("litetile-2x8", fixed(110.0, 5_000.0)),
    ("infinimat-1x4", fixed(110.0, 3_000.0)),
    ("infinimat-2x4", fixed(110.0, 6_000.0)),
    ("infinimat-4x4", fixed(120.0, 12_000.0)),
    ("infinimat-8x8", fixed(120.0, 30_000.0)),
    ("tube", fixed(150.0, 400.0)),
    ("tube-s", fixed(150.0, 200.0)),
    ("quasar-2", fixed(150.0, 250.0)),
    ("quasar-4", fixed(150.0, 500.0)),
    ("quasar-8", fixed(150.0, 1_000.0)),
    ("astera-titan", fixed(150.0, 400.0)),
    ("astera-helios", fixed(150.0, 200.0)),
    ("pavo-15", fixed(150.0, 250.0)),
    ("pavo-30", fixed(150.0, 500.0)),
    ("infinibar-pb6", fixed(150.0, 200.0)),
    ("infinibar-pb12", fixed(150.0, 400.0)),
    ("kino-tube", fixed(180.0, 300.0)),
    // Soft
    ("softbox", fixed(90.0, 2_500.0)),
    ("softbox-s", fixed(90.0, 1_500.0)),
    ("softbox-l", fixed(90.0, 5_000.0)),
    ("pancake", fixed(100.0, 3_000.0)),
    ("lantern", fixed(360.0, 1_500.0)),
    ("china-ball", fixed(360.0, 400.0)),
    ("china-ball-l", fixed(360.0, 1_000.0)),
    ("spacelight", fixed(360.0, 4_000.0)),
    ("spacelight-6k", fixed(360.0, 12_000.0)),
    ("briese-100", zoom(12.0, 300_000.0, 90.0, 25_000.0)),
    ("briese-180", zoom(12.0, 1_000_000.0, 90.0, 60_000.0)),
    ("briese-220", zoom(12.0, 1_500_000.0, 90.0, 100_000.0)),
    ("briese-330", zoom(12.0, 2_500_000.0, 90.0, 150_000.0)),
    ("mozzie", fixed(90.0, 5_000.0)),
    ("redback", fixed(90.0, 20_000.0)),
    // Practicals
    ("practical", fixed(360.0, 50.0)),
    ("bulb", fixed(360.0, 60.0)),
    ("lamp-shade", fixed(360.0, 50.0)),
    ("street-sodium", fixed(100.0, 8_000.0)),
    ("street-mercury", fixed(100.0, 6_000.0)),
    ("wall-light", fixed(120.0, 800.0)),
    ("flashlight", fixed(20.0, 3_000.0)),
];

pub fn by_id(id: &str) -> Option<Output> {
    UNITS.iter().find(|u| u.0 == id).map(|u| u.1)
}

/// An LED head's standard-reflector candela, by the model in its name.
const HEADS: &[(&str, f64)] = &[
    ("1200d", 50_000.0),
    ("1200x", 50_000.0),
    ("1000c", 38_000.0),
    ("xt26", 110_000.0),
    ("cs15", 65_000.0),
    ("600d", 25_000.0),
    ("300d", 13_000.0),
    ("120d", 7_000.0),
    ("80c", 3_500.0),
    ("2400b", 120_000.0),
    ("1200b", 60_000.0),
    ("900c", 45_000.0),
];

/// What is hung on an LED head's front, from its name.
fn front(base: f64, n: &str) -> Output {
    let has = |k: &str| n.contains(k);
    if has("fresnel") {
        zoom(15.0, base * 8.0, 45.0, base * 1.3)
    } else if has("spotlight") || has("projector") {
        zoom(15.0, base * 3.0, 40.0, base * 0.6)
    } else if has("hyper") {
        fixed(20.0, base * 5.0)
    } else if has("narrow") || has("26 degree") {
        fixed(26.0, base * 3.5)
    } else if has("30 degree") {
        fixed(30.0, base * 2.5)
    } else if has("medium") || has("45 degree") {
        fixed(40.0, base * 1.6)
    } else if has("wide") || has("60 degree") {
        fixed(60.0, base * 0.8)
    } else if has("dome") || has("lantern") {
        fixed(90.0, base * 0.2)
    } else {
        fixed(55.0, base)
    }
}

/// The first run of digits in a name, as a number: `Joker 800` → 800.
fn number(n: &str) -> Option<f64> {
    let s: String = n.chars().skip_while(|c| !c.is_ascii_digit()).take_while(|c| c.is_ascii_digit()).collect();
    s.parse().ok()
}

/// **The Film Set Objects pack**, by what its name says the unit is.
pub fn by_name(name: &str) -> Option<Output> {
    let n = name.to_lowercase();
    let has = |k: &str| n.contains(k);
    let id = by_id;
    // LED heads and what hangs on them.
    if let Some((_, base)) = HEADS.iter().find(|h| has(h.0)) {
        return Some(front(*base, &n));
    }
    if has("cf12 fresnel") {
        return Some(front(65_000.0, &n));
    }
    if has("f14 fresnel") {
        return Some(front(50_000.0, &n));
    }
    if has("spotlight max") {
        return Some(front(25_000.0, &n));
    }
    if has("forza 500") {
        return id("forza-500");
    }
    if has("forza 300") {
        return id("forza-300");
    }
    if has("forza 60") {
        return id("forza-60");
    }
    // HMI
    if has("softube") {
        return number(&n).map(|w| fixed(180.0, w * 6.0));
    }
    if has("joker") {
        let w = number(&n.replace("joker2", "joker"))?;
        return Some(if has("leko") { fixed(25.0, w * 190.0) } else { zoom(20.0, w * 300.0, 60.0, w * 40.0) });
    }
    if has("arrimax") {
        return id("arrimax");
    }
    if has("18-12") || has("18/12") {
        return id("arri-1812");
    }
    for (k, u) in [("m90", "arri-m90"), ("m40", "arri-m40"), ("m18", "arri-m18"), ("m8", "arri-m8")] {
        if has(k) {
            return id(u);
        }
    }
    // Tungsten
    for (k, u) in [
        ("12k par", "mole-par-12k"),
        ("6k molepar", "maxi-6"),
        ("9k molepar", "maxi-9"),
        ("6 light molefay", "molefay-6"),
        ("9 light molefay", "molefay-9"),
        ("molebeam 20k", "molebeam-20k"),
        ("molebeam 10k", "molebeam-10k"),
        ("molebeam 5k", "molebeam-5k"),
        ("5k par", "mole-par-5k"),
        ("2k par", "mole-par-2k"),
        ("1k par", "mole-par-1k"),
        ("par 64", "par-64"),
        ("skypan", "skypan-5k"),
        ("tweenie", "mole-tweenie"),
        ("baby", "mole-baby"),
        ("junior", "mole-junior"),
        ("arri t24", "arri-t24"),
        ("arri t12", "arri-t12"),
        ("arri 150", "arri-150"),
        ("arri 300", "arri-300"),
        ("arri 650", "arri-650"),
        ("750 plus arrilite", "arrilite-750"),
        ("2k plus arrilite", "arrilite-2k"),
        ("2k zip", "zip-2k"),
        ("china ball", "china-ball"),
        ("spacelight", "spacelight"),
        ("light dome mini", "light-dome-mini"),
        ("light dome", "light-dome"),
        ("bare bulb", "bulb"),
        ("lamp with shade", "lamp-shade"),
        ("wall mount utility", "wall-light"),
        ("mercury vapor", "street-mercury"),
        ("street light", "street-sodium"),
        ("flashlight", "flashlight"),
        ("source four led", "source-four-led"),
        ("ellipsoidal", "ellipsoidal"),
    ] {
        if has(k) {
            return id(u);
        }
    }
    if has("1k zip") {
        return Some(fixed(90.0, 2_500.0));
    }
    if has("briese focus") {
        return match number(&n) {
            Some(w) if w >= 330.0 => id("briese-330"),
            Some(w) if w >= 220.0 => id("briese-220"),
            Some(w) if w >= 180.0 => id("briese-180"),
            _ => id("briese-100"),
        };
    }
    if has("pancake") {
        return Some(fixed(100.0, if has("large") { 4_000.0 } else { 3_000.0 }));
    }
    if has("softbox") {
        return id(if has("small") { "softbox-s" } else if has("large") { "softbox-l" } else { "softbox" });
    }
    if has("outdoor spot") {
        return Some(fixed(30.0, if has("double") { 5_000.0 } else { 2_500.0 }));
    }
    if has("triolet") {
        return Some(zoom(10.0, 40_000.0, 50.0, 4_000.0));
    }
    // Fluorescent
    if has("diva 400") {
        return id("diva-400");
    }
    if has("diva 200") {
        return Some(fixed(100.0, 800.0));
    }
    if has("gaffer 4x4") {
        return id("kino-4-bank");
    }
    if has("gaffer 4x2") {
        return Some(fixed(100.0, 700.0));
    }
    if has("kino bare") {
        return Some(fixed(150.0, if has("4'") { 300.0 } else { 150.0 }));
    }
    // LED fixtures
    if has("skypanel x") {
        return Some(if has("hyper") { fixed(20.0, 200_000.0) } else if has("dome") { fixed(100.0, 20_000.0) } else { id("skypanel-x")? });
    }
    for (k, u) in [
        ("s360", "skypanel-s360"),
        ("s120", "skypanel-s120"),
        ("s60", "skypanel-s60"),
        ("s30", "skypanel-s30"),
        ("arri l10", "arri-l10"),
        ("arri l7", "arri-l7"),
        ("arri l5", "arri-l5"),
        ("astra 1x1", "astra"),
        ("vortex 8", "vortex-8"),
        ("vortex 4", "vortex-4"),
        ("dyno 1200", "dyno-1200"),
        ("dyno 650", "dyno-650"),
        ("mixpanel 150", "mixpanel-150"),
        ("mixpanel 60", "mixpanel-60"),
        ("pavo 30", "pavo-30"),
        ("pavo 15", "pavo-15"),
        ("celeb 850", "celeb-850"),
        ("celeb 450", "celeb-450"),
        ("celeb 250", "celeb-250"),
        ("ds6", "ds6"),
        ("mozzie", "mozzie"),
        ("redback", "redback"),
        ("tenorled", "mole-tenor-led"),
        ("seniorled", "mole-senior-led"),
        ("litetile 2x8", "litetile-2x8"),
        ("litetile 2x4", "litetile-2x4"),
        ("1x1 litemat", "litemat-1x1"),
        ("2x2 litemat", "litemat-2x2"),
        ("4x1 litemat", "litemat-4x1"),
        ("4x2 litemat", "litemat-4x2"),
        ("infinimat 8x8", "infinimat-8x8"),
        ("infinimat 4x4", "infinimat-4x4"),
        ("infinimat 2x4", "infinimat-2x4"),
        ("infinimat 1x4", "infinimat-1x4"),
        ("infinibar pb12", "infinibar-pb12"),
        ("infinibar pb6", "infinibar-pb6"),
    ] {
        if has(k) {
            return id(u);
        }
    }
    if has("orbiter") {
        return Some(if has("dome") { fixed(90.0, 8_000.0) } else { id("arri-orbiter")? });
    }
    if has("litemat 8") {
        return Some(fixed(110.0, 3_000.0));
    }
    if has("infinimat 1x2") {
        return Some(fixed(110.0, 1_500.0));
    }
    if has("infinibar pb3") {
        return Some(fixed(150.0, 100.0));
    }
    if has("astera") || has("pixel tube") {
        return id("astera-titan");
    }
    if has("pavo 6") {
        return Some(fixed(120.0, 250.0));
    }
    if has("voyager") {
        return Some(fixed(150.0, if has("4ft") { 500.0 } else { 250.0 }));
    }
    if has("ds1") || has("ds-1") {
        return Some(fixed(20.0, 10_000.0));
    }
    if has("quasar") {
        return Some(fixed(150.0, if has("1'") { 125.0 } else if has("2'") { 250.0 } else { 500.0 }));
    }
    if has("ls 1-2w") {
        return Some(fixed(100.0, 2_500.0));
    }
    if has("ls-mini20") {
        return Some(fixed(100.0, 1_500.0));
    }
    if has("mc pro") {
        return Some(fixed(100.0, 100.0));
    }
    if has("literibbon") {
        return Some(fixed(360.0, if has("24") { 300.0 } else { 150.0 }));
    }
    if has("b7c") {
        return Some(fixed(360.0, 60.0));
    }
    if has("2k led") {
        return Some(zoom(15.0, 90_000.0, 60.0, 12_000.0));
    }
    if has("small led") {
        return Some(fixed(60.0, 1_000.0));
    }
    None
}

/// A drawing's output, if the library knows it.
pub fn of(sym: &str) -> Option<Output> {
    match fso::find(sym) {
        Some(a) => by_name(a.name),
        None => by_id(sym),
    }
}

/// The candela a lamp throws at its beam now: its unit's output between
/// spot and flood. Before its dimmer or gels (`levels.rs` takes those). A
/// lamp the library does not know is read from its reach — as bright as it
/// takes to light a stop over a common midtone that far off.
pub fn candela(e: &El) -> f64 {
    match of(&e.sym) {
        Some(o) => o.at(e.beam),
        None => 120.0 * e.reach.max(0.5).powi(2),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_lamp_in_both_libraries_has_an_output() {
        let mut missing = Vec::new();
        for s in super::super::symbols::CATALOG.iter().filter(|s| s.light && s.beam > 0.0) {
            if by_id(s.id).is_none() {
                missing.push(s.id.to_string());
            }
        }
        for a in fso::ART.iter().filter(|a| a.role == "light" && a.beam > 0.0) {
            if by_name(a.name).is_none() {
                missing.push(a.name.to_string());
            }
        }
        assert!(missing.is_empty(), "no output for {missing:?}");
    }

    #[test]
    fn a_fresnel_is_brightest_at_spot_and_follows_its_beam_between() {
        let f = by_id("fresnel-2k").unwrap();
        assert_eq!(f.at(12.0), 125_000.0);
        assert!((f.at(56.0) - 18_000.0).abs() < 1.0);
        let mid = f.at(30.0);
        assert!(mid < 125_000.0 && mid > 18_000.0, "{mid}");
        assert_eq!(f.at(5.0), 125_000.0, "no brighter than full spot");
        assert!(f.at(30.0) > f.at(40.0), "wider is dimmer");
    }

    #[test]
    fn the_packs_units_read_by_class_and_by_what_hangs_on_them() {
        let bare = by_name("Aputure 600D").unwrap();
        let fresnel = by_name("Aputure 600D with Fresnel").unwrap();
        assert!(fresnel.spot_cd > bare.spot_cd * 4.0);
        assert!(by_name("Arri M18").unwrap().spot_cd > by_name("Arri M8").unwrap().spot_cd);
        assert!(by_name("Joker 1600").unwrap().spot_cd > by_name("Joker 400").unwrap().spot_cd);
        assert_eq!(by_name("Arri S60c Top"), by_id("skypanel-s60"));
        assert_eq!(by_name("China Ball").unwrap().spot, 360.0);
        assert!(by_name("Molebeam 20K").unwrap().spot_cd > by_name("Molebeam 5K").unwrap().spot_cd);
    }
}
