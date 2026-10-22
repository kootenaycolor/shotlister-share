/**
 * **The Camera Spec Sheet as a Google Sheet in the project's Drive folder,
 * kept current by the server** (2026-10-15). The rules and the layout are
 * `specsheetsheet.js`; this reads a project's spec sheets off its record,
 * talks to Google, remembers what it wrote, and hangs it on a switch and the
 * portal's two-minute clock.
 *
 *   GET  /console/studio/specsheetsheet             the switch {mode, root, only}, ready, last sweep
 *   PUT  /console/studio/specsheetsheet             {mode: off|scratch|live, root?, only?, by}
 *   GET  /console/studio/specsheetsheet/look?id=…   what a run would do; writes nothing
 *   GET  /console/studio/specsheetsheet/xlsx?id=…   the workbook as .xlsx bytes; writes nothing
 *   GET  /console/studio/specsheetsheet/manifest?id=…[&mode=]  what the server remembers Drive holding
 *   POST /console/studio/specsheetsheet/run  {id}   one project now (switch on only); 202 at once, runs on beside it ({wait:true} to hear)
 *   POST /console/studio/specsheetsheet/tick        the clock's sweep, now ({wait:true}, {force:true})
 *
 * **Where it goes.** `<project>/2-logistics/camera-spec/live-sheet/<slug>-
 * camera-spec-sheet` (the filing rules, as the shot list's `live-sheet/` is).
 * `camera-spec/` itself is for his own camera PDFs and spreadsheets; the one
 * the server keeps current sits alone in `live-sheet/`. An older project's
 * logistics folder is found by name (`3-logistics`, …) like the copier finds
 * its homes; whatever is missing is made, never anything moved or removed.
 *
 * **The change is the debounce.** Nothing here runs in a save. The clock
 * (every two minutes) builds each project's workbook from its record, hashes
 * the words in it (the "Updated" time left out), and only a project whose hash
 * differs from the one last written is touched: a burst of edits within the
 * two minutes is one rewrite. A workbook that did not change is not
 * rewritten, so the Drive file's history is not filled with identical versions.
 *
 * **Never deletes.** The Drive here is `{list, get, mkdir, create, replace}`:
 * no trash, no delete, no move, no rename. A sheet he trashes by hand is made
 * again at the next change; one he moves or renames is still found by its id.
 * Media drives are not involved at all.
 *
 * **Three stages, off until thrown** (`s/specsheetsheet.json`), as the
 * picture copies are:
 * - `off` — nothing is written; the look still answers.
 * - `scratch` — into `<root>/<project>/2-logistics/camera-spec/live-sheet/`, a
 *   throwaway folder, for the first real writes. Only projects in `only` run.
 * - `live` — each project's own Drive folder (the record's Drive Folder link);
 *   `only`, when set, still narrows it.
 * Scratch and live keep separate manifests (`s/specsheetsheet/<mode>/<id>.json`)
 * and a manifest made for another folder is never trusted.
 */

import { accessToken, filesUrl, uploadUrl } from "./drivewrite.js";
import { resolveProject, bare, ID } from "./projectid.js";
import { idFromUrl, slugify } from "./drivefolders.js";
import { recordSheets } from "./specsheet.js";
import * as S from "./specsheetsheet.js";

export const SWITCH_KEY = "s/specsheetsheet.json";
const LAST_KEY = "s/specsheetsheet-last.json";
const LOCK_KEY = "s/specsheetsheet-run.json";
const LOCK_MS = 4 * 60 * 1000;
export const TICK_MS = 80 * 1000;
export const MANUAL_MS = 18 * 1000;
export const MODES = ["off", "scratch", "live"];
export const HOME = ["2-logistics", "camera-spec", "live-sheet"];
const FOLDER = "application/vnd.google-apps.folder";
const JSON_TYPE = { httpMetadata: { contentType: "application/json" } };
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const DRIVE_ID = /^[A-Za-z0-9_-]{10,160}$/;

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export function settingsShape(raw) {
  const v = isObject(raw) ? raw : {};
  return {
    mode: MODES.includes(v.mode) ? v.mode : "off",
    root: DRIVE_ID.test(String(v.root || "")) ? String(v.root) : "",
    only: Array.isArray(v.only) ? v.only.map(bare).filter((x) => ID.test(x)) : [],
    at: v.at || null, by: v.by || null,
  };
}

