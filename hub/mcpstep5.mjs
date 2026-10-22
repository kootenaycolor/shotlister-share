#!/usr/bin/env node
/**
 * **The AI connector, stage 5 step 5** — `src/mcp.js` and `src/mcpprojects.js`
 * driven through the real `serveMcp` and the real engine (`src/mcp.wasm`),
 * over a bucket held in memory. Nothing here touches a real film, the real
 * bucket or Notion.
 *
 * 1. A project opens by its ID, by its film's old relay id, or by name; the
 *    remembered open project follows its ID when its Studio side moves.
 * 2. `modes` reads a project's modes and sets one through studiomodes.js's
 *    own door: the switch, the both-off rule, the Studio side made lazily.
 * 3. Project or Job and Type in what lists and describes; a Job with no
 *    Studio side says so plainly.
 * 4. "project", not "film": `projects`, `update_project`.
 * 5. `set_kind` is gone; kind follows Type.
 * 6. One shoot: `shoot` narrows scenes, shots, schedule, locations and kit.
 *
 *     node --import <json+wasm hook> hub/mcpstep5.mjs
 *
 * (Node 20 needs the hook to import `relay/layout.json` and `mcp.wasm`, as
 * every suite that loads the engine does.)
 */
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 78).padEnd(80)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};

// ── the cache and the bucket, in memory ──────────────────────────────────────

const cached = new Map();
globalThis.caches = {
  default: {
    async match(req) { const hit = cached.get(typeof req === "string" ? req : req.url); return hit ? new Response(hit.body, { headers: hit.headers }) : undefined; },
    async put(req, res) { cached.set(typeof req === "string" ? req : req.url, { body: await res.text(), headers: Object.fromEntries(res.headers) }); },
    async delete(req) { return cached.delete(typeof req === "string" ? req : req.url); },
  },
};

function bucket() {
  const m = new Map();
  let n = 0;
  const obj = (key) => {
    const v = m.get(key);
    const bytes = typeof v.body === "string" ? new TextEncoder().encode(v.body) : v.body;
    return {
      key, size: bytes.length, etag: v.etag, uploaded: new Date(v.at), httpMetadata: {},
      json: async () => JSON.parse(new TextDecoder().decode(bytes)),
      text: async () => new TextDecoder().decode(bytes),
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length),
    };
  };
  return {
    m,
    async get(k) { return m.has(k) ? obj(k) : null; },
    async head(k) { return m.has(k) ? obj(k) : null; },
    async put(k, body, opts = {}) {
      if (opts.onlyIf) {
        const had = m.get(k);
        if (opts.onlyIf.etagMatches && (!had || had.etag !== opts.onlyIf.etagMatches)) return null;
        if (opts.onlyIf.etagDoesNotMatch === "*" && had) return null;
      }
      const b = typeof body === "string" ? body : body instanceof Uint8Array ? body : String(body);
      m.set(k, { body: b, etag: `e${++n}`, at: Date.now() });
      return obj(k);
    },
    async delete(k) { for (const one of [].concat(k)) m.delete(one); },
    async list({ prefix = "", delimiter, cursor } = {}) {
      const objects = [], seen = new Set();
      for (const k of [...m.keys()].sort()) {
        if (!k.startsWith(prefix)) continue;
        const rest = k.slice(prefix.length);
        if (delimiter && rest.includes(delimiter)) { seen.add(prefix + rest.split(delimiter)[0] + delimiter); continue; }
        objects.push(obj(k));
      }
      return { objects, delimitedPrefixes: [...seen], truncated: false };
    },
  };
}

const ME = "owner@example.com";
const DIRECTOR = "clara@example.com";
const env = { BUCKET: bucket(), OWNER: ME, HUB_SECRET: "checking-secret" };
const put = (k, v) => env.BUCKET.put(k, typeof v === "string" ? v : JSON.stringify(v));
const read = async (k) => { const g = await env.BUCKET.get(k); return g ? g.json() : null; };

const { serveMcp } = await import("./src/mcp.js");

// ── the films ────────────────────────────────────────────────────────────────

