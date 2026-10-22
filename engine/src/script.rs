//! Reading a screenplay, and saying what a new draft would change.
//!
//! This is the case the automation surface exists for: a new draft arrives on
//! Thursday, and the question is not *what does it say* but **what is different
//! from the list I already have** — which scenes are new, which have moved
//! location or time, and which are gone.
//!
//! Two rules govern the whole module, and both come from elsewhere in this
//! project rather than being invented here:
//!
//! - **Scene numbers are the script's, never ours.** The app has never
//!   renumbered a scene and does not start now. A draft that numbers its scenes
//!   is matched on those numbers; one that does not is read in order and said to
//!   be unmatchable rather than guessed at.
//! - **Report, never invent — and never destroy.** A scene that has left the
//!   draft is *reported*, not deleted. It holds shots, and shots are somebody's
//!   work; a script revision is not authority to throw them away. Deleting is
//!   always a person's decision, taken with the number in front of them.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::natural;
use crate::value::Value;

/// One scene as the screenplay has it.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct ScriptScene {
    /// As printed, when the draft is numbered.
    pub number: Option<String>,
    /// `INT`, `EXT`, or something the draft said that we pass along as written.
    pub int_ext: String,
    pub location: String,
    pub time_of_day: String,
    /// The slug exactly as it appeared, for showing back.
    pub heading: String,
    /// Everything under the slug, up to the next one.
    pub body: String,
}

/// What a new draft would do to the list.
#[derive(Clone, Debug, Default)]
pub struct ScriptDiff {
    pub added: Vec<ScriptScene>,
    pub changed: Vec<SceneChange>,
    /// Scenes the project has that the draft no longer mentions. Reported and
    /// never acted on.
    pub gone: Vec<GoneScene>,
    pub unchanged: usize,
    /// Draft scenes with no number, which cannot be matched to anything.
    pub unnumbered: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SceneChange {
    pub scene: Id,
    pub number: String,
    /// Field, what the project says, what the draft says.
    pub differences: Vec<(String, String, String)>,
    pub draft: ScriptScene,
}

#[derive(Clone, Debug, PartialEq)]
pub struct GoneScene {
    pub scene: Id,
    pub number: String,
    pub heading: String,
    /// How much work would go with it, which is the number somebody needs in
    /// order to decide.
    pub shots: usize,
}

impl ScriptDiff {
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.changed.is_empty() && self.gone.is_empty()
    }

    /// Whether it should stop and ask. A draft that only adds scenes and changes
    /// nothing is the ordinary case; a scene disappearing with shots on it is
    /// not.
    pub fn needs_confirming(&self) -> bool {
        !self.gone.is_empty() || !self.changed.is_empty() || self.unnumbered > 0
    }

    pub fn summary(&self) -> String {
        let mut said = Vec::new();
        if !self.added.is_empty() {
            said.push(format!("{} new", self.added.len()));
        }
        if !self.changed.is_empty() {
            said.push(format!("{} changed", self.changed.len()));
        }
        if !self.gone.is_empty() {
            let shots: usize = self.gone.iter().map(|g| g.shots).sum();
            said.push(format!(
                "{} no longer in the script, holding {shots} shots between them",
                self.gone.len()
            ));
        }
        if self.unnumbered > 0 {
            said.push(format!(
                "{} unnumbered and so not matched to anything",
                self.unnumbered
            ));
        }
        if said.is_empty() {
            return format!("Nothing has changed. All {} scenes match.", self.unchanged);
        }
        format!("{}. {} unchanged.", said.join(", "), self.unchanged)
    }
}

// ---- reading a screenplay -----------------------------------------------

/// Split a draft into scenes on its slug lines.
///
/// Deliberately forgiving about layout and strict about what a slug is: a line
/// that begins `INT`, `EXT` or a combination, optionally with a scene number in
/// front of it and the same number repeated at the end, which is how numbered
/// drafts are printed.
pub fn parse(text: &str) -> Vec<ScriptScene> {
    let mut scenes: Vec<ScriptScene> = Vec::new();
    let mut body = String::new();

    for line in text.lines() {
        match read_slug(line) {
            Some(scene) => {
                if let Some(previous) = scenes.last_mut() {
                    previous.body = body.trim().to_string();
                }
                body.clear();
                scenes.push(scene);
            }
            None => {
                if !scenes.is_empty() {
                    body.push_str(line);
                    body.push('\n');
                }
            }
        }
    }
    if let Some(previous) = scenes.last_mut() {
        previous.body = body.trim().to_string();
    }
    settle_times_of_day(&mut scenes);
    scenes
}

