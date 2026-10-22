//! Taking a new draft in.
//!
//! The law is *report, never invent — and never destroy*, and this is where it
//! either holds or does not. So most of what is pinned here is what **fails to
//! happen**: that weighing a draft changes nothing, that a scene the script has
//! dropped keeps its shots, that nothing is taken which was not ticked, and
//! that the sentences a person reads before agreeing are the plan's own rather
//! than a second description of it.

use shotlister_engine::doc::f;
use shotlister_engine::revisions::{Revision, Taking, CAST_COLUMN};
use shotlister_engine::screenplay::read;
use shotlister_engine::{DeviceId, Doc, Id, Value};

fn project() -> Doc {
    let mut doc = Doc::new(DeviceId(1));
    // A project's lists live on its own record, so there has to be one.
    doc.create_project("Call Her Back");
    for (number, location) in [("1", "KITCHEN"), ("2", "BALCONY"), ("9", "PIER")] {
        let scene = doc.create_scene(number);
        doc.set(scene, f::LOCATION, Value::text(location));
        doc.set(scene, f::INT_EXT, Value::text("INT"));
        doc.set(scene, f::TIME_OF_DAY, Value::text("DAY"));
    }
    doc
}

/// A draft that keeps 1 and 2, adds 3, and has forgotten 9.
const DRAFT: &str = "\
1    INT. KITCHEN - NIGHT

She waits.

MELISSA
You're up early.

2    INT. BALCONY - DAY

He smokes.

3    INT. GARAGE - NIGHT

The car is gone.
";

fn revision() -> Revision {
    Revision {
        id: Id::new(),
        name: "Revision (8/20/26, 11:56 AM)".to_string(),
        filename: "DRAFTJP.pdf".to_string(),
        imported_at: "2026-08-20T11:56:00Z".to_string(),
        hash: "abc123".to_string(),
    }
}

fn everything(screenplay: &shotlister_engine::Screenplay) -> Taking {
    Taking {
        scenes: (0..screenplay.scenes.len()).collect(),
        cast: vec!["MELISSA".to_string()],
        archive_omitted: true,
        ..Default::default()
    }
}

#[test]
fn weighing_a_draft_changes_absolutely_nothing() {
    let doc = project();
    let screenplay = read(DRAFT);
    let before = doc.scenes_in_order().len();

    let plan = doc.plan_revision(&screenplay, &everything(&screenplay));

    assert_eq!(plan.linked, vec!["1", "2"]);
    assert_eq!(plan.created, vec!["3"]);
    assert_eq!(plan.archived, vec![("9".to_string(), 0)]);
    assert_eq!(plan.cast_added, vec!["MELISSA"]);
    assert_eq!(doc.scenes_in_order().len(), before);
    assert!(doc.revisions().is_empty());
}

#[test]
fn the_confirm_screen_is_the_plans_own_words() {
    let doc = project();
    let screenplay = read(DRAFT);
    let said = doc
        .plan_revision(&screenplay, &everything(&screenplay))
        .sentences();
    assert_eq!(
        said,
        vec![
            "2 existing scenes will be linked to the new revision.",
            "1 new scene will be created.",
            "1 existing scene is no longer in the script and will be moved to archived scenes, keeping 0 shots on it.",
            "1 character will be created as an option in the Cast column of your shot lists.",
        ]
    );
}

#[test]
fn taking_it_does_what_the_plan_said_it_would() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = everything(&screenplay);
    let planned = doc.plan_revision(&screenplay, &taking);

    let done = doc.take_revision(&screenplay, &taking, &revision());

    assert_eq!(planned, done, "the plan and the doing are one computation");
    assert!(doc.scene_numbered("3").is_some());
    assert_eq!(doc.revisions().len(), 1);
}

