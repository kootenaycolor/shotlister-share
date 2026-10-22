/**
 * **Customize Record, answered by the server** (2026-10-11, Projects Console
 * without the Mac, stage 3 step 5). The Mac's `backend.set_project_layout`
 * with `recordlayout.py`, ported rule for rule: which facts and credits a
 * project shows, kept on the record as the `layout` fact (only where it
 * differs from its Type's standard) and the `story` fact in step for older
 * builds. Hiding never deletes.
 *
 * The rules that read a layout are the Notion link's already
 * (`resolveLayout` in notionlink.js, the same port of `recordlayout.resolve`);
 * what is here is the rest of the ask: `explicit_after`, `story_after`,
 * `hidden`, the three tries against a record that moves, and the readout's
 * `hidden` line that the portal, the film mirror and the phone read
 * (`record.patch_readout`).
 *
 * **What it writes.** Two facts, through `writeFacts` (compare-and-set, one
 * version each, kept in the history), and the readout's `hidden` line. Never
 * Notion: the Notion link reads the layout from the record on its minute.
 *
 * **Not live by being deployed.** A switch, `s/record-layout.json` (`on`),
 * off until thrown (`GET/PUT /console/studio/layout`). While it is off the
 * server still answers every ask that writes nothing — opening Customize
 * Record on a project whose layout is already tidy — and hands anything that
 * would write to the Mac (`Handoff`), so the two never both write. A look
 * (`POST /console/studio/layout/run`, `dry` by default) says what it would
 * write, for one project or every one.
 *
 * Where it differs from the Mac, on purpose:
 * - the Notion row is read live (the Mac reads its own list, a few minutes
 *   old); the record's facts are read from the bucket, never a kept copy;
 * - nothing is queued offline: the server is where the record lives;
 * - the history says the change was the server's (`by: "server"`), not the
 *   Mac's name;
 * - the readout's `hidden` line is written compare-and-set at once, not
 *   re-sent whole a moment later, so a readout change landing in between is
 *   not lost;
 * - the film is not told here: the films' minute (filmfacts.js) sees the
 *   new `hidden` and tells it, when the server owns the films.
 */

import { resolveLayout, truthy } from "./notionlink.js";
import { ROLES, MIRRORS } from "./credits.js";
import { projectRow, bareId, Handoff } from "./cloud.js";

/** The facts a project may show or hide, in the record's order — recordlayout.FIELDS. */
export const FIELD_KEYS = ["logline", "synopsis", "directors_note", "visual_language", "length",
  "client", "agency", "shoot_dates", "website"];

export const SWITCH_KEY = "s/record-layout.json";
const TEMPLATES_KEY = "s/record-templates.json";
const LAST_KEY = "s/record-layout-last.json";
export const BY = "server";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

/** A fact's value, or null — recordlayout._fact_value. */
const factValue = (facts, field) => {
  const one = (facts || {})[field];
  return isObject(one) ? (one.value === undefined ? null : one.value) : null;
};

/** `int(x.get("v") or 0)` */
const vOf = (one) => (isObject(one) ? Number(one.v) || 0 : 0);

/** Python's `==` on JSON values: order of keys does not count. */
export function sameValue(a, b) {
  if (a === b) return true;
  if (a === null || b === null || a === undefined || b === undefined) return (a ?? null) === (b ?? null);
  if (typeof a === "boolean" || typeof b === "boolean" || typeof a === "number" || typeof b === "number") {
    // True == 1 in Python; JSON brings back only these
    return (typeof a === "boolean" ? Number(a) : a) === (typeof b === "boolean" ? Number(b) : b);
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => sameValue(x, b[i]));
  }
  if (isObject(a) && isObject(b)) {
    const ka = Object.keys(a), kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => Object.prototype.hasOwnProperty.call(b, k) && sameValue(a[k], b[k]));
  }
  return false;
}

// ── recordlayout.py, the parts the Notion link did not need ─────────────────

