//! **Shoots in the film** (stage 5 step 4, piece D, 2026-10-15).
//!
//! A project that shoots more than once (Let's Bake: Shoot 1 in July, Shoot 2
//! in October) used to show it with section headings, which look exactly like
//! his own sections. His approved design: the shoots are the project's — they
//! come on the **card** (`crate::card`), from the record — and in the film
//! **each scene belongs to a shoot, and each schedule day belongs to a shoot
//! and follows its dates**. Sections go back to being his own dividers inside
//! a shoot.
//!
//! What the film stores is only the reference: `shoot` on a scene and on a
//! day (the Shoot's bare id), and `shoot_day` on a day (which day of the
//! shoot, from 0). Everything else — the shoot's name, dates and status — is
//! the card's, laid over in memory and never written.
//!
//! **A scene or day that has never been given a shoot still belongs to one**,
//! so the picker never loses anything: a day by its date (the shoot whose days
//! it falls on, else the last one that started before it), a scene by its
//! first scheduled day, and anything left over by the first shoot — which is
//! what a project that had one shoot and gets a second wants: everything it
//! already had was the first shoot's.
//!
//! **A day's date follows its shoot.** A day with a `shoot` and a `shoot_day`
//! shows the shoot's first day plus that many days, so moving a shoot moves
//! its days, on every device, without anything being written. With no card,
//! or a shoot the card does not list, the day shows its own date, which is
//! what an older build or an export made without a card reads.
//!
//! **No card shoots, no shoots.** With fewer than two, nothing narrows and
//! days count across the film as they always have.

use crate::doc::f;
use crate::id::Id;
use crate::json::Json;
use crate::jsonw;
use crate::value::Value;
use crate::Doc;

/// One of the project's shoots, as the card lists it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Shoot {
    /// Its bare id (the Shoots row's page id, no dashes, lowercase).
    pub id: String,
    /// What it is called: its own name ("Style Server"), else its kind.
    pub label: String,
    /// Its place among the shoots, in words: "Shoot 2", "Principal".
    pub kind: String,
    /// The number its title carries ("Shoot 2" → 2), when it has one.
    pub n: Option<i64>,
    /// First and last day, `YYYY-MM-DD`; the last may be empty (one day).
    pub start: String,
    pub end: String,
    /// Wrapped, Next, Today, To Wrap or Upcoming — the console's word.
    pub state: String,
}

/// An id as the film keeps it: no dashes, lowercase, hex only. Empty when it
/// is not one.
pub fn bare(id: &str) -> String {
    let out: String = id.trim().chars().filter(|c| *c != '-').collect::<String>().to_ascii_lowercase();
    if (8..=64).contains(&out.len()) && out.chars().all(|c| c.is_ascii_hexdigit()) {
        out
    } else {
        String::new()
    }
}

fn tidy(said: &str, cap: usize) -> String {
    let clean: String = said.chars().map(|c| if c.is_control() { ' ' } else { c }).collect();
    clean.trim().chars().take(cap).collect()
}

impl Shoot {
    /// One shoot off the card: `{id, label|name, kind, n, start, end,
    /// state|status}`. Nothing without a usable id.
    pub fn read(j: &Json) -> Option<Shoot> {
        let id = bare(j.get("id").and_then(Json::as_str).unwrap_or(""));
        if id.is_empty() {
            return None;
        }
        let said = |k: &str| tidy(j.get(k).and_then(Json::as_str).unwrap_or(""), 120);
        let kind = said("kind");
        let label = {
            let l = said("label");
            if !l.is_empty() {
                l
            } else {
                let n = said("name");
                if n.is_empty() { kind.clone() } else { n }
            }
        };
        let day = |k: &str| {
            let t = said(k);
            if parse_day(&t).is_some() { t } else { String::new() }
        };
        let state = {
            let s = said("state");
            if s.is_empty() { said("status") } else { s }
        };
        Some(Shoot {
            id,
            label: if label.is_empty() { "Shoot".to_string() } else { label },
            kind,
            n: j.get("n").and_then(Json::as_f64).map(|n| n as i64).filter(|n| *n > 0),
            start: day("start"),
            end: day("end"),
            state,
        })
    }

    /// Every shoot on the card, each id once, in the card's order.
    pub fn read_all(list: &[Json]) -> Vec<Shoot> {
        let mut out: Vec<Shoot> = Vec::new();
        for one in list.iter().take(60) {
            if let Some(s) = Shoot::read(one) {
                if !out.iter().any(|x| x.id == s.id) {
                    out.push(s);
                }
            }
        }
        out
    }

    pub fn wrapped(&self) -> bool {
        self.state.eq_ignore_ascii_case("wrapped")
    }

