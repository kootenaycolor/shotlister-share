#!/usr/bin/env node
/**
 * **The server answers the phone's Notion edits itself** — `src/cloud.js`,
 * 2026-10-10 (stage 1 of Projects Console without the Mac).
 *
 * A hub of its own on 8851 and a small Notion on 8852 that remembers what is
 * written to it. Each check posts an ask exactly as the iPhone app does
 * (`POST /console/studio/asks`) and reads the answer back the way it polls.
 *
 * - the edits are answered on arrival, by the server, in the Mac's shapes;
 * - what the screen saw is checked first: a field moved in Notion is answered
 *   `moved` and nothing is written;
 * - a shoot's dates carry the project's Shoot Dates when they were its;
 * - a call that is not the server's still waits for the Mac;
 * - a Notion that refuses to be written to hands the ask to the Mac, pending,
 *   with nothing written;
 * - the project page (`project_page`) is read here — shoots, sheets, people
 *   from the record, documents, the Next box — and a Next line hidden from
 *   the phone stays hidden until it is brought back.
 *
 *     node hub/cloudasks.mjs
 */
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = 8851, NPORT = 8852;
const H = `http://127.0.0.1:${PORT}`;
const TOKEN = "checking-token-not-a-secret";
const NTOKEN = "checking-notion-token";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(70)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(70)} FAIL — ${why}`); }
};

// ---- a Notion that remembers ------------------------------------------------
const PROJECTS = "feedface-0000-4000-8000-000000000001";
const P = "11111111-2222-3333-4444-555555555555";
const SHOOT = "aaaaaaaa-0000-0000-0000-000000000001";
const SHEET = "aaaaaaaa-0000-0000-0000-000000000002";
const CREW = "feedface-0000-4000-8000-000000000004";
const MATE = "cccccccc-0000-0000-0000-000000000001";
const BUSY = "cccccccc-0000-0000-0000-000000000002";
const SHOOTS = "feedface-0000-4000-8000-000000000002";
const SPECS = "feedface-0000-4000-8000-000000000003";
const DOCS = "feedface-0000-4000-8000-000000000005";
const DOC = "aaaaaaaa-0000-0000-0000-000000000003";
// thirty other projects: past the 25 a page carries
const OTHERS = Array.from({ length: 30 }, (_, i) => `eeeeeeee-0000-0000-0000-${String(i).padStart(12, "0")}`);
const text = (s) => [{ type: "text", plain_text: s, text: { content: s } }];
let readOnly = false;
let writes = 0;
let projectQueries = 0;
const pages = {};
function reset() {
  writes = 0;
  readOnly = false;
  pages[P] = { object: "page", id: P, properties: {
    Project: { type: "title", title: text("Cloud Film") },
    Status: { type: "select", select: { name: "Development" } },
    Website: { type: "url", url: null },
    "Shoot Dates": { type: "date", date: { start: "2026-11-02", end: "2026-11-04" } },
  } };
  pages[SHOOT] = { object: "page", id: SHOOT, url: "https://notion.so/shoot1", parent: { data_source_id: SHOOTS }, properties: {
    Shoot: { type: "title", title: text("Cloud Film — Shoot 1") },
    Dates: { type: "date", date: { start: "2026-11-02", end: "2026-11-04" } },
    "What Changes": { type: "rich_text", rich_text: [] },
    Project: { type: "relation", relation: [{ id: P }] },
    Crew: { type: "relation", relation: [] },
    "Camera Spec Sheet": { type: "relation", relation: [{ id: SHEET }] },
  } };
  pages[DOC] = { object: "page", id: DOC, url: "https://notion.so/doc", parent: { data_source_id: DOCS }, properties: {
    Name: { type: "title", title: text("Call Sheet Day 1") },
    Category: { type: "multi_select", multi_select: [{ name: "Call sheet" }] },
    Projects: { type: "relation", relation: [{ id: P }] },
    Shoot: { type: "relation", relation: [{ id: SHOOT }] },
    Hub: { type: "checkbox", checkbox: true },
  } };
  for (const id of Object.keys(pages)) if (id.startsWith("dddddddd")) delete pages[id];
  pages[MATE] = { object: "page", id: MATE, url: "https://notion.so/mate", parent: { data_source_id: CREW }, properties: {
    Name: { type: "title", title: text("Tess Marlow De Vries") },
    Type: { type: "select", select: { name: "Person" } },
    Role: { type: "multi_select", multi_select: [{ name: "Gaffer" }] },
    Email: { type: "email", email: "paula@example.com" },
    Projects: { type: "relation", relation: [] },
    Shoots: { type: "relation", relation: [] },
  } };
  pages[BUSY] = { object: "page", id: BUSY, parent: { data_source_id: CREW }, properties: {
    Name: { type: "title", title: text("Busy Grip") },
    Type: { type: "select", select: { name: "Person" } },
    Role: { type: "multi_select", multi_select: [] },
    Projects: { id: "prj%3D", type: "relation", relation: OTHERS.slice(0, 25).map((id) => ({ id })), has_more: true },
    Shoots: { type: "relation", relation: [] },
  } };
  pages[SHEET] = { object: "page", id: SHEET, url: "https://notion.so/sheet", parent: { data_source_id: SPECS }, properties: {
    Name: { type: "title", title: text("Cloud Film — Spec") },
    Camera: { type: "rich_text", rich_text: text("Alexa 35") },
    Lenses: { type: "rich_text", rich_text: text("Cooke S4/i — 18, 25, 32mm — T2") },
    "Frame Rate": { type: "number", number: 24 },
    "LUT Labels": { type: "rich_text", rich_text: [] },
    "Production LUT": { type: "files", files: [{ name: "Show LUT", type: "external", external: { url: "https://drive.google.com/a" } }] },
    Projects: { type: "relation", relation: [{ id: P }] },
  } };
}
reset();

// Notion keeps what it is given as plain_text for reading back.
function stored(prop, old) {
  const kind = old ? old.type : Object.keys(prop)[0];
  if (kind === "rich_text" || kind === "title") {
    return { type: kind, [kind]: (prop[kind] || []).map((t) => ({ ...t, plain_text: t.text.content })) };
  }
  return { type: kind, [kind]: prop[kind] };
}

const notion = createServer(async (req, res) => {
  const send = (status, body) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify(body)); };
  if (req.headers.authorization !== `Bearer ${NTOKEN}`) return send(401, { object: "error", code: "unauthorized" });
  let body = "";
  for await (const bit of req) body += bit;
  const json = body ? JSON.parse(body) : {};
  const path = req.url.replace(/^\/v1\//, "");
  if (req.method === "POST" && path === `data_sources/${PROJECTS}/query`) {
    projectQueries += 1;
    const want = json.filter.title.equals;
    return send(200, { object: "list", results: Object.values(pages).filter((p) => p.properties.Project && p.properties.Project.type === "title"
      && p.properties.Project.title.map((t) => t.plain_text).join("") === want) });
  }
  if (req.method === "POST" && path === `data_sources/${CREW}/query`) {
    return send(200, { object: "list", has_more: false, results: Object.values(pages).filter((p) => p.parent && p.parent.data_source_id === CREW) });
  }
  // the project page's readings: a data source's rows on this project
  const listed = /^data_sources\/([0-9a-f-]+)\/query$/.exec(path);
  if (req.method === "POST" && listed && [SHOOTS, SPECS, DOCS].includes(listed[1])) {
    const { property, relation } = json.filter;
    return send(200, { object: "list", has_more: false, results: Object.values(pages).filter((p) => p.parent
      && p.parent.data_source_id === listed[1] && ((p.properties[property] || {}).relation || []).some((r) => r.id === relation.contains)) });
  }
  if (req.method === "GET" && path === `data_sources/${CREW}`) {
    return send(200, { object: "data_source", properties: {
      Role: { type: "multi_select", multi_select: { options: [{ name: "Gaffer" }] } },
      Department: { type: "select", select: { options: [{ name: "Vendor" }] } },
      Company: { type: "select", select: { options: [{ name: "Odd Kind" }] } },
      Location: { type: "select", select: { options: [] } },
    } });
  }
  if (req.method === "POST" && path === "pages") {
    if (readOnly) return send(403, { object: "error", code: "restricted_resource" });
    writes += 1;
    const id = `dddddddd-0000-0000-0000-${String(writes).padStart(12, "0")}`;
    const props = {};
    for (const [k, v] of Object.entries(json.properties)) props[k] = stored(v);
    pages[id] = { object: "page", id, url: `https://notion.so/${id}`, parent: { data_source_id: json.parent.data_source_id }, properties: props, icon: json.icon || null };
    return send(200, pages[id]);
  }
  const rel = /^pages\/([0-9a-f-]+)\/properties\/([^?]+)/.exec(path);
  if (req.method === "GET" && rel && pages[rel[1]]) {
    const all = rel[1] === BUSY && !pages[BUSY].touched ? OTHERS : pages[rel[1]].properties.Projects.relation.map((r) => r.id);
    return send(200, { object: "list", has_more: false, results: all.map((id) => ({ object: "property_item", type: "relation", relation: { id } })) });
  }
  if (req.method === "GET" && path.startsWith(`blocks/${P.replace(/-/g, "")}/children`)) {
    return send(200, { object: "list", has_more: false, results: [{ object: "block", id: "abababab-0000-0000-0000-000000000001", type: "child_database" }] });
  }
  if (req.method === "GET" && path.startsWith("views?database_id=")) return send(200, { results: [{ id: "view1" }] });
  if (req.method === "GET" && path === "views/view1") {
    return send(200, { data_source_id: CREW, url: "https://notion.so/crew-view", filter: { relation: { contains: P } } });
  }
  if (req.method === "GET" && path === `data_sources/${SPECS}`) return send(200, { object: "data_source", properties: {} });
  if (req.method === "GET" && path === `data_sources/${PROJECTS}`) {
    return send(200, { object: "data_source", properties: {
      Status: { type: "select", select: { options: ["Development", "Active", "Post", "Archived"].map((name) => ({ name })) } },
      Type: { type: "select", select: { options: [{ name: "Narrative" }, { name: "Commercial" }] } },
      Length: { type: "select", select: { options: [{ name: "Short" }] } },
      Color: { type: "select", select: { options: [{ name: "orange" }] } },
    } });
  }
  const m = /^pages\/([0-9a-f-]+)$/.exec(path);
  if (m && pages[m[1]]) {
    if (req.method === "GET") return send(200, pages[m[1]]);
    if (req.method === "PATCH") {
      if (readOnly) return send(403, { object: "error", code: "restricted_resource", message: "Insufficient permissions for this endpoint." });
      writes += 1;
      for (const [k, v] of Object.entries(json.properties || {})) pages[m[1]].properties[k] = stored(v, pages[m[1]].properties[k]);
      if (m[1] === BUSY) pages[BUSY].touched = true;
      return send(200, pages[m[1]]);
    }
  }
  return send(404, { object: "error", code: "object_not_found" });
});
notion.listen(NPORT, "127.0.0.1");

