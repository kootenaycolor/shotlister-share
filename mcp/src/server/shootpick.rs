//! **One shoot of a project that shoots more than once** (stage 5 step 5,
//! 2026-10-14). `scenes`, `shots`, `schedule`, `locations` and `kit` take an
//! optional `shoot` — its name (`Shoot 2`, `Malibu Pickup`), its number
//! (`2`) or the portal's slug (`shoot-2`) — and answer for that shoot only.
//! A project with one shoot ignores it.
//!
//! **What a shoot is, today.** Scenes do not yet belong to shoots (stage 5
//! step 4 makes them); a shoot is read off what New Shoot leaves behind:
//!
//! - a **section** whose title starts with the shoot's name, before a
//!   separator: `Shoot 1 — July 9`, `Shoot 2 - Style Server`,
//!   `Shoot 3 · November 3` (two sections may share a shoot);
//! - a **day** named after the shoot: `Day 2 · Shoot 2`.
//!
//! A name counts as a shoot when it reads `Shoot N`, or when a section and a
//! day both carry it (New Shoot's own `Malibu Pickup`). The shoot's scenes are
//! its sections' scenes and any scene with shots on its days (pickups); its
//! shots are those scenes' shots, and of other scenes only the ones on its
//! days; its days are the days named after it, or, when none is, the days
//! its scenes' shots are on.
//!
//! **Once the film carries shoot fields** (stage 5 step 4 piece D: a scene or
//! a day names its shoot) and the card lists the project's shoots, that is
//! the rule instead, the same one Studio's picker uses
//! (`Doc::scene_shoot`, `Doc::day_shoot`): the shoot's scenes, those scenes'
//! shots and the shoot's days. The section/day-name rule above is only the
//! fallback for a project with no shoot fields.

use std::collections::BTreeSet;

use shotlister_engine::{f, Doc, Id};

use crate::json::Json;

/// One shoot, as the film holds it today.
pub(crate) struct ShootPick {
    pub name: String,
    pub key: String,
    pub scenes: BTreeSet<Id>,
    pub placements: BTreeSet<Id>,
    pub days: Vec<Id>,
}

/// A title's name part: before ` · `, ` — `, ` – ` or ` - `.
fn name_part(title: &str) -> String {
    let mut cut = title.len();
    for sep in [" \u{00b7} ", " \u{2014} ", " \u{2013} ", " - ", " | "] {
        if let Some(at) = title.find(sep) {
            cut = cut.min(at);
        }
    }
    title[..cut].split_whitespace().collect::<Vec<_>>().join(" ")
}

fn key_of(name: &str) -> String {
    let lower = name.to_lowercase();
    let flat = lower.replace(['-', '_'], " ");
    let words: Vec<&str> = flat.split_whitespace().collect();
    // `Shoot 2`, `shoot-2`, `Shoot 2 Pickups` → `shoot 2`
    if words.len() >= 2 && words[0] == "shoot" && words[1].chars().all(|c| c.is_ascii_digit()) {
        return format!("shoot {}", words[1].trim_start_matches('0'));
    }
    words.join(" ")
}

fn is_numbered(key: &str) -> bool {
    key.starts_with("shoot ") && key[6..].chars().all(|c| c.is_ascii_digit()) && key.len() > 6
}

fn text(doc: &Doc, id: Id, field: &str) -> String {
    doc.get(id).and_then(|r| r.text(field)).unwrap_or_default().trim().to_string()
}

/// Whether the film names shoots on its scenes or days (piece D's fields).
fn has_shoot_fields(doc: &Doc) -> bool {
    doc.scenes_in_order().into_iter().any(|s| doc.names_shoot(s)) || doc.days_in_order().into_iter().any(|d| doc.names_shoot(d))
}

/// Whether to go by the shoot fields: the film carries them and the card
/// lists two or more shoots to resolve them against.
fn by_fields(doc: &Doc) -> bool {
    doc.many_shoots() && has_shoot_fields(doc)
}

