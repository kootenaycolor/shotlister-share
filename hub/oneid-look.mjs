#!/usr/bin/env node
/**
 * **One ID, a dry look over the real bucket** (stage 5 step 2). Runs the real
 * rules (`freezeAliases`, `planStudioSide`) over a READ-ONLY copy of the
 * bucket — the portal backup's mirror in iCloud, or any folder laid out like
 * the bucket — and says, per project, what flipping the switch would mean.
 * Every write throws; nothing is sent anywhere.
 *
 *     node hub/oneid-look.mjs [mirror folder]
 *
 * Also compares the mirror's records with the live hub's list (a GET with the
 * console's token from the Keychain), so a stale mirror is said, not trusted.
 */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { execFileSync } from "node:child_process";
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);
const ids = await import("./src/projectid.js");
const { planStudioSide } = await import("./src/studioside.js");

const ROOT = process.argv[2] || join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups/mirror/bucket");
if (!existsSync(join(ROOT, "r"))) { console.error(`no bucket copy at ${ROOT}`); process.exit(2); }

const readOnly = () => { throw new Error("read only: this look writes nothing"); };
// The mirror never deletes; what the server no longer has is named beside it.
const goneList = join(ROOT, "..", "gone-from-server.txt");
const GONE = new Set(existsSync(goneList) ? readFileSync(goneList, "utf8").split("\n").slice(2).filter(Boolean) : []);
const file = (key) => (GONE.has(key) ? join(ROOT, "\u0000gone") : join(ROOT, key));
const bucket = {
  async get(key) {
    const f = file(key);
    if (!existsSync(f) || statSync(f).isDirectory()) return null;
    const bytes = readFileSync(f);
    return { key, etag: "m", json: async () => JSON.parse(bytes.toString("utf8")), text: async () => bytes.toString("utf8") };
  },
  async head(key) { const f = file(key); return existsSync(f) && !statSync(f).isDirectory() ? { etag: "m" } : null; },
  async list({ prefix = "", delimiter } = {}) {
    const dir = prefix.endsWith("/") ? prefix : prefix.slice(0, prefix.lastIndexOf("/") + 1);
    const at = file(dir);
    if (!existsSync(at)) return { objects: [], delimitedPrefixes: [], truncated: false };
    if (delimiter) {
      // A folder whose every file is gone is gone.
      return { objects: [], delimitedPrefixes: readdirSync(at).filter((n) => statSync(join(at, n)).isDirectory()).map((n) => `${dir}${n}/`), truncated: false };
    }
    const out = [];
    const walk = (d, rel) => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) walk(p, `${rel}${n}/`); else out.push({ key: `${rel}${n}` }); } };
    walk(at, dir);
    return { objects: out.filter((o) => o.key.startsWith(prefix) && !GONE.has(o.key)), truncated: false };
  },
  put: readOnly, delete: readOnly,
};
const env = { BUCKET: bucket };

// The live list, to say how stale the copy is.
let live = null;
try {
  const token = execFileSync("security", ["find-generic-password", "-a", "shotlister-relay-token", "-w"], { encoding: "utf8" }).trim();
  const got = execFileSync("curl", ["-s", "-m", "30", "-A", "ProjectsConsole/1.0", "-H", `Authorization: Bearer ${token}`, "https://mcp.your-domain.example/console/records"], { encoding: "utf8" });
  live = JSON.parse(got).records || null;
} catch { live = null; }

const look = await ids.freezeAliases(env, { dry: true });
console.log(`\nRecords in the copy: ${look.records}${live ? `  ·  on the live hub: ${live.length}` : "  ·  live hub not read"}`);
if (live) {
  const here = new Map(look.found.map((f) => [f.key, f]));
  for (const r of live) {
    const mine = here.get(r.page);
    const relay = (r.film && r.film.relay) || "";
    if (!mine) console.log(`  STALE COPY: live has ${r.page} (${r.name}) the copy lacks`);
    else if (mine.relay !== relay) console.log(`  STALE COPY: ${r.name} names film ${relay || "none"} live, ${mine.relay || "none"} in the copy`);
  }
}
console.log(`\nAliases that freezing would add (${Object.keys(look.would_add).length}):`);
for (const f of look.found.filter((x) => x.alias)) console.log(`  ${f.name.padEnd(34)} ${f.relay} → ${f.key}${f.clash ? `  CLASH with ${f.clash}` : ""}`);

console.log("\nPer project, with the switch on:");
for (const f of look.found) {
  const portal = Boolean(await bucket.head(`p/${f.key}/portal.json`));
  const plan = await planStudioSide(env, f.key, { fetchRow: async () => null, fetchText: async () => "" });
  let says;
  if (plan.ok && !plan.made) says = plan.alias ? `film under its alias ${plan.relay}` : `film under its own ID`;
  else if (plan.ok && plan.made) says = `no Studio side yet — would be made under ${plan.key}${plan.portal ? " ON TOP OF ITS PORTAL (no carry)" : ""}`;
  else says = `REFUSED: ${plan.why}`;
  const trap = portal && f.relay && f.relay !== f.key ? "  !! portal on its own AND a film elsewhere: carry it once before the switch" : "";
  console.log(`  ${f.name.padEnd(34)} ${says}${trap}`);
}
console.log("\n(read-only: nothing was written)");
