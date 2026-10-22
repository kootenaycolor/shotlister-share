#!/usr/bin/env node
/**
 * **The portal follows the modes** (stage 5 step 5, the portal piece): the
 * rules in `src/portalmodes.js` and the rail `pages.js` draws from them, on a
 * bucket held in memory. No worker, no network.
 *
 * - which pages each mode takes off, his boards with References;
 * - switch off: nothing is left out, whatever the record says;
 * - switch on: each Type's start, a Job's none, a project's own changes, a
 *   film found by its relay id;
 * - the rail leaves the pages out, keeps the rest, and keeps the row
 *   somebody is standing on; the page itself still draws;
 * - the look lists what would go and writes nothing;
 * - Shared / Not Shared: refused while the switch is off.
 *
 *     node hub/portalmodes.mjs        (PLANT=1 plants a wrong answer, to see it fail)
 */
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);

const pm = await import("./src/portalmodes.js");
const { tidy, shotView } = await import("./src/front.js");
const { homeBody, recordBody } = await import("./src/pages.js");
const { emptyVisible } = await import("./src/films.js");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(84)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sorted = (a) => [...a].sort();

// ---- a bucket in memory
function bucketOf(objects) {
  const writes = [];
  return {
    writes,
    objects,
    async get(k) { return objects.has(k) ? { json: async () => JSON.parse(objects.get(k)), text: async () => objects.get(k) } : null; },
    async head(k) { return objects.has(k) ? {} : null; },
    async put(k, v) { writes.push(k); objects.set(k, String(v)); },
    async delete(k) { writes.push(`-${k}`); objects.delete(k); },
    async list({ prefix = "", delimiter } = {}) {
      const keys = [...objects.keys()].filter((k) => k.startsWith(prefix));
      if (!delimiter) return { objects: keys.map((key) => ({ key })), delimitedPrefixes: [], truncated: false };
      const pre = new Set(keys.map((k) => k.slice(prefix.length)).filter((r) => r.includes(delimiter)).map((r) => prefix + r.split(delimiter)[0] + delimiter));
      return { objects: [], delimitedPrefixes: [...pre], truncated: false };
    },
  };
}

const NARR = "a1".repeat(16), COMM = "c0".repeat(16), JOB = "d0".repeat(16), PERS = "e0".repeat(16), MINE = "f0".repeat(16);
const RELAY_C = "cc".repeat(16);
const record = (page, type, extra = {}) => JSON.stringify({ page, name: `${type} one`, type, facts: { type: { value: type, v: 1 } }, film: null, ...extra });
const objects = new Map([
  [`r/${NARR}/record.json`, record(NARR, "Narrative")],
  [`r/${COMM}/record.json`, record(COMM, "Commercial", { film: { relay: RELAY_C, title: "Comm" } })],
  [`r/${JOB}/record.json`, record(JOB, "Commercial", { job: true })],
  [`r/${PERS}/record.json`, record(PERS, "Personal")],
  // His own change: a Commercial with Diagram on and Schedule off.
  [`r/${MINE}/record.json`, record(MINE, "Commercial", { facts: { type: { value: "Commercial", v: 1 }, modes: { value: { diagram: true, schedule: false }, v: 2 } } })],
  ["s/ids.json", JSON.stringify({ notion: {}, alias: { [RELAY_C]: COMM } })],
  [`p/${RELAY_C}/manifest.json`, JSON.stringify({ format: 1, title: "Comm" })],
  [`p/${RELAY_C}/front.json`, JSON.stringify({ version: 1, sections: [
    { slug: "night-look", name: "Night Look", type: "board", share: "link" },
    { slug: "call-sheet", name: "Call Sheet", type: "page", source: "here" }] })],
]);
const env = { BUCKET: bucketOf(objects) };

