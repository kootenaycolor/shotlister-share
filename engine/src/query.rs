//! Filtering and grouping.
//!
//! The sheets are read by grouping the same table three ways — by scene, by day,
//! by sequence — each with a count in the header, and filtering on any vocabulary
//! column. That is not a feature bolted on the side; it is how the document is
//! used. So it belongs in the engine, identical in every view and on every
//! platform, rather than being re-implemented per screen the way the prototype
//! did it.
//!
//! Grouping decides ordering too: by day you get shooting order, by scene you get
//! story order. Both are real, neither is derived from the other.

use crate::doc::{f, Doc};
use crate::id::Id;
use crate::store::Kind;
use crate::value::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GroupBy {
    Scene,
    Day,
    Sequence,
    Flat,
}

/// Which day a placement is on. `Unscheduled` is a real answer, not an absence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DayFilter {
    Any,
    On(Id),
    Unscheduled,
}

/// Reading a group in the order of one column rather than in the order the list
/// is kept in.
///
/// This is a **way of looking, not a way of editing**. Nothing is written, no
/// position moves, and no letter changes — turn it off and the list is exactly
/// as it was. That distinction is the whole reason this is on the query rather
/// than being a reorder: sorting a two-hundred-shot list by lens must not be a
/// two-hundred-change edit that somebody then has to undo.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SortBy {
    /// A column name, as `columns::DEFAULT_ORDER` uses them, or `shot` for the
    /// number.
    pub column: String,
    pub descending: bool,
}

impl SortBy {
    pub fn column(name: &str) -> SortBy {
        SortBy {
            column: name.to_string(),
            descending: false,
        }
    }

    pub fn descending(mut self) -> SortBy {
        self.descending = true;
        self
    }
}

#[derive(Clone, Debug)]
pub struct Query {
    /// Field on the shot must equal this, or contain it if the field is a list.
    pub shot_is: Vec<(String, String)>,
    /// Field on the placement's scene must equal this.
    pub scene_is: Vec<(String, String)>,
    pub day: DayFilter,
    pub sequence: Option<Id>,
    /// **One shoot of the project, and no others** (piece D): the shoot the
    /// picker is on, by its id. `None` is All Shoots. Ignored while the card
    /// lists fewer than two shoots.
    pub shoot: Option<String>,
    /// One or several scenes, and no others — a scene's own PDF export (one
    /// scene, or several picked at once) asks for exactly these, regardless
    /// of whatever search or facet is live on screen. Empty means unfiltered.
    pub scenes: Vec<Id>,
    /// Free text across shot, scene, tags, day label and sequence title.
    pub text: Option<String>,
    /// Struck shots are hidden when this is false.
    pub include_struck: bool,
    /// **An archived scene's shots are left out unless asked for.** His
    /// report, 2026-09-20: *"the pdf is not honoring archived scenes!!"* —
    /// the Mac and the portal set archived scenes aside on their own
    /// screens, but every export read the query, and the query did not
    /// know. Only the screens ask for them (`view.rs`), and decide what to
    /// draw; paper, the workbook and the share page never do.
    pub include_archived: bool,
    pub group_by: GroupBy,
    /// How to read each group. `None` is the list's own order, which is what
    /// the numbering means and what everything else is measured against.
    pub sort: Option<SortBy>,
    /// **Several shoot days at once**, and whether the unscheduled come too —
    /// the export's Days picker (2026-10-15). `None` is no narrowing by it.
    /// Read alongside `day`, never instead of it.
    pub days: Option<(Vec<Id>, bool)>,
}

impl Default for Query {
    fn default() -> Self {
        Query {
            shot_is: Vec::new(),
            scene_is: Vec::new(),
            day: DayFilter::Any,
            sequence: None,
            shoot: None,
            scenes: Vec::new(),
            text: None,
            include_struck: true,
            include_archived: false,
            group_by: GroupBy::Scene,
            sort: None,
            days: None,
        }
    }
}

impl Query {
    pub fn grouped_by(group_by: GroupBy) -> Query {
        Query {
            group_by,
            ..Query::default()
        }
    }

