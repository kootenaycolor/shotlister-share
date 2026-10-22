/**
 * **A full project (Tier 1) made by the server** (2026-10-13, Projects
 * Console without the Mac, stage 4 part B). The Mac's New Project —
 * `backend.new_project_options`, `backend.create_project` and
 * `engine.create_project` with everything it calls — ported rule for rule,
 * so New Project works from the phone with the Mac asleep. The ways in (the
 * asks, the switch, the look, the owed list) are `newprojectdoor.js`.
 *
 * **His decision (2026-10-13): the server does everything at once** — the
 * Google Drive folders and their `.gdrive-project` marker (drivefolders.js),
 * any new Crew rows the credits need, the Projects database's colour option,
 * the Notion row from the Type's template (with the Mac's fallback to a plain
 * row), its native icon and its `Drive Folder` link, the website link — and
 * **the Mac adds what only it can**: the media drive's folders (`volume`) and
 * the Finder sidebar entry, the next time it is awake with that drive plugged
 * in. Those are written down as an *owed* item (`s/newproject-owed.json`),
 * which the Mac reads and marks done over the console door. The Mac cannot
 * simply be asked to make the project again: its own New Project refuses a
 * project whose Drive folder is already there ("… already exists in Google
 * Drive — pick another name."), and the server has made that folder.
 *
 * **In the Mac's order, word for word.** Drive folders, then the media line,
 * then (a full project only) the credits — a typed name Crew lacks becomes a
 * Crew row first — then the colour option, then the row, then the website.
 * The answer is the Mac's lines; where the server's is different it says so
 * in as few words (the media folder and the sidebar are the Mac's later;
 * "Opened in Notion" is not said: nothing is opened on the Mac's screen).
 *
 * **Reads first.** Before anything is made the server reads the Projects
 * database (and Crew's, when a credit names someone new), so a Notion key
 * that cannot reach them hands the whole ask to the Mac with nothing made.
 * After the first write the ask can no longer go to the Mac — the Mac would
 * refuse the folder — so a later refusal is answered as a failure, saying
 * what was made, as the Mac's own New Project fails when Notion fails after
 * its folder is made.
 *
 * **Where it differs from the Mac, on purpose** (each marked `SERVER:`):
 * - the Drive folder's link is known at once (the Mac waits up to 45 s for
 *   Google to assign it), so "Drive link pending" never happens;
 * - Notion is spoken to in its newer dialect throughout (data sources), so
 *   the plain-row fallback is made under the data source, not the database;
 * - the website link is written to the new row by its id; the Mac looks the
 *   row up by name, which with two rows of one name can find the older one;
 * - the project's record is begun at once (as New Film begins one), so the
 *   Notion link carries the credits and words into it within the minute, and
 *   the Story choice is written onto it — the Mac waits up to two minutes for
 *   a record that only its own screen makes, and drops the choice after;
 * - a media drive is one the Mac has told the server about; the Mac checks
 *   it is plugged in, and refuses only after making the Drive folder.
 */

import { slugify } from "./drivefolders.js";
import { truthy, pyStrip, pySplit, casefold, cmp, iconParts, iconPayload, FACTS, resolveLayout } from "./notionlink.js";
import { LINE_FACTS } from "./credits.js";
import { Handoff, personProps, companyProps, normName, bareId } from "./cloud.js";
import { standardOf } from "./studiomodes.js";

export const SWITCH_KEY = "s/newproject.json";
export const OWED_KEY = "s/newproject-owed.json";

/** notionlink.IDS — the data sources the server speaks to. */
export const PROJECTS = "feedface-0000-4000-8000-000000000001";
export const CREW = "feedface-0000-4000-8000-000000000004";

/** backend.new_project_options' fixed lists, word for word. */
/** SERVER: Music Video (stage 5 step 5) behaves as Commercial everywhere:
 * its standard, its modes, its shoots' words, its Studio kind. */
export const TYPES = ["Narrative", "Commercial", "Music Video", "Personal"];
export const LENGTHS = ["Short", "Feature"];
/** engine.NEW_PROJECT_STATUSES: Post and Archived are reached by their rituals. */
export const STATUSES = ["Development", "Active"];
/** engine.NOTION_COLORS — the only colours a Notion choice can be. */
export const COLORS = ["gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"];