export async function settingsOf(env) {
  return settingsShape(await readJson(env, SWITCH_KEY));
}

/** Whether a run may write: {ok, why}. */
export function readiness(s, { signin }) {
  if (s.mode === "off") return { ok: false, why: "the switch is off" };
  if (!signin) return { ok: false, why: "the server has no Google sign-in that can write" };
  if (s.mode === "scratch" && !s.root) return { ok: false, why: "scratch needs a scratch folder (root)" };
  return { ok: true, why: "" };
}

export function changedSettings(now, said) {
  const s = isObject(said) ? said : {};
  const next = { ...now };
  if ("mode" in s) {
    if (!MODES.includes(s.mode)) return { problem: "mode is off, scratch or live." };
    next.mode = s.mode;
  }
  if ("root" in s) {
    if (s.root !== "" && !DRIVE_ID.test(String(s.root))) return { problem: "root is a Drive folder id." };
    next.root = String(s.root);
  }
  if ("only" in s) {
    if (!Array.isArray(s.only) || !s.only.every((x) => ID.test(bare(x)))) return { problem: "only is a list of project ids." };
    next.only = s.only.map(bare);
  }
  next.at = new Date().toISOString();
  next.by = String(s.by || "").slice(0, 80);
  return next;
}

const manifestKey = (mode, key) => `s/specsheetsheet/${mode}/${key}.json`;

// ── the project and its workbook ─────────────────────────────────────────────

/** `{key, name, slug, record, drive}` for any id the project is known by, or null. */
export async function projectOf(env, id) {
  const got = await resolveProject(env, bare(id));
  if (!got.key) return null;
  const r = got.record || {};
  const facts = isObject(r.facts) ? r.facts : {};
  const link = isObject(facts.drive_folder) ? String(facts.drive_folder.value || "") : "";
  const title = isObject(facts.title) ? String(facts.title.value || "") : "";
  return { key: got.key, name: String(r.name || title || ""), slug: String(r.slug || ""), record: r, drive: idFromUrl(link) };
}

/** Whether the record has any spec sheet: the cheap look a sweep gives every project. */
const hasSheet = (p) => Object.keys(isObject(p.record.facts) ? p.record.facts : {}).some((k) => /^spec_(?:project|[0-9a-f]{32})$/.test(k));

/** The lens library, stored shape, or null. */
async function libraryOf(env) {
  try {
    const { readLibrary } = await import("./lenslibrary.js");
    return (await readLibrary(env)).library;
  } catch { return null; }
}

/** The project's tabs (time left out): `[]` when it has no spec sheet. */
export async function tabsFor(env, p, lib, updated = "") {
  const facts = isObject(p.record.facts) ? p.record.facts : {};
  const sheets = recordSheets(facts);
  if (!Object.keys(sheets).length) return [];
  const shoots = isObject(facts.shoots) && Array.isArray(facts.shoots.value) ? facts.shoots.value : [];
  let lensEntry = null;
  try { lensEntry = (await import("./lenslibrary.js")).entryOfSheetLens; } catch { lensEntry = null; }
  return S.tabsOf({ name: p.name, sheets, shoots, lib, lensEntry }, updated);
}

// ── Google ───────────────────────────────────────────────────────────────────

