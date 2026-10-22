/**
 * **The portal follows the modes, and has one Shared switch** (stage 5 step
 * 5, the portal piece, 2026-10-15).
 *
 * Behind one switch, `s/portal-modes.json`, off until thrown:
 *
 * 1. **The sidebar leaves out the pages of a mode that is off** (his plan,
 *    step 5: "the sidebar hides the page of any mode that is off"). The
 *    modes are `studiomodes.resolveModes(record)`, never a second copy.
 *    Hidden the way a page in the Library is (`offSidebar`): off the rail,
 *    for everybody, and **still at its address** — a link already sent to it
 *    opens it as before (portal links never break). The row somebody is
 *    standing on stays, as every other hidden row does.
 *
 *      Shot List, Script            shot_list
 *      Locations                    locations
 *      Reference Images, his boards references
 *      Schedule                     schedule
 *      Diagrams                     diagram
 *      anything else                stays
 *
 * 2. **Shared / Not Shared** (`portalShared`): Not Shared is a flag, never
 *    a change to a link, so a crew member holding one sees "This page isn't
 *    shared" and Shared opens every address already sent, byte for byte the
 *    same. Nothing here forgets a key: Take Down and Replace Link stay the
 *    ways a portal goes away or a link changes.
 *
 * 3. **The one shoot picker** on the portal (`pages.js` `shootTabs`): All
 *    Shoots, each shoot with its dates and Wrapped / Next / Upcoming; every
 *    shoot keeps its own address.
 *
 *   GET  /console/studio/portalmodes        the switch {on, at, by}
 *   PUT  /console/studio/portalmodes        {on, by}
 *   GET  /console/studio/portalmodes/look   per project, which sidebar pages would go; writes nothing
 */

import { resolveProject, studioOf, bare, ID } from "./projectid.js";
import { resolveModes, MODES, TITLES, loadStandards } from "./studiomodes.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/portal-modes.json";

/** The address "All Shoots" lives at, beside each shoot's own (`/shoots/<slug>`). */
export const ALL_SHOOTS = "all-shoots";

