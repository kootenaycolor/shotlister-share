//! **Diagram mode**: everything the overhead plan does, for Claude.
//!
//! His ask, 2026-09-30: *"build out a mcp for diagram mode."* Until then the
//! connector could read a plan, make one edit, list the library, copy a plan
//! and set a plan setting everywhere — and nothing else. Every diagram
//! command the Mac's Diagram mode calls was set against that list; what a
//! person does there and a chat could not is here now: a picture of the plan
//! to look at, which scenes have one, the nine favorites, the cast the people
//! tool offers, a scanned room, a picture under the plan, and a guide to
//! every kind, edit and setting so an AI does not draw by guessing.
//!
//! What only a screen does — hit-testing, snapping, a marquee, a drag's
//! preview — has no tool, because a chat never points.

use shotlister_engine::diagram::{self, copy, favorites, render, svg, Kind};
use shotlister_engine::json as ejson;
use shotlister_engine::{f, Doc, Id};

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "diagram_guide",
        description: "Read this before drawing on a diagram: every kind of thing a plan holds and the fields each takes, every edit edit_diagram understands, every plan setting, and how steps, beats, aims and rigging work. Plain text.",
        arguments: &[],
    },
    Tool {
        name: "diagram",
        description: "A scene's overhead diagram: every wall, set piece, camera, person, light, arrow and word on it, as JSON, with the plan's settings. Metres, y growing down the page; angles in degrees clockwise from east (0 faces right, 90 faces down). A camera's `shot` is the shot it stands for; `name` is that shot's number. Each piece carries its `layer`: \"set\" (the room laid once: walls, doors, windows, openings, the street, set pieces, buildings, areas, stairs, a floor plan picture or scan to trace) or \"plot\" (lamps, frames, grip, cameras, cast, words, arrows, connectors, track, rulers, drawn lines and shapes; camera support and electric set pieces too). The app works one layer at a time, the other greyed and locked; the layer is the kind, except words and arrows, which stay in the view they were put down in (`in_set`, true for Set; none means Plot). Each lamp carries its `lamp_name` (its label as typed; empty until one is typed), `legend_key` and `label_lines` (the two lines its label writes); `legend` lists each symbol-and-Name line with its lamps, `sheet` the page it prints on and `gear` the gear it counts. diagram_picture shows it.",
        arguments: &[("scene", "string", true)],
    },
    Tool {
        name: "diagram_picture",
        description: "A picture of a scene's diagram, drawn the way the app draws it — look at it after editing to check the plan reads right. `beat` is kept for old plans and changes nothing: a plot draws no steps or beats. `width` in pixels, 1200 if not given. `paper` true draws the whole SHEET exactly as it prints and as the app shows it: the title (scene, film and day), north, the plan, and the band of Notes, Legend and Shots.",
        arguments: &[("scene", "string", true), ("beat", "number", false), ("width", "number", false), ("paper", "boolean", false)],
    },
    Tool {
        name: "diagram_scenes",
        description: "Which scenes have a diagram, in script order, with how many things are on each and how many are cameras, people and lights.",
        arguments: &[],
    },
    Tool {
        name: "edit_diagram",
        description: "Change a scene's diagram with one edit, taken back with one undo. `op` is an object such as {\"op\":\"add\",\"els\":[{\"kind\":\"wall\",\"points\":[[0,0],[4,0],[4,3],[0,3]],\"closed\":true}]}, {\"op\":\"update\",\"id\":\"..\",\"set\":{..}}, {\"op\":\"remove\",\"ids\":[..]}, move, rotate, flip, order, duplicate, swap, group, ungroup, align, distribute, name_lamp (a lamp's Name), name_piece (any piece's label, as typed), send_layer (Send to Set / Plot), share_label, own_label, legend, step_add, step_set, step_remove (a piece's lettered steps, each on a beat), beat, unbeat, settings (sheet_notes, paper, orientation, legend, notes, scale_bar, fabric, measures among them), clear, the wall edits (wall_corner, wall_insert, wall_extend, wall_break, wall_round, wall_smooth, wall_handle, path_as, wall_remove_corner, wall_length, wall_join), or batch {\"ops\":[..]} for several as one. A camera added with \"new_shot\":true makes its own shot. diagram_guide has every kind, field and edit.",
        arguments: &[("scene", "string", true), ("op", "object", true)],
    },
    Tool {
        name: "diagram_library",
        description: "Every drawing a set piece, light or bit of grip on a diagram can be — id, name, group, the size it arrives at in metres, and where the app's library shows it: `lib` (light = lamps; grip = frames, rags, flags, nets, boards, rolls, stands, rigging, lifts; set = rooms, furniture, vehicles, outdoors, props, camera support, electric), `kind` (its section there), `maker`, and `aka` (what crews call it). Lights carry beam, reach and colour temperature; `frames` lists a frame's materials, frame types and grids. Give `library`, `kind`, `maker` or `search` to get just the matching pieces — search knows nicknames: \"m18\", \"4k par\", \"kino\", \"china ball\", \"c-stand\". An id goes in `sym`.",
        arguments: &[("library", "string", false), ("kind", "string", false), ("maker", "string", false), ("search", "string", false)],
    },
    Tool {
        name: "set_frame",
        description: "Dress a frame (a light-kind piece with sym \"frame\") on a scene's plan, as the frame's bar and Details do: `material` (a skin id or name from diagram_library's frames — diff-medium, silk, art-silk, grid-cloth, single-net, double-net, solid, bounce-white, ultra-bounce, muslin, bleached-muslin, day-grey, silver-lame, check-gold-white, natural-1-1, hard-mirror, green-screen, custom, gel, none…), `frame_type` (none, open, butterfly, speed-rail, black-pipe), `grid` (0 for none, or 20, 30, 40, 45, 50, 60 degrees), `tilt` (0 lying flat — how a new frame lands — to 90 standing, in 5° steps), `width` and `height` in metres, `gel` (a gel id, with material gel), `color` (#rrggbb, with material custom), `note` (its Note, what it is doing: \"Bounce for Key\", the line under its size and cloth), as on the frame's bar. `id` is the frame's id, or several separated by commas. One undo step.",
        arguments: &[
            ("scene", "string", true),
            ("id", "string", true),
            ("material", "string", false),
            ("frame_type", "string", false),
            ("grid", "number", false),
            ("tilt", "number", false),
            ("width", "number", false),
            ("height", "number", false),
            ("gel", "string", false),
            ("color", "string", false),
            ("note", "string", false),
        ],
    },
    Tool {
        name: "point_arrows",
        description: "Arrows from one piece — a note, words, anything — to each of several others, pinned at both ends: they follow either piece wherever it moves and stop at its outline, as the Mac's arrows do when drawn from one piece onto another. `from` is the piece the arrows leave; `to` is one id or several separated by commas. `dashed` draws them dashed. One undo step.",
        arguments: &[("scene", "string", true), ("from", "string", true), ("to", "string", true), ("dashed", "boolean", false)],
    },
    Tool {
        name: "diagram_cast",
        description: "Who can stand on a scene's plan: the characters the script puts in this scene, then everyone else in the project. A person is added with {\"kind\":\"cast\",\"cast\":\"<name>\"} and wears that character's Cast colour.",
        arguments: &[("scene", "string", true)],
    },
    Tool {
        name: "diagram_favorites",
        description: "The project's nine favorite pieces — the Favorites row under the Diagram toolbar — by slot 1 to 9, each empty or the piece it keeps.",
        arguments: &[],
    },
    Tool {
        name: "set_diagram_favorite",
        description: "Keep a piece from a scene's plan in a favorite slot (1–9), as it is now — its drawing, size, colour, lens, beam and the rest. Leave `id` empty to empty the slot. The project's, not the scene's: every plan offers it.",
        arguments: &[("scene", "string", true), ("slot", "number", true), ("id", "string", false)],
    },
    Tool {
        name: "place_favorite",
        description: "Put a favorite slot's piece on a scene's plan with its middle at x, y (metres). One undo step.",
        arguments: &[("scene", "string", true), ("slot", "number", true), ("x", "number", true), ("y", "number", true)],
    },
    Tool {
        name: "copy_diagram",
        description: "Another scene's diagram onto this scene's, as the app's Copy From does: the room, furniture, lights and people come across, and every camera too, loose from its shot (that scene's shots are not this one's). `mode` \"replace\" (the default) takes the place of what is on this plan, settings too; \"add\" puts the copies on top, where they were drawn, keeping all that is here. `ids` (separated by commas) copies just those pieces of the other plan, their groups and what rides them coming too. A replace over a plan that already has anything on it is refused, saying how much, unless `even_if_drawn` is true — ask him first.",
        arguments: &[("scene", "string", true), ("from", "string", true), ("mode", "string", false), ("ids", "string", false), ("even_if_drawn", "boolean", false)],
    },
    Tool {
        name: "send_diagram",
        description: "This scene's diagram, or some pieces of it, onto other scenes' diagrams, as the app's Copy To and Send to Scene do — one undo step for all of them. `to` is one scene or several separated by commas. `ids` (separated by commas) sends just those pieces, their groups and what rides them coming too; cameras arrive loose from their shots. `mode` \"add\" (the default) puts the copies on top of each plan, where they were drawn; \"replace\" takes the place of what each holds — refused, naming them, where any already has something on it, unless `even_if_drawn` is true — ask him first.",
        arguments: &[("scene", "string", true), ("to", "string", true), ("ids", "string", false), ("mode", "string", false), ("even_if_drawn", "boolean", false)],
    },
    Tool {
        name: "plans",
        description: "The project's loose plans — diagrams that belong to no scene (a recce, a plan before the script, a lighting setup used again): each by name, with how many pieces it holds. Every diagram tool's `scene` takes a plan's name too (or \"plan: <name>\" where a name could be read as a scene's number); a camera on a plan stands for no shot.",
        arguments: &[],
    },
    Tool {
        name: "new_plan",
        description: "Make a loose plan. `name` (Plan 1, Plan 2… if not given); `from` a scene or plan whose diagram it starts as a copy of (cameras loose from their shots). Draw on it with edit_diagram, scene = its name. One undo step.",
        arguments: &[("name", "string", false), ("from", "string", false)],
    },
    Tool {
        name: "rename_plan",
        description: "Rename a loose plan.",
        arguments: &[("plan", "string", true), ("name", "string", true)],
    },
    Tool {
        name: "delete_plan",
        description: "Delete a loose plan and everything on it — ask him first, saying how many pieces it holds (plans lists it). Undo brings it back.",
        arguments: &[("plan", "string", true)],
    },
    Tool {
        name: "scene_diagrams",
        description: "A scene's diagrams — a scene can hold several (a Wide Setup, a Reverse, a Night Version): each by its place, the name he typed (blank when unnamed; the app shows \"Diagram N\" as a placeholder) and how many pieces it holds. Every diagram tool's `scene` takes one of them as \"<scene> / <name or place>\", e.g. \"5 / Reverse\" or \"5 / 2\"; the scene alone is its first-made diagram.",
        arguments: &[("scene", "string", true)],
    },
    Tool {
        name: "new_scene_diagram",
        description: "Another diagram on a scene, at the end of its row. `name` is his — never invent one; leave it blank when he gave none. `from`: a scene, scene diagram (\"5 / Reverse\") or plan whose pieces it starts as a copy of (cameras loose from their shots). One undo step.",
        arguments: &[("scene", "string", true), ("name", "string", false), ("from", "string", false)],
    },
    Tool {
        name: "rename_scene_diagram",
        description: "Rename one of a scene's diagrams (\"5 / 2\"). A blank name makes it unnamed again.",
        arguments: &[("diagram", "string", true), ("name", "string", false)],
    },
    Tool {
        name: "move_scene_diagram",
        description: "Move one of a scene's diagrams to `place` (1 = first) in the scene's row.",
        arguments: &[("diagram", "string", true), ("place", "number", true)],
    },
    Tool {
        name: "delete_scene_diagram",
        description: "Delete one of a scene's diagrams and everything on it — ask him first, saying how many pieces it holds. A scene keeps at least one. Undo brings it back.",
        arguments: &[("diagram", "string", true)],
    },
    Tool {
        name: "hide_scenes_from_diagrams",
        description: "Hide scenes from the Diagram's scene list by hand (or show them again) — the right-click Hide from Diagrams on the Mac, iPhone and portal; the same on all three. `scenes` is scene numbers separated by commas (\"4, 7\"); `hidden` false shows them again (true if not given). Only the Diagram's list changes: the shot list, the schedule and every diagram stay as they are. Give no `scenes` to list what is hidden now. diagram_scenes marks them. One undo step.",
        arguments: &[("scenes", "string", false), ("hidden", "boolean", false)],
    },
    Tool {
        name: "diagram_everywhere",
        description: "Set one plan setting on every scene's diagram at once — the project's switches rather than one scene's. `setting` is any key edit_diagram's settings op takes; `value` is its JSON value.",
        arguments: &[("setting", "string", true), ("value", "string", true)],
    },
    Tool {
        name: "room_scans",
        description: "The rooms scanned with the iPhone at the places a scene is shot — each by location and name, and whether its measurements are there to lay. lay_room puts one on the plan. Give `location` instead of `scene` for one location's scans. Scanning a room needs the iPhone itself.",
        arguments: &[("scene", "string", false), ("location", "string", false)],
    },
    Tool {
        name: "rename_scan",
        description: "Rename a scanned room, as Rename Scan on a location does on the Mac and iPhone: `location` (as locations names it), `scan` (its name now, as room_scans lists it) and `name`. Its files and every plan already laid from it stay as they are. One undo step. Deleting a scan is remove_attachment on the location, once for each of its two files (the .json measurements and the .usdz shape, as attachments lists them) — ask him first.",
        arguments: &[("location", "string", true), ("scan", "string", true), ("name", "string", true)],
    },
    Tool {
        name: "lay_room",
        description: "Lay a scanned room on a scene's plan — its walls, doors, windows and furniture, to measure. A room laid before is replaced; everything else on the plan stays. `scan` is its name from room_scans (the newest at the scene's place if not given); `location` narrows it when two places share a name.",
        arguments: &[("scene", "string", true), ("scan", "string", false), ("location", "string", false), ("measurements", "string", false)],
    },
    Tool {
        name: "floor_picture",
        description: "Lay a picture under a scene's plan — a floor plan he was sent, a photo of the room from above — to draw over. Either a picture already in the project (`attachment`, with the shot, scene, location or board it is pinned to, as attachments lists it) or, on his Mac only, a file at `path`. `width` is how wide it lies, in metres (5 if not given); `x`, `y` its middle (0, 0 if not given). `over` true lays it on top as a loose photo instead.",
        arguments: &[
            ("scene", "string", true),
            ("attachment", "string", false),
            ("shot", "string", false),
            ("location", "string", false),
            ("board", "string", false),
            ("path", "string", false),
            ("width", "number", false),
            ("x", "number", false),
            ("y", "number", false),
            ("over", "boolean", false),
        ],
    },
];

