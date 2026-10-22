/**
 * **Released and Close Project** (2026-10-15, his design: mockup
 * claude.ai/artifact/7qejyP7j2dxSgLNsY1X59i, findings v3).
 *
 * - **Released** is a plain status pick (cloud.js `set_stage`). Its card and
 *   page read the record's facts — `released_date`, `my_credit` (default
 *   "Cinematographer"), `selects` (Drive file ids he picked, 10–20) and
 *   `key_still` — and the stills come from the showcase's `stills/` folder
 *   (`stills/hq/` when there is one — his call 2026-10-17, "the default
 *   opening thing to be the project showcase's stills HQ folder, if there is
 *   an HQ" — else `stills/lq/`, else `stills/` itself; `matted/` is skipped).
 *   Read only: nothing in the Drive is copied, moved or renamed.
 * - **Close Project** takes a project out of the console and the portal. It
 *   writes the project's snapshot (the record, the Notion row and its Shoots
 *   rows, the Drive ids, the portal's own pages) as a file, `<slug>.project`,
 *   into the project's Drive folder, and keeps the same snapshot and a copy of
 *   the portal's own files hidden on the server (`closed/<key>/<stamp>/`).
 *   Nothing is deleted anywhere: the portal's files stay where they are behind
 *   a mark (`closed/portal/<id>.json`) that makes every sent link answer
 *   "This project is closed." at the same address. The record keeps
 *   `closed: {at, by, reason, status_before, file, hidden, portal}` and its
 *   status becomes Closed (Notion's Status follows). Media drives are never
 *   named here.
 * - **Reopen Project** takes the marks away and puts the status back.
 *
 * A step 6 group (step6.js): its switch `s/step6-shelf.json`.
 */

import {
  worldOf, projectOf, settingsOf, busyWords, Refusal,
  portalPrefixes, shootPages, changeRecord, writeStatus, readBucketJson, putBucketJson,
} from "./bigmoves.js";

export const SWITCH = "step6shelf";
import { keys } from "../../relay/layout.js";
export const SWITCH_KEY = "s/step6-shelf.json";
export const METHODS = new Set(["close_look", "close_project", "reopen_project", "closed_projects", "released_stills"]);
export const NOW = new Set(["close_look", "closed_projects", "released_stills"]);
export const LATER_WRITES = new Set(["close_project", "reopen_project"]);
export const LATER_READS = new Set([]);

export const REASONS = ["Not Produced"];
export const FILE_EXT = ".project";
export const FILE_KIND = "projects-console.project";
export const CLOSED = "closed/";
export const MARKS = "closed/portal/";
/** The portal's own files are copied; the film's logs, marks and pictures stay put. */
const FILM_PARTS = ["logs/", "devices/", "media/"];
const INLINE_MAX = 256 * 1024;
const INLINE_TOTAL = 4 * 1024 * 1024;
const IMAGE = /\.(jpe?g|png|webp|tiff?|heic)$/i;
const ID32 = /^[0-9a-f]{32}$/;
const PORTAL_ID = /^[0-9a-f]{8,64}$/;
const DRIVE_ID = /^[A-Za-z0-9_-]{10,120}$/;

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();
const factOf = (record, k) => {
  const f = record && isObject(record.facts) ? record.facts[k] : null;
  return isObject(f) ? f.value : undefined;
};

// ── the gate the portal asks ─────────────────────────────────────────────────

/** The closed mark for a portal id (a film's relay id, a record key, a page), or null. */
export async function closedMark(env, id) {
  const x = bare(id);
  if (!PORTAL_ID.test(x) || !env || !env.BUCKET) return null;
  const got = await env.BUCKET.get(`${MARKS}${x}.json`);
  if (!got) return null;
  try { return await got.json(); } catch { return { closed: true }; }
}

// ── the record's own ids ─────────────────────────────────────────────────────

function idsOf(key, record, extra = []) {
  const film = record && isObject(record.film) ? record.film : {};
  const out = [key, record && record.notion_page, record && record.page, film.relay, ...extra].map(bare).filter((x) => PORTAL_ID.test(x));
  return [...new Set(out)];
}

function statusOf(ctx) {
  const kept = factOf(ctx.record, "status");
  return (typeof kept === "string" && kept) || ctx.status || "";
}

// ── Close ────────────────────────────────────────────────────────────────────

