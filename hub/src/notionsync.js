/**
 * **The Notion link, running on the hub** (2026-10-11, Projects Console
 * without the Mac, stage 2) — `projects-console/notionsync.py`, ported rule
 * for rule. The deciding is in `notionlink.js`; this file reads, writes,
 * remembers and is called once a minute by `timer.js`.
 *
 * Each look (`syncTick`) does what `notionsync.tick` does on the Studio Mac:
 * every Projects row against its record — the text boxes, the choices, the
 * credits, the title (Notion → record only), the dates, the addresses, the
 * icon — then the page's Story section, the credited people, and every five
 * minutes the crew and shoots copies. Words decide, never times; the last
 * point both sides agreed is remembered; both moved → a conflict, shown to
 * him, never merged.
 *
 * **What it remembers**, in the bucket, in exactly the shape of the Mac's
 * files so either can be copied to the other:
 *   s/notion-link.json      the Mac's notion-link.json   (bases, pushed, bot, crew_at)
 *   s/notion-story.json     the Mac's notion-story.json  (the Story section per page)
 *   s/notion-conflicts.json {conflicts: [...]} — the Mac kept these in
 *                           facts-outbox.json's `conflicts` (kind "notion");
 *                           same items, same shape
 *   s/notion-people.json    what Python kept in memory between looks: the
 *                           Crew and Shoots rows (read every five minutes),
 *                           Notion's choices
 *   s/record-templates.json the console's Settings → Record standards
 *                           (`record_templates` in its settings.json) — the
 *                           Mac's own copy never reaches the hub on its own
 *
 * **Dry** (`{dry: true}`): reads the real Notion and the real records and
 * writes nothing anywhere — no Notion, no record, no state, no conflict —
 * and answers `{decided, writes, trouble}` exactly as `notionsync.dry_run()`
 * does, so the two can be diffed line for line.
 */

import { notionOf, Handoff, duplicates, companyProps, NAMES_KEY } from "./cloud.js";
import * as L from "./notionlink.js";
import { planPush, editsOf, layEdit, EDITS as SHOOT_EDITS } from "./shootedits.js";
import { flushWaits } from "./notionwaits.js";

const { CONFLICT, NO_OP, PUSH_RECORD, TAKE_NOTION, REBASE, FACTS, truthy, int } = L;

const LINK_KEY = "s/notion-link.json";
const STORY_KEY = "s/notion-story.json";
const CONFLICTS_KEY = "s/notion-conflicts.json";
const PEOPLE_KEY = "s/notion-people.json";
const TEMPLATES_KEY = "s/record-templates.json";
const LEASE_KEY = "s/notion-sync-lease.json";
const LEASE_SECONDS = 300;

const CREW_EVERY = 300;      // seconds between crew reads   (notionsync.CREW_EVERY)
const PEOPLE_EVERY = 300;    // seconds between people reads (notionsync.PEOPLE_EVERY)
const OPTIONS_EVERY = 3600;  // seconds Notion's choices are kept (Python: the app's lifetime)
const FIELDS = Object.keys(FACTS);
const BY = "notion";
const COMPANY_CREDITS = new Set(["production_company"]);
const CREW_SOURCE = L.IDS.crew[1];

const clone = (x) => (x === undefined ? undefined : JSON.parse(JSON.stringify(x)));
const nowSec = () => Date.now() / 1000;
/** notionsync._now — microseconds, as Python stamps them. */
const nowIso = () => new Date().toISOString().replace("Z", "000Z");
const bareId = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

/** notionsync.NotionTrouble */
export class NotionTrouble extends Error {}
/** notionsync.Refused */
class Refused extends Error {}

const STATUS_OF = { validation_error: 400, invalid_json: 400, invalid_request_url: 400, invalid_request: 400,
  missing_version: 400, unauthorized: 401, restricted_resource: 403, object_not_found: 404, conflict_error: 409,
  rate_limited: 429, internal_server_error: 500, service_unavailable: 503,
  database_connection_unavailable: 503, gateway_timeout: 504 };

/** notionsync.notion — cloud.js's caller, its refusals said the way
 * Python says them ("Notion answered 404: …"), every call counted, and in a
 * dry run anything that is not a read refused before it leaves. */
function notionCaller(env, cx) {
  const n = notionOf(env);
  return async function notion(path, method = "GET", body) {
    if (cx.dry && method !== "GET" && !path.endsWith("/query")) {
      throw new NotionTrouble(`dry run: ${method} ${path} blocked`);
    }
    cx.requests += 1;
    try {
      if (method === "GET") return await n.get(path);
      if (method === "POST") return await n.post(path, body);
      if (method === "PATCH") return await n.patch(path, body);
      if (method === "DELETE") return await n.del(path);
      throw new Error(`no such method ${method}`);
    } catch (e) {
      if (e instanceof NotionTrouble) throw e;
      if (e instanceof Handoff) {
        const code = e.message;
        throw new NotionTrouble(`Notion answered ${STATUS_OF[code] || code}: ${code}`);
      }
      const m = /^Notion: ([^ ]+)(?: — (.*))?$/s.exec(String(e && e.message));
      if (m) {
        const code = m[1];
        throw new NotionTrouble(`Notion answered ${STATUS_OF[code] || code}: ${(m[2] || code).slice(0, 160)}`);
      }
      throw new NotionTrouble(`Notion did not answer: ${e && e.message}`);
    }
  };
}

/** notionsync.rows_of */
async function rowsOf(cx, name, body = {}) {
  const out = [];
  let cursor = null;
  for (;;) {
    const b = { ...body, page_size: 100 };
    if (cursor) b.start_cursor = cursor;
    const got = await cx.notion(L.queryPath(name), "POST", b);
    out.push(...(got.results || []));
    if (!got.has_more) return out;
    cursor = got.next_cursor;
  }
}

/** notionsync.blocks_of */
async function blocksOf(cx, page) {
  const out = [];
  let cursor = null;
  for (;;) {
    const got = await cx.notion(`blocks/${page}/children?page_size=100${cursor ? `&start_cursor=${cursor}` : ""}`);
    out.push(...(got.results || []));
    if (!got.has_more) return out;
    cursor = got.next_cursor;
  }
}

// ── the bucket ───────────────────────────────────────────────────────────────

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

async function writeJson(cx, key, body) {
  if (cx.dry) throw new Error(`dry run: ${key} not written`);       // belt and braces
  await cx.env.BUCKET.put(key, JSON.stringify(body, null, 1), { httpMetadata: { contentType: "application/json" } });
}

/** notionsync._save */
async function save(cx) {
  if (cx.dry) return;
  await writeJson(cx, LINK_KEY, cx.st);
}

/** notionsync._story_save */
async function storySave(cx) {
  if (cx.dry) return;
  await writeJson(cx, STORY_KEY, cx.sst);
}

/** notionsync._page_state */
function pageState(st, page) {
  if (!st.pages[page]) st.pages[page] = {};
  const one = st.pages[page];
  if (!one.bases) one.bases = {};
  return one;
}

// ── the record's side ────────────────────────────────────────────────────────

/** notionsync._records — page -> record, read from the bucket. Python asks
 * the hub for `records` then each record's facts when its `updated` moved;
 * here the record *is* one read, so it is read whole once a look. */
