//! **The sheet** (Back to Paper, Batch 2, his call C, 2026-10-04): the page a
//! plan is drawn on — the Mac's screen, Export (the Share page's Diagram
//! page), the Print window, the portal's Print and Claude's paper picture —
//! built **once**, here, so the five can never drift apart again.
//!
//! A title across the top — the scene, the film and its day, north — the plan
//! to scale in a window, and a band along the foot: Notes, the Legend
//! (Film Lights · Practicals · Existing, then Frames by size) and the Shots
//! key, each only when it has something in it. No scale bar unless the plan
//! asks for one (his call G): then a bar and the scale written in the title.
//!
//! Everything is in **points** (1/72 inch) on the paper; the plan stands in
//! its window at `scale` points to the metre, its origin at (`ox`, `oy`).
//! The sheet's own words and marks come back as shapes in points
//! (`furniture`), so the Mac paints them with the plan's own painter, and
//! the lines a click can pick (a legend line, a head, the notes) as boxes.

use super::render::{self, Context, Geom, Ink, Options, Shape, Xf};
use super::{frame, plot, svg, Diagram, Kind};
use crate::doc::{f, Doc};
use crate::id::Id;
use crate::jsonw::Json;
use std::fmt::Write;

/// The paper's edge to the sheet's contents, all round — the Mac's page
/// cutter's own margin for a diagram (`Printing.Kind.diagram`).
pub const MARGIN: f64 = 36.0;
/// Room left at the sheet's foot for the line Export and Print stamp under
/// every page — when it was made, Page 1 of 1 (`Printing.Footered`) — so it
/// never sits on the legend's last line. On screen too: the page is the page.
const FOOT_ROOM: f64 = 12.0;
/// The sheet's words: its lines and their heads.
pub const LINE_PT: f64 = 8.0;
pub const HEAD_PT: f64 = 7.0;
const ROW: f64 = 11.5;
const TITLE_PT: f64 = 15.0;
const SUB_PT: f64 = 7.5;
/// The legend's marks, across.
const MARK: f64 = 11.0;
/// How much of `MARK` a bar or panel mark is tall (a row is `ROW` high).
const UPRIGHT: f64 = 0.75;

/// A box on the sheet, points.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl Rect {
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x <= self.x + self.w && y >= self.y && y <= self.y + self.h
    }
}

/// What a page asks of the sheet beyond the plan's own settings: Export's
/// switches, and whether it is the screen.
#[derive(Clone, Debug)]
pub struct Ask {
    /// The way round, the paper and the scale bar, when the page says (the
    /// Share page's own switches); else the plan's (`Settings`).
    pub landscape: Option<bool>,
    pub paper: Option<String>,
    pub scale_bar: Option<bool>,
    /// Wall lengths and lens cones, as the plan has them unless turned off.
    pub dims: bool,
    pub cones: bool,
    /// The Shots key.
    pub key: bool,
    /// The plan drawn dark, as on the portal; the sheet stays white.
    pub dark: bool,
    /// On screen: an empty Notes block shows faintly, to be clicked and
    /// typed into; on paper it is left off.
    pub screen: bool,
    /// The day it is printed, as the shell writes a date; empty for none.
    pub printed: String,
    pub beat: u32,
    /// The shell's clock, minutes from UTC, as its plan is drawn with
    /// (`Context::utc_offset`): the sun the page is fitted round is the sun
    /// the screen draws.
    pub tz: Option<f64>,
}

impl Default for Ask {
    fn default() -> Ask {
        Ask { landscape: None, paper: None, scale_bar: None, dims: true, cones: true, key: true, dark: false, screen: false, printed: String::new(), beat: 1, tz: None }
    }
}

/// Something on the sheet a click picks: a legend line (`legend`, its look
/// as `key`, its lamps as `ids`), a group head (`head`, `colour:added`), a
/// size of frame (`frames`), the Notes block (`notes`), a camera's line in
/// the Shots key (`shot`).
#[derive(Clone, Debug, PartialEq)]
pub struct Item {
    pub kind: &'static str,
    pub key: String,
    pub ids: Vec<String>,
    pub rect: Rect,
    /// What the line says, as typed (not in capitals).
    pub name: String,
    pub count: u32,
}

/// One line of the gear the plan uses, counted: `Lights`, `Practicals`,
/// `Frames`, `Grip`.
#[derive(Clone, Debug, PartialEq)]
pub struct Gear {
    pub group: &'static str,
    pub name: String,
    pub count: u32,
}

/// A camera's line in the Shots key.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ShotLine {
    pub camera: String,
    pub number: String,
    pub ink: String,
    /// Size, lens, movement, support, description — what the shot has.
    pub facts: Vec<String>,
}

/// The words a sheet's title carries.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Title {
    /// "8 · Style & Spice", or a loose plan's name.
    pub scene: String,
    /// "Let's Bake · Day 2 · 2026-10-04".
    pub film: String,
}

/// **The sheet, laid out.**
#[derive(Clone, Debug)]
pub struct Sheet {
    /// The paper, points, either way round.
    pub w: f64,
    pub h: f64,
    pub margin: f64,
    pub paper: String,
    pub landscape: bool,
    /// Where the plan is drawn.
    pub window: Rect,
    /// Points to the metre, and where the plan's origin lands — a point on
    /// the plan (turned `turn`, which is nought) is at
    /// (`ox` + x · `scale`, `oy` + y · `scale`).
    pub scale: f64,
    pub ox: f64,
    pub oy: f64,
    pub turn: f64,
    /// The scale written in the title — `1/4" = 1'-0"`, `1:50` — when the
    /// bar is shown and the scale is a standard one.
    pub stated: String,
    pub bar: bool,
    /// The sheet's own words, rules and marks, points.
    pub furniture: Vec<Shape>,
    pub items: Vec<Item>,
    pub gear: Vec<Gear>,
}