// ---- 1. which pages each mode takes off
check("Shot List off takes the Shot List and the Script", same(sorted(pm.pagesOff({}, ["locations", "references", "schedule", "diagram"])), ["script", "shotlist"]));
check("Locations off takes Locations", same(pm.pagesOff({}, ["shot_list", "references", "schedule", "diagram"]), ["locations"]));
check("References off takes Reference Images and his boards, not his pages",
  same(pm.pagesOff({ sections: [{ slug: "night-look", type: "board" }, { slug: "call-sheet", type: "page" }] }, ["shot_list", "locations", "schedule", "diagram"]), ["boards", "night-look"]));
check("Schedule off takes the Schedule", same(pm.pagesOff({}, ["shot_list", "locations", "references", "diagram"]), ["schedule"]));
check("Diagram off takes the Diagrams", same(pm.pagesOff({}, ["shot_list", "locations", "references", "schedule"]), ["diagrams"]));
check("all five on takes nothing", same(pm.pagesOff({ sections: [{ slug: "b", type: "board" }] }, ["shot_list", "locations", "references", "schedule", "diagram"]), []));
check("People, Documents, the bible and the spec sheet belong to no mode",
  ["people", "documents", "bible", "camera", "call-sheet"].every((at) => pm.modeOfPage(at, "page") === ""));

// ---- 2. switch off: nothing left out
let got = await pm.modesOffFor(env, JOB, {});
check("off until thrown", (await pm.portalModesOn(env)).on === false && got.on === false && same(got.off, []), JSON.stringify(got));

// ---- 3. switch on
await pm.setPortalModes(env, { on: true, by: "check" });
check("the switch can be thrown", (await pm.portalModesOn(env)).on === true);
got = await pm.modesOffFor(env, NARR, {});
check("a Narrative leaves nothing out", same(got.off, []), JSON.stringify(got));
got = await pm.modesOffFor(env, RELAY_C, { sections: [{ slug: "night-look", type: "board" }] });
check("a Commercial, found by its film's id, leaves out Locations and Diagrams", same(sorted(got.off), ["diagrams", "locations"]), JSON.stringify(got));
got = await pm.modesOffFor(env, PERS, {});
check("a Personal leaves out Locations, Schedule and Diagrams", same(sorted(got.off), ["diagrams", "locations", "schedule"]), JSON.stringify(got));
got = await pm.modesOffFor(env, JOB, { sections: [{ slug: "night-look", type: "board" }] });
const PLANT = process.env.PLANT === "1";
check("a Job leaves out every mode's page, his boards too",
  same(sorted(got.off), PLANT ? ["boards"] : ["boards", "diagrams", "locations", "night-look", "schedule", "script", "shotlist"]), JSON.stringify(got));
got = await pm.modesOffFor(env, MINE, {});
check("his own changes count (Diagram on, Schedule off)", same(sorted(got.off), ["locations", "schedule"]), JSON.stringify(got));
got = await pm.modesOffFor(env, "99".repeat(16), {});
check("a portal no record names leaves nothing out", got.on === true && same(got.off, []), JSON.stringify(got));

// ---- 4. the rail
const FRONT = tidy({
  version: 1, logline: "x", counts: { scenes: 3, locations: 2, days: 1, boards: 2, diagrams: 1 },
  sections: [{ slug: "night-look", name: "Night Look", type: "board", share: "link" }, { slug: "call-sheet", name: "Call Sheet", type: "page", source: "here", body: "Be there." }],
  crew: [{ name: "Ana", role: "Gaffer" }],
});
FRONT.live = true;
FRONT.scripts = [{ stem: "ab".repeat(16), name: "Draft 1" }];
const railOf = (html) => {
  const nav = (html.match(/<nav class="rail"[\s\S]*?<\/nav>/) || [""])[0];
  return [...nav.matchAll(/data-key="([^"]+)"/g)].map((m) => m[1]);
};
const base = `/f/${RELAY_C}`;
const who = { email: "owner@example.com", via: "access" };
let rail = railOf(homeBody(base, "Comm", "editor", who, { ...FRONT, modesOff: [] }, false, false, emptyVisible(), true));
check("switch off: the rail has Locations, Diagrams, Schedule and the Shot List",
  ["locations", "diagrams", "schedule", "shotlist", "boards", "night-look"].every((k) => rail.includes(k)), rail.join(","));
