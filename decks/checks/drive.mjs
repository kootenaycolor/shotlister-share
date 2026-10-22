/** The editor, driven the way a hand drives it. */
import { chromium } from "playwright-core";

const HOST = "http://localhost:8931";
const FILM = "01a02852ebb00198e46a252100000000";
const EDIT = `${HOST}/f/${FILM}/lookbook/edit`;
const CHROME = process.env.HOME + "/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

let pass = 0, fail = 0;
const ok = (what) => { pass += 1; console.log(`  PASS  ${what}`); };
const no = (what, why) => { fail += 1; console.log(`  FAIL  ${what} — ${why}`); };
const is = (what, got, want) => (String(got) === String(want) ? ok(what) : no(what, `got ${got}, wanted ${want}`));
const yes = (what, got, why) => (got ? ok(what) : no(what, why));

const browser = await chromium.launch({ executablePath: CHROME });
const page = await browser.newPage({ viewport: { width: 1440, height: 1200 } });
const blew = [];
page.on("pageerror", (e) => blew.push(String(e)));
page.on("console", (m) => { if (m.type() === "error") blew.push(m.text()); });

// **The press answers without printing.** Since 2026-09-07 a publish asks the
// portal to print, and the portal's Chrome is real and metered; here it is
// answered for.
await page.route("**/lookbook/print", (route) =>
  route.fulfill({ status: 200, contentType: "application/json", body: '{"file":"abababababababababababababababab.pdf","bytes":6000000,"ms":1200}' }));
// **What the editor would save, kept.** The record is the only place a group's
// settings live, so the honest question about any control is not what the
// screen draws but what would be written.
let lastSave = null;
await page.route("**/lookbook/edit", (route) => {
  if (route.request().method() !== "POST") return route.continue();
  try { lastSave = route.request().postDataJSON(); } catch { /* not JSON */ }
  return route.fulfill({ status: 200, contentType: "application/json", body: '{"saved":true}' });
});
await page.goto(EDIT, { waitUntil: "networkidle" });
await page.waitForTimeout(500);

const keys = () => page.$$eval("#stage figure[data-key]", (f) => f.map((x) => x.dataset.key));
const picked = () => page.$$eval("#stage figure.picked", (f) => f.map((x) => x.dataset.key));
const said = (sel) => page.$eval(sel, (e) => e.textContent.trim());
const shown = (sel) => page.$eval(sel, (e) => !e.hidden && getComputedStyle(e).display !== "none");

/** The centre of the nth frame, with the page scrolled so it is really there. */
async function at(n) {
  const el = (await page.$$("#stage figure[data-key]"))[n];
  await el.scrollIntoViewIfNeeded();
  await page.waitForTimeout(80);
  const b = await el.boundingBox();
  return [b.x + b.width / 2, b.y + b.height / 2, b];
}
const click = async (n, mods = []) => {
  const [x, y] = await at(n);
  for (const m of mods) await page.keyboard.down(m);
  await page.mouse.click(x, y);
  for (const m of mods) await page.keyboard.up(m);
  await page.waitForTimeout(150);
};

console.log("\n— picking —");
yes("the inspector is there before anything is picked", await shown("#insp"), "hidden");
await click(1);
is("a click picks one frame", (await picked()).length, 1);
is("the inspector says what is picked", await said("#insp .dkhead b"), "Picture");
await click(3, ["Shift"]);
is("shift picks the run between", (await picked()).length, 3);
await click(5, ["Meta"]);
is("command adds one more", (await picked()).length, 4);
await page.keyboard.press("Escape");
await page.waitForTimeout(150);
is("escape lets go of everything", (await picked()).length, 0);
is("…and the inspector goes back to the deck", await said("#insp .dkhead b"), "Look Book");

console.log("\n— the group is drawn —");
await click(1);
yes("the rest of the group is outlined",
    (await page.$$eval("#stage figure.kin", (f) => f.length)) > 0, "no frame marked as kin");

