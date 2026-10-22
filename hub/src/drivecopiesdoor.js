/**
 * **Drive copies of pictures, on the server** (stage 5 step 5, his answer
 * 24). The rules are `drivecopies.js`; this reads a project's pictures off the
 * bucket and the engine, keeps what Drive holds (a manifest per project),
 * talks to Google, and hangs it on the switch and the clock.
 *
 *   GET  /console/studio/drivecopies             the switch {mode, drivecopies_root, only, cap}, ready, last sweep
 *   PUT  /console/studio/drivecopies             {mode: off|scratch|live, drivecopies_root?, only?, cap?, by}
 *   GET  /console/studio/drivecopies/look?id=…   the plan for one project against what Drive holds; writes nothing
 *   GET  /console/studio/drivecopies/manifest?id=…  what the server remembers Drive holding
 *   POST /console/studio/drivecopies/run  {id}   one project now (switch on only); answers 202 at once, runs on beside it
 *   POST /console/studio/drivecopies/tick        the clock's sweep, now; 202 at once too ({wait:true} or ?wait=1 to hear the result; {force:true})
 *
 * A run saves the manifest after every file, adopts a file already in the folder
 * under the target name (same size/md5) instead of uploading it again, and stops
 * cleanly when its time (TICK_MS / MANUAL_MS) is used; the next tick resumes.
 *
 * **Two stages, off until thrown** (`s/drivecopies.json`):
 *
 * - `off` — nothing is copied; the look still answers.
 * - `scratch` — every copy goes into `<drivecopies_root>/<project>/…`, a
 *   throwaway folder, for the first real writes; with no scratch folder set
 *   nothing is written. Only the projects in `only` are swept.
 * - `live` — each project's own Drive folder (the record's Drive Folder link);
 *   `only`, when set, still narrows it.
 *
 * Scratch and live keep separate manifests (`s/drivecopies/<mode>/<id>.json`),
 * and a manifest made for another folder is never trusted, so going live
 * starts clean.
 *
 * **When it runs.** The portal's two-minute clock (`scheduled` in worker.js)
 * sweeps: for each project it compares the film's change logs (`filmStamp`,
 * the stamp that already says "this film changed" to the snapshot cache) and
 * its portal's board and page files with what the manifest last saw, and does
 * nothing more for a project that has not moved. A run takes at most the cap's
 * files and bytes across all projects (30 files, 50 MB), so a slow Drive never
 * holds the clock; what is left waits for the next tick. One sweep at a time.
 *
 * **The Drive** is `GDRIVE_WRITE` with its own few calls here — list, make a
 * folder, upload, replace a file's bytes, move or rename — and nothing that
 * trashes or deletes.
 */

import { keys } from "../../relay/layout.js";
import * as R from "./drivecopies.js";
import { accessToken, filesUrl, uploadUrl } from "./drivewrite.js";
import { resolveProject, studioOf, bare, ID } from "./projectid.js";
import { slugify, idFromUrl } from "./drivefolders.js";
import { listAll, titleOf } from "./films.js";
import mcpWasm from "./mcp.wasm";
import { begin, feed, take, logObjects, filmStamp } from "./live.js";

const LAST_KEY = "s/drivecopies-last.json";
const LOCK_KEY = "s/drivecopies-run.json";
const LOCK_MS = 4 * 60 * 1000;
/**
 * How long one tick works before it stops cleanly and leaves the rest for the
 * next (2026-10-15: the first live try was cut at the platform's limit). The
 * clock's own run may go long (a cron trigger has minutes); a run started by
 * hand is answered at once and finishes beside the reply (`waitUntil`, which
 * the platform allows 30 s), so it stops sooner. A call in flight finishes.
 */
export const TICK_MS = 100 * 1000;
export const MANUAL_MS = 18 * 1000;
const FOLDER = "application/vnd.google-apps.folder";
const ONE_PART = 5 * 1024 * 1024;
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const JSON_TYPE = { httpMetadata: { contentType: "application/json" } };

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

