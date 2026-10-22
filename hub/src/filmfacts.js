/**
 * **The project record's facts, into the Shotlister film — from the server**
 * (2026-10-11, Projects Console without the Mac, stage 3, step 1). Rule for
 * rule the Mac's `projects-console/filmfacts.py`: a film's shown name,
 * director, producer, client and agency come from the project record, the way
 * its icon and colour come from the console.
 *
 * The Mac asked Shotlister's own command-line door (`--recordfacts`). Here the
 * door is `mirror_record` in the film engine (`mcpweb/src/lib.rs`, run through
 * `mirrorRecord` in `filmdoor.js`): the same engine, the same `take_record_facts`,
 * the same rules — five fields and the source beside them, nothing else; the
 * words already there are not written again; no undo step. The change is kept
 * as a log of the device `hub/record-mirror`, which the Mac and the phone take
 * in like any other.
 *
 * Only a film carrying this project's Notion page id is ever written (the
 * door checks the film's own `console_page`). A film held to its project by a
 * matching title alone is a guess, and a guess does not get to write.
 *
 * **The film's icon and colour** (the Mac's `mirror_mark`, stage 3 step 2b)
 * ride on the same door and the same look: the record's icon fact is a Notion
 * icon's address; its outline and fill become the film's mark, unless he set
 * the mark by hand (the engine never writes over his hand) and never clearing
 * a mark the record has no icon for. Its own switch (`s/film-mark.json`, off
 * until he says), so it can be looked at (dry) before it writes.
 *
 * **When it runs:** on the portal's minute, for a record whose five words
 * changed since the last look (or whose last try failed); and every tenth
 * minute for all of them, which catches a film that was never told. On the
 * phone's ask (`mirror_facts`, `mirror_director`) at once. Never while the
 * Mac is the owner (`/console/studio/owner/films`).
 */

import { creditsOf, creditLine, peopleIn } from "./credits.js";
import { iconParts } from "./notionlink.js";
import { markFromSvg } from "./notionmark.js";
import { hubOwner } from "./fixedon.js";

/** The facts the record gives a film, in the order Project Settings shows them. */
export const FIELDS = ["title", "director", "producer", "client", "agency"];

const STATE_KEY = "s/filmfacts.json";
const LAST_KEY = "s/filmfacts-last.json";
const SWEEP_EVERY_MINUTES = 10;
const MARK_SWITCH = "s/film-mark.json";
const MARK_PAIRS = "s/film-mark-pairs.json";
/** Studio reads the card (studiocards.js `SWITCH_KEY`): read here directly, not imported, to keep the two files free of a cycle. */
const CARDS_SWITCH = "s/studio-cards.json";

/**
 * **Whether films are read from the card instead** (stage 5 step 4, piece A).
 * While the switch is on, nothing copies facts into a film any more: every
 * shell lays the card over the film it shows.
 */
export async function cardsStandDown(env) {
  const said = await readJson(env, CARDS_SWITCH);
  return Boolean(said && said.on === true);
}

const held = (one) => one && typeof one === "object" && typeof one.value === "string";

/**
 * {fact: words} for each of the five the record holds as text — filmfacts.wanted.
 * A fact the record has never held is left out: the film keeps its own word.
 * The director and producer are the credit's whole line ("Ivy Sterling &
 * Robin Vale Arden"), from the credits list. A field this project
 * hides goes as "": the film leaves it off, and the record keeps the words.
 * An edit still waiting on a Mac to go up (`waiting`) is not the record's yet.
 */
export function wantedFacts(facts, hidden = []) {
  const confirmed = {};
  for (const [k, v] of Object.entries(facts || {})) {
    if (v && typeof v === "object" && v.waiting) continue;
    confirmed[k] = v;
  }
  const off = new Set(hidden || []);
  const out = {};
  if (held(confirmed.title)) out.title = confirmed.title.value.trim();
  const listed = creditsOf(confirmed);
  for (const [field, role] of [["director", "Director"], ["producer", "Producer"]]) {
    if (held(confirmed[field])) out[field] = off.has(field) ? "" : creditLine(peopleIn(listed, role));
  }
  for (const field of ["client", "agency"]) {
    if (held(confirmed[field])) out[field] = off.has(field) ? "" : confirmed[field].value.trim();
  }
  return out;
}

/**
 * The facts the film does not yet show the record's way, plus `source` when
 * the film does not yet take its facts from the record — filmfacts.differs.
 * `film` is the film's own word as the engine's view gives it (`project`:
 * title, displayTitle, director, producer, client, agency, factsSource).
 */
