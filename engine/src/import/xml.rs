//! Just enough XML to read the formats people actually send.
//!
//! Two of them now — a spreadsheet's `sheet1.xml` and a Final Draft `.fdx` — and
//! neither needs a real parser. Both are machine-written, shallow, and read by
//! pulling out every occurrence of one element and then its text. So this is a
//! scanner over the string rather than a tree, which keeps the engine
//! dependency-free and keeps the failure mode boring: an element it does not
//! understand is one it does not return.
//!
//! It was private inside `xlsx.rs` until the screenplay reader needed the same
//! three functions. Copying them would have been the easy move and the wrong
//! one — two XML readers is two ways to disagree about an ampersand.
//!
//! What it deliberately cannot do: nested elements of the same name, namespaces,
//! DTDs, CDATA. Nothing it is pointed at contains them.

/// Turn `&amp;` and friends back into the characters they stand for, including
/// numeric escapes in both decimal and hex.
pub fn unescape(text: &str) -> String {
    if !text.contains('&') {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('&') {
        out.push_str(&rest[..at]);
        rest = &rest[at..];
        let end = match rest.find(';') {
            Some(end) if end <= 10 => end,
            _ => {
                out.push('&');
                rest = &rest[1..];
                continue;
            }
        };
        let entity = &rest[1..end];
        let replacement = match entity {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            other => other
                .strip_prefix('#')
                .and_then(|number| {
                    match number.strip_prefix('x').or_else(|| number.strip_prefix('X')) {
                        Some(hex) => u32::from_str_radix(hex, 16).ok(),
                        None => number.parse::<u32>().ok(),
                    }
                })
                .and_then(char::from_u32),
        };
        match replacement {
            Some(ch) => out.push(ch),
            None => out.push_str(&rest[..=end]),
        }
        rest = &rest[end + 1..];
    }
    out.push_str(rest);
    out
}

/// Every occurrence of an element, as the whole text from its open tag to its
/// close tag. Elements of the kinds read here do not nest, which is what makes
/// this safe. A self-closing element comes back as an empty string, so that the
/// count still matches what the document said.
pub fn elements<'a>(xml: &'a str, name: &str) -> Vec<&'a str> {
    let open = format!("<{name}");
    let close = format!("</{name}>");
    let mut found = Vec::new();
    let mut rest = xml;

    while let Some(start) = rest.find(&open) {
        let after = &rest[start..];
        // Guard against matching `<row` inside `<rowBreaks`.
        let next = after[open.len()..].chars().next();
        if !matches!(next, Some(' ') | Some('>') | Some('/') | Some('\t') | Some('\n')) {
            rest = &after[open.len()..];
            continue;
        }
        let tag_end = match after.find('>') {
            Some(end) => end,
            None => break,
        };
        if after[..tag_end].ends_with('/') {
            found.push("");
            rest = &after[tag_end + 1..];
            continue;
        }
        match after.find(&close) {
            Some(end) => {
                found.push(&after[..end + close.len()]);
                rest = &after[end + close.len()..];
            }
            None => break,
        }
    }
    found
}

/// One attribute off a fragment's own opening tag.
pub fn attribute(fragment: &str, name: &str) -> Option<String> {
    let tag_end = fragment.find('>')?;
    let tag = &fragment[..tag_end];
    let key = format!("{name}=\"");
    let start = tag.find(&key)? + key.len();
    let end = tag[start..].find('"')? + start;
    Some(unescape(&tag[start..end]))
}

/// What is between a fragment's own open and close tags, with any child tags
/// stripped and entities resolved. Whitespace is left exactly as found: a
/// screenplay's indentation is content, not formatting.
pub fn inner_text(fragment: &str) -> String {
    let Some(start) = fragment.find('>') else {
        return String::new();
    };
    let body = &fragment[start + 1..];
    let body = match body.rfind("</") {
        Some(end) => &body[..end],
        None => body,
    };

    let mut out = String::with_capacity(body.len());
    let mut rest = body;
    while let Some(at) = rest.find('<') {
        out.push_str(&rest[..at]);
        match rest[at..].find('>') {
            Some(end) => rest = &rest[at + end + 1..],
            None => {
                rest = "";
                break;
            }
        }
    }
    out.push_str(rest);
    unescape(&out)
}