async function records(cx) {
  const pages = [];
  let cursor;
  do {
    const got = await cx.env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const page = p.split("/")[1];
      if (/^[0-9a-f]{32}$/.test(page)) pages.push(page);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  const out = {};
  const got = await Promise.all(pages.map((page) => readJson(cx.env, `r/${page}/record.json`)));
  // A minted project (projectid.js) is walked by its Notion page, which the
  // bucket's door reads back to its record.
  for (const r of got) if (r && r.page) out[(typeof r.notion_page === "string" && /^[0-9a-f]{32}$/.test(r.notion_page)) ? r.notion_page : r.page] = r;
  return out;
}

/** notionsync._facts — the facts as read this look; read again after a write. */
async function factsOf(cx, page) {
  if (cx.facts.has(page)) return cx.facts.get(page);
  const r = await readJson(cx.env, `r/${page}/record.json`);
  if (!r) return null;
  const f = r.facts || {};
  cx.facts.set(page, f);
  return f;
}
/** notionsync._forget */
const forget = (cx, page) => cx.facts.delete(page);

/** record.set_facts — {facts} · {conflicts} · {trouble}. `changes` is
 * {field: [value, base]}. */
async function setFacts(cx, page, changes, by) {
  if (cx.dry) throw new Error("dry run: no record written");
  const writeFacts = cx.writeFacts || (await import("./facts.js")).writeFacts;
  const body = {};
  for (const [f, [v, b]] of Object.entries(changes)) body[f] = { value: v, base: int(b) };
  const got = await writeFacts(cx.env, page, body, by);
  if (got.status === 200) return { facts: got.facts };
  if (got.conflicts) return { conflicts: got.conflicts };
  return { trouble: got.problem || `the hub answered ${got.status}` };
}

// ── conflicts (record.note_link_conflict / clear_link_conflict) ──────────────
//
// The Mac kept these in facts-outbox.json beside its offline edits; on the
// hub they are their own file, in the same item shape, read once a look and
// written back at its end — compare-and-set, the look's changes replayed on
// what is there if the console settled one meanwhile.

async function box(cx) {
  if (!cx.box) {
    const got = await cx.env.BUCKET.get(CONFLICTS_KEY);
    let data = null;
    try { data = got ? await got.json() : null; } catch { data = null; }
    cx.box = { etag: got ? got.etag : null, data: data && Array.isArray(data.conflicts) ? data : { conflicts: [] }, ops: [] };
  }
  return cx.box;
}

function applyNote(data, item, field) {
  const page = item.page;
  for (let i = 0; i < data.conflicts.length; i++) {
    const c = data.conflicts[i];
    if (c.kind === "notion" && c.page === page && field in (c.changes || {})) {
      const same = c.changes[field][0] === item.changes[field][0]
        && ((((c.theirs || {})[field]) || {}).v ?? null) === (((item.theirs[field]) || {}).v ?? null);
      if (same) return false;
      data.conflicts[i] = item;
      return true;
    }
  }
  data.conflicts.push(item);
  return true;
}

function applyClear(data, page, field) {
  const kept = data.conflicts.filter((c) => !(c.kind === "notion" && c.page === page && field in (c.changes || {})));
  const moved = kept.length !== data.conflicts.length;
  data.conflicts = kept;
  return moved;
}

/** A stamp that always has a fraction, so its JSON reads back as a float on
 * either side and the conflict's id ("<page>:<met_at>") is spelt the same. */
const fractional = (t) => (Number.isInteger(t) ? t + 0.000001 : t);

/** record.note_link_conflict */
async function noteLinkConflict(cx, page, field, notionWords, fact, why = "", said = "") {
  const b = await box(cx);
  // Two conflicts met in one look land in the same millisecond; Python's
  // clock has microseconds. The stamp is the id he settles by, so it is
  // kept apart from every other on the page.
  let met = fractional(nowSec());
  while (b.data.conflicts.some((c) => c.page === bareId(page) && c.met_at === met)) met = fractional(met + 0.000001);
  const item = { page: bareId(page), kind: "notion", changes: { [field]: [notionWords, int((fact || {}).v)] },
    theirs: { [field]: truthy(fact) ? fact : null }, by: "notion", why, met_at: met };
  if (said) item.said = said;
  const fresh = applyNote(b.data, item, field);
  if (fresh) b.ops.push(["note", item, field]);
  return fresh;
}

/** record.clear_link_conflict */
async function clearLinkConflict(cx, page, field) {
  const b = await box(cx);
  if (applyClear(b.data, bareId(page), field)) b.ops.push(["clear", bareId(page), field]);
}

async function saveBox(cx) {
  if (cx.dry || !cx.box || !cx.box.ops.length) return;
  let { etag, data } = cx.box;
  for (let attempt = 0; attempt < 4; attempt++) {
    const opts = { httpMetadata: { contentType: "application/json" } };
    if (etag) opts.onlyIf = { etagMatches: etag };
    const put = await cx.env.BUCKET.put(CONFLICTS_KEY, JSON.stringify(data, null, 1), opts);
    if (put) return;
    const got = await cx.env.BUCKET.get(CONFLICTS_KEY);         // settled meanwhile: replay on what is there
    etag = got ? got.etag : null;
    let now = null;
    try { now = got ? await got.json() : null; } catch { now = null; }
    data = now && Array.isArray(now.conflicts) ? now : { conflicts: [] };
    for (const op of cx.box.ops) {
      if (op[0] === "note") applyNote(data, op[1], op[2]);
      else applyClear(data, op[1], op[2]);
    }
  }
  cx.said.push("conflicts not kept — the list kept changing");
}

// ── people and choices, read now and then ────────────────────────────────────

/** notionsync._people — [crew rows, shoot rows], or [null, null]. */
async function people(cx, fresh = false) {
  const c = cx.people;
  if (fresh || c.crew === null || nowSec() - c.at >= PEOPLE_EVERY) {
    let crew, shoots;
    try {
      crew = await rowsOf(cx, "crew");
      shoots = await rowsOf(cx, "shoots");
    } catch (e) {
      // **Stale, not fresh** (2026-10-19, Daybreak): the rows kept from the
      // last read that worked are still handed back (the credits read them),
      // but marked, so nothing copies them over the record as if Notion had
      // just said so — a shoot made since that read would be taken off.
      if (e instanceof NotionTrouble) { c.stale = true; return [c.crew, c.shoots]; }
      throw e;
    }
    Object.assign(c, { at: nowSec(), crew, shoots, stale: false });
    cx.peopleMoved = true;
  }
  return [c.crew, c.shoots];
}

/** notionsync._forget_people */
function forgetPeople(cx) {
  cx.people.at = 0;
  cx.peopleMoved = true;
}

/** notionsync._crew_names */
function crewNames(crew) {
  if (crew === null) return null;
  const out = {};
  for (const r of crew) out[bareId(r.id || "")] = (L.names(r, "Name").length ? L.names(r, "Name") : [""])[0];
  return out;
}

/** notionsync._options */
async function options(cx, column) {
  let have = cx.people.options[column];
  if (have === undefined) {
    const ds = await cx.notion(`data_sources/${L.IDS.projects[1]}`);
    const prop = (ds.properties || {})[column] || {};
    have = (((prop.select || {}).options) || []).map((o) => o.name || "");
    cx.people.options[column] = have;
    if (!cx.people.options_at) cx.people.options_at = nowSec();
    cx.peopleMoved = true;
  }
  return have;
}

// ── dry run ──────────────────────────────────────────────────────────────────

/** notionsync._dry */
function dryNote(cx, what) {
  if (!cx.dry) return false;
  cx.DRY.push(what);
  return true;
}

/** notionsync._plan */
function plan(cx, what) {
  if (cx.dry) cx.DRY.push({ decided: true, ...what });
}

// ── one field, one project ───────────────────────────────────────────────────

/** notionsync._base */
function baseOf(v, field, words, edited = "") {
  const kind = FACTS[field][0];
  const out = { v: int(v), hash: L.keyFor(field)(words), edited };
  if (kind !== L.TEXT) out.words = truthy(words) ? String(words) : "";
  return out;
}

/** notionsync._value */
const valueOf = (fact) => (fact && typeof fact.value === "string" ? fact.value : "");

const relationIds = (row, name) => ((((row || {}).properties || {})[name] || {}).relation || []).map((r) => r.id || "");

/** notionsync.crew_plan — pure, as Python: the PATCH body, {} when nothing
 * would change. (`allProjects` / `allShoots`: every id past the 25 a page
 * carries, read before a live write — see `crewPlanLive`.) */
export function crewPlan(personRow, project, { onProject = null, addShoots = [], removeShoots = [], roles = null } = {},
  allProjects = null, allShoots = null) {
  const props = {};
  const projects = allProjects || relationIds(personRow, "Projects");
  const haveP = new Set(projects.map(bareId));
  if (onProject === true && !haveP.has(bareId(project))) {
    props.Projects = { relation: [...projects.map((id) => ({ id })), { id: project }] };
  } else if (onProject === false && haveP.has(bareId(project))) {
    props.Projects = { relation: projects.filter((i) => bareId(i) !== bareId(project)).map((id) => ({ id })) };
  }
  const shoots = allShoots || relationIds(personRow, "Shoots");
  const gone = new Set((removeShoots || []).map(bareId));
  const keep = shoots.filter((i) => !gone.has(bareId(i)));
  const haveS = new Set(keep.map(bareId));
  for (const i of addShoots || []) if (!haveS.has(bareId(i))) keep.push(i);
  if (JSON.stringify(keep.map(bareId)) !== JSON.stringify(shoots.map(bareId))) {
    props.Shoots = { relation: keep.map((id) => ({ id })) };
  }
  if (roles !== null) {
    const now = L.sorted(((((personRow.properties || {}).Role) || {}).multi_select || []).map((o) => o.name || ""));
    const want = L.sorted([...new Set(roles.map((r) => L.pyStrip(String(r))).filter((r) => r))]);
    if (JSON.stringify(want) !== JSON.stringify(now)) props.Role = { multi_select: want.map((r) => ({ name: r })) };
  }
  return props;
}

/** Every id of a relation, past the 25 a read page carries (cloud.js
 * `relationAll`). Python's link wrote back only what the page carried, which
 * would take a person on 26+ projects off the rest; here a live write reads
 * them all first. */
async function relationEvery(cx, page, name) {
  const field = (page.properties || {})[name] || {};
  const ids = (field.relation || []).map((r) => r.id);
  if (!field.has_more || !field.id) return ids;
  const all = [];
  let cursor;
  do {
    const got = await cx.notion(`pages/${page.id}/properties/${encodeURIComponent(field.id)}${cursor ? `?start_cursor=${cursor}` : ""}`);
    for (const item of got.results || []) if (item.relation && item.relation.id) all.push(item.relation.id);
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return all;
}

async function crewPlanLive(cx, row, project, how) {
  if (cx.dry) return crewPlan(row, project, how);
  return crewPlan(row, project, how, await relationEvery(cx, row, "Projects"), await relationEvery(cx, row, "Shoots"));
}

/** notionsync._ensure_on_project */
async function ensureOnProject(cx, person, page, st = null) {
  const row = await cx.notion(`pages/${person}`);
  const p = await crewPlanLive(cx, row, page, { onProject: true });
  if (!Object.keys(p).length) return [];
  if (dryNote(cx, { write: "crew row", person, page, properties: p,
    name: (L.names(row, "Name").length ? L.names(row, "Name") : [""])[0], why: "credited, put on the project" })) {
    return L.sorted(Object.keys(p));
  }
  await cx.notion(`pages/${person}`, "PATCH", { properties: p });
  const back = await cx.notion(`pages/${person}`);
  if (Object.keys(await crewPlanLive(cx, back, page, { onProject: true })).length) {
    throw new NotionTrouble("Notion did not keep the change to a Crew row");
  }
  if (st !== null) {
    const ps = pageState(st, page);
    if (!ps.credit_added) ps.credit_added = [];
    if (!ps.credit_added.includes(bareId(person))) ps.credit_added.push(bareId(person));
  }
  return L.sorted(Object.keys(p));
}

/** notionsync._new_companies */
async function newCompanies(cx, list, crew) {
  const have = crew.map((r) => ({ id: r.id || "", name: (L.names(r, "Name").length ? L.names(r, "Name") : [""])[0] }));
  const made = {};
  for (const name of list) {
    const close = duplicates({ name }, have);
    if (close.length) throw new Refused(`${name} looks like ${close[0].name}, already in Crew. Pick that one, or keep Notion's.`);
    const [props, why] = companyProps({ name });
    if (why) throw new Refused(why);
    if (dryNote(cx, { write: "new crew row", name, properties: props, why: "a company typed in the record" })) continue;
    const pageMade = await cx.notion("pages", "POST", { parent: { type: "data_source_id", data_source_id: CREW_SOURCE }, properties: props });
    const pid = bareId(pageMade.id || "");
    const back = await cx.notion(`pages/${pid}`);
    if ((L.names(back, "Name").length ? L.names(back, "Name") : [""])[0] !== props.Name.title[0].text.content) {
      throw new NotionTrouble(`${name} did not read back as written in Crew`);
    }
    made[name] = pid;
    cx.said.push(`${name} added to Crew as a company (credited in the record)`);
  }
  if (Object.keys(made).length) forgetPeople(cx);
  return made;
}

/** notionsync._people_ids */
async function peopleIds(cx, list, field = "") {
  const [crew] = await people(cx, true);
  if (crew === null) throw new NotionTrouble("the Crew list could not be read");
  let [ids, missing, twice] = L.findPeople(list, crew);
  if (missing.length && !twice.length && COMPANY_CREDITS.has(field)) {
    const made = await newCompanies(cx, missing, crew);
    const found = {};
    list.filter((n) => !missing.includes(n)).forEach((n, i) => { found[n] = ids[i]; });
    ids = list.map((n) => found[n] || made[n]).filter((i) => i);
    missing = [];
  }
  if (missing.length) {
    throw new Refused(`${missing.join(", ")} isn't in Crew in Notion. Add them on the People tab, then save again, or keep Notion's.`);
  }
  if (twice.length) {
    throw new Refused(`There are two people called ${twice.join(", ")} in Crew. Merge them in Notion, then try again.`);
  }
  return ids;
}

/** notionsync._credit_names */
function creditNames(field, words, facts) {
  const role = L.ROLE_OF[field];
  const stored = (((facts || {}).credits) || {}).value;
  if (role && Array.isArray(stored)) {
    const list = L.creditPeople(L.creditTidy(stored), role);
    if (L.keyFor(field)(L.creditLine(list)) === L.keyFor(field)(words)) return list;
  }
  return L.splitPeople(words);
}

/** notionsync._push */
async function push(cx, page, field, words, ps, v, facts = null) {
  const [kind, column] = FACTS[field];
  words = truthy(words) ? String(words) : "";
  const key = L.keyFor(field);
  const opts = kind === L.CHOICE ? await options(cx, column) : null;
  const why = L.pushRefusal(field, words, opts);
  if (why) throw new Refused(why);
  const ids = kind === L.PEOPLE ? await peopleIds(cx, creditNames(field, words, facts), field) : [];
  if (kind === L.ICON && ((ps.bases[field] || {}).refused ?? null) === key(words)) {
    throw new Refused("Notion doesn't have that icon. Pick another.");
  }
  if (!cx.dry) {
    if (!ps.bases[field]) ps.bases[field] = {};
    ps.bases[field].pushed = key(words);
    await save(cx);                                              // write-ahead
  }
  let edited = "";
  if ([L.TEXT, L.CHOICE, L.PEOPLE, L.URL, L.DATES].includes(kind)) {
    let prop;
    if (kind === L.TEXT) prop = { rich_text: L.richTextFor(words) };
    else if (kind === L.URL) prop = { url: L.pyStrip(words) || null };
    else if (kind === L.DATES) prop = L.notionDate(words);
    else if (kind === L.CHOICE) {
      const pick = L.pickChoice(opts, words);
      prop = { select: pick ? { name: pick } : null };
    } else prop = { relation: ids.map((id) => ({ id })) };
    if (!dryNote(cx, { write: "project row", page, field, properties: { [column]: prop }, value: words })) {
      await cx.notion(`pages/${page}`, "PATCH", { properties: { [column]: prop } });
      const row = await cx.notion(`pages/${page}`);
      let ok;
      if (kind === L.PEOPLE) {
        const got = ((((row.properties || {})[column]) || {}).relation || []).map((r) => bareId(r.id || ""));
        ok = JSON.stringify(L.sorted(got)) === JSON.stringify(L.sorted(ids.map(bareId)));
      } else if (kind === L.TEXT) {
        const back = L.propertyText(row, column);
        ok = back !== null && key(back) === key(words);
      } else if (kind === L.URL) {
        const back = L.urlText(row, column);
        ok = back !== null && key(back) === key(L.pyStrip(words));
      } else if (kind === L.DATES) {
        const back = L.datesText(row, column);
        ok = back !== null && key(back) === key(words);
      } else {
        const back = L.choiceText(row, column);
        ok = back !== null && key(back) === key(words);
      }
      if (!ok) throw new NotionTrouble(`${column} did not read back as written`);
      edited = row.last_edited_time || "";
    }
  }
  if (kind === L.ICON) {
    if (!dryNote(cx, { write: "project row", page, field, icon: words })) {
      try {
        await cx.notion(`pages/${page}`, "PATCH", { icon: L.iconPayload(words) });
      } catch (e) {
        if (e instanceof NotionTrouble && String(e.message).includes("400") && String(e.message).toLowerCase().includes("icon")) {
          if (!cx.dry) {
            if (!ps.bases[field]) ps.bases[field] = {};
            ps.bases[field].refused = key(words);
            await save(cx);
          }
          throw new Refused("Notion doesn't have that icon. Pick another.");
        }
        throw e;
      }
      const row = await cx.notion(`pages/${page}`);
      const back = L.iconText(row);
      if (back === null || key(back) !== key(words)) throw new NotionTrouble("the icon did not read back as written");
      edited = row.last_edited_time || "";
    }
  }
  if (kind === L.PEOPLE) {
    for (const person of ids) await ensureOnProject(cx, person, page, cx.st);
    forgetPeople(cx);
    cx.st.crew_at = 0;
  }
  if (!cx.dry) {
    ps.bases[field] = baseOf(v, field, words, edited);
    await save(cx);
  }
  return edited;
}

/** notionsync._write_record */
async function writeRecord(cx, page, field, words, fact, facts = null, list = null) {
  if (!(field in L.ROLE_OF)) {
    return setFacts(cx, page, { [field]: [words, int((fact || {}).v)] }, BY);
  }
  if (facts === null) facts = cx.facts.has(page) ? cx.facts.get(page) : null;
  if (facts === null) {
    facts = await factsOf(cx, page);
    if (facts === null) return { trouble: "offline" };
  }
  facts = { ...facts, [field]: fact || {} };
  const next = L.withPeople(L.creditsOf(facts), L.ROLE_OF[field], list !== null ? list : L.creditSplit(words));
  const changes = L.creditsPlan(facts, next);
  if (!Object.keys(changes).length) return { facts };
  return setFacts(cx, page, changes, BY);
}

/** notionsync._take */
async function take(cx, page, field, words, fact, edited, ps, list = null) {
  if (dryNote(cx, { write: "record", page, field, value: words })) return true;
  const got = await writeRecord(cx, page, field, words, fact, null, list);
  if ("conflicts" in got || got.trouble) return false;
  const fresh = ((got.facts || {})[field]) || fact;
  ps.bases[field] = baseOf(fresh.v, field, words, edited);
  forget(cx, page);
  await save(cx);
  return true;
}

/** notionsync._conflict */
async function conflict(cx, page, name, field, words, fact, why, said = "") {
  if (dryNote(cx, { write: "conflict card", page, field, notion: words, record: valueOf(fact), why, said })) return true;
  const fresh = await noteLinkConflict(cx, page, field, words, fact || {}, why, said);
  if (fresh) {
    // The Mac showed a desktop notification here; the server hands it back
    // to whoever runs the look (a push, later).
    cx.notify.push({
      page, field, project: name,
      title: !said ? "Changed in two places" : "Can't be written to Notion",
      body: `${name}: the ${field} — ${said || "changed in Notion and in the record."} Open Projects Console to pick which to keep.`,
    });
  }
  return fresh;
}

/** notionsync._one */
async function one(cx, page, name, row, words, facts, bot, people_) {
  const pushed = {};
  const ps = pageState(cx.st, page);
  const edited = row.last_edited_time || "";
  const by = ((row.last_edited_by || {}).id) || "";
  const [crew] = people_;
  const namesById = crewNames(crew);
  const lay = L.resolveLayout(facts, L.choiceText(row, "Type") || "", cx.templates);
  for (const field of FIELDS) {
    const [kind, column] = FACTS[field];
    const key = L.keyFor(field);
    const fact = truthy(facts[field]) ? facts[field] : {};
    if (truthy(fact) && !(typeof fact.value === "string" || fact.value === null || fact.value === undefined)) continue;
    const base = ps.bases[field] ?? null;
    const rec = valueOf(fact);
    let list = null;
    let nv;
    if (field in words) nv = words[field];
    else if (kind === L.PEOPLE) {
      list = namesById === null ? null : L.peopleNames(row, column, namesById);
      nv = list === null ? null : L.joinPeople(list);
    } else nv = L.notionValue(field, row, namesById);
    const bots = bot ? [bot] : [];
    let d;
    if (kind === L.TITLE) d = L.decideTitle(fact, nv, base);
    else if (kind === L.ICON) d = L.decideIcon(fact, nv, edited, by, bots, base);
    else {
      const f = truthy(fact) || truthy(base) ? { ...fact, synced_base: base } : null;
      d = L.decide(f, nv, edited, by, bots, key);
    }
    const nvShown = typeof nv === "string" ? nv : null;
    if (!L.shows(lay, field) && (d.action === CONFLICT || (d.action === PUSH_RECORD && !L.normalize(rec)))) {
      plan(cx, { project: name, field, action: "nothing",
        why: `${field} is hidden on this project — ${d.why}; both kept as they are`, notion: nvShown, record: rec });
      if (!cx.dry) await clearLinkConflict(cx, page, field);
      continue;
    }
    plan(cx, { project: name, field, action: d.action, why: d.why, notion: nvShown, record: rec });
    if (d.action === REBASE) {
      if (!cx.dry) {
        ps.bases[field] = baseOf(fact.v, field, nv, edited);
        await save(cx);
      }
      continue;
    }
    if (d.action === NO_OP) {
      if (nv !== null && nv !== undefined && key(nv) === key(rec) && !cx.dry) {
        const agreed = baseOf(fact.v, field, nv, edited);
        if (!truthy(base) || base.v !== agreed.v || base.hash !== agreed.hash
            || truthy(base.pushed) || (base.words ?? null) !== (agreed.words ?? null)) {
          ps.bases[field] = agreed;
          await save(cx);
        }
        await clearLinkConflict(cx, page, field);
      }
      continue;
    }
    if (d.action === TAKE_NOTION) {
      if (await take(cx, page, field, nv, fact, edited, ps, list)) {
        cx.said.push(`${name} · ${field}: Notion → record (${d.why})`);
      }
    } else if (d.action === PUSH_RECORD) {
      try {
        await push(cx, page, field, rec, ps, int(fact.v), facts);
        pushed[field] = rec;
        cx.said.push(`${name} · ${field}: record → Notion (${d.why})`);
      } catch (e) {
        if (e instanceof Refused) {
          if (await conflict(cx, page, name, field, nv, fact, `the record's ${field} can't be written to Notion`, e.message)) {
            cx.said.push(`${name} · ${field}: can't go to Notion — waiting for him (${e.message})`);
          }
        } else if (e instanceof NotionTrouble) {
          cx.said.push(`${name} · ${field}: could not write Notion — ${e.message}`);
        } else throw e;
      }
    } else if (d.action === CONFLICT) {
      if (await conflict(cx, page, name, field, nv, fact, d.why)) {
        cx.said.push(`${name} · ${field}: both changed — waiting for him`);
      }
    }
  }
  return pushed;
}

/** notionsync._migrate */
async function migrate(cx, page, name, row, facts, crew) {
  const changes = {};
  let notes = [];
  if (crew !== null) {
    const list = crew.map((r) => (L.names(r, "Name").length ? L.names(r, "Name") : [""])[0]);
    const [moved, said] = L.creditsMigrate(facts, list);
    Object.assign(changes, moved);
    notes = notes.concat(said);
  }
  if ("value" in ((facts.credits && typeof facts.credits === "object") ? facts.credits : {})) {
    const lines = {};
    for (const [f, c] of Object.entries(L.creditsPlan(facts, L.creditsOf(facts)))) {
      if (f !== "credits" && !(f in changes)) lines[f] = c;
    }
    if (Object.keys(lines).length) {
      Object.assign(changes, lines);
      notes.push(`lines for ${L.sorted(Object.keys(lines)).join(", ")}`);
    }
  }
  const folded = L.foldStory(facts, L.choiceText(row, "Type") || "", cx.templates);
  if (folded !== null) {
    changes.layout = [folded, int(((facts.layout || {}).v))];
    notes.push(`Story ${facts.story.value} → layout ${L.pyDumps(folded)}`);
  }
  if (!Object.keys(changes).length) return facts;
  const shown = {};
  for (const [f, [v]] of Object.entries(changes)) {
    shown[f] = f === "credits" ? v.map((x) => `${x.role}: ${L.creditLine(x.people)}`).join("; ")
      : (v && typeof v === "object" && !Array.isArray(v) ? L.pyDumps(v) : v);
  }
  if (dryNote(cx, { write: "record", page, field: "migrate", value: shown })) {
    plan(cx, { project: name, field: "migrate", action: TAKE_NOTION, why: notes.join("; ") || "credits list from the lines",
      notion: null, record: shown });
    const out = { ...facts };
    for (const [f, [v]] of Object.entries(changes)) out[f] = { ...(facts[f] || {}), value: v };
    return out;
  }
  const got = await setFacts(cx, page, changes, "console");
  if (got.trouble || "conflicts" in got) return facts;
  cx.said.push(`${name}: migrated — ${notes.join("; ") || Object.keys(changes).join(", ")}`);
  forget(cx, page);
  return got.facts || facts;
}

/** notionsync._credit_people */
async function creditPeople(cx, page, name, row, facts, crew, shoots) {
  if (crew === null || shoots === null) return;
  const project = bareId(page);
  const named = new Set();
  for (const [kind, column] of Object.values(FACTS)) {
    if (kind === L.PEOPLE) for (const r of ((((row.properties || {})[column]) || {}).relation || [])) named.add(bareId(r.id || ""));
  }
  for (const credit of L.creditsOf(facts)) {
    const [ids] = L.findPeople(credit.people.flatMap((p) => L.splitPeople(p)), crew);
    for (const i of ids) named.add(i);
  }
  const byId = new Map(crew.map((r) => [bareId(r.id || ""), r]));
  const projectShoots = new Set(shoots.filter((x) => L.related(x, "Project").includes(project)).map((x) => bareId(x.id || "")));
  const ps = pageState(cx.st, page);
  for (const pid of L.sorted([...named])) {
    const r = byId.get(pid);
    if (r === undefined || L.related(r, "Projects").includes(project)) continue;
    try {
      if ((await ensureOnProject(cx, pid, page, cx.dry ? null : cx.st)).length) {
        cx.said.push(`${name} · ${(L.names(r, "Name").length ? L.names(r, "Name") : [""])[0]}: on the project (credited)`);
      }
    } catch (e) {
      if (!(e instanceof NotionTrouble)) throw e;
      cx.said.push(`${name} · could not put a credited person on the project — ${e.message}`);
    }
  }
  const before = ps.credit_added || [];
  const added = [...before];
  for (const pid of [...added]) {
    if (named.has(pid)) continue;
    const r = byId.get(pid);
    if (r === undefined || !L.related(r, "Projects").includes(project)) continue;
    const onShoot = L.related(r, "Shoots").some((s) => projectShoots.has(s));
    if (!onShoot) {
      const who = (L.names(r, "Name").length ? L.names(r, "Name") : [""])[0];
      if (dryNote(cx, { write: "crew row", person: pid, page, properties: { Projects: "without this project" },
        name: who, why: "no credit names them now" })) continue;
      try {
        const got = await cx.notion(`pages/${pid}`);
        const p = await crewPlanLive(cx, got, page, { onProject: false });
        if (Object.keys(p).length) {
          await cx.notion(`pages/${pid}`, "PATCH", { properties: p });
          if (Object.keys(await crewPlanLive(cx, await cx.notion(`pages/${pid}`), page, { onProject: false })).length) {
            throw new NotionTrouble("Notion did not keep the change to a Crew row");
          }
        }
        cx.said.push(`${name} · ${who}: off the project (no credit now)`);
      } catch (e) {
        if (!(e instanceof NotionTrouble)) throw e;
        cx.said.push(`${name} · could not take ${who} off the project — ${e.message}`);
        continue;
      }
    }
    added.splice(added.indexOf(pid), 1);
    cx.st.crew_at = 0;
  }
  if (JSON.stringify(added) !== JSON.stringify(ps.credit_added || []) || "credit_added" in ps) ps.credit_added = added;
}

// ── the Story section in the page body (storyblocks) ─────────────────────────

/** notionsync._rich_prop */
function richProp(words) {
  return { type: "rich_text", rich_text: L.richTextFor(words).map((p) => ({ type: "text", plain_text: p.text.content, text: p.text })) };
}

/** notionsync._story_find — [section id|null, its children|null, top blocks|null] */
async function storyFind(cx, page, row, ss) {
  const cid = ss.container;
  if (cid) {
    try {
      const got = await cx.notion(`blocks/${cid}`);
      if (!(got.in_trash || got.archived) && got.type === "synced_block") return [cid, await blocksOf(cx, cid), null];
    } catch (e) {
      if (!(e instanceof NotionTrouble) || !String(e.message).includes("404")) throw e;
    }
    delete ss.container;
  }
  if (!L.needsLook(row.last_edited_time || "", ss.looked)) return [null, null, null];
  const top = await blocksOf(cx, page);
  ss.looked = nowIso();
  for (const b of top) {
    if (b.type === "synced_block" && b.has_children) {
      const kids = await blocksOf(cx, b.id);
      if (L.isContainer(b, kids)) {
        ss.container = bareId(b.id);
        return [ss.container, kids, top];
      }
    }
  }
  return [null, null, top];
}

const storyShows = (cx, row, facts) => {
  const lay = L.resolveLayout(facts, L.choiceText(row, "Type") || "", cx.templates);
  return (field) => L.shows(lay, field);
};

/** notionsync._story_before */
async function storyBefore(cx, page, name, row, facts) {
  if (!cx.sst.pages[page]) cx.sst.pages[page] = {};
  const ss = cx.sst.pages[page];
  if (!ss.fields) ss.fields = {};
  const managed = ss.fields;
  let cid, kids, top;
  try {
    [cid, kids, top] = await storyFind(cx, page, row, ss);
  } catch (e) {
    if (!(e instanceof NotionTrouble)) throw e;
    cx.said.push(`${name} · Story section not read — ${e.message}`);
    return null;
  }
  const parsed = kids !== null ? L.parseStory(kids) : null;
  const showsFn = storyShows(cx, row, facts);
  const ctx = { container: cid, parsed, top, shows: showsFn };
  if (parsed === null) return ctx;
  if (ss.dirty) return ctx;
  const edits = {};
  const now = nowIso();
  for (const field of L.STORY_FIELDS) {
    const part = parsed.parts[field];
    const column = L.PROPERTIES[field];
    const boxWords = L.propertyText(row, column);
    if (part === undefined || boxWords === null || !showsFn(field)) continue;
    const typed = part.words;
    const last = managed[field] ?? null;
    if (last !== null && last === L.fingerprint(typed)) continue;
    if (L.sameWords(boxWords, typed)) { managed[field] = L.fingerprint(typed); continue; }
    if (last === null && L.normalize(boxWords)) continue;
    if (!L.settled(part.edited, now)) {
      plan(cx, { project: name, field, action: "wait", why: "typed in the Story section this minute — read next look" });
      return null;
    }
    edits[field] = typed;
  }
  for (const [field, typed] of Object.entries(edits)) {
    const column = L.PROPERTIES[field];
    plan(cx, { project: name, field, action: "page → box", why: "typed in the page's Story section", notion: typed, record: null });
    if (!dryNote(cx, { write: "project row", page, field, properties: { [column]: "from the Story section" }, value: typed })) {
      let back;
      try {
        await cx.notion(`pages/${page}`, "PATCH", { properties: { [column]: { rich_text: L.richTextFor(typed) } } });
        back = await cx.notion(`pages/${page}`);
      } catch (e) {
        if (!(e instanceof NotionTrouble)) throw e;
        cx.said.push(`${name} · ${field}: typed in the page, not written to the box — ${e.message}`);
        return null;
      }
      const got = L.propertyText(back, column);
      if (got === null || !L.sameWords(got, typed)) {
        cx.said.push(`${name} · ${field}: typed in the page, the box did not read back as written`);
        return null;
      }
      managed[field] = L.fingerprint(typed);
      row.last_edited_time = back.last_edited_time || row.last_edited_time || "";
    }
    if (!row.properties) row.properties = {};
    row.properties[column] = richProp(typed);
    cx.said.push(`${name} · ${field}: typed in the page → the box`);
  }
  return ctx;
}

/** notionsync._story_apply */
async function storyApply(cx, cid, ops) {
  for (const op of ops) {
    if (op[0] === "patch") await cx.notion(`blocks/${op[1]}`, "PATCH", { paragraph: { rich_text: L.richTextFor(op[2]) } });
    else if (op[0] === "delete") await cx.notion(`blocks/${op[1]}`, "DELETE");
    else if (op[0] === "insert") {
      const body = { children: op[2] };
      if (op[1]) body.after = op[1];
      else body.position = { type: "start" };
      await cx.notion(`blocks/${cid}/children`, "PATCH", body);
    }
  }
}

/** notionsync._story_after */
async function storyAfter(cx, page, name, row, facts, ctx, pushed) {
  if (ctx === null) return;
  if (!cx.sst.pages[page]) cx.sst.pages[page] = {};
  const ss = cx.sst.pages[page];
  if (!ss.fields) ss.fields = {};
  const managed = ss.fields;
  const showsFn = ctx.shows;
  const words = {};
  for (const field of L.STORY_FIELDS) {
    const w = field in pushed ? pushed[field] : L.propertyText(row, L.PROPERTIES[field]);
    if (w === null && showsFn(field)) return;
    words[field] = w;
  }
  const want = L.wanted(words, showsFn);
  let cid = ctx.container;
  const parsed = ctx.parsed;
  try {
    if (cid === null) {
      if (!want.length) {
        for (const k of Object.keys(managed)) delete managed[k];
        return;
      }
      const top = ctx.top !== null ? ctx.top : await blocksOf(cx, page);
      const [, after] = L.anchor(top);
      const parts = want.map(([f]) => L.LABELS[f]);
      plan(cx, { project: name, field: "story section", action: "make", why: `parts: ${parts.join(", ")}`, notion: null, record: null });
      if (dryNote(cx, { write: "page section", page, make: parts, where: after ? "above Notes" : "at the top" })) return;
      ss.dirty = true;
      await storySave(cx);
      const body = { children: [L.container(want)] };
      if (after) body.after = after;
      else body.position = { type: "start" };
      const made = await cx.notion(`blocks/${page}/children`, "PATCH", body);
      const fresh = (made.results || []).find((b) => b.type === "synced_block");
      if (!fresh) throw new NotionTrouble("the Story section was not made");
      cid = ss.container = bareId(fresh.id);
      cx.said.push(`${name} · Story section made: ${parts.join(", ")}`);
    } else {
      const partsNow = new Set(Object.keys(parsed.parts));
      const hisOwn = [...partsNow].filter((f) => !(f in managed) && !showsFn(f));
      if (!want.length && !parsed.foreign.length && !hisOwn.length) {
        plan(cx, { project: name, field: "story section", action: "take out", why: "no story words to show", notion: null, record: null });
        if (dryNote(cx, { write: "page section", page, delete: "the whole Story section" })) return;
        await cx.notion(`blocks/${cid}`, "DELETE");
        delete ss.container;
        for (const k of Object.keys(managed)) delete managed[k];
        cx.said.push(`${name} · Story section taken out (nothing to show)`);
        return;
      }
      const ops = L.storyPlan(parsed, want, managed, showsFn);
      if (!ops.length) {
        ss.fields = Object.fromEntries(want.map(([f, w]) => [f, L.fingerprint(w)]));
        delete ss.dirty;
        return;
      }
      const wantD = Object.fromEntries(want);
      const what = L.sorted([...new Set(L.STORY_FIELDS.filter((f) => ((f in wantD) !== partsNow.has(f))
        || (f in wantD && !L.sameWords(wantD[f], parsed.parts[f].words))).map((f) => L.LABELS[f] || f))]);
      plan(cx, { project: name, field: "story section", action: "update", why: `parts: ${what.join(", ")}`, notion: null, record: null });
      if (dryNote(cx, { write: "page section", page, ops: ops.map((o) => o[0]), parts: what })) return;
      ss.dirty = true;
      await storySave(cx);
      await storyApply(cx, cid, ops);
      cx.said.push(`${name} · Story section: ${what.join(", ") || "tidied"}`);
    }
    const back = L.parseStory(await blocksOf(cx, cid));
    const wrong = want.filter(([f, w]) => !(f in back.parts) || !L.sameWords(back.parts[f].words, w)).map(([f]) => f);
    if (wrong.length) {
      cx.said.push(`${name} · Story section did not read back as written: ${wrong.join(", ")}`);
      ss.fields = Object.fromEntries(want.filter(([f]) => f in back.parts).map(([f]) => [f, L.fingerprint(back.parts[f].words)]));
      return;
    }
    ss.fields = Object.fromEntries(want.map(([f, w]) => [f, L.fingerprint(w)]));
    delete ss.dirty;
  } catch (e) {
    if (!(e instanceof NotionTrouble)) throw e;
    cx.said.push(`${name} · Story section not written — ${e.message}`);
  }
}

/** notionsync._headings */
async function headings(cx, page, row) {
  const ps = pageState(cx.st, page);
  let kept = ps.headings || {};
  const unread = !Object.values(L.LINK_HEADINGS).every((k) => k in kept);
  if (unread || L.needsLook(row.last_edited_time || "", ps.blocks_read)) {
    let secs;
    try {
      secs = L.sections(await blocksOf(cx, page));
    } catch (e) {
      if (e instanceof NotionTrouble) return null;
      throw e;
    }
    ps.headings = Object.fromEntries(Object.entries(secs).map(([k, s]) => [k, s.found ? s.text : null]));
    ps.blocks_read = nowIso();
  }
  kept = ps.headings || {};
  return Object.fromEntries(Object.entries(kept).map(([k, v]) => [k, new L.Section(v !== null, "", v ? [v] : [], [])]));
}

// ── crew and shoots, Notion → record ─────────────────────────────────────────

const stable = (v) => L.pyDumps(v === undefined ? null : v);
const titleOf = (row) => L.plain((((row.properties || {}).Project) || {}).title);

/** notionsync._crew_tick */
async function crewTick(cx, rows, recs) {
  const said = [];
  const [crew, shoots] = await people(cx, true);
  if (crew === null || shoots === null || cx.people.stale) return ["crew not read — Notion did not answer"];
  for (const row of rows) {
    const page = bareId(row.id || "");
    if (!(page in recs)) continue;
    const facts = await factsOf(cx, page);
    if (facts === null) continue;
    const here = facts.crew_roles && typeof facts.crew_roles.value === "object" ? facts.crew_roles.value : null;
    const snap = L.crewSnapshot(page, crew, shoots, here);
    const have = facts.crew || {};
    if (stable(have.value) === stable(snap)) continue;
    if (!snap.length && !truthy(have)) continue;
    if (dryNote(cx, { write: "record", page, field: "crew", value: `${snap.length} people` })) continue;
    const got = await setFacts(cx, page, { crew: [snap, int(have.v)] }, BY);
    if (!got.trouble && !("conflicts" in got)) {
      forget(cx, page);
      said.push(`${titleOf(row)} · crew: ${snap.length} people, from Notion`);
    }
  }
  return said;
}

/** The record's shoot edits that Notion has not got yet, written to their rows
 * (shootedits.js): the record is the master, this is Notion following. Each
 * row is read as Notion has it now; one that moved in Notion since the edit
 * was made keeps Notion's words and the edit is let go. */
async function shootEditsTick(cx, rows, recs, only = null) {
  const said = [];
  for (const row of rows) {
    const page = bareId(row.id || "");
    if (!(page in recs) || (only && page !== only)) continue;
    const facts = await factsOf(cx, page);
    if (facts === null) continue;
    const edits = editsOf(facts);
    const ids = Object.keys(edits);
    if (!ids.length) continue;
    const name = titleOf(row);
    if (dryNote(cx, { write: "notion", page, field: "shoot_edits", value: `${ids.length} shoot edits` })) continue;
    const steps = await planPush(edits, async (id) => (await cx.notion(`pages/${id}`)).properties || {});
    const left = { ...edits };
    const landed = [];
    let touched = false;
    for (const step of steps) {
      if (step.wait) {
        said.push(`${name} · shoot edit ${step.id.slice(0, 6)}: ${step.note}`);
        continue;
      }
      if (step.patch) {
        try {
          await cx.notion(`pages/${step.id}`, "PATCH", { properties: step.patch });
        } catch (e) {
          if (!(e instanceof NotionTrouble)) throw e;
          const tries = (Number(left[step.id].tries) || 0) + 1;
          if (tries < 10) {
            left[step.id] = { ...left[step.id], tries };
            said.push(`${name} · shoot edit ${step.id.slice(0, 6)}: Notion did not take it yet (${e.message}); tried ${tries} times`);
            touched = true;
            continue;
          }
          step.note = `dropped: Notion would not take it after ${tries} tries (${e.message})`;
          step.landed = false;
        }
      }
      delete left[step.id];
      touched = true;
      if (step.landed) landed.push(step.id);
      said.push(`${name} · shoot edit ${step.id.slice(0, 6)}: ${step.note}`);
    }
    if (!touched) continue;
    const changes = { [SHOOT_EDITS]: [left, int((facts[SHOOT_EDITS] || {}).v)] };
    // the record's copy of the Shoots rows takes what Notion now has, so the
    // next edit is checked against the shoot as it is, not as it was
    const copy = facts.shoots && Array.isArray(facts.shoots.value) ? facts.shoots.value : null;
    if (copy && landed.length) {
      changes.shoots = [copy.map((x) => (landed.includes(x.id) ? layEdit(x, edits[x.id]) : x)), int(facts.shoots.v)];
    }
    const got = await setFacts(cx, page, changes, BY);
    if (!got.trouble && !("conflicts" in got)) {
      forget(cx, page);
      forgetPeople(cx);        // the Shoots rows are read again, so the record's copy is Notion's new words
    }
  }
  return said;
}

/** The project names Notion has, kept in the bucket (cloud.js `fastPage`) so a
 * save on the record can find its project without asking Notion. A title two
 * projects share is left out: that one is asked about in Notion, as before. */
async function keepNames(cx, rows) {
  if (cx.dry) return;
  const seen = new Map();
  for (const row of rows) {
    const title = titleOf(row);
    const page = bareId(row.id || "");
    if (!title || !page) continue;
    seen.set(title, seen.has(title) ? "" : page);
  }
  const names = Object.fromEntries([...seen].filter(([, page]) => page).sort((a, b) => (a[0] < b[0] ? -1 : 1)));
  const kept = await readJson(cx.env, NAMES_KEY);
  if (kept && JSON.stringify(kept.names || {}) === JSON.stringify(names)) return;
  await writeJson(cx, NAMES_KEY, { names, at: nowIso() });
}

/**
 * Shoots added from the AI connector while Notion was out (`mcpshoots.js`,
 * the record's `shoots_waiting`): made now that Notion answers, one add run
 * again as an ordinary Add Shoot, then taken off the queue. Never throws.
 */
async function waitingShootsTick(cx, rows, recs, only = null) {
  if (cx.dry || cx.env.SHOOTS_WAITING_OFF) return [];
  const said = [];
  for (const row of rows) {
    const page = bareId(row.id || "");
    if (!(page in recs) || (only && page !== only)) continue;
    const mine = (((recs[page] || {}).facts || {}).shoots_waiting || {}).value;
    if (!Array.isArray(mine) || !mine.length) continue;
    try {
      const { catchUpWaiting } = await import("./mcpshoots.js");
      const lines = await catchUpWaiting(cx.env, String(recs[page].page || page), cx.shootsDeps || {});
      if (lines.length) forget(cx, page);
      // a shoot just made: the Shoots rows are read again this look, so the
      // record's copy has it at once and no screen goes a minute without it
      if (lines.some((l) => l.includes("made in Notion"))) { forgetPeople(cx); cx.st.crew_at = 0; }
      said.push(...lines);
    } catch (e) {
      said.push(`shoots waiting: ${String((e && e.message) || e).slice(0, 120)}`);
    }
  }
  return said;
}

/** notionsync._shoots_tick */
async function shootsTick(cx, rows, recs, only = null) {
  const said = [];
  const [, shootRows] = await people(cx);
  if (shootRows === null || cx.people.stale) return ["shoots not read — Notion did not answer"];
  for (const row of rows) {
    const page = bareId(row.id || "");
    if (!(page in recs) || (only && page !== only)) continue;
    const facts = await factsOf(cx, page);
    if (facts === null) continue;
    const have = facts.shoots || {};
    // Notion's rows, and every shoot the record has that Notion did not list
    // kept (L.keepShoots): a sync adds and updates shoots, never takes one off.
    const [snap, kept] = L.keepShoots(L.shootsSnapshot(page, shootRows), have.value);
    if (stable(have.value) === stable(snap)) continue;
    if (!snap.length && !truthy(have)) continue;
    const name = titleOf(row);
    if (dryNote(cx, { write: "record", page, field: "shoots", value: `${snap.length} shoots` })) {
      plan(cx, { project: name, field: "shoots", action: TAKE_NOTION,
        why: `${snap.length} Shoots rows in Notion — the record keeps a copy`,
        notion: snap.map((s) => L.pyStrip(`${s.label} ${s.start}`)).join(", "), record: null });
      continue;
    }
    const got = await setFacts(cx, page, { shoots: [snap, int(have.v)] }, BY);
    if (!got.trouble && !("conflicts" in got)) {
      forget(cx, page);
      said.push(`${name} · shoots: ${snap.length}, from Notion`);
      for (const k of kept) said.push(`${name} · shoot “${k.title || k.id}” is on the record but not in Notion: kept`);
    }
  }
  return said;
}

// ── the look ─────────────────────────────────────────────────────────────────

async function loadState(cx, given) {
  const link = given && given.link !== undefined ? clone(given.link) : await readJson(cx.env, LINK_KEY);
  const story = given && given.story !== undefined ? clone(given.story) : await readJson(cx.env, STORY_KEY);
  cx.st = link && typeof link === "object" ? link : {};
  if (!cx.st.pages) cx.st.pages = {};
  cx.sst = story && typeof story === "object" ? story : {};
  if (!cx.sst.pages) cx.sst.pages = {};
}

/** One look at a lease, so two minutes' looks never run over each other
 * (Python held a lock; a minute's look that runs long would otherwise meet
 * the next one). Live only. */
async function takeLease(env) {
  const got = await env.BUCKET.get(LEASE_KEY);
  let held = null;
  try { held = got ? await got.json() : null; } catch { held = null; }
  if (held && nowSec() - Number(held.at || 0) < LEASE_SECONDS) return null;
  const id = crypto.randomUUID();
  const opts = { httpMetadata: { contentType: "application/json" } };
  if (got) opts.onlyIf = { etagMatches: got.etag };
  const put = await env.BUCKET.put(LEASE_KEY, JSON.stringify({ id, at: nowSec() }), opts);
  return put ? id : null;
}

async function dropLease(env, id) {
  const got = await env.BUCKET.get(LEASE_KEY);
  let held = null;
  try { held = got ? await got.json() : null; } catch { held = null; }
  if (held && held.id === id) await env.BUCKET.delete(LEASE_KEY);
}

/** What Python kept in memory between looks: the Crew and Shoots rows and
 * Notion's choices. Live only — a dry run reads them afresh, as a fresh
 * Python process does. */
async function loadPeople(cx) {
  const kept = await readJson(cx.env, PEOPLE_KEY);
  if (kept && typeof kept === "object") {
    // Python kept Notion's choices for as long as the app ran; here an
    // hour, so a choice added in Notion is seen without a restart.
    const fresh = nowSec() - (Number(kept.options_at) || 0) < OPTIONS_EVERY;
    cx.people = { at: Number(kept.at) || 0, crew: kept.crew ?? null, shoots: kept.shoots ?? null,
      options: fresh ? (kept.options || {}) : {}, options_at: fresh ? Number(kept.options_at) || 0 : 0 };
  }
}

/**
 * One look at everything (or at one page, `only`) — `notionsync.tick`, and
 * with `dry` `notionsync.dry_run`. Never throws.
 *
 *   dry:   {decided, writes, trouble, requests}
 *   live:  {at, said, trouble, notify, requests}
 *
 * `state` ({link, story}) starts from those instead of the bucket's copies,
 * `templates` stands in for `s/record-templates.json`, and `writeFacts` for
 * facts.js's — all three for checks.
 */
export async function syncTick(env, { dry = false, only = null, state = null, templates = null, writeFacts = null } = {}) {
  const cx = { env, dry: Boolean(dry), writeFacts, DRY: [], said: [], notify: [], requests: 0, facts: new Map(),
    people: { at: 0, crew: null, shoots: null, options: {} }, peopleMoved: false, box: null };
  cx.notion = notionCaller(env, cx);
  if (only) only = bareId(only);
  let lease = null;
  let trouble = "";
  try {
    if (!cx.dry) {
      lease = await takeLease(env);
      if (!lease) return { at: nowIso(), said: [], trouble: "another look is still running", notify: [], requests: 0 };
    }
    await loadState(cx, state);
    if (cx.dry) cx.st.crew_at = 0;                    // dry_run: include the crew read
    cx.templates = templates !== null ? templates : ((await readJson(env, TEMPLATES_KEY)) || {});
    if (!cx.dry) await loadPeople(cx);
    trouble = await look(cx, only);
  } catch (e) {
    trouble = String((e && e.message) || e);
  } finally {
    if (!cx.dry) {
      try { await saveBox(cx); } catch (e) { trouble = trouble || `conflicts not kept: ${e && e.message}`; }
      try {
        if (cx.peopleMoved) await writeJson(cx, PEOPLE_KEY, cx.people);
      } catch { /* read again next look */ }
      if (lease) { try { await dropLease(env, lease); } catch { /* it times out */ } }
    }
  }
  if (cx.dry) {
    return { decided: cx.DRY.filter((d) => d.decided), writes: cx.DRY.filter((d) => !d.decided), trouble,
      requests: cx.requests };
  }
  return { at: nowIso(), said: cx.said, trouble, notify: cx.notify, requests: cx.requests };
}

/** notionsync.tick's body. Answers the trouble ("" when none). */
async function look(cx, only) {
  let recs;
  try {
    recs = await records(cx);
  } catch {
    return "the hub could not be reached";
  }
  for (const [page, r] of Object.entries(recs)) cx.facts.set(page, r.facts || {});
  try {
    const rows = await rowsOf(cx, "projects");
    let bot = cx.st.bot || "";
    if (!bot) {
      try {
        bot = (await cx.notion("users/me")).id || "";
        cx.st.bot = bot;
      } catch (e) {
        if (!(e instanceof NotionTrouble)) throw e;
      }
    }
    try { await keepNames(cx, rows); } catch { /* the names are only a shortcut; the next look keeps them */ }
    const ppl = await people(cx, Boolean(only));
    for (const row of rows) {
      const page = bareId(row.id || "");
      if (only && page !== only) continue;
      const name = L.plain((((row.properties || {}).Project) || {}).title) || page;
      if (!(page in recs)) {
        const story = await storyBefore(cx, page, name, row, {});
        await storyAfter(cx, page, name, row, {}, story, {});
        continue;
      }
      let facts = await factsOf(cx, page);
      if (facts === null) continue;
      facts = await migrate(cx, page, name, row, facts, ppl[0]);
      const story = await storyBefore(cx, page, name, row, facts);
      let words = L.notionWords(row);
      if (Object.keys(L.PROPERTIES).some((f) => words[f] === "")) words = L.notionWords(row, await headings(cx, page, row));
      const pushed = await one(cx, page, name, row, words, facts, bot, ppl);
      await storyAfter(cx, page, name, row, facts, story, pushed || {});
      await creditPeople(cx, page, name, row, facts, ppl[0], ppl[1]);
    }
    cx.said.push(...await shootEditsTick(cx, rows, recs, only));
    cx.said.push(...await waitingShootsTick(cx, rows, recs, only));
    // Notion parts kept while Notion was out of reach (a stage change's shoot row): done now it answers.
    if (!only) cx.said.push(...await flushWaits(cx.env, cx.notion, { dry: cx.dry }));
    if (!only && nowSec() - (Number(cx.st.crew_at) || 0) >= CREW_EVERY) {
      cx.said.push(...await crewTick(cx, rows, recs));
      cx.said.push(...await shootsTick(cx, rows, recs, null));
      cx.st.crew_at = nowSec();
    } else if (only) {
      cx.said.push(...await shootsTick(cx, rows, recs, only));
    }
    await save(cx);
    await storySave(cx);
    return "";
  } catch (e) {
    if (e instanceof NotionTrouble) return e.message;
    return String((e && e.message) || e);
  }
}

// ── settling a conflict he was shown (notionsync.settle, record.settle) ──────

/** Python's `repr()` of what was passed as `keep`, for the refusal's words. */
function pyRepr(v) {
  if (v === null || v === undefined) return "None";
  if (typeof v === "boolean") return v ? "True" : "False";
  if (typeof v === "number") return conflictStamp(v);
  if (typeof v !== "string") return String(v);
  const q = v.includes("'") && !v.includes("\"") ? "\"" : "'";
  const body = v.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t")
    .split(q).join(`\\${q}`);
  return `${q}${body}${q}`;
}

/** `met_at` as Python's f-string writes it: a float keeps its ".0", a
 * missing one is 0. The hub only ever writes fractional seconds
 * (`noteLinkConflict`), so the two sides always spell an id the same. */
function conflictStamp(v) {
  if (v === undefined || v === null || v === 0) return "0";
  if (typeof v !== "number") return String(v);
  return Number.isInteger(v) ? `${v}.0` : String(v);
}

/** record.outbox's id for one conflict: "<page>:<met_at>". */
const conflictId = (c) => `${c.page ?? ""}:${conflictStamp(c.met_at ?? 0)}`;

/** The conflicts he is shown, each with its `id` — record.outbox()'s
 * `conflicts` for the Notion link's kind. */
export async function conflictsList(env, { all = false } = {}) {
  const data = await readJson(env, CONFLICTS_KEY);
  const list = data && Array.isArray(data.conflicts) ? data.conflicts : [];
  const out = list.map((c) => ({ ...c, id: conflictId(c) }));
  if (all) return out;
  // **A deleted project's questions drop out** (2026-10-17): the record is
  // tombstoned (or was removed with a test project), so the question can
  // never be settled; it made the phone say "1 to settle" for ZZ Selects
  // Project. Kept in the file, so an Undo of the Delete brings them back.
  const alive = new Map();
  const kept = [];
  for (const c of out) {
    const page = bareId(c.page || "");
    if (!alive.has(page)) alive.set(page, await projectAlive(env, page));
    if (alive.get(page)) kept.push(c);
  }
  return kept;
}

/** Whether a Notion-link question's project still stands: a record, not deleted. */
async function projectAlive(env, page) {
  if (!/^[0-9a-f]{32}$/.test(page)) return true;
  try {
    const { resolveProject } = await import("./projectid.js");
    const got = await resolveProject(env, page);
    return Boolean(got.record) && !got.record.deleted;
  } catch {
    return true;
  }
}

/**
 * **Take a deleted project's questions off the list for good** — the
 * leftovers door (bigmoves.js) after a Delete. Answers the items taken, so
 * the caller keeps a copy. `dry` takes nothing.
 */
export async function dropDeadConflicts(env, { dry = true } = {}) {
  const every = await conflictsList(env, { all: true });
  const live = new Set((await conflictsList(env)).map((c) => c.id));
  const dead = every.filter((c) => !live.has(c.id));
  if (!dry) for (const c of dead) await dropConflict(env, c.id);
  return dead;
}

/** Take one conflict off the list by its id, compare-and-set. */
async function dropConflict(env, id) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const got = await env.BUCKET.get(CONFLICTS_KEY);
    if (!got) return;
    let data = null;
    try { data = await got.json(); } catch { data = null; }
    const list = data && Array.isArray(data.conflicts) ? data.conflicts : [];
    const kept = list.filter((c) => conflictId(c) !== id);
    if (kept.length === list.length) return;
    const put = await env.BUCKET.put(CONFLICTS_KEY, JSON.stringify({ ...data, conflicts: kept }, null, 1),
      { httpMetadata: { contentType: "application/json" }, onlyIf: { etagMatches: got.etag } });
    if (put) return;
  }
  throw new Error("the conflicts list kept changing");
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * He picked — `notionsync.settle`. `keep: "notion"` puts Notion's words (as
 * he saw them, `words`) in the record; `keep: "record"` writes the record's
 * value into Notion. The record moved again while he decided → {moved};
 * a value Notion cannot take → {trouble} in his words, nothing changed;
 * else {settled}. Takes the same lease as a look (waits a few seconds for
 * one that is running, then answers busy).
 */
