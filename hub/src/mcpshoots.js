/**
 * **Shoots and their crew, from the AI connector** (2026-10-19).
 *
 * Notion AI is connected to the Studio connector and could change a shoot's
 * dates (`set_shoot`) but not add one. Three tools here:
 *
 * - `add_shoot` — Projects Console's Add Shoot, in two steps. Step 1 (no
 *   `confirm`) writes nothing: it plans the shoot exactly as the console's
 *   button does (`newshoot.js`, the server path the console itself calls) and
 *   hands back the preview with a short-lived `confirm` token. Step 2 (the
 *   same details plus the token) makes it: the Shoots row and spec sheet in
 *   Notion, the `shoot-N` Drive folders, the Studio day, the portal page.
 * - `set_shoot_crew` — people on or off one shoot, each with the role they
 *   hold on this project.
 * - `shoots` — every shoot with its crew.
 *
 * **Owner only.** All three are his alone; a collaborator is refused.
 *
 * **Notion down.** Notion is the shoot row's home, and its key can be dead
 * (it was, 2026-10-19). Then step 1 plans from the project's record alone and
 * says so; step 2 makes the Drive folders at once and QUEUES the rest on the
 * record (`shoots_waiting`). The record shows the queued shoot (flagged
 * `waiting_for_notion`) and the minute's Notion look (`notionsync.js`) makes
 * the rest, the same form run again, as soon as Notion answers.
 *
 * **Per-project roles.** A person's role on one project may differ from their
 * Crew role in Notion. It is the record's `crew_roles` ({Crew page id:
 * [role]}), never written to Notion; `roles_here` marks it on the crew copy.
 */
import { writeFacts } from "./facts.js";
import { sha256Hex, owners } from "./films.js";
import { bareId, cleanName, notionOf, relationAll } from "./cloud.js";
import { shootParts } from "./notion.js";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const oneLine = (said) => String(said == null ? "" : said).replace(/\s+/g, " ").trim();
const BY = "AI connector";
const CONFIRM_SECONDS = 600;
const PAGE = /^[0-9a-f]{32}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

const WHERE = "A project's shoots and their crew live in its project record (Studio's own copy; Notion follows). Editing Notion's Shoots rows or a Notion project page directly does NOT reliably reach Studio and can be overwritten by the next sync, so always use these tools (add_shoot, set_shoot, set_shoot_crew, set_record) to change a project's shoots, dates or crew.";

