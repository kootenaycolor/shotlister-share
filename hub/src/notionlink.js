/**
 * **The Notion link's deciding, ported from the console** (2026-10-11,
 * Projects Console without the Mac, stage 2).
 *
 * A rule-for-rule port of `projects-console/notionlink.py` (pure functions),
 * `storyblocks.py` (the page's Story section), and the parts of
 * `credits.py`, `recordlayout.py` and `shoots.py` the link calls. Nothing
 * here talks to Notion, the bucket or anything else: `notionsync.js` reads,
 * writes and remembers, and calls these to decide. Every function names the
 * Python one it mirrors. **Change a rule there and change it here in the
 * same breath** — the two are diffed line for line by a dry run against his
 * real Notion (see `hub/notionsync.mjs`).
 *
 * Python's string rules are kept where they could differ: whitespace is
 * Python's `str.isspace` set (not JavaScript's `\s`), `casefold` is folded
 * the way Python folds (`ß` → `ss`), sorting is by code point, and the
 * fingerprints are the same sha256 prefixes, so a fingerprint either side
 * wrote into the link's memory reads the same on the other.
 */

import { createHash } from "node:crypto";

// ── Python's string rules ────────────────────────────────────────────────────

/** `str.isspace()` — what Python's `split()` and `strip()` take as space. */
const WS = "\\t\\n\\x0b\\x0c\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const WS_RUN = new RegExp(`[${WS}]+`, "g");
const WS_EDGES = new RegExp(`^[${WS}]+|[${WS}]+$`, "g");

/** `s.split()` */
export const pySplit = (s) => String(s).split(WS_RUN).filter((x) => x !== "");
/** `s.strip()` */
export const pyStrip = (s) => String(s).replace(WS_EDGES, "");
/** `" ".join(s.split())` */
export const squash = (s) => pySplit(s).join(" ");
/** `s.casefold()` — upper then lower is Python's folding for every case that
 * can reach a name or a choice (ß → ss, ﬁ → fi). */
export const casefold = (s) => String(s).toUpperCase().toLowerCase();
/** `s.lower()` */
export const lower = (s) => String(s).toLowerCase();
/** Python's truthiness, for the values the link handles. */
export const truthy = (v) => {
  if (v === null || v === undefined || v === false || v === 0 || v === "") return false;
  if (Array.isArray(v)) return v.length > 0;
  if (typeof v === "object") return Object.keys(v).length > 0;
  return true;
};
/** `str(x or "")` */
const str = (v) => (truthy(v) ? String(v) : "");
/** `sorted()` of strings — by code point, as Python compares. */
export function cmp(a, b) {
  if (Array.isArray(a)) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) {
      const c = cmp(a[i], b[i]);
      if (c) return c;
    }
    return a.length - b.length;
  }
  if (typeof a === "number" && typeof b === "number") return a - b;
  const A = Array.from(String(a)), B = Array.from(String(b));
  for (let i = 0; i < Math.min(A.length, B.length); i++) {
    const x = A[i].codePointAt(0), y = B[i].codePointAt(0);
    if (x !== y) return x - y;
  }
  return A.length - B.length;
}
export const sorted = (xs, key = (x) => x) => [...xs].map((x, i) => [key(x), i, x])
  .sort((p, q) => cmp(p[0], q[0]) || p[1] - q[1]).map((t) => t[2]);
const sha16 = (text) => createHash("sha256").update(text, "utf8").digest("hex").slice(0, 16);

/** `json.dumps(v, sort_keys=True)` exactly (separators, ASCII escapes). */
export function pyDumps(v) {
  if (v === null || v === undefined) return "null";
  if (v === true) return "true";
  if (v === false) return "false";
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : String(v);
  if (typeof v === "string") {
    let out = "\"";
    for (const ch of v) {
      const c = ch.codePointAt(0);
      if (ch === "\"") out += "\\\"";
      else if (ch === "\\") out += "\\\\";
      else if (ch === "\n") out += "\\n";
      else if (ch === "\r") out += "\\r";
      else if (ch === "\t") out += "\\t";
      else if (ch === "\b") out += "\\b";
      else if (ch === "\f") out += "\\f";
      else if (c < 0x20 || c > 0x7e) {
        if (c > 0xffff) {
          const s = c - 0x10000;
          out += `\\u${(0xd800 + (s >> 10)).toString(16).padStart(4, "0")}\\u${(0xdc00 + (s & 0x3ff)).toString(16).padStart(4, "0")}`;
        } else out += `\\u${c.toString(16).padStart(4, "0")}`;
      } else out += ch;
    }
    return `${out}"`;
  }
  if (Array.isArray(v)) return `[${v.map(pyDumps).join(", ")}]`;
  return `{${sorted(Object.keys(v)).map((k) => `${pyDumps(k)}: ${pyDumps(v[k])}`).join(", ")}}`;
}

// ── the two API dialects (query_path, parent_for_new_row) ────────────────────

export const OLD_VERSION = "2022-06-28";
export const NEW_VERSION = "2025-09-03";
export const IDS = {
  projects: ["feedface-0000-4000-8000-00000000000a", "feedface-0000-4000-8000-000000000001"],
  crew: ["feedface-0000-4000-8000-000000000009", "feedface-0000-4000-8000-000000000004"],
  shoots: ["feedface-0000-4000-8000-000000000008", "feedface-0000-4000-8000-000000000002"],
};

/** query_path — the worker speaks only the new dialect. */
export function queryPath(name, version = NEW_VERSION) {
  const [database, source] = IDS[name];
  if (version === OLD_VERSION) return `databases/${database}/query`;
  if (version === NEW_VERSION) return `data_sources/${source}/query`;
  throw new Error(`unknown Notion-Version ${version}`);
}

// ── reading the words off a page ─────────────────────────────────────────────

export const PORTAL_HEADINGS = { logline: "logline", "director's note": "note", "visual language": "look" };
export const LINK_HEADINGS = { logline: "logline", synopsis: "synopsis",
  "director's note": "directors_note", "director’s note": "directors_note",
  "visual language": "visual_language" };
const SECTION_ENDS = ["divider", "column_list", "child_database"];

