//! The MCP, in a worker.
//!
//! His ask, 2026-09-01: the MCP should run somewhere any AI can reach it,
//! rather than only on the Mac he happens to be sitting at.
//!
//! **Nothing about the tools is here.** All of them are
//! `shotlister_mcp`, the same code the Mac runs, compiled without its `disk`
//! feature. This crate is only the other end of `mcp::films::Films`: where a
//! Mac has a folder, a worker has change logs handed to it out of the relay's
//! bucket, and where a Mac appends to a file, a worker hands back a new log for
//! the caller to put in the bucket.
//!
//! **A worker is another device, exactly as a browser is.** It replays every
//! log before it answers anything, so its clock has heard every write that came
//! before — which is what makes a change it writes sort after them rather than
//! being dropped as stale (`engine::stamp`, and Ref 339 for the shape of the
//! bug when a device *has not* heard).
//!
//! ## The order the host must call things in
//!
//! ```text
//! set_now(Date.now())        // a worker has no clock the engine can reach
//! set_seed(random)           // nor any randomness
//! start(film, title, read_only, device)
//! add_log(text) …            // every log in the bucket, in name order
//! settle()
//! handle(one JSON-RPC message) -> the reply
//! pending_log()              // "" unless the tool changed something
//! ```
//!
//! Every request starts again. That is not a shortcut — it is the only honest
//! thing a stateless worker can do, and it costs a few milliseconds: his
//! largest film is 6,497 changes across 118 logs.
//!
//! **Or, since 2026-09-16, it starts from where the last request left off.**
//! `snapshot()` after `settle()` hands back the film's state as text
//! (`engine::snapshot`); `restore(text)` between `start` and the first
//! `add_log` puts it back without replaying a change, and the host then adds
//! only the logs — or the ends of logs — the snapshot did not cover. The
//! state is the same either way, and so is what the clock has heard; the hub
//! keeps the text in its cache under the logs' names and sizes, so a stale
//! one is never restored and a missing one costs only the replay.

use std::cell::RefCell;

use shotlister_engine::format::{decode_log, encode_log};
use shotlister_engine::json::Json;
use shotlister_engine::{Change, DeviceId, Doc, GroupBy, Id, Query, FORMAT_VERSION};
use shotlister_mcp::films::{no_filesystem, Films};
use shotlister_mcp::Server;

/// New Film from the server (Projects Console without the Mac, stage 3 step 5).
pub mod newfilm;
/// Link a spare film to a project from the server (stage 4 step D).
pub mod linkfilm;

thread_local! {
    static SERVER: RefCell<Option<Server<Bucket>>> = const { RefCell::new(None) };
}

/// A film held as change logs, with the relay's bucket standing in for a disk.
pub struct Bucket {
    doc: Doc,
    /// The film's id in the bucket — `p/<id>/`. Answers `summary`'s `path`,
    /// because on this side that is genuinely where the film is.
    id: String,
    title: String,
    read_only: bool,
    /// How many of our own changes were already in the logs we were handed.
    /// Anything past this is what this request wrote and what has to go back.
    persisted: usize,
    /// Lines the logs held that this build could not read. Counted rather than
    /// dropped quietly, exactly as the Mac counts them.
    unreadable: usize,
    /// The log this request wants written, once `save` has been asked for.
    pending: String,
}

impl Bucket {
    pub fn new(id: &str, title: &str, read_only: bool, device: DeviceId) -> Bucket {
        Bucket {
            doc: Doc::new(device),
            id: id.to_string(),
            title: title.to_string(),
            read_only,
            persisted: 0,
            unreadable: 0,
            pending: String::new(),
        }
    }

    /// Take in one change log, exactly as the Mac takes in one file in
    /// `changes/`. Returns lines it could not read, or -1 for an unreadable log.
    pub fn take(&mut self, text: &str) -> i32 {
        match decode_log(text) {
            Ok(parsed) => {
                let preserved = parsed.preserved.len();
                self.doc.merge(parsed.changes);
                self.unreadable += preserved;
                preserved as i32
            }
            Err(_) => -1,
        }
    }

    /// The film put back from a snapshot, as this device. `false` — and the
    /// film untouched — for text this build will not trust; the host then
    /// replays as if there were none.
    pub fn restore(&mut self, text: &str) -> bool {
        match Doc::restore(self.doc.device(), text) {
            Ok(doc) => {
                self.doc = doc;
                true
            }
            Err(_) => false,
        }
    }

    /// Every log is in.
    ///
    /// Two things happen here and both matter. **History is cleared**, so
    /// nothing that came off the wire is undoable — the same call the Mac makes
    /// at the end of opening a film, and the reason `undo` truthfully answers
    /// "there is nothing to undo" over here rather than offering to reverse
    /// somebody else's work from a month ago. And **what is already ours is
    /// counted**, so that the log this request writes holds what this request
    /// did and not everything this person has ever done.
    pub fn settle(&mut self) {
        self.doc.clear_history();
        self.persisted = self.ours().len();
    }

    pub fn unreadable(&self) -> usize {
        self.unreadable
    }

    /// The log this request wants written, or empty if it changed nothing.
    pub fn pending(&self) -> &str {
        &self.pending
    }

    /// Our own changes, in the order we made them. Another device's changes sit
    /// in the same logs and are not ours to write out. Same rule as
    /// `storage::Project::ours`.
    fn ours(&self) -> Vec<&Change> {
        let device = self.doc.device();
        self.doc
            .changes()
            .iter()
            .filter(|change| change.stamp.device == device)
            .collect()
    }
}

impl Films for Bucket {
    /// The film is already open by the time any tool runs — the host fetched
    /// its logs before it could know which film was wanted. Naming the one that
    /// is open is allowed; naming a different one is the host's job, not a
    /// tool's, because only the host can reach the bucket.
    fn open(&mut self, _reference: &str) -> Result<(), String> {
        Ok(())
    }

    fn doc(&self) -> Result<&Doc, String> {
        Ok(&self.doc)
    }

