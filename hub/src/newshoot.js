/**
 * **New Shoot, answered by the server** (2026-10-13, Projects Console
 * without the Mac, stage 4 part A). The Mac's one button that sets up the
 * next shoot on a project that shoots more than once, ported rule for rule:
 *
 * - `backend.py`: `_shoots_ctx`, `new_shoot_form`, `_shotlister_preview`,
 *   `plan_new_shoot`, `run_new_shoot` — the three asks the phone makes
 *   (`NewShootView.swift`) and the words it shows;
 * - `rituals.py`: `plan_new_shoot`, `_what_changes`, `_pretty`, `_long`,
 *   `_iso`, `SYSTEMS` — every step, grouped by the system it touches;
 * - `shoots.py`: reading the Shoots rows, spec sheets and crew, and
 *   `execute` with everything it writes (`create_crew`, `create_shoot_row`,
 *   `retitle_sheet`, `copy_spec_sheet` and its block copier and file carrier,
 *   `set_shoot_status`, `set_project_dates`, `set_project_status`).
 *
 * Change a rule there and change it here in the same breath; the words are
 * the Mac's, because the phone shows them. `hub/newshoot.mjs` holds this file
 * to the Mac's own code on real projects (`hub/newshoot-real.py`), request for
 * request.
 *
 * **Everything outside comes in as `deps`** — Notion, the record, the film,
 * Shotlister's door, the Drive, the portal refresh, a file download and a
 * Notion upload — so the checks can run every rule in plain node. The worker
 * hands in the real ones (`newshootdoor.js`).
 *
 * What is the server's own and not the Mac's:
 * - **Notion** speaks its newer dialect (2025-09-03): a list is a data source,
 *   so `databases/<id>/query` is `data_sources/<id>/query` and a new row's
 *   parent is its data source. The bodies are otherwise the Mac's.
 * - **The film** is the relay copy the project's record names (`film.relay`),
 *   read by the engine in the worker, not the Mac's copy on its disk.
 * - **The Drive** is Google's own (`drivefolders.js` `planShoot` / `carryOut`
 *   for the `shoot-N` folders, a walk of the project folder for a LUT's Drive
 *   copy), not the Mac's mounted folder. The plugged-in media drives were
 *   never part of New Shoot.
 */

import { Handoff, bareId, plainTitle, words, relationAll, cleanName, nameProblem } from "./cloud.js";
import { urlRefusal } from "./notionlink.js";
import { shootOf, orderShoots, readout, today as todayHere } from "./projectpage.js";
import { SHOOT_SECTIONS } from "./drivefolders.js";
import { fieldText, pillsOf } from "./entries.js";

/** The data sources (2025-09-03) of the Mac's databases. */
export const SHOOTS = "feedface-0000-4000-8000-000000000002";   // shoots.SHOOTS_DB
export const SPECS = "feedface-0000-4000-8000-000000000003";    // shoots.SPEC_DB
export const CREW = "feedface-0000-4000-8000-000000000004";     // engine.CREW_DB
const parentOf = (source) => ({ type: "data_source_id", data_source_id: source });

/** rituals.SYSTEMS — the preview's groups, in his order. */
export const SYSTEMS = ["NOTION", "DRIVE", "SHOTLISTER", "PORTAL"];
/** shoots.SPEC_EDITABLE — the spec-sheet fields the form shows. */
export const SPEC_EDITABLE = ["Camera", "Lenses"];
const NAME_SEP = " · ";
const NOTION_COLORS = ["gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"];

// ── small things Python does for free ────────────────────────────────────────

/** Notion refused before anything was written: the whole ask is the Mac's. */
const isHandoff = (e) => e instanceof Handoff;
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const str = (v) => (v == null ? "" : String(v));
const strip = (v) => str(v).trim();
/** Python's `str(x)` of a pickup the phone sent (a number or its words). */
const pyStr = (v) => (typeof v === "number" && Number.isInteger(v) ? String(v) : str(v));
const selectOf = (props, name) => ((((props || {})[name] || {}).select) || {}).name || "";
/** engine.prop_text — rich text only. */
const propText = (props, name) => words(((props || {})[name] || {}).rich_text);

/** `pathlib.PurePosixPath(name).suffix`. */
export function suffixOf(name) {
  const parts = str(name).split("/").filter((p) => p && p !== ".");
  const last = parts.length ? parts[parts.length - 1] : "";
  const i = last.lastIndexOf(".");
  return i > 0 && i < last.length - 1 ? last.slice(i) : "";
}
/** `pathlib.PurePosixPath(name).name`. */
const nameOfPath = (p) => { const parts = str(p).split("/").filter((x) => x && x !== "."); return parts.length ? parts[parts.length - 1] : ""; };

// ── days (rituals.py) ────────────────────────────────────────────────────────

const SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const LONG = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December"];

function dayOf(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(str(iso).slice(0, 10));
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const back = new Date(Date.UTC(y, mo - 1, d));
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) return null;
  return { y, m: mo, d };
}

/** rituals._iso — a day as typed, or "". (The phone's date picker sends
 * YYYY-MM-DD; Python would also take the compact ISO forms, which nothing sends.) */
export function isoDay(value) {
  const v = strip(value).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(v) && dayOf(v) ? v : "";
}
/** rituals._pretty — 'Oct 6'. */
export const pretty = (iso) => { const a = dayOf(iso); return a ? `${SHORT[a.m - 1]} ${a.d}` : ""; };
/** rituals._long — 'October 6'. */
export const longDay = (iso) => { const a = dayOf(iso); return a ? `${LONG[a.m - 1]} ${a.d}` : ""; };

// ── a shoot's words (shoots.py) ──────────────────────────────────────────────

const NUMBER = /\bShoot\s+(\d+)\b/i;
export function shootNumber(title) {
  const m = NUMBER.exec(str(title));
  return m ? Number(m[1]) : null;
}

const SHOOT_WORDS = { principal: "Principal", additional: "Additional Shoot", shoot: "Shoot" };
export const isCommercial = (ptype) => ["commercial", "music video"].includes(strip(ptype).toLowerCase().replace(/\s+/g, " "));

/** shoots.display_label. */
export function displayLabel(index, total, commercial, n = null) {
  const num = n || index + 1;
  if (commercial) return total === 1 ? SHOOT_WORDS.shoot : `${SHOOT_WORDS.shoot} ${num}`;
  if (index === 0) return SHOOT_WORDS.principal;
  return total === 2 ? SHOOT_WORDS.additional : `${SHOOT_WORDS.additional} ${num}`;
}

/** shoots.next_label. */
export function nextLabel(count, ptype, n = null) {
  const have = Math.max(count, 1);
  return displayLabel(have, have + 1, isCommercial(ptype), n || have + 1);
}

/** shoots.sheet_title — `<Name> - Shoot N - Camera Spec Sheet`, keeping the
 * film's spelling from the last sheet. */
export function sheetTitle(prevTitle, projectName, n) {
  const m = /^(.*?)\s+-\s+Shoot\s+\d+\s+-\s+Camera Spec Sheet\s*$/i.exec(str(prevTitle));
  const pre = m ? m[1] : str(prevTitle).replace(/\s*-?\s*Camera Spec Sheet\s*$/i, "").trim();
  return `${pre || projectName} - Shoot ${n} - Camera Spec Sheet`;
}

/** shoots.carried_heading — a copied "Shoot 1 Camera Settings:" said honestly. */
export function carriedHeading(text, prevN) {
  const m = /^\s*(?:Shoot\s+\d+\s+Camera Settings|Camera Settings\s*\(carried over from Shoot\s+\d+, confirm on the day\))\s*(:?)\s*$/i.exec(str(text));
  if (!m) return null;
  return `Camera Settings (carried over from Shoot ${prevN}, confirm on the day)${m[1]}`;
}

/** shoots._rich — plain text as Notion rich text, under the cap. */
export function rich(text) {
  const s = str(text);
  const out = [];
  for (let i = 0; i < s.length; i += 1900) out.push({ type: "text", text: { content: s.slice(i, i + 1900) } });
  return out;
}

/** shoots.calendar_icon — Notion's calendar in the project's colour. */
export function calendarIcon(color) {
  const c = NOTION_COLORS.includes(color) ? color : "gray";
  return { type: "external", external: { url: `https://www.notion.so/icons/calendar_${c}.svg` } };
}

/** crewrows.icon_for, for the one kind New Shoot makes: a person. */
const PERSON_ICON = { type: "external", external: { url: "https://www.notion.so/icons/person-masculine_gray.svg" } };

// ── reading (shoots.py) ──────────────────────────────────────────────────────