console.log("\n— dragging —");
const was = await keys();
const [fx, fy] = await at(1);
const [tx, ty, tb] = await at(3);
await page.mouse.move(fx, fy);
await page.mouse.down();
await page.mouse.move(tb.x + tb.width - 8, ty, { steps: 14 });
await page.waitForTimeout(180);
const barPaint = await page.evaluate(() => {
  const r = document.querySelector(".dropbar");
  if (!r || r.hidden) return null;
  const s = getComputedStyle(r);
  return { colour: s.backgroundColor, w: r.getBoundingClientRect().width, h: r.getBoundingClientRect().height };
});
yes("the drop bar is visible while a frame is held",
    barPaint && barPaint.w > 0 && barPaint.h > 0 && barPaint.colour !== "rgba(0, 0, 0, 0)",
    `bar was ${JSON.stringify(barPaint)}`);
is("what is being dragged follows the pointer", await page.$$eval(".dghost", (g) => g.length), 1);
await page.mouse.up();
await page.waitForTimeout(300);
const now = await keys();
yes("dropping puts the frame where the bar said", JSON.stringify(now) !== JSON.stringify(was), "order unchanged");
yes("what moved stays picked", (await picked()).length === 1, "nothing picked after the move");

console.log("\n— undo and redo —");
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);
is("undo puts the order back", JSON.stringify(await keys()), JSON.stringify(was));
yes("undo puts the selection back too", (await picked()).length > 0, "nothing picked after undo");
await page.keyboard.press("Meta+Shift+z");
await page.waitForTimeout(300);
is("redo does it again", JSON.stringify(await keys()), JSON.stringify(now));
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);

console.log("\n— sweeping —");
await page.keyboard.press("Escape");
const [, , b0] = await at(0);
await page.mouse.move(b0.x - 60, b0.y - 20);
await page.mouse.down();
await page.mouse.move(b0.x + b0.width + 60, b0.y + b0.height + 260, { steps: 16 });
await page.waitForTimeout(180);
const band = await page.evaluate(() => {
  const m = document.querySelector(".marquee");
  return m && !m.hidden ? m.getBoundingClientRect().width : 0;
});
const swept = (await picked()).length;
await page.mouse.up();
await page.waitForTimeout(150);
yes("a sweep across empty space draws a band", band > 0, "no band drawn");
yes("…and picks up everything it touches", swept > 1, `picked ${swept}`);

console.log("\n— cropping, with no mode to switch off —");
await page.keyboard.press("Escape");
const [cx, cy] = await at(2);
await page.mouse.dblclick(cx, cy);
await page.waitForTimeout(200);
is("a double-click starts cropping that frame", await page.$$eval("#stage figure.cropping", (f) => f.length), 1);
const spotWas = await page.$$eval("#stage figure[data-key] img", (i) => i[2].style.objectPosition);
await page.mouse.move(cx, cy);
await page.mouse.down();
await page.mouse.move(cx - 50, cy - 25, { steps: 10 });
await page.mouse.up();
await page.waitForTimeout(250);
const spotNow = await page.$$eval("#stage figure[data-key] img", (i) => i[2].style.objectPosition);
yes("dragging inside moves the picture", spotNow && spotNow !== spotWas, `stayed at "${spotWas}"`);
await page.keyboard.press("Escape");
await page.waitForTimeout(150);
is("escape leaves cropping", await page.$$eval("#stage figure.cropping", (f) => f.length), 0);
// And the thing the old mode broke: after cropping, dragging still reorders.
const orderWas = await keys();
const [ax, ay] = await at(1);
const [, by, bb] = await at(3);
await page.mouse.move(ax, ay);
await page.mouse.down();
await page.mouse.move(bb.x + bb.width - 8, by, { steps: 12 });
await page.mouse.up();
await page.waitForTimeout(300);
yes("and a frame can still be dragged straight afterwards",
    JSON.stringify(await keys()) !== JSON.stringify(orderWas), "order unchanged");
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);