export function differs(want, film) {
  if (!want || !Object.keys(want).length) return [];
  const knows = film.factsSource !== undefined && film.factsSource !== null;
  const shown = {
    title: film.displayTitle || film.title || "",
    director: film.director || "",
    producer: film.producer || "",
    client: film.client || "",
    agency: film.agency || "",
  };
  const gaps = FIELDS.filter((f) => f in want && (f !== "title" || knows) && shown[f].trim() !== want[f]);
  if (knows && film.factsSource !== "console") gaps.push("source");
  return gaps;
}

// ── the bucket ──────────────────────────────────────────────────────────────

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

async function keepJson(env, key, body) {
  await env.BUCKET.put(key, JSON.stringify(body), { httpMetadata: { contentType: "application/json" } });
}

/** Who writes films' facts: the server (the Mac's copy went in stage 5 step 9). */
export async function filmsOwner(env) {
  return hubOwner(await readJson(env, "s/film-owner.json"));
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

// ── the mark ────────────────────────────────────────────────────────────────

/** Whether the film's icon and colour are written by the server: off until `{on:true}`. */
export async function marksOn(env) {
  const said = await readJson(env, MARK_SWITCH);
  return Boolean(said && said.on === true);
}

/** `{path, colour}` as the engine takes it (an outline and `#RRGGBB`), or `{}`. */
export function cleanPair(pair) {
  const path = pair && typeof pair.path === "string" ? pair.path.trim() : "";
  const colour = pair && typeof pair.colour === "string" ? pair.colour.trim().toUpperCase() : "";
  return path && /^#[0-9A-F]{6}$/.test(colour) ? { path, colour } : {};
}

/**
 * The Notion icon address the record's icon fact holds, or "" — only Notion's
 * own built-in icons (`https://www.notion.so/icons/<name>_<colour>.svg`), an
 * edit still waiting on a Mac to go up is not the record's yet, and an emoji
 * or a picture is no mark (the Mac's `mark_of` took the same).
 */
export function markAddress(facts) {
  const one = (facts || {}).icon;
  if (!held(one) || one.waiting) return "";
  const address = one.value.trim();
  return iconParts(address) ? address : "";
}

/**
 * The mark of a record's facts, with the icons it has seen kept in the bucket
 * (an icon's drawing at its address never changes, so it is asked for once).
 * `fetchText(address)` answers the SVG's text or "" (a refusal is no mark and
 * is not remembered). `of(facts)` answers `{path, colour}` or `{}`; `save()`
 * keeps anything new.
 */
export function markLookup(env, fetchText) {
  let pairs = null;
  let fresh = false;
  const load = async () => { if (!pairs) pairs = (await readJson(env, MARK_PAIRS)) || {}; return pairs; };
  return {
    async of(facts) {
      const address = markAddress(facts);
      if (!address) return {};
      const known = await load();
      if (known[address]) return cleanPair(known[address]);
      let drawing = "";
      try { drawing = await fetchText(address); } catch { drawing = ""; }
      const pair = cleanPair(drawing ? markFromSvg(drawing) : {});
      if (pair.path) { known[address] = pair; fresh = true; }
      return pair;
    },
    async save() { if (fresh && pairs) { await keepJson(env, MARK_PAIRS, pairs); fresh = false; } },
  };
}

/** The real fetch of an icon's drawing: a refusal answers "". */
export async function fetchIcon(address) {
  const got = await fetch(address);
  return got.ok ? await got.text() : "";
}

// ── doing ───────────────────────────────────────────────────────────────────

/**
 * One project's facts into its film, if the film needs them — mirror_one.
 * Answers {ok, already} (the film already shows them), {ok, taken, said}
 * (it was told), or {ok: false, why}.
 *
 * `mirror` is `mirrorRecord` (filmdoor.js), passed in so a plain node check of
 * this file need not load the engine.
 */
export async function mirrorOne(env, page, ctx, mirror, { dry = false, marks = null, only = "" } = {}) {
  const record = await readJson(env, `r/${page}/record.json`);
  if (!record) return { ok: false, why: "no record for this project" };
  const relay = record.film && record.film.relay;
  if (!relay) return { ok: false, why: "no film" };
  const hidden = Array.isArray(record.hidden) ? record.hidden.map(String) : [];
  const want = only === "mark" ? {} : wantedFacts(record.facts || {}, hidden);
  const pair = marks ? await marks.of(record.facts || {}) : {};
  if (!Object.keys(want).length && !pair.path) {
    return { ok: false, why: only === "mark" ? "the record holds no Notion icon for this project" : "the record holds none of these yet" };
  }
  // Studio reads the card: nothing is written into the film (a dry look still opens it).
  if (!dry && (await cardsStandDown(env))) {
    return { ok: true, already: true, card: true, want, pair, mark: pair.path ? "card" : "" };
  }
  let got;
  try {
    // A dry look opens the film and asks the door, but keeps nothing.
    got = await mirror(env, relay, ctx, {
      link: page,
      ...(Object.keys(want).length ? { facts: want } : {}),
      ...(pair.path ? { mark: pair } : {}),
      ...(dry ? { dry: true } : {}),
    });
  } catch (e) {
    const why = String((e && e.message) || e || "the film would not take them");
    return { ok: false, why: why.slice(0, 300), want, pair };
  }
  const changed = [...(got.changed || [])];
  if (got.mark === "mirrored") changed.push("mark");
  const mark = pair.path ? String(got.mark || "none") : "";
  if (!changed.length) return { ok: true, already: true, want, pair, mark };
  return { ok: true, taken: changed.join(", "), said: `facts: taken ${changed.join(", ")}`, want, pair, mark, ...(dry ? { dry: true } : {}) };
}

/**
 * The portal's minute: look at every project, tell the films whose words
 * moved. `state` remembers the words last told each film so a quiet minute
 * costs one read of each record and no film is opened.
 */
export async function filmFactsTick(env, ctx, mirror, when = Date.now(), { dry = false, marks = null } = {}) {
  const at = new Date(when).toISOString();
  const sweep = new Date(when).getUTCMinutes() % SWEEP_EVERY_MINUTES === 0;
  const state = (await readJson(env, STATE_KEY)) || { pages: {} };
  state.pages = state.pages || {};
  const said = [];
  const trouble = [];
  const hand = [];
  let looked = 0;
  let opened = 0;
  for (const page of await recordPages(env)) {
    looked += 1;
    const record = await readJson(env, `r/${page}/record.json`);
    const relay = record && record.film && record.film.relay;
    if (!relay) continue;
    const want = wantedFacts(record.facts || {}, Array.isArray(record.hidden) ? record.hidden.map(String) : []);
    const pair = marks ? await marks.of((record && record.facts) || {}) : {};
    if (!Object.keys(want).length && !pair.path) continue;
    const key = JSON.stringify(pair.path ? { relay, want, mark: pair } : { relay, want });
    const before = state.pages[page];
    const fresh = !before || before.key !== key || !before.ok;
    if (!fresh && !sweep) continue;
    const got = await mirrorOne(env, page, ctx, mirror, { dry, marks });
    const name = (record.name || page).toString();
    if (got.ok) {
      if (!dry) state.pages[page] = { key, ok: true, at };
      if (got.taken) said.push(`${dry ? "would tell " : ""}${name}: ${got.taken}`);
      if (got.mark === "hand") hand.push(name);
      opened += 1;
    } else {
      // "No film" and "none of these yet" are not trouble; a film that would
      // not take them is, and is tried again next minute.
      if (!dry) state.pages[page] = { key, ok: /no film|none of these/.test(got.why || ""), at };
      if (!/no film|none of these/.test(got.why || "")) trouble.push(`${name}: ${got.why}`);
    }
  }
  if (marks) await marks.save();
  if (!dry) await keepJson(env, STATE_KEY, state);
  const out = { at, sweep, looked, opened, said, trouble, ...(marks ? { marks: true, hand } : {}), ...(dry ? { dry: true } : {}) };
  await keepJson(env, dry ? `${LAST_KEY}.dry` : LAST_KEY, out);
  return out;
}

/** The timer's door: does nothing unless the server is the owner. */
export async function onFilmFactsTimer(env, ctx, when = Date.now()) {
  const { owner } = await filmsOwner(env);
  if (owner !== "hub") return;
  // Studio reads the card (studiocards.js): no film is told anything.
  if (await cardsStandDown(env)) return;
  try {
    const { mirrorRecord } = await import("./filmdoor.js");
    const marks = (await marksOn(env)) ? markLookup(env, fetchIcon) : null;
    await filmFactsTick(env, ctx, mirrorRecord, when, { marks });
  } catch (e) {
    await keepJson(env, LAST_KEY, { at: new Date(when).toISOString(), trouble: [String((e && e.stack) || e).slice(0, 2000)] });
  }
}
