/**
 * A film, replayed in the worker — and the film half of its card.
 *
 * **Its own file so `front.js` can ask for the card without a cycle.**
 * `mcp.js` imports `front.js` for the card's words; the card's film half needs
 * the engine, which lived in `mcp.js`. The replay and the four pointer helpers
 * moved here, and both import this.
 *
 * `cardOf` is the reason this file exists. His row, 2026-09-16, off the
 * systems map: counts, credits and aspect ratio come from the film, which the
 * hub already replays on every request — only the words need Notion. So the
 * page is never behind the film, and Update the Portal is for the words.
 */
import mcpWasm from "./mcp.wasm";
import { keys } from "../../relay/layout.js";
import { listAll, sha256Hex } from "./films.js";

const SPLIT = "\u0000";

/** A worker reading, never writing: one fixed device, and the engine told read-only. */
const READER = "0000000000000001";

/** Which fields a card carries. Bump it when `film_card` in `mcpweb` grows one. */
const CARD_SHAPE = 5;

/**
 * The film half of a film's card, asked of the film itself.
 *
 * **Never throws.** `null` when the film has no logs in the bucket or the
 * engine will not start, and the caller draws the stored card as before.
 *
 * Held in Cloudflare's cache under the logs' own names and sizes, the same
 * key `logsOf` uses, so it is computed once per change and read for free
 * until the next one. **The key changing is the invalidation.**
 */
export async function cardOf(env, project, ctx) {
  let objects;
  try {
    objects = await logObjects(env, project);
  } catch {
    return null;
  }
  if (!objects.length) return null;

  const stamp = await stampOf(objects);
  // **`CARD_SHAPE` is in the key** so a card that grows a field is computed
  // afresh rather than read back without it for a day — `scripts` (SL-1338)
  // would otherwise have waited for each film's next change.
  const key = new Request(`https://cards.invalid/${CARD_SHAPE}/${project}/${stamp}`);
  const cache = caches.default;
  const held = await cache.match(key);
  if (held) {
    try {
      return await held.json();
    } catch {
      // fall through and compute it again
    }
  }

  let card = null;
  try {
    const film = await WebAssembly.instantiate(mcpWasm, {});
    const x = film.exports;
    x.set_now(Date.now());
    x.set_seed(1);
    begin(x, project, "", true, READER);
    await feed(env, project, ctx, x, objects);
    const said = take(x, x.card());
    card = said ? JSON.parse(said) : null;
  } catch (error) {
    console.error("could not ask the film for its card:", String(error));
    return null;
  }
  if (!card) return null;

  const kept = cache.put(
    key,
    new Response(JSON.stringify(card), {
      headers: { "cache-control": "max-age=86400", "content-type": "application/json" },
    })
  );
  if (ctx && ctx.waitUntil) ctx.waitUntil(kept);
  else await kept;
  return card;
}

/**
 * Hand a started engine the film.
 *
 * **From its saved state, when there is one; from every log, when there is
 * not.** His row, 2026-09-16: a saved snapshot per film so the hub does not
 * replay every change on every request. After a replay the engine's state —
 * the records, and how far it has heard from each device (`engine::snapshot`)
 * — is kept here under the logs' own names and sizes, the key `logsOf` uses.
 * The next request finds it and:
 *
 * - **the same logs, the same sizes** — restores it and adds nothing;
 * - **the logs grew** — restores it and adds only what is new: a log the
 *   snapshot never saw, whole; a log that grew, from where it was. **Proven
 *   against the text, not the size**: the logs the snapshot was made from are
 *   still in the cache under its stamp, and each must still be the beginning
 *   of the log it is now. A log that was rewritten (a fold says `?rewrite=1`
 *   to the relay) or retired fails that, and the film is replayed;
 * - **anything else** — no snapshot, the old texts gone from the cache, the
 *   engine refusing the text — replays every log, as it always did.
 *
 * Whatever road it took, the engine ends settled and having heard everything
 * in the bucket, so a change it writes sorts after all of it. A snapshot is
 * saved on every road but the first; the cache is the only place it lives,
 * and it is never a file in the bucket. Answers the road taken —
 * `restored`, `restored+tail` or `replayed` — a word for a header and a
 * check; nothing decides on it.
 */