/// The paper, points, either way round.
pub fn paper_size(paper: &str, landscape: bool) -> (f64, f64) {
    let (w, h) = match paper {
        "tabloid" => (792.0, 1224.0),
        "a4" => (595.28, 841.89),
        _ => (612.0, 792.0),
    };
    if landscape {
        (h, w)
    } else {
        (w, h)
    }
}

/// **Standard scales**, largest first, as points to the metre and how
/// they are written: an architect's inches to the foot (and an engineer's
/// feet to the inch for a street), or a ratio in metres.
fn standards(units: &str) -> Vec<(f64, String)> {
    let inch = 72.0;
    if units == "m" {
        [10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0]
            .iter()
            .map(|n| (inch / 0.0254 / n, format!("1:{}", *n as i64)))
            .collect()
    } else {
        let foot = super::FOOT;
        let mut v: Vec<(f64, String)> = [
            (1.0, "1\""),
            (0.75, "3/4\""),
            (0.5, "1/2\""),
            (0.375, "3/8\""),
            (0.25, "1/4\""),
            (0.1875, "3/16\""),
            (0.125, "1/8\""),
            (0.09375, "3/32\""),
            (0.0625, "1/16\""),
        ]
        .iter()
        .map(|(i, t)| (i * inch / foot, format!("{t} = 1'-0\"")))
        .collect();
        for feet in [10.0, 20.0, 30.0, 40.0, 50.0, 100.0, 200.0, 500.0] {
            v.push((inch / (feet * foot), format!("1\" = {}'-0\"", feet as i64)));
        }
        v
    }
}

/// The largest standard scale at or under `fit`, and how it is written;
/// `fit` itself and nothing written when even the smallest is too big.
pub fn standard_scale(fit: f64, units: &str) -> (f64, String) {
    standards(units).into_iter().find(|(s, _)| *s <= fit + 1e-9).unwrap_or((fit, String::new()))
}


/// Words cut to fit `width` points at `size`, with an ellipsis.
fn fit(text: &str, size: f64, width: f64) -> String {
    if render::words_box_pt(text, size).0 <= width {
        return text.to_string();
    }
    let mut chars: Vec<char> = text.chars().collect();
    while !chars.is_empty() {
        chars.pop();
        let t: String = chars.iter().collect::<String>().trim_end().to_string() + "…";
        if render::words_box_pt(&t, size).0 <= width {
            return t;
        }
    }
    String::new()
}

/// Words broken into lines no wider than `width` at `size`; a line he
/// broke stays broken.
fn wrap(text: &str, size: f64, width: f64) -> Vec<String> {
    let mut out = Vec::new();
    for para in text.lines() {
        let mut line = String::new();
        for word in para.split_whitespace() {
            let next = if line.is_empty() { word.to_string() } else { format!("{line} {word}") };
            if render::words_box_pt(&next, size).0 <= width || line.is_empty() {
                line = next;
            } else {
                out.push(std::mem::take(&mut line));
                line = word.to_string();
            }
        }
        out.push(line);
    }
    while out.last().map(|l| l.is_empty()).unwrap_or(false) {
        out.pop();
    }
    out
}

fn words(x: f64, y: f64, text: &str, size: f64, ink: Ink, anchor: &'static str, bold: bool) -> Shape {
    let mut s = Shape::new(
        "",
        "sheet",
        Geom::Text { x, y, text: text.to_string(), size, anchor, bold, rot: 0.0, fixed: false, halo: false, patch: false, shift: (0.0, 0.0), under: Ink::None, lead: 1 },
    );
    s.fill = ink;
    s
}

fn rule(x1: f64, y1: f64, x2: f64, y2: f64, ink: Ink, w: f64) -> Shape {
    let mut s = Shape::new("", "sheet", Geom::Path(render::line(x1, y1, x2, y2)));
    s.stroke = ink;
    s.line = w;
    s
}

/// A role as the plan draws it: his colour for the category, else the
/// three inks (`render`'s last pass, the same sums).
fn inked(d: &Diagram, i: Ink) -> Ink {
    match i {
        Ink::Role(r) => match d.settings.colours.iter().find(|(k, _)| k == r) {
            Some((_, hex)) => Ink::hex(hex),
            None => Ink::Role(plot::three_inks(r)),
        },
        other => other,
    }
}

/// What a lamp's Type is called at the head of its lines: his words for
/// that ink, else its own.
fn head_name(d: &Diagram, role: &str) -> String {
    let key = format!("colour:{role}");
    d.legend.iter().find(|n| n.key == key).map(|n| n.name.clone()).unwrap_or_else(|| {
        match role {
            "practical" => "Practicals",
            "existing" => "Existing",
            _ => "Film Lights",
        }
        .to_string()
    })
}

/// The legend's marks' role for a look's ink.
fn role_of(look: &plot::Look) -> &'static str {
    match look.ink {
        "ink" => "existing",
        "practical" => "practical",
        _ => "added",
    }
}

/// One line the legend will write.
struct Line {
    kind: &'static str,
    key: String,
    ids: Vec<String>,
    text: String,
    name: String,
    count: u32,
    /// A mark: a lamp's look (and whether it hangs above), or a frame.
    look: Option<plot::Look>,
    /// Another Name of the symbol on the line before: drawn under it with
    /// no mark of its own, unless it starts a column. Never set since his
    /// pick of 2026-10-15 (every label wears its symbol); kept for the frame.
    follows: bool,
    /// Lamps with no label: written faint.
    dim: bool,
    frame: bool,
    head: bool,
}

