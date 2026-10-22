#!/usr/bin/env -S node --experimental-websocket
/**
 * **The Schedule's Shooting Order, on the portal** — his ask, 2026-10-05,
 * after the Mac's: each day as its shots in the order they are shot, and an
 * editor drags them into place.
 *
 * - the door `PUT api/shootorder` moves a shot, keeps one log, and says no
 *   to a viewer and to nonsense;
 * - the page's Shooting Order switch draws each day's shots in order;
 * - a mouse drag within a day, and onto another day, moves the shot there,
 *   and the order is still there when the page is opened again;
 * - a finger held still, then moved, does the same on a phone's width;
 * - a Mac replaying the bucket sees the same order.
 *
 *     hub/shootorder.mjs
 *
 * The scratch film is made by the Mac's connector (`mcp/`), put in a
 * throwaway bucket, and served by a hub of its own on 8793. Screenshots land
 * in /tmp (or $SHOTS). Nothing here touches a real film or the real bucket.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, mkdirSync, readdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "05b07c4ec1ec00000000000000000002";
const OWNER = "owner@example.com";
const PORT = 8793;
const DEBUG = 9349;
const H = `http://127.0.0.1:${PORT}`;
const MANIFEST = { format: 1, project: FILM, title: "Order Check", engine: "0.1.0" };
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

// ---- the Mac's connector, on a folder ---------------------------------------
const PATH = `${process.env.HOME}/.cargo/bin:/opt/homebrew/bin:${process.env.PATH}`;
say("Building the Mac's connector and the hub's engine…");
const built = spawnSync("cargo", ["build", "--quiet", "--manifest-path", join(ROOT, "mcp/Cargo.toml")],
  { env: { ...process.env, PATH } });
if (built.status !== 0) { say(`the connector would not build\n${built.stderr}`); process.exit(1); }
if (spawnSync(join(HERE, "build.sh"), [], { stdio: "ignore", env: { ...process.env, PATH } }).status !== 0) {
  say("the hub's engine would not build — nothing below would mean anything"); process.exit(1);
}
const MCP = join(ROOT, "mcp/target/debug/shotlister-mcp");

function folder(box, logs) {
  const path = join(box, "Order Check.shotlist");
  mkdirSync(join(path, "changes"), { recursive: true });
  writeFileSync(join(path, "manifest.json"), JSON.stringify(MANIFEST));
  for (const [name, text] of logs) writeFileSync(join(path, "changes", name), text);
  return path;
}

function connector(path, calls, device) {
  const lines = [["open_project", { path }], ...calls].map(([name, args], i) =>
    JSON.stringify({ jsonrpc: "2.0", id: i + 1, method: "tools/call", params: { name, arguments: args } }));
  const run = spawnSync(MCP, [], { input: lines.join("\n") + "\n", env: { ...process.env, SHOTLISTER_DEVICE: device } });
  return run.stdout.toString().trim().split("\n").map((l) => JSON.parse(l)).map((r) =>
    r.error ? { error: r.error.message } : r.result.content.map((c) => c.text).join("\n"));
}

const box = mkdtempSync(join(tmpdir(), "order-film-"));
const made = folder(box, []);
const said = connector(made, [
  ["add_scene", { number: "1" }], ["add_shot", { scene: "1" }], ["add_shot", { scene: "1" }],
  ["add_scene", { number: "2" }], ["add_shot", { scene: "2" }], ["add_shot", { scene: "2" }],
  ["add_scene", { number: "3" }], ["add_shot", { scene: "3" }], ["add_shot", { scene: "3" }],
  ["add_day", { date: "2026-07-09" }], ["add_day", { date: "2026-07-10" }],
  ["schedule_scene", { scenes: ["1", "2"], day: "1" }],
  ["schedule_scene", { scenes: ["3"], day: "2" }],
  ["update_shot", { shot: "1A", shot_done: true }],
], "order-check-mac");
const refused = said.find((s) => s && s.error);
if (refused) { say(`the scratch film could not be made: ${refused.error}`); process.exit(1); }
const seeded = readdirSync(join(made, "changes")).filter((n) => n.endsWith(".log"));

const state = mkdtempSync(join(tmpdir(), "order-state-"));
say("Putting the scratch film in a local bucket…");
const W = join(HERE, "node_modules/.bin/wrangler");
const put = (key, file) => spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
  "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
put(`p/${FILM}/manifest.json`, join(made, "manifest.json"));
for (const name of seeded) put(`p/${FILM}/logs/${name}`, join(made, "changes", name));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

const logs = async () => (await (await fetch(`${H}/f/${FILM}/api/state?as=${OWNER}`)).json()).logs.map((l) => l.name);
const door = (body, who = OWNER) => fetch(`${H}/f/${FILM}/api/shootorder?as=${encodeURIComponent(who)}`, {
  method: "PUT", headers: { "content-type": "application/json" },
  body: typeof body === "string" ? body : JSON.stringify(body),
});
/** What a Mac replaying the bucket says each day runs. */
async function macRuns() {
  const pulled = [];
  for (const name of await logs()) pulled.push([name, await (await fetch(`${H}/f/${FILM}/api/log/${name}?as=${OWNER}`)).text()]);
  const mac = folder(mkdtempSync(join(box, "mac-")), pulled);
  const [, schedule] = connector(mac, [["schedule", {}]], "order-check-other-mac");
  return (String(schedule).match(/"run":\[[^\]]*\]/g) || []).join(" ");
}

