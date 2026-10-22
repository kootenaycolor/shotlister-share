//! Laying a screenplay on pages, and what that costs in eighths.
//!
//! The measurements here are the trade's, not ours, and the tests are written
//! against them rather than against whatever the code happens to do: fifty-five
//! lines to a page, a cue at twenty-two characters in, dialogue at ten, and a
//! page divided into eight. A scene's length only means anything because
//! everybody's page is the same page.

use shotlister_engine::pages::{eighths_for, lay_out, Extent, LINES_PER_PAGE};
use shotlister_engine::screenplay::{read, Kind};

fn laid_out(text: &str) -> shotlister_engine::pages::Paginated {
    lay_out(&read(text))
}

const SCENE: &str = "\
INT. KITCHEN - DAY

Melissa stands at the window. The kettle boils.

MELISSA
(quietly)
You're up early.

JIMMY
Couldn't sleep.
";

#[test]
fn every_line_sits_where_the_standard_puts_it() {
    let laid = laid_out(SCENE);
    let page = &laid.pages[0];
    let found: Vec<(usize, usize, &str)> = page
        .lines
        .iter()
        .map(|line| (line.row, line.indent, line.text.as_str()))
        .collect();
    assert_eq!(
        found,
        vec![
            (0, 0, "INT. KITCHEN - DAY"),
            (2, 0, "Melissa stands at the window. The kettle boils."),
            (4, 22, "MELISSA"),
            (5, 16, "(quietly)"),
            (6, 10, "You're up early."),
            (8, 22, "JIMMY"),
            (9, 10, "Couldn't sleep."),
        ]
    );
}

#[test]
fn a_page_does_not_open_with_a_gap() {
    let laid = laid_out(SCENE);
    assert_eq!(laid.pages[0].lines[0].row, 0);
}

#[test]
fn a_line_too_long_for_its_measure_is_wrapped_at_it() {
    // Dialogue runs forty characters. Nothing may be wider than its column, or
    // two people's page counts stop agreeing.
    let text = "INT. A - DAY\n\nMELISSA\nI have been thinking about this for a very long time and I am not going to change my mind now.\n";
    let laid = laid_out(text);
    for line in &laid.pages[0].lines {
        let width = match line.kind {
            Kind::Dialogue => 40,
            Kind::Character => 38,
            _ => 60,
        };
        assert!(
            line.text.chars().count() <= width,
            "{:?} is wider than its column",
            line.text
        );
    }
}

#[test]
fn what_the_writer_wrote_is_never_rewritten_by_the_wrapping() {
    let text = "INT. A - DAY\n\nMELISSA\nI have been thinking about this for a very long time and I am not going to change my mind now.\n";
    let laid = laid_out(text);
    let said: Vec<&str> = laid.pages[0]
        .lines
        .iter()
        .filter(|line| line.kind == Kind::Dialogue)
        .map(|line| line.text.as_str())
        .collect();
    assert_eq!(
        said.join(" "),
        "I have been thinking about this for a very long time and I am not going to change my mind now."
    );
}

// ---- where a page may not break -----------------------------------------

/// A scene of `action` paragraphs, each one line, to fill a page to order.
fn filler(lines: usize) -> String {
    let mut text = String::from("INT. KITCHEN - DAY\n\n");
    for at in 0..lines {
        text.push_str(&format!("Beat {at}.\n\n"));
    }
    text
}

#[test]
fn a_scene_heading_never_sits_alone_at_the_foot_of_a_page() {
    // Fill a page to within a line or two of the bottom, then start a scene.
    for tail in 0..4 {
        let mut text = filler(26 - tail);
        text.push_str("INT. GARAGE - NIGHT\n\nHe parks.\n");
        let laid = laid_out(&text);

        for page in &laid.pages {
            let Some(heading) = page
                .lines
                .iter()
                .find(|line| line.kind == Kind::SceneHeading)
            else {
                continue;
            };
            let under = page
                .lines
                .iter()
                .filter(|line| line.row > heading.row)
                .count();
            // Either it is the only thing that would fit and it moved, or it
            // brought company.
            assert!(
                under >= 2 || heading.row + 2 < LINES_PER_PAGE,
                "a heading on page {} at row {} has {under} lines under it",
                page.number,
                heading.row
            );
        }
    }
}