    pub fn shot_is(mut self, field: &str, value: &str) -> Query {
        self.shot_is.push((field.to_string(), value.to_string()));
        self
    }

    pub fn scene_is(mut self, field: &str, value: &str) -> Query {
        self.scene_is.push((field.to_string(), value.to_string()));
        self
    }

    pub fn on_day(mut self, day: Id) -> Query {
        self.day = DayFilter::On(day);
        self
    }

    pub fn unscheduled(mut self) -> Query {
        self.day = DayFilter::Unscheduled;
        self
    }

    /// Just this scene — what a scene's own PDF export asks for.
    pub fn for_scene(mut self, scene: Id) -> Query {
        self.scenes = vec![scene];
        self
    }

    /// Just these scenes — what exporting several picked scenes at once asks
    /// for.
    pub fn for_scenes(mut self, scenes: Vec<Id>) -> Query {
        self.scenes = scenes;
        self
    }

    pub fn matching(mut self, text: &str) -> Query {
        self.text = Some(text.to_string());
        self
    }

    /// Read every group in one column's order. The list itself is untouched.
    pub fn sorted_by(mut self, column: &str, descending: bool) -> Query {
        self.sort = Some(SortBy {
            column: column.to_string(),
            descending,
        });
        self
    }

    pub fn hiding_struck(mut self) -> Query {
        self.include_struck = false;
        self
    }

    /// Archived scenes too — what a screen asks, so it can set them aside
    /// its own way (greyed, behind a chevron) rather than lose them.
    pub fn with_archived(mut self) -> Query {
        self.include_archived = true;
        self
    }
}

/// A group and its members. The count the sheets show in each group header is
/// just `placements.len()`, never stored.
#[derive(Clone, Debug)]
pub struct Group {
    /// The scene, day or sequence this group is for. `None` is the catch-all —
    /// unscheduled shots, or shots in scenes with no sequence.
    pub key: Option<Id>,
    pub label: String,
    pub placements: Vec<Id>,
}

impl Group {
    pub fn count(&self) -> usize {
        self.placements.len()
    }
}

fn value_matches(value: Option<&Value>, wanted: &str) -> bool {
    match value {
        Some(Value::Text(s)) => s.eq_ignore_ascii_case(wanted),
        // **A field that points at a record is matched by that record's id.**
        // Narrowing to a location was impossible without this: a scene's
        // location is a reference, and a reference fell through to `false`, so
        // the answer was always "no scene is at that location". Found while
        // reading why three of the scene filter's categories could only ever
        // come back empty (2026-08-22).
        Some(Value::Ref(id)) => id.0.to_string().eq_ignore_ascii_case(wanted),
        // A list of either — tags are text, and the places a scene moves
        // between are references.
        Some(Value::List(items)) => items.iter().any(|item| match item {
            Value::Text(s) => s.eq_ignore_ascii_case(wanted),
            Value::Ref(id) => id.0.to_string().eq_ignore_ascii_case(wanted),
            _ => false,
        }),
        _ => false,
    }
}

fn contains_text(value: Option<&Value>, needle: &str) -> bool {
    match value {
        Some(Value::Text(s)) => s.to_lowercase().contains(needle),
        Some(Value::List(items)) => items
            .iter()
            .filter_map(|i| i.as_text())
            .any(|s| s.to_lowercase().contains(needle)),
        _ => false,
    }
}

impl Doc {
    pub fn sequences_in_order(&self) -> Vec<Id> {
        let mut sequences = self.store().of_kind(&Kind::Sequence);
        sequences.sort_by(|a, b| {
            crate::order::compare(
                a.float(f::ORDER).unwrap_or(0.0),
                b.float(f::ORDER).unwrap_or(0.0),
            )
        });
        sequences.iter().map(|r| r.id).collect()
    }

    /// Every placement in the project, in story order: scenes in order, and
    /// within each scene its running order.
    pub fn all_placements(&self) -> Vec<Id> {
        let mut out = Vec::new();
        for scene in self.scenes_in_order() {
            out.extend(self.placements_in_scene(scene));
        }
        out
    }

