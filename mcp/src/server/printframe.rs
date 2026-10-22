//! A shot's Print Frame — the one picture that stands for it on paper — and
//! the storyboard arrows on any picture (`engine/src/printframe.rs`,
//! `engine/src/arrow.rs`).
//!
//! The engine holds the spec; **the Mac draws the board**. So a Print Frame
//! set here prints the next time the Mac has the film open and bakes it, and
//! until then the shot prints the way it always did. Every tool says so.

use shotlister_engine::arrow::{Arrow, ArrowDepth, ArrowLook, ArrowShape, ArrowStance, ArrowWeight, ZoomDir, THICKEST, THINNEST};
use shotlister_engine::media::MediaKind;
use shotlister_engine::printframe::{Moment, PrintFrame, LAYOUTS};
use shotlister_engine::{f, Doc, Id};

use super::media::{find_use, owner_of};
use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

const UPDATES: &str = "The printed picture updates when the Mac next opens the project.";

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "print_frame",
        description: "A shot's Print Frame: the one picture that stands for it in every PDF, built from its own stills and clip moments. Answers the layout, numbers, frames (attachment position and name, `at` seconds for a clip), board arrows, whether the Mac has printed it yet (`printed`), and the shot's attachments to build one from. A shot with none prints its lead frame as always.",
        arguments: &[("shot", "string", true)],
    },
    Tool {
        name: "set_print_frame",
        description: "Set a shot's Print Frame. `frames`: [{\"attachment\": 1 or a name, \"at\": seconds from the clip's start, clips only}], in board order. `layout`: one, across, stacked, grid22, grid32, grid23 (grids need frames of one shape), side (first big, rest beside), under (first big, rest below), rows, cols; left out, it follows the count. `numbers`: badges on each frame (default on for 3 or more). `arrows`: board arrows, as picture_arrows takes them, in fractions of the whole board. Anything left out is kept. `clear`=true removes it. Frames are never cropped; the board takes their shape. The printed picture updates when the Mac next opens the project.",
        arguments: &[
            ("shot", "string", true),
            ("frames", "array", false),
            ("layout", "string", false),
            ("numbers", "boolean", false),
            ("arrows", "array", false),
            ("clear", "boolean", false),
        ],
    },
    Tool {
        name: "picture_arrows",
        description: "The storyboard arrows on one picture: owner (`shot`, `scene`, `location` or `board`) and `attachment` (position or name). Without `arrows` it answers what is drawn. `arrows` replaces them all: [{\"points\": [[x,y], …] tail, any pins, head, each 0 to 1 of the picture's width and height; \"shape\": smooth|corner; \"heads\": 0|1|2; \"dashed\": bool; \"look\": light|dark|red|yellow; \"thickness\": 0.5 to 3 times the usual (or \"weight\": S|M|L, 0.7/1/1.4); \"depth\": flat|toward|away (a perspective arrow: toward grows from a narrow tail to a big head, coming at camera; away shrinks to a small head, going away); \"strength\": how much a deep arrow widens, 0.1 to 1, usually 0.5; \"stance\": floor|standing (a deep arrow drawn as a solid slab lying on the floor, the default, or standing up facing the lens); \"zoom\": in|out, a zoom mark instead of an arrow: points are the inner frame's top-left and bottom-right corners, it keeps the picture's shape, look and thickness apply}]. Two points is a straight arrow. `clear`=true removes them. Subject moves are usually dashed and red. Shows on screen at once; a shot's Print Frame picks it up when the Mac next opens the project.",
        arguments: &[
            ("shot", "string", false),
            ("scene", "string", false),
            ("location", "string", false),
            ("board", "string", false),
            ("attachment", "string", true),
            ("arrows", "array", false),
            ("clear", "boolean", false),
        ],
    },
];

/// One arrow as the tools say it.
pub(super) fn arrow_json(a: &Arrow) -> Json {
    let point = |(x, y): (f64, f64)| Json::Array(vec![Json::Number(round(x)), Json::Number(round(y))]);
    Json::object(vec![
        ("points", Json::Array(a.points().into_iter().map(point).collect())),
        ("shape", Json::text(a.shape.name())),
        ("heads", Json::Number(a.heads as f64)),
        ("dashed", Json::Bool(a.dashed)),
        ("look", Json::text(a.look.name())),
        ("thickness", Json::Number(round(a.thickness))),
        ("depth", Json::text(a.depth.name())),
        ("strength", Json::Number(round(a.depth_strength))),
        ("stance", if a.depth == ArrowDepth::Flat { Json::Null } else { Json::text(a.stance.name()) }),
        ("zoom", a.zoom.map(|z| Json::text(z.name())).unwrap_or(Json::Null)),
        (
            "view",
            a.view
                .map(|[l, t, r, b]| Json::Array(vec![point((l, t)), point((r, b))]))
                .unwrap_or(Json::Null),
        ),
    ])
}

