/**
 * **Film backups, made by the server: where they go and when** (2026-10-13,
 * stage 4 part C). The rules — what a snapshot is, when one is due, which
 * old ones go — are `filmbackup.js`; this is the bucket, the Drive, the
 * clock and the doors.
 *
 * ## Two homes, his pick of 2026-10-13
 *
 * - **A bucket of their own, `shotlister-backups`** (binding `BACKUPS`),
 *   apart from the portal's live one. Only this file writes to it, and the
 *   only thing that ever deletes from it is the tidy-up below. Two folders:
 *   `daily/<relay id>/<stamp>.zip`, every snapshot, and
 *   `forever/<relay id>/<stamp>.zip`, a film's last copy once it has gone
 *   quiet. Cloudflare's bucket lock rules hold them, so no sync, no
 *   `removeProject`, no slip of this code and no stolen key can take a copy
 *   sooner than the rule says (the exact commands are beside the binding in
 *   `hub/wrangler.toml`):
 *     - `daily/` locked 90 days from the moment each copy is put;
 *     - `forever/` locked indefinitely.
 *   A copy's fingerprint, film title and size ride on it as R2 metadata, so
 *   "has this film changed since its last copy?" is one listing.
 * - **His Google Drive**, `My Drive/shotlister-backups/<Film>/<stamp>.zip`
 *   in the owner@your-domain.example Drive that the `GDRIVE_WRITE`
 *   sign-in reaches — the Mac's "Shotlister Backups" layout exactly, so on
 *   the Mac (where that Drive is mounted) the existing `restore.sh` and
 *   "Restore a Film" open them: `SHOTLISTER_BACKUPS=<that folder>`. Old
 *   copies there go to the Drive's bin by the same rule (recoverable for 30
 *   days), never deleted outright. The folder is found, or made once, by
 *   name; the switch may name another (`folder`), a scratch one for the
 *   first real run.
 *
 * ## When
 *
 * - **Daily, on the worker's minute** (`timer.js`): from 04:00 on his clock,
 *   each minute looks at a few films (`PER_TICK`, and at most one new copy
 *   a minute, so a minute never reads more than one film's logs) until every
 *   film on the relay has had its look that day. A film whose change files
 *   are what they were at its last copy is left alone ("unchanged").
 * - **When the phone asks** (`film_backup`): that film, now, answered in
 *   `backup.sh`'s words. `film_backups` lists the copies, newest first.
 *
 * ## Restoring
 *
 * Never over the live film, the Mac's own rule. Two ways back, both of them
 * a copy beside the film: on the Mac, `restore.sh` on the Drive folder
 * (Desktop, "<Film> (14 Oct).shotlist"); and from anywhere, the console
 * door `GET /console/studio/filmbackup/zip/<relay>/<stamp>` hands back a copy
 * from the bucket — the road for the day the Drive copy is gone too. The
 * phone's `film_restore` stays the Mac's: what it does is put a film on the
 * Mac's Desktop.
 *
 * **Off until thrown** (`s/filmbackup.json`): while off, nothing is copied,
 * the phone's asks are the Mac's (and `backup.sh`'s) as before, and they are
 * not listed to the phone. `POST /console/studio/filmbackup/look` says what a
 * run would do — which films, how big, which old copies would go — and
 * writes nothing, switch or no switch.
 */

import { keys } from "../../relay/layout.js";
import {
  KEEP, ZIP_NAME, CHANGE_NAME, stampOf, dayOf, hourOf, folderName, remoteJson, fingerprint,
  makeZip, retention, saidOf,
} from "./filmbackup.js";
import { accessToken, filesUrl, uploadUrl, DriveRefused } from "./drivewrite.js";

