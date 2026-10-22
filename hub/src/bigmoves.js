/**
 * **The big moves, done by the server** (stage 5 step 7): Wrap, Archive,
 * Move Drive, Rename, Turn Off, Delete, and Prepare Showcase — from any
 * device, one door each, each with a `look` that writes nothing and a `run`.
 *
 * His rules (2026-10-15) are the spec here, over the older Mac code:
 * - **Wrap** parks a project in Post: the shoot it wraps is marked Wrapped; a
 *   later shoot still to come keeps the status Active and moves the Shoot
 *   Dates on; otherwise Post. Nothing else — no stills, no showcase.
 * - **Prepare Showcase** (the Released sheet's last step, 2026-10-17) makes
 *   the showcase from the selects he picked (the record's `selects`, the one
 *   source — showcaseplan.js): the folder, its marker, `stills/`, `select-stills/`
 *   and `credits.txt` (at its root) here, and leaves the pictures (the gallery .webp of a
 *   pick from another folder, every pick's numbered copy in `select-stills/`)
 *   to a Mac (`showcase-stills`). Never `website/` (his, by hand). Only adds;
 *   a file already there is kept, and a select no longer picked moves into
 *   `select-stills/z-archive/` (nothing is deleted).
 * - **Archive removes nothing**: the Drive folder moves to its section's
 *   archive year (`projects/z-archived/<year>/`, `gigs/z-archive/<year>/`, as
 *   `.filing-rules.md` says), the showcase to
 *   `project-showcases/zz-archived/<year>/`, the status to Archived. The
 *   portal, the Studio side and the footage stay exactly as they are.
 * - **Move Drive** is the Google Drive folder only, by the Drive's own move,
 *   so its id (and Notion's link) is kept.
 * - **Rename** renames the Notion title, the record, the Drive folder and the
 *   showcase (ids kept), all of it or none of it. Media folders are never
 *   renamed; the record remembers the old folder name per drive
 *   (`media_names`) so the drive light still finds the footage.
 * - **Turn Off** covers the showcase (moved into
 *   `project-showcases/zz-archived/<year>/`, never a trash) and the website
 *   link only.
 * - **Delete** is a true delete everywhere except media drives — backed up
 *   first, so it can be undone for 30 days.
 * - **Media drives are never touched.** Nothing here names a media drive; the only
 *   Mac work a move leaves is a showcase's web stills, telling Studio where
 *   its Drive folder went, and the Drive bridge's list.
 *
 * **One move at a time** per project: `moving: {kind, since, move_id}` on
 * the record (New Shoot refuses too). **Every run is kept** under
 * `s/bigmoves/moves/<id>.json` with what undo needs, and logged in the shared
 * history with `undo: {type: "bigmove", move_id}`. Undo lasts 30 days, cancels
 * the move's waiting Mac jobs first, and waits for a running one.
 *
 * **The switch** `s/bigmoves.json`: `{wrap, archive, movedrive, rename,
 * turnoff, delete, showcase}` each "off" (the Mac's, as before), "scratch"
 * (only a project whose Drive folder sits in the scratch folder) or "live".
 *
 * Rule: no static import of cloud.js / studio.js (they import this).
 */
import { tombstoneKey } from "./deletedguard.js";
import { keys } from "../../relay/layout.js";
import { notionDown, QUIET as NOTION_WAITS, waitsFor, addWait, dropWaits } from "./notionwaits.js";

export const SWITCH_KEY = "s/bigmoves.json";
export const MOVES = "s/bigmoves/moves/";
export const BACKUPS = "bigmoves/backups/";
export const KINDS = ["wrap", "archive", "movedrive", "rename", "turnoff", "delete", "showcase"];
export const MODES = ["off", "scratch", "live"];
export const METHODS = new Set(["bigmove_look", "bigmove_run", "bigmove_undo"]);
/** Answered on the spot (the router's /now); the rest are held (later.js). */
export const NOW = new Set(["bigmove_look"]);
export const LATER_WRITES = new Set(["bigmove_run", "bigmove_undo"]);
export const UNDO_DAYS = 30;
/** A `moving` lock older than this was left by a run that never finished. */
export const LOCK_STALE_MS = 20 * 60 * 1000;
const DAY_MS = 86400000;

/** The Mac jobs a move can leave (merged into macjobs.js's KINDS). */
export const BIGMOVE_KINDS = {
  // a showcase's pictures from the picked selects, on a Mac's Google Drive mount
  "showcase-stills": { retry_safe: true, needs_default: { mac: "any", tools: ["cwebp"] }, parts: ["stills"], label: "Showcase pictures" },
  // Studio told where its project's Drive folder now is (`--drivefolder`)
  "film-drivefolder": { retry_safe: true, needs_default: { mac: "studio" }, parts: ["studio"], label: "Tell Studio where the folder went" },
  // the Drive bridge's allow-list (`bridge/projects.txt`) following a new folder name
  "bridge-list": { retry_safe: true, needs_default: { mac: "studio" }, parts: ["bridge"], label: "Drive bridge list" },
};

const ID32 = /^[0-9a-f]{32}$/;
const DRIVE_ID = /^[A-Za-z0-9_-]{10,120}$/;
const MOVE_ID = /^mv-[0-9a-f]{16}$/;
const SLUG_OK = /^[a-z0-9][a-z0-9-]*$/;
const IMAGE = /\.(jpe?g|png|tiff?|dpx|exr|heic|webp)$/i;
const SHOWCASE_SUFFIX = "-showcase";
const PROJECTS_SOURCE = "feedface-0000-4000-8000-000000000001";
const SHOOTS_SOURCE = "feedface-0000-4000-8000-000000000002";
const SERVER = "Server";
const MAC = "Needs a Mac";
const STUDIO_MAC = "Needs the Studio Mac";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();
const words = (rich) => (rich || []).map((t) => t.plain_text || (t.text && t.text.content) || "").join("");
const same = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();
const plural = (n, one, many = `${one}s`) => `${n.toLocaleString("en-US")} ${n === 1 ? one : many}`;

/** A refusal in his words: nothing was written. */
export class Refusal extends Error {
  constructor(why, extra = {}) { super(why); Object.assign(this, extra); }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function settingsOf(env) {
  let v = {};
  const got = env && env.BUCKET ? await env.BUCKET.get(SWITCH_KEY) : null;
  if (got) { try { v = await got.json(); } catch { v = {}; } }
  if (!isObject(v)) v = {};
  const out = { at: v.at || null, by: v.by || null };
  for (const k of KINDS) out[k] = MODES.includes(v[k]) ? v[k] : "off";
  if (DRIVE_ID.test(String(v.scratch || ""))) out.scratch = v.scratch;
  return out;
}

export function changedSettings(now, said) {
  const s = isObject(said) ? said : {};
  const out = { ...now, at: new Date().toISOString(), by: String(s.by || "").slice(0, 80) };
  for (const k of KINDS) {
    if (s[k] === undefined) continue;
    if (!MODES.includes(s[k])) return { problem: `${k} is off, scratch or live.` };
    out[k] = s[k];
  }
  if (s.scratch !== undefined) {
    if (s.scratch === null || s.scratch === "") delete out.scratch;
    else if (!DRIVE_ID.test(String(s.scratch))) return { problem: "scratch is a Drive folder id, or null." };
    else out.scratch = s.scratch;
  }
  return out;
}

export async function setSettings(env, said) {
  const next = changedSettings(await settingsOf(env), said);
  if (next.problem) return next;
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(next), { httpMetadata: { contentType: "application/json" } });
  return next;
}

/** Whether any move is answered here (the methods are listed only then). */
export async function anyOn(env) {
  const s = await settingsOf(env);
  return KINDS.some((k) => s[k] !== "off");
}

// ── the world a move works in (fakes in the checks) ─────────────────────────

/**
 * `{env, n, drive, create, jobs, now, by}`: Notion (`cloud.notionOf`), the
 * fenced Drive (`drivemoves.guarded`), the create-only Drive for the showcase
 * folders (`drivewrite.driveApi`), the Mac jobs list, and the clock.
 */
export async function worldOf(env, { write = false, by = "" } = {}) {
  const cloud = await import("./cloud.js");
  const { driveMovesApi } = await import("./drivemoves.js");
  const { driveApi } = await import("./drivewrite.js");
  const drive = await import("./drivefolders.js");
  return {
    env,
    n: cloud.notionOf(env),
    raw: driveMovesApi(env, { write }),
    create: driveApi(env, { write }),
    driveSettings: await drive.settingsOf(env),
    jobs: await jobsList(),
    now: () => new Date(),
    by: String(by || "server").slice(0, 80),
  };
}

/** The Mac jobs list (macjobs.js), as the moves use it. `READY` only while its switch is on. */
async function jobsList() {
  const m = await import("./macjobs.js");
  return { READY: true, addJob: m.addJob, cancelJobs: m.cancelJobs, jobsFor: m.jobsFor, macJobsOn: m.macJobsOn };
}

async function Handoff(why) {
  const { Handoff: H } = await import("./cloud.js");
  return new H(why);
}

// ── reading ──────────────────────────────────────────────────────────────────

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

async function putJson(env, key, value, opts = {}) {
  return env.BUCKET.put(key, JSON.stringify(value), { httpMetadata: { contentType: "application/json" }, ...opts });
}

function titleProp(props) {
  for (const [k, p] of Object.entries(props || {})) if (p && p.type === "title") return k;
  return "Project";
}
function plainTitle(props) {
  for (const p of Object.values(props || {})) if (p && p.type === "title") return words(p.title);
  return "";
}
const selectOf = (props, name) => ((((props || {})[name] || {}).select) || {}).name || "";
const urlOf = (props, name) => (((props || {})[name] || {}).url) || "";
const idFromUrl = (url) => { const m = /\/folders\/([A-Za-z0-9_-]+)/.exec(String(url || "")); return m ? m[1] : ""; };

/** The day on his clock, "YYYY-MM-DD". */
export function today(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Vancouver", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}
/** The year an archive move happens in, on his clock. */
export function yearNow(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Vancouver", year: "numeric" }).format(now);
}
const SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export function pretty(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""));
  return m ? `${SHORT[Number(m[2]) - 1]} ${Number(m[3])}` : "";
}

/** A Shoots row as the rituals read it (`shoots.shoot_of`). */
export function shootOf(page) {
  const props = page.properties || {};
  const title = plainTitle(props);
  let label = title;
  for (const dash of [" — ", " – ", " - "]) {
    const at = title.indexOf(dash);
    if (at >= 0) { label = title.slice(at + dash.length).trim(); break; }
  }
  const num = /\bShoot\s+(\d+)\b/i.exec(title);
  const when = ((props.Dates || {}).date) || {};
  return { id: page.id, title, label: label || title, n: num ? Number(num[1]) : null,
    start: String(when.start || "").slice(0, 10), end: String(when.end || "").slice(0, 10),
    status: selectOf(props, "Status") };
}

/** `rituals.wrap_target`: the shoot just finished, and those still to come. */
export function wrapTarget(shoots, day) {
  const key = (s) => [s.start || "9999", s.n || 0];
  const ordered = [...(shoots || [])].sort((a, b) => {
    const [x, y] = [key(a), key(b)];
    return x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : x[1] - y[1];
  });
  const begun = ordered.filter((s) => s.start && s.start <= day);
  let target = null;
  if (begun.length) target = begun[begun.length - 1];
  else {
    const up = ordered.filter((s) => s.status !== "Wrapped");
    target = up.length ? up[0] : (ordered.length ? ordered[ordered.length - 1] : null);
  }
  if (!target) return { target: null, later: [] };
  const later = ordered.filter((s) => s !== target && s.status !== "Wrapped" && (s.start || "9999") >= (target.start || ""));
  return { target, later };
}

