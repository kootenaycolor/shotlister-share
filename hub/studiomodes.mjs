#!/usr/bin/env node
/**
 * **Modes, one switch everywhere** — `src/studiomodes.js` (stage 5 step 4, piece B).
 *
 * 1. The starting sets per Type; a Job starts with none; an unknown Type hides nothing.
 * 2. The project's own changes over its standard, kept only where they differ.
 * 3. The rules between modes: Schedule brings Shot List; Shot List off offers both.
 * 4. The switch: off by default; setting refuses while off (a dry ask answers).
 * 5. Setting: written as a `modes` fact; the Studio side made first when a mode
 *    goes on for a project with none, and a refusal there writes nothing.
 * 6. The card carries the list, the cards door says whether Studio follows it.
 * 7. The look: a mode a film already uses that its start would hide is found,
 *    and the run keeps it on; a planted difference is caught.
 * 8. The doors.
 *
 *     node hub/studiomodes.mjs
 */
import {
  MODES, standardOf, resolveModes, modesAfter, modesValue, explicitOf, setMode, modesOn, setModesSwitch,
  modesLook, usedModes, modesDoor, readModes,
} from "./src/studiomodes.js";
import { allCards, cardsDoor } from "./src/studiocards.js";
import { markLookup } from "./src/filmfacts.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 70).padEnd(72)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 500)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function bucket() {
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? { json: async () => JSON.parse(m.get(k)), text: async () => m.get(k), etag: "e" } : null; },
    async head(k) { return m.has(k) ? {} : null; },
    async put(k, v) { m.set(k, typeof v === "string" ? v : String(v)); return {}; },
    async delete(k) { m.delete(k); },
    async list({ prefix, delimiter }) {
      const seen = new Set();
      for (const k of m.keys()) if (k.startsWith(prefix)) seen.add(prefix + k.slice(prefix.length).split(delimiter)[0] + delimiter);
      return { delimitedPrefixes: [...seen], truncated: false };
    },
  };
}
const ID = (n) => n.toString(16).padStart(32, "0");
const RELAY = (n) => "f" + n.toString(16).padStart(31, "0");
const fact = (value, v = 1) => ({ value, v, at: "2026-10-05T10:00:00.000Z" });

const env = { BUCKET: bucket() };
const put = (key, record) => env.BUCKET.put(`r/${key}/record.json`, JSON.stringify({ page: key, ...record }));
const record = async (key) => JSON.parse(env.BUCKET.m.get(`r/${key}/record.json`));
/** writeFacts, as far as these checks need it: compare-and-set on `v`. */
const writes = [];
const writeFacts = async (page, changes, by) => {
  const r = await record(page);
  r.facts ||= {};
  for (const [k, c] of Object.entries(changes)) {
    const v = r.facts[k] ? r.facts[k].v || 0 : 0;
    if ((Number(c.base) || 0) !== v) return { status: 409, conflicts: { [k]: r.facts[k] } };
  }
  for (const [k, c] of Object.entries(changes)) r.facts[k] = { value: c.value, v: (r.facts[k] ? r.facts[k].v || 0 : 0) + 1, by };
  await put(page, r);
  writes.push({ page, changes, by });
  return { status: 200, facts: r.facts };
};

// ── 1. the starting sets ─────────────────────────────────────────────────────

check("Narrative: all five", same(standardOf("Narrative"), MODES));
check("Commercial: Shot List, References, Schedule", same(standardOf("Commercial"), ["shot_list", "references", "schedule"]));
check("Music Video behaves as Commercial", same(standardOf("music video"), standardOf("Commercial")));
check("Personal: Shot List, References", same(standardOf("Personal"), ["shot_list", "references"]));
check("a Job: none, whatever its Type", same(standardOf("Narrative", true), []) && same(standardOf("Commercial", true), []));
check("no Type yet: nothing hidden", same(standardOf(""), MODES) && same(standardOf("Documentary"), MODES));
check("Type read case- and space-blind", same(standardOf("  COMMERCIAL "), standardOf("Commercial")));

// ── 2. the project's own changes ─────────────────────────────────────────────