/// **The gear the plan uses, counted** (Copy › Gear List): every kind of
/// lamp by its legend name times its Count — Film Lights, then Practicals;
/// the location's own are not brought — then frames by size and skin, then
/// grip by what it is.
pub fn gear(d: &Diagram) -> Vec<Gear> {
    let mut out: Vec<Gear> = Vec::new();
    let mut add = |group: &'static str, name: String, n: u32| match out.iter_mut().find(|g| g.group == group && g.name == name) {
        Some(g) => g.count += n,
        None => out.push(Gear { group, name, count: n }),
    };
    // Each lamp by its label, else its unit ("Arri M18"), else its mark —
    // a lamp with no label is still a piece of gear.
    let looks = plot::looks(d);
    for (role, group) in [("added", "Lights"), ("practical", "Practicals")] {
        for (id, look) in looks.iter().filter(|(_, l)| role_of(l) == role) {
            let Some(e) = d.get(id) else { continue };
            let name = plot::unit_name(e);
            let name = if name.is_empty() { mark_word(look) } else { name };
            add(group, name, e.count.max(1));
        }
    }
    for e in d.els.iter().filter(|e| !e.hidden && e.kind == Kind::Light && frame::is_frame(e)) {
        add("Frames", frame::plan_name(e), e.count.max(1));
    }
    for e in d.els.iter().filter(|e| !e.hidden && e.kind == Kind::Light && !frame::is_frame(e) && !plot::is_lamp(e)) {
        let name = if e.label.trim().is_empty() { super::symbols::plan_name(&e.sym) } else { e.label.trim().to_string() };
        if !name.is_empty() {
            add("Grip", name, e.count.max(1));
        }
    }
    out
}

/// A mark that stands for nothing yet, said in a word: "Chevron".
fn mark_word(l: &plot::Look) -> String {
    match l.mark {
        plot::Mark::Chevron => "Chevron".into(),
        plot::Mark::Wedge => "Wedge".into(),
        plot::Mark::Bar => "Bar".into(),
        plot::Mark::DoubleBar => "Panel".into(),
        plot::Mark::Ring => "Ring".into(),
        plot::Mark::Dot => "Dot".into(),
        plot::Mark::Arrow => "Arrow".into(),
        plot::Mark::Square => "Square".into(),
        plot::Mark::Mat => "Mat".into(),
        plot::Mark::Letter(c) => format!("{c}"),
    }
}

/// The legend's lines, heads among them: lamps grouped by Type (a head
/// each only when there is more than one Type), a line per symbol drawn
/// plainly however faded its lamps are (Ref 1505), then frames by size and
/// cloth.
fn legend_lines(d: &Diagram) -> Vec<Line> {
    let legend = plot::legend(d);
    let caps = d.settings.caps;
    let up = |s: &str| render::cased(caps, s);
    // **Exactly the labels as written** (his call, 2026-10-17): a count
    // after each only with Plan Settings › Counts; lamps and frames with no
    // label leave no line unless Show Unlabeled is on.
    let counted = |name: &str, n: u32| if d.settings.counts { format!("{name} ×{n}") } else { name.to_string() };
    let mut out = Vec::new();
    let shows = |x: &&plot::Entry| !x.name.trim().is_empty() || d.settings.unlabeled;
    let roles: Vec<&str> = ["added", "practical", "existing"].into_iter().filter(|r| legend.iter().filter(shows).any(|x| role_of(&x.look) == *r)).collect();
    for role in &roles {
        if roles.len() > 1 {
            let name = head_name(d, role);
            out.push(Line { kind: "head", key: format!("colour:{role}"), ids: Vec::new(), text: up(&name), name, count: 0, look: None, follows: false, dim: false, frame: false, head: true });
        }
        // **One line per label, each with its symbol** (his pick,
        // 2026-10-15); lamps with no label after, faint, a line a symbol.
        for x in legend.iter().filter(shows).filter(|x| role_of(&x.look) == *role) {
            let n = x.count;
            let dim = x.name.trim().is_empty();
            // A name on several lines reads as one line in the legend.
            let one = x.name.split_whitespace().collect::<Vec<_>>().join(" ");
            let text = if dim { counted("Unlabeled", n) } else { counted(&one, n) };
            out.push(Line { kind: "legend", key: x.key.clone(), ids: x.ids.clone(), text: up(&text), name: x.name.clone(), count: n, look: Some(x.look), follows: false, dim, frame: false, head: false });
        }
    }
    // Frames by the Name he gave them (2026-10-17) — never a size or cloth
    // written for him.
    let mut names: Vec<(String, Vec<String>, u32)> = Vec::new();
    for e in d.els.iter().filter(|e| !e.hidden && e.kind == Kind::Light && frame::is_frame(e)) {
        let name = plot::lamp_name(e);
        if name.is_empty() && !d.settings.unlabeled {
            continue;
        }
        match names.iter_mut().find(|s| s.0 == name) {
            Some(s) => {
                s.1.push(e.id.clone());
                s.2 += e.count.max(1);
            }
            None => names.push((name, vec![e.id.clone()], e.count.max(1))),
        }
    }
    names.sort_by_key(|n| n.0.is_empty());
    if !names.is_empty() {
        out.push(Line { kind: "head", key: "frames".into(), ids: Vec::new(), text: up("Frames"), name: "Frames".into(), count: 0, look: None, follows: false, dim: false, frame: false, head: true });
        for (name, ids, n) in names {
            let dim = name.is_empty();
            let one = name.split_whitespace().collect::<Vec<_>>().join(" ");
            let text = if dim { counted("Unlabeled", n) } else { counted(&one, n) };
            out.push(Line { kind: "frames", key: name.clone(), ids, text: up(&text), name, count: n, look: None, follows: false, dim, frame: true, head: false });
        }
    }
    out
}

/// Every camera on the plan, with what its shot says.
pub fn shot_lines(doc: &Doc, plan: &Diagram, ctx: &Context) -> Vec<ShotLine> {
    let text = |id: Id, field: &str| doc.get(id).and_then(|r| r.text(field)).unwrap_or("").trim().to_string();
    plan.els
        .iter()
        .filter(|e| e.kind == Kind::Camera && !e.hidden)
        .map(|cam| {
            let shot = cam.shot.parse::<u128>().ok().map(Id).filter(|s| doc.get(*s).is_some());
            let number = render::camera_name(cam, ctx);
            let facts: Vec<String> = match shot {
                Some(s) => {
                    let said = doc.described_by(s);
                    [f::SIZE, f::LENS, f::MOVEMENT, f::SUPPORT, f::DESCRIPTION].iter().map(|k| text(said, k)).filter(|t| !t.is_empty()).collect()
                }
                None if cam.lens > 0.0 => vec![format!("{}mm", cam.lens)],
                None => Vec::new(),
            };
            ShotLine { camera: cam.id.clone(), number: if number.is_empty() { "Camera".into() } else { number }, ink: cam.color.clone(), facts }
        })
        .collect()
}