    /// Whether a date falls on one of this shoot's days.
    pub fn covers(&self, date: &str) -> bool {
        let (Some(at), Some(first)) = (parse_day(date), parse_day(&self.start)) else { return false };
        let last = parse_day(&self.end).unwrap_or(first).max(first);
        at >= first && at <= last
    }
}

// ---- days as numbers -------------------------------------------------------

/// `YYYY-MM-DD` as days since 1970-01-01. Nothing for anything else.
pub fn parse_day(s: &str) -> Option<i64> {
    let s = s.trim();
    if s.len() != 10 || s.as_bytes()[4] != b'-' || s.as_bytes()[7] != b'-' {
        return None;
    }
    let y: i64 = s[0..4].parse().ok()?;
    let m: i64 = s[5..7].parse().ok()?;
    let d: i64 = s[8..10].parse().ok()?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let n = days_from_civil(y, m, d);
    // 2026-02-30 is not a day.
    if format_day(n) != s {
        return None;
    }
    Some(n)
}

/// Days since 1970-01-01 as `YYYY-MM-DD`.
pub fn format_day(n: i64) -> String {
    let (y, m, d) = civil_from_days(n);
    format!("{:04}-{:02}-{:02}", y, m, d)
}

// Howard Hinnant's algorithms.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

// ---- the film's shoots -------------------------------------------------------

impl Doc {
    /// The project's shoots, from the card. Empty without one.
    pub fn shoots(&self) -> &[Shoot] {
        self.card.as_ref().map(|c| c.shoots.as_slice()).unwrap_or(&[])
    }

    /// Whether the film is split by shoot at all: two or more. One shoot is no
    /// shoots — his ruling, 2026-10-02 — and shows no picker.
    pub fn many_shoots(&self) -> bool {
        self.shoots().len() >= 2
    }

    /// A shoot the card lists, by id (bare or not).
    pub fn shoot(&self, id: &str) -> Option<&Shoot> {
        let want = bare(id);
        if want.is_empty() {
            return None;
        }
        self.shoots().iter().find(|s| s.id == want)
    }

    /// The shoot a record names itself, when the card knows it.
    pub fn own_shoot(&self, id: Id) -> Option<String> {
        let said = self.get(id).and_then(|r| r.text(f::SHOOT)).unwrap_or("");
        self.shoot(said).map(|s| s.id.clone())
    }

    /// The shoot a record names, as stored (bare), whether or not a card
    /// knows it — what a reader with no card (the portal's browser, the
    /// server's sidebar count) matches against the shoots it has.
    pub fn said_shoot(&self, id: Id) -> String {
        bare(self.get(id).and_then(|r| r.text(f::SHOOT)).unwrap_or(""))
    }

    /// Whether a record names a shoot of its own at all (known or not).
    pub fn names_shoot(&self, id: Id) -> bool {
        !bare(self.get(id).and_then(|r| r.text(f::SHOOT)).unwrap_or("")).is_empty()
    }

    /// The shoot a date belongs to: the one whose days it falls on, else the
    /// last that started on or before it, else the first.
    pub fn shoot_for_date(&self, date: &str) -> Option<String> {
        let shoots = self.shoots();
        let first = shoots.first()?;
        if let Some(s) = shoots.iter().find(|s| s.covers(date)) {
            return Some(s.id.clone());
        }
        if let Some(at) = parse_day(date) {
            let before = shoots
                .iter()
                .filter(|s| parse_day(&s.start).map(|st| st <= at).unwrap_or(false))
                .max_by_key(|s| parse_day(&s.start).unwrap_or(i64::MIN));
            if let Some(s) = before {
                return Some(s.id.clone());
            }
        }
        Some(first.id.clone())
    }

    /// **The shoot a day belongs to**: its own, else by its date, else the
    /// first. None when the card lists no shoots.
    pub fn day_shoot(&self, day: Id) -> Option<String> {
        if self.shoots().is_empty() {
            return None;
        }
        if let Some(own) = self.own_shoot(day) {
            return Some(own);
        }
        let date = self.get(day).and_then(|r| r.text(f::DATE)).unwrap_or("").to_string();
        self.shoot_for_date(&date)
    }

    /// **The shoot a scene belongs to**: its own, else its first scheduled
    /// day's, else the first. None when the card lists no shoots.
    pub fn scene_shoot(&self, scene: Id) -> Option<String> {
        let first = self.shoots().first()?.id.clone();
        if let Some(own) = self.own_shoot(scene) {
            return Some(own);
        }
        if let Some(day) = self.days_of_scene(scene).into_iter().next() {
            if let Some(s) = self.day_shoot(day) {
                return Some(s);
            }
        }
        Some(first)
    }

