//! **The project's frames and sensors, from its spec sheet** (stage 5 step 4,
//! piece E, 2026-10-15).
//!
//! His answers 20–21 (2026-10-14): a project has **several frames**, written
//! once on the spec sheet (a name and a ratio, one of them Main — the portal
//! shows Main; no resolution, his rule 2026-10-15). **Studio keeps its ratio setting, but
//! it becomes a picker over those frames**, chosen independently of Main; the
//! others can be shown as guide lines. **Sensor size comes from the sheet's
//! sensor mode of the camera** — nothing typed in Studio; squeeze still comes
//! from the lens name (`diagram::lens`).
//!
//! The sheet comes on the **card** (`crate::card`), laid over the film in
//! memory: the project's frames and each camera's sensor, plus a shoot's own
//! when a shoot overrides the sheet (rare). The shoot picked in the picker
//! (`Doc::set_born_in`) reads its own; everything else the project's.
//!
//! **What the film keeps** is only Studio's choice: the frame's name
//! (`studio_frame`) and whether the guides show (`frame_guides`). Picking a
//! frame also writes its ratio into the film's own `aspect_ratio`, so what an
//! older iPhone build, the portal's browser or an export made without a card
//! reads stays the same frame.
//!
//! **Which frame Studio draws at:** the one it picked, by name; else (never
//! picked, or renamed since) the frame whose ratio is the film's own; else
//! Main. A sheet with no frames is one Main frame at the film's own ratio.
//!
//! **No card sheet, nothing changes**: the ratio is the film's own, and every
//! camera reads the sensor typed for it, as before.

use crate::doc::f;
use crate::id::Id;
use crate::json::{self, Json};
use crate::kit::label_key;
use crate::value::Value;
use crate::Doc;

/// One of the project's frames.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Frame {
    pub name: String,
    /// The ratio as the sheet writes it: `2.39:1`, `9:16`.
    pub said: String,
    /// Width over height.
    pub ratio: f64,
    pub main: bool,
}

/// A camera's sensor, off the sheet's sensor mode.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Sensor {
    /// The sheet camera's label, "A Cam".
    pub label: String,
    pub name: String,
    pub w: f64,
    pub h: f64,
}

/// One spec sheet, as the card hands it over.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Sheet {
    pub frames: Vec<Frame>,
    pub sensors: Vec<Sensor>,
}

/// The project's sheet and any shoot's own.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Sheets {
    pub project: Sheet,
    /// A shoot's own sheet, by the shoot's bare id.
    pub shoots: Vec<(String, Sheet)>,
}

/// The most frames a sheet may hold (`MAX.frames` in hub/src/specsheet.js).
const MOST: usize = 8;

fn tidy(said: &str, most: usize) -> String {
    let clean: String = said.chars().map(|c| if c.is_control() { ' ' } else { c }).collect();
    clean.trim().chars().take(most).collect()
}

impl Sheet {
    /// `{frames: [{name, ratio, main}], sensors: [{label, name,
    /// width, height}]}`. A frame with no name, or a ratio that is not one,
    /// is left out; one is always Main when any are left.
    pub fn read(j: &Json) -> Sheet {
        let mut frames: Vec<Frame> = Vec::new();
        for one in j.get("frames").and_then(Json::as_array).unwrap_or(&[]) {
            let name = tidy(one.get("name").and_then(Json::as_str).unwrap_or(""), 40);
            let said = tidy(one.get("ratio").and_then(Json::as_str).unwrap_or(""), 20);
            let Some(ratio) = crate::ratio::parse(&said) else { continue };
            if name.is_empty() || frames.len() >= MOST {
                continue;
            }
            frames.push(Frame {
                name,
                said,
                ratio,
                main: one.get("main").and_then(Json::as_bool).unwrap_or(false),
            });
        }
        let mut seen = false;
        for one in frames.iter_mut() {
            if one.main && seen {
                one.main = false;
            }
            seen |= one.main;
        }
        if !seen {
            if let Some(first) = frames.first_mut() {
                first.main = true;
            }
        }
        let sensors = j
            .get("sensors")
            .and_then(Json::as_array)
            .unwrap_or(&[])
            .iter()
            .filter_map(|s| {
                let label = tidy(s.get("label").and_then(Json::as_str).unwrap_or(""), 60);
                let w = s.get("width").and_then(Json::as_f64).filter(|w| w.is_finite() && *w > 0.0 && *w <= 100.0)?;
                let h = s.get("height").and_then(Json::as_f64).filter(|h| h.is_finite() && *h >= 0.0 && *h <= 100.0).unwrap_or(0.0);
                if label.is_empty() {
                    return None;
                }
                let name = tidy(s.get("name").and_then(Json::as_str).unwrap_or(""), 120);
                Some(Sensor { label, name: if name.is_empty() { format!("{w:.2} mm") } else { name }, w, h })
            })
            .collect();
        Sheet { frames, sensors }
    }
}

