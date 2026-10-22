//! **A lamp's mark grows when he sizes the lamp** (his note, 2026-10-17:
//! *"any lights … actually need to size up when I scale them, instead of
//! just staying in place while the window around them gets bigger"*).
//!
//! A lamp is drawn as its mark at a fixed size on the page (`plot::MARK_PT`),
//! like a symbol on a map. Dragging its corners changed its footprint, so the
//! pick's outline grew and the mark stayed as it was. Now every resize of a
//! lamp drawn as a mark multiplies its `mark_k` by as much as the lamp grew,
//! and the mark is drawn at its page size times `mark_k` — on screen, on
//! paper, on the portal and the iPhone, which all draw with this engine and
//! all resize with the same `update` edit.
//!
//! Kept to `mark_k` rather than read off the footprint, so a plan made
//! before (or by the connector, whose lamps come at 1 m × 1 m) draws exactly
//! as it did until a lamp is sized.
//!
//! What it does not touch: a tube's length, a mat's and a hung lamp's true
//! size from above (already to scale), a string of lamps (its size is the
//! string's), and a lamp's reach, which is a setting of its own and is not
//! drawn (`render::LAMP_BEAMS`).

use super::{plot, El, Json, Kind};

/// The smallest and largest a mark is drawn against its page size.
pub const MIN: f64 = 0.4;
pub const MAX: f64 = 10.0;

/// How many times its page size a lamp's mark is drawn.
pub fn mark_scale(e: &El) -> f64 {
    if e.mark_k.is_finite() {
        e.mark_k.clamp(MIN, MAX)
    } else {
        1.0
    }
}

/// Whether a lamp's mark is a tube's or a panel's, drawn along its length.
pub fn is_bar(look: &plot::Look) -> bool {
    matches!(look.mark, plot::Mark::Bar | plot::Mark::DoubleBar)
}

/// Whether a lamp is drawn as a mark that a resize should grow: not a mat
/// or a lamp hung pointing down (drawn at their true size), not a string.
fn grows(e: &El) -> Option<bool> {
    if e.kind != Kind::Light || !plot::is_lamp(e) || !e.spread.is_empty() {
        return None;
    }
    let mark = plot::chosen(e).map(|l| l.mark).unwrap_or_else(|| plot::family(&e.sym, e.w, e.h));
    if mark == plot::Mark::Mat || (plot::points_down(e) && !matches!(mark, plot::Mark::Ring | plot::Mark::Dot)) {
        return None;
    }
    Some(matches!(mark, plot::Mark::Bar | plot::Mark::DoubleBar))
}

/// **A lamp outlined by its mark alone** (2026-10-17): one drawn as a
/// mark that is not a tube or a panel. Its footprint is not drawn, so a
/// pick's outline, its handles and a click all go round the mark — what he
/// sees — and a corner dragged sizes the mark (`mark_k`).
pub fn hugs(e: &El) -> bool {
    grows(e) == Some(false)
}

/// After an `update` of `was` into `new`: a size set on a lamp drawn as a
/// mark grows (or shrinks) the mark by as much — the larger of the two
/// sides' change, or a tube's or panel's width alone, its length being its
/// own already. A `mark_k` set in the same edit wins.
pub fn resized(was: &El, new: &mut El, set: &Json) {
    if set.get("mark_k").is_some() || (set.get("w").is_none() && set.get("h").is_none()) {
        return;
    }
    let Some(bar) = grows(new) else { return };
    let ok = |v: f64| v.is_finite() && v > 1e-6;
    if !(ok(was.w) && ok(was.h) && ok(new.w) && ok(new.h)) {
        return;
    }
    let r = if bar {
        new.w.min(new.h) / was.w.min(was.h)
    } else {
        (new.w / was.w).max(new.h / was.h)
    };
    if (r - 1.0).abs() < 1e-9 {
        return;
    }
    new.mark_k = (mark_scale(was) * r).clamp(MIN, MAX);
}

#[cfg(test)]
mod tests {
    use super::super::render::{self, Context, Geom, Options};
    use super::super::*;
    use crate::json;