async function queryAll(n, source, body) {
  const out = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${source}/query`, { ...body, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    out.push(...(got.results || []));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

async function shootPages(w, page) {
  return queryAll(w.n, SHOOTS_SOURCE, { filter: { property: "Project", relation: { contains: page } } });
}

// ── the Drive's roots ───────────────────────────────────────────────────────

/** Children named so (exact spelling first, then any case). */
const childNamed = (kids, name) => kids.find((k) => k.name === name) || kids.find((k) => same(k.name, name)) || null;

/**
 * The roots a project's moves work in: the real ones (`drivefolders` roots,
 * and the cinematography folder above `projects`), or the scratch folder's
 * own `projects`, `gigs` and `portfolio/project-showcases` found by name.
 */
async function rootsOf(w, scratch) {
  const api = w.raw;
  if (scratch) {
    const top = scratch;
    const kids = (await api.list(top)).filter((k) => k.folder);
    const projects = childNamed(kids, "projects");
    const gigs = childNamed(kids, "gigs");
    const portfolio = childNamed(kids, "portfolio");
    const showcases = portfolio ? childNamed((await api.list(portfolio.id)).filter((k) => k.folder), "project-showcases") : null;
    return { top, scratch: true, projects: projects && projects.id, gigs: gigs && gigs.id,
      portfolio: portfolio && portfolio.id, showcases: showcases && showcases.id };
  }
  const r = (w.driveSettings && w.driveSettings.roots) || {};
  let top = w.cine || null;
  if (!top && r.projects) {
    const p = await api.get(r.projects);
    top = p && p.parents && p.parents[0];
  }
  let portfolio = null;
  if (r.showcases) {
    const s = await api.get(r.showcases);
    portfolio = s && s.parents && s.parents[0];
  }
  return { top, scratch: false, projects: r.projects || null, gigs: r.gigs || null, portfolio, showcases: r.showcases || null };
}

/** The scratch folder moves may act in: the switch's, else New Project's. */
function scratchOf(w, settings) {
  return (settings && settings.scratch) || (w.driveSettings && w.driveSettings.scratch) || null;
}

/** The fenced Drive for one project's roots. */
async function fencedFor(w, roots) {
  const { guarded } = await import("./drivemoves.js");
  const keep = [roots.projects, roots.gigs, roots.showcases, roots.portfolio];
  return guarded(w.raw, { roots: [roots.top], keep });
}

/** One level down by name, made when missing (only on a run). */
async function folderIn(api, parent, name, { make = false, made = [] } = {}) {
  const hit = childNamed((await api.list(parent)).filter((k) => k.folder), name);
  if (hit) return hit.id;
  if (!make) return null;
  const got = await api.mkdir(parent, name);
  made.push(got.id);
  return got.id;
}

/** The showcase for a slug: live first, then each zz-archived year, newest first. */
async function findShowcase(api, roots, slug, loose) {
  if (!roots.showcases) return null;
  const top = (await api.list(roots.showcases)).filter((k) => k.folder);
  const parents = [{ id: roots.showcases, kids: top, path: "portfolio/project-showcases", year: "" }];
  const zz = childNamed(top, "zz-archived");
  if (zz) {
    const years = (await api.list(zz.id)).filter((k) => k.folder).sort((a, b) => (a.name < b.name ? 1 : -1));
    for (const y of years) parents.push({ id: y.id, kids: (await api.list(y.id)).filter((k) => k.folder), path: `portfolio/project-showcases/zz-archived/${y.name}`, year: y.name });
  }
  for (const p of parents) {
    const hit = childNamed(p.kids, `${slug}${SHOWCASE_SUFFIX}`);
    if (hit) return { id: hit.id, name: hit.name, parent: p.id, path: `${p.path}/${hit.name}`, archived: Boolean(p.year) };
  }
  if (!loose) return null;
  const { looseMatch } = await import("./drivefolders.js");
  for (const p of parents) {
    for (const d of [...p.kids].sort((a, b) => (a.name < b.name ? -1 : 1))) {
      if (!d.name.endsWith(SHOWCASE_SUFFIX)) continue;
      if (looseMatch(d.name.slice(0, -SHOWCASE_SUFFIX.length), loose)) return { id: d.id, name: d.name, parent: p.id, path: `${p.path}/${d.name}`, archived: Boolean(p.year) };
    }
  }
  return null;
}

// ── the project ──────────────────────────────────────────────────────────────

/**
 * Everything a move reads, fresh: the record (by any id the project has —
 * never its name), its Notion page by page id, the Drive folder by the
 * Notion link, where it sits, the showcase. Throws `Refusal`.
 */
export async function projectOf(w, asked, settings, { tombstone = false } = {}) {
  const env = w.env;
  const said = isObject(asked) ? asked : { id: asked };
  const id = bare(said.id || said.page || said.page_id || "");
  if (!ID32.test(id)) throw new Refusal("Say which project (its ID).");
  const { resolveProject, notionOf } = await import("./projectid.js");
  const found = await resolveProject(env, id);
  const key = found.key || id;
  const record = found.record || null;
  if (record && record.deleted && !tombstone) throw new Refusal("This project was deleted.", { deleted: true });
  const page = (record && notionOf(record, key)) || key;
  let notion = null;
  let down = false;       // Notion could not be reached (no key, a refused key, no connection)
  if (!(record && record.kind === "job")) {
    try { notion = await w.n.get(`pages/${page}`); } catch (e) { notion = null; down = notionDown(e); if (!record) throw new Refusal(down ? NOTION_WAITS : "No project by that ID."); }
    if (notion && (notion.in_trash || notion.archived) && !tombstone) notion = null;
  }
  if (!notion && !record) throw new Refusal("No project by that ID.");
  const props = (notion && notion.properties) || {};
  const facts = (record && record.facts) || {};
  const fact = (k) => (isObject(facts[k]) ? facts[k].value : undefined);
  const name = (notion && plainTitle(props)) || fact("title") || (record && record.name) || said.name || "";
  const status = (notion ? selectOf(props, "Status") : "") || fact("status") || (record && record.stage) || "";
  const driveUrl = (notion && urlOf(props, "Drive Folder")) || fact("drive_folder") || "";
  const dates = (((props["Shoot Dates"] || {}).date) || {});
  // With Notion out of reach the record's Shoot Dates stand in ("a/b" or "a").
  const kept = down ? String(fact("shoot_dates") || "").split("/") : [];
  const ctx = {
    key, page: notion ? bare(notion.id) : "", record, notion, props, name, status, driveUrl,
    notionDown: down, pageId: bare(page),
    website: notion ? urlOf(props, "Website") : "",
    dates: down ? { start: String(kept[0] || "").slice(0, 10), end: String(kept[1] || "").slice(0, 10) }
      : { start: String(dates.start || "").slice(0, 10), end: String(dates.end || "").slice(0, 10) },
    titleProp: titleProp(props), folder: null, place: null, scratch: false, roots: null, showcase: null,
  };
  // The Drive folder: by the link Notion holds (its id is the folder's own).
  const linked = idFromUrl(driveUrl);
  const scratch = scratchOf(w, settings);
  if (w.raw && linked) {
    const got = await w.raw.get(linked);
    if (got && got.folder && (!got.trashed || tombstone)) ctx.folder = got;
  }
  if (w.raw && !ctx.folder && name) {
    // No link: the real roots by name, as the Mac finds it (never the scratch).
    const roots = await rootsOf(w, null);
    const { findProjectFolder } = await import("./drivefolders.js");
    const rootsShape = { projects: roots.projects ? { id: roots.projects } : {}, gigs: roots.gigs ? { id: roots.gigs } : {} };
    const hit = await findProjectFolder(w.raw, rootsShape, name, "", { archived: true });
    if (hit) ctx.folder = await w.raw.get(hit.id);
  }
  if (ctx.folder) {
    const { placeOf } = await import("./drivemoves.js");
    const real = await rootsOf(w, null);
    const place = await placeOf(w.raw, ctx.folder.id, [real.top, scratch].filter(Boolean));
    if (place) {
      ctx.place = place;
      ctx.scratch = Boolean(scratch) && place.root === scratch;
      ctx.roots = ctx.scratch ? await rootsOf(w, scratch) : real;
    }
  }
  if (!ctx.roots) ctx.roots = await rootsOf(w, null).catch(() => ({ top: null }));
  ctx.slug = ctx.folder ? ctx.folder.name : (record && record.slug) || "";
  if (w.raw && ctx.roots && ctx.roots.showcases) {
    const { slugify } = await import("./drivefolders.js");
    ctx.showcase = await findShowcase(w.raw, ctx.roots, ctx.slug || slugify(name), slugify(name));
  }
  return ctx;
}

/** The switch's word for this move on this project; throws a Handoff when it is not the server's. */
async function mine(w, settings, kind, ctx) {
  const mode = settings[kind] || "off";
  if (mode === "off") throw await Handoff(`the ${kind} switch is off`);
  if (mode === "scratch" && !ctx.scratch) throw await Handoff(`${kind} is on for the scratch folder only`);
  return mode;
}

function lockOf(record, now = Date.now()) {
  const m = record && isObject(record.moving) ? record.moving : null;
  if (!m) return null;
  if (now - Date.parse(m.since || 0) > LOCK_STALE_MS) return null;
  return m;
}

const KIND_WORDS = { wrap: "Wrap", archive: "Archive", movedrive: "Move", rename: "Rename", turnoff: "Turn Off",
  delete: "Delete", showcase: "Prepare Showcase", undo: "Undo" };

/** A move already running on this project, in words, or "". */
export function busyWords(record, now = Date.now()) {
  const m = lockOf(record, now);
  return m ? `${KIND_WORDS[m.kind] || "Another move"} is running on this project. Wait for it to finish.` : "";
}

/** Change the record by compare-and-set (`fn(record) → record | null`). */
async function changeRecord(env, key, fn) {
  for (let i = 0; i < 4; i++) {
    const got = await env.BUCKET.get(`r/${key}/record.json`);
    if (!got) return null;
    let r;
    try { r = await got.json(); } catch { return null; }
    const next = fn(r);
    if (!next) return r;
    const ok = await env.BUCKET.put(`r/${key}/record.json`, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" }, onlyIf: { etagMatches: got.etag },
    });
    if (ok) return next;
  }
  throw new Error("The record kept changing while this was being written.");
}

async function lock(w, ctx, kind, moveId) {
  if (!ctx.record) return;
  let refused = "";
  await changeRecord(w.env, ctx.key, (r) => {
    const held = lockOf(r, w.now().getTime());
    if (held && held.move_id !== moveId) { refused = busyWords(r, w.now().getTime()); return null; }
    return { ...r, moving: { kind, since: w.now().toISOString(), move_id: moveId } };
  });
  if (refused) throw new Refusal(refused);
}

async function unlock(w, ctx, moveId) {
  if (!ctx.record) return;
  try {
    await changeRecord(w.env, ctx.key, (r) => {
      if (!r.moving || r.moving.move_id !== moveId) return null;
      const { moving: _gone, ...rest } = r;
      return rest;
    });
  } catch (e) { console.error("bigmoves: unlock:", String((e && e.message) || e)); }
}

/** The record's status fact written (as `set_stage` does). */
async function writeStatus(w, ctx, value) {
  if (!ctx.record) return null;
  const { writeFacts } = await import("./facts.js");
  const r = await readJson(w.env, `r/${ctx.key}/record.json`);
  if (!r) return null; // a project with no record yet: Notion's status is the whole of it
  const kept = r.facts && r.facts.status;
  const base = isObject(kept) ? Number(kept.v) || 0 : 0;
  const before = isObject(kept) ? kept.value : null;
  const got = await writeFacts(w.env, ctx.key, { status: { value, base } }, "server");
  if (got.status !== 200) throw new Error(`the record's status could not be written (${got.problem || got.status})`);
  return before;
}

/** The record's Shoot Dates fact written, so a Wrap that moves the dates is not
 * contradicted by the record's old ones (it is read over Notion's). Returns
 * the words it held, or null when the record has no Shoot Dates to keep in step
 * (nothing is written then: a first one would be a question for the link). */
async function writeDatesFact(w, ctx, value) {
  if (!ctx.record) return null;
  const { writeFacts } = await import("./facts.js");
  const r = await readJson(w.env, `r/${ctx.key}/record.json`);
  const kept = r && r.facts && r.facts.shoot_dates;
  if (!isObject(kept) || typeof kept.value !== "string") return null;
  const got = await writeFacts(w.env, ctx.key, { shoot_dates: { value, base: Number(kept.v) || 0 } }, "server");
  if (got.status !== 200) throw new Error(`the record's Shoot Dates could not be written (${got.problem || got.status})`);
  return kept.value;
}
const datesWords = (d) => (!d.start ? "" : (d.end && d.end !== d.start ? `${d.start}/${d.end}` : d.start));

async function writeTitleFact(w, ctx, value) {
  const { writeFacts } = await import("./facts.js");
  const r = await readJson(w.env, `r/${ctx.key}/record.json`);
  if (!r) return null;
  const kept = r.facts && r.facts.title;
  const base = isObject(kept) ? Number(kept.v) || 0 : 0;
  const got = await writeFacts(w.env, ctx.key, { title: { value, base } }, "server");
  if (got.status !== 200) throw new Error(`the record's title could not be written (${got.problem || got.status})`);
  return isObject(kept) ? kept.value : null;
}

const statusProp = (name) => ({ properties: { Status: name ? { select: { name } } : { select: null } } });
function datesProp(start, end) {
  if (!start) return { properties: { "Shoot Dates": { date: null } } };
  return { properties: { "Shoot Dates": { date: end && end !== start ? { start, end } : { start } } } };
}

function line(text, who = SERVER, extra = {}) { return { text, who, ...extra }; }

function base(kind, ctx, extra = {}) {
  return {
    ok: true, kind, by: "server",
    project: { id: ctx.key, page: ctx.page, name: ctx.name, scratch: ctx.scratch },
    title: "", sub: "", heading: "", lines: [], stays: [], flags: [], notes: [], problems: [],
    arm: "click", confirm: ctx.name, button: "", footer: "Nothing is deleted. Undo is in the history.",
    ...extra,
  };
}

function placeWords(path) {
  const parts = String(path || "").split("/");
  return parts.length > 1 ? `${parts.slice(0, -1).join("/")}/` : "";
}

function sectionOf(ctx) {
  const top = String((ctx.place && ctx.place.path) || "").split("/")[0];
  return top === "gigs" ? "gigs" : top === "projects" ? "projects" : "other";
}

