//! Reading a script off printed pages.
//!
//! Every fixture here is written as the page itself: the indentation in the
//! string *is* the column on the paper. Column 0 is an inch from the paper's
//! edge, where scene numbers are printed, and every character is a tenth of an
//! inch after that — so column 5 is the 1.5" text block, 15 is dialogue at
//! 2.5", 21 is a parenthetical, 27 is a cue at 3.7", and 50 is a transition.
//! That is a real page, laid out to the standard, and it is what PDFKit will
//! hand across.

use shotlister_engine::cast::{self, Options};
use shotlister_engine::printed::{self, Page, Run};
use shotlister_engine::screenplay::{Detection, Kind, Status};

/// Turn a laid-out page into the runs a PDF would give: text separated by two
/// or more spaces arrives as separate runs, exactly as it does off a real one.
fn page(text: &str) -> Page {
    let mut runs = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let y = 36.0 + index as f32 * 12.0;
        let letters: Vec<char> = line.chars().collect();
        let mut at = 0;
        while at < letters.len() {
            if letters[at] == ' ' {
                at += 1;
                continue;
            }
            let start = at;
            let mut gap = 0;
            let mut end = at;
            while at < letters.len() {
                if letters[at] == ' ' {
                    gap += 1;
                    if gap >= 2 {
                        break;
                    }
                } else {
                    gap = 0;
                    end = at;
                }
                at += 1;
            }
            let word: String = letters[start..=end].iter().collect();
            runs.push(Run::new(72.0 + start as f32 * 7.2, y, word));
        }
    }
    Page::letter(runs)
}

fn shifted(text: &str, inches: f32) -> Page {
    let mut page = page(text);
    for run in &mut page.runs {
        run.x += inches * 72.0;
    }
    page
}

const PAGE: &str = "\
                                                            12.

1    INT. REMOTE MANSION (BEDROOM) - MORNING                   1

     A rotary phone rings and rings on the nightstand. Nobody
     reaches for it.

     THE PHONE STOPS.

                         HUSBAND
                   (not moving)
                   Don't answer it.

                         ANYA
                   It's my mother.

                                                  CUT TO:

2    EXT. BALCONY - CONTINUOUS                                 2

     Anya steps out into the cold.
";

#[test]
fn a_column_tells_a_cue_from_a_shout() {
    // The whole reason to take positions rather than plain text. `THE PHONE
    // STOPS.` is capitals with a blank line above it and words below it, which
    // is a character cue by every rule text alone can offer. On the page it is
    // standing at the action column, so it is not one, and nobody by that name
    // joins the cast.
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    let cues: Vec<&str> = screenplay
        .elements
        .iter()
        .filter(|element| element.kind == Kind::Character)
        .map(|element| element.text.as_str())
        .collect();
    assert_eq!(cues, vec!["HUSBAND", "ANYA"]);
}

#[test]
fn a_shout_at_the_left_edge_is_offered_as_a_room_and_never_taken() {
    // What it *does* become, said out loud. Standing alone in capitals at the
    // action column is exactly what a bare room name looks like, so the room
    // rule takes it — and the room rule's whole answer to being loose is that
    // what it finds arrives unticked.
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    let shout = screenplay
        .scenes
        .iter()
        .find(|scene| scene.script.heading == "THE PHONE STOPS.")
        .expect("it is found, and the test says so rather than hiding it");
    assert!(matches!(shout.status, Status::SubSlug { .. }));
    assert!(!shout.accepted);
}

#[test]
fn with_rooms_not_being_looked_for_a_shout_is_simply_action() {
    let detection = Detection {
        find_sub_slugs: false,
        ..Detection::printed()
    };
    let screenplay = printed::read(&[page(PAGE)], &detection);
    assert!(screenplay
        .elements
        .iter()
        .any(|e| e.kind == Kind::Action && e.text == "THE PHONE STOPS."));
}

#[test]
fn every_kind_of_line_lands_where_its_column_says() {
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    let found: Vec<(&str, &str)> = screenplay
        .elements
        .iter()
        .map(|element| (element.kind.name(), element.text.as_str()))
        .collect();
    assert_eq!(
        found,
        vec![
            // The printed numbers belong to the scene, not to the line of
            // text: the heading element carries the slug alone.
            ("heading", "INT. REMOTE MANSION (BEDROOM) - MORNING"),
            (
                "action",
                "A rotary phone rings and rings on the nightstand. Nobody reaches for it."
            ),
            // A room, offered and unticked — see the test above.
            ("heading", "THE PHONE STOPS."),
            ("character", "HUSBAND"),
            ("parenthetical", "(not moving)"),
            ("dialogue", "Don't answer it."),
            ("character", "ANYA"),
            ("dialogue", "It's my mother."),
            ("transition", "CUT TO:"),
            ("heading", "EXT. BALCONY - CONTINUOUS"),
            ("action", "Anya steps out into the cold."),
        ]
    );
}

