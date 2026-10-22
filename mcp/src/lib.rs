//! Letting Claude work on a project directly.
//!
//! The case this exists for: a new draft of the script arrives, and the scenes
//! need bringing into line without doing it by hand.
//!
//! Everything goes through the engine, so this obeys the same validation,
//! produces the same change records, and is as undoable as anything typed into
//! the app. There is no back door that can write a state the app could not.
//!
//! Two decisions worth knowing:
//!
//! - **Things are named the way you would say them.** A scene is `34`, a shot is
//!   `34A`. Internal ids work too, but nobody should have to use them.
//! - **Every change saves.** There is no window left open here, so an unsaved
//!   edit would simply be lost when the conversation ends.

/// The JSON reader lives in the engine now, because the Mac and the phone both
/// need one and the engine is the thing all three build. Re-exported under its
/// old name so nothing here had to be re-read.
pub use shotlister_engine::json;
pub mod films;
pub mod server;
pub mod tools;

pub use films::Films;
pub use server::Server;