/** `.filing-rules.md` → Archiving: each section keeps its own archive. */
function archiveHome(ctx) {
  return sectionOf(ctx) === "gigs" ? { root: ctx.roots.gigs, name: "z-archive", path: "gigs/z-archive" }
    : { root: ctx.roots.projects, name: "z-archived", path: "projects/z-archived" };
}

function alreadyArchived(ctx) {
  return /^(projects\/z-archived|gigs\/z-archive)\/[^/]+\//.test(String((ctx.place && ctx.place.path) || ""));
}

// ── the looks ────────────────────────────────────────────────────────────────

/** The project's shoots as the wrap reads them: Notion's rows, or — with Notion
 * out of reach — the record's own copy of them (with its waiting edits laid on).
 * Parts waiting to reach Notion (a shoot already marked Wrapped here) are laid on both. */
async function wrapShoots(w, ctx) {
  let rows;
  if (!ctx.notionDown && ctx.page) {
    try {
      rows = (await shootPages(w, ctx.page)).map(shootOf);
    } catch (e) {
      if (!notionDown(e)) throw e;
      ctx.notionDown = true;
    }
  }
  if (!rows) {
    const { layEdits, editsOf } = await import("./shootedits.js");
    const facts = (ctx.record && ctx.record.facts) || {};
    const copy = facts.shoots && Array.isArray(facts.shoots.value) ? facts.shoots.value : [];
    rows = layEdits(copy.map((x) => ({ ...x, id: x.id })), editsOf(facts)).map((x) => ({
      id: x.id, title: x.title || "", label: x.label || x.title || "", n: x.n || null,
      start: String(x.start || "").slice(0, 10), end: String(x.end || "").slice(0, 10), status: x.status || "" }));
  }
  const waiting = await waitsFor(w.env, ctx.key, ctx.pageId);
  for (const x of waiting) {
    if (x.kind !== "shoot-status") continue;
    const hit = rows.find((r) => bare(r.id) === bare(x.shoot));
    if (hit) hit.status = x.status;
  }
  return rows;
}

async function lookWrap(w, ctx) {
  const out = base("wrap", ctx, { title: `Wrap ${ctx.name}`, button: "Wrap Project" });
  const shoots = await wrapShoots(w, ctx);
  const { target, later } = shoots.length ? wrapTarget(shoots, today(w.now())) : { target: null, later: [] };
  out.plan = { target: target ? { id: target.id, label: target.label, status: target.status } : null,
    later: later.map((s) => ({ id: s.id, label: s.label, start: s.start, end: s.end })) };
  if (target) out.sub = target.title && target.label !== target.title ? `${target.label}` : target.label;
  if (later.length) {
    const nxt = later[0];
    const when = pretty(nxt.start);
    out.lines.push(line(`Status stays Active · ${nxt.label}${when ? ` (${when})` : ""} is still to come`));
    if (nxt.start && ctx.dates.start !== nxt.start) {
      out.lines.push(line(`Shoot Dates move on to ${nxt.label}${when ? ` (${when})` : ""}`));
      out.plan.dates = { start: nxt.start, end: nxt.end || "" };
    }
  } else {
    // Already in Post, and no shoot left to mark: there is nothing to do (a second press).
    const done = same(ctx.status, "Post") && (!target || target.status === "Wrapped");
    if (!done) { out.lines.push(line("Notion status → Post")); out.plan.status = "Post"; }
  }
  if (target) {
    if (target.status === "Wrapped") out.notes.push(`${target.label} is already marked Wrapped.`);
    else { out.lines.push(line(`${target.label} marked Wrapped`)); out.plan.shoot = target.id; }
  }
  out.lines.push(line("Drive folder stays where it is", SERVER, { tone: "keep" }));
  const rec = ctx.record || {};
  if ((rec.film && rec.film.relay) || rec.portal) out.lines.push(line("Portal stays up for the grade", SERVER, { tone: "keep" }));
  out.lines.push(line(`Job Log reminder for ${target ? target.label : ctx.name}`));
  if (!ctx.folder) out.notes.push("No Drive folder found. Only the status changes.");
  // Notion out of reach: the record's part is done now, Notion's waits (one quiet line).
  if (ctx.notionDown) {
    out.plan.notion_waits = true;
    out.lines.push(line(NOTION_WAITS, SERVER, { tone: "note" }));
  }
  if (!out.plan.status && !out.plan.shoot && !out.plan.dates) out.problems.push("Nothing to change.");
  return out;
}

async function lookArchive(w, ctx) {
  const year = yearNow(w.now());
  const out = base("archive", ctx, { title: `Archive ${ctx.name}`, arm: "twice", button: `Archive ${ctx.name}`,
    armed_button: "Click Again to Archive" });
  if (!ctx.folder || !ctx.place) {
    out.problems.push("No Drive folder found.");
    return out;
  }
  if (alreadyArchived(ctx)) { out.problems.push("Its Drive folder is already in the archive."); return out; }
  const home = archiveHome(ctx);
  if (!home.root) { out.problems.push(`No ${home.path.split("/")[0]}/ folder on the Drive.`); return out; }
  const { weigh } = await import("./drivemoves.js");
  const weight = await weigh(w.raw, ctx.folder.id);
  const za = await folderIn(w.raw, home.root, home.name);
  const yr = za ? await folderIn(w.raw, za, year) : null;
  if (yr && childNamed(await w.raw.list(yr), ctx.folder.name)) {
    out.problems.push(`${home.path}/${year}/${ctx.folder.name} already exists. Resolve it by hand first.`);
    return out;
  }
  out.plan = { year, home: home.path };
  out.lines.push(line(`${ctx.place.path} (${plural(weight.items, "item")}${weight.partial ? "+" : ""}) → ${home.path}/${year}/`));
  if (ctx.showcase && !ctx.showcase.archived) out.lines.push(line(`Showcase → project-showcases/zz-archived/${year}/`));
  out.lines.push(line("Notion status → Archived"));
  out.lines.push(line("Portal stays as it is", SERVER, { tone: "keep" }));
  out.lines.push(line("Studio side stays as it is", SERVER, { tone: "keep" }));
  out.lines.push(line("Footage stays on its drives", SERVER, { tone: "keep" }));
  out.lines.push(line("Then: Job Log entry and payment status current?", "", { tone: "note" }));
  return out;
}

const HOMES = [
  { key: "projects", label: "PROJECTS", sub: "projects/" },
  { key: "gigs", label: "GIGS", sub: "gigs/" },
  { key: "archive", label: "ARCHIVE", sub: "" },
  { key: "custom", label: "ANYWHERE…", sub: "pick a folder on the Drive" },
];

async function destOf(w, ctx, opts, { make = false, made = [] } = {}) {
  const dest = String(opts.dest || "");
  if (dest === "projects" || dest === "gigs") {
    const id = ctx.roots[dest];
    return id ? { id, path: `${dest}/` } : { why: `${dest}/ is not there` };
  }
  if (dest === "archive") {
    const home = archiveHome(ctx);
    const year = yearNow(w.now());
    if (!home.root) return { why: "No archive folder on the Drive." };
    const za = await folderIn(make ? w.fenced : w.raw, home.root, home.name, { make, made });
    const yr = za ? await folderIn(make ? w.fenced : w.raw, za, year, { make, made }) : null;
    return { id: yr, path: `${home.path}/${year}/`, would_make: !yr };
  }
  if (dest === "custom") {
    const id = String(opts.folder || "");
    if (!DRIVE_ID.test(id)) return { why: "Pick a folder first." };
    const { placeOf } = await import("./drivemoves.js");
    const place = id === ctx.roots.top ? { path: "" } : await placeOf(w.raw, id, [ctx.roots.top]);
    if (!place) return { why: "That folder is not inside the cinematography folder." };
    const got = await w.raw.get(id);
    if (!got || !got.folder) return { why: "That is not a folder." };
    return { id, path: place.path ? `${place.path}/` : "" };
  }
  return { why: `No home called ${dest || "that"}.` };
}

async function lookMoveDrive(w, ctx, opts) {
  const out = base("movedrive", ctx, { title: `Move ${ctx.name}`, arm: "typed", button: "Move" });
  if (!ctx.folder || !ctx.place) { out.problems.push("No Drive folder to move."); return out; }
  const here = placeWords(ctx.place.path);
  const year = yearNow(w.now());
  const arch = archiveHome(ctx);
  out.homes = HOMES.map((h) => ({ ...h, sub: h.key === "archive" ? `${arch.path}/${year}/` : h.sub }))
    .filter((h) => h.sub !== here);
  out.where = here;
  if (opts.browse !== undefined) {
    // The folder picker: a folder's folders, inside the cinematography folder only.
    const at = DRIVE_ID.test(String(opts.browse || "")) ? opts.browse : ctx.roots.top;
    const { placeOf } = await import("./drivemoves.js");
    const place = at === ctx.roots.top ? { path: "" } : await placeOf(w.raw, at, [ctx.roots.top]);
    if (!place) { out.problems.push("That folder is not inside the cinematography folder."); return out; }
    out.browse = { id: at, path: place.path, up: at === ctx.roots.top ? "" : ((await w.raw.get(at)).parents || [])[0] || "",
      folders: (await w.raw.list(at)).filter((k) => k.folder && !k.name.startsWith(".") && k.id !== ctx.folder.id)
        .sort((a, b) => (a.name < b.name ? -1 : 1)).map((k) => ({ id: k.id, name: k.name })) };
    return out;
  }
  if (!opts.dest) { out.problems.push("Pick where it goes."); return out; }
  const dest = await destOf(w, ctx, opts);
  if (dest.why) { out.problems.push(dest.why); return out; }
  if (dest.id && dest.id === (ctx.folder.parents || [])[0]) { out.problems.push("It is already there."); return out; }
  if (dest.id === ctx.folder.id) { out.problems.push("A folder can't move into itself."); return out; }
  if (dest.id) {
    const { chainUp } = await import("./drivemoves.js");
    const chain = await chainUp(w.raw, dest.id, [ctx.roots.top]);
    if (chain && chain.some((c) => c.id === ctx.folder.id)) { out.problems.push("A folder can't move into itself."); return out; }
    if (childNamed(await w.raw.list(dest.id), ctx.folder.name)) { out.problems.push(`${dest.path}${ctx.folder.name} already exists.`); return out; }
  }
  const { weigh } = await import("./drivemoves.js");
  const weight = await weigh(w.raw, ctx.folder.id);
  out.plan = { dest: opts.dest, folder: opts.folder || "", to: dest.path };
  out.lines.push(line(`${ctx.place.path} (${plural(weight.items, "item")}${weight.partial ? "+" : ""}) → ${dest.path}${ctx.folder.name}`));
  out.lines.push(line("Notion's link keeps working", SERVER, { tone: "keep" }));
  if (ctx.record && ctx.record.film && ctx.record.film.relay) out.lines.push(line("Studio told where the folder went", STUDIO_MAC));
  out.lines.push(line("The showcase and footage stay where they are", SERVER, { tone: "keep" }));
  return out;
}

function renameAsked(ctx, opts) {
  let newName = String(opts.new_name || "").trim();
  let newSlug = String(opts.new_slug || "").trim();
  if (newName === ctx.name) newName = "";
  if (newSlug && ctx.slug && newSlug === ctx.slug) newSlug = "";
  return { newName, newSlug };
}

async function lookRename(w, ctx, opts) {
  const out = base("rename", ctx, { title: `Rename ${ctx.name}`, arm: "typed", button: "Rename",
    footer: "Share links don't change. Undo is in the history." });
  out.slug = ctx.slug;
  const { newName, newSlug } = renameAsked(ctx, opts);
  out.plan = { new_name: newName, new_slug: newSlug };
  if (!newName && !newSlug) { out.problems.push("Nothing to change."); return out; }
  if (newName) out.lines.push(line(`Name: ${ctx.name} → ${newName}`));
  if (newName && !ctx.notion && ctx.notionDown) out.notes.push(NOTION_WAITS);
  if (newSlug) {
    if (!SLUG_OK.test(newSlug)) { out.problems.push("A folder name is lowercase letters, numbers and dashes only."); return out; }
    if (!ctx.folder) { out.problems.push("No Drive folder found for this project."); return out; }
    out.lines.push(line(`Folders: ${ctx.slug} → ${newSlug}`, "", { tone: "head" }));
    const parent = (ctx.folder.parents || [])[0];
    if (parent && childNamed(await w.raw.list(parent), newSlug)) out.problems.push(`already there: ${newSlug}`);
    out.lines.push(line(`Drive folder → ${newSlug}`));
    if (ctx.showcase) {
      const want = `${newSlug}${SHOWCASE_SUFFIX}`;
      if (childNamed(await w.raw.list(ctx.showcase.parent), want)) out.problems.push(`already there: ${want}`);
      out.lines.push(line(`Showcase → ${want}`));
    }
    const media = ((ctx.record && ctx.record.media) || []).map((m) => m && m.drive).filter(Boolean);
    for (const d of media) out.lines.push(line(`Media on ${d} keeps its folder name (${ctx.slug})`, SERVER, { tone: "keep" }));
    out.lines.push(line(`Drive bridge list → ${newSlug}, if it names ${ctx.slug}`, STUDIO_MAC));
    if (ctx.record && ctx.record.film && ctx.record.film.relay) out.lines.push(line("Studio told where the folder went", STUDIO_MAC));
  }
  out.lines.push(line("Share links don't change", SERVER, { tone: "keep" }));
  return out;
}

