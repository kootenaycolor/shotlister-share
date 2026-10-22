//! The diagram on paper: the page the scene's PDF carries.
//!
//! **One sheet a scene, the sheet** (`sheet.rs`, Back to Paper, Batch 2): its
//! title, the plan to scale in its window, the legend, the notes and the
//! shots key — the same page the Mac shows on screen, the portal prints and
//! Claude looks at. Written without its margin, which the Mac's page
//! cutter (`Printing.swift`) puts round it, so it prints at its true size;
//! each sheet is one `.card` on a `.fresh-page` of its own. Its paper is
//! said on the page (`data-paper="792x612"`, points) for the cutter.

use super::sheet::{self, Ask};
use super::svg::Frame;
use crate::doc::{f, Doc};
use crate::id::Id;

/// What Export's Diagram page asks of the sheet (the Share page's own
/// switches): the way round and the scale bar when it says, else the
/// plan's own; wall lengths, cones, the Shots key and a dark plan.
#[derive(Clone, Debug)]
pub struct Show {
    pub landscape: Option<bool>,
    pub scale_bar: Option<bool>,
    pub dims: bool,
    pub cones: bool,
    /// The plan drawn dark, as on the portal; the sheet stays white.
    pub dark: bool,
    /// The Shots key under the plan. Off, the plan has the room (his ask,
    /// 2026-10-04: *"do I want to show the shot list next to it? Not
    /// always."*).
    pub key: bool,
    /// The day it is printed, as the shell writes a date; empty for none.
    pub printed: String,
    /// The shell's clock, minutes from UTC, the one its screen draws the sun
    /// by (`diagram`'s `tz=`). None: the plan's own, from its longitude.
    pub tz: Option<f64>,
}

impl Default for Show {
    fn default() -> Show {
        Show { landscape: None, scale_bar: None, dims: true, cones: true, dark: false, key: true, printed: String::new(), tz: None }
    }
}

impl Show {
    pub fn ask(&self) -> Ask {
        Ask {
            landscape: self.landscape,
            paper: None,
            scale_bar: self.scale_bar,
            dims: self.dims,
            cones: self.cones,
            key: self.key,
            dark: self.dark,
            screen: false,
            printed: self.printed.clone(),
            beat: 1,
            tz: self.tz,
        }
    }
}

/// The page. `scenes` empty means every scene with a plan, in story order.
/// `picture` turns a picture's media name (`<hash>.<ext>`) into something a
/// page can show — on the Mac, the file itself as a data address. `_title`
/// is the film's, which each sheet now reads for itself.
pub fn page(doc: &Doc, scenes: &[Id], show: Show, _title: &str, picture: &dyn Fn(&str) -> Option<String>) -> String {
    let wanted: Vec<Id> = if scenes.is_empty() {
        let with = doc.scenes_with_diagrams();
        doc.scenes_in_order().into_iter().filter(|s| with.contains(s)).collect()
    } else {
        scenes.iter().copied().filter(|s| doc.scene_diagram_total(*s) > 0).collect()
    };
    page_of(doc, &wanted, show, picture)
}

/// The scenes with a plan that have a shot on `day` (`None`: a shot on no
/// day yet), in story order — what a per-day export's diagram page holds
/// (Ref 1503). A day with none is an empty list, never "every scene".
pub fn scenes_for_day(doc: &Doc, day: Option<Id>) -> Vec<Id> {
    let with = doc.scenes_with_diagrams();
    doc.scenes_in_order()
        .into_iter()
        .filter(|s| with.contains(s))
        .filter(|s| doc.placements_in_scene(*s).iter().any(|p| doc.get(*p).and_then(|r| r.ref_id(f::DAY)) == day))
        .collect()
}

/// The page for one day's scenes (`None`: the unscheduled), "No diagrams
/// yet" when that day has none.
pub fn page_for_day(doc: &Doc, day: Option<Id>, show: Show, picture: &dyn Fn(&str) -> Option<String>) -> String {
    page_of(doc, &scenes_for_day(doc, day), show, picture)
}

fn page_of(doc: &Doc, wanted: &[Id], show: Show, picture: &dyn Fn(&str) -> Option<String>) -> String {
    let ask = show.ask();
    let mut sheets: Vec<(sheet::Sheet, String)> = Vec::new();
    // **Every diagram a scene has, each its own sheet** (`scenediagrams`),
    // in his order, the empty ones left out; a loose plan, or one diagram
    // asked for by its own id, is itself.
    let wanted: Vec<Id> = wanted
        .iter()
        .flat_map(|s| {
            if doc.get(*s).map(|r| r.kind == crate::store::Kind::Scene).unwrap_or(false) {
                doc.scene_diagram_ids(*s).into_iter().filter(|d| doc.diagram_count(*d) > 0).collect()
            } else {
                vec![*s]
            }
        })
        .collect();
    for (i, scene) in wanted.iter().enumerate() {
        let (sh, plan, ctx) = sheet::of(doc, *scene, &ask);
        let frame = Frame {
            fades: false,
            grid: false,
            scale_bar: false,
            hrefs: plan
                .els
                .iter()
                .filter(|e| e.kind == super::Kind::Image && !e.media.is_empty())
                .map(|e| e.media.clone())
                // A camera's frame laid on the plan, too.
                .chain(plan.els.iter().filter(|e| e.kind == super::Kind::Camera && e.frame_on).filter_map(|e| ctx.frame(&e.shot).map(|f| f.0.to_string())))
                .filter_map(|m| picture(&m).map(|h| (m, h)))
                .collect(),
            ..Default::default()
        };
        let pic = sheet::svg_of(&plan, &ctx, &sh, &ask, 0.0, true, &frame, &format!("p{i}"));
        sheets.push((sh, pic));
    }
    let paper = |s: &sheet::Sheet| format!("{:.0}x{:.0}", s.w, s.h);
    let mut out = String::new();
    out.push_str("<!doctype html><html><head><meta charset=\"utf-8\"><style>");
    out.push_str(
        "body{margin:0;font:11px -apple-system,system-ui,sans-serif;color:#17171A;background:#fff}\
         .sheet,.card{margin:0}\
         .sheet svg{display:block;max-width:100%;height:auto}\
         .scene-head{font-weight:700;font-size:14px;margin:0 0 10px}\
         .empty{color:#88888F;font-size:12px;padding:40px 0}",
    );
    out.push_str("</style></head>");
    match sheets.first() {
        Some((s, _)) => out.push_str(&format!("<body data-paper=\"{}\" data-orientation=\"{}\">", paper(s), if s.landscape { "landscape" } else { "portrait" })),
        None => out.push_str("<body>"),
    }
    if sheets.is_empty() {
        out.push_str("<div class=\"scene-head fresh-page\">Diagrams</div><div class=\"empty\">No diagrams yet</div>");
    }
    for (s, pic) in &sheets {
        out.push_str(&format!("<div class=\"sheet fresh-page\" data-paper=\"{}\"><div class=\"card\">", paper(s)));
        out.push_str(pic);
        out.push_str("</div></div>");
    }
    out.push_str("</body></html>");
    out
}
