#!/usr/bin/env node
/**
 * **The kit door** (Ref 1627) — `GET|POST /kit/<film>` on the hub
 * (`src/kit.js`), and the film taking what it says:
 *
 * - shut without the token;
 * - a film that shoots twice: each shoot's sheet, lenses broken into picks,
 *   cameras by name and body, the next shoot leading;
 * - Add to Spec Sheet puts `edit_spec_sheet` on the record's pending list —
 *   the queue Projects Console works — in Notion's words, with what was seen;
 *   until Notion has it the kit shows it, marked waiting;
 *   asked twice it is refused; a box changed since it was read is refused;
 * - the console failing it: the kit says why, and stops showing it;
 * - a film with no record reads but cannot be changed; a film with one sheet
 *   and no Shoots rows uses the card's lead sheet;
 * - the kit, handed to the Mac's connector (`take_kit`), fills the Lens list
 *   and the cameras, and `kit` names the shot whose lens is off the sheet.
 *
 *     hub/kit.mjs
 *
 * A throwaway bucket and a hub of its own on 8852. Nothing here touches a
 * real film, the real bucket or Notion.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const PORT = 8852;
const H = `http://127.0.0.1:${PORT}`;
const TOKEN = "checking-token-not-a-secret";
const TWICE = "0f0e0d0c0b0a00000000000000001627";
const LONE = "0f0e0d0c0b0a00000000000000001628";
const BARE = "0f0e0d0c0b0a00000000000000001629";
const PAGE = "aa0e0d0c0b0a00000000000000001627";
const LONE_PAGE = "aa0e0d0c0b0a00000000000000001628";
const S1 = "51000000000000000000000000000001";
const S2 = "52000000000000000000000000000002";
const S3 = "53000000000000000000000000000003";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${typeof why === "string" ? why : JSON.stringify(why)}`); }
};

// The Mac's connector first: built while a hub runs, the hub was gone after.
const PATH = `${process.env.HOME}/.cargo/bin:/opt/homebrew/bin:${process.env.PATH}`;
const built = spawnSync("cargo", ["build", "--quiet", "--manifest-path", join(ROOT, "mcp/Cargo.toml")], { env: { ...process.env, PATH } });
if (built.status !== 0) { say(`the connector would not build\n${built.stderr}`); process.exit(1); }

const state = mkdtempSync(join(tmpdir(), "kit-"));
const W = join(HERE, "node_modules/.bin/wrangler");
function put(key, body) {
  const file = join(state, "put.bin");
  writeFileSync(file, typeof body === "string" ? body : JSON.stringify(body));
  spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
}

const sheet = (body, lenses) => ({ body, lenses, format: "", capture: "", finishing: "", colour: "LogC4", codec: "ProRes 4444", fps: "23.976", desqueeze: "", guides: "", luts: "" });
// Let's Bake, near enough: Shoot 2 swapped to the Premista zoom.
put(`p/${TWICE}/manifest.json`, { format: 1, project: TWICE, title: "Twice", engine: "0.1.0" });
put(`p/${TWICE}/front.json`, {
  version: 1, linked: "link", updated: "2026-10-06T12:00:00Z", source: `notion:${PAGE}`,
  camera: sheet("Alexa Mini LF", "Fujinon Premista 28-100mm T2.9"), camera_sheet: S2,
  shoots: [
    { id: "e1000000000000000000000000000001", name: "Shoot 1", slug: "shoot-1", status: "Wrapped", start: "2026-07-09", end: "2026-07-10",
      sheet: S1, camera: sheet("A Cam: Alexa 35\nB Cam: Sony FX6", "Cooke S4 18mm\nCooke S4 25mm\nCooke S4 32mm\nCooke S4 50mm") },
    { id: "e2000000000000000000000000000002", name: "Shoot 2", slug: "shoot-2", status: "Upcoming", start: "2026-10-06", end: "",
      sheet: S2, camera: sheet("Alexa Mini LF", "Fujinon Premista 28-100mm T2.9") },
  ],
});
put(`r/${PAGE}/record.json`, { version: 1, page: PAGE, name: "Twice", facts: {} });
// One sheet, no Shoots rows: the card's lead sheet.
put(`p/${LONE}/manifest.json`, { format: 1, project: LONE, title: "Lone", engine: "0.1.0" });
put(`p/${LONE}/front.json`, { version: 1, linked: "link", updated: "2026-10-06T12:00:00Z", source: `notion:${LONE_PAGE}`,
  camera: sheet("Sony FX3", "Sony G Master 24-70"), camera_sheet: S3, shoots: [] });
put(`r/${LONE_PAGE}/record.json`, { version: 1, page: LONE_PAGE, name: "Lone", facts: {} });
// No record at all.
put(`p/${BARE}/manifest.json`, { format: 1, project: BARE, title: "Bare", engine: "0.1.0" });
put(`p/${BARE}/front.json`, { version: 1, linked: "link", updated: "2026-10-06T12:00:00Z", camera: sheet("RED Komodo", "Zeiss CP.3 — 25, 35, 50"), shoots: [] });

const free = (port) => spawnSync("sh", ["-c", `lsof -ti tcp:${port} -sTCP:LISTEN | xargs kill -9 2>/dev/null`]);
free(PORT);
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`,
  "--var", "COMMIT:checking-commit", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });
const stop = () => {
  try { hub.kill("SIGTERM"); } catch {}
  spawnSync("pkill", ["-f", `wrangler.*dev --local --port ${PORT}`]);
  free(PORT);
  rmSync(state, { recursive: true, force: true });
};

const ask = async (path, { token = TOKEN, method = "GET", body } = {}) => {
  const r = await fetch(`${H}${path}`, {
    method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};

try {
  let up = false;
  for (let i = 0; i < 80 && !up; i++) {
    try { up = (await fetch(`${H}/version`)).ok; } catch {}
    if (!up) await wait(500);
  }
  if (!up) throw new Error("the hub would not start");

  say("\nShut without the token");
  check("no token: refused", (await ask(`/kit/${TWICE}`, { token: "" })).status === 401);
  check("a film that is not there: 404", (await ask(`/kit/ffffffffffffffffffffffffffffffff`)).status === 404);

  say("\nA film that shoots twice");
  let r = await ask(`/kit/${TWICE}`);
  const [one, two] = r.body.shoots || [];
  check("answers, and may be changed", r.status === 200 && r.body.editable === true, r);
  check("two sheets, oldest first", one && two && one.name === "Shoot 1" && two.name === "Shoot 2", r.body.shoots);
  check("Shoot 2 leads (the next upcoming)", two && two.lead && !one.lead, r.body.shoots);
  // since 2026-10-13 the sheet's lenses are pills, each a lens named in full
  check("four Cooke pills, four lenses, named in full", one && JSON.stringify(one.lenses) === '["Cooke S4 18mm","Cooke S4 25mm","Cooke S4 32mm","Cooke S4 50mm"]', one && one.lenses);
  check("the Premista zoom stays one, as named", two && JSON.stringify(two.lenses) === '["Fujinon Premista 28-100mm T2.9"]', two && two.lenses);
  check("cameras by name and body", one && JSON.stringify(one.cameras) === '[{"label":"A Cam","body":"Alexa 35"},{"label":"B Cam","body":"Sony FX6"}]', one && one.cameras);

  say("\nAdd to Spec Sheet: asked of the Studio, never written here");
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { sheet: S2, add: { lens: "85mm" }, by: "Check Mac" } });
  const item = r.body.item || {};
  check("taken", r.status === 200 && r.body.ok, r);
  check("an edit_spec_sheet for the Studio", item.verb === "edit_spec_sheet" && item.state === "pending", item);
  check("in Notion's words, a line of its own", item.args && item.args.sheet === S2
    && item.args.changes.Lenses === "Fujinon Premista 28-100mm T2.9\n85mm", item.args);
  check("with what the screen saw", item.args && item.args.seen.Lenses === "Fujinon Premista 28-100mm T2.9", item.args);
  check("who asked", item.by === "Shotlister on Check Mac", item.by);
  r = await ask(`/console/record/${PAGE}/pending`);
  check("on the record's pending list, where the console looks", (r.body.pending || []).some((x) => x.id === item.id), r.body);
  r = await ask(`/kit/${TWICE}`);
  const after = (r.body.shoots || [])[1] || {};
  check("the kit shows it before Notion has it, marked waiting", after.lenses && after.lenses.includes("85mm")
    && JSON.stringify(after.waiting) === '["lenses"]', after);
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { shoot: "2", add: { lens: "85MM" } } });
  check("asked twice: already on it", r.status === 409 && r.body.already, r);
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { shoot: "Shoot 1", add: { camera: "RED Komodo", label: "C-Cam" } } });
  // Notion lists only the bodies; the label goes on the record (his ruling, 2026-10-13)
  check("a camera goes on Notion as its body alone", r.status === 200
    && r.body.item.args.changes.Camera === "Alexa 35\nSony FX6\nRED Komodo"
    && r.body.item.args.seen.Camera === "Alexa 35\nSony FX6", r.body.item && r.body.item.args);
  r = await ask(`/console/record/${PAGE}/facts`);
  const labels = ((r.body.facts || {}).camera_labels || {}).value || {};
  check("and its label on the record", labels["RED Komodo"] === "C-Cam" && labels["Alexa 35"] === "A Cam", r.body);
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { sheet: S1, seen: { codec: "ProRes 422" }, changes: { codec: "ARRIRAW" } } });
  check("a box changed since it was read: refused", r.status === 409 && r.body.moved === "codec", r);
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { sheet: S1, changes: { luts: "x" } } });
  check("a box the sheet does not have: refused", r.status === 409, r);
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { sheet: S1, seen: { fps: "23.976" }, changes: { fps: "25" } } });
  check("a plain edit, with what was seen", r.status === 200 && r.body.item.args.changes["Frame Rate"] === "25"
    && r.body.item.args.seen["Frame Rate"] === "23.976", r.body.item);

  say("\nThe Studio could not write it");
  await ask(`/console/record/${PAGE}/pending/${item.id}`, { method: "PUT", body: { state: "working", by: "studio" } });
  await ask(`/console/record/${PAGE}/pending/${item.id}`, { method: "PUT", body: { state: "failed", report: "Changed in Notion since you opened it.", by: "studio" } });
  r = await ask(`/kit/${TWICE}`);
  const failed = (r.body.shoots || [])[1] || {};
  check("the kit says why", failed.failed === "Changed in Notion since you opened it.", failed);
  check("and stops showing what was not written", failed.lenses && !failed.lenses.includes("85mm") && !failed.waiting.length, failed);
  r = await ask(`/kit/${TWICE}`, { method: "POST", body: { sheet: S2, add: { lens: "65mm" } } });
  r = await ask(`/kit/${TWICE}`);
  const again = (r.body.shoots || [])[1] || {};
  check("asked again: the new ask stands, the old failure goes", again.failed === "" && again.waiting.includes("lenses"), again);

  say("\nOne sheet, no Shoots rows; and no record");
  r = await ask(`/kit/${LONE}`);
  const lone = (r.body.shoots || [])[0] || {};
  check("the card's lead sheet, by its page", r.body.shoots && r.body.shoots.length === 1 && lone.sheet === S3 && lone.lead, r.body);
  check("a zoom pill keeps its name", JSON.stringify(lone.lenses) === '["Sony G Master 24-70"]', lone.lenses);
  r = await ask(`/kit/${LONE}`, { method: "POST", body: { add: { lens: "50mm" } } });
  check("the lead sheet takes an add with no sheet named", r.status === 200 && r.body.item.args.sheet === S3, r);
  r = await ask(`/kit/${BARE}`);
  check("no record: read, not editable", r.status === 200 && r.body.editable === false && r.body.shoots.length === 1, r.body);
  check("a sheet still in the old typed sets reads as before", JSON.stringify((r.body.shoots[0] || {}).lenses) === '["25mm","35mm","50mm"]', r.body.shoots);
  r = await ask(`/kit/${BARE}`, { method: "POST", body: { add: { lens: "85mm" } } });
  check("no record: a change is refused, saying where", r.status === 409 && /no project record/.test(r.body.why), r);

  say("\nThe film takes the kit (the Mac's connector)");
  r = await ask(`/kit/${TWICE}`);
  const kit = r.body.shoots.map(({ name, start, end, sheet, lead, cameras, lenses }) => ({ name, start, end, sheet, lead, cameras, lenses }));
  const box = mkdtempSync(join(tmpdir(), "kit-film-"));
  // A real film (the battery's Daybreak), copied: it has a project record.
  const path = join(box, "Daybreak.shotlist");
  spawnSync("ditto", [join(ROOT, "studio/fixtures/Daybreak.shotlist"), path]);
  const calls = [["open_project", { path }], ["add_scene", { number: "901" }],
    ["take_kit", { kit }], ["add_shot", { scene: "901", lens: "25mm" }],
    ["add_shot", { scene: "901", lens: "85mm" }], ["add_day", { date: "2026-10-06", name: "Kit Check Day" }],
    ["schedule_shot", { shots: ["901A"], day: "Kit Check Day" }], ["kit", {}], ["cameras", {}], ["take_kit", { kit }]];
  const lines = calls.map(([name, args], i) => JSON.stringify({ jsonrpc: "2.0", id: i + 1, method: "tools/call", params: { name, arguments: args } }));
  const run = spawnSync(join(ROOT, "mcp/target/debug/shotlister-mcp"), [], { input: lines.join("\n") + "\n", env: { ...process.env, SHOTLISTER_DEVICE: "kit-check" } });
  const said = run.stdout.toString().trim().split("\n").map((l) => JSON.parse(l)).map((x) =>
    x.error ? `ERROR ${x.error.message}` : x.result.content.map((c) => c.text).join("\n"));
  const took = said[2] || "";
  const kitSaid = said[7] || "";
  let lensList = [];
  try { lensList = JSON.parse(kitSaid).lens_list; } catch {}
  check("taken, and said", /Lens list: .*Fujinon Premista 28-100mm.* added/.test(took), took);
  check("the sheets' lenses are on the Lens list", ["Cooke S4 18mm", "Cooke S4 25mm", "Cooke S4 32mm", "Cooke S4 50mm", "Fujinon Premista 28-100mm T2.9"]
    .every((l) => lensList.some((h) => h.toLowerCase() === l.toLowerCase())), lensList);
  const cams = said[8] || "";
  check("the cameras carry the sheets' bodies", cams.includes("Alexa Mini LF") && cams.includes("Sony FX6"), cams);
  check("901B's 85mm is off Shoot 2's sheet", kitSaid.includes('"shot":"901B","sheet":"Shoot 2","lens":"85mm"'), kitSaid);
  check("901A's 25mm, on a Shoot 2 day, is off Shoot 2's sheet", kitSaid.includes('"shot":"901A","sheet":"Shoot 2","lens":"25mm"'), kitSaid);
  check("taken again: nothing to do", (said[9] || "") === "The film already has this kit.", said[9]);
  rmSync(box, { recursive: true, force: true });
} catch (problem) {
  fail += 1;
  say(`  ${problem.message}`);
}
say(`\npassed ${pass}, failed ${fail}`);
// **For looking at it in the Mac app**: `KIT_SERVE=1` leaves the hub up after
// the checks (Ctrl-C ends it). Launch a checking run with
// `-PortalURL http://127.0.0.1:8852 -PortalToken checking-token-not-a-secret`
// on a film whose remote.json names 0f0e0d0c0b0a00000000000000001627.
if (process.env.KIT_SERVE === "1") {
  say(`serving on ${H} — Ctrl-C ends it`);
  process.on("SIGINT", () => { stop(); process.exit(fail ? 1 : 0); });
  process.on("SIGTERM", () => { stop(); process.exit(fail ? 1 : 0); });
  await new Promise(() => {});
}
stop();
process.exit(fail ? 1 : 0);
