//! Matching a folder of frames to a list of shots.
//!
//! Somebody exports a board as `01.png … 34.png` and wants them on the shots, in
//! order, without dragging thirty-four files one at a time. The prototype did
//! this and it is the single most-used way media gets in, so the rule for *which
//! file goes on which shot* belongs here rather than in whichever shell happens
//! to own the file picker.
//!
//! Two decisions do all the work:
//!
//! - **Read the folder the way a person reads it.** `10.png` comes after
//!   `2.png`, which sorting as text gets backwards — see `natural`.
//! - **Say what will happen before it happens.** A folder with more files than
//!   shots, or fewer, is the normal case rather than an error, and quietly
//!   dropping the remainder is how somebody ends up with a board that is silently
//!   short. The plan is returned to be shown and confirmed.

use crate::doc::Doc;
use crate::id::Id;
use crate::natural;

/// One file, and the shot it would land on.
#[derive(Clone, Debug, PartialEq)]
pub struct Pairing {
    pub filename: String,
    pub placement: Id,
    /// What that shot is called, so the plan can be read without looking
    /// anything up.
    pub number: String,
    /// Whether that shot already has a frame. Not a refusal — plenty of shots
    /// want a second — but the one thing worth seeing before agreeing.
    pub already_has_frames: bool,
}

/// What a bulk import would do, before it does any of it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Plan {
    pub pairings: Vec<Pairing>,
    /// Files with no shot left to land on.
    pub spare_files: Vec<String>,
    /// Shots the folder ran out before reaching.
    pub shots_left_over: usize,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        self.pairings.is_empty()
    }

    /// Whether anything about this needs saying before it is applied. A folder
    /// that matches the shots exactly, onto shots with no frames yet, is the
    /// case that should just happen.
    pub fn needs_confirming(&self) -> bool {
        !self.spare_files.is_empty()
            || self.shots_left_over > 0
            || self.pairings.iter().any(|p| p.already_has_frames)
    }

    /// Said the way it should appear on screen.
    pub fn summary(&self) -> String {
        let mut said = vec![match self.pairings.len() {
            1 => "1 picture will go onto 1 shot".to_string(),
            n => format!("{n} pictures will go onto {n} shots"),
        }];
        let replacing = self.pairings.iter().filter(|p| p.already_has_frames).count();
        if replacing > 0 {
            said.push(format!(
                "{replacing} of them already {} a frame, and will gain another rather than lose it",
                if replacing == 1 { "has" } else { "have" }
            ));
        }
        if !self.spare_files.is_empty() {
            said.push(format!(
                "{} {} no shot to go on",
                self.spare_files.len(),
                if self.spare_files.len() == 1 { "file has" } else { "files have" }
            ));
        }
        if self.shots_left_over > 0 {
            said.push(format!(
                "{} {} will be left without one",
                self.shots_left_over,
                if self.shots_left_over == 1 { "shot" } else { "shots" }
            ));
        }
        said.join(". ") + "."
    }
}

impl Doc {
    /// Work out what a folder of pictures would do to a list of shots.
    ///
    /// `placements` is the list **as it is being read on screen** — filtered and
    /// grouped as the person sees it — because "in order" can only mean the
    /// order they are looking at. Passing story order when the screen shows
    /// shooting order would attach every picture to the wrong shot while looking
    /// perfectly correct.
    pub fn plan_bulk_media(&self, filenames: &[String], placements: &[Id]) -> Plan {
        let ordered = natural::sorted(filenames);
        let mut pairings = Vec::new();
        let mut spare_files = Vec::new();

        for (index, filename) in ordered.into_iter().enumerate() {
            match placements.get(index) {
                Some(placement) => pairings.push(Pairing {
                    filename,
                    placement: *placement,
                    number: self.display_number(*placement).unwrap_or_default(),
                    already_has_frames: !self.media_refs(*placement).is_empty(),
                }),
                None => spare_files.push(filename),
            }
        }

        let shots_left_over = placements.len().saturating_sub(pairings.len());
        Plan {
            pairings,
            spare_files,
            shots_left_over,
        }
    }
}
