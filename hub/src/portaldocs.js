/**
 * **Drive files on the portal's Documents page** (his decision, 2026-10-17,
 * "Option A"): in Projects Console every file in the project's Drive folder has
 * a Show on Portal switch. Nothing goes up unless he switches it on; the file
 * stays in Drive and the portal opens it from there.
 *
 * The choice is the record's `portal_docs` fact — a list of the files, each
 * `{id, name, mime, modified, size, path}` as Drive said them when he chose it
 * (and again whenever the console reads the folder). `layRecordDocs` puts them
 * on the card as documents with `source: "drive"`; everything else on the
 * Documents page (files held here, links) is left as it is.
 *
 * The console (Mac and iPhone) reads and writes through one door:
 *   GET /console/record/<page>/portaldocs    → {folder, files, chosen}
 *   PUT /console/record/<page>/portaldocs    {id, on, by} → {chosen}
 *
 * Viewers open a chosen file through `/<film>/drive/<id>`, which streams it
 * from Drive only if it is on the card and the viewer may see it — so crew
 * need no Drive access, and a file switched off stops answering at once.
 */

import { scriptDrive, projectFolderOf } from "./scriptdrive.js";
import { accessToken, filesUrl } from "./drivewrite.js";

export const FACT = "portal_docs";
const ID = /^[A-Za-z0-9_-]{10,160}$/;
const MAX_CHOSEN = 60;
const MAX_FILES = 1500;
const MAX_FOLDERS = 400;
const FOLDER = "application/vnd.google-apps.folder";
const G = "application/vnd.google-apps.";

/** The portal's groups, in the order the page shows them. */
export const GROUPS = ["Schedule & Call Sheets", "Script", "Creative", "Other"];

/** Folders whose insides are working material: hidden unless Show All Files. */
const WORKING_DIR = /^(z-|zz-|\.|_)|^(cache|cacheclip|proxy|proxies|optimized media|render ?cache|\.gallery)$/i;
/** Folders never walked at all (huge, and nothing in them is a document). */
const SKIP_DIR = /^(cacheclip|render ?cache|optimized media|\.gallery|\.trash)$/i;

const EXT = (name) => { const m = /\.([A-Za-z0-9]{1,6})$/.exec(String(name || "")); return m ? m[1].toLowerCase() : ""; };
const SHAREABLE_EXT = new Set(["pdf", "jpg", "jpeg", "png", "webp", "gif", "heic", "tif", "tiff",
  "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "rtf", "csv",
  "mov", "mp4", "m4v"]);
const NATIVE = { document: "Doc", spreadsheet: "Sheet", presentation: "Slides", drawing: "Drawing" };

/** The short type word a row shows: PDF, JPG, Doc, Sheet… */
export function typeOf(f) {
  const mime = String((f && f.mime) || "");
  if (mime.startsWith(G)) return NATIVE[mime.slice(G.length)] || "";
  const ext = EXT(f && f.name);
  return ext ? ext.toUpperCase() : "";
}

