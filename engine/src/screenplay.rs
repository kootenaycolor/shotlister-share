//! Reading a screenplay as a screenplay.
//!
//! `script.rs` reads a draft the way a scheduler does: find the slug lines, and
//! call everything underneath one of them "the body". That is exactly enough to
//! answer *what changed since Thursday*, and nowhere near enough to put the
//! script on screen — a page of a screenplay is not a paragraph of text, it is
//! a dozen kinds of line at a dozen different indents, and which kind each line
//! is decides where it sits and how it breaks across a page.
//!
//! So this module does the one job that module does not: it turns a draft into
//! **typed elements**. Scene heading, action, character, parenthetical,
//! dialogue, transition. Nothing here lays anything out — that is `pages.rs`,
//! which reads what this produces. This is only the question of *what is this
//! line*.
//!
//! Three formats arrive and all of them land here:
//!
//! - **Fountain**, the plain-text screenplay convention, in full: forced
//!   elements, notes, the boneyard, sections, synopses, dual dialogue, a title
//!   page.
//! - **Final Draft** `.fdx`, whose paragraphs are already typed — see
//!   `import/fdx.rs`, which builds the same `Screenplay` this does.
//! - **Plain text**, which is Fountain with none of the marks used, and which
//!   therefore needs no special path: a screenplay written normally is already
//!   readable by the rules below.
//!
//! One rule matters more than the rest: **a scene heading is whatever
//! `script.rs` says a scene heading is.** Its `read_slug` is called here rather
//! than reimplemented. Two opinions about what a slug looks like would mean the
//! script panel and the draft comparison could disagree about how many scenes a
//! film has, which is the sort of bug that costs an afternoon to even see.

use crate::script::{self, ScriptScene};

/// What a line of a screenplay is.
///
/// Ordered roughly as they appear on a page. `Section` and `Synopsis` are
/// Fountain's outlining marks: they carry a writer's structure, they are never
/// printed, and the pagination skips them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    SceneHeading,
    Action,
    Character,
    Parenthetical,
    Dialogue,
    /// A sung line. Rare, and set where dialogue is set.
    Lyric,
    Transition,
    /// `> like this <` — set in the middle of the measure.
    Centered,
    /// A page break the writer asked for by hand.
    PageBreak,
    /// `# Act One` — structure, not script.
    Section,
    /// `= what happens here` — a writer's note on a scene, not script.
    Synopsis,
}

impl Kind {
    /// The name this kind travels under, across the wire and in tests. Stable:
    /// the Swift side matches on these.
    pub fn name(self) -> &'static str {
        match self {
            Kind::SceneHeading => "heading",
            Kind::Action => "action",
            Kind::Character => "character",
            Kind::Parenthetical => "parenthetical",
            Kind::Dialogue => "dialogue",
            Kind::Lyric => "lyric",
            Kind::Transition => "transition",
            Kind::Centered => "centered",
            Kind::PageBreak => "page-break",
            Kind::Section => "section",
            Kind::Synopsis => "synopsis",
        }
    }

    /// Whether it reaches the page at all. Sections and synopses are the
    /// writer's scaffolding and are not printed, so they take up no room and
    /// are not measured.
    pub fn is_printed(self) -> bool {
        !matches!(self, Kind::Section | Kind::Synopsis)
    }

    /// Whether it belongs to somebody speaking. The page breaker needs this:
    /// the run of elements from a character cue to the end of their speech is
    /// the one run it may not part carelessly.
    pub fn is_speech(self) -> bool {
        matches!(
            self,
            Kind::Character | Kind::Parenthetical | Kind::Dialogue | Kind::Lyric
        )
    }
}

/// One element of a screenplay, as written.
#[derive(Clone, Debug, PartialEq)]
pub struct Element {
    pub kind: Kind,
    /// The text without its mark: a forced `@JIMMY` arrives here as `JIMMY`.
    /// Line breaks inside one element are kept — an action paragraph the writer
    /// broke by hand stays broken.
    pub text: String,
    /// Which scene it is in, as an index into `Screenplay::scenes`. `None` for
    /// anything standing before the first slug, which is where an epigraph or a
    /// stray note lives.
    pub scene: Option<usize>,
    /// The right-hand column of a dual-dialogue pair. The left column is the
    /// speech immediately before it.
    pub dual: bool,
}