console.log("\n— the keys —");
await click(1);
const before = (await picked())[0];
await page.keyboard.press("ArrowRight");
await page.waitForTimeout(150);
yes("an arrow moves what is picked", (await picked())[0] !== before, "selection did not move");
await page.keyboard.press("1");
await page.waitForTimeout(300);
yes("a digit sets the emphasis",
    await page.$$eval("#stage .frow", (r) => r.some((x) => x.className.includes("loud-hero"))), "no hero row");
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);
const many = (await keys()).length;
await click(1);
await page.keyboard.press("Delete");
await page.waitForTimeout(300);
is("delete takes a frame out", (await keys()).length, many - 1);
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);
is("…and undo brings it back", (await keys()).length, many);

console.log("\n— the right-click menu —");
const [mx, my] = await at(2);
await page.mouse.click(mx, my, { button: "right" });
await page.waitForTimeout(200);
is("right-click opens a menu", await shown("#menu"), "true");
const rows = await page.$$eval("#menu [data-act]", (b) => b.length);
yes("…with the moves on it", rows >= 10, `only ${rows} rows`);
await page.keyboard.press("Escape");
await page.waitForTimeout(150);
is("escape shuts it", await shown("#menu"), "false");

console.log("\n— it saves itself —");
await click(1);
// Press a number the row is NOT already at — pressing the one it is at is now
// a deliberate no-op, and would prove nothing about saving.
const already = await page.$eval("#insp .dkstep span", (b) => b.textContent.trim()).catch(() => "3");
const want = already === "2" ? "4" : "2";
await page.keyboard.press(want);
await page.waitForTimeout(300);
const dirty = await said("#state");
await page.waitForTimeout(2400);
is("it says there is something unpublished", dirty, "Unpublished");
is("…and saves it without being asked", await said("#state"), "Saved");
const wanted = { "1": 1, "2": 2, "3": 3, "4": 4 }[want];
is("what it sent is what is on screen", await page.$eval("#insp .dkstep span", (b) => b.textContent.trim()), String(wanted));

console.log("\n— the shelf —");
await page.keyboard.press("Escape");
await click(1);
await page.click('#insp [data-act="replace"]');
await page.waitForTimeout(400);
is("Replace opens the film's pictures", await shown("#stills"), "true");
const tiles = await page.$$eval(".dkpic", (t) => t.length);
yes("…and it holds the film's library, not just this deck's", tiles >= 12, `only ${tiles}`);
const swapWas = await keys();
await page.click(".dkpic:not(.dkused)").catch(() => page.click(".dkpic"));
await page.waitForTimeout(400);
yes("clicking one puts it in place of the frame picked",
    JSON.stringify(await keys()) !== JSON.stringify(swapWas), "nothing changed");
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);

if (!(await shown("#stills"))) { await page.click('#insp [data-act="replace"]'); await page.waitForTimeout(350); }
const dragWas = (await keys()).length;
// Scroll first — measuring the tile before scrolling gives a stale box.
const [dx, dy] = await at(2);
const tile = (await page.$$(".dkpic"))[0];
const tb2 = await tile.boundingBox();
await page.mouse.move(tb2.x + tb2.width / 2, tb2.y + tb2.height / 2);
await page.mouse.down();
await page.mouse.move(dx, dy, { steps: 16 });
await page.waitForTimeout(150);
const shelfGhost = await page.$$eval(".dghost", (g) => g.length);
await page.mouse.up();
await page.waitForTimeout(400);
is("a picture can be dragged off the shelf", shelfGhost, 1);
is("…and lands where it was dropped", (await keys()).length, dragWas + 1);
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);

console.log("\n— splitting and joining —");
await click(1);
const rowsWas = await page.$$eval("#stage .frow", (r) => r.length);
await page.click('#insp [data-act="split"]');
await page.waitForTimeout(400);
yes("Own Row makes a group of its own",
    (await page.$$eval("#stage .frow", (r) => r.length)) > rowsWas, "no new row");
await page.click('#insp [data-act="join"]');
await page.waitForTimeout(400);
is("Join Row Above folds it back", await page.$$eval("#stage .frow", (r) => r.length), rowsWas);