const OFF_SYSTEMS = { showcase: "Portfolio Showcase", website: "Website Page" };

async function lookTurnOff(w, ctx, opts) {
  const system = String(opts.system || "");
  const label = OFF_SYSTEMS[system];
  const out = base("turnoff", ctx, { title: `Turn Off ${label || ""} · ${ctx.name}`, system, label: label || "" });
  if (!label) {
    if (system === "notion" || system === "drive") out.problems.push("That one is the project itself. Use Delete.");
    else if (system === "media") out.problems.push("Footage is never touched.");
    else out.problems.push("Turn Off covers the showcase and the website link.");
    return out;
  }
  if (system === "showcase") {
    // Nothing goes to any trash (his rule, 2026-10-15 morning): the showcase
    // moves into project-showcases/zz-archived/<year>/, id kept, as Archive does.
    if (!ctx.showcase) { out.problems.push("No showcase to turn off."); return out; }
    if (ctx.showcase.archived) { out.problems.push("The showcase is already in the archive."); return out; }
    const year = yearNow(w.now());
    const zz = await folderIn(w.raw, ctx.roots.showcases, "zz-archived");
    const yr = zz ? await folderIn(w.raw, zz, year) : null;
    if (yr && childNamed(await w.raw.list(yr), ctx.showcase.name)) {
      out.problems.push(`project-showcases/zz-archived/${year}/${ctx.showcase.name} already exists. Resolve it by hand first.`);
      return out;
    }
    const { weigh } = await import("./drivemoves.js");
    const weight = await weigh(w.raw, ctx.showcase.id);
    out.heading = "MOVES";
    out.lines.push(line(`${ctx.showcase.path} · ${plural(weight.files, "file")} → project-showcases/zz-archived/${year}/`));
    out.warn = "Your curated selects move with it. Nothing is deleted.";
    out.arm = "twice";
    out.button = "Move to Archive";
    out.armed_button = "Click Again to Move";
    out.footer = "Undo is in the history.";
    out.plan = { showcase: ctx.showcase.id, year };
    return out;
  }
  if (!ctx.website) { out.problems.push("No website link to forget."); return out; }
  out.heading = "FORGETS";
  out.lines.push(line(ctx.website));
  out.warn = "Your website page stays up. This forgets the address.";
  out.button = "Forget Link";
  out.plan = { website: ctx.website };
  return out;
}

/** What a project holds that someone would miss: shots, scenes, files, people. */
async function contentOf(w, ctx) {
  const rec = ctx.record || {};
  const film = isObject(rec.film) ? rec.film : null;
  const out = { shots: 0, scenes: 0, files: 0, people: 0, links: 0, views: 0 };
  if (film) { out.shots = Number(film.shots) || 0; out.scenes = Number(film.scenes) || 0; }
  if (ctx.folder) {
    const { weigh } = await import("./drivemoves.js");
    out.files = (await weigh(w.raw, ctx.folder.id)).files;
  }
  const relay = film && film.relay ? bare(film.relay) : "";
  for (const p of [relay, ctx.key].filter(Boolean)) {
    const people = await readJson(w.env, keys.people(p));
    if (people) {
      out.people += (people.people || []).length + (people.invites || []).length;
      out.links += (people.links || []).filter((l) => l && !l.off).length;
    }
    const views = await readJson(w.env, keys.views(p));
    if (views) out.views += Array.isArray(views) ? views.length : Array.isArray(views.views) ? views.views.length : 0;
  }
  return out;
}

/** Every bucket prefix that is this project's Studio side or portal. */
async function portalPrefixes(w, ctx) {
  const out = [];
  const film = ctx.record && isObject(ctx.record.film) ? ctx.record.film : null;
  const ids = [film && film.relay ? bare(film.relay) : "", ctx.key, ctx.page].filter((x) => /^[0-9a-f]{8,64}$/.test(x));
  for (const id of [...new Set(ids)]) {
    const got = await w.env.BUCKET.list({ prefix: keys.film(id), limit: 1 });
    if ((got.objects || []).length) out.push(id);
  }
  return out;
}

async function lookDelete(w, ctx) {
  const out = base("delete", ctx, { title: `Delete ${ctx.name}`, arm: "typed", button: "Delete", heading: "WHAT GOES",
    footer: "Everything here can be brought back for 30 days." });
  const shoots = ctx.page ? await shootPages(w, ctx.page) : [];
  if (ctx.notion) {
    out.lines.push(line(`Notion · ${ctx.name}${shoots.length ? ` and its ${plural(shoots.length, "shoot row")}` : ""} → Notion's trash`));
  }
  if (ctx.folder && ctx.place) out.lines.push(line(`Drive · ${ctx.place.path} → Drive's trash`));
  else out.notes.push("No Drive folder found.");
  if (ctx.showcase) out.lines.push(line(`Showcase · ${ctx.showcase.name} → Drive's trash`));
  if (ctx.record) out.lines.push(line("Project record · off every list"));
  const prefixes = await portalPrefixes(w, ctx);
  const film = ctx.record && isObject(ctx.record.film) && ctx.record.film.relay ? ctx.record.film : null;
  if (film) out.lines.push(line(`Studio · ${film.title || ctx.name} · removed from Studio on every Mac`));
  if (prefixes.length) out.lines.push(line("Portal · taken down, its share links stop working"));
  const media = ((ctx.record && ctx.record.media) || []).filter((m) => m && m.drive);
  out.stays.push(line("Job Log row", "", { tone: "keep" }));
  if (media.length) for (const m of media) out.stays.push(line(`Footage on ${m.drive}${m.size ? ` · ${m.size}` : ""} · stays on that drive, in ${ctx.slug || "its folder"}`, "", { tone: "keep" }));
  else out.stays.push(line("Footage on media drives · none known; any stays where it is", "", { tone: "keep" }));
  const c = await contentOf(w, ctx);
  if (c.shots || c.scenes) out.flags.push(`Studio has ${plural(c.shots, "shot")} in ${plural(c.scenes, "scene")}.`);
  if (c.files) out.flags.push(`The Drive folder holds ${plural(c.files, "file")}.`);
  if (c.people) out.flags.push(`${plural(c.people, "person", "people")} can open the portal.`);
  if (c.links) out.flags.push(`${plural(c.links, "share link")} will stop working.`);
  if (c.views) out.flags.push(`${plural(c.views, "view link")} will stop working.`);
  out.content = c;
  out.plan = { prefixes, shoots: shoots.map((s) => s.id) };
  return out;
}

/** A folder's path from the top of the Drive ("cinematography/portfolio/…"), or "" when it can't be walked. */
async function pathUp(api, id, depth = 14) {
  const parts = [];
  let at = id;
  for (let i = 0; i < depth && at; i++) {
    const it = await api.get(at);
    if (!it) return "";
    const up = (it.parents || [])[0];
    if (!up) return parts.join("/");
    parts.unshift(it.name);
    at = up;
  }
  return "";
}

/** `fn` over `items`, `size` at a time, answers in the items' order. */
async function inGroups(items, size, fn) {
  const out = new Array(items.length);
  let next = 0;
  const worker = async () => { for (;;) { const i = next++; if (i >= items.length) return; out[i] = await fn(items[i], i); } };
  await Promise.all(Array.from({ length: Math.min(size, items.length) }, worker));
  return out;
}

/**
 * Prepare Showcase from the picked selects (2026-10-17, showcaseplan.js): the
 * record's `selects` are the one source. The look lists every file it will
 * make and every one it keeps, before anything is written.
 */
async function lookShowcase(w, ctx) {
  const SP = await import("./showcaseplan.js");
  const out = base("showcase", ctx, { title: `Prepare Showcase · ${ctx.name}`, button: "Prepare Showcase",
    footer: "Only adds. Files already there are kept." });
  if (!ctx.roots || !ctx.roots.top) { out.problems.push("The server can't see the Drive."); return out; }
  const year = yearNow(w.now());
  const archived = ctx.status === "Archived";
  const slug = ctx.slug || (await import("./drivefolders.js")).slugify(ctx.name);
  const sc = ctx.showcase;
  const where = sc ? sc.path : `portfolio/project-showcases/${archived ? `zz-archived/${year}/` : ""}${slug}${SHOWCASE_SUFFIX}`;
  out.where = String(where).replace(/^\(scratch\)\/?/, "");
  out.plan = { slug, archived };
  const facts = (ctx.record && ctx.record.facts) || {};
  const said = isObject(facts.selects) ? facts.selects.value : null;
  const ids = (Array.isArray(said) ? said : []).filter((x) => typeof x === "string" && DRIVE_ID.test(x));
  if (!ids.length) { out.problems.push("Pick selects first."); out.files = []; out.counts = { new: 0, kept: 0 }; return out; }
  // the showcase as it is: its stills/ (and lq/ when split), select-stills/,
  // credits.txt at its root, marker. website/ is his and is never read or written.
  const have = { stills: null, lq: null, select: null, root: new Set() };
  const stillsIds = new Set();
  let marker = false, oldCredits = null, stillsId = null, lqId = null;
  if (sc) {
    const inside = await w.raw.list(sc.id);
    marker = inside.some((k) => !k.folder && k.name === ".portfolio-project");
    have.root = new Set(inside.filter((k) => !k.folder).map((k) => k.name));
    const cr = inside.find((k) => !k.folder && k.name === "credits.txt");
    if (cr) oldCredits = (w.raw.text ? await w.raw.text(cr.id) : "") || "";
    const st = childNamed(inside.filter((k) => k.folder), "stills");
    const sel = childNamed(inside.filter((k) => k.folder), SP.SELECT_DIR);
    // the Drive can hold two folders of one name (a Mac's and a server-made one, 2026-10-17): read both
    const selTwins = inside.filter((k) => k.folder && k.id !== (sel && sel.id) && same(k.name, SP.SELECT_DIR));
    if (st) {
      stillsId = st.id; stillsIds.add(st.id);
      const kids = await w.raw.list(st.id);
      have.stills = new Set(kids.filter((k) => !k.folder).map((k) => k.name));
      for (const f of kids.filter((k) => k.folder)) {
        if (["lq", "hq", "matted"].includes(f.name.toLowerCase())) stillsIds.add(f.id);
        if (f.name.toLowerCase() === "lq") { lqId = f.id; have.lq = new Set((await w.raw.list(f.id)).filter((k) => !k.folder).map((k) => k.name)); }
      }
    }
    if (sel) {
      have.select = (await w.raw.list(sel.id)).filter((k) => !k.folder).map((k) => ({ id: k.id, name: k.name }));
      for (const tw of selTwins) {
        const seen = new Set(have.select.map((f) => f.name));
        for (const k of (await w.raw.list(tw.id)).filter((x) => !x.folder && !seen.has(x.name))) have.select.push({ id: k.id, name: k.name, twin: tw.id });
      }
      if (selTwins.length) out.notes.push("select-stills/ is on the Drive twice. Both are read.");
    }
  }
  // each pick: where it is, by its id
  const chose = isObject(facts.selects_folder) ? facts.selects_folder.value : null;
  const picks = [], gone = [];
  // Every pick is looked up at once, eight at a time (it was one after another:
  // about 0.6 s each, so 40 picks sat in "Looking…" for 25 s), then each distinct
  // folder is walked up once, also together.
  const found = await inGroups(ids, 8, (id) => w.raw.get(id));
  const dirs = new Map();
  const parentsToWalk = [...new Set(found.filter((it, i) => it && !it.trashed && !it.folder && !stillsIds.has((it.parents || [])[0] || "") && (it.parents || [])[0]).map((it) => it.parents[0]))];
  await inGroups(parentsToWalk, 8, async (parent) => { dirs.set(parent, await pathUp(w.raw, parent)); });
  ids.forEach((id, i) => {
    const it = found[i];
    if (!it || it.trashed || it.folder) { gone.push(id); return; }
    const parent = (it.parents || [])[0] || "";
    const inShowcase = stillsIds.has(parent);
    let at = "";
    if (inShowcase) at = parent === stillsId ? `stills/${it.name}` : `stills/${parent === lqId ? "lq" : "hq"}/${it.name}`;
    picks.push({ id, name: it.name, inShowcase, at, parent,
      dir: inShowcase ? "" : dirs.get(parent) || "",
      local: !inShowcase && isObject(chose) && chose.id === parent ? String(chose.path || "") : "" });
  });
  if (gone.length) out.notes.push(`${plural(gone.length, "select")} can't be found on the Drive and ${gone.length === 1 ? "is" : "are"} left out.`);
  if (!picks.length) { out.problems.push("Pick selects first."); out.files = []; out.counts = { new: 0, kept: 0 }; return out; }
  const text = SP.creditsText({ name: ctx.name, record: ctx.record, website: ctx.website });
  const day = today(w.now()).replace(/-/g, "");
  const got = SP.planFiles({ slug, picks, have, credits: { text, old: oldCredits }, showcaseMade: Boolean(sc), marker, day });
  out.files = got.files.map((f) => ({ path: f.path, kind: f.kind, state: f.state, still: f.still,
    ...(f.n ? { n: f.n } : {}), ...(f.kind === "archive" ? { id: f.id, from: f.from, to: f.to } : {}) }));
  out.counts = got.counts;
  const byId = new Map(picks.map((p) => [p.id, p]));
  out.plan = { slug, archived, credits: text, credits_name: got.creditsName,
    archive: got.archive,
    make: got.files.filter((f) => f.state === "new" && (f.kind === "still" || f.kind === "select"))
      .map((f) => { const p = byId.get(f.src); return { kind: f.kind, dst: f.path, src: { id: p.id, name: p.name, dir: p.dir, local: p.local, showcase: p.inShowcase ? p.at : "" } }; }) };
  // the words, for a screen that doesn't draw `files`
  const n = (kind, state) => got.files.filter((f) => f.kind === kind && f.state === state).length;
  if (!sc) out.lines.push(line(`Showcase folder ${out.where}`));
  if (n("still", "new")) out.lines.push(line(`${plural(n("still", "new"), "still")} into stills/ (.webp, fits 2560×1440, under 1MB)`, MAC));
  if (n("select", "new")) out.lines.push(line(`${plural(n("select", "new"), "select still")} into select-stills/, numbered in your order`, MAC));
  if (got.archive.length) out.lines.push(line(`${plural(got.archive.length, "select")} no longer picked → select-stills/z-archive/`, SERVER));
  if (n("credits", "new")) out.lines.push(line(`${got.creditsName} at the showcase's top level`));
  const kept = got.counts.kept;
  if (kept) out.lines.push(line(`${plural(kept, "file")} already there, kept`, SERVER, { tone: "keep" }));
  if (!got.counts.new && !got.archive.length) out.lines.push(line("Everything is already made", SERVER, { tone: "keep" }));
  return out;
}

