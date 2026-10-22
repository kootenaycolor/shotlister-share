//! Vocabularies, filtering and grouping — the behaviour every view shares.

use shotlister_engine::doc::f;
use shotlister_engine::{DeviceId, Doc, GroupBy, Query};

fn project() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

// ---- vocabularies ------------------------------------------------------

#[test]
fn a_project_owns_its_lists() {
    let mut d = project();
    d.set_vocabulary("lens", &["20.7mm", "27mm", "37mm", "47mm", "57mm"]);

    assert_eq!(d.vocabulary("lens").len(), 5);
    assert!(d.vocabulary_contains("lens", "37mm"));
    assert!(!d.vocabulary_contains("lens", "50mm"));
}

#[test]
fn typing_a_new_value_teaches_the_project() {
    let mut d = project();
    d.set_vocabulary("lens", &["27mm", "37mm"]);
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);

    d.set_vocab_field(shot, "lens", "20.7mm");

    // The shot has it, and so does the master list, permanently.
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("20.7mm"));
    assert!(d.vocabulary_contains("lens", "20.7mm"));
    assert_eq!(d.vocabulary("lens"), vec!["27mm", "37mm", "20.7mm"]);
}

#[test]
fn a_known_value_teaches_nothing_new() {
    let mut d = project();
    d.set_vocabulary("size", &["W/OTS", "M/OTS", "CU"]);
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);

    // Casing differs; it is still the same value and must not be added twice.
    d.set_vocab_field(shot, "size", "cu");
    assert_eq!(d.vocabulary("size").len(), 3);
}

#[test]
fn multi_value_fields_teach_every_value() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);

    // Angle holds more than one value, as it does in the real lists.
    d.set_vocab_list(shot, "angle", &["Front On", "Eye Level"]);

    assert!(d.vocabulary_contains("angle", "Front On"));
    assert!(d.vocabulary_contains("angle", "Eye Level"));
}

// ---- grouping ----------------------------------------------------------

#[test]
fn grouping_by_scene_counts_each_group() {
    let mut d = project();
    let s2 = d.create_scene("2");
    let s34 = d.create_scene("34");
    for _ in 0..20 {
        d.add_shot_to_scene(s2);
    }
    for _ in 0..16 {
        d.add_shot_to_scene(s34);
    }

    let groups = d.run(&Query::grouped_by(GroupBy::Scene));

    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0].label, "Scene 2");
    assert_eq!(groups[0].count(), 20);
    assert_eq!(groups[1].label, "Scene 34");
    assert_eq!(groups[1].count(), 16);
}

#[test]
fn grouping_by_day_uses_shooting_order_and_names_the_unscheduled() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    let (_, c) = d.add_shot_to_scene(scene);

    // Shot out of story order, as on a real day.
    d.schedule(c, day);
    d.schedule(a, day);
    // b stays unscheduled.

    let groups = d.run(&Query::grouped_by(GroupBy::Day));

    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0].label, "Day 1");
    assert_eq!(groups[0].placements, vec![c, a]);
    assert_eq!(groups[1].label, "Unscheduled");
    assert_eq!(groups[1].placements, vec![b]);
}

#[test]
fn grouping_by_sequence_keeps_loose_scenes_visible() {
    let mut d = project();
    let chase = d.create_sequence("Hospital Chase");
    let in_sequence = d.create_scene("34");
    let loose = d.create_scene("40");
    d.set(in_sequence, f::SEQUENCE, chase);
    let (_, a) = d.add_shot_to_scene(in_sequence);
    let (_, b) = d.add_shot_to_scene(loose);

    let groups = d.run(&Query::grouped_by(GroupBy::Sequence));

    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0].label, "Hospital Chase");
    assert_eq!(groups[0].placements, vec![a]);
    assert_eq!(groups[1].label, "No sequence");
    assert_eq!(groups[1].placements, vec![b]);
}

#[test]
fn an_empty_group_does_not_appear() {
    let mut d = project();
    let with_shots = d.create_scene("34");
    d.create_scene("40"); // no shots
    d.add_shot_to_scene(with_shots);

    let groups = d.run(&Query::grouped_by(GroupBy::Scene));
    assert_eq!(groups.len(), 1);
}

