//! Getting the list out.
//!
//! Everything here works from one flattened row model, so the spreadsheet, the
//! printed document and the share page cannot disagree about what is in the
//! list. Derived values are resolved once, in `rows`.
//!
//! Two things deliberately stay outside:
//!
//!   - **Bytes.** Frames are supplied by the caller, since the engine never
//!     touches files. Pass a function that turns a media id into a `src`.
//!   - **PDF.** The pages here are HTML, and the Mac app renders them to PDF
//!     with the system, which sets type and breaks pages better than anything
//!     worth hand-writing.

pub mod autolayout;
pub mod csv;
pub mod html;
pub mod metrics;
pub mod rows;
pub mod share;
pub mod xlsx;
pub mod zip;

pub use csv::COLUMNS;
pub use html::{document, no_frames, table, Frame, FrameSize, Frames, Print};
pub use share::{data_uri, ShareFrame, ShareOptions};
pub use rows::{Camera, Row, RowGroup, Sheet};