#[test]
fn a_paragraph_wrapped_by_the_printer_is_put_back_together() {
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    let action = screenplay
        .elements
        .iter()
        .find(|element| element.kind == Kind::Action)
        .unwrap();
    assert!(
        !action.text.contains('\n'),
        "the printer's line breaks are not the writer's: {:?}",
        action.text
    );
}

#[test]
fn the_page_number_is_not_part_of_the_film() {
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    assert!(!screenplay.elements.iter().any(|e| e.text.contains("12.")));
}

#[test]
fn the_scenes_come_out_numbered_as_the_script_numbered_them() {
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    let numbers: Vec<String> = screenplay
        .accepted()
        .into_iter()
        .filter_map(|scene| scene.number)
        .collect();
    assert_eq!(numbers, vec!["1", "2"]);
}

#[test]
fn a_script_printed_with_unusual_margins_reads_the_same() {
    // The columns are learned from the page, not assumed. A half-inch of extra
    // margin would put every fixed measurement out by the same amount and drop
    // every line into the wrong column.
    let ordinary = printed::read(&[page(PAGE)], &Detection::printed());
    let wide = printed::read(&[shifted(PAGE, 0.5)], &Detection::printed());

    let kinds = |screenplay: &shotlister_engine::Screenplay| -> Vec<String> {
        screenplay
            .elements
            .iter()
            .map(|element| format!("{} {}", element.kind.name(), element.text))
            .collect()
    };
    assert_eq!(kinds(&ordinary), kinds(&wide));
}

#[test]
fn a_revision_mark_in_the_margin_is_not_a_line_of_the_script() {
    let marked = "\
1    INT. KITCHEN - DAY                                        1

     She waits.                                                *
";
    let screenplay = printed::read(&[page(marked)], &Detection::printed());
    assert!(!screenplay.elements.iter().any(|e| e.text.contains('*')));
}

// ---- what a page break does ---------------------------------------------

const FIRST: &str = "\
                                                            3.

3    INT. MANSION - AFTERNOON                                  3

     He moves through the house.

     BATHROOM.

     Steam on the mirror.

     BEDROOM.

     The bed is made.

                                              (CONTINUED)
";

const SECOND: &str = "\
                                                            4.

     CONTINUED:

3    INT. MANSION - AFTERNOON                                  3

                         HUSBAND
                   Anya?

4    INT. KITCHEN - NIGHT                                      4

     The kettle.
";

#[test]
fn a_scene_carried_over_a_page_break_is_one_scene() {
    let screenplay = printed::read(&[page(FIRST), page(SECOND)], &Detection::printed());
    let numbers: Vec<String> = screenplay
        .accepted()
        .into_iter()
        .filter_map(|scene| scene.number)
        .collect();
    assert_eq!(numbers, vec!["3", "4"]);
    assert_eq!(screenplay.duplicates_ignored, 1);
}

#[test]
fn what_is_said_after_the_break_belongs_to_the_scene_it_is_in() {
    let screenplay = printed::read(&[page(FIRST), page(SECOND)], &Detection::printed());
    let three = screenplay.scene_numbered("3").unwrap();
    assert!(screenplay
        .elements_in(three)
        .iter()
        .any(|element| element.kind == Kind::Character && element.text == "HUSBAND"));
}

#[test]
fn neither_kind_of_continued_reaches_the_script() {
    let screenplay = printed::read(&[page(FIRST), page(SECOND)], &Detection::printed());
    assert!(!screenplay
        .elements
        .iter()
        .any(|element| element.text.to_uppercase().contains("CONTINUED")));
}

#[test]
fn a_room_under_a_scene_is_lettered_to_it_and_offered_unticked() {
    let screenplay = printed::read(&[page(FIRST), page(SECOND)], &Detection::printed());
    let rooms: Vec<(&str, &str)> = screenplay
        .scenes
        .iter()
        .filter(|scene| matches!(scene.status, Status::SubSlug { .. }))
        .map(|scene| (scene.label.as_str(), scene.script.heading.as_str()))
        .collect();
    assert_eq!(rooms, vec![("3A", "BATHROOM."), ("3B", "BEDROOM.")]);
    assert!(screenplay
        .scenes
        .iter()
        .all(|scene| scene.accepted != matches!(scene.status, Status::SubSlug { .. })));
}

// ---- the odd ones --------------------------------------------------------

