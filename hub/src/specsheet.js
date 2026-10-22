/**
 * **The Camera Spec Sheet on the project record** (2026-10-14, phase 1 of
 * `design/spec-sheet.md`; mockups `design/48-spec-sheet.html`).
 *
 * Until now the sheet lived only in Notion, one row per shoot, and a Notion
 * pill column holds one list for the whole row: it cannot say "ProRes 4444 is
 * A Cam's, XAVC-I is B Cam's". So the sheet moves onto the project record, a
 * fact per shoot, and Notion becomes a copy of it (phase 6).
 *
 * **The shape** (a record fact named `spec_<shoot id>`, or `spec_project` for
 * the project's own shoot when it has no Shoots rows, or a sheet tied to none):
 *
 *   { format: 1, shoot, notion, title,
 *     cameras: [{ label, body, format, capture, fps, codec,
 *                 colour, desqueeze, luts: [{label, name, url, held}],
 *                 sensor: {ref, name, width, height} }],
 *     lenses:  [{ name, note, ref, stop, set }],
 *     modifiers: [{ name, note, ref }],   filters: [{ name, note, ref, set }],
 *     frames: [{ name, ratio, main }],
 *     finishing_resolutions: [{ title, resolution, note }],
 *     notes, files: [{name, url, held}], moved }
 *
 * - Every camera keeps **all** of its own values. There is no shared layer:
 *   "shared" is only how a screen draws two equal values. Add Camera copies
 *   the first camera (`addCamera`).
 * - Each box but `body` and `label` is a list of pills (strings). `format`
 *   is the sensor mode's name (Shooting Format and the sensor mode are one
 *   pill, his decision 2026-10-14). A mode picked from the library
 *   (sensormodes.js, phase 2) also puts `sensor` on the camera: the mode's id
 *   and its size in millimetres, kept beside the name. Optional: a sheet
 *   moved from Notion has none until a mode is picked.
 * - **Lenses are one pool for the shoot**, never a camera's (his ruling
 *   2026-10-14). A lens is its full name, an optional short note ("A Cam
 *   only"), its library id (`ref`, lenslibrary.js) when picked from the
 *   library, and its stop and set as they were when it went on.
 * - **Modifiers and filters are pools for the shoot too** (2026-10-14,
 *   kitlibrary.js): what the shoot carries. A shot picks from them; the sheet
 *   never ties one to a lens.
 * - Notes and files belong to the sheet. Rental notes go in Notes.
 * - **Frames are the sheet's, not a camera's** (stage 5 step 5; shown to him
 *   as "Aspect Ratio"): a name and a ratio ("2.39:1", "16:9"; a bare 2.39 is
 *   2.39:1), and exactly one is Main (the portal shows Main). **No
 *   resolution** (his rule, 2026-10-15: a frame guide is not a delivery or a
 *   capture resolution). Not stored until the first frame edit; until then
 *   `framesOf` answers one Main frame with no ratio yet.
 *   A shoot's own sheet holds its own list. Notion's Frame Guides become a
 *   copy (framescopy.js). **A camera has no Frame Guides or Finishing
 *   Resolution of its own** (folded into these two lists, 2026-10-15); only
 *   a Notion row read before the move still carries them (`sheetFromNotion`
 *   turns them into these lists).
 * - **Finishing Resolutions** (2026-10-15): the deliverables, a list of
 *   {title, resolution, note} ("Master · 4096 x 2160 · DCI 4K for the
 *   grade"). Kept on the project's sheet; a shoot's own sheet may hold its
 *   own list, which then stands instead (`finishingOf`). Capture resolution
 *   stays each camera's, from its sensor mode.
 *
 * **One writer.** Everything that changes a sheet goes through `writeFacts`
 * (facts.js), which checks it here (`checkSheet`) and refuses a crossed edit
 * by its version, like every other fact.
 *
 * **Old readers** (the phone's current build, older console builds, the
 * portal's camera page) understand only text. `textView` gives them labelled
 * lines: a value every camera shares as a plain line, one they differ on as
 * "A Cam: ProRes 4444" — the rule `entries.js` already reads.
 *
 * **The switch** (`s/specsheet.json`, `GET/PUT /console/studio/specsheet`):
 * off, every reader takes Notion as before, now reading the hidden Old
 * columns where they kept the camera labels (`boxesOfRow`), so nothing is
 * blank or flattened. On, a shoot with a sheet on the record reads that, and
 * Notion only where a shoot has none.
 *
 * **The move** (`lookAt`, `moveSheets`): every row of Camera Spec Sheets made
 * into a sheet, the Old columns first where they kept labels, the pills
 * otherwise. The look writes nothing and lists, sheet by sheet, what it would
 * write and every line it could not place. The move itself writes record
 * facts only (never Notion), only with `confirm`, and never over a sheet the
 * record already has.
 */
import { entries, splitLabel, labelKey, fieldText, luts as lutRows, lutKey } from "./entries.js";

/** The card's room for each box — `CAMERA` in front.js (which this file
 * cannot import: front.js reaches the worker's own modules, and the look runs
 * in plain node). Change one, change both. */
const CAMERA = { body: 400, format: 300, capture: 200, colour: 300, codec: 200, fps: 200, desqueeze: 100, lenses: 1000, modifiers: 600, filters: 1000, luts: 2000 };

/** The shoot the portal leads with — `leadShoot` in front.js, the same rule. */
function leadShoot(card) {
  const shoots = (card && card.shoots) || [];
  if (!shoots.length) return null;
  return shoots.find((one) => one.status === "Upcoming") || shoots[shoots.length - 1];
}

export const SOURCE = "feedface-0000-4000-8000-000000000003";
export const SWITCH_KEY = "s/specsheet.json";
export const PROJECT_KEY = "spec_project";
export const SPEC_FACT = /^spec_(?:project|[0-9a-f]{32})$/;

/** The camera's boxes, in a crew's reading order, and the Notion column each is. */
export const BOXES = ["body", "format", "capture", "fps", "codec", "colour", "desqueeze"];
/** Notion columns a camera no longer has: read only when a row is moved or read as a sheet, into the two lists. */
const OLD_NOTION = { finishing: "Finishing Resolution", guides: "Frame Guides" };
export const NOTION = {
  body: "Camera", format: "Shooting Format", capture: "Capture Resolution",
  fps: "Frame Rate", codec: "Codec",
  colour: "Color Space", desqueeze: "Desqueeze", lenses: "Lenses",
};
export const WORDS = {
  body: "Camera", format: "Shooting Format", capture: "Capture Resolution",
  fps: "Frame Rate", codec: "Codec",
  colour: "Colour Space", desqueeze: "Desqueeze", lenses: "Lenses",
  modifiers: "Modifiers", filters: "Filters",
};
const old = (box) => `Old ${NOTION[box] || OLD_NOTION[box]}`;
const PILL_BOXES = BOXES.filter((b) => b !== "body");

const MAX = { frames: 8, guides: 12, finishing: 12, cameras: 8, lenses: 80, pills: 12, luts: 12, files: 24, word: 120, note: 120, notes: 4000, url: 1000 };

const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
const bare = (id) => String(id || "").replace(/-/g, "").toLowerCase();
const PAGE = /^[0-9a-f]{32}$/;
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
/** A library id: "l-…" a lens, "s-…" a set, "m-…" a sensor mode (lenslibrary.js). */
const REF = /^[lsmxgf]-[a-z0-9]+(?:-\d+)?$/;

/** "A Cam", "B Cam", … the label the nth camera gets. */
export const letterLabel = (n) => `${String.fromCharCode(65 + Math.max(0, Math.min(25, n)))} Cam`;

/** The fact a shoot's sheet is kept under. */
export const specFact = (shoot) => (PAGE.test(bare(shoot)) ? `spec_${bare(shoot)}` : PROJECT_KEY);

// ------------------------------------------------------------------ checks

function pillList(raw, what) {
  const list = Array.isArray(raw) ? raw : raw == null || raw === "" ? [] : [raw];
  const out = [];
  for (const one of list) {
    if (typeof one !== "string" && typeof one !== "number") return { why: `${what} is a list of words.` };
    const s = squash(one);
    if (!s) continue;
    if (s.length > MAX.word) return { why: `${what} is too long.` };
    if (!out.some((x) => x.toLowerCase() === s.toLowerCase())) out.push(s);
  }
  if (out.length > MAX.pills) return { why: `${what} has too many values.` };
  return { list: out };
}

