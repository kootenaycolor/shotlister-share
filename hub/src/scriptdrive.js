/**
 * **One script, from Drive** (stage 5 step 4, piece C, 2026-10-14).
 *
 * His rule: *the script draws from Google Drive, like all other files.* A
 * draft arrives as an emailed PDF; he saves it into the project's Drive
 * folder. The PDF's only home is Drive; the film keeps a copy for speed and
 * offline, never a second home.
 *
 * **Drive is the door.**
 *
 * - `1-creative/script/current-draft/` holds the draft in use, in a folder of
 *   its own so it is never mistaken; `1-creative/script/z-archive/` every older
 *   one (the template, `drivefolders.js`). **Only `current-draft/` is
 *   watched**: loose files in `script/` itself are ignored and never moved
 *   (his change, 2026-10-15).
 * - **More than one draft in `current-draft/`: he picks** (`pick`, "Pick the
 *   current draft" in Studio). The server never guesses which one.
 * - **Nothing updates by itself** (his rule: *"some things need a bit of
 *   manual touch, scene syncing"*). The server only notices that the script
 *   folder holds a newer PDF than the draft the film is using, and says so on
 *   the card (`script.new`). Studio shows **New draft in Drive**; he reviews
 *   the import (scenes, what changed against the shot list, cast), adjusts and
 *   confirms. Until then every app keeps showing the draft in use.
 * - **On confirm the old draft moves to `z-archive/`** (`settle`): every other
 *   PDF in `current-draft/` goes there; nothing is ever deleted, trashed or renamed.
 * - **Studio's own Import PDF is a second door** that files the PDF into
 *   `current-draft/` too (`fileIn`), then settles the same way, so Drive never falls
 *   behind.
 * - **Lined and compressed copies are outputs**, kept out of the script
 *   folder. One found there anyway is never taken for a draft, and never moved.
 * - **The script goes on and off with Shot List**: while the modes switch is
 *   on, a project with Shot List off is not looked at.
 *
 * **Which draft is "in use"** is the film's: its newest revision (the drafts
 * the portal's Script page lists, `front.scripts`). A Drive file is the same
 * draft when its bytes are (Drive's `md5Checksum` against the bucket's copy
 * of that draft's PDF, or the md5 kept when it was settled); with no bytes to
 * compare, when the file's name is the one the draft came from. A different
 * file is **new** only when Drive's copy changed after the draft in use came
 * in: an older file left in the folder is reported, never offered.
 *
 * **Off until thrown** (`s/script-drive.json`). Off, the cards carry no
 * `script`, Studio shows nothing new, and every door but the switch, the look
 * and the template's below refuses. **The look writes nothing**, ever.
 *
 *   GET  /console/studio/scriptdrive             the switch {on, at, by}
 *   PUT  /console/studio/scriptdrive             {on, by}
 *   POST /console/studio/script/look             {only?, wide?} — every project's script
 *                                                folder against its film; `wide` lists every
 *                                                script-looking PDF in the project folder too
 *   POST /console/studio/script/template         {dry} — the kept folder template gains
 *                                                `1-creative/script/`, `z-archive/`, `current-draft/`
 *   GET  /console/studio/script/<id>             what was last seen for one project
 *   POST /console/studio/script/<id>/check       look now, keep it, answer it
 *   GET  /console/studio/script/<id>/file/<f>    the PDF of a file in its script folder
 *   POST /console/studio/script/<id>/settle      {file?, stem, by} — the draft confirmed:
 *                                                the other PDFs in current-draft/ move to archive/
 *   PUT  /console/studio/script/<id>/upload      ?name&stem&by, the PDF as the body —
 *                                                Studio's Import files it into current-draft/
 *
 * **The Drive** is the `GDRIVE_WRITE` sign-in (full scope; `drivewrite.js`),
 * or for reading alone the portal's read-only `GDRIVE`. The few calls are
 * here and nowhere else: list, read one, download, make a folder, upload, and
 * **move from `script/current-draft/` to `script/z-archive/`** — the only move
 * the server makes anywhere, held to those two folders.
 */