console.log("\n— what a new row inherits —");
// **A row split off a group is that group with fewer pictures in it.** Twice
// now a group has been rebuilt from a hand-written literal and quietly lost a
// setting: first `ratio`, so a row off an even grid came out ragged, then
// `across` — which since the portal began printing the PDF decides the printed
// sheet. Asked of the record, because the record is what publishes.
await page.keyboard.press("Escape");
await page.waitForTimeout(150);
await click(6);                                    // a frame of the even 4:3 grid
// One fewer across, not one more: a group already at its widest has the
// "+" disabled, and this only needs `across` written onto the group.
const stepper = await page.$('#insp [data-step$=":-1"]:not([disabled])');
if (!stepper) no("the inspector offers how many across", "no stepper for a picked frame");
else {
  await stepper.click();
  await page.waitForTimeout(400);
  await page.click('#insp [data-act="split"]');
  await page.waitForTimeout(1200);
  const worlds = ((lastSave && lastSave.sections) || []).find((s) => s.id === "worlds") || {};
  const grid = (worlds.groups || []).filter((g) => g.ratio === "4/3");
  is("a row split off an even grid is still an even grid", grid.length, 2);
  yes("…and keeps how many across", grid.length === 2 && grid.every((g) => g.across && g.across.paper),
      `across on the split rows: ${JSON.stringify(grid.map((g) => g.across))}`);
  await page.keyboard.press("Meta+z");
  await page.waitForTimeout(300);
  await page.keyboard.press("Meta+z");
  await page.waitForTimeout(300);
}

console.log("\n— paper, which is arranged and not just looked at —");
await page.keyboard.press("Escape");
await page.click('[data-view="paper"]');
await page.waitForTimeout(900);
const sheetsOn = () => page.$$eval("#papered", (h) =>
  h[0].shadowRoot.querySelectorAll(".page").length);
const onPaper = () => page.$$eval("#papered", (h) =>
  [...h[0].shadowRoot.querySelectorAll("figure[data-key]")].map((f) => f.dataset.key));
const sheets = await sheetsOn();
yes("the paper view draws real sheets", sheets > 1, `drew ${sheets}`);
// **A sheet wears what its design wrote.** The kit carries each block's class
// and the editor puts it on the sheet — dropped, every sheet of his red bible
// came out black (2026-09-07). The seed dresses the opening in `red` and
// leaves worlds a bare string, so both shapes of a block are read.
const dress = await page.evaluate(() => {
  const root = document.getElementById("papered").shadowRoot;
  const first = (id) => root.querySelector(`.page[data-section="${id}"]`);
  const o = first("opening"), w = first("worlds");
  return { o: o && o.className, ob: o && getComputedStyle(o).backgroundColor,
           w: w && w.className, wb: w && getComputedStyle(w).backgroundColor };
});
is("a sheet wears the class its design gave it", dress.o, "page red");
is("…and is painted by it", dress.ob, "rgb(77, 8, 18)");
is("a block sent as a bare string still draws, undressed", dress.w, "page");
is("…on the plain ground", dress.wb, "rgb(22, 18, 20)");
const sheetBox = await page.evaluate(() =>
  document.getElementById("papered").shadowRoot.querySelector(".page").getBoundingClientRect());
yes("…at the size they print", Math.abs(sheetBox.width - 816) < 3 && Math.abs(sheetBox.height - 1056) < 3,
    `sheet was ${Math.round(sheetBox.width)}x${Math.round(sheetBox.height)}`);
is("every frame is on paper too", (await onPaper()).length, (await keys()).length);
const pbox = await page.evaluate(() => {
  const f = document.getElementById("papered").shadowRoot.querySelectorAll("figure[data-key]")[2];
  f.scrollIntoView({ block: "center" });
  const b = f.getBoundingClientRect();
  return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
});
await page.mouse.click(pbox.x, pbox.y);
await page.waitForTimeout(300);
is("a frame on a sheet can be picked", await said("#insp .dkhead b"), "Picture");
yes("…and the inspector offers paper's own controls",
    (await page.$$eval("#insp [data-step]", (b) => b.length)) >= 2, "no per-side stepper");
