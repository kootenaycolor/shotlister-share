/**
 * **The shell of the app, kept so the film opens with no signal.**
 *
 * `film.js` already keeps the film itself — the change logs, which is where the
 * time goes. This is the other half: the page, its script, its stylesheets and
 * the engine. Without them a phone with no bars gets a browser error, and the
 * copy of the film sitting in that same browser is unreachable. He reads
 * locations standing in them, which is exactly where there is no signal.
 *
 * ## Network first, always
 *
 * **Nothing here is served from the cache while a network answers.** A worker
 * that prefers its own copy is how a site gets stuck on a version nobody can
 * shift, and this one is his own portal — being stuck would be worse than
 * being slow. So: ask the network, and only if that fails at all reach for
 * what was kept. Online behaviour is byte for byte what it was before this
 * file existed.
 *
 * ## Kept by path, never by address
 *
 * Every asset is asked for as `/film.js?v=<build>`, and the stamp changes with
 * every deploy. Keying on the whole address would leave one dead copy per
 * deploy for ever, so the key is the path alone and the newest good answer
 * simply replaces the last one.
 *
 * ## What is not here
 *
 * The film's change logs (`/api/…`) — `film.js` keeps those itself, keyed by
 * name and size, which is a thing only it knows. And the photographs, which
 * the relay already serves as immutable and the browser already keeps.
 */
const SHELL = "shell";

/** The handful of files a film's page is made of. */
const WANTED = /^\/(film|copy|share|made|feel)\.js$|^\/(hub|front|feel)\.css$|^\/shotlister_web\.wasm$|^\/mark(-light)?\.png$/;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const navigating = request.mode === "navigate";
  if (!navigating && !WANTED.test(url.pathname)) return;

  event.respondWith((async () => {
    try {
      const got = await fetch(request);
      // **Only a good answer is kept.** A 404 or a sign-in redirect cached as
      // the film's page would be a page he could never get back.
      if (got && got.ok && got.type === "basic") {
        const keep = got.clone();
        // Not awaited: a browser out of room must not hold up the page.
        caches.open(SHELL).then((c) => c.put(url.pathname, keep)).catch(() => {});
      }
      return got;
    } catch (offline) {
      const held = await caches.match(url.pathname);
      if (held) return held;
      throw offline;
    }
  })());
});