const RELAY_S = "01a00b57e8790941866a989900000000";   // Daybreak, a film under its old relay id
const PAGE_S = "5a000000000000000000000000000001";    // …its project, by its Notion page
const JOB = "70b00000000000000000000000000001";       // a Job, no Studio side
const MINE = "70b00000000000000000000000000002";      // a Project with every mode off, no Studio side

async function seedFilm(relay, title) {
  await put(`p/${relay}/manifest.json`, { format: 1, project: relay, title, engine: "0.1.0" });
  const dir = join(ROOT, "studio/fixtures/Daybreak.shotlist/changes");
  for (const f of readdirSync(dir)) await put(`p/${relay}/logs/${f}`, readFileSync(join(dir, f), "utf8"));
}
await seedFilm(RELAY_S, "Daybreak");
await put(`p/${RELAY_S}/people.json`, { version: 1, people: [{ email: DIRECTOR, role: "viewer" }], links: [] });
const fact = (value, v = 1) => ({ value, v, at: "2026-10-14T10:00:00.000Z" });
await put(`r/${PAGE_S}/record.json`, { version: 1, page: PAGE_S, name: "Daybreak", film: { relay: RELAY_S }, facts: { type: fact("Music Video") } });
await put(`r/${JOB}/record.json`, { version: 1, page: JOB, name: "Quick Job", job: true, facts: { type: fact("Commercial") } });
await put(`r/${MINE}/record.json`, { version: 1, page: MINE, name: "Quiet Project", kind: "project", facts: { type: fact("Personal"), modes: fact({ shot_list: false, references: false }) } });

// ── signing in, as the tokens are kept ──────────────────────────────────────

