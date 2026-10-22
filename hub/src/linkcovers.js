/**
 * **The link covers, drawn beside the worker** (2026-10-11, Projects Console
 * without the Mac, stage 3 step 2) — `put_cover` in `hub/refresh.py`, which
 * drew them on the Mac with `cover.mjs` because "a Worker cannot draw". It
 * still cannot; Cloudflare's browser (the `BROWSER` binding, the one the
 * press prints with) can, and it is handed the very page `cover.mjs` hands
 * the Mac's Chrome (`coverhtml.js`, one copy of the card for both).
 *
 * **The typeface is the portal's own, inlined.** The two Rethink Sans files
 * are read out of the worker's static files (`env.ASSETS`) and written into
 * the page as data, as `cover.mjs` does off disk, so the browser never has to
 * fetch anything and a card can never come out in a fallback face. If the
 * files cannot be read, nothing is drawn and the run says so.
 *
 * **Only what changed is drawn**, as on the Mac: each cover's inputs have a
 * fingerprint (`fingerprint`, byte for byte Python's) kept in
 * `media/covers.json`, so a card whose words have not moved launches no
 * browser at all — which matters more here, where the browser is metered.
 * The fingerprints are the Mac's own, so the first run after the switch
 * redraws nothing the Mac already drew.
 */
import puppeteer from "@cloudflare/puppeteer";
import { keys } from "../../relay/layout.js";
import { coverPage, coverIcon, fontFaces } from "./coverhtml.js";
import { coversWanted, fingerprint, ICON } from "./refreshrules.js";

const FONT_FILES = ["rethink-600.woff2", "rethink-500.woff2"];
const LIMIT_MS = 30_000;

/** Where a cover is kept: the film's (`""`), a page's, or the icon. */
export function coverKey(project, slug) {
  if (slug === ICON) return keys.icon(project);
  return slug ? keys.coverFor(project, slug) : keys.cover(project);
}

const coversJsonKey = (project) => keys.medium(project, "covers.json");

function base64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

/** The `@font-face` rules with both files inlined, or a thrown reason. */
export async function inlineFonts(env) {
  if (!env.ASSETS || typeof env.ASSETS.fetch !== "function") throw new Error("the portal's own files are not reachable, so its typeface is not");
  const at = [];
  for (const name of FONT_FILES) {
    const got = await env.ASSETS.fetch(new Request(`https://assets.invalid/${name}`));
    const bytes = got.ok ? new Uint8Array(await got.arrayBuffer()) : new Uint8Array();
    if (bytes.length < 1000) throw new Error(`the portal's typeface (${name}) could not be read`);
    at.push(`data:font/woff2;base64,${base64(bytes)}`);
  }
  return fontFaces(at[0], at[1]);
}

/** `work`, or a plain error once `ms` have gone by: a browser that stops
 * answering is a cover that did not draw, never a tick that never ends. */
function inTime(work, ms, what) {
  let timer;
  return Promise.race([
    work.finally(() => clearTimeout(timer)),
    new Promise((_, no) => { timer = setTimeout(() => no(new Error(`the browser did not answer in ${ms / 1000} s (${what})`)), ms); }),
  ]);
}

/**
 * One browser for one card's covers: launched on the first cover that needs
 * drawing, closed by `close()`. A card with nothing to draw never launches it.
 */
