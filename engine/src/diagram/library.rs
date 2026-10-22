//! **Where a piece lives in the library, and how it is found** (2026-09-30).
//!
//! Three libraries, each under its own tool: **Light** — lamps only;
//! **Grip** — frames and rags, flags and nets, boards and cards, rolls,
//! stands and rigging, lifts (his words: *"grip equipment, that should be a
//! separate category no? right now it's all lumped in one"*); **Set** —
//! rooms, furniture, vehicles, outdoors, props, camera support, electric.
//!
//! Each piece carries a `kind` (the library's sections and its filter
//! chips), a `maker` where it is a branded unit (the Maker filter), and the
//! words a gaffer calls it by (`aka`: "m18", "kino", "china ball") so search
//! finds what he types, not only what the pack named it.
//!
//! What a piece *is* on the plan does not change here — a stand is still a
//! set piece, a flag still a light-kind piece that gives no light. This is
//! only where the library shows it.

use super::fso;
use super::gear::{Look, Tone};
use super::symbols::Sym;

/// The libraries, by the tool that opens them.
pub const LIGHT: &str = "light";
pub const GRIP: &str = "grip";
pub const SET: &str = "set";

/// Each library's sections, in the order it shows them.
pub const LIGHT_KINDS: &[&str] = &["HMI", "LED", "Tungsten", "Fluorescent", "Soft", "Practical"];
/// Flags & Nets went 2026-10-01: every flag, net and silk is the Frame's.
pub const GRIP_KINDS: &[&str] = &["Frames & Rags", "Boards & Cards", "Rolls", "Stands & Rigging", "Lifts"];
pub const SET_KINDS: &[&str] = &["Rooms", "Furniture", "Vehicles", "Outdoors", "Props", "Camera Support", "Electric"];

/// Where a piece sits, and the words it answers to.
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub lib: &'static str,
    pub kind: &'static str,
    pub maker: &'static str,
    pub aka: String,
}

fn has(n: &str, words: &[&str]) -> bool {
    words.iter().any(|w| n.contains(w))
}

/// A pack picture's place.
pub fn of_art(a: &fso::Art) -> Place {
    let n = a.name.to_lowercase();
    let (lib, kind) = match a.role {
        "light" | "fixture" => (LIGHT, light_kind(&n, a.group, a.kelvin)),
        "grip" => (GRIP, grip_kind(&n, a.group)),
        _ => set_or_grip(&n, a.group),
    };
    Place { lib, kind, maker: maker(&n), aka: aka(&n) }
}

/// One of our own drawings' place.
pub fn of_sym(s: &Sym) -> Place {
    let n = s.name.to_lowercase();
    let (lib, kind) = if s.light && s.beam > 0.0 {
        (LIGHT, look_kind(s.look).unwrap_or_else(|| light_kind(&n, s.group, s.kelvin)))
    } else if s.light {
        (GRIP, grip_kind(&n, s.group))
    } else {
        set_or_grip(&n, s.group)
    };
    Place { lib, kind, maker: maker(&n), aka: aka(&n) }
}

/// A lamp's kind by how it is drawn, where that says.
fn look_kind(look: Look) -> Option<&'static str> {
    Some(match look {
        Look::Fresnel(Tone::Tungsten) | Look::OpenFace | Look::Par | Look::Ellipsoidal | Look::Cluster(..) | Look::Beam => "Tungsten",
        Look::Fresnel(Tone::Hmi) | Look::Can(_) | Look::Joker | Look::Softube => "HMI",
        Look::Fresnel(Tone::Led) | Look::Head(_) | Look::Panel | Look::Mat | Look::Tube => "LED",
        Look::Kino => "Fluorescent",
        Look::Softbox | Look::Ball | Look::Spacelight | Look::Parabolic => "Soft",
        Look::Shade | Look::Bulb | Look::StreetLight | Look::WallLight | Look::Torch => "Practical",
        _ => return None,
    })
}

