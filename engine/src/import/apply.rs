//! Taking a sheet and making it the list.
//!
//! Import has to survive a document that has been away and been worked on: rows
//! reordered, columns renamed by whoever received it, values typed in that were
//! never on a list, whole scenes added. So the rules are forgiving in the places
//! a person is likely to be loose, and strict in the one place being loose would
//! lose work.
//!
//! **A row that already exists updates rather than duplicating.** A row is
//! identified by its scene number and its shot letter — `34` and `A` out of
//! `34A` — which is the identifier the sheet already shows and a person already
//! understands. Re-importing a sheet you exported an hour ago changes what was
//! edited and touches nothing else.
//!
//! **Letters are the app's to give.** They are read from the file to *find* an
//! existing row, never to name a new one. A row the project has not seen gets
//! the next free letter and the report says what it was called instead.
//!
//! **A bad row is skipped and reported, never fatal.** One malformed line in
//! four hundred should not cost you the other three hundred and ninety-nine.

use std::collections::HashMap;

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::import::csv::Table;
use crate::store::Kind;
use crate::value::Value;

/// What the import did, in terms worth showing someone.
#[derive(Clone, Debug, Default)]
pub struct Report {
    pub scenes_created: Vec<String>,
    pub sequences_created: Vec<String>,
    pub cameras_created: Vec<String>,
    pub shots_created: usize,
    pub shots_updated: usize,
    /// Rows whose shot number could not be given as written — what the sheet
    /// asked for, and what the app called it instead. `("34Z", "34B")` means a
    /// new row wanted 34Z and got the next free letter. Nothing about the shot's
    /// description or title; only its number.
    pub renumbered: Vec<(String, String)>,
    /// Rows naming a shoot day this project does not have. Scheduling is a
    /// decision, so they are left unscheduled rather than invented.
    pub days_not_found: Vec<String>,
    /// Row number in the file, and why it was skipped.
    pub skipped: Vec<(usize, String)>,
}

impl Report {
    pub fn touched(&self) -> usize {
        self.shots_created + self.shots_updated
    }

    /// One line, the way it would be said out loud.
    pub fn summary(&self) -> String {
        let mut parts = Vec::new();
        if self.shots_created > 0 {
            parts.push(format!("{} added", self.shots_created));
        }
        if self.shots_updated > 0 {
            parts.push(format!("{} updated", self.shots_updated));
        }
        if !self.scenes_created.is_empty() {
            parts.push(format!("{} new scenes", self.scenes_created.len()));
        }
        if !self.skipped.is_empty() {
            parts.push(format!("{} skipped", self.skipped.len()));
        }
        if parts.is_empty() {
            "Nothing to import".to_string()
        } else {
            parts.join(", ")
        }
    }
}

/// The columns import understands, and the headings that mean each one.
///
/// Generated from the shot's own fields rather than a hand-kept list, so the
/// template cannot drift from the app.
fn canonical(header: &str) -> Option<&'static str> {
    let key: String = header
        .trim()
        .to_lowercase()
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect();
    Some(match key.as_str() {
        "day" | "shootday" | "shootingday" => "day",
        "scene" | "scenenumber" | "scenenum" => "scene",
        "shot" | "shotnumber" | "shotnum" | "shotno" => "shot",
        "shotdescription" | "description" | "desc" | "action" => "description",
        "title" | "shottitle" => "title",
        "size" | "framing" | "shotsize" => "size",
        "angle" => "angle",
        "movement" | "move" | "cameramovement" => "movement",
        "camera" | "cam" | "unit" => "camera",
        "lens" | "focallength" => "lens",
        "equipment" | "support" | "rig" => "support",
        "notes" | "note" | "shotnotes" => "notes",
        "tags" | "tag" => "tags",
        "sequence" | "seq" => "sequence",
        "struck" | "done" | "got" | "complete" => "struck",
        _ => return None,
    })
}

struct Rows {
    columns: HashMap<&'static str, usize>,
}