async function queryAll(n, source, body = {}) {
  const out = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${source}/query`, { ...body, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    out.push(...(got.results || []));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/** shoots.project_shoots — this project's shoots, oldest first. */
export async function projectShoots(n, pageId) {
  const pages = await queryAll(n, SHOOTS, { filter: { property: "Project", relation: { contains: pageId } } });
  const out = [];
  for (const p of pages) out.push(await shootOf(n, p));
  return orderShoots(out);
}

/** shoots.spec_sheets — newest first. */
export async function specSheets(n, pageId) {
  return await queryAll(n, SPECS, {
    filter: { property: "Projects", relation: { contains: pageId } },
    sorts: [{ timestamp: "created_time", direction: "descending" }],
  });
}

/** shoots.spec_summary. */
export function specSummary(page) {
  const props = page.properties || {};
  const files = [];
  for (const field of Object.values(props)) {
    if (field && field.type === "files") for (const f of field.files || []) files.push(f.name || "");
  }
  return {
    id: page.id,
    title: plainTitle(props),
    url: page.url || "",
    shoot: (((props.Shoot || {}).relation) || []).map((r) => r.id),
    fields: Object.fromEntries(SPEC_EDITABLE.map((k) => [k, fieldText((props || {})[k])])),
    files,
  };
}

/** shoots.pick_last_sheet — the one the last shoot links, else the newest
 * tied to no shoot, else the newest. */
export function pickLastSheet(sheets, lastShoot) {
  if (lastShoot) {
    const linked = new Set((lastShoot.spec || []).map(bareId));
    for (const page of sheets) if (linked.has(bareId(page.id))) return page;
  }
  for (const page of sheets) if (!(((page.properties || {}).Shoot || {}).relation || []).length) return page;
  return sheets.length ? sheets[0] : null;
}

/** shoots._crew_row. */
function crewRow(page) {
  const props = page.properties || {};
  return {
    id: page.id,
    name: plainTitle(props),
    role: (((props.Role || {}).multi_select) || []).map((o) => o.name).join(", "),
    department: selectOf(props, "Department"),
    type: selectOf(props, "Type"),
    company: selectOf(props, "Company"),
    location: selectOf(props, "Location"),
    email: (props.Email || {}).email || "",
    phone: (props.Phone || {}).phone_number || "",
    url: page.url || "",
    projects: (((props.Projects || {}).relation) || []).map((r) => bareId(r.id)),
    shoots: (((props.Shoots || {}).relation) || []).map((r) => bareId(r.id)),
  };
}

/** shoots.all_crew — every Crew row (the Mac keeps it five minutes; asked fresh here). */
export async function allCrew(n) {
  return (await queryAll(n, CREW)).map(crewRow);
}

/** shoots.crew_departments. */
async function crewDepartments(n) {
  try {
    const ds = await n.get(`data_sources/${CREW}`);
    return ds.properties.Department.select.options.map((o) => o.name);
  } catch (e) {
    if (isHandoff(e)) throw e;
    return [];
  }
}

// ── the context (backend._shoots_ctx) ────────────────────────────────────────

/** The film, the portal and Shotlister's door as the plan reads them. None of it is Notion's. */
async function worldOf(deps, page, name) {
  const film = await deps.film(page, name);
  const filmCtx = film.ok
    ? { ok: true, title: film.title, trouble: film.trouble || "", scenes: film.scenes || [], sections: film.sections || [], days: film.days || [] }
    : { ok: false, why: film.why || "no Shotlister film" };
  const portal = await deps.portal(page, film);
  let door = null, doorWhy = "";
  if (film.ok) {
    const [live, why] = await deps.door.live(film.relay || "");
    doorWhy = why;
    door = live ? { relay: film.relay } : null;
  }
  return { filmCtx, portal, door, doorWhy };
}

/**
 * Everything plan_new_shoot reads, fresh: the project row (its stage, dates
 * and colour as Notion has them this second; its type, the shoot's own name
 * and the Drive link as the record lays them over), its Shoots rows, spec
 * sheets and crew, the film, the portal and Shotlister's door.
 */
export async function shootsCtx(deps, name) {
  const { n } = deps;
  const row = await deps.row(name);
  if (!row) throw new Error(`No Notion row for ${name}`);
  const pid = row.id;
  // The row as the console's list has it (engine.fetch_projects +
  // record.overlay_rows): the record's typed type, shoot name and Drive link.
  const facts = (await deps.facts(bareId(pid))) || {};
  const kept = (field) => { const one = facts[field]; return isObject(one) && typeof one.value === "string" ? one.value : null; };
  const props = (await n.get(`pages/${pid}`)).properties || {};
  const when = ((props["Shoot Dates"] || {}).date) || {};
  const rowProps = row.properties || {};
  let type = selectOf(rowProps, "Type");
  if (kept("type") !== null) type = kept("type");
  let driveUrl = (rowProps["Drive Folder"] || {}).url || "";
  if (kept("drive_folder") !== null && !urlRefusal(kept("drive_folder"))) driveUrl = kept("drive_folder");
  const shootName = kept("shoot_name") !== null ? kept("shoot_name") : "";
  const mine = await projectShoots(n, pid);
  const sheets = await specSheets(n, pid);
  const lastPage = pickLastSheet(sheets, mine.length ? mine[mine.length - 1] : null);
  const crew = await allCrew(n);
  const { filmCtx, portal, door, doorWhy } = await worldOf(deps, bareId(pid), name);
  return {
    project: { name, page_id: pid, status: selectOf(props, "Status"),
      dates: str(when.start).slice(0, 10), dates_end: str(when.end).slice(0, 10),
      color: selectOf(props, "Color"), type, shoot_name: shootName },
    drive_url: driveUrl,
    shoots: mine,
    sheets: sheets.map(specSummary),
    last_sheet: lastPage ? specSummary(lastPage) : null,
    crew,
    crewById: new Map(crew.map((c) => [c.id, c])),
    project_crew: crew.filter((c) => c.projects.includes(bareId(pid))).map((c) => c.id),
    film: filmCtx,
    portal,
    shotlister_door: door,
    shotlister_why: doorWhy,
    // Stage 5 step 4 piece E (studioframes.js): the film's day belongs to
    // the new shoot and follows its dates; no section. Off: the Mac's rule.
    ...(deps.daysFollow && (await deps.daysFollow()) ? { days_follow: true } : {}),
  };
}

const ARCHIVED_FORM = (name) => `${name} is Archived — its folder is in projects/z-archived/, `
  + "and bringing it back is its own decision. Set it to Active "
  + "first if another shoot is really coming.";

/**
 * The people the form offers, each ticked when on the last shoot (or, with no
 * shoot yet, on the project): backend.new_shoot_form's `crew`. Pure.
 */
export function offeredCrew(ctx) {
  const mine = ctx.shoots;
  const lastCrew = mine.length ? [...mine[mine.length - 1].crew] : [...ctx.project_crew];
  const lastSet = new Set(lastCrew.map(bareId));
  const offered = [];
  const seen = new Set();
  for (const cid of [...lastCrew, ...ctx.project_crew, ...mine.flatMap((s) => s.crew)]) {
    const key = bareId(cid);
    if (seen.has(key)) continue;
    seen.add(key);
    const row = ctx.crew.find((c) => bareId(c.id) === key);
    if (!row) continue;
    offered.push({ id: row.id, name: row.name, role: row.role, department: row.department, type: row.type, ticked: lastSet.has(key) });
  }
  return offered;
}

/** backend.new_shoot_form — what the form starts from. Reads only. */
export async function newShootForm(deps, name, opts = {}) {
  let ctx;
  try {
    ctx = opts.ctx || await shootsCtx(deps, name);
  } catch (e) {
    if (notionOut(e)) throw e;
    return { ok: false, why: str((e && e.message) || e) };
  }
  const { project } = ctx;
  const mine = ctx.shoots;
  if (project.status === "Archived") return { ok: false, refuse: true, why: ARCHIVED_FORM(name) };
  const first = !mine.length;
  const numbers = mine.map((s) => s.n).filter(Boolean);
  const nNext = numbers.length ? Math.max(...numbers) + 1 : (first ? 2 : mine.length + 1);
  const offered = offeredCrew(ctx);
  const sheet = ctx.last_sheet;
  const film = ctx.film;
  const now = deps.now;
  const shown = readout(mine, project, now);
  const commercial = isCommercial(project.type);
  return {
    ok: true, name, first_time: first, n: nNext,
    default_name: `Shoot ${nNext}`,
    project: { status: project.status, dates: project.dates, dates_end: project.dates_end, color: project.color },
    shoots: shown,
    commercial,
    next_label: nextLabel(mine.length, project.type, nNext),
    last: mine.length
      ? { label: shown[shown.length - 1].label, start: mine[mine.length - 1].start, end: mine[mine.length - 1].end }
      : { label: project.dates ? readout([], project, now)[0].label : displayLabel(0, 1, commercial),
        start: project.dates, end: project.dates_end },
    crew: offered,
    departments: opts.mode === "down" ? [] : await crewDepartments(deps.n),
    ...(opts.mode === "down" ? { notion_down: true } : {}),
    fields: { ...((sheet && sheet.fields) || Object.fromEntries(SPEC_EDITABLE.map((k) => [k, ""]))) },
    sheet: sheet ? { title: sheet.title, files: sheet.files } : null,
    film: { ok: film.ok, title: film.title || "", why: film.why || film.trouble || "", scenes: film.scenes || [] },
    portal: ctx.portal,
    shotlister_door: Boolean(ctx.shotlister_door),
    shotlister_why: ctx.shotlister_why,
  };
}

// ── the plan (rituals.plan_new_shoot) ────────────────────────────────────────

/** rituals._what_changes — written for him when he leaves the box empty. */
export function whatChanges(form, lastFields, newcomers, prevLabel) {
  const bits = [];
  const scenes = (form.new_scenes || []).filter((s) => strip(s));
  if (scenes.length) bits.push(`New: ${scenes.join(", ")}.`);
  const picks = form.pickups || [];
  if (picks.length) bits.push(`Pickups of scene${picks.length > 1 ? "s " : " "}${picks.map(pyStr).join(", ")}.`);
  for (const [name, value] of Object.entries(isObject(form.fields) ? form.fields : {})) {
    if (strip(value) && strip(value) !== strip(lastFields[name])) {
      bits.push(name.endsWith("s") ? `${name} change to ${strip(value)}.` : `${name} changes to ${strip(value)}.`);
    }
  }
  if (newcomers.length) bits.push(`New crew: ${newcomers.map((c) => c.name).join(", ")}.`);
  return bits.join(" ") || (prevLabel ? `Same as ${prevLabel}.` : "");
}

/** shoots._UPLOAD_OK — the files Notion takes back from an app. */
export const UPLOAD_OK = new Set([".pdf", ".txt", ".json", ".xml", ".csv", ".doc", ".docx", ".xls",
  ".xlsx", ".ppt", ".pptx", ".png", ".jpg", ".jpeg", ".gif", ".webp",
  ".heic", ".svg", ".tif", ".tiff", ".ico", ".mp4", ".mov", ".m4v",
  ".mp3", ".wav", ".m4a", ".aac", ".ogg"]);
const UPLOAD_CAP = 20 * 1024 * 1024;
/** Python's `mimetypes.guess_type` for those, as the Mac answers it. */
export const MIME = {
  ".pdf": "application/pdf", ".txt": "text/plain", ".json": "application/json", ".xml": "application/xml",
  ".csv": "text/csv", ".doc": "application/msword",
  ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ".xls": "application/vnd.ms-excel", ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ".ppt": "application/vnd.ms-powerpoint",
  ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp",
  ".heic": "image/heic", ".svg": "image/svg+xml", ".tif": "image/tiff", ".tiff": "image/tiff", ".ico": "image/x-icon",
  ".mp4": "video/mp4", ".mov": "video/quicktime", ".m4v": "video/x-m4v", ".mp3": "audio/mpeg", ".wav": "audio/x-wav",
  ".m4a": "audio/mp4a-latm", ".aac": "audio/x-aac", ".ogg": "audio/ogg",
};
const mimeOf = (name) => MIME[suffixOf(name)] || MIME[suffixOf(name).toLowerCase()] || "application/octet-stream";

function newPlan(project) {
  return { project, steps: [], problems: [], notes: [], shoot: null, later: [],
    groups: Object.fromEntries(SYSTEMS.map((s) => [s, []])), changes: "", changes_written: false, drive: null };
}

/**
 * Every step of setting up the next shoot, read-only — rituals.plan_new_shoot.
 * `deps.drive.plan(facts)` is `drivefolders.planShoot` (the Drive's shape,
 * read only) and `deps.drive.copy(folderId, name)` a file's Drive link.
 */
export async function planNewShoot(deps, ctx, form) {
  const f = isObject(form) ? form : {};
  const project = ctx.project;
  const name = project.name;
  const plan = newPlan(name);
  const add = (system, kind, detail, extra = {}) => {
    const step = { kind, detail, system, payload: "", ...extra };
    plan.steps.push(step);
    plan.groups[system].push(step);
    return step;
  };

  // ── refusals, in plain words ─────────────────────────────────────────────
  if (project.status === "Archived") {
    plan.problems.push(`${name} is Archived — its folder is in projects/z-archived/, and bringing `
      + "a project back is its own decision. Set it back to Active first if "
      + "another shoot is really coming.");
    return plan;
  }
  const start = isoDay(f.start);
  let end = isoDay(f.end);
  if (!start) { plan.problems.push("Pick the date of the shoot."); return plan; }
  if (end && end < start) { plan.problems.push("The last day is before the first."); return plan; }
  if (end === start) end = "";

  const shoots = orderShoots(ctx.shoots || []);
  const firstTime = !shoots.length;
  const numbers = shoots.map((s) => s.n).filter(Boolean);
  const n = numbers.length ? Math.max(...numbers) + 1 : (firstTime ? 2 : shoots.length + 1);
  let typed = strip(f.name);
  if (typed && shootNumber(typed) === n) typed = cleanName(typed.replace(new RegExp(`\\bShoot\\s+${n}\\b`, "gi"), " "));
  const why = nameProblem(typed);
  if (why) { plan.problems.push(why); return plan; }
  typed = cleanName(typed);
  const label = typed ? `Shoot ${n}${NAME_SEP}${typed}` : `Shoot ${n}`;
  const title = `${name} — ${label}`;
  plan.shoot = { n, label, title, start, end };
  const sectionName = `${label} — ${longDay(start)}`;
  const color = project.color || "";
  const pid = project.page_id;
  const todayIso = deps.now;

  // The Drive's shape, read once when first needed (the Mac reads its
  // mounted folder as it goes).
  let driveHeld = null;
  const drive = async () => (driveHeld ||= await deps.drive.plan({
    name, status: project.status, dates: project.dates, drive_url: ctx.drive_url, rows: shoots, n }));

  // ── NOTION ───────────────────────────────────────────────────────────────
  const newcomers = (Array.isArray(f.newcomers) ? f.newcomers : []).filter((c) => isObject(c) && strip(c.name));
  const crewNames = new Map([...ctx.crewById].map(([k, v]) => [k, v.name || ""]));
  newcomers.forEach((c, i) => {
    const what = [strip(c.role), strip(c.department)].filter(Boolean).join(" · ");
    const contact = [strip(c.email), strip(c.phone)].filter(Boolean).join(", ");
    add("NOTION", "crew-new",
      `Add ${strip(c.name)} to Crew${what ? ` — ${what}` : ""}${contact ? ` (${contact})` : " (no contact details yet)"}`,
      { payload: { key: `crew-${i}`, name: strip(c.name), project_id: pid, role: str(c.role), department: str(c.department),
        email: str(c.email), phone: str(c.phone) } });
  });

  const sheets = ctx.sheets || [];
  let lastSheet = ctx.last_sheet;
  const prevLabel = shoots.length ? shoots[shoots.length - 1].label : "Shoot 1";
  const prevN = shoots.length ? (shoots[shoots.length - 1].n || n - 1) : 1;

  if (firstTime) {
    const s1Start = str(project.dates).slice(0, 10);
    const s1End = str(project.dates_end).slice(0, 10);
    if (!s1Start) {
      plan.problems.push(`${name} has no Shoot Dates, so there is no first shoot to build Shoot 1 `
        + "from. Put its date in Notion first, or set this one up as Shoot 1 by hand.");
      return plan;
    }
    const s1Done = (s1End || s1Start) < todayIso;
    const firstCrew = [...(Array.isArray(f.first_crew) ? f.first_crew : [])];
    const who = firstCrew.map((i) => (crewNames.has(i) ? crewNames.get(i) : "?")).join(", ") || "nobody ticked";
    const own = cleanName(project.shoot_name || "");
    const firstLabel = own ? `Shoot 1${NAME_SEP}${own}` : "Shoot 1";
    add("NOTION", "shoot-row",
      `First time: build Shoot 1 from what exists — ${name} — ${firstLabel}, `
      + `${pretty(s1Start)}, ${s1Done ? "Wrapped" : "Upcoming"}, crew: ${who}`,
      { payload: { key: "shoot-1", title: `${name} — ${firstLabel}`, project_id: pid, start: s1Start, end: s1End,
        status: s1Done ? "Wrapped" : "Upcoming", crew: firstCrew, color } });
    if (lastSheet && !(lastSheet.shoot || []).length) {
      const t1 = sheetTitle(lastSheet.title, name, 1);
      add("NOTION", "sheet-retitle", `Rename the spec sheet “${lastSheet.title}” → “${t1}” and tie it to Shoot 1`,
        { payload: { sheet_id: lastSheet.id, title: t1, shoot_key: "shoot-1" } });
      lastSheet = { ...lastSheet, title: t1 };
    }
  }

  const crewIds = [...(Array.isArray(f.crew) ? f.crew : [])];
  const who = [...crewIds.map((i) => (crewNames.has(i) ? crewNames.get(i) : "?")), ...newcomers.map((c) => strip(c.name))];
  let changes = strip(f.changes);
  const lastFields = (lastSheet && lastSheet.fields) || {};
  const writtenForHim = !changes;
  if (!changes) changes = whatChanges(f, lastFields, newcomers.map((c) => ({ ...c, name: str(c.name) })), prevLabel);
  const when = pretty(start) + (end ? `–${pretty(end)}` : "");
  add("NOTION", "shoot-row", `Create ${title} — ${when}, Upcoming, crew: ${who.join(", ") || "none yet"}`,
    { payload: { key: "shoot-new", title, project_id: pid, start, end, status: "Upcoming", crew: crewIds,
      crew_keys: newcomers.map((_, i) => `crew-${i}`), section: sectionName, changes, color } });
  plan.changes = changes;
  plan.changes_written = writtenForHim;
  if (shoots.some((s) => strip(s.title).toLowerCase() === title.toLowerCase())) {
    plan.notes.push(`${title} is already in Notion — that row is used, not copied.`);
  }

  if (lastSheet) {
    const tn = sheetTitle(lastSheet.title, name, n);
    const edits = {};
    for (const [k, v] of Object.entries(isObject(f.fields) ? f.fields : {})) {
      if (strip(v) && strip(v) !== strip(lastFields[k])) edits[k] = strip(v);
    }
    const changed = Object.entries(edits).map(([k, v]) => `${k} → ${v}`).join("; ");
    const files = lastSheet.files || [];
    for (const fname of files) {
      if (UPLOAD_OK.has(suffixOf(fname).toLowerCase())) continue;
      if (await driveCopy(deps, await drive(), fname)) {
        plan.notes.push(`${fname} goes onto the new sheet as a link to its copy in the `
          + "Drive folder — Notion won't let an app upload that kind of file.");
      } else {
        plan.notes.push(`${fname} can't be copied by the console (Notion won't let an `
          + "app upload that kind of file) and there is no copy in the Drive "
          + "folder to link — drag it onto the new sheet from the last one.");
      }
    }
    add("NOTION", "sheet-copy",
      `Copy the spec sheet “${lastSheet.title}” → “${tn}” — its fields, notes and `
      + `files${files.length ? ` (${files.join(", ")})` : ""}, tied to this shoot only`
      + (changed ? `; ${changed}` : "; camera and lenses unchanged"),
      { payload: { src_id: lastSheet.id, title: tn, shoot_key: "shoot-new", edits, prev_n: prevN } });
    if (sheets.some((s) => strip(s.title).toLowerCase() === tn.toLowerCase())) plan.notes.push(`“${tn}” already exists — it is left as it is.`);
  } else {
    plan.notes.push("No camera spec sheet on this project yet — nothing to copy.");
  }

  for (const s of shoots) {
    if (s.status === "Upcoming" && ((s.end || s.start || "9999") < todayIso)) {
      add("NOTION", "shoot-status", `Mark ${s.label} Wrapped — its date (${pretty(s.start)}) has passed`,
        { payload: { shoot_id: s.id, status: "Wrapped" } });
    }
  }

  // The project's Shoot Dates is the NEXT shoot, not the newest one.
  const ahead = shoots.filter((s) => s.status !== "Wrapped" && (s.end || s.start || "") >= todayIso && s.start);
  const firstAhead = ahead.reduce((best, s) => (best === null || s.start < best.start ? s : best), null);
  if (firstAhead && firstAhead.start < start) {
    plan.notes.push(`${name}'s Shoot Dates stays on ${firstAhead.label} `
      + `(${pretty(firstAhead.start)}) — it comes first. Shoot Wrap moves `
      + `it on to ${label} when ${firstAhead.label} wraps.`);
  } else {
    add("NOTION", "project-dates", `Set ${name}'s Shoot Dates to ${when} (the Shoots rows keep the history)`,
      { payload: { project_id: pid, start, end } });
  }
  // A project in Post stays in Post (his call, 2026-10-19): Add Shoot never changes the stage.
  // Its Shoot Dates move to the new shoot as for any project: they are the next shoot's.
  if (project.status === "Post") {
    plan.notes.push(`${name} stays in Post — adding a shoot never changes its stage.`);
  }

  // ── DRIVE ────────────────────────────────────────────────────────────────
  const dp = await drive();
  plan.drive = dp;
  if (!dp.ok) {
    plan.problems.push(`Google Drive: ${dp.why}`);
  } else if (!dp.project_folder) {
    add("DRIVE", "say", "No Drive folder found for this project — no shoot folders made");
  } else {
    // The Mac names a folder by its place in the project (`2-logistics/shoot-3`),
    // in the filing rules' spelling of the section.
    const top = dp.project_folder;
    const rel = (key) => {
      const parts = key.slice(top.length + 1).split("/");
      const sec = SHOOT_SECTIONS.find((s) => s.toLowerCase() === parts[0].toLowerCase());
      if (sec) parts[0] = sec;
      return parts.join("/");
    };
    const subsOf = (key) => dp.steps.filter((s) => s.parent === key).map((s) => s.name);
    for (const s of dp.steps) {
      const isTop = s.parent.split("/").length === 2 && /^shoot-\d+$/.test(s.name);
      if (!isTop) continue;
      const subs = subsOf(s.key);
      const firstOne = firstTime && s.name === "shoot-1";
      add("DRIVE", "mkdir", `${rel(s.key)}/` + (subs.length ? ` with ${subs.join(", ")}` : "")
        + (firstOne ? " — empty; existing files stay where they are" : ""), { payload: { key: s.key } });
      for (const sub of dp.steps.filter((x) => x.parent === s.key)) {
        plan.steps.push({ kind: "mkdir", detail: `${rel(sub.key)}/`, system: "DRIVE", payload: { key: sub.key } });
      }
    }
    for (const note of dp.notes) {
      const m = /^(.+?)\/(shoot-\d+)\/ is already there\.$/.exec(note);
      if (m) {
        const sec = SHOOT_SECTIONS.find((x) => x.toLowerCase() === m[1].toLowerCase()) || m[1];
        plan.notes.push(`${sec}/${m[2]}/ is already there.`);
      } else if (/older folder layout/.test(note)) {
        add("DRIVE", "say", note);
      }
    }
  }

  // ── SHOTLISTER ───────────────────────────────────────────────────────────
  const film = ctx.film || {};
  const scenes = (Array.isArray(f.new_scenes) ? f.new_scenes : []).filter((s) => strip(s));
  const picks = Array.isArray(f.pickups) ? f.pickups : [];
  if (!film.ok) {
    add("SHOTLISTER", "say", "No Shotlister film on this project — nothing to add");
  } else {
    const existing = (film.sections || []).filter((t) => strip(t).toLowerCase() === sectionName.toLowerCase());
    const door = ctx.shotlister_door;
    const sceneLine = `add scene${scenes.length > 1 ? "s " : " "}${scenes.map((s) => `“${s}”`).join(", ")} to the section “${sectionName}”`;
    if (door && ctx.days_follow) {
      add("SHOTLISTER", "shotlister",
        `In “${film.title}”: save a version “Before ${label} setup” and add a day on ${start} named “${label}”, `
        + `belonging to ${label}`
        + (picks.length ? `, and put scene${picks.length > 1 ? "s " : " "}${picks.map(pyStr).join(", ")} on it` : ""),
        { payload: { relay: door.relay, shoot_key: "shoot-new", body: { date: start, name: label,
          pickups: picks.map(pyStr), version: `Before ${label} setup` } } });
      if (scenes.length) {
        add("SHOTLISTER", "manual", `Do this in Shotlister, in “${film.title}” — the console's door adds `
          + `days, not scenes: add scene${scenes.length > 1 ? "s " : " "}${scenes.map((s) => `“${s}”`).join(", ")} to ${label}`);
      }
    } else if (door) {
      add("SHOTLISTER", "shotlister",
        `In “${film.title}”: save a version “Before ${label} setup”, add the section `
        + `“${sectionName}” and a day on ${start} named “${label}”`
        + (picks.length ? `, and put scene${picks.length > 1 ? "s " : " "}${picks.map(pyStr).join(", ")} on it` : ""),
        { payload: { relay: door.relay, body: { date: start, name: label, section: sectionName,
          pickups: picks.map(pyStr), version: `Before ${label} setup` } } });
      if (scenes.length) {
        add("SHOTLISTER", "manual", `Do this in Shotlister, in “${film.title}” — the console's door adds `
          + `sections and days, not scenes: ${sceneLine}`);
      }
    } else {
      const lines = [`save a version “Before ${label} setup”`,
        existing.length ? `use the section “${sectionName}” that is already there` : `add a section “${sectionName}”`,
        `add a day on ${start} named “${label}”`];
      if (scenes.length) lines.push(sceneLine);
      if (picks.length) lines.push(`put scene${picks.length > 1 ? "s " : " "}${picks.map(pyStr).join(", ")} on that day (pickups)`);
      const because = ctx.shotlister_why || "the console can't write a film yet";
      add("SHOTLISTER", "manual", `Do this in Shotlister, in “${film.title}” — ${because}: ${lines.join("; ")}`);
    }
  }

  // ── PORTAL ───────────────────────────────────────────────────────────────
  if (ctx.portal) {
    add("PORTAL", "portal", "Update the portal from Notion, after the Notion steps "
      + "(Shotlister's hub/refresh.py)");
  } else {
    add("PORTAL", "say", "No portal page for this project — nothing to update");
  }
  return plan;
}