impl Element {
    fn new(kind: Kind, text: impl Into<String>, scene: Option<usize>) -> Element {
        Element {
            kind,
            text: text.into(),
            scene,
            dual: false,
        }
    }
}

/// What the reader decided a heading was.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Status {
    /// A scene in its own right.
    Scene,
    /// A heading with no number of its own, sitting inside the scene above it —
    /// the bare `BATHROOM.` that a screenplay uses to move around a location
    /// without starting a new numbered scene. Lettered to its parent and
    /// **offered rather than taken**, because the rule that finds these is also
    /// the rule that would find a line of action written in capitals.
    SubSlug { under: usize },
}

/// A scene the reader found, and what it decided about it.
#[derive(Clone, Debug)]
pub struct Scene {
    /// In the shape `script.rs` compares drafts in.
    pub script: ScriptScene,
    pub status: Status,
    /// How it is named in a list: `34` for a numbered scene, `3A` for a
    /// sub-slug, empty for a scene with no number at all.
    pub label: String,
    /// Whether it should be taken by default. A sub-slug arrives unticked.
    pub accepted: bool,
}

/// A whole screenplay: its title page, its elements in order, and its scenes.
#[derive(Clone, Debug, Default)]
pub struct Screenplay {
    /// Title-page pairs as written — `("Title", "DAYBREAK")` — in their order.
    pub title: Vec<(String, String)>,
    pub elements: Vec<Element>,
    pub scenes: Vec<Scene>,
    /// Headings dropped for repeating a number already used. Counted rather
    /// than hidden, so the import can say how many it swallowed.
    pub duplicates_ignored: usize,
}

impl Screenplay {
    /// The elements belonging to one scene, by its index.
    pub fn elements_in(&self, scene: usize) -> Vec<&Element> {
        self.elements
            .iter()
            .filter(|element| element.scene == Some(scene))
            .collect()
    }

    /// The index of the scene printed with this number, compared the way a
    /// person reads it so `034` and `34` are the same scene.
    pub fn scene_numbered(&self, number: &str) -> Option<usize> {
        self.scenes.iter().position(|scene| {
            scene
                .script
                .number
                .as_deref()
                .is_some_and(|existing| crate::natural::same(existing, number))
        })
    }

    /// The scenes to actually act on, in the shape the draft comparison reads.
    /// Sub-slugs are left out unless somebody has ticked them.
    pub fn accepted(&self) -> Vec<ScriptScene> {
        self.scenes
            .iter()
            .filter(|scene| scene.accepted)
            .map(|scene| scene.script.clone())
            .collect()
    }

    /// One title-page value, by key, case-insensitively.
    pub fn titled(&self, key: &str) -> Option<&str> {
        self.title
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case(key))
            .map(|(_, value)| value.as_str())
    }
}

/// The rules the reader uses to decide what a scene heading is.
///
/// These exist because **reading a script off a printed page cannot be made
/// reliable, only adjustable.** A page prints `CONTINUED:` at the top of a
/// scene carried over from the page before, and it looks exactly like a slug to
/// anything reading lines. A revision reprints a page and a number turns up
/// twice. A location gets a bare room name under it and no number of its own.
///
/// Cadrage exposes the same four dials on their import sheet, having presumably
/// arrived at them the same way. Ours default to **off**, because a Fountain
/// file or plain text has none of these problems and should be read plainly;
/// `Detection::printed()` is the set for a script that has been through a
/// printer, which is what a PDF is.
#[derive(Clone, Debug, Default)]
pub struct Detection {
    /// A heading with no number does not open a scene of its own. It becomes a
    /// sub-slug lettered under the scene it sits in, offered unticked.
    pub must_have_a_number: bool,
    /// A number already used does not open a second scene. This is what a page
    /// header reprinting a slug looks like from here.
    pub ignore_duplicate_numbers: bool,
    /// Look for bare room names — `BATHROOM.` — standing alone inside a scene.
    /// Only worth doing where numbers are required, because that is the only
    /// world where an unnumbered heading means something particular.
    pub find_sub_slugs: bool,
    /// If any are given, a slug must contain one of them. `INT`, `EXT`.
    pub must_contain: Vec<String>,
    /// A line containing any of these is not a slug at all. `CONTINUED:`.
    pub never_contains: Vec<String>,
}