#[test]
fn a_cue_never_parts_from_the_first_thing_they_say() {
    for tail in 0..6 {
        let mut text = filler(26 - tail);
        text.push_str("MELISSA\nYou're up early.\nAnd it is a very long speech besides.\n");
        let laid = laid_out(&text);

        for page in &laid.pages {
            let Some(cue) = page
                .lines
                .iter()
                .find(|line| line.kind == Kind::Character && !line.added)
            else {
                continue;
            };
            assert!(
                page.lines.iter().any(|line| line.row > cue.row),
                "a cue was left at the foot of page {}",
                page.number
            );
        }
    }
}

#[test]
fn a_speech_broken_by_a_page_says_so_at_both_ends() {
    let mut text = filler(24);
    text.push_str("MELISSA\n");
    for at in 0..12 {
        text.push_str(&format!("Line {at} of what she says, at some length. "));
    }
    text.push('\n');
    let laid = laid_out(&text);
    assert!(laid.pages.len() >= 2);

    let bottom = laid.pages[0].lines.last().unwrap();
    assert_eq!(bottom.text, "(MORE)");
    assert!(bottom.added, "the paginator's word, not the writer's");

    let top = &laid.pages[1].lines[0];
    assert_eq!(top.text, "MELISSA (CONT'D)");
    assert!(top.added);
    assert_eq!(top.indent, 22, "a carried cue is still a cue");
}

#[test]
fn a_carried_cue_does_not_end_up_wearing_two_sets_of_brackets() {
    let mut text = filler(24);
    text.push_str("MELISSA (V.O.)\n");
    for at in 0..12 {
        text.push_str(&format!("Line {at} of what she says, at some length. "));
    }
    text.push('\n');
    let laid = laid_out(&text);
    let top = &laid.pages[1].lines[0];
    assert_eq!(top.text, "MELISSA (CONT'D)");
}

#[test]
fn the_words_the_paginator_adds_are_the_only_ones_flagged() {
    let laid = laid_out(SCENE);
    assert!(laid.pages[0].lines.iter().all(|line| !line.added));
}

#[test]
fn a_page_break_the_writer_asked_for_is_taken() {
    let laid = laid_out("INT. A - DAY\n\nShe waits.\n\n===\n\nINT. B - DAY\n\nHe leaves.\n");
    assert_eq!(laid.pages.len(), 2);
    assert_eq!(laid.pages[1].lines[0].text, "INT. B - DAY");
}

#[test]
fn nothing_at_all_makes_no_pages() {
    let laid = laid_out("");
    assert!(laid.pages.is_empty());
    assert_eq!(laid.pages_long(), 0);
}

// ---- eighths -------------------------------------------------------------

#[test]
fn a_page_is_eight_eighths_and_a_scene_is_never_nothing() {
    assert_eq!(eighths_for(LINES_PER_PAGE), 8);
    assert_eq!(eighths_for(LINES_PER_PAGE * 2), 16);
    assert_eq!(eighths_for(1), 1, "a scene that exists is an eighth");
    assert_eq!(eighths_for(0), 1);
}

#[test]
fn eighths_read_the_way_an_ad_writes_them() {
    let at = |eighths| Extent {
        scene: 0,
        label: String::new(),
        starts_on: 1,
        lines: 0,
        eighths,
    };
    assert_eq!(at(1).length(), "1/8");
    assert_eq!(at(5).length(), "5/8");
    assert_eq!(at(8).length(), "1");
    assert_eq!(at(16).length(), "2");
    assert_eq!(at(19).length(), "2 3/8");
    assert_eq!(at(9).length(), "1 1/8");
}

#[test]
fn a_scene_knows_how_long_it_is_and_where_it_starts() {
    let laid = laid_out(SCENE);
    let extent = laid.extent_of(0).expect("the one scene");
    assert_eq!(extent.starts_on, 1);
    // Ten rows of a fifty-five row page: one and a half eighths, rounded.
    assert_eq!(extent.lines, 10);
    assert_eq!(extent.eighths, 1);
    assert_eq!(extent.length(), "1/8");
}

#[test]
fn a_scene_of_about_two_and_a_third_pages_measures_as_one() {
    // 128 rows out of 55 to a page is 2.33 pages, which is 18.6 eighths, which
    // an AD writes as two and three eighths.
    assert_eq!(eighths_for(128), 19);
    let extent = Extent {
        scene: 0,
        label: "34".to_string(),
        starts_on: 12,
        lines: 128,
        eighths: eighths_for(128),
    };
    assert_eq!(extent.length(), "2 3/8");
}

