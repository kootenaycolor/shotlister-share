/** The sheets the editor would publish, taken without publishing.
 *
 *  Opens the editor in the rig, presses Publish with the save intercepted, and
 *  writes the `paper` body of that request to a file — exactly what the live
 *  editor would put at `decks/<slug>.paper.html`, with the editor's `../pic/`
 *  put back to `pic/` the way the worker does. Used on 2026-09-07 to replace
 *  the sheets on the portal, which had been drawn before the kit carried a
 *  sheet's dress and would have printed black.
 *
 *      node capture.mjs out/paper.html
 */
import { chromium } from "playwright-core";
import { writeFileSync } from "node:fs";

const HOST = process.env.HOST || "http://localhost:8931";
const FILM = process.env.FILM || "01a02852ebb00198e46a252100000000";
const EDIT = `${HOST}/f/${FILM}/lookbook/edit`;
const OUT = process.argv[2] || "shots/paper.html";
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
let body = null;
await page.route("**/lookbook/edit", (route) => {
  if (route.request().method() !== "POST") return route.continue();
  body = route.request().postDataJSON();
  return route.fulfill({ status: 200, contentType: "application/json", body: '{"saved":true,"published":true}' });
});
await page.goto(EDIT, { waitUntil: "networkidle" });
await page.waitForTimeout(1200);
await page.click("#publish");
await page.waitForTimeout(1500);
await browser.close();
if (!body || !body.paper) { console.log("nothing captured"); process.exit(1); }
const paper = body.paper.replace(/(\s(?:src|href)=")\.\.\/pic\//g, "$1pic/");
writeFileSync(OUT, paper);
const classes = [...paper.matchAll(/<div class="(page[^"]*)" data-section="([^"]+)"/g)].map((m) => `${m[2]}:${m[1]}`);
console.log(`${classes.length} sheets →`, classes.join("  "));
console.log(`wrote ${OUT} (${paper.length} bytes)`);
