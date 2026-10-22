#!/usr/bin/env node
/**
 * The feel of the portal (moves 7 and 8): the confirmation pill and its Undo,
 * the shared tooltip, pictures arriving, popovers, neutral switches, the focus
 * ring in the film's colour, the hairline along the top. Driven in a real
 * browser, like `library.mjs`, whose set-up this shares. Run it with
 * `node hub/feel.mjs`.
 *
 * The Library and the portal's right-click menu, driven in a real browser.
 *
 * `checks.sh` asks the worker questions over curl, which cannot press a
 * button. This puts a small film in a throwaway local bucket, starts the hub,
 * opens the Library in headless Chromium and does what a person does: switches
 * to List, ticks cards, right-clicks, applies a setting to the selection. Run
 * it with `node hub/library.mjs`; `SHOTS=<dir>` also writes a picture of each
 * state there.
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
const PORT = 8793, DEBUG = 9353;
const WHO = "owner@example.com";
const SHOTS = process.env.SHOTS || "";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(60)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(60)} FAIL — ${why}`); };
const check = (what, cond, why = "not so") => (cond ? ok(what) : no(what, why));

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

const FRONT = {
  version: 1, logline: "x", colour: "#D44C47",
  sections: [
    { slug: "lighting-plan", name: "Lighting Plan", by: "mcp", type: "page", source: "here" },
    { slug: "safety-briefing", name: "Safety Briefing", by: "mcp", type: "page", source: "here" },
    { slug: "pitch-deck", name: "Pitch Deck", by: "deck", type: "deck", source: "program" },
    { slug: "night-look", name: "Night Look", by: "mcp", type: "page", source: "here" },
    { slug: "wrap-notes", name: "Wrap Notes", by: "mcp", type: "page", source: "here" },
  ],
  documents: [
    { name: "Deal memo", url: "https://drive.google.com/x", kind: "document" },
    { name: "Call sheet day 1", url: "https://docs.google.com/y", kind: "document" },
  ],
  crew: [{ name: "Ellis Ward", role: "Gaffer" }],
  groups: [{ name: "Creative", rows: ["night-look", "lighting-plan"] }, { name: "Logistics", rows: ["safety-briefing", "people", "documents"] }],
};

const state = mkdtempSync(join(tmpdir(), "feel-state-"));
const box = mkdtempSync(join(tmpdir(), "feel-box-"));
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
  "--var", "COMMIT:feel-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

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

  proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1280,900", "about:blank"], { stdio: "ignore" });
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
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
  });
  const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
  await ask("Page.enable");
  await ask("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  const js = async (e) => (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
  const open = async (path) => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/${path}?as=${WHO}` });
    await wait(1800);
  };
  const shot = async (name) => {
    if (!SHOTS) return;
    mkdirSync(SHOTS, { recursive: true });
    const r = await ask("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.result.data, "base64"));
  };
  const right = (sel) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return false;
    const r = el.getBoundingClientRect();
    return el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: r.left + 30, clientY: r.top + 20 })); })()`);
  const click = (sel, mods = {}) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return false;
    return el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, ...${JSON.stringify(mods)} })); })()`);
  const link = (key) => `.fh-card[data-key="${key}"] .fh-cardlink`;
  const menuWords = () => js(`[...document.querySelectorAll('.ctxmenu > .ctxitem, .ctxmenu > .ctxwrap > .ctxitem')].map(b => b.textContent)`);

  say("Everything it needs is there");
  await open("library");
  check("feel.js and feel.css are on the page", (await js(`typeof window.feel === 'object' && !!document.querySelector('link[href*="feel.css"]')`)) === true);

  say("The confirmation pill");
  await js(`feel.toast('Link Copied')`);
  check("a pill appears with the words", (await js(`document.querySelector('.fx-toast.on').textContent`)) === "Link Copied");
  check("…with no Undo when none was given", (await js(`document.querySelectorAll('.fx-toast button').length`)) === 0);
  await shot("1-pill");
  await js(`window.__undone = 0; feel.toast('Archived', { undo: () => { window.__undone += 1; return true; } })`);
  check("given an undo it carries an Undo button", (await js(`document.querySelector('.fx-toast button').textContent`)) === "Undo");
  await js(`document.querySelector('.fx-toast button').click()`);
  await wait(200);
  check("…which runs it once and says Undone", (await js(`window.__undone`)) === 1 && (await js(`document.querySelector('.fx-toast').textContent`)) === "Undone");
  await wait(2800);
  check("a plain pill leaves by itself", (await js(`document.querySelector('.fx-toast').classList.contains('on')`)) === false);

  say("Archive says so, and Undo puts it back");
  await open("library");
  await right(`.fh-card[data-key="night-look"]`);
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Archive').click()`);
  await wait(2500);
  check("the next page says Archived with an Undo", (await js(`document.querySelector('.fx-toast.on') ? document.querySelector('.fx-toast').textContent : ''`)) === "ArchivedUndo");
  check("…and it is archived", (await js(`!!document.querySelector('.fh-archive .fh-card[data-key="night-look"]')`)) === true);
  await shot("2-archived");
  await js(`document.querySelector('.fx-toast button').click()`);
  for (let i = 0; i < 30 && !(await js(`!!document.querySelector('.fx-toast.on') && document.querySelector('.fx-toast').textContent === 'Undone'`)); i++) await wait(150);
  check("Undo brings it back", (await js(`!document.querySelector('.fh-archive .fh-card[data-key="night-look"]')`)) === true);
  check("…and says Undone", (await js(`document.querySelector('.fx-toast.on') ? document.querySelector('.fx-toast').textContent : ''`)) === "Undone");

  say("Tooltips");
  check("no title is left for the browser to draw", (await js(`document.querySelectorAll('[title]:not(iframe)').length`)) === 0);
  check("the title became a tooltip", (await js(`document.querySelectorAll('[data-tip]').length`)) > 3);
  await js(`window.__t = document.createElement('button'); __t.setAttribute('data-tip','Find'); __t.setAttribute('data-key','⌘K'); __t.textContent='x'; document.querySelector('.fh-pane').prepend(__t);`);
  await js(`__t.dispatchEvent(new PointerEvent('pointerover', { bubbles: true, pointerType: 'mouse' }))`);
  await wait(700);
  const tip = await js(`(document.querySelector('.fx-tip.on') || {}).textContent`);
  check("hovering shows the name and its key", /^Find(⌘K|Ctrl\+K)$/.test(tip || ""), String(tip));
  await js(`__t.remove()`);

  say("Pictures");
  await js(`(() => { const box = document.createElement('div'); box.id='pics'; box.style.cssText='width:300px'; document.querySelector('.fh-pane').prepend(box);
    const c = document.createElement('canvas'); c.width = 600; c.height = 400; const g = c.getContext('2d'); g.fillStyle = '#7a8'; g.fillRect(0,0,600,400);
    window.__png = c.toDataURL('image/png');
    const i = document.createElement('img'); i.id='pic1'; i.alt=''; i.style.width='100%'; i.src = '/nope.jpg'; box.append(i);
    const j = document.createElement('img'); j.id='pic2'; j.alt=''; j.width=300; j.height=200; j.src = window.__png; box.append(j);
    window.__sawIn = false; new MutationObserver(() => { if (j.classList.contains('fx-in')) window.__sawIn = true; }).observe(j, { attributes: true }); })()`);
  await wait(400);
  check("a picture that will not load wears the quiet failed state", (await js(`document.getElementById('pic1').classList.contains('fx-bad')`)) === true);
  check("a picture that loads fades up", (await js(`window.__sawIn`)) === true);
  await wait(1500);
  check("…and is left clean afterwards", (await js(`!document.getElementById('pic2').classList.contains('fx-wait') && !document.getElementById('pic2').classList.contains('fx-in')`)) === true);
  await js(`document.getElementById('pics').remove()`);

  say("Popovers");
  await js(`window.__a = document.querySelector('.fh-cardmenu summary'); window.__p = feel.pop(__a, '<button class="fx-pop-item">One</button><div class="fx-pop-sep"></div><button class="fx-pop-item">Two<small>T</small></button>')`);
  check("a popover opens beside the thing clicked", (await js(`(() => { const p = document.querySelector('.fx-pop').getBoundingClientRect(), a = __a.getBoundingClientRect(); return Math.abs(p.top - a.bottom) < 40; })()`)) === true);
  await shot("3-popover");
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  check("Escape closes it", (await js(`document.querySelectorAll('.fx-pop').length`)) === 0);
  await js(`document.querySelector('.fh-cardmenu summary').click()`);
  check("the ⋯ menu wears the same surface", (await js(`getComputedStyle(document.querySelector('.fh-cardmenu .pmcard')).borderRadius`)) === "14px");
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  check("…and Escape closes it", (await js(`!document.querySelector('details.fh-cardmenu[open]')`)) === true);

  say("Colour means this film");
  await js(`document.querySelector('.fh-cardmenu summary').click()`);
  const sw = await js(`(() => { const on = document.querySelector('.fh-cardmenu .pmswitch.on i'); return on ? getComputedStyle(on).backgroundColor : ''; })()`);
  check("a switch that is on is neutral, not the film's colour", sw === "rgb(237, 237, 240)", String(sw));
  await shot("4-switch");
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  await js(`document.querySelector('.fh-seg button').focus()`);
  await ask("Input.dispatchKeyEvent", { type: "keyDown", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 });
  await ask("Input.dispatchKeyEvent", { type: "keyUp", key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 });
  const focus = await js(`(() => { const e = document.activeElement; const s = getComputedStyle(e); return s.outlineStyle + ' ' + s.outlineWidth; })()`);
  check("the keyboard shows a ring where you are", /solid 2px/.test(focus || ""), String(focus));

  say("Arriving");
  await js(`document.dispatchEvent(new Event('arranging'))`);
  await js(`document.querySelector('nav.rail a[href$="/safety-briefing"]').click()`);
  await wait(60);
  const bar = await js(`(() => { const b = document.getElementById('pw-bar'); return b ? getComputedStyle(b).backgroundColor + ' ' + getComputedStyle(b).height : 'none'; })()`);
  check("a hairline in the film's colour runs along the top when the wait is long", bar === "none" || bar === "rgb(212, 76, 71) 2px", String(bar));
  await wait(1800);
  check("the page lands", (await js(`location.pathname.endsWith('/safety-briefing')`)) === true);
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
