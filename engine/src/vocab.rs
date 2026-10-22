//! Project vocabularies.
//!
//! Size, angle, movement, lens, support, priority, POV and tags each have one
//! master list, and it belongs to the project rather than to the app. Daybreak
//! runs 20.7 / 27 / 37 / 47 / 57mm; The Turning runs 24 / 29 / 35 / 50mm. Neither
//! is a default worth shipping.
//!
//! Two rules, and they only look contradictory:
//!
//!   - **If it is not on the list, it is not in a dropdown.** One place to edit,
//!     no hidden alternates anywhere in the app.
//!   - **Typing a new value teaches the project.** Entering a lens the list has
//!     never seen adds it, permanently, rather than rejecting it.
//!
//! Together they mean the list is always complete without ever being in the way.

use crate::doc::Doc;
use crate::id::Id;
use crate::store::Kind;
use crate::value::Value;

/// Vocabulary field names, without the `vocab_` prefix the records carry.
pub const SIZE: &str = "size";
pub const ANGLE: &str = "angle";
pub const MOVEMENT: &str = "movement";
pub const LENS: &str = "lens";
pub const SUPPORT: &str = "support";
pub const PRIORITY: &str = "priority";
pub const POV: &str = "pov";
pub const TAGS: &str = "tags";
/// Extenders, expanders, diopters — several to a shot. Fed by the spec sheet.
pub const MODIFIERS: &str = "modifiers";
/// Filters — several to a shot. Fed by the spec sheet. Not `filter`, which
/// is the table's filter command.
pub const LENS_FILTERS: &str = "lens_filters";

pub const ALL: [&str; 10] = [SIZE, ANGLE, MOVEMENT, LENS, MODIFIERS, LENS_FILTERS, SUPPORT, PRIORITY, POV, TAGS];

/// **His own lists**, given 2026-08-22, in the order he wrote them — which for
/// shot size is the order the trade reads sizes in and is not alphabetical.
///
/// The note at the top of this file says no default is worth shipping, and for
/// lenses that is still true: a lens list is a fact about the glass on the
/// truck this week. These four are not that. Size, angle, movement and the
/// gear under the camera are how *he* works on every film, so a new project
/// starting empty means typing the same sixteen sizes again.
///
/// A project is given these **once**, and never has anything taken away: his
/// own terms stay, and are simply kept after the standing ones.
pub const DEFAULT_SIZES: [&str; 16] = [
    "ESTAB.", "W", "M", "M/OTS", "MCU", "CU", "CU/OTS", "INSERT", "ECU",
    "COWBOY", "FULL", "POV", "MWS", "W/TS", "TS", "W/OTS",
];

pub const DEFAULT_EQUIPMENT: [&str; 10] = [
    "Handheld", "Sticks", "Dana Dolly", "Hostess Tray", "Hood Mount",
    "Apple Boxes", "On Ground", "Dolly", "Jib", "Gimbal",
];

pub const DEFAULT_ANGLES: [&str; 10] = [
    "Front On", "3/4", "Profile", "Low", "High", "Top-Down", "Short-Sided",
    "Eye Level", "POV", "Ground Level",
];

pub const DEFAULT_MOVEMENTS: [&str; 10] = [
    "Loose Pan/Tilt", "Static", "Tracking Forward", "Tracking Backward",
    "Push-In", "Pull-Out", "Feel the Force", "Follow Action", "Pan", "Tilt",
];

/// Where the "this project has had its standing lists" mark is kept.
const SEEDED: &str = "vocab_seeded";

pub(crate) fn key(name: &str) -> String {
    format!("vocab_{name}")
}

/// Where a list's lock is kept — beside the list itself, on the project
/// record, so it travels with the project and syncs like anything else.
fn lock_key(name: &str) -> String {
    format!("vocab_{name}_locked")
}

/// Where a list's stored colours are kept — Ref 55.
///
/// One field beside the list rather than one field per term: a term is a piece
/// of text a person typed and turning it into a record key would make every
/// rename an orphaning. Held as a list of `term=RRGGBB`, in no particular
/// order, and only terms that have actually been given a colour appear.
fn colour_key(name: &str) -> String {
    format!("vocab_{name}_colours")
}

/// `("M/OTS", "2B6CB0")` out of `"M/OTS=2B6CB0"`. The term may contain
/// anything at all, `=` included, so the split is from the **right**.
fn split_colour(entry: &str) -> Option<(&str, &str)> {
    let at = entry.rfind('=')?;
    let (term, hex) = (entry[..at].trim(), entry[at + 1..].trim());
    if term.is_empty() || hex.is_empty() {
        return None;
    }
    Some((term, hex))
}

