/**
 * **Google Drive folders, made by the server** (2026-10-13, Projects Console
 * without the Mac, stage 3 step 6). The rules; the Drive itself is
 * `drivewrite.js`.
 *
 * The Mac makes a project's Google Drive folders in three places, and each is
 * ported here rule for rule, with the filing rules as the spec — the two
 * documents he keeps on the Drive, `cinematography/.filing-rules.md` and
 * `cinematography/portfolio/showcase-structure.md`. **Where they and the code
 * disagree, the documents win** (each place is marked `DOCS:`).
 *
 * - **New Project** (`engine.create_project`): `projects/<slug>/` — or
 *   `gigs/<slug>/` for a quick job — with the DP Project profile's folders
 *   and the hidden `.gdrive-project` marker, refused when the folder is
 *   already there. The Notion row's `Drive Folder` link is
 *   `https://drive.google.com/drive/folders/<id>`.
 * - **New Shoot** (`rituals.plan_new_shoot`'s DRIVE half, `_shoot_folders`):
 *   `shoot-N/` in each section the project has, shaped like the last shoot's
 *   folder there, or the template; the first time, `shoot-1/` too.
 * - **The portfolio showcase** (`engine.create_showcase`):
 *   `portfolio/project-showcases/<slug>-showcase/` — or under
 *   `zz-archived/<year>/` for an archived project — with `stills/`,
 *   `website/` and the `.portfolio-project` marker.
 *
 * Plugged-in media drives (`/Volumes/wd-*`, `.media-project`) stay the Mac's
 * for good.
 *
 * **Only ever creates.** Nothing here moves, renames, trashes or deletes, and
 * the Drive client has no way to: a folder or file already there is reported
 * and left as it is, and a second run makes nothing new. Names are compared
 * as the Mac's Drive folder compares them, without regard to case.
 *
 * **A plan first** (`planProject`, `planShoot`, `planShowcase`): what would be
 * made, in order, and what is already there — read from the Drive, nothing
 * written. `carryOut` then makes exactly that, checking each name again as it
 * goes. The plans read through a small `api` ({list, get}) and `carryOut`
 * writes through one ({list, mkdir, mkfile}), so `hub/drivefolders.mjs`
 * checks every rule with a Drive held in memory.
 *
 * **Off until thrown** (`s/drivefolders.json`): `{on, roots, scratch}`. The
 * roots are the Drive's own ids for `cinematography/projects`, `gigs` and
 * `portfolio/project-showcases` (read on the Mac with `xattr -p
 * "com.google.drivefs.item-id#S"`), kept here, not in the code. `scratch`, a
 * throwaway folder's id, sends everything into `<scratch>/projects`,
 * `<scratch>/gigs` and `<scratch>/portfolio/project-showcases` instead, for
 * the first real test. Without the switch, the roots or the `GDRIVE_WRITE`
 * sign-in, the asks are the Mac's, as before.
 */

export const SWITCH_KEY = "s/drivefolders.json";
export const FOLDER_URL = "https://drive.google.com/drive/folders/";
const DRIVE_ID = /^[A-Za-z0-9_-]{10,120}$/;

/** `.filing-rules.md` → Project template: what a new project gets. The same
 * as the DP Project profile today (`~/.kc-project-creator/profiles.json`);
 * `s/drivefolders.json` may carry `template` when he changes the profile. */
export const PROJECT_TEMPLATE = [
  "1-creative", "1-creative/previs", "1-creative/reference", "1-creative/script", "1-creative/script/z-archive",
  "1-creative/script/current-draft", "1-creative/shot-list", "1-creative/shot-list/images", "1-creative/shot-list/live-sheet", "1-creative/storyboards",
  "2-logistics", "2-logistics/camera-spec", "2-logistics/camera-spec/live-sheet", "2-logistics/equipment", "2-logistics/locations", "2-logistics/schedule",
  "3-post", "3-post/camera-reports", "3-post/dailies-stills", "3-post/frame-line", "3-post/resolve-project",
  "3-post/show-lut", "3-post/show-lut/amls", "3-post/show-lut/cubes", "3-post/show-lut/lut-build-tests", "3-post/tests",
  "4-financial",
  "z-other", "z-other/bts-photos", "z-other/cadrage-frames",
];

/**
 * **The script's folder** (stage 5 step 4, piece C, 2026-10-14). His rule:
 * the script draws from Google Drive. `1-creative/script/current-draft/`
 * holds the draft in use, alone in its own folder so it is never mistaken;
 * every older draft is in `script/z-archive/`. Loose files in `script/` itself
 * are left alone. (His change, 2026-10-15: current-draft/ was added.) Lined
 * and compressed copies are outputs (`scriptdrive.js`).
 */
export const SCRIPT_FOLDERS = ["1-creative/script", "1-creative/script/z-archive", "1-creative/script/current-draft"];

/**
 * A template with the script's folders in it, placed after the rest of
 * `1-creative/`'s own folders that sort before it — or the template as it is
 * when it already has them, or has no `1-creative`.
 */