/** plain */
export function plain(rich) {
  return pyStrip((rich || []).map((bit) => (bit && bit.plain_text) || "").join(""));
}

/** is_placeholder */
export function isPlaceholder(words) {
  return /^\*?insert here\*?$/i.test(words) || /^add the director['’]s creative note here\b/i.test(words);
}

/** Section (NamedTuple) */
export class Section {
  constructor(found, headingId, paragraphs, blockIds) {
    this.found = found; this.heading_id = headingId; this.paragraphs = paragraphs; this.block_ids = blockIds;
  }
  get text() { return this.paragraphs.join("\n\n"); }
  get portal_text() { return pyStrip(this.paragraphs.join(" ")); }
  get value() { return this.found ? this.text : null; }
}

const headingKey = (block, kind) => pyStrip(lower(plain(((block[kind] || {}).rich_text))));

/** sections */
export function sections(blocks, headings = LINK_HEADINGS) {
  const out = {};
  for (const key of Object.values(headings)) out[key] = new Section(false, "", [], []);
  let under = null;
  for (const block of blocks || []) {
    const kind = block.type || "";
    if (kind.startsWith("heading_")) {
      const key = headings[headingKey(block, kind)];
      under = key && !out[key].found ? key : null;
      if (under) out[under] = new Section(true, block.id || "", [], []);
    } else if (kind === "paragraph" && under) {
      out[under].block_ids.push(block.id || "");
      const words = plain((block.paragraph || {}).rich_text);
      if (words && !isPlaceholder(words)) out[under].paragraphs.push(words);
    } else if (SECTION_ENDS.includes(kind)) {
      under = null;
    }
  }
  return out;
}

// ── the row's text boxes ─────────────────────────────────────────────────────

export const PROPERTIES = { logline: "Logline", synopsis: "Synopsis",
  directors_note: "Director's Note", visual_language: "Visual Language" };
const RICH_PIECE = 2000;

const propOf = (row, column) => (((row || {}).properties) || {})[column];

/** property_text */
export function propertyText(row, column) {
  const field = propOf(row, column);
  if (!field || field.type !== "rich_text") return null;
  return plain(field.rich_text);
}

/** notion_words */
export function notionWords(row, pageSections = null) {
  const out = {};
  for (const [field, column] of Object.entries(PROPERTIES)) {
    let words = propertyText(row, column);
    if (words === null) { out[field] = null; continue; }
    if (!words && pageSections && field in pageSections && pageSections[field].found) words = pageSections[field].text;
    out[field] = words;
  }
  return out;
}

/** rich_text_for — pieces by code point, as Python slices. */
export function richTextFor(words) {
  const text = Array.from(str(words));
  const out = [];
  for (let i = 0; i < text.length; i += RICH_PIECE) {
    out.push({ type: "text", text: { content: text.slice(i, i + RICH_PIECE).join("") } });
  }
  return out;
}

// ── comparing words ──────────────────────────────────────────────────────────

const PARA_SPLIT = new RegExp(`\\n[${WS}]*\\n`);

/** normalize */
export function normalize(text) {
  const t = str(text).normalize("NFC").replace(/\r\n/g, "\n");
  const paras = t.split(PARA_SPLIT).map(squash);
  return paras.filter((p) => p).join("\n\n");
}

/** fingerprint */
export const fingerprint = (text) => sha16(normalize(text));

// ── which rows changed ───────────────────────────────────────────────────────

/** _when — milliseconds since the epoch (Python keeps microseconds; nothing
 * the link compares is finer than a second). */
export function when(iso) {
  const s = String(iso).replace("Z", "+00:00");
  const m = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(.*)$/.exec(s);
  const t = m ? Date.parse(`${m[1]}${m[2] ? m[2].slice(0, 4).padEnd(4, "0") : ""}${m[3] || "Z"}`) : Date.parse(s);
  if (Number.isNaN(t)) throw new Error(`not a time: ${iso}`);
  return t;
}

/** minute_floor */
export function minuteFloor(iso) {
  const d = new Date(when(iso));
  d.setUTCSeconds(0, 0);
  return d.toISOString().replace(/\.\d{3}Z$/, ".000Z").replace(/:00\.000Z$/, ":00.000Z");
}

/** needs_look */
export function needsLook(pageEdited, lastRead) {
  if (!lastRead) return true;
  if (!pageEdited) return true;
  return when(pageEdited) >= when(minuteFloor(lastRead));
}

// ── the decision ─────────────────────────────────────────────────────────────

export const NO_OP = "no-op", TAKE_NOTION = "take-notion", PUSH_RECORD = "push-record", CONFLICT = "conflict";
export const REBASE = "rebase";
const D = (action, why) => ({ action, why });

/** decide */
export function decide(fact, notionValue, notionEdited = "", notionBy = "", botIds = [], key = null) {
  key = key || fingerprint;
  if (notionValue === null || notionValue === undefined) {
    return D(NO_OP, "Notion's copy could not be read (heading missing or page unread) — nothing decided from silence");
  }
  fact = fact || {};
  const recordValue = truthy(fact.value) ? fact.value : "";
  const nh = key(notionValue), rh = key(recordValue);
  const ours = Boolean(notionBy) && (botIds || []).includes(notionBy);
  const who = ours ? "the link's own integration" : (notionBy ? "someone in Notion" : "Notion");
  if (nh === rh) return D(NO_OP, "both say the same words");
  const base = fact.synced_base;
  if (!truthy(base)) {
    if (!normalize(recordValue)) return D(TAKE_NOTION, "first link: the record is empty, Notion has words");
    if (!normalize(notionValue)) return D(PUSH_RECORD, "first link: Notion is empty, the record has words");
    return D(CONFLICT, "first link: Notion and the record say different things — he decides");
  }
  const known = new Set([base.hash ?? null]);
  if (truthy(base.pushed)) known.add(base.pushed);
  const notionMoved = !known.has(nh);
  const recordMoved = int(fact.v) !== int(base.v);
  const by = truthy(fact.by) ? fact.by : "someone";
  if (notionMoved && !recordMoved) return D(TAKE_NOTION, `changed in Notion by ${who}; the record has not moved since the last sync`);
  if (recordMoved && !notionMoved) {
    if (truthy(base.pushed) && nh === base.pushed) return D(PUSH_RECORD, "Notion shows the link's own earlier write; the record has moved on since");
    return D(PUSH_RECORD, `changed in the record by ${by}; Notion has not moved since the last sync`);
  }
  if (!notionMoved && !recordMoved) return D(CONFLICT, "neither side moved since the last sync but they differ — bookkeeping is off, he decides");
  return D(CONFLICT, `changed in both places since the last sync (Notion by ${who}, the record by ${by})`);
}

/** int(x or 0) */
export function int(v) {
  if (!truthy(v)) return 0;
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

// ── crew as the record would cache it ────────────────────────────────────────

export const bare = (id) => str(id).replace(/-/g, "");

/** _related */
export function related(row, name) {
  return ((((row || {}).properties || {})[name] || {}).relation || []).map((r) => bare(r.id));
}

/** _names */
export function names(row, name) {
  const field = (((row || {}).properties) || {})[name] || {};
  const kind = field.type || "";
  if (kind === "multi_select") return (field.multi_select || []).map((o) => o.name || "");
  if (kind === "select") return field.select ? [field.select.name] : [];
  if (kind === "title") return [plain(field.title)];
  return [];
}
const firstName = (row) => { const n = names(row, "Name"); return n.length ? n[0] : ""; };

/** crew_snapshot */
export function crewSnapshot(projectId, crewRows, shootRows, here = null) {
  const project = bare(projectId);
  // `here` is the record's `crew_roles` ({Crew page id: [role]}): a role held on
  // THIS project only. It stands in for the Crew role (flagged `roles_here`)
  // and is never written to Notion.
  const heldHere = here && typeof here === "object" && !Array.isArray(here) ? here : {};
  const shoots = (shootRows || []).filter((s) => related(s, "Project").includes(project));
  const shootIds = new Set(shoots.map((s) => bare(s.id)));
  const listedOn = new Map();
  for (const s of shoots) {
    for (const person of related(s, "Crew")) {
      if (!listedOn.has(person)) listedOn.set(person, new Set());
      listedOn.get(person).add(bare(s.id));
    }
  }
  const out = [];
  for (const row of crewRows || []) {
    const pid = bare(row.id);
    const mine = new Set(related(row, "Shoots").filter((x) => shootIds.has(x)));
    for (const x of listedOn.get(pid) || []) mine.add(x);
    if (!related(row, "Projects").includes(project) && !mine.size) continue;
    const mineHere = [...new Set((Array.isArray(heldHere[pid]) ? heldHere[pid] : []).map((r) => str(r).trim()).filter(Boolean))];
    out.push({
      person: pid,
      name: (names(row, "Name").length ? names(row, "Name") : [""])[0],
      roles: mineHere.length ? mineHere : sorted(names(row, "Role")),
      shoots: mine.size ? sorted([...mine]) : sorted([...shootIds]),
      all_shoots: !mine.size,
      ...(mineHere.length ? { roles_here: true } : {}),
    });
  }
  return sorted(out, (p) => [lower(p.name), p.person]);
}

// ── every project fact, both ways ────────────────────────────────────────────

export const TEXT = "text", CHOICE = "choice", TITLE = "title", PEOPLE = "people";
export const URL = "url", DATES = "dates", ICON = "icon";

/** FACTS — field -> [kind, the Projects row's property], in Python's order. */
export const FACTS = {
  logline: [TEXT, "Logline"],
  synopsis: [TEXT, "Synopsis"],
  directors_note: [TEXT, "Director's Note"],
  visual_language: [TEXT, "Visual Language"],
  client: [TEXT, "Client"],
  agency: [TEXT, "Agency"],
  status: [CHOICE, "Status"],
  type: [CHOICE, "Type"],
  length: [CHOICE, "Length"],
  director: [PEOPLE, "Director"],
  writer: [PEOPLE, "Writer"],
  producer: [PEOPLE, "Producer"],
  executive_producer: [PEOPLE, "Executive Producer"],
  line_producer: [PEOPLE, "Line Producer"],
  co_producer: [PEOPLE, "Co-Producer"],
  creative_director: [PEOPLE, "Creative Director"],
  production_company: [PEOPLE, "Production Company"],
  title: [TITLE, "Project"],
  color: [CHOICE, "Color"],
  shoot_dates: [DATES, "Shoot Dates"],
  website: [URL, "Website"],
  drive_folder: [URL, "Drive Folder"],
  icon: [ICON, ""],
};
// Released is a plain pick; Closed is written by Close Project (closeproject.js)
// and follows to Notion like any record status (2026-10-15).
export const STATUS_THE_LINK_MAY_SET = ["Development", "Active", "Released", "Closed"];

/** split_people */
export function splitPeople(text) {
  return String(str(text)).split(/[&,]/).map(squash).filter((n) => n);
}

/** join_people — credits.line */
export const joinPeople = (list) => creditLine(list);

/** _people_key */
function peopleKey(text) {
  const set = new Set(splitPeople(text).map((n) => casefold(n.normalize("NFC"))));
  return sha16(sorted([...set]).join("\n"));
}

/** _choice_key */
const choiceKey = (text) => sha16(casefold(normalize(text)));

/** key_for */
export function keyFor(field) {
  const kind = (FACTS[field] || [TEXT, ""])[0];
  if (kind === CHOICE) return choiceKey;
  if (kind === PEOPLE) return peopleKey;
  if (kind === ICON) return iconKey;
  return fingerprint;
}

/** choice_text */
export function choiceText(row, column) {
  const field = propOf(row, column);
  if (!field || field.type !== "select") return null;
  return ((field.select || {}).name) || "";
}

/** title_text */
export function titleText(row, column = "Project") {
  const field = propOf(row, column);
  if (!field || field.type !== "title") return null;
  return plain(field.title);
}

/** url_text */
export function urlText(row, column) {
  const field = propOf(row, column);
  if (!field || field.type !== "url") return null;
  return pyStrip(field.url || "");
}

/** dates_text */
export function datesText(row, column) {
  const field = propOf(row, column);
  if (!field || field.type !== "date") return null;
  const w = field.date || {};
  const start = (w.start || "").slice(0, 10), end = (w.end || "").slice(0, 10);
  if (!start) return "";
  return end && end !== start ? `${start}/${end}` : start;
}

/** split_dates */
export function splitDates(value) {
  const s = pyStrip(str(value));
  const at = s.indexOf("/");
  const [start, end] = at < 0 ? [s, ""] : [s.slice(0, at), s.slice(at + 1)];
  return [pyStrip(start), pyStrip(end)];
}

/** notion_date */
export function notionDate(value) {
  const [start, end] = splitDates(value);
  if (!start) return { date: null };
  return { date: { start, ...(end && end !== start ? { end } : {}) } };
}

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const realDay = (d) => {
  const [y, m, dd] = d.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, dd));
  return y >= 1 && t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === dd;
};

