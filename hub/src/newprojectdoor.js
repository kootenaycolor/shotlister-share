/**
 * **The ways in to New Project on the server** (newproject.js, 2026-10-13,
 * stage 4 part B): the phone's two asks, the switch, a look that writes
 * nothing, and the list of what the Mac still owes.
 *
 * - `new_project_options()` — the sheet's lists, from Crew, his record
 *   standards and the Mac's last drive list. Answered here only while the
 *   switch is on; otherwise the Mac's, as before.
 * - `create_project(form)` — a full project (Tier 1), and a quick job with a
 *   media drive, made here while the switch is on (with the Drive folders'
 *   own switch on and the server able to make folders). A quick job with no
 *   media drive stays where it was (drivefoldersdoor.js); with the switch
 *   off everything else stays the Mac's, exactly as today.
 *
 *   GET  /console/studio/newproject            { on, at, by, ready, why }
 *   PUT  /console/studio/newproject            { on, by } — off until thrown
 *   POST /console/studio/newproject/look       { form } — every Notion request, Drive folder,
 *                                              owed item and record change it would make;
 *                                              writes nothing, switch or no switch
 *   GET  /console/studio/newproject/owed       { items } — what the Mac still owes (open ones;
 *                                              `?all=1` the finished ones too, kept 30 days)
 *   PUT  /console/studio/newproject/owed/<id>  { part: media|sidebar, state: done|failed|open,
 *                                              said, by } — the Mac, as it does each part
 *
 * **The owed list** (`s/newproject-owed.json`, `{items}`), one item per
 * project that needs the Mac:
 *
 *   { id, asked, by: "server", state: "open" | "done", done_at?,
 *     name, page, slug, section, home, drive_folder, tier1,
 *     parts: { media?: { volume, state, said?, at?, by? },
 *              sidebar?: { state, said?, at?, by? } } }
 *
 * `slug` is the folder name on both drives; `section` is `projects` or
 * `gigs`. Written compare-and-set, like the mailbox, so the Mac marking a
 * part while a new project is added loses neither.
 */

import { notionIn, notionOut } from "./stageword.js";   // Notion says "Complete"; the record "Released"
import { Handoff, cloudReady, apiOf, allCrew } from "./cloud.js";
import * as rules from "./newproject.js";
import * as folders from "./drivefolders.js";
import { driveApi, DriveRefused } from "./drivewrite.js";
import { truthy } from "./notionlink.js";
import { refuseOff } from "./fixedon.js";

const NOTION_VERSION = "2025-09-03";
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const PAGE = /^[0-9a-f]{32}$/;
const ID = /^[0-9a-f]{12}$/;

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ──────────────────────────────────────────────────────────────

export async function settingsOf(env) {
  return rules.switchOf(await readJson(env, rules.SWITCH_KEY));
}

/** Whether the server makes projects now, and why not. */
export async function readiness(env) {
  const settings = await settingsOf(env);
  if (!settings.on) return { ok: false, why: "the switch is off", settings };
  if (!cloudReady(env)) return { ok: false, why: "the server has no Notion key", settings };
  const drive = await folders.settingsOf(env);
  const ready = folders.readiness(env, drive);
  if (!ready.ok) return { ok: false, why: `Drive folders: ${ready.why}`, settings };
  return { ok: true, settings, drive };
}

/** The asks answered here right now, for the phone's list. */
export async function listed(env) {
  return (await readiness(env)).ok ? ["new_project_options", "create_project"] : [];
}

export async function show(env) {
  const r = await readiness(env);
  return { ...r.settings, ready: r.ok, ...(r.ok ? {} : { why: r.why }) };
}

