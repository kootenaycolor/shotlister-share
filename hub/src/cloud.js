/**
 * **The server answers the phone itself** (2026-10-10, his ask: "nothing
 * film-related relies on the Mac Studio"). Stage 1 of moving Projects Console
 * off the Mac — Shotlister Work row "Projects Console without the Mac".
 *
 * The phone puts every call it would have made on the Mac into the Studio
 * mailbox (studio.js). Until now every one waited for the Mac to claim it, so
 * with the Mac off a shoot's dates or a spec sheet could not be changed from
 * the phone at all. The calls that only touch Notion are answered **here, the
 * moment they arrive**, and never reach the Mac; everything else waits for it
 * exactly as before. The phone cannot tell the difference — same method, same
 * arguments, same answer in the same shape — so no iPhone build is needed.
 *
 * **Each is the Python one ported, rule for rule**, and names it: `backend.py`
 * for the door, `shoots.py` for the compare-and-set edits (what the screen
 * showed is checked against Notion first, and a field that moved is answered
 * as `moved`, never overwritten), `entries.py` and `lenses.py` for the text.
 * Change a rule there and change it here in the same breath.
 *
 * **The key.** `NOTION_TOKEN`, the portal's own Notion connection. It was made
 * read-only (Ref 1155); for this it needs Update and Insert content, and the
 * Shoots database connected. **Until it has them nothing breaks**: a refusal
 * from Notion before anything is written hands the ask on to the Mac
 * (`Handoff`), the way it went before this file existed.
 */

import { notionIn, notionOut, canonStage } from "./stageword.js";   // Notion says "Complete"; the record "Released"
import { LUT_FILES, LUT_LABELS, formatEntry, writeEntries, lutFiles, lutKey, lutLabelsText, lutsPlan, fieldText, pillsOf, bodiesOf, labelsOf } from "./entries.js";
import { writeSets, lensPills } from "./lenses.js";
import { keepCameraLabels } from "./kit.js";
import { gather, projectOf, hideChecks, setHiddenIn, showHiddenIn } from "./projectpage.js";
import { creditsOf } from "./credits.js";
import { STEP6_METHODS, step6Now, step6Answer } from "./step6.js";
import { METHODS as BIGMOVE_METHODS, bigmovesNow, bigmoveAnswer } from "./bigmoves.js";

const API = "https://api.notion.com/v1/";
const NOTION_VERSION = "2025-09-03";
/** Camera Spec Sheets' data source (its fields are pills since 2026-10-13). */
const SPEC_SOURCE = "feedface-0000-4000-8000-000000000003";
const PROJECTS = "feedface-0000-4000-8000-000000000001";
const CREW = "feedface-0000-4000-8000-000000000004";

/** The calls answered here. Anything else is the Mac's. */
export const CLOUD_METHODS = new Set([
  "set_stage", "set_project_website", "fact_choices", "spec_adopt",
  "edit_shoot", "edit_project_dates", "edit_spec_sheet",
  "edit_entries", "edit_lens_sets", "edit_lut_labels", "edit_luts",
  "crew_directory", "crew_dupes", "crew_edit", "crew_new", "company_new", "project_crew_url",
  "project_page", "next_check_hide", "next_check_show",
  "portal_down", "portal_link", "portal_visible", "portal_general_access",
  "refresh_portal", "create_portal", "set_document_on_portal",
  // Share, What Viewers See and the Library (cloudportal.js, 2026-10-13)
  "portal_people", "portal_invite", "portal_set_role", "portal_password", "portal_replace_link",
  "portal_viewers", "portal_viewers_set", "portal_library", "portal_library_set",
  // Link on a suggestion and Look Again (cloudlink.js, 2026-10-13); a film
  // to link, or the Mac awake, is still the Mac's.
  "link_suggestion", "project_dossier",
  "mirror_facts", "mirror_director", "mirror_mark",
  // stage 3 step 5: Customize Record (writes only once its switch is on) and
  // Suggestions (read only; the Mac's when it needs the Mac's disk)
  "set_project_layout", "project_suggestions",
  // The Mac's last read of a drive (drivelists.js); a plugged-in drive with
  // the Mac awake is still handed on to the Mac.
  "drive_tree",
  // A film made on the relay (newfilm.js) — only once its switch is on;
  // until then the Mac's, and not listed to the phone (`cloudMethodsNow`).
  "new_film",
  // Google Drive folders (drivefolders.js, stage 3 step 6) — only once its
  // switch is on and the server has a sign-in that can make folders; a
  // Tier-1 New Project is the server's only once its own switch is on too
  // (newproject.js, stage 4 part B), else the Mac's.
  "create_showcase", "create_project", "new_project_options",
  // A project's facts, credits, links and their history (cloudfacts.js,
  // group 2): the record is the server's, so these never needed the Mac.
  "project_facts", "set_project_facts", "settle_facts", "project_history",
  "set_project_credits", "add_custom_link", "remove_custom_link",
  // New Shoot (newshoot.js, stage 4 part A) — only once its switch is on and
  // the server can make Drive folders; until then the Mac's, and not listed.
  "new_shoot_form", "plan_new_shoot", "run_new_shoot",
  // Film backups (filmbackuprun.js, stage 4 part C) — only once its switch
  // is on; until then `backup.sh` on the Mac, and not listed to the phone.
  // `film_restore` stays the Mac's: it puts a film on the Mac's Desktop.
  "film_backup", "film_backups",
  // The one list (onelist.js, stage 5 step 3): the project list, card and
  // films shelf from the records and Notion; the Mac lays its drives on top.
  "project_list", "films_shelf",
  // A project's Studio modes (projectmodes.js, stage 5 step 5): read always;
  // a change only while the `studiomodes` switch is on (refused in its words).
  "project_modes", "set_project_mode",
  // A project's mods (studiomods.js, 2026-10-17): read with project_modes.
  "set_project_mod",
  // The portal's Shared switch and its status line, by project ID
  // (portalmodes.js, stage 5 step 5); Shared refuses while its switch is off.
  "portal_shared", "portal_state",
  // Step 6 (step6.js): each listed only while its group's switch is on.
  ...STEP6_METHODS,
  // Step 7 (bigmoves.js): Wrap, Archive, Move Drive, Rename, Turn Off,
  // Delete and Prepare Showcase — listed while any move's switch is on; a
  // move whose own switch is off is handed back to the Mac.
  ...BIGMOVE_METHODS,
  // The Mac jobs list (macjobs.js, stage 5 step 7): listed only while its switch is on.
  "mac_jobs", "mac_job_retry", "mac_job_cancel", "mac_job_index",
  // Drive files on the portal's Documents page (portaldocs.js, 2026-10-17):
  // the folder to pick from, and his Show on Portal switch.
  "portal_docs", "set_portal_doc",
]);

/** The calls answered here right now, for the phone's list: those behind a
 * switch only while it is on. */
export async function cloudMethodsNow(env) {
  const out = [...CLOUD_METHODS].sort();
  // Every switch is its own small read: asked all at once, not one after the
  // other (each read waited on the last; about a second on every call).
  const [nf, dfd, npd, pid, shoot, fbr, mj] = await Promise.all([
    import("./newfilm.js"), import("./drivefoldersdoor.js"), import("./newprojectdoor.js"),
    import("./projectid.js"), import("./newshootdoor.js"), import("./filmbackuprun.js"), import("./macjobs.js"),
  ]);
  const [dfListed, npListed, filmOn, idOn, shootListed, backups, sixNow, bigNow, mjOn] = await Promise.all([
    dfd.listed(env), npd.listed(env), nf.newFilmOn(env), pid.oneIdOn(env), shoot.listed(env),
    fbr.backupsOn(env), step6Now(env), bigmovesNow(env), mj.macJobsOn(env),
  ]);
  const drive = new Set(dfListed);
  for (const m of npListed) drive.add(m);
  const off = new Set(["create_showcase", "create_project", "new_project_options"].filter((m) => !drive.has(m)));
  if (!filmOn.on && !idOn.on) off.add("new_film");
  if (!shootListed.length) for (const m of ["new_shoot_form", "plan_new_shoot", "run_new_shoot"]) off.add(m);
  if (!backups) { off.add("film_backup"); off.add("film_backups"); }
  const six = new Set(sixNow);
  for (const m of STEP6_METHODS) if (!six.has(m)) off.add(m);
  const big = new Set(bigNow);
  for (const m of BIGMOVE_METHODS) if (!big.has(m)) off.add(m);
  if (!mjOn.on) for (const m of mj.CLOUD) off.add(m);
  return out.filter((m) => !off.has(m));
}

/** The portal's switches (cloudportal.js), each needing the project's row. */
const PORTAL = new Set(["portal_down", "portal_link", "portal_visible", "portal_general_access",
  "refresh_portal", "create_portal", "set_document_on_portal",
  "portal_people", "portal_invite", "portal_set_role", "portal_password", "portal_replace_link",
  "portal_viewers", "portal_viewers_set", "portal_library", "portal_library_set"]);
/** Of those, the ones that only read: nothing on the record moves. */
const PORTAL_READS = new Set(["portal_people", "portal_viewers", "portal_library"]);

/** The record's own facts (cloudfacts.js). */
const FACTS = new Set(["project_facts", "set_project_facts", "settle_facts", "project_history",
  "set_project_credits", "add_custom_link", "remove_custom_link"]);

/** Edits whose result the project's record shows (its stage, dates, website):
 * the record is looked at again at once (recordlive.js). */
// set_stage and set_project_website are record edits now (2026-10-15): they look
// again themselves, and only when they had to write Notion for want of a record.
const AFTER_EDIT = new Set(["run_new_shoot"]);

async function liveAfter(env, page) {
  try {
    const { liveAfterEdit } = await import("./recordlive.js");
    await liveAfterEdit(env, page);
  } catch (e) {
    console.error("record live:", String((e && e.stack) || e));
  }
}

/** Let the Notion link look at this project now, after the answer has gone
 * (`ctx.waitUntil`), so Notion has a record edit in seconds rather than at the
 * minute's look. Never waited for; with no way to run beside the reply the
 * minute's look does it. */
