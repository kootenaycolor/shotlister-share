#!/usr/bin/env -S node --experimental-websocket
/**
 * **Whether the portal's storyboard follows each picture's shape**: a card's
 * picture area takes its Print Frame's shape (or the film's), rows share a
 * height, and a board that is not on the page falls back to the key picture.
 *
 *     FILM=/path/to/Some.shotlist hub/storyboardframes.mjs
 *
 * The film is a scratch copy with Print Frames of different shapes baked on
 * some shots. Its pictures are put in the local bucket too.
 *
 * It starts its own hub on 8796 against a throwaway bucket and stops
 * everything after. Screenshots land in $SHOTS or /tmp.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, readdirSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const PORT = 8796, DEBUG = 9352;
const WHO = "owner@example.com";
const REAL = process.env.FILM;

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(62)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(62)} FAIL — ${why}`); };

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "sbframes-"));
  const putFile = (k, f) => spawnSync(w, ["r2", "object", "put", `shotlister-preview/${k}`,
    "--file", f, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  const file = join(box, "one.bin");
  writeFileSync(file, JSON.stringify({ format: 1, project: FILM, title: basename(REAL, ".shotlist"), engine: "0.1.0" }));
  putFile(`p/${FILM}/manifest.json`, file);
  let logs = 0;
  for (const n of readdirSync(join(REAL, "changes"))) {
    if (!n.endsWith(".log")) continue;
    putFile(`p/${FILM}/logs/${n}`, join(REAL, "changes", n));
    logs += 1;
  }
  let pics = 0;
  const media = join(REAL, "media", "proxies");
  if (existsSync(media)) for (const n of readdirSync(media)) {
    putFile(`p/${FILM}/media/${n}`, join(media, n));
    pics += 1;
  }
  rmSync(box, { recursive: true, force: true });
  return { logs, pics };
}

if (!REAL || !existsSync(join(REAL, "changes"))) { say(`give FILM=<a .shotlist folder> (got ${REAL})`); process.exit(1); }
const state = mkdtempSync(join(tmpdir(), "sbframes-state-"));
say(`Putting ${basename(REAL)} in a local bucket…`);
{ const got = seed(state); say(`  ${got.logs} change logs, ${got.pics} pictures`); }
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
  const js = async (e) =>
    (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;

  await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/shotlist?as=${WHO}` });
  await wait(7000);

  const scenes = await js(`document.querySelectorAll('.sceneband').length`);
  scenes > 0 ? ok("the film draws its scenes") : no("the film draws its scenes", "no scene bands");

  await js(`document.querySelector('button[data-view="storyboard"]').click()`);
  await wait(2500);
  const cards = JSON.parse(await js(`JSON.stringify([...document.querySelectorAll('.cards .card')].map((c) => {
    const f = c.querySelector('.cardframe'), r = f.getBoundingClientRect(), k = c.getBoundingClientRect();
    return { n: c.querySelector('.no').textContent.trim(), board: f.classList.contains('board'),
             w: Math.round(r.width), h: Math.round(r.height), top: Math.round(k.top), x: Math.round(k.left), cw: Math.round(k.width),
             ratio: +(r.width / r.height).toFixed(3), want: +getComputedStyle(c).getPropertyValue('--r') };
  }))`) || "[]");
  for (const c of cards) say(`  ${c.n}: ${c.board ? "board " : "frame "}${c.w}x${c.h} = ${c.ratio} (wants ${c.want}), card ${c.cw}w at ${c.x},${c.top}`);
  cards.length >= 6 ? ok("the storyboard draws its cards") : no("the storyboard draws its cards", `${cards.length}`);
  const boards = cards.filter((c) => c.board);
  boards.length >= 3 ? ok("shots with a baked Print Frame wear it") : no("shots with a baked Print Frame wear it", `${boards.length}`);
  cards.every((c) => Math.abs(c.ratio - c.want) < 0.03)
    ? ok("every picture area has its own shape, none squeezed")
    : no("every picture area has its own shape, none squeezed", JSON.stringify(cards.filter((c) => Math.abs(c.ratio - c.want) >= 0.03)));
  const broken = await js(`[...document.querySelectorAll('.boardpic')].filter((i) => !i.complete || !i.naturalWidth).length`);
  broken === 0 ? ok("every board picture loaded") : no("every board picture loaded", `${broken} did not`);
  // Rows: cards on one line share a picture height, except one kept wider than its picture.
  const rows = {};
  for (const c of cards) (rows[c.top] ||= []).push(c);
  const spread = Object.values(rows).map((r) => Math.max(...r.map((c) => c.h)) - Math.min(...r.map((c) => c.h)));
  say(`  rows: ${Object.values(rows).map((r) => r.length).join(" ")}  height spread per row: ${spread.join(" ")}`);
  spread.every((s) => s <= 40) ? ok("cards on a row stand at about one picture height") : no("cards on a row stand at about one picture height", spread.join(","));
  // A board that is not on the page falls back to the key picture, at the film's shape.
  const before = await js(`document.querySelectorAll('.boardpic').length`);
  await js(`document.querySelectorAll('.boardpic')[0].dispatchEvent(new Event('error'))`);
  await wait(300);
  const after = await js(`document.querySelectorAll('.boardpic').length`);
  after === before - 1 ? ok("a board that is missing falls back to the key picture") : no("a board that is missing falls back to the key picture", `${before} -> ${after}`);

  const shot = await ask("Page.captureScreenshot", { format: "png" });
  const out = join(process.env.SHOTS || tmpdir(), "storyboardframes-portal.png");
  writeFileSync(out, Buffer.from(shot.result.data, "base64"));
  say(`  → ${out}`);
} finally {
  try { proc && proc.kill(); } catch {}
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  try { hub.kill(); } catch {}
  rmSync(state, { recursive: true, force: true });
}
say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