const LOOKS = { wrap: lookWrap, archive: lookArchive, movedrive: lookMoveDrive, rename: lookRename,
  turnoff: lookTurnOff, delete: lookDelete, showcase: lookShowcase };

/** The look: what the run would do, from the world as it is. Writes nothing. */
export async function look(w, asked, kind, opts = {}, { settings = null, dry = false } = {}) {
  if (!KINDS.includes(kind)) throw new Refusal(`No move called ${kind}.`);
  const s = settings || await settingsOf(w.env);
  let ctx;
  try {
    ctx = await projectOf(w, asked, s);
  } catch (e) {
    if (e instanceof Refusal) return { ok: false, kind, why: e.message, ...(e.deleted ? { deleted: true } : {}) };
    throw e;
  }
  if (!dry) await mine(w, s, kind, ctx);
  const out = await LOOKS[kind](w, ctx, isObject(opts) ? opts : {});
  const busy = busyWords(ctx.record, w.now().getTime());
  if (busy) out.problems.unshift(busy);
  out.mode = s[kind];
  out.can_run = !out.problems.length;
  return out;
}

// ── the runs ─────────────────────────────────────────────────────────────────

function moveId() {
  const a = new Uint8Array(8);
  crypto.getRandomValues(a);
  return `mv-${[...a].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

async function queueJob(w, ctx, mv, kind, title, args, extra = {}) {
  if (!w.jobs || !w.jobs.READY) return { queued: false, why: "the Mac jobs list isn't on the server yet" };
  try {
    if (w.jobs.macJobsOn && !((await w.jobs.macJobsOn(w.env)) || {}).on) return { queued: false, why: "the Mac jobs list is switched off" };
    const job = await w.jobs.addJob(w.env, {
      kind, project_id: ctx.key, project_name: ctx.name, title, needs: { ...BIGMOVE_KINDS[kind].needs_default, ...(extra.needs || {}) },
      args, move_id: mv.id, by: w.by, ...(extra.sub ? { sub: extra.sub } : {}),
    });
    const id = job && (job.id || (job.job && job.job.id));
    if (id) mv.jobs.push(id);
    return { queued: true, id };
  } catch (e) {
    return { queued: false, why: String((e && e.message) || e).slice(0, 200) };
  }
}

async function saveMove(w, mv) {
  await putJson(w.env, `${MOVES}${mv.id}.json`, mv);
}

export async function moveOf(env, id) {
  if (!MOVE_ID.test(String(id || ""))) return null;
  return readJson(env, `${MOVES}${id}.json`);
}

async function logIt(w, mv, desc, undoable = true) {
  try {
    const { logActivity } = await import("./step6history.js");
    await logActivity(w.env, { kind: `bigmove-${mv.kind}`, desc, undo: undoable ? { type: "bigmove", move_id: mv.id } : null });
  } catch (e) { console.error("bigmoves: log:", String((e && e.message) || e)); }
}

/** Writes done in order; on a failure every one done is put back (newest first). */
async function allOrNothing(steps) {
  const done = [];
  for (const st of steps) {
    try {
      const back = await st.do();
      done.push({ st, back });
    } catch (e) {
      const why = String((e && e.message) || e).slice(0, 300);
      const stuck = [];
      for (const d of done.reverse()) {
        try { if (d.st.undo) await d.st.undo(d.back); } catch (u) { stuck.push(`${d.st.what}: ${String((u && u.message) || u).slice(0, 160)}`); }
      }
      const err = new Refusal(`Nothing was changed. It stopped at: ${st.what} — ${why}${stuck.length ? `\nCould not put back: ${stuck.join("; ")}` : ""}`);
      err.stuck = stuck;
      err.down = notionDown(e) && !stuck.length;     // Notion out of reach, and everything done put back
      throw err;
    }
  }
  return done;
}

async function runWrap(w, ctx, plan, mv) {
  const n = w.n;
  const u = mv.undo;
  u.status = ctx.status || "";
  const page = ctx.pageId || ctx.page;
  // Two kinds of step. The record's are the move (the record is the master);
  // Notion's follow, and when Notion is out of reach they wait on the list
  // (notionwaits.js) instead of stopping the move. A project's Status and
  // Shoot Dates reach Notion through the Notion link from the record, so only
  // the shoot row needs keeping — and a project with no record, its status.
  const notionSteps = [];
  const recordSteps = [];
  const waits = [];                    // what Notion has still to be told
  if (plan.shoot) {
    let was = "";
    if (!ctx.notionDown) {
      try { was = selectOf(((await n.get(`pages/${plan.shoot}`)) || {}).properties, "Status"); } catch (e) { if (!notionDown(e)) throw e; ctx.notionDown = true; }
    }
    u.shoot = { id: plan.shoot, status: was || (plan.target && plan.target.status) || "Upcoming" };
    notionSteps.push({ what: "the shoot row", do: () => n.patch(`pages/${plan.shoot}`, statusProp("Wrapped")),
      undo: () => n.patch(`pages/${plan.shoot}`, statusProp(u.shoot.status)) });
    waits.push({ kind: "shoot-status", shoot: bare(plan.shoot), status: "Wrapped", label: (plan.target && plan.target.label) || "A shoot" });
  }
  if (plan.dates) {
    u.dates = { ...ctx.dates };
    notionSteps.push({ what: "the Shoot Dates", do: () => n.patch(`pages/${page}`, datesProp(plan.dates.start, plan.dates.end)),
      undo: () => n.patch(`pages/${page}`, datesProp(ctx.dates.start, ctx.dates.end)) });
    recordSteps.push({ what: "the record's Shoot Dates", do: async () => { u.record_dates = await writeDatesFact(w, ctx, datesWords(plan.dates)); return u.record_dates; },
      undo: async (before) => { if (before !== null && before !== undefined) await writeDatesFact(w, ctx, before); } });
  }
  if (plan.status) {
    notionSteps.push({ what: "Notion's status", do: () => n.patch(`pages/${page}`, statusProp(plan.status)),
      undo: () => n.patch(`pages/${page}`, statusProp(ctx.status)) });
    recordSteps.push({ what: "the record's status", do: async () => { u.record_status = await writeStatus(w, ctx, plan.status); return u.record_status; },
      undo: (before) => writeStatus(w, ctx, before || ctx.status) });
  }
  // The order Notion-first steps always had (Notion's, then the record's, each in
  // the plan's order), so a refusal from Notion that is not "out of reach"
  // still puts everything back and changes nothing.
  const inPlanOrder = [...notionSteps, ...recordSteps];
  if (!ctx.notionDown) {
    try {
      await allOrNothing(inPlanOrder);
    } catch (e) {
      if (!(e instanceof Refusal) || !e.down) throw e;
      ctx.notionDown = true;           // Notion went out of reach: nothing was changed, so go on without it
    }
  }
  if (ctx.notionDown) {
    await allOrNothing(recordSteps);
    u.waits = [];
    for (const x of waits) u.waits.push(await addWait(w.env, { ...x, project: ctx.key, page: bare(page), by: w.by }));
    // Dates the record has none to carry, or a status with no record: the Notion link has nothing
    // to follow, so Notion is told these itself.
    if (plan.dates && (u.record_dates === null || u.record_dates === undefined)) {
      u.waits.push(await addWait(w.env, { kind: "project-dates", project: ctx.key, page: bare(page), start: plan.dates.start, end: plan.dates.end || "", label: ctx.name }));
    }
    if (plan.status && !ctx.record) {
      u.waits.push(await addWait(w.env, { kind: "project-status", project: ctx.key, page: bare(page), status: plan.status, label: ctx.name }));
    }
  }
  const said = plan.status ? `${ctx.name} is in Post.` : `${ctx.name}: ${plan.shoot ? "shoot wrapped" : "nothing"}; status stays Active.`;
  return { said: ctx.notionDown ? `${said} ${NOTION_WAITS}.` : said, notionWaits: Boolean(ctx.notionDown) };
}

async function runArchive(w, ctx, plan, mv) {
  const year = plan.year;
  const home = archiveHome(ctx);
  const made = [];
  const u = mv.undo;
  u.status = ctx.status || "";
  u.made = made;
  const steps = [];
  steps.push({ what: `the Drive folder → ${home.path}/${year}/`, do: async () => {
    const za = await folderIn(w.fenced, home.root, home.name, { make: true, made });
    const yr = await folderIn(w.fenced, za, year, { make: true, made });
    const from = (ctx.folder.parents || [])[0];
    await w.fenced.move(ctx.folder.id, from, yr);
    u.folder = { id: ctx.folder.id, from, to: yr };
    return u.folder;
  }, undo: (b) => w.fenced.move(b.id, b.to, b.from) });
  if (ctx.showcase && !ctx.showcase.archived) {
    steps.push({ what: "the showcase", do: async () => {
      const zz = await folderIn(w.fenced, ctx.roots.showcases, "zz-archived", { make: true, made });
      const yr = await folderIn(w.fenced, zz, year, { make: true, made });
      await w.fenced.move(ctx.showcase.id, ctx.showcase.parent, yr);
      u.showcase = { id: ctx.showcase.id, from: ctx.showcase.parent, to: yr };
      return u.showcase;
    }, undo: (b) => w.fenced.move(b.id, b.to, b.from) });
  }
  // Notion out of reach never stops an Archive: the record (the master) and Drive do their parts,
  // and Notion's status follows from the record through the Notion link (or waits on the list when
  // there is no record to follow).
  let notionWaiting = false;
  if (ctx.notion) {
    steps.push({ what: "Notion's status", do: async () => {
      try { await w.n.patch(`pages/${ctx.page}`, statusProp("Archived")); return { sent: true }; } catch (e) {
        if (!notionDown(e)) throw e;
        notionWaiting = true;
        return { sent: false };
      }
    }, undo: (b) => (b && b.sent ? w.n.patch(`pages/${ctx.page}`, statusProp(ctx.status)) : undefined) });
  }
  steps.push({ what: "the record's status", do: async () => { u.record_status = await writeStatus(w, ctx, "Archived"); return u.record_status; },
    undo: (before) => writeStatus(w, ctx, before || ctx.status) });
  await allOrNothing(steps);
  if (ctx.notionDown || notionWaiting) {
    notionWaiting = true;
    if (!ctx.record && ctx.pageId) {
      u.waits = [await addWait(w.env, { kind: "project-status", project: ctx.key, page: bare(ctx.pageId), status: "Archived", label: ctx.name })];
    }
  }
  const jobs = [];
  if (ctx.record && ctx.record.film && ctx.record.film.relay && !ctx.scratch) {
    jobs.push(await queueJob(w, ctx, mv, "film-drivefolder", `Tell Studio where the folder went · ${ctx.name}`,
      { page: ctx.page, project_id: ctx.key, drive_id: ctx.folder.id, path: `${home.path}/${year}/${ctx.folder.name}` }));
  }
  return { said: `${ctx.name} archived: ${home.path}/${year}/${ctx.folder.name}. Job Log entry and payment status current?${notionWaiting ? ` ${NOTION_WAITS}.` : ""}`, jobs, notionWaits: notionWaiting };
}

async function runMoveDrive(w, ctx, plan, mv, opts) {
  const made = [];
  const dest = await destOf(w, ctx, opts, { make: true, made });
  if (dest.why || !dest.id) throw new Refusal(dest.why || "The destination could not be made.");
  const from = (ctx.folder.parents || [])[0];
  await w.fenced.move(ctx.folder.id, from, dest.id);
  mv.undo = { folder: { id: ctx.folder.id, from, to: dest.id }, made };
  const jobs = [];
  if (ctx.record && ctx.record.film && ctx.record.film.relay && !ctx.scratch) {
    jobs.push(await queueJob(w, ctx, mv, "film-drivefolder", `Tell Studio where the folder went · ${ctx.name}`,
      { page: ctx.page, project_id: ctx.key, drive_id: ctx.folder.id, path: `${dest.path}${ctx.folder.name}` }));
  }
  return { said: `${ctx.place.path} → ${dest.path}${ctx.folder.name}`, jobs };
}

/** The record's own names after a rename, and what they were. */
function renamedRecord(r, { name, slug, oldSlug }) {
  const next = { ...r };
  if (name) next.name = name;
  if (slug) {
    next.slug = slug;
    if (isObject(r.drive)) next.drive = { ...r.drive, name: slug };
    // Media folders are never renamed: each drive's folder keeps the name it
    // had, and the record says so, so the drive light still finds it.
    const names = isObject(r.media_names) ? { ...r.media_names } : {};
    for (const m of (Array.isArray(r.media) ? r.media : [])) {
      if (m && m.drive && !names[m.drive]) names[m.drive] = oldSlug;
    }
    if (Object.keys(names).length) next.media_names = names;
  }
  return next;
}

async function runRename(w, ctx, plan, mv) {
  const { new_name: newName, new_slug: newSlug } = plan;
  const u = mv.undo;
  u.name = ctx.name;
  u.slug = ctx.slug;
  const steps = [];
  if (newSlug) {
    steps.push({ what: "the Drive folder", do: async () => { await w.fenced.rename(ctx.folder.id, newSlug); return ctx.folder.id; },
      undo: () => w.fenced.rename(ctx.folder.id, ctx.slug) });
    if (ctx.showcase) {
      steps.push({ what: "the showcase", do: async () => { await w.fenced.rename(ctx.showcase.id, `${newSlug}${SHOWCASE_SUFFIX}`); return ctx.showcase.name; },
        undo: (old) => w.fenced.rename(ctx.showcase.id, old) });
      u.showcase = { id: ctx.showcase.id, name: ctx.showcase.name };
    }
    u.folder = { id: ctx.folder.id, name: ctx.slug };
  }
  if (newName && ctx.notion) {
    steps.push({ what: "the Notion title", do: () => w.n.patch(`pages/${ctx.page}`, { properties: { [ctx.titleProp]: { title: [{ text: { content: newName } }] } } }),
      undo: () => w.n.patch(`pages/${ctx.page}`, { properties: { [ctx.titleProp]: { title: [{ text: { content: ctx.name } }] } } }) });
  }
  if (ctx.record) {
    steps.push({ what: "the record", do: async () => {
      let before = null;
      await changeRecord(w.env, ctx.key, (r) => { before = { name: r.name, slug: r.slug, drive: r.drive, media_names: r.media_names };
        return renamedRecord(r, { name: newName, slug: newSlug, oldSlug: ctx.slug }); });
      u.record = before;
      return before;
    }, undo: (before) => changeRecord(w.env, ctx.key, (r) => {
      const back = { ...r, name: before.name, slug: before.slug, drive: before.drive };
      if (before.media_names === undefined) delete back.media_names; else back.media_names = before.media_names;
      return back;
    }) });
    if (newName) {
      steps.push({ what: "the record's title", do: async () => { u.title = await writeTitleFact(w, ctx, newName); return u.title; },
        undo: (before) => (before !== null ? writeTitleFact(w, ctx, before) : null) });
    }
  }
  await allOrNothing(steps);
  // Notion out of reach: its title waits (notionwaits.js) and is written the
  // first time Notion answers, so the name never stays old there for good.
  let notionWaiting = false;
  if (newName && !ctx.notion && ctx.notionDown && ctx.pageId) {
    u.waits = [await addWait(w.env, { kind: "project-title", project: ctx.key, page: bare(ctx.pageId), status: newName,
      prop: "Project", label: ctx.name, by: w.by })];
    notionWaiting = true;
  }
  const jobs = [];
  if (newSlug && !ctx.scratch) {
    jobs.push(await queueJob(w, ctx, mv, "bridge-list", `Drive bridge list · ${newName || ctx.name}`, { old: ctx.slug, new: newSlug }));
    if (ctx.record && ctx.record.film && ctx.record.film.relay) {
      jobs.push(await queueJob(w, ctx, mv, "film-drivefolder", `Tell Studio where the folder went · ${newName || ctx.name}`,
        { page: ctx.page, project_id: ctx.key, drive_id: ctx.folder.id, path: `${placeWords(ctx.place.path)}${newSlug}` }));
    }
  }
  const said = [newName ? `${ctx.name} → ${newName}` : "", newSlug ? `${ctx.slug} → ${newSlug}` : "",
    notionWaiting ? NOTION_WAITS : ""].filter(Boolean).join(" · ");
  return { said, jobs, notionWaits: notionWaiting };
}

async function runTurnOff(w, ctx, plan, mv) {
  if (plan.showcase) {
    const made = [];
    const zz = await folderIn(w.fenced, ctx.roots.showcases, "zz-archived", { make: true, made });
    const yr = await folderIn(w.fenced, zz, plan.year, { make: true, made });
    await w.fenced.move(ctx.showcase.id, ctx.showcase.parent, yr);
    mv.undo = { showcase: { id: ctx.showcase.id, from: ctx.showcase.parent, to: yr }, made };
    return { said: `${ctx.showcase.name} → project-showcases/zz-archived/${plan.year}/` };
  }
  await w.n.patch(`pages/${ctx.page}`, { properties: { Website: { url: null } } });
  mv.undo = { website: plan.website };
  return { said: "Website link forgotten" };
}

/** Copy every object under a prefix to another; answers how many. */
async function copyPrefix(env, from, to) {
  let n = 0;
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: from, cursor, limit: 1000 });
    for (const o of page.objects || []) {
      const got = await env.BUCKET.get(o.key);
      if (!got) continue;
      await env.BUCKET.put(to + o.key.slice(from.length), got.body !== undefined ? got.body : await got.text(), {
        httpMetadata: got.httpMetadata, customMetadata: got.customMetadata,
      });
      n += 1;
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return n;
}

async function deletePrefix(env, prefix) {
  let n = 0;
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000 });
    const keys = (page.objects || []).map((o) => o.key);
    if (keys.length) { await env.BUCKET.delete(keys); n += keys.length; }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return n;
}

async function countPrefix(env, prefix) {
  let n = 0;
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000 });
    n += (page.objects || []).length;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return n;
}

/**
 * **The backup, before anything is deleted**: the record whole, the Notion
 * page and its Shoots rows as they are, the Drive ids, and every object of
 * the Studio side and the portal copied under `bigmoves/backups/<move>/`.
 * Checked (read back and counted) before the first write; a backup that
 * cannot be finished stops the delete with nothing deleted.
 */
async function backupForDelete(w, ctx, plan, mv) {
  const at = `${BACKUPS}${mv.id}/`;
  const shoots = [];
  for (const id of plan.shoots || []) {
    try { shoots.push(await w.n.get(`pages/${id}`)); } catch (e) { throw new Error(`a Shoots row could not be read for the backup (${e.message})`); }
  }
  const copied = {};
  for (const p of plan.prefixes || []) {
    const n = await copyPrefix(w.env, keys.film(p), `${at}${keys.film(p)}`);
    const back = await countPrefix(w.env, `${at}${keys.film(p)}`);
    if (back < n) throw new Error("the portal's backup is short; nothing was deleted");
    copied[p] = n;
  }
  const gone = {};
  for (const p of plan.prefixes || []) {
    const note = await readJson(w.env, `gone/${p}.json`);
    if (note) gone[p] = note;
  }
  let filmBackup = null;
  const relay = ctx.record && ctx.record.film && ctx.record.film.relay ? bare(ctx.record.film.relay) : "";
  if (relay && w.filmBackup !== false) {
    try {
      const fb = await import("./filmbackuprun.js");
      if (await fb.backupsOn(w.env)) filmBackup = await fb.backupFilm(w.env, { relay, title: (ctx.record.film.title || ctx.name) });
    } catch (e) { filmBackup = { trouble: String((e && e.message) || e).slice(0, 200) }; }
  }
  const backup = {
    move_id: mv.id, at: w.now().toISOString(), key: ctx.key, page: ctx.page, name: ctx.name,
    record: ctx.record, notion: ctx.notion ? { id: ctx.notion.id, properties: ctx.notion.properties, icon: ctx.notion.icon || null, parent: ctx.notion.parent || null } : null,
    shoots: shoots.map((s) => ({ id: s.id, properties: s.properties })),
    drive: { folder: ctx.folder ? { id: ctx.folder.id, name: ctx.folder.name, parents: ctx.folder.parents } : null,
      showcase: ctx.showcase ? { id: ctx.showcase.id, name: ctx.showcase.name, parent: ctx.showcase.parent } : null },
    portal: copied, gone, film_backup: filmBackup,
  };
  await putJson(w.env, `${at}backup.json`, backup);
  const check = await readJson(w.env, `${at}backup.json`);
  if (!check || check.move_id !== mv.id) throw new Error("the backup could not be read back; nothing was deleted");
  return backup;
}

async function runDelete(w, ctx, plan, mv) {
  const backup = await backupForDelete(w, ctx, plan, mv);
  mv.undo = { backup: `${BACKUPS}${mv.id}/backup.json`, done: [] };
  const done = mv.undo.done;
  const said = [];
  const failed = [];
  const step = async (what, fn) => {
    try { await fn(); done.push(what); said.push(what); await saveMove(w, mv); } catch (e) { failed.push(`${what}: ${String((e && e.message) || e).slice(0, 200)}`); }
  };
  for (const id of plan.shoots || []) await step(`shoot:${id}`, () => w.n.patch(`pages/${id}`, { in_trash: true }));
  if (ctx.notion) await step("notion", () => w.n.patch(`pages/${ctx.page}`, { in_trash: true }));
  if (ctx.showcase) await step("showcase", () => w.fenced.trash(ctx.showcase.id));
  if (ctx.folder) await step("folder", () => w.fenced.trash(ctx.folder.id));
  const relay = ctx.record && ctx.record.film && ctx.record.film.relay ? bare(ctx.record.film.relay) : "";
  for (const p of plan.prefixes || []) {
    await step(`portal:${p}`, async () => {
      if (!(p in backup.portal)) throw new Error("not backed up");
      // **Its tombstone first** (deletedguard.js): from here no clock writes
      // under it again (the refresh wrote ZZ Close Test's card back 98 s
      // after its delete, 2026-10-16). Undo takes it away.
      await putJson(w.env, tombstoneKey(p), { project: p, move_id: mv.id, at: w.now().toISOString(), by: w.by, name: ctx.name });
      await deletePrefix(w.env, keys.film(p));
      // The relay's own note: every device that has this film does the same
      // to its copy at its next sync (Studio moves it to the Mac's Trash).
      if (p === relay) await putJson(w.env, `gone/${p}.json`, { project: p, fate: "deleted", when: w.now().toISOString(), by: w.by });
    });
  }
  if (ctx.record) {
    await step("record", () => changeRecord(w.env, ctx.key, (r) => {
      const { moving: _m, ...rest } = r;
      return { ...rest, deleted: { at: w.now().toISOString(), by: w.by, move_id: mv.id } };
    }));
  }
  const words = failed.length ? `\nNot done: ${failed.join("; ")}` : "";
  return { said: `${ctx.name} deleted. Undo brings it back for 30 days.${words}`, failed };
}

async function runShowcase(w, ctx, plan, mv) {
  const drive = await import("./drivefolders.js");
  const settings = { ...(w.driveSettings || {}), scratch: ctx.scratch ? ctx.roots.top : null };
  // stills/ and select-stills/ only: website/ is his, by hand, never made here
  const sp = await drive.planShowcase(w.create, settings, { name: ctx.name, status: ctx.status, drive_url: ctx.driveUrl,
    parts: ["stills", "select-stills"] });
  if (!sp.ok) throw new Refusal(sp.why);
  const got = sp.steps.length ? await drive.carryOut(w.create, sp) : { made: [], ids: sp.ids, failed: [] };
  if (got.failed && got.failed.length) throw new Error(`Showcase not finished — ${got.failed.map((f) => `${f.key}: ${f.why}`).join("; ")}`);
  const scId = got.ids[sp.showcase];
  const folders = scId ? (await w.raw.list(scId)).filter((k) => k.folder) : [];
  const stills = childNamed(folders, "stills");
  const selectDir = childNamed(folders, "select-stills");
  const made = [...(got.made || [])];
  if (scId && !(await w.raw.list(scId)).some((k) => !k.folder && k.name === ".portfolio-project")) {
    await w.create.mkfile(scId, ".portfolio-project", "projects-console: this is a portfolio showcase folder\n");
    made.push(`${sp.showcase}/.portfolio-project`);
  }
  const cname = plan.credits_name || "credits.txt";
  if (scId && plan.credits && !childNamed(await w.raw.list(scId), cname)) {
    await w.create.mkfile(scId, cname, plan.credits);
    made.push(`${sp.showcase}/${cname}`);
  }
  // a select no longer picked moves into select-stills/z-archive/ (a move, never a delete)
  const moved = [];
  if (selectDir && Array.isArray(plan.archive) && plan.archive.length) {
    const here = await w.raw.list(selectDir.id);
    const todo = plan.archive.filter((a) => here.some((k) => k.id === a.id && !k.folder));
    // a file of the same-named twin folder stays where it is (the twin is not touched)
    if (todo.length) {
      let arch = childNamed(here.filter((k) => k.folder), "z-archive");
      if (!arch) { await w.create.mkdir(selectDir.id, "z-archive"); arch = childNamed((await w.raw.list(selectDir.id)).filter((k) => k.folder), "z-archive"); }
      if (!arch) throw new Error("select-stills/z-archive could not be made");
      for (const a of todo) { await w.fenced.move(a.id, selectDir.id, arch.id); moved.push(a.name); }
    }
  }
  mv.undo = null;
  const jobs = [];
  const make = Array.isArray(plan.make) ? plan.make : [];
  if (make.length && scId) {
    jobs.push(await queueJob(w, ctx, mv, "showcase-stills", `Showcase · ${ctx.name}`, {
      project_id: ctx.key, name: ctx.name, slug: plan.slug, files: make,
      showcase: { id: scId, path: sp.showcase.replace(/^\(scratch\)\/?/, ""), stills: stills && stills.id, select: selectDir && selectDir.id },
      scratch: ctx.scratch, root: ctx.roots.top,
    }, { needs: { tools: ["cwebp", "showcase-picks"] } }));
  }
  const n = make.length;
  return { said: `${sp.said}${moved.length ? ` ${plural(moved.length, "select")} moved to select-stills/z-archive.` : ""}${n ? ` ${plural(n, "picture")} to make on a Mac.` : ""}`, made, jobs };
}

// ── no trash but Delete ──────────────────────────────────────────────────────
//
// His rule (2026-10-15 morning): "nothing should be trashed during these
// moves". Every move but Delete, and every undo, runs on a world that cannot
// trash or delete: the Drive has no trash, Notion refuses `in_trash` /
// `archived`, and the bucket refuses delete. A step that tries stops the move
// (all-or-nothing puts back what was done) with these words.

export const TRASHES = new Set(["delete"]);
export class NoTrash extends Error {}

function noTrashSaid(kind, what) {
  return new NoTrash(`${KIND_WORDS[kind] || kind} never trashes or deletes anything (only Delete does). It stopped before: ${what}.`);
}

function noTrashDrive(api, kind) {
  if (!api) return api;
  return new Proxy(api, {
    get(t, k) {
      if (k === "trash" || k === "delete" || k === "remove") return async (id) => { throw noTrashSaid(kind, `Drive trash ${id}`); };
      const v = t[k];
      return typeof v === "function" ? v.bind(t) : v;
    },
  });
}

function trashingBody(body) {
  return Boolean(body && (body.in_trash === true || body.archived === true || body.trashed === true));
}

function noTrashNotion(n, kind) {
  if (!n) return n;
  return new Proxy(n, {
    get(t, k) {
      const v = t[k];
      if (k === "delete" || k === "del" || k === "remove") return async (path) => { throw noTrashSaid(kind, `Notion delete ${path}`); };
      if ((k === "patch" || k === "post" || k === "put") && typeof v === "function") {
        return async (path, body, ...rest) => {
          if (trashingBody(body)) throw noTrashSaid(kind, `Notion trash ${path}`);
          return v.call(t, path, body, ...rest);
        };
      }
      return typeof v === "function" ? v.bind(t) : v;
    },
  });
}

function noTrashEnv(env, kind) {
  if (!env || !env.BUCKET) return env;
  const bucket = new Proxy(env.BUCKET, {
    get(t, k) {
      if (k === "delete") return async (key) => { throw noTrashSaid(kind, `removing ${[].concat(key).join(", ")}`); };
      const v = t[k];
      return typeof v === "function" ? v.bind(t) : v;
    },
  });
  // A copy, not a Proxy: a Worker's bindings are read-only properties.
  const out = {};
  for (const k of Reflect.ownKeys(env)) if (k !== "BUCKET") out[k] = env[k];
  Object.defineProperty(out, "BUCKET", { value: bucket, enumerable: true });
  return out;
}

/** The world a move other than Delete runs on: it cannot trash or delete. */
export function noTrash(w, kind) {
  if (TRASHES.has(kind)) return w;
  return { ...w, env: noTrashEnv(w.env, kind), n: noTrashNotion(w.n, kind),
    raw: noTrashDrive(w.raw, kind), fenced: noTrashDrive(w.fenced, kind), create: noTrashDrive(w.create, kind) };
}

const RUNS = { wrap: runWrap, archive: runArchive, movedrive: runMoveDrive, rename: runRename,
  turnoff: runTurnOff, delete: runDelete, showcase: runShowcase };

const DESC = {
  wrap: (c, r) => `Wrapped ${c.name}${r.said ? ` — ${r.said}` : ""}`,
  archive: (c) => `Archived ${c.name}`,
  movedrive: (c, r) => `Moved ${c.name}'s Drive folder: ${r.said}`,
  rename: (c, r) => `Renamed ${r.said}`,
  turnoff: (c, r) => `Turned off on ${c.name}: ${r.said}`,
  delete: (c) => `Deleted ${c.name}`,
  showcase: (c) => `Prepared the showcase for ${c.name}`,
};

