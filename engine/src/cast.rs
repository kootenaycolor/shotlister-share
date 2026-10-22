//! Who is in this film, according to the script.
//!
//! Everybody who is cued to speak, how often, and in which scenes — which is
//! what fills the Cast column on a shot list, and what a first AD wants before
//! anything else.
//!
//! **This cannot be exactly right, and the design admits it.** A cue is a line
//! in capitals with a blank line above it and something underneath, which is
//! also what a title card is, and an end card, and a chapter heading. Cadrage's
//! own import shows `Call Her Back 1x` and `The End 1x` sitting in the cast list
//! of his film, and it does not pretend otherwise: it shows the count, sorts by
//! it, and lets you set a floor. That is the honest design, and it is the one
//! here. Cleverness that guessed at these would be wrong in some other way, on
//! a script nobody has written yet.
//!
//! So the three dials are the ones that matter and no more:
//!
//! - **Merging**, because `JIMMY`, `JIMMY (V.O.)` and `JIMMY (CONT'D)` are one
//!   person and three spellings.
//! - **A floor**, because the false ones almost always speak once.
//! - What you do with the result, which is a person's business, not ours.

use crate::screenplay::{Kind, Screenplay};

/// How hard to work at deciding two spellings are one person.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Merging {
    /// Take every cue exactly as written.
    None,
    /// Fold the extension — `(V.O.)`, `(O.S.)`, `(CONT'D)` — which is the same
    /// person with a microphone somewhere else. The default, and Cadrage's.
    #[default]
    Regular,
    /// Also fold punctuation and spacing, and fold a name that is wholly
    /// contained in a longer one that also speaks — `FRANK` and `OLD FRANK`.
    ///
    /// Deliberately not the default: on a film that really does cast two ages
    /// of one person, this is wrong, and it is wrong quietly. Offered because
    /// on the far more common script where somebody typed the name two ways, it
    /// is right.
    Aggressive,
}

/// The dials, together.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Options {
    pub merging: Merging,
    /// Drop anybody cued fewer times than this. `0` keeps everybody.
    pub minimum_speeches: usize,
}

impl Options {
    pub fn merging(merging: Merging) -> Options {
        Options {
            merging,
            minimum_speeches: 0,
        }
    }

    pub fn at_least(self, minimum_speeches: usize) -> Options {
        Options {
            minimum_speeches,
            ..self
        }
    }
}

/// One person the script has speaking.
#[derive(Clone, Debug, PartialEq)]
pub struct Member {
    /// As the script writes it, in capitals, without the extension: `HUSBAND`.
    pub name: String,
    /// How it should be read by a person: `Husband`. Screenplays shout every
    /// cue; a cast list should not.
    pub display: String,
    /// How many times they are cued. Not lines — speeches, which is what a
    /// count of `33x` means to anybody reading it.
    pub speeches: usize,
    /// The scenes they speak in, by index, in order and without repeats.
    pub scenes: Vec<usize>,
    /// Every spelling folded into this one, `name` included, most-used first.
    /// Shown so that a merge can be disagreed with.
    pub aliases: Vec<String>,
}

/// Everybody in the script, most-spoken first, then alphabetically so that the
/// order never depends on which of two equal names was read first.
pub fn read(screenplay: &Screenplay, options: Options) -> Vec<Member> {
    let mut found: Vec<Gathered> = Vec::new();

    for (at, element) in screenplay.elements.iter().enumerate() {
        if element.kind != Kind::Character {
            continue;
        }
        // A cue with nothing under it is a heading somebody wrote in capitals,
        // not somebody speaking. The reader will not normally produce one, but
        // a forced `@` cue can, and a title card must not be able to sneak in
        // through the one door that skips every rule.
        if !speaks(screenplay, at) {
            continue;
        }

        let written = element.text.trim();
        let key = fold(written, options.merging);
        if key.is_empty() {
            continue;
        }

        match found.iter_mut().find(|member| member.key == key) {
            Some(member) => member.saw(written, element.scene),
            None => {
                let mut member = Gathered::new(key);
                member.saw(written, element.scene);
                found.push(member);
            }
        }
    }

    if options.merging == Merging::Aggressive {
        fold_names_inside_names(&mut found);
    }

    let mut cast: Vec<Member> = found
        .into_iter()
        .filter(|member| member.speeches >= options.minimum_speeches.max(1))
        .map(|member| member.into_member(options.merging))
        .collect();

    cast.sort_by(|a, b| b.speeches.cmp(&a.speeches).then_with(|| a.name.cmp(&b.name)));
    cast
}

/// Whether the cue at this position is followed by anything spoken.
fn speaks(screenplay: &Screenplay, at: usize) -> bool {
    screenplay
        .elements
        .get(at + 1)
        .is_some_and(|next| matches!(next.kind, Kind::Dialogue | Kind::Parenthetical | Kind::Lyric))
}

// ---- gathering -----------------------------------------------------------

struct Gathered {
    key: String,
    /// Each spelling seen, with how many times, in the order first seen.
    spellings: Vec<(String, usize)>,
    speeches: usize,
    scenes: Vec<usize>,
}

impl Gathered {
    fn new(key: String) -> Gathered {
        Gathered {
            key,
            spellings: Vec::new(),
            speeches: 0,
            scenes: Vec::new(),
        }
    }

