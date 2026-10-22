#!/usr/bin/env node
/**
 * **One ID per project, on its own** (2026-10-14, stage 5 step 2). The rules
 * of `projectid.js`, `studioside.js` and `oneiddoor.js` over a bucket in
 * memory; the engine's real `new_film` door (hub/src/mcp.wasm) makes the
 * Studio side. The worker's routes are `oneid-live.mjs`.
 *
 *     node hub/oneid.mjs        (after hub/build.sh, for the engine)
 */
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);

const ids = await import("./src/projectid.js");
const side = await import("./src/studioside.js");
const door = await import("./src/oneiddoor.js");
const { recordPageOf } = await import("./src/facts.js");

const HERE = dirname(fileURLToPath(import.meta.url));
let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(84)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};

// ---- a bucket in memory ----------------------------------------------------
function bucket(seed = {}) {
  const objects = new Map(Object.entries(seed).map(([k, v]) => [k, typeof v === "string" ? v : JSON.stringify(v)]));
  let n = 0;
  const etags = new Map([...objects.keys()].map((k) => [k, `s${++n}`]));
  const calls = [];
  const obj = (key) => ({ key, etag: etags.get(key), json: async () => JSON.parse(objects.get(key)), text: async () => objects.get(key) });
  return {
    objects, calls,
    async get(key) { calls.push(["get", key]); return objects.has(key) ? obj(key) : null; },
    async head(key) { calls.push(["head", key]); return objects.has(key) ? { etag: etags.get(key) } : null; },
    async put(key, value, opts = {}) {
      calls.push(["put", key]);
      const only = opts.onlyIf || {};
      if (only.etagDoesNotMatch === "*" && objects.has(key)) return null;
      if (only.etagMatches && etags.get(key) !== only.etagMatches) return null;
      objects.set(key, String(value)); etags.set(key, `e${++n}`); return { etag: etags.get(key) };
    },
    async delete(key) { calls.push(["delete", key]); objects.delete(key); },
    async list({ prefix = "", delimiter } = {}) {
      calls.push(["list", prefix]);
      const keys = [...objects.keys()].filter((k) => k.startsWith(prefix)).sort();
      if (!delimiter) return { objects: keys.map((key) => ({ key })), truncated: false };
      const pre = new Set(keys.map((k) => k.slice(prefix.length)).filter((r) => r.includes(delimiter)).map((r) => prefix + r.split(delimiter)[0] + delimiter));
      return { objects: [], delimitedPrefixes: [...pre], truncated: false };
    },
  };
}
const read = (b, key) => (b.objects.has(key) ? JSON.parse(b.objects.get(key)) : null);
const ON = { "s/oneid.json": { on: true } };

// ---- the engine, as newfilmdoor.js drives it -------------------------------
const WASM = join(HERE, "src/mcp.wasm");
const mod = existsSync(WASM) ? await WebAssembly.compile(readFileSync(WASM)) : null;
const put = (x, text) => { const b = new TextEncoder().encode(text); const p = x.alloc(b.length); new Uint8Array(x.memory.buffer, p, b.length).set(b); return [p, b.length]; };
const take = (x, ptr) => { const len = new DataView(x.memory.buffer).getUint32(ptr, true); const t = new TextDecoder().decode(new Uint8Array(x.memory.buffer, ptr + 4, len)); x.free_result(ptr); return t; };
async function engineMakes(link) {
  const x = (await WebAssembly.instantiate(mod, {})).exports;
  x.set_now(Date.now()); x.set_seed(4242);
  const args = ["0".repeat(32), link.title, "a1b2c3d4e5f60718"].map((s) => put(x, s));
  if (x.start(args[0][0], args[0][1], args[1][0], args[1][1], 0, args[2][0], args[2][1]) !== 0) throw new Error("no start");
  x.settle();
  const [p, l] = put(x, JSON.stringify(link));
  const said = JSON.parse(take(x, x.new_film(p, l)));
  const log = take(x, x.pending_log());
  if (said.error) throw new Error(said.error);
  return { said, log };
}
function fieldsOf(log) {
  const out = {};
  let project = null;
  for (const line of log.split("\n")) {
    const parts = line.split("\t");
    if (parts[3] === "C" && parts[5] === "project") project = parts[4];
    if (parts.length >= 7 && parts[3] === "S" && parts[4] === project) out[parts[5]] = parts[6];
  }
  return out;
}