fn round(v: f64) -> f64 {
    (v * 10_000.0).round() / 10_000.0
}

/// One arrow from what a tool was given.
pub(super) fn arrow_from(json: &Json) -> Result<Arrow, String> {
    let points: Vec<(f64, f64)> = json
        .get("points")
        .and_then(|p| p.as_array())
        .ok_or("Each arrow needs points: [[x,y], …], tail first, head last.")?
        .iter()
        .map(|p| {
            let pair = p.as_array().unwrap_or(&[]);
            match (pair.first().and_then(|v| v.as_f64()), pair.get(1).and_then(|v| v.as_f64())) {
                (Some(x), Some(y)) if x.is_finite() && y.is_finite() => Ok((x, y)),
                _ => Err("A point is two numbers, [x, y], each 0 to 1.".to_string()),
            }
        })
        .collect::<Result<_, _>>()?;
    let mut arrow = Arrow::through(&points).ok_or("An arrow needs at least two points: a tail and a head.")?;
    if let Some(said) = json.get("shape").and_then(|v| v.as_str()) {
        arrow.shape = ArrowShape::read(said).ok_or(format!("No arrow shape {said}: smooth or corner."))?;
    }
    if let Some(n) = json.get("heads").and_then(|v| v.as_f64()) {
        if !(0.0..=2.0).contains(&n) {
            return Err("heads is 0, 1 or 2.".into());
        }
        arrow.heads = n.round() as u8;
    }
    if let Some(dashed) = json.get("dashed").and_then(|v| v.as_bool()) {
        arrow.dashed = dashed;
    }
    if let Some(said) = json.get("look").and_then(|v| v.as_str()) {
        arrow.look = ArrowLook::read(said).ok_or(format!("No arrow look {said}: light, dark, red or yellow."))?;
    }
    if let Some(said) = json.get("weight").and_then(|v| v.as_str()) {
        arrow.thickness = ArrowWeight::read(said).ok_or(format!("No arrow weight {said}: S, M or L."))?.factor();
    }
    if let Some(t) = json.get("thickness").and_then(|v| v.as_f64()) {
        if !(t.is_finite() && (THINNEST..=THICKEST).contains(&t)) {
            return Err(format!("thickness is {THINNEST} to {THICKEST} times the usual."));
        }
        arrow.thickness = t;
    }
    if let Some(said) = json.get("depth").and_then(|v| v.as_str()) {
        arrow.depth = ArrowDepth::read(said).ok_or(format!("No arrow depth {said}: flat, toward or away."))?;
    }
    if let Some(s) = json.get("strength").and_then(|v| v.as_f64()) {
        if !(s.is_finite() && (0.1..=1.0).contains(&s)) {
            return Err("strength is 0.1 to 1.".into());
        }
        arrow.depth_strength = s;
    }
    if let Some(said) = json.get("stance").and_then(|v| v.as_str()) {
        arrow.stance = ArrowStance::read(said).ok_or(format!("No arrow stance {said}: floor or standing."))?;
    }
    if let Some(v) = json.get("view").and_then(|v| v.as_array()) {
        let n: Vec<f64> = v.iter().flat_map(|p| p.as_array().unwrap_or(&[]).iter().filter_map(|x| x.as_f64()).collect::<Vec<_>>()).collect();
        if n.len() != 4 {
            return Err("view is two points, [[x,y],[x,y]]: the corners of the part of the picture that shows.".into());
        }
        arrow.view = Some([n[0], n[1], n[2], n[3]]);
    }
    if let Some(said) = json.get("zoom").and_then(|v| v.as_str()) {
        arrow.zoom = Some(ZoomDir::read(said).ok_or(format!("No zoom {said}: in or out."))?);
        arrow.pins.clear();
        arrow.heads = 0;
    }
    Ok(arrow.held())
}

fn arrows_from(list: &Json) -> Result<Vec<Arrow>, String> {
    list.as_array().ok_or("arrows is a list.")?.iter().map(arrow_from).collect()
}

/// The layout a board of this many frames takes when none is named — one
/// that takes any mix of shapes.
fn layout_for(count: usize) -> &'static str {
    match count {
        0 | 1 => "one",
        2 | 3 => "across",
        5 => "under",
        _ => "rows",
    }
}

/// A picture's shape, as the board will draw it: a crop is the film's ratio.
fn shape_of(doc: &Doc, mref: Id) -> Option<f64> {
    let record = doc.get(mref)?;
    if record.get(f::CROP_SCALE).and_then(|v| v.as_float()).is_some() {
        return None;
    }
    let media = doc.get(record.ref_id(f::MEDIA)?)?;
    let w = media.get(f::WIDTH).and_then(|v| v.as_int())? as f64;
    let h = media.get(f::HEIGHT).and_then(|v| v.as_int())? as f64;
    (w > 0.0 && h > 0.0).then_some(w / h)
}

