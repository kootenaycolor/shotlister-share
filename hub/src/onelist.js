/**
 * **The one list** (2026-10-14, stage 5 step 3 — "the router and the one
 * list"). The project list, each project's card and the films shelf, answered
 * by the server as one list, Projects and Jobs apart. Projects Console on the
 * Mac asks for it first (its router, `hubbackend.py`) and lays on top only
 * what a Mac alone can see: the drive lights, the media drives, Notion's icon
 * pictures it keeps on disk.
 *
 * **Ported rule for rule** from the Mac's `engine.fetch_projects` (the
 * Projects rows, their Director names, their shoots' lines) and
 * `record.overlay_rows` (the record's facts laid over each row: what he typed
 * in the console wins over Notion). Change a rule there and change it here in
 * the same breath; `hub/onelist.mjs` checks the port case by case and
 * `projects-console/bothways.py` compares the two on every real project.
 *
 * **Where it differs, on purpose** (each marked `SERVER:`):
 * - each row says its record's key as `id` (the project's one ID, step 2);
 * - the icon picture itself (`icon_svg`) is the Mac's to lay on, from the
 *   copies it keeps; the row says which one as `icon_key`;
 * - `media_drives`, `lights` and `sub` are the Mac's (drives, its disk);
 * - the overlay reads the server's record, where the Mac reads its kept copy
 *   of the same record (they differ only while an edit waits on the Mac).
 *
 * The films shelf (`films_shelf`) reads the records alone, as the Mac's reads
 * only what it kept: nothing is asked of the portal.
 */

import { bareId, plainTitle, words } from "./cloud.js";
import { readout } from "./projectpage.js";
import { creditsOf } from "./credits.js";
import { resolveLayout } from "./notionlink.js";
import { hiddenOf, savedTemplates } from "./cloudlayout.js";
import { resolveModes, loadStandards } from "./studiomodes.js";

/** notionlink.IDS — the data sources read. */
export const SOURCES = {
  projects: "feedface-0000-4000-8000-000000000001",
  crew: "feedface-0000-4000-8000-000000000004",
  shoots: "feedface-0000-4000-8000-000000000002",
};

// ── engine.py: a page's words ────────────────────────────────────────────────

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const selectOf = (props, name) => ((((props || {})[name] || {}).select) || {}).name || "";
const urlOf = (props, name) => (((props || {})[name] || {}).url) || "";
const textOf = (props, name) => words(((props || {})[name] || {}).rich_text);
function dateStart(props, name) {
  const d = ((props || {})[name] || {}).date;
  return d ? (d.start || "") : "";
}
function dateEnd(props, name) {
  const d = ((props || {})[name] || {}).date;
  return (d && d.end) || "";
}

// ── engine.type_icon / notion_project_icon ───────────────────────────────────

export const TYPE_ICON = {
  narrative: ["clapper", "#1e45d6"],
  commercial: ["flame", "#b07a2b"],
  // SERVER: stage 5 step 5 — Music Video (keyed by its first word, as
  // type_icon reads it): a commercial's colour, the record glyph.
  music: ["disc", "#b07a2b"],
  personal: ["star", "#8a63d2"],
  docuseries: ["camera", "#2e7d55"],
  short: ["clip", "#6a4bb0"],
};

export const NOTION_COLOR_HEX = {
  default: "#787774", gray: "#9b9a97", brown: "#64473a",
  orange: "#d9730d", yellow: "#dfab01", green: "#0f7b6c",
  blue: "#0b6e99", purple: "#6940a5", pink: "#ad1a72", red: "#e03e3e",
};

export const NOTION_ICON_MAP = {
  fire: "flame",
  sun: "sun", sunny: "sun",
  headphones: "mic", microphone: "mic", audio: "mic",
  movie: "clapper", clapperboard: "clapper", film: "clapper",
  camera: "camera",
  video: "video", play: "video",
  star: "star",
  box: "box", package: "box", archive: "box",
  disc: "disc", record: "disc",
  scissors: "clip", clip: "clip", clipboard: "clip",
};