export async function closeLook(env, id, { world = null } = {}) {
  const w = world || await worldOf(env, { write: false });
  let ctx;
  try { ctx = await projectOf(w, id, await settingsOf(env)); } catch (e) { if (e instanceof Refusal) return { ok: false, why: e.message }; throw e; }
  const problems = [];
  if (!ctx.record) problems.push("This project has no record yet.");
  else if (ctx.record.closed || statusOf(ctx) === "Closed") problems.push("This project is already closed.");
  const busy = ctx.record ? busyWords(ctx.record) : "";
  if (busy) problems.push(busy);
  const slug = ctx.slug || "";
  return {
    ok: true, id: ctx.key, name: ctx.name, status: statusOf(ctx),
    file: ctx.folder ? `${slug || "project"}${FILE_EXT}` : "",
    folder: ctx.place ? ctx.place.path : "",
    reasons: REASONS, can_run: !problems.length, problems,
  };
}

/** Every object under a prefix, listed. */
async function listAll(env, prefix) {
  const out = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000 });
    out.push(...(page.objects || []));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out;
}

/**
 * The portal's own files of each portal id copied under `hidden`, and the
 * small written ones (people, front, visible, views, pages) read into the
 * snapshot. Throws when a copy comes up short: nothing has been changed yet.
 */
async function keepPortal(env, prefixes, hidden) {
  const files = {};
  const pages = {};
  let inlined = 0;
  for (const p of prefixes) {
    const from = keys.film(p);
    const all = await listAll(env, from);
    const wanted = all.filter((o) => {
      const rest = o.key.slice(from.length);
      return rest && rest !== "manifest.json" && !FILM_PARTS.some((f) => rest.startsWith(f));
    });
    let n = 0;
    for (const o of wanted) {
      const got = await env.BUCKET.get(o.key);
      if (!got) continue;
      const rest = o.key.slice(from.length);
      const type = (got.httpMetadata && got.httpMetadata.contentType) || "";
      const small = (o.size || 0) <= INLINE_MAX && inlined + (o.size || 0) <= INLINE_TOTAL
        && (/json|text|markdown|html/.test(type) || /\.(json|md|txt|html)$/i.test(rest));
      if (small) {
        const text = await got.text();
        pages[`${from}${rest}`] = text;
        inlined += text.length;
        await env.BUCKET.put(`${hidden}${from}${rest}`, text, { httpMetadata: got.httpMetadata, customMetadata: got.customMetadata });
      } else {
        await env.BUCKET.put(`${hidden}${from}${rest}`, got.body, { httpMetadata: got.httpMetadata, customMetadata: got.customMetadata });
      }
      n += 1;
    }
    const back = (await listAll(env, `${hidden}${from}`)).length;
    if (back < n) throw new Error("the portal's copy came up short; nothing was changed");
    files[p] = { kept: n, film: all.length - wanted.length };
  }
  return { files, pages };
}

/** A file name not already in the folder: `<slug>.project`, else dated. */
async function freeName(api, folderId, slug, day) {
  const want = `${slug}${FILE_EXT}`;
  let kids = [];
  try { kids = await api.list(folderId); } catch { kids = []; }
  const names = new Set(kids.map((k) => k.name));
  if (!names.has(want)) return want;
  for (let i = 1; i < 50; i++) {
    const n = `${slug}-${day}${i > 1 ? `-${i}` : ""}${FILE_EXT}`;
    if (!names.has(n)) return n;
  }
  return `${slug}-${Date.now()}${FILE_EXT}`;
}