/// The title a scene's or a loose plan's sheet carries.
pub fn title_of(doc: &Doc, scene: Id) -> Title {
    let film = doc.project_id().and_then(|id| doc.get(id)).and_then(|r| r.text(f::TITLE).map(String::from)).unwrap_or_default();
    if doc.is_plan(scene) {
        return Title { scene: doc.plan_name(scene), film };
    }
    // **One of several on a scene** (`scenediagrams`): the scene's words,
    // then which diagram — "5 · INT. KITCHEN — Reverse". A scene with one
    // diagram prints as it always did.
    let owner = scene;
    let scene = doc.diagram_scene(owner);
    let which = {
        let all = doc.scene_diagrams(scene);
        if all.len() > 1 { all.into_iter().find(|d| d.id == owner).map(|d| d.title) } else { None }
    };
    let number = doc.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or("").trim().to_string();
    let heading = doc.scene_heading(scene).unwrap_or_default();
    let scene_words = if number.is_empty() { heading } else { format!("{number} · {heading}") };
    let scene_words = match which { Some(w) => format!("{scene_words} — {w}"), None => scene_words };
    let mut film_line: Vec<String> = Vec::new();
    if !film.trim().is_empty() {
        film_line.push(film.trim().to_string());
    }
    let days = doc.days_of_scene(scene);
    let labels: Vec<String> = days.iter().filter_map(|d| doc.day_label(*d)).collect();
    if !labels.is_empty() {
        film_line.push(labels.join(", "));
    }
    if let Some(date) = days.iter().map(|d| doc.day_date(*d).trim().to_string()).find(|t| !t.is_empty()) {
        film_line.push(date);
    }
    Title { scene: scene_words, film: film_line.join(" · ") }
}