const off = ["locations", "diagrams"];
rail = railOf(homeBody(base, "Comm", "editor", who, { ...FRONT, modesOff: off }, false, false, emptyVisible(), true));
check("a Commercial's rail leaves out Locations and Diagrams", !rail.includes("locations") && !rail.includes("diagrams"), rail.join(","));
check("…and keeps the Shot List, Schedule, Reference Images, his board and his page",
  ["shotlist", "schedule", "boards", "night-look", "call-sheet"].every((k) => rail.includes(k)), rail.join(","));
rail = railOf(homeBody(base, "Job", "viewer", { email: null, via: "link", key: "k" }, { ...FRONT, modesOff: pm.pagesOff(FRONT, []) }, true, false, emptyVisible(), false));
check("a Job's rail, as a link holder sees it, has no mode's page", ["shotlist", "script", "locations", "diagrams", "schedule", "boards", "night-look"].every((k) => !rail.includes(k)), rail.join(","));
check("…and still has People and his page", rail.includes("people") && rail.includes("call-sheet"), rail.join(","));
const page = recordBody(base, "Comm", "viewer", { email: null, via: "link", key: "k" }, { ...FRONT, modesOff: ["call-sheet"] }, "call-sheet", true, null, false, emptyVisible(), false);
rail = railOf(page);
check("the row somebody is standing on stays", rail.includes("call-sheet"), rail.join(","));
check("…and the page itself still draws", /Call Sheet/.test(page.replace(/<nav class="rail"[\s\S]*?<\/nav>/, "")), page.slice(0, 200));

// ---- 5. the look writes nothing
const before = env.BUCKET.writes.length;
const look = await pm.portalModesLook(env, null, { readFront: async (e, p) => tidy(JSON.parse(objects.get(`p/${p}/front.json`) || "{}")) });
const rowC = look.rows.find((r) => r.id === COMM);
check("the look reads every record", look.projects === 5, JSON.stringify(look).slice(0, 300));
check("…finds the Commercial's portal by its film", rowC && rowC.portal === RELAY_C, JSON.stringify(rowC));
check("…and says Locations and Diagrams would go from its sidebar",
  rowC && same(rowC.hides.map((h) => h.at).sort(), ["diagrams", "locations"]) && rowC.hides.every((h) => h.mode), JSON.stringify(rowC && rowC.hides));
check("…and writes nothing", env.BUCKET.writes.length === before, env.BUCKET.writes.slice(before).join(","));

// ---- 6. Shared refused while the switch is off
got = await pm.setPortalModes(env, { on: false, by: "check" });
check("the switch can't be turned off any more (fixed on)", got.on === true && /fixed on/.test(got.problem || ""), JSON.stringify(got));
got = await pm.portalShared(env, COMM, "yes");
check("an answer that is not on or off is refused", got.ok === false, JSON.stringify(got));
got = await pm.portalState(env, "77".repeat(16));
check("a project with no portal: not shared, 0 people, 0 pages, no link",
  got.ok === true && got.shared === false && got.people === 0 && got.pages === 0 && got.link === "", JSON.stringify(got));