    fn saw(&mut self, written: &str, scene: Option<usize>) {
        self.speeches += 1;
        match self
            .spellings
            .iter_mut()
            .find(|(spelling, _)| spelling == written)
        {
            Some((_, count)) => *count += 1,
            None => self.spellings.push((written.to_string(), 1)),
        }
        if let Some(scene) = scene {
            if !self.scenes.contains(&scene) {
                self.scenes.push(scene);
            }
        }
    }

    fn take(&mut self, other: Gathered) {
        self.speeches += other.speeches;
        for (spelling, count) in other.spellings {
            match self
                .spellings
                .iter_mut()
                .find(|(existing, _)| *existing == spelling)
            {
                Some((_, existing)) => *existing += count,
                None => self.spellings.push((spelling, count)),
            }
        }
        for scene in other.scenes {
            if !self.scenes.contains(&scene) {
                self.scenes.push(scene);
            }
        }
        self.scenes.sort_unstable();
    }

    fn into_member(mut self, merging: Merging) -> Member {
        // The name is the spelling used most, so a character cued once as
        // `JIMMY (V.O.)` and forty times as `JIMMY` is called `JIMMY`.
        self.spellings.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        let name = self
            .spellings
            .first()
            .map(|(spelling, _)| match merging {
                // Asked to take the cues exactly as written, the name is the
                // cue — extension and all, or the two spellings kept apart
                // would print under one name and look like a bug.
                Merging::None => spelling.trim().to_string(),
                _ => without_extension(spelling).to_string(),
            })
            .unwrap_or_default();
        Member {
            display: as_read(&name),
            name,
            speeches: self.speeches,
            scenes: self.scenes,
            aliases: self.spellings.into_iter().map(|(spelling, _)| spelling).collect(),
        }
    }
}

/// Fold the longer name into the shorter one when the shorter also speaks in
/// its own right — `OLD FRANK` into `FRANK`. Only under `Aggressive`.
fn fold_names_inside_names(found: &mut Vec<Gathered>) {
    // Shortest first, so a name is only ever absorbed by something smaller
    // than it and the result cannot depend on the order they were read in.
    let mut order: Vec<usize> = (0..found.len()).collect();
    order.sort_by_key(|&index| (found[index].key.split(' ').count(), found[index].key.len()));

    let mut absorbed: Vec<(usize, usize)> = Vec::new();
    for (rank, &longer) in order.iter().enumerate() {
        for &shorter in &order[..rank] {
            if absorbed.iter().any(|&(what, _)| what == shorter) {
                continue;
            }
            if contains_whole_words(&found[longer].key, &found[shorter].key) {
                absorbed.push((longer, shorter));
                break;
            }
        }
    }

    // Take from the back so the indices ahead of each removal stay put.
    absorbed.sort_by(|a, b| b.0.cmp(&a.0));
    for (longer, shorter) in absorbed {
        let taken = found.remove(longer);
        let shorter = if shorter > longer { shorter - 1 } else { shorter };
        found[shorter].take(taken);
    }
}

/// Whether `whole` contains `part` as a run of complete words.
fn contains_whole_words(whole: &str, part: &str) -> bool {
    if whole == part {
        return false;
    }
    let whole: Vec<&str> = whole.split(' ').collect();
    let part: Vec<&str> = part.split(' ').collect();
    if part.is_empty() || part.len() >= whole.len() {
        return false;
    }
    whole.windows(part.len()).any(|window| window == part.as_slice())
}

// ---- the spellings -------------------------------------------------------

/// The key two spellings must share to be one person.
fn fold(written: &str, merging: Merging) -> String {
    let name = match merging {
        Merging::None => written.trim(),
        _ => without_extension(written),
    };
    match merging {
        Merging::None | Merging::Regular => name.trim().to_uppercase(),
        // Punctuation is where the same name gets typed two ways — `MRS. HALE`
        // and `MRS HALE`, `JEAN-LUC` and `JEAN LUC`.
        Merging::Aggressive => {
            let mut out = String::with_capacity(name.len());
            let mut spaced = true;
            for ch in name.chars() {
                if ch.is_alphanumeric() {
                    out.extend(ch.to_uppercase());
                    spaced = false;
                } else if !spaced {
                    out.push(' ');
                    spaced = true;
                }
            }
            out.trim().to_string()
        }
    }
}

/// `JIMMY (V.O.)` → `JIMMY`. Everything from the first bracket is where a
/// screenplay puts the microphone, not the person.
fn without_extension(written: &str) -> &str {
    match written.split_once('(') {
        Some((name, _)) => name.trim_end(),
        None => written.trim(),
    }
}

/// `MRS. O'HARA` → `Mrs. O'Hara`. A screenplay shouts every cue because that is
/// how a page is read at speed; a cast list is read at rest.
fn as_read(name: &str) -> String {
    let letters: Vec<char> = name.chars().collect();
    let mut out = String::with_capacity(name.len());
    let mut starting = true;

    for (at, &ch) in letters.iter().enumerate() {
        if starting {
            out.extend(ch.to_uppercase());
        } else {
            out.extend(ch.to_lowercase());
        }
        starting = if ch == '\'' {
            // An apostrophe begins a new word in a name and does not in a
            // contraction, and the difference is length: `O'HARA` is O'Hara,
            // `CONT'D` is Cont'd.
            letters[at + 1..]
                .iter()
                .take_while(|next| next.is_alphabetic())
                .count()
                > 1
        } else {
            !ch.is_alphabetic()
        };
    }
    out
}
