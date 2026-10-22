//! The diagram's commands: every one starts `diagram`, and all of them live
//! here rather than in `dispatch`, which is shared with every other thread.
//!
//! - `diagram <scene> [beat=] [sel=a,b] [ppm=] [page=1] [typing=]` — the plan,
//!   its shapes and its size; `ppm` is the shell's zoom, points to the metre,
//!   for placing names; `page=1`, that zoom is the sheet's and the plan is
//!   lettered as the sheet letters it; `typing` the piece whose words are
//!   being typed on the plan, its name drawn even when hidden (also on
//!   `diagramedit` and `diagrampreview`).
//! - `diagramedit <scene> <op> [beat=] [sel=]` — one edit (an op, as JSON,
//!   from `diagram::apply`), as one undo step; answers `{made, diagram}`.
//! - `diagrampreview <scene> <op> [beat=] [sel=]` — the shapes that edit
//!   *would* give, written nowhere. What a drag paints while it is moving.
//! - `diagramhit <scene> x y tol [beat=] [skip=a,b] [ppm=] [page=1]` — what is
//!   under a point, as drawn at that zoom and lettering.
//! - `diagramwithin <scene> x1 y1 x2 y2` — what a marquee catches.
//! - `diagramsnap <scene> x y reach [skip=a,b] [step=] [own=wall:corner]` —
//!   where a point wants to be: a corner, a wall's line, lined up square with
//!   a corner (`guides`, as `[x1,y1,x2,y2]` lines), or the grid. `own`: the
//!   corner being dragged, which is not a target.
//! - `diagramwall <scene> x y reach [w=] [step=]` — where a door lands in a
//!   wall; with its width and a step, slid so its near edge is a whole number
//!   of steps from the nearer corner (`from`, and the `face`/`edge` points
//!   that distance runs between).
//! - `diagramlibrary` — every drawing and sensor.
//! - `diagramart <id>` — a Film Set Objects picture, as base64 PNG.
//! - `diagramcast <scene>` — the characters the cast tool offers.
//! - `diagramroom <scene> <location> <path>` — lay a scanned room.
//! - `diagramcopy <scene> <from-scene> [mode=add] [ids=a,b]` — another
//!   scene's plan (or the pieces `ids` of it) onto this one, replacing what
//!   is here or, `mode=add`, on top of it.
//! - `diagramsend <scene> to=a,b [mode=add] [ids=a,b]` — this plan (or the
//!   pieces `ids`) onto other scenes'. Both one undo step.
//! - `diagramscenes` — the scenes with a plan, and how many pieces each holds.
//! - `diagramplans` — the loose plans (`diagram::plans`): id, name, pieces.
//! - `diagramplanadd <name> [from]` — a new one, blank or a copy of `from`'s
//!   diagram; answers its id. `diagramplanrename <id> <name>`,
//!   `diagramplandelete <id>` — each one undo step. Every other command here
//!   takes a plan's id where it says `<scene>`.
//! - `diagramsvg <scene> [width=] [paper=1] [beat=] [grid=0]` — a picture.
//! - `diagramsheet <scene> [screen=1] [printed=] [svg=1] [width=] [tz=]` — **the
//!   sheet** (`diagram::sheet`): the paper, the window the plan stands in and
//!   its scale, the sheet's own words and marks as shapes in points, what a
//!   click picks (legend lines, heads, the notes, the shots), the gear list;
//!   with `svg=1`, the whole page as a picture too. `screen=1`: an empty
//!   Notes block is kept, faint, to be clicked.
//! - `diagramfavorites <scene>` — the film's nine favorite slots.
//! - `diagramfavoriteset <scene> <slot> <id|->` — a piece into a slot, or
//!   `-` to empty it; one undo step. Answers the slots.
//! - `diagramfavoriteat <scene> <slot> <x> <y>` — that slot's piece, ready to
//!   `add` with its middle there.

use shotlister_engine::diagram::{self, render, svg, wire, Aabb};
use shotlister_engine::json;
use shotlister_engine::jsonw::Json;

use super::{error, id_from, writable, Handle, Options};

fn options<'a>(parts: impl Iterator<Item = &'a str>) -> (u32, Vec<String>, Options<'a>) {
    let o = Options::read(parts);
    let beat = o.number("beat").map(|b| b.max(1.0) as u32).unwrap_or(1);
    let sel = o.list("sel").unwrap_or_default();
    (beat, sel, o)
}

fn render_opts(beat: u32, sel: Vec<String>) -> render::Options {
    render::Options { beat, tween: 0.0, sel, paper: false, scale: 0.0, typing: String::new(), page: false }
}

/// `typing=` — the piece whose words are being typed on the plan: its name
/// is placed and drawn even when hidden, so the cursor stands where the
/// words will be (`render::Options::typing`).
fn typing(o: &Options) -> String {
    o.get("typing").unwrap_or("").to_string()
}

/// `tween=` — part of the way to the next beat, while playing.
fn tweened(beat: u32, sel: Vec<String>, o: &Options) -> render::Options {
    render::Options { beat, tween: o.number("tween").unwrap_or(0.0).clamp(0.0, 1.0), sel, paper: false, scale: ppm(o), typing: typing(o), page: page(o) }
}

/// `page=1` — the zoom is the sheet's own, and the plan is lettered as the
/// sheet letters it (`render::Options::page`, Ref 1511): the Mac with the
/// page on screen.
fn page(o: &Options) -> bool {
    o.get("page") == Some("1")
}

