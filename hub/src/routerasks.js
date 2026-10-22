/**
 * **The Mac's router on the asks door** (2026-10-14, stage 5 step 3).
 *
 * Projects Console on the Mac now sends each action the server does to the
 * same door the phone uses (`POST /console/studio/asks`), and does the rest
 * itself (drives, agents, windows). Two small additions make that safe:
 *
 * - **`key`** — the Mac's own name for one ask. Sent again under the same
 *   key (a reply lost on a bad connection, an edit replayed from the waiting
 *   list after a night offline), the ask already kept is answered, never made
 *   a second time. Kept as long as the mailbox keeps the ask (an answered one
 *   ten minutes, an unanswered one a day).
 * - **`here_only`** — the server's or nobody's. An ask the server does not
 *   take (its switch is off, or Notion handed it back before writing) is
 *   answered `declined` and not left `pending` for the Mac's mailbox, because
 *   the Mac that asked will do it itself at once. Without it the ask would
 *   bounce: the Mac's mailbox worker would claim it a few seconds later and
 *   do it a second time.
 *
 * Nothing changes for an ask sent without them (the phone's).
 */

const KEY = /^[a-z0-9][a-z0-9-]{7,63}$/;

/** The ask's key, or "" when it has none worth keeping. */
export function keyOf(asked) {
  const k = String((asked && asked.key) || "").trim().toLowerCase();
  return KEY.test(k) ? k : "";
}

/** Whether the asker does it itself when the server will not. */
export function hereOnly(asked) {
  return Boolean(asked && asked.here_only === true);
}

/** The ask already kept under this key, newest first, or null. */
export function sameKey(list, key) {
  if (!key) return null;
  for (let i = (list || []).length - 1; i >= 0; i--) {
    const x = list[i];
    if (x && x.key === key) return x;
  }
  return null;
}

/** The answer to an ask the server declined: nothing kept, nothing done. */
export function declined(item, now = new Date()) {
  return { ...item, state: "declined", by_done: "server", done_at: now.toISOString() };
}

/**
 * **Reads answered on the spot** (`POST /console/studio/now`): the router's
 * reads go here, not to the mailbox, so a list read every few seconds never
 * fills the mailbox the phone shares (an answered ask is kept ten minutes).
 * Only these — the reads the server answers within a reply. A write always
 * goes to the mailbox, under its key, so it is never done twice.
 */
import { STEP6_NOW } from "./step6.js";
export const NOW_READS = new Set([
  ...STEP6_NOW,
  "project_list", "films_shelf", "fact_choices", "crew_directory", "crew_dupes", "project_crew_url",
  "project_page", "portal_people", "portal_viewers", "portal_library", "project_suggestions",
  "new_project_options", "new_shoot_form", "project_facts", "project_history", "film_backups",
  "drive_tree", "project_dossier", "project_modes",
  // The portal's status line (portalmodes.js, stage 5 step 5).
  "portal_state",
  // A big move's look (bigmoves.js, stage 5 step 7); its run is held.
  "bigmove_look",
  // The Mac jobs list (macjobs.js, stage 5 step 7).
  "mac_jobs",
  // The Drive folder to pick portal documents from (portaldocs.js).
  "portal_docs",
]);

/** The on-the-spot answer: done, failed, or declined (the asker's own). */
export function nowAnswer(method, here) {
  if (!here) return { method, state: "declined" };
  return here.state === "done"
    ? { method, state: "done", result: here.result === undefined ? null : here.result }
    : { method, state: "failed", error: here.error };
}