/// **Lay the sheet out** for a plan: its title, its shots and its notes as
/// given. The plan as asked (`Ask`'s dims and cones applied by the caller).
pub fn layout(d: &Diagram, ctx: &Context, title: &Title, shots: &[ShotLine], ask: &Ask) -> Sheet {
    // In capitals only with Plan Settings › All Caps (2026-10-17).
    let up = |s: &str| render::cased(d.settings.caps, s);
    let st = &d.settings;
    let landscape = ask.landscape.unwrap_or(st.orientation != "portrait");
    let paper = ask.paper.clone().filter(|p| super::PAPERS.contains(&p.as_str())).unwrap_or_else(|| st.paper.clone());
    let (w, h) = paper_size(&paper, landscape);
    let m = MARGIN;
    let bar = ask.scale_bar.unwrap_or(st.scale_bar) && !st.sketch;
    let mut furniture: Vec<Shape> = Vec::new();
    let mut items: Vec<Item> = Vec::new();
    let ink = || Ink::Role("ink");
    let grey = || Ink::Role("ink2");

    // ---------------------------------------------------- the band at the foot
    let band_w = w - 2.0 * m;
    let gap = 18.0;
    let notes_text = st.sheet_notes.trim().to_string();
    let notes_on = st.notes && (!notes_text.is_empty() || ask.screen);
    let lines = if st.legend { legend_lines(d) } else { Vec::new() };
    let shots: Vec<&ShotLine> = if ask.key { shots.iter().collect() } else { Vec::new() };
    // Each block as wide as its words want, within its share: an empty
    // Notes block kept on screen to be typed into is a narrow one.
    let wide = |t: &str, size: f64| render::words_box_pt(t, size).0;
    let notes_w = if !notes_on {
        0.0
    } else if notes_text.is_empty() {
        90.0
    } else {
        let want = up(&notes_text).lines().map(|l| wide(l, LINE_PT)).fold(0.0, f64::max) + 8.0;
        want.clamp(90.0, (band_w * 0.28).clamp(140.0, 240.0))
    };
    let shots_w = if shots.is_empty() {
        0.0
    } else {
        let want = shots.iter().map(|s| wide(&up(&s.number), LINE_PT) + wide(&up(&s.facts.join(" · ")), LINE_PT) + MARK + 20.0).fold(0.0, f64::max);
        want.clamp(110.0, (band_w * 0.3).clamp(170.0, 280.0))
    };
    let used = notes_w + shots_w + gap * ((notes_on as u8 + !shots.is_empty() as u8) as f64);
    let legend_w = if lines.is_empty() { 0.0 } else { (band_w - used).max(110.0) };
    let max_rows = (((h - 2.0 * m) * 0.3 - 14.0) / ROW).floor().max(3.0) as usize;
    let line_w = lines.iter().map(|l| if l.head { wide(&l.text, HEAD_PT) } else { wide(&l.text, LINE_PT) + MARK + 7.0 }).fold(0.0, f64::max) + 12.0;
    let mut cols = ((legend_w / line_w.clamp(110.0, 230.0)).floor() as usize).max(1);
    while !lines.is_empty() && lines.len().div_ceil(cols) > max_rows && legend_w / (cols as f64 + 1.0) >= 110.0 {
        cols += 1;
    }
    let col_w = if lines.is_empty() { 0.0 } else { (legend_w / cols as f64).min(line_w.max(110.0)) };
    let notes_lines = if notes_on { wrap(&up(&notes_text), LINE_PT, notes_w) } else { Vec::new() };
    let least = [notes_lines.len().max(notes_on as usize), shots.len(), 1].into_iter().max().unwrap_or(1);
    // The fewest rows the legend fits in across its columns, a head never
    // left at the foot of a column away from its lines.
    let mut rows = least.min(max_rows);
    let mut spots = flow(&lines, rows, cols);
    while spots.len() < lines.len() && rows < max_rows {
        rows += 1;
        spots = flow(&lines, rows, cols);
    }
    let rows = if lines.is_empty() && !notes_on && shots.is_empty() { 0 } else { rows };
    let band_h = if rows == 0 { 0.0 } else { 14.0 + rows as f64 * ROW };
    let band_top = h - m - FOOT_ROOM - band_h;
    if rows > 0 {
        furniture.push(rule(m, band_top - 9.0, w - m, band_top - 9.0, Ink::Role("tagline"), 0.6));
        let row_y = |i: usize| band_top + 14.0 + ROW * (i as f64 + 0.5);
        let mut x = m;
        // Notes: his words, under its head.
        if notes_on {
            let mut head = words(x, band_top + 3.5, &up("Notes"), HEAD_PT, grey(), "start", true);
            if notes_text.is_empty() {
                head.alpha = 0.35;
            }
            furniture.push(head);
            let shown = notes_lines.len().min(rows);
            for (i, l) in notes_lines.iter().take(shown).enumerate() {
                let l = if i + 1 == shown && notes_lines.len() > shown { fit(&format!("{l}…"), LINE_PT, notes_w) } else { l.clone() };
                furniture.push(words(x, row_y(i), &l, LINE_PT, ink(), "start", false));
            }
            items.push(Item { kind: "notes", key: "notes".into(), ids: Vec::new(), rect: Rect { x, y: band_top - 2.0, w: notes_w, h: band_h + 2.0 }, name: st.sheet_notes.clone(), count: 0 });
            x += notes_w + gap;
        }
        // The legend, flowing down its columns.
        if !lines.is_empty() {
            furniture.push(words(x, band_top + 3.5, &up("Legend"), HEAD_PT, grey(), "start", true));
            for (line, (c, r)) in lines.iter().zip(spots.iter().copied()) {
                let lx = x + c as f64 * col_w;
                let y = row_y(r);
                let text_x = if line.head { lx } else { lx + MARK + 7.0 };
                let room = col_w - (text_x - lx) - 6.0;
                if line.head {
                    furniture.push(words(text_x, y, &fit(&line.text, HEAD_PT, room), HEAD_PT, grey(), "start", true));
                } else {
                    furniture.push(words(text_x, y, &fit(&line.text, LINE_PT, room), LINE_PT, if line.dim { grey() } else { ink() }, "start", false));
                }
                // A symbol's other Names sit under it with no mark — but one
                // that starts a column wears it, so it never stands alone.
                if let Some(look) = line.look.filter(|_| !line.follows || r == 0) {
                    let role = Ink::Role(role_of(&look));
                    let colour = inked(d, role);
                    // An upright bar or panel is as tall as the size it is
                    // drawn at, so it is drawn smaller than the rest: at the
                    // full size one touches the next row's (Ref 1509).
                    let size = if matches!(look.mark, plot::Mark::Bar | plot::Mark::DoubleBar) { MARK * UPRIGHT } else { MARK };
                    let shapes = plot::mark(look, size, 0.0, colour.clone());
                    let xf = Xf::new(lx + MARK / 2.0, y, 0.0);
                    for mut s in shapes {
                        xf.shape(&mut s);
                        s.part = "sheet";
                        s.fill = inked(d, s.fill.clone());
                        s.stroke = inked(d, s.stroke.clone());
                        furniture.push(s);
                    }
                    if let plot::Mark::Letter(ch) = look.mark {
                        furniture.push(words(lx + MARK / 2.0, y, &ch.to_string(), MARK * 0.55, colour, "middle", true));
                    }
                }
                if line.frame {
                    let colour = inked(d, Ink::Role("gripink"));
                    for dy in [-1.6, 1.6] {
                        furniture.push(rule(lx, y + dy, lx + MARK, y + dy, colour.clone(), 1.1));
                    }
                }
                items.push(Item {
                    kind: line.kind,
                    key: line.key.clone(),
                    ids: line.ids.clone(),
                    rect: Rect { x: lx, y: y - ROW / 2.0, w: col_w - 4.0, h: ROW },
                    name: line.name.clone(),
                    count: line.count,
                });
            }
            x += cols as f64 * col_w + gap;
        }
        // The shots: each camera's number in its ink, and what its shot is.
        if !shots.is_empty() {
            furniture.push(words(x, band_top + 3.5, &up("Shots"), HEAD_PT, grey(), "start", true));
            for (i, s) in shots.iter().take(rows).enumerate() {
                let y = row_y(i);
                let colour = if s.ink.starts_with('#') { Ink::hex(&s.ink) } else { inked(d, Ink::Role("camink")) };
                for mut c in plot::camera(MARK * 0.8, colour.clone()) {
                    Xf::new(x + MARK / 2.0, y, 0.0).shape(&mut c);
                    c.part = "sheet";
                    c.fill = inked(d, c.fill.clone());
                    furniture.push(c);
                }
                let number = up(&s.number);
                furniture.push(words(x + MARK + 7.0, y, &number, LINE_PT, ink(), "start", true));
                let after = x + MARK + 7.0 + render::words_box_pt(&number, LINE_PT).0 + 6.0;
                let facts = up(&s.facts.join(" · "));
                if !facts.is_empty() {
                    furniture.push(words(after, y, &fit(&facts, LINE_PT, x + shots_w - after), LINE_PT, grey(), "start", false));
                }
                items.push(Item { kind: "shot", key: s.camera.clone(), ids: vec![s.camera.clone()], rect: Rect { x, y: y - ROW / 2.0, w: shots_w, h: ROW }, name: s.number.clone(), count: 1 });
            }
        }
    }

    // ---------------------------------------------------- the title
    let north_x = w - m - 10.0;
    let date_right = north_x - 22.0;
    let mut bar_room = 0.0;
    // The plan's scale is worked out before the title is written, so the
    // bar can say it.
    let window_top = m + 42.0;
    let window_bottom = if rows > 0 { band_top - 18.0 } else { h - m - FOOT_ROOM };
    let window = Rect { x: m, y: window_top, w: w - 2.0 * m, h: (window_bottom - window_top).max(40.0) };
    let (ext, scale, stated) = place(d, ctx, &window, ask, bar);
    let pad = (window.w - (ext.x2 - ext.x1) * scale) / 2.0;
    let ox = window.x + pad - ext.x1 * scale;
    let oy = window.y + (window.h - (ext.y2 - ext.y1) * scale) / 2.0 - ext.y1 * scale;
    if bar {
        // A bar of a round length, 30 to 110 points long, by the date.
        let lengths: &[f64] = if st.units == "m" { &[0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0] } else { &[1.0, 2.0, 4.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 500.0] };
        let unit = if st.units == "m" { 1.0 } else { super::FOOT };
        let len = lengths.iter().rev().find(|l| *l * unit * scale <= 110.0).or_else(|| lengths.first()).copied().unwrap_or(5.0);
        let pts = len * unit * scale;
        let (x1, y) = (date_right - pts, m + 6.0);
        let mut open = Shape::new("", "sheet", Geom::Path(render::rect(x1 + pts / 2.0, y, pts / 2.0, 4.0)));
        open.stroke = ink();
        open.line = 0.8;
        let mut solid = Shape::new("", "sheet", Geom::Path(render::rect(x1, y, pts / 2.0, 4.0)));
        solid.fill = ink();
        solid.stroke = ink();
        solid.line = 0.8;
        furniture.push(solid);
        furniture.push(open);
        let word = if st.units == "m" { format!("{} M", trim_num(len)) } else { format!("{} FT", trim_num(len)) };
        furniture.push(words(x1, y + 11.0, "0", 6.5, grey(), "middle", false));
        furniture.push(words(x1 + pts, y + 11.0, &word, 6.5, grey(), "middle", false));
        bar_room = pts + 24.0;
    }
    let title_w = w - 2.0 * m - 30.0 - bar_room;
    furniture.push(words(m, m + 8.0, &fit(&up(&title.scene), TITLE_PT, title_w), TITLE_PT, ink(), "start", true));
    let mut sub: Vec<String> = Vec::new();
    if !title.film.trim().is_empty() {
        sub.push(title.film.trim().to_string());
    }
    if bar && !stated.is_empty() {
        sub.push(format!("Scale {stated}"));
    }
    let date_w = if ask.printed.trim().is_empty() { 0.0 } else { render::words_box_pt(&up(ask.printed.trim()), SUB_PT).0 + 14.0 };
    if !sub.is_empty() {
        furniture.push(words(m, m + 25.0, &fit(&up(&sub.join(" · ")), SUB_PT, w - 2.0 * m - 30.0 - date_w), SUB_PT, grey(), "start", false));
    }
    if date_w > 0.0 {
        furniture.push(words(date_right, m + 25.0, &up(ask.printed.trim()), SUB_PT, grey(), "end", false));
    }
    // North: an arrow pointing to it, and N under it. A sketch shows it only
    // once he has said where north is.
    if !st.sketch || st.north.abs() > 1e-9 {
        let k = 9.0;
        let at = Xf::new(north_x, m + 9.0, -90.0 + render::north_bearing(d));
        let mut arrow = Shape::new("", "sheet", Geom::Path(at.path(&render::poly(&[(k, 0.0), (-k * 0.75, -k * 0.42), (-k * 0.4, 0.0), (-k * 0.75, k * 0.42)], true))));
        arrow.fill = ink();
        furniture.push(arrow);
        furniture.push(words(north_x, m + 25.0, "N", SUB_PT, ink(), "middle", true));
    }

    let mut out = Sheet {
        w,
        h,
        margin: m,
        paper,
        landscape,
        window,
        scale,
        ox,
        oy,
        turn: render::view_turn(d),
        stated: if bar { stated } else { String::new() },
        bar,
        furniture,
        items,
        gear: gear(d),
    };
    if d.settings.caps {
        for s in &mut out.furniture {
            if let Geom::Text { text, .. } = &mut s.geom {
                *text = text.to_uppercase();
            }
        }
    }
    out
}

