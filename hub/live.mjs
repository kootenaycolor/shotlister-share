#!/usr/bin/env -S node --experimental-websocket
/**
 * **Two people on one board, at once** — whether each sees the other's change
 * the moment it is made, and whether both keep their work.
 *
 * His ask, 2026-09-25: "live collaboration features to the look board, so
 * people can see changes in real time." `checks.sh` asks the worker questions
 * over HTTP and cannot hold two browsers open on one board; this does. Two
 * tabs — him, and the director — on a board with two notes:
 *
 * - each sees the other on the toolbar;
 * - a card he drags wears his colour on her screen while it is in his hand,
 *   and lands where he dropped it within a second;
 * - she types into one note while he moves the other, and the board keeps
 *   both — the thing a whole-board save used to lose;
 * - two changes sent at the same instant are both kept.
 *
 *     hub/live.mjs
 *
 * It starts its own hub on 8791 against a throwaway bucket, and stops
 * everything after. Screenshots land in /tmp (or $SHOTS).
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const OWNER = "owner@example.com";
const DIRECTOR = "clara@example.com";
const PORT = 8791;
const DEBUG = 9347;
const H = `http://127.0.0.1:${PORT}`;
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(66)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); };
const check = (what, good, why) => (good ? ok(what) : no(what, why));

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "live-"));
  const put = (key, body) => {
    const file = join(box, "one.json");
    writeFileSync(file, body);
    spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
      "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  };
  put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
  put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
  put(`p/${FILM}/front.json`, JSON.stringify({
    version: 1, status: "Active", type: "Narrative", length: "Short", director: "Clara Moreau",
    updated: new Date().toISOString(), mark: { path: "", colour: "#D44C47" }, camera: {},
    crew: [{ name: "Clara Moreau", role: "Director", email: DIRECTOR }],
    documents: [], sections: [], groups: [],
  }));
  rmSync(box, { recursive: true, force: true });
}

/** One browser, any number of tabs, each driven over its own line. */
async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1200,800", "about:blank"], { stdio: "ignore" });
  const lines = [];
  try {
    let up = false;
    for (let i = 0; i < 80 && !up; i++) {
      await wait(150);
      try { up = (await fetch(`http://127.0.0.1:${DEBUG}/json/version`)).ok; } catch {}
    }
    if (!up) throw new Error("the browser never answered — is Playwright's Chromium cached?");
    const tab = async (url) => {
      const t = await (await fetch(`http://127.0.0.1:${DEBUG}/json/new?${encodeURI(url)}`, { method: "PUT" })).json();
      const ws = new WS(t.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
      await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
      lines.push(ws);
      let id = 0;
      const waiting = new Map();
      ws.on("message", (m) => {
        const said = JSON.parse(m);
        if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
      });
      const ask = (method, params = {}) =>
        new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
      await ask("Page.enable");
      await ask("Emulation.setDeviceMetricsOverride", { width: 1200, height: 800, deviceScaleFactor: 1, mobile: false });
      // A tab in the background is still a page somebody is looking at.
      await ask("Emulation.setFocusEmulationEnabled", { enabled: true });
      const js = async (expression) => {
        const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
        return got.result?.result?.value;
      };
      const mouse = (type, x, y) => ask("Input.dispatchMouseEvent", {
        type, x, y, button: type === "mouseMoved" ? "none" : "left",
        buttons: type === "mouseReleased" ? 0 : 1, clickCount: type === "mouseMoved" ? 0 : 1, pointerType: "mouse",
      });
      const shot = async (name) => {
        const got = await ask("Page.captureScreenshot", { format: "png" });
        writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
        say(`  → ${join(shots, name)}`);
      };
      return { ask, js, mouse, shot };
    };
    return await run(tab);
  } finally {
    for (const l of lines) l.close();
    proc.kill();
  }
}

/** In the page: everything under every shadow root. */
const ALL = `(function all(sel, r = document) {
  let out = [...r.querySelectorAll(sel)];
  for (const e of r.querySelectorAll("*")) if (e.shadowRoot) out = out.concat(all(sel, e.shadowRoot));
  return out;
})`;
/** Where a card is on the board, read off its transform. */
const cardAt = (id) => `(() => {
  const c = ${ALL}('.bd-n[data-id="${id}"]')[0];
  if (!c) return null;
  const m = c.style.transform.match(/translate\\(([-\\d.]+)px,\\s*([-\\d.]+)px\\)/);
  const r = c.getBoundingClientRect();
  return JSON.stringify({ x: m ? +m[1] : null, y: m ? +m[2] : null, sx: r.left + 30, sy: r.top + 26,
    held: c.classList.contains("held"), text: (c.querySelector(".bd-t") || {}).textContent || "" });
})()`;