function linkOf(raw, what) {
  const url = squash(raw);
  if (!url) return { url: "" };
  if (url.length > MAX.url || !/^https:\/\/\S+$/.test(url)) return { why: `${what} is a link (https://…).` };
  return { url };
}

function fileList(raw, what, max) {
  if (raw == null) return { list: [] };
  if (!Array.isArray(raw)) return { why: `${what} is a list.` };
  if (raw.length > max) return { why: `${what} has too many.` };
  const out = [];
  for (const one of raw) {
    if (!isObject(one)) return { why: `Each of ${what} is {name, url}.` };
    const link = linkOf(one.url, `${what}'s link`);
    if (link.why) return link;
    const name = squash(one.name).slice(0, MAX.word);
    const held = Boolean(one.held);
    // a file Notion keeps itself has only its name until it is copied to Drive
    if (!link.url && !(held && name)) return { why: `Each of ${what} needs a link.` };
    out.push({ label: squash(one.label).slice(0, 40), name: name || "", url: link.url, ...(held ? { held: true } : {}) });
  }
  return { list: out };
}

/** A modifiers or filters pool: [{name, note, ref, set}], each name once. */
function extraList(raw, pool, what) {
  const list = raw == null ? [] : raw;
  if (!Array.isArray(list)) return { why: `${pool} is a list.` };
  if (list.length > MAX.lenses) return { why: `Too many ${pool}.` };
  const out = [];
  for (const x of list) {
    const one = typeof x === "string" ? { name: x } : x;
    if (!isObject(one)) return { why: `Each ${what} is {name, note}.` };
    const name = squash(one.name);
    if (!name) continue;
    if (name.length > MAX.word) return { why: `${name.slice(0, 40)}… is too long for a ${what}.` };
    const note = squash(one.note);
    if (note.length > MAX.note) return { why: `The note on ${name} is too long.` };
    if (out.some((y) => y.name.toLowerCase() === name.toLowerCase())) continue;
    const kept = { name, note };
    if (REF.test(String(one.ref || ""))) kept.ref = String(one.ref);
    const set = squash(one.set).slice(0, MAX.word);
    if (set) kept.set = set;
    out.push(kept);
  }
  return { list: out };
}

// ----------------------------------------------------------------- frames

/** A frame's ratio as the sheet writes it: "2.39:1", "9:16"; a bare number gains its ":1". */
export function ratioText(r) {
  const t = squash(r).replace(/\u2236/g, ":").replace(/\s*:\s*/g, ":").slice(0, 20);
  return /^\d+(?:\.\d+)?$/.test(t) ? `${t}:1` : t;
}
const RATIO = /^\d+(?:\.\d+)?:\d+(?:\.\d+)?$/;
/** Whether a ratio, as written, is one ("" is: not said yet). */
export const isRatio = (t) => t === "" || (RATIO.test(t) && !/^0+(?:\.0+)?:|:0+(?:\.0+)?$/.test(t));

/**
 * The frames a sheet with none starts from: one Main frame with no ratio
 * yet. Not stored until the first frame edit.
 */
export function defaultFrames() {
  return [{ name: "Main", ratio: "", main: true }];
}

/** The sheet's frames as a reader takes them: its own, else the default. */
export function framesOf(sheet) {
  return sheet && Array.isArray(sheet.frames) && sheet.frames.length ? sheet.frames : defaultFrames(sheet);
}

/**
 * **Frame guide files** (2026-10-15): the camera frame-line files the AC loads
 * (ARRI XML, RED / Sony guide files, PNG overlays), kept on the aspect ratio
 * they belong to: { name, camera, note, file, url }. `file` is where the copy
 * sits in the project's Drive folder (`3-post/frame-line/x.xml`); `url` is its
 * Drive link, "" for the moments before Drive has taken the file in.
 */
export function guideOne(g) {
  const url = squash(g.url);
  const file = squash(g.file).replace(/^\/+/, "").slice(0, 300);
  return {
    name: squash(g.name).slice(0, MAX.word) || (file ? file.split("/").pop() : "Frame guide"),
    camera: squash(g.camera).slice(0, 40), note: squash(g.note).slice(0, MAX.note), file, url,
  };
}
function guideList(raw, what) {
  if (raw == null) return { list: [] };
  if (!Array.isArray(raw)) return { why: `${what} is a list.` };
  if (raw.length > MAX.guides) return { why: `${what} has too many (${MAX.guides} at most).` };
  const out = [];
  for (const g of raw) {
    if (!isObject(g)) return { why: `Each of ${what} is {name, camera, note, file, url}.` };
    const one = guideOne(g);
    if (one.url && (one.url.length > MAX.url || !/^https:\/\/\S+$/.test(one.url))) return { why: `${what}'s link is a link (https://…).` };
    if (one.file.split("/").includes("..")) return { why: `${what}'s file is not a place in the folder.` };
    if (!one.url && !one.file) return { why: `Each of ${what} needs a file.` };
    out.push(one);
  }
  return { list: out };
}

/** A frames list, checked: {list} or {why}. Exactly one Main when any: none
 * said makes the first Main; two is refused. */
function frameList(raw) {
  if (raw == null) return { list: [] };
  if (!Array.isArray(raw)) return { why: "frames is a list." };
  if (raw.length > MAX.frames) return { why: `A spec sheet holds ${MAX.frames} frames at most.` };
  const out = [];
  for (const f of raw) {
    if (!isObject(f)) return { why: "Each frame is {name, ratio, main}." };
    const name = squash(f.name).slice(0, 40);
    if (!name) return { why: "Each frame needs a name." };
    const ratio = ratioText(f.ratio);
    if (!isRatio(ratio)) return { why: `${name}'s ratio is not a ratio (2.39:1, 16:9).` };
    const guides = guideList(f.guides, `${name}'s frame guides`);
    if (guides.why) return guides;
    out.push({ name, ratio, main: f.main === true, ...(guides.list.length ? { guides: guides.list } : {}) });
  }
  const mains = out.filter((f) => f.main).length;
  if (mains > 1) return { why: "Only one frame is Main." };
  if (out.length && !mains) out[0].main = true;
  return { list: out };
}

/**
 * **One frame change** — the console's ops (specrecord.py, the same words):
 *   {op: "add_frame", frame?}                    {name, ratio}; not Main
 *   {op: "frame", at, name?, ratio?}
 *   {op: "remove_frame", at}                     the first left becomes Main if Main went
 *   {op: "main_frame", at}
 * A sheet with no frames starts from `defaultFrames`. {sheet} or {why}.
 */
export function applyFrameOp(sheetIn, op) {
  if (!isObject(op)) return { why: "Say what changes." };
  const sheet = JSON.parse(JSON.stringify(sheetIn || {}));
  const kind = String(op.op || "");
  if (!["add_frame", "frame", "remove_frame", "main_frame", "add_guide", "guide", "remove_guide", "link_guide"].includes(kind)) return { why: `No such change: ${kind || "nothing"}.` };
  const frames = Array.isArray(sheet.frames) && sheet.frames.length ? sheet.frames : defaultFrames(sheet);
  if (kind === "link_guide") {
    // Drive has taken a file in: its link goes on the guide that names the file
    const file = squash(op.file), url = squash(op.url);
    const hit = frames.flatMap((f) => f.guides || []).find((g) => g.file === file);
    if (!file || !hit) return { why: "No such frame guide." };
    hit.url = url;
  } else if (kind === "add_frame") {
    if (frames.length >= MAX.frames) return { why: `A spec sheet holds ${MAX.frames} frames at most.` };
    const f = isObject(op.frame) ? op.frame : {};
    frames.push({ name: squash(f.name) || `Frame ${frames.length + 1}`, ratio: ratioText(f.ratio), main: false });
  } else {
    const at = Number.isInteger(Number(op.at)) && op.at !== null && op.at !== "" ? Number(op.at) : -1;
    if (!(at >= 0 && at < frames.length)) return { why: "No such frame." };
    const f = frames[at];
    if (kind === "frame") {
      if ("name" in op) {
        if (!squash(op.name)) return { why: "Say the frame's name." };
        f.name = squash(op.name).slice(0, 40);
      }
      if ("ratio" in op) f.ratio = ratioText(op.ratio);
    } else if (kind === "remove_frame") {
      const wasMain = f.main;
      frames.splice(at, 1);
      if (wasMain && frames.length) frames[0].main = true;
      // its frame guide files are not lost: they go under Main
      if (f.guides && f.guides.length && frames.length) {
        const main = frames.find((x) => x.main) || frames[0];
        main.guides = [...(main.guides || []), ...f.guides].slice(0, MAX.guides);
      }
    } else if (kind === "add_guide") {
      const g = guideOne(isObject(op.guide) ? op.guide : {});
      if (!g.file && !g.url) return { why: "Say which file." };
      f.guides = [...(f.guides || [])];
      if (f.guides.length >= MAX.guides) return { why: `A frame holds ${MAX.guides} frame guides at most.` };
      f.guides.push(g);
    } else if (kind === "guide" || kind === "remove_guide") {
      const i = Number.isInteger(Number(op.i)) && op.i !== null && op.i !== "" ? Number(op.i) : -1;
      if (!(f.guides && i >= 0 && i < f.guides.length)) return { why: "No such frame guide." };
      if (kind === "remove_guide") {
        f.guides.splice(i, 1);
        if (!f.guides.length) delete f.guides;
      } else {
        if ("name" in op) {
          if (!squash(op.name)) return { why: "Say the frame guide's name." };
          f.guides[i].name = squash(op.name).slice(0, MAX.word);
        }
        if ("camera" in op) f.guides[i].camera = squash(op.camera).slice(0, 40);
        if ("note" in op) f.guides[i].note = squash(op.note).slice(0, MAX.note);
      }
    } else {
      frames.forEach((x, i) => { x.main = i === at; });
    }
  }
  sheet.frames = frames;
  return checkSheet(sheet);
}