impl Doc {
    /// The project record, if one has been created.
    pub fn project_id(&self) -> Option<Id> {
        self.store().of_kind(&Kind::Project).first().map(|r| r.id)
    }

    pub fn vocabulary(&self, name: &str) -> Vec<String> {
        let project = match self.project_id() {
            Some(id) => id,
            None => return Vec::new(),
        };
        self.store()
            .get(project)
            .and_then(|r| r.get(&key(name)).cloned())
            .and_then(|v| {
                v.as_list().map(|items| {
                    items
                        .iter()
                        .filter_map(|i| i.as_text().map(|s| s.to_string()))
                        .collect()
                })
            })
            .unwrap_or_default()
    }

    pub fn set_vocabulary(&mut self, name: &str, values: &[&str]) {
        let project = match self.project_id() {
            Some(id) => id,
            None => return,
        };
        let list = Value::List(values.iter().map(|s| Value::text(*s)).collect());
        self.set(project, &key(name), list);
    }

    /// **The standing lists, put on a project once.**
    ///
    /// Returns true if anything was added, so a caller knows whether to save.
    /// It runs at most once per project — the mark lives on the project record
    /// and syncs with it, so a second machine opening the same film does not
    /// do it again.
    ///
    /// Nothing is removed and nothing is reordered away: the standing terms go
    /// first, in his order, and anything the project had already learned that
    /// is not among them follows.
    pub fn seed_standing_vocabularies(&mut self) -> bool {
        let Some(project) = self.project_id() else {
            return false;
        };
        let already = self
            .store()
            .get(project)
            .and_then(|r| r.get(SEEDED).cloned())
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if already {
            return false;
        }
        for (field, standing) in [
            (SIZE, &DEFAULT_SIZES[..]),
            (ANGLE, &DEFAULT_ANGLES[..]),
            (MOVEMENT, &DEFAULT_MOVEMENTS[..]),
            (SUPPORT, &DEFAULT_EQUIPMENT[..]),
        ] {
            let held = self.vocabulary(field);
            let mut list: Vec<String> = standing.iter().map(|s| s.to_string()).collect();
            for value in held {
                if !standing.iter().any(|s| s.eq_ignore_ascii_case(&value)) {
                    list.push(value);
                }
            }
            let borrowed: Vec<&str> = list.iter().map(|s| s.as_str()).collect();
            self.set_vocabulary(field, &borrowed);
        }
        self.set(project, SEEDED, Value::Bool(true));
        true
    }

    /// **A locked list stops learning.**
    ///
    /// The two rules above — "if it is not on the list it is not in a
    /// dropdown" and "typing a new value teaches the project" — are what make
    /// a list complete without being in the way. But by the time a project is
    /// shooting, the second rule is the one that hurts: a stray "Handheld " or
    /// a mistyped "37mmm" becomes a permanent near-duplicate of a term that
    /// was already right. Locking says *this list is finished*: nothing new
    /// can be learned into it, by any door — the table, the page, the MCP.
    /// Existing values still read, still write, still clear. Unlocking is one
    /// click on the project's own settings, where the lists live.
    pub fn vocabulary_locked(&self, name: &str) -> bool {
        self.project_id()
            .and_then(|id| self.store().get(id))
            .and_then(|r| r.get(&lock_key(name)).cloned())
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
    }

    pub fn set_vocabulary_locked(&mut self, name: &str, locked: bool) {
        if let Some(project) = self.project_id() {
            self.set(project, &lock_key(name), Value::Bool(locked));
        }
    }

    /// **The colour a term has been given, if it has been given one.**
    ///
    /// Ref 55. Nothing is derived here: a term with no stored colour answers
    /// `None`, and the app falls back to hashing the word — which is what it
    /// has always done and remains the right default, because the eye learns
    /// that all the wides are that green without anybody choosing anything.
    /// A stored colour simply wins over the hash.
    pub fn term_colour(&self, name: &str, value: &str) -> Option<String> {
        if self.cast_field().as_deref() == Some(name) {
            let wanted = value.trim();
            return self.term_colours(name).into_iter().find(|(t, _)| t.eq_ignore_ascii_case(wanted)).map(|(_, h)| h);
        }
        let wanted = value.trim();
        self.project_id()
            .and_then(|id| self.store().get(id))
            .and_then(|r| r.get(&colour_key(name)).cloned())
            .and_then(|v| match v {
                Value::List(items) => Some(items),
                _ => None,
            })?
            .iter()
            .filter_map(|item| item.as_text())
            .filter_map(split_colour)
            .find(|(term, _)| term.eq_ignore_ascii_case(wanted))
            .map(|(_, hex)| hex.to_string())
    }

