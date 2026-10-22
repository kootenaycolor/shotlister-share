#!/usr/bin/env node
/**
 * **Shoots and their crew from the AI connector** — `src/mcpshoots.js` driven
 * through the real `serveMcp` (tokens, owner, tool list) over a bucket held in
 * memory, with a Notion, a Drive and a Studio door that are stand-ins on this
 * machine. A ZZ test project only; nothing touches his workspace, his Drive or
 * the real bucket.
 *
 * 1. The three tools are listed and say plainly that shoots and crew live in
 *    the project record and that editing Notion directly does not reach Studio.
 * 2. Owner only: a collaborator is refused.
 * 3. add_shoot is two steps: step 1 writes nothing and gives a token; step 2
 *    with no token, a made-up one, a stale one, a used one, or with the details
 *    changed is refused and makes nothing.
 * 4. Step 2 makes the shoot: Notion row, Drive folders, activity line.
 * 5. Notion down: the preview says so, the Drive folders are made, the Notion
 *    row waits (queued on the record, shown by `shoots` as waiting), the shoot
 *    is NOT refused. When Notion is back the same queue is made, once.
 * 6. set_shoot_crew: add with a role on this project (Notion's Role untouched),
 *    remove, the on-every-shoot and only-shoot rules, Notion down.
 * 7. `shoots` and `record` return every shoot with its crew.
 *
 *     node --import <json+wasm hook> hub/shoottools.mjs
 */
import { createHash } from "node:crypto";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 78).padEnd(80)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 700)}`}`);
};

globalThis.caches = { default: { async match() { return undefined; }, async put() {}, async delete() { return false; } } };