#[test]
fn a_scene_the_script_has_dropped_keeps_every_shot_on_it() {
    let mut doc = project();
    let gone = doc.scene_numbered("9").unwrap();
    let (shot, _) = doc.add_shot_to_scene(gone);
    doc.set(shot, f::DESCRIPTION, Value::text("The one good shot"));

    let screenplay = read(DRAFT);
    let taking = everything(&screenplay);
    let plan = doc.plan_revision(&screenplay, &taking);
    assert_eq!(plan.archived, vec![("9".to_string(), 1)], "and it says so first");

    doc.take_revision(&screenplay, &taking, &revision());

    let still = doc.scene_numbered("9").expect("the scene is still here");
    assert!(doc.is_archived(still));
    assert_eq!(doc.placements_in_scene(still).len(), 1, "with its work on it");
}

#[test]
fn nothing_is_archived_unless_somebody_asks() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = Taking {
        archive_omitted: false,
        ..everything(&screenplay)
    };

    let plan = doc.plan_revision(&screenplay, &taking);
    assert!(plan.archived.is_empty());
    // Still said out loud, so it is never a surprise.
    assert_eq!(plan.left_alone, vec![("9".to_string(), 0)]);
    assert!(plan.sentences().iter().any(|said| said.contains("Nothing will happen")));

    doc.take_revision(&screenplay, &taking, &revision());
    assert!(!doc.is_archived(doc.scene_numbered("9").unwrap()));
}

#[test]
fn only_what_is_ticked_is_taken() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = Taking {
        // Scene 3 is the third; leave it out.
        scenes: vec![0, 1],
        cast: Vec::new(),
        archive_omitted: false,
        ..Default::default()
    };
    let plan = doc.plan_revision(&screenplay, &taking);
    assert!(plan.created.is_empty());

    doc.take_revision(&screenplay, &taking, &revision());
    assert!(doc.scene_numbered("3").is_none(), "an unticked scene is not created");
    assert!(doc.cast_list().is_empty(), "and no cast arrives on its own");
}

#[test]
fn a_scene_that_stayed_is_brought_up_to_the_new_draft() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = everything(&screenplay);
    doc.take_revision(&screenplay, &taking, &revision());

    // The draft moved scene 1 from day to night.
    let scene = doc.scene_numbered("1").unwrap();
    let record = doc.get(scene).unwrap();
    assert_eq!(record.text(f::TIME_OF_DAY), Some("NIGHT"));
    assert_eq!(record.text(f::LOCATION), Some("KITCHEN"));
}

#[test]
fn every_scene_taken_is_linked_to_the_revision_it_came_from() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = everything(&screenplay);
    doc.take_revision(&screenplay, &taking, &revision());

    let landed = doc.latest_revision().unwrap();
    for number in ["1", "2", "3"] {
        let scene = doc.scene_numbered(number).unwrap();
        assert_eq!(doc.revision_of(scene), Some(landed.id), "scene {number}");
    }
}

#[test]
fn the_characters_ticked_become_a_list_and_a_column_to_offer_them_from() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    assert_eq!(doc.cast_list(), vec!["MELISSA"]);
    let field = doc.cast_field().expect("a Cast column to offer them from");
    assert_eq!(doc.custom_column_kind(&field).as_deref(), Some("multi"));
    // Found by its label, since the slug is generated per project.
    assert!(field != CAST_COLUMN, "the field is a slug, not the word Cast");
}

#[test]
fn somebody_already_on_the_list_is_not_added_twice() {
    let mut doc = project();
    doc.add_column(CAST_COLUMN, "multi");
    let field = doc.cast_field().unwrap();
    doc.set_vocabulary(&field, &["MELISSA"]);
    let screenplay = read(DRAFT);

    let plan = doc.plan_revision(&screenplay, &everything(&screenplay));
    assert!(plan.cast_added.is_empty());
    assert!(!plan.sentences().iter().any(|said| said.contains("character")));
}

#[test]
fn a_whole_draft_is_one_thing_to_take_back() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let before = doc.scenes_in_order().len();

    let depth = doc.undo_depth();
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());
    assert_eq!(doc.undo_depth(), depth + 1, "not one step per scene");
    assert_eq!(doc.scenes_in_order().len(), before + 1);

    doc.undo();

    // Undo restores what records held rather than removing the records, which
    // is the engine's long-standing behaviour — so the questions worth asking
    // are the ones a person would ask.
    assert!(doc.scene_numbered("3").is_none(), "the new scene is gone");
    assert!(doc.revisions().is_empty(), "and so is the draft it came from");
    assert!(!doc.is_archived(doc.scene_numbered("9").unwrap()), "and 9 is back");
}

