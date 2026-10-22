/**
 * **The connector's projects** (stage 5 step 5, 2026-10-14).
 *
 * What the AI connector (`mcp.js`) knows about a project beyond its Studio
 * side: its one ID (`projectid.js`), whether it is a Project or a Job, its
 * Type, and whether it has a Studio side at all. Kept beside `mcp.js` so the
 * checks (`hub/mcpstep5.mjs`) can reach it without a worker.
 *
 * - **Opening** takes the project's ID, its Notion page, its film's relay id
 *   (an alias) or its name. A project with no Studio side (a Job, say, or a
 *   project with every mode off) opens too, for him: it answers plainly that
 *   it has no shot list, and `modes` makes one.
 * - **The remembered open project** keeps its ID and follows it: when the
 *   project's Studio side is made or moves, the next call goes there.
 */
import { resolveProject, studioOf, bare, ID, readIds } from "./projectid.js";
import { keys } from "../../relay/layout.js";
import { typeOfRecord, readModes, setMode, modesOn, MODES, TITLES } from "./studiomodes.js";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

/** A Job: no Notion Projects row by design. Either shape the server writes. */
export const isJob = (record) => Boolean(isObject(record) && (record.job === true || record.kind === "job"));

/** "Project" or "Job". */
export const kindWord = (record) => (isJob(record) ? "Job" : "Project");

/** The project's name as the record keeps it: its title fact, else its name. */
export function nameOf(record) {
  const t = isObject(record) && isObject(record.facts) && isObject(record.facts.title) ? record.facts.title.value : "";
  return String((typeof t === "string" && t.trim()) || (isObject(record) && record.name) || "").trim();
}

/** The Type, "" when the record has none. "Music Video" behaves like Commercial. */
export const typeOf = (record) => (isObject(record) ? typeOfRecord(record) : "");

/** Every record in the bucket, `[{key, record}]`. */
export async function allRecords(env) {
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const k = p.split("/")[1];
      if (ID.test(k)) keys.push(k);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  const out = [];
  for (const key of keys) {
    const got = await env.BUCKET.get(`r/${key}/record.json`);
    if (!got) continue;
    try {
      const record = await got.json();
      if (isObject(record)) out.push({ key, record });
    } catch { /* unreadable: left out */ }
  }
  return out;
}

/**
 * **Every project this person may open**, each with its ID, Project or Job,
 * Type and Studio side. `films` is `filmsFor`'s answer (the Studio sides and
 * portals they have a part in). `admin` (him) also sees the projects with no
 * Studio side and no portal, which have nobody else on them.
 */
export async function projectRows(env, films, admin) {
  // A deleted project's record stays (its Undo needs it) and is never listed.
  const records = (await allRecords(env)).filter((r) => !r.record.deleted);
  const ids = await readIds(env).catch(() => ({ alias: {} }));
  const byKey = new Map(records.map((r) => [r.key, r]));
  const byStudio = new Map();
  for (const r of records) {
    byStudio.set(r.key, r);
    const relay = studioOf(r.record);
    if (relay) byStudio.set(relay, r);
  }
  for (const [alias, key] of Object.entries(ids.alias || {})) if (byKey.has(key) && !byStudio.has(alias)) byStudio.set(alias, byKey.get(key));
  const used = new Set();
  const rows = films.map((f) => {
    const r = byStudio.get(f.project) || null;
    if (r) used.add(r.key);
    const record = r ? r.record : null;
    return {
      project: (record && nameOf(record)) || f.title,
      id: r ? r.key : f.project,
      is: kindWord(record),
      type: typeOf(record),
      studio: f.portal ? "none yet, only its portal" : "yes",
      you_may: f.role === "editor" ? (f.portal ? "read and change its pages" : "read and change") : (f.portal ? "read its pages" : "read"),
      ...(f.portal ? {} : { changes: f.logs }),
      open: f.project,
      side: !f.portal,
      title: f.title,
    };
  });
  if (admin) {
    for (const r of records) {
      if (used.has(r.key)) continue;
      const relay = studioOf(r.record);
      // A record naming a film that is not in the bucket (yet): still listed, as it stands.
      rows.push({
        project: nameOf(r.record) || r.key, id: r.key, is: kindWord(r.record), type: typeOf(r.record),
        studio: relay ? "named but not on the server" : "none", you_may: "read and change its record and modes",
        open: r.key, side: false, title: "",
      });
    }
  }
  rows.sort((a, b) => a.project.localeCompare(b.project));
  return rows;
}