/** A type a collaborator can open: PDFs, pictures, docs and sheets, video. */
export function shareable(f) {
  const mime = String((f && f.mime) || "");
  if (mime.startsWith(G)) return Boolean(NATIVE[mime.slice(G.length)]);
  if (/^(image|video)\//.test(mime) || mime === "application/pdf") return true;
  return SHAREABLE_EXT.has(EXT(f && f.name));
}

/** In a working folder (z-archive, z-source, caches…): hidden by default. */
export function working(path) {
  return String(path || "").split("/").filter(Boolean).some((part) => WORKING_DIR.test(part));
}

const SCHEDULE = /call ?sheet|callsheet|schedule|stripboard|one[- ]?liner|day out of days|\bdood\b|shot ?list|movement|itinerary|crew ?list|contact ?sheet/i;
const SCRIPT = /script|screenplay|\bdraft\b|\bsides\b|teleplay/i;
const CREATIVE = /deck|look ?book|lookbook|treatment|bible|mood|storyboard|board|reference|lighting|floor ?plan|overhead|concept|pitch|spec ?sheet/i;

/** Which group a file is shown under on the portal. */
export function groupOf(f) {
  const name = String((f && f.name) || ""), path = String((f && f.path) || "");
  const at = `${path}/${name}`;
  if (SCHEDULE.test(name)) return "Schedule & Call Sheets";
  if (SCRIPT.test(name) || /(^|\/)script(\/|$)/i.test(path)) return "Script";
  if (CREATIVE.test(at) || /^1-creative/i.test(path)) return "Creative";
  return "Other";
}

/** A likely portal file: call sheets, the current script, decks, schedules, spec sheets. */
export function suggested(f) {
  if (!shareable(f) || working(f.path)) return false;
  const name = String(f.name || ""), path = String(f.path || "");
  if (/call ?sheet|callsheet|schedule|look ?book|lookbook|\bdeck\b|treatment|spec ?sheet|storyboard|bible/i.test(name)) return true;
  if (/(^|\/)current-draft(\/|$)/i.test(path)) return true;
  if (/(^|\/)decks\//i.test(path) && /\.pdf$/i.test(name)) return true;
  return false;
}

/** The name the portal shows: Drive's, without a plain file extension. */
export function shownName(name) {
  return String(name || "").replace(/\.(pdf|docx?|xlsx?|pptx?|key|pages|numbers|jpe?g|png|webp|gif|heic|tiff?|txt|rtf|csv|mov|mp4|m4v)$/i, "").trim() || String(name || "");
}

/** One chosen file, tidied: what the fact keeps. */
export function tidyChosen(raw) {
  if (!raw || typeof raw !== "object" || !ID.test(String(raw.id || ""))) return null;
  const words = (v, n) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, n);
  return {
    id: String(raw.id),
    name: words(raw.name, 200) || "Untitled",
    mime: words(raw.mime, 120),
    modified: /^\d{4}-\d\d-\d\dT/.test(String(raw.modified || "")) ? String(raw.modified).slice(0, 24) : "",
    size: Math.max(0, Math.min(Math.round(Number(raw.size) || 0), 1e12)),
    path: words(raw.path, 300),
  };
}

export function chosenOf(facts) {
  const v = ((facts || {})[FACT] || {}).value;
  return (Array.isArray(v) ? v : []).map(tidyChosen).filter(Boolean).slice(0, MAX_CHOSEN);
}

/**
 * Lay the chosen Drive files on a card as documents. Documents from anywhere
 * else are kept as they are. A record with no `portal_docs` fact leaves the
 * card alone. Returns whether anything changed.
 */
export function layRecordDocs(card, facts) {
  if (!facts || !facts[FACT]) return false;
  const chosen = chosenOf(facts);
  const others = (card.documents || []).filter((d) => d && d.source !== "drive");
  const taken = new Set(others.map((d) => String(d.name || "").toLowerCase()));
  const was = new Map((card.documents || []).filter((d) => d && d.source === "drive").map((d) => [d.drive, d]));
  const drive = chosen.map((one) => {
    const base = shownName(one.name).slice(0, 140);
    let name = base;
    for (let n = 2; taken.has(name.toLowerCase()); n++) name = `${base} (${n})`.slice(0, 140);
    taken.add(name.toLowerCase());
    const before = was.get(one.id) || {};
    return {
      name, kind: "document", file: "", url: `https://drive.google.com/file/d/${one.id}/view`,
      bytes: one.size, note: "", was: "", source: "drive", shoots: Array.isArray(before.shoots) ? before.shoots : [],
      drive: one.id, mime: one.mime, modified: one.modified, type: typeOf(one), group: groupOf(one),
    };
  });
  const next = [...drive, ...others];
  if (JSON.stringify(next) === JSON.stringify(card.documents || [])) return false;
  card.documents = next;
  return true;
}

/**
 * Every file under the project folder, with where it is. Walked breadth
 * first, a few folders at a time; caches and the like are not walked.
 */
export async function walkFolder(api, root) {
  const files = [];
  let queue = [{ id: root, path: "" }];
  let folders = 0;
  while (queue.length && folders < MAX_FOLDERS && files.length < MAX_FILES) {
    const batch = queue.splice(0, 8);
    folders += batch.length;
    const lists = await Promise.all(batch.map(async (one) => ({ one, kids: await api.list(one.id) })));
    for (const { one, kids } of lists) {
      for (const k of kids || []) {
        if (k.mime === FOLDER || k.folder) {
          if (!SKIP_DIR.test(k.name)) queue.push({ id: k.id, path: one.path ? `${one.path}/${k.name}` : k.name });
          continue;
        }
        if (/^\./.test(k.name) || /^application\/vnd\.google-apps\.(shortcut|folder)$/.test(k.mime)) continue;
        files.push({ id: k.id, name: k.name, mime: k.mime, modified: k.modified || "", size: k.size || 0, path: one.path });
      }
    }
  }
  return { files, partial: queue.length > 0 };
}

/** The listing the picker draws: every file, with its flags, newest first. */
export function describe(files, chosen) {
  const on = new Set(chosen.map((c) => c.id));
  return files.map((f) => ({
    ...f, type: typeOf(f), top: String(f.path || "").split("/")[0] || "",
    shareable: shareable(f), working: working(f.path), suggested: suggested(f), group: groupOf(f), on: on.has(f.id),
  })).sort((a, b) => String(b.modified).localeCompare(String(a.modified)));
}

/** Is this file inside the project folder? Walks its parents, a few hops. */
async function inside(api, file, root) {
  let parents = (file && file.parents) || [];
  for (let hop = 0; hop < 10 && parents.length; hop++) {
    if (parents.includes(root)) return true;
    const up = await api.get(parents[0]);
    if (!up) return false;
    parents = up.parents || [];
  }
  return false;
}

/** The folder's path from the root, for a file found by id. */
async function pathOf(api, file, root) {
  const names = [];
  let parents = (file && file.parents) || [];
  for (let hop = 0; hop < 10 && parents.length && !parents.includes(root); hop++) {
    const up = await api.get(parents[0]);
    if (!up) break;
    names.unshift(up.name);
    parents = up.parents || [];
  }
  return names.join("/");
}

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});
const problem = (status, said) => json({ problem: said }, status);