/**
 * backend._shotlister_preview — the film's half in Shotlister's own words:
 * its door asked with `preview` (which writes nothing), its steps in place of
 * the console's guess. A refusal stops the whole press.
 */
export async function shotlisterPreview(deps, plan) {
  const steps = plan.groups.SHOTLISTER || [];
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    if (step.kind !== "shotlister") continue;
    const got = await deps.door.shoot(step.payload.relay, step.payload.body, true);
    if (got.status === 422) { plan.problems.push(`Shotlister won't set it up: ${got.trouble}`); continue; }
    if (got.trouble) {
      plan.notes.push(`Couldn't ask Shotlister for its preview (${got.trouble}) — it will be asked again when you press Create.`);
      continue;
    }
    const lines = got.steps || [];
    if (lines.length) {
      step.detail = lines[0];
      const extra = lines.slice(1).map((line) => ({ kind: "say", detail: line, system: "SHOTLISTER", payload: "" }));
      steps.splice(i + 1, 0, ...extra);
      i += extra.length;
    }
  }
}

/** backend.plan_new_shoot — the preview, every step by system. Writes nothing. */
export async function planAnswer(deps, name, form, opts = {}) {
  let plan;
  try {
    const ctx = opts.ctx || await shootsCtx(deps, name);
    plan = await planNewShoot(deps, ctx, form || {});
    if (opts.mode) holdBack(plan, opts.mode);
    await shotlisterPreview(deps, plan);
  } catch (e) {
    if (notionOut(e)) throw e;
    return { ok: false, problems: [str((e && e.message) || e)], notes: [], groups: [], can_run: false };
  }
  return {
    ok: true,
    title: (plan.shoot || {}).title || "",
    label: (plan.shoot || {}).label || "",
    groups: SYSTEMS.filter((s) => plan.groups[s].length).map((s) => ({ system: s, steps: plan.groups[s].map((x) => x.detail) })),
    problems: plan.problems, notes: plan.notes,
    changes: plan.changes, changes_written: plan.changes_written,
    can_run: !plan.problems.length && Boolean(plan.steps.length),
    ...(opts.mode === "down" ? { notion_down: true } : {}),
  };
}

