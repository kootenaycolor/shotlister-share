/**
 * Which buttons do nothing?
 *
 * His report, 2026-09-06: *"i still dont understand the functionality of all
 * the buttons. they are not clear in funtion and often don't do anythign."*
 *
 * "Often don't do anything" is a checkable claim, so this checks it rather than
 * guessing. It puts the editor into each shape a selection can take, presses
 * every button that is offered, and records whether the deck actually changed —
 * both the record underneath and the pixels on the screen.
 *
 * A button that is offered and changes nothing is the fault. A button that is
 * visibly off is not — but one that is off with no way to know why is.
 */
import { chromium } from "playwright-core";

const HOST = process.env.HUB || "http://localhost:8931";
const FILM = "01a02852ebb00198e46a252100000000";
const EDIT = `${HOST}/f/${FILM}/lookbook/edit`;
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

// Every control the inspector offers, by what finds it.
//
// **The bar became an inspector on 2026-09-06**, on his report that the ui
// *"frankly sucks"*. The controls are the same moves under better names, plus
// two he asked for: a row can be joined downwards as well as up, and how many
// sit across is stepped per side.
const BUTTONS = [
  ['#insp [data-loud="hero"]', "Hero"],
  ['#insp [data-loud="large"]', "Large"],
  ['#insp [data-loud="normal"]', "Normal"],
  ['#insp [data-loud="quiet"]', "Quiet"],
  ['#insp [data-step="web:1"]', "Across web +"],
  ['#insp [data-step="web:-1"]', "Across web −"],
  ['#insp [data-step="paper:1"]', "Across paper +"],
  ['#insp [data-step="paper:-1"]', "Across paper −"],
  ['#insp [data-ratio="16/9"]', "Grid 16:9"],
  ['#insp [data-ratio="4/3"]', "Grid 4:3"],
  ['#insp [data-ratio=""]', "Grid True"],
  ['#insp [data-act="split"]', "Own Row"],
  ['#insp [data-act="join"]', "Join Row Above"],
  ['#insp [data-act="joinbelow"]', "Join Row Below"],
  ['#insp [data-act="replace"]', "Replace…"],
  ['#insp [data-act="crop"]', "Crop"],
  ['#insp [data-act="uncrop"]', "Recentre"],
  ['#insp [data-act="remove"]', "Remove"],
];

const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });

// **Nothing this run does is allowed to stick.** The editor saves itself, so
// without this each press carried into the next one and the deck under test
// drifted — which is how two buttons read as alive in one run and dead in the
// next. Every save is answered here and never reaches the hub, so each press
// starts from the same deck.
// **The press answers without printing.** Since 2026-09-07 a publish asks the
// portal to print, and the portal's Chrome is real and metered; here it is
// answered for.
await page.route("**/lookbook/print", (route) =>
  route.fulfill({ status: 200, contentType: "application/json", body: '{"file":"abababababababababababababababab.pdf","bytes":6000000,"ms":1200}' }));
await page.route("**/lookbook/edit", (route) =>
  route.request().method() === "POST"
    ? route.fulfill({ status: 200, contentType: "application/json", body: '{"saved":true}' })
    : route.continue());
const blew = [];
page.on("pageerror", (e) => blew.push(String(e)));

/** The deck as the record holds it, and as **both** screens draw it.
 *
 * **Both, since 2026-09-06.** Paper is drawn here now, and a control that sets
 * paper's own formatting changes nothing in the web document — so measuring
 * only that one reported "Across paper +" as a dead button when it had done
 * exactly what it says. A control is dead when it moves neither side.
 */
const shape = () => page.evaluate(() => {
  const seen = (host) => {
    if (!host) return {};
    const rows = [...host.querySelectorAll(".frow, .rw")].map((r) => {
      const b = r.getBoundingClientRect();
      return r.className + "@" + Math.round(b.width) + "x" + Math.round(b.height)
           + "/" + (r.style.height || "");
    });
    const frames = [...host.querySelectorAll("figure[data-key]")].map((f) => {
      const b = f.getBoundingClientRect();
      const img = f.querySelector("img");
      return f.dataset.key + "@" + Math.round(b.width) + "x" + Math.round(b.height)
           + "/" + (img ? img.style.objectPosition : "");
    });
    return { rows, frames, cropping: host.querySelectorAll("figure.cropping").length };
  };
  const web = document.querySelector("#stage");
  const paper = document.querySelector("#papered");
  return JSON.stringify({
    web: seen(web && web.shadowRoot),
    paper: seen(paper && paper.shadowRoot),
    drawer: document.getElementById("drawer").className,
    // The record itself, because a change that reaches neither drawing yet is
    // still a change he asked for and will see on the other side.
    said: document.getElementById("insp").textContent.replace(/\s+/g, " "),
  });
});

async function frames() {
  return (await page.$$("#stage figure[data-key]"));
}

async function pickNth(n, mods = []) {
  await page.keyboard.press("Escape");
  await page.waitForTimeout(80);
  const el = (await frames())[n];
  await el.scrollIntoViewIfNeeded();
  await page.waitForTimeout(60);
  const b = await el.boundingBox();
  for (const m of mods) await page.keyboard.down(m);
  await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
  for (const m of mods) await page.keyboard.up(m);
  await page.waitForTimeout(140);
}

async function addNth(n) {
  const el = (await frames())[n];
  await el.scrollIntoViewIfNeeded();
  await page.waitForTimeout(60);
  const b = await el.boundingBox();
  await page.keyboard.down("Meta");
  await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
  await page.keyboard.up("Meta");
  await page.waitForTimeout(140);
}

const SCENES = [
  ["one frame in a group of several", async () => { await pickNth(1); }],
  ["a frame that is alone in its group", async () => { await pickNth(0); }],
  ["two frames in the same group", async () => { await pickNth(1); await addNth(2); }],
  ["two frames in different groups", async () => { await pickNth(0); await addNth(2); }],
  ["the first group in a section", async () => { await pickNth(0); }],
];

const dead = [];
const offNoReason = [];

for (const [what, set] of SCENES) {
  console.log(`\n=== ${what} ===`);
  for (const [sel, name] of BUTTONS) {
    await page.goto(EDIT, { waitUntil: "networkidle" });
    await page.waitForTimeout(350);
    await set();
    const enabled = await page.$eval(sel, (b) => !b.disabled).catch(() => false);
    const visible = await page.$eval(sel, (b) => {
      const r = b.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    }).catch(() => false);
    if (!visible) { console.log(`  ---   ${name.padEnd(18)} not on screen`); continue; }
    if (!enabled) {
      const why = await page.$eval(sel, (b) => b.title).catch(() => "");
      if (!why) offNoReason.push(`${what} — ${name}`);
      console.log(`  off   ${name.padEnd(18)} switched off${why ? " — " + why : "  (NO REASON GIVEN)"}`);
      continue;
    }
    const before = await shape();
    await page.click(sel);
    await page.waitForTimeout(420);
    const after = await shape();
    if (before === after) {
      console.log(`  DEAD  ${name.padEnd(18)} pressed, and nothing changed`);
      dead.push(`${what} — ${name}`);
    } else {
      console.log(`  ok    ${name.padEnd(18)} changed the deck`);
    }
  }
}

console.log("\n\n================ what a hand would call broken ================");
if (!dead.length) console.log("Nothing offered does nothing.");
for (const d of dead) console.log("  DEAD:", d);
for (const o of offNoReason) console.log("  OFF WITH NO REASON:", o);
if (blew.length) { console.log("\nPAGE ERRORS:"); for (const b of blew.slice(0, 6)) console.log("   ", b); }
await browser.close();
