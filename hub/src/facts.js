/**
 * **A project's facts, written from anywhere in the worker** (2026-10-05, the
 * one-record plan, phase 4 — the Notion link).
 *
 * The facts door (`/console/record/<page>/facts` in worker.js) was the only
 * writer. The portal's AI connector (`set_front`) wrote the logline straight
 * into the film's card instead — and the Mac's 15-minute refresh put Notion's
 * words back over it, so a logline changed that way silently reverted. Now
 * both go through `writeFacts`, the record keeps every change with a version,
 * and the Studio's Notion link carries it into Notion.
 *
 * **What a write does to the portal.** A fact the card shows (the logline) is
 * laid onto the card at once, so a change made in Notion, the console or
 * here shows on the portal within the link's minute rather than the next
 * refresh. `from_record` in refresh.py and `layRecordFacts` here are the same
 * rule; change one, change both.
 */
import { canonStage } from "./stageword.js";
import { keys } from "../../relay/layout.js";
import { storedFront, saveFront } from "./front.js";
import { cardCredits } from "./credits.js";
import { CAMERA_LABELS, labelledCameras } from "./entries.js";
import { portalOf } from "./films.js";
import { SPEC_FACT, checkSheet } from "./specsheet.js";
import { FACT as DOCS_FACT, layRecordDocs } from "./portaldocs.js";

export const FACT_NAME = /^[a-z][a-z0-9_]{0,40}$/;
const PAGE = /^[0-9a-f]{32}$/;
const RELAY = /^[0-9a-f]{32}$/;

/** Facts the card shows, by the card's own names — `RECORD_OWNS` in refresh.py. */
export const RECORD_OWNS = { logline: "logline", director: "director", producer: "producer",
  status: "status", type: "type", length: "length",
  directors_note: "note", visual_language: "look" };

/** Card fields that are prose, laid as one line the way the portal shows
 * them — `PROSE` and `one_line` in refresh.py. */
const PROSE = new Set(["logline", "note", "look"]);
export const oneLine = (words) => String(words ?? "").split(/\s+/).filter(Boolean).join(" ");
const asCard = (key, value) => (PROSE.has(key) ? oneLine(value) : value);

/** Facts laid onto the card the moment they are written: the logline, the
 * director's note, the visual language, and (since the AI connector writes
 * them too, 2026-10-05) the status, type and length. The rest still reach
 * the card through the refresh, as before. A fact the project hides is left
 * to the refresh, which leaves it off. */
const SHOWN_AT_ONCE = ["logline", "directors_note", "visual_language", "status", "type", "length"];

async function recordAt(env, page) {
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try { return { record: await got.json(), etag: got.etag }; } catch { return null; }
}

/** The record's facts for a Notion page id, or {} — never throws. */
export async function factsOfRecord(env, page) {
  const bare = String(page || "").replace(/-/g, "");
  if (!PAGE.test(bare)) return {};
  const got = await recordAt(env, bare);
  return (got && got.record && got.record.facts) || {};
}

/** The record's facts and what the project hides, for a Notion page id —
 * `hidden` is the console's word on its readout (recordlayout.py). */
export async function recordView(env, page) {
  const bare = String(page || "").replace(/-/g, "");
  if (!PAGE.test(bare)) return { facts: {}, hidden: [] };
  const got = await recordAt(env, bare);
  const record = (got && got.record) || {};
  return { facts: record.facts || {}, hidden: Array.isArray(record.hidden) ? record.hidden.map(String) : [] };
}

/** Lay the record's typed facts over a card. Returns the names that changed.
 * A field the project hides (`hidden`) is left off the card. */
export function layRecordFacts(card, facts, hidden = []) {
  const moved = [];
  for (const [field, key] of Object.entries(RECORD_OWNS)) {
    const one = (facts || {})[field];
    if (!one || typeof one !== "object" || !("value" in one)) continue;
    if (typeof one.value === "string" && card[key] !== asCard(key, one.value)) {
      card[key] = asCard(key, one.value);
      moved.push(key);
    }
  }
  for (const [field, key] of Object.entries(RECORD_OWNS)) {
    if (hidden.includes(field) && card[key]) {
      card[key] = "";
      moved.push(key);
    }
  }
  // which camera body is A Cam, B Cam: the record's, laid on the Camera box
  // of the lead shoot and of each shoot (Notion only lists the bodies)
  const camLabels = ((facts || {})[CAMERA_LABELS] || {}).value;
  if (camLabels && typeof camLabels === "object") {
    for (const one of [card, ...(Array.isArray(card.shoots) ? card.shoots : [])]) {
      const cam = one && one.camera;
      if (!cam || !cam.body) continue;
      const body = labelledCameras(cam.body, camLabels);
      if (body !== cam.body) { cam.body = body; if (!moved.includes("camera")) moved.push("camera"); }
    }
  }
  const listed = cardCredits(facts, hidden);
  if (JSON.stringify(card.credits || []) !== JSON.stringify(listed)) {
    card.credits = listed;
    moved.push("credits");
  }
  if (layRecordCrew(card, facts)) moved.push("crew");
  if (layRecordDocs(card, facts)) moved.push("documents");
  return moved;
}

