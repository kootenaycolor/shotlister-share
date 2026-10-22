#!/usr/bin/env node
/**
 * Checks for `hub/spec-sheets.py`, the helper inside `Move Spec Sheets.app`
 * and `Spec Sheet Switch.app` (2026-10-14).
 *
 * Against a small fake of the hub's four spec sheet doors on this machine,
 * in the shapes `src/studio.js` and `src/specsheet.js` answer with, and a
 * password made up here. The helper is pointed at the fake by
 * `SHOTLISTER_HUB_CONSOLE` and handed the password by
 * `SHOTLISTER_RELAY_TOKEN`, so nothing here reads the Keychain or reaches
 * the real hub.
 *
 *     node hub/specsheet-app.mjs
 */
import { createServer } from "node:http";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HELPER = join(dirname(fileURLToPath(import.meta.url)), "spec-sheets.py");
const PASSWORD = "made-up-checking-password-4e1d";
const CONFIRM = "move the spec sheets";

// ---------------------------------------------------------------- the fake

const sheet = (cams, lenses) => ({
  cameras: cams.map(([label, body]) => ({ label, body })),
  lenses: Array.from({ length: lenses }, (_, i) => ({ name: `Lens ${i}` })),
  notes: "", files: [],
});
const ROWS = [
  { row: "r1", title: "Halcyon · Shoot 1", project: "p1", fact: "spec_project", record: true,
    sheet: sheet([["A Cam", "ALEXA 35"], ["B Cam", "FX6"]], 6),
    flags: [{ level: "unplaced", field: "lenses", line: "Hawk 2x", why: "no lens pill matches this line" },
            { level: "unplaced", field: "luts", line: "x", why: "y" },
            { level: "note", field: "format", line: "", why: "matched" }] },
  { row: "r2", title: "Let's Bake", project: "p2", fact: "spec_project", record: true,
    sheet: sheet([["A Cam", "VENICE 2"]], 1), flags: [] },
  { row: "r3", title: "Orphan Sheet", project: "", fact: "spec_project", record: false,
    sheet: null, flags: [{ level: "unplaced", field: "sheet", line: "", why: "the row names no project" }] },
];
const written = {};          // project → fact value, the record side
let writes = 0;
let switchOn = false;
let mode = "ok";             // "ok" | "down" (503 on everything)
const confirms = [];

function lookReport() {
  return ROWS.map((r) => {
    const one = JSON.parse(JSON.stringify(r));
    if (one.record) {
      one.already = Boolean(written[one.project]);
      if (one.already) one.flags.push({ level: "note", field: "sheet", line: "", why: "the record has it already" });
    }
    return one;
  });
}

const server = createServer(async (req, res) => {
  const send = (status, body) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify(body)); };
  let raw = "";
  for await (const chunk of req) raw += chunk;
  if ((req.headers.authorization || "") !== `Bearer ${PASSWORD}`) return send(401, { problem: "Not the console's token." });
  if (mode === "down") return send(503, { problem: "The hub has no Notion key, so it cannot read the spec sheets." });
  const path = req.url;
  let said = {};
  try { said = raw ? JSON.parse(raw) : {}; } catch { return send(400, { problem: "That is not JSON." }); }

  if (path === "/console/studio/specsheet") {
    if (req.method === "GET") return send(200, { on: switchOn, at: "", by: "", source: switchOn ? "record" : "notion", confirm: CONFIRM });
    if (req.method === "PUT") {
      if (typeof said.on !== "boolean") return send(400, { problem: "Say on: true or false." });
      switchOn = said.on;
      return send(200, { on: switchOn, at: new Date().toISOString(), by: said.by, source: switchOn ? "record" : "notion" });
    }
    return send(405, { problem: "Wrong method." });
  }
  if (path === "/console/studio/specsheet/look" && req.method === "POST") {
    const report = lookReport();
    return send(200, { sheets: report.length, report, text: "…" });
  }
  if (path === "/console/studio/specsheet/move" && req.method === "POST") {
    confirms.push(said.confirm);
    if (said.confirm !== CONFIRM) return send(400, { problem: `Nothing written. The move needs confirm: “${CONFIRM}”, after the look.` });
    const done = [];
    for (const one of lookReport()) {
      if (!one.sheet || !one.record || one.already) { done.push({ title: one.title, written: false }); continue; }
      if (one.title === "Let's Bake" && mode === "fail-one") {
        done.push({ title: one.title, project: one.project, fact: one.fact, written: false, why: "the record had one already" });
        continue;
      }
      written[one.project] = one.sheet; writes += 1;
      done.push({ title: one.title, project: one.project, fact: one.fact, written: true });
    }
    return send(200, { status: 200, moved: done.filter((d) => d.written).length, done, text: "…" });
  }
  return send(404, { problem: "No such door." });
});

