//! A scene's plan as the shells receive it.
//!
//! One answer carries the elements (for the inspector and for picking), the
//! shapes to paint (`render.rs`), and how big it all is. Paths travel as flat
//! lists of numbers — `0 x y` moves, `1 x y` lines, `2 x1 y1 x2 y2 x y`
//! curves, `3` closes — because a plan is hundreds of paths and a Mac
//! decoding them sixty times a second while something is dragged cannot
//! afford a string parser.
//!
//! An ink travels as a word: empty for none, a role (`wall`), or a colour with
//! how much of it (`#D9483B/0.30`).

use super::render::{self, Context, Geom, Ink, Options, Seg, Shape};
use super::{lens, symbols, Diagram};
use crate::jsonw::Json;

fn ink(i: &Ink) -> String {
    match i {
        Ink::None => String::new(),
        Ink::Role(r) => (*r).to_string(),
        Ink::Hex(h, a) => {
            if (*a - 1.0).abs() < 1e-9 {
                h.clone()
            } else {
                format!("{h}/{a:.3}")
            }
        }
    }
}

fn r(v: f64) -> f64 {
    (v * 10_000.0).round() / 10_000.0
}

pub fn write_shape(j: &mut Json, s: &Shape) {
    j.obj();
    if !s.el.is_empty() {
        j.kv("e", &s.el);
    }
    j.kv("p", s.part);
    match &s.geom {
        Geom::Path(segs) => {
            j.kv("k", "path");
            j.key("d").arr();
            for seg in segs {
                match *seg {
                    Seg::M(x, y) => {
                        j.num(0.0).num(r(x)).num(r(y));
                    }
                    Seg::L(x, y) => {
                        j.num(1.0).num(r(x)).num(r(y));
                    }
                    Seg::C(a, b, c, d, x, y) => {
                        j.num(2.0).num(r(a)).num(r(b)).num(r(c)).num(r(d)).num(r(x)).num(r(y));
                    }
                    Seg::Z => {
                        j.num(3.0);
                    }
                }
            }
            j.end_arr();
        }
        Geom::Text { x, y, text, size, anchor, bold, rot, fixed, halo, patch, shift, under, lead } => {
            j.kv("k", "text").kn("x", r(*x)).kn("y", r(*y)).kv("tx", text).kn("sz", r(*size)).kv("an", anchor);
            j.kb("b", *bold).kn("r", r(*rot)).kb("fx", *fixed).kb("h", *halo);
            if *patch {
                j.kb("pa", true);
            }
            // The ink of every line after the first (a callout's second line
            // in grey); absent, they all take `f`.
            let rest = ink(under);
            if !rest.is_empty() {
                j.kv("f2", &rest);
                // A Name of several lines: how many lead in `f`.
                if *lead > 1 {
                    j.kn("n1", *lead as f64);
                }
            }
            if shift.0.abs() > 1e-9 || shift.1.abs() > 1e-9 {
                j.kn("nx", r(shift.0)).kn("ny", r(shift.1));
            }
        }
        Geom::Pill { x, y, text, size, ink: fill } => {
            j.kv("k", "pill").kn("x", r(*x)).kn("y", r(*y)).kv("tx", text).kn("sz", *size);
            let on = match fill {
                Ink::Hex(h, _) => render::text_on(h).to_string(),
                _ => String::new(),
            };
            j.kv("on", &on);
        }
        Geom::Badge { x, y, text, ink: fill } => {
            j.kv("k", "badge").kn("x", r(*x)).kn("y", r(*y)).kv("tx", text);
            let on = match fill {
                Ink::Hex(h, _) => render::text_on(h).to_string(),
                _ => String::new(),
            };
            j.kv("on", &on);
        }
        Geom::Image { media, x, y, w, h, rot } => {
            j.kv("k", "img").kv("m", media).kn("x", r(*x)).kn("y", r(*y)).kn("iw", r(*w)).kn("ih", r(*h)).kn("r", r(*rot));
        }
    }
    let (f, st) = (ink(&s.fill), ink(&s.stroke));
    if !f.is_empty() {
        j.kv("f", &f);
    }
    if !st.is_empty() {
        j.kv("s", &st);
        j.kn("w", r(s.line));
    }
    if !s.dash.is_empty() {
        j.kv("da", s.dash);
    }
    if (s.alpha - 1.0).abs() > 1e-9 {
        j.kn("a", r(s.alpha));
    }
    if let Some((x, y, rad)) = s.fade {
        j.key("fd").arr().num(r(x)).num(r(y)).num(r(rad)).end_arr();
    }
    j.end_obj();
}

