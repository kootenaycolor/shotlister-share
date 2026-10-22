/**
 * **The lens library** (2026-10-14, phase 2 of `design/spec-sheet.md`).
 *
 * One library for every project, kept on the hub as a studio file
 * (`s/lens-library.json`). Every sheet's Lenses pool picks from it.
 *
 *   { format: 1, v,
 *     sets:   [{ id: "s-…", name, whole }],
 *     lenses: [{ id: "l-…", name, focal, stop, set, close_focus?, close_focus_m? }],
 *     merged: { old id: id it became }, at, by }
 *
 * - A **lens** is its full name ("Master Prime 25mm"), its focal length or
 *   range as he would say it ("25", "8-64", or "" when not on record), its
 *   stop ("T1.3": T-stops belong to the lens, his ruling) and the set it is
 *   in (a set id, or "" for a lens on its own, such as a zoom). Optionally
 *   its **close focus** (2026-10-15): as he typed it ("0.35 m", "1'2\"",
 *   "14 in"), kept only when set, with `close_focus_m`, the same in metres,
 *   when it reads as a distance. Shown as "CF 0.35 m" wherever a lens's
 *   details show, and nowhere when empty.
 * - A **set** is a name and, in the order kept here, its lenses. A set sold
 *   whole with no focal lengths on record (Tribe7 Blackwings, Signature
 *   Primes) is marked `whole`: it holds no lenses and goes on a sheet as one
 *   entry, named as the set.
 * - Names are written out in full. There is no short name, on purpose.
 *
 * **On a sheet** (specsheet.js) a lens is {name, note, ref, stop, set}: `ref`
 * is the library id, and `name` is the library's name as it was when picked,
 * kept beside it so renaming a lens here never changes a sheet that has gone
 * out. `renameOffers` names the sheets' lenses the library now calls
 * something else, for a screen to offer, never to apply by itself.
 *
 * **Merging** two entries that are the same lens keeps one and remembers the
 * other's id in `merged`, so a sheet that points at the old id still finds it.
 * **Removing** is refused while any sheet on any record uses the entry.
 *
 * **Seeded** from what the ten moved sheets already say: Notion's Lenses
 * pills and the stops and sets the Old Lenses text kept. Nothing invented:
 * a focal or stop not on record is left blank. The seed is only what a read
 * answers until the first write; nothing is written to seed it.
 */

export const LENS_KEY = "s/lens-library.json";

const MAX = { lenses: 600, sets: 200, word: 120, focal: 24, stop: 24, cf: 24, ops: 100 };
const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
const low = (s) => squash(s).toLowerCase();
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
export const REF = /^[lsm]-[a-z0-9]+(?:-\d+)?$/;

/** An id from a name: "l-masterprime25mm", "-2" after it when taken. */
export function idFor(prefix, name, taken) {
  const base = `${prefix}-${low(name).replace(/[^a-z0-9]/g, "").slice(0, 60) || "x"}`;
  let id = base;
  for (let n = 2; taken.has(id); n++) id = `${base}-${n}`;
  return id;
}

// ------------------------------------------------------------------- the seed

const MASTER_PRIMES = [16, 18, 21, 25, 27, 35, 40, 50, 65, 75, 100, 135];

