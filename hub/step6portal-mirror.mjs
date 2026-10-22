/** The portal backup's mirror of the bucket, read only: every write throws (as portalmodes-look.mjs). */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

/** The portal backup's mirror of the bucket, read only (portalmodes-look.mjs). */
export function mirrorBucket(ROOT) {
  const readOnly = () => { throw new Error("read only"); };
  const goneList = join(ROOT, "..", "gone-from-server.txt");
  const GONE = new Set(existsSync(goneList) ? readFileSync(goneList, "utf8").split("\n").slice(2).filter(Boolean) : []);
  const file = (key) => (GONE.has(key) ? join(ROOT, "\u0000gone") : join(ROOT, key));
  return {
    async get(key) {
      const f = file(key);
      if (!existsSync(f) || statSync(f).isDirectory()) return null;
      const bytes = readFileSync(f);
      return { key, etag: "m", httpEtag: '"m"', uploaded: statSync(f).mtime, json: async () => JSON.parse(bytes.toString("utf8")), text: async () => bytes.toString("utf8"),
        arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length), body: bytes, size: bytes.length, httpMetadata: {} };
    },
    async head(key) { const f = file(key); return existsSync(f) && !statSync(f).isDirectory() ? { key, etag: "m", size: statSync(f).size, uploaded: statSync(f).mtime } : null; },
    async list({ prefix = "", delimiter, limit } = {}) {
      const dir = prefix.endsWith("/") ? prefix : prefix.slice(0, prefix.lastIndexOf("/") + 1);
      const where = file(dir);
      if (!existsSync(where)) return { objects: [], delimitedPrefixes: [], truncated: false };
      if (delimiter) {
        return { objects: readdirSync(where).filter((n) => !statSync(join(where, n)).isDirectory()).map((n) => ({ key: `${dir}${n}` })).filter((o) => o.key.startsWith(prefix) && !GONE.has(o.key)),
          delimitedPrefixes: readdirSync(where).filter((n) => statSync(join(where, n)).isDirectory()).map((n) => `${dir}${n}/`), truncated: false };
      }
      const out = [];
      const walk = (d, rel) => { for (const n of readdirSync(d)) { const q = join(d, n); if (statSync(q).isDirectory()) walk(q, `${rel}${n}/`); else out.push({ key: `${rel}${n}`, uploaded: statSync(q).mtime }); } };
      walk(where, dir);
      const objects = out.filter((o) => o.key.startsWith(prefix) && !GONE.has(o.key));
      return { objects: limit ? objects.slice(0, limit) : objects, truncated: false };
    },
    put: readOnly, delete: readOnly,
  };
}