const nar = { type: "Narrative", facts: {} };
check("a record with no modes fact shows its standard", same(resolveModes(nar).modes, MODES));
const com = { facts: { type: fact("Commercial"), modes: fact({ locations: true, references: false, junk: true, diagram: "yes" }) } };
check("the fact's type wins over the record's, changes laid on", same(resolveModes(com).modes, ["shot_list", "locations", "schedule"]), JSON.stringify(resolveModes(com)));
check("only known modes and booleans are read", same(explicitOf(com.facts), { locations: true, references: false }));
const odd = { type: "Personal", facts: { modes: fact({ shot_list: false, schedule: true }) } };
check("Schedule on keeps Shot List showing, whatever was written", same(resolveModes(odd).modes, ["shot_list", "references", "schedule"]));
check("a Job record starts with none", same(resolveModes({ type: "Narrative", job: true, facts: {} }).modes, []));
check("the value is only the differences", same(modesValue(standardOf("Commercial"), ["shot_list", "locations", "schedule"]), { locations: true, references: false }));
check("the standard itself is an empty value", same(modesValue(MODES, MODES), {}));

// ── 3. the rules between modes ───────────────────────────────────────────────

const pers = ["shot_list", "references"];
let r = modesAfter(pers, "schedule", true);
check("Schedule on brings Shot List (already on)", r.ok && same(r.modes, ["shot_list", "references", "schedule"]) && same(r.also, []));
r = modesAfter(["references"], "schedule", true);
check("Schedule on brings Shot List (was off)", r.ok && same(r.modes, ["shot_list", "references", "schedule"]) && same(r.also, ["shot_list"]), JSON.stringify(r));
r = modesAfter(["shot_list", "schedule"], "shot_list", false);
check("Shot List off while Schedule on: refused, both offered", !r.ok && r.needs === "both", JSON.stringify(r));
r = modesAfter(["shot_list", "schedule", "diagram"], "shot_list", false, true);
check("…and with both, both go off", r.ok && same(r.modes, ["diagram"]) && same(r.also, ["schedule"]), JSON.stringify(r));
r = modesAfter(["shot_list", "schedule"], "schedule", false);
check("Schedule off leaves Shot List", r.ok && same(r.modes, ["shot_list"]));
check("no such mode", !modesAfter(MODES, "storyboard", true).ok);

// ── 4. the switch ────────────────────────────────────────────────────────────

check("off by default", (await modesOn(env)).on === false);
await env.BUCKET.put("s/ids.json", JSON.stringify({ notion: {}, alias: { [RELAY(1)]: ID(1), [RELAY(3)]: ID(3), [RELAY(4)]: ID(4) } }));
await put(ID(1), { name: "Lets Bake", type: "Commercial", film: { relay: RELAY(1) }, facts: { title: fact("Let's Bake") } });
r = await setMode(env, ID(1), { mode: "locations", on: true }, { writeFacts });
check("setting refused while off", !r.ok && r.status === 409 && writes.length === 0, JSON.stringify(r));
r = await setMode(env, ID(1), { mode: "locations", on: true, dry: true }, { writeFacts });
check("a dry ask answers while off, writes nothing", r.ok && r.dry && same(r.modes, ["shot_list", "locations", "references", "schedule"]) && same(r.would, { locations: true }) && writes.length === 0, JSON.stringify(r));
await setModesSwitch(env, { on: true, by: "check" });
check("thrown on", (await modesOn(env)).on === true && (await modesOn(env)).by === "check");

// ── 5. setting ───────────────────────────────────────────────────────────────

r = await setMode(env, ID(1), { mode: "locations", on: true, by: "studio" }, { writeFacts });
check("on: written as the difference", r.ok && same((await record(ID(1))).facts.modes.value, { locations: true }) && writes.at(-1).by === "studio", JSON.stringify(r));
check("…and answers the new list", same(r.modes, ["shot_list", "locations", "references", "schedule"]));
r = await setMode(env, ID(1), { mode: "locations", on: true }, { writeFacts });
check("the same again writes nothing", r.ok && r.unchanged && writes.length === 1, JSON.stringify(r));
r = await setMode(env, RELAY(1), { mode: "shot_list", on: false }, { writeFacts });
check("found by its film's id; Shot List off asks about Schedule", !r.ok && r.needs === "both" && writes.length === 1, JSON.stringify(r));
r = await setMode(env, RELAY(1), { mode: "shot_list", on: false, both: true }, { writeFacts });
check("…both off, kept as differences", r.ok && same(r.modes, ["locations", "references"])
  && same((await record(ID(1))).facts.modes.value, { shot_list: false, locations: true, schedule: false }), JSON.stringify((await record(ID(1))).facts.modes));