/** The few calls the sheet needs, with `GDRIVE_WRITE`: no trash, delete, move or rename. Null with no write sign-in. */
export function sheetDrive(env) {
  if (!env.GDRIVE_WRITE) return null;
  const secret = "GDRIVE_WRITE";
  async function call(url, init = {}) {
    const access = await accessToken(env, secret);
    let got;
    try {
      got = await fetch(url, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${access}` } });
    } catch (e) {
      throw new Error(`couldn't reach Google Drive (${e && e.message})`);
    }
    if (got.status === 404) throw Object.assign(new Error("Google Drive has no such file"), { gone: true });
    if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
    return got.json();
  }
  const enc = new TextEncoder();
  const fields = `fields=${encodeURIComponent("id,name,mimeType,trashed")}&supportsAllDrives=true`;
  const item = (f) => ({ id: f.id, name: String(f.name || ""), folder: f.mimeType === FOLDER, mime: f.mimeType || "", trashed: Boolean(f.trashed) });
  return {
    async list(parent) {
      const out = [];
      let page = "";
      do {
        const q = `'${parent}' in parents and trashed = false`;
        const got = await call(`${filesUrl(env)}?q=${encodeURIComponent(q)}&fields=${encodeURIComponent("nextPageToken,files(id,name,mimeType,trashed)")}`
          + `&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`);
        out.push(...(got.files || []).map(item));
        page = got.nextPageToken || "";
      } while (page);
      return out;
    },
    async get(id) {
      try {
        return item(await call(`${filesUrl(env)}/${encodeURIComponent(id)}?${fields}`));
      } catch (e) {
        if (e.gone) return null;
        throw e;
      }
    },
    async mkdir(parent, name) {
      return item(await call(`${filesUrl(env)}?${fields}`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, mimeType: FOLDER, parents: [parent] }),
      }));
    },
    /** A new native Google Sheet, converted by Drive from the .xlsx bytes. */
    async create(parent, name, bytes) {
      const boundary = `specsheet${crypto.randomUUID().replace(/-/g, "")}`;
      const head = enc.encode(`--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify({ name, mimeType: S.SHEET_TYPE, parents: [parent] })}\r\n--${boundary}\r\ncontent-type: ${S.XLSX_TYPE}\r\n\r\n`);
      const tail = enc.encode(`\r\n--${boundary}--`);
      const body = new Uint8Array(head.length + bytes.length + tail.length);
      body.set(head, 0); body.set(bytes, head.length); body.set(tail, head.length + bytes.length);
      const got = await call(`${uploadUrl(env)}?uploadType=multipart&${fields}`, { method: "POST", headers: { "content-type": `multipart/related; boundary=${boundary}` }, body });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      return item(got);
    },
    /** The Sheet's contents replaced in place, its id and link kept. */
    async replace(id, bytes) {
      const got = await call(`${uploadUrl(env)}/${encodeURIComponent(id)}?uploadType=media&${fields}`, { method: "PATCH", headers: { "content-type": S.XLSX_TYPE }, body: bytes });
      if (!got || !got.id) throw new Error("Google Drive did not take the new contents");
      return item(got);
    },
  };
}

const lower = (s) => String(s).toLowerCase();
const namedFolder = (kids, name) => kids.filter((k) => k.folder).find((k) => lower(k.name) === name) || null;

/**
 * Find (or, with `make`, make) the folder the sheet sits in:
 * `2-logistics/camera-spec/live-sheet`. The logistics folder is the exact name
 * first, else an older spine's by word (`3-logistics`). {id, path, made[]}; with
 * `make` false, `id` is "" when something is missing and `made` lists what would be.
 */
export async function findHome(drive, rootId, { make = false } = {}) {
  const made = [];
  const top = await drive.list(rootId);
  let logistics = namedFolder(top, HOME[0]) || top.filter((k) => k.folder && !k.name.startsWith(".")).find((k) => /logistic/i.test(k.name)) || null;
  let path = logistics ? logistics.name : HOME[0];
  if (!logistics) {
    made.push(HOME[0]);
    if (make) logistics = await drive.mkdir(rootId, HOME[0]);
  }
  let parent = logistics;
  for (const name of HOME.slice(1)) {
    const kids = parent ? await drive.list(parent.id) : [];
    let one = namedFolder(kids, name);
    path += `/${one ? one.name : name}`;
    if (!one) {
      made.push(path);
      one = make && parent ? await drive.mkdir(parent.id, name) : null;
    }
    parent = one;
  }
  return { id: parent ? parent.id : "", path, made };
}