fn shot_needed(doc: &Doc, arguments: &Json) -> Result<(Id, String), String> {
    let said = arguments.str_field("shot");
    if said.trim().is_empty() {
        return Err("Say which shot.".into());
    }
    let placement = tools::find_placement(doc, &said).ok_or(format!("There is no shot {} in this project.", said.trim()))?;
    let shot = tools::shot_of(doc, placement).ok_or(format!("There is no shot {} in this project.", said.trim()))?;
    Ok((doc.described_by(shot), format!("shot {}", said.trim())))
}

fn attachments_json(doc: &Doc, shot: Id) -> Json {
    Json::Array(
        doc.media_refs(shot)
            .into_iter()
            .enumerate()
            .map(|(i, mref)| {
                let media = doc.get(mref).and_then(|r| r.ref_id(f::MEDIA));
                let kind = media.and_then(|m| doc.media_kind(m)).unwrap_or(MediaKind::Other);
                let mut pairs = vec![
                    ("attachment", Json::Number((i + 1) as f64)),
                    ("name", Json::text(doc.media_ref_name(mref))),
                    ("kind", Json::text(kind.as_str())),
                ];
                if let Some(shape) = shape_of(doc, mref) {
                    pairs.push(("shape", Json::Number(round(shape))));
                }
                if let Some((start, end)) = doc.media_trim(mref) {
                    pairs.push(("trim", Json::Array(vec![Json::Number(start), Json::Number(end)])));
                }
                Json::object(pairs)
            })
            .collect(),
    )
}