// ---- the hub ----------------------------------------------------------------
const state = mkdtempSync(join(tmpdir(), "cloudasks-"));
const W = join(HERE, "node_modules/.bin/wrangler");
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`,
  "--var", `NOTION_TOKEN:${NTOKEN}`, "--var", `NOTION_API:http://127.0.0.1:${NPORT}/v1/`], { cwd: HERE, stdio: process.env.HUBLOG ? "inherit" : "ignore" });

const call = (path, method = "GET", body) => fetch(`${H}/console/${path}`, {
  method, headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));

/** As the phone does it: post, then read the ask back by its id. */
async function ask(method, args) {
  const posted = await call("studio/asks", "POST", { method, args, by: "phone" });
  const back = await call(`studio/asks/${posted.body.id}`);
  return back.body;
}

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    up = await fetch(`${H}/console/studio`, { headers: { authorization: `Bearer ${TOKEN}` } }).then((r) => r.ok).catch(() => false);
  }
  if (!up) throw new Error("the hub did not start");

  say("\nAnswered by the server, on arrival");
  let got = await ask("set_stage", ["Cloud Film", "Active"]);
  check("set_stage is done by the server", got.state === "done" && got.by_done === "server", JSON.stringify(got));
  check("…answers as the Mac does", JSON.stringify(got.result) === JSON.stringify({ ok: true, status: "Active" }), JSON.stringify(got.result));
  check("…and Notion holds it", pages[P].properties.Status.select.name === "Active", JSON.stringify(pages[P].properties.Status));
  got = await ask("set_stage", ["Cloud Film", "Archived"]);
  check("Archived from the phone is refused in the Mac's words", got.state === "failed" && /ritual/.test(got.error), JSON.stringify(got));
  got = await ask("set_stage", ["No Such Film", "Active"]);
  check("a project with no row says so", got.result && got.result.why === "no Notion row", JSON.stringify(got));

  got = await ask("set_project_website", ["Cloud Film", "your-website.example/cloud"]);
  check("set_project_website adds https:// and answers the address", got.result === "https://your-website.example/cloud", JSON.stringify(got));
  check("…and Notion holds it", pages[P].properties.Website.url === "https://your-website.example/cloud", JSON.stringify(pages[P].properties.Website));

  got = await ask("fact_choices", []);
  check("fact_choices: status is only the two stages", JSON.stringify(got.result.choices.status) === '["Development","Active"]', JSON.stringify(got.result));

  say("\nShoots and dates, checked against what the screen saw");
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-02", end: "2026-11-04" }, { start: "2026-11-09", end: "2026-11-10" }]);
  check("edit_shoot moves the dates", got.result && got.result.ok && JSON.stringify(got.result.changed) === '["Dates"]', JSON.stringify(got));
  check("…and the project's Shoot Dates follow (they were this shoot's)", got.result.project_dates === true
    && pages[P].properties["Shoot Dates"].date.start === "2026-11-09", JSON.stringify(pages[P].properties["Shoot Dates"]));
  const before = writes;
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-02" }, { start: "2026-11-03" }]);
  check("a stale screen is answered `moved`", got.result && got.result.ok === false && got.result.moved && got.result.moved.start === "2026-11-09", JSON.stringify(got));
  check("…and nothing is written", writes === before, `${writes - before} writes`);
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, {}, { name: "Malibu Pickup" }]);
  check("a shoot's own name goes after its number", pages[SHOOT].properties.Shoot.title.map((t) => t.plain_text).join("") === "Cloud Film — Shoot 1 · Malibu Pickup", JSON.stringify(pages[SHOOT].properties.Shoot));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, {}, { name: "Shoot 4 Pickup" }]);
  check("…and a typed number is refused in words", /Leave out/.test(got.result.why || ""), JSON.stringify(got));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, {}, { start: "2026-12-10", end: "2026-12-01" }]);
  check("an end before the start is refused", got.result.why === "The last day is before the first.", JSON.stringify(got));
  got = await ask("edit_project_dates", ["Cloud Film", { start: "2026-11-09", end: "2026-11-10" }, "2026-11-12", ""]);
  check("edit_project_dates writes a one-day shoot", got.result.ok && pages[P].properties["Shoot Dates"].date.start === "2026-11-12"
    && !pages[P].properties["Shoot Dates"].date.end, JSON.stringify(pages[P].properties["Shoot Dates"]));

  say("\nClearing a project's dates is a record edit (2026-10-15)");
  const PAGEKEY = P.replace(/-/g, "");
  const seed = join(state, "record-seed.json");
  const put = (rec) => { writeFileSync(seed, JSON.stringify(rec)); spawnSync(W, ["r2", "object", "put", `shotlister-preview/r/${PAGEKEY}/record.json`, "--file", seed, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" }); };
  const recordNow = () => JSON.parse(spawnSync(W, ["r2", "object", "get", `shotlister-preview/r/${PAGEKEY}/record.json`, "--pipe", "--local", "--persist-to", state], { cwd: HERE, encoding: "utf8" }).stdout || "{}").facts;
  put({ page: PAGEKEY, facts: { status: { value: "Active", v: 1 }, shoot_dates: { value: "2026-11-12", v: 1 } } });
  const wrote = writes;
  got = await ask("edit_project_dates", ["Cloud Film", { start: "2026-11-12", end: "" }, "", ""]);
  check("a project with a record: the clear is saved on the record", got.result && got.result.ok && got.result.record === true, JSON.stringify(got));
  let rec = recordNow() || {};
  check("…its Shoot Dates is empty and its status untouched", rec.shoot_dates && rec.shoot_dates.value === "" && rec.shoot_dates.v === 2
    && rec.status.value === "Active", JSON.stringify(rec));
  check("…and Notion was not written (it follows on the link's minute)", writes === wrote && pages[P].properties["Shoot Dates"].date.start === "2026-11-12", `${writes - wrote} writes`);
  got = await ask("edit_project_dates", ["Cloud Film", { start: "2026-11-12", end: "" }, "", ""]);
  check("the same clear sent again is not a clash", got.result && got.result.ok === true && got.result.changed.length === 0 && !got.result.moved, JSON.stringify(got));
  got = await ask("edit_project_dates", ["Cloud Film", { start: "", end: "" }, "2026-12-01", "2026-12-03"]);
  rec = recordNow() || {};
  check("dates set again, one version on", got.result.ok && rec.shoot_dates.value === "2026-12-01/2026-12-03" && rec.shoot_dates.v === 3, JSON.stringify([got.result, rec.shoot_dates]));
  got = await ask("edit_project_dates", ["Cloud Film", { start: "2026-11-12", end: "" }, "", ""]);
  check("a screen that is out of date is answered moved, nothing written", got.result.ok === false && got.result.moved && got.result.moved.start === "2026-12-01"
    && (recordNow() || {}).shoot_dates.v === 3, JSON.stringify(got.result));
  say("\nStage, website and a shoot's own edits are record edits too (2026-10-15)");
  const SHOOTKEY = SHOOT.replace(/-/g, "");
  const shootNow = () => { const pr = pages[SHOOT].properties, d = pr.Dates.date || {}; return { id: SHOOTKEY, title: pr.Shoot.title.map((t) => t.plain_text).join(""),
    label: "Shoot 1", name: "Malibu Pickup", n: 1, start: d.start || "", end: d.end && d.end !== d.start ? d.end : "", status: "", section: "",
    changes: (pr["What Changes"].rich_text || []).map((t) => t.plain_text).join(""), spec: [], docs: [] }; };
  put({ page: PAGEKEY, facts: { status: { value: "Active", v: 1 }, shoot_dates: { value: "2026-11-09/2026-11-10", v: 1 },
    shoots: { value: [shootNow()], v: 1 } } });
  let w0 = writes;
  got = await ask("set_stage", ["Cloud Film", "Development"]);
  rec = recordNow() || {};
  check("set_stage with a record is saved on the record", got.result && got.result.ok && got.result.record === true && rec.status.value === "Development" && rec.status.v === 2, JSON.stringify([got.result, rec.status]));
  check("…and Notion was not written or read back", writes === w0 && pages[P].properties.Status.select.name === "Active", `${writes - w0} writes`);
  got = await ask("set_stage", ["Cloud Film", "Development"]);
  check("the same stage again changes nothing", got.result.ok && (recordNow() || {}).status.v === 2, JSON.stringify(got.result));
  got = await ask("set_project_website", ["Cloud Film", "your-website.example/hall"]);
  rec = recordNow() || {};
  check("set_project_website with a record is saved on the record", got.result === "https://your-website.example/hall" && rec.website.value === "https://your-website.example/hall", JSON.stringify([got, rec.website]));
  check("…and Notion was not written", writes === w0 && pages[P].properties.Website.url === "https://your-website.example/cloud", `${writes - w0} writes`);
  got = await ask("set_project_website", ["Cloud Film", "not a web address"]);
  check("a website that isn't an address is refused in words", got.state === "failed" && /web address/.test(got.error || ""), JSON.stringify(got));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-09", end: "2026-11-10" }, { start: "2026-11-20", end: "2026-11-21" }]);
  rec = recordNow() || {};
  const waiting = (rec.shoot_edits || {}).value || {};
  check("edit_shoot with a record is saved on the record, waiting for Notion", got.result && got.result.ok && got.result.record === true && JSON.stringify(got.result.changed) === '["Dates"]'
    && waiting[SHOOTKEY] && waiting[SHOOTKEY].want.start === "2026-11-20" && waiting[SHOOTKEY].from.start === "2026-11-09", JSON.stringify([got.result, waiting]));
  check("…the project's Shoot Dates follow on the record (they were this shoot's)", got.result.project_dates === true && rec.shoot_dates.value === "2026-11-20/2026-11-21", JSON.stringify(rec.shoot_dates));
  check("…and Notion's row was not written", writes === w0 && pages[SHOOT].properties.Dates.date.start === "2026-11-09", `${writes - w0} writes`);
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-09" }, { start: "2026-11-25" }]);
  check("a stale screen is answered moved with what the record holds, nothing written", got.result.ok === false && got.result.moved && got.result.moved.start === "2026-11-20"
    && (recordNow() || {}).shoot_edits.v === 1, JSON.stringify(got.result));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { notes: "" }, { notes: "Night exteriors." }]);
  rec = recordNow() || {};
  check("a second edit on the same shoot keeps what Notion had at the start", got.result.ok && rec.shoot_edits.value[SHOOTKEY].want.notes === "Night exteriors."
    && rec.shoot_edits.value[SHOOTKEY].want.start === "2026-11-20" && rec.shoot_edits.value[SHOOTKEY].from.start === "2026-11-09", JSON.stringify(rec.shoot_edits.value));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-20", end: "2026-11-21" }, { start: "2026-11-20", end: "2026-11-21" }]);
  check("the same dates sent again are not a clash", got.result.ok && got.result.changed.length === 0, JSON.stringify(got.result));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, {}, { start: "2026-12-10", end: "2026-12-01" }]);
  check("an end before the start is still refused", got.result.why === "The last day is before the first.", JSON.stringify(got.result));
  got = await ask("project_page", ["Cloud Film"]);
  const lead = ((got.result || {}).shoots || []).find((x) => String(x.id || "").replace(/-/g, "") === SHOOTKEY || x.start === "2026-11-20");
  check("the project page shows the edit at once, laid over Notion's row", lead && lead.start === "2026-11-20" && lead.end === "2026-11-21" && lead.changes === "Night exteriors.", JSON.stringify(lead));
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-20", end: "2026-11-21" }, { start: "", end: "" }]);
  rec = recordNow() || {};
  check("clearing a shoot's dates is an edit like any other, and its project's dates clear with it", got.result.ok && rec.shoot_edits.value[SHOOTKEY].want.start === "" && rec.shoot_dates.value === "", JSON.stringify([got.result, rec.shoot_edits.value[SHOOTKEY], rec.shoot_dates]));
  got = await ask("project_page", ["Cloud Film"]);
  const cleared = ((got.result || {}).shoots || []).find((x) => String(x.id || "").replace(/-/g, "") === SHOOTKEY);
  check("…and the page shows it cleared", cleared && cleared.start === "", JSON.stringify(cleared));
  put({ page: PAGEKEY, facts: { status: { value: "Active", v: 1 }, shoots: { value: [], v: 1 } } });
  got = await ask("edit_shoot", ["Cloud Film", SHOOT, { start: "2026-11-09", end: "2026-11-10" }, { start: "2026-11-30", end: "2026-11-30" }]);
  rec = recordNow() || {};
  check("a shoot newer than the record's copy is added to the copy, then edited there", got.result.ok && got.result.record === true
    && (rec.shoots.value || []).length === 1 && rec.shoot_edits.value[SHOOTKEY].want.start === "2026-11-30" && pages[SHOOT].properties.Dates.date.start === "2026-11-09",
    JSON.stringify([got.result, rec.shoots, rec.shoot_edits]));

  say("\nA save on the record does not ask Notion which project it is");
  put({ page: PAGEKEY, facts: { status: { value: "Active", v: 1 }, shoot_dates: { value: "2026-11-09/2026-11-10", v: 1 } } });
  writeFileSync(seed, JSON.stringify({ names: { "Cloud Film": PAGEKEY } }));
  spawnSync(W, ["r2", "object", "put", "shotlister-preview/s/project-names.json", "--file", seed, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  const q0 = projectQueries, wq = writes;
  got = await ask("set_stage", ["Cloud Film", "Development"]);
  check("set_stage found its project from the names list: not one Notion query", got.result && got.result.record === true && projectQueries === q0 && writes === wq, `${projectQueries - q0} queries`);
  got = await ask("set_project_website", ["Cloud Film", "https://your-website.example/fast"]);
  check("…set_project_website too", got.result === "https://your-website.example/fast" && projectQueries === q0, `${projectQueries - q0} queries`);
  got = await ask("edit_project_dates", ["Cloud Film", { start: "2026-11-09", end: "2026-11-10" }, "2026-11-12", "2026-11-13"]);
  check("…edit_project_dates too", got.result && got.result.record === true && projectQueries === q0, `${projectQueries - q0} queries`);
  got = await ask("set_stage", ["Not In The List", "Active"]);
  check("a name the list does not know is asked about in Notion, as before", got.result && got.result.why === "no Notion row" && projectQueries > q0, JSON.stringify(got.result));
  spawnSync(W, ["r2", "object", "delete", "shotlister-preview/s/project-names.json", "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });

  say("\nA spec sheet that is still a row in Notion is moved to the record by hand");
  got = await ask("spec_adopt", ["Cloud Film", "principal", SHEET]);
  rec = recordNow() || {};
  check("spec_adopt writes the record's sheet and no Notion", got.result && got.result.ok && got.result.moved === true && got.result.fact === "spec_project"
    && rec.spec_project && rec.spec_project.value.moved && rec.spec_project.value.moved.from === "notion", JSON.stringify([got.result, rec.spec_project]).slice(0, 400));
  const w1 = writes;
  got = await ask("spec_adopt", ["Cloud Film", "principal", SHEET]);
  check("…and asking again leaves the sheet as it is", got.result && got.result.ok && got.result.moved === false && writes === w1, JSON.stringify(got.result));
  got = await ask("spec_adopt", ["Cloud Film", SHOOT, MATE]);
  check("a sheet that isn't this project's is refused", got.result && got.result.ok === false, JSON.stringify(got.result));

  // the later checks start from a project with no record yet
  spawnSync(W, ["r2", "object", "delete", `shotlister-preview/r/${PAGEKEY}/record.json`, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });

  say("\nSpec sheets, lenses and LUTs");
  got = await ask("edit_spec_sheet", ["Cloud Film", SHEET, { Camera: "Alexa 35" }, { Camera: "Venice 2" }]);
  check("edit_spec_sheet writes a text field", got.result.ok && pages[SHEET].properties.Camera.rich_text[0].plain_text === "Venice 2", JSON.stringify(got));
  got = await ask("edit_spec_sheet", ["Cloud Film", SHEET, { "Frame Rate": "24" }, { "Frame Rate": "23.976" }]);
  check("…and a number field as a number", pages[SHEET].properties["Frame Rate"].number === 23.976, JSON.stringify(pages[SHEET].properties["Frame Rate"]));
  got = await ask("edit_spec_sheet", ["Cloud Film", SHEET, {}, { "Frame Rate": "fast" }]);
  check("…and refuses words in a number", /needs a number/.test(got.result.why || ""), JSON.stringify(got));
  got = await ask("edit_entries", ["Cloud Film", SHEET, "Camera", "Venice 2",
    [{ label: "A Cam", value: "Venice 2", edited: true }, { label: "B Cam", value: "FX6", edited: true }]]);
  check("edit_entries writes one line per camera", got.result.text === "A Cam: Venice 2\nB Cam: FX6", JSON.stringify(got));
  got = await ask("edit_lens_sets", ["Cloud Film", SHEET, "Cooke S4/i — 18, 25, 32mm — T2",
    [{ raw: "Cooke S4/i — 18, 25, 32mm — T2" }, { label: "B Cam", series: "Ultra Primes", focals: ["16", "24"], stop: "t1.9", edited: true }]]);
  check("edit_lens_sets keeps an untouched set as typed and writes the new one",
    got.result.lenses === "Cooke S4/i — 18, 25, 32mm — T2\nB Cam: Ultra Primes — 16, 24 — T1.9", JSON.stringify(got));
  got = await ask("edit_luts", ["Cloud Film", SHEET, ["Show LUT"], "", { url: "https://drive.google.com/b", name: "Day LUT", label: "Day" }]);
  check("edit_luts adds a link and its label", got.result.ok && pages[SHEET].properties["Production LUT"].files.length === 2
    && pages[SHEET].properties["LUT Labels"].rich_text[0].plain_text === "Day: Day LUT", JSON.stringify(pages[SHEET].properties["LUT Labels"]));
  got = await ask("edit_lut_labels", ["Cloud Film", SHEET, "Day: Day LUT",
    [{ name: "Show LUT", url: "https://drive.google.com/a", label: "Night" }], ["a stray line"]]);
  check("edit_lut_labels rewrites the labels, keeping a stray line", pages[SHEET].properties["LUT Labels"].rich_text[0].plain_text === "Night: Show LUT\na stray line", JSON.stringify(got));


  say("\nCrew");
  got = await ask("crew_directory", []);
  check("crew_directory lists Crew, sorted", got.result.ok && got.result.people.map((p) => p.name).join("|") === "Busy Grip|Tess Marlow De Vries", JSON.stringify(got.result));
  got = await ask("crew_dupes", [{ name: "Tess Marlow" }]);
  check("crew_dupes finds a near-miss spelling", got.result.dupes.length === 1 && got.result.dupes[0].why === "similar name", JSON.stringify(got.result));
  got = await ask("crew_new", ["Cloud Film", { name: "Tess Marlow" }]);
  check("crew_new refuses a look-alike, making nothing", got.result.ok === false && got.result.dupes.length === 1, JSON.stringify(got.result));
  got = await ask("crew_new", ["Cloud Film", { name: "Nova Reyes", role: "Key Grip, Rigging", email: "nova@example.com" }]);
  const made = got.result && pages[Object.keys(pages).find((k) => k.startsWith("dddddddd"))];
  check("crew_new makes the person on the project", got.result.ok && made && made.properties.Projects.relation[0].id === P
    && made.properties.Role.multi_select.map((o) => o.name).join(",") === "Key Grip,Rigging", JSON.stringify(got.result));
  check("…with the Mac's gray person icon", made && made.icon && made.icon.external.url === "https://www.notion.so/icons/person-masculine_gray.svg", JSON.stringify(made && made.icon));
  got = await ask("crew_new", ["Cloud Film", { name: "Credited Person", credit: "Producer" }]);
  check("…one with a credit is made, and says the credit could not land with no record yet", got.state === "done"
    && got.result.ok && /^Added, but not credited/.test(got.result.why || ""), JSON.stringify(got));
  got = await ask("company_new", ["", { name: "Odd Kinds" }]);
  check("company_new: a company already a choice is refused", got.result.dupes && got.result.dupes[0].why === "a company already", JSON.stringify(got.result));
  got = await ask("company_new", ["", { name: "Keslow Camera", kind: "Equipment House", website: "keslowcamera.com" }]);
  const co = Object.values(pages).find((p) => p.properties.Name && p.properties.Name.title && p.properties.Name.title[0] && p.properties.Name.title[0].plain_text === "Keslow Camera");
  check("company_new makes a Vendor row with its website", got.result.ok && co && co.properties.Type.select.name === "Vendor"
    && co.properties["Source Link"].url === "https://keslowcamera.com", JSON.stringify(got.result));
  check("…with the Mac's gray city icon", co && co.icon && co.icon.external.url === "https://www.notion.so/icons/city_gray.svg", JSON.stringify(co && co.icon));
  const usualRole = JSON.stringify(pages[MATE].properties.Role);
  got = await ask("crew_edit", ["Cloud Film", MATE, true, [SHOOT], [], null]);
  check("crew_edit puts a person on the project and its shoot", got.result.ok
    && pages[MATE].properties.Projects.relation[0].id === P && pages[MATE].properties.Shoots.relation[0].id === SHOOT, JSON.stringify(got.result));
  got = await ask("crew_edit", ["Cloud Film", BUSY, true]);
  check("someone on 30 projects keeps all 30 when added to one more", got.result.ok
    && pages[BUSY].properties.Projects.relation.length === 31, `${pages[BUSY].properties.Projects.relation.length} projects`);
  got = await ask("project_crew_url", ["Cloud Film"]);
  check("project_crew_url finds the page's own Crew view", got.result.url === "https://notion.so/crew-view", JSON.stringify(got.result));

  say("\nThe project page, read by the server");
  const PB = P.replace(/-/g, "");
  await call(`record/${PB}`, "PUT", { name: "Cloud Film", lights: { media: "off", portal: "off" } });
  await call(`record/${PB}/facts`, "PUT", { by: "check", changes: {
    crew: { base: 0, value: [{ person: MATE.replace(/-/g, ""), name: "Tess Marlow De Vries", roles: ["Gaffer"],
      shoots: [SHOOT.replace(/-/g, "")], all_shoots: false }] },
    credits: { base: 0, value: [{ role: "Director", people: ["Dana Field"] }] } } });
  pages[SHOOT].properties["What Changes"] = { type: "rich_text", rich_text: text("Lenses change to the Fujinon Premavista 24-100 zoom.") };
  got = await ask("project_page", ["Cloud Film"]);
  const pg = got.result || {};
  check("project_page is answered by the server", got.state === "done" && got.by_done === "server" && pg.ok === true, JSON.stringify(got).slice(0, 300));
  const sh = (pg.shoots || [])[0] || {};
  check("…its shoot, by its own name, with its sheet", pg.shoots.length === 1 && sh.label === "Malibu Pickup" && sh.kind === "Principal"
    && sh.spec && sh.spec.id === SHEET.replace(/-/g, "") && sh.spec.cameras.multi === true, JSON.stringify(sh).slice(0, 300));
  const names = (pg.people || []).map((p) => p.name);
  check("…the record's crew and a credited person not in Crew", names.join("|") === "Tess Marlow De Vries|Dana Field"
    && pg.people[1].credits[0] === "Director" && pg.people[1].in_crew === false
    && pg.groups.map((g) => g.label).join("|") === "Above the line|No department", JSON.stringify(pg.people).slice(0, 300));
  check("…who is on the shoot", JSON.stringify(sh.people) === JSON.stringify([MATE.replace(/-/g, ""), ""]), JSON.stringify(sh.people));
  const doc = (pg.documents || []).find((d) => d.kind === "doc") || {};
  check("…its documents: the doc with its shoot and box, then the sheet", pg.documents.length === 2 && doc.on_portal === true
    && doc.shoots[0] === "Malibu Pickup" && pg.documents[1].kind === "sheet", JSON.stringify(pg.documents).slice(0, 300));
  const lens = pg.next.checks.find((c) => c.kind === "lens");
  check("…the Next box names the lens the sheet does not", lens && lens.notes === "Fujinon Premavista 24-100" && lens.level === "bad", JSON.stringify(pg.next));
  const media = pg.next.checks.find((c) => c.kind === "media");
  check("…and the media line, hideable", media && media.key === `${SHOOT.replace(/-/g, "")}|media|`, JSON.stringify(pg.next));
  check("…with no Drive on the server", pg.drive_path === "" && pg.folders.length === 0 && pg.page_id === P, JSON.stringify({ d: pg.drive_path, f: pg.folders }));
  got = await ask("next_check_hide", ["Cloud Film", media.key, true]);
  check("next_check_hide hides the line", got.state === "done" && got.result.ok === true, JSON.stringify(got));
  got = await ask("project_page", ["Cloud Film"]);
  check("…and the page leaves it out, counted", !got.result.next.checks.some((c) => c.kind === "media") && got.result.next.hidden === 1, JSON.stringify(got.result.next));
  got = await ask("next_check_hide", ["Cloud Film", "x|lens|", true]);
  check("a lens line can't be hidden, in the Mac's words", got.result.ok === false && got.result.why === "not a line that can be hidden: 'x|lens|'", JSON.stringify(got));
  got = await ask("next_check_show", ["Cloud Film", SHOOT.replace(/-/g, "")]);
  check("next_check_show brings the shoot's lines back", got.result.ok === true && got.result.shown === 1, JSON.stringify(got));
  got = await ask("project_page", ["Cloud Film"]);
  check("…and the page shows it again", got.result.next.checks.some((c) => c.kind === "media") && got.result.next.hidden === 0, JSON.stringify(got.result.next));
  got = await ask("project_page", ["No Such Film"]);
  check("a project with no row says so, as the Mac does", got.result && got.result.ok === false && got.result.why === "no Notion row for this project", JSON.stringify(got));


  say("\nA role on this project only");
  const MB = MATE.replace(/-/g, "");
  let facts;
  const crewNow = async () => (await call(`record/${PB}/facts`)).body.facts || {};
  got = await ask("crew_edit", ["Cloud Film", MATE, null, null, null, ["Key Grip", "Gaffer", "Key Grip"]]);
  facts = await crewNow();
  check("a role here lands on the record: crew copy flagged, crew_roles beside it", got.result.ok && got.result.changed.join() === "roles"
    && facts.crew.value[0].roles.join() === "Key Grip,Gaffer" && facts.crew.value[0].roles_here === true
    && JSON.stringify(facts.crew_roles.value) === JSON.stringify({ [MB]: ["Key Grip", "Gaffer"] }), JSON.stringify(got.result) + JSON.stringify(facts.crew));
  check("…and Notion's Crew role is never written", JSON.stringify(pages[MATE].properties.Role) === usualRole, JSON.stringify(pages[MATE].properties.Role));
  got = await ask("project_page", ["Cloud Film"]);
  check("…the project page lists the role held here", (got.result.people || [])[0].roles.includes("Key Grip"), JSON.stringify((got.result.people || [])[0]));
  got = await ask("crew_edit", ["Cloud Film", MATE, null, null, null, []]);
  facts = await crewNow();
  check("an empty role puts them back on their usual Crew role", got.result.ok && facts.crew.value[0].roles_here === undefined
    && facts.crew.value[0].roles.join() === pages[MATE].properties.Role.multi_select.map((o) => o.name).sort().join()
    && Object.keys(facts.crew_roles.value).length === 0, JSON.stringify(facts.crew));
  got = await ask("crew_edit", ["Cloud Film", "cccccccc-0000-0000-0000-0000000000ff", null, null, null, ["Grip"]]);
  check("someone not on the project's crew is refused", got.result.ok === false && /Add them first/.test(got.result.why), JSON.stringify(got.result));

  say("\nCredits and the portal, by the server");
  got = await ask("crew_new", ["Cloud Film", { name: "Rhea Moss", credit: "Producer" }]);
  facts = (await call(`record/${PB}/facts`)).body.facts || {};
  check("crew_new with a credit puts them on the record's credits", got.result.ok && !got.result.why
    && JSON.stringify(facts.credits.value) === JSON.stringify([{ role: "Director", people: ["Dana Field"] }, { role: "Producer", people: ["Rhea Moss"] }])
    && facts.producer && facts.producer.value === "Rhea Moss", JSON.stringify(facts.credits));
  got = await ask("company_new", ["Cloud Film", { name: "Night Owl Films", kind: "Production Company", credit: true }]);
  facts = (await call(`record/${PB}/facts`)).body.facts || {};
  const owl = Object.values(pages).find((p) => p.properties.Name && p.properties.Name.title && p.properties.Name.title[0] && p.properties.Name.title[0].plain_text === "Night Owl Films");
  check("company_new with a credit: on the project, credited Production Company", got.result.ok && owl
    && owl.properties.Projects.relation[0].id === P && facts.production_company && facts.production_company.value === "Night Owl Films", JSON.stringify(got.result));
  got = await ask("portal_down", ["Cloud Film", true]);
  check("portal_down with no portal says so, as the Mac does", got.result.ok === false && got.result.why === "this film has no portal page", JSON.stringify(got));
  got = await ask("create_portal", ["Cloud Film"]);
  check("create_portal makes a portal for a project with no film", got.state === "done" && got.result.ok && got.result.page === PB, JSON.stringify(got).slice(0, 300));
  got = await ask("portal_down", ["Cloud Film", true]);
  const down = (await call(`${PB}/down`)).body;
  check("portal_down takes it down, through the hub's own door", got.result.ok && down.down === true, JSON.stringify(down));
  got = await ask("portal_down", ["Cloud Film", false]);
  check("…and back up", got.result.ok && (await call(`${PB}/down`)).body.down === false, JSON.stringify(got.result));
  got = await ask("portal_down", ["No Such Film", true]);
  check("a project with no row says so", got.result.why === "no Notion row for this project", JSON.stringify(got));

  say("\nThe Mac's, still the Mac's");
  got = await ask("create_showcase", ["Cloud Film"]);
  check("a Drive call waits for the Mac", got.state === "pending" && !got.by_done, JSON.stringify(got));

  say("\nA Notion that cannot be written to");
  readOnly = true;
  const was = pages[P].properties.Status.select.name;
  put({ page: PAGEKEY, facts: { status: { value: "Active", v: 1 } } });
  got = await ask("set_stage", ["Cloud Film", "Development"]);
  check("a project with a record is saved all the same: Notion is not in the way", got.state === "done" && got.result && got.result.record === true
    && (recordNow() || {}).status.value === "Development", JSON.stringify(got));
  spawnSync(W, ["r2", "object", "delete", `shotlister-preview/r/${PAGEKEY}/record.json`, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  got = await ask("set_stage", ["Cloud Film", "Development"]);
  check("the ask is handed to the Mac, pending", got.state === "pending" && !got.by_done, JSON.stringify(got));
  check("…with nothing written", pages[P].properties.Status.select.name === was, pages[P].properties.Status.select.name);
} catch (e) {
  fail += 1;
  say(`  ${e.message}`);
} finally {
  hub.kill("SIGTERM");
  notion.close();
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