// ── the run ──────────────────────────────────────────────────────────────────

/** Where this project's sheet goes: its own folder (live), or its own folder in the scratch one. */
async function rootFor(drive, s, p, { make }) {
  if (s.mode === "live") return p.drive ? { id: p.drive } : { why: "the project has no Drive Folder link" };
  const name = slugify(p.name) || p.key;
  const kids = await drive.list(s.root);
  const there = kids.find((k) => k.folder && lower(k.name) === name);
  if (there) return { id: there.id };
  if (!make) return { id: "", would: `${name}/` };
  const got = await drive.mkdir(s.root, name);
  return { id: got.id, made: name };
}

const linkOf = (id) => `https://docs.google.com/spreadsheets/d/${id}/edit`;

/**
 * One project. Writes only when the workbook's words differ from the ones last
 * written (or the folder changed). {ok, id, name, status, …}.
 */
export async function runOne(env, ctx, id, { force = false } = {}) {
  const s = await settingsOf(env);
  const ready = readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
  if (!ready.ok) return { ok: false, why: ready.why };
  const p = await projectOf(env, id);
  if (!p) return { ok: false, why: "No project by that ID." };
  if (!hasSheet(p)) return { ok: true, id: p.key, name: p.name, status: "no spec sheet" };
  const lib = await libraryOf(env);
  const quiet = await tabsFor(env, p, lib, "");
  const hash = await S.contentHash(quiet);
  const drive = sheetDrive(env);
  const key = manifestKey(s.mode, p.key);
  const before = await readJson(env, key);
  let root;
  try {
    root = await rootFor(drive, s, p, { make: true });
  } catch (e) {
    return { ok: false, id: p.key, name: p.name, why: String((e && e.message) || e).slice(0, 300) };
  }
  if (!root.id) return { ok: false, id: p.key, name: p.name, why: root.why };
  const held = before && before.root === root.id && before.mode === s.mode ? before : null;
  if (!force && held && held.hash === hash && held.file && held.file.id) return { ok: true, id: p.key, name: p.name, status: "unchanged", link: held.link };
  try {
    const home = await findHome(drive, root.id, { make: true });
    const name = S.fileNameOf(p.slug, p.name);
    const tabs = await tabsFor(env, p, lib, S.updatedWords(new Date()));
    const bytes = S.xlsxOf(tabs);
    // the file this project's sheet already is: the one remembered, else one
    // of the same name already in the folder (adopted, never made twice)
    let file = null;
    if (held && held.file && held.file.id) {
      const got = await drive.get(held.file.id);
      if (got && !got.trashed && got.mime === S.SHEET_TYPE) file = got;
    }
    if (!file) {
      const kids = await drive.list(home.id);
      file = kids.find((k) => !k.folder && k.mime === S.SHEET_TYPE && lower(k.name) === name) || null;
    }
    let status;
    if (file) { await drive.replace(file.id, bytes); status = "updated"; }
    else { file = await drive.create(home.id, name, bytes); status = "created"; }
    const out = { project: p.key, name: p.name, mode: s.mode, root: root.id, folder: home.id, path: home.path,
      file: { id: file.id, name: file.name }, link: linkOf(file.id), hash, tabs: tabs.map((t) => t.name), at: new Date().toISOString() };
    await env.BUCKET.put(key, JSON.stringify(out), JSON_TYPE);
    return { ok: true, id: p.key, name: p.name, status, link: out.link, path: home.path, tabs: out.tabs, ...(home.made.length ? { made: home.made } : {}) };
  } catch (e) {
    return { ok: false, id: p.key, name: p.name, why: String((e && e.message) || e).slice(0, 300) };
  }
}