pub fn write_shapes(j: &mut Json, shapes: &[Shape]) {
    j.arr();
    for s in shapes {
        write_shape(j, s);
    }
    j.end_arr();
}

/// Everything a shell needs to show and edit one scene's plan.
pub fn payload(d: &Diagram, ctx: &Context, opt: &Options) -> String {
    let shapes = render::render(d, ctx, opt);
    let mut j = Json::new();
    j.obj();
    j.key("els").arr();
    // Each lamp's mark on a plot, so a shell can show and change it.
    let looks = if render::plot_on(d) { super::plot::looks(d) } else { Vec::new() };
    let legend = super::plot::legend(d);
    for e in &d.els {
        let mut el = e.to_json_full();
        // Set or Plot (Ref 1498): which layer it is drawn and picked in.
        if let crate::json::Json::Object(pairs) = &mut el {
            pairs.push(("layer".into(), crate::json::Json::text(super::layer(e))));
        }
        // What a camera is working out from the film, so the inspector can
        // show it without asking again.
        if e.kind == super::Kind::Camera {
            if let crate::json::Json::Object(pairs) = &mut el {
                let o = render::camera_optics(e, ctx);
                let n = |v: f64| crate::json::Json::Number((v * 100.0).round() / 100.0);
                pairs.push(("focal".into(), crate::json::Json::Number(o.focal)));
                pairs.push(("aov".into(), crate::json::Json::Number((o.aov * 10.0).round() / 10.0)));
                // What its cone is worked out from (`render::camera_optics`),
                // so a panel shows what the cone is actually using.
                pairs.push(("cam_unit".into(), crate::json::Json::text(&o.unit)));
                pairs.push(("cam_unit_label".into(), crate::json::Json::text(&o.unit_label)));
                pairs.push(("sensor_set".into(), crate::json::Json::Bool(o.sensor_set)));
                pairs.push(("lens_text".into(), crate::json::Json::text(&o.lens)));
                if let Some((lo, hi)) = o.zoom {
                    pairs.push(("zoom".into(), crate::json::Json::Array(vec![n(lo), n(hi)])));
                }
                pairs.push(("gate".into(), crate::json::Json::text(&o.gate.id)));
                pairs.push(("gate_name".into(), crate::json::Json::text(&o.gate.name)));
                pairs.push(("gate_w".into(), n(o.gate.w)));
                pairs.push(("gate_h".into(), n(o.gate.h)));
                pairs.push(("squeeze_used".into(), n(o.squeeze)));
                pairs.push(("name".into(), crate::json::Json::text(render::camera_name(e, ctx))));
            }
        }
        if let Some(words) = render::shared_label_words(d, e) {
            if let crate::json::Json::Object(pairs) = &mut el {
                pairs.push(("shown".into(), crate::json::Json::text(&words)));
            }
        }
        // How big it is drawn, where more than its footprint (Ref 1511): a
        // pick's outline goes round what is on the paper.
        if let Some((w, h)) = render::drawn_size(e, d, opt) {
            if let crate::json::Json::Object(pairs) = &mut el {
                let n = |v: f64| crate::json::Json::Number((v * 1000.0).round() / 1000.0);
                pairs.push(("drawn".into(), crate::json::Json::Array(vec![n(w), n(h)])));
                // Outlined and sized by its mark alone (`lampscale::hugs`).
                if super::lampscale::hugs(e) {
                    pairs.push(("hug".into(), crate::json::Json::Bool(true)));
                }
            }
        }
        if let Some((_, l)) = looks.iter().find(|(id, _)| *id == e.id) {
            if let crate::json::Json::Object(pairs) = &mut el {
                let key = super::plot::look_key(l);
                // **Name and Note**: its Name — its own (2026-10-05), else
                // its unit's — its legend line, and the two lines its label
                // writes, as typed: "4× 4' Titan Tube", "Uplight on BG · ½
                // CTO". The Note is its `label`.
                let name = super::plot::lamp_name(e);
                let line = legend.iter().find(|x| x.ids.contains(&e.id)).map(|x| x.key.clone()).unwrap_or_else(|| key.clone());
                let (first, under) = render::lamp_lines(e, &name, d.settings.counts);
                pairs.retain(|(k, _)| k != "lamp_name");
                pairs.push(("look".into(), crate::json::Json::text(&key)));
                pairs.push(("legend_key".into(), crate::json::Json::text(&line)));
                pairs.push(("lamp_name".into(), crate::json::Json::text(&name)));
                pairs.push(("label_lines".into(), crate::json::Json::Array(vec![crate::json::Json::text(&first), crate::json::Json::text(&under)])));
            }
        }
        // **A frame's two lines** (2026-10-05), the way a lamp's travel: its
        // size and cloth, and its Note.
        if super::frame::is_frame(e) {
            if let crate::json::Json::Object(pairs) = &mut el {
                let (first, under) = render::frame_lines(e, d.settings.counts);
                pairs.push(("label_lines".into(), crate::json::Json::Array(vec![crate::json::Json::text(&first), crate::json::Json::text(&under)])));
            }
        }
        // A set piece's or lamp's own name, from the catalogue even when the
        // library hides our drawing behind the pack's (a scanned room's
        // `table`), so a list can say Table rather than Set Piece.
        if matches!(e.kind, super::Kind::Set | super::Kind::Light) {
            // A frame writes its own: "8×8 Medium Diffusion".
            let name = if super::frame::is_frame(e) {
                super::frame::plan_name(e)
            } else if super::symbols::is_half_round(e) {
                super::symbols::half_round_name(e)
            } else {
                super::symbols::plan_name(&e.sym)
            };
            if !name.is_empty() {
                if let crate::json::Json::Object(pairs) = &mut el {
                    pairs.push(("name".into(), crate::json::Json::text(name)));
                }
            }
        }
        j.raw(&el.encode());
    }
    j.end_arr();
    j.key("settings").raw(&{
        let mut s = d.to_json();
        if let crate::json::Json::Object(pairs) = &mut s {
            pairs.retain(|(k, _)| k == "settings");
        }
        let settings = s.get("settings").cloned().unwrap_or(crate::json::Json::Object(Vec::new()));
        let st = &d.settings;
        let mut full = match settings {
            crate::json::Json::Object(p) => p,
            _ => Vec::new(),
        };
        let mut put = |k: &str, v: crate::json::Json| {
            if !full.iter().any(|(key, _)| key == k) {
                full.push((k.to_string(), v));
            }
        };
        put("units", crate::json::Json::text(&st.units));
        put("grid", crate::json::Json::Bool(st.grid));
        put("snap", crate::json::Json::Bool(st.snap));
        put("dims", crate::json::Json::Bool(st.dims));
        put("all_lengths", crate::json::Json::Bool(st.all_lengths));
        put("sketch", crate::json::Json::Bool(st.sketch));
        put("cones", crate::json::Json::Bool(st.cones));
        put("beams", crate::json::Json::Bool(st.beams));
        put("labels", crate::json::Json::Bool(st.labels));
        put("sun_rays", crate::json::Json::Bool(st.sun_rays));
        put("style", crate::json::Json::text(&st.style));
        put("step", crate::json::Json::Number(st.step));
        // The sheet (Back to Paper, Batch 2).
        put("paper", crate::json::Json::text(&st.paper));
        put("orientation", crate::json::Json::text(&st.orientation));
        put("legend", crate::json::Json::Bool(st.legend));
        put("notes", crate::json::Json::Bool(st.notes));
        put("sheet_notes", crate::json::Json::text(&st.sheet_notes));
        put("scale_bar", crate::json::Json::Bool(st.scale_bar));
        put("fabric", crate::json::Json::Bool(st.fabric));
        crate::json::Json::Object(full).encode()
    });
    j.kv("roomFrom", &d.room_from);
    // **The sheet's legend** (Labs, 2026-10-03): every kind of lamp, its
    // mark, ink and count, in the order it first appears.
    j.key("legend").arr();
    for x in &legend {
        j.obj()
            .kv("key", &x.key)
            .kv("name", &x.name)
            .kv("mark", &x.look.mark.as_str())
            .kv("ink", x.look.ink)
            .kb("solid", x.look.solid)
            .kn("count", x.count as f64)
            .kb("named", x.named);
        j.key("ids").arr();
        for id in &x.ids {
            j.str(id);
        }
        j.end_arr();
        j.end_obj();
    }
    j.end_arr();
    j.key("legendColours").arr();
    for (role, name, named) in super::plot::colour_rows(d) {
        j.obj().kv("role", &role).kv("name", &name).kb("named", named).end_obj();
    }
    j.end_arr();
    // Where the sun is for this plan, or why it cannot be said — the panel
    // that sets it shows this.
    // With it, the day's sunrise, noon, sunset and golden hours, for the
    // panel's quick picks.
    if d.settings.sun {
        j.key("sun").obj();
        match render::sun_now(d, ctx) {
            Ok((sun, minutes)) => {
                j.kn("azimuth", r(sun.azimuth)).kn("altitude", r(sun.altitude)).kn("minutes", minutes);
                // Where its disc is, so the Mac can keep it in sight.
                if let Some((x, y)) = render::sun_spot(d, ctx) {
                    j.kn("x", r(x)).kn("y", r(y));
                }
            }
            Err(why) => {
                j.kv("why", why);
            }
        }
        if let Some(day) = render::sun_day(d, ctx) {
            j.kn("noon", day.noon.round());
            for (key, at) in [("rise", day.rise), ("set", day.set), ("goldenMorning", day.golden_morning), ("goldenEvening", day.golden_evening)] {
                if let Some(m) = at {
                    j.kn(key, m.round());
                }
            }
        }
        j.end_obj();
    }
    j.kv("sceneDate", &ctx.date);
    j.ki("lastBeat", d.last_beat() as i64);
    // The screen fits the plan and everywhere its sun can stand, so a new
    // hour never puts the sun under the bars.
    let reach = d.settings.sun.then(|| render::sun_ring(d).reach());
    let extent = match (render::extent(d, ctx), reach) {
        (Some(a), Some(s)) => Some(super::Aabb { x1: a.x1.min(s.x1), y1: a.y1.min(s.y1), x2: a.x2.max(s.x2), y2: a.y2.max(s.y2) }),
        (a, s) => a.or(s),
    };
    match extent {
        Some(b) => {
            j.key("extent").arr().num(r(b.x1)).num(r(b.y1)).num(r(b.x2)).num(r(b.y2)).end_arr();
        }
        None => {
            j.key("extent").null();
        }
    }
    j.key("shapes");
    write_shapes(&mut j, &shapes);
    j.end_obj();
    j.finish()
}

