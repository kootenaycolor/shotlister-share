/**
 * **The project record, from the AI connector** (2026-10-05).
 *
 * Projects Console grew the record — logline, synopsis, Director's Note,
 * Visual Language, status, type, length, client, agency, colour, icon, shoot
 * dates, website, Drive folder, credits as lists, custom links, and what each
 * project hides — and the connector reached only four of those (`set_front`)
 * and wrote the rest onto the portal's card, where the next refresh put
 * Notion's words back. Here every project fact the connector writes goes
 * through `writeFacts`: one version each, compare-and-set, kept in the
 * history as the AI connector's, and carried into Notion and the film by the
 * Studio's link and film mirror like anything typed in the console.
 *
 * **What the project hides is not written.** The console's readout says it
 * (`hidden`, recordlayout.py: the Type's standard and Customize Record). A
 * write to a hidden fact is refused, not dropped — and nothing here deletes:
 * a hidden fact keeps its words.
 *
 * The rules below are the console's, ported: `notionlink.dates_refusal`,
 * `url_refusal`, `icon_refusal`, `STATUS_THE_LINK_MAY_SET`,
 * `record.links_plan`, `recordlayout.FIELDS`. Change one, change both.
 */
import { canonStage, shownStage } from "./stageword.js";
import { writeFacts, recordPageOf } from "./facts.js";
import { storedFront } from "./front.js";
import { ROLES, MIRRORS, creditsOf, creditsPlan, withPeople, creditHidden, creditLine, splitNames } from "./credits.js";
import { shootParts } from "./notion.js";
import { lensSetsSaid } from "./lenses.js";
import { shootsWithCrew } from "./mcpshoots.js";

/** Who the history says wrote it. The same words `set_front` has used. */
export const BY = "portal AI connector";

/** The facts the connector writes, in the console's order. */
export const WRITABLE = ["logline", "synopsis", "directors_note", "visual_language", "status", "type", "length",
  "client", "agency", "color", "icon", "shoot_dates", "website", "drive_folder"];

export const LABEL = { title: "Title", logline: "Logline", synopsis: "Synopsis", directors_note: "Director's Note",
  visual_language: "Visual Language", status: "Status", type: "Type", length: "Length", client: "Client",
  agency: "Agency", color: "Colour", icon: "Icon", shoot_dates: "Shoot Dates", website: "Website",
  drive_folder: "Drive Folder" };

/** Facts a project may hide — recordlayout.FIELDS. */
const HIDEABLE = ["logline", "synopsis", "directors_note", "visual_language", "length", "client", "agency",
  "shoot_dates", "website"];

/** Stages the record may set at once; Released, Post and Archived ask him
 * first in the console's stage picker, and so here: `set_stage` (consoletools.js). */
const STAGES = ["Development", "Active"];
const TYPES = ["Narrative", "Commercial", "Music Video", "Personal"];
export const COLOURS = ["gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"];

/** Notion's built-in icons the console's picker offers — notionlink.ICON_NAMES. */
export const ICON_NAMES = new Set(`
add airplane alarm alert alien ambulance anchor apple archive arrow-down arrow-left arrow-right arrow-up
avocado baby backpack bag balloon banana barcode baseball basketball battery bed bee beer bell bicycle
binoculars bluetooth boat bone book bookmark boombox bowling brain bread briefcase broccoli bug bullseye
burger bus butterfly cactus cafe cake calculator calendar camera camera-off candy car card cards carrot
cassette castle cat cd chair chart chat check checklist checkmark chess-bishop chess-king chess-knight
chess-pawn chess-queen chess-rook chicken child church circle city clock close cloud clover cocktail code
coffee comment compass corn couch cow crab daisy database delete dining dna document dog download dress
drink duck ear egg elephant elevator factory fire fire-truck fireworks fish flag flag-checkered flash
flashlight fog folder football fork forward gear gem ghost gift glasses globe golf grapes grid guitar
hammer headphones headset heart heart-outline heartbroken helicopter hexagon home hourglass inbox infinity
key keyboard knife knife-kitchen laptop leaf lemon library link list location lock luggage magic-wand
magnet mail map map-pin meat megaphone microphone microscope microwave mobile moon motorcycle mountains
mouth movie movie-camera mushroom music octagon orange oven package paint-roller passport pear pen pencil
pentagon people phone piano pig pill pin pizza plus postcard pot power puzzle radio rain rainbow refresh
remove repeat robot rocket ruler run sailboat school science scooter send server share sharing shield
shirt shoe shop shower shuffle skateboard skull snake snowflake soccer sock spider spoon square stairs
star star-outline stars stethoscope stopwatch storm strawberry suitcase sun sunglasses sunrise sunset
sword sync syringe table tablet tag target taxi teapot telescope theatre thumbs-down thumbs-up ticket
toilet tooth tornado traffic-light train tree triangle trophy truck trumpet tulip tv umbrella unlock
upload user video-camera violin walk warning water whale wifi wind window wine wrench
`.split(/\s+/).filter(Boolean));

