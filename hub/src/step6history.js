/**
 * Stage 5 step 6, group "history": the console-wide activity log and its
 * undo, kept on the server so every device sees one log (his answer: undo is
 * kept and shared across devices; undo lasts 30 days, batch 4 answer 8).
 *
 * The Mac's log (engine.py `record_activity` / `activity_list` /
 * `undo_activity`) is one line per action in `activity.jsonl`:
 *   {ts: "2026-10-09T10:07:55" (the Mac's wall clock), kind, desc, undo}
 * where `undo` is null or {type: "rename"|"link"|"icon"|"file-move", ...}.
 * Here each entry is ONE object under `activity/`, so two devices writing at
 * the same moment never lose each other's line:
 *   activity/<9999999999999 - at, 13 digits>-<id>.json
 * Newest sorts first, so the newest N are one list call. `id` is the
 * writer's: "srv-<random>" for the server's own, "mac-<hash>" for a Mac's
 * line (the same line always has the same id, so shipping it twice writes
 * it once). Nothing is ever deleted here; the list shows the newest 60, as
 * the Mac's does, and undo refuses an entry older than 30 days.
 *
 * Undo goes through the same Notion calls the Mac's makes: `link` (take the
 * project off the doc's Projects relation) and `icon` (put the old icon
 * back). `file-move` is a file on a Mac's Drive mount and `rename` calls a
 * function the Mac no longer has (engine.tidy_rename): both, and anything
 * unknown, go back to the Mac (null), which answers exactly as before.
 *
 * Rule: NO static import of cloud.js / studio.js here (they import step6.js,
 * which imports this file): use `await import("./cloud.js")` inside functions.
 */

/** The switch: `s/step6-history.json` {on, at, by}; door at /console/studio/step6history. */
export const SWITCH = "step6history";
/** Every ask this group answers (listed to the Mac and phone only while the switch is on). */
export const METHODS = new Set(["activity_undo"]);
/** Of those, reads answered on the spot (`POST /console/studio/now`). */
export const NOW = new Set([]);
/** Asks too slow for the 20 s reply: kept working by the server (later.js). */
export const LATER_WRITES = new Set([]);
export const LATER_READS = new Set([]);

export const PREFIX = "activity/";
/** engine.activity_list(limit=60). */
export const LIST_LIMIT = 60;
/** Undo lasts 30 days (his batch 4 answer 8). */
export const UNDO_DAYS = 30;
const DAY_MS = 86400000;
const TOP = 9999999999999;
const ID = /^(srv|mac)-[a-z0-9]{6,40}$/;
const KINDS = /^[a-z][a-z0-9-]{0,39}$/;
/** A shipped batch, and one entry, at most. */
const MAX_BATCH = 100;
const MAX_ENTRY = 8192;

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);

/** The object's name for an entry. */
export function keyOf(at, id) {
  const rev = String(Math.max(0, TOP - Math.floor(Number(at) || 0))).padStart(13, "0");
  return `${PREFIX}${rev}-${id}.json`;
}

/** The Mac's `ts` shape, "YYYY-MM-DDTHH:MM:SS", on his wall clock. */
export function wallClock(ms, zone = "America/Vancouver") {
  try {
    const s = new Date(ms).toLocaleString("sv-SE", { timeZone: zone, hour12: false });
    return s.replace(" ", "T").slice(0, 19);
  } catch {
    return new Date(ms).toISOString().slice(0, 19);
  }
}

