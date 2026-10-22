//! The shape of a project on disk — names, the manifest, and what this build is
//! allowed to do with what it finds.

use shotlister_engine::package::{
    self, access, Access, Manifest, Problem, CHANGES_DIR, EXTENSION, MANIFEST,
};
use shotlister_engine::{DeviceId, Id, FORMAT_VERSION};

// ---- the manifest ------------------------------------------------------

#[test]
fn a_manifest_round_trips() {
    let id = Id::new();
    let manifest = Manifest::new("Daybreak", Some(id));
    let parsed = Manifest::parse(&manifest.encode()).expect("reads");

    assert_eq!(parsed, manifest);
    assert_eq!(parsed.format, FORMAT_VERSION);
    assert_eq!(parsed.project, Some(id));
}

#[test]
fn a_title_with_awkward_characters_survives() {
    let manifest = Manifest::new("Rope \"Around\" the Wind \\ 2026", None);
    let parsed = Manifest::parse(&manifest.encode()).expect("reads");
    assert_eq!(parsed.title, "Rope \"Around\" the Wind \\ 2026");
    assert_eq!(parsed.project, None);
}

#[test]
fn a_manifest_without_a_format_is_refused() {
    let problem = Manifest::parse("{ \"title\": \"Daybreak\" }").unwrap_err();
    assert!(matches!(problem, Problem::Unreadable(_)));
    assert!(problem.message().contains("could not be read"));
}

#[test]
fn a_manifest_from_a_newer_build_still_parses() {
    // We must be able to read it in order to say something useful about it.
    let parsed = Manifest::parse("{ \"format\": 99, \"title\": \"Later\" }").expect("reads");
    assert_eq!(parsed.format, 99);
    assert_eq!(parsed.title, "Later");
}

// ---- the floor ---------------------------------------------------------

#[test]
fn a_project_this_build_understands_is_writable() {
    assert_eq!(access(FORMAT_VERSION), Ok(Access::ReadWrite));
}

#[test]
fn a_project_from_the_future_is_refused_with_something_to_do_about_it() {
    let problem = access(FORMAT_VERSION + 5).unwrap_err();
    assert_eq!(
        problem,
        Problem::TooNew {
            found: FORMAT_VERSION + 5,
            understood: FORMAT_VERSION
        }
    );
    // The message has to say what happened and what to do, not just fail.
    let message = problem.message();
    assert!(message.contains("newer version"));
    assert!(message.contains("Update"));
}

// ---- names -------------------------------------------------------------

#[test]
fn a_project_is_named_after_its_title() {
    assert_eq!(package::package_name("Daybreak"), "Daybreak.shotlist");
    assert_eq!(
        package::package_name("Salt Along the Shore"),
        "Salt Along the Shore.shotlist"
    );
}

#[test]
fn a_title_that_would_break_a_file_system_is_cleaned_up() {
    // Slashes and colons are the ones that actually bite, across Mac, Windows
    // and a Drive folder.
    assert_eq!(package::package_name("INT/EXT: Car"), "INT EXT Car.shotlist");
    assert_eq!(package::package_name("a\\b*c?d"), "a b c d.shotlist");
    // A leading dot would hide the project; a trailing one upsets Windows.
    assert_eq!(package::package_name("...Daybreak..."), "Daybreak.shotlist");
    assert_eq!(package::package_name("   "), "Untitled.shotlist");
    assert_eq!(package::package_name(""), "Untitled.shotlist");
}

#[test]
fn a_very_long_title_is_shortened_rather_than_refused() {
    let long = "A".repeat(300);
    let name = package::package_name(&long);
    assert!(name.len() < 100);
    assert!(name.ends_with(EXTENSION));
}

#[test]
fn one_device_one_session_one_log() {
    let a = package::log_name(DeviceId(1), 100);
    let b = package::log_name(DeviceId(2), 100);
    let c = package::log_name(DeviceId(1), 101);

    // Two devices never write to the same file, which is what makes appending
    // safe without any locking.
    assert_ne!(a, b);
    assert_ne!(a, c);
    assert!(package::is_log_name(&a));
    assert!(!package::is_log_name("manifest.json"));
    assert!(!package::is_log_name(".DS_Store"));
}

#[test]
fn logs_sort_into_a_sensible_order() {
    let mut names = vec![
        package::log_name(DeviceId(2), 5),
        package::log_name(DeviceId(1), 9),
        package::log_name(DeviceId(1), 2),
    ];
    names.sort();
    // Grouped by device, then by session — which is how somebody looking in the
    // folder would want to find them. Order does not affect merging.
    assert_eq!(names[0], package::log_name(DeviceId(1), 2));
    assert_eq!(names[1], package::log_name(DeviceId(1), 9));
    assert_eq!(names[2], package::log_name(DeviceId(2), 5));
}

#[test]
fn media_is_filed_under_its_own_contents() {
    let hash = shotlister_engine::sha256(b"a frame").to_hex();
    let proxy = package::proxy_name(&hash, "png");
    let original = package::original_name(&hash, ".JPEG");

    assert!(proxy.starts_with("media/proxies/"));
    assert!(original.starts_with("media/originals/"));
    assert!(proxy.ends_with(".png"));
    // Extensions are normalised, so `.JPEG` and `jpeg` are one file.
    assert!(original.ends_with(".jpeg"));
    // The same frame lands on the same name however it was imported.
    assert_eq!(proxy, package::proxy_name(&hash, "png"));
}

#[test]
fn a_file_with_no_usable_extension_still_gets_a_name() {
    let hash = shotlister_engine::sha256(b"x").to_hex();
    assert!(package::proxy_name(&hash, "").ends_with(".bin"));
    assert!(package::proxy_name(&hash, "!!!").ends_with(".bin"));
}

#[test]
fn the_layout_is_the_one_the_spec_describes() {
    assert_eq!(MANIFEST, "manifest.json");
    assert_eq!(CHANGES_DIR, "changes");
    assert_eq!(EXTENSION, "shotlist");
}
