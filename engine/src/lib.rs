//! Shotlister engine.
//!
//! The portable core shared by the macOS app, the iPhone app, the MCP server and
//! — later — the web app compiled to WebAssembly. It holds the data model, the
//! change log, and the rules that must not differ between platforms.
//!
//! Deliberately no UI, no file system, no network. Those belong to the shells
//! around it, which keeps this layer testable and identical everywhere.
//!
//! Spec: `../ARCHITECTURE.html`

pub mod arrow;
pub mod avscript;
pub mod beats;
pub mod quoting;
pub mod bulk;
pub mod card;
pub mod cast;
pub mod diagram;
pub mod columns;
pub mod doc;
pub mod editref;
pub mod docstyle;
pub mod export;
pub mod format;
pub mod frames;
pub mod hash;
pub mod id;
pub mod import;
pub mod insideout;
pub mod json;
pub mod jsonw;
pub mod kind;
pub mod kit;
pub mod layout;
pub mod lettering;
pub mod mark;
pub mod letters;
pub mod media;
pub mod printframe;
pub mod natural;
pub mod order;
pub mod package;
pub mod pages;
pub mod playties;
pub mod printed;
pub mod query;
pub mod ratio;
pub mod recordfacts;
pub mod revisions;
pub mod room;
pub mod screenplay;
pub mod script;
pub mod shelf;
pub mod shoots;
pub mod snapshot;
pub mod stamp;
pub mod store;
pub mod sync;
pub mod undo;
pub mod versions;
pub mod value;
pub mod view;
pub mod vocab;

pub use bulk::{Pairing, Plan as BulkPlan};
pub use cast::{Member as CastMember, Merging, Options as CastOptions};
pub use doc::{f, Doc};
pub use export::{Row, RowGroup, Sheet};
pub use format::{decode_log, encode_log, Log};
pub use hash::{sha256, Hash256, Sha256};
pub use id::Id;
pub use kind::Kind as FilmKind;
pub use avscript::{as_audio_only, read as read_av_script, read_any as read_any_script, Report as AvReport, Row as AvRow, Shape as ScriptShape};
pub use import::{apply as apply_import, Report as ImportReport};
pub use layout::FramePosition;
pub use lettering::Regime;
pub use letters::LetterScheme;
pub use media::{
    crop_to_ratio, name_with_extension, plan_cache, proxy_for, CacheEntry, CachePlan, MediaKind,
    Rect,
};
pub use query::{DayFilter, Group, GroupBy, Query, SortBy};
pub use pages::{lay_out, Extent, Paginated};
pub use printed::{Page as PrintedPage, Run as PrintedRun};
pub use revisions::{Plan as RevisionPlan, Revision, Taking, CAST_COLUMN};
pub use screenplay::{Detection, Element, Kind as ElementKind, Screenplay};
pub use script::{ScriptDiff, ScriptScene};
pub use stamp::{Clock, DeviceId, Stamp, Watermark};
pub use store::{Change, Kind, Op, Record, Store};
pub use sync::Clash;
pub use undo::{UndoOutcome, UndoStep};
pub use value::Value;

/// Data format version. Separate from the app version: it moves rarely, only
/// forward, and it is what the write floor is checked against.
pub const FORMAT_VERSION: u32 = 1;

/// Oldest format version this build will write to a shared store.
pub const MIN_WRITABLE_FORMAT: u32 = 1;

/// Whether this build may write to a store at `format`. Below the floor the app
/// goes read-only rather than guessing at data it does not understand.
pub fn can_write(format: u32) -> bool {
    format >= MIN_WRITABLE_FORMAT && format <= FORMAT_VERSION
}