export async function settingsOf(env) {
  return R.settingsShape(await readJson(env, R.SWITCH_KEY));
}

const manifestKey = (mode, key) => `s/drivecopies/${mode}/${key}.json`;

// ── the project and its pictures ─────────────────────────────────────────────

/** `{key, name, record, film, drive}` for any ID the project is known by, or null. */
export async function projectOf(env, id) {
  const got = await resolveProject(env, bare(id));
  if (!got.key) return null;
  const r = got.record || {};
  const facts = isObject(r.facts) ? r.facts : {};
  const link = isObject(facts.drive_folder) ? String(facts.drive_folder.value || "") : "";
  return {
    key: got.key,
    name: String(r.name || (isObject(facts.title) ? facts.title.value : "") || ""),
    record: r,
    film: studioOf(r),
    portal: studioOf(r) || got.key,
    drive: idFromUrl(link),
  };
}

/** The engine's whole view of a film, read only. */
async function filmView(env, film, ctx) {
  const inst = await WebAssembly.instantiate(mcpWasm, {});
  const x = inst.exports;
  x.set_now(Date.now());
  x.set_seed(1);
  begin(x, film, await titleOf(env, film), true, "0000000000000001");
  await feed(env, film, ctx, x, await logObjects(env, film));
  const text = take(x, x.view());
  return text ? JSON.parse(text) : {};
}

/** `{<file name>: bytes}` of a bucket folder. */
async function sizes(env, prefix) {
  const out = {};
  for (const o of await listAll(env, prefix)) {
    const name = o.key.slice(prefix.length);
    if (!name.includes("/")) out[name] = o.size;
  }
  return out;
}

/** The trimmed clips made for a film, `{<file name>: bytes}`: the hub's own shelf beside the film (`p/<film>/trims/`). */
export const trimsKey = (film, name = "") => `${keys.film(film)}trims/${name}`;
async function trimsOf(env, film) {
  return film ? await sizes(env, trimsKey(film)) : {};
}

/** The portal's boards — board pages, and a published page carrying one (Halcyon's). */
async function looksOf(env, portal) {
  const [{ storedFront }, B] = await Promise.all([import("./front.js"), import("./boards.js")]);
  const front = await storedFront(env, portal);
  const out = [];
  for (const one of Array.isArray(front.sections) ? front.sections : []) {
    if (!one || !one.slug) continue;
    if (one.type === "board" && one.board) {
      const b = await B.readBoard(env, portal, one.board);
      out.push({ file: one.board, name: String(one.name || one.slug), slug: one.slug, cards: R.lookCards(b) });
      continue;
    }
    const got = await env.BUCKET.get(keys.pageHtml(portal, one.slug));
    const html = got ? await got.text() : "";
    const board = B.boardIn(html);
    if (!board) continue;
    const whole = B.publishedBoard(await B.readBoard(env, portal, board), html);
    out.push({ file: board, name: String(one.name || one.slug), slug: one.slug, cards: R.lookCards(whole) });
  }
  return out;
}

/** Every picture this project should have on Drive: `{wanted, passed, film}`. */
export async function wantedFor(env, p, ctx) {
  const view = p.film ? await filmView(env, p.film, ctx) : {};
  const looks = await looksOf(env, p.portal);
  const media = p.film ? await sizes(env, keys.media(p.film)) : {};
  const docs = await sizes(env, keys.docs(p.portal));
  // A look board's `media/…` picture is the film's own (the portal and the film share it).
  const lookMedia = p.film && p.film !== p.portal ? { ...(await sizes(env, keys.media(p.portal))), ...media } : media;
  const trims = await trimsOf(env, p.film);
  return { ...R.wantedOf({ view, looks, media: lookMedia, docs, trims }), film: p.film };
}

