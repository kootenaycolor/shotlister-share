/**
 * **Notion waits** (2026-10-19, "error 401" on Daybreak's Post). The project's
 * record is the master; Notion is kept in step. So a stage change that has a
 * Notion part (a Shoots row marked Wrapped) must never fail because Notion is
 * out of reach: the record's part is done, and the Notion part is kept here,
 * in the bucket, and done by the minute's look (`notionsync.js`) the first
 * time Notion answers again.
 *
 *     s/notion-waits.json   { items: [ { id, kind, project, page, shoot,
 *                                         status, label, at, by, tries } ] }
 *
 * Only `shoot-status` is kept for a project that has a record: its Status and
 * Shoot Dates follow from the record through the Notion link on their own.
 * (`project-status` and `project-dates` are for a project with no record,
 * where nothing else would carry them.)
 *
 * `QUIET` is the one line he is shown. A raw "error 401" never is.
 */

import { canonStage, shownStage } from "./stageword.js";

export const WAITS_KEY = "s/notion-waits.json";
export const QUIET = "Notion waits: not connected";
/** Real refusals (not "Notion is out of reach") before a part is let go. */
export const MAX_TRIES = 20;

const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

/** Whether this failure is "Notion is out of reach" (no key, a refused key, no
 * connection, Notion itself down), as opposed to Notion refusing a request. */
export function notionDown(e) {
  if (!e) return false;
  if (e && e.constructor && e.constructor.name === "Handoff") return true;   // cloud.js's (not imported: it imports the moves)
  if (e instanceof TypeError) return true;               // fetch failed: no connection
  const m = String((e && e.message) || e);
  return /^Notion: (unauthorized|restricted_resource|service_unavailable|gateway_timeout|bad_gateway|internal_server_error)\b/.test(m)
    || /^Notion did not answer/.test(m)
    || /^Notion answered (401|403|5\d\d)\b/.test(m);
}

/** Any raw Notion failure in his words: the quiet line when Notion is out of reach. */
export function notionWords(e) {
  return notionDown(e) ? QUIET : "";
}

async function read(env) {
  const got = await env.BUCKET.get(WAITS_KEY);
  if (!got) return { etag: null, data: { items: [] } };
  let data = null;
  try { data = await got.json(); } catch { data = null; }
  if (!data || !Array.isArray(data.items)) data = { items: [] };
  return { etag: got.etag, data };
}

async function change(env, fn) {
  for (let i = 0; i < 5; i++) {
    const { etag, data } = await read(env);
    const next = fn(data);
    if (!next) return data;
    const opts = { httpMetadata: { contentType: "application/json" } };
    if (etag) opts.onlyIf = { etagMatches: etag };
    const ok = await env.BUCKET.put(WAITS_KEY, JSON.stringify(next, null, 1), opts);
    if (ok) return next;
  }
  throw new Error("Notion's waiting list kept changing while it was written.");
}

export async function waitsList(env) {
  return (await read(env)).data.items;
}

/** What is waiting for one project (by any id it has). */
export async function waitsFor(env, ...ids) {
  const want = new Set(ids.map(bare).filter(Boolean));
  return (await waitsList(env)).filter((x) => want.has(bare(x.project)) || want.has(bare(x.page)));
}