// ── Notion unreachable (the connector's add_shoot, 2026-10-19) ───────────────

/** Whether an error is Notion being out of reach, not a fault in the ask. */
export function notionOut(e) {
  if (isHandoff(e)) return true;
  const said = str(e && e.message);
  return /^Notion: /.test(said) || (e instanceof TypeError && /fetch/i.test(said));
}

export const NOTION_WAITS = "Notion row waits for Notion to be reconnected — the shoot, its crew and its spec sheet are made then, on their own";

/**
 * A run that holds steps back. `down`: Notion cannot be reached, so only the
 * Drive folders are made now; the Notion rows, the Studio day (which belongs
 * to the shoot's Notion row) and the portal refresh wait. The catch-up later
 * is an ordinary run of the same form (the Drive folders are then already
 * there, which is not an error). The preview says so in the same groups.
 */
export function holdBack(plan, mode) {
  const held = (system) => mode === "down" && system !== "DRIVE";
  const note = {
    NOTION: NOTION_WAITS,
    SHOTLISTER: "Studio day waits for the Notion row — made when Notion is reconnected",
    PORTAL: "Portal page follows once Notion is back",
  };
  const kept = [];
  const said = new Set();
  for (const step of plan.steps) {
    if (!held(step.system)) { kept.push(step); continue; }
    if (step.kind === "manual" || step.kind === "say") { kept.push(step); continue; }
    if (!said.has(step.system)) {
      said.add(step.system);
      kept.push({ kind: "say", detail: note[step.system] || NOTION_WAITS, system: step.system, payload: "" });
    }
  }
  plan.steps = kept;
  plan.groups = Object.fromEntries(SYSTEMS.map((system) => [system, kept.filter((x) => x.system === system)]));
  if (mode === "down") plan.notes.push("Notion is not reachable right now. The Drive folders are made at once; the rest is queued and made on its own when Notion is back.");
}

