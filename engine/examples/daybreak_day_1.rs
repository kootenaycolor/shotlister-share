//! Daybreak, Day 1 — rebuilt in the engine from the real shot list.
//!
//! Sixteen shots taken from `DAY 1 - DAYBREAK SHOT LIST.pdf`. This exists to
//! check the model against a real list rather than an invented one, and it
//! catches the things that matter:
//!
//!   - letters out of order on the day — 34C, 34D, 34A, 34B, 34E
//!   - two cameras on one moment — 34C and 34D, 54D and 54E
//!   - an angle holding two values — "Front On, Eye Level"
//!   - a lens set that is this production's, not a default
//!
//! Scene headings are inferred from the descriptions; the day breakdown does not
//! carry them.
//!
//! Run with: cargo run --example daybreak_day_1

use std::collections::HashMap;
use std::fs;

use shotlister_engine::docstyle::Style;
use shotlister_engine::doc::f;
use shotlister_engine::export::xlsx::Frame;
use shotlister_engine::export::{csv, html, xlsx, FrameSize, Print};
use shotlister_engine::export::zip::crc32;
use shotlister_engine::media::MediaKind;
use shotlister_engine::sha256;
use shotlister_engine::{DeviceId, Doc, GroupBy, Id, Query};

struct Shot {
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
const DAY_ONE: &[Shot] = &[
    Shot { scene: "33", letter: "A", description: "Establish Jail - Camera shooting through front driver window - Felix walking out towards camera", size: "W/OTS", angle: &["Eye Level"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &[] },
    Shot { scene: "34", letter: "C", description: "Frontal Dirty Single on Milo through Front Window", size: "M/OTS", angle: &["Short-Sided"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "Frame is a way to hide 2 cameras cross coverage", tags: &["Cross Coverage"] },
    Shot { scene: "34", letter: "D", description: "Frontal Dirty Single on Felix through Front Window", size: "M/OTS", angle: &["Short-Sided"], movement: "Static", camera: "B-Cam", lens: "37mm", support: "Handheld", notes: "Frame is a way to hide 2 cameras cross coverage", tags: &["Cross Coverage"] },
    Shot { scene: "34", letter: "A", description: "Milo French Over - Run until \"Did you tell them that you need them?\"", size: "M/OTS", angle: &["Short-Sided"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &["Cross Coverage"] },
    Shot { scene: "34", letter: "B", description: "Felix French Over - Run until \"Did you tell them that you need them?\"", size: "CU/OTS", angle: &["Short-Sided"], movement: "Static", camera: "B-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &["Cross Coverage"] },
    Shot { scene: "34", letter: "E", description: "Wide of the Car - Pulls away from station", size: "W", angle: &["Short-Sided", "3/4"], movement: "Static", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &["Free Driving"] },
    Shot { scene: "35", letter: "A", description: "Shot looking away from the building - out of focus - car pulls into frame in profile - we see their reactions and then it pulls out", size: "TS", angle: &["Profile"], movement: "Static", camera: "A-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &[] },
    Shot { scene: "35", letter: "B", description: "Wide shot revealing the closed up pharmacy", size: "W", angle: &[], movement: "Static", camera: "A-Cam", lens: "20.7mm", support: "Handheld", notes: "", tags: &[] },
    Shot { scene: "54", letter: "A", description: "Milo/Felix Walk In - Follow from Behind in TS - We reveal the fight scene as we come around the door entrance - a big stunt happens at the ring", size: "TS", angle: &["Front On", "Eye Level"], movement: "Tracking Forward", camera: "A-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &[] },
    Shot { scene: "54", letter: "B", description: "Milo/Felix Walk In - Follow from Front in TS, as they see everything happening", size: "TS", angle: &["Front On"], movement: "Tracking Backward", camera: "A-Cam", lens: "27mm", support: "Handheld", notes: "", tags: &[] },
    Shot { scene: "54", letter: "C", description: "Shot of the fight as they walk in - longer lens, through the crowd looking up at the fight happening in the ring", size: "POV", angle: &["Low"], movement: "Follow Action", camera: "Cam Undecided", lens: "47mm", support: "Handheld", notes: "", tags: &["Stunt"] },
    Shot { scene: "54", letter: "F", description: "Reverse on Bruno - From their POV, looking up at him through the ropes.", size: "POV", angle: &["Low"], movement: "Follow Action", camera: "A-Cam", lens: "37mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Shot { scene: "54", letter: "G", description: "Reverse on Bruno Tighter - From their POV, looking up at him through the ropes.", size: "POV", angle: &["Low"], movement: "Follow Action", camera: "B-Cam", lens: "57mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Shot { scene: "54", letter: "D", description: "Milo/Felix Observe the Fight - Wider shot over crowd's shoulders as they watch - this is where we cover their interactions with Bruno", size: "COWBOY/OTS", angle: &["High"], movement: "Static", camera: "A-Cam", lens: "47mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Shot { scene: "54", letter: "E", description: "Milo/Felix Observe the Fight - Closer shot over crowd's shoulders as they watch - this is where we cover their interactions with Bruno", size: "COWBOY/OTS", angle: &["High"], movement: "Static", camera: "B-Cam", lens: "47mm", support: "Handheld", notes: "", tags: &["Dual Coverage"] },
    Shot { scene: "54", letter: "H", description: "INSERT FIGHT COREOGRAPHY - Find this sequence on the day", size: "", angle: &[], movement: "", camera: "", lens: "", support: "", notes: "Perspective: We stay outside the ring with them, we go in the ring when they go in the ring", tags: &["Stunt"] },
];

const SCENES: [(&str, &str, &str, &str); 4] = [
    ("33", "EXT", "county jail", "day"),
    ("34", "INT", "car", "day"),
    ("35", "EXT", "pharmacy", "day"),
    ("54", "INT", "fight venue", "night"),
];

/// A solid-colour PNG, written by hand.
///
/// Stands in for a real storyboard frame so the spreadsheet's picture layer can
/// be checked end to end. Encoding images is the shells' job, not the engine's —
/// this lives in the example for exactly that reason.
fn png(width: u32, height: u32, rgb: (u8, u8, u8)) -> Vec<u8> {
    fn chunk(kind: &[u8; 4], data: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        out.extend_from_slice(kind);
        out.extend_from_slice(data);
        let mut crc_input = kind.to_vec();
        crc_input.extend_from_slice(data);
        out.extend_from_slice(&crc32(&crc_input).to_be_bytes());
        out
    }

    fn adler32(data: &[u8]) -> u32 {
        let (mut a, mut b) = (1u32, 0u32);
        for byte in data {
            a = (a + *byte as u32) % 65521;
            b = (b + a) % 65521;
        }
        (b << 16) | a
    }

    // Raw scanlines, each prefixed with filter byte 0.
    let mut raw = Vec::with_capacity((height * (1 + width * 3)) as usize);
    for _ in 0..height {
        raw.push(0u8);
        for _ in 0..width {
            raw.extend_from_slice(&[rgb.0, rgb.1, rgb.2]);
        }
    }

    // zlib wrapping deflate "stored" blocks — no compressor needed.
    let mut zlib = vec![0x78, 0x01];
    for (index, block) in raw.chunks(65_535).enumerate() {
        let last = (index + 1) * 65_535 >= raw.len();
        zlib.push(if last { 1 } else { 0 });
        zlib.extend_from_slice(&(block.len() as u16).to_le_bytes());
        zlib.extend_from_slice(&(!(block.len() as u16)).to_le_bytes());
        zlib.extend_from_slice(block);
    }
    zlib.extend_from_slice(&adler32(&raw).to_be_bytes());

    let mut header = Vec::new();
    header.extend_from_slice(&width.to_be_bytes());
    header.extend_from_slice(&height.to_be_bytes());
    header.extend_from_slice(&[8, 2, 0, 0, 0]); // 8-bit truecolour

    let mut out = vec![137, 80, 78, 71, 13, 10, 26, 10];
    out.extend_from_slice(&chunk(b"IHDR", &header));
    out.extend_from_slice(&chunk(b"IDAT", &zlib));
    out.extend_from_slice(&chunk(b"IEND", &[]));
    out
}

fn main() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let project = d.project_id().unwrap();
    d.set(project, f::ASPECT_RATIO, 2.39_f64);

    // Cameras are their own thing, and their colour travels with them.
    let a_cam = d.create_unit("A-Cam", "Alexa35");
    d.set(a_cam, f::COLOUR, "#b00020");
    let b_cam = d.create_unit("B-Cam", "Alexa35");
    d.set(b_cam, f::COLOUR, "#1c4f9c");
    let undecided = d.create_unit("Cam Undecided", "");
    d.set(undecided, f::COLOUR, "#b00020");
    let unit_for = |label: &str| -> Option<Id> {
        match label {
            "A-Cam" => Some(a_cam),
            "B-Cam" => Some(b_cam),
            "Cam Undecided" => Some(undecided),
            _ => None,
        }
    };

    let mut scenes = Vec::new();
    for (number, int_ext, location, tod) in SCENES {
        let scene = d.create_scene(number);
        d.set(scene, f::INT_EXT, int_ext);
        d.set(scene, f::LOCATION, location);
        d.set(scene, f::TIME_OF_DAY, tod);
        scenes.push((number, scene));
    }
    // Shots are created in letter order within each scene, because the letter is
    // assigned on creation and never moves afterwards.
    let mut by_letter: Vec<(String, Id)> = Vec::new();
    let mut frames: HashMap<Id, Vec<u8>> = HashMap::new();
    for (number, scene) in &scenes {
        let mut letters: Vec<&Shot> = DAY_ONE.iter().filter(|s| s.scene == *number).collect();
        letters.sort_by_key(|s| s.letter);
        for entry in letters {
            let (shot, placement) = d.add_shot_to_scene(*scene);
            d.set(shot, f::DESCRIPTION, entry.description);
            if !entry.size.is_empty() {
                d.set_vocab_field(shot, "size", entry.size);
            }
            if !entry.angle.is_empty() {
                d.set_vocab_list(shot, "angle", entry.angle);
            }
            if !entry.movement.is_empty() {
                d.set_vocab_field(shot, "movement", entry.movement);
            }
            if !entry.lens.is_empty() {
                d.set_vocab_field(shot, "lens", entry.lens);
            }
            if !entry.support.is_empty() {
                d.set_vocab_field(shot, "support", entry.support);
            }
            if let Some(unit) = unit_for(entry.camera) {
                d.set(shot, f::UNIT, unit);
            }
            if !entry.notes.is_empty() {
                d.set(shot, f::NOTES, entry.notes);
            }
            if !entry.tags.is_empty() {
                d.set_vocab_list(shot, "tags", entry.tags);
            }

            // A stand-in frame per shot, so the picture layer is exercised.
            let seed = format!("{}{}", entry.scene, entry.letter);
            let hue = (by_letter.len() * 37 % 200) as u8;
            let bytes = png(160, 90, (40 + hue / 2, 80 + hue / 3, 120 - hue / 4));
            let media = d.add_media(
                sha256(seed.as_bytes()),
                MediaKind::Image,
                160,
                90,
                bytes.len() as u64,
                &format!("{seed}.png"),
            );
            d.attach_media(shot, media, "");
            frames.insert(media, bytes);

            let number = d.display_number(placement).expect("numbered");
            by_letter.push((number, placement));
        }
    }

    // Now schedule them in the order they are actually shot.
    let day = d.create_day();
    for entry in DAY_ONE {
        let wanted = format!("{}{}", entry.scene, entry.letter);
        let placement = by_letter
            .iter()
            .find(|(number, _)| *number == wanted)
            .map(|(_, id)| *id)
            .unwrap_or_else(|| panic!("no placement for {wanted}"));
        d.schedule(placement, day);
    }

    let out = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("samples");
    fs::create_dir_all(&out).expect("create samples dir");

    // The same list, read two ways. This is the whole thesis in two files.
    let by_day = d.sheet(&Query::grouped_by(GroupBy::Day));
    let by_scene = d.sheet(&Query::grouped_by(GroupBy::Scene));

    fs::write(
        out.join("daybreak-day-1-document.html"),
        html::document(&by_day, &html::no_frames, Print::Document, 1.0, "", &Style::standard_style()),
    )
    .unwrap();
    fs::write(
        out.join("daybreak-day-1-table.html"),
        html::table(&by_day, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default()),
    )
    .unwrap();
    fs::write(
        out.join("daybreak-by-scene-table.html"),
        html::table(&by_scene, &html::no_frames, Print::Table, 1.0, FrameSize::default(), &Default::default()),
    )
    .unwrap();
    fs::write(out.join("daybreak-day-1.csv"), csv::write(&by_day)).unwrap();
    // One picture per row. With several frames a real shell composites them
    // side by side; the example simply takes the first, which is enough to
    // exercise the placement.
    let supply = |ids: &[Id]| -> Option<Frame> {
        ids.first().and_then(|id| frames.get(id)).map(|bytes| Frame {
            bytes: bytes.clone(),
            extension: "png".to_string(),
            width: 160,
            height: 90,
            // Carried in the file: this example writes a workbook that has to
            // stand on its own, with no relay to fetch anything from.
            url: None,
        })
    };
    fs::write(
        out.join("daybreak-day-1.xlsx"),
        xlsx::write(&by_day, &|name| d.vocabulary(name), &supply),
    )
    .unwrap();

    // His actual working file, exactly: four tabs off the same shot list.
    let flat = d.sheet(&Query::grouped_by(GroupBy::Flat));
    let by_sequence = d.sheet(&Query::grouped_by(GroupBy::Sequence));
    fs::write(
        out.join("daybreak-day-1-workbook.xlsx"),
        xlsx::workbook(&flat, &by_day, &by_sequence, &|name| d.vocabulary(name), &supply),
    )
    .unwrap();

    println!("Daybreak — {} shots across {} scenes", by_day.total(), SCENES.len());
    println!();
    println!("Day 1, in shooting order:");
    for group in &by_day.groups {
        println!("  {} — {} shots", group.label, group.count());
        let numbers: Vec<&str> = group.rows.iter().map(|r| r.number.as_str()).collect();
        println!("    {}", numbers.join("  "));
    }
    println!();
    println!("The same shots, in story order:");
    for group in &by_scene.groups {
        let numbers: Vec<&str> = group.rows.iter().map(|r| r.number.as_str()).collect();
        println!("  {:<10} {}", group.label, numbers.join("  "));
    }
    println!();
    println!("Lens list this project taught itself: {:?}", d.vocabulary("lens"));
    println!("Written to {}", out.display());
}