/** The library as the ten moved sheets already describe it. */
export function seedLibrary() {
  const sets = [
    { name: "ARRI Master Primes", whole: false },
    { name: "Tribe7 Blackwings", whole: true },
    { name: "Signature Primes", whole: true },
    { name: "Arriflex S16 Super Speed", whole: true },
    { name: "Zeiss Superspeed", whole: true },
    { name: "Panavision Panaspeed", whole: true },
    { name: "Second Reef Coral Anamorphic", whole: true },
  ];
  const lenses = [
    ...MASTER_PRIMES.map((mm) => ({ name: `Master Prime ${mm}mm`, focal: String(mm), stop: "T1.3", set: "ARRI Master Primes" })),
    { name: "Fujinon Cabrio 19-90mm", focal: "19-90", stop: "T2.9" },
    { name: "Fujinon Premier 75-400mm", focal: "75-400", stop: "T2.8-3.8" },
    { name: "Atlas LF Extender 1.6x" },
    { name: "Sony G Master 24-70mm", focal: "24-70" },
    { name: "Laowa Probe2" },
    { name: "Angenieux Optimo 45-165mm", focal: "45-165", stop: "T2.3" },
    { name: "Canon Super 16 11-165mm", focal: "11-165" },
    { name: "Canon 8-64mm", focal: "8-64", stop: "T2.2" },
  ];
  const taken = new Set();
  const lib = { format: 1, v: 0, sets: [], lenses: [], merged: {}, at: "", by: "" };
  for (const s of sets) {
    const id = idFor("s", s.name, taken);
    taken.add(id);
    lib.sets.push({ id, name: s.name, whole: s.whole });
  }
  for (const l of lenses) {
    const id = idFor("l", l.name, taken);
    taken.add(id);
    const set = l.set ? lib.sets.find((s) => s.name === l.set).id : "";
    lib.lenses.push({ id, name: l.name, focal: l.focal || "", stop: l.stop || "", set });
  }
  return lib;
}

// ----------------------------------------------------------------- the checks

/** A focal as he writes it: "25", "8-64", "19-90"; "mm" and spaces dropped. */
function focalOf(raw) {
  const f = squash(raw).toLowerCase().replace(/mm$/, "").replace(/\s*[-–]\s*/g, "-").trim();
  if (!f) return { focal: "" };
  if (!/^\d+(\.\d+)?(-\d+(\.\d+)?)?$/.test(f) || f.length > MAX.focal) return { why: `“${squash(raw)}” is not a focal length (25, or 8-64).` };
  return { focal: f };
}

function stopOf(raw) {
  const s = squash(raw);
  if (!s) return { stop: "" };
  const t = /^t/i.test(s) ? `T${s.slice(1)}` : `T${s}`;
  if (!/^T\d+(\.\d+)?(-\d+(\.\d+)?)?$/.test(t)) return { why: `“${s}” is not a stop (T1.3, or T2.8-3.8).` };
  return { stop: t };
}

/**
 * A close focus as he typed it: {close_focus, close_focus_m?} or {why}. Metres
 * ("0.35 m", "0.35", "35 cm") or feet and inches ("1'2\"", "1 ft 2 in",
 * "14 in", "2'"); `close_focus_m` is the distance in metres when it reads as
 * one, else left off (the words are kept as typed either way).
 */
export function closeFocusOf(raw) {
  const said = squash(raw).replace(/[’′]/g, "'").replace(/[”″]/g, '"');
  if (!said) return { close_focus: "" };
  if (said.length > MAX.cf) return { why: `“${said.slice(0, 30)}” is too long for a close focus.` };
  const t = said.toLowerCase().replace(/^cf\s*/, "");
  const num = "(\\d+(?:\\.\\d+)?)";
  let m;
  let metres = null;
  if ((m = t.match(new RegExp(`^${num}\\s*(m|metres?|meters?)?$`)))) metres = Number(m[1]);
  else if ((m = t.match(new RegExp(`^${num}\\s*cm$`)))) metres = Number(m[1]) / 100;
  else if ((m = t.match(new RegExp(`^${num}\\s*(?:'|ft|feet|foot)\\s*(?:${num}\\s*(?:"|in|inch|inches)?)?$`)))) metres = Number(m[1]) * 0.3048 + (m[2] ? Number(m[2]) * 0.0254 : 0);
  else if ((m = t.match(new RegExp(`^${num}\\s*(?:"|in|inch|inches)$`)))) metres = Number(m[1]) * 0.0254;
  const ok = metres !== null && Number.isFinite(metres) && metres > 0 && metres < 100;
  return { close_focus: said, ...(ok ? { close_focus_m: Math.round(metres * 1000) / 1000 } : {}) };
}

/** A lens's close focus as a short label: "CF 0.35 m", or "" when not set. */
export const cfLabel = (lens) => (lens && lens.close_focus ? `CF ${String(lens.close_focus).replace(/^cf\s*/i, "")}` : "");