/** engine.drive_homes, the two a new project may be born in. The paths are
 * the Mac's own (its Google Drive mount); only shown, never used here. */
const MOUNT = "/Users/YOUR_USER/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/cinematography";
export const HOMES = [
  { key: "projects", label: "PROJECTS", sub: "projects/", path: `${MOUNT}/projects` },
  { key: "gigs", label: "GIGS", sub: "gigs/", path: `${MOUNT}/gigs` },
];

/** crewrows.ICON_URL — every Crew row's gray icon. */
const CREW_ICON = (glyph) => ({ type: "external", external: { url: `https://www.notion.so/icons/${glyph}_gray.svg` } });

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
/** `form.get(k, "")` as the Mac reads a string box: None and missing are "". */
const text = (v) => (v === null || v === undefined ? "" : String(v));
/** Python's `s[:n]`, by code point. */
const cut = (s, n) => Array.from(String(s)).slice(0, n).join("");

/** Notion answered with an error: its HTTP status and code ride along, so a
 * template refusal (4xx) can be told from a dropped connection. */
export class NotionSaid extends Error {
  constructor(status, code, message) {
    super(`Notion: ${code || status}${message ? ` — ${String(message).slice(0, 160)}` : ""}`);
    this.status = status;
    this.code = code;
  }
}

// ── engine.fmt_bytes ────────────────────────────────────────────────────────

/** `engine.fmt_bytes`: "123 GB", "1.2 TB". */
export function fmtBytes(n) {
  let x = Number(n) || 0;
  for (const unit of ["B", "KB", "MB", "GB"]) {
    if (x < 1000) return `${pyRound(x, 0)} ${unit}`;
    x /= 1000;
  }
  return x < 100 ? `${pyRound(x, 1)} TB` : `${pyRound(x, 0)} TB`;
}

/** Python's `f"{x:.Nf}"`. Both round the exact binary value; they differ only
 * on an exact half, which Python sends to the even neighbour — and with one
 * decimal place no exact half exists in binary, so only whole numbers need it. */
function pyRound(x, digits) {
  if (digits === 0 && x - Math.floor(x) === 0.5) {
    const floor = Math.floor(x);
    return String(floor % 2 === 0 ? floor : floor + 1);
  }
  return x.toFixed(digits);
}

// ── new_project_options ─────────────────────────────────────────────────────

/** Python's `sorted(xs, key=lambda x: x["name"].lower())`. */
const byName = (xs) => xs.map((x, i) => [x.name.toLowerCase(), i, x])
  .sort((a, b) => cmp(a[0], b[0]) || a[1] - b[1]).map((t) => t[2]);

/**
 * The drives a media folder can be asked for: the ones the Mac last told the
 * server about (its snapshot, `s/studio.json`), never one he set aside, nor a
 * backup drive (the backup copy is made from the main one). The Mac offers
 * only the drives plugged in at that moment; here every one it knows, those
 * plugged in at its last look first, in the Mac's order (by name), each
 * marked `later`: the Mac makes the folder when it next sees the drive.
 */
export function knownVolumes(studio) {
  const drives = isObject(studio) && Array.isArray(studio.drives) ? studio.drives : [];
  const out = [];
  const seen = new Set();
  const rows = drives.filter((d) => isObject(d) && !d.ignored && !d.is_backup);
  const mounted = rows.filter((d) => d.mounted === true).sort((a, b) => cmp(text(a.volume || a.name), text(b.volume || b.name)));
  const shelf = rows.filter((d) => d.mounted !== true);
  for (const d of [...mounted, ...shelf]) {
    const name = text(d.volume || d.name).trim();
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    const room = d.free === null || d.free === undefined || d.free === "" ? "" : ` · ${fmtBytes(d.free)} free`;
    out.push({ name, label: `${name}${room} · made when the Mac next sees it`, later: true,
      mounted: d.mounted === true, as_of: text(studio.at) });
  }
  return out;
}

/**
 * backend.new_project_options, from what the server holds: Crew (read now),
 * his record standards (`s/record-templates.json`, which the console sends on
 * every save), the Mac's last drive list. `films` is empty: a film to link
 * is a folder on the Mac's disk (`film_path`), which stays the Mac's.
 */
