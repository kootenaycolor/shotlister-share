#!/usr/bin/env node
/**
 * **The Mac's router and the one list, on the server** (2026-10-14, stage 5
 * step 3). Checks, with a bucket held in memory and a stand-in Notion on
 * this machine (never the real ones):
 *
 * - the asks door: the same `key` twice is one ask; `here_only` is declined,
 *   not left for the Mac's mailbox; a held ask the server turns out not to
 *   take is declined, not handed back; the phone's asks are unchanged;
 * - `POST /console/studio/now`: reads answered on the spot, never kept; a
 *   write refused there; a method the server does not answer declined;
 * - the folder template: today's until written, compare-and-set, refusals,
 *   the Drive folders' switch reading it and never keeping it;
 * - a folder a Mac made offline: finished by its marker's ID, never doubled,
 *   and someone else's folder still refused;
 * - the one list: the Mac's rules (`engine.fetch_projects`,
 *   `record.overlay_rows`), case by case, and the films shelf.
 *
 *     node hub/router.mjs
 */
import { register } from "node:module";
import { createServer } from "node:http";

register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(88)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ── a bucket in memory, compare-and-set like R2 ─────────────────────────────
function memoryBucket() {
  const items = new Map();
  let n = 0;
  const obj = (key) => {
    const x = items.get(key);
    return x && { key, etag: x.etag, async json() { return JSON.parse(x.body); }, async text() { return x.body; } };
  };
  return {
    items,
    async get(key) { return obj(key) || null; },
    async head(key) { return obj(key) || null; },
    async put(key, body, opts = {}) {
      const have = items.get(key);
      const c = opts.onlyIf || {};
      if (c.etagMatches && (!have || have.etag !== c.etagMatches)) return null;
      if (c.etagDoesNotMatch === "*" && have) return null;
      const etag = `e${++n}`;
      items.set(key, { body: typeof body === "string" ? body : JSON.stringify(body), etag });
      return { key, etag };
    },
    async delete(key) { items.delete(key); },
    async list({ prefix = "", delimiter } = {}) {
      const keys = [...items.keys()].filter((k) => k.startsWith(prefix)).sort();
      if (!delimiter) return { objects: keys.map((key) => ({ key })), truncated: false };
      const pre = new Set();
      const objects = [];
      for (const k of keys) {
        const rest = k.slice(prefix.length);
        const at = rest.indexOf(delimiter);
        if (at >= 0) pre.add(prefix + rest.slice(0, at + 1)); else objects.push({ key: k });
      }
      return { objects, delimitedPrefixes: [...pre], truncated: false };
    },
  };
}

// ── a stand-in Notion on this machine ────────────────────────────────────────
const NOTION = { pages: {}, calls: [] };
const notion = createServer(async (req, res) => {
  let body = "";
  for await (const c of req) body += c;
  NOTION.calls.push({ method: req.method, url: req.url });
  const m = /^\/v1\/data_sources\/([0-9a-f-]+)\/query$/.exec(req.url);
  if (req.method === "POST" && m) {
    const rows = NOTION.pages[m[1]] || [];
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ object: "list", results: rows, has_more: false }));
    return;
  }
  res.writeHead(404, { "content-type": "application/json" });
  res.end(JSON.stringify({ object: "error", code: "object_not_found", message: "no" }));
});
await new Promise((ok) => notion.listen(0, "127.0.0.1", ok));
const NOTION_API = `http://127.0.0.1:${notion.address().port}/v1/`;

const { studioDoor } = await import("./src/studio.js");
const RA = await import("./src/routerasks.js");
const later = await import("./src/later.js");
const FT = await import("./src/foldertemplate.js");
const DF = await import("./src/drivefolders.js");
const OL = await import("./src/onelist.js");

function envOf(extra = {}) {
  return { BUCKET: memoryBucket(), NOTION_TOKEN: "stand-in", NOTION_API, ...extra };
}
async function door(env, method, path, body) {
  const url = `https://hub.test${path}`;
  const req = new Request(url, { method, body: body === undefined ? undefined : JSON.stringify(body), headers: { "content-type": "application/json" } });
  const parts = path.split("/").filter(Boolean);
  const got = await studioDoor(req, env, parts, { waitUntil() {} });
  let json = null;
  try { json = await got.json(); } catch { json = null; }
  return { status: got.status, json };
}
const asks = async (env) => JSON.parse((env.BUCKET.items.get("s/asks.json") || { body: "[]" }).body);

