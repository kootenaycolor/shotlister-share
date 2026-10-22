/**
 * **Each small file read once a request, and a page's reads started together.**
 *
 * Measured on the live portal, 2026-10-02 (`timing.js`): a film's page made
 * 24 bucket calls at 60–200 ms each, nearly all one after another, for 1.7 s
 * of waiting and 20 ms of work. The film's list of people was read five
 * times, its manifest three, its logs listed twice, `shorts.json` twice —
 * each helper asking for what it needs, which is the right way to write them
 * and the slow way to run them.
 *
 * So the bucket a request sees remembers, for that request only:
 *
 *  - **a `.json` read** — the bytes, handed to each asker as a fresh object
 *    (`json()`, `text()`, `body` all work, as many times as asked);
 *  - **a list** — by its exact options, each asker getting its own copy of
 *    the arrays.
 *
 * A write or a delete through the same bucket forgets the key and every list
 * that could hold it, before and after it lands, so a read after a write sees
 * the write. Anything with options (a range, a condition) and anything not
 * `.json` — a picture, a log — goes straight through, untouched.
 *
 * **Nothing outlives the request.** Another request, another isolate, another
 * datacentre all read the bucket as before; this cannot serve anybody a stale
 * answer from somebody else's visit.
 *
 * `warm` starts the reads nearly every page of a film makes, all at once, the
 * moment the film is known — so the helpers that ask one after another find
 * their answers already on the way.
 */
import { keys } from "../../relay/layout.js";
import { everyFilm, listAll } from "./films.js";

/** Above this a `.json` is read the ordinary way, not kept. */
const KEEP_UP_TO = 4 * 1024 * 1024;

function view(obj, bytes) {
  const text = () => new TextDecoder().decode(bytes);
  return {
    key: obj.key, version: obj.version, size: obj.size, etag: obj.etag, httpEtag: obj.httpEtag,
    uploaded: obj.uploaded, httpMetadata: obj.httpMetadata, customMetadata: obj.customMetadata,
    checksums: obj.checksums, range: obj.range, storageClass: obj.storageClass,
    writeHttpMetadata: (headers) => obj.writeHttpMetadata(headers),
    get body() { return new Response(bytes).body; },
    bodyUsed: false,
    arrayBuffer: async () => bytes.slice().buffer,
    text: async () => text(),
    json: async () => JSON.parse(text()),
    blob: async () => new Blob([bytes]),
  };
}

function copyList(got) {
  return {
    ...got,
    objects: (got.objects || []).slice(),
    delimitedPrefixes: (got.delimitedPrefixes || []).slice(),
  };
}

const plain = (options) => options === undefined || options === null
  || (typeof options === "object" && Object.keys(options).length === 0);

export function readOnce(bucket) {
  const gets = new Map();      // key → Promise<{obj, bytes} | {raw} | null>
  const lists = new Map();     // JSON of options → Promise<list>

  const forget = (key) => {
    gets.delete(key);
    for (const [named] of lists) {
      const prefix = JSON.parse(named).prefix || "";
      if (String(key).startsWith(prefix)) lists.delete(named);
    }
  };

  const get = (key, options) => {
    if (!plain(options) || typeof key !== "string" || !key.endsWith(".json")) return bucket.get(key, options);
    let held = gets.get(key);
    const mine = !held;
    if (!held) {
      held = bucket.get(key).then(async (obj) => {
        if (!obj) return null;
        if (obj.size > KEEP_UP_TO) return { raw: obj };
        return { obj, bytes: new Uint8Array(await obj.arrayBuffer()) };
      });
      gets.set(key, held);
      held.catch(() => { if (gets.get(key) === held) gets.delete(key); });
    }
    return held.then((got) => {
      if (!got) return null;
      if (got.raw) {
        // Too big to keep: the first asker has it; anyone else reads afresh.
        if (gets.get(key) === held) gets.delete(key);
        return mine ? got.raw : bucket.get(key);
      }
      return view(got.obj, got.bytes);
    });
  };

  const list = (options = {}) => {
    const named = JSON.stringify(options || {});
    let held = lists.get(named);
    if (!held) {
      held = bucket.list(options);
      lists.set(named, held);
      held.catch(() => { if (lists.get(named) === held) lists.delete(named); });
    }
    return held.then(copyList);
  };

  const writing = (name) => async (...args) => {
    const touched = name === "delete" ? [].concat(args[0]) : [args[0]];
    touched.forEach(forget);
    try {
      return await bucket[name](...args);
    } finally {
      touched.forEach(forget);
    }
  };

  return new Proxy(bucket, {
    get(target, name) {
      if (name === "get") return get;
      if (name === "list") return list;
      if (name === "put" || name === "delete") return writing(name);
      const real = target[name];
      return typeof real === "function" ? real.bind(target) : real;
    },
  });
}

/** This request's env, its bucket remembering. Every other binding is the original. */
export function onceEach(env) {
  if (!env.BUCKET) return env;
  const out = Object.create(env);
  Object.defineProperty(out, "BUCKET", { value: readOnce(env.BUCKET) });
  return out;
}

/**
 * **Start a film's usual reads at once.** Not awaited, and a failure here is
 * nobody's: the helper that needs the answer asks again and meets the error
 * itself, where it can say something about it.
 */
export function warm(env, project, also = []) {
  const quiet = (p) => { if (p && p.catch) p.catch(() => {}); };
  for (const key of [
    keys.people(project), keys.down(project), keys.visible(project), keys.manifest(project),
    keys.portal(project), keys.front(project),
    ...also,
  ]) quiet(env.BUCKET.get(key));
  // The two lists nearly every page makes: the film's logs, and the films.
  // Asked through the same helpers so the options — and so the memory — match.
  quiet(listAll(env, keys.logs(project)));
  quiet(everyFilm(env));
}
