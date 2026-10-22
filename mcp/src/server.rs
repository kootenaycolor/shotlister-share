//! The protocol, and what answers it.

#[cfg(feature = "disk")]
use shotlister_engine::DeviceId;

use crate::films::Films;
use crate::json::{self, Json};
use crate::tools;

mod diagram;
mod film;
mod kit;
mod media;
mod editref;
mod export;
mod misc;
mod places;
mod printframe;
mod schedule;
mod shootpick;
mod shots;
mod versions;

const PROTOCOL_VERSION: &str = "2024-11-05";

/// Every tool: the first list, then each area's own. Areas since 2026-09-30,
/// when his rule — anything he can do in the app, Claude can do here — made
/// one list too long to find anything in.
fn all_tools() -> impl Iterator<Item = &'static Tool> {
    TOOLS.iter().chain(schedule::TOOLS.iter()).chain(places::TOOLS.iter()).chain(shots::TOOLS.iter()).chain(film::TOOLS.iter()).chain(kit::TOOLS.iter()).chain(media::TOOLS.iter()).chain(printframe::TOOLS.iter()).chain(misc::TOOLS.iter()).chain(diagram::TOOLS.iter()).chain(versions::TOOLS.iter()).chain(editref::TOOLS.iter())
}

/// A tool, described once so the list and the dispatch cannot drift apart.
struct Tool {
    name: &'static str,
    description: &'static str,
    /// Argument name, type, and whether it must be given.
    arguments: &'static [(&'static str, &'static str, bool)],
}