/// The card's shoots as `(key, name, id, also)`: `key` and `name` read the
/// way the section rule reads them (`shoot 2` / `Shoot 2`), `also` the
/// shoot's own name's key (`style server`), so either finds it.
fn card_shoots(doc: &Doc) -> Vec<(String, String, String, String)> {
    doc.shoots()
        .iter()
        .map(|s| {
            let kind = key_of(&s.kind);
            let label = key_of(&s.label);
            let numbered = if is_numbered(&kind) {
                Some(kind.clone())
            } else if is_numbered(&label) {
                Some(label.clone())
            } else {
                s.n.map(|n| format!("shoot {n}"))
            };
            match numbered {
                Some(k) => (k.clone(), format!("Shoot {}", &k[6..]), s.id.clone(), label),
                None => (label.clone(), s.label.clone(), s.id.clone(), label),
            }
        })
        .collect()
}

/// The project's shoots, `(key, name)` in order: by section, then by day.
pub(crate) fn shoots(doc: &Doc) -> Vec<(String, String)> {
    if by_fields(doc) {
        return card_shoots(doc).into_iter().map(|(k, n, _, _)| (k, n)).collect();
    }
    let sections: Vec<(String, String)> = doc
        .sequences_in_order()
        .into_iter()
        .map(|s| name_part(&text(doc, s, f::TITLE)))
        .filter(|n| !n.is_empty())
        .map(|n| (key_of(&n), n))
        .collect();
    let days: Vec<(String, String)> = doc
        .days_in_order()
        .into_iter()
        .map(|d| name_part(&text(doc, d, f::TITLE)))
        .filter(|n| !n.is_empty())
        .map(|n| (key_of(&n), n))
        .collect();
    let mut out: Vec<(String, String)> = Vec::new();
    for (key, name) in sections.iter().chain(days.iter()) {
        let counts = is_numbered(key) || (sections.iter().any(|(k, _)| k == key) && days.iter().any(|(k, _)| k == key));
        if counts && !out.iter().any(|(k, _)| k == key) {
            let shown = if is_numbered(key) { format!("Shoot {}", &key[6..]) } else { name.clone() };
            out.push((key.clone(), shown));
        }
    }
    out
}

/// The shoots' names, when there are two or more (for `summary`).
pub(crate) fn shoot_names(doc: &Doc) -> Vec<String> {
    let all = shoots(doc);
    if all.len() < 2 {
        return Vec::new();
    }
    all.into_iter().map(|(_, n)| n).collect()
}