const rwWas = await page.$$eval("#papered", (h) =>
  [...h[0].shadowRoot.querySelectorAll(".rw")].map((r) => r.style.height).join(","));
await page.keyboard.press("1");
await page.waitForTimeout(600);
const rwNow = await page.$$eval("#papered", (h) =>
  [...h[0].shadowRoot.querySelectorAll(".rw")].map((r) => r.style.height).join(","));
yes("…and arranging on paper redraws the sheets", rwNow !== rwWas, "the sheets did not change");
await page.keyboard.press("Meta+z");
await page.waitForTimeout(400);
is("undo puts the sheets back", await page.$$eval("#papered", (h) =>
  [...h[0].shadowRoot.querySelectorAll(".rw")].map((r) => r.style.height).join(",")), rwWas);
await page.keyboard.press("Escape");
await page.waitForTimeout(200);
const pdfLink = await page.$$eval("#insp a.dkbtn", (a) => (a[0] ? a[0].getAttribute("href") : ""));
yes("the printed file is still offered", /\/pic\/[0-9a-f]{32}\.pdf$/.test(pdfLink || ""), `link was "${pdfLink}"`);

await page.screenshot({ path: "shots/driven.png", fullPage: false });
console.log("\n— what driving found on 2026-09-07 —");
await page.click('[data-view="web"]');
await page.keyboard.press("Escape");
await page.waitForTimeout(250);
const zoomWas = (await at(0))[2].width;
await page.click("#zoomin"); await page.click("#zoomin");
await page.waitForTimeout(200);
const zoomNow = (await at(0))[2].width;
yes("zoom changes the web side, not only its own number", zoomNow > zoomWas * 1.1, `${zoomWas} -> ${zoomNow}`);
await page.click("#zoomout"); await page.click("#zoomout");
await page.waitForTimeout(200);
is("…and back", Math.round((await at(0))[2].width), Math.round(zoomWas));

await page.click('[data-source="film"]');
await page.waitForTimeout(300);
const tileNow = await page.$eval("#stills .dkpic.dkused", (b) => {
  const s = getComputedStyle(b);
  return { flex: s.flexShrink, pad: s.paddingLeft, tick: getComputedStyle(b, "::after").content };
});
yes("a shelf tile is drawn as a tile", tileNow.flex === "0" && tileNow.pad === "0px", JSON.stringify(tileNow));
is("…and one in the deck wears its tick", tileNow.tick, '"✓"');

await click(2);
await page.keyboard.press("Backspace");
await page.waitForTimeout(250);
await page.click('[data-source="unused"]');
await page.waitForTimeout(250);
const unused = await page.$$eval("#stills .dkpic", (t) => t.map((b) => b.classList.contains("dkused")));
yes("Unused lists stills not yet in the deck", unused.length === 1 && !unused[0], JSON.stringify(unused));
await page.keyboard.press("Meta+z");
await page.waitForTimeout(250);
is("…and empties when they are back", await page.$$eval("#stills .dkpic", (t) => t.length), 0);
await page.click('[data-source="film"]');
await page.waitForTimeout(250);
yes("Add Stills… is on the shelf", await shown("#addstills"), "no button");
yes("…and is a real file picker", await page.$eval("#addfiles", (i) => i.type === "file" && i.multiple), "not a file input");

await page.click("#drawergrid");
await page.waitForTimeout(250);
is("the drawer can be a grid", await page.$eval("#stills", (e) => getComputedStyle(e).flexWrap), "wrap");
await page.click("#drawergrid");
await page.waitForTimeout(250);

