//! What a film looks like, said once.
//!
//! Every screen the Mac app draws — the table, the scene sidebar, the schedule,
//! the locations, the boards — is drawn from the one payload this builds. It
//! lived inside the C boundary in `ffi/` until 2026-09-01, which was fine while
//! the Mac was the only thing drawing, and stopped being fine the moment a
//! browser had to draw the same screens (SL-403).
//!
//! **Moving it rather than writing a second one is the whole point.** Two
//! descriptions of a film drift, and the day they disagree the browser quietly
//! shows something the Mac does not. There is one, and both read it.
//!
//! It touches no files and asks for no shell. What it cannot work out for
//! itself — what is being looked at, and the handful of facts that belong to an
//! *open* project rather than to the film — is handed in.

use crate::doc::f;
use crate::jsonw::Json;
use crate::media::{Arrow, MediaKind};
use crate::query::GroupBy;
use crate::store::Kind;
use crate::value::Value;
use crate::{Doc, Id, Query};


/// **The fields that belong to a *scene* rather than to a shot.**
///
/// Which record a field belongs to decides which narrowing it is. Every facet
/// used to be read as a fact about the scene, so asking for "every M/OTS in the
/// film" asked for *scenes* whose shot size was M/OTS — of which there are none,
/// and the list came back empty with nothing to say why. A scene's own facts are
/// few and named; everything else is a shot's.
pub const SCENE_FACETS: [&str; 7] = [
    "location",
    // Which location *record* the scene is shot at, by id — the fact the
    // Locations screen owns, as against `location`, which is the word the
    // slugline printed.
    "location_id",
    "shooting_location",
    "time_of_day",
    "int_ext",
    "priority",
    "pov",
];

/// What a person has asked to see.
///
/// The shells collect this — a search box, a filter menu, a column header
/// clicked — and this turns it into the `Query` the engine narrows by. **It
/// lives here so the Mac and a browser cannot come to disagree about what a
/// search means**; it was inside the Mac's boundary layer until the hub needed
/// to search too, and a second copy would have drifted inside a week.
#[derive(Clone, Debug)]
pub struct Asked {
    pub group_by: GroupBy,
    pub search: String,
    pub hide_struck: bool,
    pub facets: Vec<(String, String)>,
    pub day: Option<Id>,
    pub unscheduled_only: bool,
    pub sequence: Option<Id>,
    /// The shoot the picker is on (piece D); `None` is All Shoots.
    pub shoot: Option<String>,
    /// Which column the list is read in, and whether backwards. `None` is the
    /// list's own order, which is what the numbering means.
    pub sort: Option<(String, bool)>,
}

impl Default for Asked {
    fn default() -> Asked {
        Asked {
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
        }
    }
}

impl Asked {
    pub fn query(&self) -> Query {
        let mut q = Query::grouped_by(self.group_by);
        if !self.search.trim().is_empty() {
            q = q.matching(self.search.trim());
        }
        if self.hide_struck {
            q = q.hiding_struck();
        }
        for (field, value) in &self.facets {
            if SCENE_FACETS.contains(&field.as_str()) {
                q = q.scene_is(field, value);
            } else {
                q = q.shot_is(field, value);
            }
        }
        if let Some(day) = self.day {
            q = q.on_day(day);
        } else if self.unscheduled_only {
            q = q.unscheduled();
        }
        if let Some(sequence) = self.sequence {
            q.sequence = Some(sequence);
        }
        q.shoot = self.shoot.clone();
        if let Some((column, descending)) = &self.sort {
            q = q.sorted_by(column, *descending);
        }
        q
    }

    /// Whether anything is narrowing the list at all.
    ///
    /// **What the person did, not what the query contains** — grouping and
    /// sorting change how the list reads without hiding anything, so neither
    /// counts.
    pub fn narrowed(&self) -> bool {
        !self.search.trim().is_empty()
            || self.hide_struck
            || !self.facets.is_empty()
            || self.day.is_some()
            || self.unscheduled_only
            || self.sequence.is_some()
    }

    /// What `describe` wants, built from the same asking.
    pub fn looking(&self) -> Looking<'_> {
        Looking {
            query: self.query(),
            group_by: self.group_by,
            search: &self.search,
            hide_struck: self.hide_struck,
            narrowed: self.narrowed(),
            sort: self.sort.clone(),
        }
    }
}

/// What is being looked at: the narrowing on screen, and how the list is read.
pub struct Looking<'a> {
    pub query: Query,
    pub group_by: GroupBy,
    pub search: &'a str,
    pub hide_struck: bool,
    /// Whether anything is narrowing the list at all — the shell says so
    /// rather than this working it out, because "narrowed" means what the
    /// person did, not what the query happens to contain.
    pub narrowed: bool,
    pub sort: Option<(String, bool)>,
}

/// The few facts that belong to an *open* project rather than to the film: not
/// in the change log, not the same on two machines, and not something a
/// document can know about itself.
pub struct Standing {
    pub read_only: bool,
    pub unsaved: usize,
    /// Set when two machines are writing under one device name. A sentence
    /// rather than the clash itself, because that type lives on disk with the
    /// shell that found it.
    pub device_clash: Option<String>,
}

pub fn text(d: &Doc, id: Id, field: &str) -> String {
    match d.get(id).and_then(|r| r.get(field)) {
        Some(Value::Text(s)) => s.clone(),
        Some(Value::Int(n)) => n.to_string(),
        Some(Value::Float(n)) => format!("{}", n),
        Some(Value::Bool(b)) => b.to_string(),
        _ => String::new(),
    }
}

/// A whole number off a record, or nought. Text that happens to hold digits
/// counts — a field written by an older Shotlister as text should not read as
/// nothing just because of how it was stored.
fn int(d: &Doc, id: Id, field: &str) -> i64 {
    match d.get(id).and_then(|r| r.get(field)) {
        Some(Value::Int(n)) => *n,
        Some(Value::Float(n)) => *n as i64,
        Some(Value::Text(s)) => s.parse().unwrap_or(0),
        _ => 0,
    }
}

pub fn list(d: &Doc, id: Id, field: &str) -> Vec<String> {
    match d.get(id).and_then(|r| r.get(field)) {
        Some(Value::List(items)) => items
            .iter()
            .filter_map(|v| match v {
                Value::Text(s) => Some(s.clone()),
                _ => None,
            })
            .collect(),
        Some(Value::Text(s)) => vec![s.clone()],
        _ => Vec::new(),
    }
}

/// A real number off a record, when it holds one. Unlike `int`, absence stays
/// absence rather than folding to nought — a trim range with no in point is a
/// different fact from one trimmed to start at zero.
pub fn float(d: &Doc, id: Id, field: &str) -> Option<f64> {
    match d.get(id).and_then(|r| r.get(field)) {
        Some(Value::Float(n)) => Some(*n),
        Some(Value::Int(n)) => Some(*n as f64),
        Some(Value::Text(s)) => s.parse().ok(),
        _ => None,
    }
}

pub fn reference(d: &Doc, id: Id, field: &str) -> Option<Id> {
    match d.get(id).and_then(|r| r.get(field)) {
        Some(Value::Ref(r)) => Some(*r),
        _ => None,
    }
}

fn flag(d: &Doc, id: Id, field: &str) -> bool {
    matches!(
        d.get(id).and_then(|r| r.get(field)),
        Some(Value::Bool(true))
    )
}

fn ids_of(d: &Doc, kind: Kind) -> Vec<Id> {
    d.store().of_kind(&kind).iter().map(|r| r.id).collect()
}