/// The shoot `arguments` asks for: `None` when none is asked or the project
/// shoots once; a refusal naming the shoots when it is not one of them.
pub(crate) fn pick(doc: &Doc, arguments: &Json) -> Result<Option<ShootPick>, String> {
    let asked = arguments.get("shoot").and_then(|v| match v {
        Json::Number(n) => Some(format!("{}", *n as i64)),
        other => other.as_str().map(str::to_string),
    });
    let asked = match asked {
        Some(a) if !a.trim().is_empty() => a.trim().to_string(),
        _ => return Ok(None),
    };
    let all = shoots(doc);
    if all.len() < 2 {
        return Ok(None);
    }
    let wanted = if asked.chars().all(|c| c.is_ascii_digit()) {
        format!("shoot {}", asked.trim_start_matches('0'))
    } else {
        key_of(&name_part(&asked))
    };
    if by_fields(doc) {
        let listed = card_shoots(doc);
        let found = listed
            .iter()
            .find(|(k, _, _, _)| *k == wanted)
            .or_else(|| listed.iter().find(|(_, _, _, also)| *also == wanted || *also == key_of(&asked)));
        let Some((key, name, id, _)) = found.cloned() else {
            return Err(format!(
                "No shoot called {asked}. This project's shoots: {}.",
                all.iter().map(|(_, n)| n.as_str()).collect::<Vec<_>>().join(", ")
            ));
        };
        let scenes: BTreeSet<Id> = doc.scenes_of_shoot(&id).into_iter().collect();
        let placements: BTreeSet<Id> = scenes.iter().flat_map(|s| doc.placements_in_scene(*s)).collect();
        let days = doc.days_of_shoot(&id);
        return Ok(Some(ShootPick { name, key, scenes, placements, days }));
    }
    let Some((key, name)) = all.iter().find(|(k, _)| *k == wanted).cloned() else {
        return Err(format!(
            "No shoot called {asked}. This project's shoots: {}.",
            all.iter().map(|(_, n)| n.as_str()).collect::<Vec<_>>().join(", ")
        ));
    };

    let sections: Vec<Id> = doc
        .sequences_in_order()
        .into_iter()
        .filter(|s| key_of(&name_part(&text(doc, *s, f::TITLE))) == key)
        .collect();
    let named_days: Vec<Id> = doc
        .days_in_order()
        .into_iter()
        .filter(|d| key_of(&name_part(&text(doc, *d, f::TITLE))) == key)
        .collect();

    let mut scenes = BTreeSet::new();
    let mut placements = BTreeSet::new();
    for scene in doc.scenes_in_order() {
        let home = doc.get(scene).and_then(|r| r.ref_id(f::SEQUENCE));
        let ours = home.map(|h| sections.contains(&h)).unwrap_or(false);
        for p in doc.placements_in_scene(scene) {
            let day = doc.get(p).and_then(|r| r.ref_id(f::DAY));
            let on_ours = day.map(|d| named_days.contains(&d)).unwrap_or(false);
            if ours || on_ours {
                placements.insert(p);
                scenes.insert(scene);
            }
        }
        if ours {
            scenes.insert(scene);
        }
    }
    let days = if named_days.is_empty() {
        doc.days_in_order()
            .into_iter()
            .filter(|d| doc.placements_on_day(*d).iter().any(|p| placements.contains(p)))
            .collect()
    } else {
        named_days
    };
    Ok(Some(ShootPick { name, key, scenes, placements, days }))
}

/// **One of the card's shoots, by what he calls it** — its name, its number
/// or its slug, as `pick` reads them — for writing a scene into it (Move to
/// Shoot). `(id, name)`; a refusal naming the shoots when it is none of them.
pub(crate) fn card_shoot(doc: &Doc, asked: &str) -> Result<(String, String), String> {
    let listed = card_shoots(doc);
    if listed.is_empty() {
        return Err("This project has no shoots on its record (they come from his Notion Shoots rows).".to_string());
    }
    let asked = asked.trim();
    if let Some(s) = doc.shoot(asked) {
        let name = listed.iter().find(|(_, _, id, _)| *id == s.id).map(|(_, n, _, _)| n.clone()).unwrap_or(s.label.clone());
        return Ok((s.id.clone(), name));
    }
    let wanted = if !asked.is_empty() && asked.chars().all(|c| c.is_ascii_digit()) {
        format!("shoot {}", asked.trim_start_matches('0'))
    } else {
        key_of(&name_part(asked))
    };
    listed
        .iter()
        .find(|(k, _, _, _)| *k == wanted)
        .or_else(|| listed.iter().find(|(_, _, _, also)| *also == wanted || *also == key_of(asked)))
        .map(|(_, name, id, _)| (id.clone(), name.clone()))
        .ok_or_else(|| {
            format!(
                "No shoot called {asked}. This project's shoots: {}.",
                listed.iter().map(|(_, n, _, _)| n.as_str()).collect::<Vec<_>>().join(", ")
            )
        })
}

/// Whether a spec sheet's shoot name (`Shoot 2`) is this shoot.
pub(crate) fn same_shoot(name: &str, key: &str) -> bool {
    !name.trim().is_empty() && key_of(&name_part(name)) == key
}