/** dates_refusal */
export function datesRefusal(value) {
  const [start, end] = splitDates(value);
  if (!start && !end) return "";
  for (const d of [start, end]) if (d && !DAY.test(d)) return `“${d}” isn't a day (YYYY-MM-DD).`;
  if (end && !start) return "An end day needs a first day.";
  if (end && end < start) return "The last day is before the first.";
  for (const d of [start, end]) if (d && !realDay(d)) return `“${value}” isn't a real day.`;
  return "";
}

const WEB = /^https?:\/\/[^\s<>"']+$/i;

/** url_refusal */
export function urlRefusal(value) {
  const v = pyStrip(str(value));
  if (!v || WEB.test(v)) return "";
  return `“${Array.from(v).slice(0, 60).join("")}” isn't a web address (https://…).`;
}

/** icon_text */
export function iconText(row) {
  if (!row || typeof row !== "object" || Array.isArray(row) || !("icon" in row)) return null;
  const icon = row.icon || {};
  const kind = icon.type || "";
  if (!truthy(icon)) return "";
  if (kind === "icon") {
    const one = icon.icon || {};
    const name = one.name || "", color = (one.color || "gray").replace("_background", "");
    return name ? `https://www.notion.so/icons/${name}_${color}.svg` : "";
  }
  if (kind === "external") return pyStrip(((icon.external || {}).url) || "");
  if (kind === "emoji") return icon.emoji || "";
  return null;
}

export const ICON_COLORS = ["gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"];
const ICON_URL = /^https:\/\/www\.notion\.so\/icons\/([a-z0-9_-]+)_([a-z]+)\.svg$/i;

/** icon_parts */
export function iconParts(value) {
  const m = ICON_URL.exec(pyStrip(str(value)));
  return m ? [m[1].toLowerCase(), m[2].toLowerCase()] : null;
}

/** icon_key */
export function iconKey(value) {
  const parts = iconParts(value);
  if (parts) return `icon:${parts[0].replace(/_/g, "-")}:${parts[1].replace(/lightgray/g, "gray")}`;
  return fingerprint(value);
}

/** icon_refusal */
export function iconRefusal(value) {
  const parts = iconParts(value);
  if (!parts) return "Only Notion's own icons can be sent to Notion. Pick one from the list.";
  if (!ICON_COLORS.includes(parts[1])) return `“${parts[1]}” isn't one of the icon colours.`;
  return "";
}

/** icon_payload */
export function iconPayload(value) {
  const [name, color] = iconParts(value);
  return { type: "icon", icon: { name, color } };
}

/** people_names */
export function peopleNames(row, column, crewNames) {
  const field = propOf(row, column);
  if (!field || field.type !== "relation") return null;
  const out = [];
  for (const r of field.relation || []) {
    const name = crewNames[bare(r.id)];
    if (!name) return null;
    out.push(name);
  }
  return out;
}

/** notion_value */
export function notionValue(field, row, crewNames = null) {
  const [kind, column] = FACTS[field];
  if (kind === TEXT) return propertyText(row, column);
  if (kind === CHOICE) return choiceText(row, column);
  if (kind === TITLE) return titleText(row, column);
  if (kind === PEOPLE) {
    const list = crewNames === null ? null : peopleNames(row, column, crewNames);
    return list === null ? null : joinPeople(list);
  }
  if (kind === URL) return urlText(row, column);
  if (kind === DATES) return datesText(row, column);
  if (kind === ICON) return iconText(row);
  return null;
}

/** pick_choice */
export function pickChoice(options, value) {
  const want = casefold(normalize(value));
  if (!want) return "";
  const hit = (options || []).find((o) => casefold(normalize(o)) === want);
  return hit === undefined ? null : hit;
}

/** find_people */
export function findPeople(list, crewRows) {
  const by = new Map();
  for (const row of crewRows || []) {
    const name = firstName(row);
    if (name) {
      const k = casefold(name);
      if (!by.has(k)) by.set(k, []);
      by.get(k).push(bare(row.id));
    }
  }
  const ids = [], missing = [], twice = [];
  for (const n of list) {
    const hit = by.get(casefold(n)) || [];
    if (!hit.length) missing.push(n);
    else if (hit.length > 1) twice.push(n);
    else ids.push(hit[0]);
  }
  return [ids, missing, twice];
}

/** push_refusal */
export function pushRefusal(field, value, options = null) {
  const [kind, column] = FACTS[field];
  if (kind === ICON) return iconRefusal(value);
  if (kind === URL) return urlRefusal(value);
  if (kind === DATES) return datesRefusal(value);
  if (kind === TITLE) {
    return "The project's name in Notion is how the console, the Drive folders and Shotlister find it, "
      + "so the record's title is shown, not written back. To change the name everywhere, use Rename.";
  }
  if (field === "status" && !STATUS_THE_LINK_MAY_SET.includes(value)) {
    return `“${value || "nothing"}” isn't set from the record — Post and Archived come from the Wrap `
      + "and Archive rituals, which do the folders too.";
  }
  if (kind === CHOICE && options !== null && pickChoice(options, value) === null) {
    return `“${value}” isn't one of Notion's ${column} choices (${options.join(", ")}).`;
  }
  return "";
}

/** decide_title */
export function decideTitle(fact, notionName, base) {
  if (notionName === null || notionName === undefined) return D(NO_OP, "Notion's name could not be read — nothing decided from silence");
  fact = fact || {};
  const rec = truthy(fact.value) ? fact.value : "";
  const nh = fingerprint(notionName);
  if (!truthy(base)) {
    if (!normalize(rec) && normalize(notionName)) return D(TAKE_NOTION, "first link: the record has no title, Notion's name fills it");
    if (nh === fingerprint(rec)) return D(REBASE, "first link: both say the same name — remembered, nothing written");
    return D(REBASE, "first link: the record's title is shown as it is; Notion's name stays the key");
  }
  if (nh !== (base.hash ?? null) && nh !== (base.pushed ?? null)) {
    if (nh === fingerprint(rec)) return D(REBASE, "renamed in Notion to the record's own title");
    return D(TAKE_NOTION, "renamed in Notion — the record's title follows");
  }
  if (int(fact.v) !== int(base.v)) return D(REBASE, "the record's title changed for show; Notion's name is left alone");
  return D(NO_OP, "Notion's name has not moved");
}

/** decide_icon */
export function decideIcon(fact, notionValue, notionEdited = "", notionBy = "", botIds = [], base = null) {
  if (notionValue === null || notionValue === undefined) return D(NO_OP, "Notion's icon could not be read — nothing decided from silence");
  fact = fact || {};
  const recv = truthy(fact.value) ? fact.value : "";
  if (!truthy(base) && iconKey(notionValue) !== iconKey(recv) && normalize(notionValue)) {
    return D(TAKE_NOTION, "first link: the icon in Notion — the record follows");
  }
  const got = decide(truthy(base) ? { ...fact, synced_base: base } : (truthy(fact) ? fact : null),
    notionValue, notionEdited, notionBy, botIds, iconKey);
  if (got.action === NO_OP && !truthy(base) && iconKey(notionValue) === iconKey(recv)) return D(REBASE, "both show the same icon");
  return got;
}

// ── the record's copy of the Shoots rows ─────────────────────────────────────

function datePair(row, column) {
  const w = (((row.properties || {})[column] || {}).date) || {};
  return [(w.start || "").slice(0, 10), (w.end || "").slice(0, 10)];
}

function shootLabel(title) {
  for (const dash of [" — ", " – ", " - "]) {
    if ((title || "").includes(dash)) return pyStrip(title.slice(title.indexOf(dash) + dash.length));
  }
  return title || "";
}

// shoots.py `name_of` and its helpers
const DEFAULT_WORDS = /^(?:principal|additional shoot(?:\s+\d+)?|shoot(?:\s+\d+)?)$/i;
const EDGES = " \t·:—–-|,";
const NUMBER = /\bShoot\s+(\d+)\b/i;
const stripChars = (s, chars) => {
  const set = new Set(Array.from(chars));
  const a = Array.from(s);
  let i = 0, j = a.length;
  while (i < j && set.has(a[i])) i++;
  while (j > i && set.has(a[j - 1])) j--;
  return a.slice(i, j).join("");
};
function rest(title) {
  for (const dash of [" — ", " – ", " - "]) {
    if ((title || "").includes(dash)) {
      const at = title.indexOf(dash);
      return [title.slice(0, at), dash, title.slice(at + dash.length)];
    }
  }
  return ["", "", title || ""];
}

/** shoots.name_of */
export function shootNameOf(title) {
  let [, dash, r] = rest(title);
  if (DEFAULT_WORDS.test(stripChars(pySplit(r).join(" "), EDGES))) return "";
  if (!dash && NUMBER.test(r)) { const m = NUMBER.exec(r); r = r.slice(m.index + m[0].length); }
  const m = /\(?\bShoot\s+\d+\b\)?/i.exec(r);
  if (m) r = `${r.slice(0, m.index)} ${r.slice(m.index + m[0].length)}`;
  const name = stripChars(pySplit(r).join(" "), EDGES);
  return !name || DEFAULT_WORDS.test(name) ? "" : name;
}

/** shoots_snapshot */
export function shootsSnapshot(projectId, shootRows) {
  const project = bare(projectId);
  const out = [];
  for (const s of shootRows || []) {
    if (!related(s, "Project").includes(project)) continue;
    const props = s.properties || {};
    const title = plain(((props.Shoot || {}).title) || []);
    const m = NUMBER.exec(title || "");
    const [start, end] = datePair(s, "Dates");
    const status = names(s, "Status");
    out.push({
      id: bare(s.id),
      title,
      label: shootLabel(title),
      name: shootNameOf(title),
      n: m ? parseInt(m[1], 10) : null,
      start,
      end: end && end !== start ? end : "",
      status: status.length ? status[0] : "",
      section: plain((props["Shot List Section"] || {}).rich_text),
      changes: plain((props["What Changes"] || {}).rich_text),
      spec: sorted(related(s, "Camera Spec Sheet")),
      docs: sorted(related(s, "Docs")),
    });
  }
  return sorted(out, (x) => [x.start || "9999", x.n || 0, x.id]);
}

/**
 * **A sync never takes a shoot off the record** (2026-10-19, Daybreak: shoots
 * there for a moment, then gone). `snap` is Notion's rows as just read; `have`
 * is the record's copy. Every shoot Notion lists is Notion's words; every shoot
 * the record has that Notion did not list stays, marked `missing_in_notion`, so
 * nothing he or the AI added is lost to an outage, a half-made row or a row
 * moved off the project. Answers [the copy to keep, the shoots newly kept].
 */
export function keepShoots(snap, have) {
  const seen = new Set((snap || []).map((x) => x.id));
  const kept = [];
  const fresh = [];
  for (const x of Array.isArray(have) ? have : []) {
    if (!x || typeof x !== "object" || !x.id || seen.has(x.id)) continue;
    seen.add(x.id);
    if (!x.missing_in_notion) fresh.push(x);
    kept.push({ ...x, missing_in_notion: true });
  }
  if (!kept.length) return [snap || [], []];
  return [sorted([...(snap || []), ...kept], (x) => [x.start || "9999", x.n || 0, x.id]), fresh];
}

// ── credits.py, the parts the link calls ─────────────────────────────────────

export const ROLES = ["Director", "Writer", "Producer", "Executive Producer", "Line Producer",
  "Co-Producer", "Creative Director", "Production Company"];
export const MIRRORS = { Director: "director", Producer: "producer",
  "Executive Producer": "executive_producer", "Line Producer": "line_producer" };
export const LINES = { ...MIRRORS, Writer: "writer", "Co-Producer": "co_producer",
  "Creative Director": "creative_director", "Production Company": "production_company" };
export const ROLE_OF = Object.fromEntries(Object.entries(LINES).map(([role, field]) => [field, role]));
const MAX_ROLES = 16, MAX_PEOPLE = 24, MAX_NAME = 120;
const ROLE = /^[A-Za-z][A-Za-z /&'.-]{0,39}$/;

/** credits._clean */
export const cleanName = (name) => Array.from(squash(String(name ?? "").normalize("NFC"))).slice(0, MAX_NAME).join("");
const sameName = (a, b) => casefold(cleanName(a)) === casefold(cleanName(b));

/** credits.line */
export function creditLine(list) {
  const all = (list || []).map(cleanName).filter((n) => n);
  if (all.length < 3) return all.join(" & ");
  return `${all.slice(0, -1).join(", ")} & ${all[all.length - 1]}`;
}

/** credits.split */
export const creditSplit = (text) => String(str(text)).split(/[&,]/).map(cleanName).filter((n) => n);

const rank = (role) => (ROLES.includes(role) ? ROLES.indexOf(role) : ROLES.length);

/** credits.tidy */
export function creditTidy(value) {
  let out = [];
  if (!Array.isArray(value)) return out;
  for (const item of value) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const role = cleanName(item.role);
    if (!role || !ROLE.test(role)) continue;
    let people = [];
    for (const raw of item.people || []) {
      const n = cleanName(raw);
      if (n && !people.some((p) => sameName(n, p))) people.push(n);
    }
    people = people.slice(0, MAX_PEOPLE);
    const have = out.find((x) => casefold(x.role) === casefold(role));
    if (have) have.people.push(...people.filter((p) => !have.people.some((q) => sameName(p, q))));
    else if (people.length) out.push({ role, people });
  }
  out = out.filter((x) => x.people.length);
  out = out.map((x, i) => [x, i]).sort((a, b) => rank(a[0].role) - rank(b[0].role) || a[1] - b[1]).map((t) => t[0]);
  return out.slice(0, MAX_ROLES);
}

/** credits.people */
export function creditPeople(list, role) {
  const one = (list || []).find((x) => x.role === role);
  return one ? [...one.people] : [];
}

/** credits.with_people */
export function withPeople(list, role, names_) {
  const others = (list || []).filter((x) => x.role !== role).map((x) => ({ ...x }));
  return creditTidy([...others, { role, people: [...(names_ || [])] }]);
}

const factOf = (facts, field) => {
  const one = (facts || {})[field];
  return one && typeof one === "object" && !Array.isArray(one) ? one : {};
};

/** credits.of */
export function creditsOf(facts) {
  const c = factOf(facts, "credits");
  const stored = "value" in c ? creditTidy(c.value) : null;
  let out = [...(stored || [])];
  for (const [role, field] of Object.entries(LINES)) {
    const m = factOf(facts, field);
    if (typeof m.value !== "string") continue;
    const said = cleanName(m.value);
    if (stored === null) { out = withPeople(out, role, said ? [said] : []); continue; }
    const newer = truthy(m.at) && truthy(c.at) && cmp(m.at, c.at) > 0 && !truthy(c.waiting);
    if (newer && !sameName(creditLine(creditPeople(out, role)), said)) out = withPeople(out, role, said ? [said] : []);
  }
  return out;
}

const vOf = (one) => int(one.v);

/** Python `==` for JSON-shaped values: key order does not matter. */
export function pyEqual(a, b) {
  if (a === b) return true;
  if (a === null || b === null || a === undefined || b === undefined) return (a ?? null) === (b ?? null);
  if (typeof a !== typeof b) return false;
  if (Array.isArray(a)) return Array.isArray(b) && a.length === b.length && a.every((x, i) => pyEqual(x, b[i]));
  if (typeof a === "object") {
    if (Array.isArray(b)) return false;
    const ka = Object.keys(a), kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => k in b && pyEqual(a[k], b[k]));
  }
  return false;
}