/** What a run would do, writing nothing. */
export async function look(env, id) {
  const s = await settingsOf(env);
  const p = await projectOf(env, id);
  if (!p) return { ok: false, why: "No project by that ID." };
  const lib = await libraryOf(env);
  const tabs = await tabsFor(env, p, lib, "");
  const mode = s.mode === "off" ? "live" : s.mode;
  const held = await readJson(env, manifestKey(mode, p.key));
  const hash = tabs.length ? await S.contentHash(tabs) : "";
  return {
    ok: true, id: p.key, name: p.name, drive_folder: p.drive || null, switch: s.mode, against: mode,
    ready: readiness(s, { signin: Boolean(env.GDRIVE_WRITE) }),
    file: S.fileNameOf(p.slug, p.name), where: HOME.join("/"),
    tabs: tabs.map((t) => ({ name: t.name, fact: t.fact, rows: t.rows.length })),
    links: tabs.flatMap((t) => t.rows.flat().filter((c) => c.link).map((c) => ({ tab: t.name, text: c.text, url: c.link }))),
    hash, held: held ? { hash: held.hash, at: held.at, link: held.link, current: held.hash === hash } : null,
    would: !tabs.length ? "nothing (no spec sheet)" : held && held.hash === hash ? "nothing (unchanged)" : held ? "update the sheet" : "make the sheet",
  };
}

/** The projects a sweep looks at: `only`, else (live) every record. */
async function sweepList(env, s) {
  if (s.only.length) return s.only;
  if (s.mode !== "live") return [];
  const out = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const pre of got.delimitedPrefixes || []) {
      const k = pre.split("/")[1];
      if (ID.test(k)) out.push(k);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return out;
}

async function locked(env, fn) {
  const lock = await env.BUCKET.get(LOCK_KEY);
  let held = null;
  if (lock) { try { held = await lock.json(); } catch { held = null; } }
  if (held && Date.parse(held.until) > Date.now()) return null;
  const took = await env.BUCKET.put(LOCK_KEY, JSON.stringify({ until: new Date(Date.now() + LOCK_MS).toISOString(), by: crypto.randomUUID() }), {
    ...JSON_TYPE, onlyIf: lock ? { etagMatches: lock.etag } : { etagDoesNotMatch: "*" },
  });
  if (!took) return null;
  try { return await fn(); } finally { await env.BUCKET.delete(LOCK_KEY); }
}

async function remember(env, mode, projects) {
  const last = { at: new Date().toISOString(), mode, projects };
  await env.BUCKET.put(LAST_KEY, JSON.stringify(last), JSON_TYPE);
  return last;
}

/**
 * The clock's sweep (every two minutes): each project whose workbook changed.
 * A project with nothing to write costs a record read and a hash. The last
 * sweep is remembered only when it did something or failed.
 */
export async function sweep(env, ctx, { force = false, ms = TICK_MS } = {}) {
  const s = await settingsOf(env);
  if (s.mode === "off") return { ran: false, why: "the switch is off" };
  const ready = readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
  if (!ready.ok) return { ran: false, why: ready.why };
  const deadline = Date.now() + ms;
  const done = await locked(env, async () => {
    const projects = [];
    for (const id of await sweepList(env, s)) {
      if (Date.now() >= deadline) { projects.push({ id, waiting: true }); continue; }
      let got;
      try { got = await runOne(env, ctx, id, { force }); } catch (e) { got = { ok: false, id, why: String((e && e.message) || e).slice(0, 300) }; }
      if (got.status === "unchanged" || got.status === "no spec sheet") continue;
      projects.push(got);
    }
    return projects.length ? remember(env, s.mode, projects) : { at: new Date().toISOString(), mode: s.mode, projects };
  });
  return done ? { ran: true, ...done } : { ran: false, why: "a sweep is already running" };
}

/** One project by hand, holding the same lock as the clock. */
export async function runLocked(env, ctx, id, { force = true } = {}) {
  const s = await settingsOf(env);
  const out = await locked(env, async () => {
    const one = await runOne(env, ctx, id, { force });
    await remember(env, s.mode, [one]);
    return one;
  });
  return out || { ok: false, why: "a sweep is already running" };
}

// ── the door ─────────────────────────────────────────────────────────────────