impl Sheets {
    /// The card's `sheet`: the project's frames and sensors, and `shoots`
    /// keyed by a shoot's id for a shoot that reads its own. None for
    /// anything that is not an object.
    pub fn read(j: &Json) -> Option<Sheets> {
        if !matches!(j, Json::Object(_)) {
            return None;
        }
        let shoots = match j.get("shoots") {
            Some(Json::Object(pairs)) => pairs
                .iter()
                .filter(|(_, v)| matches!(v, Json::Object(_)))
                .map(|(k, v)| (crate::shoots::bare(k), Sheet::read(v)))
                .filter(|(k, _)| !k.is_empty())
                .collect(),
            _ => Vec::new(),
        };
        Some(Sheets { project: Sheet::read(j), shoots })
    }

    /// Read from text, for checks.
    pub fn parse(text: &str) -> Option<Sheets> {
        Sheets::read(&json::parse(text)?)
    }
}

impl Doc {
    /// **The sheet Studio reads now**: the picked shoot's own, else the
    /// project's. None when the card brings no sheet (an older server, the
    /// switch off, or no card).
    pub fn sheet_now(&self) -> Option<&Sheet> {
        let sheets = self.card.as_ref()?.sheet.as_ref()?;
        if let Some(on) = self.new_in.as_deref() {
            if let Some((_, own)) = sheets.shoots.iter().find(|(id, _)| id == on) {
                return Some(own);
            }
        }
        Some(&sheets.project)
    }

    /// The film's own ratio, as stored.
    pub fn own_ratio(&self) -> Option<f64> {
        self.project_id()
            .and_then(|p| self.get(p))
            .and_then(|r| r.get(f::ASPECT_RATIO))
            .and_then(|v| v.as_float())
            .filter(|r| r.is_finite() && *r > 0.0)
    }

    /// **The project's frames**, as the picker lists them. None with no card
    /// sheet. A sheet with no frames is one Main frame at the film's own ratio.
    pub fn frames(&self) -> Option<Vec<Frame>> {
        let sheet = self.sheet_now()?;
        if !sheet.frames.is_empty() {
            return Some(sheet.frames.clone());
        }
        let ratio = self.own_ratio().unwrap_or(2.39);
        Some(vec![Frame { name: "Main".to_string(), said: ratio_said(ratio), ratio, main: true }])
    }

    /// The frame name Studio picked, as stored ("" when none).
    pub fn studio_frame_said(&self) -> String {
        self.project_id()
            .and_then(|p| self.get(p))
            .and_then(|r| r.text(f::STUDIO_FRAME))
            .unwrap_or("")
            .trim()
            .to_string()
    }

    /// **The frame Studio draws at**: its pick by name; else the one at the
    /// film's own ratio; else Main. None with no card sheet.
    pub fn picked_frame(&self) -> Option<Frame> {
        let frames = self.frames()?;
        let said = self.studio_frame_said().to_lowercase();
        if !said.is_empty() {
            if let Some(one) = frames.iter().find(|x| x.name.trim().to_lowercase() == said) {
                return Some(one.clone());
            }
        }
        if let Some(own) = self.own_ratio() {
            if let Some(one) = frames.iter().find(|x| (x.ratio - own).abs() < 0.005) {
                return Some(one.clone());
            }
        }
        frames.iter().find(|x| x.main).or(frames.first()).cloned()
    }

    /// **The ratio every frame in the film is drawn at** — storyboards,
    /// printed sheets, the diagram's cone, the portal's ratio line. The
    /// picked frame's; with no card sheet, the film's own (2.39 when unset).
    pub fn film_ratio(&self) -> f64 {
        self.film_ratio_said().unwrap_or(2.39)
    }

    /// The same, or None when neither the sheet nor the film says one.
    pub fn film_ratio_said(&self) -> Option<f64> {
        match self.picked_frame() {
            Some(frame) => Some(frame.ratio),
            None => self.own_ratio(),
        }
    }

