/**
 * **The Camera Spec Sheet, from the AI connector** (Ref 1627, 2026-10-08).
 *
 * The sheets live in Notion, one per shoot (`kit.js` says why and how).
 * These read them as the portal last did, and change them the way Shotlister
 * does: an `edit_spec_sheet` on the record's pending list, which the Studio
 * writes into Notion after checking nothing moved since it was read. The
 * film's own half — the kit taken into its Lens list and cameras, and the
 * shots off it — is the engine's (`mcp/src/server/kit.rs`: `kit`,
 * `take_kit`); `take_kit` with no kit is filled from here.
 */
import { SHEET_FIELDS, SHEET_WORDS, kitHere, changeSheet, kitForFilm, sheetNamed } from "./kit.js";
import { readLibrary, libraryView, changeLibrary, entryOfSheetLens } from "./lenslibrary.js";
import { readModes, modesView, changeModes } from "./sensormodes.js";
import { readExtras, extrasView, changeExtras } from "./kitlibrary.js";
import { framesOf, ratioOnCard } from "./specsheet.js";

const BY = "portal AI connector";
// modifiers and filters: a sheet on the project record only (kitlibrary.js)
const BOXES = [...Object.keys(SHEET_FIELDS), "modifiers", "filters"];

export const KIT_TOOLS = [
  {
    name: "spec_sheet",
    description: "The open project's Camera Spec Sheets, one per shoot, as the portal last read them from Notion: every box (" + BOXES.join(", ") + "; each is a set of Notion pills, one per line), the lenses (each pill a lens named in full, \"Master Prime 25mm\") and the cameras by label and body (the label, \"A Cam\", is the project record's, not Notion's), which shoot leads, and any change still on its way to Notion (`waiting`). `shoot` narrows it to one (its name, \"2\" for Shoot 2, or its id). A sheet kept on the project record (`kept_on`) also gives `sheet`: every camera with all of its own values (label, body, format, capture, fps, codec, colour, desqueeze, luts: each LUT's `url` is its Drive link, what the console's LUT click opens) and the shoot's one Lenses pool (each lens its full name and an optional note), and its Modifiers (extenders, expanders, diopters) and Filters pools, what the shoot carries, never tied to a lens: a shot picks which it uses; its boxes are labelled lines, \"A Cam: ProRes 4444\" where the cameras differ. It also gives `aspect_ratios` (the sheet's frames: name, ratio, one `main`, the one the portal shows, and each one's frame guide `guides`: name, camera, note, url; no resolution) and `finishing_resolutions` (the deliverables: title, resolution, note; a shoot's own list, else the project sheet's). Capture resolution is each camera's `capture`, from its sensor mode. A camera has no finishing resolution or frame guides of its own: those are the two lists.",
    inputSchema: { type: "object", properties: { shoot: { type: "string" } }, required: [] },
  },
  {
    name: "set_spec_sheet",
    description: "Change boxes of one shoot's Camera Spec Sheet: `changes` is {box: text}, boxes " + BOXES.join(", ") + " (one pill per line; a pill Notion has not seen becomes a new option; on `body`, \"A Cam: Alexa 35\" puts the label on the project record and only the body in Notion). Give `seen` — {box: text as you read it} — so a box changed since is refused rather than written over. A sheet kept in Notion: the Studio writes it within a minute or two, shown as waiting until then. A sheet kept on the project record: written at once; a labelled line (\"B Cam: XAVC-I\") is that camera's, an unlabelled one every camera's; on `body` a new label adds a camera (a copy of the first); on `lenses`, `modifiers` and `filters` a note goes after a middle dot (\"Canon 8-64mm · A Cam only\"); `modifiers` and `filters` only on a sheet kept on the project record. `shoot` as in spec_sheet; left out, the lead shoot's. `sensor_mode` {camera, mode} (a sheet on the project record only, sent on its own): picks a mode from `sensor_modes` for that camera (\"B Cam\"), or for every camera with `camera` left out, each camera taking its own body's mode of that name (refused when a camera's body has none): its Shooting Format becomes the mode's name and it takes the mode's size and capture resolution (the capture resolution stays editable on that camera through `changes`). `aspect_ratio` (a sheet on the project record only, sent on its own) is one change to its aspect ratios: {op: \"add_frame\", frame: {name, ratio}}, {op: \"frame\", at, name?, ratio?}, {op: \"remove_frame\", at}, {op: \"main_frame\", at}, or on its frame guide files {op: \"add_guide\", at, guide: {url, name?, camera?, note?}} (a link to a guide file that is already in Drive or on the web; a new file from his Mac is added in Projects Console, which puts it in the project's Drive folder), {op: \"guide\", at, i, name?, camera?, note?} and {op: \"remove_guide\", at, i}. `finishing_resolution` (the same) is one change to its Finishing Resolutions: {op: \"add_finishing\", entry: {title, resolution, note}}, {op: \"finishing\", at, title?, resolution?, note?} or {op: \"remove_finishing\", at}.",
    inputSchema: {
      type: "object",
      properties: {
        shoot: { type: "string" },
        changes: { type: "object" },
        seen: { type: "object" },
        sensor_mode: { type: "object", properties: { camera: { type: "string" }, mode: { type: "string" } }, required: ["mode"] },
        aspect_ratio: { type: "object" },
        finishing_resolution: { type: "object" },
      },
      required: [],
    },
  },
  {
    name: "add_to_spec_sheet",
    description: "Put a lens or a camera a shot uses onto a shoot's Camera Spec Sheet — Shotlister's Add to Spec Sheet: `lens` goes on under Lenses as the studio's lens library names it (`lens_library`): \"27mm\" becomes \"Master Prime 27mm\" when one library lens of that focal fits, or the one in a set the sheet already has (when several fit you are told the choices); a set's name adds every lens in it, a set sold whole one entry; a lens the library does not know goes on as said; `camera` (a body, \"Sony FX6\") as a pill under Camera, with `label` (\"B Cam\") kept on the project record when given. Never automatic: ask him first, since a shot's lens can be a wish or a typo and the sheet goes to the rental house. `kit` lists what is off the sheet and which shoot's.",
    inputSchema: {
      type: "object",
      properties: {
        shoot: { type: "string" },
        lens: { type: "string" },
        modifier: { type: "string" },
        filter: { type: "string" },
        camera: { type: "string" },
        label: { type: "string" },
      },
      required: [],
    },
  },
];

