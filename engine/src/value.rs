//! Field values.
//!
//! Deliberately a small closed set. Anything the app wants to store has to fit
//! one of these, which keeps the change format stable across versions: an older
//! build can hold and pass through a value whose *meaning* it does not know.

use crate::id::Id;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Text(String),
    Int(i64),
    Float(f64),
    Bool(bool),
    Ref(Id),
    /// Multi-value fields: angle, tags, pov, ordered media references.
    List(Vec<Value>),
}

impl Value {
    pub fn text(s: impl Into<String>) -> Value {
        Value::Text(s.into())
    }

    pub fn as_text(&self) -> Option<&str> {
        match self {
            Value::Text(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_int(&self) -> Option<i64> {
        match self {
            Value::Int(i) => Some(*i),
            _ => None,
        }
    }

    pub fn as_float(&self) -> Option<f64> {
        match self {
            Value::Float(f) => Some(*f),
            Value::Int(i) => Some(*i as f64),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_ref_id(&self) -> Option<Id> {
        match self {
            Value::Ref(id) => Some(*id),
            _ => None,
        }
    }

    pub fn as_list(&self) -> Option<&[Value]> {
        match self {
            Value::List(v) => Some(v),
            _ => None,
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }
}

impl From<&str> for Value {
    fn from(s: &str) -> Value {
        Value::Text(s.to_string())
    }
}

impl From<String> for Value {
    fn from(s: String) -> Value {
        Value::Text(s)
    }
}

impl From<bool> for Value {
    fn from(b: bool) -> Value {
        Value::Bool(b)
    }
}

impl From<i64> for Value {
    fn from(i: i64) -> Value {
        Value::Int(i)
    }
}

impl From<f64> for Value {
    fn from(f: f64) -> Value {
        Value::Float(f)
    }
}

impl From<Id> for Value {
    fn from(id: Id) -> Value {
        Value::Ref(id)
    }
}