const ICON_URL = /^https:\/\/www\.notion\.so\/icons\/([a-z0-9_-]+)_([a-z]+)\.svg$/i;
const WEB = /^https?:\/\/[^\s<>"']+$/i;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const SLOT = /^(drive|website|film|deck|doc|watch|shoot:[0-9a-f]{32}:(spec|callsheet))$/;
const oneLine = (said) => String(said == null ? "" : said).replace(/\s+/g, " ").trim();

/** The open project's record: {page, record} — or null when it has none. */
export async function recordOfOpen(env, project) {
  const card = await storedFront(env, project);
  const page = await recordPageOf(env, project, card);
  if (!page) return null;
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try {
    const record = await got.json();
    return { page, record, card, facts: record.facts || {}, hidden: Array.isArray(record.hidden) ? record.hidden.map(String) : [] };
  } catch {
    return null;
  }
}

const factValue = (facts, field) => {
  const one = (facts || {})[field];
  return one && typeof one === "object" ? one.value : undefined;
};

function realDay(day) {
  const d = new Date(`${day}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === day;
}

/** "2026-10-06", "2026-10-06/2026-10-08" or "" — or why not (dates_refusal). */
export function datesRefusal(value) {
  const [start = "", end = ""] = String(value || "").trim().split("/").map((s) => s.trim());
  if (!start && !end) return "";
  for (const d of [start, end]) if (d && !DAY.test(d)) return `“${d}” isn't a day (YYYY-MM-DD).`;
  if (end && !start) return "An end day needs a first day.";
  if (end && end < start) return "The last day is before the first.";
  for (const d of [start, end]) if (d && !realDay(d)) return `“${value}” isn't a real day.`;
  return "";
}

/** Shoot dates as the record keeps them: one day alone, two joined by "/". */
export function datesFrom(start, end) {
  const a = String(start || "").trim();
  const b = String(end || "").trim();
  return b && b !== a ? `${a}/${b}` : a;
}

/** A Notion built-in icon address from what was said: an address, `name`,
 * or `name_colour`. Null when it is none of those. */
export function iconFrom(said, colour) {
  const s = String(said || "").trim();
  const url = ICON_URL.exec(s);
  if (url) return { name: url[1].toLowerCase(), colour: url[2].toLowerCase() };
  const m = /^([a-z0-9-]+?)(?:[_ ]([a-z]+))?$/i.exec(s);
  if (!m) return null;
  return { name: m[1].toLowerCase(), colour: (m[2] || colour || "gray").toLowerCase() };
}

/** The values a choice fact already takes on his projects (Notion's own
 * spelling), so a word Notion has no choice for is refused here rather than
 * becoming a "can't be written to Notion" card for him later. */
async function choicesInUse(env, field) {
  const seen = new Map();
  if (field === "type") for (const t of TYPES) seen.set(t.toLowerCase(), t);
  const prefixes = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor });
    prefixes.push(...(got.delimitedPrefixes || []));
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  const records = await Promise.all(prefixes.map(async (p) => {
    try { const got = await env.BUCKET.get(`${p}record.json`); return got ? await got.json() : null; } catch { return null; }
  }));
  for (const r of records) {
    if (!r) continue;
    for (const v of [factValue(r.facts, field), r[field]]) {
      const t = oneLine(v);
      if (t && !seen.has(t.toLowerCase())) seen.set(t.toLowerCase(), t);
    }
  }
  return seen;
}

/**
 * Check what was asked against the record's rules. Returns {changes, skipped,
 * refused}: `changes` are {field: {value, base}} ready for `writeFacts`;
 * `skipped` are facts that already say that; `refused` are {field: why}.
 * `seen` is the version the caller last read, per fact; without it the
 * version just read is used.
 */
export async function planFacts(env, view, asked, seen = {}) {
  const changes = {};
  const skipped = [];
  const refused = {};
  const facts = view.facts;
  for (const [field, raw] of Object.entries(asked)) {
    if (raw === undefined || raw === null) continue;
    if (!WRITABLE.includes(field)) { refused[field] = "not a fact the connector writes"; continue; }
    if (HIDEABLE.includes(field) && view.hidden.includes(field)) {
      refused[field] = `${LABEL[field]} is hidden on this project (its Type's standard or Customize Record in Projects Console). Its words are kept; nothing written`;
      continue;
    }
    let value = typeof raw === "string" ? raw : String(raw);
    const now = factValue(facts, field);
    // A choice already said, in any case, is not a change — and asks nothing.
    if (["status", "type", "length", "color"].includes(field) && typeof now === "string"
        && now.toLowerCase() === oneLine(value).toLowerCase()) { skipped.push(field); continue; }
    if (field === "status") {
      const pick = STAGES.find((s) => s.toLowerCase() === oneLine(value).toLowerCase());
      if (!pick) {
        if (typeof now === "string" && now.toLowerCase() === oneLine(value).toLowerCase()) { skipped.push(field); continue; }
        refused[field] = `“${oneLine(value) || "nothing"}” isn't set from here — the record sets ${STAGES.join(" or ")}; Complete, Post and Archived ask him first: set_stage`;
        continue;
      }
      value = pick;
    } else if (field === "type" || field === "length") {
      const choices = await choicesInUse(env, field);
      const pick = choices.get(oneLine(value).toLowerCase());
      if (!pick) {
        refused[field] = `“${oneLine(value)}” isn't one of the ${LABEL[field]} choices in use (${[...choices.values()].join(", ")}). A new choice is added in Notion`;
        continue;
      }
      value = pick;
    } else if (field === "client" || field === "agency") {
      value = oneLine(value);
      if (value.length > 300) { refused[field] = "a name, not a paragraph (300 characters at most)"; continue; }
    } else if (field === "color") {
      value = oneLine(value).toLowerCase().replace(/^grey$/, "gray");
      if (value && !COLOURS.includes(value)) { refused[field] = `one of ${COLOURS.join(", ")}`; continue; }
    } else if (field === "icon") {
      const colourNow = asked.color !== undefined ? oneLine(asked.color).toLowerCase() : factValue(facts, "color");
      const icon = iconFrom(value, COLOURS.includes(colourNow) ? colourNow : "gray");
      if (!icon || !ICON_NAMES.has(icon.name)) { refused[field] = "one of Notion's built-in icon names, e.g. `camera`, `movie`, `sun` (optionally `name_colour`)"; continue; }
      if (!COLOURS.includes(icon.colour)) { refused[field] = `the icon's colour is one of ${COLOURS.join(", ")}`; continue; }
      value = `https://www.notion.so/icons/${icon.name}_${icon.colour}.svg`;
    } else if (field === "shoot_dates") {
      value = oneLine(value).replace(/\s*\/\s*/, "/");
      const why = datesRefusal(value);
      if (why) { refused[field] = why; continue; }
      const [a, b] = value.split("/");
      value = datesFrom(a, b);
    } else if (field === "website" || field === "drive_folder") {
      value = value.trim();
      if (value && !WEB.test(value)) { refused[field] = `“${value.slice(0, 60)}” isn't a web address (https://…)`; continue; }
    }
    if (now === value) { skipped.push(field); continue; }
    const stored = facts[field];
    const v = stored && typeof stored === "object" ? Number(stored.v) || 0 : 0;
    const base = seen && seen[field] !== undefined ? Number(seen[field]) || 0 : v;
    changes[field] = { value, base };
  }
  return { changes, skipped, refused };
}