// ------------------------------------------------- finishing resolutions

/** A finishing resolution as the sheet writes it: "4096 x 2160" (x or ×, spaces tidied). */
export function resolutionText(r) {
  return squash(r).replace(/^(\d+)\s*[x×X*]\s*(\d+)$/, "$1 x $2").slice(0, 40);
}

/** A finishing resolutions list, checked: {list} or {why}. */
function finishingList(raw) {
  if (raw == null) return { list: [] };
  if (!Array.isArray(raw)) return { why: "finishing_resolutions is a list." };
  if (raw.length > MAX.finishing) return { why: `A spec sheet holds ${MAX.finishing} finishing resolutions at most.` };
  const out = [];
  for (const f of raw) {
    if (!isObject(f)) return { why: "Each finishing resolution is {title, resolution, note}." };
    const title = squash(f.title).slice(0, 60);
    const resolution = resolutionText(f.resolution);
    const note = squash(f.note);
    if (note.length > MAX.note) return { why: `The note on ${title || "a finishing resolution"} is too long.` };
    if (!title && !resolution && !note) continue;
    out.push({ title: title || "Untitled", resolution, note });
  }
  return { list: out };
}

/**
 * The finishing resolutions a sheet reads: its own, else the project's
 * sheet's (a shoot's own list stands instead of the project's). `sheets` is
 * `recordSheets`; `fact` the sheet being read.
 */
export function finishingOf(sheets, fact) {
  const own = sheets && sheets[fact] && sheets[fact].sheet;
  if (own && Array.isArray(own.finishing_resolutions) && own.finishing_resolutions.length) return own.finishing_resolutions;
  const project = sheets && sheets[PROJECT_KEY] && sheets[PROJECT_KEY].sheet;
  return (project && project.finishing_resolutions) || [];
}

/**
 * **One finishing resolution change** — the console's ops (specrecord.py):
 *   {op: "add_finishing", entry?}                {title, resolution, note}
 *   {op: "finishing", at, title?, resolution?, note?}
 *   {op: "remove_finishing", at}
 * {sheet} or {why}.
 */
export function applyFinishingOp(sheetIn, op) {
  if (!isObject(op)) return { why: "Say what changes." };
  const sheet = JSON.parse(JSON.stringify(sheetIn || {}));
  const kind = String(op.op || "");
  if (!["add_finishing", "finishing", "remove_finishing"].includes(kind)) return { why: `No such change: ${kind || "nothing"}.` };
  const list = Array.isArray(sheet.finishing_resolutions) ? sheet.finishing_resolutions : [];
  if (kind === "add_finishing") {
    if (list.length >= MAX.finishing) return { why: `A spec sheet holds ${MAX.finishing} finishing resolutions at most.` };
    const e = isObject(op.entry) ? op.entry : {};
    list.push({ title: squash(e.title) || (list.length ? `Resolution ${list.length + 1}` : "Master"), resolution: resolutionText(e.resolution), note: squash(e.note) });
  } else {
    const at = Number.isInteger(Number(op.at)) && op.at !== null && op.at !== "" ? Number(op.at) : -1;
    if (!(at >= 0 && at < list.length)) return { why: "No such finishing resolution." };
    if (kind === "remove_finishing") list.splice(at, 1);
    else {
      const e = list[at];
      if ("title" in op) {
        if (!squash(op.title)) return { why: "Say its title." };
        e.title = squash(op.title).slice(0, 60);
      }
      if ("resolution" in op) e.resolution = resolutionText(op.resolution);
      if ("note" in op) e.note = squash(op.note);
    }
  }
  sheet.finishing_resolutions = list;
  return checkSheet(sheet);
}

/**
 * **A sheet, checked and tidied**: {sheet} or {why}. Every writer's sheet
 * passes through here (facts.js), so a stored sheet is always this shape.
 */
export function checkSheet(raw) {
  if (!isObject(raw)) return { why: "A spec sheet is an object." };
  const cams = raw.cameras == null ? [] : raw.cameras;
  if (!Array.isArray(cams)) return { why: "cameras is a list." };
  if (cams.length > MAX.cameras) return { why: `A spec sheet holds ${MAX.cameras} cameras at most.` };
  const cameras = [];
  for (let i = 0; i < cams.length; i++) {
    const c = cams[i];
    if (!isObject(c)) return { why: "Each camera is an object." };
    const label = squash(c.label).replace(/:/g, " ").trim().slice(0, 24) || letterLabel(i);
    if (cameras.some((x) => labelKey(x.label) === labelKey(label))) return { why: `Two cameras are called ${label}.` };
    const body = squash(c.body);
    if (body.length > MAX.word) return { why: `${label}'s camera is too long.` };
    const one = { label, body };
    for (const box of PILL_BOXES) {
      const got = pillList(c[box], `${label}'s ${WORDS[box]}`);
      if (got.why) return got;
      one[box] = got.list;
    }
    const luts = fileList(c.luts, `${label}'s LUTs`, MAX.luts);
    if (luts.why) return luts;
    one.luts = luts.list;
    // the sensor mode the Shooting Format names (phase 2, sensormodes.js):
    // its size kept beside the name, as it was when picked. Kept only while
    // the Shooting Format still says that name; a format changed as text
    // leaves the mode behind with it.
    if (isObject(c.sensor)) {
      const name = squash(c.sensor.name).slice(0, MAX.word);
      const mm = (x) => (x === null || x === undefined || x === "" ? null : Number.isFinite(Number(x)) && Number(x) > 0 && Number(x) < 100 ? Math.round(Number(x) * 100) / 100 : undefined);
      const width = mm(c.sensor.width);
      const height = mm(c.sensor.height);
      if (width === undefined || height === undefined) return { why: `${label}'s sensor size is millimetres, under 100.` };
      const ref = REF.test(String(c.sensor.ref || "")) ? String(c.sensor.ref) : "";
      if (name && one.format.some((f) => f.toLowerCase() === name.toLowerCase())) one.sensor = { ref, name, width, height };
    }
    cameras.push(one);
  }
  const lensesRaw = raw.lenses == null ? [] : raw.lenses;
  if (!Array.isArray(lensesRaw)) return { why: "lenses is a list." };
  if (lensesRaw.length > MAX.lenses) return { why: "Too many lenses." };
  const lenses = [];
  for (const l of lensesRaw) {
    const lens = typeof l === "string" ? { name: l } : l;
    if (!isObject(lens)) return { why: "Each lens is {name, note}." };
    const name = squash(lens.name);
    if (!name) continue;
    if (name.length > MAX.word) return { why: `${name.slice(0, 40)}… is too long for a lens.` };
    const note = squash(lens.note);
    if (note.length > MAX.note) return { why: `The note on ${name} is too long.` };
    if (lenses.some((x) => x.name.toLowerCase() === name.toLowerCase())) continue;
    const out = { name, note };
    // the lens library's id (phase 2, lenslibrary.js); `name` is the library's
    // name as it was when picked, kept so a rename there never changes this
    if (REF.test(String(lens.ref || ""))) out.ref = String(lens.ref);
    const stop = squash(lens.stop).slice(0, 24);
    const set = squash(lens.set).slice(0, MAX.word);
    if (stop) out.stop = stop;
    if (set) out.set = set;
    lenses.push(out);
  }
  const extras = {};
  for (const [pool, what] of [["modifiers", "modifier"], ["filters", "filter"]]) {
    const got = extraList(raw[pool], pool, what);
    if (got.why) return got;
    extras[pool] = got.list;
  }
  const notes = String(raw.notes == null ? "" : raw.notes).replace(/\r\n?/g, "\n").trim();
  if (notes.length > MAX.notes) return { why: "The notes are too long." };
  const files = fileList(raw.files, "the sheet's files", MAX.files);
  if (files.why) return files;
  const frames = frameList(raw.frames);
  if (frames.why) return frames;
  const finishing = finishingList(raw.finishing_resolutions);
  if (finishing.why) return finishing;
  const sheet = {
    format: 1,
    shoot: PAGE.test(bare(raw.shoot)) ? bare(raw.shoot) : "",
    notion: PAGE.test(bare(raw.notion)) ? bare(raw.notion) : "",
    title: squash(raw.title).slice(0, 200),
    cameras, lenses, ...extras, ...(frames.list.length ? { frames: frames.list } : {}),
    ...(finishing.list.length ? { finishing_resolutions: finishing.list } : {}), notes, files: files.list,
  };
  if (isObject(raw.moved)) {
    sheet.moved = { from: squash(raw.moved.from).slice(0, 40), at: squash(raw.moved.at).slice(0, 40), by: squash(raw.moved.by).slice(0, 80) };
  }
  return { sheet };
}