export function optionsFrom({ crew = [], templates = {}, studio = null } = {}) {
  const people = [], companies = [];
  for (const r of crew || []) {
    const one = { id: bareId(r.id || ""), name: text(r.name) };
    if (!one.name) continue;
    if (r.type === "Vendor") companies.push(one);
    else people.push({ ...one, role: text(r.role) });
  }
  const layouts = {};
  for (const t of TYPES) {
    const tpl = resolveLayout({}, t, templates).template;
    layouts[t] = { fields: [...tpl.fields], credits: [...tpl.credits] };
  }
  return {
    directors: people.filter((x) => x.role.split(", ").includes("Director/Writer")).map((x) => ({ id: x.id, name: x.name })),
    people: byName(people),
    companies: byName(companies),
    layouts,
    volumes: knownVolumes(studio),
    films: [],
    homes: HOMES.map((h) => ({ ...h })),
    types: [...TYPES],
    // SERVER: each Type's starting modes (studiomodes.js), for the sheet's
    // switches (stage 5 step 5); a Job starts with none.
    modes_standard: Object.fromEntries(TYPES.map((t) => [t, standardOf(t)])),
    lengths: [...LENGTHS],
    statuses: [...STATUSES],
    colors: [...COLORS],
    // SERVER: the Mac's `mysides` is not installed on the Studio (2026-10-13),
    // so its own answer is false too; asked for anyway, it is owed.
    finder_sidebar: false,
  };
}

// ── the form, as backend.create_project reads it ─────────────────────────────

/** backend.create_project's reading of the form, before engine.create_project. */
export function readForm(form) {
  const f = isObject(form) ? form : {};
  const credits = {};
  if (isObject(f.credits)) for (const [role, people] of Object.entries(f.credits)) credits[role] = Array.isArray(people) ? [...people] : [];
  return {
    name: pyStrip(text(f.name)),
    drive_name: pyStrip(text(f.drive_name)),
    tier1: "tier1" in f ? truthy(f.tier1) : true,
    // A Job (the sheet's Kind; an older sheet's quick job): its folder is loose.
    job: "job" in f ? truthy(f.job) : ("tier1" in f ? !truthy(f.tier1) : false),
    ptype: text(f.type), length: text(f.length),
    date_start: text(f.date_start), date_end: text(f.date_end),
    director_id: text(f.director_id), director_new: text(f.director_new),
    volume: text(f.volume), emoji: text(f.emoji), color: text(f.color), status: text(f.status),
    home: f.home === undefined ? "projects" : text(f.home), icon: text(f.icon),
    credits, client: text(f.client), agency: text(f.agency), logline: text(f.logline),
    film_path: pyStrip(text(f.film_path)), website: pyStrip(text(f.website)),
    story: f.story, finder_sidebar: truthy(f.finder_sidebar),
  };
}

/**
 * The credits engine.create_project writes: the form's, with the older single
 * Director field added to Director's list (`setdefault(...).append`).
 */
export function creditsWanted(r) {
  const out = {};
  for (const [role, people] of Object.entries(r.credits)) out[role] = [...(people || [])];
  if (r.director_id || pyStrip(r.director_new)) {
    if (!out.Director) out.Director = [];
    out.Director.push(r.director_id ? { id: r.director_id } : { name: pyStrip(r.director_new) });
  }
  return out;
}

/** The credits whose role the record keeps (credits.LINES, a Projects property). */
const columnOf = (role) => {
  const field = Object.prototype.hasOwnProperty.call(LINE_FACTS, role) ? LINE_FACTS[role] : null;
  return field && FACTS[field] ? FACTS[field][1] : null;
};

/** Whether any credit names someone by a typed name only — Crew is read for it. */
export function needsCrew(credits) {
  for (const [role, people] of Object.entries(credits)) {
    if (!columnOf(role)) continue;
    for (const one of people || []) {
      const pid = bareId(text(isObject(one) ? one.id || "" : ""));
      const typed = pySplit(text(isObject(one) ? one.name || "" : "")).join(" ");
      if (!pid && typed) return true;
    }
  }
  return false;
}

/** crewrows.icon_for */
export function crewIcon(props) {
  const sel = (col) => ((((props || {})[col] || {}).select) || {}).name || "";
  const title = (((props || {}).Name || {}).title || []).map((t) => (t.text || {}).content || "").join("");
  const company = sel("Type") === "Vendor" && normName(title) === normName(sel("Company"));
  return CREW_ICON(company ? "city" : "person-masculine");
}