/** What a conflict says: each fact that moved, as it is now. */
export function conflictSaid(conflicts) {
  return Object.entries(conflicts || {}).map(([field, now]) => {
    const words = now && typeof now === "object" ? JSON.stringify(now.value) : "nothing";
    return `${LABEL[field] || field} changed since it was read — it is now ${words} (v${(now && now.v) || 0}, by ${(now && now.by) || "somebody"})`;
  }).join("; ");
}

// ---------------------------------------------------------------- the tools

export const RECORD_TOOLS = [
  {
    name: "record",
    description:
      "The open project's record — what defines it, as Projects Console shows it: title, logline, synopsis, Director's Note, Visual Language, status, type, length, client, agency, colour, icon, shoot dates, website, Drive folder, credits, custom links, and its Shoots and Crew (the record's copy, Notion follows). Each shoot comes with its `crew` (who is on it and their role on this project); one queued while Notion was unreachable is marked `waiting_for_notion`. A project's shoots and their crew live in this record: editing Notion's Shoots rows or a Notion project page directly does NOT reliably reach Studio, so always change them with add_shoot, set_shoot, set_shoot_crew and set_record. Each fact has `value` and its version `v`; pass `v` back in `seen` when writing. `hidden` lists what this project does not show (its Type's standard and Customize Record); a hidden fact keeps its words and is not written. Each shoot has its own `name` (\"\" for none) and `lens_sets` from its spec sheet; with no Shoots rows, `shoot_name` and `lens_sets` are the project's own shoot's.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_record",
    description:
      "Change facts on the open project's record. Only what is given changes; \"\" clears. The console, the portal, the Notion page and Studio follow. Refused: a fact this project hides; a status other than Development or Active (Complete, Post and Archived ask him first, as the console's stage picker does: `set_stage`; a Released project's date, credit and stills are `set_released`); a type or length that is not a choice already in use. The project's name is changed with Rename (`big_move` kind rename), not here. Credits: set_credit. Links: add_record_link.",
    inputSchema: {
      type: "object",
      properties: {
        logline: { type: "string" },
        synopsis: { type: "string" },
        directors_note: { type: "string", description: "Director's Note." },
        visual_language: { type: "string", description: "Visual Language." },
        status: { type: "string", description: "Development or Active. Complete, Post and Archived: set_stage." },
        type: { type: "string", description: "Narrative, Commercial, Personal, …" },
        length: { type: "string", description: "Short, Feature, …" },
        client: { type: "string" },
        agency: { type: "string" },
        color: { type: "string", description: "gray, brown, orange, yellow, green, blue, purple, pink or red." },
        icon: { type: "string", description: "A Notion built-in icon name (`camera`, `sun`, …), optionally `name_colour`. Takes the project's colour when none is said." },
        shoot_dates: { type: "string", description: "YYYY-MM-DD, or YYYY-MM-DD/YYYY-MM-DD for more than one day." },
        website: { type: "string", description: "An https:// address." },
        drive_folder: { type: "string", description: "An https:// address." },
        seen: { type: "object", description: "The version `v` each fact had when read, by the fact's name. A fact that has moved since is not written." },
      },
      required: [],
    },
  },
  {
    name: "set_credit",
    description:
      "Set who holds one credit on the open project, in order. `people` replaces that credit's list; [] takes the credit off. Roles: " + ROLES.join(", ") + ". Refused for a credit this project hides. Notion links only names already in Crew; any other stays on the record and Projects Console asks him.",
    inputSchema: {
      type: "object",
      properties: {
        role: { type: "string", description: "One of: " + ROLES.join(", ") + "." },
        people: { type: "array", items: { type: "string" }, description: "Names, in credit order." },
      },
      required: ["role", "people"],
    },
  },
  {
    name: "add_record_link",
    description:
      "Add a custom link to the open project's record — the console's Use a Custom Link…. `slot` is where it belongs: drive, website, film, deck, doc, watch (where the finished piece can be watched — a Complete project's portal home lists these), or a shoot's `shoot:<shoot id>:spec` / `shoot:<shoot id>:callsheet` (shoot ids from `record`). Notion is not changed.",
    inputSchema: {
      type: "object",
      properties: {
        slot: { type: "string" },
        url: { type: "string", description: "An https:// address." },
        title: { type: "string", description: "What to call it. Left out: the site and the last part of the address." },
      },
      required: ["slot", "url"],
    },
  },
  {
    name: "remove_record_link",
    description: "Remove one custom link from the open project's record, by its `id` from `record`.",
    inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },
  },
  {
    name: "rename_record_link",
    description: "Rename one custom link on the open project's record, by its `id` from `record` — the console's Rename on a link. Its address and place stay.",
    inputSchema: { type: "object", properties: { id: { type: "string" }, title: { type: "string", description: "Its new name." } }, required: ["id", "title"] },
  },
  {
    name: "set_shoot",
    description: "Change one of the project's shoots, as Projects Console's shoot editor does: `shoot` (its id from `record`'s `shoots`, its name, or 2 for Shoot 2), and any of `start` / `end` (YYYY-MM-DD; a one-day shoot leaves `end` out), `name` (what he calls it — \"Malibu Pickup\"; \"\" for none, so it reads as Shoot 2) and `notes` (What Changes). Saved on the record at once; his Notion Shoots row follows within a minute or two. Give `seen` ({start, end, name, notes} as you read them) so a shoot changed since is refused rather than written over. A new shoot is `add_shoot` (never this), and who is on a shoot is `set_shoot_crew`. A project's shoots live in its project record (Notion follows): editing Notion's Shoots rows directly does NOT reliably reach Studio, so always use these tools.",
    inputSchema: {
      type: "object",
      properties: {
        shoot: { type: "string" },
        start: { type: "string" },
        end: { type: "string" },
        name: { type: "string" },
        notes: { type: "string" },
        seen: { type: "object" },
      },
      required: ["shoot"],
    },
  },
  {
    name: "released",
    description:
      "A Complete project's release (Complete was called Released), as Projects Console shows it on the project and in its sheet: its release date, his credit (\"Cinematographer\" when none), the selects (the showcase stills he picked, in his order, each `id` and file `name`), the key still (one of the selects, the one that stands for the project; the first select when none is set), Featured (up to six selects he starred; until he stars any, the key still and the next picks), the folder the selects come from, and the website and watch links. `stills: true` also lists every still there is to pick from (`available`). Read this before set_released.",
    inputSchema: {
      type: "object",
      properties: { stills: { type: "boolean", description: "Also list every still there is to pick from." } },
      required: [],
    },
  },
  {
    name: "set_released",
    description:
      "Change a Complete project's release, as its sheet and the stills' stars in Projects Console do. The release date is optional. Only what is given changes. `released_date` YYYY-MM-DD (\"\" clears); `my_credit` his credit on it (\"\" goes back to Cinematographer); `key_still` one of the selects, by id or file name; `featured` the selects to star, at most six, in order ([] unstars them all); `selects` the whole list of selects in his order, by id or file name from `released` `stills: true`. **Which stills are selects, which is the key still and which are featured is his eye**: write exactly the stills he names, never ones you chose. Status Released is `set_stage` (it asks him first); Prepare Showcase (copying the selects into the showcase folder) is `big_move` kind showcase, with his OK. The website is `set_record` `website`, watch links `add_record_link` slot watch.",
    inputSchema: {
      type: "object",
      properties: {
        released_date: { type: "string", description: "YYYY-MM-DD." },
        my_credit: { type: "string", description: "His credit: Cinematographer, Director of Photography, …" },
        key_still: { type: "string", description: "A select's id or file name." },
        featured: { type: "array", items: { type: "string" }, description: "Selects to star, at most six, by id or file name." },
        selects: { type: "array", items: { type: "string" }, description: "Every select, in order, by id or file name." },
      },
      required: [],
    },
  },
  {
    name: "portal_documents",
    description:
      "The project's Drive files and which of them are on the portal's Documents page — Projects Console's Documents tab, the Show on Portal switches. Answers `on_portal` (each file's id, name, type, date and the group crew see it under: Schedule & Call Sheets, Script, Creative or Other), `suggested` (call sheets, schedules, the current script, decks and look books not yet on), and with `all: true` every file in the folder by its path (working files — project files, LUTs, z-archive — marked `working`). Files stay in Drive; crew open them through the portal.",
    inputSchema: {
      type: "object",
      properties: {
        all: { type: "boolean", description: "Every file in the project's Drive folder, not only what is on and suggested." },
        search: { type: "string", description: "Only files whose name or folder holds these words." },
      },
      required: [],
    },
  },
  {
    name: "show_on_portal",
    description:
      "Put a Drive file on the portal's Documents page, or take it off — his Show on Portal switch. `file` is its id or name as portal_documents lists it; `on` true shows it, false takes it off (it stops opening at once; nothing is deleted, the file stays in Drive). **His choice, file by file**: switch only a file he named, never one you picked, and never to share something with crew he has not asked to share. Files he hid in What Viewers See stay hidden.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "The file's id, or its name as portal_documents lists it." },
        on: { type: "boolean" },
      },
      required: ["file", "on"],
    },
  },
];