#[test]
fn a_cue_with_nothing_under_it_is_not_somebody_speaking() {
    let text = "\
1    INT. KITCHEN - DAY                                        1

                         THE END

     Black.
";
    let screenplay = printed::read(&[page(text)], &Detection::printed());
    assert!(!screenplay
        .elements
        .iter()
        .any(|element| element.kind == Kind::Character));
}

#[test]
fn a_bracketed_line_is_a_parenthetical_wherever_it_was_set() {
    // Software disagrees about where a parenthetical sits; it never disagrees
    // about the brackets.
    let text = "\
1    INT. KITCHEN - DAY                                        1

                         ANYA
                     (quietly, to herself)
                   I knew it.
";
    let screenplay = printed::read(&[page(text)], &Detection::printed());
    assert!(screenplay
        .elements
        .iter()
        .any(|e| e.kind == Kind::Parenthetical && e.text == "(quietly, to herself)"));
}

#[test]
fn who_is_in_it_comes_straight_off_the_page() {
    let screenplay = printed::read(&[page(PAGE)], &Detection::printed());
    let found: Vec<(String, usize)> = cast::read(&screenplay, Options::default())
        .into_iter()
        .map(|member| (member.display, member.speeches))
        .collect();
    assert_eq!(
        found,
        vec![("Anya".to_string(), 1), ("Husband".to_string(), 1)]
    );
}

#[test]
fn nothing_on_the_page_is_nothing_at_all() {
    let screenplay = printed::read(&[Page::letter(Vec::new())], &Detection::printed());
    assert!(screenplay.elements.is_empty());
    assert!(screenplay.scenes.is_empty());
}

#[test]
fn the_marked_script_is_there_to_be_read_when_something_looks_wrong() {
    // What the module hands on, in the form a person can check by eye.
    let marked = printed::as_script(&[page(PAGE)]);
    assert!(marked.contains("@HUSBAND"), "{marked}");
    assert!(marked.contains("\nTHE PHONE STOPS."), "{marked}");
    assert!(marked.contains(">CUT TO:"), "{marked}");
    assert!(
        marked.contains("1 INT. REMOTE MANSION (BEDROOM) - MORNING 1"),
        "a heading keeps its printed numbers and is left unmarked, so the \
         detection rules are the ones that decide: {marked}"
    );
}

#[test]
fn a_page_where_nothing_wrapped_is_still_read_as_separate_paragraphs() {
    // The awkward case: no two lines on this page are adjacent, so every gap
    // is a double space and there is nothing to measure the single space
    // against. Read wrongly it becomes one sixty-line paragraph — which is not
    // a thing a screenplay page has ever been.
    let sparse = "\
1    INT. KITCHEN - DAY                                        1

     She waits.

     BATHROOM.

     Steam.
";
    let screenplay = printed::read(&[page(sparse)], &Detection::printed());
    let action: Vec<&str> = screenplay
        .elements
        .iter()
        .filter(|element| element.kind == Kind::Action)
        .map(|element| element.text.as_str())
        .collect();
    assert_eq!(action, vec!["She waits.", "Steam."]);
    assert!(
        screenplay.scenes.iter().any(|scene| scene.label == "1A"),
        "and the room is still seen for what it is"
    );
}

// ---- what his own script taught us --------------------------------------
//
// Every case below was found by running `tools/pdftext.swift` over the real
// `DRAFTJP.pdf` and looking at what came back. None of them were predicted.

/// A reader that hands back *lines* gives the two margin scene numbers as their
/// own piece of the line, before the slug — `54: "2 2"`, `108: "INT. …"`.
#[test]
fn the_numbers_printed_at_both_margins_do_not_stop_a_slug_being_one() {
    let page = Page::letter(vec![
        Run::new(54.0, 131.0, "2 2"),
        Run::new(108.0, 131.0, "INT. REMOTE MANSION (BEDROOM) - MORNING"),
        Run::new(108.0, 155.0, "ANYA stands next to a red rotary phone."),
    ]);
    let screenplay = printed::read(&[page], &Detection::printed());
    assert_eq!(screenplay.scenes.len(), 1, "left in, it is not a slug at all");
    assert_eq!(screenplay.scenes[0].script.number.as_deref(), Some("2"));
    assert_eq!(
        screenplay.scenes[0].script.heading,
        "INT. REMOTE MANSION (BEDROOM) - MORNING"
    );
}

/// And the margin number must not drag the left edge of the text block out to
/// where *it* sits, or every column on the page is read one place too far in.
#[test]
fn a_number_in_the_margin_is_not_where_the_text_block_begins() {
    let page = Page::letter(vec![
        Run::new(54.0, 131.0, "2 2"),
        Run::new(108.0, 131.0, "INT. KITCHEN - DAY"),
        Run::new(108.0, 155.0, "She waits by the window."),
        Run::new(252.0, 179.0, "ANYA"),
        Run::new(180.0, 191.0, "Hello, dear."),
    ]);
    let screenplay = printed::read(&[page], &Detection::printed());
    let kinds: Vec<&str> = screenplay
        .elements
        .iter()
        .map(|element| element.kind.name())
        .collect();
    assert_eq!(kinds, vec!["heading", "action", "character", "dialogue"]);
}

