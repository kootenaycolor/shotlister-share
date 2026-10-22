#!/usr/bin/env -S node --experimental-websocket
/**
 * **Copying plans between scenes on the portal** — Copy From with Add on
 * Top and Replace, Copy To several scenes, Send to Scene — pressed in a real
 * browser, then the film read again to see the server kept every copy. A
 * short cousin of `diagram.mjs` (his ask, 2026-10-01: copying properly).
 *
 * His ask, 2026-09-29: the portal's Diagram must *"have all the functionality
 * of the shotlister app"*. `checks.sh` can only ask the worker whether an edit
 * is kept; it cannot see a wall drawn corner by corner, a knob that stands in
 * front of a camera, or a library that will not open. This seeds the
 * Daybreak fixture into a throwaway bucket, opens the Diagrams page as its
 * owner in a headless browser, and works the plan: walls one corner at a
 * time, + to add a corner, Break / Curve / thickness, a ⇧ room, Turn To,
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
      for (let i = 0; i < 40; i++) { await wait(250); if (await js(`!!(window.shotlisterPlan && (document.querySelector('.planpic svg') || document.querySelector('[data-pedit]')))`)) break; }
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
    const handles = () => P(`shotlisterPlan.handles()`);
    const at = (x, y) => P(`shotlisterPlan.at(${x}, ${y})`);
    const plan = () => js(`document.querySelector('.planvp').focus()`);
    const tool = (k) => js(`document.querySelector('[data-ptool=${k}]').click()`);
    const clear = async () => { await plan(); await key("a", { meta: true }); await key("Delete"); await wait(1500); await open(); await plan(); };
    const settled = async () => { for (let i = 0; i < 40; i++) { const s = await P(`shotlisterPlan.state()`); if (s && !s.pending) break; await wait(150); } await wait(900); };

    const scene = () => js(`shotlisterPlan.scene()`);
    const go = async (id) => { await js(`document.querySelector('[data-pick=plan][data-id="${id}"]').click()`); await wait(400); };
    const rowsOf = () => P(`[...document.querySelectorAll('[data-pick=plan]')].map((b) => b.dataset.id)`);
    const toast = () => js(`(document.querySelector('.plantoast')||{}).textContent`);

    await open();
    const home = await scene();
    const all = await rowsOf();
    const [a, b] = all.filter((id) => id !== home);
    check("the page lists other scenes to copy to", Boolean(a && b), JSON.stringify(all));

    // A room, and a camera in it.
    await plan();
    await tool("wall");
    await click(450, 350); await click(800, 350); await click(800, 650); await click(450, 650); await click(450, 351);
    await P(`shotlisterPlan.edit({ op: "add", els: [{ kind: "camera", x: 0, y: 0 }] })`);
    await settled();
    const mine = (await els()).length;
    check("the plan to copy holds a room and a camera", mine === 2, `${mine} pieces`);

    // ---- Copy To two scenes ----------------------------------------------------
    await js(`document.querySelector('[data-pcopymenu]').click()`); await wait(200);
    const menu = await js(`document.querySelector('.planmenu').innerText.replace(/\\s+/g, ' ')`);
    check("Copy offers Copy To", /Copy To/.test(menu), menu);
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /Copy To/.test(x.textContent)).click()`); await wait(200);
    await js(`document.querySelector('[data-pcopyto="${a}"]').click()`); await wait(100);
    await js(`document.querySelector('[data-pcopyto="${b}"]').click()`); await wait(100);
    await shot("copy-to.png");
    await js(`document.querySelector('[data-pcopygo]').click()`); await wait(300);
    check("Copy To says where it went", /Copied to 2 plans/.test(await toast()), await toast());
    await settled();

    await go(a);
    check("the first scene has the plan", (await els()).length === 2, `${(await els()).length} pieces`);
    check("…its camera loose from any shot", (await els()).filter((e) => e.kind === "camera").every((e) => !e.shot), "a shot came too");

    // ---- Copy From over a drawn plan: Add on Top, then Replace -------------------
    await js(`document.querySelector('[data-pcopymenu]').click()`); await wait(200);
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /^\\s*\\d/.test(x.textContent)).click()`); await wait(200);
    const ask2 = await js(`(document.querySelector('.planmenu')||{innerText:''}).innerText.replace(/\\s+/g, ' ')`);
    check("Copy From over a drawn plan asks first", /Add on Top/.test(ask2) && /Replace/.test(ask2), ask2);
    await shot("copy-from-ask.png");
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /Add on Top/.test(x.textContent)).click()`); await wait(300);
    check("Add on Top keeps what was there", (await els()).length === 4, `${(await els()).length} pieces`);
    await plan(); await key("z", { meta: true }); await wait(200);
    check("…and Undo takes the copy back", (await els()).length === 2, `${(await els()).length} pieces`);
    await settled();

    // ---- Send to Scene: just the camera -----------------------------------------
    await go(home);
    const cam = (await els()).find((e) => e.kind === "camera");
    const [cx, cy] = await at(cam.x, cam.y);
    await click(cx, cy);
    // Send To is in More now (design/26): the bar keeps what the piece is and what to do.
    await js(`document.querySelector('[data-pa=more]').click()`); await wait(150);
    const sendIt = `[...document.querySelectorAll('.planmenu button')].find((x) => /^Send To/.test(x.textContent.trim()))`;
    check("a picked piece offers Send To in More", Boolean(await js(`!!(${sendIt})`)), "not in More");
    await js(`(${sendIt}).click()`); await wait(200);
    await js(`document.querySelector('[data-pcopyto="${b}"]').click()`); await wait(100);
    await shot("send-to-scene.png");
    await js(`document.querySelector('[data-pcopygo]').click()`); await wait(300);
    await settled();

    // ---- read again: the server kept it all --------------------------------------
    await open();
    await go(a);
    check("read again, the first scene keeps its copy", (await els()).length === 2, `${(await els()).length} pieces`);
    await go(b);
    const bs = await els();
    check("read again, the second has the plan and the sent camera", bs.length === 3 && bs.filter((e) => e.kind === "camera").length === 2, `${bs.length} pieces`);

    // ---- a loose plan: made, drawn on, copied out, renamed, kept, deleted --------
    await js(`document.querySelector('[data-pnewplan]').click()`); await wait(500);
    const planId = await scene();
    check("+ makes a plan and opens it", !(await rowsOf()).slice(0, 0).length && !all.includes(planId) && /Plan 1/.test(await js(`document.querySelector('.planhead h1').textContent`)), await js(`document.querySelector('.planhead h1').textContent`));
    await P(`shotlisterPlan.edit({ op: "add", els: [{ kind: "wall", x: 0, y: 0, x2: 4, y2: 0 }, { kind: "camera", x: 1, y: 1, new_shot: true }] })`);
    check("a camera on a plan stands for no shot", (await els()).filter((e) => e.kind === "camera").every((e) => !e.shot), "it got one");
    await settled();
    await shot("plan-new.png");
    await js(`document.querySelector('[data-pcopymenu]').click()`); await wait(200);
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /Copy To/.test(x.textContent)).click()`); await wait(200);
    await js(`document.querySelector('[data-pcopyto="${a}"]').click()`); await wait(100);
    await js(`document.querySelector('[data-pcopygo]').click()`); await wait(300);
    await js(`document.querySelector('[data-pplanmenu]').click()`); await wait(200);
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /Rename/.test(x.textContent)).click()`); await wait(200);
    await js(`(() => { const i = document.querySelector('input.planrename'); i.value = "Warehouse Recce"; i.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" })); })()`); await wait(300);
    check("the Plan menu renames it", /Warehouse Recce/.test(await js(`document.querySelector('.planhead h1').textContent`)), await js(`document.querySelector('.planhead h1').textContent`));
    await settled();

    await open();
    await go(planId);
    check("read again, the plan keeps its name and pieces", /Warehouse Recce/.test(await js(`document.querySelector('.planhead h1').textContent`)) && (await els()).length === 2, `${await js(`document.querySelector('.planhead h1').textContent`)} · ${(await els()).length}`);
    await shot("plan-kept.png");
    await go(a);
    check("…and the scene it was copied to has them on top", (await els()).length === 4, `${(await els()).length} pieces`);

    await go(planId);
    await js(`document.querySelector('[data-pplanmenu]').click()`); await wait(200);
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /Delete/.test(x.textContent)).click()`); await wait(200);
    const warn = await js(`document.querySelector('.planmenu').innerText.replace(/\\s+/g, ' ')`);
    check("Delete says what goes with it", /2 pieces on it go with it/.test(warn), warn);
    await js(`[...document.querySelectorAll('.planmenu button')].find((x) => /Delete/.test(x.textContent)).click()`); await wait(300);
    await settled();
    await open();
    check("read again, the plan is gone", !(await rowsOf()).includes(planId), JSON.stringify(await rowsOf()));
    check("nothing on the page threw", thrown.length === 0, thrown.join(" | "));
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