const state = mkdtempSync(join(tmpdir(), "live-state-"));
say("Putting one film in a local bucket…");
seed(state);
say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state,
   "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  // ---- a board, shared with the crew, with two notes on it ----
  const as = (who) => `as=${encodeURIComponent(who)}`;
  await fetch(`${H}/f/${FILM}/api/people?${as(OWNER)}`, { method: "PUT", headers: { "content-type": "application/json" },
    body: JSON.stringify({ people: [{ email: DIRECTOR, role: "editor" }], links: [] }) });
  const fd = new FormData();
  fd.set("type", "board");
  fd.set("name", "Live Look");
  const made = await fetch(`${H}/f/${FILM}/add?${as(OWNER)}`, { method: "POST", body: fd, redirect: "manual" });
  const slug = (made.headers.get("location") || "").split("/").pop();
  const page = await (await fetch(`${H}/f/${FILM}/${slug}?${as(OWNER)}`)).text();
  const name = (page.match(/data-bd="([^"]+)"/) || [])[1];
  if (!name) { say("no board was made"); process.exit(1); }
  const B = `${H}/f/${FILM}/api/board/${name}`;
  await fetch(`${B}/share?${as(OWNER)}`, { method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify({ share: "crew" }) });
  const patch = (ops, who = OWNER) => fetch(`${B}?${as(who)}`, { method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ ops }) });
  const board = async () => (await (await fetch(`${B}?${as(OWNER)}`)).json()).board;

  say("\n  the portal takes changes, not boards");
  let r = await patch([
    { f: "added", k: "note-one", v: { id: "note-one", kind: "note", kicker: "Note", x: -200, y: 0, text: "Handheld" } },
    { f: "added", k: "note-two", v: { id: "note-two", kind: "note", kicker: "Note", x: 200, y: 0, text: "" } },
  ]);
  check("a change is taken, and answers the stamp it replaced", r.ok && "prev" in (await r.json()), `status ${r.status}`);
  check("…and the board has both cards", (await board()).added.length === 2, "not two");
  const [a1, a2] = await Promise.all([
    patch([{ f: "added", k: "note-one", p: "x", v: -260 }]),
    patch([{ f: "added", k: "note-two", p: "text", v: "Night" }], DIRECTOR),
  ]);
  let b = await board();
  const one = (id) => b.added.find((d) => d.id === id) || {};
  check("two changes sent at the same instant are both kept", a1.ok && a2.ok && one("note-one").x === -260 && one("note-two").text === "Night",
    JSON.stringify(b.added.map((d) => [d.id, d.x, d.text])));
  check("a viewer on the share host still may not change it", (await fetch(`${B}?k=nokeynokeynokeynokey01`, { method: "PATCH", body: "{}" })).status >= 400, "taken");

  await browser(async (tab) => {
    // ---- him, and the director ----
    const him = await tab(`${H}/f/${FILM}/${slug}`);
    await wait(1500);
    const her = await tab(`${H}/f/${FILM}/${slug}?${as(DIRECTOR)}`);
    await wait(3500);
    say("\n  two people, one board");
    const faces = (t) => t.js(`${ALL}('.bd-face').map(f => f.title).join(",")`);
    check("he sees her on the toolbar", (await faces(him)) === "Clara Moreau", `"${await faces(him)}"`);
    check("she sees him on the toolbar", (await faces(her)).length > 0, "nobody");

    // ---- he drags a card; she watches it move ----
    // Mouse and keys go to the tab in front, as they would for a person.
    await him.ask("Page.bringToFront");
    await wait(300);
    const start = JSON.parse(await him.js(cardAt("note-one")));
    const herStart = JSON.parse(await her.js(cardAt("note-one")));
    await him.mouse("mousePressed", start.sx, start.sy);
    for (let i = 1; i <= 12; i++) { await him.mouse("mouseMoved", start.sx + i * 12, start.sy + i * 8); await wait(30); }
    await wait(400);
    const mid = JSON.parse(await her.js(cardAt("note-one")));
    check("while he holds a card, it wears his colour on her screen", mid.held, "not marked");
    check("…and moves on her screen as he moves it", Math.abs(mid.x - herStart.x) > 40, `moved ${Math.round(mid.x - herStart.x)}px`);
    await her.shot("shotlister-live-mid-drag.png");
    const hisMid = JSON.parse(await him.js(cardAt("note-one")));
    check("the card follows his pointer on his own screen", Math.abs(hisMid.x - start.x) > 40, `start ${JSON.stringify(start)} now ${JSON.stringify(hisMid)}`);
    await him.mouse("mouseReleased", start.sx + 144, start.sy + 96);
    const dropped = Date.now();
    let landed = null;
    for (let i = 0; i < 30; i++) {
      await wait(100);
      const h = JSON.parse(await him.js(cardAt("note-one"))), s = JSON.parse(await her.js(cardAt("note-one")));
      if (!s.held && Math.abs(h.x - s.x) < 2 && Math.abs(h.y - s.y) < 2 && Math.abs(s.x - herStart.x) > 40) { landed = Date.now() - dropped; break; }
    }
    check("the card lands where he dropped it, on her screen", landed !== null, "never matched");
    if (landed !== null) say(`      (${landed} ms after he let go)`);

    // ---- she types while he moves the other card ----
    await her.ask("Page.bringToFront");
    await her.js(`(() => { const t = ${ALL}('.bd-n[data-id="note-two"] .bd-t')[0]; t.focus();
      const s = t.getRootNode().getSelection ? t.getRootNode().getSelection() : getSelection(); const rg = document.createRange();
      rg.selectNodeContents(t); rg.collapse(false); (getSelection()).removeAllRanges(); getSelection().addRange(rg); })()`);
    await her.ask("Input.insertText", { text: " exteriors" });
    await him.ask("Page.bringToFront");
    const two = JSON.parse(await him.js(cardAt("note-one")));
    await him.mouse("mousePressed", two.sx, two.sy);
    for (let i = 1; i <= 8; i++) { await him.mouse("mouseMoved", two.sx - i * 15, two.sy + i * 10); await wait(25); }
    await him.mouse("mouseReleased", two.sx - 120, two.sy + 80);
    await her.ask("Page.bringToFront");
    await her.ask("Input.insertText", { text: " only" });
    await wait(2000);
    b = await board();
    const n1 = b.added.find((d) => d.id === "note-one"), n2 = b.added.find((d) => d.id === "note-two");
    check("she types while he moves a card: the board keeps both", n2.text === "Night exteriors only" && n1.x < -260 + 144 - 60,
      `text "${n2.text}", x ${n1.x}`);
    const hisView = JSON.parse(await him.js(cardAt("note-two")));
    check("…her words are on his screen", hisView.text === "Night exteriors only", `"${hisView.text}"`);
    const herCaret = await her.js(`(() => { const a = ${ALL}('.bd-n[data-id="note-two"] .bd-t')[0]; return a.getRootNode().activeElement === a; })()`);
    check("…and her note kept its caret while his change came in", herCaret === true, "lost focus");
    await him.shot("shotlister-live-his-screen.png");
    await her.shot("shotlister-live-her-screen.png");

    // ---- undo takes back only one's own ----
    await her.js(`${ALL}('.bd-n[data-id="note-two"] .bd-t')[0].blur()`);
    await him.ask("Page.bringToFront");
    await wait(300);
    await him.ask("Input.dispatchKeyEvent", { type: "keyDown", key: "z", code: "KeyZ", modifiers: 4, windowsVirtualKeyCode: 90 });
    await him.ask("Input.dispatchKeyEvent", { type: "keyUp", key: "z", code: "KeyZ", modifiers: 4, windowsVirtualKeyCode: 90 });
    await wait(1500);
    b = await board();
    const u1 = b.added.find((d) => d.id === "note-one"), u2 = b.added.find((d) => d.id === "note-two");
    check("his undo takes back his move, and leaves her words", u2.text === "Night exteriors only" && u1.x !== n1.x,
      `text "${u2.text}", x ${n1.x} → ${u1.x}`);

    // ---- a chat's change reaches both screens ----
    await patch([{ f: "added", k: "note-three", v: { id: "note-three", kind: "note", kicker: "Note", x: 0, y: 300, text: "From a chat" } }]);
    await wait(1200);
    check("a change from anywhere else appears on both screens", Boolean(await him.js(cardAt("note-three"))) && Boolean(await her.js(cardAt("note-three"))), "missing");
  });
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