    fn placement_passes(&self, placement: Id, query: &Query) -> bool {
        let record = match self.get(placement) {
            Some(r) => r,
            None => return false,
        };
        let shot = record.ref_id(f::SHOT).and_then(|id| self.get(id));
        let scene = record.ref_id(f::SCENE).and_then(|id| self.get(id));

        // A shot whose record is gone should not show up as a blank row.
        let shot = match shot {
            Some(s) => s,
            None => return false,
        };

        if !query.include_struck && shot.bool(f::STRUCK) {
            return false;
        }
        if !query.include_archived && scene.map(|s| s.bool(f::ARCHIVED)).unwrap_or(false) {
            return false;
        }

        for (field, wanted) in &query.shot_is {
            if !value_matches(shot.get(field), wanted) {
                return false;
            }
        }

        for (field, wanted) in &query.scene_is {
            let mut found = if field == f::INT_EXT {
                // **A scene that happens inside and outside answers for
                // both** — see `insideout::answers`.
                let held = scene.and_then(|s| s.text(field)).unwrap_or_default();
                crate::insideout::answers(held, wanted)
            } else {
                value_matches(scene.and_then(|s| s.get(field)), wanted)
            };
            // **A scene shot at three places is found by any of them.** The
            // single `location_id` holds the first only, and narrowing to the
            // second would have said the scene is not there — which is exactly
            // the shape of the bug this arm was written to fix in the first
            // place.
            if !found && field == f::LOCATION_ID {
                found = value_matches(scene.and_then(|s| s.get(f::LOCATION_IDS)), wanted);
            }
            if !found {
                return false;
            }
        }

        match query.day {
            DayFilter::Any => {}
            DayFilter::On(day) => {
                if record.ref_id(f::DAY) != Some(day) {
                    return false;
                }
            }
            DayFilter::Unscheduled => {
                if record.ref_id(f::DAY).is_some() {
                    return false;
                }
            }
        }

        if let Some((days, loose)) = &query.days {
            match record.ref_id(f::DAY) {
                Some(day) if days.contains(&day) => {}
                None if *loose => {}
                _ => return false,
            }
        }

        if let Some(sequence) = query.sequence {
            if scene.and_then(|s| s.ref_id(f::SEQUENCE)) != Some(sequence) {
                return false;
            }
        }

        if query.shoot.is_some() {
            match record.ref_id(f::SCENE) {
                Some(scene) if self.scene_in(scene, query.shoot.as_deref()) => {}
                _ => return false,
            }
        }

        if !query.scenes.is_empty() {
            match record.ref_id(f::SCENE) {
                Some(scene) if query.scenes.contains(&scene) => {}
                _ => return false,
            }
        }

        if let Some(text) = &query.text {
            let needle = text.to_lowercase();
            if needle.is_empty() {
                return true;
            }
            let mut hit = false;

            for field in [f::TITLE, f::DESCRIPTION, f::NOTES, f::SIZE, f::MOVEMENT, f::LENS, f::MODIFIERS, f::LENS_FILTERS, f::SUPPORT, f::ANGLE, f::TAGS] {
                hit |= contains_text(shot.get(field), &needle);
            }
            if let Some(scene) = scene {
                for field in [f::NUMBER, f::LOCATION, f::DESCRIPTION, f::NOTES, f::TIME_OF_DAY, f::INT_EXT, f::PRIORITY, f::POV, f::SHOOTING_LOCATION] {
                    hit |= contains_text(scene.get(field), &needle);
                }
                if let Some(heading) = self.scene_heading(scene.id) {
                    hit |= heading.to_lowercase().contains(&needle);
                }
                if let Some(sequence) = scene.ref_id(f::SEQUENCE).and_then(|id| self.get(id)) {
                    hit |= contains_text(sequence.get(f::TITLE), &needle);
                }
            }
            if let Some(day) = record.ref_id(f::DAY) {
                if let Some(label) = self.day_label(day) {
                    hit |= label.to_lowercase().contains(&needle);
                }
            }
            // The number you would say out loud: "thirty-four A".
            if let Some(number) = self.display_number(placement) {
                hit |= number.to_lowercase().contains(&needle);
            }
            if !hit {
                return false;
            }
        }

        true
    }