/** What says "something here moved": the film's logs, the portal's boards and pages. */
async function signature(env, p) {
  const film = p.film ? (await filmStamp(env, p.film)).stamp : "";
  const base = keys.pages(p.portal).replace(/pages\/$/, "");
  const top = async (prefix) => {
    const got = await env.BUCKET.list({ prefix, delimiter: "/", limit: 1000 });
    return (got.objects || []).map((o) => `${o.key.slice(prefix.length)}:${o.size}:${o.uploaded ? new Date(o.uploaded).getTime() : ""}`).join(",");
  };
  const [boards, pages, trims] = await Promise.all([top(`${base}boards/`), top(keys.pages(p.portal)), p.film ? top(trimsKey(p.film)) : ""]);
  return `${film}|${boards}|${pages}|${trims}`;
}

// ── the look ─────────────────────────────────────────────────────────────────

/** GET …/look?id= — the plan for one project, against the manifest of the stage the switch is at. Writes nothing. */
export async function look(env, id, ctx) {
  const s = await settingsOf(env);
  const p = await projectOf(env, id);
  if (!p) return { ok: false, why: "No project by that ID." };
  const mode = s.mode === "off" ? "live" : s.mode;
  const held = (await readJson(env, manifestKey(mode, p.key))) || R.emptyManifest();
  const w = await wantedFor(env, p, ctx);
  const plan = R.plan(w.wanted, held);
  const per = {};
  for (const x of w.wanted) per[x.what] = (per[x.what] || 0) + 1;
  return {
    ok: true, id: p.key, name: p.name, film: p.film || null, drive_folder: p.drive || null,
    switch: s.mode, against: mode, ready: R.readiness(s, { signin: Boolean(env.GDRIVE_WRITE) }),
    pictures: { total: w.wanted.length, ...per, bytes: w.wanted.reduce((t, x) => t + x.bytes, 0) },
    passed: w.passed,
    manifest: { held: Object.keys(held.items || {}).length, at: held.at || null },
    plan: R.shownPlan(plan, held.homes || {}),
  };
}

// ── Google ───────────────────────────────────────────────────────────────────

