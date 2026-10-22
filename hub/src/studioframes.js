/**
 * **Shared facts in Studio: frames and sensors** (stage 5 step 4, piece E,
 * 2026-10-15).
 *
 * His answers 20–21 (2026-10-14): the project's **frames** are written once,
 * on the spec sheet on the project record (`specsheet.js`: a name, a ratio,
 * one Main — the portal shows Main; no resolution, 2026-10-15). **Studio keeps
 * its ratio setting as a picker over those frames**, chosen apart from Main,
 * and can show the others as guide lines. **Sensor size comes from the
 * sheet's sensor mode of each camera** (sensormodes.js); squeeze still comes
 * from the lens name.
 *
 * So the card Studio reads (`studiocards.js`) gains `sheet`: the frames and
 * each camera's sensor of the sheet the project reads (the lead shoot's own,
 * else the project's — the portal's rule, `laySheets`), and under `shoots`
 * each shoot's when it reads its own. The engine (`engine/src/frames.rs`)
 * lays it over the film; the film keeps only Studio's pick (`studio_frame`)
 * and the guides switch, plus the picked frame's ratio as its own for
 * readers with no card.
 *
 * Behind one switch, `s/studio-frames.json`, off until thrown. Off, cards
 * carry no sheet and Studio is exactly what it was (its own ratio menu, the
 * sensors typed in Settings). On:
 * - every card carries `sheet` (an empty one for a project with no sheet:
 *   Studio then shows one Main frame at the film's own ratio);
 * - the portal's renderer draws the picked frame's ratio line from the card
 *   (`frameRatio`), so a frame changed on the sheet shows at once;
 * - the server's New Shoot ties its Studio day to the new shoot (the day is
 *   written once and follows the shoot's dates; no section is made).
 *
 *   GET  /console/studio/studioframes         the switch {on, at, by}
 *   PUT  /console/studio/studioframes         {on, by}
 *   POST /console/studio/studioframes/look    {only?} — per project with a
 *                                             film: the ratio and sensors
 *                                             Studio shows today against what
 *                                             it would show. Writes nothing.
 */

import { recordSheets, sheetForShoot, framesOf, PROJECT_KEY, SPEC_FACT } from "./specsheet.js";
import { refuseOff } from "./fixedon.js";