// ════ the asks door ══════════════════════════════════════════════════════════
console.log("the asks door");
check("a key is kept only when it looks like one", RA.keyOf({ key: "mac-0f3a9c21b7d4" }) === "mac-0f3a9c21b7d4" && RA.keyOf({ key: "x" }) === "" && RA.keyOf({ key: "a b c d e f g h" }) === "" && RA.keyOf({}) === "");
check("here_only only when said true", RA.hereOnly({ here_only: true }) && !RA.hereOnly({ here_only: "yes" }) && !RA.hereOnly({}));
check("the newest ask under a key is found", RA.sameKey([{ id: "1", key: "k" }, { id: "2", key: "j" }, { id: "3", key: "k" }], "k").id === "3" && RA.sameKey([], "k") === null && RA.sameKey([{ key: "" }], "") === null);
check("no write is answered on the spot", ["create_project", "run_new_shoot", "set_stage", "edit_shoot", "set_project_facts", "portal_down", "crew_new", "film_backup", "plan_new_shoot"].every((m) => !RA.NOW_READS.has(m)));
{
  // a method the server does not answer (the Mac's): here_only → declined, not kept
  const env = envOf();
  const a = await door(env, "POST", "/console/studio/asks", { method: "index_volume", args: ["wd-4"], by: "mac-router", here_only: true, key: "mac-aaaaaaaaaaaa" });
  check("here_only: an ask the server does not take is declined", a.status === 200 && a.json.state === "declined", JSON.stringify(a.json));
  check("…and nothing is left for the Mac's mailbox", (await asks(env)).length === 0, JSON.stringify(await asks(env)));
  // the phone's ask, unchanged: pending for the Mac
  const p = await door(env, "POST", "/console/studio/asks", { method: "index_volume", args: ["wd-4"], by: "phone" });
  check("the phone's ask (no here_only) still waits for the Mac", p.json.state === "pending" && (await asks(env)).length === 1 && !("here_only" in p.json));
  // the same key twice: one ask
  const k1 = await door(env, "POST", "/console/studio/asks", { method: "agents", args: ["roster"], by: "mac-router", key: "mac-bbbbbbbbbbbb" });
  const k2 = await door(env, "POST", "/console/studio/asks", { method: "agents", args: ["roster"], by: "mac-router", key: "mac-bbbbbbbbbbbb" });
  check("the same key twice is one ask, answered with the one kept", k1.json.id === k2.json.id && (await asks(env)).filter((x) => x.key === "mac-bbbbbbbbbbbb").length === 1, `${k1.json.id} ${k2.json.id}`);
  const k3 = await door(env, "POST", "/console/studio/asks", { method: "agents", args: ["roster"], by: "mac-router", key: "mac-cccccccccccc" });
  check("…a different key is a different ask", k3.json.id !== k1.json.id);
}
{
  // a held ask the server turns out not to take: declined when here_only
  const item = { id: "abcdefabcdef", method: "create_project", args: [{}], state: "pending", asked: new Date().toISOString() };
  const held = later.heldItem({ ...item, here_only: true });
  const back = later.answered(held, null);
  check("a held ask sent here_only and not the server's after all is declined", back.state === "declined" && back.done_at);
  const phone = later.answered(later.heldItem(item), null);
  check("…the phone's goes back to the Mac as before", phone.state === "pending" && !phone.by_done);
}

// ════ the on-the-spot door ═══════════════════════════════════════════════════
console.log("reads on the spot");
{
  const env = envOf();
  const w = await door(env, "POST", "/console/studio/now", { method: "set_stage", args: ["X", "Active"] });
  check("a write is refused on the spot door", w.status === 400, JSON.stringify(w));
  const d = await door(env, "POST", "/console/studio/now", { method: "drive_tree", args: ["wd-9"] });
  check("a read the server answers is answered, and nothing is kept", ["done", "failed", "declined"].includes(d.json.state) && (await asks(env)).length === 0, JSON.stringify(d.json));
  const noKey = envOf({ NOTION_TOKEN: "" });
  const n = await door(noKey, "POST", "/console/studio/now", { method: "project_list" });
  check("with no Notion key the server declines (the Mac reads it itself)", n.json.state === "declined", JSON.stringify(n.json));
}

