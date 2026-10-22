/**
 * **Stage 5 step 6, group "health"** (2026-10-15): a project's folder health,
 * done by the server — the Google Drive half of it. Ported rule for rule from
 * the Mac (Projects Console `engine.py`), with the filing rules as the spec
 * (`cinematography/.filing-rules.md`, `portfolio/showcase-structure.md`):
 *
 * - `project_gaps(name, status)` — `engine.project_gaps`: what the project
 *   is missing against the filing rules. Read only.
 * - `project_tree(name)` — `engine.project_folder_trees`: the Google Drive
 *   and showcase folder trees for the detail panel. Read only.
 * - `repair_subfolders(name)` — `engine.repair_subfolders`: the five
 *   standard sections, and the template's folders wherever a section is
 *   still empty. Only ever creates.
 * - `complete_setup(name, status)` — `engine.complete_setup`: every gap
 *   filled in one go (the sections, the showcase when it is due).
 *
 * **The media drives stay the Mac's.** A plugged-in drive is the Mac's to
 * read, so the server answers the Drive half and leaves the rest with
 * `media_by_mac: true` (gaps and trees): the Mac's screen asks the Mac for
 * `media_missing_on` and the media trees (`s6_health.py`), and adds
 * complete_setup's media line itself.
 *
 * **Not moved, on purpose** (each is a file on the Mac's own disk):
 * `film_restore` (a backup unpacked onto the Mac's Desktop by Shotlister's
 * `restore.sh`, never over the live film; from anywhere the server's zip
 * door already hands a copy back) and `unarchive_film` (Shotlister Studio's
 * `--unarchivefilm` door: the film's folder out of its bin in the Mac's
 * iCloud Documents, then one sync). See `restoreLook` below for the
 * old-and-new-ID check on the server's copies.
 *
 * **A Job's Job Log row** (newproject.js `jobLogLine`) is written while this
 * switch is on — before step 6 the server wrote none. A Job's loose Drive
 * folder is not behind it (drivefolders.js `planProject`).
 *
 * Reads use the Drive the folders switch names (`s/drivefolders.json`
 * roots; its scratch folder when set). Writes need that switch ready too
 * (on, roots, the `GDRIVE_WRITE` sign-in); otherwise the ask is the Mac's.
 *
 * Rule: NO static import of cloud.js / studio.js here (they import step6.js,
 * which imports this file): `await import("./cloud.js")` inside functions.
 */

import * as folders from "./drivefolders.js";

/** The switch: `s/step6-health.json` {on, at, by}; door at /console/studio/step6health. */
export const SWITCH = "step6health";
export const SWITCH_KEY = "s/step6-health.json";

/** Whether the switch is on (read here: step6.js imports this file). */
export async function healthOn(env) {
  const got = await env.BUCKET.get(SWITCH_KEY);
  if (!got) return false;
  try { return (await got.json()).on === true; } catch { return false; }
}

/**
 * A Job made by the server gets its Job Log row (backend._job_after,
 * newproject.js jobLogLine) while this group's switch is on. Before step 6
 * the server wrote none; the Job's loose Drive folder is not behind it.
 */
export async function jobLogOn(env) {
  return healthOn(env);
}

/** Every ask this group answers (listed to the Mac and phone only while the switch is on). */
export const METHODS = new Set(["project_gaps", "project_tree", "repair_subfolders", "complete_setup"]);
/** Of those, reads answered on the spot (`POST /console/studio/now`). */
export const NOW = new Set(["project_gaps", "project_tree"]);
/** Asks too slow for the 20 s reply: kept working by the server (later.js). */
export const LATER_WRITES = new Set(["complete_setup", "repair_subfolders"]);
export const LATER_READS = new Set([]);

// ── the rules ────────────────────────────────────────────────────────────────