function idOf() {
  const a = new Uint8Array(6);
  crypto.getRandomValues(a);
  return `nw-${[...a].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

/** Keep one Notion part to do later. The same part twice is kept once.
 * Answers the item's id. */
export async function addWait(env, item) {
  let id = "";
  await change(env, (data) => {
    const same = data.items.find((x) => x.kind === item.kind && bare(x.shoot || x.page) === bare(item.shoot || item.page)
      && (item.kind !== "crew-edit" || bare(x.page) === bare(item.page)));
    if (same) {
      id = same.id;
      const changes = item.kind === "crew-edit" ? crewMerge(same.changes || {}, item.changes || {}) : same.changes;
      return { ...data, items: data.items.map((x) => (x.id === same.id ? { ...x, status: item.status, ...(changes ? { changes } : {}) } : x)) };
    }
    id = idOf();
    return { ...data, items: [...data.items, { tries: 0, ...item, id, at: item.at || new Date().toISOString() }] };
  });
  return id;
}

/** Two waiting edits of one person on one project as one: the later on/off
 * wins; a shoot added then removed (or the other way) ends as the later. */
export function crewMerge(was, now) {
  const nowAdd = now.add_shoots || [], nowRem = now.remove_shoots || [];
  const add = (was.add_shoots || []).filter((s) => !nowRem.includes(s));
  const rem = (was.remove_shoots || []).filter((s) => !nowAdd.includes(s));
  for (const s of nowAdd) if (!add.includes(s)) add.push(s);
  for (const s of nowRem) if (!rem.includes(s)) rem.push(s);
  return { on_project: now.on_project != null ? now.on_project : (was.on_project != null ? was.on_project : null), add_shoots: add, remove_shoots: rem };
}

/** The project a waiting part belongs to. */
export const projectOf = (w) => bare(w.project || w.page || w.shoot || w.id);
/** The line a part says when it waits behind an earlier one for its project. */
export const BEHIND = "waits for the change before it";

/** Take parts off the list (done, or undone before they were). Answers the ids
 * that really were still waiting. */
export async function dropWaits(env, ids) {
  const want = new Set(ids || []);
  const had = [];
  if (!want.size) return had;
  await change(env, (data) => {
    for (const x of data.items) if (want.has(x.id)) had.push(x.id);
    if (!had.length) return null;
    return { ...data, items: data.items.filter((x) => !want.has(x.id)) };
  });
  return had;
}

const BODY = {
  "shoot-status": (w) => ({ properties: { Status: { select: { name: w.status } } } }),
  "project-status": (w) => ({ properties: { Status: { select: { name: canonStage(w.status) } } } }),
  // a Project Docs row's Hub box (cloud.js documentOnPortal)
  "doc-hub": (w) => ({ properties: { Hub: { checkbox: w.status === "on" } } }),
  // a person on a project and its shoots: planned against the Crew row when Notion answers (cloud.js crewPlan)
  "crew-edit": () => null,
  "project-dates": (w) => ({ properties: { "Shoot Dates": { date: w.start ? (w.end && w.end !== w.start ? { start: w.start, end: w.end } : { start: w.start }) : null } } }),
  // a Rename's Notion title, kept while Notion was out of reach (bigmoves.js)
  "project-title": (w) => ({ properties: { [w.prop || "Project"]: { title: [{ text: { content: w.status } }] } } }),
};
const TARGET = (w) => (w.kind === "shoot-status" || w.kind === "crew-edit" ? w.shoot : w.page);

/**
 * The minute's look, when Notion answered: do each waiting part, once. A part
 * Notion already has (the same Status) is simply let go. Notion out of reach
 * costs it nothing. Notion refusing the request keeps it, up to 20 refusals,
 * then lets it go and says so. A page
 * Notion no longer has (404) is let go.
 * `notion(path, method, body)` is the look's caller (it throws on trouble).
 */
export async function flushWaits(env, notion, { dry = false } = {}) {
  const said = [];
  const items = await waitsList(env);
  if (!items.length || dry) return said;
  const done = [];
  const tried = new Map();
  // In order, per project (2026-10-20, his #9): a part that didn't go holds
  // back every later part for its project, so they never land out of order.
  const stuck = new Set(), refused = new Set(), behind = new Map();
  for (const w of items) {
    const body = BODY[w.kind];
    if (!body) { done.push(w.id); continue; }
    const target = TARGET(w);
    const label = w.label || "A shoot";
    const here = projectOf(w);
    if (stuck.has(here)) { if (refused.has(here)) behind.set(here, label); continue; }
    try {
      if (w.kind === "crew-edit") {
        const { crewPlan } = await import("./cloud.js");
        const n = { get: (p) => notion(p), patch: (p, b) => notion(p, "PATCH", b), post: (p, b) => notion(p, "POST", b) };
        const crew = await notion(`pages/${w.shoot}`);
        const props = await crewPlan(n, crew, w.page, w.changes || {});
        if (Object.keys(props).length) {
          await notion(`pages/${w.shoot}`, "PATCH", { properties: props });
          if (Object.keys(await crewPlan(n, await notion(`pages/${w.shoot}`), w.page, w.changes || {})).length) throw new Error("Notion did not keep the change");
        }
      } else if (w.kind === "project-dates" || w.kind === "project-title" || w.kind === "doc-hub") {
        await notion(`pages/${target}`, "PATCH", body(w));
      } else {
        const now = await notion(`pages/${target}`);
        const have = (((now.properties || {}).Status || {}).select || {}).name || "";
        if (canonStage(have) !== canonStage(w.status)) await notion(`pages/${target}`, "PATCH", body(w));
      }
      done.push(w.id);
      said.push(w.kind === "project-title" ? `${w.status} · name in Notion, kept from earlier`
        : w.kind === "crew-edit" ? `${label} · crew in Notion, kept from earlier`
          : w.kind === "doc-hub" ? `${label} · document in Notion, kept from earlier`
            : `${label} · ${shownStage(w.status) || "dates"} in Notion, kept from earlier`);
    } catch (e) {
      const why = String((e && e.message) || e);
      if (/\b404\b|object_not_found/.test(why)) { done.push(w.id); said.push(`${label} · gone from Notion, nothing to mark`); continue; }
      stuck.add(here);
      // Notion out of reach (a refused key, no connection, Notion down) costs
      // a part nothing, however long it lasts: only a real refusal counts
      if (notionDown(e)) continue;
      refused.add(here);
      const tries = (Number(w.tries) || 0) + 1;
      if (tries >= MAX_TRIES) { done.push(w.id); said.push(`${label} · ${shownStage(w.status) || "dates"} not in Notion: Notion refused it`); } else tried.set(w.id, tries);
    }
  }
  for (const label of behind.values()) said.push(`${label} · ${BEHIND}`);
  if (done.length || tried.size) {
    await change(env, (data) => ({ ...data, items: data.items.filter((x) => !done.includes(x.id)).map((x) => (tried.has(x.id) ? { ...x, tries: tried.get(x.id) } : x)) }));
  }
  return said;
}