export function withScriptFolders(tree) {
  return withShotListFolders(withScriptOnly(tree));
}

/**
 * **The shot-list folder's two homes** (his ask, 2026-10-15): `images/` holds
 * the always-updating shot pictures (`images/scene-01/1a-1.jpg`) so they do
 * not overtake the folder, and `live-sheet/` holds the one spreadsheet
 * Studio keeps current, apart from his own spreadsheets. A template without
 * them gains them right after `1-creative/shot-list`.
 */
export const SHOTLIST_FOLDERS = ["1-creative/shot-list", "1-creative/shot-list/images", "1-creative/shot-list/live-sheet"];
export function withShotListFolders(tree) {
  const list = Array.isArray(tree) ? [...tree] : [];
  const has = (p) => list.some((t) => String(t).toLowerCase() === p);
  if (!has(SHOTLIST_FOLDERS[0])) return list;
  const missing = SHOTLIST_FOLDERS.filter((p) => !has(p));
  if (!missing.length) return list;
  const at = list.findIndex((t) => String(t).toLowerCase() === SHOTLIST_FOLDERS[0]);
  let end = at + 1;
  while (end < list.length && String(list[end]).toLowerCase().startsWith(`${SHOTLIST_FOLDERS[0]}/`)) end++;
  list.splice(end, 0, ...missing);
  return list;
}

/**
 * **The camera spec folder** (his ask, 2026-10-15): `2-logistics/camera-spec/`
 * is the project's camera information, his own PDFs and spreadsheets loose in
 * it; `live-sheet/` holds the one Google Sheet the server keeps current from
 * the project's Camera Spec Sheet (`specsheetsheetdoor.js`), apart from his
 * own files. A template without them gains them right after `2-logistics`.
 */
export const CAMERA_SPEC_FOLDERS = ["2-logistics", "2-logistics/camera-spec", "2-logistics/camera-spec/live-sheet"];
export function withCameraSpecFolders(tree) {
  const list = Array.isArray(tree) ? [...tree] : [];
  const has = (p) => list.some((t) => String(t).toLowerCase() === p);
  if (!has(CAMERA_SPEC_FOLDERS[0])) return list;
  const missing = CAMERA_SPEC_FOLDERS.filter((p) => !has(p));
  if (!missing.length) return list;
  const at = list.findIndex((t) => String(t).toLowerCase() === CAMERA_SPEC_FOLDERS[0]);
  list.splice(at + 1, 0, ...missing);
  return list;
}

function withScriptOnly(tree) {
  // A template kept from before 2026-10-15 names it `archive`; archive folders are all `z-archive` now.
  const list = (Array.isArray(tree) ? [...tree] : []).map((t) => (String(t).toLowerCase() === "1-creative/script/archive" ? "1-creative/script/z-archive" : t));
  const has = (p) => list.some((t) => String(t).toLowerCase() === p);
  if (!has("1-creative") || SCRIPT_FOLDERS.every(has)) return list;
  const missing = SCRIPT_FOLDERS.filter((p) => !has(p));
  if (has(SCRIPT_FOLDERS[0])) {
    const at = list.findIndex((t) => String(t).toLowerCase() === SCRIPT_FOLDERS[0]);
    let end = at + 1;
    while (end < list.length && String(list[end]).toLowerCase().startsWith(`${SCRIPT_FOLDERS[0]}/`)) end++;
    list.splice(end, 0, ...missing);
    return list;
  }
  // After the last of 1-creative's direct children (and theirs) that sort before "script".
  let at = list.findIndex((t) => String(t).toLowerCase() === "1-creative") + 1;
  for (let i = at; i < list.length; i++) {
    const t = String(list[i]).toLowerCase();
    if (!t.startsWith("1-creative/")) break;
    const child = t.slice("1-creative/".length).split("/")[0];
    if (child < "script") at = i + 1; else break;
  }
  list.splice(at, 0, ...missing);
  return list;
}

/** shoots.py: the sections a shoot gets a `shoot-N/` in, and what one holds
 * when there is no earlier shoot folder to copy the shape from. */
export const SHOOT_SECTIONS = ["1-creative", "2-logistics", "3-post", "4-financial", "z-other"];
export const SHOOT_TEMPLATE = {
  "1-creative": ["previs"],
  "2-logistics": [],
  "3-post": ["camera-reports", "dailies-stills", "resolve-project"],
  "4-financial": [],
  "z-other": ["bts-photos", "cadrage-frames"],
};

/** The hidden markers, word for word as the Mac writes them
 * (`engine._write_marker`, `engine.create_showcase`). */
export const MARKERS = {
  project: { name: ".gdrive-project", text: "projects-console: this is the gdrive project copy\n" },
  showcase: { name: ".portfolio-project", text: "projects-console: this is a portfolio showcase folder\n" },
};

