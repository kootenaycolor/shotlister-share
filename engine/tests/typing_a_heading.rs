//! Reading a heading somebody **typed**, rather than one a draft printed.
//!
//! The New scene box on the Mac takes one line — `34 INT. CAR - NIGHT` — and
//! fills the scene's four parts from it. The import's own reader is strict
//! about what counts as a slug, for good reason; this is its forgiving twin,
//! and these are the shapes a person actually types.

use shotlister_engine::script::read_heading;

fn parts(line: &str) -> (String, String, String, String) {
    let scene = read_heading(line);
    (
        scene.number.unwrap_or_default(),
        scene.int_ext,
        scene.location,
        scene.time_of_day,
    )
}

#[test]
fn a_whole_slug_line_reads_into_four_parts() {
    assert_eq!(
        parts("34 INT. CAR - NIGHT"),
        ("34".into(), "INT".into(), "CAR".into(), "NIGHT".into())
    );
}

#[test]
fn the_number_is_optional() {
    assert_eq!(
        parts("EXT. BEACH - DAY"),
        (String::new(), "EXT".into(), "BEACH".into(), "DAY".into())
    );
}

#[test]
fn a_bare_number_is_what_the_box_used_to_ask_for() {
    assert_eq!(
        parts("34"),
        ("34".into(), String::new(), String::new(), String::new())
    );
    assert_eq!(
        parts("12A"),
        ("12A".into(), String::new(), String::new(), String::new())
    );
}

#[test]
fn inside_or_outside_can_simply_be_left_off() {
    assert_eq!(
        parts("34 CAR - NIGHT"),
        ("34".into(), String::new(), "CAR".into(), "NIGHT".into())
    );
    assert_eq!(
        parts("KITCHEN"),
        (String::new(), String::new(), "KITCHEN".into(), String::new())
    );
}

#[test]
fn lower_case_is_typed_and_a_heading_is_still_a_heading() {
    assert_eq!(
        parts("34 int. car - night"),
        ("34".into(), "INT".into(), "CAR".into(), "NIGHT".into())
    );
}

#[test]
fn a_location_may_contain_its_own_dash() {
    assert_eq!(
        parts("7 INT. DRIVE-IN CINEMA - DUSK"),
        ("7".into(), "INT".into(), "DRIVE-IN CINEMA".into(), "SUNSET".into())
    );
}

#[test]
fn the_time_is_snapped_to_one_of_the_four_when_it_means_one() {
    assert_eq!(parts("1 INT. HALL - DAWN").3, "SUNRISE");
    assert_eq!(parts("1 INT. HALL - MAGIC HOUR").3, "SUNSET");
    assert_eq!(parts("1 INT. HALL - EVENING").3, "SUNSET");
    assert_eq!(parts("1 INT. HALL - MORNING").3, "DAY");
}

#[test]
fn a_time_the_four_do_not_cover_is_kept_as_written() {
    assert_eq!(parts("1 INT. HALL - CONTINUOUS").3, "CONTINUOUS");
    assert_eq!(parts("1 INT. HALL - LATER").3, "LATER");
}

#[test]
fn nothing_typed_is_nothing_read_rather_than_a_guess() {
    assert_eq!(
        parts("   "),
        (String::new(), String::new(), String::new(), String::new())
    );
}

#[test]
fn an_em_dash_reads_because_a_mac_makes_one_out_of_a_hyphen() {
    assert_eq!(
        parts("2 EXT. PORCH — NIGHT"),
        ("2".into(), "EXT".into(), "PORCH".into(), "NIGHT".into())
    );
}