export async function followSoon(env, ctx, page) {
  if (!ctx || typeof ctx.waitUntil !== "function") return;
  ctx.waitUntil((async () => {
    try {
      const { kickNotion } = await import("./cloudfacts.js");
      await kickNotion(env, page);
    } catch (e) {
      console.error("follow soon:", String((e && e.message) || e));
    }
  })());
}

/** Notion said no before anything was written: the Mac's to do instead. */
export class Handoff extends Error {}

/** The Project Docs row's Hub box with Notion out of reach (2026-10-20, his
 * #8): kept on Notion's waiting list and made the first time Notion answers;
 * the portal follows on its next refresh. Null when Notion answers (the usual
 * road, cloudportal.js), or for a refused key (the Mac's, by Handoff). */
async function documentOnPortal(n, [name, docId, on], env) {
  if (!docId) return null;
  try {
    await projectRow(n, name);
    return null;
  } catch (e) {
    const { notionDown, addWait, QUIET } = await import("./notionwaits.js");
    if (e instanceof Handoff || !notionDown(e)) throw e;
    const page = await fastPage(env, name);
    if (!page) throw e;
    await addWait(env, { kind: "doc-hub", project: page, page: bareId(docId), status: on ? "on" : "off", label: name, by: "console" });
    return { ok: true, on: Boolean(on), portal: false, waits: QUIET, why: "" };
  }
}

export function cloudReady(env) {
  return Boolean(env && typeof env.NOTION_TOKEN === "string" && env.NOTION_TOKEN.trim());
}

export function apiOf(env) {
  // Only a stand-in on this machine, for the checks (`hub/cloudasks.mjs`).
  const said = String(env.NOTION_API || "");
  return /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/v1\/$/.test(said) ? said : API;
}

