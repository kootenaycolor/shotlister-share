/**
 * **Film backups, made by the server** (2026-10-13, Projects Console without
 * the Mac, stage 4 part C). The rules: what a snapshot holds, what it is
 * called, when one is needed, and which old ones go. The bucket, the Drive
 * and the clock are `filmbackuprun.js`; nothing in this file reads or writes
 * anywhere, so `hub/filmbackup.mjs` checks every rule in plain node.
 *
 * **Why it exists** is the header of Shotlister's `backup/backup.sh`, and it
 * still holds: the relay and iCloud are sync, not backup. Delete a scene by
 * mistake and both carry the deletion everywhere within seconds. A backup is
 * a copy of *last Tuesday*. The Mac's daily run never actually ran (launchd
 * was refused iCloud Drive every day), so this is the first one that does.
 *
 * **A snapshot is the zip `backup.sh` makes**, entry for entry, so the Mac's
 * own `restore.sh` and "Restore a Film" open a server copy as they open one
 * of their own:
 *
 *     <Film>.shotlist/                  a folder entry
 *     <Film>.shotlist/changes/          a folder entry
 *     <Film>.shotlist/changes/<name>    every log, device mark and fold record
 *                                       (the relay's `logs/` is the film's `changes/`)
 *     <Film>.shotlist/manifest.json     the film's birth certificate
 *     <Film>.shotlist/remote.json       which relay project it is, so a restored
 *                                       film still knows where it syncs
 *
 * Not the pictures, for `backup.sh`'s reasons: they are written once under
 * their own hash and the relay never deletes one. What the Mac's zip has and
 * this one does not is `__MACOSX/`, where `ditto` files each file's Finder
 * labels (only `com.apple.provenance` on his films); there is nothing of the
 * film in it and nothing to label on a server. Unpacked, the two are the same
 * files with the same bytes (`hub/filmbackup.mjs` runs both and compares).
 *
 * **When one is taken**: when the film's change files are not what they were
 * at its last snapshot, judged as `backup.sh` judges it — the files' names and
 * sizes (a log only ever grows), fingerprinted the same way, so the two
 * fingerprints of one film agree.
 *
 * **How long they are kept** — his rule of 2026-10-13, in one place, `KEEP`:
 * every copy for 90 days; a film's newest copy never, however old (so a film
 * nobody touches for a year still has its last state); and once that newest
 * copy has been the newest for the whole 90 days — the film has gone quiet —
 * it is also put in the bucket's `forever/` folder, which is locked for good
 * (`filmbackuprun.js` has the lock rules). Change a number here and both
 * places, the bucket and the Drive, follow.
 */

export const KEEP = {
  /** Every copy younger than this is kept, and the bucket's `daily/` folder
   * is locked for exactly this long, so nothing can take one sooner. */
  days: 90,
  /** One day's grace before the tidy-up takes a copy, so it never races the
   * lock (which counts from the moment the copy was put). */
  graceDays: 1,
  /** A film's newest copy is never removed, however old. */
  newest: true,
  /** …and once it is older than `days`, it is also copied into `forever/`,
   * the folder locked indefinitely. */
  forever: true,
};

/** The stamps and the zip's own times are his clock, as the Mac's were. */
export const ZONE = "America/Vancouver";
export const DAY_MS = 24 * 3600 * 1000;
export const STAMP = /^(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})$/;
export const ZIP_NAME = /^(\d{4}-\d{2}-\d{2}-\d{4})\.zip$/;
/** The names the relay keeps under a film's `logs/` (relay/layout.json):
 * change logs, device marks and fold records — all of the Mac's `changes/`. */
export const CHANGE_NAME = /^[0-9a-f]{16}(-[0-9a-f]{16}\.(log|device)|\.folded)$/;
const RELAY_HOST = "https://sync.your-domain.example";

