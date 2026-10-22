// The asks the server answers after its reply (src/later.js): which are held,
// when the minute starts them, that a writer is started once and a cut-off one
// is answered as failed rather than run twice, that a reader is started again,
// and that one the server turns out not to take goes back to the Mac.
//
//     node hub/later.mjs
import { WRITES, READS, STALE_MS, due, heldItem, answered, runOne, onLaterTimer } from "./src/later.js";

let passed = 0, failed = 0;
const check = (ok, what) => { if (ok) passed++; else { failed++; console.log("FAIL", what); } };

// A mailbox in memory, compare-and-set like the bucket's.
function box(list) {
  const m = { list: list.map((x) => ({ ...x })), writes: 0 };
  m.asksOf = async () => ({ list: m.list.map((x) => ({ ...x })) });
  m.changeAsks = async (env, change) => { const out = change(m.list.map((x) => ({ ...x }))); if (out.list) { m.list = out.list; m.writes++; } return out; };
  return m;
}
const T0 = Date.parse("2026-10-13T21:00:00Z");
const ask = (method, extra = {}) => ({ id: method.slice(0, 6) + Math.random().toString(16).slice(2, 8), method, args: ["Stage 4 Test"], by: "phone", asked: new Date(T0).toISOString(), state: "pending", ...extra });

check(WRITES.has("create_project") && WRITES.has("run_new_shoot") && WRITES.has("film_backup"), "the three that outlast the phone's wait are writers");
check(READS.has("plan_new_shoot") && !WRITES.has("plan_new_shoot"), "New Shoot's plan is a reader");

const held = heldItem(ask("run_new_shoot"), new Date(T0));
check(held.state === "working" && held.by_done === "server" && held.later.at, "held: working, by the server — the Mac claims only pending");

// due
check(due([held], T0).start.length === 1, "a held writer not yet started is due");
const startedW = { ...held, later: { ...held.later, started: new Date(T0).toISOString() } };
check(due([startedW], T0 + 60e3).start.length === 0, "a started writer is never started again");
check(due([startedW], T0 + STALE_MS + 1).stale.length === 1 && due([startedW], T0 + STALE_MS + 1).start.length === 0, "a writer cut off is stale, not started again");
const r = heldItem(ask("plan_new_shoot"), new Date(T0));
const startedR = { ...r, later: { ...r.later, started: new Date(T0).toISOString() } };
check(due([startedR], T0 + 30e3).start.length === 0, "a reader just started is left to finish");
check(due([startedR], T0 + 91e3).start.length === 1, "a reader cut off is started again");
check(due([ask("run_new_shoot")], T0).start.length === 0, "a pending ask (the Mac's) is never the minute's");
check(due([{ ...held, by_done: "mac" }], T0).start.length === 0, "a working ask the Mac claimed is never the minute's");
check(due([{ ...held, later: undefined }], T0).start.length === 0, "a working ask not held for later is never the minute's");

// answered
const done = answered(held, { state: "done", result: "Made." }, new Date(T0));
check(done.state === "done" && done.result === "Made." && done.done_at && done.by_done === "server", "done: the answer on the ask, by the server");
const fail = answered(held, { state: "failed", error: "no" }, new Date(T0));
check(fail.state === "failed" && fail.error === "no", "failed: the error on the ask");
const back = answered(held, null, new Date(T0));
check(back.state === "pending" && !("by_done" in back) && !("claimed_at" in back), "not the server's after all: back to pending, for the Mac");

// runOne: once, even with two minutes at it
{
  const m = box([held]);
  let calls = 0;
  const answer = async () => { calls++; return { state: "done", result: "ok" }; };
  const [a, b] = await Promise.all([runOne({}, m, held.id, { answer }), runOne({}, m, held.id, { answer })]);
  check(calls === 1, `two minutes at one writer start it once (${calls})`);
  check(m.list[0].state === "done" && m.list[0].result === "ok" && m.list[0].later.started && m.list[0].later.finished, "…and its answer is kept");
}
// runOne: a throw is a failure, said
{
  const m = box([held]);
  await runOne({}, m, held.id, { answer: async () => { throw new Error("Notion said no"); } });
  check(m.list[0].state === "failed" && m.list[0].error === "Notion said no", "a run that throws is answered as failed, in its words");
}
// runOne: a Handoff (null) goes to the Mac
{
  const m = box([held]);
  await runOne({}, m, held.id, { answer: async () => null });
  check(m.list[0].state === "pending", "a run the server hands on goes back to pending");
}
// onLaterTimer: stale writers answered as failed, due ones started in turn
{
  const old = { ...startedW, later: { ...startedW.later, started: new Date(Date.now() - STALE_MS - 5000).toISOString() } };
  const fresh = heldItem(ask("create_project"), new Date());
  const m = box([old, fresh, ask("film_backup")]);
  const seen = [];
  const got = await onLaterTimer({}, m, { answer: async (env, method) => { seen.push(method); return { state: "done", result: method }; } });
  check(m.list[0].state === "failed" && /interrupted/.test(m.list[0].error), "the minute answers a cut-off writer as failed");
  check(JSON.stringify(seen) === '["create_project"]', `the minute starts only the due one (${seen})`);
  check(m.list[1].state === "done" && m.list[2].state === "pending", "…answers it, and leaves the Mac's pending ask alone");
  check(got.started.length === 1 && got.stale.length === 1, "and says what it did");
}

console.log(`later: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
