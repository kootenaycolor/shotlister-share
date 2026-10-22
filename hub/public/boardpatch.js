// A board's changes, one at a time.
//
// **Why it exists.** His ask, 2026-09-25: "live collaboration features to the
// look board, so people can see changes in real time." A board used to be
// saved whole, and the last save won — so two people moving cards within a
// few seconds of each other meant one of them was quietly undone. Now a
// browser works out what it changed (this card moved, this note changed, this
// thread was tied) and sends only that; the portal applies it on top of the
// board as it stands, so both people keep their work.
//
// **Every change says what a thing now is, never what to do to it.** "Card
// x is at 40, 90", not "move card x by 10". So a change applied twice is the
// same as once, and a browser that is unsure whether the portal already has
// something may simply send it again — that is what makes catching up after a
// dropped line safe.
//
// One file, used by both halves: `board.js` in the browser, and the portal
// (`src/boardroom.js`, `src/boards.js`) for the MCP's writes.

/** Kept by the portal, never merged: when, who, the history clock, the format. */
const OWN = new Set(["at", "snap", "by", "v"]);
/** Card id → value. */
const MAPS = ["free", "obs", "cam", "text", "labels", "folded", "bare", "size"];
/** Lists of ids or thread keys that behave as sets. */
const SETS = ["cut", "gone"];

const same = (a, b) => a === b || JSON.stringify(a) === JSON.stringify(b);
const tieKey = (a, b) => [a, b].sort().join("~");
const obj = (v) => (v && typeof v === "object" && !Array.isArray(v) ? v : {});
const arr = (v) => (Array.isArray(v) ? v : []);
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

/**
 * What it takes to turn board `a` into board `b`, as a list of changes.
 * Cards somebody added are compared field by field, so one person moving a
 * card and another writing on it both stand.
 */
export function diffBoard(a, b) {
  a = obj(a); b = obj(b);
  const ops = [];
  for (const f of MAPS) {
    const x = obj(a[f]), y = obj(b[f]);
    for (const k of Object.keys(y)) if (!(k in x) || !same(x[k], y[k])) ops.push({ f, k, v: clone(y[k]) });
    for (const k of Object.keys(x)) if (!(k in y)) ops.push({ f, k, del: 1 });
  }
  // A sort's places: `vals[sort][card]`.
  const va = obj(a.vals), vb = obj(b.vals);
  for (const s of new Set([...Object.keys(va), ...Object.keys(vb)])) {
    const x = obj(va[s]), y = obj(vb[s]);
    for (const k of Object.keys(y)) if (!(k in x) || !same(x[k], y[k])) ops.push({ f: "vals", s, k, v: clone(y[k]) });
    for (const k of Object.keys(x)) if (!(k in y)) ops.push({ f: "vals", s, k, del: 1 });
  }
  // Cards somebody put on: a new one whole, a changed one by the fields that
  // changed, a removed one by its id.
  const ca = new Map(arr(a.added).filter((d) => d && d.id).map((d) => [d.id, d]));
  const cb = new Map(arr(b.added).filter((d) => d && d.id).map((d) => [d.id, d]));
  for (const [id, d] of cb) {
    const was = ca.get(id);
    if (!was) { ops.push({ f: "added", k: id, v: clone(d) }); continue; }
    for (const p of Object.keys(d)) if (p !== "id" && !same(was[p], d[p])) ops.push({ f: "added", k: id, p, v: clone(d[p]) });
    for (const p of Object.keys(was)) if (!(p in d)) ops.push({ f: "added", k: id, p, del: 1 });
  }
  for (const id of ca.keys()) if (!cb.has(id)) ops.push({ f: "added", k: id, del: 1 });
  // Threads somebody tied, by the pair of cards they join.
  const ta = new Map(arr(a.ties).filter((t) => t && t.a && t.b).map((t) => [tieKey(t.a, t.b), t]));
  const tb = new Map(arr(b.ties).filter((t) => t && t.a && t.b).map((t) => [tieKey(t.a, t.b), t]));
  for (const [k, t] of tb) if (!ta.has(k) || !same(ta.get(k), t)) ops.push({ f: "ties", k, v: clone(t) });
  for (const k of ta.keys()) if (!tb.has(k)) ops.push({ f: "ties", k, del: 1 });
  for (const f of SETS) {
    const x = new Set(arr(a[f])), y = new Set(arr(b[f]));
    for (const k of y) if (!x.has(k)) ops.push({ f, k, v: 1 });
    for (const k of x) if (!y.has(k)) ops.push({ f, k, del: 1 });
  }
  // Anything else on the board (its sorts among them) goes whole.
  const known = new Set([...MAPS, ...SETS, "vals", "added", "ties"]);
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (OWN.has(k) || known.has(k)) continue;
    if (!(k in b)) ops.push({ f: "top", k, del: 1 });
    else if (!same(a[k], b[k])) ops.push({ f: "top", k, v: clone(b[k]) });
  }
  return ops;
}

