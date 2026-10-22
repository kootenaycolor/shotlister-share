/**
 * **A project's credits, changed by the server** (2026-10-10, stage 1 of
 * Projects Console without the Mac) — `record.change_credits`, for the
 * credit a new person or company carries (`crew_new` / `company_new`).
 *
 * Since 2026-10-13 this is cloudfacts.js's port of `record.change_credits`
 * and `credits.apply`, rule for rule, not a second copy: the list is compared
 * as Python compares it (a list the phone wrote as {"people", "role"} is the
 * same list), and names are cleaned and matched as `credits._clean` /
 * `_same` do (Python's spaces, `casefold`, 120 letters). Its own copy here
 * compared with `JSON.stringify`, so an unchanged list could be rewritten and
 * its version bumped. `hub/cloudcredits.mjs` holds it to the Mac's code.
 */

import { applyCredit, changeCredits as changeOnRecord, liveDeps } from "./cloudfacts.js";

export { applyCredit };

/** record.change_credits: read, apply, write; on a clash read again and redo. */
export async function changeCredits(env, page, edit, by = "server") {
  const key = String(page || "").replace(/-/g, "").toLowerCase();
  const deps = liveDeps(env);
  return await changeOnRecord(key, edit, { ...deps, writeFacts: (p, changes) => deps.writeFacts(p, changes, by) });
}
