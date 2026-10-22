#!/usr/bin/env node
/**
 * **A Music Video is a Commercial, one rule on server and Mac** (2026-10-15).
 *
 * A Music Video follows his SAVED Commercial standard (fields, credits,
 * starting modes) unless Music Video has a saved standard of its own. Every
 * server reader of the standards is asked: notionlink (record layout),
 * step6recordsrules (Settings › Record, the master once step6records is on),
 * studiomodes (a new project's modes, after loadStandards), newproject's
 * sheet options. Then the Mac's own recordlayout.py (PC_DIR, default
 * ~/Developer/projects-console) answers the same cases and must agree.
 *
 *     node hub/musicvideo.mjs
 */
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);

const { resolveLayout } = await import("./src/notionlink.js");
const R = await import("./src/step6recordsrules.js");
const { standardOf, loadStandards, forgetStandards } = await import("./src/studiomodes.js");
const { tidyTemplates } = await import("./src/cloudlayout.js");
const { optionsFrom } = await import("./src/newproject.js");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 70).padEnd(72)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 3000)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const CASES = [
  null,
  { Commercial: { fields: ["client", "shoot_dates"], credits: ["Director"] } },
  { Commercial: { fields: ["client"], credits: ["Director"], modes: ["references"] } },
  { Commercial: { fields: ["client"], credits: ["Director"], modes: ["schedule"] },
    "Music Video": { fields: ["length"], credits: ["Producer"] } },
  { Commercial: { fields: ["client"], credits: ["Director"], modes: ["references"] },
    "Music Video": { fields: ["website"], credits: ["Producer"], modes: ["diagram"] } },
  { Narrative: { fields: ["logline"], credits: ["Writer"] } },
];

const bucket = (saved) => ({ get: async (k) => (k === "s/record-templates.json" && saved ? { json: async () => saved } : null) });

const server = [];
for (const saved of CASES) {
  forgetStandards();
  await loadStandards({ BUCKET: bucket(saved) });
  const tidy = tidyTemplates(saved || {});
  const lay = (t) => { const x = resolveLayout({}, t, tidy).template; return { fields: x.fields, credits: x.credits }; };
  const opts = optionsFrom({ templates: tidy });
  const view = R.templatesView(saved || {});
  const one = {
    layout: { mv: lay("Music Video"), com: lay("Commercial") },
    rules: { mv: R.templateFor("Music Video", saved || {}), com: R.templateFor("Commercial", saved || {}) },
    changed: view["Music Video"].changed,
    modes: { mv: standardOf("Music Video"), com: standardOf("Commercial"), job: standardOf("Music Video", true) },
    sheet: { layout: opts.layouts["Music Video"], modes: opts.modes_standard["Music Video"] },
  };
  server.push(one);
  const own = saved && saved["Music Video"];
  const tag = own ? "own standard" : "no own standard";
  check(`${JSON.stringify(saved)} · ${tag}: readers agree with each other`,
    same(one.layout.mv, { fields: one.rules.mv.fields, credits: one.rules.mv.credits })
      && same(one.sheet.layout, one.layout.mv) && same(one.sheet.modes, one.modes.mv) && same(one.rules.mv.modes, one.modes.mv),
    JSON.stringify(one));
  if (!own) {
    check(`${tag}: Music Video == Commercial (layout, Settings, modes)`,
      same(one.layout.mv, one.layout.com) && same(one.rules.mv, one.rules.com) && same(one.modes.mv, one.modes.com), JSON.stringify(one));
    check(`${tag}: not shown as his own`, one.changed === false);
  } else {
    check(`${tag}: its own fields and credits`, same(one.layout.mv, { fields: own.fields, credits: own.credits }), JSON.stringify(one.layout.mv));
    check(`${tag}: shown as his own`, one.changed === true);
  }
  check(`${tag}: a Job starts with none`, same(one.modes.job, []));
}

// ── the Mac answers the same cases ───────────────────────────────────────────
const PC = (process.env.PC_DIR || `${homedir()}/Developer/projects-console`).replace(/^~/, homedir());
const PY = `
import json, sys
sys.path.insert(0, sys.argv[1])
import recordlayout as L
out = []
for saved in json.loads(sys.argv[2]):
    mv, com = L.template_for("Music Video", saved), L.template_for("Commercial", saved)
    out.append({"layout": {"mv": {"fields": mv["fields"], "credits": mv["credits"]},
                           "com": {"fields": com["fields"], "credits": com["credits"]}},
                "rules": {"mv": mv, "com": com},
                "changed": L.templates(saved)["Music Video"]["changed"],
                "modes": {"mv": L.modes_standard("Music Video", saved=saved),
                          "com": L.modes_standard("Commercial", saved=saved),
                          "job": L.modes_standard("Music Video", job=True, saved=saved)}})
print(json.dumps(out))
`;
const mac = JSON.parse(execFileSync("python3", ["-c", PY, PC, JSON.stringify(CASES)], { encoding: "utf8" }));
CASES.forEach((saved, i) => {
  const s = { ...server[i] }; delete s.sheet;
  check(`Mac == server: ${JSON.stringify(saved)}`, same(mac[i], s), `mac ${JSON.stringify(mac[i])} server ${JSON.stringify(s)}`);
});

console.log(`musicvideo: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
