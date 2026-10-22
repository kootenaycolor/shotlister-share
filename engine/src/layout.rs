//! Per-shot layout on the page.
//!
//! In document view a shot decides how big its frame is and whether it sits
//! beside the text or below it. Both belong to the shot, so the page keeps its
//! shape wherever it is read or printed.
//!
//! **Width is a fraction of the text measure, never a size.** Storing points or
//! pixels would mean that changing paper size or margins silently rescaled every
//! frame in the project — the page would look right until the day it did not.
//! A fraction survives all of it.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::value::Value;

/// Where the frame sits relative to the shot's text. Four positions, because a
/// frame above the text reads differently from one below it, and which side it
/// takes changes how the page scans.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum FramePosition {
    /// Under the text, full measure by default. The usual case.
    #[default]
    Below,
    /// Over the text, which makes the frame the thing you meet first.
    Above,
    Left,
    Right,
}

impl FramePosition {
    pub fn as_str(self) -> &'static str {
        match self {
            FramePosition::Below => "below",
            FramePosition::Above => "above",
            FramePosition::Left => "left",
            FramePosition::Right => "right",
        }
    }

    pub fn parse(value: &str) -> FramePosition {
        match value.trim().to_lowercase().as_str() {
            "above" | "over" => FramePosition::Above,
            "right" => FramePosition::Right,
            // `beside` was the old name for this, before there were two sides.
            "left" | "side" | "beside" => FramePosition::Left,
            _ => FramePosition::Below,
        }
    }

    /// True when the text and the frame share a line rather than stacking.
    pub fn is_alongside(self) -> bool {
        matches!(self, FramePosition::Left | FramePosition::Right)
    }
}

/// A frame narrower than this is too small to read; wider than the measure
/// would run off the page. Dragging is clamped rather than refused.
pub const MIN_FRAME_WIDTH: f64 = 0.1;
pub const MAX_FRAME_WIDTH: f64 = 1.0;
pub const DEFAULT_FRAME_WIDTH: f64 = 1.0;

impl Doc {
    /// Set the frame width as a fraction of the text measure, 0.1 to 1.0.
    pub fn set_frame_width(&mut self, shot: Id, fraction: f64) {
        let clamped = if fraction.is_finite() {
            fraction.clamp(MIN_FRAME_WIDTH, MAX_FRAME_WIDTH)
        } else {
            DEFAULT_FRAME_WIDTH
        };
        self.set(shot, f::LAYOUT_WIDTH, Value::Float(clamped));
    }

    pub fn frame_width(&self, shot: Id) -> f64 {
        self.get(shot)
            .and_then(|r| r.float(f::LAYOUT_WIDTH))
            .filter(|value| value.is_finite())
            .map(|value| value.clamp(MIN_FRAME_WIDTH, MAX_FRAME_WIDTH))
            .unwrap_or(DEFAULT_FRAME_WIDTH)
    }

    pub fn set_frame_position(&mut self, shot: Id, position: FramePosition) {
        self.set(shot, f::LAYOUT_POSITION, Value::text(position.as_str()));
    }

    pub fn frame_position(&self, shot: Id) -> FramePosition {
        self.get(shot)
            .and_then(|r| r.text(f::LAYOUT_POSITION))
            .map(FramePosition::parse)
            .unwrap_or_default()
    }
}