    /// **Pick the frame Studio draws at**, by name. One undo step: the name,
    /// and its ratio into the film's own `aspect_ratio` (for readers with no
    /// card). False when the project has no such frame.
    pub fn pick_frame(&mut self, name: &str) -> bool {
        let Some(project) = self.project_id() else { return false };
        let want = name.trim().to_lowercase();
        let Some(frame) = self.frames().and_then(|l| l.into_iter().find(|x| x.name.trim().to_lowercase() == want)) else {
            return false;
        };
        let tx = self.begin("Studio Frame");
        self.set(project, f::STUDIO_FRAME, Value::text(frame.name.clone()));
        if self.own_ratio().map(|r| (r - frame.ratio).abs() > 1e-9).unwrap_or(true) {
            self.set(project, f::ASPECT_RATIO, Value::Float(frame.ratio));
        }
        self.end(tx);
        true
    }

    /// Whether the other frames show as guide lines.
    pub fn frame_guides(&self) -> bool {
        self.project_id().and_then(|p| self.get(p)).map(|r| r.bool(f::FRAME_GUIDES)).unwrap_or(false)
    }

    /// Show or hide the guide lines. One undo step.
    pub fn set_frame_guides(&mut self, on: bool) -> bool {
        let Some(project) = self.project_id() else { return false };
        if self.frame_guides() == on {
            return true;
        }
        let tx = self.begin(if on { "Show Frame Guides" } else { "Hide Frame Guides" });
        self.set(project, f::FRAME_GUIDES, Value::Bool(on));
        self.end(tx);
        true
    }

    /// **The sheet's sensor for one of the film's cameras**, matched by name
    /// ("A-Cam" is the sheet's "A Cam"). None when the card brings no sheet,
    /// the sheet does not name the camera, or names no sensor mode for it.
    pub fn sheet_sensor(&self, unit: Id) -> Option<&Sensor> {
        let sheet = self.sheet_now()?;
        let label = self.get(unit).and_then(|r| r.text(f::LABEL)).map(label_key)?;
        if label.is_empty() {
            return None;
        }
        sheet.sensors.iter().find(|s| label_key(&s.label) == label)
    }

    /// Whether a camera's sensor is the sheet's (shells show it, never type it).
    pub fn sensor_from_sheet(&self, unit: Id) -> bool {
        self.sheet_sensor(unit).is_some()
    }

    /// Whether the card brings a sheet at all: sensors are the sheet's to
    /// set, and Studio's own typing stands down.
    pub fn sensors_from_sheet(&self) -> bool {
        self.sheet_now().is_some()
    }
}