export const SWITCH_KEY = "s/filmbackup.json";
export const DAY_KEY = "s/filmbackup-day.json";
export const DRIVE_FOLDER = "shotlister-backups";
/** His clock: the daily run starts at four in the morning. */
export const START_HOUR = 4;
/** Films looked at in one minute, at most; and never more than one new copy. */
export const PER_TICK = 4;
const DRIVE_ID = /^[A-Za-z0-9_-]{10,120}$/;
const RELAY = /^[0-9a-f]{8,64}$/;
const FOLDER = "application/vnd.google-apps.folder";
const READ_AT_ONCE = 8;

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const daily = (relay, stamp = "") => `daily/${relay}/${stamp ? `${stamp}.zip` : ""}`;
const forever = (relay, stamp = "") => `forever/${relay}/${stamp ? `${stamp}.zip` : ""}`;
const drivePath = (title, stamp) => `My Drive/${DRIVE_FOLDER}/${folderName(title)}/${stamp}.zip`;
const serverPath = (relay, stamp) => `server: daily/${relay}/${stamp}.zip`;
const short = (e) => String((e && e.message) || e || "").slice(0, 300);

// ── the switch ──────────────────────────────────────────────────────────────

export async function settingsOf(env) {
  let v = {};
  const got = await env.BUCKET.get(SWITCH_KEY);
  if (got) { try { v = await got.json(); } catch { v = {}; } }
  if (!isObject(v)) v = {};
  return {
    on: v.on === true, at: v.at || null, by: v.by || null,
    folder: DRIVE_ID.test(String(v.folder || "")) ? v.folder : null,
  };
}

/** A switch change: `on`, and `folder` (a Drive folder id, or null to find
 * or make `My Drive/shotlister-backups` again). Answers the settings, or `{problem}`. */
export function changedSettings(now, said) {
  const s = isObject(said) ? said : {};
  const out = { ...now, on: s.on === true, at: new Date().toISOString(), by: String(s.by || "").slice(0, 80) };
  if (s.folder !== undefined) {
    if (s.folder === null || s.folder === "") out.folder = null;
    else if (!DRIVE_ID.test(String(s.folder))) return { problem: "folder is a Drive folder id, or null." };
    else out.folder = s.folder;
  }
  return out;
}

async function keepJson(env, key, body) {
  await env.BUCKET.put(key, JSON.stringify(body), { httpMetadata: { contentType: "application/json" } });
}

export function readiness(env) {
  return {
    bucket: Boolean(env.BACKUPS),
    signin: env.GDRIVE_WRITE ? "write" : env.GDRIVE ? "read" : "none",
  };
}

/** Whether the phone's asks are answered here: switch on, and a bucket. */
export async function backupsOn(env) {
  return (await settingsOf(env)).on && Boolean(env.BACKUPS);
}

// ── the films ───────────────────────────────────────────────────────────────

