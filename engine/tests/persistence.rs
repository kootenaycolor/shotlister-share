//! The log has to survive a round trip through a file, and through a build that
//! does not fully understand it.

use shotlister_engine::doc::f;
use shotlister_engine::format::{
    decode_change, decode_log, decode_value, encode_change, encode_log, encode_value, DecodeError,
};
use shotlister_engine::{DeviceId, Doc, Id, Value, FORMAT_VERSION};

#[test]
fn every_value_type_round_trips() {
    let id = Id::new();
    let cases = vec![
        Value::Null,
        Value::text("W/OTS"),
        Value::Int(-42),
        Value::Float(1024.5),
        Value::Bool(true),
        Value::Bool(false),
        Value::Ref(id),
        Value::List(vec![Value::text("Front On"), Value::text("Eye Level")]),
        Value::List(vec![]),
    ];
    for value in cases {
        let encoded = encode_value(&value).expect("encodes");
        let decoded = decode_value(&encoded).expect("decodes");
        assert_eq!(value, decoded, "round trip of {value:?}");
    }
}

#[test]
fn awkward_text_survives() {
    // Tabs and newlines are the field and record separators; notes contain both.
    let nasty = "Frame is a way to hide 2 cameras\tcross\ncoverage \\ 100%";
    let value = Value::text(nasty);
    let encoded = encode_value(&value).unwrap();
    assert!(!encoded.contains('\t'), "tabs must not leak into the line");
    assert!(!encoded.contains('\n'), "newlines must not leak into the line");
    assert_eq!(decode_value(&encoded).unwrap(), value);
}

#[test]
fn a_change_round_trips() {
    let mut d = Doc::new(DeviceId(7));
    let scene = d.create_scene("34");
    d.set(scene, f::LOCATION, "JAIL");

    // One line carries the change itself. The watermark on it is a fact about
    // the log rather than about the line, so it comes back on the log round
    // trip below rather than this one.
    for change in d.changes() {
        let line = encode_change(change).expect("encodes");
        let back = decode_change(&line).expect("decodes");
        assert_eq!(back.stamp, change.stamp);
        assert_eq!(back.op, change.op);
    }

    let text = encode_log(1, d.changes(), &[]);
    let log = decode_log(&text).expect("decodes");
    assert_eq!(log.changes, d.changes(), "a whole log round trips exactly");
}

#[test]
fn a_whole_project_survives_being_written_and_read() {
    let mut original = Doc::new(DeviceId(1));
    original.create_project("Daybreak");
    let scene = original.create_scene("34");
    original.set(scene, f::INT_EXT, "INT");
    original.set(scene, f::LOCATION, "car");
    original.set(scene, f::TIME_OF_DAY, "day");
    let day = original.create_day();
    let (shot, placement) = original.add_shot_to_scene(scene);
    original.set(shot, f::LENS, "37mm");
    original.set_vocab_list(shot, "angle", &["Short-Sided", "3/4"]);
    original.schedule(placement, day);

    let text = encode_log(FORMAT_VERSION, original.changes(), &[]);
    let log = decode_log(&text).expect("valid log");
    assert!(log.preserved.is_empty(), "nothing should be unreadable");

    let mut reopened = Doc::new(DeviceId(2));
    reopened.merge(log.changes);

    assert_eq!(reopened.display_number(placement).unwrap(), "34A");
    assert_eq!(reopened.scene_heading(scene).unwrap(), "INT. CAR - DAY");
    assert_eq!(reopened.get(shot).unwrap().text(f::LENS), Some("37mm"));
    assert_eq!(reopened.day_label(day).unwrap(), "Day 1");
    assert_eq!(reopened.placements_on_day(day), vec![placement]);
    assert_eq!(reopened.vocabulary("angle"), vec!["Short-Sided", "3/4"]);
}

#[test]
fn a_line_from_a_newer_build_is_kept_not_dropped() {
    let mut d = Doc::new(DeviceId(1));
    let scene = d.create_scene("34");
    d.add_shot_to_scene(scene);

    // Two lines this build has no idea about: an operation it does not know, and
    // a value type it does not know.
    let from_the_future = vec![
        "1700000000000\t0\t99\tX\t000000000000000000000000000f00d5\tsomething".to_string(),
        "1700000000001\t0\t99\tS\t000000000000000000000000000f00d5\tcolour\tz:experimental"
            .to_string(),
    ];

    let mut text = encode_log(FORMAT_VERSION, d.changes(), &[]);
    for line in &from_the_future {
        text.push_str(line);
        text.push('\n');
    }

    let log = decode_log(&text).expect("valid log");
    assert_eq!(log.changes.len(), d.changes().len());
    assert_eq!(log.preserved, from_the_future);

    // And they go back out exactly as they came in, so the newer build still has
    // them after this build has saved over the file.
    let rewritten = encode_log(log.format, &log.changes, &log.preserved);
    for line in &from_the_future {
        assert!(rewritten.contains(line), "lost: {line}");
    }
}

#[test]
fn a_corrupt_line_is_kept_rather_than_discarded() {
    let text = format!(
        "shotlister-log {FORMAT_VERSION}\nthis is not a change at all\n"
    );
    let log = decode_log(&text).expect("header is still valid");
    assert!(log.changes.is_empty());
    assert_eq!(log.preserved, vec!["this is not a change at all".to_string()]);
}

#[test]
fn a_missing_header_is_refused() {
    assert_eq!(
        decode_log("just some text\n").unwrap_err(),
        DecodeError::MissingHeader
    );
    assert_eq!(decode_log("").unwrap_err(), DecodeError::MissingHeader);
}

#[test]
fn appending_to_a_log_does_not_rewrite_it() {
    // The format is append-only: everything written before must appear verbatim
    // at the head of the file after more changes land.
    let mut d = Doc::new(DeviceId(1));
    let scene = d.create_scene("34");
    let first = encode_log(FORMAT_VERSION, d.changes(), &[]);

    d.add_shot_to_scene(scene);
    let second = encode_log(FORMAT_VERSION, d.changes(), &[]);

    assert!(second.starts_with(&first), "earlier lines must be untouched");
}