    fn edit(d: &mut Diagram, text: &str) {
        apply(d, &json::parse(text).unwrap()).unwrap();
    }

    fn plan(els: &str) -> Diagram {
        let mut d = Diagram::default();
        edit(&mut d, &format!(r#"{{"op":"add","els":{els}}}"#));
        d
    }

    /// Across and down of what is drawn for `id`'s mark (its paths only,
    /// not its name), in metres.
    fn mark_box(d: &Diagram, id: &str, opt: &Options) -> (f64, f64) {
        let shapes: Vec<_> = render::render(d, &Context::default(), opt)
            .into_iter()
            .filter(|s| s.el == id && s.part == "body" && matches!(s.geom, Geom::Path(_)))
            .collect();
        let b = render::bounds(&shapes).expect("the lamp draws a mark");
        (b.x2 - b.x1, b.y2 - b.y1)
    }

    fn lamp(id: &str, mark: &str, w: f64, h: f64, x: f64) -> String {
        format!(r#"{{"kind":"light","id":"{id}","sym":"","x":{x},"y":0,"rot":0,"w":{w},"h":{h},"mark":"{mark}","mark_fill":"open"}}"#)
    }

    /// Dragged by a corner to `w` × `h`, as the Mac, the portal and the
    /// iPhone all resize: one `update` of its size.
    fn resize(d: &mut Diagram, id: &str, w: f64, h: f64) {
        edit(d, &format!(r#"{{"op":"update","ids":["{id}"],"set":{{"w":{w},"h":{h}}}}}"#));
    }

    #[test]
    fn a_lamp_sized_up_draws_its_mark_bigger() {
        let mut d = plan(&format!("[{},{}]", lamp("a", "chevron", 0.3, 0.3, 0.0), lamp("b", "chevron", 0.3, 0.3, 5.0)));
        let opt = Options::default();
        let before = mark_box(&d, "b", &opt);
        resize(&mut d, "b", 0.9, 0.9);
        let (aw, ah) = mark_box(&d, "a", &opt);
        let (bw, bh) = mark_box(&d, "b", &opt);
        assert!((bw / aw - 3.0).abs() < 0.05 && (bh / ah - 3.0).abs() < 0.05,
            "three times the size draws three times the mark: {before:?} → {bw}×{bh}");
        // The pick's outline (what is drawn) goes with it.
        let db = render::drawn_size(d.get("b").unwrap(), &d, &opt).unwrap();
        assert!(db.0 >= bw - 1e-9 && db.1 >= bh - 1e-9, "{db:?} round {bw}×{bh}");
        // Kept in the film, and an undo-able edit like any other.
        let back = Diagram::parse(&d.encode());
        assert!((back.get("b").unwrap().mark_k - 3.0).abs() < 1e-9);
        // Sized again from there, it goes on from there.
        resize(&mut d, "b", 0.45, 0.45);
        assert!((d.get("b").unwrap().mark_k - 1.5).abs() < 1e-9);
    }

    #[test]
    fn every_kind_of_mark_grows() {
        for mark in ["wedge", "ring", "dot", "square", "letter-B"] {
            let mut d = plan(&format!("[{},{}]", lamp("a", mark, 0.3, 0.3, 0.0), lamp("b", mark, 0.3, 0.3, 5.0)));
            resize(&mut d, "b", 0.6, 0.6);
            let opt = Options::default();
            let (aw, _) = mark_box(&d, "a", &opt);
            let (bw, _) = mark_box(&d, "b", &opt);
            assert!((bw / aw - 2.0).abs() < 0.08, "{mark}: {aw} → {bw}");
        }
    }

    #[test]
    fn a_lamp_sized_down_draws_smaller_but_never_vanishes() {
        let mut d = plan(&format!("[{},{}]", lamp("a", "chevron", 0.3, 0.3, 0.0), lamp("s", "chevron", 0.3, 0.3, 5.0)));
        resize(&mut d, "s", 0.15, 0.15);
        let opt = Options::default();
        let (aw, _) = mark_box(&d, "a", &opt);
        let (sw, _) = mark_box(&d, "s", &opt);
        assert!((sw / aw - 0.5).abs() < 0.05, "{aw} → {sw}");
        resize(&mut d, "s", 0.01, 0.01);
        let (tw, _) = mark_box(&d, "s", &opt);
        assert!(tw / aw > super::MIN - 0.05, "{tw}");
    }

    #[test]
    fn a_plan_drawn_before_draws_as_it_always_has() {
        // A connector lamp at 1 m × 1 m, and one sized before this: drawn
        // at the page size until it is sized again.
        let d = plan(&format!("[{},{}]", lamp("a", "chevron", 0.3, 0.3, 0.0), lamp("big", "chevron", 1.0, 1.0, 5.0)));
        let opt = Options::default();
        let (aw, _) = mark_box(&d, "a", &opt);
        let (bw, _) = mark_box(&d, "big", &opt);
        assert!((aw - bw).abs() < 1e-9, "{aw} {bw}");
        assert!(!d.encode().contains("mark_k"), "nothing new written until sized");
        // Its pick goes round the mark it shows, not a metre of nothing.
        let m = render::mark_m(&opt);
        let (w, h) = render::drawn_size(d.get("big").unwrap(), &d, &opt).unwrap();
        assert!((w - m * 1.1).abs() < 1e-9 && (h - m * 1.1).abs() < 1e-9, "{w}×{h}");
        assert!(super::hugs(d.get("big").unwrap()));
        let wire = super::super::wire::payload(&d, &Context::default(), &opt);
        assert!(wire.contains(r#""hug":true"#), "the shells are told");
    }

    #[test]
    fn printed_the_mark_grows_the_same() {
        let mut d = plan(&format!("[{},{}]", lamp("a", "chevron", 0.3, 0.3, 0.0), lamp("b", "chevron", 0.3, 0.3, 5.0)));
        resize(&mut d, "b", 0.6, 0.6);
        let opt = Options { page: true, paper: true, scale: 30.0, ..Default::default() };
        let (aw, _) = mark_box(&d, "a", &opt);
        let (bw, _) = mark_box(&d, "b", &opt);
        assert!((bw / aw - 2.0).abs() < 0.05, "{aw} → {bw}");
    }

    #[test]
    fn a_tube_keeps_its_length_and_grows_in_width() {
        let mut d = plan(&format!("[{},{}]", lamp("a", "bar", 0.3, 1.2, 0.0), lamp("b", "bar", 0.3, 1.2, 5.0)));
        resize(&mut d, "b", 0.6, 1.2);
        let opt = Options::default();
        let (aw, ah) = mark_box(&d, "a", &opt);
        let (bw, bh) = mark_box(&d, "b", &opt);
        assert!((ah - 1.2).abs() < 0.05 && (bh - 1.2).abs() < 0.05, "its length is its own: {ah} {bh}");
        assert!((bw / aw - 2.0).abs() < 0.1, "twice as wide: {aw} → {bw}");
        // Made longer only, it is longer, no thicker.
        let mut d = plan(&format!("[{}]", lamp("c", "bar", 0.3, 1.2, 0.0)));
        resize(&mut d, "c", 0.3, 2.4);
        assert_eq!(d.get("c").unwrap().mark_k, 1.0);
    }

    #[test]
    fn a_mat_and_a_string_keep_their_true_size() {
        let mut d = plan(&format!("[{}]", lamp("m", "mat", 1.2, 0.6, 0.0)));
        resize(&mut d, "m", 2.4, 1.2);
        assert_eq!(d.get("m").unwrap().mark_k, 1.0, "a mat is to scale already");
        let mut d = plan(r#"[{"kind":"light","id":"s","sym":"","x":0,"y":0,"w":0.3,"h":3,"spread":"line","count":6,"mark":"chevron"}]"#);
        resize(&mut d, "s", 0.3, 6.0);
        assert_eq!(d.get("s").unwrap().mark_k, 1.0, "a string's size is the string's");
    }
}