/** Lay a close focus on a lens (kept only when set). */
function setCf(lens, raw) {
  const cf = closeFocusOf(raw);
  if (cf.why) return cf;
  delete lens.close_focus;
  delete lens.close_focus_m;
  if (cf.close_focus) Object.assign(lens, cf);
  return {};
}

/** A library, checked and tidied: {library} or {why}. */
export function checkLibrary(raw) {
  if (!isObject(raw)) return { why: "A lens library is an object." };
  const sets = Array.isArray(raw.sets) ? raw.sets : [];
  const lenses = Array.isArray(raw.lenses) ? raw.lenses : [];
  if (sets.length > MAX.sets || lenses.length > MAX.lenses) return { why: "The lens library is too big." };
  const names = new Set();
  const ids = new Set();
  const outSets = [];
  for (const s of sets) {
    if (!isObject(s)) return { why: "Each set is {id, name, whole}." };
    const name = squash(s.name);
    if (!name || name.length > MAX.word) return { why: "A set needs a name." };
    if (!REF.test(String(s.id)) || !String(s.id).startsWith("s-") || ids.has(s.id)) return { why: `${name} has no proper id.` };
    if (names.has(low(name))) return { why: `Two entries are called ${name}.` };
    names.add(low(name));
    ids.add(s.id);
    outSets.push({ id: s.id, name, whole: Boolean(s.whole) });
  }
  const outLenses = [];
  for (const l of lenses) {
    if (!isObject(l)) return { why: "Each lens is {id, name, focal, stop, set}." };
    const name = squash(l.name);
    if (!name || name.length > MAX.word) return { why: "A lens needs a name." };
    if (!REF.test(String(l.id)) || !String(l.id).startsWith("l-") || ids.has(l.id)) return { why: `${name} has no proper id.` };
    if (names.has(low(name))) return { why: `Two entries are called ${name}.` };
    const f = focalOf(l.focal);
    if (f.why) return f;
    const st = stopOf(l.stop);
    if (st.why) return st;
    const set = String(l.set || "");
    const home = set ? outSets.find((s) => s.id === set) : null;
    if (set && !home) return { why: `${name} is in a set the library does not have.` };
    if (home && home.whole) return { why: `${home.name} is sold whole; it holds no lenses of its own.` };
    names.add(low(name));
    ids.add(l.id);
    const lens = { id: l.id, name, focal: f.focal, stop: st.stop, set };
    const cf = setCf(lens, l.close_focus);
    if (cf.why) return { why: `${name}: ${cf.why}` };
    outLenses.push(lens);
  }
  const merged = {};
  for (const [from, to] of Object.entries(isObject(raw.merged) ? raw.merged : {})) {
    if (REF.test(from) && REF.test(String(to)) && !ids.has(from)) merged[from] = String(to);
  }
  return {
    library: {
      format: 1, v: Number.isInteger(raw.v) && raw.v >= 0 ? raw.v : 0,
      sets: outSets, lenses: outLenses, merged,
      at: squash(raw.at).slice(0, 40), by: squash(raw.by).slice(0, 80),
    },
  };
}

// ---------------------------------------------------------------- looking up

/** An id followed through merges to what it is now. */
export function resolveRef(lib, ref) {
  let id = String(ref || "");
  for (let i = 0; i < 20 && lib.merged && lib.merged[id]; i++) id = lib.merged[id];
  return id;
}

/** {kind: "lens"|"set", item} for an id or a name, or null. */
export function itemOf(lib, said) {
  const s = squash(said);
  if (!s) return null;
  const id = resolveRef(lib, s);
  const lens = lib.lenses.find((l) => l.id === id) || lib.lenses.find((l) => low(l.name) === low(s));
  if (lens) return { kind: "lens", item: lens };
  const set = lib.sets.find((x) => x.id === id) || lib.sets.find((x) => low(x.name) === low(s));
  return set ? { kind: "set", item: set } : null;
}

/** A set's lenses, in the library's order. */
export const lensesIn = (lib, set) => lib.lenses.filter((l) => l.set === set.id);