import { accessToken, filesUrl, uploadUrl, DriveRefused } from "./drivewrite.js";
import { idFromUrl, folderUrl } from "./drivefolders.js";
import { studioOf, bare, ID, resolveProject } from "./projectid.js";
import { draftLabel, draftDate } from "./scriptlabel.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/script-drive.json";
export const STATE_KEY = "s/script-drive-state.json";
export const CHECK_EVERY_MINUTES = 10;
const FOLDER = "application/vnd.google-apps.folder";
const PDF = "application/pdf";
const FILE_ID = /^[A-Za-z0-9_-]{10,160}$/;
const MAX_UPLOAD = 60 * 1024 * 1024;

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function scriptDriveOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setScriptDrive(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── the rules ────────────────────────────────────────────────────────────────

/** A lined or compressed copy: an output, never a draft. */
export const isOutput = (name) => /(^|[^a-z])(lined|line[ _-]?script|compressed|compress|sides)([^a-z]|$)/i.test(String(name || ""));

/** A PDF that can be a draft: not a folder, not an output. */
export function isDraftFile(f) {
  if (!f || f.folder) return false;
  const pdf = f.mime === PDF || /\.pdf$/i.test(String(f.name || ""));
  return pdf && !isOutput(f.name);
}

const time = (s) => { const t = Date.parse(String(s || "")); return Number.isNaN(t) ? 0 : t; };

/** The script folder's files sorted: the draft in use first (newest change), then the rest. */
export function sortDrafts(files) {
  return (files || []).filter(isDraftFile).sort((a, b) => (time(b.modified) - time(a.modified))
    || (time(b.created) - time(a.created)) || String(a.name).localeCompare(String(b.name)));
}

/** A file's name as a draft is called: without `.pdf`. */
const stemName = (name) => String(name || "").replace(/\.pdf$/i, "").trim();
const baseName = (path) => String(path || "").split(/[\\/]/).pop().trim();

/** What a Drive file is called on the card: `Halcyon Pink · Oct 12, 2026`. */
export function fileLabel(f) {
  return [stemName(f && f.name) || "Script", draftDate(f && f.modified)].filter(Boolean).join(" · ");
}

/** The drafts as the film lists them (`film_card`'s `scripts`), newest first, one per file. */
export function draftsOf(raw) {
  const seen = new Set();
  return (Array.isArray(raw) ? raw : [])
    .filter((d) => d && /^[0-9a-f]{32}$/.test(String(d.stem || "")))
    .filter((d) => !seen.has(d.stem) && seen.add(d.stem))
    .map((d) => ({ stem: String(d.stem), name: String(d.name || ""), came_from: String(d.came_from || ""), dated: String(d.dated || "") }));
}

/**
 * The one draft in `current-draft/` against the draft in use:
 *
 *   none    no PDF in the folder
 *   same    the same draft (same bytes; else, with nothing to compare, the same name)
 *   new     a different file, changed after the draft in use came in (or no draft yet)
 *   older   a different file that is not newer: reported, never offered
 */
export function compare(active, inUse) {
  if (!active) return "none";
  if (!inUse) return "new";
  if (active.md5 && inUse.md5) {
    if (active.md5 === inUse.md5) return "same";
  } else if (stemName(active.name).toLowerCase() === stemName(baseName(inUse.came_from)).toLowerCase()) {
    return "same";
  }
  return time(active.modified) > time(inUse.dated) ? "new" : "older";
}

/** The card's few words for a project, from what was last seen. */
export function cardScript(row) {
  if (!isObject(row)) return null;
  const u = row.in_use;
  const n = row.status === "new" && row.active ? row.active : null;
  const pick = row.status === "pick" && Array.isArray(row.choices)
    ? row.choices.map((f) => ({ file: f.id, name: f.name, label: fileLabel(f), modified: f.modified, same: f.same === true }))
    : null;
  return {
    label: u ? u.label : "",
    name: u ? u.name : "",
    dated: u ? u.dated : "",
    new: n ? { file: n.id, name: n.name, label: fileLabel(n), modified: n.modified } : null,
    pick,
    folder: row.folder && (row.folder.current || row.folder.script) ? folderUrl(row.folder.current || row.folder.script) : "",
    checked: row.checked || "",
  };
}

// ── the Drive ────────────────────────────────────────────────────────────────

const FIELDS = "id,name,mimeType,trashed,parents,md5Checksum,modifiedTime,createdTime,size";
const item = (f) => ({
  id: f.id, name: String(f.name || ""), folder: f.mimeType === FOLDER, mime: f.mimeType || "",
  parents: f.parents || [], md5: f.md5Checksum || "", modified: f.modifiedTime || "", created: f.createdTime || "",
  size: Number(f.size || 0),
});

/**
 * The few Drive calls the script needs. `write: false` reads with
 * `GDRIVE_WRITE` or else `GDRIVE`, and has nothing else. Null with no sign-in.
 */
export function scriptDrive(env, { write = false } = {}) {
  const secret = env.GDRIVE_WRITE ? "GDRIVE_WRITE" : (!write && env.GDRIVE ? "GDRIVE" : "");
  if (!secret) return null;
  async function raw(url, init = {}) {
    const access = await accessToken(env, secret);
    try {
      return await fetch(url, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${access}` } });
    } catch (e) {
      throw new Error(`couldn't reach Google Drive (${e && e.message})`);
    }
  }
  async function call(url, init = {}) {
    const got = await raw(url, init);
    if (got.status === 404) return null;
    if (got.status === 401 || got.status === 403) throw new DriveRefused(`Google Drive refused (${got.status}): ${(await got.text()).slice(0, 200)}`);
    if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
    return got.json();
  }
  const checked = (id) => {
    if (!/^[A-Za-z0-9_-]{5,160}$/.test(String(id || ""))) throw new Error(`not a Drive id: ${String(id).slice(0, 40)}`);
    return id;
  };
  const api = {
    secret,
    async list(parent) {
      checked(parent);
      const out = [];
      let page = "";
      do {
        const q = `'${parent}' in parents and trashed = false`;
        const got = await call(`${filesUrl(env)}?q=${encodeURIComponent(q)}&fields=${encodeURIComponent(`nextPageToken,files(${FIELDS})`)}`
          + `&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`);
        if (!got) return out;
        out.push(...(got.files || []).filter((f) => !f.trashed).map(item));
        page = got.nextPageToken || "";
      } while (page);
      return out;
    },
    async get(id) {
      const got = await call(`${filesUrl(env)}/${checked(id)}?fields=${encodeURIComponent(FIELDS)}&supportsAllDrives=true`);
      return got && !got.trashed ? item(got) : null;
    },
    /** The file's bytes, as Google's response (streamed through, never kept). */
    async download(id) {
      const got = await raw(`${filesUrl(env)}/${checked(id)}?alt=media&supportsAllDrives=true`);
      if (!got.ok) throw new Error(`Google Drive answered ${got.status} for the file`);
      return got;
    },
  };
  if (write && secret === "GDRIVE_WRITE") {
    api.mkdir = async (parent, name) => {
      const got = await call(`${filesUrl(env)}?fields=${encodeURIComponent(FIELDS)}&supportsAllDrives=true`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, mimeType: FOLDER, parents: [checked(parent)] }),
      });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      return item(got);
    };
    /** A PDF into a folder, by Google's resumable upload (any size). */
    api.upload = async (parent, name, bytes) => {
      const start = await raw(`${uploadUrl(env)}?uploadType=resumable&supportsAllDrives=true&fields=${encodeURIComponent(FIELDS)}`, {
        method: "POST",
        headers: { "content-type": "application/json; charset=UTF-8", "x-upload-content-type": PDF, "x-upload-content-length": String(bytes.length) },
        body: JSON.stringify({ name, parents: [checked(parent)], mimeType: PDF }),
      });
      if (!start.ok) throw new Error(`Google Drive would not start the upload (${start.status}): ${(await start.text()).slice(0, 200)}`);
      const where = start.headers.get("location");
      if (!where) throw new Error("Google Drive gave no upload address");
      const put = await raw(where, { method: "PUT", headers: { "content-type": PDF }, body: bytes });
      if (!put.ok) throw new Error(`Google Drive did not take ${name} (${put.status}): ${(await put.text()).slice(0, 200)}`);
      const got = await put.json();
      if (!got || !got.id) throw new Error(`Google Drive did not take ${name}`);
      return item(got);
    };
    /**
     * **The one move**: a file from `script/current-draft/` into
     * `script/z-archive/`. The ids are checked by the caller against the
     * listings it just read.
     */
    api.archive = async (file, current, archive) => {
      const got = await call(`${filesUrl(env)}/${checked(file)}?addParents=${checked(archive)}&removeParents=${checked(current)}`
        + `&fields=${encodeURIComponent(FIELDS)}&supportsAllDrives=true`, {
        method: "PATCH", headers: { "content-type": "application/json" }, body: "{}",
      });
      if (!got || !got.id) throw new Error("Google Drive did not move it");
      return item(got);
    };
  }
  return api;
}

