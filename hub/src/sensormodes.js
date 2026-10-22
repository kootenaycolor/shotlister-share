/**
 * **The sensor mode library** (2026-10-14, phase 2 of `design/spec-sheet.md`).
 *
 * One studio wide list of sensor modes on the hub (`s/sensor-modes.json`),
 * beside the lens library. Still no table of cameras: he types the
 * millimetres himself (his ruling of 2026-10-01) and keeps them under a name.
 *
 *   { format: 1, v, modes: [{ id: "m-…", body, name, width, height, capture }], merged, at, by }
 *
 * - **A mode belongs to a camera body** (his ruling, 2026-10-14: *"shooting
 *   formats are directly tied to camera bodies … each camera has its own
 *   sensor modes"*). `body` is the Camera pill ("Sony FX6"); a name is unique
 *   only within its body, so two bodies can each have an "Open Gate". A
 *   camera on a sheet is offered, and can be given, only its own body's
 *   modes. A mode kept from before the ruling may have no body yet ("").
 * - A **mode** is a name that stands for a size: `width` and `height` in
 *   millimetres (numbers, or null while he has not typed them), and a capture
 *   resolution ("8640 x 5760", or "").
 * - **Shooting Format and the sensor mode are one pill** (his decision,
 *   2026-10-14). On a sheet a camera's `format` is the mode's name, and
 *   picking a mode (`pickMode`) also gives the camera `sensor` — {ref, name,
 *   width, height}, the size kept beside the name as it was when picked — and
 *   the mode's capture resolution, which stays editable on that camera.
 * - A mode with no size yet is listed as needing one (`needsSize`). Nothing
 *   here ever guesses a size.
 *
 * **Seeded** only from what he already typed: the one preset on his Mac
 * (`SensorPresets` in studio/Sources/DiagramSensors.swift, "Alexa Mini LF Open
 * Gate", 36.70 x 25.54 mm, no capture resolution typed) and the ten moved
 * sheets' Shooting Format pills with the Capture Resolution each was shot
 * at, their sizes left empty.
 */
import { idFor, REF, readStudioList, writeStudioList, everySheet } from "./lenslibrary.js";

export const MODES_KEY = "s/sensor-modes.json";

const MAX = { modes: 300, word: 120, ops: 100 };
const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
const low = (s) => squash(s).toLowerCase();
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);

/** The seed: his Mac's one preset, then each Shooting Format the sheets used. */
export const SEED_MODES = [
  { body: "Alexa Mini LF", name: "Open Gate", width: 36.7, height: 25.54, capture: "" },
  { body: "Sony Venice 2", name: "8.6K 3:2", capture: "8640 x 5760" },
  { body: "Alexa 35", name: "4.6K 16:9", capture: "4096 x 2304" },
  { body: "Alexa Mini LF", name: "4.3K LF 16:9 UHD", capture: "3840 x 2160" },
  { body: "Arri Alexa Mini", name: "3.2K", capture: "3200 x 1800" },
  { body: "Arri Alexa Mini", name: "2.8K 4:3", capture: "" },
  { body: "Arri Alexa Mini", name: "S16 Crop Mode", capture: "1920 x 1080" },
  { body: "Sony FX6", name: "S35 Sensor", capture: "3840 x 2160" },
];

export function seedModes() {
  const taken = new Set();
  const modes = SEED_MODES.map((m) => {
    const id = idFor("m", `${m.body} ${m.name}`, taken);
    taken.add(id);
    return { id, body: m.body, name: m.name, width: m.width ?? null, height: m.height ?? null, capture: m.capture || "" };
  });
  return { format: 1, v: 0, modes, merged: {}, at: "", by: "" };
}

/** Millimetres: a number above 0 and under 100, two places; "" or null is none yet. */
function mmOf(raw, what) {
  if (raw === null || raw === undefined || raw === "") return { mm: null };
  const n = typeof raw === "number" ? raw : Number(String(raw).replace(/mm$/i, "").trim());
  if (!Number.isFinite(n) || n <= 0 || n >= 100) return { why: `${what} is millimetres, more than 0 and under 100.` };
  return { mm: Math.round(n * 100) / 100 };
}

