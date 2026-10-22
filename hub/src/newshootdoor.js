/**
 * **The ways in to New Shoot on the server** (newshoot.js, stage 4 part A):
 * the phone's three asks, its switch, and a look that writes nothing.
 *
 * - `new_shoot_form(name)`, `plan_new_shoot(name, form)` and
 *   `run_new_shoot(name, form)` — answered here, the Mac's way, **only while
 *   the switch is on and the server can make Drive folders** (the
 *   `drivefolders` switch on, its roots set and the `GDRIVE_WRITE` sign-in).
 *   Otherwise all three stay the Mac's and are not listed to the phone, so a
 *   form drawn by one never meets a press answered by the other. The two
 *   that only read are kept behind the same switch for that reason.
 * - **The Mac awake changes nothing.** `project_dossier` and `drive_tree`
 *   hand back to an awake Mac because it can read what the server cannot (a
 *   plugged-in drive, the film on its disk). New Shoot reads nothing the
 *   server lacks: the film's half goes through the relay copy whichever
 *   machine asks (the Mac's own New Shoot calls this same door), and the
 *   Drive is Google's. So with the switch on the server answers every time —
 *   the simplest rule, and the one that can never split a form from its run
 *   when the Mac wakes or sleeps in between.
 *
 * What it reaches, each the server's own:
 * - Notion through `cloud.js` `notionOf` (a refusal before anything is
 *   written hands the ask to the Mac, as every cloud ask does);
 * - the project's record (`r/<page>/record.json`): the facts the Mac lays
 *   over its list (type, the shoot's own name, the Drive link) and the film
 *   it names (`film.relay`);
 * - the film, read by the engine from the relay copy (`view`), for its
 *   scenes, sections and days;
 * - Shotlister's door, `POST /console/<relay>/shoot` (SL-1402), called
 *   in-process the way `cloudportal.js` calls the console door;
 * - Google Drive through `drivefolders.js` (`planShoot`, `carryOut`) and a
 *   walk of the project folder for a LUT's Drive copy (`copyFinder`);
 * - the portal's Refresh from Notion (`cloudportal.js` `refresh_portal`).
 *
 *   GET  /console/studio/newshoot         { on, at, by, ready, why }
 *   PUT  /console/studio/newshoot         { on, by }
 *   POST /console/studio/newshoot/look    { name, form? } — the form, and with a form the
 *                                         plan, as the phone would get them; writes nothing
 */

import { Handoff, projectRow, notionOf, cloudReady } from "./cloud.js";
import * as rules from "./newshoot.js";

export const SWITCH_KEY = "s/newshoot.json";
const PAGE = /^[0-9a-f]{32}$/;
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

/** The switch: `{on, at, by}`, off when never set. */
export async function newShootOn(env) {
  const got = env && env.BUCKET ? await env.BUCKET.get(SWITCH_KEY) : null;
  let v = {};
  if (got) { try { v = await got.json(); } catch { v = {}; } }
  if (!isObject(v)) v = {};
  return { on: v.on === true, at: v.at || null, by: v.by || null };
}

/** Whether the server answers New Shoot now, and why not. */
export async function readiness(env) {
  const sw = await newShootOn(env);
  if (!sw.on) return { ...sw, ok: false, why: "the switch is off" };
  if (!cloudReady(env)) return { ...sw, ok: false, why: "the server has no Notion key" };
  const { state } = await import("./drivefoldersdoor.js");
  const drive = await state(env);
  if (!drive.ok) return { ...sw, ok: false, why: `the server can't make Drive folders: ${drive.why}` };
  return { ...sw, ok: true };
}

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the film ────────────────────────────────────────────────────────────────

/**
 * The project's film as `engine.find_shotlister_film` + `dossier.film_facts`
 * answer it: the film the record names. A record that names a film with no
 * relay is a film that has never synced — there on the Mac, out of the
 * server's reach (`shotlister_door`'s own words for it).
 */