/** credits.plan — {field: [value, base]} */
export function creditsPlan(facts, next) {
  const want = creditTidy(next);
  const c = factOf(facts, "credits");
  const changes = {};
  if (!pyEqual(c.value ?? null, want)) changes.credits = [want, vOf(c)];
  for (const [role, field] of Object.entries(LINES)) {
    const line = creditLine(creditPeople(want, role));
    const m = factOf(facts, field);
    const have = typeof m.value === "string" ? m.value : null;
    if (have === null && !line) continue;
    if ((have || "") !== line) changes[field] = [line, vOf(m)];
  }
  return changes;
}

/** credits.migrate — [changes, notes] */
export function creditsMigrate(facts, crewNames) {
  if ("value" in factOf(facts, "credits")) return [{}, []];
  const known = new Set((crewNames || []).filter((n) => cleanName(n)).map((n) => casefold(cleanName(n))));
  let next = [];
  const notes = [];
  for (const [role, field] of Object.entries(MIRRORS)) {
    const m = factOf(facts, field);
    const said = typeof m.value === "string" ? cleanName(m.value) : "";
    if (!said) continue;
    const list = creditSplit(said);
    if (list.length > 1 && list.every((n) => known.has(casefold(n)))) {
      next = withPeople(next, role, list);
      notes.push(`${role}: ${list.length} people (${creditLine(list)})`);
    } else {
      next = withPeople(next, role, [said]);
      if (list.length > 1) {
        const missing = list.filter((n) => !known.has(casefold(n)));
        notes.push(`${role}: kept as one — “${said}” (${missing.join(", ")} not in Crew)`);
      }
    }
  }
  if (!next.length) return [{}, []];
  return [creditsPlan(facts, next), notes];
}