// ---- filtering ---------------------------------------------------------

#[test]
fn filtering_on_a_shot_field() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (wide, _) = d.add_shot_to_scene(scene);
    let (close, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(wide, "size", "W/OTS");
    d.set_vocab_field(close, "size", "CU");

    let query = Query::grouped_by(GroupBy::Scene).shot_is("size", "W/OTS");
    assert_eq!(d.count(&query), 1);
}

#[test]
fn filtering_matches_inside_a_multi_value_field() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);
    d.set_vocab_list(a, "angle", &["Front On", "Eye Level"]);
    d.set_vocab_list(b, "angle", &["Low"]);

    // "Eye Level" is one of several values on that shot and must still match.
    let query = Query::grouped_by(GroupBy::Flat).shot_is("angle", "Eye Level");
    assert_eq!(d.count(&query), 1);
}

#[test]
fn filtering_to_one_scene_or_to_several_picked_at_once() {
    let mut d = project();
    let a = d.create_scene("33");
    let b = d.create_scene("34");
    let c = d.create_scene("35");
    d.add_shot_to_scene(a);
    d.add_shot_to_scene(b);
    d.add_shot_to_scene(c);

    // A scene's own PDF export: just that one, whatever else is on screen.
    let one = Query::grouped_by(GroupBy::Scene).for_scene(b);
    assert_eq!(d.count(&one), 1);

    // Several scenes picked at once, in one export.
    let several = Query::grouped_by(GroupBy::Scene).for_scenes(vec![a, c]);
    assert_eq!(d.count(&several), 2);

    // Unfiltered is still unfiltered — an empty list means no restriction.
    let none = Query::grouped_by(GroupBy::Scene);
    assert_eq!(d.count(&none), 3);
}

#[test]
fn searching_finds_a_shot_by_the_number_you_would_say_out_loud() {
    let mut d = project();
    let scene = d.create_scene("34");
    d.add_shot_to_scene(scene);
    let (_, second) = d.add_shot_to_scene(scene);

    let groups = d.run(&Query::grouped_by(GroupBy::Flat).matching("34b"));
    assert_eq!(groups[0].placements, vec![second]);
}

#[test]
fn searching_reaches_the_scene_and_the_sequence() {
    let mut d = project();
    let chase = d.create_sequence("Hospital Chase");
    let scene = d.create_scene("34");
    d.set(scene, f::LOCATION, "corridor");
    d.set(scene, f::SEQUENCE, chase);
    d.add_shot_to_scene(scene);

    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat).matching("corridor")), 1);
    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat).matching("hospital")), 1);
    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat).matching("nowhere")), 0);
}

#[test]
fn filtering_to_one_day_or_to_the_unscheduled() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    let (_, a) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);
    d.schedule(a, day);

    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat).on_day(day)), 1);
    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat).unscheduled()), 1);
}

#[test]
fn struck_shots_can_be_hidden_without_being_touched() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (got_it, placement) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);

    d.strike(got_it, true);

    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat)), 2);
    assert_eq!(d.count(&Query::grouped_by(GroupBy::Flat).hiding_struck()), 1);
    // Hiding is a view choice; the shot itself is untouched.
    assert_eq!(d.display_number(placement).unwrap(), "34A");
}

#[test]
fn filters_combine() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    let (a, pa) = d.add_shot_to_scene(scene);
    let (b, pb) = d.add_shot_to_scene(scene);
    let (c, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(a, "size", "CU");
    d.set_vocab_field(b, "size", "CU");
    d.set_vocab_field(c, "size", "W");
    d.schedule(pa, day);
    d.schedule(pb, day);
    d.strike(b, true);

    let query = Query::grouped_by(GroupBy::Day)
        .shot_is("size", "CU")
        .on_day(day)
        .hiding_struck();

    assert_eq!(d.count(&query), 1);
}

// ---- scheduling a whole scene -----------------------------------------

#[test]
fn a_whole_scene_can_go_on_a_day_in_one_gesture() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    for _ in 0..5 {
        d.add_shot_to_scene(scene);
    }

    d.schedule_scene(scene, day);

    assert_eq!(d.placements_on_day(day).len(), 5);
    assert_eq!(d.days_of_scene(scene), vec![day]);
    assert!(!d.scene_is_split(scene));
}

