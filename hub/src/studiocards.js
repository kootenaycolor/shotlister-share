/**
 * **Studio reads the card** (stage 5 step 4, piece A, 2026-10-14).
 *
 * One record per project, kept here. Studio (Mac and iPhone), the engine,
 * exports, the connector and the portal's renderer stop keeping their own copy
 * of what defines a project — title, director, producer, client, agency, icon
 * and colour, and the kind its Type implies — and read it from the record:
 * the **card**.
 *
 * The card is the record's words put the way a film shows them — the very
 * rule `filmfacts.js` used to copy them into films (`wantedFacts`, the Notion
 * icon's mark) — so a film shows exactly what it showed while the copies were
 * being made, without anything being written into it. The engine lays it over
 * the film in memory (`engine/src/card.rs`); the film's own words underneath
 * are what an older iPhone build, or anything reading the film alone, still
 * sees.
 *
 *   GET  /console/studio/cards              {on, at, cards: [card…]} — always answers
 *   GET  /console/studio/studiocards        the switch
 *   PUT  /console/studio/studiocards        {on, by}
 *   POST /console/studio/cards/look         {only?} — every film's facts today
 *                                           against its card; writes nothing
 *   POST /console/studio/open               {mac, page, id, action?} — Studio's
 *                                           "open the console on this project"
 *   POST /console/studio/open/take          {mac} — that Mac's console takes it
 *
 * **The switch** (`s/studio-cards.json`, off until thrown) decides:
 * - whether Studio, the phone and the connector lay the card on (the cards
 *   door answers `on`, and the shells read it);
 * - the server stops copying facts into films: the film-facts timer and the
 *   phone's `mirror_facts`/`mirror_director`/`mirror_mark` stand down;
 * - the portal's renderer lays the card's director, producer and mark over
 *   what the film says (`layCardOnFront`).
 * Off, everything behaves exactly as before.
 */