/// Where each legend line stands, (column, row), flowing down `rows` rows
/// and across `cols` columns; a head at a column's foot goes to the top of
/// the next. As many lines as fit.
fn flow(lines: &[Line], rows: usize, cols: usize) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let (mut c, mut r) = (0usize, 0usize);
    for line in lines {
        if r >= rows || (line.head && r > 0 && r + 1 >= rows) {
            c += 1;
            r = 0;
        }
        if c >= cols {
            break;
        }
        out.push((c, r));
        r += 1;
    }
    out
}

fn trim_num(n: f64) -> String {
    if (n - n.round()).abs() < 1e-9 {
        format!("{}", n as i64)
    } else {
        format!("{n}")
    }
}

/// How much of the plan the window shows, and at what scale: the plan as
/// drawn on paper, its north and the sun's light left out, fitted to the
/// window inside a little room for the words that hang off it — at the
/// largest standard scale that fits, so the page does not jump while he
/// draws; to fit exactly on a sketch.
fn place(d: &Diagram, ctx: &Context, window: &Rect, ask: &Ask, bar: bool) -> (super::Aabb, f64, String) {
    let pad = 16.0;
    let fit_at = |scale: f64| {
        let ext = reach(d, ctx, ask, scale);
        let fit = ((window.w - 2.0 * pad) / (ext.x2 - ext.x1)).min((window.h - 2.0 * pad) / (ext.y2 - ext.y1)).max(0.5);
        let (scale, stated) = if bar && !d.settings.sketch { standard_scale(fit, &d.settings.units) } else { (steady(fit), String::new()) };
        (ext, scale, stated)
    };
    // **Fitted with its words at the size they are drawn** (Ref 1511):
    // words stand a set size on the page, so the smaller the plan is drawn
    // the more of it they cover — the sun's time hung off the window and
    // over the legend. Fitted at the nominal scale, then again at the scale
    // that gives, until it holds; never at a scale that would not fit.
    let mut placed = fit_at(0.0);
    for _ in 0..5 {
        // Its reach measured at the scale it was given, and the scale that
        // reach fits at.
        let next = fit_at(placed.1);
        if next.1 >= placed.1 - 1e-9 {
            // It fits where it is (a larger scale would only grow the
            // words' reach again): kept, with its reach at its own scale.
            placed.0 = next.0;
            return placed;
        }
        placed = next;
    }
    placed.0 = reach(d, ctx, ask, placed.1);
    placed
}