    /// Every term on this list that has a colour: the ones given one, and —
    /// on the Cast column — **every character, in billing order** (his ask,
    /// 2026-10-17: *"a color for the whole film, usually in order of lead,
    /// starting with red"*): one he gave a colour keeps it; the rest take the
    /// next of `CAST_COLOURS` not already worn, in the order the cast list
    /// runs. Read here, so the shot list's chips, the plans, the portal and
    /// paper all agree; never written until he picks one.
    pub fn term_colours(&self, name: &str) -> Vec<(String, String)> {
        let mut out = self.stored_term_colours(name);
        if self.cast_field().as_deref() == Some(name) {
            let taken: Vec<String> = out.iter().map(|(_, h)| h.to_uppercase()).collect();
            let mut free = CAST_COLOURS.iter().filter(|h| !taken.contains(&h.to_string())).copied().collect::<Vec<_>>().into_iter().cycle();
            for who in self.vocabulary(name) {
                if who.trim().is_empty() || out.iter().any(|(t, _)| t.eq_ignore_ascii_case(who.trim())) {
                    continue;
                }
                let hex = free.next().unwrap_or(CAST_COLOURS[0]);
                out.push((who.trim().to_string(), hex.to_string()));
            }
        }
        out
    }

    /// The colours he gave, as stored — nothing worked out.
    pub fn stored_term_colours(&self, name: &str) -> Vec<(String, String)> {
        self.project_id()
            .and_then(|id| self.store().get(id))
            .and_then(|r| r.get(&colour_key(name)).cloned())
            .and_then(|v| match v {
                Value::List(items) => Some(items),
                _ => None,
            })
            .unwrap_or_default()
            .iter()
            .filter_map(|item| item.as_text())
            .filter_map(split_colour)
            .map(|(term, hex)| (term.to_string(), hex.to_string()))
            .collect()
    }

    /// Give a term a colour, or — with an empty one — hand it back to the hash.
    ///
    /// Handing it back is a real act and not the same as never having chosen:
    /// it is the only way out of a colour you have decided against, and there
    /// is no second verb for it.
    pub fn set_term_colour(&mut self, name: &str, value: &str, hex: &str) {
        let term = value.trim().to_string();
        if term.is_empty() {
            return;
        }
        let hex = hex.trim().trim_start_matches('#').to_uppercase();
        let mut kept: Vec<(String, String)> = self
            .stored_term_colours(name)
            .into_iter()
            .filter(|(held, _)| !held.eq_ignore_ascii_case(&term))
            .collect();
        if !hex.is_empty() {
            kept.push((term, hex));
        }
        self.write_term_colours(name, kept);
    }

    fn write_term_colours(&mut self, name: &str, colours: Vec<(String, String)>) {
        let Some(project) = self.project_id() else { return };
        let list = Value::List(
            colours
                .into_iter()
                .map(|(term, hex)| Value::Text(format!("{term}={hex}")))
                .collect(),
        );
        self.set(project, &colour_key(name), list);
    }

    pub fn vocabulary_contains(&self, name: &str, value: &str) -> bool {
        self.vocabulary(name)
            .iter()
            .any(|v| v.eq_ignore_ascii_case(value))
    }

    /// Add a value to a master list if it is not already there. Returns true if
    /// the project learned something.
    pub fn learn(&mut self, name: &str, value: &str) -> bool {
        let trimmed = value.trim();
        if trimmed.is_empty() || self.vocabulary_contains(name, trimmed) {
            return false;
        }
        // The lock, at the one place a list grows.
        if self.vocabulary_locked(name) {
            return false;
        }
        let project = match self.project_id() {
            Some(id) => id,
            None => return false,
        };
        let mut values = self.vocabulary(name);
        values.push(trimmed.to_string());
        let list = Value::List(values.into_iter().map(Value::Text).collect());
        self.set(project, &key(name), list);
        true
    }

