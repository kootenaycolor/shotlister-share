#!/usr/bin/env node
/**
 * The picture a pasted link unfurls into.
 *
 * **Why a browser and not a library.** The card has to be a raster — iMessage,
 * Slack and Mail will not render an SVG `og:image`, which is the one place this
 * is ever seen — and a Cloudflare Worker cannot rasterise anything: there is no
 * canvas in one, and the alternative was shipping a megabyte of type-setting
 * WebAssembly to draw six words. So it is drawn once, here, in the same engine
 * that draws the portal, using the portal's own typeface — and the result is a
 * file in the bucket beside the film's other pictures.
 *
 * **It is the film's identity, not a decoration**: the mark and the colour that
 * already come off its Notion row, so nothing new has to be made or kept up to
 * date. A film with no mark still gets a card — its title on the ground colour,
 * which is better than the bare address it replaces.
 *
 * **A page of the film gets a card of its own.** His ask, 2026-09-10: one
 * picture for every link to a film told the person nothing about *which* page
 * they had been sent. A page's card carries the page's name where the film's
 * carries the film's, and the film's name where the film's carries its logline
 * — same mark, same colour, so it still reads as the film's at a glance.
 *
 *   node hub/cover.mjs <out.png> '<json>'         one card
 *   node hub/cover.mjs '<json array>'             many cards, one browser
 *
 * where each json is { out, title, page, path, colour, logline } — `out` only
 * in the array form, `page` only on a page's card.
 *
 * **An icon is the same job at a different size.** `{ icon: true }` on a job
 * draws a 512-square instead: the film's mark on the night ground, lit by its
 * colour — the picture Safari puts in its tab and the iPhone on its home
 * screen, neither of which will draw an SVG. `{ icon: "product" }` draws the
 * product's own mark on the app icon's gradient, for pages that are nobody's
 * film. His ask, 2026-09-20.
 */
import { spawn } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { writeFileSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import WS from "./node_modules/ws/index.js";
import { coverPage, coverIcon, fontFaces } from "./src/coverhtml.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL = `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234`
            + `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;

/* **Two ways in, one list out.** Every cover a refresh wants is drawn in one
   browser — launching Chrome costs more than drawing the card, and a film with
   eight pages would otherwise launch it eight times, every fifteen minutes. */
let jobs;
if (process.argv[2] && process.argv[2].endsWith(".png")) {
  jobs = [{ out: process.argv[2], ...JSON.parse(process.argv[3] || "{}") }];
} else {
  try { jobs = JSON.parse(process.argv[2] || ""); } catch { jobs = null; }
  if (!Array.isArray(jobs) || !jobs.length || !jobs.every((j) => j && j.out)) {
    console.error("usage: cover.mjs <out.png> '<json>'  |  cover.mjs '<json array>'");
    process.exit(2);
  }
}

/* **The drawing itself is `src/coverhtml.js`** (2026-10-11), shared with the
   portal, which draws the same cards in Cloudflare's browser
   (`src/linkcovers.js`) — one copy of the card, two places that photograph it.
   The typeface the portal itself uses, read off disk so the card cannot come
   out in a fallback the rest of the product never shows. */
const font = (f) => `data:font/woff2;base64,${readFileSync(join(HERE, "public", f)).toString("base64")}`;
const FONTS = fontFaces(font("rethink-600.woff2"), font("rethink-500.woff2"));
const pageOf = (film) => coverPage(film, FONTS);

/* The Mac app's own mark, read off the icon's source so the two cannot drift. */
const PRODUCT_MARK = join(HERE, "..", "release", "icon", "Shotlister.icon", "Assets", "mark.svg");

function iconOf(film) {
  if (film.icon === "product") {
    /* The app icon's own two colours, as `release/icon/Shotlister.icon/icon.json`
       names them — navy into charcoal, top to bottom. */
    return `<!doctype html><meta charset="utf-8"><style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:512px;height:512px}
body{background:linear-gradient(180deg,#0E1F61,#282828);display:flex;align-items:center;justify-content:center}
svg{width:352px;height:352px;display:block}
</style>${readFileSync(PRODUCT_MARK, "utf8")}`;
  }
  return coverIcon(film, FONTS);
}

const PORT = 9371 + Math.floor(Math.random() * 40);
const chrome = spawn(SHELL, [`--remote-debugging-port=${PORT}`, "--headless=new",
  "--hide-scrollbars", "--no-first-run", `--user-data-dir=/tmp/cover-${PORT}`, "about:blank"],
  { stdio: "ignore" });

let target;
for (let i = 0; i < 40; i++) {
  try { const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
        target = l.find((t) => t.type === "page"); if (target) break; } catch {}
  await wait(250);
}
const ws = new WS(target.webSocketDebuggerUrl);
await new Promise((r) => ws.on("open", r));
let id = 0; const waiting = new Map();
ws.on("message", (m) => { const x = JSON.parse(m); if (x.id && waiting.has(x.id)) { waiting.get(x.id)(x); waiting.delete(x.id); } });
const send = (m, p = {}) => new Promise((res) => { const n = ++id; waiting.set(n, res); ws.send(JSON.stringify({ id: n, method: m, params: p })); });

await send("Page.enable");
for (const job of jobs) {
  const side = job.icon ? 512 : 0;
  await send("Emulation.setDeviceMetricsOverride",
    { width: side || 1200, height: side || 630, deviceScaleFactor: 1, mobile: false });
  const doc = job.icon ? iconOf(job) : pageOf(job);
  await send("Page.navigate", { url: `data:text/html;base64,${Buffer.from(doc).toString("base64")}` });
  await wait(900);          // the fonts are inline, so this only waits on layout
  const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
  writeFileSync(job.out, Buffer.from(shot.result.data, "base64"));
  console.log(job.out);
}
ws.close(); chrome.kill();
