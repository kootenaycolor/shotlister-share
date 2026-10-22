//! The diagram as an SVG picture — how the portal and paper draw it.
//!
//! The same shapes the Mac paints (`render.rs`), written out at a given width.
//! Colours are CSS variables (`--d-wall`, `--d-cast`…) so the page around it
//! decides the palette: the portal's dark, paper's white. A light-paper palette
//! is built in, so the picture reads on its own too.
//!
//! Each shape carries `data-el`, so a page can tell which camera was tapped.

use super::render::{self, Context, Geom, Ink, Options, Seg, Shape};
use super::{length_text, Aabb, Diagram};
use std::fmt::Write;

pub struct Frame {
    /// The picture's width in pixels; its height follows the plan.
    pub width: f64,
    /// Blank room round the plan, in pixels.
    pub margin: f64,
    pub grid: bool,
    pub scale_bar: bool,
    /// How a picture element's file is reached: `{hash}` is replaced.
    pub media: String,
    /// Force a region rather than fitting the whole plan — as shown, turned
    /// so north is up.
    pub area: Option<Aabb>,
    pub max_scale: f64,
    /// Soft radial fades on cones and beams. Off for paper: the Mac's PDF
    /// maker drops a fade's transparency and prints the cone solid.
    pub fades: bool,
    /// The tallest the picture may be, in pixels, when a page has only so much
    /// room for it.
    pub max_height: Option<f64>,
    /// A picture's address by its media name, when there is no template —
    /// paper, where every picture travels inside the page.
    pub hrefs: Vec<(String, String)>,
    /// Where a Film Set Objects picture is fetched from (`{id}` replaced)
    /// when the build does not carry the pack — the portal. Empty: the
    /// pictures travel inside the page.
    pub art: String,
    /// **On the sheet** (the portal's page, as the Mac draws it): the plan
    /// lies on a page drawn under it, so it has no paper of its own, and
    /// its dots stand only inside the sheet's window — this box, as shown,
    /// metres.
    pub window: Option<Aabb>,
}

impl Default for Frame {
    fn default() -> Frame {
        Frame { width: 1000.0, margin: 36.0, grid: true, scale_bar: true, media: String::new(), area: None, max_scale: 90.0, fades: true, max_height: None, hrefs: Vec::new(), art: String::new(), window: None }
    }
}

/// Every role on a dark page — the portal's own (`.planpic` in `hub.css`),
/// for a plan printed dark.
pub const DARK: &[(&str, &str)] = &[
    ("paper", "#141414"),
    ("grid", "#1B1B1B"),
    ("grid5", "#232323"),
    ("wall", "#4B5157"),
    ("set", "#1E1E1E"),
    ("setline", "#7C848B"),
    ("setsoft", "#191919"),
    ("setink", "#5E656B"),
    ("glass", "#1F2A33"),
    ("rug", "#221F1B"),
    ("screen", "#0B0B0B"),
    ("vehicle", "#26292D"),
    ("tyre", "#0B0B0B"),
    ("plant", "#4E7A4B"),
    ("trunk", "#6B5139"),
    ("grip", "#B8BDC2"),
    ("silk", "#3A3C40"),
    ("light", "#E9AE3F"),
    ("lightface", "#5E4B22"),
    ("lightline", "#F2C66B"),
    ("fixture", "#2B2F33"),
    ("fixtureline", "#A3ACB4"),
    ("muslin", "#3B352A"),
    ("wood", "#4A4034"),
    ("lightink", "#E9AE3F"),
    ("added", "#F27A72"),
    // Three inks (Back to Paper): grip in the film lights' red, the
    // location's own lamps in the walls' grey. Practicals amber (his calls,
    // 2026-10-05: "yellow", then "more amber"), their words the same on the
    // dark.
    ("practical", "#F5A623"),
    ("practicalword", "#F5A623"),
    ("plan", "#8C949A"),
    ("prop", "#5E666C"),
    ("blue", "#7FA2F0"),
    ("gripink", "#F27A72"),
    ("existing", "#8C949A"),
    ("camink", "#7FA2F0"),
    ("cast", "#7DA4FF"),
    ("cam", "#F2F2F2"),
    ("cone", "#F2F2F2"),
    ("tag", "#1B1B1B"),
    ("tagline", "rgba(255,255,255,.18)"),
    ("ink", "#F2F2F2"),
    ("ink2", "#8A8A8A"),
    ("dim", "#7C848B"),
    ("track", "#8A8A8A"),
    ("road", "#2A2C2F"),
    ("roadline", "#4A4F55"),
    ("marking", "#C9CDD2"),
    ("walk", "#202224"),
    ("zone", "#9D90F0"),
    ("zonefill", "#9D90F0"),
    ("cable", "#E07A73"),
    ("note", "#3F3A22"),
    ("noteline", "#7A6C34"),
    ("sun", "#F2B33D"),
    ("sunink", "#F2C66B"),
];