impl Detection {
    /// The rules for a script that has been through a printer — which is to say
    /// a PDF. Cadrage's own defaults, and for the same reasons.
    pub fn printed() -> Detection {
        Detection {
            must_have_a_number: true,
            ignore_duplicate_numbers: true,
            find_sub_slugs: true,
            must_contain: Vec::new(),
            never_contains: vec!["CONTINUED:".to_string()],
        }
    }

    /// Whether a line is disqualified outright — a page artifact, not a slug.
    fn forbids(&self, line: &str) -> bool {
        let upper = line.to_uppercase();
        self.never_contains
            .iter()
            .any(|word| !word.is_empty() && upper.contains(&word.to_uppercase()))
    }

    /// Whether a line carries one of the words a slug must have. Vacuously true
    /// when nobody has asked for any.
    fn permits(&self, line: &str) -> bool {
        if self.must_contain.is_empty() {
            return true;
        }
        let upper = line.to_uppercase();
        if self
            .must_contain
            .iter()
            .any(|word| !word.is_empty() && upper.contains(&word.to_uppercase()))
        {
            return true;
        }
        // **`I/E` carries neither word and is both.** A rule asking for INT or
        // EXT is asking for a scene that is inside or outside, and a scene
        // that is both is one — however the script abbreviates it.
        let asks_for_a_side = self.must_contain.iter().any(|word| {
            matches!(word.trim().trim_end_matches('.').to_uppercase().as_str(), "INT" | "EXT")
        });
        asks_for_a_side && script::read_slug(line).is_some_and(|slug| slug.int_ext == "INT/EXT")
    }
}

// ---- reading -------------------------------------------------------------

/// Read a screenplay: Fountain, or plain text, which is the same thing with
/// none of the marks used.
pub fn read(text: &str) -> Screenplay {
    read_with(text, &Detection::default())
}

/// Read a screenplay under a particular set of detection rules.
///
/// **Two passes, when a draft carries no numbers at all.** `must_have_a_number`
/// is on by default for a printed script, and it says an unnumbered heading
/// belongs to the scene above it. That is the right rule for a numbered draft
/// with the odd bare room name in it, and precisely the wrong one for the many
/// scripts that were simply never numbered: the first heading becomes a scene
/// with no label and every heading after it becomes a room, so the import has
/// nothing to take and quietly takes nothing. His report, 2026-08-22: *"a lot of
/// scripts I get don't have scene numbers attached … that should not stop it
/// from being imported."*
///
/// So: read it once, and if the draft turned out to carry no number anywhere,
/// read it again with that rule off and number the scenes by where they are.
///
/// **This is not renumbering.** Scene numbers belong to the script and we never
/// touch one — the law, and it stands. A draft with no numbers has none to
/// belong to it, and 1, 2, 3 in order is what an AD writes on it before anybody
/// can talk about it. One numbered scene anywhere is enough to say the writer
/// is numbering, and then an unnumbered heading goes back to meaning what
/// `must_have_a_number` says it means.
pub fn read_with(text: &str, detection: &Detection) -> Screenplay {
    let first = read_once(text, detection);
    let numbered = first.scenes.iter().any(|scene| scene.script.number.is_some());
    if !detection.must_have_a_number || first.scenes.is_empty() || numbered {
        return first;
    }
    let mut relaxed = detection.clone();
    relaxed.must_have_a_number = false;
    let mut again = read_once(text, &relaxed);
    number_by_position(&mut again);
    again
}