/** The few calls copies need, with `GDRIVE_WRITE`. No trash, no delete. Null with no write sign-in. */
export function copiesDrive(env) {
  if (!env.GDRIVE_WRITE) return null;
  const secret = "GDRIVE_WRITE";
  async function call(url, init = {}, raw = false) {
    const access = await accessToken(env, secret);
    let got;
    try {
      got = await fetch(url, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${access}` } });
    } catch (e) {
      throw new Error(`couldn't reach Google Drive (${e && e.message})`);
    }
    if (got.status === 404) throw Object.assign(new Error("Google Drive has no such file"), { gone: true });
    if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
    return raw ? got : got.json();
  }
  const enc = new TextEncoder();
  const resumable = async (url, method, meta, mime, bytes) => {
    const start = await call(url, {
      method, headers: { "content-type": "application/json; charset=UTF-8", "x-upload-content-type": mime, "x-upload-content-length": String(bytes.length) },
      body: JSON.stringify(meta),
    }, true);
    const at = start.headers.get("location");
    if (!at) throw new Error("Google Drive gave no upload address");
    return call(at, { method: "PUT", headers: { "content-type": mime }, body: bytes });
  };
  const fields = `fields=${encodeURIComponent("id,name")}&supportsAllDrives=true`;
  return {
    async list(parent) {
      const out = [];
      let page = "";
      do {
        const q = `'${parent}' in parents and trashed = false`;
        const got = await call(`${filesUrl(env)}?q=${encodeURIComponent(q)}&fields=${encodeURIComponent("nextPageToken,files(id,name,mimeType,size,md5Checksum)")}`
          + `&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`);
        out.push(...(got.files || []).map((f) => ({ id: f.id, name: String(f.name || ""), folder: f.mimeType === FOLDER,
          size: f.size === undefined ? undefined : Number(f.size), md5: f.md5Checksum || "" })));
        page = got.nextPageToken || "";
      } while (page);
      return out;
    },
    async get(id) {
      try {
        const f = await call(`${filesUrl(env)}/${encodeURIComponent(id)}?fields=${encodeURIComponent("id,name,mimeType,trashed")}&supportsAllDrives=true`);
        return { id: f.id, name: f.name, folder: f.mimeType === FOLDER, trashed: Boolean(f.trashed) };
      } catch (e) {
        if (e.gone) return null;
        throw e;
      }
    },
    async mkdir(parent, name) {
      return call(`${filesUrl(env)}?${fields}`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, mimeType: FOLDER, parents: [parent] }),
      });
    },
    async upload(parent, name, mime, bytes) {
      const meta = { name, parents: [parent], mimeType: mime };
      if (bytes.length > ONE_PART) return resumable(`${uploadUrl(env)}?uploadType=resumable&${fields}`, "POST", meta, mime, bytes);
      const boundary = `drivecopies${crypto.randomUUID().replace(/-/g, "")}`;
      const head = enc.encode(`--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(meta)}\r\n--${boundary}\r\ncontent-type: ${mime}\r\n\r\n`);
      const tail = enc.encode(`\r\n--${boundary}--`);
      const body = new Uint8Array(head.length + bytes.length + tail.length);
      body.set(head, 0); body.set(bytes, head.length); body.set(tail, head.length + bytes.length);
      const got = await call(`${uploadUrl(env)}?uploadType=multipart&${fields}`, {
        method: "POST", headers: { "content-type": `multipart/related; boundary=${boundary}` }, body,
      });
      if (!got || !got.id) throw new Error(`Google Drive did not take ${name}`);
      return got;
    },
    async replace(id, mime, bytes) {
      const at = `${uploadUrl(env)}/${encodeURIComponent(id)}`;
      if (bytes.length > ONE_PART) return resumable(`${at}?uploadType=resumable&${fields}`, "PATCH", {}, mime, bytes);
      return call(`${at}?uploadType=media&${fields}`, { method: "PATCH", headers: { "content-type": mime }, body: bytes });
    },
    /** Rename, and with `from` and `to` move between folders. Never to the bin. */
    async move(id, { name, from = "", to = "" }) {
      const q = from && to ? `&addParents=${encodeURIComponent(to)}&removeParents=${encodeURIComponent(from)}` : "";
      return call(`${filesUrl(env)}/${encodeURIComponent(id)}?${fields}${q}`, {
        method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(name ? { name } : {}),
      });
    },
  };
}

// ── the run ──────────────────────────────────────────────────────────────────

/** Where this project's copies go: its own folder (live), or its own folder in the scratch one. */
async function rootFor(drive, s, p, { make }) {
  if (s.mode === "live") return p.drive ? { id: p.drive } : { why: "the project has no Drive Folder link" };
  const name = slugify(p.name) || p.key;
  const kids = await drive.list(s.drivecopies_root);
  const there = kids.find((k) => k.folder && k.name.toLowerCase() === name);
  if (there) return { id: there.id };
  if (!make) return { id: "", would: `${name}/` };
  const got = await drive.mkdir(s.drivecopies_root, name);
  return { id: got.id, made: name };
}

/**
 * One project, within `budget` ({files, bytes}, taken down as it goes). Saves
 * the manifest only when Drive changed; marks it caught up (`sig`) only when
 * nothing was left and nothing failed.
 */