fn light_kind(n: &str, group: &str, kelvin: f64) -> &'static str {
    if has(n, &["bare bulb", "lamp with shade", "flashlight", "street light", "wall mount", "wall utility", "outdoor spot", "practical", "triolet"]) {
        "Practical"
    } else if group == "Fluorescent" || has(n, &["kino bare", "diva", "gaffer 4x"]) {
        "Fluorescent"
    } else if group == "HMI" || has(n, &["joker", "hmi", "12k par"]) {
        "HMI"
    } else if group == "LED" || has(n, &["led"]) {
        "LED"
    } else if has(n, &["china ball", "lantern", "spacelight", "space light", "softbox", "pancake", "light dome", "briese"]) {
        "Soft"
    } else if group.starts_with("Tungsten") || kelvin > 0.0 && kelvin < 4000.0 {
        "Tungsten"
    } else {
        "LED"
    }
}

fn grip_kind(n: &str, group: &str) -> &'static str {
    match group {
        "Rags" => "Frames & Rags",
        "Rolls & Cards" if has(n, &["roll", "cut "]) => "Rolls",
        "Rolls & Cards" => "Boards & Cards",
        _ if has(n, &["frame", "rag", "overhead"]) => "Frames & Rags",
        _ if has(n, &["foam", "shiny", "lightbridge", "crls", "bounce", "mirror", "showcard", "neg"]) => "Boards & Cards",
        _ => "Flags & Nets",
    }
}

/// A set piece's place — or the grip library's, for the stands, rigging
/// and lifts a grip puts up.
fn set_or_grip(n: &str, group: &str) -> (&'static str, &'static str) {
    if has(n, &["condor", "genie", "scissor"]) {
        return (GRIP, "Lifts");
    }
    if has(n, &["speed rail", "truss", "polecat", "c-stand", "baby stand", "combo stand", "crankovator", "crank stand", "high roller"]) {
        return (GRIP, "Stands & Rigging");
    }
    if has(n, &["distro", "lunch box", "gang box", "generator"]) {
        return (SET, "Electric");
    }
    if has(n, &[
        "dolly", "slider", "track", "curve", "curved radius", "crane", "jib", "easyrig", "kira", "sticks", "menace", "russian arm",
    ]) {
        return (SET, "Camera Support");
    }
    let kind = match group {
        "Rooms & Spaces" | "Structure" => "Rooms",
        "Furniture" | "Kitchen & Bath" => "Furniture",
        "Vehicles" => "Vehicles",
        "Outdoors" => "Outdoors",
        "Stage" | "Film Gear" => "Props",
        _ if n.split_whitespace().any(|w| w == "car" || w == "truck") => "Vehicles",
        _ if has(n, &["bed", "couch", "chair", "table"]) && !n.contains("crafty") => "Furniture",
        _ if has(n, &["tree", "hedge", "sidewalk", "cone", "canopy"]) => "Outdoors",
        _ => "Props",
    };
    (SET, kind)
}

/// Who makes it, for a branded unit; empty for a plain one.
fn maker(n: &str) -> &'static str {
    const MAKERS: &[(&[&str], &str)] = &[
        (&["arri", "skypanel", "orbiter"], "ARRI"),
        (&["aputure", "infinibar", "infinimat", "light dome", "spotlight max", "cf12", "f14 fresnel"], "Aputure"),
        (&["astera"], "Astera"),
        (&["astra"], "Litepanels"),
        (&["creamsource"], "Creamsource"),
        (&["digital sputnik", "ds-1", "ds1"], "Digital Sputnik"),
        (&["etc "], "ETC"),
        (&["hudson spider"], "Hudson Spider"),
        (&["kino", "diva", "gaffer 4x"], "Kino Flo"),
        (&["litemat", "litetile"], "LiteGear"),
        (&["mole", "molebeam", "molefay", "molepar"], "Mole-Richardson"),
        (&["nanlux"], "Nanlux"),
        (&["nanlite"], "Nanlite"),
        (&["quasar"], "Quasar Science"),
        (&["joker"], "K5600"),
        (&["briese"], "Briese"),
        (&["lightbridge", "crls"], "Lightbridge"),
        (&["chapman"], "Chapman"),
        (&["fisher"], "Fisher"),
        (&["techno crane", "technocrane"], "Technocrane"),
    ];
    MAKERS.iter().find(|(words, _)| has(n, words)).map(|m| m.1).unwrap_or("")
}