/** engine.STANDARD_SUBFOLDERS: the spine of a new project (filing rules). */
export const STANDARD = ["1-creative", "2-logistics", "3-post", "4-financial", "z-other"];
/** engine.SHOWCASE_STATUSES: when a showcase is due. */
const SHOWCASE_DUE = ["post", "archived"];
/** Where his Google Drive is mounted on the Mac: the paths the Mac's answers carry (Finder opens them). */
export const MOUNT = "/Users/YOUR_USER/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/cinematography";

const lower = (s) => String(s).toLowerCase();
const isDir = (k) => k && k.folder && !k.shortcut;
const dirs = async (api, id) => (id ? (await api.list(id)).filter(isDir) : []);
/** Python's `sorted()` on names: by code point. */
const byCodePoint = (a, b) => {
  const x = [...a], y = [...b];
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d) return d;
  }
  return x.length - y.length;
};
const templateOf = (settings) => settings.template || folders.PROJECT_TEMPLATE;
/** A Job's folder (in gigs/, or its archive) is loose by design: filing rules,
 * Tier 2, "deliberately no ceremony" — no spine is missing from it. */
export const looseJob = (place) => String(place || "").startsWith("gigs/");
export const LOOSE_JOB_SAID = "A Job's folder is loose by design — nothing added.";

/** engine._legacy_spine: a top folder numbered its own older way (one older project's 1-script/…). */
export function legacySpine(kids) {
  return kids.some((k) => /^\d-/.test(k.name) && !STANDARD.includes(k.name));
}

/**
 * engine._starter_subfolders: the template's nested folders, offered only
 * where the section above them is there and still has no folder of its own
 * (another project named its own 3-post/dailies-stills; filling in the template
 * would bolt an empty duplicate beside it). `sections` maps a section's name
 * to its folder ids' children (null for a section not there).
 */
export function starters(template, sections) {
  const out = [];
  for (const rel of template) {
    if (!rel.includes("/")) continue;
    const kids = sections[rel.split("/")[0]];
    if (kids === null || kids === undefined) continue;     // the section is missing: the spine covers it
    if (kids.some(isDir)) continue;                         // it has its own shape: left alone
    out.push(rel);
  }
  return out;
}

/** Each standard section's children, as the Mac's `(pdir / s).is_dir()` and iterdir see them. */
async function sectionsOf(api, pid, template) {
  const top = await api.list(pid);
  const names = new Set([...STANDARD, ...template.filter((t) => t.includes("/")).map((t) => t.split("/")[0])]);
  const out = {};
  for (const n of names) {
    const hit = folders.childNamed(top.filter(isDir), n);
    out[n] = hit ? await api.list(hit.id) : null;
  }
  return { top, sections: out };
}

/**
 * Where an item is, as the filing rules name it (`projects/lets-bake`), by
 * walking its parents up to one of the roots. "" when it is not under one.
 */
export async function placeOf(api, roots, item) {
  const known = {};
  for (const r of Object.values(roots)) if (r && r.id) known[r.id] = r.path;
  const parts = [item.name];
  let at = item;
  for (let i = 0; i < 8; i++) {
    const parent = (at.parents || [])[0] || ((await api.get(at.id)) || {}).parents?.[0];
    if (!parent) return "";
    if (known[parent]) return `${known[parent]}/${parts.join("/")}`;
    const up = await api.get(parent);
    if (!up) return "";
    parts.unshift(up.name);
    at = up;
  }
  return "";
}

const localPath = (rel) => (rel ? `${MOUNT}/${rel}` : "");

/** The project's folder (engine.project_drive_folder, or the archived one too) with its place. */
async function projectFolder(api, roots, name, url, archived) {
  const found = await folders.findProjectFolder(api, roots, name, url, { archived });
  if (!found) return null;
  const item = (await api.get(found.id)) || { id: found.id, name: found.name };
  return { ...found, place: await placeOf(api, roots, item) };
}