/// Everything an AI needs to draw without guessing — the engine's own rules
/// (`diagram::apply`, `El`, `Settings`), said once.
const GUIDE: &str = r#"DIAGRAM GUIDE

Space. Metres. x grows right, y grows DOWN the page. Angles in degrees clockwise from east: 0 faces right, 90 faces down, 180 left, 270 up. A plan is drawn north-up unless `north` turns it.

Every piece has an `id` (the plan gives one), a `kind`, and only the fields it uses. Fields every kind may take: label, color (#rrggbb; empty is the kind's own ink), opacity (0–1 — fades a piece to see what is under it, its label never; lamps and frames too, a frame over a large area most of all), locked, hidden, note, group / group_name, label_dx / label_dy (metres, moves its label — see NAME AND NOTE), label_size (points), label_bold, label_hidden. label_size and label_bold are kept and read back, but a plot draws every label one size in regular weight and the app no longer offers them (see NAME AND NOTE): do not use them to style a plot. `note` is the piece's hidden note (a room scan keeps its mark there) — never a lamp's Note, which is its `label`.

KINDS
- wall — ONE continuous line with corners: points [[x,y],…] (any number of corners; a plain two-corner wall may be x,y → x2,y2 instead), closed true to run back to the first corner (a room is one closed wall), round [corner indices] for corners drawn as curves, thick (default 0.15; in a plan in feet 6 in — the app's one-tap thicknesses are 1, 4, 6, 9, 12 in, or 0.025, 0.1, 0.15, 0.23, 0.3 m). A closed room's lengths are written along its inside face. Doors and windows lying on a stretch move with it; a corner sitting on another wall's corner or on the middle of its stretch (a T) moves when that wall moves.
- door / window / opening — sit in a wall: x,y is the middle, rot the wall's direction, w the width (in a plan in feet: door 3 ft, window 4 ft, opening 3 ft, walls 6 in thick; in metres: door 0.9, window 1.2, opening 1.0). door: swing (degrees, 90; 0 is shut), hinge ("left"/"right"), flip (opens the other side), door (its kind, one word: "swing" one leaf on hinges, "double" two leaves swinging from the middle, "sliding" two panels on two tracks, "center" two panels parting from the centre, "pocket" sliding into the wall, "pocketpair"; set it on add or update — it is stored as the switches slide/pair/pocket). A sliding kind's swing is how far open, 0 shut, 90 all the way; hinge is the side a single panel slides toward or the pocket is on; flip the wall face its track runs on. An opening is a plain gap with no door in it.
- set — furniture and set dressing: x,y middle, rot, w (length along rot) × h (depth); sym picks the drawing from diagram_library (bed, sofa, table…). fill and color are kept but not drawn: a plot draws set pieces in the set's grey.
- camera — x,y, rot = the way the lens points; shot (the shot's id — or add with "new_shot":true to make one). **A camera is its shot**: its film camera (and so its sensor) and its Lens come off the shot — set them with update_shot camera / lens, and a zoom's setting with update_shot focal. A camera with no shot takes unit (one of the film's cameras, by id — `cameras` lists them), lens_name (a lens off the film's Lens list — `diagram` lists them under `lenses`) and lens (mm: where its zoom is set, or a focal length when it has no lens). A sensor is typed on the film's camera (update_camera sensor_w/sensor_h); a camera with none reads Super 35. A lens name says the rest: "24-70mm" is a zoom, "2x" a squeeze. reach (cone length, m); cone (draw the cone); height, rig (words); frame_on with frame_dx, frame_dy, frame_w lays the shot's frame on the plan beside it. `diagram` answers each camera's camera, lens, zoom, focal, sensor and view_degrees.
- cast — a person: cast (the character's name, from diagram_cast); pose ("standing", "seated", "lying"); rot = the way they face. w 0.28 × h 0.46.
- light — sym (the unit, from diagram_library: hmi-par-4k, tungsten-fresnel-2k, fso-arri-m18…); gels (list of gel ids); kelvin, dim (0–100 %), role and height are kept but not drawn on a plot. **A plan is a lighting plot by default** (his ruling 2026-10-03, after Deakins's plots): a lamp is drawn as a small mark (a chevron opening the way it throws, a ringed circle for a practical, a bar for a tube or panel) and named by a callout in dark ink. The MARK carries the colour, in THREE INKS (Back to Paper, his call 2026-10-04): red for what we bring (film lights, frames, grip), blue for the camera and its move, grey for the set and what is already there (the location's own lamps); PRACTICALS ARE AMBER (his calls 2026-10-05). A callout's first line (the Name) is drawn in its mark's colour, its second line (the Note) grey (his call 2026-10-05). mark, mark_fill (the lamp's SYMBOL: chevron, wedge, bar, double-bar, ring, dot, square, mat, letter-A…letter-Z; mat is a soft panel seen from above — a LiteMat, book light, overhead frame, soft box — drawn at its true w × h (metres, any size, no locked ratio) in the lamp's colour with a faint wash and a fine inner line, turned with rot; give it w and h, e.g. a 4 × 2 ft mat is w 1.2192, h 0.6096; arrow is kept on old lamps but no longer offered, his note 2026-10-05: an arrow is not a lighting unit — draw arrows with the arrow kind; fill solid/open — add lights with "sym":"" and a mark, then name them with name_lamp. ONE CONTROL PER JOB (his call 2026-10-04): a lamp's colour is its TYPE alone — mark_ink is ignored. THE SYMBOL SAYS THE FAMILY, THE NAME SAYS THE UNIT (his call 2026-10-05, reversing 10-04's name-on-the-symbol: "i might have 3 different kinds of panel lights in a setup"): three kinds of panel all wear double-bar, each with its own Name), mark_k (how many times its page size the mark is drawn: 1 as put down; an update of a lamp's w/h — the app's corner drag — multiplies it by as much as the lamp grew, a tube or panel by its width alone; a mat, a hung lamp and a string stay at their true size; give mark_k to size a mark directly, 0.4–10), count (1–999: how many units stand there under one name — "3× 2K Blonde"), spread (a STRING of lamps, his ask 2026-10-04: "line" draws count marks evenly along the lamp's long side — h is its length with w 0.3, curve its bow in metres, + toward the way it faces — for bulbs along a drive or a row of space lights; "ring" puts count marks round an oval w × h — globes round a table; "" is one lamp; one name "10× 300W Mushroom"), a light's TYPE: a film light (default, ours, kept out of frame; red), practical true (seen in the shot, often the art department's; amber, with its own legend line), or existing true (the location's own; grey); action "off" on a practical or existing light crosses it out (swap or dim go in its label as words). A lamp has TWO WORDS (Back to Paper, Batch 2): its NAME is what it is ("4' Titan Tube") — the lamp's own `lamp_name`, its label as typed (2026-10-15: a new lamp has none until one is typed; the legend lists unlabelled lamps on a faint UNLABELED line per symbol and the gear list counts them by unit); set it with name_lamp, or lamp_name on add/update. Lamps of one symbol may carry different Names. Its NOTE is what that one lamp is doing ("Uplight on BG") — its `label`, drawn as the label's second line in grey, after which its gels and Off follow, joined by a middle dot ("UPLIGHT ON BG · ½ CTO · OFF"). Never put a lamp's name in its label. A lamp faces the way rot says — the heavy ink line on its outline is its front, a tube's being its long side; the app puts one down facing up the page (rot 270). **A lamp HUNG POINTING STRAIGHT DOWN** (his ask 2026-10-05: a LiteMat 8 over the set) is tilt 0 — the app's Down on a lamp's bar; tilt 90 (the default) is pointing across the plan. Pointing down, it is drawn at its true size from above (w × h, a mark across at least) with heavy edges (so it never reads as a frame), a thin cross corner to corner and no front edge, and its Note line starts "TOP", then its `height` when set (a text such as "8'" — the app's Height: 6' to 20', or 2 m to 6 m), then its note: "TOP · 8' · OVER DINNER TABLE". A ring or dot mark keeps its mark. **Lamps draw no beams for now** (his call, 2026-10-01: a beam needs each lamp's real size of source first) — only the sun lights the plan; beam, reach and beam_on are still kept on a lamp but change nothing drawn. Grip — flags, nets, rags, boards, frames — is a light-kind piece that gives no light (diagram_library library=grip); stands, rigging and lifts are set pieces from the grip library.
- frame — a light with sym "frame": h its width across, tall its height, tilt 0 lying flat (a new frame lands flat) to 90 standing, material (diagram_library's frames.materials: diffusions, silk, grid cloth, nets, solid, bounces, muslins, day grey/blue, lamés, mirrors, checkerboards, natural bounces, blue/green screen, custom (wears color), gel (wears its gels), none), pipe (none, open, butterfly, speed-rail, black-pipe) and grid (0, 20, 30, 40, 45, 50, 60) are kept but not drawn, and the app no longer offers them. set_frame does all of it by name. A frame in plan is a line or a double line in grip's red: leaning, its raised edge (the back, away from the way it faces) as one line; lying flat, a dashed outline with its cloth's pattern faint across it (on screen and on paper, his note 2026-10-05; the fabric setting false hides it); standing, one line. Its lean in perspective and its cloth at full strength show on the picked frame on screen. A frame's callout (his notes 2026-10-05): the first line is its SIZE AND CLOTH, then its lean after a middle dot ("12×12 ULTRA BOUNCE · 45°"), set by h, tall, material and tilt; the second line is its NOTE, its `label` (what it is doing, "Bounce for Key"). `diagram` answers its `label_lines`. (`title` is kept on a few frames but not drawn.) Its length shows only while it is picked or being drawn. With Snap on in a plan in feet, a frame's size keeps to whole feet.
- track — dolly track: a line x,y → x2,y2, thick 0.6; curve bends it (m sideways at the middle). Drawn as dolly track: two fine blue rails its gauge apart (thick, up to 0.8 m) with a tie across them every two feet (his note 2026-10-05: the old single line with ticks read as a measurement), its length written small and grey.
- road — a street, alley, driveway or path on an exterior plot (his ask 2026-10-04, after the street plots): x,y → x2,y2 with curve to bend it (a driveway); thick is kerb to kerb in metres (street 9.144 = 30 ft, the default; alley 4.572; driveway 3.048; path 1.2192). Drawn as its two kerbs only, cut open wherever another road meets or crosses it, so lay streets end to end or across each other and junctions open by themselves. label is its name, written along it in capitals ("Douglas Ave"). lanes, marking and walks are kept but not drawn.
- set sym "building" — a building's footprint (w × h metres) with its label written inside it ("709", "BANK"); sym "area" — a shaded patch with a dashed edge and its label inside ("Shop lights off in this area"). Both from diagram_library library=set, Outdoors. sym "stairs" — treads across its length and an arrow pointing up (h is the run).
- text — WORDS: text, size, bold, align ("left", "centre", "right"); x,y, rot. Dark ink unless color is set. Words stand the same size on the sheet at any scale (Back to Paper, Batch 2): `size` draws at size × 1.5 points, so use the app's two sizes — Regular 6.6667 (10 pt, a label's size; new words) or Large 9.3333 (14 pt). Old words keep their stored size and their look.
- measure — the Ruler: a line through markers, ticked every foot (or metre), each stretch's length written on it, small and grey, and the total when there are more than two markers. A Ruler's lengths always show, whatever dims says. A plain one is x,y → x2,y2; with more markers, points [[x,y],…]. pins: one per marker, the id of the piece (person, camera, object) that marker is locked to, or "" for a marker placed by hand — a locked marker stands on its piece and follows it. Markers are edited with the wall edits: wall_insert (stretch, x, y, and "on" to lock it), wall_extend, wall_corner (corner, x, y, and "on" to lock or "" to free), wall_remove_corner, wall_length.
- arrow — x,y → x2,y2 (or points for a bent one); head ("end" default, "both", "none"), weight, dash ("dashed", "dotted"), curve. start_on / end_on pin an end to a piece by id: that end follows the piece and stops at its outline (point_arrows draws them). Moving a pinned end or the whole arrow by hand lets it go; "end_on":"" frees it.
- shape — sym "rect" (default), "ellipse", "circle", "triangle", "diamond", "pentagon", "hexagon", "star"; w × h; fill (off unless set true: a shape is an outline by default, Back to Paper), color.
- cable / stroke — points [[x,y],…]; weight, dash, color. A stroke with no `handles` is a freehand pen line, smoothed through its points.
- A drawn path — a stroke with `handles` (or a wall with them): one pair of curve handles to each point, [[in_dx,in_dy,out_dx,out_dy],…], offsets from the point; all nought is a sharp corner. A stretch with a handle at either end is a curve, so a path can be exact straight sides, a curved wall, or a flowing outline. `closed:true` closes it; a closed stroke with `fill:true` is an object (a pond, a curved sofa), with `label` for its name; without fill it is an outline. Any closed path or room takes `fill_color` (`#rrggbb`, or "auto" for the plan's tint; a path with `fill` on and none is tinted) and `fill_alpha` (0–1, how solid; 0 is its own: a tint is light, a colour firmer). A room (a closed wall) is filled only when it has a `fill_color`. Make one smooth with wall_smooth, turn it into a wall, an object or a line with path_as.
- image — a picture on the plan; made by floor_picture, not by add. A picture shows at its own opacity whichever layer is being worked (2026-10-15); new ones start at 1. MARKS DRAWN ON A PICTURE (his ask 2026-10-15) live on it, in `marks`, every number a fraction of the picture (0–1, left to right, top to bottom), so they move, size and turn with it and are drawn at full strength: `;`-separated, each a storyboard arrow exactly as picture_arrows writes one, or `line,x1,y1,x2,y2[,dashed][,look:<light|dark|red|yellow>][,thick:<0.5–3>]`, `box,x1,y1,x2,y2[,look][,thick]`, `oval,x1,y1,x2,y2[,look][,thick]`, `draw,x:y,x:y,…[,look][,thick]` or `words,x,y[,look][,size:<fraction of the picture's height, 0.045>],t:<text with % , ; and new lines as %25 %2C %3B %0A>`; set it with update set {"marks":…}. `perspective` is `<horizon y>:<vanishing x>` (fractions; empty off), the helper drawn only while he draws on it. {"op":"attach_marks","id":<picture>} moves the arrows, lines, shapes, drawn lines and words lying wholly on it onto it (Attach to Photo).
- note — an old sticky note: text, x,y. Kept and drawn; the app edits it as Words and no longer makes them — add kind text instead.

EDITS (edit_diagram's op)
- add {els:[…], group_name?} — new pieces; each takes the fields above. Answers the ids made. An el may carry an id already on the plan (copied from diagram's output): it gets a new one, and an aim or rig_on at it from the same add follows it to the new piece. "new_shot":true on a camera, or beside "els" for every camera in the add, makes each its own shot. group_name makes them one group by that name. A room is one closed wall: {"kind":"wall","points":[[0,0],[4,0],[4,3],[0,3]],"closed":true}.
- wall_corner {id, corner, x, y, free?} — one corner moved; its two stretches follow, and what is joined there comes too unless free.
- wall_insert {id, stretch, x?, y?} — a corner added in a stretch (its middle unless told); it becomes corner stretch+1.
- wall_extend {id, end:"start"|"end", x, y} — an open wall grown on from an end.
- wall_break {id, corner, gap?} — opened at a corner: a door-wide gap (3 ft / 0.9 m, or gap metres). A closed wall opens there; an open one becomes two (the new one's id is answered). For a doorway mid-stretch: wall_insert, then wall_break that corner.
- wall_round {id, corner, round:true|false} — a corner made a curve, or a corner again.
- wall_smooth {id, corner, smooth?:true|false} — a corner of a wall or drawn path made smooth (its handles worked out from its neighbours), or sharp again. Round (wall_round) is a rounded corner of straight walls; smooth is a flowing curve through the point.
- wall_handle {id, corner, side:"in"|"out", x, y, free?} — one curve handle moved to a place; the other swings opposite unless free.
- camera_shot {id, set:{…}} — a camera's shot, written through the camera as the Mac's and the portal's Details do: `unit` (a camera record's id), `lens`, `focal`, and its shot's `size`, `movement`, `title`, `description`, `angle` ("High, Dutch"), `support` (Equipment), and `columns` ({"Cast":"Gio, Anna"}, the film's own list columns by name). "" clears. A camera with no shot keeps only unit, lens and focal.
- path_as {id, as:"wall"|"object"|"line"} — a wall or drawn path made a wall (thickness, doors sit in it), an object (closed and filled) or a line (outline only). Same points and curves.
- wall_remove_corner {id, corner} — a corner taken out.
- wall_length {id, stretch, length} — a stretch given a length (a closed room's inside face). Its far corner moves along it; an open wall's corners beyond ride along; a room's next corner too, so it stays square.
- wall_join {ids, gap?} — walls that meet end to end made one, bridging the gap a wall_break left (ends within about 1.7 gaps; `gap` is the break's width in metres if it was not a door's); a chain back to its start is closed, and one open wall named alone closes on itself.
- update {id or ids, set:{…}} — fields changed; a field left out stays.
- remove {ids}
- move {ids, dx, dy} — metres; a group moves whole; locked pieces stay.
- rotate {ids, deg, px?, py?} — about their middle, or the point given (the Mac turns a pick about its middle put on the grid).
- "alone":true on move, rotate, flip or duplicate — that piece by itself, not its whole group (one piece picked inside its group).
- flip {ids, axis:"x"|"y"} — mirror.
- order {ids, to:"front"|"back"|"forward"|"backward"} — or to:"above"/"below" with next:<id>.
- duplicate {ids, dx?, dy?, x?, y?} — copies 0.5 m off, or dx,dy off, or with x,y their middle put at that point (the Mac's paste at the pointer); a copy of a camera is a new camera, loose from the shot. Copies keep their aim: aimed at a piece copied with them, at that piece's copy. To build a row, step each copy by the same dx,dy from the last.
- swap {ids, sym} — a different drawing, keeping place and rigging; on a camera, a body from diagram_library's `cameras`.
- group {ids, name?} / ungroup {ids}
- align {ids, to:"left"|"right"|"top"|"bottom"|"hcentre"|"vcentre"}; distribute {ids, axis:"x"|"y"}
- step_add {id, after?, before?, turn?, x?, y?, rot?, pose?, beat?} — the next STEP a camera, person, light or set piece takes (see STEPS): after the step at that letter-order index (after the last if neither is given), or before it for a move or turn FROM somewhere. Placed a little ahead and on the next beat unless told.
- step_set {id, step, x?, y?, rot?, pose?, beat?, turn?} — change one step by its letter-order index (A is 0); the thing itself is one of its steps. A beat another of its steps holds is traded with it; beat 0 is no beat.
- step_remove {id, step} — take one step away; the thing itself stays.
- beat {id, beat, x, y, rot?, pose?} — where it stands at a beat: the step on that beat moves, or a new step is made on it. unbeat {id, beat} takes away the step on that beat. The plan plays beat 1 → 2 → 3…
- settings {set:{…}} — the plan's settings, below.
- share_label {ids} — on a plot, ONE label for these lamps — or frames, grip, set pieces, cameras, people, track, roads, shapes and pictures, any mix (his ask 2026-10-05: "frames and any object can share the same label"; not words, walls, doors, windows, openings, rulers, arrows, cables or drawn lines). A label holding more than lamps counts each by its name — a frame by size and cloth ("2× 12×12 ULTRA BOUNCE + 1× SOFA"), a camera by its shot, a person by who plays them, anything else by its label or what it is — and under it each piece's Note (a lamp's and a frame's `label`, anything else's `caption`); a Note set on one piece of a label is set on all. Lamps only (his ask: fewer labels for the same symbol across the plan): a text among the ids is the label they join, else new words are put over them; a fine line runs from the label to every lamp tied to it, and the lamps lose their own callouts. In the app this is Share Label. ONE JOIN RULE (Back to Paper, Batch 2): Share Label, the Connector tool drawn from a label onto a lamp, and a label picked with lamps all do the same — a shared label NEVER changes a lamp's symbol or Name (2026-10-05) and counts each kind ("2× SKYPANEL S60 + 1× LITEMAT 4"); lamps picked with a lamp already on a label join that label rather than making a second. Every lamp's note and gels are gathered onto all of them. The label writes what the lamps are, counted ("4× 2K BLONDE"), and under it their note, gels and Off (a second line, as a lamp's own label has); a note, gels, action or Type set on any lamp of a shared label is set on all of them, a new symbol for one lamp is for that lamp alone; typed words on the label show only while its lamps have no Name. A shared label obeys label_hidden (on the label) and the labels setting like every other label; a lamp's own label_hidden is about its own callout, so it keeps its line while it shares one. New words are put down clear of the plan's other words and pieces, by their lamps (optional `ppm`: the zoom they are kept clear at, points to the metre). Deleting the label gives the lamps their own callouts back. Answers the label's id. own_label {ids} — these lamps (or every lamp of a label, given the label's id) get their own labels back; the label stays. In the app both are Share Label and Own Label.
- legend {key:"colour:<role>", name} — what a colour means on this sheet (roles: added, practical, existing — these three name the legend's group heads on the sheet, "Film Lights", "Practicals", "Existing" unless renamed — and blue, gripink, camink); diagram's `legend_colours` lists the colours in use and what each means.
- under (any piece, true/false) — drawn underneath everything, e.g. a ruler kept under the furniture.
- ride {id} — a camera locked to the nearest dolly track (a laid track, or a circle track from the library): it is put on the track's line and from then on slides only along it, and goes with the track when the track moves. update {id, set:{rig_on:""}} unlocks it. A camera set down on track is NOT locked until ride. On a plot a track writes its length and the sections it takes ("24 FT · 3 × 8'").
- name_piece {id, name} — any piece's label, as typed (diagram2, his call 2026-10-17: "labels are just what you type", on frames, grip, half rounds, cameras and cast as on lamps; several lines are kept as typed, "\n" between them); on words, their text. name_lamp does the same on a lamp or a frame.
- send_layer {ids, to:"set"|"plot", copy?} — Send to Set / Send to Plot: the pieces move to the other view where they stand, turned and named as they were; copy:true leaves them and sends a copy in place (answers the copies' ids). Walls, doors and the street cannot go and are passed over.
- ONE COLOUR FOR SEVERAL (the app's Color on a multiple pick): a batch of update ops, one per id, each {"set":{"color":"<hex>"}} — one undo step.
- name_lamp {id, name} — a lamp's NAME, its label (his call 2026-10-15: labels are just what you type): this lamp ALONE, never another called the same and never its mirrorland (only is still read and changes nothing). It never changes a symbol. name "" clears it (no label). A lamp put down has no label until one is typed; lamps on plans from before keep the unit name they showed, as an ordinary label. Lamps carrying the exact same label share one legend line ("KEY LIGHT ×2"); to rename every lamp on a legend line, use the legend op with that line's key and a name. Several items under one label drawn once with thin lines: share_label.
- legend {key, name?, to?} — on a plot, ONE LEGEND LINE: a symbol and one Name drawn with it (2026-10-05). key is the look and the Name, "double-bar|added|solid|SkyPanel S60" (mark · ink: added = a film light, practical, ink = the location's own, drawn grey · solid or open · Name), or the look alone for lamps with no Name yet; diagram's `legend` lists the lines with each key, name, count and the ids of their lamps, a symbol's Names one after another (the sheet draws the symbol once beside them, the Names stacked). name: renames the lamps on that line ("" clears). to: another look, re-marking the lamps on that line. Each lamp's `legend_key` says its line.
- clear — everything off the plan. Ask him first.
- batch {ops:[…]} — several edits as one undo step.

NAME AND NOTE (Back to Paper, Batch 2 — the app's two words). Every piece has a NAME: on a lamp it is its own Name (name_lamp; lamps of one symbol may differ); on a frame its size and cloth; on anything else it is its `label` (a sofa, a wall, a street; a camera linked to a shot shows the shot's number, a person their character). EVERY PIECE HAS A NOTE (his note 2026-10-05: "alll items should be able to have a note"), drawn in grey on the line under its name: a lamp's and a frame's is their `label`; any other piece's (set piece, person, camera, wall, street, arrow, shape, cable, track, grip) is its `caption` — update set {"caption":"Strike for 8B"}. Words are words and take none. The words drawn beside a piece are its LABEL — not a field, it writes itself: a lamp's count and Name ("4× 4' TITAN TUBE"), over its Note, gels and Off in grey. `diagram` answers each lamp's `lamp_name`, `legend_key` and `label_lines` [first line, second line], as typed (the plan writes them in capitals). WORDS ARE INK (his call 2026-10-04, softened 2026-10-05): every label is one size, regular weight, with no box behind it; a lamp's, a frame's and a camera's first line is drawn in its mark's colour (a practical's in a deeper amber), the second line grey, anything else's dark. A plot's labels ignore label_size and label_bold (kept, not drawn, not offered). A label never moved is put by the plan off other unmoved labels and pieces — under, else right, left, above, else further out. To name a piece other than a lamp: update set {"label":"Sofa"} (a single space hides it). To move a label: label_dx / label_dy, metres from its spot under the piece; it then stays EXACTLY there as the piece moves, over whatever is under it (his note 2026-10-05: no collision barriers), tied back by a thin line once it is away from it. label_dx 0 and label_dy 0 put it back (the app's Reset Label). label_hidden hides it (Hide Label); the labels setting hides every label, shared ones too.

LIGHTING PLOT (Labs, his call 2026-10-03): a plot draws no steps or beats; they stay in the film but are not shown. The plot is a lighting plot after Deakins: thin walls, plain outlines, lamps as marks with a legend, notes in capitals.
STEPS (his ruling, 2026-10-01 — there is no fixed A and B): a camera, person, light or set piece takes as many steps as he likes, lettered A, B, C … Z, AA … in order. The piece's own x, y, rot is one of them (the solid one; `lead` says how many steps come before it); each other step is KEPT, NOT DRAWN on a plot (it was a ghost with its letter and arrows between steps), and a turn (turn:true) stays on the spot of the step before it and only turns. Every step plays on a beat (its `beat`; 0 is none — kept on the plan, not played); diagram's `seq` lists them with letters and beats. Add one with step_add, never by writing `steps` by hand. A plan made before steps had a `move` (one A → B that never played) and a `path` (beats 2 and on); both read in as steps.
AIMED: set "aim":"<id>" on a light, camera or person and it keeps facing that piece whenever either moves. "aim":"" lets go.
RIGGED: set "rig_on":"<id>" and a piece rides another — a lamp on a stand, a camera on a track; moving the one carries the other.

SETTINGS (settings op; diagram_everywhere for every scene at once)
LABELS AS TYPED (Plan Settings, diagram2 2026-10-17): caps (false, the default: every word in the case it was typed; true: capitals, as reference plots write) · counts (false by default: no automatic numbers; true: "3× Key Light", "Key Light ×2" on labels and the legend) · unlabeled (false by default; true: the legend's faint UNLABELED line for pieces with no label) · free_names (true on every plan saved since: every piece is named only by what he types; an older plan is switched over on first read, its frames' and grip's old words written on as ordinary labels). Where this guide says a label or legend line is counted or in capitals, that is with counts or caps on. Never type a count into a label: counts is his switch.
sketch (true: a SKETCH, not a plan — his ask 2026-10-04, callouts over a location photo or a drawing: turns grid, snap, dims and sun off and drops the scale bar; lay the picture with diagram_picture or the add op's image, then lamp marks, words and arrows over it; false brings grid and snap back) · units "ft"|"m" (switching it puts step at a foot or half a metre, unless step comes too) · grid (faint dots one step apart, not lines), snap, dims, cones, labels (true/false) · dims is OFF on a new plan (his Ref 1452, measurements off by default): leave it off unless he asks for lengths; while it is off, a wall's or frame's length shows only on the picked piece or while drawing, and a Ruler's and a track's own lengths still show · all_lengths (true: every wall's lengths on screen, not only the picked wall's; on paper a wall's lengths print ONLY with dims and all_lengths both true — the app's View › Lengths: Picked is dims false, All is dims and all_lengths true) · step (grid, m) · north (degrees the page is turned from north) · colours ({added, practical, existing, blue, gripink, camink, plan, prop: a #rrggbb text}, an OVERRIDE of the plot's colour for one category — every plan is a lighting plot; a category left out draws in the three inks: added and gripink red, practical amber, camink blue, existing, plan and prop grey. Set colours only when he asks for a colour; never write the defaults in) · sun, sun_rays (true/false), sun_date ("2026-09-27"), sun_time ("14:30") — empty reads the scene's shoot day and time of day · beams and levels are kept in old plans but draw nothing: the picture style is retired.
THE SHEET (Back to Paper, Batch 2, his calls C and G): every plan is drawn on a sheet — on the Mac's screen, Export, Print, the portal's Print and diagram_picture paper — built once: a title across the top (the scene, the film and its day, north, the date it is printed), the plan to fit in a window, and a band along the foot of NOTES, LEGEND (Film Lights · Practicals · Existing, each line a mark, its NAME and ×N, drawn plainly however faded its lamps are; then FRAMES by size and cloth, "12×12 ULTRABOUNCE ×2") and SHOTS (each camera's shot number with size, lens, movement, support). Its settings: sheet_notes (his own words for the whole setup, "ALL LAMPS TO DIMMERS" — printed under NOTES only when it has words; write it from his notes when he asks, never generate it, never repeat lamp notes there) · notes (true: show the Notes block) · legend (true: show the legend) · paper "letter" | "tabloid" | "a4" · orientation "landscape" | "portrait" · fabric (true by default: a frame's cloth drawn faint across it on screen and paper; the app's View › Frame Fabric) · measures (true by default: the rulers laid with the measure kind, on screen and on paper; false keeps them and draws none, and none can be picked — the app's View › Measurements) · scale_bar (false by default: no scale bar and no stated scale — sizes go in the words, "22' TRACK", "12×12"; true draws a bar and writes a standard scale such as 1/4" = 1'-0" in the title, for a plan someone will measure off paper). `diagram`'s `sheet` says them all; its `gear` is the app's Copy › Gear List: lamps by legend name × count (Lights, Practicals; the location's own lamps are not brought), frames by size and material, then grip.

WORKING WELL
- Read diagram first; place relative to what is there. Draw the room (one closed wall, then doors and windows on its stretches), then furniture, then people, then cameras and lights.
- Furniture against a wall sits at the wall's FACE: the face is half the wall's thickness from its line.
- Style a plot by Type and symbol, not by colour or size: leave color, colours, label_size and label_bold alone unless he asks. The plot draws words in ink and marks in three inks by itself, and keeps measurements off on a new plan.
- Say what a lamp IS with name_lamp and what it is DOING in its label (its Note). Several lamps of one kind with one note between them: share_label. A whole-setup note goes in sheet_notes.
- Check the sheet with diagram_picture paper:true — what prints, legend and all.
- One camera per shot: add with "new_shot":true, or "shot":"<id>" for a shot that exists (shots lists them; diagram's `shots` lists this scene's).
- Look at diagram_picture after a change and fix what reads wrong.
- A locked piece (a floor plan picture, say) is clicked straight through in the app and stays put; update set {"locked":false} to work on it.
- undo answers with what it took back ("Move", "Add Light", "Resize", "Turn", "Aim"…), as the app's Undo says.
"#;

impl<F: Films> Server<F> {
    pub(super) fn diagram_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "diagram_guide" => Ok(GUIDE.to_string()),
            "diagram" => (|| {
                let reference = arguments.str_field("scene");
                let doc = self.films.doc()?;
                let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                Ok(plan_json(doc, scene).encode())
            })(),
            "diagram_picture" => self.picture(arguments),
            "diagram_scenes" => self.films.doc().map(|doc| {
                let counts = doc.diagram_counts();
                Json::Array(
                    doc.scenes_with_diagrams()
                        .into_iter()
                        .map(|scene| {
                            let plan = doc.diagram(scene);
                            let of = |k: Kind| plan.els.iter().filter(|e| e.kind == k).count() as f64;
                            Json::object(vec![
                                ("scene", Json::text(scene_number(doc, scene))),
                                ("heading", Json::text(doc.scene_heading(scene).unwrap_or_default())),
                                ("things", Json::Number(counts.get(&scene).copied().unwrap_or(0) as f64)),
                                // Left out of the Diagram's list by hand: see hide_scenes_from_diagrams.
                                ("hidden", Json::Bool(doc.scene_diagram_hidden(scene))),
                                // More than one: see scene_diagrams.
                                ("diagrams", Json::Number(doc.scene_diagram_ids(scene).len() as f64)),
                                ("cameras", Json::Number(of(Kind::Camera))),
                                ("people", Json::Number(of(Kind::Cast))),
                                ("lights", Json::Number(of(Kind::Light))),
                            ])
                        })
                        .collect(),
                )
                .encode()
            }),
            "edit_diagram" => {
                let reference = arguments.str_field("scene");
                let op = match arguments.get("op") {
                    Some(Json::Text(text)) => match ejson::parse(text) {
                        Some(op) => op,
                        None => return Some(Err("That op is not JSON.".into())),
                    },
                    Some(value) => value.clone(),
                    None => return Some(Err("Say what to change: op.".into())),
                };
                self.change("Change Diagram", move |doc| {
                    let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                    let made = doc.diagram_edit(scene, &op).map_err(|e| e.to_string())?;
                    let count = doc.diagram_count(scene);
                    Ok(if made.is_empty() {
                        format!("Done. Scene {reference}'s diagram holds {count}.")
                    } else {
                        format!("Made {}. Scene {reference}'s diagram holds {count}.", made.join(", "))
                    })
                })
            }
            "diagram_library" => Ok(library_json(arguments)),
            "set_frame" => self.set_frame(arguments),
            "point_arrows" => self.point_arrows(arguments),
            "diagram_cast" => (|| {
                let reference = arguments.str_field("scene");
                let doc = self.films.doc()?;
                let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                let (here, film) = doc.diagram_characters(scene);
                let names = |v: Vec<String>| Json::Array(v.into_iter().map(Json::text).collect());
                Ok(Json::object(vec![("in_this_scene", names(here)), ("rest_of_film", names(film))]).encode())
            })(),
            "diagram_favorites" => self.films.doc().map(|doc| favorites_json(doc).encode()),
            "set_diagram_favorite" => {
                let reference = arguments.str_field("scene");
                let id = arguments.str_field("id").trim().to_string();
                let slot = match slot_of(arguments) {
                    Ok(s) => s,
                    Err(e) => return Some(Err(e)),
                };
                self.change("Set Favorite", move |doc| {
                    let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                    if id.is_empty() {
                        doc.set_diagram_favorite(slot, None);
                        return Ok(format!("Favorite {} is empty.", slot + 1));
                    }
                    let piece = doc
                        .diagram(scene)
                        .get(&id)
                        .cloned()
                        .ok_or(format!("Scene {reference}'s diagram has nothing called {id}."))?;
                    doc.set_diagram_favorite_from(slot, scene, Some(&piece));
                    let kept = doc.diagram_favorites().into_iter().nth(slot).flatten().map(|j| favorites::name(&j)).unwrap_or_default();
                    Ok(format!("Favorite {} is {kept}.", slot + 1))
                })
            }
            "place_favorite" => {
                let reference = arguments.str_field("scene");
                let slot = match slot_of(arguments) {
                    Ok(s) => s,
                    Err(e) => return Some(Err(e)),
                };
                let (Some(x), Some(y)) = (number(arguments, "x"), number(arguments, "y")) else {
                    return Some(Err("Say where: x and y, in metres.".into()));
                };
                self.change("Add Favorite", move |doc| {
                    let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                    let fav = doc.diagram_favorites().into_iter().nth(slot).flatten().ok_or(format!("Favorite {} is empty.", slot + 1))?;
                    let op = favorites::placed_op(&fav, x, y).ok_or(format!("Favorite {} is empty.", slot + 1))?;
                    let made = doc.diagram_edit(scene, &op).map_err(|e| e.to_string())?;
                    Ok(format!("Made {} — {}.", made.join(", "), favorites::name(&fav)))
                })
            }
            "copy_diagram" | "send_diagram" => {
                let sending = name == "send_diagram";
                let reference = arguments.str_field("scene");
                let others: Vec<String> = arguments
                    .str_field(if sending { "to" } else { "from" })
                    .split(',')
                    .map(|t| t.trim().to_string())
                    .filter(|t| !t.is_empty())
                    .collect();
                let ids: Vec<String> =
                    arguments.str_field("ids").split(',').map(|t| t.trim().to_string()).filter(|t| !t.is_empty()).collect();
                let said_mode = arguments.str_field("mode");
                let mode = match said_mode.trim() {
                    "" if sending => copy::Mode::Add,
                    m => match copy::Mode::parse(m) {
                        Some(m) => m,
                        None => return Some(Err("mode is \"replace\" or \"add\".".to_string())),
                    },
                };
                let anyway = tools::bool_arg(arguments, "even_if_drawn").unwrap_or(false);
                self.change(if sending { "Send Diagram" } else { "Copy Diagram" }, move |doc| {
                    let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                    if others.is_empty() {
                        return Err(if sending { "Say which scenes: to." } else { "Say which scene: from." }.to_string());
                    }
                    if !sending && others.len() > 1 {
                        return Err("Copy from one scene at a time.".to_string());
                    }
                    let mut found = Vec::new();
                    for other in &others {
                        let id = find_owner(doc, other).ok_or(unknown_owner(other))?;
                        if id == scene {
                            return Err("A scene cannot copy its own diagram onto itself.".to_string());
                        }
                        found.push((other.clone(), id));
                    }
                    let (from, to): (_, Vec<(String, _)>) =
                        if sending { (scene, found) } else { (found[0].1, vec![(reference.clone(), scene)]) };
                    if let Some(bad) = ids.iter().find(|i| doc.diagram(from).get(i).is_none()) {
                        return Err(format!("That diagram has nothing called {bad}."));
                    }
                    if mode == copy::Mode::Replace && !anyway {
                        let drawn: Vec<String> = to
                            .iter()
                            .filter_map(|(n, id)| {
                                let held = doc.diagram_count(*id);
                                (held > 0).then(|| format!("scene {n} has {held} thing{}", plural(held)))
                            })
                            .collect();
                        if !drawn.is_empty() {
                            return Err(format!(
                                "{}, and replacing takes their place. Nothing was changed — ask him, then call again with even_if_drawn=true, or use mode \"add\".",
                                drawn.join("; ")
                            ));
                        }
                    }
                    let targets: Vec<_> = to.iter().map(|(_, id)| *id).collect();
                    let n = doc.diagram_copy(from, &ids, &targets, mode).len() / targets.len().max(1);
                    let names: Vec<&str> = to.iter().map(|(n, _)| n.as_str()).collect();
                    let how = if mode == copy::Mode::Add { "added to" } else { "now on" };
                    Ok(format!("{n} thing{} {how} scene{} {}.", plural(n), plural(names.len()), names.join(", ")))
                })
            }
            "plans" => self.films.doc().map(|doc| {
                let counts = doc.diagram_counts();
                Json::Array(
                    doc.plans_in_order()
                        .into_iter()
                        .map(|p| {
                            Json::object(vec![
                                ("plan", Json::text(doc.plan_name(p))),
                                ("things", Json::Number(counts.get(&p).copied().unwrap_or(0) as f64)),
                            ])
                        })
                        .collect(),
                )
                .encode()
            }),
            "new_plan" => {
                let name = arguments.str_field("name").trim().to_string();
                let from = arguments.str_field("from").trim().to_string();
                self.change("Add Plan", move |doc| {
                    if !name.is_empty() && doc.plan_named(&name).is_some() {
                        return Err(format!("There is a plan called {name} already."));
                    }
                    let source = if from.is_empty() { None } else { Some(find_owner(doc, &from).ok_or(unknown_owner(&from))?) };
                    let plan = doc.add_plan(&name, source);
                    let n = doc.diagram_count(plan);
                    Ok(if source.is_some() {
                        format!("Made the plan {}, a copy of {from}: {n} thing{}.", doc.plan_name(plan), plural(n))
                    } else {
                        format!("Made the plan {}.", doc.plan_name(plan))
                    })
                })
            }
            "rename_plan" | "delete_plan" => {
                let deleting = name == "delete_plan";
                let reference = arguments.str_field("plan").trim().to_string();
                let to = arguments.str_field("name").trim().to_string();
                self.change(if deleting { "Delete Plan" } else { "Rename Plan" }, move |doc| {
                    let plan = doc.plan_named(reference.trim_start_matches("plan:").trim()).ok_or(format!("There is no plan {reference}."))?;
                    if deleting {
                        let n = doc.diagram_count(plan);
                        doc.delete_plan(plan);
                        return Ok(format!("Deleted the plan {reference} and the {n} thing{} on it.", plural(n)));
                    }
                    if to.is_empty() {
                        return Err("Say its new name.".to_string());
                    }
                    if doc.plan_named(&to).is_some_and(|p| p != plan) {
                        return Err(format!("There is a plan called {to} already."));
                    }
                    doc.rename_plan(plan, &to);
                    Ok(format!("{reference} is {to} now."))
                })
            }
            "scene_diagrams" => {
                let reference = arguments.str_field("scene").trim().to_string();
                self.films.doc().and_then(|doc| {
                    let scene = tools::find_scene(doc, &reference).ok_or(format!("There is no scene {reference} in this project."))?;
                    Ok(Json::Array(
                        doc.scene_diagrams(scene)
                            .into_iter()
                            .enumerate()
                            .map(|(i, d)| {
                                Json::object(vec![
                                    ("place", Json::Number((i + 1) as f64)),
                                    ("name", Json::text(d.name)),
                                    ("things", Json::Number(d.count as f64)),
                                ])
                            })
                            .collect(),
                    )
                    .encode())
                })
            }
            "new_scene_diagram" => {
                let reference = arguments.str_field("scene").trim().to_string();
                let name = arguments.str_field("name").trim().to_string();
                let from = arguments.str_field("from").trim().to_string();
                self.change("New Diagram", move |doc| {
                    let scene = tools::find_scene(doc, &reference).ok_or(format!("There is no scene {reference} in this project."))?;
                    let source = if from.is_empty() { None } else { Some(find_owner(doc, &from).ok_or(unknown_owner(&from))?) };
                    let made = doc.add_scene_diagram(scene, &name, source).ok_or(format!("There is no scene {reference} in this project."))?;
                    let place = doc.scene_diagram_ids(scene).iter().position(|x| *x == made).unwrap_or(0) + 1;
                    Ok(format!("Scene {reference} has a diagram {place} now; draw on it with scene = \"{reference} / {place}\"."))
                })
            }
            "rename_scene_diagram" | "move_scene_diagram" | "delete_scene_diagram" => {
                let what = name.to_string();
                let reference = arguments.str_field("diagram").trim().to_string();
                let to = arguments.str_field("name").trim().to_string();
                let place = arguments.get("place").and_then(|v| v.as_f64()).unwrap_or(1.0).max(1.0) as usize;
                self.change(match what.as_str() { "rename_scene_diagram" => "Rename Diagram", "move_scene_diagram" => "Move Diagram", _ => "Delete Diagram" }, move |doc| {
                    let id = find_owner(doc, &reference).filter(|id| doc.get(doc.diagram_scene(*id)).map(|r| r.kind == shotlister_engine::store::Kind::Scene).unwrap_or(false))
                        .ok_or(format!("There is no scene diagram {reference}."))?;
                    match what.as_str() {
                        "rename_scene_diagram" => {
                            doc.rename_scene_diagram(id, &to);
                            Ok(if to.is_empty() { format!("{reference} is unnamed now.") } else { format!("{reference} is {to} now.") })
                        }
                        "move_scene_diagram" => {
                            doc.move_scene_diagram(id, place - 1);
                            Ok(format!("Moved to place {place}."))
                        }
                        _ => {
                            let n = doc.diagram_count(id);
                            if !doc.delete_scene_diagram(id) {
                                return Err("A scene keeps at least one diagram; clear it instead.".to_string());
                            }
                            Ok(format!("Deleted {reference} and the {n} thing{} on it.", plural(n)))
                        }
                    }
                })
            }
            "hide_scenes_from_diagrams" => {
                let said = arguments.str_field("scenes");
                let hide = match arguments.get("hidden") {
                    Some(v) => v.as_bool().unwrap_or_else(|| v.as_str().map(|t| !matches!(t.trim(), "false" | "off" | "no" | "0")).unwrap_or(true)),
                    None => true,
                };
                if said.trim().is_empty() {
                    return Some(self.films.doc().map(|doc| {
                        Json::Array(
                            doc.store()
                                .of_kind(&shotlister_engine::store::Kind::Scene)
                                .iter()
                                .filter(|r| doc.scene_diagram_hidden(r.id))
                                .map(|r| Json::object(vec![("scene", Json::text(scene_number(doc, r.id))), ("heading", Json::text(doc.scene_heading(r.id).unwrap_or_default()))]))
                                .collect(),
                        )
                        .encode()
                    }));
                }
                self.change(if hide { "Hide from Diagrams" } else { "Show in Diagrams" }, move |doc| {
                    let mut ids = Vec::new();
                    for one in said.split(',').map(str::trim).filter(|s| !s.is_empty()) {
                        ids.push(tools::find_scene(doc, one).ok_or(format!("There is no scene {one} in this project."))?);
                    }
                    let n = doc.set_scenes_diagram_hidden(&ids, hide);
                    Ok(match (n, hide) {
                        (0, true) => "Already hidden from the Diagram's list.".to_string(),
                        (0, false) => "None of them was hidden.".to_string(),
                        (n, true) => format!("{n} scene{} hidden from the Diagram's list.", plural(n)),
                        (n, false) => format!("{n} scene{} back in the Diagram's list.", plural(n)),
                    })
                })
            }
            "diagram_everywhere" => {
                let key = arguments.str_field("setting").trim().to_string();
                if key.is_empty() {
                    return Some(Err("Say which setting.".to_string()));
                }
                let value = match arguments.get("value") {
                    Some(Json::Text(t)) => ejson::parse(t.trim()).unwrap_or_else(|| Json::text(t.trim())),
                    Some(other) => other.clone(),
                    None => return Some(Err("Say its value.".to_string())),
                };
                self.change("Plan Setting", move |doc| {
                    let n = doc.diagram_setting_everywhere(&key, value);
                    Ok(format!("{key} is set on {n} scene{}.", plural(n)))
                })
            }
            "room_scans" => (|| {
                let reference = arguments.str_field("scene");
                let at_place = arguments.str_field("location");
                let doc = self.films.doc()?;
                let found = if reference.trim().is_empty() {
                    if at_place.trim().is_empty() {
                        return Err("Say which scene, or which location.".to_string());
                    }
                    let place = super::places::find_location(doc, &at_place)?;
                    scans_of_place(doc, place)
                } else {
                    let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
                    if !doc.is_plan(scene) && doc.scene_locations(scene).is_empty() {
                        return Err(format!("Scene {reference} is not shot at any location yet — set_scene_locations ties it to one."));
                    }
                    scans_at(doc, scene)
                };
                Ok(Json::Array(
                    found
                        .iter()
                        .map(|s| {
                            Json::object(vec![
                                ("location", Json::text(&s.location)),
                                ("scan", Json::text(&s.name)),
                                ("measurements", Json::Bool(s.file.is_some())),
                                ("file", s.file.as_deref().map(Json::text).unwrap_or(Json::Null)),
                            ])
                        })
                        .collect(),
                )
                .encode())
            })(),
            "rename_scan" => (|| {
                let at_place = arguments.str_field("location");
                let from = arguments.str_field("scan").trim().to_string();
                let to = arguments.str_field("name").trim().to_string();
                if from.is_empty() || to.is_empty() {
                    return Err("Say the scan's name now (`scan`) and its new `name`.".to_string());
                }
                self.change("Rename Scan", move |doc| {
                    let place = super::places::find_location(doc, &at_place)?;
                    let names: Vec<String> = doc.scans_of(place).into_iter().map(|s| s.name).collect();
                    let Some(now) = names.iter().find(|n| n.eq_ignore_ascii_case(&from)).cloned() else {
                        let whose = doc.location_full_name(place);
                        return Err(if names.is_empty() {
                            format!("{whose} has no scanned rooms.")
                        } else {
                            format!("{whose} has no scan called {from}. Its scans: {}.", names.join(", "))
                        });
                    };
                    if now == to {
                        return Ok(format!("It is already called {to}."));
                    }
                    if names.iter().any(|n| n != &now && n.eq_ignore_ascii_case(&to)) {
                        return Err(format!("{} already has a scan called {to}.", doc.location_full_name(place)));
                    }
                    if !doc.rename_scan(place, &now, &to) {
                        return Err(format!("{now} could not be renamed."));
                    }
                    Ok(format!("{now} is now {to}."))
                })
            })(),
            "lay_room" => self.lay_room(arguments),
            "floor_picture" => self.floor_picture(arguments),
            _ => return None,
        })
    }

    /// The plan as an SVG, every picture inside it where this host can reach
    /// the film's files. The protocol turns it into a PNG where it can
    /// (`Films::rasterize`, `Server::handle`); the portal does its own.
    fn picture(&self, arguments: &Json) -> Result<String, String> {
        let reference = arguments.str_field("scene");
        let doc = self.films.doc()?;
        let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
        if doc.diagram_count(scene) == 0 {
            return Err(format!("Scene {reference} has no diagram yet."));
        }
        let beat = number(arguments, "beat").map(|b| b.max(1.0) as u32).unwrap_or(1);
        let width = number(arguments, "width").unwrap_or(1200.0).clamp(400.0, 2400.0);
        let paper = tools::bool_arg(arguments, "paper").unwrap_or(false);
        let frame = svg::Frame {
            width,
            // Pictures by name, and the pack by file where the build leaves
            // the pack out; `inline` below, or the portal, makes them whole.
            media: "media/{hash}".into(),
            art: "fso/{id}.png".into(),
            ..Default::default()
        };
        // **Paper is the sheet** (Back to Paper, Batch 2): the page exactly
        // as it prints and as the app shows it — title, north, the plan, its
        // Notes, Legend and Shots — so Claude sees what he hands round.
        let picture = if paper {
            let ask = diagram::sheet::Ask { beat, ..Default::default() };
            let sheet_frame = svg::Frame { fades: false, grid: false, scale_bar: false, ..frame };
            diagram::sheet::svg(doc, scene, &ask, width, &sheet_frame, "d")
        } else {
            let opt = render::Options { beat, tween: 0.0, sel: Vec::new(), paper, scale: 0.0, typing: String::new(), page: false };
            svg::svg(&doc.diagram(scene), &doc.diagram_context(scene), &opt, &frame, "d")
        };
        Ok(inline(&inked(&picture), |name| self.films.media_bytes(name).ok()))
    }

    fn lay_room(&mut self, arguments: &Json) -> Result<String, String> {
        let reference = arguments.str_field("scene");
        let wanted = arguments.str_field("scan").trim().to_string();
        let place = arguments.str_field("location").trim().to_string();
        let (scene, scan) = {
            let doc = self.films.doc()?;
            let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
            let found = scans_at(doc, scene);
            let fits = |s: &&FoundScan| {
                (wanted.is_empty() || s.name.eq_ignore_ascii_case(&wanted))
                    && (place.is_empty() || s.location.to_lowercase().contains(&place.to_lowercase()))
            };
            let scan = found.iter().find(fits).cloned().ok_or_else(|| {
                if found.is_empty() {
                    if doc.is_plan(scene) { "No room has been scanned anywhere in this project.".to_string() }
                    else { format!("No room has been scanned at scene {reference}'s place.") }
                } else {
                    format!(
                        "There is no scan {wanted} there. The scans are {}.",
                        found.iter().map(|s| format!("{} at {}", s.name, s.location)).collect::<Vec<_>>().join(", ")
                    )
                }
            })?;
            (scene, scan)
        };
        // The portal hands the measurements in, having fetched them itself;
        // on a Mac they are read off the film.
        let given = arguments.str_field("measurements");
        let text = if !given.trim().is_empty() {
            given
        } else {
            let file = scan.file.clone().ok_or(format!("The {} scan has its shape but not its measurements, so it cannot be laid.", scan.name))?;
            let bytes = self.films.media_bytes(&file)?;
            String::from_utf8(bytes).map_err(|_| "That scan's measurements could not be read.".to_string())?
        };
        let plan = shotlister_engine::room::read(&text).ok_or("There is no room in that scan.")?;
        let location = scan.place.0.to_string();
        let name = scan.name.clone();
        self.change("Add Room", move |doc| {
            let made = doc.diagram_import_room(scene, &plan, &location);
            Ok(format!("Laid the {name} room on scene {reference}: {} piece{}.", made.len(), plural(made.len())))
        })
    }

    fn floor_picture(&mut self, arguments: &Json) -> Result<String, String> {
        let reference = arguments.str_field("scene");
        let path = arguments.str_field("path").trim().to_string();
        let said = arguments.str_field("attachment").trim().to_string();
        let wide = number(arguments, "width").unwrap_or(5.0).clamp(0.5, 500.0);
        let at = (number(arguments, "x").unwrap_or(0.0), number(arguments, "y").unwrap_or(0.0));
        let over = tools::bool_arg(arguments, "over").unwrap_or(false);
        // The file: one the film already keeps, or one off his disk.
        let (hash, ext, pixels, size, filename) = if !said.is_empty() {
            let doc = self.films.doc()?;
            let mut owner_args = arguments.clone();
            if let Json::Object(pairs) = &mut owner_args {
                pairs.retain(|(k, _)| k != "scene");
            }
            let (owner, whose) = super::media::owner_of(doc, &owner_args, "")?
                .ok_or("Say whose picture: shot, location or board — as attachments lists it.")?;
            let mref = super::media::find_use(doc, owner, &whose, &said)?;
            let media = doc.get(mref).and_then(|r| r.ref_id(f::MEDIA)).ok_or("That attachment has no file.")?;
            let r = doc.get(media).ok_or("That attachment has no file.")?;
            let hex = r.text(f::HASH).unwrap_or_default().to_string();
            let hash = shotlister_engine::hash::Hash256::from_hex(&hex).ok_or("That attachment has no file.")?;
            let filename = r.text(f::FILENAME).unwrap_or("picture").to_string();
            let ext = extension(&filename);
            if !matches!(ext.as_str(), "png" | "jpg" | "jpeg" | "webp" | "gif" | "heic") {
                return Err(format!("{filename} is not a picture."));
            }
            let px = |k| r.get(k).and_then(|v| v.as_int()).unwrap_or(0).max(0) as u32;
            let size = r.get(f::BYTES).and_then(|v| v.as_int()).unwrap_or(0).max(0) as u64;
            (hash, ext, (px(f::WIDTH), px(f::HEIGHT)), size, filename)
        } else if !path.is_empty() {
            let bytes = self.films.read_bytes(&path)?;
            let filename = path.rsplit('/').next().filter(|n| !n.is_empty()).unwrap_or("plan").to_string();
            let ext = extension(&filename);
            let pixels = pixel_size(&bytes).ok_or(format!("{filename} is not a PNG or JPEG picture."))?;
            let hash = shotlister_engine::sha256(&bytes);
            self.films.keep_media(&hash.to_hex(), &ext, &bytes)?;
            (hash, ext, pixels, bytes.len() as u64, filename)
        } else {
            return Err("Say which picture: an attachment the project already has, or a path on his Mac.".into());
        };
        self.change("Add Picture", move |doc| {
            let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
            let id = doc
                .diagram_add_image(scene, hash, &ext, pixels, size, &filename, at, wide, over)
                .ok_or("The picture could not be laid on the plan.")?;
            Ok(format!("Laid {filename} {} scene {reference}'s plan, {wide} m wide: {id}.", if over { "on" } else { "under" }))
        })
    }
}

/// The plan as `diagram` answers it: every piece, a camera with its shot's
/// number and focal length, the settings, and this scene's shots.
fn plan_json(doc: &Doc, scene: Id) -> Json {
    let plan = doc.diagram(scene);
    let ctx = doc.diagram_context(scene);
    let looks = diagram::plot::looks(&plan);
    let legend = diagram::plot::legend(&plan);
    let mut els = Vec::new();
    for e in &plan.els {
        let mut j = e.to_json();
        // Set or Plot (Ref 1498): the layer the app draws and picks it in.
        if let Json::Object(pairs) = &mut j {
            pairs.push(("layer".into(), Json::text(diagram::layer(e))));
        }
        // **Name and Note** (Back to Paper, Batch 2): a lamp's Name is its
        // symbol's (`name_lamp`), its legend line's key, and the two lines
        // its label writes — Name, then Note, gels and Off — as typed.
        if let (Some((_, look)), Json::Object(pairs)) = (looks.iter().find(|(id, _)| *id == e.id), &mut j) {
            // Its own Name, as typed (2026-10-15); its legend line.
            let key = legend.iter().find(|x| x.ids.contains(&e.id)).map(|x| x.key.clone()).unwrap_or_else(|| diagram::plot::look_key(look));
            let name = diagram::plot::lamp_name(e);
            let (first, under) = render::lamp_lines(e, &name, plan.settings.counts);
            pairs.retain(|(k, _)| k != "lamp_name");
            pairs.push(("legend_key".into(), Json::text(&key)));
            pairs.push(("lamp_name".into(), Json::text(&name)));
            pairs.push(("label_lines".into(), Json::Array(vec![Json::text(&first), Json::text(&under)])));
        }
        // A frame's two lines (2026-10-05): its size and cloth, its Note.
        if let (true, Json::Object(pairs)) = (diagram::frame::is_frame(e), &mut j) {
            let (first, under) = render::frame_lines(e, plan.settings.counts);
            pairs.push(("label_lines".into(), Json::Array(vec![Json::text(&first), Json::text(&under)])));
        }
        // Its steps lettered, so Claude reads A, B, C as he sees them.
        if let (Some(seq), Json::Object(pairs)) = (e.seq_json(), &mut j) {
            pairs.push(("seq".into(), seq));
        }
        if e.kind == Kind::Camera {
            if let Json::Object(pairs) = &mut j {
                // What its cone is worked out from (`render::camera_optics`).
                let o = render::camera_optics(e, &ctx);
                pairs.push(("name".into(), Json::text(render::camera_name(e, &ctx))));
                pairs.push(("focal".into(), Json::Number(o.focal)));
                pairs.push(("view_degrees".into(), Json::Number((o.aov * 10.0).round() / 10.0)));
                pairs.push(("camera".into(), Json::text(&o.unit_label)));
                pairs.push(("lens_said".into(), Json::text(&o.lens)));
                if let Some((lo, hi)) = o.zoom {
                    pairs.push(("zoom_mm".into(), Json::Array(vec![Json::Number(lo), Json::Number(hi)])));
                }
                pairs.push(("sensor_name".into(), Json::text(if o.sensor_set { o.gate.name.as_str() } else { "Super 35 (no sensor set)" })));
                pairs.push(("sensor_mm".into(), Json::Array(vec![Json::Number(o.gate.w), Json::Number(o.gate.h)])));
                pairs.push(("squeeze_used".into(), Json::Number(o.squeeze)));
            }
        }
        els.push(j);
    }
    let here: Vec<String> = doc
        .placements_in_scene(scene)
        .iter()
        .filter_map(|p| doc.get(*p).and_then(|r| r.ref_id(f::SHOT)).map(|x| x.0.to_string()))
        .collect();
    let mut whole = plan.to_json();
    if let Json::Object(pairs) = &mut whole {
        pairs.retain(|(k, _)| k != "els" && k != "view");
        pairs.insert(0, ("els".into(), Json::Array(els)));
        // The names as kept (a mark's, a colour's) under their own word: `legend`
        // below is the sheet's, the marks in use — one key, never two.
        for (k, _) in pairs.iter_mut() {
            if k == "legend" {
                *k = "legend_names".into();
            }
        }
        // What each colour on the sheet means.
        pairs.push((
            "legend_colours".into(),
            Json::Array(
                shotlister_engine::diagram::plot::colour_rows(&plan)
                    .into_iter()
                    .map(|(role, name, _)| Json::object(vec![("role", Json::text(&role)), ("means", Json::text(&name))]))
                    .collect(),
            ),
        ));
        // The sheet's legend: each kind of lamp, its mark and how many.
        pairs.push((
            "legend".into(),
            Json::Array(
                shotlister_engine::diagram::plot::legend(&plan)
                    .into_iter()
                    .map(|x| {
                        Json::object(vec![
                            ("key", Json::text(&x.key)),
                            ("name", Json::text(&x.name)),
                            ("mark", Json::text(&x.look.mark.as_str())),
                            // The ink each mark is drawn in by default: three inks (Back to Paper).
                            ("ink", Json::text(match x.look.ink { "added" => "red", "ink" => "grey", o => o })),
                            ("solid", Json::Bool(x.look.solid)),
                            ("count", Json::Number(x.count as f64)),
                            ("named", Json::Bool(x.named)),
                            // Its lamps.
                            ("ids", Json::Array(x.ids.iter().map(|id| Json::text(id)).collect())),
                        ])
                    })
                    .collect(),
            ),
        ));
        pairs.push((
            "shots".into(),
            Json::Array(
                ctx.shots
                    .iter()
                    .filter(|(id, _, _)| here.contains(id))
                    .map(|(id, number, lens)| Json::object(vec![("id", Json::text(id)), ("number", Json::text(number)), ("lens", Json::text(lens))]))
                    .collect(),
            ),
        ));
        // The film's Lens list, for a camera with no shot.
        pairs.push(("lenses".into(), Json::Array(doc.vocabulary("lens").iter().map(|v| Json::text(v)).collect())));
        // **The sheet** it prints on (Back to Paper, Batch 2), every setting
        // said, defaults too; and the gear it counts (Copy › Gear List).
        let st = &plan.settings;
        pairs.push((
            "sheet".into(),
            Json::object(vec![
                ("paper", Json::text(&st.paper)),
                ("orientation", Json::text(&st.orientation)),
                ("legend", Json::Bool(st.legend)),
                ("notes", Json::Bool(st.notes)),
                ("sheet_notes", Json::text(&st.sheet_notes)),
                ("scale_bar", Json::Bool(st.scale_bar)),
                ("fabric", Json::Bool(st.fabric)),
                ("measures", Json::Bool(st.measures)),
            ]),
        ));
        pairs.push((
            "gear".into(),
            Json::Array(
                diagram::sheet::gear(&plan)
                    .into_iter()
                    .map(|g| Json::object(vec![("group", Json::text(g.group)), ("name", Json::text(&g.name)), ("count", Json::Number(g.count as f64))]))
                    .collect(),
            ),
        ));
    }
    whole
}

fn favorites_json(doc: &Doc) -> Json {
    Json::Array(
        doc.diagram_favorites()
            .into_iter()
            .enumerate()
            .map(|(i, slot)| {
                let mut o = vec![("slot", Json::Number((i + 1) as f64))];
                match slot {
                    Some(fav) => {
                        o.push(("name", Json::text(favorites::name(&fav))));
                        o.push(("piece", fav));
                    }
                    None => o.push(("name", Json::Null)),
                }
                Json::object(o)
            })
            .collect(),
    )
}

/// The library, whole — or only what was asked for, by library, section,
/// maker or words (the app's own search, nicknames and all).
fn library_json(arguments: &Json) -> String {
    let [lib, kind, maker, search] = ["library", "kind", "maker", "search"].map(|k| arguments.str_field(k).trim().to_lowercase());
    if lib.is_empty() && kind.is_empty() && maker.is_empty() && search.is_empty() {
        return diagram::wire::library();
    }
    Json::Array(
        diagram::symbols::offered()
            .into_iter()
            .filter(|(_, name, group, _, _, p)| {
                (lib.is_empty() || p.lib == lib)
                    && (kind.is_empty() || p.kind.to_lowercase() == kind)
                    && (maker.is_empty() || p.maker.to_lowercase().contains(&maker))
                    && (search.is_empty() || diagram::library::matches(&search, name, group, p))
            })
            .map(|(id, name, group, w, h, p)| {
                Json::object(vec![
                    ("id", Json::text(id)),
                    ("name", Json::text(name)),
                    ("group", Json::text(group)),
                    ("library", Json::text(p.lib)),
                    ("kind", Json::text(p.kind)),
                    ("maker", Json::text(p.maker)),
                    ("w", Json::Number((w * 1000.0).round() / 1000.0)),
                    ("h", Json::Number((h * 1000.0).round() / 1000.0)),
                ])
            })
            .collect(),
    )
    .encode()
}

impl<F: Films> Server<F> {
    /// **Arrows that stay attached** (SL-1231): one from `from` to each of
    /// `to`, both ends pinned, one undo step.
    fn point_arrows(&mut self, arguments: &Json) -> Result<String, String> {
        let reference = arguments.str_field("scene");
        let from = arguments.str_field("from").trim().to_string();
        let to: Vec<String> = arguments.str_field("to").split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
        if from.is_empty() || to.is_empty() {
            return Err("Say which piece the arrows leave (from) and which they point at (to).".into());
        }
        let dashed = arguments.get("dashed").and_then(|d| d.as_bool()) == Some(true) || arguments.str_field("dashed") == "true";
        self.change("Add Arrows", move |doc| {
            let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
            let plan = doc.diagram(scene);
            let at = |id: &str| -> Result<(f64, f64), String> {
                match plan.get(id) {
                    Some(e) if e.kind == Kind::Arrow => Err(format!("{id} is an arrow.")),
                    Some(e) => Ok(e.centre()),
                    None => Err(format!("Nothing called {id} on scene {reference}'s plan.")),
                }
            };
            let a = at(&from)?;
            let mut els = Vec::new();
            for t in &to {
                if *t == from {
                    return Err("An arrow cannot point at the piece it leaves.".into());
                }
                let b = at(t)?;
                let mut el = vec![
                    ("kind", Json::text("arrow")),
                    ("x", Json::Number(a.0)),
                    ("y", Json::Number(a.1)),
                    ("x2", Json::Number(b.0)),
                    ("y2", Json::Number(b.1)),
                    ("head", Json::text("end")),
                    ("start_on", Json::text(&from)),
                    ("end_on", Json::text(t)),
                ];
                if dashed {
                    el.push(("dash", Json::text("dashed")));
                }
                els.push(Json::object(el));
            }
            let op = Json::object(vec![("op", Json::text("add")), ("els", Json::Array(els))]);
            let made = doc.diagram_edit(scene, &op).map_err(|e| e.to_string())?;
            Ok(format!("Made {}.", made.join(", ")))
        })
    }

    /// A frame dressed by name: its skin, pipe, grid, tilt and size, one
    /// undo step, refused with the choices when a name is not one.
    fn set_frame(&mut self, arguments: &Json) -> Result<String, String> {
        use diagram::frame;
        let reference = arguments.str_field("scene");
        let ids: Vec<String> = arguments.str_field("id").split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
        if ids.is_empty() {
            return Err("Say which frame: id.".into());
        }
        let mut set: Vec<(&str, Json)> = Vec::new();
        let material = arguments.str_field("material").trim().to_lowercase();
        if !material.is_empty() {
            let found = frame::MATERIALS.iter().find(|m| m.0 == material || m.1.to_lowercase() == material);
            let Some(m) = found else {
                let all: Vec<&str> = frame::MATERIALS.iter().map(|m| m.0).collect();
                return Err(format!("No material {material}. The materials: {}.", all.join(", ")));
            };
            set.push(("material", Json::text(m.0)));
        }
        let pipe = arguments.str_field("frame_type").trim().to_lowercase();
        if !pipe.is_empty() {
            let found = frame::PIPES.iter().find(|p| p.0 == pipe || p.1.to_lowercase() == pipe);
            let Some(p) = found else {
                let all: Vec<&str> = frame::PIPES.iter().map(|p| p.0).collect();
                return Err(format!("No frame type {pipe}. The frame types: {}.", all.join(", ")));
            };
            set.push(("pipe", Json::text(p.0)));
        }
        if let Some(g) = number(arguments, "grid") {
            if g != 0.0 && !frame::GRIDS.contains(&g) {
                return Err("A grid is 0 (none), 20, 30, 40, 45, 50 or 60.".into());
            }
            set.push(("grid", Json::Number(g)));
        }
        if let Some(t) = number(arguments, "tilt") {
            if !(0.0..=90.0).contains(&t) {
                return Err("Tilt is 0 (lying flat) to 90 (standing).".into());
            }
            set.push(("tilt", Json::Number((t / 5.0).round() * 5.0)));
        }
        for (arg, field) in [("width", "h"), ("height", "tall")] {
            if let Some(m) = number(arguments, arg) {
                if !(0.05..=frame::LARGEST).contains(&m) {
                    return Err(format!("A frame's {arg} is 0.05 to {} metres.", frame::LARGEST));
                }
                set.push((field, Json::Number(m)));
            }
        }
        let gel = arguments.str_field("gel").trim().to_string();
        if !gel.is_empty() {
            set.push(("gels", Json::Array(vec![Json::text(&gel)])));
        }
        let color = arguments.str_field("color").trim().to_string();
        if !color.is_empty() {
            set.push(("color", Json::text(&color)));
        }
        // Its Note, typed (his note, 2026-10-05).
        if arguments.get("note").is_some() {
            set.push(("label", Json::text(arguments.str_field("note").trim())));
        }
        if set.is_empty() {
            return Err("Say what to change: material, frame_type, grid, tilt, width, height, gel, color or note.".into());
        }
        let op = Json::object(vec![
            ("op", Json::text("update")),
            ("ids", Json::Array(ids.iter().map(|i| Json::text(i)).collect())),
            ("set", Json::object(set)),
        ]);
        self.change("Change Frame", move |doc| {
            let scene = find_owner(doc, &reference).ok_or(unknown_owner(&reference))?;
            let plan = doc.diagram(scene);
            for id in &ids {
                match plan.els.iter().find(|e| &e.id == id) {
                    Some(e) if frame::is_frame(e) => {}
                    Some(_) => return Err(format!("{id} is not a frame.")),
                    None => return Err(format!("Nothing called {id} on scene {reference}'s plan.")),
                }
            }
            doc.diagram_edit(scene, &op).map_err(|e| e.to_string())?;
            let plan = doc.diagram(scene);
            let names: Vec<String> = ids.iter().filter_map(|id| plan.els.iter().find(|e| &e.id == id)).map(frame::plan_name).collect();
            Ok(format!("Done: {}.", names.join(", ")))
        })
    }
}

/// A favorite slot as Claude says it, 1–9, as the engine counts it, 0–8.
fn slot_of(arguments: &Json) -> Result<usize, String> {
    match number(arguments, "slot") {
        Some(n) if (1.0..=9.0).contains(&n) && n.fract() == 0.0 => Ok(n as usize - 1),
        _ => Err("A favorite slot is 1 to 9.".into()),
    }
}

fn number(arguments: &Json, key: &str) -> Option<f64> {
    match arguments.get(key) {
        Some(Json::Number(n)) if n.is_finite() => Some(*n),
        Some(Json::Text(t)) => t.trim().parse::<f64>().ok().filter(|n| n.is_finite()),
        _ => None,
    }
}

fn plural(n: usize) -> &'static str {
    if n == 1 {
        ""
    } else {
        "s"
    }
}

fn scene_number(doc: &Doc, scene: Id) -> String {
    doc.get(scene).and_then(|r| r.text(f::NUMBER)).unwrap_or_default().to_string()
}

fn extension(filename: &str) -> String {
    filename.rsplit_once('.').map(|(_, e)| e.to_lowercase()).unwrap_or_else(|| "png".into())
}

/// One scan at one of a scene's places, and the file its measurements are
/// kept under — `<hash>.<ext>`, the name the film's pictures go by.
#[derive(Clone)]
struct FoundScan {
    place: Id,
    location: String,
    name: String,
    file: Option<String>,
}

/// **A scene by number, or a loose plan by name** — every diagram tool's
/// `scene`. `plan: <name>` says it is a plan when a name could be read as a
/// scene's number.
fn find_owner(doc: &Doc, reference: &str) -> Option<Id> {
    let r = reference.trim();
    if let Some(name) = r.strip_prefix("plan:") {
        return doc.plan_named(name.trim());
    }
    // One of a scene's diagrams: "5 / Reverse", "5 / 2".
    if let Some((scene, which)) = r.rsplit_once(" / ") {
        if let Some(scene) = tools::find_scene(doc, scene.trim()) {
            let all = doc.scene_diagrams(scene);
            let which = which.trim();
            return match which.parse::<usize>() {
                Ok(n) if n >= 1 && n <= all.len() && !all.iter().any(|d| d.name == which) => Some(all[n - 1].id),
                _ => all.iter().find(|d| d.name.eq_ignore_ascii_case(which) || d.title.eq_ignore_ascii_case(which)).map(|d| d.id),
            };
        }
    }
    tools::find_scene(doc, r).or_else(|| doc.plan_named(r))
}

fn unknown_owner(reference: &str) -> String {
    format!("There is no scene or plan {reference} in this project.")
}

/// The rooms scanned where a scene is shot — on a loose plan, every scan in
/// the film (his ruling, 2026-10-01: any 3D scan can go on one).
fn scans_at(doc: &Doc, scene: Id) -> Vec<FoundScan> {
    let places = if doc.is_plan(scene) { doc.locations_in_order() } else { doc.scene_locations(scene) };
    scans_in(doc, places)
}

/// One location's scanned rooms.
fn scans_of_place(doc: &Doc, place: Id) -> Vec<FoundScan> {
    scans_in(doc, vec![place])
}

fn scans_in(doc: &Doc, places: Vec<Id>) -> Vec<FoundScan> {
    let mut out = Vec::new();
    for place in places {
        let location = doc.location_full_name(place);
        for scan in doc.scans_of(place) {
            let file = scan.plan.and_then(|m| doc.get(m)).and_then(|r| {
                let hex = r.text(f::HASH)?;
                let ext = extension(r.text(f::FILENAME).unwrap_or("room.json"));
                Some(format!("{}.{ext}", &hex[..hex.len().min(32)]))
            });
            out.push(FoundScan { place, location: location.clone(), name: scan.name, file });
        }
    }
    out
}

/// **The colours, inside the picture.** The plan names its inks by role
/// (`var(--d-wall)`) so the Mac and the portal can each paint their own; a
/// picture that travels alone carries the paper palette with it.
fn inked(picture: &str) -> String {
    let Some(end) = picture.find('>') else { return picture.to_string() };
    let roles: String = svg::PAPER.iter().map(|(role, hex)| format!("--d-{role}:{hex};")).collect();
    format!("{}<style>svg{{{roles}}}</style>{}", &picture[..=end], &picture[end + 1..])
}

/// Every `href="media/<name>"` the plan names, made whole from the film's
/// own files where this host has them; the rest are left for the portal.
fn inline(picture: &str, mut bytes_of: impl FnMut(&str) -> Option<Vec<u8>>) -> String {
    const AT: &str = "href=\"media/";
    let mut out = String::with_capacity(picture.len());
    let mut rest = picture;
    while let Some(i) = rest.find(AT) {
        let (before, after) = rest.split_at(i);
        out.push_str(before);
        let tail = &after[AT.len()..];
        let Some(end) = tail.find('"') else {
            out.push_str(after);
            rest = "";
            break;
        };
        let name = &tail[..end];
        match bytes_of(name) {
            Some(bytes) => {
                let mime = match extension(name).as_str() {
                    "jpg" | "jpeg" => "image/jpeg",
                    "webp" => "image/webp",
                    "gif" => "image/gif",
                    _ => "image/png",
                };
                out.push_str(&format!("href=\"data:{mime};base64,{}\"", shotlister_engine::export::share::base64(&bytes)));
            }
            None => out.push_str(&after[..AT.len() + end + 1]),
        }
        rest = &tail[end + 1..];
    }
    out.push_str(rest);
    out
}

/// A PNG's or JPEG's size in pixels, read off its header.
fn pixel_size(b: &[u8]) -> Option<(u32, u32)> {
    if b.len() > 24 && b.starts_with(&[0x89, b'P', b'N', b'G']) {
        let w = u32::from_be_bytes(b[16..20].try_into().ok()?);
        let h = u32::from_be_bytes(b[20..24].try_into().ok()?);
        return Some((w, h));
    }
    if b.len() > 4 && b[0] == 0xFF && b[1] == 0xD8 {
        let mut i = 2;
        while i + 9 < b.len() {
            if b[i] != 0xFF {
                i += 1;
                continue;
            }
            let marker = b[i + 1];
            let len = u16::from_be_bytes([b[i + 2], b[i + 3]]) as usize;
            if (0xC0..=0xCF).contains(&marker) && !matches!(marker, 0xC4 | 0xC8 | 0xCC) {
                let h = u16::from_be_bytes([b[i + 5], b[i + 6]]) as u32;
                let w = u16::from_be_bytes([b[i + 7], b[i + 8]]) as u32;
                return Some((w, h));
            }
            i += 2 + len;
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_picture_named_by_the_plan_is_made_whole_and_a_missing_one_is_left() {
        let svg = r#"<svg><image href="media/abc.png"/><image href="media/gone.jpg"/></svg>"#;
        let out = inline(svg, |n| (n == "abc.png").then(|| vec![1, 2, 3]));
        assert!(out.contains(r#"href="data:image/png;base64,AQID""#), "{out}");
        assert!(out.contains(r#"href="media/gone.jpg""#), "{out}");
        assert!(out.ends_with("</svg>"));
    }

    #[test]
    fn a_png_and_a_jpeg_say_their_size() {
        let mut png = vec![0x89, b'P', b'N', b'G', 13, 10, 26, 10, 0, 0, 0, 13, b'I', b'H', b'D', b'R'];
        png.extend_from_slice(&640u32.to_be_bytes());
        png.extend_from_slice(&480u32.to_be_bytes());
        png.extend_from_slice(&[8, 6, 0, 0, 0]);
        assert_eq!(pixel_size(&png), Some((640, 480)));
        let jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8, 0, 200, 1, 44, 3, 0, 0];
        assert_eq!(pixel_size(&jpeg), Some((300, 200)));
        assert_eq!(pixel_size(b"not a picture at all"), None);
    }
}
