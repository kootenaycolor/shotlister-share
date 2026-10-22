/**
 * **Modes, one switch everywhere** (stage 5 step 4, piece B, 2026-10-14).
 *
 * A project's Studio has five modes: Shot List, Locations, References,
 * Schedule, Diagram. Each project switches on only the ones it needs (his
 * answers 9, 11-14). Off means hidden, never deleted.
 *
 * **Kept like the layout** (cloudlayout.js): the record's `modes` fact holds
 * only where this project differs from its Type's standard,
 * `{shot_list: true, diagram: false}`; the card carries the resolved list.
 *
 *   Narrative                      all five
 *   Commercial, Music Video        Shot List, References, Schedule
 *   Personal                       Shot List, References
 *   a Job, whatever its Type       none
 *   no Type yet                    all five (nothing is hidden by not knowing)
 *
 * **The rules between them:** Schedule arranges the shot list's scenes, so
 * Schedule on brings Shot List on, and Shot List off takes Schedule with it
 * (the asker is offered both: without `both` the server refuses and says so).
 *
 * **The Studio side is made the first time a mode goes on** (`ensureStudioSide`,
 * step 2's door), before the mode is written: a project with no modes never
 * gets an empty film.
 *
 *   GET  /console/studio/studiomodes        the switch {on, at, by}; off until thrown
 *   PUT  /console/studio/studiomodes        {on, by}
 *   GET  /console/studio/modes/<id>         {ok, id, type, job, modes, set, standard}
 *   POST /console/studio/modes/<id>         {mode, on, both?, by, dry?} — one mode on or off
 *   POST /console/studio/modes/look         {dry: true, only?} — every project's modes against
 *                                           what its Studio side holds; {dry: false} keeps on
 *                                           (in its `modes` fact) any mode a project already uses
 *
 * While the switch is off, Studio and the phone show every mode, as before,
 * and the set door refuses; the card still carries the list, and the look and
 * the read answer either way.
 */