/** engine.list_dir_tree(path, depth=1): folders only, no dot names, by name without regard to case. */
export async function dirTree(api, id, place, depth = 1) {
  if (depth < 0) return [];
  const kids = (await dirs(api, id)).filter((k) => !k.name.startsWith("."))
    .sort((a, b) => byCodePoint(lower(a.name), lower(b.name)) || byCodePoint(a.name, b.name));
  const out = [];
  for (const k of kids) {
    const rel = `${place}/${k.name}`;
    out.push({ name: k.name, path: localPath(rel), children: depth > 0 ? await dirTree(api, k.id, rel, depth - 1) : [] });
  }
  return out;
}

/** The showcase, as planShowcase finds it: `{found, key, missing, plan}`. */
async function showcaseOf(api, settings, name, status, url, now) {
  const plan = await folders.planShowcase(api, settings, { name, status, drive_url: url }, now);
  if (!plan.ok) return { found: false, key: "", missing: [], plan };
  const fresh = plan.steps.some((s) => s.key === plan.showcase);
  const missing = fresh ? ["stills", "website"]
    : plan.steps.filter((s) => s.op === "folder" && s.parent === plan.showcase).map((s) => s.name);
  return { found: !fresh, key: plan.showcase, missing, plan };
}

/**
 * engine.project_gaps — everything this project is missing against the
 * filing rules. The media drives are the Mac's (`media_by_mac`).
 */
export async function gapsOf(api, settings, { name, status = "", url = "", now = new Date() }) {
  const roots = await folders.rootsOf(api, settings);
  const pdir = await projectFolder(api, roots, name, url, true);
  const slug = pdir ? pdir.name : folders.slugify(name);
  const template = templateOf(settings);
  let legacy = false, missingSub = [], missingStarters = [];
  const loose = Boolean(pdir) && looseJob(pdir.place);
  if (pdir) {
    const { top, sections } = await sectionsOf(api, pdir.id, template);
    legacy = legacySpine(top.filter(isDir));
    if (!legacy && !loose) {
      missingSub = STANDARD.filter((s) => !folders.childNamed(top.filter(isDir), s));
      missingStarters = starters(template, sections);
    }
  }
  const sc = await showcaseOf(api, settings, name, status, url, now);
  const scKey = sc.key;
  const st = lower(String(status).trim());
  return {
    slug,
    has_folder: Boolean(pdir),
    folder: pdir ? localPath(pdir.place) : "",
    legacy_spine: legacy,
    loose_job: loose,
    missing_subfolders: missingSub,
    missing_starters: missingStarters,
    has_showcase: sc.found,
    showcase_path: localPath(scKey),
    showcase_name: scKey.slice(scKey.lastIndexOf("/") + 1),
    showcase_due: SHOWCASE_DUE.includes(st),
    missing_showcase_parts: sc.missing,
    media_missing_on: [],
    media_by_mac: true,
  };
}

/** engine.project_folder_trees — the Google Drive and showcase trees; media is the Mac's. */
export async function treeOf(api, settings, { name, url = "" }) {
  const roots = await folders.rootsOf(api, settings);
  const gdir = await projectFolder(api, roots, name, url, false);
  const slug = gdir ? gdir.name : folders.slugify(name);
  const gdrive = gdir ? { name: gdir.name, path: localPath(gdir.place), label: "Google Drive", children: await dirTree(api, gdir.id, gdir.place) } : null;
  const sc = await showcaseOf(api, settings, name, "", url, new Date());
  let showcase = null;
  if (sc.found) {
    const id = sc.plan.ids[sc.key];
    showcase = { name: sc.key.slice(sc.key.lastIndexOf("/") + 1), path: localPath(sc.key), label: "Portfolio Showcase",
      archived: sc.key.split("/").includes("zz-archived"), children: await dirTree(api, id, sc.key) };
  }
  return { gdrive, showcase, media: [], slug, media_by_mac: true };
}