const SHOWCASE_SUFFIX = "-showcase";
const ROOT_PATHS = { projects: ["projects"], gigs: ["gigs"], showcases: ["portfolio", "project-showcases"] };
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);

// ── names, as Python has them ────────────────────────────────────────────────

const ALNUM = /^[\p{L}\p{N}]$/u;

/** `engine.slugify` / `rituals._slug`: every character that is not a letter
 * or a digit becomes a dash, lower case, dashes trimmed from the ends. */
export function slugify(name) {
  let out = "";
  for (const c of String(name || "").toLowerCase()) out += ALNUM.test(c) ? c : "-";
  return out.replace(/^-+|-+$/g, "");
}

/** `rituals._loose_match`: one inside the other, or the same once every
 * non-letter is dropped. */
export function looseMatch(folderName, slug) {
  const dn = String(folderName).toLowerCase();
  if (dn.includes(slug) || slug.includes(dn)) return true;
  const squash = (s) => [...s].filter((c) => ALNUM.test(c)).join("");
  return squash(dn) === squash(slug);
}

/** Python's `sorted()` on names: by code point. */
const byCodePoint = (a, b) => {
  const x = [...a], y = [...b];
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d) return d;
  }
  return x.length - y.length;
};

/** The Mac's Drive folder ignores case: `PROJECTS` opens `projects`. */
const same = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();
/** The child of that name: the exact spelling first, else any case. */
export const childNamed = (kids, name) => kids.find((k) => k.name === name) || kids.find((k) => same(k.name, name)) || null;

/** The year an archive move happens in, on his clock. */
export function yearNow(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Vancouver", year: "numeric" }).format(now);
}

export const folderUrl = (id) => `${FOLDER_URL}${id}`;
export function idFromUrl(url) {
  const m = /\/folders\/([A-Za-z0-9_-]+)/.exec(String(url || ""));
  return m ? m[1] : "";
}

// ── the switch and its settings ──────────────────────────────────────────────

/** `{on, at, by, roots, scratch, template}` — off, with no roots, until set. */
export async function settingsOf(env) {
  let v = {};
  const got = await env.BUCKET.get(SWITCH_KEY);
  if (got) { try { v = await got.json(); } catch { v = {}; } }
  if (!isObject(v)) v = {};
  const roots = {};
  for (const k of Object.keys(ROOT_PATHS)) if (isObject(v.roots) && DRIVE_ID.test(String(v.roots[k] || ""))) roots[k] = v.roots[k];
  let template = Array.isArray(v.template) && v.template.every((t) => typeof t === "string" && t) ? v.template : null;
  // The folder template's master copy (foldertemplate.js, stage 5 step 3)
  // wins once written; it is not kept in this switch's own settings.
  let fromMaster = false;
  try {
    const kept = await env.BUCKET.get("s/folder-template.json");
    const t = kept ? await kept.json() : null;
    if (t && Array.isArray(t.drive) && t.drive.length && t.drive.every((x) => typeof x === "string" && x)) { template = t.drive; fromMaster = true; }
  } catch { /* the switch's own, or today's */ }
  return {
    on: v.on === true, at: v.at || null, by: v.by || null, roots,
    scratch: DRIVE_ID.test(String(v.scratch || "")) ? v.scratch : null,
    ...(template ? { template } : {}),
    ...(fromMaster ? { template_master: true } : {}),
  };
}

/** A switch change: `on`, and `roots` / `scratch` / `template` when given
 * (`scratch: null` clears it). Answers the settings as kept, or `{problem}`. */
export function changedSettings(now, said) {
  const s = isObject(said) ? said : {};
  const out = { ...now, on: s.on === true, at: new Date().toISOString(), by: String(s.by || "").slice(0, 80) };
  // the master copy's template is not this switch's to keep
  if (out.template_master) { delete out.template; delete out.template_master; }
  if (s.roots !== undefined) {
    if (!isObject(s.roots)) return { problem: "roots is {projects, gigs, showcases}, each a Drive folder id." };
    const roots = { ...now.roots };
    for (const [k, v] of Object.entries(s.roots)) {
      if (!(k in ROOT_PATHS)) return { problem: `${k} is not one of projects, gigs, showcases.` };
      if (!DRIVE_ID.test(String(v || ""))) return { problem: `${k} is not a Drive folder id.` };
      roots[k] = v;
    }
    out.roots = roots;
  }
  if (s.scratch !== undefined) {
    if (s.scratch === null || s.scratch === "") out.scratch = null;
    else if (!DRIVE_ID.test(String(s.scratch))) return { problem: "scratch is a Drive folder id, or null." };
    else if (Object.values(out.roots || {}).includes(s.scratch)) return { problem: "scratch must be a throwaway folder, not one of the real roots." };
    else out.scratch = s.scratch;
  }
  if (s.template !== undefined) {
    if (s.template === null) delete out.template;
    else if (!Array.isArray(s.template) || !s.template.every((t) => typeof t === "string" && /^[^/.][^/]*(\/[^/.][^/]*)*$/.test(t))) {
      return { problem: "template is a list of folder paths like 1-creative/previs." };
    } else out.template = s.template;
  }
  return out;
}