function parts(ms) {
  const got = {};
  for (const p of new Intl.DateTimeFormat("en-CA", {
    timeZone: ZONE, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
  }).formatToParts(new Date(ms))) got[p.type] = p.value;
  return got;
}

/** `date "+%Y-%m-%d-%H%M"` on his clock: a snapshot's name. */
export function stampOf(ms) {
  const p = parts(ms);
  return `${p.year}-${p.month}-${p.day}-${p.hour}${p.minute}`;
}

/** His calendar day, for the once-a-day run. */
export function dayOf(ms) {
  return stampOf(ms).slice(0, 10);
}

/** His hour of the day, 0-23. */
export function hourOf(ms) {
  return Number(parts(ms).hour);
}

/** Roughly when a stamp was (his clock, read as UTC: off by his offset at
 * most, which no rule here is fine enough to notice). */
export function stampMs(stamp) {
  const m = STAMP.exec(String(stamp || ""));
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) : NaN;
}

/** A film's folder name: its title, as the Mac's film folder is named, with
 * the two characters a folder cannot carry made into dashes. */
export function folderName(title, relay = "") {
  const clean = String(title || "").replace(/[/:]/g, "-").replace(/[\u0000-\u001f]/g, "").trim().replace(/^\.+/, "");
  return clean.slice(0, 120) || String(relay || "film");
}