#[test]
fn a_scene_can_be_split_across_two_days() {
    let mut d = project();
    let scene = d.create_scene("34");
    let monday = d.create_day();
    let tuesday = d.create_day();
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);

    // Ran out of light. The rest goes tomorrow — which the prototype could not
    // represent at all, because the day belonged to the scene.
    d.schedule(a, monday);
    d.schedule(b, tuesday);

    assert_eq!(d.days_of_scene(scene), vec![monday, tuesday]);
    assert!(d.scene_is_split(scene));
}

#[test]
fn a_partly_scheduled_scene_reads_as_split() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    let (_, a) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene);

    d.schedule(a, day);

    assert!(d.scene_is_split(scene));
    assert_eq!(d.days_of_scene(scene), vec![day]);
}

#[test]
fn unscheduling_a_scene_clears_all_of_it() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    for _ in 0..3 {
        d.add_shot_to_scene(scene);
    }
    d.schedule_scene(scene, day);

    d.unschedule_scene(scene);

    assert!(d.placements_on_day(day).is_empty());
    assert!(d.days_of_scene(scene).is_empty());
}

// ---- what the outline needs -------------------------------------------

#[test]
fn hidden_scenes_are_counted_for_the_outline() {
    let mut d = project();
    let keep = d.create_scene("34");
    let drop = d.create_scene("40");
    let (a, _) = d.add_shot_to_scene(keep);
    let (b, _) = d.add_shot_to_scene(drop);
    d.set_vocab_field(a, "size", "CU");
    d.set_vocab_field(b, "size", "W");

    let query = Query::grouped_by(GroupBy::Scene).shot_is("size", "CU");

    assert_eq!(d.visible_scenes(&query), vec![keep]);
    assert_eq!(d.hidden_scenes(&query), vec![drop]);
    assert_eq!(d.hidden_scene_count(&query), 1);
}

#[test]
fn a_scene_with_no_shots_is_empty_rather_than_hidden() {
    let mut d = project();
    let with_shots = d.create_scene("34");
    let empty = d.create_scene("40");
    let (shot, _) = d.add_shot_to_scene(with_shots);
    d.set_vocab_field(shot, "size", "CU");

    // Nothing in scene 40 could match, but it was not filtered away — it is
    // simply empty, and saying it was hidden would be wrong.
    let query = Query::grouped_by(GroupBy::Scene).shot_is("size", "CU");
    assert!(d.visible_scenes(&query).contains(&empty));
    assert_eq!(d.hidden_scene_count(&query), 0);
}

#[test]
fn with_no_filter_nothing_is_hidden() {
    let mut d = project();
    let scene = d.create_scene("34");
    d.add_shot_to_scene(scene);

    assert_eq!(d.hidden_scene_count(&Query::default()), 0);
}

// ---- what the schedule needs ------------------------------------------

#[test]
fn a_band_can_say_which_other_days_its_scene_touches() {
    let mut d = project();
    let scene = d.create_scene("54");
    let monday = d.create_day();
    let tuesday = d.create_day();
    let (_, a) = d.add_shot_to_scene(scene);
    let (_, b) = d.add_shot_to_scene(scene);
    d.schedule(a, monday);
    d.schedule(b, tuesday);

    // Standing on Day 1, the band reads "also Day 2".
    assert_eq!(d.other_days_of_scene(scene, monday), vec![tuesday]);
    assert_eq!(d.other_days_of_scene(scene, tuesday), vec![monday]);
    assert_eq!(d.days_of_scene(scene), vec![monday, tuesday]);
}

#[test]
fn dropping_a_shot_into_a_day_costs_two_changes_however_long_the_day() {
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    for _ in 0..40 {
        let (_, placement) = d.add_shot_to_scene(scene);
        d.schedule(placement, day);
    }
    let (_, dropped) = d.add_shot_to_scene(scene);

    let before = d.changes().len();
    d.schedule_at(dropped, day, 20);

    // Which day, and where in it. Never one change per shot in the lane.
    assert_eq!(d.changes().len() - before, 2);
    assert_eq!(d.placements_on_day(day)[20], dropped);
    assert_eq!(d.placements_on_day(day).len(), 41);
}

