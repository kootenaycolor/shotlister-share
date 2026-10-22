/**
 * **Mods: one shelf, switched on per project** (2026-10-17, his go-ahead on
 * the mods plan of 2026-10-15).
 *
 * A mod is a small add-on built once and kept on one shelf for every project.
 * A project switches one on when it needs it; **off by default**, and a
 * project with none on looks exactly as it did before mods existed. His
 * answers: no fixed cap, one shared gold, add-ons to the existing modes only,
 * switched from the console card and from Studio (the same switch).
 *
 * **Kept like the modes** (studiomodes.js), minus the Type standard: the
 * record's `mods` fact holds the mods this project has on, `{edit_reference:
 * true}`. Nothing starts on, so there is nothing to differ from. Off hides,
 * never deletes: a mod's own content lives in the Studio side and stays there.
 *
 *   GET  /console/studio/mods            the shelf [{key, title, adds_to}]
 *   GET  /console/studio/mods/<id>       {ok, id, mods: [key], shelf}
 *   POST /console/studio/mods/<id>       {mod, on, by} — one mod on or off
 *
 * The card (studiocards.js), the console list (onelist.js) and the
 * Systems card's ask (projectmodes.js) carry the list as `mods`.
 */

import { resolveProject } from "./projectid.js";

/**
 * **The shelf.** One entry per mod; a mod no project has used for a long time
 * is `tucked: true` (kept, never offered), never removed. Mirrored by hand in
 * Studio (`Mods.swift`), the phone and the console (`projectmodes.py`), the
 * way `MODES` is.
 */
export const SHELF = [
  { key: "edit_reference", title: "Edit Reference", adds_to: "shot_list" },
];
export const MOD_KEYS = SHELF.map((m) => m.key);

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

/** What the shelf offers, for any reader. */
export function shelf() {
  return SHELF.filter((m) => !m.tucked).map(({ key, title, adds_to }) => ({ key, title, adds_to }));
}

/** The mods a record has on, in the shelf's order. Unknown or non-true entries are ignored. */
export function resolveMods(record) {
  const one = isObject(record && record.facts) ? record.facts.mods : null;
  const raw = isObject(one) ? one.value : null;
  if (!isObject(raw)) return [];
  return MOD_KEYS.filter((k) => raw[k] === true);
}

/** The `mods` fact for a wanted list: only the ones on. */
export function modsValue(list) {
  const out = {};
  for (const k of MOD_KEYS) if (list.includes(k)) out[k] = true;
  return out;
}

/** The mods a film's project has on, by any of its ids; none when unknown. */
export async function modsOfFilm(env, id) {
  try {
    const found = await resolveProject(env, id);
    return found.key && isObject(found.record) ? resolveMods(found.record) : [];
  } catch {
    return [];
  }
}

export async function readMods(env, id) {
  const found = await resolveProject(env, id);
  if (!found.key || !isObject(found.record)) return { ok: false, status: 404, why: "No project with that ID." };
  return { ok: true, id: found.key, mods: resolveMods(found.record), shelf: shelf() };
}

/** One mod on or off: `{mod, on, by, dry?}`. `deps.writeFacts` stands in for the checks. */
export async function setMod(env, id, said, deps = {}) {
  const s = isObject(said) ? said : {};
  const mod = String(s.mod || "");
  if (!MOD_KEYS.includes(mod)) return { ok: false, status: 400, why: "No such mod." };
  if (typeof s.on !== "boolean") return { ok: false, status: 400, why: "Say on or off." };
  const by = String(s.by || "").slice(0, 80) || "server";
  const write = deps.writeFacts || (async (page, changes, who) => (await import("./facts.js")).writeFacts(env, page, changes, who));
  for (let attempt = 0; attempt < 3; attempt++) {
    const found = await resolveProject(env, id);
    if (!found.key || !isObject(found.record)) return { ok: false, status: 404, why: "No project with that ID." };
    const now = resolveMods(found.record);
    const next = MOD_KEYS.filter((k) => (k === mod ? s.on : now.includes(k)));
    if (s.dry === true) return { ok: true, dry: true, id: found.key, mods: next };
    if (next.join() === now.join()) return { ok: true, id: found.key, mods: now, unchanged: true };
    const have = (found.record.facts || {}).mods;
    const wrote = await write(found.key, { mods: { value: modsValue(next), base: isObject(have) ? Number(have.v) || 0 : 0 } }, by);
    if (wrote && wrote.status === 409) continue;
    if (!wrote || wrote.status !== 200) return { ok: false, status: 500, id: found.key, why: (wrote && wrote.problem) || "The mod could not be switched." };
    return { ok: true, id: found.key, mods: next };
  }
  return { ok: false, status: 409, why: "The project kept changing. Try again." };
}

export async function modsDoor(env, rest, method, read) {
  if (rest[0] !== "mods") return null;
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest.length === 1) {
    if (method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    return reply({ ok: true, shelf: shelf() });
  }
  if (rest.length !== 2) return null;
  if (method === "GET") {
    const got = await readMods(env, rest[1]);
    return reply(got, got.status || 200);
  }
  if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
  let said;
  try { said = await read(); } catch { said = null; }
  if (!isObject(said)) return reply({ ok: false, problem: "That is not JSON." }, 400);
  try {
    const got = await setMod(env, rest[1], said);
    return reply(got, got.status || 200);
  } catch (e) {
    return reply({ ok: false, why: String((e && e.message) || e).slice(0, 300) }, 500);
  }
}