/** crewrows._check */
function readsBackOff(back, props) {
  const got = (back && back.properties) || {};
  const off = [];
  const words = (rich) => (rich || []).map((t) => t.plain_text || "").join("");
  for (const [column, want] of Object.entries(props)) {
    const have = got[column] || {};
    const kind = Object.keys(want)[0];
    let a, b;
    if (kind === "title" || kind === "rich_text") { a = words(have[kind]); b = want[kind].map((t) => t.text.content).join(""); }
    else if (kind === "select") { a = (have.select || {}).name || ""; b = want.select.name; }
    else if (kind === "multi_select") { a = (have.multi_select || []).map((o) => o.name || "").sort(cmp).join("\n"); b = want.multi_select.map((o) => o.name).sort(cmp).join("\n"); }
    else if (kind === "relation") { a = (have.relation || []).map((x) => bareId(x.id)).sort(cmp).join(","); b = want.relation.map((x) => bareId(x.id)).sort(cmp).join(","); }
    else { a = JSON.stringify(have[kind] ?? null); b = JSON.stringify(want[kind] ?? null); }
    if (a !== b) off.push(column);
  }
  return off.join(", ");
}

// ── making it ───────────────────────────────────────────────────────────────

/**
 * The project, made — engine.create_project and backend.create_project's
 * follow-ups. `io` is how it reaches the world, so the look and the checks
 * run the very same steps:
 *
 *   io.notion(method, path, body)  → the answer, or throws NotionSaid
 *   io.drive.plan(form)            → drivefolders.planProject's plan
 *   io.drive.make(plan)            → { url, id, made } (throws with `made` on a part-made folder)
 *   io.volumes                     → the drives the Mac knows (knownVolumes)
 *   io.owe(item) / io.owed(id, patch) → the owed list
 *   io.record.begin(page, name) / io.record.story(page, value)
 *   io.log(words)
 *
 * Answers `{said, page, url, owed}`; throws `Handoff` while nothing is made
 * and the Mac should do it instead, or an Error in his words.
 */
export async function makeProject(form, io) {
  const r = readForm(form);
  const log = io.log || (() => {});
  let wrote = false;
  const notion = async (method, path, body) => {
    try {
      return await io.notion(method, path, body);
    } catch (e) {
      // Nothing made yet and Notion will not let this key in: the Mac's, whole.
      if (!wrote && e instanceof NotionSaid && [401, 403, 404].includes(e.status)) throw new Handoff(e.code || String(e.status));
      throw e;
    } finally {
      if (method !== "GET" && !path.endsWith("/query")) wrote = true;
    }
  };

  // ---- before anything is made ------------------------------------------------
  if (r.film_path) throw new Handoff("the Mac links a film from its own disk");
  // SERVER: the project's ID rides along, so a folder a Mac made for it
  // offline (its marker names the ID) is finished, not refused (stage 5 step 3).
  const minted = bareId(text(isObject(form) ? form.id || "" : ""));
  const plan = await io.drive.plan({ name: r.name, drive_name: r.drive_name, home: r.home, tier1: r.tier1, job: r.job,
    ...(/^[0-9a-f]{32}$/.test(minted) ? { id: minted } : {}) });
  if (!plan.ok) throw new Error(plan.why);
  const volume = r.volume;
  if (volume && !(io.volumes || []).some((v) => v.name === volume)) {
    throw new Error(`${volume} is not a drive the Mac has told the server about.`);
  }
  const credits = r.tier1 ? creditsWanted(r) : {};
  if (r.tier1) {
    // SERVER: the reads that prove the key can do this, before the folder.
    await notion("GET", `data_sources/${PROJECTS}`);
    if (needsCrew(credits)) await notion("GET", `data_sources/${CREW}`);
  }

  // ---- the Google Drive folder (drivefolders.js) ----------------------------
  const lines = [];
  let folder;
  try {
    folder = await io.drive.make(plan);
  } catch (e) {
    if (e && e.made && e.made.length) wrote = true;
    throw e;
  }
  wrote = true;
  lines.push(plan.said.split("\n")[0]);
  log(`new project: created ${plan.folder}`);
  try {
    return await afterFolder(r, io, { plan, folder, lines, volume, credits, notion, log });
  } catch (e) {
    // The folder is there now, so asking again would be refused: say so.
    throw new Error(`Made the Drive folder ${plan.folder}, then stopped: ${(e && e.message) || e}`);
  }
}

