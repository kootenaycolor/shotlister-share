#!/usr/bin/env -S node --experimental-websocket
/**
 * **A shot's Shoot Day, picked on the portal** (Ref 1570) — the Mac's Day
 * menu: an editor presses a shot's Day in the shot list and gets the film's
 * days and Not Scheduled; the shot goes to the end of that day's order, its
 * scene, number and letter unchanged. The door is `PUT api/shootorder` with no
 * place (end of the day) or `day: ""` (off every day) — the connector's
 * `schedule_shot`, so an AI, the apps and the portal make the one change.
 *
 *     hub/shootday.mjs
 *
 * Made like `shootorder.mjs`: a scratch film by the Mac's connector, a hub of
 * its own on 8861, screenshots in /tmp (or $SHOTS).
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
const FILM = "05b07c4ec1ec00000000000000000007";
const OWNER = "owner@example.com";
const PORT = 8861;
const DEBUG = 9381;
const H = `http://127.0.0.1:${PORT}`;
const MANIFEST = { format: 1, project: FILM, title: "Day Check", engine: "0.1.0" };
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
  const path = join(box, "Day Check.shotlist");
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

const box = mkdtempSync(join(tmpdir(), "day-film-"));
const made = folder(box, []);
const said = connector(made, [
  ["add_scene", { number: "1" }], ["add_shot", { scene: "1" }], ["add_shot", { scene: "1" }],
  ["add_scene", { number: "2" }], ["add_shot", { scene: "2" }], ["add_shot", { scene: "2" }],
  ["add_scene", { number: "3" }], ["add_shot", { scene: "3" }], ["add_shot", { scene: "3" }],
  ["add_day", { date: "2026-07-09" }], ["add_day", { date: "2026-07-10" }],
  ["schedule_scene", { scenes: ["1", "2"], day: "1" }],
  ["schedule_scene", { scenes: ["3"], day: "2" }],
  ["update_shot", { shot: "1A", shot_done: true }],
], "day-check-mac");
const refused = said.find((s) => s && s.error);
if (refused) { say(`the scratch film could not be made: ${refused.error}`); process.exit(1); }
const seeded = readdirSync(join(made, "changes")).filter((n) => n.endsWith(".log"));

const state = mkdtempSync(join(tmpdir(), "day-state-"));
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
  const [, schedule] = connector(mac, [["schedule", {}]], "day-check-other-mac");
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

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  say("\n  the door");
  let r = await door({ shot: "1A", day: "Day 2" }, "stranger@example.com");
  check("a person not on the film may not change a shot's day", r.status >= 400 && r.status < 500, `status ${r.status}`);
  check("a day of nothing with a place is nonsense",
    (await door({ shot: "1A", day: "", position: 2 })).status === 400, "taken");
  const before = (await logs()).length;
  r = await door({ shot: "1A", day: "Day 2" });
  let body = await r.json().catch(() => ({}));
  check("an editor puts 1A on Day 2, with no place named: the end of the day",
    r.ok && /Day 2 \(2026-07-10\) runs: 3A, 3B, 1A\./.test(body.said || ""), JSON.stringify(body));
  check("…keeping one log", (await logs()).length === before + 1, "not one");
  r = await door({ shot: "1A", day: "" });
  body = await r.json().catch(() => ({}));
  check("an empty day takes it off every day", r.ok && /1A off the schedule\./.test(body.said || ""), JSON.stringify(body));
  r = await door({ shot: "1A", day: "Day 1" });
  body = await r.json().catch(() => ({}));
  check("…and a pick after it puts it at the end of Day 1, scene and number unchanged",
    r.ok && /Day 1 \(2026-07-09\) runs: 1B, 2A, 2B, 1A\./.test(body.said || ""), JSON.stringify(body));
  r = await door({ shot: "1A", day: "Day 1", position: 50 });
  body = await r.json().catch(() => ({}));
  check("a place far past the last is the last, not the first (Ref 1575)",
    r.ok && /Day 1 \(2026-07-09\) runs: 1B, 2A, 2B, 1A\./.test(body.said || ""), JSON.stringify(body));
  check("a day nobody has is refused, saying which there are",
    /There is no shoot day/.test(await (await door({ shot: "1A", day: "Day 9" })).text()), "taken");

  const DAY_OF = (n) => `(() => { const r = [...document.querySelectorAll('.trow, .lrow')].find((x) => x.querySelector('.no').textContent.trim() === '${n}'); return r ? r.querySelector('.daybtn, .td-day').textContent.trim() : null; })()`;
  const CELL = (n) => `(() => { const r = [...document.querySelectorAll('.trow')].find((x) => x.querySelector('.no').textContent.trim() === '${n}'); const b = r && r.querySelector('.daybtn'); if (!b) return null; b.scrollIntoView({ inline: 'center', block: 'center' }); const q = b.getBoundingClientRect(); return JSON.stringify({ x: q.left + q.width / 2, y: q.top + q.height / 2 }); })()`;
  const ITEM = (label) => `(() => { const b = [...document.querySelectorAll('.dayitem')].find((x) => x.textContent.trim().startsWith(${JSON.stringify(label)})); if (!b) return null; const q = b.getBoundingClientRect(); return JSON.stringify({ x: q.left + q.width / 2, y: q.top + q.height / 2 }); })()`;
  const MENU = `JSON.stringify([...document.querySelectorAll('.daymenu .dayitem')].map((b) => [b.textContent.trim(), b.classList.contains('on')]))`;

  await browser(async ({ ask, js, size, go, mouse, shot }) => {
    const press = async (p) => { await mouse("mousePressed", p.x, p.y); await mouse("mouseReleased", p.x, p.y); };
    say("\n  the shot list, as an editor");
    await size(1300, 800, false);
    await go(`${H}/f/${FILM}/shotlist`);
    const buttons = await js(`document.querySelectorAll('.td-day .daybtn').length`);
    check("every shot's Day is a button to press", buttons === 6, String(buttons));
    check("…reading the day it is on", (await js(DAY_OF("1A"))) === "Day 1" && (await js(DAY_OF("3A"))) === "Day 2", `${await js(DAY_OF("1A"))} / ${await js(DAY_OF("3A"))}`);

    let at = JSON.parse(await js(CELL("1B")));
    await press(at);
    await wait(400);
    const menu = JSON.parse(await js(MENU));
    check("pressing the Day opens the days, then Not Scheduled",
      menu.length === 3 && /^Day 1 · /.test(menu[0][0]) && /^Day 2 · /.test(menu[1][0]) && menu[2][0] === "Not Scheduled", JSON.stringify(menu));
    check("…with the shot's own day ticked", menu[0][1] === true && menu[1][1] === false && menu[2][1] === false, JSON.stringify(menu));
    await shot("shootday-1-menu.png");
    await ask("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
    await wait(200);
    check("Escape puts it away", (await js(`document.querySelectorAll('.daymenu').length`)) === 0, "still there");
    await press(at);
    await wait(300);
    await press({ x: 40, y: 700 });
    await wait(200);
    check("a press anywhere else puts it away too", (await js(`document.querySelectorAll('.daymenu').length`)) === 0, "still there");

    await press(at);
    await wait(300);
    await press(JSON.parse(await js(ITEM("Day 2"))));
    await wait(3200);
    check("picking Day 2 puts the shot there", (await js(DAY_OF("1B"))) === "Day 2", await js(DAY_OF("1B")));
    await shot("shootday-2-picked.png");

    at = JSON.parse(await js(CELL("1B")));
    await press(at);
    await wait(300);
    await press(JSON.parse(await js(ITEM("Not Scheduled"))));
    await wait(3200);
    check("Not Scheduled takes it off its day", (await js(DAY_OF("1B"))) === "Not Scheduled", await js(DAY_OF("1B")));
    await shot("shootday-3-unscheduled.png");

    await go(`${H}/f/${FILM}/shotlist`);
    check("opened again, it is still off its day", (await js(DAY_OF("1B"))) === "Not Scheduled", await js(DAY_OF("1B")));

    say("\n  a phone");
    await size(390, 844, true);
    await go(`${H}/f/${FILM}/shotlist`);
    const lrows = await js(`document.querySelectorAll('.lrow .daybtn').length`);
    check("the phone's rows carry the same button", lrows === 6, String(lrows));
    await shot("shootday-4-phone.png");
  });

  say("\n  a Mac");
  const ran = await macRuns();
  check("a Mac replaying the bucket sees 1B on no day", !ran.includes('"1B"'), ran);

  say("\n  a viewer");
  const put = await fetch(`${H}/f/${FILM}/api/people?as=${OWNER}`, {
    method: "PUT", headers: { "content-type": "application/json" },
    body: JSON.stringify({ people: [{ email: "clara@example.com", role: "viewer" }], links: [] }),
  });
  check("a viewer is put on the film", put.ok, `status ${put.status}`);
  await browser(async ({ js, size, go }) => {
    await size(1300, 800, false);
    await go(`${H}/f/${FILM}/shotlist?as=clara@example.com`);
    const chips = await js(`document.querySelectorAll('.td-day .chip').length`);
    const btns = await js(`document.querySelectorAll('.daybtn').length`);
    check("a viewer sees the day, and no button", chips > 0 && btns === 0, `${chips} chips, ${btns} buttons`);
  });
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