async function listAll(bucket, options) {
  const out = [];
  const prefixes = [];
  let cursor;
  do {
    const page = await bucket.list({ ...options, cursor, limit: 1000 });
    out.push(...page.objects);
    prefixes.push(...(page.delimitedPrefixes || []));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return { objects: out, prefixes };
}

/** Each film's title as the project's record names it — the Mac's folder
 * name for the film, which its backups are filed under. */
async function recordTitles(env) {
  const out = {};
  const { prefixes } = await listAll(env.BUCKET, { prefix: "r/", delimiter: "/" });
  for (const p of prefixes) {
    const got = await env.BUCKET.get(`${p}record.json`);
    if (!got) continue;
    try {
      const r = await got.json();
      const relay = r && r.film && String(r.film.relay || "");
      if (RELAY.test(relay) && r.film.title) out[relay] = String(r.film.title);
    } catch { /* an unreadable record names nothing */ }
  }
  return out;
}

async function manifestTitle(env, relay) {
  const got = await env.BUCKET.get(keys.manifest(relay));
  if (!got) return null;
  try { return String((await got.json()).title || ""); } catch { return ""; }
}

/** Every film on the relay — a prefix with a manifest; a portal with no
 * film has none — as `[{relay, title}]`, by title. */
export async function filmsOnRelay(env) {
  const titles = await recordTitles(env);
  const { prefixes } = await listAll(env.BUCKET, { prefix: "p/", delimiter: "/" });
  const out = [];
  for (const p of prefixes) {
    const relay = p.split("/")[1];
    if (!RELAY.test(relay)) continue;
    const named = await manifestTitle(env, relay);
    if (named === null) continue;
    out.push({ relay, title: titles[relay] || named || relay });
  }
  out.sort((a, b) => a.title.localeCompare(b.title));
  return out;
}

/** The film's change files as the relay holds them: names and sizes. */
async function changeList(env, relay) {
  const prefix = keys.logs(relay);
  const { objects } = await listAll(env.BUCKET, { prefix });
  return objects.map((o) => ({ name: o.key.slice(prefix.length), size: o.size }))
    .filter((f) => CHANGE_NAME.test(f.name));
}

/** …and their bytes, a few at a time. */
async function changeBytes(env, relay, list) {
  const out = [];
  for (let i = 0; i < list.length; i += READ_AT_ONCE) {
    const got = await Promise.all(list.slice(i, i + READ_AT_ONCE).map(async (f) => {
      const o = await env.BUCKET.get(keys.log(relay, f.name));
      if (!o) throw new Error(`${f.name} went while it was being read`);
      return { name: f.name, bytes: new Uint8Array(await o.arrayBuffer()) };
    }));
    out.push(...got);
  }
  return out;
}

/** The film's copies in the backups bucket, newest first, and the stamps
 * already in `forever/`. */
export async function copiesOf(env, relay) {
  const { objects } = await listAll(env.BACKUPS, { prefix: daily(relay), include: ["customMetadata"] });
  const copies = objects.map((o) => {
    const m = ZIP_NAME.exec(o.key.slice(daily(relay).length));
    if (!m) return null;
    const meta = o.customMetadata || {};
    return { stamp: m[1], at: new Date(o.uploaded).getTime(), size: o.size, fingerprint: meta.fingerprint || "", title: meta.title || "" };
  }).filter(Boolean).sort((a, b) => (a.stamp < b.stamp ? 1 : -1));
  const kept = (await listAll(env.BACKUPS, { prefix: forever(relay) })).objects
    .map((o) => (ZIP_NAME.exec(o.key.slice(forever(relay).length)) || [])[1]).filter(Boolean).sort().reverse();
  return { copies, forever: kept };
}

// ── the Drive ───────────────────────────────────────────────────────────────

/**
 * The few Drive calls backups need: list a folder, make a folder or a small
 * note, upload a zip, and put an old zip in the bin. `write: false` (a look)
 * reads with whichever sign-in there is and can do nothing else. Null with
 * no sign-in.
 */
export function backupDrive(env, { write = false } = {}) {
  const secret = env.GDRIVE_WRITE ? "GDRIVE_WRITE" : (!write && env.GDRIVE ? "GDRIVE" : "");
  if (!secret) return null;
  async function call(url, init = {}) {
    const access = await accessToken(env, secret);
    let got;
    try {
      got = await fetch(url, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${access}` } });
    } catch (e) {
      throw new Error(`couldn't reach Google Drive (${e && e.message})`);
    }
    if (got.status === 401 || got.status === 403) throw new DriveRefused(`Google Drive refused (${got.status}): ${(await got.text()).slice(0, 200)}`);
    if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
    return got.json();
  }
  const fields = "nextPageToken,files(id,name,mimeType,size,createdTime)";
  const api = {
    async list(parent) {
      const out = [];
      let page = "";
      do {
        const q = `'${parent}' in parents and trashed = false`;
        const got = await call(`${filesUrl(env)}?q=${encodeURIComponent(q)}&fields=${encodeURIComponent(fields)}&pageSize=1000`
          + `&supportsAllDrives=true&includeItemsFromAllDrives=true${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`);
        out.push(...(got.files || []).map((f) => ({ id: f.id, name: String(f.name || ""), folder: f.mimeType === FOLDER, size: Number(f.size || 0), created: f.createdTime ? Date.parse(f.createdTime) : NaN })));
        page = got.nextPageToken || "";
      } while (page);
      return out;
    },
  };
  if (write && secret === "GDRIVE_WRITE") {
    const multipart = async (parent, name, mime, bytes) => {
      const boundary = `filmbackup${crypto.randomUUID().replace(/-/g, "")}`;
      const enc = new TextEncoder();
      const head = enc.encode(`--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n`
        + `${JSON.stringify({ name, parents: [parent], mimeType: mime })}\r\n--${boundary}\r\ncontent-type: ${mime}\r\n\r\n`);
      const tail = enc.encode(`\r\n--${boundary}--`);
      const body = new Uint8Array(head.length + bytes.length + tail.length);
      body.set(head, 0); body.set(bytes, head.length); body.set(tail, head.length + bytes.length);
      const got = await call(`${uploadUrl(env)}?uploadType=multipart&fields=${encodeURIComponent("id,name,size")}&supportsAllDrives=true`, {
        method: "POST", headers: { "content-type": `multipart/related; boundary=${boundary}` }, body,
      });
      if (!got || !got.id) throw new Error(`Google Drive did not take ${name}`);
      return got;
    };
    api.mkdir = async (parent, name) => {
      const got = await call(`${filesUrl(env)}?fields=${encodeURIComponent("id,name")}&supportsAllDrives=true`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, mimeType: FOLDER, parents: [parent] }),
      });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      return got;
    };
    api.note = (parent, name, text) => multipart(parent, name, "text/plain", new TextEncoder().encode(text));
    // Google's one-request upload takes up to 5 MB. His biggest film packs to
    // well under 1 MB (Call Her Back: 5 MB of logs, 0.8 MB zipped), so a
    // bigger one is said as trouble rather than half-handled; its bucket
    // copy is made all the same.
    api.upload = (parent, name, bytes) => {
      if (bytes.length > 5 * 1024 * 1024) throw new Error(`${name} is over 5 MB, too big for the Drive upload this uses — the bucket has it`);
      return multipart(parent, name, "application/zip", bytes);
    };
    /** To the bin, never deleted: the Drive keeps it 30 days. */
    api.trash = async (id) => {
      await call(`${filesUrl(env)}/${encodeURIComponent(id)}?fields=id&supportsAllDrives=true`, {
        method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ trashed: true }),
      });
    };
  }
  return api;
}

