/**
 * **Something moving the moment a click is heard, on every page.**
 *
 * His ask, 2026-09-30: *"make loading feel dynamic and responsive, have
 * something for us to look at so we know it's trying to work."* Most of the
 * portal's links are ordinary page loads — a project card, Back to Projects,
 * a deck, a save on a page without `deep.js` — and through every one of them
 * the old page sat perfectly still until the new one arrived. On a phone on a
 * set that is a second or two that reads as a click that missed.
 *
 * So: a thin bar across the top that starts the moment a link or a save is
 * pressed, runs quickly to about a third, creeps after that, and finishes and
 * fades when the page is up. The pressed link dims at once, so the answer to
 * a click is on the thing clicked as well as at the top of the screen.
 *
 * **Only after a blink.** A kept page lands in a few milliseconds, and a bar
 * that flashes for those is noise. It waits `GRACE` before it shows.
 *
 * `deep.js` swaps pages in place, so the browser never says it is loading;
 * it calls `portalWait.start()` / `.done()` itself. Everything else is caught
 * here by watching which clicks nobody else took.
 *
 * Also here, because it is the same job — getting the next page in hand
 * sooner: **speculation rules**, which let Chrome fetch a page while the
 * pointer rests on its link. Safari ignores them and loses nothing.
 */
(() => {
  if (window.portalWait) return;

  const GRACE = 110;       // ms before anything shows
  const GIVE_UP = 20000;   // a page load that never unloads (a download) must not leave it running

  const style = document.createElement("style");
  style.textContent = `
#pw-bar{position:fixed;left:0;top:env(safe-area-inset-top,0px);height:2px;width:100%;z-index:2147483646;
  pointer-events:none;transform-origin:0 50%;transform:scaleX(0);opacity:0;
  background:var(--pw-tint,#7DA4FF);
  transition:transform .3s cubic-bezier(.2,.7,.2,1),opacity .25s ease}
#pw-bar.on{opacity:1}
#pw-bar.end{transition:transform .18s ease-out,opacity .35s ease .15s;opacity:0}
html.pw-busy,html.pw-busy *{cursor:progress}
.pw-going{opacity:.55;transition:opacity .12s ease}
@media (prefers-reduced-motion:reduce){#pw-bar{transition:opacity .2s}}`;
  document.head.appendChild(style);

  let bar = null;
  let showing = null;   // the grace timer
  let creep = null;     // the trickle timer
  let giveUp = null;
  let at = 0;           // 0..1, how far the bar has run
  let busy = 0;         // starts not yet matched by a done
  let leaving = false;  // a real page load is under way; only the new page ends it
  let pressed = null;

  const put = () => {
    if (bar && bar.isConnected) return bar;
    bar = document.createElement("div");
    bar.id = "pw-bar";
    bar.setAttribute("aria-hidden", "true");
    (document.body || document.documentElement).appendChild(bar);
    return bar;
  };
  const draw = () => { if (bar) bar.style.transform = `scaleX(${at})`; };

  /**
   * **The hairline is the film's colour** (move 7 of the portal details): the
   * card or link that was pressed carries its film's `--accent`, and failing
   * that the page in front does. Read once, when the bar appears.
   */
  let tintFrom = null;
  const paint = () => {
    const near = tintFrom && tintFrom.isConnected && tintFrom.closest ? tintFrom.closest("[style*='--accent']") : null;
    const page = document.querySelector(".fh2[style*='--accent']") || document.querySelector(".fh2");
    const from = near || page;
    const colour = from ? getComputedStyle(from).getPropertyValue("--accent").trim() : "";
    if (bar) bar.style.setProperty("--pw-tint", colour || "#7DA4FF");
  };

  function show() {
    showing = null;
    put();
    paint();
    bar.classList.remove("end");
    at = 0;
    draw();
    // One frame at zero, so the first step is seen as movement.
    requestAnimationFrame(() => {
      bar.classList.add("on");
      at = 0.28;
      draw();
    });
    clearInterval(creep);
    // Fast early, slower later, never arriving: each step closes a share of
    // what is left, so a slow page still looks like it is getting somewhere.
    creep = setInterval(() => {
      at += (0.92 - at) * (at < 0.6 ? 0.12 : 0.05);
      draw();
    }, 220);
  }

  function start() {
    busy += 1;
    document.documentElement.classList.add("pw-busy");
    if (bar && bar.classList.contains("on") && !bar.classList.contains("end")) return;
    if (!showing) showing = setTimeout(show, GRACE);
  }

  function finish() {
    busy = 0;
    document.documentElement.classList.remove("pw-busy");
    if (pressed) { pressed.classList.remove("pw-going"); pressed = null; }
    tintFrom = null;
    clearTimeout(showing);
    showing = null;
    clearInterval(creep);
    clearTimeout(giveUp);
    if (!bar || !bar.classList.contains("on")) return;
    at = 1;
    draw();
    bar.classList.add("end");
    setTimeout(() => {
      if (!bar || !bar.classList.contains("end")) return;
      bar.classList.remove("on", "end");
      at = 0;
      draw();
    }, 520);
  }

  function done() {
    if (leaving) return;
    busy = Math.max(0, busy - 1);
    if (!busy) finish();
  }

  /** A real page load: nothing on this page can say it is over. */
  function away(link) {
    leaving = true;
    if (link) { pressed = link; tintFrom = link; link.classList.add("pw-going"); }
    start();
    clearTimeout(giveUp);
    giveUp = setTimeout(() => { leaving = false; finish(); }, GIVE_UP);
  }

  window.portalWait = { start, done, away };

  // **Registered on `window`, so it runs after every listener on `document`.**
  // By then `deep.js` and the rest have had their say: a click they took is
  // `defaultPrevented`, and they drive the bar themselves.
  addEventListener("click", (event) => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest && event.target.closest("a[href]");
    if (!link || link.hasAttribute("download") || (link.target && link.target !== "_self")) return;
    const to = new URL(link.href, location.href);
    if (to.origin !== location.origin) return;
    if (to.searchParams.has("save")) return;          // a file, not a page
    // The same page, or only its #fragment: the browser scrolls, it does not
    // load — and a script-driven `href="#"` must not start a bar nothing ends.
    if (to.pathname === location.pathname && to.search === location.search) return;
    away(link);
  });

  addEventListener("submit", (event) => {
    if (event.defaultPrevented) return;
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || (form.target && form.target !== "_self")) return;
    away(null);
  });

  // Back into a page kept whole by the browser: whatever was running is over.
  addEventListener("pageshow", () => { leaving = false; finish(); });

  // ---- the next page, fetched on the way to the click (Chrome) ------------
  //
  // `moderate` is "the pointer has rested on it", about a fifth of a second —
  // the same moment `deep.js` warms its own pages. **Prefetch, not prerender**:
  // a prerender runs the page's scripts, and the app's door starts an engine.
  // Links `deep.js` swaps itself, downloads, and anything aimed elsewhere are
  // left out.
  if (HTMLScriptElement.supports && HTMLScriptElement.supports("speculationrules")) {
    const rules = document.createElement("script");
    rules.type = "speculationrules";
    rules.textContent = JSON.stringify({
      prefetch: [{
        source: "document",
        eagerness: "moderate",
        where: {
          and: [
            { href_matches: "/*" },
            { not: { selector_matches: "[data-deep], [download], [target], [data-share]" } },
            { not: { href_matches: "/*\\?*save=*" } },
            { not: { href_matches: "/*/api/*" } },
          ],
        },
      }],
    });
    document.head.appendChild(rules);
  }
})();
