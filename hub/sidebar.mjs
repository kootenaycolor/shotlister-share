#!/usr/bin/env node
/**
 * The sidebar you edit in place, Add as a menu, and Pinned and Private, driven in a real
 * browser (moves 1, 2 and 4 of design/29-portal-details).
 *
 * `checks.sh` asks the worker questions over curl, which cannot press a
 * button or drag a row. This puts a small film in a throwaway local bucket,
 * starts the hub, opens it in headless Chromium and does what a person does:
 * renames a heading by double-clicking it, folds one, drags a row under another
 * heading, turns Pinned and Private from a row's ⋯, adds a Written
 * Page under a heading from its +, pastes a link, drops a file, and then opens
 * the same film as a viewer and looks for any of it. Run it with
 * `node hub/sidebar.mjs`; `SHOTS=<dir>` also writes a picture of each state
 * there (desktop and phone).
 *
 * Local only: it never touches the real bucket, and the identity it uses
 * cannot work anywhere but localhost.
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
const PORT = 8873, DEBUG = 9373;
const WHO = "owner@example.com";
const VIEWER = "reader@example.com";
const SHOTS = process.env.SHOTS || "";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(66)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); };
const check = (what, cond, why = "not so") => (cond ? ok(what) : no(what, why));

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

const FRONT = {
  version: 1, logline: "x", linked: "link", updated: new Date(Date.now() - 3 * 3600 * 1000).toISOString(),
  sections: [
    { slug: "lighting-plan", name: "Lighting Plan", by: "mcp", type: "page", source: "here", notion: false },
    { slug: "safety-briefing", name: "Safety Briefing", by: "mcp", type: "page", source: "here", notion: false },
    { slug: "night-look", name: "Night Look", by: "mcp", type: "page", source: "here", notion: false },
    { slug: "wrap-notes", name: "Wrap Notes", by: "mcp", type: "page", source: "here", notion: false },
  ],
  documents: [{ name: "Deal memo", url: "https://drive.google.com/x", kind: "document" }],
  crew: [{ name: "Ellis Ward", role: "Gaffer" }],
  groups: [
    { name: "Creative", rows: ["night-look", "lighting-plan"] },
    { name: "Logistics", rows: ["safety-briefing", "people", "documents"] },
  ],
};

const state = mkdtempSync(join(tmpdir(), "sidebar-state-"));
const box = mkdtempSync(join(tmpdir(), "sidebar-box-"));
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
put(`p/${FILM}/people.json`, JSON.stringify({ people: [{ email: VIEWER, role: "viewer" }], links: [] }));
for (const p of FRONT.sections) put(`p/${FILM}/pages/${p.slug}.json`, JSON.stringify([{ t: "p", r: [{ s: `Words for ${p.name}.` }] }]));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:",
  "--var", "COMMIT:sidebar-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

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
  const problems = [];
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
    if (said.method === "Runtime.exceptionThrown") problems.push(said.params.exceptionDetails.exception?.description || said.params.exceptionDetails.text);
    if (said.method === "Runtime.consoleAPICalled" && said.params.type === "error") problems.push(said.params.args.map((a) => a.value || a.description).join(" "));
  });
  const ask = (method, params = {}) => new Promise((y) => {
    const n = ++id;
    waiting.set(n, y);
    ws.send(JSON.stringify({ id: n, method, params }));
    setTimeout(() => { if (waiting.has(n)) { waiting.delete(n); y({ error: `timeout ${method}` }); } }, 20000);
  });
  await ask("Page.enable");
  await ask("Runtime.enable");
  const size = (width, height, mobile = false) => ask("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile });
  await size(1440, 900);
  const js = async (e) => (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
  const open = async (path, who = WHO) => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}${path ? `/${path}` : ""}?as=${who}` });
    await wait(1800);
  };
  const shot = async (name) => {
    if (!SHOTS) return;
    mkdirSync(SHOTS, { recursive: true });
    const r = await ask("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.result.data, "base64"));
  };
  const rect = (sel) => js(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height, cx: r.left + r.width / 2, cy: r.top + r.height / 2 }; })()`);
  const mouse = (type, x, y, extra = {}) => ask("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1, ...extra });
  const move = (x, y) => ask("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  const click = async (x, y, count = 1) => { await move(x, y); await mouse("mousePressed", x, y, { buttons: 1, clickCount: count }); await mouse("mouseReleased", x, y, { clickCount: count }); };
  const key = (k, extra = {}) => ask("Input.dispatchKeyEvent", { type: "keyDown", key: k, ...extra }).then(() => ask("Input.dispatchKeyEvent", { type: "keyUp", key: k }));
  const type = (text) => ask("Input.insertText", { text });
  const heads = () => js(`[...document.querySelectorAll('nav.rail .group[data-head]')].map(g => g.dataset.head + ':' + [...g.querySelectorAll(':scope > .to[data-key]')].map(a => a.dataset.key).join(','))`);
  const until = async (fn, ms = 7000) => { for (let t = 0; t < ms; t += 250) { if (await js(fn)) return true; await wait(250); } return false; };
  const pill = () => js(`(document.querySelector('.fx-toast.on') || {}).textContent || ''`);
  const hoverRow = async (keyed) => { const r = await rect(`nav.rail .to[data-key="${keyed}"]`); await move(r.cx, r.cy); await wait(150); return r; };
  const pressMore = async (keyed) => {
    await hoverRow(keyed);
    const m = await rect(`nav.rail .to[data-key="${keyed}"] .rowmore`);
    await click(m.cx, m.cy);
    await wait(250);
  };
  const escape = () => js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);

  // ----------------------------------------------------------------------------
  say("The sidebar, plain");
  await open("");
  const bad = await js(`[...document.querySelectorAll('nav.rail .to[data-key]')].filter(a => getComputedStyle(a.querySelector('.dot')).display !== 'none').length`);
  check("no square bullet before any row", bad === 0, `${bad} rows still show one`);
  check("a heading's rows are not in a box", (await js(`getComputedStyle(document.querySelector('nav.rail .group')).boxShadow`)) === "none");
  const rowH = await js(`Math.round(document.querySelector('nav.rail .to[data-key="shotlist"]').getBoundingClientRect().height)`);
  check("a row is 30px tall", rowH === 30, `${rowH}`);
  await open("library");
  const sliver = await js(`getComputedStyle(document.querySelector('nav.rail .to.on'), '::before').width`);
  check("the current page has a 2px sliver at its edge", sliver === "2px", sliver);
  await open("night-look");
  check("…on a page that is a row, too", (await js(`getComputedStyle(document.querySelector('nav.rail .to.on[data-key="night-look"]'), '::before').width`)) === "2px");
  await open("library");
  check("Find is a field-like button under the film name", (await js(`!!document.querySelector('nav.rail .railtop .railfind')`)) === true);
  check("Add and Headings are no longer tools on the sidebar", (await js(`!document.querySelector('nav.rail .railphone') && !document.querySelector('nav.rail .railtool')`)) === true);
  check("the foot is avatar, +, Share", (await js(`[...document.querySelector('nav.rail .railfoot').children].map(c => c.className.split(' ')[0]).join(',')`)) === "railedit,me,railadd,sharebtn");
  check("Share keeps its own hook", (await js(`!!document.querySelector('nav.rail .railfoot a.sharebtn[data-share]')`)) === true);
  check("Updated N ago left the list for the film's menu", (await js(`!document.querySelector('nav.rail > .railfresh') && !!document.querySelector('nav.rail .filmmenu')`)) === true);
  await open("");
  await shot("1-sidebar");

  say("Find");
  const f = await rect("nav.rail .railfind");
  await click(f.cx, f.cy);
  await wait(400);
  check("Find opens the jump box", (await js(`!!document.querySelector('.jumpcard')`)) === true);
  await shot("2-find");
  await key("Escape");
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  await wait(200);

  // ----------------------------------------------------------------------------
  say("Headings, in place");
  await open("");
  // **The headings are the categories** (2026-10-11): Look is one of them.
  const LOOK = 'nav.rail .grouphead:has(+ .group[data-head="Creative"])';
  const h = await rect(LOOK);
  await move(h.cx, h.cy);
  await wait(250);
  check("hovering a heading shows its + and ⋯", (await js(`getComputedStyle(document.querySelector('${LOOK} .hplus')).opacity`)) === "1");
  await shot("3-heading-hover");
  const name = await rect(`${LOOK} .hname`);
  await click(name.cx, name.cy, 2);
  await wait(300);
  check("double-click puts a text box where the name is", (await js(`!!document.querySelector('nav.rail .grouphead .inedit')`)) === true);
  await shot("4-renaming");
  await key("Escape");
  await wait(200);
  check("Escape leaves the name as it was", (await js(`document.querySelector('${LOOK} .hname').textContent`)) === "Creative");
  const name2 = await rect(`${LOOK} .hname`);
  await click(name2.cx, name2.cy, 2);
  await wait(250);
  await js(`document.querySelector('nav.rail .grouphead .inedit').select()`);
  await type("Lighting");
  await key("Enter");
  await wait(600);
  check("Enter keeps the new name", (await js(`document.querySelector('nav.rail .grouphead:has(+ .group[data-head="Lighting"]) .hname').textContent`)) === "Lighting");
  await open("");
  check("…and it is saved", (await heads()).some((s) => s.startsWith("Lighting:night-look,lighting-plan")), JSON.stringify(await heads()));
  check("…as the category renamed, not a second one", (await heads()).every((s) => !s.startsWith("Creative:"))
    && (await js(`document.querySelector('nav.rail .group[data-head="Lighting"]').dataset.shelf`)) === "creative", JSON.stringify(await heads()));

  say("Folding");
  const LIT = 'nav.rail .grouphead:has(+ .group[data-head="Lighting"])';
  const fold = async () => { const hh = await rect(LIT); await move(hh.cx, hh.cy); await wait(150); const a = await rect(`${LIT} .hfold`); await click(a.cx, a.cy); await wait(250); };
  await fold();
  check("the arrow folds a heading's rows away", (await js(`document.querySelector('nav.rail .group[data-head="Lighting"]').offsetHeight`)) === 0);
  await shot("5-folded");
  await open("");
  check("…and it stays folded next time, in this browser", (await js(`document.querySelector('nav.rail .group[data-head="Lighting"]').offsetHeight`)) === 0);
  await fold();
  check("…and opens again", (await js(`document.querySelector('nav.rail .group[data-head="Lighting"]').offsetHeight`)) > 0);

  say("A new heading, and removing one");
  await open("");
  const nh = await rect("nav.rail .newhead");
  await click(nh.cx, nh.cy);
  await wait(250);
  await type("Tech");
  await key("Enter");
  await wait(600);
  check("+ New Heading adds one, at the end", (await heads()).some((s) => s.startsWith("Tech:")), JSON.stringify(await heads()));
  await open("");
  check("…and it is saved", (await heads()).some((s) => s.startsWith("Tech:")));
  const t = await rect('nav.rail .group[data-head="Tech"]');
  const th = await js(`(() => { const g = document.querySelector('nav.rail .group[data-head="Tech"]'); const r = g.previousElementSibling.getBoundingClientRect(); return { cx: r.left + 60, cy: r.top + r.height / 2 }; })()`);
  await move(th.cx, th.cy);
  await wait(150);
  const hm = await js(`(() => { const r = document.querySelector('nav.rail .grouphead:has(+ .group[data-head="Tech"]) .hmore').getBoundingClientRect(); return { cx: r.left + r.width / 2, cy: r.top + r.height / 2 }; })()`);
  await click(hm.cx, hm.cy);
  await wait(250);
  const words = await js(`[...document.querySelectorAll('.ctxmenu > .ctxitem')].map(b => b.textContent)`);
  check("a heading's ⋯ has Rename and Remove", words.includes("Rename") && words.includes("Remove"), JSON.stringify(words));
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Remove').click()`);
  await wait(600);
  check("Remove takes the heading away", !(await heads()).some((s) => s.startsWith("Tech:")), JSON.stringify(await heads()));
  check("…and says so, with an Undo", /Removed/.test(await pill()) && (await js(`!!document.querySelector('.fx-toast.on button')`)) === true);
  await wait(3500);
  await open("");
  await move((await rect(LIT)).cx, (await rect(LIT)).cy);
  await wait(150);
  await click((await rect(`${LIT} .hmore`)).cx, (await rect(`${LIT} .hmore`)).cy);
  await wait(250);
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Remove').click()`);
  await wait(500);
  check("a starting category's heading is not removed, and says why", (await heads()).some((s) => s.startsWith("Lighting:"))
    && /four starting categories/.test(await pill()), await pill());
  await escape();

  say("Dragging a heading");
  await open("");
  const order0 = (await heads()).map((s) => s.split(":")[0]);
  const OTH = 'nav.rail .grouphead:has(+ .group[data-head="Other"])';
  const from = await rect(`${OTH} .hname`);
  const to = await rect(LIT);
  await move(from.cx, from.cy);
  await mouse("mousePressed", from.cx, from.cy, { buttons: 1 });
  await move(from.cx, from.cy - 10);
  await move(to.cx, to.y + 2);
  await move(to.cx, to.y + 1);
  await mouse("mouseReleased", to.cx, to.y + 1);
  await wait(900);
  const order1 = (await heads()).map((s) => s.split(":")[0]);
  check("a heading dragged above another moves, rows and all", order1[0] === "Other" && order0[0] !== "Other", JSON.stringify(order1));
  await open("");
  check("…and the category order is saved", (await heads())[0].startsWith("Other:"), JSON.stringify(await heads()));

  // ----------------------------------------------------------------------------
  say("Dragging a row");
  await open("");
  const before = await heads();
  const a = await rect('nav.rail .to[data-key="safety-briefing"]');
  const dest = await rect('nav.rail .to[data-key="night-look"]');
  await move(a.cx, a.cy);
  await mouse("mousePressed", a.cx, a.cy, { buttons: 1 });
  await move(a.cx, a.cy - 10);
  await move(dest.cx, dest.cy - 5);
  await move(dest.cx, dest.cy - 8);
  await wait(150);
  check("while dragging, the row is a thin line in the film's colour", (await js(`(() => { const r = document.querySelector('nav.rail .to.moving'); return !!r && r.getBoundingClientRect().height <= 4; })()`)) === true);
  await shot("6-dragging");
  await mouse("mouseReleased", dest.cx, dest.cy - 8);
  await wait(900);
  const after = await heads();
  check("a row dragged under another heading lands there", after.find((s) => s.startsWith("Lighting:")).includes("safety-briefing"), JSON.stringify(after));
  await open("");
  check("…and it is saved", (await heads()).find((s) => s.startsWith("Lighting:")).includes("safety-briefing"), JSON.stringify(await heads()));

  // ----------------------------------------------------------------------------
  say("A row's ⋯: On Sidebar, Rename, Icon");
  await open("");
  await pressMore("night-look");
  const menu = await js(`[...document.querySelectorAll('.ctxmenu:not(.ctxsub) > .ctxsec, .ctxmenu:not(.ctxsub) > .ctxnode .sn, .ctxmenu:not(.ctxsub) > .ctxsep, .ctxmenu:not(.ctxsub) > .ctxitem, .ctxmenu:not(.ctxsub) > .ctxwrap > .ctxitem')].map(e => e.className.split(' ')[0] + ':' + e.textContent)`);
  check("the menu is one On Sidebar switch, then Rename and Icon",
    JSON.stringify(menu) === JSON.stringify(["sn:On Sidebar", "ctxsep:", "ctxitem:Rename", "ctxitem:Icon"]), JSON.stringify(menu));
  check("…the switch is a switch, and on", (await js(`(() => { const b = document.querySelector('.ctxmenu .sn[data-seen="pin"]'); return b.getAttribute('role') === 'switch' && b.getAttribute('aria-checked') === 'true'; })()`)) === true);
  await shot("7-row-menu");
  await escape();
  await pressMore("people");
  check("a Built In page has no Rename", JSON.stringify(await js(`[...document.querySelectorAll('.ctxmenu:not(.ctxsub) > .ctxitem, .ctxmenu:not(.ctxsub) > .ctxwrap > .ctxitem')].map(e => e.textContent)`)) === JSON.stringify(["Icon"]));
  await escape();
  // A setting that fails goes back.
  await pressMore("night-look");
  await js(`window.__fetch = window.fetch; window.fetch = () => Promise.reject(new Error('no'))`);
  const me = await rect('.ctxmenu .sn[data-seen="pin"]');
  await click(me.cx, me.cy);
  await wait(400);
  check("when the save fails the switch goes back and the pill says so",
    (await js(`document.querySelector('.ctxmenu .sn[data-seen="pin"]').classList.contains('on')`)) === true && (await pill()) === "Could Not Save"
    && (await js(`!!document.querySelector('nav.rail .to[data-key="night-look"]')`)) === true, await pill());
  await js(`window.fetch = window.__fetch`);
  await escape();
  await pressMore("wrap-notes");
  const side = await rect('.ctxmenu .sn[data-seen="pin"]');
  await click(side.cx, side.cy);
  await wait(700);
  check("On Sidebar off takes the row off the sidebar", (await js(`!document.querySelector('nav.rail .to[data-key="wrap-notes"]')`)) === true);
  await open("library");
  check("…and it is still in the Library", (await js(`!!document.querySelector('.fh-lrow[data-key="wrap-notes"]')`)) === true);

  say("Add Pages");
  await open("");
  check("with a mouse it is not drawn: pages are dragged on from the Library", (await js(`getComputedStyle(document.querySelector('nav.rail .fh-addpages')).display`)) === "none");
  // drawn for a touch screen, where there is no dragging from the Library; shown here to test what it does
  await js(`document.head.append(Object.assign(document.createElement('style'), { textContent: 'nav.rail .fh-addpages{display:flex !important}' }))`);
  const ap = await rect("nav.rail .fh-addpages");
  check("Add Pages… sits under New Heading", ap !== null && (await js(`document.querySelector('nav.rail .newhead').nextElementSibling.classList.contains('fh-addpages')`)) === true);
  await click(ap.cx, ap.cy);
  await wait(900);
  check("it opens a panel with a search and the categories, counted", (await js(`!!document.querySelector('.fh-apbox .fh-apfind') && document.querySelectorAll('.fh-apbox .fh-aphead').length >= 1`)) === true);
  check("…listing only what is not on the sidebar", (await js(`[...document.querySelectorAll('.fh-aprow .fh-apname')].map(e => e.textContent).join()`)) === "Wrap Notes",
    await js(`[...document.querySelectorAll('.fh-aprow .fh-apname')].map(e => e.textContent).join()`));
  check("…and the button counts nothing yet", (await js(`(() => { const b = document.querySelector('.fh-apgo'); return b.disabled && b.textContent === 'Add 0 Pages'; })()`)) === true);
  await js(`document.querySelector('.fh-aprow').click()`);
  check("a tick counts it", (await js(`document.querySelector('.fh-apgo').textContent`)) === "Add 1 Page");
  await shot("8-add-pages");
  await js(`document.querySelector('.fh-apgo').click()`);
  check("Add puts it back on the sidebar", await until(`!!document.querySelector('nav.rail .to[data-key="wrap-notes"]')`), JSON.stringify(await heads()));

  say("The right click on a row");
  await open("");
  await js(`document.querySelector('nav.rail .to[data-key="people"]').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 100, clientY: 300 }))`);
  await wait(200);
  const rr = await js(`[...document.querySelectorAll('.ctxmenu:not(.ctxsub) > .ctxitem, .ctxmenu:not(.ctxsub) > .ctxwrap > .ctxitem')].map(e => e.textContent)`);
  check("a right click on a sidebar row: its links, On Sidebar and Icon, not Archive", (await js(`!!document.querySelector('.ctxmenu .seenon')`)) === true && rr.includes("Open") && rr.includes("Copy Link") && rr.includes("Icon") && !rr.includes("Archive"), JSON.stringify(rr));
  await escape();

  say("Renaming a page from its row");
  await pressMore("lighting-plan");
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Rename').click()`);
  await wait(250);
  await js(`document.querySelector('nav.rail .to .inedit').select()`);
  await type("Lighting Notes");
  await key("Enter");
  await wait(700);
  check("Rename edits the name in the row, at its new address", (await js(`document.querySelector('nav.rail .to[data-key="lighting-notes"] .nm').textContent`)) === "Lighting Notes");
  await open("lighting-notes");
  check("…and the page has the new name", (await js(`document.title`)).startsWith("Lighting Notes"), await js(`document.title`));

  // ----------------------------------------------------------------------------
  say("Add is a menu");
  await open("");
  const plus = await rect("nav.rail .railfoot .railadd");
  await click(plus.cx, plus.cy);
  await wait(400);
  check("the + opens a menu with its name field focused", (await js(`document.activeElement && document.activeElement.classList.contains('fx-pop-field')`)) === true);
  const kinds = await js(`[...document.querySelectorAll('.addpop .addkind')].map(b => b.querySelector('span:nth-child(2)').textContent)`);
  check("it offers Written Page, Deck, Board, File, Link", JSON.stringify(kinds) === JSON.stringify(["Written Page", "Deck", "Board", "File", "Link"]), JSON.stringify(kinds));
  check("Written Page is lit", (await js(`document.querySelector('.addpop .addkind.on').dataset.kind`)) === "page");
  check("the Built In pages are in the same menu, each with a switch", (await js(`document.querySelectorAll('.addpop .addbuilt .fx-sw').length`)) >= 5);
  await shot("10-add");
  await key("ArrowDown");
  await key("ArrowDown");
  check("the arrow keys move the lit one", (await js(`document.querySelector('.addpop .addkind.on').dataset.kind`)) === "board");
  await key("ArrowUp");
  await key("ArrowUp");
  await type("https://www.youtube.com/watch?v=abc");
  await wait(150);
  check("a pasted address lights Link by itself", (await js(`document.querySelector('.addpop .addkind.on').dataset.kind`)) === "link");
  await shot("11-add-link");
  await js(`window.__posts = []; const f0 = window.fetch; window.fetch = async (...a) => { const r = await f0(...a); if (String(a[0]).endsWith('/add')) { const c = r.clone(); window.__posts.push(r.status + ' ' + await c.text()); } return r; }`);
  await key("Enter");
  check("Enter on Link adds it to Documents", await until(`location.pathname.endsWith('/documents') && /youtube\\.com/.test(document.body.textContent)`), await js(`location.pathname + ' | ' + JSON.stringify(window.__posts) + ' | ' + ((document.querySelector('main') || {}).innerText || 'no main').slice(0, 200)`));
  await open("");
  const built = await js(`(() => document.querySelector('nav.rail').dataset.built)()`);
  check("Built In rows carry their state", /"state":"(Empty|Notion|Filled)"/.test(built), built);

  say("Add under a heading");
  const lh = await js(`(() => { const r = document.querySelector('nav.rail .grouphead:has(+ .group[data-head="Logistics"])'); const b = r.getBoundingClientRect(); return { cx: b.left + 60, cy: b.top + b.height / 2 }; })()`);
  await move(lh.cx, lh.cy);
  await wait(200);
  const lp = await js(`(() => { const r = document.querySelector('nav.rail .grouphead:has(+ .group[data-head="Logistics"]) .hplus').getBoundingClientRect(); return { cx: r.left + r.width / 2, cy: r.top + r.height / 2 }; })()`);
  await click(lp.cx, lp.cy);
  await wait(350);
  check("a heading's + says Add to <Heading>", (await js(`document.querySelector('.addpop .fx-pop-sec').textContent`)) === "Add to Logistics", await js(`document.querySelector('.addpop .fx-pop-sec').textContent`));
  await shot("12-add-to-heading");
  await type("Gear Check");
  await key("Enter");
  await wait(1800);
  check("Enter makes the Written Page and opens it", (await js(`location.pathname.endsWith('/gear-check')`)) === true, await js(`location.pathname`));
  check("…and it is under that heading", (await heads()).find((s) => s.startsWith("Logistics:")).includes("gear-check"), JSON.stringify(await heads()));
  check("…and the pill says Added", /Added/.test(await pill()), await pill());

  say("Add refuses well");
  await open("");
  const plus2 = await rect("nav.rail .railfoot .railadd");
  await click(plus2.cx, plus2.cy);
  await wait(300);
  await type("Gear Check");
  await key("Enter");
  await wait(900);
  check("a name that is taken is said, and the menu stays", (await js(`!!document.querySelector('.addpop') && !document.querySelector('.addbox-err').hidden`)) === true, await js(`(document.querySelector('.addbox-err')||{}).textContent`));
  await escape();

  say("Dropping a file");
  await open("");
  const dropped = await js(`(async () => {
    const rail = document.querySelector('nav.rail');
    const file = new File(['%PDF-1.4 hello'], 'Look Book.pdf', { type: 'application/pdf' });
    const data = new DataTransfer();
    data.items.add(file);
    const over = new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: data });
    rail.querySelector('.sections').dispatchEvent(over);
    const lit = rail.classList.contains('dropping');
    rail.querySelector('.sections').dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: data }));
    return lit;
  })()`);
  check("a file over the sidebar lights it", dropped === true);
  await wait(1800);
  check("dropping it adds a File, with the pill Added", /Added/.test(await pill()), await pill());
  const docs = await (await fetch(`http://127.0.0.1:${PORT}/f/${FILM}/documents?as=${WHO}`)).text();
  check("…and it is in Documents", /Look Book/.test(docs));

  say("The old pages still work");
  await open("add");
  check("/add still opens", (await js(`!!document.querySelector('form.addform')`)) === true);
  await open("groups");
  check("/groups still opens", (await js(`!!document.querySelector('.fh-headform')`)) === true);
  check("…and its rail has the new look", (await js(`!!document.querySelector('nav.rail .railfind')`)) === true);

  // ----------------------------------------------------------------------------
  say("A viewer");
  await open("", VIEWER);
  check("a viewer's sidebar has Find", (await js(`!!document.querySelector('nav.rail .railfind')`)) === true);
  const none = await js(`document.querySelectorAll('nav.rail [data-add], nav.rail .railadd, nav.rail .newhead, nav.rail .hplus, nav.rail .hmore, nav.rail .hfold, nav.rail .rowmore, nav.rail .off-tag, nav.rail .filmmenu').length`);
  check("…and none of the editing: no +, ⋯, fold, New Heading, tags", none === 0, `${none}`);
  check("…the rail is not arrangeable", (await js(`!document.querySelector('nav.rail[data-arrange]')`)) === true);
  await shot("13-viewer");
  await js(`document.querySelector('nav.rail .to[data-key="shotlist"]').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 100, clientY: 300 }))`);
  await wait(200);
  const vm = await js(`[...document.querySelectorAll('.ctxmenu .ctxitem')].map(e => e.textContent)`);
  check("a right click on a row gives a viewer links only", Array.isArray(vm) && vm.includes("Open") && !vm.includes("Archive") && (await js(`!document.querySelector('.ctxmenu .seenon')`)) === true, JSON.stringify(vm));
  await escape();
  const refused = await (await fetch(`http://127.0.0.1:${PORT}/f/${FILM}/add?as=${VIEWER}`, { method: "POST", body: new URLSearchParams({ type: "page", name: "Sneaky" }), headers: { accept: "application/json" } })).status;
  check("…and the server refuses a viewer's Add", refused === 403, `${refused}`);

  // ----------------------------------------------------------------------------
  say("On a phone");
  await size(390, 844, true);
  await open("");
  check("the sidebar is still the narrow navigation sheet", (await js(`getComputedStyle(document.querySelector('.nowbar')).display`)) !== "none");
  await js(`document.querySelector('.nowbar').click()`);
  await wait(600);
  // **The tools wait behind Edit** (his pick, 2026-10-03, design/31-portal-quiet.html 2).
  await js(`document.querySelector('nav.rail .railedit').click()`);
  await wait(300);
  check("…with the heading and row controls drawn in Edit, since a thumb cannot hover", (await js(`[...document.querySelectorAll('nav.rail .hplus, nav.rail .hmore, nav.rail .hfold, nav.rail .rowmore, nav.rail .newhead')].every(e => getComputedStyle(e).opacity !== '0' && e.getBoundingClientRect().width > 0 || e.closest('.group.folded'))`)) === true);
  await shot("14-phone-sheet");
  check("the sheet opens and lists the pages", (await js(`document.querySelectorAll('nav.rail .to[data-key]').length`)) >= 6);
  check("…and an editor has the real tools in it, not the old Add and Headings copies", (await js(`!document.querySelector('nav.rail .railtool') && !!document.querySelector('nav.rail .hplus') && !!document.querySelector('nav.rail .newhead')`)) === true);
  await size(1440, 900);

  check("the console has no errors", problems.length === 0, JSON.stringify(problems.slice(0, 3)));
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
