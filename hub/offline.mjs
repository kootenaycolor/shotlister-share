#!/usr/bin/env -S node --experimental-websocket
/**
 * **Whether the film opens a second time without asking, and a third time with
 * no network at all.**
 *
 * A film is its change logs. Opening his real *Call Her Back* used to fetch
 * every one of them — measured, 166 requests, 120 of them logs — and on a phone
 * on a location that is the whole of the wait. `film.js` keeps them now, keyed
 * by name **and size**, because the relay's one rule is that a log may only
 * ever grow and the server says every size before a byte is fetched.
 *
 * `checks.sh` cannot see any of this: it asks the worker questions, and the
 * question here is what a *browser* does on its second visit. Same reason
 * `drag.mjs` and `scans.mjs` exist.
 *
 *     hub/offline.mjs
 *
 * It starts its own hub on 8794 against a throwaway bucket, seeds his real
 * film, and stops everything after.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, readdirSync, existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const PORT = 8794, DEBUG = 9350;
const WHO = "owner@example.com";
const REAL = process.env.FILM ||
  join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/Shotlister/Call Her Back.shotlist");

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(58)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(58)} FAIL — ${why}`); };

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "offline-"));
  const putFile = (k, f) => spawnSync(w, ["r2", "object", "put", `shotlister-preview/${k}`,
    "--file", f, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  const file = join(box, "one.bin");
  writeFileSync(file, JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
  putFile(`p/${FILM}/manifest.json`, file);
  let logs = 0;
  for (const n of readdirSync(join(REAL, "changes"))) {
    if (!n.endsWith(".log")) continue;
    putFile(`p/${FILM}/logs/${n}`, join(REAL, "changes", n));
    logs += 1;
  }
  rmSync(box, { recursive: true, force: true });
  return logs;
}

if (!existsSync(join(REAL, "changes"))) { say(`no film at ${REAL}`); process.exit(1); }
const state = mkdtempSync(join(tmpdir(), "offline-state-"));
say(`Putting ${basename(REAL)} in a local bucket…`);
say(`  ${seed(state)} change logs`);
say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state,
   "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

let proc = null;
try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1500,1000", "about:blank"], { stdio: "ignore" });
  let targets = null;
  for (let i = 0; i < 80 && !targets; i++) {
    await wait(150);
    try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch {}
  }
  if (!targets) throw new Error("the browser never answered");
  const page = targets.find((t) => t.type === "page");
  const ws = new WS(page.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
  await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
  let id = 0;
  const waiting = new Map();
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
  });
  const ask = (method, params = {}) =>
    new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
  await ask("Page.enable");
  await ask("Network.enable");

  const js = async (e) =>
    (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
  const open = async () => {
    await ask("Page.navigate", { url: "about:blank" });
    await wait(300);
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/shotlist?as=${WHO}` });
    await wait(6000);
  };
  /** How many logs this load actually asked the server for. */
  const asked = () => js(
    `performance.getEntriesByType('resource').filter(r => /\\/api\\/log\\//.test(r.name)).length`);
  const drawn = () => js(`document.querySelectorAll('.sceneband').length`);
  const bar = () => js(
    `(document.querySelector('.livedot') || {}).textContent || ''`);

  // ---- the shape it draws before the film arrives -----------------------
  //
  // **Throttled on purpose.** On a local server the film is up in a tenth of a
  // second and the outline is gone before anything could see it; on his phone
  // that first visit is the whole point of drawing one.
  await ask("Network.emulateNetworkConditions",
    { offline: false, latency: 300, downloadThroughput: 40 * 1024, uploadThroughput: 40 * 1024 });
  await ask("Page.navigate", { url: "about:blank" });
  await wait(300);
  await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/shotlist?as=${WHO}` });
  // **Wait for the page to be able to paint at all, then look.**
  //
  // 56 KB of gzipped stylesheet sits in the head and blocks the first paint, so
  // for the first second or so of a slow load the browser draws nothing —
  // nothing in the body can change that, and a check that measured before then
  // was measuring a browser that had not started. What is being asked here is
  // the real question: once the page *can* draw, is the outline what it draws,
  // and is the film still on its way?
  for (let i = 0; i < 60; i += 1) {
    await wait(250);
    if (await js(`document.styleSheets.length >= 2`)) break;
  }
  await wait(700);
  // **Present is not the same as visible, and that distinction cost a round.**
  // Written into the page but styled from `hub.css`, the outline was in the
  // document and drew nothing, because at this speed the stylesheet had not
  // arrived either. So this reads what the browser actually computed.
  const ghost = JSON.parse(await js(`(() => {
    const g = document.querySelector('.ghost');
    const b = document.querySelector('.ghost .gb');
    const seen = (el) => {
      if (!el) return null;
      const s = getComputedStyle(el);
      const box = el.getBoundingClientRect();
      return { opacity: Number(s.opacity).toFixed(2), paint: s.backgroundColor,
               w: Math.round(box.width), h: Math.round(box.height) };
    };
    return JSON.stringify({
      outline: document.querySelectorAll('.ghost').length,
      bands: document.querySelectorAll('.ghost .gband').length,
      bones: document.querySelectorAll('.ghost .gb').length,
      busy: !!document.querySelector('[aria-busy="true"]'),
      words: (g && g.innerText || '').trim(),
      frame: seen(g), bone: seen(b),
    });
  })()`) || "{}");
  say(`\n  while it loads: ${JSON.stringify(ghost)}`);
  const real = await js(`document.querySelectorAll('.app .sceneband').length`);
  ghost.outline === 1 && ghost.bands === 3 && real === 0
    ? ok("the page draws the film's shape while it loads")
    : no("the page draws the film's shape while it loads",
         `outline ${ghost.outline}, bands ${ghost.bands}, film already drawn: ${real}`);
  ghost.busy ? ok("…and says it is busy to anything reading it aloud")
             : no("…and says it is busy to anything reading it aloud", "no aria-busy");
  // The one that matters: a shape nobody can see is not a shape.
  Number(ghost.frame?.opacity) > 0.9 && ghost.bone?.w > 0 && ghost.bone?.h > 0
    && !/rgba\(0, 0, 0, 0\)/.test(ghost.bone?.paint || "")
    ? ok("…and is actually drawn, with no stylesheet yet")
    : no("…and is actually drawn, with no stylesheet yet", JSON.stringify({ frame: ghost.frame, bone: ghost.bone }));
  (ghost.words || "").trim() === ""
    ? ok("…and says nothing the shape does not")
    : no("…and says nothing the shape does not", `it says "${ghost.words.trim()}"`);
  const shot = await ask("Page.captureScreenshot", { format: "png" });
  writeFileSync(join(process.env.SHOTS || tmpdir(), "shotlister-loading.png"),
    Buffer.from(shot.result.data, "base64"));
  say(`  → ${join(process.env.SHOTS || tmpdir(), "shotlister-loading.png")}`);
  await ask("Network.emulateNetworkConditions",
    { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });

  // ---- first visit ------------------------------------------------------
  await open();
  const firstLogs = await asked();
  const firstScenes = await drawn();
  say(`\n  first visit: ${firstLogs} log requests, ${firstScenes} scenes drawn`);
  firstScenes > 0 ? ok("the film draws on a first visit")
                  : no("the film draws on a first visit", "nothing drawn");
  firstLogs > 50 ? ok("…and a first visit is the one that pays for it")
                 : no("…and a first visit is the one that pays for it", `${firstLogs} requests`);

  // ---- second visit -----------------------------------------------------
  await open();
  const againLogs = await asked();
  const againScenes = await drawn();
  say(`  second visit: ${againLogs} log requests, ${againScenes} scenes drawn`);
  againScenes === firstScenes
    ? ok("the same film draws from the copy in the browser")
    : no("the same film draws from the copy in the browser", `${againScenes} scenes, was ${firstScenes}`);
  againLogs <= 2
    ? ok(`…without asking for the logs again (${firstLogs} → ${againLogs})`)
    : no("…without asking for the logs again", `${againLogs} requests`);

  // ---- and with the network pulled out ----------------------------------
  await ask("Network.emulateNetworkConditions",
    { offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await open();
  const darkScenes = await drawn();
  const said = await bar();
  say(`  no network: ${darkScenes} scenes drawn, the bar says "${said.trim()}"`);
  darkScenes === firstScenes
    ? ok("the film opens with no network at all")
    : no("the film opens with no network at all", `${darkScenes} scenes`);
  /offline/i.test(said)
    ? ok("…and says Offline rather than pretending")
    : no("…and says Offline rather than pretending", `it says "${said.trim()}"`);
  await ask("Network.emulateNetworkConditions",
    { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  ws.close();
} finally {
  if (proc) proc.kill();
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
