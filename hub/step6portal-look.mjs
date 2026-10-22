#!/usr/bin/env node
/**
 * **Step 6, group "portal": the dry look over the real bucket** (2026-10-15).
 * `lookOf` — what `GET /console/studio/step6portal/look?id=<page>` answers —
 * for every project record, run against a READ-ONLY copy of the bucket (the
 * portal backup's mirror in iCloud) with the real worker answering its own
 * door in-process. Every write throws; nothing is sent anywhere.
 *
 * With `--real FILE` (from `step6portal-real.py --real FILE`) each project's
 * preview is set beside the Mac's, read from the live hub: the Mac's code on
 * live data against the server's code on the bucket's copy.
 *
 *     node --import ~/.worktrees/step6-tools/jsonhook.mjs hub/step6portal-look.mjs [--real FILE]
 */
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { mirrorBucket } from "./step6portal-mirror.mjs";

const ROOT = process.env.MIRROR || join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups/mirror/bucket");
if (!existsSync(join(ROOT, "r"))) { console.error(`no bucket copy at ${ROOT}`); process.exit(2); }
// The Workers cache, stood in for: always a miss, nothing kept.
const cache = { match: async () => undefined, put: async () => {}, delete: async () => false };
globalThis.caches = globalThis.caches || { default: cache, open: async () => cache };
const { lookOf } = await import("./src/step6portal.js");
const toml = readFileSync(new URL("./wrangler.toml", import.meta.url), "utf8");
const varOf = (k) => ((toml.match(new RegExp(`^${k}\\s*=\\s*"([^"]*)"`, "m")) || [])[1] || "");
const env = { BUCKET: mirrorBucket(ROOT), CONSOLE_TOKEN: "look-only", OWNER: varOf("OWNER") };

const at = process.argv.indexOf("--real");
const real = at > 0 ? JSON.parse(readFileSync(process.argv[at + 1], "utf8")) : null;
const macOf = new Map((real ? real.projects : []).map((p) => [p.page, p]));
let pass = 0, fail = 0, writes = 0;
const pages = readdirSync(join(ROOT, "r")).filter((n) => /^[0-9a-f]{32}$/.test(n));
for (const page of pages) {
  let look;
  try { look = await lookOf(env, page); } catch (e) { console.log(`  ${page} TROUBLE ${String(e.stack || e).slice(0, 300)}`); fail += 1; continue; }
  const sends = Object.values(look.would || {}).flat().reduce((n, w) => n + w.sends.length, 0);
  writes += look.writes || 0;
  const pv = look.preview || {};
  if (look.library) console.log(`      the Library did not answer: ${JSON.stringify(look.library).slice(0, 200)}`);
  console.log(`  ${String(look.name).slice(0, 30).padEnd(32)} ${look.portal ? "portal" : "no portal"} ${look.portal ? `sidebar ${look.sidebar ? look.sidebar.length : "?"} groups, ${look.pages} pages, ${look.documents} documents, ${(look.shelves || []).length} categories; would send ${sends} no-change edits (dry)` : ""} preview: ${pv.ok ? (pv.crew ? "crew link" : pv.crew_why) : pv.why}`);
  const mac = macOf.get(page);
  if (mac) {
    // `name` is the asker's (the Mac's project name; the look names the record's)
    const mine = { ...pv, ...(pv.ok ? { name: mac.preview.name } : {}) };
    const good = JSON.stringify(mine) === JSON.stringify(mac.preview);
    if (good) pass += 1; else fail += 1;
    console.log(`      the Mac's preview (live hub) ${good ? "the same" : `DIFFERS — Mac ${JSON.stringify(mac.preview).replace(/[A-Za-z0-9_-]{20,}/g, "<…>")} vs server ${JSON.stringify(mine).replace(/[A-Za-z0-9_-]{20,}/g, "<…>")}`}`);
  }
}
if (real) {
  const looked = new Set(pages);
  for (const p of real.projects) if (p.page && !looked.has(p.page)) console.log(`  ${p.name}: no record in the bucket copy (Mac: ${p.preview.ok ? "a portal" : p.preview.why})`);
}
console.log(`\nstep6portal-look: ${pages.length} records looked at, ${writes} writes; ${real ? `${pass} previews the same as the Mac's, ${fail} differ` : ""}`);
process.exit(fail ? 1 : 0);
