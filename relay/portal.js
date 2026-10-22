/**
 * **Whether a project is a portal with no film behind it — the one rule.**
 *
 * A portal mark (`portal.json`, written by the console's door) and no film
 * manifest. Nothing else: change logs do not make a film. SL-1376, 2026-10-01:
 * a chat wrote two change logs into Halcyon, a portal with no film, and four
 * places answered the question four ways. The shelf and the rail counted the
 * logs and called it a film, so they linked to Schedule; the screen gate
 * looked at the mark alone and refused Schedule with *No such page*; the
 * relay listed it to every Mac and iPhone as a film with no manifest.
 *
 * So the question is asked here, in one function, by the hub (`filmlessPortal`
 * in `hub/src/films.js`, and every door that reads it) and by the relay
 * (`listProjects`), and they cannot disagree again. Logs that land under a
 * mark with no manifest are strays: everything ignores them, and the
 * console's readout says how many there are.
 *
 * Takes facts, not a bucket, because the two callers learn them differently
 * — the hub asks for two keys, the relay sees them go past in its listing.
 * `mark` is the mark's key being there at all, readable or not.
 */
export function filmless({ mark, manifest }) {
  return Boolean(mark) && !manifest;
}