/// **A draft nobody numbered, numbered by where its scenes are.** Rooms found
/// under them are lettered again off the new numbers, because a room's label is
/// its parent's plus a letter and the parent had no label a moment ago.
fn number_by_position(screenplay: &mut Screenplay) {
    let mut number = 0usize;
    for at in 0..screenplay.scenes.len() {
        if screenplay.scenes[at].status != Status::Scene {
            continue;
        }
        number += 1;
        let said = number.to_string();
        screenplay.scenes[at].label = said.clone();
        screenplay.scenes[at].script.number = Some(said);
        screenplay.scenes[at].accepted = true;
    }
    let mut lettered: std::collections::HashMap<usize, usize> = std::collections::HashMap::new();
    for at in 0..screenplay.scenes.len() {
        let Status::SubSlug { under } = screenplay.scenes[at].status else {
            continue;
        };
        let seen = lettered.entry(under).or_insert(0);
        screenplay.scenes[at].label =
            format!("{}{}", screenplay.scenes[under].label, letters_for(*seen));
        *seen += 1;
    }
}

fn read_once(text: &str, detection: &Detection) -> Screenplay {
    let text = strip_boneyard_and_notes(&text.replace("\r\n", "\n").replace('\r', "\n"));
    let mut lines: Vec<&str> = text.lines().collect();

    let mut screenplay = Screenplay::default();
    let consumed = read_title_page(&lines, &mut screenplay.title);
    lines.drain(..consumed);

    let mut scene: Option<usize> = None;
    let mut at = 0;

    while at < lines.len() {
        let line = lines[at];
        if line.trim().is_empty() {
            at += 1;
            continue;
        }

        // A line the rules forbid is a page artifact — `CONTINUED:` at the top
        // of a carried-over scene — and it is dropped whole rather than merely
        // refused as a heading. Left in, it would become a transition, or a
        // paragraph of action that nobody wrote.
        if detection.forbids(line) {
            at += 1;
            continue;
        }

        // A blank line above is what lets a lone uppercase line be a name
        // rather than a shout in the middle of a paragraph.
        let after_blank = at == 0 || lines[at - 1].trim().is_empty();
        let next = lines.get(at + 1).map(|line| line.trim()).unwrap_or("");

        // Forced elements first: a mark is the writer overruling every rule
        // below it, and is the only way to write a scene called `.MEMORY` or a
        // character called `@McCLANE` that the rules would otherwise miss.
        if let Some(element) = forced(line, scene) {
            match element.kind {
                Kind::SceneHeading => {
                    scene = Some(open_scene(&mut screenplay, element.text.clone()));
                    push(&mut screenplay, Element::new(Kind::SceneHeading, element.text, scene));
                    at += 1;
                }
                Kind::Character => {
                    at = read_speech(&lines, at, scene, &mut screenplay, Some(element.text));
                }
                _ => {
                    let mut element = element;
                    element.scene = scene;
                    push(&mut screenplay, element);
                    at += 1;
                }
            }
            continue;
        }

        if detection.permits(line) {
            // A slug proper, or a heading the script numbered without writing
            // INT or EXT on it — which is a scene either way.
            let found = script::read_slug(line).or_else(|| script::read_numbered_heading(line));
            if let Some(slug) = found {
                match take_heading(&mut screenplay, slug, scene, detection) {
                    Taken::Opened(index) => {
                        let heading = screenplay.scenes[index].script.heading.clone();
                        scene = Some(index);
                        push(&mut screenplay, Element::new(Kind::SceneHeading, heading, scene));
                    }
                    // A number seen before: the page is repeating itself, and
                    // whatever follows belongs to the scene it names.
                    Taken::Duplicate(existing) => {
                        screenplay.duplicates_ignored += 1;
                        scene = Some(existing);
                    }
                }
                at += 1;
                continue;
            }

            // A bare room name inside a scene — `BATHROOM.` — which carries no
            // INT/EXT and so is invisible to `read_slug`.
            if detection.find_sub_slugs
                && after_blank
                && next.is_empty()
                && looks_like_a_sub_slug(line)
            {
                if let Some(parent) = scene {
                    let index = open_sub_slug(&mut screenplay, line.trim(), parent);
                    scene = Some(index);
                    push(
                        &mut screenplay,
                        Element::new(Kind::SceneHeading, line.trim().to_string(), scene),
                    );
                    at += 1;
                    continue;
                }
            }
        }

        if after_blank && next.is_empty() && looks_like_a_transition(line) {
            push(
                &mut screenplay,
                Element::new(Kind::Transition, line.trim().to_string(), scene),
            );
            at += 1;
            continue;
        }

        // A character cue: a name in capitals, with a blank line above it and
        // something for them to say below it. Without the line below, an
        // uppercase line is a shout in the action, which is a real thing people
        // write and must not become a silent speaker.
        if after_blank && !next.is_empty() && looks_like_a_character(line) {
            at = read_speech(&lines, at, scene, &mut screenplay, None);
            continue;
        }

        // Anything else is action, and runs until a blank line.
        let start = at;
        while at < lines.len() && !lines[at].trim().is_empty() {
            at += 1;
        }
        let block = lines[start..at]
            .iter()
            .map(|line| line.trim_end())
            .collect::<Vec<_>>()
            .join("\n");
        if !block.trim().is_empty() {
            push(&mut screenplay, Element::new(Kind::Action, block, scene));
        }
    }

    fill_bodies(&mut screenplay);
    // **CONTINUOUS is not a time of day** — Ref 257. Settled here, in order,
    // because a scene that points back at the last one can only be read once
    // the whole draft is in hand.
    let mut slugs: Vec<crate::script::ScriptScene> =
        screenplay.scenes.iter().map(|s| s.script.clone()).collect();
    crate::script::settle_times_of_day(&mut slugs);
    for (scene, slug) in screenplay.scenes.iter_mut().zip(slugs) {
        scene.script.time_of_day = slug.time_of_day;
    }
    screenplay
}