    fn doc_mut(&mut self) -> Result<&mut Doc, String> {
        Ok(&mut self.doc)
    }

    fn title(&self) -> String {
        self.title.clone()
    }

    fn whereabouts(&self) -> String {
        self.id.clone()
    }

    fn read_only(&self) -> bool {
        self.read_only
    }

    /// Set aside a log holding whatever this request changed.
    ///
    /// **Always a whole log, never an append.** Each request is its own session
    /// and gets a name of its own in the bucket, so there is no file to append
    /// to — which is also why two requests landing at once cannot tread on each
    /// other: they write two files, and the merge settles the rest.
    ///
    /// Nothing unreadable is carried in. Those lines are in logs of their own
    /// that nobody rewrites, so they are already safe; copying them would put a
    /// second copy in the bucket every time anybody changed anything.
    fn save(&mut self) -> Result<(), String> {
        if self.read_only {
            return Err("You may look at this film, not change it.".to_string());
        }
        let ours: Vec<Change> = self.ours().into_iter().cloned().collect();
        let fresh: &[Change] = if self.persisted < ours.len() {
            &ours[self.persisted..]
        } else {
            &[]
        };
        if fresh.is_empty() {
            return Ok(());
        }
        self.pending = encode_log(FORMAT_VERSION, fresh, &[]);
        Ok(())
    }

    fn read_bytes(&self, _path: &str) -> Result<Vec<u8>, String> {
        Err(no_filesystem("Pinning a file to a shot"))
    }

    fn write_bytes(&mut self, _path: &str, _bytes: &[u8]) -> Result<(), String> {
        Err(no_filesystem("Writing the list out to a file"))
    }

    fn keep_media(&mut self, _hash: &str, _extension: &str, _bytes: &[u8]) -> Result<(), String> {
        Err(no_filesystem("Keeping a picture"))
    }
}

// ----------------------------------------------------------------- the ABI
//
// The same forty lines of pointer passing `web/src/lib.rs` uses, and for the
// same reason: a binding generator would be the only dependency in either
// crate.

/// Room for the caller to write a string into. Paired with `dealloc`.
///
/// A boxed slice rather than a `Vec`: `Vec::with_capacity` may hand back more
/// room than was asked for, and giving memory back with the wrong capacity is
/// undefined behaviour.
#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let buffer = vec![0u8; len].into_boxed_slice();
    Box::into_raw(buffer) as *mut u8
}

/// # Safety
/// `ptr` and `len` must be exactly what a previous `alloc` returned and asked for.
#[no_mangle]
pub unsafe extern "C" fn dealloc(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
    }
}

/// A result the caller reads and then frees: four bytes of length, then UTF-8.
fn give(text: String) -> *mut u8 {
    let bytes = text.into_bytes();
    let mut out = Vec::with_capacity(bytes.len() + 4);
    out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(&bytes);
    Box::into_raw(out.into_boxed_slice()) as *mut u8
}

/// # Safety
/// `ptr` must be a pointer one of the result-returning functions here returned,
/// freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn free_result(ptr: *mut u8) {
    if ptr.is_null() {
        return;
    }
    let mut length = [0u8; 4];
    std::ptr::copy_nonoverlapping(ptr, length.as_mut_ptr(), 4);
    let len = u32::from_le_bytes(length) as usize + 4;
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
}

/// # Safety
/// `ptr` must point at `len` bytes of UTF-8 the caller still owns.
unsafe fn taken(ptr: *const u8, len: usize) -> String {
    let slice = std::slice::from_raw_parts(ptr, len);
    String::from_utf8_lossy(slice).into_owned()
}

/// What time it is, in milliseconds since 1970. A worker has no clock the
/// engine can reach — see `engine::id`.
#[no_mangle]
pub extern "C" fn set_now(millis: f64) {
    shotlister_engine::id::set_now_millis(millis as u64);
}

/// Seed the id generator. Must be random per request, or two requests could
/// mint the same id.
#[no_mangle]
pub extern "C" fn set_seed(seed: f64) {
    shotlister_engine::id::set_seed(seed as u64);
}

/// Begin a film.
///
/// **The device is a hexadecimal string, not a number**, because a device id is
/// 64 bits and the numbers that cross this boundary are doubles, which quietly
/// lose the bottom eleven of them. A device that rounded would be a different
/// device on every other request, and the film would fill with strangers.
///
/// # Safety
/// Every pointer/length pair must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn start(
    id_ptr: *const u8,
    id_len: usize,
    title_ptr: *const u8,
    title_len: usize,
    read_only: i32,
    device_ptr: *const u8,
    device_len: usize,
) -> i32 {
    let id = taken(id_ptr, id_len);
    let title = taken(title_ptr, title_len);
    let device_text = taken(device_ptr, device_len);
    let device = match u64::from_str_radix(device_text.trim(), 16) {
        Ok(number) => DeviceId(number),
        Err(_) => return -1,
    };
    let bucket = Bucket::new(&id, &title, read_only != 0, device);
    SERVER.with(|server| *server.borrow_mut() = Some(Server::with(bucket)));
    0
}

/// Take in one change log. Returns lines it could not read, -1 for an
/// unreadable log, or -2 if no film was begun.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn add_log(ptr: *const u8, len: usize) -> i32 {
    let text = taken(ptr, len);
    SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => server.films_mut().take(&text),
        None => -2,
    })
}

/// Put the film back from a snapshot `snapshot()` gave an earlier request.
/// **Between `start` and the first `add_log`**, so that what is added
/// afterwards lands on top of it. Returns 0, -1 for text that was not
/// trusted (the film is untouched, and every log should be added as usual),
/// or -2 if no film was begun.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn restore(ptr: *const u8, len: usize) -> i32 {
    let text = taken(ptr, len);
    SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => {
            if server.films_mut().restore(&text) {
                0
            } else {
                -1
            }
        }
        None => -2,
    })
}