    /// Set a single-value vocabulary field on a shot, teaching the project the
    /// value if it is new. This is the path the table view's cells use.
    pub fn set_vocab_field(&mut self, shot: Id, name: &str, value: &str) {
        let trimmed = value.trim();
        // A locked list refuses a term it does not hold — otherwise the lock
        // would only stop the *list* growing while the shots quietly filled
        // with values that are on no list at all, which is worse than either.
        // Clearing a cell is always allowed: emptying is not adding.
        if !trimmed.is_empty()
            && self.vocabulary_locked(name)
            && !self.vocabulary_contains(name, trimmed)
        {
            return;
        }
        let tx = self.begin("Change shot");

        self.learn(name, value);
        self.set(shot, name, Value::text(trimmed));
        self.end(tx);
    }

    /// Set a multi-value vocabulary field — angle, tags, POV — teaching the
    /// project any value it has not seen.
    pub fn set_vocab_list(&mut self, shot: Id, name: &str, values: &[&str]) {
        // Same rule as the single-value path: on a locked list, a term the
        // list does not hold simply does not land. The others still do.
        let locked = self.vocabulary_locked(name);
        let kept: Vec<&str> = values
            .iter()
            .copied()
            .filter(|v| !locked || v.trim().is_empty() || self.vocabulary_contains(name, v.trim()))
            .collect();
        let values = &kept[..];
        let tx = self.begin("Change shot");

        for value in values {
            self.learn(name, value);
        }
        let list = Value::List(
            values
                .iter()
                .map(|s| Value::text(s.trim()))
                .filter(|v| !v.as_text().unwrap_or_default().is_empty())
                .collect(),
        );
        self.set(shot, name, list);
        self.end(tx);
    }
}

// ---- what a list is actually used for ----------------------------------

/// Kinds that can carry a vocabulary value. Priority and POV live on scenes;
/// everything else lives on shots, so both have to be looked at.
fn carriers() -> [Kind; 2] {
    [Kind::Shot, Kind::Scene]
}

fn matches(value: &Value, wanted: &str) -> bool {
    match value {
        Value::Text(text) => text.eq_ignore_ascii_case(wanted),
        Value::List(items) => items
            .iter()
            .filter_map(|item| item.as_text())
            .any(|text| text.eq_ignore_ascii_case(wanted)),
        _ => false,
    }
}

impl Doc {
    /// Every record currently carrying a value in this field, with what it holds.
    fn records_using(&self, field: &str, value: &str) -> Vec<(Id, Value)> {
        let mut found = Vec::new();
        for kind in carriers() {
            for record in self.store().of_kind(&kind) {
                if let Some(held) = record.get(field) {
                    if matches(held, value) {
                        found.push((record.id, held.clone()));
                    }
                }
            }
        }
        found
    }

    /// **Which shots and scenes carry a term** — by id, so a reply can name
    /// them. The same match the counts below use: case ignored, and a term
    /// inside a multi-value field counts.
    pub fn carrying(&self, field: &str, value: &str) -> Vec<Id> {
        self.records_using(field, value).into_iter().map(|(id, _)| id).collect()
    }

    /// How many shots or scenes use each value on a master list, in list order.
    /// The settings screen shows this next to each entry so deleting one is an
    /// informed decision rather than a surprise.
    pub fn vocab_usage(&self, field: &str) -> Vec<(String, usize)> {
        self.vocabulary(field)
            .into_iter()
            .map(|value| {
                let count = self.records_using(field, &value).len();
                (value, count)
            })
            .collect()
    }

    /// Values in use that are not on the list — usually the result of an import
    /// from somebody else's sheet. Worth surfacing rather than leaving to be
    /// found in a dropdown that does not offer them.
    pub fn vocabulary_orphans(&self, field: &str) -> Vec<(String, usize)> {
        let known = self.vocabulary(field);
        let is_known = |value: &str| known.iter().any(|k| k.eq_ignore_ascii_case(value));

        let mut counts: Vec<(String, usize)> = Vec::new();
        for kind in carriers() {
            for record in self.store().of_kind(&kind) {
                let held = match record.get(field) {
                    Some(value) => value,
                    None => continue,
                };
                let values: Vec<String> = match held {
                    Value::Text(text) if !text.is_empty() => vec![text.clone()],
                    Value::List(items) => items
                        .iter()
                        .filter_map(|item| item.as_text().map(|s| s.to_string()))
                        .collect(),
                    _ => Vec::new(),
                };
                for value in values {
                    if is_known(&value) {
                        continue;
                    }
                    match counts.iter_mut().find(|(existing, _)| *existing == value) {
                        Some((_, count)) => *count += 1,
                        None => counts.push((value, 1)),
                    }
                }
            }
        }
        counts
    }

