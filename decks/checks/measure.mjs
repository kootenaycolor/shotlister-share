/** The editor and the live page, measured against each other — before and
 *  after publishing from the editor. */
import { chromium } from "playwright-core";

const HOST = "http://localhost:8931";
const FILM = "01a02852ebb00198e46a252100000000";
const LIVE = `${HOST}/f/${FILM}/lookbook`;
const EDIT = `${HOST}/f/${FILM}/lookbook/edit`;
const OUT = process.argv[2] || "shots";
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

const GEOMETRY = `(() => {
  const stage = document.querySelector("#stage");
  const made = document.querySelector(".madepage");
  const host = stage && stage.shadowRoot ? stage.shadowRoot
             : made && made.shadowRoot ? made.shadowRoot : document;
  const deck = host.querySelector(".deckweb");
  const out = { rows: [], frames: [], sections: [] };
  for (const s of host.querySelectorAll("div[data-section]")) {
    const b = s.getBoundingClientRect(); const st = getComputedStyle(s);
    out.sections.push({ id: s.dataset.section, w: Math.round(b.width), h: Math.round(b.height), display: st.display });
  }
  for (const r of host.querySelectorAll(".frow")) {
    const b = r.getBoundingClientRect(); const st = getComputedStyle(r);
    out.rows.push({ cls: r.className, w: Math.round(b.width), h: Math.round(b.height),
                    gap: st.gap, display: st.display, ar: st.aspectRatio });
  }
  for (const f of host.querySelectorAll("figure[data-key]")) {
    const b = f.getBoundingClientRect();
    out.frames.push({ key: f.dataset.key, w: Math.round(b.width), h: Math.round(b.height) });
  }
  const d = deck ? deck.getBoundingClientRect() : { width: 0, x: 0 };
  out.deck = { w: Math.round(d.width), x: Math.round(d.x), found: !!deck };
  return out;
})()`;

const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
page.on("pageerror", (e) => errors.push(String(e)));
page.on("response", (r) => { if (r.status() >= 400 && !r.url().endsWith("icon.svg")) errors.push(`${r.status()} ${r.url()}`); });

async function look(url, name) {
  errors.length = 0;
  await page.goto(url, { waitUntil: "networkidle" });
  await page.waitForTimeout(500);
  const g = await page.evaluate(GEOMETRY);
  await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
  return { g, errors: [...errors] };
}

function show(name, r) {
  console.log(`\n===== ${name} =====   deck ${JSON.stringify(r.g.deck)}`);
  for (const s of r.g.sections) console.log("  section", JSON.stringify(s));
  for (const row of r.g.rows) console.log("  row    ", JSON.stringify(row));
  if (r.errors.length) console.log("  ERRORS:", r.errors.slice(0, 6));
}

/**
 * The editor against the live page — **in proportion, not in pixels.**
 *
 * They stopped being the same width on 2026-09-06, when the editor grew a rail
 * of sections and an inspector, so the deck is drawn in a narrower column than
 * the site gives it. Comparing raw pixels after that says "12 frames differ"
 * about a page that is laid out identically and merely smaller, which is a
 * check that cries wolf.
 *
 * What must not drift is the **layout**: every frame's share of the deck's
 * width, and the shape it is drawn at. Both are what the inline styles decide,
 * and both are what publishing carries across.
 */
function diff(a, b, an, bn) {
  console.log(`\n----- ${an} vs ${bn} -----`);
  if (a.frames.length !== b.frames.length) {
    console.log(`  frame count: ${an} ${a.frames.length}, ${bn} ${b.frames.length}`);
  }
  const wide = { [an]: a.deck.w, [bn]: b.deck.w };
  console.log(`  column: ${an} ${wide[an]}px, ${bn} ${wide[bn]}px`);
  let worst = 0, bad = 0;
  for (let i = 0; i < Math.min(a.frames.length, b.frames.length); i += 1) {
    const A = a.frames[i], B = b.frames[i];
    // A frame's share of the column it sits in, and the shape it is drawn at.
    const share = (f, w) => (w ? f.w / w : 0);
    const dShare = Math.abs(share(A, a.deck.w) - share(B, b.deck.w));
    const dShape = Math.abs((A.h ? A.w / A.h : 0) - (B.h ? B.w / B.h : 0));
    if (dShare > 0.005 || dShape > 0.02) {
      bad += 1;
      if (bad <= 8) {
        console.log(`  ${A.key}: ${an} ${(share(A, a.deck.w) * 100).toFixed(1)}% of the column `
          + `at ${(A.w / A.h).toFixed(2)}:1   ${bn} ${(share(B, b.deck.w) * 100).toFixed(1)}% `
          + `at ${(B.w / B.h).toFixed(2)}:1`);
      }
      worst = Math.max(worst, dShare * 100);
    }
  }
  console.log(worst
    ? `  ${bad} frames laid out differently, worst ${worst.toFixed(2)}% of the column`
    : "  every frame the same share of the column, at the same shape");
}

const edit = await look(EDIT, "editor-before");
show("EDITOR", edit);
const liveWas = await look(LIVE, "live-before");
show("LIVE (as published by the press)", liveWas);
diff(edit.g, liveWas.g, "editor", "live");

// Now publish from the editor and look at the live page again — the real test.
await page.goto(EDIT, { waitUntil: "networkidle" });
await page.waitForTimeout(400);
await page.click("#publish");
await page.waitForTimeout(1500);
const editAfter = await page.evaluate(GEOMETRY);
const liveNow = await look(LIVE, "live-after");
show("LIVE (after publishing from the editor)", liveNow);
diff(editAfter, liveNow.g, "editor", "live");

await browser.close();
