//! Reading a list back in.
//!
//! A list can leave for a spreadsheet, be worked on by somebody who does not
//! have the app, and come back. That round trip is the point: the sheet is a
//! format, not a one-way door.

pub mod apply;
pub mod csv;
pub mod inflate;
pub mod xlsx;
pub mod xml;
pub mod zip;

pub use apply::{apply, Report};
pub use csv::{parse, Table};
pub use inflate::inflate;
pub use xlsx::read as read_xlsx;