async function filmOf(env, page, ctx) {
  const record = await readJson(env, `r/${page}/record.json`);
  const film = record && isObject(record.film) ? record.film : null;
  if (!film || film.archived) return { ok: false, why: "no Shotlister film" };
  const relay = PAGE.test(bare(film.relay)) ? bare(film.relay) : "";
  const { hasFilm, titleOf } = await import("./films.js");
  if (!relay || !(await hasFilm(env, relay))) {
    return { ok: true, relay: "", title: film.title || "", trouble: "", scenes: [], sections: [], days: [] };
  }
  const title = await titleOf(env, relay);
  try {
    const { filmShape } = await import("./newshootfilm.js");
    return { ok: true, relay, title, trouble: "", ...(await filmShape(env, relay, ctx)) };
  } catch (e) {
    return { ok: true, relay, title, trouble: String((e && e.message) || e).slice(0, 200), scenes: [], sections: [], days: [] };
  }
}

// ── Shotlister's door, in-process ───────────────────────────────────────────

/** `dossier.hub_console(relay, "shoot", "POST", …)`: the hub's JSON, or
 * `{trouble, status}` when it refused. */
async function shootDoor(env, relay, body, preview) {
  const { door } = await import("./cloudportal.js");
  try {
    const { status, json } = await door(env, `${relay}/shoot`, "POST", { ...body, preview: Boolean(preview) });
    if (status >= 400) return { trouble: (json && json.problem) || `the hub answered ${status}`, status };
    return json;
  } catch (e) {
    return { trouble: `the hub did not answer: ${String((e && e.message) || e).slice(0, 200)}` };
  }
}

// ── a file across to Notion ─────────────────────────────────────────────────

function notionBase(env) {
  const said = String(env.NOTION_API || "");
  return /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/v1\/$/.test(said) ? said : "https://api.notion.com/v1/";
}