/**
 * The run: planned again from the world as it is this second (never from
 * what a screen held), refused with the look's words if anything is in the
 * way, locked, done, kept and logged.
 */
export async function run(w, asked, kind, opts = {}, { settings = null } = {}) {
  const s = settings || await settingsOf(w.env);
  const said = isObject(opts) ? opts : {};
  const seen = await look(w, asked, kind, said, { settings: s });
  if (!seen.ok) return seen;
  if (!seen.can_run) return { ok: false, kind, why: seen.problems.join(" "), problems: seen.problems };
  // A typed name is checked here too, whatever the screen did.
  if (seen.arm === "typed" && said.confirm !== undefined && String(said.confirm) !== seen.confirm) {
    return { ok: false, kind, why: "The name typed doesn't match." };
  }
  const ctx = await projectOf(w, asked, s);
  const roots = ctx.roots && ctx.roots.top ? ctx.roots : null;
  if (roots && w.raw) w.fenced = await fencedFor(w, roots);
  w = noTrash(w, kind);
  const mv = { id: moveId(), kind, at: w.now().toISOString(), by: w.by, project: { id: ctx.key, page: ctx.page, name: ctx.name },
    scratch: ctx.scratch, opts: said, plan: seen.plan || {}, undo: {}, jobs: [] };
  await lock(w, ctx, kind, mv.id);
  let result;
  try {
    result = await RUNS[kind](w, ctx, seen.plan || {}, mv, said);
  } catch (e) {
    await unlock(w, ctx, mv.id);
    if (e instanceof NoTrash) return { ok: false, kind, why: e.message };
    if (e instanceof Refusal) return { ok: false, kind, why: e.message, ...(e.stuck ? { stuck: e.stuck } : {}) };
    throw e;
  }
  if (kind !== "delete") await unlock(w, ctx, mv.id);
  mv.said = result.said;
  mv.lines = seen.lines.map((l) => ({ ...l, state: l.who === MAC || l.who === STUDIO_MAC ? "waiting" : l.tone === "keep" || l.tone === "note" ? "kept" : "done" }));
  for (const j of result.jobs || []) if (!j.queued) mv.lines.push({ text: `Not queued for a Mac: ${j.why}`, who: MAC, state: "failed" });
  await saveMove(w, mv);
  await logIt(w, mv, DESC[kind](ctx, result), kind !== "showcase");
  return { ok: !(result.failed && result.failed.length), kind, move_id: mv.id, report: result.said, lines: mv.lines,
    undo: kind !== "showcase", jobs: (result.jobs || []).filter((j) => j.queued).map((j) => j.id) };
}