/** A row as the `projects` tool says it: no bookkeeping. */
export const shownRow = ({ open, side, title, ...row }) => (title && title !== row.project ? { ...row, studio_title: title } : row);

/**
 * **The project somebody meant**: its name, its ID (the project's own, its
 * Notion page, or its film's relay id, `resolveProject`), or a part of its
 * name. `null` when none of theirs.
 */
export async function findProject(env, rows, wanted) {
  const w = String(wanted || "").trim();
  if (!w) return null;
  const same = (a, b) => a.trim().toLowerCase() === b.trim().toLowerCase();
  // The project's name first, then the Studio side's own title (a film
  // still called what it was before the project was renamed).
  let row = rows.find((r) => same(r.project, w)) || rows.find((r) => r.title && same(r.title, w));
  if (!row && ID.test(bare(w))) {
    const found = await resolveProject(env, w);
    if (found.key) row = rows.find((r) => r.id === found.key);
  }
  if (!row && /^[0-9a-f-]{8,72}$/i.test(w)) row = rows.find((r) => r.open === bare(w) || r.id === bare(w));
  if (!row) row = rows.find((r) => r.project.toLowerCase().includes(w.toLowerCase()) || (r.title || "").toLowerCase().includes(w.toLowerCase()));
  return row || null;
}

/**
 * **The remembered open project, followed.** `open` is what was kept
 * (`{project, id?, side?}`, older ones just `{project}`). Answers where it
 * is now: `{project, id, side, moved}`. The project's ID is looked up when an
 * older note lacks it (an alias reaches it), and when the record now names a
 * Studio side elsewhere (made by a mode going on, or under its own ID), the
 * open project goes there.
 */
export async function followOpen(env, open) {
  const was = String((open && open.project) || "");
  const hadId = bare(open && open.id);
  const hadSide = !(open && open.side === false);
  let id = hadId;
  let project = was;
  let looked = Boolean(open && open.looked);
  let found = await resolveProject(env, id || was).catch(() => ({ key: "" }));
  // A film whose record is not under its id, and no alias frozen yet: the
  // record naming it, looked for once and the answer kept.
  if (!found.key && !looked && was) {
    looked = true;
    const hit = (await allRecords(env)).find((r) => studioOf(r.record) === was);
    if (hit) found = { key: hit.key, record: hit.record };
  }
  if (found.key) {
    id = found.key;
    const relay = studioOf(found.record);
    if (relay && relay !== project && await env.BUCKET.head(keys.manifest(relay))) project = relay;
  }
  // Anything of it on the server (a film, a portal, its people) is a side.
  const side = (hadSide && project === was) || Boolean(await env.BUCKET.head(keys.manifest(project))
    || await env.BUCKET.head(keys.portal(project)) || await env.BUCKET.head(keys.people(project)));
  return { project, id, side, looked, moved: project !== was || id !== hadId || side !== hadSide || looked !== Boolean(open && open.looked) };
}

/** What a project with no Studio side says when one of its tools is asked. */
export function noSideSaid(name, record) {
  const what = kindWord(record);
  return `${name || "This project"} is a ${what} with no Studio side: it has no shot list, locations, references, schedule or diagram. \`modes\` turns one on, which makes it.`;
}

/** What opening a project with no Studio side says. */
export function openedNoSide(name, record, id) {
  const type = typeOf(record);
  return [
    `Opened ${name}, a ${kindWord(record)}${type ? ` (${type})` : ""}. ID ${id}.`,
    "It has no Studio side: no shot list, locations, references, schedule or diagram.",
    "`modes` shows its modes and turns one on, which makes its Studio side. `record` reads its record.",
  ].join("\n");
}

