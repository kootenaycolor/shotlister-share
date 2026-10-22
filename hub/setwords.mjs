#!/usr/bin/env -S node --experimental-websocket
/**
 * **Words and Arrow in Set as well as Plot** — the portal's tool bar, a word
 * and an arrow placed from Set stay in Set, and the sliding door draws as two
 * panels. (Ported from diagram.mjs's harness; ports 8798 / 9353.)
 *
 * (older header follows)
 * **Whether the portal's Diagram does what the Mac's does** — pressed and
 * dragged in a real browser, the way a hand does it.
 *
 * His ask, 2026-09-29: the portal's Diagram must *"have all the functionality
 * of the shotlister app"*. `checks.sh` can only ask the worker whether an edit
 * is kept; it cannot see a wall drawn corner by corner, a knob that stands in
 * front of a camera, or a library that will not open. This seeds the
 * Daybreak fixture into a throwaway bucket, opens the Diagrams page as its
 * owner in a headless browser, and works the plan: walls one corner at a
 * time, + to add a corner, Break / Curve / thickness, a ⇧ room, steps,
 * turning a pick, ⇧ onto the axis, the Grip tool and its library, a frame's
 * bar, Return to rename, an arrow pinned at both ends, a camera's body,
 * paste at the pointer, a locked floor clicked through — and then reads the
 * film again to see that every edit was kept by the server.
 *
 *     hub/diagram.mjs
 *
 * Its own hub on 8797 and its own browser on 9352; photographs land in /tmp,
 * or wherever SHOTS says. Builds the browser half first (`build.sh`).
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
const PORT = 8798;
const DEBUG = 9353;
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
    const names = await js(`[...document.querySelectorAll('[data-ptool]')].map((b) => b.dataset.ptool).join(',')`);
    check("Set offers Words and Arrow beside its own tools", /wall/.test(names) && /text/.test(names) && /arrow/.test(names), names);
    await js(`document.querySelector('[data-player=plot]').click()`); await wait(300);
    const plotNames = await js(`[...document.querySelectorAll('[data-ptool]')].map((b) => b.dataset.ptool).join(',')`);
    check("Plot still offers Lamp, Frame, Camera, Words, Arrow, Draw", /light/.test(plotNames) && /text/.test(plotNames) && /arrow/.test(plotNames) && /pen/.test(plotNames), plotNames);
    await js(`document.querySelector('[data-player=set]').click()`); await wait(300);
    await plan();
    await tool("arrow");
    await drag(500, 500, 700, 500);
    await settled();
    await tool("select");
    await tool("text"); await click(600, 600); await key("Escape"); await settled();
    const made = (await els()).filter((e) => e.kind === "arrow" || e.kind === "text");
    const mine = made.filter((e) => e.in_set === true);
    check("an arrow and words placed in Set say so and are Set pieces", mine.some((e) => e.kind === "arrow" && e.layer === "set") && mine.some((e) => e.kind === "text" && e.layer === "set"), JSON.stringify(made.map((e) => [e.kind, e.in_set, e.layer])));
    const old = (await els()).filter((e) => (e.kind === "arrow" || e.kind === "text") && !e.in_set);
    check("older words and arrows stay in Plot", old.every((e) => e.layer === "plot"), JSON.stringify(old.map((e) => e.layer)));
    check("nothing on the page threw", thrown.length === 0, thrown.slice(0, 2).join(" / "));
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