export const KIT_TOOL_NAMES = new Set(KIT_TOOLS.map((t) => t.name));

/**
 * **The studio's two libraries** (phase 2, lenslibrary.js and sensormodes.js):
 * one for every project, so they need no open film. Anyone signed in reads
 * them; only he changes them. Any change can be a look first (`look: true`),
 * which says what would happen and writes nothing.
 */
const OPS = { type: "array", items: { type: "object" } };
export const LIBRARY_TOOLS = [
  {
    name: "lens_library",
    description: "The studio's lens library, one for every project: each set (\"ARRI Master Primes\") with its lenses in order, each lens its full name (\"Master Prime 25mm\"), focal length or range (\"25\", \"8-64\") and stop (\"T1.3\"), and its close focus when set (`close_focus` as he typed it, \"0.35 m\" or \"1'2\\\"\", and `close_focus_m`, the same in metres, when it reads as a distance; shown as \"CF 0.35 m\"); sets sold whole with no focal lengths on record (Tribe7 Blackwings) are marked `whole` and go on a sheet as one entry; then lenses on their own (zooms). `v` is its version, for `set_lens_library`. Names are always written in full.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_lens_library",
    description: "Change the studio's lens library (his alone). `ops` is a list, applied in order, all or none: {op:\"add\", name, focal, stop, set, close_focus} (a set named that does not exist is made), {op:\"add_set\", name, whole}, {op:\"rename\", id, name}, {op:\"edit\", id, focal, stop, close_focus} (close_focus \"\" clears it) (or {op:\"edit\", id, whole} on an empty set), {op:\"move\", id, set} (set \"\" for a lens on its own), {op:\"merge\", keep, drop} (two entries that are the same lens; sheets pointing at the dropped one still find it), {op:\"remove\", id} (refused while any spec sheet uses it). `id` is an id or the current name. A rename never changes a sheet already written: the sheet keeps the name it had. `look: true` answers what it would become and writes nothing; otherwise give `base`, the `v` you read, so a change made since is refused.",
    inputSchema: { type: "object", properties: { ops: OPS, base: { type: "number" }, look: { type: "boolean" } }, required: ["ops"] },
  },
  {
    name: "kit_extras",
    description: "The studio's modifiers and filters, one library for every project, beside the lens library: `modifiers` (extenders, expanders, diopters, each its full name, \"Atlas LF Extender 1.6x\", and `kind`), filter `sets` (a family at one size, \"Tiffen ND\" · \"4x5.65\", with its filters, each named in full, \"Tiffen ND .6\"), and filters `alone` with their own size. A spec sheet carries some of them for the shoot; a shot picks which it uses. `v` is its version.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_kit_extras",
    description: "Change the studio's modifiers and filters (his alone). `ops`, in order, all or none: {op:\"add_modifier\", name, kind} (kind extender, expander, diopter or other; read from the name when left out), {op:\"add_set\", name, size, strengths:[\".3\", \".6\"]} (a filter per strength, named \"<set> <strength>\"), {op:\"add_filter\", name, set, size} (into a set, or alone with its size), {op:\"rename\", id, name}, {op:\"edit\", id, kind|size}, {op:\"move\", id, set}, {op:\"remove\", id} (refused while any spec sheet carries it). Never invent a filter or a size: only as he gives them. `look: true` writes nothing; otherwise give `base`, the `v` you read.",
    inputSchema: { type: "object", properties: { ops: OPS, base: { type: "number" }, look: { type: "boolean" } }, required: ["ops"] },
  },
  {
    name: "sensor_modes",
    description: "The studio's sensor modes, one list for every project, each belonging to a camera body (`body`, the Camera pill, e.g. \"Alexa Mini LF\"): a name (\"Open Gate\") unique within its body that stands for a size, width and height in millimetres, and a capture resolution (\"4448 x 3096\"). `bodies` lists each body with its modes. A camera's Shooting Format on a spec sheet is the name of one of its own body's modes; a camera is never given another body's mode. `needing_size` lists modes with no millimetres typed yet: never guess them, ask him. `v` is its version.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_sensor_modes",
    description: "Change the studio's sensor modes (his alone). `ops`, in order, all or none: {op:\"add\", body, name, width, height, capture} (body required), {op:\"edit\", id, body, width, height, capture} (\"\" clears a size; body moves it to another camera), {op:\"rename\", id, name}, {op:\"merge\", keep, drop}, {op:\"remove\", id} (refused while any spec sheet uses it). Millimetres only as he gives them. `look: true` writes nothing; otherwise give `base`, the `v` you read.",
    inputSchema: { type: "object", properties: { ops: OPS, base: { type: "number" }, look: { type: "boolean" } }, required: ["ops"] },
  },
];
export const LIBRARY_TOOL_NAMES = new Set(LIBRARY_TOOLS.map((t) => t.name));