export const SHOOT_TOOLS = [
  {
    name: "add_shoot",
    description:
      "Add a shoot to a project (Shoot 2, a pickup day) exactly as Projects Console's Add Shoot does: the shoot on the project record, its Notion Shoots row with the spec sheet carried forward, its shoot-N Drive folders, the Studio day and the portal page. His alone.\n\n"
      + "TWO STEPS, ALWAYS. Step 1: the details and NO `confirm`: nothing is made; you get a `preview` and a `confirm` token (10 minutes). SHOW HIM THAT PREVIEW AND WAIT FOR HIS OK. Step 2, only after his yes: the SAME details plus `confirm`. A missing, wrong, used or expired token, or changed details, is refused and nothing is made.\n\n"
      + "If Notion can't be reached, the Drive folders are made at once and the Notion part waits on the record until Notion answers; never add the shoot twice. Shoots and crew live in the project record: editing Notion's Shoots rows directly does NOT reliably reach Studio, so use these tools.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "The project's name or ID. Leave out to use the open project." },
        start: { type: "string", description: "First day, YYYY-MM-DD." },
        end: { type: "string", description: "Last day, YYYY-MM-DD, for a shoot of more than one day." },
        name: { type: "string", description: "What he calls it (\"Malibu Pickup\"). Leave out for plain Shoot N." },
        notes: { type: "string", description: "What changes from the last shoot (Notion's What Changes); written for him if left out." },
        crew: { type: "array", items: { type: "string" }, description: "Names or Crew ids on this shoot. Leave out to carry over the last shoot's crew; [] for nobody. Someone not in his Crew directory is added there first (set_crew new_person)." },
        pickups: { type: "array", items: { type: "string" }, description: "Scene numbers re-shot on this shoot." },
        new_scenes: { type: "array", items: { type: "string" }, description: "New scenes; Studio adds days, not scenes, so these come back as things to do by hand." },
        confirm: { type: "string", description: "Step 2 only: the token step 1 gave, with exactly the same details." },
      },
      required: ["start"],
    },
  },
  {
    name: "set_shoot_crew",
    description:
      "Put people on, or take them off, one shoot of a project, and give each the role they hold on THIS project, as Projects Console's per-shoot people do. His alone. Who is on a shoot is written to Notion's Crew row (refused with the reason if Notion can't be reached); a role on this project is the record's alone (`crew_roles`) and works without Notion; their usual Crew role is never changed. Someone already on every shoot is on this one; adding a role for them only sets the role. Read `shoots` first; the reply says exactly what changed. Shoots and crew live in the project record: editing Notion's Shoots rows directly does NOT reliably reach Studio, so use these tools.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "The project's name or ID. Leave out to use the open project." },
        shoot: { type: "string", description: "The shoot's id, name, or its number (2 for Shoot 2)." },
        add: { type: "array", items: { type: "object", properties: { person: { type: "string", description: "A name or Crew id." }, role: { type: "string", description: "What they do on this project (\"Key Grip\"); \"\" puts them back on their usual role." } }, required: ["person"] }, description: "People to add, each {person, role} (a bare name or Crew id works too)." },
        remove: { type: "array", items: { type: "string" }, description: "People to take off this shoot (name or Crew id)." },
        off_project: { type: "boolean", description: "With `remove`: taking someone off their only shoot would put them on every shoot, so it is refused unless this is true, which takes them off the project's crew altogether." },
      },
      required: ["shoot"],
    },
  },
  {
    name: "shoots",
    description:
      "Every shoot of a project, oldest first, each with its dates, name, notes, status and its crew (who, their role on this project, whether they are on all shoots) — from the project record. A shoot queued while Notion was unreachable is listed too, marked `waiting_for_notion`. His alone (owner). `project` is a name or ID (leave out to use the open project). "
      + WHERE,
    inputSchema: { type: "object", properties: { project: { type: "string" } }, required: [] },
  },
];

export const SHOOT_TOOL_NAMES = new Set(SHOOT_TOOLS.map((t) => t.name));

// ── the record ───────────────────────────────────────────────────────────────

const factValue = (facts, field) => {
  const one = (facts || {})[field];
  return isObject(one) ? one.value : undefined;
};