/// How far the plan reaches as drawn on the sheet at `scale` points to the
/// metre (0: nominal) — its words whole, at the sheet's lettering, its
/// north and the sun's light left out. A plan smaller than a metre each way
/// reaches a metre.
fn reach(d: &Diagram, ctx: &Context, ask: &Ask, scale: f64) -> super::Aabb {
    let mut shapes = render::render(d, ctx, &Options { beat: ask.beat.max(1), paper: true, scale, page: true, ..Options::default() });
    shapes.retain(|s| !matches!(s.part, "north" | "sunlight"));
    render::turn_shapes(&mut shapes, render::view_turn(d));
    let k = if scale > 0.0 { scale } else { render::NOMINAL_SCALE };
    let mut ext = render::bounds(&shapes).unwrap_or(super::Aabb { x1: 0.0, y1: 0.0, x2: 6.0, y2: 4.0 });
    for s in &shapes {
        if let Geom::Text { x, y, text, size, fixed: true, anchor, rot, .. } = &s.geom {
            let (w, h) = render::words_box_pt(text, *size);
            let (w, h) = ((w + 2.0 * render::PATCH_PAD) / k, (h + render::PATCH_PAD) / k);
            let (w, h) = if rot.abs() < 45.0 || rot.abs() > 135.0 { (w, h) } else { (h, w) };
            let x1 = match *anchor {
                "start" => *x,
                "end" => x - w,
                _ => x - w / 2.0,
            };
            ext.x1 = ext.x1.min(x1);
            ext.x2 = ext.x2.max(x1 + w);
            ext.y1 = ext.y1.min(y - h / 2.0);
            ext.y2 = ext.y2.max(y + h / 2.0);
        }
    }
    super::Aabb {
        x1: ext.x1.min((ext.x1 + ext.x2) / 2.0 - 0.5),
        x2: ext.x2.max((ext.x1 + ext.x2) / 2.0 + 0.5),
        y1: ext.y1.min((ext.y1 + ext.y2) / 2.0 - 0.5),
        y2: ext.y2.max((ext.y1 + ext.y2) / 2.0 + 0.5),
    }
}

/// **A scale that holds still**: the largest of a fine ladder of scales —
/// each about four per cent apart — at or under `fit`, so the plan fills
/// its window and does not creep with every small change at its edge.
/// With the scale bar on, the scale is a standard one, so the bar and the
/// title can say it.
pub fn steady(fit: f64) -> f64 {
    let step = 16.0;
    2f64.powf((fit.max(1e-6).log2() * step).floor() / step)
}

/// The plan's shapes on the sheet: drawn at the sheet's scale, so its
/// marks and names are their page size, with its own north left to the
/// title.
pub fn plan_shapes(d: &Diagram, ctx: &Context, sheet: &Sheet, beat: u32) -> Vec<Shape> {
    let mut shapes = render::render(d, ctx, &Options { beat: beat.max(1), paper: true, scale: sheet.scale, page: true, ..Options::default() });
    shapes.retain(|s| s.part != "north");
    render::turn_shapes(&mut shapes, sheet.turn);
    shapes
}