export async function runOne(env, ctx, id, { budget = null, sig = null, deadline = 0 } = {}) {
  const s = await settingsOf(env);
  const ready = R.readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
  if (!ready.ok) return { ok: false, why: ready.why };
  const p = await projectOf(env, id);
  if (!p) return { ok: false, why: "No project by that ID." };
  const drive = copiesDrive(env);
  const cap = budget || { ...s.cap };
  const key = manifestKey(s.mode, p.key);
  const before = (await readJson(env, key)) || R.emptyManifest();
  let root;
  try {
    root = await rootFor(drive, s, p, { make: true });
  } catch (e) {
    return { ok: false, id: p.key, why: String((e && e.message) || e).slice(0, 300) };
  }
  if (!root.id) return { ok: false, id: p.key, why: root.why };
  const held = before.root === root.id && before.mode === s.mode ? before : R.emptyManifest(root.id, s.mode);
  const w = await wantedFor(env, p, ctx);
  const plan = R.plan(w.wanted, held);
  const stamp = () => new Date().toISOString();
  // Kept after every call that worked, so a run cut off part way loses nothing
  // (the first live try lost nine pictures' record that way). Never "caught up" here.
  const save = (m) => env.BUCKET.put(key, JSON.stringify({ ...m, project: p.key, name: p.name, film: p.film, root: root.id, mode: s.mode,
    at: stamp(), sig: "" }), JSON_TYPE);
  const md5Of = async (b) => [...new Uint8Array(await crypto.subtle.digest("MD5", b))].map((x) => x.toString(16).padStart(2, "0")).join("");
  const got = plan.ops.length
    ? await R.carry(drive, plan, held, { rootId: root.id, bytesOf: async (src) => {
      const [kind, file] = src.split("/");
      if (kind === "trim") {
        const t = w.film ? await env.BUCKET.get(trimsKey(w.film, file)) : null;
        return t ? new Uint8Array(await t.arrayBuffer()) : null;
      }
      const o = await env.BUCKET.get(kind === "pic" ? keys.doc(p.portal, file) : keys.medium(kind === "media" && w.film ? w.film : p.portal, file))
        || (kind === "media" && w.film && w.film !== p.portal ? await env.BUCKET.get(keys.medium(p.portal, file)) : null);
      return o ? new Uint8Array(await o.arrayBuffer()) : null;
    }, cap, save, deadline, md5Of })
    : { manifest: held, done: [], failed: null, left: 0, made: [], files: 0, bytes: 0 };
  cap.files -= got.files; cap.bytes -= got.bytes;
  const caught = !got.failed && !got.left;
  const summary = { at: new Date().toISOString(), done: got.done.length, adopted: (got.adopted || []).length, left: got.left, failed: got.failed, made: got.made,
    ...(got.timeUp ? { time_up: true } : {}),
    counts: plan.counts, bytes: got.bytes, ...(root.made ? { scratch_folder: root.made } : {}) };
  const out = got.manifest;
  const changed = got.done.length || got.made.length || held !== before;
  if (changed || (caught && sig && out.sig !== sig) || out.name !== p.name) {
    // The manifest records what Drive now holds; it is saved even after a
    // failure, holding only what worked — the failed picture is as it was.
    const save = { ...out, project: p.key, name: p.name, film: p.film, root: root.id, mode: s.mode, at: summary.at, last: summary,
      sig: caught && sig ? sig : (caught ? out.sig : "") };
    await env.BUCKET.put(key, JSON.stringify(save), JSON_TYPE);
  }
  return { ok: !got.failed, id: p.key, name: p.name, ...summary };
}

/** The projects a sweep looks at: `only`, else (live) every record with a film or a portal. */
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

/** One run at a time: `fn` runs holding the lock, or `null` when a run already holds it. */
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
 * The clock's sweep (every two minutes): each project that moved, within one
 * cap and one time budget (`ms`) for the whole tick. Out of either, it stops
 * cleanly; what is left is picked up by the next tick, where the manifest
 * (saved after every file) says where it got to.
 */
