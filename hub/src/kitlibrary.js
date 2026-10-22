/**
 * **Modifiers and filters** (2026-10-14, `design/spec-sheet.md` "Modifiers
 * and filters"). His words: *"i want to be able to add modifiers to lenses
 * like extenders, and also we should add filters … the modifiers would be a
 * per shot thing … so they are apart of the whole kit but not always tied to
 * a lens"*.
 *
 * One studio file on the hub (`s/kit-extras.json`), beside the lens library
 * and the sensor modes, every project picking from it:
 *
 *   { format: 1, v,
 *     modifiers: [{ id: "x-…", name, kind }],          kind: extender | expander | diopter | other
 *     sets:      [{ id: "g-…", name, size }],          a filter set: "Tiffen ND", "4x5.65"
 *     filters:   [{ id: "f-…", name, set, size }],     "Tiffen ND .6" in its set; or alone with its own size
 *     merged, at, by }
 *
 * - A **modifier** goes between a lens and the camera (or in front): an
 *   extender, an expander, a diopter. Named in full ("Atlas LF Extender 1.6x").
 * - A **filter** is named in full ("Tiffen ND .6"). A set holds a family of
 *   strengths at one size; adding a set with its strengths makes a filter per
 *   strength, named "<set> <strength>". A filter on its own keeps its size.
 * - **On a sheet** (specsheet.js) both are pools for the shoot, like lenses:
 *   {name, note, ref, set}. A shot picks from the film's lists, which the
 *   sheet feeds (engine `take_kit`).
 * - **Seeded** from what the sheets carry: the one extender the moved sheets
 *   held among their lenses. No filter is invented.
 */
import { readStudioList, writeStudioList, everySheet } from "./lenslibrary.js";

export const EXTRAS_KEY = "s/kit-extras.json";
export const KINDS = ["extender", "expander", "diopter", "other"];
export const EXTRA_REF = /^[xgf]-[a-z0-9]+(?:-\d+)?$/;

const MAX = { modifiers: 300, sets: 200, filters: 800, word: 120, size: 24, ops: 100 };
const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
const low = (s) => squash(s).toLowerCase();
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);

function idFor(prefix, name, taken) {
  const base = `${prefix}-${low(name).replace(/[^a-z0-9]/g, "").slice(0, 60) || "x"}`;
  let id = base;
  for (let n = 2; taken.has(id); n++) id = `${base}-${n}`;
  return id;
}

/** A modifier's kind from its name when none is said: "Extender" in it is an extender. */
export function kindOf(name, said = "") {
  const k = low(said);
  if (KINDS.includes(k)) return k;
  const n = low(name);
  if (/extender|doubler|\b1\.4x\b|\b2x\b/.test(n)) return "extender";
  if (/expander/.test(n)) return "expander";
  if (/diopter|split.?field|\+\s?\d/.test(n)) return "diopter";
  return "other";
}

export function seedExtras() {
  return {
    format: 1, v: 0,
    modifiers: [{ id: "x-atlaslfextender16x", name: "Atlas LF Extender 1.6x", kind: "extender" }],
    sets: [], filters: [], merged: {}, at: "", by: "",
  };
}

const sizeOf = (raw) => squash(raw).replace(/\s*[x×]\s*/gi, "x").slice(0, MAX.size);