export function drawer(env) {
  let browser = null;
  let fonts = null;
  return {
    launched: () => Boolean(browser),
    async draw(job) {
      if (!env.BROWSER) throw new Error("the portal has no browser to draw with (BROWSER binding)");
      if (!fonts) fonts = await inlineFonts(env);
      if (!browser) browser = await inTime(puppeteer.launch(env.BROWSER, { keep_alive: 60_000 }), LIMIT_MS, "starting");
      const page = await inTime(browser.newPage(), LIMIT_MS, "a new page");
      try {
        page.setDefaultTimeout(LIMIT_MS);
        const side = job.icon ? 512 : 0;
        const width = side || 1200;
        const height = side || 630;
        await inTime(page.setViewport({ width, height, deviceScaleFactor: 1 }), LIMIT_MS, "sizing");
        await inTime(page.setContent(job.icon ? coverIcon(job, fonts) : coverPage(job, fonts), { waitUntil: "load", timeout: LIMIT_MS }), LIMIT_MS, "the page");
        // **The face, loaded and in use, before the picture is taken** —
        // `cover.mjs` waited 900 ms for the same; here it is asked.
        // Both weights asked for by name, so a card with no words at all (an
        // icon that is only a mark) still proves the face is there.
        const ready = await inTime(page.evaluate(async () => {
          await Promise.all([document.fonts.load("600 40px R"), document.fonts.load("500 20px R")]);
          await document.fonts.ready;
          return document.fonts.check("600 40px R") && document.fonts.check("500 20px R");
        }), LIMIT_MS, "the typeface");
        if (!ready) throw new Error("the portal's typeface did not load in the browser");
        const shot = await inTime(page.screenshot({ type: "png", clip: { x: 0, y: 0, width, height } }), LIMIT_MS, "the picture");
        return shot instanceof Uint8Array ? shot : new Uint8Array(shot);
      } finally {
        await inTime(page.close(), 5_000, "closing a page").catch(() => {});
      }
    },
    async close() {
      if (browser) await inTime(browser.close(), 10_000, "closing").catch(() => {});
      browser = null;
    },
  };
}

/** What was drawn last time — `covers_drawn`: the fingerprints, or `{}`. */
export async function coversDrawn(env, project) {
  const got = await env.BUCKET.get(coversJsonKey(project));
  if (!got) return {};
  try {
    const drawn = JSON.parse(await got.text());
    return drawn && typeof drawn === "object" && !Array.isArray(drawn) ? drawn : {};
  } catch {
    return {};
  }
}

/**
 * The pictures a pasted link unfurls into — `put_cover`. Answers
 * `{todo, drawn}`: the covers that needed drawing (by slug, `""` the film's)
 * and how many were drawn and kept. `dry` works out `todo` and draws nothing.
 * Throws, after keeping what did draw, when any would not — as the Python
 * raised after writing `covers.json`.
 */
export async function putCovers(env, project, title, card, { draw = null, dry = false, redraw = false } = {}) {
  const wanted = coversWanted(title, card);
  const prints = new Map();
  for (const [slug, spec] of wanted) prints.set(slug, await fingerprint(spec));
  let drawn = redraw ? {} : await coversDrawn(env, project);
  const todo = [...wanted.keys()].filter((slug) => drawn[slug] !== prints.get(slug));
  if (!todo.length || dry) return { todo, drawn: 0 };
  let trouble = null;
  let made = 0;
  for (const slug of todo) {
    let png;
    try {
      png = await draw.draw(wanted.get(slug));
    } catch (problem) {
      // The whole browser refusing is the Mac's "the cover would not draw":
      // nothing is kept, not even the fingerprints.
      if (!draw.launched()) throw problem;
      trouble = trouble || new Error(`the cover for “${slug || "the film"}” would not draw: ${problem.message}`);
      continue;
    }
    try {
      await env.BUCKET.put(coverKey(project, slug), png, { httpMetadata: { contentType: "image/png" } });
    } catch (problem) {
      trouble = trouble || problem;
      continue;
    }
    drawn[slug] = prints.get(slug);
    made += 1;
  }
  // A page taken off the rail keeps its old picture, unlisted and harmless;
  // forgetting its fingerprint means it is drawn afresh if it ever comes back.
  drawn = Object.fromEntries(Object.entries(drawn).filter(([slug]) => prints.has(slug)));
  await env.BUCKET.put(coversJsonKey(project), JSON.stringify(drawn), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  if (trouble) throw trouble;
  return { todo, drawn: made };
}