// ════ the folder template ════════════════════════════════════════════════════
console.log("the folder template");
{
  const env = envOf();
  const t0 = await door(env, "GET", "/console/studio/template");
  check("until written: today's Drive template, the media template, version 0", eq(t0.json.drive, DF.PROJECT_TEMPLATE) && eq(t0.json.media, FT.MEDIA_TEMPLATE) && t0.json.v === 0);
  check("…with the shoot folders' rule for offline New Shoot", eq(t0.json.shoot.sections, DF.SHOOT_SECTIONS) && eq(t0.json.shoot.folders, DF.SHOOT_TEMPLATE));
  const bad = await door(env, "PUT", "/console/studio/template", { drive: ["a/b"], base: 0 });
  check("a child before its parent is refused", bad.status === 400, JSON.stringify(bad.json));
  const dup = await door(env, "PUT", "/console/studio/template", { drive: ["a", "A"], base: 0 });
  check("the same folder twice (any case) is refused", dup.status === 400);
  const dot = await door(env, "PUT", "/console/studio/template", { media: [".hidden"], base: 0 });
  check("a dot name is refused", dot.status === 400);
  const want = [...DF.PROJECT_TEMPLATE, "z-other/notes"];
  const ok = await door(env, "PUT", "/console/studio/template", { drive: want, base: 0, by: "check" });
  check("a good change from version 0 is kept as version 1, media as it was", ok.status === 200 && ok.json.v === 1 && eq(ok.json.drive, want) && eq(ok.json.media, FT.MEDIA_TEMPLATE), JSON.stringify(ok.json));
  const stale = await door(env, "PUT", "/console/studio/template", { drive: DF.PROJECT_TEMPLATE, base: 0 });
  check("a change from an old version is refused with the template as it is now", stale.status === 409 && stale.json.now.v === 1);
  const s = await DF.settingsOf(env);
  check("the Drive folders' switch reads the master copy's template", eq(s.template, want) && s.template_master === true);
  const kept = DF.changedSettings(s, { on: true, by: "check" });
  check("…and never keeps it in its own settings", !("template" in kept) && !("template_master" in kept), JSON.stringify(kept));
  const own = DF.changedSettings(s, { on: true, template: ["x"] });
  check("…a template sent to the switch itself is still its own", eq(own.template, ["x"]));
}

