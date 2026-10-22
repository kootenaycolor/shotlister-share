/**
 * **Lens sets on a camera spec sheet** (2026-10-05) — `lenses.py` in Projects
 * Console, the other reader of the same words. Change one, change both; the
 * shared cases are `hub/lens-cases.json` (a copy of the console's) and
 * `hub/lenses.mjs` checks them.
 *
 * The sheet's one "Lenses" text holds one set per line:
 *
 *     A Cam: Cooke S4/i — 18, 25, 32, 50, 75, 100mm — T2 — rehoused, Keslow
 *
 * an optional camera or label before a colon, the lenses, then focal lengths,
 * stop and notes split by em dashes, in any order. A line that cannot be
 * placed stays whole in the lenses, so nothing typed is ever lost.
 */

import { splitLabel } from "./entries.js";

const FOCAL = String.raw`\d+(?:\.\d+)?(?:\s*[-–]\s*\d+(?:\.\d+)?)?\s*(?:mm)?`;
const FOCAL_LIST = new RegExp(String.raw`^${FOCAL}(?:\s*(?:,|/|&|\band\b)\s*${FOCAL})*$`, "i");
const STOP = /^(?:[Tt]\s*\/?\s*|[Ff]\s*\/\s*|[Ff](?=\d))\d+(?:\.\d+)?(?:\s*[-–]\s*\d+(?:\.\d+)?)?$/;
const TRAIL_STOP = /\s+((?:[Tt]\s*\/?\s*|[Ff]\s*\/\s*)\d+(?:\.\d+)?(?:\s*[-–]\s*\d+(?:\.\d+)?)?)$/;
const TRAIL_FOCAL = /\s+(\d+(?:\.\d+)?\s*[-–]\s*\d+(?:\.\d+)?\s*(?:mm)?|\d+(?:\.\d+)?\s*mm)$/i;
const SPLIT = /\s+[—–|]\s+|\s+-\s+/;
const CAMERA = /^(?:[A-H]\d?[\s-]?cam(?:era)?|main|specialty|special|splinter|second unit|2nd unit|drone|crash cam|steadicam|gimbal|underwater|principal|principle|pickups?)$/i;
const SEP = " — ";

/** 't/2.3' → 'T2.3', 'f / 2.8' → 'f/2.8'. */
export function stopWords(stop) {
  const s = String(stop || "").replace(/\s+/g, "");
  if (!s) return "";
  return /^[Tt]/.test(s) ? `T${s.slice(1).replace(/^\/+/, "")}` : `f/${s.slice(1).replace(/^\/+/, "")}`;
}

export function focalList(text) {
  return String(text || "").split(/\s*(?:,|\/|&|\band\b)\s*/i).map((f) => f.trim()).filter(Boolean);
}

/** One line as a set: {label, series, focals, stop, notes, raw}. */
export function parseLine(line) {
  const raw = String(line || "").trim();
  const out = { label: "", series: "", focals: [], stop: "", notes: "", raw };
  if (!raw) return out;
  // the label rule every multi-entry field shares (src/entries.js)
  let rest;
  [out.label, rest] = splitLabel(raw);
  let parts = rest.split(SPLIT).map((p) => p.trim()).filter(Boolean);
  if (!out.label && parts.length > 1 && CAMERA.test(parts[0])) {
    out.label = parts[0];
    parts = parts.slice(1);
  }
  let series = parts[0] || "";
  const notes = [];
  for (const part of parts.slice(1)) {
    if (!out.focals.length && FOCAL_LIST.test(part)) out.focals = focalList(part);
    else if (!out.stop && STOP.test(part)) out.stop = stopWords(part);
    else notes.push(part);
  }
  if (!out.stop) {
    const t = TRAIL_STOP.exec(series);
    if (t && t.index > 0) { out.stop = stopWords(t[1]); series = series.slice(0, t.index).trim(); }
  }
  if (!out.focals.length) {
    const t = TRAIL_FOCAL.exec(series);
    if (t && t.index > 0) { out.focals = [t[1].trim()]; series = series.slice(0, t.index).trim(); }
  }
  out.series = series;
  out.notes = notes.join(SEP);
  return out;
}

/** The Lenses text as its sets, one per line. */
export function lensSets(text) {
  return String(text || "").split("\n").filter((line) => line.trim()).map(parseLine);
}

/** Is this Lenses text pills (2026-10-13: one lens per line, named in full,
 * "Master Prime 25mm") rather than the old typed sets? */
export function arePills(text) {
  const lines = String(text || "").split("\n").filter((line) => line.trim());
  return lines.length > 0 && !lines.some((line) => /\s[—–|]\s|,|:\s/.test(line));
}

/** The Lenses as sets to read: pills grouped by family ("Master Prime ·
 * 16, 25, 50mm", a family where its first lens was, its primes in focal
 * order); the old typed sets as they are. `raw` keeps the pills, one per
 * line, so a set written back is the same pills. */