const PAGE_OLD = "27fd41c6923285effb414614bf2884e0";     // an existing project: its page is its ID
const RELAY_OLD = "f351d7ab0000000000000000000000aa";    // …and its film's relay id, an alias
const PAGE_PORTAL = "a01122c777bb8836cd75842f7d8d684f";  // a portal-only project (Jonas on Edge's shape)
const NOTION_NEW = "47ec4bb140d181cbbc22e5a8314a2f9d";   // a new project's Notion page

// ---- minting ---------------------------------------------------------------
{
  const a = ids.mintId(), b = ids.mintId();
  check("a minted ID is 32 hex, the shape relay ids and page ids share", ids.ID.test(a) && /^[0-9a-f]{8,64}$/.test(a), a);
  check("…and two are never the same", a !== b);
  const env = { BUCKET: bucket({ [`r/${PAGE_OLD}/record.json`]: { page: PAGE_OLD }, [`p/${RELAY_OLD}/manifest.json`]: { title: "x" } }) };
  const want = "0123456789abcdef0123456789abcdef";
  check("a device's own ID, free, is kept", (await ids.freeId(env, want)) === want);
  const taken1 = await ids.freeId(env, PAGE_OLD);
  check("an ID a record holds is never handed out again", taken1 !== PAGE_OLD && ids.ID.test(taken1), taken1);
  const taken2 = await ids.freeId(env, RELAY_OLD);
  check("…nor one a film holds", taken2 !== RELAY_OLD, taken2);
  const junk = await ids.freeId(env, "not-an-id");
  check("a malformed ID is replaced by a minted one", ids.ID.test(junk), junk);
}

// ---- the map ---------------------------------------------------------------
{
  const env = { BUCKET: bucket() };
  let got = await ids.addIds(env, { notion: { [NOTION_NEW]: "a".repeat(32) }, alias: { [RELAY_OLD]: PAGE_OLD } });
  check("entries are added", got.added.notion[NOTION_NEW] === "a".repeat(32) && got.added.alias[RELAY_OLD] === PAGE_OLD, JSON.stringify(got));
  got = await ids.addIds(env, { notion: { [NOTION_NEW]: "b".repeat(32) } });
  check("an entry is never changed: a second answer is a clash, not a write", got.clashes.length === 1 && read(env.BUCKET, ids.IDS_KEY).notion[NOTION_NEW] === "a".repeat(32), JSON.stringify(got));
  got = await ids.addIds(env, { alias: { [PAGE_OLD]: PAGE_OLD, zz: "a".repeat(32) } });
  check("an ID mapped to itself, or a malformed one, is not kept", !Object.keys(got.added.alias).length);
  const m = ids.idsShape({ notion: { x: "y", [NOTION_NEW]: "c".repeat(32) }, alias: null });
  check("a damaged map reads as what is sound in it", Object.keys(m.notion).length === 1 && Object.keys(m.alias).length === 0, JSON.stringify(m));
  check("notionOf: a minted record's Notion page", ids.notionOf({ page: "a".repeat(32), notion_page: NOTION_NEW, notion: "https://www.notion.so/x" }) === NOTION_NEW);
  check("notionOf: an existing record's own key (its readout's `notion` is a URL)", ids.notionOf({ page: PAGE_OLD, notion: `https://www.notion.so/Lets-Bake-${PAGE_OLD}` }) === PAGE_OLD);
}