/// The library: every drawing, and every sensor a camera can be.
pub fn library() -> String {
    let mut j = Json::new();
    j.obj();
    j.key("symbols").raw(&symbols::catalog_json());
    j.key("sensors").arr();
    for (key, name, width) in lens::SENSORS {
        j.obj().kv("id", key).kv("name", name).kn("width", width).end_obj();
    }
    j.end_arr();
    // The bodies a camera can show (`symbols::camera_bodies`).
    j.key("cameras").arr();
    for (id, name) in symbols::camera_bodies() {
        j.obj().kv("id", id).kv("name", name).end_obj();
    }
    j.end_arr();
    j.kv("camera_default", symbols::DEFAULT_BODY);
    // Each library's sections, in order (`library.rs`).
    j.key("kinds").obj();
    for (lib, kinds) in [
        (super::library::LIGHT, super::library::LIGHT_KINDS),
        (super::library::GRIP, super::library::GRIP_KINDS),
        (super::library::SET, super::library::SET_KINDS),
    ] {
        j.key(lib).arr();
        for k in kinds {
            j.str(k);
        }
        j.end_arr();
    }
    j.end_obj();
    // A frame's choices — its skins with their swatches, its pipes, its
    // egg crates — so every shell offers the engine's own list.
    j.key("frames").obj();
    j.kv("default", super::frame::DEFAULT_MATERIAL);
    j.key("materials").arr();
    for (id, name, _) in super::frame::MATERIALS {
        let (fill, alt, edge) = super::frame::swatch(id);
        j.obj()
            .kv("id", id)
            .kv("name", name)
            .kv("group", super::frame::material_group(id))
            .kv("fill", fill)
            .kv("alt", alt)
            .kv("edge", edge)
            .end_obj();
    }
    j.end_arr();
    j.key("pipes").arr();
    for (id, name) in super::frame::PIPES {
        j.obj().kv("id", id).kv("name", name).end_obj();
    }
    j.end_arr();
    j.key("grids").arr();
    for g in super::frame::GRIDS {
        j.num(*g);
    }
    j.end_arr();
    j.end_obj();
    j.end_obj();
    j.finish()
}
