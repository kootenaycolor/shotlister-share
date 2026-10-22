/**
 * **The rules of `hub/refresh.py` that need no Notion and no bucket** — the
 * film half of a card and the link covers' list and fingerprints — ported
 * rule for rule (2026-10-11, Projects Console without the Mac, stage 3 step 2).
 *
 * Pure on purpose: `node hub/refreshhub.mjs` checks every function here in
 * plain node against what the Python says on real films, and
 * `refreshhub.js` (the run itself, on the portal's clock) is the only caller.
 * Each says which Python it is. Change one, change both, the same day.
 */

// ------------------------------------------------------------ the film half

/** A picture's stored name prefers an image extension, in this order — `IMAGES`. */
export const IMAGES = ["jpg", "jpeg", "png", "webp", "heic"];

/** The extensions `_facts` counts as pictures. */
const COUNTED = new Set(["jpg", "jpeg", "png", "heic", "webp"]);

/**
 * The stored name of a picture, or "" — `proxy_named`. On the Mac the
 * question was "is this file in the film's proxies folder"; here it is "is it
 * in the film's media in the bucket", which is where the relay keeps the same
 * files under the same names. `names` is that folder's file names (a Set).
 */
export function proxyNamed(names, digest) {
  if (!digest) return "";
  const stem = String(digest).slice(0, 32);
  for (const extension of IMAGES) {
    if (names.has(`${stem}.${extension}`)) return `${stem}.${extension}`;
  }
  return "";
}

/** One picture from each thing, then more from the front, up to `want` — `some_pictures`. */
export function somePictures(groups, names, want) {
  const picked = [];
  for (let round = 0; round < 4; round += 1) {
    for (const media of groups) {
      if (picked.length >= want) return picked;
      if (round < media.length) {
        const name = proxyNamed(names, (media[round] || {}).hash || "");
        if (name && !picked.includes(name)) picked.push(name);
      }
    }
  }
  return picked;
}

/** What each way in is drawn with: frames, location photographs, board pictures — `drawn_with`. */
export function drawnWith(view, names) {
  const firstFrame = new Map();
  for (const group of view.groups || []) {
    for (const row of group.rows || []) {
      const scene = row.sceneId || "";
      const frame = row.frame || {};
      if (scene && !firstFrame.has(scene) && frame.hash) firstFrame.set(scene, frame.hash);
    }
  }
  const scenes = [];
  for (const scene of view.scenes || []) {
    if (scene.archived) continue;
    const name = proxyNamed(names, firstFrame.get(scene.id || "") || "");
    if (name && !scenes.includes(name)) scenes.push(name);
    if (scenes.length >= 8) break;
  }
  return {
    scenes,
    locations: somePictures((view.locations || []).map((l) => l.media || []), names, 5),
    boards: somePictures((view.boards || []).map((b) => b.media || []), names, 6),
  };
}

/**
 * How many pictures the film holds. **Not the Mac's count, by necessity**:
 * `_facts` counted the image files in the film's proxies folder on the Mac,
 * which the hub has no way to see. Here it is the image files the relay holds
 * for the film under the engine's naming (32 hex characters and an image
 * extension) — the same files, plus any picture a refresh copied out of
 * Notion beside them. Nothing on the portal draws this number (`withFilm` in
 * `front.js` keeps it as stored and never shows it).
 */
export function pictureCount(names) {
  let n = 0;
  for (const name of names) {
    const m = /^[0-9a-f]{32}\.([A-Za-z0-9]{1,8})$/.exec(name);
    if (m && COUNTED.has(m[1].toLowerCase())) n += 1;
  }
  return n;
}

/**
 * What the film itself says, out of the engine's own view of it — `_facts`,
 * the same fields in the same order. `view` is the engine's `view()` (the
 * same description `dump_view` prints on the Mac); `names` the film's media.
 */
export function factsFromView(view, names, pictures) {
  const project = view.project || {};
  return {
    pictures: drawnWith(view, names),
    days: (view.days || []).filter((d) => d.date).map((d) => ({ label: d.label || "", date: d.date || "" })).slice(0, 12),
    director: project.director || "",
    producer: project.producer || "",
    ratio: project.ratio || 0,
    console_page: project.consolePage || "",
    counts: {
      scenes: (view.scenes || []).length,
      shots: (view.groups || []).reduce((n, g) => n + (g.rows || []).length, 0),
      locations: (view.locations || []).length,
      boards: (view.boards || []).length,
      days: (view.days || []).length,
      pictures,
    },
  };
}

// ------------------------------------------------------------ which Notion page

/**
 * Which Notion project this film is, and how it was found — `page_for`: its
 * own link (the film's `consolePage`) first, then its title against every
 * Projects row's `Project`, word for word, case aside. `prop` is the reader
 * of a property (Python's own, `pyProp` in `refreshhub.js`).
 */
