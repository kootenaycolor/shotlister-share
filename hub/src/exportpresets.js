/**
 * **The Studio's export presets** (2026-10-15) — one small studio file, so
 * the laptop and the Studio Mac show the same Presets menu in Export.
 *
 *   GET /console/studio/exportpresets   { v, presets } — `presets` is null
 *                                       until the first write (each Mac then
 *                                       offers its own starters and sends them)
 *   PUT /console/studio/exportpresets   { presets, base, by } — written from
 *                                       version `base`, or 409 with `now`
 *
 * Kept at `s/export-presets.json`: { v, presets, at, by }. A preset is the
 * Mac's own shape (`studio/Sources/ExportPresets.swift`): an id, a name, and
 * the settings. This file only holds them; it checks they are a short list
 * of named objects and nothing more, so a later Studio's new fields pass.
 */

export const PRESETS_KEY = "s/export-presets.json";
const MOST = 100;
const LONGEST = 128 * 1024;

/** A list worth keeping, or why not. */
export function checkPresets(presets) {
  if (!Array.isArray(presets)) return { why: "Presets are a list." };
  if (presets.length > MOST) return { why: `At most ${MOST} presets.` };
  const ids = new Set();
  for (const p of presets) {
    if (!p || typeof p !== "object" || Array.isArray(p)) return { why: "A preset is an object." };
    const id = String(p.id || "");
    const name = String(p.name || "").trim();
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) return { why: "A preset needs an id." };
    if (!name || name.length > 120) return { why: "A preset needs a name." };
    if (ids.has(id)) return { why: "Two presets share an id." };
    ids.add(id);
  }
  if (JSON.stringify(presets).length > LONGEST) return { why: "Too long." };
  return { presets };
}

export async function readPresets(env) {
  const got = await env.BUCKET.get(PRESETS_KEY);
  if (!got) return { v: 0, presets: null };
  try {
    const said = await got.json();
    return { v: Number(said.v) || 0, presets: Array.isArray(said.presets) ? said.presets : null };
  } catch {
    return { v: 0, presets: null };
  }
}

/** Written from version `base`; `moved` (the copy now kept) when another wrote first. */
export async function writePresets(env, { presets, base, by }) {
  const checked = checkPresets(presets);
  if (checked.why) return { problem: checked.why };
  const now = await readPresets(env);
  if (Number(base) !== now.v) return { moved: now };
  const kept = { v: now.v + 1, presets: checked.presets, at: new Date().toISOString(), by: String(by || "").slice(0, 80) };
  await env.BUCKET.put(PRESETS_KEY, JSON.stringify(kept), { httpMetadata: { contentType: "application/json" } });
  return { v: kept.v };
}