/**
 * engine.repair_subfolders, as a plan: the missing sections, then — the
 * sections now there — every template folder under a section still empty
 * (a section just made is empty, so it gets the template's own folders).
 * `{ok, legacy, steps, ids, added, said}`; `{ok: false, why}` with no folder.
 */
export async function planRepair(api, settings, { name, url = "" }) {
  const roots = await folders.rootsOf(api, settings);
  const pdir = await projectFolder(api, roots, name, url, true);
  if (!pdir) return { ok: false, why: "No Drive folder for this project." };
  const template = templateOf(settings);
  const { top, sections } = await sectionsOf(api, pdir.id, template);
  const plan = { ok: true, kind: "repair", folder: pdir.place, steps: [], ids: { [pdir.place]: pdir.id }, notes: [], added: [] };
  if (legacySpine(top.filter(isDir))) {
    plan.legacy = true;
    plan.said = "This project uses its own older folder numbering — left alone "
      + "on purpose (the filing rules say never renumber an existing project).";
    return plan;
  }
  if (looseJob(pdir.place)) {
    plan.loose = true;
    plan.said = LOOSE_JOB_SAID;
    return plan;
  }
  const made = {};
  for (const s of STANDARD) {
    const hit = folders.childNamed(top.filter(isDir), s);
    if (hit) { plan.ids[`${pdir.place}/${s}`] = hit.id; continue; }
    plan.steps.push({ op: "folder", key: `${pdir.place}/${s}`, parent: pdir.place, name: s, exists: false });
    plan.added.push(s);
    made[s] = [];
  }
  // the sections as they will be: a made one is there and empty
  for (const s of Object.keys(sections)) {
    if (made[s]) sections[s] = [];
    else if (sections[s] && !plan.ids[`${pdir.place}/${s}`]) {
      const hit = folders.childNamed(top.filter(isDir), s);
      if (hit) plan.ids[`${pdir.place}/${s}`] = hit.id;
    }
  }
  const have = new Set(plan.steps.map((x) => x.key));
  for (const rel of starters(template, sections)) {
    const parts = rel.split("/");
    for (let i = 2; i <= parts.length; i++) {
      const key = `${pdir.place}/${parts.slice(0, i).join("/")}`;
      if (have.has(key)) continue;
      have.add(key);
      plan.steps.push({ op: "folder", key, parent: `${pdir.place}/${parts.slice(0, i - 1).join("/")}`, name: parts[i - 1], exists: false });
    }
    plan.added.push(rel);
  }
  plan.said = plan.added.length ? `Added: ${plan.added.join(", ")}` : "Nothing missing — all standard folders exist.";
  return plan;
}

/** engine.repair_subfolders, made: its sentence. */
export async function repair(api, settings, { name, url = "" }) {
  const plan = await planRepair(api, settings, { name, url });
  if (!plan.ok) throw new Error(plan.why);
  if (!plan.steps.length) return { said: plan.said, made: [] };
  const got = await folders.carryOut(api, plan);
  if (got.failed.length) {
    const e = new Error(`Folders not finished — ${got.failed.map((f) => `${f.key}: ${f.why}`).join("; ")}`);
    e.made = got.made;
    throw e;
  }
  return { said: plan.said, made: got.made };
}

/**
 * engine.complete_setup — every gap filled in one go, each piece the same
 * as its own button. `write: false` says what it would do, writing nothing.
 * The media line is the Mac's to add (the drives are its own).
 */
