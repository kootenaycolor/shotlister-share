#!/usr/bin/env node
/**
 * **Shoots in Studio** — `src/studioshoots.js` (stage 5 step 4, piece D).
 *
 * 1. The switch: off by default; off, no card carries shoots.
 * 2. His Shoots database: read once, kept ten minutes, a failed read keeps
 *    the last good one.
 * 3. A card's shoots: the console's picker's list (real Shoots rows, first to
 *    last, Wrapped / Next / Upcoming), never the project's own Shoot Dates.
 * 4. The cards door and the engine's card carry them while the switch is on.
 * 5. The look: per project, what each shoot would hold. Writes nothing.
 *
 *     node hub/studioshoots.mjs
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

const S = await import("./src/studioshoots.js");
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
const LC = "e6ee5875f5d789412e0b12538f71cfb5";
const CHB = "33333333333333333333333333333333";
const RELAY = "feedface000040008000000000000006";
const S1 = "4acab7b3-b555-897c-7c58-dce7762aca55";
const S2 = "50ad9510-5a93-869d-d1c9-7f9e1a45a05a";

const page = (id, title, start, end, status, project) => ({
  id, url: `https://app.notion.com/p/${id}`,
  properties: {
    Name: { type: "title", title: [{ plain_text: title }] },
    Dates: { date: { start, end } },
    Status: { select: status ? { name: status } : null },
    Project: { relation: [{ id: project }] },
    Crew: { relation: [] }, "Camera Spec Sheet": { relation: [] },
    "Shot List Section": { rich_text: [] }, "What Changes": { rich_text: [] },
  },
});
const SHOOTS = [
  page(S2, "Lets Bake - Shoot 2", "2026-10-06", null, "Wrapped", "e6ee5875-f5d7-8941-2e0b-12538f71cfb5"),
  page(S1, "Lets Bake - Shoot 1", "2026-07-09", null, "Wrapped", "e6ee5875-f5d7-8941-2e0b-12538f71cfb5"),
  page("44444444444444444444444444444444", "Call Her Back - Principal", "2026-11-02", "2026-11-04", "", CHB),
];
function notion(pages = SHOOTS) {
  const n = { calls: 0, broken: false, async post(path) { n.calls += 1; if (n.broken) throw new Error("Notion: down"); return { results: pages, has_more: false }; } };
  return n;
}

const env = { BUCKET: bucket() };
await env.BUCKET.put(`r/${LC}/record.json`, JSON.stringify({ page: LC, name: "Lets Bake", type: "Commercial", film: { relay: RELAY }, facts: { title: fact("Let's Bake"), status: fact("Post"), shoot_dates: fact("2026-10-06") } }));
await env.BUCKET.put(`r/${CHB}/record.json`, JSON.stringify({ page: CHB, name: "Call Her Back", type: "Narrative", facts: { title: fact("Call Her Back"), status: fact("Active"), shoot_dates: fact("2026-11-02/2026-11-04") } }));

// 1. the switch
check("off by default", (await S.shootsOn(env)).on === false);
let cards = await C.allCards(env, { marks: { of: async () => ({}), save: async () => {} } });
check("off: no card carries shoots", cards.every((c) => !("shoots" in c)), JSON.stringify(cards.map((c) => Object.keys(c))));
check("off: the engine's card has no shoots", !JSON.parse(C.engineCard(cards[0])).shoots);
const set = await S.setShoots(env, { on: true, by: "check" });
check("on", set.on === true && set.by === "check" && (await S.shootsOn(env)).on === true);

// 2. the Shoots database, kept
const n = notion();
const rows = await S.shootRows(env, { notion: n });
check("read once: rows by project", Object.keys(rows).length === 2 && rows[LC].length === 2, JSON.stringify(Object.keys(rows)));
await S.shootRows(env, { notion: n });
check("kept ten minutes: not read again", n.calls === 1, n.calls);
await S.shootRows(env, { notion: n, now: Date.now() + 11 * 60 * 1000 });
check("read again after ten minutes", n.calls === 2, n.calls);
n.broken = true;
const kept = await S.shootRows(env, { notion: n, force: true });
check("a failed read keeps the last good one", kept[LC] && kept[LC].length === 2);
n.broken = false;

// 3. a card's shoots
const tools = await S.shootTools();
const lc = S.cardShoots(rows, { id: LC, notion: LC, type: "Commercial", status: "Post", dates: "2026-10-06" }, tools, "2026-10-15");
check("Lets Bake: two shoots, first to last", lc.length === 2 && lc[0].id === S1.replace(/-/g, "") && lc[1].id === S2.replace(/-/g, ""), JSON.stringify(lc));
check("their words: Shoot 1, Shoot 2", lc[0].label === "Shoot 1" && lc[1].label === "Shoot 2" && lc[1].kind === "Shoot 2" && lc[1].n === 2, JSON.stringify(lc));
check("their dates and states", lc[0].start === "2026-07-09" && lc[1].when === "Oct 6" && lc.every((s) => s.state === "Wrapped"), JSON.stringify(lc));
const chb = S.cardShoots(rows, { id: CHB, notion: CHB, type: "Narrative", status: "Active", dates: "2026-11-02" }, tools, "2026-10-15");
check("one shoot: one, and Next", chb.length === 1 && chb[0].label === "Principal" && chb[0].state === "Next" && chb[0].when === "Nov 2–4", JSON.stringify(chb));
const none = S.cardShoots(rows, { id: "55555555555555555555555555555555", type: "Narrative", status: "Active", dates: "2026-12-01" }, tools, "2026-10-15");
check("the project's own Shoot Dates are never a shoot", same(none, []), JSON.stringify(none));
check("no tools, no shoots", same(S.cardShoots(rows, { id: LC, notion: LC }, null), []));

// 4. the cards and the engine's card
cards = await C.allCards(env, { marks: { of: async () => ({}), save: async () => {} } });
const lcCard = cards.find((c) => c.id === LC);
check("on: the card carries its shoots", lcCard && lcCard.shoots.length === 2 && lcCard.shoots[1].label === "Shoot 2", JSON.stringify(lcCard && lcCard.shoots));
check("on: a one-shoot project carries its one", cards.find((c) => c.id === CHB).shoots.length === 1);
const eng = JSON.parse(C.engineCard(lcCard));
check("the engine's card carries them", Array.isArray(eng.shoots) && eng.shoots.length === 2 && eng.shoots[0].start === "2026-07-09");
const door = await C.cardsDoor(env, ["cards"], "GET", async () => ({}), {});
const said = await door.json();
check("the cards door says the switch", said.shoots === true && said.cards.find((c) => c.id === LC).shoots.length === 2, JSON.stringify(Object.keys(said)));

// 5. the look
const views = [];
const readView = async (e, relay, ctx, card) => {
  views.push({ relay, shoots: card.shoots.length });
  return { scenes: [
    { id: "1", shoot: S1.replace(/-/g, ""), shootOwn: true }, { id: "2", shoot: S1.replace(/-/g, ""), shootOwn: false },
    { id: "7", shoot: S2.replace(/-/g, ""), shootOwn: false }],
    days: [{ label: "Day 1", date: "2026-07-09", shoot: S1.replace(/-/g, "") }, { label: "Day 1", date: "2026-10-06", shoot: S2.replace(/-/g, "") }] };
};
const before = [...env.BUCKET.m.keys()].sort().join();
const look = await S.shootsLook(env, {}, readView, { notion: n });
const row = look.rows.find((r) => r.id === LC);
check("the look: a picker for Lets Bake only", look.pickers === 1 && row.picker && !look.rows.find((r) => r.id === CHB).picker, JSON.stringify(look.rows));
check("the look reads the film with the shoots laid on", views.length === 1 && views[0].relay === RELAY && views[0].shoots === 2, JSON.stringify(views));
check("each shoot's scenes and days", row.shoots[0].scenes === 2 && row.shoots[0].ownScenes === 1 && row.shoots[1].scenes === 1 && same(row.shoots[1].days, ["Day 1 2026-10-06"]), JSON.stringify(row.shoots));
check("the look writes nothing", [...env.BUCKET.m.keys()].sort().join() === before);

// the door
const reply = async (rest, method, body) => {
  const got = await S.shootsDoor(env, rest, method, async () => body, {}, { readView, notion: n });
  return got ? { status: got.status, body: await got.json() } : null;
};
check("door: GET the switch", (await reply(["studioshoots"], "GET")).body.on === true);
const off = await reply(["studioshoots"], "PUT", { on: false, by: "check" });
check("door: PUT off is refused (fixed on)", off.body.on === true && /fixed on/.test(off.body.problem || "") && (await S.shootsOn(env)).on === true);
check("door: wrong method", (await reply(["studioshoots"], "DELETE")).status === 405);
check("door: the look answers", (await reply(["studioshoots", "look"], "POST", { only: LC })).body.projects === 1);
check("door: not its own", (await reply(["studiomodes"], "GET")) === null);


// ── 6. The portal follows the shoot fields (gap a, before landing) ──────────
{
  const F = await import("./src/front.js");
  const I1 = "b211a308026286ea6fba6436ae9b4891", I2 = "4acab7b3b555897c7c58dce7762aca55";
  const tabs = [
    { id: I1, slug: "shoot-1", name: "Shoot 1", status: "Wrapped", start: "2026-07-09", end: "", sections: ["Shoot 1 — July 9"], crew: [] },
    { id: I2, slug: "shoot-2", name: "Shoot 2", status: "Upcoming", start: "2026-10-06", end: "2026-10-07", sections: ["Shoot 2 - Style Server"], crew: [] },
  ];
  const days = [{ label: "Day 1", date: "2026-07-09" }, { label: "Day 2", date: "2026-10-06" }];
  // Let's Bake before conversion: sections and dates only.
  const before = [1, 2, 3, 4, 5, 6].map(() => ({ section: "Shoot 1 — July 9", day: "2026-07-09", archived: false, shoot: "" }))
    .concat([7, 8].map(() => ({ section: "Shoot 2 - Style Server", day: "2026-10-06", archived: false, shoot: "" })));
  const front = (list, ds = days, on = "shoot-2") => ({ scene_list: list, shoots: tabs, days: ds, shootOn: { slug: on } });
  check("portal: no fields, the section rule", !F.byFields(tabs, before, days) && F.shotListCount(front(before)) === 2);
  // After conversion, with scene 3 moved to Shoot 2 (section still says Shoot 1, now Unscheduled).
  const after = before.map((one, i) => ({ ...one, shoot: i < 6 ? I1 : I2 }));
  after[2] = { ...after[2], shoot: I2, day: "" };
  const dsAfter = [{ ...days[0], shoot: I1 }, { ...days[1], shoot: I2 }];
  check("portal: fields seen", F.byFields(tabs, after, dsAfter));
  check("portal: Shoot 2 counts by field (7, 8 and moved 3)", F.shotListCount(front(after, dsAfter)) === 3, F.shotListCount(front(after, dsAfter)));
  check("portal: Shoot 1 by field (5 left)", F.shotListCount(front(after, dsAfter, "shoot-1")) === 5);
  // Converted but identical: the same scenes as before for each shoot.
  const same = before.map((one, i) => ({ ...one, shoot: i < 6 ? I1 : I2 }));
  check("portal: conversion alone changes no count", F.shotListCount(front(same, dsAfter)) === F.shotListCount(front(before)) && F.shotListCount(front(same, dsAfter, "shoot-1")) === F.shotListCount(front(before, days, "shoot-1")));
  // A day that names Shoot 2 but is dated in July follows its field.
  const odd = [{ label: "Day 1", date: "2026-07-09", shoot: I1 }, { label: "Day 2", date: "2026-07-10", shoot: I2 }];
  const v = F.shotView({ ...front(same, odd), sections: [], documents: [], counts: {}, crew: [], shootOn: null }, "shoot-2");
  check("portal: Schedule days by field", v.days.length === 1 && v.days[0].label === "Day 2", JSON.stringify(v.days));
  const v0 = F.shotView({ ...front(before, days), sections: [], documents: [], counts: {}, crew: [], shootOn: null }, "shoot-2");
  check("portal: no fields, days by date as before", v0.days.length === 1 && v0.days[0].date === "2026-10-06");
  // A tab without ids (an older card) never goes by fields.
  check("portal: tabs without ids keep the old rule", !F.byFields(tabs.map(({ id, ...t }) => t), after, dsAfter));
  // One shoot: nothing narrows.
  check("portal: one shoot, no fields mode", !F.byFields(tabs.slice(0, 1), after, dsAfter));
  // An unscheduled scene with no field is the first shoot's; a stray date falls to the last shoot begun.
  check("portal: scene rule", F.sceneShootOf(tabs, { shoot: "" }, null) === "shoot-1" && F.dayShootOf(tabs, { date: "2026-12-01" }) === "shoot-2" && F.dayShootOf(tabs, { date: "2026-01-01" }) === "shoot-1");
  // The tidy keeps the fields.
  const t = F.tidy({ days: [{ label: "Day 1", date: "2026-07-09", shoot: I1 }, { label: "Day 2", date: "2026-07-10", shoot: "nope" }] });
  check("portal: tidy keeps a day's shoot id, drops junk", t.days[0].shoot === I1 && !("shoot" in t.days[1]));
}

console.log(`\nstudioshoots: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
