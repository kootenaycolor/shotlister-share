#!/usr/bin/env -S node --experimental-websocket
/**
 * **A scene's several diagrams, and Hide Empty, on the portal** (his ask,
 * 2026-10-17). A copy of the Daybreak fixture is given three diagrams on
 * scene 34 by the engine itself (`ffi/examples/run_commands`), seeded into a
 * throwaway bucket, and the Diagrams page is opened as its owner in a
 * headless browser: the tabs are there, in his order, with his names; a tab
 * opens its own diagram; Hide Empty takes the undrawn scenes off the list and
 * says how many.
 *
 *     hub/diagrammulti.mjs
 *
 * Its own hub on 8798 and its own browser on 9353; photographs land in /tmp,
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

// ---- the film: Daybreak, scene 34 with three diagrams -------------------------
const work = mkdtempSync(join(tmpdir(), "diagrammulti-"));
const fixture = join(work, "Daybreak.shotlist");
cpSync(join(HERE, "../studio/fixtures/Daybreak.shotlist"), fixture, { recursive: true });
const ffi = join(HERE, "../ffi");
spawnSync("cargo", ["build", "--quiet", "--example", "run_commands"], { cwd: ffi, stdio: "ignore" });
const runner = join(ffi, "target/debug/examples/run_commands");
const run = (lines) => spawnSync(runner, [fixture], { input: lines.join("\n") + "\n" }).stdout.toString().trim().split("\n");
const view = JSON.parse(run(["view"])[0]);
const s34 = view.scenes.find((s) => s.number === "34");
if (!s34) { say("no scene 34 in Daybreak"); process.exit(1); }
const wall = JSON.stringify({ op: "add", els: [{ kind: "wall", x: 0, y: 0, x2: 5, y2: 0 }, { kind: "wall", x: 5, y: 0, x2: 5, y2: 3 }] });
const made = run([
  `scenediagramadd\t${s34.id}\tReverse\t${s34.id}`,
  `scenediagramadd\t${s34.id}\t`,
]).map((l) => JSON.parse(l).id);
run([`diagramedit\t${made[1]}\t${wall}`]);
const expect = JSON.parse(run([`scenediagrams\t${s34.id}`])[0]).diagrams;
const undrawn = view.scenes.filter((s) => !s.archived && !(s.diagram > 0) && s.id !== s34.id).length;

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

const state = mkdtempSync(join(tmpdir(), "diagrammulti-state-"));
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
    await open(false);
    const tabs = await js(`JSON.stringify([...document.querySelectorAll('[data-pdtab]')].map((b) => [b.dataset.pdtab, b.textContent.trim(), b.classList.contains('on')]))`);
    const got = JSON.parse(tabs || "[]");
    check("scene 34 shows one tab a diagram, in his order, with his names", got.length === 3 && got.every((t, i) => t[0] === expect[i].id && t[1] === expect[i].title), tabs);
    check("…the first open", got[0] && got[0][2] && (await js(`shotlisterPlan.scene()`)) === expect[0].id, tabs);
    check("…an unnamed one wears its placeholder, set apart", Boolean(await js(`document.querySelector('[data-pdtab="${expect[2].id}"]').classList.contains('ph')`)) && expect[2].title === "Diagram 3", expect[2].title);
    await js(`document.querySelector('[data-pdtab="${expect[2].id}"]').click()`); await wait(900);
    check("a tab opens its own diagram", (await js(`shotlisterPlan.scene()`)) === expect[2].id && (await js(`shotlisterPlan.els().length`)) === 2, `${await js(`shotlisterPlan.scene()`)} / ${await js(`shotlisterPlan.els().length`)}`);
    check("…and the list still lights scene 34", Boolean(await js(`document.querySelector('[data-pick=plan][data-id="${s34.id}"]').classList.contains('on')`)), "not lit");
    const words = (await js(`shotlisterPlan.sheet() && shotlisterPlan.sheet().svg || ''`)) || "";
    check("…its sheet titled with the scene and the diagram", /34 · .*— Diagram 3/i.test(words.replace(/<[^>]+>/g, " ").replace(/&amp;/g, "&")) || /DIAGRAM 3/i.test(words), words.slice(0, 120));
    await shot("diagrammulti-tabs.png");
    await open(true);
    const before = await js(`document.querySelectorAll('[data-pick=plan]').length`);
    await js(`document.querySelector('[data-phideempty]').click()`); await wait(700);
    const after = await js(`document.querySelectorAll('[data-pick=plan]').length`);
    const reveal = await js(`(document.querySelector('[data-pshowempty]') || {}).textContent || ''`);
    check("Edit lists every scene; Hide Empty takes the undrawn away", after < before && /\d+ Hidden/.test(reveal), `${before} → ${after}, "${reveal}"`);
    check("…saying how many", reveal.trim() === `${undrawn} Hidden`, `"${reveal}" vs ${undrawn}`);
    await shot("diagrammulti-hide.png");
    await js(`document.querySelector('[data-pshowempty]').click()`); await wait(700);
    check("…and the count brings them back", (await js(`document.querySelectorAll('[data-pick=plan]').length`)) === before, "still hidden");
    check("no page errors", thrown.length === 0, thrown.slice(0, 2).join(" | "));
  });
} finally {
  hub.kill();
}
say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