const NOTE = `Shotlister backups, made by the server
======================================

One zip per film per day it changed, made by your-domain.example every
morning from the copy of the film on the sync relay. Each holds that film's
complete history — every shot, every scene, every edit — as it stood then.
Photographs are not in here, on purpose (they are never deleted from the relay).

TO GO BACK TO AN OLDER VERSION
------------------------------
On the Mac, "Restore a Film" pointed at this folder lists them and puts the one
you pick on your Desktop under its own name. The film you are working in is
never touched.

Every copy is kept 90 days. A film's newest copy is never removed. Older ones
go to the Drive's bin (kept there 30 days). The same copies are also kept in a
locked store on the server that nothing can delete early.
`;

/** The backups folder on the Drive: the switch's, or `My Drive/shotlister-backups`
 * found by name — or made, on a write, with its note, and remembered. */
async function backupsFolder(env, drive, { write }) {
  const s = await settingsOf(env);
  if (s.folder) return { id: s.folder };
  const found = (await drive.list("root")).find((f) => f.folder && f.name === DRIVE_FOLDER);
  if (found) {
    if (write) await keepJson(env, SWITCH_KEY, { ...s, folder: found.id });
    return { id: found.id };
  }
  if (!write) return { id: null, would: `would make My Drive/${DRIVE_FOLDER}` };
  const made = await drive.mkdir("root", DRIVE_FOLDER);
  await drive.note(made.id, "What these are.txt", NOTE);
  await keepJson(env, SWITCH_KEY, { ...s, folder: made.id });
  return { id: made.id, made: true };
}

/** The film's folder in it, by name as `restore.sh` finds one (case blind). */
async function filmFolder(drive, parent, title, { write }) {
  const want = folderName(title).toLowerCase();
  const found = (await drive.list(parent)).find((f) => f.folder && f.name.toLowerCase() === want);
  if (found) return found.id;
  if (!write) return null;
  return (await drive.mkdir(parent, folderName(title))).id;
}

// ── one film ────────────────────────────────────────────────────────────────

