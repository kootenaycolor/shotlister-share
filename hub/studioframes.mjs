#!/usr/bin/env node
/**
 * **Frames and sensors in Studio** — `src/studioframes.js` (stage 5 step 4,
 * piece E).
 *
 * 1. The switch: off by default; off, no card carries a sheet.
 * 2. A card's sheet: the lead shoot's (own, else the project's) frames and
 *    each camera's sensor, a shoot's own under `shoots`; frames with no
 *    ratio left out; a project with no sheet gets an empty one.
 * 3. The frame Studio draws at, by the engine's rule (pick, own ratio, Main).
 * 4. The cards door, the engine's card and the portal's ratio line.
 * 5. New Shoot: with the switch on, the film's day is the new shoot's own.
 * 6. The look: today against with the sheet, per film. Writes nothing.
 *
 *     node hub/studioframes.mjs
 */
import { register } from "node:module";
register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

const F = await import("./src/studioframes.js");
const C = await import("./src/studiocards.js");

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
    async get(k) { return m.has(k) ? { json: async () => JSON.parse(m.get(k)), text: async () => m.get(k) } : null; },
    async head(k) { return m.has(k) ? {} : null; },
    async put(k, v) { m.set(k, typeof v === "string" ? v : String(v)); return {}; },
    async list({ prefix, delimiter }) {
      const seen = new Set();
      for (const k of m.keys()) if (k.startsWith(prefix)) seen.add(prefix + k.slice(prefix.length).split(delimiter)[0] + delimiter);
      return { delimitedPrefixes: [...seen], truncated: false };
    },
  };
}
const fact = (value) => ({ value, v: 1, at: "2026-10-05T10:00:00.000Z" });
const marks = { of: async () => ({}), save: async () => {} };
const SUN = "11111111111111111111111111111111";
const CHB = "33333333333333333333333333333333";
const LC = "e6ee5875f5d789412e0b12538f71cfb5";
const RELAY = "feedface000040008000000000000006";
const S1 = "4acab7b3b555897c7c58dce7762aca55";
const S2 = "50ad95105a93869dd1c97f9e1a45a05a";

const cam = (label, guides, sensor) => ({ label, body: "Alexa 35", format: sensor ? [sensor.name] : [], capture: [], fps: [], codec: [], colour: [], desqueeze: [], luts: [], ...(sensor ? { sensor } : {}) });
const sheet = (cameras, frames) => ({ format: 1, cameras, lenses: [], ...(frames ? { frames } : {}), notes: "", files: [] });
const SUN_SHEET = sheet([cam("A Cam", ["2.39:1"], { ref: "m-og", name: "Open Gate", width: 36.7, height: 25.54 }), cam("B Cam", ["2.39:1"])],
  [{ name: "Delivery", ratio: "2.39:1", main: true }, { name: "Social", ratio: "9:16", main: false }, { name: "Unsaid", ratio: "", main: false }]);

const env = { BUCKET: bucket() };
await env.BUCKET.put(`r/${SUN}/record.json`, JSON.stringify({ page: SUN, name: "Daybreak", type: "Narrative", film: { relay: SUN }, facts: { title: fact("Daybreak"), spec_project: fact(SUN_SHEET) } }));
await env.BUCKET.put(`r/${CHB}/record.json`, JSON.stringify({ page: CHB, name: "Call Her Back", type: "Narrative", facts: { title: fact("Call Her Back") } }));
await env.BUCKET.put(`r/${LC}/record.json`, JSON.stringify({ page: LC, name: "Lets Bake", type: "Commercial", film: { relay: RELAY }, facts: {
  title: fact("Let's Bake"),
  [`spec_${S1}`]: fact(sheet([cam("A Cam", ["1:1"])], [{ name: "Main", ratio: "1:1", main: true }])),
  [`spec_${S2}`]: fact(sheet([cam("A Cam", ["16:9"])], [{ name: "Main", ratio: "16:9", main: true }])),
} }));

// 1. the switch
check("off by default", (await F.framesOn(env)).on === false);
let cards = await C.allCards(env, { marks });
check("off: no card carries a sheet", cards.every((c) => !("sheet" in c)), JSON.stringify(cards.map((c) => Object.keys(c))));
check("off: the engine's card has no sheet", cards.every((c) => !JSON.parse(C.engineCard(c)).sheet));
const set = await F.setFrames(env, { on: true, by: "check" });
check("on", set.on === true && set.by === "check" && (await F.framesOn(env)).on === true);

