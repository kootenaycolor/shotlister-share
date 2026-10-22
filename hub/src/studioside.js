/**
 * **A project's Studio side, made when it is first wanted** (2026-10-14,
 * stage 5 step 2; his answer 14). A project with no modes has no film; the
 * first time a mode is switched on — from the console, from Studio, from
 * Studio's own New Project — this makes it, **under the project's own ID**
 * (`p/<id>/`), so there is nothing to link afterwards and nothing to carry.
 *
 * - A project whose record already names a film answers that film, whatever
 *   its id: an existing project's film keeps its relay id for good (an alias,
 *   `projectid.js`). Nothing is made.
 * - A film already under the project's ID (a device made it first and synced)
 *   is named on the record. Nothing is made.
 * - Otherwise the engine's own `new_film` door (`mcpweb/src/newfilm.rs`, the
 *   door New Film uses) writes the film's first change log and manifest at
 *   `p/<id>/`, and the record names it (`film.relay = id`, `made: "hub"`, so
 *   the record door keeps it while the Mac has not fetched it yet).
 * - **A portal the project already had stays exactly where it is.** It lives
 *   at `p/<page id>/`, which for an existing project is the project's ID: the
 *   film is born on top of it. Its mark (`portal.json`, "a portal with no film")
 *   is taken away, because now there is a film; every page, person and link
 *   stays put, so no sent address changes and nothing is copied.
 *
 * Refused, with nothing written: no project with that ID; a film the record
 * names that is no longer on the relay (archived or taken off — the console's
 * restore is the way back, not a second film); a film of the same name
 * already on the relay (Studio's folder names must differ); a make already
 * under way. Only while the one-ID switch is on (`s/oneid.json`); a dry look
 * answers either way and writes nothing.
 */

import { resolveProject, studioOf, notionOf, oneIdOn, bare, ID } from "./projectid.js";

let LAYOUT = null;
const layout = async () => (LAYOUT ||= await import("../../relay/layout.js"));

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const claimKey = (id) => `s/studioside/${id}.json`;
const STALE_MS = 10 * 60 * 1000;

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return { value: await got.json(), etag: got.etag }; } catch { return { value: null, etag: got.etag }; }
}

/** The Notion row's Drive Folder address and icon, when the server can read Notion. */
async function notionBits(env, page, fetchRow) {
  if (!ID.test(page)) return { drive_url: "", icon: "" };
  try {
    const row = fetchRow ? await fetchRow(page) : await (async () => {
      const { cloudReady, apiOf } = await import("./cloud.js");
      if (!cloudReady(env)) return null;
      const got = await fetch(`${apiOf(env)}pages/${page}`, {
        headers: { authorization: `Bearer ${String(env.NOTION_TOKEN).trim()}`, "notion-version": "2025-09-03" },
      });
      return got.ok ? await got.json() : null;
    })();
    if (!isObject(row)) return { drive_url: "", icon: "" };
    const url = ((row.properties || {})["Drive Folder"] || {}).url || "";
    let icon = "";
    try { const { iconText } = await import("./notionlink.js"); icon = iconText(row) || ""; } catch { icon = ""; }
    return { drive_url: String(url || ""), icon };
  } catch {
    return { drive_url: "", icon: "" };
  }
}

/**
 * What would happen for this ID, and what the film would be made from;
 * nothing written. `{ok, key, relay, made, ...}` or `{ok: false, why}`.
 * `deps.fetchRow(page)` and `deps.fetchText(url)` stand in for Notion and
 * icon fetches in the checks.
 */
export async function planStudioSide(env, id, deps = {}) {
  const { keys, names } = await layout();
  const found = await resolveProject(env, id);
  if (!found.key) return { ok: false, why: "No project with that ID." };
  const { key, record } = found;
  const relay = studioOf(record);
  if (relay) {
    if (await env.BUCKET.head(keys.manifest(relay))) {
      return { ok: true, key, via: found.via, relay, made: false, alias: relay !== key, title: String((record.film || {}).title || "") };
    }
    return { ok: false, key, why: `This project's film (${(record.film || {}).title || relay}) is not on the relay. Restore it rather than make another.` };
  }
  if (await env.BUCKET.head(keys.manifest(key))) {
    return { ok: true, key, via: found.via, relay: key, made: false, name_it: true, title: String(record.name || "") };
  }
  const title = String(record.name || "").trim();
  if (!title) return { ok: false, key, why: "The project has no name yet." };
  // The Mac's rule (`--newfilm` refuses a taken name): Studio keeps a film as
  // a folder named after its title, and two films cannot share one.
  const { safeName } = await import("./newfilm.js");
  const want = safeName(title).toLowerCase();
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: "p/", delimiter: "/", cursor, limit: 1000 });
    for (const prefix of page.delimitedPrefixes || []) {
      const project = prefix.slice(2, -1);
      if (!names.project.test(project) || project === key) continue;
      const m = await readJson(env, keys.manifest(project));
      if (m && isObject(m.value) && safeName(String(m.value.title || "")).toLowerCase() === want) {
        return { ok: false, key, why: `A film called "${title}" already exists on the relay.` };
      }
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  const notion = notionOf(record, key);
  const bits = await notionBits(env, notion, deps.fetchRow);
  const folders = await readJson(env, `r/${key}/folders.json`);
  const folder = folders && isObject(folders.value) ? String(folders.value.path || "") : "";
  const { markLookup, fetchIcon, markAddress } = await import("./filmfacts.js");
  let facts = isObject(record.facts) ? record.facts : {};
  if (!markAddress(facts) && bits.icon) facts = { icon: { value: bits.icon } };
  let pair = {};
  try { pair = await markLookup(env, deps.fetchText || fetchIcon).of(facts); } catch { pair = {}; }
  return {
    ok: true, key, via: found.via, relay: key, made: true, title,
    portal: Boolean(await env.BUCKET.head(keys.portal(key))),
    link: {
      title, page: notion, name: String(record.name || ""), drive_url: bits.drive_url, drive_folder: folder,
      ...(pair && pair.path ? { mark: { path: pair.path, colour: pair.colour } } : {}),
    },
  };
}