r = await setMode(env, ID(1), { mode: "schedule", on: true }, { writeFacts });
check("Schedule back on brings Shot List back", r.ok && same(r.modes, ["shot_list", "locations", "references", "schedule"]) && same(r.also, ["shot_list"])
  && same((await record(ID(1))).facts.modes.value, { locations: true }));
r = await setMode(env, ID(1), { mode: "Locations", on: true }, { writeFacts });
check("a wrong mode name is refused", !r.ok && r.status === 400);
r = await setMode(env, ID(1), { mode: "locations" }, { writeFacts });
check("on or off must be said", !r.ok && r.status === 400);
check("an unknown project", (await setMode(env, ID(99), { mode: "diagram", on: true }, { writeFacts })).status === 404);

// a project with no Studio side
await put(ID(2), { name: "Quick One", type: "Personal", job: true, facts: {} });
const sides = [];
let sideAnswer = { ok: true, relay: ID(2), made: true };
const ensureSide = async (key) => { sides.push(key); return sideAnswer; };
const w0 = writes.length;
sideAnswer = { ok: false, why: "A film called \"Quick One\" already exists on the relay." };
r = await setMode(env, ID(2), { mode: "references", on: true }, { writeFacts, ensureSide });
check("no Studio side: made first; a refusal there writes nothing", !r.ok && sides.length === 1 && writes.length === w0 && /already exists/.test(r.why), JSON.stringify(r));
sideAnswer = { ok: true, relay: ID(2), made: true };
r = await setMode(env, ID(2), { mode: "references", on: true }, { writeFacts, ensureSide });
check("…made, then the mode written", r.ok && sides.length === 2 && r.side && r.side.made && same((await record(ID(2))).facts.modes.value, { references: true }), JSON.stringify(r));
await put(ID(2), { ...(await record(ID(2))), film: { relay: ID(2) } });
r = await setMode(env, ID(2), { mode: "references", on: false }, { writeFacts, ensureSide });
check("turning off never makes a side", r.ok && sides.length === 2 && same(r.modes, []));
r = await setMode(env, ID(2), { mode: "diagram", on: true }, { writeFacts, ensureSide });
check("a project with its side is not made again", r.ok && sides.length === 2);

// a write that loses a race is read again
let raced = false;
const racing = async (page, changes, by) => {
  if (!raced) { raced = true; const rr = await record(page); rr.facts.modes = { ...rr.facts.modes, v: (rr.facts.modes.v || 0) + 1 }; await put(page, rr); return { status: 409 }; }
  return writeFacts(page, changes, by);
};
r = await setMode(env, ID(1), { mode: "diagram", on: true }, { writeFacts: racing });
check("a write that loses a race is read again and lands", r.ok && raced && (await record(ID(1))).facts.modes.value.diagram === true, JSON.stringify(r));

// ── 6. the card ──────────────────────────────────────────────────────────────

await put(ID(3), { name: "Call Her Back", type: "Narrative", film: { relay: RELAY(3) }, facts: { title: fact("Call Her Back") } });
const marks = markLookup(env, async () => "");
const cards = await allCards(env, { marks });
const card = (id) => cards.find((c) => c.id === id);
check("the card carries the list", same(card(ID(3)).modes, MODES) && same(card(ID(1)).modes, ["shot_list", "locations", "references", "schedule", "diagram"]), JSON.stringify(cards.map((c) => c.modes)));
check("a Job carries only what was turned on", same(card(ID(2)).modes, ["diagram"]), JSON.stringify(card(ID(2)).modes));
const rd = await readModes(env, RELAY(3));
check("read by any id", rd.ok && rd.id === ID(3) && same(rd.modes, MODES) && rd.relay === RELAY(3), JSON.stringify(rd));
const door = async (rest, method, said, deps) => {
  const res = await (rest[0] === "cards" ? cardsDoor(env, rest, method, async () => said) : modesDoor(env, rest, method, async () => said, null, deps));
  return res ? { status: res.status, body: await res.json() } : null;
};
let d = await door(["cards"], "GET");
check("the cards door says whether Studio follows the modes", d.status === 200 && d.body.modes === true && d.body.on === false, JSON.stringify({ on: d.body.on, modes: d.body.modes }));

// ── 7. the look ──────────────────────────────────────────────────────────────

