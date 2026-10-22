/** What the paper view laid out: per sheet, its section, the frames on each
 *  row and each row's height. The quickest honest look at the packer.
 *      node rows.mjs */
import { chromium } from "playwright-core";
const HOST = process.env.HOST || "http://localhost:8931";
const FILM = process.env.FILM || "01a02852ebb00198e46a252100000000";
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";
const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
const blew = [];
page.on("pageerror", (e) => blew.push(String(e)));
await page.goto(`${HOST}/f/${FILM}/lookbook/edit`, { waitUntil: "networkidle" });
await page.waitForTimeout(600);
await page.click('[data-view="paper"]');
await page.waitForTimeout(1200);
const said = await page.evaluate(() => {
  const root = document.getElementById("papered").shadowRoot;
  return [...root.querySelectorAll(".page")].map((p) => ({
    section: p.dataset.section,
    shots: (p.querySelector(".shots") || {}).style ? p.querySelector(".shots").style.height : "",
    rows: [...p.querySelectorAll(".rw")].map((r) => `${r.querySelectorAll("figure").length}@${parseFloat(r.style.height).toFixed(2)}${r.style.width ? "w" + r.style.width : ""}`),
  }));
});
for (const s of said) console.log(`${s.section.padEnd(28)} box ${String(s.shots).padEnd(8)} rows ${s.rows.join("  ")}`);
if (blew.length) console.log("errors:", blew);
await browser.close();