export const SWITCH_KEY = "s/studio-frames.json";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function framesOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setFrames(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

// ── the card's sheet ─────────────────────────────────────────────────────────

/** A frame's ratio as width over height, or 0 when it is not one ("2.39:1", "9:16", "2.39"). */
export function ratioValue(said) {
  const t = String(said || "").trim().replace(/∶/g, ":");
  const m = t.match(/^(\d+(?:\.\d+)?)\s*(?:[:x×/]\s*(\d+(?:\.\d+)?))?$/i);
  if (!m) return 0;
  const r = m[2] === undefined ? Number(m[1]) : Number(m[1]) / Number(m[2]);
  return Number.isFinite(r) && r > 0.2 && r < 10 ? r : 0;
}

/** One sheet as Studio takes it: its frames (only those with a ratio) and each camera's sensor. */
export function studioSheet(sheet) {
  const frames = sheet ? framesOf(sheet) : [];
  return {
    frames: frames
      .filter((f) => f && f.name && ratioValue(f.ratio) > 0)
      .map((f) => ({ name: String(f.name), ratio: String(f.ratio), main: f.main === true })),
    sensors: ((sheet && sheet.cameras) || [])
      .filter((c) => c && c.label && isObject(c.sensor) && Number(c.sensor.width) > 0)
      .map((c) => ({ label: String(c.label), name: String(c.sensor.name || ""), width: Number(c.sensor.width), height: Number(c.sensor.height) || 0 })),
  };
}

/** The shoot the portal leads with (`leadShoot` in front.js and specsheet.js): the next one, else the last. */
function leadShoot(shoots) {
  if (!shoots.length) return null;
  return shoots.find((s) => /^(upcoming|next|today|to wrap)$/i.test(String(s.state || s.status || ""))) || shoots[shoots.length - 1];
}

/**
 * **A card's sheet**: from the record's facts and the card's shoots. The
 * project reads the lead shoot's sheet (its own, else the project's); a
 * project with no shoots reads the project's, else its only shoot sheet.
 * Each shoot that reads a sheet is under `shoots`. A project with no sheet
 * at all gets an empty one.
 */
export function cardSheet(facts, shoots = []) {
  const sheets = recordSheets(facts || {});
  const list = Array.isArray(shoots) ? shoots.filter((s) => s && s.id) : [];
  let lead = null;
  const leader = leadShoot(list);
  if (leader) lead = sheetForShoot(sheets, leader.id);
  if (!lead && sheets[PROJECT_KEY]) lead = { fact: PROJECT_KEY, ...sheets[PROJECT_KEY] };
  if (!lead) {
    const names = Object.keys(sheets).filter((k) => SPEC_FACT.test(k)).sort();
    if (names.length) lead = { fact: names[names.length - 1], ...sheets[names[names.length - 1]] };
  }
  const out = studioSheet(lead ? lead.sheet : null);
  const per = {};
  for (const s of list) {
    const got = sheetForShoot(sheets, s.id);
    if (got) per[String(s.id).replace(/-/g, "").toLowerCase()] = studioSheet(got.sheet);
  }
  if (Object.keys(per).length) out.shoots = per;
  return out;
}

/** Lay the sheet on a card made from `record` (in place), when the switch is on. */
export function laySheet(card, record) {
  card.sheet = cardSheet(isObject(record && record.facts) ? record.facts : {}, card.shoots || []);
  return card;
}

/**
 * **The frame Studio draws at**, by the engine's rule (`frames.rs`
 * `picked_frame`): its pick by name; else the frame at the film's own ratio;
 * else Main. `frames` as `studioSheet` gives them. Null with none.
 */
export function pickedFrame(frames, pick, own) {
  const list = (frames || []).filter((f) => ratioValue(f.ratio) > 0);
  if (!list.length) return null;
  const want = String(pick || "").trim().toLowerCase();
  if (want) {
    const named = list.find((f) => String(f.name).trim().toLowerCase() === want);
    if (named) return named;
  }
  const r = Number(own);
  if (r > 0) {
    const same = list.find((f) => Math.abs(ratioValue(f.ratio) - r) < 0.005);
    if (same) return same;
  }
  return list.find((f) => f.main) || list[0];
}

/** The ratio Studio draws at, from a card's sheet and the film's pick and own ratio (2.39 when nothing says one). */
export function frameRatio(sheet, pick, own) {
  const got = pickedFrame(sheet && sheet.frames, pick, own);
  if (got) return ratioValue(got.ratio);
  return Number(own) > 0 ? Number(own) : 2.39;
}

// ── the look ─────────────────────────────────────────────────────────────────

const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.005;
const round = (r) => Math.round(Number(r) * 1000) / 1000;

/**
 * One film: what Studio shows today (`today`: the engine's view `project`
 * and `units` with no sheet on the card) against what it would show with the
 * sheet laid on (`after`). Pure.
 */
export function compareFrames(sheet, today, after) {
  const was = Number(today.project && today.project.ratio) || 2.39;
  const will = Number(after.project && after.project.ratio) || 2.39;
  const row = {
    ratio: { now: round(was), would: round(will), frame: String((after.project && after.project.frame) || "") },
    frames: (sheet.frames || []).map((f) => `${f.name} ${f.ratio}${f.main ? " (Main)" : ""}`),
    sensors: [],
  };
  row.ratioChanges = !near(was, will);
  const before = new Map(((today.units) || []).map((u) => [u.id, u]));
  for (const u of after.units || []) {
    const b = before.get(u.id) || {};
    const now = b.sensor_w ? `${b.sensor_name || ""} ${round(b.sensor_w)}×${round(b.sensor_h || 0)}`.trim() : "";
    const would = u.sensor_w ? `${u.sensor_name || ""} ${round(u.sensor_w)}×${round(u.sensor_h || 0)}`.trim() : "";
    row.sensors.push({ camera: u.label, now, would, fromSheet: u.sensor_sheet === true, changes: now !== would });
  }
  row.sensorChanges = row.sensors.filter((s) => s.changes).length;
  return row;
}

/**
 * **The dry look**: per project with a film, the ratio and sensors Studio
 * shows today against what it would show with the switch on.
 * `readView(env, relay, ctx, card)` answers the engine's whole view with
 * `card` laid on (`studioframesfilm.js`). Writes nothing.
 */
export async function framesLook(env, ctx, readView, { only = "", cards = null, records = null } = {}) {
  const { allCards } = await import("./studiocards.js");
  const list = cards || await allCards(env, { only });
  const rows = [];
  for (const card of list) {
    const record = records ? records[card.id] : await readJson(env, `r/${card.id}/record.json`);
    const sheet = cardSheet(isObject(record) && isObject(record.facts) ? record.facts : {}, card.shoots || []);
    const row = { id: card.id, name: card.name, film: Boolean(card.relay), sheet: sheet.frames.length > 0 || sheet.sensors.length > 0 };
    if (!card.relay) { row.frames = sheet.frames.map((f) => `${f.name} ${f.ratio}${f.main ? " (Main)" : ""}`); rows.push(row); continue; }
    try {
      const plain = { ...card };
      delete plain.sheet;
      const today = await readView(env, card.relay, ctx, plain);
      const after = await readView(env, card.relay, ctx, { ...card, sheet });
      Object.assign(row, compareFrames(sheet, today, after));
    } catch (e) {
      row.trouble = String((e && e.message) || e).slice(0, 200);
    }
    rows.push(row);
  }
  const films = rows.filter((r) => r.film);
  return {
    at: new Date().toISOString(),
    projects: rows.length,
    films: films.length,
    ratioChanges: films.filter((r) => r.ratioChanges).length,
    sensorChanges: films.filter((r) => r.sensorChanges).length,
    rows,
  };
}

// ── the door ─────────────────────────────────────────────────────────────────

export async function framesDoor(env, rest, method, read, ctx, { readView } = {}) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest[0] !== "studioframes") return null;
  if (rest.length === 1) {
    if (method === "GET") return reply(await framesOn(env));
    if (method !== "PUT") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said;
    try { said = await read(); } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    return reply(await setFrames(env, said));
  }
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "POST" && method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
    let said = {};
    if (method === "POST") {
      try { said = (await read()) || {}; } catch { return reply({ ok: false, problem: "That is not JSON." }, 400); }
    }
    const reader = readView || (await import("./studioshootsfilm.js")).filmView;
    return reply(await framesLook(env, ctx, reader, { only: String(said.only || "").slice(0, 64) }));
  }
  return null;
}
