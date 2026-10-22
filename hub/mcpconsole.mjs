#!/usr/bin/env node
/**
 * **Projects Console from the connector, in-process** (2026-10-19): the real
 * `serveMcp` and engine (`src/mcp.wasm`) over a bucket held in memory.
 * Nothing real is touched: no Notion, no Drive, no film of his.
 *
 * 1. The confirm token (consolegate.js): runs once; refused when missing,
 *    made up, used, run out, given to somebody else, for another ask, or
 *    when the preview it was given for has moved.
 * 2. The console's tools are offered, and say his OK and his laws.
 * 3. Only he may use them: a director is refused, step 1 included.
 * 4. Link Edits and its Undo, two steps, on a real plan.
 * 5. set_record and set_front no longer set Released: set_stage asks first.
 *
 *     node --import ./hub/nodehook.mjs hub/mcpconsole.mjs
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
  console.log(`  ${String(what).slice(0, 86).padEnd(88)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};

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
      const b = typeof body === "string" ? body : body instanceof Uint8Array ? body : body instanceof ArrayBuffer ? new Uint8Array(body) : String(body);
      m.set(k, { body: b, etag: `e${++n}`, at: Date.now() });
      return obj(k);
    },
    async delete(k) { for (const one of [].concat(k)) m.delete(one); },
    async list({ prefix = "", delimiter, limit = 1000 } = {}) {
      const objects = [], seen = new Set();
      for (const k of [...m.keys()].sort()) {
        if (!k.startsWith(prefix)) continue;
        const rest = k.slice(prefix.length);
        if (delimiter && rest.includes(delimiter)) { seen.add(prefix + rest.split(delimiter)[0] + delimiter); continue; }
        objects.push(obj(k));
        if (objects.length >= limit) break;
      }
      return { objects, delimitedPrefixes: [...seen], truncated: false };
    },
  };
}

const ME = "owner@example.com";
const DIRECTOR = "clara@example.com";
const env = { BUCKET: bucket(), OWNER: ME, HUB_SECRET: "checking-secret", MCP_ASK_WAIT_MS: "0" };
const put = (k, v) => env.BUCKET.put(k, typeof v === "string" ? v : JSON.stringify(v));
const read = async (k) => { const g = await env.BUCKET.get(k); return g ? g.json() : null; };

const { serveMcp, diagramEdit } = await import("./src/mcp.js");
const gate = await import("./src/consolegate.js");
const { keepLinkEdit } = await import("./src/linkedits.js");
const { keys } = await import("../relay/layout.js");

// ── 1. the token, by itself ──────────────────────────────────────────────────
{
  const me = { email: ME };
  const ask = { tool: "big_move", project: "p1", args: { kind: "wrap" } };
  const shown = { title: "Wrap ZZ", lines: ["Notion status → Post"] };
  const t = await gate.issue(env, me, ask, shown);
  check("1. a token is ok-<20 hex>, kept under mcp/confirm/", /^ok-[0-9a-f]{20}$/.test(t) && Boolean(await read(`mcp/confirm/${t}.json`)), t);
  let r = await gate.redeem(env, me, "", ask, shown);
  check("1. no token: refused, saying to look first and get his OK", !r.ok && /needs his OK/.test(r.why), r.why);
  r = await gate.redeem(env, me, "ok-00000000000000000000", ask, shown);
  check("1. a made-up token: refused", !r.ok && /not one this server gave/.test(r.why), r.why);
  r = await gate.redeem(env, me, "please-go", ask, shown);
  check("1. not even a token's shape: refused", !r.ok && /not a confirm token/.test(r.why), r.why);
  r = await gate.redeem(env, { email: DIRECTOR }, t, ask, shown);
  check("1. somebody else's: refused", !r.ok && /somebody else/.test(r.why), r.why);
  r = await gate.redeem(env, me, t, { ...ask, args: { kind: "delete" } }, shown);
  check("1. for another ask (other arguments): refused", !r.ok && /different ask/.test(r.why), r.why);
  r = await gate.redeem(env, me, t, { ...ask, tool: "set_stage" }, shown);
  check("1. for another tool: refused", !r.ok && /different ask/.test(r.why), r.why);
  r = await gate.redeem(env, me, t, ask, { ...shown, lines: ["Notion status → Post", "Shoot Dates move on"] });
  check("1. a preview that moved since: refused as stale", !r.ok && r.stale && /changed since he saw/.test(r.why), r.why);
  r = await gate.redeem(env, me, t, ask, shown, { now: Date.now() + 11 * 60 * 1000 });
  check("1. after ten minutes: refused as run out", !r.ok && r.stale && /ran out/.test(r.why), r.why);
  r = await gate.redeem(env, me, t, ask, { lines: shown.lines, title: shown.title });
  check("1. the same preview (keys in any order), in time: runs", r.ok, r.why);
  r = await gate.redeem(env, me, t, ask, shown);
  check("1. …and only once", !r.ok && /already used/.test(r.why), r.why);
  check("1. typed_name and confirm are not part of the ask", gate.canon({ kind: "x", confirm: "ok-1", typed_name: "A" }) === gate.canon({ kind: "x" }));
}

// ── a film, and him and a director ──────────────────────────────────────────
const RELAY = "01a00b57e8790941866a989900000000";
const PAGE = "5a000000000000000000000000000001";
await put(`p/${RELAY}/manifest.json`, { format: 1, project: RELAY, title: "Daybreak", engine: "0.1.0" });
const dir = join(ROOT, "studio/fixtures/Daybreak.shotlist/changes");
for (const f of readdirSync(dir)) await put(`p/${RELAY}/logs/${f}`, readFileSync(join(dir, f), "utf8"));
await put(`p/${RELAY}/people.json`, { version: 1, people: [{ email: DIRECTOR, role: "editor" }], links: [] });
const fact = (value, v = 1) => ({ value, v, at: "2026-10-14T10:00:00.000Z" });
await put(`r/${PAGE}/record.json`, { version: 1, page: PAGE, name: "Daybreak", film: { relay: RELAY }, facts: { type: fact("Music Video"), status: fact("Active") } });

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
const me = await tokenFor(ME, "claude-a");
const her = await tokenFor(DIRECTOR, "claude-b");

// ── 2. offered, in his words ────────────────────────────────────────────────
{
  const { tools } = await tell(me, "tools/list");
  const t = Object.fromEntries(tools.map((x) => [x.name, x]));
  const need = ["big_move", "set_stage", "close_project", "closed_projects", "reopen_project", "new_project", "create_portal", "replace_link",
    "portal_up", "portal_shared", "notion_conflicts", "settle_conflict", "customize_record", "record_templates", "set_type_template",
    "drive_template", "set_drive_template", "update_filing_rules", "add_shoot", "activity", "undo_activity", "mac_jobs", "mac_job",
    "media_folders", "index_drive", "project_health", "repair_project", "studio_backup", "link_edits", "undo_link_edit", "next_steps",
    "project_crew", "set_crew", "suggestions", "agents", "agent_do", "console_result"];
  const missing = need.filter((n) => !t[n]);
  check("2. every console tool is offered", !missing.length, missing.join(", "));
  const twoStep = ["big_move", "set_stage", "close_project", "reopen_project", "new_project", "create_portal", "replace_link", "portal_up",
    "portal_shared", "settle_conflict", "customize_record", "set_type_template", "set_drive_template", "update_filing_rules",
    "undo_activity", "mac_job", "undo_link_edit", "agent_do"];
  const vague = twoStep.filter((n) => !t[n] || !/Two steps, with his OK in between/.test(t[n].description) || !/Show him that preview/.test(t[n].description) || !t[n].inputSchema.properties.confirm);
  check("2. each two-step tool says: show him the preview, wait for his yes, then confirm", !vague.length, vague.join(", "));
  const big = (t.big_move || {}).description || "";
  check("2. big_move says his laws: no trash but Delete, Delete true with 30 days, media drives untouched and create-only",
    /nothing is sent to any trash by a big move except Delete/.test(big) && /true delete/.test(big) && /30 days/.test(big)
    && /never touches a media drive/.test(big) && /create-only/.test(big), big.slice(0, 300));
  check("2. …and Prepare Showcase copies exactly what the filing rules say, never website/", /exactly what the filing rules and showcase-structure say/.test(big) && /never website\//.test(big));
  check("2. replace_link says every sent link stops working", /Every link he has already sent stops working/.test((t.replace_link || {}).description || ""));
  check("2. media_folders says create-only", /Create-only/.test((t.media_folders || {}).description || ""));
  check("2. set_record no longer takes Released; it points at set_stage",
    /Development or Active/.test(t.set_record.inputSchema.properties.status.description) && /set_stage/.test(t.set_record.description));
  check("2. the Studio-only new_shoot points at add_shoot", /add_shoot/.test(t.new_shoot.description));
}

// ── 3. his alone ────────────────────────────────────────────────────────────
{
  await tell(her, "open_project", { project: "Daybreak" });
  for (const [name, args] of [["big_move", { kind: "delete" }], ["replace_link", {}], ["link_edits", {}], ["closed_projects", {}], ["new_project", { name: "X" }], ["agent_do", { action: "run_now", agent: "a" }]]) {
    const got = await tell(her, name, args);
    check(`3. a director (an editor on the film) is refused ${name}, step 1 included`, /Only he may do that/.test(got.text), got.text);
  }
  const confirm = Object.keys(env.BUCKET.m).length;
  void confirm;
  check("3. …and no token was ever kept for her", ![...env.BUCKET.m.keys()].some((k) => k.startsWith("mcp/confirm/") && JSON.parse(env.BUCKET.m.get(k).body).email === DIRECTOR));
}

// ── 4. Link Edits, his list, and its Undo in two steps ──────────────────────
{
  await tell(me, "open_project", { project: "Daybreak" });
  const scenes = (await tell(me, "scenes")).json;
  const scene = scenes[0].id || scenes[0].number;
  // A link visitor draws a wall, as the share link's editor would.
  const visitor = { email: "public-link/visitor01", via: "link" };
  const said = await diagramEdit(env, RELAY, visitor, ctx, { scene: String(scenes[0].number), ops: [{ op: { op: "add", els: [{ kind: "wall", x: 0, y: 0, x2: 4, y2: 0 }] } }], link: true }, true);
  const base = keys.pages(RELAY).replace(/pages\/$/, "");
  await keepLinkEdit(env.BUCKET, base, { me: "visitor01", scene: said.scene || String(scenes[0].number), ops: [1], labels: ["Wall"], said });
  const walls = async () => {
    const d = (await tell(me, "diagram", { scene: String(scenes[0].number) })).text;
    return (d.match(/"kind":\s*"wall"/g) || []).length;
  };
  const before = await walls();
  if (process.env.DEBUG) console.log("said", JSON.stringify(said).slice(0, 600));
  let got = await tell(me, "link_edits");
  const list = got.json || [];
  check("4. link_edits lists the visitor's change: who, which plan, what", list.length === 1 && /Link visitor/.test(list[0].who) && list[0].did[0] === "Wall" && !list[0].undone && list[0].changes > 0, got.text);
  const key = list[0] && list[0].key;
  got = await tell(me, "undo_link_edit", { key });
  check("4. step 1 answers the preview and a token, and changes nothing", got.json && /Undo Link visitor/.test(got.json.title) && /^ok-/.test(got.json.confirm) && (await walls()) === before, got.text);
  const token = got.json && got.json.confirm;
  got = await tell(me, "undo_link_edit", { key });
  const second = got.json && got.json.confirm;
  got = await tell(me, "undo_link_edit", { key, confirm: "ok-11111111111111111111" });
  check("4. step 2 with a token this server never gave: refused, nothing changed", /not one this server gave/.test(got.text) && (await walls()) === before, got.text);
  got = await tell(her, "undo_link_edit", { key, confirm: token });
  check("4. his token in a director's hands: refused", /Only he may/.test(got.text) && (await walls()) === before, got.text);
  got = await tell(me, "undo_link_edit", { key, confirm: token });
  check("4. step 2 with his token: the visitor's wall is taken back", /Took back Link visitor/.test(got.text) && (await walls()) === before - 1, `${got.text} walls ${before}→${await walls()}`);
  got = await tell(me, "undo_link_edit", { key, confirm: token });
  check("4. the same token again: refused (each runs once)", /already used|Already undone/.test(got.text), got.text);
  got = await tell(me, "undo_link_edit", { key, confirm: second });
  check("4. a token from before it was undone: the preview moved, so refused", /Already undone|changed since/.test(got.text) && (await walls()) === before - 1, got.text);
  got = await tell(me, "link_edits");
  check("4. …and his list says Undone", got.json && got.json[0].undone === true, got.text);
  void scene;
}

// ── 5. Complete (was Released) asks first ──────────────────────────────────────────────────
{
  await tell(me, "open_project", { project: "Daybreak" });
  await tell(me, "set_front", { source: `notion:${PAGE}` });
  let got = await tell(me, "set_record", { status: "Released" });
  check("5. set_record status Released is refused, pointing at set_stage", /set_stage/.test(got.text) && (await read(`r/${PAGE}/record.json`)).facts.status.value === "Active", got.text);
  got = await tell(me, "set_record", { status: "Complete" });
  check("5. …and Complete, its new name, too", /set_stage/.test(got.text) && (await read(`r/${PAGE}/record.json`)).facts.status.value === "Active", got.text);
  // Complete (was Released, 2026-10-20): the release date is optional, the pop-up says Complete
  got = await tell(me, "set_stage", { stage: "Complete" });
  check("5. set_stage Complete with no release date: asks, Mark Complete, a token, no problems",
    got.json && got.json.can_run === true && got.json.confirm && got.json.title === "Mark Daybreak Complete?"
      && got.json.button === "Mark Complete" && !got.json.problems, got.text);
  got = await tell(me, "set_stage", { stage: "Released" });
  check("5. the old word still works: the same pop-up", got.json && got.json.can_run === true && got.json.title === "Mark Daybreak Complete?", got.text);
  // an Archived project moved back asks first, as the console does (confirms-report.md); the stand-in can't run it, so the preview is the check
  const rec = await read(`r/${PAGE}/record.json`);
  await put(`r/${PAGE}/record.json`, { ...rec, facts: { ...rec.facts, status: { ...rec.facts.status, value: "Archived" } } });
  got = await tell(me, "set_stage", { stage: "Active" });
  check("5. set_stage Active on an Archived project: asks first, a token, nothing changed yet",
    got.json && got.json.can_run === true && got.json.confirm && got.json.title === "Move Daybreak Back to Active?"
      && got.json.lines[0] === "Its Drive folder and showcase stay in the archive" && got.json.button === "Move to Active"
      && (await read(`r/${PAGE}/record.json`)).facts.status.value === "Archived", got.text);
  got = await tell(me, "set_stage", { stage: "Development", confirm: "ok-not-a-real-token" });
  check("5. …a made-up token is refused, nothing changed", !(got.json && got.json.confirm) && (await read(`r/${PAGE}/record.json`)).facts.status.value === "Archived", got.text);
  await put(`r/${PAGE}/record.json`, rec);
  got = await tell(me, "set_stage", { stage: "Development" });
  check("5. …a project not Archived: Development still applies at once, no pop-up", !(got.json && got.json.confirm) && !/Back to/.test(got.text), got.text);
}

// ── 6. The portal's who-sees-what tools ask first too (mcpgate.js) ──────────
{
  const g = await import("./src/mcpgate.js");
  check("6. needsGate: set_board only for share / link_edit", g.needsGate("set_board", { share: "link" }) && g.needsGate("set_board", { link_edit: false }) && !g.needsGate("set_board", { rename: "x" }));
  check("6. needsGate: Share, What Viewers See, views, Show on Portal, archive/remove page, real media deletes",
    ["set_access", "set_visibility", "share_view", "set_view", "show_on_portal", "remove_page", "archive_page", "delete_media", "delete_unused_media"].every((n) => g.needsGate(n, {})));
  const { tools } = await tell(me, "tools/list");
  const t = Object.fromEntries(tools.map((x) => [x.name, x]));
  const unsaid = ["set_access", "set_visibility", "share_view", "set_view", "show_on_portal", "remove_page", "archive_page", "delete_media", "delete_unused_media", "set_board"]
    .filter((n) => !t[n] || !/Two steps|two steps/.test(t[n].description) || !t[n].inputSchema.properties.confirm);
  check("6. each gated tool says two steps and takes confirm", !unsaid.length, unsaid.join(", "));
  const loose = [];
  const walk = (s, at) => { if (!s || typeof s !== "object") return; if (Array.isArray(s.type)) loose.push(`${at} type list`); if (s.type === "array" && (!s.items || !s.items.type)) loose.push(`${at} items`); for (const [k, v] of Object.entries(s.properties || {})) walk(v, `${at}.${k}`); if (s.items) walk(s.items, `${at}[]`); };
  for (const x of tools) walk(x.inputSchema, x.name);
  check("6. every list in tools/list says what it holds; no type given as a list", !loose.length, loose.join(", "));

  await tell(me, "open_project", { project: "Daybreak" });
  const people = async () => (await read(`p/${RELAY}/people.json`)).people.map((p) => p.email);
  let got = await tell(me, "set_access", { add: [{ email: "zz-gate@example.com" }] });
  check("6. set_access step 1: the change in words and a token; nobody added", got.json && /Adds zz-gate@example.com as viewer/.test(JSON.stringify(got.json.lines)) && /^ok-/.test(got.json.confirm || "") && !(await people()).includes("zz-gate@example.com"), got.text);
  const token = got.json && got.json.confirm;
  got = await tell(her, "set_access", { add: [{ email: "zz-gate@example.com" }], confirm: token });
  check("6. …a director with his token: refused", /Only he may/.test(got.text) && !(await people()).includes("zz-gate@example.com"), got.text);
  got = await tell(me, "set_access", { add: [{ email: "zz-other@example.com" }], confirm: token });
  check("6. …his token for another person: refused", /different ask/.test(got.text) && !(await people()).includes("zz-other@example.com"), got.text);
  got = await tell(me, "set_access", { add: [{ email: "zz-gate@example.com" }], confirm: token });
  check("6. …with his token: added", (await people()).includes("zz-gate@example.com"), got.text);
  got = await tell(me, "set_access", { add: [{ email: "zz-gate@example.com" }], confirm: token });
  check("6. …the same token again: refused", /already used/.test(got.text), got.text);
  got = await tell(me, "set_access", { remove: ["zz-gate@example.com"] });
  got = await tell(me, "set_access", { remove: ["zz-gate@example.com"], confirm: got.json && got.json.confirm });
  check("6. …and taken off again the same way (test person removed)", !(await people()).includes("zz-gate@example.com"), got.text);

  got = await tell(me, "share_view", { name: "zz gate", filters: [{ field: "Shot Size", value: "W" }] });
  const viewsNow = async () => JSON.stringify((await tell(me, "views")).json || (await tell(me, "views")).text);
  check("6. share_view step 1: no link made yet", got.json && /^ok-/.test(got.json.confirm || "") && !/zz gate/.test(await viewsNow()), got.text);
  got = await tell(me, "share_view", { name: "zz gate", filters: [{ field: "Shot Size", value: "W" }], confirm: got.json && got.json.confirm });
  check("6. …confirmed: the view link is made", /zz gate|zz-gate/i.test(await viewsNow()), got.text);
  got = await tell(me, "set_view", { view: "zz gate", remove: true });
  check("6. set_view remove: step 1 says it is for good", got.json && /for good/.test(JSON.stringify(got.json.lines)), got.text);
  got = await tell(me, "set_view", { view: "zz gate", remove: true, confirm: got.json && got.json.confirm });
  check("6. …confirmed: gone (test view removed)", !/zz gate|zz-gate/i.test(await viewsNow()), got.text);

  got = await tell(her, "delete_unused_media", {});
  check("6. delete_unused_media: a director is refused", /Only he may/.test(got.text), got.text);
  const media = Object.keys(Object.fromEntries(env.BUCKET.m)).filter((k) => k.includes("/logs/")).length;
  got = await tell(me, "delete_unused_media", {});
  check("6. delete_unused_media step 1: a preview, nothing deleted", got.json && Array.isArray(got.json.lines) && /Not undoable|Nothing is unused/.test(got.text)
    && Object.keys(Object.fromEntries(env.BUCKET.m)).filter((k) => k.includes("/logs/")).length === media, got.text);
  got = await tell(her, "add_scene", { number: "99", heading: "INT. ZZ GATE - DAY" });
  check("6. Studio's own edits are not gated: a director still adds a scene", !/confirm|Only he may/.test(got.text) && !got.error, got.text);
}

console.log(`\nmcpconsole: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