/** The child of that name: the exact spelling first, else any case. Folders only. */
function folderNamed(kids, name) {
  const folders = kids.filter((k) => k.folder);
  return folders.find((k) => k.name === name) || folders.find((k) => k.name.toLowerCase() === name.toLowerCase()) || null;
}

/** The project's Drive folder id, from its record (`drive_folder`). */
export function projectFolderOf(record) {
  const facts = isObject(record && record.facts) ? record.facts : {};
  const one = facts.drive_folder;
  const url = isObject(one) && typeof one.value === "string" ? one.value : String((record && record.drive_url) || "");
  return idFromUrl(url);
}

/**
 * `{project, creative, script, current, archive}` — the ids found, "" where
 * missing — plus what `current-draft/` and `z-archive/` hold, and the names of
 * loose files in `script/` itself (reported, never read as drafts).
 */
export const CURRENT = "current-draft";
export const ARCHIVE = "z-archive";
export async function readFolders(api, projectFolder) {
  const out = { folder: { project: projectFolder, creative: "", script: "", current: "", archive: "" }, files: [], archived: [], loose: [] };
  const top = await api.list(projectFolder);
  const creative = folderNamed(top, "1-creative");
  if (!creative) return out;
  out.folder.creative = creative.id;
  const script = folderNamed(await api.list(creative.id), "script");
  if (!script) return out;
  out.folder.script = script.id;
  const inside = await api.list(script.id);
  out.loose = inside.filter((f) => !f.folder).map((f) => f.name);
  const archive = folderNamed(inside, ARCHIVE) || folderNamed(inside, "archive");  // older folders may still say `archive`
  if (archive) {
    out.folder.archive = archive.id;
    out.archived = (await api.list(archive.id)).filter((f) => !f.folder);
  }
  const current = folderNamed(inside, CURRENT);
  if (current) {
    out.folder.current = current.id;
    out.files = (await api.list(current.id)).filter((f) => !f.folder);
  }
  return out;
}