    /// A shoot's days, in the schedule's order.
    pub fn days_of_shoot(&self, shoot: &str) -> Vec<Id> {
        let want = bare(shoot);
        self.days_in_order()
            .into_iter()
            .filter(|d| self.day_shoot(*d).as_deref() == Some(want.as_str()))
            .collect()
    }

    /// A shoot's scenes, in script order.
    pub fn scenes_of_shoot(&self, shoot: &str) -> Vec<Id> {
        let want = bare(shoot);
        self.scenes_in_order()
            .into_iter()
            .filter(|s| self.scene_shoot(*s).as_deref() == Some(want.as_str()))
            .collect()
    }

    /// Whether a scene is in the shoot being looked at. Always, with no
    /// shoots or nothing picked.
    pub fn scene_in(&self, scene: Id, shoot: Option<&str>) -> bool {
        match shoot {
            Some(on) if self.many_shoots() && self.shoot(on).is_some() => {
                self.scene_shoot(scene).as_deref() == Some(bare(on).as_str())
            }
            _ => true,
        }
    }

    /// Whether a day is in the shoot being looked at.
    pub fn day_in(&self, day: Id, shoot: Option<&str>) -> bool {
        match shoot {
            Some(on) if self.many_shoots() && self.shoot(on).is_some() => {
                self.day_shoot(day).as_deref() == Some(bare(on).as_str())
            }
            _ => true,
        }
    }

    /// **A day's date as shown**: its shoot's first day plus its place in
    /// the shoot, when it follows a shoot the card dates; its own otherwise.
    pub fn day_date(&self, day: Id) -> String {
        let own = self.get(day).and_then(|r| r.text(f::DATE)).unwrap_or("").to_string();
        let Some(shoot) = self.own_shoot(day).and_then(|s| self.shoot(&s).cloned()) else { return own };
        let Some(start) = parse_day(&shoot.start) else { return own };
        let Some(offset) = self.get(day).and_then(|r| r.get(f::SHOOT_DAY)).and_then(|v| v.as_int().or(v.as_float().map(|x| x as i64))) else {
            return own;
        };
        format_day(start + offset)
    }

    /// The shoot new scenes and days are born into: the one the picker is on.
    pub fn set_born_in(&mut self, shoot: Option<&str>) {
        self.new_in = shoot.map(bare).filter(|s| !s.is_empty());
    }

    pub(crate) fn shoot_to_be_born_in(&self) -> Option<String> {
        if !self.many_shoots() {
            return None;
        }
        let on = self.new_in.as_deref()?;
        self.shoot(on).map(|s| s.id.clone())
    }

    /// A day just made, put in a shoot: the shoot's next day, dated by it.
    pub(crate) fn born_in_shoot(&mut self, day: Id, shoot: &str) {
        let others = self.days_of_shoot(shoot).into_iter().filter(|d| *d != day).count() as i64;
        self.set(day, f::SHOOT, Value::text(shoot));
        self.set(day, f::SHOOT_DAY, Value::Int(others));
        if let Some(start) = self.shoot(shoot).and_then(|s| parse_day(&s.start)) {
            self.set(day, f::DATE, Value::text(format_day(start + others)));
        }
    }

    /// After a day's date is set by hand: if it follows a shoot, its place in
    /// the shoot is counted again from the new date.
    pub(crate) fn refollow_day(&mut self, day: Id) {
        let Some(shoot) = self.own_shoot(day).and_then(|s| self.shoot(&s).cloned()) else { return };
        let date = self.get(day).and_then(|r| r.text(f::DATE)).unwrap_or("").to_string();
        if let (Some(start), Some(at)) = (parse_day(&shoot.start), parse_day(&date)) {
            self.set(day, f::SHOOT_DAY, Value::Int(at - start));
        }
    }

    /// The scene's shots that sit on a day of another shoot than `to`.
    fn placements_off_shoot(&self, scene: Id, to: &str) -> Vec<Id> {
        self.placements_in_scene(scene)
            .into_iter()
            .filter(|p| {
                self.get(*p)
                    .and_then(|r| r.ref_id(f::DAY))
                    .map(|day| self.day_shoot(day).as_deref() != Some(to))
                    .unwrap_or(false)
            })
            .collect()
    }