/**
 * Board `board` with `ops` applied, as a new board; `board` is left alone.
 * A change to a card that is no longer there is dropped — whoever took the
 * card off wins, and History still has it.
 */
export function applyOps(board, ops) {
  const out = clone(obj(board)) || {};
  for (const op of arr(ops)) {
    if (!op || typeof op.f !== "string") continue;
    const { f, k } = op;
    if (typeof k !== "string" && f !== "top") continue;
    if (MAPS.includes(f)) {
      const m = obj(out[f]);
      if (op.del) delete m[k]; else m[k] = clone(op.v);
      out[f] = m;
    } else if (f === "vals") {
      if (typeof op.s !== "string") continue;
      const all = obj(out.vals);
      const m = obj(all[op.s]);
      if (op.del) delete m[k]; else m[k] = clone(op.v);
      if (Object.keys(m).length) all[op.s] = m; else delete all[op.s];
      out.vals = all;
    } else if (f === "added") {
      const list = arr(out.added);
      const i = list.findIndex((d) => d && d.id === k);
      if (op.p === undefined) {
        if (op.del) { if (i >= 0) list.splice(i, 1); }
        else if (op.v && typeof op.v === "object") {
          const d = { ...clone(op.v), id: k };
          if (i >= 0) list[i] = d; else list.push(d);
        }
      } else if (i >= 0 && typeof op.p === "string" && op.p !== "id") {
        if (op.del) delete list[i][op.p]; else list[i][op.p] = clone(op.v);
      }
      out.added = list;
    } else if (f === "ties") {
      const list = arr(out.ties);
      const i = list.findIndex((t) => t && tieKey(t.a, t.b) === k);
      if (op.del) { if (i >= 0) list.splice(i, 1); }
      else if (op.v && op.v.a && op.v.b && tieKey(op.v.a, op.v.b) === k) {
        if (i >= 0) list[i] = clone(op.v); else list.push(clone(op.v));
      }
      out.ties = list;
    } else if (SETS.includes(f)) {
      const s = new Set(arr(out[f]));
      if (op.del) s.delete(k); else s.add(k);
      if (s.size || f === "cut") out[f] = [...s]; else delete out[f];
    } else if (f === "top") {
      if (typeof k !== "string" || OWN.has(k) || MAPS.includes(k) || SETS.includes(k) || ["vals", "added", "ties"].includes(k)) continue;
      if (op.del) delete out[k]; else out[k] = clone(op.v);
    }
  }
  return out;
}

/** A change list the portal will take: a list, of plain changes, not huge. */
export function opsProblem(ops) {
  if (!Array.isArray(ops)) return "That is not a list of changes.";
  if (ops.length > 20000) return "Too many changes at once.";
  for (const op of ops) if (!op || typeof op !== "object" || typeof op.f !== "string") return "That is not a change.";
  return "";
}
