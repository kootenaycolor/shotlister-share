//! **The kit: what the film's shots pick from, off its Camera Spec Sheets.**
//!
//! Ref 1627, his words 2026-10-08: *"The spec sheet could also feed the
//! lenses in Shotlister and diagrams and vice versa. Like the selected cams,
//! lenses should feed the spec sheet (if chosen)."*
//!
//! ## Where the spec sheet lives, and where it does not
//!
//! One Notion row per shoot (Camera Spec Sheets). Notion is its only home;
//! Projects Console on the Studio Mac is the one thing that writes it, and the
//! portal's card holds what it said at the last refresh. **The film keeps no
//! copy of the sheet.** What it keeps is the *kit* — each shoot's lenses
//! broken into picks and its cameras as name and body — mirrored here the way
//! `crate::recordfacts` mirrors the director: the portal hands it over (the
//! Mac asks the hub's kit door and passes it through `recordkit`), this module
//! writes it down, and nothing in the film lets anyone type over it. Changing
//! the kit means changing the sheet, which goes back the other way as an edit
//! the Studio writes into Notion.
//!
//! ## What taking the kit does
//!
//! - **Lenses go on the film's Lens list**, by focal length, never removing
//!   one: the film's own extras with no place on a spec sheet (Diopter,
//!   Probe) stay. A locked list is not grown — the lock is a decision — and
//!   the answer says so.
//! - **Cameras fill the film's cameras.** "A Cam: Alexa 35" gives the camera
//!   called A-Cam (or A Cam, or A-Camera) the body Alexa 35, making it if the
//!   film has none; an unlabelled body is the A camera's. Bodies are the lead
//!   shoot's when shoots disagree. A camera the sheet does not name is left
//!   alone, and nothing is ever deleted. A diagram's camera is one of these,
//!   so it carries the body with it.
//! - **No undo step**, as with the record's facts: writing down what the
//!   sheet already says is not something he did here.
//!
//! - **Modifiers and filters go on their own lists** (his ask, 2026-10-14):
//!   the sheet says what the shoot carries ("Atlas LF Extender 1.6x",
//!   "Tiffen ND .6"), a shot says what it uses. Same rules as lenses, by the
//!   sheet's exact name, a locked list left alone.
//! - **What leaves the sheet leaves the list** (Kit Links, 2026-10-14: *one
//!   home*). A lens, modifier or filter the kit had last time and has no
//!   longer comes off its list, unless a shot uses it — then it stays, and the
//!   shells mark it Not on Sheet. The film's own extras were never on a sheet,
//!   so they are never taken off.
//! - **A name glued from a whole box is split** ("Master Prime 16mm, Master
//!   Prime 18mm, …" as one lens, 2026-10-13): a kit name with a comma in it is
//!   read as several. No lens, modifier or filter is named with a comma.
//!
//! ## The other way: what a shot uses that the kit does not have
//!
//! `off_kit` says, for one shot, whether its lens or its camera's body is
//! missing from the kit of the shoot its day falls in (by date), or from the
//! whole film's when its day belongs to no shoot. The shells offer **Add to
//! Spec Sheet** for it — offered, never done: a shot's lens can be a wish or
//! a typo, and the sheet goes to the rental house.

use crate::doc::f;
use crate::id::Id;
use crate::json::{self, Json};
use crate::store::Kind;
use crate::value::Value;
use crate::vocab;
use crate::Doc;

/// Where the kit is kept on the project record: the JSON `recordkit` was
/// handed, tidied. Empty: the film has no kit.
pub const KIT: &str = "kit";

/// Where the film's Spec Sheet switch is kept on the project record.
pub const KIT_MODE: &str = "kit_mode";

/// **The film's Spec Sheet switch** (his ruling, 2026-10-13): *"He does not
/// want it syncing on every project."* Off, nothing flows between the sheet
/// and the film either way; Ask, the shells say what changed and he takes it
/// with one click; Follow, the film takes the kit on open and every few
/// minutes, as every linked film did before the switch. **Off is the
/// default**, and every film written before the switch existed says nothing,
/// so is Off: his call for the films already linked.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KitMode {
    Off,
    Ask,
    Follow,
}

impl KitMode {
    pub fn as_str(self) -> &'static str {
        match self {
            KitMode::Off => "off",
            KitMode::Ask => "ask",
            KitMode::Follow => "follow",
        }
    }

    /// `ask` and `follow` as said; anything else, or nothing, is Off.
    pub fn read(said: &str) -> KitMode {
        match said.trim().to_ascii_lowercase().as_str() {
            "ask" => KitMode::Ask,
            "follow" => KitMode::Follow,
            _ => KitMode::Off,
        }
    }
}

/// The colours a new camera wears, in turn — the table's palette.
const COLOURS: [&str; 6] = ["E5484D", "D97706", "16A34A", "0A6CE8", "7B4BC4", "DB2777"];

