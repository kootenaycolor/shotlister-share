/**
 * **The stage he calls Complete** (2026-10-20, his answer to the console
 * audit's #6): "Released" was renamed "Complete", with the release date
 * optional. The record keeps "Released" as the stage's id (like
 * `released_date`, `released_stills` and the portal's /select/ links), so no
 * record changes and no share link moves. Notion's own option may say either
 * word: the API can't rename it, so it is renamed by hand in Notion, or not at all.
 *
 * Two boundaries, the Mac's `stages.py` function for function:
 * - Notion: `notionIn` reads Notion's "Complete" as "Released" on every
 *   answer; `notionOut` sends the stage as its option's id on every write,
 *   whatever Notion calls it. Nothing inside meets Notion's word.
 * - Words: `shownStage` is what he reads; `canonStage` takes either name.
 */

export const RECORD = "Released";
export const SHOWN = "Complete";
const NOTION = "Complete";      // what Notion says once he renames the option there

/** The record's word for a stage, from either name. */
export function canonStage(stage) {
  const s = String(stage == null ? "" : stage).trim();
  return /^(complete|released)$/i.test(s) ? RECORD : s;
}

/** The word he reads for a stage. */
export function shownStage(stage) {
  const s = canonStage(stage);
  return s === RECORD ? SHOWN : s;
}

const isObj = (x) => x && typeof x === "object";

function statusIn(prop) {
  if (!isObj(prop) || !isObj(prop.select)) return;
  if (prop.select.name === NOTION) prop.select.name = RECORD;
  for (const o of prop.select.options || []) if (isObj(o) && o.name === NOTION) o.name = RECORD;
}

/** Notion's answer with "Complete" read as "Released" (pages, query results, a schema's options). In place. */
export function notionIn(answer) {
  const walk = (x, depth) => {
    if (depth > 6 || !isObj(x)) return;
    if (Array.isArray(x)) { for (const one of x) walk(one, depth + 1); return; }
    if (isObj(x.properties) && x.properties.Status) statusIn(x.properties.Status);
    if (Array.isArray(x.results)) for (const one of x.results) walk(one, depth + 1);
  };
  walk(answer, 0);
  return answer;
}

/** Notion's Status option for this stage (Projects database). Writes name it by
 * id, so they land on the same option whether Notion calls it Released or
 * Complete, and never make a second one. (The API can't rename an option: it
 * accepts the call and keeps the old name, 2026-10-20.) */
export const OPTION_ID = "feedface-0000-4000-8000-000000000007";

/** A write for Notion with the record's "Released" status sent as its option's id. A copy; the caller's body is left alone. */
export function notionOut(body) {
  if (!isObj(body)) return body;
  const b = JSON.parse(JSON.stringify(body));
  const walk = (x, depth) => {
    if (depth > 12 || !isObj(x)) return;
    if (Array.isArray(x)) { for (const one of x) walk(one, depth + 1); return; }
    const st = isObj(x.properties) && isObj(x.properties.Status) ? x.properties.Status : null;
    if (st && isObj(st.select) && st.select.name === RECORD && !st.select.options) st.select = { id: OPTION_ID };
    for (const v of Object.values(x)) if (isObj(v)) walk(v, depth + 1);
  };
  walk(b, 0);
  return b;
}
