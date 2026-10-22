/**
 * **Where a request's time goes.** His ask, 2026-10-02: *"I want things to
 * feel 'instant'."* Measured that day on the live portal: a film's page took
 * 1.7 seconds of wall time and 20 milliseconds of work — the rest was waiting
 * on storage. This is the stopwatch that says on what.
 *
 * Every bucket read, list and write, every outside `fetch`, every cache look
 * and every call to the relay's rooms is timed against the request that made
 * it (`AsyncLocalStorage`, so two requests in one isolate never share a
 * clock). The answer carries a `Server-Timing` header — storage, network and
 * cache, each a total and a count — which a browser's own network panel
 * draws. Sent `x-hub-trace: 1`, the request also writes every step, with when
 * it started, to the worker's log, which `wrangler tail` shows.
 *
 * It only ever watches: nothing here changes what a request does.
 */
import { AsyncLocalStorage } from "node:async_hooks";

const clock = new AsyncLocalStorage();

/** The trace this request is writing, or none. */
function now() {
  return clock.getStore() || null;
}

async function timed(kind, what, run) {
  const t = now();
  if (!t) return run();
  const start = Date.now();
  try {
    return await run();
  } finally {
    t.steps.push({ kind, what, at: start - t.start, ms: Date.now() - start });
  }
}

/** The bucket, with every call timed. Anything it does not know passes through. */
function bucketTimed(bucket) {
  return new Proxy(bucket, {
    get(target, name) {
      const real = target[name];
      if (typeof real !== "function") return real;
      if (!["get", "head", "list", "put", "delete"].includes(name)) return real.bind(target);
      return (...args) => {
        const key = typeof args[0] === "string" ? args[0]
          : args[0] && typeof args[0] === "object" && "prefix" in args[0] ? `prefix:${args[0].prefix}` : "";
        return timed("store", `${name} ${key}`, () => real.apply(target, args));
      };
    },
  });
}

/** A Durable Object namespace whose stubs' calls are timed. */
function roomsTimed(ns) {
  return new Proxy(ns, {
    get(target, name) {
      const real = target[name];
      if (typeof real !== "function") return real;
      if (name !== "get") return real.bind(target);
      return (...args) => {
        const stub = real.apply(target, args);
        return new Proxy(stub, {
          get(s, n) {
            const f = s[n];
            if (typeof f !== "function") return f;
            if (n !== "fetch") return f.bind(s);
            return (req, init) => timed("room", `fetch ${typeof req === "string" ? req : req.url}`, () => f.call(s, req, init));
          },
        });
      };
    },
  });
}

let patched = false;

/** Outside fetches and the default cache, timed for whichever request is running. */
function patchGlobals() {
  if (patched) return;
  patched = true;
  const realFetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    const url = typeof input === "string" ? input : input && input.url ? input.url : String(input);
    return timed("net", `fetch ${url.replace(/\?.*$/, "")}`, () => realFetch(input, init));
  };
  if (globalThis.caches && caches.default) {
    const cache = caches.default;
    for (const name of ["match", "put", "delete"]) {
      const real = cache[name].bind(cache);
      cache[name] = (req, ...rest) => {
        const url = typeof req === "string" ? req : req && req.url ? req.url : "";
        return timed("cache", `${name} ${url.replace(/^https?:\/\/[^/]+/, "")}`, () => real(req, ...rest));
      };
    }
  }
}

/**
 * Run `handle(env)` with a stopwatch on, and say what it found.
 *
 * The env handed in is the same env with its bucket and rooms watched; every
 * other binding is the original.
 */
export async function withTiming(request, env, handle) {
  patchGlobals();
  const t = { start: Date.now(), steps: [] };
  const watched = Object.create(env);
  if (env.BUCKET) Object.defineProperty(watched, "BUCKET", { value: bucketTimed(env.BUCKET) });
  if (env.ROOMS) Object.defineProperty(watched, "ROOMS", { value: roomsTimed(env.ROOMS) });
  const response = await clock.run(t, () => handle(watched));
  const total = Date.now() - t.start;
  const sum = (kind) => t.steps.filter((s) => s.kind === kind);
  const part = (kind) => {
    const list = sum(kind);
    if (!list.length) return "";
    // **Busy, not added up.** Two reads at once take the time of one; the
    // header says how long that kind of thing kept the request waiting.
    const spans = list.map((s) => [s.at, s.at + s.ms]).sort((a, b) => a[0] - b[0]);
    let busy = 0, end = -1;
    for (const [a, b] of spans) { if (b > end) { busy += b - Math.max(a, end); end = b; } }
    return `${kind};dur=${busy};desc="${list.length}"`;
  };
  const header = [part("store"), part("room"), part("net"), part("cache"), `total;dur=${total}`].filter(Boolean).join(", ");
  if (request.headers.get("x-hub-trace") === "1") {
    console.log(JSON.stringify({
      trace: new URL(request.url).pathname, total,
      steps: t.steps.sort((a, b) => a.at - b.at).map((s) => `${String(s.at).padStart(5)}ms +${String(s.ms).padStart(4)}ms ${s.kind} ${s.what}`),
    }));
  }
  // A websocket's answer is handed over as it is: copying it would drop the socket.
  if (!response || response.webSocket || response.status === 101) return response;
  const out = new Response(response.body, response);
  out.headers.set("server-timing", header);
  return out;
}
