//! CSV.
//!
//! The plainest way out. Columns follow the working sheets, and the group column
//! is filled on every row rather than only the first, because a spreadsheet that
//! is going to be sorted or filtered by someone else must not depend on rows
//! staying next to each other.

use crate::export::rows::Sheet;

/// Header row. Ordered to match the sheets, so a pasted export lands in the
/// right columns of an existing template.
pub const COLUMNS: [&str; 14] = [
    "Day",
    "Scene #",
    "Shot #",
    "Shot Description",
    "Size",
    "Angle",
    "Movement",
    "Camera",
    "Lens",
    "Equipment",
    "Notes",
    "Tags",
    "Sequence",
    "Struck",
];

fn field(value: &str) -> String {
    // Quote whenever the value could otherwise break the row, and double any
    // quotes inside it. The prototype quoted everything and escaped nothing,
    // which turned any note containing a quote mark into corrupt columns.
    let needs_quotes = value.contains(',')
        || value.contains('"')
        || value.contains('\n')
        || value.contains('\r');
    if needs_quotes {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_string()
    }
}

pub fn write(sheet: &Sheet) -> String {
    let mut out = String::new();
    out.push_str(&COLUMNS.join(","));
    out.push('\n');

    for group in &sheet.groups {
        for row in &group.rows {
            let cells = [
                row.day_label.clone().unwrap_or_default(),
                row.scene_number.clone(),
                row.number.clone(),
                row.description.clone(),
                row.size.clone(),
                row.angle.join(", "),
                row.movement.clone(),
                row.camera.as_ref().map(|c| c.display()).unwrap_or_default(),
                row.lens_cell(),
                row.support.clone(),
                row.notes.clone(),
                row.tags.join("; "),
                row.sequence.clone().unwrap_or_default(),
                if row.struck { "yes".to_string() } else { String::new() },
            ];
            let line: Vec<String> = cells.iter().map(|c| field(c)).collect();
            out.push_str(&line.join(","));
            out.push('\n');
        }
    }

    out
}