await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const HUB = `http://127.0.0.1:${server.address().port}/console`;

// --------------------------------------------------------------- the checks

// The helper runs as a child that waits on this server, so each call goes
// off the main loop: a synchronous run would block the fake from answering.
async function runAsync(args, env) {
  return new Promise((ok) => execFile("/usr/bin/python3", [HELPER, ...args], {
    env: { PATH: "/usr/bin:/bin", SHOTLISTER_HUB_CONSOLE: HUB, SHOTLISTER_RELAY_TOKEN: PASSWORD, ...env },
    encoding: "utf8",
  }, (_err, stdout) => ok(stdout || "")));
}

let passed = 0, failed = 0;
function check(name, ok, got) {
  if (ok) { passed += 1; console.log(`  ✓ ${name}`); }
  else { failed += 1; console.log(`  ✗ ${name}\n${String(got).split("\n").map((l) => `      ${l}`).join("\n")}`); }
}

let out = await runAsync(["look"]);
check("look: counts what the move would write", out.startsWith("MOVABLE 2 OF 3\n"), out);
check("look: sheet, cameras, lenses, unplaced count", out.includes("Halcyon · Shoot 1 · A Cam ALEXA 35, B Cam FX6 · 6 lenses · 2 lines not placed"), out);
check("look: one lens said as one", out.split("\n").includes("Let's Bake · A Cam VENICE 2 · 1 lens"), out);
check("look: a sheet that cannot move says so", out.includes("Orphan Sheet · no cameras · 0 lenses · 1 line not placed · cannot be moved"), out);
check("look: wrote nothing", writes === 0, writes);

out = await runAsync(["move"]);
check("move: sent the exact confirming words", confirms.at(-1) === CONFIRM, confirms);
check("move: says how many moved", out.startsWith("DONE\n2 spec sheets moved."), out);
check("move: names what was left", out.includes("Left as they were: Orphan Sheet"), out);
check("move: says Notion was not written", out.trim().endsWith("Nothing was written to Notion."), out);
check("move: two writes", writes === 2, writes);

out = await runAsync(["look"]);
check("second look: nothing left to move", out.startsWith("MOVABLE 0 OF 3\n") && out.includes("already moved, left as it is"), out);
out = await runAsync(["move"]);
check("second move: nothing written over", writes === 2 && out.startsWith("DONE\n0 spec sheets moved."), out);

// One that fails, said by name.
for (const k of Object.keys(written)) delete written[k];
mode = "fail-one";
out = await runAsync(["move"]);
check("a failure is named with its reason", out.includes("1 sheet failed:\nLet's Bake · the record had one already") && out.startsWith("DONE\n1 spec sheet moved."), out);
mode = "ok";

out = await runAsync(["switch"]);
check("switch: reads Off", out.trim() === "Off", out);
out = await runAsync(["switch", "on"]);
check("switch on: reads On", out.trim() === "On" && switchOn === true, out);
out = await runAsync(["switch", "off"]);
check("switch off: reads Off", out.trim() === "Off" && switchOn === false, out);

out = await runAsync(["look"], { SHOTLISTER_RELAY_TOKEN: "" });
check("no password: said plainly, nothing sent", out.startsWith("PROBLEM\nThe sync password is not on this Mac."), out);
out = await runAsync(["move"], { SHOTLISTER_RELAY_TOKEN: "wrong-made-up" });
check("wrong password: said plainly", out.startsWith("PROBLEM\nThe hub did not accept the sync password") && out.includes("Nothing was written to Notion."), out);
mode = "down";
out = await runAsync(["look"]);
check("hub refusal: its reason passed on", out.startsWith("PROBLEM\nThe hub said no (503): The hub has no Notion key"), out);
mode = "ok";
out = await runAsync(["look"], { SHOTLISTER_HUB_CONSOLE: "http://127.0.0.1:9/console" });
check("hub out of reach: said plainly", out.startsWith("PROBLEM\nCould not reach the hub."), out);

server.close();
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