    /// Run a query. Groups come back in display order, and each carries its own
    /// members in the order that grouping implies.
    /// Filter and group, then read each group in whatever order was asked for.
    pub fn run(&self, query: &Query) -> Vec<Group> {
        let mut groups = self.grouped(query);
        if let Some(sort) = &query.sort {
            for group in &mut groups {
                // Sorted by key rather than in place, so an unsortable value
                // cannot make the order depend on where a shot started.
                let mut keyed: Vec<(String, Id)> = group
                    .placements
                    .iter()
                    .map(|p| (self.sort_key(*p, &sort.column), *p))
                    .collect();
                keyed.sort_by(|(a, _), (b, _)| crate::natural::compare_filled_first(a, b));
                if sort.descending {
                    // Reversed among the filled-in values only: an empty cell is
                    // absent rather than smallest, so it stays at the bottom
                    // whichever way the column is pointing.
                    let filled = keyed.iter().filter(|(k, _)| !k.trim().is_empty()).count();
                    keyed[..filled].reverse();
                }
                group.placements = keyed.into_iter().map(|(_, p)| p).collect();
            }
        }
        groups
    }

    /// What one column says about a shot, as text a person would recognise —
    /// which is what makes sorting by camera sort by the unit's name rather than
    /// by an id nobody can see.
    pub fn sort_key(&self, placement: Id, column: &str) -> String {
        let Some(record) = self.get(placement) else {
            return String::new();
        };
        let shot = record.ref_id(f::SHOT).and_then(|id| self.get(id));
        let text_of = |field: &str| -> String {
            shot.and_then(|s| s.get(field))
                .map(|value| match value {
                    Value::List(items) => items
                        .iter()
                        .filter_map(|i| i.as_text())
                        .collect::<Vec<_>>()
                        .join(", "),
                    Value::Text(t) => t.clone(),
                    other => other.as_text().unwrap_or_default().to_string(),
                })
                .unwrap_or_default()
        };

        match column {
            "shot" => self.display_number(placement).unwrap_or_default(),
            "day" => record
                .ref_id(f::DAY)
                .and_then(|day| self.day_label(day))
                .unwrap_or_default(),
            "camera" => shot
                .and_then(|s| s.ref_id(f::UNIT))
                .and_then(|unit| self.get(unit))
                .and_then(|unit| unit.text(f::LABEL))
                .unwrap_or_default()
                .to_string(),
            "sequence" => record
                .ref_id(f::SCENE)
                .and_then(|scene| self.get(scene))
                .and_then(|scene| scene.ref_id(f::SEQUENCE))
                .and_then(|sequence| self.get(sequence))
                .and_then(|sequence| sequence.text(f::TITLE))
                .unwrap_or_default()
                .to_string(),
            "struck" => {
                if shot.map(|s| s.bool(f::STRUCK)) == Some(true) {
                    "struck".to_string()
                } else {
                    String::new()
                }
            }
            // A picture has no order of its own, so the useful question is
            // whether there is one — which puts the shots still missing a frame
            // together where they can be dealt with.
            "image" => {
                if self.media_refs(placement).is_empty() {
                    String::new()
                } else {
                    "frame".to_string()
                }
            }
            other => text_of(other),
        }
    }