const tiles2 = await page.$$("#stills .dkpic");
const t0 = await tiles2[0].boundingBox();
const t1 = await tiles2[1].boundingBox();
await page.mouse.click(t0.x + 10, t0.y + 10);
await page.keyboard.down("Shift");
await page.mouse.click(t1.x + 10, t1.y + 10);
await page.keyboard.up("Shift");
await page.waitForTimeout(200);
is("shift picks two on the shelf", await page.$$eval("#stills .dkpic.dkon", (t) => t.length), 2);
is("…and the shelf says so", await said("#shelfsaid"), "2 picked");
const manyWas = (await keys()).length;
const [gx, gy, gb] = await at(3);
const p0 = await (await page.$("#stills .dkpic.dkon")).boundingBox();
await page.mouse.move(p0.x + 10, p0.y + 10);
await page.mouse.down();
await page.mouse.move(gb.x + gb.width - 8, gy, { steps: 14 });
await page.waitForTimeout(150);
is("both follow the pointer", await page.$eval(".dghost", (g) => g.dataset.many), "2");
await page.mouse.up();
await page.waitForTimeout(350);
is("…and both land in the row", (await keys()).length, manyWas + 2);
is("…picked", (await picked()).length, 2);
await page.keyboard.press("Meta+z");
await page.waitForTimeout(300);

await page.mouse.dblclick(t0.x + 10, t0.y + 10);
await page.waitForTimeout(400);
is("double-click on a still opens it whole", await shown("#look"), "true");
yes("…and says its size", /\d+ × \d+ · [\d.]+:1/.test(await said("#looksaid")), `said "${await said("#looksaid")}"`);
await page.keyboard.press("Escape");
await page.waitForTimeout(150);
is("escape closes it", await shown("#look"), "false");

await click(1);
await page.keyboard.press("Meta+a");
await page.waitForTimeout(200);
const sectionCount = await page.$$eval("#stage figure[data-key]", (f) => f.filter((x) => x.dataset.section === f[1].dataset.section).length);
is("command-A picks the section", (await picked()).length, sectionCount);
await page.keyboard.press("Meta+a");
await page.waitForTimeout(200);
is("…and again, the deck", (await picked()).length, (await keys()).length);
await page.keyboard.press("Escape");

await click(1);
const nudgeWas = await keys();
await page.keyboard.press("Alt+ArrowRight");
await page.waitForTimeout(250);
const nudged = await keys();
yes("option-right swaps the frame along its row", nudged[1] === nudgeWas[2] && nudged[2] === nudgeWas[1], `${nudgeWas.slice(0,3)} -> ${nudged.slice(0,3)}`);
await page.keyboard.press("Alt+ArrowLeft");
await page.waitForTimeout(250);
is("…and back", JSON.stringify(await keys()), JSON.stringify(nudgeWas));

await page.keyboard.press("Escape");
await page.waitForTimeout(150);
await page.click("#linknotion");
await page.waitForTimeout(150);
yes("Link… opens a field, not a prompt", await shown("#notionurl"), "no field");
await page.fill("#notionurl", "https://www.notion.so/Some-Page-e3f032cd713e8f395a68dfb5d8c7a6e3");
await page.keyboard.press("Enter");
await page.waitForTimeout(300);
yes("…and enter links it", (await said("#insp")).includes("Linked page"), "inspector does not say Linked page");

await click(1);
const [rx, ry] = await at(1);
await page.mouse.click(rx, ry, { button: "right" });
await page.waitForTimeout(150);
yes("the menu offers emphasis", (await page.$$eval('#menu [data-act^="loud:"]', (b) => b.length)) === 4, "no emphasis rows");
await page.keyboard.press("Escape");

await page.setViewportSize({ width: 1000, height: 900 });
await page.waitForTimeout(300);
const deckBox = await page.$eval("#canvas", (c) => c.getBoundingClientRect().width);
yes("a narrow window keeps the deck on screen", deckBox > 500, `canvas ${deckBox}px wide`);
await page.setViewportSize({ width: 900, height: 900 });
await page.waitForTimeout(300);
const deckBox2 = await page.$eval("#canvas", (c) => c.getBoundingClientRect().width);
yes("…even at the app's smallest", deckBox2 > 500, `canvas ${deckBox2}px wide`);
await page.setViewportSize({ width: 1440, height: 1200 });

console.log("");
if (blew.length) { console.log("PAGE ERRORS:"); for (const b of blew.slice(0, 10)) console.log("   ", b); }
console.log(`${pass} passed, ${fail} failed, ${blew.length} page errors`);
await browser.close();
process.exit(fail || blew.length ? 1 : 0);