/**
 * The `layout` value that makes this project show `want` ({fields: {key:
 * bool}, credits: {role: bool}}, either part may be partial — the rest stays
 * as it is now): only where it differs from the Type's standard —
 * recordlayout.explicit_after. A choice is read the way Python's `bool()`
 * reads it.
 */
export function layoutAfter(ptype, saved, want, facts = null) {
  const now = resolveLayout(facts || {}, ptype, saved);
  const tpl = now.template;
  const asked = isObject(want) ? want : {};
  const fields = { ...now.fields };
  for (const [k, v] of Object.entries(isObject(asked.fields) ? asked.fields : {})) {
    if (FIELD_KEYS.includes(k)) fields[k] = truthy(v);
  }
  const roles = { ...now.credits };
  for (const [k, v] of Object.entries(isObject(asked.credits) ? asked.credits : {})) {
    if (ROLES.includes(k)) roles[k] = truthy(v);
  }
  return {
    fields: Object.fromEntries(Object.entries(fields).filter(([k, v]) => v !== tpl.fields.includes(k))),
    credits: Object.fromEntries(Object.entries(roles).filter(([r, v]) => v !== tpl.credits.includes(r))),
  };
}

/**
 * The `story` fact older builds read, kept in step with a new layout: "on"
 * or "off" when it must be written, null when it already says that (or was
 * never set and the standard already says it) — recordlayout.story_after.
 */
export function storyAfter(facts, layoutValue, ptype = "", saved = null) {
  const t = resolveLayout(facts || {}, ptype, saved).type;
  const probe = { ...(facts || {}), layout: { value: layoutValue } };
  const r = resolveLayout(probe, t, saved);
  const on = r.fields.logline || r.fields.synopsis;
  const have = factValue(facts, "story");
  if (have === "on" || have === "off") return (have === "on") === on ? null : (on ? "on" : "off");
  const oldDefault = t.toUpperCase().toLowerCase() !== "commercial";
  return on === oldDefault ? null : (on ? "on" : "off");
}

/**
 * Everything this project hides, as the readout says it: field keys, and
 * each hidden credit as its line fact where it has one
 * (`executive_producer`) or `credit:<Role>` — recordlayout.hidden.
 */
export function hiddenOf(resolved) {
  const out = Object.entries(resolved.fields).filter(([, on]) => !on).map(([k]) => k);
  for (const [role, on] of Object.entries(resolved.credits)) if (!on) out.push(MIRRORS[role] || `credit:${role}`);
  return out;
}

/**
 * What one ask would write — the body of `set_project_layout`'s loop:
 * {value, changes: {field: {value, base}}}. `changes` is {} when the record
 * already says it.
 */
export function layoutPlan(facts, ptype, saved, want, reset) {
  const now = facts || {};
  const value = reset ? { fields: {}, credits: {} } : layoutAfter(ptype, saved, truthy(want) ? want : {}, now);
  const have = isObject(now.layout) ? now.layout : {};
  const changes = {};
  if (!sameValue(have.value === undefined ? null : have.value, value)) changes.layout = { value, base: vOf(have) };
  const story = storyAfter(now, value, ptype, saved);
  if (story !== null) changes.story = { value: story, base: vOf(now.story) };
  return { value, changes };
}

/**
 * The Type the Mac reads a project by: the record's `type` fact when it holds
 * words (or ""), else Notion's Type — the console's list with the record laid
 * over (`record.overlay_rows`).
 */
export function projectType(row, facts) {
  const typed = factValue(facts, "type");
  if (typeof typed === "string") return typed;
  return ((((row || {}).properties || {}).Type || {}).select || {}).name || "";
}

// ── the bucket ───────────────────────────────────────────────────────────────

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

/** The record, its facts and its etag — null when the project has none. */
async function recordAt(env, page) {
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try { return { record: await got.json(), etag: got.etag }; } catch { return null; }
}

/** What Python's `for x in value` walks: a list's items, a string's letters,
 * a dict's keys; nothing for the rest. */
const walk = (x) => (Array.isArray(x) ? x : typeof x === "string" ? Array.from(x) : isObject(x) ? Object.keys(x) : []);

