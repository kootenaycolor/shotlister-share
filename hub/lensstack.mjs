#!/usr/bin/env -S node --experimental-websocket
/**
 * **Whether the portal's shot list draws Lens Stack**: the lens chip with the
 * shot's filters and modifiers on a quiet line under it, and no Modifiers or
 * Filters columns. Always on.
 *
 *     FILM=/path/to/Some.shotlist hub/lensstack.mjs
 *
 * The film is a change log folder with at least one shot that has a filter. With no `FILM`, the scratch
 * Daybreak a Studio run left behind is used.
 *
 * It starts its own hub on 8795 against a throwaway bucket and stops
 * everything after. A screenshot lands in $SHOTS or /tmp.
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
const PORT = 8795, DEBUG = 9351;
const WHO = "owner@example.com";
const REAL = process.env.FILM;

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(62)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(62)} FAIL — ${why}`); };

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "lensstack-"));
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
  rmSync(box, { recursive: true, force: true });
  return logs;
}

if (!REAL || !existsSync(join(REAL, "changes"))) { say(`give FILM=<a .shotlist folder> (got ${REAL})`); process.exit(1); }
const state = mkdtempSync(join(tmpdir(), "lensstack-state-"));
say(`Putting ${basename(REAL)} in a local bucket…`);
say(`  ${seed(state)} change logs`);
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

  const heads = JSON.parse(await js(`JSON.stringify([...document.querySelectorAll('.thead .th')].map(e => e.textContent.trim()))`) || "[]");
  say(`  columns: ${heads.join(", ")}`);
  heads.includes("Lens") ? ok("there is a Lens column") : no("there is a Lens column", heads.join(","));
  !heads.includes("Modifiers") && !heads.includes("Filters")
    ? ok("Modifiers and Filters are not columns")
    : no("Modifiers and Filters are not columns", heads.join(","));

  const cells = await js(`document.querySelectorAll('.lenscell').length`);
  const under = await js(`document.querySelectorAll('.lensunder .lu').length`);
  say(`  stacked lens cells: ${cells}, filters/modifiers drawn: ${under}`);
  cells > 0 && under > 0 ? ok("the filters and modifiers sit under the lens chip")
                         : no("the filters and modifiers sit under the lens chip", `${cells} cells, ${under} items`);

  const look = JSON.parse(await js(`(() => {
    const u = document.querySelector('.lensunder');
    const c = document.querySelector('.lenscell .chip');
    if (!u || !c) return JSON.stringify(null);
    const a = u.getBoundingClientRect(), b = c.getBoundingClientRect();
    const s = getComputedStyle(u);
    return JSON.stringify({ under: a.top >= b.bottom - 1, size: s.fontSize, border: s.borderTopWidth });
  })()`) || "null");
  look && look.under && look.border === "0px"
    ? ok("…below it, with no box or outline")
    : no("…below it, with no box or outline", JSON.stringify(look));

  const shot = await ask("Page.captureScreenshot", { format: "png" });
  const out = join(process.env.SHOTS || tmpdir(), "lensstack-portal.png");
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
