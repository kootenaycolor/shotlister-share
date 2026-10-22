//! Comparing the way people expect.
//!
//! Sorted as text, `100mm` comes before `37mm`, and `shot-10.jpg` comes before
//! `shot-2.jpg`. Both are correct and both are wrong: a lens list that puts the
//! hundreds first is unreadable, and a folder of frames that lands in the wrong
//! order silently attaches the wrong picture to the wrong shot.
//!
//! So runs of digits are compared as numbers and everything else as text. That
//! is the only rule, and it is enough for every place this project sorts things
//! a person named: lenses, sizes, scene numbers, file names.

use std::cmp::Ordering;

/// Compare two strings the way a person reads them.
///
/// Case is ignored for ordering but breaks ties, so `A` and `a` do not compare
/// equal and a sort stays stable and total.
pub fn compare(a: &str, b: &str) -> Ordering {
    let mut left = Chunks::new(a);
    let mut right = Chunks::new(b);

    loop {
        match (left.next(), right.next()) {
            (None, None) => break,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) => {
                let order = match (x.number(), y.number()) {
                    // Leading zeros do not make a number bigger or smaller, so
                    // `007` and `7` compare equal here and are separated below.
                    (Some(m), Some(n)) => m.cmp(&n),
                    _ => x.text.to_lowercase().cmp(&y.text.to_lowercase()),
                };
                if order != Ordering::Equal {
                    return order;
                }
            }
        }
    }

    // Everything a reader can see is equal. Fall back to the bytes so the
    // ordering is total — two different strings never compare the same.
    a.cmp(b)
}

/// Whether two strings say the same thing to a reader.
///
/// Not the same question as `compare(a, b).is_eq()`, and the difference matters.
/// Ordering has to be *total* — two different strings must never compare equal,
/// or a sort becomes unstable — so `compare` falls back to the bytes once
/// everything visible matches. Matching wants the opposite: `034` and `34` are
/// the same scene, and a draft that prints it one way is not describing a
/// different one.
pub fn same(a: &str, b: &str) -> bool {
    let mut left = Chunks::new(a);
    let mut right = Chunks::new(b);
    loop {
        match (left.next(), right.next()) {
            (None, None) => return true,
            (None, _) | (_, None) => return false,
            (Some(x), Some(y)) => {
                let alike = match (x.number(), y.number()) {
                    (Some(m), Some(n)) => m == n,
                    _ => x.text.eq_ignore_ascii_case(y.text),
                };
                if !alike {
                    return false;
                }
            }
        }
    }
}

/// An empty value sorts last whichever way the column is pointing.
///
/// A blank cell is not the smallest value, it is an absent one, and burying the
/// filled-in rows under a wall of empties is never what anybody meant by sorting
/// a column.
pub fn compare_filled_first(a: &str, b: &str) -> Ordering {
    match (a.trim().is_empty(), b.trim().is_empty()) {
        (true, true) => Ordering::Equal,
        (true, false) => Ordering::Greater,
        (false, true) => Ordering::Less,
        (false, false) => compare(a, b),
    }
}

/// Sort a list of names the way a folder should be read.
pub fn sorted(names: &[String]) -> Vec<String> {
    let mut out = names.to_vec();
    out.sort_by(|a, b| compare(a, b));
    out
}

struct Chunk<'a> {
    text: &'a str,
    digits: bool,
}

impl Chunk<'_> {
    fn number(&self) -> Option<u128> {
        if !self.digits {
            return None;
        }
        // A run of digits long enough to overflow is not a number anybody
        // typed, so it is compared as text rather than truncated.
        self.text.trim_start_matches('0').parse().ok().or({
            if self.text.chars().all(|c| c == '0') {
                Some(0)
            } else {
                None
            }
        })
    }
}

struct Chunks<'a> {
    rest: &'a str,
}

impl<'a> Chunks<'a> {
    fn new(text: &'a str) -> Chunks<'a> {
        Chunks { rest: text }
    }
}

impl<'a> Iterator for Chunks<'a> {
    type Item = Chunk<'a>;

    fn next(&mut self) -> Option<Chunk<'a>> {
        if self.rest.is_empty() {
            return None;
        }
        let digits = self.rest.chars().next().is_some_and(|c| c.is_ascii_digit());
        let end = self
            .rest
            .char_indices()
            .find(|(_, c)| c.is_ascii_digit() != digits)
            .map(|(at, _)| at)
            .unwrap_or(self.rest.len());
        let (text, rest) = self.rest.split_at(end);
        self.rest = rest;
        Some(Chunk { text, digits })
    }
}