/** A capture resolution as the pills write it: "8640 x 5760". */
export function captureOf(raw) {
  const s = squash(raw);
  if (!s) return { capture: "" };
  const m = /^(\d{3,5})\s*[x×]\s*(\d{3,5})$/i.exec(s);
  if (!m) return { why: `“${s}” is not a capture resolution (8640 x 5760).` };
  return { capture: `${m[1]} x ${m[2]}` };
}

/** True when a mode has no size typed yet. */
export const needsSize = (mode) => mode.width == null || mode.height == null;

/** True when two body names are the same camera ("sony fx6" is "Sony FX6"). */
export const sameBody = (a, b) => low(a) === low(b);
/** A mode as people read it out of its list: "Sony FX6 · Full Frame". */
export const modeWords = (m) => (m.body ? `${m.body} · ${m.name}` : m.name);

export function checkModes(raw) {
  if (!isObject(raw)) return { why: "The sensor modes are an object." };
  const list = Array.isArray(raw.modes) ? raw.modes : [];
  if (list.length > MAX.modes) return { why: "Too many sensor modes." };
  const modes = [];
  for (const m of list) {
    if (!isObject(m)) return { why: "Each mode is {id, body, name, width, height, capture}." };
    const name = squash(m.name);
    const body = squash(m.body);
    if (!name || name.length > MAX.word) return { why: "A sensor mode needs a name." };
    if (body.length > MAX.word) return { why: `${name}'s camera body is too long.` };
    if (!REF.test(String(m.id)) || !String(m.id).startsWith("m-") || modes.some((x) => x.id === m.id)) return { why: `${name} has no proper id.` };
    if (modes.some((x) => sameBody(x.body, body) && low(x.name) === low(name))) return { why: `Two ${body ? body + " " : ""}modes are called ${name}.` };
    const w = mmOf(m.width, `${name}'s width`);
    if (w.why) return w;
    const h = mmOf(m.height, `${name}'s height`);
    if (h.why) return h;
    const c = captureOf(m.capture);
    if (c.why) return c;
    modes.push({ id: m.id, body, name, width: w.mm, height: h.mm, capture: c.capture });
  }
  const merged = {};
  for (const [from, to] of Object.entries(isObject(raw.merged) ? raw.merged : {})) {
    if (REF.test(from) && REF.test(String(to)) && !modes.some((x) => x.id === from)) merged[from] = String(to);
  }
  return { modes: { format: 1, v: Number.isInteger(raw.v) && raw.v >= 0 ? raw.v : 0, modes, merged, at: squash(raw.at).slice(0, 40), by: squash(raw.by).slice(0, 80) } };
}

const resolve = (lib, ref) => {
  let id = String(ref || "");
  for (let i = 0; i < 20 && lib.merged && lib.merged[id]; i++) id = lib.merged[id];
  return id;
};

/**
 * A mode by its id, or by its name for a `body` (the camera's): that body's
 * mode of the name, else one kept with no body yet. With no body given, a
 * name only answers when one body has it ("Body · Name" says which). Or null.
 */
export function modeOf(lib, said, body = "") {
  const s = squash(said);
  if (!s) return null;
  const id = resolve(lib, s);
  const byId = lib.modes.find((m) => m.id === id);
  if (byId) return byId;
  const dot = /^(.+?)\s*·\s*(.+)$/.exec(s);
  const [b, n] = dot ? [dot[1], dot[2]] : [body, s];
  const named = lib.modes.filter((m) => low(m.name) === low(n));
  if (squash(b)) return named.find((m) => sameBody(m.body, b)) || named.find((m) => !m.body) || null;
  return named.length === 1 ? named[0] : null;
}

/** A body's own modes (and those kept with no body yet). */
export const modesFor = (lib, body) => lib.modes.filter((m) => !m.body || !squash(body) || sameBody(m.body, body));

/** The list as a screen reads it: each mode, and which still need a size. */
export function modesView(lib) {
  return {
    v: lib.v,
    modes: lib.modes.map((m) => ({ ...m, needs_size: needsSize(m) })),
    needing_size: lib.modes.filter(needsSize).map(modeWords),
    // each camera body with its own modes, in the order first met
    bodies: [...new Set(lib.modes.map((m) => m.body))].map((body) => ({ body, modes: lib.modes.filter((m) => m.body === body).map((m) => m.id) })),
  };
}