// ---- the list of drafts --------------------------------------------------

#[test]
fn the_project_keeps_every_draft_newest_first() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = everything(&screenplay);

    for (name, at) in [
        ("Revision (8/17/26, 11:58 AM)", "2026-08-17T11:58:00Z"),
        ("Revision (8/20/26, 11:56 AM)", "2026-08-20T11:56:00Z"),
    ] {
        doc.take_revision(
            &screenplay,
            &taking,
            &Revision {
                id: Id::new(),
                name: name.to_string(),
                filename: "DRAFTJP.pdf".to_string(),
                imported_at: at.to_string(),
                hash: "abc".to_string(),
            },
        );
    }

    let kept = doc.revisions();
    assert_eq!(kept.len(), 2);
    assert_eq!(kept[0].name, "Revision (8/20/26, 11:56 AM)");
    assert_eq!(doc.latest_revision().unwrap().name, kept[0].name);
    assert_eq!(kept[0].filename, "DRAFTJP.pdf");
}

#[test]
fn which_draft_is_latest_is_decided_by_when_it_landed() {
    // Not by which record happens to sit later in the log: two machines
    // importing on the same day have to agree about this.
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = everything(&screenplay);

    for at in ["2026-08-20T11:56:00Z", "2026-08-17T11:58:00Z"] {
        doc.take_revision(
            &screenplay,
            &taking,
            &Revision {
                id: Id::new(),
                name: at.to_string(),
                filename: "a.pdf".to_string(),
                imported_at: at.to_string(),
                hash: "abc".to_string(),
            },
        );
    }
    assert_eq!(doc.latest_revision().unwrap().name, "2026-08-20T11:56:00Z");
}

#[test]
fn a_draft_can_be_renamed_and_nothing_else_about_it_can() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    let landed = doc.latest_revision().unwrap();
    doc.rename_revision(landed.id, "First white");

    let again = doc.revision(landed.id).unwrap();
    assert_eq!(again.name, "First white");
    assert_eq!(again.filename, landed.filename, "where it came from is a fact");
    assert_eq!(again.imported_at, landed.imported_at);
}

// ---- what a scene now remembers -----------------------------------------
//
// All three of these were worked out by the reader and then dropped on the
// floor. Each is cheap at import and expensive afterwards: the length means
// laying the whole screenplay out again, and the cast means reading it again.

#[test]
fn a_scene_remembers_how_long_it_is() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    let scene = doc.scene_numbered("1").unwrap();
    assert!(doc.scene_eighths(scene).is_some());
    assert_eq!(doc.scene_length(scene).as_deref(), Some("1/8"));
}

#[test]
fn a_scene_remembers_the_page_it_starts_on() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    let scene = doc.scene_numbered("1").unwrap();
    let record = doc.get(scene).unwrap();
    assert_eq!(record.get(f::SCRIPT_PAGE).and_then(|v| v.as_int()), Some(1));
}

#[test]
fn a_scene_remembers_who_speaks_in_it() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    // Melissa speaks in scene 1 only.
    assert_eq!(doc.scene_cast(doc.scene_numbered("1").unwrap()), vec!["MELISSA"]);
    assert!(doc.scene_cast(doc.scene_numbered("2").unwrap()).is_empty());
}

#[test]
fn somebody_unticked_may_not_arrive_on_a_scene_through_another_door() {
    // The cast list is a person's choice. Pruning it and then finding the same
    // names scene by scene would make the pruning meaningless.
    let mut doc = project();
    let screenplay = read(DRAFT);
    let taking = Taking {
        scenes: (0..screenplay.scenes.len()).collect(),
        cast: Vec::new(),
        archive_omitted: false,
        ..Default::default()
    };
    doc.take_revision(&screenplay, &taking, &revision());
    assert!(doc.scene_cast(doc.scene_numbered("1").unwrap()).is_empty());
}

// ---- the dials the project keeps ----------------------------------------