export async function closeRun(env, id, opts = {}, { world = null } = {}) {
  const said = isObject(opts) ? opts : {};
  const by = String(said.by || "Projects Console").slice(0, 80);
  const reason = REASONS.includes(said.reason) ? said.reason : REASONS[0];
  const w = world || await worldOf(env, { write: true, by });
  let ctx;
  try { ctx = await projectOf(w, id, await settingsOf(env)); } catch (e) { if (e instanceof Refusal) return { ok: false, why: e.message }; throw e; }
  if (!ctx.record) return { ok: false, why: "This project has no record yet." };
  if (ctx.record.closed) return { ok: false, why: "This project is already closed." };
  const busy = busyWords(ctx.record);
  if (busy) return { ok: false, why: busy };
  const now = w.now();
  const at = now.toISOString();
  const day = at.slice(0, 10).replace(/-/g, "");
  const hidden = `${CLOSED}${ctx.key}/${at.replace(/[:.]/g, "-")}/`;
  const before = statusOf(ctx);
  const prefixes = await portalPrefixes(w, ctx);
  const ids = idsOf(ctx.key, ctx.record, [ctx.page, ...prefixes]);

  // 1. The hidden copy and the snapshot, checked, before anything changes.
  const { files, pages } = await keepPortal(env, prefixes, hidden);
  let shoots = [];
  if (ctx.page) {
    try { shoots = (await shootPages(w, ctx.page)).map((s) => ({ id: s.id, properties: s.properties })); } catch { shoots = []; }
  }
  const slug = ctx.slug || String(ctx.record.slug || "") || "project";
  const snapshot = {
    kind: FILE_KIND, version: 1,
    closed: { at, by, reason },
    id: ctx.key, page: ctx.page, name: ctx.name, slug, status_before: before,
    record: ctx.record,
    notion: ctx.notion ? { id: ctx.notion.id, properties: ctx.notion.properties, icon: ctx.notion.icon || null } : null,
    shoots,
    drive: {
      folder: ctx.folder ? { id: ctx.folder.id, name: ctx.folder.name, path: ctx.place ? ctx.place.path : "" } : null,
      showcase: ctx.showcase ? { id: ctx.showcase.id, name: ctx.showcase.name, path: ctx.showcase.path } : null,
    },
    portal: { ids, files, hidden },
    pages,
  };
  const text = JSON.stringify(snapshot, null, 1);
  await env.BUCKET.put(`${hidden}project.json`, text, { httpMetadata: { contentType: "application/json" } });
  const check = await readBucketJson(env, `${hidden}project.json`);
  if (!check || check.id !== ctx.key) return { ok: false, why: "The server's copy could not be read back. Nothing was changed." };

  // 2. The project file, in its Drive folder.
  let file = null;
  if (ctx.folder) {
    if (!w.create || !w.create.mkfile) return { ok: false, why: "The Drive can't be written from the server. Nothing was changed." };
    try {
      const name = await freeName(w.create, ctx.folder.id, slug, day);
      file = await w.create.mkfile(ctx.folder.id, name, text);
    } catch (e) {
      return { ok: false, why: `The project file couldn't be saved to Drive (${String((e && e.message) || e).slice(0, 120)}). Nothing was changed.` };
    }
  }

  // 3. The portal's marks: every sent link now says it is closed.
  for (const x of ids) await putBucketJson(env, `${MARKS}${x}.json`, { key: ctx.key, name: ctx.name, at });

  // 4. The record.
  const closed = { at, by, reason, status_before: before, file: file ? { id: file.id, name: file.name } : null,
    folder: ctx.place ? ctx.place.path : "", hidden, portal: ids };
  await changeRecord(env, ctx.key, (r) => ({ ...r, closed }));
  try { await writeStatus(w, ctx, "Closed"); } catch (e) { console.error("close: status:", String((e && e.message) || e)); }
  try {
    const { writeFacts } = await import("./facts.js");
    const r = await readBucketJson(env, `r/${ctx.key}/record.json`);
    const kept = r && r.facts && r.facts.close_reason;
    await writeFacts(env, ctx.key, { close_reason: { value: reason, base: isObject(kept) ? Number(kept.v) || 0 : 0 } }, "server");
  } catch (e) { console.error("close: reason:", String((e && e.message) || e)); }

  // 5. Notion's Status follows (never waited on for anything above).
  const notes = [];
  if (ctx.page && ctx.notion) {
    try { await w.n.patch(`pages/${ctx.page}`, { properties: { Status: { select: { name: "Closed" } } } }); } catch (e) { notes.push("Notion's Status follows on the link's next minute."); }
  }
  try {
    const { logActivity } = await import("./step6history.js");
    await logActivity(env, { kind: "close", desc: `Closed ${ctx.name}`, undo: null });
  } catch { /* the close stands */ }
  return {
    ok: true, id: ctx.key, name: ctx.name,
    report: `${ctx.name} closed.`, file: file ? file.name : "", folder: ctx.place ? ctx.place.path : "", notes,
  };
}

// ── Reopen ───────────────────────────────────────────────────────────────────

/** A project file's snapshot, as it was read on a Mac and sent: checked. */
function snapshotOf(x) {
  if (!isObject(x) || x.kind !== FILE_KIND || !ID32.test(bare(x.id))) return null;
  return x;
}