/// The film's state as text, for a later request to `restore`. Empty if no
/// film was begun.
#[no_mangle]
pub extern "C" fn snapshot() -> *mut u8 {
    SERVER.with(|server| {
        let held = server.borrow();
        match held.as_ref().and_then(|s| s.films().doc().ok()) {
            Some(doc) => give(doc.snapshot()),
            None => give(String::new()),
        }
    })
}

/// Every log is in.
#[no_mangle]
pub extern "C" fn settle() -> i32 {
    SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => {
            server.films_mut().settle();
            server.films().unreadable() as i32
        }
        None => -2,
    })
}

/// Handle one JSON-RPC message and give back the reply, or an empty string for
/// a notification, which by definition is not answered.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn handle(ptr: *const u8, len: usize) -> *mut u8 {
    let message = taken(ptr, len);
    SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => give(server.handle(&message).unwrap_or_default()),
        None => give(String::new()),
    })
}

/// **The film half of a film's card on the portal**, asked of the film.
///
/// What `hub/refresh.py` used to compute on his Mac with `dump_view` — the
/// credits, the ratio, the counts, the dated days and which pictures stand for
/// the scenes, the locations and the boards — so a page is never behind the
/// film. The hub asks this on every look (cached under the logs' own names
/// and sizes, so it is computed once per change); `refresh.py` now writes only
/// what Notion knows. The shape is exactly what `front.js` `tidy`s, and the
/// rules are the ones `refresh.py` had: eight scene frames, one picture per
/// location or board before a second from any, twelve dated days.
///
/// Picture names are the relay's — the hash's first thirty-two characters and
/// the proxy's extension, a clip by its poster (`jpg`, and the hub answers the
/// PNG under that name for an older film). The same rule as `picture_at` in
/// `web/src/lib.rs`.
#[no_mangle]
pub extern "C" fn card() -> *mut u8 {
    SERVER.with(|server| {
        let held = server.borrow();
        let doc = match held.as_ref().and_then(|s| s.films().doc().ok()) {
            Some(doc) => doc,
            None => return give(String::new()),
        };
        give(film_card(doc).encode())
    })
}

fn film_card(doc: &Doc) -> Json {
    use shotlister_engine::doc::f;
    use shotlister_engine::view::{reference, text};

    let project = doc.project_id();
    let said = |field: &str| project.map(|p| text(doc, p, field)).unwrap_or_default();

    // A picture's name in the bucket, or nothing for a hash-less record.
    let name_of = |media: Id| -> Option<String> {
        let hash = text(doc, media, f::HASH);
        if hash.is_empty() {
            return None;
        }
        let moving = doc.media_kind(media).map(|k| k.is_moving()).unwrap_or(false);
        let extension = if moving {
            "jpg".to_string()
        } else {
            let filename = text(doc, media, f::FILENAME);
            filename.rsplit('.').next().unwrap_or("png").to_lowercase()
        };
        let extension: String = extension
            .trim_start_matches('.')
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .take(8)
            .collect();
        let short: String = hash.chars().take(32).collect();
        Some(format!("{short}.{}", if extension.is_empty() { "png".to_string() } else { extension }))
    };

    // A frame off the front of each scene, in the film's own order: the first
    // placed shot that has a key picture, the master's when it stands in.
    let mut scenes = Vec::new();
    for scene in doc.scenes_in_order() {
        if doc.is_archived(scene) {
            continue;
        }
        let mut frame = None;
        for placement in doc.placements_in_scene(scene) {
            let Some(shot) = reference(doc, placement, f::SHOT) else { continue };
            let shown = doc.described_by(shot);
            let key_ref = reference(doc, shown, f::KEY_MEDIA)
                .or_else(|| doc.media_refs(shown).first().copied());
            if let Some(media) = key_ref.and_then(|r| reference(doc, r, f::MEDIA)) {
                if let Some(name) = name_of(media) {
                    frame = Some(name);
                    break;
                }
            }
        }
        if let Some(name) = frame {
            if !scenes.contains(&name) {
                scenes.push(name);
            }
        }
        if scenes.len() >= 8 {
            break;
        }
    }

    // One picture from each thing, then more from the front, up to `want` —
    // so a mosaic shows four different boards rather than four off one.
    let some = |owners: Vec<Id>, want: usize, pictures_only: bool| -> Vec<String> {
        let walls: Vec<Vec<Id>> = owners
            .iter()
            .map(|owner| if pictures_only { doc.picture_refs(*owner) } else { doc.media_refs(*owner) })
            .collect();
        let mut picked: Vec<String> = Vec::new();
        for round in 0..4 {
            for wall in &walls {
                if picked.len() >= want {
                    return picked;
                }
                if let Some(mref) = wall.get(round) {
                    if let Some(name) = reference(doc, *mref, f::MEDIA).and_then(name_of) {
                        if !picked.contains(&name) {
                            picked.push(name);
                        }
                    }
                }
            }
        }
        picked
    };
    let locations = some(doc.locations_in_order(), 5, true);
    let boards = some(doc.boards_in_order(), 6, false);

    // The days as the film has them, dated ones only: the tile draws a
    // calendar, and a calendar needs a date.
    let days_in_order = doc.days_in_order();
    let days: Vec<Json> = days_in_order
        .iter()
        .filter(|day| !doc.day_date(**day).is_empty())
        .take(12)
        .map(|day| {
            Json::object(vec![
                ("label", Json::text(doc.day_label(*day).unwrap_or_default())),
                ("date", Json::text(doc.day_date(*day))),
                // The shoot the day names (piece D), as stored; empty if none.
                ("shoot", Json::text(doc.said_shoot(*day))),
            ])
        })
        .collect();

    // **The drafts of the script, newest first** — the portal's Script page
    // (SL-1338). Each draft's text and PDF travel to the bucket as
    // `media/<hash[..32]>.txt` / `.pdf`, so the stem is all the page needs to
    // find them. Read off the film, so a draft taken in on the Mac is the
    // page's newest the moment its log arrives; nobody re-pins anything.
    let scripts: Vec<Json> = doc
        .revisions()
        .into_iter()
        .filter(|r| !r.hash.is_empty())
        .map(|r| {
            Json::object(vec![
                ("name", Json::text(r.name)),
                ("came_from", Json::text(r.filename)),
                ("dated", Json::text(r.imported_at)),
                ("stem", Json::text(r.hash.chars().take(32).collect::<String>())),
            ])
        })
        .collect();

    // **Each scene's section, its one day's date and whether it is set
    // aside** (Ref 1408) — so the portal's sidebar counts a shoot's scenes on
    // the server by the rule the program uses in the browser (`inShoot` and
    // `setAside` in `public/film.js`, `shotListCount` in `src/front.js`). A
    // scene on two days has no single day, as the program reads it.
    let scene_list: Vec<Json> = doc
        .scenes_in_order()
        .into_iter()
        .map(|scene| {
            let section = reference(doc, scene, f::SEQUENCE).map(|q| text(doc, q, f::TITLE)).unwrap_or_default();
            let days = doc.days_of_scene(scene);
            let day = if days.len() == 1 { doc.day_date(days[0]) } else { String::new() };
            Json::object(vec![
                ("section", Json::text(section)),
                ("day", Json::text(day)),
                ("archived", Json::Bool(doc.is_archived(scene))),
                // The shoot the scene names (piece D), as stored; empty if
                // none. Once a film has these, the portal goes by them.
                ("shoot", Json::text(doc.said_shoot(scene))),
            ])
        })
        .collect();

    let shots = doc.count(&Query::grouped_by(GroupBy::Flat));
    let number = |n: usize| Json::Number(n as f64);
    Json::object(vec![
        ("director", Json::text(said(f::DIRECTOR))),
        ("producer", Json::text(said(f::PRODUCER))),
        (
            "ratio",
            Json::Number(
                project
                    .and_then(|p| doc.get(p))
                    .and_then(|r| r.float(f::ASPECT_RATIO))
                    .unwrap_or(0.0),
            ),
        ),
        // **The frame Studio picked** (piece E), by name: the portal draws
        // that frame of the card's, with the ratio above as the fallback.
        ("frame", Json::text(doc.studio_frame_said())),
        ("console_page", Json::text(said("console_page"))),
        (
            "counts",
            Json::object(vec![
                ("scenes", number(doc.scenes_in_order().len())),
                ("shots", number(shots)),
                ("locations", number(doc.locations_in_order().len())),
                ("boards", number(doc.boards_in_order().len())),
                ("days", number(days_in_order.len())),
                // Scenes with a plan on them, and loose plans with anything
                // on them — the portal's Diagrams row lists both.
                (
                    "diagrams",
                    number(
                        doc.scenes_with_diagrams().len()
                            + doc.plans_in_order().into_iter().filter(|p| doc.diagram_count(*p) > 0).count(),
                    ),
                ),
            ]),
        ),
        ("days", Json::Array(days)),
        ("scene_list", Json::Array(scene_list)),
        ("scripts", Json::Array(scripts)),
        // **How many shots hold lines of the screenplay** (Ref 1553), so the
        // Script page knows whether there are marks to draw (Ref 1568)
        // without replaying the film in the browser to find out.
        ("play_shots", number(doc.shots_holding_lines().len())),
        (
            "pictures",
            Json::object(vec![
                ("scenes", Json::Array(scenes.into_iter().map(Json::text).collect())),
                ("locations", Json::Array(locations.into_iter().map(Json::text).collect())),
                ("boards", Json::Array(boards.into_iter().map(Json::text).collect())),
            ]),
        ),
    ])
}

