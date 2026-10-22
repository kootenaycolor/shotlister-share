#!/usr/bin/env node
/**
 * The Type's starting Studio modes come from his Settings › New Projects
 * (the saved record standards), one source (stage 5 step 5).
 *   node --import <json+wasm hook> hub/step5standards.mjs
 */
import { standardOf, loadStandards, forgetStandards, resolveModes } from "./src/studiomodes.js";
import { tidyTemplates } from "./src/cloudlayout.js";
let pass = 0, fail = 0;
const check = (w, g, why = "") => { if (g) pass++; else { fail++; console.log(`  ${w} FAIL ${why}`); } };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const env = (obj) => ({ BUCKET: { async get(k) { return k === "s/record-templates.json" && obj ? { json: async () => obj, text: async () => JSON.stringify(obj) } : null; } } });

forgetStandards();
check("ours until read", same(standardOf("Commercial"), ["shot_list", "references", "schedule"]));
check("tidy keeps modes", same(tidyTemplates({ Personal: { fields: [], credits: [], modes: ["diagram", "bogus", "shot_list"] } }).Personal.modes, ["shot_list", "diagram"]));
check("tidy without modes leaves none", !("modes" in tidyTemplates({ Personal: { fields: [], credits: [] } }).Personal));
await loadStandards(env({ Personal: { fields: [], credits: [], modes: ["shot_list", "diagram"] } }));
check("his Personal wins", same(standardOf("Personal"), ["shot_list", "diagram"]));
check("others stay ours", same(standardOf("Narrative"), ["shot_list", "locations", "references", "schedule", "diagram"]));
check("a Job still none", same(standardOf("Personal", true), []));
check("a project resolves from it", same(resolveModes({ facts: { type: { value: "Personal" } } }).modes, ["shot_list", "diagram"]));
check("his own change over it", same(resolveModes({ facts: { type: { value: "Personal" }, modes: { value: { diagram: false } } } }).modes, ["shot_list"]));
const { sweep } = await import("./src/framescopy.js");
check("frame sweep off does nothing", (await sweep(env(null), 0)).skipped === "off");
const onEnv = { BUCKET: { async get(k) { return k === "s/framescopy.json" ? { json: async () => ({ on: true }) } : null; } } };
check("frame sweep on but off-tick waits", (await sweep(onEnv, 120000)).skipped === "not this tick");
check("frame sweep on, its tick, no Notion: says so", (await sweep(onEnv, 0)).skipped === "no Notion");
forgetStandards();
console.log(`step5standards: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
