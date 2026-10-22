/**
 * **The spec sheet's pills, with Notion's colours** (2026-10-13). His ask:
 * *"i want the lenses, and camera to show up as pills, same as notion … if we
 * do pills in notion and the table view, then we stick to it."* So every
 * screen that shows a sheet draws each value as a pill in the colour Notion
 * gave its option: Shotlister's Spec Sheet page (through the kit door), the
 * portal's camera page, Projects Console (`spec_options`).
 *
 * The options are read off the Camera Spec Sheets data source and kept in R2
 * (`studio/spec-pills.json`) for ten minutes, so a page never waits on Notion
 * and a new pill typed in Notion shows its colour within minutes. With no
 * Notion key, or Notion away, the kept copy answers; with none, every pill is
 * Notion's default grey.
 */
import { cloudReady, notionOf } from "./cloud.js";

const SOURCE = "feedface-0000-4000-8000-000000000003";
const KEY = "studio/spec-pills.json";
const KEEP_MS = 10 * 60 * 1000;

/** {prop: [{name, color}]} in Notion's order — every pill each field offers. */
export async function specPills(env, { fresh = false } = {}) {
  let kept = null;
  try {
    const got = await env.BUCKET.get(KEY);
    if (got) kept = await got.json();
  } catch { kept = null; }
  const young = kept && Date.now() - (Date.parse(kept.at) || 0) < KEEP_MS;
  if (young && !fresh) return kept.options || {};
  if (!cloudReady(env)) return (kept && kept.options) || {};
  try {
    const ds = await notionOf(env).get(`data_sources/${SOURCE}`);
    const options = {};
    for (const [name, field] of Object.entries(ds.properties || {})) {
      if (field.type !== "multi_select") continue;
      options[name] = ((field.multi_select || {}).options || []).map((o) => ({ name: o.name || "", color: o.color || "default" }));
    }
    await env.BUCKET.put(KEY, JSON.stringify({ at: new Date().toISOString(), options }), {
      httpMetadata: { contentType: "application/json" },
    });
    return options;
  } catch {
    return (kept && kept.options) || {};
  }
}

/** {prop: {name (lower case): color}} — a pill's colour by its name. */
export function colourIndex(options) {
  return Object.fromEntries(Object.entries(options || {}).map(([prop, list]) =>
    [prop, Object.fromEntries((list || []).map((o) => [String(o.name).toLowerCase(), o.color || "default"]))]));
}

/** Notion's tag colours, light and dark: [background, text]. One table for
 * every web screen; Shotlister keeps the same one in Swift (`PillColour`). */
export const PILL_COLOURS = {
  default: { light: ["#E9E9E7", "#37352F"], dark: ["#3A3A3A", "#E6E6E4"] },
  gray: { light: ["#E3E2E0", "#32302C"], dark: ["#5A5A5A", "#F0F0EE"] },
  brown: { light: ["#EEE0DA", "#442A1E"], dark: ["#603B2C", "#F3E8E2"] },
  orange: { light: ["#FADEC9", "#49290E"], dark: ["#854C1D", "#FBEBDD"] },
  yellow: { light: ["#FDECC8", "#402C1B"], dark: ["#89632A", "#FCF1DA"] },
  green: { light: ["#DBEDDB", "#1C3829"], dark: ["#2B593F", "#E3F1E5"] },
  blue: { light: ["#D3E5EF", "#183347"], dark: ["#28456C", "#E1EDF6"] },
  purple: { light: ["#E8DEEE", "#412454"], dark: ["#492F64", "#EFE7F5"] },
  pink: { light: ["#F5E0E9", "#4C2337"], dark: ["#69314C", "#F7E6EE"] },
  red: { light: ["#FFE2DD", "#5D1715"], dark: ["#6E3630", "#FBE6E3"] },
};