#[test]
fn a_long_scene_is_measured_across_every_page_it_runs_over() {
    let laid = laid_out(&filler(60));
    let extent = laid.extent_of(0).unwrap();
    assert!(laid.pages.len() >= 2, "it has to actually span pages");
    assert!(
        extent.lines > LINES_PER_PAGE,
        "a scene running over a break measures the whole of what it occupies"
    );
    let (first, last) = laid.pages_of(0).unwrap();
    assert_eq!(first, 1);
    assert_eq!(last, laid.pages.len());
}

#[test]
fn each_scene_is_measured_and_placed_in_its_own_right() {
    let text = format!("{}\nINT. GARAGE - NIGHT\n\nHe parks.\n", filler(30));
    let laid = laid_out(&text);
    assert_eq!(laid.scenes.len(), 2);
    let second = &laid.scenes[1];
    assert!(second.starts_on >= 2, "it starts on a later page");
    assert_eq!(second.length(), "1/8");
}

#[test]
fn what_is_not_printed_is_not_measured() {
    // Sections and synopses are the writer's scaffolding; they take up no page
    // and so cannot lengthen a scene.
    let bare = laid_out("INT. A - DAY\n\nShe waits.\n");
    let noted = laid_out("# Act One\n\nINT. A - DAY\n\n= she finally says it\n\nShe waits.\n");
    assert_eq!(
        bare.extent_of(0).unwrap().lines,
        noted.extent_of(0).unwrap().lines
    );
}

// ---- lines somebody else's margin broke ----------------------------------

#[test]
fn a_paragraph_already_wrapped_by_somebody_elses_margin_is_put_back_together() {
    // Typed to a seventy-character terminal, then laid out to sixty. Wrapping
    // the wrap gives ragged half-lines — and, worse, invents rows, which is
    // what eighths are counted from.
    let text = "INT. A - DAY\n\n\
Sunlight through the high window. FRANK walks the length of it, past\n\
doors that do not open, counting them the way he has counted them every\n\
morning for eleven years.\n";
    let laid = laid_out(text);
    let action: Vec<&str> = laid.pages[0]
        .lines
        .iter()
        .filter(|line| line.kind == Kind::Action)
        .map(|line| line.text.as_str())
        .collect();

    assert_eq!(action.len(), 3, "sixty characters of measure, not five: {action:?}");
    for line in &action[..action.len() - 1] {
        assert!(
            line.chars().count() > 40,
            "a line broken by the margin should reach it: {line:?}"
        );
    }
    assert_eq!(
        action.join(" "),
        "Sunlight through the high window. FRANK walks the length of it, past \
         doors that do not open, counting them the way he has counted them \
         every morning for eleven years."
    );
}

#[test]
fn short_lines_the_writer_meant_are_left_alone() {
    // The floor that stops a run of deliberately short lines — all equally
    // short, so all equally "long" — from being glued into a paragraph.
    let laid = laid_out("INT. A - DAY\n\nShe waits.\nAnd waits.\nAnd waits.\n");
    let action: Vec<&str> = laid.pages[0]
        .lines
        .iter()
        .filter(|line| line.kind == Kind::Action)
        .map(|line| line.text.as_str())
        .collect();
    assert_eq!(action, vec!["She waits.", "And waits.", "And waits."]);
}

#[test]
fn putting_a_paragraph_back_together_changes_what_a_scene_measures() {
    // The reason it matters at all: rows are what eighths come from, so a
    // paragraph read as five lines instead of three would have somebody
    // scheduling a day around the difference.
    let wrapped = "INT. A - DAY\n\n\
Sunlight through the high window. FRANK walks the length of it, past\n\
doors that do not open, counting them the way he has counted them every\n\
morning for eleven years.\n";
    let whole = "INT. A - DAY\n\n\
Sunlight through the high window. FRANK walks the length of it, past \
doors that do not open, counting them the way he has counted them every \
morning for eleven years.\n";
    assert_eq!(
        laid_out(wrapped).extent_of(0).unwrap().lines,
        laid_out(whole).extent_of(0).unwrap().lines
    );
}