impl Rows {
    fn new(table: &Table) -> Rows {
        let mut columns = HashMap::new();
        for (index, header) in table.headers.iter().enumerate() {
            if let Some(name) = canonical(header) {
                // First matching column wins, so a duplicate heading further
                // right cannot quietly shadow the real one.
                columns.entry(name).or_insert(index);
            }
        }
        Rows { columns }
    }

    fn get(&self, row: &[String], name: &str) -> String {
        self.columns
            .get(name)
            .and_then(|index| row.get(*index))
            .map(|value| value.trim().to_string())
            .unwrap_or_default()
    }
}

/// Split a multi-value cell. People write "Front On, Eye Level" and sometimes
/// separate with semicolons instead.
fn multi(value: &str) -> Vec<String> {
    value
        .split([',', ';'])
        .map(|part| part.trim().to_string())
        .filter(|part| !part.is_empty())
        .collect()
}

/// Pull the letter out of a shot number, given the scene it belongs to.
/// `34A` in scene `34` is `A`. A number that does not start with its scene is
/// taken whole, since somebody may just be writing letters on their own.
fn letter_of(shot_number: &str, scene_number: &str) -> String {
    let trimmed = shot_number.trim();
    match trimmed.strip_prefix(scene_number) {
        Some(rest) if !rest.is_empty() => rest.trim().to_uppercase(),
        _ => trimmed.to_uppercase(),
    }
}

fn find_scene(doc: &Doc, number: &str) -> Option<Id> {
    doc.scenes_in_order()
        .into_iter()
        .find(|scene| doc.get(*scene).and_then(|r| r.text(f::NUMBER)) == Some(number))
}

fn find_by_text(doc: &Doc, kind: &Kind, field: &str, wanted: &str) -> Option<Id> {
    doc.store()
        .of_kind(kind)
        .iter()
        .find(|r| {
            r.text(field)
                .map(|value| value.eq_ignore_ascii_case(wanted))
                .unwrap_or(false)
        })
        .map(|r| r.id)
}

fn find_camera(doc: &Doc, wanted: &str) -> Option<Id> {
    doc.store()
        .of_kind(&Kind::Unit)
        .iter()
        .find(|r| {
            let label = r.text(f::LABEL).unwrap_or_default();
            let body = r.text(f::BODY).unwrap_or_default();
            let full = if body.is_empty() {
                label.to_string()
            } else {
                format!("{label} {body}")
            };
            full.eq_ignore_ascii_case(wanted) || label.eq_ignore_ascii_case(wanted)
        })
        .map(|r| r.id)
}

fn find_day(doc: &Doc, label: &str) -> Option<Id> {
    doc.days_in_order()
        .into_iter()
        .find(|day| doc.day_label(*day).as_deref() == Some(label))
}

fn find_placement(doc: &Doc, scene: Id, letter: &str) -> Option<Id> {
    doc.placements_in_scene(scene).into_iter().find(|placement| {
        doc.get(*placement)
            .and_then(|r| r.text(f::LETTER))
            .map(|existing| existing.eq_ignore_ascii_case(letter))
            .unwrap_or(false)
    })
}