export function notionOf(env) {
  const key = env.NOTION_TOKEN.trim();
  const base = apiOf(env);
  let wrote = false;
  async function call(path, method = "GET", body) {
    const got = await fetch(base + path, {
      method,
      headers: { authorization: `Bearer ${key}`, "notion-version": NOTION_VERSION, "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(notionOut(body)),
    });
    let answer = null;
    try { answer = notionIn(await got.json()); } catch { answer = null; }
    if (!got.ok || !answer || answer.object === "error") {
      const code = (answer && answer.code) || String(got.status);
      // The connection has no right to this page, or cannot write: nothing
      // happened yet, so the Mac (whose key can) is asked as before.
      if (!wrote && (got.status === 401 || got.status === 403 || got.status === 404
          || code === "restricted_resource" || code === "unauthorized" || code === "object_not_found")) {
        throw new Handoff(code);
      }
      throw new Error(`Notion: ${code}${answer && answer.message ? ` — ${String(answer.message).slice(0, 160)}` : ""}`);
    }
    if (method !== "GET" && !path.endsWith("/query")) wrote = true;
    return answer;
  }
  return {
    get: (path) => call(path),
    patch: (path, body) => call(path, "PATCH", body),
    post: (path, body) => call(path, "POST", body),
    // The Notion link's Story section takes its own blocks out (notionsync.js).
    del: (path) => call(path, "DELETE"),
  };
}

// ── reading a page, as engine.py reads one ───────────────────────────────────

export const words = (rich) => (rich || []).map((t) => t.plain_text || "").join("");
const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
export const same = (a, b) => squash(a) === squash(b);
export const bareId = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

export function plainTitle(props) {
  for (const p of Object.values(props || {})) if (p && p.type === "title") return words(p.title);
  return "?";
}
const propText = (props, name) => words(((props || {})[name] || {}).rich_text);
const relationIds = (props, name) => new Set((((props || {})[name] || {}).relation || []).map((r) => bareId(r.id)));

/** Plain text as Notion rich text, under the 2000-character cap — `_rich`. */
export function rich(text) {
  const s = String(text || "");
  const out = [];
  for (let i = 0; i < s.length; i += 1900) out.push({ type: "text", text: { content: s.slice(i, i + 1900) } });
  return out;
}

/** The project's Notion row, by the name the phone shows — `_project_row`. */
export async function projectRow(n, name) {
  const want = String(name || "");
  if (!want) return null;
  const got = await n.post(`data_sources/${PROJECTS}/query`, {
    filter: { property: "Project", title: { equals: want } }, page_size: 10,
  });
  return (got.results || []).find((p) => plainTitle(p.properties) === want) || null;
}

// ── shoots.py: dates, names, the compare-and-set plans ───────────────────────

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;
const NUMBER = /\bShoot\s+(\d+)\b/i;
const NAME_SEP = " · ";
const DEFAULT_WORDS = /^(?:principal|additional shoot(?:\s+\d+)?|shoot(?:\s+\d+)?)$/i;
const EDGES = " \t·:—–-|,";

function strip(s, chars) {
  let a = 0, b = s.length;
  while (a < b && chars.includes(s[a])) a += 1;
  while (b > a && chars.includes(s[b - 1])) b -= 1;
  return s.slice(a, b);
}

export function datePropOf(start, end) {
  const s = String(start || "").slice(0, 10), e = String(end || "").slice(0, 10);
  if (!s) return { date: null };
  return { date: e && e !== s ? { start: s, end: e } : { start: s } };
}

export function checkDays(start, end) {
  for (const d of [start, end]) if (d && !ISO_DAY.test(d.slice(0, 10))) return `“${d}” isn't a day (YYYY-MM-DD).`;
  if (end && !start) return "An end day needs a first day.";
  if (start && end && end.slice(0, 10) < start.slice(0, 10)) return "The last day is before the first.";
  return "";
}

export function datesOf(props, column) {
  const when = ((props || {})[column] || {}).date || {};
  const start = String(when.start || "").slice(0, 10);
  return [start, String(when.end || "").slice(0, 10) || start];
}

function restOf(title) {
  for (const dash of [" — ", " – ", " - "]) {
    const at = (title || "").indexOf(dash);
    if (at >= 0) return [title.slice(0, at), dash, title.slice(at + dash.length)];
  }
  return ["", "", title || ""];
}

/** The shoot's own name in a Shoots row title — `name_of`. */
export function nameOf(title) {
  const [, dash, r] = restOf(title);
  let rest = r;
  if (DEFAULT_WORDS.test(strip(squash(rest), EDGES))) return "";
  if (!dash) {
    const m = NUMBER.exec(rest);
    if (m) rest = rest.slice(m.index + m[0].length);
  }
  const m = /\(?\bShoot\s+\d+\b\)?/i.exec(rest);
  if (m) rest = `${rest.slice(0, m.index)} ${rest.slice(m.index + m[0].length)}`;
  const name = strip(squash(rest), EDGES);
  return !name || DEFAULT_WORDS.test(name) ? "" : name;
}

export function cleanName(name) {
  const s = strip(squash(name), EDGES);
  return DEFAULT_WORDS.test(s) ? "" : s.slice(0, 80);
}

export function nameProblem(name) {
  if (NUMBER.test(cleanName(name))) return "Leave out “Shoot N”. The number is kept for you.";
  if (String(name || "").includes("\n")) return "A name is one line.";
  return "";
}

export function titled(title, name, projectName = "") {
  let [pre, dash, rest] = restOf(title);
  pre = pre || projectName;
  dash = dash || " — ";
  const m = NUMBER.exec((title || "").includes(dash) ? rest : (title || ""));
  const base = m ? `Shoot ${m[1]}` : "";
  const clean = cleanName(name);
  if (!base && !clean && !nameOf(title)) return title;
  const tail = base && clean ? `${base}${NAME_SEP}${clean}` : (base || clean || "Shoot");
  return pre ? `${pre}${dash}${tail}` : tail;
}

/** [patch, moved, why] — `shoot_edit_plan`. */
export function shootEditPlan(props, seen, changes) {
  const [start, end] = datesOf(props, "Dates");
  const title = plainTitle(props);
  const now = { start, end, notes: propText(props, "What Changes"), name: nameOf(title) };
  const unknown = Object.keys(changes).filter((k) => !(k in now)).sort();
  if (unknown.length) return [{}, {}, `A shoot's ${unknown.join(", ")} isn't edited here.`];
  const saw = { ...seen };
  if ("end" in saw && !saw.end) saw.end = "start" in saw ? saw.start : start;
  const moved = {};
  for (const f of Object.keys(changes)) if (f in saw && !same(now[f], saw[f])) moved[f] = now[f];
  if (Object.keys(moved).length) return [{}, moved, ""];
  const patch = {};
  if ("start" in changes || "end" in changes) {
    const s = String(("start" in changes ? changes.start : start) || "");
    const e = String(("end" in changes ? changes.end : (!("start" in changes) || end !== start ? end : "")) || "");
    const why = checkDays(s, e);
    if (why) return [{}, {}, why];
    if (s.slice(0, 10) !== start || (e.slice(0, 10) || s.slice(0, 10)) !== end) patch.Dates = datePropOf(s, e);
  }
  if ("notes" in changes && !same(changes.notes, now.notes)) patch["What Changes"] = { rich_text: rich(String(changes.notes || "")) };
  if ("name" in changes) {
    const why = nameProblem(changes.name);
    if (why) return [{}, {}, why];
    const want = cleanName(changes.name);
    if (want !== now.name) {
      const key = Object.keys(props).find((k) => (props[k] || {}).type === "title") || "Shoot";
      patch[key] = { title: rich(titled(title, want)) };
    }
  }
  return [patch, {}, ""];
}

/** [patch, moved, why] for a project's Shoot Dates — `project_dates_plan`. */
function projectDatesPlan(props, seen, start, end) {
  const [s0, e0] = datesOf(props, "Shoot Dates");
  const saw = { ...seen };
  if ("end" in saw && !saw.end) saw.end = "start" in saw ? saw.start : s0;
  const moved = {};
  for (const [k, v] of [["start", s0], ["end", e0]]) if (k in saw && !same(v, saw[k])) moved[k] = v;
  if (Object.keys(moved).length) return [{}, moved, ""];
  const s = String(start || ""), e = String(end || "");
  const why = checkDays(s, e);
  if (why) return [{}, {}, why];
  if (s.slice(0, 10) === s0 && (e.slice(0, 10) || s.slice(0, 10)) === e0) return [{}, {}, ""];
  return [{ "Shoot Dates": datePropOf(s, e) }, {}, ""];
}

/** A sheet field as text, pills one per line (entries.fieldText). */
function specWords(field) {
  return fieldText(field);
}

/** [patch, moved, why] for a Camera Spec Sheet row — `spec_edit_plan`. */
function specEditPlan(props, seen, changes) {
  const patch = {}, moved = {};
  for (let [key, value] of Object.entries(changes)) {
    const field = props[key];
    if (!field || !["rich_text", "number", "multi_select"].includes(field.type)) return [{}, {}, `The spec sheet's “${key}” isn't something this edits.`];
    const now = specWords(field);
    if (field.type === "multi_select") {
      // pills by name, one per line or a list; Notion adds a pill it has not seen.
      // An older screen's words, made pills: a camera without its label (the
      // record keeps that), a typed lens set one lens per pill.
      const tidy = { Camera: bodiesOf, Lenses: lensPills }[key];
      if (tidy) {
        value = tidy(Array.isArray(value) ? value.join("\n") : value);
        if (key in seen && typeof seen[key] === "string") seen = { ...seen, [key]: tidy(seen[key]) };
      }
      const fold = (t) => JSON.stringify(pillsOf(t).map((x) => x.toLowerCase()));
      if (key in seen && fold(now) !== fold(seen[key])) { moved[key] = now; continue; }
      if (JSON.stringify(pillsOf(now)) === JSON.stringify(pillsOf(value))) continue;
      patch[key] = { multi_select: pillsOf(value).map((name) => ({ name })) };
      continue;
    }
    if (key in seen && !same(now, seen[key])) { moved[key] = now; continue; }
    if (same(now, value)) continue;
    if (field.type === "number") {
      const text = String(value == null ? "" : value).trim();
      if (text.includes("\n")) return [{}, {}, `${key} is a number in Notion, so it holds one value.`];
      if (!text) { patch[key] = { number: null }; continue; }
      const num = text.includes(".") ? Number.parseFloat(text) : Number(text);
      if (!/^[+-]?\d+(\.\d*)?$|^[+-]?\.\d+$/.test(text) || Number.isNaN(num)) return [{}, {}, `${key} needs a number, not “${text}”.`];
      patch[key] = { number: num };
    } else {
      patch[key] = { rich_text: rich(String(value == null ? "" : value)) };
    }
  }
  if (Object.keys(moved).length) return [{}, moved, ""];
  return [patch, {}, ""];
}

/** PATCH, read again, and check nothing is left to do — `_write_checked`. */
async function writeChecked(n, pageId, patch, replan) {
  await n.patch(`pages/${pageId}`, { properties: patch });
  const back = await n.get(`pages/${pageId}`);
  if (Object.keys(replan(back.properties || {})).length) throw new Error("Notion did not keep the change — try again");
  return back;
}

const sorted = (o) => Object.keys(o).sort();
const noRow = { ok: false, why: "This project has no Notion row." };

async function editShoot(n, projectId, shootId, seen, changes) {
  const page = await n.get(`pages/${shootId}`);
  const props = page.properties || {};
  if (projectId && !relationIds(props, "Project").has(bareId(projectId))) return { ok: false, why: "That shoot isn't on this project." };
  const [patch, moved, why] = shootEditPlan(props, seen || {}, changes || {});
  if (why) return { ok: false, why };
  if (Object.keys(moved).length) return { ok: false, moved, why: "Changed in Notion since you opened it." };
  if (!Object.keys(patch).length) return { ok: true, changed: [] };
  const old = datesOf(props, "Dates");
  const want = { ...changes };
  await writeChecked(n, shootId, patch, (p) => shootEditPlan(p, {}, want)[0]);
  const out = { ok: true, changed: sorted(patch) };
  if (patch.Dates && projectId) {
    const prow = (await n.get(`pages/${projectId}`)).properties || {};
    const [ps, pe] = datesOf(prow, "Shoot Dates");
    if (ps === old[0] && pe === old[1]) {
      const [ns, ne] = datesOf({ Dates: patch.Dates }, "Dates");
      const [p2] = projectDatesPlan(prow, {}, ns, ne);
      if (Object.keys(p2).length) {
        await writeChecked(n, projectId, p2, (p) => projectDatesPlan(p, {}, ns, ne)[0]);
        out.project_dates = true;
      }
    }
  }
  return out;
}

/** The Shoot Dates fact of the project's record: `null` when the project has
 * no record (the caller writes Notion), else the answer `{ok, changed}` or
 * `{ok:false, moved|why}` in the shapes the Notion way gives. Nothing here
 * reads or writes Notion. An empty start clears the dates; the project's
 * status is never touched. */
async function recordProjectDates(env, page, seen, start, end) {
  const record = await recordOf(env, page);
  if (!record) return null;
  const { splitDates } = await import("./notionlink.js");
  const stored = isObject(record.facts) && isObject(record.facts.shoot_dates) ? record.facts.shoot_dates : null;
  const now = stored && typeof stored.value === "string" ? stored.value : "";
  const [s0, e0r] = splitDates(now);
  const e0 = e0r || s0;
  const s = String(start || "").slice(0, 10), e = String(end || "").slice(0, 10);
  const why = checkDays(s, e);
  if (why) return { ok: false, why };
  // Already as asked (a second Save of the same clear): nothing to do.
  if (s === s0 && (s ? e || s : "") === (s0 ? e0 : "")) return { ok: true, changed: [] };
  const saw = { ...(isObject(seen) ? seen : {}) };
  if ("end" in saw && !saw.end) saw.end = "start" in saw ? saw.start : s0;
  const moved = {};
  for (const [k, v] of [["start", s0], ["end", e0]]) if (k in saw && !same(v, saw[k])) moved[k] = v;
  if (Object.keys(moved).length) return { ok: false, moved, why: "Changed since you opened it." };
  const value = !s ? "" : (e && e !== s ? `${s}/${e}` : s);
  const { writeFacts } = await import("./facts.js");
  const got = await writeFacts(env, page, { shoot_dates: { value, base: stored ? stored.v || 0 : 0 } }, "server");
  if (got.status === 409 && got.conflicts) {
    const c = got.conflicts.shoot_dates;
    const [cs, ce] = splitDates(c && typeof c.value === "string" ? c.value : "");
    return { ok: false, moved: { start: cs, end: ce || cs }, why: "Changed since you opened it." };
  }
  if (got.status !== 200) return { ok: false, why: got.problem || "The record could not be written. Try again." };
  return { ok: true, changed: ["Shoot Dates"], record: true };
}

/** Where the link keeps the project names it saw in Notion on its last look —
 * `{names: {<title>: <page id>}}`, only titles that are one project's alone —
 * so a save on the record can find its project without asking Notion. */
export const NAMES_KEY = "s/project-names.json";

/** The project's page id by the name the screen shows, from that list; "" when
 * the list does not know the name (the caller then asks Notion, as before). */
export async function fastPage(env, name) {
  if (!env || !env.BUCKET || !name) return "";
  try {
    const got = await env.BUCKET.get(NAMES_KEY);
    if (!got) return "";
    const page = ((await got.json()).names || {})[String(name)];
    return typeof page === "string" && /^[0-9a-f]{32}$/.test(page) ? page : "";
  } catch {
    return "";
  }
}

/** One fact written on the project's record — the record is the master, so a
 * change to it is the save and Notion follows on the link's next minute.
 * `null` when the project has no record (the caller writes Notion), else
 * `{ok, changed}` or `{ok:false, why}`. Nothing here reads or writes Notion;
 * a second save of what is already there changes nothing. */
export async function writeRecordFact(env, page, field, value) {
  if (!env || !env.BUCKET) return null;
  const { writeFacts } = await import("./facts.js");
  for (let tries = 0; tries < 3; tries++) {
    const record = await recordOf(env, page);
    if (!record) return null;
    const kept = isObject(record.facts) && isObject(record.facts[field]) ? record.facts[field] : null;
    if (kept && kept.value === value) return { ok: true, changed: false };
    const got = await writeFacts(env, page, { [field]: { value, base: kept ? kept.v || 0 : 0 } }, "server");
    if (got.status === 200) return { ok: true, changed: true };
    if (got.status !== 409) return { ok: false, why: got.problem || "The record could not be written. Try again." };
  }
  return { ok: false, why: "The record kept changing. Try again." };
}

async function editProjectDates(n, projectId, seen, start, end) {
  const props = (await n.get(`pages/${projectId}`)).properties || {};
  const [patch, moved, why] = projectDatesPlan(props, seen || {}, start, end);
  if (why) return { ok: false, why };
  if (Object.keys(moved).length) return { ok: false, moved, why: "Changed in Notion since you opened it." };
  if (!Object.keys(patch).length) return { ok: true, changed: [] };
  await writeChecked(n, projectId, patch, (p) => projectDatesPlan(p, {}, start, end)[0]);
  return { ok: true, changed: ["Shoot Dates"] };
}

async function editSpecSheet(n, projectId, sheetId, seen, changes) {
  const props = (await n.get(`pages/${sheetId}`)).properties || {};
  if (projectId && !relationIds(props, "Projects").has(bareId(projectId))) return { ok: false, why: "That spec sheet isn't on this project." };
  const [patch, moved, why] = specEditPlan(props, seen || {}, changes || {});
  if (why) return { ok: false, why };
  if (Object.keys(moved).length) return { ok: false, moved, why: "Changed in Notion since you opened it." };
  if (!Object.keys(patch).length) return { ok: true, changed: [] };
  await writeChecked(n, sheetId, patch, (p) => specEditPlan(p, {}, changes)[0]);
  return { ok: true, changed: sorted(patch) };
}

async function editSpecLuts(n, projectId, sheetId, seen, remove, add) {
  const props = (await n.get(`pages/${sheetId}`)).properties || {};
  if (projectId && !relationIds(props, "Projects").has(bareId(projectId))) return { ok: false, why: "That spec sheet isn't on this project." };
  if (!(LUT_FILES in props)) return { ok: false, why: "This spec sheet has no Production LUT." };
  const files = lutFiles(props[LUT_FILES]);
  if (seen != null && JSON.stringify(files.map(lutKey)) !== JSON.stringify([...seen])) {
    return { ok: false, moved: true, why: "Changed in Notion since you opened it." };
  }
  const [next, why] = lutsPlan(files, remove || "", add);
  if (why) return { ok: false, why };
  const patch = { [LUT_FILES]: { files: next } };
  const label = squash((add || {}).label);
  if (label) {
    if (!(LUT_LABELS in props)) return { ok: false, why: "Labels need a “LUT Labels” text property on Camera Spec Sheets in Notion." };
    const made = next[next.length - 1];
    const line = formatEntry({ label, value: made.name.startsWith("http") ? made.external.url : made.name, edited: true });
    const now = specWords(props[LUT_LABELS]);
    patch[LUT_LABELS] = { rich_text: rich(`${now.replace(/\n+$/, "")}\n${line}`.trim()) };
  }
  await n.patch(`pages/${sheetId}`, { properties: patch });
  return { ok: true, changed: sorted(patch) };
}

// ── crew (crewrows.py, disagree.py, notionsync.crew_plan) ────────────────────

/**
 * `difflib.SequenceMatcher(None, a, b).ratio()`, the same number. Names are
 * short, so Python's autojunk (strings of 200 and more) never applies.
 */
export function likeness(a, b) {
  const A = Array.from(a), B = Array.from(b);
  if (!A.length && !B.length) return 1;
  const where = new Map();
  B.forEach((c, j) => { if (!where.has(c)) where.set(c, []); where.get(c).push(j); });
  const longest = (alo, ahi, blo, bhi) => {
    let bi = alo, bj = blo, size = 0;
    let run = new Map();
    for (let i = alo; i < ahi; i++) {
      const next = new Map();
      for (const j of where.get(A[i]) || []) {
        if (j < blo) continue;
        if (j >= bhi) break;
        const k = (run.get(j - 1) || 0) + 1;
        next.set(j, k);
        if (k > size) { bi = i - k + 1; bj = j - k + 1; size = k; }
      }
      run = next;
    }
    return [bi, bj, size];
  };
  let matched = 0;
  const todo = [[0, A.length, 0, B.length]];
  while (todo.length) {
    const [alo, ahi, blo, bhi] = todo.pop();
    const [i, j, k] = longest(alo, ahi, blo, bhi);
    if (!k) continue;
    matched += k;
    if (alo < i && blo < j) todo.push([alo, i, blo, j]);
    if (i + k < ahi && j + k < bhi) todo.push([i + k, ahi, j + k, bhi]);
  }
  return (2 * matched) / (A.length + B.length);
}

const MAX = 200;
const cleanText = (t) => squash(String(t == null ? "" : t).normalize("NFC")).slice(0, MAX);
export function normName(t) {
  let s = cleanText(t).normalize("NFKD").replace(/[^\x00-\x7f]/g, "").toLowerCase();
  s = s.replace(/\(.*?\)/g, " ");
  return squash(s.replace(/[^a-z0-9& ]/g, " "));
}
const emailOk = (e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e);
const crewRich = (t) => (t ? [{ type: "text", text: { content: t.slice(0, 2000) } }] : []);

function tokensMatch(n, m) {
  const a = n.split(" ").filter(Boolean), b = m.split(" ").filter(Boolean);
  if (a.length < 2) return false;
  return a.every((x) => b.some((y) => likeness(x, y) >= 0.85));
}

/** crewrows.duplicates — [{id, name, why, url, type}]. */
export function duplicates(want, rows, companyNames = []) {
  const n = normName(want.name);
  const email = cleanText(want.email).toLowerCase();
  const out = [], seen = new Set();
  for (const r of rows || []) {
    const rid = bareId(r.id);
    let why = "";
    if (email && cleanText(r.email).toLowerCase() === email) why = "same email";
    else {
      const m = normName(r.name);
      if (n && m && (n === m || likeness(n, m) >= 0.88
          || (n.length > 5 && (m.startsWith(`${n} `) || n.startsWith(`${m} `)))
          || tokensMatch(n, m) || tokensMatch(m, n))) why = n === m ? "same name" : "similar name";
    }
    if (why && !seen.has(rid)) {
      seen.add(rid);
      out.push({ id: rid, name: r.name || "", why, url: r.url || "", type: r.type || "" });
    }
  }
  for (const c of companyNames || []) {
    const m = normName(c);
    if (n && m && (n === m || likeness(n, m) >= 0.88) && !out.some((o) => normName(o.name) === m)) {
      out.push({ id: "", name: c, why: "a company already", url: "", type: "Company" });
    }
  }
  return out;
}

/** disagree.norm. */
const looseName = (t) => squash(String(t == null ? "" : t).toLowerCase().replace(/’/g, "'").replace(/[^a-z0-9]+/g, " "));

/** projectpage.directory — every Crew row, marked when typed twice. */
export function directory(rows) {
  const out = (rows || []).map((r) => ({ ...r, id: bareId(r.id) }));
  const twin = new Map();
  const seen = [];
  for (const r of out) {
    const nn = looseName(r.name);
    if (!nn) continue;
    for (const o of seen) {
      const on = looseName(o.name);
      if (nn !== on && likeness(nn, on) >= 0.9) {
        if (!twin.has(r.name)) twin.set(r.name, o.name);
        if (!twin.has(o.name)) twin.set(o.name, r.name);
      }
    }
    seen.push(r);
  }
  for (const r of out) if (twin.has(r.name)) r.dupe_of = twin.get(r.name);
  return out.sort((a, b) => (a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0));
}

const selectName = (props, name) => (((props || {})[name] || {}).select || {}).name || "";

/** shoots._crew_row. */
function crewRow(page) {
  const props = page.properties || {};
  return {
    id: page.id,
    name: plainTitle(props),
    role: ((props.Role || {}).multi_select || []).map((o) => o.name).join(", "),
    department: selectName(props, "Department"),
    type: selectName(props, "Type"),
    company: selectName(props, "Company"),
    location: selectName(props, "Location"),
    email: (props.Email || {}).email || "",
    phone: (props.Phone || {}).phone_number || "",
    url: page.url || "",
    projects: ((props.Projects || {}).relation || []).map((r) => bareId(r.id)),
    shoots: ((props.Shoots || {}).relation || []).map((r) => bareId(r.id)),
  };
}

export async function allCrew(n) {
  const rows = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${CREW}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    for (const p of got.results || []) rows.push(crewRow(p));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return rows;
}

export async function crewOptions(n) {
  const ds = await n.get(`data_sources/${CREW}`);
  const out = {};
  for (const column of ["Role", "Department", "Company", "Location"]) {
    const f = (ds.properties || {})[column] || {};
    out[column] = ((f[f.type || ""] || {}).options || []).map((o) => o.name);
  }
  return out;
}

/** crewrows.person_props — [props, why]. */
export function personProps(person, projectId = "") {
  const name = cleanText(person.name);
  if (!name) return [{}, "A person needs a name."];
  const email = cleanText(person.email);
  if (email && !emailOk(email)) return [{}, "That email doesn't look right."];
  const roles = [...new Set((person.roles || []).map(cleanText).filter(Boolean))];
  const props = { Name: { title: crewRich(name) }, Type: { select: { name: "Person" } } };
  if (roles.length) props.Role = { multi_select: roles.map((r) => ({ name: r.replace(/,/g, " ") })) };
  for (const [key, column] of [["department", "Department"], ["company", "Company"], ["location", "Location"]]) {
    const v = cleanText(person[key]).replace(/,/g, " ");
    if (v) props[column] = { select: { name: v } };
  }
  if (email) props.Email = { email };
  const phone = cleanText(person.phone);
  if (phone) props.Phone = { phone_number: phone };
  const notes = String(person.notes == null ? "" : person.notes).trim().slice(0, 2000);
  if (notes) props.Notes = { rich_text: crewRich(notes) };
  if (projectId) props.Projects = { relation: [{ id: projectId }] };
  const shoots = (person.shoots || []).filter(Boolean);
  if (shoots.length) props.Shoots = { relation: shoots.map((id) => ({ id })) };
  return [props, ""];
}

/** crewrows.company_props. */
export function companyProps(company, projectId = "") {
  const name = cleanText(company.name).replace(/,/g, " ");
  if (!name) return [{}, "A company needs a name."];
  const kind = cleanText(company.kind);
  let website = cleanText(company.website);
  if (website && !/^https?:\/\//i.test(website)) website = `https://${website}`;
  const [props, why] = personProps({ ...company, name, company: name, roles: kind ? [kind] : [],
    department: company.department || "Vendor" }, projectId);
  if (why) return [{}, why.replace("person", "company")];
  props.Type = { select: { name: "Vendor" } };
  if (website) props["Source Link"] = { url: website };
  return [props, ""];
}

/** crewrows._check — "" when the row reads back as written. */
export function readsBack(back, props) {
  const got = back.properties || {};
  const off = [];
  for (const [column, want] of Object.entries(props)) {
    const have = got[column] || {};
    const kind = Object.keys(want)[0];
    let a, b;
    if (kind === "title" || kind === "rich_text") { a = words(have[kind]); b = want[kind].map((t) => t.text.content).join(""); }
    else if (kind === "select") { a = (have.select || {}).name || ""; b = want.select.name; }
    else if (kind === "multi_select") { a = (have.multi_select || []).map((o) => o.name).sort().join("\n"); b = want.multi_select.map((o) => o.name).sort().join("\n"); }
    else if (kind === "relation") { a = (have.relation || []).map((r) => bareId(r.id)).sort().join(","); b = want.relation.map((r) => bareId(r.id)).sort().join(","); }
    else { a = have[kind]; b = want[kind]; }
    if (a !== b) off.push(column);
  }
  return off.join(", ");
}

/**
 * crewrows.icon_for — every Crew row carries a gray icon: the city for a
 * company (a Vendor row whose Company is itself), the person otherwise.
 * Notion Tidy and the Contacts → Notion agent keep to the same pair.
 */
export function iconFor(props) {
  const sel = (col) => (((props[col] || {}).select) || {}).name || "";
  const title = ((props.Name || {}).title || []).map((t) => ((t || {}).text || {}).content || "").join("");
  const company = sel("Type") === "Vendor" && normName(title) === normName(sel("Company"));
  return { type: "external", external: { url: `https://www.notion.so/icons/${company ? "city" : "person-masculine"}_gray.svg` } };
}

/** crewrows._create — the row, its icon, read back. */
async function createCrewRow(n, props) {
  const page = await n.post("pages", { parent: { type: "data_source_id", data_source_id: CREW }, icon: iconFor(props), properties: props });
  const back = await n.get(`pages/${page.id}`);
  const off = readsBack(back, props);
  const out = { ok: !off, id: bareId(page.id), url: page.url || "" };
  if (off) out.why = `Notion kept it, but ${off} didn't read back as written.`;
  return out;
}

/**
 * Every id in a relation. A page carries at most 25 and says `has_more`;
 * past that the property is read on its own, so a crew member on thirty
 * projects is never written back with five of them missing.
 */
export async function relationAll(n, page, name) {
  const field = (page.properties || {})[name] || {};
  const ids = (field.relation || []).map((r) => r.id);
  if (!field.has_more || !field.id) return ids;
  const all = [];
  let cursor;
  do {
    const got = await n.get(`pages/${page.id}/properties/${encodeURIComponent(field.id)}${cursor ? `?start_cursor=${cursor}` : ""}`);
    for (const item of got.results || []) if (item.relation && item.relation.id) all.push(item.relation.id);
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return all;
}

/** notionsync.crew_plan — the PATCH body, {} when nothing would change. Never
 * Role: a role on one project is the record's (`crew_roles`), not the Crew row's. */
export async function crewPlan(n, row, project, { on_project, add_shoots, remove_shoots }) {
  const props = {};
  const projects = await relationAll(n, row, "Projects");
  const haveP = new Set(projects.map(bareId));
  if (on_project === true && !haveP.has(bareId(project))) props.Projects = { relation: [...projects, project].map((id) => ({ id })) };
  else if (on_project === false && haveP.has(bareId(project))) props.Projects = { relation: projects.filter((i) => bareId(i) !== bareId(project)).map((id) => ({ id })) };
  const shoots = await relationAll(n, row, "Shoots");
  const gone = new Set((remove_shoots || []).map(bareId));
  const keep = shoots.filter((i) => !gone.has(bareId(i)));
  const haveS = new Set(keep.map(bareId));
  for (const i of add_shoots || []) if (!haveS.has(bareId(i))) { keep.push(i); haveS.add(bareId(i)); }
  if (keep.map(bareId).join(",") !== shoots.map(bareId).join(",")) props.Shoots = { relation: keep.map((id) => ({ id })) };
  return props;
}

// ── the project page's R2 parts: the record, the portal, hidden lines ───────

/** The project's record (`r/<page>/record.json`), or null. */
export async function recordOf(env, page) {
  if (!env || !env.BUCKET || !/^[0-9a-f]{32}$/.test(page)) return null;
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

/** A portal the hub knows for this page (films.js), loaded only when asked
 * so the checks can read this file without the relay's layout. */
async function portalHere(env, page) {
  if (!env || !env.BUCKET) return null;
  const { portalOf } = await import("./films.js");
  // A minted project's portal lives under its ID, not its Notion page.
  const { keyOfPage } = await import("./projectid.js");
  return await portalOf(env, (await keyOfPage(env, page)) || page);
}

/** The Next box's hidden lines, the Mac's `next-hidden.json` shape:
 * {bare page id (or name): [key]} — kept at `s/next-hidden.json`. */
const HIDDEN = "s/next-hidden.json";

async function hiddenFile(env) {
  const got = env && env.BUCKET ? await env.BUCKET.get(HIDDEN) : null;
  if (!got) return { d: {}, etag: null };
  let d = {};
  try { d = await got.json(); } catch { d = {}; }
  return { d: isObject(d) ? d : {}, etag: got.etag };
}

/** Change the file once, safely beside another writer; `fn`'s answer back. */
async function changeHidden(env, fn) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const { d, etag } = await hiddenFile(env);
    const out = fn(d);
    const text = JSON.stringify(Object.fromEntries(Object.keys(d).sort().map((k) => [k, d[k]])), null, 1);
    const put = await env.BUCKET.put(HIDDEN, text, {
      httpMetadata: { contentType: "application/json" },
      ...(etag ? { onlyIf: { etagMatches: etag } } : {}),
    });
    if (put) return out;
  }
  throw new Error("The hidden lines kept changing while this was being written. Try again.");
}

/** Hidden lines are kept under the project's bare page id (a rename keeps
 * them), or its name when it has no row — `_hidden_project`. */
async function hiddenProject(n, name) {
  const row = await projectRow(n, name);
  return (row && bareId(row.id)) || String(name || "");
}

// ── the doors, as backend.py has them ────────────────────────────────────────

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);

/** The stages a plain pick sets (Released since 2026-10-15); Post, Archived and
 * Closed come from Wrap, Archive and Close Project. */
const SET_STAGES = ["Development", "Active", "Released"];

/** One person's role on THIS project, on the record (`crew_roles`, and the
 * crew copy's `roles` / `roles_here` beside it). Never Notion's Role. [] puts
 * them back on their usual Crew role, read from Notion (needed only then). */
export async function setRolesHere(n, env, page, person, roles, seed = null) {
  if (!page) return { ok: false, why: "This project has no record yet." };
  const { writeFacts } = await import("./facts.js");
  const pid = bareId(person);
  const want = [...new Set((roles || []).map((r) => String(r).replace(/\s+/g, " ").trim()).filter(Boolean))];
  for (let tries = 0; tries < 4; tries++) {
    const record = await recordOf(env, page);
    if (!record) return { ok: false, why: "This project has no record yet." };
    const facts = isObject(record.facts) ? record.facts : {};
    const crewFact = isObject(facts.crew) ? facts.crew : {};
    const heldFact = isObject(facts.crew_roles) ? facts.crew_roles : {};
    const wasHere = isObject(heldFact.value) ? heldFact.value : {};
    const here = { ...wasHere };
    if (want.length) here[pid] = want; else delete here[pid];
    const crew = (Array.isArray(crewFact.value) ? crewFact.value : []).map((p) => ({ ...p }));
    let mine = crew.find((p) => bareId(p.person) === pid);
    if (!mine && seed) {       // just put on the project: the crew copy follows on the next look; this is their entry till then
      const all = !seed.shoots.length;
      mine = { person: pid, name: seed.name, roles: seed.usual, shoots: all ? [...new Set(crew.flatMap((p) => p.shoots || []))].sort() : seed.shoots, all_shoots: all };
      crew.push(mine);
    }
    if (!mine) return { ok: false, why: "They aren't on this project's crew. Add them first." };
    if (want.length) { mine.roles = want; mine.roles_here = true; }
    else {
      let usual;
      try { usual = (((await n.get(`pages/${person}`)).properties || {}).Role || {}).multi_select; } catch { usual = null; }
      if (!Array.isArray(usual)) return { ok: false, why: "Needs Notion to put back their usual role." };
      mine.roles = usual.map((o) => o.name || "").filter(Boolean).sort();
      delete mine.roles_here;
    }
    const changes = {};
    if (JSON.stringify(crewFact.value) !== JSON.stringify(crew)) changes.crew = { value: crew, base: crewFact.v || 0 };
    if (JSON.stringify(wasHere) !== JSON.stringify(here)) changes.crew_roles = { value: here, base: heldFact.v || 0 };
    if (!Object.keys(changes).length) return { ok: true, changed: false };
    const got = await writeFacts(env, page, changes, "server");
    if (got.status === 200) return { ok: true, changed: true };
    if (got.status !== 409) return { ok: false, why: got.problem || "The record could not be written. Try again." };
  }
  return { ok: false, why: "The record kept changing. Try again." };
}

const METHODS = {
  /** The one list (onelist.js): {projects, jobs}, the console's own rows. */
  async project_list(n, _args, env) {
    const { projectList } = await import("./onelist.js");
    return projectList(env, n);
  },

  /** backend.films_shelf, from the records (onelist.js). */
  async films_shelf(n, _args, env) {
    const { filmsShelfAsk } = await import("./onelist.js");
    return filmsShelfAsk(env, n);
  },

  /** backend.set_stage — Development or Active only; the rest are rituals.
   * A change to the record (2026-10-15): the stage is the record's status, saved
   * there at once, and Notion's Status follows on the link's next minute. Notion
   * is written here only for a project with no record yet. */
  async set_stage(n, [name, status], env, ctx) {
    const want = canonStage(status);     // "Complete" is the record's "Released" (stageword.js)
    if (!SET_STAGES.includes(want)) return { ok: false, why: "Post and Archived are reached by their rituals" };
    const fast = await fastPage(env, name);
    const kept = fast ? await writeRecordFact(env, fast, "status", want) : null;
    if (kept) {
      if (kept.ok && kept.changed) await followSoon(env, ctx, fast);
      return kept.ok ? { ok: true, status: want, record: true } : kept;
    }
    const row = await projectRow(n, name);
    if (!row) return { ok: false, why: "no Notion row" };
    const slow = fast === bareId(row.id) ? null : await writeRecordFact(env, bareId(row.id), "status", want);
    if (slow) {
      if (slow.ok && slow.changed) await followSoon(env, ctx, bareId(row.id));
      return slow.ok ? { ok: true, status: want, record: true } : slow;
    }
    await n.patch(`pages/${row.id}`, { properties: { Status: { select: { name: want } } } });
    await liveAfter(env, row.id);
    return { ok: true, status: want };
  },

  /** engine.set_project_website — answers the address saved. The record's
   * (2026-10-15): saved there at once, Notion's Website follows on the link's
   * next minute; Notion is written only for a project with no record. */
  async set_project_website(n, [name, url], env, ctx) {
    let u = String(url || "").trim();
    if (u && !u.includes("://")) u = `https://${u.replace(/^\/+/, "")}`;
    if (u && !/^https?:\/\/[^\s<>"']+$/i.test(u)) throw new Error("That isn't a web address. It starts with http:// or https://.");
    const fast = await fastPage(env, name);
    let kept = fast ? await writeRecordFact(env, fast, "website", u) : null;
    let page = fast;
    let row = null;
    if (!kept) {
      row = await projectRow(n, name);
      if (!row) throw new Error(`no Notion row for ${name}`);
      page = bareId(row.id);
      kept = page === fast ? null : await writeRecordFact(env, page, "website", u);
    }
    if (kept) {
      if (!kept.ok) throw new Error(kept.why);
      if (kept.changed) await followSoon(env, ctx, page);
      return u;
    }
    await n.patch(`pages/${row.id}`, { properties: { Website: { url: u || null } } });
    await liveAfter(env, row.id);
    return u;
  },

  /** A spec sheet that is still only a row in Notion, made a sheet on the record
   * (specsheet.js adoptSheet) so its edits are the record's. Notion is read. */
  async spec_adopt(n, [name, shootId, sheetId], env) {
    const row = await projectRow(n, name);
    if (!row) return noRow;
    const { adoptSheet } = await import("./specsheet.js");
    return await adoptSheet(env, n, { page: bareId(row.id), shootId: String(shootId || ""), sheetId: String(sheetId || ""), by: "Projects Console" });
  },

  /** notionsync.choices — Notion's own spelling; status only the two stages. */
  async fact_choices(n) {
    const ds = await n.get(`data_sources/${PROJECTS}`);
    const options = (column) => ((((ds.properties || {})[column] || {}).select || {}).options || []).map((o) => o.name || "");
    return { ok: true, choices: {
      status: options("Status").filter((o) => SET_STAGES.includes(o)),
      type: options("Type"), length: options("Length"), color: options("Color"),
    } };
  },

  /** A shoot's dates, name or notes — a change to the RECORD (2026-10-15),
   * like the project's own Shoot Dates: saved on the record, the screen shows
   * it at once, and Notion's row follows on the link's next minute (shootedits.js).
   * Notion is written here only for a project with no record, or no copy of its
   * shoots on it yet. */
  async edit_shoot(n, [name, shootId, seen, changes], env, ctx) {
    if (!shootId || !isObject(changes) || !Object.keys(changes).length) {
      if (!(await projectRow(n, name))) return noRow;
      return { ok: false, why: "Say which shoot and what changes." };
    }
    const { recordShootEdit } = await import("./shootedits.js");
    const fast = await fastPage(env, name);
    let kept = fast ? await recordShootEdit(env, n, { id: fast }, String(shootId), seen, changes) : null;
    let page = fast;
    let row = null;
    if (!kept) {
      row = await projectRow(n, name);
      if (!row) return noRow;
      page = bareId(row.id);
      kept = page === fast ? null : await recordShootEdit(env, n, row, String(shootId), seen, changes);
    }
    if (kept) {
      if (kept.ok && kept.changed.length) await followSoon(env, ctx, page);
      return kept;
    }
    return await editShoot(n, row.id, String(shootId), seen, changes);
  },

  /** The project's Shoot Dates, a change to the RECORD (2026-10-15): the
   * record is the master, so the save is a record write and nothing else —
   * clearing them is a real edit, the screen reads them cleared at once, and
   * Notion's Shoot Dates follows on the Notion link's next minute. Notion is
   * not written, read back or waited for here. A project with no record yet
   * is written in Notion directly, as before. */
  async edit_project_dates(n, [name, seen, start, end], env) {
    const fast = await fastPage(env, name);
    const quick = fast ? await recordProjectDates(env, fast, seen, start || "", end || "") : null;
    if (quick) return quick;
    const row = await projectRow(n, name);
    if (!row) return noRow;
    const kept = fast === bareId(row.id) ? null : await recordProjectDates(env, bareId(row.id), seen, start || "", end || "");
    if (kept) return kept;
    return await editProjectDates(n, row.id, seen, start || "", end || "");
  },

  async edit_spec_sheet(n, [name, sheetId, seen, changes]) {
    const row = await projectRow(n, name);
    if (!row) return noRow;
    if (!sheetId || !isObject(changes) || !Object.keys(changes).length) return { ok: false, why: "Say which sheet and what changes." };
    return await editSpecSheet(n, row.id, String(sheetId), seen, changes);
  },

  async edit_entries(n, [name, sheetId, key, seen, items], env) {
    if (!Array.isArray(items) || !key) return { ok: false, why: "Say which field and its lines." };
    const text = writeEntries(items.filter(isObject));
    const got = await METHODS.edit_spec_sheet(n, [name, sheetId, { [key]: seen || "" }, { [key]: text }], env);
    if (got.ok) got.text = text;
    // the labels a Camera edit carried go on the record (Notion holds bodies)
    if (got.ok && key === "Camera" && env) {
      const row = await projectRow(n, name);
      if (row) await keepCameraLabels(env, bareId(row.id), text, "console");
    }
    return got;
  },

  async edit_lut_labels(n, [name, sheetId, seen, rows, stray]) {
    if (!Array.isArray(rows)) return { ok: false, why: "Say which LUTs." };
    const keep = (stray || []).map(String).filter((x) => x.trim());
    const made = lutLabelsText(rows.filter(isObject));
    const text = [...(made ? [made] : []), ...keep].join("\n");
    return await METHODS.edit_spec_sheet(n, [name, sheetId, { [LUT_LABELS]: seen || "" }, { [LUT_LABELS]: text }]);
  },

  async edit_luts(n, [name, sheetId, seen, remove, add]) {
    const row = await projectRow(n, name);
    if (!row) return noRow;
    return await editSpecLuts(n, row.id, String(sheetId || ""), seen == null ? null : seen, remove || "", isObject(add) ? add : null);
  },

  /** backend.spec_options — the pills each spec sheet field offers. */
  async spec_options(n) {
    const db = await n.get(`data_sources/${SPEC_SOURCE}`);
    const options = {}, colors = {};
    for (const [name, field] of Object.entries(db.properties || {})) {
      if (field.type !== "multi_select") continue;
      const list = (field.multi_select || {}).options || [];
      options[name] = list.map((o) => o.name || "");
      colors[name] = Object.fromEntries(list.map((o) => [String(o.name || "").toLowerCase(), o.color || "default"]));
    }
    return { ok: true, options, colors };
  },

  async edit_lens_sets(n, [name, sheetId, seen, sets]) {
    if (!Array.isArray(sets)) return { ok: false, why: "Say which lens sets." };
    const text = writeSets(sets.filter(isObject));
    const got = await METHODS.edit_spec_sheet(n, [name, sheetId, { Lenses: seen || "" }, { Lenses: text }]);
    if (got.ok) got.lenses = text;
    return got;
  },

  /** backend.crew_directory. */
  async crew_directory(n) {
    return { ok: true, people: directory(await allCrew(n)) };
  },

  /** backend.crew_dupes — as he types. */
  async crew_dupes(n, [person]) {
    const p = isObject(person) ? person : {};
    const rows = await allCrew(n);
    if (p.kind === "company") {
      const names = (await crewOptions(n)).Company || [];
      return { ok: true, dupes: duplicates(p, rows.filter((r) => r.type === "Vendor" || (p.email && r.email)), names) };
    }
    return { ok: true, dupes: duplicates(p, rows) };
  },

  /** backend.crew_edit → notionsync.crew_edit. On the project and its shoots:
   * Notion's Crew row. A role (`roles`; [] = back to their usual Crew role) is
   * this project's own, kept on the record as `crew_roles` ({Crew id: [role]})
   * and never written to Notion — so it needs no Notion at all. */
  async crew_edit(n, [name, person, on_project, add_shoots, remove_shoots, roles], env) {
    if (!person) return { ok: false, why: "Say which person." };
    const moves = on_project != null || (add_shoots || []).length || (remove_shoots || []).length;
    let changed = [], seed = null, waits = "";
    const want = { on_project: on_project == null ? null : on_project, add_shoots: add_shoots || [], remove_shoots: remove_shoots || [] };
    if (moves || roles == null) try {
      const row = await projectRow(n, name);
      if (!row) return noRow;
      const crew = await n.get(`pages/${person}`);
      const nameOf = ((crew.properties || {}).Name || {}).title || [];
      seed = {
        name: nameOf.map((t) => t.plain_text || "").join(""),
        usual: ((((crew.properties || {}).Role || {}).multi_select) || []).map((o) => o.name || "").filter(Boolean).sort(),
        shoots: [...(add_shoots || [])].map(bareId).sort(),
      };
      const props = await crewPlan(n, crew, row.id, want);
      if (Object.keys(props).length) {
        await n.patch(`pages/${person}`, { properties: props });
        const back = await n.get(`pages/${person}`);
        if (Object.keys(await crewPlan(n, back, row.id, want)).length) return { ok: false, why: "Notion did not keep the change — try again" };
        changed = sorted(props);
      }
    } catch (e) {
      // Notion out of reach (2026-10-20, his #8): the change waits and is made
      // the first time Notion answers (notionwaits.js), like a stage change.
      // A refused key still goes to the Mac (Handoff), whose key may work.
      const { notionDown, addWait, QUIET } = await import("./notionwaits.js");
      if (e instanceof Handoff || !notionDown(e) || !moves) throw e;
      const page = await fastPage(env, name);
      if (!page) throw e;
      await addWait(env, { kind: "crew-edit", project: page, page, shoot: bareId(person), changes: want, label: "Crew", by: "console" });
      waits = QUIET;
    }
    if (roles == null) return { ok: true, changed, ...(waits ? { waits } : {}) };
    const page = (await fastPage(env, name)) || bareId(((await projectRow(n, name).catch(() => null)) || {}).id || "");
    const got = await setRolesHere(n, env, page, person, roles, on_project === true ? seed : null);
    return got.ok ? { ok: true, changed: [...changed, ...(got.changed ? ["roles"] : [])].sort(), ...(waits ? { waits } : {}) } : got;
  },

  /** backend.crew_new — a credit with it goes on the record in answerHere. */
  async crew_new(n, [name, person, force]) {
    const p = { ...(isObject(person) ? person : {}) };
    if (typeof p.role === "string" && !p.roles) p.roles = p.role.split(",").map((r) => r.trim()).filter(Boolean);
    const row = name ? await projectRow(n, name) : null;
    if (name && !row) return noRow;
    const page = row ? row.id : "";
    const rows = await allCrew(n);
    if (!force) {
      const dupes = duplicates(p, rows);
      if (dupes.length) return { ok: false, dupes };
    }
    const on = Boolean(page) && p.on_project !== false;
    const [props, why] = personProps({ ...p, shoots: on ? p.shoots : [] }, on ? page : "");
    if (why) return { ok: false, why };
    return { ...(await createCrewRow(n, props)), reused: false };
  },

  /** backend.company_new — a credit with it goes on the record in answerHere. */
  async company_new(n, [name, company, force]) {
    const c = { ...(isObject(company) ? company : {}) };
    const rows = await allCrew(n);
    const options = (await crewOptions(n)).Company || [];
    if (!force) {
      const dupes = duplicates(c, [...rows.filter((r) => r.type === "Vendor"), ...rows.filter((r) => r.email)], options);
      if (dupes.length) return { ok: false, dupes };
    }
    // On the project only when credited as its Production Company.
    const row = name && c.credit ? await projectRow(n, name) : null;
    const [props, why] = companyProps(c, row ? row.id : "");
    if (why) return { ok: false, why };
    return await createCrewRow(n, props);
  },

  /** backend.project_crew_url → notionsync.crew_view_url. */
  async project_crew_url(n, [name]) {
    const row = await projectRow(n, name);
    if (!row) return noRow;
    const page = bareId(row.id);
    const fallback = `https://www.notion.so/${page}`;
    try {
      let cursor;
      do {
        const kids = await n.get(`blocks/${page}/children?page_size=100${cursor ? `&start_cursor=${cursor}` : ""}`);
        for (const block of kids.results || []) {
          if (block.type !== "child_database") continue;
          const views = (await n.get(`views?database_id=${bareId(block.id)}`)).results || [];
          for (const v of views) {
            const one = await n.get(`views/${v.id}`);
            if (bareId(one.data_source_id) !== bareId(CREW)) continue;
            if (JSON.stringify(one.filter || {}).replace(/-/g, "").includes(page)) return { ok: true, url: one.url || fallback };
          }
        }
        cursor = kids.has_more ? kids.next_cursor : undefined;
      } while (cursor);
    } catch (e) {
      if (e instanceof Handoff) throw e;
      return { ok: true, url: fallback, why: String(e.message || e) };
    }
    return { ok: true, url: fallback };
  },

  /** backend.project_page — Overview, Shoots, People and Documents
   * (projectpage.js). The crew and credits are the record's, from R2; the
   * Drive folder is the Mac's last read of it (drivelists.js), with its age
   * as `folders_at`. `force` asks nothing: there is no two-minute keep here. */
  async project_page(n, [name], env) {
    const row = await projectRow(n, name);
    if (!row) return { ok: false, why: "no Notion row for this project" };
    const page = bareId(row.id);
    const { projectFolders } = await import("./drivelists.js");
    const held = await projectFolders(env, page);
    const record = await recordOf(env, page);
    const facts = (record && isObject(record.facts) && record.facts) || {};
    const crew = isObject(facts.crew) ? facts.crew.value : null;
    let credits;
    try { credits = creditsOf(facts); } catch { credits = []; }
    const lights = (record && isObject(record.lights) && record.lights) || {};
    const relay = record && isObject(record.film) && record.film.relay;
    const { layEdits, editsOf } = await import("./shootedits.js");
    const waiting = editsOf(facts);
    const got = await gather(n, projectOf(row, facts), Array.isArray(crew) ? crew : [], {
      lay: (rows) => layEdits(rows, waiting),
      recordShoots: isObject(facts.shoots) && Array.isArray(facts.shoots.value) ? facts.shoots.value : null,
      media_on: lights.media === "on",
      portal_on: Boolean(relay) || Boolean(await portalHere(env, page)) || lights.portal === "on",
      credits,
      cameraLabels: isObject(facts.camera_labels) && isObject(facts.camera_labels.value) ? facts.camera_labels.value : null,
      isHandoff: (e) => e instanceof Handoff,
      tree: held ? held.tree : [],
    });
    // which body is A Cam, B Cam: the record's (Notion only lists the bodies)
    got.camera_labels = isObject(facts.camera_labels) && isObject(facts.camera_labels.value) ? facts.camera_labels.value : {};
    got.camera_labels_v = isObject(facts.camera_labels) ? facts.camera_labels.v || 0 : 0;
    got.drive_path = held ? held.path : "";
    if (held) got.folders_at = held.at;
    got.page_id = row.id;
    const hidden = await hiddenFile(env);
    return { ...got, next: hideChecks(got.next, hidden.d[page] || []) };
  },

  /** backend.mirror_facts — the record's shown name, director, producer,
   * client and agency into the film (filmfacts.js). The Mac's while the Mac
   * is the one writing films (`/console/studio/owner/films`). */
  async mirror_facts(n, [name], env) {
    const row = await projectRow(n, name);
    if (!row) return { ok: false, why: "no Notion row" };
    const { filmsOwner, mirrorOne } = await import("./filmfacts.js");
    if ((await filmsOwner(env)).owner !== "hub") throw new Handoff("the Mac writes the films");
    const { mirrorRecord } = await import("./filmdoor.js");
    const got = await mirrorOne(env, bareId(row.id), undefined, mirrorRecord);
    delete got.want;
    return got;
  },

  /** backend.mirror_director — Notion's Director into the film. The director
   * is one of the record's five facts, so it goes the same road. */
  async mirror_director(n, [name], env) {
    const row = await projectRow(n, name);
    if (!row) return { ok: false, why: "no Notion row" };
    const { filmsOwner, mirrorOne } = await import("./filmfacts.js");
    if ((await filmsOwner(env)).owner !== "hub") throw new Handoff("the Mac writes the films");
    const { mirrorRecord } = await import("./filmdoor.js");
    const got = await mirrorOne(env, bareId(row.id), undefined, mirrorRecord);
    if (!got.ok) return got;
    const director = (got.want && got.want.director) || "";
    return { ok: true, director, said: `director: ${director || "none"}` };
  },

  /** backend.mirror_mark — Notion's icon and colour into the film
   * (filmfacts.js, the same door as the facts). The Mac's until the server
   * owns both the films and the marks. A mark he set by hand is his: it says
   * so and writes nothing. */
  async mirror_mark(n, [name], env) {
    const row = await projectRow(n, name);
    if (!row) return { ok: false, why: "no Notion row" };
    const { filmsOwner, marksOn, markLookup, fetchIcon, mirrorOne } = await import("./filmfacts.js");
    if ((await filmsOwner(env)).owner !== "hub") throw new Handoff("the Mac writes the films");
    if (!(await marksOn(env))) throw new Handoff("the Mac writes the films' marks");
    const { mirrorRecord } = await import("./filmdoor.js");
    const marks = markLookup(env, fetchIcon);
    const got = await mirrorOne(env, bareId(row.id), undefined, mirrorRecord, { marks, only: "mark" });
    await marks.save();
    if (!got.ok) return got;
    const byHand = got.mark === "hand";
    return {
      ok: true,
      mirrored: got.mark === "mirrored",
      by_hand: byHand,
      said: `mark: colour ${got.pair.colour}  source ${byHand ? "hand" : "console"}  outline yes`,
    };
  },

  /** backend.set_project_layout — Customize Record (cloudlayout.js). What
   * writes nothing is answered here; a write only once its switch is on,
   * else the Mac's. */
  async set_project_layout(n, args, env) {
    const { setProjectLayout } = await import("./cloudlayout.js");
    return await setProjectLayout(env, n, args);
  },

  /** backend.project_suggestions — what belongs in each empty place
   * (suggest.js). The Mac's when the guess needs its disk. */
  async project_suggestions(n, args, env) {
    const { projectSuggestions } = await import("./suggest.js");
    return await projectSuggestions(env, n, args);
  },

  /** backend.new_film — a film made on the relay and linked to the project
   * (newfilm.js). The Mac's until the switch is on. */
  async new_film(n, [name, title], env) {
    const { newFilmOn, makeNewFilm } = await import("./newfilm.js");
    // **One ID** (projectid.js): the film is the project's Studio side, made
    // under the project's own ID (studioside.js) — nothing to link or carry.
    const { oneIdOn, keyOfPage } = await import("./projectid.js");
    if ((await oneIdOn(env)).on) {
      const row = await projectRow(n, name);
      if (!row) return { ok: false, why: "no Notion row for this project" };
      const key = await keyOfPage(env, String(row.id || ""));
      const { ensureStudioSide } = await import("./studioside.js");
      const got = await ensureStudioSide(env, key, { by: "new_film" });
      if (!got.ok) return got;
      await liveAfter(env, row.id);
      return { ok: true, path: "", linked: true, relay: got.relay, title: got.title,
        said: got.made ? `newfilm: "${got.title}"  on the relay` : `This project already has a film: ${got.title || "untitled"}.` };
    }
    if (!(await newFilmOn(env)).on) throw new Handoff("the Mac makes films");
    const row = await projectRow(n, name);
    const got = await makeNewFilm(env, row, name, title);
    if (got.ok && row) await liveAfter(env, row.id);
    return got;
  },

  /** backend.film_backup — a copy of the film now, into the backups bucket
   * and the Drive (filmbackuprun.js). The Mac's until the switch is on. */
  async film_backup(n, [name], env) {
    const { backupsOn, phoneBackup } = await import("./filmbackuprun.js");
    if (!(await backupsOn(env))) throw new Handoff("the Mac backs films up");
    return await phoneBackup(env, n, name);
  },

  /** backend.film_backups — the film's copies, newest first. */
  async film_backups(n, [name], env) {
    const { backupsOn, phoneBackups } = await import("./filmbackuprun.js");
    if (!(await backupsOn(env))) throw new Handoff("the Mac lists its backups");
    return await phoneBackups(env, n, name);
  },

  /** backend.create_showcase — the portfolio showcase's folders on the
   * Drive (drivefolders.js). The Mac's until the switch is on. */
  async create_showcase(n, args, env) {
    const { createShowcase } = await import("./drivefoldersdoor.js");
    return await createShowcase(env, n, args);
  },

  /** backend.create_project — a quick job with no media drive (Drive
   * folders only, drivefoldersdoor.js); a full project, or a media drive,
   * only once New Project's own switch is on (newprojectdoor.js), the media
   * folders left for the Mac. Anything else is the Mac's. */
  async create_project(n, args, env) {
    const { createProject } = await import("./newprojectdoor.js");
    return await createProject(env, n, args);
  },

  /** backend.new_shoot_form / plan_new_shoot / run_new_shoot — New Shoot
   * (newshoot.js). The Mac's until its switch is on. */
  async new_shoot_form(n, args, env) {
    const { newShootAsk } = await import("./newshootdoor.js");
    return await newShootAsk(env, n, "new_shoot_form", args);
  },
  async plan_new_shoot(n, args, env) {
    const { newShootAsk } = await import("./newshootdoor.js");
    return await newShootAsk(env, n, "plan_new_shoot", args);
  },
  async run_new_shoot(n, args, env) {
    const { newShootAsk } = await import("./newshootdoor.js");
    return await newShootAsk(env, n, "run_new_shoot", args);
  },

  /** backend.new_project_options — the sheet's lists, while New Project's
   * switch is on; else the Mac's. */
  async new_project_options(n, args, env) {
    const { newProjectOptions } = await import("./newprojectdoor.js");
    return await newProjectOptions(env, n);
  },

  /** project_modes / set_project_mode — the Systems card's mode tiles
   * (projectmodes.js over studiomodes.js). */
  async project_modes(n, args, env) {
    const { projectModes } = await import("./projectmodes.js");
    return await projectModes(env, args);
  },
  async set_project_mode(n, args, env) {
    const { setProjectMode } = await import("./projectmodes.js");
    return await setProjectMode(env, args);
  },
  async set_project_mod(n, args, env) {
    const { setProjectMod } = await import("./projectmodes.js");
    return await setProjectMod(env, args);
  },

  /** backend.link_suggestion — Link on a suggestion (cloudlink.js). */
  async link_suggestion(n, args, env) {
    const { linkSuggestion } = await import("./cloudlink.js");
    const got = await linkSuggestion(env, n, args);
    if (got.ok && got.changed && got.changed.length) {
      const row = await projectRow(n, args[0]);
      if (row) await liveAfter(env, row.id);
    }
    return got;
  },

  /** backend.project_dossier — the phone's Look Again (cloudlink.js). */
  async project_dossier(n, args, env) {
    const { lookAgain } = await import("./cloudlink.js");
    return await lookAgain(env, n, args);
  },

  /** backend.drive_tree — a media drive's project folders as the Mac last
   * read them (drivelists.js), each row with `as_of`. The Mac's own when it
   * is awake with the drive plugged in: it reads the drive now. */
  async drive_tree(n, [volume], env) {
    const { driveTree } = await import("./drivelists.js");
    const rows = await driveTree(env, volume);
    if (rows === null) throw new Handoff("the Mac reads a plugged-in drive itself");
    return rows;
  },

  /** backend.next_check_hide — one Next-box line hidden for its shoot (or back). */
  async next_check_hide(n, [name, key, hide], env) {
    const project = await hiddenProject(n, name);
    try {
      await changeHidden(env, (d) => setHiddenIn(d, project, key, hide === undefined ? true : Boolean(hide)));
    } catch (e) {
      if (e instanceof RangeError) return { ok: false, why: e.message };
      throw e;
    }
    return { ok: true };
  },

  /** backend.next_check_show — every line hidden for this shoot, back. */
  async next_check_show(n, [name, shoot], env) {
    const project = await hiddenProject(n, name);
    const shown = await changeHidden(env, (d) => showHiddenIn(d, project, String(shoot || "")));
    return { ok: true, shown };
  },
};

/**
 * Answer one ask here, if it is ours. `null` means not ours, or Notion
 * refused before anything was written: the ask waits for the Mac. Otherwise
 * `{ state: "done", result }` or `{ state: "failed", error }`, as the Mac
 * would have answered.
 */
export async function answerHere(env, method, args, ctx = null) {
  // The phone's registration for alerts rides the Mac's `agents` seam
  // (push_register / push_unregister): the server keeps the list now.
  if (method === "agents" && Array.isArray(args) && (args[0] === "push_register" || args[0] === "push_unregister")) {
    const push = await import("./push.js");
    const p = (args[1] && typeof args[1] === "object") ? args[1] : {};
    const got = args[0] === "push_register"
      ? await push.register(env, p.token, p.env, p.device)
      : await push.unregister(env, p.token);
    return { state: "done", result: got.ok ? got : { ok: false, error: got.error || "refused" } };
  }
  // The Mac jobs list needs no Notion key (macjobs.js); only while its switch is on.
  if (method.startsWith("mac_job")) {
    const mj = await import("./macjobs.js");
    if (mj.CLOUD.has(method)) return (await mj.macJobsOn(env)).on ? await mj.cloudAnswer(env, method, args) : null;
  }
  if (!CLOUD_METHODS.has(method) || !cloudReady(env)) return null;
  if (STEP6_METHODS.has(method)) {
    try {
      const six = await step6Answer(env, method, Array.isArray(args) ? args : []);
      if (six !== undefined) return six;
    } catch (e) {
      if (e instanceof Handoff) return null;
      return { state: "failed", error: String((e && e.message) || e || "It failed, and did not say why.").slice(0, 2000) };
    }
  }
  if (BIGMOVE_METHODS.has(method)) {
    try {
      if (!(await bigmovesNow(env)).length) return null;
      return await bigmoveAnswer(env, method, Array.isArray(args) ? args : []);
    } catch (e) {
      if (e instanceof Handoff) return null;
      return { state: "failed", error: String((e && e.message) || e || "It failed, and did not say why.").slice(0, 2000) };
    }
  }
  // phonelink.perform's own refusal, word for word.
  if (method === "set_stage" && (!Array.isArray(args) || args.length < 2 || !SET_STAGES.includes(canonStage(args[1])))) {
    return { state: "failed", error: "Post and Archived run a ritual — move a project there on the Mac." };
  }
  const n = notionOf(env);
  const list = Array.isArray(args) ? args : [];
  try {
    if (method === "portal_shared" || method === "portal_state") {
      const { PORTAL_MODE_ASKS } = await import("./portalmodes.js");
      return { state: "done", result: await PORTAL_MODE_ASKS[method](list, env) };
    }
    if (method === "set_document_on_portal") {
      const got = await documentOnPortal(n, list, env);
      if (got) return { state: "done", result: got };
    }
    if (PORTAL.has(method)) {
      // Loaded when asked: they reach the worker and the record, which a plain
      // node check of this file cannot load.
      const { PORTAL_METHODS } = await import("./cloudportal.js");
      const row = await projectRow(n, list[0]);
      if (!row) return { state: "done", result: { ok: false, why: "no Notion row for this project" } };
      const result = await PORTAL_METHODS[method](n, list, env, row);
      if (!PORTAL_READS.has(method)) await liveAfter(env, row.id);
      return { state: "done", result };
    }
    if (method === "portal_docs" || method === "set_portal_doc") {
      const row = await projectRow(n, list[0]);
      if (!row) return { state: "done", result: { ok: false, why: "This project has no Notion row." } };
      const [{ portalDocsDoor }, { writeFacts }] = await Promise.all([import("./portaldocs.js"), import("./facts.js")]);
      const page = String(row.id).replace(/-/g, "");
      const got = method === "portal_docs"
        ? await portalDocsDoor(env, page, "GET", null, { recordOf, writeFacts })
        : await portalDocsDoor(env, page, "PUT", async () => ({ id: list[1], on: list[2], by: "console" }), { recordOf, writeFacts });
      const said = await got.json();
      return { state: "done", result: got.ok ? { ok: true, ...said } : { ok: false, why: said.problem || `Couldn't (${got.status})` } };
    }
    if (FACTS.has(method)) {
      const { factsAsk } = await import("./cloudfacts.js");
      return { state: "done", result: await factsAsk(env, n, method, list, null, ctx) };
    }
    const result = await METHODS[method](n, list, env, ctx);
    if (AFTER_EDIT.has(method) && result && result.ok !== false) {
      const row = await projectRow(n, list[0]);
      if (row) await liveAfter(env, row.id);
    }
    // A credit with a new person or company: on the record too, as
    // backend.crew_new / company_new do through set_project_credits.
    if ((method === "crew_new" || method === "company_new") && isObject(result) && result.ok && list[0]) {
      const { newCredit } = await import("./cloudfacts.js");
      const edit = newCredit(method, list[1]);
      const row = edit ? await projectRow(n, list[0]) : null;
      if (row) {
        const { changeCredits } = await import("./cloudrecord.js");
        const got = await changeCredits(env, row.id, edit);
        if (!got.ok) result.why = `Added, but not credited: ${got.why || ""}`;
      }
    }
    return { state: "done", result };
  } catch (e) {
    if (e instanceof Handoff) return null;
    // Notion out of reach is never shown as its raw error ("401 …"): one quiet line.
    const quiet = (await import("./notionwaits.js")).notionWords(e);
    return { state: "failed", error: quiet || String((e && e.message) || e || "It failed, and did not say why.").slice(0, 2000) };
  }
}
