/** The paper view, photographed — and what each sheet is wearing.
 *
 *  Opens the editor in the rig, switches to Paper, shrinks the table so every
 *  sheet fits one tall picture, and writes it out. Beside the picture it
 *  prints, per sheet, the class it carries and the colour its ground and its
 *  title actually came out — because "the sheet is red" and "the title glows"
 *  are the two things his report of 2026-09-07 said were missing, and neither
 *  can be checked by reading the stylesheet.
 *
 *      node paperlook.mjs shots/paper.png
 */
import { chromium } from "playwright-core";

const HOST = process.env.HOST || "http://localhost:8931";
const FILM = process.env.FILM || "01a02852ebb00198e46a252100000000";
const EDIT = `${HOST}/f/${FILM}/lookbook/edit`;
const OUT = process.argv[2] || "shots/paper.png";
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
const blew = [];
page.on("pageerror", (e) => blew.push(String(e)));
await page.goto(EDIT, { waitUntil: "networkidle" });
await page.waitForTimeout(600);
await page.click('[data-view="paper"]');
await page.waitForTimeout(1500);

const said = await page.evaluate(() => {
  const root = document.getElementById("papered").shadowRoot;
  const sheets = root.getElementById("sheets");
  sheets.style.setProperty("--sheet", "0.3");
  // The editor is one window tall and scrolls the table inside itself; for a
  // photograph of every sheet the page is let grow instead.
  const grow = (el) => { if (el) { el.style.height = "auto"; el.style.overflow = "visible"; el.style.maxHeight = "none"; } };
  grow(document.querySelector(".deckedit"));
  grow(document.querySelector(".dbody"));
  grow(document.getElementById("canvas"));
  const out = [];
  for (const p of root.querySelectorAll(".page")) {
    const title = p.querySelector(".head, .t1");
    const ts = title ? getComputedStyle(title) : null;
    out.push({
      n: p.dataset.sheet, section: p.dataset.section, cls: p.className,
      ground: getComputedStyle(p).backgroundColor,
      title: ts ? { colour: ts.color, glow: ts.textShadow !== "none", font: ts.fontFamily.split(",")[0] } : null,
    });
  }
  return out;
});
await page.waitForTimeout(800);
await page.screenshot({ path: OUT, fullPage: true });
for (const s of said) {
  const t = s.title ? ` title ${s.title.colour} glow=${s.title.glow} ${s.title.font}` : "";
  console.log(`${String(s.n).padStart(2)} ${s.section.padEnd(28)} [${s.cls}] ground ${s.ground}${t}`);
}
if (blew.length) console.log("page errors:", blew);
console.log(`wrote ${OUT}`);
await browser.close();