#[test]
fn a_project_reads_scripts_the_way_it_was_told_to_last_time() {
    use shotlister_engine::screenplay::Detection;

    let mut doc = project();
    // Untouched, a project reads a script the way a printed one wants reading.
    assert!(doc.detection().must_have_a_number);

    doc.set_detection(&Detection {
        must_have_a_number: false,
        ignore_duplicate_numbers: true,
        find_sub_slugs: false,
        must_contain: vec!["INT".to_string(), "EXT".to_string()],
        never_contains: vec!["OMITTED".to_string()],
    });

    let kept = doc.detection();
    assert!(!kept.must_have_a_number);
    assert!(!kept.find_sub_slugs);
    assert!(kept.ignore_duplicate_numbers);
    assert_eq!(kept.must_contain, vec!["INT", "EXT"]);
    assert_eq!(kept.never_contains, vec!["OMITTED"]);
}

#[test]
fn a_film_that_prints_oddly_only_has_to_be_explained_once() {
    // The point of keeping them: the next revision of the same film reads the
    // same way without being tuned again.
    use shotlister_engine::screenplay::{read_with, Detection};

    let mut doc = project();
    doc.set_detection(&Detection {
        never_contains: vec!["OMITTED".to_string()],
        ..Detection::printed()
    });

    let odd = "1  INT. KITCHEN - DAY\n\nOMITTED\n\nShe waits.\n";
    let screenplay = read_with(odd, &doc.detection());
    assert!(!screenplay
        .elements
        .iter()
        .any(|element| element.text.contains("OMITTED")));
}

#[test]
fn a_slug_the_script_wrote_oddly_is_not_rebuilt_into_one_it_did_not() {
    // His own draft opens on this, and it has no INT and no time of day.
    // Rebuilding a heading out of its parts invented both — `INT. OVER BLACK
    // … - DAY` — which is a slug line nobody wrote.
    // A scene arriving from the script rather than one the project already had
    // an INT and a time of day recorded for — where keeping those is right.
    let mut doc = project();
    let draft = "77  OVER BLACK - THE SOUND OF A ROTARY PHONE RINGING.\n\nA phone rings.\n";
    let screenplay = read(draft);
    let taking = Taking {
        scenes: vec![0],
        ..Default::default()
    };
    doc.take_revision(&screenplay, &taking, &revision());

    let scene = doc.scene_numbered("77").unwrap();
    assert_eq!(
        doc.scene_heading(scene).as_deref(),
        Some("OVER BLACK - THE SOUND OF A ROTARY PHONE RINGING.")
    );
}

#[test]
fn an_ordinary_slug_is_still_built_back_up_from_its_parts() {
    // Which is what a scene somebody made in the app needs, and what keeps a
    // heading following the location when it is edited.
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    let scene = doc.scene_numbered("1").unwrap();
    assert_eq!(doc.scene_heading(scene).as_deref(), Some("INT. KITCHEN - NIGHT"));

    // **A person's edit rewrites the slug; a draft being conformed does not.**
    // This used to be one path and `set` did both, which is how Ref 257's
    // conforming came to rewrite his script's own words. `set_scene_field` is
    // the door a person types through.
    doc.set_scene_field(scene, f::LOCATION, Value::text("GARAGE"));
    assert_eq!(
        doc.scene_heading(scene).as_deref(),
        Some("INT. GARAGE - NIGHT"),
        "the heading has to follow the location, not the words it arrived with"
    );

    // And the other door leaves the printed slug exactly as it is.
    doc.set(scene, f::TIME_OF_DAY, Value::text("EVENING"));
    assert_eq!(
        doc.scene_heading(scene).as_deref(),
        Some("INT. GARAGE - NIGHT"),
        "conforming a time of day must never rewrite what the script printed"
    );
}