// ── recordlayout.py: what a project shows ────────────────────────────────────

const LAYOUT_FIELDS = ["logline", "synopsis", "directors_note", "visual_language", "length",
  "client", "agency", "shoot_dates", "website"];
const STORY = ["logline", "synopsis", "directors_note", "visual_language"];
const TYPES = ["Narrative", "Commercial", "Music Video", "Personal"];
const DEFAULTS = {
  Narrative: { fields: ["logline", "synopsis", "directors_note", "visual_language", "length", "shoot_dates", "website"],
    credits: ["Director", "Writer", "Producer", "Executive Producer", "Line Producer"] },
  Commercial: { fields: ["length", "client", "agency", "shoot_dates", "website"],
    credits: ["Director", "Producer", "Executive Producer", "Line Producer"] },
  Personal: { fields: ["logline", "synopsis", "directors_note", "visual_language", "length", "shoot_dates", "website"],
    credits: ["Director", "Producer"] },
};
const FALLBACK = { fields: [...LAYOUT_FIELDS], credits: ["Director", "Producer"] };
const MUSIC_VIDEO = "Music Video";

/** recordlayout._type_key */
function typeKey(ptype) {
  const t = squash(String(ptype ?? ""));
  for (const known of [...Object.keys(DEFAULTS), MUSIC_VIDEO]) if (casefold(known) === casefold(t)) return known;
  return t;
}