async function readRecord(env, page) {
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

/** Waiting shoots (queued while Notion was out) on a record's facts. */
export function waitingOf(facts) {
  const v = factValue(facts, "shoots_waiting");
  return Array.isArray(v) ? v.filter((w) => isObject(w) && w.id) : [];
}

/** The people on one shoot, from the crew copy. */
export function crewOnShoot(people, shootId) {
  return (Array.isArray(people) ? people : [])
    .filter((p) => isObject(p) && (p.all_shoots || (p.shoots || []).includes(shootId)))
    .map((p) => ({ person: p.person, name: p.name || "", role: (p.roles || []).join(", "),
      ...(p.roles_here ? { role_on_this_project: true } : {}), ...(p.all_shoots ? { on_all_shoots: true } : {}) }));
}

/**
 * Every shoot with its crew: the record's copy of the Shoots rows, then the
 * shoots still waiting for Notion. Shared by `shoots` and `record`.
 */
export function shootsWithCrew(facts, rows = null) {
  const people = factValue(facts, "crew");
  const copy = rows || (Array.isArray(factValue(facts, "shoots")) ? factValue(facts, "shoots") : []);
  const out = copy.filter(isObject).map((row) => ({ ...row, crew: crewOnShoot(people, String(row.id || "").replace(/-/g, "")) }));
  for (const w of waitingOf(facts)) {
    const ids = Array.isArray(w.form && w.form.crew) ? w.form.crew.map(bareId) : [];
    out.push({ id: w.id, title: w.title, label: w.label, name: w.form ? oneLine(w.form.name) : "", n: w.n, start: w.start, end: w.end || "",
      status: "Upcoming", changes: w.form ? String(w.form.changes || "") : "", waiting_for_notion: true,
      crew: (Array.isArray(people) ? people : []).filter((p) => isObject(p) && ids.includes(bareId(p.person)))
        .map((p) => ({ person: p.person, name: p.name || "", role: (p.roles || []).join(", ") })) });
  }
  return out;
}

// ── the entry: who, which project ────────────────────────────────────────────

/**
 * One call. `held`/`who` are the connector's; `deps` stand in for the world in
 * checks (`readiness`, `depsFor`, `notion`, `now`, `afterAdd`) and are honoured
 * only on a machine whose Notion is a stand-in on localhost.
 */
export async function shootToolRun(env, found, name, args, refuse, who, deps = {}) {
  const a = isObject(args) ? args : {};
  const mine = owners(env).includes(String((who && who.email) || "").toLowerCase());
  if (!mine) throw refuse("Only Nathaniel can add shoots or change who is on them.");
  if (!found || !found.id) throw refuse("Say which project (`project`), or open one first with `open_project`.");
  const { resolveProject } = await import("./projectid.js");
  const got = await resolveProject(env, found.id);
  if (!got.key || !got.record) throw refuse(`${found.title || "That project"} has no project record, so it has no shoots on it.`);
  const record = got.record;
  if (record.job === true || record.kind === "job") throw refuse(`${found.title || "That"} is a Job. Jobs have no shoots; only a Project does.`);
  // `key` is where the record lives; `page` the Notion page its rows point at
  const page = String(record.notion_page || record.page || got.key);
  if (!PAGE.test(page)) throw refuse("That project's record has no page of its own yet.");
  const facts = isObject(record.facts) ? record.facts : {};
  const title = oneLine(factValue(facts, "title")) || oneLine(record.name) || found.title;
  const cx = { env, key: got.key, page, record, facts, title, refuse, who, deps };
  if (name === "shoots") return JSON.stringify({ project: title, shoots: shootsWithCrew(facts) }, null, 1);
  if (name === "add_shoot") return await addShoot(cx, a);
  if (name === "set_shoot_crew") return await setShootCrew(cx, a);
  throw refuse("No such tool.");
}

// ── add_shoot ────────────────────────────────────────────────────────────────

const canon = (x) => {
  if (Array.isArray(x)) return `[${x.map(canon).join(",")}]`;
  if (isObject(x)) return `{${Object.keys(x).sort().map((k) => `${JSON.stringify(k)}:${canon(x[k])}`).join(",")}}`;
  return JSON.stringify(x === undefined ? null : x);
};

/** What step 2 must repeat exactly: the details, normalised. */
function askedOf(args) {
  const list = (v) => (Array.isArray(v) ? v.map((x) => oneLine(x)).filter(Boolean) : undefined);
  return {
    start: oneLine(args.start), end: oneLine(args.end), name: oneLine(args.name), notes: String(args.notes == null ? "" : args.notes).trim(),
    crew: Array.isArray(args.crew) ? args.crew.map((x) => oneLine(isObject(x) ? x.person || x.name || x.id : x)).filter(Boolean) : null,
    pickups: list(args.pickups) || [], new_scenes: list(args.new_scenes) || [],
  };
}

const tokenKey = async (token) => `mcp/shoot-confirm/${await sha256Hex(String(token))}.json`;

async function mintToken(cx, asked, now) {
  const raw = crypto.getRandomValues(new Uint8Array(18));
  const token = [...raw].map((b) => b.toString(16).padStart(2, "0")).join("");
  await cx.env.BUCKET.put(await tokenKey(token), JSON.stringify({
    tool: "add_shoot", page: cx.page, email: String((cx.who && cx.who.email) || "").toLowerCase(),
    asked: await sha256Hex(canon(asked)), until: now + CONFIRM_SECONDS * 1000,
  }), { httpMetadata: { contentType: "application/json" } });
  return token;
}

/** Take the token (it works once). Throws the refusal when it will not do. */
async function takeToken(cx, token, asked, now) {
  const key = await tokenKey(token);
  const got = await cx.env.BUCKET.get(key);
  let held = null;
  try { held = got ? await got.json() : null; } catch { held = null; }
  const again = "Ask for the preview again (call add_shoot without `confirm`), show it to him, and use the new token.";
  if (!held) throw cx.refuse(`That confirmation isn't one I gave, or it was already used. Nothing was made. ${again}`);
  if (now > Number(held.until || 0)) {
    await cx.env.BUCKET.delete(key);
    throw cx.refuse(`That confirmation has expired (they last ten minutes). Nothing was made. ${again}`);
  }
  const email = String((cx.who && cx.who.email) || "").toLowerCase();
  if (held.tool !== "add_shoot" || held.page !== cx.page || held.email !== email) throw cx.refuse(`That confirmation is for something else. Nothing was made. ${again}`);
  if (held.asked !== await sha256Hex(canon(asked))) throw cx.refuse(`The details changed since the preview he saw. Nothing was made. ${again}`);
  await cx.env.BUCKET.delete(key);                       // used: once
}

async function worldOf(cx, write) {
  const rules = await import("./newshoot.js");
  const door = await import("./newshootdoor.js");
  const depsFor = cx.deps.depsFor || door.depsFor;
  const ready = await (cx.deps.readiness || door.readiness)(cx.env);
  if (!ready.ok) throw cx.refuse(`Add Shoot isn't switched on for the server: ${ready.why}. It can still be done with the New Shoot… button in Projects Console.`);
  const n = cx.deps.notion || notionOf(cx.env);
  const d = await depsFor(cx.env, n, cx.title, { write, ctx: cx.deps.ctx || null });
  return { rules, d, n };
}

/** The context: Notion's when Notion answers, else the record's. */
async function contextOf(cx, rules, d) {
  try {
    return { ctx: await rules.shootsCtx(d, cx.title), down: false };
  } catch (e) {
    if (!rules.notionOut(e)) throw e;
  }
  const ctx = await rules.ctxFromRecord(d, { name: cx.title, page: cx.page, facts: cx.facts, waiting: waitingOf(cx.facts) });
  return { ctx, down: true };
}

function resolvePerson(said, pool, refuse) {
  const want = oneLine(said).toLowerCase();
  const id = want.replace(/-/g, "");
  const hit = pool.filter((c) => bareId(c.id) === id || oneLine(c.name).toLowerCase() === want);
  if (hit.length === 1) return hit[0];
  const all = pool.map((c) => c.name).filter(Boolean).slice(0, 40).join(", ");
  throw refuse(hit.length ? `More than one person answers to “${said}”; use their Crew id.` : `“${said}” isn't on this project's crew. People on it: ${all || "none"}. Someone new is added to his Crew in Projects Console first.`);
}

/** The engine's form: what the console's sheet posts. */
function formOf(cx, rules, ctx, asked) {
  const offered = rules.offeredCrew(ctx);
  const first = !ctx.shoots.length;
  let crew;
  if (asked.crew === null) crew = offered.filter((c) => c.ticked).map((c) => c.id);
  else crew = asked.crew.map((said) => resolvePerson(said, ctx.crew, cx.refuse).id);
  return {
    start: asked.start, end: asked.end, name: asked.name, changes: asked.notes, crew,
    ...(first ? { first_crew: offered.filter((c) => c.ticked).map((c) => c.id) } : {}),
    pickups: asked.pickups, new_scenes: asked.new_scenes, newcomers: [], fields: {},
  };
}

async function addShoot(cx, args) {
  const { refuse, deps } = cx;
  const now = deps.now ? deps.now() : Date.now();
  const asked = askedOf(args);
  if (!DAY.test(asked.start)) throw refuse("Say the first day as `start`, YYYY-MM-DD.");
  if (asked.end && !DAY.test(asked.end)) throw refuse("`end` is a day, YYYY-MM-DD.");
  const confirm = oneLine(args.confirm);
  if (confirm) await takeToken(cx, confirm, asked, now);   // a bad token ends it here, before anything is read

  const { rules, d, n } = await worldOf(cx, Boolean(confirm));
  const { ctx, down } = await contextOf(cx, rules, d);
  const form = formOf(cx, rules, ctx, asked);
  const mode = down ? "down" : undefined;
  const planned = await rules.planAnswer(d, cx.title, form, { ctx, ...(mode ? { mode } : {}) });
  if (!planned.ok || !planned.can_run) {
    const why = [...(planned.problems || [])].join(" ") || "It can't be set up.";
    throw refuse(`${why} Nothing was made.`);
  }
  const names = form.crew.map((id) => (ctx.crewById.get(id) || { name: id }).name);
  const said = {
    project: cx.title, shoot: { label: planned.label, title: planned.title, start: asked.start, ...(asked.end && asked.end !== asked.start ? { end: asked.end } : {}) },
    crew: names, notes: planned.changes, changes_written_for_him: planned.changes_written,
  };

  if (!confirm) {
    const token = await mintToken(cx, asked, now);
    return JSON.stringify({
      ok: true, step: 1, made: "nothing yet",
      ...said,
      will_make: planned.groups, notes_on_it: planned.notes,
      ...(down ? { notion: "Notion can't be reached right now. The Drive folders will be made at once; the Notion row, spec sheet, Studio day and portal page wait for Notion to be reconnected and are made on their own then." } : {}),
      confirm: token, expires_in: "10 minutes",
      next: "Show him this preview in plain words and ask if he wants it. Only if he says yes, call add_shoot again with exactly the same details plus this `confirm`.",
    }, null, 1);
  }

  // One move at a time (bigmoves.js), as the console's ask holds it.
  const { busyWords } = await import("./bigmoves.js");
  const busy = busyWords(await readRecord(cx.env, cx.key));
  if (busy) throw refuse(`${busy} Nothing was made.`);

  let result;
  let wentDown = down;
  if (!down) {
    try {
      result = await rules.runAnswer(d, cx.title, form);
    } catch (e) {
      if (!rules.notionOut(e)) throw e;
      wentDown = true;                                   // Notion refused before anything was written
    }
  }
  if (wentDown) {
    const ctx2 = down ? ctx : await rules.ctxFromRecord(d, { name: cx.title, page: cx.page, facts: cx.facts, waiting: waitingOf(cx.facts) });
    const form2 = down ? form : formOf(cx, rules, ctx2, asked);
    const quiet = Object.create(d);
    quiet.logActivity = async (entry) => (d.logActivity
      ? d.logActivity({ ...entry, desc: `${String(entry.desc).replace(/ set up$/, "")}: Drive folders made, the rest waits for Notion` })
      : undefined);
    result = await rules.runAnswer(quiet, cx.title, form2, { ctx: ctx2, mode: "down" });
    if (!result.ok) throw refuse(result.report);
    const queued = await queueWaiting(cx, result, form2);
    return JSON.stringify({
      ok: true, step: 2, ...said, notion: "waiting",
      notion_row: "Notion row waits for Notion to be reconnected",
      queued: queued ? "Queued on the project record; made on its own within a minute or two of Notion answering." : "Could not be queued on the record; add the shoot again once Notion is back.",
      report: result.report,
    }, null, 1);
  }
  if (!result.ok) throw refuse(result.report);
  if (deps.afterAdd) await deps.afterAdd(cx);
  else if (cx.deps.ctx && cx.deps.ctx.waitUntil) cx.deps.ctx.waitUntil(refreshRecord(cx));
  return JSON.stringify({ ok: true, step: 2, ...said, notion: "made", report: result.report, ...(result.failed && result.failed.length ? { not_done: result.failed } : {}) }, null, 1);
}

/** Bring the record's copy of the Shoots rows up to date (Notion → record). Best effort. */
async function refreshRecord(cx) {
  try {
    const { syncTick } = await import("./notionsync.js");
    await syncTick(cx.env, { only: cx.page });
  } catch { /* the five-minute look does it */ }
}

/** Put the shoot in the queue on the record (compare-and-set). */
export async function queueWaiting(cx, result, form) {
  const shoot = result.shoot || {};
  const entry = {
    id: `waiting-${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`,
    n: shoot.n || null, label: shoot.label || result.label || "", title: shoot.title || "",
    start: shoot.start || form.start, end: shoot.end || "",
    form, at: new Date().toISOString(), by: BY,
  };
  for (let tries = 0; tries < 4; tries++) {
    const record = await readRecord(cx.env, cx.key);
    const facts = (record && record.facts) || {};
    const have = waitingOf(facts);
    const one = facts.shoots_waiting;
    const got = await writeFacts(cx.env, cx.key, { shoots_waiting: { value: [...have, entry], base: (one && one.v) || 0 } }, BY);
    if (got.status === 200) return true;
    if (got.status !== 409) return false;
  }
  return false;
}

/**
 * The queue, made: for one project, every waiting shoot run again as an
 * ordinary Add Shoot now that Notion answers, then taken off the queue. Called
 * by the Notion look. Answers the lines to say. Never throws.
 */
export async function catchUpWaiting(env, key, deps = {}) {
  const said = [];
  try {
    const record = await readRecord(env, key);
    const facts = (record && record.facts) || {};
    const waiting = waitingOf(facts);
    if (!waiting.length) return said;
    const title = oneLine(factValue(facts, "title")) || oneLine(record.name);
    const rules = await import("./newshoot.js");
    const door = await import("./newshootdoor.js");
    if (!(await (deps.readiness || door.readiness)(env)).ok) return said;
    const n = deps.notion || notionOf(env);
    for (const w of waiting) {
      const d = await (deps.depsFor || door.depsFor)(env, n, title, { write: true });
      let result;
      try {
        result = await rules.runAnswer(d, title, w.form || {});
      } catch (e) {
        said.push(`${title} · ${w.label}: still waiting for Notion (${oneLine(e && e.message).slice(0, 80)})`);
        break;                                            // Notion is out again: the rest wait, in order
      }
      if (!result.ok) { said.push(`${title} · ${w.label}: not made yet — ${oneLine(result.report).slice(0, 200)}`); break; }
      const fresh = await readRecord(env, key);
      const ffacts = (fresh && fresh.facts) || {};
      const left = waitingOf(ffacts).filter((x) => x.id !== w.id);
      const got = await writeFacts(env, key, { shoots_waiting: { value: left, base: (ffacts.shoots_waiting && ffacts.shoots_waiting.v) || 0 } }, "server");
      said.push(`${title} · ${w.label}: made in Notion, Studio and the portal (it was waiting for Notion)${got.status === 200 ? "" : " — the queue line stays and will be dropped next look"}`);
    }
  } catch (e) {
    said.push(`shoots waiting: ${oneLine(e && e.message).slice(0, 120)}`);
  }
  return said;
}

// ── set_shoot_crew ───────────────────────────────────────────────────────────

function pickShoot(cx, rows, saidRaw) {
  const said = oneLine(saidRaw);
  const bare = said.replace(/-/g, "").toLowerCase();
  const numbered = /^\d+$/.test(said) ? `shoot ${Number(said)}` : "";
  const nameOf = (row) => (typeof row.name === "string" && row.name) || shootParts(row.label || "").name || row.label || "";
  const hit = rows.filter((row) => String(row.id || "").replace(/-/g, "").toLowerCase() === bare
    || oneLine(nameOf(row)).toLowerCase() === said.toLowerCase()
    || oneLine(row.label || "").toLowerCase() === said.toLowerCase()
    || (numbered && oneLine(shootParts(row.label || "").base || "").toLowerCase() === numbered));
  if (hit.length !== 1) {
    const all = rows.map((row) => `${oneLine(row.label || nameOf(row))} (${row.id})`).join(", ");
    throw cx.refuse(hit.length ? `More than one shoot answers to “${said}”: use its id. ${all}.` : `No shoot called “${said}”. This project's shoots: ${all || "none"}.`);
  }
  return hit[0];
}

/** One role, a list or text, as a clean list. */
function rolesOf(said) {
  const list = Array.isArray(said) ? said : String(said == null ? "" : said).split(",");
  return [...new Set(list.map((r) => oneLine(r)).filter(Boolean))].slice(0, 6);
}

async function setShootCrew(cx, args) {
  const { refuse } = cx;
  const rows = shootsWithCrew(cx.facts);
  if (!rows.length) throw refuse("This project has no shoots on its record. A shoot is made with add_shoot.");
  const shoot = pickShoot(cx, rows, args.shoot);
  if (shoot.waiting_for_notion) throw refuse(`${shoot.label} is queued, waiting for Notion to be reconnected. Its crew is set once it is made.`);
  const sid = String(shoot.id).replace(/-/g, "");
  const adds = Array.isArray(args.add) ? args.add : [];
  const removes = Array.isArray(args.remove) ? args.remove : [];
  if (!adds.length && !removes.length) throw refuse("Say who: `add` and/or `remove`.");
  const people = (Array.isArray(factValue(cx.facts, "crew")) ? factValue(cx.facts, "crew") : []).filter(isObject);
  const known = people.map((p) => ({ id: p.person, name: p.name || "" }));
  const others = rows.filter((r) => String(r.id).replace(/-/g, "") !== sid && !r.waiting_for_notion).map((r) => String(r.id).replace(/-/g, ""));

  // resolve everyone before anything is written
  let notion = null;
  const crewRows = async () => {
    if (!notion) {
      const rules = await import("./newshoot.js");
      const n = cx.deps.notion || notionOf(cx.env);
      notion = { n, all: await rules.allCrew(n) };
    }
    return notion;
  };
  const lines = [];
  const plan = [];                                       // {person, name, addShoot, removeShoot, onProject, roles, note}
  for (const raw of adds) {
    const spec = isObject(raw) ? raw : { person: raw };
    const said = oneLine(spec.person || spec.name || spec.id);
    if (!said) throw refuse("Each person in `add` needs a name or Crew id.");
    let onProject = true;
    let who;
    try {
      who = resolvePerson(said, known, () => new Error("none"));
    } catch (e) {
      if (e.message !== "none") throw e;
      onProject = false;
      let pool;
      try { pool = (await crewRows()).all; } catch (err) {
        throw refuse(`${said} isn't on this project's crew yet, and Notion can't be reached to add them (${oneLine(err && err.message).slice(0, 60)}). Nothing was written.`);
      }
      who = resolvePerson(said, pool.map((c) => ({ id: c.id, name: c.name })), refuse);
    }
    plan.push({ kind: "add", person: bareId(who.id), name: who.name, onProject, roles: spec.role !== undefined ? rolesOf(spec.role) : null, entry: people.find((p) => bareId(p.person) === bareId(who.id)) });
  }
  for (const raw of removes) {
    const who = resolvePerson(oneLine(isObject(raw) ? raw.person || raw.name : raw), known, refuse);
    plan.push({ kind: "remove", person: bareId(who.id), name: who.name, entry: people.find((p) => bareId(p.person) === bareId(who.id)) });
  }

  // what Notion must change, per person
  const notionWork = [];
  const next = people.map((p) => ({ ...p, shoots: [...(p.shoots || [])] }));
  const entryFor = (p) => {
    let e = next.find((x) => bareId(x.person) === p.person);
    if (!e) { e = { person: p.person, name: p.name, roles: [], shoots: [], all_shoots: false }; next.push(e); }
    return e;
  };
  for (const p of plan) {
    const e = p.entry ? entryFor(p) : null;
    if (p.kind === "add") {
      if (e && e.all_shoots) { lines.push(`${p.name} is on every shoot already, so on ${shoot.label}`); }
      else if (e && (e.shoots || []).includes(sid)) { lines.push(`${p.name} is on ${shoot.label} already`); }
      else {
        notionWork.push({ person: p.person, name: p.name, add: sid, onProject: p.onProject });
        const t = entryFor(p);
        t.shoots = [...new Set([...(t.shoots || []), sid])]; t.all_shoots = false;
        lines.push(`${p.name} added to ${shoot.label}`);
      }
    } else {
      if (!e) throw refuse(`${p.name} isn't on this project's crew.`);
      const onThis = e.all_shoots || (e.shoots || []).includes(sid);
      if (!onThis) { lines.push(`${p.name} wasn't on ${shoot.label}`); continue; }
      const left = e.all_shoots ? others : (e.shoots || []).filter((x) => x !== sid);
      if (!left.length && args.off_project !== true) {
        throw refuse(`${p.name}'s only shoot is ${shoot.label}; taking them off it would put them on every shoot of the project. To take them off the project's crew altogether, say \`off_project: true\`. Nothing was written.`);
      }
      notionWork.push({ person: p.person, name: p.name, remove: sid, keep: e.all_shoots ? left : null, offProject: !left.length });
      if (!left.length) { next.splice(next.indexOf(e), 1); lines.push(`${p.name} taken off ${shoot.label} and off the project's crew`); }
      else { e.shoots = left; e.all_shoots = false; lines.push(`${p.name} taken off ${shoot.label}`); }
    }
  }

  // Notion first (a refusal there writes nothing on the record)
  if (notionWork.length) {
    let ctxN;
    try { ctxN = await crewRows(); } catch (err) {
      throw refuse(`Notion can't be reached (${oneLine(err && err.message).slice(0, 60)}), and who is on a shoot is written to Notion's Crew row. Nothing was written. Roles on this project can still be set (leave out \`add\`/\`remove\` for them).`);
    }
    try {
      for (const w of notionWork) {
        const page = await ctxN.n.get(`pages/${w.person}`);
        const props = {};
        const haveS = (await relationAll(ctxN.n, page, "Shoots")).map(bareId);
        let wantS = haveS;
        if (w.add) wantS = [...new Set([...haveS, w.add])];
        if (w.remove) wantS = (w.keep ? [...new Set([...haveS, ...w.keep])] : haveS).filter((x) => x !== w.remove);
        if (w.offProject) wantS = wantS.filter((x) => x !== w.remove);
        if (wantS.join(",") !== haveS.join(",")) props.Shoots = { relation: wantS.map((id) => ({ id })) };
        const haveP = (await relationAll(ctxN.n, page, "Projects")).map(bareId);
        if ((w.onProject || w.add) && !haveP.includes(cx.page)) props.Projects = { relation: [...haveP, cx.page].map((id) => ({ id })) };
        if (w.offProject) props.Projects = { relation: haveP.filter((x) => x !== cx.page).map((id) => ({ id })) };
        if (Object.keys(props).length) {
          await ctxN.n.patch(`pages/${w.person}`, { properties: props });
          const back = await ctxN.n.get(`pages/${w.person}`);
          const gotS = (await relationAll(ctxN.n, back, "Shoots")).map(bareId);
          if (props.Shoots && gotS.join(",") !== wantS.join(",")) throw new Error("Notion did not keep the change");
        }
        // someone new to the project: their entry, as the crew copy has it
        if (w.add && !next.some((x) => bareId(x.person) === w.person)) {
          const row = ctxN.all.find((c) => bareId(c.id) === w.person);
          next.push({ person: w.person, name: row ? row.name : w.name, roles: row && row.role ? row.role.split(",").map((x) => x.trim()).filter(Boolean).sort() : [], shoots: [w.add], all_shoots: false });
        }
      }
    } catch (err) {
      throw refuse(`Notion wouldn't take it (${oneLine(err && err.message).slice(0, 120)}). Check the shoot's crew with \`shoots\`.`);
    }
  }

  // roles on this project: the record's alone
  const held = factValue(cx.facts, "crew_roles");
  const here = isObject(held) ? { ...held } : {};
  let rolesChanged = false;
  for (const p of plan) {
    if (p.kind !== "add" || p.roles === null) continue;
    const e = next.find((x) => bareId(x.person) === p.person);
    if (!e) continue;
    const before = JSON.stringify(here[p.person] || []);
    if (p.roles.length) here[p.person] = p.roles; else delete here[p.person];
    if (JSON.stringify(here[p.person] || []) !== before) {
      rolesChanged = true;
      lines.push(p.roles.length ? `${p.name}'s role on this project: ${p.roles.join(", ")} (their Crew role in Notion is unchanged)` : `${p.name} is back on their usual Crew role`);
    }
  }
  for (const e of next) {
    const mine = rolesOf(here[bareId(e.person)] || []);
    if (mine.length) { e.roles = mine; e.roles_here = true; } else delete e.roles_here;
  }
  const same = JSON.stringify(next) === JSON.stringify(people);
  if (same && !rolesChanged) return `${lines.join("; ") || "Nothing to change"}. Nothing written.`;
  for (let tries = 0; tries < 4; tries++) {
    const record = await readRecord(cx.env, cx.key);
    const facts = (record && record.facts) || {};
    const changes = {};
    const nowPeople = factValue(facts, "crew");
    if (!same) changes.crew = { value: next.sort((x, y) => `${(x.name || "").toLowerCase()}${x.person}`.localeCompare(`${(y.name || "").toLowerCase()}${y.person}`)), base: (facts.crew && facts.crew.v) || 0 };
    if (rolesChanged) changes.crew_roles = { value: here, base: (facts.crew_roles && facts.crew_roles.v) || 0 };
    if (nowPeople === undefined && !Object.keys(changes).length) break;
    const got = await writeFacts(cx.env, cx.key, changes, BY);
    if (got.status === 200) return `${shoot.label}: ${lines.join("; ")}. Projects Console shows it now.`;
    if (got.status !== 409) throw refuse(`The record would not take it: ${got.problem}`);
  }
  throw refuse("The record kept changing. Try again.");
}

export { cleanName };