/** engine.create_project from the media drive on, and backend's follow-ups. */
async function afterFolder(r, io, { plan, folder, lines, volume, credits, notion, log }) {
  // ---- what the Mac owes: the media drive's folders, the Finder sidebar ------
  const parts = {};
  if (volume) parts.media = { volume, state: "open" };
  // backend.create_project pins any new folder, a quick job's too.
  if (r.finder_sidebar) parts.sidebar = { state: "open" };
  let owed = null;
  if (Object.keys(parts).length) {
    owed = await io.owe({ name: r.name, page: "", slug: plan.slug, section: plan.section, home: plan.section,
      drive_folder: folder.url, tier1: r.tier1, parts });
  }
  if (volume) lines.push(`Media folders on ${volume}: made when the Mac next sees the drive`);

  const sidebarLine = "Finder sidebar: added by the Mac when it is next awake";
  if (!r.tier1) {
    lines.push("Quick job — no Notion row, by design.");
    // A Job's row in the Job Log (backend._job_after), while step 6's health
    // group says so (io.jobLog); before, the server wrote none.
    if (r.job && io.jobLog) lines.push(await jobLogLine(notion, r, folder.url, io.today));
    if (parts.sidebar) lines.push(sidebarLine);
    return { said: lines.join("\n"), page: "", url: folder.url, owed };
  }

  // ---- the credits, and any new Crew rows (engine._credit_relations) --------
  const relations = {};
  const added = [];
  let crew = null;
  for (const [role, people] of Object.entries(credits)) {
    const column = columnOf(role);
    if (!column) continue;
    const ids = [];
    for (const one of people || []) {
      let pid = bareId(text(isObject(one) ? one.id || "" : ""));
      const typed = pySplit(text(isObject(one) ? one.name || "" : "")).join(" ");
      if (!pid && typed) {
        if (crew === null) crew = await crewRows(notion);
        const hit = crew.find((x) => casefold(pySplit(text(x.name)).join(" ")) === casefold(typed));
        if (hit) {
          pid = bareId(hit.id || "");
        } else {
          const made = await makeCrew(notion, role, typed);
          if (!made.id) throw new Error(`${typed} couldn't be added to Crew: ${made.why || ""}`);
          pid = made.id;
          crew.push({ id: pid, name: typed });
          added.push(typed);
        }
      }
      if (pid && !ids.includes(pid)) ids.push(pid);
    }
    if (ids.length) relations[column] = { relation: ids.map((id) => ({ id })) };
  }
  for (const who of added) lines.push(`Added ${who} to Crew`);

  // ---- the row's properties --------------------------------------------------
  const status = STATUSES.includes(pyStrip(r.status)) ? pyStrip(r.status) : STATUSES[0];
  const props = {
    Project: { title: [{ text: { content: r.name } }] },
    Status: { select: { name: status } },
  };
  if (r.ptype) props.Type = { select: { name: r.ptype } };
  if (r.length) props.Length = { select: { name: r.length } };
  if (r.date_start) {
    const d = { start: r.date_start };
    if (r.date_end) d.end = r.date_end;
    props["Shoot Dates"] = { date: d };
  }
  Object.assign(props, relations);
  for (const [column, words] of [["Client", r.client], ["Agency", r.agency], ["Logline", r.logline]]) {
    const w = pyStrip(words || "");
    if (w) props[column] = { rich_text: [{ text: { content: cut(w, 2000) } }] };
  }
  props["Drive Folder"] = { url: folder.url };
  if (r.color) {
    await ensureColor(notion, r.color, log);
    props.Color = { select: { name: r.color } };
  }
  const payload = { properties: props };
  if (r.emoji) payload.icon = { type: "emoji", emoji: r.emoji };
  if (r.icon && iconParts(r.icon)) payload.icon = iconPayload(r.icon);

  // ---- the row, from the Type's template (engine._new_project_row) ----------
  const { page, templated } = await newRow(notion, payload, r.name, log);
  const pageId = bareId(page.id || "");
  lines.push(`Notion project created (status: ${status})`);
  if (!templated) lines.push("⚠ Notion template not applied");
  log(`new project: notion row for ${r.name}`);
  if (owed) owed = (await io.owed(owed.id, { page: pageId })) || owed;

  // ---- backend.create_project's follow-ups ------------------------------------
  if (r.website && page.id) {
    let url = r.website;
    if (url && !url.includes("://")) url = `https://${url.replace(/^\/+/, "")}`;
    try {
      // SERVER: the new row by its id, not looked up by name.
      await notion("PATCH", `pages/${page.id}`, { properties: { Website: { url: url || null } } });
      log(`WEBSITE: ${r.name} → ${url || "(cleared)"}`);
      lines.push("Website link saved");
    } catch (e) {
      lines.push(`⚠ website link not saved: ${(e && e.message) || e}`);
    }
  }
  // SERVER: the record is begun now, so the Notion link takes it from here.
  try {
    await io.record.begin(pageId, r.name);
    if (r.story === "on" || r.story === "off") await io.record.story(pageId, r.story);
  } catch (e) {
    log(`record: ${r.name}: ${(e && e.message) || e}`);
  }
  if (parts.sidebar) lines.push(sidebarLine);
  return { said: lines.join("\n"), page: pageId, url: folder.url, owed, notion_url: page.url || "" };
}