// ════ a folder a Mac made offline ════════════════════════════════════════════
console.log("a folder made offline");
function drive(tree) {
  const items = new Map();
  let n = 0;
  const add = (parent, name, folder, text = "") => { const id = `id${String(++n).padStart(10, "0")}`; items.set(id, { id, name, folder, parent, text }); return id; };
  const root = add(null, "projects", true);
  const made = { mkdir: 0, mkfile: 0 };
  const walk = (parent, node) => { for (const [name, v] of Object.entries(node)) { if (typeof v === "string") add(parent, name, false, v); else walk(add(parent, name, true), v); } };
  walk(root, tree);
  const api = {
    made, items,
    async list(id) { return [...items.values()].filter((x) => x.parent === id).map((x) => ({ id: x.id, name: x.name, folder: x.folder })); },
    async get(id) { const x = items.get(id); return x ? { id, name: x.name, folder: x.folder } : null; },
    async text(id) { return (items.get(id) || {}).text || ""; },
    async mkdir(parent, name) { made.mkdir += 1; const id = add(parent, name, true); return { id, name, folder: true }; },
    async mkfile(parent, name, text) { made.mkfile += 1; const id = add(parent, name, false, text); return { id, name, folder: false }; },
  };
  return { api, root };
}
{
  const ID = "0123456789abcdef0123456789abcdef";
  const marker = `${DF.MARKERS.project.text}${DF.ADOPT_LINE}${ID}\n`;
  const full = {};
  for (const rel of DF.PROJECT_TEMPLATE) {
    let at = full;
    for (const part of rel.split("/")) at = (at[part] = at[part] || {});
  }
  const { api, root } = drive({ "zz-router-test": { ...JSON.parse(JSON.stringify(full)), ".gdrive-project": marker } });
  const settings = { on: true, roots: { projects: root, gigs: root, showcases: root }, scratch: null };
  const plan = await DF.planProject(api, settings, { name: "zz Router Test", id: ID });
  check("a folder whose marker names this project's ID is finished, not refused", plan.ok && plan.adopted === true, JSON.stringify(plan).slice(0, 200));
  const got = await DF.carryOut(api, plan);
  check("…a folder made whole offline: nothing made twice, not even the marker", got.made.length === 0 && api.made.mkdir === 0 && api.made.mkfile === 0 && got.failed.length === 0, JSON.stringify(got.made));
  check("…and its link is the folder that was there", got.ids["projects/zz-router-test"] === [...api.items.values()].find((x) => x.name === "zz-router-test").id);
  check("…said in its own words", /made offline, finished/.test(plan.said));
  const other = await DF.planProject(api, settings, { name: "zz Router Test", id: "f".repeat(32) });
  check("another project's ID: refused, as any folder already there", !other.ok && /already exists/.test(other.why));
  const none = await DF.planProject(api, settings, { name: "zz Router Test" });
  check("no ID: refused, as before", !none.ok && /already exists/.test(none.why));
  // half made offline (the Mac lost its connection to the Drive app mid-way)
  const half = drive({ "zz-half": { "1-creative": {}, ".gdrive-project": marker } });
  const hs = { on: true, roots: { projects: half.root, gigs: half.root, showcases: half.root }, scratch: null };
  const hp = await DF.planProject(half.api, hs, { name: "zz Half", id: ID });
  const hg = await DF.carryOut(half.api, hp);
  check("a folder half made offline: only what is missing is made", hp.ok && hg.made.length === DF.PROJECT_TEMPLATE.length - 1 && !hg.made.some((k) => k.endsWith(".gdrive-project")) && hg.already.includes("projects/zz-half/1-creative"), JSON.stringify(hg.already));
  // no marker at all
  const bare = drive({ "zz-bare": { "1-creative": {} } });
  const bs = { on: true, roots: { projects: bare.root, gigs: bare.root, showcases: bare.root }, scratch: null };
  const bp = await DF.planProject(bare.api, bs, { name: "zz Bare", id: ID });
  check("a folder with no marker is never taken over", !bp.ok);
  // a marker that names the ID only inside a longer line
  const sly = drive({ "zz-sly": { ".gdrive-project": `${DF.MARKERS.project.text}note: not project-id: ${ID}\n` } });
  const ss = { on: true, roots: { projects: sly.root, gigs: sly.root, showcases: sly.root }, scratch: null };
  check("…nor one that only mentions the ID", !(await DF.planProject(sly.api, ss, { name: "zz Sly", id: ID })).ok);
}

// ════ the one list ═══════════════════════════════════════════════════════════
console.log("the one list");
const page = (id, title, { status = "Active", type = "Narrative", length = "", dates = null, color = null, icon = null, director = [], drive = null, website = null, edited = "2026-10-01T00:00:00.000Z" } = {}) => ({
  id, url: `https://www.notion.so/${id.replace(/-/g, "")}`, last_edited_time: edited, icon,
  properties: {
    Project: { type: "title", title: [{ plain_text: title }] },
    Status: { type: "select", select: status ? { name: status } : null },
    Type: { type: "select", select: type ? { name: type } : null },
    Length: { type: "select", select: length ? { name: length } : null },
    Color: { type: "select", select: color ? { name: color, color } : null },
    "Shoot Dates": { type: "date", date: dates },
    Director: { type: "relation", relation: director.map((d) => ({ id: d })) },
    "Drive Folder": { type: "url", url: drive },
    Website: { type: "url", url: website },
  },
});
const crewPage = (id, name) => ({ id, properties: { Name: { type: "title", title: [{ plain_text: name }] } } });
const shootPage = (id, title, project, start, end = null, status = "") => ({
  id, url: `https://www.notion.so/${id}`, properties: {
    Name: { type: "title", title: [{ plain_text: title }] }, Dates: { type: "date", date: { start, end } },
    Status: { type: "select", select: status ? { name: status } : null }, Project: { type: "relation", relation: [{ id: project }] },
  } });