/**
 * His standards, each made the shape the Mac reads them in
 * (recordlayout._tidy_template): one that is not a {fields, credits} is no
 * standard (the Type's default stands), and only known fields and credits
 * are kept, in the record's order. The console only ever saves them tidy;
 * this is so a stray one is read as the Mac reads it, not thrown on.
 */
const MODE_KEYS = ["shot_list", "locations", "references", "schedule", "diagram"];
export function tidyTemplates(saved) {
  const out = {};
  for (const [t, raw] of Object.entries(isObject(saved) ? saved : {})) {
    if (!isObject(raw)) continue;
    const fields = walk(raw.fields), roles = walk(raw.credits);
    out[t] = { fields: FIELD_KEYS.filter((f) => fields.includes(f)), credits: ROLES.filter((r) => roles.includes(r)) };
    // The Type's starting Studio modes (Settings › New Projects), kept when he set them.
    if (Array.isArray(raw.modes)) out[t].modes = MODE_KEYS.filter((m) => raw.modes.includes(m));
  }
  return out;
}

/** His Settings › Record standards, as the console last sent them. */
export async function savedTemplates(env) {
  return tidyTemplates(await readJson(env, TEMPLATES_KEY));
}

/** Whether the server writes Customize Record: off until `{on: true}`. */
export async function layoutOn(env) {
  const said = await readJson(env, SWITCH_KEY);
  return Boolean(said && said.on === true);
}

/**
 * The readout's `hidden` line, said again now — `record.patch_readout`. The
 * Type is the project's (`ptype`), else the readout's own. Compare-and-set on
 * the record, so a write landing in between is read again, not lost. Answers
 * the line written, or null when there is no record.
 */
export async function patchHidden(env, page, ptype, saved) {
  for (let i = 0; i < 3; i++) {
    const got = await recordAt(env, page);
    if (!got) return null;
    const record = got.record || {};
    const hidden = hiddenOf(resolveLayout(record.facts || {}, ptype || record.type || "", saved));
    const next = { ...record, hidden, updated: new Date().toISOString() };
    const put = await env.BUCKET.put(`r/${page}/record.json`, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: { etagMatches: got.etag },
    });
    if (put) return hidden;
  }
  throw new Error("the record kept changing while its hidden line was being written");
}

// ── the ask ──────────────────────────────────────────────────────────────────

/**
 * backend.set_project_layout(name, want=None, reset=False) — the phone's
 * Customize Record. `want` {fields: {key: bool}, credits: {role: bool}}
 * (only what changes), or `reset` back to the Type's standard. Answers
 * {ok, facts, layout} · {ok: false, why}, as the Mac does. Throws `Handoff`
 * when it would write and the switch is off.
 *
 * `deps` stands in for the bucket's writer in the checks: `writeFacts`
 * (facts.js) and `on` (the switch).
 */
export async function setProjectLayout(env, n, args, deps = {}) {
  const [name, want, reset] = Array.isArray(args) ? args : [];
  const row = await projectRow(n, name);
  if (!row) return { ok: false, why: "This project has no Notion row." };
  const page = bareId(row.id);
  const saved = await savedTemplates(env);
  for (let i = 0; i < 3; i++) {
    const got = await recordAt(env, page);
    const now = (got && isObject(got.record.facts) && got.record.facts) || {};
    const ptype = projectType(row, now);
    const { changes } = layoutPlan(now, ptype, saved, want, truthy(reset));
    if (!Object.keys(changes).length) return { ok: true, facts: now, layout: resolveLayout(now, ptype, saved) };
    // The hub's facts door says this for a project with no record yet, and
    // writes nothing: the Mac's answer, whoever answers.
    if (!got) return { ok: false, why: "No record for that project yet." };
    const on = deps.on !== undefined ? deps.on : await layoutOn(env);
    if (!on) throw new Handoff("the Mac customizes records until the switch is on");
    const write = deps.writeFacts || (await import("./facts.js")).writeFacts;
    const wrote = await write(env, page, changes, BY);
    if (wrote.status === 409 && wrote.conflicts) continue;
    if (wrote.status !== 200) return { ok: false, why: wrote.problem || "The record could not be written." };
    const facts = wrote.facts || {};
    try {
      await patchHidden(env, page, projectType(row, facts), saved);
    } catch (e) {
      // The facts are written; the readout catches up at the Mac's next look.
      console.error("layout: hidden line not written:", String((e && e.message) || e));
    }
    return { ok: true, facts, layout: resolveLayout(facts, projectType(row, facts), saved) };
  }
  return { ok: false, why: "The record kept changing. Try again." };
}

