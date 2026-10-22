#!/usr/bin/env node
/**
 * **Export presets on the server** (src/exportpresets.js), with a bucket in
 * memory: the first read says none yet, a write from the version read is
 * kept, a write from an old version is refused with what is there now, and
 * a list that is not presets is refused. `node hub/exportpresets.mjs`
 */
import { readPresets, writePresets, checkPresets } from "./src/exportpresets.js";

let pass = 0, fail = 0;
const check = (what, good, why) => {
  if (good) { pass += 1; console.log(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; console.log(`  ${what.padEnd(66)} FAIL — ${JSON.stringify(why)}`); }
};
const store = new Map();
const env = { BUCKET: {
  async get(key) { return store.has(key) ? { json: async () => JSON.parse(store.get(key)) } : null; },
  async put(key, body) { store.set(key, body); },
} };

const tomorrow = { id: "p-tomorrow", name: "Tomorrow", arrange: "schedule", days: { kind: "next" }, pages: ["table"] };
const ac = { id: "p-ac-sheet", name: "AC Sheet: Day by Day", arrange: "schedule", output: "perday", future: { x: 1 } };

const first = await readPresets(env);
check("before any write: version 0, no presets (each Mac offers starters)", first.v === 0 && first.presets === null, first);
const one = await writePresets(env, { presets: [ac, tomorrow], base: 0, by: "laptop" });
check("a write from the version read is kept", one.v === 1, one);
const read = await readPresets(env);
check("…and reads back the same, unknown fields kept", read.v === 1 && JSON.stringify(read.presets) === JSON.stringify([ac, tomorrow]), read);
const late = await writePresets(env, { presets: [tomorrow], base: 0, by: "studio mac" });
check("a write from an old version is refused, with what is there now", late.moved && late.moved.v === 1, late);
const again = await writePresets(env, { presets: [tomorrow, ac], base: 1, by: "studio mac" });
check("…and taken from the version it was handed", again.v === 2 && (await readPresets(env)).presets[0].id === "p-tomorrow", again);
check("a list that is not presets is refused", Boolean(checkPresets([{ name: "no id" }]).why) && Boolean(checkPresets({}).why));
check("two presets sharing an id are refused", Boolean(checkPresets([tomorrow, tomorrow]).why));
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