export async function sweep(env, ctx, { force = false, ms = TICK_MS } = {}) {
  const s = await settingsOf(env);
  if (s.mode === "off") return { ran: false, why: "the switch is off" };
  const ready = R.readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
  if (!ready.ok) return { ran: false, why: ready.why };
  const deadline = Date.now() + ms;
  const done = await locked(env, async () => {
    const budget = { ...s.cap };
    const projects = [];
    for (const id of await sweepList(env, s)) {
      if (budget.files <= 0 || budget.bytes <= 0 || Date.now() >= deadline) { projects.push({ id, waiting: true }); continue; }
      const p = await projectOf(env, id);
      if (!p || (!p.film && !p.portal)) continue;
      if (s.mode === "live" && !p.drive) continue;
      const sig = await signature(env, p);
      const m = await readJson(env, manifestKey(s.mode, p.key));
      if (!force && m && m.sig && m.sig === sig && (s.mode !== "live" || m.root === p.drive)) continue;
      try {
        projects.push(await runOne(env, ctx, p.key, { budget, sig, deadline }));
      } catch (e) {
        projects.push({ ok: false, id: p.key, why: String((e && e.message) || e).slice(0, 300) });
      }
    }
    return remember(env, s.mode, projects);
  });
  return done ? { ran: true, ...done } : { ran: false, why: "a sweep is already running" };
}

/** One project by hand, holding the same lock as the clock, within `ms`. */
export async function runLocked(env, ctx, id, { ms = MANUAL_MS } = {}) {
  const s = await settingsOf(env);
  const deadline = Date.now() + ms;
  const out = await locked(env, async () => {
    const one = await runOne(env, ctx, id, { deadline });
    await remember(env, s.mode, [one]);
    return one;
  });
  return out || { ok: false, why: "a sweep is already running" };
}

// ── the door ─────────────────────────────────────────────────────────────────

