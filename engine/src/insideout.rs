//! **Inside, outside, or both.**
//!
//! A slug opens `INT.`, `EXT.`, or one of the many ways a script says the scene
//! happens in both at once: `INT./EXT.`, `INT/EXT`, `I/E`, `EXT./INT.`,
//! `INT. / EXT.`. His ruling, 2026-10-09: that is a real scene heading and it
//! has to be taken into account, not read as an interior with a strange
//! location.
//!
//! One reading of it lives here so the script import, the scene's settings, a
//! typed heading, the filter and Claude's connector all agree on what the three
//! answers are and how each is spelled.

/// Where a scene happens.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InsideOut {
    Int,
    Ext,
    /// Both — a car pulling out of a garage, a doorway, a porch. It needs the
    /// light and the rooms of both.
    Both,
}

impl InsideOut {
    /// What the scene's setting stores: `INT`, `EXT`, `INT/EXT`.
    pub fn word(self) -> &'static str {
        match self {
            InsideOut::Int => "INT",
            InsideOut::Ext => "EXT",
            InsideOut::Both => "INT/EXT",
        }
    }

    /// How a slug prints it: `INT.`, `EXT.`, `INT./EXT.`
    pub fn printed(self) -> &'static str {
        match self {
            InsideOut::Int => "INT.",
            InsideOut::Ext => "EXT.",
            InsideOut::Both => "INT./EXT.",
        }
    }

    pub fn is_inside(self) -> bool {
        matches!(self, InsideOut::Int | InsideOut::Both)
    }

    pub fn is_outside(self) -> bool {
        matches!(self, InsideOut::Ext | InsideOut::Both)
    }

    /// Read a stored or typed value, in any spelling: `INT`, `int.`, `EXT`,
    /// `INT/EXT`, `INT./EXT.`, `I/E`, `EXT./INT.`, `INTERIOR`. Nothing it does
    /// not recognise.
    pub fn read(written: &str) -> Option<InsideOut> {
        let mut inside = false;
        let mut outside = false;
        let mut any = false;
        for word in written
            .split(|c: char| !c.is_ascii_alphabetic())
            .filter(|w| !w.is_empty())
        {
            match word.to_ascii_uppercase().as_str() {
                "INT" | "INTERIOR" | "I" => inside = true,
                "EXT" | "EXTERIOR" | "EST" | "E" => outside = true,
                _ => return None,
            }
            any = true;
        }
        match (any, inside, outside) {
            (false, _, _) => None,
            (_, true, true) => Some(InsideOut::Both),
            (_, true, false) => Some(InsideOut::Int),
            _ => Some(InsideOut::Ext),
        }
    }
}

/// The value as the setting should hold it: one spelling for each answer, and
/// anything unrecognised left exactly as written.
pub fn canonical(written: &str) -> String {
    match InsideOut::read(written) {
        Some(meant) => meant.word().to_string(),
        None => written.to_string(),
    }
}

/// The value as a slug prints it — `INT./EXT.` — or what was written, in
/// capitals with one full stop, when it is none of the three.
pub fn printed(written: &str) -> String {
    match InsideOut::read(written) {
        Some(meant) => meant.printed().to_string(),
        None => format!("{}.", written.trim().trim_end_matches('.').to_uppercase()),
    }
}

/// **How a scene that is both reads on screen: `I/E`.** His ruling,
/// 2026-10-13. The setting still holds `INT/EXT` and a script still prints
/// `INT./EXT.`; this is only what a label says. Anything else is left alone.
pub fn short(written: &str) -> String {
    match InsideOut::read(written) {
        Some(InsideOut::Both) => "I/E".to_string(),
        _ => written.to_string(),
    }
}

/// A slug line as it is drawn on screen: a heading that opens with both
/// (`INT./EXT. CAR - DAY`, `EXT./INT. PORCH`) opens `I/E.` instead, and the rest
/// is as written. Every other heading is returned untouched. The stored heading
/// is never changed, so a script comes back out as it went in.
pub fn shown_heading(heading: &str) -> String {
    match split_front(heading.trim_start()) {
        Some((InsideOut::Both, rest)) => format!("I/E. {rest}").trim_end().to_string(),
        _ => heading.to_string(),
    }
}

/// Whether a scene held as `stored` answers a filter asking for `wanted`.
///
/// **A scene that happens in both answers for each.** Asking for the exteriors
/// finds the INT/EXT scenes too, because somebody has to light them outside;
/// asking for INT/EXT finds only those. Anything either side does not parse as
/// one of the three is compared as plain words.
pub fn answers(stored: &str, wanted: &str) -> bool {
    match (InsideOut::read(stored), InsideOut::read(wanted)) {
        (Some(have), Some(want)) => match want {
            InsideOut::Int => have.is_inside(),
            InsideOut::Ext => have.is_outside(),
            InsideOut::Both => have == InsideOut::Both,
        },
        _ => stored.trim().eq_ignore_ascii_case(wanted.trim()),
    }
}