/** The library laid out as a screen reads it: sets with their lenses, then lenses on their own. */
export function libraryView(lib) {
  return {
    v: lib.v,
    sets: lib.sets.map((s) => ({ ...s, lenses: s.whole ? [] : lensesIn(lib, s).map(({ set, ...l }) => l) })),
    alone: lib.lenses.filter((l) => !l.set).map(({ set, ...l }) => l),
    counts: { sets: lib.sets.length, lenses: lib.lenses.length, whole: lib.sets.filter((s) => s.whole).length },
  };
}

/**
 * **What a pick puts on a sheet**: a lens is one entry; a set every lens in
 * it, in order; a set marked whole one entry named as the set. Each entry
 * carries its library name, its id, and its stop and set as the library has
 * them now.
 */
export function entriesFor(lib, found) {
  const one = (l) => {
    const set = l.set ? lib.sets.find((s) => s.id === l.set) : null;
    return { name: l.name, note: "", ref: l.id, ...(l.stop ? { stop: l.stop } : {}), ...(set ? { set: set.name } : {}) };
  };
  if (found.kind === "lens") return [one(found.item)];
  if (found.item.whole) return [{ name: found.item.name, note: "", ref: found.item.id }];
  return lensesIn(lib, found.item).map(one);
}

/** The library entry a sheet's lens is: by its ref, else by its name. */
export function entryOfSheetLens(lib, lens) {
  if (lens.ref) {
    const id = resolveRef(lib, lens.ref);
    const hit = lib.lenses.find((l) => l.id === id) || lib.sets.find((s) => s.id === id);
    if (hit) return hit;
  }
  const n = low(lens.name);
  return lib.lenses.find((l) => low(l.name) === n) || lib.sets.find((s) => low(s.name) === n) || null;
}

/** The sheet's lenses the library now names otherwise: [{name, now, ref}]. Never applied. */
export function renameOffers(sheet, lib) {
  const out = [];
  for (const lens of (sheet && sheet.lenses) || []) {
    if (!lens.ref) continue;
    const hit = entryOfSheetLens(lib, lens);
    if (hit && hit.name !== lens.name) out.push({ name: lens.name, now: hit.name, ref: hit.id });
  }
  return out;
}

/**
 * **A lens a shot names, as the library names it** (Add to Spec Sheet,
 * closing Ref 1724): "Master Prime 27mm" as it is; "27mm" or "27" to the one
 * library lens of that focal, preferring a set already in the shoot's pool.
 * {name, ref, kind, entries} when found, {choices} when several fit, else null.
 */
export function matchLens(lib, said, pool = []) {
  const s = squash(said);
  if (!s) return null;
  const named = itemOf(lib, s);
  if (named) return { name: named.item.name, ref: named.item.id, kind: named.kind, entries: entriesFor(lib, named) };
  const f = focalOf(s);
  if (f.why || !f.focal) return null;
  const fits = lib.lenses.filter((l) => l.focal === f.focal);
  if (!fits.length) return null;
  const inPool = new Set(pool.map((l) => low(l.set || "")).filter(Boolean));
  const poolSets = lib.sets.filter((x) => inPool.has(low(x.name))).map((x) => x.id);
  const preferred = fits.filter((l) => l.set && poolSets.includes(l.set));
  const pick = fits.length === 1 ? fits[0] : preferred.length === 1 ? preferred[0] : null;
  if (!pick) return { choices: fits.map((l) => l.name) };
  return { name: pick.name, ref: pick.id, kind: "lens", entries: entriesFor(lib, { kind: "lens", item: pick }) };
}

/**
 * **Lenses picked onto a sheet** (a lens, a set, or a whole set, by id or
 * name). {sheet, added, already} or {why}. The sheet is not checked here;
 * the caller writes it through `checkSheet`.
 */