export const RECORD_TOOL_NAMES = new Set(RECORD_TOOLS.map((t) => t.name));

/** The record as `record` says it. */
export function recordSaid(found, view) {
  const facts = view.facts;
  const out = {};
  for (const field of ["title", ...WRITABLE]) {
    const one = facts[field];
    out[field] = one && typeof one === "object"
      ? { value: one.value, v: one.v || 0, at: one.at || "", by: one.by || "" }
      : { value: "", v: 0 };
    if (view.hidden.includes(field)) out[field].hidden = true;
  }
  const credits = creditsOf(facts).map((c) => (creditHidden(c.role, view.hidden) ? { ...c, hidden: true } : c));
  const linksOne = facts.links && typeof facts.links === "object" ? facts.links : {};
  const custom = linksOne.value && Array.isArray(linksOne.value.custom) ? linksOne.value.custom : [];
  return {
    project: oneLine(factValue(facts, "title")) || view.record.name || found.title,
    page: view.page,
    facts: out,
    credits,
    credits_v: (facts.credits && facts.credits.v) || 0,
    links: custom.filter((i) => i && i.url).map(({ id, slot, url, title }) => ({ id, slot, url, title })),
    links_v: linksOne.v || 0,
    ...shootsSaid(facts, view.card),
    crew: Array.isArray(factValue(facts, "crew")) ? factValue(facts, "crew") : [],
    hidden: view.hidden,
  };
}

/** The record's shoots, each with its own name and the lens sets of its spec
 * sheet as the portal last read it; with no Shoots rows, the project's own
 * shoot's name (`shoot_name`) and lens sets. */
