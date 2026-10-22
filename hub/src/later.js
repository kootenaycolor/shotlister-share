/**
 * **Asks the server answers after it has replied** (2026-10-13, Projects
 * Console without the Mac, stage 4).
 *
 * The phone sends an ask and waits **20 seconds** for the first reply
 * (`HubClient.timeout`), then polls `GET /console/studio/asks/<id>` until its
 * own deadline (New Shoot's run 240 s, New Project 180 s). An ask answered on
 * arrival (`answerHere`) is answered inside that first reply — and a few of
 * them take longer than 20 s on the server: a whole New Project (≈27 s,
 * measured live 2026-10-13), a New Shoot's run (a minute and more: Notion
 * rows, two shoots' Drive folders, the film, the portal), a film's backup. The
 * phone hangs up, the worker's request is cancelled, and the work stops
 * half-way with nothing kept to say so. Found live on the first real New
 * Shoot: the Notion rows and half the Drive folders were made, the rest not.
 *
 * So these are not answered in the reply. The ask is kept **working, by the
 * server** (`later: {at}`), the reply goes back at once, and the worker's own
 * minute (`timer.js`, which may run for many minutes) does it and writes the
 * answer on the ask, where the phone's poll finds it. The Mac claims only
 * `pending` asks, so it never sees one of these. If the server turns out not
 * to take it after all (its switch, or a `Handoff` — the Mac's disk is
 * needed), the ask goes back to `pending`, and the Mac answers it as before.
 *
 * - **Writers** (`WRITES`) are started only by the minute, once. A run that
 *   never finished (the worker was stopped) is answered as failed after
 *   `STALE_MS`, never started again: half a New Project run twice is worse.
 * - **Readers** (`READS`, New Shoot's plan, ≈11–18 s) are started at once
 *   beside the reply (`ctx.waitUntil`, 30 s), and the minute starts them
 *   again if that was cut off: reading twice is harmless.
 */

import { answerHere, cloudMethodsNow } from "./cloud.js";
import { STEP6_LATER_WRITES, STEP6_LATER_READS } from "./step6.js";

import { LATER_WRITES as BIGMOVE_LATER_WRITES } from "./bigmoves.js";

export const WRITES = new Set(["create_project", "run_new_shoot", "film_backup", ...STEP6_LATER_WRITES, ...BIGMOVE_LATER_WRITES]);
export const READS = new Set(["plan_new_shoot", ...STEP6_LATER_READS]);
/** A started run with no answer after this long was cut off. */
export const STALE_MS = 10 * 60 * 1000;
/** A reader started beside the reply and not answered after this is started again. */
const READ_RETRY_MS = 90 * 1000;

/** Whether this ask is to be answered later by the server: one of these, and
 * one the server answers right now (its switch on — `cloudMethodsNow`). */
export async function answeredLater(env, method) {
  if (!WRITES.has(method) && !READS.has(method)) return false;
  return (await cloudMethodsNow(env)).includes(method);
}

/** The ask as it is kept until the server has answered it. */
export function heldItem(item, now = new Date()) {
  return { ...item, state: "working", by_done: "server", claimed_at: now.toISOString(), later: { at: now.toISOString() } };
}

/**
 * Which held asks the minute should start now: writers never started,
 * readers never started or started long enough ago to have been cut off.
 * `stale` are writers started and never answered — to be answered as failed.
 */
export function due(list, now = Date.now()) {
  const start = [];
  const stale = [];
  for (const x of list || []) {
    if (!x || x.state !== "working" || x.by_done !== "server" || !x.later) continue;
    const started = x.later.started ? Date.parse(x.later.started) : 0;
    if (WRITES.has(x.method)) {
      if (!started) start.push(x);
      else if (now - started > STALE_MS) stale.push(x);
    } else if (READS.has(x.method)) {
      if (!started || now - started > READ_RETRY_MS) start.push(x);
    }
  }
  return { start, stale };
}

/** The answer written on the ask: done or failed, or back to the Mac. */
export function answered(item, here, now = new Date()) {
  const next = { ...item, later: { ...item.later, finished: now.toISOString() } };
  if (!here && item.here_only) {
    // Sent by the Mac's router to be the server's or nobody's: declined, so
    // the Mac does it itself (routerasks.js) — never left for its mailbox.
    next.state = "declined";
    next.done_at = now.toISOString();
    return next;
  }
  if (!here) {
    // Not the server's after all: the Mac's, as if it had just arrived.
    next.state = "pending";
    delete next.by_done;
    delete next.claimed_at;
    return next;
  }
  next.state = here.state;
  next.done_at = now.toISOString();
  if (here.state === "done") next.result = here.result === undefined ? null : here.result;
  else next.error = here.error;
  return next;
}

/**
 * Start one held ask: claim it (compare-and-set on the mailbox, so two
 * minutes never both start it), answer it, write the answer. `mailbox` is
 * studio.js's `{ asksOf, changeAsks }`; `answer` is `answerHere` (passed in
 * by the checks).
 */
export async function runOne(env, mailbox, id, { answer = answerHere, now = () => new Date() } = {}) {
  let claimed = null;
  await mailbox.changeAsks(env, (list) => {
    const at = list.findIndex((x) => x.id === id);
    if (at < 0) return { list };
    const x = list[at];
    const { start } = due([x], now().getTime());
    if (!start.length) return { list };
    claimed = { ...x, later: { ...x.later, started: now().toISOString(), tries: (x.later.tries || 0) + 1 } };
    const next = list.slice();
    next[at] = claimed;
    return { list: next };
  });
  if (!claimed) return null;
  let here;
  try {
    // A run that can say how far it is (Add Shoot's steps) writes it on the
    // ask, where the poll finds it beside the state.
    const runEnv = claimed.method === "run_new_shoot"
      ? { ...env, ASK_PROGRESS: async (groups) => {
        await mailbox.changeAsks(env, (list) => {
          const at = list.findIndex((x) => x.id === id);
          if (at < 0 || list[at].state !== "working") return { list };
          const next = list.slice();
          next[at] = { ...list[at], progress: { at: new Date().toISOString(), groups } };
          return { list: next };
        });
      } }
      : env;
    here = await answer(runEnv, claimed.method, claimed.args);
  } catch (e) {
    here = { state: "failed", error: String((e && e.message) || e || "It failed, and did not say why.").slice(0, 2000) };
  }
  let out = null;
  await mailbox.changeAsks(env, (list) => {
    const at = list.findIndex((x) => x.id === id);
    if (at < 0) return { list };
    // A reader started twice: the first answer stands.
    if (list[at].state !== "working") return { list };
    out = answered(list[at], here, now());
    const next = list.slice();
    next[at] = out;
    return { list: next };
  });
  return out;
}

/** The minute: start what is due, one after another; answer the stale as failed. */
export async function onLaterTimer(env, mailbox, opts = {}) {
  const { list } = await mailbox.asksOf(env);
  const { start, stale } = due(list, Date.now());
  if (stale.length) {
    const ids = new Set(stale.map((x) => x.id));
    await mailbox.changeAsks(env, (now) => ({
      list: now.map((x) => (ids.has(x.id) && x.state === "working"
        ? answered(x, { state: "failed", error: "The server was interrupted while doing this. Check what was made before trying again." })
        : x)),
    }));
  }
  const done = [];
  for (const x of start) done.push(await runOne(env, mailbox, x.id, opts));
  return { started: start.map((x) => x.id), stale: stale.map((x) => x.id), done };
}
