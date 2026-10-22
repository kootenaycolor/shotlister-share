//! Reading a spreadsheet.
//!
//! Enough of the format to get the values out, and no more. Sheets people send
//! back come from Google Sheets, Excel or Numbers, so this has to cope with
//! shared strings, inline strings, sparse rows and cells that skip columns — but
//! not with formulas, charts or anything else nobody is going to put in a shot
//! list.
//!
//! Whatever it finds goes through the same apply layer as CSV, so the rules
//! about updating rather than duplicating are stated once.

use crate::import::csv::Table;
use crate::import::xml::{attribute, elements, unescape};
use crate::import::zip::{self, ZipError};

#[derive(Debug, PartialEq)]
pub enum XlsxError {
    NotAnArchive,
    NoSheet,
    Corrupt,
}

impl From<ZipError> for XlsxError {
    fn from(error: ZipError) -> XlsxError {
        match error {
            ZipError::NotAnArchive => XlsxError::NotAnArchive,
            _ => XlsxError::Corrupt,
        }
    }
}

/// The text of every `<t>` inside a fragment, joined. Rich text splits a single
/// value across several runs.
fn text_runs(fragment: &str) -> String {
    elements(fragment, "t")
        .iter()
        .map(|run| {
            let start = match run.find('>') {
                Some(at) => at + 1,
                None => return String::new(),
            };
            let end = run.rfind("</t>").unwrap_or(run.len());
            if end <= start {
                String::new()
            } else {
                unescape(&run[start..end])
            }
        })
        .collect::<Vec<_>>()
        .join("")
}

fn first_value(fragment: &str) -> String {
    match elements(fragment, "v").first() {
        Some(value) => {
            let start = match value.find('>') {
                Some(at) => at + 1,
                None => return String::new(),
            };
            let end = value.rfind("</v>").unwrap_or(value.len());
            if end <= start {
                String::new()
            } else {
                unescape(&value[start..end])
            }
        }
        None => String::new(),
    }
}

/// `B7` -> 1. Anything unreadable falls back to appending in order.
fn column_of(reference: &str) -> Option<usize> {
    let letters: String = reference
        .chars()
        .take_while(|c| c.is_ascii_alphabetic())
        .collect();
    if letters.is_empty() {
        return None;
    }
    let mut index = 0usize;
    for ch in letters.chars() {
        index = index * 26 + (ch.to_ascii_uppercase() as usize - 'A' as usize + 1);
    }
    Some(index - 1)
}

fn shared_strings(archive: &zip::Archive) -> Vec<String> {
    match archive.text("xl/sharedStrings.xml") {
        Some(xml) => elements(&xml, "si")
            .iter()
            .map(|item| text_runs(item))
            .collect(),
        None => Vec::new(),
    }
}

fn first_sheet(archive: &zip::Archive) -> Option<String> {
    if let Some(xml) = archive.text("xl/worksheets/sheet1.xml") {
        return Some(xml);
    }
    let mut names: Vec<&str> = archive
        .names()
        .into_iter()
        .filter(|name| name.starts_with("xl/worksheets/") && name.ends_with(".xml"))
        .collect();
    names.sort();
    names.first().and_then(|name| archive.text(name))
}

/// Read the first sheet of a workbook into a table.
pub fn read(bytes: &[u8]) -> Result<Table, XlsxError> {
    let archive = zip::read(bytes)?;
    let strings = shared_strings(&archive);
    let sheet = first_sheet(&archive).ok_or(XlsxError::NoSheet)?;

    let mut records: Vec<Vec<String>> = Vec::new();

    for row in elements(&sheet, "row") {
        let mut cells: Vec<String> = Vec::new();
        for cell in elements(row, "c") {
            let value = match attribute(cell, "t").as_deref() {
                // A shared string: the cell holds an index into the table.
                Some("s") => first_value(cell)
                    .parse::<usize>()
                    .ok()
                    .and_then(|index| strings.get(index).cloned())
                    .unwrap_or_default(),
                Some("inlineStr") => text_runs(cell),
                // A formula's cached result, which is what a reader wants.
                Some("str") => first_value(cell),
                Some("b") => {
                    if first_value(cell) == "1" {
                        "TRUE".to_string()
                    } else {
                        "FALSE".to_string()
                    }
                }
                _ => first_value(cell),
            };

            // Cells may skip columns entirely when they are empty.
            match attribute(cell, "r").as_deref().and_then(column_of) {
                Some(column) => {
                    while cells.len() < column {
                        cells.push(String::new());
                    }
                    if cells.len() == column {
                        cells.push(value);
                    } else {
                        cells[column] = value;
                    }
                }
                None => cells.push(value),
            }
        }
        records.push(cells);
    }

    // A group band is one merged cell across an otherwise empty row — it is
    // decoration this list wrote, not data, so it is dropped rather than read
    // as a shot with no scene.
    records.retain(|record| record.iter().filter(|cell| !cell.trim().is_empty()).count() > 1);

    if records.is_empty() {
        return Ok(Table::default());
    }
    let headers = records.remove(0);
    Ok(Table {
        headers,
        rows: records,
    })
}
