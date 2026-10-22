/**
 * **New Project or Job, as step 5 makes them** (stage 5 step 5, 2026-10-15).
 *
 * The sheet now asks Kind first (Project or Job), then Type, then which modes
 * and which systems (his answers 7-13). `create_project(form)` takes three
 * more things, read here:
 *
 *   form.job    true = a Job: any Type, no Notion Projects row, its Drive
 *               folder in gigs/, its record of kind "job", every mode off
 *               unless switched on in the sheet
 *   form.modes  the mode keys switched on (a Project); kept on the record as
 *               only the differences from its Type's standard (studiomodes.js)
 *   form.setup  {drive, notion, portal, media}: media off drops the drive;
 *               notion off makes a Project with no Notion row; drive cannot
 *               be off yet; portal is not made at birth (the console asks
 *               create_portal after, as it does today)
 *
 * **Behind its own switch, `step5birth`** (`s/step5birth.json`), off until
 * thrown: while off, create_project is exactly what it was (a `job` or
 * `setup` in the form is not read), so the Mac's and the phone's sheets keep
 * working. Only the record's birth is new; the Drive folder and the Notion
 * row are made by the same code as before.
 *
 *   GET /console/studio/step5birth   {on, at, by}
 *   PUT /console/studio/step5birth   {on, by}
 */

import { standardOf, modesValue, modesAfter, MODES, typeKey, loadStandards } from "./studiomodes.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/step5birth.json";
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const PAGE = /^[0-9a-f]{32}$/;

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

