//! Writing JSON as you go.
//!
//! A builder, not a tree: keys and values are pushed in order and the string is
//! finished at the end. `json.rs` beside this is the other half — reading, and
//! holding a whole value in memory. Two shapes because they answer two
//! questions, and neither wants to be the other.
//!
//! **It lived in `ffi/` until 2026-09-01**, and moved here for the same reason
//! `json.rs` did: a second shell needed it. The browser draws its screens from
//! the same description of a film the Mac draws from, and that description is
//! built with this.

pub struct Json {
    out: String,
    /// Whether the collection currently being written already has an item in it,
    /// so we know when a comma is owed.
    stack: Vec<bool>,
}

impl Json {
    pub fn new() -> Json {
        Json {
            out: String::new(),
            stack: Vec::new(),
        }
    }

    pub fn finish(self) -> String {
        self.out
    }

    fn comma(&mut self) {
        if let Some(has_item) = self.stack.last_mut() {
            if *has_item {
                self.out.push(',');
            }
            *has_item = true;
        }
    }

    pub fn obj(&mut self) -> &mut Json {
        self.comma();
        self.out.push('{');
        self.stack.push(false);
        self
    }

    pub fn end_obj(&mut self) -> &mut Json {
        self.out.push('}');
        self.stack.pop();
        self
    }

    pub fn arr(&mut self) -> &mut Json {
        self.comma();
        self.out.push('[');
        self.stack.push(false);
        self
    }

    pub fn end_arr(&mut self) -> &mut Json {
        self.out.push(']');
        self.stack.pop();
        self
    }

    /// A key expects a value to follow it, so it writes its own comma and then
    /// suppresses the value's.
    pub fn key(&mut self, k: &str) -> &mut Json {
        self.comma();
        escape(&mut self.out, k);
        self.out.push(':');
        if let Some(has_item) = self.stack.last_mut() {
            *has_item = false;
        }
        self
    }

    pub fn str(&mut self, v: &str) -> &mut Json {
        self.comma();
        escape(&mut self.out, v);
        self
    }

    pub fn num(&mut self, v: f64) -> &mut Json {
        self.comma();
        if v.is_finite() {
            if v.fract() == 0.0 && v.abs() < 1e15 {
                self.out.push_str(&format!("{}", v as i64));
            } else {
                self.out.push_str(&format!("{}", v));
            }
        } else {
            self.out.push_str("null");
        }
        self
    }

    pub fn int(&mut self, v: i64) -> &mut Json {
        self.comma();
        self.out.push_str(&v.to_string());
        self
    }

    pub fn bool(&mut self, v: bool) -> &mut Json {
        self.comma();
        self.out.push_str(if v { "true" } else { "false" });
        self
    }

    /// A value that is already JSON, written as it stands — a piece built by
    /// `json.rs`, carried through without being taken apart and rebuilt.
    pub fn raw(&mut self, json: &str) -> &mut Json {
        self.comma();
        self.out.push_str(json);
        self
    }

    pub fn null(&mut self) -> &mut Json {
        self.comma();
        self.out.push_str("null");
        self
    }

    // Shorthands, because `key(..).str(..)` twice per line gets noisy fast.
    pub fn kv(&mut self, k: &str, v: &str) -> &mut Json {
        self.key(k).str(v)
    }
    pub fn kb(&mut self, k: &str, v: bool) -> &mut Json {
        self.key(k).bool(v)
    }
    pub fn ki(&mut self, k: &str, v: i64) -> &mut Json {
        self.key(k).int(v)
    }
    pub fn kn(&mut self, k: &str, v: f64) -> &mut Json {
        self.key(k).num(v)
    }
}

fn escape(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_a_nested_object() {
        let mut j = Json::new();
        j.obj();
        j.kv("title", "Daybreak");
        j.ki("shots", 16);
        j.key("scenes").arr();
        j.obj().kv("number", "34").end_obj();
        j.end_arr();
        j.end_obj();
        assert_eq!(
            j.finish(),
            r#"{"title":"Daybreak","shots":16,"scenes":[{"number":"34"}]}"#
        );
    }

    #[test]
    fn escapes_what_would_break_the_parser() {
        let mut j = Json::new();
        j.obj().kv("d", "Run until \"you need them?\"\n\tnext").end_obj();
        assert_eq!(
            j.finish(),
            "{\"d\":\"Run until \\\"you need them?\\\"\\n\\tnext\"}"
        );
    }

    #[test]
    fn empty_collections_are_still_valid() {
        let mut j = Json::new();
        j.obj().key("rows").arr().end_arr().end_obj();
        assert_eq!(j.finish(), r#"{"rows":[]}"#);
    }
}