impl<F: Films> Server<F> {
    pub(super) fn print_frame_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "print_frame" => (|| {
                let doc = self.films.doc()?;
                let (shot, whose) = shot_needed(doc, arguments)?;
                let uses = doc.media_refs(shot);
                let mut pairs = vec![("shot", Json::text(whose.trim_start_matches("shot ")))];
                match doc.print_frame(shot) {
                    None => {
                        pairs.push(("print_frame", Json::Null));
                        pairs.push(("says", Json::text("No Print Frame: it prints its lead frame as always.")));
                    }
                    Some(spec) => {
                        let frames = spec
                            .frames
                            .iter()
                            .map(|m| {
                                let at = uses.iter().position(|u| *u == m.media_ref);
                                let mut p = vec![
                                    ("attachment", at.map(|i| Json::Number((i + 1) as f64)).unwrap_or(Json::Null)),
                                    ("name", Json::text(if at.is_some() { doc.media_ref_name(m.media_ref) } else { "(no longer on the shot)".to_string() })),
                                ];
                                if let Some(t) = m.at {
                                    p.push(("at", Json::Number(t)));
                                }
                                Json::object(p)
                            })
                            .collect();
                        pairs.push((
                            "print_frame",
                            Json::object(vec![
                                ("layout", Json::text(spec.layout.clone())),
                                ("numbers", Json::Bool(spec.numbers)),
                                ("frames", Json::Array(frames)),
                                ("arrows", Json::Array(spec.arrows.iter().map(arrow_json).collect())),
                                ("printed", Json::Bool(doc.print_frame_is_current(shot))),
                            ]),
                        ));
                        if !doc.print_frame_is_current(shot) {
                            pairs.push(("says", Json::text(UPDATES)));
                        }
                    }
                }
                pairs.push(("attachments", attachments_json(doc, shot)));
                pairs.push(("layouts", Json::Array(LAYOUTS.iter().map(|l| Json::text(*l)).collect())));
                Ok(Json::object(pairs).encode())
            })(),
            "set_print_frame" => {
                let arguments = arguments.clone();
                self.change("Change Print Frame", move |doc| {
                    let (shot, whose) = shot_needed(doc, &arguments)?;
                    if tools::bool_arg(&arguments, "clear") == Some(true) {
                        doc.clear_print_frame(shot);
                        return Ok(format!("Removed the Print Frame on {whose}; it prints its lead frame again."));
                    }
                    let before = doc.print_frame(shot);
                    let frames: Vec<Moment> = match arguments.get("frames").filter(|v| !v.is_null()) {
                        Some(list) => {
                            let list = list.as_array().ok_or("frames is a list.")?;
                            let mut out = Vec::new();
                            for item in list {
                                let said = match item.get("attachment").or(Some(item)) {
                                    Some(Json::Number(n)) => format!("{}", *n as i64),
                                    Some(Json::Text(t)) => t.clone(),
                                    _ => return Err("Each frame names its attachment: a position or a name.".into()),
                                };
                                let mref = find_use(doc, shot, &whose, &said)?;
                                let moving = doc
                                    .get(mref)
                                    .and_then(|r| r.ref_id(f::MEDIA))
                                    .and_then(|m| doc.media_kind(m))
                                    .map(|k| k.is_moving())
                                    .unwrap_or(false);
                                let at = item.get("at").and_then(|v| v.as_f64());
                                if at.is_some() && !moving {
                                    return Err(format!("{} is a still; only a clip's frame takes a time.", doc.media_ref_name(mref)));
                                }
                                let at = if moving {
                                    Some(at.unwrap_or_else(|| doc.media_trim(mref).map(|t| t.0).unwrap_or(0.0)))
                                } else {
                                    None
                                };
                                out.push(Moment { media_ref: mref, at });
                            }
                            out
                        }
                        None => match &before {
                            Some(spec) => spec.frames.clone(),
                            None => return Err("Say which frames: [{\"attachment\": 1}, …].".into()),
                        },
                    };
                    if frames.is_empty() {
                        return Err("A Print Frame needs at least one frame. clear=true removes it.".into());
                    }
                    let layout = match arguments.get("layout").and_then(|v| v.as_str()).map(|s| s.trim().to_lowercase()) {
                        Some(l) if !l.is_empty() => {
                            if !LAYOUTS.contains(&l.as_str()) {
                                return Err(format!("No layout {l}. The layouts are {}.", LAYOUTS.join(", ")));
                            }
                            l
                        }
                        _ => match &before {
                            Some(spec) if spec.frames.len() == frames.len() => spec.layout.clone(),
                            _ => layout_for(frames.len()).to_string(),
                        },
                    };
                    if layout.starts_with("grid") {
                        let shapes: Vec<Option<f64>> = frames.iter().map(|m| shape_of(doc, m.media_ref)).collect();
                        let first = shapes.first().copied().flatten();
                        if shapes.iter().any(|s| match (s, first) {
                            (Some(a), Some(b)) => (a - b).abs() > 0.01,
                            _ => false,
                        }) {
                            return Err("A grid needs frames of one shape; these differ. Try rows, across, side or under.".into());
                        }
                    }
                    let numbers = tools::bool_arg(&arguments, "numbers")
                        .or_else(|| before.as_ref().filter(|s| s.frames.len() == frames.len()).map(|s| s.numbers))
                        .unwrap_or(frames.len() >= 3);
                    let arrows = match arguments.get("arrows").filter(|v| !v.is_null()) {
                        Some(list) => arrows_from(list)?,
                        None => before.as_ref().map(|s| s.arrows.clone()).unwrap_or_default(),
                    };
                    let count = frames.len();
                    doc.set_print_frame(shot, &PrintFrame { layout: layout.clone(), frames, numbers, arrows });
                    Ok(format!(
                        "Print Frame on {whose}: {count} frame{}, {layout}{}. {UPDATES}",
                        if count == 1 { "" } else { "s" },
                        if numbers { ", numbered" } else { "" }
                    ))
                })
            }
            "picture_arrows" => {
                let reading = arguments.get("arrows").filter(|v| !v.is_null()).is_none()
                    && tools::bool_arg(arguments, "clear") != Some(true);
                if reading {
                    return Some((|| {
                        let doc = self.films.doc()?;
                        let (owner, whose) = owner_of(doc, arguments, "")?.ok_or("Say whose: shot, scene, location or board.")?;
                        let mref = find_use(doc, owner, &whose, &arguments.str_field("attachment"))?;
                        Ok(Json::object(vec![
                            ("picture", Json::text(doc.media_ref_name(mref))),
                            ("arrows", Json::Array(doc.media_arrows(mref).iter().map(arrow_json).collect())),
                        ])
                        .encode())
                    })());
                }
                let arguments = arguments.clone();
                self.change("Draw arrows", move |doc| {
                    let (owner, whose) = owner_of(doc, &arguments, "")?.ok_or("Say whose: shot, scene, location or board.")?;
                    let mref = find_use(doc, owner, &whose, &arguments.str_field("attachment"))?;
                    let named = doc.media_ref_name(mref);
                    if tools::bool_arg(&arguments, "clear") == Some(true) {
                        doc.clear_media_arrows(mref);
                        return Ok(format!("Took the arrows off {named} on {whose}."));
                    }
                    let arrows = arrows_from(arguments.get("arrows").ok_or("Give arrows, or clear=true.")?)?;
                    let n = arrows.len();
                    doc.set_media_arrows(mref, &arrows);
                    Ok(format!("{n} arrow{} on {named} on {whose}.", if n == 1 { "" } else { "s" }))
                })
            }
            _ => return None,
        })
    }
}
