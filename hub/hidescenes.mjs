#!/usr/bin/env -S node --experimental-websocket
/**
 * **Hide from Diagrams, on the portal** (his ask, 2026-10-17: *"manually hide
 * scenes in the diagram bar"*). A copy of the Daybreak fixture is seeded into
 * a throwaway bucket and the Diagrams page is opened as its owner in a
 * headless browser: right-click a scene row, Hide from Diagrams; it leaves the
 * list and the grey "1 Hidden" line counts it; the Shot List still has every
 * scene; reload and it is still hidden (the film holds it, not the browser);
 * the line lists it again, dim, with Show; ⋯ and ⌘-click for several; the
 * scene open always stays; a viewer simply does not see it.
 *
 *     hub/hidescenes.mjs
 *
 * HUB_PORT and DEBUG_PORT pick its hub and browser; photographs land in /tmp,
 * or wherever SHOTS says. Builds the browser half first (`build.sh`).
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, readdirSync, cpSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a00b57e8790941866a989900000000";
const PORT = Number(process.env.HUB_PORT || 8811);
const DEBUG = Number(process.env.DEBUG_PORT || 9371);
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => { if (good) { pass += 1; say(`  ${what.padEnd(64)} PASS`); } else { fail += 1; say(`  ${what.padEnd(64)} FAIL — ${why}`); } };

let WS;
try { ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js"))); } catch { say("`ws` is not in hub/node_modules"); process.exit(1); }

if (!process.env.SKIP_BUILD) {
  say("Building the browser half…");
  if (spawnSync(join(HERE, "build.sh"), { stdio: "ignore" }).status !== 0) { say("the browser half would not build"); process.exit(1); }
}

// ---- the film: Daybreak, a scratch copy -------------------------------------
const work = mkdtempSync(join(tmpdir(), "hidescenes-"));
const fixture = join(work, "Daybreak.shotlist");
cpSync(join(HERE, "../studio/fixtures/Daybreak.shotlist"), fixture, { recursive: true });
const ffi = join(HERE, "../ffi");
spawnSync("cargo", ["build", "--quiet", "--example", "run_commands"], { cwd: ffi, stdio: "ignore" });
const runner = join(ffi, "target/debug/examples/run_commands");
const run = (lines) => spawnSync(runner, [fixture], { input: lines.join("\n") + "\n" }).stdout.toString().trim().split("\n");
const first = JSON.parse(run(["view"])[0]);
const s34 = first.scenes.find((s) => s.number === "34");
const others = first.scenes.filter((s) => !s.archived && s.id !== s34.id);
if (!s34 || others.length < 3) { say("Daybreak is not as expected"); process.exit(1); }
const [a, b, c] = others;
// Something drawn on 34 (the one open) and on `a`; `b` and `c` are undrawn.
const wall = JSON.stringify({ op: "add", els: [{ kind: "wall", x: 0, y: 0, x2: 5, y2: 0 }] });
run([`diagramedit\t${s34.id}\t${wall}`, `diagramedit\t${a.id}\t${wall}`]);
const view = JSON.parse(run(["view"])[0]);
const scenes = view.scenes.filter((s) => !s.archived);

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const put = (key, file) => spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  put(`p/${FILM}/manifest.json`, join(fixture, "manifest.json"));
  for (const name of readdirSync(join(fixture, "changes"))) if (name.endsWith(".log")) put(`p/${FILM}/logs/${name}`, join(fixture, "changes", name));
}

async function browser(go) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1400,900", "about:blank"], { stdio: "ignore" });
  try {
    let targets = null;
    for (let i = 0; i < 80 && !targets; i++) { await wait(150); try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch {} }
    if (!targets) throw new Error("the browser never answered");
    const ws = new WS(targets.find((t) => t.type === "page").webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
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
    await ask("Page.enable"); await ask("Runtime.enable");
    await ask("Emulation.setDeviceMetricsOverride", { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
    return await go(ask, thrown).finally(() => ws.close());
  } finally { proc.kill(); }
}

const state = mkdtempSync(join(tmpdir(), "hidescenes-state-"));
seed(state);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });
try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) { await wait(1000); try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch {} }
  if (!up) { say("the hub would not start"); process.exit(1); }
  await browser(async (ask, thrown) => {
    const js = async (expression) => (await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;
    const shot = async (name) => { const g = await ask("Page.captureScreenshot", { format: "png" }); writeFileSync(join(shots, name), Buffer.from(g.result.data, "base64")); say(`    → ${join(shots, name)}`); };
    const open = async (edit) => {
      await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/diagrams?as=owner@example.com` });
      for (let i = 0; i < 40; i++) { await wait(250); if (await js(`!!(window.shotlisterPlan && (document.querySelector('.planpic > svg') || document.querySelector('[data-pedit]')))`)) break; }
      await wait(400);
      if (edit) { await js(`(document.querySelector('[data-pedit]:not(.on)') || { click() {} }).click()`); await wait(500); }
      await js(`(document.querySelector('[data-pick=plan][data-id="${s34.id}"]') || { click() {} }).click()`); await wait(700);
    };
    const rowsN = () => js(`document.querySelectorAll('[data-pick=plan]').length`);
    const has = (id) => js(`!!document.querySelector('[data-pick=plan][data-id="${id}"]')`);
    const line = async () => ((await js(`(document.querySelector('[data-pshowempty]') || {}).textContent || ''`)) || "").trim();
    const menuItems = async () => JSON.parse((await js(`JSON.stringify([...document.querySelectorAll('.planmenu button')].map((x) => x.textContent.trim()))`)) || "[]");
    const rightClick = (id) => js(`(() => { const r = document.querySelector('[data-pick=plan][data-id="${id}"]'); const b = r.getBoundingClientRect(); r.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: b.left + 30, clientY: b.top + 10 })); })()`);
    const choose = async (word) => { await js(`[...document.querySelectorAll('.planmenu button')].find((x) => x.textContent.trim() === ${JSON.stringify(word)}).click()`); await wait(700); };
    const flushed = async () => { for (let i = 0; i < 30; i++) { if ((await js(`shotlisterPlan.state().pending`)) === 0) break; await wait(250); } await wait(500); };
    const shotListScenes = async () => {
      await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/shotlist?as=owner@example.com` });
      await wait(2500);
      return js(`document.querySelectorAll('.scene-row, [data-scene]').length`);
    };

    const shotsBefore = await shotListScenes();
    await open(true);
    const total = await rowsN();
    check("an owner's Edit lists every scene", total >= scenes.length, `${total}`);
    check("no \"Hidden\" line while nothing is hidden", (await line()) === "", await line());

    await rightClick(a.id); await wait(300);
    const items = await menuItems();
    check("right-click on a scene offers Hide from Diagrams", items.includes("Hide from Diagrams"), items.join(" / "));
    await shot("hidescenes-menu.png");
    await choose("Hide from Diagrams");
    check("…the scene leaves the list", !(await has(a.id)) && (await rowsN()) === total - 1, `${await rowsN()} of ${total}`);
    check("…and the grey line counts it", (await line()) === "1 Hidden", await line());
    check("…other scenes stay", Boolean(await has(b.id)) && Boolean(await has(c.id)), "gone");
    await flushed();

    // The film holds it: a fresh page, a fresh read.
    await open(true);
    check("after a reload it is still hidden (the film holds it, not the browser)", !(await has(a.id)) && (await line()) === "1 Hidden", `${await has(a.id)} "${await line()}"`);
    check("the Shot List still has every scene", (await shotListScenes()) === shotsBefore, `${await shotListScenes()} vs ${shotsBefore}`);
    await open(true);

    // The line lists it again, dim, with Show.
    await js(`document.querySelector('[data-pshowempty]').click()`); await wait(600);
    check("the line lists it again", Boolean(await has(a.id)) && (await rowsN()) === total && (await line()) === "Hide 1", `${await rowsN()} "${await line()}"`);
    check("…dim", Boolean(await js(`document.querySelector('[data-pick=plan][data-id="${a.id}"]').classList.contains('out')`)), "not dim");
    await shot("hidescenes-shown.png");
    await rightClick(a.id); await wait(300);
    const hid = await menuItems();
    check("…its menu says Show", hid.length === 1 && hid[0] === "Show", hid.join(" / "));
    await choose("Show");
    check("Show puts it back for good, and the line goes", Boolean(await has(a.id)) && (await line()) === "", `"${await line()}"`);
    await flushed();
    await open(true);
    check("…also after a reload", Boolean(await has(a.id)) && (await line()) === "", `"${await line()}"`);

    // ⋯ and several at once.
    const dots = await js(`!!document.querySelector('[data-pick=plan][data-id="${a.id}"] [data-pdscenemenu]')`);
    check("each scene row has a ⋯", Boolean(dots), "none");
    await js(`document.querySelector('[data-pick=plan][data-id="${a.id}"]').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, ctrlKey: true }))`);
    await js(`document.querySelector('[data-pick=plan][data-id="${b.id}"]').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, ctrlKey: true }))`);
    await wait(300);
    check("⌘/Ctrl-click marks scenes without opening them", (await js(`document.querySelectorAll('[data-pick=plan].mark').length`)) === 2 && (await js(`shotlisterPlan.scene()`)) !== a.id, "not marked");
    await js(`document.querySelector('[data-pick=plan][data-id="${a.id}"] [data-pdscenemenu]').click()`); await wait(300);
    check("…⋯ offers Hide from Diagrams", (await menuItems()).includes("Hide from Diagrams"), (await menuItems()).join(" / "));
    await choose("Hide from Diagrams");
    check("…and hides both marked scenes", !(await has(a.id)) && !(await has(b.id)) && (await line()) === "2 Hidden", `"${await line()}"`);
    await shot("hidescenes-two.png");

    // Hide Empty and by hand together; the open scene stays.
    await js(`document.querySelector('[data-phideempty]').click()`); await wait(700);
    // a and b by hand; b and c are undrawn (b counted once).
    const together = scenes.filter((s) => s.id !== s34.id && (s.id === a.id || s.id === b.id || !(s.diagram > 0))).length;
    check("the line counts Hide Empty's and the hand-hidden together", (await line()) === `${together} Hidden`, `"${await line()}" vs ${together}`);
    check("the scene open always stays", Boolean(await has(await js(`shotlisterPlan.scene()`))), "gone");
    await js(`document.querySelector('[data-phideempty]').click()`); await wait(500);
    await js(`document.querySelector('[data-pshowempty]').click()`); await wait(500);
    await rightClick(b.id); await wait(300);
    await choose("Show");
    await rightClick(a.id); await wait(300);
    await choose("Show");
    await flushed();
    check("both Shown again", (await rowsN()) === total && (await line()) === "", `${await rowsN()} "${await line()}"`);
    check("no page errors", thrown.length === 0, thrown.slice(0, 2).join(" | "));
  });
} finally {
  hub.kill();
}
say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