/// `W/OTS - Short-Sided - Static - 37mm - Handheld`, in the order the table's
/// columns are in. The engine decides that order; this only asks for it, so the
/// document page and the table cannot disagree about where lens sits.
fn technical_line(d: &crate::Doc, placement: Id) -> String {
    let row = match d.row(placement) {
        Some(row) => row,
        None => return String::new(),
    };
    // The camera is drawn on its own, in its own colour — colour is how a unit
    // is read at a glance — so it is not repeated in the line beside it.
    let columns: Vec<String> = d
        .technical_columns()
        .into_iter()
        .filter(|name| name != "camera")
        .collect();
    row.technical_line_for(&columns)
}

/// A built-in field's label, as this film calls it. One word differs by
/// Kind: a commercial's sequences are **Sections** — his call in
/// `design/22-commercial.html` — and every column head, filter and picker
/// reads the name from here, so there is one place the word lives.
fn label_for_kind(d: &Doc, field: &str) -> String {
    if let Some(own) = d.column_label_override(field) {
        return own;
    }
    label_for_kind_default(d, field).to_string()
}

fn label_for_kind_default<'a>(d: &Doc, field: &'a str) -> &'a str {
    if field == "sequence" && d.kind() == crate::kind::Kind::Commercial {
        return "Section";
    }
    crate::columns::label_for(field)
}

