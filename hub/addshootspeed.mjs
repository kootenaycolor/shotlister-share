// Add Shoot's run in parallel (src/newshoot.js execute), its progress, the
// at-once start (src/askrunner.js) and the progress riding on the ask
// (src/later.js). No network: a Notion, a Drive, a Studio door and a portal
// that take a set time each, so what may overlap, and what may not, shows.
//
//     hub/../bundled run:  esbuild addshootspeed.mjs --bundle … && node
import { execute, groupOf } from "./src/newshoot.js";
import { startNow, KICKED } from "./src/askrunner.js";
import { runOne, heldItem } from "./src/later.js";
import { Handoff } from "./src/cloud.js";

let passed = 0, failed = 0;
const check = (ok, what) => { if (ok) passed++; else { failed++; console.log("FAIL", what); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// A Notion whose every call takes `ms`, and which remembers who started when.
function world({ ms = 60, driveMs = 200, fail = {}, handoff = false } = {}) {
  const log = [];
  const t0 = Date.now();
  const at = () => Date.now() - t0;
  let serial = 0;
  const call = async (what, extra) => {
    log.push({ what, start: at() });
    await sleep(ms);
    if (handoff) throw new Handoff("Notion refused before anything was written");
    if (fail[what]) throw new Error(`Notion: 400 — ${fail[what]}`);
    log.push({ what: what + " end", start: at() });
    return extra;
  };
  const n = {
    get: async (path) => call("get " + path, { properties: {} }),
    post: async (path, body) => {
      if (/query$/.test(path)) return call("query", { results: [], has_more: false });
      return call("post " + path, { id: `page${++serial}`, url: "" });
    },
    patch: async (path, body) => call("patch " + path, {}),
  };
  const deps = {
    n,
    drive: { make: async (plan) => { log.push({ what: "drive", start: at() }); await sleep(driveMs); log.push({ what: "drive end", start: at() }); return { made: ["k1", "k2"], already: [], failed: [] }; } },
    door: { shoot: async (relay, body) => { log.push({ what: "door", start: at(), body }); await sleep(ms); log.push({ what: "door end", start: at() }); return { steps: ["day added"] }; } },
    refresh: async () => { log.push({ what: "portal", start: at() }); await sleep(ms); log.push({ what: "portal end", start: at() }); return { ok: true }; },
  };
  return { deps, log, at };
}
const plan = () => ({
  project: "Test", drive: {},
  steps: [
    { kind: "crew-new", detail: "Add Jo to Crew", system: "NOTION", payload: { key: "crew-0", name: "Jo", project_id: "P", role: "", department: "", email: "", phone: "" } },
    { kind: "shoot-row", detail: "Create Test — Shoot 2", system: "NOTION", payload: { key: "shoot-new", title: "Test — Shoot 2", project_id: "P", start: "2026-11-03", end: "", status: "Upcoming", crew: [], crew_keys: ["crew-0"], section: "", changes: "", color: "" } },
    { kind: "sheet-retitle", detail: "Retitle the sheet", system: "NOTION", payload: { sheet_id: "S", title: "T", shoot_key: "shoot-new" } },
    { kind: "project-dates", detail: "Set dates", system: "NOTION", payload: { project_id: "P", start: "2026-11-03", end: "" } },
    { kind: "mkdir", detail: "2-logistics/shoot-2/", system: "DRIVE", payload: { key: "k1" } },
    { kind: "mkdir", detail: "2-logistics/shoot-2/a/", system: "DRIVE", payload: { key: "k2" } },
    { kind: "shotlister", detail: "In the film: add a day", system: "SHOTLISTER", payload: { relay: "r", shoot_key: "shoot-new", body: { date: "2026-11-03" } } },
    { kind: "manual", detail: "Add the scenes by hand", system: "SHOTLISTER", payload: "" },
    { kind: "portal", detail: "Update the portal", system: "PORTAL", payload: "" },
  ],
});
const first = (log, what) => log.find((x) => x.what === what);

// ── parallel: what overlaps ──
{
  const w = world();
  const seen = [];
  const out = {};
  const report = await execute(Object.assign(Object.create(w.deps), { out, progress: async (g) => seen.push(g) }), plan());
  const L = w.log;
  const drive = first(L, "drive"), row = L.find((x) => x.what.startsWith("post pages") && !x.what.endsWith(" end")), dates = first(L, "patch pages/P"), portal = first(L, "portal"), door = first(L, "door");
  check(drive && drive.start < 40, "the Drive folders start at once, beside the Notion steps");
  check(dates && dates.start >= first(L, "drive").start && dates.start < first(L, "door end").start, "the project's dates follow the new rows (so a refusing Notion can still hand over) but not the sheet or Studio");
  const crewEnd = L.filter((x) => x.what.startsWith("post pages") && !x.what.endsWith(" end")).map((x) => x.start);
  check(row && crewEnd.length === 2 && crewEnd[1] >= crewEnd[0] + 55, "the shoot row waits for the newcomer's Crew row");
  check(door.start >= crewEnd[1] + 55, "Studio's day waits for the shoot row (it is the shoot's own)");
  check(door.body.shoot === "page2", "…and is handed the new row's id");
  check(portal.start >= first(L, "door end").start && portal.start >= first(L, "patch pages/S").start, "the portal page waits for Notion and Studio");
  check(portal.start < first(L, "drive end").start + 5 || true, "…not for the Drive (not asserted either way)");
  const total = Math.max(...L.map((x) => x.start));
  check(total < 700, `the whole run took ${total} ms, not the sum of its steps`);
  check(/^Test: 8 steps done$/m.test(report) && /Still to do by hand:/.test(report) && /→ Add the scenes by hand/.test(report) && /· Shotlister: day added/.test(report), "the report reads as the Mac's: " + report.split("\n").join(" | "));
  check(out.steps.map((g) => g.id).join() === "notion,sheet,drive,studio,portal" && out.steps.every((g) => g.state === "done"), "every group done at the end, in his order");
  check(out.timings.length === 8 && out.timings.every((t) => t.ms >= 0), "a time for each step");
  const states = seen.map((g) => g.map((x) => x.state[0]).join(""));
  check(states[0].split("").every((c) => c === "w" || c === "r"), "progress is told before the first step ends");
  check(seen.length >= 5, "progress is told as groups start and end: " + seen.length);
}

// ── serial: the old way, step by step ──
{
  const w = world({ driveMs: 100 });
  const out = {};
  const report = await execute(Object.assign(Object.create(w.deps), { out, serial: true }), plan());
  const L = w.log;
  const starts = L.filter((x) => !x.what.endsWith(" end")).map((x) => x.what);
  const ends = Object.fromEntries(L.filter((x) => x.what.endsWith(" end")).map((x) => [x.what, x.start]));
  const portal = first(L, "portal"), drive = first(L, "drive");
  check(drive.start >= first(L, "patch pages/S").start, "serial: the Drive waits its turn after the sheet");
  check(portal.start >= ends["door end"], "serial: the portal is last");
  check(/8 steps done/.test(report), "serial: same report");
  check(starts.length > 0, "serial ran");
}

// ── the same words either way ──
{
  const a = await execute(Object.assign(Object.create(world({ ms: 5, driveMs: 5 }).deps), {}), plan());
  const b = await execute(Object.assign(Object.create(world({ ms: 5, driveMs: 5 }).deps), { serial: true }), plan());
  check(a === b, "parallel and serial give the same report, word for word");
}

// ── a step that fails: the others still run, and it is said in the plan's order ──
{
  const w = world({ ms: 10, driveMs: 10, fail: { "patch pages/S": "Sheet gone" } });
  const out = {};
  const report = await execute(Object.assign(Object.create(w.deps), { out }), plan());
  check(/⚠ Retitle the sheet — Notion said: Sheet gone/.test(report), "a Notion refusal is said in Notion's words");
  check(/7 steps done/.test(report), "the other seven still ran");
  check(out.steps.find((g) => g.id === "sheet").state === "fail" && out.steps.find((g) => g.id === "portal").state === "done", "the sheet group failed, the portal group still ran");
  check(out.failed.length === 1, "failed lists the one");
}
{
  // a row that never got made: what depends on it is skipped and says why
  const w = world({ ms: 10, driveMs: 10, fail: { "post pages": "No" } });
  const out = {};
  const report = await execute(Object.assign(Object.create(w.deps), { out }), plan());
  check(/skipped — a newcomer's Crew row was not made/.test(report) && /skipped — the new shoot's row was not made/.test(report), "dependents are skipped and say what was missing");
}
{
  // Notion refused before anything was written: the Mac's to do instead
  const w = world({ ms: 5, driveMs: 5, handoff: true });
  let threw = false;
  try { await execute(Object.assign(Object.create(w.deps), {}), plan()); } catch (e) { threw = e instanceof Handoff; }
  check(threw, "a Notion that refuses first still hands the whole ask to the Mac");
}
check(groupOf("mkdir") === "drive" && groupOf("shotlister") === "studio" && groupOf("portal") === "portal" && groupOf("sheet-copy") === "sheet" && groupOf("shoot-row") === "notion", "step kinds map to the sheet's groups");

// ── the at-once start ──
check(KICKED.has("run_new_shoot") && !KICKED.has("create_project"), "only Add Shoot is started at once");
function box(list) {
  const m = { list: list.map((x) => ({ ...x })) };
  m.asksOf = async () => ({ list: m.list.map((x) => ({ ...x })) });
  m.changeAsks = async (e, change) => { const o = change(m.list.map((x) => ({ ...x }))); if (o.list) m.list = o.list; return o; };
  return m;
}
{
  const held = heldItem({ id: "0123456789ab", method: "run_new_shoot", args: ["Test", {}], state: "pending" });
  const m = box([held]);
  let ran = 0, waited = 0;
  const run = async (env, mb, id) => { ran++; await sleep(20); await mb.changeAsks(env, (l) => ({ list: l.map((x) => (x.id === id ? { ...x, state: "done", result: { ok: true } } : x)) })); };
  const got = await startNow({}, m, { waitUntil: (p) => { waited++; } }, "0123456789ab", { run });
  check(ran === 1 && waited === 1 && got.item.state === "done", "a start runs the held ask inside the request and answers it finished");
  const again = await startNow({}, m, null, "0123456789ab", { run });
  check(ran === 1 && again.item.state === "done", "a second start finds it done and runs nothing");
  const started = box([{ ...held, later: { ...held.later, started: new Date().toISOString() } }]);
  const taken = await startNow({}, started, null, "0123456789ab", { run });
  check(ran === 1 && taken.item.state === "working", "an ask the minute has already started is not started again");
  const other = box([heldItem({ id: "aaaaaaaaaaaa", method: "create_project", args: [], state: "pending" })]);
  check((await startNow({}, other, null, "aaaaaaaaaaaa", { run })).refusal, "other asks are left for the minute");
  check((await startNow({}, box([]), null, "bbbbbbbbbbbb", { run })).refusal === "No such ask.", "an ask that is not there is said so");
  const boom = box([held]);
  const fails = await startNow({}, boom, null, "0123456789ab", { run: async () => { throw new Error("down"); } });
  check(fails.item && fails.item.state === "working", "a run that throws never throws at the asker: it is written on the ask, and the minute is the way back");
}

// ── progress rides on the ask ──
{
  const list = [{ ...heldItem({ id: "0123456789ab", method: "run_new_shoot", args: ["Test", {}], state: "pending" }) }];
  const m = { list, asksOf: async () => ({ list: m.list.map((x) => ({ ...x })) }), changeAsks: async (e, change) => { const o = change(m.list.map((x) => ({ ...x }))); if (o.list) m.list = o.list; return o; } };
  const seen = [];
  const answer = async (env, method, args) => {
    await env.ASK_PROGRESS([{ id: "notion", label: "Shoot in Notion", state: "run" }]);
    seen.push(m.list[0].progress && m.list[0].progress.groups[0].state);
    return { state: "done", result: { ok: true, report: "x" } };
  };
  const out = await runOne({}, m, "0123456789ab", { answer });
  check(seen[0] === "run", "a run's progress is on the ask while it works");
  check(out.state === "done" && out.progress && out.progress.groups.length === 1, "…and stays on the finished ask");
  const other = [{ ...heldItem({ id: "aaaaaaaaaaaa", method: "create_project", args: [], state: "pending" }) }];
  const m2 = { list: other, asksOf: async () => ({ list: other }), changeAsks: async (e, change) => { const o = change(m2.list.map((x) => ({ ...x }))); if (o.list) m2.list = o.list; return o; } };
  let had = null;
  await runOne({}, m2, "aaaaaaaaaaaa", { answer: async (env) => { had = typeof env.ASK_PROGRESS; return { state: "done", result: 1 }; } });
  check(had === "undefined", "other asks are given no progress line");
}

console.log(`addshootspeed: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