function shootsSaid(facts, card) {
  const rows = Array.isArray(factValue(facts, "shoots")) ? factValue(facts, "shoots") : [];
  const onCard = new Map(((card && card.shoots) || []).map((one) => [one.id, one]));
  const own = (row) => {
    if (typeof row.name === "string") return row.name;
    const parts = shootParts(row.label || "");
    return parts.base !== parts.name ? parts.name : "";
  };
  const shoots = rows.map((row) => {
    if (!row || typeof row !== "object") return row;
    const portal = onCard.get(String(row.id || "").replace(/-/g, ""));
    const lenses = portal && portal.camera ? portal.camera.lenses : "";
    return { ...row, name: own(row), ...(lenses ? { lens_sets: lensSetsSaid(lenses) } : {}) };
  });
  const one = facts.shoot_name && typeof facts.shoot_name === "object" ? facts.shoot_name : {};
  // every shoot with the people on it (and any queued while Notion was out)
  const out = { shoots: shootsWithCrew(facts, shoots), shoot_name: { value: typeof one.value === "string" ? one.value : "", v: one.v || 0 } };
  const lenses = !rows.length && card && card.camera ? card.camera.lenses : "";
  if (lenses) out.lens_sets = lensSetsSaid(lenses);
  return out;
}

function linkTitle(url) {
  try {
    const u = new URL(url);
    const host = u.host.replace(/^www\./, "");
    const tail = decodeURIComponent(u.pathname || "").split("/").filter(Boolean);
    let last = tail.length ? tail[tail.length - 1] : "";
    if (/notion\.(so|site|com)$/.test(host)) last = last.replace(/-?[0-9a-f]{32}$/, "").replace(/-/g, " ").trim();
    if (last.length > 40 || /^[\w-]{20,}$/.test(last) || ["edit", "view", "d", "file"].includes(last)) last = "";
    return last ? `${host} · ${last}` : host;
  } catch {
    return url.slice(0, 60);
  }
}