/** recordlayout._tidy_template */
function tidyTemplate(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const fields = (raw.fields || []).filter((f) => LAYOUT_FIELDS.includes(f));
  const roles = (raw.credits || []).filter((r) => typeof r === "string" && ROLES.includes(r));
  return { fields: LAYOUT_FIELDS.filter((f) => fields.includes(f)), credits: ROLES.filter((r) => roles.includes(r)) };
}

/** recordlayout.template_for */
function templateFor(ptype, saved) {
  const t = typeKey(ptype);
  const mine = tidyTemplate((saved || {})[t]);
  if (mine !== null) return mine;
  // SERVER: a Music Video with no standard of its own shows what a Commercial
  // shows, his saved Commercial standard included (stage 5 step 5).
  if (t === MUSIC_VIDEO) return templateFor("Commercial", saved);
  const base = DEFAULTS[t] || FALLBACK;
  return { fields: [...base.fields], credits: [...base.credits] };
}

const factValue = (facts, field) => {
  const one = (facts || {})[field];
  return one && typeof one === "object" && !Array.isArray(one) ? one.value : null;
};

/** recordlayout.type_of */
function typeOf(facts, ptype = "") {
  const typed = factValue(facts, "type");
  return typeKey(typeof typed === "string" && pyStrip(typed) ? typed : ptype);
}