export async function syncSettle(env, { page, field, keep, words, v } = {}, overrides = {}) {
  page = bareId(page);
  let lease = null;
  for (let i = 0; i < 4 && !lease; i++) {
    lease = await takeLease(env);
    if (!lease && i < 3) await sleep(overrides.waitMs ?? 1000);
  }
  if (!lease) return { trouble: "busy — try again" };
  const cx = { env, dry: false, writeFacts: overrides.writeFacts || null, DRY: [], said: [], notify: [], requests: 0,
    facts: new Map(), people: { at: 0, crew: null, shoots: null, options: {} }, peopleMoved: false, box: null };
  cx.notion = notionCaller(env, cx);
  try {
    await loadState(cx, null);
    await loadPeople(cx);
    const ps = pageState(cx.st, page);
    const r = await readJson(env, `r/${page}/record.json`);       // the hub's facts door answers {} for no record
    const facts = (r && r.facts) || {};
    cx.facts.set(page, facts);
    const fact = truthy(facts[field]) ? facts[field] : {};
    if (int(fact.v) !== int(v)) return { moved: true };
    if (keep === "notion") {
      const got = await writeRecord(cx, page, field, words, fact, facts);
      if ("conflicts" in got) return { moved: true };
      if (got.trouble) return { trouble: got.trouble };
      const fresh = ((got.facts || {})[field]) || {};
      ps.bases[field] = baseOf(fresh.v, field, words, "");
      await save(cx);
      return { settled: true };
    }
    if (keep === "record") {
      try {
        await push(cx, page, field, valueOf(fact), ps, int(fact.v));
      } catch (e) {
        if (e instanceof Refused || e instanceof NotionTrouble) return { trouble: e.message };
        throw e;
      }
      return { settled: true };
    }
    return { trouble: `keep Notion's or the record's, not ${pyRepr(keep)}` };
  } finally {
    try { if (cx.peopleMoved) await writeJson(cx, PEOPLE_KEY, cx.people); } catch { /* read again next look */ }
    try { await dropLease(env, lease); } catch { /* it times out */ }
  }
}

