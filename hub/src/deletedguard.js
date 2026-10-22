/**
 * **A deleted project stays gone** (2026-10-17).
 *
 * After "ZZ Close Test" was deleted from the console (2026-10-16 08:29), the
 * portal's own refresh clock wrote its front page and twelve link covers back
 * under its old id 98 seconds later: the refresh makes its list of cards at
 * the start of a pass and takes two a minute, and nothing asked again whether
 * a card on that list still existed. The leftovers had no project file and no
 * changes, and the shelf and the connector listed them as a nameless project.
 *
 * So a delete leaves a **tombstone** for every portal prefix it removes
 * (`bigmoves/deleted/<id>.json`, written by Delete, taken away by its Undo),
 * and the clocks write through `stayGone(env)`: a write under a prefix with a
 * tombstone — or with the relay's own "deleted" note (`gone/<id>.json`, which
 * Studio's Delete leaves) — is refused. Reads and deletes pass.
 *
 * With `anchors` (the refresh, one card at a time) a write under that
 * project's prefix also needs the project's own file to still be there: the
 * film's manifest, or a portal's mark. A card deleted while it was being
 * made is never written back.
 *
 * No import of `relay/layout.js` here on purpose: the node checks load this
 * without a JSON loader. The two names it needs are the layout's own.
 */

export const TOMBSTONES = "bigmoves/deleted/";
const UNDER = /^p\/([0-9a-f]{8,64})\//;
const ID = /^[0-9a-f]{8,64}$/;
const NOTE = /^(?:bigmoves\/deleted\/([0-9a-f]{8,64})|gone\/([0-9a-f]{8,64}))\.json$/;
/** How long a "not deleted" answer is believed inside one wrapper. */
const FRESH_MS = 5_000;

export const tombstoneKey = (id) => `${TOMBSTONES}${id}.json`;

/** The id a key is under (`p/<id>/…`), or "". */
export function prefixId(key) {
  const m = typeof key === "string" ? UNDER.exec(key) : null;
  return m ? m[1] : "";
}

async function readJson(bucket, key) {
  const got = await bucket.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return {}; }
}

/** Why this id is deleted — `{by: "delete"|"relay", …}` — or null when it is not. */
export async function deletedNote(bucket, id) {
  if (!ID.test(String(id || ""))) return null;
  const stone = await readJson(bucket, tombstoneKey(id));
  if (stone) return { by: "delete", ...stone };
  const gone = await readJson(bucket, `gone/${id}.json`);
  if (gone && gone.fate === "deleted") return { by: "relay", ...gone };
  return null;
}

export class StaysGone extends Error {
  constructor(id, why) {
    super(`${id} was deleted${why ? ` (${why})` : ""}; nothing is written under it.`);
    this.name = "StaysGone";
    this.project = id;
  }
}

/**
 * `env` whose bucket refuses writes under a deleted project's prefix.
 * `anchors`: `{ <id>: [key, …] }` — a write under `p/<id>/` also needs one of
 * these keys to exist at that moment (asked on every write, never cached).
 */
export function stayGone(env, { anchors = null } = {}) {
  if (!env || !env.BUCKET) return env;
  const bucket = env.BUCKET;
  const seen = new Map();
  const deleted = async (id) => {
    const had = seen.get(id);
    if (had && (had.note || Date.now() - had.at < FRESH_MS)) return had.note;
    const note = await deletedNote(bucket, id);
    seen.set(id, { note, at: Date.now() });
    return note;
  };
  const check = async (key) => {
    const id = prefixId(key);
    if (!id) return;
    const note = await deleted(id);
    if (note) throw new StaysGone(id, note.move_id || note.fate || "");
    const need = anchors && anchors[id];
    if (need && need.length) {
      for (const k of need) if (k === key || await bucket.head(k)) return;
      throw new StaysGone(id, "its project file is gone");
    }
  };
  const wrapped = Object.create(bucket);
  Object.defineProperty(wrapped, "__stayGone", { value: true });
  wrapped.get = (...a) => bucket.get(...a);
  wrapped.head = (...a) => bucket.head(...a);
  wrapped.list = (...a) => bucket.list(...a);
  // A note written or taken away is believed at once.
  const forget = (key) => {
    for (const k of [].concat(key)) {
      const m = typeof k === "string" ? NOTE.exec(k) : null;
      if (m) seen.delete(m[1] || m[2]);
    }
  };
  wrapped.delete = async (key) => { const out = await bucket.delete(key); forget(key); return out; };
  wrapped.put = async (key, value, opts) => {
    await check(key);
    const out = await bucket.put(key, value, opts);
    forget(key);
    return out;
  };
  if (typeof bucket.createMultipartUpload === "function") {
    wrapped.createMultipartUpload = async (key, ...a) => { await check(key); return bucket.createMultipartUpload(key, ...a); };
  }
  if (typeof bucket.resumeMultipartUpload === "function") wrapped.resumeMultipartUpload = (...a) => bucket.resumeMultipartUpload(...a);
  const out = Object.create(env);
  Object.defineProperty(out, "BUCKET", { value: wrapped });
  return out;
}
