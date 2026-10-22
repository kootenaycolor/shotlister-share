//! The domain API.
//!
//! `Doc` is what the apps and the MCP talk to. It wraps the store with the rules
//! that are specific to shot listing: letters belong to placements, numbers are
//! derived, headings are derived, day labels follow order.
//!
//! Nothing here stores a value that can be computed. Every duplicated fact in
//! the prototype turned into a sync bug eventually.

use std::collections::HashSet;

use crate::id::Id;
use crate::letters::LetterScheme;
use crate::order;
use crate::stamp::{Clock, DeviceId, Stamp};
use crate::store::{Change, Kind, Op, Record, Store, F_DELETED};
use crate::undo::{UndoEntry, UndoStep};
use crate::value::Value;

/// Field names, in one place so the apps, the exporters and the MCP cannot
/// disagree about spelling.
pub mod f {
    // project
    pub const TITLE: &str = "title";
    pub const DIRECTOR: &str = "director";
    pub const PRODUCER: &str = "producer";
    pub const ASPECT_RATIO: &str = "aspect_ratio";
    pub const DEFAULT_PRIORITY: &str = "default_priority";

    /// **The film's own icon**, as the outline to draw it with — SVG path data
    /// in a twenty-by-twenty box, the same drawing the website wears.
    ///
    /// His call, 2026-09-11, after the icons were missing on his other Mac:
    /// *"that information should be stored on a server level - not local
    /// level… and then distributed out from there"* — and then, plainly:
    /// *"why can't it be part of the project file data that syncs?"*
    ///
    /// It was read off a cache file a **different app** writes on one Mac, so a
    /// Mac that had never run that app drew no icon and the program's own blue,
    /// silently. On the film's own record it travels with the film, through the
    /// sync that already carries the shots and the photographs, and any device
    /// that has the film has the icon.
    ///
    /// The engine stores the outline and never draws or parses it. See
    /// `crate::mark`, which owns everything that is decided about this pair.
    pub const MARK_PATH: &str = "mark_path";
    /// **The colour the film is worn in** — `#D44C47`, seven characters,
    /// uppercase. The accent every screen of that film takes.
    pub const MARK_COLOUR: &str = "mark_colour";
    /// **Where the pair came from**, which decides who may overwrite it.
    ///
    /// `console` — mirrored off his Notion row by the Mac, and refreshed
    /// whenever that row changes. `hand` — he chose it here, for a film that is
    /// not in the larger system, and nothing automatic ever touches it again.
    /// Empty means nobody has said, and the mirror is free to fill it.
    pub const MARK_SOURCE: &str = "mark_source";

    /// **What sort of film this is** — `film` or `commercial`. Empty is a
    /// film. See `crate::kind`, which owns everything decided about it.
    pub const KIND: &str = "kind";
    /// Who the commercial is for, and who brought it. Two plain strings the
    /// engine never reads; a commercial's Project Settings shows them where
    /// a film's shows Director and Producer.
    pub const CLIENT: &str = "client";
    pub const AGENCY: &str = "agency";
    /// **The film's name as his project record says it** — the record on the
    /// portal's server that the Projects Console keeps. Shown wherever the
    /// film's name is drawn; the film's own `title` stays as it is, because
    /// the package, the console's film list and the sync all know the film
    /// by that one. Empty means the record has not said, and the title shows.
    /// See `crate::recordfacts`.
    pub const RECORD_TITLE: &str = "record_title";
    /// **Who owns the film's facts** — its shown name, director, producer,
    /// client and agency. `console` means they come from the project record
    /// and the shells show them without letting anyone type over them; empty
    /// means the film keeps its own, as every film did before 2026-10-05.
    /// Written only by `Doc::take_record_facts`. See `crate::recordfacts`.
    pub const FACTS_SOURCE: &str = "facts_source";

    // scene
    pub const NUMBER: &str = "number";
    pub const INT_EXT: &str = "int_ext";
    pub const LOCATION: &str = "location";
    pub const TIME_OF_DAY: &str = "time_of_day";
    pub const SHOOTING_LOCATION: &str = "shooting_location";
    pub const SCRIPT: &str = "script";
    pub const PRIORITY: &str = "priority";
    pub const POV: &str = "pov";
    pub const SEQUENCE: &str = "sequence";
    /// **What we hear** — the right-hand column of an AV script. A commercial
    /// scene's `SCRIPT` is its *Video*; this is its *Audio*. A film never
    /// writes it.
    pub const AUDIO: &str = "audio";
    /// **The beat a shot is tied to** — a `Kind::Beat`. The shot's Video
    /// and Audio are read off it, never copied.
    pub const BEAT: &str = "beat";
    /// The **location record** a scene is actually shot at — a reference to a
    /// `Kind::Location`, not text.
    ///
    /// Deliberately not `LOCATION`: that one is already taken and means
    /// something else entirely. A scene's `location` is the script's word —
    /// "CAR", "COUNTY JAIL" — lifted off the slugline and never ours to change.
    /// Where the crew actually goes is a different fact about the same scene,
    /// which is why Cadrage has both and why `shooting_location` existed as
    /// free text before there was a record to point at.
    ///
    /// **It was called `place` until 2026-08-21.** That collided with the
    /// bridge's older `place` command, which schedules a shot onto a day and
    /// has nothing to do with any of this — two meanings for one word in one
    /// codebase, which is how somebody loses an afternoon. Renamed on his call
    /// that the whole feature is "Locations".
    pub const LOCATION_ID: &str = "location_id";

    /// **Every location a scene is shot at**, in order, when it is shot at more
    /// than one — his ask, 2026-08-22: "in case it moves between". A chase that
    /// starts in the kitchen and ends in the yard is one scene at two places,
    /// and the crew has to be told about both.
    ///
    /// `LOCATION_ID` above stays, and stays correct: it holds the **first** of
    /// these, written in the same breath. Everything that only ever wanted one
    /// place — the phone, the bridge, Claude's server, a project written by an
    /// older build — keeps reading the field it always read and gets the scene's
    /// main location, rather than nothing at all.
    pub const LOCATION_IDS: &str = "location_ids";

    /// Every mood board this scene links to, comma-order preserved as a list.
    /// His call, 2026-08-23 (Ref SL-348): the chip lives on the scene, the
    /// same grammar as `LOCATION_IDS` — a board usually serves many scenes,
    /// so the cheaper end to file the link from is the scene, not the board.
    pub const BOARD_IDS: &str = "board_ids";

    /// How a mood board's own pictures fill their tile: `original` (each
    /// keeps its own shape — the default, and the one already built),
    /// `square`, or `project` (the project's own aspect ratio, the same box
    /// the storyboard draws). A board-wide setting, not per-picture — a wall
    /// reads as one thing.
    pub const BOARD_RATIO: &str = "board_ratio";

    // ---- a location's own fields -------------------------------------------
    //
    // These names are the ones the phone thread asked for, in the engine's
    // snake_case rather than the JSON's camelCase — `handoff/from-phone.md`
    // says "tell me the real field names and I will move the phone onto the
    // engine". `name` reuses `f::LABEL`; the rest are here.
    pub const ADDRESS: &str = "address";
    pub const LATITUDE: &str = "latitude";
    pub const LONGITUDE: &str = "longitude";
    pub const CREATED_AT: &str = "created_at";
    pub const CAPTURED_BY: &str = "captured_by";
    /// The room as a shape — RoomPlan's `CapturedRoom`, stored as media by its
    /// hash like everything else. **The JSON is the valuable half**, per the
    /// phone: the `.usdz` is what you look at, the JSON is walls and openings
    /// with measurements, and a floor plan can only be built from the second.
    pub const SCAN: &str = "scan";
    pub const SCAN_SHAPE: &str = "scan_shape";
    /// Which folder under `<Project>.shotlist/locations/` this record came
    /// from, when it came from the phone.
    ///
    /// The phone names its folders with a uuid of its own making, and the
    /// engine names records with ids of its own — so without this the two can
    /// never be matched up again, and importing the same scout twice would
    /// make two of everything. It is also how the Mac finds the scans and the
    /// attachments, which stay as files: they are gigabytes of room, and the
    /// engine is not a place to put gigabytes of room.
    ///
    /// Empty on a location made on the Mac, which has no folder.
    pub const FOLDER: &str = "folder";
    /// **Which folder in Google Drive holds this location's photographs.**
    ///
    /// The Drive bridge (`bridge/`) keeps a location's pictures the same in the
    /// project and in his Google Drive, so a producer or a gaffer can see them
    /// without owning a copy of an app that was never published. The pairing is
    /// written down rather than guessed from the name, and that is the whole
    /// point of it: **the app owns a location's name**, so renaming one in
    /// Shotlister renames its Drive folder — and without this field a rename
    /// looks exactly like a location nobody has ever seen, and orphans its
    /// photographs in a folder still called the old thing.
    ///
    /// Asked for by name in `handoff/from-phone.md`, 2026-08-21: *"If you build
    /// `Kind::Location` in the engine, carry that field."*
    pub const DRIVE_FOLDER: &str = "drive_folder";
    /// **How the document page is set** — see `crate::docstyle`, which owns
    /// the encoding and is the only thing that reads or writes this.
    pub const DOC_STYLE: &str = "doc_style";
    /// **Whether this place's photographs travel to Google Drive.** Ref 229.
    ///
    /// His ask, 2026-08-22: *"It happens in the BG right now, but it's
    /// something that should be visible and something I can opt into if I so
    /// chose."* Carrying photographs out of a project and into a shared
    /// warehouse is not a thing to do to somebody by default.
    ///
    /// **Three states, not two, and the third is the important one.** `"1"` is
    /// on and `"0"` is off, but *absent* means nobody has ever been asked —
    /// which is not the same as having said no. Every location that existed
    /// before this field did is absent, and the bridge has been syncing some of
    /// them for days; reading absent as off would have silently stopped work
    /// that was already happening. The bridge grandfathers those in and writes
    /// down what it decided, so absent only ever means *undecided*, once.
    ///
    /// **On a mood board the same field reads the other way, and that is not
    /// an inconsistency.** Ref 229's second half, 2026-08-30: no board has
    /// ever been carried to Drive, so there is no work in progress to protect
    /// and absent safely means *no*. The rule underneath both is one rule —
    /// *never start carrying somebody's pictures out of the app without being
    /// told to, and never stop carrying ones already going* — and it happens
    /// to point in opposite directions for the two.
    pub const SYNC_WITH_DRIVE: &str = "sync_with_drive";
    /// **The location this one sits inside** — a reference to another
    /// `Kind::Location`, absent on a location that stands on its own.
    ///
    /// His ask, 2026-08-22 (Ref 269): *Call Her Back* is one house with one
    /// address, and inside it a kitchen, a master bedroom and a garage, each
    /// with its own scan and its own photographs. Without this there are two
    /// bad answers — one location holding a jumble of every room's pictures,
    /// or six locations each made to carry the same address and the same
    /// parking notes typed six times.
    ///
    /// **One level deep, and the engine enforces it.** A location inside a
    /// location inside a location is a filing system, and he asked for a way
    /// to organise a house, not a tree. `set_location_parent` refuses to make
    /// a grandchild.
    ///
    /// **The child inherits what it does not say.** Address, pin and notes
    /// come from the parent unless the child sets its own — which is the whole
    /// point of the ask, *"so we don't have to input the same address and
    /// logistical information on how to get to that house every location."*
    /// Reading them goes through `location_address`, `location_pin` and
    /// `location_notes`, never through `get` directly.
    pub const PARENT: &str = "parent";

    // shot
    pub const SIZE: &str = "size";
    pub const ANGLE: &str = "angle";
    pub const MOVEMENT: &str = "movement";
    pub const LENS: &str = "lens";
    /// **Where a zoom is set**, in millimetres — the Lens says `24-70mm`,
    /// this says 35. Read only while the Lens is a zoom (`lens::zoom_from_text`);
    /// a prime says its own. His ask, 2026-10-01.
    pub const FOCAL: &str = "focal";
    /// **What goes on the lens for this shot** — extenders, expanders,
    /// diopters ("Atlas LF Extender 1.6x"). Several; not tied to a lens, it
    /// sits beside whatever this shot's lens is. His ask, 2026-10-14.
    pub const MODIFIERS: &str = "modifiers";
    /// **The filters this shot uses** ("Tiffen ND .6", "Polarizer 138mm").
    /// Several. Not `filter`: that word is the table's filter command.
    pub const LENS_FILTERS: &str = "lens_filters";
    pub const SUPPORT: &str = "support";
    pub const UNIT: &str = "unit";
    pub const TAGS: &str = "tags";
    pub const SETUP: &str = "setup";
    pub const KEY_MEDIA: &str = "key_media";
    /// Whether `KEY_MEDIA` is a **decision** or merely the first frame that
    /// happened to land. Adding a picture to a shot takes over the lead frame,
    /// which is right — until somebody has said which one they want, and then
    /// it is silent destruction. This is what tells the two apart.
    pub const KEY_CHOSEN: &str = "key_chosen";
    pub const STRUCK: &str = "struck";
    /// **A shot other shots stand in for.** A film breaks a scene up and comes
    /// back to the same setup later; rather than describing it twice and
    /// letting the two drift, one shot is the master and the others point at
    /// it. His ask, 2026-08-22, carried over from the old app.
    pub const IS_MASTER: &str = "is_master";
    /// Which master this shot stands in for, if it stands in for one.
    pub const MASTER: &str = "master";
    /// A scene set aside without being destroyed — hidden from the working
    /// list, kept in the file, always reachable to bring back.
    pub const ARCHIVED: &str = "archived";
    pub const LAYOUT_WIDTH: &str = "layout_width";
    pub const LAYOUT_POSITION: &str = "layout_position";