// ---- resolving any ID ------------------------------------------------------
const MINTED = "9".repeat(32);
function world(extra = {}) {
  return bucket({
    [`r/${PAGE_OLD}/record.json`]: { page: PAGE_OLD, name: "Halcyon", film: { title: "Halcyon", relay: RELAY_OLD }, facts: {} },
    [`p/${RELAY_OLD}/manifest.json`]: { title: "Halcyon" },
    [`r/${PAGE_PORTAL}/record.json`]: { page: PAGE_PORTAL, name: "Jonas on Edge", film: null, facts: {} },
    [`p/${PAGE_PORTAL}/portal.json`]: { title: "Jonas on Edge", page: PAGE_PORTAL },
    [`p/${PAGE_PORTAL}/people.json`]: { people: [{ email: "crew@example.com", role: "viewer" }], links: [{ hash: "h1", role: "viewer" }], invites: [] },
    [`p/${PAGE_PORTAL}/front.json`]: { title: "Jonas on Edge", sections: [{ slug: "notes" }] },
    [`p/${PAGE_PORTAL}/pages/notes.json`]: { words: "his page" },
    [`r/${MINTED}/record.json`]: { page: MINTED, notion_page: NOTION_NEW, name: "Northern Lights", facts: {} },
    [ids.IDS_KEY]: { notion: { [NOTION_NEW]: MINTED }, alias: { [RELAY_OLD]: PAGE_OLD } },
    ...extra,
  });
}
{
  const env = { BUCKET: world() };
  let r = await ids.resolveProject(env, PAGE_OLD);
  check("an existing project by its own ID (its Notion page)", r.key === PAGE_OLD && r.via === "key");
  r = await ids.resolveProject(env, RELAY_OLD);
  check("…by its film's relay id, an alias for good", r.key === PAGE_OLD && r.via === "alias");
  r = await ids.resolveProject(env, MINTED);
  check("a new project by its minted ID", r.key === MINTED && r.via === "key");
  r = await ids.resolveProject(env, NOTION_NEW);
  check("…and by its Notion page", r.key === MINTED && r.via === "notion");
  r = await ids.resolveProject(env, "27fd41c6-9232-85ef-fb41-4614bf2884e0");
  check("a dashed page id is the same page", r.key === PAGE_OLD);
  r = await ids.resolveProject(env, "e".repeat(32));
  check("an ID that names nothing names nothing", r.key === "" && r.record === null);
  check("keyOfPage: a minted project's page → its ID; any other page → itself", (await ids.keyOfPage(env, NOTION_NEW)) === MINTED && (await ids.keyOfPage(env, PAGE_OLD)) === PAGE_OLD);
}

// ---- the bucket's door -----------------------------------------------------
{
  const raw = world();
  const env = ids.byProjectId({ BUCKET: raw });
  let got = await env.BUCKET.get(`r/${NOTION_NEW}/record.json`);
  check("a minted project's record, read by its Notion page", got && (await got.json()).page === MINTED);
  check("…from where it lives (r/<id>/)", raw.calls.some(([op, k]) => op === "get" && k === `r/${MINTED}/record.json`), JSON.stringify(raw.calls.slice(-3)));
  got = await env.BUCKET.get(`r/${PAGE_OLD}/record.json`);
  check("an existing project's record is read where it always was", got && (await got.json()).page === PAGE_OLD);
  await env.BUCKET.put(`r/${NOTION_NEW}/folders.json`, JSON.stringify({ path: "/x" }));
  check("a write by the Notion page lands beside the minted record", raw.objects.has(`r/${MINTED}/folders.json`) && !raw.objects.has(`r/${NOTION_NEW}/folders.json`));
  check("head goes the same way", Boolean(await env.BUCKET.head(`r/${NOTION_NEW}/folders.json`)));
  const listed = await env.BUCKET.list({ prefix: `r/${NOTION_NEW}/` });
  check("a list under the Notion page lists the minted record's files", listed.objects.map((o) => o.key).includes(`r/${MINTED}/record.json`), JSON.stringify(listed));
  const all = await env.BUCKET.list({ prefix: "r/", delimiter: "/" });
  check("the list of every record is not translated: minted IDs appear as they are", all.delimitedPrefixes.includes(`r/${MINTED}/`) && !all.delimitedPrefixes.includes(`r/${NOTION_NEW}/`));
  got = await env.BUCKET.get(`p/${NOTION_NEW}/people.json`);
  check("films and portals (p/…) are never translated", got === null && raw.calls.some(([op, k]) => op === "get" && k === `p/${NOTION_NEW}/people.json`));
  // The map changes in the middle of a request: a record begun under a
  // minted ID is read back by its Notion page at once.
  const fresh = bucket({ "s/oneid.json": { on: true } });
  const env2 = ids.byProjectId({ BUCKET: fresh });
  await env2.BUCKET.get(`r/${NOTION_NEW}/record.json`);          // the map read: empty
  const made = await door.beginMinted(env2, { notion: NOTION_NEW, name: "Northern Lights" });
  got = await env2.BUCKET.get(`r/${NOTION_NEW}/record.json`);
  check("…and the map is read again after it is written through the same bucket", got && (await got.json()).page === made.key, made.key);
  check("an empty map changes nothing", (await ids.byProjectId({ BUCKET: bucket({ [`r/${PAGE_OLD}/record.json`]: { page: PAGE_OLD } }) }).BUCKET.get(`r/${PAGE_OLD}/record.json`)) !== null);
  check("wrapping twice is wrapping once", ids.byProjectId(env).BUCKET === env.BUCKET);
}