/** Whether the server makes the folders now, and why not. */
export function readiness(env, settings) {
  if (!settings.on) return { ok: false, why: "the switch is off" };
  if (!env.GDRIVE_WRITE) return { ok: false, why: "the server has no Google sign-in that can make folders" };
  if (!settings.scratch && Object.keys(ROOT_PATHS).some((k) => !settings.roots[k])) return { ok: false, why: "the Drive's root folders are not set" };
  return { ok: true };
}

// ── finding the roots, and a project's folder ────────────────────────────────

/**
 * Where each root is: `{key: {id} | {missing: [names], under: id}}`. With a
 * scratch folder every root is looked for by name inside it, and one not
 * there yet is made there on the run (never in the real Drive).
 */
export async function rootsOf(api, settings) {
  const out = {};
  for (const [key, path] of Object.entries(ROOT_PATHS)) {
    if (!settings.scratch) {
      out[key] = { id: settings.roots[key], path: path.join("/") };
      continue;
    }
    let at = settings.scratch;
    let missing = null;
    for (let i = 0; i < path.length; i++) {
      const hit = childNamed((await api.list(at)).filter((k) => k.folder), path[i]);
      if (!hit) { missing = path.slice(i); break; }
      at = hit.id;
    }
    out[key] = missing ? { under: at, missing, path: path.join("/") } : { id: at, path: path.join("/") };
  }
  return out;
}

/** A scratch folder must be a throwaway one: never a project's or a showcase's. */
export async function scratchProblem(api, settings) {
  if (!settings.scratch) return "";
  const kids = await api.list(settings.scratch);
  if (kids.some((k) => same(k.name, MARKERS.project.name) || same(k.name, MARKERS.showcase.name) || same(k.name, ".media-project"))) {
    return "the scratch folder is a project's or a showcase's own folder; use an empty throwaway folder";
  }
  const me = await api.get(settings.scratch);
  if (!me || !me.folder || me.trashed) return "the scratch folder can't be found on the Drive";
  return "";
}

const folders = async (api, id) => (id ? (await api.list(id)).filter((k) => k.folder) : []);

/**
 * The project's Drive folder — `engine.project_drive_folder` and
 * `rituals.find_project_folder`. The Notion link first (the server has the
 * folder's own id for free; the Mac reads every folder's id from its disk to
 * do the same, so it looks by name first), then the slug exactly under
 * `projects/` and `gigs/`, then loosely (`_loose_match`, folders not starting
 * `z-`). `archived`: `projects/z-archived/<year>/` too, newest year first.
 */
export async function findProjectFolder(api, roots, name, driveUrl, { archived = false } = {}) {
  const linked = idFromUrl(driveUrl);
  if (linked) {
    const got = await api.get(linked);
    if (got && got.folder && !got.trashed) return { id: got.id, name: got.name, how: "link" };
  }
  const slug = slugify(name);
  if (!slug) return null;
  const homes = [];
  for (const key of ["projects", "gigs"]) if (roots[key] && roots[key].id) homes.push(await folders(api, roots[key].id));
  for (const kids of homes) {
    const hit = childNamed(kids, slug);
    if (hit) return { id: hit.id, name: hit.name, how: "name" };
  }
  for (const kids of homes) {
    for (const d of [...kids].sort((a, b) => byCodePoint(a.name, b.name))) {
      if (d.name.startsWith("z-") || d.name.startsWith(".")) continue;
      if (looseMatch(d.name, slug)) return { id: d.id, name: d.name, how: "loose" };
    }
  }
  if (!archived || !(roots.projects && roots.projects.id)) return null;
  const za = childNamed(homes[0] || [], "z-archived");
  if (!za) return null;
  const years = (await folders(api, za.id)).sort((a, b) => byCodePoint(b.name, a.name));
  for (const year of years) {
    const kids = await folders(api, year.id);
    const exact = childNamed(kids, slug);
    if (exact) return { id: exact.id, name: exact.name, how: "archived" };
    for (const d of [...kids].sort((a, b) => byCodePoint(a.name, b.name))) {
      if (d.name.startsWith(".")) continue;
      if (looseMatch(d.name, slug)) return { id: d.id, name: d.name, how: "archived" };
    }
  }
  return null;
}

// ── plans ────────────────────────────────────────────────────────────────────

/**
 * A plan: `{ok, kind, steps, ids, notes, said}` or `{ok: false, why}`.
 * Each step is `{op: "folder" | "file", key, parent, name, text?, exists}`;
 * `key` is its place as the filing rules name it (`projects/lets-bake/3-post`)
 * and `parent` the key of the folder it goes in, whose id is in `ids` or is
 * made by an earlier step.
 */
function newPlan(kind) {
  return { ok: true, kind, steps: [], ids: {}, notes: [], said: "" };
}

