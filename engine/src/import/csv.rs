//! Reading delimited text.
//!
//! A full parser rather than a split on commas, because the sheets people send
//! back contain commas inside descriptions, quote marks inside notes, and
//! line breaks inside both. The prototype's importer split on commas and lost a
//! column every time somebody wrote a sentence.

/// A parsed table: whatever the first row was, then everything after it.
#[derive(Clone, Debug, Default)]
pub struct Table {
    pub headers: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

impl Table {
    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }
}

/// Split delimited text into records. Handles quoted fields containing the
/// delimiter, doubled quotes, and both line ending conventions.
pub fn parse_records(text: &str, delimiter: char) -> Vec<Vec<String>> {
    let mut records = Vec::new();
    let mut record: Vec<String> = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();

    while let Some(ch) = chars.next() {
        if quoted {
            match ch {
                '"' => {
                    if chars.peek() == Some(&'"') {
                        chars.next();
                        field.push('"');
                    } else {
                        quoted = false;
                    }
                }
                other => field.push(other),
            }
            continue;
        }

        match ch {
            '"' if field.is_empty() => quoted = true,
            c if c == delimiter => record.push(std::mem::take(&mut field)),
            '\r' => {
                // Swallow the newline of a CRLF pair.
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                record.push(std::mem::take(&mut field));
                records.push(std::mem::take(&mut record));
            }
            '\n' => {
                record.push(std::mem::take(&mut field));
                records.push(std::mem::take(&mut record));
            }
            other => field.push(other),
        }
    }

    if !field.is_empty() || !record.is_empty() {
        record.push(field);
        records.push(record);
    }

    // A trailing newline should not produce a phantom empty record.
    records.retain(|r| !(r.len() == 1 && r[0].trim().is_empty()));
    records
}

/// Parse a sheet, taking the first record as the header row.
pub fn parse(text: &str) -> Table {
    let mut records = parse_records(text, ',');
    if records.is_empty() {
        return Table::default();
    }
    let headers = records.remove(0);
    Table {
        headers,
        rows: records,
    }
}
