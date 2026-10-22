#!/usr/bin/env node
/**
 * **Projects Console's New Shoot, its shot-list step** (SL-1402) — the door
 * `POST /console/<film>/shoot`, knocked on the way the console knocks: the
 * console's token and JSON, no browser.
 *
 * - a preview says every step and keeps no log;
 * - a refusal says why, with 422, and keeps no log;
 * - the real press keeps one log, in the console's own name;
 * - pressed again it finds everything there and keeps nothing;
 * - and the log it kept is a film's ordinary change: the Mac's own connector,
 *   replaying every log in the bucket, sees the version, the section, the
 *   dated day and the pickup, and Shoot 1's day keeps the shot it got.
 *
 *     hub/shoot.mjs
 *
 * The scratch film is made by the Mac's connector (`mcp/`), put in a
 * throwaway bucket, and served by a hub of its own on 8794. Nothing here
 * touches a real film or the real bucket.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const FILM = "05b07c4ec1ec00000000000000000001";
const OWNER = "owner@example.com";
const TOKEN = "checking-token-not-a-secret";
const PORT = 8794;
const H = `http://127.0.0.1:${PORT}`;
const MANIFEST = { format: 1, project: FILM, title: "Shoot Check", engine: "0.1.0" };

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

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

/** A `.shotlist` folder holding these logs. */
function folder(box, logs) {
  const path = join(box, "Shoot Check.shotlist");
  mkdirSync(join(path, "changes"), { recursive: true });
  writeFileSync(join(path, "manifest.json"), JSON.stringify(MANIFEST));
  for (const [name, text] of logs) writeFileSync(join(path, "changes", name), text);
  return path;
}

/** Ask the connector, opened on `path`, one call after another; their answers. */
function connector(path, calls, device) {
  const lines = [["open_project", { path }], ...calls].map(([name, args], i) =>
    JSON.stringify({ jsonrpc: "2.0", id: i + 1, method: "tools/call", params: { name, arguments: args } }));
  const run = spawnSync(MCP, [], { input: lines.join("\n") + "\n", env: { ...process.env, SHOTLISTER_DEVICE: device } });
  return run.stdout.toString().trim().split("\n").map((l) => JSON.parse(l)).map((r) =>
    r.error ? { error: r.error.message } : r.result.content.map((c) => c.text).join("\n"));
}

const box = mkdtempSync(join(tmpdir(), "shoot-film-"));
const made = folder(box, []);
const said = connector(made, [
  ["add_scene", { number: "1" }], ["add_shot", { scene: "1" }], ["add_shot", { scene: "1" }],
  ["add_scene", { number: "2" }], ["add_shot", { scene: "2" }], ["add_shot", { scene: "2" }],
  ["add_scene", { number: "3" }],
  ["add_day", { date: "2026-07-09", name: "Shoot 1" }],
  ["schedule_scene", { scenes: ["1", "2"], day: "1" }],
  ["update_shot", { shot: "1A", shot_done: true }],
  // Typed by hand on the Mac, with a dash: the door's dot must find it.
  ["add_section", { title: "Shoot 3 – November 3" }],
], "shoot-check-mac");
const refused = said.find((s) => s && s.error);
if (refused) { say(`the scratch film could not be made: ${refused.error}`); process.exit(1); }
const seeded = readdirSync(join(made, "changes")).filter((n) => n.endsWith(".log"));

// ---- a bucket and a hub of its own ------------------------------------------
const state = mkdtempSync(join(tmpdir(), "shoot-state-"));
say("Putting the scratch film in a local bucket…");
const W = join(HERE, "node_modules/.bin/wrangler");
const put = (key, file) => spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
  "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