/// Read a character cue and everything they say, which is one block: the cue,
/// then parentheticals and dialogue until a blank line.
///
/// Returns the line to carry on from.
fn read_speech(
    lines: &[&str],
    at: usize,
    scene: Option<usize>,
    screenplay: &mut Screenplay,
    forced_name: Option<String>,
) -> usize {
    let raw = forced_name.unwrap_or_else(|| lines[at].trim().to_string());

    // `^` at the end says: print this speech beside the one before it.
    let (name, dual) = match raw.strip_suffix('^') {
        Some(name) => (name.trim_end().to_string(), true),
        None => (raw, false),
    };

    let first = screenplay.elements.len();
    push(screenplay, Element::new(Kind::Character, name, scene));

    let mut at = at + 1;
    while at < lines.len() && !lines[at].trim().is_empty() {
        let line = lines[at].trim();
        let kind = if line.starts_with('(') && line.ends_with(')') {
            Kind::Parenthetical
        } else if let Some(rest) = line.strip_prefix('~') {
            push(
                screenplay,
                Element::new(Kind::Lyric, rest.trim().to_string(), scene),
            );
            at += 1;
            continue;
        } else {
            Kind::Dialogue
        };
        push(screenplay, Element::new(kind, line.to_string(), scene));
        at += 1;
    }

    if dual {
        for element in &mut screenplay.elements[first..] {
            element.dual = true;
        }
    }

    at
}

fn push(screenplay: &mut Screenplay, element: Element) {
    screenplay.elements.push(element);
}

/// What happened when a heading was offered to the screenplay.
enum Taken {
    Opened(usize),
    /// A number already used. Carries the scene it repeats, because a reprinted
    /// heading means the page is resuming that scene and what follows belongs
    /// to it — not to whichever room the reader happened to be standing in when
    /// the page ended.
    Duplicate(usize),
}

