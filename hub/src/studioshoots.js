/**
 * **Shoots in Studio** (stage 5 step 4, piece D, 2026-10-15).
 *
 * His approved design (the one shoot picker, 2026-10-14): a project's shoots
 * are the project's, not headings in the shot list. The card Studio reads
 * (`studiocards.js`) gains the project's **shoots** — the very list the
 * console's picker draws (`onelist.js`: his Shoots database read by
 * `shootRow`, put in order and given its words and Wrapped / Next / Upcoming
 * by `readout`) — and the engine (`engine/src/shoots.rs`) lets each scene and
 * schedule day belong to one of them, with a day's date following its
 * shoot's. Studio's picker narrows every mode to one shoot.
 *
 * Behind one switch, `s/studio-shoots.json`, off until thrown. Off, the cards
 * carry no shoots and Studio is exactly what it was (no picker, sections as
 * before). On, every card carries `shoots` (real Shoots rows only; the
 * project's own Shoot Dates never count as a shoot, as on the console).
 *
 * His Shoots database is read at most every ten minutes and kept
 * (`s/studio-shoots-rows.json`); a Notion hiccup keeps the last good read.
 *
 *   GET  /console/studio/studioshoots         the switch {on, at, by}
 *   PUT  /console/studio/studioshoots         {on, by}
 *   POST /console/studio/studioshoots/look    {only?} — per project: its shoots
 *                                             and, for a project with a film,
 *                                             what Studio would show under each
 *                                             (scenes and days, how many named
 *                                             their shoot themselves). Writes nothing.
 */

import { bare } from "./projectid.js";
import { refuseOff } from "./fixedon.js";

/**
 * The console's own rules for a Shoots row and its words, loaded only when
 * the switch is on: `onelist.js` and `projectpage.js` pull in the record's
 * layout, which a check of the cards with the switch off need not load.
 */
export async function shootTools() {
  const [ol, pp] = await Promise.all([import("./onelist.js"), import("./projectpage.js")]);
  return { SOURCES: ol.SOURCES, shootsByProject: ol.shootsByProject, readout: pp.readout, today: pp.today };
}

export const SWITCH_KEY = "s/studio-shoots.json";
export const ROWS_KEY = "s/studio-shoots-rows.json";
const KEEP_MS = 10 * 60 * 1000;

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function shootsOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setShoots(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── his Shoots database, read and kept ───────────────────────────────────────

async function queryAll(n, source) {
  const out = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${source}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    out.push(...(got.results || []));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/**
 * Every Shoots row by its project's bare page, as the console's list reads
 * them (`shootsByProject`). Kept ten minutes; `notion` is a client (or a
 * stand-in for checks), made from `NOTION_TOKEN` when not given. A failed
 * read keeps the last good one; none at all is `{}`.
 */
export async function shootRows(env, { notion = null, force = false, now = Date.now() } = {}) {
  const kept = await readJson(env, ROWS_KEY);
  if (!force && isObject(kept) && isObject(kept.rows) && now - Date.parse(kept.at || 0) < KEEP_MS) return kept.rows;
  try {
    let n = notion;
    if (!n) {
      if (!env.NOTION_TOKEN) return (kept && kept.rows) || {};
      const { notionOf } = await import("./cloud.js");
      n = notionOf(env);
    }
    const { SOURCES, shootsByProject } = await shootTools();
    const rows = shootsByProject(await queryAll(n, SOURCES.shoots));
    await env.BUCKET.put(ROWS_KEY, JSON.stringify({ at: new Date(now).toISOString(), rows }), { httpMetadata: { contentType: "application/json" } });
    return rows;
  } catch {
    return (kept && kept.rows) || {};
  }
}

/**
 * **A card's shoots**: the project's Shoots rows as the console's picker
 * says them — first to last, each with its words and state — leaving out
 * the project's own Shoot Dates (never a shoot of its own). `card` is the
 * card being made (its `type`, `status`, `dates`).
 */
export function cardShoots(rows, card, tools, now = null) {
  const key = bare(card.notion || card.id);
  const mine = (rows && rows[key]) || [];
  if (!mine.length || !tools) return [];
  const project = { type: card.type || "", status: card.status || "", dates: card.dates || "" };
  let read;
  try { read = tools.readout(mine, project, now || tools.today()); } catch { return []; }
  return read.filter((s) => !s.from_project).map((s) => ({
    id: bare(s.id),
    label: s.label || s.kind || "",
    kind: s.kind || "",
    name: s.name || "",
    n: s.n == null ? null : s.n,
    start: s.start || "",
    end: s.end || "",
    when: s.when || "",
    state: s.state || "",
  }));
}

/** Lay the shoots on a list of cards (in place); `rows` from `shootRows`. */
export async function layShoots(cards, rows, now = null) {
  const tools = await shootTools();
  for (const card of cards) card.shoots = cardShoots(rows, card, tools, now);
  return cards;
}

// ── the look ─────────────────────────────────────────────────────────────────

/**
 * Per project: its shoots as Studio would list them, whether the picker
 * shows (two or more), and for a film what each shoot would hold.
 * `readView(env, relay, ctx, card)` answers the engine's view with the card
 * laid on (`studioshootsfilm.js`). Writes nothing.
 */
export async function shootsLook(env, ctx, readView, { only = "", notion = null, cards = null } = {}) {
  const { allCards } = await import("./studiocards.js");
  const list = cards || await allCards(env, { only });
  const rows = await shootRows(env, { notion });
  await layShoots(list, rows);
  const out = [];
  for (const card of list) {
    const row = { id: card.id, name: card.name, picker: card.shoots.length >= 2,
      shoots: card.shoots.map((s) => ({ id: s.id, label: s.label, kind: s.kind, when: s.when, state: s.state })) };
    if (card.relay && card.shoots.length && readView) {
      try {
        const v = await readView(env, card.relay, ctx, card);
        const scenes = Array.isArray(v.scenes) ? v.scenes : [];
        const days = Array.isArray(v.days) ? v.days : [];
        for (const s of row.shoots) {
          const mine = scenes.filter((x) => x.shoot === s.id);
          s.scenes = mine.length;
          s.ownScenes = mine.filter((x) => x.shootOwn).length;
          s.days = days.filter((d) => d.shoot === s.id).map((d) => `${d.label} ${d.date}`.trim());
        }
        row.scenes = scenes.length;
      } catch (e) {
        row.trouble = String((e && e.message) || e).slice(0, 200);
      }
    }
    out.push(row);
  }
  return { at: new Date().toISOString(), projects: out.length, pickers: out.filter((r) => r.picker).length, rows: out };
}

// ── the door ─────────────────────────────────────────────────────────────────

export async function shootsDoor(env, rest, method, read, ctx, { readView, notion } = {}) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest[0] !== "studioshoots") return null;
  if (rest.length === 1) {
    if (method === "GET") return reply(await shootsOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said;
    try { said = await read(); } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    return reply(await setShoots(env, said));
  }
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "POST" && method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said = {};
    if (method === "POST") {
      try { said = (await read()) || {}; } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    }
    const reader = readView || (await import("./studioshootsfilm.js")).filmView;
    return reply(await shootsLook(env, ctx, reader, { only: String(said.only || "").slice(0, 64), notion }));
  }
  return null;
}