// ── the film's side ──────────────────────────────────────────────────────────

/** The film's drafts, newest first (`film_card`, cached per change). */
async function filmDrafts(env, relay, ctx) {
  const { cardOf } = await import("./live.js");
  const card = await cardOf(env, relay, ctx);
  return draftsOf(card && card.scripts);
}

const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

/** The md5 of a draft's PDF as the bucket holds it: R2 keeps one for a plain upload. */
async function bucketMd5(env, relay, stem) {
  const { keys } = await import("../../relay/layout.js");
  const head = await env.BUCKET.head(keys.inFolder(relay, "media", `${stem}.pdf`));
  if (!head) return "";
  const sums = head.checksums || {};
  if (sums.md5) return typeof sums.md5 === "string" ? sums.md5 : hex(sums.md5);
  const tag = String(head.etag || head.httpEtag || "").replace(/"/g, "");
  return /^[0-9a-f]{32}$/.test(tag) ? tag : "";
}

const defaults = (deps = {}) => ({
  api: deps.api,
  drafts: deps.drafts || filmDrafts,
  md5: deps.md5 || bucketMd5,
});

// ── the state (what was last seen) ───────────────────────────────────────────

export async function readState(env) {
  const v = await readJson(env, STATE_KEY);
  return { projects: isObject(v && v.projects) ? v.projects : {} };
}

async function keepRows(env, rows) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const got = await env.BUCKET.get(STATE_KEY);
    let now = { projects: {} };
    if (got) { try { const v = await got.json(); if (isObject(v && v.projects)) now = v; } catch { /* start again */ } }
    for (const row of rows) now.projects[row.id] = row;
    const put = await env.BUCKET.put(STATE_KEY, JSON.stringify(now), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: got && got.etag ? { etagMatches: got.etag } : { etagDoesNotMatch: "*" },
    });
    if (put) return true;
  }
  return false;
}

// ── one project ──────────────────────────────────────────────────────────────

const shotListOn = async (env, record) => {
  const { modesOn, resolveModes } = await import("./studiomodes.js");
  if (!(await modesOn(env)).on) return true;
  return resolveModes(record).modes.includes("shot_list");
};

/**
 * **One project's script folder against its film.** Writes nothing. `kept`
 * is what was last seen (its settled md5 stands in for the bucket's when it
 * names the same draft).
 */