/// Decide what a slug becomes under the rules, and open it.
fn take_heading(
    screenplay: &mut Screenplay,
    slug: ScriptScene,
    inside: Option<usize>,
    detection: &Detection,
) -> Taken {
    if let Some(number) = slug.number.as_deref() {
        if detection.ignore_duplicate_numbers {
            if let Some(existing) = screenplay.scene_numbered(number) {
                return Taken::Duplicate(existing);
            }
        }
    } else if detection.must_have_a_number {
        // No number where one is required: it belongs to the scene above it,
        // if there is one. With nothing above it there is nothing to letter it
        // under, so it stands as a scene and says so by having no label.
        if let Some(parent) = inside {
            let heading = slug.heading.clone();
            return Taken::Opened(open_sub_slug_from(screenplay, slug, &heading, parent));
        }
    }
    let label = slug.number.clone().unwrap_or_default();
    Taken::Opened(open_scene_from(screenplay, slug, label, Status::Scene, true))
}

/// A new scene from a heading whose slug we already read.
fn open_scene_from(
    screenplay: &mut Screenplay,
    script: ScriptScene,
    label: String,
    status: Status,
    accepted: bool,
) -> usize {
    screenplay.scenes.push(Scene {
        script,
        status,
        label,
        accepted,
    });
    screenplay.scenes.len() - 1
}

/// A bare room name standing inside a scene, lettered under its parent.
fn open_sub_slug(screenplay: &mut Screenplay, heading: &str, parent: usize) -> usize {
    let slug = ScriptScene {
        number: None,
        int_ext: String::new(),
        location: heading.trim_end_matches('.').to_uppercase(),
        time_of_day: String::new(),
        heading: heading.to_string(),
        body: String::new(),
    };
    open_sub_slug_from(screenplay, slug, heading, parent)
}

fn open_sub_slug_from(
    screenplay: &mut Screenplay,
    slug: ScriptScene,
    heading: &str,
    inside: usize,
) -> usize {
    let _ = heading;
    // Rooms letter under the numbered scene, never under each other: standing
    // in 3A when 3B arrives must still give 3B, not 3AA.
    let parent = match screenplay.scenes[inside].status {
        Status::SubSlug { under } => under,
        Status::Scene => inside,
    };
    // Letters run per parent, so scene 3's rooms are 3A…3G however many other
    // scenes have their own. This is scene lettering and has nothing to do with
    // `letters.rs`, which letters shots and obeys the shoot's own regime.
    let taken = screenplay
        .scenes
        .iter()
        .filter(|scene| scene.status == Status::SubSlug { under: parent })
        .count();
    let label = format!("{}{}", screenplay.scenes[parent].label, letters_for(taken));
    open_scene_from(screenplay, slug, label, Status::SubSlug { under: parent }, false)
}

/// `0` → `A`, `25` → `Z`, `26` → `AA`.
fn letters_for(mut index: usize) -> String {
    let mut out = String::new();
    loop {
        out.insert(0, (b'A' + (index % 26) as u8) as char);
        if index < 26 {
            return out;
        }
        index = index / 26 - 1;
    }
}

/// A bare room name: capitals, standing alone, short, and not a transition.
///
/// This is the loosest rule in the file and it knows it — a line of action
/// written in capitals matches it exactly. That is why what it finds is offered
/// unticked and why it is off unless numbers are being required.
fn looks_like_a_sub_slug(line: &str) -> bool {
    let text = line.trim();
    if text.is_empty() || text.ends_with(':') {
        return false;
    }
    if text.split_whitespace().count() > 5 {
        return false;
    }
    text.chars().any(|c| c.is_alphabetic()) && !text.chars().any(|c| c.is_lowercase())
}

/// A new scene from a forced heading, which may not parse as a slug at all —
/// `.MEMORY` is a perfectly good scene heading and says nothing about interiors.
///
/// A forced heading is the writer overruling the rules, so it is always taken.
fn open_scene(screenplay: &mut Screenplay, heading: String) -> usize {
    let slug = script::read_slug(&heading).unwrap_or(ScriptScene {
        number: None,
        int_ext: String::new(),
        location: heading.to_uppercase(),
        time_of_day: String::new(),
        heading: heading.clone(),
        body: String::new(),
    });
    let label = slug.number.clone().unwrap_or_default();
    open_scene_from(screenplay, slug, label, Status::Scene, true)
}