export async function feed(env, project, ctx, x, listed = null) {
  const objects = listed || (await logObjects(env, project));
  const stamp = await stampOf(objects);
  const logs = await logsOf(env, project, ctx, objects);
  const names = objects.map((o) => o.key.split("/").pop());
  const cache = caches.default;
  const key = new Request(`https://snapshots.invalid/${project}`);

  let road = "replayed";
  const held = await heldSnapshot(cache, key);
  if (held && held.stamp === stamp) {
    if (restore(x, held.state)) road = "restored";
  } else if (held) {
    const tails = await grownSince(cache, project, held, names, logs);
    if (tails && restore(x, held.state)) {
      for (const tail of tails) add(x, tail);
      road = "restored+tail";
    }
  }
  if (road === "replayed") {
    for (const log of logs) add(x, log);
  }
  x.settle();

  if (road !== "restored" && objects.length) {
    const state = take(x, x.snapshot());
    if (state) {
      const kept = cache.put(
        key,
        new Response(JSON.stringify({ stamp, names, state }), {
          headers: { "cache-control": "max-age=86400", "content-type": "application/json" },
        })
      );
      if (ctx && ctx.waitUntil) ctx.waitUntil(kept);
      else await kept;
    }
  }
  return road;
}

async function heldSnapshot(cache, key) {
  const got = await cache.match(key);
  if (!got) return null;
  try {
    const held = await got.json();
    if (typeof held.stamp !== "string" || !Array.isArray(held.names) || typeof held.state !== "string") {
      return null;
    }
    return held;
  } catch {
    return null;
  }
}

/**
 * What to add on top of a snapshot made of older logs, or `null` if the film
 * cannot be shown to have only grown.
 *
 * Each log the snapshot covered must still exist, and what it was then must
 * still be exactly how it begins now — the relay's own rule, checked here
 * against the cached texts rather than trusted. A log the snapshot never saw
 * is added whole; one that grew is added from where it was, under its own
 * header so the engine reads it as a log.
 */
async function grownSince(cache, project, held, names, logs) {
  const before = await cache.match(new Request(`https://films.invalid/${project}/${held.stamp}`));
  if (!before) return null;
  const was = new Map();
  const texts = (await before.text()).split(SPLIT);
  if (texts.length !== held.names.length) return null;
  held.names.forEach((name, at) => was.set(name, texts[at]));

  const tails = [];
  for (let at = 0; at < names.length; at += 1) {
    const then = was.get(names[at]);
    const now = logs[at];
    if (then === undefined) {
      tails.push(now);
      continue;
    }
    was.delete(names[at]);
    if (!now.startsWith(then)) return null;
    if (now.length === then.length) continue;
    // A log ends at a line's end, always. One that does not is not a log the
    // engine read whole, and the film is replayed rather than guessed at.
    if (then && !then.endsWith("\n")) return null;
    const header = then.slice(0, then.indexOf("\n") + 1);
    tails.push(header + now.slice(then.length));
  }
  // A covered log that is no longer there was retired by a fold.
  if (was.size) return null;
  return tails;
}

function add(x, log) {
  if (!log) return;
  const [ptr, len] = put(x, log);
  x.add_log(ptr, len);
  x.dealloc(ptr, len);
}

function restore(x, state) {
  const [ptr, len] = put(x, state);
  const said = x.restore(ptr, len);
  x.dealloc(ptr, len);
  return said === 0;
}

/**
 * A film's logs and the stamp they make together — what a cache of anything
 * computed from the film is keyed on, so a change to the film is a new key.
 */
export async function filmStamp(env, project) {
  const objects = await logObjects(env, project);
  return { objects, stamp: objects.length ? await stampOf(objects) : "" };
}

/** A film's change logs as bucket objects, in name order. */
export async function logObjects(env, project) {
  return (await listAll(env, keys.logs(project)))
    .filter((o) => o.key.endsWith(".log"))
    .sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
}

async function stampOf(objects) {
  return sha256Hex(objects.map((o) => `${o.key}:${o.size}`).join("\n"));
}

/**
 * Every change log of a film, in name order.
 *
 * Held in Cloudflare's cache under a key made of the logs' own names and sizes,
 * so they are fetched once per change rather than once per question. **The key
 * changing is the invalidation** — there is nothing to remember to clear, and
 * no way for a stale film to be served.
 */