    /// Rename a value everywhere it is used — the list and every shot or scene
    /// carrying it — as one undoable action however many it touches. Returns how
    /// many records changed.
    pub fn rename_vocabulary_value(&mut self, field: &str, from: &str, to: &str) -> usize {
        let to = to.trim().to_string();
        if to.is_empty() || from.eq_ignore_ascii_case(&to) {
            return 0;
        }

        let tx = self.begin("Rename value");
        let affected = self.records_using(field, from);

        for (id, held) in &affected {
            let replacement = match held {
                Value::List(items) => Value::List(
                    items
                        .iter()
                        .map(|item| match item.as_text() {
                            Some(text) if text.eq_ignore_ascii_case(from) => Value::text(&to),
                            _ => item.clone(),
                        })
                        .collect(),
                ),
                _ => Value::text(&to),
            };
            self.set(*id, field, replacement);
        }

        // The list itself, keeping its order. Renaming onto a value already on
        // the list folds the two together rather than listing it twice, which is
        // what folding an orphan into an existing value amounts to.
        let mut renamed: Vec<String> = Vec::new();
        for value in self.vocabulary(field) {
            let value = if value.eq_ignore_ascii_case(from) {
                to.clone()
            } else {
                value
            };
            if !renamed.iter().any(|kept| kept.eq_ignore_ascii_case(&value)) {
                renamed.push(value);
            }
        }
        let borrowed: Vec<&str> = renamed.iter().map(|s| s.as_str()).collect();
        self.set_vocabulary(field, &borrowed);

        // **A renamed term keeps the colour it was given.** Ref 55 — the
        // colour belongs to the thing, not to the spelling, and a term that
        // went grey because somebody fixed a typo would teach people not to
        // fix typos. Renaming *onto* an existing term folds the two together
        // above, so the one being kept keeps its own colour.
        let carried: Vec<(String, String)> = self
            .stored_term_colours(field)
            .into_iter()
            .map(|(term, hex)| {
                if term.eq_ignore_ascii_case(from) { (to.clone(), hex) } else { (term, hex) }
            })
            .fold(Vec::new(), |mut kept, (term, hex)| {
                if !kept.iter().any(|(held, _): &(String, String)| held.eq_ignore_ascii_case(&term)) {
                    kept.push((term, hex));
                }
                kept
            });
        self.write_term_colours(field, carried);

        self.end(tx);
        affected.len()
    }

    /// Take a value off a list and out of everything using it.
    ///
    /// Shots are left **empty** rather than falling back to something else —
    /// inventing a replacement would be worse than an obvious gap. One undoable
    /// action, and `vocab_usage` will have said how many it would touch.
    pub fn remove_vocabulary_value(&mut self, field: &str, value: &str) -> usize {
        let tx = self.begin("Remove value");
        let affected = self.records_using(field, value);

        for (id, held) in &affected {
            let replacement = match held {
                Value::List(items) => Value::List(
                    items
                        .iter()
                        .filter(|item| {
                            !item
                                .as_text()
                                .map(|text| text.eq_ignore_ascii_case(value))
                                .unwrap_or(false)
                        })
                        .cloned()
                        .collect(),
                ),
                _ => Value::Null,
            };
            self.set(*id, field, replacement);
        }

        let remaining: Vec<String> = self
            .vocabulary(field)
            .into_iter()
            .filter(|existing| !existing.eq_ignore_ascii_case(value))
            .collect();
        let borrowed: Vec<&str> = remaining.iter().map(|s| s.as_str()).collect();
        self.set_vocabulary(field, &borrowed);
        // The colour goes with it, or a term typed again later would come back
        // wearing a colour nobody chose for it.
        self.set_term_colour(field, value, "");

        self.end(tx);
        affected.len()
    }
}

// ---- a list edited as a list -------------------------------------------
//
// Everything above grows a list one term at a time, as a side effect of a
// shot being given a value. That is the right door for a person typing into
// a cell. It is the wrong one for "these nine lenses arrived on the truck":
// before 2026-09-30 the only way Claude could put a lens on a film's list was
// to set some shot's lens to it and set it back, one lens at a time. These are
// the list's own verbs — add several, say where they go, put the list in
// order — each one write to the project record, so each is one undo.