// ── undo ─────────────────────────────────────────────────────────────────────

async function undoWrap(w, mv) {
  const u = mv.undo || {};
  const page = mv.project.page;
  // A part still waiting for Notion is simply taken off the list; one Notion
  // already has is put back, unless Notion is out of reach again, in which
  // case it waits to be put back (Status and dates follow the record).
  const pending = new Set(await dropWaits(w.env, u.waits || []));
  const back = [];
  const soft = async (fn, redo) => { try { await fn(); } catch (e) { if (!notionDown(e)) throw e; if (redo) back.push(redo); } };
  if (u.shoot && !(u.waits || []).some((id) => pending.has(id))) {
    await soft(() => w.n.patch(`pages/${u.shoot.id}`, statusProp(u.shoot.status)),
      { kind: "shoot-status", shoot: bare(u.shoot.id), status: u.shoot.status, label: "A shoot" });
  }
  if (u.dates && page) await soft(() => w.n.patch(`pages/${page}`, datesProp(u.dates.start, u.dates.end)));
  if (u.dates && u.record_dates !== null && u.record_dates !== undefined) await writeDatesFact(w, { key: mv.project.id, record: true }, u.record_dates);
  if (mv.plan.status) {
    if (page) await soft(() => w.n.patch(`pages/${page}`, statusProp(u.status)));
    await writeStatus(w, { key: mv.project.id, record: true }, u.record_status || u.status);
  }
  for (const x of back) await addWait(w.env, { ...x, project: mv.project.id, page: bare(page || ""), by: w.by });
  return `${mv.project.name} back to ${u.status || "its stage"}.${back.length || pending.size ? ` ${NOTION_WAITS}.` : ""}`;
}

async function fencedForMove(w, mv) {
  const s = await settingsOf(w.env);
  const roots = await rootsOf(w, mv.scratch ? scratchOf(w, s) : null);
  return fencedFor(w, roots);
}

async function undoArchive(w, mv) {
  const u = mv.undo || {};
  const api = await fencedForMove(w, mv);
  if (u.showcase) await api.move(u.showcase.id, u.showcase.to, u.showcase.from);
  if (u.folder) await api.move(u.folder.id, u.folder.to, u.folder.from);
  let waits = false;
  const stillWaiting = new Set(await dropWaits(w.env, u.waits || []));
  if (mv.project.page && !stillWaiting.size) {
    try { await w.n.patch(`pages/${mv.project.page}`, statusProp(u.status)); } catch (e) { if (!notionDown(e)) throw e; waits = true; }
  }
  await writeStatus(w, { key: mv.project.id, record: true }, u.record_status || u.status);
  return `${mv.project.name} is back where it was, ${u.status || "unarchived"}.${waits ? ` ${NOTION_WAITS}.` : ""}`;
}

async function undoMoveDrive(w, mv) {
  const u = mv.undo || {};
  const api = await fencedForMove(w, mv);
  await api.move(u.folder.id, u.folder.to, u.folder.from);
  return `${mv.project.name}'s Drive folder is back.`;
}

async function undoRename(w, mv) {
  const u = mv.undo || {};
  const api = await fencedForMove(w, mv);
  const steps = [];
  if (u.folder) steps.push({ what: "the Drive folder", do: () => api.rename(u.folder.id, u.folder.name) });
  if (u.showcase) steps.push({ what: "the showcase", do: () => api.rename(u.showcase.id, u.showcase.name) });
  const stillWaiting = new Set(await dropWaits(w.env, u.waits || []));
  if (mv.plan.new_name && mv.project.page && !(u.waits || []).some((id) => stillWaiting.has(id))) {
    const page = await w.n.get(`pages/${mv.project.page}`);
    const prop = titleProp((page || {}).properties);
    steps.push({ what: "the Notion title", do: () => w.n.patch(`pages/${mv.project.page}`, { properties: { [prop]: { title: [{ text: { content: u.name } }] } } }) });
  }
  if (u.record) {
    steps.push({ what: "the record", do: () => changeRecord(w.env, mv.project.id, (r) => {
      const back = { ...r, name: u.record.name, slug: u.record.slug, drive: u.record.drive };
      if (u.record.media_names === undefined) delete back.media_names; else back.media_names = u.record.media_names;
      return back;
    }) });
  }
  if (u.title !== undefined && u.title !== null) steps.push({ what: "the record's title", do: () => writeTitleFact(w, { key: mv.project.id }, u.title) });
  await allOrNothing(steps);
  return `${mv.project.name} has its old name back.`;
}

async function undoTurnOff(w, mv) {
  const u = mv.undo || {};
  if (u.showcase) {
    const api = await fencedForMove(w, mv);
    if (typeof u.showcase === "string") await api.untrash(u.showcase); // a move kept before the no-trash rule
    else await api.move(u.showcase.id, u.showcase.to, u.showcase.from);
    return "The showcase is back.";
  }
  await w.n.patch(`pages/${mv.project.page}`, { properties: { Website: { url: u.website } } });
  return "The website link is back.";
}