    // placement
    pub const SHOT: &str = "shot";
    pub const SCENE: &str = "scene";
    pub const LETTER: &str = "letter";
    pub const DAY: &str = "day";
    pub const ORDER_IN_SCENE: &str = "order_in_scene";
    pub const ORDER_IN_DAY: &str = "order_in_day";

    // media file
    pub const HASH: &str = "hash";
    pub const MEDIA_KIND: &str = "media_kind";
    pub const WIDTH: &str = "width";
    pub const HEIGHT: &str = "height";
    pub const DURATION: &str = "duration";
    pub const BYTES: &str = "bytes";
    pub const FILENAME: &str = "filename";
    /// **When this picture was deleted from the Media window**, in
    /// milliseconds. The bytes are gone; the record stays as its name, so a
    /// version that showed it can say what was there. `crate::shelf`.
    pub const GONE_ON: &str = "gone_on";
    /// **What the stored file was made from.** Ref 211. A small copy is filed
    /// under the hash of *itself*, which is what lets a stored file check
    /// itself against its own name — so two small copies of one clip that came
    /// out even slightly different are two files as far as a project is
    /// concerned. This remembers the clip they were both made from, so the
    /// second one is recognised before it is ever encoded.
    pub const SOURCE: &str = "source";

    // one draft of the screenplay
    pub const IMPORTED_AT: &str = "imported_at";
    /// On a scene: the revision it was last seen in.
    pub const REVISION: &str = "revision";
    /// On a scene: how much page it takes, in eighths, as measured when the
    /// draft was taken in. Stored rather than recomputed because working it out
    /// means laying the whole screenplay out again.
    pub const EIGHTHS: &str = "eighths";
    /// On a scene: the page its heading is printed on.
    pub const SCRIPT_PAGE: &str = "script_page";
    /// On a scene: who speaks in it, according to the script.
    pub const CAST: &str = "cast";
    /// On a scene: its slug exactly as the script printed it. Kept because a
    /// heading is only reconstructable when the script wrote it in the usual
    /// shape, and plenty do not.
    pub const HEADING: &str = "heading";

    // one use of a media file
    pub const MEDIA: &str = "media";
    pub const OWNER: &str = "owner";
    pub const CAPTION: &str = "caption";
    /// **Non-destructive trim, in seconds.** The original file is never
    /// touched or re-encoded — this is just the range *this use* of a clip
    /// plays back. Absent on both means the whole clip, same as before trim
    /// existed. His call, 2026-08-28: the original always stays whole.
    pub const TRIM_START: &str = "trim_start";
    pub const TRIM_END: &str = "trim_end";
    /// **Which part of a picture is kept when it is drawn cropped**, and how
    /// close in — his ask, 2026-08-30.
    ///
    /// A wall set to squares, a table cell, a storyboard plate: all of them
    /// take a picture that is not that shape and keep the middle of it, which
    /// is the wrong half of a photograph about as often as it is the right
    /// one. These three say what to keep instead: `crop_x` and `crop_y` are
    /// the point of the picture that should end up in the middle, each from
    /// nought to one, and `crop_scale` is how far in, where one is the whole
    /// picture.
    ///
    /// **It belongs to this *use* of the file, exactly like the trim**, so the
    /// same photograph on a board and on a shot can be framed two ways, and
    /// the file itself is never touched. Absent means the middle, at full
    /// width — what every picture in the app did before this existed.
    pub const CROP_X: &str = "crop_x";
    pub const CROP_Y: &str = "crop_y";
    pub const CROP_SCALE: &str = "crop_scale";

    /// **Storyboard arrows drawn over a picture** — his ask, 2026-08-31:
    /// arrows over a still to say how the shot or the character moves.
    ///
    /// The traditional mark, and the one every board he has ever read uses:
    /// a curved arrow lying on the photograph, pointing where the thing goes.
    /// Two straight ones top and bottom is a pan, two curved ones at the sides
    /// is a tilt, four in the corners is a push in or a pull out — all of them
    /// the *same* arrow placed differently, which is why there is one mark
    /// here and not six.
    ///
    /// **It belongs to this use of the file, exactly like the crop and the
    /// trim.** The same photograph on a board and on a shot can carry
    /// different arrows, and the file is never touched.
    ///
    /// Held as one line of text so a change is one entry in the log and two
    /// devices merge it the way they merge any other field: arrows separated
    /// by `;`, each of them seven numbers separated by `,` — tail, bend, head,
    /// and how many heads. Every coordinate is a fraction of the *picture*,
    /// not of the tile, so an arrow stays on the thing it was drawn on however
    /// the picture is cropped or how big it is drawn. Absent means no arrows,
    /// which is every picture in the app until somebody draws one.
    pub const ARROWS: &str = "arrows";

    /// **On a shot: its Print Frame** — the board that stands for the shot on
    /// paper, as canonical JSON (`crate::printframe`). Absent means none, and
    /// the shot prints as it always has.
    pub const PRINT_FRAME: &str = "print_frame";
    /// On a shot: the picture the Mac last baked from its Print Frame, and
    /// the digest of the spec it was baked from (`crate::printframe::Baked`).
    pub const PRINT_FRAME_BAKED: &str = "print_frame_baked";

    // custom column: the slug shots store values under, and what shape the
    // values are — text, single, multi, check, media, location
    pub const FIELD: &str = "field";
    pub const COLUMN_KIND: &str = "column_kind";

    // shared
    pub const DESCRIPTION: &str = "description";
    pub const NOTES: &str = "notes";
    pub const COLOUR: &str = "colour";
    /// On a scene: its diagram's settings and where its room came from, as
    /// JSON. The elements themselves are `diagram_item` records.
    pub const DIAGRAM: &str = "diagram";
    pub const LABEL: &str = "label";
    pub const BODY: &str = "body";
    /// On a camera: the sensor it reads, as he typed it — a name and the
    /// width and height in millimetres (`Doc::set_unit_sensor`).
    pub const SENSOR_NAME: &str = "sensor_name";
    pub const SENSOR_W: &str = "sensor_w";
    pub const SENSOR_H: &str = "sensor_h";
    pub const DATE: &str = "date";
    pub const ORDER: &str = "order";
    /// **The shoot a scene or a day belongs to** (stage 5 step 4, piece D):
    /// the project's Shoot, by its bare id, as the card lists it. See
    /// `crate::shoots`.
    pub const SHOOT: &str = "shoot";
    /// On a day that belongs to a shoot: which day of the shoot it is, counted
    /// from the shoot's first day (0 is the first). The day's date follows the
    /// shoot's: move the shoot and its days move with it.
    pub const SHOOT_DAY: &str = "shoot_day";
    /// On the project: **the frame Studio draws at**, by the name the spec
    /// sheet gives it (stage 5 step 4, piece E). See `crate::frames`.
    pub const STUDIO_FRAME: &str = "studio_frame";
    /// On the project: whether the project's other frames show as guide lines.
    pub const FRAME_GUIDES: &str = "frame_guides";
}

pub struct Doc {
    store: Store,
    clock: Clock,
    letters: LetterScheme,
    /// Open transaction, if one is running.
    pub(crate) recording: Option<Vec<UndoEntry>>,
    pub(crate) recording_label: String,
    pub(crate) undo_stack: Vec<UndoStep>,
    pub(crate) redo_stack: Vec<UndoStep>,
    /// What day it is, as the shell understands it. The engine has no clock.
    pub(crate) today: Option<String>,
    /// **The project's card, laid over the film** (`crate::card`): never
    /// written, never synced, set by the shell for the session.
    pub(crate) card: Option<crate::card::Card>,
    /// **The shoot new scenes and days are born into** — the one the shoot
    /// picker is on (`crate::shoots`). Session only, like the card.
    pub(crate) new_in: Option<String>,
}

impl Doc {
    pub fn new(device: DeviceId) -> Doc {
        Doc {
            store: Store::new(),
            clock: Clock::new(device),
            letters: LetterScheme::default(),
            recording: None,
            recording_label: String::new(),
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            today: None,
            card: None,
            new_in: None,
        }
    }

    pub fn with_letter_scheme(device: DeviceId, letters: LetterScheme) -> Doc {
        Doc {
            store: Store::new(),
            clock: Clock::new(device),
            letters,
            recording: None,
            recording_label: String::new(),
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            today: None,
            card: None,
            new_in: None,
        }
    }

    pub fn store(&self) -> &Store {
        &self.store
    }

    pub fn letters(&self) -> &LetterScheme {
        &self.letters
    }

    pub fn device(&self) -> DeviceId {
        self.clock.device()
    }

    // ---- writing -------------------------------------------------------

    fn next_stamp(&mut self) -> Stamp {
        self.clock.tick()
    }

    /// Create a bare record of any kind. Used by the modules that extend `Doc`
    /// with their own vocabulary of operations.
    pub fn create_record(&mut self, kind: Kind) -> Id {
        self.create(kind)
    }

    pub(crate) fn create(&mut self, kind: Kind) -> Id {
        self.create_as(kind, Id::new())
    }

    /// `create`, under an id the caller chose — the portal's page and the
    /// server it sends to must make a new loose plan under one id between
    /// them, or the edits that follow could not find it (`add_plan_with`).
    pub(crate) fn create_as(&mut self, kind: Kind, id: Id) -> Id {
        let seen = self.clock.watermark();
        let stamp = self.next_stamp();
        let label = format!("Add {}", kind.as_str().replace('_', " "));
        self.store.apply(Change {
            stamp,
            seen,
            op: Op::Create { kind, id },
        });
        // Undoing a creation is deleting the record, which the tombstone model
        // makes reversible in turn — nothing is destroyed either way. `after`
        // is `Null`, not `false`: creation leaves the tombstone field unset,
        // and undo only fires when the field still holds what this action left
        // it as. `Bool(false)` here meant undo never matched, and every
        // undone creation quietly stayed.
        self.record(
            &label,
            UndoEntry {
                id,
                field: F_DELETED.to_string(),
                before: Value::Bool(true),
                after: Value::Null,
            },
        );
        id
    }

    /// Create a record that no undo reaches — for the bookkeeping a person did
    /// not do by hand, where ⌘Z taking it back would undo nothing he did. A
    /// version saved on his behalf is the one user; `write_without_recording`
    /// is its partner for the fields.
    pub(crate) fn create_quietly(&mut self, kind: Kind) -> Id {
        let id = Id::new();
        let seen = self.clock.watermark();
        let stamp = self.next_stamp();
        self.store.apply(Change {
            stamp,
            seen,
            op: Op::Create { kind, id },
        });
        id
    }

    pub fn set(&mut self, id: Id, field: &str, value: impl Into<Value>) {
        let value = value.into();
        let before = self
            .store
            .get_raw(id)
            .and_then(|record| record.get(field).cloned())
            .unwrap_or(Value::Null);
        self.write_without_recording(id, field, value.clone());
        // **Writing a value that is already there is not an undoable action.**
        // The write itself still happens — it ticks the clock, and a device
        // saying "this is what I think it is" is worth something to a merge —
        // but recording it put a step on the pile that puts nothing back.
        // Undo then appeared broken: the menu offered an action, the keystroke
        // did nothing, and the real change he wanted back was one further down.
        if before == value {
            return;
        }
        let label = if self.recording.is_some() {
            String::new()
        } else {
            format!("Change {field}")
        };
        self.record(
            &label,
            UndoEntry {
                id,
                field: field.to_string(),
                before,
                after: value,
            },
        );
    }

    /// Apply a change with no undo entry — used by undo and redo themselves,
    /// which must not be undoable in the same breath.
    pub(crate) fn write_without_recording(&mut self, id: Id, field: &str, value: Value) {
        // Read before ticking: what this device knew when it decided to write,
        // which is what a later reader needs to judge a disagreement.
        let seen = self.clock.watermark();
        let stamp = self.next_stamp();
        self.store.apply(Change {
            stamp,
            seen,
            op: Op::Set {
                id,
                field: field.to_string(),
                value,
            },
        });
    }

    pub fn delete(&mut self, id: Id) {
        self.set(id, F_DELETED, true);
    }

