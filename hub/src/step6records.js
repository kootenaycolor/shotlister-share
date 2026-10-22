/**
 * **Stage 5 step 6, group "records": records and templates, on the server.**
 *
 * The Mac's Settings › Record, Settings › Templates, the icon picker, the
 * crew sheets' choices, a spec sheet's pills, a pasted link's name and the
 * Notion link's status line, answered here once the group's switch is on
 * (`s/step6-records.json`, door `/console/studio/step6records`). Off, none
 * is listed and the Mac does each exactly as before. The rules are the
 * Mac's, ported in `step6recordsrules.js`; this file reads and writes.
 *
 * **The server is the master** of both kinds of template:
 * - the record standards (`s/record-templates.json`), which the Notion link,
 *   Customize Record and the Studio modes already read: `set_record_template`
 *   writes them here (compare-and-set), and says each project's `hidden` line
 *   again where the Type's standard moved (`record.patch_readout`, as the
 *   Mac's `_readout_later` does). The Mac keeps a copy (`saved` in each
 *   answer) for its own screens and New Project offline;
 * - the folder template (`s/folder-template.json`, foldertemplate.js), which
 *   it already was: `save_drive_template` now writes it from here, and
 *   `update_filing_rules` rewrites `.filing-rules.md` on the Drive — the
 *   spec GD Filer and every rule reads — through the Drive's API (only that
 *   one file, only its words; a copy of the words before is kept in the
 *   bucket, and Drive keeps its own versions).
 *
 * **What stays the Mac's:** `save_media_template` (the media drives are the
 * Mac's); `slug_preview` (pure, typed on every key; the server's own slugify
 * is checked against it instead); anything the server can't do right now —
 * no Drive sign-in for the filing rules, an icon library still filling —
 * is handed back (`null`), and the Mac does it as before.
 *
 * Rule: NO static import of cloud.js / studio.js here (they import step6.js,
 * which imports this file): `await import()` inside functions.
 */

import * as R from "./step6recordsrules.js";

/** The switch: `s/step6-records.json` {on, at, by}; door at /console/studio/step6records. */
export const SWITCH = "step6records";

/** Reads answered on the spot (`POST /console/studio/now`). */
export const NOW = new Set([
  "record_templates", "templates_read", "templates_notion", "template_edit",
  "icon_library", "icon_svg", "crew_choices", "spec_options", "notion_link_status",
]);
/** Every ask this group answers (listed to the Mac and phone only while the switch is on). */
export const METHODS = new Set([...NOW, "set_record_template", "save_drive_template", "update_filing_rules", "rename_custom_link"]);
/** Asks too slow for the 20 s reply: kept working by the server (later.js). */
export const LATER_WRITES = new Set([]);
export const LATER_READS = new Set([]);

export const STANDARDS_KEY = "s/record-templates.json";
const PROJECTS = "feedface-0000-4000-8000-000000000001";
const NO_ROW = "This project has no Notion row.";

/** `.filing-rules.md` on the Drive: in the cinematography folder (the
 * parent of the drive folders' `projects` root; this id when unset). */
export const FILING_NAME = ".filing-rules.md";
export const CINE_FOLDER = "YOUR_CINEMATOGRAPHY_FOLDER_ID";
/** The Mac's path to it (the same on each of his Macs): the screen's Open. */
export const FILING_PATH = "/Users/YOUR_USER/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/cinematography/.filing-rules.md";
const FILING_BEFORE = "s/filing-rules-before/";

const ICON_LIBRARY_KEY = "s/icon-library.json";
const ICON_KEY = (name, color) => `s/notion-icons/${String(name).replace(/[^\p{L}\p{N}-]/gu, "_")}_${String(color).replace(/[^\p{L}\p{N}-]/gu, "_")}.svg`;
/** Icons fetched from notion.so per ask while the library fills (a Worker's
 * subrequests are counted); a library short of some is the Mac's to answer. */
export const ICON_BATCH = 40;
/** An icon notion.so did not give is asked again after this. */
const ICON_RETRY_MS = 7 * 24 * 3600 * 1000;

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