/// A heading the script numbered but did not write `INT` or `EXT` on.
///
/// `5 BATHROOM.` and `1 OVER BLACK - THE SOUND OF A ROTARY PHONE RINGING.` are
/// both scenes in his own draft, both numbered by the script, and neither is a
/// slug by the rule above. A number printed in the margin is the script saying
/// *this is a scene* as plainly as it can, and it is why Cadrage's own import
/// leaves its INT/EXT requirement switched off.
///
/// Kept strict, because the only thing separating this from a line of action
/// that opens with a figure is that a heading is not written in lower case.
pub(crate) fn read_numbered_heading(line: &str) -> Option<ScriptScene> {
    let trimmed = line.trim();
    let (head, rest) = trimmed.split_once(char::is_whitespace)?;
    if !looks_like_a_scene_number(head) {
        return None;
    }
    let rest = rest.trim();
    if rest.is_empty() || rest.chars().any(|c| c.is_lowercase()) {
        return None;
    }
    if !rest.chars().any(|c| c.is_alphabetic()) {
        return None;
    }
    // A transition is in capitals too, and is not a scene.
    if rest.ends_with(':') {
        return None;
    }
    Some(ScriptScene {
        number: Some(head.trim_end_matches('.').to_string()),
        int_ext: String::new(),
        location: rest.trim_end_matches('.').to_uppercase(),
        time_of_day: String::new(),
        heading: rest.to_string(),
        body: String::new(),
    })
}

pub(crate) fn read_slug(line: &str) -> Option<ScriptScene> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }

    // A leading scene number, and the same number often repeated at the end.
    let mut rest = trimmed;
    let mut number = None;
    if let Some((head, tail)) = rest.split_once(char::is_whitespace) {
        if looks_like_a_scene_number(head) {
            number = Some(head.trim_end_matches('.').to_string());
            rest = tail.trim_start();
        }
    }
    if let Some((head, tail)) = rest.rsplit_once(char::is_whitespace) {
        if looks_like_a_scene_number(tail) && number.is_some() {
            rest = head.trim_end();
        }
    }

    let upper = rest.to_uppercase();
    let (int_ext, after) = starts_with_int_ext(&upper, rest)?;

    let (location, time_of_day) = split_place_from_time(&after);

    Some(ScriptScene {
        number,
        int_ext,
        location: location.to_uppercase(),
        time_of_day: time_of_day.to_uppercase(),
        heading: rest.to_string(),
        body: String::new(),
    })
}

/// `LOCATION - TIME`, split on the **last** dash, since a location can
/// perfectly well contain one. An em dash counts, because a Mac turns a typed
/// hyphen into one without asking.
fn split_place_from_time(after: &str) -> (String, String) {
    match after.rsplit_once(" - ") {
        Some((place, time)) => (place.trim().to_string(), time.trim().to_string()),
        None => match after.rsplit_once(" — ") {
            Some((place, time)) => (place.trim().to_string(), time.trim().to_string()),
            None => (after.trim().to_string(), String::new()),
        },
    }
}

/// A heading **typed by hand** rather than read out of a draft.
///
/// `read_slug` is deliberately suspicious: a line in a screenplay is a slug
/// only if it opens INT or EXT, because a draft is full of lines that merely
/// look like headings. Nobody typing into the New scene box is under that
/// suspicion — whatever they typed *is* the heading, and the only job left is
/// working out which part is which. So this is the forgiving twin, and it
/// lives here rather than in the app so the Mac, the phone and Claude all read
/// a typed heading the same way.
///
/// `34 INT. CAR - NIGHT`, `INT. CAR - NIGHT`, `34 CAR - DAY`, `CAR` and a bare
/// `34` all read. Unlike the import it never answers "not a scene": an empty
/// part simply means that part was not typed.
///
/// **The number is still the script's.** This reads the one a person typed; it
/// never invents one.
///
/// The time is snapped to one of `TIMES_OF_DAY` when it means one of them —
/// DAWN is a sunrise, MAGIC HOUR a sunset — and kept as written when it means
/// none of them, so CONTINUOUS and LATER survive.
pub fn read_heading(line: &str) -> ScriptScene {
    let trimmed = line.trim();
    let mut scene = read_slug(trimmed).unwrap_or_else(|| {
        // No INT or EXT in front, so read what is left the same way round: a
        // number first, then the place and the time either side of a dash.
        let mut rest = trimmed;
        let mut number = None;
        match rest.split_once(char::is_whitespace) {
            Some((head, tail)) if looks_like_a_scene_number(head) => {
                number = Some(head.trim_end_matches('.').to_string());
                rest = tail.trim_start();
            }
            // A bare number and nothing else — which is all the box used to
            // ask for, so what he types today keeps working.
            None if looks_like_a_scene_number(rest) => {
                number = Some(rest.trim_end_matches('.').to_string());
                rest = "";
            }
            _ => {}
        }
        let (location, time_of_day) = split_place_from_time(rest);
        ScriptScene {
            number,
            int_ext: String::new(),
            location: location.to_uppercase(),
            time_of_day: time_of_day.to_uppercase(),
            heading: rest.to_string(),
            body: String::new(),
        }
    });

    if let Some(meant) = time_of_day_meaning(&scene.time_of_day) {
        scene.time_of_day = meant.to_string();
    }
    scene
}