/// Give every scene the printed text underneath it, so that a screenplay read
/// here can go straight into `diff_script` — and so that the excerpt stored on
/// a scene is what a person would read, with the writer's private notes gone.
fn fill_bodies(screenplay: &mut Screenplay) {
    let mut bodies: Vec<String> = vec![String::new(); screenplay.scenes.len()];
    for element in &screenplay.elements {
        let Some(index) = element.scene else { continue };
        if element.kind == Kind::SceneHeading || !element.kind.is_printed() {
            continue;
        }
        let body = &mut bodies[index];
        if !body.is_empty() {
            body.push_str("\n\n");
        }
        body.push_str(&element.text);
    }
    for (scene, body) in screenplay.scenes.iter_mut().zip(bodies) {
        scene.script.body = body;
    }
}

// ---- the marks -----------------------------------------------------------

/// A line the writer typed a mark in front of to say what it is.
fn forced(line: &str, scene: Option<usize>) -> Option<Element> {
    let trimmed = line.trim_end();
    let body = trimmed.trim_start();

    // A page break is a rule of at least three, and must not be read as a
    // synopsis with a lot of equals signs in it.
    if body.len() >= 3 && body.chars().all(|c| c == '=') {
        return Some(Element::new(Kind::PageBreak, "", scene));
    }

    if let Some(rest) = body.strip_prefix('!') {
        return Some(Element::new(Kind::Action, rest.to_string(), scene));
    }
    if let Some(rest) = body.strip_prefix('@') {
        return Some(Element::new(Kind::Character, rest.trim().to_string(), scene));
    }
    if let Some(rest) = body.strip_prefix('~') {
        return Some(Element::new(Kind::Lyric, rest.trim().to_string(), scene));
    }
    if let Some(rest) = body.strip_prefix('#') {
        return Some(Element::new(
            Kind::Section,
            rest.trim_start_matches('#').trim().to_string(),
            scene,
        ));
    }
    if let Some(rest) = body.strip_prefix('=') {
        return Some(Element::new(Kind::Synopsis, rest.trim().to_string(), scene));
    }
    // `.` forces a heading, but `..` is an ellipsis somebody started a line
    // with, and `.` alone is nothing at all.
    if let Some(rest) = body.strip_prefix('.') {
        if !rest.starts_with('.') && !rest.trim().is_empty() {
            return Some(Element::new(Kind::SceneHeading, rest.trim().to_string(), scene));
        }
    }
    if let Some(rest) = body.strip_prefix('>') {
        let rest = rest.trim();
        return match rest.strip_suffix('<') {
            Some(middle) => Some(Element::new(Kind::Centered, middle.trim().to_string(), scene)),
            None => Some(Element::new(Kind::Transition, rest.to_string(), scene)),
        };
    }
    None
}

/// Capitals, with something in them that could be a name, and nothing that
/// gives them away as a slug or a shot. `JIMMY (V.O.)` and `MRS. O'HARA` count;
/// `A LOUD BANG.` does not, because it ends in a full stop and names nobody.
fn looks_like_a_character(line: &str) -> bool {
    let mut text = line.trim();
    if text.is_empty() {
        return false;
    }
    if let Some(stripped) = text.strip_suffix('^') {
        text = stripped.trim_end();
    }

    // The extension in brackets is not part of the name and is allowed to
    // contain full stops — `(V.O.)`, `(CONT'D)`.
    let name = match text.split_once('(') {
        Some((name, extension)) if extension.trim_end().ends_with(')') => name.trim_end(),
        Some(_) => return false,
        None => text,
    };
    if name.is_empty() {
        return false;
    }

    // Ending in a full stop is how a line of action in capitals reads.
    if name.ends_with('.') {
        return false;
    }
    // A cue is a name, not a sentence. Six words is generous for
    // `DETECTIVE SERGEANT ANNIE MARSDEN JR`.
    if name.split_whitespace().count() > 6 {
        return false;
    }
    if !name.chars().any(|c| c.is_alphabetic()) {
        return false;
    }
    if name.chars().any(|c| c.is_lowercase()) {
        return false;
    }
    // A transition is also in capitals; it is not somebody speaking.
    !looks_like_a_transition(line) && script::read_slug(line).is_none()
}

