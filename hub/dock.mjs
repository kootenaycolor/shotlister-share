#!/usr/bin/env node
/**
 * The phone's dock, the sidebar as a sheet, and the touch rules (moves 1, 2
 * and 6 of design/30-portal-phone), driven in a real browser as a touch device.
 *
 * Seeds a small film in a throwaway local bucket, opens it as a 390x844 touch
 * device and does what a thumb does: opens the sheet from the dock's pill,
 * presses a heading's + and its three dots, a row's three dots, holds and drags
 * a row under another heading, finds, adds, scrolls the dock away, swipes back
 * from the edge, then looks at a reader's phone, an iPad and a desk.
 * `SHOTS=<dir>` writes a picture of each state. Run it with `node hub/dock.mjs`.
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
const PORT = 8874, DEBUG = 9374;
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

const state = mkdtempSync(join(tmpdir(), "dock-state-"));
const box = mkdtempSync(join(tmpdir(), "dock-box-"));
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
  "--var", "COMMIT:dock-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

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

  // touch device helpers
  const touchOn = async (w, h) => {
    await ask("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 1, mobile: true });
    await ask("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
    await ask("Emulation.setEmulatedMedia", { features: [{ name: "hover", value: "none" }, { name: "pointer", value: "coarse" }] });
  };
  const touchOff = async () => {
    await ask("Emulation.setTouchEmulationEnabled", { enabled: false });
    await ask("Emulation.setEmulatedMedia", { features: [] });
    await size(1440, 900);
  };
  const tp = (type, x, y) => ask("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y, id: 1 }] });
  const tap = async (x, y) => { await tp("touchStart", x, y); await wait(60); await tp("touchEnd", x, y); await wait(300); };
  const swipe = async (x0, y0, x1, y1, n = 10) => {
    await tp("touchStart", x0, y0);
    for (let i = 1; i <= n; i++) { await tp("touchMove", x0 + ((x1 - x0) * i) / n, y0 + ((y1 - y0) * i) / n); await wait(16); }
    await tp("touchEnd", x1, y1);
    await wait(900);
  };
  const tapSel = async (sel) => { const r = await rect(sel); if (!r) return false; await tap(r.cx, r.cy); return true; };
  const order = () => js(`JSON.stringify([...document.querySelectorAll('nav.rail .sections > .group[data-head]')].map(g => [g.dataset.head, [...g.querySelectorAll(':scope > .to[data-key]')].map(a => a.dataset.key)]))`);
  const sheetOpen = () => js(`document.body.classList.contains('railopen')`);
  const openSheet = async () => { if (!(await sheetOpen())) { await tapSel(".dock .nowbar"); await until(`document.body.classList.contains('railopen')`); await wait(500); } };

  // ----------------------------------------------------------------------------
  say("The dock, on a phone");
  await touchOn(390, 844);
  await open("night-look");
  check("there is one dock at the foot", (await js(`document.querySelectorAll('.fh2 .dock').length`)) === 1);
  check("…with the page pill, Find and a +", (await js(`[...document.querySelector('.dock').children].map(c => c.className.split(' ')[0]).join(',')`)) === "nowbar,dockbtn,dockbtn");
  check("…the pill names the page", (await js(`document.querySelector('.dock .nn').textContent`)) === "Night Look");
  check("…and nothing else: no count, no arrow", (await js(`document.querySelector('.dock .nowbar').children.length`)) === 1);
  check("the top line has no Share", (await js(`!document.querySelector('.fh-topbar .sharebtn')`)) === true);
  check("…and carries the film's mark and name", (await js(`!!document.querySelector('.fh-topbar .tname .filmicon') && /Call Her Back/.test(document.querySelector('.fh-topbar .tname').textContent)`)) === true);
  const small = await js(`JSON.stringify([...document.querySelectorAll('.dock .nowbar, .dock .dockbtn, .fh-topbar .tname, .fh-topbar .tback')].filter(e => e.getBoundingClientRect().height < 44).map(e => e.className))`);
  check("every dock and top-line button is 44px or taller", small === "[]", small);
  const dock = JSON.parse(await js(`JSON.stringify(document.querySelector('.dock').getBoundingClientRect())`));
  check("the dock is inside the screen (safe areas respected)", dock.bottom <= 844 && dock.left >= 0 && dock.right <= 390, JSON.stringify(dock));
  await shot("20-phone-page");

  await tapSel(".dock .dockfind");
  check("Find opens the jump box with the field focused", await until(`!!document.querySelector('.jumpshroud') && document.activeElement && document.activeElement.classList.contains('jumpfind')`));
  await shot("21-phone-find");
  await js(`document.querySelector('.jumpfind').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  await wait(300);

  await tapSel(".dock .dockadd");
  check("+ opens Add", await until(`!!document.querySelector('.fx-sheet, .fx-pop')`));
  check("…aimed at the heading the page is under", /Creative/.test(await js(`(document.querySelector('.fx-sheet') || document.querySelector('.fx-pop') || {}).textContent || ''`)));
  await escape();
  await wait(500);

  await js(`document.body.style.minHeight = '3000px'; window.scrollTo(0, 500)`); await wait(300);
  await js(`window.scrollTo(0, 900)`); await wait(500);
  check("the dock leaves on a scroll down", (await js(`document.querySelector('.dock').classList.contains('away')`)) === true);
  await js(`window.scrollTo(0, 800)`); await wait(300);
  await js(`window.scrollTo(0, 760)`); await wait(500);
  check("…and returns on a scroll up", (await js(`!document.querySelector('.dock').classList.contains('away')`)) === true);
  await js(`window.scrollTo(0, 0)`);

  await js(`feel.toast('Saved')`); await wait(400);
  const toast = JSON.parse(await js(`JSON.stringify(document.querySelector('.fx-toast').getBoundingClientRect())`));
  const dockBox = JSON.parse(await js(`JSON.stringify(document.querySelector('.dock').getBoundingClientRect())`));
  check("the confirmation pill sits above the dock", toast.bottom <= dockBox.top, `${toast.bottom} vs ${dockBox.top}`);

  // ----------------------------------------------------------------------------
  say("The sidebar, as a sheet");
  await open("night-look");
  await openSheet();
  check("the pill opens the sidebar sheet", await sheetOpen());
  await shot("22-phone-sheet");
  check("the header has the film's name, its menu and Share", (await js(`!!document.querySelector('nav.rail .railtop .filmname') && !!document.querySelector('nav.rail .railtop .filmmenu') && !!document.querySelector('nav.rail .railfoot .sharebtn[data-share]')`)) === true);
  const sh = JSON.parse(await js(`JSON.stringify(document.querySelector('nav.rail .railfoot .sharebtn').getBoundingClientRect())`));
  const sheetTop = await js(`document.querySelector('nav.rail').getBoundingClientRect().top`);
  check("…Share is on the header line, not the foot", sh.top - sheetTop < 60 && sh.height >= 44, JSON.stringify(sh));
  check("Find sits under the name", (await js(`!!document.querySelector('nav.rail .railtop .railfind') && document.querySelector('nav.rail .railtop .railfind').getBoundingClientRect().width > 200`)) === true);
  check("out of Edit, headings show only their fold", (await js(`[...document.querySelectorAll('nav.rail .grouphead')].every(h => h.querySelector('.hfold').getBoundingClientRect().width >= 36 && ['.hplus', '.hmore'].every(s => !h.querySelector(s) || h.querySelector(s).getBoundingClientRect().width === 0))`)) === true);
  check("…and rows show no ⋯", (await js(`[...document.querySelectorAll('nav.rail .to[data-key] .rowmore')].every(r => r.getBoundingClientRect().width === 0)`)) === true);
  check("Edit sits on the header line", (await js(`(() => { const e = document.querySelector('nav.rail .railedit'); const r = e && e.getBoundingClientRect(); return !!r && r.top - document.querySelector('nav.rail').getBoundingClientRect().top < 60 && r.height >= 44 && e.textContent === 'Edit'; })()`)) === true);
  await tapSel("nav.rail .railedit"); await wait(300);
  check("Edit turns to Done", (await js(`document.querySelector('nav.rail .railedit').textContent`)) === "Done");
  check("in Edit, every heading shows its fold, + and ⋯", (await js(`[...document.querySelectorAll('nav.rail .grouphead')].every(h => ['.hfold', '.hplus', '.hmore'].every(s => { const b = h.querySelector(s); const r = b && b.getBoundingClientRect(); return r && r.width >= 36 && r.height >= 44 && getComputedStyle(b).opacity === '1'; }))`)) === true);
  check("…every row shows its ⋯", (await js(`[...document.querySelectorAll('nav.rail .to[data-key]')].every(a => { const r = a.querySelector('.rowmore'); return r && r.getBoundingClientRect().width >= 44; })`)) === true);
  check("every row is 44px or taller", (await js(`[...document.querySelectorAll('nav.rail .to[data-key]')].every(a => a.getBoundingClientRect().height >= 44)`)) === true);
  check("the old phone Add and Headings tools are gone", (await js(`!document.querySelector('.railphone') && !document.querySelector('.railtool')`)) === true);
  check("+ New Heading, then Add Pages…, end the list", (await js(`(() => { const l = document.querySelector('nav.rail .sections').lastElementChild; return l.classList.contains('fh-addpages') && l.previousElementSibling.classList.contains('newhead'); })()`)) === true);

  await tapSel('nav.rail .to[data-key="night-look"] .rowmore');
  check("a row's ⋯ opens the shared Pinned and Private menu", await until(`!!document.querySelector('.ctxmenu .seenon')`));
  await shot("23-phone-rowmenu");
  await escape(); await wait(300);
  await open("night-look");
  await openSheet();
  await tapSel("nav.rail .railedit"); await wait(300);

  await tapSel('nav.rail .grouphead .hmore');
  check("a heading's ⋯ offers New Page Here, Rename and Remove", (await js(`[...document.querySelectorAll('.ctxmenu .ctxitem')].map(e => e.textContent).join('|')`)) === "New Page Here|Rename|Remove");
  const ren = await js(`(() => { const e = [...document.querySelectorAll('.ctxmenu .ctxitem')].find(x => x.textContent === 'Rename'); const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; })()`);
  await tap(ren.x, ren.y);
  check("…Rename puts a field where the name is", await until(`!!document.querySelector('nav.rail .grouphead .inedit')`));
  await shot("24-phone-rename");
  await open("night-look");
  await openSheet();
  await tapSel("nav.rail .railedit"); await wait(300);

  await tapSel('nav.rail .grouphead .hplus');
  check("a heading's + opens Add for that heading", await until(`!!document.querySelector('.fx-sheet, .fx-pop')`));
  await open("night-look");
  await openSheet();

  // press and hold, then drag, a row under another heading
  const before = await order();
  const src = await rect('nav.rail .to[data-key="lighting-plan"]');
  const dst = await rect('nav.rail .to[data-key="safety-briefing"]');
  await tp("touchStart", src.cx, src.cy);
  await wait(600);
  check("holding a row lifts it", (await js(`!!document.querySelector('nav.rail .to.lifted') && document.body.classList.contains('holding')`)) === true);
  for (let i = 1; i <= 12; i++) { await tp("touchMove", src.cx, src.cy + ((dst.cy + 10 - src.cy) * i) / 12); await wait(40); }
  check("…and then it is being dragged, with a drop line", (await js(`document.body.classList.contains('arranging') && !!document.querySelector('nav.rail .to.moving')`)) === true);
  check("…the sheet itself does not move with the finger", (await js(`document.querySelector('nav.rail').style.transform === ''`)) === true);
  await shot("25-phone-dragging");
  await tp("touchEnd", src.cx, dst.cy + 10);
  await wait(900);
  const after = await order();
  check("the row is filed under the other heading", before !== after && /Logistics",\[[^\]]*lighting-plan/.test(after), after);
  check("…and it was saved the way a desk drag is", (await js(`!document.querySelector('nav.rail').classList.contains('unsaved')`)) === true);

  // a drag down on the sheet closes it
  await js(`document.querySelector('nav.rail .sections').scrollTop = 0`);
  const top = await js(`document.querySelector('nav.rail').getBoundingClientRect().top`);
  await swipe(195, top + 30, 195, top + 330, 12);
  check("pulling the sheet down closes it", (await sheetOpen()) === false);

  // the film's name in the top line opens the sheet too
  await tapSel(".fh-topbar .tname");
  check("the film's name in the top line opens the sheet", await until(`document.body.classList.contains('railopen')`));

  // swipe back
  await open("people");
  await open("night-look");
  const here = await js(`location.pathname`);
  await swipe(5, 450, 220, 455);
  check("a swipe from the left edge goes back", (await js(`location.pathname`)) !== here, await js(`location.pathname`));
  await open("night-look");
  await swipe(80, 450, 280, 455);
  check("…a swipe that does not start at the edge does not", (await js(`location.pathname`)).endsWith("/night-look"));
  await openSheet();
  const inSheet = await js(`location.pathname`);
  await swipe(5, 500, 220, 505);
  check("…and nothing goes back from inside the sheet", (await js(`location.pathname`)) === inSheet);

  // ----------------------------------------------------------------------------
  say("A reader's phone, an iPad and a desk");
  await open("night-look", VIEWER);
  check("a reader has the dock without +", (await js(`!!document.querySelector('.dock .nowbar') && !!document.querySelector('.dock .dockfind') && !document.querySelector('.dock .dockadd')`)) === true);
  await tapSel(".dock .nowbar");
  await wait(700);
  check("…and the sheet shows no editing controls", (await js(`!document.querySelector('nav.rail .hplus, nav.rail .hmore, nav.rail .rowmore, nav.rail .newhead')`)) === true);
  await shot("26-reader-sheet");

  await touchOn(1024, 768);
  await open("night-look");
  check("an iPad has no dock", (await js(`getComputedStyle(document.querySelector('.dock')).display`)) === "none");
  check("…and keeps the sidebar with its + and ⋯ drawn", (await js(`getComputedStyle(document.querySelector('nav.rail .grouphead .hplus')).opacity !== '0' && getComputedStyle(document.querySelector('nav.rail .to .rowmore')).display !== 'none'`)) === true);
  await shot("27-ipad");

  await touchOff();
  await open("night-look");
  check("a desk has no dock", (await js(`getComputedStyle(document.querySelector('.dock')).display`)) === "none");
  check("…and no top line", (await js(`getComputedStyle(document.querySelector('.fh-topbar')).display`)) === "none");
  check("…and the foot is avatar, +, Share", (await js(`[...document.querySelector('nav.rail .railfoot').children].map(c => c.className.split(' ')[0]).join(',')`)) === "railedit,me,railadd,sharebtn");
  await shot("28-desk");

  check("the console has no errors", problems.length === 0, JSON.stringify(problems.slice(0, 3)));
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