const P1 = "11111111-1111-1111-1111-111111111111", P2 = "22222222-2222-2222-2222-222222222222";
const P3 = "33333333-3333-3333-3333-333333333333", P4 = "44444444-4444-4444-4444-444444444444";
const pages = [
  page(P1, "Zeta", { status: "Active", type: "Commercial", dates: { start: "2026-11-02", end: "2026-11-04" }, director: ["aaaa-1", "aaaa-2"], icon: { type: "icon", icon: { name: "fire", color: "red" } } }),
  page(P2, "alpha", { status: "Post", type: "Narrative", color: "blue", icon: { type: "icon", icon: { name: "unknown-glyph", color: "green" } } }),
  page(P3, "Beta", { status: "Development", type: "Personal", website: "https://example.com" }),
  page(P4, "Archive Me", { status: "Archived", type: "", icon: { type: "emoji", emoji: "x" } }),
];
const crew = [crewPage("aaaa1", "Ann"), crewPage("aaaa2", "Bo")];
const shoots = [shootPage("s1", "Zeta — Shoot 1", P1, "2026-07-09", null, "Wrapped"), shootPage("s2", "Zeta — Shoot 2 · Malibu", P1, "2026-11-02", "2026-11-04")];
const fact = (value, v = 1, at = "2026-10-01T00:00:00.000Z") => ({ value, v, at, by: "check" });
const records = {
  [P2.replace(/-/g, "")]: { page: P2.replace(/-/g, ""), facts: {
    logline: fact("A line"), status: fact("Active"), color: fact("purple"), website: fact("not a url"),
    drive_folder: fact("https://drive.google.com/drive/folders/x"), shoot_dates: fact("2026-12-01/2026-12-03"),
    story: fact("off"), producer: fact("Pat"), credits: fact([{ role: "Director", people: ["Ann"] }]) },
    film: { title: "alpha", relay: "f".repeat(32), shots: 3, scenes: 2 },
    portal: { address: "https://n.studio/f/x", down: false, share: { on: true, count: 1, address: "https://share.n.studio/a", people: 2 },
      visible: [{ slug: "a", on: true }, { slug: "b", on: false }], updated: "2026-10-02T00:00:00Z" } },
  ["9".repeat(32)]: { page: "9".repeat(32), notion_page: P3.replace(/-/g, ""), facts: { type: fact("Commercial"), color: fact("not-a-colour") } },
  ["8".repeat(32)]: { page: "8".repeat(32), kind: "job", facts: { title: fact("Instant Stills"), type: fact("Commercial") } },
};
const now = "2026-10-14";
const L = OL.buildList({ pages, crew, shoots, records, saved: {}, now });
const by = Object.fromEntries(L.projects.map((r) => [r.name, r]));
check("sorted as the Mac sorts: stage, then name without regard to case", eq(L.projects.map((r) => r.name), ["Beta", "Zeta", "alpha", "Archive Me"]), L.projects.map((r) => r.name));
check("Directors named from Crew, joined with &", by.Zeta.director === "Ann & Bo");
check("Notion's icon: a known glyph and its colour", by.Zeta.icon === "flame" && by.Zeta.icon_color === "#e03e3e" && by.Zeta.icon_name === "fire" && eq(by.Zeta.icon_key, { name: "fire", color: "red" }));
check("an unknown glyph falls back to the Type's, the colour still Notion's (the Color choice first)", by.alpha.icon === "clapper" && by.alpha.icon_color === OL.NOTION_COLOR_HEX.blue);
check("no icon: the Type's glyph and colour; Archived with no Type is the box", by.Beta.icon === "star" && by["Archive Me"].icon === "box" && by["Archive Me"].icon_color === "#1b1b1a");
check("shoots read out: Shoot 1 Wrapped, Shoot 2 named and Next", eq(by.Zeta.shoots.map((s) => [s.kind, s.label, s.state]), [["Shoot 1", "Shoot 1", "Wrapped"], ["Shoot 2", "Malibu", "Next"]]), JSON.stringify(by.Zeta.shoots.map((s) => [s.kind, s.label, s.state])));
check("the record's facts laid over Notion's", by.alpha.logline === "A line" && by.alpha.status === "Active" && by.alpha.producer === "Pat" && by.alpha.color === "purple");
check("…a website that is not an address is left as Notion's; a Drive link that is, laid on", by.alpha.website_url === "" && by.alpha.drive_url === "https://drive.google.com/drive/folders/x");
check("…the record's dates", by.alpha.dates === "2026-12-01" && by.alpha.dates_end === "2026-12-03");
check("…the shoots said again for the record's dates (Principal from the project's days)", by.alpha.shoots.length === 1 && by.alpha.shoots[0].kind === "Principal" && by.alpha.shoots[0].start === "2026-12-01");
check("…story, credits and what it hides", by.alpha.story === "off" && eq(by.alpha.credits, [{ role: "Director", people: ["Ann"] }]) && by.alpha.hidden.includes("logline"), JSON.stringify([by.alpha.story, by.alpha.credits, by.alpha.hidden]));
check("a minted record laid over its Notion row by its notion_page, its ID said", by.Beta.type === "Commercial" && by.Beta.id === "9".repeat(32) && by.Beta.color === "");
check("…a colour that is not one of Notion's is never laid on", by.Beta.color === "");
check("a row with no record gets the record's defaults: no credits, its Type's hidden fields", eq(by.Zeta.credits, []) && Array.isArray(by.Zeta.hidden) && by.Zeta.hidden.length > 0 && by.Zeta.id === P1.replace(/-/g, ""), JSON.stringify([by.Zeta.credits, by.Zeta.hidden]));
check("Jobs apart: a job record is listed under jobs, never projects", L.jobs.length === 1 && L.jobs[0].name === "Instant Stills" && L.jobs[0].kind === "job" && !L.projects.some((r) => r.name === "Instant Stills"));
check("every project row says kind project", L.projects.every((r) => r.kind === "project"));
const shelf = OL.filmsShelf(L, records);
const sh = Object.fromEntries(shelf.films.map((f) => [f.name, f]));
check("films shelf: the record's portal read as the Mac reads its kept card", sh.alpha.film === true && sh.alpha.portal && sh.alpha.anyone && sh.alpha.link && sh.alpha.people === 2 && sh.alpha.shown === 1 && sh.alpha.offered === 2 && sh.alpha.counts.shots === 3, JSON.stringify(sh.alpha));
check("…no record: not a portal, not known", sh.Zeta.portal === false && sh.Zeta.known === false);
check("…a record with no portal: known, no portal", sh.Beta.portal === false && sh.Beta.known === true);
check("dates_refusal and url_refusal as the Mac's", OL.datesRefusal("2026-02-30") !== "" && OL.datesRefusal("2026-01-02/2026-01-01") !== "" && OL.datesRefusal("") === "" && OL.urlRefusal("https://a.b") === "" && OL.urlRefusal("ftp://x") !== "");
{
  // end to end through the asks door, with the stand-in Notion
  const env = envOf();
  NOTION.pages[OL.SOURCES.projects] = pages;
  NOTION.pages[OL.SOURCES.crew] = crew;
  NOTION.pages[OL.SOURCES.shoots] = shoots;
  for (const [k, r] of Object.entries(records)) await env.BUCKET.put(`r/${k}/record.json`, JSON.stringify(r));
  const got = await door(env, "POST", "/console/studio/now", { method: "project_list" });
  check("project_list answered on the spot from Notion and the records", got.json.state === "done" && got.json.result.projects.length === 4 && got.json.result.jobs.length === 1, JSON.stringify(got.json).slice(0, 300));
  const fs = await door(env, "POST", "/console/studio/now", { method: "films_shelf" });
  check("films_shelf answered on the spot", fs.json.state === "done" && fs.json.result.films.length === 4);
  const listed = await door(env, "GET", "/console/studio");
  check("both listed as the server's to answer", listed.json.cloud.includes("project_list") && listed.json.cloud.includes("films_shelf"));
  check("nothing kept in the mailbox by reads", (await asks(env)).length === 0);
}

notion.close();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