/// Every role, with its colour on white paper — the Film Set Objects
/// pack's own greys, charcoal, wood and green (2026-09-27), so what we draw
/// sits beside the pack's pictures as one set. The paper is a neutral off-white so
/// it does not call attention to itself (his words, 2026-09-27: no warmth).
pub const PAPER: &[(&str, &str)] = &[
    ("paper", "#F2F2F2"),
    ("grid", "#E6E6E6"),
    ("grid5", "#DBDBDB"),
    ("wall", "#48494A"),
    ("set", "#BFBFBF"),
    ("setline", "#444444"),
    ("setsoft", "#E2E2E1"),
    ("setink", "#8F8F8F"),
    ("glass", "#E2F2F7"),
    ("rug", "#D4CDC6"),
    ("screen", "#333333"),
    ("vehicle", "#7C7C7C"),
    ("tyre", "#333333"),
    ("plant", "#D1E0C2"),
    ("trunk", "#AC8D77"),
    ("grip", "#444444"),
    ("silk", "#F1F1F1"),
    ("light", "#F0B63F"),
    ("lightface", "#FFF3D6"),
    ("lightline", "#9A6A10"),
    ("fixture", "#BFBFBF"),
    ("fixtureline", "#444444"),
    ("muslin", "#EFE6D2"),
    ("wood", "#AC8D77"),
    ("lightink", "#8A5A06"),
    ("added", "#B42318"),
    // Three inks (Back to Paper): grip in the film lights' red, the
    // location's own lamps in the walls' grey. Practicals amber (his calls,
    // 2026-10-05: "yellow", then "more amber"): an amber that holds on
    // white, their words a deeper one so they read.
    ("practical", "#E08A00"),
    ("practicalword", "#A35E00"),
    ("plan", "#7E8186"),
    ("prop", "#A2A5AA"),
    ("blue", "#2F5DB8"),
    ("gripink", "#B42318"),
    ("existing", "#7E8186"),
    ("camink", "#2F5DB8"),
    ("cast", "#3E66C0"),
    ("cam", "#333333"),
    ("cone", "#1B1B1E"),
    ("tag", "#FFFFFF"),
    ("tagline", "#C9CDD1"),
    ("ink", "#1B1B1E"),
    ("ink2", "#5A5A61"),
    ("dim", "#5B6770"),
    ("track", "#656565"),
    ("road", "#D4D4D4"),
    ("roadline", "#A8A8A8"),
    ("marking", "#FFFFFF"),
    ("walk", "#EDEDED"),
    ("zone", "#6354C6"),
    ("zonefill", "#6354C6"),
    ("cable", "#A74643"),
    ("sun", "#F2A93B"),
    ("sunink", "#8A5A06"),
    ("note", "#FFF4C2"),
    ("noteline", "#E0C860"),
];

fn ink(i: &Ink) -> (String, f64) {
    match i {
        Ink::None => ("none".into(), 1.0),
        Ink::Role(r) => (format!("var(--d-{r})"), 1.0),
        Ink::Hex(h, a) => (h.clone(), *a),
    }
}

