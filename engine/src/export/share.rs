//! The share page.
//!
//! One file, with the frames inside it. No server, no network, nothing to break
//! later — it opens from a Downloads folder on a plane and looks the same as it
//! did the day it was made.
//!
//! Which is also its honest limitation, and the page says so: a file cannot know
//! the list moved on. It carries the date it was made and describes itself as a
//! snapshot rather than pretending to be live.
//!
//! What goes out is a choice, not a default. Crew shorthand in a note reads
//! differently to a producer than it does to you, so notes, struck shots and the
//! technical line can each be held back. Everything is included unless said
//! otherwise, which is what the drawn page does today.

use crate::export::html::{self, Print};
use crate::export::rows::Sheet;
use crate::id::Id;

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Base64, for embedding frames in the page itself.
pub fn base64(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let triple = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(ALPHABET[(triple >> 18) as usize & 63] as char);
        out.push(ALPHABET[(triple >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(triple >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[triple as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

pub fn data_uri(bytes: &[u8], mime: &str) -> String {
    format!("data:{mime};base64,{}", base64(bytes))
}

/// A frame, what it is, and what shape it is — all three supplied by the
/// caller, because only the shell has the bytes. The shape is what lets the
/// page keep the part of a picture he chose to keep; `(0, 0)` is a shell that
/// could not say, and the page then covers the box and keeps the middle.
#[derive(Clone, Debug, Default)]
pub struct ShareFrame {
    pub bytes: Vec<u8>,
    pub mime: String,
    pub width: f64,
    pub height: f64,
}

pub type ShareFrames<'a> = &'a dyn Fn(Id) -> Option<ShareFrame>;

pub fn no_frames(_: Id) -> Option<ShareFrame> {
    None
}

#[derive(Clone, Debug)]
pub struct ShareOptions {
    /// The date this was made, already formatted. The engine has no calendar and
    /// should not pretend to.
    pub made_on: String,
    pub include_notes: bool,
    pub include_struck: bool,
    pub include_technical: bool,
}

impl Default for ShareOptions {
    fn default() -> Self {
        ShareOptions {
            made_on: String::new(),
            include_notes: true,
            include_struck: true,
            include_technical: true,
        }
    }
}

impl ShareOptions {
    pub fn made_on(date: &str) -> ShareOptions {
        ShareOptions {
            made_on: date.to_string(),
            ..ShareOptions::default()
        }
    }

    /// Hold back the crew shorthand.
    pub fn without_notes(mut self) -> ShareOptions {
        self.include_notes = false;
        self
    }

    /// A shot you have cut is arguably nobody else's business.
    pub fn without_struck(mut self) -> ShareOptions {
        self.include_struck = false;
        self
    }

    /// Sizes, lenses and rigs stay in the building.
    pub fn without_technical(mut self) -> ShareOptions {
        self.include_technical = false;
        self
    }
}

/// Apply the choices by editing the rows, so the renderer stays unaware of them.
fn prepare(sheet: &Sheet, options: &ShareOptions) -> Sheet {
    let mut out = sheet.clone();
    for group in out.groups.iter_mut() {
        if !options.include_struck {
            group.rows.retain(|row| !row.struck);
        }
        for row in group.rows.iter_mut() {
            if !options.include_notes {
                row.notes.clear();
            }
            if !options.include_technical {
                row.size.clear();
                row.angle.clear();
                row.movement.clear();
                row.lens.clear();
                row.modifiers.clear();
                row.lens_filters.clear();
                row.support.clear();
                row.camera = None;
            }
        }
    }
    out.groups.retain(|group| !group.rows.is_empty());
    out
}

fn footer(options: &ShareOptions) -> String {
    if options.made_on.is_empty() {
        return String::new();
    }
    format!(
        "<footer class=\"snapshot\">Shared {} — a snapshot of the list as it was that day, \
         not a live view.</footer>",
        html::escape(&options.made_on)
    )
}

/// A whole shot list in one file.
pub fn page(sheet: &Sheet, frames: ShareFrames, options: &ShareOptions) -> String {
    let prepared = prepare(sheet, options);
    // A share page draws one picture per shot, so a clip's trim tells it
    // nothing it can use — but the door it comes through is the same one the
    // printed page uses, so it is taken and ignored on purpose rather than by
    // an accident of the signature.
    let embed = |id: Id, _trim: html::Trim| {
        frames(id).map(|frame| html::Frame {
            src: data_uri(&frame.bytes, &frame.mime),
            width: frame.width,
            height: frame.height,
            moments: 1,
        })
    };
    // The share page has no scene sidebar behind it, so nothing there knows
    // what order the list is being read in — the caption the app writes in its
    // own corner is left off rather than guessed at.
    html::document_page(&prepared, &embed, Print::Screen, &footer(options), "",
                        &crate::docstyle::Style::standard_style())
}