/**
 * Make sure the project has its Studio side. `{dry}` answers the plan and
 * writes nothing; otherwise only while the switch is on. Answers
 * `{ok, key, relay, made}` (made false when it was already there) or
 * `{ok: false, why}`.
 */
export async function ensureStudioSide(env, id, { dry = false, by = "", ...deps } = {}) {
  const plan = await planStudioSide(env, id, deps);
  if (dry) {
    const { link, ...shown } = plan;
    return { ...shown, dry: true, ...(link ? { would: link } : {}), switch: (await oneIdOn(env)).on };
  }
  if (!(await oneIdOn(env)).on) return { ok: false, why: "The one-ID switch is off." };
  if (!plan.ok) return plan;
  const { nameOnRecord, deviceFor } = await import("./newfilm.js");
  const { keys } = await layout();
  const { key } = plan;
  if (!plan.made) {
    if (plan.name_it) await nameOnRecord(env, key, plan.title, plan.title, key, null);
    const { link: _l, ...out } = plan;
    return out;
  }

  // Claimed first: a second press, a second device, finds it under way.
  const held = await readJson(env, claimKey(key));
  if (held && isObject(held.value) && held.value.state === "making" && Date.now() - Date.parse(held.value.at || 0) < STALE_MS) {
    return { ok: false, key, why: "This project's Studio side is being made right now." };
  }
  const claim = { key, title: plan.title, state: "making", at: new Date().toISOString(), by: String(by || "").slice(0, 80) };
  const claimed = await env.BUCKET.put(claimKey(key), JSON.stringify(claim), {
    httpMetadata: { contentType: "application/json" },
    onlyIf: held ? { etagMatches: held.etag } : { etagDoesNotMatch: "*" },
  });
  if (!claimed) return { ok: false, key, why: "This project's Studio side is being made right now." };

  const device = deviceFor("studio-side");
  const make = deps.engineMakes || (await import("./newfilmdoor.js")).engineMakes;
  let said, log;
  try {
    ({ said, log } = await make(plan.link, device));
  } catch (e) {
    await env.BUCKET.delete(claimKey(key));
    throw e;
  }
  const session = [...crypto.getRandomValues(new Uint8Array(8))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const logKey = keys.log(key, `${device}-${session}.log`);
  await env.BUCKET.put(logKey, log, { httpMetadata: { contentType: "text/plain; charset=utf-8" } });
  try {
    await env.BUCKET.put(keys.manifest(key), said.manifest, { httpMetadata: { contentType: "application/json" } });
  } catch (e) {
    await env.BUCKET.delete(logKey);
    await env.BUCKET.delete(claimKey(key));
    throw e;
  }
  await nameOnRecord(env, key, plan.link.name, plan.title, key, plan.link.mark || null);
  // The portal it may have had is now the film's page, where it already is.
  let portal = false;
  if (await env.BUCKET.head(keys.portal(key))) {
    await env.BUCKET.delete(keys.portal(key));
    portal = true;
  }
  await env.BUCKET.put(claimKey(key), JSON.stringify({ ...claim, state: "made", made: new Date().toISOString(), engine_project: said.project }), {
    httpMetadata: { contentType: "application/json" },
  });
  return { ok: true, key, via: plan.via, relay: key, made: true, title: plan.title, ...(portal ? { portal: "kept in place" } : {}) };
}

/** `POST /console/studio/projects/<id>/studio {dry, by}` — the door later steps call. */
export async function studioSideDoor(env, id, said) {
  const s = isObject(said) ? said : {};
  const x = bare(id);
  if (!ID.test(x)) return { status: 404, body: { problem: "That is not a project ID." } };
  try {
    const got = await ensureStudioSide(env, x, { dry: s.dry === true, by: s.by });
    // A refusal is an answer, `{ok: false, why}`, as New Film's are.
    return { status: 200, body: got };
  } catch (e) {
    return { status: 500, body: { ok: false, why: String((e && e.message) || e).slice(0, 300) } };
  }
}
