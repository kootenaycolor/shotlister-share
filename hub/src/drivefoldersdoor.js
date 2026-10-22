/**
 * **The ways in to the Drive folders** (drivefolders.js, stage 3 step 6):
 * the phone's two asks the server answers itself once the switch is on, and
 * the Studio doors — the switch, a look that writes nothing, and a run.
 *
 * - `create_showcase(name, status)` — the whole ask is Drive folders, so it
 *   is answered here, in the Mac's one sentence.
 * - `create_project(form)` — answered here only when every part of it is
 *   Drive folders: a quick job (no Notion row) with no media drive. A Tier-1
 *   project, or a media drive, is New Project's own (newprojectdoor.js, its
 *   own switch; it comes here for the rest) or else the Mac's: one ask cannot
 *   be split — the Mac refuses a project whose Drive folder is already there.
 * - `run_new_shoot` stays the Mac's: its Notion rows, spec sheet copy,
 *   Shotlister door and portal refresh are not on the server. Its Drive half
 *   is here (`planShoot`), for the look and the run door, ready for when they
 *   are.
 *
 *   GET  /console/studio/drivefolders        { on, roots, scratch, ready, why, signin }
 *   PUT  /console/studio/drivefolders        { on, by, roots?, scratch?, template? }
 *   POST /console/studio/drivefolders/look   { kind: project|shoot|showcase, name, … } — the plan
 *                                            and what is already there; writes nothing
 *   POST /console/studio/drivefolders/run    the same, made — only with the switch on and
 *                                            GDRIVE_WRITE; for a project, after its Notion row
 *                                            exists, with the row's Drive Folder link
 */

import { Handoff, projectRow, notionOf, cloudReady, bareId, plainTitle } from "./cloud.js";
import * as rules from "./drivefolders.js";
import { driveApi, DriveRefused } from "./drivewrite.js";

const SHOOTS = "feedface-0000-4000-8000-000000000002";
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);

/** The switch, its settings, and whether the server makes the folders now. */
export async function state(env) {
  const settings = await rules.settingsOf(env);
  const ready = rules.readiness(env, settings);
  return { settings, ...ready };
}

/** The asks answered here right now, for the phone's list. `create_project`
 * is never listed: only part of it can be answered here. */
export async function listed(env) {
  const s = await state(env);
  return s.ok ? ["create_showcase"] : [];
}

const props = (row) => (row && row.properties) || {};
const urlOf = (row) => (props(row)["Drive Folder"] || {}).url || "";
const selectOf = (row, name) => ((props(row)[name] || {}).select || {}).name || "";
const datesOf = (row) => (((props(row)["Shoot Dates"] || {}).date) || {});