export async function logsOf(env, project, ctx, listed = null) {
  const objects = listed || (await logObjects(env, project));
  if (!objects.length) return [];

  const stamp = await stampOf(objects);
  const key = new Request(`https://films.invalid/${project}/${stamp}`);
  const cache = caches.default;

  const held = await cache.match(key);
  if (held) return (await held.text()).split(SPLIT);

  // **Only what changed is read** (2026-10-02). A film that gained one change
  // used to be read whole again — 263 logs, four at a time, fourteen seconds
  // of a page opened while he was working on the Mac. The texts read last
  // time are still in the cache with each one's etag beside it; a log whose
  // etag is the same is the same bytes, so it is taken from there, and only
  // the logs that are new or grew are fetched. No etag, no reuse: a log the
  // last read cannot vouch for is read afresh.
  let before = await lastRead(cache, project);
  // **And when this city's cache has none of it, the bucket's copy**
  // (2026-10-13). Cloudflare's cache is kept per datacentre, and the portal's
  // visitors are sent to Paris, Dublin, Madrid, Tokyo, Berlin by turns — each
  // a cache that has never seen the film. Measured: a share link took 20 to
  // 43 seconds whenever it landed in one, reading LSC's 466 logs four at a
  // time. One copy of every log's text, by etag, kept in the bucket where
  // every datacentre can read it, makes that one read.
  const covers = (map) => map && objects.every((o) => o.etag && map.has(o.etag));
  const short = !covers(before);
  let copy = null;
  if (short) {
    copy = await bucketCopy(env, project);
    if (copy) before = before ? new Map([...copy, ...before]) : copy;
  }
  const texts = new Array(objects.length);
  const wanted = [];
  objects.forEach((o, at) => {
    const was = before && o.etag ? before.get(o.etag) : undefined;
    if (was === undefined) wanted.push(at);
    else texts[at] = was;
  });
  // **A few at a time, and each one read before the next is opened.**
  //
  // Cloudflare allows only about six open responses at once, and an R2 object
  // is an open response until its body has been read. Asking for twenty and
  // *then* reading them held twenty open, and the platform closed them:
  // `Response closed due to connection limit`. It cost the first morning this
  // was live — every film failed to open, however small, and nothing local
  // could have caught it because `wrangler dev` does not enforce the limit.
  //
  // Four, so there is room for whatever else the request is doing — four
  // readers each taking the next log as soon as its last is read, so one slow
  // read holds up one reader, not a batch.
  //
  // **And the bucket's copy kept as it goes** when it fell short (2026-10-13):
  // a film read whole from a far datacentre took longer than a visitor waits,
  // and a request given up on is stopped where it stands — before the copy
  // at the end was ever written, so the next visitor started again from
  // nothing. Every so many logs the copy is rewritten with what is known so
  // far; a log in it is still only ever taken by its etag.
  let next = 0, since = 0;
  const reader = async () => {
    while (next < wanted.length) {
      const at = wanted[next++];
      const one = await env.BUCKET.get(objects[at].key);
      texts[at] = one ? await one.text() : "";
      if (short && ++since >= KEEP_EVERY) {
        since = 0;
        await keepCopy(env, project, objects, texts);
      }
    }
  };
  await Promise.all([reader(), reader(), reader(), reader()]);

  const json = { "cache-control": "max-age=86400", "content-type": "application/json" };
  const kept = Promise.all([
    cache.put(
      key,
      new Response(texts.join(SPLIT), {
        headers: { "cache-control": "max-age=86400", "content-type": "text/plain; charset=utf-8" },
      })
    ),
    cache.put(etagsKey(project, stamp), new Response(JSON.stringify(objects.map((o) => o.etag || "")), { headers: json })),
    cache.put(latestKey(project), new Response(JSON.stringify({ stamp }), { headers: json })),
    // Rewritten only when it was read and fell short — once per change to
    // the film, by whichever request meets the change first.
    short && !covers(copy) ? keepCopy(env, project, objects, texts) : null,
  ]);
  if (ctx && ctx.waitUntil) ctx.waitUntil(kept);
  else await kept;

  return texts;
}

