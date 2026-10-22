//! **Favorites** — nine slots of pieces kept ready, Scenario's: a lamp rigged
//! the way he likes it, a camera in his colour, a 12×12 of silk with its gel.
//! Keys 1–9 put one down under the pointer.
//!
//! They belong to the film, not to one scene's plan or to this Mac: they are
//! one field on the project record (`diagram_favorites`), so they travel with
//! the film, sync like everything else, and a change to them is one step of
//! undo. A slot keeps what a piece *is* — its kind, drawing, name, colour,
//! size, gels, a frame's skin and lean, a lamp's beam, reach and Kelvin —
//! and never where it stood, its beats, its shot or what it was aimed at.

use super::{symbols, Diagram, El, Kind};
use crate::doc::Doc;
use crate::Id;
use crate::json::{self, Json};

pub const SLOTS: usize = 9;
const FIELD: &str = "diagram_favorites";

/// What a slot keeps of a piece: everything but where it stood. A line keeps
/// its run from nought, a drawn stroke its points about its middle.
pub fn keep(el: &El) -> Json {
    let mut e = el.clone();
    if e.kind.is_line() {
        let (x0, y0) = (e.x, e.y);
        e.translate(-x0, -y0);
    } else {
        let (cx, cy) = e.centre();
        for p in &mut e.points {
            p.0 -= cx;
            p.1 -= cy;
        }
        (e.x, e.y) = (0.0, 0.0);
        e.rot = 0.0;
    }
    e.steps.clear();
    e.lead = 0;
    e.beat = 1;
    e.shot.clear();
    e.aim.clear();
    e.group.clear();
    e.rig_on.clear();
    e.start_on.clear();
    e.end_on.clear();
    e.locked = false;
    e.hidden = false;
    let mut j = e.to_json();
    if let Json::Object(pairs) = &mut j {
        pairs.retain(|(k, _)| k != "id");
    }
    j
}

/// **A group kept as one favorite** (his ask, 2026-10-04: a curved driveway
/// into a building, "grouped together as sort of an object"): every piece
/// about the group's middle, ties between them kept by their own short ids,
/// and the group's name. `{"kind":"group","group_name":…,"els":[…]}`.
pub fn keep_group(pieces: &[El], name: &str) -> Json {
    let n = pieces.len().max(1) as f64;
    let (cx, cy) = pieces.iter().map(|e| e.centre()).fold((0.0, 0.0), |a, c| (a.0 + c.0 / n, a.1 + c.1 / n));
    let short: Vec<(String, String)> = pieces.iter().enumerate().map(|(i, e)| (e.id.clone(), format!("f{}", i + 1))).collect();
    let own = |id: &str| short.iter().find(|(from, _)| from == id).map(|(_, to)| to.clone()).unwrap_or_default();
    let els = pieces
        .iter()
        .map(|p| {
            let mut e = p.clone();
            e.translate(-cx, -cy);
            e.id = own(&p.id);
            e.tie_to = own(&p.tie_to);
            e.rig_on = own(&p.rig_on);
            e.aim = own(&p.aim);
            e.start_on = own(&p.start_on);
            e.end_on = own(&p.end_on);
            e.group.clear();
            e.group_name.clear();
            e.shot.clear();
            e.steps.clear();
            e.locked = false;
            e.hidden = false;
            e.to_json()
        })
        .collect();
    Json::object(vec![("kind", Json::text("group")), ("group_name", Json::text(name)), ("els", Json::Array(els))])
}

fn group_of(fav: &Json) -> Option<(String, Vec<El>)> {
    if fav.str_field("kind") != "group" {
        return None;
    }
    let els: Vec<El> = fav.get("els")?.as_array()?.iter().filter_map(El::from_json).collect();
    (!els.is_empty()).then(|| (fav.str_field("group_name"), els))
}

/// **A slot made ready to put down**, middle at `x`, `y`: the `add` edit
/// that places it — one piece, or a group's pieces added as one group.
pub fn placed_op(fav: &Json, x: f64, y: f64) -> Option<Json> {
    if let Some((name, els)) = group_of(fav) {
        let els = els
            .into_iter()
            .map(|mut e| {
                e.translate(x, y);
                e.tame();
                e.to_json()
            })
            .collect();
        let name = if name.trim().is_empty() { "Group".to_string() } else { name };
        return Some(Json::object(vec![("op", Json::text("add")), ("els", Json::Array(els)), ("group_name", Json::text(&name)), ("fresh", Json::Bool(true))]));
    }
    let el = placed(fav, x, y)?;
    Some(Json::object(vec![("op", Json::text("add")), ("els", Json::Array(vec![el]))]))
}