/**
 * The context from the project's record alone — what the plan reads when
 * Notion cannot be asked. The record holds a copy of the Shoots rows (with
 * who is on which, from its crew copy), the crew, the project's stage, dates,
 * colour, type and Drive link; nothing here reads Notion. Shoots waiting for
 * Notion (`waiting`) count as shoots, so a second add numbers after them.
 * No spec sheets: the copy waits.
 */
export async function ctxFromRecord(deps, { name, page, facts, waiting = [] }) {
  const value = (field) => { const one = facts[field]; return isObject(one) ? one.value : undefined; };
  const text = (field) => (typeof value(field) === "string" ? value(field) : "");
  const [dates, datesEnd] = text("shoot_dates").split("/").map((x) => strip(x));
  const people = Array.isArray(value("crew")) ? value("crew").filter(isObject) : [];
  const copy = Array.isArray(value("shoots")) ? value("shoots").filter(isObject) : [];
  const crewIds = (shootId) => people.filter((p) => p.all_shoots || (p.shoots || []).includes(shootId)).map((p) => p.person);
  const rows = copy.map((r) => ({ ...r, crew: crewIds(r.id), spec: r.spec || [], docs: r.docs || [] }));
  for (const w of waiting) {
    rows.push({ id: w.id, title: w.title, label: w.label, n: w.n, start: w.start, end: w.end || "", status: "Upcoming",
      changes: w.form ? str(w.form.changes) : "", crew: Array.isArray(w.form && w.form.crew) ? w.form.crew : [], spec: [], docs: [] });
  }
  const crew = people.map((p) => ({ id: p.person, name: str(p.name), role: (p.roles || []).join(", "), department: "", type: "", company: "",
    location: "", email: "", phone: "", url: "", projects: [bareId(page)], shoots: p.all_shoots ? [] : (p.shoots || []) }));
  const { filmCtx, portal, door, doorWhy } = await worldOf(deps, bareId(page), name);
  return {
    project: { name, page_id: page, status: text("status"), dates: str(dates).slice(0, 10), dates_end: str(datesEnd).slice(0, 10),
      color: text("color"), type: text("type"), shoot_name: text("shoot_name") },
    drive_url: text("drive_folder"),
    shoots: orderShoots(rows),
    sheets: [], last_sheet: null,
    crew, crewById: new Map(crew.map((c) => [c.id, c])),
    project_crew: crew.map((c) => c.id),
    film: filmCtx, portal,
    shotlister_door: door, shotlister_why: doorWhy,
    ...(deps.daysFollow && (await deps.daysFollow()) ? { days_follow: true } : {}),
  };
}

// ── a file's Drive copy (shoots.drive_copy) ──────────────────────────────────

/**
 * A Drive link to the file of this name in the project's folder, or "" —
 * looked for in `3-post`, then `1-creative`, `2-logistics`, then anywhere in
 * the project, by name without regard to case, as the Mac's mounted folder
 * finds it. `plan` is the Drive half's plan (it knows the project's folder).
 */
export async function driveCopy(deps, plan, filename) {
  if (!plan || !plan.ok || !plan.project_folder || !filename) return "";
  return await deps.drive.copy(plan.ids[plan.project_folder], filename);
}

/**
 * The walk behind `deps.drive.copy`, over a Drive `{list}`: each root in the
 * Mac's order, files of a folder before its folders, by name. Remembered per
 * project folder for one ask, and bounded (`cap` folders) so a folder of
 * thousands of stills cannot run the worker out of calls.
 */