/** The steps that make a root a scratch folder does not have yet. */
function rootSteps(plan, root) {
  if (root.id) { plan.ids[root.path] = root.id; return; }
  const all = root.path.split("/");
  const have = all.slice(0, all.length - root.missing.length);
  const base = have.length ? have.join("/") : "(scratch)";
  plan.ids[base] = root.under;
  let parent = base;
  for (const name of root.missing) {
    const key = parent === "(scratch)" ? name : `${parent}/${name}`;
    plan.steps.push({ op: "folder", key, parent, name, exists: false });
    parent = key;
  }
}

/** Every folder a template names, its parents before it, once each. */
function templateFolders(template) {
  const out = [];
  const seen = new Set();
  for (const rel of template) {
    const parts = rel.split("/").filter(Boolean);
    for (let i = 1; i <= parts.length; i++) {
      const p = parts.slice(0, i).join("/");
      if (!seen.has(p)) { seen.add(p); out.push(p); }
    }
  }
  return out;
}

/**
 * New Project's Drive folder — `engine.create_project`, the Google Drive
 * half. `form` is the console's: `name`, `drive_name`, `home`
 * (`projects` | `gigs`), `tier1`. Refused, in the Mac's words, with no name
 * or with a folder of that name already there.
 */
export async function planProject(api, settings, form) {
  const f = isObject(form) ? form : {};
  const name = String(f.name || "").trim();
  const driveName = String(f.drive_name || "").trim();
  const slug = slugify(driveName || name);
  if (!slug) return { ok: false, why: "Project needs a name." };
  const section = f.home === "gigs" ? "gigs" : "projects";
  const problem = await scratchProblem(api, settings);
  if (problem) return { ok: false, why: problem };
  const roots = await rootsOf(api, settings);
  const root = roots[section];
  const plan = newPlan("project");
  plan.slug = slug;
  plan.section = section;
  rootSteps(plan, root);
  if (root.id) {
    const kids = await api.list(root.id);
    const there = kids.find((k) => same(k.name, slug));
    if (there && !(await adoptable(api, there, f.id))) {
      return { ok: false, why: `${section}/${slug} already exists in Google Drive — pick another name.` };
    }
    // **Made by a Mac offline** (stage 5 step 3): its marker names this
    // project's ID, so it is this project's folder — finished, never doubled.
    if (there) plan.adopted = true;
  }
  const top = `${section}/${slug}`;
  plan.steps.push({ op: "folder", key: top, parent: section, name: slug, exists: false });
  plan.tier1 = f.tier1 === undefined ? true : Boolean(f.tier1);
  // **A Job's folder is loose** (2026-10-15, his rule; `.filing-rules.md`:
  // "Tier 2 Job → gigs/ folder + Job Log row only, deliberately no
  // ceremony"): the folder and its hidden marker, none of the template's.
  // `job` is the sheet's Kind; an older sheet's quick job (tier1 false, no
  // `job`) is a Job, as the Mac reads it (backend.new_project_form).
  plan.job = "job" in f ? jobSaid(f.job) : !plan.tier1;
  const template = plan.job ? [] : (settings.template || PROJECT_TEMPLATE);
  for (const rel of templateFolders(template)) {
    const at = rel.lastIndexOf("/");
    plan.steps.push({ op: "folder", key: `${top}/${rel}`, parent: at < 0 ? top : `${top}/${rel.slice(0, at)}`,
      name: at < 0 ? rel : rel.slice(at + 1), exists: false });
  }
  plan.steps.push({ op: "file", key: `${top}/${MARKERS.project.name}`, parent: top, name: MARKERS.project.name,
    text: MARKERS.project.text, exists: false });
  plan.folder = top;
  plan.count = template.length;
  plan.said = `${plan.adopted ? "Google Drive folder made offline, finished" : "Google Drive folder created"}: ${top}`
    + (plan.job ? "" : ` (${template.length} folders)`)
    + (plan.tier1 ? "" : "\nQuick job — no Notion row, by design.");
  return plan;
}

/** The sheet's `job`, as the Mac's `bool()` and the server's `truthy` both read a sent value. */
const jobSaid = (v) => v === true || v === 1 || v === "1" || v === "true" || v === "on";

/** The line a Mac's offline New Project adds to the marker it writes, so the
 * server can tell the folder is that project's and finish it (offline.py). */
export const ADOPT_LINE = "project-id: ";

/**
 * Whether a project folder already in the Drive is the one a Mac made
 * offline for this very project: it holds the `.gdrive-project` marker and
 * the marker names `id`. Anything else (no id, no marker, another id) is
 * someone else's folder and New Project refuses, as before.
 */
export async function adoptable(api, folder, id) {
  const want = String(id || "").trim().toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(want) || !folder || !folder.folder || typeof api.text !== "function") return false;
  const kids = await api.list(folder.id);
  const marker = kids.find((k) => !k.folder && k.name === MARKERS.project.name);
  if (!marker) return false;
  const words = String(await api.text(marker.id) || "");
  return words.split(/\r?\n/).some((line) => line.trim().toLowerCase() === `${ADOPT_LINE}${want}`);
}