/// Whether `name` is one of the lists a project keeps.
pub fn is_list(name: &str) -> bool {
    ALL.contains(&name)
}

/// Where new terms go on a list.
#[derive(Clone, Debug, PartialEq)]
pub enum ListPlace {
    /// After everything already there — what typing into a cell does.
    End,
    Start,
    /// Just before a term already on the list.
    Before(String),
    /// Just after a term already on the list.
    After(String),
    /// Among the others by the number in them, so a 40mm lands between the
    /// 35mm and the 50mm. A term with no number goes at the end.
    ByNumber,
}

/// Why a list edit did nothing.
#[derive(Clone, Debug, PartialEq)]
pub enum ListRefusal {
    /// The film has no project record yet, so it has nowhere to keep a list.
    NoProject,
    /// The list is locked and the edit would have grown it.
    Locked,
    /// A term the edit named is not on the list.
    NotOnList(String),
}

/// What an add did: the terms that went on, and the ones already there.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ListAdded {
    pub added: Vec<String>,
    pub already: Vec<String>,
}

/// **The number a term is about** — its focal length, for a lens.
///
/// A number written against "mm" wins over any other, so "Cooke S4 32mm" is
/// 32 and not 4; otherwise the first number in it, so "85 Macro" is 85 and
/// "24-70mm" is 24. Decimals count: Daybreak's 20.7mm is 20.7.
pub fn number_in(term: &str) -> Option<f64> {
    let chars: Vec<char> = term.chars().collect();
    let mut first: Option<f64> = None;
    let mut at = 0;
    while at < chars.len() {
        if !chars[at].is_ascii_digit() {
            at += 1;
            continue;
        }
        let start = at;
        while at < chars.len() && chars[at].is_ascii_digit() {
            at += 1;
        }
        if at + 1 < chars.len() && chars[at] == '.' && chars[at + 1].is_ascii_digit() {
            at += 1;
            while at < chars.len() && chars[at].is_ascii_digit() {
                at += 1;
            }
        }
        let number: f64 = chars[start..at].iter().collect::<String>().parse().ok()?;
        // A zoom is its wide end: "24-70mm" is 24, and its "mm" still counts.
        if at + 1 < chars.len() && (chars[at] == '-' || chars[at] == '–') && chars[at + 1].is_ascii_digit() {
            at += 1;
            while at < chars.len() && (chars[at].is_ascii_digit() || chars[at] == '.') {
                at += 1;
            }
        }
        let rest: String = chars[at..].iter().collect::<String>();
        if rest.trim_start().to_ascii_lowercase().starts_with("mm") {
            return Some(number);
        }
        first.get_or_insert(number);
    }
    first
}

/// Where `term` goes among `list` by its number: before the first term with a
/// bigger one, else just after the last term that has one, else at the end.
pub(crate) fn place_by_number(list: &[String], term: &str) -> usize {
    let Some(wanted) = number_in(term) else {
        return list.len();
    };
    let mut after_last_numbered = None;
    for (at, held) in list.iter().enumerate() {
        if let Some(number) = number_in(held) {
            if number > wanted {
                return at;
            }
            after_last_numbered = Some(at + 1);
        }
    }
    after_last_numbered.unwrap_or(list.len())
}

/// How to put a list in order.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum ListSort {
    /// By the number in each term — focal length for lenses. Terms with no
    /// number keep their order, after the ones that have one.
    ByNumber,
    /// As a person reads them: `37mm` before `100mm`, case ignored.
    Alphabetical,
}

impl Doc {
    /// The list's own spelling of `term`, if the list holds it.
    fn on_list(&self, name: &str, term: &str) -> Option<String> {
        let wanted = term.trim();
        self.vocabulary(name)
            .into_iter()
            .find(|held| held.eq_ignore_ascii_case(wanted))
    }