export function copyFinder(api, { cap = 400 } = {}) {
  const listed = new Map();
  let lists = 0;
  const list = async (id) => {
    if (!listed.has(id)) {
      if (lists >= cap) throw new Error("too many folders");
      lists += 1;
      listed.set(id, await api.list(id));
    }
    return listed.get(id);
  };
  const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  async function walk(id, want) {
    const kids = [...(await list(id))].sort(byName);
    for (const k of kids) if (!k.folder && !k.shortcut && k.name.toLowerCase() === want) return k.id;
    for (const k of kids) {
      if (!k.folder) continue;
      const hit = await walk(k.id, want);
      if (hit) return hit;
    }
    return "";
  }
  return async (folderId, filename) => {
    if (!folderId || !filename) return "";
    const want = String(filename).toLowerCase();
    try {
      const top = await list(folderId);
      for (const root of ["3-post", "1-creative", "2-logistics", ""]) {
        const base = root ? top.find((k) => k.folder && k.name.toLowerCase() === root) : { id: folderId };
        if (!base) continue;
        const hit = await walk(base.id, want);
        if (hit) return `https://drive.google.com/file/d/${hit}/view`;
      }
    } catch {
      return "";
    }
    return "";
  };
}

// ── writing (shoots.py) ──────────────────────────────────────────────────────

/** shoots.find_crew_by_name — fresh. */
async function findCrewByName(n, name) {
  const want = strip(name).toLowerCase();
  for (const row of await allCrew(n)) if (strip(row.name).toLowerCase() === want) return row;
  return null;
}

/** shoots.create_crew — a newcomer's Crew row, or the one already there linked. */
export async function createCrew(n, { name, project_id, role = "", department = "", email = "", phone = "" }) {
  const found = await findCrewByName(n, name);
  if (found) {
    if (!found.projects.includes(bareId(project_id))) {
      const page = await n.get(`pages/${found.id}`);
      const have = ((((page.properties || {}).Projects || {}).relation) || []).map((r) => ({ id: r.id }));
      await n.patch(`pages/${found.id}`, { properties: { Projects: { relation: [...have, { id: project_id }] } } });
    }
    return { id: found.id, reused: true };
  }
  const props = {
    Name: { title: rich(strip(name)) },
    Type: { select: { name: "Person" } },
    Projects: { relation: [{ id: project_id }] },
  };
  const roles = str(role).split(",").map((r) => r.trim()).filter(Boolean);
  if (roles.length) props.Role = { multi_select: roles.map((r) => ({ name: r })) };
  if (department) props.Department = { select: { name: department } };
  if (strip(email)) props.Email = { email: strip(email) };
  if (strip(phone)) props.Phone = { phone_number: strip(phone) };
  const page = await n.post("pages", { parent: parentOf(CREW), icon: PERSON_ICON, properties: props });
  return { id: page.id, reused: false };
}

/** shoots.create_shoot_row — reuses a row with the same title. */
export async function createShootRow(n, { title, project_id, start, end = "", status = "Upcoming", crew = [], section = "", changes = "", color = "" }) {
  for (const s of await projectShoots(n, project_id)) {
    if (strip(s.title).toLowerCase() === strip(title).toLowerCase()) return { id: s.id, url: s.url, reused: true };
  }
  const props = {
    Shoot: { title: rich(title) },
    Project: { relation: [{ id: project_id }] },
    Status: { select: { name: status } },
  };
  if (start) props.Dates = { date: end && end !== start ? { start, end } : { start } };
  if (crew && crew.length) props.Crew = { relation: crew.map((id) => ({ id })) };
  if (section) props["Shot List Section"] = { rich_text: rich(section) };
  if (changes) props["What Changes"] = { rich_text: rich(changes) };
  const page = await n.post("pages", { parent: parentOf(SHOOTS), icon: calendarIcon(color), properties: props });
  return { id: page.id, url: page.url || "", reused: false };
}

const setStatus = (n, id, status) => n.patch(`pages/${id}`, { properties: { Status: { select: { name: status } } } });

/** shoots.set_project_dates. */
async function setProjectDates(n, projectId, start, end = "") {
  await n.patch(`pages/${projectId}`, { properties: { "Shoot Dates": { date: end && end !== start ? { start, end } : { start } } } });
}

/** shoots.retitle_sheet — the project's sheet becomes Shoot 1's. */
async function retitleSheet(n, sheetId, title, shootId) {
  await n.patch(`pages/${sheetId}`, { properties: { Title: { title: rich(title) }, Shoot: { relation: [{ id: shootId }] } } });
}

/**
 * shoots._Files — carries one file across: re-uploaded when Notion allows,
 * else linked to its Drive copy, else written down as left behind.
 */
class Files {
  constructor(deps, drivePlan) {
    this.deps = deps;
    this.drivePlan = drivePlan;
    this.linked = []; this.left = []; this.copied = [];
    this.done = new Map();
  }

  async carry(name, url) {
    const nm = name || nameOfPath(str(url).split("?")[0]);
    if (this.done.has(nm)) return this.done.get(nm);
    let out = null;
    if (UPLOAD_OK.has(suffixOf(nm).toLowerCase())) {
      try {
        const data = await this.deps.download(url);
        if (data.byteLength <= UPLOAD_CAP) {
          out = { name: nm, type: "file_upload", file_upload: { id: await uploadFile(this.deps, nm, data) } };
          this.copied.push(nm);
        }
      } catch {
        out = null;      // said in the Mac's log only; the Drive copy is tried next
      }
    }
    if (out === null) {
      const link = await driveCopy(this.deps, this.drivePlan, nm);
      if (link) {
        out = { name: nm, type: "external", external: { url: link } };
        this.linked.push(nm);
      } else {
        this.left.push(nm);
      }
    }
    this.done.set(nm, out);
    return out;
  }
}

/** shoots.upload_file — one file into Notion, its upload id back. */
async function uploadFile(deps, name, data) {
  const ctype = mimeOf(name);
  const up = await deps.n.post("file_uploads", { filename: name, content_type: ctype });
  const got = await deps.upload(up.id, name, ctype, data);
  if (!got || got.status !== "uploaded") throw new Error(`Notion did not take ${name}`);
  return up.id;
}

/** shoots._clean_rich — rich text as the API takes it back. */
export function cleanRich(list) {
  const out = [];
  for (const rt of list || []) {
    const kind = rt.type;
    const ann = rt.annotations || {};
    if (kind === "text") {
      out.push({ type: "text", text: { content: rt.text.content, link: rt.text.link === undefined ? null : rt.text.link }, annotations: ann });
    } else if (kind === "equation") {
      out.push({ type: "equation", equation: rt.equation, annotations: ann });
    } else if (kind === "mention" && ["page", "database", "date", "user"].includes((rt.mention || {}).type)) {
      const m = rt.mention;
      out.push({ type: "mention", mention: { [m.type]: m[m.type] }, annotations: ann });
    } else {
      const said = rt.plain_text || "";
      if (said) out.push({ type: "text", text: { content: said, link: rt.href ? { url: rt.href } : null }, annotations: ann });
    }
  }
  return out;
}

const TEXT_BLOCKS = new Set(["paragraph", "heading_1", "heading_2", "heading_3", "bulleted_list_item",
  "numbered_list_item", "to_do", "toggle", "quote", "callout", "code"]);
const MEDIA_BLOCKS = new Set(["file", "image", "pdf", "video", "audio"]);