// ---- the time of day -----------------------------------------------------
//
// His report, 2026-08-22 (Ref 257): *"I'm noticing on script import you are
// importing CONTINUED and LATER as time of day. those should not be import as
// time of day options. They are markers telling you what time of day it is
// based on the previous scene that had proper time of day."* And: *"we can
// keep the script's headings custom time of day in the written header — but
// all time of days should conform to one of the options on the list."*
//
// So there are two jobs and they are separate. **The heading is never
// touched** — `heading` keeps whatever the writer printed, MAGIC HOUR and
// all, because the slugline is the script's and not ours. Only the
// `time_of_day` *field* — the one that fills a column, sorts a list and
// answers a filter — is snapped to the list the app actually offers.

/// The times of day the app holds. Everything a script writes is snapped to
/// one of these or to nothing at all.
///
/// **CONTINUOUS is deliberately not here.** It is not a time of day; it is a
/// sentence about the previous scene, which is exactly what he reported.
///
/// **Four, and only four** — his instruction of 2026-09-02, after taking it
/// from seven to six the same afternoon:
///
/// > 1. Sunrise — 2nd coolest
/// > 2. Day — brightest yellowish
/// > 3. Sunset — warmest
/// > 4. Night — coolest
///
/// Everything else a writer might put after the dash is one of these. The two
/// edges of the day each keep one word: DAWN is a SUNRISE, DUSK is a SUNSET.
/// Everything lit is DAY, so a morning and an afternoon are both simply day.
///
/// **Nothing written is lost.** A script that says MAGIC HOUR still prints
/// MAGIC HOUR in its slug line — only the *field* behind it, the one that
/// fills a column and answers a filter, is snapped to one of these four. The
/// slug is the script's and has never been ours to rewrite.
pub const TIMES_OF_DAY: [&str; 4] = [
    "SUNRISE",
    "DAY",
    "SUNSET",
    "NIGHT",
];

/// What a written time of day means, if it means one of ours.
///
/// Matched on whole words, longest first, so `LATE NIGHT` is NIGHT and
/// `YESTERDAY` is not DAY. The synonyms are the ones that turn up in real
/// drafts — a call sheet has never said DUSK when the writer wrote MAGIC HOUR.
pub fn time_of_day_meaning(written: &str) -> Option<&'static str> {
    const MEANINGS: [(&str, &str); 18] = [
        ("MIDNIGHT", "NIGHT"),
        ("NIGHT", "NIGHT"),
        // The morning edge. DAWN is the word most drafts use and it is a
        // sunrise; so is the hour either side of it.
        ("SUNRISE", "SUNRISE"),
        ("DAYBREAK", "SUNRISE"),
        ("SUNUP", "SUNRISE"),
        ("DAWN", "SUNRISE"),
        // The evening edge, and the same bargain in the other direction. DUSK
        // and TWILIGHT are the cool end of a sunset rather than a fifth answer.
        ("SUNSET", "SUNSET"),
        ("SUNDOWN", "SUNSET"),
        ("EVENING", "SUNSET"),
        ("TWILIGHT", "SUNSET"),
        ("NIGHTFALL", "SUNSET"),
        ("DUSK", "SUNSET"),
        // Everything lit.
        ("MORNING", "DAY"),
        ("AFTERNOON", "DAY"),
        ("NOON", "DAY"),
        ("MIDDAY", "DAY"),
        ("DAYTIME", "DAY"),
        ("DAY", "DAY"),
    ];
    // Words, not substrings. `MAGIC HOUR` and `GOLDEN HOUR` are two words and
    // are handled first, before anything is split.
    let upper = written.to_uppercase();
    if upper.contains("MAGIC HOUR") || upper.contains("GOLDEN HOUR") {
        return Some("SUNSET");
    }
    if upper.contains("PRE-DAWN") || upper.contains("PREDAWN") {
        return Some("SUNRISE");
    }
    let words: Vec<&str> = upper
        .split(|c: char| !c.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
        .collect();
    for (needle, meaning) in MEANINGS {
        if words.contains(&needle) {
            return Some(meaning);
        }
    }
    None
}

