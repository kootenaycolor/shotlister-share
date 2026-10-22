/**
 * **A project's modes as two asks** (stage 5 step 5, 2026-10-15): the
 * console's Systems card and New Project, on the Mac and the iPhone, read and
 * switch the five Studio modes through the asks door, like every other
 * console call. Thin wrappers over studiomodes.js — the rules, the switch and
 * the lazy Studio side are all its; nothing is decided here.
 *
 *   project_modes(id)
 *     → {ok, id, type, job, switch, modes:{shot_list, locations, references, schedule, diagram: bool},
 *        standard:{same keys}, tiles:{same keys: "142 shots" | ""}}
 *   set_project_mode(id, mode, on, both)
 *     → {ok, modes:{…}, also?} | {ok:false, needs:"both", error} | {ok:false, error}
 *
 * `id` is any of the project's ids (its key, its Notion page, its film's).
 * `set_project_mode` obeys the `studiomodes` switch: refused in its words
 * while it is off. `tiles` say only what the server can count cheaply — the
 * record's film counts, else one read of the film by the engine; "" when it
 * does not know, never a guess.
 */

import { MODES, readModes, setMode, modesOn, loadStandards } from "./studiomodes.js";
import { resolveMods, setMod, shelf, MOD_KEYS } from "./studiomods.js";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

/** A list of modes as the contract's `{key: bool}`. */
export function asFlags(list) {
  const on = new Set(list || []);
  const out = {};
  for (const m of MODES) out[m] = on.has(m);
  return out;
}

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const count = (x) => (typeof x === "number" && Number.isFinite(x) && x > 0 ? Math.floor(x) : 0);

/**
 * Each mode's short line, from what is known: `film` is the record's film
 * (the Mac's published counts: shots, scenes, days, boards), `use` the
 * engine's count of the film (studiocardsfilm.filmUse) or null. A count of
 * nothing, or not known, is "".
 */
export function tilesOf(film, use) {
  const f = isObject(film) ? film : {};
  const u = isObject(use) ? use : {};
  const shots = count(f.shots);
  const scenes = count(u.scenes) || count(f.scenes);
  const pick = (a, b) => count(a) || count(b);
  const out = {
    shot_list: shots ? plural(shots, "shot", "shots") : scenes ? plural(scenes, "scene", "scenes") : "",
    locations: count(u.locations) ? plural(count(u.locations), "place", "places") : "",
    references: pick(u.boards, f.boards) ? plural(pick(u.boards, f.boards), "board", "boards") : "",
    schedule: pick(u.days, f.days) ? plural(pick(u.days, f.days), "day", "days") : "",
    diagram: count(u.diagrams) ? plural(count(u.diagrams), "plan", "plans") : "",
  };
  return out;
}

async function recordOf(env, key) {
  const got = await env.BUCKET.get(`r/${key}/record.json`);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

/** The ask `project_modes(id)`. `deps.readUse(env, relay, ctx)` stands in for the engine's read. */
export async function projectModes(env, [id] = [], deps = {}) {
  await loadStandards(env);
  const got = await readModes(env, String(id || ""));
  if (!got.ok) return { ok: false, error: got.why };
  const sw = await modesOn(env);
  let use = null;
  const record = await recordOf(env, got.id);
  if (got.relay) {
    try {
      const read = deps.readUse || (await import("./studiocardsfilm.js")).filmUse;
      use = await read(env, got.relay, deps.ctx);
    } catch (e) {
      console.log(`project_modes: ${got.id}: the film was not read — ${(e && e.message) || e}`);
    }
  }
  return {
    ok: true, id: got.id, type: got.type, job: got.job, switch: sw.on,
    modes: asFlags(got.modes), standard: asFlags(got.standard),
    tiles: tilesOf(record && record.film, use),
    // The mods (studiomods.js): every one on the shelf, on or off; off by default.
    mods: modFlags(resolveMods(record)), shelf: shelf(),
  };
}

/** A list of mods as `{key: bool}`, every shelf mod named. */
export function modFlags(list) {
  const on = new Set(list || []);
  const out = {};
  for (const k of MOD_KEYS) out[k] = on.has(k);
  return out;
}

/** The ask `set_project_mod(id, mod, on)` — the Systems card's mod switch. */
export async function setProjectMod(env, [id, mod, on] = [], deps = {}) {
  if (typeof on !== "boolean") return { ok: false, error: "Say on or off." };
  const got = await setMod(env, String(id || ""), { mod: String(mod || ""), on, by: deps.by || "console" }, deps);
  if (!got.ok) return { ok: false, error: got.why || "The mod was not switched." };
  return { ok: true, id: got.id, mods: modFlags(got.mods), ...(got.unchanged ? { unchanged: true } : {}) };
}

/** The ask `set_project_mode(id, mode, on, both)`. */
export async function setProjectMode(env, [id, mode, on, both] = [], deps = {}) {
  await loadStandards(env);
  if (typeof on !== "boolean") return { ok: false, error: "Say on or off." };
  const got = await setMode(env, String(id || ""), { mode: String(mode || ""), on, both: both === true, by: deps.by || "console" }, deps);
  if (!got.ok) return { ok: false, ...(got.needs ? { needs: got.needs } : {}), error: got.why || "The mode was not changed.", ...(got.modes ? { modes: asFlags(got.modes) } : {}) };
  return { ok: true, id: got.id, modes: asFlags(got.modes), ...(got.also && got.also.length ? { also: got.also } : {}), ...(got.unchanged ? { unchanged: true } : {}) };
}
