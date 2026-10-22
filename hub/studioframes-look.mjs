#!/usr/bin/env node
/**
 * **Frames and sensors in Studio, a dry look over the real bucket** (stage 5
 * step 4, piece E): `framesLook` over a READ-ONLY copy of the bucket — the
 * portal backup's mirror in iCloud, or any folder laid out like it — with the
 * real engine (`src/mcp.wasm`, built by `hub/build.sh`). Per project with a
 * film: the ratio and each camera's sensor Studio shows today against what
 * it would show once the studioframes switch is thrown. Every write throws;
 * nothing is sent anywhere.
 *
 *     node hub/studioframes-look.mjs [mirror folder] [--json out.json]
 */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "import { readFileSync } from 'node:fs'; export default new WebAssembly.Module(readFileSync(new URL(" + JSON.stringify(url) + ")));" };
  return next(url, context);
}`)}`, import.meta.url);
const ROOT = (process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "") || join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups/mirror/bucket");
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

// The worker's cache, which a look has none of: every read misses.
const none = { match: async () => undefined, put: async () => {}, delete: async () => false };
globalThis.caches = { default: none, open: async () => none };
const { framesLook } = await import("./src/studioframes.js");
const { filmView } = await import("./src/studioshootsfilm.js");
const { allCards } = await import("./src/studiocards.js");

const ctx = { waitUntil() {}, passThroughOnException() {} };
const marks = { of: async () => ({}), save: async () => {} };
// The cache writes of a replayed film are the only writes a read makes; here they are dropped.
const quiet = { ...bucket, put: async () => ({}) };
const look = await framesLook({ BUCKET: quiet }, ctx, filmView, { cards: await allCards({ BUCKET: quiet }, { marks }) });
const out = process.argv.indexOf("--json");
if (out > 0) (await import("node:fs")).writeFileSync(process.argv[out + 1], JSON.stringify(look, null, 2));
console.log(`${look.projects} projects, ${look.films} with a film: ${look.ratioChanges} ratio would change, ${look.sensorChanges} with a sensor that would change`);
for (const r of look.rows) {
  if (!r.film) { console.log(`  ${(r.name || r.id).padEnd(30)} no film; frames: ${(r.frames || []).join(", ") || "none"}`); continue; }
  if (r.trouble) { console.log(`  ${(r.name || r.id).padEnd(30)} TROUBLE ${r.trouble}`); continue; }
  const sensors = r.sensors.filter((s) => s.now || s.would).map((s) => `${s.camera}: ${s.now || "none"}${s.changes ? ` -> ${s.would || "none"}${s.fromSheet ? " (sheet)" : ""}` : " (same)"}`).join("; ");
  console.log(`  ${(r.name || r.id).padEnd(30)} ratio ${r.ratio.now}${r.ratioChanges ? ` -> ${r.ratio.would}` : " (same)"} [${r.ratio.frame}]  frames: ${r.frames.join(", ") || "none (Main at the film's own)"}${sensors ? `  sensors: ${sensors}` : ""}`);
}