    /// **Put several terms on a list at once**, in the order given, where
    /// `place` says. Terms already on it (case ignored) are left where they
    /// are and reported, never moved or doubled.
    ///
    /// A locked list refuses the whole add if any of it is new — the lock is a
    /// decision somebody made, and the way past it is to unlock, not to find a
    /// door the lock does not cover. One write, so one undo.
    pub fn add_to_vocabulary(
        &mut self,
        name: &str,
        values: &[&str],
        place: &ListPlace,
    ) -> Result<ListAdded, ListRefusal> {
        let project = self.project_id().ok_or(ListRefusal::NoProject)?;
        let mut list = self.vocabulary(name);
        let mut said = ListAdded::default();
        for value in values {
            let term = value.trim();
            if term.is_empty() {
                continue;
            }
            if list.iter().any(|held| held.eq_ignore_ascii_case(term)) {
                if !said.already.iter().any(|a| a.eq_ignore_ascii_case(term)) {
                    said.already.push(term.to_string());
                }
            } else if !said.added.iter().any(|a| a.eq_ignore_ascii_case(term)) {
                said.added.push(term.to_string());
            }
        }
        if said.added.is_empty() {
            return Ok(said);
        }
        if self.vocabulary_locked(name) {
            return Err(ListRefusal::Locked);
        }

        let anchor = |list: &[String], term: &str| {
            list.iter()
                .position(|held| held.eq_ignore_ascii_case(term.trim()))
                .ok_or_else(|| ListRefusal::NotOnList(term.trim().to_string()))
        };
        match place {
            ListPlace::End => list.extend(said.added.iter().cloned()),
            ListPlace::Start => {
                list.splice(0..0, said.added.iter().cloned());
            }
            ListPlace::Before(term) => {
                let at = anchor(&list, term)?;
                list.splice(at..at, said.added.iter().cloned());
            }
            ListPlace::After(term) => {
                let at = anchor(&list, term)? + 1;
                list.splice(at..at, said.added.iter().cloned());
            }
            ListPlace::ByNumber => {
                for term in &said.added {
                    let at = place_by_number(&list, term);
                    list.insert(at, term.clone());
                }
            }
        }
        let list = Value::List(list.into_iter().map(Value::Text).collect());
        self.set(project, &key(name), list);
        Ok(said)
    }

    /// **Put a list in the order given.** Every term named has to be on the
    /// list already — ordering never adds — and the terms left unnamed keep
    /// their order after the named ones. Returns those, so a reply can say
    /// where they went. Nothing changes on any shot.
    pub fn order_vocabulary(&mut self, name: &str, order: &[&str]) -> Result<Vec<String>, ListRefusal> {
        let project = self.project_id().ok_or(ListRefusal::NoProject)?;
        let held = self.vocabulary(name);
        let mut ordered: Vec<String> = Vec::new();
        for term in order {
            if term.trim().is_empty() {
                continue;
            }
            let own = self
                .on_list(name, term)
                .ok_or_else(|| ListRefusal::NotOnList(term.trim().to_string()))?;
            if !ordered.contains(&own) {
                ordered.push(own);
            }
        }
        let rest: Vec<String> = held.into_iter().filter(|h| !ordered.contains(h)).collect();
        ordered.extend(rest.iter().cloned());
        let list = Value::List(ordered.into_iter().map(Value::Text).collect());
        self.set(project, &key(name), list);
        Ok(rest)
    }

    /// **Sort a list** — by number for glass, as read for words. Stable, so
    /// terms that tie keep the order they had.
    pub fn sort_vocabulary(&mut self, name: &str, by: ListSort) -> Result<(), ListRefusal> {
        let project = self.project_id().ok_or(ListRefusal::NoProject)?;
        let mut list = self.vocabulary(name);
        match by {
            ListSort::ByNumber => list.sort_by(|a, b| match (number_in(a), number_in(b)) {
                (Some(m), Some(n)) => m.partial_cmp(&n).unwrap_or(std::cmp::Ordering::Equal),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => std::cmp::Ordering::Equal,
            }),
            ListSort::Alphabetical => list.sort_by(|a, b| crate::natural::compare(a, b)),
        }
        let list = Value::List(list.into_iter().map(Value::Text).collect());
        self.set(project, &key(name), list);
        Ok(())
    }
}

#[cfg(test)]
mod edited_as_a_list {
    use super::*;
    use crate::stamp::DeviceId;

    fn lenses(terms: &[&str]) -> Doc {
        let mut d = Doc::new(DeviceId(1));
        d.create_project("Call Her Back");
        d.set_vocabulary(LENS, terms);
        d
    }

    #[test]
    fn the_number_a_lens_is_about() {
        assert_eq!(number_in("18mm"), Some(18.0));
        assert_eq!(number_in("20.7mm"), Some(20.7));
        assert_eq!(number_in("Cooke S4 32mm"), Some(32.0));
        assert_eq!(number_in("24-70mm"), Some(24.0));
        assert_eq!(number_in("85 Macro"), Some(85.0));
        assert_eq!(number_in("Zoom"), None);
    }

