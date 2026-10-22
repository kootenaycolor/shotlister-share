/**
 * **The worker's own minute** (2026-10-11, Projects Console without the Mac,
 * stage 2) — what `notionsync.py`'s loop did on the Studio Mac, on
 * Cloudflare's timer (`[triggers] crons` in wrangler.toml).
 *
 * Every minute, one live look (`notionsync.js` `syncTick`). What it did is
 * kept at `s/sync-last.json` for the console to show. Not until the Mac's
 * memory has been copied up: see below. (The switch back to the Mac's link,
 * and the ten-minute dry look kept beside it for comparing, went in stage 5
 * step 9, 2026-10-18.)
 *
 * A look that throws is kept as trouble, never retried in a loop: the next
 * minute is the retry, as it was on the Mac.
 */

const LAST_KEY = "s/sync-last.json";

async function keep(env, key, body) {
  await env.BUCKET.put(key, JSON.stringify(body), { httpMetadata: { contentType: "application/json" } });
}

/** The portal's minute: the Notion link, the films' facts, and the portal's
 * own refresh (cards and link covers, `refreshhub.js`, stage 3 step 2), the
 * records, and the films' daily backups. Each has its own switch
 * (`/console/studio/owner`, `/console/studio/owner/films`,
 * `/console/studio/owner/portal`, `/console/studio/filmbackup`) and a
 * trouble in one never stops another. */
export async function onTimer(env, when = Date.now()) {
  await Promise.allSettled([
    notionMinute(env, when),
    import("./filmfacts.js").then(({ onFilmFactsTimer }) => onFilmFactsTimer(env, undefined, when)),
    import("./refreshhub.js").then(({ onPortalTimer }) => onPortalTimer(env, undefined, when)),
    import("./recordlive.js").then(({ onRecordLiveTimer }) => onRecordLiveTimer(env, undefined, when)),
    // The films' daily backups (filmbackuprun.js): off until its switch.
    import("./filmbackuprun.js").then(({ onFilmBackupTimer }) => onFilmBackupTimer(env, when)),
    // The script's Drive folder against each film (scriptdrive.js): off
    // until its switch; every ten minutes when on.
    import("./scriptdrive.js").then(({ onScriptTimer }) => onScriptTimer(env, undefined, when)),
    // The phone's asks the server answers after its reply (later.js): a New
    // Project, a New Shoot's run, a film's backup.
    Promise.all([import("./later.js"), import("./studio.js")]).then(([later, studio]) => later.onLaterTimer(env, studio.mailbox)),
    // The Mac jobs list (macjobs.js): the server's parts, the one reminder.
    import("./macjobs.js").then(({ onMacJobsTimer }) => onMacJobsTimer(env, when)),
  ]);
}

async function notionMinute(env, when) {
  const owner = "hub";
  const at = new Date(when).toISOString();
  // **Never live without the Mac's memory.** The link decides from what both
  // sides last agreed (`s/notion-link.json`, copied up from the Mac at the
  // switch); without it every difference would look new. Until it is there
  // nothing is written.
  if (!(await env.BUCKET.head("s/notion-link.json"))) {
    await keep(env, LAST_KEY, { at, owner, trouble: "waiting for the Mac's memory (s/notion-link.json) before writing anything" });
    return;
  }
  try {
    const { syncTick } = await import("./notionsync.js");
    const got = await syncTick(env, { dry: false });
    // The questions for him that this look met, on the phone (push.js). The
    // Mac's desk hears of them from the same list.
    if (Array.isArray(got.notify) && got.notify.length) {
      const { tellConflicts } = await import("./push.js");
      got.pushed = await tellConflicts(env, got.notify);
    }
    await keep(env, LAST_KEY, { at, owner, ...got });
  } catch (e) {
    await keep(env, LAST_KEY, { at, owner, trouble: String((e && e.stack) || e).slice(0, 2000) });
  }
}
