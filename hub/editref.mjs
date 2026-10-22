#!/usr/bin/env -S node --experimental-websocket
/**
 * **Edit Reference on the portal** (the first mod, 2026-10-17): the gold
 * bracket beside the shots an edit reference joins, its player, and nothing
 * at all on a project without the mod.
 *
 *     FILM=/path/to/Some.shotlist hub/editref.mjs
 *
 * The film must hold one edit reference over 34C, 34D, 34E and 35A with its
 * clip (a Studio checking run with `--addeditref 34C,34D,34E,35A` makes one). Two copies go in a throwaway
 * bucket: one whose record has the mod on, one with no record. Screenshots
 * land in $SHOTS or /tmp.
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
const PLAIN = "01a02852ebb00198e46a252100000001";
const PORT = 8796, DEBUG = 9352;
const WHO = "owner@example.com";
const REAL = process.env.FILM;

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(62)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(62)} FAIL — ${why}`); };

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

function seed(state, FILM, mods) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "editref-"));
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
  for (const n of readdirSync(join(REAL, "media", "proxies"))) putFile(`p/${FILM}/media/${n}`, join(REAL, "media", "proxies", n));
  if (mods) {
    writeFileSync(file, JSON.stringify({ page: FILM, name: "ZZ Mods", film: { relay: FILM }, facts: { mods: { value: { edit_reference: true }, v: 1 } } }));
    putFile(`r/${FILM}/record.json`, file);
  }
  rmSync(box, { recursive: true, force: true });
  return logs;
}

if (!REAL || !existsSync(join(REAL, "changes"))) { say(`give FILM=<a .shotlist folder> (got ${REAL})`); process.exit(1); }
const state = mkdtempSync(join(tmpdir(), "editref-state-"));
say(`Putting ${basename(REAL)} in a local bucket…`);
say(`  ${seed(state, FILM, true)} change logs`);
seed(state, PLAIN, false);
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

  const go = async (film, extra = "") => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${film}/shotlist?as=${WHO}${extra}` });
    await wait(7000);
  };
  const out = (n) => join(process.env.SHOTS || tmpdir(), n);
  const snap = async (n) => { const s = await ask("Page.captureScreenshot", { format: "png" }); writeFileSync(out(n), Buffer.from(s.result.data, "base64")); say(`  → ${out(n)}`); };

  // 1. a project without the mod: nothing new
  await go(PLAIN);
  say("  page: " + await js(`location.href + ' mode=' + HUB.mode + ' title=' + document.title`));
  const plain = JSON.parse(await js(`JSON.stringify({ bands: document.querySelectorAll('.sceneband').length, eref: document.querySelectorAll('.eref').length, edmod: document.body.classList.contains('edmod'), mods: HUB.mods })`));
  plain.bands > 0 ? ok("the film draws its scenes") : no("the film draws its scenes", JSON.stringify(plain));
  plain.eref === 0 && !plain.edmod ? ok("without the mod: no bracket, no margin") : no("without the mod: no bracket, no margin", JSON.stringify(plain));

  // 2. with the mod on: one bracket over 34C–35A, across scene 35's heading
  //    (his note, 2026-10-17: "right now the scene heading splits")
  await go(FILM, "&editrefat=6.5");
  const on = JSON.parse(await js(`JSON.stringify({ mods: HUB.mods, edmod: document.body.classList.contains('edmod'),
    rows: [...document.querySelectorAll('.trow .eref, .lrow .eref')].map(e => e.closest('.trow, .lrow').querySelector('.no').textContent.trim() + (e.classList.contains('first') ? ':first' : '') + (e.classList.contains('last') ? ':last' : '')),
    thru: [...document.querySelectorAll('.sceneband .eref.thru')].map(e => e.closest('.sceneband').querySelector('.num').textContent.trim()),
    play: document.querySelectorAll('.eref-play').length })`));
  say(`  bracket rows: ${on.rows.join(", ")}  over headings: ${on.thru.join(", ")}`);
  on.edmod && on.rows.join() === "34C:first,34D,34E,35A:last" ? ok("with the mod: one bracket from 34C to 35A") : no("with the mod: one bracket from 34C to 35A", JSON.stringify(on));
  on.thru.join() === "35" ? ok("the bracket runs over scene 35's heading") : no("the bracket runs over scene 35's heading", JSON.stringify(on.thru));
  on.play === 1 ? ok("one play button, at its top") : no("one play button, at its top", String(on.play));
  await js(`document.querySelector('[data-band]') && document.querySelectorAll('.sceneband')[1].scrollIntoView()`);
  await snap("editref-portal.png");

  // 3. the player: the clip, play and pause, a scrubber, close — nothing else
  // A real pointer press at the button's middle (not the element's own
  // .click()): what he does, and what finds a button something else covers.
  await js(`document.querySelector('.eref-play').scrollIntoView({ block: 'center' })`);
  await wait(300);
  const where = JSON.parse(await js(`(() => { const b = document.querySelector('.eref-play'), r = b.getBoundingClientRect();
    const x = r.left + r.width / 2, y = r.top + r.height / 2, top = document.elementFromPoint(x, y);
    return JSON.stringify({ x, y, onButton: !!(top && top.closest('.eref-play')) }); })()`));
  where.onButton ? ok("the point on the play button is the button, not the row") : no("the point on the play button is the button, not the row", JSON.stringify(where));
  for (const type of ["mousePressed", "mouseReleased"]) {
    await ask("Input.dispatchMouseEvent", { type, x: where.x, y: where.y, button: "left", clickCount: 1 });
  }
  await wait(2500);
  const pl = JSON.parse(await js(`JSON.stringify({ open: !!document.querySelector('.eref-wrap'), ready: (document.querySelector('.eref-wrap video')||{}).readyState || 0,
    at: (document.querySelector('.eref-wrap video')||{}).currentTime || 0, time: (document.querySelector('.eref-now-t')||{}).textContent || '',
    scrub: !!document.querySelector('.eref-scrub[role=slider]'), strip: document.querySelectorAll('.eref-strip, .eref-chips, .eref-now').length,
    glow: [...document.querySelectorAll('.eref-dot.now, .eref-play.now')].map(d => d.closest('.trow, .lrow').querySelector('.no').textContent.trim()) })`));
  say(`  player: ${JSON.stringify(pl)}`);
  pl.open && pl.ready >= 1 ? ok("play opens the player and the clip loads") : no("play opens the player and the clip loads", JSON.stringify(pl));
  pl.scrub && pl.time === "0:06" ? ok("a scrubber, at 0:06") : no("a scrubber, at 0:06", JSON.stringify(pl));
  pl.strip === 0 ? ok("no shot strip, chips or cut picker") : no("no shot strip, chips or cut picker", String(pl.strip));
  pl.glow.join() === "34E" ? ok("the shot on now glows on the bracket (34E)") : no("the shot on now glows on the bracket (34E)", JSON.stringify(pl.glow));
  await snap("editref-player.png");
  // drag-free: a click a quarter along the scrubber goes a quarter in
  await js(`(() => { const s = document.querySelector('.eref-scrub'), r = s.getBoundingClientRect();
    s.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerId: 1, clientX: r.left + r.width / 4, clientY: r.top + r.height / 2 }));
    s.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, pointerId: 1 })); })()`);
  await wait(400);
  const quarter = await js(`document.querySelector('.eref-wrap video').currentTime`);
  Math.abs(quarter - 3) < 0.6 ? ok("the scrubber seeks (a quarter in is 0:03)") : no("the scrubber seeks (a quarter in is 0:03)", String(quarter));
  await js(`document.querySelector('.eref-scrub').focus(); document.querySelector('.eref-scrub').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))`);
  await wait(300);
  const stepped = await js(`document.querySelector('.eref-wrap video').currentTime`);
  Math.abs(stepped - quarter - 5) < 0.6 ? ok("→ steps five seconds") : no("→ steps five seconds", `${quarter} → ${stepped}`);
  await js(`document.querySelector('.eref-x').click()`);
  await wait(700);
  (await js(`!document.querySelector('.eref-wrap')`)) ? ok("× closes it") : no("× closes it", "still open");
} finally {
  try { proc && proc.kill(); } catch {}
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  try { hub.kill(); } catch {}
  rmSync(state, { recursive: true, force: true });
}
say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