/** The libraries' four. `admin` is whether the one asking is him. */
export async function libraryTool(env, name, args, refuse, admin) {
  if (name === "lens_library") {
    const got = await readLibrary(env);
    return JSON.stringify({ ...libraryView(got.library), ...(got.seeded ? { seeded: "from the ten moved spec sheets; nothing written yet" } : {}) }, null, 1);
  }
  if (name === "sensor_modes") {
    const got = await readModes(env);
    return JSON.stringify({ ...modesView(got.modes), ...(got.seeded ? { seeded: "from his Mac's preset and the moved spec sheets; nothing written yet" } : {}) }, null, 1);
  }
  if (name === "kit_extras") {
    const got = await readExtras(env);
    return JSON.stringify({ ...extrasView(got.extras), ...(got.seeded ? { seeded: "from the moved spec sheets; nothing written yet" } : {}) }, null, 1);
  }
  if (!admin) throw refuse("Only he changes the studio's libraries.");
  const asked = { ops: args.ops, base: args.base, look: args.look === true, by: BY };
  if (!asked.look && asked.base === undefined) throw refuse("Give `base`, the `v` you read, or `look: true` first.");
  const got = name === "set_lens_library" ? await changeLibrary(env, asked) : name === "set_sensor_modes" ? await changeModes(env, asked) : name === "set_kit_extras" ? await changeExtras(env, asked) : null;
  if (!got) throw refuse("No such tool.");
  if (got.status !== 200) throw refuse(`Nothing written. ${got.why}`);
  return JSON.stringify({ written: got.written, said: got.said, ...(got.library ? { library: got.library } : got.extras ? { extras: got.extras } : { modes: got.modes }) }, null, 1);
}