/** shoots.all_crew(token, fresh=True) — every Crew row, read now. */
async function crewRows(notion) {
  const rows = [];
  let cursor;
  do {
    const got = await notion("POST", `data_sources/${CREW}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    for (const p of got.results || []) {
      const props = p.properties || {};
      let name = "?";
      for (const v of Object.values(props)) if (v && v.type === "title") { name = (v.title || []).map((t) => t.plain_text || "").join(""); break; }
      rows.push({ id: p.id, name });
    }
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return rows;
}

/** crewrows.create_person / create_company, each read back (`_create`). */
async function makeCrew(notion, role, typed) {
  const [props, why] = role === "Production Company"
    ? companyProps({ name: typed, kind: "Production Company" })
    : personProps({ name: typed, roles: [role === "Director" ? "Director/Writer" : role] });
  if (why) return { ok: false, why };
  const page = await notion("POST", "pages", { parent: { type: "data_source_id", data_source_id: CREW }, icon: crewIcon(props), properties: props });
  const back = await notion("GET", `pages/${page.id}`);
  const off = readsBackOff(back, props);
  const out = { ok: !off, id: bareId(page.id), url: page.url || "" };
  if (off) out.why = `Notion kept it, but ${off} didn't read back as written.`;
  return out;
}

/** engine._ensure_color_option: the Color choice in its own colour, the nine
 * of them written whole when this one is missing. Never stops the project. */
async function ensureColor(notion, color, log) {
  try {
    const db = await notion("GET", `data_sources/${PROJECTS}`);
    const prop = (db.properties || {}).Color;
    const have = new Set(prop ? ((prop.select || {}).options || []).map((o) => o.name) : []);
    if (prop && have.has(color)) return;
    await notion("PATCH", `data_sources/${PROJECTS}`, { properties: { Color: { select: { options: COLORS.map((c) => ({ name: c, color: c })) } } } });
  } catch (e) {
    if (e instanceof Handoff) throw e;
    log(`color option ensure failed: ${(e && e.message) || e}`);
  }
}

/**
 * engine._new_project_row: the row with the database's default template, or —
 * when Notion refuses the template (4xx) — a plain row, its native icon set
 * after. Anything else is raised: a second try could make two rows.
 */
async function newRow(notion, payload, name, log) {
  const parent = { type: "data_source_id", data_source_id: PROJECTS };
  try {
    return { page: await notion("POST", "pages", { ...payload, parent, template: { type: "default" } }), templated: true };
  } catch (e) {
    if (!(e instanceof NotionSaid) || !(e.status >= 400 && e.status < 500)) throw e;
    log(`new project: Notion refused the template for ${name} (${e.status}: ${e.message}) — made a plain row instead`);
  }
  const icon = payload.icon || {};
  const native = icon.type === "icon";
  const plain = {};
  for (const [k, v] of Object.entries(payload)) if (!(native && k === "icon")) plain[k] = v;
  plain.parent = parent;
  const page = await notion("POST", "pages", plain);
  if (native) {
    try {
      await notion("PATCH", `pages/${page.id}`, { icon });
    } catch (e) {
      log(`new project: ${name}'s icon not set — ${(e && e.message) || e}`);
    }
  }
  return { page, templated: false };
}

// ── the switch, and the owed list ────────────────────────────────────────────

/** `{on, at, by}` — off until thrown. */
export function switchOf(raw) {
  const v = isObject(raw) ? raw : {};
  return { on: v.on === true, at: v.at || null, by: v.by || null };
}

/** The owed list's parts the Mac marks: the media drive's folders, the sidebar. */
// ── a Job's Job Log row (engine.job_log_row, backend._job_after) ─────────────

/** The Job Log, the money ledger: its data source (notionlink.IDS["job_log"]). */
export const JOB_LOG = "feedface-0000-4000-8000-00000000000f";
/** engine.JOB_LOG_TYPES: a Job's Type, as the Job Log's "Project Type" names it. */
export const JOB_LOG_TYPES = { Narrative: "Short Film", Commercial: "Commercial", "Music Video": "Music Video", Personal: "Other" };

/** Today on his clock (the Mac's `date.today()`). */
export function todayHere(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Vancouver", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

/**
 * engine.job_log_row's page: Job Name and Project the job's name, Position
 * Cinematographer, Payment Status Not Started, Entry Date the shoot's first
 * day (else today), the Drive folder in Notes. Rate, days and client are
 * left for him.
 */
export function jobLogPage({ name, ptype = "", date_start = "", drive_url = "" }, today = todayHere()) {
  const props = {
    "Job Name": { title: [{ text: { content: name } }] },
    Project: { select: { name: cut(name, 100).replaceAll(",", " ") } },
    Position: { select: { name: "Cinematographer" } },
    "Payment Status": { status: { name: "Not Started" } },
    "Entry Date": { date: { start: date_start || today } },
  };
  const kind = JOB_LOG_TYPES[String(ptype || "").split(/\s+/).filter(Boolean).join(" ")] || "";
  if (kind) props["Project Type"] = { select: { name: kind } };
  if (drive_url) props.Notes = { rich_text: [{ text: { content: drive_url } }] };
  return { parent: { type: "data_source_id", data_source_id: JOB_LOG }, properties: props };
}

/** backend._job_after's Job Log line: written, or why not (never stops the Job). */
export async function jobLogLine(notion, r, url, today) {
  try {
    await notion("POST", "pages", jobLogPage({ name: r.name, ptype: r.ptype, date_start: r.date_start, drive_url: url }, today || todayHere()));
    return "Job Log row added";
  } catch (e) {
    return `⚠ Job Log row not added: ${(e && e.message) || e}`;
  }
}

export const PARTS = ["media", "sidebar"];
const OWED_KEEP_MS = 30 * 24 * 3600 * 1000;

/** A new owed item, as kept. */
export function owedItem(fields, now = new Date()) {
  return {
    id: crypto.randomUUID().replace(/-/g, "").slice(0, 12),
    asked: now.toISOString(), by: "server", state: "open",
    ...fields,
  };
}

/** One part marked: `{part, state: done|failed|open, said, by}` → the item, or `{problem}`. */
export function marked(item, said, now = new Date()) {
  const s = isObject(said) ? said : {};
  const part = String(s.part || "");
  if (!isObject(item.parts) || !isObject(item.parts[part])) return { problem: `This item owes no ${part || "part"}.` };
  const state = String(s.state || "");
  if (!["done", "failed", "open"].includes(state)) return { problem: "Say state: done, failed or open." };
  const next = { ...item, parts: { ...item.parts } };
  next.parts[part] = { ...item.parts[part], state, said: String(s.said || "").slice(0, 500), at: now.toISOString(), by: String(s.by || "").slice(0, 80) };
  const open = Object.values(next.parts).some((p) => p.state === "open");
  next.state = open ? "open" : "done";
  if (!open) next.done_at = now.toISOString(); else delete next.done_at;
  return { item: next };
}

/** Kept: every open item; a finished one for thirty days. */
export function pruneOwed(items, now = Date.now()) {
  return (items || []).filter((x) => isObject(x) && (x.state === "open" || !x.done_at || now - Date.parse(x.done_at) < OWED_KEEP_MS));
}