/** The project's Shoots rows, each with its number (`shoots.project_shoots`). */
async function shootRows(n, row) {
  if (!row) return [];
  const { shootNumber } = await import("./projectpage.js");
  const out = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${SHOOTS}/query`, {
      filter: { property: "Project", relation: { contains: row.id } }, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}),
    });
    for (const p of got.results || []) {
      const title = plainTitle(p.properties || {});
      out.push({ id: p.id, title, n: shootNumber(title) });
    }
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/** What a shoot's Drive half needs to know, from Notion as it is now. */
async function shootFacts(n, row, name, said) {
  return {
    name, status: selectOf(row, "Status"), dates: String(datesOf(row).start || "").slice(0, 10),
    drive_url: urlOf(row), rows: await shootRows(n, row), ...(Number(said.n) ? { n: Number(said.n) } : {}),
  };
}

// ── the asks ────────────────────────────────────────────────────────────────

async function writer(env) {
  const s = await state(env);
  if (!s.ok) throw new Handoff(s.why);
  const api = driveApi(env, { write: true });
  if (!api || !api.mkdir) throw new Handoff("the server has no Google sign-in that can make folders");
  return { settings: s.settings, api };
}

/** A refusal from Google before anything was made is the Mac's to do instead. */
function handOn(e) {
  const cause = e instanceof DriveRefused ? e : e && e.cause;
  if (cause instanceof DriveRefused && !(e.made && e.made.length)) throw new Handoff(cause.message);
  throw e;
}

/** backend.create_showcase — answers the Mac's sentence. */
export async function createShowcase(env, n, [name, status]) {
  const { settings, api } = await writer(env);
  const row = await projectRow(n, name);
  try {
    const got = await rules.showcaseAsk(api, settings, String(name || ""), String(status || ""), urlOf(row));
    return got.said;
  } catch (e) {
    return handOn(e);
  }
}

/** backend.create_project, for the asks that are all Drive folders. */
export async function createProject(env, n, args) {
  return (await quickJobMade(env, n, args)).said;
}

/** The same, with the new folder's link (step5birth.js writes it on the Job's record). */
export async function quickJobMade(env, n, [form]) {
  const f = isObject(form) ? form : {};
  const tier1 = f.tier1 === undefined ? true : Boolean(f.tier1);
  if (tier1) throw new Handoff("the Mac makes a project's Notion row");
  if (String(f.volume || "").trim()) throw new Handoff("the Mac makes the media drive's folders");
  if (String(f.film_path || "").trim() || f.finder_sidebar) throw new Handoff("the Mac links a film and the Finder sidebar");
  const { settings, api } = await writer(env);
  try {
    const got = await rules.projectFolders(api, settings, { ...f, tier1: false });
    return { said: got.plan.said, url: got.url };
  } catch (e) {
    return handOn(e);
  }
}

// ── the doors ───────────────────────────────────────────────────────────────

/** The look: what each kind would make, and what is there. Writes nothing. */
export async function look(env, said) {
  const s = await state(env);
  const api = driveApi(env, { write: false });
  const base = { on: s.settings.on, ready: s.ok, ...(s.ok ? {} : { why_not: s.why }), signin: api ? api.secret : "" };
  if (!api) return { ok: false, why: "the server has no Google sign-in to read the Drive with", ...base };
  if (!s.settings.scratch && Object.keys(s.settings.roots).length < 3) return { ok: false, why: "the Drive's root folders are not set", ...base };
  const kind = String(said.kind || "");
  const name = String(said.name || "");
  const n = cloudReady(env) ? notionOf(env) : null;
  try {
    const row = n && name ? await projectRow(n, name) : null;
    if (kind === "project") {
      const form = { ...(isObject(said.form) ? said.form : {}), name: (isObject(said.form) && said.form.name) || name };
      const plan = rules.shown(await rules.planProject(api, s.settings, form));
      if (plan.ok && plan.tier1) plan.notion = row ? { page: bareId(row.id), drive_folder: urlOf(row) || null } : { page: null, why: "no Notion row for this project yet" };
      return { ...plan, ...base };
    }
    if (kind === "shoot") {
      if (!n) return { ok: false, why: "the server has no Notion key", ...base };
      if (!row) return { ok: false, why: `No Notion row for ${name}`, ...base };
      return { ...rules.shown(await rules.planShoot(api, s.settings, await shootFacts(n, row, name, said))), ...base };
    }
    if (kind === "showcase") {
      const status = said.status !== undefined ? String(said.status) : selectOf(row, "Status");
      return { ...rules.shown(await rules.planShowcase(api, s.settings, { name, status, drive_url: urlOf(row) })), status, ...base };
    }
  } catch (e) {
    return { ok: false, why: String((e && e.message) || e).slice(0, 300), ...base };
  }
  return { ok: false, why: "Say kind: project, shoot or showcase.", ...base };
}

/** The run: the same, made. A project's Drive half needs its Notion row. */
export async function run(env, said) {
  const s = await state(env);
  if (!s.ok) return { ok: false, why: s.why };
  const api = driveApi(env, { write: true });
  if (!api || !api.mkdir) return { ok: false, why: "the server has no Google sign-in that can make folders" };
  if (!cloudReady(env)) return { ok: false, why: "the server has no Notion key" };
  const kind = String(said.kind || "");
  const name = String(said.name || "");
  const n = notionOf(env);
  try {
    if (kind === "project") {
      const form = { ...(isObject(said.form) ? said.form : {}), name: (isObject(said.form) && said.form.name) || name };
      const tier1 = form.tier1 === undefined ? true : Boolean(form.tier1);
      const row = tier1 ? await projectRow(n, String(form.name).trim()) : null;
      if (tier1 && !row) return { ok: false, why: "no Notion row for this project" };
      const got = await rules.projectFolders(api, s.settings, { ...form, tier1 });
      const out = { ok: true, kind, said: got.plan.said, made: got.made, folder: got.url };
      if (row) {
        const link = rules.linkPlan(row, got.url);
        if (link.write) await n.patch(`pages/${row.id}`, { properties: { "Drive Folder": { url: got.url } } });
        out.notion = link.said;
      }
      return out;
    }
    if (kind === "shoot") {
      const row = await projectRow(n, name);
      if (!row) return { ok: false, why: `No Notion row for ${name}` };
      const got = await rules.shootFolderMake(api, s.settings, await shootFacts(n, row, name, said));
      return { ok: !got.failed.length, kind, n: got.plan.n, made: got.made, already: got.already, failed: got.failed, notes: got.plan.notes };
    }
    if (kind === "showcase") {
      const row = await projectRow(n, name);
      const status = said.status !== undefined ? String(said.status) : selectOf(row, "Status");
      const got = await rules.showcaseAsk(api, s.settings, name, status, urlOf(row));
      return { ok: true, kind, said: got.said, made: got.made };
    }
  } catch (e) {
    return { ok: false, why: String((e && e.message) || e).slice(0, 500), ...(e && e.made ? { made: e.made } : {}) };
  }
  return { ok: false, why: "Say kind: project, shoot or showcase." };
}