/// Everything the table draws, in one payload.
///
/// Sending the whole view rather than a row at a time keeps the boundary
/// crossings to one per change, which matters more than the bytes do.
pub fn describe(d: &Doc, looking: &Looking, standing: &Standing) -> String {
    let mut j = Json::new();
    j.obj();
    let kit = d.kit();
    // Off, the film offers nothing for the sheet (no Add to Spec Sheet)
    let kit_on = d.kit_mode() != crate::kit::KitMode::Off;

    // --- project ---
    j.key("project").obj();
    if let Some(project) = d.project_id() {
        j.kv("id", &project.0.to_string());
        j.kv("title", &text(d, project, f::TITLE));
        j.kv("director", &d.fact(f::DIRECTOR));
        j.kv("producer", &d.fact(f::PRODUCER));
        // **What sort of film this is.** `film` or `commercial` — the shells
        // draw a scene off this: what Add Scene asks for first, whether the
        // slugline leads or folds away, whether a sequence is called a
        // Section. See `crate::kind`.
        j.kv("kind", d.kind().as_str());
        j.kv("client", &d.fact(f::CLIENT));
        j.kv("agency", &d.fact(f::AGENCY));
        // **Where those facts come from** (one-record plan, 2026-10-05).
        // `console`: the project record owns the shown name, director,
        // producer, client and agency, and the shells show them without
        // letting anyone type over them. Empty: the film keeps its own.
        // `displayTitle` is the name to draw — the record's when it has
        // said one, the film's own `title` otherwise. See `crate::recordfacts`.
        // A card laid over the film (`crate::card`) speaks for the record
        // too, so the shells hold its words the same way: not typed over.
        let source = if d.card().is_some() { crate::recordfacts::FROM_CONSOLE.to_string() } else { text(d, project, f::FACTS_SOURCE) };
        j.kv("factsSource", &source);
        j.key("card").bool(d.card().is_some());
        j.kv("displayTitle", &d.shown_title());
        // **The kit** (Ref 1627): each shoot's spec sheet as the picks it
        // gives — lenses, and cameras by name and body — mirrored off the
        // portal (`crate::kit`). Empty: the film has no spec sheet yet.
        j.key("kit").raw(&crate::kit::encode(&kit));
        // **The Spec Sheet switch** (2026-10-13): `off`, `ask` or `follow`.
        // Off, nothing flows and no shot offers Add to Spec Sheet.
        j.kv("kitMode", d.kit_mode().as_str());
        j.kv("defaultPriority", &text(d, project, f::DEFAULT_PRIORITY));
        // **The ratio Studio draws at** (piece E): the picked frame's when
        // the card brings the spec sheet's frames, the film's own otherwise.
        j.kn("ratio", d.film_ratio());
        if let Some(own) = d.own_ratio() {
            j.kn("ownRatio", own);
        }
        // **The project's frames** (piece E), only while the card brings the
        // sheet: name, ratio as written and as a number, Main, and which
        // one Studio draws at (no resolution, 2026-10-15).
        if let Some(frames) = d.frames() {
            let picked = d.picked_frame().map(|f| f.name).unwrap_or_default();
            j.key("frames").arr();
            for one in &frames {
                j.obj()
                    .kv("name", &one.name)
                    .kv("said", &one.said)
                    .kn("ratio", one.ratio)
                    .kb("main", one.main)
                    .kb("picked", one.name == picked)
                    .end_obj();
            }
            j.end_arr();
            j.kv("frame", &picked);
            j.kb("sensorsFromSheet", d.sensors_from_sheet());
        } else {
            // **Said with no sheet too.** Studio and the phone read these
            // two as plain fields, and a reply without them decodes to
            // nothing — every film with no spec sheet opened with no scenes
            // (builds 1966-1991, found 2026-10-15). `frames` stays absent:
            // it is the one that is allowed to be.
            j.kv("frame", "");
            j.kb("sensorsFromSheet", false);
        }
        j.kb("frameGuides", d.frame_guides());
        // **The film's own icon and colour**, which every device wearing this
        // film wears with it — see `crate::mark`. Three plain strings: the
        // outline, the colour, and who is allowed to write them. The engine
        // draws none of it.
        // The card's, when one is laid over the film (`crate::card`).
        let mark = d.mark().unwrap_or_default();
        j.kv("markPath", &mark.path);
        j.kv("markColour", &mark.colour);
        j.kv("markSource", &text(d, project, f::MARK_SOURCE));
        // **Where this film sits in the rest of his systems.** The Projects
        // Console is the window over every project he has; a Shotlister project
        // that knows which one it is can hand a mood board, a location's
        // photographs or a wrap ritual the right Google Drive folder instead of
        // asking again. Four plain strings on the project record — the engine
        // has no opinion about any of them, and never goes and looks.
        // **How the page is set, already resolved.** The defaults live in
        // `docstyle` and nowhere else, so the app reads a finished answer
        // rather than keeping a second copy of what "standard" means — which
        // is the whole reason this moved into the engine.
        // **The same page, in the engine's own shorthand.** The app keeps
        // this to hand round as a default for other films and never reads a
        // character of it — the format stays a private matter between
        // `docstyle.rs` and itself, which is the whole reason it is one field
        // and not nine.
        let set = crate::docstyle::of(d, project);
        j.kv("docStyleSaid", &set.encode());
        j.key("docStyle").arr();
        for (class, one) in set.all() {
            j.obj()
                .kv("class", class.key())
                .kv("label", class.label())
                .kn("size", one.size)
                .kv("face", one.face.key())
                .kv("case", one.case.key())
                .kv("colour", &one.colour.hex())
                .end_obj();
        }
        j.end_arr();
        j.kv("consolePage", &text(d, project, "console_page"));
        j.kv("consoleName", &text(d, project, "console_name"));
        j.kv("driveUrl", &text(d, project, "drive_url"));
        // The **local** folder the Drive sync watches, which is a different
        // fact from the Drive link: one is a web address, the other is a path
        // on this Mac, and only a person can say the second is the first.
        j.kv("driveFolder", &text(d, project, f::DRIVE_FOLDER));
        // **The workbook this film keeps up to date**, if he has asked for
        // one — an absolute path, empty when nothing is linked. Same shape as
        // the four above: a plain string the engine stores and never acts on.
        // The Mac rewrites the file after a change settles; the engine's only
        // part is remembering where it goes.
        j.kv("excelPath", &text(d, project, "excel_path"));
        // **Whether that workbook keeps itself current, apart from whether
        // one is linked at all** — his ask, 2026-08-27: a location and an
        // on/off switch are two different questions. Empty reads as "not
        // decided yet"; the Mac side treats that as "on" when a path is
        // already set, since that was the only behaviour before this field
        // existed and a project linked under the old rule should not go
        // quiet the first time this build opens it.
        j.kv("excelAuto", &text(d, project, "excel_auto"));
        // **Whether a frame goes into the cell or into the file** — two
        // different products, and his ask, 2026-09-04: *"we should still have
        // the XLS as an option for different production needs… as universal as
        // possible."*
        //
        // `cells` writes an `IMAGE()` formula the sheet fetches, which is the
        // only way a frame survives his sorting — and which only Google Sheets
        // resolves. `file` carries the picture inside the workbook, pasted over
        // the grid, which opens anywhere and is what he sends to somebody
        // else. Empty means `cells`, the behaviour this build shipped with.
        j.kv("excelFrames", &text(d, project, "excel_frames"));
    } else {
        j.kv("id", "")
            .kv("title", "Untitled")
            .kv("director", "")
            .kv("producer", "")
            .kv("kind", "film")
            .kv("client", "")
            .kv("agency", "")
            .kv("factsSource", "")
            .kv("displayTitle", "Untitled")
            .kv("defaultPriority", "")
            .kn("ratio", 2.39)
            .kv("markPath", "")
            .kv("markColour", "")
            .kv("markSource", "")
            .kv("consolePage", "")
            .kv("consoleName", "")
            .kv("driveUrl", "")
            .kv("driveFolder", "")
            .kv("excelPath", "")
            .kv("excelAuto", "")
            .kv("excelFrames", "");
    }
    j.kb("readOnly", standing.read_only);
    j.ki("unsaved", standing.unsaved as i64);
    // **Two machines writing under one name** — Ref 186. Absent is the ordinary
    // answer and deserves no words at all; present, it is a sentence rather
    // than a label, because there is nothing a label could say that would tell
    // him what to do about it.
    if let Some(message) = &standing.device_clash {
        j.kv("deviceClash", message);
    }
    j.end_obj();

    // which columns are on screen, in order — the same list the technical line
    // is built from, so hiding a column in the table shortens the line too.
    // A custom column carries its label and kind beside its slug, so the
    // shell never hardcodes what a column is called or how its cells behave.
    let customs = d.custom_columns();
    // Lens Stack: filters and modifiers always sit inside the Lens column; the
    // two columns report themselves not visible.
    j.key("columns").arr();
    for name in d.column_order() {
        j.obj()
            .kv("name", &name)
            .kb("visible", d.is_column_visible(&name))
            // Whether the project's own list shows it, apart from the Lens
            // Stack: the stack takes Modifiers and Filters out of the table,
            // and the Document page still wants to know if they were in.
            .kb("own", !d.hidden_columns().iter().any(|h| *h == name))
            // Whether this column's list has been closed — the pickers read it
            // so a locked list stops offering to create a term, rather than
            // offering one and then quietly refusing it.
            .kb("locked", d.vocabulary_locked(&name));
        // **Every column carries a label**, not only a project's own — Ref
        // 249. The Mac and the phone each held their own copy of "Shot Angle"
        // and "Camera Gear", which is two lists that can disagree.
        match customs.iter().find(|c| c.field == name) {
            Some(c) => {
                j.kv("label", &c.label).kv("kind", &c.kind);
            }
            None => {
                j.kv("label", &label_for_kind(d, &name));
            }
        }
        j.end_obj();
    }
    j.end_arr();

    // **What every field is called, in one place** — Ref 249.
    //
    // The columns array above only carries the ones this project *has*. Some
    // fields are named on screen without being columns at all — a scene's POV
    // and priority keep lists, and the settings screen names them — so the
    // whole table is sent rather than only the part that happens to be
    // showing. That is the same trap the columns report fell into: reporting
    // the narrower of two truths, and reading as a bug when a name went
    // missing.
    j.key("fieldLabels").obj();
    for (field, _) in crate::columns::BUILT_IN_LABELS {
        j.kv(field, &label_for_kind(d, field));
    }
    for c in &customs {
        j.kv(&c.field, &c.label);
    }
    j.end_obj();

    // --- units, sequences, days ---
    j.key("units").arr();
    for id in ids_of(d, Kind::Unit) {
        // An undone creation survives as an empty husk — undo is field-level
        // and strips what was written without removing the record. A camera
        // with no name is nothing to offer, so husks stay out of the view.
        if text(d, id, f::LABEL).is_empty() {
            continue;
        }
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("label", &text(d, id, f::LABEL))
            .kv("body", &text(d, id, f::BODY))
            .kv("colour", &text(d, id, f::COLOUR));
        // The sensor he typed for it, when there is one (`set_unit_sensor`).
        if let Some((name, w, h)) = d.unit_sensor(id) {
            j.kv("sensor_name", &name).kn("sensor_w", w).kn("sensor_h", h);
        }
        // Off the spec sheet's sensor mode (piece E): shown, never typed.
        if d.sensor_from_sheet(id) {
            j.kb("sensor_sheet", true);
        }
        j.end_obj();
    }
    j.end_arr();

    // **The scripts**, as text — the film's own (empty section) and one per
    // section that has one (2026-09-19). The panel draws these and the
    // ranges on the rows over them.
    j.key("scripts").arr();
    for (section, text) in d.av_scripts() {
        j.obj()
            .kv("section", &section.map(|s| s.0.to_string()).unwrap_or_default())
            .kv("text", &text)
            .kb("av", crate::quoting::is_av(&text))
            .end_obj();
    }
    j.end_arr();

    j.key("sequences").arr();
    for id in ids_of(d, Kind::Sequence) {
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("title", &text(d, id, f::TITLE))
            .kv("colour", &text(d, id, f::COLOUR))
            .end_obj();
    }
    j.end_arr();

    // **Locations**, with how much of the film hangs on each — a Locations list
    // that cannot say "eleven scenes are here" is a list of addresses, not a
    // tool. The scenes come out as **ids rather than a count**, because the
    // screen that draws them lets you walk from a location to the scenes shot
    // there, and a count cannot be clicked.
    //
    // The photographs are the same objects a scene's `attachments` are, drawn
    // by the same code. A location that invented its own picture would be a
    // second answer to a question already answered.
    // The shoot the picker is on (piece D), when there is one to be on.
    let on = looking.query.shoot.as_deref().filter(|s| d.many_shoots() && d.shoot(s).is_some());
    j.key("locations").arr();
    for id in d.locations_in_order() {
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("name", &text(d, id, f::LABEL))
            .kv("address", &text(d, id, f::ADDRESS))
            .kv("latitude", &text(d, id, f::LATITUDE))
            .kv("longitude", &text(d, id, f::LONGITUDE))
            .kv("notes", &text(d, id, f::NOTES))
            .kv("capturedBy", &text(d, id, f::CAPTURED_BY))
            .kv("createdAt", &text(d, id, f::CREATED_AT))
            .kv("folder", &text(d, id, f::FOLDER))
            .kv("driveFolder", &text(d, id, f::DRIVE_FOLDER))
            // **Whether this place's photographs travel to Drive** — Ref 229.
            // Empty means nobody has been asked yet, which the bridge reads
            // differently from a plain no. See `f::SYNC_WITH_DRIVE`.
            .kv("syncWithDrive", &text(d, id, f::SYNC_WITH_DRIVE))
            // **A room inside a house** — Ref 269. `parent` is the house;
            // `fullName` is what to call this away from its own screen.
            .kv(
                "parent",
                &d.parent_of_location(id)
                    .map(|x| x.0.to_string())
                    .unwrap_or_default(),
            )
            .kv("fullName", &d.location_full_name(id))
            // The address, pin and notes **as they should be shown** — the
            // room's own if it has them, otherwise the house's.
            //
            // These are deliberately separate from `address`/`notes` above,
            // which stay the record's own values. The editor writes those
            // back, and an editor prefilled with the house's address would
            // stamp a borrowed address onto every room the first time anybody
            // clicked in the field.
            // The same one tag list the boards, scenes and shots share — his
            // call, 2026-08-23: one vocabulary for the whole film, not a
            // second one for places.
            .kv("tags", &list(d, id, f::TAGS).join(", "))
            .kv("effectiveAddress", &d.location_address(id))
            .kv(
                "effectiveLatitude",
                &d.location_pin(id).map(|(lat, _)| lat).unwrap_or_default(),
            )
            .kv(
                "effectiveLongitude",
                &d.location_pin(id).map(|(_, lon)| lon).unwrap_or_default(),
            )
            .kv("effectiveNotes", &d.location_notes(id));
        j.key("areas").arr();
        for area in d.areas_of(id) {
            j.str(&area.0.to_string());
        }
        j.end_arr();
        // Narrowed to a shoot, only that shoot's scenes; a place that has
        // scenes but none in this shoot says so (`inShoot`), and the screens
        // leave it off.
        let here = d.scenes_at_location(id);
        let mine: Vec<Id> = here.iter().copied().filter(|s| d.scene_in(*s, on)).collect();
        j.key("scenes").arr();
        for scene in &mine {
            j.str(&scene.0.to_string());
        }
        j.end_arr();
        let inside = d.scenes_at_location_or_inside(id);
        j.kb("inShoot", on.is_none() || inside.is_empty() || inside.iter().any(|s| d.scene_in(*s, on)));
        // How much of the film hangs on this location **including its rooms**
        // — the number a house should show in the list.
        j.ki(
            "scenesInside",
            d.scenes_at_location_or_inside(id).len() as i64,
        );
        // **Photographs only.** A scanned room is attached the same way a
        // picture is, so asking for every file here would hang a broken image
        // on the wall for the room and a second one for its measurements.
        j.key("media").arr();
        for mref in d.picture_refs(id) {
            if let Some(media) = reference(d, mref, f::MEDIA) {
                j.obj()
                    .kv("ref", &mref.0.to_string())
                    .kv("hash", &text(d, media, f::HASH))
                    .kv("filename", &d.media_ref_name(mref))
                    .kv("kind", d.media_kind(media).unwrap_or(MediaKind::Other).as_str())
                    // **How big it is, so nobody has to open it to find out.**
                    // A wall lays each tile out in the picture's own shape, and
                    // the only way it could learn that shape was to decode the
                    // picture — during layout, on the window's thread, before a
                    // single tile was drawn. These two numbers have sat on the
                    // record since the day it was stored (`add_media`); they
                    // were simply never handed over. Nought for a file that has
                    // no dimensions, which a PDF has not.
                    .ki("width", int(d, media, f::WIDTH))
                    .ki("height", int(d, media, f::HEIGHT))
                    // How wide it hangs, in base columns. Nought means it has
                    // never been sized and the wall's own default stands.
                    // What was said about this use of the picture. Stored on
                    // the use since the day media existed and never handed to
                    // a wall until now.
                    .kv("caption", &text(d, mref, f::CAPTION));
                // **The remembered trim, if this clip has ever been cut.**
                // Absent means the whole thing, same as before trim existed —
                // so a still, or a clip nobody has trimmed, sends neither key
                // rather than a pair of noughts that would read as "starts at
                // the very first frame" by mistake.
                if let Some(start) = float(d, mref, f::TRIM_START) {
                    j.kn("trimStart", start);
                }
                if let Some(end) = float(d, mref, f::TRIM_END) {
                    j.kn("trimEnd", end);
                }
                framing(d, &mut j, mref);
                arrows(d, &mut j, mref);
                j.end_obj();
            }
        }
        j.end_arr();
        // **The scanned rooms.** Two files sharing a name — the shape you turn
        // over, and the measurements a floor plan is built from — and either
        // may be absent. A reader that wants a plan asks for `plan`; one that
        // wants something to look at asks for `shape`; and one that finds
        // neither says the room was never measured rather than drawing nothing.
        j.key("scans").arr();
        for scan in d.scans_of(id) {
            // `file`: the name its files were made with, so a device finds
            // them beside it whatever the room is called now; `taken`: the
            // day it was scanned, said as a list says it.
            j.obj()
                .kv("name", &scan.name)
                .kv("file", &scan.file)
                .kv("taken", &crate::media::scan_date_text(&scan.file));
            for (key, media) in [("shape", scan.shape), ("plan", scan.plan)] {
                let Some(media) = media else { continue };
                // **The use, not just the file** — so a reader can take the
                // room off this location with `detach`, the way a photograph
                // comes off. The phone deletes a scan through this.
                let held = d
                    .media_refs(id)
                    .into_iter()
                    .find(|r| d.get(*r).and_then(|x| x.ref_id(f::MEDIA)) == Some(media));
                j.key(key)
                    .obj()
                    .kv("ref", &held.map(|r| r.0.to_string()).unwrap_or_default())
                    .kv("hash", &text(d, media, f::HASH))
                    .kv("filename", &text(d, media, f::FILENAME))
                    .ki("bytes", int(d, media, f::BYTES))
                    .end_obj();
            }
            j.end_obj();
        }
        j.end_arr();
        j.end_obj();
    }
    j.end_arr();

    // **Mood boards** — a name and a wall of pictures. The pictures are the
    // very same objects a location's photographs and a scene's attachments
    // are, emitted by the same shape, because `media_refs` never cared who
    // owned it.
    j.key("boards").arr();
    for id in d.boards_in_order() {
        // How the wall fills each tile — `original`, `square` or `project`.
        // Empty on a board written before this existed, and that reads as
        // `original`, the shape it always drew.
        let ratio_mode = text(d, id, f::BOARD_RATIO);
        let ratio_mode = if ratio_mode.is_empty() { "original" } else { &ratio_mode };
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("name", &d.board_name(id))
            .kv("ratioMode", ratio_mode)
            // **The one tag list the whole film shares** — his call,
            // 2026-08-23. Same field, same vocabulary, same colours the shots
            // and scenes already use, so tagging a board "night exterior"
            // teaches the term once and everything can be narrowed by it.
            .kv("tags", &list(d, id, f::TAGS).join(", "))
            // **Whether this board's pictures travel to Google Drive** — Ref
            // 229, the mood board half, built 2026-08-30 once boards existed.
            //
            // **A board is off until he switches it on**, which is the
            // opposite of a location and deliberately so. A location was
            // already being carried before the switch existed, so reading
            // absent as off would have silently stopped work in progress;
            // no board has ever been carried, so there is nothing to
            // grandfather and the safe reading of absent is *no*. His call,
            // 2026-08-30.
            .kv("syncWithDrive", &text(d, id, f::SYNC_WITH_DRIVE))
            // Which folder under the film's Drive folder holds them, written
            // down rather than guessed from the name — so renaming a board
            // renames its folder instead of orphaning its pictures.
            .kv("driveFolder", &text(d, id, f::DRIVE_FOLDER));
        // Which scenes hang this board — the other half of Ref 348's link,
        // so it can be made and broken from the board as well as the scene.
        j.key("scenes").arr();
        for scene in d.scenes_with_board(id) {
            j.str(&scene.0.to_string());
        }
        j.end_arr();
        j.key("media").arr();
        for mref in d.media_refs(id) {
            if let Some(media) = reference(d, mref, f::MEDIA) {
                j.obj()
                    .kv("ref", &mref.0.to_string())
                    .kv("hash", &text(d, media, f::HASH))
                    .kv("filename", &d.media_ref_name(mref))
                    .kv("kind", d.media_kind(media).unwrap_or(MediaKind::Other).as_str())
                    // **How big it is, so nobody has to open it to find out.**
                    // A wall lays each tile out in the picture's own shape, and
                    // the only way it could learn that shape was to decode the
                    // picture — during layout, on the window's thread, before a
                    // single tile was drawn. These two numbers have sat on the
                    // record since the day it was stored (`add_media`); they
                    // were simply never handed over. Nought for a file that has
                    // no dimensions, which a PDF has not.
                    .ki("width", int(d, media, f::WIDTH))
                    .ki("height", int(d, media, f::HEIGHT))
                    // How wide it hangs, in base columns. Nought means it has
                    // never been sized and the wall's own default stands.
                    // What was said about this use of the picture. Stored on
                    // the use since the day media existed and never handed to
                    // a wall until now.
                    .kv("caption", &text(d, mref, f::CAPTION));
                // **The remembered trim, if this clip has ever been cut.**
                // Absent means the whole thing, same as before trim existed —
                // so a still, or a clip nobody has trimmed, sends neither key
                // rather than a pair of noughts that would read as "starts at
                // the very first frame" by mistake.
                if let Some(start) = float(d, mref, f::TRIM_START) {
                    j.kn("trimStart", start);
                }
                if let Some(end) = float(d, mref, f::TRIM_END) {
                    j.kn("trimEnd", end);
                }
                framing(d, &mut j, mref);
                arrows(d, &mut j, mref);
                j.end_obj();
            }
        }
        j.end_arr();
        j.end_obj();
    }
    j.end_arr();

    // **Edit references** (the Edit Reference mod): each one's shots in cut
    // order with their numbers, where each starts, its link, and its clip or
    // stills as a board's media are drawn. Absent when the film has none.
    let edits = d.edit_refs_in_order();
    if !edits.is_empty() {
        j.key("editRefs").arr();
        for id in edits {
            let Some(e) = d.edit_ref(id) else { continue };
            j.obj()
                .kv("id", &id.0.to_string())
                .kv("name", &e.name)
                .kv("link", &e.link)
                .kn("length", e.length);
            j.key("shots").arr();
            for (at, shot) in e.shots.iter().enumerate() {
                let number = d
                    .placements_of_shot(*shot)
                    .first()
                    .and_then(|p| d.display_number(*p))
                    .unwrap_or_default();
                j.obj()
                    .kv("shot", &shot.0.to_string())
                    .kv("number", &number)
                    .kn("start", e.starts.get(at).copied().unwrap_or(0.0))
                    .end_obj();
            }
            j.end_arr();
            j.key("media").arr();
            for mref in &e.media {
                if let Some(media) = reference(d, *mref, f::MEDIA) {
                    j.obj()
                        .kv("ref", &mref.0.to_string())
                        .kv("hash", &text(d, media, f::HASH))
                        .kv("filename", &d.media_ref_name(*mref))
                        .kv("kind", d.media_kind(media).unwrap_or(MediaKind::Other).as_str())
                        .ki("width", int(d, media, f::WIDTH))
                        .ki("height", int(d, media, f::HEIGHT));
                    if let Some(secs) = float(d, media, f::DURATION) {
                        j.kn("seconds", secs);
                    }
                    j.end_obj();
                }
            }
            j.end_arr();
            j.end_obj();
        }
        j.end_arr();
    }

    // **The project's shoots** (piece D), off the card: the picker's list,
    // and the one it is on. Empty with no card shoots; the picker shows only
    // with two or more.
    j.key("shoots").arr();
    for s in d.shoots() {
        j.obj()
            .kv("id", &s.id)
            .kv("label", &s.label)
            .kv("kind", &s.kind)
            .kv("start", &s.start)
            .kv("end", &s.end)
            .kv("state", &s.state)
            .ki("scenes", d.scenes_of_shoot(&s.id).len() as i64)
            .ki("days", d.days_of_shoot(&s.id).len() as i64)
            .end_obj();
    }
    j.end_arr();
    j.kv("shootOn", &on.map(crate::shoots::bare).unwrap_or_default());

    j.key("days").arr();
    for id in d.days_in_order() {
        if !d.day_in(id, on) {
            continue;
        }
        // **A wrapped day** is one whose every shot is in an archived scene:
        // shot out and put away. The screens leave it out of the lists a day is
        // picked from, so Day 1 stops coming back once its scenes are archived.
        let wrapped = d.day_wrapped(id);
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("label", &d.day_label(id).unwrap_or_default())
            .kv("date", &d.day_date(id))
            .ki("count", d.shot_count_on_day(id) as i64)
            .kb("wrapped", wrapped)
            .kv("shoot", &d.day_shoot(id).unwrap_or_default())
            .kv("shootSaid", &d.said_shoot(id))
            .end_obj();
    }
    j.end_arr();

    // --- the outline: scenes in script order ---
    // How many things are on each scene's diagram, counted once for the lot
    // rather than once a scene — a page that lists the plans wants to know
    // which scenes have one without asking for every plan.
    let drawn = d.diagram_counts();
    // **The loose plans** (`diagram::plans`) — diagrams that belong to no
    // scene, listed above the scenes on the portal's Diagrams page.
    j.key("plans").arr();
    for id in d.plans_in_order() {
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("name", &d.plan_name(id))
            .ki("diagram", drawn.get(&id).copied().unwrap_or(0) as i64)
            .end_obj();
    }
    j.end_arr();
    j.key("scenes").arr();
    for id in d.scenes_in_order() {
        // Another shoot's scene is not on this shoot's list at all.
        if !d.scene_in(id, on) {
            continue;
        }
        j.obj()
            .kv("id", &id.0.to_string())
            .kv("shoot", &d.scene_shoot(id).unwrap_or_default())
            .kb("shootOwn", d.own_shoot(id).is_some())
            // As stored, card or no card: the portal matches it to its tabs.
            .kv("shootSaid", &d.said_shoot(id))
            // Every piece on every one of its diagrams: whether it is started.
            .ki("diagram", d.scene_diagram_ids(id).iter().map(|x| drawn.get(x).copied().unwrap_or(0)).sum::<usize>() as i64)
            .kv("number", &text(d, id, f::NUMBER))
            .kb("archived", d.is_archived(id))
            .kv("heading", &d.scene_heading_shown(id).unwrap_or_default())
            // **A commercial scene's own three facts.** `title` is what it is
            // called; `slug` is the slugline underneath, empty when nobody has
            // given it one (a film's `heading` never is); `audio` is the
            // right-hand column of an AV script, beside `script` as the left.
            .kv("title", &d.scene_title(id))
            .kv("slug", &d.scene_slug(id).unwrap_or_default())
            .kv("audio", &text(d, id, f::AUDIO))
            .kv("intExt", &crate::insideout::canonical(&text(d, id, f::INT_EXT)))
            .kv("location", &text(d, id, f::LOCATION))
            .kv("timeOfDay", &text(d, id, f::TIME_OF_DAY))
            .kv("script", &text(d, id, f::SCRIPT))
            .kv("description", &text(d, id, f::DESCRIPTION))
            .kv("notes", &text(d, id, f::NOTES))
            // The same words with their emphasis, kept beside the plain text
            // rather than inside it — every other surface reads `notes` and is
            // unaware this exists, the same arrangement the document page's
            // `descriptionRich` uses.
            .kv("notesRich", &text(d, id, "notes_rich"))
            .kv("shootingLocation", &text(d, id, f::SHOOTING_LOCATION))
            // The place record it points at, if any — distinct from
            // `location`, which is the slugline's own word.
            .kv("locationId", &d.location_of_scene(id).map(|x| x.0.to_string()).unwrap_or_default())
            // **And all of them**, when a scene moves between places — his ask
            // of 2026-08-22. `locationId` above is the first of these and is
            // never absent, so a shell that has not learned about the list
            // still shows the scene's main location rather than nothing.
            .kv(
                "locationIds",
                &d.scene_locations(id)
                    .iter()
                    .map(|x| x.0.to_string())
                    .collect::<Vec<_>>()
                    .join(","),
            )
            // Every mood board this scene links to — his call, 2026-08-23
            // (Ref SL-348): the chip lives on the scene.
            .kv(
                "boardIds",
                &d.scene_boards(id)
                    .iter()
                    .map(|x| x.0.to_string())
                    .collect::<Vec<_>>()
                    .join(","),
            )
            // A scene's own tags, the same shared list the shots draw from —
            // his ask for the line under the scene heading. Emitted joined,
            // like `pov`, because the shell shows them as pills either way.
            .kv("tags", &list(d, id, f::TAGS).join(", "))
            .kv("priority", &text(d, id, f::PRIORITY))
            .kv("pov", &list(d, id, f::POV).join(", "))
            .kv(
                "day",
                &d.days_of_scene(id)
                    .into_iter()
                    .filter_map(|day| d.day_label(day))
                    .collect::<Vec<_>>()
                    .join(" · "),
            )
            .ki("count", d.shot_count_in_scene(id) as i64)
            .kb("split", d.scene_is_split(id));
        // What is pinned to the scene itself — the Notes tab's attachments.
        // A shot's frames and a scene's attachments are the same machinery
        // (a media ref with an owner); only the owner differs.
        j.key("attachments").arr();
        for mref in d.media_refs(id) {
            if let Some(media) = reference(d, mref, f::MEDIA) {
                j.obj()
                    .kv("ref", &mref.0.to_string())
                    .kv("hash", &text(d, media, f::HASH))
                    .kv("filename", &d.media_ref_name(mref))
                    .kv("kind", d.media_kind(media).unwrap_or(MediaKind::Other).as_str())
                    // **How big it is, so nobody has to open it to find out.**
                    // A wall lays each tile out in the picture's own shape, and
                    // the only way it could learn that shape was to decode the
                    // picture — during layout, on the window's thread, before a
                    // single tile was drawn. These two numbers have sat on the
                    // record since the day it was stored (`add_media`); they
                    // were simply never handed over. Nought for a file that has
                    // no dimensions, which a PDF has not.
                    .ki("width", int(d, media, f::WIDTH))
                    .ki("height", int(d, media, f::HEIGHT))
                    // How wide it hangs, in base columns. Nought means it has
                    // never been sized and the wall's own default stands.
                    // What was said about this use of the picture. Stored on
                    // the use since the day media existed and never handed to
                    // a wall until now.
                    .kv("caption", &text(d, mref, f::CAPTION));
                // **The remembered trim, if this clip has ever been cut.**
                // Absent means the whole thing, same as before trim existed —
                // so a still, or a clip nobody has trimmed, sends neither key
                // rather than a pair of noughts that would read as "starts at
                // the very first frame" by mistake.
                if let Some(start) = float(d, mref, f::TRIM_START) {
                    j.kn("trimStart", start);
                }
                if let Some(end) = float(d, mref, f::TRIM_END) {
                    j.kn("trimEnd", end);
                }
                framing(d, &mut j, mref);
                arrows(d, &mut j, mref);
                j.end_obj();
            }
        }
        j.end_arr();
        // Hidden from the Diagram's list by hand: present only when so.
        if d.scene_diagram_hidden(id) {
            j.kb("diagramHidden", true);
        }
        // **Its diagrams, when it has more than one** (`scenediagrams`): each
        // one's id (the scene's own first in his order wherever he put it),
        // the name he typed (empty when unnamed), what it is called, and how
        // many pieces it holds. Absent for the usual one, so nothing that
        // reads a scene had to learn about this.
        let several = d.scene_diagrams(id);
        if several.len() > 1 {
            j.key("diagrams").arr();
            for x in &several {
                j.obj()
                    .kv("id", &x.id.0.to_string())
                    .kv("name", &x.name)
                    .kv("title", &x.title)
                    .ki("count", drawn.get(&x.id).copied().unwrap_or(0) as i64)
                    .end_obj();
            }
            j.end_arr();
        }
        match reference(d, id, f::SEQUENCE) {
            Some(seq) => {
                j.kv("sequence", &seq.0.to_string());
            }
            None => {
                j.key("sequence").null();
            }
        }
        j.end_obj();
    }
    j.end_arr();

    // --- what is being looked for ---
    // The screen sees archived scenes and sets them aside itself — the
    // Mac greys them behind a chevron, the portal leaves them off its
    // views. Paper never sees them (`Query.include_archived`).
    let query = looking.query.clone().with_archived();
    j.key("filter").obj();
    j.kv("text", looking.search)
        .kb("hideStruck", looking.hide_struck)
        .kb("narrowed", looking.narrowed)
        .kv("sortColumn", looking.sort.as_ref().map(|(c, _)| c.as_str()).unwrap_or(""))
        .kb("sortDescending", looking.sort.as_ref().map(|(_, d)| *d).unwrap_or(false))
        // the outline says how many scenes went out of sight, so a filter never
        // silently shortens the film
        .ki("hiddenScenes", d.hidden_scene_count(&query) as i64)
        .ki("shown", d.count(&query) as i64);
    // **Which** ones went out of sight, not just how many. A filter that
    // empties a scene takes it off the list, and if that is the scene somebody
    // is sitting on the app falls back to the first one in the film — quietly.
    // In front of a person that is reasonable; inside a checking run it means
    // a check can pass or fail for a reason that has nothing to do with what
    // it tests. Naming them lets the app and the harness both notice, instead
    // of finding out by being somewhere else. Ref 101.
    j.key("hiddenSceneIds").arr();
    for scene in d.hidden_scenes(&query) {
        j.str(&scene.0.to_string());
    }
    j.end_arr();
    j.end_obj();

    // --- the rows, grouped the way the toolbar asks ---
    j.kv(
        "groupBy",
        match looking.group_by {
            GroupBy::Scene => "scene",
            GroupBy::Day => "day",
            GroupBy::Sequence => "sequence",
            _ => "none",
        },
    );
    j.key("groups").arr();
    let groups = d.run(&query);
    // **Edit Reference brackets** run across headings, so each group's are
    // worked out knowing its neighbours' rows.
    let drawn_rows: Vec<Vec<Id>> = groups
        .iter()
        .map(|g| g.placements.iter().filter_map(|p| reference(d, *p, f::SHOT)).collect())
        .collect();
    let across = d.edit_spans_across(&drawn_rows);
    for (gi, group) in groups.iter().enumerate() {
        j.obj();
        match group.key {
            Some(k) => {
                j.kv("key", &k.0.to_string());
            }
            None => {
                j.key("key").null();
            }
        }
        j.kv("label", &group.label);
        j.ki("count", group.count() as i64);

        // a scene group carries everything its header shows as a pill: the
        // heading, the sequence it belongs to in that sequence's colour, the day
        // it is scheduled on, its point of view, and its priority when that is
        // not the project's own default. All facts that decide whether you need
        // to open the scene at all.
        if let (GroupBy::Scene, Some(scene)) = (looking.group_by, group.key) {
            j.kv("heading", &d.scene_heading_shown(scene).unwrap_or_default());
            // The band under a commercial's title: the slugline when there is
            // one, and the two AV columns. A film's band draws none of these.
            j.kv("slug", &d.scene_slug(scene).unwrap_or_default());
            j.kv("video", &text(d, scene, f::SCRIPT));
            j.kv("audio", &text(d, scene, f::AUDIO));
            if let Some(seq) = reference(d, scene, f::SEQUENCE) {
                j.kv("colour", &text(d, seq, f::COLOUR));
                j.kv("sequenceTitle", &text(d, seq, f::TITLE));
            }
            // A scene sits on the days its shots do — which is one day usually,
            // and worth saying plainly when it is more.
            let days: Vec<String> = d
                .days_of_scene(scene)
                .into_iter()
                .filter_map(|day| d.day_label(day))
                .collect();
            if !days.is_empty() {
                j.kv("day", &days.join(" · "));
            }
            let pov = list(d, scene, f::POV);
            if !pov.is_empty() {
                j.kv("pov", &pov.join(", "));
            }
            let priority = text(d, scene, f::PRIORITY);
            if !priority.is_empty() {
                j.kv("priority", &priority);
            }
            j.kv("intExt", &crate::insideout::canonical(&text(d, scene, f::INT_EXT)));
            j.kv("location", &text(d, scene, f::LOCATION));
            j.kv("timeOfDay", &text(d, scene, f::TIME_OF_DAY));
        }

        // **Edit Reference brackets** (the mod's socket A): which runs of
        // these rows an edit reference joins, by row index. Absent when there
        // are none, so a project with none answers exactly as before.
        // `before` / `after` only when the run carries across a heading, and
        // `editThrough` only on a group with no rows inside such a run.
        let here = &across[gi];
        if !here.spans.is_empty() {
            j.key("editSpans").arr();
            for span in &here.spans {
                j.obj()
                    .kv("ref", &span.edit.0.to_string())
                    .ki("from", span.from as i64)
                    .ki("to", span.to as i64);
                if span.before {
                    j.kb("before", true);
                }
                if span.after {
                    j.kb("after", true);
                }
                j.end_obj();
            }
            j.end_arr();
        }
        if !here.through.is_empty() {
            j.key("editThrough").arr();
            for e in &here.through {
                j.str(&e.0.to_string());
            }
            j.end_arr();
        }

        j.key("rows").arr();
        for placement in &group.placements {
            let placement = *placement;
            let shot = match reference(d, placement, f::SHOT) {
                Some(s) => s,
                None => continue,
            };
            j.obj();
            j.kv("placement", &placement.0.to_string());
            j.kv("shot", &shot.0.to_string());
            // The shot's colour, when it has one — identity, so it travels
            // with the shot rather than with where the shot happens to sit.
            let colour = text(d, shot, f::COLOUR);
            if !colour.is_empty() {
                j.kv("colour", &colour);
            }
            match reference(d, placement, f::SCENE) {
                Some(scene) => {
                    j.kv("sceneId", &scene.0.to_string());
                }
                None => {
                    j.key("sceneId").null();
                }
            }
            j.kv("number", &d.display_number(placement).unwrap_or_default());
            // **Where the words come from.** A shot standing in for a master
            // shows the master's description and technical fields and keeps its
            // own number, scene, colour and whether it is cut. `described_by`
            // is the engine's answer to "which record says what this shot is",
            // and it is one hop by construction.
            let said = d.described_by(shot);
            j.kb("isMaster", d.is_master(shot));
            match d.master_of(shot) {
                Some(master) => {
                    // The number a person would recognise it by, wherever in
                    // the film it lives.
                    let where_ = d
                        .placements_of_shot(master)
                        .first()
                        .and_then(|at| d.display_number(*at))
                        .unwrap_or_default();
                    j.kv("linkedTo", &where_);
                }
                None => {
                    j.key("linkedTo").null();
                }
            }
            j.kv("title", &text(d, said, f::TITLE));
            j.kv("description", &text(d, said, f::DESCRIPTION));
            // **The stretch of the script this shot quotes** (2026-09-19):
            // which script (a section id, or empty for the film's), the
            // UTF-16 range, and the words — read off the script every time.
            match d.quote_of(said) {
                Some(q) => {
                    j.kv("scriptOf", &q.section.map(|s| s.0.to_string()).unwrap_or_default())
                        .ki("scriptFrom", q.from as i64)
                        .ki("scriptTo", q.to as i64)
                        .kv("script", &d.shot_excerpt(said));
                    // Every stretch, the first one too: `[[from, to], …]`.
                    j.key("scriptSpans").arr();
                    for (from, to) in d.spans_of(said) {
                        j.arr().int(from as i64).int(to as i64).end_arr();
                    }
                    j.end_arr();
                }
                None => {
                    j.key("scriptOf").null().key("scriptFrom").null().key("scriptTo").null().kv("script", "");
                    j.key("scriptSpans").arr().end_arr();
                }
            }
            // **The lines of the screenplay it covers** (Ref 1553): each
            // stretch's words, as kept. Where they sit on a page is
            // `scriptpages`'s answer, draft by draft.
            j.key("playLines").arr();
            for stretch in d.play_stretches(shot) {
                j.str(&stretch.plain());
            }
            j.end_arr();
            // The document page can hold emphasis the table has no use for, so
            // it is kept beside the plain text rather than inside it: every other
            // surface — table, spreadsheet, share page — reads `description` and
            // is unaware this exists.
            j.kv("descriptionRich", &text(d, said, "description_rich"));
            j.kv("size", &text(d, said, f::SIZE));
            j.key("angle").arr();
            for a in list(d, said, f::ANGLE) {
                j.str(&a);
            }
            j.end_arr();
            j.kv("movement", &text(d, said, f::MOVEMENT));
            j.kv("lens", &text(d, said, f::LENS));
            // Where a zoom is set — only while the Lens is a zoom.
            if crate::diagram::lens::zoom_from_text(&text(d, said, f::LENS)).is_some() {
                if let Some(mm) = d.get(said).and_then(|r| r.get(f::FOCAL)).and_then(|v| v.as_float()) {
                    j.kn("focal", mm);
                }
            }
            j.key("modifiers").arr();
            for m in list(d, said, f::MODIFIERS) {
                j.str(&m);
            }
            j.end_arr();
            j.key("lens_filters").arr();
            for m in list(d, said, f::LENS_FILTERS) {
                j.str(&m);
            }
            j.end_arr();
            j.kv("support", &text(d, said, f::SUPPORT));
            j.kv("notes", &text(d, said, f::NOTES));
            j.key("tags").arr();
            for t in list(d, said, f::TAGS) {
                j.str(&t);
            }
            j.end_arr();
            j.kb("struck", flag(d, shot, f::STRUCK));
            // **What it uses that the spec sheet lacks** (Ref 1627): the
            // lens, the camera's body, and which shoot's sheet would take
            // them. The shells offer Add to Spec Sheet; nothing is added here.
            if let Some(off) = kit_on.then(|| d.off_kit(&kit, placement)).flatten() {
                j.key("offKit").obj().ki("shoot", off.shoot as i64);
                if let Some(lens) = &off.lens {
                    j.kv("lens", lens);
                }
                if let Some((label, body)) = &off.camera {
                    j.kv("camera", label).kv("body", body);
                }
                if !off.modifiers.is_empty() {
                    j.key("modifiers").arr();
                    for m in &off.modifiers {
                        j.str(m);
                    }
                    j.end_arr();
                }
                if !off.filters.is_empty() {
                    j.key("filters").arr();
                    for m in &off.filters {
                        j.str(m);
                    }
                    j.end_arr();
                }
                j.end_obj();
            }

            // The project's own columns, uniformly as lists: a text or single
            // value is a list of one, a check is present-or-absent, and multi
            // is itself. One shape, so the shell decodes one shape.
            j.key("custom").obj();
            for c in &customs {
                j.key(&c.field).arr();
                match c.kind.as_str() {
                    "multi" => {
                        for v in list(d, shot, &c.field) {
                            j.str(&v);
                        }
                    }
                    "check" => {
                        if flag(d, shot, &c.field) {
                            j.str("1");
                        }
                    }
                    _ => {
                        let v = text(d, shot, &c.field);
                        if !v.is_empty() {
                            j.str(&v);
                        }
                    }
                }
                j.end_arr();
            }
            j.end_obj();

            match reference(d, shot, f::UNIT) {
                Some(u) => {
                    j.key("unit").obj();
                    j.kv("id", &u.0.to_string())
                        .kv("label", &text(d, u, f::LABEL))
                        .kv("body", &text(d, u, f::BODY))
                        .kv("colour", &text(d, u, f::COLOUR));
                    j.end_obj();
                }
                None => {
                    j.key("unit").null();
                }
            }

            // setup siblings are what the bracket in the gutter is drawn from
            let siblings = d.setup_siblings(shot);
            j.key("setup").arr();
            for s in siblings {
                j.str(&s.0.to_string());
            }
            j.end_arr();
            // and the setup itself, so rows next to each other can tell whether
            // they are the same moment on two cameras
            match reference(d, shot, f::SETUP) {
                Some(setup) => {
                    j.kv("setupId", &setup.0.to_string());
                }
                None => {
                    j.key("setupId").null();
                }
            }

            // priority is only ever drawn when it is not the project's default —
            // marking every shot "normal" says nothing and costs a column
            j.kv("priority", &text(d, shot, f::PRIORITY));

            // **Inside, outside, or both — as the answers it gives a filter.**
            // A scene that is INT/EXT answers to INT, to EXT and to INT/EXT,
            // so the portal's any-of filter needs no rule of its own: the
            // engine said what each scene counts as, once, in
            // `insideout::answers`. Absent when the scene says nothing.
            j.key("int_ext").arr();
            if let Some(scene) = reference(d, placement, f::SCENE) {
                for answer in ["INT", "EXT", "INT/EXT"] {
                    if crate::insideout::answers(&text(d, scene, f::INT_EXT), answer) {
                        j.str(answer);
                    }
                }
            }
            j.end_arr();

            // a shot placed more than once is the ⚭ in the table
            let places = d.placements_of_shot(shot);
            j.key("alsoAt").arr();
            for other in places {
                if other != placement {
                    if let Some(n) = d.display_number(other) {
                        j.str(&n);
                    }
                }
            }
            j.end_arr();

            // **The picture comes from the master too.** A shot standing in for
            // another shows what that one shows, and a frame is the loudest
            // thing on a row — his report, 2026-08-22: the words carried over
            // and the image did not. `said` is the master when there is one.
            let key_ref = reference(d, said, f::KEY_MEDIA)
                .or_else(|| d.media_refs(said).first().copied());
            let key = key_ref.and_then(|mref| reference(d, mref, f::MEDIA));
            match key {
                Some(media) => {
                    j.key("frame").obj();
                    j.kv("hash", &text(d, media, f::HASH))
                        .kv(
                            "filename",
                            &key_ref.map(|r| d.media_ref_name(r)).unwrap_or_default(),
                        )
                        .kv(
                            "kind",
                            d.media_kind(media).unwrap_or(MediaKind::Other).as_str(),
                        );
                    // **The trim rides with the lead frame**, so the thumbnail
                    // in the table plays the same range the viewer does.
                    // Without it a trimmed clip went on playing whole
                    // everywhere it was small (2026-08-28).
                    if let Some(mref) = key_ref {
                        if let Some(start) = float(d, mref, f::TRIM_START) {
                            j.kn("trimStart", start);
                        }
                        if let Some(end) = float(d, mref, f::TRIM_END) {
                            j.kn("trimEnd", end);
                        }
                        framing(d, &mut j, mref);
                        arrows(d, &mut j, mref);
                    }
                    j.end_obj();
                }
                None => {
                    j.key("frame").null();
                }
            }
            j.ki("frames", d.media_refs(said).len() as i64);

            // every frame on the shot, in order — document view draws them all,
            // and the table needs to know which one is standing for the shot
            j.key("stills").arr();
            for mref in d.media_refs(said) {
                if let Some(media) = reference(d, mref, f::MEDIA) {
                    j.obj()
                        .kv("ref", &mref.0.to_string())
                        .kv("hash", &text(d, media, f::HASH))
                        .kv("filename", &d.media_ref_name(mref))
                        // What the file *is*, said rather than guessed. The
                        // phone read the kind off the filename until now, so a
                        // clip named oddly was drawn as a photograph.
                        .kv(
                            "kind",
                            d.media_kind(media).unwrap_or(MediaKind::Other).as_str(),
                        )
                        .kb("key", Some(mref) == key_ref);
                    // The remembered trim, if this clip has ever been cut —
                    // same as a location's or a board's media, so a clip on a
                    // shot's own frame strip can be trimmed too.
                    if let Some(start) = float(d, mref, f::TRIM_START) {
                        j.kn("trimStart", start);
                    }
                    if let Some(end) = float(d, mref, f::TRIM_END) {
                        j.kn("trimEnd", end);
                    }
                    framing(d, &mut j, mref);
                    arrows(d, &mut j, mref);
                    j.end_obj();
                }
            }
            j.end_arr();

            // **The shot's Print Frame**, when it has one — the board that
            // stands for it on paper, read off the shot its pictures come from
            // (`said`). Absent when there is none. `stale` is the Mac's cue to
            // bake it again. (`crate::printframe`, `Doc::print_frame_view`)
            if let Some(pf) = d.print_frame_view(said) {
                j.key("printFrame").raw(&pf);
            }

            // how the page lays this shot out: a fraction of the measure, never
            // a size, and which of the four sides the frame takes
            j.kn("frameWidth", d.frame_width(shot));
            j.kv("framePosition", d.frame_position(shot).as_str());
            j.kv("technical", &technical_line(d, placement));

            match reference(d, placement, f::DAY) {
                Some(day) => {
                    j.kv("day", &d.day_label(day).unwrap_or_default());
                    j.kv("dayId", &day.0.to_string());
                }
                None => {
                    j.key("day").null().key("dayId").null();
                }
            }

            // **The sequence the shot is in** — Ref 250. The day was already
            // here and this was not, so the phone had one of the two and drew
            // neither rather than draw half an answer.
            //
            // It is read off the **scene**, which is where it lives and where
            // the Mac sets it. A shot moved to another scene takes that
            // scene's sequence, which is the whole point of a sequence: it is
            // a run of the film, not a property of one setup.
            match reference(d, placement, f::SCENE).and_then(|scene| reference(d, scene, f::SEQUENCE))
            {
                Some(seq) => {
                    j.kv("sequence", &text(d, seq, f::TITLE));
                    j.kv("sequenceId", &seq.0.to_string());
                    j.kv("sequenceColour", &text(d, seq, f::COLOUR));
                }
                None => {
                    j.key("sequence")
                        .null()
                        .key("sequenceId")
                        .null()
                        .key("sequenceColour")
                        .null();
                }
            }
            j.end_obj();
        }
        j.end_arr();
        j.end_obj();
    }
    j.end_arr();

    j.end_obj();
    j.finish()
}