export function pageFor(fact, title, projects, prop) {
  if (fact.console_page) return { page: fact.console_page.replace(/-/g, ""), how: "link" };
  for (const row of projects) {
    if (prop(row, "Project").trim().toLowerCase() === String(title).trim().toLowerCase()) {
      return { page: String(row.id).replace(/-/g, ""), how: "name" };
    }
  }
  return { page: "", how: "" };
}

// ------------------------------------------------------------- the link covers

const MONTHS = ["January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"];

/** `MONTHS[m - 1]` as Python reads it: 0 is December (index -1); past 12 is an error. */
function month(m) {
  const at = m - 1;
  const got = at < 0 ? MONTHS[MONTHS.length + at] : MONTHS[at];
  if (got === undefined) throw new Error(`list index out of range (month ${m})`);
  return got;
}

/** `int(p) for p in start.split("-")` into three — Python's ValueError otherwise. */
function ymd(text) {
  const parts = String(text).split("-");
  if (parts.length !== 3 || !parts.every((p) => /^\s*[+-]?\d+\s*$/.test(p))) {
    throw new Error(`not a date: ${JSON.stringify(text)}`);
  }
  return parts.map((p) => parseInt(p, 10));
}

/** `2 – 4 November`, or `2 November`, or nothing at all — `shoot_dates_text`. */
export function shootDatesText(shoot) {
  const start = (shoot || {}).start || "";
  if (!start) return "";
  const [sy, sm, sd] = ymd(start);
  const end = (shoot || {}).end || "";
  if (!end || end === start) return `${sd} ${month(sm)}`;
  const [ey, em, ed] = ymd(end);
  if (sm === em && sy === ey) return `${sd} – ${ed} ${month(em)}`;
  return `${sd} ${month(sm)} – ${ed} ${month(em)}`;
}

/** The record's own pages and the program's tabs, by the names a cover says — the two lists in `refresh.py`. */
export const RECORD_PAGES = [["script", "Script"], ["bible", "Visual Bible"], ["camera", "Camera Spec Sheet"],
  ["people", "People"], ["documents", "Documents"]];
export const PROGRAM_PAGES = [["shotlist", "Shot List"], ["locations", "Locations"],
  ["boards", "Reference Images"], ["schedule", "Schedule"], ["diagrams", "Diagrams"]];

/** The icon's key in `covers.json`: a dot, which a slug may not carry. */
export const ICON = "icon.png";

/**
 * Every card a link into this film may unfurl into — `covers_wanted`: the
 * film's (key ""), one per page of the record and per tab of the program, a
 * page he named in Notion under its own name, and the 512-square icon.
 * A Map, so the order is Python's dict order (it is the order they are drawn).
 */
export function coversWanted(title, card) {
  const mark = card.mark || {};
  const base = {
    title,
    path: mark.path || "",
    colour: mark.colour || "",
    status: card.status || "",
    shoot: shootDatesText(card.shoot),
  };
  const wanted = new Map([["", { ...base, logline: card.logline || "" }]]);
  const names = new Map([...RECORD_PAGES, ...PROGRAM_PAGES]);
  for (const section of card.sections || []) {
    const slug = section.slug || "";
    const name = section.name || "";
    if (slug && name && /^[a-z0-9-]{1,64}$/.test(slug)) names.set(slug, name);
  }
  for (const [slug, name] of names) wanted.set(slug, { ...base, page: name });
  wanted.set(ICON, { ...base, icon: true });
  return wanted;
}

/**
 * `json.dumps(value, sort_keys=True)` exactly — Python's separators (", " and
 * ": "), keys sorted, and every character outside printable ASCII written as
 * `\uXXXX` (lower case), the short forms for the five Python has them for.
 * Only what a cover's spec holds is needed: strings, `true`, whole numbers.
 */
export function pyJson(value) {
  if (value === null || value === undefined) return "null";
  if (value === true) return "true";
  if (value === false) return "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("not a JSON number");
    return Number.isInteger(value) ? String(value) : pyFloat(value);
  }
  if (typeof value === "string") return pyString(value);
  if (Array.isArray(value)) return `[${value.map(pyJson).join(", ")}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map((k) => `${pyString(k)}: ${pyJson(value[k])}`).join(", ")}}`;
}

function pyFloat(n) {
  // Python's repr: the shortest round-trip, as JavaScript's, but with "e+XX"/"e-XX" spelled 2 digits.
  const said = String(n);
  const m = /^(-?[\d.]+)e([+-])(\d+)$/.exec(said);
  if (!m) return said.includes(".") ? said : `${said}.0`;
  return `${m[1]}e${m[2]}${m[3].padStart(2, "0")}`;
}

const SHORT = { '"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f" };

function pyString(text) {
  let out = '"';
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    const code = text.charCodeAt(i);
    if (SHORT[ch]) out += SHORT[ch];
    else if (code < 0x20 || code > 0x7e) out += `\\u${code.toString(16).padStart(4, "0")}`;
    else out += ch;
  }
  return `${out}"`;
}

/** A cover's fingerprint in `covers.json` — `sha256(json.dumps(spec, sort_keys=True))[:16]`. */
export async function fingerprint(spec) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(pyJson(spec)));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}