async function children(n, blockId) {
  const out = [];
  let cursor;
  do {
    const got = await n.get(`blocks/${blockId}/children?page_size=100${cursor ? `&start_cursor=${cursor}` : ""}`);
    out.push(...(got.results || []));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/** shoots._block_payload — one block as the API takes it back, or null. */
async function blockPayload(n, block, files, prevN, skipped) {
  const kind = block.type;
  const body = block[kind] || {};
  if (TEXT_BLOCKS.has(kind)) {
    const made = { rich_text: cleanRich(body.rich_text) };
    if (kind.startsWith("heading_")) {
      const said = (body.rich_text || []).map((rt) => rt.plain_text || "").join("");
      const honest = carriedHeading(said, prevN);
      if (honest !== null) {
        const ann = (made.rich_text.length ? made.rich_text[0].annotations : {}) || {};
        made.rich_text = [{ type: "text", text: { content: honest }, annotations: ann }];
      }
      if (body.is_toggleable) made.is_toggleable = true;
    }
    if ("color" in body) made.color = body.color;
    if (kind === "to_do") made.checked = Boolean(body.checked);
    if (kind === "code") {
      made.language = body.language || "plain text";
      made.caption = cleanRich(body.caption);
    }
    if (kind === "callout") {
      const icon = body.icon || {};
      if (icon.type === "emoji" || icon.type === "external") made.icon = icon;
    }
    return { type: kind, [kind]: made };
  }
  if (MEDIA_BLOCKS.has(kind)) {
    const src = body.type;
    const caption = cleanRich(body.caption);
    if (src === "external") return { type: kind, [kind]: { type: "external", external: body.external, caption } };
    if (src === "file") {
      const name = body.name || nameOfPath(str(body.file.url).split("?")[0]);
      const carried = await files.carry(name, body.file.url);
      if (carried === null) return null;
      const inner = Object.fromEntries(Object.entries(carried).filter(([k]) => k !== "name"));
      if (kind === "file") inner.name = name;
      inner.caption = caption;
      // An image can only hold an image; a linked LUT goes in a file block.
      const outKind = carried.type === "file_upload" || kind === "file" ? kind : "file";
      if (outKind === "file") inner.name = name;
      return { type: outKind, [outKind]: inner };
    }
    return null;
  }
  if (kind === "divider") return { type: "divider", divider: {} };
  if (kind === "bookmark" || kind === "embed") return { type: kind, [kind]: { url: body.url || "", caption: cleanRich(body.caption) } };
  if (kind === "equation") return { type: "equation", equation: { expression: body.expression || "" } };
  if (kind === "link_to_page") return { type: "link_to_page", link_to_page: body };
  if (kind === "table") {
    const rows = [];
    for (const row of await children(n, block.id)) {
      if (row.type === "table_row") rows.push({ type: "table_row", table_row: { cells: row.table_row.cells.map(cleanRich) } });
    }
    return { type: "table", table: { table_width: "table_width" in body ? body.table_width : 1, has_column_header: Boolean(body.has_column_header),
      has_row_header: Boolean(body.has_row_header), children: rows } };
  }
  skipped.push(kind.replace(/_/g, " "));
  return null;
}

/** shoots._copy_children — src's blocks appended to dst, in order, nesting kept. */
async function copyChildren(n, srcId, dstId, files, prevN, skipped, depth = 0) {
  const batch = [];
  const flush = async () => {
    if (batch.length) {
      await n.patch(`blocks/${dstId}/children`, { children: [...batch] });
      batch.length = 0;
    }
  };
  for (const block of await children(n, srcId)) {
    const payload = await blockPayload(n, block, files, prevN, skipped);
    if (payload === null) continue;
    const nests = block.has_children && block.type !== "table" && depth < 3;
    if (!nests) {
      batch.push(payload);
      if (batch.length >= 90) await flush();
      continue;
    }
    await flush();
    const made = await n.patch(`blocks/${dstId}/children`, { children: [payload] });
    await copyChildren(n, block.id, made.results[0].id, files, prevN, skipped, depth + 1);
  }
  await flush();
}

const SKIP_PROPS = new Set(["created_time", "created_by", "last_edited_time", "last_edited_by",
  "formula", "rollup", "unique_id", "verification", "button"]);

/** shoots.copy_spec_sheet — a new sheet for this shoot from the last one. */
export async function copySpecSheet(deps, srcId, { title, shootId, edits = {}, prevN = 1, drivePlan = null }) {
  const { n } = deps;
  const src = await n.get(`pages/${srcId}`);
  const projects = ((((src.properties || {}).Projects || {}).relation) || []).map((r) => r.id);
  for (const page of (projects.length ? await specSheets(n, projects[0]) : [])) {
    if (strip(plainTitle(page.properties)).toLowerCase() === strip(title).toLowerCase()) {
      return { id: page.id, url: page.url || "", reused: true, linked: [], left: [], copied: [], skipped: [] };
    }
  }
  const files = new Files(deps, drivePlan);
  const props = {};
  for (const [name, field] of Object.entries(src.properties || {})) {
    const kind = field.type;
    if (SKIP_PROPS.has(kind)) continue;
    if (kind === "title") props[name] = { title: rich(title) };
    else if (kind === "rich_text") props[name] = { rich_text: cleanRich(field.rich_text) };
    else if (["number", "url", "email", "phone_number", "checkbox"].includes(kind)) {
      if (field[kind] !== null && field[kind] !== undefined) props[name] = { [kind]: field[kind] };
    } else if (kind === "select") {
      if (field.select) props[name] = { select: { name: field.select.name } };
    } else if (kind === "multi_select") {
      props[name] = { multi_select: field.multi_select.map((o) => ({ name: o.name })) };
    } else if (kind === "date") {
      if (field.date) props[name] = { date: Object.fromEntries(Object.entries(field.date).filter(([, v]) => v)) };
    } else if (kind === "relation") {
      if (name === "Shoot") props[name] = { relation: [{ id: shootId }] };
      else props[name] = { relation: (await relationAll(n, src, name)).map((id) => ({ id })) };
    } else if (kind === "files") {
      const carried = [];
      for (const one of field.files || []) {
        if (one.type === "external") carried.push({ name: one.name || "", type: "external", external: one.external });
        else if (one.type === "file") {
          const got = await files.carry(one.name || "", one.file.url);
          if (got) carried.push(got);
        }
      }
      props[name] = { files: carried };
    }
  }
  for (const [name, value] of Object.entries(edits || {})) {
    const kind = ((src.properties || {})[name] || {}).type;
    if (kind === "rich_text") props[name] = { rich_text: rich(value) };
    else if (kind === "multi_select") props[name] = { multi_select: pillsOf(value).map((one) => ({ name: one })) };
  }
  const payload = { parent: parentOf(SPECS), properties: props };
  const icon = src.icon || {};
  if (icon.type === "emoji" || icon.type === "external") payload.icon = icon;
  else if (icon.type === "icon") {
    const named = icon.icon || {};
    payload.icon = { type: "external", external: { url: `https://www.notion.so/icons/${named.name}_${named.color || "gray"}.svg` } };
  }
  const page = await n.post("pages", payload);
  const skipped = [];
  await copyChildren(n, srcId, page.id, files, prevN, skipped);
  return { id: page.id, url: page.url || "", reused: false, linked: files.linked, left: files.left,
    copied: files.copied, skipped: [...new Set(skipped)].sort() };
}

// ── doing the plan (shoots.execute) ──────────────────────────────────────────

class Skip extends Error {}

/** The Mac's words for a Notion refusal: its message, after "Notion said:". */
function notionWords(e) {
  const m = /^Notion: [^\s—]+(?: — ([\s\S]*))?$/.exec(str(e && e.message));
  return m ? (m[1] || "") : null;
}

/** The step groups the sheet shows, in his words: one line each, ticking off. */
const GROUPS = [
  ["notion", "Shoot in Notion", ["crew-new", "shoot-row", "shoot-status", "project-dates", "project-status"]],
  ["sheet", "Spec sheet", ["sheet-copy", "sheet-retitle", "record-sheet-copy"]],
  ["drive", "Drive folders", ["mkdir"]],
  ["studio", "Studio section", ["shotlister"]],
  ["portal", "Portal page", ["portal"]],
];
export const groupOf = (kind) => (GROUPS.find((g) => g[2].includes(kind)) || [])[0] || "";

/**
 * Carry out the plan — shoots.execute's work, now in parallel where it is
 * safe (2026-10-19, "Add Shoot" speed). The Mac did the steps one after
 * another; each now starts the moment what it needs has been made:
 *
 * - a shoot row waits for the newcomers' Crew rows it lists;
 * - the spec sheet, the Studio day and the retitle wait for the shoot row
 *   they belong to;
 * - the Drive folders need nothing, and are made beside the Notion steps;
 * - the portal page waits for every Notion and Studio step (it reads them).
 *
 * The report is word for word the Mac's, and in the plan's order whatever
 * order the steps finished in. `deps.serial` runs them one at a time, the old
 * way (for timing, and as a way back). `deps.progress(groups)` is told as each
 * group starts and ends; `deps.out` is handed `{ steps, timings, failed }`.
 */
export async function execute(deps, plan) {
  const { n } = deps;
  const made = new Map();
  const steps = plan.steps;
  const saidBy = steps.map(() => []);      // each step's words, read back in the plan's order
  const result = steps.map(() => null);          // per step: {ok, why?} once finished
  const started = steps.map(() => 0);
  const timings = [];
  const need = (key) => {
    if (!made.has(key)) {
      const what = { "shoot-new": "the new shoot's row", "shoot-1": "Shoot 1's row" }[key]
        || (key.startsWith("crew-") ? "a newcomer's Crew row" : key);
      throw new Skip(`skipped — ${what} was not made`);
    }
    return made.get(key);
  };
  // The Drive half is made in one go, when its first step comes up.
  let driveRun = null;
  const makeDrive = async () => (driveRun ||= deps.drive.make(plan.drive));

  async function doStep(step, i) {
    const said = saidBy[i];
    const p = isObject(step.payload) ? step.payload : {};
    if (step.kind === "crew-new") {
      const got = await createCrew(n, p);
      made.set(p.key, got.id);
      if (got.reused) said.push(`${p.name} was already in Crew — linked that row`);
    } else if (step.kind === "shoot-row") {
      const crew = [...(p.crew || []), ...(p.crew_keys || []).map(need)];
      const got = await createShootRow(n, { ...p, crew });
      made.set(p.key, got.id);
      if (got.reused) said.push(`${p.title} was already in Notion — used that row`);
    } else if (step.kind === "sheet-retitle") {
      await retitleSheet(n, p.sheet_id, p.title, need(p.shoot_key));
    } else if (step.kind === "sheet-copy") {
      const got = await copySpecSheet(deps, p.src_id, { title: p.title, shootId: need(p.shoot_key), edits: p.edits,
        prevN: p.prev_n || 1, drivePlan: plan.drive });
      made.set("sheet", got.id);
      if (got.reused) said.push(`${p.title} was already there — left as it is`);
      for (const nm of got.linked) said.push(`${nm} is linked to its Drive copy (Notion won't let an app upload that kind of file)`);
      for (const nm of got.left) said.push(`⚠ ${nm} could not be carried over — drag it onto the new sheet from the last one`);
      for (const kind of got.skipped) said.push(`⚠ a ${kind} block on the old sheet was not copied`);
    } else if (step.kind === "shoot-status") {
      await setStatus(n, p.shoot_id, p.status);
    } else if (step.kind === "project-dates") {
      await setProjectDates(n, p.project_id, p.start, p.end || "");
    } else if (step.kind === "project-status") {
      await setStatus(n, p.project_id, p.status);
    } else if (step.kind === "mkdir") {
      const run = await makeDrive();
      const key = p.key;
      if (run.made.includes(key) || run.already.includes(key)) { /* made, or there */ } else {
        const off = run.failed.find((x) => x.key === key);
        throw new Error(off ? off.why : "not made: Google Drive stopped before it");
      }
    } else if (step.kind === "shotlister") {
      // The new shoot's row id, so the day is the shoot's own (piece E).
      const body = p.shoot_key ? { ...p.body, shoot: String(need(p.shoot_key)).replace(/-/g, "") } : p.body;
      const got = await deps.door.shoot(p.relay, body, false);
      if (got.trouble) throw new Error(`Shotlister said: ${got.trouble}`);
      for (const line of got.steps || []) said.push(`Shotlister: ${line}`);
    } else if (step.kind === "portal") {
      if (!deps.refresh) throw new Skip("skipped — nothing to refresh it with");
      const got = await deps.refresh();
      if (!got.ok) throw new Error(got.why || (got.said || []).join("; ") || "the refresh failed");
    } else {
      return false;
    }
    return true;
  }

  // What each step waits for: the steps (by index) that make what it uses.
  const keyIndex = new Map();
  steps.forEach((s, i) => { const p = isObject(s.payload) ? s.payload : {}; if ((s.kind === "crew-new" || s.kind === "shoot-row") && p.key) keyIndex.set(p.key, i); });
  const waitsFor = (step, i) => {
    const p = isObject(step.payload) ? step.payload : {};
    const out = [];
    if (step.kind === "shoot-row") {
      for (const k of p.crew_keys || []) if (keyIndex.has(k)) out.push(keyIndex.get(k));
      // shoot rows are made in order (Shoot 1, then the new one), so Notion's list keeps that order
      for (let j = 0; j < i; j++) if (steps[j].kind === "shoot-row") out.push(j);
    }
    if ((step.kind === "sheet-copy" || step.kind === "sheet-retitle" || step.kind === "shotlister") && p.shoot_key && keyIndex.has(p.shoot_key)) out.push(keyIndex.get(p.shoot_key));
    // The first thing written to Notion is always a new row (a Crew row or the shoot's), as before. If Notion
    // refuses that, nothing else has been written and the whole ask can still go to the Mac.
    if (["project-dates", "project-status", "shoot-status"].includes(step.kind)) steps.forEach((s, j) => { if (s.kind === "shoot-row" || s.kind === "crew-new") out.push(j); });
    if (step.kind === "portal") steps.forEach((s, j) => { if (j !== i && s.kind !== "mkdir" && s.kind !== "portal" && !["manual", "say"].includes(s.kind)) out.push(j); });
    if (deps.serial) for (let j = 0; j < i; j++) out.push(j);
    return out;
  };

  // The groups the sheet shows, each with its steps.
  const groups = GROUPS.map(([id, label, kinds]) => ({ id, label, idx: steps.map((s, i) => (kinds.includes(s.kind) ? i : -1)).filter((i) => i >= 0) }))
    .filter((g) => g.idx.length);
  const shown = () => groups.map((g) => {
    const rs = g.idx.map((i) => result[i]);
    const failed = rs.find((r) => r && !r.ok);
    const state = failed ? "fail" : rs.every((r) => r && r.ok) ? "done" : g.idx.some((i) => started[i]) ? "run" : "wait";
    return { id: g.id, label: g.label, state, ...(failed ? { why: failed.why } : {}) };
  });
  let lastShown = "";
  const tell = async () => {
    if (typeof deps.progress !== "function") return;
    const now = shown();
    const key = JSON.stringify(now);
    if (key === lastShown) return;
    lastShown = key;
    try { await deps.progress(now); } catch { /* a line that can't be kept never stops the shoot */ }
  };

  const tasks = new Array(steps.length);
  const run = (i) => (tasks[i] ||= (async () => {
    const step = steps[i];
    const before = waitsFor(step, i);
    await Promise.all(before.map((j) => run(j)));
    try {
      if (step.kind === "manual" || step.kind === "say") { result[i] = { ok: true, skipped: true }; return; }
      started[i] = Date.now();
      await tell();
      const did = await doStep(step, i);
      if (did === false) { result[i] = { ok: true, skipped: true }; return; }
      result[i] = { ok: true };
    } catch (e) {
      // Notion said no before anything was written: the Mac's to do instead.
      // (The Drive may have been made beside it; the Mac finds those folders already there.)
      if (isHandoff(e) && !steps.some((s, j) => s.system === "NOTION" && result[j] && result[j].ok)) throw e;
      if (e instanceof Skip) result[i] = { ok: false, why: `${step.detail} — ${e.message}` };
      else {
        const words2 = notionWords(e);
        result[i] = { ok: false, why: words2 !== null ? `${step.detail} — Notion said: ${words2}` : `${step.detail} — ${str((e && e.message) || e)}` };
      }
    } finally {
      if (started[i]) timings.push({ kind: step.kind, detail: step.detail, ms: Date.now() - started[i] });
      await tell();
    }
  })());
  await tell();
  const settled = await Promise.allSettled(steps.map((_, i) => run(i)));
  const rejected = settled.find((r) => r.status === "rejected");
  if (rejected) throw rejected.reason;

  const said = saidBy.flat();
  const done = [], failed = [];
  steps.forEach((step, i) => {
    const r = result[i];
    if (!r || r.skipped) return;
    if (r.ok) done.push(step.detail); else failed.push(r.why);
  });
  const lines = [`${plan.project}: ${done.length} step${done.length === 1 ? "" : "s"} done`];
  for (const s of said) lines.push(`  · ${s}`);
  for (const f of failed) lines.push(`  ⚠ ${f}`);
  const todo = plan.steps.filter((s) => s.kind === "manual").map((s) => s.detail);
  if (todo.length) {
    lines.push("Still to do by hand:");
    for (const t of todo) lines.push(`  → ${t}`);
  }
  if (deps.out) Object.assign(deps.out, { steps: shown(), timings, failed, said });
  return lines.join("\n");
}

/** backend.run_new_shoot — re-planned from scratch at this moment, then done. */
export async function runAnswer(deps, name, form, opts = {}) {
  let plan;
  try {
    const ctx = opts.ctx || await shootsCtx(deps, name);
    plan = await planNewShoot(deps, ctx, form || {});
    if (opts.mode) holdBack(plan, opts.mode);
    await shotlisterPreview(deps, plan);
  } catch (e) {
    if (notionOut(e)) throw e;
    return { ok: false, report: `Not run — ${str((e && e.message) || e)}` };
  }
  // The preview's extra lines were for reading; the one shotlister step does the work.
  plan.steps = plan.steps.filter((s) => !(s.system === "SHOTLISTER" && s.kind === "say"));
  if (plan.problems.length) return { ok: false, report: `Not run — ${plan.problems.join(" ")}` };
  // `serial_test` runs the steps one at a time, the old way: for timing, and a way back.
  const out = {};
  const run = Object.assign(Object.create(deps), { out, serial: deps.serial || (form && form.serial_test === true) });
  const report = await execute(run, plan);
  // The shared activity log, word for word the Mac's line (backend.run_new_shoot):
  // a New Shoot run here (the phone, or a Mac routed here) shows in every console.
  if (typeof deps.logActivity === "function") {
    await deps.logActivity({ kind: "new-shoot", desc: `${name}: ${(plan.shoot || {}).label || ""} set up`, undo: null });
  }
  // The steps and their times ride beside the Mac's report (the phone and the
  // desk read `report`; the new sheet reads the rest).
  return { ok: true, report, steps: out.steps || [], failed: out.failed || [], timings: out.timings || [], label: (plan.shoot || {}).label || "",
    ...(plan.shoot ? { shoot: plan.shoot } : {}), changes: plan.changes };
}

export { todayHere as today };