/** The second half of `shoots.upload_file`: the bytes, as a form. */
async function sendUpload(env, id, name, ctype, bytes) {
  const form = new FormData();
  form.append("file", new Blob([bytes], { type: ctype }), name);
  const got = await fetch(`${notionBase(env)}file_uploads/${id}/send`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.NOTION_TOKEN.trim()}`, "notion-version": "2025-09-03" },
    body: form,
  });
  const answer = await got.json().catch(() => ({}));
  if (!got.ok) throw new Error(`Notion: ${answer.code || got.status}${answer.message ? ` — ${String(answer.message).slice(0, 160)}` : ""}`);
  return answer;
}

/** `shoots._download`: a Notion-hosted file's bytes. */
async function download(url) {
  const got = await fetch(url);
  if (!got.ok) throw new Error(`the file answered ${got.status}`);
  return new Uint8Array(await got.arrayBuffer());
}

// ── everything the rules reach, for one ask ─────────────────────────────────

/**
 * The world `newshoot.js` works in, for one ask. `write: false` (a look)
 * reads the Drive with whichever sign-in there is and can make nothing.
 */
export async function depsFor(env, n, name, { write = false, ctx = null } = {}) {
  const { driveApi } = await import("./drivewrite.js");
  const drive = await import("./drivefolders.js");
  const settings = await drive.settingsOf(env);
  const api = driveApi(env, { write });
  const run = ctx || { waitUntil() {}, passThroughOnException() {} };
  const copy = api ? rules.copyFinder(api) : async () => "";
  return {
    n,
    now: rules.today(),
    row: (nm) => projectRow(n, nm),
    facts: async (page) => (((await readJson(env, `r/${page}/record.json`)) || {}).facts) || {},
    film: (page) => filmOf(env, page, run),
    portal: async (page, film) => {
      if (film.ok) return Boolean(film.relay);
      const { portalOf } = await import("./films.js");
      const { keyOfPage } = await import("./projectid.js");
      return Boolean(await portalOf(env, (await keyOfPage(env, page)) || page));
    },
    door: {
      live: async (relay) => (relay ? [true, ""] : [false, "the film has never synced, so the portal can't reach it"]),
      shoot: (relay, body, preview) => shootDoor(env, relay, body, preview),
    },
    drive: {
      plan: async (facts) => (api ? await drive.planShoot(api, settings, facts) : { ok: false, why: "the server has no Google sign-in to read the Drive with" }),
      copy,
      make: async (plan) => {
        if (!api || !api.mkdir) throw new Error("the server has no Google sign-in that can make folders");
        return await drive.carryOut(api, plan);
      },
    },
    refresh: async () => {
      const { PORTAL_METHODS } = await import("./cloudportal.js");
      const row = await projectRow(n, name);
      if (!row) return { ok: false, why: "no Notion row for this project" };
      return await PORTAL_METHODS.refresh_portal(n, [name], env, row);
    },
    download,
    upload: (id, nm, ctype, bytes) => sendUpload(env, id, nm, ctype, bytes),
    // **Days written once, belonging to their shoot** (studioframes.js, step
    // 4 piece E): with its switch on, the film's day is the new shoot's own.
    daysFollow: async () => {
      const { framesOn } = await import("./studioframes.js");
      return (await framesOn(env)).on;
    },
    // step6history.logActivity never throws: a line that can't be kept never fails the shoot
    logActivity: async (entry) => {
      const { logActivity } = await import("./step6history.js");
      return await logActivity(env, entry);
    },
  };
}

/**
 * The project's record by its name, for when Notion cannot be asked for its
 * page. Reads the records in the bucket (a few dozen), takes the one whose
 * title is this. Null when none, or two.
 */
export async function recordByName(env, name) {
  const want = String(name || "").trim();
  if (!want) return null;
  const hits = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const key = p.split("/")[1];
      if (!/^[0-9a-f]{32}$/.test(key)) continue;
      const rec = await readJson(env, `r/${key}/record.json`);
      if (!isObject(rec)) continue;
      const facts = isObject(rec.facts) ? rec.facts : {};
      const title = String((isObject(facts.title) ? facts.title.value : "") || rec.name || "").trim();
      if (title === want && !(rec.job === true || rec.kind === "job")) hits.push({ key, record: rec, facts, title });
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return hits.length === 1 ? hits[0] : null;
}

/**
 * The same three asks when Notion cannot be reached (a dead key, an outage):
 * read from the project's record, the Drive folders made at once, the Notion
 * row, spec sheet, Studio day and portal page queued on the record as a
 * waiting shoot (`shoots_waiting`) and made on their own when Notion answers.
 * This is the connector's add_shoot path (mcpshoots.js), shared.
 */
async function askWithNotionDown(env, n, method, name, list, why, hooks = {}) {
  const found = await recordByName(env, name);
  if (!found) throw why;                                   // no record to go on: as before
  const { waitingOf, queueWaiting } = await import("./mcpshoots.js");
  const page = String(found.record.notion_page || found.record.page || found.key);
  const deps = await (hooks.depsFor || depsFor)(env, n, name, { write: method === "run_new_shoot" });
  if (method === "run_new_shoot" && typeof env.ASK_PROGRESS === "function") deps.progress = env.ASK_PROGRESS;
  const ctx = await rules.ctxFromRecord(deps, { name, page, facts: found.facts, waiting: waitingOf(found.facts) });
  if (method === "new_shoot_form") return await rules.newShootForm(deps, name, { ctx, mode: "down" });
  const form = isObject(list[1]) ? list[1] : {};
  if (method === "plan_new_shoot") return await rules.planAnswer(deps, name, form, { ctx, mode: "down" });
  const { busyWords } = await import("./bigmoves.js");
  const busy = busyWords(found.record);
  if (busy) return { ok: false, why: busy, report: busy };
  const quiet = Object.create(deps);
  quiet.logActivity = async (entry) => (deps.logActivity
    ? deps.logActivity({ ...entry, desc: `${String(entry.desc).replace(/ set up$/, "")}: Drive folders made, the rest waits for Notion` })
    : undefined);
  const result = await rules.runAnswer(quiet, name, form, { ctx, mode: "down" });
  if (!result.ok) return result;
  const queued = await queueWaiting({ env, key: found.key }, result, form);
  return { ...result, notion_waits: true,
    report: `${result.report}\n${queued ? rules.NOTION_WAITS : "Could not be queued on the record; add the shoot again once Notion is back."}`,
    ...(queued ? {} : { failed: [...(result.failed || []), "The Notion part could not be queued; add the shoot again once Notion is back."] }) };
}

/** One of the phone's three asks, answered here — or handed to the Mac. */
export async function newShootAsk(env, n, method, args, hooks = {}) {
  const ready = hooks.readiness ? await hooks.readiness(env) : await readiness(env);
  if (!ready.ok) throw new Handoff(ready.why);
  const list = Array.isArray(args) ? args : [];
  const name = String(list[0] || "");
  try {
    return await newShootAskNormal(env, n, method, name, list, hooks);
  } catch (e) {
    // Notion could not be reached before anything was written: carry on from the record
    if (!rules.notionOut(e)) throw e;
    return await askWithNotionDown(env, n, method, name, list, e, hooks);
  }
}

async function newShootAskNormal(env, n, method, name, list, hooks = {}) {
  const deps = await (hooks.depsFor || depsFor)(env, n, name, { write: method === "run_new_shoot" });
  if (method === "run_new_shoot" && typeof env.ASK_PROGRESS === "function") deps.progress = env.ASK_PROGRESS;
  if (method === "new_shoot_form") return await rules.newShootForm(deps, name);
  const form = isObject(list[1]) ? list[1] : {};
  if (method === "plan_new_shoot") return await rules.planAnswer(deps, name, form);
  if (method === "run_new_shoot") {
    // One move at a time (bigmoves.js): a Wrap, Archive or Rename running on
    // this project holds New Shoot back until it is done.
    const row = await projectRow(n, name);
    if (row) {
      const { keyOfPage } = await import("./projectid.js");
      const { busyWords } = await import("./bigmoves.js");
      const busy = busyWords(await readJson(env, `r/${await keyOfPage(env, row.id)}/record.json`));
      if (busy) return { ok: false, why: busy, report: busy };
    }
    return await rules.runAnswer(deps, name, form);
  }
  throw new Handoff("not a New Shoot ask");
}

/** The asks answered here right now, for the phone's list. */
export async function listed(env) {
  return (await readiness(env)).ok ? ["new_shoot_form", "plan_new_shoot", "run_new_shoot"] : [];
}

/** The look: the form, and with a form the plan, as the phone would get them.
 * Writes nothing, switch or no switch (Shotlister is asked with `preview`). */
export async function look(env, said) {
  const ready = await readiness(env);
  const base = { on: ready.on, ready: ready.ok, ...(ready.ok ? {} : { why_not: ready.why }) };
  if (!cloudReady(env)) return { ok: false, why: "the server has no Notion key", ...base };
  const name = String((said && said.name) || "");
  if (!name) return { ok: false, why: "Say the project's name.", ...base };
  const n = notionOf(env);
  try {
    const deps = await depsFor(env, n, name, { write: false });
    const form = await rules.newShootForm(deps, name);
    const out = { ok: true, form, ...base };
    if (isObject(said.form)) out.plan = await rules.planAnswer(deps, name, said.form);
    return out;
  } catch (e) {
    if (e instanceof Handoff) return { ok: false, why: `Notion refused: ${e.message}`, ...base };
    return { ok: false, why: String((e && e.message) || e).slice(0, 300), ...base };
  }
}
