#!/usr/bin/env node
/**
 * **The portal follows the modes, a dry look over the real bucket** (stage 5
 * step 5): `portalModesLook` over a READ-ONLY copy of the bucket — the portal
 * backup's mirror in iCloud, or any folder laid out like it. Says, per
 * project, which sidebar pages would go when the portalmodes switch is
 * thrown. Every write throws; nothing is sent anywhere.
 *
 *     node hub/portalmodes-look.mjs [mirror folder]
 */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);
const { portalModesLook } = await import("./src/portalmodes.js");
const { storedFront } = await import("./src/front.js");

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

// The stored card, not the engine's: the rail's rows and the Library are the card's.
const look = await portalModesLook(env, null, { readFront: (e, p) => storedFront(e, p) });
console.log(`${look.projects} projects, ${look.portals} with a portal, ${look.hiding} would lose sidebar pages`);
for (const r of look.rows) {
  const off = r.off.length ? r.off.join(", ") : "none";
  const hides = r.hides && r.hides.length ? r.hides.map((h) => `${h.name} (${h.mode})`).join(", ") : "nothing";
  console.log(`  ${(r.name || r.id).padEnd(34)} ${(r.job ? "Job " : "") + (r.type || "no Type")}`.padEnd(60) + ` modes off: ${off}; ${r.portal ? `sidebar loses: ${hides}` : "no portal"}${r.trouble ? ` TROUBLE ${r.trouble}` : ""}`);
}