export function pickLenses(sheetIn, lib, said) {
  const found = itemOf(lib, said);
  if (!found) return { why: `The lens library has no “${squash(said)}”.` };
  const sheet = JSON.parse(JSON.stringify(sheetIn));
  sheet.lenses = sheet.lenses || [];
  const added = [];
  const already = [];
  for (const e of entriesFor(lib, found)) {
    const have = sheet.lenses.some((l) => (l.ref && resolveRef(lib, l.ref) === e.ref) || low(l.name) === low(e.name));
    if (have) { already.push(e.name); continue; }
    sheet.lenses.push(e);
    added.push(e.name);
  }
  return { sheet, added, already };
}

// --------------------------------------------------------------- the changes

function setOf(lib, said, { create = false } = {}) {
  const s = squash(said);
  if (!s) return { set: "" };
  const hit = itemOf(lib, s);
  if (hit && hit.kind === "set") {
    if (hit.item.whole) return { why: `${hit.item.name} is sold whole; it holds no lenses of its own.` };
    return { set: hit.item.id };
  }
  if (hit) return { why: `${hit.item.name} is a lens, not a set.` };
  if (!create) return { why: `The lens library has no set called ${s}.` };
  const taken = takenIds(lib);
  const id = idFor("s", s, taken);
  lib.sets.push({ id, name: s, whole: false });
  return { set: id, made: s };
}

const takenIds = (lib) => new Set([...lib.sets.map((s) => s.id), ...lib.lenses.map((l) => l.id), ...Object.keys(lib.merged || {})]);
const nameFree = (lib, name, except = "") => ![...lib.sets, ...lib.lenses].some((x) => x.id !== except && low(x.name) === low(name));

/**
 * **Changes to the library**, in order, all or none: {library, said} or
 * {why}. `usage` is {id: [where each sheet uses it]} (`lensUsage`), for the
 * refusal to remove one in use.
 *
 *   {op: "add", name, focal, stop, set, close_focus}   a lens; a set named that does not exist is made
 *   {op: "add_set", name, whole}          a set, empty; `whole` for one sold whole
 *   {op: "rename", id, name}              a lens or a set (id or its current name)
 *   {op: "edit", id, focal, stop, close_focus, whole}  what is given changes; `whole` only on an empty set
 *   {op: "move", id, set}                 a lens into a set, or out of one with set ""
 *   {op: "merge", keep, drop}             two entries that are the same lens (or two sets)
 *   {op: "remove", id}                    only when no sheet uses it (a set only when empty)
 */