    /// **Move to Shoot…** — scenes into a shoot. A moved scene's shots that
    /// sit on another shoot's day go back to Unscheduled, so no shoot's day
    /// ever lists a scene that is not its own; shots already on a day of the
    /// new shoot keep it. One undo step. Returns how many scenes changed.
    pub fn move_scenes_to_shoot(&mut self, scenes: &[Id], shoot: &str) -> usize {
        let Some(to) = self.shoot(shoot).map(|s| s.id.clone()) else { return 0 };
        let moving: Vec<Id> = scenes
            .iter()
            .copied()
            .filter(|s| self.get(*s).is_some())
            .filter(|s| {
                self.own_shoot(*s).as_deref() != Some(to.as_str()) || !self.placements_off_shoot(*s, &to).is_empty()
            })
            .collect();
        if moving.is_empty() {
            return 0;
        }
        let off: Vec<Id> = moving.iter().flat_map(|s| self.placements_off_shoot(*s, &to)).collect();
        let tx = self.begin("Move to Shoot");
        for scene in &moving {
            self.set(*scene, f::SHOOT, Value::text(to.clone()));
        }
        for placement in &off {
            self.set(*placement, f::DAY, Value::Null);
            self.set(*placement, f::ORDER_IN_DAY, Value::Null);
        }
        self.end(tx);
        moving.len()
    }

    /// A day into a shoot. Dated, it keeps its date and counts its place in
    /// the shoot from it; undated, it becomes the shoot's next day.
    pub fn set_day_shoot(&mut self, day: Id, shoot: &str) -> bool {
        let Some(to) = self.shoot(shoot).cloned() else { return false };
        if self.get(day).is_none() {
            return false;
        }
        let tx = self.begin("Move Day to Shoot");
        let date = self.get(day).and_then(|r| r.text(f::DATE)).unwrap_or("").to_string();
        match (parse_day(&to.start), parse_day(&date)) {
            (Some(start), Some(at)) => {
                self.set(day, f::SHOOT, Value::text(to.id.clone()));
                self.set(day, f::SHOOT_DAY, Value::Int(at - start));
            }
            _ => self.born_in_shoot(day, &to.id),
        }
        self.end(tx);
        true
    }
}

// ---- the one-time converter: section headings to shoots --------------------

/// Where one scene or day goes, and why.
#[derive(Clone, Debug, PartialEq)]
pub struct Assigned {
    pub id: Id,
    /// The scene's number, or the day's label.
    pub name: String,
    /// The scene's section, or the day's date.
    pub from: String,
    pub shoot: String,
    /// `section`, `date`, `already` or `stray`.
    pub why: &'static str,
    /// Whether applying it writes anything.
    pub changes: bool,
}

/// **Section headings to shoots, before anything is written** — the dry run.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ShootPlan {
    pub scenes: Vec<Assigned>,
    pub days: Vec<Assigned>,
}

impl ShootPlan {
    pub fn changes(&self) -> usize {
        self.scenes.iter().chain(self.days.iter()).filter(|a| a.changes).count()
    }
}

