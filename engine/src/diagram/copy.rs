//! **A plan, or some of it, carried onto another plan** — Copy From, Copy
//! To, and Send to Scene (his ask, 2026-10-01: *"lets do copying properly"*).
//!
//! What the receiving plan already holds is either **replaced** — the whole
//! plan comes across, its settings too — or **added to**, the copies landing
//! exactly where they were drawn, on top. Either way:
//!
//! - every camera comes loose from its shot, because the other scene's shots
//!   are not this one's;
//! - what one copied piece points at — an aim, a rig, an arrow's pinned end —
//!   follows to that piece's copy, and lets go of anything left behind;
//! - a group stays a group, under a name of its own where the plan it lands
//!   in already uses that one.

use super::{rigging, Diagram, El};

/// What happens to what the receiving plan already holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Everything on it goes; the copied plan, settings and all, takes its
    /// place. Where it was looking stays.
    Replace,
    /// It all stays; the copies go on top, where they were drawn.
    Add,
}

impl Mode {
    pub fn parse(text: &str) -> Option<Mode> {
        match text.trim() {
            "" | "replace" => Some(Mode::Replace),
            "add" => Some(Mode::Add),
            _ => None,
        }
    }
}

/// The pieces a copy of `ids` takes: their groups whole, and whatever rides
/// them (a lamp on a stand). Empty `ids` is the whole plan.
pub fn picked(source: &Diagram, ids: &[String]) -> Vec<String> {
    if ids.is_empty() {
        return source.els.iter().map(|e| e.id.clone()).collect();
    }
    let ids: Vec<String> = ids.iter().filter(|id| source.get(id).is_some()).cloned().collect();
    rigging::with_riders(source, &source.with_groups(&ids))
}