function sheetSaid(one, library = null) {
  // each lens's close focus, off the library, only when set (2026-10-15)
  const withCf = (sheet) => (!library ? sheet : { ...sheet, lenses: (sheet.lenses || []).map((l) => {
    const hit = entryOfSheetLens(library, l);
    return hit && hit.close_focus ? { ...l, close_focus: hit.close_focus } : l;
  }) });
  return {
    shoot: one.name || "The project's",
    dates: one.end && one.end !== one.start ? `${one.start} to ${one.end}` : one.start,
    lead: one.lead,
    in_notion: Boolean(one.sheet),
    // where this sheet is kept: the project record once the switch is on and
    // the sheet has moved, else Notion (specsheet.js)
    kept_on: one.record ? "project record" : "Notion",
    // the record's own sheet, every camera with all of its values, the
    // shoot's one Lenses pool: what a two camera sheet really says
    ...(one.record ? { sheet: withCf(one.record.sheet) } : {}),
    // the sheet's aspect ratios and finishing resolutions (2026-10-15)
    ...(one.record ? { aspect_ratios: framesOf(one.record.sheet).map(ratioOnCard) } : {}),
    ...(one.record ? { finishing_resolutions: one.finishing || one.record.sheet.finishing_resolutions || [] } : {}),
    boxes: Object.fromEntries(BOXES.map((box) => [box, one.camera[box] || ""])),
    lenses: one.lenses,
    modifiers: one.modifiers || [],
    filters: one.filters || [],
    cameras: one.cameras.map((c) => (c.label ? `${c.label}: ${c.body}` : c.body)),
    ...(one.waiting.length ? { waiting: one.waiting.map((b) => SHEET_WORDS[b]) } : {}),
    ...(one.failed ? { failed: one.failed } : {}),
  };
}

/** The connector's three. `found` is the open film ({project, title, role}). */
export async function kitTool(env, found, name, args, refuse, ctx) {
  if (name === "spec_sheet") {
    const here = await kitHere(env, found.project, ctx);
    if (!here.kit.length) return `${found.title} has no Camera Spec Sheet yet. Projects Console makes one (New Shoot, or the Shoots tab).`;
    const list = args.shoot ? [sheetNamed(here.kit, args.shoot)].filter(Boolean) : here.kit;
    if (!list.length) throw refuse(`No shoot called “${args.shoot}”. ${here.kit.map((k) => k.name || "The project's").join(", ")}.`);
    return JSON.stringify({ sheets: list.map((one) => sheetSaid(one, here.library)), editable: Boolean(here.page) }, null, 1);
  }
  if (found.role !== "editor") throw refuse("You may read this project's spec sheet, not change it.");
  if (name === "set_spec_sheet" || name === "add_to_spec_sheet") {
    const asked = name === "set_spec_sheet"
      ? (args.sensor_mode ? { shoot: args.shoot, mode: args.sensor_mode }
        : args.aspect_ratio ? { shoot: args.shoot, frame: args.aspect_ratio }
        : args.finishing_resolution ? { shoot: args.shoot, finishing: args.finishing_resolution }
        : { shoot: args.shoot, changes: args.changes || {}, seen: args.seen })
      : { shoot: args.shoot, add: { lens: args.lens, modifier: args.modifier, filter: args.filter, camera: args.camera, label: args.label } };
    if ((asked.mode || asked.frame || asked.finishing) && args.changes && Object.keys(args.changes).length) throw refuse("Send a sensor mode, aspect ratio or finishing resolution change on its own, then the other changes.");
    if (name === "set_spec_sheet" && !asked.mode && !asked.frame && !asked.finishing && (typeof asked.changes !== "object" || !Object.keys(asked.changes).length)) {
      throw refuse(`Say what changes: {box: text}, boxes ${BOXES.join(", ")}; or sensor_mode {camera, mode}.`);
    }
    const got = await changeSheet(env, found.project, ctx, asked, BY);
    if (got.status !== 200) throw refuse(`Nothing written. ${got.why}`);
    if (!got.item) return got.why || "It says that already. Nothing written.";
    const boxes = Object.keys(got.item.args.changes).join(", ");
    if (got.record) return `Written: ${boxes} on ${sheetNamed(got.kit, got.item.args.shoot || got.item.args.sheet)?.name || "the project's"} spec sheet, on the project record.`;
    return `Asked for: ${boxes} on ${sheetNamed(got.kit, got.item.args.sheet).name || "the project's"} spec sheet. The Studio writes it into Notion within a minute or two; it shows as waiting until then.`;
  }
  throw refuse("No such tool.");
}

/** `take_kit` with no kit: the film's spec sheets as the engine takes them. */
export async function kitArguments(env, found, args, ctx) {
  if (args && args.kit !== undefined) return args;
  const here = await kitHere(env, found.project, ctx);
  return { ...(args || {}), kit: kitForFilm(here.kit) };
}