const TOOLS: &[Tool] = &[
    Tool {
        name: "open_project",
        description: "Open a Shotlister project. Everything else works on whatever is open.",
        arguments: &[("path", "string", true)],
    },
    Tool {
        name: "summary",
        description: "What this project is: title, how many scenes and shots, and whether shot letters are still free to move.",
        arguments: &[],
    },
    Tool {
        name: "scenes",
        description: "Every scene in story order, with its heading and how many shots it holds. `shoot` (its name, or 2 for Shoot 2) narrows it to one shoot when the project shoots more than once; with one shoot it is ignored.",
        arguments: &[("shoot", "string", false)],
    },
    Tool {
        name: "shots",
        description: "Shots, optionally just one scene's. Scenes are named the way you say them — 34. `shoot` (its name, or 2 for Shoot 2) narrows it to one shoot when the project shoots more than once; with one shoot it is ignored.",
        arguments: &[("scene", "string", false), ("shoot", "string", false)],
    },
    Tool {
        name: "add_scene",
        description: "Add a scene. `int_ext` is INT, EXT or INT/EXT (I/E and INT./EXT. are read the same): a scene that happens in both is a real heading, and filtering to inside or outside finds it under each. On a film the number is yours and is never changed by the app. On a commercial give a title instead — the app numbers it next in line — and video / audio are the two columns of an AV script.",
        arguments: &[
            ("number", "string", false),
            ("title", "string", false),
            ("video", "string", false),
            ("audio", "string", false),
            ("int_ext", "string", false),
            ("location", "string", false),
            ("time_of_day", "string", false),
            ("description", "string", false),
            ("section", "string", false),
        ],
    },
    Tool {
        name: "update_scene",
        description: "Change a scene. Only the fields you give are touched. `int_ext` is INT, EXT or INT/EXT (I/E is read as INT/EXT); a scene that is both counts as inside and as outside. `number` is the script's — change it only when he asks; a number another scene has is refused. `priority` is one term, `pov` and `tags` take several, comma-separated, each from its master list (tags are the one list shots, boards and locations share). `shooting_location` is free words for where it is really shot; the Locations mode's records are set_scene_locations.",
        arguments: &[
            ("scene", "string", true),
            ("number", "string", false),
            ("title", "string", false),
            ("video", "string", false),
            ("audio", "string", false),
            ("int_ext", "string", false),
            ("location", "string", false),
            ("time_of_day", "string", false),
            ("description", "string", false),
            ("notes", "string", false),
            ("section", "string", false),
            ("priority", "string", false),
            ("pov", "string", false),
            ("tags", "string", false),
            ("shooting_location", "string", false),
        ],
    },
    Tool {
        name: "sections",
        description: "The sections (a film says sequences) in order, each with how many scenes it holds. A commercial with several scripts keeps one section per script.",
        arguments: &[],
    },
    Tool {
        name: "add_section",
        description: "Add a section by title. Scenes join it through add_scene or update_scene with section.",
        arguments: &[("title", "string", true)],
    },
    Tool {
        name: "rename_section",
        description: "Rename a section (its scenes come with it), or give it a colour — the colour runs down its scenes on the Mac, the portal and paper. `colour` is one of 2C7A7B 2B6CB0 4C51BF 7B4BC4 A33574 9A6B10 2F7A44 B4531B (or 1–8 for those), or six hex digits.",
        arguments: &[("section", "string", true), ("title", "string", false), ("colour", "string", false)],
    },
    Tool {
        name: "delete_section",
        description: "Take a section away. Its scenes stay and simply leave it.",
        arguments: &[("section", "string", true)],
    },
    Tool {
        name: "move_scene",
        description: "Move a scene in the list to sit just after another scene, or first with after=start. Order only — its number and its shots' letters do not change. To put it in a section, use update_scene with section.",
        arguments: &[("scene", "string", true), ("after", "string", true)],
    },
    Tool {
        name: "sort_scenes",
        description: "Put the scenes in the order of their numbers — for a film whose draft landed out of order.",
        arguments: &[],
    },
    Tool {
        name: "archive_scene",
        description: "Archive a scene (or bring it back with on=false). Archived is the reversible step; delete_scene needs it first.",
        arguments: &[("scene", "string", true), ("on", "boolean", false)],
    },
    Tool {
        name: "delete_scene",
        description: "Delete an archived scene and its shots. Refused unless the scene was archived first.",
        arguments: &[("scene", "string", true)],
    },
    Tool {
        name: "renumber",
        description: "A commercial only: number every scene by its place in the list, 1 to n. Shot IDs follow. A person's decision — say what it costs before asking for it.",
        arguments: &[],
    },
    Tool {
        name: "script",
        description: "A commercial's scripts — the project's own and one per section that has one — each with its layout (plain, or av: Video beside Audio, given as rows), its text, and for each shot that quotes it, the shot number and the words it quotes. An AV script's text has each row's Video then Audio on their own lines; quote words from within one cell.",
        arguments: &[],
    },
    Tool {
        name: "set_script",
        description: "Set a section's script (the project's own when no section is given; the section is made if it does not exist). Give text for a plain script, or rows — [{\"video\": \"…\", \"audio\": \"…\"}] — for an AV script, Video beside Audio. layout (plain or av) alone lays the script's own words out the other way: plain to av makes a row per paragraph, all Audio (a tab-separated table keeps its columns); av to plain puts each row's Video then Audio. Nothing is parsed into beats. Shots already quoting the script keep their tie where their words still appear; the reply says how many kept and how many lost. append=true adds to the end instead of replacing, in the script's own layout.",
        arguments: &[
            ("text", "string", false),
            ("rows", "array", false),
            ("layout", "string", false),
            ("section", "string", false),
            ("append", "boolean", false),
        ],
    },
    Tool {
        name: "tie_shot",
        description: "Tie a shot to a stretch of the script by quoting the words (an exact run of text from the script; the first place they appear). Stretches may overlap and several shots may quote the same one. A shot can quote several stretches far apart: mode=add adds these words to what it already quotes; mode=remove lets just these words go; the default, replace, makes these words all it quotes. An empty text unties everything. Give section when the project has several scripts.",
        arguments: &[
            ("shot", "string", true),
            ("text", "string", true),
            ("section", "string", false),
            ("mode", "string", false),
        ],
    },
    Tool {
        name: "add_shot",
        description: "Add a shot to a scene. It is given the next free letter, so 34 gets 34A, 34B and so on — at the end, or just after the shot `after` names. Takes every field update_shot takes.",
        arguments: SHOT_ARGUMENTS_ADD,
    },
    Tool {
        name: "update_shot",
        description: "Change a shot, named the way you say it — 34A. Only the fields given change; \"\" clears one. Size, lens, movement, support (Equipment), priority are one term each; angle, tags, pov, modifiers (extenders, expanders, diopters: \"Atlas LF Extender 1.6x\") and lens_filters (Filters on screen: \"Tiffen ND .6\") take several, comma-separated. A term not on its master list is added to it — unless the list is locked, and then the reply says it was not set. `camera` names a camera (a new name makes one). `colour` is red, orange, green, blue, purple, pink or hex. `fields` sets the project's own columns: {\"Sound\": \"MOS\"}. `shot_done` marks it Shot (got on set). `master`=true makes it a master other shots can follow; `follows` points it at a master (\"\" cuts it loose, keeping what it showed). `rolls_with` ties it to a shot on another camera at the same moment (\"\" unties). `focal` is where a zoom lens is set, in mm (the Lens says 24-70mm; focal says 35) — read only while the Lens is a zoom; \"\" clears it.",
        arguments: SHOT_ARGUMENTS_UPDATE,
    },
    Tool {
        name: "delete_shot",
        description: "Remove a shot. Undo takes it back on the Mac's connector; the web connector has no undo yet, so be sure it is meant.",
        arguments: &[("shot", "string", true)],
    },
    Tool {
        name: "move_shot",
        description: "Move a shot to another scene. It takes a new letter there and gives up the one it held.",
        arguments: &[("shot", "string", true), ("scene", "string", true)],
    },
    Tool {
        name: "lists",
        description: "The project's master lists — the terms its dropdowns offer: size, angle, movement, lens, modifiers, lens_filters (Filters on screen), support (Equipment on screen), priority, pov, tags. The spec sheet feeds lens, modifiers and lens_filters. Each list in its order, whether it is locked, how many shots (priority and pov: scenes) use each term, any colour a term has been given, and `not_on_list`: terms shots carry that the list does not hold. Give `list` for just one. Read this before changing a list.",
        arguments: &[("list", "string", false)],
    },
    Tool {
        name: "add_to_list",
        description: "Put terms on a master list — one or many, in the order given — without touching any shot. Terms already on it (case ignored) are skipped and named in the reply. They go at the end unless you say: `after` or `before` a term already on the list, `at`=start, or `by_number`=true, which slots each one in among the others by the number in it (a 40mm between the 35mm and the 50mm; a zoom by its wide end) — the way to keep a lens list in focal-length order. A locked list refuses the whole add: say so, and do not unlock it without asking him. All in one change.",
        arguments: &[
            ("list", "string", true),
            ("terms", "array", true),
            ("after", "string", false),
            ("before", "string", false),
            ("at", "string", false),
            ("by_number", "boolean", false),
        ],
    },
    Tool {
        name: "rename_in_list",
        description: "Rename a term on a master list and on every shot or scene that uses it — a typo, or glass that turned out to be something else. Renaming onto a term already on the list folds the two into one. The term keeps its colour. Allowed on a locked list: renaming is not adding. The reply says how many it changed.",
        arguments: &[("list", "string", true), ("from", "string", true), ("to", "string", true)],
    },
    Tool {
        name: "remove_from_list",
        description: "Take terms off a master list. A term shots or scenes are using is cleared from every one of them too (the app does the same), which is losing work — so a term in use is refused, with the shots named, unless `clear_from_shots` is true. Ask him before clearing. Also takes a term that shots carry but the list does not hold (`not_on_list` in lists).",
        arguments: &[
            ("list", "string", true),
            ("terms", "array", true),
            ("clear_from_shots", "boolean", false),
        ],
    },
    Tool {
        name: "order_list",
        description: "Change the order of a master list — the order its dropdown offers; no shot changes. Either `terms`: the terms in the order wanted (each already on the list; any left out keep their order after them), or `sort`: number (by the number in each term — focal length, so 18mm, 25mm, 35mm, with words after) or alphabetical.",
        arguments: &[("list", "string", true), ("terms", "array", false), ("sort", "string", false)],
    },
    Tool {
        name: "lock_list",
        description: "Lock a master list, or unlock it with locked=false. A locked list is finished: nothing new gets on it by any door — a shot's cell, update_shot, add_to_list — while its terms still read, set and clear, and can be renamed, ordered and removed. Locking and unlocking are his decisions: do not unlock a list to get a term past it without asking.",
        arguments: &[("list", "string", true), ("locked", "boolean", false)],
    },
    Tool {
        name: "colour_term",
        description: "Give a term on a master list the colour its chip wears everywhere, or colour=\"\" to hand it back to the automatic one. The app's own eight are 2C7A7B 2B6CB0 4C51BF 7B4BC4 A33574 9A6B10 2F7A44 B4531B; any RRGGBB is kept.",
        arguments: &[("list", "string", true), ("term", "string", true), ("colour", "string", true)],
    },
    Tool {
        name: "read_draft",
        description: "Read a screenplay and say everything about it, changing nothing: every scene with its length in eighths and the page it starts on, who speaks and how often, which scenes the project already has, which are new, and which the project has that this draft no longer mentions — with how many shots would go with each. Hand over the script **as text**; turning a PDF into text is the Mac app's job. Optional `merge_names` (none/regular/hard) and `at_least` tune the cast list the way the app's import screen does.",
        arguments: &[
            ("text", "string", true),
            ("merge_names", "string", false),
            ("at_least", "number", false),
        ],
    },
    Tool {
        name: "apply_draft",
        description: "Take a draft on: create its new scenes, bring the ones that stayed up to date, and remember it as a revision. Each scene keeps how long it is and who speaks in it. **Read it first** — this is the acting half and it is one undoable step. Scenes no longer in the script are left exactly where they are unless `archive_scenes_no_longer_in_the_script` is true, and even then they are archived with their shots, never deleted. `only_scenes` takes scene numbers to limit it; without it, every numbered scene is taken and bare room names are not. `only_cast` limits who is added to the Cast list.",
        arguments: &[
            ("text", "string", true),
            ("revision_name", "string", false),
            ("came_from", "string", false),
            ("dated", "string", false),
            ("only_scenes", "array", false),
            ("only_cast", "array", false),
            ("archive_scenes_no_longer_in_the_script", "boolean", false),
            ("merge_names", "string", false),
            ("at_least", "number", false),
        ],
    },
    Tool {
        name: "cast",
        description: "Who speaks in a screenplay and how often, most-spoken first. Reading a script off a page cannot tell a character from a title card — both are a name in capitals — so a card may appear speaking once; that is what `at_least` is for. `merge_names`: none, regular (folds V.O., O.S., CONT'D), or hard (also folds MRS. HALE with MRS HALE, and OLD FRANK into FRANK).",
        arguments: &[
            ("text", "string", true),
            ("merge_names", "string", false),
            ("at_least", "number", false),
        ],
    },
    Tool {
        name: "revisions",
        description: "Every draft of the script this project has taken in — what it was called, the file it came from, when it landed, and which is the latest.",
        arguments: &[],
    },
    Tool {
        name: "script_pages",
        description: "Lay a screenplay out as it would be printed — 12pt Courier, industry margins, 55 lines a page — and give it back as text, so a scene can be read or quoted as it actually sits on the page. Give `scene` to get one scene's pages and its length in eighths; leave it out for the whole script.",
        arguments: &[("text", "string", true), ("scene", "string", false)],
    },
    Tool {
        name: "detection",
        description: "The rules this project reads scripts by, and a way to change them. A script off a printed page needs tuning — a page prints CONTINUED: at the top of a carried-over scene and it looks exactly like a scene heading. Whatever is set here is remembered, so a film that prints oddly only has to be explained once. Call with no arguments to see the current rules.",
        arguments: &[
            ("must_have_a_number", "boolean", false),
            ("find_rooms", "boolean", false),
            ("ignore_lines_containing", "array", false),
        ],
    },
    Tool {
        name: "undo",
        description: "Take back the last change made through this connector. Says if any of it was left alone because something else had moved on. On the web connector every request starts from the project as saved, so there is nothing to take back yet.",
        arguments: &[],
    },
    Tool {
        name: "attach",
        description: "Pin a file that is already on this Mac to a shot (34A), a scene (34), a location, a reference board or an edit reference (its clip or stills) — a lighting reference, an overhead, a permit, a frame. Give the owner and `path`. **This tool does no network**: fetch the file yourself first (a Notion image, a download) and hand over the local path. `caption` is optional and is what the app shows under it. To hang a file the project already holds somewhere else, copy_attachment.",
        arguments: &[
            ("path", "string", true),
            ("scene", "string", false),
            ("shot", "string", false),
            ("location", "string", false),
            ("board", "string", false),
            ("edit_reference", "string", false),
            ("caption", "string", false),
        ],
    },
    Tool {
        name: "attachments",
        description: "What is pinned to a shot, scene, location, reference board or edit reference (`edit_reference`, by its name: its clip and stills), in order — each with its position (what update_attachment, remove_attachment and copy_attachment call it by), name, kind, caption and, on a shot, which is the lead frame. Files are identified by their contents, so pinning the same picture twice stores it once.",
        arguments: &[("scene", "string", false), ("shot", "string", false), ("location", "string", false), ("board", "string", false), ("edit_reference", "string", false)],
    },
    Tool {
        name: "export",
        description: "Write the list out: csv, xlsx, document or table. Grouped by scene, day or sequence.",
        arguments: &[
            ("format", "string", true),
            ("path", "string", true),
            ("group_by", "string", false),
        ],
    },
];