import { resolveProject, studioOf, bare, ID } from "./projectid.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/studio-modes.json";
export const LAST_LOOK_KEY = "s/studio-modes-look.json";
export const MODES = ["shot_list", "locations", "references", "schedule", "diagram"];
export const TITLES = { shot_list: "Shot List", locations: "Locations", references: "References", schedule: "Schedule", diagram: "Diagram" };
const STANDARD = {
  Narrative: [...MODES],
  Commercial: ["shot_list", "references", "schedule"],
  "Music Video": ["shot_list", "references", "schedule"],
  Personal: ["shot_list", "references"],
};

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function modesOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setModesSwitch(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── the rules ────────────────────────────────────────────────────────────────

/** The Type as the standards name it, or "" when unknown. */
export function typeKey(type) {
  const t = String(type || "").trim().replace(/\s+/g, " ").toLowerCase();
  return Object.keys(STANDARD).find((k) => k.toLowerCase() === t) || "";
}

/** The Type's starting set; a Job starts with none (his answer 11). */
export function standardOf(type, job = false) {
  if (job) return [];
  const k = typeKey(type);
  if (k && SAVED[k]) return [...SAVED[k]];
  // One rule, server and Mac (2026-10-15): a Music Video with no standard of
  // its own starts as his Commercial does.
  if (k === "Music Video" && !SAVED_TYPES.has(k)) return standardOf("Commercial");
  return k ? [...STANDARD[k]] : [...MODES];
}

// His own starting sets (Settings › New Projects), kept with his record
// standards: the one source. Read at the start of each ask (`loadStandards`),
// so the sync functions above stay sync. Empty until read, then ours stand.
let SAVED = {};
let SAVED_TYPES = new Set();   // every Type he saved a standard for, modes or not
let SAVED_AT = 0;
export async function loadStandards(env) {
  if (Date.now() - SAVED_AT < 5000) return SAVED;
  try {
    const { savedTemplates } = await import("./cloudlayout.js");
    const saved = await savedTemplates(env);
    const next = {};
    const types = new Set();
    for (const [t, v] of Object.entries(saved)) {
      const k = typeKey(t);
      if (k) types.add(k);
      // tidied as the Mac's recordlayout._tidy_template does: known modes, in
      // order, Schedule bringing Shot List
      if (k && Array.isArray(v.modes)) {
        const have = new Set(v.modes.filter((m) => MODES.includes(m)));
        if (have.has("schedule")) have.add("shot_list");
        next[k] = MODES.filter((m) => have.has(m));
      }
    }
    SAVED = next;
    SAVED_TYPES = types;
    SAVED_AT = Date.now();
  } catch { /* keep what was read */ }
  return SAVED;
}
export function forgetStandards() { SAVED = {}; SAVED_TYPES = new Set(); SAVED_AT = 0; }

const factValue = (facts, k) => {
  const one = (facts || {})[k];
  return isObject(one) ? one.value : undefined;
};

/** The project's own changes, tidy: only known modes, only booleans. */
export function explicitOf(facts) {
  const raw = factValue(facts, "modes");
  const out = {};
  if (isObject(raw)) for (const m of MODES) if (typeof raw[m] === "boolean") out[m] = raw[m];
  return out;
}

/**
 * Whether a record is a Job (no Notion Projects row, every mode off). A Job's
 * record says `kind: "job"` (onelist.js reads the same). `job: true` is the
 * older spelling the checks use. NOT any other `job`: the Mac's record carries
 * `job: {…}` for a long-running drive move (jobs.py), and a project in the
 * middle of one is not a Job.
 */
export function isJob(record) {
  return Boolean(record) && (record.kind === "job" || record.job === true);
}

export function typeOfRecord(record) {
  const facts = isObject(record && record.facts) ? record.facts : {};
  const typed = factValue(facts, "type");
  return typeof typed === "string" && typed.trim() ? typed.trim() : String((record && record.type) || "");
}

/**
 * The modes a project has on, in Studio's order. A Schedule left on beside a
 * Shot List turned off (written by hand, or by an older rule) keeps the Shot
 * List showing: a mode in use is never hidden by the rule between them.
 */
export function resolveModes(record) {
  const type = typeOfRecord(record);
  const job = isJob(record);
  const standard = standardOf(type, job);
  const set = explicitOf(record && record.facts);
  const on = new Set(MODES.filter((m) => (m in set ? set[m] : standard.includes(m))));
  if (on.has("schedule")) on.add("shot_list");
  return { type, job, standard, set, modes: MODES.filter((m) => on.has(m)) };
}

/** What the `modes` fact becomes for the wanted set: only where it differs from the standard. */
export function modesValue(standard, wanted) {
  const out = {};
  for (const m of MODES) {
    const want = wanted.includes(m);
    if (want !== standard.includes(m)) out[m] = want;
  }
  return out;
}

/**
 * One mode on or off, with the rules between them. Answers
 * `{ok, modes, also}` (also: the other mode the rule moved) or
 * `{ok: false, why, needs?}`.
 */
export function modesAfter(now, mode, on, both = false) {
  if (!MODES.includes(mode)) return { ok: false, why: "No such mode." };
  const next = new Set(now);
  const also = [];
  if (on) {
    next.add(mode);
    if (mode === "schedule" && !now.includes("shot_list")) { next.add("shot_list"); also.push("shot_list"); }
  } else {
    if (mode === "shot_list" && now.includes("schedule")) {
      if (!both) return { ok: false, needs: "both", why: "Schedule goes off with Shot List." };
      next.delete("schedule");
      also.push("schedule");
    }
    next.delete(mode);
  }
  return { ok: true, modes: MODES.filter((m) => next.has(m)), also };
}

// ── reading and setting ──────────────────────────────────────────────────────

export async function readModes(env, id) {
  await loadStandards(env);
  const found = await resolveProject(env, id);
  if (!found.key || !isObject(found.record)) return { ok: false, status: 404, why: "No project with that ID." };
  const r = resolveModes(found.record);
  return { ok: true, id: found.key, relay: studioOf(found.record), ...r };
}

/**
 * Turn one mode on or off for a project: `{mode, on, both?, by, dry?}`.
 * Turning one on for a project with no Studio side makes it first (step 2's
 * door); a refusal there writes nothing. `deps.ensureSide` and
 * `deps.writeFacts` stand in for the checks.
 */
export async function setMode(env, id, said, deps = {}) {
  await loadStandards(env);
  const s = isObject(said) ? said : {};
  const mode = String(s.mode || "");
  const on = s.on === true;
  if (!MODES.includes(mode)) return { ok: false, status: 400, why: "Say which mode." };
  if (typeof s.on !== "boolean") return { ok: false, status: 400, why: "Say on or off." };
  const by = String(s.by || "").slice(0, 80) || "server";
  if (s.dry !== true && !(await modesOn(env)).on) return { ok: false, status: 409, why: "Modes are switched off on the server." };
  const write = deps.writeFacts || (async (page, changes, who) => (await import("./facts.js")).writeFacts(env, page, changes, who));
  for (let attempt = 0; attempt < 3; attempt++) {
    const found = await resolveProject(env, id);
    if (!found.key || !isObject(found.record)) return { ok: false, status: 404, why: "No project with that ID." };
    const now = resolveModes(found.record);
    const got = modesAfter(now.modes, mode, on, s.both === true);
    if (!got.ok) return { ...got, id: found.key, modes: now.modes };
    const value = modesValue(now.standard, got.modes);
    const have = (found.record.facts || {}).modes;
    const same = JSON.stringify(explicitOf(found.record.facts)) === JSON.stringify(value) && got.modes.join() === now.modes.join();
    let side = null;
    const needsSide = got.modes.length > 0 && !studioOf(found.record);
    if (s.dry === true) return { ok: true, dry: true, id: found.key, modes: got.modes, also: got.also, would: value, side: needsSide ? "would be made" : null };
    if (same) return { ok: true, id: found.key, modes: got.modes, also: got.also, unchanged: true };
    if (needsSide) {
      const ensure = deps.ensureSide || (async (key) => (await import("./studioside.js")).ensureStudioSide(env, key, { by }));
      side = await ensure(found.key);
      if (!side || side.ok !== true) return { ok: false, status: 200, id: found.key, modes: now.modes, why: (side && side.why) || "The Studio side could not be made." };
    }
    const wrote = await write(found.key, { modes: { value, base: isObject(have) ? Number(have.v) || 0 : 0 } }, by);
    if (wrote && wrote.status === 409) continue; // moved on in between: read again
    if (!wrote || wrote.status !== 200) return { ok: false, status: 500, id: found.key, why: (wrote && wrote.problem) || "The modes could not be written." };
    return { ok: true, id: found.key, modes: got.modes, also: got.also, ...(side ? { side: { relay: side.relay, made: side.made } } : {}) };
  }
  return { ok: false, status: 409, why: "The project kept changing. Try again." };
}

// ── the look ─────────────────────────────────────────────────────────────────

/** Which modes a film holds anything in, from the engine's view (counts). */
export function usedModes(use) {
  const u = isObject(use) ? use : {};
  const out = [];
  if ((u.scenes || 0) > 0 || (u.scripts || 0) > 0) out.push("shot_list");
  if ((u.locations || 0) > 0) out.push("locations");
  if ((u.boards || 0) > 0) out.push("references");
  if ((u.days || 0) > 0) out.push("schedule");
  if ((u.diagrams || 0) > 0) out.push("diagram");
  return out;
}

async function recordKeys(env) {
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const k = p.split("/")[1];
      if (ID.test(k)) keys.push(k);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return keys;
}

/**
 * **Every project's starting modes against what its Studio side holds today.**
 * A mode a film already uses that its starting set would hide is a `hides`
 * row; `keep` is the `modes` value that keeps it on. `readUse(env, relay, ctx)`
 * answers the film's counts. `{dry: false}` writes the `keep` values (only
 * where something would be hidden), so no mode a project uses disappears when
 * the switch goes on.
 */
export async function modesLook(env, ctx, readUse, { dry = true, only = "", by = "server", deps = {} } = {}) {
  await loadStandards(env);
  const want = bare(only);
  const rows = [];
  for (const key of await recordKeys(env)) {
    if (want && key !== want) continue;
    const record = await readJson(env, `r/${key}/record.json`);
    if (!isObject(record)) continue;
    const r = resolveModes(record);
    const relay = studioOf(record);
    const row = { id: key, name: String(record.name || ""), type: r.type, job: r.job, modes: r.modes, set: r.set };
    if (!relay) { rows.push({ ...row, film: false }); continue; }
    let use;
    try { use = await readUse(env, relay, ctx); } catch (e) {
      rows.push({ ...row, relay, trouble: String((e && e.message) || e).slice(0, 200) });
      continue;
    }
    const used = usedModes(use);
    const hides = used.filter((m) => !r.modes.includes(m));
    const out = { ...row, relay, use, used, hides };
    if (hides.length) {
      const kept = MODES.filter((m) => r.modes.includes(m) || used.includes(m));
      out.keep = modesValue(r.standard, kept);
      if (!dry) {
        const write = deps.writeFacts || (async (page, changes, who) => (await import("./facts.js")).writeFacts(env, page, changes, who));
        const have = (record.facts || {}).modes;
        const wrote = await write(key, { modes: { value: out.keep, base: isObject(have) ? Number(have.v) || 0 : 0 } }, by);
        out.wrote = wrote && wrote.status === 200 ? true : String((wrote && (wrote.problem || wrote.status)) || "not written");
      }
    }
    rows.push(out);
  }
  const answer = {
    at: new Date().toISOString(), dry, projects: rows.length, films: rows.filter((r) => r.relay).length,
    hiding: rows.filter((r) => r.hides && r.hides.length).length, rows,
  };
  if (!dry) await env.BUCKET.put(LAST_LOOK_KEY, JSON.stringify(answer), { httpMetadata: { contentType: "application/json" } });
  return answer;
}

// ── the door ─────────────────────────────────────────────────────────────────

export async function modesDoor(env, rest, method, read, ctx, { readUse } = {}) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  const body = async () => { try { const v = await read(); return isObject(v) ? v : {}; } catch { return null; } };
  if (rest[0] === "studiomodes" && rest.length === 1) {
    if (method === "GET") return reply(await modesOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    return reply(await setModesSwitch(env, said));
  }
  if (rest[0] !== "modes" || rest.length !== 2) return null;
  if (rest[1] === "look") {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    const said = await body();
    if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
    const reader = readUse || (await import("./studiocardsfilm.js")).filmUse;
    return reply(await modesLook(env, ctx, reader, { dry: said.dry !== false, only: String(said.only || "").slice(0, 64), by: String(said.by || "server").slice(0, 80) }));
  }
  if (method === "GET") {
    const got = await readModes(env, rest[1]);
    return reply(got, got.status || 200);
  }
  if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
  const said = await body();
  if (!said) return reply({ ok: false, problem: "That is not JSON." }, 400);
  try {
    const got = await setMode(env, rest[1], said);
    return reply(got, got.status || 200);
  } catch (e) {
    return reply({ ok: false, why: String((e && e.message) || e).slice(0, 300) }, 500);
  }
}
