#!/usr/bin/env -S node --experimental-websocket
/**
 * **The portal edits diagrams as much as the Mac, and a link can too** (his
 * ask, 2026-10-17: *"The portal should be able to edit the diagrams as much
 * as the Mac. And editing should be available publicly."*).
 *
 * A copy of the Daybreak fixture, a plan put on scene 33 by the engine
 * itself (`ffi/examples/run_commands`), seeded into a throwaway bucket. Then,
 * in a headless browser, pressed and dragged as a hand does:
 *
 * - as the owner: a scene's diagrams made, named, duplicated, moved, deleted
 *   (asked first) and brought back with Undo; one Colour for several; Send
 *   and Copy to Set; Own Label for several; a lamp's mark sized by its
 *   corner; Draw on Photo (arrow, line, box, words, guides, Style, Delete,
 *   Undo, Done) and Attach to Photo; Print takes every drawn diagram;
 * - as a visitor on the share link with Editable by Link on: the same tools
 *   as the owner, edits kept by the server, a tab made and deleted, a photo
 *   drawn on; a whole diagram is never taken away without the page asking;
 *   too many batches at once are slowed; every batch is in his Link Edits
 *   list as "Link visitor", and his Undo there takes it back;
 * - the switch off: the visitor's next edit is refused and the page puts its
 *   tools away.
 *
 *     hub/portaldiagram.mjs
 *
 * Its own hub on 8883 and browser on 9618 (HUB_PORT, DEBUG_PORT); photographs
 * land in /tmp, or wherever SHOTS says. Builds the browser half first.
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
const OWNER = "owner@example.com";
const KEY = "a".repeat(32);
const PORT = Number(process.env.HUB_PORT || 8883);
const DEBUG = Number(process.env.DEBUG_PORT || 9618);
const H = `http://127.0.0.1:${PORT}`;
const SHARE = { "x-hub-host": "share.your-domain.example" };
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => { if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); } else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); } };

let WS;
try { ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js"))); } catch { say("`ws` is not in hub/node_modules"); process.exit(1); }

if (!process.env.SKIP_BUILD) {
  say("Building the browser half…");
  if (spawnSync(join(HERE, "build.sh"), { stdio: "ignore" }).status !== 0) { say("the browser half would not build"); process.exit(1); }
}

// ---- the film: Daybreak, scene 33 with a plan --------------------------------
const work = mkdtempSync(join(tmpdir(), "portaldiagram-"));
const fixture = join(work, "Daybreak.shotlist");
cpSync(join(HERE, "../studio/fixtures/Daybreak.shotlist"), fixture, { recursive: true });
const ffi = join(HERE, "../ffi");
spawnSync("cargo", ["build", "--quiet", "--example", "run_commands"], { cwd: ffi, stdio: "ignore" });
const runner = join(ffi, "target/debug/examples/run_commands");
const run = (lines) => spawnSync(runner, [fixture], { input: lines.join("\n") + "\n" }).stdout.toString().trim().split("\n");
const view = JSON.parse(run(["view"])[0]);
const scene = view.scenes.find((s) => s.number === "33");
if (!scene) { say("no scene 33 in Daybreak"); process.exit(1); }
const els = [
  { kind: "wall", x: 0, y: 0, x2: 6, y2: 0 }, { kind: "wall", x: 6, y: 0, x2: 6, y2: 4 },
  { kind: "light", x: 2, y: 1.5, rot: 0, w: 0.6, h: 0.6, mark: "chevron", mark_fill: "open", lamp_name: "Key" },
  { kind: "light", x: 4, y: 1.5, rot: 0, w: 0.6, h: 0.6, mark: "chevron", mark_fill: "open", lamp_name: "Fill" },
  { kind: "cast", x: 3, y: 3, rot: 0, label: "Maya" },
  { kind: "text", x: 1, y: 3.5, text: "Window" },
  { kind: "arrow", x: 0.5, y: 2, x2: 2, y2: 2.5 },
];
run([`diagramedit\t${scene.id}\t${JSON.stringify({ op: "add", els })}`]);

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const put = (key, file) => spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  put(`p/${FILM}/manifest.json`, join(fixture, "manifest.json"));
  for (const name of readdirSync(join(fixture, "changes"))) if (name.endsWith(".log")) put(`p/${FILM}/logs/${name}`, join(fixture, "changes", name));
}

/** A fresh browser (its own cookies), driven through `go(page)`. */
async function browser(go, { share = false, size = [1400, 900] } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "portaldiagram-chrome-"));
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--remote-debugging-address=127.0.0.1", `--user-data-dir=${dir}`, "--no-sandbox", "--disable-gpu", `--window-size=${size[0]},${size[1]}`, "about:blank"], { stdio: "ignore" });
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
      if (said.method === "Page.javascriptDialogOpening") ask("Page.handleJavaScriptDialog", { accept: true });
    });
    const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable"); await ask("Runtime.enable"); await ask("Network.enable");
    await ask("Network.setCacheDisabled", { cacheDisabled: true });
    if (share) await ask("Network.setExtraHTTPHeaders", { headers: SHARE });
    await ask("Emulation.setDeviceMetricsOverride", { width: size[0], height: size[1], deviceScaleFactor: 1, mobile: false });
    const js = async (expression) => { const r = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }); return r.result?.result?.value; };
    const shot = async (name) => { const g = await ask("Page.captureScreenshot", { format: "png" }); writeFileSync(join(shots, name), Buffer.from(g.result.data, "base64")); say(`    → ${join(shots, name)}`); };
    const mouse = async (steps) => { for (const [type, x, y] of steps) { await ask("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1, buttons: type === "mouseReleased" ? 0 : 1 }); await wait(25); } };
    const drag = (x1, y1, x2, y2, n = 8) => mouse([["mousePressed", x1, y1], ...Array.from({ length: n }, (_, i) => ["mouseMoved", x1 + (x2 - x1) * (i + 1) / n, y1 + (y2 - y1) * (i + 1) / n]), ["mouseReleased", x2, y2]]);
    const key = async (k) => { await ask("Input.dispatchKeyEvent", { type: "keyDown", key: k, code: k.length === 1 ? `Key${k.toUpperCase()}` : k, text: k.length === 1 ? k : undefined }); await ask("Input.dispatchKeyEvent", { type: "keyUp", key: k }); };
    const helpers = `window.__m = (label) => { const b = [...document.querySelectorAll(".planmenu button")].find((n) => n.querySelector("span:last-of-type") && [...n.querySelectorAll("span")].some((s) => s.textContent.trim() === label)); if (!b) return "no " + label; b.click(); return "ok"; };
      window.__q = (sel) => { const n = document.querySelector(sel); if (!n) return "none " + sel; n.click(); return "ok"; };
      window.__menu = () => [...document.querySelectorAll(".planmenu button, .planmenu .pmhead")].map((n) => n.textContent.trim()).join(" | ");
      window.__tabs = () => [...document.querySelectorAll("[data-pdtab]")].map((b) => b.textContent.trim());`;
    await ask("Page.addScriptToEvaluateOnNewDocument", { source: helpers });
    const open = async (url) => {
      await ask("Page.navigate", { url });
      for (let i = 0; i < 60; i++) { await wait(250); if (await js(`!!(window.shotlisterPlan && document.querySelector('.planpic > svg'))`)) break; }
      await wait(500);
    };
    return await go({ ask, js, shot, mouse, drag, key, open, thrown });
  } finally { proc.kill(); }
}

const state = mkdtempSync(join(tmpdir(), "portaldiagram-state-"));
seed(state);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} -sTCP:LISTEN | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });
const asOwner = (path) => `${H}${path}${path.includes("?") ? "&" : "?"}as=${OWNER}`;
const putJson = (url, body, headers = {}) => fetch(url, { method: "PUT", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });
const ownerURL = `${H}/f/${FILM}/diagrams?as=${OWNER}`;
const visitorURL = `${H}/f/${FILM}/diagrams?k=${KEY}`;
const toEdit = async (p) => { await p.js(`__q('[data-pedit]:not(.on)')`); await wait(900); };
const pickWhere = (f) => `shotlisterPlan.pick(shotlisterPlan.els().filter(${f}).map((e) => e.id)); 1`;
const more = async (p) => { await p.js(`__q('.planfloat [data-pa=more]')`); await wait(300); };
/** A picture laid on the plan the way the Picture tool's Choose File does: kept, then laid. */
const layPicture = `(async () => {
  const c = document.createElement('canvas'); c.width = 800; c.height = 500; const x = c.getContext('2d');
  const g = x.createLinearGradient(0, 0, 0, 500); g.addColorStop(0, '#7aa7d8'); g.addColorStop(.55, '#d9c9a8'); g.addColorStop(1, '#6b5a45');
  x.fillStyle = g; x.fillRect(0, 0, 800, 500); x.fillStyle = '#3d3a36'; x.fillRect(300, 180, 200, 200);
  const blob = await new Promise((r) => c.toBlob(r, 'image/png'));
  const r = await fetch('/f/${FILM}/api/picture?name=room.png', { method: 'PUT', headers: { 'content-type': 'image/png' }, body: blob });
  const s = await r.json();
  shotlisterPlan.edit({ op: 'picture', hash: s.hash, ext: s.ext, pw: 800, ph: 500, bytes: s.bytes, filename: 'room.png', x: 3, y: 2, width: 4, photo: true });
  return r.status; })()`;