export async function completeSetup(api, settings, { name, status = "", url = "", write = true, now = new Date() }) {
  const gaps = await gapsOf(api, settings, { name, status, url, now });
  if (!gaps.has_folder) {
    return { said: "No Drive folder found for this project — use NEW PROJECT instead, "
      + "so Notion and the media drive are set up alongside it.", gaps, made: [] };
  }
  const lines = [];
  const made = [];
  const would = [];
  if (gaps.legacy_spine) {
    lines.push("Drive folders: left alone — this project uses its own older "
      + "numbering, and the filing rules say never renumber it.");
  } else if (gaps.loose_job) {
    lines.push("Drive folders: a Job's folder is loose by design.");
  } else if (gaps.missing_subfolders.length || gaps.missing_starters.length) {
    if (write) {
      const got = await repair(api, settings, { name, url });
      made.push(...got.made);
      lines.push(`Drive folders — ${got.said}`);
    } else {
      const plan = await planRepair(api, settings, { name, url });
      would.push(...plan.steps.map((s) => `${s.key}/`));
      lines.push(`Drive folders — ${plan.said}`);
    }
  } else {
    lines.push("Drive folders: already complete.");
  }
  if (gaps.showcase_due && (!gaps.has_showcase || gaps.missing_showcase_parts.length)) {
    if (write) {
      const got = await folders.showcaseAsk(api, settings, name, status, url);
      made.push(...got.made);
      lines.push(`Showcase — ${got.said}`);
    } else {
      const plan = await folders.planShowcase(api, settings, { name, status, drive_url: url }, now);
      if (!plan.ok) throw new Error(plan.why);
      would.push(...plan.steps.map((s) => (s.op === "file" ? `${s.key} (hidden marker)` : `${s.key}/`)));
      lines.push(`Showcase — ${plan.said}`);
    }
  } else if (!gaps.showcase_due && !gaps.has_showcase) {
    lines.push("Showcase: not due yet — Shoot Wrap builds it when this "
      + "project moves to Post.");
  }
  return { said: lines.join("\n"), gaps, made, ...(write ? {} : { would }) };
}

// ── the asks ─────────────────────────────────────────────────────────────────

/** The Drive, its settings and the project's Notion link. Hands the ask to
 * the Mac (Handoff) when the server cannot read — or, to write, make — folders. */
async function world(env, name, { write }) {
  const { Handoff, projectRow, notionOf, cloudReady } = await import("./cloud.js");
  const { driveApi } = await import("./drivewrite.js");
  const settings = await folders.settingsOf(env);
  if (write) {
    const ready = folders.readiness(env, settings);
    if (!ready.ok) throw new Handoff(ready.why);
  } else if (!settings.scratch && ["projects", "gigs", "showcases"].some((k) => !settings.roots[k])) {
    throw new Handoff("the Drive's root folders are not set");
  }
  const api = driveApi(env, { write });
  if (!api || (write && !api.mkdir)) throw new Handoff("the server has no Google sign-in for the Drive");
  if (settings.scratch) {
    const problem = await folders.scratchProblem(api, settings);
    if (problem) throw new Error(problem);
  }
  const row = cloudReady(env) && name ? await projectRow(notionOf(env), String(name)) : null;
  const url = (((row || {}).properties || {})["Drive Folder"] || {}).url || "";
  return { api, settings, url, Handoff };
}

/** A refusal from Google before anything was made is the Mac's to do instead. */
async function handOn(e) {
  const { Handoff } = await import("./cloud.js");
  const { DriveRefused } = await import("./drivewrite.js");
  const cause = e instanceof DriveRefused ? e : e && e.cause;
  if (cause instanceof DriveRefused && !(e.made && e.made.length)) throw new Handoff(cause.message);
  throw e;
}

/** `async (list, env) => result` per method; a Handoff hands the ask to the Mac. */
export const ASKS = {
  async project_gaps([name, status = ""], env) {
    const w = await world(env, name, { write: false });
    try { return await gapsOf(w.api, w.settings, { name: String(name || ""), status: String(status || ""), url: w.url }); } catch (e) { return handOn(e); }
  },
  async project_tree([name], env) {
    const w = await world(env, name, { write: false });
    try { return await treeOf(w.api, w.settings, { name: String(name || ""), url: w.url }); } catch (e) { return handOn(e); }
  },
  async repair_subfolders([name], env) {
    const w = await world(env, name, { write: true });
    try { return (await repair(w.api, w.settings, { name: String(name || ""), url: w.url })).said; } catch (e) { return handOn(e); }
  },
  async complete_setup([name, status = ""], env) {
    const w = await world(env, name, { write: true });
    try { return (await completeSetup(w.api, w.settings, { name: String(name || ""), status: String(status || ""), url: w.url })).said; } catch (e) { return handOn(e); }
  },
};