/// A colour, as a name a filter can carry.
fn tint_id(hex: &str) -> String {
    hex.chars().filter(|c| c.is_ascii_alphanumeric()).collect()
}

pub fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// The picture. `id` makes gradient names unique when several share a page.
pub fn svg(d: &Diagram, ctx: &Context, opt: &Options, frame: &Frame, id: &str) -> String {
    // Drawn the way it is shown: turned so north is straight up.
    let turn = render::view_turn(d);
    let extent = frame.area.or_else(|| render::extent_in(d, ctx, frame.width - 2.0 * frame.margin)).unwrap_or(Aabb { x1: 0.0, y1: 0.0, x2: 6.0, y2: 4.0 });
    // Room for words that hang off the edge.
    let pad = 0.6;
    let (ex1, ey1, ex2, ey2) = (extent.x1 - pad, extent.y1 - pad, extent.x2 + pad, extent.y2 + pad);
    let span = (ex2 - ex1).max(1.0);
    let mut scale = ((frame.width - 2.0 * frame.margin) / span).min(frame.max_scale);
    if let Some(tallest) = frame.max_height {
        let fit = (tallest - 2.0 * frame.margin) / (ey2 - ey1).max(1.0);
        scale = scale.min(fit.max(1.0));
    }
    let height = ((ey2 - ey1).max(1.0) * scale + 2.0 * frame.margin).round();
    let ox = frame.margin + ((frame.width - 2.0 * frame.margin) - span * scale) / 2.0 - ex1 * scale;
    let oy = frame.margin - ey1 * scale;
    let px = |x: f64| ox + x * scale;
    let py = |y: f64| oy + y * scale;
    // Drawn once the scale is known, so names are kept apart at the size
    // they will print (`render::place_names`). Lettered as the sheet
    // letters it (`page`), the scale is the sheet's own and is kept.
    let opt = if opt.page && opt.scale > 0.0 { opt.clone() } else { Options { scale, ..opt.clone() } };
    let mut shapes = render::render(d, ctx, &opt);
    render::turn_shapes(&mut shapes, turn);

    let mut o = String::new();
    let _ = write!(
        o,
        r#"<svg class="dia" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" data-scale="{s:.4}" data-ox="{ox:.2}" data-oy="{oy:.2}">"#,
        w = frame.width,
        h = height,
        s = scale,
    );
    style(&mut o);
    if frame.window.is_none() {
        let _ = write!(o, r#"<rect width="{}" height="{}" style="fill:var(--d-paper)"/>"#, frame.width, height);
    }

    if frame.grid && d.settings.grid {
        // **Faint dots, not graph paper** (Back to Paper, 2026-10-04): a dot
        // at every crossing of the grid, one grid step apart. The grid
        // belongs to the plan, so it turns with it about the plan's origin,
        // far enough each way to fill the picture.
        let step = d.settings.step.max(0.05);
        let (mut x1, mut y1, mut x2, mut y2) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
        for (cx, cy) in [(0.0, 0.0), (frame.width, 0.0), (frame.width, height), (0.0, height)] {
            let (wx, wy) = render::turn_point((cx - ox) / scale, (cy - oy) / scale, -turn);
            x1 = x1.min(wx);
            y1 = y1.min(wy);
            x2 = x2.max(wx);
            y2 = y2.max(wy);
        }
        let (gx1, gy1) = ((x1 / step).floor() * step, (y1 / step).floor() * step);
        let (gx2, gy2) = ((x2 / step).ceil() * step, (y2 / step).ceil() * step);
        let cell = step * scale;
        let _ = write!(
            o,
            r#"<defs><pattern id="{id}-dots" x="{:.2}" y="{:.2}" width="{cell:.3}" height="{cell:.3}" patternUnits="userSpaceOnUse"><circle cx="{h:.3}" cy="{h:.3}" r="1" style="fill:var(--d-grid5)"/></pattern></defs>"#,
            ox - cell / 2.0,
            oy - cell / 2.0,
            h = cell / 2.0,
        );
        let turned = if turn.abs() > 1e-9 { format!(r#" transform="rotate({turn:.3} {ox:.2} {oy:.2})""#) } else { String::new() };
        // On the sheet, the dots only where the plan stands on the paper.
        if let Some(w) = frame.window {
            let _ = write!(
                o,
                r#"<defs><clipPath id="{id}-win"><rect x="{:.1}" y="{:.1}" width="{:.1}" height="{:.1}"/></clipPath></defs><g clip-path="url(#{id}-win)">"#,
                px(w.x1), py(w.y1), (w.x2 - w.x1) * scale, (w.y2 - w.y1) * scale,
            );
        }
        let _ = write!(
            o,
            r#"<rect x="{:.1}" y="{:.1}" width="{:.1}" height="{:.1}" style="fill:url(#{id}-dots)"{turned}/>"#,
            px(gx1) - cell / 2.0,
            py(gy1) - cell / 2.0,
            (gx2 - gx1) * scale + cell,
            (gy2 - gy1) * scale + cell,
        );
        if frame.window.is_some() {
            o.push_str("</g>");
        }
    }

    body(&mut o, &shapes, &px, &py, scale, frame, id);

    if frame.scale_bar && !d.settings.sketch {
        let (len_m, label) = if d.settings.units == "m" { (1.0, "1 m".to_string()) } else { (5.0 * super::FOOT, "5 ft".to_string()) };
        let len = len_m * scale;
        let (x, y) = (frame.margin * 0.6, height - frame.margin * 0.45);
        let _ = write!(
            o,
            r#"<g class="scale"><rect x="{x:.1}" y="{y:.1}" width="{len:.1}" height="5" style="fill:none;stroke:var(--d-dim)"/><rect x="{x:.1}" y="{y:.1}" width="{half:.1}" height="5" style="fill:var(--d-dim)"/><text x="{x:.1}" y="{ty:.1}" font-size="9" style="fill:var(--d-dim)">0</text><text x="{ex:.1}" y="{ty:.1}" font-size="9" text-anchor="end" style="fill:var(--d-dim)">{label}</text></g>"#,
            half = len / 2.0,
            ty = y - 4.0,
            ex = x + len,
        );
    }
    o.push_str("</svg>");
    let _ = length_text;
    o
}

/// The palette and the type every diagram picture is drawn with: each role
/// a CSS variable a page can set (`--dia-wall`…), paper's colour when it
/// does not. For an `<svg class="dia">`.
pub fn style(o: &mut String) {
    o.push_str("<style>.dia{");
    for (role, colour) in PAPER {
        let _ = write!(o, "--d-{role}:var(--dia-{role},{colour});");
    }
    // **Words in regular weight** (Back to Paper, 2026-10-04); only words
    // asked to be bold are.
    o.push_str("font-family:var(--dia-font,-apple-system,system-ui,sans-serif)}.dia text{font-weight:400}</style>");
}

/// The plan's shapes, written where `px` and `py` put a point on the plan
/// and `scale` page units make a metre — the pictures they use first,
/// once each. `svg` places the plan to fit its own picture; the sheet
/// (`sheet.rs`) places it in its window.
pub fn body(o: &mut String, shapes: &[Shape], px: &dyn Fn(f64) -> f64, py: &dyn Fn(f64) -> f64, scale: f64, frame: &Frame, id: &str) {
    // Each pack picture once, reused wherever it stands — and each colour a
    // picture wears (a character's person, `render::cast`) once, as a filter
    // that multiplies it in and keeps the picture's own shape and shading.
    let mut arts: Vec<&str> = Vec::new();
    let mut tints: Vec<String> = Vec::new();
    let mut inked = false;
    for s in shapes {
        if let Geom::Image { media, .. } = &s.geom {
            inked |= s.fill == Ink::Role(super::symbols::INKED);
            if let Some(a) = media.strip_prefix("fso:") {
                if !arts.contains(&a) {
                    arts.push(a);
                }
            }
            if let Ink::Hex(h, _) = &s.fill {
                if !tints.contains(h) {
                    tints.push(h.clone());
                }
            }
        }
    }
    if !arts.is_empty() || !tints.is_empty() {
        o.push_str("<defs>");
        // Lamps and grip in plain ink: the picture's own light and shade,
        // in greys, a touch firmer (`symbols::INKED`; the Mac's
        // `DiagramPictures.inked` does the same sums).
        if inked {
            let _ = write!(
                o,
                r#"<filter id="{id}-ink" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer><feFuncR type="linear" slope="1.25" intercept="-0.28"/><feFuncG type="linear" slope="1.25" intercept="-0.28"/><feFuncB type="linear" slope="1.25" intercept="-0.28"/></feComponentTransfer></filter>"#
            );
        }
        for h in &tints {
            let _ = write!(
                o,
                r#"<filter id="{id}-tint-{}" color-interpolation-filters="sRGB"><feFlood flood-color="{}"/><feComposite in2="SourceGraphic" operator="in"/><feBlend in2="SourceGraphic" mode="multiply"/></filter>"#,
                tint_id(h),
                esc(h),
            );
        }
        for a in &arts {
            let Some(art) = super::fso::find(a) else { continue };
            let href = if !art.png.is_empty() {
                format!("data:image/png;base64,{}", base64(art.png))
            } else if !frame.art.is_empty() {
                esc(&frame.art.replace("{id}", a.trim_start_matches("fso-")))
            } else {
                continue;
            };
            let _ = write!(o, r#"<image id="{id}-{a}" width="{}" height="{}" href="{href}"/>"#, art.px_w, art.px_h);
        }
        o.push_str("</defs>");
    }

    let mut gradients = 0usize;
    for s in shapes {
        shape(o, s, px, py, scale, frame, id, &mut gradients);
    }
}

fn path_d(segs: &[Seg], px: &dyn Fn(f64) -> f64, py: &dyn Fn(f64) -> f64) -> String {
    let mut d = String::new();
    for s in segs {
        match *s {
            Seg::M(x, y) => {
                let _ = write!(d, "M{:.1} {:.1}", px(x), py(y));
            }
            Seg::L(x, y) => {
                let _ = write!(d, "L{:.1} {:.1}", px(x), py(y));
            }
            Seg::C(a, b, c, e, x, y) => {
                let _ = write!(d, "C{:.1} {:.1} {:.1} {:.1} {:.1} {:.1}", px(a), py(b), px(c), py(e), px(x), py(y));
            }
            Seg::Z => d.push('Z'),
        }
    }
    d
}

#[allow(clippy::too_many_arguments)]
pub fn shape(o: &mut String, s: &Shape, px: &dyn Fn(f64) -> f64, py: &dyn Fn(f64) -> f64, scale: f64, frame: &Frame, id: &str, gradients: &mut usize) {
    let el = if s.el.is_empty() { String::new() } else { format!(r#" data-el="{}" data-part="{}""#, esc(&s.el), s.part) };
    let alpha = s.alpha.clamp(0.0, 1.0);
    let op = if alpha < 1.0 { format!(r#" opacity="{alpha:.2}""#) } else { String::new() };
    match &s.geom {
        Geom::Path(segs) => {
            let (mut fill, mut fa) = ink(&s.fill);
            let (stroke, sa) = ink(&s.stroke);
            let fade = if frame.fades { s.fade } else { None };
            if s.fade.is_some() && !frame.fades {
                // Flat, and fainter: a fade's average rather than its peak.
                fa *= 0.45;
            }
            if let Some((cx, cy, r)) = fade {
                if fill != "none" {
                    *gradients += 1;
                    let gid = format!("{id}g{gradients}");
                    let _ = write!(
                        o,
                        r#"<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{:.1}" cy="{:.1}" r="{:.1}"><stop offset="0" style="stop-color:{fill};stop-opacity:{fa:.2}"/><stop offset="1" style="stop-color:{fill};stop-opacity:0"/></radialGradient>"#,
                        px(cx),
                        py(cy),
                        r * scale,
                    );
                    fill = format!("url(#{gid})");
                }
            }
            let dash = match s.dash {
                "dash" => r#" stroke-dasharray="5 4""#,
                "dot" => r#" stroke-dasharray="1.5 3" stroke-linecap="round""#,
                _ => "",
            };
            let fill_op = if fade.is_none() && fa < 1.0 { format!(";fill-opacity:{fa:.2}") } else { String::new() };
            let stroke_part = if stroke == "none" || s.line <= 0.0 {
                String::new()
            } else {
                format!(";stroke:{stroke};stroke-width:{:.2};stroke-opacity:{sa:.2};stroke-linejoin:round", s.line)
            };
            let _ = write!(
                o,
                r#"<path d="{}" style="fill:{fill}{fill_op}{stroke_part}"{dash}{op}{el}/>"#,
                path_d(segs, px, py)
            );
        }
        Geom::Text { x, y, text, size, anchor, bold, rot, fixed, halo, patch, shift, under, lead } => {
            let size_px = if *fixed { *size } else { size * scale };
            if size_px < 1.0 || text.is_empty() {
                return;
            }
            // A name stepped aside to stay clear says how far, so the
            // portal's drag of it starts where it is drawn.
            let el = if shift.0.abs() > 1e-9 || shift.1.abs() > 1e-9 {
                format!(r#"{el} data-nx="{:.3}" data-ny="{:.3}""#, shift.0, shift.1)
            } else {
                el
            };
            let (fill, _) = ink(&s.fill);
            // A name's patch of paper: whatever line it lies across breaks
            // round it, on paper as on screen. `--dia-patch` keeps it light
            // when a screen dims its backdrop (2026-10-02) — measured the way the plan
            // measured it to keep names apart (`render::words_box_pt`).
            if *patch {
                let (w, h) = render::words_box_pt(text, size_px);
                let (cx, cy) = (px(*x), py(*y));
                let x0 = match *anchor {
                    "start" => cx,
                    "end" => cx - w,
                    _ => cx - w / 2.0,
                };
                let _ = write!(
                    o,
                    r#"<rect x="{:.1}" y="{:.1}" width="{:.1}" height="{:.1}" rx="2" style="fill:var(--dia-patch,var(--d-paper))"{op}{el}/>"#,
                    x0 - render::PATCH_PAD,
                    cy - h / 2.0 - render::PATCH_PAD / 2.0,
                    w + 2.0 * render::PATCH_PAD,
                    h + render::PATCH_PAD,
                );
            }
            let halo = if *halo { ";paint-order:stroke;stroke:var(--d-paper);stroke-width:3.5px;stroke-linejoin:round" } else { "" };
            let weight = if *bold { ";font-weight:600" } else { "" };
            // The lines after the first, in their own ink: a callout's
            // second line in grey.
            let rest = match under {
                Ink::None => String::new(),
                i => format!(r#" style="fill:{}""#, ink(i).0),
            };
            let (x, y) = (px(*x), py(*y));
            let lines: Vec<&str> = text.split('\n').collect();
            let _ = write!(
                o,
                r#"<text x="{x:.1}" y="{y:.1}" font-size="{size_px:.1}" text-anchor="{anchor}" dominant-baseline="central" transform="rotate({rot:.1} {x:.1} {y:.1})" style="fill:{fill}{halo}{weight}"{op}{el}>"#,
            );
            if lines.len() == 1 {
                o.push_str(&esc(text));
            } else {
                let first = -((lines.len() - 1) as f64) * 0.6;
                for (i, l) in lines.iter().enumerate() {
                    let dy = if i == 0 { first } else { 1.2 };
                    let own = if i < (*lead).max(1) { "" } else { rest.as_str() };
                    let _ = write!(o, r#"<tspan x="{x:.1}" dy="{dy:.2}em"{own}>{}</tspan>"#, esc(l));
                }
            }
            o.push_str("</text>");
        }
        Geom::Pill { x, y, text, size, ink: fill_ink } => {
            let (fill, _) = ink(fill_ink);
            let (stroke, _) = ink(&s.stroke);
            let text_ink = match fill_ink {
                Ink::Hex(h, _) => render::text_on(h).to_string(),
                _ => "var(--d-ink)".to_string(),
            };
            let w = text.chars().count() as f64 * size * 0.62 + size * 1.3;
            let h = size * 1.75;
            let (cx, cy) = (px(*x), py(*y));
            let _ = write!(
                o,
                r#"<g{el}{op}><rect x="{:.1}" y="{:.1}" width="{w:.1}" height="{h:.1}" rx="{:.1}" style="fill:{fill};stroke:{stroke};stroke-width:1"/><text x="{cx:.1}" y="{cy:.1}" font-size="{size:.1}" text-anchor="middle" dominant-baseline="central" style="fill:{text_ink}">{}</text></g>"#,
                cx - w / 2.0,
                cy - h / 2.0,
                h * 0.36,
                esc(text),
            );
        }
        Geom::Badge { x, y, text, ink: fill_ink } => {
            let (fill, _) = ink(fill_ink);
            let text_ink = match fill_ink {
                Ink::Hex(h, _) => render::text_on(h).to_string(),
                _ => "var(--d-paper)".to_string(),
            };
            let (cx, cy) = (px(*x), py(*y));
            let _ = write!(
                o,
                r#"<g{el}{op}><circle cx="{cx:.1}" cy="{cy:.1}" r="7" style="fill:{fill}"/><text x="{cx:.1}" y="{cy:.1}" font-size="8.5" text-anchor="middle" dominant-baseline="central" style="fill:{text_ink}">{}</text></g>"#,
                esc(text),
            );
        }
        Geom::Image { media, x, y, w, h, rot } if media.starts_with("fso:") => {
            let Some(art) = super::fso::find(&media[4..]) else { return };
            let (cx, cy) = (px(*x), py(*y));
            let (sx, sy) = (w * scale / art.px_w as f64, h * scale / art.px_h as f64);
            let tint = match &s.fill {
                Ink::Hex(h, _) => format!(r#" filter="url(#{id}-tint-{})""#, tint_id(h)),
                Ink::Role(r) if *r == super::symbols::INKED => format!(r#" filter="url(#{id}-ink)""#),
                _ => String::new(),
            };
            let _ = write!(
                o,
                r##"<use href="#{id}-{}" transform="translate({cx:.1} {cy:.1}) rotate({rot:.1}) scale({sx:.5} {sy:.5}) translate({} {})"{tint}{op}{el}/>"##,
                art.id,
                -(art.px_w as f64) / 2.0,
                -(art.px_h as f64) / 2.0,
            );
        }
        Geom::Image { media, x, y, w, h, rot } => {
            if media.is_empty() {
                return;
            }
            let href = if !frame.media.is_empty() {
                frame.media.replace("{hash}", media)
            } else if let Some((_, h)) = frame.hrefs.iter().find(|(m, _)| m == media) {
                h.clone()
            } else {
                return;
            };
            let (cx, cy) = (px(*x), py(*y));
            let (pw, ph) = (w * scale, h * scale);
            let _ = write!(
                o,
                r#"<image href="{}" x="{:.1}" y="{:.1}" width="{pw:.1}" height="{ph:.1}" preserveAspectRatio="none" transform="rotate({rot:.1} {cx:.1} {cy:.1})"{op}{el}/>"#,
                esc(&href),
                cx - pw / 2.0,
                cy - ph / 2.0,
            );
        }
    }
}

/// Bytes as base64, for a picture carried inside the page.
fn base64(bytes: &[u8]) -> String {
    const A: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for c in bytes.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        out.push(A[(n >> 18) as usize & 63] as char);
        out.push(A[(n >> 12) as usize & 63] as char);
        out.push(if c.len() > 1 { A[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if c.len() > 2 { A[n as usize & 63] as char } else { '=' });
    }
    out
}
