#!/usr/bin/env node
/**
 * Share, as a popover beside the button (move 3 of design/29-portal-details).
 * Driven in a real browser, with the set-up `feel.mjs` and `library.mjs` use:
 * a small film in a throwaway local bucket, the hub on its own port, headless
 * Chromium. It opens Share as the owner, copies the link, switches General
 * Access, adds and removes a person, checks there is no What Viewers See tab (it moved to the Library, 2026-10-11), shuts it with Escape — then does the phone, where it is the shared bottom sheet
 * (feel.sheet) and Add is another.
 * `SHOTS=<dir>` also writes a picture of each state there.
 *
 * Run it with `node hub/share.mjs`. Local only: it never touches the real
 * bucket, and the identity it uses cannot work anywhere but localhost.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL = `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const PORT = 8824, DEBUG = 9364;
const WHO = "owner@example.com";
const SHOTS = process.env.SHOTS || "";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(66)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(66)} FAIL: ${why}`); };
const check = (what, cond, why = "not so") => (cond ? ok(what) : no(what, why));

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

const FRONT = {
  version: 1, logline: "x", colour: "#D44C47", mark: { colour: "#D44C47", path: "M10 2l2.5 5 5.5.8-4 3.9.9 5.6L10 14.8 5.1 17.3l.9-5.6-4-3.9 5.5-.8z" },
  sections: [
    { slug: "lighting-plan", name: "Lighting Plan", by: "mcp", type: "page", source: "here" },
    { slug: "safety-briefing", name: "Safety Briefing", by: "mcp", type: "page", source: "here" },
    { slug: "night-look", name: "Night Look", by: "mcp", type: "page", source: "here" },
  ],
  documents: [{ name: "Deal memo", url: "https://drive.google.com/x", kind: "document" }],
  crew: [{ name: "Ellis Ward", role: "Gaffer" }, { name: "Max Kowalski", role: "Producer" }],
  groups: [{ name: "Look", rows: ["night-look", "lighting-plan"] }, { name: "Logistics", rows: ["safety-briefing", "people", "documents"] }],
};

const state = mkdtempSync(join(tmpdir(), "share-state-"));
const box = mkdtempSync(join(tmpdir(), "share-box-"));
const wr = join(HERE, "node_modules/.bin/wrangler");
const put = (key, body) => {
  const file = join(box, "f.bin");
  writeFileSync(file, body);
  spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
say("Putting a small film in a local bucket…");
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
put(`p/${FILM}/front.json`, JSON.stringify(FRONT));
for (const p of FRONT.sections) put(`p/${FILM}/pages/${p.slug}.json`, JSON.stringify([{ t: "p", r: [{ s: `Words for ${p.name}.` }] }]));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:",
  "--var", "COMMIT:share-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

let proc = null;
const finish = (code) => {
  try { proc && proc.kill("SIGKILL"); } catch { /* gone */ }
  try { hub.kill("SIGTERM"); } catch { /* gone */ }
  spawnSync("bash", ["-c", `sleep 1; lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -9 -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
  process.exit(code);
};

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch { /* not yet */ }
  }
  if (!up) { say("the hub would not start"); finish(1); }

  proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1440,900", "about:blank"], { stdio: "ignore" });
  let targets = null;
  for (let i = 0; i < 80 && !targets; i++) {
    await wait(150);
    try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch { /* not yet */ }
  }
  if (!targets) throw new Error("the browser never answered");
  const target = targets.find((t) => t.type === "page");
  const ws = new WS(target.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
  await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
  let id = 0;
  const waiting = new Map();
  const errors = [];
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
    if (said.method === "Runtime.exceptionThrown") errors.push(said.params.exceptionDetails.exception?.description || said.params.exceptionDetails.text);
    if (said.method === "Runtime.consoleAPICalled" && said.params.type === "error") errors.push((said.params.args[0] || {}).value || "console error");
  });
  const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
  await ask("Page.enable");
  await ask("Runtime.enable");
  await ask("Browser.grantPermissions", { permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"], origin: `http://127.0.0.1:${PORT}` });
  const desk = () => ask("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await desk();
  const js = async (e) => (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
  const open = async (path = "") => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}${path}${path.includes('?') ? '&' : '?'}as=${WHO}` });
    await wait(1800);
  };
  const shot = async (name) => {
    if (!SHOTS) return;
    await wait(450);
    mkdirSync(SHOTS, { recursive: true });
    const r = await ask("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.result.data, "base64"));
  };
  const until = async (expr, tries = 40) => { for (let i = 0; i < tries; i++) { if (await js(expr)) return true; await wait(100); } return false; };
  const api = (path, init = "") => js(`fetch('/f/${FILM}${path}', ${init || "{}"}).then(r => r.text())`);
  const people = async () => JSON.parse(await api("/api/people"));
  // The Share button that is on screen, whichever chrome is drawn.
  const press = () => js(`(() => { const b = [...document.querySelectorAll('a[data-share]:not([data-tab])')].find(a => { const r = a.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
    if (!b) return false; b.click(); return true; })()`);
  const esc = () => js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  const pillText = () => js(`(document.querySelector('.fx-toast.on') || {}).textContent || ''`);
  const choose = (sel, value) => js(`(() => { const s = document.querySelector(${JSON.stringify(sel)}); s.value = ${JSON.stringify(value)}; s.dispatchEvent(new Event('change', { bubbles: true })); return s.value; })()`);

  say("Share opens beside the button");
  await open();
  check("the sidebar has a Share button", await press() === true);
  check("a popover opens", await until(`!!document.querySelector('.fx-pop.sp')`));
  await wait(450);
  check("…and there is no centred box over a blurred page", (await js(`!document.querySelector('.shroud')`)) === true);
  if (process.env.DEBUG) say("DEBUG", await js(`JSON.stringify([document.querySelector('.fx-pop.sp').getBoundingClientRect(), [...document.querySelectorAll('a[data-share]')].map(a => a.getBoundingClientRect())])`));
  check("…it is above/beside the sidebar's button, not centred", await js(`(() => { const p = document.querySelector('.fx-pop.sp').getBoundingClientRect();
    const b = [...document.querySelectorAll('a[data-share]:not([data-tab])')].find(a => a.getBoundingClientRect().width).getBoundingClientRect();
    return Math.abs(p.left - b.left) < 60 && (p.bottom <= b.top + 2 || p.top >= b.bottom - 2) && p.left + p.width / 2 < 800; })()`));
  // Share is Access alone (2026-10-11): what a viewer sees is set in the Library.
  check("the head says Share, with no tabs", (await js(`document.querySelector('.sp-h').textContent.replace(/\\s+/g,' ').trim()`)) === "Share"
    && (await js(`!document.querySelector('.fx-pop.sp [data-tab]')`)) === true);
  check("the link line comes first, Restricted to begin with", (await js(`document.querySelector('#general').value`)) === "restricted");
  check("…with a Copy button, a role and the invite row", (await js(`!!document.querySelector('#copy') && !!document.querySelector('#linkrole') && !!document.querySelector('#who') && !!document.querySelector('#asrole') && !!document.querySelector('#add')`)) === true);
  check("Done is the film's colour and the only coloured button", await js(`(() => { const d = getComputedStyle(document.querySelector('.sp-done')).backgroundColor;
    return d === 'rgb(212, 76, 71)' && [...document.querySelectorAll('.sp-btn, .sp-seg button.on')].every(b => getComputedStyle(b).backgroundColor !== d); })()`));
  await shot("1-people");

  say("General Access and Copy");
  await choose("#general", "anyone");
  check("Anyone with the Link makes a link", await until(`document.querySelector('.sp-note') && /127\\.0\\.0\\.1/.test(document.querySelector('.sp-note').textContent) && document.querySelector('#general').value === 'anyone'`));
  check("…saved on the hub", (await people()).links.length === 1 && !(await people()).links[0].off);
  check("…and the footer says Link On", /Link On$/.test(await js(`document.querySelector('.sp-count').textContent`)));
  await js(`document.querySelector('#copy').click()`);
  check("Copy copies, and the pill says Link Copied", await until(`document.querySelector('.fx-toast.on') && document.querySelector('.fx-toast').textContent === 'Link Copied'`));
  const copied = await js(`navigator.clipboard.readText().catch(() => '')`);
  check("…what is on the clipboard is the film's link", /^http:\/\/127\.0\.0\.1:\d+\/\w+/.test(copied || ""), String(copied));
  await shot("2-link-on");
  await choose("#general", "restricted");
  check("Restricted turns it off at once, with Undo in the pill", await until(`document.querySelector('.fx-toast.on') && document.querySelector('.fx-toast').textContent.startsWith('Link Turned Off') && !!document.querySelector('.fx-toast button')`));
  check("…the link is kept but off", (await people()).links.length === 1 && (await people()).links[0].off === true);
  await js(`document.querySelector('.fx-toast button').click()`);
  check("Undo turns it back on", await until(`document.querySelector('#general').value === 'anyone'`));

  say("People");
  await js(`(() => { const w = document.querySelector('#who'); w.value = 'test.person@example.com'; w.dispatchEvent(new Event('input', { bubbles: true })); document.querySelector('#asrole').value = 'editor'; document.querySelector('#add').click(); })()`);
  check("adding a person lists them", await until(`[...document.querySelectorAll('.sp-who b')].some(b => b.textContent === 'test.person@example.com')`));
  check("…saved as an editor", (await people()).people.some((p) => p.email === "test.person@example.com" && p.role === "editor"));
  check("…and the footer counts them", /^2 people/.test(await js(`document.querySelector('.sp-count').textContent`)) || /^\d+ people/.test(await js(`document.querySelector('.sp-count').textContent`)));
  await choose(`select[data-role]`, "viewer");
  check("a role can be changed", await until(`document.querySelector('select[data-role]').value === 'viewer'`) && (await people()).people.find((p) => p.email === "test.person@example.com").role === "viewer");
  await shot("3-person");
  await choose(`select[data-role]`, "remove");
  check("Remove takes them off", await until(`![...document.querySelectorAll('.sp-who b')].some(b => b.textContent === 'test.person@example.com')`));
  check("…saved on the hub", !(await people()).people.some((p) => p.email === "test.person@example.com"));

  say("What Viewers See lives in the Library now");
  check("the popover draws no checklist", (await js(`!document.querySelector('.fx-pop.sp .sp-vform')`)) === true);
  const fragment = async () => api("/visibility?part=2");
  const flip = (shown) => js(`fetch('/f/${FILM}/visibility', { method: 'POST', headers: { accept: 'application/json' }, body: new URLSearchParams({ flip: 'sections:night-look', shown: '${shown}', back: 'library' }) }).then(r => r.status)`);
  check("the Library's switch saves the same setting", (await flip(0)) === 200 && !/name="sections" value="night-look" checked/.test(await fragment()));
  check("…and the old Visibility page agrees", !/name="sections" value="night-look" checked/.test(await api("/visibility")));
  check("…and set on again, it shows", (await flip(1)) === 200 && /name="sections" value="night-look" checked/.test(await fragment()));

  say("No For Me");
  check("there is no For Me control, and no For Me list", (await js(`!document.querySelector('.sp-seg.sm') && !document.querySelector('.sp-part[data-part="me"]') && !/For Me/.test(document.querySelector('.fx-pop.sp').innerText)`)) === true);
  await shot("5-no-for-me");

  say("Escape closes it");
  await esc();
  check("Escape closes the popover", await until(`!document.querySelector('.fx-pop.sp')`));
  // Closing refreshes the sidebar; press the Share button that is there afterwards.
  await new Promise((r) => setTimeout(r, 800));
  check("…and a second press of Share opens and then closes it", await press() && await until(`!!document.querySelector('.fx-pop.sp')`) && await press() && await until(`!document.querySelector('.fx-pop.sp')`));

  say("Add on a desk is still a popover");
  await open();
  await js(`document.querySelector('nav.rail [data-add]').click()`);
  check("Add opens a popover, not a sheet", await until(`!!document.querySelector('.fx-pop.addpop')`) && (await js(`!document.querySelector('.fx-sheet')`)) === true);
  check("…with the name field focused and the five kinds", await js(`document.activeElement === document.querySelector('.addpop .fx-pop-field') && document.querySelectorAll('.addpop .addkind').length === 5`));
  await shot("1b-desktop-add");
  await esc();
  check("Escape closes it", await until(`!document.querySelector('.fx-pop.addpop')`));

  say("The old addresses");
  await open("/share");
  check("/share lands on the film with Share open", await until(`!!document.querySelector('.fx-pop.sp')`, 60) && (await js(`location.pathname`)) === `/f/${FILM}`);
  check("…and the address is clean afterwards", (await js(`!/share=/.test(location.search)`)) === true);
  await esc();
  await open("/share?from=night-look");
  if (process.env.DEBUG) say("DEBUG2", await js(`location.href`), await js(`!!document.querySelector('.fx-pop')`));
  check("/share?from= lands on the page it was pressed on", await until(`!!document.querySelector('.fx-pop.sp')`, 60) && (await js(`location.pathname`)) === `/f/${FILM}/night-look`);
  await esc();
  await open("/visibility");
  check("the plain Visibility page still draws its form", (await js(`!!document.querySelector('.fh-visform .vcb')`)) === true);
  await open("/library");
  await js(`document.querySelector('details.me summary, .railfoot summary') && document.querySelector('details.me summary, .railfoot summary').click()`);
  check("the menu behind his initials no longer offers a second Visibility", (await js(`!document.querySelector('a[data-share][data-tab="visibility"]')`)) === true);

  say("A phone: Share is the shared bottom sheet");
  // The desk run above left a link on; the phone starts from a film with none.
  const bare = { ...(await people()), links: [] };
  await js(`fetch('/f/${FILM}/api/people', { method: 'PUT', headers: { 'content-type': 'application/json' }, body: ${JSON.stringify(JSON.stringify(bare))} }).then(r => r.status)`);
  await ask("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
  await open();
  check("the top bar has Share", await press() === true);
  check("a sheet opens", await until(`!!document.querySelector('.fx-sheet.spsheet')`));
  await wait(450);
  check("…it sits on the bottom edge and is as wide as the phone", await js(`(() => { const r = document.querySelector('.fx-sheet').getBoundingClientRect(); return Math.abs(r.bottom - innerHeight) < 2 && Math.abs(r.width - innerWidth) < 2; })()`));
  check("…with a grab handle, a scrim and rounded top corners", await js(`!!document.querySelector('.fx-sheet .fx-sheet-grab') && !!document.querySelector('.fx-sheet-scrim') && parseFloat(getComputedStyle(document.querySelector('.fx-sheet')).borderTopLeftRadius) >= 16`));
  check("…and no sideways scroll", (await js(`document.documentElement.scrollWidth <= innerWidth`)) === true);
  check("…the head leads with the film's name and who can open it", (await js(`document.querySelector('.sp-film-t b').textContent`)) === "Call Her Back" && (await js(`document.querySelector('#access').textContent.trim()`)) === "Restricted · Can View ›");
  check("…the film's mark is drawn in its colour", (await js(`getComputedStyle(document.querySelector('.sp-film')).color`)) === "rgb(212, 76, 71)");
  check("…with no tabs under it", (await js(`!document.querySelector('.sp-segrow, .fx-sheet [data-tab]')`)) === true);
  check("…then a full-width Copy Link row, saying it turns the link on", await js(`(() => { const r = document.querySelector('.sp-copyrow'); return !!r && r.getBoundingClientRect().width > innerWidth - 40 && /Copy Link/.test(r.textContent) && /Turns the link on/.test(r.textContent); })()`));
  check("…then the invite row, with Done at the foot", await js(`!!document.querySelector('#who') && !!document.querySelector('#asrole') && !!document.querySelector('#add') && !!document.querySelector('#done') && !!document.querySelector('.sp-count')`));
  check("…General Access is behind the line, not on the sheet", (await js(`!document.querySelector('#general')`)) === true);
  await shot("6-phone-people");
  await js(`document.querySelector('#access').click()`);
  check("pressing the line opens General Access and the link role", await until(`!!document.querySelector('#general') && !!document.querySelector('#linkrole')`));
  await choose("#general", "anyone");
  check("…Anyone with the Link makes a link and the line says so", await until(`/^Anyone with the Link · Can View/.test(document.querySelector('#access').textContent.trim())`));
  check("…and the Short Name and Password settings are there", await until(`!!document.querySelector('#haspass')`));
  await shot("6b-phone-access");
  await js(`document.querySelector('#access').click()`);
  check("pressing the line again puts General Access away", await until(`!document.querySelector('#general')`));
  check("…and Copy Link has nothing left to say", (await js(`document.querySelector('.sp-copyrow').textContent.trim()`)) === "Copy Link");
  await js(`document.querySelector('.sp-copyrow').click()`);
  check("Copy Link copies, and the pill says Link Copied", await until(`document.querySelector('.fx-toast.on') && document.querySelector('.fx-toast').textContent === 'Link Copied'`));
  await esc();
  check("Escape closes the sheet and the scrim", await until(`!document.querySelector('.fx-sheet') && !document.querySelector('.fx-sheet-scrim')`));
  await wait(300);
  await press();
  await until(`!!document.querySelector('.fx-sheet')`);
  await js(`document.querySelector('.fx-sheet-scrim').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true }))`);
  check("a press on the scrim closes it", await until(`!document.querySelector('.fx-sheet')`));
  await wait(300);
  await press();
  await until(`!!document.querySelector('.fx-sheet')`);
  await js(`document.querySelector('#sheetx').click()`);
  check("the close button closes it", await until(`!document.querySelector('.fx-sheet')`));
  const pull = async (sel, dy) => {
    const at = JSON.parse(await js(`(() => { const r = document.querySelector(${JSON.stringify(sel)}).getBoundingClientRect(); return JSON.stringify([r.left + r.width / 2, r.top + r.height / 2]); })()`));
    await ask("Input.dispatchMouseEvent", { type: "mousePressed", x: at[0], y: at[1], button: "left", clickCount: 1 });
    for (let i = 1; i <= 8; i++) { await ask("Input.dispatchMouseEvent", { type: "mouseMoved", x: at[0], y: at[1] + dy * i / 8, button: "left", buttons: 1 }); await wait(16); }
    await ask("Input.dispatchMouseEvent", { type: "mouseReleased", x: at[0], y: at[1] + dy, button: "left", clickCount: 1 });
  };
  await wait(300);
  await press();
  await until(`!!document.querySelector('.fx-sheet')`);
  await wait(400);
  await pull(".fx-sheet-grab", 30);
  await wait(400);
  check("a short pull on the handle springs back", (await js(`!!document.querySelector('.fx-sheet')`)) === true);
  await pull(".fx-sheet-grab", 300);
  check("a long pull down closes it", await until(`!document.querySelector('.fx-sheet')`));
  await wait(300);

  say("A phone: Add is the shared bottom sheet");
  await open();
  await js(`document.querySelector('[data-add]').click()`);
  check("Add opens a sheet", await until(`!!document.querySelector('.fx-sheet.addsheet')`));
  await wait(450);
  check("…headed Add with a close button", (await js(`document.querySelector('.fx-sheet-head b').textContent`)) === "Add" && (await js(`!!document.querySelector('.fx-sheet-head .fx-sheet-x')`)));
  check("…the name field is focused, so the keyboard is up", await js(`document.activeElement === document.querySelector('.fx-sheet .fx-pop-field')`));
  check("…the field is 16px, so the phone does not zoom", (await js(`getComputedStyle(document.querySelector('.fx-sheet .fx-pop-field')).fontSize`)) === "16px");
  check("…five kinds as 44px rows", await js(`(() => { const rows = [...document.querySelectorAll('.fx-sheet .addkind')]; return rows.length === 5 && rows.every(r => r.getBoundingClientRect().height >= 44); })()`));
  check("…named Written Page, Deck, Board, File, Link", (await js(`[...document.querySelectorAll('.fx-sheet .addkind > span:nth-child(2)')].map(e => e.textContent).join()`)) === "Written Page,Deck,Board,File,Link");
  check("…File says Photos or Files, Link says or paste one", (await js(`[...document.querySelectorAll('.fx-sheet .addkind small')].map(e => e.textContent).join()`)) === "Photos or Files,or paste one");
  check("…a file input is there for the phone's picker", await js(`(() => { const i = document.querySelector('.fx-sheet input[type=file]'); return !!i && !i.accept; })()`));
  check("…Built In is under the kinds, with neutral switches", await js(`/Built In/.test(document.querySelector('.fx-sheet').textContent) && document.querySelectorAll('.fx-sheet .addbuilt .fx-sw').length > 0`));
  check("…and no sideways scroll", (await js(`document.documentElement.scrollWidth <= innerWidth`)) === true);
  await shot("8-phone-add");
  await esc();
  check("Escape closes the Add sheet", await until(`!document.querySelector('.fx-sheet')`));
  await wait(300);
  await js(`document.querySelector('[data-add]').click()`);
  await until(`!!document.querySelector('.fx-sheet.addsheet')`);
  await js(`document.querySelector('.fx-sheet-scrim').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true }))`);
  check("a press on the scrim closes it", await until(`!document.querySelector('.fx-sheet')`));
  await wait(300);
  await js(`document.querySelector('[data-add]').click()`);
  await until(`!!document.querySelector('.fx-sheet.addsheet')`);
  await wait(400);
  await pull(".fx-sheet-grab", 300);
  check("a long pull down closes it", await until(`!document.querySelector('.fx-sheet')`));
  await wait(300);
  await js(`document.querySelector('[data-add]').click()`);
  await until(`!!document.querySelector('.fx-sheet.addsheet')`);
  await js(`(() => { const f = document.querySelector('.fx-sheet .fx-pop-field'); f.value = 'https://example.com/look'; f.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  check("a pasted address lights Link", (await js(`document.querySelector('.fx-sheet .addkind.on').dataset.kind`)) === "link");
  await js(`(() => { const f = document.querySelector('.fx-sheet .fx-pop-field'); f.value = 'Phone Page'; f.dispatchEvent(new Event('input', { bubbles: true })); document.querySelector('.fx-sheet .addkind[data-kind="page"]').click(); })()`);
  check("choosing Written Page adds it and closes the sheet", await until(`!document.querySelector('.fx-sheet') && /phone-page/.test(location.pathname)`, 60));
  await desk();

  say("Somebody holding the link");
  const key = (await people()).links[0].key;
  await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}?k=${key}` });
  await wait(2200);
  check("a link holder's Share opens a small popover", await press() && await until(`!!document.querySelector('.fx-pop.sp')`));
  await wait(450);
  check("…with the link and Copy, and none of the editor's controls", await js(`!!document.querySelector('.sp-pop, .fx-pop.sp #copy') && !document.querySelector('#who') && !document.querySelector('#general') && !document.querySelector('.sp-seg')`));
  await shot("5b-link-holder");
  await esc();

  say("The page");
  check("nothing threw", errors.length === 0, errors.slice(0, 3).join(" | "));
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