/// `into` with `source`'s pieces `ids` (all of them when empty) copied onto
/// it. New pieces carry temporary ids (`copy-N`) for the store to swap for
/// real ones; they come back in the order they were added.
pub fn copied(source: &Diagram, ids: &[String], into: &Diagram, mode: Mode) -> (Diagram, Vec<String>) {
    let take = picked(source, ids);
    let whole = take.len() == source.els.len();
    let mut out = match mode {
        Mode::Replace => {
            let mut d = Diagram { els: Vec::new(), ..into.clone() };
            if whole {
                d.settings = source.settings.clone();
                d.room_from = source.room_from.clone();
            }
            d
        }
        Mode::Add => into.clone(),
    };

    // Temporary ids no piece on either plan has.
    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut n = 0;
    let mut fresh = |out: &Diagram| loop {
        n += 1;
        let id = format!("copy-{n}");
        if out.get(&id).is_none() && source.get(&id).is_none() {
            return id;
        }
    };
    let copies: Vec<El> = source.els.iter().filter(|e| take.contains(&e.id)).cloned().collect();
    for e in &copies {
        pairs.push((e.id.clone(), fresh(&out)));
    }
    let follow = |id: &str| pairs.iter().find(|(old, _)| old == id).map(|(_, new)| new.clone());

    // A group name the receiving plan already uses gets one of its own.
    let mut regroup: Vec<(String, String)> = Vec::new();
    let mut made = Vec::new();
    for mut el in copies {
        el.id = follow(&el.id).expect("paired above");
        el.shot.clear();
        // An aim at something not copied lets go: this plan does not have it.
        el.aim = follow(&el.aim).unwrap_or_default();
        el.rig_on = follow(&el.rig_on).unwrap_or_default();
        for pin in [&mut el.start_on, &mut el.end_on] {
            *pin = follow(pin).unwrap_or_default();
        }
        if !el.group.is_empty() {
            el.group = match regroup.iter().find(|(old, _)| *old == el.group) {
                Some((_, new)) => new.clone(),
                None => {
                    let taken = |g: &str| out.els.iter().any(|e| e.group == g);
                    let mut new = el.group.clone();
                    let mut k = 1;
                    while taken(&new) {
                        k += 1;
                        new = format!("{}-{k}", el.group);
                    }
                    regroup.push((el.group.clone(), new.clone()));
                    new
                }
            };
        }
        made.push(el.id.clone());
        out.els.push(el);
    }
    (out, made)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::diagram::Kind;

    fn el(kind: Kind, id: &str) -> El {
        let mut e = El::new(kind, id);
        e.x = 1.0;
        e.y = 2.0;
        e
    }

    fn source() -> Diagram {
        let mut d = Diagram::default();
        let mut cam = el(Kind::Camera, "cam");
        cam.shot = "123".into();
        cam.aim = "bob".into();
        d.els.push(cam);
        d.els.push(el(Kind::Cast, "bob"));
        let mut stand = el(Kind::Set, "stand");
        stand.group = "rig".into();
        let mut lamp = el(Kind::Light, "lamp");
        lamp.rig_on = "stand".into();
        let mut flag = el(Kind::Set, "flag");
        flag.group = "rig".into();
        d.els.push(stand);
        d.els.push(lamp);
        d.els.push(flag);
        d.settings.grid = false;
        d
    }

    #[test]
    fn replace_takes_everything_and_the_settings() {
        let mut into = Diagram::default();
        into.els.push(el(Kind::Wall, "old"));
        into.view = Some((1.0, 2.0, 3.0));
        let (out, made) = copied(&source(), &[], &into, Mode::Replace);
        assert_eq!(made.len(), 5);
        assert!(out.get("old").is_none());
        assert!(!out.settings.grid);
        assert_eq!(out.view, Some((1.0, 2.0, 3.0)), "where it was looking stays");
        let cam = out.els.iter().find(|e| e.kind == Kind::Camera).unwrap();
        assert!(cam.shot.is_empty(), "loose from its shot");
        let bob = out.els.iter().find(|e| e.kind == Kind::Cast).unwrap();
        assert_eq!(cam.aim, bob.id, "aim follows to the copy");
    }

    #[test]
    fn add_keeps_what_is_there_and_lands_where_drawn() {
        let mut into = Diagram::default();
        into.els.push(el(Kind::Wall, "old"));
        let mut theirs = el(Kind::Set, "theirs");
        theirs.group = "rig".into();
        into.els.push(theirs);
        into.settings.grid = true;
        let (out, made) = copied(&source(), &[], &into, Mode::Add);
        assert_eq!(out.els.len(), 7);
        assert!(out.get("old").is_some());
        assert!(out.settings.grid, "its own settings stay");
        for id in &made {
            let e = out.get(id).unwrap();
            assert_eq!((e.x, e.y), (1.0, 2.0));
        }
        // The copied group does not merge into the one already there.
        let copied_groups: Vec<&str> = made.iter().filter_map(|id| out.get(id)).map(|e| e.group.as_str()).filter(|g| !g.is_empty()).collect();
        assert_eq!(copied_groups, vec!["rig-2", "rig-2"]);
    }

    #[test]
    fn some_pieces_bring_their_group_and_riders_and_let_go_of_the_rest() {
        let (out, made) = copied(&source(), &["stand".to_string(), "cam".to_string()], &Diagram::default(), Mode::Add);
        // The stand brings its group (the flag) and its lamp.
        assert_eq!(made.len(), 4);
        let lamp = out.els.iter().find(|e| e.kind == Kind::Light).unwrap();
        let stand = out.els.iter().find(|e| e.kind == Kind::Set && e.group == "rig" && e.rig_on.is_empty() && out.els.iter().any(|l| l.rig_on == e.id)).unwrap();
        assert_eq!(lamp.rig_on, stand.id);
        // The camera's person was not copied: it lets go of its aim.
        let cam = out.els.iter().find(|e| e.kind == Kind::Camera).unwrap();
        assert!(cam.aim.is_empty());
    }

    #[test]
    fn unknown_ids_copy_nothing() {
        let (out, made) = copied(&source(), &["nope".to_string()], &Diagram::default(), Mode::Add);
        assert!(made.is_empty());
        assert!(out.els.is_empty());
    }
}