/**
 * **A mode picked for a camera** (or every camera, `label` left empty): the
 * camera's Shooting Format becomes the mode's name, its `sensor` the mode's
 * size, and its capture resolution the mode's when the mode has one. The
 * caller writes the sheet through `checkSheet`. {sheet, cameras} or {why}.
 */
export function pickMode(sheetIn, lib, label, said) {
  const sheet = JSON.parse(JSON.stringify(sheetIn));
  const key = (s) => low(s).replace(/[\s\-_]/g, "");
  const cams = squash(label) ? sheet.cameras.filter((c) => key(c.label) === key(label)) : sheet.cameras;
  if (!cams.length) return { why: `No camera called ${squash(label)} on this sheet. ${sheet.cameras.map((c) => c.label).join(", ")}.` };
  // each camera its own body's mode: one name can be a mode on two bodies
  const picks = [];
  for (const c of cams) {
    const mode = modeOf(lib, said, c.body);
    if (!mode) {
      const own = modesFor(lib, c.body).map((m) => m.name);
      return { why: `${c.body || c.label} has no sensor mode called “${squash(said)}”.${own.length ? ` Its modes: ${own.join(", ")}.` : " It has no modes yet."}` };
    }
    if (mode.body && c.body && !sameBody(mode.body, c.body)) return { why: `${mode.name} is a ${mode.body} mode; ${c.label} is a ${c.body}.` };
    picks.push([c, mode]);
  }
  for (const [c, mode] of picks) {
    c.format = [mode.name];
    c.sensor = { ref: mode.id, name: mode.name, width: mode.width, height: mode.height };
    if (mode.capture) c.capture = [mode.capture];
  }
  return { sheet, cameras: cams.map((c) => c.label), mode: picks[0][1] };
}

/** {mode id: ["Halcyon", …]}: which sheets use each mode, by ref or by Shooting Format. */
export function modeUsageOf(lib, sheets) {
  const out = {};
  for (const one of sheets) {
    for (const cam of one.sheet.cameras || []) {
      const hit = (cam.sensor && cam.sensor.ref && modeOf(lib, cam.sensor.ref)) || (cam.format || []).map((f) => modeOf(lib, f, cam.body)).find(Boolean);
      if (!hit) continue;
      out[hit.id] = out[hit.id] || [];
      if (!out[hit.id].includes(one.name)) out[hit.id].push(one.name);
    }
  }
  return out;
}

/**
 * **Changes to the modes**, in order, all or none: {modes, said} or {why}.
 *
 *   {op: "add", body, name, width, height, capture}
 *   {op: "edit", id, body, width, height, capture}   what is given changes ("" clears it)
 *   {op: "rename", id, name}                   unique within its body
 *   {op: "merge", keep, drop}
 *   {op: "remove", id}                         only when no sheet uses it
 */