/// Whether a written time of day is really a pointer back at the last scene
/// that named one — CONTINUOUS, CONTINUED, LATER, SAME.
///
/// Only consulted **after** `time_of_day_meaning`, so `LATER THAT NIGHT` is
/// night rather than a pointer, and `THE NEXT MORNING` is morning.
pub fn carries_the_last_time_forward(written: &str) -> bool {
    const MARKERS: [&str; 8] = [
        "CONTINUOUS",
        "CONTINUED",
        "CONTD",
        "CONT",
        "LATER",
        "SAME",
        "MOMENTS",
        "MOMENT",
    ];
    let upper = written.to_uppercase();
    let words: Vec<&str> = upper
        .split(|c: char| !c.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
        .collect();
    !words.is_empty() && words.iter().any(|w| MARKERS.contains(w))
}

/// Walk a draft in order and settle every scene's time of day.
///
/// A scene that points back — CONTINUOUS, LATER — takes the last real one, so
/// three scenes of CONTINUOUS after a MORNING are all morning, which is what he
/// asked for and what a call sheet needs. A scene whose time of day is nothing
/// we recognise keeps its heading and loses the field, rather than putting a
/// word in a column that nothing else in the app can match.
pub fn settle_times_of_day(scenes: &mut [ScriptScene]) {
    let mut carried = String::new();
    for scene in scenes.iter_mut() {
        let written = scene.time_of_day.trim().to_string();
        // **A scene with no time of day takes the last one too.** His ruling,
        // 2026-08-22: *"scenes that don't carry a time of day should just
        // assume the TOD from the last scene that had one."* A slug that names
        // no time is the same claim CONTINUOUS makes, written more quietly —
        // and a call sheet cannot use a blank.
        //
        // The heading is untouched either way, so a slug that printed no time
        // still prints no time.
        if written.is_empty() {
            scene.time_of_day = carried.clone();
            continue;
        }
        if let Some(meaning) = time_of_day_meaning(&written) {
            carried = meaning.to_string();
            scene.time_of_day = meaning.to_string();
        } else if carries_the_last_time_forward(&written) {
            // Nothing to carry yet — the first scene of the film cannot say
            // "the same as before". Left empty rather than guessed at.
            scene.time_of_day = carried.clone();
        } else {
            scene.time_of_day = String::new();
        }
    }
}

/// The opening of a scene's action, for saying *which* rewrite this is without
/// printing the whole scene into a report somebody has to read.
fn first_words(body: &str) -> String {
    let flat = body.split_whitespace().collect::<Vec<_>>().join(" ");
    if flat.chars().count() <= 120 {
        return flat;
    }
    let mut out: String = flat.chars().take(120).collect();
    // Back off to the last whole word, so a report never ends mid-word.
    if let Some(at) = out.rfind(' ') {
        out.truncate(at);
    }
    out.push('…');
    out
}

fn looks_like_a_scene_number(word: &str) -> bool {
    let cleaned = word.trim_end_matches('.');
    !cleaned.is_empty()
        && cleaned.chars().next().is_some_and(|c| c.is_ascii_digit())
        && cleaned.chars().all(|c| c.is_ascii_alphanumeric())
        && cleaned.len() <= 6
}

/// The forms a slug actually gets printed in. `I/E`, `INT./EXT.` and
/// `EXT./INT.` all mean both, and all turn up; `crate::insideout` reads them.
fn starts_with_int_ext(_upper: &str, original: &str) -> Option<(String, String)> {
    let (meant, after) = crate::insideout::split_front(original)?;
    Some((meant.word().to_string(), after))
}

// ---- comparing it to the list -------------------------------------------

impl Doc {
    /// What a new draft would change, without changing anything.
    pub fn diff_script(&self, draft: &[ScriptScene]) -> ScriptDiff {
        let mut diff = ScriptDiff::default();
        let mut matched: Vec<Id> = Vec::new();

        for scene in draft {
            let Some(number) = scene.number.as_deref() else {
                diff.unnumbered += 1;
                diff.added.push(scene.clone());
                continue;
            };
            match self.scene_numbered(number) {
                Some(existing) => {
                    matched.push(existing);
                    let differences = self.differences(existing, scene);
                    if differences.is_empty() {
                        diff.unchanged += 1;
                    } else {
                        diff.changed.push(SceneChange {
                            scene: existing,
                            number: number.to_string(),
                            differences,
                            draft: scene.clone(),
                        });
                    }
                }
                None => diff.added.push(scene.clone()),
            }
        }

        for scene in self.scenes_in_order() {
            if matched.contains(&scene) {
                continue;
            }
            let Some(record) = self.get(scene) else { continue };
            let number = record.text(f::NUMBER).unwrap_or_default().to_string();
            // A scene with no number was never in a numbered draft to begin
            // with, so a numbered draft not mentioning it says nothing.
            if number.is_empty() {
                continue;
            }
            diff.gone.push(GoneScene {
                scene,
                number,
                heading: self.scene_heading(scene).unwrap_or_default(),
                shots: self.placements_in_scene(scene).len(),
            });
        }

        diff
    }

    /// The scene carrying a number, compared the way a person reads it so that
    /// `034` and `34` are the same scene.
    pub fn scene_numbered(&self, number: &str) -> Option<Id> {
        self.scenes_in_order().into_iter().find(|scene| {
            self.get(*scene)
                .and_then(|record| record.text(f::NUMBER))
                .is_some_and(|existing| natural::same(existing, number))
        })
    }

    fn differences(&self, scene: Id, draft: &ScriptScene) -> Vec<(String, String, String)> {
        let Some(record) = self.get(scene) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for (field, drafted) in [
            (f::INT_EXT, &draft.int_ext),
            (f::LOCATION, &draft.location),
            (f::TIME_OF_DAY, &draft.time_of_day),
        ] {
            let ours = record.text(field).unwrap_or_default();
            // A draft that is silent about something is not disagreeing with it.
            if drafted.is_empty() || ours.eq_ignore_ascii_case(drafted) {
                continue;
            }
            out.push((field.to_string(), ours.to_string(), drafted.clone()));
        }
        // **And what the scene actually says.**
        //
        // Only the slug was ever compared, so a scene rewritten from top to
        // bottom came back as *unchanged* while a `DAY` that had become
        // `CONTINUOUS` came back as changed. On Call Her Back that meant ten
        // scenes reported as different, every one of them a cosmetic
        // time-of-day string, and not one of the two real rewrites among them —
        // which is worse than reporting nothing, because it reads as a report
        // that looked.
        //
        // Judged on the words rather than character by character: a draft
        // re-flowed in another program differs on every line and says the same
        // thing. Four fifths shared is the same figure a moved scene is
        // recognised by.
        let ours = record.text(f::SCRIPT).unwrap_or_default();
        if !draft.body.trim().is_empty()
            && !ours.trim().is_empty()
            && crate::revisions::body_overlap(ours, &draft.body) < 0.8
        {
            out.push((
                f::SCRIPT.to_string(),
                first_words(ours),
                first_words(&draft.body),
            ));
        }
        out
    }

    /// Take a diff on: create the new scenes, update the changed ones, and leave
    /// the missing ones exactly where they are.
    ///
    /// One undoable step however many scenes it touches, so a draft applied by
    /// mistake is one ⌘Z rather than an afternoon.
    pub fn apply_script(&mut self, diff: &ScriptDiff) -> usize {
        let tx = self.begin("Apply a new draft");
        let mut touched = 0;

        for scene in &diff.added {
            let Some(number) = scene.number.as_deref() else {
                continue;
            };
            let id = self.create_scene(number);
            self.write_scene(id, scene);
            touched += 1;
        }

        for change in &diff.changed {
            self.write_scene(change.scene, &change.draft);
            touched += 1;
        }

        self.end(tx);
        touched
    }

    pub(crate) fn write_scene(&mut self, scene: Id, from: &ScriptScene) {
        // What the script actually printed, so a slug it wrote in an unusual
        // shape is never rebuilt into one it did not.
        if !from.heading.is_empty() {
            self.set(scene, f::HEADING, Value::text(&from.heading));
        }
        if !from.int_ext.is_empty() {
            self.set(scene, f::INT_EXT, Value::text(&from.int_ext));
        }
        if !from.location.is_empty() {
            self.set(scene, f::LOCATION, Value::text(&from.location));
        }
        if !from.time_of_day.is_empty() {
            self.set(scene, f::TIME_OF_DAY, Value::text(&from.time_of_day));
        }
        if !from.body.is_empty() {
            self.set(scene, f::SCRIPT, Value::text(&from.body));
        }
    }
}