/// `ppm=` — the shell's zoom, in points to the metre, so names are kept
/// apart at the size they are shown (`render::place_names`).
fn ppm(o: &Options) -> f64 {
    o.number("ppm").filter(|v| v.is_finite() && *v > 0.0).unwrap_or(0.0)
}

pub fn command<'a>(h: &mut Handle, cmd: &str, mut parts: impl Iterator<Item = &'a str>) -> String {
    if cmd == "diagramlibrary" {
        return wire::library();
    }
    if cmd == "diagramart" {
        // A Film Set Objects picture's bytes, for the shells to paint.
        let id = parts.next().unwrap_or("").trim();
        let Some(a) = diagram::fso::find(id) else { return error("no such picture") };
        let mut j = Json::new();
        j.obj().kv("data", &super::b64::encode(a.png)).end_obj();
        return j.finish();
    }
    if cmd == "diagramglyph" {
        // One drawing on its own, sized to its footprint and centred on the
        // origin: a library tile, a tool's picture.
        let kind = parts.next().unwrap_or("set").trim().to_string();
        let sym = parts.next().unwrap_or("").trim().to_string();
        let w = parts.next().and_then(|v| v.trim().parse::<f64>().ok()).unwrap_or(1.0);
        let h = parts.next().and_then(|v| v.trim().parse::<f64>().ok()).unwrap_or(1.0);
        let Some(k) = diagram::Kind::parse(&kind) else { return error("no such kind") };
        let mut el = diagram::El::new(k, "glyph");
        el.sym = sym;
        el.w = w.max(0.01);
        el.h = h.max(0.01);
        el.cone = false;
        el.beam_on = false;
        el.label.clear();
        if k == diagram::Kind::Door || k == diagram::Kind::Window {
            el.h = 0.15;
        }
        let mut plan = diagram::Diagram::default();
        plan.settings.labels = false;
        plan.settings.dims = false;
        plan.els.push(el);
        let shapes = render::render(&plan, &render::Context::default(), &render::Options::default());
        let mut j = Json::new();
        j.obj().key("shapes");
        wire::write_shapes(&mut j, &shapes);
        j.end_obj();
        return j.finish();
    }
    if cmd == "diagramscenes" {
        let doc = h.project.doc();
        let mut j = Json::new();
        let with = doc.scenes_with_diagrams();
        let counts = doc.diagram_counts();
        j.obj().key("scenes").arr();
        for s in &with {
            j.str(&s.0.to_string());
        }
        j.end_arr().key("counts").obj();
        for s in &with {
            j.ki(&s.0.to_string(), counts.get(s).copied().unwrap_or(0) as i64);
        }
        // Every piece on all of a scene's diagrams (`scenediagrams`), and how
        // many diagrams it has — `counts` stays the scene's own, which is
        // what a copy onto it replaces.
        j.end_obj().key("totals").obj();
        for s in &with {
            j.ki(&s.0.to_string(), doc.scene_diagram_total(*s) as i64);
        }
        j.end_obj().key("several").obj();
        for s in &with {
            j.ki(&s.0.to_string(), doc.scene_diagram_ids(*s).len() as i64);
        }
        // Left out of the Diagram's list by hand (`scenediagrams`): kept in
        // `scenes` above, because Copy To and the editor still offer them.
        j.end_obj().key("hidden").arr();
        for s in &with {
            if doc.scene_diagram_hidden(*s) {
                j.str(&s.0.to_string());
            }
        }
        j.end_arr().end_obj();
        return j.finish();
    }
    // `diagramhide <on|off> <scene,scene…>` — Hide from Diagrams / Show: the
    // scenes left out of (or back in) the Diagram's list. One undo step.
    if cmd == "diagramhide" {
        if let Some(problem) = writable(h) {
            return problem;
        }
        let hide = parts.next().map(|s| s.trim() != "off").unwrap_or(true);
        let ids: Vec<shotlister_engine::Id> = parts.next().unwrap_or("").split(',').filter_map(|s| id_from(s.trim())).collect();
        let n = h.project.doc_mut().set_scenes_diagram_hidden(&ids, hide);
        let mut j = Json::new();
        j.obj().ki("changed", n as i64).end_obj();
        return j.finish();
    }
    if cmd == "diagramplans" {
        let doc = h.project.doc();
        let counts = doc.diagram_counts();
        let mut j = Json::new();
        j.obj().key("plans").arr();
        for p in doc.plans_in_order() {
            j.obj()
                .kv("id", &p.0.to_string())
                .kv("name", &doc.plan_name(p))
                .ki("count", counts.get(&p).copied().unwrap_or(0) as i64)
                .end_obj();
        }
        j.end_arr().end_obj();
        return j.finish();
    }
    if cmd == "diagramplanadd" {
        if let Some(problem) = writable(h) {
            return problem;
        }
        let name = parts.next().unwrap_or("").trim().to_string();
        let from = parts.next().and_then(|s| id_from(s.trim()));
        let id = h.project.doc_mut().add_plan(&name, from);
        let mut j = Json::new();
        j.obj().kv("id", &id.0.to_string()).end_obj();
        return j.finish();
    }
    // **A scene's diagrams** (`engine::diagram::scenediagrams`): list, add,
    // rename, move, delete. `scenediagrams <scene>`; `scenediagramadd
    // <scene> <name> [from]`; `scenediagramrename <id> <name>`;
    // `scenediagrammove <id> <index>`; `scenediagramdelete <id>`.
    if cmd.starts_with("scenediagram") {
        let Some(id) = parts.next().and_then(|s| id_from(s.trim())) else {
            return error("that is not a scene this project has");
        };
        if cmd != "scenediagrams" {
            if let Some(problem) = writable(h) {
                return problem;
            }
        }
        let list = |doc: &shotlister_engine::Doc, scene| {
            let mut j = Json::new();
            j.obj().key("diagrams").arr();
            for x in doc.scene_diagrams(scene) {
                j.obj().kv("id", &x.id.0.to_string()).kv("name", &x.name).kv("title", &x.title).ki("count", x.count as i64).end_obj();
            }
            j.end_arr().end_obj();
            j.finish()
        };
        return match cmd {
            "scenediagrams" => {
                let doc = h.project.doc();
                list(doc, doc.diagram_scene(id))
            }
            "scenediagramadd" => {
                let name = parts.next().unwrap_or("").to_string();
                let from = parts.next().and_then(|s| id_from(s.trim()));
                match h.project.doc_mut().add_scene_diagram(id, &name, from) {
                    Some(made) => {
                        let mut j = Json::new();
                        j.obj().kv("id", &made.0.to_string()).end_obj();
                        j.finish()
                    }
                    None => error("that is not a scene this project has"),
                }
            }
            "scenediagramrename" => {
                let name = parts.next().unwrap_or("").to_string();
                if h.project.doc_mut().rename_scene_diagram(id, &name) { "{\"ok\":true}".to_string() } else { error("that is not a diagram of a scene") }
            }
            "scenediagrammove" => {
                let at = parts.next().and_then(|s| s.trim().parse::<usize>().ok()).unwrap_or(0);
                if h.project.doc_mut().move_scene_diagram(id, at) { "{\"ok\":true}".to_string() } else { error("that is not a diagram of a scene") }
            }
            "scenediagramdelete" => {
                if h.project.doc_mut().delete_scene_diagram(id) { "{\"ok\":true}".to_string() } else { error("a scene keeps at least one diagram") }
            }
            _ => error("unknown command"),
        };
    }
    let Some(scene) = parts.next().and_then(|s| id_from(s.trim())) else {
        return error("that is not a scene this project has");
    };
    if h.project.doc().get(scene).is_none() {
        return error("that is not a scene this project has");
    }
    match cmd {
        "diagramplanrename" | "diagramplandelete" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            if !h.project.doc().is_plan(scene) {
                return error("that is not a plan");
            }
            if cmd == "diagramplanrename" {
                let name = parts.next().unwrap_or("").trim().to_string();
                h.project.doc_mut().rename_plan(scene, &name);
            } else {
                h.project.doc_mut().delete_plan(scene);
            }
            "{\"ok\":true}".to_string()
        }
        "diagramcast" => {
            // Who the cast tool offers: this scene's characters, then the film's.
            let (here, others) = h.project.doc().diagram_characters(scene);
            let mut j = Json::new();
            j.obj().key("scene").arr();
            for n in &here {
                j.str(n);
            }
            j.end_arr().key("film").arr();
            for n in &others {
                j.str(n);
            }
            j.end_arr().end_obj();
            j.finish()
        }
        "diagram" => {
            let (beat, sel, o) = options(parts);
            let doc = h.project.doc();
            let mut ctx = doc.diagram_context(scene);
            ctx.utc_offset = o.number("tz");
            wire::payload(&doc.diagram(scene), &ctx, &tweened(beat, sel, &o))
        }
        "diagramedit" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let Some(op) = parts.next().and_then(json::parse) else {
                return error("that edit could not be read");
            };
            let (beat, sel, o) = options(parts);
            let scale = ppm(&o);
            let made = match h.project.doc_mut().diagram_edit(scene, &op) {
                Ok(made) => made,
                Err(e) => return error(&e.to_string()),
            };
            // `join=1`: this edit and the one before are one gesture, one
            // step to take back (a burst of nudges; an ⌥-drag's copy and move).
            if o.number("join") == Some(1.0) {
                h.project.doc_mut().join_last_steps();
            }
            let doc = h.project.doc();
            let mut j = Json::new();
            j.obj().key("made").arr();
            for id in &made {
                j.str(id);
            }
            j.end_arr();
            // The Mac's clock, as `diagram` takes it: the sun stays put.
            let mut ctx = doc.diagram_context(scene);
            if o.number("tz").is_some() {
                ctx.utc_offset = o.number("tz");
            }
            j.key("diagram").raw(&wire::payload(&doc.diagram(scene), &ctx, &render::Options { scale, typing: typing(&o), page: page(&o), ..render_opts(beat, sel) }));
            j.end_obj();
            j.finish()
        }
        "diagrampreview" => {
            let Some(op) = parts.next().and_then(json::parse) else {
                return error("that edit could not be read");
            };
            let (beat, sel, o) = options(parts);
            let doc = h.project.doc();
            let mut plan = doc.diagram(scene);
            if let Err(e) = diagram::apply(&mut plan, &op) {
                return error(&e.to_string());
            }
            // The Mac's own clock, as `diagram` takes it, so a sun dragged
            // through the day in preview stands where it will when let go.
            let mut ctx = doc.diagram_context(scene);
            ctx.utc_offset = o.number("tz");
            // The whole plan as it would be — every piece's place as well as
            // its drawing — so whatever the Mac draws itself (a pick's
            // outline, its handles, the side panel) follows the drag too.
            wire::payload(&plan, &ctx, &render::Options { scale: ppm(&o), typing: typing(&o), page: page(&o), ..render_opts(beat, sel) })
        }
        "diagramhit" => {
            let x = parts.next().and_then(|v| v.parse::<f64>().ok());
            let y = parts.next().and_then(|v| v.parse::<f64>().ok());
            let tol = parts.next().and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.05);
            let (beat, _, o) = options(parts);
            let (Some(x), Some(y)) = (x, y) else { return error("where?") };
            let mut plan = h.project.doc().diagram(scene);
            // What this Mac is not showing (its Show panel) is not there to hit.
            let skip = o.list("skip").unwrap_or_default();
            plan.els.retain(|e| !skip.contains(&e.id));
            // As drawn at the Mac's zoom and lettering (`ppm=`, `page=1`):
            // a lamp by its mark, Words by their words (Ref 1511).
            let opt = render::Options { beat, scale: ppm(&o), page: page(&o), ..render::Options::default() };
            let mut j = Json::new();
            j.obj();
            match diagram::hit_drawn(&plan, x, y, tol, beat, &opt) {
                Some(id) => {
                    j.kv("id", &id);
                }
                None => {
                    j.key("id").null();
                }
            }
            j.end_obj();
            j.finish()
        }
        "diagramwithin" => {
            let n: Vec<f64> = (0..4).filter_map(|_| parts.next().and_then(|v| v.parse().ok())).collect();
            if n.len() < 4 {
                return error("where?");
            }
            let b = Aabb { x1: n[0].min(n[2]), y1: n[1].min(n[3]), x2: n[0].max(n[2]), y2: n[1].max(n[3]) };
            let ids = diagram::within(&h.project.doc().diagram(scene), b);
            let mut j = Json::new();
            j.obj().key("ids").arr();
            for id in &ids {
                j.str(id);
            }
            j.end_arr().end_obj();
            j.finish()
        }
        "diagramsnap" => {
            let n: Vec<f64> = (0..3).filter_map(|_| parts.next().and_then(|v| v.parse().ok())).collect();
            if n.len() < 3 {
                return error("where?");
            }
            let (_, _, o) = options(parts);
            let skip = o.list("skip").unwrap_or_default();
            let plan = h.project.doc().diagram(scene);
            // `step=` the grid the shell is showing, which follows its zoom.
            let step = o.number("step").filter(|s| *s > 1e-6).unwrap_or(plan.settings.step);
            // `own=<wall>:<corner>` — the corner being dragged.
            let own_text = o.get("own").unwrap_or("").to_string();
            let own = own_text.split_once(':').and_then(|(w, c)| c.parse::<usize>().ok().map(|c| (w, c)));
            let s = diagram::walls::snap(&plan, n[0], n[1], n[2], step, &skip, own);
            let mut j = Json::new();
            j.obj().kn("x", s.at.0).kn("y", s.at.1).kb("caught", s.caught);
            j.key("guides").arr();
            for (a, b) in &s.guides {
                j.arr().num(a.0).num(a.1).num(b.0).num(b.1).end_arr();
            }
            j.end_arr().end_obj();
            j.finish()
        }
        "diagramwall" => {
            let n: Vec<f64> = (0..3).filter_map(|_| parts.next().and_then(|v| v.parse().ok())).collect();
            if n.len() < 3 {
                return error("where?");
            }
            let (_, _, o) = options(parts);
            let (w, step) = (o.number("w").unwrap_or(0.0).max(0.0), o.number("step").unwrap_or(0.0).max(0.0));
            let mut j = Json::new();
            match diagram::walls::in_wall(&h.project.doc().diagram(scene), n[0], n[1], n[2], w, step) {
                Some(at) => {
                    j.obj().kn("x", at.x).kn("y", at.y).kn("rot", at.rot).kn("thick", at.thick);
                    j.kv("wall", &at.wall).kn("stretch", at.stretch as f64).kn("from", at.from);
                    j.kn("fx", at.face.0).kn("fy", at.face.1).kn("ex", at.edge.0).kn("ey", at.edge.1);
                    j.end_obj();
                }
                None => {
                    j.obj().key("x").null().end_obj();
                }
            }
            j.finish()
        }
        "diagramroom" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let location = parts.next().unwrap_or("").trim().to_string();
            let path = parts.next().unwrap_or("").trim().to_string();
            let plan = if path.is_empty() {
                shotlister_engine::room::sample()
            } else {
                match std::fs::read_to_string(&path) {
                    Ok(text) => shotlister_engine::room::read(&text),
                    Err(_) => return error("that scan could not be read"),
                }
            };
            let Some(plan) = plan else { return error("there is no room in that scan") };
            let made = h.project.doc_mut().diagram_import_room(scene, &plan, &location);
            let doc = h.project.doc();
            let mut j = Json::new();
            j.obj().ki("made", made.len() as i64);
            j.key("diagram").raw(&wire::payload(&doc.diagram(scene), &doc.diagram_context(scene), &render_opts(1, Vec::new())));
            j.end_obj();
            j.finish()
        }
        "diagrameverywhere" => {
            // diagrameverywhere <scene> <key> <json value> — a plan setting on every scene
            if let Some(problem) = writable(h) {
                return problem;
            }
            let key = parts.next().unwrap_or("").trim().to_string();
            let Some(value) = parts.next().and_then(json::parse) else {
                return error("that setting could not be read");
            };
            let n = h.project.doc_mut().diagram_setting_everywhere(&key, value);
            let doc = h.project.doc();
            let mut j = Json::new();
            j.obj().ki("scenes", n as i64);
            j.key("diagram").raw(&wire::payload(&doc.diagram(scene), &doc.diagram_context(scene), &render_opts(1, Vec::new())));
            j.end_obj();
            j.finish()
        }
        "diagramcopy" | "diagramsend" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let (from, to, o) = if cmd == "diagramcopy" {
                let Some(from) = parts.next().and_then(|s| id_from(s.trim())) else {
                    return error("that is not a scene this project has");
                };
                (from, vec![scene], Options::read(parts))
            } else {
                let o = Options::read(parts);
                (scene, o.ids("to"), o)
            };
            if h.project.doc().get(from).is_none() || to.iter().any(|t| h.project.doc().get(*t).is_none()) {
                return error("that is not a scene this project has");
            }
            let Some(mode) = diagram::copy::Mode::parse(o.get("mode").unwrap_or("")) else {
                return error("mode is replace or add");
            };
            let ids = o.list("ids").unwrap_or_default();
            let n = h.project.doc_mut().diagram_copy(from, &ids, &to, mode).len() / to.len().max(1);
            let doc = h.project.doc();
            let mut j = Json::new();
            j.obj().ki("copied", n as i64);
            j.key("diagram").raw(&wire::payload(&doc.diagram(scene), &doc.diagram_context(scene), &render_opts(1, Vec::new())));
            j.end_obj();
            j.finish()
        }
        "diagramimage" => {
            // diagramimage <scene> <width px> <height px> <ext> <base64> <filename> <x> <y> <width m> [photo]
            if let Some(problem) = writable(h) {
                return problem;
            }
            let pw: u32 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0);
            let ph: u32 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0);
            let ext = parts.next().unwrap_or("png").trim().to_lowercase();
            let Some(bytes) = parts.next().and_then(super::b64::decode).filter(|b| !b.is_empty()) else {
                return error("that picture could not be read");
            };
            let filename = parts.next().unwrap_or("").trim().to_string();
            let x: f64 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0.0);
            let y: f64 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0.0);
            let wide: f64 = parts.next().and_then(|v| v.trim().parse().ok()).unwrap_or(5.0);
            let photo = parts.next().map(str::trim) == Some("photo");
            let hash = shotlister_engine::sha256(&bytes);
            if let Err(e) = h.project.write_proxy(&hash.to_hex(), &ext, &bytes) {
                return error(&e.message());
            }
            let name = if filename.is_empty() { format!("plan.{ext}") } else { filename };
            match h.project.doc_mut().diagram_add_image(scene, hash, &ext, (pw, ph), bytes.len() as u64, &name, (x, y), wide, photo) {
                Some(id) => {
                    let doc = h.project.doc();
                    let mut j = Json::new();
                    j.obj().key("made").arr().str(&id).end_arr();
                    j.key("diagram").raw(&wire::payload(&doc.diagram(scene), &doc.diagram_context(scene), &render_opts(1, vec![id.clone()])));
                    j.end_obj();
                    j.finish()
                }
                None => error("the picture could not be laid on the plan"),
            }
        }
        "diagramsample" => {
            // The sample bedroom, laid on this scene — for checks, and for
            // seeing the plan without drawing one first.
            if let Some(problem) = writable(h) {
                return problem;
            }
            let mut plan = diagram::sample();
            // Its cameras stand for the scene's first shots, when it has them,
            // so the plan shows what a real one does.
            let shots: Vec<String> = {
                let doc = h.project.doc();
                doc.placements_in_scene(scene)
                    .into_iter()
                    .filter_map(|p| doc.get(p).and_then(|r| r.ref_id(shotlister_engine::doc::f::SHOT)))
                    .map(|s| s.0.to_string())
                    .collect()
            };
            let mut next = shots.into_iter();
            for (i, el) in plan.els.iter_mut().enumerate() {
                el.id = format!("sample-{i}");
                if el.kind == diagram::Kind::Camera {
                    if let Some(s) = next.next() {
                        el.shot = s;
                        el.label.clear();
                        el.lens = 0.0;
                    }
                }
            }
            h.project.doc_mut().diagram_replace(scene, &plan, "Sample Diagram");
            let doc = h.project.doc();
            wire::payload(&doc.diagram(scene), &doc.diagram_context(scene), &render_opts(1, Vec::new()))
        }
        "diagramfavorites" => favorites_json(h.project.doc()),
        "diagramfavoriteset" => {
            if let Some(problem) = writable(h) {
                return problem;
            }
            let slot = parts.next().and_then(|s| s.trim().parse::<usize>().ok()).unwrap_or(usize::MAX);
            let id = parts.next().unwrap_or("-").trim().to_string();
            let piece = if id == "-" { None } else { h.project.doc().diagram(scene).get(&id).cloned() };
            if id != "-" && piece.is_none() {
                return error("nothing on the plan called that");
            }
            if !h.project.doc_mut().set_diagram_favorite_from(slot, scene, piece.as_ref()) {
                return error("no such slot");
            }
            favorites_json(h.project.doc())
        }
        "diagramfavoriteat" => {
            let slot = parts.next().and_then(|s| s.trim().parse::<usize>().ok()).unwrap_or(usize::MAX);
            let n: Vec<f64> = parts.take(2).filter_map(|v| v.trim().parse::<f64>().ok()).collect();
            let (Some(fav), [x, y]) = (h.project.doc().diagram_favorites().into_iter().nth(slot).flatten(), n.as_slice()) else {
                return error("that slot is empty");
            };
            // `op`: the whole add, a group's pieces as one group; `el`, a
            // lone piece, for a shell that still reads it.
            match diagram::favorites::placed_op(&fav, *x, *y) {
                Some(op) => {
                    let mut j = Json::new();
                    j.obj().key("op").raw(&op.encode());
                    if let Some(el) = diagram::favorites::placed(&fav, *x, *y) {
                        j.key("el").raw(&el.encode());
                    }
                    j.end_obj();
                    j.finish()
                }
                None => error("that slot is empty"),
            }
        }
        "diagramsheet" => {
            let (beat, _, o) = options(parts);
            let doc = h.project.doc();
            let ask = diagram::sheet::Ask {
                screen: o.get("screen") == Some("1"),
                printed: o.get("printed").unwrap_or("").to_string(),
                beat,
                tz: o.number("tz"),
                ..Default::default()
            };
            let (sheet, plan, ctx) = diagram::sheet::of(doc, scene, &ask);
            let body = diagram::sheet::json(&sheet);
            if o.get("svg") != Some("1") {
                return body;
            }
            let frame = svg::Frame { fades: false, grid: false, scale_bar: false, media: "media/{hash}".into(), ..Default::default() };
            let picture = diagram::sheet::svg_of(&plan, &ctx, &sheet, &ask, o.number("width").unwrap_or(0.0).clamp(0.0, 8000.0), false, &frame, "s");
            let mut j = Json::new();
            j.obj().key("sheet").raw(&body).kv("svg", &picture).end_obj();
            j.finish()
        }
        "diagramsvg" => {
            let (beat, sel, o) = options(parts);
            let doc = h.project.doc();
            let frame = svg::Frame {
                width: o.number("width").unwrap_or(1000.0).clamp(200.0, 8000.0),
                grid: o.get("grid") != Some("0"),
                scale_bar: o.get("scale") != Some("0"),
                ..Default::default()
            };
            let opt = render::Options { beat, tween: 0.0, sel, paper: o.get("paper") == Some("1"), scale: 0.0, typing: String::new(), page: false };
            let picture = svg::svg(&doc.diagram(scene), &doc.diagram_context(scene), &opt, &frame, "d");
            let mut j = Json::new();
            j.obj().kv("svg", &picture).end_obj();
            j.finish()
        }
        _ => error("no such diagram command"),
    }
}

