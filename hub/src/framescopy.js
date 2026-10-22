/**
 * **Notion's Frame Guides, a one-way copy of the sheet's frames** (stage 5
 * step 5, 2026-10-15). The frames live on the record's spec sheet
 * (specsheet.js: name, ratio, one Main); the Camera
 * Spec Sheets row's `Frame Guides` pills are written from them, never read
 * back. Main first, then the others in order, each ratio once.
 *
 * Only a sheet that keeps its own frames is copied (a sheet with none shows
 * defaults drawn from those very pills, so copying them would go round in a
 * circle), and only to the Notion row the sheet names.
 *
 * **Behind its own switch, `framescopy`** (`s/framescopy.json`), off until
 * thrown; the look writes nothing, switch or no switch.
 *
 *   GET  /console/studio/framescopy        {on, at, by}
 *   PUT  /console/studio/framescopy        {on, by}
 *   POST /console/studio/framescopy/look   {only?} — every sheet: the pills it would write, what Notion has
 *   POST /console/studio/framescopy/run    {only?} — the same, written where they differ (switch on)
 */

import { recordSheets } from "./specsheet.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/framescopy.json";
export const COLUMN = "Frame Guides";
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const PAGE = /^[0-9a-f]{32}$/;

/** The Frame Guides pills a frames list stands for: Main's ratio first, each ratio once, none empty. */
export function frameGuidesOf(frames) {
  const list = Array.isArray(frames) ? frames.filter(isObject) : [];
  const ordered = [...list.filter((f) => f.main === true), ...list.filter((f) => f.main !== true)];
  const out = [];
  for (const f of ordered) {
    const r = String(f.ratio || "").trim();
    if (r && !out.includes(r)) out.push(r);
  }
  return out;
}

/** What one sheet's row would be given: {page, guides, properties} or {skip}. */
export function copyPlan(sheet) {
  if (!isObject(sheet) || !Array.isArray(sheet.frames) || !sheet.frames.length) return { skip: "keeps no frames of its own" };
  const page = String(sheet.notion || "").replace(/-/g, "");
  if (!PAGE.test(page)) return { skip: "names no Notion row" };
  const guides = frameGuidesOf(sheet.frames);
  return { page, guides, properties: { [COLUMN]: { multi_select: guides.map((name) => ({ name })) } } };
}

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

export async function copyOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setCopySwitch(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

async function recordKeys(env) {
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const k = p.split("/")[1];
      if (PAGE.test(k)) keys.push(k);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return keys;
}

const pillsOf = (row) => ((((row || {}).properties || {})[COLUMN] || {}).multi_select || []).map((o) => o.name || "");

/**
 * Every sheet's copy: `notion(method, path, body)` reaches Notion. `write`
 * false reads Notion and writes nothing. Answers {dry, rows, would, wrote}.
 */
export async function framesCopy(env, notion, { write = false, only = "" } = {}) {
  const rows = [];
  for (const key of await recordKeys(env)) {
    if (only && key !== only) continue;
    const record = await readJson(env, `r/${key}/record.json`);
    if (!isObject(record)) continue;
    for (const [fact, one] of Object.entries(recordSheets(record.facts))) {
      const plan = copyPlan(one.sheet);
      const row = { id: key, name: String(record.name || ""), fact };
      if (plan.skip) { rows.push({ ...row, skip: plan.skip }); continue; }
      let have = null;
      try { have = pillsOf(await notion("GET", `pages/${plan.page}`)); } catch (e) {
        rows.push({ ...row, page: plan.page, guides: plan.guides, trouble: String((e && e.message) || e).slice(0, 200) });
        continue;
      }
      const differs = JSON.stringify(have) !== JSON.stringify(plan.guides);
      const out = { ...row, page: plan.page, guides: plan.guides, notion: have, differs };
      if (differs && write) {
        try { await notion("PATCH", `pages/${plan.page}`, { properties: plan.properties }); out.wrote = true; } catch (e) {
          out.wrote = false; out.trouble = String((e && e.message) || e).slice(0, 200);
        }
      }
      rows.push(out);
    }
  }
  return { dry: !write, rows, would: rows.filter((r) => r.differs).length, wrote: rows.filter((r) => r.wrote).length };
}

export async function copyDoor(env, rest, method, read, notion) {
  if (rest[0] !== "framescopy") return null;
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  const body = async () => { try { const v = await read(); return isObject(v) ? v : {}; } catch { return null; } };
  if (rest.length === 1) {
    if (method === "GET") return reply(await copyOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    return reply(await setCopySwitch(env, said));
  }
  if (rest.length !== 2 || !["look", "run"].includes(rest[1])) return reply({ ok: false, problem: "No such door." }, 404);
  if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
  const said = await body();
  if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
  if (!notion) return reply({ ok: false, problem: "The hub has no Notion key." }, 503);
  if (rest[1] === "run" && !(await copyOn(env)).on) return reply({ ok: false, problem: "The frames copy is switched off." }, 409);
  const only = String(said.only || "").replace(/-/g, "").slice(0, 64);
  return reply({ ok: true, ...(await framesCopy(env, notion, { write: rest[1] === "run", only })) });
}

/**
 * The clock's turn (worker.js, every two minutes, but only about one tick in
 * five does the work): when the `framescopy` switch is on, every sheet's Frame
 * Guides are made to match its frames. Off, it reads one key and stops.
 */
export async function sweep(env, now = Date.now()) {
  if (!(await copyOn(env)).on) return { skipped: "off" };
  if (Math.floor(now / 120000) % 5 !== 0) return { skipped: "not this tick" };
  const { cloudReady } = await import("./cloud.js");
  if (!cloudReady(env)) return { skipped: "no Notion" };
  const { notionClient } = await import("./newprojectdoor.js");
  return framesCopy(env, notionClient(env), { write: true });
}