#[test]
fn a_place_past_the_last_slot_is_the_last_place_not_the_first() {
    // Ref 1575: an index past the end of a day read as the top of it.
    let mut d = project();
    let scene = d.create_scene("34");
    let day = d.create_day();
    let mut lane = Vec::new();
    for _ in 0..3 {
        let (_, p) = d.add_shot_to_scene(scene);
        d.schedule(p, day);
        lane.push(p);
    }
    let (_, loose) = d.add_shot_to_scene(scene);
    // Far past the end, from off every day (the connector's schedule_shot).
    d.schedule_at(loose, day, 99);
    assert_eq!(d.placements_on_day(day), vec![lane[0], lane[1], lane[2], loose]);
    // Exactly the end, and one past it, are the same place.
    d.schedule_at(lane[0], day, 3);
    assert_eq!(d.placements_on_day(day), vec![lane[1], lane[2], loose, lane[0]]);
    d.move_in_day_to(lane[1], 50);
    assert_eq!(d.placements_on_day(day), vec![lane[2], loose, lane[0], lane[1]]);
    // The neighbour door: no neighbour is the end.
    d.shoot_before(lane[2], Some(day), None);
    assert_eq!(d.placements_on_day(day), vec![loose, lane[0], lane[1], lane[2]]);
    // A scene's running order and the days themselves read it the same way.
    d.move_in_scene_to(d.placements_in_scene(scene)[0], 40);
    assert_eq!(d.placements_in_scene(scene).len(), 4);
    let second = d.create_day();
    d.move_day_to(day, 9);
    assert_eq!(d.days_in_order(), vec![second, day]);
}

#[test]
fn reordering_days_costs_one_change_and_renumbers_nothing_else() {
    let mut d = project();
    let scene = d.create_scene("34");
    let one = d.create_day();
    let two = d.create_day();
    let three = d.create_day();
    let (_, placement) = d.add_shot_to_scene(scene);
    d.schedule(placement, three);

    let before = d.changes().len();
    d.move_day_to(three, 0);

    assert_eq!(d.changes().len() - before, 1);
    // Labels follow position, so they all move without being written.
    assert_eq!(d.day_label(three).unwrap(), "Day 1");
    assert_eq!(d.day_label(one).unwrap(), "Day 2");
    assert_eq!(d.day_label(two).unwrap(), "Day 3");
    // And the shot is untouched — still on the same day, still 34A.
    assert_eq!(d.display_number(placement).unwrap(), "34A");
    assert_eq!(d.placements_on_day(three), vec![placement]);
}

// ---- what the settings screen needs ------------------------------------

#[test]
fn a_list_says_how_much_each_value_is_used() {
    let mut d = project();
    d.set_vocabulary("lens", &["27mm", "37mm", "50mm"]);
    let scene = d.create_scene("34");
    for _ in 0..3 {
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set_vocab_field(shot, "lens", "37mm");
    }
    let (one, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(one, "lens", "27mm");

    // In list order, so the screen can put a count beside each entry.
    assert_eq!(
        d.vocab_usage("lens"),
        vec![
            ("27mm".to_string(), 1),
            ("37mm".to_string(), 3),
            ("50mm".to_string(), 0),
        ]
    );
}

#[test]
fn a_value_in_use_but_not_on_the_list_is_surfaced() {
    let mut d = project();
    d.set_vocabulary("lens", &["27mm"]);
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    // As if it arrived from somebody else's sheet, bypassing the list.
    d.set(shot, "lens", "85mm");

    assert_eq!(d.vocabulary_orphans("lens"), vec![("85mm".to_string(), 1)]);
}

#[test]
fn renaming_a_value_changes_it_everywhere_in_one_step() {
    let mut d = project();
    d.set_vocabulary("lens", &["27mm", "37mm"]);
    let scene = d.create_scene("34");
    let mut shots = Vec::new();
    for _ in 0..4 {
        let (shot, _) = d.add_shot_to_scene(scene);
        d.set_vocab_field(shot, "lens", "37mm");
        shots.push(shot);
    }
    d.clear_history();

    let touched = d.rename_vocabulary_value("lens", "37mm", "35mm");

    assert_eq!(touched, 4);
    assert_eq!(d.vocabulary("lens"), vec!["27mm", "35mm"]);
    for shot in &shots {
        assert_eq!(d.get(*shot).unwrap().text("lens"), Some("35mm"));
    }
    // However many it touched, it is one thing to take back.
    assert_eq!(d.undo_depth(), 1);
    d.undo();
    assert_eq!(d.get(shots[0]).unwrap().text("lens"), Some("37mm"));
    assert_eq!(d.vocabulary("lens"), vec!["27mm", "37mm"]);
}

#[test]
fn renaming_reaches_inside_multi_value_fields() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_list(shot, "angle", &["Front On", "Eye Level"]);

    d.rename_vocabulary_value("angle", "Eye Level", "Eyeline");

    let held = d.get(shot).unwrap().get("angle").unwrap().as_list().unwrap().to_vec();
    let values: Vec<&str> = held.iter().filter_map(|v| v.as_text()).collect();
    assert_eq!(values, vec!["Front On", "Eyeline"]);
}