/**
 * The console's door. `deps` lets the checks hand in a fake Drive and the
 * record's helpers.
 */
export async function portalDocsDoor(env, page, method, sent, deps = {}) {
  const { recordOf, writeFacts } = deps;
  const record = await recordOf(env, page);
  if (!record) return problem(404, "No record for that project yet.");
  const root = projectFolderOf(record);
  if (!root) return problem(409, "This project has no Drive folder.");
  const api = deps.api !== undefined ? deps.api : scriptDrive(env);
  if (!api) return problem(503, "The server has no Drive sign-in.");
  const facts = record.facts || {};
  const chosen = chosenOf(facts);
  const base = (facts[FACT] && facts[FACT].v) || 0;

  if (method === "GET") {
    let walked;
    try { walked = await walkFolder(api, root); } catch (e) { return problem(502, `Couldn't read the Drive folder (${String((e && e.message) || e).slice(0, 120)})`); }
    // Freshen what was chosen: a renamed or updated file keeps its id, so the
    // portal follows its new name and date. A file gone from the folder stays
    // chosen (it may be moved back); the page still opens it while Drive has it.
    const now = new Map(walked.files.map((f) => [f.id, f]));
    let moved = false;
    const fresh = chosen.map((c) => {
      const f = now.get(c.id);
      if (!f) return c;
      const next = tidyChosen({ ...c, name: f.name, mime: f.mime, modified: f.modified, size: f.size, path: f.path });
      if (JSON.stringify(next) !== JSON.stringify(c)) moved = true;
      return next;
    });
    let kept = fresh;
    if (moved) {
      const got = await writeFacts(env, page, { [FACT]: { value: fresh, base } }, "server");
      if (got.status !== 200) kept = chosen;
    }
    return json({
      folder: { id: root, url: `https://drive.google.com/drive/folders/${root}` },
      partial: walked.partial, files: describe(walked.files, kept), chosen: kept, groups: GROUPS,
    });
  }

  if (method !== "PUT") return problem(405, "Wrong method.");
  let asked;
  try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
  const id = String((asked && asked.id) || "");
  if (!ID.test(id)) return problem(400, "Say which file.");
  const on = Boolean(asked.on);
  let next;
  if (on) {
    if (chosen.some((c) => c.id === id)) return json({ chosen });
    if (chosen.length >= MAX_CHOSEN) return problem(400, `At most ${MAX_CHOSEN} files on the portal.`);
    let file;
    try { file = await api.get(id); } catch (e) { return problem(502, `Couldn't read the file from Drive (${String((e && e.message) || e).slice(0, 120)})`); }
    if (!file || file.folder) return problem(404, "That file isn't in Drive.");
    if (!(await inside(api, file, root))) return problem(400, "That file isn't in this project's Drive folder.");
    const path = typeof asked.path === "string" ? asked.path : await pathOf(api, file, root);
    next = [...chosen, tidyChosen({ id, name: file.name, mime: file.mime, modified: file.modified, size: file.size, path })];
  } else {
    if (!chosen.some((c) => c.id === id)) return json({ chosen });
    next = chosen.filter((c) => c.id !== id);
  }
  const got = await writeFacts(env, page, { [FACT]: { value: next, base } }, String((asked && asked.by) || "console").slice(0, 40));
  if (got.status === 409) return problem(409, "Changed somewhere else. Try again.");
  if (got.status !== 200) return problem(got.status, got.problem || "Not saved.");
  return json({ chosen: next });
}

