#!/usr/bin/env -S node --experimental-websocket
/**
 * **Door kinds on the portal** (2026-10-17): an older sliding door reads as
 * Sliding, the bar's Style menu and the Details pills change a door's kind
 * (Swing, Double, Sliding, Center, Pocket), and the server keeps it.
 * (diagram.mjs's harness, ports 8799 / 9354.)
 *
 *     hub/doorkinds.mjs
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a00b57e8790941866a989900000000";
const FIXTURE = join(HERE, "../studio/fixtures/Daybreak.shotlist");
const PORT = 8799;
const DEBUG = 9354;
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(60)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(60)} FAIL — ${why}`); };
const check = (what, good, why) => (good ? ok(what) : no(what, why));

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

say("Building the browser half…");
if (spawnSync(join(HERE, "build.sh"), { stdio: "ignore" }).status !== 0) { say("the browser half would not build"); process.exit(1); }

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const put = (key, file) =>
    spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  put(`p/${FILM}/manifest.json`, join(FIXTURE, "manifest.json"));
  for (const name of readdirSync(join(FIXTURE, "changes"))) if (name.endsWith(".log")) put(`p/${FILM}/logs/${name}`, join(FIXTURE, "changes", name));
  // The Film Set Objects pictures the plan stands its pieces on, so the
  // photographs show a camera body and a lamp, not a broken picture.
  spawnSync(join(HERE, "fso.sh"), ["--local", state], { cwd: HERE, stdio: "ignore" });
}

async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1400,900", "about:blank"], { stdio: "ignore" });
  try {
    let targets = null;
    for (let i = 0; i < 80 && !targets; i++) {
      await wait(150);
      try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch {}
    }
    if (!targets) throw new Error("the browser never answered — is Playwright's Chromium cached?");
    const page = targets.find((t) => t.type === "page");
    const ws = new WS(page.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
    await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
    let id = 0;
    const waiting = new Map();
    const thrown = [];
    ws.on("message", (m) => {
      const said = JSON.parse(m);
      if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
      if (said.method === "Runtime.exceptionThrown") thrown.push(said.params.exceptionDetails.exception?.description || said.params.exceptionDetails.text);
    });
    const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable");
    await ask("Runtime.enable");
    await ask("Emulation.setDeviceMetricsOverride", { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
    return await run(ask, thrown).finally(() => ws.close());
  } finally {
    proc.kill();
  }
}

const state = mkdtempSync(join(tmpdir(), "diagram-state-"));
say("Putting Daybreak in a local bucket…");
seed(state);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  await browser(async (ask, thrown) => {
    const js = async (expression) => {
      const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return got.result?.result?.value;
    };
    const P = async (expr) => { const t = await js(`JSON.stringify(${expr})`); try { return JSON.parse(t); } catch { return null; } };
    let edits = true;
    const open = async () => {
      await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/diagrams?as=owner@example.com` });
      for (let i = 0; i < 40; i++) { await wait(250); if (await js(`!!(window.shotlisterPlan && (document.querySelector('.planpic > svg') || document.querySelector('[data-pedit]')))`)) break; }
      await wait(300);
      // The page opens to look at (his ask, 2026-10-02); these checks edit.
      if (edits) { await js(`(document.querySelector('[data-pedit]:not(.on)') || { click() {} }).click()`); await wait(400); }
    };
    const shot = async (name) => {
      const got = await ask("Page.captureScreenshot", { format: "png" });
      writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
      say(`    → ${join(shots, name)}`);
    };
    const mods = (m = {}) => (m.alt ? 1 : 0) | (m.meta ? 4 : 0) | (m.shift ? 8 : 0);
    const mouse = (type, x, y, m = {}) => ask("Input.dispatchMouseEvent", { type, x, y, button: type === "mouseMoved" && !m.held ? "none" : "left", buttons: m.held || type === "mousePressed" ? 1 : 0, clickCount: 1, modifiers: mods(m) });
    const click = async (x, y, m = {}) => { await mouse("mouseMoved", x, y, m); await mouse("mousePressed", x, y, m); await mouse("mouseReleased", x, y, m); await wait(150); };
    const drag = async (x1, y1, x2, y2, m = {}) => {
      await mouse("mouseMoved", x1, y1, m); await mouse("mousePressed", x1, y1, m);
      for (let i = 1; i <= 8; i++) { await mouse("mouseMoved", x1 + ((x2 - x1) * i) / 8, y1 + ((y2 - y1) * i) / 8, { ...m, held: true }); await wait(16); }
      await mouse("mouseReleased", x2, y2, m); await wait(200);
    };
    const CODES = { Escape: 27, Enter: 13, Delete: 46, ArrowRight: 39 };
    const key = async (k, m = {}) => {
      const text = k.length === 1 && !m.meta ? k : undefined;
      await ask("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", key: k, windowsVirtualKeyCode: CODES[k] || k.toUpperCase().charCodeAt(0), text, modifiers: mods(m) });
      await ask("Input.dispatchKeyEvent", { type: "keyUp", key: k, windowsVirtualKeyCode: CODES[k] || k.toUpperCase().charCodeAt(0), modifiers: mods(m) });
      await wait(120);
    };
    const els = () => P(`shotlisterPlan.els()`);
    const barText = () => js(`document.querySelector('.planfloat').innerText.replace(/\\s+/g,' ')`);
    const menuText = () => js(`[...document.querySelectorAll('.planmenu')].map((m) => m.innerText.replace(/\\s+/g,' ')).join(' / ')`);
    const rightClick = async (x, y) => {
      await mouse("mouseMoved", x, y);
      await ask("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "right", buttons: 2, clickCount: 1 });
      await ask("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "right", buttons: 0, clickCount: 1 });
      await wait(200);
    };
    const handles = () => P(`shotlisterPlan.handles()`);
    const at = (x, y) => P(`shotlisterPlan.at(${x}, ${y})`);
    const plan = () => js(`document.querySelector('.planvp').focus()`);
    const tool = (k) => js(`document.querySelector('[data-ptool=${k}]').click()`);
    const clear = async () => { await plan(); await key("a", { meta: true }); await key("Delete"); await wait(1500); await open(); await plan(); };
    const settled = async () => { for (let i = 0; i < 40; i++) { const s = await P(`shotlisterPlan.state()`); if (s && !s.pending) break; await wait(150); } await wait(900); };
    edits = true;
    await open();
    await js(`document.querySelector('[data-player=set]').click()`); await wait(400);
    await js(`shotlisterPlan.edit({op:"add",els:[{kind:"wall",id:"dkw",x:0,y:0,x2:8,y2:0},
      {kind:"door",id:"dkold",x:2,y:0,w:1.8,slide:true,swing:45,hinge:"right"},
      {kind:"door",id:"dkswing",x:5,y:0,w:0.9}]})`);
    await settled();
    // The engine names what it adds: find the two doors by what they are.
    const doors = (await els()).filter((e) => e.kind === "door");
    const OLD = (doors.find((e) => e.slide && Math.abs(e.w - 1.8) < 0.01) || {}).id;
    const SWING = (doors.find((e) => !e.slide && Math.abs(e.x - 5) < 0.01) || {}).id;
    const one = async (id) => (await els()).find((e) => e.id === (id === "dkold" ? OLD : SWING)) || {};
    await js(`shotlisterPlan.pick(["${OLD}"])`); await wait(500);
    const bar = await barText();
    check("an older sliding door's bar says Style Sliding", /Style\s*Sliding/.test(bar || ""), bar);
    await shot("doorkinds-bar.png");
    // The bar's Style menu: pick Center.
    await js(`document.querySelector('.planfloat [data-pa=doorkind]').click()`); await wait(300);
    const menu = await menuText();
    check("its Style menu lists every kind", ["Swing", "Double", "Sliding", "Center", "Pocket"].every((k) => (menu || "").includes(k)), menu);
    await js(`[...document.querySelectorAll('.planmenu button, .planmenu [role=menuitem], .planmenu div')].find((b) => b.textContent.trim() === "Center").click()`);
    await settled();
    let d = await one("dkold");
    check("Center keeps it sliding, as a pair", d.slide === true && d.pair === true && !d.pocket, JSON.stringify(d));
    // The Details pills on another door: Double, then Pocket.
    await js(`shotlisterPlan.pick(["${SWING}"])`); await wait(300);
    await js(`document.querySelector('[data-ptab=details]').click()`); await wait(500);
    const pill = (v) => js(`([...document.querySelectorAll('[data-pset=door_kind]')].find((b) => b.dataset.pv === JSON.stringify("${v}")) || { click() { window.__nopill = 1 } }).click()`);
    await pill("double"); await settled();
    d = await one("dkswing");
    check("Details › Style › Double makes two swinging leaves", !d.slide && d.pair === true, JSON.stringify(d));
    await shot("doorkinds-details.png");
    await pill("pocket"); await settled();
    d = await one("dkswing");
    check("…and Pocket slides it into the wall, open as it was", d.slide === true && d.pocket === true && d.swing >= 89, JSON.stringify(d));
    check("the Style pills were there", !(await js(`window.__nopill || 0`)), "no door_kind pills in Details");
    await open();
    d = await one("dkswing");
    check("the server kept it", d.pocket === true, JSON.stringify(d));
    check("nothing on the page threw", thrown.length === 0, thrown.slice(0, 2).join(" / "));
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