/**
 * **The bucket's copy of a film's logs** — one object per film, every log's
 * text beside its etag, so a datacentre whose cache has never seen the film
 * reads one thing rather than every log (`logsOf`). A first line of etags as
 * JSON, then the texts, joined as the cache joins them.
 *
 * It is only ever a shortcut: a log is taken from it when its etag — the
 * bucket's own fingerprint of its bytes — is one the copy holds, so a stale
 * or half-written copy costs reads, never a wrong film. Outside `p/` so no
 * listing of films or logs ever meets it, and nothing reads it but this.
 */
const copyKey = (project) => `hub/logs/${project}.txt`;

/** How many logs fetched between keeping the copy, on a long read. */
const KEEP_EVERY = 60;

async function bucketCopy(env, project) {
  try {
    const got = await env.BUCKET.get(copyKey(project));
    if (!got) return null;
    const text = await got.text();
    const cut = text.indexOf("\n");
    if (cut < 0) return null;
    const tags = JSON.parse(text.slice(0, cut));
    const split = text.slice(cut + 1).split(SPLIT);
    if (!Array.isArray(tags) || tags.length !== split.length) return null;
    const out = new Map();
    tags.forEach((tag, at) => { if (tag) out.set(tag, split[at]); });
    return out;
  } catch {
    return null;
  }
}

/**
 * The logs read so far, as the copy. A log not yet read is left out, so a copy
 * kept halfway is a smaller copy, never a wrong one. Never throws: a copy that
 * could not be kept is the next request's to make.
 */
async function keepCopy(env, project, objects, texts) {
  try {
    const known = objects.map((o, at) => at).filter((at) => objects[at].etag && texts[at] !== undefined);
    const tags = JSON.stringify(known.map((at) => objects[at].etag));
    await env.BUCKET.put(copyKey(project), `${tags}\n${known.map((at) => texts[at]).join(SPLIT)}`, {
      httpMetadata: { contentType: "text/plain; charset=utf-8" },
    });
  } catch (error) {
    console.error("could not keep the film's logs in the bucket:", String(error));
  }
}

const etagsKey = (project, stamp) => new Request(`https://films.invalid/${project}/${stamp}/etags`);
const latestKey = (project) => new Request(`https://films.invalid/${project}/latest`);

/**
 * The texts of the last full read of this film, by etag — or `null` when the
 * cache no longer holds all three pieces of it.
 */
async function lastRead(cache, project) {
  try {
    const latest = await cache.match(latestKey(project));
    if (!latest) return null;
    const { stamp } = await latest.json();
    if (typeof stamp !== "string") return null;
    const [texts, etags] = await Promise.all([
      cache.match(new Request(`https://films.invalid/${project}/${stamp}`)),
      cache.match(etagsKey(project, stamp)),
    ]);
    if (!texts || !etags) return null;
    const split = (await texts.text()).split(SPLIT);
    const tags = await etags.json();
    if (!Array.isArray(tags) || tags.length !== split.length) return null;
    const out = new Map();
    tags.forEach((tag, at) => { if (tag) out.set(tag, split[at]); });
    return out;
  } catch {
    return null;
  }
}

// ------------------------------------------- the pointers, and nothing else

export function put(x, text) {
  const bytes = new TextEncoder().encode(text);
  const ptr = x.alloc(bytes.length);
  new Uint8Array(x.memory.buffer, ptr, bytes.length).set(bytes);
  return [ptr, bytes.length];
}

export function take(x, ptr) {
  // **Read the memory fresh every time.** An `alloc` can grow the WebAssembly
  // memory, and growing it detaches every view taken before it.
  const length = new DataView(x.memory.buffer).getUint32(ptr, true);
  const text = new TextDecoder().decode(new Uint8Array(x.memory.buffer, ptr + 4, length));
  x.free_result(ptr);
  return text;
}

export function begin(x, project, title, readOnly, device) {
  const [ip, il] = put(x, project);
  const [tp, tl] = put(x, title);
  const [dp, dl] = put(x, device);
  const said = x.start(ip, il, tp, tl, readOnly ? 1 : 0, dp, dl);
  x.dealloc(ip, il);
  x.dealloc(tp, tl);
  x.dealloc(dp, dl);
  if (said !== 0) throw new Error("The engine would not start.");
}