export async function setSwitch(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(rules.SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return await show(env);
}

// ── Notion, with its status ─────────────────────────────────────────────────

/** One Notion call that throws `NotionSaid` (status and code) when refused. */
export function notionClient(env) {
  const key = String(env.NOTION_TOKEN || "").trim();
  const base = apiOf(env);
  return async (method, path, body) => {
    const got = await fetch(base + path, {
      method,
      headers: { authorization: `Bearer ${key}`, "notion-version": NOTION_VERSION, "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(notionOut(body)),
    });
    let answer = null;
    try { answer = notionIn(await got.json()); } catch { answer = null; }
    if (!got.ok || !answer || answer.object === "error") {
      throw new rules.NotionSaid(got.status, (answer && answer.code) || "", (answer && answer.message) || "");
    }
    return answer;
  };
}

// ── the owed list ───────────────────────────────────────────────────────────

async function owedOf(env) {
  const got = await env.BUCKET.get(rules.OWED_KEY);
  if (!got) return { items: [], etag: null };
  try {
    const v = await got.json();
    return { items: isObject(v) && Array.isArray(v.items) ? v.items.filter(isObject) : [], etag: got.etag };
  } catch {
    return { items: [], etag: got.etag };
  }
}

/** Read, change, write back only if nobody wrote in between. */
async function changeOwed(env, change) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const { items, etag } = await owedOf(env);
    const out = change(items);
    if (out.problem) return out;
    const saved = await env.BUCKET.put(rules.OWED_KEY, JSON.stringify({ items: rules.pruneOwed(out.items) }), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: etag ? { etagMatches: etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return out;
  }
  throw new Error("the owed list kept changing while this was being written");
}

/** Stage 5 step 7: with the Mac jobs list's switch on, the owed list is the
 * jobs list (macjobs.js) — one job per part, grouped under the item's id. */
async function jobsOn(env) {
  const mj = await import("./macjobs.js");
  return (await mj.macJobsOn(env)).on ? mj : null;
}

export async function owe(env, fields) {
  const item = rules.owedItem(fields);
  const mj = await jobsOn(env);
  if (mj) { await mj.migrateOwed(env); return await mj.oweAsJobs(env, item); }
  await changeOwed(env, (items) => ({ items: [...items, item] }));
  return item;
}

async function owedSet(env, id, patch) {
  const mj = await jobsOn(env);
  if (mj) return await mj.owedPatch(env, id, patch);
  let after = null;
  await changeOwed(env, (items) => ({
    items: items.map((x) => (x.id === id ? (after = { ...x, ...patch }) : x)),
  }));
  return after;
}

export async function owedList(env, all = false) {
  const mj = await jobsOn(env);
  if (mj) { await mj.migrateOwed(env); return { items: await mj.owedItems(env, all) }; }
  const { items } = await owedOf(env);
  const kept = rules.pruneOwed(items);
  return { items: all ? kept : kept.filter((x) => x.state === "open") };
}

export async function markOwed(env, id, said) {
  if (!ID.test(String(id))) return { status: 404, body: { problem: "No such item." } };
  const mj = await jobsOn(env);
  if (mj) { await mj.migrateOwed(env); return await mj.markOwedJob(env, id, said); }
  let item = null;
  const out = await changeOwed(env, (items) => {
    const at = items.findIndex((x) => x.id === id);
    if (at < 0) return { problem: "No such item." };
    const got = rules.marked(items[at], said);
    if (got.problem) return { problem: got.problem };
    item = got.item;
    const next = items.slice();
    next[at] = item;
    return { items: next };
  });
  if (out.problem) return { status: out.problem === "No such item." ? 404 : 400, body: { problem: out.problem } };
  return { status: 200, body: item };
}

// ── the record, begun ───────────────────────────────────────────────────────

/** A record for a page that has none — New Film's skeleton (newfilm.js).
 * With one ID (projectid.js) the record is begun under a freshly minted ID
 * (or `id`, one a device minted itself and sent with the form) and the
 * Notion page is kept on it as `notion_page`. */
export async function beginRecord(env, page, name, id = "") {
  if (!PAGE.test(page)) return false;
  const { oneIdOn } = await import("./projectid.js");
  if ((await oneIdOn(env)).on) {
    const { beginMinted } = await import("./oneiddoor.js");
    return (await beginMinted(env, { notion: page, id, name, by: "server" })).made;
  }
  for (let attempt = 0; attempt < 3; attempt++) {
    const got = await env.BUCKET.get(`r/${page}/record.json`);
    if (got) return false;
    const record = { version: 1, page, name, facts: {}, lights: {}, by: "server", updated: new Date().toISOString() };
    const saved = await env.BUCKET.put(`r/${page}/record.json`, JSON.stringify(record), {
      httpMetadata: { contentType: "application/json" }, onlyIf: { etagDoesNotMatch: "*" },
    });
    if (saved) return true;
  }
  return false;
}

/** record.set_when_ready(page, "story", value): never over one already set. */
async function storyFact(env, page, value) {
  const record = await readJson(env, `r/${page}/record.json`);
  const have = record && isObject(record.facts) && isObject(record.facts.story) ? record.facts.story : {};
  if (have.v) return;
  const { writeFacts } = await import("./facts.js");
  await writeFacts(env, page, { story: { value, base: 0 } }, "server");
}

// ── the Drive ───────────────────────────────────────────────────────────────

function driveIo(api, settings, { write }) {
  return {
    async plan(form) {
      try {
        return await folders.planProject(api, settings, form);
      } catch (e) {
        if (e instanceof DriveRefused) throw new Handoff(e.message);
        throw e;
      }
    },
    async make(plan) {
      if (!write) return { url: "(the new folder's link)", id: "(the new folder)", made: plan.steps.map((s) => s.key) };
      let got;
      try {
        got = await folders.carryOut(api, plan);
      } catch (e) {
        if (e instanceof DriveRefused) throw new Handoff(e.message);
        throw e;
      }
      if (got.failed.length) {
        if (got.error instanceof DriveRefused && !got.made.length) throw new Handoff(got.error.message);
        const e = new Error(`The Drive folder was not finished — ${got.failed.map((f) => `${f.key}: ${f.why}`).join("; ")}`);
        e.made = got.made;
        throw e;
      }
      return { url: folders.folderUrl(got.ids[plan.folder]), id: got.ids[plan.folder], made: got.made };
    },
  };
}

// ── the asks ────────────────────────────────────────────────────────────────

/** backend.new_project_options */
export async function newProjectOptions(env, n) {
  const r = await readiness(env);
  if (!r.ok) throw new Handoff(r.why);
  let crew = [];
  try {
    crew = await allCrew(n);
  } catch (e) {
    // The Mac's: "new project: Crew not read", and the lists left empty.
    console.log(`new project: Crew not read — ${(e && e.message) || e}`);
  }
  const { savedTemplates } = await import("./cloudlayout.js");
  await (await import("./studiomodes.js")).loadStandards(env);
  return rules.optionsFrom({ crew, templates: await savedTemplates(env), studio: await readJson(env, "s/studio.json") });
}

/** backend.create_project — a full project, or a quick job with a media drive. */
export async function createProject(env, n, args) {
  let form = isObject(args && args[0]) ? args[0] : {};
  // Step 5's Kind, modes and systems (step5birth.js), only once its switch is on.
  const birth = await import("./step5birth.js");
  let b = null;
  if ((await birth.birthOn(env)).on) {
    b = birth.readBirth(form);
    if (b.why) throw new Error(b.why);
    form = b.form;
  }
  const born = async (said, made) => {
    if (!b) return said;
    const got = await birth.bear(env, b, made);
    return got.line ? `${said}\n${got.line}` : said;
  };
  const tier1 = "tier1" in form ? truthy(form.tier1) : true;
  const volume = String(form.volume || "").trim();
  const r = await readiness(env);
  // Step 6 (health): a Job's Job Log row, as the Mac's backend._job_after.
  const jobLog = await (await import("./step6health.js")).jobLogOn(env);
  if (!r.ok || (!tier1 && !volume)) {
    const { quickJobMade } = await import("./drivefoldersdoor.js");
    const got = await quickJobMade(env, n, [form]);
    let said = got.said;
    const rf = rules.readForm(form);
    if (jobLog && rf.job) said = `${said}\n${await rules.jobLogLine(notionClient(env), rf, got.url)}`;
    return await born(said, { page: "", url: got.url });
  }
  const api = driveApi(env, { write: true });
  if (!api || !api.mkdir) throw new Handoff("the server has no Google sign-in that can make folders");
  const io = {
    notion: notionClient(env),
    drive: driveIo(api, r.drive, { write: true }),
    volumes: rules.knownVolumes(await readJson(env, "s/studio.json")),
    owe: (fields) => owe(env, fields),
    owed: (id, patch) => owedSet(env, id, patch),
    record: { begin: (page, name) => beginRecord(env, page, name, String(form.id || "")), story: (page, value) => storyFact(env, page, value) },
    log: (words) => console.log(words),
    jobLog,
  };
  const got = await rules.makeProject(form, io);
  return await born(got.said, { page: got.page || "", url: got.url || "" });
}

// ── the look ────────────────────────────────────────────────────────────────

/** Written properties as Notion reads them back (a crew row's check). */
function asRead(props) {
  const out = {};
  for (const [k, v] of Object.entries(props || {})) {
    const kind = Object.keys(v)[0];
    if (kind === "title" || kind === "rich_text") out[k] = { type: kind, [kind]: v[kind].map((t) => ({ ...t, plain_text: t.text.content })) };
    else out[k] = { type: kind, ...v };
  }
  return out;
}

/**
 * What a create would do, now, and nothing written: Notion is read for real
 * (Crew, the Projects database) and every write is set down instead of sent;
 * the Drive is read and its plan shown; the owed item and the record are set
 * down. `form` is the phone's form.
 */
export async function look(env, said) {
  let form = isObject(said && said.form) ? said.form : {};
  const r = await readiness(env);
  // Step 5's birth (step5birth.js): what the record would be given, shown
  // whether or not its switch is on; the form read its way only when it is.
  const birth = await import("./step5birth.js");
  const b = birth.readBirth(form);
  const birthOn = (await birth.birthOn(env)).on;
  if (birthOn && !b.why) form = b.form;
  const base = { on: r.settings.on, ready: r.ok, ...(r.ok ? {} : { why_not: r.why }),
    birth: { on: birthOn, ...(b.why ? { why: b.why } : { kind: b.job ? "job" : "project", setup: b.setup, record: birth.birthPlan(b, { page: b.setup.notion ? "(the new row)" : "", url: "(the new folder's link)" }) }) } };
  if (!cloudReady(env)) return { ok: false, why: "the server has no Notion key", ...base };
  const api = driveApi(env, { write: false });
  if (!api) return { ok: false, why: "the server has no Google sign-in to read the Drive with", ...base };
  const drive = await folders.settingsOf(env);
  if (!drive.scratch && Object.keys(drive.roots).length < 3) return { ok: false, why: "the Drive's root folders are not set", ...base };
  const real = notionClient(env);
  const notion = [];
  const made = new Map();
  let k = 0;
  const owed = [];
  const record = [];
  let plan = null;
  const io = {
    async notion(method, path, body) {
      const page = /^pages\/(.+)$/.exec(path);
      if (method === "GET" && page && made.has(page[1])) {
        notion.push({ method, path, read: true });
        return { object: "page", id: page[1], properties: asRead(made.get(page[1]).properties) };
      }
      if (method === "GET" || path.endsWith("/query")) {
        notion.push({ method, path, ...(body ? { body } : {}), read: true });
        return await real(method, path, body);
      }
      notion.push({ method, path, body });
      if (method === "POST" && path === "pages") {
        const id = `newpage${String(++k).padStart(4, "0")}`;
        made.set(id, body);
        return { object: "page", id, url: "" };
      }
      return { object: "ok" };
    },
    drive: {
      plan: async (f) => (plan = await driveIo(api, drive, { write: false }).plan(f)),
      make: (p) => driveIo(api, drive, { write: false }).make(p),
    },
    volumes: rules.knownVolumes(await readJson(env, "s/studio.json")),
    owe: async (fields) => { const item = rules.owedItem(fields); owed.push(item); return item; },
    owed: async (id, patch) => { const at = owed.findIndex((x) => x.id === id); if (at >= 0) owed[at] = { ...owed[at], ...patch }; return owed[at]; },
    record: {
      begin: async (page, name) => { record.push({ begin: page, name, already: Boolean(PAGE.test(page) && await env.BUCKET.head(`r/${page}/record.json`)) }); },
      story: async (page, value) => { record.push({ fact: "story", page, value }); },
    },
    log: () => {},
    jobLog: await (await import("./step6health.js")).jobLogOn(env),
  };
  try {
    const got = await rules.makeProject(form, io);
    return {
      ok: true, ...base, said: got.said,
      drive: plan ? folders.shown(plan) : null,
      notion, owed: owed[0] || null, record,
    };
  } catch (e) {
    return {
      ok: false, ...base, why: String((e && e.message) || e).slice(0, 500),
      ...(e instanceof Handoff ? { mac: true } : {}),
      drive: plan ? folders.shown(plan) : null, notion,
    };
  }
}
