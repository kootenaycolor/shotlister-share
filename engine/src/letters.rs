//! Shot letters.
//!
//! A letter identifies a shot *within a scene*: scene 34 has shots 34A, 34B, 34C.
//! Two rules from how the lists are actually written:
//!
//!   - Ambiguous letters are skipped. `I` reads as 1 and `P` collides with other
//!     paperwork; real lists run …G, H, J, K… and …N, O, Q, R…
//!   - Letters never reflow. Reordering or deleting a neighbour never renames an
//!     existing shot. A freed letter *is* available to a new placement.
//!
//! Past Z the scheme continues AA, AB, … (bijective, so there is no "A0").

use std::collections::HashSet;

pub const DEFAULT_SKIP: [char; 2] = ['I', 'P'];

#[derive(Clone, Debug)]
pub struct LetterScheme {
    alphabet: Vec<char>,
}

impl Default for LetterScheme {
    fn default() -> Self {
        LetterScheme::new(&DEFAULT_SKIP)
    }
}

impl LetterScheme {
    pub fn new(skip: &[char]) -> LetterScheme {
        let skip: HashSet<char> = skip.iter().map(|c| c.to_ascii_uppercase()).collect();
        let alphabet: Vec<char> = ('A'..='Z').filter(|c| !skip.contains(c)).collect();
        assert!(!alphabet.is_empty(), "letter scheme cannot skip every letter");
        LetterScheme { alphabet }
    }

    pub fn alphabet(&self) -> &[char] {
        &self.alphabet
    }

    /// The nth letter, zero-based. 0 -> "A", 23 -> "Z", 24 -> "AA".
    pub fn nth(&self, n: usize) -> String {
        let base = self.alphabet.len();
        let mut n = n + 1; // bijective numeration
        let mut out = Vec::new();
        while n > 0 {
            n -= 1;
            out.push(self.alphabet[n % base]);
            n /= base;
        }
        out.iter().rev().collect()
    }

    /// Position of a letter in the sequence, if it is well-formed under this
    /// scheme. Used to sort letters as letters rather than as text.
    pub fn position(&self, letter: &str) -> Option<usize> {
        if letter.is_empty() {
            return None;
        }
        let base = self.alphabet.len();
        let mut acc: usize = 0;
        for ch in letter.chars() {
            let up = ch.to_ascii_uppercase();
            let idx = self.alphabet.iter().position(|&c| c == up)?;
            acc = acc.checked_mul(base)?.checked_add(idx + 1)?;
        }
        Some(acc - 1)
    }

    /// Lowest letter not already taken in this scene. Freed letters come back
    /// into play, which is what makes deleting a shot and adding another behave
    /// the way it does on paper.
    pub fn next_free(&self, used: &HashSet<String>) -> String {
        let used_upper: HashSet<String> = used.iter().map(|s| s.to_ascii_uppercase()).collect();
        let mut n = 0usize;
        loop {
            let candidate = self.nth(n);
            if !used_upper.contains(&candidate) {
                return candidate;
            }
            n += 1;
        }
    }
}
