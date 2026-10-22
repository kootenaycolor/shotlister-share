/**
 * **Starts a held ask the moment its asker says so** (2026-10-19, Add Shoot speed).
 *
 * `later.js` keeps the asks that outlast a phone's wait and lets the server's
 * own minute start them, so a run began 0 to 60 seconds after the press (about
 * 50 measured, three times running) before a single step was taken. The minute
 * stays as the safety net; this is the quicker way in. The asker that posted
 * the ask (the desk console, the phone) sends `POST /console/studio/asks/<id>/start`
 * straight after, and the server runs it inside that request: a request the
 * asker keeps open lives as long as the run does, where `waitUntil` is cut off
 * thirty seconds after the reply, and a Durable Object that would have done
 * the same is refused by this account's placement hint (code 10023, tried
 * 2026-10-19).
 *
 * `runOne` claims the ask compare-and-set, so this and the minute can never
 * both start it, and a second start finds it taken and answers what is there.
 */

import { runOne } from "./later.js";

/** The asks started this way. Others (a New Project, a backup) wait for the minute as before. */
export const KICKED = new Set(["run_new_shoot"]);

/**
 * Start one held ask now. Answers the ask as it stands: finished, when this
 * request ran it to the end, or as found, when the minute (or an earlier
 * start) has it. Never throws a run's own failure: that is written on the ask.
 */
export async function startNow(env, mailbox, ctx, id, { run = runOne } = {}) {
  const list = (await mailbox.asksOf(env)).list;
  const item = list.find((x) => x.id === id);
  if (!item) return { refusal: "No such ask." };
  if (!KICKED.has(item.method)) return { refusal: "That ask waits for the server's minute." };
  if (item.state !== "working" || item.by_done !== "server" || !item.later || item.later.started) return { item };
  const work = run(env, mailbox, id).catch((e) => console.error("start:", String((e && e.stack) || e)));
  if (ctx && ctx.waitUntil) ctx.waitUntil(work);
  await work;
  const now = (await mailbox.asksOf(env)).list.find((x) => x.id === id);
  return { item: now || item };
}