/**
 * One film's look, and unless `dry`, its work: a new copy when its change
 * files moved, the newest copy onto the Drive if it is not there yet, and the
 * tidy-up in both places. Answers what happened, in parts, never throwing for
 * the Drive (a Drive trouble is said, and the next day's look catches up).
 */
export async function backupFilm(env, film, { when = Date.now(), dry = false } = {}) {
  const { relay, title } = film;
  const out = { relay, title, state: "", stamp: "", bytes: 0, files: 0, where: "", pruned: [], forever: null, drive: {}, trouble: [] };
  const list = await changeList(env, relay);
  out.files = list.length;
  out.bytes = list.reduce((n, f) => n + f.size, 0);
  if (!list.length) { out.state = "nothing"; return out; }
  const print = await fingerprint(list);
  const held = await copiesOf(env, relay);
  const newest = held.copies[0];
  let copies = held.copies;
  if (newest && newest.fingerprint === print) {
    out.state = "unchanged";
    out.stamp = newest.stamp;
  } else if (dry) {
    out.state = "would copy";
  } else {
    const stamp = stampOf(when);
    if (newest && newest.stamp === stamp) throw new Error("a copy of it was taken this very minute — ask again in a minute");
    const manifest = await env.BUCKET.get(keys.manifest(relay));
    const zip = await makeZip({
      title, relay, manifest: manifest ? new Uint8Array(await manifest.arrayBuffer()) : null,
      changes: await changeBytes(env, relay, list), remote: remoteJson(relay),
    }, when);
    await env.BACKUPS.put(daily(relay, stamp), zip, {
      httpMetadata: { contentType: "application/zip" },
      customMetadata: { fingerprint: print, title, files: String(list.length) },
    });
    out.state = "made";
    out.stamp = stamp;
    out.size = zip.length;
    copies = [{ stamp, at: when, size: zip.length, fingerprint: print, title }, ...copies];
  }
  out.where = out.stamp ? serverPath(relay, out.stamp) : "";

  // The tidy-up in the bucket, and a quiet film's last copy put away for good.
  const rule = retention(copies, when, { forever: held.forever });
  out.pruned = rule.prune;
  out.forever = rule.forever;
  if (!dry) {
    for (const stamp of rule.prune) {
      try { await env.BACKUPS.delete(daily(relay, stamp)); } catch (e) { out.trouble.push(`could not remove ${stamp} (${short(e)})`); }
    }
    if (rule.forever) {
      const got = await env.BACKUPS.get(daily(relay, rule.forever));
      if (got) {
        await env.BACKUPS.put(forever(relay, rule.forever), await got.arrayBuffer(), {
          httpMetadata: { contentType: "application/zip" }, customMetadata: got.customMetadata || {},
        });
      }
    }
  }

  // The Drive: the newest copy there, and its tidy-up.
  try {
    out.drive = await driveSide(env, film, copies, rule, { when, dry });
    if (out.state === "would copy") out.drive.upload = "the new copy";
    if (out.drive.at) out.where = out.drive.at;
  } catch (e) {
    out.drive = { trouble: short(e) };
    out.trouble.push(`Drive: ${short(e)}`);
  }
  return out;
}

async function driveSide(env, film, copies, rule, { when, dry }) {
  const drive = backupDrive(env, { write: !dry });
  if (!drive) return { trouble: dry ? "no Google sign-in" : "no Google sign-in that can write (GDRIVE_WRITE)" };
  const root = await backupsFolder(env, drive, { write: !dry });
  const newest = copies[0];
  if (!root.id) return { would: root.would, upload: newest ? newest.stamp : null, prune: [] };
  const folder = await filmFolder(drive, root.id, film.title, { write: !dry && Boolean(newest) });
  const there = folder ? (await drive.list(folder)).filter((f) => !f.folder && ZIP_NAME.test(f.name)) : [];
  const out = { upload: null, prune: [] };
  if (newest && !there.some((f) => f.name === `${newest.stamp}.zip`)) {
    out.upload = newest.stamp;
    if (!dry) {
      const got = await env.BACKUPS.get(daily(film.relay, newest.stamp));
      if (!got) throw new Error(`the copy ${newest.stamp} is not in the bucket`);
      await drive.upload(folder, `${newest.stamp}.zip`, new Uint8Array(await got.arrayBuffer()));
      there.push({ name: `${newest.stamp}.zip`, created: when });
    }
  }
  if (newest && (there.some((f) => f.name === `${newest.stamp}.zip`))) out.at = drivePath(film.title, newest.stamp);
  // The same rule over what the Drive holds, by its own dates; no forever/
  // there, the newest staying is the Drive's keep-for-good.
  const driveRule = retention(there.map((f) => ({ stamp: ZIP_NAME.exec(f.name)[1], at: Number.isFinite(f.created) ? f.created : undefined })),
    when, {}, { ...KEEP, forever: false });
  out.prune = driveRule.prune;
  if (!dry) for (const stamp of driveRule.prune) await drive.trash(there.find((f) => f.name === `${stamp}.zip`).id);
  return out;
}