/// What a shot's cells take — the same list on add_shot and update_shot.
const SHOT_ARGUMENTS_ADD: &[(&str, &str, bool)] = &[
    ("scene", "string", true),
    ("after", "string", false),
    ("title", "string", false),
    ("description", "string", false),
    ("size", "string", false),
    ("angle", "string", false),
    ("movement", "string", false),
    ("lens", "string", false),
    ("focal", "number", false),
    ("modifiers", "string", false),
    ("lens_filters", "string", false),
    ("support", "string", false),
    ("camera", "string", false),
    ("priority", "string", false),
    ("pov", "string", false),
    ("tags", "string", false),
    ("colour", "string", false),
    ("notes", "string", false),
    ("fields", "object", false),
    ("script", "string", false),
    ("master", "boolean", false),
    ("follows", "string", false),
    ("rolls_with", "string", false),
];

const SHOT_ARGUMENTS_UPDATE: &[(&str, &str, bool)] = &[
    ("shot", "string", true),
    ("title", "string", false),
    ("description", "string", false),
    ("size", "string", false),
    ("angle", "string", false),
    ("movement", "string", false),
    ("lens", "string", false),
    ("focal", "number", false),
    ("modifiers", "string", false),
    ("lens_filters", "string", false),
    ("support", "string", false),
    ("camera", "string", false),
    ("priority", "string", false),
    ("pov", "string", false),
    ("tags", "string", false),
    ("colour", "string", false),
    ("notes", "string", false),
    ("fields", "object", false),
    ("script", "string", false),
    ("shot_done", "boolean", false),
    ("master", "boolean", false),
    ("follows", "string", false),
    ("rolls_with", "string", false),
];

fn schema(tool: &Tool) -> Json {
    let properties: Vec<(String, Json)> = tool
        .arguments
        .iter()
        .map(|(name, kind, _)| {
            (
                name.to_string(),
                Json::object(vec![("type", Json::text(*kind))]),
            )
        })
        .collect();
    let required: Vec<Json> = tool
        .arguments
        .iter()
        .filter(|(_, _, required)| *required)
        .map(|(name, _, _)| Json::text(*name))
        .collect();
    Json::object(vec![
        ("type", Json::text("object")),
        ("properties", Json::Object(properties)),
        ("required", Json::Array(required)),
    ])
}

/// The protocol, the tools, and the sentences — over whatever home the films
/// happen to live in.
///
/// **Generic since 2026-09-01**, and only that. A Mac hands it a folder; the
/// worker on his own domain hands it change logs out of the relay's bucket.
/// Everything else here is the same code either way, which is the entire
/// reason it was made generic rather than copied.
pub struct Server<F: Films> {
    films: F,
}

#[cfg(feature = "disk")]
impl Server<crate::films::Disk> {
    pub fn new(device: DeviceId) -> Server<crate::films::Disk> {
        Server::new_on(device, 0)
    }

    /// The same, saying **which machine** the name belongs to, so the engine
    /// can notice when two machines end up writing under one. Ref 186.
    pub fn new_on(device: DeviceId, installation: u64) -> Server<crate::films::Disk> {
        Server::with(crate::films::Disk::new(device, installation))
    }
}

impl<F: Films> Server<F> {
    /// A server over any home for films.
    pub fn with(films: F) -> Server<F> {
        Server { films }
    }

    /// The home itself, for a host that needs a word with it afterwards — the
    /// worker asks its bucket what new change log to write.
    pub fn films(&self) -> &F {
        &self.films
    }

    pub fn films_mut(&mut self) -> &mut F {
        &mut self.films
    }

    /// Handle one message. Returns the reply, or `None` for a notification,
    /// which by definition is not answered.
    pub fn handle(&mut self, message: &str) -> Option<String> {
        let request = json::parse(message)?;
        let id = request.get("id").cloned();
        let method = request.str_field("method");

        // Notifications carry no id and expect no reply.
        if id.is_none() || id.as_ref().map(|v| v.is_null()).unwrap_or(true) {
            return None;
        }
        let id = id.unwrap();

        let result = match method.as_str() {
            "initialize" => Ok(Json::object(vec![
                ("protocolVersion", Json::text(PROTOCOL_VERSION)),
                (
                    "capabilities",
                    Json::object(vec![("tools", Json::object(vec![]))]),
                ),
                (
                    "serverInfo",
                    Json::object(vec![
                        ("name", Json::text("shotlister")),
                        ("version", Json::text(env!("CARGO_PKG_VERSION"))),
                    ]),
                ),
            ])),
            "tools/list" => Ok(Json::object(vec![(
                "tools",
                Json::Array(
                    all_tools()
                        .map(|tool| {
                            Json::object(vec![
                                ("name", Json::text(tool.name)),
                                ("description", Json::text(tool.description)),
                                ("inputSchema", schema(tool)),
                            ])
                        })
                        .collect(),
                ),
            )])),
            "tools/call" => {
                let params = request.get("params").cloned().unwrap_or(Json::Null);
                let name = params.str_field("name");
                let arguments = params.get("arguments").cloned().unwrap_or(Json::Null);
                self.call(&name, &arguments).map(|text| {
                    // **A plan to look at, not markup to read** — where this
                    // host can draw one. The portal draws its own (`hub/src/mcp.js`).
                    let png = (name == "diagram_picture" && text.starts_with("<svg"))
                        .then(|| self.films.rasterize(&text, 1200))
                        .flatten();
                    let content = match png {
                        Some(png) => vec![Json::object(vec![
                            ("type", Json::text("image")),
                            ("data", Json::text(shotlister_engine::export::share::base64(&png))),
                            ("mimeType", Json::text("image/png")),
                        ])],
                        None => vec![Json::object(vec![
                            ("type", Json::text("text")),
                            ("text", Json::text(text)),
                        ])],
                    };
                    Json::object(vec![("content", Json::Array(content))])
                })
            }
            other => Err(format!("Unknown method: {other}")),
        };

        Some(match result {
            Ok(value) => reply(&id, value),
            Err(message) => error(&id, &message),
        })
    }