/**
 * A chosen file's bytes, for `/<film>/drive/<id>`. A Google Doc, Sheet or
 * Slides comes out as a PDF. Inline, under the name the portal shows.
 */
export async function driveFileResponse(env, doc, request) {
  const secret = env.GDRIVE_WRITE ? "GDRIVE_WRITE" : env.GDRIVE ? "GDRIVE" : "";
  if (!secret) return new Response("No Drive sign-in on the server.", { status: 503 });
  const access = await accessToken(env, secret);
  const native = String(doc.mime || "").startsWith(G);
  const url = native
    ? `${filesUrl(env)}/${doc.drive}/export?mimeType=application%2Fpdf`
    : `${filesUrl(env)}/${doc.drive}?alt=media&supportsAllDrives=true`;
  const headers = { authorization: `Bearer ${access}` };
  const range = request.headers.get("range");
  if (range && !native) headers.range = range;
  const got = await fetch(url, { headers });
  if (!got.ok && got.status !== 206) return new Response("This file can't be opened right now.", { status: got.status === 404 ? 404 : 502 });
  const said = native ? "application/pdf" : (got.headers.get("content-type") || doc.mime || "");
  // **Only types a browser shows safely are shown inline.** Anything else (an
  // HTML or SVG file, a project file) is handed over as a download, never
  // drawn on the portal's own address.
  const safe = /^(application\/pdf|image\/(png|jpe?g|gif|webp|heic|heif|tiff)|video\/(mp4|quicktime|x-m4v)|audio\/(mpeg|mp4|x-m4a|wav)|text\/plain)\b/i.test(said);
  const type = safe ? said : "application/octet-stream";
  // The portal's name has no extension (shownName); the type it keeps does.
  const ext = native ? "pdf" : EXT(doc.name) || (/^[A-Za-z0-9]{1,5}$/.test(String(doc.type || "")) ? String(doc.type).toLowerCase() : "");
  const file = `${doc.name}${ext && !String(doc.name).toLowerCase().endsWith(`.${ext}`) ? `.${ext}` : ""}`.replace(/["\\\r\n]/g, "");
  const out = new Headers({
    "content-type": type,
    "content-disposition": `${safe ? "inline" : "attachment"}; filename="${file.replace(/[^\x20-\x7e]/g, "_")}"; filename*=UTF-8''${encodeURIComponent(file)}`,
    "cache-control": "private, max-age=300",
    "x-content-type-options": "nosniff",
  });
  // A download is sandboxed too, should a browser draw it anyway; a PDF is not
  // (Chrome will not show a PDF in a sandboxed page).
  if (!safe) out.set("content-security-policy", "sandbox");
  for (const k of ["content-length", "content-range", "accept-ranges"]) { const v = got.headers.get(k); if (v) out.set(k, v); }
  return new Response(got.body, { status: got.status, headers: out });
}
