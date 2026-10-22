/**
 * **One ID per project** (2026-10-14, Projects Console without the Mac, stage
 * 5 step 2). His answers 6, 14 and 15: one record per project, the Studio
 * side made only when a mode is first switched on and under the same ID, and
 * a freshly minted ID for every new project with its Notion page kept as a
 * field.
 *
 * - **A project's ID** is the key of its record, `r/<id>/record.json`.
 *   Existing projects keep their Notion page id as that key, so nothing that
 *   exists moves. A project made while the switch is on gets a **minted** ID
 *   (32 hex, the shape page ids and relay ids already share) and its Notion
 *   page goes on the record as `notion_page` (`notion` is already the
 *   readout's Notion address, a URL).
 * - **The Studio side** (the relay film) of a new project lives at
 *   `p/<id>/`, under the same ID, made by `studioside.js` when it is first
 *   wanted. An existing project's film keeps its own relay id for good: that
 *   id is an **alias** of the project, never moved, so every sent link, the
 *   doc-follow index, rebuilt pages, the connector's remembered film,
 *   console snapshots and locked backups — all filed by it — keep working.
 *
 * The map of the two kinds of other id is one small file, `s/ids.json`:
 *
 *   { notion: {<notion page>: <id>},   only for minted projects
 *     alias:  {<relay id>: <id>},      a film's id, where it differs from its project's
 *     at }
 *
 * Entries are only ever added. `freezeAliases` fills `alias` from the records
 * as they stand (a dry look first); the record door adds one whenever a
 * record names a film under a different id.
 *
 * **Notion page → project ID at the bucket's door** (`byProjectId`). Most of
 * the server still finds a project by its Notion row (the phone's asks name a
 * project, `projectRow` finds the row, the row's id names the record), and the
 * Notion link walks Notion pages. Rather than teach thirty readers the map,
 * the bucket a request sees reads `r/<notion page>/…` from `r/<id>/…` when the
 * map says that page belongs to a minted project. With no minted project the
 * map is empty and nothing changes. A listing of `r/` is not translated: a
 * reader that lists records and then asks Notion uses `notionOf(record)`.
 *
 * **The switch** (`s/oneid.json`, off until thrown) decides the new
 * behaviour: minting at New Project, the Studio side made under the ID, the
 * `/f/` address serving a project directly with no carry. Off, the server
 * behaves exactly as before.
 */

import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/oneid.json";
export const IDS_KEY = "s/ids.json";
export const ID = /^[0-9a-f]{32}$/;

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
export const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