/** Who the project is, for `summary` and `open_project`. */
export function projectFacts(record, id) {
  if (!isObject(record)) return { id, is: "Project", type: "" };
  return { id, is: kindWord(record), type: typeOf(record) };
}

// ── the `modes` tool ─────────────────────────────────────────────────────────

export const MODES_TOOL = {
  name: "modes",
  description: "The open project's Studio modes: Shot List, Locations, References, Schedule, Diagram. Read: which are on, its Type's standard set, and whether it is a Project or a Job (a Job starts with none). Give `mode` and `on` to turn one on or off: on is at once; off hides it and deletes nothing. Schedule on brings Shot List on; Shot List off with Schedule on is refused unless `both` is true, which turns both off. The first mode turned on for a project with no Studio side makes it. Changing needs the server's modes switch on; ask him before turning one off.",
  inputSchema: {
    type: "object",
    properties: {
      mode: { type: "string", enum: [...MODES], description: "shot_list, locations, references, schedule or diagram (or its title, \"Shot List\")." },
      on: { type: "boolean" },
      both: { type: "boolean", description: "With Shot List off while Schedule is on: turn both off." },
    },
    required: [],
  },
};

/** A mode as somebody says it: `shot_list`, "Shot List", "shotlist". */
export function modeKey(said) {
  const s = String(said || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (MODES.includes(s)) return s;
  const flat = s.replace(/_/g, "");
  return MODES.find((m) => m.replace(/_/g, "") === flat || TITLES[m].toLowerCase().replace(/\s/g, "") === flat) || "";
}

const titled = (list) => (list.length ? list.map((m) => TITLES[m]).join(", ") : "none");

/**
 * Read or set the open project's modes. `found` is `{id, title, role}`;
 * `deps.setMode` stands in for the checks. Answers text; throws `refuse(...)`.
 */
export async function modesTool(env, found, args, refuse, who, deps = {}) {
  const a = isObject(args) ? args : {};
  if (!found.id) throw refuse(`${found.title || "This project"} has no project record yet, so it has no modes: every mode shows.`);
  const asked = a.mode !== undefined || a.on !== undefined;
  if (!asked) {
    const got = await readModes(env, found.id);
    if (!got.ok) throw refuse(got.why || "No project with that ID.");
    const sw = await modesOn(env);
    return { said: JSON.stringify({
      project: found.title, id: got.id, is: got.job ? "Job" : "Project", type: got.type || "",
      on: Object.fromEntries(MODES.map((m) => [m, got.modes.includes(m)])),
      standard: got.standard,
      differs: got.set,
      studio_side: got.relay ? "yes" : "none yet",
      switch: sw.on ? "on: Studio follows the modes" : "off: Studio shows every mode, and modes cannot be changed yet",
    }, null, 1) };
  }
  if (found.role !== "editor") throw refuse("Only an editor may change a project's modes.");
  const mode = modeKey(a.mode);
  if (!mode) throw refuse(`Say which mode: ${MODES.join(", ")}.`);
  if (typeof a.on !== "boolean") throw refuse("Say on: true or on: false.");
  const by = `AI connector${who && who.email ? ` (${who.email})` : ""}`.slice(0, 80);
  const set = deps.setMode || ((id, said) => setMode(env, id, said));
  const got = await set(found.id, { mode, on: a.on, both: a.both === true, by });
  if (!got || !got.ok) {
    const why = (got && got.why) || "The mode could not be changed.";
    throw refuse(got && got.needs === "both" ? `${why} Send both: true to turn both off.` : why);
  }
  const lines = [];
  if (got.unchanged) lines.push(`${TITLES[mode]} was already ${a.on ? "on" : "off"}.`);
  else lines.push(`${TITLES[mode]} is ${a.on ? "on" : "off"}.${a.on ? "" : " Nothing is deleted."}`);
  for (const m of got.also || []) lines.push(`${TITLES[m]} ${a.on ? "came on" : "went off"} with it.`);
  if (got.side) lines.push("Its Studio side was made.");
  lines.push(`On: ${titled(got.modes)}.`);
  return { said: lines.join(" "), side: got.side || null, modes: got.modes };
}