export async function lookAt(env, key, record, ctx, deps = {}, kept = null) {
  const d = defaults(deps);
  const row = { id: key, name: String(record.name || ""), relay: studioOf(record), checked: new Date().toISOString(), status: "" };
  if (!(await shotListOn(env, record))) return { ...row, status: "off" };
  const folder = projectFolderOf(record);
  if (!folder) return { ...row, status: "no-drive" };
  if (!d.api) return { ...row, status: "no-signin" };
  let found;
  try { found = await readFolders(d.api, folder); } catch (e) {
    return { ...row, status: "trouble", trouble: String((e && e.message) || e).slice(0, 300) };
  }
  row.folder = found.folder;
  const drafts = sortDrafts(found.files);
  const active = drafts[0] || null;
  row.active = active ? { id: active.id, name: active.name, md5: active.md5, modified: active.modified, size: active.size } : null;
  row.older = drafts.slice(1).map((f) => ({ id: f.id, name: f.name, modified: f.modified }));
  row.others = found.files.filter((f) => !isDraftFile(f)).map((f) => f.name);
  row.loose = found.loose;
  row.archived = found.archived.length;
  let inUse = null;
  if (row.relay) {
    try {
      const list = await d.drafts(env, row.relay, ctx);
      const latest = list[0];
      const k = kept && kept.in_use;
      if (k && k.md5 && active && active.md5 === k.md5 && k.stem && !list.some((x) => x.stem === k.stem)) {
        // Settled moments ago from Studio, whose logs have not reached the
        // bucket yet: the draft just confirmed is the one in use.
        inUse = { ...k };
      } else if (latest) {
        const settled = kept && kept.in_use && kept.in_use.stem === latest.stem ? kept.in_use.md5 || "" : "";
        inUse = { stem: latest.stem, name: latest.name, came_from: latest.came_from, dated: latest.dated, label: draftLabel(latest),
          md5: settled || (await d.md5(env, row.relay, latest.stem).catch(() => "")) };
      }
      row.drafts = list.length;
    } catch (e) {
      row.trouble = `couldn't read the film: ${String((e && e.message) || e).slice(0, 200)}`;
    }
  }
  row.in_use = inUse;
  if (!found.folder.current) {
    row.status = "no-folder";
  } else if (drafts.length > 1) {
    // More than one draft in current-draft/: he picks, the server never guesses.
    row.status = "pick";
    row.choices = drafts.map((f) => ({ id: f.id, name: f.name, md5: f.md5, modified: f.modified, same: compare(f, inUse) === "same" }));
  } else {
    row.status = compare(active, inUse);
  }
  return row;
}

async function recordOf(env, id) {
  const found = await resolveProject(env, id);
  if (!found.key || !isObject(found.record)) return null;
  return found;
}

/** Look now at one project, keep it, answer it. The switch must be on. */
export async function checkOne(env, id, ctx, deps = {}) {
  if (!(await scriptDriveOn(env)).on) return { ok: false, status: 409, why: "The script's Drive folder is switched off on the server." };
  const found = await recordOf(env, id);
  if (!found) return { ok: false, status: 404, why: "No project with that ID." };
  const api = deps.api !== undefined ? deps.api : scriptDrive(env);
  const kept = (await readState(env)).projects[found.key] || null;
  const row = await lookAt(env, found.key, found.record, ctx, { ...deps, api }, kept);
  await keepRows(env, [row]);
  return { ok: true, row, script: cardScript(row) };
}

// ── every project ────────────────────────────────────────────────────────────

async function recordKeys(env) {
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const k = p.split("/")[1];
      if (ID.test(k)) keys.push(k);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return keys;
}

/** A script-looking name: the step 9 listing's net. */
const SCRIPTY = /script|screenplay|draft|revision|shooting/i;

/**
 * **Every script-looking PDF in the project folder**, and where (step 9 will
 * pick each project's current script once). Read only, three folders deep.
 */