// ── the day ─────────────────────────────────────────────────────────────────

async function dayState(env) {
  const got = await env.BUCKET.get(DAY_KEY);
  if (!got) return { value: null, etag: null };
  try { return { value: await got.json(), etag: got.etag }; } catch { return { value: null, etag: got.etag }; }
}

/**
 * The worker's minute. From `START_HOUR` on his clock, a few films a minute
 * until each has had its look that day; the day's progress and what was done
 * are kept at `s/filmbackup-day.json`. A tick that finds another still at
 * work leaves it be.
 */
export async function onFilmBackupTimer(env, when = Date.now()) {
  if (!env.BACKUPS || !(await settingsOf(env)).on) return null;
  if (hourOf(when) < START_HOUR) return null;
  const day = dayOf(when);
  let { value: s, etag } = await dayState(env);
  if (s && s.day === day && s.next >= (s.films || []).length) return null;
  if (s && s.day === day && s.busy_until && s.busy_until > when) return null;
  if (!s || s.day !== day) {
    s = { day, started: new Date(when).toISOString(), films: await filmsOnRelay(env), next: 0, made: [], unchanged: [], nothing: [], pruned: [], forever: [], drive: [], trouble: [] };
  }
  s.busy_until = when + 50 * 1000;
  const claimed = await env.BUCKET.put(DAY_KEY, JSON.stringify(s), {
    httpMetadata: { contentType: "application/json" },
    onlyIf: etag ? { etagMatches: etag } : { etagDoesNotMatch: "*" },
  });
  if (!claimed) return null;
  let looked = 0;
  while (s.next < s.films.length && looked < PER_TICK) {
    const film = s.films[s.next];
    looked += 1;
    s.next += 1;
    let got;
    try {
      got = await backupFilm(env, film, { when });
    } catch (e) {
      s.trouble.push(`${film.title}: ${short(e)}`);
      continue;
    }
    const tag = `${film.title} ${got.stamp}`.trim();
    if (got.state === "made") s.made.push(`${tag} (${got.size} bytes)`);
    else if (got.state === "unchanged") s.unchanged.push(film.title);
    else s.nothing.push(film.title);
    for (const p of got.pruned) s.pruned.push(`${film.title} ${p}`);
    if (got.forever) s.forever.push(`${film.title} ${got.forever}`);
    if (got.drive && got.drive.upload) s.drive.push(`${film.title} ${got.drive.upload} up`);
    for (const p of (got.drive && got.drive.prune) || []) s.drive.push(`${film.title} ${p} to the bin`);
    for (const t of got.trouble) s.trouble.push(`${film.title}: ${t}`);
    if (got.state === "made") break;   // one film's logs read a minute, at most
  }
  delete s.busy_until;
  if (s.next >= s.films.length) s.finished = new Date(when).toISOString();
  await keepJson(env, DAY_KEY, s);
  return s;
}

// ── the look, the run, and the phone ────────────────────────────────────────

/** What a run would do now, writing nothing: every film, or the one named
 * (by title or relay id). */