export async function reopenRun(env, said0 = {}, { world = null } = {}) {
  const said = isObject(said0) ? said0 : { id: said0 };
  const by = String(said.by || "Projects Console").slice(0, 80);
  const snap = snapshotOf(said.file);
  const id = bare(said.id || (snap && snap.id) || "");
  if (!ID32.test(id)) return { ok: false, why: "Say which project." };
  const { resolveProject } = await import("./projectid.js");
  let found = await resolveProject(env, id);
  let restored = false;
  if (!found.record && snap && isObject(snap.record)) {
    // The server's record is gone: the file brings it back as it was closed.
    const key = bare(snap.id);
    await putBucketJson(env, `r/${key}/record.json`, { ...snap.record, closed: snap.record.closed || { ...snap.closed, status_before: snap.status_before, portal: (snap.portal || {}).ids || [] } });
    found = await resolveProject(env, key);
    restored = true;
  }
  if (!found.record) return { ok: false, why: "No project by that ID." };
  const key = found.key;
  const rec = found.record;
  const closed = isObject(rec.closed) ? rec.closed : (factOf(rec, "status") === "Closed" ? {} : null);
  if (!closed) return { ok: false, why: "This project isn't closed." };
  const ids = idsOf(key, rec, Array.isArray(closed.portal) ? closed.portal : []);
  const name = factOf(rec, "title") || rec.name || (snap && snap.name) || "Project";

  // The portal's own files: any that went missing come back from the hidden copy.
  let back = 0;
  if (closed.hidden) {
    for (const o of await listAll(env, `${closed.hidden}p/`)) {
      const live = o.key.slice(closed.hidden.length);
      if (await env.BUCKET.head(live)) continue;
      const got = await env.BUCKET.get(o.key);
      if (!got) continue;
      await env.BUCKET.put(live, got.body, { httpMetadata: got.httpMetadata, customMetadata: got.customMetadata });
      back += 1;
    }
  }
  for (const x of ids) await env.BUCKET.delete(`${MARKS}${x}.json`);
  const status = ["Development", "Active", "Post", "Released", "Archived"].includes(closed.status_before) ? closed.status_before : "Development";
  await changeRecord(env, key, (r) => {
    const { closed: _c, ...rest } = r;
    return { ...rest, reopened: { at: new Date().toISOString(), by, closed_at: closed.at || "" } };
  });
  const w = world || await worldOf(env, { write: true, by });
  try { await writeStatus(w, { key, record: rec }, status); } catch (e) { console.error("reopen: status:", String((e && e.message) || e)); }
  const { notionOf } = await import("./projectid.js");
  const page = notionOf(rec, key);
  if (page && rec.kind !== "job") {
    try { await w.n.patch(`pages/${page}`, { properties: { Status: { select: { name: status } } } }); } catch { /* the link follows */ }
  }
  try {
    const { logActivity } = await import("./step6history.js");
    await logActivity(env, { kind: "reopen", desc: `Reopened ${name}`, undo: null });
  } catch { /* the reopen stands */ }
  return { ok: true, id: key, name, status, restored, portal_back: back, report: `${name} reopened.` };
}

// ── the closed list ──────────────────────────────────────────────────────────

export async function closedProjects(env) {
  const { allRecords } = await import("./onelist.js");
  const records = await allRecords(env);
  const out = [];
  for (const [key, r] of Object.entries(records)) {
    if (!isObject(r) || r.deleted) continue;
    if (!r.closed && factOf(r, "status") !== "Closed") continue;
    const c = isObject(r.closed) ? r.closed : {};
    out.push({ id: key, name: factOf(r, "title") || r.name || "", at: c.at || "", reason: c.reason || factOf(r, "close_reason") || "",
      file: c.file ? c.file.name : "", folder: c.folder || "" });
  }
  out.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : a.name.localeCompare(b.name)));
  return { ok: true, closed: out };
}

// ── Released: the showcase's stills ──────────────────────────────────────────

const childNamed = (kids, name) => kids.find((k) => k.name === name) || kids.find((k) => k.name.toLowerCase() === name) || null;

/** The stills a Released page picks from: `stills/hq/` when there is one, else `stills/lq/`, else `stills/`. */
export async function stillsOf(api, showcase) {
  if (!api || !showcase) return null;
  const kids = await api.list(showcase.id);
  const stills = childNamed(kids.filter((k) => k.folder), "stills");
  if (!stills) return { folder: "", files: [] };
  let inner = await api.list(stills.id);
  let path = `${showcase.path || showcase.name}/stills`;
  const sub = childNamed(inner.filter((k) => k.folder), "hq") || childNamed(inner.filter((k) => k.folder), "lq");
  if (sub) { inner = await api.list(sub.id); path += `/${sub.name}`; }
  const files = inner.filter((k) => !k.folder && !k.shortcut && IMAGE.test(k.name))
    .sort((a, b) => a.name.localeCompare(b.name, "en", { numeric: true }))
    .map((k) => ({ id: k.id, name: k.name }));
  return { folder: path, files };
}