async function notion(env) {
  const { cloudReady, notionOf } = await import("./cloud.js");
  return cloudReady(env) ? notionOf(env) : null;
}

// ── the record standards ─────────────────────────────────────────────────────

/** His saved standards as kept, untidied (`settings.json` record_templates). */
export async function standardsOf(env) {
  const got = await env.BUCKET.get(STANDARDS_KEY);
  if (!got) return { saved: {}, etag: null };
  let saved = {};
  try { saved = await got.json(); } catch { saved = {}; }
  return { saved: isObject(saved) ? saved : {}, etag: got.etag };
}

/** Notion's Types (notionsync.choices()["type"]); [] when Notion can't say. */
async function notionTypes(env) {
  try {
    const n = await notion(env);
    if (!n) return [];
    const ds = await n.get(`data_sources/${PROJECTS}`);
    return ((((ds.properties || {}).Type || {}).select || {}).options || []).map((o) => o.name || "");
  } catch {
    return [];
  }
}

/** backend.record_templates, plus `saved` (his standards as kept: the Mac's copy). */
export async function recordTemplates(env, deps = {}) {
  const { saved } = await standardsOf(env);
  const types = deps.types ? await deps.types() : await notionTypes(env);
  return { ...R.recordTemplatesAnswer(saved, types), saved };
}