/** One headless tab, driven over its own line. */
async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1200,800", "about:blank"], { stdio: "ignore" });
  let line;
  try {
    let up = false;
    for (let i = 0; i < 80 && !up; i++) {
      await wait(150);
      try { up = (await fetch(`http://127.0.0.1:${DEBUG}/json/version`)).ok; } catch {}
    }
    if (!up) throw new Error("the browser never answered — is Playwright's Chromium cached?");
    const t = await (await fetch(`http://127.0.0.1:${DEBUG}/json/new?about:blank`, { method: "PUT" })).json();
    line = new WS(t.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
    await new Promise((y, n) => { line.once("open", y); line.once("error", n); });
    let id = 0;
    const waiting = new Map();
    line.on("message", (m) => {
      const got = JSON.parse(m);
      if (got.id && waiting.has(got.id)) { waiting.get(got.id)(got); waiting.delete(got.id); }
    });
    const ask = (method, params = {}) =>
      new Promise((y) => { const n = ++id; waiting.set(n, y); line.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable");
    const js = async (expression) => {
      const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return got.result?.result?.value;
    };
    const size = (width, height, mobile) => ask("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile });
    const go = async (url) => { await ask("Page.navigate", { url }); await wait(3500); };
    const mouse = (type, x, y) => ask("Input.dispatchMouseEvent", {
      type, x, y, button: "left", buttons: type === "mouseReleased" ? 0 : 1, clickCount: type === "mouseMoved" ? 0 : 1,
    });
    const shot = async (name) => {
      const got = await ask("Page.captureScreenshot", { format: "png" });
      writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
      say(`  → ${join(shots, name)}`);
    };
    return await run({ ask, js, size, go, mouse, shot });
  } finally {
    if (line) line.close();
    proc.kill();
  }
}

const RUNS = `JSON.stringify([...document.querySelectorAll(".lane[data-day]")].map((l) => [...l.querySelectorAll(".runrow")].map((r) => r.dataset.run)))`;
const AT = (n) => `(() => { const r = document.querySelector('.runrow[data-run="${n}"]'); if (!r) return null; const b = r.getBoundingClientRect(); return JSON.stringify({ x: b.left + b.width / 2, y: b.top + b.height / 2, top: b.top, h: b.height }); })()`;

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  say("\n  the door");
  let r = await door({ shot: "1A", day: "Day 1", position: 1 }, "stranger@example.com");
  check("a person not on the film may not move a shot", r.status >= 400 && r.status < 500, `status ${r.status}`);
  check("nonsense is refused", (await door("{not json")).status === 400 && (await door({ shot: "1A", day: "Day 1", position: 0 })).status === 400, "taken");
  const before = (await logs()).length;
  r = await door({ shot: "2B", day: "Day 1", position: 1 });
  const body = await r.json().catch(() => ({}));
  check("an editor moves 2B to the top of Day 1", r.ok && /Day 1 \(2026-07-09\) runs: 2B, 1A, 1B, 2A\./.test(body.said || ""), JSON.stringify(body));
  check("…keeping one log", (await logs()).length === before + 1, "not one");

  await browser(async ({ ask, js, size, go, mouse, shot }) => {
    say("\n  the page");
    await size(1200, 800, false);
    await go(`${H}/f/${FILM}/schedule`);
    check("the Schedule opens on its scene strips", (await js(`document.querySelectorAll(".stripe").length`)) > 0, "no strips");
    await js(`document.querySelector('[data-shootorder="1"]').click()`);
    await wait(500);
    check("Shooting Order draws each day's shots in order", (await js(RUNS)) === JSON.stringify([["2B", "1A", "1B", "2A"], ["3A", "3B"]]), await js(RUNS));
    check("…a shot marked Shot crossed out", await js(`document.querySelector('.runrow[data-run="1A"]').classList.contains("struck")`), "not struck");
    await shot("shootorder-1.png");

    // 2A, last of Day 1, to the top of it.
    let from = JSON.parse(await js(AT("2A"))), to = JSON.parse(await js(AT("2B")));
    await mouse("mousePressed", from.x, from.y);
    for (let i = 1; i <= 12; i++) await mouse("mouseMoved", from.x, from.y + (to.top + 4 - from.y) * (i / 12));
    await shot("shootorder-2-dragging.png");
    await mouse("mouseReleased", from.x, to.top + 4);
    await wait(3000);
    check("a shot dragged to the top of its day goes there", (await js(RUNS)) === JSON.stringify([["2A", "2B", "1A", "1B"], ["3A", "3B"]]), await js(RUNS));

    // 3B, from Day 2, between 1A and 1B on Day 1.
    from = JSON.parse(await js(AT("3B"))); to = JSON.parse(await js(AT("1B")));
    await mouse("mousePressed", from.x, from.y);
    for (let i = 1; i <= 14; i++) await mouse("mouseMoved", from.x, from.y + (to.top + 4 - from.y) * (i / 14));
    await mouse("mouseReleased", from.x, to.top + 4);
    await wait(3000);
    check("a shot dragged onto another day lands where it was let go", (await js(RUNS)) === JSON.stringify([["2A", "2B", "1A", "3B", "1B"], ["3A"]]), await js(RUNS));

    // A press that does not travel moves nothing.
    from = JSON.parse(await js(AT("1A")));
    await mouse("mousePressed", from.x, from.y);
    await mouse("mouseReleased", from.x, from.y);
    await wait(800);
    check("a click moves nothing", (await js(RUNS)) === JSON.stringify([["2A", "2B", "1A", "3B", "1B"], ["3A"]]), await js(RUNS));

    await go(`${H}/f/${FILM}/schedule`);
    check("opened again, still Shooting Order, still that order", (await js(RUNS)) === JSON.stringify([["2A", "2B", "1A", "3B", "1B"], ["3A"]]), await js(RUNS));
    await shot("shootorder-3.png");

    say("\n  a phone");
    await size(390, 844, true);
    await go(`${H}/f/${FILM}/schedule`);
    check("the phone draws Shooting Order too", (await js(RUNS)) === JSON.stringify([["2A", "2B", "1A", "3B", "1B"], ["3A"]]), await js(RUNS));
    await ask("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
    const touch = (type, x, y) => ask("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y }] });
    // A finger that moves at once is a scroll, and moves nothing.
    from = JSON.parse(await js(AT("3A"))); to = JSON.parse(await js(AT("2A")));
    await touch("touchStart", from.x, from.y);
    for (let i = 1; i <= 8; i++) await touch("touchMove", from.x, from.y + (to.top + 4 - from.y) * (i / 8));
    await touch("touchEnd");
    await wait(1200);
    check("a finger moving at once scrolls, and moves no shot", (await js(RUNS)) === JSON.stringify([["2A", "2B", "1A", "3B", "1B"], ["3A"]]), await js(RUNS));
    // Held still first, it lifts the shot.
    from = JSON.parse(await js(AT("3A"))); to = JSON.parse(await js(AT("2A")));
    await touch("touchStart", from.x, from.y);
    await wait(650);
    for (let i = 1; i <= 10; i++) await touch("touchMove", from.x, from.y + (to.top + 4 - from.y) * (i / 10));
    await touch("touchEnd");
    await wait(3000);
    check("a finger held still, then moved, carries the shot", (await js(RUNS)) === JSON.stringify([["3A", "2A", "2B", "1A", "3B", "1B"], []]), await js(RUNS));
    await shot("shootorder-4-phone.png");
  });

  say("\n  a Mac");
  const runs = await macRuns();
  check("a Mac replaying the bucket sees the same order", runs === `"run":["3A","2A","2B","1A","3B","1B"] "run":[]`, runs);
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