async function readJson(bucket, key) {
  const got = await bucket.get(key);
  if (!got) return null;
  try { return { value: await got.json(), etag: got.etag }; } catch { return { value: null, etag: got.etag }; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function oneIdOn(env) {
  const got = await readJson(env.BUCKET, SWITCH_KEY);
  const v = got && isObject(got.value) ? got.value : {};
  return { on: v.on === true, at: v.at || null, by: v.by || null };
}

export async function setOneId(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── minting ──────────────────────────────────────────────────────────────────

/** 32 hex characters from the platform's own random source. */
export function mintId() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * An ID nobody holds: no record, no film, no portal under it, and not in the
 * map. `wanted` is an ID a device minted itself (Studio's New Project sends
 * one, so it knows the project's ID before the server answers); it is taken
 * when free, else a fresh one is minted.
 */
export async function freeId(env, wanted = "") {
  const ids = await readIds(env);
  const taken = async (id) => Boolean(
    ids.notion[id] || ids.alias[id] || Object.values(ids.notion).includes(id)
    || await env.BUCKET.head(`r/${id}/record.json`)
    || await env.BUCKET.head(`p/${id}/manifest.json`)
    || await env.BUCKET.head(`p/${id}/portal.json`)
    || await env.BUCKET.head(`p/${id}/people.json`));
  const asked = bare(wanted);
  if (ID.test(asked) && !(await taken(asked))) return asked;
  for (let i = 0; i < 8; i++) {
    const id = mintId();
    if (!(await taken(id))) return id;
  }
  throw new Error("could not mint a free project ID");
}

// ── the map ──────────────────────────────────────────────────────────────────

export function idsShape(v) {
  const o = isObject(v) ? v : {};
  const clean = (m) => Object.fromEntries(Object.entries(isObject(m) ? m : {})
    .filter(([k, val]) => ID.test(k) && ID.test(String(val))));
  return { notion: clean(o.notion), alias: clean(o.alias), at: o.at || null };
}

export async function readIds(env) {
  const got = await readJson(env.BUCKET, IDS_KEY);
  return idsShape(got && got.value);
}

/** Add entries, compare-and-set; an entry already there is never changed. */
export async function addIds(env, { notion = {}, alias = {} } = {}) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const got = await readJson(env.BUCKET, IDS_KEY);
    const ids = idsShape(got && got.value);
    const added = { notion: {}, alias: {} };
    const clashes = [];
    for (const [kind, want] of [["notion", notion], ["alias", alias]]) {
      for (const [k0, v0] of Object.entries(want || {})) {
        const k = bare(k0), v = bare(v0);
        if (!ID.test(k) || !ID.test(v) || k === v) continue;
        if (ids[kind][k] === v) continue;
        if (ids[kind][k]) { clashes.push({ kind, id: k, has: ids[kind][k], wanted: v }); continue; }
        ids[kind][k] = v;
        added[kind][k] = v;
      }
    }
    if (!Object.keys(added.notion).length && !Object.keys(added.alias).length) return { added, clashes, ids };
    ids.at = new Date().toISOString();
    const saved = await env.BUCKET.put(IDS_KEY, JSON.stringify(ids, null, 1), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: got ? { etagMatches: got.etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return { added, clashes, ids };
  }
  throw new Error("the ID map kept changing while this was being written");
}

/** The Notion page a record stands for: its `notion_page` field, else its own key. */
export function notionOf(record, key = "") {
  if (isObject(record) && ID.test(bare(record.notion_page))) return bare(record.notion_page);
  const own = bare((isObject(record) && record.page) || key);
  return ID.test(own) ? own : "";
}

/** The record key for a Notion page: the minted ID the map holds, else the page itself. */
export async function keyOfPage(env, page) {
  const p = bare(page);
  if (!ID.test(p)) return "";
  return (await readIds(env)).notion[p] || p;
}

/**
 * **The one way to find a project.** Any ID somebody holds — the project's
 * own, its Notion page, its film's relay id — to `{key, via, record}`;
 * `{key: ""}` when it names no project. `via` says which: `key`, `notion` or
 * `alias`.
 */
export async function resolveProject(env, id) {
  const x = bare(id);
  if (!ID.test(x)) return { key: "", via: null, record: null };
  const recordAt = async (k) => {
    const got = await readJson(env.BUCKET, `r/${k}/record.json`);
    return got && isObject(got.value) ? got.value : null;
  };
  const ids = await readIds(env);
  // A minted project's Notion page first: under the bucket's door the page
  // would read the minted record anyway, and `via` should say so.
  if (ids.notion[x]) {
    const record = await recordAt(ids.notion[x]);
    if (record) return { key: ids.notion[x], via: "notion", record };
  }
  const own = await recordAt(x);
  if (own) return { key: x, via: "key", record: own };
  if (ids.alias[x]) {
    const record = await recordAt(ids.alias[x]);
    if (record) return { key: ids.alias[x], via: "alias", record };
  }
  return { key: "", via: null, record: null };
}

/** A project's Studio side as its record names it: the relay id, or "". */
export function studioOf(record) {
  const relay = bare(isObject(record) && isObject(record.film) ? record.film.relay : "");
  return ID.test(relay) || /^[0-9a-f]{8,64}$/.test(relay) ? relay : "";
}

// ── aliases, frozen ──────────────────────────────────────────────────────────

/**
 * Every record whose film lives under another id, as an alias of the
 * project. `dry` says what would be added and writes nothing. Never removes.
 */
export async function freezeAliases(env, { dry = true } = {}) {
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
  const ids = await readIds(env);
  const found = [];
  const want = {};
  const seen = {};
  for (const key of keys) {
    const got = await readJson(env.BUCKET, `r/${key}/record.json`);
    const record = got && isObject(got.value) ? got.value : null;
    if (!record) continue;
    const relay = studioOf(record);
    const row = { key, name: String(record.name || ""), relay, notion: notionOf(record, key) };
    if (!relay || !ID.test(relay) || relay === key) { found.push({ ...row, alias: false }); continue; }
    const had = ids.alias[relay];
    found.push({ ...row, alias: true, already: had === key, clash: had && had !== key ? had : undefined });
    if (!had) (seen[relay] ||= []).push(key);
  }
  // Two records naming one film (a test copy, a mistake) decide nothing: the
  // film is kept out of the map and both are said, for a person to settle.
  for (const [relay, keys] of Object.entries(seen)) {
    if (keys.length === 1) { want[relay] = keys[0]; continue; }
    for (const f of found) if (f.relay === relay) f.clash = keys.filter((k) => k !== f.key).join(",");
  }
  if (dry) return { dry: true, records: found.length, would_add: want, found };
  const got = await addIds(env, { alias: want });
  return { dry: false, records: found.length, added: got.added.alias, clashes: got.clashes, found };
}

// ── the bucket's door ────────────────────────────────────────────────────────

const RECORD_KEY = /^r\/([0-9a-f]{32})(\/.*)?$/;

/**
 * The bucket as a request sees it, with `r/<notion page>/…` read from and
 * written to `r/<id>/…` for every minted project. The map is read once, the
 * first time a record path is touched, and read again after anything writes
 * the map through this same bucket (so New Project can register an ID and
 * then write the record by its Notion page in one request).
 */
export function byProjectId(env) {
  if (!env || !env.BUCKET || env.BUCKET.__byProjectId) return env;
  const bucket = env.BUCKET;
  let map = null;
  const load = () => (map ||= readJson(bucket, IDS_KEY).then((got) => idsShape(got && got.value).notion).catch(() => ({})));
  const forget = (key) => { if (key === IDS_KEY) map = null; };
  const to = async (key) => {
    if (typeof key !== "string") return key;
    const m = RECORD_KEY.exec(key);
    if (!m) return key;
    const id = (await load())[m[1]];
    return id ? `r/${id}${m[2] || ""}` : key;
  };
  const wrapped = {
    __byProjectId: true,
    get: async (key, opts) => bucket.get(await to(key), opts),
    head: async (key) => bucket.head(await to(key)),
    put: async (key, value, opts) => { forget(key); const out = await bucket.put(await to(key), value, opts); forget(key); return out; },
    delete: async (key) => {
      if (Array.isArray(key)) return bucket.delete(await Promise.all(key.map(to)));
      forget(key);
      return bucket.delete(await to(key));
    },
    list: async (opts = {}) => {
      if (!opts || typeof opts.prefix !== "string" || !RECORD_KEY.test(opts.prefix.replace(/\/?$/, "/"))) return bucket.list(opts);
      const prefix = opts.prefix;
      const moved = await to(prefix.endsWith("/") ? prefix : `${prefix}/`);
      if (moved === (prefix.endsWith("/") ? prefix : `${prefix}/`)) return bucket.list(opts);
      return bucket.list({ ...opts, prefix: prefix.endsWith("/") ? moved : moved.slice(0, -1) });
    },
    createMultipartUpload: (...a) => bucket.createMultipartUpload(...a),
    resumeMultipartUpload: (...a) => bucket.resumeMultipartUpload(...a),
  };
  const out = Object.create(env);
  Object.defineProperty(out, "BUCKET", { value: wrapped });
  return out;
}