// ---- a project born: the record under a minted ID --------------------------
{
  const b = bucket(ON);
  const env = { BUCKET: b };
  const got = await door.beginMinted(env, { notion: NOTION_NEW, name: "Northern Lights", by: "server" });
  const rec = read(b, `r/${got.key}/record.json`);
  check("New Project begins the record under a minted ID", got.made && ids.ID.test(got.key) && got.key !== NOTION_NEW, JSON.stringify(got));
  check("…the record's page is the ID, its Notion page a field", rec.page === got.key && rec.notion_page === NOTION_NEW && rec.name === "Northern Lights" && rec.minted, JSON.stringify(rec));
  check("…and the map says so", read(b, ids.IDS_KEY).notion[NOTION_NEW] === got.key);
  const again = await door.beginMinted(env, { notion: NOTION_NEW, name: "Northern Lights" });
  check("asked twice, one record", !again.made && again.key === got.key && [...b.objects.keys()].filter((k) => k.endsWith("record.json")).length === 1);
  const old = await door.beginMinted({ BUCKET: world() }, { notion: PAGE_OLD, name: "Halcyon" });
  check("an existing project keeps its page id: nothing minted", !old.made && old.key === PAGE_OLD, JSON.stringify(old));
  const device = "0a1b2c3d4e5f60718293a4b5c6d7e8f9";
  const mine = await door.beginMinted({ BUCKET: bucket(ON) }, { notion: "a32d4e0b6e9888eac61fbc526e428b2c", id: device, name: "Studio Made" });
  check("a device's own minted ID is kept (Studio's New Project knows it before the answer)", mine.key === device, JSON.stringify(mine));
  const job = await door.beginMinted({ BUCKET: bucket(ON) }, { name: "A Job" });
  check("a project with no Notion page at all gets a record and no map entry", job.made && ids.ID.test(job.key));
}

// ---- New Project on the server (newprojectdoor.js) -------------------------
{
  const { beginRecord } = await import("./src/newprojectdoor.js");
  const page = "29b405b7b5b98d4b98a63c6360b2bc0f";
  let b = bucket();
  check("switch off: the server's New Project begins the record under the Notion page, as before",
    (await beginRecord({ BUCKET: b }, page, "Old Way")) === true && read(b, `r/${page}/record.json`).page === page && !b.objects.has(ids.IDS_KEY));
  b = bucket(ON);
  const env = ids.byProjectId({ BUCKET: b });
  const device = "0a1b2c3d4e5f60718293a4b5c6d7e8f9";
  check("switch on: under the ID the device sent, its Notion page a field", (await beginRecord(env, page, "Studio Made", device)) === true
    && read(b, `r/${device}/record.json`).notion_page === page && !b.objects.has(`r/${page}/record.json`));
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  check("…and the rest of New Project, writing by the Notion page in the same run, reaches it", got && (await got.json()).page === device);
  b = bucket(ON);
  check("switch on, no ID sent: a minted one", (await beginRecord({ BUCKET: b }, page, "Console Made")) === true
    && ids.ID.test(read(b, ids.IDS_KEY).notion[page]) && read(b, ids.IDS_KEY).notion[page] !== page);
}

// ---- aliases, frozen -------------------------------------------------------
{
  const b = bucket({
    [`r/${PAGE_OLD}/record.json`]: { page: PAGE_OLD, name: "Halcyon", film: { title: "Halcyon", relay: RELAY_OLD } },
    [`r/${PAGE_PORTAL}/record.json`]: { page: PAGE_PORTAL, name: "Jonas on Edge", film: null },
    [`r/${"7".repeat(32)}/record.json`]: { page: "7".repeat(32), name: "In Place", film: { relay: "7".repeat(32) } },
  });
  const env = { BUCKET: b };
  const look = await ids.freezeAliases(env, { dry: true });
  check("the dry look names every film under another id, and writes nothing", look.would_add[RELAY_OLD] === PAGE_OLD && Object.keys(look.would_add).length === 1 && !b.objects.has(ids.IDS_KEY), JSON.stringify(look));
  const run = await ids.freezeAliases(env, { dry: false });
  check("the run keeps them", run.added[RELAY_OLD] === PAGE_OLD && read(b, ids.IDS_KEY).alias[RELAY_OLD] === PAGE_OLD);
  const both = { BUCKET: bucket({
    [`r/${"1".repeat(32)}/record.json`]: { page: "1".repeat(32), name: "Test A", film: { relay: "f".repeat(32) } },
    [`r/${"2".repeat(32)}/record.json`]: { page: "2".repeat(32), name: "Test B", film: { relay: "f".repeat(32) } },
  }) };
  const split = await ids.freezeAliases(both, { dry: true });
  check("two records naming one film: neither kept, both said", !split.would_add["f".repeat(32)] && split.found.filter((f) => f.clash).length === 2, JSON.stringify(split));
  const twice = await ids.freezeAliases(env, { dry: false });
  check("run again, nothing new", Object.keys(twice.added).length === 0 && twice.found.find((f) => f.relay === RELAY_OLD).already === true);
}