/// **A scene lands where its number says**, not on the end of the list.
///
/// His report, 2026-08-22: he took a draft running up to 20 into a project that
/// already held the thirties, chose not to archive them, and the film read
/// 33, 34, 35, 54, 1, 2, 3… because every new scene was appended.
#[test]
fn a_new_scene_lands_in_number_order() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Sorting");
    for number in ["33", "34", "54"] {
        doc.create_scene(number);
    }
    // A draft's worth of earlier scenes, taken in after the fact.
    for number in ["1", "2", "20"] {
        doc.create_scene(number);
    }
    // And one that belongs in the middle of what is already there.
    doc.create_scene("35");

    let read: Vec<String> = doc
        .scenes_in_order()
        .iter()
        .filter_map(|id| doc.get(*id))
        .map(|r| r.text(f::NUMBER).unwrap_or_default().to_string())
        .collect();
    assert_eq!(read, ["1", "2", "20", "33", "34", "35", "54"], "{read:?}");
}

/// Two scenes wearing the same number is not a thing the app can stop — a draft
/// can print one twice — and it must not send the ordering into a spin.
#[test]
fn a_repeated_number_still_orders() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Doubles");
    for number in ["7", "7", "8"] {
        doc.create_scene(number);
    }
    let read: Vec<String> = doc
        .scenes_in_order()
        .iter()
        .filter_map(|id| doc.get(*id))
        .map(|r| r.text(f::NUMBER).unwrap_or_default().to_string())
        .collect();
    assert_eq!(read, ["7", "7", "8"], "{read:?}");
}

/// **Putting a film that is already out of order back in order.**
///
/// New scenes land in their place now, but a project that took a draft in
/// before that was true is already jumbled and nothing moves it — his report
/// of a film reading 33, 34, 35, 54, 1, 2, 3. Asked for, never automatic.
#[test]
fn scenes_can_be_put_back_in_number_order() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Jumbled");
    // Built the way the old create_scene built them: appended, in the order
    // they happened to arrive.
    for (at, number) in ["33", "34", "54", "1", "2", "20"].iter().enumerate() {
        let scene = doc.create_scene(number);
        doc.set(scene, f::ORDER, Value::Float(at as f64 * 1024.0));
    }
    let before: Vec<String> = doc
        .scenes_in_order()
        .iter()
        .filter_map(|id| doc.get(*id))
        .map(|r| r.text(f::NUMBER).unwrap_or_default().to_string())
        .collect();
    assert_eq!(before, ["33", "34", "54", "1", "2", "20"], "the mess is set up");

    doc.sort_scenes_by_number();

    let after: Vec<String> = doc
        .scenes_in_order()
        .iter()
        .filter_map(|id| doc.get(*id))
        .map(|r| r.text(f::NUMBER).unwrap_or_default().to_string())
        .collect();
    assert_eq!(after, ["1", "2", "20", "33", "34", "54"], "{after:?}");
}

/// A scene with no number goes to the end: there is nothing to sort it by, and
/// leaving it in the middle of a run it has no claim on would be worse.
#[test]
fn a_scene_with_no_number_sorts_to_the_end() {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Nameless");
    let blank = doc.create_scene("");
    doc.set(blank, f::ORDER, Value::Float(0.0));
    let seven = doc.create_scene("7");
    doc.set(seven, f::ORDER, Value::Float(1024.0));

    doc.sort_scenes_by_number();

    let after: Vec<String> = doc
        .scenes_in_order()
        .iter()
        .filter_map(|id| doc.get(*id))
        .map(|r| r.text(f::NUMBER).unwrap_or_default().to_string())
        .collect();
    assert_eq!(after, ["7", ""], "{after:?}");
}

// ---------------------------------------------------------------------------
// A scene that moved to a new number — Ref 241.
//
// The import compares by number, so a scene that went from 9 to 11 reads as one
// scene gone and one scene new: the old one keeps its shots and nobody ever
// looks at them again. These pin the three things that have to be true — it
// finds the pair, it does nothing unless ticked, and it will not guess.

/// A project whose scene 9 has words under it and shots on it.
fn film_with_a_scene_worth_moving() -> (Doc, Id) {
    let mut doc = project();
    let nine = doc.scene_numbered("9").expect("scene 9");
    doc.set(nine, f::LOCATION, Value::text("PIER"));
    doc.set(nine, f::INT_EXT, Value::text("INT"));
    doc.set(
        nine,
        f::SCRIPT,
        Value::text("He walks to the end of the pier and stands there a long time."),
    );
    for _ in 0..3 {
        doc.add_shot_to_scene(nine);
    }
    (doc, nine)
}