#[test]
fn renaming_reaches_scene_fields_too() {
    let mut d = project();
    let scene = d.create_scene("34");
    // Priority and POV live on scenes rather than shots.
    d.set(scene, f::PRIORITY, "Must Have");
    d.set_vocabulary("priority", &["Must Have", "Nice to Have"]);

    let touched = d.rename_vocabulary_value("priority", "Must Have", "Essential");

    assert_eq!(touched, 1);
    assert_eq!(d.get(scene).unwrap().text(f::PRIORITY), Some("Essential"));
}

#[test]
fn removing_a_value_leaves_shots_empty_rather_than_inventing_one() {
    let mut d = project();
    d.set_vocabulary("lens", &["27mm", "37mm"]);
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "37mm");
    d.clear_history();

    let touched = d.remove_vocabulary_value("lens", "37mm");

    assert_eq!(touched, 1);
    assert_eq!(d.vocabulary("lens"), vec!["27mm"]);
    // An obvious gap beats a plausible substitution nobody chose.
    assert_eq!(d.get(shot).unwrap().text("lens"), None);

    // And it is one action, so it comes straight back.
    d.undo();
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("37mm"));
    assert_eq!(d.vocabulary("lens"), vec!["27mm", "37mm"]);
}

#[test]
fn removing_one_value_from_a_multi_value_field_keeps_the_others() {
    let mut d = project();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_list(shot, "angle", &["Front On", "Eye Level"]);

    d.remove_vocabulary_value("angle", "Front On");

    let held = d.get(shot).unwrap().get("angle").unwrap().as_list().unwrap().to_vec();
    let values: Vec<&str> = held.iter().filter_map(|v| v.as_text()).collect();
    assert_eq!(values, vec!["Eye Level"]);
}

#[test]
fn renaming_to_nothing_or_to_itself_does_nothing() {
    let mut d = project();
    d.set_vocabulary("lens", &["37mm"]);
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    d.set_vocab_field(shot, "lens", "37mm");

    assert_eq!(d.rename_vocabulary_value("lens", "37mm", "   "), 0);
    assert_eq!(d.rename_vocabulary_value("lens", "37mm", "37mm"), 0);
    assert_eq!(d.get(shot).unwrap().text("lens"), Some("37mm"));
}

// ---- what Studio and the phone read as plain fields ---------------------

/// **A film with no spec sheet still says `frame` and `sensorsFromSheet`.**
/// Both apps read them as required fields; a reply without them decoded to
/// nothing and every such film opened with no scenes (2026-10-15).
#[test]
fn a_film_with_no_sheet_still_names_its_frame() {
    use shotlister_engine::view::{describe, Asked, Standing};
    let d = project();
    let view = describe(&d, &Asked::default().looking(), &Standing { read_only: false, unsaved: 0, device_clash: None });
    assert!(view.contains("\"frame\":\"\""), "{view}");
    assert!(view.contains("\"sensorsFromSheet\":false"), "{view}");
    assert!(view.contains("\"frameGuides\":"), "{view}");
}