/** engine.type_icon: Python's `split()[0]` on the lower-cased Type. */
export function typeIcon(ptype, status = "") {
  const key = ptype ? (String(ptype).trim().toLowerCase().split(/\s+/)[0] || "") : "";
  if (key in TYPE_ICON) return TYPE_ICON[key];
  if (String(status || "").toLowerCase() === "archived") return ["box", "#1b1b1a"];
  return ["clapper", "#1e45d6"];
}

/** engine._notion_icon_name_color: [name, colour name], each null when missing. */
export function iconNameColor(page) {
  const props = (page && page.properties) || {};
  const icon = (page && page.icon) || {};
  const sel = (props.Color || {}).select;
  let color = null;
  if (sel && sel.color) color = sel.color;
  else if (icon.type === "icon") color = String((icon.icon || {}).color || "").replace("_background", "") || null;
  const name = icon.type === "icon" ? ((icon.icon || {}).name || null) : null;
  return [name, color];
}

/** engine.notion_project_icon: [glyph, colour] — never throws. */
export function projectIcon(page, ptype, status) {
  try {
    const [name, colorName] = iconNameColor(page);
    const color = colorName ? NOTION_COLOR_HEX[colorName] : null;
    const glyph = name ? NOTION_ICON_MAP[name] : null;
    const [dg, dc] = typeIcon(ptype, status);
    return [glyph || dg, color || dc];
  } catch {
    return typeIcon(ptype, status);
  }
}

// ── shoots.py: a Shoots row as the list reads it (no token: no paging) ───────

const NUMBER = /\bShoot\s+(\d+)\b/i;
const DEFAULT_WORDS = /^(?:principal|additional shoot(?:\s+\d+)?|shoot(?:\s+\d+)?)$/i;
const EDGES = " \t·:—–-|,";
const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
function strip(s, chars) {
  let a = 0, b = s.length;
  while (a < b && chars.includes(s[a])) a += 1;
  while (b > a && chars.includes(s[b - 1])) b -= 1;
  return s.slice(a, b);
}
function restOf(title) {
  for (const dash of [" — ", " – ", " - "]) {
    const at = (title || "").indexOf(dash);
    if (at >= 0) return [title.slice(0, at), dash, title.slice(at + dash.length)];
  }
  return ["", "", title || ""];
}
function shootLabel(title) {
  for (const dash of [" — ", " – ", " - "]) {
    const at = (title || "").indexOf(dash);
    if (at >= 0) return title.slice(at + dash.length).trim();
  }
  return title || "";
}
function nameOf(title) {
  const [, dash, r] = restOf(title);
  let rest = r;
  if (DEFAULT_WORDS.test(strip(squash(rest), EDGES))) return "";
  if (!dash) {
    const m = NUMBER.exec(rest);
    if (m) rest = rest.slice(m.index + m[0].length);
  }
  const m = /\(?\bShoot\s+\d+\b\)?/i.exec(rest);
  if (m) rest = `${rest.slice(0, m.index)} ${rest.slice(m.index + m[0].length)}`;
  const name = strip(squash(rest), EDGES);
  return !name || DEFAULT_WORDS.test(name) ? "" : name;
}

/** shoots.shoot_of(page) — as the list reads it: relations from the page. */
export function shootRow(page) {
  const props = page.properties || {};
  const title = plainTitle(props);
  const when = (props.Dates || {}).date || {};
  const m = NUMBER.exec(title || "");
  const rel = (name) => ((props[name] || {}).relation || []).map((r) => r.id);
  return {
    id: page.id, title, label: shootLabel(title), name: nameOf(title), n: m ? Number(m[1]) : null,
    start: String(when.start || "").slice(0, 10), end: String(when.end || "").slice(0, 10),
    status: selectOf(props, "Status"), crew: rel("Crew"), spec: rel("Camera Spec Sheet"),
    projects: rel("Project"), section: textOf(props, "Shot List Section"),
    changes: textOf(props, "What Changes"), url: page.url || "",
  };
}

/** shoots.shoots_by_project — every Shoots row by its project's bare page. */
export function shootsByProject(pages) {
  const out = {};
  for (const page of pages || []) {
    const s = shootRow(page);
    for (const pid of s.projects) (out[bareId(pid)] = out[bareId(pid)] || []).push(s);
  }
  return out;
}

