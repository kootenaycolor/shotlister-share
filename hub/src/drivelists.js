/**
 * **Folder lists the phone reads with the Mac off** (2026-10-11, Projects
 * Console without the Mac, stage 3 step 5). Two lists only the Mac can read,
 * because only it has the disks, which it now sends here whenever they change
 * (`folderpublish.py` in Projects Console):
 *
 * - **A media drive's project folders** — `drive_tree` on the Mac
 *   (`engine.list_drive_folders`): read off the drive while it is plugged in,
 *   and for a drive on the shelf the list its last scan remembered (the R74
 *   snapshot). Kept at `s/drive-folders.json`, `{drives: {<name, lower case>:
 *   {folders, at}}, at}`, `at` being when the Mac read that drive (null for a
 *   list read before it said so).
 * - **A project's Google Drive folder, two levels down** — what the Mac's
 *   `project_page` reads (`projectpage.folder_tree`), so the server's project
 *   page has each shoot's `shoot-N` folders and the Next box can call them
 *   ready. Kept beside the project's record, `r/<page>/folders.json`,
 *   `{page, name, path, tree, at}`.
 *
 * **A plugged-in drive with the Mac awake is still the Mac's**: it reads the
 * drive now, which beats any copy (`driveTree` answers `null`, and cloud.js
 * hands the ask on). Everything else is answered here, in the Mac's shape,
 * with `as_of` on each row — when the drive was read — so the phone can say
 * how old the list is, as it does for the lights.
 *
 *   GET /console/studio/folders   what is held: each drive's count and age, each project's
 *   PUT /console/studio/folders   {drives?, projects?} — from the Mac; drives replace the
 *                                 whole list, projects are written one by one
 */

const DRIVES_KEY = "s/drive-folders.json";
const STUDIO_KEY = "s/studio.json";
const PAGE = /^[0-9a-f]{32}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z$/;
/** The phone's own rule for an awake Mac: it checked in within three minutes. */
const AWAKE_MS = 180 * 1000;
const MAX_BODY = 8 * 1024 * 1024;

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const projectKey = (page) => `r/${page}/folders.json`;

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

function cleanAt(at) {
  return typeof at === "string" && ISO.test(at) ? at : null;
}

/** A drive's rows as the Mac answers them; anything else in the body is dropped. */
function cleanRows(folders) {
  return (Array.isArray(folders) ? folders : []).filter(isObject).map((f) => ({
    name: String(f.name || ""),
    parent: String(f.parent || ""),
    year: String(f.year || ""),
    path: String(f.path || ""),
    children: Array.isArray(f.children) ? f.children : [],
  }));
}

/** Whether the Mac is awake with this drive plugged in, by its last snapshot. */
export function macReadsIt(studio, name, now = Date.now()) {
  if (!isObject(studio) || !studio.at) return false;
  const seen = Date.parse(studio.at);
  if (!Number.isFinite(seen) || now - seen >= AWAKE_MS) return false;
  const want = String(name || "").trim().toLowerCase();
  return (Array.isArray(studio.drives) ? studio.drives : []).some((d) => isObject(d) && d.mounted === true
    && [d.name, d.volume].some((n) => String(n || "").toLowerCase() === want));
}

/**
 * `drive_tree(volume_name)`: the rows the Mac would answer, each with `as_of`,
 * or `null` when the Mac should answer it (awake, drive plugged in).
 */
export async function driveTree(env, name, now = Date.now()) {
  const want = String(name || "").trim().toLowerCase();
  if (macReadsIt(await readJson(env, STUDIO_KEY), want, now)) return null;
  const held = await readJson(env, DRIVES_KEY);
  const one = held && isObject(held.drives) ? held.drives[want] : null;
  if (!isObject(one)) return [];
  const asOf = cleanAt(one.at) || "";
  return cleanRows(one.folders).map((f) => ({ ...f, as_of: asOf }));
}

/** The project's folder as the Mac last read it: {path, tree, at} or null. */
export async function projectFolders(env, page) {
  if (!env || !env.BUCKET || !PAGE.test(String(page || ""))) return null;
  const held = await readJson(env, projectKey(page));
  if (!isObject(held)) return null;
  return {
    path: String(held.path || ""),
    tree: Array.isArray(held.tree) ? held.tree : [],
    at: cleanAt(held.at) || "",
  };
}

/** PUT /console/studio/folders, from the Mac. */
export async function putFolders(env, said) {
  if (!isObject(said)) return { status: 400, body: { problem: "Folders are an object." } };
  const out = { drives: null, projects: [] };
  if (said.drives !== undefined) {
    if (!isObject(said.drives)) return { status: 400, body: { problem: "drives is an object, by name." } };
    const drives = {};
    for (const [name, one] of Object.entries(said.drives)) {
      if (!isObject(one)) continue;
      drives[String(name).toLowerCase()] = { folders: cleanRows(one.folders), at: cleanAt(one.at) };
    }
    await env.BUCKET.put(DRIVES_KEY, JSON.stringify({ drives, at: new Date().toISOString() }), {
      httpMetadata: { contentType: "application/json" },
    });
    out.drives = Object.keys(drives).length;
  }
  if (said.projects !== undefined) {
    if (!isObject(said.projects)) return { status: 400, body: { problem: "projects is an object, by page." } };
    for (const [page, one] of Object.entries(said.projects)) {
      if (!PAGE.test(page) || !isObject(one)) continue;
      const body = {
        page, name: String(one.name || ""), path: String(one.path || ""),
        tree: Array.isArray(one.tree) ? one.tree : [], at: cleanAt(one.at),
        sent: new Date().toISOString(),
      };
      await env.BUCKET.put(projectKey(page), JSON.stringify(body), { httpMetadata: { contentType: "application/json" } });
      out.projects.push(page);
    }
  }
  return { status: 200, body: out };
}

/** GET /console/studio/folders — what is held, without the lists. */
export async function foldersHeld(env) {
  const held = await readJson(env, DRIVES_KEY);
  const drives = {};
  for (const [name, one] of Object.entries((held && held.drives) || {})) {
    drives[name] = { folders: cleanRows(one && one.folders).length, at: cleanAt(one && one.at) };
  }
  const projects = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: "r/", cursor, limit: 1000 });
    for (const o of page.objects) {
      if (!o.key.endsWith("/folders.json")) continue;
      const one = await readJson(env, o.key);
      if (isObject(one)) projects.push({ page: one.page, name: one.name, path: one.path, top: (one.tree || []).length, at: one.at });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return { drives, sent: (held && held.at) || null, projects };
}

export { MAX_BODY };