/**
 * Settle one conflict from the list — `record.settle` for a Notion-link
 * item, via `_settle_link`. `keep: "mine"` keeps Notion's words (the item's
 * `changes` side), `"theirs"` the record's. Answers {settled: true},
 * {conflicts: {field: null}} when the record moved meanwhile (the item goes
 * and a one-page look shows the newest — `overrides.waitUntil`, when given,
 * is handed that look instead of it being awaited), or {trouble} and the
 * item stays.
 */
export async function settleConflict(env, id, keep, overrides = {}) {
  const item = (await conflictsList(env)).find((c) => c.id === id);
  if (!item) return { trouble: "that change was already settled" };
  if (keep !== "mine" && keep !== "theirs") return { trouble: `keep mine or theirs, not ${pyRepr(keep)}` };
  const [field, [words, v]] = Object.entries(item.changes || {})[0];
  const got = await syncSettle(env, { page: item.page, field, keep: keep === "mine" ? "notion" : "record", words, v }, overrides);
  if (got.trouble) return got;
  await dropConflict(env, id);
  if (got.moved) {
    // the record moved again while he decided: the next look shows the newest (kick)
    const look = syncTick(env, { only: item.page, writeFacts: overrides.writeFacts || null,
      templates: overrides.templates ?? null });
    if (overrides.waitUntil) overrides.waitUntil(look);
    else await look;
    return { conflicts: { [field]: null } };
  }
  return { settled: true };
}
