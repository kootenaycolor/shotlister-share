//! Just enough JSON.
//!
//! A small complete reader and writer rather than a dependency, for the same
//! reason as everything else in this crate. Objects keep their key order, so
//! what goes out is stable and diffable.
//!
//! **It lived in `mcp/` until 2026-08-21**, and moved here when a second thing
//! needed to read JSON — the RoomPlan scans in `room.rs`. His instruction that
//! afternoon, about the floor plan: *"you guys should just share the same
//! engine."* Two parsers would have been the same mistake one step down.

use std::fmt::Write;

#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Number(f64),
    Text(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    pub fn text(value: impl Into<String>) -> Json {
        Json::Text(value.into())
    }

    pub fn object(pairs: Vec<(&str, Json)>) -> Json {
        Json::Object(
            pairs
                .into_iter()
                .map(|(key, value)| (key.to_string(), value))
                .collect(),
        )
    }

    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Object(pairs) => pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Text(text) => Some(text),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Json::Number(value) => Some(*value),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(value) => Some(*value),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Json]> {
        match self {
            Json::Array(items) => Some(items),
            _ => None,
        }
    }

    /// A string field, or empty. Tool arguments are hand-written often enough
    /// that a missing key should not be an error on its own.
    pub fn str_field(&self, key: &str) -> String {
        self.get(key).and_then(|v| v.as_str()).unwrap_or("").to_string()
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Json::Null)
    }

    pub fn encode(&self) -> String {
        let mut out = String::new();
        self.write(&mut out);
        out
    }

    fn write(&self, out: &mut String) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(true) => out.push_str("true"),
            Json::Bool(false) => out.push_str("false"),
            Json::Number(value) => {
                if value.fract() == 0.0 && value.is_finite() && value.abs() < 1e15 {
                    let _ = write!(out, "{}", *value as i64);
                } else if value.is_finite() {
                    let _ = write!(out, "{value}");
                } else {
                    out.push_str("null");
                }
            }
            Json::Text(text) => write_string(text, out),
            Json::Array(items) => {
                out.push('[');
                for (index, item) in items.iter().enumerate() {
                    if index > 0 {
                        out.push(',');
                    }
                    item.write(out);
                }
                out.push(']');
            }
            Json::Object(pairs) => {
                out.push('{');
                for (index, (key, value)) in pairs.iter().enumerate() {
                    if index > 0 {
                        out.push(',');
                    }
                    write_string(key, out);
                    out.push(':');
                    value.write(out);
                }
                out.push('}');
            }
        }
    }
}

fn write_string(text: &str, out: &mut String) {
    out.push('"');
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            other => out.push(other),
        }
    }
    out.push('"');
}

// ---- parsing -----------------------------------------------------------

pub fn parse(text: &str) -> Option<Json> {
    let bytes: Vec<char> = text.chars().collect();
    let mut at = 0usize;
    let value = parse_value(&bytes, &mut at)?;
    skip_space(&bytes, &mut at);
    if at < bytes.len() {
        return None;
    }
    Some(value)
}

fn skip_space(chars: &[char], at: &mut usize) {
    while *at < chars.len() && chars[*at].is_whitespace() {
        *at += 1;
    }
}

fn parse_value(chars: &[char], at: &mut usize) -> Option<Json> {
    skip_space(chars, at);
    match chars.get(*at)? {
        '{' => parse_object(chars, at),
        '[' => parse_array(chars, at),
        '"' => parse_string(chars, at).map(Json::Text),
        't' => literal(chars, at, "true", Json::Bool(true)),
        'f' => literal(chars, at, "false", Json::Bool(false)),
        'n' => literal(chars, at, "null", Json::Null),
        _ => parse_number(chars, at),
    }
}

fn literal(chars: &[char], at: &mut usize, word: &str, value: Json) -> Option<Json> {
    for expected in word.chars() {
        if *chars.get(*at)? != expected {
            return None;
        }
        *at += 1;
    }
    Some(value)
}

fn parse_object(chars: &[char], at: &mut usize) -> Option<Json> {
    *at += 1; // {
    let mut pairs = Vec::new();
    loop {
        skip_space(chars, at);
        match chars.get(*at)? {
            '}' => {
                *at += 1;
                return Some(Json::Object(pairs));
            }
            ',' => {
                *at += 1;
                continue;
            }
            '"' => {
                let key = parse_string(chars, at)?;
                skip_space(chars, at);
                if *chars.get(*at)? != ':' {
                    return None;
                }
                *at += 1;
                let value = parse_value(chars, at)?;
                pairs.push((key, value));
            }
            _ => return None,
        }
    }
}

fn parse_array(chars: &[char], at: &mut usize) -> Option<Json> {
    *at += 1; // [
    let mut items = Vec::new();
    loop {
        skip_space(chars, at);
        match chars.get(*at)? {
            ']' => {
                *at += 1;
                return Some(Json::Array(items));
            }
            ',' => {
                *at += 1;
                continue;
            }
            _ => items.push(parse_value(chars, at)?),
        }
    }
}

fn parse_string(chars: &[char], at: &mut usize) -> Option<String> {
    *at += 1; // "
    let mut out = String::new();
    loop {
        let ch = *chars.get(*at)?;
        *at += 1;
        match ch {
            '"' => return Some(out),
            '\\' => {
                let escaped = *chars.get(*at)?;
                *at += 1;
                match escaped {
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    'b' => out.push('\u{8}'),
                    'f' => out.push('\u{c}'),
                    'u' => {
                        let mut code = 0u32;
                        for _ in 0..4 {
                            let digit = chars.get(*at)?.to_digit(16)?;
                            code = code * 16 + digit;
                            *at += 1;
                        }
                        out.push(char::from_u32(code)?);
                    }
                    other => out.push(other),
                }
            }
            other => out.push(other),
        }
    }
}

fn parse_number(chars: &[char], at: &mut usize) -> Option<Json> {
    let start = *at;
    while *at < chars.len()
        && (chars[*at].is_ascii_digit() || matches!(chars[*at], '-' | '+' | '.' | 'e' | 'E'))
    {
        *at += 1;
    }
    let text: String = chars[start..*at].iter().collect();
    text.parse::<f64>().ok().map(Json::Number)
}