export function applyLensOps(libIn, ops, usage = {}) {
  if (!Array.isArray(ops) || !ops.length) return { why: "Say what changes: a list of {op, …}." };
  if (ops.length > MAX.ops) return { why: "Too many changes at once." };
  const lib = JSON.parse(JSON.stringify(libIn));
  lib.merged = lib.merged || {};
  const said = [];
  for (const o of ops) {
    if (!isObject(o)) return { why: "Each change is {op, …}." };
    const op = String(o.op || "");
    if (op === "add") {
      const name = squash(o.name);
      if (!name) return { why: "A new lens needs its full name." };
      if (!nameFree(lib, name)) return { why: `The library has ${name} already.` };
      const f = focalOf(o.focal);
      if (f.why) return f;
      const st = stopOf(o.stop);
      if (st.why) return st;
      const s = setOf(lib, o.set, { create: true });
      if (s.why) return s;
      const id = idFor("l", name, takenIds(lib));
      const lens = { id, name, focal: f.focal, stop: st.stop, set: s.set };
      const cf = setCf(lens, o.close_focus);
      if (cf.why) return cf;
      lib.lenses.push(lens);
      said.push(`Added ${name}${s.set ? ` to ${lib.sets.find((x) => x.id === s.set).name}` : ""}.`);
      continue;
    }
    if (op === "add_set") {
      const name = squash(o.name);
      if (!name) return { why: "A new set needs a name." };
      if (!nameFree(lib, name)) return { why: `The library has ${name} already.` };
      const id = idFor("s", name, takenIds(lib));
      lib.sets.push({ id, name, whole: Boolean(o.whole) });
      said.push(`Added the set ${name}${o.whole ? ", sold whole" : ""}.`);
      continue;
    }
    const target = itemOf(lib, o.id || o.lens || o.set_id || (op === "merge" ? o.keep : ""));
    if (op === "rename") {
      if (!target) return { why: `The library has no “${squash(o.id)}”.` };
      const name = squash(o.name || o.to);
      if (!name) return { why: "Say the new name." };
      if (!nameFree(lib, name, target.item.id)) return { why: `The library has ${name} already.` };
      said.push(`Renamed ${target.item.name} to ${name}.`);
      target.item.name = name;
      continue;
    }
    if (op === "edit") {
      if (!target) return { why: `The library has no “${squash(o.id)}”.` };
      if (target.kind === "lens") {
        if (o.focal !== undefined) { const f = focalOf(o.focal); if (f.why) return f; target.item.focal = f.focal; }
        if (o.stop !== undefined) { const st = stopOf(o.stop); if (st.why) return st; target.item.stop = st.stop; }
        if (o.close_focus !== undefined) { const cf = setCf(target.item, o.close_focus); if (cf.why) return cf; }
      } else if (o.whole !== undefined) {
        if (o.whole && lensesIn(lib, target.item).length) return { why: `${target.item.name} holds lenses; move them out before marking it whole.` };
        target.item.whole = Boolean(o.whole);
      }
      said.push(`Changed ${target.item.name}.`);
      continue;
    }
    if (op === "move") {
      if (!target || target.kind !== "lens") return { why: `The library has no lens “${squash(o.id)}”.` };
      const s = setOf(lib, o.set, { create: true });
      if (s.why) return s;
      target.item.set = s.set;
      said.push(s.set ? `Moved ${target.item.name} into ${lib.sets.find((x) => x.id === s.set).name}.` : `${target.item.name} is a lens on its own.`);
      continue;
    }
    if (op === "merge") {
      const keep = itemOf(lib, o.keep);
      const drop = itemOf(lib, o.drop);
      if (!keep || !drop) return { why: "Say which two to merge: keep and drop." };
      if (keep.item.id === drop.item.id) return { why: "Those are the same entry already." };
      if (keep.kind !== drop.kind) return { why: "A lens merges with a lens, a set with a set." };
      if (keep.kind === "lens") {
        if (!keep.item.focal) keep.item.focal = drop.item.focal;
        if (!keep.item.stop) keep.item.stop = drop.item.stop;
        if (!keep.item.close_focus && drop.item.close_focus) setCf(keep.item, drop.item.close_focus);
        if (!keep.item.set) keep.item.set = drop.item.set;
        lib.lenses = lib.lenses.filter((l) => l.id !== drop.item.id);
      } else {
        if (keep.item.whole && lensesIn(lib, drop.item).length) return { why: `${keep.item.name} is sold whole; ${drop.item.name}'s lenses have nowhere to go.` };
        for (const l of lensesIn(lib, drop.item)) l.set = keep.item.id;
        lib.sets = lib.sets.filter((s) => s.id !== drop.item.id);
      }
      lib.merged[drop.item.id] = keep.item.id;
      for (const [from, to] of Object.entries(lib.merged)) if (to === drop.item.id) lib.merged[from] = keep.item.id;
      said.push(`Merged ${drop.item.name} into ${keep.item.name}.`);
      continue;
    }
    if (op === "remove") {
      if (!target) return { why: `The library has no “${squash(o.id)}”.` };
      const uses = usage[target.item.id] || [];
      if (uses.length) return { why: `${target.item.name} is on ${uses.length} spec sheet${uses.length === 1 ? "" : "s"} (${uses.slice(0, 4).join(", ")}). Nothing removed.`, used: uses };
      if (target.kind === "set") {
        if (lensesIn(lib, target.item).length) return { why: `${target.item.name} still holds lenses. Move or remove them first.` };
        lib.sets = lib.sets.filter((s) => s.id !== target.item.id);
      } else {
        lib.lenses = lib.lenses.filter((l) => l.id !== target.item.id);
      }
      for (const [from, to] of Object.entries(lib.merged)) if (to === target.item.id) delete lib.merged[from];
      said.push(`Removed ${target.item.name}.`);
      continue;
    }
    return { why: `No such change “${op}”. add, add_set, rename, edit, move, merge or remove.` };
  }
  const checked = checkLibrary(lib);
  if (checked.why) return checked;
  return { library: checked.library, said };
}