/// **How a picture is framed when it is drawn cropped**, beside the trim and
/// for the same reason: it belongs to this *use* of the file, and every shape
/// that carries a use is drawn cropped somewhere — a wall of squares, a table
/// cell, a storyboard plate.
///
/// Absent means the middle at full width, which is what every picture in the
/// app did before this existed — so a photograph nobody has framed sends no
/// keys rather than three numbers that only say "unchanged".
pub fn framing(d: &Doc, j: &mut Json, mref: Id) {
    if let Some(x) = float(d, mref, f::CROP_X) {
        j.kn("cropX", x);
    }
    if let Some(y) = float(d, mref, f::CROP_Y) {
        j.kn("cropY", y);
    }
    if let Some(scale) = float(d, mref, f::CROP_SCALE) {
        j.kn("cropScale", scale);
    }
}

/// **The storyboard arrows drawn over this use of a picture**, beside the
/// framing and for the same reason: they belong to the use, not the file.
///
/// Sent as the one line the engine stores rather than as a list of objects.
/// Three shells have to draw the same marks from it, and one string they all
/// parse with the same six-number rule cannot drift the way six named keys
/// can. A picture nobody has marked sends no key at all.
pub fn arrows(d: &Doc, j: &mut Json, mref: Id) {
    let drawn = d.media_arrows(mref);
    if !drawn.is_empty() {
        j.kv("arrows", &Arrow::encode(&drawn));
    }
}