/// `2.39` → `2.39:1`; `0.5625` → `9:16`-ish as `0.56:1`.
pub fn ratio_said(r: f64) -> String {
    let n = (r * 100.0).round() / 100.0;
    format!("{}:1", n)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::card::Card;
    use crate::stamp::DeviceId;

    fn film(own: Option<f64>) -> Doc {
        film_and_units(own).0
    }

    fn film_and_units(own: Option<f64>) -> (Doc, Id, Id) {
        let mut d = Doc::new(DeviceId(1));
        let p = d.create_project("Daybreak");
        if let Some(r) = own {
            d.set(p, f::ASPECT_RATIO, Value::Float(r));
        }
        let a = d.create_unit("A-Cam", "");
        let b = d.create_unit("B Camera", "");
        d.clear_history();
        (d, a, b)
    }

    const TWO: &str = r#"{"facts":{},"sheet":{"frames":[{"name":"Delivery","ratio":"2.39:1","main":true},{"name":"Social","ratio":"9:16","main":false},{"name":"","ratio":"1.85:1"},{"name":"Bad","ratio":"wide"}],"sensors":[{"label":"A Cam","name":"Open Gate","width":36.7,"height":25.54}],"shoots":{"aaaaaaaabbbbbbbbccccccccdddddddd":{"frames":[{"name":"Pickup","ratio":"1.85:1","main":true}],"sensors":[]}}},"shoots":[{"id":"aaaaaaaabbbbbbbbccccccccdddddddd","label":"Pickups","start":"2026-11-01"},{"id":"11111111222222223333333344444444","label":"Principal","start":"2026-10-01"}]}"#;

    #[test]
    fn no_sheet_on_the_card_changes_nothing() {
        let mut d = film(Some(1.85));
        assert!(d.frames().is_none());
        assert!((d.film_ratio() - 1.85).abs() < 1e-9);
        d.set_card(Card::read(r#"{"facts":{}}"#));
        assert!(d.frames().is_none());
        assert!((d.film_ratio() - 1.85).abs() < 1e-9);
        let fresh = film(None);
        assert!((fresh.film_ratio() - 2.39).abs() < 1e-9);
        assert_eq!(fresh.film_ratio_said(), None);
    }

    #[test]
    fn the_sheet_frames_are_read_and_the_bad_ones_left_out() {
        let mut d = film(None);
        d.set_card(Card::read(TWO));
        let frames = d.frames().unwrap();
        assert_eq!(frames.iter().map(|f| f.name.as_str()).collect::<Vec<_>>(), ["Delivery", "Social"]);
        assert!(frames[0].main && !frames[1].main);
        assert!((frames[1].ratio - 0.5625).abs() < 1e-9);
    }

    #[test]
    fn unpicked_it_keeps_the_frame_at_the_films_own_ratio_else_main() {
        let mut d = film(Some(0.5625));
        d.set_card(Card::read(TWO));
        assert_eq!(d.picked_frame().unwrap().name, "Social");
        let mut e = film(Some(1.66));
        e.set_card(Card::read(TWO));
        assert_eq!(e.picked_frame().unwrap().name, "Delivery");
        assert!((e.film_ratio() - 2.39).abs() < 1e-9);
    }

    #[test]
    fn picking_is_one_undo_step_and_writes_the_ratio_underneath() {
        let mut d = film(Some(2.39));
        d.set_card(Card::read(TWO));
        assert!(d.pick_frame("social"));
        assert_eq!(d.picked_frame().unwrap().name, "Social");
        assert!((d.own_ratio().unwrap() - 0.5625).abs() < 1e-9, "older readers see the same frame");
        assert!(!d.pick_frame("Nope"));
        d.undo();
        assert_eq!(d.studio_frame_said(), "");
        assert!((d.own_ratio().unwrap() - 2.39).abs() < 1e-9);
    }

    #[test]
    fn a_renamed_frame_falls_back_by_ratio() {
        let mut d = film(None);
        d.set_card(Card::read(TWO));
        d.pick_frame("Social");
        d.set_card(Card::read(&TWO.replace("\"Social\"", "\"Vertical\"")));
        assert_eq!(d.picked_frame().unwrap().name, "Vertical");
    }

    #[test]
    fn a_sheet_with_no_frames_is_one_main_at_the_films_ratio() {
        let mut d = film(Some(1.85));
        d.set_card(Card::read(r#"{"sheet":{"frames":[],"sensors":[]}}"#));
        let frames = d.frames().unwrap();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].name, "Main");
        assert!((d.film_ratio() - 1.85).abs() < 1e-9);
    }

    #[test]
    fn the_picked_shoot_reads_its_own_sheet() {
        let mut d = film(None);
        d.set_card(Card::read(TWO));
        d.set_born_in(Some("aaaaaaaabbbbbbbbccccccccdddddddd"));
        assert_eq!(d.frames().unwrap()[0].name, "Pickup");
        assert!((d.film_ratio() - 1.85).abs() < 1e-9);
        d.set_born_in(Some("11111111222222223333333344444444"));
        assert_eq!(d.frames().unwrap()[0].name, "Delivery");
        d.set_born_in(None);
        assert_eq!(d.frames().unwrap()[0].name, "Delivery");
    }

    #[test]
    fn a_camera_reads_the_sheets_sensor_by_name() {
        let (mut d, a, b) = film_and_units(None);
        d.set_unit_sensor(b, "Super 35", 24.89, 18.66);
        d.set_card(Card::read(TWO));
        assert!(d.sensor_from_sheet(a));
        assert_eq!(d.unit_sensor(a), Some(("Open Gate".to_string(), 36.7, 25.54)));
        assert!(!d.sensor_from_sheet(b), "the sheet names no sensor for B Cam");
        assert_eq!(d.unit_sensor(b).map(|s| s.0), Some("Super 35".to_string()));
        d.set_card(None);
        assert_eq!(d.unit_sensor(a), None);
    }

    #[test]
    fn guides_are_one_undo_step() {
        let mut d = film(None);
        assert!(!d.frame_guides());
        d.set_frame_guides(true);
        assert!(d.frame_guides());
        d.undo();
        assert!(!d.frame_guides());
    }
}