    /// Run a tool. Errors come back as text rather than exceptions, because a
    /// wrong scene number is a conversation rather than a crash.
    pub fn call(&mut self, name: &str, arguments: &Json) -> Result<String, String> {
        match name {
            "open_project" => {
                self.films.open(&arguments.str_field("path"))?;
                Ok(self.summary()?.encode())
            }
            "summary" => Ok(self.summary()?.encode()),
            "scenes" => {
                let doc = self.films.doc()?;
                let all = tools::scenes(doc);
                Ok(match shootpick::pick(doc, arguments)? {
                    // One shoot's: `tools::scenes` answers one row per scene, in order.
                    Some(pick) => match all {
                        Json::Array(rows) => Json::Array(
                            doc.scenes_in_order().into_iter().zip(rows).filter(|(s, _)| pick.scenes.contains(s)).map(|(_, r)| r).collect(),
                        ),
                        other => other,
                    },
                    None => all,
                }
                .encode())
            }
            "shots" => {
                let reference = arguments.str_field("scene");
                let doc = self.films.doc()?;
                let scene = if reference.is_empty() {
                    None
                } else {
                    Some(tools::find_scene(doc, &reference).ok_or(unknown_scene(&reference))?)
                };
                let mut placements = match scene {
                    Some(scene) => doc.placements_in_scene(scene),
                    None => doc.all_placements(),
                };
                if let Some(pick) = shootpick::pick(doc, arguments)? {
                    placements.retain(|p| pick.placements.contains(p));
                }
                Ok(tools::shots_of(doc, placements).encode())
            }
            "add_scene" => {
                let number = arguments.str_field("number");
                let title = arguments.str_field("title");
                let commercial = self.films.doc()?.kind() == shotlister_engine::FilmKind::Commercial;
                // A film scene is made from its number; a commercial scene
                // from its title, and the engine numbers it. A commercial
                // given a number keeps it — the AV script may well have one.
                if !commercial && number.trim().is_empty() {
                    return Err("A scene needs a number. On a commercial, give a title instead.".to_string());
                }
                if commercial && number.trim().is_empty() && title.trim().is_empty() {
                    return Err("A commercial scene needs a title.".to_string());
                }
                let arguments = arguments.clone();
                self.change("Add scene", move |doc| {
                    let scene = if number.trim().is_empty() {
                        doc.create_scene_titled(title.trim())
                    } else {
                        doc.create_scene(number.trim())
                    };
                    tools::apply_scene_fields(doc, scene, &arguments);
                    tools::apply_section(doc, scene, &arguments);
                    Ok(format!(
                        "Added scene {} — {}.",
                        doc.get(scene).and_then(|r| r.text(shotlister_engine::f::NUMBER)).unwrap_or_default(),
                        doc.scene_heading(scene).unwrap_or_default()
                    ))
                })
            }
            "sections" => Ok(tools::sections(self.films.doc()?).encode()),
            "add_section" => {
                let title = arguments.str_field("title").trim().to_string();
                if title.is_empty() {
                    return Err("A section needs a title.".to_string());
                }
                self.change("Add section", move |doc| {
                    if tools::find_section(doc, &title).is_some() {
                        return Err(format!("There is already a section called {title}."));
                    }
                    doc.create_sequence(&title);
                    Ok(format!("Added section {title}."))
                })
            }
            "rename_section" => {
                let wanted = arguments.str_field("section").trim().to_string();
                let title = arguments.get("title").and_then(|v| v.as_str()).map(|t| t.trim().to_string());
                let colour = match arguments.get("colour").and_then(|v| v.as_str()) {
                    Some(said) => Some(film::section_colour(said)?),
                    None => None,
                };
                if title.is_none() && colour.is_none() {
                    return Err("Say a new title or a colour.".to_string());
                }
                if title.as_deref() == Some("") {
                    return Err("A section needs a title.".to_string());
                }
                self.change("Rename section", move |doc| {
                    let section = tools::find_section(doc, &wanted).ok_or(unknown_section(&wanted))?;
                    let mut said = Vec::new();
                    if let Some(title) = &title {
                        doc.set(section, shotlister_engine::f::TITLE, title.as_str());
                        said.push(format!("{wanted} is {title} now."));
                    }
                    if let Some(hex) = &colour {
                        doc.set(section, shotlister_engine::f::COLOUR, format!("#{hex}").as_str());
                        said.push(format!("Its colour is {hex}."));
                    }
                    Ok(said.join(" "))
                })
            }
            "delete_section" => {
                let wanted = arguments.str_field("section").trim().to_string();
                self.change("Remove section", move |doc| {
                    let section = tools::find_section(doc, &wanted).ok_or(unknown_section(&wanted))?;
                    let left = doc.delete_sequence(section);
                    Ok(format!(
                        "Removed {wanted}; {left} scene{} left it and stay.",
                        if left == 1 { "" } else { "s" }
                    ))
                })
            }
            "move_scene" => {
                let reference = arguments.str_field("scene");
                let after = arguments.str_field("after").trim().to_string();
                self.change("Move scene", move |doc| {
                    let scene = tools::find_scene(doc, &reference).ok_or(unknown_scene(&reference))?;
                    let target = if after.is_empty() || after.eq_ignore_ascii_case("start") {
                        None
                    } else {
                        Some(tools::find_scene(doc, &after).ok_or(unknown_scene(&after))?)
                    };
                    if target == Some(scene) {
                        return Err("A scene cannot go after itself.".to_string());
                    }
                    doc.move_scene_after(scene, target);
                    Ok(match target {
                        None => format!("Scene {reference} is first now."),
                        Some(_) => format!("Scene {reference} now follows scene {after}."),
                    })
                })
            }
            "sort_scenes" => self.change("Sort scenes by number", |doc| {
                doc.sort_scenes_by_number();
                Ok("The scenes are in the order of their numbers.".to_string())
            }),
            "archive_scene" => {
                let reference = arguments.str_field("scene");
                let on = tools::bool_arg(arguments, "on").unwrap_or(true);
                self.change(if on { "Archive scene" } else { "Unarchive scene" }, move |doc| {
                    let scene = tools::find_scene(doc, &reference).ok_or(unknown_scene(&reference))?;
                    doc.archive_scene(scene, on);
                    Ok(if on {
                        format!("Scene {reference} is archived.")
                    } else {
                        format!("Scene {reference} is back.")
                    })
                })
            }
            "delete_scene" => {
                let reference = arguments.str_field("scene");
                self.change("Delete scene", move |doc| {
                    let scene = tools::find_scene(doc, &reference).ok_or(unknown_scene(&reference))?;
                    match doc.delete_archived_scene(scene) {
                        Some(shots) => Ok(format!(
                            "Deleted scene {reference} and its {shots} shot{}.",
                            if shots == 1 { "" } else { "s" }
                        )),
                        None => Err(format!(
                            "Scene {reference} has to be archived before it can be deleted."
                        )),
                    }
                })
            }
            "renumber" => {
                let commercial = self.films.doc()?.kind() == shotlister_engine::FilmKind::Commercial;
                if !commercial {
                    return Err("Scene numbers belong to the script. Only a commercial renumbers.".to_string());
                }
                self.change("Renumber scenes", |doc| {
                    let changed = doc.renumber_in_order();
                    Ok(format!(
                        "Renumbered: {changed} scene{} changed.",
                        if changed == 1 { "" } else { "s" }
                    ))
                })
            }
            "script" => Ok(tools::script(self.films.doc()?).encode()),
            "set_script" => {
                let text = arguments.str_field("text");
                let wanted = arguments.str_field("section").trim().to_string();
                let append = tools::bool_arg(arguments, "append").unwrap_or(false);
                let layout = arguments.str_field("layout").trim().to_ascii_lowercase();
                if !layout.is_empty() && layout != "plain" && layout != "av" {
                    return Err("A layout is plain or av.".to_string());
                }
                let rows: Option<Vec<(String, String)>> = arguments.get("rows").and_then(|r| r.as_array()).map(|rows| {
                    rows.iter()
                        .map(|row| {
                            let cell = |k: &str| row.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();
                            (cell("video"), cell("audio"))
                        })
                        .collect()
                });
                if text.is_empty() && rows.is_none() && layout.is_empty() {
                    return Err("Give text, rows or a layout.".to_string());
                }
                self.change("Edit script", move |doc| {
                    let section = if wanted.is_empty() {
                        None
                    } else {
                        Some(tools::find_section(doc, &wanted).unwrap_or_else(|| doc.create_sequence(&wanted)))
                    };
                    let (kept, lost) = match (&rows, text.is_empty()) {
                        // Only a layout: the script's own words, laid out the other way.
                        (None, true) => doc.set_script_av(section, layout == "av"),
                        _ => {
                            let incoming = match &rows {
                                Some(rows) => shotlister_engine::quoting::av_text(rows),
                                None => text.clone(),
                            };
                            let av = match layout.as_str() {
                                "av" => Some(true),
                                "plain" => Some(false),
                                _ => None,
                            };
                            if append {
                                doc.add_to_script(section, &incoming, av)
                            } else {
                                let whole = match av {
                                    Some(true) => shotlister_engine::quoting::av_from_plain(&incoming),
                                    Some(false) => shotlister_engine::quoting::plain_from_av(&incoming),
                                    None => incoming,
                                };
                                doc.set_av_script(section, &whole)
                            }
                        }
                    };
                    let mut said = format!("Script set{}.", if wanted.is_empty() { String::new() } else { format!(" for {wanted}") });
                    if kept + lost > 0 {
                        said.push_str(&format!(" {kept} tie{} kept", if kept == 1 { "" } else { "s" }));
                        if lost > 0 {
                            said.push_str(&format!(", {lost} lost — the words are no longer there"));
                        }
                        said.push('.');
                    }
                    Ok(said)
                })
            }
            "tie_shot" => {
                let reference = arguments.str_field("shot");
                let arguments = arguments.clone();
                self.change("Tie shot", move |doc| {
                    let placement =
                        tools::find_placement(doc, &reference).ok_or(unknown_shot(&reference))?;
                    let shot = tools::shot_of(doc, placement).ok_or(unknown_shot(&reference))?;
                    tools::apply_quote(doc, shot, &arguments)?;
                    Ok(match doc.quote_of(shot) {
                        Some(_) => format!("{reference} quotes: {}", doc.shot_excerpt(shot)),
                        None => format!("{reference} quotes nothing."),
                    })
                })
            }
            "update_scene" => {
                let reference = arguments.str_field("scene");
                let arguments = arguments.clone();
                self.change("Change scene", move |doc| {
                    let scene =
                        tools::find_scene(doc, &reference).ok_or(unknown_scene(&reference))?;
                    if let Some(number) = arguments.get("number").and_then(|v| v.as_str()) {
                        film::check_scene_number(doc, scene, number)?;
                        doc.set(scene, shotlister_engine::f::NUMBER, number.trim());
                    }
                    tools::apply_scene_fields(doc, scene, &arguments);
                    tools::apply_section(doc, scene, &arguments);
                    let kept_off = film::apply_scene_lists(doc, scene, &arguments);
                    let number = doc.get(scene).and_then(|r| r.text(shotlister_engine::f::NUMBER)).unwrap_or_default().to_string();
                    Ok(with_notes(
                        format!("Scene {number} is now {}.", doc.scene_heading(scene).unwrap_or_default()),
                        &kept_off,
                    ))
                })
            }
            "add_shot" => {
                let reference = arguments.str_field("scene");
                let arguments = arguments.clone();
                self.change("Add shot", move |doc| {
                    let scene =
                        tools::find_scene(doc, &reference).ok_or(unknown_scene(&reference))?;
                    let after = match arguments.get("after").and_then(|v| v.as_str()).map(str::trim) {
                        None | Some("") => None,
                        Some(said) => {
                            let placement = tools::find_placement(doc, said).ok_or(unknown_shot(said))?;
                            if doc.get(placement).and_then(|r| r.ref_id(shotlister_engine::f::SCENE)) != Some(scene) {
                                return Err(format!("{said} is not in scene {reference}."));
                            }
                            Some(placement)
                        }
                    };
                    let (shot, placement) = doc.add_shot_to_scene_after(scene, after);
                    let kept_off = tools::apply_shot_fields(doc, shot, &arguments)?;
                    tools::apply_quote(doc, shot, &arguments)?;
                    Ok(with_notes(
                        format!("Added {}.", doc.display_number(placement).unwrap_or_default()),
                        &kept_off,
                    ))
                })
            }
            "update_shot" => {
                let reference = arguments.str_field("shot");
                let arguments = arguments.clone();
                self.change("Change shot", move |doc| {
                    let placement =
                        tools::find_placement(doc, &reference).ok_or(unknown_shot(&reference))?;
                    let shot = tools::shot_of(doc, placement).ok_or(unknown_shot(&reference))?;
                    let kept_off = tools::apply_shot_fields(doc, shot, &arguments)?;
                    tools::apply_quote(doc, shot, &arguments)?;
                    Ok(with_notes(format!("Updated {reference}."), &kept_off))
                })
            }
            "delete_shot" => {
                let reference = arguments.str_field("shot");
                self.change("Delete shot", move |doc| {
                    let placement =
                        tools::find_placement(doc, &reference).ok_or(unknown_shot(&reference))?;
                    doc.delete(placement);
                    Ok(format!("Deleted {reference}."))
                })
            }
            "move_shot" => {
                let shot = arguments.str_field("shot");
                let scene = arguments.str_field("scene");
                self.change("Move shot", move |doc| {
                    let placement =
                        tools::find_placement(doc, &shot).ok_or(unknown_shot(&shot))?;
                    let target = tools::find_scene(doc, &scene).ok_or(unknown_scene(&scene))?;
                    let number = doc
                        .move_placement_to_scene(placement, target)
                        .unwrap_or_default();
                    Ok(format!("{shot} is now {number}."))
                })
            }
            "lists" => {
                let wanted = arguments.str_field("list");
                let doc = self.films.doc()?;
                if wanted.trim().is_empty() {
                    Ok(tools::lists(doc).encode())
                } else {
                    Ok(tools::list(doc, &tools::list_named(doc, &wanted)?).encode())
                }
            }
            "add_to_list" => {
                use shotlister_engine::vocab::ListPlace;
                let name = tools::list_named(self.films.doc()?, &arguments.str_field("list"))?;
                let terms = tools::list_arg(arguments, "terms").unwrap_or_default();
                if terms.iter().all(|t| t.trim().is_empty()) {
                    return Err("Say which terms to add: terms.".to_string());
                }
                let after = arguments.str_field("after");
                let before = arguments.str_field("before");
                let at = arguments.str_field("at").trim().to_ascii_lowercase();
                let by_number = tools::bool_arg(arguments, "by_number").unwrap_or(false);
                let asked = [!after.trim().is_empty(), !before.trim().is_empty(), !at.is_empty() && at != "end", by_number]
                    .iter()
                    .filter(|x| **x)
                    .count();
                if asked > 1 {
                    return Err("Say one place for them: after, before, at or by_number.".to_string());
                }
                let place = if !after.trim().is_empty() {
                    ListPlace::After(after)
                } else if !before.trim().is_empty() {
                    ListPlace::Before(before)
                } else if by_number {
                    ListPlace::ByNumber
                } else {
                    match at.as_str() {
                        "" | "end" => ListPlace::End,
                        "start" => ListPlace::Start,
                        other => return Err(format!("at is start or end, not {other}.")),
                    }
                };
                self.change("Add to list", move |doc| {
                    let borrowed: Vec<&str> = terms.iter().map(|t| t.as_str()).collect();
                    let said = doc
                        .add_to_vocabulary(&name, &borrowed, &place)
                        .map_err(|r| tools::list_refusal(doc, &name, r))?;
                    let title = tools::list_title(doc, &name).to_lowercase();
                    let mut out = if said.added.is_empty() {
                        format!("Nothing new for the {title} list.")
                    } else {
                        format!("Added to the {title} list: {}.", said.added.join(", "))
                    };
                    if !said.already.is_empty() {
                        out.push_str(&format!(" Already on it: {}.", said.already.join(", ")));
                    }
                    out.push_str(&format!(" The list: {}.", doc.vocabulary(&name).join(", ")));
                    Ok(out)
                })
            }
            "rename_in_list" => {
                let name = tools::list_named(self.films.doc()?, &arguments.str_field("list"))?;
                let from = arguments.str_field("from").trim().to_string();
                let to = arguments.str_field("to").trim().to_string();
                if from.is_empty() || to.is_empty() {
                    return Err("Say from and to.".to_string());
                }
                if from == to {
                    return Err(format!("{from} is already called that."));
                }
                self.change("Rename value", move |doc| {
                    let title = tools::list_title(doc, &name).to_lowercase();
                    if !doc.vocabulary_contains(&name, &from) && doc.carrying(&name, &from).is_empty() {
                        return Err(format!("{from} is not on the {title} list, and no shot carries it."));
                    }
                    let carriers = tools::carriers_named(doc, &name, &from);
                    let folded = doc.vocabulary_contains(&name, &to) && !from.eq_ignore_ascii_case(&to);
                    if from.eq_ignore_ascii_case(&to) {
                        // A change of case only, which the engine reads as no
                        // change at all — so it goes by way of a name nothing
                        // else can hold, inside this one undo step.
                        let passing = "\u{1}renaming";
                        doc.rename_vocabulary_value(&name, &from, passing);
                        doc.rename_vocabulary_value(&name, passing, &to);
                    } else {
                        doc.rename_vocabulary_value(&name, &from, &to);
                    }
                    Ok(format!(
                        "{from} is {to} on the {title} list{} and on {}.",
                        if folded { " (it was already there, so the two are one now)" } else { "" },
                        tools::counted(&carriers)
                    ))
                })
            }
            "remove_from_list" => {
                let name = tools::list_named(self.films.doc()?, &arguments.str_field("list"))?;
                let terms = tools::list_arg(arguments, "terms").unwrap_or_default();
                let clear = tools::bool_arg(arguments, "clear_from_shots").unwrap_or(false);
                if terms.iter().all(|t| t.trim().is_empty()) {
                    return Err("Say which terms to take off: terms.".to_string());
                }
                self.change("Remove value", move |doc| {
                    let title = tools::list_title(doc, &name).to_lowercase();
                    let mut in_use = Vec::new();
                    let mut unknown = Vec::new();
                    for term in terms.iter().map(|t| t.trim()).filter(|t| !t.is_empty()) {
                        let carriers = tools::carriers_named(doc, &name, term);
                        if !doc.vocabulary_contains(&name, term) && carriers.is_empty() {
                            unknown.push(term.to_string());
                        } else if !carriers.is_empty() {
                            in_use.push(format!("{term} is on {}", tools::counted(&carriers)));
                        }
                    }
                    if !unknown.is_empty() {
                        return Err(format!(
                            "Not on the {title} list, and no shot carries: {}. Nothing was removed.",
                            unknown.join(", ")
                        ));
                    }
                    if !in_use.is_empty() && !clear {
                        return Err(format!(
                            "Nothing was removed. {}. Taking a term off clears it from those too — \
                             ask him, then call again with clear_from_shots=true.",
                            in_use.join("; ")
                        ));
                    }
                    let mut cleared: Vec<String> = Vec::new();
                    let mut gone = Vec::new();
                    for term in terms.iter().map(|t| t.trim()).filter(|t| !t.is_empty()) {
                        for carrier in tools::carriers_named(doc, &name, term) {
                            if !cleared.contains(&carrier) {
                                cleared.push(carrier);
                            }
                        }
                        doc.remove_vocabulary_value(&name, term);
                        gone.push(term.to_string());
                    }
                    let mut out = format!("Took {} off the {title} list.", gone.join(", "));
                    if !cleared.is_empty() {
                        out.push_str(&format!(" Cleared from {}.", tools::counted(&cleared)));
                    }
                    Ok(out)
                })
            }
            "order_list" => {
                use shotlister_engine::vocab::ListSort;
                let name = tools::list_named(self.films.doc()?, &arguments.str_field("list"))?;
                let terms = tools::list_arg(arguments, "terms").unwrap_or_default();
                let sort = arguments.str_field("sort").trim().to_ascii_lowercase();
                let named = terms.iter().any(|t| !t.trim().is_empty());
                if named == !sort.is_empty() {
                    return Err("Give either terms (the order you want) or sort (number or alphabetical).".to_string());
                }
                let by = match sort.as_str() {
                    "" => None,
                    "number" | "numbers" | "by_number" | "focal" | "focal length" => Some(ListSort::ByNumber),
                    "alphabetical" | "alpha" | "a-z" | "name" => Some(ListSort::Alphabetical),
                    other => return Err(format!("sort is number or alphabetical, not {other}.")),
                };
                self.change("Order list", move |doc| {
                    let title = tools::list_title(doc, &name).to_lowercase();
                    let mut out = String::new();
                    match by {
                        Some(by) => doc.sort_vocabulary(&name, by).map_err(|r| tools::list_refusal(doc, &name, r))?,
                        None => {
                            let borrowed: Vec<&str> = terms.iter().map(|t| t.as_str()).collect();
                            let rest = doc
                                .order_vocabulary(&name, &borrowed)
                                .map_err(|r| tools::list_refusal(doc, &name, r))?;
                            if !rest.is_empty() {
                                out = format!(" Not named, so kept after in their order: {}.", rest.join(", "));
                            }
                        }
                    }
                    Ok(format!("The {title} list: {}.{out}", doc.vocabulary(&name).join(", ")))
                })
            }
            "lock_list" => {
                let name = tools::list_named(self.films.doc()?, &arguments.str_field("list"))?;
                let on = tools::bool_arg(arguments, "locked").unwrap_or(true);
                self.change(if on { "Lock list" } else { "Unlock list" }, move |doc| {
                    doc.set_vocabulary_locked(&name, on);
                    let title = tools::list_title(doc, &name).to_lowercase();
                    Ok(if on {
                        format!("The {title} list is locked: nothing new gets on it.")
                    } else {
                        format!("The {title} list is open: a new term typed on a shot joins it again.")
                    })
                })
            }
            "colour_term" => {
                let name = tools::list_named(self.films.doc()?, &arguments.str_field("list"))?;
                let term = arguments.str_field("term").trim().to_string();
                let hex = arguments.str_field("colour").trim().trim_start_matches('#').to_uppercase();
                if !hex.is_empty() && (hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit())) {
                    return Err(format!("A colour is six hex digits, like 2B6CB0 — not {hex}."));
                }
                self.change("Colour term", move |doc| {
                    let title = tools::list_title(doc, &name).to_lowercase();
                    let own = doc
                        .vocabulary(&name)
                        .into_iter()
                        .find(|t| t.eq_ignore_ascii_case(&term))
                        .ok_or_else(|| format!("{term} is not on the {title} list."))?;
                    doc.set_term_colour(&name, &own, &hex);
                    Ok(if hex.is_empty() {
                        format!("{own} wears its automatic colour again.")
                    } else {
                        format!("{own} is {hex} now.")
                    })
                })
            }
            "read_draft" => {
                let text = arguments.str_field("text");
                let options = tools::cast_options(arguments);
                let doc = self.films.doc()?;
                Ok(tools::read_screenplay(doc, &text, options).encode())
            }
            "apply_draft" => {
                let text = arguments.str_field("text");
                let options = tools::cast_options(arguments);
                let archive =
                    tools::bool_arg(arguments, "archive_scenes_no_longer_in_the_script")
                        .unwrap_or(false);
                let name = {
                    let given = arguments.str_field("revision_name");
                    if given.is_empty() {
                        "Revision".to_string()
                    } else {
                        given
                    }
                };
                let filename = arguments.str_field("came_from");
                let dated = {
                    let given = arguments.str_field("dated");
                    if given.trim().is_empty() { tools::iso_now() } else { given }
                };
                let only: Vec<String> =
                    tools::list_arg(arguments, "only_scenes").unwrap_or_default();
                let named_cast: Option<Vec<String>> = tools::list_arg(arguments, "only_cast");
                // **The text kept beside the media**, as the app keeps it, so
                // the Mac and the phone can lay this draft out and a tie can
                // point into it (Ref 1553). A host with no files keeps none,
                // and the draft is a record without its text, as before.
                let kept_hash = {
                    let hash = shotlister_engine::sha256(text.as_bytes()).to_hex();
                    match self.films.keep_media(&hash, "txt", text.as_bytes()) {
                        Ok(()) => hash,
                        Err(_) => String::new(),
                    }
                };

                self.change("Take in a new draft", move |doc| {
                    let detection = doc.detection();
                    let screenplay =
                        shotlister_engine::screenplay::read_with(&text, &detection);

                    // Rooms are offered, never taken by default — the rule that
                    // finds one cannot tell BATHROOM. from A LOUD BANG.
                    let scenes: Vec<usize> = screenplay
                        .scenes
                        .iter()
                        .enumerate()
                        .filter(|(_, scene)| scene.accepted)
                        .filter(|(_, scene)| {
                            only.is_empty()
                                || only.iter().any(|wanted| {
                                    shotlister_engine::natural::same(wanted, &scene.label)
                                })
                        })
                        .map(|(at, _)| at)
                        .collect();

                    let found = shotlister_engine::cast::read(&screenplay, options);
                    let cast: Vec<String> = match &named_cast {
                        Some(named) => named.clone(),
                        None => found.iter().map(|m| m.name.clone()).collect(),
                    };

                    let taking = shotlister_engine::Taking {
                        scenes,
                        cast,
                        archive_omitted: archive,
                        // A scene that moved is offered, never assumed, and
                        // over here there is nobody to offer it to — so no
                        // scene is carried across. The new number gets a new
                        // scene and the old one keeps its shots, which is the
                        // reportable, never-destroy answer.
                        moves: Vec::new(),
                        cast_options: options,
                    };

                    let revision = shotlister_engine::Revision {
                        id: shotlister_engine::Id::new(),
                        name,
                        filename,
                        imported_at: dated,
                        hash: kept_hash,
                    };

                    let plan = doc.take_revision(&screenplay, &taking, &revision);
                    let mut said = plan.sentences().join("\n");

                    // Over here there is no list on screen beside the sentence,
                    // so the sentence has to name them. A scene somebody has to
                    // decide about is no use as a number they cannot see.
                    let named = |scenes: &[(String, usize)]| {
                        scenes
                            .iter()
                            .map(|(number, shots)| {
                                format!(
                                    "{number} ({shots} shot{})",
                                    if *shots == 1 { "" } else { "s" }
                                )
                            })
                            .collect::<Vec<_>>()
                            .join(", ")
                    };
                    if !plan.left_alone.is_empty() {
                        said.push_str(&format!(
                            "\n\nLeft exactly where they are, shots and all: {}. \
                             A script revision is not authority to throw work away — \
                             archive them yourself if that is what you mean.",
                            named(&plan.left_alone)
                        ));
                    }
                    if !plan.archived.is_empty() {
                        said.push_str(&format!(
                            "\n\nArchived, with every shot still on them: {}. \
                             Nothing was deleted and they come back with one click.",
                            named(&plan.archived)
                        ));
                    }
                    Ok(said)
                })
            }
            "cast" => {
                let text = arguments.str_field("text");
                let options = tools::cast_options(arguments);
                let detection = self.films.doc()?.detection();
                let screenplay = shotlister_engine::screenplay::read_with(&text, &detection);
                let found = shotlister_engine::cast::read(&screenplay, options);
                Ok(Json::Array(
                    found
                        .into_iter()
                        .map(|member| {
                            Json::object(vec![
                                ("name", Json::text(member.name)),
                                ("reads_as", Json::text(member.display)),
                                ("speeches", Json::Number(member.speeches as f64)),
                                (
                                    "spelled",
                                    Json::Array(member.aliases.into_iter().map(Json::text).collect()),
                                ),
                            ])
                        })
                        .collect(),
                )
                .encode())
            }
            "revisions" => {
                let doc = self.films.doc()?;
                let latest = doc.latest_revision().map(|r| r.id);
                Ok(Json::Array(
                    doc.revisions()
                        .into_iter()
                        .map(|revision| {
                            Json::object(vec![
                                ("name", Json::text(revision.name)),
                                ("came_from", Json::text(revision.filename)),
                                ("dated", Json::text(revision.imported_at)),
                                ("latest", Json::Bool(Some(revision.id) == latest)),
                            ])
                        })
                        .collect(),
                )
                .encode())
            }
            "script_pages" => {
                let text = arguments.str_field("text");
                let wanted = arguments.str_field("scene");
                let detection = self.films.doc()?.detection();
                let screenplay = shotlister_engine::screenplay::read_with(&text, &detection);
                let laid = shotlister_engine::lay_out(&screenplay);

                let only = if wanted.is_empty() {
                    None
                } else {
                    screenplay.scenes.iter().position(|scene| {
                        shotlister_engine::natural::same(&scene.label, &wanted)
                    })
                };
                if !wanted.is_empty() && only.is_none() {
                    return Err(format!("This draft has no scene {wanted}."));
                }

                // Set back out as a page reads, so it can be quoted.
                let mut out = String::new();
                for page in &laid.pages {
                    let shown: Vec<&shotlister_engine::pages::Line> = page
                        .lines
                        .iter()
                        .filter(|line| only.is_none() || line.scene == only)
                        .collect();
                    if shown.is_empty() {
                        continue;
                    }
                    out.push_str(&format!("--- page {} ---\n", page.number));
                    let mut row = shown[0].row;
                    for line in shown {
                        while row < line.row {
                            out.push('\n');
                            row += 1;
                        }
                        out.push_str(&" ".repeat(line.indent));
                        out.push_str(&line.text);
                        out.push('\n');
                        row += 1;
                    }
                }
                if let Some(at) = only {
                    let extent = laid.extent_of(at);
                    out.push_str(&format!(
                        "\nScene {} is {} of a page, starting on page {}.\n",
                        screenplay.scenes[at].label,
                        extent.map(|e| e.length()).unwrap_or_default(),
                        extent.map(|e| e.starts_on).unwrap_or(0),
                    ));
                }
                Ok(out)
            }
            "detection" => {
                let mut wanted = self.films.doc()?.detection();
                let mut changed = false;
                if let Some(on) = tools::bool_arg(arguments, "must_have_a_number") {
                    wanted.must_have_a_number = on;
                    changed = true;
                }
                if let Some(on) = tools::bool_arg(arguments, "find_rooms") {
                    wanted.find_sub_slugs = on;
                    changed = true;
                }
                if let Some(words) = tools::list_arg(arguments, "ignore_lines_containing") {
                    wanted.never_contains = words;
                    changed = true;
                }
                if changed {
                    self.films.doc_mut()?.set_detection(&wanted);
                    self.films.save()?;
                }
                let now = self.films.doc()?.detection();
                Ok(Json::object(vec![
                    ("must_have_a_number", Json::Bool(now.must_have_a_number)),
                    (
                        "ignore_repeated_numbers",
                        Json::Bool(now.ignore_duplicate_numbers),
                    ),
                    ("find_rooms", Json::Bool(now.find_sub_slugs)),
                    (
                        "ignore_lines_containing",
                        Json::Array(now.never_contains.into_iter().map(Json::text).collect()),
                    ),
                ])
                .encode())
            }
            "undo" => {
                let outcome = self.films.doc_mut()?.undo();
                self.films.save()?;
                Ok(match outcome {
                    None => "There is nothing to undo.".to_string(),
                    Some(outcome) if outcome.complete() => {
                        format!("Undid {}.", outcome.label)
                    }
                    Some(outcome) => format!(
                        "Undid {}. {} field(s) were left alone because they had changed since.",
                        outcome.label, outcome.skipped
                    ),
                })
            }
            "attach" => {
                let path = arguments.str_field("path");
                let caption = arguments.str_field("caption");
                {
                    let doc = self.films.doc()?;
                    media::owner_of(doc, arguments, "")?.ok_or("Say which shot, scene, location, board or edit reference this belongs to.")?;
                }
                if self.films.read_only() {
                    return Err("This project is open for reading only.".to_string());
                }
                let bytes = self.films.read_bytes(&path)?;
                let name = path
                    .rsplit('/')
                    .next()
                    .filter(|n| !n.is_empty())
                    .unwrap_or("attachment")
                    .to_string();
                let hash = shotlister_engine::sha256(&bytes);
                let hex = hash.to_hex();
                let ext = name
                    .rsplit_once('.')
                    .map(|(_, e)| e.to_lowercase())
                    .unwrap_or_else(|| "bin".to_string());
                self.films.keep_media(&hex, &ext, &bytes)?;
                let size = bytes.len() as u64;
                let doc = self.films.doc_mut()?;
                let (owner, whose) = media::owner_of(doc, arguments, "")?.ok_or("Say which shot, scene, location, board or edit reference this belongs to.")?;
                let kind = shotlister_engine::media::MediaKind::guess_from_name(&name);
                let stored = doc.add_media(hash, kind, 0, 0, size, &name);
                doc.attach_media(owner, stored, &caption);
                self.films.save()?;
                Ok(Json::text(format!("Pinned {name} to {whose}.")).encode())
            }
            "attachments" => {
                let doc = self.films.doc()?;
                let (owner, _) = media::owner_of(doc, arguments, "")?.ok_or("Say whose: shot, scene, location, board or edit_reference.")?;
                Ok(tools::attachments(doc, owner).encode())
            }
            "export" => {
                let format = arguments.str_field("format");
                let path = arguments.str_field("path");
                let group = tools::grouping(&arguments.str_field("group_by"));
                let (kind, bytes) = tools::export(self.films.doc()?, &format, group)?;
                self.films.write_bytes(&path, &bytes)?;
                Ok(format!("Wrote {kind} to {path}."))
            }
            other => {
                if let Some(done) = self.schedule_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.place_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.shot_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.film_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.kit_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.media_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.print_frame_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.misc_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.diagram_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.version_tools(other, arguments) {
                    return done;
                }
                if let Some(done) = self.editref_tools(other, arguments) {
                    return done;
                }
                // Unlisted: the portal's `export` asks these (`hub/src/exporting.js`).
                if let Some(done) = self.export_tools(other, arguments) {
                    return done;
                }
                Err(format!("Unknown tool: {other}"))
            }
        }
    }

    /// What this film is, in the shape `summary` and `open_project` both answer.
    fn summary(&self) -> Result<Json, String> {
        let doc = self.films.doc()?;
        let mut said = tools::summary(doc, &self.films.title(), &self.films.whereabouts(), self.films.read_only());
        // **Its shoots, when it has more than one** — what `shoot` takes.
        let shoots = shootpick::shoot_names(doc);
        if let (Json::Object(pairs), false) = (&mut said, shoots.is_empty()) {
            pairs.push(("shoots".to_string(), Json::Array(shoots.into_iter().map(Json::text).collect())));
        }
        Ok(said)
    }

    /// Run a change as one undoable action and save it.
    ///
    /// Saving every time is deliberate: there is no window open here, so an
    /// unsaved edit would simply be lost when the conversation ends.
    fn change<Body>(&mut self, label: &str, body: Body) -> Result<String, String>
    where
        Body: FnOnce(&mut shotlister_engine::Doc) -> Result<String, String>,
    {
        // Asked first so that a film nobody opened is told it was never opened,
        // rather than told it may not be changed — which is true of a film that
        // does not exist and is not the useful half of the truth.
        self.films.doc()?;
        if self.films.read_only() {
            return Err("This project is open for reading only.".to_string());
        }
        let message = self.films.doc_mut()?.transact(label, body)?;
        self.films.save()?;
        Ok(message)
    }
}