/// The same scene, printed at a different number.
const RENUMBERED: &str = "\
11   INT. PIER - DAY

He walks to the end of the pier and stands there a long time.
";

#[test]
fn a_scene_printed_at_a_new_number_is_offered_as_a_move() {
    let (doc, nine) = film_with_a_scene_worth_moving();
    let screenplay = read(RENUMBERED);
    let taking = Taking {
        scenes: vec![0],
        ..Default::default()
    };

    let found = doc.moved_scenes(&screenplay, &taking);
    assert_eq!(found.len(), 1, "one pair: {found:?}");
    assert_eq!(found[0].scene, nine);
    assert_eq!(found[0].from, "9");
    assert_eq!(found[0].to, "11");
    assert_eq!(found[0].shots, 3, "how much would come with it");

    // **Found is all it does.** Without a tick, the plan is exactly what it
    // always was: a new scene, and the old one left alone.
    let plan = doc.plan_revision(&screenplay, &taking);
    assert!(plan.moved.is_empty());
    assert_eq!(plan.created, vec!["11".to_string()]);
    assert!(plan.left_alone.iter().any(|(number, _)| number == "9"));
}

#[test]
fn ticking_the_move_carries_the_shots_across_instead_of_stranding_them() {
    let (mut doc, nine) = film_with_a_scene_worth_moving();
    let screenplay = read(RENUMBERED);
    let taking = Taking {
        scenes: vec![0],
        moves: vec![0],
        archive_omitted: true,
        ..Default::default()
    };

    let plan = doc.plan_revision(&screenplay, &taking);
    assert_eq!(plan.moved, vec![("9".to_string(), "11".to_string(), 3)]);
    // Neither number is loose: 11 is not a new scene, and 9 is not gone.
    //
    // Scenes 1 and 2 *are* archived, because this draft is one scene long and
    // does not mention them — which is right, and is the reason this asserts
    // about 9 rather than about the list being empty. My first version
    // asserted the latter and read like the fix failing.
    assert!(plan.created.is_empty(), "{plan:?}");
    assert!(
        !plan.archived.iter().any(|(number, _)| number == "9"),
        "9 moved; it did not go: {plan:?}"
    );
    assert!(
        plan.sentences().iter().any(|said| said.contains("9 → 11")),
        "the confirm screen says which: {:?}",
        plan.sentences()
    );

    doc.take_revision(&screenplay, &taking, &revision());

    // The same record, wearing the script's new number, with its shots still
    // on it — and no second scene beside it.
    assert_eq!(doc.scene_numbered("11"), Some(nine));
    assert_eq!(doc.placements_in_scene(nine).len(), 3);
    assert_eq!(doc.scene_numbered("9"), None);
    assert!(!doc.is_archived(nine));
}

#[test]
fn it_will_not_guess_when_the_scene_is_not_plainly_the_same() {
    let (doc, _) = film_with_a_scene_worth_moving();

    // A different location is a different scene, however alike the words.
    let elsewhere = read("11   INT. CAR PARK - DAY\n\nHe walks to the end of the pier and stands there a long time.\n");
    assert!(doc
        .moved_scenes(&elsewhere, &Taking { scenes: vec![0], ..Default::default() })
        .is_empty());

    // Different words are a different scene, however alike the heading.
    let rewritten = read("11   INT. PIER - DAY\n\nShe drives away without saying anything to him at all.\n");
    assert!(doc
        .moved_scenes(&rewritten, &Taking { scenes: vec![0], ..Default::default() })
        .is_empty());

    // **And nothing written under either is not a match**, which is the case
    // that would otherwise pair every scene in a house with every other.
    let mut bare = project();
    let two = bare.scene_numbered("2").expect("scene 2");
    bare.add_shot_to_scene(two);
    let empty = read("11   INT. BALCONY - DAY\n");
    assert!(bare
        .moved_scenes(&empty, &Taking { scenes: vec![0], ..Default::default() })
        .is_empty());
}