/** A refusal, said both ways the askers read one. */
const failed = (why) => ({ ok: false, error: why, why });

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function portalModesOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setPortalModes(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── pages and modes ──────────────────────────────────────────────────────────

/** The portal's own pages that belong to a mode, by their address key. */
export const PAGE_MODE = {
  shotlist: "shot_list",
  script: "shot_list",
  locations: "locations",
  boards: "references",
  schedule: "schedule",
  diagrams: "diagram",
};

/** The mode a page belongs to, or "" when it belongs to none. A board of his own is a reference. */
export function modeOfPage(at, type = "") {
  if (Object.prototype.hasOwnProperty.call(PAGE_MODE, at)) return PAGE_MODE[at];
  return type === "board" ? "references" : "";
}

/** The pages of `front` whose mode is not in `on` — every one, pinned or not. */
export function pagesOff(front, on) {
  const have = new Set(on || []);
  const out = [];
  for (const at of Object.keys(PAGE_MODE)) if (!have.has(PAGE_MODE[at])) out.push(at);
  for (const one of (front && front.sections) || []) {
    if (one && one.slug && one.type === "board" && !have.has("references") && !out.includes(one.slug)) out.push(one.slug);
  }
  return out;
}

/**
 * **What a portal's sidebar leaves out, for `frontOf`.** `{on, modes, off}`:
 * `on` is the switch, `off` the page keys to leave off the rail. Switch off,
 * or no record for this portal: nothing is left out.
 */
export async function modesOffFor(env, project, front) {
  await loadStandards(env);
  const sw = await portalModesOn(env);
  if (!sw.on) return { on: false, modes: null, off: [] };
  const found = await resolveProject(env, project);
  if (!found.key || !isObject(found.record)) return { on: true, modes: null, off: [] };
  const { modes } = resolveModes(found.record);
  return { on: true, modes, off: pagesOff(front, modes) };
}

// ── the dry look ─────────────────────────────────────────────────────────────

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

/** The portal a record has: its film's, else a portal under its own key. "" for none. */
async function portalOfRecord(env, key, record) {
  const relay = studioOf(record);
  if (relay && (await env.BUCKET.head(`p/${relay}/manifest.json`) || await env.BUCKET.head(`p/${relay}/front.json`))) return relay;
  if (await env.BUCKET.head(`p/${key}/portal.json`)) return key;
  return relay || "";
}

/**
 * **Per project, which sidebar pages would go** with the switch on. Writes
 * nothing, whatever the switch says. `readFront(env, portal, ctx)` answers the
 * portal's card (`frontOf` by default; the mirror look passes the stored one).
 *
 * A row is `{id, name, type, job, portal, modes, off: [modes off], hides:
 * [{at, name, mode}] (on the sidebar today, would go), library: [...] (off the
 * sidebar already)}`.
 */
export async function portalModesLook(env, ctx, { readFront, only = "" } = {}) {
  await loadStandards(env);
  const read = readFront || (async (e, p, c) => (await import("./front.js")).frontOf(e, p, c));
  const { offeredPages } = await import("./pages.js");
  const { offSidebar } = await import("./front.js");
  const want = bare(only);
  const rows = [];
  for (const key of await recordKeys(env)) {
    if (want && key !== want) continue;
    const record = await readJson(env, `r/${key}/record.json`);
    if (!isObject(record)) continue;
    const r = resolveModes(record);
    const row = { id: key, name: String(record.name || ""), type: r.type, job: r.job, modes: r.modes, off: MODES.filter((m) => !r.modes.includes(m)) };
    const portal = await portalOfRecord(env, key, record);
    if (!portal) { rows.push({ ...row, portal: "" }); continue; }
    let front;
    try { front = await read(env, portal, ctx); } catch (e) {
      rows.push({ ...row, portal, trouble: String((e && e.message) || e).slice(0, 200) });
      continue;
    }
    const gone = new Set(pagesOff(front, r.modes));
    const pages = offeredPages(front).filter((p) => gone.has(p.at));
    const said = (p) => ({ at: p.at, name: p.name, mode: TITLES[modeOfPage(p.at, p.type)] || "" });
    rows.push({
      ...row, portal,
      hides: pages.filter((p) => !offSidebar(front, p.at)).map(said),
      library: pages.filter((p) => offSidebar(front, p.at)).map((p) => p.at),
    });
  }
  return {
    at: new Date().toISOString(), dry: true, switch: (await portalModesOn(env)).on,
    projects: rows.length, portals: rows.filter((r) => r.portal).length,
    hiding: rows.filter((r) => r.hides && r.hides.length).length, rows,
  };
}

// ── Shared / Not Shared ──────────────────────────────────────────────────────

/** Where a portal's Not Shared is kept: beside the switch, not in the film. */
export const notSharedKey = (portal) => `s/portal-notshared/${bare(portal)}.json`;

/** `{notShared, since, by}` — false when nothing is kept. */
export async function notSharedOf(env, portal) {
  const v = await readJson(env, notSharedKey(portal));
  return { notShared: Boolean(v && v.notShared === true), since: (v && v.since) || "", by: (v && v.by) || "" };
}

/**
 * The portal a project's ID names, through the one way to find a project:
 * its own ID, its Notion page or its film's relay id. "" when it has none.
 */
export async function portalOfId(env, id) {
  const x = bare(id);
  if (!ID.test(x)) return "";
  const { relayOfPage } = await import("./cloudportal.js");
  const found = await resolveProject(env, x);
  if (found.key) {
    const relay = await relayOfPage(env, found.key);
    if (relay) return relay;
  }
  if (await relayOfPage(env, x)) return await relayOfPage(env, x);
  // A film's own relay id, with no record naming it.
  return (await env.BUCKET.head(`p/${x}/manifest.json`)) ? x : "";
}

/**
 * **The status line's facts**, `{ok, shared, people, pages, link}`: whether
 * the crew can open it, how many people are on its list (his own addresses
 * not counted), how many pages a crew member is shown, and the link he sends
 * (the short one when there is one). Read only. No portal: not shared, 0, 0.
 */
export async function portalState(env, id, ctx) {
  const portal = await portalOfId(env, id);
  if (!portal) return { ok: true, id: bare(id), portal: "", shared: false, down: false, people: 0, pages: 0, link: "" };
  const { door } = await import("./cloudportal.js");
  const [readout, viewers, kept] = await Promise.all([door(env, portal, "GET"), door(env, `${portal}/viewers`, "GET"), notSharedOf(env, portal)]);
  if (readout.status >= 400) return failed(readout.json.problem || `the hub answered ${readout.status}`);
  const { owners } = await import("./films.js");
  const mine = new Set(owners(env).map((e) => String(e).toLowerCase()));
  const people = (readout.json.people || []).filter((p) => p && p.email && !mine.has(String(p.email).toLowerCase())).length;
  const general = (readout.json.links || []).find((l) => l && l.url);
  const off = new Set(((await modesOffFor(env, portal, {})).off) || []);
  const pages = ((viewers.json && viewers.json.sections) || []).filter((p) => p.shown && !p.empty && !off.has(p.at)).length;
  return {
    ok: true, id: bare(id), portal,
    shared: !kept.notShared && !readout.json.down,
    down: Boolean(readout.json.down),
    people, pages,
    link: general ? general.url : "",
  };
}

/**
 * **Shared or Not Shared**, `{ok, shared, link}`.
 *
 * Not Shared is one small file beside the switch (`notSharedKey`): the
 * portal answers everybody but an editor "This page isn't shared", at every
 * address under it, the way Take Down answers "This page is down". **No link
 * is touched**, so turning it back on gives every address already sent, byte
 * for byte. Shared takes the file away, and makes sure the link works: a
 * portal with no link gets its first (as General Access makes one), and a
 * general link switched off is switched on again — the same key. Behind the
 * switch; the file is honoured whatever the switch says, so throwing the
 * switch off never quietly shares a portal he said was not.
 */
export async function portalShared(env, id, on, ctx) {
  if (!(await portalModesOn(env)).on) return failed("The portal switch is off on the server.");
  if (typeof on !== "boolean") return failed("Say on or off.");
  const portal = await portalOfId(env, id);
  if (!portal) return failed("This project has no portal.");
  if (!on) {
    await env.BUCKET.put(notSharedKey(portal), JSON.stringify({ notShared: true, since: new Date().toISOString(), by: "console" }),
      { httpMetadata: { contentType: "application/json" } });
  } else {
    const { door, mintLink } = await import("./cloudportal.js");
    const people = await door(env, `${portal}/people`, "GET");
    if (people.status >= 400) return failed(people.json.problem || `the hub answered ${people.status}`);
    const general = (people.json.links || []).find((l) => l && l.key);
    let got = null;
    if (!general) {
      const fresh = await mintLink();
      got = await door(env, `${portal}/access`, "PUT", { replace: { key: fresh.key, hash: fresh.hash, was: null } });
    } else if (general.off === true) {
      got = await door(env, `${portal}/link`, "PUT", { off: false, hash: general.hash });
    }
    if (got && got.status >= 400) return failed(got.json.problem || `the hub answered ${got.status}`);
    await env.BUCKET.delete(notSharedKey(portal));
  }
  const state = await portalState(env, portal, ctx);
  return { ok: true, shared: state.ok ? state.shared : on, link: state.ok ? state.link : "" };
}

/** The asks, `(args, env, ctx)`: `portal_shared(id, on)` and `portal_state(id)`. */
export const PORTAL_MODE_ASKS = {
  async portal_shared([id, on], env, ctx) { return await portalShared(env, id, on, ctx); },
  async portal_state([id], env, ctx) { return await portalState(env, id, ctx); },
};

// ── the door ─────────────────────────────────────────────────────────────────

export async function portalModesDoor(env, rest, method, read, ctx) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest[0] !== "portalmodes") return null;
  if (rest.length === 1) {
    if (method === "GET") return reply(await portalModesOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said;
    try { said = await read(); } catch { said = null; }
    if (!isObject(said)) return reply({ ok: false, problem: "That is not JSON." }, 400);
    return reply(await setPortalModes(env, said));
  }
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    return reply(await portalModesLook(env, ctx));
  }
  return null;
}
