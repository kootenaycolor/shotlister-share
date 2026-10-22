/**
 * Stage 5 step 6: the remaining non-drive actions, in four groups, each with
 * its own file and its own switch (off by default):
 *   step6portal.js   portal page editing
 *   step6records.js  records and templates
 *   step6health.js   project health, restore, unarchive, the Job's loose folder
 *   step6history.js  the console-wide activity log and undo, the agents' list
 *   step6shelf.js    Released stills, Close Project and Reopen Project (2026-10-15)
 * This file only joins them to the shared doors (cloud.js, later.js,
 * routerasks.js, studio.js).
 */
import * as portal from "./step6portal.js";
import * as records from "./step6records.js";
import * as health from "./step6health.js";
import * as history from "./step6history.js";
import * as shelf from "./step6shelf.js";
import { refuseOff } from "./fixedon.js";

export const GROUPS = [portal, records, health, history, shelf];

export const STEP6_METHODS = new Set(GROUPS.flatMap((g) => [...g.METHODS]));
export const STEP6_NOW = new Set(GROUPS.flatMap((g) => [...g.NOW]));
export const STEP6_LATER_WRITES = new Set(GROUPS.flatMap((g) => [...g.LATER_WRITES]));
export const STEP6_LATER_READS = new Set(GROUPS.flatMap((g) => [...g.LATER_READS]));

export async function groupOn(env, g) {
  const got = await env.BUCKET.get(`s/step6-${g.SWITCH.replace(/^step6/, "")}.json`);
  if (!got) return false;
  try { return (await got.json()).on === true; } catch { return false; }
}

export async function setGroup(env, g, said) {
  // All five groups are fixed on: the four from 2026-10-18, and the shelf
  // (Released stills, Close Project, Reopen) from 2026-10-19, once its
  // three-day trial from 2026-10-16 ran clean.
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(`s/step6-${g.SWITCH.replace(/^step6/, "")}.json`, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

/** The step 6 methods answered right now (their group's switch on). */
export async function step6Now(env) {
  // each group's switch read at once, the answer in the groups' order
  const on = await Promise.all(GROUPS.map((g) => (g.METHODS.size ? groupOn(env, g) : false)));
  const out = [];
  GROUPS.forEach((g, i) => { if (on[i]) out.push(...g.METHODS); });
  return out;
}

/** Answer one ask, or `undefined` when it is not a step 6 ask; `null` hands it to the Mac. */
export async function step6Answer(env, method, list) {
  for (const g of GROUPS) {
    if (!g.METHODS.has(method)) continue;
    if (!(await groupOn(env, g))) return null;
    const result = await g.ASKS[method](list, env);
    return result === null ? null : { state: "done", result };
  }
  return undefined;
}

/** The standard switch door: GET {on,at,by}, PUT {on,by}; else the group's own door. */
export async function step6Door(env, rest, method, readBody, ctx, url) {
  const g = GROUPS.find((x) => x.SWITCH === rest[0]);
  if (!g) return null;
  if (rest.length === 1 && method === "GET") return Response.json({ switch: g.SWITCH, ...(await (async () => { const on = await groupOn(env, g); return { on }; })()) });
  if (rest.length === 1 && method === "PUT") return Response.json(await setGroup(env, g, await readBody()));
  return g.door(env, rest, method, readBody, ctx, url);
}