/**
 * **The record's shoots in the list** (2026-10-19, Daybreak). Each project's
 * record keeps a copy of its shoots; any the Shoots rows just read did not
 * list (Notion down, or a row not there) are laid in, so a shoot never drops
 * off a card because one read failed. `copy` is the record's `shoots` value.
 */
export function withRecordCopy(mine, copy, page) {
  const seen = new Set((mine || []).map((s) => bareId(s.id)));
  const extra = [];
  for (const x of Array.isArray(copy) ? copy : []) {
    if (!isObject(x) || !x.id || seen.has(bareId(x.id))) continue;
    seen.add(bareId(x.id));
    const title = x.title || "";
    extra.push({
      id: bareId(x.id), title, label: x.label || shootLabel(title), name: x.name || "", n: x.n ?? null,
      start: String(x.start || "").slice(0, 10), end: String(x.end || "").slice(0, 10),
      status: x.status || "", crew: [], spec: Array.isArray(x.spec) ? x.spec : [],
      projects: [page], section: x.section || "", changes: x.changes || "",
      url: `https://www.notion.so/${bareId(x.id)}`, from_record: true,
    });
  }
  return extra.length ? [...(mine || []), ...extra] : (mine || []);
}

const isCommercial = (t) => ["commercial", "music video"].includes(String(t || "").trim().toLowerCase().replace(/\s+/g, " "));
function displayLabel(index, total, commercial, n = null) {
  const num = n || index + 1;
  if (commercial) return total === 1 ? "Shoot" : `Shoot ${num}`;
  if (index === 0) return "Principal";
  return total === 2 ? "Additional Shoot" : `Additional Shoot ${num}`;
}

/** shoots.restyle — the readout again after the record's facts were laid on. */
export function restyle(rows, project, now) {
  if (!rows || !rows.length || rows.every((r) => r.from_project)) return readout([], project, now);
  const commercial = isCommercial(project.type);
  return rows.map((r, i) => {
    const kind = displayLabel(i, rows.length, commercial, r.n);
    return { ...r, kind, label: r.name || kind };
  });
}

// ── record.overlay_rows ──────────────────────────────────────────────────────

export const ROW_FIELDS = { director: "director", status: "status", type: "type", length: "length",
  logline: "logline", producer: "producer" };