export async function scriptFilesIn(api, projectFolder, depth = 4) {
  const out = [];
  async function walk(id, path, left) {
    for (const f of await api.list(id)) {
      const at = path ? `${path}/${f.name}` : f.name;
      if (f.folder) {
        if (left > 0 && !/^(3-post|4-financial)$/i.test(f.name)) await walk(f.id, at, left - 1);
        continue;
      }
      const pdf = f.mime === PDF || /\.pdf$/i.test(f.name);
      if (!pdf && f.mime !== "application/vnd.google-apps.document") continue;
      if (!SCRIPTY.test(at)) continue;
      out.push({ path: at, modified: f.modified, kind: isOutput(f.name) ? "output" : pdf ? "pdf" : "google-doc" });
    }
  }
  await walk(projectFolder, "", depth);
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

/**
 * **The dry look**: every project's script folder against its film, as the
 * clock would see it, and (`wide`) every script-looking file in each project
 * folder. Writes nothing at all, switch or no switch.
 */
export async function scriptLook(env, ctx, { only = "", wide = false } = {}, deps = {}) {
  const api = deps.api !== undefined ? deps.api : scriptDrive(env);
  const want = bare(only);
  const kept = await readState(env);
  const rows = [];
  for (const key of await recordKeys(env)) {
    if (want && key !== want) continue;
    const record = await readJson(env, `r/${key}/record.json`);
    if (!isObject(record)) continue;
    const row = await lookAt(env, key, record, ctx, { ...deps, api }, kept.projects[key] || null);
    if (wide && api && row.folder && row.folder.project) {
      try { row.files_found = await scriptFilesIn(api, row.folder.project); } catch (e) { row.files_trouble = String((e && e.message) || e).slice(0, 200); }
    }
    rows.push(row);
  }
  const count = (s) => rows.filter((r) => r.status === s).length;
  return {
    at: new Date().toISOString(), dry: true, signin: api ? api.secret : "none", projects: rows.length,
    new: count("new"), pick: count("pick"), same: count("same"), older: count("older"), none: count("none"),
    no_folder: count("no-folder"), no_drive: count("no-drive"), off: count("off"), trouble: count("trouble"), rows,
  };
}

/** **The clock**: every ten minutes while the switch is on, each project looked at and kept. */
export async function onScriptTimer(env, ctx, when = Date.now(), deps = {}) {
  if (new Date(when).getUTCMinutes() % CHECK_EVERY_MINUTES !== 5) return { skipped: "not this minute" };
  if (!(await scriptDriveOn(env)).on) return { skipped: "off" };
  const api = deps.api !== undefined ? deps.api : scriptDrive(env);
  if (!api) return { skipped: "no sign-in" };
  const kept = await readState(env);
  const rows = [];
  for (const key of await recordKeys(env)) {
    const record = await readJson(env, `r/${key}/record.json`);
    if (!isObject(record) || record.job) continue;
    rows.push(await lookAt(env, key, record, ctx, { ...deps, api }, kept.projects[key] || null));
  }
  await keepRows(env, rows);
  return { looked: rows.length, new: rows.filter((r) => r.status === "new").length };
}

// ── confirming ───────────────────────────────────────────────────────────────

/** `script/` with `z-archive/` and `current-draft/` in it, made where missing — inside the project's own folder only. */
async function ensureFolders(api, projectFolder) {
  const got = await readFolders(api, projectFolder);
  const f = got.folder;
  const made = [];
  if (!f.creative) { f.creative = (await api.mkdir(projectFolder, "1-creative")).id; made.push("1-creative"); }
  if (!f.script) { f.script = (await api.mkdir(f.creative, "script")).id; made.push("1-creative/script"); }
  if (!f.archive) { f.archive = (await api.mkdir(f.script, ARCHIVE)).id; made.push("1-creative/script/z-archive"); }
  if (!f.current) { f.current = (await api.mkdir(f.script, CURRENT)).id; made.push(`1-creative/script/${CURRENT}`); got.files = []; }
  return { ...got, made };
}

/**
 * **The draft confirmed**: `keep` stays in `current-draft/`; every other draft
 * PDF there moves to `z-archive/`. Outputs, anything not a PDF, and loose files
 * in `script/` itself stay where they are. Answers what moved.
 */
async function archiveAllBut(api, folders, keep) {
  const moved = [];
  for (const f of sortDrafts(folders.files)) {
    if (f.id === keep) continue;
    if (!(f.parents || []).includes(folders.folder.current) && f.parents && f.parents.length) continue;
    await api.archive(f.id, folders.folder.current, folders.folder.archive);
    moved.push(f.name);
  }
  return moved;
}

async function writeReady(env, id, deps) {
  if (!(await scriptDriveOn(env)).on) return { why: "The script's Drive folder is switched off on the server.", status: 409 };
  const found = await recordOf(env, id);
  if (!found) return { why: "No project with that ID.", status: 404 };
  const api = deps.api !== undefined ? deps.api : scriptDrive(env, { write: true });
  if (!api || !api.archive) return { why: "The server can't write to Google Drive.", status: 409 };
  const folder = projectFolderOf(found.record);
  if (!folder) return { why: "This project has no Drive folder.", status: 409 };
  return { found, api, folder };
}

/** What is kept once a draft is in use: the row as now seen, the confirmed draft standing in until the film's logs arrive. */
async function settledRow(env, found, ctx, deps, api, file, stem) {
  const dated = new Date().toISOString();
  const confirmed = { stem, name: stemName(file.name), came_from: file.name, dated, md5: file.md5 || "" };
  confirmed.label = draftLabel(confirmed);
  return lookAt(env, found.key, found.record, ctx, { ...deps, api }, { in_use: confirmed });
}

/**
 * `{file?, stem, by}` — Studio took a draft in. With `file` (a draft from
 * Drive, or the one he picked), that file stays and the rest of
 * `current-draft/` moves to `z-archive/`. Without, the one draft there stays;
 * with more than one there and no `file`, nothing moves (he picks).
 */
export async function settle(env, id, said, ctx, deps = {}) {
  const s = isObject(said) ? said : {};
  const ready = await writeReady(env, id, deps);
  if (ready.why) return { ok: false, status: ready.status, why: ready.why };
  const { found, api, folder } = ready;
  const stem = /^[0-9a-f]{32}$/.test(String(s.stem || "")) ? String(s.stem) : "";
  const folders = await ensureFolders(api, folder);
  const drafts = sortDrafts(folders.files);
  if (!s.file && drafts.length > 1) return { ok: false, status: 409, why: "More than one draft in current-draft. Pick the current draft." };
  let keep = drafts[0] || null;
  if (s.file) {
    if (!FILE_ID.test(String(s.file))) return { ok: false, status: 400, why: "Not a Drive file." };
    keep = drafts.find((f) => f.id === s.file) || null;
    if (!keep) return { ok: false, status: 409, why: "That draft is no longer in current-draft." };
  }
  if (!keep) return { ok: false, status: 409, why: "current-draft is empty." };
  const moved = await archiveAllBut(api, folders, keep.id);
  const row = await settledRow(env, found, ctx, deps, api, keep, stem);
  await keepRows(env, [row]);
  return { ok: true, kept: keep.name, archived: moved, made: folders.made, script: cardScript(row) };
}

/**
 * **Studio's Import, filed into Drive** (`?name&stem`, the PDF as the body).
 * The same bytes already in `current-draft/` are not sent twice; otherwise the PDF
 * goes in, and the folder settles on it.
 */
export async function fileIn(env, id, bytes, { name = "", stem = "" } = {}, ctx, deps = {}) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 5) return { ok: false, status: 400, why: "No PDF." };
  if (bytes.length > MAX_UPLOAD) return { ok: false, status: 413, why: "That PDF is too big." };
  if (String.fromCharCode(...bytes.slice(0, 5)) !== "%PDF-") return { ok: false, status: 400, why: "That isn't a PDF." };
  const ready = await writeReady(env, id, deps);
  if (ready.why) return { ok: false, status: ready.status, why: ready.why };
  const { found, api, folder } = ready;
  const folders = await ensureFolders(api, folder);
  const md5 = deps.md5Of ? await deps.md5Of(bytes) : await md5Hex(bytes);
  let keep = md5 ? sortDrafts(folders.files).find((f) => f.md5 === md5) : null;
  const sent = !keep;
  if (!keep) {
    let named = baseName(name).replace(/[\u0000-\u001f]/g, "").slice(0, 200) || "Script.pdf";
    if (!/\.pdf$/i.test(named)) named += ".pdf";
    keep = await api.upload(folders.folder.current, named, bytes);
    folders.files.push(keep);
  }
  const moved = await archiveAllBut(api, folders, keep.id);
  const row = await settledRow(env, found, ctx, deps, api, { ...keep, md5: keep.md5 || md5 }, /^[0-9a-f]{32}$/.test(stem) ? stem : "");
  await keepRows(env, [row]);
  return { ok: true, file: keep.id, kept: keep.name, sent, archived: moved, made: folders.made, script: cardScript(row) };
}