/// The longest a kit may be, as kept: a few shoots of a few lines each.
const LONGEST: usize = 40_000;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct KitCamera {
    pub label: String,
    pub body: String,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct KitShoot {
    pub name: String,
    pub start: String,
    pub end: String,
    pub sheet: String,
    pub lead: bool,
    pub cameras: Vec<KitCamera>,
    pub lenses: Vec<String>,
    /// Extenders, expanders, diopters the shoot carries, by full name.
    pub modifiers: Vec<String>,
    /// Filters the shoot carries, by full name, one per strength.
    pub filters: Vec<String>,
}

/// What taking a kit did, for the answer.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct KitTaken {
    pub kit_changed: bool,
    pub lenses_added: Vec<String>,
    pub lens_list_locked: Vec<String>,
    /// Cameras the sheet names that were not made, because he has locked the
    /// Camera list (2026-10-13: the sheet never gets round a lock).
    pub camera_list_locked: Vec<String>,
    pub cameras_made: Vec<String>,
    pub bodies_set: Vec<String>,
    pub modifiers_added: Vec<String>,
    pub modifier_list_locked: Vec<String>,
    pub filters_added: Vec<String>,
    pub filter_list_locked: Vec<String>,
    /// Off the sheet since last time, and on no shot: off their lists.
    pub removed: Vec<String>,
}

impl KitTaken {
    pub fn changed(&self) -> bool {
        self.kit_changed
            || !self.removed.is_empty()
            || !self.lenses_added.is_empty()
            || !self.cameras_made.is_empty()
            || !self.bodies_set.is_empty()
            || !self.modifiers_added.is_empty()
            || !self.filters_added.is_empty()
    }
}

/// What one shot uses that its kit does not have.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct OffKit {
    /// The shoot whose sheet it would go on (an index into `kit()`).
    pub shoot: usize,
    pub lens: Option<String>,
    /// The camera's name and its body.
    pub camera: Option<(String, String)>,
    /// The shot's modifiers that sheet does not carry.
    pub modifiers: Vec<String>,
    /// The shot's filters that sheet does not carry.
    pub filters: Vec<String>,
}