fn read(fav: &Json) -> Option<El> {
    if let Some((_, els)) = group_of(fav) {
        return els.into_iter().next();
    }
    let Json::Object(pairs) = fav else { return None };
    let mut pairs = pairs.clone();
    pairs.retain(|(k, _)| k != "id");
    pairs.push(("id".into(), Json::text("fav")));
    El::from_json(&Json::Object(pairs))
}

/// A slot's piece, ready to add with its middle at `x`, `y`. A camera brings
/// its own shot, as one put down with the Camera tool does.
pub fn placed(fav: &Json, x: f64, y: f64) -> Option<Json> {
    if group_of(fav).is_some() {
        return None;
    }
    let mut el = read(fav)?;
    if el.kind.is_line() {
        let (cx, cy) = el.centre();
        el.translate(x - cx, y - cy);
    } else {
        el.translate(x, y);
    }
    el.tame();
    let mut j = el.to_json();
    if let Json::Object(pairs) = &mut j {
        pairs.retain(|(k, _)| k != "id");
        if el.kind == Kind::Camera {
            pairs.push(("new_shot".into(), Json::Bool(true)));
        }
    }
    Some(j)
}

/// What a slot is called: its name if it has one, its words, its drawing's
/// name, else its kind.
pub fn name(fav: &Json) -> String {
    if let Some((name, _)) = group_of(fav) {
        return if name.trim().is_empty() { "Group".into() } else { name };
    }
    let Some(el) = read(fav) else { return String::new() };
    if !el.label.trim().is_empty() {
        return el.label.trim().to_string();
    }
    if matches!(el.kind, Kind::Text | Kind::Note) && !el.text.trim().is_empty() {
        return el.text.lines().next().unwrap_or("").trim().to_string();
    }
    if super::frame::is_frame(&el) {
        return super::frame::plan_name(&el);
    }
    if symbols::is_half_round(&el) {
        return symbols::half_round_name(&el);
    }
    let sym = symbols::plan_name(&el.sym);
    if !sym.is_empty() {
        return sym;
    }
    match el.kind {
        Kind::Set => "Set Piece".into(),
        Kind::Cast => "Person".into(),
        k => {
            let s = k.as_str();
            s[..1].to_uppercase() + &s[1..]
        }
    }
}

impl Doc {
    /// The film's nine slots, empty ones `None`.
    pub fn diagram_favorites(&self) -> Vec<Option<Json>> {
        let stored = self
            .project_id()
            .and_then(|p| self.get(p))
            .and_then(|r| r.text(FIELD))
            .and_then(json::parse);
        let list = stored.as_ref().and_then(|j| j.as_array()).unwrap_or(&[]);
        (0..SLOTS).map(|i| list.get(i).filter(|v| read(v).is_some()).cloned()).collect()
    }

    /// **A piece from a scene's plan into a slot** — and a piece in a group
    /// brings its whole group, kept as one favorite.
    pub fn set_diagram_favorite_from(&mut self, slot: usize, scene: Id, piece: Option<&El>) -> bool {
        if let Some(p) = piece.filter(|p| !p.group.is_empty()) {
            let plan: Diagram = self.diagram(scene);
            let members: Vec<El> = plan.els.iter().filter(|e| e.group == p.group).cloned().collect();
            if members.len() > 1 {
                return self.keep_favorite(slot, Some(keep_group(&members, &p.group_name)));
            }
        }
        self.set_diagram_favorite(slot, piece)
    }

    /// Put a piece in a slot, or empty it — one step of undo. False when
    /// there is no such slot or no film to keep it in.
    pub fn set_diagram_favorite(&mut self, slot: usize, piece: Option<&El>) -> bool {
        self.keep_favorite(slot, piece.map(keep))
    }

    fn keep_favorite(&mut self, slot: usize, kept: Option<Json>) -> bool {
        let Some(project) = self.project_id() else { return false };
        if slot >= SLOTS {
            return false;
        }
        let mut slots = self.diagram_favorites();
        let adding = kept.is_some();
        slots[slot] = kept;
        let text = Json::Array(slots.into_iter().map(|s| s.unwrap_or(Json::Null)).collect()).encode();
        let tx = self.begin(if adding { "Add to Favorites" } else { "Remove Favorite" });
        self.set(project, FIELD, text);
        self.end(tx);
        true
    }
}