/// `5 BATHROOM.` and `1 OVER BLACK - THE SOUND OF A ROTARY PHONE RINGING.` are
/// both numbered scenes in his draft and neither says INT or EXT. It is why
/// Cadrage's own import leaves its INT/EXT requirement switched off.
#[test]
fn a_heading_the_script_numbered_is_a_scene_without_saying_int_or_ext() {
    let page = Page::letter(vec![
        Run::new(54.0, 71.0, "1 1"),
        Run::new(108.0, 71.0, "OVER BLACK - THE SOUND OF A ROTARY PHONE RINGING."),
        Run::new(108.0, 95.0, "A phone rings in the dark."),
        Run::new(54.0, 131.0, "5 5"),
        Run::new(108.0, 131.0, "BATHROOM."),
        Run::new(108.0, 155.0, "Steam on the mirror."),
    ]);
    let screenplay = printed::read(&[page], &Detection::printed());
    let taken: Vec<(String, String)> = screenplay
        .scenes
        .iter()
        .filter(|scene| scene.accepted)
        .map(|scene| (scene.label.clone(), scene.script.heading.clone()))
        .collect();
    assert_eq!(
        taken,
        vec![
            ("1".to_string(), "OVER BLACK - THE SOUND OF A ROTARY PHONE RINGING.".to_string()),
            ("5".to_string(), "BATHROOM.".to_string()),
        ]
    );
}

/// A line of action in capitals that the script did *not* number stays what it
/// is — the number is the whole difference.
#[test]
fn the_same_words_without_a_number_are_not_a_scene() {
    let page = Page::letter(vec![
        Run::new(54.0, 71.0, "1 1"),
        Run::new(108.0, 71.0, "INT. KITCHEN - DAY"),
        Run::new(108.0, 95.0, "She waits."),
        Run::new(108.0, 119.0, "THE PHONE STOPS."),
        Run::new(108.0, 143.0, "Nobody moves."),
    ]);
    let screenplay = printed::read(&[page], &Detection::printed());
    let stopped = screenplay
        .scenes
        .iter()
        .find(|scene| scene.script.heading == "THE PHONE STOPS.");
    assert!(matches!(stopped, Some(scene) if !scene.accepted), "offered, never taken");
}

/// A heading sits at the same column as the action around it, so a paragraph
/// will swallow one unless it is asked to stop. Across a page break this ate a
/// whole scene of his — 9 LIVING ROOM. simply vanished.
#[test]
fn a_heading_at_the_top_of_a_page_is_not_swallowed_by_the_paragraph_before_it() {
    let first = Page::letter(vec![
        Run::new(54.0, 623.0, "8 8"),
        Run::new(108.0, 623.0, "FRONT YARD."),
        Run::new(108.0, 647.0, "Anya waters the plants."),
    ]);
    let second = Page::letter(vec![
        Run::new(508.0, 35.0, "5."),
        Run::new(54.0, 71.0, "9 9"),
        Run::new(108.0, 71.0, "LIVING ROOM."),
        Run::new(108.0, 95.0, "Anya sits on a yellow couch."),
    ]);
    let screenplay = printed::read(&[first, second], &Detection::printed());
    let numbers: Vec<String> = screenplay
        .accepted()
        .into_iter()
        .filter_map(|scene| scene.number)
        .collect();
    assert_eq!(numbers, vec!["8", "9"], "the scene over the fold went missing");
}

/// Lines on different pages are never next to each other, whatever their `y`
/// says. The top of a page has a small `y` and the foot of the one before has a
/// large one, so without this they read as one paragraph running backwards.
#[test]
fn the_foot_of_one_page_does_not_run_into_the_top_of_the_next() {
    let first = Page::letter(vec![
        Run::new(108.0, 71.0, "INT. KITCHEN - DAY"),
        Run::new(108.0, 683.0, "She waits by the window."),
    ]);
    let second = Page::letter(vec![Run::new(108.0, 71.0, "He leaves without a word.")]);
    let screenplay = printed::read(&[first, second], &Detection::printed());
    let action: Vec<&str> = screenplay
        .elements
        .iter()
        .filter(|element| element.kind == Kind::Action)
        .map(|element| element.text.as_str())
        .collect();
    assert_eq!(action, vec!["She waits by the window.", "He leaves without a word."]);
}