// ---- a draft that renumbers from the top — Ref 488 -------------------------

/// **The white-draft shape**, which is what went wrong on Call Her Back.
///
/// A rewrite does not move one scene to a spare number; it renumbers from the
/// first page, so every scene after an insertion shifts by one and *no number is
/// ever free*. The move finder used to consider only project scenes whose number
/// the draft did not bring — which, on a draft like this, is none of them. So it
/// found nothing, the import linked scene 20 to scene 20 because they share a
/// label, and his synopses and his shots stayed a slot behind all the way to the
/// end of the film.
fn film_before_the_renumber() -> Doc {
    let mut doc = Doc::new(DeviceId(1));
    doc.create_project("Call Her Back");
    for (number, place, body, synopsis) in [
        (
            "19",
            "GATES",
            "She stands at the gates and does not go in.",
            "Anya hesitates at the gates",
        ),
        (
            "20",
            "POOL",
            "The body floats face down in an ocean of gore.",
            "The body in the pool",
        ),
        (
            "21",
            "BEDROOM",
            "He pushes in at the windows, mirroring the opening.",
            "Push in at the windows",
        ),
    ] {
        let scene = doc.create_scene(number);
        doc.set(scene, f::LOCATION, Value::text(place));
        doc.set(scene, f::INT_EXT, Value::text("INT"));
        doc.set(scene, f::SCRIPT, Value::text(body));
        doc.set(scene, f::DESCRIPTION, Value::text(synopsis));
        doc.add_shot_to_scene(scene);
        doc.add_shot_to_scene(scene);
    }
    doc
}

/// The same three scenes, with one inserted in front of them, so every number
/// after the insertion has shifted by one.
const SHIFTED_ALONG: &str = "\
19   INT. GATES - DAY

She stands at the gates and does not go in.

20   INT. FRONT DOOR - DAY

Blood on the glass. This scene is new to this draft.

21   INT. POOL - DAY

The body floats face down in an ocean of gore.

22   INT. BEDROOM - DAY

He pushes in at the windows, mirroring the opening.
";

#[test]
fn a_draft_that_renumbers_from_the_top_offers_every_shift() {
    let doc = film_before_the_renumber();
    let screenplay = read(SHIFTED_ALONG);
    let taking = Taking {
        scenes: (0..screenplay.scenes.len()).collect(),
        ..Default::default()
    };

    let moves = doc.moved_scenes(&screenplay, &taking);
    let pairs: Vec<(String, String)> = moves
        .iter()
        .map(|m| (m.from.clone(), m.to.clone()))
        .collect();
    // 19 stayed put. The two after the insertion each shifted by one, and both
    // are offered — nothing here is assumed.
    assert_eq!(
        pairs,
        vec![
            ("20".to_string(), "21".to_string()),
            ("21".to_string(), "22".to_string())
        ],
        "{moves:?}"
    );
    // And the count somebody needs in order to decide.
    assert!(moves.iter().all(|m| m.shots == 2), "{moves:?}");
}

#[test]
fn taking_the_shifts_carries_the_shots_and_the_synopsis_with_them() {
    let mut doc = film_before_the_renumber();
    let pool = doc.scene_numbered("20").expect("scene 20");
    let bedroom = doc.scene_numbered("21").expect("scene 21");
    let screenplay = read(SHIFTED_ALONG);
    let mut taking = Taking {
        scenes: (0..screenplay.scenes.len()).collect(),
        ..Default::default()
    };
    taking.moves = doc
        .moved_scenes(&screenplay, &taking)
        .iter()
        .map(|m| m.index)
        .collect();

    let plan = doc.plan_revision(&screenplay, &taking);
    // The inserted scene is the only new one; neither shifted scene is created
    // beside itself, and neither is reported gone.
    assert_eq!(plan.created, vec!["20".to_string()], "{plan:?}");
    assert!(plan.archived.is_empty() && plan.left_alone.is_empty(), "{plan:?}");

    doc.take_revision(&screenplay, &taking, &revision());

    // The same records, wearing the script's new numbers.
    assert_eq!(doc.scene_numbered("21"), Some(pool));
    assert_eq!(doc.scene_numbered("22"), Some(bedroom));
    // With their shots and their synopses still on them — the whole complaint.
    assert_eq!(doc.placements_in_scene(pool).len(), 2);
    assert_eq!(doc.placements_in_scene(bedroom).len(), 2);
    assert_eq!(
        doc.get(pool).unwrap().text(f::DESCRIPTION),
        Some("The body in the pool")
    );
    assert_eq!(
        doc.get(bedroom).unwrap().text(f::DESCRIPTION),
        Some("Push in at the windows")
    );
    // And the scene the draft inserted is its own record, not one of theirs.
    let inserted = doc.scene_numbered("20").expect("the new 20");
    assert_ne!(inserted, pool);
    assert!(doc.placements_in_scene(inserted).is_empty());
    assert_eq!(doc.get(inserted).unwrap().text(f::LOCATION), Some("FRONT DOOR"));
}