/// Split the front of a slug line off: which of the three it opens with, and
/// everything after it. `None` when the line does not open with one.
///
/// Accepts `INT.`, `EXT.`, `EST.`, bare `INT`/`EXT` followed by a space, and
/// the both-ways forms in either order with `/`, `-` or `&` between and a full
/// stop after either — `INT./EXT.`, `INT/EXT`, `I/E.`, `EXT./INT.`,
/// `INT. / EXT.`. A single `I` or `E` only counts as one half of a pair, so a
/// line that begins "I WANT" is not a slug, and `INTERIOR MONOLOGUE` is not
/// one either, since `INTERIOR` is not one of the words a slug opens with.
pub fn split_front(line: &str) -> Option<(InsideOut, String)> {
    let bytes = line.as_bytes();
    let mut at = 0;
    let mut inside = false;
    let mut outside = false;
    let mut words = 0;
    let mut single_only = true;
    let dotted;

    loop {
        let (word, next) = word_at(line, at)?;
        match word.as_str() {
            "INT" => {
                inside = true;
                single_only = false;
            }
            "EXT" | "EST" => {
                outside = true;
                single_only = false;
            }
            "I" => inside = true,
            "E" => outside = true,
            _ => return None,
        }
        words += 1;
        at = next;
        let mut stopped = false;
        if at < bytes.len() && bytes[at] == b'.' {
            at += 1;
            stopped = true;
        }

        // Another half, if a `/`, `-` or `&` leads to one. If what follows the
        // separator is not a half, it is the start of the location and the
        // separator stays where it is.
        let mut look = at;
        while look < bytes.len() && bytes[look] == b' ' {
            look += 1;
        }
        let Some(&sep) = bytes.get(look) else {
            dotted = stopped;
            break;
        };
        if !matches!(sep, b'/' | b'-' | b'&') {
            dotted = stopped;
            break;
        }
        look += 1;
        while look < bytes.len() && bytes[look] == b' ' {
            look += 1;
        }
        match word_at(line, look) {
            Some((w, _)) if matches!(w.as_str(), "INT" | "EXT" | "EST" | "I" | "E") => at = look,
            _ => {
                dotted = stopped;
                break;
            }
        }
    }

    if single_only && words < 2 {
        return None;
    }
    // A bare `INT` or `EXT` needs a space after it, so a longer word is not
    // mistaken for it. A full stop already ended the word.
    if !dotted && at < bytes.len() && !bytes[at].is_ascii_whitespace() {
        return None;
    }
    let meant = match (inside, outside) {
        (true, true) => InsideOut::Both,
        (true, false) => InsideOut::Int,
        _ => InsideOut::Ext,
    };
    Some((meant, line[at..].trim().to_string()))
}

/// The run of letters at `from`, in capitals, and where it ends.
fn word_at(line: &str, from: usize) -> Option<(String, usize)> {
    let bytes = line.as_bytes();
    let mut end = from;
    while end < bytes.len() && bytes[end].is_ascii_alphabetic() {
        end += 1;
    }
    if end == from {
        return None;
    }
    Some((line[from..end].to_ascii_uppercase(), end))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn front(line: &str) -> Option<(&'static str, String)> {
        split_front(line).map(|(m, rest)| (m.word(), rest))
    }

    #[test]
    fn every_way_a_script_writes_both() {
        for line in [
            "INT./EXT. CAR - DAY",
            "INT/EXT. CAR - DAY",
            "INT/EXT CAR - DAY",
            "I/E. CAR - DAY",
            "I/E CAR - DAY",
            "i/e car - day",
            "EXT./INT. CAR - DAY",
            "EXT/INT CAR - DAY",
            "INT. / EXT. CAR - DAY",
            "INT. - EXT. CAR - DAY",
            "INT & EXT CAR - DAY",
            "I./E. CAR - DAY",
        ] {
            let (meant, rest) = front(line).unwrap_or_else(|| panic!("{line} should read"));
            assert_eq!(meant, "INT/EXT", "{line}");
            assert!(rest.eq_ignore_ascii_case("CAR - DAY"), "{line} left {rest:?}");
        }
    }

    #[test]
    fn the_plain_two_still_read_and_the_look_alikes_do_not() {
        assert_eq!(front("INT. KITCHEN - DAY"), Some(("INT", "KITCHEN - DAY".into())));
        assert_eq!(front("EXT. YARD - NIGHT"), Some(("EXT", "YARD - NIGHT".into())));
        assert_eq!(front("EXT YARD - NIGHT"), Some(("EXT", "YARD - NIGHT".into())));
        assert_eq!(front("INT.KITCHEN - DAY"), Some(("INT", "KITCHEN - DAY".into())));
        assert_eq!(front("EST. HOUSE - DAWN"), Some(("EXT", "HOUSE - DAWN".into())));
        assert_eq!(front("INTERIOR MONOLOGUE"), None);
        assert_eq!(front("INTENSE"), None);
        assert_eq!(front("EXTRA RUNS IN"), None);
        assert_eq!(front("I WANT COFFEE"), None);
        assert_eq!(front("E. HOUSE"), None);
        assert_eq!(front("INT/EXTRA"), None);
    }

    #[test]
    fn a_dash_before_the_place_is_not_a_second_half() {
        assert_eq!(front("INT. - KITCHEN - DAY"), Some(("INT", "- KITCHEN - DAY".into())));
    }

    #[test]
    fn a_stored_value_reads_in_any_spelling() {
        for both in ["INT/EXT", "INT./EXT.", "I/E", "ext/int", "INT. & EXT."] {
            assert_eq!(InsideOut::read(both), Some(InsideOut::Both), "{both}");
            assert_eq!(canonical(both), "INT/EXT");
        }
        assert_eq!(canonical("int."), "INT");
        assert_eq!(canonical("EXT."), "EXT");
        assert_eq!(canonical("LATER"), "LATER");
        assert_eq!(canonical(""), "");
        assert_eq!(printed("INT/EXT"), "INT./EXT.");
        assert_eq!(printed("EXT"), "EXT.");
    }

    #[test]
    fn both_answers_for_each() {
        assert!(answers("INT/EXT", "INT"));
        assert!(answers("INT./EXT.", "EXT"));
        assert!(answers("I/E", "INT/EXT"));
        assert!(answers("INT", "INT."));
        assert!(!answers("INT", "EXT"));
        assert!(!answers("EXT", "INT/EXT"));
        assert!(!answers("INT", "INT/EXT"));
        assert!(!answers("", "INT"));
        assert!(answers("Porch", "porch"));
    }
}