const answer = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function drivecopiesDoor(env, rest, method, readBody, ctx, url, request = null) {
  if (rest[0] !== "drivecopies") return null;
  const show = async () => {
    const s = await settingsOf(env);
    return { ...s, ready: R.readiness(s, { signin: Boolean(env.GDRIVE_WRITE) }), signin: env.GDRIVE_WRITE ? "write" : "none",
      last: await readJson(env, LAST_KEY) };
  };
  if (rest.length === 1) {
    if (method === "GET") return answer(await show());
    if (method !== "PUT") return answer({ problem: "Wrong method." }, 405);
    let said;
    try { said = await readBody(); } catch { return answer({ problem: "That is not JSON." }, 400); }
    const next = R.changedSettings(await settingsOf(env), said);
    if (next.problem) return answer(next, 400);
    await env.BUCKET.put(R.SWITCH_KEY, JSON.stringify(next), JSON_TYPE);
    return answer(await show());
  }
  const id = String((url && url.searchParams.get("id")) || "");
  if (rest[1] === "look" && rest.length === 2) {
    if (method !== "GET") return answer({ problem: "Wrong method." }, 405);
    return answer(await look(env, id, ctx));
  }
  // **Trimmed clips** (his rule, 2026-10-15). Studio keeps a clip whole and remembers its in and
  // out; the file Drive gets is cut once on a Mac (`hub/trimclips.py`, ffmpeg) and put on the
  // hub's shelf. GET says which are still owed (and how big the shelf is); PUT shelves one.
  if (rest[1] === "trims" && rest.length === 2) {
    if (method !== "GET") return answer({ problem: "Wrong method." }, 405);
    const p = await projectOf(env, id);
    if (!p) return answer({ ok: false, why: "No project by that ID." }, 404);
    const w = await wantedFor(env, p, ctx);
    const have = await trimsOf(env, p.film);
    return answer({ ok: true, id: p.key, name: p.name, film: p.film, owed: w.passed.trims_waiting, posters: w.passed.posters_waiting, have: Object.keys(have).length, bytes: Object.values(have).reduce((a, b) => a + b, 0) });
  }
  // A clip as the server holds it (for the Mac that cuts trims and grabs posters): `src` is `media/<file>` or `pic/<file>`.
  if (rest[1] === "clipfile" && rest.length === 2) {
    if (method !== "GET") return answer({ problem: "Wrong method." }, 405);
    const p = await projectOf(env, id);
    const [kind, file] = String(url.searchParams.get("src") || "").split("/");
    if (!p || !/^[0-9a-f]{32}\.(mp4|mov|m4v)$/i.test(file || "") || !["media", "pic"].includes(kind)) return answer({ ok: false, why: "No such clip." }, 404);
    const o = kind === "pic" ? await env.BUCKET.get(keys.doc(p.portal, file))
      : (p.film && await env.BUCKET.get(keys.medium(p.film, file))) || await env.BUCKET.get(keys.medium(p.portal, file));
    if (!o) return answer({ ok: false, why: "The server does not hold that clip." }, 404);
    return new Response(o.body, { headers: { "content-type": "application/octet-stream", "cache-control": "no-store" } });
  }
  if (rest[1] === "trim" && rest.length === 2) {
    if (method !== "PUT" || !request) return answer({ problem: "Wrong method." }, 405);
    const film = String(url.searchParams.get("film") || ""), name = String(url.searchParams.get("name") || "");
    const poster = R.POSTER_NAME.test(name);
    if (!/^[0-9a-f]{32}$/.test(film) || !(poster || R.TRIM_NAME.test(name))) return answer({ ok: false, why: "film is the film's id and name is <hash>_<in ms>_<out ms|end>.mp4 or poster_<hash>.jpg." }, 400);
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.length < 1000 || bytes.length > 90 * 1024 * 1024) return answer({ ok: false, why: "That is not a clip or picture (too small, or over 90 MB)." }, 400);
    if (poster ? !(bytes[0] === 0xff && bytes[1] === 0xd8) : !(bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70)) return answer({ ok: false, why: poster ? "That is not a JPEG." : "That is not an MP4 file." }, 400);
    await env.BUCKET.put(trimsKey(film, name), bytes, { httpMetadata: { contentType: poster ? "image/jpeg" : "video/mp4" } });
    return answer({ ok: true, film, name, bytes: bytes.length });
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
    // Answered at once; the run goes on beside the reply and ends before the
    // platform's limit, so a client that waits (or hangs up) cannot cut it.
    // `wait: true` (the checks, local) answers when it is done.
    if (said.wait === true || (url && url.searchParams.get("wait") === "1")) return answer(await runLocked(env, ctx, String(said.id || ""), { ms: said.ms || MANUAL_MS }));
    const s = await settingsOf(env);
    const ready = R.readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
    if (!ready.ok) return answer({ ok: false, why: ready.why });
    ctx.waitUntil(runLocked(env, ctx, String(said.id || "")).catch((e) => console.error(e && e.stack ? e.stack : String(e))));
    return answer({ ok: true, started: true, id: String(said.id || ""), note: "Running in the background; the result is in GET /drivecopies under last." }, 202);
  }
  if (rest[1] === "tick" && rest.length === 2) {
    if (method !== "POST") return answer({ problem: "Wrong method." }, 405);
    let said = {};
    try { said = (await readBody()) || {}; } catch { said = {}; }
    if (said.wait === true || (url && url.searchParams.get("wait") === "1")) return answer(await sweep(env, ctx, { ms: said.ms || MANUAL_MS, force: said.force === true }));
    const s = await settingsOf(env);
    const ready = R.readiness(s, { signin: Boolean(env.GDRIVE_WRITE) });
    if (!ready.ok) return answer({ ran: false, why: ready.why });
    ctx.waitUntil(sweep(env, ctx, { ms: MANUAL_MS }).catch((e) => console.error(e && e.stack ? e.stack : String(e))));
    return answer({ ran: true, started: true, note: "Running in the background; the result is in GET /drivecopies under last." }, 202);
  }
  return answer({ problem: "No such door." }, 404);
}
