#!/usr/bin/env -S node --experimental-websocket
/**
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
const PORT = Number(process.env.HUB_PORT || 8797);
const DEBUG = Number(process.env.DEBUG_PORT || 9352);
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
    // The Camera button offers its choices first when the scene has no plan
    // yet (a new shot, one of the scene's, or a camera alone): New Shot.
    const camTool = async () => {
      await tool("camera"); await wait(200);
      if (/New Shot/.test(await menuText())) { await js(`[...document.querySelectorAll('.planmenu button')].find((b) => /^New Shot/.test(b.textContent.trim())).click()`); await wait(150); }
    };
    // Select All takes the layer being worked in; the other is drawn back and
    // clicked through. So each layer is cleared in turn.
    const clear = async () => {
      for (const k of ["set", "plot"]) { await layerTo(k); await plan(); await key("a", { meta: true }); await key("Delete"); await wait(500); }
      await wait(1000); await open(); await plan();
    };
    // Details is shut until asked for, here as on the Mac: its fields (the
    // focal slider, a marker's lock, Fixture, Kind) need its tab opened.
    // While it is open the picked bar steps aside (Back to Paper, Batch 2), so
    // `barBack` goes back to the Shots tab before anything reads the bar.
    const details = async () => { await js(`document.querySelector('[data-ptab=details]').click()`); await wait(250); };
    const barBack = async () => { await js(`document.querySelector('[data-ptab=shots]').click()`); await wait(250); };
    const settled = async () => { for (let i = 0; i < 40; i++) { const s = await P(`shotlisterPlan.state()`); if (s && !s.pending) break; await wait(150); } await wait(900); };

    // ---- looking first: the plan to read, a camera says its shot -------------
    edits = false;
    await open();
    check("the Diagrams page opens to look at, with Edit", await js(`document.querySelectorAll('[data-ptool]').length === 0 && Boolean(document.querySelector('[data-pedit]'))`), "tools out, or no Edit");
    edits = true;
    await open();
    // The tools it offers are the Mac's: seven named ones for the layer it
    // opens in (Plot) and the rest under More, then the Set layer's own. The
    // exact set is checked, not a count, so a tool that goes missing or turns
    // up by mistake is named. (The Mac's More under Plot has no Cable.)
    const toolSet = async () => (await P(`[...document.querySelectorAll('[data-ptool]')].map((b) => b.dataset.ptool).sort()`)) || [];
    const layerTo = async (k) => { await js(`document.querySelector('[data-player=${k}]').click()`); await wait(300); };
    const same = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
    const plotTools = ["select", "light", "frame", "camera", "text", "arrow", "pen", "connector", "measure", "track", "cast", "cable", "hand"];
    const setTools = ["select", "wall", "door", "window", "road", "set", "cast", "picture", "text", "arrow", "shape", "hand"];
    const named = (await P(`[...document.querySelectorAll('.plantools > .ptool[data-ptool]')].map((b) => b.dataset.ptool)`)) || [];
    check("the Diagrams page opens in Plot with its tools: seven named, the rest under More", same(await toolSet(), plotTools) && same(named, plotTools.slice(0, 7)), `${(await toolSet()).join(",")} / named ${named.join(",")}`);
    await layerTo("set");
    const setNamed = (await P(`[...document.querySelectorAll('.plantools > .ptool[data-ptool]')].map((b) => b.dataset.ptool)`)) || [];
    check("…and Set has its own: Wall, Door, Window, Street, Piece, Cast, Trace, Words, Arrow", same(await toolSet(), setTools) && same(setNamed, setTools.slice(0, 10).filter((t) => t !== "shape")), `${(await toolSet()).join(",")} / named ${setNamed.join(",")}`);

    // ---- a wall, one corner at a time ---------------------------------------
    // The Wall tool lives in Set: the page opens in Plot, so Set first.
    await layerTo("set");
    await plan();
    await tool("wall");
    await click(450, 350); await click(800, 350); await click(800, 650);
    await mouse("mouseMoved", 470, 640); await wait(250);
    check("the next stretch follows the pointer with its length", Boolean(await js(`(document.querySelector('.planread')||{}).textContent`)), "no readout");
    await shot("diagram-wall-drawing.png");
    await click(450, 650); await click(450, 351);
    let w = (await els()).filter((e) => e.kind === "wall");
    check("clicked corners make one wall", w.length === 1 && (w[0].points || []).length === 4, JSON.stringify(w.map((e) => e.points)));
    check("a click on the first corner closes the room", w[0] && w[0].closed === true, "open");
    check("and the tool goes back to Select", (await P(`shotlisterPlan.state()`)).tool === "select", "still drawing");

    // ---- its handles ---------------------------------------------------------
    const mid = await at((w[0].points[0][0] + w[0].points[1][0]) / 2, w[0].points[0][1]);
    await click(mid[0], mid[1]);
    let hs = await handles();
    // No box round a single line (his note, 2026-10-01): its corners and +s only.
    check("a picked wall has a square on every corner, a + on every side, and no box", ["wc0", "wc3", "add0", "add3"].every((h) => hs.some((x) => x.h === h)) && !hs.some((x) => x.h === "boxturn"), hs.map((x) => x.h).join(" "));
    await shot("diagram-wall-picked.png");
    const add = hs.find((x) => x.h === "add0");
    await drag(add.x, add.y, add.x, add.y - 60);
    w = (await els()).filter((e) => e.kind === "wall");
    check("+ adds a corner and drags it out", (w[0].points || []).length === 5, `${(w[0].points || []).length} corners`);
    check("adding and dragging is one step back", (await P(`shotlisterPlan.state()`)).undo === "Add Corner", (await P(`shotlisterPlan.state()`)).undo);
    hs = await handles();
    const c2 = hs.find((x) => x.h === "wc2");
    await click(c2.x, c2.y);
    const bar = await barText();
    await js(`document.querySelector('[data-pa=more]').click()`); await wait(150);
    const cornerMore = await menuText();
    // (Curve is Round on the bar now, with Smooth beside it, 2026-10-09.)
    check("a picked corner offers Break, Smooth and Round on the bar, and Delete Corner in More", /Break/.test(bar) && /Smooth/.test(bar) && /Round/.test(bar) && !/Delete Corner/.test(bar) && /Delete Corner/.test(cornerMore), `${bar} / ${cornerMore}`);
    await plan(); await key("Escape");
    await js(`document.querySelector('[data-pa=curve]').click()`); await wait(200);
    check("Round rounds the corner", JSON.stringify((await els()).find((e) => e.kind === "wall").round) === "[2]", "not round");
    await js(`[...document.querySelectorAll('[data-pthick]')][4].click()`); await wait(200);
    check("the thickness pictures set Very Thick (12 in)", Math.abs((await els()).find((e) => e.kind === "wall").thick - 0.3048) < 1e-6, "not 12 in");
    await shot("diagram-wall-corner.png");
    hs = await handles();
    const c3 = hs.find((x) => x.h === "wc3");
    await click(c3.x, c3.y);
    await js(`document.querySelector('[data-pa=break]').click()`); await wait(200);
    w = (await els()).filter((e) => e.kind === "wall");
    check("Break opens the room at that corner", w.length === 1 && !w[0].closed, JSON.stringify(w.map((e) => e.closed)));
    await plan();
    await key("z", { meta: true }); await wait(150);
    check("Undo says what it took back", /Undid Break/.test(await js(`document.querySelector('.plantoast').textContent`)), await js(`document.querySelector('.plantoast').textContent`));
    check("and the room is closed again", (await els()).find((e) => e.kind === "wall").closed === true, "still open");
    await settled();

    // ---- kept by the server --------------------------------------------------
    await open();
    w = (await els()).filter((e) => e.kind === "wall");
    check("read again, the film holds the same wall", w.length === 1 && w[0].closed && (w[0].points || []).length === 5 && Math.abs(w[0].thick - 0.3048) < 1e-6, JSON.stringify(w));

    // ---- ⇧ draws a room -------------------------------------------------------
    await clear();
    await layerTo("set");
    await tool("wall");
    await drag(420, 300, 720, 600, { shift: true });
    w = (await els()).filter((e) => e.kind === "wall");
    check("⇧-drag with the Wall tool draws one closed room", w.length === 1 && w[0].closed && w[0].points.length === 4, JSON.stringify(w.map((e) => ({ closed: e.closed, points: e.points }))));

    // ---- turning ----------------------------------------------------------------
    // The Camera tool is Plot's: the room stays, drawn back.
    await layerTo("plot");
    await camTool();
    await click(560, 760);
    let cam = (await els()).find((e) => e.kind === "camera");
    const [cx, cy] = await at(cam.x, cam.y);
    const knob = (await handles()).find((x) => x.h === "turn");
    check("a camera's knob stands in front of it", knob && knob.x > cx + 10 && Math.abs(knob.y - cy) < 4, JSON.stringify({ knob, cx, cy }));
    await drag(knob.x, knob.y, cx + 2, cy - 120);
    cam = (await els()).find((e) => e.kind === "camera");
    check("dragged up, it faces up", Math.round(cam.rot) === 270, `${cam.rot}°`);
    await plan();
    await key("ArrowRight", { alt: true }); await key("ArrowRight", { alt: true });
    cam = (await els()).find((e) => e.kind === "camera");
    check("⌥→ turns it 5° at a time with Snap on", Math.round(cam.rot) === 280, `${cam.rot}°`);
    // ---- no steps (his ruling, 2026-10-03: no moves or beats) -----------------
    // Add Turn, Add Move, a step's knob and ring and its Rotation in Details
    // were taken out of the Mac's Diagram on purpose, and the portal's with
    // it: a camera's bar offers no + Move or + Turn, and its plan carries no
    // steps. (The checks that pressed them went with them.)
    check("a camera offers no + Move or + Turn, and holds no steps", await js(`!document.querySelector('[data-pa=addmove]') && !document.querySelector('[data-pa=addturn]')`) && !((await els()).find((e) => e.kind === "camera").steps || []).length, "a step button, or steps on the camera");

    // ---- a camera is its shot: Lens off the film's list, a zoom's slider ------
    // His design, 2026-10-01: the Lens is the shot's, and a zoom gets a focal
    // length slider whose setting is the shot's too.
    await P(`shotlisterPlan.edit({ op: "camera_shot", id: ${JSON.stringify((await els()).find((e) => e.kind === "camera").id)}, set: { lens: "24-70mm" } })`); await settled();
    let optic = (await P(`shotlisterPlan.cams()`))[0] || {};
    check("a zoom on the shot gives the camera its range", JSON.stringify(optic.zoom) === "[24,70]" && optic.focal === 24, JSON.stringify(optic));
    await details();
    const slid = await js(`(() => { const r = document.querySelector('[data-pfocal]'); if (!r) return "no slider"; r.value = "50"; r.dispatchEvent(new Event("input", { bubbles: true })); r.dispatchEvent(new Event("change", { bubbles: true })); return "ok"; })()`); await settled();
    optic = (await P(`shotlisterPlan.cams()`))[0] || {};
    check("…and its slider sets the shot's focal length", slid === "ok" && optic.focal === 50, `${slid} ${JSON.stringify(optic)}`);
    const viewSays = await js(`(() => { const d = [...document.querySelectorAll('.pf')].find((x) => x.firstElementChild && x.firstElementChild.textContent === 'View'); return d ? d.textContent : ''; })()`);
    const want50 = (2 * Math.atan(24.89 / 100) * 180 / Math.PI).toFixed(1);   // a 50 on Super 35
    check("…and the View follows it", viewSays.includes(`${want50}°`), `${viewSays} (want ${want50}°)`);
    await barBack();
    const barSays = await js(`[...document.querySelectorAll('[data-pa=lens],[data-pa=focal]')].map((b) => b.innerText.replace(/\\s+/g,' ')).join("|")`);
    check("the bar says the lens (Lens 24-70mm) and where it is set (Focal 50mm)", /Lens 24-70mm/.test(barSays) && /Focal 50mm/.test(barSays), barSays);
    await js(`document.querySelector('[data-pa=focal]').click()`); await wait(200);
    const focalPop = await js(`(document.querySelector('.planpop') || {}).innerText || ''`);
    await shot("diagram-focal.png");
    check("Focal opens a slider: the zoom's short end, the long end and where it is set", /24mm/.test(focalPop) && /70mm/.test(focalPop) && /50mm/.test(focalPop), focalPop.replace(/\s+/g, " "));
    const nudged = await js(`(() => { const r = document.querySelector('[data-pfocalpop]'); if (!r) return "no slider"; r.value = "60"; r.dispatchEvent(new Event("input", { bubbles: true })); const live = document.querySelector('.ppnow').textContent; r.dispatchEvent(new Event("change", { bubbles: true })); return live; })()`); await settled();
    optic = (await P(`shotlisterPlan.cams()`))[0] || {};
    check("…dragged, it reads 60mm and letting go sets the shot's focal length", nudged === "60mm" && optic.focal === 60, `${nudged} ${JSON.stringify(optic)}`);
    await key("Escape");
    await shot("diagram-zoom.png");

    // ---- the Ruler: laid from the camera, markers that lock (2026-10-01) -------
    {
      const c0 = (await els()).find((e) => e.kind === "camera");
      const [rx, ry] = await at(c0.x, c0.y);
      await tool("measure");
      await drag(rx, ry, rx + 260, ry - 40);
      let ruler = (await els()).find((e) => e.kind === "measure");
      check("a ruler laid from the camera locks its first marker to it", ruler && (ruler.pins || [])[0] === c0.id, JSON.stringify(ruler && ruler.pins));
      const hs = (await handles()).map((h) => h.h);
      check("a ruler picked alone wears its markers and no box", hs.includes("wc0") && hs.includes("wc1") && !hs.includes("boxturn"), hs.join(","));
      await details();
      const locked = await js(`(() => { const s = document.querySelector('[data-pf="pin1"]'); if (!s || s.options.length < 2) return "no picker"; s.selectedIndex = 1; s.dispatchEvent(new Event("change", { bubbles: true })); return s.value; })()`); await settled();
      ruler = (await els()).find((e) => e.kind === "measure");
      check("…and its other marker locks to what the panel picks", locked && ruler && (ruler.pins || [])[1] === locked, `${locked} ${JSON.stringify(ruler && ruler.pins)}`);
      await barBack();
      // A picked marker's bar says what it is locked to; Unlock is in More.
      const mh = (await handles()).find((h) => h.h === "wc1");
      await click(mh.x, mh.y);
      const rbar = await barText();
      check("a picked marker's bar says what it is locked to", /Locked to/.test(rbar), rbar);
      await js(`document.querySelector('[data-pa=more]').click()`); await wait(150);
      const rmore = await menuText();
      check("…and its More offers Unlock", /Unlock/.test(rmore), rmore);
      await js(`[...document.querySelectorAll('.planmenu button')].find((b) => /^Unlock/.test(b.textContent.trim())).click()`); await settled();
      ruler = (await els()).find((e) => e.kind === "measure");
      check("…and Unlock lets that marker go", ruler && (ruler.pins || [])[1] === "" && (ruler.pins || [])[0] === c0.id, JSON.stringify(ruler && ruler.pins));
      await shot("diagram-ruler.png");
      await plan(); await key("z", { meta: true }); await settled();
      await plan(); await key("z", { meta: true }); await settled();
      await plan(); await key("z", { meta: true }); await settled();
    }
    // The wall is Set's: Plot draws it back and clicks straight through it.
    await layerTo("set");
    w = (await els()).find((e) => e.kind === "wall");
    const side = await at((w.points[0][0] + w.points[1][0]) / 2, w.points[0][1]);
    await click(side[0], side[1]);
    // A wall alone has no box to turn by now; ⌥→ turns it 5° at a time.
    await plan(); await key("ArrowRight", { alt: true }); await settled();
    w = (await els()).find((e) => e.kind === "wall");
    const ang = (Math.atan2(w.points[1][1] - w.points[0][1], w.points[1][0] - w.points[0][0]) * 180) / Math.PI;
    check("a wall turns with ⌥→, 5° at a time", Math.abs(ang) > 1 && Math.abs(ang / 5 - Math.round(ang / 5)) < 1e-3, `${ang}°`);
    await shot("diagram-wall-turned.png");

    // ---- exact numbers ---------------------------------------------------------
    await clear();
    await key("m");
    await drag(400, 400, 731, 417, { shift: true });
    const m = (await els()).find((e) => e.kind === "measure");
    const step = (await P(`shotlisterPlan.state()`)).step;
    const len = m ? Math.hypot(m.x2 - m.x, m.y2 - m.y) : 0;
    check("⇧ drops a line onto its axis, a whole number of steps long", m && Math.abs(m.y - m.y2) < 1e-9 && Math.abs(len / step - Math.round(len / step)) < 1e-6, JSON.stringify(m && [m.x, m.y, m.x2, m.y2]));

    // ---- the Grip tool and the library ----------------------------------------
    await plan();
    await key("q");
    const chips = await js(`[...document.querySelectorAll('.plibchips .ppill')].map(b => b.textContent).join('|')`);
    check("Q opens the Grip library in its sections", (await P(`shotlisterPlan.state()`)).tool === "grip" && /Frames & Rags/.test(chips) && !/Flags & Nets/.test(chips), chips);
    await shot("diagram-grip-library.png");
    await js(`(() => { const f = document.querySelector('.plibfind'); f.value = 'floppy'; f.dispatchEvent(new Event('input')); })()`); await wait(150);
    check("search finds a piece by what a crew calls it", (await js(`document.querySelectorAll('.plibrow').length`)) > 0, "nothing for floppy");
    // The Light tool lays a mark now (no library of fixtures under it); a click puts one down facing up.
    await plan(); await key("Escape"); await key("l");
    await click(450, 600);
    const lamp = (await els()).find((e) => e.kind === "light");
    check("a Light mark lands facing up the screen", lamp && Math.round(lamp.rot) === 270, lamp && `${lamp.rot}°`);

    // ---- Return types its Note over on the plan (the Mac's: a light's Name is typed from the bar) ----
    await plan(); await key("Escape");
    const [lx, ly] = await at(lamp.x, lamp.y);
    await click(lx, ly);
    await key("Enter");
    const boxOpen = await js(`!!document.querySelector('.plantype[aria-label=Note]')`);
    await shot("diagram-rename.png");
    await js(`document.querySelector('.plantype').value = 'Key Light'`);
    await js(`document.querySelector('.plantype').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))`); await wait(200);
    check("Return types a light's Note over on the plan", boxOpen && (await els()).find((e) => e.kind === "light").label === "Key Light", `${boxOpen} ${JSON.stringify((await els()).filter((e) => e.kind === "light").map((e) => e.label))}`);

    // ---- a lamp draws no beam (SL-1334; Ref 1506), and can be faded (Ref 1505) --
    // Batch 3 (`cfa9daee`, 2026-10-04) gave a lamp Opacity after all, in Details
    // and in More (plot.mjs checks More); this used to check it was offered
    // none, but with Details shut that check could not fail.
    await details();
    const hasFade = await js(`Boolean(document.querySelector('[data-pf="opacity"]'))`);
    const noBeam = await js(`!document.querySelector('[data-pf="beam"]') && !document.querySelector('[data-pf="beam_on"]')`);
    check("a picked lamp is offered Opacity (Ref 1505) and no Beam (Ref 1506)", hasFade && noBeam, `opacity field ${hasFade}, no beam field ${noBeam}`);
    check("…and the plan draws it no beam", (await js(`document.querySelectorAll('[data-part="beam"]').length`)) === 0, "a beam is drawn");
    await barBack();

    // ---- Swap: the toolbar's library, opened by right-click ---------------------
    // His ask, 2026-10-02: the Fixture list was too long; it should be the
    // searchable library. A Light mark has no fixture ("assign them what light
    // they are later", 2026-10-03) and Details no longer carries a Fixture
    // field for a lamp; a lamp that does stand for a unit — one from the
    // library, or an older plan's — is swapped from its right-click menu.
    await P(`shotlisterPlan.edit({ op: "add", els: [{ kind: "light", sym: "tungsten-fresnel-1k", x: 0.9, y: 2.4, rot: 270, label: "Key Light" }] })`); await settled();
    const lampWas = (await els()).find((e) => e.kind === "light" && e.sym === "tungsten-fresnel-1k");
    const [rx, ry] = await at(lampWas.x, lampWas.y);
    await click(rx, ry);
    await rightClick(rx, ry);
    const rmenu = await menuText();
    check("a right-click on a lamp offers Swap… among the keys", /Swap…/.test(rmenu) && /Duplicate/.test(rmenu) && /⌘D/.test(rmenu), rmenu);
    await js(`[...document.querySelectorAll('.planmenu button')].find((b) => /Swap…/.test(b.textContent)).click()`); await wait(250);
    const swapHead = await js(`(document.querySelector('.planfloat.lib .plibhead b') || {}).textContent || ''`);
    const swapNow = await js(`[...document.querySelectorAll('.plibglab')].map((n) => n.textContent).slice(0, 2).join('|')`);
    check("…Swap… opens the library, titled Swap Fixture, with Now on top", swapHead === "Swap Fixture" && swapNow.startsWith("Now"), `${swapHead} · ${swapNow}`);
    check("…and its foot says what a click does", /Click to swap · Esc to close/.test(await js(`document.querySelector('.planfloat.lib .plibfoot').textContent`)), "no foot");
    await shot("diagram-swap.png");
    check("…and it has a Maker filter", (await js(`document.querySelectorAll('.plibmaker option').length`)) > 2, "no makers");
    await js(`(() => { const f = document.querySelector('.plibfind'); f.value = 'm18'; f.dispatchEvent(new Event('input')); })()`); await wait(150);
    const m18 = await js(`[...document.querySelectorAll('.plibrow .ptname')].map((n) => n.textContent).join('|')`);
    check("typing m18 shows the Arri M18", /Arri M18/.test(m18), m18);
    await js(`(() => { const f = document.querySelector('.plibfind'); f.value = 'kino'; f.dispatchEvent(new Event('input')); })()`); await wait(150);
    const other = await js(`(() => { const r = [...document.querySelectorAll('.plibrow')].find((b) => b.dataset.psym !== ${JSON.stringify(lampWas.sym)}); if (!r) return ""; const s = r.dataset.psym; r.click(); return s; })()`); await settled();
    const lampNow = (await els()).find((e) => e.id === lampWas.id);
    check("clicking another light swaps it and keeps its place and name", other && lampNow && lampNow.sym === other && lampNow.sym !== lampWas.sym && lampNow.x === lampWas.x && lampNow.y === lampWas.y && lampNow.label === lampWas.label && lampNow.label === "Key Light", JSON.stringify({ was: lampWas.sym, other, now: lampNow && lampNow.sym, label: lampNow && lampNow.label }));
    await key("Escape");
    check("Escape closes the panel", !(await js(`!!document.querySelector('.planfloat.lib')`)), "still open");
    // ⌘L locks what is picked, and again lets it go.
    await plan(); await key("l", { meta: true }); await wait(200);
    const locked1 = ((await els()).find((e) => e.id === lampWas.id) || {}).locked === true;
    await key("l", { meta: true }); await wait(200);
    const locked2 = ((await els()).find((e) => e.id === lampWas.id) || {}).locked === true;
    check("⌘L locks the lamp, and ⌘L again lets it go", locked1 && !locked2, `${locked1} then ${locked2}`);
    // A grip piece's Kind is the Grip library, titled Swap Kind.
    await plan(); await key("Escape"); await key("q");
    await js(`(() => { const f = document.querySelector('.plibfind'); f.value = 'stand'; f.dispatchEvent(new Event('input')); })()`); await wait(150);
    await js(`[...document.querySelectorAll('.plibrow')].find((b) => b.dataset.psym !== 'frame').click()`);
    await click(650, 700); await settled();
    const grip = (await els()).find((e) => e.kind === "set");
    await details();
    await js(`document.querySelector('[data-pswap]').click()`); await wait(250);
    const kindHead = await js(`(document.querySelector('.planfloat.lib .plibhead b') || {}).textContent || ''`);
    check("a grip piece's Details Kind opens the library, titled Swap Kind", grip && kindHead === "Swap Kind", `${kindHead} · ${grip && grip.sym}`);
    const gripTo = await js(`(() => { const r = [...document.querySelectorAll('.plibrow')].find((b) => b.dataset.psym !== ${JSON.stringify(grip && grip.sym)}); if (!r) return ""; const s = r.dataset.psym; r.click(); return s; })()`); await settled();
    const gripNow = (await els()).find((e) => e.id === grip.id);
    check("…and a click swaps it and keeps its place", gripTo && gripNow && gripNow.sym === gripTo && gripNow.x === grip.x && gripNow.y === grip.y, JSON.stringify({ was: grip && grip.sym, gripTo, now: gripNow && gripNow.sym }));
    await key("Escape");

    // ---- a frame's bar ----------------------------------------------------------
    await barBack();
    // F puts a frame under the pointer, picked (the Mac's one-key adds).
    await mouse("mouseMoved", 780, 400); await wait(100);
    await plan(); await key("f"); await wait(300);
    const fbar = await barText();
    const fmat = await P(`(() => { const b = document.querySelector('.planfloat [data-pa=material]'); return b ? { label: b.getAttribute('aria-label'), swatch: !!b.querySelector('.pbsw'), text: b.innerText } : null; })()`);
    // (Frame Type and Grid left the bar with Back to Paper, as on the Mac.)
    check("a frame's bar: Size, Material (a swatch and its name), Note and Opacity", fmat && /^Material /.test(fmat.label) && fmat.swatch && fmat.text.trim() !== "" && /Size/.test(fbar) && /Note/.test(fbar) && /Opacity/.test(fbar) && !/Type/.test(fbar) && !/Grid/.test(fbar), `${JSON.stringify(fmat)} · ${fbar}`);
    await js(`document.querySelector('[data-pa=material]').click()`); await wait(150);
    check("Material opens the swatches", (await js(`document.querySelectorAll('.planmenu .pmsw').length`)) > 10, "no swatches");
    await shot("diagram-frame-material.png");
    await js(`[...document.querySelectorAll('.planmenu button')].find(b => b.textContent === 'Silk').click()`); await wait(200);
    let fr = (await els()).find((e) => e.kind === "light" && e.material);
    check("a swatch dresses the frame", fr && fr.material === "silk", fr ? fr.material : `${await js(`document.querySelector(".plantoast").textContent`)} / ${JSON.stringify(await P(`shotlisterPlan.picks()`))} / ${JSON.stringify((await els()).map((e) => e.id))}`);
    const tilt = (await handles()).find((x) => x.h === "tilt");
    if (tilt) await drag(tilt.x, tilt.y, tilt.x + 40, tilt.y + 40);
    fr = (await els()).find((e) => e.id === fr.id);
    check("its tilt knob stands it up in 5° steps", fr.tilt > 0 && fr.tilt % 5 === 0, `${fr.tilt}°`);
    // His note, 2026-10-01: standing, the two knobs sat on each other.
    const t2 = (await handles()).find((x) => x.h === "tilt");
    if (t2) await drag(t2.x, t2.y, t2.x + 400, t2.y);
    fr = (await els()).find((e) => e.id === fr.id);
    const fh = await handles(), ftk = fh.find((x) => x.h === "tilt"), frk = fh.find((x) => x.h === "turn");
    const gap = ftk && frk ? Math.hypot(ftk.x - frk.x, ftk.y - frk.y) : 0;
    check("standing, its turning and tilt knobs are far apart", fr.tilt === 90 && gap > 60, `${fr.tilt}°, ${Math.round(gap)} apart`);
    await shot("diagram-frame-standing.png");
    // Laid back to where it was, so what follows meets the plan it always has.
    await plan(); await key("z", { meta: true }); await settled();
    // Ref 1350: ⌘Z here brings the frame back under a new id. Said as its own
    // check, then found by what it is, so the rest of the run still runs.
    const back = (await els()).find((e) => e.id === fr.id);
    check("…⌘Z lays it back as the same piece", Boolean(back), "it came back under a new id");
    fr = back || (await els()).find((e) => e.sym === "frame");

    // ---- an arrow pinned at both ends; a camera's body ------------------------
    await mouse("mouseMoved", 600, 640); await wait(100);
    await plan(); await key("c"); await wait(300);
    cam = (await els()).filter((e) => e.kind === "camera").pop();
    const [fx, fy] = await at(fr.x, fr.y);
    const [kx, ky] = await at(cam.x, cam.y);
    await plan(); await key("a");
    await drag(fx, fy, kx, ky);
    const ar = (await els()).find((e) => e.kind === "arrow");
    check("an arrow drawn from one piece to another is pinned to both", ar && ar.start_on === fr.id && ar.end_on === cam.id, JSON.stringify(ar && [ar.start_on, ar.end_on]));
    await shot("diagram-arrow-pinned.png");
    await click(kx, ky);
    // No list of bodies any more (his ruling, 2026-10-01): the bar offers the
    // shot's Lens and Camera instead.
    const camBar = await js(`[...document.querySelectorAll('[data-pa]')].map((b) => b.getAttribute('data-pa')).join(",")`);
    check("a camera's bar has Lens and Camera, and no Body", /\blens\b/.test(camBar) && /\bcam\b/.test(camBar) && !/\bbody\b/.test(camBar), camBar);
    const camText = await barText();
    // (The bar names the Shot and takes a Note; + Move and + Turn went with the moves.)
    check("a camera's bar shows its Shot, Note, Camera and Lens values, and More, with no + Move or + Turn", /Shot/.test(camText) && /Note/.test(camText) && /Camera/.test(camText) && /Lens/.test(camText) && /More/.test(camText) && !/\+ Move|\+ Turn/.test(camText), camText);
    await shot("diagram-bar-camera.png");
    await js(`document.querySelector('[data-pa=more]').click()`); await wait(150);
    const camMore = await menuText();
    check("…and its More lists Duplicate, Lock, Hide and Delete", ["Duplicate", "Lock", "Hide", "Delete", "Details", "Frame on Plan"].every((w) => camMore.includes(w)), camMore);
    await shot("diagram-bar-more.png");
    await plan(); await key("Escape");
    // **Narrow, the bar folds and stays on its line** (design/26): the actions
    // go into More, and the bar never reaches over the zoom.
    // A zoom's bar carries the most (Focal too), so it is the one that has to fold at 700.
    await P(`shotlisterPlan.edit({ op: "camera_shot", id: ${JSON.stringify((await P(`shotlisterPlan.picks()`))[0])}, set: { lens: "24-70mm" } })`); await settled();
    await ask("Emulation.setDeviceMetricsOverride", { width: 700, height: 900, deviceScaleFactor: 1, mobile: false });
    await wait(700);
    const narrow = await P(`(() => { const f = document.querySelector('.planfloat'), r = f.getBoundingClientRect(), z = document.querySelector('.planzoom').getBoundingClientRect(), v = document.querySelector('.planvp').getBoundingClientRect(); return { text: f.innerText.replace(/\\s+/g, ' '), l: r.left - v.left, r: r.right - v.left, b: v.bottom - r.bottom, zl: z.left - v.left, zt: z.top - v.top, fold: shotlisterPlan.state().fold, vw: v.width }; })()`);
    await shot("diagram-bar-narrow.png");
    check("narrowed to 700px the bar folds: no Focal left in it", narrow && narrow.fold >= 1 && !/Focal/.test(narrow.text) && /More/.test(narrow.text), JSON.stringify(narrow));
    check("…and it stays on the foot, inside the plan and clear of the zoom", narrow && narrow.l >= 0 && narrow.r <= narrow.zl && narrow.b >= 0 && narrow.b < 40, JSON.stringify(narrow));
    await js(`document.querySelector('[data-pa=more]').click()`); await wait(150);
    const foldedMore = await menuText();
    check("…and what the bar had no room for is at the top of More", /^Note Camera .*Lens .*Focal/.test(foldedMore) && /Duplicate/.test(foldedMore), foldedMore);
    await plan(); await key("Escape");
    await ask("Emulation.setDeviceMetricsOverride", { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
    await wait(700);

    // ---- paste at the pointer ---------------------------------------------------
    await click(lx, ly);
    await key("c", { meta: true });
    await mouse("mouseMoved", 900, 300); await wait(100);
    await key("v", { meta: true }); await wait(200);
    const copy = (await els()).filter((e) => e.kind === "light" && !e.material).find((e) => e.id !== lamp.id);
    const [px, py] = copy ? await at(copy.x, copy.y) : [0, 0];
    check("paste lands at the pointer", copy && Math.hypot(px - 900, py - 300) < 0.35 * (await P(`shotlisterPlan.state()`)).k, `${Math.round(px)},${Math.round(py)}`);

    // ---- a locked floor is clicked straight through ---------------------------
    // The first piece on an empty plan lays the paper out round itself and
    // moves under the hand, so what is pressed on is found where the plan
    // says it now stands, not where it was drawn.
    await clear();
    await layerTo("set");
    await tool("shape");
    await drag(400, 300, 700, 560);
    await settled();
    const floor = (await els()).find((e) => e.kind === "shape");
    await plan(); await P(`shotlisterPlan.pick([${JSON.stringify(floor.id)}])`);
    await key("l", { meta: true }); await wait(200);
    await key("Escape");
    const [fx0, fy0] = await at(...(floor.at || [floor.x, floor.y]));
    await click(1000, 820);
    await click(fx0, fy0);
    check("a locked piece is clicked straight through", (await P(`shotlisterPlan.picks()`)).length === 0 && ((await els()).find((e) => e.kind === "shape") || {}).locked === true, JSON.stringify(await P(`shotlisterPlan.picks()`)));
    await settled();

    // ---- Backdrop: the paper dims for this viewer (it lives in View now) --------
    await js(`document.querySelector('[data-pview]').click()`); await wait(250);
    const hasRange = await js(`!!document.querySelector('[data-pvbackdrop]')`);
    const startAt = await js(`(document.querySelector('[data-pvbackdrop]') || {}).value`);
    await js(`(() => { const r = document.querySelector('[data-pvbackdrop]'); r.value = '0'; r.dispatchEvent(new Event('input')); r.dispatchEvent(new Event('change')); })()`); await wait(250);
    // (The paper is the sheet's own colour, `--dia-paper` on the plan; the desk round it, `.planvp`, keeps its grey.)
    const dim = await js(`[document.querySelector('.planpic').style.getPropertyValue('--dia-paper').trim(), getComputedStyle(document.querySelector('.planpic')).getPropertyValue('--dia-patch').trim()].join(' ')`);
    await shot("diagram-backdrop-dim.png");
    check("Backdrop dims the plan's paper for this viewer, and names keep a light patch", hasRange && /^#8c8d8e /i.test(dim) && /#E4E5E7/i.test(dim), dim);
    await js(`(() => { const r = document.querySelector('[data-pvbackdrop]'); r.value = '1'; r.dispatchEvent(new Event('input')); r.dispatchEvent(new Event('change')); })()`); await wait(250);
    const bright = await js(`document.querySelector('.planpic').style.getPropertyValue('--dia-paper').trim()`);
    check("…and brightens it to white at the other end (the Mac's 0 and 1; the Reset button is gone)", /^#ffffff$/i.test(bright), `${bright} (it started at ${startAt})`);
    await js(`document.querySelector('[data-pview]').click()`); await wait(200);

    // ---- a group is one thing; double-click goes into it ----------------------
    await clear();
    await layerTo("set");
    await tool("shape"); await drag(420, 300, 520, 380); await settled();
    await tool("shape"); await drag(700, 300, 800, 380);
    await settled();
    await plan(); await key("a", { meta: true }); await key("g", { meta: true }); await settled();
    await key("Escape");
    const [g1x, g1y] = await at(...((await els()).filter((e) => e.kind === "shape").sort((p, q) => p.x - q.x)[0].at));
    await click(g1x, g1y);
    const groupPick = await P(`shotlisterPlan.picks()`);
    check("a piece of a group, clicked, picks its group", groupPick.length === 2, JSON.stringify(groupPick));
    await wait(500); await key("Escape"); await wait(500);
    // Two presses close together, as a hand double-clicks.
    for (const n of [1, 2]) {
      await ask("Input.dispatchMouseEvent", { type: "mousePressed", x: g1x, y: g1y, button: "left", buttons: 1, clickCount: n });
      await ask("Input.dispatchMouseEvent", { type: "mouseReleased", x: g1x, y: g1y, button: "left", buttons: 0, clickCount: n });
    }
    await wait(250);
    check("…and a double-click picks that piece alone", (await P(`shotlisterPlan.picks()`)).length === 1, JSON.stringify(await P(`shotlisterPlan.picks()`)));

    // ---- moving, a piece lines up with another ---------------------------------
    await key("Escape"); await key("Escape");
    await plan(); await key("a", { meta: true }); await key("g", { meta: true, shift: true }); await settled();
    await key("Escape");
    {
      const shapes = (await els()).filter((e) => e.kind === "shape");
      const [a, b] = shapes.sort((p, q) => p.x - q.x);
      const [ax, ay] = await at(a.x, a.y);
      const [, by] = await at(b.x, b.y);
      // Dragged to land a few points off level with the other: pulled level.
      const want = by - ay + 3;
      await mouse("mouseMoved", ax, ay); await mouse("mousePressed", ax, ay);
      for (let i = 1; i <= 8; i++) { await mouse("mouseMoved", ax + 10 * i, ay + (want * i) / 8, { held: true }); await wait(16); }
      const lined = await js(`document.querySelectorAll('.planpic .planguide').length`);
      await mouse("mouseReleased", ax + 80, ay + want); await settled();
      const a2 = (await els()).find((e) => e.id === a.id) || {};
      check("moving, a piece is pulled level with another and a guide says so", lined > 0 && Math.abs(a2.y - b.y) < 1e-3, `guides ${lined}, Δy ${(a2.y - b.y).toFixed(4)}`);
    }

    // ---- ⌥-drag copies; looking, a camera says its shot ----------------------
    await layerTo("plot");
    await camTool();
    await click(1000, 380);
    await settled();
    const cams0 = (await els()).filter((e) => e.kind === "camera");
    const c0 = cams0[cams0.length - 1];
    const [c0x, c0y] = c0 ? await at(c0.x, c0.y) : [1000, 380];
    await drag(c0x, c0y, c0x + 160, c0y + 40, { alt: true });
    await settled();
    const cams1 = (await els()).filter((e) => e.kind === "camera");
    check("⌥-drag leaves the camera and puts a copy where it is let go", cams1.length === cams0.length + 1 && cams1.some((e) => c0 && e.id === c0.id && Math.abs(e.x - c0.x) < 1e-6), `${cams0.length} → ${cams1.length}`);
    // ---- Edit sets the shot's Size and Movement, off the film's lists ---------
    let sizeSet = "";
    {
      const cam = (await els()).find((e) => e.kind === "camera" && e.shot);
      if (cam) {
        const [cx, cy] = await at(cam.at[0], cam.at[1]);
        await key("Escape"); await wait(500);
        await click(cx, cy); await wait(200);
        await js(`document.querySelector('[data-ptab=details]').click()`); await wait(200);
        sizeSet = await js(`(() => { const s = document.querySelector('[data-pf=shot_size]'); if (!s) return ''; const o = [...s.options].find((x) => x.value && !x.selected); if (!o) return ''; s.value = o.value; s.dispatchEvent(new Event('change', { bubbles: true })); return o.value; })()`);
        await settled();
        await open();
      }
      check("Edit sets a camera's shot Size from the film's list", Boolean(sizeSet), "no Size field, or nothing on the list");
    }
    await js(`document.querySelector('[data-pedit].on').click()`); await wait(400);
    check("Done puts the tools away", await js(`document.querySelectorAll('[data-ptool]').length === 0 && Boolean(document.querySelector('[data-pedit]:not(.on)'))`), "tools still out");
    {
      // The camera that stands for a shot, tapped where the plan draws it.
      const cam = (await els()).find((e) => e.kind === "camera" && e.shot);
      const [cx, cy] = cam ? await at(cam.at[0], cam.at[1]) : [0, 0];
      await click(cx, cy);
      const card = await js(`(document.querySelector('.planfloat.look') || {}).innerText || ''`);
      const picked = await P(`shotlisterPlan.picks()`);
      await shot("diagram-look.png");
      check("looking, a camera tapped says its shot", Boolean(cam) && /^Shot /.test(card) && picked.length === 1 && picked[0] === cam.id, `card said: ${card.slice(0, 60)}`);
      check("…and says the Size set in Edit, kept by the film", !sizeSet || new RegExp(`Size\\s+${sizeSet.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`).test(card), `card said: ${card.slice(0, 120)}`);
      check("…and the Shots list has it picked", await js(`Boolean(document.querySelector('.pshot.on'))`), "nothing picked in Shots");
      // A beat later: two taps close together are a double, which zooms in.
      await wait(500);
      await click(cx, cy);
      check("…tapped again, the card goes", !(await js(`Boolean(document.querySelector('.planfloat.look'))`)), "card stayed");
    }
    check("the plan carries a scale bar", /\d/.test(await js(`document.querySelector('.planscale').innerText`)), "no scale bar");

    check("nothing on the page threw", thrown.length === 0, thrown.slice(0, 2).join(" / "));
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