    pub fn undelete(&mut self, id: Id) {
        self.set(id, F_DELETED, false);
    }

    /// Merge changes from another device. Advances our clock so subsequent local
    /// writes sort after everything we have seen.
    pub fn merge(&mut self, changes: impl IntoIterator<Item = Change>) {
        for change in changes {
            self.clock.observe(&change.stamp);
            self.store.apply(change);
        }
    }

    pub fn changes(&self) -> &[Change] {
        self.store.log()
    }

    /// Advance the clock past a stamp without applying anything — how a
    /// restored document comes to have heard what its snapshot covers.
    pub(crate) fn hear(&mut self, stamp: &Stamp) {
        self.clock.observe(stamp);
    }

    pub(crate) fn put_store(&mut self, store: Store) {
        self.store = store;
    }

    // ---- creating records ----------------------------------------------

    pub fn create_project(&mut self, title: &str) -> Id {
        let id = self.create(Kind::Project);
        self.set(id, f::TITLE, title);
        id
    }

    /// A new scene, **landing where its number says it belongs**.
    ///
    /// It used to be appended, and that is what he found on 2026-08-22: taking
    /// a draft running 1–20 into a project already holding 33, 34, 35 and 54
    /// put all twenty at the bottom, so the film read 33, 34, 35, 54, 1, 2,
    /// 3… The same rule makes a scene added by hand land in its place, which is
    /// the only thing a number can reasonably mean.
    ///
    /// **Nothing already in the list moves.** A scene is placed between the two
    /// it belongs between; scenes somebody has deliberately arranged keep the
    /// order they were given. A scene with no number at all is no landmark —
    /// it could belong anywhere — so it is never used as one.
    pub fn create_scene(&mut self, number: &str) -> Id {
        let tx = self.begin("Add scene");

        let mut standing: Vec<(f64, String)> = self
            .store
            .of_kind(&Kind::Scene)
            .iter()
            .map(|r| {
                (
                    r.float(f::ORDER).unwrap_or(0.0),
                    r.text(f::NUMBER).unwrap_or_default().to_string(),
                )
            })
            .collect();
        standing.sort_by(|a, b| order::compare(a.0, b.0));

        let after = standing.iter().position(|(_, existing)| {
            !existing.is_empty()
                && crate::natural::compare(existing, number) == std::cmp::Ordering::Greater
        });
        let landing = match after {
            Some(0) => order::between(None, Some(standing[0].0)),
            Some(at) => order::between(Some(standing[at - 1].0), Some(standing[at].0)),
            None => order::after_last(
                &standing.iter().map(|(at, _)| *at).collect::<Vec<f64>>(),
            ),
        };

        let id = self.create(Kind::Scene);
        self.set(id, f::NUMBER, number);
        self.set(id, f::ORDER, landing);
        if let Some(shoot) = self.shoot_to_be_born_in() {
            self.set(id, f::SHOOT, Value::text(shoot));
        }
        self.end(tx);
        id
    }

    pub fn create_shot(&mut self) -> Id {
        self.create(Kind::Shot)
    }

    /// **The colours a sequence is born with**, in turn. His finding,
    /// 2026-09-19: three scripts in one commercial were not telling apart in
    /// the table, and a section with no colour is a grey square like every
    /// other. The same inks the columns wear (`Brand.columnInks`), so a
    /// section's spine reads as one of the app's own colours; a person can
    /// still set another.
    pub const SEQUENCE_COLOURS: [&'static str; 8] = [
        "#2B6CB0", "#B4531B", "#2F7A44", "#7B4BC4",
        "#A33574", "#2C7A7B", "#9A6B10", "#4C51BF",
    ];

    pub fn create_sequence(&mut self, title: &str) -> Id {
        let tx = self.begin("Add sequence");

        let existing: Vec<f64> = self
            .store
            .of_kind(&Kind::Sequence)
            .iter()
            .filter_map(|r| r.float(f::ORDER))
            .collect();
        let colour = Self::SEQUENCE_COLOURS[existing.len() % Self::SEQUENCE_COLOURS.len()];
        let id = self.create(Kind::Sequence);
        self.set(id, f::TITLE, title);
        self.set(id, f::ORDER, order::after_last(&existing));
        self.set(id, f::COLOUR, colour);
        self.end(tx);
        id
    }

    /// **Every sequence with no colour gets one**, in the order they were
    /// made, from the same palette a new one is born with. True when any
    /// changed. Run at open, once, for films from before 2026-09-19.
    pub fn colour_bare_sequences(&mut self) -> bool {
        let bare: Vec<(usize, Id)> = self
            .sequences_in_order()
            .into_iter()
            .enumerate()
            .filter(|(_, id)| {
                self.get(*id)
                    .and_then(|r| r.text(f::COLOUR))
                    .map(|c| c.trim().is_empty())
                    .unwrap_or(true)
            })
            .collect();
        if bare.is_empty() {
            return false;
        }
        let tx = self.begin("Colour sequences");
        for (at, id) in bare {
            self.set(id, f::COLOUR, Self::SEQUENCE_COLOURS[at % Self::SEQUENCE_COLOURS.len()]);
        }
        self.end(tx);
        true
    }

    /// **A scene moved as one block within its day**, to sit before another
    /// scene's first shot there — or last, given `None`. His ask,
    /// 2026-09-19: *"should be easier to adjust order of scenes in schedule
    /// within a day."* Every placement of the scene on that day travels,
    /// keeping its own order; a scene split across days moves only the part
    /// that is on this one. Nothing else on the day changes place.
    pub fn move_scene_in_day(&mut self, scene: Id, day: Id, before: Option<Id>) {
        let on_day = self.placements_on_day(day);
        let mine: Vec<Id> = on_day
            .iter()
            .copied()
            .filter(|p| self.get(*p).and_then(|r| r.ref_id(f::SCENE)) == Some(scene))
            .collect();
        if mine.is_empty() {
            return;
        }
        let others: Vec<Id> = on_day.iter().copied().filter(|p| !mine.contains(p)).collect();
        let at = match before {
            None => others.len(),
            Some(other) => match others
                .iter()
                .position(|p| self.get(*p).and_then(|r| r.ref_id(f::SCENE)) == Some(other))
            {
                Some(i) => i,
                None => return,
            },
        };
        let position = |p: Option<&Id>| p.and_then(|id| self.get(*id)).and_then(|r| r.float(f::ORDER_IN_DAY));
        let (mut low, high) = (
            if at == 0 { None } else { position(others.get(at - 1)) },
            position(others.get(at)),
        );
        let tx = self.begin("Move scene in day");
        for p in &mine {
            let here = order::between(low, high);
            self.set(*p, f::ORDER_IN_DAY, Value::Float(here));
            low = Some(here);
        }
        self.end(tx);
    }

    /// **Take a sequence away.** Its scenes stay, and leave the sequence —
    /// nothing else about them changes. Undoable as one step.
    pub fn delete_sequence(&mut self, sequence: Id) -> usize {
        let scenes: Vec<Id> = self
            .scenes_in_order()
            .into_iter()
            .filter(|s| self.get(*s).and_then(|r| r.ref_id(f::SEQUENCE)) == Some(sequence))
            .collect();
        let tx = self.begin("Remove sequence");
        for scene in &scenes {
            self.set(*scene, f::SEQUENCE, Value::Null);
        }
        self.delete(sequence);
        self.end(tx);
        scenes.len()
    }

    /// **Move a scene in the list**, to sit just after `after` — or first,
    /// given `None`. Order only: its number, its shots and their letters are
    /// exactly what they were. *Scene numbers belong to the script; we never
    /// renumber.* A commercial that wants its numbers to follow the list asks
    /// for that separately (`renumber_in_order`), as a person's decision.
    pub fn move_scene_after(&mut self, scene: Id, after: Option<Id>) {
        let list: Vec<Id> = self.scenes_in_order().into_iter().filter(|s| *s != scene).collect();
        let position = |id: Id| self.get(id).and_then(|r| r.float(f::ORDER));
        let at = match after {
            None => 0,
            Some(a) => match list.iter().position(|s| *s == a) {
                Some(i) => i + 1,
                None => return,
            },
        };
        let before = if at == 0 { None } else { position(list[at - 1]) };
        let next = list.get(at).and_then(|s| position(*s));
        let tx = self.begin("Move scene");
        self.set(scene, f::ORDER, Value::Float(order::between(before, next)));
        self.end(tx);
    }

    // ------------------------------------------------------------- locations
    //
    // **A location the crew actually goes to.** Ref 57, and the one thing the phone
    // thread has been blocked on: it has been writing `locations/<id>/…` beside
    // the project because there was nowhere in the engine to put a location. The
    // field names here are its JSON field names, so reading those files in is a
    // copy rather than a translation.
    //
    // Photographs are not special: they are `Kind::Media` attached through
    // `Kind::MediaRef`, exactly as a shot's frames are. A location that
    // invented its own way to hold a picture would be a second answer to a
    // question already answered.

    pub fn create_location(&mut self, name: &str) -> Id {
        let tx = self.begin("Add location");
        let existing: Vec<f64> = self
            .store
            .of_kind(&Kind::Location)
            .iter()
            .filter_map(|r| r.float(f::ORDER))
            .collect();
        let id = self.create(Kind::Location);
        self.set(id, f::LABEL, name);
        self.set(id, f::ORDER, order::after_last(&existing));
        self.end(tx);
        id
    }

