#!/usr/bin/env node
/**
 * The portal reads several cameras and several LUTs on a spec sheet the way
 * Projects Console does (`src/entries.js` and the console's `entries.py`).
 * `spec-cases.json` is the console's file, copied.
 *
 *     node hub/entries.mjs
 */
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { entries, cameras, luts, suggestCameras } from "./src/entries.js";
import { lensSets } from "./src/lenses.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const cases = JSON.parse(readFileSync(join(HERE, "spec-cases.json"), "utf8"));
let pass = 0, fail = 0;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.replace(/\n/g, " ⏎ ").slice(0, 64).padEnd(66)} ${good ? "PASS" : `FAIL — ${why}`}`);
};
for (const c of cases.entries) {
  const got = entries(c.text).map(({ label, value }) => ({ label, value }));
  check(`entries: ${c.text}`, same(got, c.entries), JSON.stringify(got));
}
for (const c of cases.cameras) {
  const g = cameras(c.fields, lensSets(c.lenses));
  const got = {
    multi: g.multi,
    cameras: g.cameras.map((x) => ({ label: x.label, name: x.name, fields: x.fields, lenses: x.lenses.map((s) => s.raw) })),
    shared: Object.fromEntries(Object.entries(g.shared).filter(([, v]) => v)),
    lenses_shared: g.lenses_shared.map((s) => s.raw),
    unmatched: g.unmatched,
  };
  // key order aside: compare each part with its keys sorted
  const norm = (o) => JSON.parse(JSON.stringify(o, (k, v) => (v && typeof v === "object" && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort()) : v)));
  const want = { multi: c.multi, cameras: c.cameras, shared: c.shared, lenses_shared: c.lenses_shared, unmatched: c.unmatched };
  check(`cameras: ${c.fields.Camera}`, same(norm(got), norm(want)), JSON.stringify(got));
}
for (const c of cases.luts) {
  const g = luts(c.files, c.labels);
  const got = { rows: g.rows.map(({ label, shown }) => ({ label, shown })), stray: g.stray };
  check(`luts: ${c.labels || "no labels"}`, same(got, { rows: c.rows, stray: c.stray }), JSON.stringify(got));
}
for (const c of cases.suggest) check(`suggest: ${c.text}`, suggestCameras(c.text) === c.suggested, suggestCameras(c.text));
// Pills (2026-10-13): Notion's fields became multi-selects
{
  const { fieldText, pillsOf, labelledCameras } = await import("./src/entries.js");
  const { lensSetsShown, arePills } = await import("./src/lenses.js");
  const ms = (...n) => ({ type: "multi_select", multi_select: n.map((name) => ({ name })) });
  check("a pill field reads one pill per line", fieldText(ms("Arri Alexa Mini", "Sony FX6")) === "Arri Alexa Mini\nSony FX6");
  check("pills drop commas and repeats", same(pillsOf("Master Prime 25mm\n\nmaster prime 25mm\nCooke, S4"), ["Master Prime 25mm", "Cooke S4"]));
  check("the record's labels go on the camera pills", labelledCameras("Alexa 35\nSony FX3", { "alexa 35": "A Cam", "Sony FX3": "B Cam" }) === "A Cam: Alexa 35\nB Cam: Sony FX3");
  check("the record's label wins over a stale one", labelledCameras("A Cam: Sony FX3", { "Sony FX3": "B Cam" }) === "B Cam: Sony FX3");
  const shown = lensSetsShown("Master Prime 50mm\nFujinon Cabrio 19-90mm\nMaster Prime 25mm\nSignature Primes");
  check("lens pills grouped by family, primes in focal order", same(shown.map((x) => [x.series, x.focals.join(", ")]),
    [["Master Prime", "25, 50mm"], ["Fujinon Cabrio", "19-90mm"], ["Signature Primes", ""]]), JSON.stringify(shown));
  check("old typed sets are not pills", !arePills("A Cam: Cooke S4 — 18, 25mm") && arePills("Laowa Probe2"));
  const { lensPills } = await import("./src/lenses.js");
  const { bodiesOf, labelsOf } = await import("./src/entries.js");
  check("an older screen's typed set becomes one pill per lens", lensPills("Master Prime 25mm\nA Cam: Cooke S4 — 18, 32mm — T2\nSignature Primes")
    === "Master Prime 25mm\nCooke S4 18mm\nCooke S4 32mm\nSignature Primes", lensPills("A Cam: Cooke S4 — 18, 32mm — T2"));
  check("a camera edit sends Notion bodies, keeps labels", bodiesOf("A Cam: Alexa 35\nSony FX3") === "Alexa 35\nSony FX3"
    && JSON.stringify(labelsOf("A Cam: Alexa 35\nSony FX3")) === '{"Alexa 35":"A Cam"}');
}
console.log(`passed ${pass}, failed ${fail}`);
process.exit(fail ? 1 : 0);