fn tidy(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// How lenses are compared: "35 MM", "35mm" and "35" are one lens; an en
/// dash is a hyphen.
pub fn lens_key(s: &str) -> String {
    let mut k = tidy(s).to_lowercase().replace('–', "-");
    if k.ends_with(" mm") {
        k = format!("{}mm", &k[..k.len() - 3]);
    }
    if !k.is_empty() && k.chars().all(|c| c.is_ascii_digit() || c == '.' || c == '-') {
        k.push_str("mm");
    }
    k
}

/// Whether a shot's lens is one of the kit's picks: the same lens, or one
/// naming the other with its maker ("Cooke 32mm" and "32mm", "45-165mm" and
/// "Angenieux 45-165mm").
pub fn lens_in(picks: &[String], lens: &str) -> bool {
    let want = lens_key(lens);
    if want.is_empty() {
        return true;
    }
    picks.iter().map(|p| lens_key(p)).any(|have| {
        have == want || have.ends_with(&format!(" {want}")) || want.ends_with(&format!(" {have}"))
    })
}

/// How modifiers and filters are compared: case and spacing aside, as named.
pub fn name_key(s: &str) -> String {
    tidy(s).to_lowercase().replace('–', "-")
}

/// Whether a shot's modifier or filter is one the kit carries: the same name,
/// or one naming the other with its maker ("ND .6" and "Tiffen ND .6",
/// "1.6x" and "Atlas LF Extender 1.6x").
pub fn name_in(picks: &[String], said: &str) -> bool {
    let want = name_key(said);
    if want.is_empty() {
        return true;
    }
    picks.iter().map(|p| name_key(p)).any(|have| {
        have == want || have.ends_with(&format!(" {want}")) || want.ends_with(&format!(" {have}"))
    })
}

/// The names a kit entry says: itself, or several when a whole box was
/// glued into one with commas.
fn pieces(said: &str) -> Vec<String> {
    said.split(',').map(tidy).filter(|p| !p.is_empty()).collect()
}

/// A list of names off the kit, tidied, each once.
fn names(one: &Json, key: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for l in one.get(key).and_then(|c| c.as_array()).unwrap_or(&[]) {
        for l in pieces(l.as_str().unwrap_or("")) {
            if !out.iter().any(|h| name_key(h) == name_key(&l)) {
                out.push(l);
            }
        }
    }
    out
}

/// How cameras' names are matched: "A-Camera" = "A Cam" = "a cam".
pub fn label_key(s: &str) -> String {
    let k: String = s.to_lowercase().chars().filter(|c| c.is_ascii_alphanumeric()).collect();
    k.replacen("camera", "cam", 1)
}

fn body_key(s: &str) -> String {
    tidy(s).to_lowercase()
}

/// The kit as kept, read back. Anything unreadable is no kit.
pub fn parse(text: &str) -> Result<Vec<KitShoot>, String> {
    let said = json::parse(text).ok_or("the kit is not JSON")?;
    let list = said.as_array().ok_or("the kit is a list of shoots")?;
    let text_of = |j: &Json, k: &str| tidy(j.get(k).and_then(|v| v.as_str()).unwrap_or(""));
    let mut out = Vec::new();
    for one in list {
        if !matches!(one, Json::Object(_)) {
            return Err("a shoot in the kit is an object".into());
        }
        let cameras = one
            .get("cameras")
            .and_then(|c| c.as_array())
            .unwrap_or(&[])
            .iter()
            .map(|c| KitCamera { label: text_of(c, "label"), body: text_of(c, "body") })
            .filter(|c| !c.body.is_empty())
            .collect();
        let mut lenses: Vec<String> = Vec::new();
        for l in one.get("lenses").and_then(|c| c.as_array()).unwrap_or(&[]) {
            for l in pieces(l.as_str().unwrap_or("")) {
                if !lenses.iter().any(|h| lens_key(h) == lens_key(&l)) {
                    lenses.push(l);
                }
            }
        }
        out.push(KitShoot {
            name: text_of(one, "name"),
            start: text_of(one, "start"),
            end: text_of(one, "end"),
            sheet: text_of(one, "sheet"),
            lead: one.get("lead").and_then(|v| v.as_bool()).unwrap_or(false),
            cameras,
            lenses,
            modifiers: names(one, "modifiers"),
            filters: names(one, "filters"),
        });
    }
    Ok(out)
}

/// The kit in the one shape it is kept and shown in.
pub fn encode(kit: &[KitShoot]) -> String {
    Json::Array(
        kit.iter()
            .map(|s| {
                let mut pairs = vec![
                    ("name", Json::text(&s.name)),
                    ("start", Json::text(&s.start)),
                    ("end", Json::text(&s.end)),
                    ("sheet", Json::text(&s.sheet)),
                    ("lead", Json::Bool(s.lead)),
                    (
                        "cameras",
                        Json::Array(
                            s.cameras
                                .iter()
                                .map(|c| Json::object(vec![("label", Json::text(&c.label)), ("body", Json::text(&c.body))]))
                                .collect(),
                        ),
                    ),
                    ("lenses", Json::Array(s.lenses.iter().map(Json::text).collect())),
                ];
                // Only when there are some, so a kit from before modifiers
                // and filters is kept exactly as it was.
                if !s.modifiers.is_empty() {
                    pairs.push(("modifiers", Json::Array(s.modifiers.iter().map(Json::text).collect())));
                }
                if !s.filters.is_empty() {
                    pairs.push(("filters", Json::Array(s.filters.iter().map(Json::text).collect())));
                }
                Json::object(pairs)
            })
            .collect(),
    )
    .encode()
}

/// "A Cam", "B Cam"… for the unlabelled bodies of a sheet, in order.
fn letter_label(n: usize) -> String {
    format!("{}-Cam", (b'A' + (n.min(25)) as u8) as char)
}

/// The cameras the kit names, each once by name: the lead shoot's first, so
/// its bodies win where shoots disagree.
fn kit_cameras(kit: &[KitShoot]) -> Vec<KitCamera> {
    let mut order: Vec<&KitShoot> = kit.iter().filter(|s| s.lead).collect();
    order.extend(kit.iter().filter(|s| !s.lead));
    let mut out: Vec<KitCamera> = Vec::new();
    for shoot in order {
        let mut unlabelled = 0;
        for c in &shoot.cameras {
            let label = if c.label.is_empty() {
                unlabelled += 1;
                letter_label(unlabelled - 1)
            } else {
                c.label.clone()
            };
            if out.iter().any(|h| label_key(&h.label) == label_key(&label)) {
                continue;
            }
            out.push(KitCamera { label, body: c.body.clone() });
        }
    }
    out
}

impl Doc {
    /// The film's Spec Sheet switch. A film with no project record is Off.
    ///
    /// **Unsaid, a film backed by the shared project record follows** (his
    /// ask, 2026-10-16: Call Her Back could not follow its live sheet). The
    /// card laid on says the film is that project's; its sheet is the one
    /// home of its lenses, so the lists follow it unless he has said Off or
    /// Ask. Taking the kit only adds, and takes off only what an earlier
    /// sheet put there and no shot uses, so his own terms stay. A film with
    /// no card keeps the old default, Off.
    pub fn kit_mode(&self) -> KitMode {
        let said = self.project_id().and_then(|p| self.get(p)).and_then(|r| r.text(KIT_MODE));
        match said {
            Some(said) if !said.trim().is_empty() => KitMode::read(said),
            _ if self.card().is_some() => KitMode::Follow,
            _ => KitMode::Off,
        }
    }

    /// **Set the film's Spec Sheet switch.** Undoable; it changes nothing
    /// else. Turning it Off keeps the lens list and the cameras as they are.
    pub fn set_kit_mode(&mut self, mode: KitMode) {
        let Some(project) = self.project_id() else {
            return;
        };
        if self.kit_mode() == mode {
            return;
        }
        let tx = self.begin("Set spec sheet switch");
        self.set(project, KIT_MODE, mode.as_str());
        self.end(tx);
    }

    /// **The film's kit**, as last taken. Empty when it has none.
    pub fn kit(&self) -> Vec<KitShoot> {
        let Some(project) = self.project_id() else {
            return Vec::new();
        };
        let held = self.get(project).and_then(|r| r.text(KIT)).unwrap_or("");
        if held.trim().is_empty() {
            return Vec::new();
        }
        parse(held).unwrap_or_default()
    }

    /// **Take the kit** — the portal's word for each shoot's spec sheet,
    /// broken into picks. Checked whole before anything is written. Cameras
    /// are only ever added or given a body; a lens, modifier or filter that
    /// left the sheet since last time comes off its list when no shot uses it.
    pub fn take_kit(&mut self, said: &str) -> Result<KitTaken, String> {
        let project = self.project_id().ok_or("this film has no project record")?;
        let kit = parse(said)?;
        let kept = if kit.is_empty() { String::new() } else { encode(&kit) };
        if kept.len() > LONGEST {
            return Err("the kit is too long to be a spec sheet".into());
        }
        let mut taken = KitTaken::default();
        let held = self.get(project).and_then(|r| r.text(KIT)).unwrap_or("").to_string();
        if held != kept {
            self.write_without_recording(project, KIT, Value::Text(kept));
            taken.kit_changed = true;
        }

        // What left the sheet since last time leaves its list, when no shot
        // uses it. Only what a sheet put there: the film's own never were.
        let was = if held.trim().is_empty() { Vec::new() } else { parse(&held).unwrap_or_default() };
        let lenses_now: Vec<String> = kit.iter().flat_map(|s| s.lenses.iter().cloned()).collect();
        let lenses_was: Vec<String> = was.iter().flat_map(|s| s.lenses.iter().cloned()).collect();
        let gone = |was: &[String], now: &[String], key: fn(&str) -> String| -> Vec<String> {
            was.iter().filter(|w| !now.iter().any(|n| key(n) == key(w))).cloned().collect()
        };
        let lenses_gone = gone(&lenses_was, &lenses_now, lens_key);
        let mut removed = self.drop_gone(project, vocab::LENS, &lenses_gone, lens_key);
        let carried = |k: &[KitShoot], m: bool| -> Vec<String> {
            k.iter().flat_map(|s| if m { s.modifiers.iter() } else { s.filters.iter() }).cloned().collect()
        };
        for (list_name, m) in [(vocab::MODIFIERS, true), (vocab::LENS_FILTERS, false)] {
            let went = gone(&carried(&was, m), &carried(&kit, m), name_key);
            removed.extend(self.drop_gone(project, list_name, &went, name_key));
        }
        taken.removed = removed;

        // Lenses, onto the list by focal length.
        let mut list = self.vocabulary(vocab::LENS);
        let mut new: Vec<String> = Vec::new();
        for shoot in &kit {
            for lens in &shoot.lenses {
                let known = list.iter().chain(new.iter()).any(|h| lens_key(h) == lens_key(lens));
                if !known {
                    new.push(lens.clone());
                }
            }
        }
        if !new.is_empty() {
            if self.vocabulary_locked(vocab::LENS) {
                taken.lens_list_locked = new;
            } else {
                for lens in &new {
                    let at = vocab::place_by_number(&list, lens);
                    list.insert(at, lens.clone());
                }
                let value = Value::List(list.into_iter().map(Value::Text).collect());
                self.write_without_recording(project, &vocab::key(vocab::LENS), value);
                taken.lenses_added = new;
            }
        }

        // Modifiers and filters, onto their own lists by the sheet's name.
        let modifiers: Vec<String> = kit.iter().flat_map(|s| s.modifiers.iter().cloned()).collect();
        let (added, locked) = self.take_names(project, vocab::MODIFIERS, &modifiers);
        taken.modifiers_added = added;
        taken.modifier_list_locked = locked;
        let filters: Vec<String> = kit.iter().flat_map(|s| s.filters.iter().cloned()).collect();
        let (added, locked) = self.take_names(project, vocab::LENS_FILTERS, &filters);
        taken.filters_added = added;
        taken.filter_list_locked = locked;

        // Cameras, by name; a body given where the sheet says one.
        for cam in kit_cameras(&kit) {
            let units: Vec<Id> = self
                .store()
                .of_kind(&Kind::Unit)
                .into_iter()
                .filter(|r| r.text(f::LABEL).map(|l| !l.trim().is_empty()).unwrap_or(false))
                .map(|r| r.id)
                .collect();
            let text = |d: &Doc, id: Id, field: &str| d.get(id).and_then(|r| r.text(field)).unwrap_or("").to_string();
            match units.iter().find(|u| label_key(&text(self, **u, f::LABEL)) == label_key(&cam.label)) {
                Some(unit) => {
                    if body_key(&text(self, *unit, f::BODY)) != body_key(&cam.body) {
                        self.write_without_recording(*unit, f::BODY, Value::text(cam.body.as_str()));
                        taken.bodies_set.push(format!("{} {}", text(self, *unit, f::LABEL), cam.body));
                    }
                }
                None if self.vocabulary_locked(f::UNIT) => {
                    taken.camera_list_locked.push(format!("{} {}", cam.label, cam.body));
                }
                None => {
                    let unit = self.create_quietly(Kind::Unit);
                    self.write_without_recording(unit, f::LABEL, Value::text(cam.label.as_str()));
                    self.write_without_recording(unit, f::BODY, Value::text(cam.body.as_str()));
                    self.write_without_recording(unit, f::COLOUR, Value::text(COLOURS[units.len() % COLOURS.len()]));
                    taken.cameras_made.push(format!("{} {}", cam.label, cam.body));
                }
            }
        }
        Ok(taken)
    }

    /// Take off a list the terms that left the sheet, matched by `key`, when
    /// no shot or scene uses them. What came off, in list order.
    fn drop_gone(&mut self, project: Id, list_name: &str, gone: &[String], key: fn(&str) -> String) -> Vec<String> {
        if gone.is_empty() {
            return Vec::new();
        }
        let list = self.vocabulary(list_name);
        let (off, keep): (Vec<String>, Vec<String>) = list.into_iter().partition(|term| {
            gone.iter().any(|g| key(g) == key(term)) && self.carrying(list_name, term).is_empty()
        });
        if !off.is_empty() {
            let value = Value::List(keep.into_iter().map(Value::Text).collect());
            self.write_without_recording(project, &vocab::key(list_name), value);
        }
        off
    }

    /// Names onto the end of a list, each once: what was added, and what a
    /// locked list kept off.
    fn take_names(&mut self, project: Id, list_name: &str, said: &[String]) -> (Vec<String>, Vec<String>) {
        let mut list = self.vocabulary(list_name);
        let mut new: Vec<String> = Vec::new();
        for name in said {
            let known = list.iter().chain(new.iter()).any(|h| name_key(h) == name_key(name));
            if !known {
                new.push(name.clone());
            }
        }
        if new.is_empty() {
            return (Vec::new(), Vec::new());
        }
        if self.vocabulary_locked(list_name) {
            return (Vec::new(), new);
        }
        list.extend(new.iter().cloned());
        let value = Value::List(list.into_iter().map(Value::Text).collect());
        self.write_without_recording(project, &vocab::key(list_name), value);
        (new, Vec::new())
    }

    /// **Let go of the kit** — for a film unlinked from its project. The lens
    /// list and the cameras keep everything; only the kit itself goes, and
    /// with it every Add to Spec Sheet. Returns whether there was one.
    pub fn let_go_of_kit(&mut self) -> bool {
        let Some(project) = self.project_id() else {
            return false;
        };
        if self.get(project).and_then(|r| r.text(KIT)).unwrap_or("").is_empty() {
            return false;
        }
        self.write_without_recording(project, KIT, Value::Text(String::new()));
        true
    }

    /// The shoot a placement's day falls in, by date — an index into `kit()`.
    pub fn kit_shoot_of(&self, kit: &[KitShoot], placement: Id) -> Option<usize> {
        let day = self.get(placement).and_then(|r| r.ref_id(f::DAY))?;
        let date = self.day_date(day).trim().to_string();
        if date.len() < 10 {
            return None;
        }
        let date = &date[..10];
        kit.iter().position(|s| {
            let start = s.start.get(..10).unwrap_or("");
            let end = s.end.get(..10).filter(|e| !e.is_empty()).unwrap_or(start);
            !start.is_empty() && start <= date && date <= end
        })
    }

    /// **What this shot uses that its kit lacks** — the lens, the camera's
    /// body, or both; nothing when the film has no kit or the shot is in it.
    pub fn off_kit(&self, kit: &[KitShoot], placement: Id) -> Option<OffKit> {
        if kit.is_empty() {
            return None;
        }
        let shot = self.get(placement).and_then(|r| r.ref_id(f::SHOT))?;
        let shoot = self.kit_shoot_of(kit, placement);
        let of: Vec<&KitShoot> = match shoot {
            Some(at) => vec![&kit[at]],
            None => kit.iter().collect(),
        };
        let target = shoot.or_else(|| kit.iter().position(|s| s.lead)).unwrap_or(0);
        let said = self.described_by(shot);
        let lens = self.get(said).and_then(|r| r.text(f::LENS)).unwrap_or("").trim().to_string();
        let picks: Vec<String> = of.iter().flat_map(|s| s.lenses.iter().cloned()).collect();
        let lens = (!lens.is_empty() && !lens_in(&picks, &lens)).then_some(lens);
        let camera = self.get(shot).and_then(|r| r.ref_id(f::UNIT)).and_then(|unit| {
            let text = |field: &str| self.get(unit).and_then(|r| r.text(field)).unwrap_or("").trim().to_string();
            let body = text(f::BODY);
            if body.is_empty() {
                return None;
            }
            let known = of.iter().flat_map(|s| s.cameras.iter()).any(|c| body_key(&c.body) == body_key(&body));
            (!known).then(|| (text(f::LABEL), body))
        });
        let missing = |field: &str, picks: Vec<String>| -> Vec<String> {
            let held: Vec<String> = self
                .get(said)
                .and_then(|r| r.get(field))
                .and_then(|v| v.as_list())
                .map(|items| items.iter().filter_map(|i| i.as_text().map(|s| s.trim().to_string())).collect())
                .unwrap_or_default();
            held.into_iter().filter(|m| !m.is_empty() && !name_in(&picks, m)).collect()
        };
        let modifiers = missing(f::MODIFIERS, of.iter().flat_map(|s| s.modifiers.iter().cloned()).collect());
        let filters = missing(f::LENS_FILTERS, of.iter().flat_map(|s| s.filters.iter().cloned()).collect());
        if lens.is_none() && camera.is_none() && modifiers.is_empty() && filters.is_empty() {
            return None;
        }
        Some(OffKit { shoot: target, lens, camera, modifiers, filters })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stamp::DeviceId;
    use crate::store::Op;

    fn film() -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Lets Bake");
        d.set_vocabulary(vocab::LENS, &["Diopter", "35mm", "Probe"]);
        d.create_unit("A-Cam", "");
        d.clear_history();
        d
    }

    const TWO: &str = r#"[
      {"name":"Shoot 1","start":"2026-07-09","end":"2026-07-10","sheet":"aaaa","lead":false,
       "cameras":[{"label":"A Cam","body":"Alexa 35"},{"label":"B Cam","body":"Sony FX6"}],
       "lenses":["18mm","25mm","32mm","50mm"]},
      {"name":"Shoot 2","start":"2026-10-06","end":"","sheet":"bbbb","lead":true,
       "cameras":[{"label":"","body":"Alexa Mini LF"}],
       "lenses":["Fujinon Premista 28-100mm"]}
    ]"#;

    fn units(d: &Doc) -> Vec<(String, String)> {
        d.store()
            .of_kind(&Kind::Unit)
            .into_iter()
            .map(|r| (r.text(f::LABEL).unwrap_or("").to_string(), r.text(f::BODY).unwrap_or("").to_string()))
            .collect()
    }

    #[test]
    fn the_kits_lenses_go_on_the_list_by_focal_length_and_the_films_extras_stay() {
        let mut d = film();
        let taken = d.take_kit(TWO).unwrap();
        assert_eq!(taken.lenses_added, vec!["18mm", "25mm", "32mm", "50mm", "Fujinon Premista 28-100mm"]);
        let list = d.vocabulary(vocab::LENS);
        for kept in ["Diopter", "35mm", "Probe"] {
            assert!(list.iter().any(|l| l == kept), "{kept} kept: {list:?}");
        }
        let at = |l: &str| list.iter().position(|h| h == l).unwrap();
        assert!(at("18mm") < at("25mm") && at("32mm") < at("35mm") && at("35mm") < at("50mm"), "{list:?}");
    }

    #[test]
    fn cameras_get_their_bodies_and_a_missing_one_is_made() {
        let mut d = film();
        let taken = d.take_kit(TWO).unwrap();
        let held = units(&d);
        // The lead shoot's unlabelled body is the A camera's: it wins.
        assert!(held.contains(&("A-Cam".into(), "Alexa Mini LF".into())), "{held:?}");
        assert!(held.contains(&("B Cam".into(), "Sony FX6".into())), "{held:?}");
        assert_eq!(taken.cameras_made, vec!["B Cam Sony FX6"]);
        assert_eq!(taken.bodies_set, vec!["A-Cam Alexa Mini LF"]);
    }

    #[test]
    fn taking_it_again_writes_nothing_and_leaves_nothing_to_undo() {
        let mut d = film();
        d.take_kit(TWO).unwrap();
        assert_eq!(d.undo_label(), None);
        let written = d.changes().len();
        let again = d.take_kit(TWO).unwrap();
        assert!(!again.changed(), "{again:?}");
        assert_eq!(d.changes().len(), written);
    }

    #[test]
    fn a_lens_off_the_sheet_leaves_the_list_unless_a_shot_uses_it_and_cameras_stay() {
        let mut d = film();
        d.take_kit(TWO).unwrap();
        let scene = d.create_scene("7");
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set(shot, f::LENS, "25mm");
        d.clear_history();
        let taken = d.take_kit(r#"[{"name":"","lenses":["40mm"],"cameras":[]}]"#).unwrap();
        let list = d.vocabulary(vocab::LENS);
        assert!(list.contains(&"40mm".to_string()), "{list:?}");
        assert!(!list.contains(&"18mm".to_string()), "unused and off the sheet: {list:?}");
        assert!(list.contains(&"25mm".to_string()), "a shot still uses it: {list:?}");
        for kept in ["Diopter", "35mm", "Probe"] {
            assert!(list.contains(&kept.to_string()), "the film's own {kept} was never on a sheet");
        }
        assert_eq!(taken.removed, vec!["18mm", "Fujinon Premista 28-100mm", "32mm", "50mm"]);
        assert_eq!(units(&d).len(), 2);
        assert_eq!(d.undo_label(), None, "still no undo step");
    }

    #[test]
    fn a_whole_box_glued_into_one_name_is_split() {
        let mut d = film();
        let glued = r#"[{"name":"","cameras":[],
          "lenses":["Master Prime 16mm, Master Prime 18mm, Fujinon Cabrio 19-90mm"],
          "filters":["Tiffen ND .6, Tiffen ND .9"]}]"#;
        let taken = d.take_kit(glued).unwrap();
        assert_eq!(taken.lenses_added, vec!["Master Prime 16mm", "Master Prime 18mm", "Fujinon Cabrio 19-90mm"]);
        assert_eq!(d.vocabulary(vocab::LENS_FILTERS), vec!["Tiffen ND .6", "Tiffen ND .9"]);
        assert!(!d.vocabulary(vocab::LENS).iter().any(|l| l.contains(',')));
    }

    #[test]
    fn only_the_project_lens_list_and_cameras_are_written() {
        let mut d = film();
        let scene = d.create_scene("7");
        d.add_shot_to_scene(scene);
        let project = d.project_id().unwrap();
        let before = d.changes().len();
        d.take_kit(TWO).unwrap();
        for change in &d.changes()[before..] {
            match &change.op {
                Op::Set { id, field, .. } => {
                    let kind = d.get(*id).map(|r| r.kind.clone());
                    assert!(*id == project || kind == Some(Kind::Unit), "{field} written on a {kind:?}");
                }
                Op::Create { kind, .. } => assert_eq!(*kind, Kind::Unit),
            }
        }
    }

    #[test]
    fn a_locked_list_is_not_grown_and_says_so() {
        let mut d = film();
        d.set_vocabulary_locked(vocab::LENS, true);
        let taken = d.take_kit(TWO).unwrap();
        assert!(taken.lenses_added.is_empty());
        assert_eq!(taken.lens_list_locked.len(), 5);
        assert_eq!(d.vocabulary(vocab::LENS), vec!["Diopter", "35mm", "Probe"]);
    }

    #[test]
    fn a_bad_kit_refuses_and_writes_nothing() {
        let mut d = film();
        let before = d.changes().len();
        assert!(d.take_kit("not json").is_err());
        assert!(d.take_kit(r#"{"name":"x"}"#).is_err());
        assert_eq!(d.changes().len(), before);
    }

    #[test]
    fn lenses_are_matched_loosely() {
        let picks = vec!["32mm".to_string(), "Angenieux 45-165mm".to_string()];
        assert!(lens_in(&picks, "32MM"));
        assert!(lens_in(&picks, "32 mm"));
        assert!(lens_in(&picks, "32"));
        assert!(lens_in(&picks, "Cooke 32mm"));
        assert!(lens_in(&picks, "45–165mm"));
        assert!(!lens_in(&picks, "35mm"));
        assert!(!lens_in(&picks, "132mm"));
        assert_eq!(label_key("A-Camera"), label_key("a cam"));
    }

    #[test]
    fn a_shot_off_the_kit_is_judged_by_the_shoot_its_day_falls_in() {
        let mut d = film();
        d.take_kit(TWO).unwrap();
        let scene = d.create_scene("7");
        let (shot, placement) = d.add_shot_to_scene(scene);
        let kit = d.kit();
        // No day: the whole film's kit. 25mm is on Shoot 1's sheet.
        d.set(shot, f::LENS, "25mm");
        assert_eq!(d.off_kit(&kit, placement), None);
        d.set(shot, f::LENS, "85mm");
        let off = d.off_kit(&kit, placement).unwrap();
        assert_eq!(off.lens.as_deref(), Some("85mm"));
        assert_eq!(off.shoot, 1, "the lead shoot's sheet when no shoot is known");
        // On a Shoot 2 day, 25mm is not in that shoot's kit.
        let day = d.create_record(Kind::ShootDay);
        d.set(day, f::DATE, "2026-10-06");
        d.set(placement, f::DAY, day);
        d.set(shot, f::LENS, "25mm");
        let off = d.off_kit(&kit, placement).unwrap();
        assert_eq!((off.shoot, off.lens.as_deref()), (1, Some("25mm")));
        // On a Shoot 1 day it is.
        d.set(day, f::DATE, "2026-07-10");
        assert_eq!(d.off_kit(&kit, placement), None);
        // A camera whose body is not on that shoot's sheet.
        let c = d.create_unit("C-Cam", "RED Komodo");
        d.set(shot, f::UNIT, c);
        let off = d.off_kit(&kit, placement).unwrap();
        assert_eq!(off.camera, Some(("C-Cam".to_string(), "RED Komodo".to_string())));
        assert_eq!(off.shoot, 0);
    }

    #[test]
    fn letting_go_keeps_the_list_and_the_cameras() {
        let mut d = film();
        d.take_kit(TWO).unwrap();
        assert!(d.let_go_of_kit());
        assert!(d.kit().is_empty());
        assert!(d.vocabulary(vocab::LENS).contains(&"18mm".to_string()));
        assert_eq!(units(&d).len(), 2);
        assert!(!d.let_go_of_kit());
    }

    #[test]
    fn the_switch_is_off_until_he_turns_it_on_and_turning_it_undoes() {
        let mut d = film();
        assert_eq!(d.kit_mode(), KitMode::Off);
        d.set_kit_mode(KitMode::Ask);
        assert_eq!(d.kit_mode(), KitMode::Ask);
        d.set_kit_mode(KitMode::Follow);
        assert_eq!(d.kit_mode(), KitMode::Follow);
        d.undo();
        assert_eq!(d.kit_mode(), KitMode::Ask);
        assert_eq!(KitMode::read("nonsense"), KitMode::Off);
    }

    #[test]
    fn a_film_on_the_shared_record_follows_unless_he_says_otherwise() {
        let mut d = film();
        d.set_vocabulary(vocab::LENS, &["Diopter +1"]);
        d.clear_history();
        assert_eq!(d.kit_mode(), KitMode::Off);
        d.set_card(crate::card::Card::read("{}"));
        assert_eq!(d.kit_mode(), KitMode::Follow);
        // Taking the sheet keeps his own terms.
        d.take_kit(TWO).unwrap();
        assert!(d.vocabulary(vocab::LENS).contains(&"Diopter +1".to_string()));
        d.take_kit("[]").unwrap();
        assert!(d.vocabulary(vocab::LENS).contains(&"Diopter +1".to_string()));
        // His Off stands over the default.
        d.set_kit_mode(KitMode::Off);
        assert_eq!(d.kit_mode(), KitMode::Off);
        d.set_card(None);
        assert_eq!(d.kit_mode(), KitMode::Off);
    }

    #[test]
    fn off_offers_no_shot_for_the_sheet() {
        let mut d = film();
        d.take_kit(TWO).unwrap();
        let asked = crate::view::Asked::default();
        let standing = crate::view::Standing { read_only: false, unsaved: 0, device_clash: None };
        let view = |d: &Doc| crate::view::describe(d, &asked.looking(), &standing);
        assert!(view(&d).contains("\"kitMode\":\"off\""));
        d.set_kit_mode(KitMode::Follow);
        assert!(view(&d).contains("\"kitMode\":\"follow\""));
    }

    const CARRIED: &str = r#"[
      {"name":"Shoot 1","start":"2026-07-09","end":"2026-07-10","sheet":"aaaa","lead":true,
       "cameras":[],"lenses":["45-165mm"],
       "modifiers":["Atlas LF Extender 1.6x"],
       "filters":["Tiffen ND .6","Tiffen ND .9","Polarizer 138mm"]}
    ]"#;

    #[test]
    fn modifiers_and_filters_go_on_their_own_lists_by_name_and_stay() {
        let mut d = film();
        d.set_vocabulary(vocab::LENS_FILTERS, &["Black Pro-Mist 1/8"]);
        d.clear_history();
        let taken = d.take_kit(CARRIED).unwrap();
        assert_eq!(taken.modifiers_added, vec!["Atlas LF Extender 1.6x"]);
        assert_eq!(taken.filters_added, vec!["Tiffen ND .6", "Tiffen ND .9", "Polarizer 138mm"]);
        assert_eq!(d.vocabulary(vocab::MODIFIERS), vec!["Atlas LF Extender 1.6x"]);
        assert_eq!(
            d.vocabulary(vocab::LENS_FILTERS),
            vec!["Black Pro-Mist 1/8", "Tiffen ND .6", "Tiffen ND .9", "Polarizer 138mm"],
            "the film's own filter stays, the sheet's go after it as named"
        );
        // Again: nothing new, nothing to undo.
        let again = d.take_kit(CARRIED).unwrap();
        assert!(!again.changed(), "{again:?}");
        assert_eq!(d.undo_label(), None);
        // A sheet without them takes the sheet's off; the film's own stays.
        d.take_kit(TWO).unwrap();
        assert!(d.vocabulary(vocab::MODIFIERS).is_empty());
        assert_eq!(d.vocabulary(vocab::LENS_FILTERS), vec!["Black Pro-Mist 1/8"]);
    }

    #[test]
    fn a_locked_filter_list_is_not_grown_and_says_so() {
        let mut d = film();
        d.set_vocabulary_locked(vocab::LENS_FILTERS, true);
        let taken = d.take_kit(CARRIED).unwrap();
        assert!(taken.filters_added.is_empty());
        assert_eq!(taken.filter_list_locked.len(), 3);
        assert!(d.vocabulary(vocab::LENS_FILTERS).is_empty());
        assert_eq!(taken.modifiers_added.len(), 1, "the modifier list is not locked");
    }

    #[test]
    fn an_old_kit_without_them_reads_and_is_kept_as_it_was() {
        let kit = parse(TWO).unwrap();
        assert!(kit.iter().all(|s| s.modifiers.is_empty() && s.filters.is_empty()));
        assert!(!encode(&kit).contains("modifiers"));
        let carried = parse(CARRIED).unwrap();
        assert_eq!(parse(&encode(&carried)).unwrap(), carried);
    }

    #[test]
    fn a_shots_modifier_or_filter_off_the_sheet_is_offered() {
        let mut d = film();
        d.take_kit(CARRIED).unwrap();
        let scene = d.create_scene("7");
        let (shot, placement) = d.add_shot_to_scene(scene);
        let kit = d.kit();
        d.set(shot, f::LENS, "45-165mm");
        d.set_vocab_list(shot, f::MODIFIERS, &["1.6x"]);
        d.set_vocab_list(shot, f::LENS_FILTERS, &["ND .6", "Polarizer 138mm"]);
        assert_eq!(d.off_kit(&kit, placement), None, "named loosely, as a lens is");
        d.set_vocab_list(shot, f::MODIFIERS, &["Atlas LF Extender 1.6x", "Expander 1.4x"]);
        d.set_vocab_list(shot, f::LENS_FILTERS, &["Tiffen ND 1.2", "Tiffen ND .9"]);
        let off = d.off_kit(&kit, placement).unwrap();
        assert_eq!(off.lens, None);
        assert_eq!(off.modifiers, vec!["Expander 1.4x"]);
        assert_eq!(off.filters, vec!["Tiffen ND 1.2"]);
        assert_eq!(off.shoot, 0);
    }

    #[test]
    fn a_locked_camera_list_is_not_grown_but_bodies_are_still_set() {
        let mut d = film();
        d.set_vocabulary_locked(f::UNIT, true);
        let taken = d.take_kit(TWO).unwrap();
        assert_eq!(units(&d).len(), 1, "only the A-Cam the film had");
        assert_eq!(taken.camera_list_locked, vec!["B Cam Sony FX6".to_string()]);
        assert_eq!(units(&d)[0].1, "Alexa Mini LF", "the lead shoot's body still goes on A-Cam");
    }
}