/** `rituals._shoot_folders`: `[section, folder key, [subfolders], exists]`
 * for each section the project has, shaped like its last earlier shoot. */
async function shootFolders(api, pdir, n, sections) {
  const out = [];
  for (const section of SHOOT_SECTIONS) {
    const sec = childNamed(sections, section);
    if (!sec) continue;
    const kids = await folders(api, sec.id);
    const earlier = [];
    for (const d of kids) {
      const m = /^shoot-(\d+)$/.exec(d.name);
      if (m && Number(m[1]) < n) earlier.push([Number(m[1]), d]);
    }
    let subs;
    if (earlier.length) {
      const last = earlier.sort((a, b) => a[0] - b[0] || byCodePoint(a[1].name, b[1].name))[earlier.length - 1][1];
      subs = (await folders(api, last.id)).map((c) => c.name).filter((c) => !c.startsWith(".")).sort(byCodePoint);
    } else {
      subs = [...(SHOOT_TEMPLATE[section] || [])];
    }
    const there = childNamed(kids, `shoot-${n}`);
    out.push({ section: sec.name, secId: sec.id, name: `shoot-${n}`, subs, exists: Boolean(there), id: there ? there.id : "" });
  }
  return out;
}

/**
 * New Shoot's Drive folders — the DRIVE half of `rituals.plan_new_shoot`.
 * `shoot` is what the Notion half already knows: `name`, `status`, `dates`
 * (the project's Shoot Dates start), `drive_url`, and `rows` (its Shoots
 * rows, each with `n`). `n` is the new shoot's number; with no rows, the
 * project's own shoot becomes `shoot-1` and this one `shoot-2`.
 */
export async function planShoot(api, settings, shoot) {
  const s = isObject(shoot) ? shoot : {};
  const name = String(s.name || "");
  if (s.status === "Archived") {
    return { ok: false, why: `${name} is Archived — its folder is in projects/z-archived/, and bringing `
      + `a project back is its own decision. Set it back to Active first if `
      + `another shoot is really coming.` };
  }
  const rows = Array.isArray(s.rows) ? s.rows : [];
  const firstTime = !rows.length;
  const numbers = rows.map((r) => Number(r && r.n) || 0).filter(Boolean);
  const n = Number(s.n) || (numbers.length ? Math.max(...numbers) + 1 : (firstTime ? 2 : rows.length + 1));
  if (firstTime && !String(s.dates || "").slice(0, 10)) {
    return { ok: false, why: `${name} has no Shoot Dates, so there is no first shoot to build Shoot 1 `
      + `from. Put its date in Notion first, or set this one up as Shoot 1 by hand.` };
  }
  const problem = await scratchProblem(api, settings);
  if (problem) return { ok: false, why: problem };
  const roots = await rootsOf(api, settings);
  const plan = newPlan("shoot");
  plan.n = n;
  plan.first_time = firstTime;
  const pdir = await findProjectFolder(api, roots, name, s.drive_url);
  if (!pdir) {
    plan.notes.push("No Drive folder found for this project — no shoot folders made");
    return plan;
  }
  plan.project_folder = pdir.name;
  plan.ids[pdir.name] = pdir.id;
  const sections = await folders(api, pdir.id);
  const add = (one, quiet) => {
    const key = `${pdir.name}/${one.section}/${one.name}`;
    if (one.exists) {
      if (!quiet) plan.notes.push(`${one.section}/${one.name}/ is already there.`);
      return;
    }
    plan.ids[`${pdir.name}/${one.section}`] = one.secId;
    plan.steps.push({ op: "folder", key, parent: `${pdir.name}/${one.section}`, name: one.name, exists: false });
    for (const sub of one.subs) plan.steps.push({ op: "folder", key: `${key}/${sub}`, parent: key, name: sub, exists: false });
  };
  if (firstTime) for (const one of await shootFolders(api, pdir, 1, sections)) add(one, true);
  const now = await shootFolders(api, pdir, n, sections);
  for (const one of now) add(one, false);
  if (!now.length) {
    plan.notes.push("This project uses an older folder layout (no 2-logistics / "
      + "3-post / 4-financial / z-other) — no shoot folders made");
  }
  return plan;
}

/**
 * The portfolio showcase — `engine.create_showcase`. Found live or archived
 * by its `-showcase` name (never by the marker: older showcases have none);
 * when there is none, made where it belongs, straight under
 * `zz-archived/<year>/` for an archived project.
 *
 * DOCS: `showcase-structure.md` (2026-08-13) holds website thumbnails flat in
 * `website/`, no subfolders, and dropped `website/<slug>/1-thumbnails/`. A
 * showcase gets `stills/` and `website/`, and one that has a `website/`
 * folder is complete there — the Mac's `rituals.missing_showcase_parts` the
 * same since 2026-10-13.
 */