/** The library, checked and tidied: {extras} or {why}. */
export function checkExtras(raw) {
  if (!isObject(raw)) return { why: "The modifiers and filters are an object." };
  const mods = Array.isArray(raw.modifiers) ? raw.modifiers : [];
  const sets = Array.isArray(raw.sets) ? raw.sets : [];
  const filters = Array.isArray(raw.filters) ? raw.filters : [];
  if (mods.length > MAX.modifiers || sets.length > MAX.sets || filters.length > MAX.filters) return { why: "Too many modifiers or filters." };
  const ids = new Set();
  const names = new Set();
  const take = (x, prefix, what) => {
    const name = squash(x && x.name);
    if (!name || name.length > MAX.word) return { why: `${what} needs a name.` };
    if (!EXTRA_REF.test(String(x.id)) || !String(x.id).startsWith(`${prefix}-`) || ids.has(x.id)) return { why: `${name} has no proper id.` };
    if (names.has(low(name))) return { why: `Two entries are called ${name}.` };
    ids.add(x.id);
    names.add(low(name));
    return { name };
  };
  const outMods = [];
  for (const m of mods) {
    if (!isObject(m)) return { why: "Each modifier is {id, name, kind}." };
    const got = take(m, "x", "A modifier");
    if (got.why) return got;
    outMods.push({ id: m.id, name: got.name, kind: kindOf(got.name, m.kind) });
  }
  const outSets = [];
  for (const s of sets) {
    if (!isObject(s)) return { why: "Each filter set is {id, name, size}." };
    const got = take(s, "g", "A filter set");
    if (got.why) return got;
    outSets.push({ id: s.id, name: got.name, size: sizeOf(s.size) });
  }
  const outFilters = [];
  for (const f of filters) {
    if (!isObject(f)) return { why: "Each filter is {id, name, set, size}." };
    const got = take(f, "f", "A filter");
    if (got.why) return got;
    const set = String(f.set || "");
    if (set && !outSets.some((s) => s.id === set)) return { why: `${got.name} is in a set the library does not have.` };
    outFilters.push({ id: f.id, name: got.name, set, size: set ? "" : sizeOf(f.size) });
  }
  const merged = {};
  for (const [from, to] of Object.entries(isObject(raw.merged) ? raw.merged : {})) {
    if (EXTRA_REF.test(from) && EXTRA_REF.test(String(to)) && !ids.has(from)) merged[from] = String(to);
  }
  return {
    extras: {
      format: 1, v: Number.isInteger(raw.v) && raw.v >= 0 ? raw.v : 0,
      modifiers: outMods, sets: outSets, filters: outFilters, merged,
      at: squash(raw.at).slice(0, 40), by: squash(raw.by).slice(0, 80),
    },
  };
}

const resolve = (lib, ref) => {
  let id = String(ref || "");
  for (let i = 0; i < 20 && lib.merged && lib.merged[id]; i++) id = lib.merged[id];
  return id;
};

/** {kind: "modifier"|"set"|"filter", item} by id or name, or null. */
export function extraOf(lib, said) {
  const s = squash(said);
  if (!s) return null;
  const id = resolve(lib, s);
  const by = (list) => list.find((x) => x.id === id) || list.find((x) => low(x.name) === low(s));
  const m = by(lib.modifiers);
  if (m) return { kind: "modifier", item: m };
  const f = by(lib.filters);
  if (f) return { kind: "filter", item: f };
  const g = by(lib.sets);
  return g ? { kind: "set", item: g } : null;
}

export const filtersIn = (lib, set) => lib.filters.filter((f) => f.set === set.id);

/** The library as a screen reads it. */
export function extrasView(lib) {
  return {
    v: lib.v,
    modifiers: lib.modifiers,
    sets: lib.sets.map((s) => ({ ...s, filters: filtersIn(lib, s).map(({ set, size, ...f }) => f) })),
    alone: lib.filters.filter((f) => !f.set).map(({ set, ...f }) => f),
    counts: { modifiers: lib.modifiers.length, sets: lib.sets.length, filters: lib.filters.length },
  };
}

/**
 * **What a pick puts on a sheet**, into its `modifiers` or `filters` pool:
 * a modifier is one entry, a filter one, a set every filter in it.
 * {pool, entries} or null.
 */
export function entriesForExtra(lib, found) {
  if (found.kind === "modifier") return { pool: "modifiers", entries: [{ name: found.item.name, note: "", ref: found.item.id }] };
  const one = (f) => {
    const set = f.set ? lib.sets.find((s) => s.id === f.set) : null;
    return { name: f.name, note: "", ref: f.id, ...(set ? { set: set.name } : {}) };
  };
  if (found.kind === "filter") return { pool: "filters", entries: [one(found.item)] };
  return { pool: "filters", entries: filtersIn(lib, found.item).map(one) };
}

/**
 * **Modifiers or filters picked onto a sheet** (by id or name; a set adds
 * every strength). {sheet, pool, added, already} or {why}. Written by the
 * caller through `checkSheet`.
 */
