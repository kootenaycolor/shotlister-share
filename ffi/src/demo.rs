//! Daybreak, Day 1 — the real list, so the app opens with something true in it.
//!
//! Same sixteen shots as `engine/examples/daybreak_day_1.rs`, including the parts
//! that matter: letters out of order on the day, two cameras on one moment, an
//! angle holding two values, and this production's lens set rather than a default.

use shotlister_engine::doc::f;
use shotlister_engine::{Doc, Id};

struct Row {
    scene: &'static str,
    letter: &'static str,
    description: &'static str,
    size: &'static str,
    angle: &'static [&'static str],
    movement: &'static str,
    camera: &'static str,
    lens: &'static str,
    support: &'static str,
    notes: &'static str,
    tags: &'static [&'static str],
}

/// In the order they are shot on Day 1, which is not the order of their letters.
const DAY_ONE: &[Row] = &[
    Row { scene: "33", letter: "A", description: "Establish Jail — camera shooting through front driver window, Felix walking out towards camera", size: "W/OTS", angle: &["Eye Level"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &[] },
    Row { scene: "34", letter: "C", description: "Frontal Dirty Single on Milo through Front Window", size: "M/OTS", angle: &["Short-Sided"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "Frame in a way to hide 2 cameras cross coverage", tags: &["Cross Coverage"] },
    Row { scene: "34", letter: "D", description: "Frontal Dirty Single on Felix through Front Window", size: "M/OTS", angle: &["Short-Sided"], movement: "Static", camera: "B-Cam", lens: "37mm", support: "Handheld", notes: "Frame in a way to hide 2 cameras cross coverage", tags: &["Cross Coverage"] },
    Row { scene: "34", letter: "A", description: "Milo French Over — run until \"Did you tell them that you need them?\"", size: "M/OTS", angle: &["Short-Sided"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &["Cross Coverage"] },
    Row { scene: "34", letter: "B", description: "Felix French Over — run until \"Did you tell them that you need them?\"", size: "CU/OTS", angle: &["Short-Sided"], movement: "Static", camera: "B-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &["Cross Coverage"] },
    Row { scene: "34", letter: "E", description: "Wide of the Car — pulls away from station", size: "W", angle: &["Short-Sided", "3/4"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &["Free Driving"] },
    Row { scene: "35", letter: "A", description: "Shot looking away from the building — out of focus — car pulls into frame in profile, we see their reactions and then it pulls out", size: "TS", angle: &["Profile"], movement: "Static", camera: "A-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &[] },
    Row { scene: "35", letter: "B", description: "Wide shot revealing the closed up pharmacy", size: "W", angle: &[], movement: "Static", camera: "A-Cam", lens: "20.7mm", support: "Handheld", notes: "", tags: &[] },
    Row { scene: "54", letter: "A", description: "Milo/Felix Walk In — follow from behind in TS. We reveal the fight scene as we come around the door entrance — a big stunt happens at the ring", size: "TS", angle: &["Front On", "Eye Level"], movement: "Tracking Forward", camera: "A-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &[] },
    Row { scene: "54", letter: "B", description: "Milo/Felix Walk In — follow from front in TS, as they see everything happening", size: "TS", angle: &["Front On"], movement: "Tracking Backward", camera: "A-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &[] },
    Row { scene: "54", letter: "C", description: "Shot of the fight as they walk in — longer lens, through the crowd looking up at the fight happening in the ring", size: "POV", angle: &["Low"], movement: "Follow Action", camera: "Cam Undecided", lens: "47mm", support: "Handheld", notes: "", tags: &["Stunt"] },
    Row { scene: "54", letter: "D", description: "Milo/Felix Observe the Fight — wider shot over the crowd's shoulders as they watch; this is where we cover their interactions with Bruno", size: "COWBOY/OTS", angle: &["High"], movement: "Static", camera: "A-Cam", lens: "47mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Row { scene: "54", letter: "E", description: "Milo/Felix Observe the Fight — closer shot over the crowd's shoulders as they watch", size: "COWBOY/OTS", angle: &["High"], movement: "Static", camera: "B-Cam", lens: "47mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Row { scene: "54", letter: "F", description: "Reverse on Bruno — from their POV, looking up at him through the ropes", size: "POV", angle: &["Low"], movement: "Follow Action", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Row { scene: "54", letter: "G", description: "Reverse on Bruno tighter — from their POV, looking up at him through the ropes", size: "POV", angle: &["Low"], movement: "Follow Action", camera: "B-Cam", lens: "57mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Row { scene: "54", letter: "H", description: "INSERT — fight choreography. Find this sequence on the day", size: "", angle: &[], movement: "", camera: "", lens: "", support: "", notes: "We stay outside the ring with them, and go in when they go in", tags: &["Stunt"] },
];

const SCENES: [(&str, &str, &str, &str); 4] = [
    ("33", "EXT", "COUNTY JAIL", "DAY"),
    ("34", "INT", "CAR", "DAY"),
    ("35", "EXT", "PHARMACY", "DAY"),
    ("54", "INT", "FIGHT VENUE", "NIGHT"),
];

/// Fills an existing document rather than building a second one.
///
/// Storage has already made the project record; creating another here would
/// leave two, and the vocabulary would be learned on one and read from the other.
pub fn seed(d: &mut Doc) {
    let project = match d.project_id() {
        Some(p) => p,
        None => {
            d.create_project("Daybreak");
            d.project_id().unwrap()
        }
    };
    d.set(project, f::TITLE, "Daybreak");
    d.set(project, f::ASPECT_RATIO, 2.39_f64);
    d.set(project, f::DIRECTOR, "Sam Ridley");

    let a_cam = d.create_unit("A-Cam", "Alexa 35");
    d.set(a_cam, f::COLOUR, "#B8332A");
    let b_cam = d.create_unit("B-Cam", "Alexa 35");
    d.set(b_cam, f::COLOUR, "#2A66C4");
    let undecided = d.create_unit("Cam Undecided", "");
    d.set(undecided, f::COLOUR, "#6B4FB0");

    let unit_for = |label: &str| -> Option<Id> {
        match label {
            "A-Cam" => Some(a_cam),
            "B-Cam" => Some(b_cam),
            "Cam Undecided" => Some(undecided),
            _ => None,
        }
    };

    // The pages these shots came off. Enough of them for the panel beside the
    // list to be worth opening.
    const SCRIPT: [(&str, &str); 2] = [
        (
            "33",
            "EXT. COUNTY JAIL - DAY\n\nFELIX steps out into light he has not\nstood in for two years. He does not\nlook back at the building.\n\nA car idles across the lot. MILO at\nthe wheel, watching him come.",
        ),
        (
            "34",
            "INT. CAR - DAY\n\nThey drive. Neither of them starts.\n\n                    MILO\n          You could have called.\n\n                    FELIX\n          Did you tell them that you\n          need them?\n\nMilo does not answer. The pharmacy\nsign slides past the window.",
        ),
    ];

    let drive = d.create_sequence("The Drive");
    d.set(drive, f::COLOUR, "#35756D");
    let fight = d.create_sequence("The Fight");
    d.set(fight, f::COLOUR, "#8A3B57");
    let jail = d.create_sequence("Jail Release");
    d.set(jail, f::COLOUR, "#96703A");

    let mut scene_ids: Vec<(&str, Id)> = Vec::new();
    for (number, int_ext, location, tod) in SCENES {
        let scene = d.create_scene(number);
        d.set(scene, f::INT_EXT, int_ext);
        d.set(scene, f::LOCATION, location);
        d.set(scene, f::TIME_OF_DAY, tod);
        d.set(
            scene,
            f::SEQUENCE,
            match number {
                "33" => jail,
                "34" | "35" => drive,
                _ => fight,
            },
        );
        // a few lines of the scene, so the script panel has something in it and
        // the search has prose to find as well as shot descriptions
        if let Some(lines) = SCRIPT.iter().find(|(n, _)| *n == number).map(|(_, s)| *s) {
            d.set(scene, f::SCRIPT, lines);
        }
        scene_ids.push((number, scene));
    }

    // Shots are created in letter order within each scene, because the letter is
    // assigned on creation. The shooting order is applied afterwards, on the day.
    let mut placements: Vec<(&Row, Id)> = Vec::new();
    let mut shots_by_number: Vec<(&str, &str, Id)> = Vec::new();
    for (number, scene) in &scene_ids {
        let mut rows: Vec<&Row> = DAY_ONE.iter().filter(|s| s.scene == *number).collect();
        rows.sort_by_key(|s| s.letter);
        for row in rows {
            let (shot, placement) = d.add_shot_to_scene(*scene);
            d.set(shot, f::DESCRIPTION, row.description);
            if !row.size.is_empty() {
                d.set_vocab_field(shot, "size", row.size);
            }
            if !row.angle.is_empty() {
                d.set_vocab_list(shot, "angle", row.angle);
            }
            if !row.movement.is_empty() {
                d.set_vocab_field(shot, "movement", row.movement);
            }
            if !row.lens.is_empty() {
                d.set_vocab_field(shot, "lens", row.lens);
            }
            if !row.support.is_empty() {
                d.set_vocab_field(shot, "support", row.support);
            }
            if !row.tags.is_empty() {
                d.set_vocab_list(shot, "tags", row.tags);
            }
            if !row.notes.is_empty() {
                d.set(shot, f::NOTES, row.notes);
            }
            if let Some(unit) = unit_for(row.camera) {
                d.set(shot, f::UNIT, unit);
            }
            shots_by_number.push((row.scene, row.letter, shot));
            placements.push((row, placement));
        }
    }

    // The cross-coverage pairs are one moment on two cameras, which is what the
    // bracket down the margin says. In the real list they are the French Overs
    // and the frontal dirties: A and B, C and D.
    for (scene, first, second) in [("34", "A", "B"), ("34", "C", "D")] {
        let find = |letter: &str| {
            shots_by_number
                .iter()
                .find(|(s, l, _)| *s == scene && *l == letter)
                .map(|(_, _, id)| *id)
        };
        if let (Some(a), Some(b)) = (find(first), find(second)) {
            // any shared id will do; the engine only asks that it is the same one
            d.set(a, f::SETUP, a);
            d.set(b, f::SETUP, a);
        }
    }

    // Day 1, in the order it is actually shot — which is not letter order.
    let day = d.create_day();
    d.set(day, f::DATE, "Fri 12 Sep");
    for (index, row) in DAY_ONE.iter().enumerate() {
        if let Some((_, placement)) = placements
            .iter()
            .find(|(r, _)| r.scene == row.scene && r.letter == row.letter)
        {
            d.schedule_at(*placement, day, index);
        }
    }

    // Somewhere to put things, so the board is not a single column.
    let day_two = d.create_day();
    d.set(day_two, f::DATE, "Sat 13 Sep");
}