/** recordlayout.explicit_of */
function explicitOf(facts) {
  const out = { fields: {}, credits: {} };
  const raw = factValue(facts, "layout");
  const story = factValue(facts, "story");
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    for (const [k, v] of Object.entries(raw.fields || {})) if (LAYOUT_FIELDS.includes(k) && typeof v === "boolean") out.fields[k] = v;
    for (const [k, v] of Object.entries(raw.credits || {})) if (ROLES.includes(k) && typeof v === "boolean") out.credits[k] = v;
    const layAt = ((facts || {}).layout || {}).at || "";
    const st = (facts || {}).story;
    const storyAt = st && typeof st === "object" && !Array.isArray(st) ? st.at : "";
    if ((story === "on" || story === "off") && layAt && storyAt && cmp(storyAt, layAt) > 0) {
      for (const k of STORY) out.fields[k] = story === "on";
    }
    return out;
  }
  if (story === "on" || story === "off") for (const k of STORY) out.fields[k] = story === "on";
  return out;
}

/** recordlayout.resolve */
export function resolveLayout(facts, ptype = "", saved = null) {
  const t = typeOf(facts, ptype);
  const tpl = templateFor(t, saved);
  const ex = explicitOf(facts);
  const fields = {};
  for (const k of LAYOUT_FIELDS) fields[k] = k in ex.fields ? ex.fields[k] : tpl.fields.includes(k);
  const roles = {};
  for (const r of ROLES) roles[r] = r in ex.credits ? ex.credits[r] : tpl.credits.includes(r);
  return { type: t, fields, credits: roles, explicit: ex, template: tpl };
}

/** recordlayout.shows */
export function shows(resolved, key) {
  if (key in resolved.fields) return resolved.fields[key];
  const role = ROLE_OF[key] || (key.startsWith("credit:") ? key.slice(7) : null);
  if (role !== null && role in resolved.credits) return resolved.credits[role];
  return true;
}

/** recordlayout.explicit_after */
function explicitAfter(ptype, saved, want, facts = null) {
  const now = resolveLayout(facts || {}, ptype, saved);
  const tpl = now.template;
  const fields = { ...now.fields };
  for (const [k, v] of Object.entries(want.fields || {})) if (LAYOUT_FIELDS.includes(k)) fields[k] = Boolean(v);
  const roles = { ...now.credits };
  for (const [k, v] of Object.entries(want.credits || {})) if (ROLES.includes(k)) roles[k] = Boolean(v);
  return {
    fields: Object.fromEntries(Object.entries(fields).filter(([k, v]) => v !== tpl.fields.includes(k))),
    credits: Object.fromEntries(Object.entries(roles).filter(([r, v]) => v !== tpl.credits.includes(r))),
  };
}

/** recordlayout.fold_story */
export function foldStory(facts, ptype = "", saved = null) {
  const lay = factValue(facts, "layout");
  if (lay && typeof lay === "object" && !Array.isArray(lay)) return null;
  const story = factValue(facts, "story");
  if (story !== "on" && story !== "off") return null;
  const ex = explicitOf(facts);
  const rest_ = Object.fromEntries(Object.entries(facts || {}).filter(([k]) => k !== "story"));
  return explicitAfter(ptype, saved, { fields: ex.fields }, rest_);
}

export { TYPES as LAYOUT_TYPES };

// ── storyblocks.py: the Story section in the page body ───────────────────────

export const STORY_TITLE = "Story";
export const LABELS = { logline: "Logline", synopsis: "Synopsis",
  directors_note: "Director's Note", visual_language: "Visual Language" };
export const STORY_FIELDS = Object.keys(LABELS);
const TITLE_LEVEL = 2, PART_LEVEL = 3;

