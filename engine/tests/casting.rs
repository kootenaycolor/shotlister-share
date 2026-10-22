//! Who the script says is in the film.
//!
//! The cases that matter are the ones where it is *wrong*, because it will be:
//! a title card read as somebody who speaks once, one person spelled three
//! ways, and a merge that would be right on most films and wrong on this one.
//! What the tests pin is that every one of those is visible and adjustable
//! rather than decided quietly.

use shotlister_engine::cast::{read, Merging, Options};
use shotlister_engine::screenplay;

fn cast(text: &str, options: Options) -> Vec<(String, usize)> {
    read(&screenplay::read(text), options)
        .into_iter()
        .map(|member| (member.name, member.speeches))
        .collect()
}

const FILM: &str = "\
INT. MANSION (BEDROOM) - MORNING

The phone rings.

HUSBAND
Don't answer it.

ANYA
It's my mother.

HUSBAND (CONT'D)
It is always your mother.

EXT. BALCONY - CONTINUOUS

ANYA (V.O.)
I should have answered it.

RYAN
Nobody's coming.
";

#[test]
fn everybody_who_speaks_is_found_most_spoken_first() {
    let found = cast(FILM, Options::default());
    assert_eq!(
        found,
        vec![
            ("ANYA".to_string(), 2),
            ("HUSBAND".to_string(), 2),
            ("RYAN".to_string(), 1),
        ]
    );
}

#[test]
fn one_person_spelled_three_ways_is_one_person() {
    let members = read(&screenplay::read(FILM), Options::default());
    let husband = members.iter().find(|m| m.name == "HUSBAND").unwrap();
    assert_eq!(husband.speeches, 2);
    assert_eq!(husband.aliases, vec!["HUSBAND", "HUSBAND (CONT'D)"]);
}

#[test]
fn taking_the_cues_exactly_as_written_keeps_them_apart() {
    let found = cast(FILM, Options::merging(Merging::None));
    assert!(found.contains(&("HUSBAND".to_string(), 1)));
    assert!(found.contains(&("HUSBAND (CONT'D)".to_string(), 1)));
}

#[test]
fn a_cast_list_is_read_at_rest_not_shouted() {
    let members = read(&screenplay::read(FILM), Options::default());
    let displays: Vec<&str> = members.iter().map(|m| m.display.as_str()).collect();
    assert_eq!(displays, vec!["Anya", "Husband", "Ryan"]);
}

#[test]
fn a_name_with_punctuation_in_it_still_reads() {
    let members = read(
        &screenplay::read("INT. HALL - DAY\n\nMRS. O'HARA\nWe were young.\n"),
        Options::default(),
    );
    assert_eq!(members[0].display, "Mrs. O'Hara");
}

#[test]
fn an_apostrophe_begins_a_name_and_does_not_begin_a_contraction() {
    // `O'HARA` is O'Hara and `CONT'D` is Cont'd, and the only thing telling
    // them apart is how much follows the mark.
    let text = "INT. A - DAY\n\nO'HARA (CONT'D)\nAgain.\n";
    let members = read(&screenplay::read(text), Options::merging(Merging::None));
    assert_eq!(members[0].display, "O'Hara (Cont'd)");
}

#[test]
fn everyone_carries_the_scenes_they_speak_in() {
    let members = read(&screenplay::read(FILM), Options::default());
    let anya = members.iter().find(|m| m.name == "ANYA").unwrap();
    assert_eq!(anya.scenes, vec![0, 1]);
    let ryan = members.iter().find(|m| m.name == "RYAN").unwrap();
    assert_eq!(ryan.scenes, vec![1]);
}

#[test]
fn the_name_used_most_is_the_name() {
    // Cued once with a microphone note and twice plainly: they are called by
    // the plain one.
    let text = "INT. A - DAY\n\nJIMMY (V.O.)\nOne.\n\nJIMMY\nTwo.\n\nJIMMY\nThree.\n";
    let members = read(&screenplay::read(text), Options::default());
    assert_eq!(members[0].name, "JIMMY");
    assert_eq!(members[0].speeches, 3);
}

// ---- the ones it gets wrong, and what you can do about them --------------

const WITH_CARDS: &str = "\
INT. MANSION - MORNING

Black.

CALL HER BACK
A film.

HUSBAND
Don't answer it.

HUSBAND
I mean it.

THE END
Fade.
";

#[test]
fn a_title_card_is_found_as_a_person_because_it_looks_exactly_like_one() {
    // Stated as a test rather than hidden: this is the real behaviour, it is
    // what Cadrage's own import does on his film, and the fix below is the
    // honest one.
    let found = cast(WITH_CARDS, Options::default());
    assert!(found.contains(&("CALL HER BACK".to_string(), 1)));
    assert!(found.contains(&("THE END".to_string(), 1)));
}

#[test]
fn a_floor_takes_the_cards_out_and_leaves_the_people() {
    let found = cast(WITH_CARDS, Options::default().at_least(2));
    assert_eq!(found, vec![("HUSBAND".to_string(), 2)]);
}

#[test]
fn a_cue_with_nothing_spoken_under_it_is_not_a_person() {
    // The one door that skips every rule is a forced cue, and a heading in
    // capitals must not get through it.
    let found = cast("INT. A - DAY\n\n@THE END\n\nSomething happens.\n", Options::default());
    assert!(found.is_empty(), "got {found:?}");
}

// ---- merging harder ------------------------------------------------------

#[test]
fn folding_a_name_inside_a_longer_one_is_offered_but_never_the_default() {
    let text = "INT. A - DAY\n\nFRANK\nOne.\n\nOLD FRANK\nTwo.\n\nFRANK\nThree.\n";

    let ordinary = cast(text, Options::default());
    assert!(
        ordinary.contains(&("OLD FRANK".to_string(), 1)),
        "by default the two ages stay two people: {ordinary:?}"
    );

    let hard = cast(text, Options::merging(Merging::Aggressive));
    assert_eq!(hard, vec![("FRANK".to_string(), 3)]);
}

#[test]
fn the_same_name_typed_two_ways_folds_when_asked() {
    let text = "INT. A - DAY\n\nMRS. HALE\nOne.\n\nMRS HALE\nTwo.\n";
    assert_eq!(cast(text, Options::default()).len(), 2);
    assert_eq!(cast(text, Options::merging(Merging::Aggressive)).len(), 1);
}

#[test]
fn a_merge_can_be_disagreed_with_because_it_shows_its_working() {
    let text = "INT. A - DAY\n\nFRANK\nOne.\n\nOLD FRANK\nTwo.\n";
    let members = read(&screenplay::read(text), Options::merging(Merging::Aggressive));
    assert_eq!(members.len(), 1);
    let mut aliases = members[0].aliases.clone();
    aliases.sort();
    assert_eq!(aliases, vec!["FRANK", "OLD FRANK"]);
}

#[test]
fn folding_never_depends_on_who_spoke_first() {
    let one = cast(
        "INT. A - DAY\n\nOLD FRANK\nTwo.\n\nFRANK\nOne.\n",
        Options::merging(Merging::Aggressive),
    );
    let other = cast(
        "INT. A - DAY\n\nFRANK\nOne.\n\nOLD FRANK\nTwo.\n",
        Options::merging(Merging::Aggressive),
    );
    assert_eq!(one, other);
    assert_eq!(one, vec![("FRANK".to_string(), 2)]);
}

#[test]
fn nobody_speaking_is_nobody() {
    assert!(cast("INT. A - DAY\n\nWind in the trees.\n", Options::default()).is_empty());
}