import { wantedFacts, markLookup, fetchIcon } from "./filmfacts.js";
import { creditsOf } from "./credits.js";
import { readIds, notionOf, studioOf, bare, ID, resolveProject } from "./projectid.js";
import { resolveModes, modesOn, isJob, loadStandards } from "./studiomodes.js";
import { resolveMods } from "./studiomods.js";
import { frameRatio as frameRatioOf } from "./studioframes.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/studio-cards.json";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function cardsOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setCards(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── the card ─────────────────────────────────────────────────────────────────

/** Kind follows Type (his answer, 2026-10-14): Commercial and Music Video are commercials. */
export function kindOfType(type) {
  const t = String(type || "").trim().toLowerCase();
  if (!t) return "";
  return t === "commercial" || t === "music video" ? "commercial" : "film";
}

const factText = (facts, k) => {
  const one = (facts || {})[k];
  return one && typeof one === "object" && typeof one.value === "string" && !one.waiting ? one.value.trim() : "";
};

/**
 * One record's card. `pair` is its mark (`{path, colour}` or `{}`), looked up
 * by `markLookup` — the film-facts rule. `aliases` the other ids it is known
 * by (its film's relay id, a minted project's Notion page).
 */
export function cardOf(key, record, pair = {}, aliases = []) {
  const facts = isObject(record.facts) ? record.facts : {};
  const hidden = Array.isArray(record.hidden) ? record.hidden.map(String) : [];
  const type = factText(facts, "type") || String(record.type || "");
  const relay = studioOf(record);
  const notion = notionOf(record, key);
  const drive = factText(facts, "drive_folder");
  return {
    id: key,
    notion,
    relay,
    aliases: [...new Set([relay, notion, ...aliases].filter((x) => x && x !== key))],
    name: String(record.name || factText(facts, "title") || ""),
    facts: wantedFacts(facts, hidden),
    mark: pair && pair.path ? { path: pair.path, colour: pair.colour } : null,
    type,
    kind: kindOfType(type),
    job: isJob(record),
    status: factText(facts, "status") || String(record.stage || ""),
    // The first shoot day, as the console's list says it (its readout's
    // `dates`); the fact's own range start when there is no readout.
    dates: String(record.dates || factText(facts, "shoot_dates").split("/")[0] || ""),
    drive_url: /^https:\/\/drive\.google\.com\//.test(drive) ? drive : "",
    notion_url: typeof record.notion === "string" ? record.notion : "",
    logline: hidden.includes("logline") ? "" : factText(facts, "logline"),
    credits: creditsOf(facts),
    hidden,
    updated: String(record.updated || ""),
    // The modes this project has on (studiomodes.js, step 4 piece B): its
    // Type's starting set plus its own changes. Studio follows them only while
    // the cards door says `modes: true`.
    modes: resolveModes(record).modes,
    // The mods this project has switched on (studiomods.js); none by default.
    mods: resolveMods(record),
  };
}

async function recordKeys(env) {
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
  return keys;
}

/**
 * Every project's card, in the bucket's order. `marks` is a `markLookup`
 * (pass one with a stand-in fetch for checks); `only` narrows to one id.
 */
export async function allCards(env, { marks = null, only = "" } = {}) {
  await loadStandards(env);
  const lookup = marks || markLookup(env, fetchIcon);
  const ids = await readIds(env);
  const back = {};
  for (const [other, key] of [...Object.entries(ids.alias), ...Object.entries(ids.notion)]) (back[key] ||= []).push(other);
  const want = bare(only);
  // The script's draft in use and any new one in Drive (scriptdrive.js, step
  // 4 piece C): only while its own switch is on, from what was last seen.
  const sd = await import("./scriptdrive.js");
  const scripts = (await sd.scriptDriveOn(env)).on ? (await sd.readState(env)).projects : null;
  // The project's shoots (studioshoots.js, step 4 piece D): only while its
  // own switch is on, from his Shoots database as last read.
  const sh = await import("./studioshoots.js");
  const shootRows = (await sh.shootsOn(env)).on ? await sh.shootRows(env) : null;
  const shootTools = shootRows ? await sh.shootTools() : null;
  // The spec sheet's frames and sensors (studioframes.js, step 4 piece E):
  // only while its own switch is on.
  const fr = await import("./studioframes.js");
  const framesSwitch = (await fr.framesOn(env)).on;
  const cards = [];
  for (const key of await recordKeys(env)) {
    const record = await readJson(env, `r/${key}/record.json`);
    if (!isObject(record)) continue;
    const pair = await lookup.of(record.facts || {});
    const card = cardOf(key, record, pair, back[key] || []);
    if (scripts && scripts[key]) card.script = sd.cardScript(scripts[key]);
    if (shootRows) card.shoots = sh.cardShoots(shootRows, card, shootTools);
    if (want && card.id !== want && !card.aliases.includes(want)) continue;
    if (framesSwitch) fr.laySheet(card, record);
    cards.push(card);
  }
  await lookup.save();
  return cards;
}

/** The card for one id (its own, its Notion page, or its film's relay id), or null. */
export async function cardFor(env, id, { marks = null } = {}) {
  await loadStandards(env);
  const got = await allCards(env, { marks, only: id });
  return got[0] || null;
}

/**
 * **The card for a film being drawn, when the switch is on** — for the
 * portal's renderer and the connector, which hold a film's relay id. Cheap:
 * the switch, the ID map and one record (no listing). Null when the switch is
 * off, the film belongs to no record, or anything fails (the film's own words
 * then show, as before).
 */
export async function liveCardFor(env, filmId, { marks = null } = {}) {
  await loadStandards(env);
  try {
    if (!(await cardsOn(env)).on) return null;
    const found = await resolveProject(env, filmId);
    if (!found.key || !isObject(found.record)) return null;
    const lookup = marks || markLookup(env, fetchIcon);
    const pair = await lookup.of(found.record.facts || {});
    await lookup.save();
    const card = cardOf(found.key, found.record, pair);
    // The project's shoots too, while their own switch is on (piece D).
    const sh = await import("./studioshoots.js");
    if ((await sh.shootsOn(env)).on) card.shoots = sh.cardShoots(await sh.shootRows(env), card, await sh.shootTools());
    // And the spec sheet's frames and sensors, while theirs is (piece E).
    const fr = await import("./studioframes.js");
    if ((await fr.framesOn(env)).on) fr.laySheet(card, found.record);
    return card;
  } catch {
    return null;
  }
}

/** What the engine takes (`card` in ffi, `set_card` in mcpweb). */
export function engineCard(card) {
  if (!card) return "";
  return JSON.stringify({ facts: card.facts, mark: card.mark, kind: card.kind, type: card.type, ...(Array.isArray(card.shoots) ? { shoots: card.shoots } : {}), ...(isObject(card.sheet) ? { sheet: card.sheet } : {}) });
}

// ── the portal's renderer ────────────────────────────────────────────────────

/**
 * The card's words over a portal card (`frontOf`): the director and producer
 * lines and the mark. Only the facts the card holds; the rest is the film's.
 */
export function layCardOnFront(front, card, live = null) {
  if (!card) return front;
  const out = { ...front };
  // **The ratio line follows the frame Studio picked** (piece E), off the
  // card's sheet, so a frame changed on the sheet shows at once. `live` is
  // the film's half (its pick, `frame`, and its own `ratio`).
  if (isObject(card.sheet) && live) out.ratio = frameRatioOf(card.sheet, live.frame, live.ratio);
  if (typeof card.facts.director === "string") out.director = card.facts.director;
  if (typeof card.facts.producer === "string") out.producer = card.facts.producer;
  if (card.mark && card.mark.path) out.mark = { path: card.mark.path, colour: card.mark.colour };
  return out;
}

// ── the look ─────────────────────────────────────────────────────────────────

/**
 * Every film's facts as it shows them today, against its card: what Studio
 * would show differently once the card is laid on. `readFilm(env, relay, ctx)`
 * answers the engine's view `project` block (displayTitle, director,
 * producer, client, agency, kind, markPath, markColour, markSource). Writes
 * nothing.
 */
export async function cardsLook(env, ctx, readFilm, { only = "", marks = null } = {}) {
  const cards = await allCards(env, { marks, only });
  const rows = [];
  for (const card of cards) {
    if (!card.relay) { rows.push({ id: card.id, name: card.name, film: false }); continue; }
    let p;
    try { p = await readFilm(env, card.relay, ctx); } catch (e) {
      rows.push({ id: card.id, name: card.name, relay: card.relay, trouble: String((e && e.message) || e).slice(0, 200) });
      continue;
    }
    rows.push({ id: card.id, name: card.name, relay: card.relay, ...compareFilm(card, p) });
  }
  const differ = rows.filter((r) => r.differs && r.differs.length);
  return { at: new Date().toISOString(), cards: cards.length, films: rows.filter((r) => r.relay).length, same: rows.filter((r) => r.differs && !r.differs.length).length, differ: differ.length, rows };
}

/** The fields where a film today shows something other than its card would. */
export function compareFilm(card, p) {
  const shown = {
    title: String(p.displayTitle || p.title || ""),
    director: String(p.director || ""),
    producer: String(p.producer || ""),
    client: String(p.client || ""),
    agency: String(p.agency || ""),
  };
  const differs = [];
  const detail = {};
  for (const k of Object.keys(shown)) {
    if (!(k in card.facts)) continue;
    if (shown[k].trim() !== card.facts[k]) { differs.push(k); detail[k] = { film: shown[k], card: card.facts[k] }; }
  }
  const hand = String(p.markSource || "") === "hand";
  if (card.mark && !hand) {
    const film = { path: String(p.markPath || ""), colour: String(p.markColour || "").toUpperCase() };
    if (film.path !== card.mark.path || film.colour !== card.mark.colour) { differs.push("mark"); detail.mark = { film: film.colour, card: card.mark.colour }; }
  }
  if (card.kind && String(p.kind || "film") !== card.kind) { differs.push("kind"); detail.kind = { film: String(p.kind || "film"), card: card.kind }; }
  return { differs, ...(differs.length ? { detail } : {}) };
}

// ── opening the console ──────────────────────────────────────────────────────

/**
 * **Studio opens the console through the server**, not a file beside the
 * console. The request is kept per Mac (the console's own `gethostname()`),
 * newest wins, for two minutes; that Mac's console takes it when it comes to
 * the front (`studioopen.py` in projects-console). `action` is `archive` or
 * `delete`: the project's own Archive or Delete, previewed and confirmed in
 * the console.
 */
export const OPEN_KEY = "s/open-requests.json";
const OPEN_KEEP_MS = 2 * 60 * 1000;
const ACTIONS = new Set(["", "archive", "delete"]);
const macOf = (v) => String(v || "").trim().slice(0, 120);

export async function leaveOpen(env, said, now = Date.now()) {
  const mac = macOf(said && said.mac);
  const page = bare(said && said.page);
  const id = bare(said && said.id);
  const action = String((said && said.action) || "");
  if (!mac) return { ok: false, status: 400, problem: "Say which Mac." };
  if (!/^[0-9a-f]{8,64}$/.test(page) && !/^[0-9a-f]{8,64}$/.test(id)) return { ok: false, status: 400, problem: "Say which project." };
  if (!ACTIONS.has(action)) return { ok: false, status: 400, problem: "Archive or delete, or nothing." };
  const held = (await readJson(env, OPEN_KEY)) || {};
  const kept = {};
  for (const [m, r] of Object.entries(held)) if (r && now - Date.parse(r.at || 0) < OPEN_KEEP_MS) kept[m] = r;
  kept[mac] = { type: "project", page, id, ...(action ? { action } : {}), at: new Date(now).toISOString(), by: String((said && said.by) || "").slice(0, 40) };
  await env.BUCKET.put(OPEN_KEY, JSON.stringify(kept), { httpMetadata: { contentType: "application/json" } });
  return { ok: true, request: kept[mac] };
}

export async function takeOpen(env, said, now = Date.now()) {
  const mac = macOf(said && said.mac);
  if (!mac) return { ok: false, status: 400, problem: "Say which Mac." };
  const held = (await readJson(env, OPEN_KEY)) || {};
  const mine = held[mac];
  if (!mine) return { ok: true, request: null };
  delete held[mac];
  await env.BUCKET.put(OPEN_KEY, JSON.stringify(held), { httpMetadata: { contentType: "application/json" } });
  return { ok: true, request: now - Date.parse(mine.at || 0) < OPEN_KEEP_MS ? mine : null };
}

// ── the door ─────────────────────────────────────────────────────────────────

export async function cardsDoor(env, rest, method, read, ctx, { readFilm } = {}) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest[0] === "studiocards" && rest.length === 1) {
    if (method === "GET") return reply(await cardsOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said;
    try { said = await read(); } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    return reply(await setCards(env, said));
  }
  if (rest[0] === "open" && (rest.length === 1 || (rest.length === 2 && rest[1] === "take"))) {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said;
    try { said = await read(); } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    const got = rest.length === 1 ? await leaveOpen(env, said) : await takeOpen(env, said);
    return reply(got, got.status || 200);
  }
  if (rest[0] !== "cards") return null;
  if (rest.length === 1) {
    if (method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    const { scriptDriveOn } = await import("./scriptdrive.js");
    const { shootsOn } = await import("./studioshoots.js");
    const { framesOn } = await import("./studioframes.js");
    const [sw, modes, script, shoots, frames, cards] = await Promise.all([cardsOn(env), modesOn(env), scriptDriveOn(env), shootsOn(env), framesOn(env), allCards(env)]);
    return reply({ on: sw.on, modes: modes.on, script: script.on, shoots: shoots.on, frames: frames.on, at: new Date().toISOString(), cards });
  }
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "POST") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said = {};
    try { said = (await read()) || {}; } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    const reader = readFilm || (await import("./studiocardsfilm.js")).filmProject;
    return reply(await cardsLook(env, ctx, reader, { only: String(said.only || "").slice(0, 64) }));
  }
  return null;
}