// ── the look ─────────────────────────────────────────────────────────────────

/**
 * What each ask would answer for one project, now, and what complete_setup
 * would make — read from the Drive, nothing written, switch or no switch.
 */
export async function look(env, name, status = "") {
  const { cloudReady } = await import("./cloud.js");
  const out = { switch: await healthOn(env), name, status };
  let w;
  try {
    w = await world(env, name, { write: false });
  } catch (e) {
    return { ...out, ok: false, why: String((e && e.message) || e) };
  }
  out.notion_link = w.url || null;
  out.notion = cloudReady(env);
  try {
    out.project_gaps = await gapsOf(w.api, w.settings, { name, status, url: w.url });
    out.project_tree = await treeOf(w.api, w.settings, { name, url: w.url });
    const plan = await planRepair(w.api, w.settings, { name, url: w.url });
    out.repair_subfolders = plan.ok ? { said: plan.said, make: plan.steps.map((s) => `${s.key}/`) } : plan;
    const cs = await completeSetup(w.api, w.settings, { name, status, url: w.url, write: false });
    out.complete_setup = { said: cs.said, make: cs.would || [] };
    out.ready_to_write = folders.readiness(env, w.settings);
    out.ok = true;
  } catch (e) {
    out.ok = false;
    out.why = String((e && e.message) || e).slice(0, 500);
  }
  return out;
}

/**
 * The server's own film copies for one project, found by every ID the
 * project has had (the old relay id kept as an alias of the one project ID
 * since stage 5 step 2, and the ID itself). Read only: what `film_restore`
 * could be handed from the server, for the Mac's report.
 */
export async function restoreLook(env, name) {
  const { projectRow, notionOf } = await import("./cloud.js");
  const { readIds, bare } = await import("./projectid.js");
  const row = await projectRow(notionOf(env), String(name || ""));
  if (!row) return { ok: false, why: "no Notion row" };
  const page = bare(row.id);
  const ids = await readIds(env);
  const project = ids.notion[page] || page;
  const recordGot = await env.BUCKET.get(`r/${project}/record.json`);
  let record = null;
  try { record = recordGot ? await recordGot.json() : null; } catch { record = null; }
  const relay = String((record && record.film && record.film.relay) || "");
  const all = new Set([project, page, ...(relay ? [relay] : [])]);
  for (const [alias, id] of Object.entries(ids.alias)) if (id === project) all.add(alias);
  const copies = {};
  for (const id of all) {
    if (!env.BACKUPS) break;
    for (const where of ["daily", "forever"]) {
      const listed = await env.BACKUPS.list({ prefix: `${where}/${id}/` });
      const stamps = (listed.objects || []).map((o) => o.key.split("/").pop().replace(/\.zip$/, ""));
      if (stamps.length) copies[`${where}/${id}`] = stamps.sort().reverse();
    }
  }
  return { ok: true, project, page, relay: relay || null, ids: [...all], copies };
}

/** The group's own doors: GET /console/studio/step6health/look?name=…&status=…, …/restore?name=… */
export async function door(env, rest, method, readBody, ctx, url) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest.length !== 2 || method !== "GET") return null;
  const q = url ? new URL(url).searchParams : new URLSearchParams();
  const name = String(q.get("name") || "");
  if (!name) return reply({ ok: false, why: "Say ?name=" }, 400);
  if (rest[1] === "look") return reply(await look(env, name, String(q.get("status") || "")));
  if (rest[1] === "restore") return reply(await restoreLook(env, name));
  return null;
}