// Lets Bake (a commercial) has locations and a diagram; Call Her Back everything;
// Daybreak (Personal) has a schedule its start would hide.
await put(ID(4), { name: "Daybreak", type: "Personal", film: { relay: RELAY(4) }, facts: {} });
await put(ID(1), { ...(await record(ID(1))), facts: { title: fact("Let's Bake") } }); // back to its start
const use = {
  [RELAY(1)]: { scenes: 12, scripts: 1, locations: 3, boards: 2, days: 2, diagrams: 1 },
  [RELAY(3)]: { scenes: 40, scripts: 1, locations: 9, boards: 4, days: 6, diagrams: 0 },
  [RELAY(4)]: { scenes: 5, scripts: 0, locations: 0, boards: 0, days: 1, diagrams: 0 },
};
const readUse = async (_env, relay) => { if (!use[relay]) throw new Error("no film"); return use[relay]; };
check("used modes from counts", same(usedModes(use[RELAY(1)]), MODES) && same(usedModes({}), []) && same(usedModes({ scripts: 1 }), ["shot_list"]));
const before = JSON.stringify([...env.BUCKET.m.entries()]);
let look = await modesLook(env, null, readUse, { dry: true });
const row = (id) => look.rows.find((x) => x.id === id);
check("dry: writes nothing", JSON.stringify([...env.BUCKET.m.entries()]) === before);
check("every project is a row", look.projects === 4 && look.films === 4, JSON.stringify(look.rows.map((x) => [x.name, x.relay])));
check("Lets Bake would hide Locations and Diagram", same(row(ID(1)).hides, ["locations", "diagram"]) && same(row(ID(1)).keep, { locations: true, diagram: true }), JSON.stringify(row(ID(1))));
check("Daybreak would hide Schedule", same(row(ID(4)).hides, ["schedule"]) && same(row(ID(4)).keep, { schedule: true }));
check("Call Her Back hides nothing", same(row(ID(3)).hides, []) && !row(ID(3)).keep);
check("the count of projects that would hide something", look.hiding === 2);
look = await modesLook(env, null, readUse, { dry: false, deps: { writeFacts } });
check("run: keeps on what each film uses", same((await record(ID(1))).facts.modes.value, { locations: true, diagram: true }) && same((await record(ID(4))).facts.modes.value, { schedule: true })
  && !(await record(ID(3))).facts.modes, JSON.stringify(look.rows.map((x) => x.wrote)));
look = await modesLook(env, null, readUse, { dry: true });
check("after the run nothing would be hidden", look.hiding === 0, JSON.stringify(look.rows.filter((x) => x.hides && x.hides.length)));
use[RELAY(3)] = { ...use[RELAY(3)], diagrams: 2 };
await put(ID(3), { ...(await record(ID(3))), facts: { modes: fact({ diagram: false }) } });
look = await modesLook(env, null, readUse, { dry: true });
check("a planted difference is caught (a diagram drawn, the mode off)", look.hiding === 1 && same(look.rows.find((x) => x.id === ID(3)).hides, ["diagram"]), JSON.stringify(look.rows.find((x) => x.id === ID(3))));
look = await modesLook(env, null, readUse, { dry: true, only: ID(4) });
check("one project at a time", look.projects === 1 && look.rows[0].id === ID(4));
use[RELAY(4)] = undefined;
look = await modesLook(env, null, readUse, { dry: true, only: ID(4) });
check("a film that cannot be read is a row with its trouble", look.rows[0].trouble === "no film");

// ── 8. the doors ─────────────────────────────────────────────────────────────

d = await door(["studiomodes"], "GET");
check("GET the switch", d.status === 200 && d.body.on === true);
d = await door(["studiomodes"], "PUT", { on: false, by: "check" });
check("PUT off is refused (fixed on)", d.body.on === true && /fixed on/.test(d.body.problem || "") && (await modesOn(env)).on === true);
d = await door(["modes", ID(3)], "GET");
check("GET a project's modes", d.status === 200 && same(d.body.modes, ["shot_list", "locations", "references", "schedule"]), JSON.stringify(d.body));
d = await door(["modes", ID(99)], "GET");
check("GET an unknown project: 404", d.status === 404);
d = await door(["modes", "look"], "POST", { only: ID(1) }, { readUse });
check("POST look is dry by default", d.status === 200 && d.body.dry === true && d.body.projects === 1, JSON.stringify(d.body).slice(0, 200));
check("not this door's", (await modesDoor(env, ["cards"], "GET", async () => ({}))) === null && (await modesDoor(env, ["modes", "a", "b"], "GET", async () => ({}))) === null);
d = await door(["studiomodes"], "DELETE");
check("wrong method", d.status === 405);

console.log(`studiomodes: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