const answer = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function specsheetsheetDoor(env, rest, method, readBody, ctx, url) {
  if (rest[0] !== "specsheetsheet") return null;
  const show = async () => {
    const s = await settingsOf(env);
    return { ...s, ready: readiness(s, { signin: Boolean(env.GDRIVE_WRITE) }), signin: env.GDRIVE_WRITE ? "write" : "none", last: await readJson(env, LAST_KEY) };
  };
  if (rest.length === 1) {
    if (method === "GET") return answer(await show());
    if (method !== "PUT") return answer({ problem: "Wrong method." }, 405);
    let said;
    try { said = await readBody(); } catch { return answer({ problem: "That is not JSON." }, 400); }
    const next = changedSettings(await settingsOf(env), said);
    if (next.problem) return answer(next, 400);
    await env.BUCKET.put(SWITCH_KEY, JSON.stringify(next), JSON_TYPE);
    return answer(await show());
  }
  const id = String((url && url.searchParams.get("id")) || "");
  if (rest[1] === "look" && rest.length === 2) {
    if (method !== "GET") return answer({ problem: "Wrong method." }, 405);
    return answer(await look(env, id));
  }
  if (rest[1] === "xlsx" && rest.length === 2) {
    if (method !== "GET") return answer({ problem: "Wrong method." }, 405);
    const p = await projectOf(env, id);
    if (!p) return answer({ ok: false, why: "No project by that ID." }, 404);
    const tabs = await tabsFor(env, p, await libraryOf(env), S.updatedWords(new Date()));
    if (!tabs.length) return answer({ ok: false, why: "The project has no spec sheet." }, 404);
    return new Response(S.xlsxOf(tabs), { headers: { "content-type": S.XLSX_TYPE, "cache-control": "no-store" } });
  }
  if (rest[1] === "manifest" && rest.length === 2) {
    if (method !== "GET") return answer({ problem: "Wrong method." }, 405);
    const p = await projectOf(env, id);
    if (!p) return answer({ ok: false, why: "No project by that ID." }, 404);
    const mode = String(url.searchParams.get("mode") || (await settingsOf(env)).mode);
    if (!["scratch", "live"].includes(mode)) return answer({ ok: false, why: "mode is scratch or live." }, 400);
    return answer({ ok: true, id: p.key, mode, manifest: await readJson(env, manifestKey(mode, p.key)) });
  }
  if (rest[1] === "run" && rest.length === 2) {
    if (method !== "POST") return answer({ problem: "Wrong method." }, 405);
    let said = {};
    try { said = (await readBody()) || {}; } catch { return answer({ problem: "That is not JSON." }, 400); }
    if (said.wait === true || (url && url.searchParams.get("wait") === "1")) return answer(await runLocked(env, ctx, String(said.id || "")));
    const s = await settingsOf(env);
    const ready = readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
    if (!ready.ok) return answer({ ok: false, why: ready.why });
    ctx.waitUntil(runLocked(env, ctx, String(said.id || "")).catch((e) => console.error(e && e.stack ? e.stack : String(e))));
    return answer({ ok: true, started: true, id: String(said.id || ""), note: "Running in the background; the result is in GET /specsheetsheet under last." }, 202);
  }
  if (rest[1] === "tick" && rest.length === 2) {
    if (method !== "POST") return answer({ problem: "Wrong method." }, 405);
    let said = {};
    try { said = (await readBody()) || {}; } catch { said = {}; }
    if (said.wait === true || (url && url.searchParams.get("wait") === "1")) return answer(await sweep(env, ctx, { ms: said.ms || MANUAL_MS, force: said.force === true }));
    const s = await settingsOf(env);
    const ready = readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
    if (!ready.ok) return answer({ ran: false, why: ready.why });
    ctx.waitUntil(sweep(env, ctx, { ms: MANUAL_MS, force: said.force === true }).catch((e) => console.error(e && e.stack ? e.stack : String(e))));
    return answer({ ran: true, started: true, note: "Running in the background; the result is in GET /specsheetsheet under last." }, 202);
  }
  return answer({ problem: "No such door." }, 404);
}
