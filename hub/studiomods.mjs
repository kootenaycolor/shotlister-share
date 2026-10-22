#!/usr/bin/env node
/**
 * **Mods, one shelf** — `src/studiomods.js` (2026-10-17).
 *
 * 1. Off by default: a record with no `mods` fact has none; junk is ignored.
 * 2. Switching on and off writes only the `mods` fact, never anything else.
 * 3. The card carries `mods`, empty for a project that uses none.
 * 4. The Systems card's ask answers every shelf mod; set_project_mod switches one.
 * 5. The connector's `mods` tool reads and switches; a viewer may not.
 * 6. The doors.
 *
 *     node hub/studiomods.mjs
 */
import { SHELF, resolveMods, setMod, readMods, modsDoor, shelf } from "./src/studiomods.js";
import { modFlags, setProjectMod } from "./src/projectmodes.js";
import { modsTool, modKey } from "./src/mcpmods.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 70).padEnd(72)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 500)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function bucket() {
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? { json: async () => JSON.parse(m.get(k)), text: async () => m.get(k), etag: "e" } : null; },
    async head(k) { return m.has(k) ? {} : null; },
    async put(k, v) { m.set(k, typeof v === "string" ? v : String(v)); return {}; },
    async delete(k) { m.delete(k); },
    async list({ prefix, delimiter }) {
      const seen = new Set();
      for (const k of m.keys()) if (k.startsWith(prefix)) seen.add(prefix + k.slice(prefix.length).split(delimiter)[0] + delimiter);
      return { delimitedPrefixes: [...seen], truncated: false };
    },
  };
}
const ID = (n) => n.toString(16).padStart(32, "0");
const env = { BUCKET: bucket() };
const put = (key, record) => env.BUCKET.put(`r/${key}/record.json`, JSON.stringify({ page: key, ...record }));
const record = async (key) => JSON.parse(env.BUCKET.m.get(`r/${key}/record.json`));
const writes = [];
const writeFacts = async (page, changes, by) => {
  const r = await record(page);
  r.facts ||= {};
  for (const [k, c] of Object.entries(changes)) {
    const v = r.facts[k] ? r.facts[k].v || 0 : 0;
    if ((Number(c.base) || 0) !== v) return { status: 409 };
  }
  for (const [k, c] of Object.entries(changes)) r.facts[k] = { value: c.value, v: (r.facts[k] ? r.facts[k].v || 0 : 0) + 1, by };
  await put(page, r);
  writes.push({ page, changes, by });
  return { status: 200 };
};
const deps = { writeFacts };

// 1
check("the shelf holds Edit Reference", same(shelf().map((m) => m.key), ["edit_reference"]) && SHELF[0].title === "Edit Reference");
check("no mods fact: none on", same(resolveMods({ facts: { title: { value: "X" } } }), []));
check("no record: none on", same(resolveMods(null), []));
check("junk ignored", same(resolveMods({ facts: { mods: { value: { edit_reference: "yes", nope: true } } } }), []));
check("true reads on", same(resolveMods({ facts: { mods: { value: { edit_reference: true } } } }), ["edit_reference"]));

// 2
await put(ID(1), { name: "ZZ Mods", facts: { title: { value: "ZZ Mods", v: 1 }, modes: { value: { diagram: false }, v: 3 } } });
let got = await setMod(env, ID(1), { mod: "edit_reference", on: true, by: "check" }, deps);
check("on: ok", got.ok && same(got.mods, ["edit_reference"]), JSON.stringify(got));
check("on: only the mods fact written", writes.length === 1 && same(Object.keys(writes[0].changes), ["mods"]), JSON.stringify(writes));
let r = await record(ID(1));
check("on: the modes fact untouched", same(r.facts.modes, { value: { diagram: false }, v: 3 }));
got = await setMod(env, ID(1), { mod: "edit_reference", on: true, by: "check" }, deps);
check("on again: unchanged, nothing written", got.unchanged === true && writes.length === 1);
got = await setMod(env, ID(1), { mod: "edit_reference", on: false, by: "check" }, deps);
r = await record(ID(1));
check("off: written as an empty set", got.ok && same(got.mods, []) && same(r.facts.mods.value, {}), JSON.stringify(r.facts.mods));
check("no such mod: refused", (await setMod(env, ID(1), { mod: "song_map", on: true }, deps)).ok === false);
check("no on: refused", (await setMod(env, ID(1), { mod: "edit_reference" }, deps)).ok === false);
check("no project: 404", (await setMod(env, ID(9), { mod: "edit_reference", on: true }, deps)).status === 404);

// 3
const { allCards } = await import("./src/studiocards.js").catch(() => ({}));
check("studiocards carries mods (source)", (await import("node:fs")).readFileSync(new URL("./src/studiocards.js", import.meta.url), "utf8").includes("mods: resolveMods(record)"));
void allCards;

// 4
check("modFlags names every shelf mod", same(modFlags([]), { edit_reference: false }) && same(modFlags(["edit_reference"]), { edit_reference: true }));
got = await setProjectMod(env, [ID(1), "edit_reference", true], deps);
check("set_project_mod on", got.ok && same(got.mods, { edit_reference: true }), JSON.stringify(got));
got = await setProjectMod(env, [ID(1), "edit_reference", "yes"], deps);
check("set_project_mod needs a bool", got.ok === false);

// 5
const refuse = (m) => new Error(m);
const found = { id: ID(1), title: "ZZ Mods", role: "editor" };
check("modKey reads titles", modKey("Edit Reference") === "edit_reference" && modKey("edit-reference") === "edit_reference" && modKey("x") === "");
let said = await modsTool(env, found, {}, refuse, null, { setMod: (id, s) => setMod(env, id, s, deps) });
check("tool reads the shelf", JSON.parse(said).shelf[0].on === true, said);
said = await modsTool(env, found, { mod: "Edit Reference", on: false }, refuse, { email: "x@y" }, { setMod: (id, s) => setMod(env, id, s, deps) });
check("tool switches off", /Edit Reference is off\. Nothing is deleted\. On: none\./.test(said), said);
let threw = "";
try { await modsTool(env, { ...found, role: "viewer" }, { mod: "edit_reference", on: true }, refuse, null); } catch (e) { threw = e.message; }
check("a viewer may not switch", /Only an editor/.test(threw), threw);

// 6
const res = async (p) => { const x = await p; return { status: x.status, body: JSON.parse(await x.text()) }; };
let d = await res(modsDoor(env, ["mods"], "GET", async () => ({})));
check("door: the shelf", d.status === 200 && d.body.shelf[0].key === "edit_reference");
d = await res(modsDoor(env, ["mods", ID(1)], "GET", async () => ({})));
check("door: a project's mods", d.status === 200 && same(d.body.mods, []), JSON.stringify(d.body));
check("door: not ours", (await modsDoor(env, ["modes", ID(1)], "GET", async () => ({}))) === null);
const rm = await readMods(env, ID(1));
check("readMods answers the shelf", rm.ok && rm.shelf.length === 1);

console.log(`studiomods: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