const flat = (p) => ["name", "role", "department", "company", "email", "phone", "note"].map((k) => String((p || {})[k] || ""));
const nameKey = (name) => String(name || "").replace(/\s+/g, " ").trim().toLowerCase();
const bare = (id) => String(id || "").replace(/-/g, "");

/**
 * **People on the portal are the record's** (his decision, 2026-10-17:
 * people come from the project record, as Projects Console shows them; no
 * Notion pulling). Who is on the project, their roles and which shoots they
 * are on are the record's `crew` fact, plus everyone named in a credit — the
 * console's own list (`people` in projectpage.js). The record keeps no
 * contact details, so a person's department, company, email and phone are
 * kept from the card where the card already knows them, by name.
 *
 * A record with no `crew` fact leaves the card's people as they are. Returns
 * whether anything changed.
 */
export function layRecordCrew(card, facts) {
  const snap = ((facts || {}).crew || {}).value;
  if (!Array.isArray(snap)) return false;
  const credits = Array.isArray(((facts || {}).credits || {}).value) ? facts.credits.value : [];
  const shoots = Array.isArray(card.shoots) ? card.shoots : [];
  // what the card already knows of each person, wherever it is written
  const known = new Map();
  const order = new Map();
  for (const one of [...(card.crew || []), ...shoots.flatMap((s) => (s && s.crew) || [])]) {
    if (!one || !one.name) continue;
    const k = nameKey(one.name);
    if (!known.has(k)) known.set(k, one);
  }
  (card.crew || []).forEach((one, i) => { if (one && one.name && !order.has(nameKey(one.name))) order.set(nameKey(one.name), i); });

  const people = [];
  const add = (name, roles, onShoot) => {
    const k = nameKey(name);
    if (!k || people.some((p) => p.k === k)) return;
    const was = known.get(k) || {};
    people.push({
      k, onShoot,
      one: {
        name: String(name).trim(),
        role: roles.length ? roles.join(", ") : was.role || "",
        department: was.department || "",
        company: was.company || "",
        email: was.email || "",
        phone: was.phone || "",
        note: was.note || "",
      },
    });
  };
  for (const p of snap) {
    if (!p || !p.name) continue;
    const on = new Set((Array.isArray(p.shoots) ? p.shoots : []).map(bare));
    add(p.name, (Array.isArray(p.roles) ? p.roles : []).map(String).filter(Boolean),
      (id) => Boolean(p.all_shoots) || on.has(bare(id)));
  }
  // everyone named in a credit is on every shoot (the console's rule)
  for (const credit of credits) {
    for (const name of (credit && credit.people) || []) {
      const roles = credits.filter((c) => (c.people || []).some((n) => nameKey(n) === nameKey(name))).map((c) => c.role).filter(Boolean);
      add(name, known.has(nameKey(name)) ? [] : roles, () => true);
    }
  }
  // the card's order where it had one, newcomers after
  const rank = (p) => (order.has(p.k) ? order.get(p.k) : 1e6 + people.indexOf(p));
  const sorted = [...people].sort((a, b) => rank(a) - rank(b));
  // compared field by field, so a card written without `note` is not a change
  const same = (a, b) => JSON.stringify((a || []).map(flat)) === JSON.stringify((b || []).map(flat));
  let changed = false;
  const crew = sorted.map((p) => p.one);
  if (!same(card.crew, crew)) { card.crew = crew; changed = true; }
  for (const shoot of shoots) {
    if (!shoot || !shoot.id) continue;
    const mine = sorted.filter((p) => p.onShoot(shoot.id)).map((p) => p.one);
    if (!same(shoot.crew, mine)) { shoot.crew = mine; changed = true; }
  }
  return changed;
}

/**
 * Write facts, each from the version it was read at.
 *
 * `changes` is {field: {value, base}}; `base` is the version the writer last
 * saw (0 for a field never set). Answers one of
 *   {status: 200, facts, kept}             written; `kept` is the history lines
 *   {status: 409, conflicts: {field: stored}}  something moved on — nothing written
 *   {status: 400 | 404 | 500, problem}
 * Every accepted change is also kept, append-only, under `r/<page>/history/`.
 */