put(`p/${FILM}/manifest.json`, join(made, "manifest.json"));
for (const name of seeded) put(`p/${FILM}/logs/${name}`, join(made, "changes", name));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`], { cwd: HERE, stdio: "ignore" });

const door = (body, { film = FILM, method = "POST", token = TOKEN } = {}) =>
  fetch(`${H}/console/${film}/shoot`, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));
const logs = async () => (await (await fetch(`${H}/f/${FILM}/api/state?as=${OWNER}`)).json()).logs.map((l) => l.name);
const SHOOT = { date: "2026-11-03", name: "Shoot 3", pickups: ["1"] };

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }
  const before = await logs();
  check("the hub serves the scratch film", before.length === seeded.length, JSON.stringify(before));

  // ---- the door's own rules ----
  check("no token, no door", (await door(SHOOT, { token: "wrong" })).status === 401, "not 401");
  check("a film it does not have is 404", (await door(SHOOT, { film: "0000000000000000000000000000dead" })).status === 404, "not 404");
  check("it is asked with POST", (await door(null, { method: "GET" })).status === 405, "not 405");
  check("it is asked in JSON", (await door("{not json")).status === 400, "not 400");

  // ---- a preview ----
  let got = await door({ ...SHOOT, preview: true });
  check("a preview answers 200, ok, preview", got.status === 200 && got.body.ok === true && got.body.preview === true, JSON.stringify(got));
  const steps = got.body.steps || [];
  check("…saying the version first", steps[0] === "Save version “Before Shoot 3 setup”.", steps[0]);
  check("…finding the section typed with a dash", steps[1] === "Section “Shoot 3 – November 3” is already there.", steps[1]);
  check("…the day it would add", steps[2] === "Add Day 2: 2026-11-03, Shoot 3.", steps[2]);
  check("…and the pickup, keeping what Shoot 1 got",
    steps[3] === "Put scene 1 on Day 2: 1B. 1A is marked Shot and stays where it was got.", steps[3]);
  check("…with the film's name", got.body.film === "Shoot Check", got.body.film);
  check("a preview keeps no log", (await logs()).length === before.length, "a log appeared");

  // ---- a refusal ----
  got = await door({ ...SHOOT, pickups: ["1", "3"] });
  check("a refusal is 422 with its reason",
    got.status === 422 && got.body.ok === false && /Scene 3 has no shots.*Nothing was changed\.$/.test(got.body.why || ""), JSON.stringify(got));
  got = await door({ date: "Nov 3", name: "Shoot 3" });
  check("…a date it cannot read too", got.status === 422 && /YYYY-MM-DD/.test(got.body.why || ""), JSON.stringify(got));
  check("a refusal keeps no log", (await logs()).length === before.length, "a log appeared");

  // ---- the real press ----
  got = await door(SHOOT);
  check("the press answers 200, ok, not a preview", got.status === 200 && got.body.ok === true && got.body.preview === false, JSON.stringify(got));
  check("…in plain words", JSON.stringify(got.body.steps) === JSON.stringify([
    "Saved version “Before Shoot 3 setup”.",
    "Section “Shoot 3 – November 3” is already there.",
    "Day 2 is 2026-11-03, Shoot 3.",
    "Scene 1 is on Day 2: 1B. 1A is marked Shot and stayed where it was got.",
  ]), JSON.stringify(got.body.steps));
  check("…and the day and version as fields",
    got.body.day && got.body.day.day === "Day 2" && got.body.day.new === true && got.body.version === "Before Shoot 3 setup", JSON.stringify(got.body));
  const after = await logs();
  const fresh = after.filter((n) => !before.includes(n));
  check("the press keeps one log", fresh.length === 1, JSON.stringify(fresh));

  got = await door(SHOOT);
  check("pressed again, nothing to do", got.status === 200 && got.body.changes === false && got.body.version === null, JSON.stringify(got.body));
  check("…and no second log", (await logs()).length === after.length, "a log appeared");

  // ---- the way a Mac takes it in ----
  const pulled = [];
  for (const name of await logs()) {
    pulled.push([name, await (await fetch(`${H}/f/${FILM}/api/log/${name}?as=${OWNER}`)).text()]);
  }
  const mac = folder(mkdtempSync(join(box, "mac-")), pulled);
  const [, schedule, sections, versions] = connector(mac, [["schedule", {}], ["sections", {}], ["versions", {}]], "shoot-check-other-mac");
  check("a Mac replaying the bucket sees Day 2, dated and named",
    typeof schedule === "string" && schedule.includes('"day":"Day 2","date":"2026-11-03","name":"Shoot 3"'), schedule);
  check("…with the pickup on it", typeof schedule === "string" && schedule.includes('"run":["1B"]'), schedule);
  check("…and Shoot 1's day still holding what it got",
    typeof schedule === "string" && schedule.includes('"run":["1A","2A","2B"]'), schedule);
  check("…one section, not two", typeof sections === "string" && (sections.match(/"title"/g) || []).length === 1, sections);
  check("…and the version saved first", typeof versions === "string" && versions.includes("Before Shoot 3 setup"), versions);
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