    #[test]
    fn several_go_on_in_one_undo_and_duplicates_are_reported() {
        let mut d = lenses(&["18mm", "35mm"]);
        let said = d
            .transact("Add to list", |d| d.add_to_vocabulary(LENS, &["25mm", "35MM", "50mm", "25mm"], &ListPlace::End))
            .expect("adds");
        assert_eq!(said.added, vec!["25mm", "50mm"]);
        assert_eq!(said.already, vec!["35MM"]);
        assert_eq!(d.vocabulary(LENS), vec!["18mm", "35mm", "25mm", "50mm"]);
        d.undo();
        assert_eq!(d.vocabulary(LENS), vec!["18mm", "35mm"], "one undo takes the whole add back");
    }

    #[test]
    fn by_number_keeps_the_glass_in_order() {
        let mut d = lenses(&["18mm", "35mm", "85mm", "Diopter"]);
        d.add_to_vocabulary(LENS, &["50mm", "14mm", "135mm", "Probe", "40mm"], &ListPlace::ByNumber)
            .expect("adds");
        assert_eq!(
            d.vocabulary(LENS),
            vec!["14mm", "18mm", "35mm", "40mm", "50mm", "85mm", "135mm", "Diopter", "Probe"]
        );
    }

    #[test]
    fn before_and_after_a_term_on_the_list() {
        let mut d = lenses(&["18mm", "85mm"]);
        d.add_to_vocabulary(LENS, &["25mm", "35mm"], &ListPlace::After("18MM".into())).expect("adds");
        d.add_to_vocabulary(LENS, &["14mm"], &ListPlace::Before("18mm".into())).expect("adds");
        assert_eq!(d.vocabulary(LENS), vec!["14mm", "18mm", "25mm", "35mm", "85mm"]);
        assert_eq!(
            d.add_to_vocabulary(LENS, &["50mm"], &ListPlace::After("40mm".into())),
            Err(ListRefusal::NotOnList("40mm".into()))
        );
        assert_eq!(d.vocabulary(LENS).len(), 5, "a refused add changes nothing");
    }

    #[test]
    fn a_locked_list_refuses_to_grow_but_not_to_be_asked_what_it_holds() {
        let mut d = lenses(&["18mm"]);
        d.set_vocabulary_locked(LENS, true);
        assert_eq!(d.add_to_vocabulary(LENS, &["25mm"], &ListPlace::End), Err(ListRefusal::Locked));
        let said = d.add_to_vocabulary(LENS, &["18mm"], &ListPlace::End).expect("nothing new is not a refusal");
        assert!(said.added.is_empty());
        assert_eq!(d.vocabulary(LENS), vec!["18mm"]);
    }

    #[test]
    fn ordering_names_terms_and_the_rest_follow() {
        let mut d = lenses(&["50mm", "18mm", "Zoom", "35mm"]);
        let rest = d.order_vocabulary(LENS, &["18mm", "35MM"]).expect("orders");
        assert_eq!(rest, vec!["50mm", "Zoom"]);
        assert_eq!(d.vocabulary(LENS), vec!["18mm", "35mm", "50mm", "Zoom"]);
        assert_eq!(
            d.order_vocabulary(LENS, &["40mm"]),
            Err(ListRefusal::NotOnList("40mm".into()))
        );
    }

    #[test]
    fn sorting_by_number_and_as_read() {
        let mut d = lenses(&["100mm", "Zoom", "20.7mm", "37mm", "Diopter"]);
        d.sort_vocabulary(LENS, ListSort::ByNumber).expect("sorts");
        assert_eq!(d.vocabulary(LENS), vec!["20.7mm", "37mm", "100mm", "Zoom", "Diopter"]);
        d.sort_vocabulary(LENS, ListSort::Alphabetical).expect("sorts");
        assert_eq!(d.vocabulary(LENS), vec!["20.7mm", "37mm", "100mm", "Diopter", "Zoom"]);
    }
}


/// **Cast colours in billing order** (2026-10-17): the lead red, then blue,
/// green, orange, purple, yellow, teal, pink — the kit's highlight colours
/// first, then its inks — and round again for a big cast.
pub const CAST_COLOURS: &[&str] = &[
    "E5484D", "0A6CE8", "16A34A", "D97706", "7B4BC4", "CA8A04", "2C7A7B", "DB2777", "4C51BF", "B4531B", "A33574", "2F7A44",
];