// ---- 7. the one shoot picker
const SHOOTS = tidy({
  version: 1, logline: "x",
  shoots: [
    { slug: "shoot-1", name: "Shoot 1", base: "Shoot 1", start: "2026-07-09", end: "2026-07-09", status: "Wrapped" },
    { slug: "shoot-2", name: "Style Server", base: "Shoot 2", start: "2026-10-06", end: "2026-10-07", status: "Upcoming" },
    { slug: "shoot-3", name: "Pickup", base: "Shoot 3", start: "2026-11-20", end: "2026-11-20", status: "Upcoming" },
  ],
  sections: [{ slug: "shoot-2-details", name: "Shoot 2 Details", type: "page", source: "here", shoots: ["shoot-2"] }],
});
const pickOf = (html) => (html.match(/<div class="shootpick[\s\S]*?<\/details>[\s\S]*?<\/div>/) || [""])[0];
const drawn = (front, slug) => {
  const view = shotView(front, slug);
  const b = slug ? `/f/${RELAY_C}/shoots/${slug}` : `/f/${RELAY_C}`;
  return pickOf(homeBody(b, "Lets Bake", "viewer", { email: null, via: "link", key: "k" }, view, true, false, emptyVisible(), false));
};
let pick = drawn({ ...SHOOTS, portalmodes: false }, "shoot-2");
check("switch off: the old switcher, no All Shoots", /class="shootpick"/.test(pick) && !/pick5/.test(pick) && !/All Shoots/.test(pick), pick.slice(0, 200));
const on5 = { ...SHOOTS, portalmodes: true };
pick = drawn(on5, "shoot-2");
const summary = (pick.match(/<summary[\s\S]*?<\/summary>/) || [""])[0];
check("on: the picker says Style Server · Shoot 2 · Oct 6–7 · Next",
  /pick5/.test(pick) && /<b>Style Server<\/b><span>Shoot 2 · Oct 6–7<\/span><i class="tag next">Next<\/i>/.test(summary), summary);
const rows = [...pick.matchAll(/<a class="shootrow[^"]*"[^>]*href="([^"]+)"><b>([^<]+)<\/b><span>([^<]*)<\/span>(?:<i class="tag[^"]*">([^<]+)<\/i>)?/g)].map((m) => [m[2], m[3], m[4] || "", m[1]]);
check("the list: All Shoots first, then each shoot with its dates and where it stands", same(rows.map((r) => r.slice(0, 3)), [
  ["All Shoots", "3 shoots", ""], ["Shoot 1", "Jul 9", "Wrapped"], ["Style Server", "Shoot 2 · Oct 6–7", PLANT ? "Upcoming" : "Next"], ["Pickup", "Shoot 3 · Nov 20", "Upcoming"]]), JSON.stringify(rows));
check("each shoot keeps its own address; All Shoots has its own",
  same(rows.map((r) => r[3]), [`/f/${RELAY_C}/shoots/all-shoots`, `/f/${RELAY_C}/shoots/shoot-1`, `/f/${RELAY_C}/shoots/shoot-2`, `/f/${RELAY_C}/shoots/shoot-3`]), JSON.stringify(rows.map((r) => r[3])));
const steps = [...pick.matchAll(/<a class="shootstep" href="([^"]+)"/g)].map((m) => m[1]);
check("‹ › step to Shoot 1 and Pickup", same(steps, [`/f/${RELAY_C}/shoots/shoot-1`, `/f/${RELAY_C}/shoots/shoot-3`]), JSON.stringify(steps));
check("the shoot it is on is marked", /class="shootrow on" aria-current="true" href="[^"]*shoot-2"/.test(pick));
pick = drawn(on5, "all-shoots");
check("All Shoots: the picker says All Shoots · 3 shoots, no tag", /<summary aria-label="Shoots"><b>All Shoots<\/b><span>3 shoots<\/span><svg/.test(pick), (pick.match(/<summary[\s\S]*?<\/summary>/) || [""])[0]);
check("…‹ is spent, › goes to Shoot 1", /shootstep shootend/.test(pick.split("<details")[0]) && /<a class="shootstep" href="[^"]*shoot-1"/.test(pick.split("</details>")[1]));
const allView = shotView(on5, "all-shoots");
check("…and nothing is narrowed (every shoot's page is there)", allView.shootOn.all === true && allView.sections.some((x) => x.slug === "shoot-2-details"));
check("with the switch off, all-shoots is the lead shoot, as any unknown address", shotView({ ...SHOOTS, portalmodes: false }, "all-shoots").shootOn.slug === "shoot-2");
pick = drawn(on5, "");
check("the film's own address is the next shoot, as today", /<summary aria-label="Shoots"><b>Style Server<\/b>/.test(pick));
const one = tidy({ version: 1, shoots: [{ slug: "shoot-1", name: "Shoot 1", start: "2026-07-09", status: "" }] });
check("one shoot: no picker", drawn({ ...one, portalmodes: true }, "shoot-1") === "");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