/** The stills in a folder he chose himself (`selects_folder` {id, name, path}): its own images, read only. */
export async function stillsIn(api, folderId) {
  if (!api || !DRIVE_ID.test(String(folderId || ""))) return null;
  let kids;
  try {
    const it = await api.get(folderId);
    if (!it || !it.folder || it.trashed) return null;
    kids = await api.list(folderId);
  } catch { return null; }
  if (!Array.isArray(kids)) return null;
  return kids.filter((k) => !k.folder && !k.shortcut && IMAGE.test(k.name))
    .sort((a, b) => a.name.localeCompare(b.name, "en", { numeric: true }))
    .map((k) => ({ id: k.id, name: k.name }));
}

export async function releasedStills(env, id, { world = null, showcaseOnly = false } = {}) {
  const w = world || await worldOf(env, { write: false });
  let ctx;
  try { ctx = await projectOf(w, id, await settingsOf(env)); } catch (e) { if (e instanceof Refusal) return { ok: false, why: e.message }; throw e; }
  const chose = factOf(ctx.record, "selects_folder");
  const custom = !showcaseOnly && isObject(chose) && DRIVE_ID.test(String(chose.id || ""))
    ? { id: String(chose.id), name: String(chose.name || ""), path: String(chose.path || "") } : null;
  const showcase = ctx.showcase ? { id: ctx.showcase.id, name: ctx.showcase.name, path: ctx.showcase.path } : null;
  if (custom) {
    const files = await stillsIn(w.raw, custom.id);
    if (files) return { ok: true, id: ctx.key, name: ctx.name, showcase, custom, folder: "", total: files.length, stills: files };
  }
  const got = ctx.showcase ? await stillsOf(w.raw, ctx.showcase) : null;
  return {
    ok: true, id: ctx.key, name: ctx.name, showcase, custom: custom ? { ...custom, unread: true } : null,
    folder: got ? got.folder : "", total: got ? got.files.length : 0, stills: got ? got.files : [],
  };
}

/** One still's bytes (a Drive file's), kept in the bucket after the first read. */
export async function stillBytes(env, fileId) {
  if (!DRIVE_ID.test(String(fileId || ""))) return null;
  const at = `shelf/stills/${fileId}`;
  const kept = await env.BUCKET.get(at);
  if (kept) return { body: kept.body, type: (kept.httpMetadata && kept.httpMetadata.contentType) || "image/webp" };
  const { accessToken, filesUrl } = await import("./drivewrite.js");
  const secret = env.GDRIVE_WRITE ? "GDRIVE_WRITE" : env.GDRIVE ? "GDRIVE" : "";
  if (!secret) return null;
  const access = await accessToken(env, secret);
  const meta = await fetch(`${filesUrl(env)}/${fileId}?fields=mimeType,size&supportsAllDrives=true`, { headers: { authorization: `Bearer ${access}` } });
  if (!meta.ok) return null;
  const m = await meta.json();
  if (!/^image\//.test(m.mimeType || "") || Number(m.size || 0) > 15 * 1024 * 1024) return null;
  const got = await fetch(`${filesUrl(env)}/${fileId}?alt=media&supportsAllDrives=true`, { headers: { authorization: `Bearer ${access}` } });
  if (!got.ok) return null;
  const bytes = await got.arrayBuffer();
  await env.BUCKET.put(at, bytes, { httpMetadata: { contentType: m.mimeType } });
  return { body: bytes, type: m.mimeType };
}

// ── the asks and the door ────────────────────────────────────────────────────

export const ASKS = {
  async close_look([id], env) { return closeLook(env, id); },
  async close_project([id, opts], env) { return closeRun(env, id, opts); },
  async reopen_project([said], env) { return reopenRun(env, said); },
  async closed_projects(_list, env) { return closedProjects(env); },
  async released_stills([id, opts], env) { return releasedStills(env, id, { showcaseOnly: Boolean(isObject(opts) && opts.showcase) }); },
};

/**
 *   GET /console/studio/step6shelf/still/<drive file id>   the still's bytes
 *   GET /console/studio/step6shelf/closed                  the closed list
 */
export async function door(env, rest, method, _readBody, _ctx, _url) {
  if (rest[1] === "still" && rest[2] && method === "GET") {
    const got = await stillBytes(env, rest[2]);
    if (!got) return new Response("No such still.", { status: 404 });
    return new Response(got.body, { headers: { "content-type": got.type, "cache-control": "private, max-age=86400" } });
  }
  if (rest[1] === "closed" && method === "GET") return Response.json(await closedProjects(env));
  return null;
}