/// **Pin a picture the bucket already holds to a shot** — the board's *Add to
/// Shot*. His question, 2026-09-25: a still laid on a shot on a board, should
/// it go to that shot in Shotlister too? Yes, when he says so.
///
/// The engine's own `attach` reads a file off a disk, which a worker has not
/// got. Here the file is already in the bucket, under the relay's name for it
/// (`media/<hash[..32]>.<ext>`) — the host put it there before asking — so all
/// this does is what `attach` does once it has the bytes: the file by its
/// hash (the same file already in the film is reused, never doubled), a use
/// of it on the shot, and the film saved, which leaves a log in
/// `pending_log()` for the host to keep.
///
/// Takes `{"shot": "3A", "hash": <64 hex>, "name": "x.jpg", "size": n,
/// "caption": ""}` and answers `{"ok": "Pinned x.jpg to shot 3A."}` or
/// `{"error": "…"}`.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn attach(ptr: *const u8, len: usize) -> *mut u8 {
    let asked = taken(ptr, len);
    let said = SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => attach_to_shot(server.films_mut(), &asked),
        None => Err("No film is open.".to_string()),
    });
    give(
        match said {
            Ok(text) => Json::object(vec![("ok", Json::text(text))]),
            Err(text) => Json::object(vec![("error", Json::text(text))]),
        }
        .encode(),
    )
}

/// **Diagram edits from the portal's Diagrams page** — a batch, in order, kept
/// as one change log in the editor's name (`diagramEdit` in hub/src/mcp.js).
///
/// `{scene, ops: [{op: {...}, made: ["browser id", …]}]}`. The browser made
/// each edit on its own copy first, and a piece it added has the browser's id
/// for it; the film's id is a new record's. So every piece made here is
/// matched to the browser's id for it, later edits in the batch that name the
/// browser's id are pointed at the film's, and the pairs go back so the page
/// can follow.
#[no_mangle]
pub unsafe extern "C" fn diagram_edits(ptr: *const u8, len: usize) -> *mut u8 {
    let asked = taken(ptr, len);
    let said = SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => edit_diagram(server.films_mut(), &asked),
        None => Err("No film is open.".to_string()),
    });
    give(match said {
        Ok(text) => text,
        Err(text) => Json::object(vec![("error", Json::text(text))]).encode(),
    })
}