export async function planShowcase(api, settings, showcase, now = new Date()) {
  const s = isObject(showcase) ? showcase : {};
  const name = String(s.name || "");
  const loose = slugify(name);
  // A name with no letters or digits would loosely match every folder (the
  // Mac's `_loose_match` with an empty slug): refused here instead.
  if (!loose && !idFromUrl(s.drive_url)) return { ok: false, why: "A project needs a name." };
  const archived = String(s.status || "").trim().toLowerCase() === "archived";
  const problem = await scratchProblem(api, settings);
  if (problem) return { ok: false, why: problem };
  const roots = await rootsOf(api, settings);
  const plan = newPlan("showcase");
  const pdir = await findProjectFolder(api, roots, name, s.drive_url, { archived: true });
  const slug = pdir ? pdir.name : loose;
  plan.slug = slug;
  rootSteps(plan, roots.showcases);
  const base = roots.showcases.path;
  // Every folder a showcase can sit in: the live one, then each zz-archived
  // year, newest first (`_showcase_parents`).
  const parents = [];
  let zz = null;
  if (roots.showcases.id) {
    const top = await folders(api, roots.showcases.id);
    parents.push({ key: base, id: roots.showcases.id, kids: top, year: "" });
    zz = childNamed(top, "zz-archived");
    if (zz) {
      const years = (await folders(api, zz.id)).sort((a, b) => byCodePoint(b.name, a.name));
      for (const y of years) parents.push({ key: `${base}/zz-archived/${y.name}`, id: y.id, kids: await folders(api, y.id), year: y.name });
    }
  }
  let found = null;
  for (const p of parents) {
    const hit = childNamed(p.kids, `${slug}${SHOWCASE_SUFFIX}`);
    if (hit) { found = { parent: p, folder: hit }; break; }
  }
  if (!found && loose) {
    for (const p of parents) {
      for (const d of [...p.kids].sort((a, b) => byCodePoint(a.name, b.name))) {
        if (!d.name.endsWith(SHOWCASE_SUFFIX)) continue;
        if (looseMatch(d.name.slice(0, -SHOWCASE_SUFFIX.length), loose)) { found = { parent: p, folder: d }; break; }
      }
      if (found) break;
    }
  }
  const fresh = !found;
  let key, where;
  if (found) {
    key = `${found.parent.key}/${found.folder.name}`;
    plan.ids[found.parent.key] = found.parent.id;
    plan.ids[key] = found.folder.id;
    where = found.parent.key;
  } else if (archived) {
    const year = yearNow(now);
    let parentKey = base;
    if (zz) { plan.ids[`${base}/zz-archived`] = zz.id; } else {
      plan.steps.push({ op: "folder", key: `${base}/zz-archived`, parent: base, name: "zz-archived", exists: false });
    }
    parentKey = `${base}/zz-archived/${year}`;
    const y = parents.find((p) => p.year === year);
    if (y) plan.ids[parentKey] = y.id;
    else plan.steps.push({ op: "folder", key: parentKey, parent: `${base}/zz-archived`, name: year, exists: false });
    key = `${parentKey}/${slug}${SHOWCASE_SUFFIX}`;
    plan.steps.push({ op: "folder", key, parent: parentKey, name: `${slug}${SHOWCASE_SUFFIX}`, exists: false });
    where = parentKey;
  } else {
    key = `${base}/${slug}${SHOWCASE_SUFFIX}`;
    plan.steps.push({ op: "folder", key, parent: base, name: `${slug}${SHOWCASE_SUFFIX}`, exists: false });
    where = base;
  }
  const inside = found ? await api.list(found.folder.id) : [];
  const has = (n, folder = true) => inside.some((k) => same(k.name, n) && (!folder || k.folder));
  // Which folders a showcase is "complete" with. Create Showcase wants stills/
  // and website/; Prepare Showcase passes its own `parts` (stills/ and
  // select-stills/) because website/ is his, by hand, and that flow never
  // makes it (2026-10-17).
  const wanted = Array.isArray(s.parts) && s.parts.length ? s.parts : ["stills", "website"];
  const missing = wanted.filter((part) => !has(part));
  const showcaseName = key.slice(key.lastIndexOf("/") + 1);
  plan.showcase = key;
  if (!fresh && !missing.length) {
    plan.said = `Already complete: ${showcaseName}`;
    return plan;
  }
  if (!has(MARKERS.showcase.name, false)) {
    plan.steps.push({ op: "file", key: `${key}/${MARKERS.showcase.name}`, parent: key, name: MARKERS.showcase.name,
      text: MARKERS.showcase.text, exists: false });
  }
  for (const part of missing) plan.steps.push({ op: "folder", key: `${key}/${part}`, parent: key, name: part, exists: false });
  plan.said = `${fresh ? "Created" : "Completed"} ${where.replace(/^\(scratch\)\/?/, "")}/${showcaseName} — `
    + `${missing.join(", ") || "nothing new"}. Curated stills still go in by hand (or by running Shoot Wrap).`;
  return plan;
}