/// `CUT TO:` and its family. Capitals ending in a colon, which is what every
/// printed transition has in common.
fn looks_like_a_transition(line: &str) -> bool {
    let text = line.trim();
    if !text.ends_with(':') {
        return false;
    }
    let body = &text[..text.len() - 1];
    if body.is_empty() || body.chars().any(|c| c.is_lowercase()) {
        return false;
    }
    body.chars().any(|c| c.is_alphabetic()) && body.split_whitespace().count() <= 5
}

// ---- what never reaches the page ----------------------------------------

/// Take out the writer's private matter before anything else looks at the text:
/// the boneyard `/* … */`, which is how a writer parks a scene without deleting
/// it, and notes `[[ … ]]`, which are addressed to the writer and to nobody
/// else. Both may run over several lines.
fn strip_boneyard_and_notes(text: &str) -> String {
    let text = strip_between(text, "/*", "*/");
    strip_between(&text, "[[", "]]")
}

fn strip_between(text: &str, open: &str, close: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find(open) {
        out.push_str(&rest[..start]);
        match rest[start + open.len()..].find(close) {
            Some(end) => rest = &rest[start + open.len() + end + close.len()..],
            None => {
                // Never closed: the writer is mid-thought. Everything from the
                // mark on is theirs, not the film's.
                return out;
            }
        }
    }
    out.push_str(rest);
    out
}

// ---- the title page ------------------------------------------------------

/// Read the `Key: Value` block a Fountain screenplay may open with, and say how
/// many lines it used. A value may run on over indented lines beneath it.
///
/// The block only exists if the very first line is a pair, which stops an
/// ordinary screenplay opening on `INT. KITCHEN - DAY` from being mistaken for
/// one, and stops a line of dialogue containing a colon from starting a title
/// page in the middle of a film.
fn read_title_page(lines: &[&str], into: &mut Vec<(String, String)>) -> usize {
    let mut at = 0;
    while at < lines.len() && lines[at].trim().is_empty() {
        at += 1;
    }
    if at >= lines.len() || pair(lines[at]).is_none() {
        return 0;
    }

    let mut key: Option<String> = None;
    let mut value = String::new();

    while at < lines.len() {
        let line = lines[at];
        if line.trim().is_empty() {
            break;
        }
        match pair(line) {
            Some((name, rest)) => {
                if let Some(key) = key.take() {
                    into.push((key, value.trim().to_string()));
                }
                key = Some(name);
                value = rest;
            }
            None => {
                if key.is_none() {
                    break;
                }
                if !value.is_empty() {
                    value.push('\n');
                }
                value.push_str(line.trim());
            }
        }
        at += 1;
    }
    if let Some(key) = key {
        into.push((key, value.trim().to_string()));
    }

    // The blank line that closed the block belongs to the block.
    while at < lines.len() && lines[at].trim().is_empty() {
        at += 1;
    }
    at
}

/// `Title: Daybreak` → `("Title", "Daybreak")`. The key is one word or two, in
/// letters, which is what every title-page key is and what an ordinary line of
/// prose containing a colon is not.
fn pair(line: &str) -> Option<(String, String)> {
    if line.starts_with(' ') || line.starts_with('\t') {
        return None;
    }
    let (key, value) = line.split_once(':')?;
    let key = key.trim();
    if key.is_empty() || key.split_whitespace().count() > 2 {
        return None;
    }
    if !key
        .chars()
        .all(|c| c.is_alphabetic() || c.is_whitespace() || c == '-')
    {
        return None;
    }
    Some((key.to_string(), value.trim().to_string()))
}