// ---------------------------------------------------------------- editing

/** A new camera: a copy of the first camera's values, under the next letter. */
export function addCamera(sheet, { label = "", body = "" } = {}) {
  const first = sheet.cameras[0];
  const used = new Set(sheet.cameras.map((c) => labelKey(c.label)));
  let n = sheet.cameras.length;
  while (used.has(labelKey(letterLabel(n))) && n < 25) n += 1;
  const cam = first ? JSON.parse(JSON.stringify(first)) : { body: "", luts: [], ...Object.fromEntries(PILL_BOXES.map((b) => [b, []])) };
  cam.label = squash(label) || letterLabel(n);
  if (body) cam.body = squash(body);
  sheet.cameras.push(cam);
  return cam;
}

function cameraFor(sheet, label) {
  const k = labelKey(label);
  if (!k) return null;
  return sheet.cameras.find((c) => labelKey(c.label) === k || labelKey(c.body) === k)
    || sheet.cameras.find((c) => k.length >= 3 && labelKey(c.body).endsWith(k)) || null;
}

/** "Master Prime 25mm · A Cam only" → {name, note}. */
export function lensLine(line) {
  const [name, ...rest] = String(line || "").split(" · ");
  return { name: squash(name), note: squash(rest.join(" · ")) };
}

/**
 * **A box changed as text** — the labelled lines an old reader or the
 * connector writes — laid back onto the sheet. {sheet} or {why}. A labelled
 * line is that camera's; an unlabelled line every camera's; a camera with a
 * labelled line keeps only those. On `body`, lines are the cameras: a new
 * label adds one (a copy of the first), a missing one removes it.
 */
export function applyBoxText(sheetIn, box, text) {
  const sheet = JSON.parse(JSON.stringify(sheetIn));
  const lines = entries(String(text ?? "").replace(/\r\n?/g, "\n"));
  if (box === "lenses" || box === "modifiers" || box === "filters") {
    const was = new Map((sheet[box] || []).map((l) => [l.name.toLowerCase(), l]));
    sheet[box] = String(text ?? "").split("\n").map(lensLine).filter((l) => l.name).map((l) => {
      const kept = was.get(l.name.toLowerCase());
      return kept ? { ...kept, name: l.name, note: l.note } : { name: l.name, note: l.note };
    });
    return checkSheet(sheet);
  }
  if (box === "body") {
    if (!lines.length) {
      for (const c of sheet.cameras) c.body = "";
      return checkSheet(sheet);
    }
    if (lines.length === 1 && !lines[0].label && sheet.cameras.length <= 1) {
      if (!sheet.cameras.length) addCamera(sheet);
      sheet.cameras[0].body = lines[0].value;
      return checkSheet(sheet);
    }
    const next = [];
    lines.forEach((e, i) => {
      const label = e.label || (sheet.cameras[i] ? sheet.cameras[i].label : letterLabel(i));
      const have = sheet.cameras.find((c) => labelKey(c.label) === labelKey(label));
      if (have) { next.push({ ...have, body: e.value }); return; }
      const copy = { cameras: [...sheet.cameras, ...next] };
      const cam = addCamera(copy, { label, body: e.value });
      next.push(cam);
    });
    sheet.cameras = next;
    return checkSheet(sheet);
  }
  if (!PILL_BOXES.includes(box)) return { why: `A spec sheet has no “${box}”.` };
  if (!sheet.cameras.length) addCamera(sheet);
  const shared = [];
  const own = new Map();
  for (const e of lines) {
    if (e.label && sheet.cameras.length > 1) {
      const cam = cameraFor(sheet, e.label);
      if (!cam) return { why: `No camera called ${e.label} on this sheet. ${sheet.cameras.map((c) => c.label).join(", ")}.` };
      if (!own.has(cam)) own.set(cam, []);
      own.get(cam).push(e.value);
    } else {
      shared.push(sheet.cameras.length > 1 ? e.value : e.raw);
    }
  }
  for (const cam of sheet.cameras) cam[box] = own.has(cam) ? own.get(cam) : shared;
  return checkSheet(sheet);
}

// ------------------------------------------------------------ the text view

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** The words a LUT is matched by in "LUT Labels": its name, or a link's address. */
const lutWord = (one) => lutKey({ name: one.name, url: one.url }) || one.url || one.name;

/**
 * **The sheet as the labelled text old readers take** — the card's camera
 * boxes {body, lenses, format, …, luts} and the files the camera page lists.
 * One camera: plain lines, no labels. Several: a value every camera shares is
 * a plain line; one they differ on is a line per camera, "A Cam: ProRes 4444".
 * Lenses are the shoot's, one name a line, a note after a middle dot.
 */
export function textView(sheet) {
  const cams = sheet.cameras || [];
  const multi = cams.length > 1;
  const out = {};
  out.body = multi ? cams.map((c) => `${c.label}: ${c.body}`).filter((l) => !/:\s*$/.test(l)).join("\n") : (cams[0] ? cams[0].body : "");
  for (const box of PILL_BOXES) {
    if (!cams.length) { out[box] = ""; continue; }
    const lists = cams.map((c) => c[box] || []);
    if (!multi || lists.every((l) => same(l, lists[0]))) out[box] = lists[0].join("\n");
    else out[box] = cams.flatMap((c) => (c[box] || []).map((v) => `${c.label}: ${v}`)).join("\n");
  }
  for (const pool of ["lenses", "modifiers", "filters"]) out[pool] = (sheet[pool] || []).map((l) => (l.note ? `${l.name} · ${l.note}` : l.name)).join("\n");
  // LUTs: every camera's, once each; labelled by camera when they differ
  const files = [];
  const lines = [];
  const seen = new Set();
  const lutLists = cams.map((c) => c.luts || []);
  const allSame = lutLists.every((l) => same(l, lutLists[0]));
  const add = (one, kind = "") => {
    const key = (one.url || one.name).toLowerCase();
    if (!seen.has(key)) { seen.add(key); files.push({ name: one.name || one.url, url: one.url, ...(one.held ? { held: true } : {}), ...(kind ? { kind } : {}) }); }
  };
  cams.forEach((c, i) => {
    if (multi && allSame && i > 0) return;
    for (const one of c.luts || []) {
      add(one);
      const words = multi && !allSame ? [c.label, one.label].filter(Boolean).join(" ") : one.label;
      const label = words.split(/\s+/).length <= 4 ? words : c.label;
      if (label) lines.push(`${label}: ${lutWord(one)}`);
    }
  });
  // the sheet's other files (camera reports, charts): not LUTs
  for (const one of sheet.files || []) add(one, "file");
  out.luts = lines.join("\n");
  for (const [box, cap] of Object.entries(CAMERA)) if (typeof out[box] === "string") out[box] = out[box].slice(0, cap);
  return { boxes: out, files };
}