/// **The edits that are not the plan's own** — the Mac's other diagram
/// commands, as edits the portal can send like any other: a plan copied from
/// another scene or sent to others, a room laid from a location's scan, a setting on every
/// scene, a favorite slot kept. `None` for an ordinary plan edit. The same
/// function is in `web` (`special_edit`) — the server makes them exactly as
/// the page did.
fn special_edit(doc: &mut Doc, scene: Id, op: &Json) -> Option<Result<Vec<String>, String>> {
    use shotlister_engine::diagram::El;
    match op.get("op").and_then(|o| o.as_str()).unwrap_or("") {
        // Another scene's plan, or the pieces `ids` of it, onto this one —
        // replacing what is here, or `mode: "add"` on top of it.
        "copy_from" | "send" => {
            use shotlister_engine::diagram::copy::Mode;
            let Some(mode) = Mode::parse(&op.str_field("mode")) else {
                return Some(Err("mode is replace or add".into()));
            };
            let list = |k: &str| -> Vec<String> {
                op.get(k).and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect()).unwrap_or_default()
            };
            let ids = list("ids");
            let scene_of = |t: &str| t.trim().parse::<u128>().ok().map(Id);
            // `send`: this plan, or the pieces `ids`, onto the scenes `to`.
            let (from, to) = if op.get("op").and_then(|o| o.as_str()) == Some("send") {
                (scene, list("to").iter().filter_map(|t| scene_of(t)).collect::<Vec<Id>>())
            } else {
                (scene_of(&op.str_field("from"))?, vec![scene])
            };
            if doc.get(from).is_none() || to.iter().any(|t| doc.get(*t).is_none()) {
                return Some(Err("that scene is gone".into()));
            }
            Some(Ok(doc.diagram_copy(from, &ids, &to, mode)))
        }
        // **Loose plans** (`diagram::plans`), from the portal: `plan_new`
        // makes one under the id the page chose (so the page and the server
        // make the same one), starting as a copy of `from` when given;
        // `plan_rename` and `plan_delete` act on the plan `scene` names.
        "plan_new" => {
            let id = op.str_field("id").trim().parse::<u128>().ok().map(Id);
            let from = op.str_field("from").trim().parse::<u128>().ok().map(Id);
            let made = doc.add_plan_with(id, &op.str_field("name"), from);
            Some(Ok(vec![made.0.to_string()]))
        }
        "plan_rename" => {
            if !doc.is_plan(scene) {
                return Some(Err("that is not a plan".into()));
            }
            doc.rename_plan(scene, &op.str_field("name"));
            Some(Ok(Vec::new()))
        }
        "plan_delete" => {
            if !doc.is_plan(scene) {
                return Some(Err("that plan is gone".into()));
            }
            doc.delete_plan(scene);
            Some(Ok(Vec::new()))
        }
        "room" => {
            let Some(plan) = shotlister_engine::room::read(&op.str_field("scan")) else {
                return Some(Err("there is no room in that scan".into()));
            };
            Some(Ok(doc.diagram_import_room(scene, &plan, &op.str_field("location"))))
        }
        // **Add Shot** (the Mac's Shots tab): a new shot at the end of the
        // scene, not yet on the plan — its camera is placed later, or never.
        "add_shot" => {
            if doc.get(scene).map(|r| r.kind == shotlister_engine::store::Kind::Scene) != Some(true) {
                return Some(Err("a loose plan has no scene to add a shot to".into()));
            }
            let (shot, _) = doc.add_shot_to_scene(scene);
            Some(Ok(vec![shot.0.to_string()]))
        }
        "everywhere" => {
            let value = op.get("value")?.clone();
            doc.diagram_setting_everywhere(&op.str_field("key"), value);
            Some(Ok(Vec::new()))
        }
        "picture" => {
            // A picture chosen from the computer: already kept among the
            // film's pictures by its hash (`PUT api/picture`); here it gets
            // its record and is laid on the plan — `diagram_add_image`, the
            // Mac's own step.
            let hash = shotlister_engine::Hash256::from_hex(&op.str_field("hash"))?;
            let n = |k: &str| op.get(k).and_then(|v| v.as_f64()).filter(|v| v.is_finite()).unwrap_or(0.0);
            let ext = op.str_field("ext");
            let made = doc.diagram_add_image(
                scene, hash, if ext.is_empty() { "jpg" } else { &ext }, (n("pw").max(0.0) as u32, n("ph").max(0.0) as u32),
                n("bytes").max(0.0) as u64, &op.str_field("filename"), (n("x"), n("y")), n("width").max(0.5),
                op.get("photo").and_then(|v| v.as_bool()).unwrap_or(false),
            );
            Some(made.map(|id| vec![id]).ok_or_else(|| "the picture could not be laid on the plan".to_string()))
        }
        "favorite" => {
            let slot = op.get("slot").and_then(|s| s.as_f64()).map(|s| s as usize).unwrap_or(usize::MAX);
            let piece = op.get("el").filter(|e| !e.is_null()).and_then(El::from_json);
            if !doc.set_diagram_favorite_from(slot, scene, piece.as_ref()) {
                return Some(Err("no such slot".into()));
            }
            Some(Ok(Vec::new()))
        }
        _ => None,
    }
}