    fn grouped(&self, query: &Query) -> Vec<Group> {
        let passes = |p: &Id| self.placement_passes(*p, query);

        match query.group_by {
            GroupBy::Flat => {
                let placements: Vec<Id> =
                    self.all_placements().into_iter().filter(|p| passes(p)).collect();
                if placements.is_empty() {
                    Vec::new()
                } else {
                    vec![Group {
                        key: None,
                        label: String::new(),
                        placements,
                    }]
                }
            }

            GroupBy::Scene => self
                .scenes_in_order()
                .into_iter()
                .filter_map(|scene| {
                    let placements: Vec<Id> = self
                        .placements_in_scene(scene)
                        .into_iter()
                        .filter(|p| passes(p))
                        .collect();
                    if placements.is_empty() {
                        return None;
                    }
                    let number = self
                        .get(scene)
                        .and_then(|r| r.text(f::NUMBER).map(|s| s.to_string()))
                        .unwrap_or_default();
                    Some(Group {
                        key: Some(scene),
                        label: format!("Scene {number}"),
                        placements,
                    })
                })
                .collect(),

            GroupBy::Day => {
                let mut groups = Vec::new();
                for day in self.days_in_order() {
                    let placements: Vec<Id> = self
                        .placements_on_day(day)
                        .into_iter()
                        .filter(|p| passes(p))
                        .collect();
                    if placements.is_empty() {
                        continue;
                    }
                    groups.push(Group {
                        key: Some(day),
                        label: self.day_label(day).unwrap_or_default(),
                        placements,
                    });
                }
                // Unscheduled work is not an error state; it goes last, named.
                let loose: Vec<Id> = self
                    .all_placements()
                    .into_iter()
                    .filter(|p| {
                        self.get(*p)
                            .map(|r| r.ref_id(f::DAY).is_none())
                            .unwrap_or(false)
                            && passes(p)
                    })
                    .collect();
                if !loose.is_empty() {
                    groups.push(Group {
                        key: None,
                        label: "Unscheduled".to_string(),
                        placements: loose,
                    });
                }
                groups
            }

            GroupBy::Sequence => {
                let mut groups = Vec::new();
                for sequence in self.sequences_in_order() {
                    let placements: Vec<Id> = self
                        .all_placements()
                        .into_iter()
                        .filter(|p| {
                            let scene = self.get(*p).and_then(|r| r.ref_id(f::SCENE));
                            let in_sequence = scene
                                .and_then(|s| self.get(s))
                                .and_then(|s| s.ref_id(f::SEQUENCE))
                                == Some(sequence);
                            in_sequence && passes(p)
                        })
                        .collect();
                    if placements.is_empty() {
                        continue;
                    }
                    let title = self
                        .get(sequence)
                        .and_then(|r| r.text(f::TITLE).map(|s| s.to_string()))
                        .unwrap_or_default();
                    groups.push(Group {
                        key: Some(sequence),
                        label: title,
                        placements,
                    });
                }
                let loose: Vec<Id> = self
                    .all_placements()
                    .into_iter()
                    .filter(|p| {
                        let scene = self.get(*p).and_then(|r| r.ref_id(f::SCENE));
                        let has_sequence = scene
                            .and_then(|s| self.get(s))
                            .and_then(|s| s.ref_id(f::SEQUENCE))
                            .is_some();
                        !has_sequence && passes(p)
                    })
                    .collect();
                if !loose.is_empty() {
                    groups.push(Group {
                        key: None,
                        label: "No sequence".to_string(),
                        placements: loose,
                    });
                }
                groups
            }
        }
    }

    /// Scenes the current filter leaves standing.
    ///
    /// A scene with no shots in it counts as visible: it is empty, not filtered
    /// away, and telling someone it was hidden would be wrong.
    pub fn visible_scenes(&self, query: &Query) -> Vec<Id> {
        self.scenes_in_order()
            .into_iter()
            .filter(|scene| self.scene_in(*scene, query.shoot.as_deref()))
            .filter(|scene| {
                let placements = self.placements_in_scene(*scene);
                placements.is_empty()
                    || placements
                        .iter()
                        .any(|placement| self.placement_passes(*placement, query))
            })
            .collect()
    }

    /// Scenes the filter removed — what "4 scenes are hidden" is counting.
    pub fn hidden_scenes(&self, query: &Query) -> Vec<Id> {
        let visible = self.visible_scenes(query);
        // Another shoot's scenes are not hidden by a filter: they are another
        // shoot's, and the picker says so.
        self.scenes_in_order()
            .into_iter()
            .filter(|scene| self.scene_in(*scene, query.shoot.as_deref()))
            .filter(|scene| !visible.contains(scene))
            .collect()
    }

    pub fn hidden_scene_count(&self, query: &Query) -> usize {
        self.hidden_scenes(query).len()
    }

    /// Total across every group — the "16 shots" in a filtered header.
    pub fn count(&self, query: &Query) -> usize {
        self.run(query).iter().map(|g| g.count()).sum()
    }
}