export function applyModeOps(libIn, ops, usage = {}) {
  if (!Array.isArray(ops) || !ops.length) return { why: "Say what changes: a list of {op, …}." };
  if (ops.length > MAX.ops) return { why: "Too many changes at once." };
  const lib = JSON.parse(JSON.stringify(libIn));
  lib.merged = lib.merged || {};
  const said = [];
  const free = (name, body, except = "") => !lib.modes.some((m) => m.id !== except && sameBody(m.body, body) && low(m.name) === low(name));
  const sizeFrom = (o, into) => {
    for (const side of ["width", "height"]) {
      if (o[side] === undefined) continue;
      const got = mmOf(o[side], `The ${side}`);
      if (got.why) return got;
      into[side] = got.mm;
    }
    if (o.capture !== undefined) {
      const c = captureOf(o.capture);
      if (c.why) return c;
      into.capture = c.capture;
    }
    return null;
  };
  for (const o of ops) {
    if (!isObject(o)) return { why: "Each change is {op, …}." };
    const op = String(o.op || "");
    if (op === "add") {
      const name = squash(o.name);
      const body = squash(o.body);
      if (!name) return { why: "A new sensor mode needs a name." };
      if (!body) return { why: `Say which camera body ${name} is a mode of.` };
      if (!free(name, body)) return { why: `${body} has a mode called ${name} already.` };
      const mode = { id: idFor("m", `${body} ${name}`, new Set([...lib.modes.map((m) => m.id), ...Object.keys(lib.merged)])), body, name, width: null, height: null, capture: "" };
      const bad = sizeFrom(o, mode);
      if (bad) return bad;
      lib.modes.push(mode);
      said.push(`Added ${modeWords(mode)}${needsSize(mode) ? ", needing a size" : ""}.`);
      continue;
    }
    if (op === "merge") {
      const keep = modeOf(lib, o.keep);
      const drop = modeOf(lib, o.drop);
      if (!keep || !drop) return { why: "Say which two to merge: keep and drop." };
      if (keep.id === drop.id) return { why: "Those are the same mode already." };
      if (keep.body && drop.body && !sameBody(keep.body, drop.body)) return { why: `${modeWords(drop)} and ${modeWords(keep)} are modes of two bodies. Nothing merged.` };
      if (!keep.body) keep.body = drop.body;
      if (keep.width == null && keep.height == null) { keep.width = drop.width; keep.height = drop.height; }
      if (!keep.capture) keep.capture = drop.capture;
      lib.modes = lib.modes.filter((m) => m.id !== drop.id);
      lib.merged[drop.id] = keep.id;
      for (const [from, to] of Object.entries(lib.merged)) if (to === drop.id) lib.merged[from] = keep.id;
      said.push(`Merged ${drop.name} into ${keep.name}.`);
      continue;
    }
    const mode = modeOf(lib, o.id || o.mode);
    if (!mode) return { why: `No sensor mode called “${squash(o.id || o.mode)}”.` };
    if (op === "edit") {
      if (o.body !== undefined) {
        const body = squash(o.body);
        if (!body) return { why: `Say which camera body ${mode.name} is a mode of.` };
        if (!free(mode.name, body, mode.id)) return { why: `${body} has a mode called ${mode.name} already.` };
        mode.body = body;
      }
      const bad = sizeFrom(o, mode);
      if (bad) return bad;
      said.push(`Changed ${modeWords(mode)}.`);
      continue;
    }
    if (op === "rename") {
      const name = squash(o.name || o.to);
      if (!name) return { why: "Say the new name." };
      if (!free(name, mode.body, mode.id)) return { why: `${mode.body || "That body"} has a mode called ${name} already.` };
      said.push(`Renamed ${mode.name} to ${name}.`);
      mode.name = name;
      continue;
    }
    if (op === "remove") {
      const uses = usage[mode.id] || [];
      if (uses.length) return { why: `${mode.name} is on ${uses.length} spec sheet${uses.length === 1 ? "" : "s"} (${uses.slice(0, 4).join(", ")}). Nothing removed.`, used: uses };
      lib.modes = lib.modes.filter((m) => m.id !== mode.id);
      for (const [from, to] of Object.entries(lib.merged)) if (to === mode.id) delete lib.merged[from];
      said.push(`Removed ${mode.name}.`);
      continue;
    }
    return { why: `No such change “${op}”. add, edit, rename, merge or remove.` };
  }
  const checked = checkModes(lib);
  if (checked.why) return checked;
  return { modes: checked.modes, said };
}

export async function readModes(env) {
  const got = await readStudioList(env, MODES_KEY, seedModes, checkModes);
  return { modes: got.list, seeded: got.seeded, held: got };
}

/** The door's change, as `changeLibrary` in lenslibrary.js: `look` writes nothing. */
export async function changeModes(env, { ops, base, by = "", look = false } = {}) {
  const held = await readModes(env);
  if (!look && base !== undefined && Number(base) !== held.modes.v) {
    return { status: 409, why: `The sensor modes changed since they were read (now version ${held.modes.v}). Read them again.`, v: held.modes.v };
  }
  const usage = modeUsageOf(held.modes, await everySheet(env));
  const got = applyModeOps(held.modes, ops, usage);
  if (got.why) return { status: 400, why: got.why, ...(got.used ? { used: got.used } : {}) };
  if (look) return { status: 200, look: true, written: false, said: got.said, modes: modesView({ ...got.modes, v: held.modes.v }) };
  const written = await writeStudioList(env, MODES_KEY, held.held, got.modes, by);
  if (!written) return { status: 409, why: "The sensor modes changed while this was being written. Read them again." };
  return { status: 200, written: true, said: got.said, modes: modesView(written) };
}