/** Every Projects row from Notion, by bare page id. */
async function projectRows(n) {
  const out = new Map();
  let cursor;
  do {
    const got = await n.post(`data_sources/${PROJECTS}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    for (const p of got.results || []) out.set(String(p.id).replace(/-/g, "").toLowerCase(), p);
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/** The projects of one Type, as the Mac's list types them (Notion's Type,
 * the record's `type` fact laid over): [{page, name, type}]. */
async function projectsOfType(env, n, ptype) {
  const { projectType } = await import("./cloudlayout.js");
  const { plainTitle } = await import("./cloud.js");
  const want = R.typeKey(ptype);
  const out = [];
  for (const [page, row] of await projectRows(n)) {
    const rec = await readJson(env, `r/${page}/record.json`);
    const facts = (rec && isObject(rec.facts) && rec.facts) || {};
    const t = projectType(row, facts);
    if (R.typeKey(t) === want) out.push({ page, name: plainTitle(row.properties || {}), type: t, record: Boolean(rec) });
  }
  return out;
}

/**
 * backend.set_record_template(ptype, template=None): one Type's standard
 * written here (compare-and-set on the whole object), then each project of
 * that Type says its `hidden` line again. Answers record_templates' answer
 * with `projects` (how many follow), as the Mac does.
 */
export async function setRecordTemplate(env, args, deps = {}) {
  const [ptype, template = null] = args;
  for (let i = 0; i < 3; i++) {
    const { saved, etag } = await standardsOf(env);
    const next = R.standardsAfter(saved, ptype, template);
    if (next.why) return { ok: false, why: next.why };
    const put = await env.BUCKET.put(STANDARDS_KEY, JSON.stringify(next.saved), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: etag ? { etagMatches: etag } : { etagDoesNotMatch: "*" },
    });
    if (!put) continue;
    try { (await import("./studiomodes.js")).forgetStandards(); } catch { /* read again in 5 s anyway */ }
    let projects = [];
    try {
      const n = deps.notion !== undefined ? deps.notion : await notion(env);
      if (n) projects = await projectsOfType(env, n, next.ptype);
    } catch (e) {
      console.error("record standards: projects not read:", String((e && e.message) || e));
    }
    const { patchHidden, tidyTemplates } = await import("./cloudlayout.js");
    const tidy = tidyTemplates(next.saved);
    for (const p of projects) {
      if (!p.record) continue;
      try { await patchHidden(env, p.page, p.type, tidy); } catch (e) {
        console.error(`record standards: ${p.name}: hidden line not written:`, String((e && e.message) || e));
      }
    }
    return { ...(await recordTemplates(env, deps)), projects: projects.length };
  }
  return { ok: false, why: "The standards kept changing. Try again." };
}

// ── the folder template and the filing rules ────────────────────────────────

/** The Drive for the filing rules: `{api, secret, write}` or null. */
async function filingDrive(env, { write = false } = {}) {
  const { driveApi } = await import("./drivewrite.js");
  const api = driveApi(env, { write: false });
  if (!api) return null;
  if (write && api.secret !== "GDRIVE_WRITE") return null;
  return api;
}

/** The cinematography folder: the parent of the `projects` root, else ours. */
async function cineFolder(env, api) {
  try {
    const { settingsOf } = await import("./drivefolders.js");
    const roots = (await settingsOf(env)).roots || {};
    if (roots.projects) {
      const got = await api.get(roots.projects);
      if (got && got.parents && got.parents[0]) return got.parents[0];
    }
  } catch { /* ours */ }
  return CINE_FOLDER;
}

/**
 * `.filing-rules.md` as the Mac reads it: `{id, mime, text}`; `text: null`
 * when it is not there, `false` when it could not be read. Null when the
 * server has no Drive sign-in at all.
 */
export async function readFiling(env, deps = {}) {
  if (deps.readFiling) return deps.readFiling();
  const api = await filingDrive(env);
  if (!api) return null;
  try {
    const kids = await api.list(await cineFolder(env, api));
    const hit = kids.find((k) => k.name === FILING_NAME && !k.folder && !k.shortcut);
    if (!hit) return { id: "", mime: "", text: null };
    const { accessToken, filesUrl } = await import("./drivewrite.js");
    const access = await accessToken(env, api.secret);
    const got = await fetch(`${filesUrl(env)}/${hit.id}?alt=media&supportsAllDrives=true`, { headers: { authorization: `Bearer ${access}` } });
    if (!got.ok) return { id: hit.id, mime: hit.mime, text: false };
    const bytes = new Uint8Array(await got.arrayBuffer());
    let text;
    try { text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); } catch { return { id: hit.id, mime: hit.mime, text: false }; }
    return { id: hit.id, mime: hit.mime, text: R.universal(text) };
  } catch (e) {
    console.error("filing rules: not read:", String((e && e.message) || e));
    return { id: "", mime: "", text: false };
  }
}

/** The new words of `.filing-rules.md`, its words before kept in the bucket first. */
async function writeFiling(env, file, text, deps = {}) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  await env.BUCKET.put(`${FILING_BEFORE}${stamp}.md`, file.text, { httpMetadata: { contentType: "text/markdown; charset=utf-8" } });
  if (deps.writeFiling) return deps.writeFiling(file, text);
  const api = await filingDrive(env, { write: true });
  if (!api) throw new Error("the server has no Google sign-in that can write");
  const { accessToken, uploadUrl } = await import("./drivewrite.js");
  const access = await accessToken(env, "GDRIVE_WRITE");
  const got = await fetch(`${uploadUrl(env)}/${file.id}?uploadType=media&supportsAllDrives=true&fields=id`, {
    method: "PATCH",
    headers: { authorization: `Bearer ${access}`, "content-type": `${file.mime || "text/markdown"}; charset=UTF-8` },
    body: text,
  });
  if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
}

const filingUrl = (id) => (id ? `https://drive.google.com/file/d/${id}/view` : "");

/** backend.templates_read — the trees (the master here), and whether the
 * filing rules draw them. Null (the Mac's) when the server can't read the Drive. */
export async function templatesRead(env, deps = {}) {
  const { templateOf } = await import("./foldertemplate.js");
  const t = await templateOf(env);
  const file = await readFiling(env, deps);
  // no sign-in, or the doc not found through the Drive's API (a dot-file the
  // Drive app may not have sent up): the Mac reads it on its own Drive
  if (file === null || file.text === null) return null;
  const trees = { drive: t.drive, media: t.media };
  return { ok: true, drive: [...t.drive], media: [...t.media],
    filing: { ...R.filingState(trees, file.text, FILING_PATH), ...(file.id ? { url: filingUrl(file.id) } : {}) },
    v: t.v, at: t.at, shoot: t.shoot };
}

/**
 * backend.save_drive_template(structure, base=None): templates.save_tree
 * then foldertemplate.save — validated, nothing written when the master no
 * longer says `base` or already says it — then templates_read.
 */
export async function saveDriveTemplate(env, args, deps = {}) {
  const [structure, base = null] = args;
  // the answer says the filing rules' state: no Drive to read them, the Mac's
  if (!deps.readFiling && !(await filingDrive(env))) return null;
  let tree;
  try { tree = R.validate(structure); } catch (e) {
    if (e instanceof R.Bad) return { ok: false, why: e.message };
    throw e;
  }
  const ft = await import("./foldertemplate.js");
  const now = await ft.templateOf(env);
  const same = (a, b) => Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => x === b[i]);
  if (base !== null && base !== undefined && !same(now.drive, base)) return { ok: false, why: "Changed elsewhere. Reopen Settings." };
  if (!same(now.drive, tree)) {
    const got = await ft.changeTemplate(env, { drive: tree, base: now.v, by: "server" });
    if (got.moved) return { ok: false, why: "Changed elsewhere. Reopen Settings." };
    if (got.problem) return { ok: false, why: got.problem };
  }
  return await templatesRead(env, deps);
}

/**
 * backend.update_filing_rules(): the doc's template blocks that no longer
 * match redrawn (everything else byte for byte), written to the Drive.
 * Null (the Mac's) when the server can't write the Drive, or can't find the doc there.
 */
export async function updateFilingRules(env, deps = {}) {
  if (!deps.writeFiling && !(await filingDrive(env, { write: true }))) return null;
  const { templateOf } = await import("./foldertemplate.js");
  const t = await templateOf(env);
  const trees = { drive: t.drive, media: t.media };
  const file = await readFiling(env, deps);
  if (file === null || file.text === null) return null;
  let next;
  try { next = R.rewriteFiling(trees, file.text); } catch (e) {
    if (e instanceof R.Bad) return { ok: false, why: e.message };
    throw e;
  }
  if (next.text !== file.text) {
    try { await writeFiling(env, file, next.text, deps); } catch (e) {
      console.error("filing rules: not written:", String((e && e.message) || e));
      return { ok: false, why: "Couldn't update the filing rules." };
    }
  }
  return { ok: true, filing: { ...R.filingState(trees, next.text, FILING_PATH), ...(file.id ? { url: filingUrl(file.id) } : {}) } };
}

/** backend.templates_notion — the Projects data source's default template. */
export async function templatesNotion(env) {
  const { IDS, NEW_VERSION } = await import("./notionlink.js");
  let got;
  try {
    const n = await notion(env);
    if (!n) return { ok: false, why: "Can't reach Notion" };
    void NEW_VERSION;      // notionOf speaks it already
    got = await n.get(`data_sources/${IDS.projects[1]}/templates`);
  } catch {
    return { ok: false, why: "Can't reach Notion" };
  }
  const found = ((got && got.templates) || []).filter((t) => t && t.is_default);
  if (!found.length) return { ok: false, why: "No default template" };
  const t = found[0];
  return { ok: true, name: t.name || "Untitled", id: t.id || "", url: `https://www.notion.so/${String(t.id || "").replace(/-/g, "")}` };
}

// ── icons ────────────────────────────────────────────────────────────────────

async function fetchIcon(name, color, deps) {
  if (deps.iconSvg) return deps.iconSvg(name, color);
  const { iconSvg } = await import("./cloudfacts.js");
  return iconSvg(name, color);
}

/** backend.icon_svg — one built-in icon in one colour, kept in the bucket once had. */
export async function iconSvgAsk(env, args, deps = {}) {
  const [name, color] = args;
  if (!R.iconAddress(name, color)) return { ok: false, why: "That isn't one of Notion's icons." };
  const key = ICON_KEY(name, color);
  const kept = await env.BUCKET.get(key);
  let svg = kept ? await kept.text() : null;
  if (!svg) {
    svg = await fetchIcon(name, color, deps);
    if (svg) await env.BUCKET.put(key, svg, { httpMetadata: { contentType: "image/svg+xml" } });
  }
  return { ok: Boolean(svg), svg: svg || "", why: svg ? "" : "Couldn't load the icon." };
}

/**
 * backend.icon_library — every built-in icon the picker offers, grey, and
 * the colours. Kept whole in the bucket; while it fills (at most
 * `ICON_BATCH` new icons an ask), the Mac answers (null).
 */
export async function iconLibrary(env, deps = {}) {
  const { ICON_NAMES } = await import("./recordtools.js");
  const names = [...ICON_NAMES];
  const kept = (await readJson(env, ICON_LIBRARY_KEY)) || {};
  const icons = isObject(kept.icons) ? { ...kept.icons } : {};
  const tried = isObject(kept.tried) ? { ...kept.tried } : {};
  const now = deps.now ? deps.now() : Date.now();
  const want = names.filter((n) => !icons[n] && !(tried[n] && now - Date.parse(tried[n]) < ICON_RETRY_MS));
  if (want.length) {
    const batch = want.slice(0, ICON_BATCH);
    const got = await Promise.all(batch.map((n) => fetchIcon(n, "gray", deps)));
    batch.forEach((n, i) => {
      if (got[i]) { icons[n] = got[i]; delete tried[n]; } else tried[n] = new Date(now).toISOString();
    });
    await env.BUCKET.put(ICON_LIBRARY_KEY, JSON.stringify({ icons, tried, at: new Date(now).toISOString() }), { httpMetadata: { contentType: "application/json" } });
    if (want.length > batch.length) return null;
  }
  return { ok: true, colors: [...R.ICON_COLORS], icons: names.filter((n) => icons[n]).map((n) => ({ name: n, svg: icons[n] })) };
}

// ── crew, spec sheets, a link's name, the Notion link ────────────────────────

/** backend.crew_choices */
export async function crewChoices(env) {
  const n = await notion(env);
  if (!n) return null;
  const { crewOptions, allCrew } = await import("./cloud.js");
  let opts, rows;
  try {
    opts = await crewOptions(n);
    rows = await allCrew(n);
  } catch (e) {
    const { Handoff } = await import("./cloud.js");
    if (e instanceof Handoff) throw e;
    return { ok: false, why: String((e && e.message) || e) };
  }
  return R.crewChoicesAnswer(opts, rows);
}

/** backend.spec_options — the pills (specpills.js keeps them ten minutes). */
export async function specOptions(env) {
  const { specPills } = await import("./specpills.js");
  return R.specAnswer(await specPills(env));
}

/** backend.rename_custom_link(name, link_id, title) — record.change_links(rename=…). */
export async function renameCustomLink(env, args, deps = null) {
  const [name, linkId, title] = args;
  const n = await notion(env);
  if (!n) return null;
  const { projectRow, bareId } = await import("./cloud.js");
  const row = typeof name === "string" && name ? await projectRow(n, name) : null;
  if (!row) return { ok: false, why: NO_ROW };
  const page = bareId(row.id);
  const d = deps || (await import("./cloudfacts.js")).liveDeps(env);
  const { customLinks, BY } = await import("./cloudfacts.js");
  for (let i = 0; i < 3; i++) {
    const now = await d.readFacts(page);
    if (now && (now.trouble || now.offline)) return { ok: false, why: now.offline ? "Offline. Try again when connected." : now.trouble };
    const [value, base, why] = R.renamePlan(now, linkId, title);
    if (why) return { ok: false, why };
    const got = await d.writeFacts(page, { links: { value, base } }, BY);
    if (got.status === 409 && "conflicts" in got) continue;
    if (got.status !== 200) return { ok: false, why: got.problem || `the hub answered ${got.status}` };
    return { ok: true, links: customLinks(got.facts || {}) };
  }
  return { ok: false, why: "The links kept changing. Try again." };
}

/** backend.notion_link_status — the server's own last look when it keeps
 * Notion in step; the Mac's while the Mac does. */
export async function notionLinkStatus(env) {
  const { syncOwner } = await import("./studio.js");
  if ((await syncOwner(env)).owner !== "hub") return null;
  return R.linkStatusAnswer(await readJson(env, "s/sync-last.json"));
}

// ── the asks ─────────────────────────────────────────────────────────────────

/** `async (list, env) => result`; null hands the ask to the Mac. */
export const ASKS = {
  record_templates: (list, env) => recordTemplates(env),
  set_record_template: (list, env) => setRecordTemplate(env, list),
  templates_read: (list, env) => templatesRead(env),
  templates_notion: (list, env) => templatesNotion(env),
  template_edit: async (list) => R.templateEdit(list),
  save_drive_template: (list, env) => saveDriveTemplate(env, list),
  update_filing_rules: (list, env) => updateFilingRules(env),
  icon_library: (list, env) => iconLibrary(env),
  icon_svg: (list, env) => iconSvgAsk(env, list),
  crew_choices: (list, env) => crewChoices(env),
  spec_options: (list, env) => specOptions(env),
  rename_custom_link: (list, env) => renameCustomLink(env, list),
  notion_link_status: (list, env) => notionLinkStatus(env),
};

// ── the dry look ─────────────────────────────────────────────────────────────

/**
 * What the group would answer and write now, writing nothing: the record
 * standards as kept and as Settings would show them, the folder template's
 * version, the filing rules' state and the lines Update would write, the
 * icon library's fill, who answers the Notion link's status.
 */
export async function recordsLook(env, deps = {}) {
  const { groupOn } = await import("./step6.js");
  const self = await import("./step6records.js");
  const out = { at: new Date().toISOString(), on: await groupOn(env, self), methods: [...METHODS] };
  const { saved } = await standardsOf(env);
  out.standards = { saved, types: deps.types ? await deps.types() : await notionTypes(env) };
  out.standards.shown = R.templatesView(saved, out.standards.types);
  const { templateOf } = await import("./foldertemplate.js");
  const t = await templateOf(env);
  out.folder_template = { v: t.v, at: t.at, by: t.by, drive: t.drive.length, media: t.media.length };
  const { driveApi } = await import("./drivewrite.js");
  const api = driveApi(env, { write: false });
  out.drive = { read: Boolean(api), write: Boolean(api && api.secret === "GDRIVE_WRITE") };
  const file = await readFiling(env, deps);
  if (file === null) out.filing = { trouble: "no Drive sign-in: the Mac answers templates_read and update_filing_rules" };
  else {
    const trees = { drive: t.drive, media: t.media };
    out.filing = { id: file.id, ...R.filingState(trees, file.text, FILING_PATH) };
    if (typeof file.text === "string") {
      try {
        const next = R.rewriteFiling(trees, file.text);
        out.filing.update_would = next.text === file.text ? "write nothing" : `redraw ${next.redone.join(" and ")}`;
        if (next.text !== file.text) out.filing.diff = lineDiff(file.text, next.text);
      } catch (e) {
        out.filing.update_would = `refuse: ${e.message}`;
      }
    }
  }
  const lib = (await readJson(env, ICON_LIBRARY_KEY)) || {};
  const { ICON_NAMES } = await import("./recordtools.js");
  out.icons = { library: Object.keys(lib.icons || {}).length, of: ICON_NAMES.size, unanswered: Object.keys(lib.tried || {}) };
  const { syncOwner } = await import("./studio.js");
  out.notion_link = { owner: (await syncOwner(env)).owner };
  return out;
}

/** The lines that differ, as `- old` / `+ new` around the first and last change. */
export function lineDiff(a, b) {
  const x = a.split("\n"), y = b.split("\n");
  let i = 0;
  while (i < x.length && i < y.length && x[i] === y[i]) i++;
  let j = 0;
  while (j < x.length - i && j < y.length - i && x[x.length - 1 - j] === y[y.length - 1 - j]) j++;
  return { from_line: i + 1, removed: x.slice(i, x.length - j), added: y.slice(i, y.length - j) };
}

/** The group's own doors beyond the switch: GET /console/studio/step6records/look. */
export async function door(env, rest, method, readBody, ctx, url) {
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "GET") return Response.json({ problem: "Wrong method." }, { status: 405 });
    return Response.json(await recordsLook(env));
  }
  return null;
}