/// The words a crew calls it by, past its name.
fn aka(n: &str) -> String {
    const AKA: &[(&str, &str)] = &[
        ("m18", "m18 1.8k 1800 par hmi"),
        ("m40", "m40 4k 4000 par hmi"),
        ("m90", "m90 9k par hmi"),
        ("arri m8", "m8 800 par hmi"),
        ("arrimax", "arrimax max 18k 12k par"),
        ("18-12", "18k 12k 18/12 fresnel"),
        ("18/12", "18k 12k 18/12 fresnel"),
        ("joker", "joker bug k5600 hmi"),
        ("leko", "leko ellipsoidal source four"),
        ("ellipsoidal", "leko source four"),
        ("s30c", "s30 skypanel sky panel"),
        ("s60c", "s60 skypanel sky panel"),
        ("s120c", "s120 skypanel sky panel"),
        ("s360c", "s360 skypanel sky panel"),
        ("skypanel", "skypanel sky panel"),
        ("kino", "kino kinoflo flo fluorescent fluoro"),
        ("diva", "kino kinoflo diva fluorescent fluoro"),
        ("gaffer 4x", "kino kinoflo fluorescent fluoro"),
        ("celeb", "kino celeb"),
        ("litemat", "litemat lite mat litegear"),
        ("litetile", "litetile lite tile litegear"),
        ("infinimat", "infinimat mat"),
        ("astera", "titan astera tube pixel"),
        ("quasar", "quasar tube"),
        ("pavo", "pavo tube"),
        ("infinibar", "infinibar tube bar"),
        ("china ball", "chinaball china lantern paper"),
        ("lantern", "lantern china ball chinaball paper"),
        ("spacelight", "space light space"),
        ("space light", "spacelight space"),
        ("molefay", "fay maxi brute"),
        ("molepar", "maxi brute par"),
        ("tweenie", "tweenie 650"),
        ("mole baby", "baby 1k"),
        ("mole junior", "junior 2k"),
        ("arrilite", "open face redhead blonde"),
        ("skypan", "sky pan skypan"),
        ("zip", "zip softlite"),
        ("dome", "dome softbox"),
        ("spider", "spider hudson"),
        ("solid", "flag floppy solid"),
        ("flag", "flag solid"),
        // The Frame makes every flag, net, silk and rag since 2026-10-01, so
        // it answers to what a crew calls each of them.
        ("frame", "flag floppy solid cutter silk net scrim rag butterfly overhead"),
        ("scrim", "net scrim"),
        ("ultra bounce", "ultrabounce griff bounce"),
        ("grid cloth", "grid cloth gridcloth"),
        ("showcard", "card showcard"),
        ("foam core", "foamcore bead board bounce"),
        ("shiny", "reflector shiny board"),
        ("c-stand", "cstand c stand century"),
        ("combo stand", "combo junior stand"),
        ("crankovator", "crank stand wind up"),
        ("polecat", "polecat pole"),
        ("speed rail", "speedrail pipe"),
        ("truss", "truss"),
        ("genie", "lift scissor genie"),
        ("condor", "lift boom condor"),
        ("techno", "technocrane crane"),
        ("chapman", "peewee dolly"),
        ("fisher", "dolly"),
        ("dana", "slider dolly dana"),
        ("easyrig", "easy rig"),
        ("distro", "distribution power distro"),
        ("generator", "genny putt putt power"),
        ("lunch box", "lunchbox power"),
        ("gang box", "gangbox power"),
        ("hmi", "hmi daylight"),
    ];
    let mut out = String::new();
    for (k, words) in AKA {
        if n.contains(k) {
            out.push_str(words);
            out.push(' ');
        }
    }
    out.trim_end().to_string()
}

/// Whether a piece answers to what was typed: every word typed is found in
/// its name, its section, its maker or the words it is called by. "4k par"
/// finds a 4K HMI PAR and an M40; "kino" every fluorescent.
pub fn matches(query: &str, name: &str, group: &str, p: &Place) -> bool {
    let hay = format!("{} {} {} {} {}", name, group, p.kind, p.maker, p.aka).to_lowercase();
    query.split_whitespace().all(|w| hay.contains(&w.to_lowercase()))
}