    /// Every location, in the order they were added. Deleted ones are already gone
    /// from `of_kind`.
    pub fn locations_in_order(&self) -> Vec<Id> {
        let mut all = self.store.of_kind(&Kind::Location);
        all.sort_by(|a, b| {
            a.float(f::ORDER)
                .unwrap_or(0.0)
                .partial_cmp(&b.float(f::ORDER).unwrap_or(0.0))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        all.into_iter().map(|r| r.id).collect()
    }

    pub fn location_named(&self, name: &str) -> Option<Id> {
        self.store
            .of_kind(&Kind::Location)
            .into_iter()
            .find(|r| r.text(f::LABEL).map(|l| l.eq_ignore_ascii_case(name)) == Some(true))
            .map(|r| r.id)
    }

    /// Add a location *inside* another one — a room, a wing, a back lot.
    ///
    /// Refuses to nest below one level: if `parent` is itself inside
    /// something, the new location is created beside it rather than under it,
    /// so a mis-click makes a sibling and never a lost grandchild.
    pub fn create_location_in(&mut self, parent: Id, name: &str) -> Id {
        let parent = self.parent_of_location(parent).unwrap_or(parent);
        let tx = self.begin("Add area");
        let id = self.create_location(name);
        self.set(id, f::PARENT, Value::Ref(parent));
        self.end(tx);
        id
    }

    /// Which location this one sits inside, if any.
    pub fn parent_of_location(&self, place: Id) -> Option<Id> {
        let parent = self.get(place)?.ref_id(f::PARENT)?;
        // A pointer at a location that has since been deleted is the same as
        // no pointer at all — the record outlives the thing it named, and a
        // list that showed a room under a house nobody can open is worse than
        // one that shows the room on its own.
        self.get(parent).map(|_| parent)
    }

    /// Move a location under another, or out to stand on its own.
    ///
    /// Returns `false` and changes nothing when the move would make a
    /// grandchild, a cycle, or a parent of something that already has
    /// children of its own. **One level, always** — see `f::PARENT`.
    pub fn set_location_parent(&mut self, place: Id, parent: Option<Id>) -> bool {
        if self.get(place).is_none() {
            return false;
        }
        if let Some(parent) = parent {
            if parent == place || self.get(parent).is_none() {
                return false;
            }
            // Neither end may already be nested: a parent with a parent would
            // make a grandchild, and a child with children would take its own
            // rooms down a level with it.
            if self.parent_of_location(parent).is_some() || !self.areas_of(place).is_empty() {
                return false;
            }
        }
        let tx = self.begin("Move location");
        match parent {
            Some(parent) => self.set(place, f::PARENT, Value::Ref(parent)),
            None => self.set(place, f::PARENT, Value::Text(String::new())),
        }
        self.end(tx);
        true
    }

    /// The locations that stand on their own — everything not inside something
    /// else, in order.
    pub fn top_locations(&self) -> Vec<Id> {
        self.locations_in_order()
            .into_iter()
            .filter(|id| self.parent_of_location(*id).is_none())
            .collect()
    }

    /// The locations inside this one, in order. Empty for a room.
    pub fn areas_of(&self, place: Id) -> Vec<Id> {
        self.locations_in_order()
            .into_iter()
            .filter(|id| self.parent_of_location(*id) == Some(place))
            .collect()
    }

    /// A field read the way a room reads it: its own value if it has one,
    /// otherwise the house's.
    ///
    /// **Blank means "not said", not "deliberately empty".** A room that wants
    /// no address at all cannot express that, and does not need to — the whole
    /// reason the field exists is that every room in the house shares one.
    fn inherited(&self, place: Id, field: &str) -> String {
        let own = self
            .get(place)
            .and_then(|r| r.text(field).map(str::to_string))
            .unwrap_or_default();
        if !own.trim().is_empty() {
            return own;
        }
        self.parent_of_location(place)
            .and_then(|parent| self.get(parent).and_then(|r| r.text(field).map(str::to_string)))
            .unwrap_or_default()
    }

    /// Where this location is, falling back to the house it is a room in.
    pub fn location_address(&self, place: Id) -> String {
        self.inherited(place, f::ADDRESS)
    }

    /// The pin, falling back to the house's. Both halves come from the same
    /// record — a room with its own latitude and the house's longitude would
    /// be a point in the sea.
    pub fn location_pin(&self, place: Id) -> Option<(String, String)> {
        let own = |id: Id| -> Option<(String, String)> {
            let r = self.get(id)?;
            let lat = r.text(f::LATITUDE).unwrap_or_default().trim().to_string();
            let lon = r.text(f::LONGITUDE).unwrap_or_default().trim().to_string();
            (!lat.is_empty() && !lon.is_empty()).then_some((lat, lon))
        };
        own(place).or_else(|| self.parent_of_location(place).and_then(own))
    }

    /// How to get in, where to park, who to ask — the house's, unless the room
    /// says its own.
    pub fn location_notes(&self, place: Id) -> String {
        self.inherited(place, f::NOTES)
    }

    /// What to call a location when it appears away from its own screen — on a
    /// scene, in a filter, on the phone. `Hillcrest House — Kitchen`.
    pub fn location_full_name(&self, place: Id) -> String {
        let own = self
            .get(place)
            .and_then(|r| r.text(f::LABEL).map(str::to_string))
            .unwrap_or_default();
        match self.parent_of_location(place) {
            Some(parent) => {
                let house = self
                    .get(parent)
                    .and_then(|r| r.text(f::LABEL).map(str::to_string))
                    .unwrap_or_default();
                if house.trim().is_empty() {
                    own
                } else {
                    format!("{house} — {own}")
                }
            }
            None => own,
        }
    }

    /// Every scene shot at this location **or in any of its rooms** — what a
    /// house should say when asked how much of the film hangs on it.
    ///
    /// `scenes_at_location` stays exact on purpose: a room's own list must not
    /// swell with the rest of the house's scenes.
    pub fn scenes_at_location_or_inside(&self, place: Id) -> Vec<Id> {
        let mut inside: Vec<Id> = vec![place];
        inside.extend(self.areas_of(place));
        self.scenes_in_order()
            .into_iter()
            .filter(|scene| {
                self.scene_locations(*scene)
                    .iter()
                    .any(|at| inside.contains(at))
            })
            .collect()
    }

    /// Point a scene at a location record, or at none.
    ///
    /// **This does not touch the scene's `location` text.** That is the
    /// script's word for where the scene happens and is never ours to edit;
    /// this is where the crew is going, which is a different fact.
    pub fn set_scene_location(&mut self, scene: Id, place: Option<Id>) {
        let tx = self.begin("Set location");
        self.write_scene_locations(scene, &place.map(|p| vec![p]).unwrap_or_default());
        self.end(tx);
    }

    /// Every location this scene is shot at, in the order they were added.
    ///
    /// A scene written before 2026-08-22 has only the single field, and reads
    /// back as a list of one — so nothing has to be migrated and an older build
    /// opening the same project still understands it.
    pub fn scene_locations(&self, scene: Id) -> Vec<Id> {
        let Some(record) = self.get(scene) else {
            return Vec::new();
        };
        if let Some(list) = record.get(f::LOCATION_IDS).and_then(|v| v.as_list()) {
            let places: Vec<Id> = list
                .iter()
                .filter_map(|v| v.as_ref_id())
                .filter(|place| self.get(*place).is_some())
                .collect();
            if !places.is_empty() {
                return places;
            }
        }
        record.ref_id(f::LOCATION_ID).into_iter().collect()
    }

    /// Add one more place to a scene. Returns false if it was already there.
    pub fn add_scene_location(&mut self, scene: Id, place: Id) -> bool {
        let mut places = self.scene_locations(scene);
        if places.contains(&place) || self.get(place).is_none() {
            return false;
        }
        places.push(place);
        let tx = self.begin("Add location");
        self.write_scene_locations(scene, &places);
        self.end(tx);
        true
    }

    /// Take one place off a scene, leaving the others. Returns false if the
    /// scene was not shot there.
    pub fn remove_scene_location(&mut self, scene: Id, place: Id) -> bool {
        let mut places = self.scene_locations(scene);
        let before = places.len();
        places.retain(|held| *held != place);
        if places.len() == before {
            return false;
        }
        let tx = self.begin("Remove location");
        self.write_scene_locations(scene, &places);
        self.end(tx);
        true
    }

    /// The list and its mirror, written together — the only place either is
    /// written, so the first of the list and `LOCATION_ID` cannot drift apart.
    fn write_scene_locations(&mut self, scene: Id, places: &[Id]) {
        match places.first() {
            Some(first) => self.set(scene, f::LOCATION_ID, Value::Ref(*first)),
            None => self.set(scene, f::LOCATION_ID, Value::Text(String::new())),
        }
        if places.len() > 1 {
            let list = Value::List(places.iter().map(|p| Value::Ref(*p)).collect());
            self.set(scene, f::LOCATION_IDS, list);
        } else {
            // One place, or none, leaves no list behind to go stale.
            self.set(scene, f::LOCATION_IDS, Value::List(Vec::new()));
        }
    }

    /// The scene's main location — the first of them when there are several.
    pub fn location_of_scene(&self, scene: Id) -> Option<Id> {
        self.scene_locations(scene).first().copied()
    }

    /// Which scenes are shot at a location — the other direction, for a
    /// Locations list that wants to say how much of the film hangs on one
    /// address.
    /// **Which scenes hang this board.** The other direction of the link that
    /// already exists (Ref 348): a scene has always been able to say which
    /// boards it points at, and a board could not say who was pointing at it,
    /// so the link could only be made and broken from the scene's side.
    ///
    /// Read rather than stored, exactly like `scenes_at_location` beside it —
    /// one list to keep, so the two directions cannot disagree.
    pub fn scenes_with_board(&self, board: Id) -> Vec<Id> {
        self.scenes_in_order()
            .into_iter()
            .filter(|scene| self.scene_boards(*scene).contains(&board))
            .collect()
    }

    pub fn scenes_at_location(&self, place: Id) -> Vec<Id> {
        self.scenes_in_order()
            .into_iter()
            .filter(|scene| self.scene_locations(*scene).contains(&place))
            .collect()
    }

    /// Take a location out. **The scenes that pointed at it lose the pointer
    /// and nothing else** — report-never-destroy: deleting a location must not
    /// quietly take a scene's own words with it.
    ///
    /// **The rooms inside it survive and come up a level**, keeping their own
    /// photographs, scans and scenes. Deleting a house is not a decision about
    /// its kitchen — and the alternative, taking six rooms down with one click,
    /// is exactly the kind of quiet destruction the law forbids. What they do
    /// lose is the address they were borrowing, which is why the Mac says how
    /// many rooms are about to come loose before it does this.
    pub fn delete_location(&mut self, place: Id) {
        let tx = self.begin("Delete location");
        for area in self.areas_of(place) {
            self.set(area, f::PARENT, Value::Text(String::new()));
        }
        for scene in self.scenes_at_location(place) {
            let mut places = self.scene_locations(scene);
            places.retain(|held| *held != place);
            self.write_scene_locations(scene, &places);
        }
        // Its photographs and scans go with it unless something else holds
        // them (`release_media_use`, his ruling 2026-09-19). The originals
        // in `locations/<folder>/` are the bridge's and are not touched.
        self.release_media_uses(place);
        self.delete(place);
        self.end(tx);
    }

    /// **Locations that have been deleted but still name a Drive folder.**
    ///
    /// For the Drive bridge, and the reason it exists is a loop that ran for
    /// a night on *Mirrorland* (2026-09-18): a location deleted in the app
    /// leaves its folder in Drive — the bridge destroys nothing — and the
    /// bridge, seeing a folder no location claimed, made it a location again
    /// fifteen seconds later. Every delete came back, twice over on the
    /// second pass, because the record it stamped afterwards was found by
    /// name and that name already belonged to a room. The tombstone is what
    /// tells the two apart: a folder a deleted location once named is that
    /// deletion's leftover, not something somebody made by hand.
    ///
    /// Each entry is `(id, drive folder)`. A deleted location that never had
    /// a folder is left out — there is nothing in Drive for it to explain.
    pub fn retired_drive_folders(&self) -> Vec<(Id, String)> {
        self.store
            .tombstones_of_kind(&Kind::Location)
            .into_iter()
            .filter_map(|r| {
                let held = r.text(f::DRIVE_FOLDER)?.trim();
                (!held.is_empty()).then(|| (r.id, held.to_string()))
            })
            .collect()
    }

    /// The bridge has moved a deleted location's folder aside: forget the
    /// folder, so a folder of the same name made by hand later is honoured
    /// as new rather than swept away again. A write on a tombstone, on
    /// purpose — `set` reads the raw record for exactly this.
    pub fn forget_retired_drive_folder(&mut self, place: Id) {
        if self.store.get_raw(place).is_none() {
            return;
        }
        let tx = self.begin("Retire Drive folder");
        self.set(place, f::DRIVE_FOLDER, Value::Text(String::new()));
        self.end(tx);
    }

    // ---- mood boards ------------------------------------------------------
    //
    // A board is a name and an ordered wall of pictures. That is the whole
    // record: `attach_media` and `media_refs` are already generic over their
    // owner, so a board holds photographs the same way a shot holds frames and
    // a location holds its photographs, and none of that had to be written
    // again.
    //
    // **Deliberately not tied to a scene.** A mood board is usually about a
    // look rather than a moment — *Night Exteriors*, *Anya*, *The Diner* — and
    // one board serves twenty scenes. Linking is its own decision and its own
    // row; nothing here forecloses it.

    pub fn create_board(&mut self, name: &str) -> Id {
        let tx = self.begin("Add mood board");
        let existing: Vec<f64> = self
            .store
            .of_kind(&Kind::MoodBoard)
            .iter()
            .filter_map(|r| r.float(f::ORDER))
            .collect();
        let id = self.create(Kind::MoodBoard);
        self.set(id, f::LABEL, name);
        self.set(id, f::ORDER, order::after_last(&existing));
        self.end(tx);
        id
    }

    /// Every board, in the order they were added.
    ///
    /// Deleted ones are already gone from `of_kind`. **Nameless ones are
    /// skipped**, which is how ⌘Z after *Add mood board* works: undo here is
    /// field-level, so taking back a creation clears the record's fields and
    /// leaves a husk rather than removing it. Columns and units answer this
    /// the same way, and a board with no name is the same husk — it would
    /// otherwise sit in the sidebar as a blank row nothing could remove.
    pub fn boards_in_order(&self) -> Vec<Id> {
        let mut all: Vec<_> = self
            .store
            .of_kind(&Kind::MoodBoard)
            .into_iter()
            .filter(|r| !r.text(f::LABEL).unwrap_or_default().is_empty())
            .collect();
        all.sort_by(|a, b| {
            a.float(f::ORDER)
                .unwrap_or(0.0)
                .partial_cmp(&b.float(f::ORDER).unwrap_or(0.0))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        all.into_iter().map(|r| r.id).collect()
    }

    pub fn board_named(&self, name: &str) -> Option<Id> {
        self.store
            .of_kind(&Kind::MoodBoard)
            .into_iter()
            .find(|r| r.text(f::LABEL).map(|l| l.eq_ignore_ascii_case(name)) == Some(true))
            .map(|r| r.id)
    }

    pub fn board_name(&self, board: Id) -> String {
        self.get(board)
            .and_then(|r| r.text(f::LABEL).map(str::to_string))
            .unwrap_or_default()
    }

    pub fn rename_board(&mut self, board: Id, name: &str) {
        let tx = self.begin("Rename mood board");
        self.set(board, f::LABEL, name);
        self.end(tx);
    }

    /// **The pictures stay.** Deleting a board takes away the wall, not the
    /// photographs on it: a `Kind::Media` is addressed by its contents and may
    /// be on a shot and a location as well, so only this board's *uses* of
    /// them go. Report, never invent — and never destroy.
    ///
    /// **Scenes that linked this board lose the link and nothing else** — the
    /// same law `delete_location` follows for the scenes shot there.
    pub fn delete_board(&mut self, board: Id) {
        let tx = self.begin("Delete mood board");
        // …and a photograph on no other wall goes for good (his ruling,
        // 2026-09-19 — `release_media_use`).
        self.release_media_uses(board);
        for scene in self.scenes_in_order() {
            let mut boards = self.scene_boards(scene);
            let before = boards.len();
            boards.retain(|held| *held != board);
            if boards.len() != before {
                self.write_scene_boards(scene, &boards);
            }
        }
        self.delete(board);
        self.end(tx);
    }

    /// Every mood board this scene links to, in the order they were added.
    /// **Not tied to a location or a shot** — a scene's boards are its own
    /// list, the same shape `scene_locations` uses.
    pub fn scene_boards(&self, scene: Id) -> Vec<Id> {
        let Some(record) = self.get(scene) else {
            return Vec::new();
        };
        let Some(list) = record.get(f::BOARD_IDS).and_then(|v| v.as_list()) else {
            return Vec::new();
        };
        list.iter()
            .filter_map(|v| v.as_ref_id())
            .filter(|board| self.get(*board).is_some())
            .collect()
    }

    /// Link one more board to a scene. Returns false if it was already linked.
    pub fn add_scene_board(&mut self, scene: Id, board: Id) -> bool {
        let mut boards = self.scene_boards(scene);
        if boards.contains(&board) || self.get(board).is_none() {
            return false;
        }
        boards.push(board);
        let tx = self.begin("Link mood board");
        self.write_scene_boards(scene, &boards);
        self.end(tx);
        true
    }

    /// Unlink one board from a scene, leaving the others. Returns false if it
    /// was not linked.
    pub fn remove_scene_board(&mut self, scene: Id, board: Id) -> bool {
        let mut boards = self.scene_boards(scene);
        let before = boards.len();
        boards.retain(|held| *held != board);
        if boards.len() == before {
            return false;
        }
        let tx = self.begin("Unlink mood board");
        self.write_scene_boards(scene, &boards);
        self.end(tx);
        true
    }

    fn write_scene_boards(&mut self, scene: Id, boards: &[Id]) {
        let list = Value::List(boards.iter().map(|b| Value::Ref(*b)).collect());
        self.set(scene, f::BOARD_IDS, list);
    }

    pub fn create_unit(&mut self, label: &str, body: &str) -> Id {
        let tx = self.begin("Add camera");

        let id = self.create(Kind::Unit);
        self.set(id, f::LABEL, label);
        self.set(id, f::BODY, body);
        self.end(tx);
        id
    }

    /// A unit with its colour from birth — the identity a camera wears in
    /// every cell that names it.
    pub fn create_unit_coloured(&mut self, label: &str, body: &str, colour: &str) -> Id {
        let tx = self.begin("Add camera");
        let id = self.create(Kind::Unit);
        self.set(id, f::LABEL, label);
        self.set(id, f::BODY, body);
        if !colour.is_empty() {
            self.set(id, f::COLOUR, colour);
        }
        self.end(tx);
        id
    }

    /// Every shot that names this camera.
    pub fn shots_with_unit(&self, unit: Id) -> Vec<Id> {
        self.store
            .referring_to(&Kind::Shot, f::UNIT, unit)
            .iter()
            .map(|r| r.id)
            .collect()
    }

    /// Rename a camera.
    ///
    /// **Every shot naming it follows for free, and that is the whole point of
    /// a camera being a record.** A shot holds a *reference* to the unit, not a
    /// copy of its name, so the label is resolved when the cell is read. Fixing
    /// "Alexa 35" to "Alexa 35 — A cam" is one write here; renaming a *term*
    /// has to rewrite every shot that ever used it.
    ///
    /// An empty name is refused rather than obeyed. A camera with no name is a
    /// husk that shows as a blank row in every picker — `units_in_order` already
    /// skips them for exactly that reason, so allowing one here would make a
    /// camera vanish from the app while still sitting in the file.
    pub fn rename_unit(&mut self, unit: Id, label: &str) -> bool {
        let label = label.trim();
        if label.is_empty() {
            return false;
        }
        if self.get(unit).is_none() {
            return false;
        }
        let tx = self.begin("Rename camera");
        self.set(unit, f::LABEL, label);
        self.end(tx);
        true
    }

    /// **The sensor a camera reads** — his ruling, 2026-10-01: a sensor is
    /// typed in by him, a name and millimetres, and it lives on the film's
    /// camera (A-Cam = Alexa Mini LF Open Gate, 36.70 × 25.54), so every shot
    /// on A-Cam and every cone on a plan reads the same one. A width of 0
    /// clears it. One step of undo.
    pub fn set_unit_sensor(&mut self, unit: Id, name: &str, w: f64, h: f64) -> bool {
        if self.get(unit).map(|r| r.kind == Kind::Unit) != Some(true) {
            return false;
        }
        let tx = self.begin("Camera Sensor");
        if w > 0.0 && w.is_finite() {
            let name = name.trim();
            self.set(unit, f::SENSOR_NAME, if name.is_empty() { format!("{w:.2} mm") } else { name.to_string() });
            self.set(unit, f::SENSOR_W, Value::Float(w.min(100.0)));
            self.set(unit, f::SENSOR_H, Value::Float(if h.is_finite() { h.clamp(0.0, 100.0) } else { 0.0 }));
        } else {
            for k in [f::SENSOR_NAME, f::SENSOR_W, f::SENSOR_H] {
                self.set(unit, k, Value::Null);
            }
        }
        self.end(tx);
        true
    }

    /// A camera's sensor, if one has been set: name, width, height (mm).
    /// **The spec sheet's, when the card brings one that names this camera**
    /// (piece E, `crate::frames`); the one typed for it otherwise.
    pub fn unit_sensor(&self, unit: Id) -> Option<(String, f64, f64)> {
        if let Some(s) = self.sheet_sensor(unit) {
            return Some((s.name.clone(), s.w, s.h));
        }
        self.own_unit_sensor(unit)
    }

    /// The sensor typed for a camera in the film, whatever the sheet says.
    pub fn own_unit_sensor(&self, unit: Id) -> Option<(String, f64, f64)> {
        let r = self.get(unit)?;
        let w = r.get(f::SENSOR_W).and_then(|v| v.as_float())?;
        if w <= 0.0 {
            return None;
        }
        let h = r.get(f::SENSOR_H).and_then(|v| v.as_float()).unwrap_or(0.0);
        Some((r.text(f::SENSOR_NAME).unwrap_or("").to_string(), w, h))
    }

    /// Change the colour a camera wears.
    ///
    /// The colour is its identity in every cell that names it, so this is the
    /// other half of renaming: two cameras that look alike on a strip board are
    /// as bad as two called the same thing.
    pub fn recolour_unit(&mut self, unit: Id, colour: &str) -> bool {
        if self.get(unit).is_none() {
            return false;
        }
        let colour = colour.trim();
        let tx = self.begin("Recolour camera");
        if colour.is_empty() {
            self.set(unit, f::COLOUR, Value::Null);
        } else {
            self.set(unit, f::COLOUR, Value::text(colour));
        }
        self.end(tx);
        true
    }

    /// Take a camera away, and report what it cost.
    ///
    /// **Report, never destroy.** The unit is the only record deleted: every
    /// shot that named it keeps its scene, its letter, its frames, its lens and
    /// everything else, and simply stops naming a camera. That is the same
    /// bargain deleting a location strikes, and the same one deleting a shoot
    /// day strikes.
    ///
    /// The count comes back so the Mac can say the number *before* it asks —
    /// "3 shots name this camera. They keep everything of their own." — which
    /// is how deleting a column and deleting a location already ask.
    pub fn delete_unit(&mut self, unit: Id) -> usize {
        let shots = self.shots_with_unit(unit);
        let tx = self.begin("Remove camera");
        for shot in &shots {
            self.set(*shot, f::UNIT, Value::Null);
        }
        self.delete(unit);
        self.end(tx);
        shots.len()
    }

    pub fn create_day(&mut self) -> Id {
        let tx = self.begin("Add shoot day");

        let existing: Vec<f64> = self
            .days_in_order()
            .iter()
            .filter_map(|id| self.store.get(*id).and_then(|r| r.float(f::ORDER)))
            .collect();
        let id = self.create(Kind::ShootDay);
        self.set(id, f::ORDER, order::after_last(&existing));
        if let Some(shoot) = self.shoot_to_be_born_in() {
            self.born_in_shoot(id, &shoot);
        }
        self.end(tx);
        id
    }

    /// A day born already wearing its date — what clicking a calendar date does.
    ///
    /// Grouped, or the click is two undos: one for the day and one for when it
    /// is. Nobody means that by "undo". The date goes through `set_day_date`,
    /// so the letter-freeze it warns about applies here exactly as there.
    pub fn create_day_dated(&mut self, date: &str) -> Id {
        let tx = self.begin("Add shoot day");
        let id = self.create_day();
        self.set_day_date(id, date);
        self.end(tx);
        id
    }

    /// Put a shot in a scene. Assigns the lowest free letter for that scene and
    /// appends it to the scene's running order.
    ///
    /// Calling this a second time for the same shot in a different scene is how
    /// a shot appears in more than one place: one record, two placements, and a
    /// different letter in each.
    pub fn place(&mut self, shot: Id, scene: Id) -> Id {
        let tx = self.begin("Add shot");

        let used = self.used_letters(scene);
        let letter = self.letters.next_free(&used);
        let positions = self.placement_positions(scene);
        let id = self.create(Kind::Placement);
        self.set(id, f::SHOT, shot);
        self.set(id, f::SCENE, scene);
        self.set(id, f::LETTER, letter);
        self.set(id, f::ORDER_IN_SCENE, order::after_last(&positions));
        self.end(tx);
        id
    }

    /// Convenience: a new shot placed straight into a scene.
    pub fn add_shot_to_scene(&mut self, scene: Id) -> (Id, Id) {
        // Grouped, or this is two undos: one for the shot and one for putting it
        // somewhere. Nobody means that by "undo".
        let tx = self.begin("Add shot");
        let shot = self.create_shot();
        let placement = self.place(shot, scene);
        self.end(tx);
        (shot, placement)
    }

    /// A shot created *and seated* in one breath — control-return's gesture.
    ///
    /// One transaction, deliberately: created-then-moved as two history steps
    /// meant one keystroke took two undos to walk back, and nobody means that
    /// by "undo". `begin` refuses to nest, so the inner groupings of the
    /// pieces this calls fold into this one label.
    pub fn add_shot_to_scene_after(&mut self, scene: Id, after: Option<Id>) -> (Id, Id) {
        let tx = self.begin("Add shot");
        let shot = self.create_shot();
        let placement = self.place(shot, scene);
        if let Some(after) = after {
            let order = self.placements_in_scene(scene);
            if let Some(at) = order.iter().position(|id| *id == after) {
                self.move_in_scene_to(placement, at + 1);
            }
        }
        self.end(tx);
        (shot, placement)
    }

    /// Move a placement to a position in its scene's running order. Index is
    /// where it should end up once lifted out, which is what a drag reports.
    pub fn move_in_scene_to(&mut self, placement: Id, index: usize) {
        let scene = match self.get(placement).and_then(|r| r.ref_id(f::SCENE)) {
            Some(scene) => scene,
            None => return,
        };
        let position = self.position_for(
            self.placements_in_scene(scene),
            placement,
            index,
            f::ORDER_IN_SCENE,
        );
        let tx = self.begin("Move shot");
        self.set(placement, f::ORDER_IN_SCENE, position);
        // In prep, letters follow position. Once locked this does nothing.
        self.reflow_letters(scene);
        self.end(tx);
    }

    /// Move a placement to a position in its day's shooting order.
    pub fn move_in_day_to(&mut self, placement: Id, index: usize) {
        let day = match self.get(placement).and_then(|r| r.ref_id(f::DAY)) {
            Some(day) => day,
            None => return,
        };
        let position =
            self.position_for(self.placements_on_day(day), placement, index, f::ORDER_IN_DAY);
        self.set(placement, f::ORDER_IN_DAY, position);
    }

    /// Position that lands `moving` at `index` of `siblings`, once it has been
    /// lifted out of the list.
    fn position_for(&self, siblings: Vec<Id>, moving: Id, index: usize, field: &str) -> f64 {
        let others: Vec<Id> = siblings.into_iter().filter(|id| *id != moving).collect();
        // **An index past the end is the end** (Ref 1575). Read as it stood,
        // both neighbours were missing and the spot came out as the top.
        let index = index.min(others.len());
        let position_at = |slot: usize| -> Option<f64> {
            others
                .get(slot)
                .and_then(|id| self.get(*id))
                .and_then(|r| r.float(field))
        };
        let before = if index == 0 {
            None
        } else {
            position_at(index - 1)
        };
        order::between(before, position_at(index))
    }

    /// Lower-level move, when the neighbours are already known.
    pub fn move_in_scene(&mut self, placement: Id, before: Option<f64>, after: Option<f64>) {
        let position = order::between(before, after);
        self.set(placement, f::ORDER_IN_SCENE, position);
    }

    /// Schedule a placement on a day, appended to that day's running order.
    pub fn schedule(&mut self, placement: Id, day: Id) {
        let tx = self.begin("Schedule shot");

        let positions: Vec<f64> = self
            .placements_on_day(day)
            .iter()
            .filter_map(|id| self.store.get(*id).and_then(|r| r.float(f::ORDER_IN_DAY)))
            .collect();
        self.set(placement, f::DAY, day);
        self.set(placement, f::ORDER_IN_DAY, order::after_last(&positions));
        self.end(tx);
    }

    /// Drop a shot into a day at a position. Two changes — which day, and where
    /// in it — never one per shot in the lane, however long the day is.
    pub fn schedule_at(&mut self, placement: Id, day: Id, index: usize) {
        let tx = self.begin("Schedule shot");

        let position = self.position_for(
            self.placements_on_day(day),
            placement,
            index,
            f::ORDER_IN_DAY,
        );
        self.set(placement, f::DAY, day);
        self.set(placement, f::ORDER_IN_DAY, position);
        self.end(tx);
    }

    /// **A shot into the shooting order, just before another** — the shot
    /// list sorted by Shooting Order, where a drag means "shoot it here"
    /// (his ask, 2026-10-06). `before` is the shot it lands in front of on
    /// that day, or `None` for the day's end; `day` of `None` takes it off
    /// every day. Placing by neighbour rather than by count is what keeps a
    /// drop right when a filter hides some of the day's shots. Its scene,
    /// number and letter never change. One step.
    pub fn shoot_before(&mut self, placement: Id, day: Option<Id>, before: Option<Id>) {
        let Some(day) = day else {
            self.unschedule(placement);
            return;
        };
        let others: Vec<Id> = self.placements_on_day(day).into_iter().filter(|p| *p != placement).collect();
        let index = before.and_then(|b| others.iter().position(|p| *p == b)).unwrap_or(others.len());
        self.schedule_at(placement, day, index);
    }

    /// Move a day in the running order. One change: the label is derived from
    /// position, so nothing else has to be rewritten.
    pub fn move_day_to(&mut self, day: Id, index: usize) {
        let position = self.position_for(self.days_in_order(), day, index, f::ORDER);
        self.set(day, f::ORDER, position);
    }

    /// Put the dated days into date order, and say whether anything moved.
    ///
    /// Days are numbered in the order they were made — that is the deal struck
    /// when the calendar creates them by selection — so a schedule picked out
    /// of calendar order ends up with Day 1 later than Day 2. This is the one
    /// press that fixes it: dated days permute into date order **among the
    /// positions dated days already hold**, and an undated day keeps its exact
    /// place, because sorting what has no date would be inventing an answer.
    ///
    /// `YYYY-MM-DD` sorts as text exactly as it sorts as time, which is the
    /// reason that format is the contract.
    pub fn sort_days_by_date(&mut self) -> bool {
        let order = self.days_in_order();
        let date_of = |id: &Id| -> Option<String> {
            self.store
                .get(*id)
                .and_then(|r| r.text(f::DATE))
                .map(|s| s.to_string())
                .filter(|s| !s.is_empty())
        };
        let dated: Vec<Id> = order.iter().filter(|id| date_of(id).is_some()).copied().collect();
        let mut sorted = dated.clone();
        sorted.sort_by_key(|id| date_of(id).unwrap_or_default());
        if sorted == dated {
            return false;
        }
        let tx = self.begin("Put days in date order");
        let mut next = sorted.into_iter();
        for (i, slot) in order.iter().enumerate() {
            let day = if dated.contains(slot) {
                next.next().unwrap_or(*slot)
            } else {
                *slot
            };
            self.set(day, f::ORDER, (i + 1) as f64);
        }
        self.end(tx);
        true
    }

    /// Give a day a name — "Second unit", "Pickups" — or take it away again.
    ///
    /// The name sits *beside* `Day 3` rather than replacing it. The label is
    /// derived from position and always will be, because that is the thing
    /// everyone on a crew counts by; a name is what this particular day is
    /// **for**, and a day can want both.
    pub fn rename_day(&mut self, day: Id, name: &str) {
        let tx = self.begin("Name day");
        let name = name.trim();
        if name.is_empty() {
            self.set(day, f::TITLE, Value::Null);
        } else {
            self.set(day, f::TITLE, Value::text(name));
        }
        self.end(tx);
    }

    /// Put a date on a day, as `YYYY-MM-DD`, or clear it.
    ///
    /// **This is the switch that freezes the letters** — `first_shoot_date` in
    /// `lettering.rs` reads exactly this field, and the earliest one in the
    /// film is the morning prep ends. So dating a day is not decoration, and
    /// clearing every date puts the film back into prep.
    pub fn set_day_date(&mut self, day: Id, date: &str) {
        let tx = self.begin("Set day date");
        let date = date.trim();
        if date.is_empty() {
            self.set(day, f::DATE, Value::Null);
        } else {
            self.set(day, f::DATE, Value::text(date));
        }
        // A day that follows its shoot keeps following it from the new date.
        self.refollow_day(day);
        self.end(tx);
    }

    /// Take a shoot day away, and report what it cost.
    ///
    /// **Report, never destroy.** The day is the only thing deleted: every shot
    /// that was on it keeps its scene, its letter, its frames and everything
    /// else, and simply goes back to waiting — the same bargain deleting a
    /// location strikes. The count is returned so the Mac can say the number
    /// before it asks, the way deleting a column does.
    ///
    /// The days after it slide up a number, because `day_label` has always been
    /// derived from position. Remove Day 2 of four and the film has three days.
    pub fn delete_day(&mut self, day: Id) -> usize {
        let placements = self.placements_on_day(day);
        let tx = self.begin("Remove day");
        for placement in &placements {
            self.set(*placement, f::DAY, Value::Null);
            self.set(*placement, f::ORDER_IN_DAY, Value::Null);
        }
        self.delete(day);
        self.end(tx);
        placements.len()
    }

    pub fn unschedule(&mut self, placement: Id) {
        let tx = self.begin("Unschedule shot");

        self.set(placement, f::DAY, Value::Null);
        self.set(placement, f::ORDER_IN_DAY, Value::Null);
        self.end(tx);
    }

    /// Put a whole scene on a day — the usual gesture, and what dragging a scene
    /// onto a day in the schedule does.
    ///
    /// The day is stored per shot rather than on the scene, so this is a
    /// shorthand rather than a different kind of fact. That is what lets a scene
    /// be split across two days, which the prototype could not express.
    pub fn schedule_scene(&mut self, scene: Id, day: Id) {
        let tx = self.begin("Schedule scene");

        for placement in self.placements_in_scene(scene) {
            self.schedule(placement, day);
        }
        self.end(tx);
    }

    pub fn unschedule_scene(&mut self, scene: Id) {
        let tx = self.begin("Unschedule scene");

        for placement in self.placements_in_scene(scene) {
            self.unschedule(placement);
        }
        self.end(tx);
    }

    /// Days this scene touches, in day order. More than one means it is split.
    pub fn days_of_scene(&self, scene: Id) -> Vec<Id> {
        let touched: Vec<Id> = self
            .placements_in_scene(scene)
            .iter()
            .filter_map(|p| self.get(*p).and_then(|r| r.ref_id(f::DAY)))
            .collect();
        self.days_in_order()
            .into_iter()
            .filter(|day| touched.contains(day))
            .collect()
    }

    /// The other days this scene touches, in day order — what a band on Day 1
    /// means when it says "also Day 2".
    pub fn other_days_of_scene(&self, scene: Id, besides: Id) -> Vec<Id> {
        self.days_of_scene(scene)
            .into_iter()
            .filter(|day| *day != besides)
            .collect()
    }

    /// True when a scene is being shot across more than one day, or is only
    /// partly scheduled. Worth showing plainly rather than letting it surprise
    /// someone on the day.
    pub fn scene_is_split(&self, scene: Id) -> bool {
        let placements = self.placements_in_scene(scene);
        if placements.is_empty() {
            return false;
        }
        let days: Vec<Option<Id>> = placements
            .iter()
            .map(|p| self.get(*p).and_then(|r| r.ref_id(f::DAY)))
            .collect();
        let first = days[0];
        days.iter().any(|d| *d != first)
    }

    /// Copy a shot, placed straight after the one it came from.
    ///
    /// The copy carries everything the original holds, including its frames —
    /// which cost nothing extra, since media is stored by its contents. It does
    /// not inherit the strike, because a copy is work still to do, and it does
    /// not join the original's camera setup, because that would quietly turn two
    /// cameras into three.
    ///
    /// The title is copied as-is. Marking it as a copy is wording, and wording
    /// belongs to the app rather than to the engine.
    pub fn duplicate_shot(&mut self, placement: Id) -> Option<(Id, Id)> {
        let scene = self.get(placement)?.ref_id(f::SCENE)?;
        let original = self.get(placement)?.ref_id(f::SHOT)?;

        // **The key frame is not carried.**
        //
        // `KEY_MEDIA` names a *media ref* — one shot's own use of a file — and
        // copying the field verbatim pointed the copy at the **original's** use
        // of it. Everything downstream then behaved as though the two shots
        // shared one picture: the table and the storyboard drew the copy from
        // the original's frame, and taking that frame off either shot took it
        // off both, then left the copy pointing at a record that no longer
        // existed. His report, Ref 489: *"when I duplicate a shot, it's its own
        // individual entity that is not linked to anything."* The copy's own key
        // is set below, from the copy's own new frame.
        let carried: Vec<(String, Value)> = {
            let record = self.get(original)?;
            record
                .field_names()
                .into_iter()
                .filter(|name| {
                    *name != F_DELETED
                        && *name != f::STRUCK
                        && *name != f::SETUP
                        && *name != f::KEY_MEDIA
                })
                .filter_map(|name| record.get(name).map(|value| (name.to_string(), value.clone())))
                .collect()
        };
        let key_frame = self.get(original).and_then(|r| r.ref_id(f::KEY_MEDIA));
        let frames: Vec<(Id, Id, String)> = self
            .media_refs(original)
            .into_iter()
            .filter_map(|media_ref| {
                let record = self.get(media_ref)?;
                Some((
                    media_ref,
                    record.ref_id(f::MEDIA)?,
                    record.text(f::CAPTION).unwrap_or_default().to_string(),
                ))
            })
            .collect();

        let tx = self.begin("Copy shot");
        let (copy, new_placement) = self.add_shot_to_scene(scene);
        for (field, value) in carried {
            self.set(copy, &field, value);
        }
        // The Print Frame names this shot's own uses, like the key frame does;
        // it is pointed at the copy's uses below, as each one arrives.
        let mut print_frame = self.print_frame(copy);
        let baked = self.print_frame_baked(copy);
        let was_current = self.print_frame_is_current(original);
        for (was, media, caption) in frames {
            let now = self.attach_media(copy, media, &caption);
            if let Some(spec) = print_frame.as_mut() {
                for m in spec.frames.iter_mut().filter(|m| m.media_ref == was) {
                    m.media_ref = now;
                }
            }
            // **And the frame arrives framed the way it was framed.**
            //
            // A crop, a trim and any storyboard arrows live on the ref — *this
            // use* of the file, never the file — so a copy that carried only the
            // file lost all three, and drew the middle of an untrimmed clip with
            // no marks on it. Everything except where it sits and who owns it
            // comes across, so a field added to a ref later is carried without
            // anybody having to remember this place.
            let framing: Vec<(String, Value)> = match self.get(was) {
                Some(record) => record
                    .field_names()
                    .into_iter()
                    .filter(|name| {
                        *name != F_DELETED
                            && *name != f::OWNER
                            && *name != f::ORDER
                            && *name != f::MEDIA
                            && *name != f::CAPTION
                    })
                    .filter_map(|name| record.get(name).map(|value| (name.to_string(), value.clone())))
                    .collect(),
                None => Vec::new(),
            };
            for (field, value) in framing {
                self.set(now, &field, value);
            }
            // The copy's lead frame is its own copy of whichever frame led the
            // original — not a fallback, and not the original's record.
            if key_frame == Some(was) {
                self.set(copy, f::KEY_MEDIA, now);
            }
        }
        if let Some(spec) = print_frame {
            self.set(copy, f::PRINT_FRAME, Value::text(spec.encode()));
            // The same pictures on the same board: the bake still stands.
            if let (true, Some(mut baked)) = (was_current, baked) {
                baked.digest = spec.digest();
                self.set(copy, f::PRINT_FRAME_BAKED, Value::text(baked.encode()));
            }
        }
        // Sit it directly after the original rather than at the end of the scene.
        let after = self
            .placements_in_scene(scene)
            .iter()
            .position(|id| *id == placement)
            .map(|index| index + 1)
            .unwrap_or(0);
        self.move_in_scene_to(new_placement, after);
        self.end(tx);

        Some((copy, new_placement))
    }

    /// **Copies of several shots, landed in one scene, as one thing to undo.**
    ///
    /// This is what "copy these shots and paste them over there" means, and it
    /// is not a paste of *cells*: a shot carries its frames, its notes, its
    /// gear and its tags, and smearing its columns across the table as text
    /// loses all of that and lands them in whatever column the cursor happened
    /// to be in. Nathaniel's screenshot of that going wrong is why this exists.
    ///
    /// One transaction around the lot — `begin` nests, so every `duplicate_shot`
    /// inside joins this step rather than opening its own. Four shots copied is
    /// one ⌘Z, which is what a person means by "undo that".
    ///
    /// `after` places the run directly below a shot already in the scene; with
    /// `None` they land at the foot. Order is kept, so a run pasted reads the
    /// way it read where it was copied from.
    pub fn duplicate_shots_into(
        &mut self,
        placements: &[Id],
        scene: Id,
        after: Option<Id>,
    ) -> Vec<Id> {
        if placements.is_empty() {
            return Vec::new();
        }
        let label = if placements.len() == 1 {
            "Copy shot".to_string()
        } else {
            format!("Copy {} shots", placements.len())
        };
        let tx = self.begin(&label);
        let mut landed = Vec::new();
        let mut at = after
            .and_then(|id| {
                self.placements_in_scene(scene)
                    .iter()
                    .position(|p| *p == id)
                    .map(|index| index + 1)
            })
            .unwrap_or_else(|| self.placements_in_scene(scene).len());
        for placement in placements {
            let Some((_, copy)) = self.duplicate_shot(*placement) else {
                continue;
            };
            // The copy is born in its *original's* scene. Carry it over only
            // when that is somewhere else — `move_placement_to_scene` returns
            // early when it is already home, and would otherwise spend a letter.
            if self.get(copy).and_then(|r| r.ref_id(f::SCENE)) != Some(scene) {
                self.move_placement_to_scene(copy, scene);
            }
            self.move_in_scene_to(copy, at.min(self.placements_in_scene(scene).len()));
            at += 1;
            landed.push(copy);
        }
        self.end(tx);
        landed
    }

    /// Move a shot to another scene.
    ///
    /// The shot record is untouched — only where it sits changes. It takes the
    /// next free letter in its new scene and gives up the one it held, so `34C`
    /// becomes `40D` and `C` is available again in 34.
    ///
    /// This *moves* the shot. To have it appear in both, place it in the second
    /// scene and leave the first alone.
    pub fn move_placement_to_scene(&mut self, placement: Id, scene: Id) -> Option<String> {
        let current = self.get(placement)?.ref_id(f::SCENE)?;
        if current == scene {
            return self.display_number(placement);
        }

        let used = self.used_letters(scene);
        let letter = self.letters().next_free(&used);
        let positions = self.placement_positions(scene);

        let tx = self.begin("Move shot");
        self.set(placement, f::SCENE, scene);
        self.set(placement, f::LETTER, letter);
        self.set(placement, f::ORDER_IN_SCENE, order::after_last(&positions));
        // **And the scene it left closes up behind it.**
        //
        // `delete_placement` has always done this and says why: while nobody
        // has the list on paper, letters follow position, so taking 34B out
        // makes what was 34C into 34B. A shot *moved* out leaves exactly the
        // same hole and had been leaving it open — drag 34A into another scene
        // and 34B, 34C, 34D stayed as they were, with no 34A in the film.
        //
        // Nathaniel's call, asked directly: "no gap — it should close up yes."
        //
        // `reflow_letters` is a no-op once letters are locked, so the rule in
        // `lettering.rs` — letters freeze on the morning of the first shoot
        // day, because by then people are reading them off a printed callsheet
        // — is respected without anything extra here.
        self.reflow_letters(current);
        self.end(tx);

        self.display_number(placement)
    }

    /// Scratch a shot off on the day. Means "we got this" and nothing else —
    /// the shot keeps its number, its place, and everything about it.
    pub fn strike(&mut self, shot: Id, struck: bool) {
        self.set(shot, f::STRUCK, struck);
    }

    /// Sets a scene aside, or brings it back. Report-never-destroy: an
    /// archived scene keeps everything and stays listed (greyed, at the
    /// foot), because a thing that can be hidden beyond reach has been
    /// destroyed in everything but name.
    pub fn archive_scene(&mut self, scene: Id, on: bool) {
        let tx = self.begin(if on { "Archive scene" } else { "Restore scene" });
        self.set(scene, f::ARCHIVED, Value::Bool(on));
        self.end(tx);
    }

    /// **Throw an archived scene away for good.** His ask, 2026-08-22: *"I
    /// should be able to delete scenes after they are archived."*
    ///
    /// Two rules keep this on the right side of *report, never destroy*:
    ///
    /// - **Only an archived scene.** Archiving is the reversible step and it
    ///   has to be taken first, deliberately, so nothing goes in one click
    ///   from a working list. A scene that is not archived is refused.
    /// - **Its shots go with it**, because a shot's place in a film is a
    ///   placement in a scene and there is nowhere for one to stand once the
    ///   scene is gone. How many is returned so the Mac can say the number
    ///   before it asks — the same shape as deleting a column.
    ///
    /// **The deleting itself already existed** — `delete_scene` in
    /// `lettering.rs`, which also reletters what is left. I nearly wrote a
    /// second one before finding it. This adds the guard and nothing else.
    pub fn delete_archived_scene(&mut self, scene: Id) -> Option<usize> {
        if !self.is_archived(scene) {
            return None;
        }
        Some(self.delete_scene(scene))
    }

    pub fn is_archived(&self, scene: Id) -> bool {
        self.get(scene).map(|r| r.bool(f::ARCHIVED)).unwrap_or(false)
    }

    /// **Put the scenes back in the order their numbers say.**
    ///
    /// A new scene lands in its place now, but a project that took a draft in
    /// before that was true is already out of order and nothing moves it — his
    /// report, 2026-08-22, of a film reading 33, 34, 35, 54, 1, 2, 3.
    ///
    /// **Asked for, never automatic.** The order of a film is a thing a person
    /// can arrange, and rearranging it behind them would be worse than the mess
    /// it tidies. One transaction, so it is one ⌘Z.
    ///
    /// A scene with no number at all sorts to the end, because there is nothing
    /// to sort it by and leaving it where it was would put it in the middle of
    /// a run it has no claim on.
    /// Settle every scene's time of day against the list the app offers, in
    /// order, so CONTINUOUS and LATER become the time they were pointing at.
    ///
    /// **For a film already imported** — Ref 257 fixes the reading, but that
    /// only helps the next draft to arrive, and his projects already carry
    /// CONTINUED in the column. Returns how many scenes changed, so the Mac
    /// can say what it did rather than appearing to do nothing.
    ///
    /// The scene's *heading* is untouched: the slugline is the script's.
    pub fn settle_scene_times(&mut self) -> usize {
        let scenes = self.scenes_in_order();
        let mut carried = String::new();
        let mut settled: Vec<(Id, String)> = Vec::new();
        for scene in scenes {
            let written = self
                .get(scene)
                .and_then(|r| r.text(f::TIME_OF_DAY).map(str::to_string))
                .unwrap_or_default();
            let written = written.trim().to_string();
            // A scene with nothing written takes the last real one — his
            // ruling, same as on import.
            if written.is_empty() {
                if !carried.is_empty() {
                    settled.push((scene, carried.clone()));
                }
                continue;
            }
            let wanted = if let Some(meaning) = crate::script::time_of_day_meaning(&written) {
                carried = meaning.to_string();
                meaning.to_string()
            } else if crate::script::carries_the_last_time_forward(&written) {
                carried.clone()
            } else {
                // **Left alone, not emptied.** On import an unreadable word is
                // dropped because the heading still holds it; here it may be
                // something he typed himself, and clearing that would be
                // destroying his writing to tidy a column.
                continue;
            };
            if wanted != written {
                settled.push((scene, wanted));
            }
        }
        if settled.is_empty() {
            return 0;
        }
        let tx = self.begin("Settle times of day");
        let changed = settled.len();
        for (scene, wanted) in settled {
            self.set(scene, f::TIME_OF_DAY, wanted.as_str());
        }
        self.end(tx);
        changed
    }

    pub fn sort_scenes_by_number(&mut self) {
        let tx = self.begin("Sort scenes by number");
        let mut scenes: Vec<(String, Id)> = self
            .store
            .of_kind(&Kind::Scene)
            .iter()
            .map(|r| {
                (
                    r.text(f::NUMBER).unwrap_or_default().to_string(),
                    r.id,
                )
            })
            .collect();
        scenes.sort_by(|a, b| match (a.0.is_empty(), b.0.is_empty()) {
            (true, true) => std::cmp::Ordering::Equal,
            (true, false) => std::cmp::Ordering::Greater,
            (false, true) => std::cmp::Ordering::Less,
            _ => crate::natural::compare(&a.0, &b.0),
        });
        for (at, (_, id)) in scenes.iter().enumerate() {
            self.set(*id, f::ORDER, Value::Float(at as f64 * order::STEP));
        }
        self.end(tx);
    }

    // ---- masters, and the shots that stand in for them ------------------

    /// Whether this shot is one others may point at.
    pub fn is_master(&self, shot: Id) -> bool {
        self.get(shot).map(|r| r.bool(f::IS_MASTER)).unwrap_or(false)
    }

    /// The master this shot stands in for, if any.
    ///
    /// **Never more than one hop.** A master may not itself be linked — see
    /// `link_shot` — so following the pointer once is following it all the way,
    /// and a file that somehow said otherwise cannot send a reader in circles.
    pub fn master_of(&self, shot: Id) -> Option<Id> {
        let target = self.get(shot)?.ref_id(f::MASTER)?;
        if target == shot {
            return None;
        }
        self.get(target).map(|_| target)
    }

    /// Where a shot's *description* actually comes from: its master when it has
    /// one, itself otherwise. Identity — its number, its scene, whether it is
    /// cut — is always its own.
    pub fn described_by(&self, shot: Id) -> Id {
        self.master_of(shot).unwrap_or(shot)
    }

    /// Make a shot a master, or stop it being one.
    ///
    /// **Stopping cuts the shots that pointed at it loose** rather than leaving
    /// them pointing at something that is no longer a master. They keep what
    /// they were showing: the values are copied onto them first, so unlinking
    /// is never a loss. Report, never destroy.
    pub fn set_master(&mut self, shot: Id, on: bool) {
        let tx = self.begin(if on { "Make master" } else { "Remove master" });
        if on {
            // A master cannot itself stand in for another one.
            self.set(shot, f::MASTER, Value::Null);
            self.set(shot, f::IS_MASTER, Value::Bool(true));
        } else {
            let followers: Vec<Id> = self
                .store
                .of_kind(&Kind::Shot)
                .iter()
                .map(|r| r.id)
                .filter(|id| self.master_of(*id) == Some(shot))
                .collect();
            for follower in followers {
                self.unlink_shot(follower);
            }
            self.set(shot, f::IS_MASTER, Value::Bool(false));
        }
        self.end(tx);
    }

    /// Point a shot at a master. Passing `None` cuts it loose.
    ///
    /// The target is made a master by the act of being linked to, because a
    /// person choosing one has already said what they mean, and a link to a
    /// shot that is not a master would be a link nothing could find again.
    pub fn link_shot(&mut self, shot: Id, master: Option<Id>) {
        let Some(master) = master else {
            let tx = self.begin("Unlink shot");
            self.unlink_shot(shot);
            self.end(tx);
            return;
        };
        if master == shot {
            return;
        }
        // Linking to something that is itself linked means linking to what it
        // stands in for — so a chain can never form.
        let master = self.described_by(master);
        if master == shot {
            return;
        }
        let tx = self.begin("Link shot");
        self.set(master, f::IS_MASTER, Value::Bool(true));
        self.set(shot, f::MASTER, master);
        // A shot that stands in for another is not a master itself.
        self.set(shot, f::IS_MASTER, Value::Bool(false));
        self.end(tx);
    }

    /// Cut one shot loose, keeping on it what it was showing.
    fn unlink_shot(&mut self, shot: Id) {
        let Some(master) = self.master_of(shot) else {
            self.set(shot, f::MASTER, Value::Null);
            return;
        };
        for field in Self::DESCRIBING {
            let held = self.get(master).and_then(|r| r.get(field)).cloned();
            match held {
                Some(value) => self.set(shot, field, value),
                None => self.set(shot, field, Value::Null),
            }
        }
        self.set(shot, f::MASTER, Value::Null);
    }

    /// **What a master lends to the shots that stand in for it.** Everything
    /// that describes the shot; nothing that says where this one sits. Its
    /// number, its scene, whether it is cut and what colour it wears are facts
    /// about this instance and stay its own.
    pub const DESCRIBING: [&'static str; 14] = [
        f::TITLE,
        f::DESCRIPTION,
        "description_rich",
        f::SIZE,
        f::ANGLE,
        f::MOVEMENT,
        f::LENS,
        f::FOCAL,
        f::MODIFIERS,
        f::LENS_FILTERS,
        f::SUPPORT,
        f::NOTES,
        f::TAGS,
        f::KEY_MEDIA,
    ];

    /// Several placements gone in one breath — one transaction, so deleting
    /// a selection is one thing to take back, not one per row.
    pub fn delete_placements(&mut self, placements: &[Id]) {
        let label = if placements.len() == 1 {
            "Delete shot".to_string()
        } else {
            format!("Delete {} shots", placements.len())
        };
        let tx = self.begin(&label);
        for placement in placements {
            self.delete_placement(*placement);
        }
        self.end(tx);
    }

    /// Several shots struck or restored together, one transaction.
    pub fn strike_many(&mut self, shots: &[Id], on: bool) {
        let label = if on { "Strike shots" } else { "Restore shots" };
        let tx = self.begin(label);
        for shot in shots {
            self.strike(*shot, on);
        }
        self.end(tx);
    }

    // ---- reading -------------------------------------------------------

    pub fn get(&self, id: Id) -> Option<&Record> {
        self.store.get(id)
    }

    fn placement_positions(&self, scene: Id) -> Vec<f64> {
        self.store
            .referring_to(&Kind::Placement, f::SCENE, scene)
            .iter()
            .filter_map(|r| r.float(f::ORDER_IN_SCENE))
            .collect()
    }

    pub fn scenes_in_order(&self) -> Vec<Id> {
        let mut scenes = self.store.of_kind(&Kind::Scene);
        scenes.sort_by(|a, b| {
            order::compare(
                a.float(f::ORDER).unwrap_or(0.0),
                b.float(f::ORDER).unwrap_or(0.0),
            )
        });
        scenes.iter().map(|r| r.id).collect()
    }

    pub fn days_in_order(&self) -> Vec<Id> {
        let mut days = self.store.of_kind(&Kind::ShootDay);
        days.sort_by(|a, b| {
            order::compare(
                a.float(f::ORDER).unwrap_or(0.0),
                b.float(f::ORDER).unwrap_or(0.0),
            )
        });
        days.iter().map(|r| r.id).collect()
    }

    /// Placements in a scene, in story order.
    pub fn placements_in_scene(&self, scene: Id) -> Vec<Id> {
        let mut placements = self.store.referring_to(&Kind::Placement, f::SCENE, scene);
        placements.sort_by(|a, b| {
            order::compare(
                a.float(f::ORDER_IN_SCENE).unwrap_or(0.0),
                b.float(f::ORDER_IN_SCENE).unwrap_or(0.0),
            )
        });
        placements.iter().map(|r| r.id).collect()
    }

    /// Placements on a day, in shooting order. Independent of story order.
    pub fn placements_on_day(&self, day: Id) -> Vec<Id> {
        let mut placements = self.store.referring_to(&Kind::Placement, f::DAY, day);
        placements.sort_by(|a, b| {
            order::compare(
                a.float(f::ORDER_IN_DAY).unwrap_or(0.0),
                b.float(f::ORDER_IN_DAY).unwrap_or(0.0),
            )
        });
        placements.iter().map(|r| r.id).collect()
    }

    /// Every scene a shot appears in, via its placements.
    pub fn placements_of_shot(&self, shot: Id) -> Vec<Id> {
        self.store
            .referring_to(&Kind::Placement, f::SHOT, shot)
            .iter()
            .map(|r| r.id)
            .collect()
    }

    /// Say that two shots roll at the same moment on different cameras.
    ///
    /// The setup is a record of its own rather than one of the shots standing in
    /// for it. A shot being its own setup's key works — nothing ever asks what
    /// kind the key is — but it makes a shot mean two things at once, and the
    /// first thing that reads the store expecting otherwise would be right to be
    /// confused. Older projects that used a shot's id still merge and still show
    /// their siblings, because membership is only ever "we point at the same
    /// thing".
    ///
    /// Tying a third camera to a pair **joins the pair** rather than starting a
    /// second setup, which is the rule that makes tying order not matter.
    pub fn tie_setup(&mut self, a: Id, b: Id) -> Option<Id> {
        if a == b || self.get(a).is_none() || self.get(b).is_none() {
            return None;
        }
        let existing = self
            .get(a)
            .and_then(|r| r.ref_id(f::SETUP))
            .or_else(|| self.get(b).and_then(|r| r.ref_id(f::SETUP)));

        let setup = self.transact("Tie cameras", |doc| {
            let setup = existing.unwrap_or_else(|| doc.create_record(Kind::Setup));
            doc.set(a, f::SETUP, Value::Ref(setup));
            doc.set(b, f::SETUP, Value::Ref(setup));
            setup
        });
        Some(setup)
    }

    /// Take one camera back out. A setup of one is not a setup, so the last shot
    /// left behind is released too rather than sitting in a group of itself.
    pub fn untie_setup(&mut self, shot: Id) {
        let Some(setup) = self.get(shot).and_then(|r| r.ref_id(f::SETUP)) else {
            return;
        };
        let others = self.setup_siblings(shot);
        self.transact("Untie cameras", |doc| {
            doc.set(shot, f::SETUP, Value::Null);
            if others.len() == 1 {
                doc.set(others[0], f::SETUP, Value::Null);
            }
        });
        // Nothing points at it any more, so it should not linger in the store.
        if others.len() <= 1 && self.store.get(setup).map(|r| r.kind == Kind::Setup) == Some(true) {
            self.delete(setup);
        }
    }

    /// Shots that roll at the same moment on different cameras.
    pub fn setup_siblings(&self, shot: Id) -> Vec<Id> {
        let setup = match self.store.get(shot).and_then(|r| r.ref_id(f::SETUP)) {
            Some(s) => s,
            None => return Vec::new(),
        };
        self.store
            .referring_to(&Kind::Shot, f::SETUP, setup)
            .iter()
            .map(|r| r.id)
            .filter(|id| *id != shot)
            .collect()
    }

    pub fn used_letters(&self, scene: Id) -> HashSet<String> {
        self.store
            .referring_to(&Kind::Placement, f::SCENE, scene)
            .iter()
            .filter_map(|r| r.text(f::LETTER).map(|s| s.to_string()))
            .collect()
    }

    // ---- derived -------------------------------------------------------

    /// `34A` — the placement's scene number plus the placement's letter.
    /// Never stored, so renaming a scene renumbers everything in it at once.
    pub fn display_number(&self, placement: Id) -> Option<String> {
        let record = self.store.get(placement)?;
        let scene = self.store.get(record.ref_id(f::SCENE)?)?;
        let number = scene.text(f::NUMBER).unwrap_or_default();
        let letter = record.text(f::LETTER).unwrap_or_default();
        Some(format!("{number}{letter}"))
    }

    /// `INT. BEDROOM - NIGHT`
    /// **A person typing into a scene's settings**, as against a draft being
    /// conformed.
    ///
    /// The difference matters for exactly one reason: the three fields a slug
    /// line is made of. When *he* changes where a scene happens, the heading
    /// should follow — a scene he has moved to the garage that still reads
    /// KITCHEN is wrong. When an *import* conforms a time of day, the heading
    /// must not move: the slug is the script's and he said so plainly on
    /// 2026-08-22 after `EXT. POOL - LATER` came back as `EXT. POOL - EVENING`.
    ///
    /// Both used to go through `set`, so there was no way to tell them apart
    /// and the second was rewriting his script's own words. Conforming still
    /// calls `set`; a person's edit calls this.
    ///
    /// **A scene with no printed slug is left alone** — it has none to keep,
    /// and `scene_heading` builds one from the parts every time it is asked.
    pub fn set_scene_field(&mut self, scene: Id, field: &str, value: impl Into<Value>) {
        let tx = self.begin("Edit scene");
        self.set(scene, field, value);
        if field == f::INT_EXT {
            // **One spelling for each answer**, however it was typed or
            // picked: `I/E` and `INT./EXT.` are the same scene.
            let held = self.get(scene).and_then(|r| r.text(f::INT_EXT)).unwrap_or_default();
            let canonical = crate::insideout::canonical(held.trim());
            if canonical != held {
                self.set(scene, f::INT_EXT, Value::text(&canonical));
            }
        }
        if [f::INT_EXT, f::LOCATION, f::TIME_OF_DAY].contains(&field) {
            let printed = self
                .get(scene)
                .and_then(|r| r.text(f::HEADING))
                .unwrap_or_default()
                .to_string();
            if !printed.is_empty() {
                let record = self.get(scene);
                let int_ext = crate::insideout::printed(
                    record
                        .and_then(|r| r.text(f::INT_EXT))
                        .filter(|t| !t.is_empty())
                        .unwrap_or("INT"),
                );
                let location = record
                    .and_then(|r| r.text(f::LOCATION))
                    .unwrap_or("LOCATION")
                    .to_uppercase();
                let tod = record
                    .and_then(|r| r.text(f::TIME_OF_DAY))
                    .filter(|t| !t.is_empty())
                    .unwrap_or_default()
                    .to_uppercase();
                let rebuilt = if tod.is_empty() {
                    format!("{int_ext} {location}")
                } else {
                    format!("{int_ext} {location} - {tod}")
                };
                self.set(scene, f::HEADING, Value::text(&rebuilt));
            }
        }
        self.end(tx);
    }

    /// A scene's slug, as it should be read.
    ///
    /// **What the script printed always wins.** His ruling, 2026-08-22: *"I
    /// want the written scene headers unchanged from the script but the
    /// underlying data point in the scene settings to be conformed."*
    ///
    /// This used to rebuild the slug out of its parts whenever it had all of
    /// them, and keep the written one only where rebuilding would have to
    /// guess. That looked harmless for as long as the parts happened to spell
    /// the same thing — and stopped being harmless the moment Ref 257 started
    /// conforming times of day, because `EXT. POOL - LATER` came back as
    /// `EXT. POOL - EVENING` and his script's own words were gone from the
    /// screen. Nothing was lost; the heading was on the record the whole time
    /// and simply was not being read.
    ///
    /// Rebuilding is still right for a scene **somebody made in the app**,
    /// which has no printed slug of its own. That is the only case left.
    ///
    /// The consequence, deliberately accepted: editing the location or the
    /// time of day of a scene that came from a script does not rewrite its
    /// slug line. The slug belongs to the script, and the settings beside it
    /// are where the crew's own answer lives.
    pub fn scene_heading(&self, scene: Id) -> Option<String> {
        let record = self.store.get(scene)?;
        // **A commercial scene is a title, not a slug.** Everything below is
        // the film rule; `crate::kind` owns the other one.
        if self.kind() == crate::kind::Kind::Commercial {
            return Some(self.commercial_heading(scene));
        }
        if let Some(written) = record.text(f::HEADING).filter(|text| !text.is_empty()) {
            return Some(written.to_string());
        }
        let int_ext = record.text(f::INT_EXT).filter(|text| !text.is_empty());
        let tod = record.text(f::TIME_OF_DAY).filter(|text| !text.is_empty());
        let int_ext = crate::insideout::printed(int_ext.unwrap_or("INT"));
        let location = record.text(f::LOCATION).unwrap_or("LOCATION").to_uppercase();
        let tod = tod.unwrap_or("DAY").to_uppercase();
        Some(format!("{int_ext} {location} - {tod}"))
    }

    /// The heading as a screen draws it: a scene that is both opens `I/E.`
    /// (see `insideout::shown_heading`). The stored heading, the print and the
    /// export keep what the script wrote.
    pub fn scene_heading_shown(&self, scene: Id) -> Option<String> {
        self.scene_heading(scene).map(|h| crate::insideout::shown_heading(&h))
    }

    /// `Day 3` — position in the manual day order, never stored. A date can be
    /// attached to a day but does not reorder anything.
    pub fn day_label(&self, day: Id) -> Option<String> {
        // **With two or more shoots, days count within their shoot** (piece
        // D, the approved design): Shoot 2's first day is its Day 1.
        if self.many_shoots() {
            if let Some(shoot) = self.day_shoot(day) {
                let index = self.days_of_shoot(&shoot).iter().position(|id| *id == day)?;
                return Some(format!("Day {}", index + 1));
            }
        }
        let index = self.days_in_order().iter().position(|id| *id == day)?;
        Some(format!("Day {}", index + 1))
    }

    pub fn shot_count_in_scene(&self, scene: Id) -> usize {
        self.placements_in_scene(scene).len()
    }

    pub fn shot_count_on_day(&self, day: Id) -> usize {
        self.placements_on_day(day).len()
    }

    /// **A wrapped day**: it has shots and every one is in an archived scene
    /// (shot out and put away). A day with nothing on it is not wrapped, it is
    /// new. The screens leave a wrapped day out of the lists a day is picked
    /// from and fold it on the Schedule.
    pub fn day_wrapped(&self, day: Id) -> bool {
        let on = self.placements_on_day(day);
        !on.is_empty()
            && on.iter().all(|at| {
                self.get(*at)
                    .and_then(|r| r.ref_id(f::SCENE))
                    .map(|scene| self.is_archived(scene))
                    .unwrap_or(false)
            })
    }
}