export async function birthOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setBirthSwitch(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

/** The Types' starting modes, for New Project's sheet. */
export function modesStandard(types) {
  const out = {};
  for (const t of types) out[t] = standardOf(t);
  return out;
}

const truthy = (v) => v === true || v === 1 || v === "1" || v === "true" || v === "on";

/**
 * The form as step 5 reads it: `{form, job, modes, setup, why}`. `form` is
 * what the existing New Project code is given (a Job as a quick job in
 * gigs/; media off as no drive; notion off as no row). `why` refuses.
 */
export function readBirth(raw) {
  const f = isObject(raw) ? { ...raw } : {};
  const job = truthy(f.job);
  const s = isObject(f.setup) ? f.setup : {};
  const setup = {
    drive: s.drive === undefined ? true : truthy(s.drive),
    notion: job ? false : (s.notion === undefined ? ("tier1" in f ? truthy(f.tier1) : true) : truthy(s.notion)),
    portal: s.portal === undefined ? !job : truthy(s.portal),
    media: s.media === undefined ? Boolean(String(f.volume || "").trim()) : truthy(s.media),
  };
  if (!setup.drive) return { why: "A Drive folder is always made." };
  const form = { ...f };
  delete form.modes; delete form.setup;
  // The Kind stays said, when it was: a Job's Drive folder is loose
  // (drivefolders.planProject; an older sheet's quick job is read there as the Mac reads it).
  if ("job" in f) form.job = job;
  form.tier1 = setup.notion;
  if (job) form.home = "gigs";
  if (!setup.media) form.volume = "";
  // The modes: what was switched on, with Schedule bringing Shot List (the
  // rule between them); else a Project its Type's, a Job none (his answer 11:
  // a Job starts with every mode off, and he may switch some on at birth).
  const type = String(f.type || "");
  let modes = job ? [] : null;
  if (Array.isArray(f.modes)) {
    const asked = f.modes.map(String);
    const bad = asked.filter((m) => !MODES.includes(m));
    if (bad.length) return { why: `No such mode: ${bad.join(", ")}.` };
    let on = [];
    for (const m of MODES) if (asked.includes(m)) on = modesAfter(on, m, true).modes;
    modes = on;
  }
  return { form, job, type, modes, setup };
}

/** The record's `modes` value at birth: only where it differs from the Type's standard. */
export function birthModes(type, job, modes) {
  if (modes === null) return null;
  const value = modesValue(standardOf(type, job), modes);
  return Object.keys(value).length ? value : null;
}

/**
 * What the record is given at birth, written nothing: `{kind, facts}`. A
 * project with a Notion row has its record begun by New Project and its
 * facts carried in by the Notion link, so only `modes`; a record with no
 * Notion row is given its Type, Drive folder, dates and stage here.
 */
export function birthPlan(b, { page = "", url = "" } = {}) {
  const facts = {};
  if (!page) {
    if (b.type) facts.type = typeKey(b.type) || b.type;
    if (url) facts.drive_folder = url;
    const start = String(b.form.date_start || "").slice(0, 10);
    const end = String(b.form.date_end || "").slice(0, 10);
    if (start) facts.shoot_dates = end && end !== start ? `${start}/${end}` : start;
    facts.status = ["Development", "Active"].includes(String(b.form.status || "").trim()) ? String(b.form.status).trim() : "Development";
  }
  const modes = birthModes(b.type, b.job, b.modes);
  if (modes) facts.modes = modes;
  return { kind: b.job ? "job" : "project", facts };
}

/**
 * The record, born: begun under the project's one ID when it has no Notion
 * row (New Project begins it when it has one), its kind set, its facts
 * written through the one door. Answers `{ok, key, line}`; never throws —
 * the folder and the row are made already, so a record that could not be
 * made is said, not raised.
 */
export async function bear(env, b, { page = "", url = "" } = {}, deps = {}) {
  await loadStandards(env);
  try {
    const plan = birthPlan(b, { page, url });
    let key = "";
    if (page && PAGE.test(page)) {
      const { resolveProject } = await import("./projectid.js");
      key = (await resolveProject(env, page)).key;
      if (!key) return { ok: false, line: "Record: not found after the Notion row was made." };
    } else {
      const { oneIdOn } = await import("./projectid.js");
      if (!(await oneIdOn(env)).on) return { ok: false, line: "Record: not made (one ID is off)." };
      const { beginMinted } = await import("./oneiddoor.js");
      const got = await beginMinted(env, { id: String(b.form.id || ""), name: String(b.form.name || "").trim(), by: "server" });
      key = got.key;
      await setKind(env, key, plan.kind);
    }
    const record = await readJson(env, `r/${key}/record.json`);
    const have = (record && record.facts) || {};
    // The modes are read against the Type: a project's record gets its Type
    // now too, if the Notion link has not carried it in yet (the same words
    // as the row, so the link finds nothing to ask).
    if (page && b.type && !isObject(have.type) && !("type" in plan.facts)) plan.facts.type = typeKey(b.type) || b.type;
    if (Object.keys(plan.facts).length) {
      const write = deps.writeFacts || (async (k, changes, who) => (await import("./facts.js")).writeFacts(env, k, changes, who));
      const changes = {};
      for (const [k, value] of Object.entries(plan.facts)) changes[k] = { value, base: isObject(have[k]) ? Number(have[k].v) || 0 : 0 };
      const wrote = await write(key, changes, "server");
      if (!wrote || wrote.status !== 200) return { ok: false, key, line: `Record: begun, facts not written — ${(wrote && wrote.problem) || "?"}` };
    }
    return { ok: true, key, line: b.job ? "Job record made" : "" };
  } catch (e) {
    return { ok: false, line: `Record: ${String((e && e.message) || e).slice(0, 200)}` };
  }
}

/** The record's own `kind`, compare-and-set (a record has only one writer at birth). */
async function setKind(env, key, kind) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const got = await env.BUCKET.get(`r/${key}/record.json`);
    if (!got) return false;
    const record = await got.json();
    if (record.kind === kind) return true;
    const saved = await env.BUCKET.put(`r/${key}/record.json`, JSON.stringify({ ...record, kind }), {
      httpMetadata: { contentType: "application/json" }, onlyIf: { etagMatches: got.etag },
    });
    if (saved) return true;
  }
  return false;
}

export async function birthDoor(env, rest, method, read) {
  if (rest[0] !== "step5birth" || rest.length !== 1) return null;
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (method === "GET") return reply(await birthOn(env));
  if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
  let said;
  try { said = await read(); } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
  return reply(await setBirthSwitch(env, isObject(said) ? said : {}));
}