export async function look(env, { name = "", when = Date.now() } = {}) {
  if (!env.BACKUPS) return { ok: false, why: "the server has no backups bucket (BACKUPS)", ...readiness(env) };
  const films = await pick(env, name);
  const out = [];
  for (const film of films) {
    try { out.push(await backupFilm(env, film, { when, dry: true })); } catch (e) { out.push({ ...film, trouble: [short(e)] }); }
  }
  return {
    ok: true, on: (await settingsOf(env)).on, ...readiness(env),
    would_copy: out.filter((f) => f.state === "would copy").map((f) => `${f.title} (${f.files} files, ${f.bytes} bytes before packing)`),
    films: out,
  };
}

/** Copies now, switch on only: every film, or the one named. */
export async function runNow(env, { name = "", when = Date.now() } = {}) {
  if (!(await backupsOn(env))) return { ok: false, why: "the switch is off, or there is no backups bucket" };
  const out = [];
  for (const film of await pick(env, name)) {
    try { out.push(await backupFilm(env, film, { when })); } catch (e) { out.push({ ...film, trouble: [short(e)] }); }
  }
  return { ok: true, films: out };
}

async function pick(env, name) {
  const all = await filmsOnRelay(env);
  if (!name) return all;
  const want = String(name).toLowerCase();
  return all.filter((f) => f.relay === name || f.title.toLowerCase() === want);
}

/** The project's film, as the Mac's `_film_title` finds it: the project's
 * Notion row, then its record's film. Null when it has none. */
async function projectFilm(env, n, name) {
  const { projectRow } = await import("./cloud.js");
  const row = await projectRow(n, name);
  if (!row) return null;
  const page = String(row.id || "").replace(/-/g, "").toLowerCase();
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  let record;
  try { record = await got.json(); } catch { return null; }
  const relay = String((record.film && record.film.relay) || "");
  if (!RELAY.test(relay)) return null;
  const title = String(record.film.title || "") || (await manifestTitle(env, relay)) || relay;
  return { relay, title };
}

/** backend.film_backup — a copy now, in `backup.sh`'s words. */
export async function phoneBackup(env, n, name, when = Date.now()) {
  const film = await projectFilm(env, n, name);
  if (!film) return { ok: false, why: "no film to back up" };
  let got;
  try {
    got = await backupFilm(env, film, { when });
  } catch (e) {
    return { ok: false, why: `"${film.title}" could not be packed (${short(e)})` };
  }
  if (got.state === "nothing") return { ok: false, why: `"${film.title}" has nothing to back up yet` };
  const said = saidOf(got.state, film.title, got.where);
  return { ok: true, said, unchanged: got.state === "unchanged", ...(got.trouble.length ? { trouble: got.trouble } : {}) };
}

/** backend.film_backups — the copies there are, newest first. */
export async function phoneBackups(env, n, name) {
  const film = await projectFilm(env, n, name);
  if (!film) return { ok: false, why: "no film", backups: [] };
  const held = await copiesOf(env, film.relay);
  const stamps = [...new Set([...held.copies.map((c) => c.stamp), ...held.forever])].sort().reverse();
  const size = Object.fromEntries(held.copies.map((c) => [c.stamp, c.size]));
  return {
    ok: true,
    backups: stamps.map((stamp) => ({
      stamp, zip: drivePath(film.title, stamp), door: ["/console/studio/filmbackup/zip", film.relay, stamp].join("/"),
      ...(size[stamp] ? { size: size[stamp] } : {}), ...(held.forever.includes(stamp) ? { forever: true } : {}),
    })),
  };
}

/** One copy's bytes, from `daily/` or else `forever/`, for the restore door. */
export async function zipOf(env, relay, stamp) {
  if (!env.BACKUPS || !RELAY.test(String(relay)) || !/^\d{4}-\d{2}-\d{2}-\d{4}$/.test(String(stamp))) return null;
  const got = (await env.BACKUPS.get(daily(relay, stamp))) || (await env.BACKUPS.get(forever(relay, stamp)));
  if (!got) return null;
  const title = (got.customMetadata && got.customMetadata.title) || relay;
  return { body: got.body, size: got.size, name: `${folderName(title)} ${stamp}.zip` };
}