/** Workers can digest MD5; elsewhere (a checking run) the caller hands one in. */
async function md5Hex(bytes) {
  try { return hex(await crypto.subtle.digest("MD5", bytes)); } catch { return ""; }
}

/** A draft's PDF from the project's `current-draft/` (or `z-archive/`), streamed through. */
export async function fileOut(env, id, fileId, deps = {}) {
  if (!(await scriptDriveOn(env)).on) return { ok: false, status: 409, why: "The script's Drive folder is switched off on the server." };
  if (!FILE_ID.test(String(fileId || ""))) return { ok: false, status: 400, why: "Not a Drive file." };
  const found = await recordOf(env, id);
  if (!found) return { ok: false, status: 404, why: "No project with that ID." };
  const api = deps.api !== undefined ? deps.api : scriptDrive(env);
  if (!api) return { ok: false, status: 409, why: "The server can't read Google Drive." };
  const folder = projectFolderOf(found.record);
  if (!folder) return { ok: false, status: 409, why: "This project has no Drive folder." };
  const folders = await readFolders(api, folder);
  const inside = [...folders.files, ...folders.archived].find((f) => f.id === fileId);
  if (!inside || !isDraftFile(inside)) return { ok: false, status: 404, why: "That file isn't in the script folder." };
  const got = await api.download(fileId);
  return { ok: true, name: inside.name, response: got };
}