export function pickExtras(sheetIn, lib, said) {
  const found = extraOf(lib, said);
  if (!found) return { why: `The library has no modifier or filter called “${squash(said)}”.` };
  const { pool, entries } = entriesForExtra(lib, found);
  const sheet = JSON.parse(JSON.stringify(sheetIn));
  sheet[pool] = sheet[pool] || [];
  const added = [];
  const already = [];
  for (const e of entries) {
    if (sheet[pool].some((x) => (x.ref && resolve(lib, x.ref) === e.ref) || low(x.name) === low(e.name))) { already.push(e.name); continue; }
    sheet[pool].push(e);
    added.push(e.name);
  }
  return { sheet, pool, added, already };
}

/** {id: [sheet names]}: which sheets carry each entry (a set when any of its filters is). */
export function extrasUsageOf(lib, sheets) {
  const out = {};
  const mark = (id, name) => { out[id] = out[id] || []; if (!out[id].includes(name)) out[id].push(name); };
  for (const one of sheets) {
    for (const pool of ["modifiers", "filters"]) {
      for (const x of one.sheet[pool] || []) {
        const hit = extraOf(lib, x.ref && resolve(lib, x.ref)) || extraOf(lib, x.name);
        if (!hit) continue;
        mark(hit.item.id, one.name);
        if (hit.kind === "filter" && hit.item.set) mark(hit.item.set, one.name);
      }
    }
  }
  return out;
}

/**
 * **Changes**, in order, all or none: {extras, said} or {why}.
 *
 *   {op: "add_modifier", name, kind}
 *   {op: "add_set", name, size, strengths: [".3", ".6"]}   a filter per strength, "<set> <strength>"
 *   {op: "add_filter", name, set, size}                    into a set (named or id), or alone with a size
 *   {op: "rename", id, name}
 *   {op: "edit", id, kind | size}
 *   {op: "move", id, set}                                  a filter into a set, or "" out of one
 *   {op: "remove", id}                                     only when no sheet carries it (a set only when empty)
 */