/// The nine slots: each empty, or the piece it keeps and what it is called.
fn favorites_json(doc: &shotlister_engine::Doc) -> String {
    let mut j = Json::new();
    j.obj().key("slots").arr();
    for slot in doc.diagram_favorites() {
        match slot {
            Some(fav) => {
                j.obj().kv("name", &diagram::favorites::name(&fav)).key("el").raw(&fav.encode()).end_obj();
            }
            None => {
                j.null();
            }
        }
    }
    j.end_arr().end_obj();
    j.finish()
}

#[cfg(test)]
mod tests {
    use super::super::*;

    fn open(name: &str) -> (Handle, PathBuf) {
        let dir = std::env::temp_dir().join(format!("shotlister-ffi-diagram-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let mut project = shotlister_storage::create(&dir, "Diagram", DeviceId(1)).unwrap();
        demo::seed(project.doc_mut());
        let h = Handle {
            project,
            group_by: GroupBy::Scene,
            search: String::new(),
            hide_struck: false,
            facets: Vec::new(),
            day: None,
            unscheduled_only: false,
            sequence: None,
            shoot: None,
            sort: None,
            looking: None,
            showing_old: false,
        };
        (h, dir)
    }

    fn call(h: &mut Handle, line: &str) -> shotlister_engine::json::Json {
        let out = dispatch(h, line);
        shotlister_engine::json::parse(&out).unwrap_or_else(|| panic!("not JSON: {out}"))
    }

    #[test]
    fn the_diagram_export_can_be_asked_for_one_day_and_takes_the_screens_clock() {
        // Refs 1503 and 1576.
        let (mut h, dir) = open("export-day");
        let scenes = h.project.doc().scenes_in_order();
        let wall = r#"{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#;
        for s in &scenes[..2] {
            call(&mut h, &format!("diagramedit\t{}\t{wall}", s.0));
        }
        // The first day holds the demo's shots; add one that holds none.
        let busy = h.project.doc().days_in_order()[0];
        let empty = h.project.doc_mut().create_day();
        let write = |h: &mut Handle, name: &str, option: &str| {
            let path = dir.join(name);
            let out = dispatch(h, &format!("print\tdiagram\t{}\t{option}", path.display()));
            assert!(out.contains("\"path\""), "got: {out}");
            std::fs::read_to_string(&path).unwrap()
        };
        let sheets = |html: &str| html.matches("class=\"sheet fresh-page\"").count();
        assert_eq!(sheets(&write(&mut h, "all.html", "tz=-420")), 2, "no ask is every scene with a plan");
        let day_page = write(&mut h, "busy.html", &format!("day={}\ttz=-420", busy.0));
        assert!(sheets(&day_page) >= 1 && sheets(&day_page) <= 2);
        let none = write(&mut h, "empty.html", &format!("day={}", empty.0));
        assert_eq!(sheets(&none), 0);
        assert!(none.contains("No diagrams yet"));
        let loose = write(&mut h, "loose.html", "day=unscheduled");
        assert_eq!(sheets(&loose), 0, "every demo shot is on a day");
        let both = dispatch(&mut h, &format!("print\tdiagram\t{}\tday={}\tscenes={}", dir.join("x.html").display(), busy.0, scenes[0].0));
        assert!(both.contains("not both"), "got: {both}");
        let bad = dispatch(&mut h, &format!("print\tdiagram\t{}\tday=nonsense", dir.join("y.html").display()));
        assert!(bad.contains("not a shoot day"), "got: {bad}");
    }

    #[test]
    fn a_plan_is_drawn_edited_undone_and_hit_across_the_boundary() {
        let (mut h, _dir) = open("round");
        let scene = h.project.doc().scenes_in_order()[0];
        let s = scene.0.to_string();

        let empty = call(&mut h, &format!("diagram\t{s}"));
        assert_eq!(empty.get("els").unwrap().as_array().unwrap().len(), 0);

        let op = r#"{"op":"add","els":[{"kind":"camera","x":1,"y":1,"lens":50},{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#;
        let r = call(&mut h, &format!("diagramedit\t{s}\t{op}"));
        let made: Vec<String> = r.get("made").unwrap().as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()).collect();
        assert_eq!(made.len(), 2);
        assert_eq!(r.get("diagram").unwrap().get("els").unwrap().as_array().unwrap().len(), 2);

        let hit = call(&mut h, &format!("diagramhit\t{s}\t1\t1\t0.1"));
        assert_eq!(hit.get("id").unwrap().as_str(), Some(made[0].as_str()));

        let preview = call(&mut h, &format!("diagrampreview\t{s}\t{{\"op\":\"move\",\"ids\":[\"{}\"],\"dx\":3,\"dy\":0}}", made[0]));
        assert!(preview.get("shapes").unwrap().as_array().unwrap().len() > 3);
        let still = call(&mut h, &format!("diagramhit\t{s}\t1\t1\t0.1"));
        assert_eq!(still.get("id").unwrap().as_str(), Some(made[0].as_str()), "a preview writes nothing");

        call(&mut h, "undo");
        let after = call(&mut h, &format!("diagram\t{s}"));
        assert_eq!(after.get("els").unwrap().as_array().unwrap().len(), 0, "undo takes the whole add back");

        let lib = call(&mut h, "diagramlibrary");
        assert!(lib.get("symbols").unwrap().as_array().unwrap().len() > 60);

        let bad = call(&mut h, "diagram\tnot-a-scene");
        assert!(bad.get("error").is_some());
        let bad = call(&mut h, &format!("diagramedit\t{s}\tnot json"));
        assert!(bad.get("error").is_some());

        let room = call(&mut h, &format!("diagramroom\t{s}\tloc\t"));
        assert!(room.get("made").unwrap().as_f64().unwrap() >= 4.0);
        let pic = call(&mut h, &format!("diagramsvg\t{s}\twidth=800"));
        assert!(pic.get("svg").unwrap().as_str().unwrap().starts_with("<svg"));
    }

    #[test]
    fn the_sheet_and_name_lamp_cross_the_boundary() {
        let (mut h, _dir) = open("sheet");
        let scene = h.project.doc().scenes_in_order()[0];
        let s = scene.0.to_string();
        let op = r#"{"op":"add","els":[{"kind":"light","id":"a","sym":"","mark":"chevron","x":0,"y":0},{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}"#;
        let r = call(&mut h, &format!("diagramedit\t{s}\t{op}"));
        let lamp = r.get("made").unwrap().as_array().unwrap()[0].as_str().unwrap().to_string();
        call(&mut h, &format!("diagramedit\t{s}\t{{\"op\":\"name_lamp\",\"id\":\"{lamp}\",\"name\":\"2K Blonde\"}}"));
        let sheet = call(&mut h, &format!("diagramsheet\t{s}\tscreen=1\tprinted=Oct 4, 2026"));
        assert_eq!(sheet.get("w").and_then(|w| w.as_f64()), Some(792.0));
        let items = sheet.get("items").unwrap().as_array().unwrap();
        let line = items.iter().find(|i| i.str_field("kind") == "legend").expect("a legend line");
        assert_eq!(line.str_field("name"), "2K Blonde");
        assert!(items.iter().any(|i| i.str_field("kind") == "notes"), "an empty Notes block on screen");
        let both = call(&mut h, &format!("diagramsheet\t{s}\tsvg=1\twidth=1000"));
        assert!(both.get("svg").unwrap().as_str().unwrap().starts_with("<svg class=\"dia sheet\""));
        assert!(both.get("sheet").unwrap().get("window").is_some());
        assert!(shotlister_engine::json::parse(&dispatch(&mut h, &format!("diagramsheet\tnot-a-scene"))).unwrap().get("error").is_some());
    }

    #[test]
    fn favorites_are_kept_read_and_put_down_across_the_boundary() {
        let (mut h, _dir) = open("favorites");
        let scene = h.project.doc().scenes_in_order()[0];
        let s = scene.0.to_string();
        let empty = call(&mut h, &format!("diagramfavorites\t{s}"));
        assert_eq!(empty.get("slots").unwrap().as_array().unwrap().len(), 9);
        let op = r#"{"op":"add","els":[{"kind":"light","sym":"generic-fresnel","x":1,"y":1,"label":"Key"}]}"#;
        let made = call(&mut h, &format!("diagramedit\t{s}\t{op}"));
        let id = made.get("made").unwrap().as_array().unwrap()[0].as_str().unwrap().to_string();
        let slots = call(&mut h, &format!("diagramfavoriteset\t{s}\t4\t{id}"));
        let four = &slots.get("slots").unwrap().as_array().unwrap()[4];
        assert_eq!(four.get("name").and_then(|n| n.as_str()), Some("Key"));
        let at = call(&mut h, &format!("diagramfavoriteat\t{s}\t4\t3\t-2"));
        let el = at.get("el").unwrap();
        assert_eq!((el.get("x").and_then(|v| v.as_f64()), el.get("sym").and_then(|v| v.as_str())), (Some(3.0), Some("generic-fresnel")));
        let cleared = call(&mut h, &format!("diagramfavoriteset\t{s}\t4\t-"));
        assert!(cleared.get("slots").unwrap().as_array().unwrap()[4].is_null());
        assert!(call(&mut h, &format!("diagramfavoriteat\t{s}\t4\t0\t0")).get("error").is_some());
    }

    #[test]
    fn a_camera_on_the_plan_reads_its_shots_camera_lens_and_zoom() {
        // His design, 2026-10-01: the film's camera carries his sensor; the
        // plan's camera is its shot and reads camera, lens and zoom off it.
        let (mut h, _dir) = open("cameras");
        let scene = h.project.doc().scenes_in_order()[0];
        let s = scene.0.to_string();
        let v = call(&mut h, "addunit\tA-Cam\t#D9483B");
        let unit = v.get("units").unwrap().as_array().unwrap().iter()
            .find(|u| u.get("label").and_then(|l| l.as_str()) == Some("A-Cam")).unwrap()
            .get("id").unwrap().as_str().unwrap().to_string();
        let v = call(&mut h, &format!("unit\tsensor\t{unit}\t36.70\t25.54\tAlexa Mini LF Open Gate"));
        let a = v.get("units").unwrap().as_array().unwrap().iter().find(|u| u.get("id").and_then(|i| i.as_str()) == Some(unit.as_str())).unwrap().clone();
        assert_eq!(a.get("sensor_w").and_then(|w| w.as_f64()), Some(36.70));

        let made = call(&mut h, &format!("diagramedit\t{s}\t{{\"op\":\"add\",\"new_shot\":true,\"els\":[{{\"kind\":\"camera\",\"x\":1,\"y\":1}}]}}"));
        let els = made.get("diagram").unwrap().get("els").unwrap().as_array().unwrap().clone();
        let shot = els[0].get("shot").unwrap().as_str().unwrap().to_string();
        call(&mut h, &format!("set\t{shot}\tunit\t{unit}"));
        call(&mut h, &format!("set\t{shot}\tlens\t24-70mm"));
        let v = call(&mut h, &format!("set\t{shot}\tfocal\t35"));
        assert!(v.get("error").is_none(), "{:?}", v.get("error"));

        let plan = call(&mut h, &format!("diagram\t{s}"));
        let c = plan.get("els").unwrap().as_array().unwrap()[0].clone();
        assert_eq!(c.get("cam_unit_label").and_then(|v| v.as_str()), Some("A-Cam"));
        assert_eq!(c.get("gate_name").and_then(|v| v.as_str()), Some("Alexa Mini LF Open Gate"));
        assert_eq!(c.get("focal").and_then(|v| v.as_f64()), Some(35.0));
        assert_eq!(c.get("zoom").and_then(|z| z.as_array()).map(|z| z.len()), Some(2));
        let want = 2.0 * (36.70f64 / 70.0).atan().to_degrees();
        assert!((c.get("aov").unwrap().as_f64().unwrap() - want).abs() < 0.06);

        // A focal length that is not one is refused.
        assert!(call(&mut h, &format!("set\t{shot}\tfocal\twide")).get("error").is_some());

        // The same three, from the plan (the portal's way): written to the shot.
        let cam = c.get("id").unwrap().as_str().unwrap().to_string();
        let op = format!(r#"{{"op":"camera_shot","id":"{cam}","set":{{"focal":50}}}}"#);
        let r = call(&mut h, &format!("diagramedit\t{s}\t{op}"));
        assert!(r.get("error").is_none(), "{:?}", r.get("error"));
        let plan = call(&mut h, &format!("diagram\t{s}"));
        assert_eq!(plan.get("els").unwrap().as_array().unwrap()[0].get("focal").and_then(|v| v.as_f64()), Some(50.0));
        let v = call(&mut h, "view");
        let row = v.get("groups").and_then(|g| g.as_array()).into_iter().flatten()
            .flat_map(|g| g.get("rows").and_then(|r| r.as_array()).map(|r| r.to_vec()).unwrap_or_default())
            .find(|r| r.get("shot").and_then(|x| x.as_str()) == Some(shot.as_str()));
        assert_eq!(row.and_then(|r| r.get("focal").and_then(|f| f.as_f64())), Some(50.0), "the shot list says 50");
    }
}
