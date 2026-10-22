/**
 * Is any sheet of this deck half empty?
 *
 * **The check that would have caught what he saw.** On 2026-09-07 four sheets
 * of his bible printed with between 1.6in and 4.7in of flat colour under the
 * frames, and it survived three rounds of checking because every round was a
 * 40dpi contact sheet — at that size an empty half-page is invisible. This
 * asks the arithmetic instead of the eye: for every sheet, how much of the box
 * the band leaves is actually filled by frames.
 *
 * A page-of-words has no frames and is skipped.
 *
 * **Measured in inches of slack, not as a percentage.** A sheet carrying one
 * sentence and three frames across can never fill — three frames across are as
 * tall as three frames across, and `fitPage` will not stretch them past 1.05×
 * — so a share-of-the-box test condemns pages that are simply sparse. What
 * separates a hole from a margin is how much bare paper is left: on his bible
 * the four bad sheets ran 1.6in to 4.7in of nothing, and after the band
 * budgets were re-solved the same four ran 1.4in to 2.7in and read as margin.
 * So `HOLE` inches is the failure and anything above `AIRY` is worth a look.
 * The lever is the band budget in the deck's `template.html`, never the
 * packing.
 *
 *     decks/checks/rig.sh            # or DATA=<folder> rig.sh for a real deck
 *     node fill.mjs                  # exits 1 if any sheet is short
 */
import { chromium } from "playwright-core";

const HOST = process.env.HOST || "http://localhost:8931";
const FILM = process.env.FILM || "01a02852ebb00198e46a252100000000";
const DECK = process.env.DECK || "lookbook";
const HOLE = Number(process.env.HOLE || 3.0);   // inches of bare sheet that is a fault
const AIRY = Number(process.env.AIRY || 1.5);   // …and that is worth a second look
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
await page.goto(`${HOST}/f/${FILM}/${DECK}/edit`, { waitUntil: "networkidle" });
await page.waitForTimeout(600);
await page.click('[data-view="paper"]');
await page.waitForTimeout(1400);

const sheets = await page.evaluate(() => {
  const root = document.getElementById("papered").shadowRoot;
  const inches = (said) => parseFloat(said) || 0;
  return [...root.querySelectorAll(".page")].map((p) => {
    const shots = p.querySelector(".shots");
    if (!shots) return null;
    const rows = [...shots.querySelectorAll(".rw")];
    if (!rows.length) return null;
    // The row heights and the box are both written in inches by `drawPaper`,
    // so this is the print's own arithmetic rather than a screen measurement.
    const hs = rows.map((r) => inches(r.style.height));
    return { section: p.dataset.section, sheet: p.dataset.sheet, rows: rows.length,
             box: inches(shots.style.height), frames: hs.reduce((a, b) => a + b, 0) };
  }).filter(Boolean);
});
await browser.close();

// The gap between rows is the deck's own; recover it from any sheet that fills.
const gap = Number(process.env.GAP || 0.13);
let holes = 0; let airy = 0;
console.log(`\n  ${"sheet".padEnd(30)} ${"box".padStart(6)} ${"frames".padStart(7)} ${"fill".padStart(5)}   bare`);
for (const s of sheets) {
  const tall = s.frames + gap * (s.rows - 1);
  const bare = Math.max(0, s.box - tall);
  const fill = s.box ? tall / s.box : 1;
  if (bare >= HOLE) holes += 1; else if (bare >= AIRY) airy += 1;
  console.log(`  ${(s.sheet + "  " + s.section).padEnd(30)} ${s.box.toFixed(2).padStart(6)} `
    + `${tall.toFixed(2).padStart(7)} ${(fill * 100).toFixed(0).padStart(4)}%   ${bare.toFixed(2)}in`
    + (bare >= HOLE ? "   <-- a hole" : bare >= AIRY ? "   (airy)" : ""));
}
if (holes) {
  console.log(`\n  ${holes} sheet${holes === 1 ? " has" : "s have"} ${HOLE}in or more of bare sheet.`);
  console.log(`  Raise the band budget in the deck's template.html — the packing cannot fix it.\n`);
} else {
  console.log(`\n  No sheet has ${HOLE}in of bare paper on it`
    + (airy ? `; ${airy} ${airy === 1 ? "is" : "are"} airy and worth looking at whole.` : ".") + "\n");
}
process.exit(holes ? 1 : 0);