/// The number a heading names a shoot by: "Shoot 2 - Style Server" → 2.
fn shoot_number(title: &str) -> Option<i64> {
    let low = title.to_ascii_lowercase();
    let at = low.find("shoot")?;
    let rest = low[at + 5..].trim_start();
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

fn loose(s: &str) -> String {
    s.to_lowercase()
        .replace(['—', '–', '-', ':', '·'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

impl Doc {
    /// The shoot a section heading names, if it names one.
    pub fn shoot_of_heading(&self, title: &str) -> Option<String> {
        let shoots = self.shoots();
        if let Some(n) = shoot_number(title) {
            if let Some(s) = shoots.iter().find(|s| s.n == Some(n)) {
                return Some(s.id.clone());
            }
            let words = format!("shoot {}", n);
            if let Some(s) = shoots.iter().find(|s| loose(&s.kind) == words || loose(&s.label) == words) {
                return Some(s.id.clone());
            }
            if n >= 1 && (n as usize) <= shoots.len() {
                return Some(shoots[n as usize - 1].id.clone());
            }
            return None;
        }
        // A heading that is a shoot's own name ("Style Server — Day 1").
        let t = loose(title);
        shoots
            .iter()
            .filter(|s| !s.label.is_empty() && loose(&s.label) != loose(&s.kind))
            .find(|s| {
                let l = loose(&s.label);
                t == l || t.starts_with(&format!("{} ", l))
            })
            .map(|s| s.id.clone())
    }

    /// **Let's Bake's "Shoot 1" / "Shoot 2" headings become real shoots**
    /// (his rule, step 9): every scene under a heading that names a shoot goes
    /// to that shoot, archived ones too; every other scene is a stray and goes
    /// to the first shoot. Days go by their date. A scene or day that already
    /// names a shoot the card knows is left as it is. Writes nothing.
    pub fn shoots_from_sections(&self) -> ShootPlan {
        let mut plan = ShootPlan::default();
        let Some(first) = self.shoots().first().map(|s| s.id.clone()) else { return plan };
        for scene in self.scenes_in_order() {
            let number = self.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or("").to_string();
            let section = self
                .get(scene)
                .and_then(|r| r.ref_id(f::SEQUENCE))
                .and_then(|seq| self.get(seq))
                .and_then(|r| r.text(f::TITLE))
                .unwrap_or("")
                .to_string();
            let (shoot, why) = if let Some(own) = self.own_shoot(scene) {
                (own, "already")
            } else if let Some(s) = self.shoot_of_heading(&section) {
                (s, "section")
            } else {
                (first.clone(), "stray")
            };
            plan.scenes.push(Assigned { id: scene, name: number, from: section, changes: why != "already", shoot, why });
        }
        for day in self.days_in_order() {
            let label = self.day_label(day).unwrap_or_default();
            let date = self.get(day).and_then(|r| r.text(f::DATE)).unwrap_or("").to_string();
            let (shoot, why) = if let Some(own) = self.own_shoot(day) {
                (own, "already")
            } else if let Some(s) = self.shoots().iter().find(|s| s.covers(&date)) {
                (s.id.clone(), "date")
            } else {
                (self.shoot_for_date(&date).unwrap_or_else(|| first.clone()), "stray")
            };
            plan.days.push(Assigned { id: day, name: label, from: date, changes: why != "already", shoot, why });
        }
        plan
    }

    /// Write a plan: one undo step, "Shoots from Sections". Sections are not
    /// touched; they stay his. Returns how many records were given a shoot.
    pub fn apply_shoot_plan(&mut self, plan: &ShootPlan) -> usize {
        let todo: Vec<&Assigned> = plan.scenes.iter().chain(plan.days.iter()).filter(|a| a.changes).collect();
        if todo.is_empty() {
            return 0;
        }
        let tx = self.begin("Shoots from Sections");
        for one in plan.scenes.iter().filter(|a| a.changes) {
            self.set(one.id, f::SHOOT, Value::text(one.shoot.clone()));
        }
        for one in plan.days.iter().filter(|a| a.changes) {
            let date = self.get(one.id).and_then(|r| r.text(f::DATE)).unwrap_or("").to_string();
            let start = self.shoot(&one.shoot).and_then(|s| parse_day(&s.start));
            self.set(one.id, f::SHOOT, Value::text(one.shoot.clone()));
            if let (Some(start), Some(at)) = (start, parse_day(&date)) {
                self.set(one.id, f::SHOOT_DAY, Value::Int(at - start));
            }
        }
        self.end(tx);
        todo.len()
    }

    /// A plan as the dry run says it.
    pub fn shoot_plan_json(&self, plan: &ShootPlan) -> String {
        let label = |id: &str| self.shoot(id).map(|s| s.label.clone()).unwrap_or_default();
        let mut j = jsonw::Json::new();
        j.obj().ki("changes", plan.changes() as i64);
        j.key("shoots").arr();
        for s in self.shoots() {
            j.obj().kv("id", &s.id).kv("label", &s.label).kv("kind", &s.kind).kv("start", &s.start).kv("end", &s.end).end_obj();
        }
        j.end_arr();
        for (key, list) in [("scenes", &plan.scenes), ("days", &plan.days)] {
            j.key(key).arr();
            for a in list.iter() {
                j.obj()
                    .kv("id", &a.id.0.to_string())
                    .kv("name", &a.name)
                    .kv("from", &a.from)
                    .kv("shoot", &a.shoot)
                    .kv("shootLabel", &label(&a.shoot))
                    .kv("why", a.why)
                    .kb("changes", a.changes)
                    .end_obj();
            }
            j.end_arr();
        }
        j.end_obj();
        j.finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::card::Card;
    use crate::json;
    use crate::stamp::DeviceId;
    use crate::view::{self, Asked, Standing};

    const S1: &str = "4acab7b3b555897c7c58dce7762aca55";
    const S2: &str = "50ad95105a93869dd1c97f9e1a45a05a";

    fn card(shoots: &str) -> Option<Card> {
        Card::read(&format!(r#"{{"facts":{{"title":"Lets Bake"}},"type":"Commercial","shoots":{}}}"#, shoots))
    }

    fn two() -> Option<Card> {
        card(&format!(
            r#"[{{"id":"4acab7b3-b555-897c-7c58-dce7762aca55","label":"Shoot 1","kind":"Shoot 1","n":1,"start":"2026-07-09","end":"","state":"Wrapped"}},
               {{"id":"{S2}","label":"Style Server","kind":"Shoot 2","n":2,"start":"2026-10-06","end":"2026-10-07","state":"Next"}}]"#
        ))
    }

    /// Let's Bake as it stands: two shoot headings, one empty divider, days
    /// on July 9 and October 6.
    fn lets_bake() -> (Doc, Vec<Id>, Vec<Id>) {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Lets Bake");
        let one = d.create_sequence("Shoot 1 — July 9");
        let two = d.create_sequence("Shoot 2 - Style Server");
        d.create_sequence("Shoot 2 - Style & Spice");
        let day1 = d.create_day_dated("2026-07-09");
        let day2 = d.create_day_dated("2026-10-06");
        let mut scenes = Vec::new();
        for n in 1..=8 {
            let s = d.create_scene(&n.to_string());
            d.set(s, f::SEQUENCE, if n <= 6 { one } else { two });
            let (_, pl) = d.add_shot_to_scene(s);
            d.schedule(pl, if n <= 6 { day1 } else { day2 });
            scenes.push(s);
        }
        d.clear_history();
        (d, scenes, vec![day1, day2])
    }

    fn shown(d: &Doc, shoot: Option<&str>) -> json::Json {
        let asked = Asked { shoot: shoot.map(String::from), ..Asked::default() };
        let out = view::describe(d, &asked.looking(), &Standing { read_only: false, unsaved: 0, device_clash: None });
        json::parse(&out).expect("the view reads")
    }

    fn ids(list: &json::Json) -> Vec<String> {
        list.as_array().unwrap_or(&[]).iter().map(|x| x.str_field("id")).collect()
    }

    #[test]
    fn days_are_numbers_and_back() {
        assert_eq!(format_day(parse_day("2026-10-06").unwrap() + 1), "2026-10-07");
        assert_eq!(format_day(parse_day("2026-02-28").unwrap() + 1), "2026-03-01");
        assert_eq!(format_day(parse_day("2028-02-28").unwrap() + 1), "2028-02-29");
        assert_eq!(parse_day("2026-02-30"), None);
        assert_eq!(parse_day("Fri 12 Sep"), None);
        assert_eq!(format_day(parse_day("1999-12-31").unwrap() + 1), "2000-01-01");
    }

    #[test]
    fn the_card_carries_the_shoots_and_ids_are_bare() {
        let c = two().unwrap();
        assert_eq!(c.shoots.len(), 2);
        assert_eq!(c.shoots[0].id, S1);
        assert_eq!(c.shoots[1].label, "Style Server");
        assert_eq!(c.shoots[1].kind, "Shoot 2");
        assert_eq!(c.shoots[1].n, Some(2));
        assert!(c.shoots[0].wrapped());
        // A card without shoots, or with junk in them, has none.
        assert!(card("[]").unwrap().shoots.is_empty());
        assert!(card(r#"[{"id":"nope"},{"label":"x"}]"#).unwrap().shoots.is_empty());
        assert!(Card::read(r#"{"facts":{}}"#).unwrap().shoots.is_empty());
    }

    #[test]
    fn nothing_belongs_to_a_shoot_without_a_card_and_one_shoot_narrows_nothing() {
        let (mut d, scenes, days) = lets_bake();
        assert_eq!(d.scene_shoot(scenes[0]), None);
        assert!(!d.many_shoots());
        assert_eq!(d.day_label(days[1]).as_deref(), Some("Day 2"));
        d.set_card(card(&format!(r#"[{{"id":"{S1}","label":"Shoot","start":"2026-07-09"}}]"#)));
        assert!(!d.many_shoots());
        assert!(d.scene_in(scenes[7], Some(S2)));
        let v = shown(&d, Some(S1));
        assert_eq!(v.get("scenes").and_then(json::Json::as_array).map(|a| a.len()), Some(8));
        assert_eq!(v.str_field("shootOn"), "");
        assert_eq!(d.day_label(days[1]).as_deref(), Some("Day 2"), "one shoot: days count across the film");
    }

    #[test]
    fn a_scene_never_given_a_shoot_follows_its_day_else_the_first() {
        let (mut d, scenes, days) = lets_bake();
        d.set_card(two());
        assert_eq!(d.scene_shoot(scenes[0]).as_deref(), Some(S1));
        assert_eq!(d.scene_shoot(scenes[7]).as_deref(), Some(S2), "scheduled on Oct 6");
        assert_eq!(d.day_shoot(days[0]).as_deref(), Some(S1));
        assert_eq!(d.day_shoot(days[1]).as_deref(), Some(S2));
        // Laying the card on wrote nothing.
        assert!(!d.can_undo());
        // An unscheduled scene with no shoot of its own is the first shoot's.
        let lone = d.create_scene("9");
        assert_eq!(d.scene_shoot(lone).as_deref(), Some(S1));
    }

    #[test]
    fn days_count_within_their_shoot() {
        let (mut d, _, days) = lets_bake();
        d.set_card(two());
        assert_eq!(d.day_label(days[0]).as_deref(), Some("Day 1"));
        assert_eq!(d.day_label(days[1]).as_deref(), Some("Day 1"), "Shoot 2's first day is its Day 1");
        let more = d.create_day_dated("2026-10-07");
        assert_eq!(d.day_label(more).as_deref(), Some("Day 2"));
        assert_eq!(d.days_of_shoot(S2), vec![days[1], more]);
    }

    #[test]
    fn picking_a_shoot_narrows_scenes_days_and_shots() {
        let (mut d, scenes, days) = lets_bake();
        d.set_card(two());
        let v = shown(&d, Some(S2));
        assert_eq!(v.str_field("shootOn"), S2);
        assert_eq!(ids(v.get("scenes").unwrap()), vec![scenes[6].0.to_string(), scenes[7].0.to_string()]);
        assert_eq!(ids(v.get("days").unwrap()), vec![days[1].0.to_string()]);
        // Other shoots' scenes are not "hidden by a filter".
        assert_eq!(v.get("filter").unwrap().get("hiddenScenes").and_then(json::Json::as_f64), Some(0.0));
        assert_eq!(v.get("filter").unwrap().get("shown").and_then(json::Json::as_f64), Some(2.0));
        // All Shoots: everything, each scene saying its shoot.
        let all = shown(&d, None);
        let list = all.get("scenes").unwrap().as_array().unwrap();
        assert_eq!(list.len(), 8);
        assert_eq!(list[0].str_field("shoot"), S1);
        assert_eq!(list[7].str_field("shoot"), S2);
        assert_eq!(all.get("shoots").unwrap().as_array().unwrap().len(), 2);
        assert_eq!(all.get("shoots").unwrap().as_array().unwrap()[1].get("scenes").and_then(json::Json::as_f64), Some(2.0));
        // A shoot the card does not know narrows nothing.
        assert_eq!(shown(&d, Some("ffffffffffffffffffffffffffffffff")).get("scenes").unwrap().as_array().unwrap().len(), 8);
    }

    #[test]
    fn move_to_shoot_is_one_undo_and_takes_shots_off_the_old_shoots_days() {
        let (mut d, scenes, days) = lets_bake();
        d.set_card(two());
        // Scene 1 is split: one shot on July 9 (Shoot 1), one on Oct 6 (Shoot 2).
        let (_, also) = d.add_shot_to_scene(scenes[0]);
        d.schedule(also, days[1]);
        d.clear_history();
        assert_eq!(d.move_scenes_to_shoot(&[scenes[0], scenes[1]], S2), 2);
        assert_eq!(d.scene_shoot(scenes[0]).as_deref(), Some(S2));
        // Shoot 1's day no longer lists them; the shot already on Shoot 2's day stays.
        assert_eq!(d.days_of_scene(scenes[0]), vec![days[1]], "off Shoot 1's day, kept on Shoot 2's");
        assert!(d.days_of_scene(scenes[1]).is_empty(), "back to Unscheduled");
        assert_eq!(d.placements_on_day(days[0]).len(), 4, "only scenes 3-6 stay on Shoot 1's day");
        assert_eq!(d.move_scenes_to_shoot(&[scenes[0]], S2), 0, "already there");
        assert_eq!(d.move_scenes_to_shoot(&[scenes[0]], "ffffffff"), 0, "no such shoot");
        // One undo puts the shoots and the days back together.
        d.undo();
        assert_eq!(d.scene_shoot(scenes[0]).as_deref(), Some(S1));
        assert_eq!(d.scene_shoot(scenes[1]).as_deref(), Some(S1));
        assert_eq!(d.days_of_scene(scenes[0]), vec![days[0], days[1]]);
        assert_eq!(d.days_of_scene(scenes[1]), vec![days[0]]);
        assert!(!d.can_undo());
        // A scene that already names the shoot but still has a shot on another
        // shoot's day is tidied too.
        d.set(scenes[6], f::SHOOT, Value::text(S1.to_string()));
        d.clear_history();
        assert_eq!(d.move_scenes_to_shoot(&[scenes[6]], S1), 1);
        assert!(d.days_of_scene(scenes[6]).is_empty());
    }

    #[test]
    fn a_days_date_follows_its_shoot() {
        let (mut d, _, days) = lets_bake();
        d.set_card(two());
        assert!(d.set_day_shoot(days[1], S2));
        assert_eq!(d.day_date(days[1]), "2026-10-06");
        let more = d.create_day_dated("2026-10-07");
        d.set_day_shoot(more, S2);
        // The shoot moves a week later: its days move with it, nothing written.
        d.clear_history();
        d.set_card(card(&format!(
            r#"[{{"id":"{S1}","label":"Shoot 1","start":"2026-07-09"}},{{"id":"{S2}","label":"Style Server","start":"2026-10-13","end":"2026-10-14"}}]"#
        )));
        assert_eq!(d.day_date(days[1]), "2026-10-13");
        assert_eq!(d.day_date(more), "2026-10-14");
        assert!(!d.can_undo());
        let v = shown(&d, Some(S2));
        assert_eq!(v.get("days").unwrap().as_array().unwrap()[1].str_field("date"), "2026-10-14");
        // Without the card, the film's own date.
        d.set_card(None);
        assert_eq!(d.day_date(days[1]), "2026-10-06");
        // Dating it by hand counts its place again.
        d.set_card(two());
        d.set_day_date(more, "2026-10-08");
        assert_eq!(d.day_date(more), "2026-10-08");
    }

    #[test]
    fn new_scenes_and_days_are_born_into_the_picked_shoot() {
        let (mut d, _, _) = lets_bake();
        d.set_card(two());
        d.set_born_in(Some(S2));
        let s = d.create_scene("10");
        assert_eq!(d.own_shoot(s).as_deref(), Some(S2));
        let day = d.create_day();
        assert_eq!(d.own_shoot(day).as_deref(), Some(S2));
        assert_eq!(d.day_date(day), "2026-10-07", "the shoot's next day");
        assert_eq!(d.day_label(day).as_deref(), Some("Day 2"));
        d.set_born_in(None);
        let plain = d.create_scene("11");
        assert!(!d.names_shoot(plain));
    }

    #[test]
    fn the_converter_reads_the_headings_and_writes_only_when_asked() {
        let (mut d, scenes, days) = lets_bake();
        let stray = d.create_scene("12");
        d.set_card(two());
        d.clear_history();
        let plan = d.shoots_from_sections();
        assert_eq!(plan.scenes.len(), 9);
        assert!(plan.scenes[..6].iter().all(|a| a.shoot == S1 && a.why == "section"));
        assert!(plan.scenes[6..8].iter().all(|a| a.shoot == S2 && a.why == "section"));
        let last = plan.scenes.iter().find(|a| a.id == stray).unwrap();
        assert_eq!((last.shoot.as_str(), last.why), (S1, "stray"));
        assert_eq!(plan.days.iter().map(|a| (a.shoot.as_str(), a.why)).collect::<Vec<_>>(), vec![(S1, "date"), (S2, "date")]);
        assert_eq!(plan.changes(), 11);
        assert!(!d.can_undo(), "the dry run writes nothing");
        let said = json::parse(&d.shoot_plan_json(&plan)).unwrap();
        assert_eq!(said.get("changes").and_then(json::Json::as_f64), Some(11.0));
        assert_eq!(said.get("scenes").unwrap().as_array().unwrap()[7].str_field("shootLabel"), "Style Server");

        assert_eq!(d.apply_shoot_plan(&plan), 11);
        assert_eq!(d.own_shoot(scenes[0]).as_deref(), Some(S1));
        assert_eq!(d.own_shoot(scenes[7]).as_deref(), Some(S2));
        assert_eq!(d.own_shoot(days[1]).as_deref(), Some(S2));
        assert_eq!(d.day_date(days[1]), "2026-10-06");
        // Sections are his: untouched.
        assert_eq!(d.sequences_in_order().len(), 3);
        // A second run has nothing left to do.
        assert_eq!(d.shoots_from_sections().changes(), 0);
        // One undo step takes it all back.
        d.undo();
        assert!(!d.names_shoot(scenes[0]) && !d.names_shoot(days[1]));
    }

    #[test]
    fn a_heading_names_a_shoot_by_number_or_by_name() {
        let (mut d, _, _) = lets_bake();
        d.set_card(two());
        assert_eq!(d.shoot_of_heading("Shoot 1 — July 9").as_deref(), Some(S1));
        assert_eq!(d.shoot_of_heading("SHOOT 2: plates").as_deref(), Some(S2));
        assert_eq!(d.shoot_of_heading("Style Server — Day 1").as_deref(), Some(S2));
        assert_eq!(d.shoot_of_heading("Plated Portions"), None);
        assert_eq!(d.shoot_of_heading("Shoot 7"), None);
    }

    #[test]
    fn locations_narrow_to_the_shoot() {
        let (mut d, scenes, _) = lets_bake();
        let diner = d.create_location("Diner");
        let seamless = d.create_location("Orange Seamless");
        let empty = d.create_location("Not Yet");
        d.set_scene_location(scenes[0], Some(diner));
        d.set_scene_location(scenes[6], Some(seamless));
        d.set_card(two());
        let v = shown(&d, Some(S2));
        let places = v.get("locations").unwrap().as_array().unwrap();
        let of = |id: Id| places.iter().find(|p| p.str_field("id") == id.0.to_string()).unwrap();
        assert_eq!(of(diner).get("inShoot").and_then(json::Json::as_bool), Some(false));
        assert_eq!(of(seamless).get("inShoot").and_then(json::Json::as_bool), Some(true));
        assert_eq!(of(empty).get("inShoot").and_then(json::Json::as_bool), Some(true), "an empty place is never hidden");
    }
}