export function applyExtrasOps(libIn, ops, usage = {}) {
  if (!Array.isArray(ops) || !ops.length) return { why: "Say what changes: a list of {op, …}." };
  if (ops.length > MAX.ops) return { why: "Too many changes at once." };
  const lib = JSON.parse(JSON.stringify(libIn));
  lib.merged = lib.merged || {};
  const said = [];
  const taken = () => new Set([...lib.modifiers, ...lib.sets, ...lib.filters].map((x) => x.id).concat(Object.keys(lib.merged)));
  const free = (name, except = "") => ![...lib.modifiers, ...lib.sets, ...lib.filters].some((x) => x.id !== except && low(x.name) === low(name));
  const setOf = (said, create) => {
    const s = squash(said);
    if (!s) return { set: "" };
    const hit = lib.sets.find((x) => x.id === s) || lib.sets.find((x) => low(x.name) === low(s));
    if (hit) return { set: hit.id };
    if (!create) return { why: `No filter set called ${s}.` };
    if (!free(s)) return { why: `${s} is a filter or modifier, not a set.` };
    const id = idFor("g", s, taken());
    lib.sets.push({ id, name: s, size: "" });
    return { set: id };
  };
  for (const o of ops) {
    if (!isObject(o)) return { why: "Each change is {op, …}." };
    const op = String(o.op || "");
    if (op === "add_modifier") {
      const name = squash(o.name);
      if (!name) return { why: "A new modifier needs its full name." };
      if (!free(name)) return { why: `The library has ${name} already.` };
      const m = { id: idFor("x", name, taken()), name, kind: kindOf(name, o.kind) };
      lib.modifiers.push(m);
      said.push(`Added ${name}.`);
      continue;
    }
    if (op === "add_set") {
      const name = squash(o.name);
      if (!name) return { why: "A new filter set needs a name." };
      if (!free(name)) return { why: `The library has ${name} already.` };
      const set = { id: idFor("g", name, taken()), name, size: sizeOf(o.size) };
      lib.sets.push(set);
      const strengths = (Array.isArray(o.strengths) ? o.strengths : String(o.strengths || "").split(/[,\n]/)).map(squash).filter(Boolean);
      for (const st of strengths) {
        const fname = `${name} ${st}`;
        if (!free(fname)) return { why: `The library has ${fname} already.` };
        lib.filters.push({ id: idFor("f", fname, taken()), name: fname, set: set.id, size: "" });
      }
      said.push(`Added ${name}${strengths.length ? `, ${strengths.length} filter${strengths.length === 1 ? "" : "s"}` : ""}.`);
      continue;
    }
    if (op === "add_filter") {
      const name = squash(o.name);
      if (!name) return { why: "A new filter needs its full name." };
      if (!free(name)) return { why: `The library has ${name} already.` };
      const s = setOf(o.set, true);
      if (s.why) return s;
      lib.filters.push({ id: idFor("f", name, taken()), name, set: s.set, size: s.set ? "" : sizeOf(o.size) });
      said.push(`Added ${name}.`);
      continue;
    }
    const found = extraOf(lib, o.id);
    if (!found) return { why: `No modifier, filter or set called “${squash(o.id)}”.` };
    const it = found.item;
    if (op === "rename") {
      const name = squash(o.name || o.to);
      if (!name) return { why: "Say the new name." };
      if (!free(name, it.id)) return { why: `The library has ${name} already.` };
      said.push(`Renamed ${it.name} to ${name}.`);
      it.name = name;
      if (found.kind === "modifier" && !o.kind) it.kind = kindOf(name, it.kind);
      continue;
    }
    if (op === "edit") {
      if (found.kind === "modifier" && o.kind !== undefined) it.kind = kindOf(it.name, o.kind);
      if (found.kind !== "modifier" && o.size !== undefined) {
        if (found.kind === "filter" && it.set) return { why: `${it.name} takes its set's size. Change the set's.` };
        it.size = sizeOf(o.size);
      }
      said.push(`Changed ${it.name}.`);
      continue;
    }
    if (op === "move") {
      if (found.kind !== "filter") return { why: "Only a filter moves into a set." };
      const s = setOf(o.set, true);
      if (s.why) return s;
      it.set = s.set;
      if (s.set) it.size = "";
      said.push(s.set ? `Moved ${it.name} into ${lib.sets.find((x) => x.id === s.set).name}.` : `Took ${it.name} out of its set.`);
      continue;
    }
    if (op === "remove") {
      const uses = usage[it.id] || [];
      if (uses.length) return { why: `${it.name} is on ${uses.length} spec sheet${uses.length === 1 ? "" : "s"} (${uses.slice(0, 4).join(", ")}). Nothing removed.`, used: uses };
      if (found.kind === "set" && filtersIn(lib, it).length) return { why: `${it.name} still holds filters. Remove or move them first.` };
      lib.modifiers = lib.modifiers.filter((x) => x.id !== it.id);
      lib.sets = lib.sets.filter((x) => x.id !== it.id);
      lib.filters = lib.filters.filter((x) => x.id !== it.id);
      said.push(`Removed ${it.name}.`);
      continue;
    }
    return { why: `No such change “${op}”. add_modifier, add_set, add_filter, rename, edit, move or remove.` };
  }
  const checked = checkExtras(lib);
  if (checked.why) return checked;
  return { extras: checked.extras, said };
}

export async function readExtras(env) {
  const got = await readStudioList(env, EXTRAS_KEY, seedExtras, (raw) => {
    const c = checkExtras(raw);
    return c.why ? c : { list: c.extras };
  });
  return { extras: got.list, seeded: got.seeded, held: got };
}

export async function changeExtras(env, { ops, base, by = "", look = false } = {}) {
  const held = await readExtras(env);
  if (!look && base !== undefined && Number(base) !== held.extras.v) {
    return { status: 409, why: `The modifiers and filters changed since they were read (now version ${held.extras.v}). Read them again.`, v: held.extras.v };
  }
  const usage = extrasUsageOf(held.extras, await everySheet(env));
  const got = applyExtrasOps(held.extras, ops, usage);
  if (got.why) return { status: 400, why: got.why, ...(got.used ? { used: got.used } : {}) };
  if (look) return { status: 200, look: true, written: false, said: got.said, extras: extrasView({ ...got.extras, v: held.extras.v }) };
  const written = await writeStudioList(env, EXTRAS_KEY, held.held, got.extras, by);
  if (!written) return { status: 409, why: "The modifiers and filters changed while this was being written. Read them again." };
  return { status: 200, written: true, said: got.said, extras: extrasView(written) };
}