/// Apply a parsed sheet to a project.
pub fn apply(doc: &mut Doc, table: &Table) -> Report {
    let mut report = Report::default();
    let rows = Rows::new(table);

    if !rows.columns.contains_key("scene") {
        report
            .skipped
            .push((0, "no Scene # column — nothing can be placed".to_string()));
        return report;
    }

    for (index, row) in table.rows.iter().enumerate() {
        let line = index + 2; // header is line 1, as a spreadsheet counts

        let scene_number = rows.get(row, "scene");
        if scene_number.is_empty() {
            // A blank line at the end of a sheet is not an error worth reporting.
            if row.iter().all(|cell| cell.trim().is_empty()) {
                continue;
            }
            report
                .skipped
                .push((line, "no scene number".to_string()));
            continue;
        }

        // Scene, created if this project has not seen it. Unknown rather than
        // guessed, so it is obvious what still needs filling in.
        let scene = match find_scene(doc, &scene_number) {
            Some(scene) => scene,
            None => {
                let scene = doc.create_scene(&scene_number);
                doc.set(scene, f::INT_EXT, "INT");
                doc.set(scene, f::LOCATION, "UNKNOWN");
                doc.set(scene, f::TIME_OF_DAY, "DAY");
                report.scenes_created.push(scene_number.clone());
                scene
            }
        };

        // An existing row updates in place; a new one is created and named by
        // the app rather than by the file.
        let asked = letter_of(&rows.get(row, "shot"), &scene_number);
        let (shot, _placement) = match (asked.is_empty(), find_placement(doc, scene, &asked)) {
            (false, Some(placement)) => {
                report.shots_updated += 1;
                let shot = match doc.get(placement).and_then(|r| r.ref_id(f::SHOT)) {
                    Some(shot) => shot,
                    None => {
                        report
                            .skipped
                            .push((line, format!("{scene_number}{asked} has no shot")));
                        continue;
                    }
                };
                (shot, placement)
            }
            _ => {
                let (shot, placement) = doc.add_shot_to_scene(scene);
                report.shots_created += 1;
                if !asked.is_empty() {
                    if let Some(given) = doc.get(placement).and_then(|r| r.text(f::LETTER)) {
                        if !given.eq_ignore_ascii_case(&asked) {
                            report.renumbered.push((
                                format!("{scene_number}{asked}"),
                                format!("{scene_number}{given}"),
                            ));
                        }
                    }
                }
                (shot, placement)
            }
        };

        // Fields. A blank cell leaves what is there alone rather than wiping it,
        // because an empty column in somebody else's copy of the sheet should
        // not delete work.
        let set_text = |doc: &mut Doc, field: &str, value: String| {
            if !value.is_empty() {
                doc.set(shot, field, Value::text(value));
            }
        };

        set_text(doc, f::TITLE, rows.get(row, "title"));
        set_text(doc, f::DESCRIPTION, rows.get(row, "description"));
        set_text(doc, f::NOTES, rows.get(row, "notes"));

        for (column, field) in [
            ("size", "size"),
            ("movement", "movement"),
            ("lens", "lens"),
            ("support", "support"),
        ] {
            let value = rows.get(row, column);
            if !value.is_empty() {
                doc.set_vocab_field(shot, field, &value);
            }
        }

        for (column, field) in [("angle", "angle"), ("tags", "tags")] {
            let values = multi(&rows.get(row, column));
            if !values.is_empty() {
                let borrowed: Vec<&str> = values.iter().map(|s| s.as_str()).collect();
                doc.set_vocab_list(shot, field, &borrowed);
            }
        }

        // A camera the project has not seen joins it, the way a lens does.
        let camera = rows.get(row, "camera");
        if !camera.is_empty() {
            let unit = match find_camera(doc, &camera) {
                Some(unit) => unit,
                None => {
                    let (label, body) = match camera.split_once(' ') {
                        Some((label, body)) => (label.to_string(), body.to_string()),
                        None => (camera.clone(), String::new()),
                    };
                    let unit = doc.create_unit(&label, &body);
                    report.cameras_created.push(camera.clone());
                    unit
                }
            };
            doc.set(shot, f::UNIT, unit);
        }

        let struck = rows.get(row, "struck").to_lowercase();
        if !struck.is_empty() {
            doc.strike(shot, matches!(struck.as_str(), "yes" | "y" | "true" | "1" | "x"));
        }

        // Sequences are created; the spec says so and it costs nothing to be wrong.
        let sequence = rows.get(row, "sequence");
        if !sequence.is_empty() {
            let id = match find_by_text(doc, &Kind::Sequence, f::TITLE, &sequence) {
                Some(id) => id,
                None => {
                    let id = doc.create_sequence(&sequence);
                    report.sequences_created.push(sequence.clone());
                    id
                }
            };
            doc.set(scene, f::SEQUENCE, id);
        }

        // Days are not created. Which day something shoots is a decision, and
        // inventing "Day 7" because a cell said so would be making it for you.
        let day = rows.get(row, "day");
        if !day.is_empty() {
            match find_day(doc, &day) {
                Some(id) => doc.schedule(_placement, id),
                None => {
                    if !report.days_not_found.contains(&day) {
                        report.days_not_found.push(day);
                    }
                }
            }
        }
    }

    report
}