/// A reply, with anything that did not land said after it.
fn with_notes(said: String, notes: &[String]) -> String {
    if notes.is_empty() {
        said
    } else {
        format!("{said} {}", notes.join(" "))
    }
}

fn unknown_scene(reference: &str) -> String {
    format!("There is no scene {reference} in this project.")
}

fn unknown_section(title: &str) -> String {
    format!("There is no section called {title} in this project.")
}

fn unknown_shot(reference: &str) -> String {
    format!("There is no shot {reference} in this project.")
}

fn reply(id: &Json, result: Json) -> String {
    Json::object(vec![
        ("jsonrpc", Json::text("2.0")),
        ("id", id.clone()),
        ("result", result),
    ])
    .encode()
}

fn error(id: &Json, message: &str) -> String {
    Json::object(vec![
        ("jsonrpc", Json::text("2.0")),
        ("id", id.clone()),
        (
            "error",
            Json::object(vec![
                ("code", Json::Number(-32000.0)),
                ("message", Json::text(message)),
            ]),
        ),
    ])
    .encode()
}


fn gone_list(diff: &shotlister_engine::ScriptDiff) -> String {
    diff.gone
        .iter()
        .map(|gone| {
            format!(
                "  scene {} — {} ({} shot{})",
                gone.number,
                gone.heading,
                gone.shots,
                if gone.shots == 1 { "" } else { "s" }
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// **What a file is being pinned to**, from `shot`, `scene`, `location`,
/// `board` or `edit_reference` — for the worker's own attach door
/// (`mcpweb`'s `attach`, the portal's `add_picture`), which brings its bytes
/// in by another road and must name the owner exactly as these tools do.
pub fn attachment_owner(doc: &shotlister_engine::Doc, arguments: &Json) -> Result<Option<(shotlister_engine::Id, String)>, String> {
    media::owner_of(doc, arguments, "")
}