fn edit_diagram(films: &mut Bucket, asked: &str) -> Result<String, String> {
    use shotlister_engine::Id;
    let asked = shotlister_engine::json::parse(asked).ok_or("That is not JSON.")?;
    if films.read_only() {
        return Err("You may look at this film, not change it.".to_string());
    }
    let reference = asked.str_field("scene");
    let doc = films.doc_mut()?;
    let scene = reference
        .trim()
        .parse::<u128>()
        .ok()
        .map(Id)
        .filter(|id| doc.get(*id).is_some())
        .or_else(|| shotlister_mcp::tools::find_scene(doc, &reference))
        .ok_or_else(|| format!("No scene called {reference}."))?;
    let ops = asked.get("ops").and_then(|o| o.as_array()).ok_or("Say what to change: ops.")?;
    // **A link visitor** (the worker says so, never the page): what takes a
    // whole diagram away is kept only when the page asked first, as it asks
    // him; and the edits that take the batch back are said, so his history
    // of link edits can undo it.
    let link = asked.get("link").and_then(|v| v.as_bool()) == Some(true);
    let mut undo: Vec<Json> = Vec::new();
    let mut renamed: Vec<(String, String)> = Vec::new();
    let mut failed: Vec<String> = Vec::new();
    for step in ops {
        let Some(op) = step.get("op") else { continue };
        let text = renamed
            .iter()
            .fold(op.encode(), |t, (a, b)| t.replace(&format!("\"{a}\""), &format!("\"{b}\"")));
        let Some(op) = shotlister_engine::json::parse(&text) else { continue };
        if link
            && shotlister_engine::diagram::portal::wipes(doc, scene, &op)
            && op.get("confirmed").and_then(|v| v.as_bool()) != Some(true)
        {
            failed.push("a whole diagram is only taken away after the page asks".to_string());
            continue;
        }
        let before = link.then(|| doc.diagram(scene));
        let made = match doc.portal_edit(scene, &op) {
            Some(Ok(sp)) => {
                if link {
                    undo.splice(0..0, sp.undo);
                }
                Ok(sp.made)
            }
            Some(Err(e)) => Err(e),
            None => match special_edit(doc, scene, &op) {
                Some(result) => result,
                None => doc.diagram_edit(scene, &op).map_err(|e| e.to_string()),
            }
            .map(|made| {
                if let Some(before) = &before {
                    undo.splice(0..0, shotlister_engine::diagram::portal::undo_ops(before, &doc.diagram(scene)));
                }
                made
            }),
        };
        match made {
            Ok(made) => {
                let theirs: Vec<String> = step
                    .get("made")
                    .and_then(|m| m.as_array())
                    .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
                    .unwrap_or_default();
                renamed.extend(theirs.into_iter().zip(made).filter(|(a, b)| a != b));
            }
            // One edit that no longer fits — a piece somebody else deleted a
            // moment ago — is skipped and said, not the whole batch lost.
            Err(e) => failed.push(e),
        }
    }
    films.save()?;
    let pairs: Vec<Json> = renamed
        .iter()
        .map(|(a, b)| Json::Array(vec![Json::text(a.clone()), Json::text(b.clone())]))
        .collect();
    let skipped: Vec<Json> = failed.into_iter().map(Json::text).collect();
    let mut said = vec![("ok", Json::Bool(true)), ("renamed", Json::Array(pairs)), ("skipped", Json::Array(skipped))];
    if link {
        said.push(("undo", Json::Array(undo)));
    }
    Ok(Json::object(said).encode())
}

fn attach_to_shot(films: &mut Bucket, asked: &str) -> Result<String, String> {
    use shotlister_engine::doc::f;
    use shotlister_engine::media::MediaKind;
    let asked = shotlister_engine::json::parse(asked).ok_or("That is not JSON.")?;
    let shot = asked.str_field("shot");
    let name = asked.str_field("name");
    let caption = asked.str_field("caption");
    let size = asked.get("size").and_then(|v| v.as_f64()).unwrap_or(0.0).max(0.0) as u64;
    let hash = shotlister_engine::Hash256::from_hex(&asked.str_field("hash"))
        .ok_or("That file has no whole hash.")?;
    // **Not only a shot** (2026-10-17, the connector's `add_picture`): a
    // scene, a location, a reference board or an edit reference, named as
    // every attachment tool names them. A board's Add to Shot sends `shot`.
    let others = ["scene", "location", "board", "edit_reference"];
    if shot.trim().is_empty() && others.iter().all(|k| asked.str_field(k).trim().is_empty()) {
        return Err("Say which shot.".to_string());
    }
    if films.read_only() {
        return Err("You may look at this film, not change it.".to_string());
    }
    let doc = films.doc_mut()?;
    let (owner, whose) = if !shot.trim().is_empty() {
        let placement = shotlister_mcp::tools::find_placement(doc, &shot)
            .ok_or_else(|| format!("No shot called {shot}."))?;
        let owner = doc
            .get(placement)
            .and_then(|r| r.ref_id(f::SHOT))
            .ok_or_else(|| format!("No shot called {shot}."))?;
        (owner, format!("Shot {}", doc.display_number(placement).unwrap_or_else(|| shot.clone())))
    } else {
        let (owner, said) = shotlister_mcp::server::attachment_owner(doc, &asked)?
            .ok_or("Say which shot, scene, location, board or edit reference.")?;
        let mut said = said;
        if let Some(first) = said.get(..1) {
            said = format!("{}{}", first.to_uppercase(), &said[1..]);
        }
        (owner, said)
    };
    let kind = MediaKind::guess_from_name(&name);
    if !matches!(kind, MediaKind::Image | MediaKind::Gif | MediaKind::Video) {
        return Err("Only pictures and clips go on it here.".to_string());
    }
    let media = doc.add_media(hash, kind, 0, 0, size, &name);
    // **Once per owner.** Laying the same picture on the same shot twice is
    // the same thought twice, not two frames.
    let already = doc
        .media_refs(owner)
        .iter()
        .any(|r| doc.get(*r).and_then(|x| x.ref_id(f::MEDIA)) == Some(media));
    if already {
        return Ok(format!("{whose} already has it."));
    }
    doc.attach_media(owner, media, &caption);
    films.save()?;
    Ok(format!("Added to {whose}."))
}