function randomId() {
  const a = new Uint8Array(8);
  crypto.getRandomValues(a);
  return `srv-${[...a].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

/** One entry made whole and safe to keep, or a reason it is refused. */
export function cleanEntry(e) {
  if (!isObject(e)) return { why: "not an entry" };
  const id = String(e.id || "");
  if (!ID.test(id)) return { why: "bad id" };
  const at = Number(e.at);
  if (!Number.isFinite(at) || at <= 0 || at > TOP) return { why: "bad time" };
  const kind = String(e.kind || "");
  if (!KINDS.test(kind)) return { why: "bad kind" };
  const undo = e.undo === null || e.undo === undefined ? null : e.undo;
  if (undo !== null && !(isObject(undo) && typeof undo.type === "string")) return { why: "bad undo" };
  const out = {
    id, at: Math.floor(at), ts: String(e.ts || "").slice(0, 32), kind,
    desc: String(e.desc == null ? "" : e.desc).slice(0, 2000), undo,
    from: String(e.from || "").slice(0, 80),
  };
  if (JSON.stringify(out).length > MAX_ENTRY) return { why: "too big" };
  return { entry: out };
}

/**
 * The writer every server ask can call (engine.record_activity's twin):
 * `await logActivity(env, {kind, desc, undo})`. Never throws: a log line that
 * cannot be kept must not fail the action it describes.
 */
export async function logActivity(env, entry, { now = Date.now(), from = "server" } = {}) {
  try {
    const e = isObject(entry) ? entry : {};
    const got = cleanEntry({
      id: randomId(), at: now, ts: wallClock(now, env && env.TZ_NAME), from,
      kind: e.kind, desc: e.desc, undo: e.undo === undefined ? null : e.undo,
    });
    if (!got.entry) return null;
    await env.BUCKET.put(keyOf(got.entry.at, got.entry.id), JSON.stringify(got.entry), { httpMetadata: { contentType: "application/json" } });
    return got.entry;
  } catch (err) {
    console.error("activity log:", String((err && err.stack) || err));
    return null;
  }
}

/** A device's own lines, shipped (the Mac's outbox): each kept under its own id; the same line twice is one object. */
export async function addEntries(env, list) {
  if (!Array.isArray(list)) return { ok: false, why: "no entries" };
  if (list.length > MAX_BATCH) return { ok: false, why: `at most ${MAX_BATCH} at a time` };
  const kept = [], refused = [];
  for (const raw of list) {
    const got = cleanEntry(raw);
    if (!got.entry) { refused.push({ id: isObject(raw) ? String(raw.id || "").slice(0, 60) : "", why: got.why }); continue; }
    await env.BUCKET.put(keyOf(got.entry.at, got.entry.id), JSON.stringify(got.entry), { httpMetadata: { contentType: "application/json" } });
    kept.push(got.entry.id);
  }
  return { ok: true, kept, refused };
}

/** The newest `limit` entries, newest first (engine.activity_list's order). */
export async function listActivity(env, limit = LIST_LIMIT) {
  const want = Math.max(1, Math.min(500, Math.floor(Number(limit) || LIST_LIMIT)));
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: PREFIX, cursor, limit: Math.min(1000, want - keys.length) });
    for (const o of got.objects || []) keys.push(o.key);
    cursor = got.truncated && keys.length < want ? got.cursor : undefined;
  } while (cursor);
  keys.sort();
  const out = await Promise.all(keys.slice(0, want).map(async (k) => {
    try {
      const got = await env.BUCKET.get(k);
      if (!got) return null;
      const e = await got.json();
      return isObject(e) ? e : null;
    } catch { return null; }
  }));
  return out.filter(Boolean);
}

/** engine.undo_activity, for what the server can reach (Notion). null = the Mac's. */
export async function undoEntry(env, entry, { now = Date.now(), notion = null } = {}) {
  const e = isObject(entry) ? entry : {};
  const u = isObject(e.undo) ? e.undo : {};
  const k = u.type;
  // A big move (bigmoves.js, stage 5 step 7): its own undo, kept with the move.
  if (k === "bigmove") {
    const big = await import("./bigmoves.js");
    const w = await big.worldOf(env, { write: true, by: "history" });
    const got = await big.undo(w, u.move_id);
    if (!got.ok) throw new Error(got.why);
    return got.report;
  }
  if (k !== "link" && k !== "icon") return null;      // file-move, rename, unknown: the Mac's, word for word
  const at = Number(e.at) || atOfTs(e.ts);
  if (at && now - at > UNDO_DAYS * DAY_MS) throw new Error(`Undo lasts ${UNDO_DAYS} days.`);
  const cloud = await import("./cloud.js");
  const n = notion || cloud.notionOf(env);
  if (k === "link") {
    const page = await n.get(`pages/${u.doc}`);
    const rel = (((page || {}).properties || {}).Projects || {}).relation || [];
    const kept = rel.filter((r) => r.id !== u.project).map((r) => ({ id: r.id }));
    await n.patch(`pages/${u.doc}`, { properties: { Projects: { relation: kept } } });
    return "Unlinked";
  }
  await n.patch(`pages/${u.page}`, { icon: u.old_icon });
  return "Icon restored";
}

/** A Mac `ts` (its wall clock) read as near enough for the 30 days. */
export function atOfTs(ts) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/.exec(String(ts || ""));
  if (!m) return 0;
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
}

/** `async (list, env) => result` per method; return null to hand the ask to the Mac. */
export const ASKS = {
  async activity_undo([entry], env) {
    return undoEntry(env, entry);
  },
};

/** The dry look: what the log holds and who would undo what. Writes nothing. */
export async function look(env) {
  const entries = await listActivity(env, 500);
  const kinds = {}, undo = { server: 0, mac: 0, none: 0 }, from = {};
  for (const e of entries) {
    kinds[e.kind] = (kinds[e.kind] || 0) + 1;
    from[e.from || "?"] = (from[e.from || "?"] || 0) + 1;
    const t = isObject(e.undo) ? e.undo.type : null;
    if (!t) undo.none += 1; else if (t === "link" || t === "icon") undo.server += 1; else undo.mac += 1;
  }
  return {
    ok: true, entries: entries.length, kinds, from, undo,
    newest: entries.length ? entries[0].ts : "", oldest: entries.length ? entries[entries.length - 1].ts : "",
    server_undoes: ["link", "icon"], mac_undoes: ["file-move", "rename"], undo_days: UNDO_DAYS, list_limit: LIST_LIMIT,
  };
}

/**
 * The group's own doors:
 *   GET  /console/studio/step6history/log?limit=60  the shared log, newest first
 *   POST /console/studio/step6history/add {entries}  a device's lines (switch on only)
 *   GET  /console/studio/step6history/look           the dry look
 */
export async function door(env, rest, method, readBody, ctx, url) {
  const what = rest[1];
  if (what === "log" && method === "GET") {
    const { groupOn } = await import("./step6.js");
    const on = await groupOn(env, await import("./step6history.js"));
    const limit = url ? url.searchParams.get("limit") : null;
    return Response.json({ ok: true, on, entries: await listActivity(env, limit || LIST_LIMIT) });
  }
  if (what === "add" && method === "POST") {
    const { groupOn } = await import("./step6.js");
    if (!(await groupOn(env, await import("./step6history.js")))) return Response.json({ ok: false, why: "off" });
    const body = await readBody();
    return Response.json(await addEntries(env, body && body.entries));
  }
  if (what === "look" && method === "GET") {
    const { groupOn } = await import("./step6.js");
    return Response.json({ ...(await look(env)), on: await groupOn(env, await import("./step6history.js")) });
  }
  return null;
}