// ── the template ─────────────────────────────────────────────────────────────

/** The kept folder template gains the script's folders (once each; `dry` says what it would do). */
export async function addScriptFolders(env, { dry = true, by = "server" } = {}) {
  const { templateOf, changeTemplate } = await import("./foldertemplate.js");
  const { withScriptFolders } = await import("./drivefolders.js");
  const now = await templateOf(env);
  const want = withScriptFolders(now.drive);
  const adds = want.filter((p) => !now.drive.includes(p));
  if (!adds.length) return { ok: true, already: true, v: now.v };
  if (dry) return { ok: true, dry: true, adds, v: now.v, drive: want };
  const got = await changeTemplate(env, { drive: want, base: now.v, by });
  if (got.problem) return { ok: false, why: got.problem };
  if (got.moved) return { ok: false, why: "The template changed meanwhile. Try again." };
  return { ok: true, adds, v: got.v };
}

// ── the door ─────────────────────────────────────────────────────────────────

export async function scriptDoor(env, request, rest, ctx, deps = {}) {
  const method = request.method;
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  const body = async (limit = 4096) => {
    try {
      const text = await request.text();
      if (text.length > limit) return null;
      const v = text ? JSON.parse(text) : {};
      return isObject(v) ? v : null;
    } catch { return null; }
  };
  if (rest[0] === "scriptdrive" && rest.length === 1) {
    if (method === "GET") return reply(await scriptDriveOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    return reply(await setScriptDrive(env, said));
  }
  if (rest[0] !== "script" || rest.length < 2) return null;
  const run = async (fn) => {
    try { return await fn(); } catch (e) {
      const refused = e instanceof DriveRefused;
      return reply({ ok: false, why: refused ? "Google Drive refused." : String((e && e.message) || e).slice(0, 300) }, refused ? 409 : 500);
    }
  };
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    return run(async () => reply(await scriptLook(env, ctx, { only: String(said.only || "").slice(0, 64), wide: said.wide === true }, deps)));
  }
  if (rest.length === 2 && rest[1] === "template") {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    const got = await addScriptFolders(env, { dry: said.dry !== false, by: String(said.by || "server").slice(0, 80) });
    return reply(got, got.ok ? 200 : 409);
  }
  const id = rest[1];
  if (rest.length === 2) {
    if (method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    const found = await recordOf(env, id);
    if (!found) return reply({ ok: false, why: "No project with that ID." }, 404);
    const [sw, state] = await Promise.all([scriptDriveOn(env), readState(env)]);
    const row = state.projects[found.key] || null;
    return reply({ ok: true, on: sw.on, id: found.key, row, script: sw.on ? cardScript(row) : null });
  }
  if (rest.length === 3 && rest[2] === "check") {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    return run(async () => { const got = await checkOne(env, id, ctx, deps); return reply(got, got.status || 200); });
  }
  if (rest.length === 3 && rest[2] === "settle") {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    return run(async () => { const got = await settle(env, id, said, ctx, deps); return reply(got, got.status || 200); });
  }
  if (rest.length === 3 && rest[2] === "upload") {
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    const size = Number(request.headers.get("content-length") || 0);
    if (size > MAX_UPLOAD) return reply({ ok: false, why: "That PDF is too big." }, 413);
    const url = new URL(request.url);
    const bytes = new Uint8Array(await request.arrayBuffer());
    return run(async () => {
      const got = await fileIn(env, id, bytes, { name: url.searchParams.get("name") || "", stem: url.searchParams.get("stem") || "" }, ctx, deps);
      return reply(got, got.status || 200);
    });
  }
  if (rest.length === 4 && rest[2] === "file") {
    if (method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    return run(async () => {
      const got = await fileOut(env, id, rest[3], deps);
      if (!got.ok) return reply(got, got.status || 200);
      const safe = got.name.replace(/[^\x20-\x7e]/g, "_").replace(/"/g, "'");
      return new Response(got.response.body, {
        headers: { "content-type": PDF, "content-disposition": `inline; filename="${safe}"`, "cache-control": "no-store", "x-script-name": encodeURIComponent(got.name) },
      });
    });
  }
  return reply({ ok: false, problem: "No such door." }, 404);
}