/** A point on the picture as the page draws it, by fractions of it. */
const onPic = (p, fx, fy) => p.js(`(() => { const e = shotlisterPlan.els().find((x) => x.kind === 'image'); return shotlisterPlan.at(e.x + (${fx} - 0.5) * e.w, e.y + (${fy} - 0.5) * e.h); })()`);

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) { await wait(1000); try { up = (await fetch(`${H}/health`)).ok; } catch {} }
  if (!up) { say("the hub would not start"); process.exit(1); }
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(KEY)))].map((b) => b.toString(16).padStart(2, "0")).join("");
  await putJson(asOwner(`/f/${FILM}/api/people`), { people: [], links: [{ hash, key: KEY, role: "viewer", off: false, expires: null, note: "" }], invites: [] });

  // ================================================================ the owner
  say("\nThe owner, on the Diagrams page");
  let ownerTools = [];
  await browser(async (p) => {
    await p.open(ownerURL);
    await toEdit(p);
    await p.js(`(document.querySelector('[data-pick=plan][data-id="${scene.id}"]') || { click() {} }).click()`); await wait(700);
    ownerTools = JSON.parse(await p.js(`JSON.stringify([...document.querySelectorAll('[data-ptool]')].map((b) => b.dataset.ptool))`));
    check("the owner's tool rail is there", ownerTools.length > 8, ownerTools.join(","));

    // ---- several diagrams on one scene
    check("a scene with one diagram offers + New Diagram", (await p.js(`__q('[data-pdnew]')`)) === "ok", "no button");
    await wait(900);
    const field = await p.js(`(() => { const i = document.activeElement; return i && i.classList.contains('planrename') ? i.placeholder : ''; })()`);
    check("…made and opened, its name asked for at once (placeholder Diagram 2)", field === "Diagram 2", field);
    await p.js(`(() => { const i = document.activeElement; i.value = 'Reverse'; i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' })); })()`); await wait(900);
    check("…named Reverse, the second tab, open", JSON.stringify(await p.js(`__tabs()`)) === JSON.stringify(["Diagram 1", "Reverse"]) && (await p.js(`document.querySelector('.pdtab.on').textContent.trim()`)) === "Reverse", JSON.stringify(await p.js(`__tabs()`)));
    await p.js(`document.querySelector('[data-pdtab]').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 400, clientY: 100 }))`); await wait(300);
    check("a tab's menu: Rename, Duplicate, Move, Delete", /Rename….*Duplicate.*Move Right.*Delete…/.test(await p.js(`__menu()`)), await p.js(`__menu()`));
    await p.js(`__m('Duplicate')`); await wait(900);
    await p.js(`(() => { const i = document.activeElement; if (i && i.tagName === 'INPUT') i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); })()`); await wait(400);
    check("Duplicate copies the first, pieces and all", (await p.js(`__tabs()`)).length === 3 && (await p.js(`shotlisterPlan.els().length`)) === els.length, `${JSON.stringify(await p.js(`__tabs()`))} ${await p.js(`shotlisterPlan.els().length`)}`);
    await p.js(`__q('[data-pdmenu]')`); await wait(300); await p.js(`__m('Move Left')`); await wait(800);
    check("Move Left moves it", JSON.stringify(await p.js(`__tabs()`)) === JSON.stringify(["Diagram 1", "Diagram 2", "Reverse"]), JSON.stringify(await p.js(`__tabs()`)));
    await p.js(`__q('[data-pdmenu]')`); await wait(300); await p.js(`__m('Delete…')`); await wait(300);
    check("Delete asks first, with what goes", /Delete Diagram 2\? 7 pieces on it go with it/.test(await p.js(`__menu()`)), await p.js(`__menu()`));
    await p.js(`__m('Delete')`); await wait(900);
    check("…and deletes it", JSON.stringify(await p.js(`__tabs()`)) === JSON.stringify(["Diagram 1", "Reverse"]), JSON.stringify(await p.js(`__tabs()`)));
    await p.js(`__q('[data-pundo]')`); await wait(1200);
    check("Undo brings it back, in its place", JSON.stringify(await p.js(`__tabs()`)) === JSON.stringify(["Diagram 1", "Diagram 2", "Reverse"]), JSON.stringify(await p.js(`__tabs()`)));
    await p.shot("portaldiagram-tabs.png");
    check("Print takes every drawn diagram of the scene", (await p.js(`shotlisterPlan.printIds().length`)) === 2, String(await p.js(`JSON.stringify(shotlisterPlan.printIds())`)));
    await p.js(`document.querySelector('[data-pdtab]').click()`); await wait(800);

    // ---- one Colour for several, Send / Copy to Set, Own Label
    await p.js(pickWhere(`(e) => e.kind === 'arrow' || e.kind === 'text' || e.lamp_name === 'Fill'`)); await wait(400);
    await more(p);
    check("several picked: More has Colour, Send to Set, Copy to Set", /Colour.*Send to Set.*Copy to Set/.test(await p.js(`__menu()`)), await p.js(`__menu()`));
    await p.js(`__m('Colour')`); await wait(300); await p.js(`__m('Red')`); await wait(700);
    const reds = await p.js(`shotlisterPlan.els().filter((e) => shotlisterPlan.picks().includes(e.id)).map((e) => e.color).join(',')`);
    check("…Colour paints them all, one step", reds === "#E5484D,#E5484D,#E5484D" && (await p.js(`shotlisterPlan.state().undo`)) === "Change Colour", reds);
    await more(p); await p.js(`__m('Copy to Set')`); await wait(800);
    check("Copy to Set leaves them and puts copies in Set", (await p.js(`shotlisterPlan.els().filter((e) => e.layer === 'set' && ['arrow','text','light'].includes(e.kind)).length`)) === 3, await p.js(`JSON.stringify(shotlisterPlan.els().map((e) => [e.kind, e.layer]))`));
    await p.js(pickWhere(`(e) => e.kind === 'arrow' && e.layer === 'plot'`)); await wait(300);
    await more(p); await p.js(`__m('Send to Set')`); await wait(800);
    check("Send to Set moves one across", (await p.js(`shotlisterPlan.els().filter((e) => e.kind === 'arrow' && e.layer === 'plot').length`)) === 0, "still on the plot");
    await p.js(pickWhere(`(e) => e.kind === 'light' && e.layer === 'plot'`)); await wait(400);
    await p.js(`__q('.planfloat [data-pa=sharelabel]')`); await wait(700);
    await p.js(pickWhere(`(e) => e.kind === 'light' && e.layer === 'plot'`)); await wait(400);
    await more(p);
    const own = await p.js(`__m('Own Label')`); await wait(700);
    check("Own Label for several takes them off a shared label", own === "ok" && (await p.js(`shotlisterPlan.els().filter((e) => e.kind === 'light' && e.layer === 'plot' && e.tie_to).length`)) === 0, own);

    // ---- a lamp's mark, sized by its corner
    await p.js(pickWhere(`(e) => e.lamp_name === 'Key'`)); await wait(400);
    const c = JSON.parse(await p.js(`JSON.stringify(shotlisterPlan.handles().find((h) => h.h === 'corner2') || null)`));
    check("a lamp drawn as a mark has corners to size it by", Boolean(c), "no corner handle");
    if (c) {
      await p.drag(c.x, c.y, c.x + 40, c.y + 40); await wait(900);
      const k = await p.js(`shotlisterPlan.els().find((e) => e.lamp_name === 'Key').mark_k`);
      check("…dragged out, its mark grows (mark_k)", k > 1.5, String(k));
    }

    // ---- Draw on Photo
    check("a picture is laid", (await p.js(layPicture)) === 200, "not kept"); await wait(900);
    await p.js(pickWhere(`(e) => e.kind === 'image'`)); await wait(400);
    check("a picture's bar has Draw on Photo", (await p.js(`__q('.planfloat [data-pa=drawon]')`)) === "ok", "no button"); await wait(800);
    check("…its own tools, Select lit", (await p.js(`[...document.querySelectorAll('[data-pphototool]')].map((b) => b.dataset.pphototool).join(',')`)) === "select,arrow,line,box,oval,draw,words,perspective" && (await p.js(`document.querySelector('[data-pphototool=select]').classList.contains('on')`)), await p.js(`[...document.querySelectorAll('[data-pphototool]')].map((b) => b.dataset.pphototool).join(',')`));
    check("…its foot bar: Photo, Guides, Color, Done", /Photo.*Guides.*Off.*Horizon.*\+ Point.*Color.*Done/.test(await p.js(`document.querySelector('.planfloat').textContent.replace(/\\s+/g, ' ')`)), await p.js(`document.querySelector('.planfloat').textContent`));
    await p.js(`__q('[data-pphototool=arrow]')`); await wait(200);
    let a = await onPic(p, 0.15, 0.8), b = await onPic(p, 0.4, 0.5);
    await p.drag(a[0], a[1], b[0], b[1]); await wait(600);
    await p.js(`__q('[data-pphotostylemenu]')`); await wait(300); await p.js(`__m('Both Ends')`); await wait(500);
    await p.js(`__q('[data-pphototool=box]')`); await wait(200);
    a = await onPic(p, 0.5, 0.3); b = await onPic(p, 0.7, 0.6);
    await p.drag(a[0], a[1], b[0], b[1]); await wait(600);
    await p.js(`__q('[data-pphototool=words]')`); await wait(200);
    a = await onPic(p, 0.65, 0.12);
    await p.mouse([["mousePressed", a[0], a[1]], ["mouseReleased", a[0], a[1]]]); await wait(500);
    await p.js(`(() => { const t = document.querySelector('.pphotowords'); t.value = 'Window light'; t.dispatchEvent(new Event('input')); t.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); })()`); await wait(700);
    await p.js(`__q('[data-pphototool=perspective]')`); await wait(700);
    let ph = JSON.parse(await p.js(`JSON.stringify(shotlisterPlan.photo())`));
    check("arrow, box and words drawn on it, in the engine's words", ph && ph.marks.map((m) => m.kind).join(",") === "arrow,box,words" && ph.marks[0].heads === 2 && ph.marks[2].text === "Window light", JSON.stringify(ph && ph.marks.map((m) => m.kind)));
    check("Perspective puts a horizon and a vanishing point on it", (await p.js(`shotlisterPlan.els().find((e) => e.kind === 'image').perspective`)) === "0.4200:0.5000", await p.js(`shotlisterPlan.els().find((e) => e.kind === 'image').perspective`));
    await p.shot("portaldiagram-photo.png");
    await p.js(`__q('[data-pphototool=select]')`); await wait(200);
    a = await onPic(p, 0.5, 0.45);
    await p.mouse([["mousePressed", a[0], a[1]], ["mouseReleased", a[0], a[1]]]); await wait(400);
    check("Select picks the box and its bar names it", /^Box/.test(await p.js(`document.querySelector('.planfloat').textContent.trim()`)), await p.js(`document.querySelector('.planfloat').textContent.trim()`));
    await p.key("Backspace"); await wait(600);
    check("Delete takes the mark, never the picture", (await p.js(`shotlisterPlan.photo().marks.length`)) === 2 && (await p.js(`shotlisterPlan.els().some((e) => e.kind === 'image')`)), String(await p.js(`shotlisterPlan.photo().marks.length`)));
    await p.js(`__q('[data-pphotoundo]')`); await wait(800);
    check("Undo on the tool bar brings it back", (await p.js(`shotlisterPlan.photo().marks.length`)) === 3, String(await p.js(`shotlisterPlan.photo().marks.length`)));
    await p.js(`__q('[data-pphotodone]')`); await wait(700);
    check("Done goes back to the plan, the picture picked", (await p.js(`shotlisterPlan.photo()`)) === null && (await p.js(`shotlisterPlan.picks().length`)) === 1, "still drawing");
    // Attach to Photo: an arrow laid on the plan over the picture comes onto it.
    await p.js(`(() => { const e = shotlisterPlan.els().find((x) => x.kind === 'image'); shotlisterPlan.edit({ op: 'add', els: [{ kind: 'arrow', x: e.x - 0.5, y: e.y, x2: e.x + 0.5, y2: e.y + 0.3 }] }); })()`); await wait(700);
    await p.js(pickWhere(`(e) => e.kind === 'image'`)); await wait(400);
    await more(p);
    const att = await p.js(`__m('Attach to Photo')`); await wait(900);
    check("Attach to Photo moves a mark lying on it onto it", att === "ok" && (await p.js(`shotlisterPlan.els().find((e) => e.kind === 'image').marks.split(';').length`)) === 4, att);
    check("no page errors (owner)", p.thrown.length === 0, p.thrown.slice(0, 2).join(" | "));
  });
  // Read again from the server: every edit above was kept.
  await browser(async (p) => {
    await p.open(ownerURL);
    await p.js(`(document.querySelector('[data-pick=plan][data-id="${scene.id}"]') || { click() {} }).click()`); await wait(700);
    check("read again: three tabs, in order, kept by the server", JSON.stringify(await p.js(`__tabs()`)) === JSON.stringify(["Diagram 1", "Diagram 2", "Reverse"]), JSON.stringify(await p.js(`__tabs()`)));
    check("…the photo's marks and guides kept", (await p.js(`(() => { const e = shotlisterPlan.els().find((x) => x.kind === 'image'); return e.marks.split(';').length === 4 && e.perspective === '0.4200:0.5000'; })()`)) === true, await p.js(`JSON.stringify(shotlisterPlan.els().find((x) => x.kind === 'image'))`));
  });

  // ================================================================ a link
  say("\nA visitor on the share link");
  check("Editable by Link switched on (his switch)", (await putJson(asOwner(`/f/${FILM}/api/diagram/settings`), { publicEdit: true })).status === 200, "not 200");
  await browser(async (p) => {
    await p.open(visitorURL);
    check("the visitor is offered Edit", (await p.js(`!!document.querySelector('[data-pedit]')`)) === true, "no Edit");
    await toEdit(p);
    await p.js(`(document.querySelector('[data-pick=plan][data-id="${scene.id}"]') || { click() {} }).click()`); await wait(700);
    const tools = JSON.parse(await p.js(`JSON.stringify([...document.querySelectorAll('[data-ptool]')].map((b) => b.dataset.ptool))`));
    check("…the same tools as the owner, not fewer", JSON.stringify(tools) === JSON.stringify(ownerTools), `${tools.length} vs ${ownerTools.length}`);
    check("…and the same head: Undo, View, Copy, Export, Present, Done", /Undo.*Redo.*View.*Copy.*Export.*Present.*Done/.test(await p.js(`document.querySelector('.planacts').textContent.replace(/\\s+/g, ' ')`)), await p.js(`document.querySelector('.planacts').textContent`));
    check("…but not his switch or his Link Edits", (await p.js(`!document.querySelector('[data-plink], [data-plinkedits]')`)) === true, "shown to a visitor");
    await p.js(pickWhere(`(e) => e.lamp_name === 'Fill' && e.layer === 'plot'`)); await wait(400);
    const c = JSON.parse(await p.js(`JSON.stringify(shotlisterPlan.handles().find((h) => h.h === 'corner2') || null)`));
    if (c) { await p.drag(c.x, c.y, c.x + 40, c.y + 40); await wait(1500); }
    check("the visitor sizes a lamp", (await p.js(`shotlisterPlan.els().find((e) => e.lamp_name === 'Fill' && e.layer === 'plot').mark_k`)) > 1.5, "not grown");
    await p.js(`__q('[data-pdnew]')`); await wait(900);
    await p.js(`(() => { const i = document.activeElement; i.value = 'Visitor'; i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' })); })()`); await wait(900);
    check("the visitor makes a diagram", (await p.js(`__tabs()`)).includes("Visitor"), JSON.stringify(await p.js(`__tabs()`)));
    await p.js(`__q('[data-pdmenu]')`); await wait(300); await p.js(`__m('Delete…')`); await wait(300); await p.js(`__m('Delete')`); await wait(1500);
    check("…and deletes it, asked first like him", !(await p.js(`__tabs()`)).includes("Visitor"), JSON.stringify(await p.js(`__tabs()`)));
    await p.js(`document.querySelector('[data-pdtab]').click()`); await wait(800);
    await p.js(pickWhere(`(e) => e.kind === 'image'`)); await wait(400);
    await p.js(`__q('.planfloat [data-pa=drawon]')`); await wait(800);
    await p.js(`__q('[data-pphototool=line]')`); await wait(200);
    const a = await onPic(p, 0.1, 0.9), b = await onPic(p, 0.9, 0.9);
    await p.drag(a[0], a[1], b[0], b[1]); await wait(1500);
    check("the visitor draws on the photo", (await p.js(`shotlisterPlan.photo().marks.length`)) === 5, String(await p.js(`shotlisterPlan.photo().marks.length`)));
    await p.shot("portaldiagram-visitor.png");
    check("no page errors (visitor)", p.thrown.length === 0, p.thrown.slice(0, 2).join(" | "));
  }, { share: true });
  // The server's side of the same visitor.
  const sceneDiagrams = JSON.parse(run(["view"])[0]);
  void sceneDiagrams;
  const wipe = await (await putJson(`${H}/f/${FILM}/api/diagram?k=${KEY}`, { scene: scene.id, ops: [{ op: { op: "clear" } }] }, { ...SHARE, "x-diagram-me": "checker01" })).json();
  check("a link's Clear without the page asking first is skipped", (wipe.skipped || []).some((s) => /asks/.test(s)), JSON.stringify(wipe));
  const listed = await (await fetch(asOwner(`/f/${FILM}/api/diagram/linkedits`))).json();
  const mine = (listed.edits || []).find((x) => (x.did || []).includes("Resize"));
  check("his Link Edits list says who, when and what", Boolean(mine) && /^Link visitor/.test(mine.who) && /T/.test(mine.at) && mine.undo.length > 0, JSON.stringify((listed.edits || []).map((x) => [x.who, x.did])));
  check("…and nobody on the link can read it", (await fetch(`${H}/f/${FILM}/api/diagram/linkedits?k=${KEY}`, { headers: SHARE })).status !== 200, "a visitor read it");
  let slowed = false;
  for (let i = 0; i < 130 && !slowed; i++) {
    const r = await putJson(`${H}/f/${FILM}/api/diagram?k=${KEY}`, { scene: scene.id, ops: [{ op: { op: "settings", set: { grid: true } } }] }, { ...SHARE, "x-diagram-me": "hammer001" });
    if (r.status === 429) slowed = true;
  }
  check("too many batches a minute from one visitor are slowed (429)", slowed, "never slowed");

  // ================================================================ his Undo
  say("\nHis history of link edits");
  await browser(async (p) => {
    await p.open(ownerURL);
    await p.js(`(document.querySelector('[data-pick=plan][data-id="${scene.id}"]') || { click() {} }).click()`); await wait(700);
    check("Link Edits is beside his switch", (await p.js(`__q('[data-plinkedits]')`)) === "ok", "no button"); await wait(900);
    const rows = await p.js(`[...document.querySelectorAll('.plinkrow')].map((r) => r.textContent.replace(/\\s+/g, ' ').trim())`);
    check("…listing the visitor's edits, newest first", rows.length >= 3 && rows.some((r) => /Link visitor .*Resize/.test(r)), JSON.stringify(rows.slice(0, 4)));
    await p.shot("portaldiagram-linkedits.png");
    const i = await p.js(`[...document.querySelectorAll('.plinkrow')].findIndex((r) => /Resize/.test(r.textContent))`);
    await p.js(`document.querySelectorAll('.plinkrow')[${i}].querySelector('[data-plinkundo]').click()`); await wait(1500);
    check("…his Undo takes the visitor's resize back", (await p.js(`shotlisterPlan.els().find((e) => e.lamp_name === 'Fill' && e.layer === 'plot').mark_k`)) === 1, String(await p.js(`shotlisterPlan.els().find((e) => e.lamp_name === 'Fill' && e.layer === 'plot').mark_k`)));
    check("no page errors (his list)", p.thrown.length === 0, p.thrown.slice(0, 2).join(" | "));
  });

  // ================================================================ switched off
  say("\nEditable by Link switched off");
  await browser(async (p) => {
    await p.open(visitorURL);
    await toEdit(p);
    check("Editable by Link switched off", (await putJson(asOwner(`/f/${FILM}/api/diagram/settings`), { publicEdit: false })).status === 200, "not 200");
    await p.js(pickWhere(`(e) => e.kind === 'cast'`)); await wait(300);
    await p.js(`shotlisterPlan.edit({ op: 'move', ids: shotlisterPlan.picks(), dx: 1, dy: 0 })`); await wait(1500);
    check("the visitor's next edit is refused and the tools are put away", (await p.js(`!document.querySelector('.planwell.editing')`)) === true && /switched off/.test(await p.js(`document.querySelector('.plantoast').textContent`)), await p.js(`document.querySelector('.plantoast').textContent`));
    check("…and the server never kept it", (await (await putJson(`${H}/f/${FILM}/api/diagram?k=${KEY}`, { scene: scene.id, ops: [{ op: { op: "settings", set: { grid: true } } }] }, SHARE)).status) === 403, "not refused");
  }, { share: true });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} -sTCP:LISTEN | xargs -r kill -9`], { stdio: "ignore" });
}
say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