const sha = (s) => createHash("sha256").update(s).digest("hex");
async function tokenFor(email, client) {
  const secret = `checking-token-${client}-${email.replace(/[^a-z]/g, "")}`.padEnd(40, "x");
  await put(`mcp/tokens/${sha(secret)}.json`, { email, client_id: client, until: Date.now() + 3600e3 });
  return secret;
}
const ctx = { waitUntil: () => {} };
let rpcId = 0;
async function tell(secret, name, args = {}) {
  const req = new Request("https://mcp.your-domain.example/mcp", {
    method: "POST",
    headers: { authorization: `Bearer ${secret}`, "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method: name === "tools/list" ? "tools/list" : "tools/call", params: { name, arguments: args } }),
  });
  const res = await serveMcp(req, env, req.url, ctx);
  const got = await res.json();
  if (got.error) return { error: got.error.message, text: `ERROR: ${got.error.message}` };
  if (name === "tools/list") return { tools: got.result.tools };
  const text = got.result.content.map((c) => c.text || "").join("\n");
  let json = null;
  try { json = JSON.parse(text); } catch { /* words */ }
  return { text, json };
}
const openNote = async (email, client) => read(`mcp/open/${sha(`${client}|${email}`)}.json`);

const me = await tokenFor(ME, "claude-a");
const her = await tokenFor(DIRECTOR, "claude-b");

// ── 1. opening by the one ID ─────────────────────────────────────────────────

{
  let got = await tell(me, "open_project", { project: PAGE_S });
  check("1. opens by the project's ID (its record key)", got.json && got.json.scenes === 4, got.text);
  let note = await openNote(ME, "claude-a");
  check("1. …and remembers the Studio side and the ID", note && note.project === RELAY_S && note.id === PAGE_S, note);
  got = await tell(me, "open_project", { project: RELAY_S });
  check("1. opens by the film's old relay id", got.json && got.json.scenes === 4, got.text);
  got = await tell(me, "open_project", { film: "daybreak" });
  check("1. opens by name, under the old argument `film`", got.json && got.json.scenes === 4, got.text);
  got = await tell(me, "open_project", { project: "Nothing Like It" });
  check("1. a name nobody has is refused, listing theirs", /No project called Nothing Like It\. Yours: .*Daybreak/.test(got.text), got.text);

  // An older note, just the relay id: given its ID on the next call.
  await put(`mcp/open/${sha(`claude-a|${ME}`)}.json`, { project: RELAY_S });
  got = await tell(me, "summary");
  note = await openNote(ME, "claude-a");
  check("1. an older note is given its ID through the record that names the film", note && note.id === PAGE_S && note.project === RELAY_S, note);

  // The Studio side moves under the project's own ID: the open project follows.
  const MOVED = PAGE_S;
  await seedFilm(MOVED, "Daybreak");
  const rec = await read(`r/${PAGE_S}/record.json`);
  await put(`r/${PAGE_S}/record.json`, { ...rec, film: { relay: MOVED } });
  got = await tell(me, "summary");
  note = await openNote(ME, "claude-a");
  check("1. the open project follows its ID when the Studio side moves", note && note.project === MOVED && got.json && got.json.scenes === 4, { note, text: got.text });
  await put(`r/${PAGE_S}/record.json`, rec);
  for (const k of [...env.BUCKET.m.keys()]) if (k.startsWith(`p/${MOVED}/`)) env.BUCKET.m.delete(k);
  await tell(me, "open_project", { project: PAGE_S });

  // A Job with no Studio side: his, opened, and plain about it.
  got = await tell(me, "open_project", { project: JOB });
  check("1. a Job with no Studio side opens for him, saying so", /Quick Job, a Job \(Commercial\)/.test(got.text) && /no Studio side/.test(got.text), got.text);
  got = await tell(me, "shots");
  check("1. …and its shots say plainly there are none, not an error from the engine", /Quick Job is a Job with no Studio side/.test(got.text), got.text);
  got = await tell(her, "open_project", { project: JOB });
  check("1. somebody else cannot open it", /No project called/.test(got.text), got.text);
  await tell(me, "open_project", { project: PAGE_S });
}

// ── 2. modes ────────────────────────────────────────────────────────────────

{
  await tell(me, "open_project", { project: "Daybreak" });
  let got = await tell(me, "modes");
  check("2. modes reads a Music Video's standard set: Shot List, References, Schedule",
    got.json && got.json.on.shot_list && got.json.on.references && got.json.on.schedule && !got.json.on.locations && !got.json.on.diagram, got.text);
  check("2. …says Project and its Type, and that the switch is off", got.json && got.json.is === "Project" && got.json.type === "Music Video" && /^off/.test(got.json.switch), got.text);
  got = await tell(me, "modes", { mode: "diagram", on: true });
  check("2. with the switch off a change is refused in the door's own words", got.text === "ERROR: Modes are switched off on the server.", got.text);
  await put("s/studio-modes.json", { on: true, by: "check" });
  got = await tell(me, "modes", { mode: "Diagram", on: true });
  let rec = await read(`r/${PAGE_S}/record.json`);
  check("2. switch on: a mode named by its title goes on, kept as a difference from the standard",
    /Diagram is on\./.test(got.text) && JSON.stringify(rec.facts.modes.value) === '{"diagram":true}', { text: got.text, modes: rec.facts.modes });
  got = await tell(me, "modes", { mode: "shot_list", on: false });
  check("2. Shot List off with Schedule on is refused, asking for both", got.text === "ERROR: Schedule goes off with Shot List. Send both: true to turn both off.", got.text);
  got = await tell(me, "modes", { mode: "shot_list", on: false, both: true });
  rec = await read(`r/${PAGE_S}/record.json`);
  check("2. …and with both, both go off and nothing else", /Shot List is off\. Nothing is deleted\. Schedule went off with it\. On: References, Diagram\./.test(got.text)
    && rec.facts.modes.value.shot_list === false && rec.facts.modes.value.schedule === false, got.text);
  got = await tell(me, "modes", { mode: "schedule", on: true });
  check("2. Schedule on brings Shot List on", /Schedule is on\. Shot List came on with it\./.test(got.text), got.text);
  got = await tell(me, "modes", { mode: "lighting", on: true });
  check("2. a mode that is not one is refused", /Say which mode/.test(got.text), got.text);
  await tell(her, "open_project", { project: "Daybreak" });
  got = await tell(her, "modes", { mode: "locations", on: true });
  check("2. a viewer may read the modes but not change them", /Only an editor/.test(got.text) && (await tell(her, "modes")).json, got.text);

  // A Job's first mode makes its Studio side (step 2's door, which needs One ID on).
  await put("s/oneid.json", { on: true, by: "check" });
  await tell(me, "open_project", { project: JOB });
  got = await tell(me, "modes");
  check("2. a Job starts with every mode off", got.json && got.json.is === "Job" && Object.values(got.json.on).every((v) => !v) && got.json.studio_side === "none yet", got.text);
  got = await tell(me, "modes", { mode: "shot_list", on: true });
  rec = await read(`r/${JOB}/record.json`);
  check("2. its first mode on makes its Studio side under its own ID", /Shot List is on\. Its Studio side was made\./.test(got.text)
    && rec.film && rec.film.relay === JOB && Boolean(env.BUCKET.m.get(`p/${JOB}/manifest.json`)), { text: got.text, film: rec.film });
  got = await tell(me, "summary");
  check("2. …and the open Job now answers from its Studio side", got.json && got.json.scenes === 0, got.text);
  await put("s/oneid.json", { on: false, by: "check" });
  await tell(me, "open_project", { project: PAGE_S });
}

// ── 3. Project or Job, and Type ─────────────────────────────────────────────

{
  let got = await tell(me, "projects");
  const rows = got.json || [];
  const row = (name) => rows.find((r) => r.project === name) || {};
  check("3. the list says Project and Music Video for Daybreak, with its ID", row("Daybreak").is === "Project" && row("Daybreak").type === "Music Video" && row("Daybreak").id === PAGE_S && row("Daybreak").studio === "yes", got.text);
  check("3. …a Job by its Type, with its Studio side made by its mode", row("Quick Job").is === "Job" && row("Quick Job").type === "Commercial" && row("Quick Job").studio === "yes", got.text);
  check("3. …and a project with no Studio side says none, plainly", row("Quiet Project").is === "Project" && row("Quiet Project").type === "Personal" && row("Quiet Project").studio === "none", got.text);
  check("3. …no bookkeeping leaks into the list", rows.every((r) => !("open" in r) && !("side" in r) && !("title" in r)), got.text);
  got = await tell(her, "projects");
  check("3. somebody else sees only what they are on", (got.json || []).map((r) => r.project).join() === "Daybreak", got.text);
  got = await tell(me, "summary");
  check("3. summary says the project's ID, Project and Type", got.json && got.json.project_id === PAGE_S && got.json.is === "Project" && got.json.type === "Music Video", got.text);
  got = await tell(me, "open_project", { project: "Quiet Project" });
  check("3. a Project with no Studio side opens, saying so", /Opened Quiet Project, a Project \(Personal\)\./.test(got.text) && /no Studio side/.test(got.text), got.text);
  got = await tell(me, "summary");
  check("3. …its summary is its record's, not an error", got.json && got.json.is === "Project" && got.json.studio_side === "none", got.text);
  got = await tell(me, "schedule");
  check("3. …and its schedule says it has none, in plain words", /Quiet Project is a Project with no Studio side: it has no shot list/.test(got.text), got.text);
  await tell(me, "open_project", { project: PAGE_S });
}

// ── 4. "project", not "film" ────────────────────────────────────────────────

{
  const names = new Set((await tell(me, "tools/list")).tools.map((t) => t.name));
  check("4. the list is `projects` and the details are `update_project`; the old names are gone", names.has("projects") && names.has("update_project") && !names.has("films") && !names.has("update_film"), [...names].filter((n) => /film|project/.test(n)));
  const tools = (await tell(me, "tools/list")).tools;
  const open = tools.find((t) => t.name === "open_project");
  check("4. open_project asks for `project`", open && open.inputSchema.required.join() === "project", open);
  const said = (await tell(me, "tools/list")).tools.filter((t) => ["projects", "open_project", "summary", "update_project", "modes", "front", "pages", "spec_sheet", "record"].includes(t.name))
    .filter((t) => /\b(the|this|that|open) film\b/i.test(t.description)).map((t) => t.name);
  check("4. the core tools' descriptions say project, not film", said.length === 0, said);
  const quiet = await tokenFor(ME, "claude-c");
  let got = await tell(quiet, "summary");
  check("4. nothing open says project", got.text === "ERROR: No project is open. Ask for `projects`, then `open_project`.", got.text);
  got = await tell(me, "update_project", { aspect_ratio: "2.39" });
  check("4. update_project changes the frame", !got.error && /2\.39|frame|ratio/i.test(got.text), got.text);
  got = await tell(me, "update_film", { aspect_ratio: "2.39" });
  check("4. update_film is no longer a tool", /Unknown tool: update_film/.test(got.text), got.text);
}

// ── 5. set_kind is gone ─────────────────────────────────────────────────────

{
  const names = new Set((await tell(me, "tools/list")).tools.map((t) => t.name));
  check("5. set_kind is no longer offered", !names.has("set_kind"), [...names].filter((n) => /kind/.test(n)));
  const got = await tell(me, "set_kind", { kind: "commercial" });
  check("5. …nor answered", /Unknown tool: set_kind/.test(got.text), got.text);
}

// ── 6. one shoot ────────────────────────────────────────────────────────────

{
  await tell(me, "open_project", { project: PAGE_S });
  const scenes = (await tell(me, "scenes")).json.map((r) => r.number);
  let got = await tell(me, "scenes", { shoot: "2" });
  check("6. one shoot: `shoot` is ignored", (got.json || []).length === scenes.length, got.text);
  got = await tell(me, "new_shoot", { date: "2026-11-02", name: "Shoot 2", pickups: [scenes[0]] });
  check("6. (a second shoot, made the way New Shoot makes it)", !got.error, got.text);
  await tell(me, "add_day", { date: "2026-05-01", name: "Shoot 1", position: 1 });
  got = await tell(me, "summary");
  check("6. summary names the shoots", got.json && JSON.stringify(got.json.shoots) === '["Shoot 2","Shoot 1"]', got.text);
  got = await tell(me, "scenes", { shoot: "Shoot 2" });
  check("6. scenes narrows to the shoot's (its pickup)", (got.json || []).map((r) => r.number).join() === scenes[0], got.text);
  got = await tell(me, "schedule", { shoot: "shoot-1" });
  check("6. schedule narrows to the shoot's days", got.json && got.json.days.length === 1 && got.json.days[0].name === "Shoot 1", got.text);
  got = await tell(me, "shots", { shoot: "2" });
  check("6. shots narrows to the shots on the shoot", got.json && got.json.length > 0 && got.json.every((r) => r.scene === scenes[0]), got.text);
  got = await tell(me, "locations", { shoot: "Lunar" });
  check("6. a shoot nobody has is refused, naming the shoots", got.text === "ERROR: No shoot called Lunar. This project's shoots: Shoot 2, Shoot 1.", got.text);
  const tools = (await tell(me, "tools/list")).tools;
  const takes = ["scenes", "shots", "schedule", "locations", "kit", "spec_sheet"].filter((n) => (tools.find((t) => t.name === n) || { inputSchema: { properties: {} } }).inputSchema.properties.shoot);
  check("6. scenes, shots, schedule, locations, kit and spec_sheet all take `shoot`", takes.length === 6, takes);
}

// ── 1b. a project renamed: its Studio side's own title still opens it ──────

{
  const rec = await read(`r/${PAGE_S}/record.json`);
  await put(`r/${PAGE_S}/record.json`, { ...rec, name: "Bright Days" });
  let got = await tell(me, "open_project", { project: "Daybreak" });
  check("1. a renamed project still opens by its Studio side's own title", got.json && got.json.scenes > 0, got.text);
  got = await tell(me, "projects");
  const row = (got.json || []).find((r) => r.id === PAGE_S) || {};
  check("1. …and the list gives both names", row.project === "Bright Days" && row.studio_title === "Daybreak", got.text);
  await put(`r/${PAGE_S}/record.json`, rec);
}

if (process.env.PLANT === "1") check("a planted difference is caught", false, "planted");

console.log(`mcpstep5: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