// ---- the second way of finding a record goes -------------------------------
{
  const card = { source: `notion:${PAGE_OLD}` };
  const off = { BUCKET: world({ [ids.IDS_KEY]: {} }) };
  check("switch off: the film's card still finds its record (as before)", (await recordPageOf(off, RELAY_OLD, card)) === PAGE_OLD);
  const on = { BUCKET: world(ON) };
  check("switch on: found by its alias, the card not asked", (await recordPageOf(on, RELAY_OLD, {})) === PAGE_OLD);
  const onNoAlias = { BUCKET: world({ ...ON, [ids.IDS_KEY]: {} }) };
  check("…and a card's source alone no longer finds it (freeze the aliases first)", (await recordPageOf(onNoAlias, RELAY_OLD, card)) === "");
  check("…a minted project by its own ID", (await recordPageOf(on, MINTED, {})) === MINTED);
}

// ---- the Studio side, made when first wanted -------------------------------
if (!mod) {
  check("the engine is here (hub/build.sh)", false, WASM);
} else {
  const noNotion = { fetchRow: async () => null, fetchText: async () => "", engineMakes };

  let b = world();
  let got = await side.ensureStudioSide({ BUCKET: b }, MINTED, noNotion);
  check("switch off: nothing made", !got.ok && /switch is off/.test(got.why) && !b.objects.has(`p/${MINTED}/manifest.json`), JSON.stringify(got));
  got = await side.ensureStudioSide({ BUCKET: b }, MINTED, { ...noNotion, dry: true });
  check("…but the dry look answers, and writes nothing", got.ok && got.dry && got.made && got.relay === MINTED && got.would.title === "Northern Lights" && !b.objects.has(`p/${MINTED}/manifest.json`), JSON.stringify(got));

  b = world(ON);
  const env = { BUCKET: b };
  got = await side.ensureStudioSide(env, PAGE_OLD, noNotion);
  check("an existing project's film: answered, nothing made", got.ok && !got.made && got.relay === RELAY_OLD && got.alias, JSON.stringify(got));
  got = await side.ensureStudioSide(env, RELAY_OLD, noNotion);
  check("…asked by the film's own id, the same answer", got.ok && got.key === PAGE_OLD && got.relay === RELAY_OLD);

  const before = new Set(b.objects.keys());
  got = await side.ensureStudioSide(env, MINTED, noNotion);
  const rec = read(b, `r/${MINTED}/record.json`);
  check("a new project: its Studio side made under its own ID", got.ok && got.made && got.relay === MINTED && b.objects.has(`p/${MINTED}/manifest.json`), JSON.stringify(got));
  const logs = [...b.objects.keys()].filter((k) => k.startsWith(`p/${MINTED}/logs/`));
  check("…one change log, named as the relay asks (device-session.log)", logs.length === 1 && /^p\/[0-9a-f]{32}\/logs\/[0-9a-f]{16}-[0-9a-f]{16}\.log$/.test(logs[0]), logs.join(" "));
  const fields = fieldsOf(b.objects.get(logs[0]));
  check("…the film is titled, and linked to the project's Notion page", fields.title === "t:Northern Lights" && fields.console_page === `t:${NOTION_NEW}` && fields.console_name === "t:Northern Lights", JSON.stringify(fields));
  check("…the record names it (relay = the project's ID, made by the server)", rec.film.relay === MINTED && rec.film.made === "hub" && rec.lights.film === "on" && rec.notion_page === NOTION_NEW, JSON.stringify(rec.film));
  const wrote = [...b.objects.keys()].filter((k) => !before.has(k));
  check("…and nothing else of his was written (the claim aside)", wrote.every((k) => k.startsWith(`p/${MINTED}/`) || k === `s/studioside/${MINTED}.json`), wrote.join(" "));
  got = await side.ensureStudioSide(env, MINTED, noNotion);
  check("asked again: the same film, nothing made", got.ok && !got.made && got.relay === MINTED && [...b.objects.keys()].filter((k) => k.startsWith(`p/${MINTED}/logs/`)).length === 1);
  got = await side.ensureStudioSide(env, NOTION_NEW, noNotion);
  check("…asked by its Notion page: the same film", got.ok && got.key === MINTED && got.relay === MINTED);

  // A portal-only project: the film is born on top of its portal.
  const sent = b.objects.get(`p/${PAGE_PORTAL}/people.json`);
  got = await side.ensureStudioSide(env, PAGE_PORTAL, noNotion);
  check("a portal-only project: the film is born where its portal is (its page id)", got.ok && got.made && got.relay === PAGE_PORTAL && b.objects.has(`p/${PAGE_PORTAL}/manifest.json`), JSON.stringify(got));
  check("…every person and sent link stays exactly where it was", b.objects.get(`p/${PAGE_PORTAL}/people.json`) === sent && b.objects.has(`p/${PAGE_PORTAL}/pages/notes.json`) && b.objects.has(`p/${PAGE_PORTAL}/front.json`));
  check("…its 'portal with no film' mark goes, nothing is copied anywhere", !b.objects.has(`p/${PAGE_PORTAL}/portal.json`) && ![...b.objects.keys()].some((k) => k.startsWith("p/") && !k.startsWith(`p/${PAGE_PORTAL}/`) && !k.startsWith(`p/${MINTED}/`) && !k.startsWith(`p/${RELAY_OLD}/`)));

  // Refusals, each with nothing written.
  b = world({ ...ON, [`r/${"6".repeat(32)}/record.json`]: { page: "6".repeat(32), name: "Gone", film: { title: "Gone", relay: "5".repeat(32) } } });
  got = await side.ensureStudioSide({ BUCKET: b }, "6".repeat(32), noNotion);
  check("a film the record names that left the relay: refused, no second film", !got.ok && /not on the relay/.test(got.why) && !b.objects.has(`p/${"6".repeat(32)}/manifest.json`), JSON.stringify(got));
  b = world({ ...ON, [`p/${"4".repeat(32)}/manifest.json`]: { title: "northern lights" } });
  got = await side.ensureStudioSide({ BUCKET: b }, MINTED, noNotion);
  check("a film of the same name already on the relay: refused (Studio's folder names)", !got.ok && /already exists/.test(got.why) && !b.objects.has(`p/${MINTED}/manifest.json`), JSON.stringify(got));
  b = world({ ...ON, [`s/studioside/${MINTED}.json`]: { state: "making", at: new Date().toISOString() } });
  got = await side.ensureStudioSide({ BUCKET: b }, MINTED, noNotion);
  check("a make already under way: refused", !got.ok && /right now/.test(got.why), JSON.stringify(got));
  got = await side.ensureStudioSide({ BUCKET: world(ON) }, "e".repeat(32), noNotion);
  check("an ID that names no project: refused", !got.ok && /No project/.test(got.why));
  b = world({ ...ON, [`p/${MINTED}/manifest.json`]: { title: "Northern Lights" } });
  got = await side.ensureStudioSide({ BUCKET: b }, MINTED, noNotion);
  check("a film a device already made under the ID: named on the record, nothing made", got.ok && !got.made && read(b, `r/${MINTED}/record.json`).film.relay === MINTED, JSON.stringify(got));

  // The Notion row's Drive Folder and icon reach the film.
  b = world(ON);
  const row = { id: NOTION_NEW, properties: { "Drive Folder": { url: "https://drive.google.com/drive/folders/abc" } } };
  got = await side.ensureStudioSide({ BUCKET: b }, MINTED, { ...noNotion, fetchRow: async () => row });
  const f2 = fieldsOf(b.objects.get([...b.objects.keys()].find((k) => k.startsWith(`p/${MINTED}/logs/`))));
  check("the Notion row's Drive Folder reaches the film", got.ok && f2.drive_url === "t:https://drive.google.com/drive/folders/abc", JSON.stringify(f2));

  // The door.
  const d = await side.studioSideDoor({ BUCKET: world(ON) }, "nope", {});
  check("the door refuses what is not an ID", d.status === 404);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