/** storyblocks._key */
const storyKey = (w) => casefold(squash(String(w ?? "").normalize("NFC").replace(/’/g, "'").replace(/‘/g, "'")));
const BY_LABEL = Object.fromEntries(Object.entries(LABELS).map(([k, v]) => [storyKey(v), k]));

/** storyblocks._text */
const blockText = (block) => plain(((block[block.type || ""]) || {}).rich_text);
/** storyblocks.is_heading */
const isHeading = (block) => String(block.type || "").startsWith("heading_");
/** storyblocks.field_of */
const fieldOf = (block) => (isHeading(block) ? (BY_LABEL[storyKey(blockText(block))] ?? null) : null);
/** storyblocks.is_title */
const isTitle = (block) => isHeading(block) && storyKey(blockText(block)) === storyKey(STORY_TITLE);

/** storyblocks.is_container */
export function isContainer(block, children) {
  if ((block || {}).type !== "synced_block") return false;
  if (((block.synced_block || {}).synced_from ?? null) !== null) return false;
  return truthy(children) && isTitle(children[0]);
}

/** storyblocks.Part */
export class Part {
  constructor(headingId, paraIds, texts, edited) {
    this.heading_id = headingId; this.para_ids = paraIds; this.texts = texts; this.edited = edited;
  }
  get paragraphs() { return this.texts.filter((t) => t); }
  get words() { return this.paragraphs.join("\n\n"); }
}

/** storyblocks.parse — {title_id, parts, order, foreign} */
export function parseStory(children) {
  let titleId = "";
  const parts = {}, order = [], foreign = [];
  let under = null;
  for (const b of children || []) {
    const bid = b.id || "";
    order.push(bid);
    const kind = b.type || "";
    const at = b.last_edited_time || "";
    if (isHeading(b)) {
      const f = fieldOf(b);
      if (f && !(f in parts)) { parts[f] = new Part(bid, [], [], at); under = f; continue; }
      if (!titleId && isTitle(b)) { titleId = bid; under = null; continue; }
      under = null;
      foreign.push(bid);
    } else if (kind === "paragraph" && under) {
      const p = parts[under];
      parts[under] = new Part(p.heading_id, [...p.para_ids, bid], [...p.texts, blockText(b)], cmp(p.edited, at) >= 0 ? p.edited : at);
    } else if (kind === "paragraph" && !blockText(b)) {
      continue;
    } else {
      foreign.push(bid);
    }
  }
  return { title_id: titleId, parts, order, foreign };
}

const STORY_PARA = new RegExp(`\\n[ \\t]*\\n`);

/** storyblocks.paragraphs_of */
export function paragraphsOf(words) {
  const t = String(words ?? "").normalize("NFC").replace(/\r\n/g, "\n");
  return t.split(STORY_PARA).map(pyStrip).filter((p) => p);
}

/** storyblocks.wanted — [[field, words]] */
export function wanted(words, showsFn) {
  const out = [];
  for (const f of STORY_FIELDS) {
    const w = words[f];
    if (typeof w === "string" && paragraphsOf(w).length && showsFn(f)) out.push([f, w]);
  }
  return out;
}

/** storyblocks.same */
export const sameWords = (a, b) => fingerprint(a) === fingerprint(b);

/** storyblocks.heading */
export function heading(text, level) {
  const kind = `heading_${level}`;
  return { type: kind, [kind]: { rich_text: richTextFor(text) } };
}
/** storyblocks.paragraph */
export const paragraph = (text) => ({ type: "paragraph", paragraph: { rich_text: richTextFor(text) } });
/** storyblocks.part_blocks */
export const partBlocks = (field, words) => [heading(LABELS[field], PART_LEVEL), ...paragraphsOf(words).map(paragraph)];

/** storyblocks.container */
export function container(want) {
  let kids = [heading(STORY_TITLE, TITLE_LEVEL)];
  for (const [f, w] of want) kids = kids.concat(partBlocks(f, w));
  return { type: "synced_block", synced_block: { synced_from: null, children: kids } };
}

/** storyblocks.anchor — ["after", id] or ["start", null] */
export function anchor(top) {
  const list = top || [];
  for (let i = 0; i < list.length; i++) {
    const b = list[i];
    if (isHeading(b) && storyKey(blockText(b)) === "notes") return i ? ["after", list[i - 1].id] : ["start", null];
  }
  return ["start", null];
}

/** storyblocks.plan — ops: ["patch", id, text] · ["insert", afterId|null, blocks] · ["delete", id] */
export function storyPlan(parsed, want, managed, showsFn) {
  const ops = [];
  const wantD = Object.fromEntries(want);
  let anchorId = parsed.title_id || null;
  const pending = parsed.title_id || !want.length ? [] : [heading(STORY_TITLE, TITLE_LEVEL)];
  const flush = () => {
    if (pending.length) { ops.push(["insert", anchorId, [...pending]]); pending.length = 0; }
  };
  for (const f of STORY_FIELDS) {
    const have = parsed.parts[f];
    const w = f in wantD ? wantD[f] : null;
    if (have === undefined) {
      if (w !== null) pending.push(...partBlocks(f, w));
      continue;
    }
    if (w === null && (f in managed || showsFn(f))) {
      for (const i of [have.heading_id, ...have.para_ids]) ops.push(["delete", i]);
      continue;
    }
    flush();
    if (w === null) {
      anchorId = (have.para_ids.length ? have.para_ids : [have.heading_id]).slice(-1)[0];
      continue;
    }
    const paras = paragraphsOf(w), ids = [...have.para_ids];
    paras.slice(0, ids.length).forEach((p, i) => { if (have.texts[i] !== p) ops.push(["patch", ids[i], p]); });
    for (const i of ids.slice(paras.length)) ops.push(["delete", i]);
    const kept = ids.slice(0, paras.length);
    anchorId = (kept.length ? kept : [have.heading_id]).slice(-1)[0];
    pending.push(...paras.slice(ids.length).map(paragraph));
  }
  flush();
  return ops;
}

/** storyblocks.settled */
export function settled(edited, now) {
  if (!edited) return true;
  const floor = when(minuteFloor(now));
  return when(edited) < floor - 60_000;
}