// 2. a card's sheet
const sun = F.cardSheet({ spec_project: fact(SUN_SHEET) }, []);
check("the sheet's frames, a frame with no ratio left out", same(sun.frames.map((f) => f.name), ["Delivery", "Social"]), JSON.stringify(sun.frames));
check("Main kept", sun.frames[0].main === true && sun.frames[1].main === false);
check("a camera's sensor off its sensor mode", same(sun.sensors, [{ label: "A Cam", name: "Open Gate", width: 36.7, height: 25.54 }]), JSON.stringify(sun.sensors));
check("a camera with no sensor mode gives none", !sun.sensors.some((s) => s.label === "B Cam"));
const def = F.cardSheet({ spec_project: fact(sheet([cam("A Cam", ["1.85:1"])])) }, []);
check("no frames stored: none to pick (a camera has no guides to take one from)", same(def.frames, []), JSON.stringify(def.frames));
check("no sheet at all: an empty one", same(F.cardSheet({}, []), { frames: [], sensors: [] }));
const lcShoots = [{ id: S1, label: "Shoot 1", state: "Wrapped" }, { id: S2, label: "Shoot 2", state: "Wrapped" }];
const lc = F.cardSheet(JSON.parse(await (await env.BUCKET.get(`r/${LC}/record.json`)).text()).facts, lcShoots);
check("shoots: the lead shoot's own (the last, all wrapped)", lc.frames[0].ratio === "16:9", JSON.stringify(lc));
check("shoots: each shoot's own under shoots", lc.shoots && lc.shoots[S1].frames[0].ratio === "1:1" && lc.shoots[S2].frames[0].ratio === "16:9", JSON.stringify(lc.shoots));
const lead = F.cardSheet(JSON.parse(await (await env.BUCKET.get(`r/${LC}/record.json`)).text()).facts, [{ id: S1, state: "Next" }, { id: S2, state: "Upcoming" }]);
check("shoots: the next one leads", lead.frames[0].ratio === "1:1", JSON.stringify(lead.frames));
const noShoots = F.cardSheet(JSON.parse(await (await env.BUCKET.get(`r/${LC}/record.json`)).text()).facts, []);
check("shoot sheets but no shoots on the card: one of them, not nothing", noShoots.frames.length === 1, JSON.stringify(noShoots));

// 3. the frame Studio draws at
check("ratio: 2.39:1, 9:16, 2.39, nonsense", Math.abs(F.ratioValue("2.39:1") - 2.39) < 1e-9 && Math.abs(F.ratioValue("9:16") - 0.5625) < 1e-9 && F.ratioValue("2.39") === 2.39 && F.ratioValue("wide") === 0);
check("picked by name", F.pickedFrame(sun.frames, "social", 2.39).name === "Social");
check("unpicked: the frame at the film's own ratio", F.pickedFrame(sun.frames, "", 0.5625).name === "Social");
check("unpicked and no match: Main", F.pickedFrame(sun.frames, "", 1.66).name === "Delivery");
check("a renamed pick falls back by ratio", F.pickedFrame(sun.frames, "Vertical", 0.5625).name === "Social");
check("frameRatio: no frames, the film's own", F.frameRatio({ frames: [] }, "", 1.85) === 1.85 && F.frameRatio({ frames: [] }, "", 0) === 2.39);

// 4. cards, engine card, portal line
cards = await C.allCards(env, { marks });
const sunCard = cards.find((c) => c.id === SUN);
check("on: the card carries the sheet", sunCard && same(sunCard.sheet.frames.map((f) => f.name), ["Delivery", "Social"]), JSON.stringify(sunCard && sunCard.sheet));
check("on: a project with no sheet carries an empty one", same(cards.find((c) => c.id === CHB).sheet, { frames: [], sensors: [] }));
const eng = JSON.parse(C.engineCard(sunCard));
check("the engine's card carries it", eng.sheet && eng.sheet.frames.length === 2 && eng.sheet.sensors[0].width === 36.7);
const door = await C.cardsDoor(env, ["cards"], "GET", async () => ({}), {});
const said = await door.json();
check("the cards door says the switch", said.frames === true && said.cards.find((c) => c.id === SUN).sheet.frames.length === 2, JSON.stringify(Object.keys(said)));
const front = { director: "x", producer: "y", ratio: 2.39, mark: {} };
check("portal: the ratio line follows the pick", Math.abs(C.layCardOnFront(front, sunCard, { frame: "Social", ratio: 2.39 }).ratio - 0.5625) < 1e-9);
check("portal: no pick, the frame at the film's ratio", C.layCardOnFront(front, sunCard, { frame: "", ratio: 2.39 }).ratio === 2.39);
check("portal: no sheet on the card, the film's own", C.layCardOnFront(front, { ...sunCard, sheet: undefined }, { frame: "Social", ratio: 1.85 }).ratio === 2.39);
check("portal: no film half, untouched", C.layCardOnFront(front, sunCard, null).ratio === 2.39);