async function undoDelete(w, mv) {
  const u = mv.undo || {};
  const backup = await readJson(w.env, u.backup);
  if (!backup) throw new Refusal("The backup for this delete is missing.");
  const done = new Set(u.done || []);
  const api = (backup.drive.folder || backup.drive.showcase) ? await fencedForMove(w, mv) : null;
  if (done.has("record") && backup.record) {
    await changeRecord(w.env, mv.project.id, (r) => {
      const { deleted: _d, moving: _m, ...rest } = r;
      return rest;
    });
  }
  for (const p of Object.keys(backup.portal || {})) {
    if (!done.has(`portal:${p}`)) continue;
    // The notes that keep it gone come off first, so nothing refuses the copy back.
    await w.env.BUCKET.delete(tombstoneKey(p));
    await w.env.BUCKET.delete(`gone/${p}.json`);
    await copyPrefix(w.env, `${BACKUPS}${mv.id}/${keys.film(p)}`, keys.film(p));
    if (backup.gone && backup.gone[p]) await putJson(w.env, `gone/${p}.json`, backup.gone[p]);
  }
  if (done.has("folder") && backup.drive.folder) await api.untrash(backup.drive.folder.id);
  if (done.has("showcase") && backup.drive.showcase) await api.untrash(backup.drive.showcase.id);
  if (done.has("notion")) await w.n.patch(`pages/${mv.project.page}`, { in_trash: false });
  for (const s of backup.shoots || []) if (done.has(`shoot:${s.id}`)) await w.n.patch(`pages/${s.id}`, { in_trash: false });
  return `${mv.project.name} is back.`;
}

const UNDOS = { wrap: undoWrap, archive: undoArchive, movedrive: undoMoveDrive, rename: undoRename,
  turnoff: undoTurnOff, delete: undoDelete };

/**
 * Undo one move: within 30 days, once, its waiting Mac jobs cancelled first
 * (and refused while one is running), the project locked while it goes back.
 */
export async function undo(w, id) {
  const mv = await moveOf(w.env, id);
  if (!mv) return { ok: false, why: "No such move." };
  if (mv.undone) return { ok: false, why: "Already undone." };
  if (!UNDOS[mv.kind] || mv.undo === null) return { ok: false, why: "Nothing to undo: it only adds." };
  if (w.now().getTime() - Date.parse(mv.at) > UNDO_DAYS * DAY_MS) return { ok: false, why: `Too late to undo. Undo lasts ${UNDO_DAYS} days.` };
  if (w.jobs && w.jobs.READY) {
    const got = await w.jobs.cancelJobs(w.env, { move_id: mv.id, by: w.by });
    const running = got ? (Array.isArray(got.running) ? got.running.length : Number(got.running) || 0) : 0;
    if (running) return { ok: false, why: "A Mac is working on part of this move. Wait for it to finish." };
  }
  const key = mv.project.id;
  const rec = await readJson(w.env, `r/${key}/record.json`);
  const busy = rec && lockOf(rec, w.now().getTime());
  if (busy && busy.move_id !== mv.id) return { ok: false, why: busyWords(rec, w.now().getTime()) };
  const ctx = { key, record: rec };
  const holder = `${mv.id}-undo`;
  if (rec && mv.kind !== "delete") await lock(w, ctx, "undo", holder);
  let said;
  try {
    said = await UNDOS[mv.kind](noTrash(w, mv.kind), mv);
  } catch (e) {
    if (rec) await unlock(w, ctx, holder);
    if (e instanceof Refusal || e instanceof NoTrash) return { ok: false, why: e.message };
    throw e;
  }
  if (rec) await unlock(w, ctx, mv.kind === "delete" ? mv.id : holder);
  mv.undone = { at: w.now().toISOString(), by: w.by };
  await saveMove(w, mv);
  try {
    const { logActivity } = await import("./step6history.js");
    await logActivity(w.env, { kind: "bigmove-undo", desc: `Undid: ${KIND_WORDS[mv.kind]} ${mv.project.name}`, undo: null });
  } catch { /* the undo stands */ }
  return { ok: true, report: said, move_id: mv.id };
}

/** This project's moves, newest first (for an Undo list). */
export async function movesFor(env, projectId, { limit = 20 } = {}) {
  const want = bare(projectId);
  const out = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: MOVES, cursor, limit: 1000 });
    for (const o of page.objects || []) {
      const mv = await readJson(env, o.key);
      if (mv && (!want || mv.project.id === want || mv.project.page === want)) {
        out.push({ id: mv.id, kind: mv.kind, at: mv.at, by: mv.by, said: mv.said || "", undone: Boolean(mv.undone), project: mv.project });
      }
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out.sort((a, b) => (a.at < b.at ? 1 : -1)).slice(0, limit);
}

// ── the asks (cloud.js) ──────────────────────────────────────────────────────

function asked(list) {
  const a = Array.isArray(list) ? list : [];
  return { project: a[0], kind: String(a[1] || ""), opts: isObject(a[2]) ? a[2] : {}, by: isObject(a[2]) ? a[2].by : "" };
}

/** `async (list, env) → result`; a Handoff gives the ask to the Mac. */
export const ASKS = {
  async bigmove_look(list, env) {
    const a = asked(list);
    const w = await worldOf(env, { write: false, by: a.by });
    try { return await look(w, a.project, a.kind, a.opts); } catch (e) { if (e instanceof Refusal) return { ok: false, kind: a.kind, why: e.message }; throw e; }
  },
  async bigmove_run(list, env) {
    const a = asked(list);
    const w = await worldOf(env, { write: true, by: a.by });
    try { return await run(w, a.project, a.kind, a.opts); } catch (e) { if (e instanceof Refusal) return { ok: false, kind: a.kind, why: e.message }; throw e; }
  },
  async bigmove_undo(list, env) {
    const a = Array.isArray(list) ? list : [];
    const w = await worldOf(env, { write: true, by: isObject(a[1]) ? a[1].by : "" });
    return undo(w, String(a[0] || ""));
  },
};

/** Answer one ask, or `undefined` when it is not a big move's. */
export async function bigmoveAnswer(env, method, list) {
  if (!METHODS.has(method)) return undefined;
  const result = await ASKS[method](list, env);
  return { state: "done", result };
}

/** The methods answered now (any move's switch on). */
export async function bigmovesNow(env) {
  return (await anyOn(env)) ? [...METHODS] : [];
}

// ── the door ─────────────────────────────────────────────────────────────────

/**
 *   GET  /console/studio/bigmoves                     the switch {wrap, archive, …, scratch}
 *   PUT  /console/studio/bigmoves                     {wrap?: off|scratch|live, …, scratch?, by}
 *   POST /console/studio/bigmoves/look                {project, kind, opts} — the look, switch or no switch; writes nothing
 *   GET  /console/studio/bigmoves/moves?project=<id>  the project's moves, newest first
 *   GET  /console/studio/bigmoves/project/<id>        {deleted, at} — a deleted project's old id still answers
 *   POST /console/studio/bigmoves/leftovers           {dry (default true), project?, by} — files written back under a deleted project's old id, kept under its backup and taken away
 */
export async function door(env, rest, method, readBody, url) {
  if (rest.length === 1) {
    if (method === "GET") return Response.json({ switch: "bigmoves", ...(await settingsOf(env)) });
    if (method === "PUT") {
      const got = await setSettings(env, await readBody());
      return got.problem ? Response.json(got, { status: 400 }) : Response.json(got);
    }
    return null;
  }
  if (rest[1] === "look" && method === "POST") {
    const said = (await readBody()) || {};
    try {
      const w = await worldOf(env, { write: false });
      return Response.json(await look(w, said.project, String(said.kind || ""), said.opts || {}, { dry: true }));
    } catch (e) {
      return Response.json({ ok: false, why: String((e && e.message) || e).slice(0, 300) });
    }
  }
  if (rest[1] === "moves" && method === "GET") {
    return Response.json({ ok: true, moves: await movesFor(env, url ? url.searchParams.get("project") || "" : "") });
  }
  if (rest[1] === "leftovers" && method === "POST") {
    const said = (await readBody()) || {};
    return Response.json(await sweepLeftovers(env, { dry: said.dry !== false, project: String(said.project || ""), by: String(said.by || "").slice(0, 80) }));
  }
  if (rest[1] === "project" && rest[2] && method === "GET") {
    const { resolveProject } = await import("./projectid.js");
    const got = await resolveProject(env, rest[2]);
    if (!got.key) return Response.json({ ok: false, why: "No project by that ID." }, { status: 404 });
    const r = got.record || {};
    return Response.json({ ok: true, id: got.key, name: r.name || "", deleted: Boolean(r.deleted), ...(r.deleted ? { at: r.deleted.at } : {}) });
  }
  return null;
}

// ── a deleted project's leftovers (2026-10-17) ───────────────────────────────

/** What makes a prefix a project — never a leftover: its manifest, its portal mark, a change log. */
const PROJECT_FILE = /^(manifest\.json|portal\.json|logs\/)/;

/**
 * **Files written back under a deleted project's old id, taken away again**
 * (ZZ Close Test: a front page and twelve covers the refresh wrote 98 s after
 * its Delete, 2026-10-16). Only under a prefix a Delete removed (in its
 * backup) whose move is not undone, and only when nothing there is a project
 * file (manifest, portal mark, change log) — any of those and the prefix is
 * left alone and said. Each file is copied under the move's backup
 * (`<backup>/leftovers/<stamp>/`) and counted back before it goes, and the
 * prefix gets its tombstone (deletedguard.js) if it had none. `dry` writes
 * nothing; `project` narrows it to one id.
 */
export async function sweepLeftovers(env, { dry = true, project = "", by = "", now = () => new Date() } = {}) {
  const only = bare(project);
  const out = { ok: true, dry: Boolean(dry), swept: [], left: [], clean: 0 };
  const moves = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: MOVES, cursor, limit: 1000 });
    for (const o of page.objects || []) {
      const mv = await readJson(env, o.key);
      if (mv && mv.kind === "delete" && !mv.undone && mv.undo && mv.undo.backup) moves.push(mv);
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  for (const mv of moves) {
    const backup = await readJson(env, mv.undo.backup);
    const done = new Set(mv.undo.done || []);
    for (const p of Object.keys((backup && backup.portal) || {})) {
      if (only && p !== only) continue;
      if (!done.has(`portal:${p}`)) continue;
      const from = keys.film(p);
      const objects = [];
      let c;
      do {
        const page = await env.BUCKET.list({ prefix: from, cursor: c, limit: 1000 });
        objects.push(...(page.objects || []));
        c = page.truncated ? page.cursor : undefined;
      } while (c);
      const stone = await env.BUCKET.head(tombstoneKey(p));
      if (!objects.length) {
        out.clean += 1;
        if (!dry && !stone) await putJson(env, tombstoneKey(p), { project: p, move_id: mv.id, at: now().toISOString(), by, name: mv.project.name, later: true });
        continue;
      }
      const files = objects.map((o) => o.key.slice(from.length));
      const held = files.filter((f) => PROJECT_FILE.test(f));
      const row = { project: p, name: mv.project.name, move_id: mv.id, files };
      if (held.length) { out.left.push({ ...row, why: `holds a project file (${held.slice(0, 3).join(", ")}); left alone` }); continue; }
      if (dry) { out.swept.push(row); continue; }
      // The tombstone first, so nothing writes them back while they go.
      if (!stone) await putJson(env, tombstoneKey(p), { project: p, move_id: mv.id, at: now().toISOString(), by, name: mv.project.name, later: true });
      const at = `${BACKUPS}${mv.id}/leftovers/${now().toISOString().replace(/[:.]/g, "-")}/`;
      const n = await copyPrefix(env, from, `${at}${from}`);
      const back = await countPrefix(env, `${at}${from}`);
      if (back < n || n < objects.length) { out.ok = false; out.left.push({ ...row, why: "the copy came back short; nothing was removed" }); continue; }
      await putJson(env, `${at}leftovers.json`, { project: p, move_id: mv.id, at: now().toISOString(), by, files });
      for (let i = 0; i < objects.length; i += 1000) await env.BUCKET.delete(objects.slice(i, i + 1000).map((o) => o.key));
      out.swept.push({ ...row, kept: at });
    }
  }
  // **Its Notion-link questions too** (notionsync.js): a deleted project's
  // can never be settled. Kept in a copy before they go.
  if (!only) {
    const { dropDeadConflicts } = await import("./notionsync.js");
    const dead = await dropDeadConflicts(env, { dry: true });
    out.conflicts = dead.map((c) => ({ id: c.id, page: c.page, fields: Object.keys(c.changes || {}) }));
    if (!dry && dead.length) {
      const at = `${BACKUPS}conflicts/${now().toISOString().replace(/[:.]/g, "-")}.json`;
      await putJson(env, at, { at: now().toISOString(), by, conflicts: dead });
      const back = await readJson(env, at);
      if (!back || !Array.isArray(back.conflicts) || back.conflicts.length !== dead.length) { out.ok = false; out.conflicts_kept = null; return out; }
      await dropDeadConflicts(env, { dry: false });
      out.conflicts_kept = at;
    }
  }
  return out;
}

// ── shared with Close Project (step6shelf.js, 2026-10-15) ───────────────────
export { portalPrefixes, shootPages, copyPrefix, countPrefix, changeRecord, writeStatus, readJson as readBucketJson, putJson as putBucketJson };