const WEB = /^https?:\/\/[^\s<>"']+$/i;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

function keptStr(kept, field) {
  const one = kept[field];
  return isObject(one) && typeof one.value === "string" ? one.value : null;
}

/** notionlink.split_dates */
export function splitDates(value) {
  const s = String(value == null ? "" : value).trim();
  const at = s.indexOf("/");
  return at < 0 ? [s, ""] : [s.slice(0, at).trim(), s.slice(at + 1).trim()];
}

function realDay(d) {
  const t = Date.parse(`${d}T00:00:00Z`);
  return !Number.isNaN(t) && new Date(t).toISOString().slice(0, 10) === d;
}

/** notionlink.dates_refusal — "" when fine. */
export function datesRefusal(value) {
  const [start, end] = splitDates(value);
  if (!start && !end) return "";
  for (const d of [start, end]) if (d && !DAY.test(d)) return `“${d}” isn't a day (YYYY-MM-DD).`;
  if (end && !start) return "An end day needs a first day.";
  if (end && end < start) return "The last day is before the first.";
  for (const d of [start, end]) if (d && !realDay(d)) return `“${value}” isn't a real day.`;
  return "";
}

/** notionlink.url_refusal — "" when fine. */
export function urlRefusal(value) {
  const v = String(value == null ? "" : value).trim();
  return !v || WEB.test(v) ? "" : "bad";
}

/** record.overlay_rows for one row: `kept` is the record's facts. */
/** What a Released project's card shows, from the record's facts, or null. */
export function releasedOf(kept) {
  if (!isObject(kept)) return null;
  const val = (k) => (isObject(kept[k]) ? kept[k].value : undefined);
  const date = typeof val("released_date") === "string" ? val("released_date") : "";
  const credit = typeof val("my_credit") === "string" ? val("my_credit") : "";
  const key = typeof val("key_still") === "string" ? val("key_still") : "";
  const selects = Array.isArray(val("selects")) ? val("selects").filter((x) => typeof x === "string") : [];
  if (!date && !credit && !key && !selects.length) return null;
  return { date, credit, key_still: key || selects[0] || "", selects: selects.length };
}

export function overlayRow(row, kept, saved, now) {
  if (!isObject(kept)) return row;
  for (const [field, key] of Object.entries(ROW_FIELDS)) {
    const v = keptStr(kept, field);
    if (v !== null) row[key] = v;
  }
  const color = keptStr(kept, "color");
  if (color !== null && (!color || color in NOTION_COLOR_HEX)) row.color = color;
  for (const [field, key] of [["website", "website_url"], ["drive_folder", "drive_url"]]) {
    const v = keptStr(kept, field);
    if (v !== null && !urlRefusal(v)) row[key] = v;
  }
  const dates = keptStr(kept, "shoot_dates");
  if (dates !== null && !datesRefusal(dates)) [row.dates, row.dates_end] = splitDates(dates);
  const story = keptStr(kept, "story");
  if (story === "on" || story === "off") row.story = story;
  const shootName = keptStr(kept, "shoot_name");
  if (shootName !== null) row.shoot_name = shootName;
  row.credits = creditsOf(kept);
  // SERVER: Released (2026-10-15) — the card's still, year and his credit.
  const shelf = releasedOf(kept);
  if (shelf) row.released = shelf;
  try {
    row.hidden = hiddenOf(resolveLayout(kept, row.type || "", saved));
  } catch {
    row.hidden = [];
  }
  try {
    row.shoots = restyle(row.shoots || [], row, now);
  } catch { /* as the Mac: the shoots stay as read */ }
  return row;
}

// ── engine.fetch_projects ────────────────────────────────────────────────────

// Released (2026-10-15) sits between Post and Archived; Closed never reaches a list.
const ORDER = { Development: 0, Active: 1, Post: 2, Released: 3, Archived: 4, Closed: 5 };
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/** One Projects row as the console's list has it, before the record. */
export function projectRow(page, crew, byProject, now) {
  const props = page.properties || {};
  const ptype = selectOf(props, "Type");
  const status = selectOf(props, "Status") || "?";
  const [icon, iconColor] = projectIcon(page, ptype, status);
  const [iconName, iconColorName] = iconNameColor(page);
  const directors = (((props.Director || {}).relation) || []).map((r) => crew[bareId(r.id)] || "").filter(Boolean);
  const mine = byProject[bareId(page.id)] || [];
  const dates = dateStart(props, "Shoot Dates");
  const datesEnd = dateEnd(props, "Shoot Dates");
  return {
    page_id: page.id,
    // SERVER: the record's key — the project's one ID (projectid.js)
    id: bareId(page.id),
    name: plainTitle(props),
    director: directors.join(" & "),
    status,
    type: ptype,
    length: selectOf(props, "Length"),
    dates,
    dates_end: datesEnd,
    color: selectOf(props, "Color"),
    shoots: readout(mine, { dates, status, type: ptype, dates_end: datesEnd }, now),
    last_edited: page.last_edited_time || "",
    drive_url: urlOf(props, "Drive Folder"),
    website_url: urlOf(props, "Website"),
    notion_url: page.url || "",
    icon,
    icon_color: iconColor,
    icon_name: iconName || "",
    // SERVER: which of Notion's icon pictures; the Mac lays the picture on
    icon_key: iconName && iconColorName ? { name: iconName, color: iconColorName } : null,
  };
}

/** Sorted as the Mac sorts: stage, then name without regard to case. */
export function sortRows(rows) {
  return rows.map((r, i) => [r, i]).sort((a, b) => {
    const s = (ORDER[a[0].status] ?? 4) - (ORDER[b[0].status] ?? 4);
    if (s) return s;
    const n = cmp(String(a[0].name).toLowerCase(), String(b[0].name).toLowerCase());
    return n || a[1] - b[1];
  }).map((p) => p[0]);
}

/** A record that is a Job (no Notion Projects row by design), as a list row. */
export function jobRow(record, now = "") {
  const f = (record && record.facts) || {};
  const v = (k) => keptStr(f, k);
  const [start, end] = splitDates(v("shoot_dates") || "");
  const type = v("type") || record.type || "";
  const status = v("status") || record.stage || "";
  const dates = start || record.dates || "";
  // SERVER (stage 5 step 5): what a Job's card in its own category needs —
  // its Type and modes (none, by the rule), its stage, both days, its shoot.
  let shoots = [];
  try { shoots = readout([], { dates, dates_end: end, status, type }, now || undefined); } catch { shoots = []; }
  return {
    page_id: "", id: record.page, kind: "job", name: v("title") || record.name || "",
    status, stage: status, type,
    dates, dates_end: end || "",
    drive_url: v("drive_folder") || "", notion_url: "", shoots, icon: "box", icon_color: "#787774",
    color: v("color") || "",
    modes: resolveModes(record).modes,
  };
}

/**
 * The list. `pages` are the Projects rows (Notion's order, by Status), `crew`
 * the Crew rows, `shoots` the Shoots rows, `records` every record
 * (`{key: record}`), `saved` his record standards. Pure: the checks call it.
 */
export function buildList({ pages, crew, shoots, records, saved, now }) {
  const names = {};
  for (const p of crew || []) names[bareId(p.id)] = plainTitle(p.properties || {});
  const byProject = shootsByProject(shoots);
  const byNotion = {};
  const jobs = [];
  for (const [key, r] of Object.entries(records || {})) {
    if (!isObject(r)) continue;
    // Deleted (bigmoves.js): a tombstone, off every list.
    if (r.deleted) continue;
    if (r.closed && r.kind === "job") continue;
    if (r.kind === "job") { jobs.push(jobRow({ ...r, page: r.page || key }, now)); continue; }
    const page = typeof r.notion_page === "string" && /^[0-9a-f]{32}$/.test(r.notion_page) ? r.notion_page : (r.page || key);
    byNotion[bareId(page)] = { key: r.page || key, record: r };
    const copy = isObject(r.facts) && isObject(r.facts.shoots) ? r.facts.shoots.value : null;
    if (Array.isArray(copy) && copy.length) byProject[bareId(page)] = withRecordCopy(byProject[bareId(page)], copy, bareId(page));
  }
  // Sorted by Notion's stage first, then the record laid on — the Mac's order
  // (fetch_projects sorts, then overlay_rows), so a stage typed in the
  // console moves the row's words, not its place, until Notion follows.
  const rows = sortRows((pages || []).map((page) => projectRow(page, names, byProject, now)));
  for (const row of rows) {
    const hit = byNotion[bareId(row.page_id)];
    if (hit) row.id = bareId(hit.key);
    // A renamed project's footage keeps its old folder name on each drive
    // (bigmoves.js): the Mac's drive light looks it up by that name.
    if (hit && isObject(hit.record.media_names)) row.media_names = hit.record.media_names;
    // A project with no record yet gets the record's defaults (no credits,
    // what its Type's standard hides) — as the Mac's overlay_rows does.
    overlayRow(row, (hit && isObject((hit.record || {}).facts)) ? hit.record.facts : {}, saved, now);
    row.kind = "project";
  }
  // Closed (closeproject.js): off every list until Reopen Project.
  const isClosed = (row) => row.status === "Closed" || Boolean(((byNotion[bareId(row.page_id)] || {}).record || {}).closed);
  const open = rows.filter((row) => !isClosed(row));
  // SERVER: the closed rows' page ids, so a Mac that lays its own rows in
  // (hubbackend.py) leaves them out too.
  const closed = rows.filter(isClosed).map((row) => bareId(row.page_id));
  return { closed, projects: open, jobs: jobs.sort((a, b) => cmp(a.name.toLowerCase(), b.name.toLowerCase())) };
}

// ── backend.films_shelf, from the records ────────────────────────────────────

/** dossier.remember_viewers: "4 of 9" — What Viewers See's sections shown. */
export function viewersCount(got) {
  const sections = (got && Array.isArray(got.sections) ? got.sections : []).filter(isObject);
  if (!got || !Array.isArray(got.sections)) return null;
  return { shown: sections.filter((s) => s.shown).length, offered: sections.length };
}

/** dossier.shelf_portal, read off the record the Mac published; `seen` is
 * What Viewers See's count (`viewersCount`), read fresh here where the Mac
 * keeps the last one it read. */
export function shelfOf(row, record, seen = null) {
  const r = isObject(record) ? record : {};
  const film = isObject(r.film) && r.film.relay ? r.film : null;
  const portal = isObject(r.portal) ? r.portal : null;
  const one = { name: row.name, film: Boolean(film) };
  if (!portal) return { ...one, portal: false, known: Boolean(record) };
  const share = isObject(portal.share) ? portal.share : {};
  const vis = Array.isArray(portal.visible) ? portal.visible : [];
  const counts = {};
  if (film) for (const k of ["shots", "scenes", "days", "boards"]) if (typeof film[k] === "number") counts[k] = film[k];
  return {
    ...one, portal: true, known: true,
    down: Boolean(portal.down), anyone: Boolean(share.on), link: Boolean(share.count),
    short: share.address || "", address: share.address || "", people: Number(share.people) || 0,
    shown: seen ? seen.shown : vis.filter((v) => v && v.on).length, offered: seen ? seen.offered : vis.length,
    counts, read_at: portal.updated || "",
  };
}

export function filmsShelf(list, records, seen = {}) {
  const byNotion = {};
  for (const [key, r] of Object.entries(records || {})) {
    if (!isObject(r)) continue;
    const page = typeof r.notion_page === "string" && r.notion_page ? r.notion_page : (r.page || key);
    byNotion[bareId(page)] = r;
  }
  return { ok: true, films: (list.projects || []).map((row) => shelfOf(row, byNotion[bareId(row.page_id)], seen[bareId(row.page_id)] || null)) };
}

/** What Viewers See's count for every project with a portal, read through
 * `viewers(page)` (the worker's own door, or the live one in the proof). */
export async function viewersSeen(list, records, viewers) {
  const out = {};
  const byNotion = {};
  for (const [key, r] of Object.entries(records || {})) {
    if (!isObject(r)) continue;
    const page = typeof r.notion_page === "string" && r.notion_page ? r.notion_page : (r.page || key);
    byNotion[bareId(page)] = r;
  }
  await Promise.all((list.projects || []).map(async (row) => {
    const k = bareId(row.page_id);
    if (!isObject((byNotion[k] || {}).portal)) return;
    try {
      const n = viewersCount(await viewers(k));
      if (n) out[k] = n;
    } catch { /* the record's own line stands */ }
  }));
  return out;
}

// ── reading it all ───────────────────────────────────────────────────────────

async function queryAll(n, source, body = {}) {
  const out = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${source}/query`, { page_size: 100, ...body, ...(cursor ? { start_cursor: cursor } : {}) });
    out.push(...(got.results || []));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/** Every record: {key: record}, read whole. */
export async function allRecords(env) {
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const k = p.split("/")[1];
      if (/^[0-9a-f]{32}$/.test(k)) keys.push(k);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  const out = {};
  await Promise.all(keys.map(async (k) => {
    const got = await env.BUCKET.get(`r/${k}/record.json`);
    if (!got) return;
    try { out[k] = await got.json(); } catch { /* a record that will not read is left out */ }
  }));
  return out;
}

/** The ask `project_list`: `{projects, jobs}` — the console's own rows. */
export async function projectList(env, n, { now } = {}) {
  await loadStandards(env);
  const [pages, crew, shoots, records, saved] = await Promise.all([
    queryAll(n, SOURCES.projects, { sorts: [{ property: "Status", direction: "ascending" }] }),
    queryAll(n, SOURCES.crew).catch(() => []),
    queryAll(n, SOURCES.shoots).catch(() => []),
    allRecords(env),
    savedTemplates(env),
  ]);
  const { today } = await import("./projectpage.js");
  return { ok: true, ...buildList({ pages, crew, shoots, records, saved, now: now || today() }) };
}

/** The ask `films_shelf`. */
export async function filmsShelfAsk(env, n) {
  const list = await projectList(env, n);
  const records = await allRecords(env);
  const { portalViewersOf } = await import("./cloudportal.js");
  return filmsShelf(list, records, await viewersSeen(list, records, (page) => portalViewersOf(env, page)));
}