// ── the look ─────────────────────────────────────────────────────────────────

/** Every Projects row, by bare page id — one paged read. */
async function projectRows(n) {
  const out = new Map();
  let cursor;
  do {
    const got = await n.post("data_sources/feedface-0000-4000-8000-000000000001/query",
      { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    for (const p of got.results || []) out.set(bareId(p.id), p);
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

async function recordPages(env) {
  const pages = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const page = p.split("/")[1];
      if (/^[0-9a-f]{32}$/.test(page)) pages.push(page);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return pages;
}

/** What one project's ask would do, said plainly, writing nothing. */
function lookAt(record, row, saved, want, reset) {
  const facts = (record && isObject(record.facts) && record.facts) || {};
  const ptype = projectType(row, facts);
  const { changes } = layoutPlan(facts, ptype, saved, want, reset);
  const after = { ...facts };
  for (const [field, c] of Object.entries(changes)) after[field] = { ...(facts[field] || {}), value: c.value, v: c.base + 1 };
  const shown = (r) => ({
    fields: FIELD_KEYS.filter((k) => r.fields[k]),
    credits: ROLES.filter((k) => r.credits[k]),
  });
  const before = resolveLayout(facts, ptype, saved);
  const then = resolveLayout(after, ptype, saved);
  return {
    name: (record && record.name) || "",
    type: before.type,
    writes: Object.keys(changes).length ? Object.fromEntries(Object.entries(changes)
      .map(([field, c]) => [field, { from: factValue(facts, field), to: c.value, base: c.base }])) : null,
    shows: shown(before),
    ...(Object.keys(changes).length ? { shows_after: shown(then) } : {}),
    hidden_now: Array.isArray(record && record.hidden) ? record.hidden : null,
    hidden_after: hiddenOf(then),
  };
}

/**
 * A look now: what Customize Record would write. With `name`, for that
 * project and the change asked (`want`, `reset`); without, for every record,
 * as if each were opened (an empty change), which is when the Mac tidies a
 * layout. `dry: false` (one project, the switch on) does it for real, as the
 * phone's ask does. Kept at `s/record-layout-last.json`.
 */
export async function layoutLook(env, n, { name = "", want = {}, reset = false, dry = true } = {}) {
  const at = new Date().toISOString();
  const saved = await savedTemplates(env);
  if (name) {
    if (!dry) {
      const result = await setProjectLayout(env, n, [name, want, reset]);
      return { at, dry: false, name, result };
    }
    const row = await projectRow(n, name);
    if (!row) return { at, dry: true, name, why: "This project has no Notion row." };
    const got = await recordAt(env, bareId(row.id));
    return { at, dry: true, on: await layoutOn(env), page: bareId(row.id),
      ...lookAt(got && got.record, row, saved, want, Boolean(reset)), ...(got ? {} : { why: "No record for that project yet." }) };
  }
  const rows = await projectRows(n);
  const projects = [];
  for (const page of await recordPages(env)) {
    const got = await recordAt(env, page);
    if (!got) continue;
    const row = rows.get(page);
    projects.push({ page, ...(row ? {} : { no_row: true }), ...lookAt(got.record, row || {}, saved, {}, false) });
  }
  const writing = projects.filter((p) => p.writes && !p.no_row);
  const out = { at, dry: true, on: await layoutOn(env), looked: projects.length,
    would_write: writing.map((p) => p.name), projects };
  await env.BUCKET.put(LAST_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}