// 5. New Shoot: the film's day is the new shoot's
{
  const NS = await import("./src/newshoot.js");
  const src = (await import("node:fs")).readFileSync(new URL("./src/newshoot.js", import.meta.url), "utf8");
  check("New Shoot: the day step carries the new shoot's key with the switch on", /shoot_key: "shoot-new", body: \{ date: start, name: label,\n\s+pickups/.test(src));
  check("New Shoot: the shoot's id goes in the body at run time", src.includes('shoot: String(need(p.shoot_key)).replace(/-/g, "")'));
  check("New Shoot: off, the Mac's words and payload stand", src.includes("add the section `\n        + `“${sectionName}” and a day on ${start} named “${label}”`"));
  check("New Shoot module loads", typeof NS.shootsCtx === "function");
}

// 6. the look
const views = [];
const readView = async (e, relay, ctx, card) => {
  views.push({ relay, sheet: Boolean(card.sheet) });
  if (!card.sheet) return { project: { ratio: 1.85 }, units: [{ id: "u1", label: "A-Cam", sensor_name: "Super 35", sensor_w: 24.89, sensor_h: 18.66 }, { id: "u2", label: "B-Cam" }] };
  return { project: { ratio: 2.39, frame: "Delivery" }, units: [{ id: "u1", label: "A-Cam", sensor_name: "Open Gate", sensor_w: 36.7, sensor_h: 25.54, sensor_sheet: true }, { id: "u2", label: "B-Cam" }] };
};
const before = [...env.BUCKET.m.keys()].sort().join() + [...env.BUCKET.m.values()].join().length;
const look = await F.framesLook(env, {}, readView, { cards: cards.filter((c) => c.id === SUN || c.id === CHB) });
const row = look.rows.find((r) => r.id === SUN);
check("the look reads each film twice: today, then with the sheet", views.length === 2 && !views[0].sheet && views[1].sheet, JSON.stringify(views));
check("the look: Daybreak's ratio would change 1.85 → 2.39 (Delivery)", row.ratioChanges && row.ratio.now === 1.85 && row.ratio.would === 2.39 && row.ratio.frame === "Delivery", JSON.stringify(row));
check("the look: A-Cam's sensor would be the sheet's", row.sensorChanges === 1 && row.sensors[0].fromSheet && row.sensors[0].would.startsWith("Open Gate"), JSON.stringify(row.sensors));
check("the look: a project with no film says so", look.rows.find((r) => r.id === CHB).film === false);
check("the look: counts", look.films === 1 && look.ratioChanges === 1 && look.sensorChanges === 1, JSON.stringify(look));
check("the look writes nothing", [...env.BUCKET.m.keys()].sort().join() + [...env.BUCKET.m.values()].join().length === before);

// the door
const reply = async (rest, method, body) => {
  const got = await F.framesDoor(env, rest, method, async () => body, {}, { readView });
  return got ? { status: got.status, body: await got.json() } : null;
};
check("door: GET the switch", (await reply(["studioframes"], "GET")).body.on === true);
check("door: the look answers", (await reply(["studioframes", "look"], "POST", { only: SUN })).body.projects === 1);
const off = await reply(["studioframes"], "PUT", { on: false, by: "check" });
check("door: PUT off is refused (fixed on)", off.body.on === true && /fixed on/.test(off.body.problem || "") && (await F.framesOn(env)).on === true);
check("door: wrong method", (await reply(["studioframes"], "DELETE")).status === 405);
check("door: not its own", (await reply(["studioshoots"], "GET")) === null);


console.log(`\nstudioframes: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