/// **The project record's facts, mirrored into the film** — what the Mac's
/// `--recordfacts` and `--setmark` doors do, from the server (Projects
/// Console without the Mac, stage 3, 2026-10-11).
///
/// Takes `{"facts": {"title": …, "director": …, "producer": …, "client": …,
/// "agency": …}, "mark": {"path": "M…", "colour": "#RRGGBB"}}` — either half
/// may be left out — and answers `{"ok": true, "changed": ["director", …],
/// "mark": "mirrored"|"same"|"hand"|"none"}` or `{"error": "…"}`.
///
/// **The same rules as the Mac's door, because it is the same engine:**
/// only the five facts and the mark are written, never a scene, a shot or a
/// day; a fact the film already shows is not written again (nothing changed
/// leaves no log to keep); and the mirror makes no undo step. A mark he set
/// by hand (`mark_source` `hand`) is never written over. The film is saved,
/// which leaves a log in `pending_log()` for the host to keep.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the length of the call.
#[no_mangle]
pub unsafe extern "C" fn mirror_record(ptr: *const u8, len: usize) -> *mut u8 {
    let asked = taken(ptr, len);
    let said = SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => mirror_into_film(server.films_mut(), &asked),
        None => Err("No film is open.".to_string()),
    });
    give(match said {
        Ok(text) => text,
        Err(text) => Json::object(vec![("error", Json::text(text))]).encode(),
    })
}

pub fn mirror_into_film(films: &mut Bucket, asked: &str) -> Result<String, String> {
    use shotlister_engine::mark::{Mark, Source};
    let asked = shotlister_engine::json::parse(asked).ok_or("That is not JSON.")?;
    if films.read_only() {
        return Err("You may look at this film, not change it.".to_string());
    }
    let doc = films.doc_mut()?;
    if doc.project_id().is_none() {
        return Err("this film has no project record".to_string());
    }
    // **Only a film that carries this project's page id** — the Mac's rule
    // (`filmfacts.mirror_one`: a film held to its project by a matching title
    // alone is a guess, and a guess does not get to write).
    let bare = |s: &str| s.chars().filter(|c| *c != '-').collect::<String>().to_lowercase();
    let link = asked.str_field("link");
    if !link.is_empty() {
        let project = doc.project_id().ok_or("this film has no project record")?;
        let carried = doc.get(project).and_then(|r| r.text("console_page")).unwrap_or("").to_string();
        if bare(&carried) != bare(&link) {
            return Err("the film is only matched by its title, so it is not written — link it first".to_string());
        }
    }
    let mut changed: Vec<&'static str> = Vec::new();
    if let Some(facts) = asked.get("facts") {
        let mut given: Vec<(String, String)> = Vec::new();
        for (word, _) in shotlister_engine::recordfacts::FACTS {
            if let Some(value) = facts.get(word).and_then(|v| v.as_str()) {
                given.push((word.to_string(), value.to_string()));
            }
        }
        if !given.is_empty() {
            changed = doc.take_record_facts(&given)?;
        }
    }
    let mut mark_said = "none";
    if let Some(mark) = asked.get("mark") {
        let path = mark.str_field("path");
        let colour = mark.str_field("colour");
        if !doc.mark_source().mirrorable() {
            mark_said = "hand";
        } else if path.is_empty() && colour.is_empty() {
            mark_said = if doc.set_mark(None, Source::Console) { "mirrored" } else { "same" };
        } else {
            if shotlister_engine::mark::colour(&colour).is_none() {
                return Err("a colour reads like #D44C47".to_string());
            }
            if shotlister_engine::mark::outline(&path).is_none() {
                return Err("that is not an icon outline".to_string());
            }
            let wanted = Mark { path, colour };
            mark_said = if doc.set_mark(Some(&wanted), Source::Console) { "mirrored" } else { "same" };
        }
    }
    films.save()?;
    Ok(Json::object(vec![
        ("ok", Json::Bool(true)),
        ("changed", Json::Array(changed.iter().map(|w| Json::text(*w)).collect())),
        ("mark", Json::text(mark_said)),
    ])
    .encode())
}

/// **The whole film, as the board's browser reads it** — `view` in
/// `web/src/lib.rs`, asked of the same engine with the default question
/// (every shot, grouped by scene). The hub's boards tools use it so a card an
/// AI puts on a board from the film — a shot, a scene, a location, a day, a
/// picture off one of Shotlister's own mood boards — is made the way the
/// board's own *From the Film* makes it, instead of waiting for a browser.
#[no_mangle]
pub extern "C" fn view() -> *mut u8 {
    use shotlister_engine::view::{describe, Asked, Standing};
    SERVER.with(|server| {
        let held = server.borrow();
        let doc = match held.as_ref().and_then(|s| s.films().doc().ok()) {
            Some(doc) => doc,
            None => return give(String::new()),
        };
        let asked = Asked::default();
        give(describe(doc, &asked.looking(), &Standing { read_only: true, unsaved: 0, device_clash: None }))
    })
}

/// **The project's card, laid over the film** (stage 5 step 4, piece A):
/// the hub hands in the card it keeps for this project after the logs are
/// fed, and everything asked afterwards (a tool's reply, an export, `view`)
/// shows the card's title, credits, mark and kind. Nothing is written. Empty
/// text or `none` takes it off. Returns 0, -1 for text that is not a card,
/// or -2 if no film was begun.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn set_card(ptr: *const u8, len: usize) -> i32 {
    let text = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    let card = if text.trim().is_empty() || text.trim() == "none" {
        None
    } else {
        match shotlister_engine::card::Card::read(&text) {
            Some(card) => Some(card),
            None => return -1,
        }
    };
    SERVER.with(|server| match server.borrow_mut().as_mut() {
        Some(server) => match server.films_mut().doc_mut() {
            Ok(doc) => {
                doc.set_card(card);
                0
            }
            Err(_) => -2,
        },
        None => -2,
    })
}