// ---------------------------------------------------------------- the move

/** A Notion text column as lines: `<br>` a line break, a link its words. */
function oldText(prop) {
  return fieldText(prop).replace(/<br\s*\/?>/gi, "\n").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1");
}
const pillNames = (prop) => (prop && prop.type === "multi_select" ? (prop.multi_select || []).map((o) => squash(o.name)).filter(Boolean) : []);
const NOTHING = /^(n\/?a|none|-|—|tbd|tbc)$/i;
const key = (s) => String(s || "").toLowerCase().replace(/[×]/g, "x").replace(/[\s\-_'’.]/g, "");
const tokens = (s) => String(s || "").split("/").map(key).filter(Boolean).sort();

/**
 * **An old typed value matched to the pill Notion has for it** — "FX6" is
 * "Sony FX6", "3840x2160" is "3840 x 2160", "S-Log3/S-Gamut3.Cine" is
 * "S-Gamut3.Cine / S-Log3", "1.0" is "1.0x", 23.98 is 23.976. {value, how}:
 * how is "" when it was the pill's own words, "matched" when it was read as
 * one, "typed" when no pill matches and it is kept as he typed it.
 */
export function canon(box, raw, options = []) {
  let v = squash(raw);
  if (box === "desqueeze" && /^\d+(\.\d+)?$/.test(v)) v = `${v}x`;
  if (box === "capture" || box === "finishing") {
    const m = /^(\d{3,5})\s*[x×]\s*(\d{3,5})$/i.exec(v);
    if (m) v = `${m[1]} x ${m[2]}`;
  }
  if (box === "guides") v = v.replace(/\s*:\s*/g, ":");
  const opts = options.filter(Boolean);
  const exact = opts.find((o) => o === v);
  if (exact) return { value: exact, how: "" };
  const k = key(v);
  let hit = opts.find((o) => key(o) === k);
  if (!hit && (box === "colour")) {
    const t = tokens(v);
    hit = opts.find((o) => same(tokens(o), t))
      || (t.length === 1 ? opts.filter((o) => tokens(o).includes(t[0])).length === 1 && opts.find((o) => tokens(o).includes(t[0])) : null);
  }
  if (!hit && box === "fps" && /^\d+(\.\d+)?$/.test(v)) {
    hit = opts.find((o) => /^\d+(\.\d+)?$/.test(o) && Math.abs(Number(o) - Number(v)) < 0.01);
  }
  if (!hit && box === "body") {
    const words = v.toLowerCase().split(/\s+/);
    const ends = opts.filter((o) => {
      const ow = o.toLowerCase().split(/\s+/);
      return ow.length > words.length && same(ow.slice(-words.length), words);
    });
    if (ends.length === 1) hit = ends[0];
  }
  if (hit) return { value: hit, how: "matched" };
  return { value: v, how: "typed" };
}

/**
 * **A camera's old Frame Guides and Finishing Resolution folded into the
 * sheet's two lists** (2026-10-15). Used when a Notion row is read as a sheet;
 * the console's data fold (`fold_camera_rows` in the data step) follows the
 * same rule. `sheet` is {cameras: [{label, guides, finishing}], frames?,
 * finishing_resolutions?}. Returns {frames, finishing_resolutions, notes,
 * unplaced: [{box, value}]}; a value that is no ratio or no resolution, or
 * would overflow a list, goes to `notes` ("Frame Guides (A Cam): …").
 *
 * - Aspect Ratio: each ratio once; named "<Camera> <ratio>", the first one
 *   Main when the sheet had none.
 * - Finishing Resolutions: "2880 x 2160 (Web)" is Web · 2880 x 2160; a bare
 *   resolution is titled by its camera ("All Cams" when every camera has it).
 *   A resolution the list already holds is skipped.
 */
export function foldCameraRows(sheet) {
  const cams = (sheet && sheet.cameras) || [];
  const frames = Array.isArray(sheet.frames) ? sheet.frames.map((f) => ({ ...f })) : [];
  const fin = Array.isArray(sheet.finishing_resolutions) ? sheet.finishing_resolutions.map((f) => ({ ...f })) : [];
  const unplaced = [];
  const bits = [];
  const stray = (box, label, value) => { unplaced.push({ box, value }); bits.push(`${WORDS_OLD[box]} (${label}): ${value}`); };
  for (const cam of cams) {
    for (const raw of cam.guides || []) {
      const ratio = ratioText(raw);
      if (!ratio || !RATIO.test(ratio) || !isRatio(ratio)) { stray("guides", cam.label, raw); continue; }
      if (frames.some((f) => ratioText(f.ratio) === ratio)) continue;
      if (frames.length >= MAX.frames) { stray("guides", cam.label, raw); continue; }
      frames.push({ name: frames.length ? `${cam.label} ${ratio}` : "Main", ratio, main: !frames.length });
    }
  }
  const ways = new Map();
  for (const cam of cams) {
    for (const raw of cam.finishing || []) {
      const m = /^\s*(\d{3,5})\s*[x×X*]\s*(\d{3,5})\s*(?:\(([^)]*)\))?\s*$/.exec(String(raw));
      if (!m) { stray("finishing", cam.label, raw); continue; }
      const resolution = `${m[1]} x ${m[2]}`;
      const entry = ways.get(`${resolution}|${squash(m[3])}`) || { resolution, said: squash(m[3]), labels: [] };
      entry.labels.push(cam.label);
      ways.set(`${resolution}|${squash(m[3])}`, entry);
    }
  }
  for (const e of ways.values()) {
    if (fin.some((f) => resolutionText(f.resolution) === e.resolution)) continue;
    if (fin.length >= MAX.finishing) { stray("finishing", e.labels[0], `${e.resolution}${e.said ? ` (${e.said})` : ""}`); continue; }
    const title = e.said || (cams.length > 1 && e.labels.length === cams.length ? "All Cams" : e.labels[0]);
    fin.push({ title: title.slice(0, 60), resolution: e.resolution, note: "" });
  }
  return { frames: frames.length ? frames : undefined, finishing_resolutions: fin.length ? fin : undefined, notes: bits.join("\n"), unplaced };
}
const WORDS_OLD = { guides: "Frame Guides", finishing: "Finishing Resolution" };

const FOCAL = /^\d+(\.\d+)?(-\d+(\.\d+)?)?(mm)?$/i;
const focalOfPill = (name) => {
  const t = String(name).split(/\s+/).filter((w) => FOCAL.test(w) && /mm$/i.test(w));
  return t.length ? t[t.length - 1].toLowerCase().replace(/mm$/, "") : "";
};
const focalsIn = (text) => (String(text).match(/\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?/g) || []).map((x) => x.replace(/\s+/g, ""));
const wordsOf = (s) => String(s || "").toLowerCase().replace(/[’']s\b/g, "").split(/[^a-z0-9.]+/).filter(Boolean);
const STOP = /^T\d/i;

/** An old typed lens line: {label, set, parts, focals, stop, line}. */
function oldLensLine(raw) {
  const [label, rest] = splitLabel(raw);
  const parts = rest.split(/\s+[—–|]\s+/).map(squash).filter(Boolean);
  const stop = parts.slice(1).find((p) => STOP.test(p)) || "";
  const dashed = parts.length > 1;
  const focalPart = dashed ? parts.slice(1).filter((p) => !STOP.test(p)).join(" ") : rest;
  const focals = focalsIn(focalPart);
  return { label, rest, parts, dashed, stop, focals, set: dashed && focals.length > 1 ? parts[0] : "" };
}

/** Which old line a lens pill came from, or null. */
function lineForPill(pill, lines) {
  const focal = focalOfPill(pill);
  const mine = wordsOf(pill).filter((w) => w.length >= 3 && !FOCAL.test(w));
  let best = null, bestScore = 0;
  for (const one of lines) {
    const theirs = new Set(wordsOf(one.dashed ? one.parts[0] : one.rest));
    const score = mine.filter((w) => theirs.has(w)).length;
    if (!score) continue;
    if (focal && one.focals.length && !one.focals.includes(focal)) continue;
    if (score > bestScore) { best = one; bestScore = score; }
  }
  return best;
}

/** A word the lens's name already says, typo and all ("Prob2" for "Probe2"). */
function saidBy(word, have) {
  for (const h of have) {
    if (h === word) return true;
    if (Math.min(h.length, word.length) >= 4 && (h.startsWith(word) || word.startsWith(h))) return true;
    if (h.length >= 4 && Math.abs(h.length - word.length) <= 1) {
      // one letter added, dropped or changed
      let i = 0, j = 0, miss = 0;
      while (i < h.length && j < word.length) {
        if (h[i] === word[j]) { i++; j++; continue; }
        miss++;
        if (h.length > word.length) i++; else if (word.length > h.length) j++; else { i++; j++; }
      }
      if (miss + (h.length - i) + (word.length - j) <= 1) return true;
    }
  }
  return false;
}
const FOCAL_PART = /^[\d.,\s&x×-]*(mm)?$/i;

/** What an old lens line says beyond the lens's own name ("T-Tuned", "PL Mount Lens (MD)"). */
function leftover(one, pill) {
  const have = wordsOf(pill);
  const bits = [];
  if (!one.set) {
    const left = (one.dashed ? one.parts[0] : one.rest).split(/\s+/).filter((w) => {
      const ws = wordsOf(w);
      return ws.length && !ws.every((x) => saidBy(x, have) || FOCAL.test(x));
    }).join(" ");
    if (left) bits.push(left);
  }
  if (one.dashed) {
    for (const p of one.parts.slice(1)) if (!STOP.test(p) && !FOCAL_PART.test(p)) bits.push(p);
  }
  return squash(bits.join(", "));
}

/**
 * **One Notion row made a sheet** — the move, for one row; also what every
 * reader takes while the switch is off (`boxesOfRow`). `options` is
 * {Notion column: [pill names]} from the data source, so an old "FX6" finds
 * "Sony FX6" even where this row's pills do not list it.
 *
 * Returns {sheet, flags, project, shoot, fact}. A flag is {level, field,
 * line, why}: "unplaced" for something the move could not put anywhere (he
 * should look), "note" for a choice it made that he may want to know.
 */
export function sheetFromNotion(row, options = {}) {
  const props = (row && row.properties) || {};
  const flags = [];
  const flag = (level, field, line, why) => flags.push({ level, field, line: squash(line), why });
  const opts = (box) => {
    const col = NOTION[box] || OLD_NOTION[box];
    const mine = pillNames(props[col]);
    const all = (options[col] || []).map((o) => (typeof o === "string" ? o : o && o.name)).filter(Boolean);
    return [...mine, ...all.filter((o) => !mine.includes(o))];
  };
  const clean = (box, value, where) => {
    if (NOTHING.test(squash(value))) { flag("note", box, value, "read as nothing"); return ""; }
    const got = canon(box, value, opts(box));
    if (got.how === "matched" && got.value !== squash(value)) flag("note", box, value, `read as “${got.value}”${where ? ` for ${where}` : ""}`);
    if (got.how === "typed") flag("note", box, value, `kept as typed; Notion has no pill for it`);
    return got.value;
  };

  // ---- the cameras: the Old Camera column kept the labels
  const oldBody = entries(oldText(props[old("body")]));
  const bodyPills = pillNames(props[NOTION.body]);
  const cameras = [];
  const blank = () => ({ luts: [], ...Object.fromEntries(PILL_BOXES.map((b) => [b, []])) });
  if (oldBody.some((e) => e.label)) {
    oldBody.forEach((e, i) => cameras.push({ ...blank(), label: e.label || letterLabel(i), body: clean("body", e.value) }));
  } else if (bodyPills.length) {
    bodyPills.forEach((name, i) => cameras.push({ ...blank(), label: letterLabel(i), body: name }));
    if (bodyPills.length > 1) flag("note", "body", bodyPills.join(", "), "no camera labels kept; named A Cam, B Cam in Notion's order");
  } else {
    oldBody.forEach((e, i) => cameras.push({ ...blank(), label: letterLabel(i), body: clean("body", e.value) }));
  }
  if (!cameras.length) cameras.push({ ...blank(), label: letterLabel(0), body: "" });
  const multi = cameras.length > 1;
  const sheet = { cameras, lenses: [], notes: "", files: [] };

  // ---- each box: Old where it kept labels or the pills are empty; else the pills
  for (const box of [...PILL_BOXES, ...Object.keys(OLD_NOTION)]) {
    const was = entries(oldText(props[old(box)]));
    const pills = pillNames(props[NOTION[box] || OLD_NOTION[box]]);
    const labelled = was.some((e) => e.label);
    if (!labelled && pills.length) {
      for (const c of cameras) c[box] = [...pills];
      continue;
    }
    const shared = [];
    const own = new Map();
    for (const e of was) {
      const values = box === "guides" && !e.label ? e.value.split(/\s+\/\s+|\s*,\s*/) : [e.value];
      if (e.label && multi) {
        const cam = cameraFor(sheet, e.label);
        if (!cam) { flag("unplaced", box, e.raw, `no camera called ${e.label}`); continue; }
        if (!own.has(cam)) own.set(cam, []);
        for (const v of values) { const c = clean(box, v, cam.label); if (c) own.get(cam).push(c); }
      } else {
        if (e.label && !multi) flag("note", box, e.raw, `the label ${e.label} dropped; the sheet has one camera`);
        for (const v of values) { const c = clean(box, v); if (c) shared.push(c); }
      }
    }
    for (const c of cameras) c[box] = [...new Set(own.has(c) ? own.get(c) : shared)];
  }

  // ---- the lenses: the pills name them; the Old lines carry stops, sets, notes
  const lensPills = pillNames(props[NOTION.lenses]);
  const lensLines = oldText(props[old("lenses")]).split("\n").map(squash).filter(Boolean).map(oldLensLine);
  const used = new Set();
  const pillOf = new Map();
  const notes = [];
  for (const name of lensPills) {
    const from = lineForPill(name, lensLines);
    const lens = { name, note: "" };
    if (from) {
      used.add(from);
      if (!pillOf.has(from)) pillOf.set(from, name);
      if (from.stop) lens.stop = from.stop;
      if (from.set) lens.set = from.set;
      const extra = leftover(from, name);
      if (extra && /[a-z]/i.test(extra)) notes.push(`${name}: ${extra}`);
    }
    sheet.lenses.push(lens);
  }
  const labelsSaid = new Map();
  for (const one of lensLines) {
    if (!lensPills.length) {
      const name = squash([one.parts[0], one.dashed ? one.parts.slice(1).filter((p) => !STOP.test(p)).join(" ") : ""].join(" ")) || one.rest;
      sheet.lenses.push({ name, note: "", ...(one.stop ? { stop: one.stop } : {}) });
      flag("note", "lenses", one.rest, "no lens pills; kept as typed");
    } else if (!used.has(one)) {
      flag("unplaced", "lenses", one.rest, "no lens pill matches this line");
    }
    if (one.label) {
      const cam = multi ? cameraFor(sheet, one.label) : null;
      if (cam || /^[a-h]\s*-?\s*cam/i.test(one.label)) {
        flag("note", "lenses", `${one.label}: ${one.rest}`, `the ${one.label} label dropped; a lens is the shoot's`);
      } else {
        if (!labelsSaid.has(one.label)) labelsSaid.set(one.label, []);
        labelsSaid.get(one.label).push(pillOf.get(one) || one.rest);
        flag("note", "lenses", `${one.label}: ${one.rest}`, `${one.label} is not a camera; written in Notes`);
      }
    }
  }
  notes.unshift(...[...labelsSaid].map(([label, list]) => `${label}: ${list.join(", ")}`));

  // ---- LUTs: a camera's own when "LUT Labels" names it, else every camera's
  const files = ((props["Production LUT"] || {}).files || []).map((f) => {
    const held = f.type === "file";
    const url = held ? "" : String(((f.external || {}).url) || "");
    return { name: squash(f.name) || url, url, held };
  });
  const labelText = oldText(props["LUT Labels"]);
  const named = lutRows(files.map((f) => ({ ...f, url: f.url })), labelText);
  const meantForCameras = multi && entries(labelText).some((e) => e.label && cameraFor(sheet, e.label));
  named.rows.forEach((row, i) => {
    const f = files[i];
    const cam = row.label && multi ? cameraFor(sheet, row.label) : null;
    const lut = { label: cam ? "" : row.label, name: f.name, url: f.url, ...(f.held ? { held: true } : {}) };
    if (f.held) flag("note", "luts", f.name, "Notion keeps this file itself; it is to be copied into the shoot's Drive folder");
    if (cam) cam.luts.push(lut);
    else if (meantForCameras && !row.label) {
      sheet.files.push(lut);
      flag("unplaced", "luts", f.name, "LUT Labels gives each camera a LUT by file name, and this link's name is not one of them; kept in the sheet's Files");
    } else {
      for (const c of cameras) c.luts.push(lut);
      if (multi) flag("note", "luts", f.name, "no camera named for it; on every camera");
    }
  });
  for (const stray of named.stray) {
    const [label] = splitLabel(stray);
    flag("unplaced", "luts", stray, label && multi && cameraFor(sheet, label)
      ? "names a file the sheet has no link by that name for"
      : "a LUT Labels line that matches no file");
  }

  // ---- Frame Guides and Finishing Resolution: a camera's own no more; the
  // sheet's two lists (the same rule the data fold used, foldCameraRows)
  const folded = foldCameraRows({ cameras, notes: "" });
  sheet.frames = folded.frames;
  sheet.finishing_resolutions = folded.finishing_resolutions;
  for (const line of folded.unplaced) flag("unplaced", line.box, line.value, "not a ratio or a resolution; written in Notes");
  if (folded.notes) notes.push(folded.notes);

  sheet.notes = notes.join("\n");
  const projects = (((props.Projects || {}).relation) || []).map((r) => bare(r.id));
  const shoots = (((props.Shoot || {}).relation) || []).map((r) => bare(r.id));
  if (!projects.length) flag("unplaced", "sheet", "", "the row names no project, so there is no record to put it on");
  if (projects.length > 1) flag("note", "sheet", "", `the row names ${projects.length} projects; it goes on the first`);
  if (shoots.length > 1) flag("note", "sheet", "", `the row names ${shoots.length} shoots; it goes on the first`);
  const shoot = shoots[0] || "";
  const title = squash(fieldText(props.Title) || fieldText(props.Name));
  const checked = checkSheet({ ...sheet, shoot, notion: bare(row && row.id), title });
  if (checked.why) {
    flag("unplaced", "sheet", "", checked.why);
    return { sheet: null, flags, project: projects[0] || "", shoot, fact: specFact(shoot), title };
  }
  return { sheet: checked.sheet, flags, project: projects[0] || "", shoot, fact: specFact(shoot), title };
}

/** A row's camera boxes as every reader takes them while the switch is off:
 * the move's reading, as labelled text, with LUT Labels as Notion has it. */
export function boxesOfRow(row, options = {}) {
  if (!row) return Object.fromEntries([...BOXES, "lenses", "luts"].map((b) => [b, ""]));
  const { sheet } = sheetFromNotion(row, options);
  const boxes = sheet ? textView(sheet).boxes : {};
  const out = {};
  for (const b of [...BOXES, "lenses"]) out[b] = boxes[b] || fieldText(((row.properties || {})[NOTION[b]]));
  out.luts = fieldText((row.properties || {})["LUT Labels"]);
  return out;
}

/** The look: every row as it would become. Writes nothing. */
export function lookAt(rows, options = {}) {
  return (rows || []).map((row) => {
    const got = sheetFromNotion(row, options);
    return { row: bare(row.id), ...got };
  });
}

/** The look as plain lines, for him and for the coordinator. */
export function lookText(report) {
  const out = [];
  for (const one of report) {
    out.push(`${one.title || one.row} · record ${one.project || "none"} · ${one.fact}`);
    const s = one.sheet;
    if (s) {
      for (const c of s.cameras) {
        const bits = BOXES.filter((b) => b !== "body").map((b) => (c[b].length ? `${WORDS[b]} ${c[b].join(", ")}` : "")).filter(Boolean);
        out.push(`  ${c.label}: ${c.body || "(no body)"} · ${bits.join(" · ")}`);
        for (const l of c.luts) out.push(`    LUT ${l.label ? `${l.label} ` : ""}${l.name}${l.held ? " (held by Notion)" : ""}`);
      }
      if (s.frames) out.push(`  Aspect Ratio: ${s.frames.map((f) => `${f.name} ${f.ratio}${f.main ? " (Main)" : ""}${(f.guides || []).length ? ` [${f.guides.length} frame guides]` : ""}`).join(" · ")}`);
      if (s.finishing_resolutions) out.push(`  Finishing Resolutions: ${s.finishing_resolutions.map((f) => [f.title, f.resolution, f.note].filter(Boolean).join(" · ")).join(" | ")}`);
      out.push(`  Lenses: ${s.lenses.map((l) => [l.name, l.stop, l.note].filter(Boolean).join(" ")).join(" · ") || "none"}`);
      if (s.notes) out.push(`  Notes: ${s.notes.split("\n").join(" · ")}`);
      for (const f of s.files) out.push(`  File: ${f.name}`);
    }
    for (const f of one.flags) out.push(`  ${f.level === "unplaced" ? "COULD NOT PLACE" : "note"} [${f.field}] ${f.line ? `“${f.line}” ` : ""}${f.why}`);
  }
  return out.join("\n");
}

// ---------------------------------------------------------- the record side

/** The record's sheets: {fact name: sheet}, each checked. */
export function recordSheets(facts) {
  const out = {};
  for (const [name, one] of Object.entries(facts || {})) {
    if (!SPEC_FACT.test(name) || !isObject(one) || !isObject(one.value)) continue;
    const got = checkSheet(one.value);
    if (got.sheet) out[name] = { sheet: got.sheet, v: one.v || 0 };
  }
  return out;
}

/** The sheet a shoot reads: its own, else the project's. {fact, sheet, v} or null. */
export function sheetForShoot(sheets, shoot) {
  const own = PAGE.test(bare(shoot)) ? sheets[`spec_${bare(shoot)}`] : null;
  if (own) return { fact: `spec_${bare(shoot)}`, ...own };
  if (sheets[PROJECT_KEY]) return { fact: PROJECT_KEY, ...sheets[PROJECT_KEY] };
  return null;
}

/** An aspect ratio as the camera page takes it, with its frame guide files. */
export const ratioOnCard = (f) => ({ name: f.name, ratio: f.ratio, main: f.main === true,
  ...((f.guides || []).length ? { guides: f.guides.map((g) => ({ name: g.name, camera: g.camera, note: g.note, url: g.url })) } : {}) });

/** Files for the camera page: a link as it is; a file Notion keeps, the copy
 * the card already has, else its name marked held (the page says it is in
 * Notion until it is copied to Drive). A file that is not a LUT keeps `kind`. */
function filesOnCard(files, had) {
  const out = [];
  for (const f of files) {
    const kind = f.kind ? { kind: f.kind } : {};
    if (f.url) { out.push({ name: f.name || f.url, url: f.url, ...kind }); continue; }
    const copy = (had || []).find((x) => x && x.file && String(x.name).toLowerCase() === String(f.name).toLowerCase());
    out.push(copy ? { ...copy, held: true, ...kind } : { name: f.name, url: "", held: true, ...kind });
  }
  return out;
}

/**
 * **The record's sheets laid on a card** (the switch on): each shoot reads its
 * own sheet, else the project's; the card's lead camera is the lead shoot's.
 * A shoot with neither keeps Notion's. Returns the shoots it laid.
 */
export function laySheets(card, sheets, cfOf = null) {
  const laid = [];
  if (!card || !Object.keys(sheets || {}).length) return laid;
  const lay = (one, got) => {
    const view = textView(got.sheet);
    // the sheet's notes ride along for the camera page's Notes row; a stored
    // card drops them (tidy keeps CAMERA's boxes only), read time lays them again.
    // So do its aspect ratios (frames: name and ratio, Main first) and its
    // finishing resolutions (its own, else the project sheet's), 2026-10-15.
    const frames = framesOf(got.sheet).filter((f) => f.ratio || (f.guides || []).length);
    one.camera = {
      ...(one.camera || {}), ...view.boxes, notes: String(got.sheet.notes || ""),
      ratios: [...frames.filter((f) => f.main), ...frames.filter((f) => !f.main)].map(ratioOnCard),
      finishing_resolutions: finishingOf(sheets, got.fact).map((f) => ({ ...f })),
    };
    // each lens's close focus, off the lens library ("CF 0.35 m"), by its line
    // on the page; a lens with none is not named (2026-10-15)
    if (cfOf) {
      const cf = {};
      for (const l of got.sheet.lenses || []) {
        const said = cfOf(l);
        if (said) cf[l.note ? `${l.name} · ${l.note}` : l.name] = said;
      }
      if (Object.keys(cf).length) one.camera.lens_cf = cf;
    }
    one.camera_files = filesOnCard(view.files, one.camera_files);
  };
  const shoots = Array.isArray(card.shoots) ? card.shoots : [];
  for (const one of shoots) {
    const got = sheetForShoot(sheets, one.id);
    if (got) { lay(one, got); laid.push(one.name || one.id); }
  }
  const lead = leadShoot(card);
  const got = lead ? sheetForShoot(sheets, lead.id) : sheets[PROJECT_KEY] ? { fact: PROJECT_KEY, ...sheets[PROJECT_KEY] } : null;
  if (got) { lay(card, got); if (!lead) laid.push("the project"); }
  return laid;
}

/** The switch: {on, at, by}. Off until he throws it. */
export async function specSwitch(env) {
  try {
    const got = await env.BUCKET.get(SWITCH_KEY);
    if (got) {
      const said = await got.json();
      return { on: said.on === true, at: String(said.at || ""), by: String(said.by || "") };
    }
  } catch { /* off */ }
  return { on: false, at: "", by: "" };
}

/** A card with the record's sheets laid on, when the switch is on — read
 * time, so the portal is right whoever wrote the card last. */
export async function withRecordSheets(env, project, card) {
  if (!(await specSwitch(env)).on) return card;
  const { recordPageOf, recordView } = await import("./facts.js");
  const page = await recordPageOf(env, project, card);
  if (!page) return card;
  const sheets = recordSheets((await recordView(env, page)).facts);
  if (!Object.keys(sheets).length) return card;
  let cfOf = null;
  try {
    const { readLibrary, entryOfSheetLens, cfLabel } = await import("./lenslibrary.js");
    const lib = (await readLibrary(env)).library;
    cfOf = (lens) => cfLabel(entryOfSheetLens(lib, lens));
  } catch { cfOf = null; }
  laySheets(card, sheets, cfOf);
  return card;
}

// --------------------------------------------------------- the hub's doors

/** Every row of Camera Spec Sheets, and each column's pills, through the hub's Notion key. */
async function rowsFromNotion(env) {
  const { notionOf } = await import("./cloud.js");
  const n = notionOf(env);
  const ds = await n.get(`data_sources/${SOURCE}`);
  const options = {};
  for (const [name, field] of Object.entries(ds.properties || {})) {
    if (field.type === "multi_select") options[name] = ((field.multi_select || {}).options || []).map((o) => o.name || "");
  }
  const rows = [];
  let cursor;
  for (let page = 0; page < 20; page++) {
    const got = await n.post(`data_sources/${SOURCE}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    rows.push(...(got.results || []));
    if (!got.has_more) break;
    cursor = got.next_cursor;
  }
  return { rows, options };
}

/** The look on the hub: each sheet as it would be written, and whether its record is there. */
export async function lookOnHub(env) {
  const { rows, options } = await rowsFromNotion(env);
  const report = lookAt(rows, options);
  for (const one of report) {
    one.record = Boolean(one.project && await env.BUCKET.head(`r/${one.project}/record.json`));
    if (one.project && !one.record) one.flags.push({ level: "unplaced", field: "sheet", line: "", why: "the project has no record on the hub yet" });
    if (one.record) {
      const { recordView } = await import("./facts.js");
      const facts = (await recordView(env, one.project)).facts || {};
      one.already = Boolean(facts[one.fact]);
      if (one.already) one.flags.push({ level: "note", field: "sheet", line: "", why: `the record has ${one.fact} already; the move leaves it as it is` });
    }
  }
  return { sheets: report.length, report, text: lookText(report) };
}

/**
 * **One sheet, moved by hand** (2026-10-15): a shoot whose sheet is still only a
 * row in Notion is made a sheet on the record, so from then on it is edited
 * there — the record is the master, and an edit never waits on Notion. The
 * same reading as the move (`sheetFromNotion`), for the one row he named, on
 * the shoot he named (`shootId` "" or "principal" = the project's own). A sheet
 * the record already has is left as it is. Record facts only: Notion is read,
 * never written. Answers {ok, fact, v, moved} or {ok:false, why}.
 */
export async function adoptSheet(env, n, { page, shootId = "", sheetId = "", by = "" } = {}) {
  const project = bare(page);
  const sheet = bare(sheetId);
  if (!PAGE.test(project) || !PAGE.test(sheet)) return { ok: false, why: "Say which project and which sheet." };
  const fact = specFact(shootId);
  const { recordView, writeFacts } = await import("./facts.js");
  const facts = (await recordView(env, project)).facts || {};
  if (isObject(facts[fact]) && isObject(facts[fact].value)) return { ok: true, fact, v: facts[fact].v || 0, moved: false };
  if (!(await env.BUCKET.head(`r/${project}/record.json`))) return { ok: false, why: "This project has no record yet." };
  const row = await n.get(`pages/${String(sheetId).trim()}`);
  const props = (row && row.properties) || {};
  const rel = (name) => (((props[name] || {}).relation) || []).map((r) => bare(r.id));
  const mine = rel("Projects").includes(project) || (PAGE.test(bare(shootId)) && rel("Shoot").includes(bare(shootId)));
  if (!mine) return { ok: false, why: "That sheet isn't this shoot's." };
  const ds = await n.get(`data_sources/${SOURCE}`);
  const options = {};
  for (const [name, field] of Object.entries(ds.properties || {})) {
    if (field.type === "multi_select") options[name] = ((field.multi_select || {}).options || []).map((o) => o.name || "");
  }
  const got = sheetFromNotion(row, options);
  if (!got.sheet) return { ok: false, why: (got.flags.find((f) => f.level === "unplaced") || {}).why || "That sheet could not be read." };
  const checked = checkSheet({ ...got.sheet, shoot: PAGE.test(bare(shootId)) ? bare(shootId) : "" });
  if (checked.why) return { ok: false, why: checked.why };
  const value = { ...checked.sheet, moved: { from: "notion", at: new Date().toISOString(), by: String(by || "").slice(0, 80) } };
  const wrote = await writeFacts(env, project, { [fact]: { value, base: 0 } }, `spec sheet move${by ? ` · ${by}` : ""}`);
  if (wrote.status === 409) {
    const now = (await recordView(env, project)).facts || {};
    return { ok: true, fact, v: (now[fact] || {}).v || 0, moved: false };      // made meanwhile: that one stands
  }
  if (wrote.status !== 200) return { ok: false, why: wrote.problem || "The record could not be written. Try again." };
  return { ok: true, fact, v: wrote.facts[fact].v, moved: true };
}

/** The words the move must be sent with, so it is never run by accident. */
export const CONFIRM = "move the spec sheets";

/**
 * **The move, for real**: each sheet written onto its record, from version 0
 * so a sheet the record already has is never written over. Record facts only:
 * Notion is read, never written. Only with `confirm` exactly CONFIRM.
 */
export async function moveSheets(env, { confirm = "", by = "" } = {}) {
  if (confirm !== CONFIRM) return { status: 400, why: `Say confirm: “${CONFIRM}”. Look first (POST /console/studio/specsheet/look).` };
  const look = await lookOnHub(env);
  const { writeFacts } = await import("./facts.js");
  const at = new Date().toISOString();
  const done = [];
  for (const one of look.report) {
    if (!one.sheet || !one.record || one.already) { done.push({ title: one.title, written: false }); continue; }
    const value = { ...one.sheet, moved: { from: "notion", at, by: String(by || "").slice(0, 80) } };
    const got = await writeFacts(env, one.project, { [one.fact]: { value, base: 0 } }, `spec sheet move${by ? ` · ${by}` : ""}`);
    done.push({ title: one.title, project: one.project, fact: one.fact, written: got.status === 200, ...(got.status === 200 ? {} : { why: got.problem || "the record had one already" }) });
  }
  return { status: 200, moved: done.filter((d) => d.written).length, done, text: look.text };
}