/// **The sheet as a picture**: an SVG of the whole page in points. `width`
/// is the size it is drawn at (nought: the paper's own, a point a pixel);
/// `crop`, the page without its margin — what the Mac's page cutter puts
/// its own margin round, so the sheet prints at its true size. `hrefs`,
/// `media` and `art` reach pictures as `svg::Frame` does.
#[allow(clippy::too_many_arguments)]
pub fn svg_of(d: &Diagram, ctx: &Context, sheet: &Sheet, ask: &Ask, width: f64, crop: bool, frame: &svg::Frame, id: &str) -> String {
    let (vx, vy, vw, vh) = if crop { (sheet.margin, sheet.margin, sheet.w - 2.0 * sheet.margin, sheet.h - 2.0 * sheet.margin - 1.0) } else { (0.0, 0.0, sheet.w, sheet.h) };
    let pw = if width > 0.0 { width } else { vw };
    let ph = pw * vh / vw;
    let mut o = String::new();
    let _ = write!(
        o,
        r#"<svg class="dia sheet" xmlns="http://www.w3.org/2000/svg" viewBox="{vx:.2} {vy:.2} {vw:.2} {vh:.2}" width="{pw:.1}" height="{ph:.1}" data-paper="{}" data-w="{:.2}" data-h="{:.2}" data-scale="{:.4}" data-ox="{:.2}" data-oy="{:.2}" style="--dia-paper:#FFFFFF">"#,
        sheet.paper, sheet.w, sheet.h, sheet.scale, sheet.ox, sheet.oy,
    );
    svg::style(&mut o);
    let _ = write!(o, r#"<rect x="0" y="0" width="{:.2}" height="{:.2}" style="fill:#FFFFFF"/>"#, sheet.w, sheet.h);
    let win = sheet.window;
    let _ = write!(o, r#"<defs><clipPath id="{id}-win"><rect x="{:.2}" y="{:.2}" width="{:.2}" height="{:.2}"/></clipPath></defs>"#, win.x, win.y, win.w, win.h);
    // The plan, in its window; dark when asked, as on the portal.
    let dark = if ask.dark {
        let mut v = String::new();
        for (role, colour) in svg::DARK {
            let _ = write!(v, "--d-{role}:{colour};");
        }
        v
    } else {
        String::new()
    };
    let _ = write!(o, r#"<g class="plan" clip-path="url(#{id}-win)" style="{dark}">"#);
    if ask.dark {
        let _ = write!(o, r#"<rect x="{:.2}" y="{:.2}" width="{:.2}" height="{:.2}" style="fill:var(--d-paper)"/>"#, win.x, win.y, win.w, win.h);
    }
    let shapes = plan_shapes(d, ctx, sheet, ask.beat);
    let (scale, ox, oy) = (sheet.scale, sheet.ox, sheet.oy);
    let px = |x: f64| ox + x * scale;
    let py = |y: f64| oy + y * scale;
    svg::body(&mut o, &shapes, &px, &py, scale, frame, id);
    o.push_str("</g>");
    // The sheet's own words and marks, a point a point.
    let same = |v: f64| v;
    let mut g = 0usize;
    for s in &sheet.furniture {
        svg::shape(&mut o, s, &same, &same, 1.0, frame, id, &mut g);
    }
    o.push_str("</svg>");
    o
}

/// **The sheet without its plan** — the paper and its own words and marks
/// (the title, north, the legend, the notes, the shots), a point a point,
/// for a shell that lays the plan on the page itself (the portal, as the
/// Mac's `drawDesk` and `drawPageFurniture` do). The paper is the page's
/// own `--d-paper`, so the screen's Backdrop lights it.
pub fn furniture_svg(sheet: &Sheet, frame: &svg::Frame, id: &str) -> String {
    let mut o = String::new();
    let _ = write!(
        o,
        r#"<svg class="dia furniture" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.2} {h:.2}" preserveAspectRatio="none">"#,
        w = sheet.w,
        h = sheet.h,
    );
    svg::style(&mut o);
    let _ = write!(o, r#"<rect x="0" y="0" width="{:.2}" height="{:.2}" style="fill:var(--d-paper)"/>"#, sheet.w, sheet.h);
    let same = |v: f64| v;
    let mut g = 0usize;
    for s in &sheet.furniture {
        svg::shape(&mut o, s, &same, &same, 1.0, frame, id, &mut g);
    }
    o.push_str("</svg>");
    o
}

/// The plan of `scene` as `ask` wants it printed: Export's switches over
/// the plan's own.
pub fn plan_for(doc: &Doc, scene: Id, ask: &Ask) -> (Diagram, Context) {
    let mut plan = doc.diagram(scene);
    plan.settings.dims = plan.settings.dims && ask.dims;
    plan.settings.cones = plan.settings.cones && ask.cones;
    let mut ctx = doc.diagram_context(scene);
    if ask.tz.is_some() {
        ctx.utc_offset = ask.tz;
    }
    (plan, ctx)
}

/// **A scene's sheet**, from the film: its title, its shots, laid out.
pub fn of(doc: &Doc, scene: Id, ask: &Ask) -> (Sheet, Diagram, Context) {
    let (plan, ctx) = plan_for(doc, scene, ask);
    let title = title_of(doc, scene);
    let shots = shot_lines(doc, &plan, &ctx);
    let sheet = layout(&plan, &ctx, &title, &shots, ask);
    (sheet, plan, ctx)
}

/// A scene's sheet as a picture of the whole page — the portal's Print and
/// Claude's paper picture. `width` nought: a point a pixel.
pub fn svg(doc: &Doc, scene: Id, ask: &Ask, width: f64, frame: &svg::Frame, id: &str) -> String {
    let (sheet, plan, ctx) = of(doc, scene, ask);
    svg_of(&plan, &ctx, &sheet, ask, width, false, frame, id)
}

/// **The sheet for a shell to draw itself** (the Mac): the paper, the
/// window and where the plan stands in it, the sheet's own words and marks
/// as shapes in points (`write_shape`'s wire), what a click picks, and the
/// gear list.
pub fn json(sheet: &Sheet) -> String {
    let mut j = Json::new();
    let r = |v: f64| (v * 100.0).round() / 100.0;
    j.obj()
        .kn("w", r(sheet.w))
        .kn("h", r(sheet.h))
        .kn("margin", sheet.margin)
        .kv("paper", &sheet.paper)
        .kv("orientation", if sheet.landscape { "landscape" } else { "portrait" })
        .kn("scale", (sheet.scale * 10_000.0).round() / 10_000.0)
        .kn("ox", r(sheet.ox))
        .kn("oy", r(sheet.oy))
        .kn("turn", sheet.turn)
        .kv("stated", &sheet.stated)
        .kb("bar", sheet.bar);
    // The sheet's lettering at its scale (`render::page_lettering`): a
    // shell drawing the plan on the page asks for it with `page=1`.
    let l = render::page_lettering(sheet.scale);
    j.kn("words", (l.words * 1000.0).round() / 1000.0).kn("marks", (l.marks * 1000.0).round() / 1000.0);
    let rect = |j: &mut Json, b: &Rect| {
        j.arr().num(r(b.x)).num(r(b.y)).num(r(b.w)).num(r(b.h)).end_arr();
    };
    j.key("window");
    rect(&mut j, &sheet.window);
    j.key("shapes");
    super::wire::write_shapes(&mut j, &sheet.furniture);
    j.key("items").arr();
    for it in &sheet.items {
        j.obj().kv("kind", it.kind).kv("key", &it.key).kv("name", &it.name).kn("count", it.count as f64);
        j.key("ids").arr();
        for id in &it.ids {
            j.str(id);
        }
        j.end_arr();
        j.key("box");
        rect(&mut j, &it.rect);
        j.end_obj();
    }
    j.end_arr();
    j.key("gear").arr();
    for g in &sheet.gear {
        j.obj().kv("group", g.group).kv("name", &g.name).kn("count", g.count as f64).end_obj();
    }
    j.end_arr();
    j.end_obj();
    j.finish()
}

/// What a click at (`x`, `y`) on the sheet picks, if anything.
pub fn item_at(sheet: &Sheet, x: f64, y: f64) -> Option<&Item> {
    sheet.items.iter().find(|i| i.rect.contains(x, y))
}