export function lensSetsShown(text) {
  if (!arePills(text)) return lensSets(text);
  const out = [], fams = new Map();
  for (const name of String(text).split("\n").map((x) => x.trim()).filter(Boolean)) {
    const m = /^(.*?)\s+(\d+(?:\.\d+)?(?:\s*[-–]\s*\d+(?:\.\d+)?)?\s*mm)$/i.exec(name);
    const fam = m ? m[1] : name, key = fam.toLowerCase();
    if (m && fams.has(key)) { const g = fams.get(key); g.focals.push(m[2]); g.names.push(name); continue; }
    const g = { fam, focals: m ? [m[2]] : [], names: [name] };
    out.push(g);
    if (m) fams.set(key, g);
  }
  const mm = (f) => Number.parseFloat(f) || 0;
  return out.map((g) => {
    const f = [...g.focals].sort((a, b) => mm(a) - mm(b));
    const focals = f.length > 1 ? f.map((x, i) => (i < f.length - 1 ? x.replace(/\s*mm$/i, "") : x)) : f;
    return { label: "", series: g.fam, focals, stop: "", notes: "", raw: g.names.join("\n") };
  });
}

/** Lens lines as pills, each a lens named in full — `entries.lens_pills`.
 * A line already a pill stays; a typed set ("A Cam: Master Prime — 25, 35mm
 * — T1.3", from an older screen) is one pill per focal length. */
export function lensPills(text) {
  const out = [];
  for (const raw of String(text || "").split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    if (!/\s[—–|]\s|,/.test(line) && !splitLabel(line)[0]) { out.push(line); continue; }
    const set = parseLine(line);
    const series = String(set.series || "").trim();
    const focals = (set.focals || []).map((f) => String(f).trim()).filter(Boolean);
    if (!focals.length) out.push(series || line);
    for (const f of focals) out.push(`${series} ${/mm$/i.test(f) ? f : `${f}mm`}`.trim());
  }
  return out.join("\n");
}

/** The text on one line (a summary, a "was"): sets joined by ' · '. */
export function oneLine(text) {
  return String(text || "").split("\n").map((line) => line.trim()).filter(Boolean).join(" · ");
}

/** The sets as the AI connector says them (`record`, `front`): the parts
 * only — the field's own text is beside them as `lenses`. */
export function lensSetsSaid(text) {
  return lensSetsShown(text).map(({ label, series, focals, stop, notes }) => ({ label, series, focals, stop, notes }));
}

/** A camera box with its lens sets beside the Lenses text, when it has any. */
export function withLensSets(camera) {
  if (!camera || typeof camera !== "object" || !String(camera.lenses || "").trim()) return camera;
  return { ...camera, lens_sets: lensSetsSaid(camera.lenses) };
}

/**
 * **A set broken into what a shot picks** (Ref 1627, 2026-10-08): the film's
 * lens list is lenses, not sets. "Cooke S4 — 18, 25, 32, 50mm" is 18mm, 25mm,
 * 32mm and 50mm; a zoom stays one entry with its name ("Angenieux 45-165mm"),
 * since its focal lengths are one lens; a set with no focal lengths at all
 * ("Signature Primes") is kept whole, because that is what the sheet says.
 * Case is ignored for doubles; the first spelling wins.
 */
export function focalWords(focal) {
  const s = String(focal || "").replace(/\s+/g, "").replace(/–/g, "-").replace(/mm$/i, "");
  return s ? `${s}mm` : "";
}

// Focal lengths left at the end of a set's name: "Cooke S4 primes 18/25/32/50",
// or "Zeiss 20.7," before a "25mm" the reader took. Two numbers at least.
const TRAIL_LIST = /\s((?:\d+(?:\.\d+)?\s*(?:mm)?\s*(?:,|\/|&)\s*)+(?:\d+(?:\.\d+)?\s*(?:mm)?)?)\s*$/i;

export function picksOfSet(set) {
  let series = String((set && set.series) || "").trim();
  let focals = (set && set.focals) || [];
  const tail = TRAIL_LIST.exec(series);
  if (tail && tail.index > 0 && (focals.length || /\d\s*(?:mm)?\s*(?:,|\/|&)\s*\d/i.test(tail[1]))) {
    focals = [...focalList(tail[1]), ...focals];
    series = series.slice(0, tail.index).trim();
  }
  if (!focals.length) return series ? [series] : [];
  return focals.map((focal) => {
    const words = focalWords(focal);
    if (!words) return "";
    return /\d-\d/.test(words) && series ? `${series} ${words}` : words;
  }).filter(Boolean);
}

/** The Lenses text as picks, in the sheet's order, each once. */
export function lensPicks(text) {
  const out = [];
  const seen = new Set();
  for (const set of lensSets(text)) {
    for (const pick of picksOfSet(set)) {
      const key = pick.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(pick);
    }
  }
  return out;
}

// ── writing (2026-10-10) — `lenses.format_set` and `lenses.write`, for the
// server answering the phone's lens-set edits itself.

/** A set as its line; an untouched set exactly as typed — `format_set`. */
export function formatSet(s) {
  if (s.raw && !s.edited) return String(s.raw).trim();
  let focals = s.focals || [];
  if (typeof focals === "string") focals = focalList(focals);
  const stop = String(s.stop == null ? "" : s.stop);
  const bits = [String(s.series == null ? "" : s.series).trim(),
    focals.map((f) => String(f).trim()).filter(Boolean).join(", "),
    STOP.test(stop.trim()) ? stopWords(stop) : stop.trim(),
    String(s.notes == null ? "" : s.notes).trim()];
  const line = bits.filter(Boolean).join(SEP);
  const label = String(s.label == null ? "" : s.label).replace(/:/g, " ").split(/\s+/).filter(Boolean).join(" ");
  if (label && line) return `${label}: ${line}`;
  return label || line;
}

/** Sets back to the Lenses field; empty sets dropped — `write`. */
export function writeSets(sets) {
  return (sets || []).filter((s) => s && typeof s === "object").map(formatSet).filter((l) => l.trim()).join("\n");
}