#[test]
fn a_scene_rewritten_at_its_own_number_is_reported_as_changed() {
    let doc = film_before_the_renumber();
    let rewritten = read(
        "20   INT. POOL - DAY\n\nShe scrubs the last specks of blood from the tiles until her hands hurt.\n",
    );
    let diff = doc.diff_script(&rewritten.accepted());

    // It used to come back unchanged: only the slug was ever compared, so a
    // scene rewritten from top to bottom read as identical.
    assert_eq!(diff.unchanged, 0, "{diff:?}");
    let change = diff.changed.first().expect("reported as changed");
    assert!(
        change.differences.iter().any(|(field, _, _)| field == f::SCRIPT),
        "the words themselves are what changed: {:?}",
        change.differences
    );
}

/// A draft rewrites as it renumbers, and the tail of a film gets both — the same
/// scene, half its action new. On its own it clears no honest bar. **Sitting
/// between two scenes that have already been matched, its position is evidence
/// in its own right**, and that is what finds the end of a film.
#[test]
fn a_rewritten_scene_between_two_matched_ones_is_still_offered() {
    let mut doc = film_before_the_renumber();
    // Scene 20 keeps its address, and the draft adds to its action — enough
    // that it no longer clears the bar a scene has to clear on its own.
    let pool = doc.scene_numbered("20").expect("scene 20");
    doc.set(
        pool,
        f::SCRIPT,
        Value::text("The body floats face down in an ocean of gore."),
    );
    let rewritten = "\
19   INT. GATES - DAY

She stands at the gates and does not go in.

20   INT. FRONT DOOR - DAY

Blood on the glass. This scene is new to this draft.

21   INT. POOL - DAY

The body floats face down in an ocean of gore. Petals gather around it.

22   INT. BEDROOM - DAY

He pushes in at the windows, mirroring the opening.
";
    let screenplay = read(rewritten);
    let taking = Taking {
        scenes: (0..screenplay.scenes.len()).collect(),
        ..Default::default()
    };

    let moves = doc.moved_scenes(&screenplay, &taking);
    let pairs: Vec<(String, String)> = moves.iter().map(|m| (m.from.clone(), m.to.clone())).collect();
    assert!(
        pairs.contains(&("20".to_string(), "21".to_string())),
        "19 and 21 anchor it, so the rewritten scene between them is offered: {pairs:?}"
    );
}

#[test]
fn the_cast_tool_offers_the_scenes_characters_then_the_films() {
    let mut doc = project();
    let screenplay = read(DRAFT);
    doc.take_revision(&screenplay, &everything(&screenplay), &revision());

    // In scene 1 Melissa is offered first, and not again among the others.
    let (here, others) = doc.diagram_characters(doc.scene_numbered("1").unwrap());
    assert_eq!(here, vec!["MELISSA"]);
    assert!(!others.iter().any(|o| o.eq_ignore_ascii_case("MELISSA")));
    // In scene 2, where nobody speaks, she is still in the film.
    let (here, others) = doc.diagram_characters(doc.scene_numbered("2").unwrap());
    assert!(here.is_empty());
    assert!(others.iter().any(|o| o == "MELISSA"));
}