/** `remote.json` as Shotlister writes it (Swift escapes its slashes). */
export function remoteJson(relay) {
  return JSON.stringify({ relay: RELAY_HOST, project: String(relay), synced: true }).replace(/\//g, "\\/");
}

/**
 * The fingerprint `backup.sh` keeps in `.seen-<stamp>`: each change file as
 * `changes/<name> <size>`, sorted, one per line, through `shasum` (SHA-1).
 */
export function fingerprintText(files) {
  const lines = files.map((f) => `changes/${f.name} ${f.size}`);
  lines.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return lines.map((l) => `${l}\n`).join("");
}

export async function fingerprint(files) {
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(fingerprintText(files)));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── the zip ─────────────────────────────────────────────────────────────────

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

async function deflate(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** DOS date and time, on his clock, as `ditto` writes them. */
function dosTime(ms) {
  const p = parts(ms);
  const time = (Number(p.hour) << 11) | (Number(p.minute) << 5) | Math.floor(Number(p.second) / 2);
  const date = ((Number(p.year) - 1980) << 9) | (Number(p.month) << 5) | Number(p.day);
  return { time, date };
}

const asBytes = (x) => (x instanceof Uint8Array ? x : typeof x === "string" ? new TextEncoder().encode(x) : new Uint8Array(x));

/**
 * The snapshot: `{title, manifest, changes: [{name, bytes}], remote}` → the
 * zip's bytes. Folders first, then the change files in name order, then the
 * manifest and `remote.json`. A folder or an empty file is stored; anything
 * else is deflated. Unix modes as the Mac's (`drwxr-xr-x`, `-rw-r--r--`).
 */
export async function makeZip({ title, relay = "", manifest, changes, remote }, when = Date.now()) {
  const top = `${folderName(title, relay)}.shotlist/`;
  const entries = [{ name: top, dir: true }, { name: `${top}changes/`, dir: true }];
  const sorted = [...changes].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const c of sorted) entries.push({ name: `${top}changes/${c.name}`, bytes: asBytes(c.bytes) });
  if (manifest !== undefined && manifest !== null) entries.push({ name: `${top}manifest.json`, bytes: asBytes(manifest) });
  if (remote !== undefined && remote !== null) entries.push({ name: `${top}remote.json`, bytes: asBytes(remote) });

  const { time, date } = dosTime(when);
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const e of entries) {
    const name = new TextEncoder().encode(e.name);
    const ascii = /^[\x20-\x7e]*$/.test(e.name);
    const raw = e.dir ? new Uint8Array(0) : e.bytes;
    const store = e.dir || raw.length === 0;
    const data = store ? raw : await deflate(raw);
    const crc = e.dir ? 0 : crc32(raw);
    const flags = ascii ? 0 : 0x0800;
    const needed = store ? 10 : 20;
    const local = new DataView(new ArrayBuffer(30));
    local.setUint32(0, 0x04034b50, true);
    local.setUint16(4, needed, true);
    local.setUint16(6, flags, true);
    local.setUint16(8, store ? 0 : 8, true);
    local.setUint16(10, time, true);
    local.setUint16(12, date, true);
    local.setUint32(14, crc, true);
    local.setUint32(18, data.length, true);
    local.setUint32(22, raw.length, true);
    local.setUint16(26, name.length, true);
    local.setUint16(28, 0, true);
    chunks.push(new Uint8Array(local.buffer), name, data);
    const head = new DataView(new ArrayBuffer(46));
    head.setUint32(0, 0x02014b50, true);
    head.setUint16(4, 0x0315, true);            // made by: Unix, 2.1 — as ditto's
    head.setUint16(6, needed, true);
    head.setUint16(8, flags, true);
    head.setUint16(10, store ? 0 : 8, true);
    head.setUint16(12, time, true);
    head.setUint16(14, date, true);
    head.setUint32(16, crc, true);
    head.setUint32(20, data.length, true);
    head.setUint32(24, raw.length, true);
    head.setUint16(28, name.length, true);
    head.setUint16(30, 0, true);
    head.setUint16(32, 0, true);
    head.setUint16(34, 0, true);
    head.setUint16(36, 0, true);
    head.setUint32(38, e.dir ? (((0o040755 << 16) | 0x10) >>> 0) : ((0o100644 << 16) >>> 0), true);
    head.setUint32(42, offset, true);
    central.push(new Uint8Array(head.buffer), name);
    offset += 30 + name.length + data.length;
  }
  const centralSize = central.reduce((n, c) => n + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(8, entries.length, true);
  end.setUint16(10, entries.length, true);
  end.setUint32(12, centralSize, true);
  end.setUint32(16, offset, true);
  const all = [...chunks, ...central, new Uint8Array(end.buffer)];
  const out = new Uint8Array(all.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of all) { out.set(c, at); at += c.length; }
  return out;
}

// ── the tidy-up ─────────────────────────────────────────────────────────────

/**
 * Which copies of one film stay. `copies` is `[{stamp, at}]`, `at` being when
 * the copy was put (ms; the stamp's time when that is all there is);
 * `forever` the stamps already in the locked-for-good folder. Answers
 * `{keep, prune, forever}`: stamps to keep, stamps to remove, and the stamp
 * to copy into `forever/` now (or null). Never prunes the newest copy, and
 * never one younger than `days` + `graceDays`.
 */
export function retention(copies, now, { forever = [] } = {}, keep = KEEP) {
  const list = copies
    .filter((c) => STAMP.test(String(c.stamp || "")))
    .map((c) => ({ stamp: c.stamp, at: Number.isFinite(c.at) ? c.at : stampMs(c.stamp) }))
    .sort((a, b) => (a.stamp < b.stamp ? 1 : a.stamp > b.stamp ? -1 : 0));
  const out = { keep: [], prune: [], forever: null };
  const held = new Set(forever);
  list.forEach((c, i) => {
    const old = now - c.at > (keep.days + keep.graceDays) * DAY_MS;
    if (i === 0 && keep.newest) {
      out.keep.push(c.stamp);
      if (keep.forever && now - c.at > keep.days * DAY_MS && !held.has(c.stamp)) out.forever = c.stamp;
      return;
    }
    (old ? out.prune : out.keep).push(c.stamp);
  });
  return out;
}

/** The one line the phone shows, in `backup.sh`'s words. */
export function saidOf(state, title, where) {
  if (state === "made") return `backed up: "${title}"  at "${where}"`;
  if (state === "unchanged") return `unchanged: "${title}"  at "${where}"`;
  return `refused: ${where}`;
}