// ── carrying a plan out ──────────────────────────────────────────────────────

/**
 * Make what the plan says, in order — each name checked again first, so a
 * folder that turned up since the look is used, not doubled. A file where a
 * folder should be stops that branch. Stops at the first thing the Drive
 * refuses. Answers `{made, already, failed, ids}`, keys in order.
 */
export async function carryOut(api, plan) {
  const ids = { ...plan.ids };
  const fresh = new Set();          // folders made in this run: nothing in them to look for
  const listed = new Map();
  const made = [], already = [], failed = [];
  const blocked = new Set();
  for (const step of plan.steps) {
    if (blocked.has(step.parent) || !ids[step.parent]) {
      blocked.add(step.key);
      failed.push({ key: step.key, why: "skipped — the folder it goes in was not made" });
      continue;
    }
    const pid = ids[step.parent];
    let kids = [];
    if (!fresh.has(pid)) {
      if (!listed.has(pid)) listed.set(pid, await api.list(pid));
      kids = listed.get(pid);
    }
    const hit = childNamed(kids, step.name);
    if (hit) {
      if (step.op === "folder" && !hit.folder) {
        blocked.add(step.key);
        failed.push({ key: step.key, why: `a file, not a folder, is called ${hit.name} — left as it is` });
        continue;
      }
      ids[step.key] = hit.id;
      already.push(step.key);
      continue;
    }
    try {
      const got = step.op === "folder" ? await api.mkdir(pid, step.name) : await api.mkfile(pid, step.name, step.text || "");
      ids[step.key] = got.id;
      if (step.op === "folder") fresh.add(got.id);
      if (listed.has(pid)) listed.get(pid).push({ id: got.id, name: step.name, folder: step.op === "folder" });
      made.push(step.key);
    } catch (e) {
      failed.push({ key: step.key, why: String((e && e.message) || e).slice(0, 300) });
      return { made, already, failed, ids, stopped: true, error: e };
    }
  }
  return { made, already, failed, ids };
}

/** A plan as a look shows it: what would be made, what is there, nothing else. */
export function shown(plan) {
  if (!plan.ok) return plan;
  const out = {
    ok: true, kind: plan.kind,
    make: plan.steps.map((s) => (s.op === "file" ? `${s.key} (hidden marker)` : `${s.key}/`)),
    notes: plan.notes, said: plan.said,
  };
  for (const k of ["slug", "section", "folder", "tier1", "job", "n", "first_time", "project_folder", "showcase"]) {
    if (plan[k] !== undefined) out[k] = plan[k];
  }
  return out;
}

// ── the three asks, and the doors ────────────────────────────────────────────

/** The Mac's create_showcase, answered here: its one sentence. */
export async function showcaseAsk(api, settings, name, status, driveUrl) {
  const plan = await planShowcase(api, settings, { name, status, drive_url: driveUrl });
  if (!plan.ok) throw new Error(plan.why);
  if (!plan.steps.length) return { said: plan.said, made: [] };
  const got = await carryOut(api, plan);
  if (got.failed.length) {
    const e = new Error(`Showcase not finished — ${got.failed.map((f) => `${f.key}: ${f.why}`).join("; ")}`);
    e.made = got.made;
    e.cause = got.error;
    throw e;
  }
  return { said: plan.said, made: got.made };
}

/** New Project's Drive half: the folder, its folders, the marker. Answers the
 * plan, what was made, and the folder's link for the Notion row. */
export async function projectFolders(api, settings, form) {
  const plan = await planProject(api, settings, form);
  if (!plan.ok) throw new Error(plan.why);
  const got = await carryOut(api, plan);
  if (got.failed.length) {
    const e = new Error(`The Drive folder was not finished — ${got.failed.map((f) => `${f.key}: ${f.why}`).join("; ")}`);
    e.made = got.made;
    e.cause = got.error;
    throw e;
  }
  return { plan, made: got.made, url: folderUrl(got.ids[plan.folder]), id: got.ids[plan.folder] };
}

/** New Shoot's Drive half. */
export async function shootFolderMake(api, settings, shoot) {
  const plan = await planShoot(api, settings, shoot);
  if (!plan.ok) throw new Error(plan.why);
  const got = await carryOut(api, plan);
  return { plan, ...got };
}

/**
 * The Notion row's `Drive Folder`, after the folder is made: written when
 * empty, left when it already names this folder, and never written over a
 * link to another folder (said, not changed).
 */
export function linkPlan(row, url) {
  const have = (((row || {}).properties || {})["Drive Folder"] || {}).url || "";
  if (!have) return { write: true, said: "Notion's Drive Folder link written" };
  if (idFromUrl(have) === idFromUrl(url)) return { write: false, said: "Notion's Drive Folder link already names this folder" };
  return { write: false, said: `Notion's Drive Folder link names another folder (${have}) — left as it is` };
}