export async function writeFacts(env, page, changes, by) {
  if (!changes || typeof changes !== "object" || Array.isArray(changes) || !Object.keys(changes).length) {
    return { status: 400, problem: "Say which facts change: {changes: {field: {value, base}}}." };
  }
  for (const [field, change] of Object.entries(changes)) {
    if (!FACT_NAME.test(field)) return { status: 400, problem: `“${field}” is not a fact's name.` };
    if (!change || typeof change !== "object" || !("value" in change)) return { status: 400, problem: `Say ${field}'s value.` };
    // **A spec sheet is checked here, whoever writes it** (specsheet.js): the
    // one door every writer takes, so a stored sheet is always the one shape.
    if (field.startsWith("spec_")) {
      if (!SPEC_FACT.test(field)) return { status: 400, problem: `“${field}” is not a spec sheet's name: spec_<shoot id> or spec_project.` };
      if (change.value !== null) {
        const got = checkSheet(change.value);
        if (got.why) return { status: 400, problem: `${field}: ${got.why}` };
        changes = { ...changes, [field]: { ...change, value: got.sheet } };
      }
    }
    // **Either name for Complete is the record's "Released"** (stageword.js, 2026-10-20)
    if (field === "status" && typeof changes[field].value === "string" && canonStage(changes[field].value) !== changes[field].value) {
      changes = { ...changes, status: { ...changes[field], value: canonStage(changes[field].value) } };
    }
    if (JSON.stringify(changes[field].value).length > 20000) return { status: 400, problem: `${field} is too long.` };
  }
  const who = String(by || "").slice(0, 80);
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await env.BUCKET.get(`r/${page}/record.json`);
    if (!current) return { status: 404, problem: "No record for that project yet." };
    let record;
    try { record = await current.json(); } catch { return { status: 500, problem: "The record could not be read." }; }
    const facts = record.facts || {};
    const conflicts = {};
    for (const [field, change] of Object.entries(changes)) {
      const stored = facts[field];
      const v = stored ? stored.v || 0 : 0;
      if ((Number(change.base) || 0) !== v) conflicts[field] = stored || null;
    }
    if (Object.keys(conflicts).length) return { status: 409, conflicts };
    const at = new Date().toISOString();
    const kept = [];
    for (const [field, change] of Object.entries(changes)) {
      const before = facts[field] || null;
      facts[field] = { value: change.value, v: (before ? before.v || 0 : 0) + 1, at, by: who };
      kept.push({ field, from: before ? before.value : null, to: change.value, v: facts[field].v, at, by: who });
    }
    const next = { ...record, facts, updated: at };
    const put = await env.BUCKET.put(`r/${page}/record.json`, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: { etagMatches: current.etag },
    });
    if (!put) continue; // somebody wrote in between: read again and re-check
    for (const one of kept) {
      const id = crypto.randomUUID().slice(0, 8);
      await env.BUCKET.put(`r/${page}/history/${one.at}-${one.field}-${id}.json`, JSON.stringify(one), {
        httpMetadata: { contentType: "application/json" },
      });
    }
    try {
      await showOnPortal(env, page, next, kept);
    } catch {
      // The record is written; the card catches up at the next refresh.
    }
    return { status: 200, facts, kept };
  }
  return { status: 409, problem: "The record kept changing while this was being written. Try again." };
}

/**
 * The card a record's facts show on: the film's, when the record names one
 * that has a card; else the portal made before its film, which lives under
 * the page id itself. Null when there is neither.
 */
async function cardKeyOf(env, page, record) {
  const relay = record && record.film && record.film.relay;
  if (relay && RELAY.test(relay) && await env.BUCKET.head(keys.front(relay))) return relay;
  // A minted project's portal lives under its ID, not its Notion page.
  const { keyOfPage } = await import("./projectid.js");
  const key = await keyOfPage(env, page) || page;
  if (await portalOf(env, key)) return key;
  return null;
}

async function showOnPortal(env, page, record, kept) {
  const hidden = Array.isArray(record && record.hidden) ? record.hidden.map(String) : [];
  const shown = kept.filter((one) => SHOWN_AT_ONCE.includes(one.field) && typeof one.to === "string"
    && !hidden.includes(one.field));
  const people = kept.some((one) => one.field === "crew" || one.field === "credits");
  const docs = kept.some((one) => one.field === DOCS_FACT);
  if (!shown.length && !people && !docs) return;
  const project = await cardKeyOf(env, page, record);
  if (!project) return;
  const card = await storedFront(env, project);
  let moved = false;
  for (const one of shown) {
    const key = RECORD_OWNS[one.field];
    const to = asCard(key, one.to);
    if (card[key] !== to) { card[key] = to; moved = true; }
  }
  if (people && layRecordCrew(card, record.facts || {})) moved = true;
  if (docs && layRecordDocs(card, record.facts || {})) moved = true;
  if (moved) await saveFront(env, project, card);
}

/**
 * Which project record a film's card belongs to: the portal made before its
 * film is keyed by the page id itself; a film's card says `notion:<page>`
 * once the refresh has found it. "" when neither says.
 */
export async function recordPageOf(env, project, card) {
  // **One ID** (projectid.js): one way to find a project — its own ID, or a
  // film's relay id kept as its alias. The card's `source` is not asked.
  const { oneIdOn, resolveProject } = await import("./projectid.js");
  if ((await oneIdOn(env)).on) return PAGE.test(project) ? (await resolveProject(env, project)).key : "";
  if (PAGE.test(project) && await env.BUCKET.head(`r/${project}/record.json`)) return project;
  const said = /^notion:([0-9a-f-]{32,36})$/.exec(String((card && card.source) || ""));
  const page = said ? said[1].replace(/-/g, "") : "";
  if (page && await env.BUCKET.head(`r/${page}/record.json`)) return page;
  return "";
}