// ------------------------------------------------------------ the studio file

/**
 * **A studio wide list on the hub**: read it (the seed until first written)
 * and write it from the version it was read at, never over a newer one.
 * Shared by the lens library and the sensor modes.
 */
export async function readStudioList(env, key, seed, check) {
  const got = await env.BUCKET.get(key);
  if (!got) return { list: seed(), seeded: true, etag: null };
  let raw = null;
  try { raw = JSON.parse(await got.text()); } catch { raw = null; }
  const ok = check(raw);
  if (ok.why) return { list: seed(), seeded: true, etag: got.etag, broken: ok.why };
  return { list: Object.values(ok)[0], seeded: false, etag: got.etag };
}

export async function writeStudioList(env, key, held, list, by) {
  const value = { ...list, v: (held.list.v || 0) + 1, at: new Date().toISOString(), by: squash(by).slice(0, 80) };
  const put = await env.BUCKET.put(key, JSON.stringify(value), {
    httpMetadata: { contentType: "application/json" },
    onlyIf: held.etag ? { etagMatches: held.etag } : { etagDoesNotMatch: "*" },
  });
  return put ? value : null;
}

/** The library as it is now: {library, seeded}. */
export async function readLibrary(env) {
  const got = await readStudioList(env, LENS_KEY, seedLibrary, checkLibrary);
  return { library: got.list, seeded: got.seeded, etag: got.etag, held: got };
}

/** Every sheet on every record: [{page, name, fact, sheet}]. */
export async function everySheet(env) {
  const { recordSheets } = await import("./specsheet.js");
  const out = [];
  let cursor;
  for (let round = 0; round < 50; round++) {
    // one entry per record (the delimiter), not every history line under it
    const page = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const prefix of page.delimitedPrefixes || []) {
      const m = /^r\/([0-9a-f]{32})\/$/.exec(prefix);
      if (!m) continue;
      let rec = null;
      try { const got = await env.BUCKET.get(`r/${m[1]}/record.json`); rec = got ? await got.json() : null; } catch { rec = null; }
      if (!rec) continue;
      for (const [fact, one] of Object.entries(recordSheets(rec.facts || {}))) out.push({ page: m[1], name: String(rec.name || m[1]), fact, sheet: one.sheet });
    }
    if (!page.truncated) break;
    cursor = page.cursor;
  }
  return out;
}

/** {library id: ["Halcyon", …]}: which sheets use each entry, by ref or by name. */
export function lensUsageOf(lib, sheets) {
  const out = {};
  for (const one of sheets) {
    for (const lens of one.sheet.lenses || []) {
      const hit = entryOfSheetLens(lib, lens);
      if (!hit) continue;
      (out[hit.id] = out[hit.id] || []);
      if (!out[hit.id].includes(one.name)) out[hit.id].push(one.name);
    }
  }
  return out;
}

/**
 * **The door's change**: the ops applied to the library as it is, from the
 * version the asker read (`base`). `look` answers what it would become and
 * writes nothing. {status, library, said} or {status, why}.
 */
export async function changeLibrary(env, { ops, base, by = "", look = false } = {}) {
  const held = await readLibrary(env);
  if (!look && base !== undefined && Number(base) !== held.library.v) {
    return { status: 409, why: `The lens library changed since it was read (now version ${held.library.v}). Read it again.`, v: held.library.v };
  }
  const usage = lensUsageOf(held.library, await everySheet(env));
  const got = applyLensOps(held.library, ops, usage);
  if (got.why) return { status: 400, why: got.why, ...(got.used ? { used: got.used } : {}) };
  if (look) return { status: 200, look: true, written: false, said: got.said, library: libraryView({ ...got.library, v: held.library.v }) };
  const written = await writeStudioList(env, LENS_KEY, held.held, got.library, by);
  if (!written) return { status: 409, why: "The lens library changed while this was being written. Read it again." };
  return { status: 200, written: true, said: got.said, library: libraryView(written) };
}