function bucket() {
  const m = new Map();
  let n = 0;
  const obj = (key) => {
    const v = m.get(key);
    const bytes = typeof v.body === "string" ? new TextEncoder().encode(v.body) : v.body;
    return { key, size: bytes.length, etag: v.etag, uploaded: new Date(v.at), httpMetadata: {},
      json: async () => JSON.parse(new TextDecoder().decode(bytes)), text: async () => new TextDecoder().decode(bytes),
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length) };
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
      m.set(k, { body: typeof body === "string" ? body : body instanceof Uint8Array ? body : String(body), etag: `e${++n}`, at: Date.now() });
      return obj(k);
    },
    async delete(k) { for (const one of [].concat(k)) m.delete(one); },
    async list({ prefix = "", delimiter } = {}) {
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
const env = { BUCKET: bucket(), OWNER: ME, HUB_SECRET: "checking-secret", NOTION_TOKEN: "stand-in", NOTION_API: "http://127.0.0.1:9/v1/" };
const put = (k, v) => env.BUCKET.put(k, typeof v === "string" ? v : JSON.stringify(v));
const read = async (k) => { const g = await env.BUCKET.get(k); return g ? g.json() : null; };
const { serveMcp } = await import("./src/mcp.js");
const { catchUpWaiting } = await import("./src/mcpshoots.js");
const { SHOOTS, CREW, SPECS } = await import("./src/newshoot.js");
const { Handoff } = await import("./src/cloud.js");

// ── the ZZ project ───────────────────────────────────────────────────────────

const PZ = "7a000000000000000000000000000f01";      // ZZ Test Shoots, its Notion page and record key
const SH1 = "5b000000000000000000000000000001";
const DAN = "6c000000000000000000000000000001";     // Gaffer, on every shoot (untagged)
const EVE = "6c000000000000000000000000000002";     // Operator, tagged to Shoot 1 only
const FAY = "6c000000000000000000000000000003";     // in the Crew directory, not on the project
const fact = (value, v = 1) => ({ value, v, at: "2026-10-19T10:00:00.000Z" });
await put(`r/${PZ}/record.json`, { version: 1, page: PZ, name: "ZZ Test Shoots", facts: {
  title: fact("ZZ Test Shoots"), type: fact("Narrative"), status: fact("Active"), color: fact("blue"), shoot_dates: fact("2026-10-05"),
  shoots: fact([{ id: SH1, title: "ZZ Test Shoots — Shoot 1", label: "Shoot 1", name: "", n: 1, start: "2026-10-05", end: "", status: "Wrapped", section: "", changes: "", spec: [], docs: [] }]),
  crew: fact([
    { person: DAN, name: "Dan Gaffer", roles: ["Gaffer"], shoots: [SH1], all_shoots: true },
    { person: EVE, name: "Eve Operator", roles: ["Operator"], shoots: [SH1], all_shoots: false },
  ]),
} });
await put(`r/${PZ}/portal.json`, {});

// ── a Notion that can be switched off, a Drive, a Studio door ───────────────

const world = { down: false, pages: new Map(), posts: [], patches: [], driveMade: [], driveCalls: 0, logs: [], shoots: [], now: "2026-10-19" };
const mkTitle = (t) => [{ type: "text", plain_text: t, text: { content: t } }];
function seedNotion() {
  world.pages.clear(); world.posts.length = 0; world.patches.length = 0;
  world.pages.set(SH1, { id: SH1, object: "page", properties: { Shoot: { type: "title", title: mkTitle("ZZ Test Shoots — Shoot 1") }, Project: { relation: [{ id: PZ }] },
    Dates: { date: { start: "2026-10-05" } }, Status: { type: "select", select: { name: "Wrapped" } }, Crew: { relation: [{ id: DAN }, { id: EVE }] } } });
  const crew = (id, name, role, shoots) => world.pages.set(id, { id, object: "page", properties: { Name: { type: "title", title: mkTitle(name) },
    Role: { type: "multi_select", multi_select: [{ name: role }] }, Projects: { relation: id === FAY ? [] : [{ id: PZ }] }, Shoots: { relation: shoots.map((x) => ({ id: x })) } } });
  crew(DAN, "Dan Gaffer", "Gaffer", []); crew(EVE, "Eve Operator", "Operator", [SH1]); crew(FAY, "Fay Grip", "Grip", []);
  world.pages.set(PZ, { id: PZ, object: "page", properties: { Status: { type: "select", select: { name: "Active" } }, "Shoot Dates": { date: { start: "2026-10-05" } }, Color: { type: "select", select: { name: "blue" } } } });
}
let serial = 0;
const dead = () => { throw new Handoff("unauthorized"); };
const fakeN = {
  get: async (path) => {
    if (world.down) dead();
    if (path.startsWith("data_sources/")) return { properties: { Department: { select: { options: [] } } } };
    const id = path.replace(/^pages\//, "");
    if (world.pages.has(id)) return world.pages.get(id);
    throw new Error("Notion: object_not_found");
  },
  post: async (path, body) => {
    if (world.down) dead();
    if (path === `data_sources/${SHOOTS}/query`) return { results: [...world.pages.values()].filter((p) => p.properties.Shoot && JSON.stringify(p.properties.Project || {}).includes(PZ)), has_more: false };
    if (path === `data_sources/${SPECS}/query`) return { results: [], has_more: false };
    if (path === `data_sources/${CREW}/query`) return { results: [DAN, EVE, FAY].map((i) => world.pages.get(i)), has_more: false };
    if (path === "pages") {
      const id = `8d00000000000000000000000000${String(++serial).padStart(4, "0")}`;
      world.posts.push(body);
      world.pages.set(id, { id, object: "page", properties: body.properties, url: "" });
      return { id, url: "" };
    }
    throw new Error(`Notion: unexpected post ${path}`);
  },
  patch: async (path, body) => {
    if (world.down) dead();
    const id = path.replace(/^pages\//, "");
    world.patches.push({ id, body });
    const page = world.pages.get(id);
    if (page) page.properties = { ...page.properties, ...body.properties };
    return {};
  },
};
const fakeDeps = (driveOk = true) => ({
  n: fakeN,
  now: world.now,
  row: async () => { if (world.down) dead(); return { id: PZ, properties: { Type: { select: { name: "Narrative" } }, "Drive Folder": { url: null } } }; },
  facts: async () => (await read(`r/${PZ}/record.json`)).facts,
  film: async () => ({ ok: false, why: "no Shotlister film" }),
  portal: async () => false,
  door: { live: async () => [false, "no film"], shoot: async () => ({ steps: [] }) },
  drive: {
    plan: async (facts) => {
      world.driveCalls += 1;
      const n = facts.n;
      const key = `proj/2-logistics/shoot-${n}`;
      return driveOk ? { ok: true, project_folder: "proj", ids: { proj: "id" }, steps: [{ key, parent: "proj/2-logistics", name: `shoot-${n}` }], notes: [] }
        : { ok: false, why: "the Drive would not answer" };
    },
    copy: async () => "",
    make: async (plan) => {
      const made = [], already = [];
      for (const s of plan.steps) (world.driveMade.includes(s.key) ? already : made).push(s.key);
      world.driveMade.push(...made);
      return { made, already, failed: [] };
    },
  },
  refresh: async () => { if (world.down) dead(); return { ok: true }; },
  download: async () => new Uint8Array(), upload: async () => ({}),
  daysFollow: async () => false,
  logActivity: async (entry) => { world.logs.push(entry); },
});
env.SHOOT_TOOL_DEPS = {
  readiness: async () => ({ ok: true }),
  depsFor: async () => fakeDeps(),
  notion: fakeN,
  now: () => world.clock,
  afterAdd: async () => {},
};
world.clock = Date.now();

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
    method: "POST", headers: { authorization: `Bearer ${secret}`, "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method: name === "tools/list" ? "tools/list" : "tools/call", params: { name, arguments: args } }),
  });
  const res = await serveMcp(req, env, req.url, ctx);
  const got = await res.json();
  if (got.error) return { error: got.error.message, text: `ERROR: ${got.error.message}` };
  if (name === "tools/list") return { tools: got.result.tools, text: "" };
  const text = got.result.content.map((c) => c.text || "").join("\n");
  let json = null;
  try { json = JSON.parse(text); } catch { /* words */ }
  return { text, json, isError: got.result.isError };
}
const me = await tokenFor(ME, "claude-a");
const her = await tokenFor(DIRECTOR, "claude-b");

seedNotion();

// ── 1. the tools and their words ────────────────────────────────────────────

{
  const got = await tell(me, "tools/list");
  const by = Object.fromEntries(got.tools.map((t) => [t.name, t]));
  check("1. add_shoot, set_shoot_crew and shoots are listed", by.add_shoot && by.set_shoot_crew && by.shoots, Object.keys(by).join(","));
  for (const name of ["add_shoot", "set_shoot_crew", "shoots"]) {
    const d = (by[name] || {}).description || "";
    check(`1. ${name} says shoots and crew live in the project record and Notion edits don't reach Studio`,
      /live in (its|the) project record/.test(d) && /Notion/.test(d) && /does NOT reliably reach Studio/.test(d), d.slice(0, 200));
  }
  check("1. add_shoot tells the AI to show the preview and get his OK", /SHOW HIM THAT PREVIEW/.test(by.add_shoot.description) && /WAIT FOR HIS OK/.test(by.add_shoot.description), "");
  check("1. the engine's new_shoot says it is only the Studio side and points to add_shoot", /^ONLY THE STUDIO SIDE/.test(by.new_shoot.description) && /add_shoot/.test(by.new_shoot.description), by.new_shoot.description.slice(0, 200));
  check("1. set_shoot and record say the same", /live in its project record/.test(by.set_shoot.description) && /live in this record/.test(by.record.description), `${by.set_shoot.description.slice(-200)} | ${by.record.description.slice(0, 100)}`);
}

// ── 2. owner only ───────────────────────────────────────────────────────────

{
  for (const [name, args] of [["add_shoot", { project: "ZZ Test Shoots", start: "2026-11-03" }], ["set_shoot_crew", { project: "ZZ Test Shoots", shoot: "1", add: ["Fay Grip"] }], ["shoots", { project: "ZZ Test Shoots" }]]) {
    const got = await tell(her, name, args);
    check(`2. ${name}: a collaborator is refused`, /Only Nathaniel/.test(got.text), got.text);
  }
  check("2. …and nothing was made", world.posts.length === 0 && world.driveMade.length === 0 && world.patches.length === 0, JSON.stringify(world.posts));
}

// ── 3. add_shoot: two steps ─────────────────────────────────────────────────

const ADD = { project: "ZZ Test Shoots", start: "2026-11-03", name: "Malibu Pickup", notes: "Night exteriors added." };
let token;
{
  let got = await tell(me, "add_shoot", ADD);
  check("3. step 1 gives a preview and a confirm token", got.json && got.json.step === 1 && /^[0-9a-f]{36}$/.test(got.json.confirm || ""), got.text);
  token = got.json && got.json.confirm;
  check("3. …naming what will be made, by system", got.json && got.json.will_make.some((g) => g.system === "NOTION") && got.json.will_make.some((g) => g.system === "DRIVE") && got.json.shoot.label === "Shoot 2 · Malibu Pickup", got.text);
  check("3. …and wrote nothing (no Notion row, no Drive folder, no queue)", world.posts.length === 0 && world.driveMade.length === 0 && !(await read(`r/${PZ}/record.json`)).facts.shoots_waiting, `${world.posts.length} ${world.driveMade.length}`);
  check("3. …carrying over the last shoot's crew by default", got.json && got.json.crew.join() === "Dan Gaffer,Eve Operator", got.text);
  check("3. …and the preview tells the AI to show him and wait", /Show him this preview/.test(got.json.next), got.text);

  got = await tell(me, "add_shoot", ADD);
  check("3. asking for a preview twice gives a different token", got.json && got.json.confirm !== token, "");

  got = await tell(me, "add_shoot", { ...ADD, confirm: "" });
  check("3. an empty confirm is just another preview (nothing made)", got.json && got.json.step === 1 && world.posts.length === 0, got.text);
  got = await tell(me, "add_shoot", { ...ADD, confirm: "0123456789abcdef0123456789abcdef0123" });
  check("3. a made-up token is refused, nothing made", /isn't one I gave/.test(got.text) && world.posts.length === 0 && world.driveMade.length === 0, got.text);
  got = await tell(me, "add_shoot", { ...ADD, notes: "Different", confirm: token });
  check("3. the details changed since the preview: refused, nothing made", /details changed/.test(got.text) && world.posts.length === 0, got.text);
  // …and that refusal did not spend the token? it did not even read it as used: still valid
  const stale = (await tell(me, "add_shoot", ADD)).json.confirm;
  world.clock = Date.now() + 11 * 60e3;
  got = await tell(me, "add_shoot", { ...ADD, confirm: stale });
  check("3. a stale token (past ten minutes) is refused, nothing made", /expired/.test(got.text) && world.posts.length === 0 && world.driveMade.length === 0, got.text);
  world.clock = Date.now();
}

// ── 4. add_shoot: step 2 ────────────────────────────────────────────────────

{
  const t = (await tell(me, "add_shoot", ADD)).json.confirm;
  let got = await tell(me, "add_shoot", { ...ADD, confirm: t });
  check("4. step 2 makes the shoot", got.json && got.json.step === 2 && got.json.notion === "made", got.text);
  const row = world.posts.find((p) => p.properties.Shoot);
  check("4. …the Notion Shoots row, titled, dated, with the crew and the notes",
    row && row.properties.Shoot.title[0].text.content === "ZZ Test Shoots — Shoot 2 · Malibu Pickup" && row.properties.Dates.date.start === "2026-11-03"
      && row.properties.Crew.relation.length === 2 && row.properties["What Changes"].rich_text[0].text.content === "Night exteriors added.", JSON.stringify(row));
  check("4. …the Drive folder", world.driveMade.includes("proj/2-logistics/shoot-2"), world.driveMade.join());
  check("4. …and one line in the activity log", world.logs.length === 1 && /Shoot 2 · Malibu Pickup set up/.test(world.logs[0].desc), JSON.stringify(world.logs));
  got = await tell(me, "add_shoot", { ...ADD, confirm: t });
  check("4. the same token again is refused (used once)", /already used|isn't one I gave/.test(got.text), got.text);
  check("4. …and made nothing twice", world.posts.filter((p) => p.properties.Shoot).length === 1, "");
}

// ── 5. Notion down ──────────────────────────────────────────────────────────

const DOWN = { project: "ZZ Test Shoots", start: "2026-12-01", name: "Winter Day", crew: ["Dan Gaffer"] };
{
  seedNotion(); world.driveMade.length = 0; world.logs.length = 0; world.down = true;
  let got = await tell(me, "add_shoot", DOWN);
  check("5. Notion down: the preview still comes, and says why", got.json && got.json.step === 1 && /Notion can't be reached/.test(got.json.notion || ""), got.text);
  check("5. …shoot numbered from the record (Shoot 2) with the Drive folder planned", got.json && got.json.shoot.label === "Shoot 2 · Winter Day" && got.json.will_make.some((g) => g.system === "DRIVE"), got.text);
  check("5. …and the Notion line is the waiting line", got.json && JSON.stringify(got.json.will_make).includes("Notion row waits for Notion to be reconnected"), got.text);
  const t = got.json.confirm;
  got = await tell(me, "add_shoot", { ...DOWN, confirm: t });
  check("5. confirm does not fail: the shoot is added, Notion row waiting", got.json && got.json.notion === "waiting" && /Notion row waits for Notion to be reconnected/.test(got.text), got.text);
  check("5. …the Drive folder was made", world.driveMade.includes("proj/2-logistics/shoot-2"), world.driveMade.join());
  const facts = (await read(`r/${PZ}/record.json`)).facts;
  check("5. …and the shoot is queued on the record", facts.shoots_waiting && facts.shoots_waiting.value.length === 1 && facts.shoots_waiting.value[0].label === "Shoot 2 · Winter Day", JSON.stringify(facts.shoots_waiting));
  got = await tell(me, "shoots", { project: "ZZ Test Shoots" });
  const waiting = got.json && got.json.shoots.find((s) => s.waiting_for_notion);
  check("5. `shoots` lists it, flagged waiting, with its crew", waiting && waiting.label === "Shoot 2 · Winter Day" && waiting.crew.map((c) => c.name).join() === "Dan Gaffer", got.text);
  // a second add while Notion is still down numbers after the first
  const t2 = (await tell(me, "add_shoot", { project: "ZZ Test Shoots", start: "2026-12-09" })).json;
  check("5. a second add while Notion is down is Shoot 3", t2 && t2.shoot.label === "Shoot 3", JSON.stringify(t2));

  // Notion back: the minute's look makes it
  world.down = false; world.driveMade.length = 0 || 0;
  const lines = await catchUpWaiting(env, PZ, { readiness: async () => ({ ok: true }), depsFor: async () => fakeDeps(), notion: fakeN });
  check("5. Notion back: the waiting shoot is made in Notion", world.posts.some((p) => p.properties.Shoot && p.properties.Shoot.title[0].text.content === "ZZ Test Shoots — Shoot 2 · Winter Day"), `${lines.join(" | ")} ${JSON.stringify(world.posts.map((p) => p.properties.Shoot))}`);
  const after = (await read(`r/${PZ}/record.json`)).facts;
  check("5. …the queue is empty and says so in the look", (after.shoots_waiting.value || []).length === 0 && /made in Notion/.test(lines.join()), JSON.stringify(after.shoots_waiting) + lines.join());
  check("5. …and the Drive folder was not made twice", world.driveMade.filter((k) => k === "proj/2-logistics/shoot-2").length <= 1, world.driveMade.join());
  const again = await catchUpWaiting(env, PZ, { readiness: async () => ({ ok: true }), depsFor: async () => fakeDeps(), notion: fakeN });
  check("5. …and running the catch-up again makes nothing more", again.length === 0 && world.posts.filter((p) => p.properties.Shoot).length === 1, again.join());
}

// ── 5b. the console's own ask (Add Shoot…), Notion down ─────────────────────

{
  const { newShootAsk } = await import("./src/newshootdoor.js");
  const hooks = { readiness: async () => ({ ok: true }), depsFor: async () => fakeDeps() };
  seedNotion(); world.driveMade.length = 0; world.logs.length = 0; world.posts.length = 0; world.down = true;
  await put(`r/${PZ}/record.json`, { ...(await read(`r/${PZ}/record.json`)), facts: { ...(await read(`r/${PZ}/record.json`)).facts, shoots_waiting: undefined } });
  const form = await newShootAsk(env, fakeN, "new_shoot_form", ["ZZ Test Shoots"], hooks);
  check("5b. the sheet opens with Notion down, from the record", form.ok && form.notion_down === true && form.n === 2 && form.crew.map((c) => c.name).join() === "Dan Gaffer,Eve Operator", JSON.stringify({ nd: form.notion_down, nl: form.next_label, crew: (form.crew || []).map((c) => c.name) }));
  const go = { start: "2026-12-14", end: "", name: "", new_scenes: [], pickups: [], crew: [DAN], first_crew: [], newcomers: [], fields: {}, changes: "" };
  const plan = await newShootAsk(env, fakeN, "plan_new_shoot", ["ZZ Test Shoots", go], hooks);
  check("5b. the steps are previewed, the Notion line waiting", plan.ok && plan.can_run && JSON.stringify(plan.groups).includes("Notion row waits"), JSON.stringify(plan).slice(0, 300));
  const out = await newShootAsk(env, fakeN, "run_new_shoot", ["ZZ Test Shoots", go], hooks);
  check("5b. Add does not fail: ok, Drive folder made, Notion waits", out.ok && out.notion_waits === true && world.driveMade.includes("proj/2-logistics/shoot-2") && /waits for Notion/.test(out.report), JSON.stringify(out).slice(0, 300));
  const q = (await read(`r/${PZ}/record.json`)).facts.shoots_waiting;
  check("5b. …and it is queued on the record for when Notion is back", q && q.value.length === 1 && q.value[0].start === "2026-12-14", JSON.stringify(q));
  check("5b. …nothing was written to Notion", world.posts.length === 0 && world.patches.length === 0, JSON.stringify(world.posts));
  world.down = false;
  const lines = await catchUpWaiting(env, PZ, { readiness: async () => ({ ok: true }), depsFor: async () => fakeDeps(), notion: fakeN });
  check("5b. Notion back: the console's waiting shoot is made", world.posts.some((p) => p.properties.Shoot) && /made in Notion/.test(lines.join()), lines.join());
  world.driveMade.length = 0;
  // a project the record does not know: handed over, as before
  world.down = true;
  let handed = false;
  try { await newShootAsk(env, fakeN, "new_shoot_form", ["ZZ Nobody"], hooks); } catch (e) { handed = e instanceof Handoff; }
  check("5b. a project with no record is handed over as before", handed, "");
  world.down = false;
}

// ── 6. set_shoot_crew ───────────────────────────────────────────────────────

{
  seedNotion();
  // the record's shoots now: Shoot 1 only (the Notion look would bring Shoot 2)
  const rec = await read(`r/${PZ}/record.json`);
  rec.facts.shoots = fact([...rec.facts.shoots.value, { id: "8d0000000000000000000000000000aa", title: "ZZ Test Shoots — Shoot 2", label: "Shoot 2", name: "", n: 2, start: "2026-11-03", end: "", status: "Upcoming", section: "", changes: "", spec: [], docs: [] }], 5);
  await put(`r/${PZ}/record.json`, rec);
  world.pages.set("8d0000000000000000000000000000aa", { id: "8d0000000000000000000000000000aa", object: "page", properties: {} });
  let got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "2", add: [{ person: "Fay Grip", role: "Key Grip" }] });
  check("6. adds someone from his Crew directory to a shoot with a role on this project", /Fay Grip added to Shoot 2/.test(got.text) && /Key Grip/.test(got.text), got.text);
  const fay = world.pages.get(FAY).properties;
  check("6. …Notion's Crew row gets the project and the shoot, and its Role is untouched", fay.Shoots.relation.some((r) => r.id === "8d0000000000000000000000000000aa") && fay.Projects.relation.some((r) => r.id === PZ) && fay.Role.multi_select[0].name === "Grip", JSON.stringify(fay));
  const facts = (await read(`r/${PZ}/record.json`)).facts;
  const f = facts.crew.value.find((p) => p.person === FAY);
  check("6. …the record's crew copy has her on Shoot 2 with the role here", f && f.shoots.includes("8d0000000000000000000000000000aa") && f.roles.join() === "Key Grip" && f.roles_here === true, JSON.stringify(f));
  check("6. …and the role is the record's alone (crew_roles)", facts.crew_roles && facts.crew_roles.value[FAY].join() === "Key Grip", JSON.stringify(facts.crew_roles));
  got = await tell(me, "shoots", { project: "ZZ Test Shoots" });
  const s2 = got.json.shoots.find((s) => s.label === "Shoot 2");
  check("6. `shoots` shows her on Shoot 2 only, with the role on this project", s2.crew.some((c) => c.name === "Fay Grip" && c.role === "Key Grip") && !got.json.shoots[0].crew.some((c) => c.name === "Fay Grip"), got.text);
  check("6. …and Dan (on every shoot) is on both", got.json.shoots.every((s) => s.crew.some((c) => c.name === "Dan Gaffer" && c.on_all_shoots)), got.text);

  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "2", add: ["Dan Gaffer"] });
  check("6. adding someone already on every shoot is a no-op", /on every shoot already/.test(got.text) && /Nothing written/.test(got.text), got.text);

  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "1", remove: ["Eve Operator"] });
  check("6. taking someone off their only shoot is refused (would put them on every shoot)", /off_project: true/.test(got.text), got.text);
  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "2", remove: ["Dan Gaffer"] });
  check("6. taking someone who is on every shoot off one shoot tags them to the others", /Dan Gaffer taken off Shoot 2/.test(got.text), got.text);
  const dan = world.pages.get(DAN).properties;
  check("6. …Notion's Crew row for Dan now lists Shoot 1 only", dan.Shoots.relation.length === 1 && dan.Shoots.relation[0].id === SH1, JSON.stringify(dan));
  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "1", remove: ["Eve Operator"], off_project: true });
  check("6. off_project: true takes them off the project's crew", /off the project's crew/.test(got.text), got.text);
  check("6. …they are gone from the record's crew and from Notion's Projects", !(await read(`r/${PZ}/record.json`)).facts.crew.value.some((p) => p.person === EVE) && world.pages.get(EVE).properties.Projects.relation.length === 0, "");

  // Notion down: adding refused, a role alone still works
  world.down = true;
  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "2", add: [{ person: "Fay Grip", role: "Best Boy" }] });
  check("6. Notion down: a role on this project alone still works (record only)", /role on this project: Best Boy/.test(got.text), got.text);
  check("6. …Notion's Role was not written", world.patches.every((p) => !(p.body.properties || {}).Role), "");
  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "1", add: ["Fay Grip"] });
  check("6. Notion down: adding someone to a shoot is refused with the reason", /Notion can't be reached|Notion wouldn't take it/.test(got.text), got.text);
  world.down = false;
  got = await tell(me, "set_shoot_crew", { project: "ZZ Test Shoots", shoot: "2", add: [{ person: "Fay Grip", role: "" }] });
  check("6. an empty role puts them back on their usual Crew role", /usual Crew role/.test(got.text) && !(await read(`r/${PZ}/record.json`)).facts.crew_roles.value[FAY], got.text);
}

// ── 7. record carries the crew per shoot ────────────────────────────────────

{
  await tell(me, "open_project", { project: "ZZ Test Shoots" });
  const got = await tell(me, "record");
  check("7. the record tool returns every shoot with its crew", got.json && got.json.shoots.length === 2 && got.json.shoots.every((s) => Array.isArray(s.crew)), got.text.slice(0, 300));
  const nope = await tell(me, "add_shoot", { start: "2027-01-05" });
  check("7. with the project open, `project` can be left out", nope.json && nope.json.step === 1, nope.text);
  const bad = await tell(me, "add_shoot", { project: "ZZ Test Shoots", start: "not a day" });
  check("7. a bad day is refused plainly", /YYYY-MM-DD/.test(bad.text), bad.text);
}

console.log(`shoottools: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