/** The `links` fact's next value — record.links_plan. {value, base} or {why}. */
export function linksPlan(facts, { add = null, remove = "" } = {}) {
  const one = facts.links && typeof facts.links === "object" ? facts.links : {};
  const base = Number(one.v) || 0;
  const value = one.value && typeof one.value === "object" && !Array.isArray(one.value) ? { ...one.value } : {};
  let items = (Array.isArray(value.custom) ? value.custom : []).filter((i) => i && typeof i === "object" && i.url);
  if (add) {
    const url = String(add.url || "").trim();
    const slot = String(add.slot || "").trim();
    if (!WEB.test(url)) return { why: "That isn't a web address (https://…)." };
    if (!SLOT.test(slot)) return { why: `No place called “${slot}”. One of drive, website, film, deck, doc, watch, shoot:<shoot id>:spec, shoot:<shoot id>:callsheet.` };
    if (items.some((i) => i.url === url && i.slot === slot)) return { why: "That link is already there." };
    const title = oneLine(add.title).slice(0, 120) || linkTitle(url);
    items = [...items, { id: crypto.randomUUID().replace(/-/g, "").slice(0, 8), slot, url, title,
      at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"), by: BY }];
  }
  if (remove) {
    if (!items.some((i) => i.id === remove)) return { why: "That link was already removed." };
    items = items.filter((i) => i.id !== remove);
  }
  value.custom = items;
  return { value, base };
}

/**
 * The record's tools. `found` is the open project ({project, title, role});
 * `refuse` makes the connector's refusal.
 */
export async function recordTool(env, found, name, args, refuse) {
  const view = await recordOfOpen(env, found.project);
  if (!view) throw refuse(`${found.title} has no project record yet. Projects Console makes one when the project is linked to its Notion row.`);
  if (found.role !== "editor") throw refuse("Only an editor may read or change a project's record.");

  if (name === "record") return JSON.stringify(recordSaid(found, view), null, 1);

  if (name === "set_record") {
    const asked = {};
    for (const field of WRITABLE) if (args[field] !== undefined) asked[field] = args[field];
    if (!Object.keys(asked).length) throw refuse(`Say what to change: ${WRITABLE.join(", ")}.`);
    const seen = args.seen && typeof args.seen === "object" ? args.seen : {};
    const { changes, skipped, refused } = await planFacts(env, view, asked, seen);
    if (Object.keys(refused).length) {
      throw refuse(`Nothing written. ${Object.entries(refused).map(([f, why]) => `${LABEL[f] || f}: ${why}.`).join(" ")}`);
    }
    if (!Object.keys(changes).length) return `${skipped.map((f) => LABEL[f]).join(", ")} already say${skipped.length === 1 ? "s" : ""} that. Nothing written.`;
    const got = await writeFacts(env, view.page, changes, BY);
    if (got.status === 409) throw refuse(`Nothing written. ${conflictSaid(got.conflicts) || got.problem}. Read the record again.`);
    if (got.status !== 200) throw refuse(`The record would not take it: ${got.problem}`);
    return `Written to the record: ${Object.keys(changes).map((f) => `${LABEL[f]} (v${got.facts[f].v})`).join(", ")}. Projects Console shows it now; Notion and Studio follow within minutes.`;
  }

  if (name === "set_credit") {
    const said = oneLine(args.role).toLowerCase();
    const role = ROLES.find((r) => r.toLowerCase() === said);
    if (!role) throw refuse(`A credit is one of: ${ROLES.join(", ")}.`);
    if (creditHidden(role, view.hidden)) throw refuse(`${role} is hidden on this project (its Type's standard or Customize Record in Projects Console). Nothing written.`);
    if (!Array.isArray(args.people)) throw refuse("`people` is a list of names; [] takes the credit off.");
    const names = args.people.flatMap((n) => splitNames(n));
    let facts = view.facts;
    for (let attempt = 0; attempt < 3; attempt++) {
      const next = withPeople(creditsOf(facts), role, names);
      const changes = creditsPlan(facts, next);
      if (!Object.keys(changes).length) return `${role}: ${creditLine(names) || "nobody"} already. Nothing written.`;
      const got = await writeFacts(env, view.page, changes, BY);
      if (got.status === 200) {
        return `${role}: ${creditLine(names) || "taken off"}. Projects Console shows it now; Notion and Studio follow within minutes.`;
      }
      if (got.status !== 409 || !got.conflicts) throw refuse(`The record would not take it: ${got.problem}`);
      const again = await recordOfOpen(env, found.project);
      facts = again ? again.facts : facts;
    }
    throw refuse("The credits kept changing. Try again.");
  }

  if (name === "add_record_link" || name === "remove_record_link") {
    let facts = view.facts;
    for (let attempt = 0; attempt < 3; attempt++) {
      const plan = name === "add_record_link"
        ? linksPlan(facts, { add: { slot: args.slot, url: args.url, title: args.title } })
        : linksPlan(facts, { remove: String(args.id || "") });
      if (plan.why) throw refuse(plan.why);
      const got = await writeFacts(env, view.page, { links: { value: plan.value, base: plan.base } }, BY);
      if (got.status === 200) {
        if (name === "remove_record_link") return "Removed.";
        const made = plan.value.custom[plan.value.custom.length - 1];
        return `Added “${made.title}” to ${made.slot} (id ${made.id}).`;
      }
      if (got.status !== 409 || !got.conflicts) throw refuse(`The record would not take it: ${got.problem}`);
      const again = await recordOfOpen(env, found.project);
      facts = again ? again.facts : facts;
    }
    throw refuse("The links kept changing. Try again.");
  }
  if (name === "rename_record_link") {
    const { renamePlan } = await import("./step6recordsrules.js");
    let facts = view.facts;
    for (let attempt = 0; attempt < 3; attempt++) {
      const [value, base, why] = renamePlan(facts, String(args.id || ""), String(args.title || ""));
      if (why) throw refuse(why);
      const got = await writeFacts(env, view.page, { links: { value, base } }, BY);
      if (got.status === 200) return `Renamed to “${oneLine(args.title).slice(0, 120)}”.`;
      if (got.status !== 409 || !got.conflicts) throw refuse(`The record would not take it: ${got.problem}`);
      const again = await recordOfOpen(env, found.project);
      facts = again ? again.facts : facts;
    }
    throw refuse("The links kept changing. Try again.");
  }
  if (name === "set_shoot") return await shootTool(env, view, args, refuse);
  if (name === "released" || name === "set_released") return await releasedTool(env, found, view, name, args, refuse);
  if (name === "portal_documents" || name === "show_on_portal") return await portalDocsTool(env, view, name, args, refuse);
  throw refuse("No such tool.");
}

// ── one shoot's dates, name and notes (the console's edit_shoot, on the record) ──

async function shootTool(env, view, args, refuse) {
  const rows = Array.isArray(factValue(view.facts, "shoots")) ? factValue(view.facts, "shoots") : null;
  if (!rows || !rows.length) throw refuse("This project has no shoots on its record. A shoot is made with New Shoot.");
  const said = oneLine(args.shoot);
  const bare = said.replace(/-/g, "").toLowerCase();
  const nameOfRow = (row) => {
    if (typeof row.name === "string" && row.name) return row.name;
    const parts = shootParts(row.label || "");
    return parts.name || row.label || "";
  };
  const numbered = /^\d+$/.test(said) ? `shoot ${Number(said)}` : "";
  const hit = rows.filter((row) => row && (String(row.id || "").replace(/-/g, "").toLowerCase() === bare
    || oneLine(nameOfRow(row)).toLowerCase() === said.toLowerCase()
    || oneLine(row.label || "").toLowerCase() === said.toLowerCase()
    || (numbered && oneLine(shootParts(row.label || "").base || "").toLowerCase() === numbered)));
  if (hit.length !== 1) {
    const all = rows.map((row) => `${oneLine(row.label || nameOfRow(row))} (${row.id})`).join(", ");
    throw refuse(hit.length ? `More than one shoot answers to “${said}”: use its id. ${all}.` : `No shoot called “${said}”. This project's shoots: ${all}.`);
  }
  const changes = {};
  for (const k of ["start", "end", "name", "notes"]) if (args[k] !== undefined) changes[k] = String(args[k] == null ? "" : args[k]);
  if (!Object.keys(changes).length) throw refuse("Say what changes: start, end, name or notes.");
  const seen = args.seen && typeof args.seen === "object" ? args.seen : {};
  const { recordShootEdit } = await import("./shootedits.js");
  const got = await recordShootEdit(env, null, { id: view.page }, String(hit[0].id), seen, changes);
  if (!got) throw refuse("This project's shoots are not on its record yet, so they are changed in Notion.");
  if (got.moved) throw refuse(`Nothing written: it changed since you read it (${Object.entries(got.moved).map(([k, v]) => `${k} is now “${v}”`).join(", ")}).`);
  if (!got.ok) throw refuse(got.why || "Not saved.");
  if (!got.changed.length) return "It already says that. Nothing written.";
  return `${oneLine(hit[0].label || nameOfRow(hit[0]))}: changed. Projects Console shows it now; his Notion Shoots row follows within a minute or two.`;
}

// ── a Released project's release (2026-10-17, Projects Console's Released page) ──

const FEATURED_MOST = 6;
const DAY_OR_NONE = (d) => d === "" || (DAY.test(d) && realDay(d));

/** The stills there are to pick from, as the console's Released sheet reads them. */
async function stillsOf(env, found, view) {
  const { releasedStills } = await import("./step6shelf.js");
  try {
    const got = await releasedStills(env, found.id || view.page);
    return got && got.ok ? got : { ok: false, why: (got && got.why) || "The stills could not be read.", stills: [] };
  } catch (e) {
    return { ok: false, why: `The stills could not be read (${String((e && e.message) || e).slice(0, 120)}).`, stills: [] };
  }
}

function releaseOf(facts) {
  const list = (f) => (Array.isArray(factValue(facts, f)) ? factValue(facts, f).filter((x) => typeof x === "string") : []);
  const selects = list("selects");
  const key = String(factValue(facts, "key_still") || "");
  const starred = list("featured").filter((id) => selects.includes(id)).slice(0, FEATURED_MOST);
  const lead = key && selects.includes(key) ? key : selects[0] || "";
  const featured = starred.length ? starred : (lead ? [lead, ...selects.filter((i) => i !== lead)] : selects).slice(0, FEATURED_MOST);
  return { selects, key: lead, starred, featured };
}

async function releasedTool(env, found, view, name, args, refuse) {
  const facts = view.facts;
  const rel = releaseOf(facts);
  const needStills = name === "set_released" || args.stills === true || rel.selects.length > 0;
  const got = needStills ? await stillsOf(env, found, view) : { ok: true, stills: [] };
  const byId = new Map((got.stills || []).map((s) => [s.id, s]));
  const named = (id) => ({ id, name: (byId.get(id) || {}).name || "" });

  if (name === "released") {
    const links = (((facts.links || {}).value || {}).custom || []).filter((i) => i && i.url && i.slot === "watch");
    const folder = factValue(facts, "selects_folder");
    const out = {
      project: oneLine(factValue(facts, "title")) || view.record.name || found.title,
      status: String(factValue(facts, "status") || ""),
      released_date: String(factValue(facts, "released_date") || ""),
      my_credit: String(factValue(facts, "my_credit") || "").trim() || "Cinematographer",
      selects: rel.selects.map(named),
      key_still: rel.key ? named(rel.key) : null,
      featured: rel.featured.map(named),
      featured_starred: rel.starred.length > 0,
      selects_folder: folder && typeof folder === "object" ? { name: folder.name || "", path: folder.path || "" } : (got.showcase ? { name: got.showcase.name, path: got.showcase.path } : null),
      website: String(factValue(facts, "website") || ""),
      watch: links.map(({ id, url, title }) => ({ id, url, title })),
    };
    if (!got.ok) out.stills_unread = got.why;
    if (args.stills === true) out.available = (got.stills || []).map((s) => ({ id: s.id, name: s.name }));
    if (canonStage(out.status) !== "Released") out.note = "This project is not Complete yet (its status is " + (shownStage(out.status) || "unset") + ").";
    return JSON.stringify(out, null, 1);
  }

  // set_released
  if (found.role !== "editor") throw refuse("Only an editor may change a project's release.");
  const asked = ["released_date", "my_credit", "key_still", "featured", "selects"].filter((k) => args[k] !== undefined);
  if (!asked.length) throw refuse("Say what to change: released_date, my_credit, key_still, featured or selects.");
  const pick = (said, pool, what) => {
    const s = oneLine(said);
    if (pool.includes(s)) return s;
    const hit = pool.filter((id) => {
      const n = (byId.get(id) || {}).name || "";
      return n && (n.toLowerCase() === s.toLowerCase() || n.replace(/\.[a-z0-9]+$/i, "").toLowerCase() === s.toLowerCase());
    });
    if (hit.length === 1) return hit[0];
    throw refuse(hit.length > 1 ? `“${s}” names more than one still; use its id.` : `“${s}” is not ${what}. Nothing written.`);
  };
  const changes = {};
  const put = (field, value) => {
    const one = facts[field];
    const now = one && typeof one === "object" ? one.value : undefined;
    if (JSON.stringify(now === undefined ? null : now) !== JSON.stringify(value)) changes[field] = { value, base: (one && one.v) || 0 };
  };
  let selects = rel.selects;
  if (args.selects !== undefined) {
    if (!Array.isArray(args.selects)) throw refuse("`selects` is a list of stills, in order.");
    if (!got.ok) throw refuse(`${got.why} Nothing written.`);
    const pool = [...byId.keys()];
    selects = [];
    for (const one of args.selects) {
      const id = pick(one, pool, "one of the stills there are to pick from (`released` `stills: true`)");
      if (!selects.includes(id)) selects.push(id);
    }
    put("selects", selects);
  }
  if (args.released_date !== undefined) {
    const d = oneLine(args.released_date);
    if (!DAY_OR_NONE(d)) throw refuse(`“${d}” isn't a day (YYYY-MM-DD). Nothing written.`);
    put("released_date", d);
  }
  if (args.my_credit !== undefined) put("my_credit", oneLine(args.my_credit).slice(0, 80) || "Cinematographer");
  if (args.key_still !== undefined) {
    const k = oneLine(args.key_still);
    put("key_still", k ? pick(k, selects, "one of the selects") : "");
  } else if (args.selects !== undefined && rel.key && !selects.includes(rel.key)) {
    put("key_still", selects[0] || "");
  }
  if (args.featured !== undefined) {
    if (!Array.isArray(args.featured)) throw refuse("`featured` is a list of selects; [] unstars them all.");
    const list = [];
    for (const one of args.featured) {
      const id = pick(one, selects, "one of the selects");
      if (!list.includes(id)) list.push(id);
    }
    if (list.length > FEATURED_MOST) throw refuse(`At most ${FEATURED_MOST} featured stills. Nothing written.`);
    put("featured", list);
  } else if (args.selects !== undefined && rel.starred.some((id) => !selects.includes(id))) {
    put("featured", rel.starred.filter((id) => selects.includes(id)));
  }
  if (!Object.keys(changes).length) return "It already says that. Nothing written.";
  const wrote = await writeFacts(env, view.page, changes, BY);
  if (wrote.status === 409) throw refuse(`Nothing written. ${conflictSaid(wrote.conflicts) || wrote.problem}. Read it again.`);
  if (wrote.status !== 200) throw refuse(`The record would not take it: ${wrote.problem}`);
  const words = { released_date: "Release date", my_credit: "Credit", key_still: "Key still", featured: "Featured", selects: "Selects" };
  return `Written: ${Object.keys(changes).map((f) => words[f]).join(", ")}. Projects Console shows it now.`;
}

// ── Show on Portal (2026-10-17): the record's `portal_docs`, Projects Console's Documents tab ──

async function portalDocsTool(env, view, name, args, refuse) {
  const [{ portalDocsDoor }, { recordOf }] = await Promise.all([import("./portaldocs.js"), import("./cloud.js")]);
  const deps = { recordOf, writeFacts };
  const listed = await portalDocsDoor(env, view.page, "GET", null, deps);
  const said = await listed.json();
  if (!listed.ok) throw refuse(said.problem || `The Drive folder could not be read (${listed.status}).`);
  const files = Array.isArray(said.files) ? said.files : [];
  const brief = (f) => ({ id: f.id, name: f.name, type: f.type, modified: String(f.modified || "").slice(0, 10), group: f.group, path: f.path || "", ...(f.working ? { working: true } : {}) });
  if (name === "portal_documents") {
    const words = oneLine(args.search).toLowerCase().split(" ").filter(Boolean);
    const fits = (f) => words.every((w) => `${f.name} ${f.path || ""}`.toLowerCase().includes(w));
    const chosen = Array.isArray(said.chosen) ? said.chosen : [];
    const known = new Map(files.map((f) => [f.id, f]));
    const out = {
      folder: said.folder ? said.folder.url : "",
      on_portal: chosen.map((c) => brief(known.get(c.id) || { ...c, type: "", group: "" })).filter(fits),
      suggested: files.filter((f) => f.suggested && !f.on && !f.working).slice(0, 6).map(brief).filter(fits),
    };
    if (args.all === true || words.length) out.files = files.filter(fits).map((f) => ({ ...brief(f), on: Boolean(f.on) }));
    if (said.partial) out.partial = "The folder is big; not every file was read.";
    return JSON.stringify(out, null, 1);
  }
  if (typeof args.on !== "boolean") throw refuse("Say on: true to show it, false to take it off.");
  const s = oneLine(args.file);
  if (!s) throw refuse("Say which file: its id or name, as portal_documents lists it.");
  const chosen = Array.isArray(said.chosen) ? said.chosen : [];
  let hit = files.filter((f) => f.id === s);
  if (!hit.length) hit = [...files, ...chosen.filter((c) => !files.some((f) => f.id === c.id))].filter((f) => String(f.name || "").toLowerCase() === s.toLowerCase());
  if (!hit.length) throw refuse(`No file called “${s}” in the project's Drive folder. portal_documents with \`search\` finds one.`);
  if (hit.length > 1) throw refuse(`More than one file is called “${s}”: ${hit.map((f) => `${f.id} (${f.path || "top"})`).join(", ")}. Use its id.`);
  const file = hit[0];
  const put = await portalDocsDoor(env, view.page, "PUT", async () => ({ id: file.id, on: args.on, path: file.path, by: "AI connector" }), deps);
  const back = await put.json();
  if (!put.ok) throw refuse(back.problem || `Not saved (${put.status}).`);
  return args.on ? `${file.name} is on the portal's Documents page.` : `${file.name} is off the portal. It stays in Drive.`;
}

/**
 * **`update_film`'s names go to the record** when the film has one. The film
 * mirrors director, producer, client and agency from it (`--recordfacts`), so
 * a name typed into the film alone is refused by the engine or put back by
 * the mirror. Returns {rest, said} — the arguments still for the film, and
 * what was written — or throws a refusal; null when there is no record.
 */
export async function filmNamesToRecord(env, found, args, refuse) {
  const names = ["director", "producer", "client", "agency"].filter((k) => typeof args[k] === "string");
  if (!names.length) return null;
  const view = await recordOfOpen(env, found.project);
  if (!view) return null;
  if (found.role !== "editor") throw refuse("You may read this project, not change it.");
  const said = [];
  const credits = names.filter((k) => k === "director" || k === "producer");
  const plain = names.filter((k) => k === "client" || k === "agency");
  // Everything checked before anything is written.
  for (const role of credits.map((k) => (k === "director" ? "Director" : "Producer"))) {
    if (creditHidden(role, view.hidden)) throw refuse(`${role} is hidden on this project. Nothing written.`);
  }
  const { changes, refused } = await planFacts(env, view, Object.fromEntries(plain.map((k) => [k, args[k]])));
  if (Object.keys(refused).length) {
    throw refuse(`Nothing written. ${Object.entries(refused).map(([f, why]) => `${LABEL[f]}: ${why}.`).join(" ")}`);
  }
  if (Object.keys(changes).length) {
    const got = await writeFacts(env, view.page, changes, BY);
    if (got.status !== 200) throw refuse(got.conflicts ? `Nothing written. ${conflictSaid(got.conflicts)}.` : `The record would not take it: ${got.problem}`);
    said.push(...Object.keys(changes).map((f) => LABEL[f]));
  }
  for (const k of credits) {
    const role = k === "director" ? "Director" : "Producer";
    let facts = (await recordOfOpen(env, found.project) || view).facts;
    for (let attempt = 0; ; attempt++) {
      const plan = creditsPlan(facts, withPeople(creditsOf(facts), role, splitNames(args[k])));
      if (!Object.keys(plan).length) break;
      const got = await writeFacts(env, view.page, plan, BY);
      if (got.status === 200) { said.push(role); break; }
      if (got.status !== 409 || !got.conflicts) throw refuse(`The record would not take it: ${got.problem}`);
      if (attempt === 2) throw refuse("The credits kept changing. Try again.");
      facts = (await recordOfOpen(env, found.project) || view).facts;
    }
  }
  const rest = { ...args };
  for (const k of names) delete rest[k];
  return { rest, said, names };
}

/** The four names the record gives a film, for `summary` — the record wins,
 * as it does on the card and in the film once its mirror runs. */
export function namesFromRecord(view) {
  const credits = creditsOf(view.facts);
  const line = (role) => creditLine((credits.find((c) => c.role === role) || { people: [] }).people);
  const out = {};
  const held = (field) => typeof factValue(view.facts, field) === "string";
  const listed = Array.isArray(factValue(view.facts, "credits"));
  if (listed || held("director")) out.director = creditHidden("Director", view.hidden) ? "" : line("Director");
  if (listed || held("producer")) out.producer = creditHidden("Producer", view.hidden) ? "" : line("Producer");
  for (const k of ["client", "agency"]) {
    if (held(k)) out[k] = view.hidden.includes(k) ? "" : factValue(view.facts, k);
  }
  return out;
}

export { MIRRORS };