/// **The film as somebody on a view link is shown it** — `view` with the
/// question asked: shooting order or the script's, a column to sort by, a
/// search. The same fields `asked_from` in `web/src/lib.rs` reads, so a sort
/// on a view link means what it means in his own browser.
///
/// **The view's filter is not asked here.** It is narrowed by the hub on the
/// values the page draws (`hub/public/narrow.js`), for the reason
/// `keepsFacets` in `hub/public/film.js` gives: the engine's `shot_is`
/// compares what a shot stores, and a filter is picked by what it shows.
///
/// # Safety
/// `ptr`/`len` must describe UTF-8 the caller owns for the call.
#[no_mangle]
pub unsafe extern "C" fn view_as(ptr: *const u8, len: usize) -> *mut u8 {
    use shotlister_engine::view::{describe, Asked, Standing};
    let text = if ptr.is_null() || len == 0 { String::new() } else { taken(ptr, len) };
    let mut asked = Asked::default();
    if let Some(said) = shotlister_engine::json::parse(&text) {
        asked.search = said.str_field("search");
        if said.get("groupBy").and_then(|v| v.as_str()) == Some("day") {
            asked.group_by = GroupBy::Day;
        }
        if let Some(column) = said.get("sortColumn").and_then(|v| v.as_str()) {
            if !column.is_empty() {
                let down = said.get("sortDescending").and_then(|v| v.as_bool()).unwrap_or(false);
                asked.sort = Some((column.to_string(), down));
            }
        }
    }
    SERVER.with(|server| {
        let held = server.borrow();
        let doc = match held.as_ref().and_then(|s| s.films().doc().ok()) {
            Some(doc) => doc,
            None => return give(String::new()),
        };
        give(describe(doc, &asked.looking(), &Standing { read_only: true, unsaved: 0, device_clash: None }))
    })
}

/// The change log this request wants written, or empty if it changed nothing.
#[no_mangle]
pub extern "C" fn pending_log() -> *mut u8 {
    SERVER.with(|server| {
        give(
            server
                .borrow()
                .as_ref()
                .map(|s| s.films().pending().to_string())
                .unwrap_or_default(),
        )
    })
}

#[cfg(test)]
mod mirror_tests {
    use super::*;
    use shotlister_mcp::Films;

    const PAGE: &str = "e6ee5875f5d789412e0b12538f71cfb5";

    /// A film as another device made it: a project that carries a page id.
    fn a_linked_film(link: &str) -> String {
        shotlister_engine::id::set_now_millis(1_760_000_000_000);
        shotlister_engine::id::set_seed(7);
        let mut first = Bucket::new("film", "Lets Bake", false, DeviceId(1));
        let doc = first.doc_mut().unwrap();
        let project = doc.create_project("Lets Bake");
        doc.set(project, "console_page", link);
        doc.set(project, shotlister_engine::doc::f::DIRECTOR, "Owen Fairweather");
        first.save().unwrap();
        first.pending().to_string()
    }

    fn open(log: &str, device: u64) -> Bucket {
        let mut b = Bucket::new("film", "Lets Bake", false, DeviceId(device));
        b.take(log);
        b.settle();
        b
    }

    fn answer(b: &mut Bucket, json: &str) -> shotlister_engine::json::Json {
        shotlister_engine::json::parse(&mirror_into_film(b, json).expect("answers")).unwrap()
    }

    #[test]
    fn a_linked_film_takes_the_records_words_once() {
        let base = a_linked_film(PAGE);
        let mut b = open(&base, 2);
        let asked = format!(
            r#"{{"link":"{PAGE}","facts":{{"title":"Let's Bake","director":"Ollie Hart Brennan","producer":"Marta Delgado","client":"Acme Express","agency":"Fabrica"}}}}"#
        );
        let said = answer(&mut b, &asked);
        let changed = said.get("changed").unwrap().encode();
        assert!(changed.contains("director") && changed.contains("producer") && changed.contains("source"), "{changed}");
        assert!(b.pending().lines().count() > 1, "a change to keep");
        // The same words again: nothing changed, nothing to keep.
        let log = b.pending().to_string();
        let mut again = open(&format!("{base}{log}"), 3);
        let said = answer(&mut again, &asked);
        assert_eq!(said.get("changed").unwrap().encode(), "[]");
        assert_eq!(again.pending(), "");
        assert_eq!(again.doc().unwrap().shown_title(), "Let's Bake");
        assert!(again.doc().unwrap().facts_from_record());
    }

    #[test]
    fn a_film_held_by_its_title_alone_is_not_written() {
        let base = a_linked_film("");
        let mut b = open(&base, 2);
        let why = mirror_into_film(&mut b, &format!(r#"{{"link":"{PAGE}","facts":{{"director":"A"}}}}"#)).unwrap_err();
        assert!(why.contains("only matched by its title"), "{why}");
        let other = a_linked_film("00000000000000000000000000000000");
        let mut c = open(&other, 2);
        assert!(mirror_into_film(&mut c, &format!(r#"{{"link":"{PAGE}","facts":{{"director":"A"}}}}"#)).is_err());
        assert_eq!(c.pending(), "");
    }

    #[test]
    fn a_fact_given_alone_is_written_alone() {
        let base = a_linked_film(PAGE);
        let mut b = open(&base, 2);
        let said = mirror_into_film(&mut b, &format!(r#"{{"link":"{PAGE}","facts":{{"director":"A"}}}}"#)).unwrap();
        assert!(said.contains("director"));
    }

    #[test]
    fn an_icon_set_by_hand_is_never_written_over() {
        let base = a_linked_film(PAGE);
        let mut b = open(&base, 2);
        let mark = r##"{"path":"M10 2 L18 18 L2 18 Z","colour":"#d44c47"}"##;
        let said = answer(&mut b, &format!(r#"{{"link":"{PAGE}","mark":{mark}}}"#));
        assert_eq!(said.get("mark").unwrap().as_str(), Some("mirrored"));
        let log = b.pending().to_string();
        let mut again = open(&format!("{base}{log}"), 3);
        let said = answer(&mut again, &format!(r#"{{"link":"{PAGE}","mark":{mark}}}"#));
        assert_eq!(said.get("mark").unwrap().as_str(), Some("same"));
        // Now he sets one by hand: the mirror leaves it.
        let hand = shotlister_engine::mark::Mark { path: "M1 1 L5 5".into(), colour: "#112233".into() };
        again.doc_mut().unwrap().set_mark(Some(&hand), shotlister_engine::mark::Source::Hand);
        let said = answer(&mut again, &format!(r#"{{"link":"{PAGE}","mark":{mark}}}"#));
        assert_eq!(said.get("mark").unwrap().as_str(), Some("hand"));
    }
}
